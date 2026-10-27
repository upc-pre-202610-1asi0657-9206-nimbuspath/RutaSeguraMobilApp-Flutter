import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/geolocator_position_source.dart';
import '../infrastructure/trip_api.dart';
import 'tracking_engine.dart';

final positionSourceProvider =
    Provider<PositionSource>((ref) => GeolocatorPositionSource());

/// Cada cuánto se envía el GPS acumulado (§3.7.d: cada 5–10 s).
final trackingFlushEveryProvider =
    Provider<Duration>((ref) => const Duration(seconds: 8));

/// Comparte la ubicación mientras exista este provider (autoDispose): se
/// observa solo desde la pantalla de un viaje en curso, así la ubicación se
/// comparte únicamente con el viaje activo.
class TrackingController extends Notifier<TrackingState> {
  TrackingController(this.tripId);

  final String tripId;
  TrackingEngine? _engine;

  /// Vacía lo pendiente (p. ej. antes de finalizar el viaje).
  Future<void> flush() async => _engine?.flush();

  @override
  TrackingState build() {
    final engine = TrackingEngine(
      tripId: tripId,
      api: ref.read(tripApiProvider),
      source: ref.read(positionSourceProvider),
      flushEvery: ref.read(trackingFlushEveryProvider),
      onChange: (s) {
        // El motor puede avisar mientras se libera el provider.
        if (ref.mounted) state = s;
      },
    );
    _engine = engine;
    ref.onDispose(engine.stop);
    engine.start();
    return const TrackingState();
  }
}

final trackingControllerProvider = NotifierProvider.autoDispose
    .family<TrackingController, TrackingState, String>(TrackingController.new);
