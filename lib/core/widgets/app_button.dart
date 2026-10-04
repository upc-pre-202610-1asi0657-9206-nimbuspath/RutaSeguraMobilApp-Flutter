import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant {
  primary,
  outline,
  neutral,
  outlineOnDark,
  danger,
  dangerText,
}

/// Botón grande del prototipo (alto 60, esquinas de 16).
/// Si [onPressed] es null se muestra en estado deshabilitado (gris).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.height = 60,
    this.fontSize = 18,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    late Color bg;
    late Color fg;
    BorderSide side = BorderSide.none;

    switch (variant) {
      case AppButtonVariant.primary:
        bg = AppColors.yellow;
        fg = AppColors.navy;
      case AppButtonVariant.outline:
        bg = AppColors.surface;
        fg = AppColors.navy;
        side = const BorderSide(color: AppColors.navy, width: 2);
      case AppButtonVariant.neutral:
        bg = AppColors.surface;
        fg = AppColors.navy;
        side = const BorderSide(color: AppColors.border, width: 2);
      case AppButtonVariant.outlineOnDark:
        bg = Colors.transparent;
        fg = Colors.white;
        side = const BorderSide(color: Color(0xFF5A6B85), width: 1.5);
      case AppButtonVariant.danger:
        bg = AppColors.danger;
        fg = Colors.white;
      case AppButtonVariant.dangerText:
        bg = AppColors.surface;
        fg = AppColors.danger;
        side = const BorderSide(color: AppColors.border, width: 2);
    }

    if (!enabled) {
      bg = AppColors.disabledBg;
      fg = AppColors.textSecondary;
      side = BorderSide.none;
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: side,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: fg, size: fontSize + 4),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.button.copyWith(
                      color: fg,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
