import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../domain/model/tracking.dart';
import '../domain/model/trip_live.dart';
import '../domain/model/trip_models.dart';

/// Última lectura GPS buena, que acompaña a las acciones del conductor.
typedef GeoPoint = ({double latitude, double longitude});

/// Acción del conductor sobre un alumno.
enum PassengerAction { board, alight, absent }

/// Trip & Tracking vía Gateway.
///
/// Toda acción lleva un `clientEventId` generado **al tocar**: reenviar la
/// misma petición es seguro (responde 200 con `applied: false`).
abstract interface class TripApi {
  /// Agenda de hoy (hora de Lima), sin cancelados, ordenada por hora.
  Future<List<ScheduledTrip>> agenda();

  Future<void> start(String tripId, {required String clientEventId});

  Future<TripLive> live(String tripId);

  Future<void> recordPassenger(
    String tripId,
    PassengerAction action, {
    required String studentId,
    required String clientEventId,
    required DateTime occurredAt,
    GeoPoint? position,
  });

  Future<void> undoPassenger(
    String tripId, {
    required String studentId,
    required String clientEventId,
  });

  Future<void> reportIncident(
    String tripId, {
    required IncidentType type,
    required String clientEventId,
    required DateTime occurredAt,
    required bool notifyGuardians,
    String? detail,
    GeoPoint? position,
  });

  /// SOS: la cuenta regresiva de 5 s es solo de la app; esto se llama al
  /// terminarla. [position] es opcional: nunca falla por falta de GPS.
  Future<void> raiseSos(
    String tripId, {
    required String clientEventId,
    required DateTime occurredAt,
    GeoPoint? position,
  });

  Future<void> complete(String tripId, {required String clientEventId});

  Future<TripSummaryData> summary(String tripId);

  /// Lote de lecturas GPS (máximo [maxReadingsPerBatch]).
  Future<PositionsResult> recordPositions(String tripId, List<GpsReading> readings);
}

const maxReadingsPerBatch = 500;

class HttpTripApi implements TripApi {
  HttpTripApi(this._client);

  final ApiClient _client;

  @override
  Future<List<ScheduledTrip>> agenda() async => [
        for (final t in await _client.get('/drivers/me/trips') as List)
          ScheduledTrip.fromJson(t as Map<String, dynamic>),
      ];

  @override
  Future<void> start(String tripId, {required String clientEventId}) =>
      _client.post('/trips/$tripId/start', body: {'clientEventId': clientEventId});

  @override
  Future<TripLive> live(String tripId) async => TripLive.fromJson(
        await _client.get('/trips/$tripId/live') as Map<String, dynamic>,
      );

  @override
  Future<void> recordPassenger(
    String tripId,
    PassengerAction action, {
    required String studentId,
    required String clientEventId,
    required DateTime occurredAt,
    GeoPoint? position,
  }) {
    final path = switch (action) {
      PassengerAction.board => 'boardings',
      PassengerAction.alight => 'alightings',
      PassengerAction.absent => 'absences',
    };
    return _client.post('/trips/$tripId/$path', body: {
      'studentId': studentId,
      'clientEventId': clientEventId,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      // Las ausencias no llevan posición.
      if (position != null && action != PassengerAction.absent)
        'position': {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
    });
  }

  @override
  Future<void> undoPassenger(
    String tripId, {
    required String studentId,
    required String clientEventId,
  }) =>
      _client.post(
        '/trips/$tripId/passengers/$studentId/undo',
        body: {'clientEventId': clientEventId},
      );

  @override
  Future<void> reportIncident(
    String tripId, {
    required IncidentType type,
    required String clientEventId,
    required DateTime occurredAt,
    required bool notifyGuardians,
    String? detail,
    GeoPoint? position,
  }) =>
      _client.post('/trips/$tripId/incidents', body: {
        'clientEventId': clientEventId,
        'incidentType': type.apiName,
        'detail': ?detail,
        'notifyGuardians': notifyGuardians,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        if (position != null)
          'position': {
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
      });

  @override
  Future<void> raiseSos(
    String tripId, {
    required String clientEventId,
    required DateTime occurredAt,
    GeoPoint? position,
  }) =>
      _client.post('/trips/$tripId/sos', body: {
        'clientEventId': clientEventId,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        if (position != null)
          'position': {
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
      });

  @override
  Future<void> complete(String tripId, {required String clientEventId}) =>
      _client.post('/trips/$tripId/complete', body: {'clientEventId': clientEventId});

  @override
  Future<TripSummaryData> summary(String tripId) async => TripSummaryData.fromJson(
        await _client.get('/trips/$tripId/summary') as Map<String, dynamic>,
      );

  @override
  Future<PositionsResult> recordPositions(
    String tripId,
    List<GpsReading> readings,
  ) async =>
      PositionsResult.fromJson(
        await _client.post('/tracking/positions', body: {
          'tripId': tripId,
          'readings': [for (final r in readings) r.toJson()],
        }) as Map<String, dynamic>,
      );
}

final tripApiProvider = Provider<TripApi>(
  (ref) => HttpTripApi(ref.watch(apiClientProvider)),
);
