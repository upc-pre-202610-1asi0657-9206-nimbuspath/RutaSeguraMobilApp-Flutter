/// Lectura GPS que se envía a `POST /tracking/positions`.
class GpsReading {
  const GpsReading({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracyMeters,
    this.speedKmh,
    this.headingDegrees,
  });

  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final double? accuracyMeters;
  final double? speedKmh;
  final double? headingDegrees;

  /// Límites de §3.7.d: el servidor ignora (sin fallar) lo que los supere;
  /// la app lo descarta antes para ahorrar datos.
  static const maxAccuracyMeters = 100.0;
  static const maxSpeedKmh = 150.0;
  static const maxFutureSkew = Duration(minutes: 2);

  bool isUsable(DateTime now) {
    if (latitude == 0 && longitude == 0) return false;
    if ((accuracyMeters ?? 0) > maxAccuracyMeters) return false;
    if ((speedKmh ?? 0) > maxSpeedKmh) return false;
    if (recordedAt.isAfter(now.add(maxFutureSkew))) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
        if (speedKmh != null) 'speedKmh': speedKmh,
        if (headingDegrees != null) 'headingDegrees': headingDegrees,
      };
}

/// Respuesta de `POST /tracking/positions`.
class PositionsResult {
  const PositionsResult({
    required this.accepted,
    required this.ignored,
    required this.rejected,
  });

  final int accepted;
  final int ignored;
  final int rejected;

  factory PositionsResult.fromJson(Map<String, dynamic> j) => PositionsResult(
        accepted: (j['accepted'] as num?)?.toInt() ?? 0,
        ignored: (j['ignored'] as num?)?.toInt() ?? 0,
        rejected: (j['rejected'] as num?)?.toInt() ?? 0,
      );
}
