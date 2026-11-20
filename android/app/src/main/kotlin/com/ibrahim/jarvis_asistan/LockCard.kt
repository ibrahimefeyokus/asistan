package com.ibrahim.jarvis_asistan

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.util.Calendar

/** Kilit ekranı kartını periyodik olarak yeniler. */
class LockCardReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val pending = goAsync()
        Thread {
            try {
                LockCard.update(app)
            } catch (_: Exception) {
            } finally {
                pending.finish()
            }
        }.start()
    }
}

/**
 * Kilit ekranında duran, kendini güncelleyen bir "kart" (sabit bildirim):
 * hava durumu, bugünün sıradaki işleri ve okunmamış mail sayısı.
 * realme kilit ekranı widget'larına üçüncü taraf uygulama izin vermediği için
 * aynı işi bildirimle yapıyoruz.
 */
object LockCard {
    private const val CHANNEL = "kilit_karti"
    private const val NOTIF_ID = 7007
    private const val UPDATE_MINUTES = 30
    private const val WEATHER_CACHE_MIN = 30
    private const val PREF_ENABLED = "flutter.lock_card"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean(PREF_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit().putBoolean(PREF_ENABLED, enabled).apply()
        if (!enabled) disable(context)
    }

    /** Arka plan iş parçacığından çağrılmalı (internet kullanabilir). */
    @Synchronized
    fun update(context: Context) {
        val now = Calendar.getInstance()
        // Takvim hatırlatmaları kart kapalı olsa da her turda yeniden kurulur.
        try { CalendarReminders.sync(context) } catch (e: Exception) {
            android.util.Log.e("Asistan", "takvim senkron hata", e)
        }
        // Takvim izleme işinin kurulu olduğundan emin ol.
        CalendarWatchJob.schedule(context)
        if (!isEnabled(context)) {
            disable(context)
            scheduleNext(context, emptyList(), now)
            return
        }
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        // --- Hava (30 dk önbellekli) ---
        var cityName = "İstanbul"
        var lat = 41.0082
        var lon = 28.9784
        prefs.getString("flutter.city", null)?.let {
            try {
                val c = JSONObject(it)
                cityName = c.getString("name"); lat = c.getDouble("lat"); lon = c.getDouble("lon")
            } catch (_: Exception) {}
        }
        val weatherTitle = cachedWeatherTitle(context, lat, lon, cityName)

        // --- Bugün kalan işler; yoksa yarın ---
        var items = Morning.items(context, prefs, now, now.timeInMillis)
        var header = "Bugün"
        if (items.isEmpty()) {
            val tomorrow = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
            items = Morning.items(context, prefs, tomorrow, null)
            header = "Yarın"
        }

        val mails = if (MailStore.accessEnabled(context)) MailStore.all(context).size else 0

        val shortText: String
        val body = StringBuilder()
        if (items.isEmpty()) {
            shortText = "Bugün ve yarın için planlanmış işin yok"
            body.append(shortText)
        } else {
            val first = items.first().second
            shortText = if (header == "Bugün") "Sıradaki: $first" else "Yarın: $first"
            body.append(header).append(":")
            items.take(5).forEach { body.append("\n").append(it.second) }
            if (items.size > 5) body.append("\n… ve ${items.size - 5} iş daha")
        }
        if (mails > 0) body.append("\n✉️ $mails okunmamış odaklanmış mail")

        post(context, weatherTitle, if (mails > 0) "$shortText • ✉️ $mails" else shortText, body.toString())
        scheduleNext(context, items.takeIf { header == "Bugün" }.orEmpty(), now)
    }

    /** Yalnızca kartı kaldırır; 30 dk'lık zamanlayıcı takvim senkronu için çalışmaya devam eder. */
    fun disable(context: Context) {
        context.getSystemService(NotificationManager::class.java)?.cancel(NOTIF_ID)
    }

    private fun cachedWeatherTitle(context: Context, lat: Double, lon: Double, city: String): String {
        val cache = context.getSharedPreferences("asistan_lockcard", Context.MODE_PRIVATE)
        val age = System.currentTimeMillis() - cache.getLong("at", 0)
        val sameCity = cache.getString("city", null) == city
        if (age < WEATHER_CACHE_MIN * 60_000L && sameCity) {
            cache.getString("title", null)?.let { return it }
        }
        return try {
            val w = Morning.fetchWeather(lat, lon)
            val title = "${Morning.emoji(w.code)} ${w.temp}° $city • ↑${w.todayMax}° ↓${w.todayMin}°" +
                    if ((w.todayRain ?: 0) >= 30) " • ☔ %${w.todayRain}" else ""
            cache.edit().putString("title", title).putString("city", city)
                .putLong("at", System.currentTimeMillis()).apply()
            title
        } catch (_: Exception) {
            cache.getString("title", null) ?: "Asistan"
        }
    }

    /** 30 dk sonra ya da sıradaki işin başlangıcından 1 dk sonra (hangisi önceyse) yenile. */
    private fun scheduleNext(context: Context, todayItems: List<Pair<String, String>>, now: Calendar) {
        var next = now.timeInMillis + UPDATE_MINUTES * 60_000L
        val nowHm = String.format("%02d:%02d", now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE))
        todayItems.map { it.first }
            .filter { it != "00:00" && it != "99:99" && it > nowHm }
            .minOrNull()?.let { hm ->
                val c = (now.clone() as Calendar).apply {
                    set(Calendar.HOUR_OF_DAY, hm.substring(0, 2).toInt())
                    set(Calendar.MINUTE, hm.substring(3, 5).toInt() + 1)
                    set(Calendar.SECOND, 0)
                }
                if (c.timeInMillis < next) next = c.timeInMillis
            }
        // Gece yarısında da yenile (gün değişince liste değişir).
        val midnight = (now.clone() as Calendar).apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 1); set(Calendar.SECOND, 0)
        }.timeInMillis
        if (midnight < next) next = midnight

        val am = context.getSystemService(AlarmManager::class.java) ?: return
        am.setAndAllowWhileIdle(AlarmManager.RTC, next, alarmIntent(context))
    }

    private fun alarmIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 7,
        Intent(context, LockCardReceiver::class.java).setAction("com.ibrahim.jarvis_asistan.TICK"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun post(context: Context, title: String, text: String, body: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Kilit ekranı kartı", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Kilit ekranında hava, sıradaki işler ve mailler"
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            )
        }
        val open = PendingIntent.getActivity(
            context, 2,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_asistan)
            .setColor(0xFF0F6E56.toInt())
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_STATUS)
            .setSortKey("0")
            .build()
        nm.notify(NOTIF_ID, n)
    }
}
