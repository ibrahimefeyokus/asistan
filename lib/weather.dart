import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Open-Meteo: ücretsiz, API anahtarı gerektirmez.
class DayForecast {
  final DateTime date;
  final int code;
  final double max;
  final double min;
  final int? rainChance;
  DayForecast(this.date, this.code, this.max, this.min, this.rainChance);
}

class Weather {
  final double temp;
  final double feels;
  final double wind;
  final int code;
  final List<DayForecast> days;
  Weather(this.temp, this.feels, this.wind, this.code, this.days);
}

class WeatherService {
  static Future<Weather> fetch(City c) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${c.lat}',
      'longitude': '${c.lon}',
      'current': 'temperature_2m,apparent_temperature,weather_code,wind_speed_10m',
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'timezone': 'auto',
      'forecast_days': '4',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Hava durumu alınamadı (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cur = j['current'] as Map<String, dynamic>;
    final d = j['daily'] as Map<String, dynamic>;
    final times = (d['time'] as List).cast<String>();
    final days = <DayForecast>[];
    for (var i = 0; i < times.length; i++) {
      final rain = (d['precipitation_probability_max'] as List)[i];
      days.add(DayForecast(
        DateTime.parse(times[i]),
        (d['weather_code'] as List)[i] as int,
        ((d['temperature_2m_max'] as List)[i] as num).toDouble(),
        ((d['temperature_2m_min'] as List)[i] as num).toDouble(),
        rain == null ? null : (rain as num).round(),
      ));
    }
    return Weather(
      (cur['temperature_2m'] as num).toDouble(),
      (cur['apparent_temperature'] as num).toDouble(),
      (cur['wind_speed_10m'] as num).toDouble(),
      cur['weather_code'] as int,
      days,
    );
  }

  static Future<List<City>> searchCity(String q) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search',
        {'name': q, 'count': '6', 'language': 'tr', 'format': 'json'});
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (j['results'] as List?) ?? [];
    return results.map((r) {
      final m = r as Map<String, dynamic>;
      final detail = [m['admin1'], m['country']]
          .where((e) => e != null && '$e'.isNotEmpty)
          .join(', ');
      return City(m['name'] as String, (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(), detail);
    }).toList();
  }
}

/// WMO hava kodu → Türkçe açıklama
String weatherText(int code) {
  if (code == 0) return 'Açık';
  if (code == 1) return 'Az bulutlu';
  if (code == 2) return 'Parçalı bulutlu';
  if (code == 3) return 'Kapalı';
  if (code == 45 || code == 48) return 'Sisli';
  if (code >= 51 && code <= 57) return 'Çisenti';
  if (code == 61) return 'Hafif yağmurlu';
  if (code == 63) return 'Yağmurlu';
  if (code == 65) return 'Kuvvetli yağmurlu';
  if (code == 66 || code == 67) return 'Dondurucu yağmur';
  if (code == 71) return 'Hafif kar yağışlı';
  if (code == 73 || code == 75 || code == 77) return 'Kar yağışlı';
  if (code >= 80 && code <= 82) return 'Sağanak yağışlı';
  if (code == 85 || code == 86) return 'Kar sağanağı';
  if (code == 95) return 'Gök gürültülü fırtına';
  if (code == 96 || code == 99) return 'Dolu ile fırtına';
  return 'Bilinmiyor';
}

String weatherEmoji(int code) {
  if (code == 0) return '☀️';
  if (code == 1) return '🌤️';
  if (code == 2) return '⛅';
  if (code == 3) return '☁️';
  if (code == 45 || code == 48) return '🌫️';
  if (code >= 51 && code <= 57) return '🌦️';
  if (code >= 61 && code <= 67) return '🌧️';
  if (code >= 71 && code <= 77) return '❄️';
  if (code >= 80 && code <= 82) return '🌦️';
  if (code == 85 || code == 86) return '🌨️';
  if (code >= 95) return '⛈️';
  return '🌡️';
}
