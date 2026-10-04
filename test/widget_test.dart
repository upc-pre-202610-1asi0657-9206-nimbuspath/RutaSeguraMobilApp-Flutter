import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rutasegura/main.dart';

void main() {
  testWidgets('Inicio muestra el próximo viaje y el botón Iniciar viaje',
      (tester) async {
    await tester.pumpWidget(const RutaSeguraDriverApp());

    expect(find.text('Ruta 3'), findsOneWidget);
    expect(find.text('Iniciar viaje'), findsOneWidget);
    expect(find.text('Antes de salir'), findsOneWidget);
  });

  testWidgets('La barra inferior cambia a Perfil', (tester) async {
    await tester.pumpWidget(const RutaSeguraDriverApp());

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Vehículo asignado'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('Iniciar viaje abre la pantalla de viaje en curso',
      (tester) async {
    await tester.pumpWidget(const RutaSeguraDriverApp());

    await tester.tap(find.text('Iniciar viaje'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Registrar abordaje'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
