@file:OptIn(UnstableApi::class)

package de.letzgo.abstand.player

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import de.letzgo.abstand.BuildConfig
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsApiError
import de.letzgo.abstand.data.AbsAudioTrack
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsChapter
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsPlaySession
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.data.Net
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.UnknownHostException
import java.util.UUID
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** iOS: `ABSPlaybackError.noTracks`. */
class PlaybackNoTracksException : Exception("No playable audio tracks.")

/**
 * iOS: `PlaybackController` — ExoPlayer-Wiedergabe für Hörbücher und Podcast-Folgen, per Play-Session
 * (`/api/items/:id/play[/:episodeId]`) gestreamt oder lokal aus einem `download.json`-Manifest.
 * Tick → Hörzeit-Akkumulation → `syncPlaySession` (alle 20 s, bei Pause/Abriss sofort), Sleep-Timer,
 * Kapitel, Geschwindigkeit, Skip-Intervalle, EQ.
 *
 * Unterschiede zur iOS-Mechanik (gleiches Verhalten nach außen):
 * - Alle Spuren liegen als ExoPlayer-Playlist vor (lückenloser Trackwechsel durch ExoPlayer statt
 *   `advanceToNextTrack` + Background-Task). Die globale Zeitachse ([TrackTimeline]) ist dieselbe;
 *   nach außen (Benachrichtigung, Sperrbildschirm, Android Auto) zeigt [BookTimelinePlayer] das Buch
 *   als **ein** Medium mit Gesamtdauer — wie `MPNowPlayingInfo` auf iOS.
 * - `AudioSessionController` entfällt: Audio-Fokus und „Becoming noisy“ übernimmt ExoPlayer
 *   (`handleAudioFocus = true`, `setHandleAudioBecomingNoisy`). Fokusverlust/Kopfhörer ziehen
 *   laufen über [syncPlayingStateFromEngine] wie die iOS-Interruptions.
 * - Statt `recoverStaleRemotePlaybackIfNeeded`-Kickstart nach `play()` reagiert der Controller auf
 *   ExoPlayer-Fehler: Stream neu binden bzw. Play-Session neu anlegen.
 *
 * Läuft ausschließlich auf dem Main-Thread (ExoPlayer-Looper); `suspend`-Einstiege wechseln selbst dorthin.
 * Zustand als `StateFlow` mit iOS-Namen, damit Mini-Player / Now Playing 1:1 portiert werden können.
 */
class PlaybackController private constructor(private val appContext: Context) {

    // MARK: - Öffentlicher Zustand (iOS `@Published`)

    private val _activeBook = MutableStateFlow<AbsBook?>(null)
    val activeBook: StateFlow<AbsBook?> = _activeBook.asStateFlow()

    /** Gesetzte Podcast-Folge (`play/.../episodeId`); bei Hörbüchern `null`. */
    private val _activePlaybackEpisodeId = MutableStateFlow<String?>(null)
    val activePlaybackEpisodeId: StateFlow<String?> = _activePlaybackEpisodeId.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    /** Laufende globale Position in Sekunden — aktualisiert je Tick (~0,35 s), Seek und Laden. */
    private val _globalPosition = MutableStateFlow(0.0)
    val globalPosition: StateFlow<Double> = _globalPosition.asStateFlow()

    private val _totalDuration = MutableStateFlow(0.0)
    val totalDuration: StateFlow<Double> = _totalDuration.asStateFlow()

    private val _isBuffering = MutableStateFlow(false)
    val isBuffering: StateFlow<Boolean> = _isBuffering.asStateFlow()

    /** Letzter Wiedergabefehler (Laden/Stream), `null` sobald wieder abgespielt wird. */
    private val _playbackError = MutableStateFlow<String?>(null)
    val playbackError: StateFlow<String?> = _playbackError.asStateFlow()

    private val sleepTimer = SleepTimer()
    /** Ende des Minuten-Timers in ms seit 1970 (nur während der Wiedergabe). */
    val sleepEndDate: StateFlow<Long?> = sleepTimer.sleepEndDate
    val sleepTimerMode: StateFlow<SleepTimerMode> = sleepTimer.sleepTimerMode

    /** Leere Mini-Player-Leiste („Nothing playing“) ohne aktives Medium. */
    private val _showMiniPlayerPlaceholder = MutableStateFlow(false)
    val showMiniPlayerPlaceholder: StateFlow<Boolean> = _showMiniPlayerPlaceholder.asStateFlow()

    private val _chapterCount = MutableStateFlow(0)
    val chapterCount: StateFlow<Int> = _chapterCount.asStateFlow()

    /** 1-basierter Index des aktuellen Kapitels, `0` wenn keine Kapitel. */
    private val _currentChapterOrdinal = MutableStateFlow(0)
    val currentChapterOrdinal: StateFlow<Int> = _currentChapterOrdinal.asStateFlow()

    private val _currentChapterTitle = MutableStateFlow("")
    val currentChapterTitle: StateFlow<String> = _currentChapterTitle.asStateFlow()

    private val _playbackRate = MutableStateFlow(PlaybackRates.fromSaved(Prefs.double(PLAYBACK_RATE_KEY, 0.0)))
    val playbackRate: StateFlow<Float> = _playbackRate.asStateFlow()

    private val _eqPreset = MutableStateFlow(AudioEQPreset.loadSaved())
    val eqPreset: StateFlow<AudioEQPreset> = _eqPreset.asStateFlow()

    private val _skipBackwardSeconds = MutableStateFlow(loadSkipSeconds(SKIP_BACKWARD_KEY, PlaybackSkipDefaults.backwardSeconds))
    val skipBackwardSeconds: StateFlow<Int> = _skipBackwardSeconds.asStateFlow()

    private val _skipForwardSeconds = MutableStateFlow(loadSkipSeconds(SKIP_FORWARD_KEY, PlaybackSkipDefaults.forwardSeconds))
    val skipForwardSeconds: StateFlow<Int> = _skipForwardSeconds.asStateFlow()

    // MARK: - Callbacks (iOS: von AppModel gesetzt — hier über PlaybackHostBridge)

    /** Neues Medium fertig geladen (lokale Wiedergabe, z. B. für Transkript-Vorproduktion). */
    var onActiveMediaPrepared: (() -> Unit)? = null
    /** Jeder Player-Tick (Smart-Download, periodisches lokales Sichern). */
    var onPlaybackTick: (() -> Unit)? = null
    /** Letzter Track eines Hörbuchs zu Ende (keine Podcast-Folge). */
    var onAudiobookPlaybackCompleted: (() -> Unit)? = null
    /** Letzter Track einer Podcast-Folge zu Ende. */
    var onPodcastEpisodePlaybackCompleted: (() -> Unit)? = null
    /** Lokale Download-Wiedergabe ohne Play-Session: (timeListened, position, duration). */
    var onLocalPlaybackWithoutSessionSync: (suspend (Int, Double, Double) -> Unit)? = null

