package com.ibrahim.jarvis_asistan

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CalendarContract
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToInt

/**
 * Günde üç kez (08:00, 12:00, 20:00) çalışır — uygulama kapalı olsa bile:
 * hava durumunu çeker, takvimi, elle eklenen işleri ve Outlook maillerini okur,
 * tek bir özet bildirimi gönderir.
 */
class MorningReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON" -> {
                Morning.schedule(app)
                val p = goAsync()
                Thread {
                    try { LockCard.update(app) } catch (_: Exception) {} finally { p.finish() }
                }.start()
                return
            }
        }
        val slot = intent.getIntExtra(Morning.EXTRA_SLOT, Morning.slotFor(Calendar.getInstance()))
        // Önce bir sonraki özeti kur, sonra bu özeti hazırla.
        Morning.schedule(app)
        val pending = goAsync()
        Thread {
            try {
                Morning.showNow(app, slot)
                LockCard.update(app)
            } catch (_: Exception) {
            } finally {
                pending.finish()
            }
        }.start()
    }
}

object Morning {
    /** Özet saatleri. */
    val HOURS = intArrayOf(8, 12, 20)

    const val EXTRA_SLOT = "slot"
    private const val CHANNEL = "gunluk_ozet"
    private const val OLD_CHANNEL = "sabah_ozeti"
    private const val NOTIF_ID = 8008
    private const val ACTION = "com.ibrahim.jarvis_asistan.MORNING"

    private val aylar = arrayOf(
        "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
        "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"
    )
    private val gunler = arrayOf(
        "Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"
    )
    val tr = Locale("tr")

    /** Elle tetiklendiğinde hangi özetin gösterileceği: saate göre en yakın geçmiş dilim. */
    fun slotFor(now: Calendar): Int {
        val h = now.get(Calendar.HOUR_OF_DAY)
        return when {
            h >= 20 -> 20
            h >= 12 -> 12
            else -> 8
        }
    }

