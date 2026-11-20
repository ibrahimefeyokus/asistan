import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

class Notifier {
  static final _p = FlutterLocalNotificationsPlugin();
  static const _morningId = 999999999;
  static const morningHour = 8;
  static bool _exactAsked = false;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _p.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'gorevler',
      'Görev hatırlatmaları',
      channelDescription: 'Planladığın işler için hatırlatmalar',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    await _p.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_asistan'),
      ),
    );
  }

  /// Ekran açıldıktan sonra çağrılır; izin penceresi açılışı bloklamasın.
  static Future<void> askPermission() async {
    await _android?.requestNotificationsPermission();
  }

  static Future<AndroidScheduleMode> _mode({bool ask = true}) async {
    final a = _android;
    if (a == null) return AndroidScheduleMode.inexactAllowWhileIdle;
    var ok = await a.canScheduleExactNotifications() ?? false;
    if (!ok && ask && !_exactAsked) {
      _exactAsked = true;
      await a.requestExactAlarmsPermission();
      ok = await a.canScheduleExactNotifications() ?? false;
    }
    return ok
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  static Future<void> schedule(Task t) async {
    await cancel(t);
    if (!t.hasTime || t.done || t.when.isBefore(DateTime.now())) return;
    await _p.zonedSchedule(
      id: t.id,
      title: '⏰ ${t.title}',
      body: 'Saat ${hhmm(t.when)} için planladığın iş zamanı geldi.',
      scheduledDate: tz.TZDateTime.from(t.when, tz.local),
      notificationDetails: _details,
      androidScheduleMode: await _mode(),
    );
  }

  static Future<void> cancel(Task t) => _p.cancel(id: t.id);

  static const _kCalIds = 'calendar_notif_ids';

  /// Takvim hatırlatmaları artık tamamen Android tarafında kuruluyor
  /// (CalendarReminders.kt: takvim değişince, 30 dk'da bir ve açılışta).
  /// Burada yalnızca eski sürümün Flutter'da kurduğu hatırlatmaları temizleyip
  /// Android tarafına "şimdi senkronla" diyoruz.
  static Future<void> scheduleCalendar([List<Task>? _]) async {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getStringList(_kCalIds);
    if (old != null) {
      for (final id in old) {
        await _p.cancel(id: int.parse(id));
      }
      await prefs.remove(_kCalIds);
    }
    await updateLockCard();
  }

  static const _native = MethodChannel('asistan/calendar');

  /// Sabah 08:00 özeti artık Android tarafında (MorningReceiver.kt) hazırlanıyor:
  /// o anda havayı çeker, takvimi ve işleri okur. Burada yalnızca alarmın kurulu
  /// olduğundan emin oluyoruz ve eski (Dart'ta kurulan) sabah bildirimini siliyoruz.
  static Future<void> scheduleMorning([List<Task>? _]) async {
    await _p.cancel(id: _morningId);
    try {
      await _native.invokeMethod('scheduleMorning');
    } catch (_) {}
  }

  /// Kilit ekranı kartını yeniler (iş eklenince/silinince).
  static Future<void> updateLockCard() async {
    try {
      await _native.invokeMethod('updateLockCard');
    } catch (_) {}
  }

  static Future<bool> lockCardEnabled() async {
    try {
      return await _native.invokeMethod<bool>('lockCardEnabled') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setLockCard(bool enabled) async {
    try {
      await _native.invokeMethod('setLockCard', {'enabled': enabled});
    } catch (_) {}
  }

  /// Sabah bildirimini hemen gönderir (deneme için).
  static Future<void> showMorningNow() async {
    try {
      await _native.invokeMethod('showMorningNow');
    } catch (_) {}
  }
}
