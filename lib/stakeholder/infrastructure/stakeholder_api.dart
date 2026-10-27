import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../domain/model/route_student.dart';

/// Stakeholder vía Gateway: los alumnos que ve el conductor.
abstract interface class StakeholderApi {
  /// Alumnos activos de **todas** sus rutas.
  Future<List<RouteStudent>> myStudents();

  /// Foto con token. [photoUrl] es la relativa que trae el alumno.
  Future<Uint8List> photo(String photoUrl);
}

class HttpStakeholderApi implements StakeholderApi {
  HttpStakeholderApi(this._client);

  final ApiClient _client;

  @override
  Future<List<RouteStudent>> myStudents() async => [
        for (final s
            in await _client.get('/stakeholders/drivers/me/students') as List)
          RouteStudent.fromJson(s as Map<String, dynamic>),
      ];

  @override
  Future<Uint8List> photo(String photoUrl) => _client.getBytes(photoUrl);
}

final stakeholderApiProvider = Provider<StakeholderApi>(
  (ref) => HttpStakeholderApi(ref.watch(apiClientProvider)),
);
