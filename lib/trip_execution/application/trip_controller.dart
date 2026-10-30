import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_error.dart';
import '../../core/network/connectivity.dart';
import '../../core/storage/local_cache.dart';
import '../domain/model/queued_event.dart';
import '../domain/model/trip_live.dart';
import '../domain/model/trip_models.dart';
import '../infrastructure/offline_store.dart';
import '../infrastructure/trip_api.dart';
import 'sync_controller.dart';
import 'sync_service.dart';

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

/// Cada cuánto se refresca `/live` (y se manda lo guardado sin red) mientras
/// la pantalla está abierta.
const liveRefreshEvery = Duration(seconds: 20);

const _uuid = Uuid();

/// Qué pasó con una acción del conductor.
///
/// - [sent]: el servidor la confirmó.
/// - [queued]: no había señal; quedó guardada y se enviará por `/sync` con el
///   mismo `clientEventId`. La pantalla la muestra como hecha.
/// - [failed]: el servidor la rechazó (regla de negocio): no se guardó.
class ActionResult {
  const ActionResult.sent() : error = null, queued = false;
  const ActionResult.queued() : error = null, queued = true;
  const ActionResult.failed(ApiError this.error) : queued = false;

  final ApiError? error;
  final bool queued;
  bool get isFailure => error != null;
}

/// Viaje en curso: inicia el viaje (si hace falta), mantiene `/live` al día y
/// aplica los registros de abordaje con UI optimista.
///
/// Cada toque genera su `clientEventId` en ese instante, de modo que un
/// reintento (directo o por `/sync`) reenvía exactamente la misma petición.
/// Sin señal las acciones se guardan en [OfflineStore] y se superponen al
/// estado que devuelve el servidor hasta que se confirman.
class TripController extends AsyncNotifier<TripLive> {
  TripController(this.trip);

  final ScheduledTrip trip;

  // Se conserva entre reintentos de "Iniciar".
  final String _startEventId = _uuid.v4();
  int _inFlight = 0;

  // Se toman al construir: las operaciones en vuelo pueden terminar después
  // de que la pantalla se cierre y el provider se libere, y entonces ya no se
  // puede usar `ref`.
  late TripApi _api;
  late SyncService _sync;
  late OfflineStore _store;
  late LocalCache _cache;
  late PositionReader _readPosition;
  String get _liveKey => 'live.${trip.id}';

  @override
  Future<TripLive> build() {
    _api = ref.read(tripApiProvider);
    _sync = ref.read(syncControllerProvider.notifier).service;
    _store = ref.read(offlineStoreProvider);
    _cache = ref.read(localCacheProvider);
    _readPosition = ref.read(positionReaderProvider);
    final timer = Timer.periodic(liveRefreshEvery, (_) => refresh());
    ref.onDispose(timer.cancel);
    // Al volver la conexión se manda lo guardado sin esperar al ciclo.
    ref.listen(connectivityRestoredProvider, (_, next) {
      if (next.value == true) refresh();
    });
    return _startAndLoad();
  }

  bool _looksOffline(ApiError e) =>
      e.kind == ApiErrorKind.network ||
      e.kind == ApiErrorKind.timeout ||
      (e.status ?? 0) >= 500;

  Future<TripLive> _startAndLoad() async {
    if (!trip.isInProgress) {
      try {
        await _api.start(trip.id, clientEventId: _startEventId);
      } on ApiError catch (e) {
        // Sin red pero el viaje ya había empezado (la agenda guardada no lo
        // sabía): se sigue con el último estado guardado.
        if (!(_looksOffline(e) && _readCachedLive() != null)) rethrow;
      }
    }
    final live = await _loadLive();
    await _sync.refreshCounts(trip.id);
    return live;
  }

  /// `/live` y, sin señal, el último estado guardado. Siempre con lo
  /// pendiente de enviar superpuesto.
  Future<TripLive> _loadLive() async {
    TripLive live;
    try {
      live = await _api.live(trip.id);
      unawaited(_cache.write(_liveKey, jsonEncode(live.toJson())));
    } on ApiError catch (e) {
      final cached = _readCachedLive();
      if (_looksOffline(e) && cached != null) return _overlay(cached);
      rethrow;
    }
    return _overlay(live);
  }

