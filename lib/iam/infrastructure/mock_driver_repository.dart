import '../domain/model/driver.dart';

/// Datos simulados del conductor para la fase visual.
/// Se reemplazará por el cliente HTTP del Identity & Access Service.
abstract final class MockDriverRepository {
  static final Driver currentDriver = Driver(
    id: 'drv-001',
    firstName: 'Jorge',
    lastNames: 'Mendoza Salas',
    company: 'Transportes Santa Rosa',
    license: DriverLicense(
      category: 'A-IIb',
      expiresOn: DateTime(2028, 8, 12),
    ),
    vehicle: Vehicle(
      plate: 'ABC-123',
      model: 'Toyota Coaster',
      seats: 22,
      soatValidUntil: DateTime(2027, 3),
    ),
  );
}
