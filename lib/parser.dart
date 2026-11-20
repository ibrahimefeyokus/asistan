/// Türkçe sesli komutları çözümler.
/// Örnekler:
///   "yarın saat 9'da toplantı"        -> yarın 09:00 "Toplantı"
///   "akşam 8'de annemi ara"           -> bugün 20:00 "Annemi ara"
///   "20 dakika sonra ilacımı hatırlat" -> şimdi+20dk "İlacımı"
///   "cuma 14:30 dişçi"                -> cuma 14:30 "Dişçi"
///   "hava nasıl" / "bugün ne var"     -> komut
library;

enum VoiceCommand { weather, today, tomorrow, addTask, unknown }

class ParsedTask {
  final String title;
  final DateTime when;
  final bool hasTime;
  ParsedTask(this.title, this.when, this.hasTime);
}

String _lower(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

VoiceCommand detectCommand(String input) {
  final s = _lower(input);
  if (s.contains('hava')) return VoiceCommand.weather;
  final asksPlan = s.contains('ne var') ||
      s.contains('neler var') ||
      s.contains('planım') ||
      s.contains('programım') ||
      s.contains('ne yapacağım') ||
      s.contains('ne yapıcam') ||
      s.contains('işlerim');
  if (asksPlan) {
    return s.contains('yarın') ? VoiceCommand.tomorrow : VoiceCommand.today;
  }
  return VoiceCommand.addTask;
}

const _weekdays = <String, int>{
  // Uzun olanlar önce: "cumartesi" "cuma"yı, "pazartesi" "pazar"ı içerir.
  'cumartesi': 6,
  'pazartesi': 1,
  'çarşamba': 3,
  'perşembe': 4,
  'cuma': 5,
  'salı': 2,
  'pazar': 7,
};

const _numberWords = <String, int>{
  'on iki': 12, 'on bir': 11, 'bir': 1, 'iki': 2, 'üç': 3, 'dört': 4,
  'beş': 5, 'altı': 6, 'yedi': 7, 'sekiz': 8, 'dokuz': 9, 'on': 10,
};

ParsedTask? parseTask(String input, DateTime now) {
  var s = ' ${_lower(input)} '.replaceAll(RegExp(r'[,!?]'), ' ');

  String cut(RegExp re) {
    final m = re.firstMatch(s);
    if (m == null) return '';
    s = s.replaceRange(m.start, m.end, ' ');
    return m.group(0)!;
  }

  // 1) Göreli zaman: "20 dakika sonra", "2 saat sonra", "yarım saat sonra"
  DateTime? relative;
  final relMin = RegExp(r'\s(\d+)\s*dakika\s+sonra\S*').firstMatch(s);
  final relHour = RegExp(r'\s(\d+)\s*saat\s+sonra\S*').firstMatch(s);
  if (relMin != null) {
    relative = now.add(Duration(minutes: int.parse(relMin.group(1)!)));
    cut(RegExp(r'\s(\d+)\s*dakika\s+sonra\S*'));
  } else if (relHour != null) {
    relative = now.add(Duration(hours: int.parse(relHour.group(1)!)));
    cut(RegExp(r'\s(\d+)\s*saat\s+sonra\S*'));
  } else if (s.contains('yarım saat sonra')) {
    relative = now.add(const Duration(minutes: 30));
    cut(RegExp(r'yarım saat sonra\S*'));
  }

  // 2) Gün
  int dayOffset = 0;
  bool explicitDay = false;
  for (final e in {'öbür gün': 2, 'ertesi gün': 2, 'yarın': 1, 'bugün': 0}.entries) {
    if (cut(RegExp('\\s${e.key}\\S*')).isNotEmpty) {
      dayOffset = e.value;
      explicitDay = true;
      break;
    }
  }
  if (!explicitDay) {
    for (final e in _weekdays.entries) {
      if (cut(RegExp('\\s${e.key}\\S*(\\s+günü\\S*)?')).isNotEmpty) {
        dayOffset = (e.value - now.weekday) % 7;
        explicitDay = true;
        break;
      }
    }
  }

  // 3) Günün bölümü
  final pm = cut(RegExp(r'\s(akşam|öğleden sonra|öğlenden sonra)\S*')).isNotEmpty;
  final night = cut(RegExp(r'\sgece\S*')).isNotEmpty;
  final morning = cut(RegExp(r'\ssabah\S*')).isNotEmpty;
  final noon = cut(RegExp(r'\söğle(n|yin)?\S*')).isNotEmpty;

  // 4) Saat
  int? hour;
  int minute = 0;
  RegExpMatch? m;
  if ((m = RegExp(r'\s(?:saat\s+)?(\d{1,2})[:.](\d{2})\S*').firstMatch(s)) != null) {
    hour = int.parse(m!.group(1)!);
    minute = int.parse(m.group(2)!);
    s = s.replaceRange(m.start, m.end, ' ');
  } else if ((m = _findHour(s)) != null) {
    // "saat 9", "9'da", "3 buçukta"
    final text = m!.group(0)!;
    hour = int.parse(m.group(1)!);
    if (text.contains('buçuk')) minute = 30;
    s = s.replaceRange(m.start, m.end, ' ');
  } else if ((m = RegExp(r'\ssaat\s+(on iki|on bir|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on)\S*(\s+buçuk\S*)?')
          .firstMatch(s)) !=
      null) {
    hour = _numberWords[m!.group(1)!];
    if (m.group(2) != null) minute = 30;
    s = s.replaceRange(m.start, m.end, ' ');
  }
  // "buçukta" tek başına kalmışsa
  if (s.contains('buçuk')) {
    minute = 30;
    cut(RegExp(r'\sbuçuk\S*'));
  }

  if (hour == null && noon) hour = 12;
  if (hour != null) {
    if (hour > 23 || minute > 59) {
      hour = null;
    } else if (pm && hour < 12) {
      hour += 12;
    } else if (night && hour >= 7 && hour < 12) {
      hour += 12;
    } else if (!morning && !pm && !night && hour >= 1 && hour <= 6) {
      // "saat 3'te" denince genelde öğleden sonrası kastedilir.
      hour += 12;
    }
  }

  // 5) Dolgu kelimelerini at
  for (final w in [
    r'hatırlat\S*',
    r'bana',
    r'lütfen',
    r'ekle\S*',
    r'not\s+al\S*',
    r'unutma\S*',
    r'saat\S*',
    r'günü\S*',
    r'de',
    r'da',
    r'te',
    r'ta',
  ]) {
    s = s.replaceAll(RegExp('(?<=\\s)$w(?=\\s)'), ' ');
  }
  var title = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  title = title.replaceAll(RegExp(r"^[\x27’.\-]+|[\x27’.\-]+$"), '').trim();
  if (title.isEmpty) return null;
  title = _capitalize(title);

  // 6) Tarihi kur
  if (relative != null) return ParsedTask(title, relative, true);
  var when = DateTime(now.year, now.month, now.day + dayOffset, hour ?? 9, minute);
  if (hour != null && !explicitDay && when.isBefore(now)) {
    when = when.add(const Duration(days: 1));
  }
  return ParsedTask(title, when, hour != null);
}

/// "saat" ile başlayan ya da ek almış ("9'da", "3te") ilk sayıyı bulur.
/// Çıplak sayılar ("2 ekmek al") saat sayılmaz.
RegExpMatch? _findHour(String s) {
  final re = RegExp(
      r'\s(?:saat\s+)?(\d{1,2})(?:\s+buçuk)?(?:[\x27’]?(?:de|da|te|ta|e|a|ye|ya))?(?=\s)');
  for (final m in re.allMatches(s)) {
    final text = m.group(0)!.trim();
    final hasSaat = text.startsWith('saat');
    final hasSuffix =
        RegExp(r'[\d k][\x27’]?(de|da|te|ta|e|a|ye|ya)$').hasMatch(text) ||
            text.contains('buçuk');
    if (hasSaat || hasSuffix) return m;
  }
  return null;
}

String _capitalize(String s) {
  final first = s[0];
  final up = first == 'i' ? 'İ' : (first == 'ı' ? 'I' : first.toUpperCase());
  return up + s.substring(1);
}