  TripLive? _readCachedLive() {
    final raw = _cache.read(_liveKey);
    if (raw == null) return null;
    try {
      return TripLive.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Aplica sobre [live] las acciones que el servidor aún no confirmó, para
  /// que la lista no "retroceda" mientras llegan.
  Future<TripLive> _overlay(TripLive live) async {
    final pending = await _store.pendingEvents(trip.id);
    final changes = [for (final e in pending) if (e.type.isPassengerChange) e];
    if (changes.isEmpty) return live;
    var passengers = live.passengers;
    for (final e in changes) {
      passengers = [
        for (final p in passengers)
          p.studentId != e.studentId
              ? p
              : switch (e.type) {
                  QueuedEventType.boarding =>
                    p.copyWith(status: PassengerStatus.boarded, boardedAt: e.occurredAt),
                  QueuedEventType.alighting =>
                    p.copyWith(status: PassengerStatus.alighted, alightedAt: e.occurredAt),
                  QueuedEventType.absent =>
                    p.copyWith(status: PassengerStatus.absent, absenceSource: 'Driver'),
                  _ => p.copyWith(status: PassengerStatus.pending, clearTimes: true),
                },
      ];
    }
    return live.withPassengers(passengers);
  }

  /// "Reintentar" tras un error al iniciar o cargar (mismo `clientEventId`).
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_startAndLoad);
  }

  /// Manda lo guardado sin red (GPS, luego acciones) y vuelve a pedir `/live`
  /// sin mostrar carga. Si falla, se conserva lo último.
  Future<void> refresh() async {
    if (_inFlight > 0 || !ref.mounted || !state.hasValue) return;
    try {
      await _sync.syncTrip(trip.id);
      final live = await _api.live(trip.id);
      if (!ref.mounted) return;
      unawaited(_cache.write(_liveKey, jsonEncode(live.toJson())));
      final shown = await _overlay(live);
      if (_inFlight == 0 && ref.mounted) state = AsyncData(shown);
    } on ApiError {
      // Sin señal: se queda con el último estado.
    }
  }

  QueuedEvent _event(
    QueuedEventType type,
    String eventId,
    DateTime at, {
    String? studentId,
    GeoPoint? position,
    IncidentType? incident,
    String? detail,
    bool? notify,
  }) =>
      QueuedEvent(
        tripId: trip.id,
        clientEventId: eventId,
        type: type,
        occurredAt: at,
        studentId: studentId,
        latitude: position?.latitude,
        longitude: position?.longitude,
        incidentType: incident?.apiName,
        detail: detail,
        notifyGuardians: notify,
      );

  /// "Subió" / "Bajó" / "No vino".
  Future<ActionResult> record(PassengerAction action, String studentId) async {
    final before = state.value;
    if (before == null) return const ActionResult.sent();
    final eventId = _uuid.v4();
    final at = DateTime.now();
    final position = await _readPosition();

    _apply(before, studentId, (p) => switch (action) {
          PassengerAction.board => p.copyWith(status: PassengerStatus.boarded, boardedAt: at),
          PassengerAction.alight => p.copyWith(status: PassengerStatus.alighted, alightedAt: at),
          PassengerAction.absent =>
            p.copyWith(status: PassengerStatus.absent, absenceSource: 'Driver'),
        });

    final type = switch (action) {
      PassengerAction.board => QueuedEventType.boarding,
      PassengerAction.alight => QueuedEventType.alighting,
      PassengerAction.absent => QueuedEventType.absent,
    };
    return _send(
      before,
      _event(type, eventId, at, studentId: studentId, position: position),
      () => _api.recordPassenger(
        trip.id,
        action,
        studentId: studentId,
        clientEventId: eventId,
        occurredAt: at,
        position: position,
      ),
    );
  }

