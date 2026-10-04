import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Círculo con iniciales (JM, VQ, MR...).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.initials,
    this.size = 48,
    this.dark = false,
  });

  final String initials;
  final double size;

  /// true: fondo navy con letras amarillas (conductor).
  /// false: fondo gris con letras navy (alumnos).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? AppColors.navy : AppColors.avatarGrey,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: dark ? AppText.display : AppText.body,
          fontWeight: FontWeight.w700,
          fontSize: size * (dark ? 0.32 : 0.36),
          color: dark ? AppColors.yellow : AppColors.navy,
        ),
      ),
    );
  }
}

/// Píldora de estado ("Vigente", "Subió 6:58").
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.background = AppColors.successBg,
    this.foreground = AppColors.success,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppText.body,
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: foreground,
        ),
      ),
    );
  }
}

/// Fila con ícono a la izquierda, título y subtítulo.
class IconInfoRow extends StatelessWidget {
  const IconInfoRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.itemTitle),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppText.caption),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Título de sección ("Antes de salir", "Mis rutas").
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(text, style: AppText.section),
    );
  }
}

/// Botón cuadrado de "volver" con chevron.
class BackChevron extends StatelessWidget {
  const BackChevron({super.key, this.color = AppColors.navy, this.label});

  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chevron_left_rounded, color: color, size: 30),
            if (label != null)
              Text(
                label!,
                style: TextStyle(
                  fontFamily: AppText.body,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Botón con borde discontinuo ("Añadir foto", "Nota de voz").
class DashedButton extends StatelessWidget {
  const DashedButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 58,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: AppColors.navy),
                const SizedBox(width: 10),
                Text(label, style: AppText.itemTitle.copyWith(fontSize: 17)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = const Color(0xFF9AA1AB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 5), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
