import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Tarjeta blanca con borde suave, usada en casi todas las pantallas.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = AppColors.surface,
    this.radius = 18,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: AppColors.border, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Tarjeta con filas separadas por divisores (ej. "Antes de salir").
class AppCardList extends StatelessWidget {
  const AppCardList({
    super.key,
    required this.children,
    this.rowPadding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry rowPadding;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(height: 1, thickness: 1, color: AppColors.divider));
      }
      rows.add(Padding(padding: rowPadding, child: children[i]));
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: rows),
    );
  }
}
