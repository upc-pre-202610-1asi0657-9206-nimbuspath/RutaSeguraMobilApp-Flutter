import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../storage/token_storage.dart';
import 'api_error.dart';

/// Claves de `RequestOptions.extra`.
abstract final class ApiExtra {
  /// No enviar `Authorization` (p. ej. sign-in).
  static const skipAuth = 'rs.skipAuth';
  static const startedAt = 'rs.startedAt';
}

/// Agrega `X-Correlation-Id` a cada petición (el Gateway lo respeta y lo
/// devuelve), para rastrear una acción de punta a punta en los logs.
class CorrelationIdInterceptor extends Interceptor {
  CorrelationIdInterceptor([Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent(ApiHeaders.correlationId, _uuid.v4);
    handler.next(options);
  }
}

/// Agrega `Authorization: Bearer <token>` y avisa cuando el backend rechaza
/// la sesión (401, o 403 de cuenta rechazada / empresa suspendida).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.tokenStorage, required this.onAuthFailure});

  final TokenStorage tokenStorage;
  final void Function(ApiError error) onAuthFailure;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[ApiExtra.skipAuth] != true) {
      final token = await tokenStorage.read();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null && err.requestOptions.extra[ApiExtra.skipAuth] != true) {
      final error = ApiError.fromResponse(response);
      if (error.isUnauthorized || error.isAccountRejected) {
        onAuthFailure(error);
      }
    }
    handler.next(err);
  }
}

/// Log mínimo en modo debug: método, ruta, estado, duración y correlación.
/// **No** registra cabeceras ni cuerpos (token, posiciones y datos de menores).
class DebugLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[ApiExtra.startedAt] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final code = err.response?.data is Map ? err.response?.data['code'] : null;
    _log(err.requestOptions, err.response?.statusCode, extra: code ?? err.type.name);
    handler.next(err);
  }

  void _log(RequestOptions o, int? status, {Object? extra}) {
    final started = o.extra[ApiExtra.startedAt] as DateTime?;
    final ms = started == null
        ? '?'
        : DateTime.now().difference(started).inMilliseconds;
    debugPrint(
      '[api] ${o.method} ${o.path} → ${status ?? '-'} ${ms}ms'
      '${extra == null ? '' : ' $extra'} '
      'cid=${o.headers[ApiHeaders.correlationId]}',
    );
  }
}
