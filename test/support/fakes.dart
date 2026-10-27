import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:rutasegura/core/network/api_error.dart';
import 'package:rutasegura/core/storage/token_storage.dart';
import 'package:rutasegura/iam/domain/model/driver.dart';
import 'package:rutasegura/iam/infrastructure/iam_api.dart';
import 'package:rutasegura/iam/infrastructure/roster_api.dart';
import 'package:rutasegura/core/storage/local_cache.dart';
import 'package:rutasegura/core/storage/photo_store.dart';
import 'package:rutasegura/stakeholder/domain/model/route_student.dart';
import 'package:rutasegura/stakeholder/infrastructure/stakeholder_api.dart';
import 'package:rutasegura/trip_execution/application/checklist.dart';
import 'package:rutasegura/trip_execution/application/tracking_controller.dart';
import 'package:rutasegura/trip_execution/application/tracking_engine.dart';
import 'package:rutasegura/trip_execution/domain/model/tracking.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_live.dart';
import 'package:rutasegura/trip_execution/domain/model/trip_models.dart';
import 'package:rutasegura/trip_execution/infrastructure/trip_api.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:rutasegura/trip_execution/application/trip_controller.dart';
import 'package:rutasegura/trip_execution/presentation/widgets/trip_map.dart';

const testUser = SessionUser(
  id: 'u1',
  firstName: 'Jorge',
  lastName: 'Mendoza',
  email: 'jorge@santarosa.pe',
  organizationId: 'org1',
);

class FakeIamApi implements IamApi {
  FakeIamApi({this.roleTier = 'DRIVER', this.signInError, this.meError});

  final String roleTier;
  final ApiError? signInError;
  final ApiError? meError;

  @override
  Future<SignInResult> signIn({
    required String email,
    required String password,
  }) async {
    if (signInError != null) throw signInError!;
    return SignInResult(user: testUser, roleTier: roleTier, token: 'jwt-nuevo');
  }

  @override
  Future<SessionUser> me() async {
    if (meError != null) throw meError!;
    return testUser;
  }

  @override
  Future<String> organizationName(String organizationId) async =>
      'Transportes Santa Rosa';
}

class FakeRosterApi implements RosterApi {
  FakeRosterApi({this.error});

  final ApiError? error;

  @override
  Future<DriverRecord> me() async {
    if (error != null) throw error!;
    return DriverRecord(
      id: 'd1',
      firstName: 'Jorge',
      lastName: 'Mendoza',
      licenseCategory: 'A-IIb',
      licenseExpiresOn: DateTime.now().add(const Duration(days: 400)),
      status: 'VERIFIED',
    );
  }

  @override
  Future<List<Vehicle>> vehicles() async => const [
        Vehicle(
          id: 'v1',
          licensePlate: 'ABC-123',
          seatingCapacity: 22,
          brand: 'Toyota',
          model: 'Coaster',
        ),
      ];

  @override
  Future<List<DriverRoute>> routes() async => const [
        DriverRoute(
          id: 'r1',
          name: 'Ruta 3',
          direction: 'PICKUP',
          status: 'ACTIVE',
          departureTime: '06:40',
          operatingDays: [
            'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
          ],
        ),
      ];
}

/// Viaje de la agenda. Por defecto sale en 30 min (dentro de la ventana de
/// inicio de 60 min).
ScheduledTrip testTrip({
  String id = 't1',
  String status = 'Scheduled',
  Duration startsIn = const Duration(minutes: 30),
  String direction = 'Pickup',
  String vehicleId = 'v1',
}) =>
    ScheduledTrip.fromJson({
      'tripId': id,
      'routeId': 'r1',
      'routeName': 'Ruta 3',
      'direction': direction,
      'scheduledStart': DateTime.now().add(startsIn).toUtc().toIso8601String(),
      'status': status,
      'vehicleId': vehicleId,
      'stopCount': 7,
      'studentCount': 18,
    });

LivePassenger testPassenger(
  String studentId, {
  String stopId = 'p1',
  PassengerStatus status = PassengerStatus.pending,
  String? absenceSource,
}) =>
    LivePassenger(
      studentId: studentId,
      stopId: stopId,
      status: status,
      absenceSource: absenceSource,
    );

