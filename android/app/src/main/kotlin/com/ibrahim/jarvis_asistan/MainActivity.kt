package com.ibrahim.jarvis_asistan

import android.Manifest
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.CalendarContract
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Telefondaki takvimleri (Google Takvim senkronu dahil) okur.
 * Dart tarafı: lib/calendar.dart
 */
class MainActivity : FlutterActivity() {
    private val channelName = "asistan/calendar"
    private val requestCode = 4711
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Morning.schedule(applicationContext)
        Thread { try { LockCard.update(applicationContext) } catch (_: Exception) {} }.start()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateLockCard" -> {
                        Thread { try { LockCard.update(applicationContext) } catch (_: Exception) {} }.start()
                        result.success(null)
                    }
                    "lockCardEnabled" -> result.success(LockCard.isEnabled(this))
                    "setLockCard" -> {
                        val on = call.argument<Boolean>("enabled") ?: true
                        LockCard.setEnabled(applicationContext, on)
                        if (on) Thread { try { LockCard.update(applicationContext) } catch (_: Exception) {} }.start()
                        result.success(null)
                    }
                    "scheduleMorning" -> {
                        Morning.schedule(applicationContext)
                        result.success(null)
                    }
                    "showMorningNow" -> {
                        Thread {
                            try {
                                Morning.showNow(applicationContext)
                            } catch (_: Exception) {}
                            runOnUiThread { result.success(null) }
                        }.start()
                    }
                    "mailAccessEnabled" -> result.success(MailStore.accessEnabled(this))
                    "openMailAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "mailCount" -> result.success(MailStore.all(this).size)
                    "hasPermission" -> result.success(hasPermission())
                    "requestPermission" -> {
                        if (hasPermission()) {
                            result.success(true)
                        } else {
                            pendingPermission = result
                            requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), requestCode)
                        }
                    }
                    "getEvents" -> {
                        if (!hasPermission()) {
                            result.error("NO_PERMISSION", "Takvim izni yok", null)
                        } else {
                            val start = (call.argument<Number>("start") ?: 0).toLong()
                            val end = (call.argument<Number>("end") ?: 0).toLong()
                            Thread {
                                try {
                                    val events = queryEvents(start, end)
                                    runOnUiThread { result.success(events) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("QUERY_FAILED", e.message, null) }
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasPermission() =
        checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grantResults)
        if (code == requestCode) {
            pendingPermission?.success(
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            pendingPermission = null
        }
    }

    private fun queryEvents(start: Long, end: Long): List<Map<String, Any?>> {
        // Instances tablosu tekrarlayan etkinlikleri de tek tek açar.
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, start)
        ContentUris.appendId(builder, end)

        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.CALENDAR_COLOR,
            CalendarContract.Instances.SELF_ATTENDEE_STATUS,
            CalendarContract.Instances.VISIBLE,
        )
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            builder.build(), projection, null, null,
            "${CalendarContract.Instances.BEGIN} ASC"
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getInt(9) == 0) continue // gizli takvim
                if (c.getInt(8) == CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED) continue
                out.add(
                    mapOf(
                        "eventId" to c.getLong(0),
                        "title" to (c.getString(1) ?: "(Başlıksız)"),
                        "begin" to c.getLong(2),
                        "end" to c.getLong(3),
                        "allDay" to (c.getInt(4) == 1),
                        "location" to c.getString(5),
                        "calendar" to c.getString(6),
                        "color" to c.getInt(7),
                    )
                )
            }
        }
        return out
    }
}
