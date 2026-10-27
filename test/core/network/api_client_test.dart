import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rutasegura/core/network/api_client.dart';
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/core/storage/token_storage.dart';

/// Adaptador falso: registra la petición y responde lo que se le indique.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...?headers,
      },
    );

void main() {
  const gateway = 'http://gateway.test';

  ApiClient client(_FakeAdapter adapter, {String? token}) => ApiClient(
        tokenStorage: InMemoryTokenStorage(token),
        baseUrl: gateway,
        adapter: adapter,
      );

  test('antepone /api/v1 y envía token y X-Correlation-Id', () async {
    final adapter = _FakeAdapter((_) => _json(200, [{'tripId': 't1'}]));

    final data = await client(adapter, token: 'jwt').get('/drivers/me/trips');

    expect(data, [{'tripId': 't1'}]);
    expect(adapter.last!.uri.toString(), '$gateway/api/v1/drivers/me/trips');
    expect(adapter.last!.headers['Authorization'], 'Bearer jwt');
    expect(adapter.last!.headers[ApiHeaders.correlationId], isNotEmpty);
  });

  test('sin token o con auth: false no envía Authorization', () async {
    final adapter = _FakeAdapter((_) => _json(200, {}));

    await client(adapter, token: 'jwt').post('/users/sign-in', auth: false);
    expect(adapter.last!.headers.containsKey('Authorization'), isFalse);

    await client(adapter).get('/users/me');
    expect(adapter.last!.headers.containsKey('Authorization'), isFalse);
  });

  test('convierte ProblemDetails en ApiError con code', () async {
    final adapter = _FakeAdapter((_) => _json(
          422,
          {
            'title': 'Regla de negocio incumplida',
            'status': 422,
            'detail': 'Faltan registrar 2 alumno(s).',
            'code': 'TRIP_HAS_PENDING_STUDENTS',
            'traceId': '00-abc',
          },
          headers: {ApiHeaders.correlationId: ['cid-1']},
        ));

    await expectLater(
      client(adapter, token: 'jwt').post('/trips/t1/complete', body: {}),
      throwsA(isA<ApiError>()
          .having((e) => e.kind, 'kind', ApiErrorKind.http)
          .having((e) => e.status, 'status', 422)
          .having((e) => e.code, 'code', ApiErrorCodes.tripHasPendingStudents)
          .having((e) => e.detail, 'detail', 'Faltan registrar 2 alumno(s).')
          .having((e) => e.correlationId, 'correlationId', 'cid-1')
          .having((e) => e.isRetryable, 'isRetryable', isFalse)),
    );
  });

  test('429 con Retry-After es reintentable', () async {
    final adapter = _FakeAdapter((_) => _json(
          429,
          {'status': 429, 'code': 'TOO_MANY_REQUESTS'},
          headers: {'retry-after': ['30']},
        ));

    await expectLater(
      client(adapter).post('/users/sign-in', auth: false),
      throwsA(isA<ApiError>()
          .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30))
          .having((e) => e.isRetryable, 'isRetryable', isTrue)),
    );
  });

  test('401 emite authFailures; un 422 no', () async {
    var status = 401;
    final adapter = _FakeAdapter(
      (_) => _json(status, {'status': status, 'code': 'TOKEN_EXPIRED'}),
    );
    final api = client(adapter, token: 'jwt');
    final failures = <ApiError>[];
    api.authFailures.listen(failures.add);

    await expectLater(api.get('/users/me'), throwsA(isA<ApiError>()));
    status = 422;
    await expectLater(api.get('/users/me'), throwsA(isA<ApiError>()));
    await Future<void>.delayed(Duration.zero);

    expect(failures.map((e) => e.code), [ApiErrorCodes.tokenExpired]);
  });

  test('sin conexión → ApiErrorKind.network, reintentable', () {
    final error = ApiError.fromDioException(DioException.connectionError(
      requestOptions: RequestOptions(path: '/x'),
      reason: 'Connection refused',
    ));

    expect(error.kind, ApiErrorKind.network);
    expect(error.isRetryable, isTrue);
  });

  test('resolveUrl completa la photoUrl relativa con el Gateway', () {
    final api = client(_FakeAdapter((_) => _json(200, {})));

    expect(
      api.resolveUrl('/api/v1/stakeholders/students/s1/photo?v=3'),
      '$gateway/api/v1/stakeholders/students/s1/photo?v=3',
    );
  });
}
