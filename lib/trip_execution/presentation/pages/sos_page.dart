import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/common.dart';
import '../../application/trip_controller.dart';
import '../../domain/model/trip_models.dart';

enum _SosState { idle, countdown, sending, sent }

/// Pantalla de emergencia. Al tocar SOS hay 5 s para cancelar; al terminar
/// la cuenta se envía la alerta (sin red, se reintenta cada pocos segundos
/// con el mismo `clientEventId`).
class SosPage extends ConsumerStatefulWidget {
  const SosPage({super.key, required this.trip});

  final ScheduledTrip trip;

  @override
  ConsumerState<SosPage> createState() => _SosPageState();
}

class _SosPageState extends ConsumerState<SosPage>
    with SingleTickerProviderStateMixin {
  static const _countdownSeconds = 5;
  static const _retryEvery = Duration(seconds: 3);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  _SosState _state = _SosState.idle;
  int _remaining = _countdownSeconds;
  Timer? _timer;
  bool _retrying = false;

  /// Sin señal: la alerta quedó guardada y `/sync` la manda al reconectar.
  bool _queued = false;
  String? _failure;

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
        _send();
      } else {
        HapticFeedback.selectionClick();
        setState(() => _remaining--);
      }
    });
  }

  /// El `clientEventId` se genera al terminar la cuenta y se reutiliza en
  /// cada reintento.
  Future<void> _send() async {
    final eventId = const Uuid().v4();
    final at = DateTime.now();
    setState(() {
      _state = _SosState.sending;
      _retrying = false;
      _queued = false;
      _failure = null;
    });
    final controller = ref.read(tripControllerProvider(widget.trip).notifier);
    while (mounted) {
      final error = await controller.sendSos(eventId, at);
      if (!mounted) return;
      if (error == null) {
        setState(() => _state = _SosState.sent);
        return;
      }
      if (!error.isRetryable) {
        // Regla de negocio (p. ej. el viaje ya no está en curso): reintentar
        // igual no sirve. Se ofrece reintentar a mano.
        setState(() {
          _state = _SosState.idle;
          _failure = error.userMessage;
        });
        return;
      }
      setState(() => _retrying = true);
      if (!_queued) {
        // Además de reintentar aquí, se guarda: así sale aunque el conductor
        // cierre esta pantalla o la app.
        _queued = true;
        await controller.queueSos(eventId, at);
        if (!mounted) return;
        setState(() {});
      }
      await Future<void>.delayed(_retryEvery);
    }
  }

  void _cancel() {
    _timer?.cancel();
    setState(() => _state = _SosState.idle);
  }

  @override
  Widget build(BuildContext context) {
    final sent = _state == _SosState.sent;
    final sending = _state == _SosState.sending;
    final onBoard =
        ref.watch(tripControllerProvider(widget.trip)).value?.studentsOnBoard ??
        0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        // No se puede salir mientras la alerta se está enviando.
        canPop: (!sending || _queued) && _state != _SosState.countdown,
        child: Scaffold(
          backgroundColor: AppColors.emergencyBg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child:
                        _state == _SosState.countdown || (sending && !_queued)
                        ? const SizedBox(height: 46)
                        : const BackChevron(
                            color: Colors.white,
                            label: 'Volver al viaje',
                          ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    sent
                        ? 'Alerta enviada'
                        : (sending
                            ? (_queued ? 'Alerta guardada' : 'Enviando alerta')
                            : 'Emergencia'),
                    style: AppText.displayStyle(32, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      sent
                          ? 'SOS activo: tu empresa fue avisada. Siguen viendo tu ubicación en vivo.'
                          : sending
                          ? (_retrying
                                ? 'Sin conexión. La alerta quedó guardada y se enviará apenas haya señal. Seguimos reintentando.'
                                : 'Avisando a tu empresa…')
                          : 'Avisa de inmediato a tu empresa y a ${onBoard == 1 ? 'la familia del alumno a bordo' : 'las familias de los $onBoard alumnos a bordo'}, con tu ubicación en vivo.',
                      textAlign: TextAlign.center,
                      style: AppText.bodyText.copyWith(
                        color: const Color(0xFFF3D6D3),
                        fontSize: 17,
                      ),
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
                  else if (sent || (sending && _queued))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: AppButton(
                        label: 'Volver al viaje',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    )
                  else if (!sending)
                    Text(
                      _failure ??
                          'Tendrás $_countdownSeconds segundos para cancelar.',
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(
                        color: const Color(0xFFF3D6D3),
                        fontSize: 15,
                      ),
                    ),
                ],
              ),
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
      case _SosState.sending:
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
          color: state == _SosState.sent
              ? const Color(0xFF2E7D4F)
              : AppColors.emergencyButton,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: state == _SosState.sent
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 110,
                      )
                    : state == _SosState.sending
                    ? const SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 6,
                        ),
                      )
                    : Text(
                        label,
                        style: AppText.displayStyle(
                          state == _SosState.idle ? 52 : 90,
                          color: Colors.white,
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
