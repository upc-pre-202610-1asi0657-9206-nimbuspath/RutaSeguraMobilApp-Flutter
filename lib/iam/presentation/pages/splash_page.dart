import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/rs_logo.dart';

/// Se muestra mientras se valida la sesión guardada.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(child: RsLogo(size: 72)),
      );
}
