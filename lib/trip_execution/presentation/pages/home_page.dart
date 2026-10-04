import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/common.dart';
import '../../../iam/infrastructure/mock_driver_repository.dart';
import '../../domain/model/trip_models.dart';
import '../../infrastructure/mock_trip_repository.dart';
import 'active_trip_page.dart';

/// Pantalla "Inicio": próximo viaje, checklist previo y viajes del día.
class HomePage extends StatelessWidget {
  const HomePage({super.key, this.onAvatarTap});

  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final driver = MockDriverRepository.currentDriver;
    final now = DateTime.now();
    const next = MockTripRepository.morningTrip;
    const later = MockTripRepository.afternoonTrip;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
        children: [
          // Encabezado
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DateFmt.longDay(now), style: AppText.caption.copyWith(fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFmt.greeting(now)}, ${driver.firstName}',
                      style: AppText.displayStyle(26),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onAvatarTap,
                child: InitialsAvatar(initials: driver.initials, size: 54, dark: true),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _NextTripCard(
            trip: next,
            onStart: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ActiveTripPage(trip: next),
              ),
            ),
          ),
          const SectionTitle('Antes de salir'),
          const AppCardList(
            children: [
              IconInfoRow(
                icon: Icons.check_circle_outline_rounded,
                iconColor: AppColors.success,
                title: 'GPS activado',
                subtitle: 'Precisión de 8 m',
              ),
              IconInfoRow(
                icon: Icons.check_circle_outline_rounded,
                iconColor: AppColors.success,
                title: 'Datos móviles con señal',
                subtitle: 'Los padres verán el bus en vivo',
              ),
              IconInfoRow(
                icon: Icons.error_outline_rounded,
                iconColor: AppColors.warning,
                title: 'Batería al 34 %',
                subtitle: 'Conecta el cargador antes de partir',
              ),
            ],
          ),
          const SectionTitle('Más tarde hoy'),
          AppCard(
            child: Row(
              children: [
                Text(
                  later.departure,
                  style: AppText.displayStyle(22, weight: FontWeight.w700),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(later.title, style: AppText.itemTitle),
                      const SizedBox(height: 2),
                      Text(
                        '${later.destination}, ${later.studentsCount} alumnos',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Tu ubicación se comparte solo mientras un viaje está en curso.',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _NextTripCard extends StatelessWidget {
  const _NextTripCard({required this.trip, required this.onStart});

  final ScheduledTrip trip;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    const muted = AppColors.textOnDarkMuted;

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
              Text('Tu próximo viaje', style: AppText.caption.copyWith(color: muted, fontSize: 15)),
              Text(trip.kind.longLabel, style: AppText.caption.copyWith(color: muted, fontSize: 15)),
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
            label: 'Iniciar viaje',
            icon: Icons.play_arrow_outlined,
            onPressed: onStart,
            height: 68,
            fontSize: 20,
          ),
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
