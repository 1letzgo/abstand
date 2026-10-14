package de.letzgo.abstand.downloads

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsAudioTrack
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsChapter
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsPlaySession
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import de.letzgo.abstand.data.DownloadCatalogEntry
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.data.trimmedOrEmpty
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.player.PlaybackNoTracksException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/**
 * Was der Download-Teil vom App-Zustand braucht (iOS: `AppModel.client` und der Completion-Block in
 * `beginOfflineItemDownload`). Implementiert vom Integrator, gesetzt in `Application.onCreate`
 * (muss vor einem Worker-Neustart nach Prozess-Tod stehen).
 */
interface DownloadHost {
    /** iOS: `AppModel.client` — `null` ohne Login (Download scheitert dann). */
    val apiClient: AbsApiClient?

    /**
     * Lauf beendet (iOS: Completion): `ok` → Speicher-ID in die Download-Liste des Accounts
     * (`Keys.downloads.<account>`), Transkript-Vorproduktion, ggf. laufende Wiedergabe auf die
     * lokalen Dateien umstellen; `!ok` → „Download failed.“ anzeigen. Nicht bei Nutzer-Abbruch.
     */
    fun onDownloadFinished(storageItemId: String, ok: Boolean)
}

/** iOS: Ergebnis eines Laufs (Completion `Bool`), als Ereignis für die UI. */
data class DownloadCompletion(val storageItemId: String, val ok: Boolean)

/**
 * iOS: `DownloadManager` — sequenzielle FIFO-Downloads der Spuren nach `filesDir/Downloads/<Speicher-ID>/`
 * (iOS: `Documents/Downloads`), je Titel ein `download.json` im iOS-Format, Wiederaufnahme über
 * `download-wip.json`. Ausgeführt in [DownloadWorker] (WorkManager, Vordergrund-Dienst `dataSync`
 * mit Fortschritts-Benachrichtigung), damit Downloads Hintergrund und Prozess-Tod überstehen.
 */
object DownloadManager {
    private const val TAG = "AbstandDownloads"
    const val DOWNLOADS_DIR = "Downloads"
    private const val QUEUE_FILE = "DownloadsQueue.json"
    const val WORK_NAME = "abstand-downloads"
    private const val TRACK_DOWNLOAD_MAX_ATTEMPTS = 3
    /** iOS: Throttling der Byte-Callbacks (0,08 s). */
    private const val INTRA_TRACK_EMIT_INTERVAL_MS = 80L

    @Volatile var host: DownloadHost? = null

    private val _activeItemId = MutableStateFlow<String?>(null)
    val activeItemId: StateFlow<String?> = _activeItemId.asStateFlow()

    private val _progress = MutableStateFlow(0.0)
    val progress: StateFlow<Double> = _progress.asStateFlow()

    /** Wartende Downloads (FIFO); `activeItemId`/`progress` beschreiben nur den aktiven Lauf. */
    private val _queuedItemIds = MutableStateFlow<List<String>>(emptyList())
    val queuedItemIds: StateFlow<List<String>> = _queuedItemIds.asStateFlow()

    /** Zähler abgeschlossener Downloads — Trigger für Haptik/Feedback in der UI. */
    private val _completedDownloadCount = MutableStateFlow(0)
    val completedDownloadCount: StateFlow<Int> = _completedDownloadCount.asStateFlow()

    private val _completions = MutableSharedFlow<DownloadCompletion>(extraBufferCapacity = 16)
    val completions: SharedFlow<DownloadCompletion> = _completions.asSharedFlow()

    private val lock = Any()
    private val queue = DownloadQueue<QueuedDownloadRecord> { it.storageItemId }
    private var activeJob: Job? = null
    private var activeClient: AbsApiClient? = null
    /** Vom Nutzer abgebrochene aktive Läufe — kein Completion-Callback (iOS-Kommentar in `removeLocalDownload`). */
    private val userCancelled = HashSet<String>()
    private lateinit var appContext: Context

