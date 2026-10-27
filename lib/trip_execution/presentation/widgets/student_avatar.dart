import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../../stakeholder/application/students_repository.dart';
import '../../../stakeholder/domain/model/route_student.dart';

/// Foto del alumno (guardada en el teléfono) o, si no hay, sus iniciales.
class StudentAvatar extends ConsumerWidget {
  const StudentAvatar({super.key, required this.student, this.size = 50});

  final RouteStudent student;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(studentPhotoProvider(student)).value;
    final initials = InitialsAvatar(initials: student.initials, size: size);
    if (bytes == null) return initials;
    return ClipOval(
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Foto dañada en disco: se muestran las iniciales.
        errorBuilder: (_, _, _) => initials,
      ),
    );
  }
}
