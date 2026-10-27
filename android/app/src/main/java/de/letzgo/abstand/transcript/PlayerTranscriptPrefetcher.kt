package de.letzgo.abstand.transcript

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.logic.PlayerTranscriptLibrary
import de.letzgo.abstand.logic.PlayerTranscriptTrackSource
import de.letzgo.abstand.logic.speech.SpeechModelStore
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.player.TrackTimeline
import de.letzgo.abstand.data.AbsAudioTrack
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext

/** iOS: `PlayerTranscriptJob` — ein heruntergeladener Titel, für den Transkripte vorproduziert werden. */
data class PlayerTranscriptJob(
    /** Schlüssel der Transkriptdateien (= Download-Ordner; bei Folgen `<Show>-<Folge>`). */
    val storageId: String,
    val title: String,
    val languageTag: String?,
    val sources: List<PlayerTranscriptTrackSource>,
)

/**
 * iOS: `PlayerTranscriptPrefetcher` — produziert Read-Along-Transkripte für heruntergeladene Titel im
 * Voraus: der laufende Titel zuerst (ab Abspielposition), dann alle anderen Downloads. Läuft im
 * Vordergrund (App sichtbar) und per WorkManager (iOS `BGProcessingTask`) als Unique Work
 * [BACKGROUND_WORK_NAME] nur am Strom und bei nicht niedrigem Akku.
 *
 * Grenzen wie iOS: Pause im Energiesparmodus, bei Überhitzung und solange Teleprompter/Recap
 * produzieren ([PlayerTranscriptLibrary.isPriorityWorkActive]); nur Buchsprache, nur installierte
 * Modelle (kein Download im Hintergrund).
 */
object PlayerTranscriptPrefetcher {
    const val BACKGROUND_WORK_NAME = "de.letzgo.abstand.transcripts"
    private const val TAG = "TranscriptPrefetch"
    private const val IDLE_RECHECK_MS = 5_000L

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()
    private val _preparedTracks = MutableStateFlow(0)
    val preparedTracks: StateFlow<Int> = _preparedTracks.asStateFlow()
    private val _totalTracks = MutableStateFlow(0)
    val totalTracks: StateFlow<Int> = _totalTracks.asStateFlow()
    /** Grund der Pause für die Einstellungen (`null` = läuft oder nichts zu tun). */
    private val _pausedReason = MutableStateFlow<String?>(null)
    val pausedReason: StateFlow<String?> = _pausedReason.asStateFlow()
    /** Titel, der gerade vorbereitet wird (Einstellungen). */
    private val _currentJobTitle = MutableStateFlow<String?>(null)
    val currentJobTitle: StateFlow<String?> = _currentJobTitle.asStateFlow()

    /**
     * iOS: `configure(player:jobs:)` / `AppModel.downloadedTranscriptJobs()`. Standard: alle fertigen
     * Downloads des aktiven Accounts aus den `download.json`-Manifesten. Austauschbar (Tests/Integration).
     */
    @Volatile
    var jobsProvider: suspend (Context) -> List<PlayerTranscriptJob> = { downloadedTranscriptJobs() }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val runMutex = Mutex()
    private var task: Job? = null
    private var runGeneration = 0
    @Volatile private var installed = false
    private lateinit var appContext: Context

    // MARK: - Öffentliche API (Einstellungen)

    /** iOS: `AppModel.readAlongPrefetchEnabled` (Standard an). */
    fun isPrefetchEnabled(): Boolean = Prefs.bool(Keys.readAlongPrefetch, true)

    /** Einstellung geändert: an → Lauf bewerten, aus → stoppen und Hintergrundarbeit verwerfen. */
    fun setPrefetchEnabled(context: Context, enabled: Boolean) {
        install(context)
        val old = isPrefetchEnabled()
        Prefs.setBool(Keys.readAlongPrefetch, enabled)
        if (old == enabled && task != null) return
        if (enabled) scheduleIfNeeded() else {
            stop()
            WorkManager.getInstance(appContext).cancelUniqueWork(BACKGROUND_WORK_NAME)
        }
    }

