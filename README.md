# Asistan

Türkçe sesli komutlarla çalışan kişisel asistan uygulaması. Günün işlerini planlar, zamanı gelince hatırlatır; hava durumu, takvim ve okunmamış mailleri tek bir özette sunar.

## Özellikler

- **Sesli komut:** Mikrofona dokunup Türkçe konuşarak iş ekleme ve soru sorma; yanıtlar sesli okunur
- **Doğal dilde tarih ve saat:** "Yarın saat 9'da toplantı", "yarım saat sonra hatırlat", "akşam altıda spor" gibi ifadelerden tarih ve saat çıkarılır
- **Hatırlatmalar:** Planlanan işler için zamanında bildirim; telefon yeniden başlasa da hatırlatmalar korunur
- **Takvim:** Telefondaki takvim etkinlikleri (Google Takvim dahil) okunur ve hatırlatılır
- **Hava durumu:** Seçilen şehir için anlık hava, sıcaklık ve yağış ihtimali (Open-Meteo)
- **Mail özeti:** Outlook bildirimlerinden okunmamış odaklanmış mail sayısı
- **Günlük özetler:** 08:00, 12:00 ve 20:00'de hava, sıradaki işler ve mailler
- **Kilit ekranı kartı:** Önemli bilgiler kilit ekranında görünür

## Kullanılan Teknolojiler

- **Flutter / Dart:** arayüz, komut ayrıştırıcı ve uygulama mantığı
- **Kotlin (Android):** takvim okuma, NotificationListenerService ile mail bildirimleri, zamanlanmış işler (JobScheduler, AlarmManager), kilit ekranı kartı
- **speech_to_text, flutter_tts:** konuşma tanıma ve sesli yanıt
- **flutter_local_notifications:** hatırlatma bildirimleri
- **Open-Meteo API:** hava durumu ve şehir arama (API anahtarı gerektirmez)

## Proje Yapısı

```
lib/
  main.dart        Ana ekran ve sesli komut akışı
  parser.dart      Türkçe tarih/saat ifadelerini ayrıştırma
  notifier.dart    Hatırlatma bildirimleri
  calendar.dart    Telefon takvimi ile bağlantı
  weather.dart     Open-Meteo hava durumu
  models.dart      Görev modeli ve kayıt
android/app/src/main/kotlin/com/ibrahim/jarvis_asistan/
  MorningReceiver.kt     Günlük özet bildirimleri
  MailListener.kt        Outlook bildirimlerini okuma
  CalendarReminders.kt   Takvim hatırlatmaları
  CalendarWatchJob.kt    Takvim değişikliklerini izleme
  LockCard.kt            Kilit ekranı kartı
```

## Çalıştırma

```bash
flutter pub get
flutter run
```

Android cihaz gerekir. Mail özeti için uygulamaya bildirim erişimi, sesli komut için mikrofon izni verilmelidir.
