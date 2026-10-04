import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/common.dart';
import '../../../trip_execution/infrastructure/mock_trip_repository.dart';
import '../../infrastructure/mock_driver_repository.dart';
import 'login_page.dart';

/// Pantalla "Perfil": datos del conductor, licencia, vehículo y rutas.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  @override
  Widget build(BuildContext context) {
    final driver = MockDriverRepository.currentDriver;
    final license = driver.license;
    final vehicle = driver.vehicle;
    final soat = vehicle.soatValidUntil;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
        children: [
          Row(
            children: [
              InitialsAvatar(initials: driver.initials, size: 80, dark: true),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.fullName, style: AppText.displayStyle(24)),
                    const SizedBox(height: 4),
                    Text('Conductor en ${driver.company}', style: AppText.caption.copyWith(fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
          const SectionTitle('Licencia'),
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(license.category, style: AppText.displayStyle(22, weight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        'Vence el ${license.expiresOn.day} de ${_months[license.expiresOn.month - 1]} de ${license.expiresOn.year}',
                        style: AppText.caption.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                ),
                license.isValid
                    ? const StatusChip(label: 'Vigente')
                    : const StatusChip(
                        label: 'Vencida',
                        background: Color(0xFFFBE4E2),
                        foreground: AppColors.danger,
                      ),
              ],
            ),
          ),
          const SectionTitle('Vehículo asignado'),
          AppCardList(
            rowPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            children: [
              _KeyValue('Placa', vehicle.plate),
              _KeyValue('Modelo', vehicle.model),
              _KeyValue('Capacidad', '${vehicle.seats} asientos'),
              _KeyValue('SOAT', 'Vigente hasta ${soat.month.toString().padLeft(2, '0')}/${soat.year}'),
            ],
          ),
          const SectionTitle('Mis rutas'),
          AppCardList(
            children: [
              for (final r in MockTripRepository.myRoutes)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title, style: AppText.itemTitle),
                          Text(r.schedule, style: AppText.caption),
                        ],
                      ),
                    ),
                    Text(r.departure, style: AppText.itemTitle.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '¿Algún dato está mal? Tu empresa de transporte puede corregirlo.',
            style: AppText.caption.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 22),
          AppButton(
            label: 'Cerrar sesión',
            variant: AppButtonVariant.dangerText,
            fontSize: 17,
            onPressed: () => Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (_) => false,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppText.caption.copyWith(fontSize: 16)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppText.itemTitle.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
