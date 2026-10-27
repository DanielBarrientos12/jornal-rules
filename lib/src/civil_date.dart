/// Fecha de calendario sin hora ni zona horaria.
///
/// Internamente usa `DateTime.utc` para la aritmética: Colombia no tiene
/// horario de verano, y trabajar en UTC evita que el huso del dispositivo
/// mueva días al sumar o restar.
class CivilDate implements Comparable<CivilDate> {
  CivilDate(this.year, this.month, this.day) {
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw ArgumentError('Fecha inválida: $year-$month-$day');
    }
  }

  /// Toma solo año, mes y día de [dateTime] (ignora hora y zona).
  factory CivilDate.fromDateTime(DateTime dateTime) =>
      CivilDate(dateTime.year, dateTime.month, dateTime.day);

  /// Lee `AAAA-MM-DD` estricto.
  factory CivilDate.parse(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (match == null) {
      throw FormatException('Fecha con formato inválido (AAAA-MM-DD)', text);
    }
    return CivilDate(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  final int year;
  final int month;
  final int day;

  DateTime toUtc() => DateTime.utc(year, month, day);

  /// 1 = lunes … 7 = domingo, igual que [DateTime.weekday].
  int get weekday => toUtc().weekday;

  bool get isSunday => weekday == DateTime.sunday;

  CivilDate addDays(int days) =>
      CivilDate.fromDateTime(toUtc().add(Duration(days: days)));

  /// El lunes de la semana (lunes a domingo) que contiene esta fecha.
  CivilDate get mondayOfWeek => addDays(1 - weekday);

  bool isBefore(CivilDate other) => compareTo(other) < 0;

  bool isAfter(CivilDate other) => compareTo(other) > 0;

  @override
  int compareTo(CivilDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CivilDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
