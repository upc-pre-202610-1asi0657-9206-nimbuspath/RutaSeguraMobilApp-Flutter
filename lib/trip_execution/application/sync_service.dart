import 'dart:async';

import '../../core/network/api_error.dart';
import '../domain/model/queued_event.dart';
import '../domain/model/tracking.dart';
import '../infrastructure/offline_store.dart';
import '../infrastructure/trip_api.dart';

/// Un evento que el servidor no aceptó (se saca de la cola y se avisa).
class RejectedEvent {
  const RejectedEvent({required this.event, this.errorCode});

  final QueuedEvent event;
  final String? errorCode;
}

class SyncState {
  const SyncState({this.pendingEvents = 0, this.pendingReadings = 0, this.rejected = const []});

  /// Acciones del conductor sin confirmar.
  final int pendingEvents;

  /// Lecturas GPS sin enviar.
  final int pendingReadings;

  /// Rechazos nuevos desde la última vez que la UI los mostró.
  final List<RejectedEvent> rejected;

  SyncState copyWith({int? pendingEvents, int? pendingReadings, List<RejectedEvent>? rejected}) =>
      SyncState(
        pendingEvents: pendingEvents ?? this.pendingEvents,
        pendingReadings: pendingReadings ?? this.pendingReadings,
        rejected: rejected ?? this.rejected,
      );
}

enum GpsFlushResult { nothing, sent, offline, rateLimited, tripNotActive }

/// Resultado de [SyncService.syncTrip].
class SyncReport {
  const SyncReport({required this.pendingEvents, required this.offline});

  /// Acciones que siguen sin enviarse.
  final int pendingEvents;

  /// No se pudo hablar con el servidor.
  final bool offline;

  bool get allSent => pendingEvents == 0;
}

/// Lo que se guardó sin red y hay que mandar cuando vuelve.
///
/// Orden al reconectar (§7.4): 1) GPS pendiente en lotes, 2) `/sync`,
/// 3) refrescar `/live` (lo hace quien llama).
///
/// Las operaciones se ejecutan de a una: así un envío no se pisa con otro.
class SyncService {
  SyncService({
    required this.store,
    required this.api,
    required this.onChange,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final OfflineStore store;
  final TripApi api;
  final void Function(SyncState) onChange;
  final DateTime Function() _now;

  SyncState _state = const SyncState();
  SyncState get state => _state;

  Future<void> _tail = Future.value();
  DateTime? _gpsPausedUntil;

  Future<T> _exclusive<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _emit(SyncState s) {
    _state = s;
    onChange(s);
  }

  Future<void> refreshCounts(String tripId) async => _emit(_state.copyWith(
        pendingEvents: await store.pendingEventCount(tripId),
        pendingReadings: await store.pendingReadingCount(tripId),
      ));

  /// La UI ya mostró los rechazos.
  void ackRejections() => _emit(_state.copyWith(rejected: const []));

  // ---------- acciones ----------

  Future<void> enqueue(QueuedEvent event) async {
    await store.enqueueEvent(event);
    await refreshCounts(event.tripId);
  }

  /// El evento ya llegó por su endpoint directo: ya no hace falta guardarlo.
  Future<void> dequeue(String tripId, String clientEventId) async {
    await store.removeEvents([clientEventId]);
    await refreshCounts(tripId);
  }

  // ---------- GPS ----------

  Future<void> addReading(String tripId, GpsReading reading) async {
    await store.addReading(tripId, reading);
    _emit(_state.copyWith(pendingReadings: await store.pendingReadingCount(tripId)));
  }

  /// Envía las lecturas guardadas, en orden y en lotes de
  /// [maxReadingsPerBatch].
  Future<GpsFlushResult> flushReadings(String tripId) => _exclusive(() async {
        final pause = _gpsPausedUntil;
        if (pause != null && _now().isBefore(pause)) return GpsFlushResult.rateLimited;
        var result = GpsFlushResult.nothing;
        try {
          while (true) {
            final rows = await store.readings(tripId, limit: maxReadingsPerBatch);
            if (rows.isEmpty) break;
            try {
              await api.recordPositions(tripId, [for (final r in rows) r.reading]);
              await store.removeReadings(rows.map((r) => r.seq));
              result = GpsFlushResult.sent;
            } on ApiError catch (e) {
              if (e.code == ApiErrorCodes.trackingRequiresActiveTrip) {
                // Solo se comparte ubicación con el viaje en curso: lo
                // guardado ya no sirve.
                await store.clearReadings(tripId);
                return GpsFlushResult.tripNotActive;
              }
              if (e.status == 400) {
                // Lote inválido (bug del cliente): reintentar igual no sirve.
                await store.removeReadings(rows.map((r) => r.seq));
                continue;
              }
              if (e.status == 429) {
                _gpsPausedUntil = _now().add(e.retryAfter ?? const Duration(seconds: 8));
                return GpsFlushResult.rateLimited;
              }
              return GpsFlushResult.offline;
            }
          }
          return result;
        } finally {
          await refreshCounts(tripId);
        }
      });

  // ---------- acciones guardadas ----------

  /// GPS pendiente primero y después las acciones por `/sync`.
  Future<SyncReport> syncTrip(String tripId) async {
    await flushReadings(tripId);
    return _exclusive(() async {
      var offline = false;
      final rejected = <RejectedEvent>[];
      try {
        while (true) {
          final batch = await store.pendingEvents(tripId, limit: maxEventsPerSync);
          if (batch.isEmpty) break;
          List<SyncOutcome> outcomes;
          try {
            outcomes = await api.sync(tripId, batch);
          } on ApiError catch (e) {
            if (e.isUnauthorized || e.isRetryable) {
              // Sin sesión o sin red: la cola se conserva tal cual.
              offline = true;
              break;
            }
            // El servidor rechaza el lote entero (400/403/404/422): reenviarlo
            // igual no sirve y bloquearía lo demás.
            await store.removeEvents(batch.map((b) => b.clientEventId));
            rejected.addAll([for (final b in batch) RejectedEvent(event: b, errorCode: e.code)]);
            continue;
          }
          final byId = {for (final o in outcomes) o.clientEventId: o};
          final done = <String>[];
          for (final e in batch) {
            final o = byId[e.clientEventId];
            if (o == null) continue; // el servidor no lo mencionó: se reintenta
            done.add(e.clientEventId);
            // Applied y Duplicate salen de la cola; Rejected también, con aviso.
            if (o.status == SyncStatus.rejected) {
              rejected.add(RejectedEvent(event: e, errorCode: o.errorCode));
            }
          }
          await store.removeEvents(done);
          if (done.isEmpty) break;
        }
      } finally {
        final pending = await store.pendingEventCount(tripId);
        _emit(SyncState(
          pendingEvents: pending,
          pendingReadings: await store.pendingReadingCount(tripId),
          rejected: [..._state.rejected, ...rejected],
        ));
      }
      return SyncReport(pendingEvents: _state.pendingEvents, offline: offline);
    });
  }

  /// Al terminar el viaje no queda nada que guardar.
  Future<void> clearTrip(String tripId) async {
    await store.clearTrip(tripId);
    await refreshCounts(tripId);
  }
}
