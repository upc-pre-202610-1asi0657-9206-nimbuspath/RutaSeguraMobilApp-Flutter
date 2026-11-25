/// Estado en vivo de un viaje (`GET /trips/{id}/live`): fuente de verdad de
/// "Viaje en curso" y "Registrar abordaje".
library;

enum PassengerStatus { pending, boarded, alighted, absent }

String _passengerStatusName(PassengerStatus s) => switch (s) {
      PassengerStatus.pending => 'Pending',
      PassengerStatus.boarded => 'Boarded',
      PassengerStatus.alighted => 'Alighted',
      PassengerStatus.absent => 'Absent',
    };

PassengerStatus _passengerStatus(String? s) => switch (s) {
      'Boarded' => PassengerStatus.boarded,
      'Alighted' => PassengerStatus.alighted,
      'Absent' => PassengerStatus.absent,
      _ => PassengerStatus.pending,
    };

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

class LivePassenger {
  const LivePassenger({
    required this.studentId,
    required this.stopId,
    required this.status,
    this.boardedAt,
    this.alightedAt,
    this.absenceSource,
    this.absenceNote,
  });

  final String studentId;
  final String? stopId;
  final PassengerStatus status;
  final DateTime? boardedAt;
  final DateTime? alightedAt;

  /// `Driver` | `Guardian` (solo si [status] es `absent`).
  final String? absenceSource;
  final String? absenceNote;

  bool get absentByGuardian => absenceSource == 'Guardian';

  LivePassenger copyWith({
    PassengerStatus? status,
    DateTime? boardedAt,
    DateTime? alightedAt,
    String? absenceSource,
    bool clearTimes = false,
  }) =>
      LivePassenger(
        studentId: studentId,
        stopId: stopId,
        status: status ?? this.status,
        boardedAt: clearTimes ? null : boardedAt ?? this.boardedAt,
        alightedAt: clearTimes ? null : alightedAt ?? this.alightedAt,
        absenceSource: clearTimes ? null : absenceSource ?? this.absenceSource,
        absenceNote: clearTimes ? null : absenceNote,
      );

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'stopId': stopId,
        'status': _passengerStatusName(status),
        'boardedAt': boardedAt?.toIso8601String(),
        'alightedAt': alightedAt?.toIso8601String(),
        'absenceSource': absenceSource,
        'absenceNote': absenceNote,
      };

  factory LivePassenger.fromJson(Map<String, dynamic> j) => LivePassenger(
        studentId: j['studentId'] as String,
        stopId: j['stopId'] as String?,
        status: _passengerStatus(j['status'] as String?),
        boardedAt: _date(j['boardedAt']),
        alightedAt: _date(j['alightedAt']),
        absenceSource: j['absenceSource'] as String?,
        absenceNote: j['absenceNote'] as String?,
      );
}

class LiveStop {
  const LiveStop({
    required this.stopId,
    required this.name,
    required this.sequence,
    required this.latitude,
    required this.longitude,
    this.reachedAt,
  });

  final String stopId;
  final String name;
  final int sequence;
  final double latitude;
  final double longitude;
  final DateTime? reachedAt;

  Map<String, dynamic> toJson() => {
        'stopId': stopId,
        'name': name,
        'sequence': sequence,
        'latitude': latitude,
        'longitude': longitude,
        'reachedAt': reachedAt?.toIso8601String(),
      };

  factory LiveStop.fromJson(Map<String, dynamic> j) => LiveStop(
        stopId: j['stopId'] as String,
        name: j['name'] as String? ?? '',
        sequence: (j['sequence'] as num).toInt(),
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        reachedAt: _date(j['reachedAt']),
      );
}

class NextStop {
  const NextStop({
    required this.stopId,
    required this.name,
    required this.sequence,
    required this.totalStops,
    this.distanceMeters,
    this.etaMinutes,
  });

  final String stopId;
  final String name;
  final int sequence;
  final int totalStops;
  final int? distanceMeters;
  final int? etaMinutes;

  /// "850 m" o "1,4 km".
  String? get distanceLabel {
    final d = distanceMeters;
    if (d == null) return null;
    if (d < 1000) return '$d m';
    return '${(d / 1000).toStringAsFixed(1).replaceFirst('.', ',')} km';
  }