    /**
     * Einmal beim App-Start (idempotent): Vordergrund-Lauf an den Prozess-Lebenszyklus koppeln,
     * beim Wechsel in den Hintergrund WorkManager-Arbeit anfordern (iOS: `abstandApp`-scenePhase,
     * `registerBackgroundTask`), bei Medienwechsel neu aufsetzen (iOS: `onActiveMediaPrepared`).
     */
    fun install(context: Context) {
        if (installed) return
        synchronized(this) {
            if (installed) return
            appContext = context.applicationContext
            installed = true
        }
        scope.launch {
            ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) = scheduleIfNeeded()
                override fun onStop(owner: LifecycleOwner) {
                    stop()
                    scheduleBackgroundProcessingIfNeeded()
                }
            })
            val player = PlaybackController.shared(appContext)
            combine(player.activeBook, player.activePlaybackEpisodeId) { book, ep ->
                book?.let { PlaybackTranscription.storageId(it.id, ep) }
            }.distinctUntilChanged().drop(1).collect {
                // Neues Medium: Vorproduktion am neuen Titel neu aufsetzen.
                if (!isPrefetchEnabled()) return@collect
                stop()
                scheduleIfNeeded()
            }
        }
    }

    /** iOS: `scheduleIfNeeded` — nur im Vordergrund (Hintergrund läuft über den Worker). */
    fun scheduleIfNeeded() {
        if (!installed || !isPrefetchEnabled() || task != null) return
        if (!ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) return
        runGeneration += 1
        val generation = runGeneration
        task = scope.launch {
            try {
                runMutex.withLock { runPrefetch(generation) }
            } catch (c: CancellationException) {
                throw c
            } catch (t: Throwable) {
                Log.w(TAG, "prefetch run failed", t)
            } finally {
                if (runGeneration == generation) {
                    task = null
                    _isRunning.value = false
                    _pausedReason.value = null
                    _currentJobTitle.value = null
                }
            }
        }
    }

    /** iOS: `stop()` — App in den Hintergrund, Buchwechsel, Einstellung aus. */
    fun stop() {
        runGeneration += 1
        task?.cancel()
        task = null
        _isRunning.value = false
        _pausedReason.value = null
    }

    /**
     * iOS: `scheduleBackgroundProcessingIfNeeded` — WorkManager um Rechenzeit bitten, nur am Strom
     * (und Akku nicht niedrig), typischerweise nachts beim Laden.
     */
    fun scheduleBackgroundProcessingIfNeeded() {
        if (!installed || !isPrefetchEnabled()) return
        val request = OneTimeWorkRequestBuilder<TranscriptPrefetchWorker>()
            .setConstraints(BackgroundConstraints.constraints())
            .setBackoffCriteria(BackoffPolicy.LINEAR, 15, TimeUnit.MINUTES)
            .build()
        WorkManager.getInstance(appContext).enqueueUniqueWork(BACKGROUND_WORK_NAME, ExistingWorkPolicy.KEEP, request)
    }

    /** Lauf im WorkManager-Worker. `true` = Arbeit offen (später weitermachen). */
    internal suspend fun runInBackground(context: Context): Boolean {
        install(context)
        if (!isPrefetchEnabled()) return false
        withContext(Dispatchers.Main) { stop() }
        return withContext(Dispatchers.Main.immediate) {
            runGeneration += 1
            val generation = runGeneration
            try {
                runMutex.withLock { runPrefetch(generation) }
            } finally {
                if (runGeneration == generation) {
                    _isRunning.value = false
                    _pausedReason.value = null
                    _currentJobTitle.value = null
                }
            }
        }
    }

    // MARK: - Lauf

    /** Rückgabe: `true`, wenn Tracks unvollständig blieben (iOS `runLeftWorkPending`). */
    private suspend fun runPrefetch(generation: Int): Boolean {
        _preparedTracks.value = 0
        _totalTracks.value = 0
        var leftWork = false
        PlayerTranscriptLibrary.activeAccount = TranscriptAccount.current() ?: return false

        // Reihenfolge: laufender Titel (ab Abspielposition), dann alle anderen Downloads.
        val player = PlaybackController.shared(appContext)
        val active: Pair<PlayerTranscriptJob, Double>? = run {
            val ready = withContext(Dispatchers.IO) { PlaybackTranscription.isReadAlongDownloadReady(player) }
            val activeId = PlaybackTranscription.transcriptionStorageId(player)
            if (!ready || activeId == null) return@run null
            val sources = PlaybackTranscription.localTranscriptionTrackSources(player)
            if (sources.isEmpty()) return@run null
            PlayerTranscriptJob(
                activeId, player.activeBook.value?.displayTitle ?: "",
                PlaybackTranscription.preferredTranscriptionLanguageTag(player), sources,
            ) to PlaybackTranscription.livePosition(player)
        }
        val others = withContext(Dispatchers.IO) { jobsProvider(appContext) }
        val jobs = PrefetchPlanner.orderJobs(active, others)
        if (jobs.isEmpty()) return false
        _totalTracks.value = jobs.sumOf { it.job.sources.size }

        val selectionByTag = HashMap<String, TranscriptionModelSelection.Selection?>()
        _isRunning.value = true
        for (planned in jobs) {
            if (!coroutineContext.isActive) return leftWork
            val tag = planned.job.languageTag ?: ""
            val selection = selectionByTag.getOrPut(tag) {
                TranscriptionModelSelection.prefetchSelection(planned.job.languageTag, { SpeechModelStore.isInstalled(appContext, it) })
            } ?: continue
            _currentJobTitle.value = planned.job.title.ifEmpty { null }
            for (step in PrefetchPlanner.trackOrder(planned)) {
                if (!coroutineContext.isActive) return leftWork
                var completed = prepare(planned.job.storageId, step.source, selection, step.from, generation)
                // Laufender Track: danach auch den Anfang vor der Hörposition (iOS gleich).
                if (completed && step.from > 0 && coroutineContext.isActive) {
                    completed = prepare(planned.job.storageId, step.source, selection, 0.0, generation)
                }
                if (!coroutineContext.isActive) return leftWork
                if (completed) _preparedTracks.value += 1 else leftWork = true
            }
        }
        _isRunning.value = false
        _pausedReason.value = null
        return leftWork
    }

    /** iOS: `prepare` — `true`, wenn der Track vollständig abgedeckt ist. */
    private suspend fun prepare(
        bookId: String,
        source: PlayerTranscriptTrackSource,
        selection: TranscriptionModelSelection.Selection,
        from: Double,
        generation: Int,
    ): Boolean {
        var cursor = from
        while (coroutineContext.isActive) {
            val gapStart = PlayerTranscriptLibrary.firstUncoveredTime(bookId, source, selection.localeIdentifier, cursor) ?: return true
            if (runGeneration != generation) return false
            // Vorrang und Gerätezustand vor jedem Abschnitt prüfen.
            val reason = blockingReason()
            if (reason != null) {
                _pausedReason.value = reason
                _isRunning.value = false
                delay(IDLE_RECHECK_MS)
                _isRunning.value = coroutineContext.isActive
                continue
            }
            _pausedReason.value = null
            try {
                // Nur die Lücke — am nächsten vorhandenen Segment aufhören (iOS gleich).
                val gapEnd = PlayerTranscriptLibrary.nextCoveredStart(bookId, source, selection.localeIdentifier, gapStart)
                val produced = PlayerTranscriptProduction.produceAndPersist(
                    appContext, bookId, source, selection.entry, selection.localeIdentifier, gapStart, gapEnd,
                ) {
                    // Ein Track läuft minutenlang — Pause greift sofort, nicht erst beim nächsten Track.
                    if (runGeneration != generation || blockingReason() != null) throw PauseSignal()
                }
                if (!(produced > gapStart + 0.5)) return true
                cursor = produced
            } catch (p: PauseSignal) {
                // Abschnitt abgebrochen (gesichert) — oben warten und an der Lücke weitermachen.
                if (runGeneration != generation) return false
                if (blockingReason() == null) delay(1_000)
            } catch (c: CancellationException) {
                throw c
            } catch (t: Throwable) {
                Log.w(TAG, "prefetch failed track=${source.trackIndex}", t)
                return false
            }
        }
        return false
    }

    /** Pause-Abbruch aus `onBatch` (kein echter Coroutine-Abbruch). */
    private class PauseSignal : Exception()

    /** `null`, wenn gearbeitet werden darf. */
    private fun blockingReason(): String? {
        val power = appContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return PrefetchPlanner.blockingReason(
            priorityWorkActive = PlayerTranscriptLibrary.isPriorityWorkActive,
            powerSaveMode = power?.isPowerSaveMode == true,
            thermalSevere = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                (power?.currentThermalStatus ?: 0) >= PowerManager.THERMAL_STATUS_SEVERE,
        )
    }

    // MARK: - Jobs aus Downloads

    /**
     * iOS: `AppModel.downloadedTranscriptJobs()` — je fertigem Download (aktiver Account) die lokalen
     * Tracks mit ihrer Lage im Hörbuch; Sprache aus Buch-Detail/LocalStore (bei Folgen: die Show).
     */
    suspend fun downloadedTranscriptJobs(): List<PlayerTranscriptJob> {
        val session = runCatching { AppModel.shared.session }.getOrNull() ?: return emptyList()
        val store = session.currentLocalLibraryStore()
        val libraryIds = session.libraries.value.map { it.id }.toSet()
        val jobs = ArrayList<PlayerTranscriptJob>()
        for (download in DownloadManager.scanDownloads()) {
            val manifest = download.manifest
            if (!PrefetchPlanner.belongsToActiveAccount(manifest.libraryId, libraryIds)) continue
            val sources = sourcesFromManifest(download.folder, manifest) ?: continue
            val book = runCatching { store?.fetchBookDetail(manifest.libraryItemId) ?: store?.fetchBook(manifest.libraryItemId) }.getOrNull()
            jobs.add(PlayerTranscriptJob(download.storageItemId, manifest.displayTitle ?: "", book?.media?.metadata?.language, sources))
        }
        return jobs
    }

    /** Track-Quellen eines Downloads (`null`, wenn eine Datei fehlt). */
    fun sourcesFromManifest(root: File, manifest: AbsDownloadManifest): List<PlayerTranscriptTrackSource>? {
        val tracks = manifest.tracks.map { AbsAudioTrack(it.index, it.startOffset, it.duration, it.title) }
        if (tracks.isEmpty()) return null
        val timeline = TrackTimeline(tracks)
        val sources = timeline.tracks.mapIndexedNotNull { position, track ->
            val file = PlaybackController.resolvedLocalTrackFile(root, track.index, manifest) ?: return@mapIndexedNotNull null
            PlayerTranscriptTrackSource(position, file.absolutePath, timeline.trackStarts[position], track.duration)
        }
        return sources.takeIf { it.size == tracks.size }
    }
}

