import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/storage/local_cache.dart';
import '../../core/storage/photo_store.dart';
import '../../iam/application/session_controller.dart';
import '../domain/model/route_student.dart';
import '../infrastructure/stakeholder_api.dart';

/// Alumnos de las rutas del conductor: se descargan al iniciar sesión y antes
/// de cada viaje, y se guardan (datos y fotos) para usarlos sin señal.
class StudentsRepository {
  StudentsRepository({
    required this.api,
    required this.cache,
    required this.photos,
    required this.userId,
  });

  final StakeholderApi api;
  final LocalCache cache;
  final PhotoStore photos;
  final String userId;

  String get _key => 'students.$userId';

  /// Última lista guardada, o `null` si nunca se descargó.
  List<RouteStudent>? cached() {
    final raw = cache.read(_key);
    if (raw == null) return null;
    try {
      return [
        for (final s in jsonDecode(raw) as List)
          RouteStudent.fromJson(s as Map<String, dynamic>),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Descarga la lista, la guarda y baja las fotos nuevas en segundo plano.
  Future<List<RouteStudent>> refresh() async {
    final students = await api.myStudents();
    await cache.write(_key, jsonEncode([for (final s in students) s.toJson()]));
    _prefetchPhotos(students); // sin await: no retrasa la lista
    return students;
  }

  /// Foto del alumno (disco primero, red después). `null` si no tiene foto o
  /// no se pudo obtener; en ese caso la UI muestra las iniciales.
  Future<Uint8List?> photo(RouteStudent student) async {
    final url = student.photoUrl;
    if (url == null) return null;
    final version = student.photoVersion;
    final stored = await photos.read(student.studentId, version);
    if (stored != null) return stored;
    try {
      final bytes = await api.photo(url);
      await photos.write(student.studentId, version, bytes);
      return bytes;
    } on ApiError {
      return null;
    }
  }

  Future<void> _prefetchPhotos(List<RouteStudent> students) async {
    for (final s in students) {
      try {
        await photo(s);
      } catch (_) {
        // Mejor esfuerzo: la foto se pedirá al mostrarla.
      }
    }
  }

  /// Borra datos y fotos (cierre de sesión): son datos de menores.
  Future<void> clear() async {
    await photos.clearAll();
  }
}

final studentsRepositoryProvider = Provider<StudentsRepository?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session is! SessionActive) return null;
  return StudentsRepository(
    api: ref.watch(stakeholderApiProvider),
    cache: ref.watch(localCacheProvider),
    photos: ref.watch(photoStoreProvider),
    userId: session.user.id,
  );
});

Duration? _noRetry(int retryCount, Object error) => null;

/// Alumnos de las rutas del conductor. Si no hay señal usa la última lista
/// guardada.
final studentsProvider = FutureProvider<List<RouteStudent>>(retry: _noRetry, (ref) async {
  final repo = ref.watch(studentsRepositoryProvider);
  if (repo == null) return const [];
  try {
    return await repo.refresh();
  } on ApiError catch (e) {
    final cached = repo.cached();
    final offline = e.kind == ApiErrorKind.network ||
        e.kind == ApiErrorKind.timeout ||
        (e.status ?? 0) >= 500;
    if (offline && cached != null) return cached;
    rethrow;
  }
});

/// Foto de un alumno (bytes) o `null`.
final studentPhotoProvider =
    FutureProvider.autoDispose.family<Uint8List?, RouteStudent>((ref, student) {
  final repo = ref.watch(studentsRepositoryProvider);
  return repo?.photo(student) ?? Future.value(null);
});
