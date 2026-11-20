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
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CalendarContract
import java.text.SimpleDateFormat
import java.util.Locale

/** Takvim etkinliğinden 10 dk önce bildirimi gösterir. */
class CalendarReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        CalendarReminders.show(context.applicationContext, intent)
    }
}

/**
 * Google Takvim (telefon takvimi) etkinlikleri için hatırlatmaları tamamen Android
 * tarafında kurar. Uygulama açılmasa da çalışır:
 *  - takvim değişince (PROVIDER_CHANGED yayını),
 *  - her 30 dakikada bir (LockCard zamanlayıcısı),
 *  - telefon açılınca.
 * İnternet gerekmez; takvim telefonda yerel olarak okunur.
 */
object CalendarReminders {
    const val LEAD_MINUTES = 10
    private const val DAYS_AHEAD = 8
    private const val ACTION = "com.ibrahim.jarvis_asistan.CAL_REMINDER"
    private const val CHANNEL = "takvim_hatirlatma"
    private const val PREFS = "asistan_cal_reminders"
    private const val KEY_IDS = "ids"

    private fun hasCalendar(c: Context) =
        c.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

    /** Önceki hatırlatmaları siler, önümüzdeki 8 günün etkinlikleri için yenilerini kurar. */
    @Synchronized
    fun sync(context: Context) {
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // Eskileri iptal et.
        prefs.getStringSet(KEY_IDS, emptySet())?.forEach { s ->
            s.toIntOrNull()?.let { id ->
                PendingIntent.getBroadcast(
                    context, id, baseIntent(context),
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                )?.let { am.cancel(it); it.cancel() }
            }
        }
        if (!hasCalendar(context)) {
            prefs.edit().putStringSet(KEY_IDS, emptySet()).apply()
            return
        }

        val now = System.currentTimeMillis()
        val b = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(b, now)
        ContentUris.appendId(b, now + DAYS_AHEAD * 86_400_000L)
        val exact = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()
        val ids = mutableSetOf<String>()

        context.contentResolver.query(
            b.build(),
            arrayOf(
                CalendarContract.Instances.EVENT_ID,
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.EVENT_LOCATION,
                CalendarContract.Instances.VISIBLE,
                CalendarContract.Instances.SELF_ATTENDEE_STATUS,
            ),
            null, null, "${CalendarContract.Instances.BEGIN} ASC"
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getInt(3) == 1) continue                     // tüm gün
                if (c.getInt(5) == 0) continue                     // gizli takvim
                if (c.getInt(6) == CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED) continue
                val begin = c.getLong(2)
                if (begin <= now) continue
                var at = begin - LEAD_MINUTES * 60_000L
                val early = at > now
                if (!early) at = begin

                val id = idFor(c.getLong(0), begin)
                val intent = baseIntent(context)
                    .putExtra("title", c.getString(1)?.trim().takeUnless { it.isNullOrEmpty() } ?: "(Başlıksız)")
                    .putExtra("begin", begin)
                    .putExtra("location", c.getString(4)?.trim().orEmpty())
                    .putExtra("early", early)
                    .putExtra("id", id)
                val pi = PendingIntent.getBroadcast(
                    context, id, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                ids += id.toString()
            }
        }
        prefs.edit().putStringSet(KEY_IDS, ids).apply()
        android.util.Log.i("Asistan", "takvim senkron: ${ids.size} hatırlatma kuruldu (exact=$exact)")
    }

    fun show(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Takvim hatırlatmaları", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Google Takvim etkinliklerinden $LEAD_MINUTES dakika önce"
                }
            )
        }
        val title = intent.getStringExtra("title") ?: return
        val begin = intent.getLongExtra("begin", 0)
        val loc = intent.getStringExtra("location").orEmpty()
        val hm = SimpleDateFormat("HH:mm", Locale("tr")).format(begin)
        val place = if (loc.isNotEmpty()) " • $loc" else ""
        val body = if (intent.getBooleanExtra("early", true))
            "$LEAD_MINUTES dakika sonra, saat $hm$place" else "Şimdi başlıyor, saat $hm$place"
        val id = intent.getIntExtra("id", 0)

        val open = PendingIntent.getActivity(
            context, 3,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_asistan)
            .setColor(0xFF0F6E56.toInt())
            .setContentTitle("📅 $title")
            .setContentText(body)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        nm.notify(id, n)
    }

    private fun baseIntent(context: Context) =
        Intent(context, CalendarReminderReceiver::class.java).setAction(ACTION)

    /** Etkinlik + başlangıç zamanından sabit bir kimlik (elle eklenen işlerle çakışmaz). */
    private fun idFor(eventId: Long, begin: Long): Int =
        1_000_000_000 + ((eventId * 31 + begin / 60_000) % 900_000_000).toInt().let { if (it < 0) -it else it }
}
