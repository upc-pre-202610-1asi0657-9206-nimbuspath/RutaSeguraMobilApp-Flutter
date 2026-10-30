import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/model/queued_event.dart';
import '../domain/model/tracking.dart';
import 'offline_store.dart';

/// [OfflineStore] sobre SQLite (sobrevive a que se cierre la app).
class SqliteOfflineStore implements OfflineStore {
  SqliteOfflineStore._(this._db);

  final Database _db;

  /// Abre (o crea) la base. [path] permite usar otra ubicación en pruebas;
  /// [factory] otra implementación de sqflite (FFI en el escritorio).
  static Future<SqliteOfflineStore> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final file = path ?? p.join(await f.getDatabasesPath(), 'rutasegura_offline.db');
    final db = await f.openDatabase(
      file,
      options: OpenDatabaseOptions(version: 1, onCreate: _create),
    );
    return SqliteOfflineStore._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE queue_events (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL,
        client_event_id TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        payload TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_events_trip ON queue_events(trip_id, seq)');
    await db.execute('''
      CREATE TABLE gps_readings (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        recorded_at TEXT NOT NULL,
        accuracy REAL,
        speed_kmh REAL,
        heading REAL
      )''');
    await db.execute('CREATE INDEX idx_gps_trip ON gps_readings(trip_id, seq)');
  }

  Future<void> close() => _db.close();

  @override
  Future<void> enqueueEvent(QueuedEvent e) => _db.insert(
        'queue_events',
        e.toRow(),
        // Mismo clientEventId: no se duplica.
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  @override
  Future<List<QueuedEvent>> pendingEvents(String tripId, {int limit = maxEventsPerSync}) async {
    final rows = await _db.query(
      'queue_events',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'seq',
      limit: limit,
    );
    return [for (final r in rows) QueuedEvent.fromRow(r)];
  }

  @override
  Future<int> pendingEventCount(String tripId) async => Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM queue_events WHERE trip_id = ?', [tripId]),
      )!;

  @override
  Future<void> removeEvents(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _db.delete(
      'queue_events',
      where: 'client_event_id IN (${List.filled(list.length, '?').join(',')})',
      whereArgs: list,
    );
  }

  @override
  Future<void> addReading(String tripId, GpsReading r) async {
    await _db.insert('gps_readings', {
      'trip_id': tripId,
      'latitude': r.latitude,
      'longitude': r.longitude,
      'recorded_at': r.recordedAt.toUtc().toIso8601String(),
      'accuracy': r.accuracyMeters,
      'speed_kmh': r.speedKmh,
      'heading': r.headingDegrees,
    });
    // Tope: se descartan las más viejas.
    await _db.rawDelete(
      'DELETE FROM gps_readings WHERE trip_id = ? AND seq <= '
      '(SELECT MAX(seq) FROM gps_readings WHERE trip_id = ?) - ?',
      [tripId, tripId, maxStoredReadings],
    );
  }

  @override
  Future<List<StoredReading>> readings(String tripId, {int limit = 500}) async {
    final rows = await _db.query(
      'gps_readings',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'seq',
      limit: limit,
    );
    return [
      for (final r in rows)
        StoredReading(
          r['seq'] as int,
          GpsReading(
            latitude: (r['latitude'] as num).toDouble(),
            longitude: (r['longitude'] as num).toDouble(),
            recordedAt: DateTime.parse(r['recorded_at'] as String),
            accuracyMeters: (r['accuracy'] as num?)?.toDouble(),
            speedKmh: (r['speed_kmh'] as num?)?.toDouble(),
            headingDegrees: (r['heading'] as num?)?.toDouble(),
          ),
        ),
    ];
  }

  @override
  Future<int> pendingReadingCount(String tripId) async => Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM gps_readings WHERE trip_id = ?', [tripId]),
      )!;

  @override
  Future<void> removeReadings(Iterable<int> seqs) async {
    final list = seqs.toList();
    if (list.isEmpty) return;
    await _db.delete(
      'gps_readings',
      where: 'seq IN (${List.filled(list.length, '?').join(',')})',
      whereArgs: list,
    );
  }

  @override
  Future<void> clearReadings(String tripId) =>
      _db.delete('gps_readings', where: 'trip_id = ?', whereArgs: [tripId]);

  @override
  Future<void> clearTrip(String tripId) async {
    await _db.delete('queue_events', where: 'trip_id = ?', whereArgs: [tripId]);
    await _db.delete('gps_readings', where: 'trip_id = ?', whereArgs: [tripId]);
  }
}
