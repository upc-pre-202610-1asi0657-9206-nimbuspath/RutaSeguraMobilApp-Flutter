import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../domain/model/driver_notification.dart';

class NotificationApi {
  NotificationApi(this.client);
  final ApiClient client;

  Future<DriverNotificationPage> page({String? cursor}) async {
    final data = await client.get(
      '/notifications/page',
      query: {'limit': 25, if (cursor != null) 'cursor': cursor},
    ) as Map<String, dynamic>;
    return DriverNotificationPage([
      for (final item in data['items'] as List)
        DriverNotification.fromJson(Map<String, dynamic>.from(item as Map)),
    ], data['nextCursor'] as String?);
  }

  Future<DriverNotification> read(String id) async =>
      DriverNotification.fromJson(
        Map<String, dynamic>.from(
          await client.patch('/notifications/$id/read') as Map,
        ),
      );

  Future<DriverNotification> detail(String id) async =>
      DriverNotification.fromJson(
        Map<String, dynamic>.from(
          await client.get('/notifications/$id') as Map,
        ),
      );

  Future<String> register(String installationId, String token) async {
    final body = await client.put(
      '/push-subscriptions/$installationId',
      body: {'token': token, 'platform': 'Android'},
    ) as Map;
    return body['id'] as String;
  }

  Future<void> disable(String id) async =>
      client.delete('/push-subscriptions/$id');
}

final notificationApiProvider = Provider<NotificationApi>(
  (ref) => NotificationApi(ref.watch(apiClientProvider)),
);
