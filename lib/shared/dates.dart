/// src/shared/model.ts:4-14 的 Dart 对应实现。
/// 统一用当地中午 12:00 做日期运算，避开 DST 导致的跨日偏移。
library;

String localDay([DateTime? time]) {
  final d = time ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

DateTime dayAtNoon(String day) {
  final parts = day.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
    12,
  );
}

String shiftDay(String day, int amount) =>
    localDay(dayAtNoon(day).add(Duration(days: amount)));

String shiftMonth(String day, int amount) {
  final noon = dayAtNoon(day);
  final monthIndex = noon.year * 12 + (noon.month - 1) + amount;
  return localDay(
    DateTime(monthIndex ~/ 12, monthIndex % 12 + 1, noon.day, 12),
  );
}

String firstOfMonth(String day) => '${day.substring(0, 7)}-01';

/// 以周一为起始的 42 格月历。
List<String> calendarDays(String month) {
  final first = firstOfMonth(month);
  final weekday = dayAtNoon(first).weekday; // DateTime: 1=Mon .. 7=Sun
  final start = shiftDay(first, -(weekday - 1));
  return List.generate(42, (index) => shiftDay(start, index));
}
