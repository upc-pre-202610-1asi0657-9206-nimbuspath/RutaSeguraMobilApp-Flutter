import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tipografía: Archivo para texto y Archivo Expanded para titulares.
abstract final class AppText {
  static const String body = 'Archivo';
  static const String display = 'ArchivoExpanded';

  /// Titulares anchos (ej. "Buenos días, Jorge", "6:40", "SOS").
  static TextStyle displayStyle(
    double size, {
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w800,
    double height = 1.1,
  }) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: -0.2,
      );

  static const title = TextStyle(
    fontFamily: body,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const section = TextStyle(
    fontFamily: body,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const itemTitle = TextStyle(
    fontFamily: body,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const bodyText = TextStyle(
    fontFamily: body,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  static const caption = TextStyle(
    fontFamily: body,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.3,
  );

  static const button = TextStyle(
    fontFamily: body,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.navy,
  );
}
