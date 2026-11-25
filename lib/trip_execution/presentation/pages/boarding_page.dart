import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/common.dart';
import '../../../stakeholder/application/students_repository.dart';
import '../../../stakeholder/domain/model/route_student.dart';
import '../../application/trip_controller.dart';
import '../../application/trip_operational_details.dart';
import '../../domain/model/trip_live.dart';
import '../../domain/model/trip_models.dart';
import '../../infrastructure/trip_api.dart';
import '../widgets/student_avatar.dart';
import '../widgets/student_boarding_card.dart';

/// Registro de asistencia, con acceso a todo el padrón del viaje.
///
/// Cada toque se aplica al instante y se envía al servidor con su propio
/// `clientEventId`; si el servidor lo rechaza, la fila vuelve a su estado.
class BoardingPage extends ConsumerStatefulWidget {
  const BoardingPage({super.key, required this.trip});

  final ScheduledTrip trip;

  @override
  ConsumerState<BoardingPage> createState() => _BoardingPageState();
}

class _BoardingPageState extends ConsumerState<BoardingPage> {
  bool _showAll = false;

  Future<void> _recordDropoff(TripLive live, LivePassenger passenger, String? name) async {
    if (!live.canAlightAtCurrentOrReachedStop(passenger)) {
      final stop = live.stop(passenger.stopId)?.name ?? 'la parada asignada';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Confirmar bajada'),
          content: Text('Confirma que ${name ?? 'este alumno'} bajó en $stop.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Volver')),
            TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Confirmar bajada')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _run(context, ref, (c) => c.record(PassengerAction.alight, passenger.studentId));
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<ActionResult> Function(TripController c) action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await action(
      ref.read(tripControllerProvider(widget.trip).notifier),
    );
    final text =
        result.error?.userMessage ??
        (result.queued
            ? 'Sin señal: se guardó y se enviará al reconectar.'
            : null);
    if (text != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(tripControllerProvider(widget.trip)).value;
    final students = {
      for (final s
          in ref.watch(studentsProvider).value ?? const <RouteStudent>[])
        s.studentId: s,
    };
    if (live == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final detailsProvider = tripOperationalDetailsProvider(
      tripDetailsKey(live),
    );
    final details = ref.watch(detailsProvider);
    final next = live.nextStop;
    final passengers =
        (_showAll ? live.passengers : live.attendancePassengers).toList()..sort(
          (a, b) => (a.status == PassengerStatus.pending ? 0 : 1).compareTo(
            b.status == PassengerStatus.pending ? 0 : 1,
          ),
        );
    final pending = passengers
        .where((p) => p.status == PassengerStatus.pending)
        .length;
    final isPickup = live.isPickup;
    final boardingAtSchool = !isPickup && pending > 0;
    final dropoffs = passengers
        .where(live.canAlightAtCurrentOrReachedStop)
        .length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 18, 0),
              child: Row(children: [BackChevron(), Spacer()]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    boardingAtSchool
                        ? 'Abordaje de retorno'
                        : next == null
                        ? 'Alumnos por registrar'
                        : 'Parada ${next.sequence} de ${next.totalStops}, ${isPickup ? 'subida' : 'bajada'}',
                    style: AppText.caption.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    boardingAtSchool
                        ? (live.stops.firstOrNull?.name ?? 'Colegio')
                        : next?.name ?? widget.trip.destination,
                    style: AppText.displayStyle(26),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cada registro guarda la hora y tu ubicación.',
                    style: AppText.caption.copyWith(fontSize: 15),
                  ),
                  if (passengers.length != live.passengers.length || _showAll)
                    TextButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      child: Text(
                        _showAll
                            ? 'Ver asistencia de la parada'
                            : 'Ver todo el padrón',
                      ),
                    ),
                  if (details.hasError)
                    TextButton(
                      onPressed: () => ref.invalidate(detailsProvider),
                      child: const Text(
                        'No pudimos consultar el padrón. Reintentar',
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: passengers.isEmpty
                  ? Center(
                      child: Text(
                        'No hay alumnos en esta parada.',
                        style: AppText.caption.copyWith(fontSize: 16),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      itemCount: passengers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (_, i) {
                        final p = passengers[i];
                        final info = students[p.studentId];
                        final name =
                            details.value?.names[p.studentId] ?? info?.fullName;
                        final stop = live.stop(p.stopId);
                        final stopLabel =
                            !isPickup && p.status == PassengerStatus.pending
                            ? 'Sube en el colegio'
                            : _showAll || p.stopId != next?.stopId
                            ? stop?.name ?? ''
                            : '';
                        final id = p.studentId;
                        return StudentBoardingCard(
                          record: BoardingRecord(
                            student: Student(
                              id: id,
                              fullName:
                                  name ??
                                  (details.isLoading
                                      ? 'Cargando nombre…'
                                      : 'Nombre no disponible'),
                              grade: [
                                info?.schoolGrade ?? '',
                                stopLabel,
                              ].where((value) => value.isNotEmpty).join(' · '),
                              guardianNotice: p.absentByGuardian
                                  ? (p.absenceNote?.isNotEmpty ?? false
                                        ? 'Su apoderado avisó que hoy no asiste: ${p.absenceNote}'
                                        : 'Su apoderado avisó que hoy no asiste.')
                                  : null,
                            ),
                            status: switch (p.status) {
                              PassengerStatus.pending => BoardingStatus.pending,
                              PassengerStatus.boarded => BoardingStatus.boarded,
                              PassengerStatus.alighted =>
                                BoardingStatus.alighted,
                              PassengerStatus.absent => BoardingStatus.absent,
                            },
                            at:
                                p.alightedAt?.toLocal() ??
                                p.boardedAt?.toLocal(),
                          ),
                          avatar: info == null
                              ? null
                              : StudentAvatar(student: info),
                          onBoarded: () => _run(
                            context,
                            ref,
                            (c) => c.record(PassengerAction.board, id),
                          ),
                          onAbsent: () => _run(
                            context,
                            ref,
                            (c) => c.record(PassengerAction.absent, id),
                          ),
                          onUndo: () => _run(context, ref, (c) => c.undo(id)),
                          onAlighted: !live.canAlightAtCurrentOrReachedStop(p) &&
                                  !(_showAll && !isPickup && p.status == PassengerStatus.boarded)
                              ? null
                              : () => _recordDropoff(live, p, name),
                        );
                      },
                    ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: AppButton(
                label: pending > 0
                    ? 'Faltan registrar $pending ${pending == 1 ? 'alumno' : 'alumnos'}'
                    : dropoffs > 0
                    ? 'Faltan registrar $dropoffs bajadas'
                    : 'Confirmar parada',
                icon: pending > 0 || dropoffs > 0 ? null : Icons.check_rounded,
                onPressed: pending > 0 || dropoffs > 0
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
