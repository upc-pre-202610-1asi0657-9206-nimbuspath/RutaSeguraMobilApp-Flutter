import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_error.dart';
import '../domain/model/trip_live.dart';
import '../domain/model/trip_models.dart';
import '../infrastructure/trip_api.dart';
import 'tracking_controller.dart';

/// Última posición conocida del teléfono, para acompañar cada registro.
/// Nunca falla: sin GPS devuelve `null` (el backend lo permite).
typedef PositionReader = Future<GeoPoint?> Function();

final positionReaderProvider = Provider<PositionReader>((ref) => () async {
      try {
        final p = await Geolocator.getLastKnownPosition();
        return p == null ? null : (latitude: p.latitude, longitude: p.longitude);
      } catch (_) {
        return null;
      }
    });

/// Cada cuánto se refresca `/live` mientras la pantalla está abierta.
const liveRefreshEvery = Duration(seconds: 20);

const _uuid = Uuid();

/// Viaje en curso: inicia el viaje (si hace falta), mantiene `/live` al día y
/// aplica los registros de abordaje con UI optimista.
///
/// Cada toque genera su `clientEventId` en ese instante, de modo que un
/// reintento reenvía exactamente la misma petición.
class TripController extends AsyncNotifier<TripLive> {
  TripController(this.trip);

  final ScheduledTrip trip;

  // Se conserva entre reintentos de "Iniciar".
  final String _startEventId = _uuid.v4();
  int _inFlight = 0;

  TripApi get _api => ref.read(tripApiProvider);

  @override
  Future<TripLive> build() {
    final timer = Timer.periodic(liveRefreshEvery, (_) => refresh());
    ref.onDispose(timer.cancel);
    return _startAndLoad();
  }

  Future<TripLive> _startAndLoad() async {
    if (!trip.isInProgress) {
      await _api.start(trip.id, clientEventId: _startEventId);
    }
    return _api.live(trip.id);
  }

  /// "Reintentar" tras un error al iniciar o cargar (mismo `clientEventId`).
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_startAndLoad);
  }

  /// Vuelve a pedir `/live` sin mostrar carga. Si falla, se conserva lo último.
  Future<void> refresh() async {
    if (_inFlight > 0 || !state.hasValue) return;
    try {
      final live = await _api.live(trip.id);
      if (_inFlight == 0) state = AsyncData(live);
    } on ApiError {
      // Sin señal: se queda con el último estado.
    }
  }

  /// "Subió" / "Bajó" / "No vino". Devuelve el error si la API lo rechazó
  /// (la fila vuelve a su estado anterior).
  Future<ApiError?> record(PassengerAction action, String studentId) async {
    final before = state.value;
    if (before == null) return null;
    final eventId = _uuid.v4();
    final at = DateTime.now();
    final position = await ref.read(positionReaderProvider)();

    _apply(before, studentId, (p) => switch (action) {
          PassengerAction.board =>
            p.copyWith(status: PassengerStatus.boarded, boardedAt: at),
          PassengerAction.alight =>
            p.copyWith(status: PassengerStatus.alighted, alightedAt: at),
          PassengerAction.absent =>
            p.copyWith(status: PassengerStatus.absent, absenceSource: 'Driver'),
        });

    return _send(before, () => _api.recordPassenger(
          trip.id,
          action,
          studentId: studentId,
          clientEventId: eventId,
          occurredAt: at,
          position: position,
        ));
  }

  /// "Deshacer": revierte el último "Subió" o "No vino" del alumno.
  Future<ApiError?> undo(String studentId) async {
    final before = state.value;
    if (before == null) return null;
    final eventId = _uuid.v4();
    _apply(before, studentId, (p) => p.copyWith(
          status: PassengerStatus.pending,
          clearTimes: true,
        ));
    return _send(before, () => _api.undoPassenger(
          trip.id,
          studentId: studentId,
          clientEventId: eventId,
        ));
  }

  /// Reporta un incidente (el evento se genera al tocar "Enviar").
  /// Devuelve el error si el backend lo rechazó.
  Future<ApiError?> reportIncident({
    required IncidentType type,
    required bool notifyGuardians,
    String? detail,
  }) async {
    final eventId = _uuid.v4();
    final at = DateTime.now();
    final position = await ref.read(positionReaderProvider)();
    _inFlight++;
    try {
      await _api.reportIncident(
        trip.id,
        type: type,
        clientEventId: eventId,
        occurredAt: at,
        notifyGuardians: notifyGuardians,
        detail: detail,
        position: position,
      );
      return null;
    } on ApiError catch (e) {
      return e;
    } finally {
      _inFlight--;
      unawaited(refresh()); // algunos incidentes pasan el viaje a "Con retraso"
    }
  }

  /// Envía el SOS con el [eventId] que se generó al terminar la cuenta
  /// regresiva; reintentar con el mismo id es seguro.
  Future<ApiError?> sendSos(String eventId, DateTime occurredAt) async {
    final position = await ref.read(positionReaderProvider)();
    try {
      await _api.raiseSos(
        trip.id,
        clientEventId: eventId,
        occurredAt: occurredAt,
        position: position,
      );
      unawaited(refresh());
      return null;
    } on ApiError catch (e) {
      return e;
    }
  }

  /// Finaliza el viaje (`/complete`). Antes envía el GPS pendiente.
  /// [eventId] se conserva entre reintentos.
  Future<ApiError?> complete(String eventId) async {
    try {
      final tracking = trackingControllerProvider(trip.id);
      // Solo si el GPS está en marcha: no se arranca solo para vaciarlo.
      if (ref.exists(tracking)) await ref.read(tracking.notifier).flush();
      await _api.complete(trip.id, clientEventId: eventId);
      return null;
    } on ApiError catch (e) {
      // Lo más probable es que el estado local esté desactualizado.
      unawaited(refresh());
      return e;
    }
  }

  /// Resumen del viaje ya finalizado; `null` si no se pudo leer.
  Future<TripSummaryData?> loadSummary() async {
    try {
      return await _api.summary(trip.id);
    } on ApiError {
      return null;
    }
  }

  void _apply(
    TripLive live,
    String studentId,
    LivePassenger Function(LivePassenger) change,
  ) {
    state = AsyncData(live.withPassengers([
      for (final p in live.passengers)
        p.studentId == studentId ? change(p) : p,
    ]));
  }

  Future<ApiError?> _send(TripLive before, Future<void> Function() call) async {
    _inFlight++;
    try {
      await call();
      return null;
    } on ApiError catch (e) {
      state = AsyncData(before);
      return e;
    } finally {
      _inFlight--;
      // La respuesta del servidor es la fuente de verdad (siguiente parada,
      // contadores...).
      unawaited(refresh());
    }
  }
}

/// Sin reintento automático de Riverpod: el inicio del viaje se reintenta a
/// mano con [TripController.retry] (mismo `clientEventId`).
Duration? _noRetry(int retryCount, Object error) => null;

final tripControllerProvider = AsyncNotifierProvider.autoDispose
    .family<TripController, TripLive, ScheduledTrip>(
  TripController.new,
  retry: _noRetry,
);
