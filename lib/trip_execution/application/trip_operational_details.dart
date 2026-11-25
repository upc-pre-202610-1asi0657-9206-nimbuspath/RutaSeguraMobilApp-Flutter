import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/storage/local_cache.dart';
import '../../iam/application/session_controller.dart';
import '../domain/model/trip_live.dart';
import '../infrastructure/trip_api.dart';

typedef TripDetailsKey = ({String tripId, String snapshot});

TripDetailsKey tripDetailsKey(TripLive live) => (
  tripId: live.tripId,
  snapshot: jsonEncode([
    for (final p in live.passengers) p.studentId,
    for (final s in live.stops) [s.stopId, s.latitude, s.longitude],
  ]),
);

final tripOperationalDetailsProvider = FutureProvider.autoDispose
    .family<TripOperationalDetails, TripDetailsKey>((ref, key) async {
      final session = ref.watch(sessionControllerProvider);
      final api = ref.watch(tripApiProvider);
      final cache = ref.watch(localCacheProvider);
      final cacheKey = session is SessionActive
          ? 'trip-details.${session.user.id}.${key.tripId}'
          : null;
      var disposed = false;
      ref.onDispose(() => disposed = true);
      try {
        final data = await api.operationalDetails(key.tripId);
        if (!disposed && cacheKey != null) {
          await cache.write(
            cacheKey,
            jsonEncode({'snapshot': key.snapshot, 'details': data}),
          );
        }
        return TripOperationalDetails.fromJson(data);
      } on ApiError catch (error) {
        final offline =
            error.kind == ApiErrorKind.network ||
            error.kind == ApiErrorKind.timeout;
        final raw = offline && cacheKey != null ? cache.read(cacheKey) : null;
        if (raw == null) rethrow;
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        if (saved['snapshot'] != key.snapshot) rethrow;
        return TripOperationalDetails.fromJson(
          saved['details'] as Map<String, dynamic>,
        );
      }
    });
