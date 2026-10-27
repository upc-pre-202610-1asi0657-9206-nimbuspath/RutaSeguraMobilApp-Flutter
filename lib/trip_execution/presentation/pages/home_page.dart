import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/common.dart';
import '../../../iam/application/session_controller.dart';
import '../../../stakeholder/application/students_repository.dart';
import '../../application/agenda_provider.dart';
import '../../application/checklist.dart';
import '../../domain/model/trip_models.dart';
import 'active_trip_page.dart';

/// Viajes ya retomados automáticamente en esta ejecución de la app, para no
/// volver a abrir "Viaje en curso" si el conductor sale de esa pantalla.
final _resumedTrips = Provider<Set<String>>((ref) => <String>{});

/// Pantalla "Inicio": próximo viaje, checklist previo y viajes del día.
class HomePage extends ConsumerWidget {
  const HomePage({super.key, this.onAvatarTap});

  final VoidCallback? onAvatarTap;

  void _openTrip(BuildContext context, ScheduledTrip trip) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ActiveTripPage(trip: trip)),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(gpsCheckProvider);
    ref.invalidate(networkCheckProvider);
    ref.invalidate(batteryCheckProvider);
    ref.invalidate(studentsProvider);
    ref.invalidate(agendaProvider);
    await ref.read(agendaProvider.future).then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final driver = session is SessionActive ? session.user : null;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final agenda = ref.watch(agendaProvider);

    // Los alumnos se descargan al abrir Inicio (y quedan guardados para el
    // abordaje sin señal); aquí solo se dispara la carga.
    ref.watch(studentsProvider);

    // Si hay un viaje en curso (p. ej. la app se cerró), se retoma solo.
    void resume(AsyncValue<Agenda> value) {
      final trip = value.value?.next;
      if (trip == null || !trip.isInProgress) return;
      if (!ref.read(_resumedTrips).add(trip.id)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _openTrip(context, trip);
      });
    }

    ref.listen(agendaProvider, (_, next) => resume(next));
    resume(agenda);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFmt.longDay(DateFmt.toLima(now)),
                        style: AppText.caption.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateFmt.greeting(DateFmt.toLima(now))}${driver == null ? '' : ', ${driver.firstName}'}',
                        style: AppText.displayStyle(26),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onAvatarTap,
                  child: InitialsAvatar(
                    initials: driver?.initials ?? '',
                    size: 54,
                    dark: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...switch (agenda) {
              AsyncData(:final value) => _agenda(context, value, now),
              AsyncError(:final error) => [
                  _Message(
                    text: error is ApiError
                        ? error.userMessage
                        : 'No pudimos cargar tus viajes.',
                    onRetry: () => ref.invalidate(agendaProvider),
                  ),
                ],
              _ => const [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 56),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
            },
            const SectionTitle('Antes de salir'),
            const _Checklist(),
            const SizedBox(height: 22),
            Text(
              'Tu ubicación se comparte solo mientras un viaje está en curso.',
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _agenda(BuildContext context, Agenda agenda, DateTime now) {
    final next = agenda.next;
    return [
      if (agenda.fromCache)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Sin conexión: se muestra lo último guardado.',
            style: AppText.caption.copyWith(color: AppColors.warning),
          ),
        ),
      if (next == null)
        const _Message(text: 'No tienes viajes programados para hoy.')
      else
        _NextTripCard(
          trip: next,
          now: now,
          onStart: () => _openTrip(context, next),
        ),
      if (agenda.later.isNotEmpty) ...[
        const SectionTitle('Más tarde hoy'),
        for (final t in agenda.later)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              child: Row(
                children: [
                  Text(
                    t.departure,
                    style: AppText.displayStyle(22, weight: FontWeight.w700),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title, style: AppText.itemTitle),
                        const SizedBox(height: 2),
                        Text(
                          'Hacia ${t.destination}, ${t.studentsCount} alumnos',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ];
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          children: [
            Text(text, textAlign: TextAlign.center, style: AppText.itemTitle),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              AppButton(
                label: 'Reintentar',
                variant: AppButtonVariant.outline,
                fontSize: 17,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      );
}

/// Checklist "Antes de salir": GPS, datos y batería (todo local).
class _Checklist extends ConsumerWidget {
  const _Checklist();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCardList(
      children: [
        _CheckRow(
          result: ref.watch(gpsCheckProvider),
          loadingTitle: 'Buscando GPS…',
          // Si falta el permiso, tocar la fila lo pide.
          onTap: () async {
            await ref
                .read(deviceChecksProvider)
                .gps(requestPermission: true);
            ref.invalidate(gpsCheckProvider);
          },
        ),
        _CheckRow(
          result: ref.watch(networkCheckProvider),
          loadingTitle: 'Revisando conexión…',
        ),
        _CheckRow(
          result: ref.watch(batteryCheckProvider),
          loadingTitle: 'Revisando batería…',
        ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.result,
    required this.loadingTitle,
    this.onTap,
  });

  final AsyncValue<CheckResult> result;
  final String loadingTitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = result.value;
    final row = switch (r) {
      null => IconInfoRow(
          icon: Icons.hourglass_empty_rounded,
          iconColor: AppColors.textSecondary,
          title: result.hasError ? 'No se pudo verificar' : loadingTitle,
        ),
      _ => IconInfoRow(
          icon: switch (r.level) {
            CheckLevel.ok => Icons.check_circle_outline_rounded,
            CheckLevel.warning => Icons.error_outline_rounded,
            CheckLevel.error => Icons.cancel_outlined,
          },
          iconColor: switch (r.level) {
            CheckLevel.ok => AppColors.success,
            CheckLevel.warning => AppColors.warning,
            CheckLevel.error => AppColors.danger,
          },
          title: r.title,
          subtitle: r.subtitle,
        ),
    };
    return onTap != null && r?.level == CheckLevel.error
        ? InkWell(onTap: onTap, child: row)
        : row;
  }
}

class _NextTripCard extends StatelessWidget {
  const _NextTripCard({
    required this.trip,
    required this.now,
    required this.onStart,
  });

  final ScheduledTrip trip;
  final DateTime now;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    const muted = AppColors.textOnDarkMuted;
    final canStart = trip.canStart(now);
    final opensAt = trip.startWindowOpensAtLabel;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  trip.isInProgress ? 'Viaje en curso' : 'Tu próximo viaje',
                  style: AppText.caption.copyWith(color: muted, fontSize: 15),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  trip.status == 'Delayed'
                      ? 'Con retraso · ${trip.kind.longLabel}'
                      : trip.kind.longLabel,
                  textAlign: TextAlign.end,
                  style: AppText.caption.copyWith(color: muted, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.routeName,
                      style: AppText.displayStyle(26, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hacia ${trip.destination}',
                      style: AppText.bodyText.copyWith(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
              FittedBox(
                child: Text(
                  trip.departure,
                  style: AppText.displayStyle(54, color: AppColors.yellow, height: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2E3F5C), height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Stat(value: '${trip.stopsCount}', label: 'paradas')),
              Expanded(child: _Stat(value: '${trip.studentsCount}', label: 'alumnos')),
              Expanded(child: _Stat(value: trip.vehiclePlate, label: 'vehículo')),
            ],
          ),
          const SizedBox(height: 18),
          AppButton(
            label: trip.isInProgress ? 'Continuar viaje' : 'Iniciar viaje',
            icon: Icons.play_arrow_outlined,
            onPressed: canStart ? onStart : null,
            height: 68,
            fontSize: 20,
          ),
          if (!canStart && opensAt != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Disponible desde $opensAt',
                style: AppText.caption.copyWith(color: muted, fontSize: 15),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppText.body,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        Text(label, style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
      ],
    );
  }
}
