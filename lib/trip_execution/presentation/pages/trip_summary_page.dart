import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/common.dart';
import '../../domain/model/trip_models.dart';

/// Resumen al finalizar el viaje.
class TripSummaryPage extends StatelessWidget {
  const TripSummaryPage({super.key, required this.summary});

  final TripSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final one = s.arrivedCount == 1;
    final arrivalPlace = s.trip.kind == TripKind.pickup
        ? (one ? 'alumno llegó al colegio' : 'alumnos llegaron al colegio')
        : (one ? 'alumno llegó a casa' : 'alumnos llegaron a casa');

    final incidentsTitle = switch (s.incidents.length) {
      0 => 'Sin incidentes',
      1 => '1 incidente reportado',
      final n => '$n incidentes reportados',
    };
    final incidentsDetail = s.incidents.isEmpty
        ? 'Viaje sin novedades'
        : s.incidents.map((i) => '${i.type.label}, ${DateFmt.time(i.at)}').join(' · ');

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      Text(
                        '${s.trip.title} de ${DateFmt.time(s.startedAt)} a ${DateFmt.time(s.endedAt)}',
                        style: AppText.caption.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text('Viaje finalizado', style: AppText.displayStyle(30)),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${s.arrivedCount}',
                                  style: AppText.displayStyle(64, color: AppColors.yellow, height: 1),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      arrivalPlace,
                                      style: AppText.bodyText.copyWith(color: Colors.white, fontSize: 17),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (s.absentStudents.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Divider(color: Color(0xFF2E3F5C), height: 1),
                              const SizedBox(height: 14),
                              Text(
                                '${s.absentStudents.length} no ${s.absentStudents.length == 1 ? 'vino' : 'vinieron'}: '
                                '${s.absentStudents.map((st) => st.guardianNotice != null ? '${st.fullName} (aviso del apoderado)' : st.fullName).join(', ')}',
                                style: AppText.bodyText.copyWith(color: Colors.white, fontSize: 16),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      AppCardList(
                        children: [
                          IconInfoRow(
                            icon: s.incidents.isEmpty
                                ? Icons.check_circle_outline_rounded
                                : Icons.warning_amber_rounded,
                            iconColor: s.incidents.isEmpty ? AppColors.success : AppColors.warning,
                            title: incidentsTitle,
                            subtitle: incidentsDetail,
                          ),
                          IconInfoRow(
                            icon: Icons.check_circle_outline_rounded,
                            iconColor: AppColors.success,
                            title: 'Todos los registros enviados',
                            subtitle: s.incidents.isEmpty
                                ? 'Abordajes y recorrido'
                                : 'Abordajes, incidente y recorrido',
                          ),
                          const IconInfoRow(
                            icon: Icons.location_off_outlined,
                            iconColor: AppColors.textSecondary,
                            title: 'Dejaste de compartir tu ubicación',
                            subtitle: 'Se activa otra vez al iniciar el siguiente viaje',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (s.nextTrip != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: Text(
                        'Siguiente viaje: ${s.nextTrip!.title} a las ${s.nextTrip!.departure}',
                        style: AppText.caption.copyWith(fontSize: 15),
                      ),
                    ),
                  ),
                AppButton(
                  label: 'Volver al inicio',
                  height: 64,
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
