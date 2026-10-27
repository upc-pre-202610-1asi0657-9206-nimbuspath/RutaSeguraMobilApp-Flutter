import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../domain/model/driver.dart';

/// Identity & Access vía Gateway.
abstract interface class IamApi {
  Future<SignInResult> signIn({required String email, required String password});

  /// Valida la sesión guardada y devuelve la cuenta.
  Future<SessionUser> me();

  /// Nombre de la empresa de transporte.
  Future<String> organizationName(String organizationId);
}

class HttpIamApi implements IamApi {
  HttpIamApi(this._client);

  final ApiClient _client;

  @override
  Future<SignInResult> signIn({
    required String email,
    required String password,
  }) async {
    final json = await _client.post(
      '/users/sign-in',
      body: {'email': email, 'password': password},
      auth: false,
    ) as Map<String, dynamic>;
    return SignInResult(
      user: SessionUser.fromJson(json),
      roleTier: json['roleTier'] as String? ?? '',
      token: json['token'] as String,
    );
  }

  @override
  Future<SessionUser> me() async {
    final json = await _client.get('/users/me') as Map<String, dynamic>;
    return SessionUser.fromJson(json);
  }

  @override
  Future<String> organizationName(String organizationId) async {
    final json = await _client.get('/organizations/$organizationId')
        as Map<String, dynamic>;
    return json['name'] as String? ?? '';
  }
}

final iamApiProvider = Provider<IamApi>(
  (ref) => HttpIamApi(ref.watch(apiClientProvider)),
);