  Map<String, dynamic> toJson() => {
        'stopId': stopId,
        'name': name,
        'sequence': sequence,
        'totalStops': totalStops,
        'distanceMeters': distanceMeters,
        'etaMinutes': etaMinutes,
      };

  factory NextStop.fromJson(Map<String, dynamic> j) => NextStop(
        stopId: j['stopId'] as String,
        name: j['name'] as String? ?? '',
        sequence: (j['sequence'] as num).toInt(),
        totalStops: (j['totalStops'] as num).toInt(),
        distanceMeters: (j['distanceMeters'] as num?)?.round(),
        etaMinutes: (j['etaMinutes'] as num?)?.round(),
      );
}

class LivePosition {
  const LivePosition({
    required this.latitude,
    required this.longitude,
    this.ageSeconds,
    this.headingDegrees,
  });

  final double latitude;
  final double longitude;
  final int? ageSeconds;
  final double? headingDegrees;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'ageSeconds': ageSeconds,
        'headingDegrees': headingDegrees,
      };

  factory LivePosition.fromJson(Map<String, dynamic> j) => LivePosition(
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        ageSeconds: (j['ageSeconds'] as num?)?.round(),
        headingDegrees: (j['headingDegrees'] as num?)?.toDouble(),
      );
}

typedef ItineraryPoint = ({double latitude, double longitude});

class TripOperationalDetails {
  const TripOperationalDetails(this.names, this.itinerary);

  final Map<String, String> names;
  final List<ItineraryPoint> itinerary;

  factory TripOperationalDetails.fromJson(Map<String, dynamic> json) {
    final geometry = (json['itinerary'] as Map?)?['geometry'] as Map?;
    final coordinates = geometry?['type'] == 'LineString'
        ? (geometry!['coordinates'] as List?)
        : null;
    return TripOperationalDetails(
      {
        for (final student in (json['students'] as List?) ?? const [])
          if (student is Map &&
              student['studentId'] is String &&
              student['fullName'] is String)
            student['studentId'] as String: student['fullName'] as String,
      },
      [
        for (final point in coordinates ?? const [])
          if (point is List &&
              point.length == 2 &&
              point[0] is num &&
              point[1] is num)
            (
              latitude: (point[1] as num).toDouble(),
              longitude: (point[0] as num).toDouble(),
            ),
      ],
    );
  }
}

class TripLive {
  const TripLive({
    required this.tripId,
    required this.status,
    required this.isPickup,
    required this.studentsOnBoard,
    required this.totalStudents,
    required this.passengers,
    required this.stops,
    this.startedAt,
    this.position,
    this.nextStop,
    this.hasActiveSos = false,
    this.plannedItinerary = const [],
  });

  final String tripId;

  /// `InProgress` | `Delayed` | `Completed` | `Cancelled`...
  final String status;
  final bool isPickup;
  final DateTime? startedAt;
  final LivePosition? position;
  final NextStop? nextStop;
  final int studentsOnBoard;
  final int totalStudents;
  final bool hasActiveSos;
  final List<LivePassenger> passengers;
  final List<LiveStop> stops;
  final List<ItineraryPoint> plannedItinerary;

  bool get isActive => status == 'InProgress' || status == 'Delayed';

  /// Alumnos sin registrar.
  int get pendingCount =>
      passengers.where((p) => p.status == PassengerStatus.pending).length;

  List<LivePassenger> passengersAt(String? stopId) => [
    for (final p in passengers)
      if (p.stopId == stopId) p,
  ];

  /// "Suben N alumnos": pendientes de la siguiente parada.
  int get boardingAtNextStop => nextStop == null
      ? 0
      : passengersAt(nextStop!.stopId)
            .where((p) => p.status == PassengerStatus.pending)
            .length;

  bool canAlightAtCurrentOrReachedStop(LivePassenger passenger) =>
      !isPickup &&
      passenger.status == PassengerStatus.boarded &&
      (passenger.stopId == nextStop?.stopId ||
          stop(passenger.stopId)?.reachedAt != null);

  int get alightingAtNextStop => nextStop == null
      ? 0
      : passengersAt(nextStop!.stopId)
            .where((passenger) => passenger.status == PassengerStatus.boarded)
            .length;

  List<LivePassenger> get attendancePassengers => [
    for (final passenger in passengers)
      if (nextStop == null ||
          passenger.stopId == nextStop?.stopId ||
          canAlightAtCurrentOrReachedStop(passenger) ||
          (passenger.status == PassengerStatus.pending &&
              (!isPickup || stop(passenger.stopId)?.reachedAt != null)))
        passenger,
  ];