/// Estado en vivo de un recojo con 2 paradas; los alumnos s1 y s2 suben en p1.
TripLive testLive({
  String tripId = 't1',
  bool isPickup = true,
  List<LivePassenger>? passengers,
  bool hasActiveSos = false,
}) {
  final list = passengers ?? [testPassenger('s1'), testPassenger('s2')];
  return TripLive(
    tripId: tripId,
    status: 'InProgress',
    isPickup: isPickup,
    startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    nextStop: const NextStop(
      stopId: 'p1',
      name: 'Av. Primavera 1240',
      sequence: 1,
      totalStops: 2,
      distanceMeters: 850,
      etaMinutes: 3,
    ),
    studentsOnBoard: list.where((p) => p.status == PassengerStatus.boarded).length,
    totalStudents: list.length,
    hasActiveSos: hasActiveSos,
    passengers: list,
    stops: const [
      LiveStop(stopId: 'p1', name: 'Av. Primavera 1240', sequence: 1, latitude: -12.1, longitude: -77.0),
      LiveStop(stopId: 'p2', name: 'Jr. Las Begonias 455', sequence: 2, latitude: -12.11, longitude: -77.01),
    ],
  );
}

class FakeTripApi implements TripApi {
  FakeTripApi({List<ScheduledTrip>? trips, this.error, TripLive? live})
      : trips = trips ?? [testTrip()],
        liveState = live ?? testLive();

  final List<ScheduledTrip> trips;
  ApiError? error;
  int calls = 0;

  TripLive liveState;
  ApiError? startError;
  ApiError? actionError;
  final startedWith = <String>[];

  /// Acciones recibidas: `board:s1:<eventId>`.
  final actions = <String>[];

  @override
  Future<void> start(String tripId, {required String clientEventId}) async {
    startedWith.add(clientEventId);
    if (startError != null) throw startError!;
  }

  @override
  Future<TripLive> live(String tripId) async => liveState;

  @override
  Future<void> recordPassenger(
    String tripId,
    PassengerAction action, {
    required String studentId,
    required String clientEventId,
    required DateTime occurredAt,
    GeoPoint? position,
  }) async {
    if (actionError != null) throw actionError!;
    actions.add('${action.name}:$studentId:$clientEventId');
    final to = switch (action) {
      PassengerAction.board => PassengerStatus.boarded,
      PassengerAction.alight => PassengerStatus.alighted,
      PassengerAction.absent => PassengerStatus.absent,
    };
    liveState = liveState.withPassengers([
      for (final p in liveState.passengers)
        p.studentId == studentId ? p.copyWith(status: to, boardedAt: occurredAt) : p,
    ]);
  }

  final incidents = <String>[]; // `HeavyTraffic|detalle|notificar`
  final sosEvents = <String>[]; // clientEventId
  final completeEvents = <String>[];
  Object? incidentError;
  Object? sosError;
  Object? completeError;
  TripSummaryData? summaryData;
  int summaryCalls = 0;

  @override
  Future<void> reportIncident(
    String tripId, {
    required IncidentType type,
    required String clientEventId,
    required DateTime occurredAt,
    required bool notifyGuardians,
    String? detail,
    GeoPoint? position,
  }) async {
    if (incidentError != null) throw incidentError!;
    incidents.add('${type.apiName}|${detail ?? ''}|$notifyGuardians');
  }

  @override
  Future<void> raiseSos(
    String tripId, {
    required String clientEventId,
    required DateTime occurredAt,
    GeoPoint? position,
  }) async {
    if (sosError != null) throw sosError!;
    sosEvents.add(clientEventId);
  }

  @override
  Future<void> complete(String tripId, {required String clientEventId}) async {
    completeEvents.add(clientEventId);
    if (completeError != null) throw completeError!;
  }

  @override
  Future<TripSummaryData> summary(String tripId) async {
    summaryCalls++;
    final d = summaryData;
    if (d == null) throw const ApiError(kind: ApiErrorKind.network);
    return d;
  }

  /// Lotes recibidos (cada uno es la lista de lecturas enviada).
  final positionBatches = <List<GpsReading>>[];
  Object? positionsError;

  @override
  Future<PositionsResult> recordPositions(
    String tripId,
    List<GpsReading> readings,
  ) async {
    if (positionsError != null) throw positionsError!;
    positionBatches.add(List.of(readings));
    return PositionsResult(accepted: readings.length, ignored: 0, rejected: 0);
  }

