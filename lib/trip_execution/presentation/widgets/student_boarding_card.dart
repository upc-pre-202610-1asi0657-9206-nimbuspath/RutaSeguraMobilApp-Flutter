import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/common.dart';
import '../../domain/model/trip_models.dart';

/// Tarjeta de un alumno en la pantalla de abordaje.
class StudentBoardingCard extends StatelessWidget {
  const StudentBoardingCard({
    super.key,
    required this.record,
    required this.onBoarded,
    required this.onAbsent,
    required this.onUndo,
    this.isPickup = true,
  });

  final BoardingRecord record;
  final VoidCallback onBoarded;
  final VoidCallback onAbsent;
  final VoidCallback onUndo;
  final bool isPickup;

  @override
  Widget build(BuildContext context) {
    final student = record.student;
    final doneLabel = isPickup ? 'Subió' : 'Bajó';

    Widget? chip;
    if (record.status == BoardingStatus.boarded) {
      chip = StatusChip(label: '$doneLabel ${DateFmt.time(record.at!)}');
    } else if (record.status == BoardingStatus.absent) {
      chip = const StatusChip(
        label: 'No vino',
        background: AppColors.disabledBg,
        foreground: AppColors.textSecondary,
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InitialsAvatar(initials: student.initials, size: 50),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(student.fullName, style: AppText.itemTitle.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
                      Text(student.grade, style: AppText.caption.copyWith(fontSize: 15)),
                    ],
                  ),
                ),
                ?chip,
              ],
            ),
            if (record.status == BoardingStatus.pending) ...[
              if (student.guardianNotice != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.noticeBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    student.guardianNotice!,
                    style: AppText.caption.copyWith(color: AppColors.noticeText, fontSize: 15),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'No vino',
                      variant: AppButtonVariant.neutral,
                      height: 54,
                      fontSize: 17,
                      onPressed: onAbsent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: doneLabel,
                      height: 54,
                      fontSize: 18,
                      onPressed: onBoarded,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onUndo,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    'Deshacer',
                    style: TextStyle(
                      fontFamily: AppText.body,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.link,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.link,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
