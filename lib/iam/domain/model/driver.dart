/// Conductor autenticado (bounded context Identity & Access).
class Driver {
  const Driver({
    required this.id,
    required this.firstName,
    required this.lastNames,
    required this.company,
    required this.license,
    required this.vehicle,
  });

  final String id;
  final String firstName;
  final String lastNames;
  final String company;
  final DriverLicense license;
  final Vehicle vehicle;

  String get fullName => '$firstName $lastNames';

  String get initials => '${firstName[0]}${lastNames[0]}'.toUpperCase();
}

class DriverLicense {
  const DriverLicense({required this.category, required this.expiresOn});

  final String category;
  final DateTime expiresOn;

  bool get isValid => expiresOn.isAfter(DateTime.now());
}

class Vehicle {
  const Vehicle({
    required this.plate,
    required this.model,
    required this.seats,
    required this.soatValidUntil,
  });

  final String plate;
  final String model;
  final int seats;
  final DateTime soatValidUntil;
}
