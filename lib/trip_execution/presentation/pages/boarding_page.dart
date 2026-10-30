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
import '../../domain/model/trip_live.dart';
import '../../domain/model/trip_models.dart';
import '../../infrastructure/trip_api.dart';
import '../widgets/student_avatar.dart';
import '../widgets/student_boarding_card.dart';

/// Registro de abordaje (o descenso) de los alumnos de la siguiente parada.
///
/// Cada toque se aplica al instante y se envía al servidor con su propio
/// `clientEventId`; si el servidor lo rechaza, la fila vuelve a su estado.
class BoardingPage extends ConsumerWidget {
  const BoardingPage({super.key, required this.trip});

  final ScheduledTrip trip;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<ActionResult> Function(TripController c) action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await action(ref.read(tripControllerProvider(trip).notifier));
    final text = result.error?.userMessage ??
        (result.queued ? 'Sin señal: se guardó y se enviará al reconectar.' : null);
    if (text != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(tripControllerProvider(trip)).value;
    final students = {
      for (final s in ref.watch(studentsProvider).value ?? const <RouteStudent>[])
        s.studentId: s,
    };
    if (live == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Parada actual: la siguiente. Sin ella (última parada), lo pendiente.
    final next = live.nextStop;
    final passengers = next == null
        ? [for (final p in live.passengers) if (p.status == PassengerStatus.pending) p]
        : live.passengersAt(next.stopId);
    final pending = passengers.where((p) => p.status == PassengerStatus.pending).length;
    final isPickup = live.isPickup;
    final movement = isPickup ? 'subida' : 'bajada';

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
                    next == null
                        ? 'Alumnos por registrar'
                        : 'Parada ${next.sequence} de ${next.totalStops}, $movement',
                    style: AppText.caption.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(next?.name ?? trip.destination, style: AppText.displayStyle(26)),
                  const SizedBox(height: 6),
                  Text(
                    'Cada registro guarda la hora y tu ubicación.',
                    style: AppText.caption.copyWith(fontSize: 15),
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
                        final id = p.studentId;
                        return StudentBoardingCard(
                          record: BoardingRecord(
                            student: Student(
                              id: id,
                              fullName: info?.fullName ?? 'Alumno sin ficha',
                              grade: info?.schoolGrade ?? '',
                              guardianNotice: p.absentByGuardian
                                  ? (p.absenceNote?.isNotEmpty ?? false
                                      ? 'Su apoderado avisó que hoy no asiste: ${p.absenceNote}'
                                      : 'Su apoderado avisó que hoy no asiste.')
                                  : null,
                            ),
                            status: switch (p.status) {
                              PassengerStatus.pending => BoardingStatus.pending,
                              PassengerStatus.boarded => BoardingStatus.boarded,
                              PassengerStatus.alighted => BoardingStatus.alighted,
                              PassengerStatus.absent => BoardingStatus.absent,
                            },
                            at: p.alightedAt?.toLocal() ?? p.boardedAt?.toLocal(),
                          ),
                          avatar: info == null
                              ? null
                              : StudentAvatar(student: info),
                          onBoarded: () => _run(context, ref,
                              (c) => c.record(PassengerAction.board, id)),
                          onAbsent: () => _run(context, ref,
                              (c) => c.record(PassengerAction.absent, id)),
                          onUndo: () => _run(context, ref, (c) => c.undo(id)),
                          onAlighted: isPickup
                              ? null
                              : () => _run(context, ref,
                                  (c) => c.record(PassengerAction.alight, id)),
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
                    : 'Confirmar parada',
                icon: pending > 0 ? null : Icons.check_rounded,
                onPressed: pending > 0 ? null : () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
