/// Alumno de una de las rutas del conductor (Stakeholder, solo lectura).
class RouteStudent {
  const RouteStudent({
    required this.studentId,
    required this.routeId,
    required this.firstName,
    required this.lastName,
    required this.schoolGrade,
    this.photoUrl,
    this.stopId,
    this.stopName,
    this.stopSequence,
    this.guardianName,
    this.guardianPhone,
  });

  final String studentId;
  final String routeId;
  final String firstName;
  final String lastName;
  final String schoolGrade;

  /// Relativa al Gateway (`/api/v1/stakeholders/students/{id}/photo?v=3`);
  /// `null` si el alumno no tiene foto.
  final String? photoUrl;

  final String? stopId;
  final String? stopName;
  final int? stopSequence;
  final String? guardianName;
  final String? guardianPhone;

  @override
  bool operator ==(Object other) =>
      other is RouteStudent &&
      other.studentId == studentId &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(studentId, photoUrl);

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final f = firstName.isEmpty ? '' : firstName[0];
    final l = lastName.isEmpty ? '' : lastName[0];
    return '$f$l'.toUpperCase();
  }

  /// Versión de la foto (`?v=`), para saber si hay que volver a descargarla.
  String get photoVersion =>
      photoUrl == null ? '' : Uri.parse(photoUrl!).queryParameters['v'] ?? '0';

  factory RouteStudent.fromJson(Map<String, dynamic> json) {
    final stop = json['stop'] as Map<String, dynamic>?;
    final guardian = json['guardian'] as Map<String, dynamic>?;
    return RouteStudent(
      studentId: json['studentId'] as String,
      routeId: json['routeId'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      schoolGrade: json['schoolGrade'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      stopId: stop?['stopId'] as String?,
      stopName: stop?['name'] as String?,
      stopSequence: (stop?['sequence'] as num?)?.toInt(),
      guardianName: guardian?['fullName'] as String?,
      guardianPhone: guardian?['phoneNumber'] as String?,
    );
  }

  /// Mismo formato que el backend (lo que se guarda en la caché local).
  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'routeId': routeId,
        'firstName': firstName,
        'lastName': lastName,
        'schoolGrade': schoolGrade,
        'photoUrl': photoUrl,
        'stop': stopId == null
            ? null
            : {'stopId': stopId, 'name': stopName, 'sequence': stopSequence},
        'guardian': guardianName == null && guardianPhone == null
            ? null
            : {'fullName': guardianName, 'phoneNumber': guardianPhone},
      };
}
