import 'dart:math' as math;

import 'tracking.dart';
import 'trip_live.dart';

/// Advisory local geofence; never performs an API action or changes the stop/passenger status.
class StopArrivalDetector {
  StopArrivalDetector({Iterable<String> seen = const []})
    : announced = {...seen};
  final Set<String> announced;
  bool _initialized = false;
  static const radiusMeters = 60.0;

  void initialize(TripLive live) {
    if (_initialized) return;
    _initialized = true;
    announced.addAll(
      live.stops.where((s) => s.reachedAt != null).map((s) => s.stopId),
    );
  }

  LiveStop? detect(TripLive live, GpsReading? reading, DateTime now) {
    initialize(live);
    if (!live.isActive || reading == null || !reading.isUsable(now))
      return null;
    final age = now.difference(reading.recordedAt);
    final accuracy = reading.accuracyMeters;
    if (age > const Duration(seconds: 20) ||
        age < const Duration(seconds: -5) ||
        accuracy == null ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 50 ||
        !reading.latitude.isFinite ||
        !reading.longitude.isFinite ||
        reading.latitude.abs() > 90 ||
        reading.longitude.abs() > 180)
      return null;
    final nearby =
        live.stops
            .where(
              (s) =>
                  !announced.contains(s.stopId) &&
                  distanceMeters(
                        reading.latitude,
                        reading.longitude,
                        s.latitude,
                        s.longitude,
                      ) <=
                      radiusMeters,
            )
            .toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
    if (nearby.isEmpty) return null;
    final stop = nearby.first;
    announced.add(stop.stopId);
    return stop;
  }

  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const radians = math.pi / 180;
    final lat = (lat2 - lat1) * radians;
    final lon = (lon2 - lon1) * radians;
    final a =
        math.pow(math.sin(lat / 2), 2) +
        math.cos(lat1 * radians) *
            math.cos(lat2 * radians) *
            math.pow(math.sin(lon / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}
