import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/trip_execution/domain/model/stop_arrival.dart';
import 'package:rutasegura/trip_execution/domain/model/tracking.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_live.dart';
import 'package:rutasegura/trip_execution/presentation/widgets/stop_arrival_banner.dart';

final now = DateTime.utc(2026, 11, 27, 14);
LiveStop stop({DateTime? reached}) => LiveStop(
  stopId: 'stop-1',
  name: 'Parque de prueba',
  sequence: 1,
  latitude: -12.05,
  longitude: -77.04,
  reachedAt: reached,
);
TripLive live({String status = 'InProgress', DateTime? reached}) => TripLive(
  tripId: 'trip-1',
  status: status,
  isPickup: true,
  studentsOnBoard: 0,
  totalStudents: 1,
  passengers: const [],
  stops: [stop(reached: reached)],
);
GpsReading point({
  double latitude = -12.05,
  double? accuracy = 10,
  DateTime? at,
}) => GpsReading(
  latitude: latitude,
  longitude: -77.04,
  recordedAt: at ?? now,
  accuracyMeters: accuracy,
);

void main() {
  test('precise local GPS announces arrival once, including while Delayed and offline', () {
    final detector = StopArrivalDetector();
    expect(
      detector.detect(live(status: 'Delayed'), point(), now)?.stopId,
      'stop-1',
    );
    expect(detector.detect(live(status: 'Delayed'), point(), now), null);
  });
  test('distant GPS cannot claim arrival or change the manual stop', () {
    final detector = StopArrivalDetector();
    final snapshot = live();
    expect(detector.detect(snapshot, point(latitude: -12.06), now), null);
    expect(snapshot.stops.single.reachedAt, null);
    expect(detector.detect(snapshot, point(), now)?.stopId, 'stop-1');
    expect(
      snapshot.stops.single.reachedAt,
      null,
    ); // A hint is not a state transition.
  });
  test('old, future, inaccurate and unknown-accuracy GPS do not produce false arrivals', () {
    for (final reading in [
      point(at: now.subtract(const Duration(minutes: 1))),
      point(at: now.add(const Duration(minutes: 1))),
      point(accuracy: 80),
      point(accuracy: null),
    ]) {
      expect(StopArrivalDetector().detect(live(), reading, now), null);
    }
  });
  test(
    'completion and previously reached/restored stops do not generate arrivals',
    () {
      expect(
        StopArrivalDetector().detect(live(status: 'Completed'), point(), now),
        null,
      );
      expect(
        StopArrivalDetector().detect(live(reached: now), point(), now),
        null,
      );
      expect(
        StopArrivalDetector(seen: ['stop-1']).detect(live(), point(), now),
        null,
      );
    },
  );
  testWidgets(
    'arrival banner shows student name and allows dismissal without a modal',
    (tester) async {
      var opened = 0;
      var dismissed = 0;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: StopArrivalBanner(
                stopName: 'Parque de prueba',
                studentNames: const ['Alumno Uno'],
                onDismiss: () => dismissed++,
                onStudents: () => opened++,
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Has llegado a la parada de Alumno Uno'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ver alumnos'));
      await tester.tap(find.byTooltip('Cerrar aviso de llegada'));
      expect(opened, 1);
      expect(dismissed, 1);
      expect(tester.takeException(), null);
    },
  );
}
