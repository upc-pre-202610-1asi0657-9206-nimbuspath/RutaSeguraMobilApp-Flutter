import '../domain/model/trip_models.dart';

/// Datos simulados de viajes para la fase visual.
/// Se reemplazará por el cliente del Trip & Tracking Service.
abstract final class MockTripRepository {
  static const morningTrip = ScheduledTrip(
    id: 'trip-r3-am',
    routeName: 'Ruta 3',
    kind: TripKind.pickup,
    destination: 'Colegio San Agustín',
    departure: '6:40',
    stopsCount: 7,
    studentsCount: 18,
    vehiclePlate: 'ABC-123',
  );

  static const afternoonTrip = ScheduledTrip(
    id: 'trip-r3-pm',
    routeName: 'Ruta 3',
    kind: TripKind.dropOff,
    destination: 'Colegio San Agustín a casas',
    departure: '13:30',
    stopsCount: 7,
    studentsCount: 18,
    vehiclePlate: 'ABC-123',
  );

  static const myRoutes = [morningTrip, afternoonTrip];

  /// Alumnos ya a bordo antes de la parada actual.
  static const onBoardBeforeCurrentStop = 9;

  /// Paradas pendientes desde la 4 de 7 (9 + 4 + 3 + 2 = 18 alumnos).
  static const remainingStops = [
    Stop(
      order: 4,
      address: 'Av. Primavera 1240',
      students: [
        Student(id: 's1', fullName: 'Valeria Quispe', grade: '3.° de primaria'),
        Student(id: 's2', fullName: 'Mateo Rojas', grade: '1.° de secundaria'),
        Student(
          id: 's3',
          fullName: 'Camila Huamán',
          grade: '5.° de primaria',
          guardianNotice: 'Su apoderado avisó que hoy no asiste.',
        ),
        Student(id: 's4', fullName: 'Diego Paredes', grade: '2.° de primaria'),
      ],
    ),
    Stop(
      order: 5,
      address: 'Jr. Las Begonias 455',
      students: [
        Student(id: 's5', fullName: 'Lucía Fernández', grade: '4.° de primaria'),
        Student(id: 's6', fullName: 'Sebastián Torres', grade: '6.° de primaria'),
        Student(id: 's7', fullName: 'Ana Chávez', grade: '2.° de secundaria'),
      ],
    ),
    Stop(
      order: 6,
      address: 'Calle Los Pinos 210',
      students: [
        Student(id: 's8', fullName: 'Thiago Ramírez', grade: '1.° de primaria'),
        Student(id: 's9', fullName: 'Isabella Castro', grade: '3.° de secundaria'),
      ],
    ),
  ];
}