    /** Bir sonraki özet saati (08, 12 ya da 20) için alarm kurar. */
    fun schedule(context: Context) {
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val nowMs = System.currentTimeMillis()
        var next: Calendar? = null
        var slot = HOURS[0]
        for (dayAdd in 0..1) {
            for (h in HOURS) {
                val c = Calendar.getInstance().apply {
                    add(Calendar.DAY_OF_YEAR, dayAdd)
                    set(Calendar.HOUR_OF_DAY, h)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                if (c.timeInMillis > nowMs) {
                    next = c
                    slot = h
                    break
                }
            }
            if (next != null) break
        }
        val at = next ?: return
        val pi = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, MorningReceiver::class.java).setAction(ACTION).putExtra(EXTRA_SLOT, slot),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val exactOk = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()
        if (exactOk) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.timeInMillis, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.timeInMillis, pi)
        }
    }

    /** Özeti hemen hazırlayıp bildirim olarak gösterir (arka plan iş parçacığında çağrılmalı). */
    fun showNow(context: Context, slot: Int = slotFor(Calendar.getInstance())) {
        val now = Calendar.getInstance()
        val tomorrow = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        // --- Şehir ve hava ---
        var cityName = "İstanbul"
        var lat = 41.0082
        var lon = 28.9784
        prefs.getString("flutter.city", null)?.let {
            try {
                val c = JSONObject(it)
                cityName = c.getString("name")
                lat = c.getDouble("lat")
                lon = c.getDouble("lon")
            } catch (_: Exception) {}
        }
        val w = try { fetchWeather(lat, lon) } catch (_: Exception) { null }

        // --- İşler ---
        // Öğlen ve akşam özetinde bugünün yalnızca kalan işleri gösterilir.
        val todayAfter = if (slot == 8) null else now.timeInMillis
        val today = items(context, prefs, now, todayAfter)
        val tomorrowItems = if (slot == 20) items(context, prefs, tomorrow, null) else emptyList()

        // --- Outlook: okunmamış odaklanmış mailler ---
        val mails = if (MailStore.accessEnabled(context)) MailStore.all(context) else emptyList()

        val title: String
        val body = StringBuilder()
        when (slot) {
            8 -> {
                title = if (today.isEmpty()) "Günaydın İbrahim ☀️"
                else "Günaydın İbrahim, bugün ${today.size} işin var"
                body.append(weatherToday(w, cityName, "Gün içinde"))
                body.append("\n")
                if (today.isEmpty()) body.append("\nBugün için planlanmış bir işin yok. Güzel bir gün geçir!")
                else today.forEach { body.append("\n").append(it.second) }
            }
            12 -> {
                title = if (today.isEmpty()) "İyi öğlenler İbrahim 🌤️"
                else "İyi öğlenler İbrahim, bugün ${today.size} işin kaldı"
                body.append(weatherToday(w, cityName, "Akşama kadar"))
                body.append("\n")
                if (today.isEmpty()) body.append("\nBugün için kalan bir işin yok.")
                else today.forEach { body.append("\n").append(it.second) }
            }
            else -> {
                title = if (tomorrowItems.isEmpty()) "İyi akşamlar İbrahim 🌙"
                else "İyi akşamlar İbrahim, yarın ${tomorrowItems.size} işin var"
                if (today.isNotEmpty()) {
                    body.append("Bu akşam:")
                    today.forEach { body.append("\n").append(it.second) }
                    body.append("\n\n")
                }
                body.append(weatherTomorrow(w, cityName))
                body.append("\n\nYarın:")
                if (tomorrowItems.isEmpty()) body.append("\nPlanlanmış bir işin yok.")
                else tomorrowItems.forEach { body.append("\n").append(it.second) }
            }
        }

        var fullTitle = title
        if (mails.isNotEmpty()) {
            fullTitle += " • ✉️ ${mails.size}"
            body.append("\n\n✉️ Odaklanmış gelen kutusunda ${mails.size} okunmamış mail:")
            val multiAccount = mails.map { it.account }.distinct().size > 1
            mails.take(6).forEach { m ->
                body.append("\n• ")
                if (multiAccount && m.account.isNotEmpty()) {
                    body.append("[").append(m.account.substringBefore("@")).append("] ")
                }
                body.append(m.from.ifEmpty { "(Gönderen yok)" })
                if (m.subject.isNotEmpty()) body.append(" — ").append(m.subject)
            }
            if (mails.size > 6) body.append("\n… ve ${mails.size - 6} mail daha")
        }

        val day = if (slot == 20) tomorrow else now
        val subText = (if (slot == 20) "Yarın • " else "") +
                "${day.get(Calendar.DAY_OF_MONTH)} ${aylar[day.get(Calendar.MONTH)]} " +
                gunler[day.get(Calendar.DAY_OF_WEEK) - 1]

        post(context, fullTitle, body.toString(), subText)
    }

    // ---------------- Hava ----------------

    class Weather(
        val temp: Int, val code: Int,
        val todayCode: Int, val todayMin: Int, val todayMax: Int, val todayRain: Int?,
        val tmrCode: Int, val tmrMin: Int, val tmrMax: Int, val tmrRain: Int?,
    )

    fun fetchWeather(lat: Double, lon: Double): Weather {
        val url = URL(
            "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon" +
                    "&current=temperature_2m,weather_code" +
                    "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max" +
                    "&timezone=auto&forecast_days=2"
        )
        val conn = url.openConnection() as HttpURLConnection
        conn.connectTimeout = 7000
        conn.readTimeout = 7000
        try {
            val j = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
            val cur = j.getJSONObject("current")
            val d = j.getJSONObject("daily")
            val codes = d.getJSONArray("weather_code")
            val maxs = d.getJSONArray("temperature_2m_max")
            val mins = d.getJSONArray("temperature_2m_min")
            val rains = d.getJSONArray("precipitation_probability_max")
            fun rain(i: Int) = if (rains.isNull(i)) null else rains.getInt(i)
            return Weather(
                cur.getDouble("temperature_2m").roundToInt(), cur.getInt("weather_code"),
                codes.getInt(0), mins.getDouble(0).roundToInt(), maxs.getDouble(0).roundToInt(), rain(0),
                codes.getInt(1), mins.getDouble(1).roundToInt(), maxs.getDouble(1).roundToInt(), rain(1),
            )
        } finally {
            conn.disconnect()
        }
    }

    private fun weatherToday(w: Weather?, city: String, rangeLabel: String): String {
        if (w == null) return "🌡️ $city için hava durumu alınamadı"
        val sb = StringBuilder()
        sb.append("${emoji(w.code)} $city: şu an ${w.temp}°, ${text(w.code).lowercase(tr)}. ")
        if (rangeLabel == "Gün içinde") sb.append("Gün içinde ${w.todayMin}° – ${w.todayMax}°")
        else sb.append("$rangeLabel en yüksek ${w.todayMax}°")
        if ((w.todayRain ?: 0) >= 30) sb.append(", yağış ihtimali %${w.todayRain} ☔ Şemsiyeni al")
        return sb.append(".").toString()
    }

    private fun weatherTomorrow(w: Weather?, city: String): String {
        if (w == null) return "🌡️ $city için yarının hava durumu alınamadı"
        val sb = StringBuilder()
        sb.append("${emoji(w.tmrCode)} Yarın $city: ${text(w.tmrCode).lowercase(tr)}, ${w.tmrMin}° – ${w.tmrMax}°")
        if ((w.tmrRain ?: 0) >= 30) sb.append(", yağış ihtimali %${w.tmrRain} ☔ Şemsiyeni hazırla")
        return sb.append(".").toString()
    }

    // ---------------- İşler ----------------

    /** Belirtilen günün takvim etkinlikleri + elle eklenen işleri, saate göre sıralı. */
    fun items(
        context: Context, prefs: SharedPreferences, day: Calendar, afterMs: Long?
    ): List<Pair<String, String>> {
        val out = mutableListOf<Pair<String, String>>()
        out += readCalendar(context, day, afterMs)
        out += readTasks(prefs, day, afterMs)
        out.sortBy { it.first }
        return out
    }

    private fun readCalendar(context: Context, day: Calendar, afterMs: Long?): List<Pair<String, String>> {
        if (context.checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            return emptyList()
        }
        val start = (day.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val end = (start.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
        val b = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(b, start.timeInMillis)
        ContentUris.appendId(b, end.timeInMillis)
        val out = mutableListOf<Pair<String, String>>()
        val fmt = SimpleDateFormat("HH:mm", tr)
        val utcDay = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val dayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(day.time)
        context.contentResolver.query(
            b.build(),
            arrayOf(
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.VISIBLE,
                CalendarContract.Instances.SELF_ATTENDEE_STATUS,
            ),
            null, null, "${CalendarContract.Instances.BEGIN} ASC"
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getInt(4) == 0) continue
                if (c.getInt(5) == CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED) continue
                val title = c.getString(0)?.trim().takeUnless { it.isNullOrEmpty() } ?: "(Başlıksız)"
                val begin = c.getLong(1)
                val endMs = c.getLong(2)
                if (c.getInt(3) == 1) {
                    if (utcDay.format(begin) != dayStr) continue
                    out += "00:00" to "📅 Tüm gün • $title"
                } else {
                    // Bitmiş etkinlikleri atla (devam edenler kalır).
                    if (afterMs != null && endMs <= afterMs) continue
                    if (begin < start.timeInMillis) continue
                    val t = fmt.format(begin)
                    out += t to "📅 $t • $title"
                }
            }
        }
        return out
    }

    private fun readTasks(prefs: SharedPreferences, day: Calendar, afterMs: Long?): List<Pair<String, String>> {
        val raw = prefs.getString("flutter.tasks", null) ?: return emptyList()
        val dayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(day.time)
        val afterHm = afterMs?.let { SimpleDateFormat("HH:mm", Locale.US).format(it) }
        val out = mutableListOf<Pair<String, String>>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val t = arr.getJSONObject(i)
                if (t.optBoolean("done")) continue
                val whenStr = t.getString("when")
                if (!whenStr.startsWith(dayStr)) continue
                val title = t.getString("title")
                if (t.optBoolean("hasTime")) {
                    val hm = whenStr.substring(11, 16)
                    if (afterHm != null && hm < afterHm) continue
                    out += hm to "⏰ $hm • $title"
                } else {
                    out += "99:99" to "✅ $title"
                }
            }
        } catch (_: Exception) {}
        return out
    }

    // ---------------- Bildirim ----------------

    private fun post(context: Context, title: String, body: String, subText: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(OLD_CHANNEL) != null) nm.deleteNotificationChannel(OLD_CHANNEL)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Günlük özet", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "08:00, 12:00 ve 20:00'de plan, hava durumu ve mailler"
                }
            )
        }
        val open = PendingIntent.getActivity(
            context, 1,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_asistan)
            .setColor(0xFF0F6E56.toInt())
            .setContentTitle(title)
            .setContentText(body.lineSequence().first())
            .setSubText(subText)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        nm.notify(NOTIF_ID, n)
    }

    fun text(code: Int): String = when (code) {
        0 -> "Açık"
        1 -> "Az bulutlu"
        2 -> "Parçalı bulutlu"
        3 -> "Kapalı"
        45, 48 -> "Sisli"
        in 51..57 -> "Çisenti"
        61 -> "Hafif yağmurlu"
        63 -> "Yağmurlu"
        65 -> "Kuvvetli yağmurlu"
        66, 67 -> "Dondurucu yağmur"
        71 -> "Hafif kar yağışlı"
        73, 75, 77 -> "Kar yağışlı"
        in 80..82 -> "Sağanak yağışlı"
        85, 86 -> "Kar sağanağı"
        95 -> "Gök gürültülü fırtına"
        96, 99 -> "Dolu ile fırtına"
        else -> "Değişken"
    }

    fun emoji(code: Int): String = when (code) {
        0 -> "☀️"
        1 -> "🌤️"
        2 -> "⛅"
        3 -> "☁️"
        45, 48 -> "🌫️"
        in 51..57, in 80..82 -> "🌦️"
        in 61..67 -> "🌧️"
        in 71..77 -> "❄️"
        85, 86 -> "🌨️"
        in 95..99 -> "⛈️"
        else -> "🌡️"
    }
}
