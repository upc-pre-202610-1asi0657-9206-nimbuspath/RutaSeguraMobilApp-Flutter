/// Modelos del bounded context Trip Execution (vista del conductor).
library;

enum TripKind { pickup, dropOff }

extension TripKindLabel on TripKind {
  String get label => this == TripKind.pickup ? 'recojo' : 'retorno';
  String get longLabel =>
      this == TripKind.pickup ? 'Recojo de la mañana' : 'Retorno de la tarde';
}

/// Viaje programado para el conductor.
class ScheduledTrip {
  const ScheduledTrip({
    required this.id,
    required this.routeName,
    required this.kind,
    required this.destination,
    required this.departure,
    required this.stopsCount,
    required this.studentsCount,
    required this.vehiclePlate,
    this.schedule = 'Lunes a viernes',
  });

  final String id;
  final String routeName;
  final TripKind kind;
  final String destination;
  final String departure; // "6:40"
  final int stopsCount;
  final int studentsCount;
  final String vehiclePlate;
  final String schedule;

  String get title => '$routeName, ${kind.label}';
}

class Student {
  const Student({
    required this.id,
    required this.fullName,
    required this.grade,
    this.guardianNotice,
  });

  final String id;
  final String fullName;
  final String grade;

  /// Aviso del apoderado (ej. "hoy no asiste").
  final String? guardianNotice;

  String get initials {
    final parts = fullName.split(' ');
    return (parts.first[0] + (parts.length > 1 ? parts[1][0] : ''))
        .toUpperCase();
  }
}

class Stop {
  const Stop({
    required this.order,
    required this.address,
    required this.students,
  });

  final int order;
  final String address;
  final List<Student> students;
}

enum BoardingStatus { pending, boarded, absent }

/// Registro de abordaje/descenso de un alumno en una parada.
class BoardingRecord {
  const BoardingRecord({
    required this.student,
    this.status = BoardingStatus.pending,
    this.at,
  });

  final Student student;
  final BoardingStatus status;
  final DateTime? at;

  BoardingRecord copyWith({BoardingStatus? status, DateTime? at}) =>
      BoardingRecord(
        student: student,
        status: status ?? this.status,
        at: at,
      );
}

enum IncidentType {
  heavyTraffic('Tráfico intenso'),
  routeDeviation('Desvío de ruta'),
  vehicleFailure('Falla del vehículo'),
  studentUnwell('Alumno se siente mal'),
  accident('Accidente'),
  other('Otro');

  const IncidentType(this.label);
  final String label;
}

class Incident {
  const Incident({
    required this.type,
    required this.at,
    this.detail,
    this.notifyParents = true,
  });

  final IncidentType type;
  final DateTime at;
  final String? detail;
  final bool notifyParents;
}

/// Resultado mostrado al finalizar el viaje.
class TripSummary {
  const TripSummary({
    required this.trip,
    required this.startedAt,
    required this.endedAt,
    required this.arrivedCount,
    required this.absentStudents,
    required this.incidents,
    this.nextTrip,
  });

  final ScheduledTrip trip;
  final DateTime startedAt;
  final DateTime endedAt;
  final int arrivedCount;
  final List<Student> absentStudents;
  final List<Incident> incidents;
  final ScheduledTrip? nextTrip;
}
