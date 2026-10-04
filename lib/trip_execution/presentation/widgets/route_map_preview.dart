import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// Mapa ilustrativo del recorrido (fase visual).
///
/// Reproduce el prototipo: tramo recorrido en navy, tramo pendiente en azul,
/// siguiente parada en amarillo, bus y colegio. En la fase de tracking se
/// reemplaza por un mapa real (flutter_map / google_maps_flutter) con la
/// misma simbología.
class RouteMapPreview extends StatefulWidget {
  const RouteMapPreview({super.key, this.nextStopLabel = 'Parada 4'});

  final String nextStopLabel;

  @override
  State<RouteMapPreview> createState() => _RouteMapPreviewState();
}

class _RouteMapPreviewState extends State<RouteMapPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => CustomPaint(
        size: Size.infinite,
        painter: _MapPainter(
          pulse: _pulse.value,
          nextStopLabel: widget.nextStopLabel,
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.pulse, required this.nextStopLabel});

  final double pulse;
  final String nextStopLabel;

  // Espacio de diseño del prototipo.
  static const double dw = 447;
  static const double dh = 550;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.mapGround);

    // Escala tipo "cover", alineada arriba.
    final s = (size.width / dw) > (size.height / dh)
        ? size.width / dw
        : size.height / dh;
    final dx = (size.width - dw * s) / 2;
    canvas.save();
    canvas.translate(dx, 0);
    canvas.scale(s);

    _drawCity(canvas);
    _drawRoute(canvas);

    canvas.restore();
  }

  void _drawCity(Canvas canvas) {
    final park = Paint()..color = AppColors.mapPark;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(270, 343, 390, 470),
        const Radius.circular(4),
      ),
      park,
    );

    final street = Paint()
      ..color = AppColors.mapStreet
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.butt;

    // Calles horizontales
    canvas.drawLine(const Offset(-20, 80), const Offset(dw + 20, 80), street);
    canvas.drawLine(const Offset(-20, 150), const Offset(dw + 20, 150), street);
    canvas.drawLine(const Offset(-20, 377), const Offset(260, 377), street);
    // Calles verticales
    canvas.drawLine(const Offset(68, -20), const Offset(68, dh + 20), street);
    canvas.drawLine(const Offset(195, -20), const Offset(195, dh + 20), street);
    canvas.drawLine(const Offset(343, -20), const Offset(343, 330), street);
    canvas.drawLine(const Offset(410, 150), const Offset(410, 330), street);
    // Avenida diagonal
    canvas.drawLine(
      const Offset(-20, 505),
      const Offset(dw + 20, 262),
      Paint()
        ..color = AppColors.mapStreet
        ..strokeWidth = 26,
    );
  }

  void _drawRoute(Canvas canvas) {
    Paint line(Color c) => Paint()
      ..color = c
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Tramo recorrido
    final done = Path()
      ..moveTo(68, 490)
      ..lineTo(68, 377)
      ..lineTo(195, 377)
      ..lineTo(195, 215);
    canvas.drawPath(done, line(AppColors.navy));

    // Tramo pendiente
    final pending = Path()
      ..moveTo(195, 215)
      ..lineTo(195, 80)
      ..lineTo(343, 80)
      ..lineTo(343, 217)
      ..lineTo(410, 217)
      ..lineTo(410, 377)
      ..lineTo(376, 377);
    canvas.drawPath(pending, line(AppColors.mapRoute));

    // Paradas ya hechas
    for (final p in const [Offset(68, 377), Offset(195, 377), Offset(68, 490)]) {
      canvas.drawCircle(p, 7, Paint()..color = AppColors.navy);
    }

    // Paradas pendientes
    for (final p in const [Offset(343, 80), Offset(343, 217), Offset(410, 297)]) {
      canvas.drawCircle(p, 9, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        9,
        Paint()
          ..color = AppColors.mapRoute
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
    }

    // Siguiente parada
    const next = Offset(195, 80);
    canvas.drawCircle(next, 13, Paint()..color = Colors.white);
    canvas.drawCircle(
      next,
      13,
      Paint()
        ..color = AppColors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    _text(canvas, nextStopLabel, const Offset(225, 58), 14, FontWeight.w700);

    // Colegio
    const school = Offset(376, 377);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: school, width: 32, height: 32),
        const Radius.circular(7),
      ),
      Paint()..color = AppColors.navy,
    );
    _icon(canvas, Icons.home_outlined, school, 22, AppColors.yellow);
    _text(canvas, 'Colegio', const Offset(333, 404), 13, FontWeight.w500);

    // Bus con pulso
    const bus = Offset(195, 215);
    canvas.drawCircle(
      bus,
      19 + 16 * pulse,
      Paint()..color = AppColors.yellow.withValues(alpha: 0.35 * (1 - pulse)),
    );
    canvas.drawCircle(bus, 19, Paint()..color = AppColors.yellow);
    canvas.drawCircle(
      bus,
      19,
      Paint()
        ..color = AppColors.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    _icon(canvas, Icons.navigation_rounded, bus, 22, AppColors.navy);
  }

  void _text(Canvas canvas, String text, Offset at, double size, FontWeight w) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppText.body,
          fontSize: size,
          fontWeight: w,
          color: AppColors.navy,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  void _icon(Canvas canvas, IconData icon, Offset center, double size, Color c) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: c,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.pulse != pulse || old.nextStopLabel != nextStopLabel;
}
