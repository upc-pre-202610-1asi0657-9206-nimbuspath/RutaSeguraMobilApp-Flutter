import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Pide el permiso de notificaciones (Android 13+).
///
/// Sin él, Android no muestra la notificación del servicio de ubicación que
/// acompaña al viaje en curso. Nunca falla: si el usuario lo niega, el GPS
/// sigue funcionando.
typedef RequestNotificationPermission = Future<void> Function();

final notificationPermissionProvider = Provider<RequestNotificationPermission>(
  (ref) => () async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Es un aviso al usuario, no un requisito para operar.
    }
  },
);