  LiveStop? stop(String? id) {
    for (final s in stops) {
      if (s.stopId == id) return s;
    }
    return null;
  }

  TripLive withPlannedItinerary(List<ItineraryPoint> itinerary) =>
      withPassengers(passengers, itinerary: itinerary);

  TripLive withPassengers(
    List<LivePassenger> next, {
    List<ItineraryPoint>? itinerary,
  }) => TripLive(
    tripId: tripId,
    status: status,
    isPickup: isPickup,
    startedAt: startedAt,
    position: position,
    nextStop: nextStop,
    studentsOnBoard: next
        .where((p) => p.status == PassengerStatus.boarded)
        .length,
    totalStudents: totalStudents,
    hasActiveSos: hasActiveSos,
    passengers: next,
    stops: stops,
    plannedItinerary: itinerary ?? plannedItinerary,
  );

  /// Mismo formato que el backend (para la caché del último `/live`).
  Map<String, dynamic> toJson() => {
    'tripId': tripId,
    'status': status,
    'direction': isPickup ? 'Pickup' : 'Return',
    'startedAt': startedAt?.toIso8601String(),
    'position': position?.toJson(),
    'nextStop': nextStop?.toJson(),
    'studentsOnBoard': studentsOnBoard,
    'totalStudents': totalStudents,
    'hasActiveSos': hasActiveSos,
    'passengers': [for (final p in passengers) p.toJson()],
    'stops': [for (final s in stops) s.toJson()],
  };

  factory TripLive.fromJson(Map<String, dynamic> j) {
    final stops = [
      for (final s in (j['stops'] as List?) ?? const [])
        LiveStop.fromJson(s as Map<String, dynamic>),
    ]..sort((a, b) => a.sequence.compareTo(b.sequence));
    return TripLive(
      tripId: j['tripId'] as String,
      status: j['status'] as String? ?? 'InProgress',
      isPickup: j['direction'] != 'Return',
      startedAt: _date(j['startedAt']),
      position: j['position'] == null
          ? null
          : LivePosition.fromJson(j['position'] as Map<String, dynamic>),
      nextStop: j['nextStop'] == null
          ? null
          : NextStop.fromJson(j['nextStop'] as Map<String, dynamic>),
      studentsOnBoard: (j['studentsOnBoard'] as num?)?.toInt() ?? 0,
      totalStudents: (j['totalStudents'] as num?)?.toInt() ?? 0,
      hasActiveSos: j['hasActiveSos'] as bool? ?? false,
      passengers: [
        for (final p in (j['passengers'] as List?) ?? const [])
          LivePassenger.fromJson(p as Map<String, dynamic>),
      ],
      stops: stops,
    );
  }
}

/// Resumen del viaje terminado (`GET /trips/{id}/summary`).
class TripSummaryData {
  const TripSummaryData({
    required this.startedAt,
    required this.completedAt,
    required this.delivered,
    required this.absent,
    required this.incidents,
  });

  final DateTime? startedAt;
  final DateTime? completedAt;

  /// Alumnos entregados (recojo: llegaron al colegio; retorno: a casa).
  final int delivered;
  final List<LivePassenger> absent;
  final List<SummaryIncident> incidents;

  factory TripSummaryData.fromJson(Map<String, dynamic> j) => TripSummaryData(
        startedAt: _date(j['startedAt']),
        completedAt: _date(j['completedAt']),
        delivered: (j['delivered'] as num?)?.toInt() ?? 0,
        absent: [
          for (final p in (j['absent'] as List?) ?? const [])
            LivePassenger.fromJson(p as Map<String, dynamic>),
        ],
        incidents: [
          for (final i in (j['incidents'] as List?) ?? const [])
            SummaryIncident.fromJson(i as Map<String, dynamic>),
        ],
      );
}

class SummaryIncident {
  const SummaryIncident({required this.type, required this.occurredAt, this.detail});

  /// `HeavyTraffic`, `Accident`...
  final String? type;
  final DateTime? occurredAt;
  final String? detail;

  factory SummaryIncident.fromJson(Map<String, dynamic> j) => SummaryIncident(
        type: j['type'] as String?,
        occurredAt: _date(j['occurredAt']),
        detail: j['detail'] as String?,
      );
}
