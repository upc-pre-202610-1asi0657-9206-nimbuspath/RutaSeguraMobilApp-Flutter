import 'dart:async';

import 'package:dio/dio.dart';
import 'package:signalr_netcore/signalr_http_client.dart';
import 'package:signalr_netcore/errors.dart' as signalr;

/// Cancellable HTTP for negotiation/long polling. Cancels the socket as soon as
/// SignalR stops, including a stop immediately after a successful handshake.
class CancellableSignalRHttpClient extends SignalRHttpClient {
  CancellableSignalRHttpClient({HttpClientAdapter? adapter})
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }
  final Dio _dio;
  Completer<void>? _handshakePost;
  bool _handshakeDeferred = false;

  @override
  Future<SignalRHttpResponse> send(SignalRHttpRequest request) async {
    final signal = request.abortSignal;
    if (signal?.aborted == true) throw signalr.AbortError();
    final cancellation = CancelToken();
    final handshake =
        request.method == 'POST' &&
        request.content is String &&
        (request.content as String).startsWith('{"protocol":');
    if (handshake) _handshakePost = Completer<void>();
    void abort() => cancellation.cancel('SignalR connection stopped');
    if (signal != null) signal.onabort = abort;
    try {
      final response = await _dio.request<String>(
        request.url!,
        data: request.content,
        cancelToken: cancellation,
        options: Options(
          method: request.method,
          headers: Map<String, String>.from(request.headers?.asMap ?? {}),
          contentType: 'text/plain;charset=UTF-8',
          responseType: ResponseType.plain,
          receiveTimeout: Duration(milliseconds: request.timeout ?? 15000),
        ),
      );
      if (request.method == 'GET' &&
          (response.data?.isNotEmpty ?? false) &&
          _handshakePost != null &&
          !_handshakeDeferred) {
        // signalr_netcore 1.4.4 clears its handshake completer when receiving ACK.
        // Let its POST continuation capture that completer before delivering a faster polling ACK.
        _handshakeDeferred = true;
        await _handshakePost!.future;
        await Future<void>.delayed(Duration.zero);
      }
      return SignalRHttpResponse(
        response.statusCode!,
        statusText: response.statusMessage,
        content: response.data ?? '',
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) throw signalr.AbortError();
      if (error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout)
        throw signalr.TimeoutError();
      if (error.response case final response?)
        throw signalr.HttpError('SignalR HTTP failure', response.statusCode!);
      throw signalr.GeneralError('SignalR connection unavailable');
    } finally {
      if (handshake && !(_handshakePost?.isCompleted ?? true))
        _handshakePost!.complete();
      if (signal != null && identical(signal.onabort, abort))
        signal.onabort = null;
    }
  }

  void close() => _dio.close(force: true);
}
