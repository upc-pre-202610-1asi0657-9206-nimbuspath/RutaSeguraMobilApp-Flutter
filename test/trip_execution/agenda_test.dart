import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/core/storage/local_cache.dart';
import 'package:rutasegura/iam/application/session_controller.dart';
import 'package:rutasegura/trip_execution/application/agenda_provider.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_models.dart';

import '../support/fakes.dart';

const _offline = ApiError(kind: ApiErrorKind.network);

Future<Agenda> _agenda(ProviderContainer c) async {
  // Espera a que la sesión se restaure y la agenda cargue.
  c.listen(sessionControllerProvider, (_, _) {});
  for (var i = 0; i < 20 && c.read(sessionControllerProvider) is! SessionActive; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(agendaProvider.future);
}

ProviderContainer _container({FakeTripApi? trips, LocalCache? cache}) {
  final c = ProviderContainer(
    overrides: fakeBackend(trips: trips, cache: cache),
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('ScheduledTrip', () {
    test('la ventana de inicio abre 60 min antes', () {
      final trip = testTrip(startsIn: const Duration(minutes: 90));
      final now = DateTime.now();
      expect(trip.canStart(now), isFalse);
      expect(trip.canStart(now.add(const Duration(minutes: 29))), isFalse);
      expect(trip.canStart(now.add(const Duration(minutes: 31))), isTrue);
    });

    test('un viaje en curso siempre se puede continuar; uno completado no', () {
      expect(testTrip(status: 'InProgress', startsIn: const Duration(hours: -1))
          .canStart(DateTime.now()), isTrue);
      expect(testTrip(status: 'Delayed').isInProgress, isTrue);
      expect(testTrip(status: 'Completed').canStart(DateTime.now()), isFalse);
    });

    test('la hora se muestra en Lima (UTC-5)', () {
      final trip = ScheduledTrip.fromJson({
        'tripId': 't',
        'routeName': 'Ruta 3',
        'direction': 'Return',
        'scheduledStart': '2026-10-26T13:30:00-05:00',
        'status': 'Scheduled',
        'stopCount': 7,
        'studentCount': 18,
      });
      expect(trip.departure, '13:30');
      expect(trip.kind, TripKind.dropOff);
      expect(trip.startWindowOpensAtLabel, '12:30');
    });
  });

  group('agendaProvider', () {
    test('cruza la placa con los vehículos y deja el primer viaje abierto como próximo', () async {
      final c = _container(trips: FakeTripApi(trips: [
        testTrip(id: 'hecho', status: 'Completed', startsIn: const Duration(hours: -3)),
        testTrip(id: 'a'),
        testTrip(id: 'b', startsIn: const Duration(hours: 6), direction: 'Return'),
      ]));
      final agenda = await _agenda(c);

      expect(agenda.next!.id, 'a');
      expect(agenda.next!.vehiclePlate, 'ABC-123');
      expect(agenda.later.map((t) => t.id), ['b']);
      expect(agenda.fromCache, isFalse);
    });

    test('sin conexión usa la agenda guardada de hoy, con su placa', () async {
      final cache = InMemoryLocalCache();
      final api = FakeTripApi();
      var c = _container(trips: api, cache: cache);
      await _agenda(c);

      final offline = FakeTripApi(trips: const [])..error = _offline;
      c = _container(trips: offline, cache: cache);
      final agenda = await _agenda(c);

      expect(agenda.fromCache, isTrue);
      expect(agenda.next!.vehiclePlate, 'ABC-123');
    });

    test('sin conexión y sin nada guardado falla con el error', () async {
      final c = _container(trips: FakeTripApi()..error = _offline);
      await expectLater(_agenda(c), throwsA(isA<ApiError>()));
    });

    test('un error de negocio (422) no usa la caché', () async {
      final cache = InMemoryLocalCache();
      await _agenda(_container(cache: cache));

      final c = _container(
        trips: FakeTripApi()
          ..error = const ApiError(kind: ApiErrorKind.http, status: 422),
        cache: cache,
      );
      await expectLater(_agenda(c), throwsA(isA<ApiError>()));
    });
  });
}
