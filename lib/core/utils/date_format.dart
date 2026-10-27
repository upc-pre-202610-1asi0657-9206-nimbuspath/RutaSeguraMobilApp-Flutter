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

  /// "12 de agosto de 2028"
  static String longDate(DateTime d) =>
      '${d.day} de ${_months[d.month - 1]} de ${d.year}';

  static const _englishDays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];

  /// Días de operación del backend (`Monday`...) en texto:
  /// "Lunes a viernes", "Lunes, miércoles y viernes".
  static String operatingDays(List<String> days) {
    final idx = ({
      for (final d in days) _englishDays.indexOf(d),
    }..remove(-1))
        .toList()
      ..sort();
    if (idx.isEmpty) return 'Sin días definidos';
    if (idx.length == 1) return _days[idx.first];
    final consecutive = idx.last - idx.first == idx.length - 1;
    if (consecutive && idx.length > 2) {
      return '${_days[idx.first]} a ${_days[idx.last].toLowerCase()}';
    }
    final names = [for (final i in idx) _days[i].toLowerCase()];
    names[0] = _days[idx.first];
    return '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
  }

  /// Lima es UTC-5 todo el año (sin horario de verano). Devuelve un
  /// `DateTime` cuyos campos de hora ya son los de Lima (marcado como UTC).
  static DateTime toLima(DateTime d) => d.toUtc().subtract(const Duration(hours: 5));

  /// "2026-10-26" según el calendario de Lima.
  static String limaDateKey(DateTime d) {
    final l = toLima(d);
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

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
