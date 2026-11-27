import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class StopArrivalBanner extends StatelessWidget {
  const StopArrivalBanner({
    required this.stopName,
    required this.studentNames,
    required this.onDismiss,
    required this.onStudents,
    super.key,
  });
  final String stopName;
  final List<String> studentNames;
  final VoidCallback onDismiss, onStudents;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Material(
      color: const Color(0xFFE8F5EF),
      borderRadius: BorderRadius.circular(16),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 10),
                  child: Icon(Icons.location_on, color: Color(0xFF16764B)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        studentNames.isEmpty
                            ? 'Has llegado a $stopName'
                            : 'Has llegado a la parada de ${studentNames.join(', ')}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'GPS cercano. Revisa a los alumnos cuando estes detenido.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar aviso de llegada',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onStudents,
                child: const Text('Ver alumnos'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
