import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Fotos de alumnos (menores) guardadas **solo** en el almacenamiento privado
/// de la app (nunca en la galería ni en caché pública), una por alumno y
/// versión (`?v=` de `photoUrl`).
abstract interface class PhotoStore {
  Future<Uint8List?> read(String studentId, String version);
  Future<void> write(String studentId, String version, Uint8List bytes);
  Future<void> clearAll();
}

class FilePhotoStore implements PhotoStore {
  FilePhotoStore([Future<Directory> Function()? baseDir])
      : _baseDir = baseDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDir;

  Future<Directory> _dir() async {
    final base = await _baseDir();
    return Directory('${base.path}/student_photos').create(recursive: true);
  }

  // Los ids son UUID; se limpian por seguridad antes de formar el nombre.
  String _prefix(String studentId) =>
      '${studentId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_')}__';

  String _name(String studentId, String version) =>
      '${_prefix(studentId)}${version.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.img';

  @override
  Future<Uint8List?> read(String studentId, String version) async {
    final file = File('${(await _dir()).path}/${_name(studentId, version)}');
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> write(String studentId, String version, Uint8List bytes) async {
    final dir = await _dir();
    // Borra las versiones anteriores del mismo alumno.
    final prefix = _prefix(studentId);
    await for (final e in dir.list()) {
      if (e is File && e.uri.pathSegments.last.startsWith(prefix)) {
        await e.delete();
      }
    }
    await File('${dir.path}/${_name(studentId, version)}').writeAsBytes(bytes);
  }

  @override
  Future<void> clearAll() async {
    final dir = await _dir();
    await for (final e in dir.list()) {
      await e.delete(recursive: true);
    }
  }
}

/// Para pruebas.
class InMemoryPhotoStore implements PhotoStore {
  final _data = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String studentId, String version) async =>
      _data['$studentId|$version'];

  @override
  Future<void> write(String studentId, String version, Uint8List bytes) async {
    _data.removeWhere((k, _) => k.startsWith('$studentId|'));
    _data['$studentId|$version'] = bytes;
  }

  @override
  Future<void> clearAll() async => _data.clear();
}

final photoStoreProvider = Provider<PhotoStore>((ref) => FilePhotoStore());
