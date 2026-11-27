import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../../core/config/app_config.dart';
import '../../core/network/signalr_http_client.dart';
import '../../core/storage/token_storage.dart';

/// Hints only. The authorized REST inbox is always the source of the content.
Stream<void> watchNotificationHints(
  String url,
  Future<String?> Function() token,
) {
  final stream = StreamController<void>();
  final stop = Completer<void>();
  HubConnection? connection;
  CancellableSignalRHttpClient? http;
  Future<void> run() async {
    while (!stop.isCompleted) {
      final closed = Completer<void>();
      final client = http = CancellableSignalRHttpClient();
      try {
        final hub = HubConnectionBuilder()
            .withUrl(
              url,
              options: HttpConnectionOptions(
                httpClient: client,
                requestTimeout: 15000,
                transport: AppConfig.signalRLongPolling
                    ? HttpTransportType.LongPolling
                    : null,
                accessTokenFactory: () async => await token() ?? '',
              ),
            )
            .build();
        connection = hub;
        hub.on('NotificationAvailable', (_) {
          if (!stream.isClosed) stream.add(null);
        });
        hub.onclose(({error}) {
          if (!closed.isCompleted) closed.complete();
        });
        await hub.start();
        if (!stream.isClosed)
          stream.add(null); // Recover missed hints on reconnect.
        await Future.any([closed.future, stop.future]);
      } catch (_) {
        // The periodic REST refresh remains available during broker/hub/network outages.
      } finally {
        try {
          await connection?.stop();
        } catch (_) {}
        connection = null;
        client.close();
      }
      if (!stop.isCompleted)
        await Future.any([
          Future<void>.delayed(const Duration(seconds: 15)),
          stop.future,
        ]);
    }
  }

  stream.onListen = () => unawaited(run());
  stream.onCancel = () async {
    if (!stop.isCompleted) stop.complete();
    try {
      await connection?.stop();
    } catch (_) {}
    http?.close();
  };
  return stream.stream;
}

final notificationHintsProvider = Provider<Stream<void> Function()>(
  (ref) =>
      () => watchNotificationHints(
        '${AppConfig.apiBaseUrl}/hubs/notifications',
        ref.read(tokenStorageProvider).read,
      ),
);
