import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/common.dart';

enum _SosState { idle, countdown, sent }

/// Pantalla de emergencia. Al tocar SOS hay 5 s para cancelar
/// antes de enviar la alerta.
class SosPage extends StatefulWidget {
  const SosPage({super.key, required this.onBoardCount});

  final int onBoardCount;

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> with SingleTickerProviderStateMixin {
  static const _countdownSeconds = 5;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  _SosState _state = _SosState.idle;
  int _remaining = _countdownSeconds;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _start() {
    HapticFeedback.heavyImpact();
    setState(() {
      _state = _SosState.countdown;
      _remaining = _countdownSeconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        HapticFeedback.heavyImpact();
        setState(() => _state = _SosState.sent);
      } else {
        HapticFeedback.selectionClick();
        setState(() => _remaining--);
      }
    });
  }

  void _cancel() {
    _timer?.cancel();
    setState(() => _state = _SosState.idle);
  }

  @override
  Widget build(BuildContext context) {
    final sent = _state == _SosState.sent;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.emergencyBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _state == _SosState.countdown
                      ? const SizedBox(height: 46)
                      : const BackChevron(color: Colors.white, label: 'Volver al viaje'),
                ),
                const SizedBox(height: 24),
                Text(
                  sent ? 'Alerta enviada' : 'Emergencia',
                  style: AppText.displayStyle(32, color: Colors.white),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    sent
                        ? 'Tu empresa y las familias de los ${widget.onBoardCount} alumnos a bordo ya fueron avisados. Siguen viendo tu ubicación en vivo.'
                        : 'Avisa de inmediato a tu empresa y a las familias de los ${widget.onBoardCount} alumnos a bordo, con tu ubicación en vivo.',
                    textAlign: TextAlign.center,
                    style: AppText.bodyText.copyWith(color: const Color(0xFFF3D6D3), fontSize: 17),
                  ),
                ),
                const Spacer(),
                _SosButton(
                  pulse: _pulse,
                  state: _state,
                  remaining: _remaining,
                  onTap: _state == _SosState.idle ? _start : null,
                ),
                const Spacer(),
                if (_state == _SosState.countdown)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: AppButton(
                      label: 'Cancelar',
                      variant: AppButtonVariant.neutral,
                      onPressed: _cancel,
                    ),
                  )
                else if (sent)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: AppButton(
                      label: 'Volver al viaje',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  )
                else
                  Text(
                    'Tendrás $_countdownSeconds segundos para cancelar.',
                    style: AppText.caption.copyWith(color: const Color(0xFFF3D6D3), fontSize: 15),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({
    required this.pulse,
    required this.state,
    required this.remaining,
    required this.onTap,
  });

  final Animation<double> pulse;
  final _SosState state;
  final int remaining;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const size = 250.0;

    String label;
    switch (state) {
      case _SosState.idle:
        label = 'SOS';
      case _SosState.countdown:
        label = '$remaining';
      case _SosState.sent:
        label = '';
    }

    return SizedBox(
      width: size + 50,
      height: size + 50,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, child) {
          final v = state == _SosState.sent ? 0.0 : pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Anillos exteriores
              Container(
                width: size + 40 + 10 * v,
                height: size + 40 + 10 * v,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              Container(
                width: size + 20,
                height: size + 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
              child!,
            ],
          );
        },
        child: Material(
          color: state == _SosState.sent ? const Color(0xFF2E7D4F) : AppColors.emergencyButton,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: state == _SosState.sent
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 110)
                    : Text(label, style: AppText.displayStyle(state == _SosState.idle ? 52 : 90, color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
