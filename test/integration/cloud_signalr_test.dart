import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:rutasegura/core/network/signalr_http_client.dart';

/// Optional read-only check of the actual Gateway, using only the synthetic fixture.
/// No route, trip, message or subscription is created by this test.
void main() {
  final path = Platform.environment['RUTASEGURA_CLOUD_FIXTURE'];
  test(
    'Dart client authenticates parent/driver SignalR via the deployed Gateway HTTP fallback',
    () async {
      final fixture =
          jsonDecode(await File(path!).readAsString()) as Map<String, dynamic>;
      final client = HttpClient();
      Future<String> signIn(Map account) async {
        final request = await client.postUrl(
          Uri.parse('${fixture['baseUrl']}/api/v1/users/sign-in'),
        );
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode({
            'email': account['email'],
            'password': account['password'],
          }),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        return (jsonDecode(await utf8.decoder.bind(response).join())
                as Map)['token']
            as String;
      }

      try {
        final parentToken = await signIn(fixture['parent'] as Map);
        final driverToken = await signIn(fixture['driver'] as Map);
        for (final channel in [
          (
            '/hubs/notifications?organizationId=${fixture['organizationId']}',
            parentToken,
          ),
          ('/hubs/notifications', driverToken),
          ('/hubs/trip-tracking', driverToken),
        ]) {
          final http = CancellableSignalRHttpClient();
          final hub = HubConnectionBuilder()
              .withUrl(
                '${fixture['baseUrl']}${channel.$1}',
                options: HttpConnectionOptions(
                  transport: HttpTransportType.LongPolling,
                  httpClient: http,
                  requestTimeout: 15000,
                  accessTokenFactory: () async => channel.$2,
                ),
              )
              .build();
          try {
            await hub.start()!.timeout(const Duration(seconds: 20));
            expect(hub.state, HubConnectionState.Connected);
          } finally {
            try {
            await hub.stop().timeout(const Duration(seconds: 10));
            } finally {
              http.close();
            }
          }
        }
      } finally {
        client.close(force: true);
      }
    },
    skip: path == null
        ? 'Set RUTASEGURA_CLOUD_FIXTURE to the synthetic accounts manifest.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
