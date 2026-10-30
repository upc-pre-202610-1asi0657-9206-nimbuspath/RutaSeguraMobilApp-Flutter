import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/trip_execution/application/sync_service.dart';
import 'package:rutasegura/trip_execution/domain/model/queued_event.dart';
import 'package:rutasegura/trip_execution/domain/model/tracking.dart';
import 'package:rutasegura/trip_execution/infrastructure/offline_store.dart';

import '../support/fakes.dart';

const _offline = ApiError(kind: ApiErrorKind.network);

QueuedEvent _event(
  String id, {
  QueuedEventType type = QueuedEventType.boarding,
  String student = 's1',
  String trip = 't1',
}) =>
    QueuedEvent(
      tripId: trip,
      clientEventId: id,
      type: type,
      occurredAt: DateTime.utc(2026, 10, 27, 11, 45),
      studentId: student,
      latitude: -12.1,
      longitude: -77.0,
    );

(SyncService, InMemoryOfflineStore, FakeTripApi) _setup() {
  final store = InMemoryOfflineStore();
  final api = FakeTripApi();
  final sync = SyncService(store: store, api: api, onChange: (_) {});
  return (sync, store, api);
}

void main() {
  test('manda las acciones guardadas por /sync y las saca de la cola', () async {
    final (sync, store, api) = _setup();
    await sync.enqueue(_event('e1'));
    await sync.enqueue(_event('e2', type: QueuedEventType.absent, student: 's2'));

    final report = await sync.syncTrip('t1');

    expect(report.allSent, isTrue);
    expect(api.syncBatches.single.map((e) => e.clientEventId), ['e1', 'e2']);
    expect(await store.pendingEventCount('t1'), 0);
    expect(sync.state.pendingEvents, 0);
  });

  test('un evento que ya se había aplicado (Duplicate) también sale de la cola', () async {
    final (sync, store, api) = _setup();
    await sync.enqueue(_event('e1'));
    await sync.syncTrip('t1');
    // Llega otra vez (p. ej. la respuesta se perdió y se reencoló).
    await store.enqueueEvent(_event('e1'));

    final report = await sync.syncTrip('t1');

    expect(report.allSent, isTrue);
    expect(await store.pendingEventCount('t1'), 0);
    expect(api.syncBatches, hasLength(2));
  });

  test('un rechazo sale de la cola, no se reintenta y se avisa', () async {
    final (sync, store, api) = _setup();
    api.syncRejections['e1'] = 'PASSENGER_INVALID_TRANSITION';
    await sync.enqueue(_event('e1'));
    await sync.enqueue(_event('e2', student: 's2'));

    final report = await sync.syncTrip('t1');

    expect(report.allSent, isTrue); // un evento inválido no bloquea a los demás
    expect(await store.pendingEventCount('t1'), 0);
    expect(sync.state.rejected, hasLength(1));
    expect(sync.state.rejected.single.event.clientEventId, 'e1');
    expect(sync.state.rejected.single.errorCode, 'PASSENGER_INVALID_TRANSITION');

    sync.ackRejections();
    expect(sync.state.rejected, isEmpty);
  });

  test('sin señal la cola se conserva intacta', () async {
    final (sync, store, api) = _setup();
    api.syncError = _offline;
    await sync.enqueue(_event('e1'));

    final report = await sync.syncTrip('t1');

    expect(report.offline, isTrue);
    expect(report.allSent, isFalse);
    expect(await store.pendingEventCount('t1'), 1);

    api.syncError = null;
    expect((await sync.syncTrip('t1')).allSent, isTrue);
  });

  test('con la sesión vencida (401) se conserva la cola', () async {
    final (sync, store, api) = _setup();
    api.syncError = const ApiError(kind: ApiErrorKind.http, status: 401, code: 'TOKEN_EXPIRED');
    await sync.enqueue(_event('e1'));

    await sync.syncTrip('t1');

    expect(await store.pendingEventCount('t1'), 1);
    expect(sync.state.rejected, isEmpty);
  });

  test('si el servidor rechaza el lote entero (422) se descarta con aviso', () async {
    final (sync, store, api) = _setup();
    api.syncError = const ApiError(kind: ApiErrorKind.http, status: 422, code: 'TRIP_NOT_ACTIVE');
    await sync.enqueue(_event('e1'));
    await sync.enqueue(_event('e2'));

    final report = await sync.syncTrip('t1');

    expect(report.allSent, isTrue);
    expect(sync.state.rejected.map((r) => r.errorCode), ['TRIP_NOT_ACTIVE', 'TRIP_NOT_ACTIVE']);
  });

  test('parte las acciones en llamadas de 200', () async {
    final (sync, _, api) = _setup();
    for (var i = 0; i < 450; i++) {
      await sync.enqueue(_event('e$i'));
    }

    await sync.syncTrip('t1');

    expect(api.syncBatches.map((b) => b.length), [200, 200, 50]);
  });

  test('primero el GPS pendiente y después /sync', () async {
    final (sync, _, api) = _setup();
    final order = <String>[];
    // Registra el orden real de llamadas.
    final tracing = _OrderApi(api, order);
    final traced = SyncService(store: sync.store, api: tracing, onChange: (_) {});
    await traced.addReading('t1', testReading());
    await traced.enqueue(_event('e1'));

    await traced.syncTrip('t1');

    expect(order, ['gps', 'sync']);
  });

  test('un evento que el servidor no menciona se queda para reintentar', () async {
    final (sync, store, _) = _setup();
    final silent = _SilentApi();
    final s = SyncService(store: store, api: silent, onChange: (_) {});
    await s.enqueue(_event('e1'));

    final report = await s.syncTrip('t1');

    expect(report.allSent, isFalse);
    expect(await store.pendingEventCount('t1'), 1);
    expect(silent.syncCalls, 1); // no se queda en un bucle
  });

  test('la cola de un viaje no se mezcla con la de otro', () async {
    final (sync, store, api) = _setup();
    await sync.enqueue(_event('a', trip: 't1'));
    await sync.enqueue(_event('b', trip: 't2'));

    await sync.syncTrip('t1');

    expect(api.syncBatches.single.single.clientEventId, 'a');
    expect(await store.pendingEventCount('t2'), 1);
  });

  test('QueuedEvent.toSyncJson sigue el contrato de /sync', () {
    final incident = QueuedEvent(
      tripId: 't1',
      clientEventId: 'x',
      type: QueuedEventType.incident,
      occurredAt: DateTime.utc(2026, 10, 27, 11, 45),
      incidentType: 'HeavyTraffic',
      notifyGuardians: false,
    );
    expect(incident.toSyncJson(), {
      'clientEventId': 'x',
      'type': 'Incident',
      'occurredAt': '2026-10-27T11:45:00.000Z',
      'incidentType': 'HeavyTraffic',
      'notifyGuardians': false,
    });
    expect(_event('e').toSyncJson()['position'], {'latitude': -12.1, 'longitude': -77.0});
  });
}

/// Anota en qué orden se llama a GPS y a /sync.
class _OrderApi extends FakeTripApi {
  _OrderApi(this._inner, this.order);
  final FakeTripApi _inner;
  final List<String> order;

  @override
  Future<PositionsResult> recordPositions(String tripId, List<GpsReading> r) {
    order.add('gps');
    return _inner.recordPositions(tripId, r);
  }

  @override
  Future<List<SyncOutcome>> sync(String tripId, List<QueuedEvent> e) {
    order.add('sync');
    return _inner.sync(tripId, e);
  }
}

/// Responde 200 sin ningún resultado.
class _SilentApi extends FakeTripApi {
  int syncCalls = 0;

  @override
  Future<List<SyncOutcome>> sync(String tripId, List<QueuedEvent> e) async {
    syncCalls++;
    return const [];
  }
}
