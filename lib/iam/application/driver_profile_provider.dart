import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/model/driver.dart';
import '../infrastructure/iam_api.dart';
import '../infrastructure/roster_api.dart';
import 'session_controller.dart';

Duration? _noRetry(int retryCount, Object error) => null;

/// Perfil del conductor: Roster (datos, vehículos, rutas) + nombre de la
/// empresa. Se recarga solo si cambia la cuenta; `ref.invalidate` para
/// reintentar.
final driverProfileProvider = FutureProvider.autoDispose<DriverProfile>(retry: _noRetry, (ref) async {
  final session = ref.watch(sessionControllerProvider);
  if (session is! SessionActive) throw StateError('Sin sesión activa');
  final user = session.user;

  final roster = ref.read(rosterApiProvider);
  final iam = ref.read(iamApiProvider);

  final results = await Future.wait<Object?>([
    roster.me(),
    roster.vehicles(),
    roster.routes(),
    // La empresa es decorativa: si falla no debe tumbar el perfil.
    iam.organizationName(user.organizationId).then<String?>(
          (name) => name,
          onError: (Object _) => null,
        ),
  ]);

  return DriverProfile(
    user: user,
    driver: results[0]! as DriverRecord,
    vehicles: results[1]! as List<Vehicle>,
    routes: results[2]! as List<DriverRoute>,
    organizationName: results[3] as String?,
  );
});
