import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/iam/application/session_controller.dart';
import 'package:rutasegura/trip_execution/application/agenda_provider.dart';
import 'package:rutasegura/trip_execution/application/agenda_watcher.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_models.dart';
import 'package:rutasegura/trip_execution/infrastructure/trip_realtime.dart';
import 'package:rutasegura/trip_execution/presentation/pages/home_page.dart';

import '../support/fakes.dart';

const _offline = ApiError(kind: ApiErrorKind.network);

class _Env {
  _Env(this.c, this.api, this.rt, this.announced, this.watcher);

  final ProviderContainer c;
  final FakeTripApi api;
  final FakeTripRealtime rt;

  /// Avisos que llegaron a la pantalla, en orden.
  final List<CancelledTrip> announced;
  final ProviderSubscription<CancelledTrip?> watcher;

  /// Pide la agenda otra vez, como lo hace el refresco automático.
  Future<void> refreshAgenda() async {
    c.invalidate(agendaProvider);
    await c.read(agendaProvider.future);
    await pumpEventQueue();
  }
}

Future<_Env> _open(
  List<ScheduledTrip> trips, {
  Duration refreshEvery = const Duration(hours: 1),
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = FakeTripApi(trips: trips);
  final rt = FakeTripRealtime();
  final c = ProviderContainer(overrides: [
    ...fakeBackend(trips: api, realtime: rt),
    agendaRefreshEveryProvider.overrideWithValue(refreshEvery),
  ]);
  addTearDown(c.dispose);

  // Espera a que la sesión se restaure.
  c.listen(sessionControllerProvider, (_, _) {});
  for (var i = 0; i < 20 && c.read(sessionControllerProvider) is! SessionActive; i++) {
    await Future<void>.delayed(Duration.zero);
  }

  final announced = <CancelledTrip>[];
  final watcher = c.listen(agendaWatcherProvider, (_, n) {
    if (n != null) announced.add(n);
  });
  await c.read(agendaProvider.future);
  await pumpEventQueue();
  return _Env(c, api, rt, announced, watcher);
}

void main() {
  group('AgendaWatcher', () {
    test('se suscribe a los viajes programados, no a los ya iniciados', () async {
      final env = await _open([
        testTrip(id: 'a'),
        testTrip(id: 'b', status: 'InProgress', startsIn: const Duration(hours: -1)),
      ]);

      expect(env.rt.watched, ['a']);
    });

    test('una cancelación por el canal avisa con el motivo y refresca la agenda', () async {
      final env = await _open([testTrip(id: 'a'), testTrip(id: 'b', startsIn: const Duration(hours: 4))]);
      final before = env.api.calls;

      env.api.trips.removeWhere((t) => t.id == 'a'); // el backend ya no lo lista
      env.rt.emit(const RealtimeStatusChanged(status: 'Cancelled', reason: 'Paro de transportes'), tripId: 'a');
      await pumpEventQueue();

      expect(env.announced, hasLength(1));
      expect(env.announced.single.trip.id, 'a');
      expect(env.announced.single.reason, 'Paro de transportes');
      expect(env.announced.single.message, contains('Motivo: Paro de transportes'));
      expect(env.api.calls, greaterThan(before));
      // Y la agenda ya no lo trae.
      final agenda = await env.c.read(agendaProvider.future);
      expect(agenda.trips.map((t) => t.id), ['b']);
    });

    test('otros estados del canal no avisan', () async {
      final env = await _open([testTrip(id: 'a')]);

      env.rt.emit(const RealtimeStatusChanged(status: 'Delayed', reason: 'Tráfico'), tripId: 'a');
      await pumpEventQueue();

      expect(env.announced, isEmpty);
    });

    test('un viaje que desaparece y está cancelado se avisa, sin motivo', () async {
      final env = await _open([testTrip(id: 'a')]);

      env.api.trips.clear();
      env.api.liveState = liveWithStatus(testLive(), 'Cancelled');
      await env.refreshAgenda();

      expect(env.announced, hasLength(1));
      expect(env.announced.single.reason, isNull);
      expect(env.announced.single.message, isNot(contains('Motivo')));
    });

    test('un viaje que desaparece porque se inició o completó NO se avisa', () async {
      for (final status in ['InProgress', 'Completed']) {
        final env = await _open([testTrip(id: 'a')]);

        env.api.trips.clear();
        env.api.liveState = liveWithStatus(testLive(), status);
        await env.refreshAgenda();

        expect(env.announced, isEmpty, reason: 'estado $status');
      }
    });

    test('sin señal al confirmar, se reintenta con la siguiente agenda', () async {
      final env = await _open([testTrip(id: 'a')]);

      env.api.trips.clear();
      env.api.liveError = _offline;
      await env.refreshAgenda();
      expect(env.announced, isEmpty);

      env.api.liveError = null;
      env.api.liveState = liveWithStatus(testLive(), 'Cancelled');
      await env.refreshAgenda();

      expect(env.announced, hasLength(1));
    });

    test('el mismo viaje no se avisa dos veces aunque llegue por las dos vías', () async {
      final env = await _open([testTrip(id: 'a')]);

      env.api.trips.clear();
      env.api.liveState = liveWithStatus(testLive(), 'Cancelled');
      env.rt.emit(const RealtimeStatusChanged(status: 'Cancelled', reason: 'Paro'), tripId: 'a');
      await pumpEventQueue();
      await env.refreshAgenda();
      await env.refreshAgenda();

      expect(env.announced, hasLength(1));
      expect(env.announced.single.reason, 'Paro');
    });

    test('acknowledge limpia el aviso', () async {
      final env = await _open([testTrip(id: 'a')]);
      env.rt.emit(const RealtimeStatusChanged(status: 'Cancelled'), tripId: 'a');
      await pumpEventQueue();
      expect(env.c.read(agendaWatcherProvider), isNotNull);

      env.c.read(agendaWatcherProvider.notifier).acknowledge();

      expect(env.c.read(agendaWatcherProvider), isNull);
    });

    test('la agenda se refresca sola cada intervalo', () async {
      final env = await _open([testTrip(id: 'a')], refreshEvery: const Duration(milliseconds: 40));
      final before = env.api.calls;

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(env.api.calls, greaterThan(before));
    });

    test('la primera conexión del canal no refresca; una reconexión sí', () async {
      final env = await _open([testTrip(id: 'a')]);
      final before = env.api.calls;

      env.rt.emit(const RealtimeConnected(), tripId: 'a');
      await pumpEventQueue();
      expect(env.api.calls, before, reason: 'la agenda acaba de pedirse');

      env.rt.emit(const RealtimeConnected(), tripId: 'a');
      await pumpEventQueue();
      expect(env.api.calls, greaterThan(before));
    });

    test('al cerrar se cancelan las suscripciones', () async {
      final env = await _open([testTrip(id: 'a'), testTrip(id: 'b', startsIn: const Duration(hours: 4))]);
      expect(env.rt.isWatching('a'), isTrue);
      expect(env.rt.isWatching('b'), isTrue);

      env.watcher.close();
      await pumpEventQueue();

      expect(env.rt.hasListener, isFalse);
    });
  });

  group('Inicio', () {
    testWidgets('muestra el aviso de cancelación y la agenda ya sin ese viaje', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeTripApi(trips: [
        testTrip(id: 'a'),
        testTrip(id: 'b', startsIn: const Duration(hours: 4), direction: 'Return'),
      ]);
      final rt = FakeTripRealtime();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...fakeBackend(trips: api, realtime: rt),
            agendaRefreshEveryProvider.overrideWithValue(const Duration(hours: 1)),
          ],
          child: const MaterialApp(home: Scaffold(body: HomePage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Más tarde hoy'), findsOneWidget);

      api.trips.removeWhere((t) => t.id == 'b');
      rt.emit(const RealtimeStatusChanged(status: 'Cancelled', reason: 'Paro de transportes'), tripId: 'b');
      await tester.pumpAndSettle();

      expect(find.text('Viaje cancelado'), findsOneWidget);
      expect(find.textContaining('Paro de transportes'), findsOneWidget);

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();

      expect(find.text('Viaje cancelado'), findsNothing);
      // La lista ya no tiene el viaje cancelado.
      expect(find.text('Más tarde hoy'), findsNothing);
    });
  });
}
