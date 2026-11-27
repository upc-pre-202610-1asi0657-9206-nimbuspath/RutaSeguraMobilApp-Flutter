import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs before removing the JWT, so the subscription can be disabled on the server.
/// The composition root supplies the native implementation; tests need no platform plugins.
final sessionNotificationCleanupProvider = Provider<Future<void> Function()>(
  (ref) => () async {},
);
