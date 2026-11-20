import 'package:flutter/services.dart';

import 'models.dart';

/// Telefondaki takvimleri okur (Google Takvim de telefonla senkronize olduğu için dahil).
/// Yerel kodu: android/app/src/main/kotlin/.../MainActivity.kt
class CalendarService {
  static const _ch = MethodChannel('asistan/calendar');

  static Future<bool> hasPermission() async =>
      await _ch.invokeMethod<bool>('hasPermission') ?? false;

  static Future<bool> requestPermission() async =>
      await _ch.invokeMethod<bool>('requestPermission') ?? false;

  // ---- Outlook mailleri (bildirim erişimi) ----
  static Future<bool> mailAccessEnabled() async =>
      await _ch.invokeMethod<bool>('mailAccessEnabled') ?? false;

  static Future<void> openMailAccessSettings() =>
      _ch.invokeMethod('openMailAccessSettings');

  static Future<int> mailCount() async =>
      await _ch.invokeMethod<int>('mailCount') ?? 0;

  /// [from, to) aralığındaki etkinlikleri Task olarak döndürür (salt okunur).
  static Future<List<Task>> events(DateTime from, DateTime to) async {
    final raw = await _ch.invokeListMethod<Map<Object?, Object?>>('getEvents', {
      'start': from.millisecondsSinceEpoch,
      'end': to.millisecondsSinceEpoch,
    });
    if (raw == null) return [];
    final out = <Task>[];
    for (final m in raw) {
      final allDay = m['allDay'] as bool? ?? false;
      final beginMs = (m['begin'] as num).toInt();
      DateTime begin;
      if (allDay) {
        // Tüm gün etkinlikleri UTC gece yarısı olarak saklanır.
        final u = DateTime.fromMillisecondsSinceEpoch(beginMs, isUtc: true);
        begin = DateTime(u.year, u.month, u.day);
      } else {
        begin = DateTime.fromMillisecondsSinceEpoch(beginMs);
      }
      final eventId = (m['eventId'] as num).toInt();
      out.add(Task(
        id: _notifId(eventId, beginMs),
        title: (m['title'] as String?)?.trim().isNotEmpty == true
            ? (m['title'] as String).trim()
            : '(Başlıksız)',
        when: begin,
        hasTime: !allDay,
        calendar: m['calendar'] as String?,
        location: (m['location'] as String?)?.trim(),
        color: (m['color'] as num?)?.toInt(),
      ));
    }
    return out;
  }

  /// Takvim etkinliklerine 1.000.000.000 üstü bildirim kimlikleri verilir,
  /// böylece elle eklenen işlerle karışmaz.
  static int _notifId(int eventId, int beginMs) =>
      1000000000 + ((eventId * 31 + beginMs ~/ 60000) % 900000000).abs();
}
