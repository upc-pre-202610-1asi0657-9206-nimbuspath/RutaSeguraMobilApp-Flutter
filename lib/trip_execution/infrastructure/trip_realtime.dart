import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/token_storage.dart';

/// Lo que llega del canal en tiempo real de un viaje.
sealed class RealtimeEvent {
  const RealtimeEvent();
}

/// El canal quedó (re)suscrito al viaje. Pudo pasar algo mientras estuvo
/// caído, así que conviene pedir `/live` otra vez.
class RealtimeConnected extends RealtimeEvent {
  const RealtimeConnected();
}

/// `TripStatusChanged`: el viaje inició, se retrasó, terminó o se canceló.
class RealtimeStatusChanged extends RealtimeEvent {
  const RealtimeStatusChanged({required this.status, this.reason});

  /// `InProgress` | `Delayed` | `Completed` | `Cancelled`.
  final String status;
  final String? reason;

  /// Convierte los argumentos que entrega SignalR. `null` si no tienen la
  /// forma esperada (un mensaje raro no debe tumbar el canal).
  static RealtimeStatusChanged? tryParse(List<Object?>? args) {
    if (args == null || args.isEmpty) return null;
    final body = args.first;
    if (body is! Map) return null;
    final status = body['status'];
    if (status is! String || status.isEmpty) return null;
    final reason = body['reason'];
    return RealtimeStatusChanged(
      status: status,
      reason: reason is String ? reason : null,
    );
  }
}

/// Canal en tiempo real de un viaje (hub `/hubs/trip-tracking`).
///
/// Es un complemento: si no hay conexión, la app sigue funcionando con el
/// refresco periódico de `/live`.
abstract interface class TripRealtime {
  /// Se conecta al escuchar y se desconecta al cancelar la suscripción.
  /// Reintenta sola con espera creciente.
  Stream<RealtimeEvent> watch(String tripId);
}

/// SignalR a través del API Gateway, con el JWT en `?access_token=`.
class SignalRTripRealtime implements TripRealtime {
  SignalRTripRealtime({
    required this.hubUrl,
    required this.readToken,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  });

  final String hubUrl;
  final Future<String?> Function() readToken;
  final List<Duration> retryDelays;

  @override
  Stream<RealtimeEvent> watch(String tripId) {
    final controller = StreamController<RealtimeEvent>();
    final stop = Completer<void>();
    HubConnection? hub;

    Future<void> close() async {
      final h = hub;
      hub = null;
      try {
        await h?.stop();
      } catch (_) {}
    }

    Future<void> run() async {
      var attempt = 0;
      while (!stop.isCompleted) {
        final dropped = Completer<void>();
        try {
          final h = hub = _build();
          h.on('TripStatusChanged', (args) {
            final e = RealtimeStatusChanged.tryParse(args);
            if (e != null && !controller.isClosed) controller.add(e);
          });
          h.onclose(({error}) {
            if (!dropped.isCompleted) dropped.complete();
          });
          await h.start();
          // Los grupos de SignalR se pierden al reconectar: se vuelve a entrar.
          await h.invoke('SubscribeToTrip', args: [tripId]);
          attempt = 0;
          if (!controller.isClosed) controller.add(const RealtimeConnected());
          await Future.any([dropped.future, stop.future]);
        } catch (_) {
          // Sin red, token vencido, viaje ajeno...: se reintenta más abajo.
        } finally {
          await close();
        }
        if (stop.isCompleted) break;
        final wait = retryDelays[attempt < retryDelays.length ? attempt : retryDelays.length - 1];
        attempt++;
        await Future.any([Future<void>.delayed(wait), stop.future]);
      }
    }

    controller.onListen = () => unawaited(run());
    controller.onCancel = () async {
      if (!stop.isCompleted) stop.complete();
      await close();
    };
    return controller.stream;
  }

  HubConnection _build() => HubConnectionBuilder()
      .withUrl(
        hubUrl,
        options: HttpConnectionOptions(
          // El Gateway reenvía el WebSocket tal cual: se evita la negociación.
          transport: HttpTransportType.WebSockets,
          skipNegotiation: true,
          accessTokenFactory: () async => await readToken() ?? '',
        ),
      )
      .build();
}

final tripRealtimeProvider = Provider<TripRealtime>((ref) {
  final tokens = ref.watch(tokenStorageProvider);
  return SignalRTripRealtime(
    hubUrl: '${AppConfig.apiBaseUrl}/hubs/trip-tracking',
    readToken: tokens.read,
  );
});
