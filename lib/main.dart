import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/app_router.dart';
import 'core/storage/local_cache.dart';
import 'core/theme/app_theme.dart';
import 'trip_execution/infrastructure/offline_store.dart';
import 'trip_execution/infrastructure/sqlite_offline_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  final offlineStore = await SqliteOfflineStore.open();
  runApp(
    ProviderScope(
      overrides: [
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
    );
  }
}
