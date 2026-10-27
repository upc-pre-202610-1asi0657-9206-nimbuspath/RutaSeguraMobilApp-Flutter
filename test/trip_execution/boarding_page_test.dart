import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/trip_execution/application/tracking_engine.dart';
import 'package:rutasegura/trip_execution/presentation/pages/active_trip_page.dart';
import 'package:rutasegura/trip_execution/presentation/pages/boarding_page.dart';

import '../support/fakes.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  FakeTripApi api, {
  FakePositionSource? gps,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: fakeBackend(trips: api, gps: gps),
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final trip = testTrip(status: 'InProgress');

  testWidgets('abordaje: registrar a todos habilita "Confirmar parada"', (tester) async {
    final api = FakeTripApi();
    await _pump(tester, BoardingPage(trip: trip), api);

    expect(find.text('Faltan registrar 2 alumnos'), findsOneWidget);
    expect(find.text('Av. Primavera 1240'), findsOneWidget);

    await tester.tap(find.text('Subió').first);
    await tester.pumpAndSettle();
    expect(find.text('Faltan registrar 1 alumno'), findsOneWidget);

    await tester.tap(find.text('No vino').first);
    await tester.pumpAndSettle();
    expect(find.text('Confirmar parada'), findsOneWidget);
    expect(api.actions, hasLength(2));
  });

  testWidgets('abordaje: un rechazo del servidor se muestra y no cambia la fila', (tester) async {
    final api = FakeTripApi()..actionError = _rejected;
    await _pump(tester, BoardingPage(trip: trip), api);

    await tester.tap(find.text('Subió').first);
    await tester.pump();
    await tester.pump();

    expect(find.text('Faltan registrar 2 alumnos'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('viaje en curso: muestra siguiente parada, ETA y avance', (tester) async {
    await _pump(tester, ActiveTripPage(trip: trip), FakeTripApi());

    expect(find.text('Siguiente parada, 1 de 2'), findsOneWidget);
    expect(find.text('Av. Primavera 1240'), findsOneWidget);
    expect(find.text('850 m'), findsOneWidget);
    expect(find.text('Suben 2 alumnos'), findsOneWidget);
    expect(find.text('0 de 2'), findsOneWidget);
    expect(find.byKey(const Key('fake-map')), findsOneWidget);
  });

  testWidgets('viaje en curso: no deja finalizar con alumnos pendientes', (tester) async {
    await _pump(tester, ActiveTripPage(trip: trip), FakeTripApi());

    await tester.tap(find.text('Finalizar viaje'));
    await tester.pumpAndSettle();

    expect(find.text('Faltan registrar 2 alumnos.'), findsOneWidget);
    expect(find.text('¿Finalizar el viaje?'), findsNothing);
  });

  testWidgets('viaje en curso: comparte la ubicación y la detiene al salir', (tester) async {
    final gps = FakePositionSource();
    await _pump(tester, ActiveTripPage(trip: trip), FakeTripApi(), gps: gps);

    expect(gps.hasListener, isTrue);
    expect(find.text('Compartiendo ubicación'), findsOneWidget);
    expect(find.text('esperando GPS'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(gps.hasListener, isFalse);
  });

  testWidgets('sin permiso de ubicación se avisa en la pantalla', (tester) async {
    final gps = FakePositionSource(permission: TrackingPermission.denied);
    await _pump(tester, ActiveTripPage(trip: trip), FakeTripApi(), gps: gps);

    expect(find.text('Ubicación sin permiso'), findsOneWidget);
    expect(gps.hasListener, isFalse);
  });

  testWidgets('si el inicio falla se ofrece reintentar', (tester) async {
    final api = FakeTripApi()
      ..startError = const ApiError(kind: ApiErrorKind.network);
    await _pump(tester, ActiveTripPage(trip: testTrip()), api);

    expect(find.text('Reintentar'), findsOneWidget);
    api.startError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Siguiente parada, 1 de 2'), findsOneWidget);
    expect(api.startedWith.toSet(), hasLength(1));
  });
}

const _rejected = ApiError(
  kind: ApiErrorKind.http,
  status: 422,
  code: 'PASSENGER_INVALID_TRANSITION',
);