    // MARK: - Interner Zustand

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    /** iOS: unstrukturierte `Task`s für Close/Sync nach dem Abriss — überleben den Abriss. */
    private val detachedScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var exo: ExoPlayer? = null
    private val eqProcessor = BiquadEqAudioProcessor(_eqPreset.value)
    private var sessionController: com.google.common.util.concurrent.ListenableFuture<MediaController>? = null

    private var playSessionId: String? = null
    private var apiClient: AbsApiClient? = null

    private var timeline = TrackTimeline.EMPTY
    private var chapters = ChapterTimeline.EMPTY
    private val listenTime = ListenTimeAccumulator()

    /** Zählt `playBook`-Aufrufe — ein überholter Aufruf verwirft seine Ergebnisse. */
    private var loadGeneration = 0
    private var syncJob: Job? = null
    private var tickJob: Job? = null
    private var sleepWakeJob: Job? = null

    private var localRoot: File? = null
    /** Nach Laden: sofort abspielen oder nur positionieren (Launch-Restore). */
    private var shouldAutoPlayAfterLoad = true
    /** Wie Absorb `_playFromLocal`: Session starten wenn online (nicht im Offline-Home-Modus). */
    private var attemptServerPlaySessionForLocal = true
    /** Automatische Stream-Wiederherstellungen seit dem letzten `STATE_READY` (Fehlerschleifen begrenzen). */
    private var errorRecoveryAttempts = 0

    private var sessionPlayerOrNull: BookTimelinePlayer? = null

    /** Für die Session (Benachrichtigung, Sperrbildschirm, Android Auto) — erzeugt den ExoPlayer bei Bedarf. */
    val sessionPlayer: BookTimelinePlayer
        get() = sessionPlayerOrNull ?: BookTimelinePlayer(ensurePlayer(), this).also { sessionPlayerOrNull = it }

    init {
        // iOS: `$sleepEndDate`-Sink → Wanduhr-Wake neu planen.
        scope.launch {
            sleepTimer.sleepEndDate.collect { end -> rescheduleSleepWake(end) }
        }
    }

    // MARK: - Abgeleitete Werte

    /** `true`, solange ein Audiobookshelf-Stream mit Session-Sync aktiv ist. */
    val isRemotePlaySessionActive: Boolean get() = playSessionId != null

    /** `true`, wenn die Wiedergabe aus einem lokalen Download-Ordner läuft. */
    val isPlaybackFromOfflineDownload: Boolean get() = localRoot != null

    /** Wie `playBook`: alle Tracks lokal — sonst Stream trotz Download-Ordner. */
    val isUsingLocalTrackFiles: Boolean
        get() {
            val root = localRoot ?: return false
            val book = _activeBook.value ?: return false
            return allTracksPresent(root, book)
        }

    /** Transkription (iOS: `tracks`/`trackStarts`/`localRoot`) — Logik in `transcript/PlaybackTranscriptionSupport.kt`. */
    internal val transcriptionTimeline: TrackTimeline get() = timeline
    internal val transcriptionLocalRoot: File? get() = localRoot

    /** Floating-Bar Play/Pause: Player wirklich bereit (nicht nur `playBook` zurückgekehrt). */
    val isPlaybackControlsReady: Boolean
        get() {
            if (_activeBook.value == null) return true
            val p = exo ?: return false
            if (p.mediaItemCount == 0) return false
            if (p.playbackState == Player.STATE_IDLE || p.playbackState == Player.STATE_BUFFERING) return false
            return !_isBuffering.value
        }

    /** Countdown für die UI in Sekunden — bei Pause konstant; Kapitel-Timer → `null`. */
    fun sleepTimerDisplaySeconds(): Double? = sleepTimer.displaySeconds()

    val isSleepTimerActive: Boolean get() = sleepTimer.isActive

    val canSkipToPreviousChapter: Boolean get() = chapters.canSkipToPreviousChapter(_globalPosition.value)
    val canSkipToNextChapter: Boolean get() = chapters.canSkipToNextChapter(_globalPosition.value)

    /** Kapitel 1…n (nach `start` sortiert). */
    val sortedChapters: List<AbsChapter> get() = chapters.sortedChapters

    /** Relative Kapitelgrenzen (0…1) für Markierungen im Fortschrittsbalken. */
    val chapterMarkerFractions: List<Double> get() = chapters.chapterMarkerFractions(_totalDuration.value)

    // MARK: - Mini-Player

    fun setMiniPlayerPlaceholder(show: Boolean) {
        _showMiniPlayerPlaceholder.value = show
    }

    // MARK: - Sleep-Timer (iOS: PlaybackController + AppModel.applySleepTimer)

    fun clearSleepTimer() {
        sleepTimer.clear()
        applySleepTimerFadeVolume()
    }

    /** AppModel setzt den Modus vor `applySleepTimerRemaining`. */
    fun setSleepTimerMode(mode: SleepTimerMode) = sleepTimer.setMode(mode)

    fun applySleepTimerRemaining(seconds: Double) {
        sleepTimer.applyRemaining(seconds, _isPlaying.value)
    }

    fun applySleepTimerChapterTarget(targetIndex: Int) {
        sleepTimer.applyChapterTarget(targetIndex)
    }

    /** iOS: `AppModel.applySleepTimer(seconds:)`. */
    fun applySleepTimer(seconds: Double?) {
        if (seconds != null && seconds > 0) {
            applySleepTimerRemaining(seconds)
        } else {
            clearSleepTimer()
            sleepTimer.setMode(SleepTimerMode.Off)
        }
    }

    /** iOS: `AppModel.applySleepTimer(minutes:)` — erneutes Wählen startet den Countdown neu. */
    fun applySleepTimer(minutes: Int) {
        if (minutes <= 0) {
            applySleepTimer(seconds = null)
        } else {
            sleepTimer.setMode(SleepTimerMode.Minutes(minutes))
            applySleepTimer(seconds = minutes * 60.0)
        }
    }

    /** iOS: `AppModel.applySleepTimer(chapters:)` — `false`, wenn kein Ziel-Kapitel existiert. */
    fun applySleepTimerChapters(count: Int): Boolean {
        if (count < 1) return false
        val target = chapterTargetIndex(count) ?: return false
        sleepTimer.setMode(SleepTimerMode.Chapters(count))
        applySleepTimerChapterTarget(target)
        return isSleepTimerActive
    }

    /** iOS: `sleepTimerSnapshot()` — vor einem Player-Neuaufbau (Umschalten auf den Download) sichern. */
    fun sleepTimerSnapshot(): SleepTimer.Snapshot? = sleepTimer.snapshot()

