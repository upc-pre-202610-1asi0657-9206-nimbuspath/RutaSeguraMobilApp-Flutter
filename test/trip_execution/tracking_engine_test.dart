import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/trip_execution/application/tracking_engine.dart';
import 'package:rutasegura/trip_execution/domain/model/tracking.dart';

import '../support/fakes.dart';

const _offline = ApiError(kind: ApiErrorKind.network);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

(TrackingEngine, FakeTripApi, FakePositionSource, List<TrackingState>) _engine({
  FakeTripApi? api,
  FakePositionSource? gps,
}) {
  final fakeApi = api ?? FakeTripApi();
  final source = gps ?? FakePositionSource();
  final states = <TrackingState>[];
  final engine = TrackingEngine(
    tripId: 't1',
    api: fakeApi,
    source: source,
    onChange: states.add,
    flushEvery: const Duration(hours: 1), // los envíos los dispara el test
  );
  addTearDown(engine.stop);
  return (engine, fakeApi, source, states);
}

void main() {
  test('descarta lecturas ruidosas y envía las buenas en orden', () async {
    final (engine, api, gps, _) = _engine();
    await engine.start();

    gps.emit(testReading(lat: -12.1, lon: -77.0));
    gps.emit(testReading(accuracy: 150)); // impreciso
    gps.emit(testReading(speedKmh: 200)); // velocidad imposible
    gps.emit(testReading(lat: 0, lon: 0)); // (0,0)
    gps.emit(testReading(at: DateTime.now().add(const Duration(minutes: 5)))); // futuro
    gps.emit(testReading(lat: -12.2, lon: -77.1));
    await _settle();
    expect(engine.pending, 2);

    await engine.flush();

    expect(api.positionBatches, hasLength(1));
    expect(api.positionBatches.single.map((r) => r.latitude), [-12.1, -12.2]);
    expect(engine.pending, 0);
    expect(engine.state.lastSentAt, isNotNull);
    expect(engine.state.sent, 2);
  });

  test('parte los envíos en lotes de 500', () async {
    final (engine, api, gps, _) = _engine();
    await engine.start();

    for (var i = 0; i < 1200; i++) {
      gps.emit(testReading(lat: -12.0 - i / 100000));
    }
    await _settle();
    await engine.flush();

    expect(api.positionBatches.map((b) => b.length), [500, 500, 200]);
  });

  test('sin señal conserva las lecturas y las manda en orden al reconectar', () async {
    final api = FakeTripApi()..positionsError = _offline;
    final (engine, _, gps, _) = _engine(api: api);
    await engine.start();

    gps.emit(testReading(lat: -12.1));
    await _settle();
    await engine.flush();
    expect(engine.pending, 1);
    expect(engine.state.status, TrackingStatus.active);

    gps.emit(testReading(lat: -12.2));
    await _settle();
    api.positionsError = null;
    await engine.flush();

    expect(api.positionBatches.single.map((r) => r.latitude), [-12.1, -12.2]);
    expect(engine.pending, 0);
  });

  test('TRACKING_REQUIRES_ACTIVE_TRIP detiene el GPS de inmediato', () async {
    final api = FakeTripApi()
      ..positionsError = const ApiError(
        kind: ApiErrorKind.http,
        status: 422,
        code: ApiErrorCodes.trackingRequiresActiveTrip,
      );
    final (engine, _, gps, _) = _engine(api: api);
    await engine.start();
    expect(gps.hasListener, isTrue);

    gps.emit(testReading());
    await _settle();
    await engine.flush();

    expect(engine.state.status, TrackingStatus.stopped);
    expect(gps.hasListener, isFalse);
  });

  test('un 429 pausa los envíos y las lecturas siguen guardándose', () async {
    final api = FakeTripApi()
      ..positionsError = const ApiError(
        kind: ApiErrorKind.http,
        status: 429,
        retryAfter: Duration(minutes: 1),
      );
    final (engine, _, gps, _) = _engine(api: api);
    await engine.start();

    gps.emit(testReading());
    await _settle();
    await engine.flush();
    api.positionsError = null;
    await engine.flush(); // dentro de la pausa: no envía

    expect(api.positionBatches, isEmpty);
    expect(engine.pending, 1);
  });

  test('sin permiso o con el GPS apagado no empieza a rastrear', () async {
    for (final (perm, expected) in [
      (TrackingPermission.denied, TrackingStatus.noPermission),
      (TrackingPermission.serviceOff, TrackingStatus.serviceOff),
    ]) {
      final gps = FakePositionSource(permission: perm);
      final (engine, _, _, _) = _engine(gps: gps);
      await engine.start();
      expect(engine.state.status, expected);
      expect(gps.hasListener, isFalse);
    }
  });

  test('stop cancela la suscripción y deja de aceptar lecturas', () async {
    final (engine, api, gps, _) = _engine();
    await engine.start();
    await engine.stop();

    gps.emit(testReading());
    await _settle();
    await engine.flush();

    expect(gps.hasListener, isFalse);
    expect(api.positionBatches, isEmpty);
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
