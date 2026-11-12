import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/network/connectivity.dart';
import '../domain/model/trip_models.dart';
import '../infrastructure/trip_api.dart';
import '../infrastructure/trip_realtime.dart';
import 'agenda_provider.dart';

/// Un viaje de la agenda que la empresa canceló.
class CancelledTrip {
  const CancelledTrip(this.trip, {this.reason});

  final ScheduledTrip trip;

  /// Motivo, solo si llegó por el canal en tiempo real.
  final String? reason;

  String get message {
    final base = 'Tu empresa canceló ${trip.title} de las ${trip.departure}.';
    final why = reason?.trim();
    return why == null || why.isEmpty ? base : '$base\nMotivo: $why';
  }
}

/// Cada cuánto se vuelve a pedir la agenda mientras Inicio está abierto.
final agendaRefreshEveryProvider =
    Provider<Duration>((ref) => const Duration(seconds: 30));

/// Mantiene la agenda al día y avisa cuando la empresa cancela un viaje.
///
/// El backend solo permite cancelar un viaje **antes de iniciarlo** y la
/// agenda no lista los cancelados, así que una cancelación se ve como un viaje
/// programado que desaparece. Hay dos vías, y vale la primera que llegue:
///
/// - el canal en tiempo real de cada viaje programado: es inmediato y trae el
///   motivo;
/// - la agenda que se refresca sola (cada [agendaRefreshEveryProvider], al
///   volver a la app y al recuperar la conexión): un viaje que desaparece se
///   confirma con `/live`, porque también desaparece al iniciarse o
///   completarse y eso no es una cancelación.
///
/// El estado es la última cancelación sin mostrar; la pantalla la muestra y
/// llama a [acknowledge].
class AgendaWatcher extends Notifier<CancelledTrip?> {
  late TripApi _api;
  late TripRealtime _realtime;

  final _subs = <String, StreamSubscription<RealtimeEvent>>{};
  final _connectedOnce = <String>{};
  final _announced = <String>{};

  /// Viajes que desaparecieron y aún no se pudieron confirmar (sin señal).
  final _unverified = <String, ScheduledTrip>{};

  var _known = <ScheduledTrip>[];

  @override
  CancelledTrip? build() {
    _api = ref.read(tripApiProvider);
    _realtime = ref.read(tripRealtimeProvider);

    final timer = Timer.periodic(ref.read(agendaRefreshEveryProvider), (_) => _refresh());
    final lifecycle = AppLifecycleListener(onResume: _refresh);
    ref.onDispose(() {
      timer.cancel();
      lifecycle.dispose();
      for (final s in _subs.values) {
        s.cancel();
      }
      _subs.clear();
    });

    ref.listen(connectivityRestoredProvider, (_, next) {
      if (next.value == true) _refresh();
    });
    ref.listen(agendaProvider, (_, next) {
      final agenda = next.value;
      if (agenda != null) _onAgenda(agenda);
    }, fireImmediately: true);
    return null;
  }

  /// La pantalla ya mostró el aviso.
  void acknowledge() {
    if (ref.mounted) state = null;
  }

  void _refresh() {
    if (ref.mounted) ref.invalidate(agendaProvider);
  }

  void _onAgenda(Agenda agenda) {
    final upcoming = [
      for (final t in agenda.trips)
        if (t.status == 'Scheduled') t,
    ];
    final ids = {for (final t in upcoming) t.id};

    for (final t in _known) {
      if (ids.contains(t.id)) continue;
      _subs.remove(t.id)?.cancel();
      _connectedOnce.remove(t.id);
      unawaited(_verifyCancelled(t));
    }
    for (final t in List.of(_unverified.values)) {
      unawaited(_verifyCancelled(t));
    }

    for (final t in upcoming) {
      _subs.putIfAbsent(
        t.id,
        () => _realtime.watch(t.id).listen((e) => _onRealtime(t, e), onError: (_) {}),
      );
    }
    _known = upcoming;
  }

  void _onRealtime(ScheduledTrip trip, RealtimeEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case RealtimeConnected():
        // La primera conexión sigue a una agenda recién pedida. Las
        // siguientes son reconexiones: pudo cambiar algo mientras no había
        // canal.
        if (!_connectedOnce.add(trip.id)) _refresh();
      case RealtimeStatusChanged(:final status, :final reason):
        if (status != 'Cancelled') return;
        _announce(trip, reason);
        _refresh();
    }
  }

  /// Un viaje programado dejó de estar en la agenda: se avisa solo si de
  /// verdad está cancelado.
  Future<void> _verifyCancelled(ScheduledTrip trip) async {
    try {
      final live = await _api.live(trip.id);
      _unverified.remove(trip.id);
      if (live.status == 'Cancelled') _announce(trip, null);
    } on ApiError {
      // Sin señal: se reintenta con la próxima agenda.
      _unverified[trip.id] = trip;
    }
  }

  void _announce(ScheduledTrip trip, String? reason) {
    if (!ref.mounted || !_announced.add(trip.id)) return;
    state = CancelledTrip(trip, reason: reason);
  }
}

final agendaWatcherProvider =
    NotifierProvider.autoDispose<AgendaWatcher, CancelledTrip?>(AgendaWatcher.new);
