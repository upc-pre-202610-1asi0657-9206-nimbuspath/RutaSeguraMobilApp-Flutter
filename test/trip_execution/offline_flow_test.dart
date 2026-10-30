import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/core/storage/local_cache.dart';
import 'package:rutasegura/trip_execution/application/sync_controller.dart';
import 'package:rutasegura/trip_execution/application/trip_controller.dart';
import 'package:rutasegura/trip_execution/domain/model/queued_event.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_live.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_models.dart';
import 'package:rutasegura/trip_execution/infrastructure/offline_store.dart';
import 'package:rutasegura/trip_execution/infrastructure/trip_api.dart';
import 'package:rutasegura/trip_execution/presentation/pages/boarding_page.dart';
import 'package:rutasegura/trip_execution/presentation/pages/report_incident_page.dart';
import 'package:rutasegura/trip_execution/presentation/pages/sos_page.dart';

import '../support/fakes.dart';

PassengerStatus _status(TripLive l, String id) =>
    l.passengers.firstWhere((p) => p.studentId == id).status;

class _Env {
  _Env({FakeTripApi? api, InMemoryOfflineStore? store, InMemoryLocalCache? cache})
      : api = api ?? FakeTripApi(),
        store = store ?? InMemoryOfflineStore(),
        cache = cache ?? InMemoryLocalCache() {
    container = ProviderContainer(
      overrides: fakeBackend(trips: this.api, offline: this.store, cache: this.cache),
    );
    addTearDown(container.dispose);
  }

  final FakeTripApi api;
  final InMemoryOfflineStore store;
  final InMemoryLocalCache cache;
  late final ProviderContainer container;

}

