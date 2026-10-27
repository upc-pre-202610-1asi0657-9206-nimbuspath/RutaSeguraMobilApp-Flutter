/// Estado en vivo de un viaje (`GET /trips/{id}/live`): fuente de verdad de
/// "Viaje en curso" y "Registrar abordaje".
library;

enum PassengerStatus { pending, boarded, alighted, absent }

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

  factory LivePosition.fromJson(Map<String, dynamic> j) => LivePosition(
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        ageSeconds: (j['ageSeconds'] as num?)?.round(),
        headingDegrees: (j['headingDegrees'] as num?)?.toDouble(),
      );
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

  bool get isActive => status == 'InProgress' || status == 'Delayed';

  /// Alumnos sin registrar.
  int get pendingCount =>
      passengers.where((p) => p.status == PassengerStatus.pending).length;

  List<LivePassenger> passengersAt(String? stopId) =>
      [for (final p in passengers) if (p.stopId == stopId) p];

  /// "Suben N alumnos": pendientes de la siguiente parada.
  int get boardingAtNextStop => nextStop == null
      ? 0
      : passengersAt(nextStop!.stopId)
          .where((p) => p.status == PassengerStatus.pending)
          .length;

  LiveStop? stop(String? id) {
    for (final s in stops) {
      if (s.stopId == id) return s;
    }
    return null;
  }

  TripLive withPassengers(List<LivePassenger> next) => TripLive(
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
      );

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