    /** iOS: `restoreSleepTimer(_:)` — nach `playBook` wieder anwenden (`tearDownPlayer` hat ihn gelöscht). */
    fun restoreSleepTimer(snapshot: SleepTimer.Snapshot) {
        sleepTimer.restore(snapshot, _isPlaying.value)
        applySleepTimerFadeVolume()
    }

    /** Auswahl „Ende von n Kapiteln“ fürs Sleep-Menü. */
    fun sleepTimerChapterOptions(): List<Int> =
        SleepTimerMetrics.chapterOptions(_chapterCount.value, maxSleepChapterCount())

    /** Wanduhr-basiert: funktioniert auch bei pausiertem Player. */
    private fun rescheduleSleepWake(end: Long?) {
        sleepWakeJob?.cancel()
        sleepWakeJob = null
        if (end == null) return
        val delayMs = end - System.currentTimeMillis()
        if (delayMs <= 0) {
            sleepTimer.markExpired()
            pause()
            return
        }
        sleepWakeJob = scope.launch {
            delay(max(1L, delayMs))
            if (sleepTimer.sleepEndDate.value != end) return@launch
            sleepTimer.markExpired()
            pause()
        }
    }

    private fun applySleepTimerFadeVolume() {
        val p = exo ?: return
        val target = SleepTimer.fadeVolume(sleepTimerSecondsUntilStop())
        if (abs(p.volume - target) > 0.001f) p.volume = target
    }

    private fun sleepTimerSecondsUntilStop(): Double? {
        val target = sleepTimer.chapterTarget
        val chapterEnd = if (target != null && target < chapters.count) chapters.chapterEndTime(target, _totalDuration.value) else null
        return sleepTimer.secondsUntilStop(_isPlaying.value, chapterEnd, playbackGlobalPosition(), _playbackRate.value)
    }

    // MARK: - App-Lebenszyklus

    /** iOS: `handleReturnToForeground` — UI an Engine angleichen, Sleep-Timer nachziehen. */
    fun handleReturnToForeground() {
        refreshPlaybackStateFromEngine()
        if (sleepTimer.reconcileAfterBackground(_isPlaying.value)) pause()
    }

    /** iOS: `refreshPlaybackStateFromEngine`. */
    fun refreshPlaybackStateFromEngine() {
        val p = exo
        if (p == null || p.mediaItemCount == 0) {
            if (_isPlaying.value) _isPlaying.value = false
            return
        }
        syncPlayingStateFromEngine()
    }

    // MARK: - Skip-Intervalle

    fun setSkipBackwardSeconds(value: Int) {
        val clamped = PlaybackSkipDefaults.clamped(value, PlaybackSkipDefaults.backwardSeconds)
        if (clamped == _skipBackwardSeconds.value) return
        _skipBackwardSeconds.value = clamped
        Prefs.setInt(SKIP_BACKWARD_KEY, clamped)
        sessionPlayerOrNull?.notifySeekIncrementsChanged()
    }

    fun setSkipForwardSeconds(value: Int) {
        val clamped = PlaybackSkipDefaults.clamped(value, PlaybackSkipDefaults.forwardSeconds)
        if (clamped == _skipForwardSeconds.value) return
        _skipForwardSeconds.value = clamped
        Prefs.setInt(SKIP_FORWARD_KEY, clamped)
        sessionPlayerOrNull?.notifySeekIncrementsChanged()
    }

    // MARK: - Session-Wiederverwendung für Downloads

    /** Gleiche Remote-Session für parallele Downloads — vermeidet ein zweites `POST …/play`. */
    fun playSessionIdForReuseWhenDownloadingSameItem(libraryItemId: String, episodeId: String?): String? {
        val sid = playSessionId?.swiftTrim()?.ifEmpty { null } ?: return null
        val book = _activeBook.value ?: return null
        if (book.id != libraryItemId) return null
        val playingEp = _activePlaybackEpisodeId.value?.swiftTrim() ?: ""
        val wantEp = episodeId?.swiftTrim() ?: ""
        if (playingEp != wantEp) return null
        return sid
    }

    /** Tracks der aktiven Remote-Session — für parallele Downloads ohne zweites `POST …/play`. */
    fun audioTracksForActiveSessionReuse(): List<AbsAudioTrack> =
        if (isRemotePlaySessionActive && !timeline.isEmpty) timeline.tracks else emptyList()

    // MARK: - Laden / Abriss

    fun tearDownPlayer() {
        // Laufende `playBook`-Aufrufe nach Schließen/Logout nicht mehr anwenden.
        loadGeneration += 1
        clearSleepTimer()
        _showMiniPlayerPlaceholder.value = false
        syncJob?.cancel(); syncJob = null
        tickJob?.cancel(); tickJob = null
        val sid = playSessionId
        val client = apiClient
        if (sid != null && client != null) {
            // Noch nicht gesyncte Hörzeit + Position vor dem Schließen senden.
            listenTime.accumulate(_isPlaying.value)
            val listened = floor(listenTime.pendingListenSeconds).toInt()
            val position = _globalPosition.value
            detachedScope.launch {
                if (listened > 0) runCatching { client.syncPlaySession(sid, listened, position) }
                runCatching { client.closePlaySession(sid) }
            }
        }
        playSessionId = null
        apiClient = null
        _activeBook.value = null
        _activePlaybackEpisodeId.value = null
        exo?.let { p ->
            p.playWhenReady = false
            p.stop()
            p.clearMediaItems()
            p.volume = 1f
        }
        timeline = TrackTimeline.EMPTY
        chapters = ChapterTimeline.EMPTY
        _chapterCount.value = 0
        _currentChapterOrdinal.value = 0
        _currentChapterTitle.value = ""
        listenTime.reset()
        _isPlaying.value = false
        _globalPosition.value = 0.0
        _totalDuration.value = 0.0
        _isBuffering.value = false
        _playbackError.value = null
        localRoot = null
        sessionPlayerOrNull?.notifyLogicalItemChanged()
    }

