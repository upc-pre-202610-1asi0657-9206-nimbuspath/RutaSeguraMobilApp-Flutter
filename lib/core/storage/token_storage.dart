import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda el JWT de IAM y los datos de la cuenta (JSON) para abrir la app sin
/// señal. El token **nunca** va a logs ni a almacenamiento sin cifrar.
abstract interface class TokenStorage {
  Future<String?> read();
  Future<void> write(String token);
  Future<String?> readUser();
  Future<void> writeUser(String userJson);

  /// Borra token y cuenta (no toca la cola offline, que vive aparte).
  Future<void> clear();
}

/// Implementación con Keychain (iOS) / Keystore (Android).
/// Mantiene una copia en memoria para no leer el almacenamiento seguro en
/// cada petición.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'rs_auth_token';
  static const _userKey = 'rs_auth_user';

  final FlutterSecureStorage _storage;
  String? _cached;
  bool _loaded = false;

  @override
  Future<String?> read() async {
    if (!_loaded) {
      _cached = await _storage.read(key: _key);
      _loaded = true;
    }
    return _cached;
  }

  @override
  Future<void> write(String token) async {
    await _storage.write(key: _key, value: token);
    _cached = token;
    _loaded = true;
  }

  @override
  Future<String?> readUser() => _storage.read(key: _userKey);

  @override
  Future<void> writeUser(String userJson) =>
      _storage.write(key: _userKey, value: userJson);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _userKey);
    _cached = null;
    _loaded = true;
  }
}

/// Para pruebas.
class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage([this._token]);

  String? _token;
  String? _user;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<String?> readUser() async => _user;

  @override
  Future<void> writeUser(String userJson) async => _user = userJson;

  @override
  Future<void> clear() async {
    _token = null;
    _user = null;
  }
}

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);
