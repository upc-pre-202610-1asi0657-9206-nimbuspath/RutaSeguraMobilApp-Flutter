import 'dart:async';

import '../../core/network/api_error.dart';
import '../domain/model/tracking.dart';
import '../infrastructure/trip_api.dart';

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

/// Recoge lecturas del GPS, descarta las ruidosas y las envía en lotes.
///
/// - En línea: una lectura cada ~4 s y un envío cada [flushEvery].
/// - Sin señal (red, 5xx, 429): las lecturas esperan en memoria y salen en
///   orden al reconectar. (La Etapa 7 las persistirá en disco.)
/// - `TRACKING_REQUIRES_ACTIVE_TRIP`: el viaje ya no está en curso, se
///   detiene de inmediato.
class TrackingEngine {
  TrackingEngine({
    required this.tripId,
    required this.api,
    required this.source,
    required this.onChange,
    this.flushEvery = const Duration(seconds: 8),
    this.maxBuffered = 5000,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String tripId;
  final TripApi api;
  final PositionSource source;
  final void Function(TrackingState) onChange;
  final Duration flushEvery;
  final int maxBuffered;
  final DateTime Function() _now;

  final _buffer = <GpsReading>[];
  StreamSubscription<GpsReading>? _sub;
  Timer? _timer;
  bool _flushing = false;
  bool _stopped = false;
  DateTime? _pausedUntil;
  TrackingState _state = const TrackingState();

  TrackingState get state => _state;
  int get pending => _buffer.length;

  void _emit(TrackingState s) {
    _state = s;
    onChange(s);
  }

  Future<void> start() async {
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
    _emit(_state.copyWith(status: TrackingStatus.active));
  }

  void _onReading(GpsReading r) {
    if (_stopped || !r.isUsable(_now())) return;
    _buffer.add(r);
    if (_buffer.length > maxBuffered) {
      _buffer.removeRange(0, _buffer.length - maxBuffered);
    }
    _emit(_state.copyWith(pending: _buffer.length));
  }

  /// Envía lo pendiente, en orden y en lotes de [maxReadingsPerBatch].
  Future<void> flush() async {
    if (_flushing || _buffer.isEmpty) return;
    final pause = _pausedUntil;
    if (pause != null && _now().isBefore(pause)) return;
    _flushing = true;
    try {
      while (_buffer.isNotEmpty && !_stopped) {
        final n = _buffer.length < maxReadingsPerBatch
            ? _buffer.length
            : maxReadingsPerBatch;
        final batch = List<GpsReading>.of(_buffer.take(n));
        await api.recordPositions(tripId, batch);
        // Lo que llegó durante el envío queda detrás: se borra solo lo enviado.
        _buffer.removeRange(0, n);
        _emit(_state.copyWith(
          lastSentAt: _now(),
          pending: _buffer.length,
          sent: _state.sent + n,
        ));
      }
    } on ApiError catch (e) {
      if (e.code == ApiErrorCodes.trackingRequiresActiveTrip) {
        await stop();
      } else if (e.status == 400) {
        // Bug del cliente (p. ej. lote inválido): reintentar igual no sirve.
        _buffer.clear();
        _emit(_state.copyWith(pending: 0));
      } else if (e.status == 429) {
        _pausedUntil = _now().add(e.retryAfter ?? flushEvery);
      }
      // Red, 5xx y demás: se conservan las lecturas y se reintenta en el
      // siguiente ciclo.
    } finally {
      _flushing = false;
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
