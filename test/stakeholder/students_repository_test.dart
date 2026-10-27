import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/core/storage/local_cache.dart';
import 'package:rutasegura/core/storage/photo_store.dart';
import 'package:rutasegura/iam/application/session_controller.dart';
import 'package:rutasegura/stakeholder/application/students_repository.dart';
import 'package:rutasegura/stakeholder/domain/model/route_student.dart';

import '../support/fakes.dart';

StudentsRepository _repo(FakeStakeholderApi api, LocalCache cache, PhotoStore photos) =>
    StudentsRepository(api: api, cache: cache, photos: photos, userId: 'u1');

void main() {
  test('refresh guarda la lista y cached() la devuelve igual', () async {
    final cache = InMemoryLocalCache();
    final repo = _repo(FakeStakeholderApi(), cache, InMemoryPhotoStore());

    expect(repo.cached(), isNull);
    await repo.refresh();
    final saved = repo.cached()!;

    expect(saved.single.fullName, 'Valeria Quispe');
    expect(saved.single.initials, 'VQ');
    expect(saved.single.stopName, 'Av. Primavera 1240');
    expect(saved.single.guardianPhone, '987654321');
    expect(saved.single.photoVersion, '3');
  });

  test('la foto se descarga una vez y luego sale del disco', () async {
    final api = FakeStakeholderApi();
    final photos = InMemoryPhotoStore();
    final repo = _repo(api, InMemoryLocalCache(), photos);

    expect(await repo.photo(testStudent), [1, 2, 3]);
    expect(await repo.photo(testStudent), [1, 2, 3]);
    expect(api.photoCalls, 1);
  });

  test('una versión nueva de la foto se vuelve a descargar', () async {
    final api = FakeStakeholderApi();
    final repo = _repo(api, InMemoryLocalCache(), InMemoryPhotoStore());

    await repo.photo(testStudent);
    await repo.photo(RouteStudent.fromJson({
      ...testStudent.toJson(),
      'photoUrl': '/api/v1/stakeholders/students/s1/photo?v=4',
    }));
    expect(api.photoCalls, 2);
  });

  test('sin photoUrl o con la descarga fallida devuelve null (iniciales)', () async {
    final repo = _repo(FakeStakeholderApi(), InMemoryLocalCache(), InMemoryPhotoStore());
    final sinFoto = RouteStudent.fromJson({...testStudent.toJson(), 'photoUrl': null});
    expect(await repo.photo(sinFoto), isNull);
  });

  test('studentsProvider usa la lista guardada si no hay señal', () async {
    final cache = InMemoryLocalCache();
    final photos = InMemoryPhotoStore();

    ProviderContainer container(FakeStakeholderApi api) {
      final c = ProviderContainer(
        overrides: fakeBackend(stakeholders: api, cache: cache, photos: photos),
      );
      addTearDown(c.dispose);
      c.listen(sessionControllerProvider, (_, _) {});
      return c;
    }

    Future<List<RouteStudent>> load(ProviderContainer c) async {
      for (var i = 0; i < 20 && c.read(sessionControllerProvider) is! SessionActive; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return c.read(studentsProvider.future);
    }

    expect(await load(container(FakeStakeholderApi())), hasLength(1));

    final offline = FakeStakeholderApi()..error = const ApiError(kind: ApiErrorKind.timeout);
    expect(await load(container(offline)), hasLength(1));

    final rejected = FakeStakeholderApi()
      ..error = const ApiError(kind: ApiErrorKind.http, status: 422);
    await expectLater(load(container(rejected)), throwsA(isA<ApiError>()));
  });

  test('cerrar sesión borra la caché y las fotos (datos de menores)', () async {
    final cache = InMemoryLocalCache();
    final photos = InMemoryPhotoStore();
    final c = ProviderContainer(overrides: fakeBackend(cache: cache, photos: photos));
    addTearDown(c.dispose);
    c.listen(sessionControllerProvider, (_, _) {});
    for (var i = 0; i < 20 && c.read(sessionControllerProvider) is! SessionActive; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final repo = _repo(FakeStakeholderApi(), cache, photos);
    await repo.refresh();
    await repo.photo(testStudent);
    expect(repo.cached(), isNotNull);

    await c.read(sessionControllerProvider.notifier).signOut();

    expect(repo.cached(), isNull);
    expect(await photos.read('s1', '3'), isNull);
  });
}
