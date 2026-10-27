import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_error.dart';
import '../../core/storage/local_cache.dart';
import '../../core/utils/date_format.dart';
import '../../iam/application/session_controller.dart';
import '../../iam/infrastructure/roster_api.dart';
import '../domain/model/trip_models.dart';
import '../infrastructure/trip_api.dart';

/// Agenda de hoy. [fromCache] indica que no hubo conexión y se muestra lo
/// último guardado.
class Agenda {
  const Agenda(this.trips, {this.fromCache = false});

  /// Sin viajes completados, ordenada por hora.
  final List<ScheduledTrip> trips;
  final bool fromCache;

  /// "Tu próximo viaje": el primero que no está completado.
  ScheduledTrip? get next => trips.isEmpty ? null : trips.first;

  /// "Más tarde hoy".
  List<ScheduledTrip> get later => trips.length > 1 ? trips.sublist(1) : const [];
}

/// Sin reintento automático de Riverpod: la UI ofrece "Reintentar" y se cae a
/// la caché sin señal.
Duration? _noRetry(int retryCount, Object error) => null;

final agendaProvider = FutureProvider<Agenda>(retry: _noRetry, (ref) async {
  final session = ref.watch(sessionControllerProvider);
  if (session is! SessionActive) return const Agenda([]);

  final cache = ref.watch(localCacheProvider);
  final key = 'agenda.${session.user.id}';
  final today = DateFmt.limaDateKey(DateTime.now());

  Map<String, dynamic>? stored() {
    final raw = cache.read(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  List<ScheduledTrip> open(List<ScheduledTrip> all) =>
      [for (final t in all) if (!t.isCompleted) t];

  try {
    final trips = await ref.watch(tripApiProvider).agenda();

    // La placa sale de cruzar `vehicleId` con los vehículos del conductor.
    // Si esa consulta falla, se usan las placas de la última agenda guardada.
    final plates = <String, String>{};
    try {
      for (final v in await ref.watch(rosterApiProvider).vehicles()) {
        plates[v.id] = v.licensePlate;
      }
    } on ApiError {
      for (final t in (stored()?['trips'] as List?) ?? const []) {
        final m = t as Map<String, dynamic>;
        final id = m['vehicleId'] as String?;
        if (id != null) plates[id] = m['vehiclePlate'] as String? ?? '—';
      }
    }
    final resolved = [
      for (final t in trips) t.withVehiclePlate(plates[t.vehicleId] ?? '—'),
    ];

    await cache.write(
      key,
      jsonEncode({'day': today, 'trips': [for (final t in resolved) t.toJson()]}),
    );
    return Agenda(open(resolved));
  } on ApiError catch (e) {
    final offline = e.kind == ApiErrorKind.network ||
        e.kind == ApiErrorKind.timeout ||
        (e.status ?? 0) >= 500;
    final saved = stored();
    // Solo se muestra la agenda guardada si es de hoy.
    if (offline && saved != null && saved['day'] == today) {
      return Agenda(
        open([
          for (final t in saved['trips'] as List)
            ScheduledTrip.fromJson(t as Map<String, dynamic>),
        ]),
        fromCache: true,
      );
    }
    rethrow;
  }
});

/// Hora actual, refrescada cada 30 s (para habilitar "Iniciar viaje" cuando
/// se abre la ventana de 60 min).
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});
