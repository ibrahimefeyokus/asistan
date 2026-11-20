package com.ibrahim.jarvis_asistan

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/**
 * Outlook uygulamasının mail bildirimlerini izler.
 * Outlook varsayılan olarak yalnızca "Odaklanmış" gelen kutusu için bildirim gönderir
 * ve Outlook'a eklenen tüm hesapları kapsar.
 *
 * Sakladığımız liste = ekranda hâlâ duran Outlook mail bildirimleri.
 * Mail Outlook'ta okununca ya da bildirim kaydırılınca listeden düşer.
 * Diğer uygulamaların bildirimlerine dokunulmaz, hiçbir şey dışarı gönderilmez.
 */
class MailListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        // Ekrandaki mevcut Outlook maillerinden listeyi baştan kur.
        try {
            MailStore.replaceAll(this, activeNotifications.orEmpty().mapNotNull { MailStore.parse(it) })
        } catch (_: Exception) {}
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        MailStore.parse(sbn)?.let {
            MailStore.put(this, it)
            refreshLockCard()
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (sbn.packageName == MailStore.OUTLOOK) {
            MailStore.remove(this, sbn.key)
            refreshLockCard()
        }
    }

    /** Mail sayısı değişince kilit ekranı kartını güncelle. */
    private fun refreshLockCard() {
        val app = applicationContext
        Thread { try { LockCard.update(app) } catch (_: Exception) {} }.start()
    }
}

data class Mail(val key: String, val from: String, val subject: String, val account: String, val time: Long)

object MailStore {
    const val OUTLOOK = "com.microsoft.office.outlook"
    private const val PREFS = "asistan_mail"

    fun parse(sbn: StatusBarNotification): Mail? {
        if (sbn.packageName != OUTLOOK) return null
        val n = sbn.notification
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return null
        val channel = n.channelId ?: return null
        if (!channel.contains("MAIL", ignoreCase = true)) return null
        val ex = n.extras
        val from = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val subject = (ex.getCharSequence(Notification.EXTRA_TEXT)
            ?: ex.getCharSequence(Notification.EXTRA_BIG_TEXT))?.toString()?.lineSequence()?.firstOrNull()?.trim().orEmpty()
        if (from.isEmpty() && subject.isEmpty()) return null
        val account = channel.substringAfter("account_", "")
        return Mail(sbn.key, from, subject, account, sbn.postTime)
    }

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun toJson(m: Mail) = JSONObject()
        .put("from", m.from).put("subject", m.subject)
        .put("account", m.account).put("time", m.time).toString()

    @Synchronized
    fun put(c: Context, m: Mail) {
        prefs(c).edit().putString(m.key, toJson(m)).apply()
    }

    @Synchronized
    fun remove(c: Context, key: String) {
        prefs(c).edit().remove(key).apply()
    }

    @Synchronized
    fun replaceAll(c: Context, mails: List<Mail>) {
        val e = prefs(c).edit().clear()
        mails.forEach { e.putString(it.key, toJson(it)) }
        e.apply()
    }

    @Synchronized
    fun all(c: Context): List<Mail> =
        prefs(c).all.mapNotNull { (k, v) ->
            try {
                val j = JSONObject(v as String)
                Mail(k, j.getString("from"), j.getString("subject"), j.getString("account"), j.getLong("time"))
            } catch (_: Exception) {
                null
            }
        }.sortedByDescending { it.time }

    fun accessEnabled(c: Context): Boolean {
        val flat = Settings.Secure.getString(c.contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(c, MailListener::class.java)
        return flat.split(":").any { ComponentName.unflattenFromString(it) == me }
    }
}
