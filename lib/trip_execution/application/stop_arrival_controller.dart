import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_cache.dart';
import '../../iam/application/session_controller.dart';
import '../domain/model/stop_arrival.dart';
import '../domain/model/trip_live.dart';
import '../domain/model/trip_models.dart';
import 'tracking_controller.dart';
import 'trip_controller.dart';

class StopArrivalController extends Notifier<LiveStop?> {
  StopArrivalController(this.trip);
  final ScheduledTrip trip;
  StopArrivalDetector? _detector;
  String? _cacheKey;

  @override
  LiveStop? build() {
    final session = ref.watch(sessionControllerProvider);
    final active = ref.watch(
      tripControllerProvider(trip).select((s) => s.value?.isActive ?? false),
    );
    if (session is! SessionActive || !active) return null;
    final key = 'stop-arrivals.${session.user.id}.${trip.id}';
    if (_cacheKey != key) {
      _cacheKey = key;
      List<String> seen;
      try {
        seen = (jsonDecode(
          ref.read(localCacheProvider).read(key) ?? '[]',
        ) as List).cast<String>();
      } catch (_) {
        seen = [];
      }
      _detector = StopArrivalDetector(seen: seen);
      _detector!.initialize(
        ref.read(tripControllerProvider(trip)).requireValue,
      );
    }
    ref.listen(trackingControllerProvider(trip.id), (_, _) => _check());
    ref.listen(tripControllerProvider(trip), (_, _) => _check());
    Future.microtask(_check);
    return null;
  }

  void _check() {
    if (!ref.mounted) return;
    final live = ref.read(tripControllerProvider(trip)).value;
    if (live == null || !live.isActive) return;
    final stop = _detector?.detect(
      live,
      ref.read(trackingControllerProvider(trip.id)).lastReading,
      DateTime.now(),
    );
    if (stop == null) return;
    state = stop;
    unawaited(
      ref
          .read(localCacheProvider)
          .write(_cacheKey!, jsonEncode(_detector!.announced.toList())),
    );
  }

  void dismiss() => state = null;
}

final stopArrivalProvider = NotifierProvider.autoDispose
    .family<StopArrivalController, LiveStop?, ScheduledTrip>(
      StopArrivalController.new,
    );