  @override
  Future<void> undoPassenger(
    String tripId, {
    required String studentId,
    required String clientEventId,
  }) async {
    if (actionError != null) throw actionError!;
    actions.add('undo:$studentId:$clientEventId');
    liveState = liveState.withPassengers([
      for (final p in liveState.passengers)
        p.studentId == studentId
            ? p.copyWith(status: PassengerStatus.pending, clearTimes: true)
            : p,
    ]);
  }

  @override
  Future<List<ScheduledTrip>> agenda() async {
    calls++;
    if (error != null) throw error!;
    return trips;
  }
}

const testStudent = RouteStudent(
  studentId: 's1',
  routeId: 'r1',
  firstName: 'Valeria',
  lastName: 'Quispe',
  schoolGrade: '3.° de primaria',
  photoUrl: '/api/v1/stakeholders/students/s1/photo?v=3',
  stopId: 'p1',
  stopName: 'Av. Primavera 1240',
  stopSequence: 4,
  guardianName: 'Rosa Quispe',
  guardianPhone: '987654321',
);

class FakeStakeholderApi implements StakeholderApi {
  FakeStakeholderApi({this.students = const [testStudent], this.error});

  final List<RouteStudent> students;
  ApiError? error;
  int photoCalls = 0;

  @override
  Future<List<RouteStudent>> myStudents() async {
    if (error != null) throw error!;
    return students;
  }

  @override
  Future<Uint8List> photo(String photoUrl) async {
    photoCalls++;
    return Uint8List.fromList([1, 2, 3]);
  }
}

/// GPS simulado: `emit` hace llegar una lectura como si la diera el teléfono.
class FakePositionSource implements PositionSource {
  FakePositionSource({this.permission = TrackingPermission.granted});

  TrackingPermission permission;
  final _controller = StreamController<GpsReading>.broadcast();
  bool get hasListener => _controller.hasListener;

  void emit(GpsReading r) => _controller.add(r);

  @override
  Future<TrackingPermission> ensurePermission() async => permission;

  @override
  Stream<GpsReading> readings() => _controller.stream;
}

GpsReading testReading({
  double lat = -12.1,
  double lon = -77.0,
  double accuracy = 8,
  double speedKmh = 20,
  DateTime? at,
}) =>
    GpsReading(
      latitude: lat,
      longitude: lon,
      recordedAt: at ?? DateTime.now(),
      accuracyMeters: accuracy,
      speedKmh: speedKmh,
    );

class FakeDeviceChecks implements DeviceChecks {
  @override
  Future<CheckResult> gps({bool requestPermission = false}) async =>
      const CheckResult(CheckLevel.ok, 'GPS activado', 'Precisión de 8 m');

  @override
  Future<CheckResult> network() async =>
      const CheckResult(CheckLevel.ok, 'Datos móviles con señal');

  @override
  Future<CheckResult> battery() async => const CheckResult(
        CheckLevel.warning,
        'Batería al 34 %',
        'Conecta el cargador antes de partir',
      );
}

/// Overrides para probar la app sin red.
List<Override> fakeBackend({
  PositionSource? gps,
  Duration flushEvery = const Duration(hours: 1),
  TokenStorage? storage,
  IamApi? iam,
  RosterApi? roster,
  TripApi? trips,
  StakeholderApi? stakeholders,
  LocalCache? cache,
  PhotoStore? photos,
}) =>
    [
      tokenStorageProvider.overrideWithValue(storage ?? signedInStorage()),
      iamApiProvider.overrideWithValue(iam ?? FakeIamApi()),
      rosterApiProvider.overrideWithValue(roster ?? FakeRosterApi()),
      tripApiProvider.overrideWithValue(trips ?? FakeTripApi()),
      stakeholderApiProvider.overrideWithValue(stakeholders ?? FakeStakeholderApi()),
      deviceChecksProvider.overrideWithValue(FakeDeviceChecks()),
      positionSourceProvider.overrideWithValue(gps ?? FakePositionSource()),
      trackingFlushEveryProvider.overrideWithValue(flushEvery),
      positionReaderProvider.overrideWithValue(() async => (latitude: -12.1, longitude: -77.0)),
      tripMapBuilderProvider.overrideWithValue((_) => const SizedBox.expand(key: Key('fake-map'))),
      localCacheProvider.overrideWithValue(cache ?? InMemoryLocalCache()),
      photoStoreProvider.overrideWithValue(photos ?? InMemoryPhotoStore()),
    ];

InMemoryTokenStorage signedInStorage() => InMemoryTokenStorage('jwt');