  /// "Deshacer": revierte el último "Subió" o "No vino" del alumno.
  Future<ActionResult> undo(String studentId) async {
    final before = state.value;
    if (before == null) return const ActionResult.sent();
    final eventId = _uuid.v4();
    final at = DateTime.now();
    _apply(before, studentId, (p) => p.copyWith(status: PassengerStatus.pending, clearTimes: true));
    return _send(
      before,
      _event(QueuedEventType.undo, eventId, at, studentId: studentId),
      () => _api.undoPassenger(trip.id, studentId: studentId, clientEventId: eventId),
    );
  }

  /// Reporta un incidente (el evento se genera al tocar "Enviar"). Sin señal
  /// queda guardado y se envía al reconectar.
  Future<ActionResult> reportIncident({
    required IncidentType type,
    required bool notifyGuardians,
    String? detail,
  }) async {
    final eventId = _uuid.v4();
    final at = DateTime.now();
    final position = await _readPosition();
    return _send(
      null,
      _event(
        QueuedEventType.incident,
        eventId,
        at,
        position: position,
        incident: type,
        detail: detail,
        notify: notifyGuardians,
      ),
      () => _api.reportIncident(
        trip.id,
        type: type,
        clientEventId: eventId,
        occurredAt: at,
        notifyGuardians: notifyGuardians,
        detail: detail,
        position: position,
      ),
    );
  }

  /// Envía el SOS con el [eventId] que se generó al terminar la cuenta
  /// regresiva; reintentar con el mismo id es seguro. Si llega, se saca de la
  /// cola (por si ya se había guardado).
  Future<ApiError?> sendSos(String eventId, DateTime occurredAt) async {
    final position = await _readPosition();
    try {
      await _api.raiseSos(
        trip.id,
        clientEventId: eventId,
        occurredAt: occurredAt,
        position: position,
      );
      await _sync.dequeue(trip.id, eventId);
      unawaited(refresh());
      return null;
    } on ApiError catch (e) {
      return e;
    }
  }

  /// El SOS no pudo salir: se guarda para que `/sync` lo mande en cuanto haya
  /// señal, aunque el conductor salga de la pantalla.
  Future<void> queueSos(String eventId, DateTime occurredAt) async {
    final position = await _readPosition();
    await _sync.enqueue(_event(QueuedEventType.sos, eventId, occurredAt, position: position));
  }

  /// Finaliza el viaje (`/complete`). Antes manda el GPS y las acciones
  /// guardadas: no se finaliza con registros sin enviar. [eventId] se conserva
  /// entre reintentos.
  Future<ApiError?> complete(String eventId) async {
    try {
      final report = await _sync.syncTrip(trip.id);
      if (!report.allSent) {
        // Quedan registros sin confirmar (casi siempre, sin señal).
        return const ApiError(kind: ApiErrorKind.network);
      }
      await _api.complete(trip.id, clientEventId: eventId);
      await _sync.clearTrip(trip.id);
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
    if (!ref.mounted) return;
    state = AsyncData(live.withPassengers([
      for (final p in live.passengers)
        p.studentId == studentId ? change(p) : p,
    ]));
  }

  /// Manda la acción por su endpoint. Si no hay señal (red, 5xx, 409, 429) la
  /// guarda con el mismo `clientEventId`; si el servidor la rechaza por una
  /// regla de negocio, [before] (si lo hay) restaura la pantalla.
  Future<ActionResult> _send(
    TripLive? before,
    QueuedEvent event,
    Future<void> Function() call,
  ) async {
    _inFlight++;
    try {
      await call();
      return const ActionResult.sent();
    } on ApiError catch (e) {
      if (e.isRetryable) {
        await _sync.enqueue(event);
        return const ActionResult.queued();
      }
      if (before != null && ref.mounted) state = AsyncData(before);
      return ActionResult.failed(e);
    } finally {
      _inFlight--;
      // La respuesta del servidor es la fuente de verdad (siguiente parada,
      // contadores, "Con retraso"...), con lo pendiente superpuesto.
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
