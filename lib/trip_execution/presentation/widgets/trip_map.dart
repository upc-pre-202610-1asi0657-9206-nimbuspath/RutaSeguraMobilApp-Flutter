import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../domain/model/trip_live.dart';

/// Mapa del recorrido (OpenStreetMap): paradas numeradas, siguiente parada
/// resaltada y el vehículo en su última posición conocida.
class TripMap extends StatefulWidget {
  const TripMap({super.key, required this.live});

  final TripLive live;

  @override
  State<TripMap> createState() => _TripMapState();
}

class _TripMapState extends State<TripMap> {
  final _controller = MapController();
  String? _fittedFor;
  bool _ready = false;

  TripLive get _live => widget.live;

  List<LatLng> get _points => [
        for (final s in _live.stops) LatLng(s.latitude, s.longitude),
        if (_live.position case final p?) LatLng(p.latitude, p.longitude),
      ];

  /// Encuadra el recorrido una vez por viaje y otra cuando aparece el
  /// vehículo (sin pelear con el gesto del conductor en cada refresco).
  void _fit() {
    final pts = _points;
    final key = '${_live.tripId}/${_live.position != null}';
    if (!_ready || pts.isEmpty || _fittedFor == key) return;
    _fittedFor = key;
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: pts,
        // El panel inferior tapa parte del mapa.
        padding: const EdgeInsets.fromLTRB(50, 110, 50, 330),
        maxZoom: 17,
      ),
    );
  }

  @override
  void didUpdateWidget(TripMap old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = _live.nextStop?.stopId;
    final first = _live.stops.isEmpty
        ? null
        : LatLng(_live.stops.first.latitude, _live.stops.first.longitude);

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        // Lima por defecto hasta que lleguen las paradas.
        initialCenter: first ?? const LatLng(-12.0464, -77.0428),
        initialZoom: 14,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _ready = true;
          _fit();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.rutasegura',
        ),
        // Unión recta entre paradas (aproximada: no sigue las calles).
        if (_live.stops.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [
                  for (final s in _live.stops) LatLng(s.latitude, s.longitude),
                ],
                color: AppColors.navy,
                strokeWidth: 4,
                pattern: StrokePattern.dashed(segments: const [14, 10]),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final s in _live.stops)
              Marker(
                point: LatLng(s.latitude, s.longitude),
                width: 38,
                height: 38,
                child: _StopPin(
                  number: s.sequence,
                  isNext: s.stopId == next,
                  reached: s.reachedAt != null,
                ),
              ),
            if (_live.position case final p?)
              Marker(
                point: LatLng(p.latitude, p.longitude),
                width: 44,
                height: 44,
                child: const _VehiclePin(),
              ),
          ],
        ),
        const SimpleAttributionWidget(
          source: Text('© OpenStreetMap'),
          alignment: Alignment.topRight,
        ),
      ],
    );
  }
}

class _StopPin extends StatelessWidget {
  const _StopPin({required this.number, required this.isNext, required this.reached});

  final int number;
  final bool isNext;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final bg = isNext ? AppColors.yellow : (reached ? AppColors.disabledBg : AppColors.navy);
    final fg = isNext ? AppColors.navy : (reached ? AppColors.textSecondary : Colors.white);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6)],
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }
}

class _VehiclePin extends StatelessWidget {
  const _VehiclePin();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.link,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6)],
        ),
        child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 22),
      );
}

/// Permite sustituir el mapa en las pruebas (los tiles necesitan red).
final tripMapBuilderProvider = Provider<Widget Function(TripLive)>(
  (ref) => (live) => TripMap(live: live),
);
