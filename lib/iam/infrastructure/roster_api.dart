import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../domain/model/driver.dart';

/// Roster de Administration: lo que el conductor puede leer de sí mismo.
/// Responde 404 `DriverNotFound` si el ADMIN aún no lo registró.
abstract interface class RosterApi {
  Future<DriverRecord> me();
  Future<List<Vehicle>> vehicles();
  Future<List<DriverRoute>> routes();
}

class HttpRosterApi implements RosterApi {
  HttpRosterApi(this._client);

  final ApiClient _client;

  @override
  Future<DriverRecord> me() async => DriverRecord.fromJson(
        await _client.get('/roster/drivers/me') as Map<String, dynamic>,
      );

  @override
  Future<List<Vehicle>> vehicles() async => [
        for (final v in await _client.get('/roster/drivers/me/vehicles') as List)
          Vehicle.fromJson(v as Map<String, dynamic>),
      ];

  @override
  Future<List<DriverRoute>> routes() async => [
        for (final r in await _client.get('/roster/drivers/me/routes') as List)
          DriverRoute.fromJson(r as Map<String, dynamic>),
      ];
}

final rosterApiProvider = Provider<RosterApi>(
  (ref) => HttpRosterApi(ref.watch(apiClientProvider)),
);
