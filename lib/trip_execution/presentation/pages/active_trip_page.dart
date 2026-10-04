import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_button.dart';
import '../../domain/model/trip_models.dart';
import '../../infrastructure/mock_trip_repository.dart';
import '../widgets/route_map_preview.dart';
import 'boarding_page.dart';
import 'report_incident_page.dart';
import 'sos_page.dart';
import 'trip_summary_page.dart';

/// Pantalla de viaje en curso: mapa, siguiente parada y acciones.
class ActiveTripPage extends StatefulWidget {
  const ActiveTripPage({super.key, required this.trip});

  final ScheduledTrip trip;

  @override
  State<ActiveTripPage> createState() => _ActiveTripPageState();
}

class _ActiveTripPageState extends State<ActiveTripPage> {
  static const _stops = MockTripRepository.remainingStops;

  // ETA simulado por parada (lo calculará el servicio de tracking).
  static const _eta = [(3, '850 m'), (6, '1,4 km'), (4, '900 m')];

  final DateTime _startedAt = DateTime.now();
  final List<Incident> _incidents = [];
  final List<Student> _absent = [];

  int _stopIndex = 0; // índice dentro de _stops
  int _onBoard = MockTripRepository.onBoardBeforeCurrentStop;
  int _secondsSinceGps = 3;
  Timer? _ticker;

  int get _stopNumber =>
      _allStopsDone ? widget.trip.stopsCount : _stops[_stopIndex].order;
  bool get _allStopsDone => _stopIndex >= _stops.length;

  @override
  void initState() {
    super.initState();
    // Simula el envío periódico de la ubicación (cada 5 s).
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _secondsSinceGps = (_secondsSinceGps + 1) % 6);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _openBoarding() async {
    final records = await Navigator.of(context).push<List<BoardingRecord>>(
      MaterialPageRoute(
        builder: (_) => BoardingPage(
          stop: _stops[_stopIndex],
          totalStops: widget.trip.stopsCount,
          stopNumber: _stopNumber,
        ),
      ),
    );
    if (records == null || !mounted) return;
    setState(() {
      _onBoard += records.where((r) => r.status == BoardingStatus.boarded).length;
      _absent.addAll(
        records.where((r) => r.status == BoardingStatus.absent).map((r) => r.student),
      );
      _stopIndex++;
    });
  }

  Future<void> _openIncident() async {
    final incident = await Navigator.of(context).push<Incident>(
      MaterialPageRoute(builder: (_) => const ReportIncidentPage()),
    );
    if (incident == null || !mounted) return;
    setState(() => _incidents.add(incident));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Incidente enviado: ${incident.type.label}')),
    );
  }

  void _openSos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SosPage(onBoardCount: _onBoard),
      ),
    );
  }

  Future<void> _finishTrip() async {
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

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TripSummaryPage(
          summary: TripSummary(
            trip: widget.trip,
            startedAt: _startedAt,
            endedAt: DateTime.now(),
            arrivedCount: _onBoard,
            absentStudents: _absent,
            incidents: _incidents,
            nextTrip: MockTripRepository.afternoonTrip,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(_startedAt).inMinutes;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _finishTrip();
        },
        child: Scaffold(
          backgroundColor: AppColors.mapGround,
          body: Column(
            children: [
              _Header(
                title: widget.trip.title,
                subtitle: 'En curso desde ${DateFmt.time(_startedAt)}, $elapsed min',
                onFinish: _finishTrip,
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RouteMapPreview(
                        nextStopLabel: _allStopsDone ? 'Colegio' : 'Parada $_stopNumber',
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      top: 16,
                      child: _SharingPill(seconds: _secondsSinceGps),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _BottomPanel(
                        stopNumber: _stopNumber,
                        totalStops: widget.trip.stopsCount,
                        stop: _allStopsDone ? null : _stops[_stopIndex],
                        eta: _allStopsDone ? null : _eta[_stopIndex],
                        destination: widget.trip.destination,
                        onBoard: _onBoard,
                        totalStudents: widget.trip.studentsCount,
                        onRegister: _allStopsDone ? null : _openBoarding,
                        onIncident: _openIncident,
                        onSos: _openSos,
                        onFinish: _finishTrip,
                      ),
                    ),
                  ],
                ),
              ),
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

class _SharingPill extends StatelessWidget {
  const _SharingPill({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
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
          const Icon(Icons.location_on_outlined, color: AppColors.success, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Compartiendo ubicación',
              style: TextStyle(
                fontFamily: AppText.body,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
          ),
          Text(
            seconds == 0 ? 'ahora' : 'hace $seconds s',
            style: AppText.caption.copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.stopNumber,
    required this.totalStops,
    required this.stop,
    required this.eta,
    required this.destination,
    required this.onBoard,
    required this.totalStudents,
    required this.onRegister,
    required this.onIncident,
    required this.onSos,
    required this.onFinish,
  });

  final int stopNumber;
  final int totalStops;
  final Stop? stop;
  final (int, String)? eta;
  final String destination;
  final int onBoard;
  final int totalStudents;
  final VoidCallback? onRegister;
  final VoidCallback onIncident;
  final VoidCallback onSos;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final s = stop;
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
                          s == null ? 'Último tramo' : 'Siguiente parada, $stopNumber de $totalStops',
                          style: AppText.caption.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s?.address ?? destination,
                          style: AppText.displayStyle(22, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s == null ? 'Todos los alumnos van a bordo' : 'Suben ${s.students.length} alumnos',
                          style: AppText.bodyText.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  if (s != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '${eta?.$1 ?? '-'}', style: AppText.displayStyle(34, height: 1)),
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
                        Text(eta?.$2 ?? '', style: AppText.caption.copyWith(fontSize: 15)),
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
              if (s != null)
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