    /** Einmal in `Application.onCreate`: persistierte Queue wiederherstellen und ggf. fortsetzen. */
    fun init(context: Context) {
        if (::appContext.isInitialized) return
        appContext = context.applicationContext
        val restored = loadPersistedQueue()
        synchronized(lock) { queue.restore(restored) }
        publishState()
        if (restored.isNotEmpty()) enqueueWorker()
    }

    // MARK: - Ordner

    /** Kontext; ohne explizites [init] der von `Prefs.init` (Application.onCreate). */
    private fun ctx(): Context {
        if (!::appContext.isInitialized) init(Prefs.appContext)
        return appContext
    }

    /** Wurzel `…/Downloads` (ohne Item-ID). */
    fun downloadsRoot(): File = File(ctx().filesDir, DOWNLOADS_DIR)

    /** Ordner eines Downloads (wird angelegt). */
    fun downloadFolder(itemId: String): File = File(downloadsRoot(), itemId).apply { mkdirs() }

    /** Ordner ohne Anlegen (Existenzprüfung). */
    fun existingDownloadFolder(itemId: String): File? = File(downloadsRoot(), itemId).takeIf { it.isDirectory }

    /** Entfernt den kompletten Download-Ordner inkl. partieller Tracks. */
    fun deleteDownload(itemId: String) {
        if (itemId.isBlank()) return
        File(downloadsRoot(), itemId).takeIf { it.exists() }?.deleteRecursively()
    }

    /** iOS: `podcastEpisodeOfflineStorageId` — Ordnername einer Podcast-Folge. */
    fun podcastEpisodeOfflineStorageId(episode: AbsPodcastEpisodeListItem): String =
        episode.progressLookupKey.replace("/", "_")

    // MARK: - Einreihen / Abbrechen

    /**
     * iOS: `startDownload(client:book:episodeId:storageItemId:reusePlaySessionId:reusePlaySessionTracks:)`.
     * Bereits aktiv oder wartend → No-Op. Läuft gerade dieselbe Remote-Session im Player, werden deren
     * ID und Spuren wiederverwendet (sonst würde ein zweites `POST …/play` die Wiedergabe beenden).
     */
    fun startDownload(
        book: AbsBook,
        episodeId: String? = null,
        storageItemId: String? = null,
        reusePlaySessionId: String? = null,
        reusePlaySessionTracks: List<AbsAudioTrack>? = null,
    ) {
        val id = storageItemId ?: book.id
        val ep = episodeId?.swiftTrim()?.ifEmpty { null }
        val player = PlaybackController.sharedOrNull()
        val reuse = reusePlaySessionId ?: player?.playSessionIdForReuseWhenDownloadingSameItem(book.id, ep)
        val reuseTracks = reusePlaySessionTracks
            ?: if (reuse != null) player?.audioTracksForActiveSessionReuse()?.ifEmpty { null } else null
        val record = QueuedDownloadRecord(
            storageItemId = id,
            book = book,
            episodeId = ep,
            reusePlaySessionId = reuse,
            reusePlaySessionTracks = reuseTracks,
            title = book.displayTitle,
            subtitle = book.displayAuthors,
        )
        ctx()
        val added = synchronized(lock) { queue.enqueue(record) }
        if (!added) return
        persistQueue()
        publishState()
        enqueueWorker()
    }

    /** iOS: `startDownloadPodcastEpisode` — Stub-Buch + Speicher-ID der Folge. */
    fun startDownloadPodcastEpisode(episode: AbsPodcastEpisodeListItem, libraryId: String?) {
        startDownload(
            book = episode.playbackStubBook(libraryId),
            episodeId = episode.episodeId,
            storageItemId = podcastEpisodeOfflineStorageId(episode),
        )
    }

    /** Bricht nur den aktuell laufenden Download ab (Queue bleibt). */
    fun cancel() {
        val id = synchronized(lock) { queue.activeId } ?: return
        cancel(id)
    }

