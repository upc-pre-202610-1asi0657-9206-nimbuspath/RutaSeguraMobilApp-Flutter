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
import '../../application/driver_profile_provider.dart';
import '../../application/session_controller.dart';
import '../../domain/model/driver.dart';

/// Pantalla "Perfil": datos del conductor, licencia, vehículo y rutas.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(driverProfileProvider);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionActive ? session.user : null;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
        children: [
          if (user != null)
            _Header(
              initials: user.initials,
              name: user.fullName,
              company: profile.value?.organizationName,
            ),
          ...switch (profile) {
            AsyncData(:final value) => _content(value),
            AsyncError(:final error) => [
                _ErrorBox(
                  message: error is ApiError
                      ? error.userMessage
                      : 'No pudimos cargar tu perfil.',
                  onRetry: () => ref.invalidate(driverProfileProvider),
                ),
              ],
            _ => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
          },
          const SizedBox(height: 22),
          AppButton(
            label: 'Cerrar sesión',
            variant: AppButtonVariant.dangerText,
            fontSize: 17,
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(DriverProfile p) {
    final license = p.driver;
    final vehicle = p.vehicles.isEmpty ? null : p.vehicles.first;
    return [
      const SectionTitle('Licencia'),
      AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(license.licenseCategory,
                      style: AppText.displayStyle(22, weight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Vence el ${DateFmt.longDate(license.licenseExpiresOn)}',
                    style: AppText.caption.copyWith(fontSize: 15),
                  ),
                ],
              ),
            ),
            license.hasValidLicense
                ? const StatusChip(label: 'Vigente')
                : const StatusChip(
                    label: 'No vigente',
                    background: Color(0xFFFBE4E2),
                    foreground: AppColors.danger,
                  ),
          ],
        ),
      ),
      const SectionTitle('Vehículo asignado'),
      if (vehicle == null)
        Text('Aún no tienes un vehículo asignado.', style: AppText.caption)
      else
        AppCardList(
          rowPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          children: [
            _KeyValue('Placa', vehicle.licensePlate),
            _KeyValue('Modelo', vehicle.displayName),
            _KeyValue('Capacidad', '${vehicle.seatingCapacity} asientos'),
            // El SOAT no existe en el modelo de Vehicle del backend (brecha #3).
          ],
        ),
      const SectionTitle('Mis rutas'),
      if (p.routes.isEmpty)
        Text('Aún no tienes rutas asignadas.', style: AppText.caption)
      else
        AppCardList(
          children: [
            for (final r in p.routes)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: AppText.itemTitle),
                        Text(
                          '${r.direction == 'RETURN' ? 'Retorno' : 'Recojo'}'
                          ' · ${DateFmt.operatingDays(r.operatingDays)}',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  Text(r.departureTime,
                      style: AppText.itemTitle
                          .copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
          ],
        ),
      const SizedBox(height: 18),
      Text(
        '¿Algún dato está mal? Tu empresa de transporte puede corregirlo.',
        style: AppText.caption.copyWith(fontSize: 15),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.initials, required this.name, this.company});

  final String initials;
  final String name;
  final String? company;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          InitialsAvatar(initials: initials, size: 80, dark: true),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.displayStyle(24)),
                if (company != null && company!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Conductor en $company',
                      style: AppText.caption.copyWith(fontSize: 15)),
                ],
              ],
            ),
          ),
        ],
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(
          children: [
            Text(message,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(fontSize: 16)),
            const SizedBox(height: 16),
            AppButton(
              label: 'Reintentar',
              variant: AppButtonVariant.outline,
              fontSize: 17,
              onPressed: onRetry,
            ),
          ],
        ),
      );
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
