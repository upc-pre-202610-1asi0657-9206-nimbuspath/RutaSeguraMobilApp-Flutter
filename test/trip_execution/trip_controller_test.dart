import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/trip_execution/application/trip_controller.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_live.dart';
import 'package:rutasegura/trip_execution/infrastructure/trip_api.dart';

import '../support/fakes.dart';

const _invalidTransition = ApiError(
  kind: ApiErrorKind.http,
  status: 422,
  code: 'PASSENGER_INVALID_TRANSITION',
  detail: 'Transición inválida',
);

(ProviderContainer, FakeTripApi) _setup({FakeTripApi? api}) {
  final fake = api ?? FakeTripApi();
  final c = ProviderContainer(overrides: fakeBackend(trips: fake));
  addTearDown(c.dispose);
  return (c, fake);
}

PassengerStatus _status(TripLive l, String id) =>
    l.passengers.firstWhere((p) => p.studentId == id).status;

void main() {
  final scheduled = testTrip();

  test('inicia el viaje programado y carga /live', () async {
    final (c, api) = _setup();
    final live = await c.read(tripControllerProvider(scheduled).future);

    expect(api.startedWith, hasLength(1));
    expect(live.nextStop?.name, 'Av. Primavera 1240');
    expect(live.passengers, hasLength(2));
  });

  test('un viaje ya en curso se retoma sin llamar a /start', () async {
    final (c, api) = _setup();
    await c.read(tripControllerProvider(testTrip(status: 'InProgress')).future);
    expect(api.startedWith, isEmpty);
  });

  test('reintentar el inicio reutiliza el mismo clientEventId', () async {
    final api = FakeTripApi()
      ..startError = const ApiError(kind: ApiErrorKind.network);
    final (c, _) = _setup(api: api);
    final provider = tripControllerProvider(scheduled);
    c.listen(provider, (_, _) {});

    await expectLater(c.read(provider.future), throwsA(isA<ApiError>()));
    api.startError = null;
    await c.read(provider.notifier).retry();

    expect(c.read(provider).hasValue, isTrue);
    expect(api.startedWith, hasLength(2));
    expect(api.startedWith[0], api.startedWith[1]);
  });

  test('"Subió" es optimista y manda un clientEventId nuevo por toque', () async {
    final (c, api) = _setup();
    final provider = tripControllerProvider(scheduled);
    c.listen(provider, (_, _) {});
    await c.read(provider.future);
    final ctrl = c.read(provider.notifier);

    final pending = ctrl.record(PassengerAction.board, 's1');
    await Future<void>.delayed(Duration.zero);
    expect(_status(c.read(provider).requireValue, 's1'), PassengerStatus.boarded);
    expect(await pending, isNull);

    await ctrl.record(PassengerAction.absent, 's2');
    final ids = api.actions.map((a) => a.split(':')[2]).toSet();
    expect(ids, hasLength(2));
    expect(api.actions.first, startsWith('board:s1:'));
    expect(c.read(provider).requireValue.studentsOnBoard, 1);
  });

  test('si el servidor rechaza la acción, la fila vuelve a su estado', () async {
    final api = FakeTripApi()..actionError = _invalidTransition;
    final (c, _) = _setup(api: api);
    final provider = tripControllerProvider(scheduled);
    c.listen(provider, (_, _) {});
    await c.read(provider.future);

    final error = await c.read(provider.notifier).record(PassengerAction.board, 's1');

    expect(error?.code, 'PASSENGER_INVALID_TRANSITION');
    expect(_status(c.read(provider).requireValue, 's1'), PassengerStatus.pending);
  });

  test('"Deshacer" devuelve al alumno a pendiente', () async {
    final (c, api) = _setup();
    final provider = tripControllerProvider(scheduled);
    c.listen(provider, (_, _) {});
    await c.read(provider.future);
    final ctrl = c.read(provider.notifier);

    await ctrl.record(PassengerAction.absent, 's1');
    expect(await ctrl.undo('s1'), isNull);

    expect(api.actions.last, startsWith('undo:s1:'));
    expect(_status(c.read(provider).requireValue, 's1'), PassengerStatus.pending);
  });

  test('TripLive cuenta pendientes y alumnos de la siguiente parada', () {
    final live = testLive(passengers: [
      testPassenger('s1'),
      testPassenger('s2', status: PassengerStatus.boarded),
      testPassenger('s3', stopId: 'p2'),
    ]);
    expect(live.pendingCount, 2);
    expect(live.boardingAtNextStop, 1);
  });

  test('TripLive.fromJson lee el contrato de /live', () {
    final live = TripLive.fromJson({
      'tripId': 't1',
      'direction': 'Return',
      'status': 'Delayed',
      'startedAt': '2026-10-26T06:41:00-05:00',
      'position': {'latitude': -12.1, 'longitude': -76.9, 'ageSeconds': 3},
      'nextStop': {
        'stopId': 'p4', 'name': 'Av. Primavera 1240', 'sequence': 4,
        'totalStops': 7, 'distanceMeters': 1400, 'etaMinutes': 6,
      },
      'studentsOnBoard': 9,
      'totalStudents': 18,
      'hasActiveSos': true,
      'passengers': [
        {'studentId': 's1', 'stopId': 'p4', 'status': 'Absent', 'absenceSource': 'Guardian', 'absenceNote': 'Enfermo'},
      ],
      'stops': [
        {'stopId': 'p5', 'name': 'B', 'sequence': 5, 'latitude': -12.2, 'longitude': -76.9},
        {'stopId': 'p4', 'name': 'A', 'sequence': 4, 'latitude': -12.1, 'longitude': -76.9},
      ],
    });
    expect(live.isPickup, isFalse);
    expect(live.isActive, isTrue);
    expect(live.nextStop?.distanceLabel, '1,4 km');
    expect(live.position?.ageSeconds, 3);
    expect(live.passengers.single.absentByGuardian, isTrue);
    expect(live.stops.first.stopId, 'p4'); // ordenadas por secuencia
  });
}