    /** Gezielt abbrechen: aus der Queue entfernen (wartet noch) oder den aktiven Lauf stoppen. */
    fun cancel(itemId: String) {
        val wasActive: Boolean
        synchronized(lock) {
            if (queue.removeQueued(itemId)) {
                wasActive = false
            } else if (queue.activeId == itemId) {
                wasActive = true
                userCancelled.add(itemId)
            } else return
        }
        if (wasActive) {
            // Erst laufende HTTP-Calls abbrechen, dann den Job — sonst trifft `cancelInFlightDownloads`
            // (alle Calls des Download-Clients) den gerade gestarteten nächsten Download.
            activeClient?.cancelInFlightDownloads()
            activeJob?.cancel()
            _activeItemId.value = null
            _progress.value = 0.0
        }
        persistQueue()
        publishState()
    }

    /** iOS: `pendingDownloadCatalog[id]` — Anzeige für aktive/wartende Downloads ohne Manifest. */
    fun catalogEntry(storageItemId: String): DownloadCatalogEntry? {
        val record = synchronized(lock) { queue.snapshot().firstOrNull { it.storageItemId == storageItemId } } ?: return null
        return DownloadCatalogEntry(
            libraryItemId = record.book.id,
            title = record.title,
            subtitle = record.subtitle,
            isPodcastEpisode = record.episodeId != null,
        )
    }

    fun isActiveOrQueued(storageItemId: String): Boolean = synchronized(lock) { queue.contains(storageItemId) }

    // MARK: - Smart-Download-Einstellungen (iOS: AppModel `smartDownloadOnWiFi` / `…RemoveWhenFinished`)

    var smartDownloadOnWiFi: Boolean
        get() = Prefs.bool(Keys.smartDlAutoWifi)
        set(value) = Prefs.setBool(Keys.smartDlAutoWifi, value)

    var smartDownloadRemoveWhenFinished: Boolean
        get() = Prefs.bool(Keys.smartDlRemoveWhenFinished)
        set(value) = Prefs.setBool(Keys.smartDlRemoveWhenFinished, value)

    /**
     * iOS: `removeLocalDownloadIfFinishedSetting` — Dateien eines fertig gehörten Titels entfernen, wenn
     * „Remove when finished“ aktiv ist. `true`, wenn gelöscht wurde (Aufrufer: Download-Liste + Regale).
     */
    fun removeLocalDownloadIfFinishedSetting(storageItemId: String, isDownloaded: Boolean): Boolean {
        if (!smartDownloadRemoveWhenFinished || !isDownloaded) return false
        cancel(storageItemId)
        deleteDownload(storageItemId)
        return true
    }

    // MARK: - Offline-Stubs aus Manifesten

    /** Ein fertiger Download auf der Platte. */
    data class OfflineDownload(val storageItemId: String, val folder: File, val manifest: AbsDownloadManifest)

    /** Alle `download.json` unter `Downloads/<id>` (unvollständige Ordner ohne Manifest zählen nicht). */
    fun scanDownloads(): List<OfflineDownload> =
        downloadsRoot().listFiles()?.filter { it.isDirectory }?.mapNotNull { dir ->
            AbsDownloadManifest.load(dir)?.let { OfflineDownload(dir.name, dir, it) }
        }?.sortedBy { it.storageItemId }.orEmpty()

    /** iOS: Basis für `loadDownloadedItemIdsForActiveAccount` — vorhandene Speicher-IDs auf der Platte. */
    fun scanDownloadedStorageIds(): Set<String> = scanDownloads().mapTo(LinkedHashSet()) { it.storageItemId }

    /**
     * iOS: `downloadedRowsForCarPlay()` — Hörbuch-Stubs per `ABSBook.fromDownloadManifest`, Folgen als
     * `ABSPodcastEpisodeListItem`; nach Speicher-ID sortiert, gefiltert auf den aktiven Account.
     */
    fun downloadedRows(
        storageIds: Collection<String>? = null,
        belongsToActiveAccount: (AbsDownloadManifest) -> Boolean = { true },
    ): List<AbsStartShelfMergedRow> {
        val wanted = storageIds?.toSet()
        return scanDownloads()
            .filter { wanted == null || it.storageItemId in wanted }
            .filter { belongsToActiveAccount(it.manifest) }
            .map { offlineRow(it.manifest) }
    }

