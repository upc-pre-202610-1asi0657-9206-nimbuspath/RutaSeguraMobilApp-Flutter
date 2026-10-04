import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/rs_logo.dart';
import '../../../shell/main_shell.dart';

/// Inicio de sesión del conductor.
/// FASE VISUAL: "Ingresar" solo navega; la autenticación real
/// (JWT contra Identity & Access Service) se conecta en el siguiente paso.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 56),
                      const RsLogo(size: 72),
                      const SizedBox(height: 28),
                      Text('RutaSegura', style: AppText.displayStyle(38, color: Colors.white)),
                      const SizedBox(height: 12),
                      Text(
                        'Para conductores. Inicia tus viajes y registra a cada alumno que sube y baja.',
                        style: AppText.bodyText.copyWith(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 17,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 32),
                      const _Label('DNI o correo'),
                      _DarkField(
                        controller: _user,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),
                      const _Label('Contraseña'),
                      _DarkField(
                        controller: _password,
                        obscure: _obscure,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        suffix: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: AppColors.textOnDarkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppButton(label: 'Ingresar', onPressed: _submit, height: 68, fontSize: 20),
                      const SizedBox(height: 22),
                      Text(
                        '¿Olvidaste tu contraseña? Pide a tu empresa de transporte que la restablezca.',
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted, fontSize: 15),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: AppText.body,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      );
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: 1.5),
        );

    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      cursorColor: AppColors.yellow,
      style: const TextStyle(fontFamily: AppText.body, fontSize: 19, color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.navyLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        enabledBorder: border(AppColors.navyBorder),
        focusedBorder: border(AppColors.yellow),
        suffixIcon: suffix,
      ),
    );
  }
}
