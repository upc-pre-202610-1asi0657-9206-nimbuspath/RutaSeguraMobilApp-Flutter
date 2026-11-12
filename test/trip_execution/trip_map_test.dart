import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_live.dart';
import 'package:rutasegura/trip_execution/presentation/widgets/trip_map.dart';

import '../support/fakes.dart';

/// [testLive] con el vehículo en [at].
TripLive _withVehicle(TripLive l, LatLng at) => TripLive(
      tripId: l.tripId,
      status: l.status,
      isPickup: l.isPickup,
      startedAt: l.startedAt,
      position: LivePosition(latitude: at.latitude, longitude: at.longitude),
      nextStop: l.nextStop,
      studentsOnBoard: l.studentsOnBoard,
      totalStudents: l.totalStudents,
      hasActiveSos: l.hasActiveSos,
      passengers: l.passengers,
      stops: l.stops,
    );

Future<void> _pump(WidgetTester tester, TripLive live) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: TripMap(live: live))),
  );
  await tester.pump();
  await tester.pump();
}

MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(MarkerLayer)));

void main() {
  // Paradas de testLive: a ~1,6 km entre sí.
  const stop1 = LatLng(-12.1, -77.0);
  const stop2 = LatLng(-12.11, -77.01);

  testWidgets('al abrir las paradas quedan dentro de la vista', (tester) async {
    await _pump(tester, testLive());

    final camera = _camera(tester);
    // OJO: este test también pasa con el encuadre anterior (en `onMapReady`).
    // Aquel defecto, que dejaba el zoom en ~1 (todo el mundo), solo se vio en
    // el emulador, donde el mapa aún no tenía tamaño en ese momento.
    expect(camera.zoom, greaterThan(12));
    expect(camera.visibleBounds.contains(stop1), isTrue);
    expect(camera.visibleBounds.contains(stop2), isTrue);
  });

  testWidgets('al aparecer el vehículo vuelve a encuadrar para incluirlo', (tester) async {
    await _pump(tester, testLive());

    // Un vehículo bastante más lejos que las paradas.
    const vehicle = LatLng(-12.05, -76.95);
    expect(_camera(tester).visibleBounds.contains(vehicle), isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TripMap(live: _withVehicle(testLive(), vehicle))),
      ),
    );
    await tester.pump();
    await tester.pump();

    final camera = _camera(tester);
    expect(camera.visibleBounds.contains(vehicle), isTrue);
    expect(camera.visibleBounds.contains(stop1), isTrue);
    expect(camera.visibleBounds.contains(stop2), isTrue);
  });
}