    /** Stub-Zeile aus einem Manifest. */
    fun offlineRow(manifest: AbsDownloadManifest): AbsStartShelfMergedRow {
        val ep = manifest.episodeId.trimmedOrEmpty()
        if (ep.isEmpty()) return AbsStartShelfMergedRow.Book(AbsBook.fromDownloadManifest(manifest))
        val title = manifest.displayTitle.trimmedOrEmpty()
        val show = manifest.displayAuthor.trimmedOrEmpty()
        return AbsStartShelfMergedRow.PodcastEpisode(
            AbsPodcastEpisodeListItem(
                libraryItemId = manifest.libraryItemId,
                libraryId = manifest.libraryId,
                episodeId = ep,
                episodeTitle = title.ifEmpty { "Episode" },
                showTitle = show,
                authorLine = show,
                duration = manifest.totalDuration ?: 0.0,
                publishedAt = null,
            ),
        )
    }

    /** iOS: `resolvedLocalDownloadForPlayback(book:)` — Ordner + Item-/Folgen-ID (Ordner kann ≠ `book.id` sein). */
    data class LocalPlaybackDownload(val root: File, val libraryItemId: String, val episodeId: String?)

    fun resolvedLocalDownloadForPlayback(book: AbsBook, downloadedIds: Collection<String>): LocalPlaybackDownload? {
        if (book.id in downloadedIds) {
            val root = downloadFolder(book.id)
            val manifest = AbsDownloadManifest.load(root)
            val ep = manifest?.episodeId.trimmedOrEmpty()
            return LocalPlaybackDownload(root, manifest?.libraryItemId ?: book.id, ep.ifEmpty { null })
        }
        for (storageId in downloadedIds) {
            val root = existingDownloadFolder(storageId) ?: continue
            val manifest = AbsDownloadManifest.load(root) ?: continue
            if (manifest.libraryItemId != book.id) continue
            val ep = manifest.episodeId.trimmedOrEmpty()
            return LocalPlaybackDownload(root, manifest.libraryItemId, ep.ifEmpty { null })
        }
        return null
    }

    /** iOS: `localDownloadRoot(for:)`. */
    fun localDownloadRoot(itemId: String, downloadedIds: Collection<String>): File? =
        if (itemId in downloadedIds) downloadFolder(itemId) else null

    // MARK: - Worker-Lauf

