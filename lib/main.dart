import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'iam/presentation/pages/login_page.dart';
import 'shell/main_shell.dart';

/// FASE VISUAL: la app arranca directo en "Inicio".
/// Cambia a `true` para arrancar en el login (se usará cuando se conecte
/// la autenticación real).
const bool kStartOnLogin = false;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const RutaSeguraDriverApp());
}

class RutaSeguraDriverApp extends StatelessWidget {
  const RutaSeguraDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RutaSegura Conductor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: kStartOnLogin ? const LoginPage() : const MainShell(),
    );
  }
}
