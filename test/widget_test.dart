import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_asistan/parser.dart';

void main() {
  // Cumartesi 7 Kasım 2026, 16:50
  final now = DateTime(2026, 11, 7, 16, 50);

  void check(String input, String title, DateTime when, {bool hasTime = true}) {
    final p = parseTask(input, now);
    expect(p, isNotNull, reason: input);
    expect(p!.title, title, reason: input);
    expect(p.when, when, reason: input);
    expect(p.hasTime, hasTime, reason: input);
  }

  test('yarın saat', () => check("yarın saat 9'da toplantı", 'Toplantı', DateTime(2026, 11, 8, 9)));
  test('akşam', () => check("akşam 8'de annemi ara", 'Annemi ara', DateTime(2026, 11, 7, 20)));
  test('hh:mm', () => check('pazartesi 14:30 dişçi randevusu', 'Dişçi randevusu', DateTime(2026, 11, 9, 14, 30)));
  test('saat 3 öğleden sonra kabul', () => check("saat 3'te spor salonu", 'Spor salonu', DateTime(2026, 11, 8, 15)));
  test('buçuk', () => check('yarın saat 10 buçukta kuaför', 'Kuaför', DateTime(2026, 11, 8, 10, 30)));
  test('göreli', () => check('20 dakika sonra ilacımı iç', 'İlacımı iç', now.add(const Duration(minutes: 20))));
  test('saatsiz', () => check('ekmek al', 'Ekmek al', DateTime(2026, 11, 7, 9), hasTime: false));
  test('çıplak sayı saat değil', () => check('2 ekmek al', '2 ekmek al', DateTime(2026, 11, 7, 9), hasTime: false));
  test('hatırlat dolgusu', () => check("bana yarın sabah 7'de koşuyu hatırlat", 'Koşuyu', DateTime(2026, 11, 8, 7)));
  test('cumartesi cuma değil', () => check("cumartesi günü saat 11'de pazar alışverişi", 'Pazar alışverişi', DateTime(2026, 11, 7, 11)));

  test('komutlar', () {
    expect(detectCommand('Hava nasıl'), VoiceCommand.weather);
    expect(detectCommand('bugün ne var'), VoiceCommand.today);
    expect(detectCommand('yarın neler var'), VoiceCommand.tomorrow);
    expect(detectCommand('yarın saat 9 toplantı'), VoiceCommand.addTask);
  });
}
