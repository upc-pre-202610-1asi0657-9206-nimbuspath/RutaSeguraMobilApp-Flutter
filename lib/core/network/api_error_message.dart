import 'api_error.dart';

/// Texto en español para mostrar al conductor. Se decide por `code`/estado,
/// nunca por el texto del backend (salvo `detail` de reglas de negocio 422).
extension ApiErrorMessage on ApiError {
  String get userMessage {
    switch (kind) {
      case ApiErrorKind.network:
        return 'No hay conexión con el servidor. Revisa tu internet.';
      case ApiErrorKind.timeout:
        return 'El servidor tardó en responder. Inténtalo de nuevo.';
      case ApiErrorKind.cancelled:
      case ApiErrorKind.unknown:
        return 'Algo salió mal. Inténtalo de nuevo.';
      case ApiErrorKind.http:
        break;
    }
    if (code == ApiErrorCodes.driverNotFound) {
      return 'Tu empresa aún no completó tu registro.';
    }
    if (isAccountRejected) {
      return 'Comunícate con tu empresa de transporte.';
    }
    switch (status) {
      case 401:
        return 'Tu sesión venció. Inicia sesión de nuevo.';
      case 429:
        return 'Demasiados intentos. Espera un momento.';
      case 502:
      case 503:
      case 504:
        return 'El servicio no está disponible por ahora. Inténtalo en un momento.';
    }
    return 'Algo salió mal. Inténtalo de nuevo.';
  }
}
