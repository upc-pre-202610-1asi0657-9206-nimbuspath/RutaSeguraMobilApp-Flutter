import 'package:flutter/material.dart';

/// Paleta de RutaSegura Conductor (tomada del prototipo).
abstract final class AppColors {
  // Marca
  static const navy = Color(0xFF15243B);
  static const navyLight = Color(0xFF1E3150);
  static const navyBorder = Color(0xFF34496B);
  static const yellow = Color(0xFFF2B705);

  // Superficies
  static const background = Color(0xFFF3F3EF);
  static const surface = Colors.white;
  static const border = Color(0xFFDFDFD8);
  static const divider = Color(0xFFE9E9E4);
  static const avatarGrey = Color(0xFFE6E8EE);
  static const disabledBg = Color(0xFFE6E8E2);

  // Texto
  static const textPrimary = navy;
  static const textSecondary = Color(0xFF5B6472);
  static const textOnDark = Colors.white;
  static const textOnDarkMuted = Color(0xFFB9C3D3);

  // Estados
  static const success = Color(0xFF1E7A46);
  static const successBg = Color(0xFFE2F1E7);
  static const warning = Color(0xFFB8560F);
  static const noticeBg = Color(0xFFFBF1D4);
  static const noticeText = Color(0xFF7A5200);
  static const danger = Color(0xFFB3261E);
  static const link = Color(0xFF1F5FA8);

  // Emergencia
  static const emergencyBg = Color(0xFF5E130E);
  static const emergencyButton = Color(0xFFE03C2E);

  // Mapa
  static const mapGround = Color(0xFFE8E9E4);
  static const mapStreet = Colors.white;
  static const mapPark = Color(0xFFD6DECC);
  static const mapRoute = Color(0xFF1F5FAD);
}
