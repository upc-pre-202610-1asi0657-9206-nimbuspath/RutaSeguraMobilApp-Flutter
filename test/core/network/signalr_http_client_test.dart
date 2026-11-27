import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalr_netcore/abort_controller.dart';
import 'package:signalr_netcore/errors.dart' as signalr;
import 'package:signalr_netcore/signalr_http_client.dart';
import 'package:rutasegura/core/network/signalr_http_client.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions, Future<void>?) respond;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) {
    calls++;
    return respond(options, cancel);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('stopping a pending SignalR poll aborts the underlying HTTP request immediately', () async {
    final adapter = _Adapter((request, cancel) async {
      await cancel;
      throw DioException.requestCancelled(
        requestOptions: request,
        reason: 'test cancellation',
      );
    });
    final client = CancellableSignalRHttpClient(adapter: adapter);
    addTearDown(client.close);
    final controller = AbortController();
    final pending = client.get(
      'http://gateway.test/hubs/notifications?id=test',
      options: SignalRHttpRequest(
        abortSignal: controller.signal,
        timeout: 100000,
      ),
    );
    final assertion = expectLater(pending, throwsA(isA<signalr.AbortError>()));
    await Future<void>.delayed(Duration.zero);
    controller.abort();
    await assertion.timeout(const Duration(seconds: 2));
  });
  test('an already-aborted poll never opens a network connection', () async {
    final adapter = _Adapter((_, _) async => ResponseBody.fromString('', 200));
    final client = CancellableSignalRHttpClient(adapter: adapter);
    addTearDown(client.close);
    final controller = AbortController()..abort();
    await expectLater(
      client.get(
        'http://gateway.test/hubs/notifications',
        options: SignalRHttpRequest(abortSignal: controller.signal),
      ),
      throwsA(isA<signalr.AbortError>()),
    );
    expect(adapter.calls, 0);
  });
  test('a fast polling handshake ACK waits for the POST continuation before reaching signalr_netcore', () async {
    final postGate = Completer<ResponseBody>();
    final adapter = _Adapter(
      (request, _) async => request.method == 'POST'
          ? postGate.future
          : ResponseBody.fromString('{}\u001e', 200),
    );
    final client = CancellableSignalRHttpClient(adapter: adapter);
    addTearDown(client.close);
    final post = client.post(
      'http://gateway.test/hubs/notifications?id=test',
      options: SignalRHttpRequest(
        content: '{"protocol":"json","version":1}\u001e',
      ),
    );
    var ackDelivered = false;
    final ack = client
        .get(
          'http://gateway.test/hubs/notifications?id=test',
          options: SignalRHttpRequest(),
        )
        .then((response) {
          ackDelivered = true;
          return response;
        });
    await Future<void>.delayed(Duration.zero);
    expect(ackDelivered, false);
    postGate.complete(ResponseBody.fromString('', 200));
    await post;
    expect((await ack).content, '{}\u001e');
  });
}
