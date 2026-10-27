import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_button.dart';
import '../../../stakeholder/application/students_repository.dart';
import '../../../stakeholder/domain/model/route_student.dart';
import '../../application/agenda_provider.dart';
import '../../application/tracking_controller.dart';
import '../../application/tracking_engine.dart';
import '../../application/trip_controller.dart';
import '../../domain/model/trip_live.dart';
import '../../domain/model/trip_models.dart';
import '../widgets/trip_map.dart';
import 'boarding_page.dart';
import 'report_incident_page.dart';
import 'sos_page.dart';
import 'trip_summary_page.dart';

/// Pantalla de viaje en curso: mapa, siguiente parada y acciones.
///
/// Si el viaje aún no empezó, lo inicia al abrirse (`POST /trips/{id}/start`);
/// si ya estaba en curso, solo lo retoma.
class ActiveTripPage extends ConsumerStatefulWidget {
  const ActiveTripPage({super.key, required this.trip});

  final ScheduledTrip trip;

  @override
  ConsumerState<ActiveTripPage> createState() => _ActiveTripPageState();
}

class _ActiveTripPageState extends ConsumerState<ActiveTripPage>
    with WidgetsBindingObserver {
  final List<Incident> _incidents = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a primer plano se refresca el estado en vivo.
    if (state == AppLifecycleState.resumed) {
      ref.read(tripControllerProvider(widget.trip).notifier).refresh();
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openBoarding() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BoardingPage(trip: widget.trip)),
    );
  }

  Future<void> _openIncident() async {
    final incident = await Navigator.of(context).push<Incident>(
      MaterialPageRoute(builder: (_) => const ReportIncidentPage()),
    );
    if (incident == null || !mounted) return;
    setState(() => _incidents.add(incident));
    _toast('Incidente enviado: ${incident.type.label}');
  }

  void _openSos(TripLive live) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SosPage(onBoardCount: live.studentsOnBoard),
      ),
    );
  }

  /// Reglas locales de §10 antes de finalizar. `null` si se puede.
  String? _cannotFinish(TripLive live) {
    if (live.pendingCount > 0) {
      final n = live.pendingCount;
      return 'Faltan registrar $n ${n == 1 ? 'alumno' : 'alumnos'}.';
    }
    if (live.hasActiveSos) {
      return 'Hay un SOS activo: tu empresa debe resolverlo antes de finalizar.';
    }
    if (!live.isPickup && live.studentsOnBoard > 0) {
      return 'Aún hay alumnos a bordo.';
    }
    return null;
  }

  Future<void> _finishTrip(TripLive live) async {
    final blocked = _cannotFinish(live);
    if (blocked != null) {
      _toast(blocked);
      return;
    }
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Finalizar el viaje?', style: AppText.displayStyle(22)),
              const SizedBox(height: 8),
              Text(
                'Dejarás de compartir tu ubicación y se enviará el resumen a tu empresa.',
                style: AppText.caption.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 22),
              AppButton(label: 'Sí, finalizar', onPressed: () => Navigator.pop(ctx, true)),
              const SizedBox(height: 10),
              AppButton(
                label: 'Seguir en viaje',
                variant: AppButtonVariant.outline,
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true || !mounted) return;

    // Etapa 6: aquí se llamará a /complete y se leerá /summary.
    final students = {
      for (final s in ref.read(studentsProvider).value ?? const <RouteStudent>[])
        s.studentId: s,
    };
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TripSummaryPage(
          summary: TripSummary(
            trip: widget.trip,
            startedAt: live.startedAt?.toLocal() ?? DateTime.now(),
            endedAt: DateTime.now(),
            arrivedCount: live.passengers
                .where((p) =>
                    p.status == PassengerStatus.boarded ||
                    p.status == PassengerStatus.alighted)
                .length,
            absentStudents: [
              for (final p in live.passengers)
                if (p.status == PassengerStatus.absent)
                  Student(
                    id: p.studentId,
                    fullName: students[p.studentId]?.fullName ?? 'Alumno sin ficha',
                    grade: students[p.studentId]?.schoolGrade ?? '',
                  ),
            ],
            incidents: _incidents,
            nextTrip: ref.read(agendaProvider).value?.later.firstOrNull,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tripControllerProvider(widget.trip));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: state.when(
        loading: () => _Status(
          title: widget.trip.title,
          child: const CircularProgressIndicator(color: AppColors.navy),
        ),
        error: (error, _) => state.hasValue
            ? _body(state.requireValue)
            : _Status(
                title: widget.trip.title,
                message: error is ApiError
                    ? error.userMessage
                    : 'No pudimos abrir el viaje.',
                onRetry: () => ref
                    .read(tripControllerProvider(widget.trip).notifier)
                    .retry(),
              ),
        data: _body,
      ),
    );
  }

  Widget _body(TripLive live) {
    final started = live.startedAt?.toLocal();
    final elapsed = started == null ? 0 : DateTime.now().difference(started).inMinutes;
    final next = live.nextStop;
    final map = ref.watch(tripMapBuilderProvider);
    // La ubicación se comparte solo mientras el viaje está en curso: al dejar
    // de observarse, el provider se libera y el GPS se detiene.
    final tracking = live.isActive
        ? ref.watch(trackingControllerProvider(live.tripId))
        : const TrackingState(status: TrackingStatus.stopped);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finishTrip(live);
      },
      child: Scaffold(
        backgroundColor: AppColors.mapGround,
        body: Column(
          children: [
            _Header(
              title: widget.trip.title,
              subtitle: started == null
                  ? 'En curso'
                  : 'En curso desde ${DateFmt.time(started)}, $elapsed min',
              onFinish: () => _finishTrip(live),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: map(live)),
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 16,
                    child: _SharingPill(tracking: tracking, serverAgeSeconds: live.position?.ageSeconds),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _BottomPanel(
                      nextStop: next,
                      boardingAtNext: live.boardingAtNextStop,
                      destination: widget.trip.destination,
                      onBoard: live.studentsOnBoard,
                      totalStudents: live.totalStudents,
                      isPickup: live.isPickup,
                      hasActiveSos: live.hasActiveSos,
                      pending: live.pendingCount,
                      onRegister: _openBoarding,
                      onIncident: _openIncident,
                      onSos: () => _openSos(live),
                      onFinish: () => _finishTrip(live),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cargando (iniciando el viaje) o error con "Reintentar".
class _Status extends StatelessWidget {
  const _Status({required this.title, this.message, this.onRetry, this.child});

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: AppText.displayStyle(24), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (child != null) ...[
                child!,
                const SizedBox(height: 16),
                Text('Iniciando el viaje…', style: AppText.caption.copyWith(fontSize: 15)),
              ],
              if (message != null) ...[
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: AppText.bodyText.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 22),
                if (onRetry != null)
                  AppButton(label: 'Reintentar', onPressed: onRetry),
                const SizedBox(height: 10),
                AppButton(
                  label: 'Volver',
                  variant: AppButtonVariant.outline,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle, required this.onFinish});

  final String title;
  final String subtitle;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: AppText.body,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
                  ],
                ),
              ),
              SizedBox(
                width: 146,
                child: AppButton(
                  label: 'Finalizar viaje',
                  variant: AppButtonVariant.outlineOnDark,
                  height: 50,
                  fontSize: 16,
                  onPressed: onFinish,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharingPill extends StatefulWidget {
  const _SharingPill({required this.tracking, this.serverAgeSeconds});

  final TrackingState tracking;

  /// `position.ageSeconds` de `/live`, mientras no haya un envío local.
  final int? serverAgeSeconds;

  @override
  State<_SharingPill> createState() => _SharingPillState();
}

class _SharingPillState extends State<_SharingPill> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Refresca el "hace N s" cada segundo.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  ({String title, String detail, Color color}) get _view {
    final t = widget.tracking;
    switch (t.status) {
      case TrackingStatus.noPermission:
        return (
          title: 'Ubicación sin permiso',
          detail: 'Actívalo en ajustes',
          color: AppColors.danger,
        );
      case TrackingStatus.serviceOff:
        return (
          title: 'GPS desactivado',
          detail: 'Actívalo en ajustes',
          color: AppColors.danger,
        );
      case TrackingStatus.stopped:
        return (title: 'Ubicación detenida', detail: '', color: AppColors.textSecondary);
      case TrackingStatus.starting:
      case TrackingStatus.active:
        break;
    }
    final sent = t.lastSentAt;
    final age = sent != null
        ? DateTime.now().difference(sent).inSeconds
        : widget.serverAgeSeconds;
    final stale = t.pending > 0 && (age == null || age > 30);
    final detail = stale
        ? 'sin señal, ${t.pending} guardadas'
        : switch (age) {
            null => 'esperando GPS',
            <= 1 => 'ahora',
            final s => 'hace $s s',
          };
    return (
      title: 'Compartiendo ubicación',
      detail: detail,
      color: stale ? AppColors.warning : AppColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, color: v.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              v.title,
              style: const TextStyle(
                fontFamily: AppText.body,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
          ),
          Text(v.detail, style: AppText.caption.copyWith(fontSize: 15)),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.nextStop,
    required this.boardingAtNext,
    required this.destination,
    required this.onBoard,
    required this.totalStudents,
    required this.isPickup,
    required this.hasActiveSos,
    required this.pending,
    required this.onRegister,
    required this.onIncident,
    required this.onSos,
    required this.onFinish,
  });

  final NextStop? nextStop;
  final int boardingAtNext;
  final String destination;
  final int onBoard;
  final int totalStudents;
  final bool isPickup;
  final bool hasActiveSos;
  final int pending;
  final VoidCallback? onRegister;
  final VoidCallback onIncident;
  final VoidCallback onSos;
  final VoidCallback onFinish;

  String _stopCaption() {
    if (boardingAtNext == 0) return 'Sin alumnos pendientes en esta parada';
    if (isPickup) {
      return boardingAtNext == 1 ? 'Sube 1 alumno' : 'Suben $boardingAtNext alumnos';
    }
    return boardingAtNext == 1 ? 'Baja 1 alumno' : 'Bajan $boardingAtNext alumnos';
  }

  @override
  Widget build(BuildContext context) {
    final s = nextStop;
    final progress = totalStudents == 0 ? 0.0 : onBoard / totalStudents;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s == null ? 'Último tramo' : 'Siguiente parada, ${s.sequence} de ${s.totalStops}',
                          style: AppText.caption.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s?.name ?? destination,
                          style: AppText.displayStyle(22, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s == null
                              ? (isPickup ? 'Todos los alumnos van a bordo' : 'Sin más paradas')
                              : _stopCaption(),
                          style: AppText.bodyText.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  if (s != null && s.etaMinutes != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '${s.etaMinutes}', style: AppText.displayStyle(34, height: 1)),
                              const TextSpan(
                                text: ' min',
                                style: TextStyle(
                                  fontFamily: AppText.body,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(s.distanceLabel ?? '', style: AppText.caption.copyWith(fontSize: 15)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text('A bordo', style: AppText.itemTitle.copyWith(fontSize: 15)),
                  const Spacer(),
                  Text('$onBoard de $totalStudents', style: AppText.bodyText),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: progress),
                  duration: const Duration(milliseconds: 500),
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 10,
                    color: AppColors.navy,
                    backgroundColor: AppColors.disabledBg,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (hasActiveSos) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.noticeBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'SOS activo · tu empresa fue avisada',
                    style: AppText.caption.copyWith(color: AppColors.noticeText, fontSize: 15),
                  ),
                ),
              ],
              if (s != null || pending > 0)
                AppButton(
                  label: 'Registrar abordaje',
                  icon: Icons.check_box_outlined,
                  height: 68,
                  fontSize: 20,
                  onPressed: onRegister,
                )
              else
                AppButton(
                  label: 'Llegué al colegio',
                  icon: Icons.flag_outlined,
                  height: 68,
                  fontSize: 20,
                  onPressed: onFinish,
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Incidente',
                      icon: Icons.warning_amber_rounded,
                      variant: AppButtonVariant.outline,
                      fontSize: 17,
                      onPressed: onIncident,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      label: 'SOS',
                      icon: Icons.error_outline_rounded,
                      variant: AppButtonVariant.danger,
                      fontSize: 18,
                      onPressed: onSos,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
