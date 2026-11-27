import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../iam/application/session_controller.dart';
import '../domain/model/driver_notification.dart';
import '../infrastructure/notification_api.dart';

class NotificationInbox extends Notifier<AsyncValue<DriverNotificationPage>> {
  int _request = 0;

  @override
  AsyncValue<DriverNotificationPage> build() {
    final session = ref.watch(sessionControllerProvider);
    _request++;
    if (session is! SessionActive)
      return const AsyncData(DriverNotificationPage([], null));
    Future.microtask(refresh);
    return const AsyncLoading();
  }

  Future<void> refresh() async {
    final generation = ++_request;
    final session = ref.read(sessionControllerProvider);
    if (session is! SessionActive) return;
    final result = await AsyncValue.guard(
      () => ref.read(notificationApiProvider).page(),
    );
    if (ref.mounted &&
        generation == _request &&
        ref.read(sessionControllerProvider) == session)
      state = result;
  }

  Future<void> loadMore() async {
    final previous = state.asData?.value;
    if (previous?.nextCursor == null) return;
    final generation = ++_request;
    final page = await ref
        .read(notificationApiProvider)
        .page(cursor: previous!.nextCursor);
    if (!ref.mounted || generation != _request) return;
    final unique = {
      for (final item in previous.items) item.id: item,
      for (final item in page.items) item.id: item,
    };
    state = AsyncData(
      DriverNotificationPage(unique.values.toList(), page.nextCursor),
    );
  }

  Future<DriverNotification> open(String id) async {
    final session = ref.read(sessionControllerProvider);
    final notice = await ref.read(notificationApiProvider).read(id);
    if (ref.read(sessionControllerProvider) != session)
      throw StateError('La sesion cambio.');
    await refresh();
    return notice;
  }
}

final notificationInboxProvider =
    NotifierProvider<NotificationInbox, AsyncValue<DriverNotificationPage>>(
      NotificationInbox.new,
    );
