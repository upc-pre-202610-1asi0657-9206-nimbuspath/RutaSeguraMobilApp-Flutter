import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/common.dart';
import '../../application/trip_controller.dart';
import '../../domain/model/trip_models.dart';

/// Reporte de incidente durante el viaje. Lo envía al backend y devuelve un
/// [Incident] si se aceptó.
class ReportIncidentPage extends ConsumerStatefulWidget {
  const ReportIncidentPage({super.key, required this.trip});

  final ScheduledTrip trip;

  @override
  ConsumerState<ReportIncidentPage> createState() => _ReportIncidentPageState();
}

class _ReportIncidentPageState extends ConsumerState<ReportIncidentPage> {
  IncidentType? _type;
  bool _notifyParents = true;
  bool _sending = false;
  String? _error;
  final _detail = TextEditingController();

  String get _detailText => _detail.text.trim();

  /// "Otro" exige un detalle.
  bool get _canSend =>
      _type != null &&
      !_sending &&
      (!_type!.requiresDetail || _detailText.isNotEmpty);

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what estará disponible próximamente.')),
    );
  }

  Future<void> _send() async {
    final type = _type!;
    final detail = _detailText.isEmpty ? null : _detailText;
    setState(() {
      _sending = true;
      _error = null;
    });
    final result = await ref
        .read(tripControllerProvider(widget.trip).notifier)
        .reportIncident(
          type: type,
          notifyGuardians: _notifyParents,
          detail: detail,
        );
    if (!mounted) return;
    final error = result.error;
    if (error != null) {
      setState(() {
        _sending = false;
        _error = error.userMessage;
      });
      return;
    }
    Navigator.of(context).pop(
      Incident(
        type: type,
        at: DateTime.now(),
        detail: detail,
        notifyParents: _notifyParents,
        queued: result.queued,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Mantiene vivo el controlador del viaje mientras se envía el reporte.
    ref.watch(tripControllerProvider(widget.trip));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BackChevron(),
                  ),
                  const SizedBox(height: 8),
                  Text('Reportar incidente', style: AppText.displayStyle(28)),
                  const SizedBox(height: 18),
                  Text('¿Qué pasó?', style: AppText.section),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.9,
                    children: [
                      for (final t in IncidentType.values)
                        _OptionTile(
                          label: t.label,
                          selected: _type == t,
                          onTap: () => setState(() => _type = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    _type?.requiresDetail ?? false
                        ? 'Detalle (obligatorio)'
                        : 'Detalle (opcional)',
                    style: AppText.section,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _detail,
                    onChanged: (_) => setState(() {}),
                    maxLength: incidentDetailMaxLength,
                    minLines: 3,
                    maxLines: 5,
                    style: AppText.bodyText.copyWith(fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'Ej. Choque leve en la esquina con Javier Prado, nadie herido',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: DashedButton(
                          icon: Icons.photo_camera_outlined,
                          label: 'Añadir foto',
                          onTap: () => _comingSoon('La cámara'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DashedButton(
                          icon: Icons.mic_none_rounded,
                          label: 'Nota de voz',
                          onTap: () => _comingSoon('La grabación de voz'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    onTap: () =>
                        setState(() => _notifyParents = !_notifyParents),
                    child: Row(
                      children: [
                        _NavyCheckbox(value: _notifyParents),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Avisar a los padres de la ruta',
                                style: AppText.itemTitle.copyWith(fontSize: 17),
                              ),
                              Text(
                                'Tu empresa siempre recibe el reporte',
                                style: AppText.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(
                        color: AppColors.danger,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  AppButton(
                    label: _sending
                        ? 'Enviando…'
                        : _type == null
                        ? 'Elige qué pasó para enviar'
                        : _type!.requiresDetail && _detailText.isEmpty
                        ? 'Cuéntanos qué pasó para enviar'
                        : 'Enviar reporte',
                    icon: _canSend ? Icons.send_rounded : null,
                    onPressed: _canSend ? _send : null,
                    height: 64,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sin señal, el reporte se guarda y se envía al reconectar.',
                    style: AppText.caption.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.navy : AppColors.border,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 2,
                style: AppText.itemTitle.copyWith(
                  fontSize: 16,
                  height: 1.1,
                  color: selected ? Colors.white : AppColors.navy,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavyCheckbox extends StatelessWidget {
  const _NavyCheckbox({required this.value});
  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: value ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.navy, width: 2),
      ),
      child: value
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 24)
          : null,
    );
  }
}
