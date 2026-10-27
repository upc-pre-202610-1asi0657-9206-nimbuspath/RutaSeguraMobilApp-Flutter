import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_live.dart';
import 'package:rutasegura/trip_execution/presentation/pages/active_trip_page.dart';
import 'package:rutasegura/trip_execution/presentation/pages/report_incident_page.dart';
import 'package:rutasegura/trip_execution/presentation/pages/sos_page.dart';

import '../support/fakes.dart';

const _offline = ApiError(kind: ApiErrorKind.network);

/// [settle] en falso para pantallas con animaciones infinitas (SOS).
Future<void> _pump(
  WidgetTester tester,
  Widget page,
  FakeTripApi api, {
  bool settle = true,
}) async {
  // Pantalla alta: el formulario de incidente cabe sin desplazarse.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: fakeBackend(trips: api),
      child: MaterialApp(home: page),
    ),
  );
  settle ? await tester.pumpAndSettle() : await tester.pump(const Duration(milliseconds: 100));
}

/// Viaje con todos registrados: se puede finalizar.
FakeTripApi _readyToFinish() => FakeTripApi(
      live: testLive(passengers: [
        testPassenger('s1', status: PassengerStatus.boarded),
        testPassenger('s2', status: PassengerStatus.absent, absenceSource: 'Guardian'),
      ]),
    )..summaryData = TripSummaryData(
        startedAt: DateTime.utc(2026, 10, 27, 11, 41),
        completedAt: DateTime.utc(2026, 10, 27, 12, 53),
        delivered: 17,
        absent: [testPassenger('s2', status: PassengerStatus.absent, absenceSource: 'Guardian')],
        incidents: [
          SummaryIncident(
            type: 'HeavyTraffic',
            occurredAt: DateTime.utc(2026, 10, 27, 12, 10),
          ),
        ],
      );

