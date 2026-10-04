import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Logo de RutaSegura: cuadrado amarillo con una ruta curva.
class RsLogo extends StatelessWidget {
  const RsLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.yellow,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: CustomPaint(painter: _RoutePainter()),
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = AppColors.navy
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.075;

    final path = Path()
      ..moveTo(w * 0.33, h * 0.80)
      ..cubicTo(w * 0.42, h * 0.62, w * 0.62, h * 0.52, w * 0.48, h * 0.38)
      ..cubicTo(w * 0.40, h * 0.30, w * 0.52, h * 0.16, w * 0.66, h * 0.20);
    canvas.drawPath(path, paint);

    canvas.drawCircle(
      Offset(w * 0.68, h * 0.20),
      w * 0.075,
      Paint()..color = AppColors.navy,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
