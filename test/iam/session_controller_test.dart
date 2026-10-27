import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/core/storage/token_storage.dart';
import 'package:rutasegura/iam/application/session_controller.dart';

import '../support/fakes.dart';

Future<SessionState> _settled(ProviderContainer c) async {
  c.read(sessionControllerProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return c.read(sessionControllerProvider);
}

ProviderContainer _container(InMemoryTokenStorage storage, FakeIamApi iam) {
  final c = ProviderContainer(overrides: fakeBackend(storage: storage, iam: iam));
  addTearDown(c.dispose);
  return c;
}

const _unauthorized = ApiError(
  kind: ApiErrorKind.http,
  status: 401,
  code: ApiErrorCodes.tokenExpired,
);

void main() {
  test('sin token queda en SignedOut', () async {
    final c = _container(InMemoryTokenStorage(), FakeIamApi());
    expect(await _settled(c), isA<SessionSignedOut>());
  });

  test('con token válido restaura la sesión', () async {
    final c = _container(InMemoryTokenStorage('jwt'), FakeIamApi());
    final state = await _settled(c);
    expect(state, isA<SessionActive>());
    expect((state as SessionActive).user.firstName, 'Jorge');
  });

  test('token vencido (401) cierra sesión, borra el token y avisa', () async {
    final storage = InMemoryTokenStorage('jwt');
    final c = _container(storage, FakeIamApi(meError: _unauthorized));
    final state = await _settled(c);
    expect(state, isA<SessionSignedOut>());
    expect((state as SessionSignedOut).message, contains('venció'));
    expect(await storage.read(), isNull);
  });

  test('sin red al abrir: usa la cuenta guardada y conserva el token', () async {
    final storage = InMemoryTokenStorage('jwt');
    await storage.writeUser(jsonEncode(testUser.toJson()));
    final c = _container(
      storage,
      FakeIamApi(meError: const ApiError(kind: ApiErrorKind.network)),
    );
    expect(await _settled(c), isA<SessionActive>());
    expect(await storage.read(), 'jwt');
  });

  test('sign-in de conductor guarda token y cuenta', () async {
    final storage = InMemoryTokenStorage();
    final c = _container(storage, FakeIamApi());
    await _settled(c);

    final error = await c
        .read(sessionControllerProvider.notifier)
        .signIn(' jorge@santarosa.pe ', 'Password123');

    expect(error, isNull);
    expect(c.read(sessionControllerProvider), isA<SessionActive>());
    expect(await storage.read(), 'jwt-nuevo');
    expect(await storage.readUser(), isNotNull);
  });

  test('sign-in con otro rol se rechaza y no guarda el token', () async {
    final storage = InMemoryTokenStorage();
    final c = _container(storage, FakeIamApi(roleTier: 'ADMIN'));
    await _settled(c);

    final error =
        await c.read(sessionControllerProvider.notifier).signIn('a@b.pe', 'x');

    expect(error, 'Esta app es solo para conductores.');
    expect(await storage.read(), isNull);
    expect(c.read(sessionControllerProvider), isA<SessionSignedOut>());
  });

  test('credenciales inválidas y empresa suspendida tienen su mensaje', () async {
    Future<String?> attempt(ApiError e) async {
      final c = _container(InMemoryTokenStorage(), FakeIamApi(signInError: e));
      await _settled(c);
      return c.read(sessionControllerProvider.notifier).signIn('a@b.pe', 'x');
    }

    expect(
      await attempt(const ApiError(
        kind: ApiErrorKind.http,
        status: 401,
        code: ApiErrorCodes.invalidCredentials,
      )),
      'Correo o contraseña incorrectos.',
    );
    expect(
      await attempt(const ApiError(
        kind: ApiErrorKind.http,
        status: 403,
        code: ApiErrorCodes.organizationNotActive,
      )),
      contains('suspendida'),
    );
    expect(
      await attempt(const ApiError(kind: ApiErrorKind.network)),
      contains('conexión'),
    );
  });

  test('signOut borra token y cuenta', () async {
    final storage = InMemoryTokenStorage('jwt');
    final c = _container(storage, FakeIamApi());
    await _settled(c);

    await c.read(sessionControllerProvider.notifier).signOut();

    expect(c.read(sessionControllerProvider), isA<SessionSignedOut>());
    expect(await storage.read(), isNull);
    expect(await storage.readUser(), isNull);
  });
}
