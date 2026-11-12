import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/trip_execution/application/trip_controller.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_live.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_notice.dart';
import 'package:rutasegura/trip_execution/infrastructure/trip_realtime.dart';
import 'package:rutasegura/trip_execution/presentation/pages/active_trip_page.dart';

import '../support/fakes.dart';

/// El mismo estado en vivo pero con otro `status`.
TripLive _withStatus(TripLive l, String status) => TripLive(
      tripId: l.tripId,
      status: status,
      isPickup: l.isPickup,
      startedAt: l.startedAt,
      position: l.position,
      nextStop: l.nextStop,
      studentsOnBoard: l.studentsOnBoard,
      totalStudents: l.totalStudents,
      hasActiveSos: l.hasActiveSos,
      passengers: l.passengers,
      stops: l.stops,
    );

void main() {
  final trip = testTrip(status: 'InProgress');

  group('Mensaje del canal (TripStatusChanged)', () {
    test('lee estado y motivo', () {
      final e = RealtimeStatusChanged.tryParse([
        {
          'tripId': 't1',
          'status': 'Cancelled',
          'reason': 'Paro de transportes',
          'occurredAt': '2026-11-12T10:00:00+00:00',
        },
      ]);
      expect(e?.status, 'Cancelled');
      expect(e?.reason, 'Paro de transportes');
    });

    test('el motivo es opcional', () {
      final e = RealtimeStatusChanged.tryParse([
        {'status': 'InProgress', 'reason': null},
      ]);
      expect(e?.status, 'InProgress');
      expect(e?.reason, isNull);
    });

    test('un mensaje con otra forma se ignora sin fallar', () {
      expect(RealtimeStatusChanged.tryParse(null), isNull);
      expect(RealtimeStatusChanged.tryParse([]), isNull);
      expect(RealtimeStatusChanged.tryParse(['texto']), isNull);
      expect(RealtimeStatusChanged.tryParse([{'reason': 'x'}]), isNull);
      expect(RealtimeStatusChanged.tryParse([{'status': ''}]), isNull);
    });
  });

  group('TripNotice', () {
    test('la cancelación incluye el motivo si lo hay', () {
      expect(
        const TripNotice(TripNoticeKind.tripCancelled, reason: ' Paro ').message,
        'Tu empresa canceló este viaje.\nMotivo: Paro',
      );
      expect(
        const TripNotice(TripNoticeKind.tripCancelled).message,
        'Tu empresa canceló este viaje.',
      );
      expect(
        const TripNotice(TripNoticeKind.tripCancelled, reason: '  ').message,
        'Tu empresa canceló este viaje.',
      );
    });
  });

  group('TripController con canal en tiempo real', () {
    late FakeTripApi api;
    late FakeTripRealtime realtime;
    late ProviderContainer c;
    late List<TripNotice> notices;
    late ProviderSubscription<AsyncValue<TripLive>> screen;

    Future<TripController> open({TripLive? live}) async {
      api = FakeTripApi(live: live);
      realtime = FakeTripRealtime();
      c = ProviderContainer(overrides: fakeBackend(trips: api, realtime: realtime));
      addTearDown(c.dispose);
      notices = [];
      c.listen(tripNoticeProvider(trip.id), (_, n) {
        if (n != null) notices.add(n);
      });
      final provider = tripControllerProvider(trip);
      // Hace de "pantalla abierta": al cerrarla el provider se libera.
      screen = c.listen(provider, (_, _) {});
      await c.read(provider.future);
      return c.read(provider.notifier);
    }

    test('se suscribe al canal del viaje y se desuscribe al cerrarse', () async {
      await open();
      expect(realtime.watched, [trip.id]);
      expect(realtime.hasListener, isTrue);

      screen.close();
      await pumpEventQueue();
      expect(realtime.hasListener, isFalse);
    });

    test('al (re)conectar el canal se vuelve a pedir /live', () async {
      await open();
      final before = api.liveCalls;

      realtime.emit(const RealtimeConnected());
      await pumpEventQueue();

      expect(api.liveCalls, greaterThan(before));
    });

    test('una cancelación avisa con el motivo y refresca', () async {
      await open();
      final before = api.liveCalls;

      realtime.emit(const RealtimeStatusChanged(status: 'Cancelled', reason: 'Paro'));
      await pumpEventQueue();

      expect(notices, hasLength(1));
      expect(notices.single.kind, TripNoticeKind.tripCancelled);
      expect(notices.single.reason, 'Paro');
      expect(api.liveCalls, greaterThan(before));
    });

    test('otros cambios de estado refrescan pero no avisan', () async {
      await open();
      final before = api.liveCalls;

      realtime.emit(const RealtimeStatusChanged(status: 'Delayed', reason: 'Tráfico'));
      await pumpEventQueue();

      expect(notices, isEmpty);
      expect(api.liveCalls, greaterThan(before));
    });

    test('la cancelación se avisa una sola vez aunque llegue por dos vías', () async {
      final ctrl = await open();

      realtime.emit(const RealtimeStatusChanged(status: 'Cancelled', reason: 'Paro'));
      await pumpEventQueue();
      api.liveState = _withStatus(api.liveState, 'Cancelled');
      await ctrl.refresh();

      expect(notices, hasLength(1));
    });

    test('sin canal, /live que pasa a Cancelled también avisa', () async {
      final ctrl = await open();

      api.liveState = _withStatus(api.liveState, 'Cancelled');
      await ctrl.refresh();

      expect(notices, hasLength(1));
      expect(notices.single.kind, TripNoticeKind.tripCancelled);
      expect(notices.single.reason, isNull);
    });

    test('que la empresa resuelva el SOS se detecta en /live', () async {
      final ctrl = await open(live: testLive(hasActiveSos: true));
      expect(notices, isEmpty);

      api.liveState = testLive(hasActiveSos: false);
      await ctrl.refresh();

      expect(notices, hasLength(1));
      expect(notices.single.kind, TripNoticeKind.sosResolved);
    });

    test('lanzar un SOS no genera aviso', () async {
      final ctrl = await open();

      api.liveState = testLive(hasActiveSos: true);
      await ctrl.refresh();

      expect(notices, isEmpty);
    });

    test('un mensaje del canal después de cerrar el viaje no rompe nada', () async {
      await open();
      screen.close();
      await pumpEventQueue();

      expect(() => realtime.emit(const RealtimeConnected()), returnsNormally);
      await pumpEventQueue();
    });
  });

  group('Pantalla del viaje', () {
    Future<(FakeTripApi, FakeTripRealtime, List<int>)> pump(
      WidgetTester tester, {
      TripLive? live,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeTripApi(live: live);
      final realtime = FakeTripRealtime();
      final permissionCalls = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: fakeBackend(
            trips: api,
            realtime: realtime,
            notificationPermission: () async => permissionCalls.add(1),
          ),
          child: MaterialApp(home: ActiveTripPage(trip: trip)),
        ),
      );
      await tester.pumpAndSettle();
      return (api, realtime, permissionCalls);
    }

    testWidgets('pide el permiso de notificaciones al abrir el viaje', (tester) async {
      final (_, _, permissionCalls) = await pump(tester);
      expect(permissionCalls, hasLength(1));
    });

    testWidgets('una cancelación muestra un aviso con el motivo', (tester) async {
      final (api, realtime, _) = await pump(tester);

      api.liveState = _withStatus(api.liveState, 'Cancelled');
      realtime.emit(const RealtimeStatusChanged(status: 'Cancelled', reason: 'Paro de transportes'));
      await tester.pumpAndSettle();

      expect(find.text('Viaje cancelado'), findsOneWidget);
      expect(find.textContaining('Paro de transportes'), findsOneWidget);

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.text('Viaje cancelado'), findsNothing);
    });

    testWidgets('el SOS resuelto por la empresa se avisa y se vuelve a poder finalizar', (tester) async {
      final (api, realtime, _) = await pump(tester, live: testLive(hasActiveSos: true));
      expect(find.text('SOS activo · tu empresa fue avisada'), findsOneWidget);

      api.liveState = testLive(hasActiveSos: false);
      // El canal no informa del SOS: llega con el siguiente refresco de /live.
      realtime.emit(const RealtimeConnected());
      await tester.pumpAndSettle();

      expect(find.text('Tu empresa resolvió el SOS. Ya puedes finalizar el viaje.'), findsOneWidget);
      expect(find.text('SOS activo · tu empresa fue avisada'), findsNothing);
    });
  });
}
