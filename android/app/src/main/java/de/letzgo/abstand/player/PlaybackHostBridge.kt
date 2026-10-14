package de.letzgo.abstand.player

import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsProgressPatch
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.downloads.DownloadManager
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * iOS: Player-Verdrahtung in `AppModel` (`player.onPlaybackTick`, `onLocalPlaybackWithoutSessionSync`,
 * `onAudiobookPlaybackCompleted`, `onPodcastEpisodePlaybackCompleted`) samt
 * `recordActivePlaybackProgressLocally`, `syncLocalDownloadedPlaybackToServer`,
 * `handleSmartDownloadPlaybackTick` und den Offline-Hörsekunden.
 *
 * Der Integrator erzeugt ihn einmal mit seinem [PlaybackHost]: `PlaybackHostBridge(controller, host).attach()`.
 */
class PlaybackHostBridge(
    private val player: PlaybackController,
    private val host: PlaybackHost,
    private val clockMillis: () -> Long = System::currentTimeMillis,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var lastPeriodicProgressSaveAt: Long? = null
    private val smartDownload = SmartDownloadTracker(clockMillis)

    fun attach() {
        player.onPlaybackTick = {
            handleSmartDownloadPlaybackTick()
            maybeRecordActivePlaybackProgressPeriodically()
        }
        player.onLocalPlaybackWithoutSessionSync = { timeListened, position, duration ->
            syncLocalDownloadedPlaybackToServer(timeListened, position, duration)
        }
        player.onAudiobookPlaybackCompleted = {
            val bookId = player.activeBook.value?.id
            if (bookId != null && player.activePlaybackEpisodeId.value == null) {
                scope.launch { host.markPlaybackFinished(bookId, null) }
            }
        }
        player.onPodcastEpisodePlaybackCompleted = {
            val bookId = player.activeBook.value?.id
            val ep = player.activePlaybackEpisodeId.value
            if (bookId != null && ep != null) scope.launch { host.markPlaybackFinished(bookId, ep) }
        }
    }

    /** iOS: `activePlaybackProgressLookupKey()` — `libraryItemId` bzw. `libraryItemId-episodeId`. */
    fun activePlaybackProgressLookupKey(): String? {
        val book = player.activeBook.value ?: return null
        val ep = player.activePlaybackEpisodeId.value?.swiftTrim() ?: ""
        if (ep.isEmpty()) return book.id
        return podcastEpisodeForActivePlayback()?.progressLookupKey ?: "${book.id}-$ep"
    }

    /** iOS: `podcastEpisodeForSmartDownloadFromActivePlayback` — Listen-Zeile oder synthetische Zeile. */
    fun podcastEpisodeForActivePlayback(): AbsPodcastEpisodeListItem? {
        val book = player.activeBook.value ?: return null
        val ep = player.activePlaybackEpisodeId.value?.swiftTrim() ?: ""
        if (ep.isEmpty()) return null
        host.podcastEpisode(book.id, ep)?.let { return it }
        val epTitle = book.displayTitle.swiftTrim()
        val authors = book.displayAuthors.swiftTrim()
        return AbsPodcastEpisodeListItem(
            libraryItemId = book.id,
            libraryId = book.libraryId,
            episodeId = ep,
            episodeTitle = epTitle.ifEmpty { "Episode" },
            showTitle = "Podcast",
            authorLine = authors.ifEmpty { "Podcast" },
            duration = book.media.duration ?: 0.0,
            publishedAt = null,
        )
    }

    /** iOS: `offlineStorageIdForActivePlayback` — Ordnername des laufenden Titels. */
    fun offlineStorageIdForActivePlayback(): String? {
        val book = player.activeBook.value ?: return null
        val ep = player.activePlaybackEpisodeId.value?.swiftTrim() ?: ""
        if (ep.isEmpty()) return book.id
        val episode = podcastEpisodeForActivePlayback() ?: return "${book.id}-$ep".replace("/", "_")
        return DownloadManager.podcastEpisodeOfflineStorageId(episode)
    }

    /**
     * iOS: `recordActivePlaybackProgressLocally(markPendingServerSync:)` — aktuelle Position als
     * Fortschrittszeile an den Host. `null` = nur markieren, wenn keine Play-Session synct.
     */
    fun recordActivePlaybackProgressLocally(markPendingServerSync: Boolean? = null) {
        val book = player.activeBook.value ?: return
        val dur = player.totalDuration.value
        if (dur <= 0) return
        val key = activePlaybackProgressLookupKey() ?: return
        val ep = player.activePlaybackEpisodeId.value?.swiftTrim()?.ifEmpty { null }
        val p = optimisticProgress(host.progress(key), book.id, ep, player.globalPosition.value, dur, clockMillis())
        host.upsertProgress(p, markPendingServerSync ?: !player.isRemotePlaySessionActive)
    }

    private fun maybeRecordActivePlaybackProgressPeriodically() {
        if (player.activeBook.value == null || player.totalDuration.value <= 0) return
        val now = clockMillis()
        val last = lastPeriodicProgressSaveAt
        if (last != null && now - last < PERIODIC_PROGRESS_SAVE_INTERVAL_MS) return
        lastPeriodicProgressSaveAt = now
        recordActivePlaybackProgressLocally()
    }

    /** iOS: `syncLocalDownloadedPlaybackToServer` — lokal sichern, dann PATCH oder Offline-Hörzeit. */
    suspend fun syncLocalDownloadedPlaybackToServer(timeListened: Int, position: Double, duration: Double) {
        recordActivePlaybackProgressLocally(markPendingServerSync = true)
        val book = player.activeBook.value ?: return
        val progressKey = activePlaybackProgressLookupKey() ?: book.id
        val client = host.apiClient
        if (!host.mayUseServerNetwork || !host.isNetworkReachable || client == null) {
            if (timeListened > 0) PendingOfflineListening.add(progressKey, timeListened)
            return
        }
        if (player.isRemotePlaySessionActive) return
        val dur = if (duration > 0) duration else player.totalDuration.value
        if (dur <= 0) return
        val pos = maxOf(0.0, position)
        val prog = (pos / dur).coerceIn(0.0, 1.0)
        try {
            client.patchProgress(book.id, player.activePlaybackEpisodeId.value, AbsProgressPatch(currentTime = pos, duration = dur, progress = prog))
            host.clearPendingLocalProgressSync(progressKey)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (timeListened > 0) PendingOfflineListening.add(progressKey, timeListened)
        }
    }

    /** iOS: `flushPendingOfflineListeningTime` — gespeicherte Offline-Hörzeit nachsenden. */
    suspend fun flushPendingOfflineListeningTime() {
        val client = host.apiClient ?: return
        if (!host.isNetworkReachable || !host.mayUseServerNetwork) return
        PendingOfflineListening.flush(client) { host.progress(it) }
    }

    /** iOS: `handleSmartDownloadPlaybackTick` — nach ≥ 3 min Wiedergabe im WLAN einmal herunterladen. */
    private fun handleSmartDownloadPlaybackTick() {
        if (host.apiClient == null) {
            smartDownload.reset()
            return
        }
        val book = player.activeBook.value
        val ep = player.activePlaybackEpisodeId.value?.swiftTrim() ?: ""
        val key = book?.let { if (ep.isEmpty()) "audiobook:${it.id}" else "podcast:${it.id}:$ep" }
        val eligible = player.isPlaying.value && host.isNetworkReachable && host.isNetworkUnmetered &&
            !player.isPlaybackFromOfflineDownload
        if (!smartDownload.tick(key, eligible, DownloadManager.smartDownloadOnWiFi)) return
        val storageId = offlineStorageIdForActivePlayback() ?: return
        if (DownloadManager.existingDownloadFolder(storageId)?.let { de.letzgo.abstand.data.AbsDownloadManifest.load(it) } != null) return
        if (DownloadManager.isActiveOrQueued(storageId)) return
        if (ep.isEmpty()) {
            DownloadManager.startDownload(book!!)
        } else {
            val episode = podcastEpisodeForActivePlayback() ?: return
            DownloadManager.startDownloadPodcastEpisode(episode, book?.libraryId)
        }
        host.onSmartDownloadStarted(storageId)
    }

    companion object {
        /** iOS: `periodicPlaybackProgressSaveInterval` (5 s). */
        const val PERIODIC_PROGRESS_SAVE_INTERVAL_MS = 5_000L

        /**
         * iOS: `progressForOptimisticAudiobook` / `…PodcastEpisode` — vorhandene Zeile fortschreiben
         * (Server-ID, eBook-Felder bleiben), `isFinished` zurück auf `false`.
         */
        fun optimisticProgress(
            existing: AbsUserMediaProgress?,
            libraryItemId: String,
            episodeId: String?,
            position: Double,
            duration: Double,
            nowMillis: Long,
        ): AbsUserMediaProgress {
            val dur = maxOf(duration, position, 1.0)
            val progress = (position / dur).coerceIn(0.0, 1.0)
            val lastUpdate = maxOf(nowMillis, (existing?.lastUpdate ?: 0L) + 1)
            return existing?.copy(
                libraryItemId = libraryItemId,
                episodeId = episodeId,
                duration = dur,
                progress = progress,
                currentTime = position,
                isFinished = false,
                lastUpdate = lastUpdate,
            ) ?: AbsUserMediaProgress(
                libraryItemId = libraryItemId,
                episodeId = episodeId,
                duration = dur,
                progress = progress,
                currentTime = position,
                isFinished = false,
                lastUpdate = lastUpdate,
            )
        }
    }
}

