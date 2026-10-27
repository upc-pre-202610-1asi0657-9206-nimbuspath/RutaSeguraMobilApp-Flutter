import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_error.dart';
import '../../core/network/api_error_message.dart';
import '../../core/storage/local_cache.dart';
import '../../core/storage/photo_store.dart';
import '../../core/storage/token_storage.dart';
import '../domain/model/driver.dart';
import '../infrastructure/iam_api.dart';

/// Estado de la sesión del conductor.
sealed class SessionState {
  const SessionState();
}

/// Leyendo el token guardado y validándolo.
class SessionRestoring extends SessionState {
  const SessionRestoring();
}

class SessionSignedOut extends SessionState {
  const SessionSignedOut({this.message});

  /// Por qué se cerró la sesión (token vencido, cuenta rechazada...).
  final String? message;
}

class SessionActive extends SessionState {
  const SessionActive(this.user);
  final SessionUser user;
}

/// Sesión del conductor: sign-in, restauración al abrir la app y cierre.
///
/// Al cerrar sesión solo se borran token y cuenta; la cola offline (etapa 7)
/// vive aparte y se conserva para sincronizar tras un nuevo login.
class SessionController extends Notifier<SessionState> {
  late final TokenStorage _storage = ref.read(tokenStorageProvider);
  late final IamApi _iam = ref.read(iamApiProvider);

  @override
  SessionState build() {
    final sub = ref.read(apiClientProvider).authFailures.listen(_onAuthFailure);
    ref.onDispose(sub.cancel);
    Future.microtask(_restore);
    return const SessionRestoring();
  }

  /// Devuelve el mensaje de error para mostrar, o `null` si ingresó.
  Future<String?> signIn(String email, String password) async {
    try {
      final result = await _iam.signIn(email: email.trim(), password: password);
      if (!result.isDriver) return 'Esta app es solo para conductores.';
      await _storage.write(result.token);
      await _storage.writeUser(jsonEncode(result.user.toJson()));
      state = SessionActive(result.user);
      return null;
    } on ApiError catch (e) {
      return _signInMessage(e);
    }
  }

  Future<void> signOut() async {
    await _storage.clear();
    await _clearPersonalData();
    state = const SessionSignedOut();
  }

  /// Agenda, alumnos y fotos (datos de menores) no se quedan en el teléfono
  /// tras un cierre de sesión voluntario ni si la cuenta es rechazada. Con un
  /// token vencido se conservan: tras el nuevo login se vuelven a validar.
  Future<void> _clearPersonalData() async {
    await ref.read(localCacheProvider).clearAll();
    await ref.read(photoStoreProvider).clearAll();
  }

  Future<void> _restore() async {
    final token = await _storage.read();
    if (token == null || token.isEmpty) {
      state = const SessionSignedOut();
      return;
    }
    final cached = await _cachedUser();
    try {
      final user = await _iam.me();
      await _storage.writeUser(jsonEncode(user.toJson()));
      state = SessionActive(user);
    } on ApiError catch (e) {
      if (e.isUnauthorized || e.isAccountRejected) {
        await _expire(e);
      } else if (cached != null) {
        // Sin señal o servidor caído: se abre con la última cuenta conocida
        // (el conductor puede estar en medio de un viaje).
        state = SessionActive(cached);
      } else {
        state = SessionSignedOut(message: e.userMessage);
      }
    }
  }

  Future<SessionUser?> _cachedUser() async {
    final raw = await _storage.readUser();
    if (raw == null) return null;
    try {
      return SessionUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void _onAuthFailure(ApiError error) {
    if (state is SessionActive) _expire(error);
  }

  Future<void> _expire(ApiError error) async {
    await _storage.clear();
    if (error.isAccountRejected) await _clearPersonalData();
    state = SessionSignedOut(message: error.userMessage);
  }

  String _signInMessage(ApiError e) {
    if (e.code == ApiErrorCodes.invalidCredentials || e.status == 401) {
      return 'Correo o contraseña incorrectos.';
    }
    if (e.code == ApiErrorCodes.organizationNotActive) {
      return 'Tu empresa de transporte está suspendida. Comunícate con ella.';
    }
    if (e.status == 400) return 'Revisa tu correo y tu contraseña.';
    return e.userMessage;
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
