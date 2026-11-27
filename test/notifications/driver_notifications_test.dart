import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_client.dart';
import 'package:rutasegura/core/permissions/session_notification_cleanup.dart';
import 'package:rutasegura/core/storage/token_storage.dart';
import 'package:rutasegura/iam/application/session_controller.dart';
import 'package:rutasegura/notifications/application/driver_push_controller.dart';
import 'package:rutasegura/notifications/application/notification_inbox.dart';
import 'package:rutasegura/notifications/domain/model/driver_notification.dart';
import 'package:rutasegura/notifications/infrastructure/native_push.dart';
import 'package:rutasegura/notifications/infrastructure/notification_api.dart';
import 'package:rutasegura/notifications/presentation/notifications_page.dart';

import '../support/fakes.dart';

const noticeId = '10000000-0000-4000-8000-000000000001';
DriverNotification notice({String id = noticeId}) => DriverNotification(
  id: id,
  title: 'Viaje cancelado',
  body: 'Consulta la agenda.',
  category: 'TripCancelled',
  occurredAt: DateTime.utc(2026, 11, 26),
);

class FakePush extends UnavailableDriverPush {
  bool allowed = true;
  bool settingsAllowed = true;
  bool deleteFails = false;
  int deleted = 0;
  String currentToken = 'device-token';
  @override
  bool get available => true;
  @override
  Future<bool> permission() async => allowed;
  @override
  Future<bool> permitted() async => settingsAllowed;
  @override
  Future<String?> token() async => currentToken;
  @override
  Future<void> deleteToken() async {
    deleted++;
    if (deleteFails) throw StateError('offline');
  }
}

class FakeNotifications extends NotificationApi {
  FakeNotifications(TokenStorage tokens)
    : storage = tokens,
      super(ApiClient(tokenStorage: tokens));
  final TokenStorage storage;
  final tokens = <String>[];
  String? jwtDuringDisable;
  bool offline = false;
  int registrations = 0;
  Completer<DriverNotificationPage>? pending;
  @override
  Future<String> register(String installationId, String token) async {
    if (offline) throw StateError('offline');
    registrations++;
    tokens.add(token);
    return 'subscription-id';
  }

  @override
  Future<void> disable(String id) async {
    jwtDuringDisable = await storage.read();
    if (offline) throw StateError('offline');
  }

  @override
  Future<DriverNotificationPage> page({String? cursor}) async => pending != null
      ? pending!.future
      : DriverNotificationPage([notice()], cursor == null ? 'next' : null);
  @override
  Future<DriverNotification> read(String id) async => notice(id: id);
}

Future<void> settle(ProviderContainer container) async {
  container.read(sessionControllerProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late ProviderContainer container;
  late InMemoryTokenStorage storage;
  late FakePush push;
  late FakeNotifications api;
  setUp(() async {
    storage = signedInStorage();
    push = FakePush();
    api = FakeNotifications(storage);
    container = ProviderContainer(
      overrides: [
        ...fakeBackend(storage: storage, notifications: api),
        driverPushGatewayProvider.overrideWithValue(push),
        sessionNotificationCleanupProvider.overrideWith(
          (ref) =>
              () => ref
                  .read(driverPushControllerProvider.notifier)
                  .disable(forget: false),
        ),
      ],
    );
    await settle(container);
    await container.read(driverPushControllerProvider.notifier).bind();
  });
  tearDown(() {
    container.dispose();
    api.client.dispose();
  });

  test(
    'revoking Android permission disables delivery registration on resume',
    () async {
      final controller = container.read(driverPushControllerProvider.notifier);
      await controller.enable();
      push.settingsAllowed = false;
      await controller.bind();
      expect(container.read(driverPushControllerProvider).enabled, false);
      expect(push.read('subscription'), '');
      expect(push.deleted, greaterThan(0));
    },
  );

  test('permission denial leaves persistent inbox usable without registering a token', () async {
    push.allowed = false;
    await container.read(driverPushControllerProvider.notifier).enable();
    expect(api.registrations, 0);
    expect(container.read(driverPushControllerProvider).enabled, false);
    container.read(notificationInboxProvider);
    await settle(container);
    expect(
      container.read(notificationInboxProvider).asData!.value.items.single.id,
      noticeId,
    );
  });

  test('token rotation reuses installation and updates subscription', () async {
    final controller = container.read(driverPushControllerProvider.notifier);
    await controller.enable();
    final installation = push.read('installation');
    push.currentToken = 'rotated-token';
    await controller.bind();
    expect(api.tokens, ['device-token', 'rotated-token']);
    expect(push.read('installation'), installation);
    expect(container.read(driverPushControllerProvider).enabled, true);
  });

  test('logout revokes subscription with JWT before clearing credentials and deletes FCM token', () async {
    await container.read(driverPushControllerProvider.notifier).enable();
    await container.read(sessionControllerProvider.notifier).signOut();
    expect(api.jwtDuringDisable, 'jwt');
    expect(await storage.read(), null);
    expect(push.deleted, greaterThan(0));
    expect(push.read('subscription'), '');
  });

  test(
    'offline logout retains pending revocation and retries after reconnect',
    () async {
      final controller = container.read(driverPushControllerProvider.notifier);
      await controller.enable();
      api.offline = true;
      push.deleteFails = true;
      await container.read(sessionControllerProvider.notifier).signOut();
      expect(push.read('subscription'), 'subscription-id');
      api.offline = false;
      push.deleteFails = false;
      await controller.bind();
      expect(push.read('subscription'), '');
    },
  );

  test('failed registration retries on network recovery without asking permission again', () async {
    api.offline = true;
    final controller = container.read(driverPushControllerProvider.notifier);
    await controller.enable();
    expect(container.read(driverPushControllerProvider).enabled, false);
    api.offline = false;
    push.allowed = false;
    await controller.bind();
    expect(container.read(driverPushControllerProvider).enabled, true);
  });

  test('pagination deduplicates notices by logical id', () async {
    container.read(notificationInboxProvider);
    await settle(container);
    await container.read(notificationInboxProvider.notifier).loadMore();
    final page = container.read(notificationInboxProvider).asData!.value;
    expect(page.items.length, 1);
    expect(page.nextCursor, null);
  });

  test(
    'an in-flight inbox response cannot populate the next signed-out session',
    () async {
      api.pending = Completer();
      container.read(notificationInboxProvider);
      await settle(container);
      await container.read(sessionControllerProvider.notifier).signOut();
      container.read(notificationInboxProvider);
      api.pending!.complete(DriverNotificationPage([notice()], null));
      await settle(container);
      expect(
        container.read(notificationInboxProvider).asData!.value.items,
        isEmpty,
      );
    },
  );

  test(
    'notification links accept identifiers and reject arbitrary URLs or paths',
    () {
      expect(NativeDriverPush.validNoticeId(noticeId), noticeId);
      expect(NativeDriverPush.validNoticeId('https://example.org'), null);
      expect(NativeDriverPush.validNoticeId('../../trips'), null);
    },
  );

  testWidgets(
    'mobile inbox opens authorized notice without triggering a trip action',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NotificationsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Viaje cancelado'), findsOneWidget);
      await tester.tap(find.text('Viaje cancelado'));
      await tester.pumpAndSettle();
      expect(find.text('Consulta la agenda.'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