void main() {
  final trip = testTrip(status: 'InProgress');

  group('Incidente', () {
    testWidgets('se envía con su tipo, detalle y el aviso a los padres', (tester) async {
      final api = FakeTripApi();
      await _pump(tester, ReportIncidentPage(trip: trip), api);

      expect(find.text('Elige qué pasó para enviar'), findsOneWidget);
      await tester.tap(find.text('Tráfico intenso'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Choque en Av. Benavides');
      await tester.tap(find.text('Avisar a los padres de la ruta'));
      await tester.pump();
      await tester.tap(find.text('Enviar reporte'));
      await tester.pumpAndSettle();

      expect(api.incidents, ['HeavyTraffic|Choque en Av. Benavides|false']);
    });

    testWidgets('"Otro" exige detalle', (tester) async {
      final api = FakeTripApi();
      await _pump(tester, ReportIncidentPage(trip: trip), api);

      await tester.tap(find.text('Otro'));
      await tester.pump();
      expect(find.text('Cuéntanos qué pasó para enviar'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Llanta baja');
      await tester.pump();
      expect(find.text('Enviar reporte'), findsOneWidget);
    });

    testWidgets('si falla muestra el error y no cierra la pantalla', (tester) async {
      final api = FakeTripApi()..incidentError = _offline;
      await _pump(tester, ReportIncidentPage(trip: trip), api);

      await tester.tap(find.text('Accidente'));
      await tester.pump();
      await tester.tap(find.text('Enviar reporte'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No hay conexión'), findsOneWidget);
      expect(find.byType(ReportIncidentPage), findsOneWidget);
      expect(api.incidents, isEmpty);
    });
  });

  group('SOS', () {
    Future<void> countdown(WidgetTester tester) async {
      await tester.tap(find.text('SOS'));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
    }

    testWidgets('cancelar durante la cuenta no llama al backend', (tester) async {
      final api = FakeTripApi();
      await _pump(tester, SosPage(trip: trip), api, settle: false);

      await tester.tap(find.text('SOS'));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Cancelar'));
      await tester.pump(const Duration(seconds: 6));

      expect(api.sosEvents, isEmpty);
    });

    testWidgets('al terminar la cuenta envía el SOS una vez', (tester) async {
      final api = FakeTripApi();
      await _pump(tester, SosPage(trip: trip), api, settle: false);

      await countdown(tester);
      await tester.pump();

      expect(api.sosEvents, hasLength(1));
      expect(find.text('Alerta enviada'), findsOneWidget);
    });

    testWidgets('sin red reintenta con el mismo clientEventId hasta lograrlo', (tester) async {
      final api = FakeTripApi()..sosError = _offline;
      await _pump(tester, SosPage(trip: trip), api, settle: false);

      await countdown(tester);
      expect(find.text('Enviando alerta'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Reintentando'), findsOneWidget);
      expect(api.sosEvents, isEmpty);

      api.sosError = null;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(api.sosEvents, hasLength(1));
      expect(find.text('Alerta enviada'), findsOneWidget);
    });

    testWidgets('un rechazo de negocio no se reintenta y se explica', (tester) async {
      final api = FakeTripApi()
        ..sosError = const ApiError(
          kind: ApiErrorKind.http,
          status: 422,
          code: 'TRIP_NOT_ACTIVE',
          detail: 'El viaje no está en curso.',
        );
      await _pump(tester, SosPage(trip: trip), api, settle: false);

      await countdown(tester);
      await tester.pump();

      expect(find.text('Enviando alerta'), findsNothing);
      expect(find.text('SOS'), findsOneWidget); // vuelve a estar disponible
    });
  });

  group('Finalizar', () {
    Future<void> tapFinish(WidgetTester tester) async {
      await tester.tap(find.text('Finalizar viaje'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sí, finalizar'));
      await tester.pumpAndSettle();
    }

    testWidgets('llama a /complete y muestra el resumen del servidor', (tester) async {
      final api = _readyToFinish();
      await _pump(tester, ActiveTripPage(trip: trip), api);

      await tapFinish(tester);

      expect(api.completeEvents, hasLength(1));
      expect(find.text('Viaje finalizado'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      expect(find.textContaining('1 incidente reportado'), findsOneWidget);
      expect(find.textContaining('aviso del apoderado'), findsOneWidget);
    });

    testWidgets('si /complete falla se queda en el viaje y reintenta con el mismo id', (tester) async {
      final api = _readyToFinish()..completeError = _offline;
      await _pump(tester, ActiveTripPage(trip: trip), api);

      await tapFinish(tester);
      expect(find.text('Viaje finalizado'), findsNothing);
      expect(find.textContaining('No hay conexión'), findsOneWidget);

      api.completeError = null;
      await tester.pump(const Duration(seconds: 5)); // deja pasar el aviso
      await tapFinish(tester);

      expect(find.text('Viaje finalizado'), findsOneWidget);
      expect(api.completeEvents, hasLength(2));
      expect(api.completeEvents[0], api.completeEvents[1]);
    });

    testWidgets('si no se puede leer el resumen usa lo que ya sabía', (tester) async {
      final api = _readyToFinish()..summaryData = null;
      await _pump(tester, ActiveTripPage(trip: trip), api);

      await tapFinish(tester);

      expect(find.text('Viaje finalizado'), findsOneWidget);
      expect(find.text('1'), findsWidgets); // 1 a bordo entregado
    });

    testWidgets('con un SOS activo no deja finalizar', (tester) async {
      final api = FakeTripApi(
        live: testLive(
          passengers: [testPassenger('s1', status: PassengerStatus.boarded)],
          hasActiveSos: true,
        ),
      );
      await _pump(tester, ActiveTripPage(trip: trip), api);

      expect(find.text('SOS activo · tu empresa fue avisada'), findsOneWidget);
      await tester.tap(find.text('Finalizar viaje'));
      await tester.pumpAndSettle();

      expect(find.textContaining('SOS activo: tu empresa debe resolverlo'), findsOneWidget);
      expect(api.completeEvents, isEmpty);
    });
  });
}
