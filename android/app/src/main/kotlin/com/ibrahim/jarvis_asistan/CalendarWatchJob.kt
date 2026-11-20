package com.ibrahim.jarvis_asistan

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.provider.CalendarContract

/**
 * Takvimde bir şey değiştiği an Android bu işi başlatır (uygulama kapalı olsa bile).
 * Hatırlatmaları ve kilit ekranı kartını yeniler, sonra bir sonraki değişikliği beklemek
 * için kendini yeniden kurar.
 */
class CalendarWatchJob : JobService() {

    override fun onStartJob(params: JobParameters): Boolean {
        val app = applicationContext
        android.util.Log.i("Asistan", "takvim değişti, iş başladı: ${params.triggeredContentUris?.size ?: 0} uri")
        Thread {
            try {
                LockCard.update(app) // CalendarReminders.sync() dahil
            } catch (e: Exception) {
                android.util.Log.e("Asistan", "takvim işi hata", e)
            } finally {
                jobFinished(params, false)
                schedule(app, force = true) // bir sonraki değişikliği bekle
            }
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        schedule(applicationContext, force = true)
        return false
    }

    companion object {
        private const val JOB_ID = 4242

        /**
         * Takvim değişikliğini izleyen işi kurar. [force] değilse ve iş zaten kuruluysa
         * (ya da şu an çalışıyorsa) dokunmaz; aksi halde çalışan iş iptal olurdu.
         */
        fun schedule(context: Context, force: Boolean = false) {
            val js = context.getSystemService(JobScheduler::class.java) ?: return
            if (!force && js.getPendingJob(JOB_ID) != null) return
            val job = JobInfo.Builder(JOB_ID, ComponentName(context, CalendarWatchJob::class.java))
                .addTriggerContentUri(
                    JobInfo.TriggerContentUri(
                        CalendarContract.CONTENT_URI,
                        JobInfo.TriggerContentUri.FLAG_NOTIFY_FOR_DESCENDANTS
                    )
                )
                // Senkron sırasında art arda gelen değişiklikleri tek seferde topla.
                .setTriggerContentUpdateDelay(3_000)
                .setTriggerContentMaxDelay(15_000)
                .build()
            try {
                js.schedule(job)
            } catch (_: Exception) {}
        }
    }
}
