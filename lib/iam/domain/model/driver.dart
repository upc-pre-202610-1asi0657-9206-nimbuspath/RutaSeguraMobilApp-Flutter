/// Cuenta autenticada (bounded context Identity & Access).
class SessionUser {
  const SessionUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.organizationId,
  });

  /// Id de usuario IAM (el mismo que lleva el token).
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String organizationId;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final f = firstName.isEmpty ? '' : firstName[0];
    final l = lastName.isEmpty ? '' : lastName[0];
    return '$f$l'.toUpperCase();
  }

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        id: json['id'] as String,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        organizationId: json['organizationId'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'organizationId': organizationId,
      };
}

/// Resultado de `POST /users/sign-in`.
class SignInResult {
  const SignInResult({
    required this.user,
    required this.roleTier,
    required this.token,
  });

  final SessionUser user;
  final String roleTier;
  final String token;

  bool get isDriver => roleTier == 'DRIVER';
}

/// Conductor en el Roster de Administration.
class DriverRecord {
  const DriverRecord({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.licenseCategory,
    required this.licenseExpiresOn,
    required this.status,
  });

  /// Id del Roster (distinto del id de IAM). La app nunca lo envía.
  final String id;
  final String firstName;
  final String lastName;
  final String licenseCategory;
  final DateTime licenseExpiresOn;

  /// `PENDING_VERIFICATION` | `VERIFIED` | `SUSPENDED`.
  final String status;

  /// Licencia vigente: conductor verificado y licencia sin vencer.
  bool get hasValidLicense =>
      status == 'VERIFIED' && !licenseExpiresOn.isBefore(_today());

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  factory DriverRecord.fromJson(Map<String, dynamic> json) => DriverRecord(
        id: json['id'] as String,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        licenseCategory: json['licenseCategory'] as String? ?? '',
        licenseExpiresOn: DateTime.parse(json['licenseExpiresOn'] as String),
        status: json['status'] as String? ?? '',
      );
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.licensePlate,
    required this.seatingCapacity,
    required this.brand,
    required this.model,
  });

  final String id;
  final String licensePlate;
  final int seatingCapacity;
  final String brand;
  final String model;

  String get displayName => '$brand $model'.trim();

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: json['id'] as String,
        licensePlate: json['licensePlate'] as String? ?? '',
        seatingCapacity: (json['seatingCapacity'] as num?)?.toInt() ?? 0,
        brand: json['brand'] as String? ?? '',
        model: json['model'] as String? ?? '',
      );
}

/// Ruta asignada al conductor (solo lectura).
class DriverRoute {
  const DriverRoute({
    required this.id,
    required this.name,
    required this.direction,
    required this.status,
    required this.departureTime,
    required this.operatingDays,
  });

  final String id;
  final String name;

  /// `PICKUP` | `RETURN`.
  final String direction;

  /// `DRAFT` | `ACTIVE` | `INACTIVE`.
  final String status;

  /// "06:40" (sin segundos).
  final String departureTime;

  /// Nombres en inglés tal como llegan: `Monday`, `Tuesday`...
  final List<String> operatingDays;

  factory DriverRoute.fromJson(Map<String, dynamic> json) {
    final schedule = json['schedule'] as Map<String, dynamic>? ?? const {};
    final time = schedule['departureTime'] as String? ?? '';
    return DriverRoute(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      direction: json['direction'] as String? ?? '',
      status: json['status'] as String? ?? '',
      departureTime: time.length >= 5 ? time.substring(0, 5) : time,
      operatingDays: [
        for (final d in schedule['operatingDays'] as List? ?? const [])
          d as String,
      ],
    );
  }
}

/// Todo lo que muestra la pantalla Perfil.
class DriverProfile {
  const DriverProfile({
    required this.user,
    required this.driver,
    required this.vehicles,
    required this.routes,
    this.organizationName,
  });

  final SessionUser user;
  final DriverRecord driver;
  final List<Vehicle> vehicles;
  final List<DriverRoute> routes;

  /// `null` si no se pudo leer la organización (no bloquea el perfil).
  final String? organizationName;
}
