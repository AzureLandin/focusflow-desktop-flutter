/// src/shared/model.ts:1-14 与 src-tauri/src/model.rs:8-42 的 Dart 对应实现。
///
/// 日期一律以 `yyyy-MM-dd` 字符串表示，运算统一用当地中午 12:00，
/// 避开 DST 切换导致的跨日偏移。时间戳沿用毫秒 epoch。
library;

import 'package:timezone/timezone.dart' as tz;

import 'errors.dart';

/// 当前毫秒时间戳（对齐 Rust model::now）。
int nowMillis() => DateTime.now().millisecondsSinceEpoch;

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// 毫秒 epoch → 本地日期键。
String localDay([int? millis]) => dateKey(
      millis == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(millis),
    );

/// 毫秒 epoch → 指定时区的日期键（DST 用例使用）。
String dateInZone(int millis, tz.Location zone) =>
    dateKey(tz.TZDateTime.fromMillisecondsSinceEpoch(zone, millis));

/// 严格校验 yyyy-MM-dd：长度、分隔符、真实日历日期都必须正确。
bool isValidDateKey(String value) {
  if (value.length != 10) return false;
  if (value[4] != '-' || value[7] != '-') return false;
  final year = int.tryParse(value.substring(0, 4));
  final month = int.tryParse(value.substring(5, 7));
  final day = int.tryParse(value.substring(8, 10));
  if (year == null || month == null || day == null) return false;
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  return dateKey(DateTime(year, month, day)) == value;
}

/// 校验失败抛出与 zod / Rust 相同文案的用户错误。
String parseDate(String value) {
  if (!isValidDateKey(value)) throw FocusFlowException(badInput);
  return value;
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
    dateKey(dayAtNoon(day).add(Duration(days: amount)));

String shiftMonth(String day, int amount) {
  final noon = dayAtNoon(day);
  final monthIndex = noon.year * 12 + (noon.month - 1) + amount;
  return dateKey(DateTime(monthIndex ~/ 12, monthIndex % 12 + 1, noon.day, 12));
}

String firstOfMonth(String day) => '${day.substring(0, 7)}-01';

/// 以周一为起始的 42 格月历（与 Rust calendar_days 一致）。
List<String> calendarDays(String month) {
  final first = firstOfMonth(parseDate(month));
  final start = shiftDay(first, -(dayAtNoon(first).weekday - 1));
  return List.generate(42, (index) => shiftDay(start, index));
}

/// 与 Rust model::valid_text 一致：UTF-16 长度落在区间内且不含 NUL。
bool validText(String value, int min, int max) =>
    value.length >= min &&
    value.length <= max &&
    !value.contains(String.fromCharCode(0));

/// 与 Rust model::clean_text 一致：去掉首尾空白与 BOM 后再校验。
String cleanText(String value, int min, int max) {
  var start = 0;
  var end = value.length;
  bool trimmable(int unit) =>
      unit == 0xFEFF || String.fromCharCode(unit).trim().isEmpty;
  while (start < end && trimmable(value.codeUnitAt(start))) {
    start++;
  }
  while (end > start && trimmable(value.codeUnitAt(end - 1))) {
    end--;
  }
  final cleaned = value.substring(start, end);
  if (!validText(cleaned, min, max)) {
    throw FocusFlowException(badInput);
  }
  return cleaned;
}
