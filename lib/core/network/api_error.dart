import 'package:dio/dio.dart';

/// Tipo de falla, independiente del `code` del backend.
enum ApiErrorKind {
  /// Sin conexión, DNS o conexión rechazada.
  network,

  /// Se agotó el tiempo de conexión, envío o respuesta.
  timeout,

  /// El servidor respondió con un estado HTTP de error.
  http,

  /// La petición se canceló desde la app.
  cancelled,

  /// Cualquier otra falla (respuesta ilegible, bug).
  unknown,
}

/// Error de la API ya normalizado.
///
/// Los servicios y el Gateway responden con ProblemDetails (RFC 9457) y un
/// `code` estable. **La app decide por `code`, nunca por el texto.**
class ApiError implements Exception {
  const ApiError({
    required this.kind,
    this.status,
    this.code,
    this.title,
    this.detail,
    this.correlationId,
    this.traceId,
    this.retryAfter,
  });

  final ApiErrorKind kind;
  final int? status;
  final String? code;
  final String? title;
  final String? detail;
  final String? correlationId;
  final String? traceId;
  final Duration? retryAfter;

  /// Convierte cualquier [DioException] en un [ApiError].
  factory ApiError.fromDioException(DioException e) {
    final correlationId =
        e.response?.headers.value(ApiHeaders.correlationId) ??
            e.requestOptions.headers[ApiHeaders.correlationId] as String?;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiError(kind: ApiErrorKind.timeout, correlationId: correlationId);
      case DioExceptionType.connectionError:
        return ApiError(kind: ApiErrorKind.network, correlationId: correlationId);
      case DioExceptionType.cancel:
        return ApiError(
          kind: ApiErrorKind.cancelled,
          correlationId: correlationId,
        );
      case DioExceptionType.badResponse:
        return ApiError.fromResponse(e.response!, correlationId: correlationId);
      case DioExceptionType.badCertificate:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        if (e.error is ApiError) return e.error! as ApiError;
        return ApiError(
          kind: ApiErrorKind.unknown,
          detail: e.message,
          correlationId: correlationId,
        );
    }
  }

  /// Lee el cuerpo ProblemDetails de una respuesta con error.
  factory ApiError.fromResponse(Response<dynamic> response, {String? correlationId}) {
    final data = response.data;
    final body = data is Map ? data : const {};
    return ApiError(
      kind: ApiErrorKind.http,
      status: response.statusCode,
      code: body['code'] as String?,
      title: body['title'] as String?,
      detail: body['detail'] as String?,
      traceId: body['traceId'] as String?,
      correlationId:
          correlationId ?? response.headers.value(ApiHeaders.correlationId),
      retryAfter: _parseRetryAfter(response.headers.value('retry-after')),
    );
  }

  static Duration? _parseRetryAfter(String? value) {
    final seconds = int.tryParse(value ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  bool get isUnauthorized => status == 401;

  /// Cuenta rechazada o empresa suspendida: cerrar sesión con mensaje.
  bool get isAccountRejected =>
      code == ApiErrorCodes.iamAccountRejected ||
      code == ApiErrorCodes.organizationNotActive;

  /// Vale la pena reintentar la **misma** petición (con el mismo
  /// `clientEventId` si es una acción del conductor).
  bool get isRetryable {
    if (kind == ApiErrorKind.network || kind == ApiErrorKind.timeout) {
      return true;
    }
    final s = status;
    if (s == null) return false;
    return s == 409 || s == 429 || s >= 500;
  }

  @override
  String toString() =>
      'ApiError(kind: ${kind.name}, status: $status, code: $code, '
      'detail: $detail, correlationId: $correlationId)';
}

/// Cabeceras propias del backend.
abstract final class ApiHeaders {
  static const correlationId = 'X-Correlation-Id';
}

/// `code` de ProblemDetails que la app trata de forma específica.
/// Catálogo completo: §9 de `docs/APP-CONDUCTOR-BACKEND.md` del backend.
abstract final class ApiErrorCodes {
  // Gateway
  static const gatewayRouteNotFound = 'GATEWAY_ROUTE_NOT_FOUND';
  static const tooManyRequests = 'TOO_MANY_REQUESTS';
  static const upstreamUnavailable = 'UPSTREAM_UNAVAILABLE';
  static const upstreamTimeout = 'UPSTREAM_TIMEOUT';
  static const serviceDisabled = 'SERVICE_DISABLED';

  // IAM / sesión
  static const invalidCredentials = 'InvalidCredentials';
  static const organizationNotActive = 'OrganizationNotActive';
  static const unauthorized = 'UNAUTHORIZED';
  static const invalidToken = 'INVALID_TOKEN';
  static const tokenExpired = 'TOKEN_EXPIRED';
  static const iamAccountRejected = 'IAM_ACCOUNT_REJECTED';
  static const iamUnavailable = 'IAM_UNAVAILABLE';

  // Administration
  static const driverNotFound = 'DriverNotFound';

  // Trip & Tracking
  static const tripNotFound = 'TRIP_NOT_FOUND';
  static const tripDriverMismatch = 'TRIP_DRIVER_MISMATCH';
  static const tripStartTooEarly = 'TRIP_START_TOO_EARLY';
  static const tripInvalidTransition = 'TRIP_INVALID_TRANSITION';
  static const tripNotActive = 'TRIP_NOT_ACTIVE';
  static const tripHasPendingStudents = 'TRIP_HAS_PENDING_STUDENTS';
  static const tripHasStudentsOnBoard = 'TRIP_HAS_STUDENTS_ON_BOARD';
  static const tripHasActiveSos = 'TRIP_HAS_ACTIVE_SOS';
  static const trackingRequiresActiveTrip = 'TRACKING_REQUIRES_ACTIVE_TRIP';
  static const studentNotInRoster = 'STUDENT_NOT_IN_ROSTER';
  static const passengerInvalidTransition = 'PASSENGER_INVALID_TRANSITION';
  static const concurrencyConflict = 'CONCURRENCY_CONFLICT';
}