/**
 * iOS: Zustand von `handleSmartDownloadPlaybackTick` (`smartDlPlaybackKey`, `smartDlAccumulatedSeconds`,
 * `smartDlLastTickAt`, `smartDlFiredForCurrentKey`) — feuert einmal je Titel nach 180 s Wiedergabe.
 */
class SmartDownloadTracker(private val clockMillis: () -> Long = System::currentTimeMillis) {
    private var key: String? = null
    private var accumulatedSeconds = 0.0
    private var lastTickAt: Long? = null
    private var firedForCurrentKey = false

    fun reset() {
        key = null
        lastTickAt = null
    }

    /**
     * @param key Titel-Schlüssel (`null` ohne aktives Medium).
     * @param eligible spielt, WLAN, nicht schon aus Download.
     * @param enabled Einstellung „Smart download on Wi-Fi“.
     * @return `true` genau einmal je Titel, wenn der Download jetzt starten soll.
     */
    fun tick(key: String?, eligible: Boolean, enabled: Boolean): Boolean {
        if (key == null) {
            reset()
            return false
        }
        if (this.key != key) {
            this.key = key
            accumulatedSeconds = 0.0
            lastTickAt = null
            firedForCurrentKey = false
        }
        if (!eligible) {
            lastTickAt = null
            return false
        }
        if (!enabled) return false
        val now = clockMillis()
        val dt = lastTickAt?.let { (now - it) / 1000.0 } ?: 0.0
        lastTickAt = now
        accumulatedSeconds += maxOf(0.0, dt)
        if (accumulatedSeconds < THRESHOLD_SECONDS) return false
        if (firedForCurrentKey) return false
        firedForCurrentKey = true
        return true
    }

    companion object {
        /** iOS: `smartDownloadWiFiListenThresholdSeconds`. */
        const val THRESHOLD_SECONDS = 180.0
    }
}
