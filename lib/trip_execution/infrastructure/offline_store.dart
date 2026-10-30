import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/model/queued_event.dart';
import '../domain/model/tracking.dart';

/// Lectura GPS guardada, con su posición en la cola.
class StoredReading {
  const StoredReading(this.seq, this.reading);
  final int seq;
  final GpsReading reading;
}

/// Lo que sobrevive sin red (y a que cierren la app): acciones del conductor
/// y lecturas GPS por enviar. Todo con el id del viaje.
abstract interface class OfflineStore {
  Future<void> enqueueEvent(QueuedEvent event);

  /// En orden de llegada; como máximo [limit].
  Future<List<QueuedEvent>> pendingEvents(String tripId, {int limit = maxEventsPerSync});
  Future<int> pendingEventCount(String tripId);
  Future<void> removeEvents(Iterable<String> clientEventIds);

  Future<void> addReading(String tripId, GpsReading reading);
  Future<List<StoredReading>> readings(String tripId, {int limit = 500});
  Future<int> pendingReadingCount(String tripId);
  Future<void> removeReadings(Iterable<int> seqs);
  Future<void> clearReadings(String tripId);

  /// Borra todo lo del viaje (terminó o ya no existe).
  Future<void> clearTrip(String tripId);
}

/// Tope de lecturas guardadas por viaje: si pasa, se tiran las más viejas.
const maxStoredReadings = 5000;

/// Para pruebas.
class InMemoryOfflineStore implements OfflineStore {
  final _events = <QueuedEvent>[];
  final _readings = <(int, String, GpsReading)>[];
  int _seq = 0;

  @override
  Future<void> enqueueEvent(QueuedEvent e) async {
    // El mismo clientEventId no se guarda dos veces.
    if (_events.any((x) => x.clientEventId == e.clientEventId)) return;
    _events.add(QueuedEvent(
      seq: ++_seq,
      tripId: e.tripId,
      clientEventId: e.clientEventId,
      type: e.type,
      occurredAt: e.occurredAt,
      studentId: e.studentId,
      latitude: e.latitude,
      longitude: e.longitude,
      incidentType: e.incidentType,
      detail: e.detail,
      notifyGuardians: e.notifyGuardians,
    ));
  }

  @override
  Future<List<QueuedEvent>> pendingEvents(String tripId, {int limit = maxEventsPerSync}) async =>
      [for (final e in _events) if (e.tripId == tripId) e].take(limit).toList();

  @override
  Future<int> pendingEventCount(String tripId) async =>
      _events.where((e) => e.tripId == tripId).length;

  @override
  Future<void> removeEvents(Iterable<String> ids) async {
    final set = ids.toSet();
    _events.removeWhere((e) => set.contains(e.clientEventId));
  }

  @override
  Future<void> addReading(String tripId, GpsReading r) async {
    _readings.add((++_seq, tripId, r));
    final mine = _readings.where((x) => x.$2 == tripId).toList();
    if (mine.length > maxStoredReadings) {
      _readings.removeWhere((x) => mine.take(mine.length - maxStoredReadings).contains(x));
    }
  }

  @override
  Future<List<StoredReading>> readings(String tripId, {int limit = 500}) async => [
        for (final x in _readings.where((x) => x.$2 == tripId).take(limit))
          StoredReading(x.$1, x.$3),
      ];

  @override
  Future<int> pendingReadingCount(String tripId) async =>
      _readings.where((x) => x.$2 == tripId).length;

  @override
  Future<void> removeReadings(Iterable<int> seqs) async {
    final set = seqs.toSet();
    _readings.removeWhere((x) => set.contains(x.$1));
  }

  @override
  Future<void> clearReadings(String tripId) async =>
      _readings.removeWhere((x) => x.$2 == tripId);

  @override
  Future<void> clearTrip(String tripId) async {
    _events.removeWhere((e) => e.tripId == tripId);
    _readings.removeWhere((x) => x.$2 == tripId);
  }
}

/// `main()` lo reemplaza por el almacén SQLite.
final offlineStoreProvider = Provider<OfflineStore>((ref) => InMemoryOfflineStore());
