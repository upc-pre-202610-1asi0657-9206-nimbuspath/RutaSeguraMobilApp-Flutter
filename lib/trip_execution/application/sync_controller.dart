import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/offline_store.dart';
import '../infrastructure/trip_api.dart';
import 'sync_service.dart';

/// Estado de lo que está guardado sin enviar y dueño del [SyncService].
class SyncController extends Notifier<SyncState> {
  late SyncService service;

  @override
  SyncState build() {
    service = SyncService(
      store: ref.read(offlineStoreProvider),
      api: ref.read(tripApiProvider),
      onChange: (s) {
        if (ref.mounted) state = s;
      },
    );
    return const SyncState();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