/** Reine Planungsentscheidungen der Vorproduktion (JUnit-testbar). */
object PrefetchPlanner {
    data class PlannedJob(val job: PlayerTranscriptJob, val startGlobal: Double?)
    data class TrackStep(val source: PlayerTranscriptTrackSource, val from: Double)

    /** Laufender Titel zuerst (ab Abspielposition), dann alle anderen ohne Duplikat. */
    fun orderJobs(active: Pair<PlayerTranscriptJob, Double>?, others: List<PlayerTranscriptJob>): List<PlannedJob> {
        val out = ArrayList<PlannedJob>()
        if (active != null) out.add(PlannedJob(active.first, active.second))
        val activeId = active?.first?.storageId
        for (job in others) if (job.storageId != activeId) out.add(PlannedJob(job, null))
        return out
    }

    /**
     * iOS: aktueller Track ab Abspielposition, dann die folgenden, zuletzt der übersprungene Anfang;
     * alle anderen Tracks von vorn.
     */
    fun trackOrder(planned: PlannedJob): List<TrackStep> {
        val sources = planned.job.sources
        if (sources.isEmpty()) return emptyList()
        val g = planned.startGlobal
        val currentIndex = g?.let { t -> sources.indexOfFirst { t in it.globalRange } }?.takeIf { it >= 0 } ?: 0
        val ordered = sources.subList(currentIndex, sources.size) + sources.subList(0, currentIndex)
        val currentTrack = sources[currentIndex].trackIndex
        return ordered.map { source ->
            val from = if (g != null && source.trackIndex == currentTrack) maxOf(0.0, g - source.globalOffset) else 0.0
            TrackStep(source, from)
        }
    }

