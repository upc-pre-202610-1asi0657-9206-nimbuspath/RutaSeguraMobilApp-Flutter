import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// No API calls or private data in the background isolate. Android displays the
/// notification payload itself; displaying it here would duplicate it.
@pragma('vm:entry-point')
Future<void> driverMessagingBackground(RemoteMessage message) async {
  await Firebase.initializeApp();
}

abstract interface class DriverPushGateway {
  bool get available;
  Stream<String> get messages;
  Stream<String> get opened;
  Stream<String> get tokenChanges;
  String? takeInitialNotice();
  Future<bool> permission();
  Future<bool> permitted();
  Future<String?> token();
  Future<void> deleteToken();
  Future<void> show(String id);
  Future<void> clear();
  String? read(String key);
  Future<void> write(String key, String value);
}

class NativeDriverPush implements DriverPushGateway {
  NativeDriverPush(this.prefs);
  final SharedPreferences prefs;
  final _local = FlutterLocalNotificationsPlugin();
  final _messages = StreamController<String>.broadcast();
  final _opened = StreamController<String>.broadcast();
  final _tokens = StreamController<String>.broadcast();
  final _seen = <String>{};
  String? _initial;
  bool _available = false;
  static const channel = 'rutasegura_updates';
  static const channelName = 'Avisos de la empresa';

  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(driverMessagingBackground);
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_rutasegura'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final id = validNoticeId(response.payload);
          if (id != null) _opened.add(id);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              channel,
              channelName,
              description:
                  'Viajes, inasistencias, comunicados y seguimiento de SOS',
              importance: Importance.defaultImportance,
            ),
          );
      final localLaunch = await _local.getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp == true)
        _initial = validNoticeId(localLaunch?.notificationResponse?.payload);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      _initial = validNoticeId(initial?.data['notificationId']) ?? _initial;
      FirebaseMessaging.onMessage.listen((m) {
        final id = validNoticeId(m.data['notificationId']);
        if (id != null) _messages.add(id);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final id = validNoticeId(m.data['notificationId']);
        if (id != null) _opened.add(id);
      });
      FirebaseMessaging.instance.onTokenRefresh.listen(_tokens.add);
      _available = true;
    } catch (_) {
      // Agenda, GPS and persistent inbox still work without Play Services/configuration.
      _available = false;
    }
  }

  static String? validNoticeId(Object? value) =>
      value is String &&
          RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
              .hasMatch(value)
      ? value
      : null;

  @override
  bool get available => _available;
  @override
  Stream<String> get messages => _messages.stream;
  @override
  Stream<String> get opened => _opened.stream;
  @override
  Stream<String> get tokenChanges => _tokens.stream;
  @override
  String? takeInitialNotice() {
    final id = _initial;
    _initial = null;
    return id;
  }

  @override
  Future<bool> permission() async {
    final result = await FirebaseMessaging.instance.requestPermission();
    return result.authorizationStatus == AuthorizationStatus.authorized ||
        result.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<bool> permitted() async {
    final result = await FirebaseMessaging.instance.getNotificationSettings();
    return result.authorizationStatus == AuthorizationStatus.authorized ||
        result.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() async {
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    return FirebaseMessaging.instance.getToken();
  }

  @override
  Future<void> deleteToken() async {
    if (_available) {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      await FirebaseMessaging.instance.deleteToken();
    }
  }

  @override
  Future<void> show(String id) async {
    if (!_seen.add(id)) return;
    if (_seen.length > 500) _seen.remove(_seen.first);
    // No names, GPS, incident details, or free text on the lock screen.
    await _local.show(
      id: 0,
      title: 'RutaSegura',
      body: 'Tienes un nuevo aviso. Revisalo cuando estes detenido.',
      payload: id,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          channelName,
          icon: 'ic_stat_rutasegura',
          tag: id.replaceAll('-', ''),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          visibility: NotificationVisibility.private,
        ),
      ),
    );
  }

  @override
  Future<void> clear() async {
    _seen.clear();
    if (!_available) return;
    for (final notification in await _local.getActiveNotifications()) {
      // Keep the geolocator foreground service's notification intact.
      if (notification.channelId == channel && notification.id != null) {
        await _local.cancel(id: notification.id!, tag: notification.tag);
      }
    }
  }

  @override
  String? read(String key) => prefs.getString('rs.push.$key');
  @override
  Future<void> write(String key, String value) async {
    await prefs.setString('rs.push.$key', value);
  }
}

/// An inert gateway keeps widget/unit tests and unsupported platforms independent of native SDKs.
class UnavailableDriverPush implements DriverPushGateway {
  final _values = <String, String>{};
  @override
  bool get available => false;
  @override
  Stream<String> get messages => const Stream.empty();
  @override
  Stream<String> get opened => const Stream.empty();
  @override
  Stream<String> get tokenChanges => const Stream.empty();
  @override
  String? takeInitialNotice() => null;
  @override
  Future<bool> permission() async => false;
  @override
  Future<bool> permitted() async => false;
  @override
  Future<String?> token() async => null;
  @override
  Future<void> deleteToken() async {}
  @override
  Future<void> show(String id) async {}
  @override
  Future<void> clear() async {}
  @override
  String? read(String key) => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

final driverPushGatewayProvider = Provider<DriverPushGateway>(
  (ref) => UnavailableDriverPush(),
);

Future<String> installationId(DriverPushGateway gateway) async {
  final stored = gateway.read('installation');
  if (stored != null) return stored;
  final id = const Uuid().v4();
  await gateway.write('installation', id);
  return id;
}
