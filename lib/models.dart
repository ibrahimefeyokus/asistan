import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Task {
  final int id;
  String title;
  DateTime when;
  bool hasTime;
  bool done;

  /// Takvimden geldiyse takvimin adı; elle eklenen işlerde null.
  final String? calendar;
  final String? location;
  final int? color;

  bool get fromCalendar => calendar != null;

  Task({
    required this.id,
    required this.title,
    required this.when,
    this.hasTime = false,
    this.done = false,
    this.calendar,
    this.location,
    this.color,
  });

  factory Task.create(String title, DateTime when, bool hasTime) => Task(
        id: DateTime.now().millisecondsSinceEpoch % 1000000000,
        title: title,
        when: when,
        hasTime: hasTime,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'when': when.toIso8601String(),
        'hasTime': hasTime,
        'done': done,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as int,
        title: j['title'] as String,
        when: DateTime.parse(j['when'] as String),
        hasTime: j['hasTime'] as bool? ?? false,
        done: j['done'] as bool? ?? false,
      );
}

class City {
  final String name;
  final String detail;
  final double lat;
  final double lon;
  const City(this.name, this.lat, this.lon, [this.detail = '']);

  static const istanbul = City('İstanbul', 41.0082, 28.9784, 'Türkiye');

  Map<String, dynamic> toJson() =>
      {'name': name, 'detail': detail, 'lat': lat, 'lon': lon};
  factory City.fromJson(Map<String, dynamic> j) => City(
      j['name'] as String,
      (j['lat'] as num).toDouble(),
      (j['lon'] as num).toDouble(),
      j['detail'] as String? ?? '');
}

/// Telefonda kalıcı kayıt.
class Store {
  static const _kTasks = 'tasks';
  static const _kCity = 'city';

  static Future<List<Task>> loadTasks() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kTasks);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List)
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
    // Dünden eski ve tamamlanmış görevleri temizle.
    final today = dayOnly(DateTime.now());
    list.removeWhere((t) => t.done && dayOnly(t.when).isBefore(today));
    return list;
  }

  static Future<void> saveTasks(List<Task> tasks) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kTasks, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  static Future<City> loadCity() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kCity);
    if (raw == null) return City.istanbul;
    return City.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<void> saveCity(City c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCity, jsonEncode(c.toJson()));
  }
}

// ---- Tarih yardımcıları ----

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const aylar = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
];
const gunler = [
  'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
];

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String longDate(DateTime d) => '${d.day} ${aylar[d.month - 1]} ${gunler[d.weekday - 1]}';

/// "bugün", "yarın" ya da "12 Kasım Perşembe"
String dayWord(DateTime d) {
  final today = dayOnly(DateTime.now());
  final diff = dayOnly(d).difference(today).inDays;
  if (diff == 0) return 'bugün';
  if (diff == 1) return 'yarın';
  if (diff == -1) return 'dün';
  return longDate(d);
}
