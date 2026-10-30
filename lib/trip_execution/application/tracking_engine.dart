import 'dart:async';

import '../domain/model/tracking.dart';
import 'sync_service.dart';

enum TrackingPermission { granted, denied, serviceOff }

/// Origen de las lecturas GPS (el real usa `geolocator`; en pruebas, un fake).
abstract interface class PositionSource {
  /// Pide el permiso si hace falta y dice si se puede rastrear.
  Future<TrackingPermission> ensurePermission();

  /// Lecturas continuas. En Android corre como servicio en primer plano, así
  /// que sigue con la pantalla apagada o la app en segundo plano.
  Stream<GpsReading> readings();
}

enum TrackingStatus { starting, active, noPermission, serviceOff, stopped }

class TrackingState {
  const TrackingState({
    this.status = TrackingStatus.starting,
    this.lastSentAt,
    this.pending = 0,
    this.sent = 0,
  });

  final TrackingStatus status;

  /// Último envío que el servidor aceptó (hora local).
  final DateTime? lastSentAt;

  /// Lecturas guardadas esperando señal.
  final int pending;
  final int sent;

  bool get isRunning =>
      status == TrackingStatus.starting || status == TrackingStatus.active;

  TrackingState copyWith({
    TrackingStatus? status,
    DateTime? lastSentAt,
    int? pending,
    int? sent,
  }) =>
      TrackingState(
        status: status ?? this.status,
        lastSentAt: lastSentAt ?? this.lastSentAt,
        pending: pending ?? this.pending,
        sent: sent ?? this.sent,
      );
}

/// Recoge lecturas del GPS, descarta las ruidosas y las guarda; cada
/// [flushEvery] pide enviar lo guardado.
///
/// - En línea: una lectura cada ~4 s y un envío cada [flushEvery].
/// - Sin señal: las lecturas esperan en SQLite (sobreviven a que cierren la
///   app) y salen en orden al reconectar. El envío y sus reglas (lotes de 500,
///   429, 400) viven en [SyncService].
/// - `TRACKING_REQUIRES_ACTIVE_TRIP`: el viaje ya no está en curso, se
///   detiene de inmediato.
class TrackingEngine {
  TrackingEngine({
    required this.tripId,
    required this.sync,
    required this.source,
    required this.onChange,
    this.flushEvery = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String tripId;
  final SyncService sync;
  final PositionSource source;
  final void Function(TrackingState) onChange;
  final Duration flushEvery;
  final DateTime Function() _now;

  StreamSubscription<GpsReading>? _sub;
  Timer? _timer;
  bool _stopped = false;
  TrackingState _state = const TrackingState();

  TrackingState get state => _state;

  void _emit(TrackingState s) {
    _state = s;
    onChange(s);
  }

  Future<void> start() async {
    // Retoma lo que quedó guardado de un cierre anterior de la app.
    await sync.refreshCounts(tripId);
    final permission = await source.ensurePermission();
    if (_stopped) return;
    if (permission != TrackingPermission.granted) {
      _emit(_state.copyWith(
        status: permission == TrackingPermission.denied
            ? TrackingStatus.noPermission
            : TrackingStatus.serviceOff,
      ));
      return;
    }
    _sub = source.readings().listen(_onReading, onError: (_) {});
    _timer = Timer.periodic(flushEvery, (_) => flush());
    _emit(_state.copyWith(status: TrackingStatus.active, pending: sync.state.pendingReadings));
  }

  Future<void> _onReading(GpsReading r) async {
    if (_stopped || !r.isUsable(_now())) return;
    await sync.addReading(tripId, r);
    if (!_stopped) _emit(_state.copyWith(pending: sync.state.pendingReadings));
  }

  /// Envía lo guardado (también lo llama quien necesita vaciar el GPS).
  Future<void> flush() async {
    if (_stopped) return;
    final result = await sync.flushReadings(tripId);
    if (_stopped) return;
    switch (result) {
      case GpsFlushResult.tripNotActive:
        await stop();
      case GpsFlushResult.sent:
        _emit(_state.copyWith(lastSentAt: _now(), pending: sync.state.pendingReadings));
      case GpsFlushResult.nothing:
      case GpsFlushResult.offline:
      case GpsFlushResult.rateLimited:
        _emit(_state.copyWith(pending: sync.state.pendingReadings));
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    await _sub?.cancel();
    _emit(_state.copyWith(status: TrackingStatus.stopped));
  }
}
