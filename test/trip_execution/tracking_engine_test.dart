import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/trip_execution/application/sync_service.dart';
import 'package:rutasegura/trip_execution/application/tracking_engine.dart';
import 'package:rutasegura/trip_execution/domain/model/tracking.dart';
import 'package:rutasegura/trip_execution/infrastructure/offline_store.dart';

import '../support/fakes.dart';

const _offline = ApiError(kind: ApiErrorKind.network);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

class _Rig {
  _Rig({FakeTripApi? api, FakePositionSource? gps, OfflineStore? store})
      : api = api ?? FakeTripApi(),
        gps = gps ?? FakePositionSource(),
        store = store ?? InMemoryOfflineStore() {
    sync = SyncService(store: this.store, api: this.api, onChange: (_) {});
    engine = TrackingEngine(
      tripId: 't1',
      sync: sync,
      source: this.gps,
      onChange: (_) {},
      flushEvery: const Duration(hours: 1), // los envíos los dispara el test
    );
  }

  final FakeTripApi api;
  final FakePositionSource gps;
  final OfflineStore store;
  late final SyncService sync;
  late final TrackingEngine engine;

  Future<int> get pending => store.pendingReadingCount('t1');
}

_Rig _rig({FakeTripApi? api, FakePositionSource? gps, OfflineStore? store}) {
  final r = _Rig(api: api, gps: gps, store: store);
  addTearDown(r.engine.stop);
  return r;
}

void main() {
  test('descarta lecturas ruidosas y envía las buenas en orden', () async {
    final r = _rig();
    await r.engine.start();

    r.gps.emit(testReading(lat: -12.1, lon: -77.0));
    r.gps.emit(testReading(accuracy: 150)); // impreciso
    r.gps.emit(testReading(speedKmh: 200)); // velocidad imposible
    r.gps.emit(testReading(lat: 0, lon: 0)); // (0,0)
    r.gps.emit(testReading(at: DateTime.now().add(const Duration(minutes: 5)))); // futuro
    r.gps.emit(testReading(lat: -12.2, lon: -77.1));
    await _settle();
    expect(await r.pending, 2);

    await r.engine.flush();

    expect(r.api.positionBatches, hasLength(1));
    expect(r.api.positionBatches.single.map((x) => x.latitude), [-12.1, -12.2]);
    expect(await r.pending, 0);
    expect(r.engine.state.lastSentAt, isNotNull);
  });

  test('parte los envíos en lotes de 500', () async {
    final r = _rig();
    await r.engine.start();

    for (var i = 0; i < 1200; i++) {
      r.gps.emit(testReading(lat: -12.0 - i / 100000));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await r.engine.flush();

    expect(r.api.positionBatches.map((b) => b.length), [500, 500, 200]);
  });

  test('sin señal conserva las lecturas y las manda en orden al reconectar', () async {
    final api = FakeTripApi()..positionsError = _offline;
    final r = _rig(api: api);
    await r.engine.start();

    r.gps.emit(testReading(lat: -12.1));
    await _settle();
    await r.engine.flush();
    expect(await r.pending, 1);
    expect(r.engine.state.status, TrackingStatus.active);

    r.gps.emit(testReading(lat: -12.2));
    await _settle();
    api.positionsError = null;
    await r.engine.flush();

    expect(api.positionBatches.single.map((x) => x.latitude), [-12.1, -12.2]);
    expect(await r.pending, 0);
  });

  test('lo guardado sobrevive a que se cierre la app', () async {
    final store = InMemoryOfflineStore();
    final api = FakeTripApi()..positionsError = _offline;
    final first = _rig(api: api, store: store);
    await first.engine.start();
    first.gps.emit(testReading(lat: -12.1));
    await _settle();
    await first.engine.flush();
    await first.engine.stop();

    // "Reabre" la app: otro motor, mismo almacén, ya con señal.
    api.positionsError = null;
    final second = _rig(api: api, store: store);
    await second.engine.start();
    await second.engine.flush();

    expect(api.positionBatches.single.map((x) => x.latitude), [-12.1]);
  });

  test('TRACKING_REQUIRES_ACTIVE_TRIP detiene el GPS y borra lo guardado', () async {
    final api = FakeTripApi()
      ..positionsError = const ApiError(
        kind: ApiErrorKind.http,
        status: 422,
        code: ApiErrorCodes.trackingRequiresActiveTrip,
      );
    final r = _rig(api: api);
    await r.engine.start();
    expect(r.gps.hasListener, isTrue);

    r.gps.emit(testReading());
    await _settle();
    await r.engine.flush();

    expect(r.engine.state.status, TrackingStatus.stopped);
    expect(r.gps.hasListener, isFalse);
    expect(await r.pending, 0);
  });

  test('un 429 pausa los envíos y las lecturas siguen guardándose', () async {
    final api = FakeTripApi()
      ..positionsError = const ApiError(
        kind: ApiErrorKind.http,
        status: 429,
        retryAfter: Duration(minutes: 1),
      );
    final r = _rig(api: api);
    await r.engine.start();

    r.gps.emit(testReading());
    await _settle();
    await r.engine.flush();
    api.positionsError = null;
    await r.engine.flush(); // dentro de la pausa: no envía

    expect(api.positionBatches, isEmpty);
    expect(await r.pending, 1);
  });

  test('sin permiso o con el GPS apagado no empieza a rastrear', () async {
    for (final (perm, expected) in [
      (TrackingPermission.denied, TrackingStatus.noPermission),
      (TrackingPermission.serviceOff, TrackingStatus.serviceOff),
    ]) {
      final gps = FakePositionSource(permission: perm);
      final r = _rig(gps: gps);
      await r.engine.start();
      expect(r.engine.state.status, expected);
      expect(gps.hasListener, isFalse);
    }
  });

  test('stop cancela la suscripción y deja de aceptar lecturas', () async {
    final r = _rig();
    await r.engine.start();
    await r.engine.stop();

    r.gps.emit(testReading());
    await _settle();
    await r.engine.flush();

    expect(r.gps.hasListener, isFalse);
    expect(r.api.positionBatches, isEmpty);
  });

  test('GpsReading.toJson sigue el contrato', () {
    final r = GpsReading(
      latitude: -12.1,
      longitude: -76.9,
      recordedAt: DateTime.utc(2026, 10, 27, 11, 45, 3),
      accuracyMeters: 8,
      speedKmh: 24.5,
    );
    expect(r.toJson(), {
      'latitude': -12.1,
      'longitude': -76.9,
      'recordedAt': '2026-10-27T11:45:03.000Z',
      'accuracyMeters': 8,
      'speedKmh': 24.5,
    });
  });
}
