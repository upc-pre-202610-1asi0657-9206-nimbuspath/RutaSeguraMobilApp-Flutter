/// Modelos del bounded context Trip Execution (vista del conductor).
library;

import '../../../core/utils/date_format.dart';

enum TripKind { pickup, dropOff }

extension TripKindLabel on TripKind {
  String get label => this == TripKind.pickup ? 'recojo' : 'retorno';
  String get longLabel => this == TripKind.pickup ? 'Recojo' : 'Retorno';
}

/// Viaje programado para el conductor (`GET /drivers/me/trips`).
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
    this.routeId,
    this.vehicleId,
    this.scheduledStart,
    this.status = 'Scheduled',
  });

  final String id;
  final String routeName;
  final TripKind kind;
  final String destination;
  final String departure; // "6:40" (hora de Lima)
  final int stopsCount;
  final int studentsCount;
  final String vehiclePlate;
  final String schedule;
  final String? routeId;
  final String? vehicleId;

  /// Instante programado de salida. `null` solo en los datos simulados.
  final DateTime? scheduledStart;

  /// `Scheduled` | `InProgress` | `Delayed` | `Completed`.
  final String status;

  String get title => '$routeName, ${kind.label}';

  /// Hay un viaje ya iniciado que se debe retomar.
  bool get isInProgress => status == 'InProgress' || status == 'Delayed';
  bool get isCompleted => status == 'Completed';

  /// El backend permite iniciar hasta 60 min antes de la hora programada.
  static const startWindow = Duration(minutes: 60);

  DateTime? get startWindowOpensAt => scheduledStart?.subtract(startWindow);

  /// "Disponible desde 5:40" (hora de Lima).
  String? get startWindowOpensAtLabel {
    final opens = startWindowOpensAt;
    return opens == null ? null : DateFmt.time(DateFmt.toLima(opens));
  }

  bool canStart(DateTime now) {
    if (isInProgress) return true;
    if (status != 'Scheduled') return false;
    final opens = startWindowOpensAt;
    return opens == null || !now.isBefore(opens);
  }

  factory ScheduledTrip.fromJson(Map<String, dynamic> json) {
    final start = DateTime.parse(json['scheduledStart'] as String).toUtc();
    final kind = json['direction'] == 'Return' ? TripKind.dropOff : TripKind.pickup;
    return ScheduledTrip(
      id: json['tripId'] as String,
      routeId: json['routeId'] as String?,
      routeName: json['routeName'] as String? ?? '',
      kind: kind,
      destination: kind == TripKind.pickup ? 'el colegio' : 'las casas',
      departure: DateFmt.time(DateFmt.toLima(start)),
      stopsCount: (json['stopCount'] as num?)?.toInt() ?? 0,
      studentsCount: (json['studentCount'] as num?)?.toInt() ?? 0,
      vehicleId: json['vehicleId'] as String?,
      vehiclePlate: json['vehiclePlate'] as String? ?? '—',
      scheduledStart: start,
      status: json['status'] as String? ?? 'Scheduled',
    );
  }

  /// Mismo formato que el backend más `vehiclePlate` (para la caché local).
  Map<String, dynamic> toJson() => {
        'tripId': id,
        'routeId': routeId,
        'routeName': routeName,
        'direction': kind == TripKind.pickup ? 'Pickup' : 'Return',
        'scheduledStart': scheduledStart?.toIso8601String(),
        'status': status,
        'vehicleId': vehicleId,
        'vehiclePlate': vehiclePlate,
        'stopCount': stopsCount,
        'studentCount': studentsCount,
      };

  ScheduledTrip withVehiclePlate(String plate) => ScheduledTrip(
        id: id,
        routeName: routeName,
        kind: kind,
        destination: destination,
        departure: departure,
        stopsCount: stopsCount,
        studentsCount: studentsCount,
        vehiclePlate: plate,
        schedule: schedule,
        routeId: routeId,
        vehicleId: vehicleId,
        scheduledStart: scheduledStart,
        status: status,
      );
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

enum BoardingStatus { pending, boarded, alighted, absent }

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
  heavyTraffic('Tráfico intenso', 'HeavyTraffic'),
  routeDeviation('Desvío de ruta', 'RouteDeviation'),
  vehicleFailure('Falla del vehículo', 'VehicleFailure'),
  studentUnwell('Alumno se siente mal', 'StudentUnwell'),
  accident('Accidente', 'Accident'),
  other('Otro', 'Other');

  const IncidentType(this.label, this.apiName);
  final String label;

  /// Valor de `incidentType` en el backend.
  final String apiName;

  /// "Otro" exige un detalle (INCIDENT_DETAIL_REQUIRED).
  bool get requiresDetail => this == other;

  static IncidentType? fromApi(String? name) {
    for (final t in values) {
      if (t.apiName == name) return t;
    }
    return null;
  }
}

/// Máximo de caracteres del detalle de un incidente.
const incidentDetailMaxLength = 500;

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
