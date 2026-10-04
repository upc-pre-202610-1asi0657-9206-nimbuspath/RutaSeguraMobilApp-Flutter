import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/common.dart';
import '../../domain/model/trip_models.dart';
import '../widgets/student_boarding_card.dart';

/// Registro de abordaje (o descenso) de los alumnos de una parada.
/// Devuelve la lista de [BoardingRecord] al confirmar la parada.
class BoardingPage extends StatefulWidget {
  const BoardingPage({
    super.key,
    required this.stop,
    required this.stopNumber,
    required this.totalStops,
    this.isPickup = true,
  });

  final Stop stop;
  final int stopNumber;
  final int totalStops;
  final bool isPickup;

  @override
  State<BoardingPage> createState() => _BoardingPageState();
}

class _BoardingPageState extends State<BoardingPage> {
  late final List<BoardingRecord> _records = [
    for (final s in widget.stop.students) BoardingRecord(student: s),
  ];

  int get _pending =>
      _records.where((r) => r.status == BoardingStatus.pending).length;

  void _set(int i, BoardingStatus status) {
    setState(() {
      _records[i] = _records[i].copyWith(
        status: status,
        at: status == BoardingStatus.pending ? null : DateTime.now(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final movement = widget.isPickup ? 'subida' : 'bajada';

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 18, 0),
              child: Row(
                children: [
                  const BackChevron(),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('La cámara se conectará en la siguiente fase.')),
                    ),
                    icon: const Icon(Icons.photo_camera_outlined, color: AppColors.navy),
                    label: Text('Foto', style: AppText.itemTitle.copyWith(fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border, width: 1.5),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Parada ${widget.stopNumber} de ${widget.totalStops}, $movement',
                    style: AppText.caption.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(widget.stop.address, style: AppText.displayStyle(26)),
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
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                itemCount: _records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (_, i) => StudentBoardingCard(
                  record: _records[i],
                  isPickup: widget.isPickup,
                  onBoarded: () => _set(i, BoardingStatus.boarded),
                  onAbsent: () => _set(i, BoardingStatus.absent),
                  onUndo: () => _set(i, BoardingStatus.pending),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: AppButton(
                label: _pending > 0
                    ? 'Faltan registrar $_pending ${_pending == 1 ? 'alumno' : 'alumnos'}'
                    : 'Confirmar parada',
                icon: _pending > 0 ? null : Icons.check_rounded,
                onPressed: _pending > 0 ? null : () => Navigator.of(context).pop(_records),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
