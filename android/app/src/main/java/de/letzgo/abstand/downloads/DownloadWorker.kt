package de.letzgo.abstand.downloads

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.sample
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Führt die Download-Queue aus (iOS: `DownloadManager`-Task + `beginDownloadBackgroundExecution`).
 * Vordergrund-Dienst `dataSync` mit Fortschritts-Benachrichtigung, damit lange Hörbuch-Downloads im
 * Hintergrund weiterlaufen; nach System-Stopp startet WorkManager neu und der Lauf setzt per WIP fort.
 */
class DownloadWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun getForegroundInfo(): ForegroundInfo =
        DownloadNotifications.foregroundInfo(applicationContext, DownloadManager.activeTitle(), null, 0)

    @OptIn(kotlinx.coroutines.FlowPreview::class)
    override suspend fun doWork(): Result = coroutineScope {
        runCatching { setForeground(getForegroundInfo()) }
        val updates = launch {
            combine(DownloadManager.activeItemId, DownloadManager.progress, DownloadManager.queuedItemIds) { id, progress, queued ->
                Triple(id, progress, queued.size)
            }
                .sample(NOTIFICATION_INTERVAL_MS)
                .collect { (id, progress, queued) ->
                    if (id == null) return@collect
                    runCatching {
                        setForeground(DownloadNotifications.foregroundInfo(applicationContext, DownloadManager.activeTitle(), progress, queued))
                    }
                }
        }
        try {
            DownloadManager.runQueue()
        } finally {
            updates.cancel()
        }
        Result.success()
    }

    private companion object {
        const val NOTIFICATION_INTERVAL_MS = 1_000L
    }
}

/** Benachrichtigungskanal + Fortschritts-Notification der Downloads. */
object DownloadNotifications {
    private const val CHANNEL_ID = "abstand_downloads"
    private const val NOTIFICATION_ID = 0xAB5D

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Progress of audiobook and episode downloads"
                setShowBadge(false)
            },
        )
    }

    private fun build(context: Context, title: String?, progress: Double?, queued: Int): Notification {
        ensureChannel(context)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val percent = progress?.let { (it * 100).roundToInt().coerceIn(0, 100) }
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title?.takeIf { it.isNotBlank() } ?: "Downloading")
            .setContentText(if (queued > 0) "$queued more queued" else null)
            .setProgress(100, percent ?: 0, percent == null)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(launch)
            .build()
    }

    fun foregroundInfo(context: Context, title: String?, progress: Double?, queued: Int): ForegroundInfo {
        val notification = build(context, title, progress, queued)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }
}
