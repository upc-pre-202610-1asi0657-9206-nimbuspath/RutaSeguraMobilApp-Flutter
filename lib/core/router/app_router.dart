import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../iam/application/session_controller.dart';
import '../../iam/presentation/pages/login_page.dart';
import '../../iam/presentation/pages/splash_page.dart';
import '../../shell/main_shell.dart';

/// Rutas de primer nivel.
///
/// El flujo del viaje (viaje en curso, abordaje, incidente, SOS, resumen)
/// todavía navega con `Navigator.push` desde sus pantallas; se pasará a rutas
/// con nombre cuando se conecte a Trip & Tracking (etapa 4).
abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Cada cambio de sesión vuelve a evaluar el `redirect`.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionControllerProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final atLogin = state.matchedLocation == AppRoutes.login;
      return switch (session) {
        SessionRestoring() => AppRoutes.splash == state.matchedLocation
            ? null
            : AppRoutes.splash,
        SessionSignedOut() => atLogin ? null : AppRoutes.login,
        SessionActive() => atLogin || state.matchedLocation == AppRoutes.splash
            ? AppRoutes.home
            : null,
      };
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const MainShell(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
