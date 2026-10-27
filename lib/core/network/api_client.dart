import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_error.dart';
import 'api_interceptors.dart';

/// Cliente HTTP único hacia el API Gateway.
///
/// - Las rutas se escriben sin el prefijo: `get('/drivers/me/trips')`.
/// - Toda falla se lanza como [ApiError] (nunca [DioException]).
/// - [authFailures] emite cuando el backend rechaza la sesión; la capa de
///   sesión decide qué hacer (ir al login sin borrar la cola offline).
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    String? baseUrl,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: '${baseUrl ?? AppConfig.apiBaseUrl}${AppConfig.apiPrefix}',
            connectTimeout: AppConfig.connectTimeout,
            receiveTimeout: AppConfig.receiveTimeout,
            sendTimeout: AppConfig.sendTimeout,
            contentType: Headers.jsonContentType,
            responseType: ResponseType.json,
            headers: {'Accept': 'application/json'},
          ),
        ),
        origin = baseUrl ?? AppConfig.apiBaseUrl {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.addAll([
      CorrelationIdInterceptor(),
      AuthInterceptor(
        tokenStorage: tokenStorage,
        onAuthFailure: _authFailures.add,
      ),
      if (kDebugMode) DebugLogInterceptor(),
    ]);
  }

  final Dio _dio;

  /// URL del Gateway sin `/api/v1` (para URLs relativas como `photoUrl`).
  final String origin;

  final _authFailures = StreamController<ApiError>.broadcast();
  Stream<ApiError> get authFailures => _authFailures.stream;

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) =>
      _send(() => _dio.get<dynamic>(
            path,
            queryParameters: query,
            options: _options(auth),
          ));

  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _send(() => _dio.post<dynamic>(path, data: body, options: _options(auth)));

  Future<dynamic> put(String path, {Object? body, bool auth = true}) =>
      _send(() => _dio.put<dynamic>(path, data: body, options: _options(auth)));

  /// Descarga binaria con token (fotos de alumnos). [url] puede ser relativa
  /// al Gateway, como la `photoUrl` de Stakeholder.
  Future<Uint8List> getBytes(String url) async {
    final data = await _send(() => _dio.get<List<int>>(
          resolveUrl(url),
          options: Options(responseType: ResponseType.bytes),
        ));
    return Uint8List.fromList(data as List<int>);
  }

  /// Convierte una ruta relativa del backend (`/api/v1/...`) en absoluta.
  String resolveUrl(String url) =>
      url.startsWith('http') ? url : '$origin${url.startsWith('/') ? '' : '/'}$url';

  Options _options(bool auth) => Options(extra: {ApiExtra.skipAuth: !auth});

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      return response.data;
    } on DioException catch (e) {
      throw ApiError.fromDioException(e);
    }
  }

  void dispose() {
    _authFailures.close();
    _dio.close();
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(tokenStorage: ref.watch(tokenStorageProvider));
  ref.onDispose(client.dispose);
  return client;
});