    private fun enqueueWorker() {
        val request = OneTimeWorkRequestBuilder<DownloadWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        // APPEND: ein gerade auslaufender Worker kann den neuen Eintrag nicht mehr verschlucken.
        WorkManager.getInstance(ctx()).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    /** Titel des aktiven Downloads für die Benachrichtigung. */
    internal fun activeTitle(): String? = synchronized(lock) { queue.active?.title }

    /**
     * Arbeitet die Queue ab, bis sie leer ist (iOS: `startNextQueuedDownload`-Kette).
     * Wird der Worker vom System gestoppt, bleibt der aktive Eintrag für die Wiederaufnahme vorn.
     */
    internal suspend fun runQueue() = coroutineScope {
        while (true) {
            val entry = synchronized(lock) { queue.takeNext() } ?: break
            _activeItemId.value = entry.storageItemId
            _progress.value = 0.0
            publishState()
            val job = async { runDownload(entry) }
            activeJob = job
            val outcome = try {
                job.await()
            } catch (e: CancellationException) {
                if (!currentCoroutineContext().isActive) {
                    // Worker gestoppt (Constraints, System): Eintrag bleibt, WIP sichert den Stand.
                    synchronized(lock) { queue.requeueActiveAtFront() }
                    activeJob = null
                    activeClient = null
                    _activeItemId.value = null
                    publishState()
                    throw e
                }
                Outcome.Interrupted
            }
            activeJob = null
            activeClient = null
            val cancelledByUser = synchronized(lock) {
                queue.finishActive()
                userCancelled.remove(entry.storageItemId)
            }
            persistQueue()
            when {
                outcome == Outcome.Success -> {
                    _activeItemId.value = null
                    _progress.value = 1.0
                    _completedDownloadCount.value += 1
                    notifyFinished(entry.storageItemId, true)
                }
                cancelledByUser || outcome == Outcome.Interrupted -> {
                    _activeItemId.value = null
                    _progress.value = 0.0
                }
                else -> {
                    deleteDownload(entry.storageItemId)
                    _activeItemId.value = null
                    _progress.value = 0.0
                    notifyFinished(entry.storageItemId, false)
                }
            }
            publishState()
        }
    }

    private fun notifyFinished(storageItemId: String, ok: Boolean) {
        runCatching { host?.onDownloadFinished(storageItemId, ok) }
        _completions.tryEmit(DownloadCompletion(storageItemId, ok))
    }

    private enum class Outcome { Success, Interrupted, Failed }

    /** Aufgelöste Tracks + Session für einen Lauf (iOS: `DownloadTrackResolution`). */
    private data class TrackResolution(
        val book: AbsBook,
        val tracks: List<AbsAudioTrack>,
        val streamSessionId: String,
        val ownsPlaySession: Boolean,
        val serverSession: AbsPlaySession?,
    )

    /** iOS: `resolveDownloadTracks` — Bücher direkt per `ino`, sonst / Podcasts über eine Play-Session. */
    private suspend fun resolveDownloadTracks(client: AbsApiClient, record: QueuedDownloadRecord): TrackResolution {
        val episodeId = record.episodeId
        val isPodcastEpisode = episodeId != null
        var workingBook = record.book
        var sorted = workingBook.media.tracks.orEmpty().sortedBy { it.index }
        val reuseSid = record.reusePlaySessionId?.swiftTrim()?.ifEmpty { null }
        if (reuseSid != null) {
            val reused = record.reusePlaySessionTracks.orEmpty().sortedBy { it.index }
            if (reused.isNotEmpty()) return TrackResolution(workingBook, reused, reuseSid, false, null)
            // Parallele Session ohne Track-Liste: bei Podcast kein zweites `POST …/play`.
            if (isPodcastEpisode) throw PlaybackNoTracksException()
        }
        if (!isPodcastEpisode && sorted.isEmpty()) {
            workingBook = client.item(workingBook.id, expanded = true)
            sorted = workingBook.media.tracks.orEmpty().sortedBy { it.index }
        }
        if (isPodcastEpisode) {
            val session = client.startPlaySession(workingBook.id, episodeId, PlaybackController.stableDeviceId(), PlaybackController.appVersion())
            val sessionTracks = session.audioTracks.orEmpty().sortedBy { it.index }
            if (sessionTracks.isEmpty()) throw PlaybackNoTracksException()
            return TrackResolution(workingBook, sessionTracks, session.id, true, session)
        }
        if (sorted.isNotEmpty() && sorted.all { !it.ino.isNullOrBlank() }) {
            return TrackResolution(workingBook, sorted, "", false, null)
        }
        val session = client.startPlaySession(workingBook.id, null, PlaybackController.stableDeviceId(), PlaybackController.appVersion())
        val sessionTracks = session.audioTracks.orEmpty().sortedBy { it.index }
        val tracks = sessionTracks.ifEmpty { sorted }
        if (tracks.isEmpty()) throw PlaybackNoTracksException()
        return TrackResolution(workingBook, tracks, session.id, true, session)
    }

    /** Ordner vorbereiten: WIP-Stand übernehmen oder Reste löschen (iOS: Disk-I/O off-Main). */
    private fun prepareFolder(id: String, episodeId: String?): Pair<File, Set<Int>> {
        val root = downloadsRoot().apply { mkdirs() }
        val itemDir = File(root, id)
        var resume = emptySet<Int>()
        if (itemDir.exists() && AbsDownloadManifest.load(itemDir) == null) {
            val wip = loadWip(itemDir)
            if (wip != null && wip.storageItemId == id && (wip.episodeId ?: "") == (episodeId ?: "") &&
                wip.completedTrackIndexes.isNotEmpty()
            ) {
                resume = wip.completedTrackIndexes.toSet()
            } else {
                itemDir.deleteRecursively()
            }
        } else if (itemDir.exists()) {
            itemDir.deleteRecursively()
        }
        itemDir.mkdirs()
        return itemDir to resume
    }

    private fun loadWip(folder: File): DownloadWip? =
        runCatching { AbsJson.decoder.decodeFromString(DownloadWip.serializer(), File(folder, DownloadWip.FILENAME).readText()) }.getOrNull()

    private fun saveWip(wip: DownloadWip, folder: File) {
        runCatching {
            val tmp = File(folder, DownloadWip.FILENAME + ".tmp")
            tmp.writeText(AbsJson.encoder.encodeToString(DownloadWip.serializer(), wip))
            tmp.renameTo(File(folder, DownloadWip.FILENAME))
        }
    }

    /** iOS: `runDownload` — ein Lauf; Fehler → [Outcome.Failed], Abbruch → [CancellationException]. */
    private suspend fun runDownload(record: QueuedDownloadRecord): Outcome {
        val id = record.storageItemId
        val client = host?.apiClient ?: return Outcome.Failed
        activeClient = client
        var ownsPlaySession = false
        var streamSessionId = ""
        try {
            val (folder, resumeCompletedInitial) = withContext(Dispatchers.IO) { prepareFolder(id, record.episodeId) }
            val resumeCompleted = resumeCompletedInitial.toMutableSet()
            val resolved = resolveDownloadTracks(client, record)
            val downloadBook = resolved.book
            val sorted = resolved.tracks
            streamSessionId = resolved.streamSessionId
            ownsPlaySession = resolved.ownsPlaySession

            val weights = DownloadProgressWeights.weights(sorted)
            val sumW = DownloadProgressWeights.sum(weights)
            var doneW = sorted.indices.filter { sorted[it].index in resumeCompleted }.sumOf { weights[it] }
            var savedAudioExtension: String? = null
            var wip = DownloadWip(id, downloadBook.id, record.episodeId, resumeCompleted.sorted())

            for ((i, tr) in sorted.withIndex()) {
                currentCoroutineContext().ensureActive()
                if (tr.index in resumeCompleted) {
                    _progress.value = minOf(1.0, doneW / sumW)
                    continue
                }
                _progress.value = doneW / sumW
                val suggested = File(folder, PlaybackController.trackFilename(tr.index))
                val trackWeight = weights[i]
                val baseDoneW = doneW
                var lastEmit = 0L
                val sink: (Double) -> Unit = { fraction ->
                    val now = System.currentTimeMillis()
                    if (now - lastEmit >= INTRA_TRACK_EMIT_INTERVAL_MS) {
                        lastEmit = now
                        _progress.value = DownloadProgressWeights.fraction(baseDoneW, trackWeight, fraction, sumW)
                    }
                }
                val ino = tr.ino
                val url = if (!ino.isNullOrEmpty()) {
                    client.itemFileDownloadURL(downloadBook.id, ino)
                } else {
                    if (streamSessionId.isEmpty()) throw PlaybackNoTracksException()
                    client.publicStreamURL(streamSessionId, tr.index)
                }
                val finalFile = client.downloadAuthenticatedFile(url, suggested, TRACK_DOWNLOAD_MAX_ATTEMPTS, sink)
                if (savedAudioExtension == null) savedAudioExtension = finalFile.extension.lowercase()
                doneW += weights[i]
                _progress.value = minOf(1.0, doneW / sumW)
                resumeCompleted.add(tr.index)
                wip = wip.copy(completedTrackIndexes = resumeCompleted.sorted())
                withContext(Dispatchers.IO) { saveWip(wip, folder) }
            }

            if (savedAudioExtension == null) {
                sorted.firstOrNull()?.let { first ->
                    PlaybackController.resolvedLocalTrackFile(folder, first.index, null)?.extension?.lowercase()
                        ?.takeIf { it.isNotEmpty() }?.let { savedAudioExtension = it }
                }
            }
            val serverSession = resolved.serverSession
            val totalDur = serverSession?.duration?.takeIf { it > 0 } ?: downloadBook.media.duration?.takeIf { it > 0 }
            val chapterSource: List<AbsChapter>? = downloadBook.media.chapters?.takeIf { it.isNotEmpty() }
                ?: serverSession?.chapters?.takeIf { it.isNotEmpty() }
                ?: serverSession?.libraryItem?.media?.chapters?.takeIf { it.isNotEmpty() }
            val manifest = AbsDownloadManifest(
                format = 1,
                libraryItemId = downloadBook.id,
                episodeId = record.episodeId,
                libraryId = downloadBook.libraryId,
                displayTitle = downloadBook.displayTitle,
                displayAuthor = downloadBook.displayAuthors,
                playSessionId = streamSessionId,
                savedAtEpoch = System.currentTimeMillis() / 1000.0,
                audioFileExtension = savedAudioExtension,
                totalDuration = totalDur,
                tracks = sorted.map { AbsDownloadManifest.Track(it.index, it.startOffset, it.duration, it.title) },
                chapters = chapterSource?.map { AbsDownloadManifest.Chapter.from(it) },
            )
            withContext(Dispatchers.IO) {
                manifest.write(folder)
                File(folder, DownloadWip.FILENAME).delete()
            }
            if (ownsPlaySession) runCatching { client.closePlaySession(streamSessionId) }
            return Outcome.Success
        } catch (e: CancellationException) {
            if (ownsPlaySession && streamSessionId.isNotEmpty()) closeQuietly(client, streamSessionId)
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "download $id failed: ${e.message}")
            if (ownsPlaySession && streamSessionId.isNotEmpty()) closeQuietly(client, streamSessionId)
            // OkHttp-Abbruch (`cancelInFlightDownloads`) ≙ `URLError.cancelled` → unterbrochen, nicht fehlgeschlagen.
            if (e is java.io.IOException && e.message == "Canceled") return Outcome.Interrupted
            return Outcome.Failed
        }
    }