    /** iOS: `blockingReason()`. */
    fun blockingReason(priorityWorkActive: Boolean, powerSaveMode: Boolean, thermalSevere: Boolean): String? = when {
        priorityWorkActive -> "Paused while read along is preparing"
        powerSaveMode -> "Paused in Battery Saver"
        thermalSevere -> "Paused while the device is warm"
        else -> null
    }

    /**
     * iOS: `downloadManifestBelongsToActiveAccount` (vereinfacht): ohne Library-ID oder ohne bekannte
     * Bibliotheken zählt der Download, sonst nur bei passender Bibliothek.
     */
    fun belongsToActiveAccount(manifestLibraryId: String?, activeLibraryIds: Set<String>): Boolean {
        val lid = manifestLibraryId?.swiftTrim().orEmpty()
        if (lid.isEmpty() || activeLibraryIds.isEmpty()) return true
        return lid in activeLibraryIds
    }
}

/** WorkManager-Bedingungen (iOS: `requiresExternalPower = true`, kein Netz nötig). */
internal object BackgroundConstraints {
    fun constraints(): Constraints = Constraints.Builder()
        .setRequiresCharging(true)
        .setRequiresBatteryNotLow(true)
        .build()
}

/**
 * iOS: `BGProcessingTask` `de.letzgo.abstand.transcripts`. Nicht im Vordergrunddienst: WorkManager
 * stoppt nach ~10 Minuten; der Zwischenstand ist gesichert und `retry` setzt später fort.
 */
class TranscriptPrefetchWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val leftWork = try {
            PlayerTranscriptPrefetcher.runInBackground(applicationContext)
        } catch (c: CancellationException) {
            throw c
        } catch (t: Throwable) {
            Log.w("TranscriptPrefetch", "background run failed", t)
            true
        }
        return if (leftWork && PlayerTranscriptPrefetcher.isPrefetchEnabled()) Result.retry() else Result.success()
    }
}
