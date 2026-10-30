import 'dart:convert';

/// Tipos de evento que se pueden guardar y mandar por `/sync`.
/// `start` y `complete` NO van aquí: tienen su propio endpoint.
enum QueuedEventType {
  boarding('Boarding'),
  alighting('Alighting'),
  absent('Absent'),
  undo('Undo'),
  incident('Incident'),
  sos('Sos');

  const QueuedEventType(this.apiName);
  final String apiName;

  static QueuedEventType? fromApi(String? name) {
    for (final t in values) {
      if (t.apiName == name) return t;
    }
    return null;
  }

  /// Cambian el estado de un alumno (se reflejan en la lista de abordaje).
  bool get isPassengerChange => switch (this) {
        boarding || alighting || absent || undo => true,
        incident || sos => false,
      };
}

/// Una acción del conductor que aún no confirmó el servidor.
///
/// El [clientEventId] se generó al tocar y no cambia nunca: reenviar el
/// evento (directo o por `/sync`) es seguro.
class QueuedEvent {
  const QueuedEvent({
    required this.tripId,
    required this.clientEventId,
    required this.type,
    required this.occurredAt,
    this.studentId,
    this.latitude,
    this.longitude,
    this.incidentType,
    this.detail,
    this.notifyGuardians,
    this.seq,
  });

  /// Posición en la cola (la asigna el almacén).
  final int? seq;
  final String tripId;
  final String clientEventId;
  final QueuedEventType type;
  final DateTime occurredAt;
  final String? studentId;
  final double? latitude;
  final double? longitude;
  final String? incidentType;
  final String? detail;
  final bool? notifyGuardians;

  /// Cuerpo de un evento de `POST /trips/{id}/sync` (§7.4).
  Map<String, dynamic> toSyncJson() => {
        'clientEventId': clientEventId,
        'type': type.apiName,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'studentId': ?studentId,
        if (latitude != null && longitude != null)
          'position': {'latitude': latitude, 'longitude': longitude},
        'incidentType': ?incidentType,
        'detail': ?detail,
        'notifyGuardians': ?notifyGuardians,
      };

  Map<String, Object?> toRow() => {
        'trip_id': tripId,
        'client_event_id': clientEventId,
        'type': type.apiName,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'payload': jsonEncode({
          'studentId': studentId,
          'latitude': latitude,
          'longitude': longitude,
          'incidentType': incidentType,
          'detail': detail,
          'notifyGuardians': notifyGuardians,
        }),
      };

  factory QueuedEvent.fromRow(Map<String, Object?> row) {
    final p = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    return QueuedEvent(
      seq: row['seq'] as int?,
      tripId: row['trip_id'] as String,
      clientEventId: row['client_event_id'] as String,
      type: QueuedEventType.fromApi(row['type'] as String)!,
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      studentId: p['studentId'] as String?,
      latitude: (p['latitude'] as num?)?.toDouble(),
      longitude: (p['longitude'] as num?)?.toDouble(),
      incidentType: p['incidentType'] as String?,
      detail: p['detail'] as String?,
      notifyGuardians: p['notifyGuardians'] as bool?,
    );
  }
}

/// Respuesta por evento de `/sync`.
enum SyncStatus { applied, duplicate, rejected }

class SyncOutcome {
  const SyncOutcome({required this.clientEventId, required this.status, this.errorCode});

  final String clientEventId;
  final SyncStatus status;
  final String? errorCode;

  factory SyncOutcome.fromJson(Map<String, dynamic> j) => SyncOutcome(
        clientEventId: j['clientEventId'] as String,
        status: switch (j['status']) {
          'Applied' => SyncStatus.applied,
          'Duplicate' => SyncStatus.duplicate,
          _ => SyncStatus.rejected,
        },
        errorCode: j['errorCode'] as String?,
      );
}

/// Máximo de eventos por llamada a `/sync`.
const maxEventsPerSync = 200;
