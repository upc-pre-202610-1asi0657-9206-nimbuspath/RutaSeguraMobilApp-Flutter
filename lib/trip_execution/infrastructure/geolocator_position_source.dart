import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../application/tracking_engine.dart';
import '../domain/model/tracking.dart';

/// GPS real con `geolocator`. En Android el stream corre en un servicio en
/// primer plano (con notificación fija); en iOS, con el modo de ubicación en
/// segundo plano.
class GeolocatorPositionSource implements PositionSource {
  @override
  Future<TrackingPermission> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return TrackingPermission.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.whileInUse ||
      LocationPermission.always =>
        TrackingPermission.granted,
      _ => TrackingPermission.denied,
    };
  }

  LocationSettings get _settings => switch (defaultTargetPlatform) {
        TargetPlatform.android => AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 4),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'RutaSegura',
              notificationText: 'Compartiendo tu ubicación del viaje en curso',
              enableWakeLock: true,
              setOngoing: true,
            ),
          ),
        TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
            accuracy: LocationAccuracy.best,
            activityType: ActivityType.automotiveNavigation,
            distanceFilter: 0,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          ),
        _ => const LocationSettings(accuracy: LocationAccuracy.best),
      };

  @override
  Stream<GpsReading> readings() =>
      Geolocator.getPositionStream(locationSettings: _settings).map(
        (p) => GpsReading(
          latitude: p.latitude,
          longitude: p.longitude,
          recordedAt: p.timestamp,
          accuracyMeters: p.accuracy,
          // El plugin usa -1 cuando no hay dato.
          speedKmh: p.speed < 0 ? null : p.speed * 3.6,
          headingDegrees: p.heading < 0 ? null : p.heading,
        ),
      );
}
