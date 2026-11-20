import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'calendar.dart';
import 'models.dart';
import 'notifier.dart';
import 'parser.dart';
import 'weather.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.init();
  runApp(const AsistanApp());
}

class AsistanApp extends StatelessWidget {
  const AsistanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asistan',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _stt = SpeechToText();
  final _tts = FlutterTts();

  /// Elle eklenen işler (telefonda kayıtlı).
  List<Task> _tasks = [];

  /// Takvimden gelen etkinlikler (her açılışta yeniden okunur).
  List<Task> _events = [];
  bool _calendarAllowed = false;

  /// Outlook mail bildirimlerine erişim açık mı; açıksa okunmamış odaklanmış mail sayısı.
  bool _mailEnabled = true;
  int _mailCount = 0;

  /// Kilit ekranı kartı açık mı
  bool _lockCard = true;

  List<Task> get _all => [..._tasks, ..._events];
  City _city = City.istanbul;
  Weather? _weather;
  String? _weatherError;
  bool _loadingWeather = true;

  bool _sttReady = false;
  String? _localeId;
  bool _listening = false;
  String _partial = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initVoice();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Uygulamaya her dönüldüğünde takvimi tazele.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_calendarAllowed) _syncCalendar();
      _refreshMail();
    }
  }

  Future<void> _refreshMail() async {
    try {
      final enabled = await CalendarService.mailAccessEnabled();
      final count = enabled ? await CalendarService.mailCount() : 0;
      if (mounted) {
        setState(() {
          _mailEnabled = enabled;
          _mailCount = count;
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    final tasks = await Store.loadTasks();
    final city = await Store.loadCity();
    setState(() {
      _tasks = tasks;
      _city = city;
    });
    _refreshWeather();
    await Notifier.askPermission();
    _calendarAllowed = await CalendarService.requestPermission();
    await _syncCalendar();
    await _refreshMail();
    final lock = await Notifier.lockCardEnabled();
    if (mounted) setState(() => _lockCard = lock);
    await Notifier.updateLockCard();
  }

  /// Önümüzdeki 7 günün takvim etkinliklerini çeker ve hatırlatmalarını kurar.
  Future<void> _syncCalendar() async {
    if (_calendarAllowed) {
      try {
        final from = dayOnly(DateTime.now());
        final events = await CalendarService.events(
            from, from.add(const Duration(days: 8)));
        if (mounted) setState(() => _events = events);
        await Notifier.scheduleCalendar(events);
      } catch (_) {
        // Takvim okunamazsa sessizce devam et.
      }
    }
    await Notifier.scheduleMorning(_all);
  }

  Future<void> _refreshAll() async {
    await Future.wait([_refreshWeather(), _syncCalendar()]);
  }

  Future<void> _initVoice() async {
    await _tts.setLanguage('tr-TR');
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<bool> _ensureStt() async {
    if (_sttReady) return true;
    _sttReady = await _stt.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (_sttReady) {
      final locales = await _stt.locales();
      final tr = locales.where((l) => l.localeId.toLowerCase().startsWith('tr'));
      _localeId = tr.isNotEmpty ? tr.first.localeId : null;
    }
    return _sttReady;
  }

  Future<void> _refreshWeather() async {
    setState(() {
      _loadingWeather = true;
      _weatherError = null;
    });
    try {
      final w = await WeatherService.fetch(_city);
      if (mounted) setState(() => _weather = w);
    } catch (_) {
      if (mounted) {
        setState(() => _weatherError = 'Hava durumu alınamadı. İnternet bağlantını kontrol et.');
      }
    } finally {
      if (mounted) setState(() => _loadingWeather = false);
    }
  }

  // ---------- Görevler ----------

  Future<void> _persist() async {
    await Store.saveTasks(_tasks);
    await Notifier.scheduleMorning(_all);
    await Notifier.updateLockCard();
  }

  Future<void> _addTask(Task t) async {
    setState(() => _tasks.add(t));
    await Notifier.schedule(t);
    await _persist();
  }

  Future<void> _toggle(Task t) async {
    setState(() => t.done = !t.done);
    if (t.done) {
      await Notifier.cancel(t);
    } else {
      await Notifier.schedule(t);
    }
    await _persist();
  }

  Future<void> _delete(Task t) async {
    setState(() => _tasks.remove(t));
    await Notifier.cancel(t);
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"${t.title}" silindi'),
      action: SnackBarAction(label: 'Geri al', onPressed: () => _addTask(t)),
    ));
  }

  List<Task> _tasksOn(DateTime day) =>
      _all.where((t) => sameDay(t.when, day)).toList()
        ..sort((a, b) {
          if (a.done != b.done) return a.done ? 1 : -1;
          if (a.hasTime != b.hasTime) return a.hasTime ? -1 : 1;
          return a.when.compareTo(b.when);
        });

  // ---------- Ses ----------

  Future<void> _say(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onMic() async {
    if (_listening) {
      await _stt.stop();
      return;
    }
    await _tts.stop();
    if (!await _ensureStt()) {
      _toast('Konuşma tanıma kullanılamıyor. Mikrofon iznini kontrol et.');
      return;
    }
    setState(() {
      _listening = true;
      _partial = '';
    });
    await _stt.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: _localeId,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onResult(SpeechRecognitionResult r) async {
    setState(() => _partial = r.recognizedWords);
    if (!r.finalResult) return;
    setState(() => _listening = false);
    final text = r.recognizedWords.trim();
    if (text.isEmpty) return;
    await _handleCommand(text);
  }

  Future<void> _handleCommand(String text) async {
    switch (detectCommand(text)) {
      case VoiceCommand.weather:
        await _say(_weatherSentence());
      case VoiceCommand.today:
        await _say(_daySentence(DateTime.now()));
      case VoiceCommand.tomorrow:
        await _say(_daySentence(DateTime.now().add(const Duration(days: 1))));
      case VoiceCommand.addTask:
      case VoiceCommand.unknown:
        final p = parseTask(text, DateTime.now());
        if (p == null) {
          _toast('Anlayamadım: "$text"');
          await _say('Kusura bakma, anlayamadım.');
          return;
        }
        await _addTask(Task.create(p.title, p.when, p.hasTime));
        final when = p.hasTime
            ? '${dayWord(p.when)} saat ${hhmm(p.when)}'
            : dayWord(p.when);
        _toast('Eklendi: ${p.title} • $when');
        await _say(p.hasTime
            ? 'Tamam, $when için ${p.title} hatırlatacağım.'
            : 'Tamam, ${p.title} $when listene eklendi.');
    }
  }

  String _daySentence(DateTime day) {
    final word = dayWord(day);
    final list = _tasksOn(day).where((t) => !t.done).toList();
    if (list.isEmpty) return '${_cap(word)} için planlanmış bir işin yok.';
    final items = list
        .map((t) => t.hasTime ? 'saat ${hhmm(t.when)} ${t.title}' : t.title)
        .join(', ');
    return '${_cap(word)} ${list.length} işin var: $items.';
  }

  String _weatherSentence() {
    final w = _weather;
    if (w == null) return 'Hava durumu bilgisine şu an ulaşamıyorum.';
    final today = w.days.first;
    var s = '${_city.name} için şu an ${w.temp.round()} derece, '
        '${weatherText(w.code).toLowerCase()}. '
        'Bugün en yüksek ${today.max.round()}, en düşük ${today.min.round()} derece.';
    if ((today.rainChance ?? 0) >= 30) {
      s += ' Yağış ihtimali yüzde ${today.rainChance}, şemsiyeni almayı unutma.';
    }
    return s;
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ---------- Elle ekleme ----------

  Future<void> _openAddSheet([Task? editing]) async {
    final ctrl = TextEditingController(text: editing?.title ?? '');
    var day = dayOnly(editing?.when ?? DateTime.now());
    TimeOfDay? time = editing != null && editing.hasTime
        ? TimeOfDay.fromDateTime(editing.when)
        : null;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final today = dayOnly(DateTime.now());
        final tomorrow = today.add(const Duration(days: 1));
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(editing == null ? 'Yeni iş' : 'İşi düzenle',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'Ne yapacaksın?', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                  label: const Text('Bugün'),
                  selected: sameDay(day, today),
                  onSelected: (_) => setS(() => day = today),
                ),
                ChoiceChip(
                  label: const Text('Yarın'),
                  selected: sameDay(day, tomorrow),
                  onSelected: (_) => setS(() => day = tomorrow),
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_today, size: 18),
                  label: Text(!sameDay(day, today) && !sameDay(day, tomorrow)
                      ? '${day.day} ${aylar[day.month - 1]}'
                      : 'Tarih seç'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: day,
                      firstDate: today,
                      lastDate: today.add(const Duration(days: 365)),
                    );
                    if (d != null) setS(() => day = d);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.alarm, size: 18),
                  label: Text(time == null
                      ? 'Saat ekle'
                      : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}'),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: time ?? TimeOfDay.now(),
                    );
                    if (t != null) setS(() => time = t);
                  },
                ),
                if (time != null)
                  ActionChip(
                    label: const Text('Saati kaldır'),
                    onPressed: () => setS(() => time = null),
                  ),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Kaydet'),
                ),
              ),
            ],
          ),
        );
      }),
    );

    final title = ctrl.text.trim();
    if (saved != true || title.isEmpty) return;
    final when = DateTime(day.year, day.month, day.day, time?.hour ?? 9,
        time?.minute ?? 0);
    if (editing != null) {
      setState(() {
        editing
          ..title = title
          ..when = when
          ..hasTime = time != null;
      });
      await Notifier.schedule(editing);
      await _persist();
    } else {
      await _addTask(Task.create(title, when, time != null));
    }
  }

  // ---------- Şehir ----------

  Future<void> _pickCity() async {
    final ctrl = TextEditingController();
    List<City> results = [];
    bool searching = false;
    final picked = await showDialog<City>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> search() async {
          if (ctrl.text.trim().isEmpty) return;
          setS(() => searching = true);
          final r = await WeatherService.searchCity(ctrl.text.trim());
          setS(() {
            results = r;
            searching = false;
          });
        }

        return AlertDialog(
          title: const Text('Şehir seç'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                  hintText: 'Örn. Trabzon',
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.search), onPressed: search),
                ),
              ),
              const SizedBox(height: 8),
              if (searching) const LinearProgressIndicator(),
              ...results.map((c) => ListTile(
                    dense: true,
                    title: Text(c.name),
                    subtitle: Text(c.detail),
                    onTap: () => Navigator.pop(ctx, c),
                  )),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          ],
        );
      }),
    );
    if (picked == null) return;
    setState(() => _city = picked);
    await Store.saveCity(picked);
    await _refreshWeather();
  }

  // ---------- Arayüz ----------

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 6) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dayOnly(now);
    final tomorrow = today.add(const Duration(days: 1));
    final overdue = _tasks
        .where((t) => !t.done && dayOnly(t.when).isBefore(today))
        .toList()
      ..sort((a, b) => a.when.compareTo(b.when));
    final later = _all
        .where((t) => dayOnly(t.when).isAfter(tomorrow))
        .toList()
      ..sort((a, b) => a.when.compareTo(b.when));
    final todayTasks = _tasksOn(today);
    final tomorrowTasks = _tasksOn(tomorrow);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_greeting, İbrahim',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(longDate(now),
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                GestureDetector(
                  // Uzun basınca o saate uygun özet bildirimini hemen gönderir (deneme için).
                  onLongPress: () async {
                    await Notifier.showMorningNow();
                    _toast('Özet bildirimi gönderildi');
                  },
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.record_voice_over),
                    onPressed: () =>
                        _say('${_daySentence(now)} ${_weatherSentence()}'),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              _weatherCard(cs),
              if (!_calendarAllowed)
                Card(
                  elevation: 0,
                  color: cs.secondaryContainer,
                  margin: const EdgeInsets.only(top: 12),
                  child: ListTile(
                    leading: const Icon(Icons.event),
                    title: const Text('Google Takvim etkinliklerini göster'),
                    subtitle: const Text('Takvim izni vermek için dokun'),
                    onTap: () async {
                      _calendarAllowed =
                          await CalendarService.requestPermission();
                      await _syncCalendar();
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              Card(
                elevation: 0,
                color: _mailEnabled
                    ? cs.surfaceContainerHighest
                    : cs.secondaryContainer,
                margin: const EdgeInsets.only(top: 12),
                child: ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(_mailEnabled
                      ? (_mailCount == 0
                          ? 'Okunmamış odaklanmış mail yok'
                          : '$_mailCount okunmamış odaklanmış mail')
                      : 'Outlook maillerini sabah özetine ekle'),
                  subtitle: Text(_mailEnabled
                      ? 'Outlook • 08:00, 12:00 ve 20:00 özetlerinde'
                      : 'Dokun → "Asistan: Outlook mailleri"ni aç'),
                  onTap: _mailEnabled
                      ? null
                      : () => CalendarService.openMailAccessSettings(),
                ),
              ),
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                margin: const EdgeInsets.only(top: 12),
                child: SwitchListTile(
                  secondary: const Icon(Icons.lock_clock_outlined),
                  title: const Text('Kilit ekranı kartı'),
                  subtitle: const Text('Hava, sıradaki işler ve mailler kilit ekranında'),
                  value: _lockCard,
                  onChanged: (v) async {
                    setState(() => _lockCard = v);
                    await Notifier.setLockCard(v);
                  },
                ),
              ),
              const SizedBox(height: 20),
              if (overdue.isNotEmpty) ...[
                _sectionTitle('Gecikmiş', color: cs.error),
                ...overdue.map((t) => _taskTile(t, showDate: true)),
                const SizedBox(height: 12),
              ],
              _sectionTitle('Bugün'),
              if (todayTasks.isEmpty)
                _empty('Bugün için bir işin yok. Mikrofona dokunup söyleyebilirsin.')
              else
                ...todayTasks.map(_taskTile),
              const SizedBox(height: 12),
              _sectionTitle('Yarın'),
              if (tomorrowTasks.isEmpty)
                _empty('Yarın için henüz plan yok.')
              else
                ...tomorrowTasks.map(_taskTile),
              if (later.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionTitle('Daha sonra'),
                ...later.map((t) => _taskTile(t, showDate: true)),
              ],
            ],
          ),
        ),
      ),
      bottomSheet: _listening ? _listeningBar(cs) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FloatingActionButton(
            heroTag: 'add',
            tooltip: 'Elle ekle',
            onPressed: () => _openAddSheet(),
            child: const Icon(Icons.add),
          ),
          const SizedBox(width: 16),
          FloatingActionButton.large(
            heroTag: 'mic',
            tooltip: 'Sesle söyle',
            backgroundColor: _listening ? cs.error : cs.primary,
            foregroundColor: _listening ? cs.onError : cs.onPrimary,
            onPressed: _onMic,
            child: Icon(_listening ? Icons.stop : Icons.mic, size: 36),
          ),
        ],
      ),
    );
  }

  Widget _listeningBar(ColorScheme cs) => Container(
        width: double.infinity,
        color: cs.primaryContainer,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Dinliyorum...',
              style: TextStyle(
                  color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            _partial.isEmpty
                ? 'Örn: "Yarın saat 9\'da toplantı" ya da "Hava nasıl?"'
                : _partial,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 16),
          ),
        ]),
      );

  Widget _weatherCard(ColorScheme cs) {
    final w = _weather;
    return Card(
      elevation: 0,
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _pickCity,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.location_on, size: 18, color: cs.onPrimaryContainer),
                const SizedBox(width: 4),
                Text(_city.name,
                    style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600)),
                Icon(Icons.arrow_drop_down, color: cs.onPrimaryContainer),
              ]),
            ),
            const SizedBox(height: 8),
            if (_loadingWeather && w == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (w == null)
              Text(_weatherError ?? '',
                  style: TextStyle(color: cs.onPrimaryContainer))
            else ...[
              Row(children: [
                Text(weatherEmoji(w.code), style: const TextStyle(fontSize: 52)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${w.temp.round()}°',
                          style: TextStyle(
                              fontSize: 44,
                              height: 1,
                              fontWeight: FontWeight.w300,
                              color: cs.onPrimaryContainer)),
                      Text(weatherText(w.code),
                          style: TextStyle(
                              fontSize: 16, color: cs.onPrimaryContainer)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _wInfo(cs, 'Hissedilen ${w.feels.round()}°'),
                    _wInfo(cs,
                        '↑${w.days.first.max.round()}°  ↓${w.days.first.min.round()}°'),
                    if (w.days.first.rainChance != null)
                      _wInfo(cs, '☔ %${w.days.first.rainChance}'),
                    _wInfo(cs, '💨 ${w.wind.round()} km/s'),
                  ],
                ),
              ]),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: w.days.skip(1).take(3).map((d) {
                  return Column(children: [
                    Text(gunler[d.date.weekday - 1].substring(0, 3),
                        style: TextStyle(color: cs.onPrimaryContainer)),
                    Text(weatherEmoji(d.code),
                        style: const TextStyle(fontSize: 26)),
                    Text('${d.max.round()}° / ${d.min.round()}°',
                        style: TextStyle(
                            fontSize: 13, color: cs.onPrimaryContainer)),
                  ]);
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _wInfo(ColorScheme cs, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(t,
            style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer)),
      );

  Widget _sectionTitle(String t, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600, color: color)),
      );

  Widget _empty(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(t,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _taskTile(Task t, {bool showDate = false}) {
    final cs = Theme.of(context).colorScheme;
    final sub = [
      if (showDate) dayWord(t.when),
      if (t.hasTime) hhmm(t.when) else if (t.fromCalendar) 'Tüm gün',
      if (t.location != null && t.location!.isNotEmpty) t.location!,
    ].join(' • ');

    if (t.fromCalendar) {
      final color = t.color != null ? Color(t.color!) : cs.primary;
      final past = t.hasTime && t.when.isBefore(DateTime.now());
      return Card(
        elevation: 0,
        color: cs.surfaceContainerHighest.withValues(alpha: past ? 0.4 : 1),
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: ListTile(
          leading: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(Icons.event, color: color),
          ),
          title: Text(t.title,
              style: TextStyle(color: past ? cs.onSurfaceVariant : null)),
          subtitle: Text(sub.isEmpty ? t.calendar! : '$sub\n${t.calendar}'),
          isThreeLine: sub.isNotEmpty,
          trailing: t.hasTime && !past
              ? Icon(Icons.notifications_active, size: 18, color: cs.primary)
              : null,
        ),
      );
    }

    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => _delete(t),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerHighest.withValues(alpha: t.done ? 0.4 : 1),
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: ListTile(
          onTap: () => _openAddSheet(t),
          leading: Checkbox(value: t.done, onChanged: (_) => _toggle(t)),
          title: Text(
            t.title,
            style: TextStyle(
              decoration: t.done ? TextDecoration.lineThrough : null,
              color: t.done ? cs.onSurfaceVariant : null,
            ),
          ),
          subtitle: sub.isEmpty ? null : Text(sub),
          trailing: t.hasTime && !t.done
              ? Icon(Icons.notifications_active, size: 18, color: cs.primary)
              : null,
        ),
      ),
    );
  }
}
