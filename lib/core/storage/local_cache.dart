import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Caché local de texto (JSON) para abrir la app sin señal. Todas las claves
/// llevan el prefijo `rs.cache.` para poder borrarlas juntas al cerrar sesión.
/// Aquí **no** va el token (eso es [TokenStorage]).
abstract interface class LocalCache {
  String? read(String key);
  Future<void> write(String key, String value);
  Future<void> clearAll();
}

class SharedPrefsLocalCache implements LocalCache {
  SharedPrefsLocalCache(this._prefs);

  static const _prefix = 'rs.cache.';

  final SharedPreferences _prefs;

  @override
  String? read(String key) => _prefs.getString('$_prefix$key');

  @override
  Future<void> write(String key, String value) =>
      _prefs.setString('$_prefix$key', value);

  @override
  Future<void> clearAll() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await _prefs.remove(k);
    }
  }
}

/// Para pruebas.
class InMemoryLocalCache implements LocalCache {
  final _data = <String, String>{};

  @override
  String? read(String key) => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> clearAll() async => _data.clear();
}

/// `main()` lo reemplaza por [SharedPrefsLocalCache].
final localCacheProvider = Provider<LocalCache>((ref) => InMemoryLocalCache());
