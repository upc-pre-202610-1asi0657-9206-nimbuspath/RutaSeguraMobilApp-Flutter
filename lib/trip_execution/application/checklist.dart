import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Resultado de una verificación de "Antes de salir".
enum CheckLevel { ok, warning, error }

class CheckResult {
  const CheckResult(this.level, this.title, [this.subtitle]);

  final CheckLevel level;
  final String title;
  final String? subtitle;
}

/// Lecturas del dispositivo para el checklist. 100 % local: no hay endpoint.
abstract interface class DeviceChecks {
  Future<CheckResult> gps({bool requestPermission = false});
  Future<CheckResult> network();
  Future<CheckResult> battery();
}

/// Umbrales: GPS verde ≤ 30 m, ámbar ≤ 100 m (el backend rechaza > 100 m).
/// Batería: verde ≥ 50 % o cargando, ámbar ≥ 25 %, rojo por debajo.
class PluginDeviceChecks implements DeviceChecks {
  @override
  Future<CheckResult> gps({bool requestPermission = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const CheckResult(
        CheckLevel.error,
        'GPS desactivado',
        'Actívalo en los ajustes del teléfono',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        return const CheckResult(
          CheckLevel.error,
          'Falta el permiso de ubicación',
          'Toca para permitirlo',
        );
      case LocationPermission.deniedForever:
      case LocationPermission.unableToDetermine:
        return const CheckResult(
          CheckLevel.error,
          'Permiso de ubicación bloqueado',
          'Permítelo en los ajustes de la app',
        );
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final m = p.accuracy.round();
      if (m <= 30) {
        return CheckResult(CheckLevel.ok, 'GPS activado', 'Precisión de $m m');
      }
      if (m <= 100) {
        return CheckResult(
          CheckLevel.warning,
          'GPS con poca precisión',
          'Precisión de $m m. Sal a un lugar abierto',
        );
      }
      return CheckResult(
        CheckLevel.error,
        'GPS sin precisión suficiente',
        'Precisión de $m m. Sal a un lugar abierto',
      );
    } catch (_) {
      return const CheckResult(
        CheckLevel.warning,
        'Buscando señal de GPS',
        'Sal a un lugar abierto y reintenta',
      );
    }
  }

  @override
  Future<CheckResult> network() async {
    final r = await Connectivity().checkConnectivity();
    final connected = r.any((c) => c != ConnectivityResult.none);
    if (!connected) {
      return const CheckResult(
        CheckLevel.error,
        'Sin conexión a internet',
        'Los registros se guardarán y se enviarán al reconectar',
      );
    }
    return const CheckResult(
      CheckLevel.ok,
      'Datos móviles con señal',
      'Los padres verán el bus en vivo',
    );
  }

  @override
  Future<CheckResult> battery() async {
    final b = Battery();
    final level = await b.batteryLevel;
    final state = await b.batteryState;
    final charging =
        state == BatteryState.charging || state == BatteryState.full;
    if (charging || level >= 50) {
      return CheckResult(
        CheckLevel.ok,
        'Batería al $level %',
        charging ? 'Cargando' : null,
      );
    }
    return CheckResult(
      level >= 25 ? CheckLevel.warning : CheckLevel.error,
      'Batería al $level %',
      'Conecta el cargador antes de partir',
    );
  }
}

final deviceChecksProvider = Provider<DeviceChecks>((ref) => PluginDeviceChecks());

/// Lecturas independientes: cada fila carga a su ritmo (el GPS tarda más).
final gpsCheckProvider = FutureProvider.autoDispose<CheckResult>(
  (ref) => ref.watch(deviceChecksProvider).gps(),
);
final networkCheckProvider = FutureProvider.autoDispose<CheckResult>(
  (ref) => ref.watch(deviceChecksProvider).network(),
);
final batteryCheckProvider = FutureProvider.autoDispose<CheckResult>(
  (ref) => ref.watch(deviceChecksProvider).battery(),
);