    /**
     * iOS: `playBook(client:book:resumeAt:localDownloadRoot:episodeId:…)`.
     * @param preferClientResumePosition Neustart nach „Fertig“ / expliziter Sprung: Client-Position statt
     *   `max(Server, Client)`.
     * @throws PlaybackNoTracksException ohne abspielbare Spuren; [CancellationException], wenn ein neuerer
     *   Aufruf diesen überholt hat; API-Fehler beim Session-Start.
     */
    suspend fun playBook(
        client: AbsApiClient,
        book: AbsBook,
        resumeAt: Double,
        localDownloadRoot: File?,
        episodeId: String? = null,
        autoPlay: Boolean = true,
        attemptServerPlaySession: Boolean = true,
        preferClientResumePosition: Boolean = false,
    ): Unit = withContext(Dispatchers.Main.immediate) {
        tearDownPlayer()
        loadGeneration += 1
        val generation = loadGeneration
        shouldAutoPlayAfterLoad = autoPlay
        apiClient = client
        _activeBook.value = book
        _activePlaybackEpisodeId.value = episodeId?.swiftTrim()?.ifEmpty { null }
        localRoot = localDownloadRoot
        attemptServerPlaySessionForLocal = attemptServerPlaySession
        // Launch-Restore darf fremde Wiedergabe nicht unterbrechen — Service erst bei Play binden.
        if (autoPlay) ensureSessionServiceConnected()
        try {
            val useLocal = localDownloadRoot != null &&
                withContext(Dispatchers.IO) { allTracksPresent(localDownloadRoot, book) }
            if (useLocal) {
                startLocalPlayback(client, book, localDownloadRoot!!, resumeAt, preferClientResumePosition, generation)
            } else {
                startRemotePlayback(client, book, resumeAt, _activePlaybackEpisodeId.value, preferClientResumePosition, generation)
            }
            throwIfSuperseded(generation)
            startPeriodicSync()
            startTickLoop()
        } catch (e: Throwable) {
            // Überholt: der neuere Aufruf besitzt den Player — nicht abreißen.
            if (generation == loadGeneration) tearDownPlayer()
            throw e
        }
    }

    private fun throwIfSuperseded(generation: Int) {
        if (generation != loadGeneration) throw CancellationException("playBook superseded")
    }

    /** Nach `startPlaySession`: überholter Aufruf schließt seine eigene Session, statt sie zu verwaisen. */
    private fun closeSessionIfSuperseded(sessionId: String, client: AbsApiClient, generation: Int) {
        if (generation == loadGeneration) return
        detachedScope.launch { runCatching { client.closePlaySession(sessionId) } }
        throw CancellationException("playBook superseded")
    }

    /** Rotierte Tokens auch in den Client des Players übernehmen (kann eine eigene Instanz sein). */
    fun adoptRefreshedTokens(accessToken: String, refreshToken: String) {
        val client = apiClient ?: return
        client.setToken(accessToken)
        if (refreshToken.isNotEmpty()) client.setRefreshToken(refreshToken)
    }

    /** Play-Session für lokale Dateien mit harter Deadline (sonst Offline-Modus mit PATCH/Flush). */
    private suspend fun startPlaySessionWithTimeout(client: AbsApiClient, itemId: String, episodeId: String?): AbsPlaySession? =
        withTimeoutOrNull(LOCAL_SESSION_TIMEOUT_MS) {
            try {
                client.startPlaySession(itemId, episodeId, stableDeviceId(), appVersion())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
        }

    private suspend fun startLocalPlayback(
        client: AbsApiClient,
        book: AbsBook,
        root: File,
        resumeHint: Double,
        preferClientResumePosition: Boolean,
        generation: Int,
    ) {
        playSessionId = null
        var resumeAt = resumeHint
        val manifest = withContext(Dispatchers.IO) { AbsDownloadManifest.load(root) }
        val manifestChapters = manifest?.chapters?.map { AbsChapter.fromManifest(it) }

        if (attemptServerPlaySessionForLocal) {
            val session = startPlaySessionWithTimeout(client, book.id, _activePlaybackEpisodeId.value)
            if (session != null) closeSessionIfSuperseded(session.id, client, generation)
            // Auch ohne Session (Timeout): ein überholter Aufruf darf Tracks/Kapitel nicht mehr setzen.
            throwIfSuperseded(generation)
            if (session != null) {
                playSessionId = session.id
                _activeBook.value = session.bookForPlayerUI()
                applyChapters(book, session.chapters, session.libraryItem, manifestChapters)
                val serverResume = if (preferClientResumePosition) resumeAt else max(session.currentTime, resumeAt)
                val cap = if (session.duration > 0) session.duration else serverResume
                resumeAt = min(serverResume, cap)
            }
        }

        val fromManifest = manifest?.tracks?.takeIf { it.isNotEmpty() }?.map { row ->
            AbsAudioTrack(index = row.index, startOffset = row.startOffset, duration = row.duration, title = row.title, ino = null)
        }
        val mediaTracks = fromManifest ?: book.media.tracks.orEmpty()
        if (mediaTracks.isEmpty()) throw PlaybackNoTracksException()
        timeline = TrackTimeline(mediaTracks)
        val manifestDur = manifest?.totalDuration?.takeIf { it > 0 }
        _totalDuration.value = manifestDur ?: book.media.duration ?: timeline.summedDuration
        if (chapters.isEmpty) applyChapters(book, null, _activeBook.value, manifestChapters)

        val items = withContext(Dispatchers.IO) {
            timeline.tracks.map { tr ->
                val file = resolvedLocalTrackFile(root, tr.index, manifest) ?: throw PlaybackNoTracksException()
                trackMediaItem(tr, Uri.fromFile(file))
            }
        }
        throwIfSuperseded(generation)
        startPlayer(items, resumeAt)
        onActiveMediaPrepared?.invoke()
    }

    private suspend fun startRemotePlayback(
        client: AbsApiClient,
        book: AbsBook,
        resumeAt: Double,
        episodeId: String?,
        preferClientResumePosition: Boolean,
        generation: Int,
    ) {
        val session = client.startPlaySession(book.id, episodeId, stableDeviceId(), appVersion())
        closeSessionIfSuperseded(session.id, client, generation)
        playSessionId = session.id
        val uiBook = session.bookForPlayerUI()
        _activeBook.value = uiBook

        val serverTracks = session.audioTracks ?: book.media.tracks.orEmpty()
        if (serverTracks.isEmpty()) throw PlaybackNoTracksException()
        timeline = TrackTimeline(serverTracks)
        applyChapters(book, session.chapters, session.libraryItem, null)

        val serverResume = if (preferClientResumePosition) resumeAt else max(session.currentTime, resumeAt)
        val safeResume = min(serverResume, if (session.duration > 0) session.duration else serverResume)
        _totalDuration.value = if (session.duration > 0) session.duration
        else uiBook.media.duration ?: book.media.duration ?: timeline.summedDuration

        val items = timeline.tracks.map { tr -> trackMediaItem(tr, Uri.parse(client.publicStreamURL(session.id, tr.index))) }
        throwIfSuperseded(generation)
        startPlayer(items, safeResume)
    }

    private fun trackMediaItem(track: AbsAudioTrack, uri: Uri): MediaItem =
        MediaItem.Builder().setMediaId("track:${track.index}").setUri(uri).build()

    /** Playlist setzen, an `resumeAt` positionieren und je nach `shouldAutoPlayAfterLoad` starten. */
    private fun startPlayer(items: List<MediaItem>, resumeAt: Double) {
        val p = ensurePlayer()
        val idx = timeline.trackIndex(resumeAt).coerceIn(0, items.size - 1)
        val offsetMs = (timeline.offsetInTrack(resumeAt) * 1000).toLong()
        sessionPlayer.notifyLogicalItemChanged()
        p.setMediaItems(items, idx, offsetMs)
        p.playbackParameters = p.playbackParameters.withSpeed(_playbackRate.value)
        p.volume = 1f
        p.prepare()
        _globalPosition.value = resumeAt
        updateChapterUI(resumeAt)
        if (shouldAutoPlayAfterLoad) {
            p.playWhenReady = true
            _isPlaying.value = true
            listenTime.resetTick()
            sleepTimer.resumeIfNeeded(true)
        } else {
            p.playWhenReady = false
            _isPlaying.value = false
        }
        listenTime.resetTick()
    }

    /** Stream-URLs neu binden (neue Session-ID / abgelaufener Stream) bzw. lokale Dateien neu laden. */
    private suspend fun reloadItemsAt(global: Double, play: Boolean): Boolean {
        val book = _activeBook.value ?: return false
        if (timeline.isEmpty) return false
        val root = localRoot
        val items: List<MediaItem> = if (root != null && withContext(Dispatchers.IO) { allTracksPresent(root, book) }) {
            val manifest = withContext(Dispatchers.IO) { AbsDownloadManifest.load(root) }
            timeline.tracks.map { tr ->
                val file = resolvedLocalTrackFile(root, tr.index, manifest) ?: return false
                trackMediaItem(tr, Uri.fromFile(file))
            }
        } else {
            val client = apiClient ?: return false
            val sid = playSessionId ?: return false
            timeline.tracks.map { tr -> trackMediaItem(tr, Uri.parse(client.publicStreamURL(sid, tr.index))) }
        }
        val p = ensurePlayer()
        p.setMediaItems(items, timeline.trackIndex(global), (timeline.offsetInTrack(global) * 1000).toLong())
        p.prepare()
        p.playWhenReady = play
        _globalPosition.value = global
        updateChapterUI(global)
        return true
    }

    // MARK: - ExoPlayer

    private fun ensurePlayer(): ExoPlayer {
        exo?.let { return it }
        // Bearer + Custom-Header pro Request (Token rotiert; Player-Client kann eine eigene Instanz sein).
        val http = OkHttpDataSource.Factory(Net.client)
        val authed = ResolvingDataSource.Factory(http) { spec ->
            val scheme = spec.uri.scheme ?: ""
            val token = apiClient?.currentToken()?.takeIf { it.isNotBlank() }
            if ((scheme == "http" || scheme == "https") && token != null) {
                spec.withAdditionalHeaders(Net.authorizedAssetHeaders(token, spec.uri.toString()))
            } else spec
        }
        val dataSources = DefaultDataSource.Factory(appContext, authed)
        val renderers = object : DefaultRenderersFactory(appContext) {
            override fun buildAudioSink(context: Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink =
                DefaultAudioSink.Builder(context)
                    .setEnableFloatOutput(false)
                    .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                    .setAudioProcessors(arrayOf(eqProcessor))
                    .build()
        }
        // iOS AudioSessionController: `.playback` + `.spokenAudio` — hier Audio-Fokus durch ExoPlayer.
        val attributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
            .build()
        val p = ExoPlayer.Builder(appContext, renderers)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSources))
            .setAudioAttributes(attributes, true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
        p.addListener(engineListener)
        exo = p
        return p
    }

    private val engineListener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            if (events.containsAny(
                    Player.EVENT_PLAY_WHEN_READY_CHANGED,
                    Player.EVENT_PLAYBACK_SUPPRESSION_REASON_CHANGED,
                    Player.EVENT_PLAYBACK_STATE_CHANGED,
                )
            ) {
                updateBufferingState()
                syncPlayingStateFromEngine()
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_READY) {
                _playbackError.value = null
                errorRecoveryAttempts = 0
            }
            if (playbackState == Player.STATE_ENDED && _activeBook.value != null) handleEndOfTracks()
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            refreshGlobalFromPlayer()
            updateChapterUI(_globalPosition.value)
        }