    /** Session-Close nach Abbruch/Fehler darf den beendeten Lauf überleben (iOS: `try? await …close`). */
    private val closeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private fun closeQuietly(client: AbsApiClient, sessionId: String) {
        closeScope.launch { runCatching { client.closePlaySession(sessionId) } }
    }

    // MARK: - Persistenz / Zustand

    private fun publishState() {
        _queuedItemIds.value = synchronized(lock) { queue.queuedIds }
    }

    private val recordsSerializer = ListSerializer(QueuedDownloadRecord.serializer())

    private fun queueFile(): File = File(ctx().filesDir, QUEUE_FILE)

    private fun persistQueue() {
        if (!::appContext.isInitialized) return
        val snapshot = synchronized(lock) { queue.snapshot() }
        runCatching {
            val f = queueFile()
            if (snapshot.isEmpty()) {
                f.delete()
            } else {
                val tmp = File(f.parentFile, "$QUEUE_FILE.tmp")
                tmp.writeText(AbsJson.encoder.encodeToString(recordsSerializer, snapshot))
                if (!tmp.renameTo(f)) {
                    tmp.copyTo(f, overwrite = true)
                    tmp.delete()
                }
            }
        }.onFailure { Log.w(TAG, "persist queue failed: ${it.message}") }
    }

    private fun loadPersistedQueue(): List<QueuedDownloadRecord> =
        runCatching { AbsJson.decoder.decodeFromString(recordsSerializer, queueFile().readText()) }.getOrDefault(emptyList())
}
