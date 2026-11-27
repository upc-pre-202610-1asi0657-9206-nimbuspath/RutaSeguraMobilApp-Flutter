import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/connectivity.dart';
import '../../core/router/app_router.dart';
import '../../iam/application/session_controller.dart';
import '../../trip_execution/application/agenda_provider.dart';
import '../../stakeholder/application/students_repository.dart';
import '../application/driver_push_controller.dart';
import '../application/notification_inbox.dart';
import '../infrastructure/native_push.dart';
import '../infrastructure/notification_api.dart';
import '../infrastructure/notification_realtime.dart';

class DriverNotificationBridge extends ConsumerStatefulWidget {
  const DriverNotificationBridge({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<DriverNotificationBridge> createState() =>
      _DriverNotificationBridgeState();
}

class _DriverNotificationBridgeState
    extends ConsumerState<DriverNotificationBridge>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _hub;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _poll;
  bool _refreshing = false;
  String? _user;
  bool _bound = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final push = ref.read(driverPushGatewayProvider);
    _subscriptions.add(
      push.messages.listen((id) => unawaited(_foreground(id))),
    );
    _subscriptions.add(push.opened.listen(_open));
    _subscriptions.add(
      push.tokenChanges.listen(
        (_) =>
            unawaited(ref.read(driverPushControllerProvider.notifier).bind()),
      ),
    );
    ref.listenManual(sessionControllerProvider, (_, session) {
      if (session is SessionRestoring) return;
      final user = session is SessionActive ? session.user.id : null;
      if (_bound && _user == user) return;
      _bound = true;
      _user = user;
      unawaited(_hub?.cancel());
      _hub = null;
      _poll?.cancel();
      _poll = null;
      unawaited(ref.read(driverPushControllerProvider.notifier).bind());
      if (user != null) {
        _start();
        final initial = push.takeInitialNotice();
        if (initial != null)
          WidgetsBinding.instance.addPostFrameCallback((_) => _open(initial));
      }
    }, fireImmediately: true);
    ref.listenManual(connectivityRestoredProvider, (_, next) {
      if (next.asData?.value == true) {
        if (_user != null) unawaited(_refresh());
        unawaited(ref.read(driverPushControllerProvider.notifier).bind());
      }
    });
  }

  void _start() {
    if (_user == null || _poll != null) return;
    _hub = ref
        .read(notificationHintsProvider)()
        .listen((_) => unawaited(_refresh()));
    _poll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refresh()),
    );
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing || _user == null) return;
    _refreshing = true;
    try {
      await ref.read(notificationInboxProvider.notifier).refresh();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _foreground(String id) async {
    final owner = _user;
    if (owner == null) return;
    try {
      final notice = await ref.read(notificationApiProvider).detail(id);
      if (!mounted || _user != owner) return;
      if (notice.readAt == null &&
          ref.read(driverPushControllerProvider).enabled) {
        await ref.read(driverPushGatewayProvider).show(id);
      }
      ref.invalidate(agendaProvider);
      ref.invalidate(studentsProvider);
      await _refresh();
    } catch (_) {
      /* Revoked, stale or foreign hints never display content. */
    }
  }

  void _open(String id) {
    if (!mounted || _user == null) return;
    ref.read(appRouterProvider).push('/notifications', extra: id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
      unawaited(_refresh());
      unawaited(ref.read(driverPushControllerProvider.notifier).bind());
    } else if (state == AppLifecycleState.paused) {
      unawaited(_hub?.cancel());
      _hub = null;
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    unawaited(_hub?.cancel());
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
