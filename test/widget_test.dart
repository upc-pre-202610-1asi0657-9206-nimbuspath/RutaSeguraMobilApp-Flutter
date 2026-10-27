import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/core/storage/token_storage.dart';
import 'package:rutasegura/main.dart';

import 'support/fakes.dart';

/// Pantalla de teléfono (393×852 lógicos) en vez de los 800×600 por defecto.
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('Inicio muestra el próximo viaje y el botón Iniciar viaje',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(),
        child: const RutaSeguraDriverApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Jorge'), findsOneWidget);
    expect(find.text('Ruta 3'), findsOneWidget);
    expect(find.text('Iniciar viaje'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Antes de salir'), 300);
    expect(find.text('Antes de salir'), findsOneWidget);
  });

  testWidgets('La barra inferior cambia a Perfil', (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(),
        child: const RutaSeguraDriverApp(),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Conductor en Transportes Santa Rosa'), findsOneWidget);
    expect(find.text('ABC-123'), findsOneWidget);
    expect(find.text('Toyota Coaster'), findsOneWidget);
    expect(find.textContaining('Lunes a viernes'), findsOneWidget);
    expect(find.text('Vehículo asignado'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Cerrar sesión'), 300);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('Perfil sin registro en el Roster muestra el aviso y reintentar',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(
          roster: FakeRosterApi(
            error: const ApiError(
              kind: ApiErrorKind.http,
              status: 404,
              code: ApiErrorCodes.driverNotFound,
            ),
          ),
        ),
        child: const RutaSeguraDriverApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Tu empresa aún no completó tu registro.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('Sin sesión muestra el login; ingresar lleva a Inicio y cerrar '
      'sesión regresa', (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(storage: InMemoryTokenStorage()),
        child: const RutaSeguraDriverApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Correo'), findsOneWidget);
    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    expect(find.text('Escribe tu correo y tu contraseña.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'jorge@santarosa.pe');
    await tester.enterText(find.byType(TextField).last, 'Password123');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar viaje'), findsOneWidget);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cerrar sesión'), 300);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Correo'), findsOneWidget);
  });

  testWidgets('Inicio muestra el checklist con las lecturas del dispositivo',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(overrides: fakeBackend(), child: const RutaSeguraDriverApp()),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('GPS activado'), 300);
    expect(find.text('GPS activado'), findsOneWidget);
    expect(find.text('Precisión de 8 m'), findsOneWidget);
    expect(find.text('Datos móviles con señal'), findsOneWidget);
    expect(find.text('Batería al 34 %'), findsOneWidget);
  });

  testWidgets('Fuera de la ventana de 60 min "Iniciar viaje" está deshabilitado',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(
          trips: FakeTripApi(trips: [testTrip(startsIn: const Duration(hours: 3))]),
        ),
        child: const RutaSeguraDriverApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Disponible desde'), findsOneWidget);
    await tester.tap(find.text('Iniciar viaje'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar abordaje'), findsNothing);
  });

  testWidgets('Sin viajes hoy lo dice; los siguientes van en "Más tarde hoy"',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(trips: FakeTripApi(trips: const [])),
        child: const RutaSeguraDriverApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No tienes viajes programados para hoy.'), findsOneWidget);
  });

  testWidgets('Más tarde hoy lista el resto de viajes', (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(
          trips: FakeTripApi(trips: [
            testTrip(),
            testTrip(id: 't2', direction: 'Return', startsIn: const Duration(hours: 6)),
          ]),
        ),
        child: const RutaSeguraDriverApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Más tarde hoy'), 300);
    expect(find.text('Más tarde hoy'), findsOneWidget);
    expect(find.text('Ruta 3, retorno'), findsOneWidget);
  });

  testWidgets('Si la agenda falla muestra el error y Reintentar la recarga',
      (tester) async {
    _usePhoneScreen(tester);
    final api = FakeTripApi()..error = const ApiError(kind: ApiErrorKind.network);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(trips: api),
        child: const RutaSeguraDriverApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay conexión'), findsOneWidget);

    api.error = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar viaje'), findsOneWidget);
  });

  testWidgets('Un viaje en curso se retoma solo al abrir la app',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(
          trips: FakeTripApi(
            trips: [testTrip(status: 'InProgress', startsIn: const Duration(minutes: -20))],
          ),
        ),
        child: const RutaSeguraDriverApp(),
      ),
    );
    // "Viaje en curso" tiene una animación infinita: no usar pumpAndSettle.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Registrar abordaje'), findsOneWidget);
  });

  testWidgets('Iniciar viaje abre la pantalla de viaje en curso',
      (tester) async {
    _usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: fakeBackend(),
        child: const RutaSeguraDriverApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Iniciar viaje'));
    await tester.pump(); // inicia la transición
    await tester.pump(const Duration(milliseconds: 600)); // la termina

    expect(find.text('Registrar abordaje'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
