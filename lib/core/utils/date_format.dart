/// Formatos de fecha/hora en español sin depender de paquetes externos.
abstract final class DateFmt {
  static const _days = [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo',
  ];
  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// "Lunes 5 de octubre"
  static String longDay(DateTime d) =>
      '${_days[d.weekday - 1]} ${d.day} de ${_months[d.month - 1]}';

  /// "6:58"
  static String time(DateTime d) =>
      '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  /// "Buenos días" / "Buenas tardes" / "Buenas noches"
  static String greeting(DateTime d) {
    if (d.hour < 12) return 'Buenos días';
    if (d.hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }
}