void main() {
  final trip = testTrip(status: 'InProgress');
  final provider = tripControllerProvider(trip);

  Future<(_Env, TripController)> open({FakeTripApi? api, InMemoryOfflineStore? store, InMemoryLocalCache? cache}) async {
    final env = _Env(api: api, store: store, cache: cache);
    env.container.listen(provider, (_, _) {});
    await env.container.read(provider.future);
    return (env, env.container.read(provider.notifier));
  }

  group('Acciones sin señal', () {
    test('"Subió" queda guardado, se ve hecho y sale por /sync al reconectar', () async {
      final (env, ctrl) = await open();
      env.api.goOffline();

      final result = await ctrl.record(PassengerAction.board, 's1');

      expect(result.queued, isTrue);
      expect(_status(env.container.read(provider).requireValue, 's1'), PassengerStatus.boarded);
      expect(await env.store.pendingEventCount('t1'), 1);
      expect(env.container.read(syncControllerProvider).pendingEvents, 1);

      env.api.goOnline();
      await ctrl.refresh();

      final sent = env.api.syncBatches.single.single;
      expect(sent.type, QueuedEventType.boarding);
      expect(sent.studentId, 's1');
      expect(await env.store.pendingEventCount('t1'), 0);
      expect(_status(env.container.read(provider).requireValue, 's1'), PassengerStatus.boarded);
    });

    test('la acción guardada conserva su clientEventId al salir por /sync', () async {
      final (env, ctrl) = await open();
      env.api.goOffline();
      await ctrl.record(PassengerAction.board, 's1');
      final queuedId = (await env.store.pendingEvents('t1')).single.clientEventId;

      env.api.goOnline();
      await ctrl.refresh();

      expect(env.api.syncBatches.single.single.clientEventId, queuedId);
    });

    test('mientras sigue sin señal, /live no deshace lo guardado', () async {
      final (env, ctrl) = await open();
      env.api.goOffline();
      await ctrl.record(PassengerAction.board, 's1');

      // Hay red para /live pero /sync todavía falla: el servidor aún no sabe.
      env.api.liveError = null;
      await ctrl.refresh();

      expect(_status(env.container.read(provider).requireValue, 's1'), PassengerStatus.boarded);
      expect(await env.store.pendingEventCount('t1'), 1);
    });

    test('un rechazo de negocio no se guarda y la fila vuelve atrás', () async {
      final (env, ctrl) = await open();
      env.api.actionError = const ApiErrorStub422().error;

      final result = await ctrl.record(PassengerAction.board, 's1');

      expect(result.isFailure, isTrue);
      expect(await env.store.pendingEventCount('t1'), 0);
      expect(_status(env.container.read(provider).requireValue, 's1'), PassengerStatus.pending);
    });

    test('si /sync rechaza una acción, se avisa y la lista vuelve a la verdad del servidor', () async {
      final (env, ctrl) = await open();
      env.api.goOffline();
      await ctrl.record(PassengerAction.board, 's1');
      final id = (await env.store.pendingEvents('t1')).single.clientEventId;
      env.api.syncRejections[id] = 'PASSENGER_INVALID_TRANSITION';

      env.api.goOnline();
      await ctrl.refresh();

      final rejected = env.container.read(syncControllerProvider).rejected;
      expect(rejected.single.errorCode, 'PASSENGER_INVALID_TRANSITION');
      expect(await env.store.pendingEventCount('t1'), 0);
      // El servidor nunca lo aplicó: vuelve a "pendiente".
      expect(_status(env.container.read(provider).requireValue, 's1'), PassengerStatus.pending);
    });

    test('un incidente sin señal se guarda y sale como Incident', () async {
      final (env, ctrl) = await open();
      env.api.goOffline();

      final result = await ctrl.reportIncident(
        type: IncidentType.accident,
        notifyGuardians: false,
        detail: 'Choque leve',
      );

      expect(result.queued, isTrue);
      env.api.goOnline();
      await ctrl.refresh();
      expect(env.api.incidents, ['Accident|Choque leve|false']);
      expect(await env.store.pendingEventCount('t1'), 0);
    });
  });

  group('Finalizar', () {
    test('no finaliza mientras haya registros sin enviar', () async {
      final (env, ctrl) = await open();
      env.api.goOffline();
      await ctrl.record(PassengerAction.board, 's1');
      env.api.completeError = null; // /complete funcionaría, pero la cola no está vacía
      env.api.syncError = const ApiErrorStub422().network;

      final error = await ctrl.complete('c1');

      expect(error, isNotNull);
      expect(env.api.completeEvents, isEmpty);
      expect(await env.store.pendingEventCount('t1'), 1);
    });

    test('vacía la cola y el GPS, y luego finaliza; después limpia lo guardado', () async {
      final (env, ctrl) = await open();
      env.api.goOffline();
      await ctrl.record(PassengerAction.board, 's1');
      await env.store.addReading('t1', testReading());
      env.api.goOnline();

      final error = await ctrl.complete('c1');

      expect(error, isNull);
      expect(env.api.positionBatches, hasLength(1)); // 1) GPS
      expect(env.api.syncBatches, hasLength(1)); // 2) /sync
      expect(env.api.completeEvents, ['c1']); // 3) /complete
      expect(await env.store.pendingEventCount('t1'), 0);
      expect(await env.store.pendingReadingCount('t1'), 0);
    });
  });

  group('Abrir el viaje sin señal', () {
    test('usa el último estado guardado con lo pendiente encima', () async {
      final cache = InMemoryLocalCache();
      final store = InMemoryOfflineStore();
      final (env, ctrl) = await open(cache: cache, store: store);
      env.api.goOffline();
      await ctrl.record(PassengerAction.board, 's1');
      env.container.dispose();

      // La app se cierra y se vuelve a abrir sin señal.
      final api2 = FakeTripApi()..goOffline();
      final (env2, _) = await open(api: api2, cache: cache, store: store);

      final live = env2.container.read(provider).requireValue;
      expect(live.nextStop?.name, 'Av. Primavera 1240');
      expect(_status(live, 's1'), PassengerStatus.boarded);
      expect(env2.container.read(syncControllerProvider).pendingEvents, 1);
    });

    test('sin estado guardado y sin señal, se informa el error', () async {
      final api = FakeTripApi()..goOffline();
      final env = _Env(api: api);
      env.container.listen(provider, (_, _) {});

      await expectLater(env.container.read(provider.future), throwsA(anything));
    });
  });

  group('Pantallas', () {
    /// Libera el contenedor antes de que termine la prueba (sus temporizadores
    /// no pueden quedar pendientes).
    Future<void> close(WidgetTester tester, _Env env) async {
      await tester.pumpWidget(const SizedBox());
      env.container.dispose();
    }

    Future<void> pump(WidgetTester tester, Widget page, _Env env, {bool settle = true}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: env.container,
        child: MaterialApp(home: page),
      ));
      settle ? await tester.pumpAndSettle() : await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('abordaje sin señal: se ve hecho y avisa que quedó guardado', (tester) async {
      final env = _Env();
      env.container.listen(provider, (_, _) {});
      await env.container.read(provider.future);
      await pump(tester, BoardingPage(trip: trip), env);
      env.api.goOffline();

      await tester.tap(find.text('Subió').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Sin señal: se guardó'), findsOneWidget);
      expect(find.textContaining('Subió '), findsOneWidget); // chip con la hora
      expect(await env.store.pendingEventCount('t1'), 1);
      await close(tester, env);
    });

    testWidgets('incidente sin señal: se guarda y la pantalla se cierra', (tester) async {
      final env = _Env();
      env.container.listen(provider, (_, _) {});
      await env.container.read(provider.future);
      Object? popped;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: env.container,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async => popped = await Navigator.of(ctx).push(
                MaterialPageRoute<Object>(builder: (_) => ReportIncidentPage(trip: trip)),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      env.api.goOffline();

      await tester.tap(find.text('Tráfico intenso'));
      await tester.pump();
      await tester.tap(find.text('Enviar reporte'));
      await tester.pumpAndSettle();

      expect(find.byType(ReportIncidentPage), findsNothing);
      expect(popped, isNotNull);
      expect(await env.store.pendingEventCount('t1'), 1);
      await close(tester, env);
    });

    testWidgets('SOS sin señal: queda guardado, se puede volver y sigue reintentando', (tester) async {
      final env = _Env();
      env.container.listen(provider, (_, _) {});
      await env.container.read(provider.future);
      await pump(tester, SosPage(trip: trip), env, settle: false);
      env.api.goOffline();

      await tester.tap(find.text('SOS'));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.pump();

      expect(find.text('Alerta guardada'), findsOneWidget);
      expect(find.text('Volver al viaje'), findsWidgets);
      final queued = await env.store.pendingEvents('t1');
      expect(queued.single.type, QueuedEventType.sos);

      // Vuelve la señal: el reintento directo lo envía y limpia la cola.
      env.api.goOnline();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump();

      expect(find.text('Alerta enviada'), findsOneWidget);
      expect(env.api.sosEvents, [queued.single.clientEventId]);
      expect(await env.store.pendingEventCount('t1'), 0);
      await close(tester, env);
    });
  });
}

/// Atajos para no repetir ApiError en cada prueba.
class ApiErrorStub422 {
  const ApiErrorStub422();
  ApiError get error => const ApiError(
        kind: ApiErrorKind.http,
        status: 422,
        code: 'PASSENGER_INVALID_TRANSITION',
      );
  ApiError get network => const ApiError(kind: ApiErrorKind.network);
}