        override fun onPlayerError(error: PlaybackException) {
            handlePlayerError(error)
        }
    }

    private fun updateBufferingState() {
        val p = exo ?: return
        _isBuffering.value = p.mediaItemCount > 0 && p.playbackState == Player.STATE_BUFFERING
    }

    /**
     * iOS: `syncPlayingStateFromPlayerIfNeeded` — Fokusverlust (Anruf, andere App), Kopfhörer ziehen,
     * Fehler: UI/`isPlaying` an den echten Engine-Zustand angleichen, Hörzeit sichern, Timer pausieren.
     */
    private fun syncPlayingStateFromEngine() {
        val p = exo ?: return
        if (p.mediaItemCount == 0 || _activeBook.value == null) return
        val state = p.playbackState
        val enginePlaying = p.playWhenReady &&
            p.playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_NONE &&
            (state == Player.STATE_READY || state == Player.STATE_BUFFERING)
        if (_isPlaying.value == enginePlaying) return
        if (enginePlaying) {
            _isPlaying.value = true
            listenTime.resetTick()
            sleepTimer.resumeIfNeeded(true)
        } else {
            listenTime.accumulate(true)
            _isPlaying.value = false
            sleepTimer.pause()
            scope.launch { flushSync(force = true) }
        }
    }

    /** iOS: `advanceToNextTrack` am Ende der letzten Spur. */
    private fun handleEndOfTracks() {
        _globalPosition.value = _totalDuration.value
        updateChapterUI(_globalPosition.value)
        pause()
        if (_activePlaybackEpisodeId.value == null) onAudiobookPlaybackCompleted?.invoke()
        else onPodcastEpisodePlaybackCompleted?.invoke()
    }

    /**
     * Stream-Fehler (abgelaufene Session, Netzabbruch): erst dieselbe Session neu binden, beim zweiten
     * Fehler eine neue Play-Session anlegen (iOS: `recoverStaleRemotePlaybackIfNeeded`); danach Fehlerzustand.
     */
    private fun handlePlayerError(error: PlaybackException) {
        Log.w(TAG, "player error ${error.errorCodeName}: ${error.message}")
        val wantPlay = exo?.playWhenReady == true || _isPlaying.value
        if (!isUsingLocalTrackFiles && apiClient != null && errorRecoveryAttempts < MAX_ERROR_RECOVERY_ATTEMPTS) {
            errorRecoveryAttempts += 1
            val attempt = errorRecoveryAttempts
            scope.launch {
                val resumeAt = playbackGlobalPosition()
                val ok = if (attempt == 1 && playSessionId != null) {
                    reloadItemsAt(resumeAt, wantPlay).also { if (it && wantPlay) beginPlaybackEngine() }
                } else {
                    recoverPlaySessionAfterSyncFailure(lostTimeListened = 0, forcePlay = wantPlay)
                }
                if (!ok) failPlayback(error)
            }
            return
        }
        failPlayback(error)
    }

    private fun failPlayback(error: PlaybackException) {
        _playbackError.value = error.message ?: "Playback failed."
        if (_isPlaying.value) {
            listenTime.accumulate(true)
            _isPlaying.value = false
            sleepTimer.pause()
            scope.launch { flushSync(force = true) }
        }
    }

    /** Session-Service binden: Media3 hält ihn dann beim Abspielen im Vordergrund (Benachrichtigung). */
    private fun ensureSessionServiceConnected() {
        if (sessionController != null) return
        runCatching {
            val token = SessionToken(appContext, ComponentName(appContext, AbstandPlaybackService::class.java))
            sessionController = MediaController.Builder(appContext, token).buildAsync()
        }
    }

    // MARK: - Tick

    private fun startTickLoop() {
        tickJob?.cancel()
        tickJob = scope.launch {
            while (isActive) {
                delay(if (_isPlaying.value) TICK_INTERVAL_MS else IDLE_TICK_INTERVAL_MS)
                tick()
            }
        }
    }

    private fun tick() {
        listenTime.accumulate(_isPlaying.value)
        onPlaybackTick?.invoke()
        refreshGlobalFromPlayer()
        updateChapterUI(_globalPosition.value)
        // Zeit-Timer: Wanduhr-abhängig (Wake-Job kann im Doze verspätet sein).
        if (_isPlaying.value && sleepTimer.isWallClockExpired()) {
            sleepTimer.markExpired()
            pause()
        }
        // Kapitel-Timer: positionsbasiert, feuert am Ende des Ziel-Kapitels.
        val target = sleepTimer.chapterTarget
        if (_isPlaying.value && target != null && target < chapters.count &&
            playbackGlobalPosition() >= chapters.chapterEndTime(target, _totalDuration.value)
        ) {
            clearSleepTimer()
            // iOS lässt den Modus hier stehen (Sink sieht noch das Kapitel-Ziel) — Menü zeigt danach „Off“.
            sleepTimer.setMode(SleepTimerMode.Off)
            pause()
        }
        applySleepTimerFadeVolume()
    }

    private fun refreshGlobalFromPlayer() {
        val p = exo ?: return
        if (p.mediaItemCount == 0 || timeline.isEmpty) return
        // iOS: `reliablePlayerGlobalPosition` — nach einem Wiedergabefehler nicht der Engine-Zeit trauen
        // (Wiederherstellung soll an der letzten guten Position weitermachen, nicht bei 0).
        if (p.playerError != null) return
        val g = timeline.globalTime(p.currentMediaItemIndex, p.currentPosition / 1000.0)
        if (g.isFinite() && g >= 0) _globalPosition.value = g
    }

    /** Aktuelle Abspielposition (frisch vom Player, falls möglich). */
    fun playbackGlobalPosition(): Double {
        refreshGlobalFromPlayer()
        return _globalPosition.value
    }

    /** Frische Position in ganzen Sekunden (z. B. Lesezeichen). */
    fun snapshotPlaybackTimeSeconds(): Int = max(0, floor(playbackGlobalPosition()).toInt())

    /** Globale Position in ms für [BookTimelinePlayer] (ohne Zustandsänderung). */
    internal fun globalPositionMsForSession(): Long {
        val p = exo ?: return (_globalPosition.value * 1000).toLong()
        if (p.mediaItemCount == 0 || timeline.isEmpty) return (_globalPosition.value * 1000).toLong()
        return (timeline.globalTime(p.currentMediaItemIndex, p.currentPosition / 1000.0) * 1000).toLong()
    }

    internal fun globalTimeForSession(trackIndex: Int, localSeconds: Double): Double = timeline.globalTime(trackIndex, localSeconds)

    internal fun bufferedGlobalPositionMsForSession(): Long {
        val p = exo ?: return 0
        if (p.mediaItemCount == 0 || timeline.isEmpty) return 0
        return (timeline.globalTime(p.currentMediaItemIndex, p.bufferedPosition / 1000.0) * 1000).toLong()
    }

    /** Cover für Benachrichtigung/Sperrbildschirm (iOS: `loadNowPlayingArtwork`, Hero-Stufe). */
    internal fun nowPlayingArtworkUri(): Uri? {
        val book = _activeBook.value ?: return null
        val client = apiClient ?: return null
        return Uri.parse(client.coverURL(book.id, CoverImageTier.hero))
    }

    // MARK: - Transport

    /** iOS: `play()` / `performPlayResume()`. */
    fun play() {
        // Der Nutzer will hören: ein ladender Launch-Restore darf danach nicht wieder pausieren.
        shouldAutoPlayAfterLoad = true
        val p = exo
        // Play-Befehl (Kopfhörer/Benachrichtigung) ohne geladenen Titel: nichts aktivieren.
        if (_activeBook.value == null || p == null || p.mediaItemCount == 0) return
        ensureSessionServiceConnected()
        scope.launch {
            if (localRoot != null && playSessionId == null && attemptServerPlaySessionForLocal) {
                recreatePlaySessionForLocalPlaybackIfNeeded()
            }
            if (!isUsingLocalTrackFiles && apiClient != null && playSessionId == null) {
                recoverPlaySessionAfterSyncFailure(lostTimeListened = 0, forcePlay = true)
                if (playSessionId != null) return@launch
            }
            if (p.playerError != null || p.playbackState == Player.STATE_IDLE) {
                // Fehlerzustand: Stream/Datei neu binden statt stumm „spielt“ anzuzeigen.
                if (!reloadItemsAt(playbackGlobalPosition(), play = true)) return@launch
            } else if (p.playbackState == Player.STATE_ENDED) {
                seek(global = 0.0)
            }
            beginPlaybackEngine()
        }
    }

    private fun beginPlaybackEngine() {
        val p = exo ?: return
        p.volume = 1f
        p.playWhenReady = true
        _isPlaying.value = true
        _playbackError.value = null
        listenTime.resetTick()
        // Intelligenter Restart nur ohne aktiven Timer (sonst hat der Nutzer selbst neu gesetzt).
        if (sleepTimer.sleepTimerMode.value == SleepTimerMode.Off) sleepTimer.restoreIfWithinGrace(true)
        sleepTimer.resumeIfNeeded(true)
        applySleepTimerFadeVolume()
    }

    fun pause() {
        listenTime.accumulate(_isPlaying.value)
        sleepTimer.pause()
        exo?.let { p ->
            p.playWhenReady = false
            // Nach Sleep-Timer-Ausblenden: nächstes Play wieder in voller Lautstärke.
            p.volume = 1f
        }
        _isPlaying.value = false
        scope.launch { flushSync(force = true) }
    }

    fun togglePlayPause() {
        if (_isPlaying.value) pause() else play()
    }

    fun skip(seconds: Double) {
        seek(global = playbackGlobalPosition() + seconds)
    }

    fun skipBackward() = skip(-_skipBackwardSeconds.value.toDouble())

    fun skipForward() = skip(_skipForwardSeconds.value.toDouble())

    /** Vorheriges Kapitel: zuerst Kapitelanfang, sonst vorheriges Kapitel. */
    fun skipToPreviousChapter() {
        chapters.previousChapterTarget(playbackGlobalPosition())?.let { seek(it) }
    }

    /** Nächstes Kapitel (Anfang). */
    fun skipToNextChapter() {
        chapters.nextChapterTarget(playbackGlobalPosition())?.let { seek(it) }
    }

    fun seek(global: Double) {
        // Remote-Befehl während Laden/nach Abriss: nichts zu seeken.
        if (_activeBook.value == null || timeline.isEmpty) return
        val p = exo ?: return
        val g = min(max(0.0, global), max(_totalDuration.value - 0.25, 0.0))
        val idx = timeline.trackIndex(g)
        if (idx >= p.mediaItemCount) return
        p.seekTo(idx, (timeline.offsetInTrack(g) * 1000).toLong())
        _globalPosition.value = g
        updateChapterUI(g)
    }

    fun setPlaybackRate(rate: Float) {
        val snapped = PlaybackRates.snapped(rate)
        _playbackRate.value = snapped
        Prefs.setDouble(PLAYBACK_RATE_KEY, snapped.toDouble())
        exo?.let { it.playbackParameters = it.playbackParameters.withSpeed(snapped) }
    }

    /** Android Auto / CarPlay: nächstes Geschwindigkeits-Preset zyklisch. */
    fun advancePlaybackRate() = setPlaybackRate(PlaybackRates.next(_playbackRate.value))

    // MARK: - EQ

    /** Preset wechseln — Live-Rekonfiguration des Prozessors, kein Pipeline-Neuaufbau. */
    fun setEQPreset(preset: AudioEQPreset) {
        if (preset == _eqPreset.value) return
        _eqPreset.value = preset
        Prefs.setString(AudioEQPreset.DEFAULTS_KEY, preset.rawValue)
        eqProcessor.preset = preset
    }

    // MARK: - Kapitel

    /** Index des laufenden Kapitels (0-basiert). */
    fun currentChapterIndex(): Int? = if (chapters.isEmpty) null else chapters.chapterIndex(playbackGlobalPosition())

    /** Fortschritt im aktuellen Kapitel — für den Kapitel-Fortschrittsbalken im Vollplayer. */
    fun currentChapterProgress(global: Double? = null): ChapterTimeline.ChapterProgress? =
        chapters.chapterProgress(global ?: playbackGlobalPosition(), _totalDuration.value)

    fun chapterTargetIndex(forCount: Int): Int? = chapters.chapterTargetIndex(forCount, playbackGlobalPosition())

    fun maxSleepChapterCount(): Int = chapters.maxSleepChapterCount(playbackGlobalPosition())

    /** Nach Metadaten-/Cover-Änderung: Titel/Autor/Cover ohne Neustart übernehmen. */
    fun refreshActiveBookMetadata(fresh: AbsBook) {
        val current = _activeBook.value ?: return
        if (current.id != fresh.id) return
        if (!_activePlaybackEpisodeId.value.isNullOrBlank()) return
        _activeBook.value = current.replacingMetadata(fresh)
        sessionPlayer.notifyLogicalItemChanged()
    }

    /** Nach „Edit Chapters“: Kapitel der aktiven Hörbuch-Wiedergabe ohne Neustart aktualisieren. */
    fun refreshActiveBookChapters(libraryItemId: String, newChapters: List<AbsChapter>) {
        if (_activeBook.value?.id != libraryItemId) return
        if (!_activePlaybackEpisodeId.value.isNullOrBlank()) return
        if (newChapters.isNotEmpty()) _activeBook.value?.let { _activeBook.value = it.withChapters(newChapters) }
        val book = _activeBook.value ?: return
        applyChapters(book, newChapters.ifEmpty { null }, null, null)
    }

    private fun applyChapters(book: AbsBook, sessionChapters: List<AbsChapter>?, libraryItemFallback: AbsBook?, manifestChapters: List<AbsChapter>?) {
        chapters = ChapterTimeline(
            ChapterTimeline.select(sessionChapters, manifestChapters, book.media.chapters, libraryItemFallback?.media?.chapters),
        )
        _chapterCount.value = chapters.count
        updateChapterUI(_globalPosition.value)
    }

    private fun updateChapterUI(global: Double) {
        if (chapters.isEmpty) {
            _chapterCount.value = 0
            _currentChapterOrdinal.value = 0
            _currentChapterTitle.value = ""
            return
        }
        _chapterCount.value = chapters.count
        val idx = chapters.chapterIndex(global) ?: 0
        _currentChapterOrdinal.value = idx + 1
        _currentChapterTitle.value = chapters.sortedChapters[idx].title
    }

    // MARK: - Sync

    private fun startPeriodicSync() {
        syncJob?.cancel()
        syncJob = scope.launch {
            while (isActive) {
                delay(SyncPlan.PERIODIC_SYNC_INTERVAL_MS)
                flushSync(force = false)
            }
        }
    }

    private suspend fun flushSync(force: Boolean) {
        listenTime.accumulate(_isPlaying.value)
        val sid = playSessionId
        val client = apiClient
        val plan = SyncPlan.decide(
            pendingSeconds = listenTime.pendingListenSeconds,
            force = force,
            hasSession = sid != null && client != null,
            isLocalPlayback = localRoot != null,
        )
        when (plan) {
            SyncPlan.Skip -> return
            is SyncPlan.SessionSync -> {
                val tl = listenTime.takeWholeSeconds()
                val generation = loadGeneration
                try {
                    client!!.syncPlaySession(sid!!, tl, _globalPosition.value)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // Inzwischen anderer Titel geladen: Zeit nicht dem neuen Titel gutschreiben.
                    if (generation != loadGeneration || playSessionId != sid) return
                    listenTime.restore(tl)
                    if (isTransientNetworkError(e)) return
                    recoverPlaySessionAfterSyncFailure(lostTimeListened = tl)
                }
            }
            is SyncPlan.LocalWithoutSession -> {
                val tl = listenTime.takeWholeSeconds()
                onLocalPlaybackWithoutSessionSync?.invoke(tl, _globalPosition.value, _totalDuration.value)
            }
        }
    }

    /** Absorb `_resumeServerSync`: Session für lokale Wiedergabe nach Pause/Offline neu anlegen. */
    private suspend fun recreatePlaySessionForLocalPlaybackIfNeeded() {
        if (playSessionId != null || !attemptServerPlaySessionForLocal) return
        val client = apiClient ?: return
        val book = _activeBook.value ?: return
        startPlaySessionWithTimeout(client, book.id, _activePlaybackEpisodeId.value)?.let { playSessionId = it.id }
    }

    /**
     * Absorb: bei ungültiger Session neue starten, verlorene Hörzeit nachsyncen und den Stream an die
     * aktuelle Position neu binden. `true`, wenn eine neue Session steht.
     */
    private suspend fun recoverPlaySessionAfterSyncFailure(lostTimeListened: Int, forcePlay: Boolean = false): Boolean {
        val client = apiClient ?: return false
        val book = _activeBook.value ?: return false
        val generation = loadGeneration
        val resumeAt = playbackGlobalPosition()
        val wantPlay = forcePlay || _isPlaying.value
        val episodeId = _activePlaybackEpisodeId.value?.swiftTrim()?.ifEmpty { null }
        return try {
            val session = client.startPlaySession(book.id, episodeId, stableDeviceId(), appVersion())
            if (generation != loadGeneration) {
                detachedScope.launch { runCatching { client.closePlaySession(session.id) } }
                return false
            }
            playSessionId = session.id
            if (lostTimeListened > 0) client.syncPlaySession(session.id, lostTimeListened, resumeAt)
            if (!isUsingLocalTrackFiles && !timeline.isEmpty) {
                if (reloadItemsAt(resumeAt, wantPlay) && wantPlay) beginPlaybackEngine()
            }
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!isTransientNetworkError(e)) playSessionId = null
            false
        }
    }

    /** Offline-Modus: keine weiteren Play-Session-Requests (vorher flushen + Hörzeit abholen). */
    fun suspendServerNetworkingForOfflineMode() {
        syncJob?.cancel()
        syncJob = null
        playSessionId = null
        apiClient = null
    }

    /** Aufgelaufene Hörsekunden abholen und Zähler leeren (Offline-Persistenz vor Session-Clear). */
    fun consumePendingListenSeconds(): Int {
        listenTime.accumulate(_isPlaying.value)
        return listenTime.takeWholeSeconds()
    }

    suspend fun closeSessionIfNeeded(): Unit = withContext(Dispatchers.Main.immediate) {
        flushSync(force = true)
        val sid = playSessionId
        val client = apiClient
        if (sid != null && client != null) runCatching { client.closePlaySession(sid) }
        playSessionId = null
    }

    /** Für `syncOfflineProgressToServer`: offene Play-Session-Zeit an den Server schreiben. */
    suspend fun flushPendingPlaySessionSync(): Unit = withContext(Dispatchers.Main.immediate) { flushSync(force = true) }

    companion object {
        private const val TAG = "AbstandPlayback"
        const val PLAYBACK_RATE_KEY = "abstand_playback_rate"
        const val SKIP_BACKWARD_KEY = "abstand_skip_backward_seconds"
        const val SKIP_FORWARD_KEY = "abstand_skip_forward_seconds"
        const val DEVICE_ID_KEY = "abstand_device_id"

        /** iOS: periodischer Time-Observer 0,35 s. */
        const val TICK_INTERVAL_MS = 350L
        private const val IDLE_TICK_INTERVAL_MS = 1_000L
        private const val LOCAL_SESSION_TIMEOUT_MS = 3_000L
        private const val MAX_ERROR_RECOVERY_ATTEMPTS = 2

        @Volatile private var instance: PlaybackController? = null

        /** Prozessweiter Player (iOS: `AppModel.player`). */
        fun shared(context: Context): PlaybackController =
            instance ?: synchronized(this) {
                instance ?: PlaybackController(context.applicationContext).also { instance = it }
            }

        /** Bereits erzeugte Instanz (für Service-Callbacks ohne Context). */
        fun sharedOrNull(): PlaybackController? = instance

        val playbackRatePresets: List<Float> get() = PlaybackRates.presets
        val skipIntervalOptions: List<Int> get() = PlaybackSkipDefaults.intervalOptions

        private fun loadSkipSeconds(key: String, fallback: Int): Int =
            if (!Prefs.has(key)) fallback else PlaybackSkipDefaults.clamped(Prefs.int(key), fallback)

        /** iOS: `stableDeviceId()` — gleicher Key wie iOS. */
        fun stableDeviceId(): String {
            Prefs.string(DEVICE_ID_KEY)?.let { return it }
            val id = UUID.randomUUID().toString().uppercase()
            Prefs.setString(DEVICE_ID_KEY, id)
            return id
        }

        fun appVersion(): String = BuildConfig.VERSION_NAME

        /** Nur Vorschlagsname für den Download-Stamm (`track_3`); die echte Endung setzt der Client. */
        fun trackFilename(index: Int): String = "track_$index.abs"

        /** Lokale Track-Datei mit erkennbarer Endung (Manifest-Endung zuerst, dann Standardliste, dann Präfix). */
        fun resolvedLocalTrackFile(root: File, trackIndex: Int, manifest: AbsDownloadManifest?): File? {
            val preferred = manifest?.audioFileExtension?.swiftTrim()?.lowercase()?.replace(".", "")
            val exts = LinkedHashSet<String>()
            if (!preferred.isNullOrEmpty()) exts.add(preferred)
            exts.addAll(listOf("m4a", "mp3", "aac", "flac", "ogg", "wav", "abs"))
            for (ext in exts) {
                val f = File(root, "track_$trackIndex.$ext")
                if (f.exists()) return f
            }
            val prefix = "track_$trackIndex."
            return root.listFiles()?.firstOrNull { it.name.startsWith(prefix) && !it.name.endsWith(".part") }
        }

        private fun allTracksPresent(root: File, book: AbsBook): Boolean {
            val manifest = AbsDownloadManifest.load(root)
            if (manifest != null && manifest.tracks.isNotEmpty()) {
                return manifest.tracks.all { resolvedLocalTrackFile(root, it.index, manifest) != null }
            }
            val list = book.media.tracks.orEmpty()
            if (list.isEmpty()) return false
            return list.all { resolvedLocalTrackFile(root, it.index, manifest) != null }
        }

        /** Alle erwarteten Track-Dateien im Download-Ordner vorhanden. */
        fun allLocalTracksPresentForOfflinePlayback(root: File, book: AbsBook): Boolean = allTracksPresent(root, book)

        /** Keine neue Play-Session bei Netzwerkfehler — sonst wirkt die alte Server-Session „gelöscht“. */
        fun isTransientNetworkError(e: Throwable): Boolean {
            if (e is AbsApiError) return false
            return e is UnknownHostException || e is ConnectException || e is NoRouteToHostException ||
                e is SocketException || e is InterruptedIOException ||
                (e is IOException && e.cause?.let { isTransientNetworkError(it) } == true)
        }
    }
}
