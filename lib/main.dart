import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/storage/local_cache.dart';
import 'core/theme/app_theme.dart';
import 'core/permissions/session_notification_cleanup.dart';
import 'notifications/infrastructure/native_push.dart';
import 'notifications/application/driver_push_controller.dart';
import 'notifications/presentation/driver_notification_bridge.dart';
import 'trip_execution/infrastructure/offline_store.dart';
import 'trip_execution/infrastructure/sqlite_offline_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  final push = NativeDriverPush(prefs);
  await push.initialize();
  final offlineStore = await SqliteOfflineStore.open();
  runApp(
    ProviderScope(
      overrides: [
        driverPushGatewayProvider.overrideWithValue(push),
        sessionNotificationCleanupProvider.overrideWith(
          (ref) =>
              () => ref
                  .read(driverPushControllerProvider.notifier)
                  .disable(forget: false),
        ),
        localCacheProvider.overrideWithValue(SharedPrefsLocalCache(prefs)),
        offlineStoreProvider.overrideWithValue(offlineStore),
      ],
      child: const RutaSeguraDriverApp(),
    ),
  );
}

class RutaSeguraDriverApp extends ConsumerWidget {
  const RutaSeguraDriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'RutaSegura Conductor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => DriverNotificationBridge(child: child!),
    );
  }
}
