import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/trip_execution/domain/model/queued_event.dart';
import 'package:rutasegura/trip_execution/infrastructure/offline_store.dart';
import 'package:rutasegura/trip_execution/infrastructure/sqlite_offline_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';

QueuedEvent _event(String id, {String trip = 't1', QueuedEventType type = QueuedEventType.boarding}) =>
    QueuedEvent(
      tripId: trip,
      clientEventId: id,
      type: type,
      occurredAt: DateTime.utc(2026, 10, 27, 11, 45, 3),
      studentId: 's1',
      latitude: -12.1,
      longitude: -77.0,
      incidentType: type == QueuedEventType.incident ? 'Accident' : null,
      detail: type == QueuedEventType.incident ? 'Choque' : null,
      notifyGuardians: type == QueuedEventType.incident ? true : null,
    );

void main() {
  sqfliteFfiInit();

  late SqliteOfflineStore store;
  setUp(() async {
    // Base en memoria: cada prueba parte limpia.
    store = await SqliteOfflineStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() => store.close());

  test('guarda y devuelve los eventos en orden, con todos sus campos', () async {
    await store.enqueueEvent(_event('e1'));
    await store.enqueueEvent(_event('e2', type: QueuedEventType.incident));

    final all = await store.pendingEvents('t1');

    expect(all.map((e) => e.clientEventId), ['e1', 'e2']);
    expect(all[0].seq! < all[1].seq!, isTrue);
    expect(all[0].type, QueuedEventType.boarding);
    expect(all[0].studentId, 's1');
    expect(all[0].latitude, -12.1);
    expect(all[0].occurredAt, DateTime.utc(2026, 10, 27, 11, 45, 3));
    expect(all[1].incidentType, 'Accident');
    expect(all[1].detail, 'Choque');
    expect(all[1].notifyGuardians, isTrue);
  });

  test('el mismo clientEventId no se guarda dos veces', () async {
    await store.enqueueEvent(_event('e1'));
    await store.enqueueEvent(_event('e1'));

    expect(await store.pendingEventCount('t1'), 1);
  });

  test('separa por viaje, respeta el límite y borra por id', () async {
    for (var i = 0; i < 5; i++) {
      await store.enqueueEvent(_event('a$i'));
    }
    await store.enqueueEvent(_event('b0', trip: 't2'));

    expect((await store.pendingEvents('t1', limit: 3)).map((e) => e.clientEventId), ['a0', 'a1', 'a2']);
    await store.removeEvents(['a0', 'a1']);
    expect(await store.pendingEventCount('t1'), 3);
    expect(await store.pendingEventCount('t2'), 1);
    await store.removeEvents(const []); // no falla
  });

  test('lecturas GPS: orden, límite, borrado y datos opcionales', () async {
    await store.addReading('t1', testReading(lat: -12.1));
    await store.addReading('t1', testReading(lat: -12.2, accuracy: 12));
    await store.addReading('t2', testReading(lat: -9));

    final rows = await store.readings('t1');
    expect(rows.map((r) => r.reading.latitude), [-12.1, -12.2]);
    expect(rows[1].reading.accuracyMeters, 12);
    expect(await store.pendingReadingCount('t1'), 2);

    await store.removeReadings([rows.first.seq]);
    expect((await store.readings('t1')).single.reading.latitude, -12.2);
    expect(await store.pendingReadingCount('t2'), 1);
  });

  test('descarta las lecturas más viejas al pasar el tope', () async {
    for (var i = 0; i < maxStoredReadings + 10; i++) {
      await store.addReading('t1', testReading(lat: -12.0 - i / 1e6));
    }

    expect(await store.pendingReadingCount('t1'), maxStoredReadings);
    // Se conservaron las más recientes.
    final first = (await store.readings('t1', limit: 1)).single.reading.latitude;
    expect(first, closeTo(-12.0 - 10 / 1e6, 1e-9));
  });

  test('clearReadings y clearTrip', () async {
    await store.enqueueEvent(_event('e1'));
    await store.addReading('t1', testReading());

    await store.clearReadings('t1');
    expect(await store.pendingReadingCount('t1'), 0);
    expect(await store.pendingEventCount('t1'), 1);

    await store.addReading('t1', testReading());
    await store.clearTrip('t1');
    expect(await store.pendingEventCount('t1'), 0);
    expect(await store.pendingReadingCount('t1'), 0);
  });
}
