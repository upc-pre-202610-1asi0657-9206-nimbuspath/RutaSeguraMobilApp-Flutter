import 'package:flutter/foundation.dart';

/// Configuración de la app según el entorno.
///
/// La URL base es la del **API Gateway** (única puerta al backend). Se define
/// al compilar con `--dart-define=API_BASE_URL=...` o con
/// `--dart-define-from-file=config/dev.json`. Si no se define, se usa el
/// Gateway local: `10.0.2.2:8000` desde el emulador Android (alias de la PC)
/// y `127.0.0.1:8000` en el resto (simulador iOS, web, escritorio).
abstract final class AppConfig {
  static const String _apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// Nombre del entorno (`dev`, `prod`, ...). Solo informativo.
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  static String get apiBaseUrl {
    final url = _apiBaseUrlOverride.isNotEmpty
        ? _apiBaseUrlOverride
        : _localGatewayUrl;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static String get _localGatewayUrl =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:8000'
          : 'http://127.0.0.1:8000';

  /// Prefijo común de la API REST.
  static const String apiPrefix = '/api/v1';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 20);
}
