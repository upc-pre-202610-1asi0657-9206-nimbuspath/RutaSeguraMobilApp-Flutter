import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../iam/application/session_controller.dart';
import '../infrastructure/native_push.dart';
import '../infrastructure/notification_api.dart';

class DriverPushState {
  const DriverPushState({
    this.enabled = false,
    this.busy = false,
    this.message,
  });
  final bool enabled, busy;
  final String? message;
}

class DriverPushController extends Notifier<DriverPushState> {
  Future<void> _queue = Future.value();
  String? _owner;
  bool _revoking = false;
  @override
  DriverPushState build() => const DriverPushState();

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.catchError((_) {
      if (ref.mounted)
        state = const DriverPushState(
          message:
              'No se pudo actualizar push. Reintenta cuando tengas conexion.',
        );
    });
    return _queue;
  }

  Future<void> bind() => _serialize(() async {
    final session = ref.read(sessionControllerProvider);
    if (session is! SessionActive) {
      await _disable(forget: false);
      _owner = null;
      return;
    }
    final gateway = ref.read(driverPushGatewayProvider);
    final previousOwner = _owner ?? gateway.read('owner');
    if ((gateway.read('pendingTokenDeletion') == 'true' ||
            (previousOwner != null &&
                previousOwner.isNotEmpty &&
                previousOwner != session.user.id)) &&
        !await _disable(forget: false)) {
      state = const DriverPushState(
        message:
            'Conectate para desvincular la cuenta anterior y activar push.',
      );
      return;
    }
    _owner = session.user.id;
    if (gateway.read('enabled.$_owner') == 'true')
      await _register(requestPermission: false);
  });

  Future<void> enable() => _serialize(() => _register(requestPermission: true));

  Future<void> _register({required bool requestPermission}) async {
    final gateway = ref.read(driverPushGatewayProvider);
    final session = ref.read(sessionControllerProvider);
    if (session is! SessionActive || _revoking) return;
    final previousOwner = gateway.read('owner');
    if ((gateway.read('pendingTokenDeletion') == 'true' ||
            (previousOwner != null &&
                previousOwner.isNotEmpty &&
                previousOwner != session.user.id)) &&
        !await _disable(forget: false)) {
      state = const DriverPushState(
        message:
            'Conectate para desvincular la cuenta anterior y activar push.',
      );
      return;
    }
    _owner = session.user.id;
    if (!gateway.available) {
      state = const DriverPushState(
        message: 'Push no disponible. Revisa Firebase y Google Play Services. La bandeja sigue disponible.',
      );
      return;
    }
    state = DriverPushState(enabled: state.enabled, busy: true);
    try {
      if (!requestPermission && !await gateway.permitted()) {
        await _disable(forget: false);
        state = const DriverPushState(
          message:
              'Permiso desactivado en Android. La bandeja sigue disponible.',
        );
        return;
      }
      if (requestPermission && !await gateway.permission()) {
        state = const DriverPushState(
          message:
              'Permiso denegado. Puedes habilitarlo en los ajustes de Android.',
        );
        return;
      }
      final token = await gateway.token();
      if (token == null) throw StateError('No token');
      // Persist intent before the request so a failed registration can retry on resume/network recovery.
      await gateway.write('enabled.${session.user.id}', 'true');
      final id = await ref
          .read(notificationApiProvider)
          .register(await installationId(gateway), token);
      await gateway.write('subscription', id);
      await gateway.write('owner', session.user.id);
      if (ref.read(sessionControllerProvider) != session || _revoking) {
        await _disable(forget: false);
        return;
      }
      state = const DriverPushState(
        enabled: true,
        message: 'Avisos push activados.',
      );
    } catch (_) {
      if (ref.mounted)
        state = const DriverPushState(
          message: 'No se pudo registrar push. Se reintentara al recuperar conexion.',
        );
    }
  }

  Future<void> disable({bool forget = true}) {
    _revoking = true;
    return _serialize(() async {
      try {
        await _disable(forget: forget);
      } finally {
        _revoking = false;
      }
    });
  }

  Future<bool> _disable({required bool forget}) async {
    final gateway = ref.read(driverPushGatewayProvider);
    if (forget && _owner != null)
      await gateway.write('enabled.$_owner', 'false');
    final id = gateway.read('subscription');
    var disabledOnServer = id == null || id.isEmpty;
    if (id != null && id.isNotEmpty) {
      try {
        await ref.read(notificationApiProvider).disable(id);
        disabledOnServer = true;
      } catch (_) {
        /* Retry after reconnect. */
      }
    }
    var deletedToken = false;
    try {
      await gateway.deleteToken();
      deletedToken = true;
    } catch (_) {}
    if (disabledOnServer || deletedToken)
      await gateway.write('subscription', '');
    if (deletedToken) await gateway.write('owner', '');
    await gateway.write(
      'pendingTokenDeletion',
      deletedToken ? 'false' : 'true',
    );
    await gateway.clear();
    if (ref.mounted) state = const DriverPushState();
    return deletedToken;
  }
}

final driverPushControllerProvider =
    NotifierProvider<DriverPushController, DriverPushState>(
      DriverPushController.new,
    );
