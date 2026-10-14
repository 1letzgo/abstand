package de.letzgo.abstand.model

import android.net.ConnectivityManager
import android.util.Log
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsProgressPatch
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.downloads.DownloadMaintenance
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.player.AbstandPlaybackService
import de.letzgo.abstand.player.BrowseSource
import de.letzgo.abstand.player.LocalDownloadSwitch
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.player.PlaybackHost
import de.letzgo.abstand.player.PlaybackHostBridge
import de.letzgo.abstand.transcript.PlaybackTranscription
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.library.LibraryPlayback
import de.letzgo.abstand.ui.permissions.NotificationPermission
import de.letzgo.abstand.ui.podcasts.PodcastActions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * iOS: Player-Teil von `AppModel` — `playPodcastEpisode`, `restoreLastPlayedOnLaunch`,
 * `markFinished`/`markPodcastEpisodeFinished` aus der Wiedergabe, `dismissPlayer`, Bookmark anlegen/
 * löschen, `requestPresentNowPlayingSheet`, Download-Knopf im Vollplayer — plus die Verdrahtung der
 * Player-Schnittstellen ([PlaybackHost], [BrowseSource] für Android Auto, [PlaybackLauncher] für
 * Karten, [PodcastActions] für den Podcast-Tab, Download-Host über [downloads]).
 *
 * Hörbücher starten über [LibraryPlayback.play] (iOS `play(book:)`, gemeinsam mit Bücher-Tab und
 * Detail). Fortschritt: eine Quelle, der [ProgressStore] (`model.progress`); Home- und Podcast-
 * Spiegel bekommen jede Player-Zeile mit ([fanOut]).
 *
 * Erzeugt im [AppModel]-Konstruktor (vor `start()`), verdrahtet in `AbstandApplication.onCreate` per [attach].
 */
class PlayerWiring(private val model: AppModel) : SessionParticipant, PlaybackHost, BrowseSource, PlaybackLauncher {
    private val session: SessionStore get() = model.session
    private val progressStore: ProgressStore get() = model.progress

    /** iOS: `AppModel.player`. */
    val player: PlaybackController by lazy { PlaybackController.shared(model.appContext) }

    /** Download-Liste je Account, Badges, [de.letzgo.abstand.downloads.DownloadHost]. */
    val downloads = DownloadWiring(model)

    private lateinit var bridge: PlaybackHostBridge

    // MARK: - UI-Zustand

    private val _nowPlaying = MutableStateFlow(NowPlayingState())
    override val nowPlaying: StateFlow<NowPlayingState> = _nowPlaying.asStateFlow()

    private val _nowPlayingPresented = MutableStateFlow(false)
    /** iOS: `nowPlayingSheetRequests` — Vollbild-Player sichtbar. */
    val nowPlayingPresented: StateFlow<Boolean> = _nowPlayingPresented.asStateFlow()

    private val _isPreparingPlayback = MutableStateFlow(false)
    /** iOS: `isPreparingPlayback` — Start läuft (Metadaten, Session). */
    val isPreparingPlayback: StateFlow<Boolean> = _isPreparingPlayback.asStateFlow()

    /** iOS: `bookmarks` (Quelle: [ProgressStore]). */
    val bookmarks: StateFlow<List<AbsAudioBookmark>> get() = progressStore.bookmarks

    private val _revision = MutableStateFlow(0L)

    /** Podcast-Tab-Brücke (iOS: `playPodcastEpisode`, `startDownloadPodcastEpisode`, …). */
    val podcastActions: PodcastActions = PlayerPodcastActions()

    /** Medium, dessen erster Play-Start noch „Now Playing öffnen“ auslösen darf. */
    private var presentOnFirstPlayKey: String? = null

    // MARK: - Verdrahtung

    /** Einmal in `Application.onCreate` (Main): Bridge, Download-Host, Auto-Browse, Beobachter. */
    fun attach() {
        bridge = PlaybackHostBridge(player, this).also { it.attach() }
        DownloadManager.host = downloads
        AbstandPlaybackService.browseSource = this
        downloads.attach()
        model.scope.launch {
            combine(player.activeBook, player.activePlaybackEpisodeId, player.isPlaying) { book, ep, playing ->
                NowPlayingState(book?.let { NowPlayingState.progressKeyOf(it.id, ep) }, playing && book != null)
            }.distinctUntilChanged().collect { state ->
                val previousKey = _nowPlaying.value.progressKey
                _nowPlaying.value = state
                _revision.value += 1
                onNowPlayingChanged(previousKey, state)
            }
        }
        model.scope.launch { downloads.revision.collect { _revision.value += 1 } }
        // Wieder online: Offline-Hörzeit und lokale Fortschritte nachsenden (iOS: `flushPendingOfflineListeningTime`).
        model.scope.launch {
            var wasReachable = session.isNetworkReachable.value
            session.isNetworkReachable.collect { reachable ->
                if (reachable && !wasReachable) syncPendingProgressToServer()
                wasReachable = reachable
            }
        }
        model.scope.launch(Dispatchers.IO) { runCatching { DownloadMaintenance.removeStaleDownloadTempFiles() } }
    }

    /**
     * Erster Play-Start eines neu geladenen Mediums (Karte, Detail, Podcast, Android Auto) — iOS ruft
     * hier `presentNowPlayingSheetOnAutoPlayIfNeeded` und lädt das Dashboard nach. Launch-Restore lädt
     * pausiert und öffnet daher nichts.
     */
    private fun onNowPlayingChanged(previousKey: String?, state: NowPlayingState) {
        val key = state.progressKey
        if (key == null) {
            presentOnFirstPlayKey = null
            _nowPlayingPresented.value = false
            return
        }
        if (key != previousKey) presentOnFirstPlayKey = key
        if (!state.isPlaying || presentOnFirstPlayKey != key) return
        presentOnFirstPlayKey = null
        NotificationPermission.requestIfNeeded(model.appContext)
        if (!session.offlineHomeUIActive && Prefs.bool(Keys.openPlayerWhenStartPlaying, true)) _nowPlayingPresented.value = true
        if (session.mayUseServerNetwork) model.scope.launch { runCatching { model.home.loadStartDashboard() } }
    }

    // MARK: - PlaybackHost

    override val apiClient: AbsApiClient?
        get() = session.client ?: if (session.offlineHomeUIActive) session.clientForOfflineLocalPlayback() else null

    override val mayUseServerNetwork: Boolean get() = session.mayUseServerNetwork

    override val isNetworkReachable: Boolean get() = session.isNetworkReachable.value

    override val isNetworkUnmetered: Boolean
        get() = model.appContext.getSystemService(ConnectivityManager::class.java)?.let { !it.isActiveNetworkMetered } ?: false

    override fun progress(progressKey: String): AbsUserMediaProgress? = progressStore.progress(progressKey)

    /** Eine Quelle ([ProgressStore], Room per `upsertProgress`), Spiegel in Home/Podcasts angleichen. */
    override fun upsertProgress(progress: AbsUserMediaProgress, markPendingServerSync: Boolean) {
        progressStore.upsertProgressLocally(progress, markPendingServerSync)
        fanOut(progress)
    }

    /** Home-Regale und Podcast-Zeilen halten (noch) eigene Spiegel — ohne zweiten Room-Write angleichen. */
    private fun fanOut(progress: AbsUserMediaProgress) {
        model.home.applyProgressUpdate(progress, persistToDisk = false)
        model.podcasts.applyProgressUpdate(progress)
    }

    override fun clearPendingLocalProgressSync(progressKey: String) = progressStore.clearPendingLocalProgressSync(progressKey)

    override fun podcastEpisode(libraryItemId: String, episodeId: String): AbsPodcastEpisodeListItem? {
        val key = NowPlayingState.progressKeyOf(libraryItemId, episodeId)
        val p = model.podcasts
        p.podcastEpisodes.value.firstOrNull { it.progressLookupKey == key }?.let { return it }
        p.podcastFilteredEpisodes.value.firstOrNull { it.progressLookupKey == key }?.let { return it }
        p.podcastEpisodesByShowId.value[libraryItemId]?.firstOrNull { it.progressLookupKey == key }?.let { return it }
        model.home.startShelves.value.forEach { s -> s.podcastEpisodes.firstOrNull { it.progressLookupKey == key }?.let { return it } }
        return downloads.downloadedEpisodes().firstOrNull { it.progressLookupKey == key }
    }

    override suspend fun markPlaybackFinished(libraryItemId: String, episodeId: String?) {
        val ep = episodeId?.swiftTrim()?.ifEmpty { null }
        val key = NowPlayingState.progressKeyOf(libraryItemId, ep)
        val storageId = if (ep == null) libraryItemId else DownloadStatusSource.storageId(libraryItemId, ep)
        val wasCurrent = player.activeBook.value?.id == libraryItemId && player.activePlaybackEpisodeId.value?.swiftTrim()?.ifEmpty { null } == ep
        if (wasCurrent) {
            bridge.recordActivePlaybackProgressLocally(markPendingServerSync = true)
            player.flushPendingPlaySessionSync()
        }
        val bookDur = player.activeBook.value?.takeIf { it.id == libraryItemId }?.media?.duration
        progressStore.applyLocalMarkFinished(libraryItemId, ep, bookDur)
        progressStore.markPendingLocalProgressSync(key)
        progress(key)?.let { fanOut(it) }
        val client = session.client
        if (!session.mayUseServerNetwork || !session.isNetworkReachable.value || client == null) {
            finishMarkFinishedLocally(storageId, wasCurrent, libraryItemId)
            return
        }
        try {
            // Play-Session VOR dem PATCH schließen — sonst setzt ihr letzter Sync `isFinished` zurück (iOS-Kommentar).
            if (wasCurrent) dismissPlayer(idlePlaceholder = false)
            client.markFinished(libraryItemId, ep)
            progressStore.clearLocallyFinishedProgressKey(key)
            progressStore.clearPendingLocalProgressSync(key)
            session.refreshProgressFromServer()
            progressStore.reconcileProgressAfterMarkFinished(libraryItemId, ep, bookDur)
            progress(key)?.let { fanOut(it) }
            finishMarkFinishedLocally(storageId, wasPlaying = false, clearLastPlayedIfBookId = libraryItemId)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    /** iOS: `finishMarkFinishedLocally`. */
    private suspend fun finishMarkFinishedLocally(storageId: String, wasPlaying: Boolean, clearLastPlayedIfBookId: String?) {
        if (wasPlaying) dismissPlayer(idlePlaceholder = false)
        _nowPlayingPresented.value = false
        if (clearLastPlayedIfBookId != null && Prefs.string(Keys.lastPlayedItemId) == clearLastPlayedIfBookId) Prefs.remove(Keys.lastPlayedItemId)
        downloads.removeIfFinishedSetting(storageId)
    }

    // MARK: - Wiedergabe beenden

    /** iOS: `dismissPlayer(idlePlaceholder:)`. */
    suspend fun dismissPlayer(idlePlaceholder: Boolean = true) {
        player.closeSessionIfNeeded()
        player.tearDownPlayer()
        player.setMiniPlayerPlaceholder(idlePlaceholder)
        _nowPlayingPresented.value = false
    }

    // MARK: - PlaybackLauncher

    override fun play(itemId: String, episodeId: String?) {
        val ep = episodeId?.swiftTrim()?.ifEmpty { null }
        if (_nowPlaying.value.isActive(itemId, ep)) {
            player.play()
            return
        }
        model.scope.launch { playItem(itemId, ep) }
    }

    override fun openNowPlaying() {
        if (player.activeBook.value != null) _nowPlayingPresented.value = true
    }

    fun dismissNowPlaying() {
        _nowPlayingPresented.value = false
    }

    override fun pause() = player.pause()

    override fun resume() = player.play()

    /** Item per ID auflösen (Regale, Katalog, Downloads, LocalStore, Server) und starten. */
    suspend fun playItem(itemId: String, episodeId: String?, autoPlay: Boolean = true) {
        if (episodeId != null) {
            playPodcastEpisode(resolveEpisode(itemId, episodeId), autoPlay = autoPlay)
            return
        }
        val book = resolveBook(itemId) ?: run {
            session.setErrorMessage(if (session.offlineHomeUIActive) "Download this title to play it offline." else "Couldn't load this title.")
            return
        }
        playBook(book, autoPlay = autoPlay)
    }

    private suspend fun resolveBook(itemId: String): AbsBook? {
        model.home.startBooks.value.firstOrNull { it.id == itemId }?.let { return it }
        model.home.startShelves.value.forEach { s -> s.books.firstOrNull { it.id == itemId }?.let { return it } }
        model.catalog.lookupBookStub(itemId)?.let { return it }
        downloads.downloadedBooks().firstOrNull { it.id == itemId }?.let { return it }
        model.catalog.cachedBookDetail(itemId)?.let { return it }
        val c = session.client ?: return null
        if (!canUseServer) return null
        return try {
            c.item(itemId, expanded = true)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
            null
        }
    }

    private suspend fun resolveEpisode(itemId: String, episodeId: String): AbsPodcastEpisodeListItem {
        podcastEpisode(itemId, episodeId)?.let { return it }
        val key = NowPlayingState.progressKeyOf(itemId, episodeId)
        session.currentLocalLibraryStore()?.let { store -> runCatching { store.fetchPodcastEpisode(key) }.getOrNull()?.let { return it } }
        progress(key)?.let { p -> AbsPodcastEpisodeListItem.forResumePlayback(p, session.resolvedPodcastLibraryId())?.let { return it } }
        return AbsPodcastEpisodeListItem(
            libraryItemId = itemId,
            libraryId = session.resolvedPodcastLibraryId(),
            episodeId = episodeId,
            episodeTitle = "Episode",
            showTitle = "—",
            authorLine = "—",
            duration = 0.0,
        )
    }

    private val canUseServer: Boolean get() = session.mayUseServerNetwork && session.isNetworkReachable.value

    /** iOS: `AppModel.play(book:resumeAtOverride:autoPlay:)` — gemeinsamer Einstieg [LibraryPlayback.play]. */
    suspend fun playBook(book: AbsBook, resumeAtOverride: Double? = null, autoPlay: Boolean = true) {
        _isPreparingPlayback.value = true
        try {
            LibraryPlayback.play(model.appContext, book, resumeAtOverride = resumeAtOverride, autoPlay = autoPlay, model = model)
        } finally {
            _isPreparingPlayback.value = false
        }
    }

    /** iOS: `playPodcastEpisode(_:autoPlay:resumeAtOverride:)`. */
    suspend fun playPodcastEpisode(episode: AbsPodcastEpisodeListItem, autoPlay: Boolean = true, resumeAtOverride: Double? = null) {
        val offlineKey = DownloadManager.podcastEpisodeOfflineStorageId(episode)
        val local = DownloadManager.localDownloadRoot(offlineKey, downloads.downloadedIds.value)
        if (session.offlineHomeUIActive && local == null) {
            session.setErrorMessage("Download this episode to play it offline.")
            return
        }
        val c = session.clientForOfflineLocalPlayback() ?: return
        _isPreparingPlayback.value = true
        try {
            session.setErrorMessage(null)
            progressStore.ensureLocalProgressLoaded()
            val key = episode.progressLookupKey
            // iOS: `resolvedPlaybackStart` — Override, nach „fertig“ von vorn, sonst gespeicherte Position.
            val (resume, restart) = when {
                resumeAtOverride != null -> maxOf(0.0, resumeAtOverride) to (resumeAtOverride <= 0.001)
                progressStore.isLocallyMarkedFinished(key) -> 0.0 to true
                else -> (progress(key)?.currentTime ?: 0.0) to false
            }
            if (restart) preparePlaybackRestartFromBeginning(episode.libraryItemId, episode.episodeId, key)
            val stub = episode.playbackStubBook(session.selectedPodcastLibrary.value?.id ?: episode.libraryId)
            // iOS: `transcriptionLanguageOverride: podcastShowTranscriptionLanguage(for:)` — Sprache der Sendung.
            PlaybackTranscription.setTranscriptionLanguageOverride(episode.libraryItemId, podcastShowTranscriptionLanguage(episode.libraryItemId))
            player.playBook(
                client = c,
                book = stub,
                resumeAt = resume,
                localDownloadRoot = local,
                episodeId = episode.episodeId,
                autoPlay = autoPlay,
                attemptServerPlaySession = canUseServer,
                preferClientResumePosition = restart || resumeAtOverride != null,
            )
            Prefs.setString(Keys.lastPlayedItemId, stub.id)
            if (autoPlay) {
                // iOS: `bumpOptimisticContinueListeningForPodcastEpisode` — Continue sofort mit lokalem Stand.
                val p = PlaybackHostBridge.optimisticProgress(progress(key), episode.libraryItemId, episode.episodeId, resume, episode.duration, System.currentTimeMillis())
                upsertProgress(p, markPendingServerSync = false)
            }
        } catch (e: CancellationException) {
            // Überholt von einem neueren Start — kein Fehler.
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _isPreparingPlayback.value = false
        }
    }

    /** iOS: `podcastShowTranscriptionLanguage(for:)` — Sprache aus den Metadaten der Sendung. */
    private fun podcastShowTranscriptionLanguage(showId: String): String? =
        model.podcasts.podcastShows.value.firstOrNull { it.id == showId }?.media?.metadata?.language?.swiftTrim()?.ifEmpty { null }

    /** iOS: `preparePlaybackRestartFromBeginning`. */
    private fun preparePlaybackRestartFromBeginning(libraryItemId: String, episodeId: String?, key: String) {
        progressStore.clearLocallyFinishedProgressKey(key)
        if (progress(key) != null) {
            progressStore.applyLocalMarkUnfinished(libraryItemId, episodeId)
            progressStore.markPendingLocalProgressSync(key)
            progress(key)?.let { fanOut(it) }
        }
        val c = session.client
        if (canUseServer && c != null) {
            // Nicht abwarten: lokal ist der Fortschritt schon zurückgesetzt.
            model.scope.launch {
                runCatching { c.patchProgress(libraryItemId, episodeId, AbsProgressPatch(currentTime = 0.0, progress = 0.0, isFinished = false)) }
            }
        }
    }

    // MARK: - Launch-Restore (iOS: `restoreLastPlayedOnLaunch`)

    override suspend fun restoreLastPlayedOnLaunch() {
        if (player.activeBook.value != null) return
        val c = session.client ?: (if (session.offlineHomeUIActive) session.clientForOfflineLocalPlayback() else null) ?: return
        progressStore.ensureLocalProgressLoaded()
        val progress = launchResumeProgress()
        if (progress == null || progress.isFinished) {
            Prefs.remove(Keys.lastPlayedItemId)
            return
        }
        val libraryItemId = progress.libraryItemId
        Prefs.setString(Keys.lastPlayedItemId, libraryItemId)
        val ep = progress.episodeId?.swiftTrim()?.ifEmpty { null }
        try {
            if (ep != null) {
                val episode = resolveEpisode(libraryItemId, ep)
                PlaybackTranscription.setTranscriptionLanguageOverride(episode.libraryItemId, podcastShowTranscriptionLanguage(episode.libraryItemId))
                val local = DownloadManager.localDownloadRoot(DownloadManager.podcastEpisodeOfflineStorageId(episode), downloads.downloadedIds.value)
                // Offline nur resumen, was auch lokal liegt — sonst hängt der Player im Ladezustand.
                if (local == null && !canUseServer) return
                player.playBook(
                    client = c,
                    book = episode.playbackStubBook(session.selectedPodcastLibrary.value?.id ?: episode.libraryId),
                    resumeAt = progress(episode.progressLookupKey)?.currentTime ?: progress.currentTime,
                    localDownloadRoot = local,
                    episodeId = episode.episodeId,
                    autoPlay = false,
                    attemptServerPlaySession = canUseServer,
                )
                return
            }
            val local = DownloadManager.localDownloadRoot(libraryItemId, downloads.downloadedIds.value)
            val manifest = local?.let { withContext(Dispatchers.IO) { AbsDownloadManifest.load(it) } }
            val book = when {
                manifest != null -> AbsBook.fromDownloadManifest(manifest)
                canUseServer -> c.item(libraryItemId, expanded = true)
                else -> return
            }
            // Während des Abrufs hat der Nutzer evtl. schon selbst gestartet.
            if (player.activeBook.value != null) return
            player.playBook(
                client = c,
                book = book,
                resumeAt = progress.currentTime,
                localDownloadRoot = local,
                episodeId = null,
                autoPlay = false,
                attemptServerPlaySession = canUseServer,
            )
        } catch (e: CancellationException) {
            // Überholt vom Nutzer-Tap.
        } catch (e: Exception) {
            Prefs.remove(Keys.lastPlayedItemId)
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    /** iOS: `launchResumeProgress` — zuletzt gespielter offener Titel, sonst der jüngste offene Fortschritt. */
    private fun launchResumeProgress(): AbsUserMediaProgress? {
        val open = progressStore.progressByItemId.value.values.filter {
            !it.isFinished && it.currentTime > HomeShelfLogic.continueListeningMinPositionSeconds &&
                !progressStore.isLocallyMarkedFinished(it.progressLookupKey) && !progressStore.isProgressKeyDiscarded(it.progressLookupKey)
        }
        if (open.isEmpty()) return null
        val lastId = Prefs.string(Keys.lastPlayedItemId)?.swiftTrim().orEmpty()
        if (lastId.isNotEmpty()) {
            open.filter { it.libraryItemId == lastId }.maxByOrNull { it.lastUpdate ?: 0L }?.let { return it }
        }
        return open.maxByOrNull { it.lastUpdate ?: 0L }
    }

    // MARK: - Server-Sync lokaler Fortschritte

    /**
     * iOS (Teil von `syncOfflineProgressToServer` + `flushPendingOfflineListeningTime`): Offline-Hörzeit
     * nachsenden, dann jede lokal geänderte Zeile per PATCH. Keys bleiben bei Fehlern stehen.
     */
    suspend fun syncPendingProgressToServer() {
        val c = session.client ?: return
        if (!canUseServer) return
        runCatching { bridge.flushPendingOfflineListeningTime() }
        val activeKey = player.activeBook.value?.let { NowPlayingState.progressKeyOf(it.id, player.activePlaybackEpisodeId.value) }
        for (key in progressStore.pendingLocalProgressSyncKeys) {
            // Laufende Remote-Session synct selbst.
            if (key == activeKey && player.isRemotePlaySessionActive) continue
            val p = progress(key)
            if (p == null) {
                progressStore.clearPendingLocalProgressSync(key)
                continue
            }
            try {
                if (p.isFinished) {
                    c.markFinished(p.libraryItemId, p.episodeId)
                    progressStore.clearLocallyFinishedProgressKey(key)
                } else {
                    c.patchProgress(p.libraryItemId, p.episodeId, AbsProgressPatch(currentTime = p.currentTime, duration = p.duration, progress = p.progress, isFinished = false))
                }
                progressStore.clearPendingLocalProgressSync(key)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Pending progress sync failed for $key: ${e.message}")
            }
        }
    }

    // MARK: - Bookmarks (iOS: `createBookmark`, `deleteBookmark`)

    /** iOS: `activeAudiobookBookmarkId` — nur Hörbücher haben Bookmarks. */
    val activeAudiobookBookmarkId: String?
        get() = player.activeBook.value?.id?.takeIf { player.activePlaybackEpisodeId.value.isNullOrBlank() }

    /** Bookmark an der aktuellen Position anlegen (`POST /api/me/item/:id/bookmark`). */
    suspend fun addBookmarkAtCurrentPosition(title: String): Boolean {
        val itemId = activeAudiobookBookmarkId ?: return false
        val c = session.client
        if (c == null || !canUseServer) {
            session.setErrorMessage("No network connection.")
            return false
        }
        val time = player.snapshotPlaybackTimeSeconds()
        val t = title.swiftTrim().ifEmpty { "Bookmark at ${formatPlaybackTime(time.toDouble())}" }
        return try {
            progressStore.upsertBookmark(c.createBookmark(itemId, time, t))
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e, forceDisplay = true)
            false
        }
    }

    suspend fun deleteBookmark(bookmark: AbsAudioBookmark): Boolean {
        val c = session.client
        if (c == null || !canUseServer) {
            session.setErrorMessage("No network connection.")
            return false
        }
        return try {
            c.deleteBookmark(bookmark.libraryItemId, bookmark.time)
            progressStore.removeBookmark(bookmark)
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e, forceDisplay = true)
            false
        }
    }

    // MARK: - Download-Knopf im Vollplayer (iOS: `startDownloadForActivePlayback` / `removeLocalDownloadForActivePlayback`)

    /** iOS: `currentPlaybackOfflineStorageId()`. */
    fun currentPlaybackOfflineStorageId(): String? = if (::bridge.isInitialized) bridge.offlineStorageIdForActivePlayback() else null

    /** iOS: `podcastEpisodeForActivePlayback()`. */
    fun podcastEpisodeForActivePlayback(): AbsPodcastEpisodeListItem? = if (::bridge.isInitialized) bridge.podcastEpisodeForActivePlayback() else null

    fun startDownloadForActivePlayback() {
        val book = player.activeBook.value ?: return
        NotificationPermission.requestIfNeeded(model.appContext)
        val ep = player.activePlaybackEpisodeId.value?.swiftTrim()?.ifEmpty { null }
        if (ep == null) {
            DownloadManager.startDownload(book)
        } else {
            val episode = podcastEpisodeForActivePlayback() ?: return
            DownloadManager.startDownloadPodcastEpisode(episode, book.libraryId ?: session.resolvedPodcastLibraryId())
        }
    }

    fun removeLocalDownloadForActivePlayback() {
        val sid = currentPlaybackOfflineStorageId() ?: return
        downloads.removeLocalDownload(sid)
    }

    // MARK: - Download fertig → lokal weiter (iOS: `applyLocalPlaybackIfDownloadMatchesCurrent`)

    /**
     * Nach abgeschlossenem Download auf lokale Dateien umschalten, wenn noch derselbe Titel aus dem Stream
     * läuft — gleiche Position, gleicher Play/Pause-Zustand, Sleep-Timer bleibt erhalten.
     */
    suspend fun applyLocalPlaybackIfDownloadMatchesCurrent(storageId: String) {
        val c = session.client ?: return
        val folder = DownloadManager.existingDownloadFolder(storageId) ?: return
        val manifest = withContext(Dispatchers.IO) { AbsDownloadManifest.load(folder) } ?: return
        val stub = AbsBook.fromDownloadManifest(manifest)
        val isOffline = player.isPlaybackFromOfflineDownload
        // Track-Prüfung liest das Dateisystem — erst nach den billigen Prüfungen, auf IO.
        val plan = withContext(Dispatchers.IO) {
            LocalDownloadSwitch.plan(
                activeItemId = player.activeBook.value?.id,
                activeEpisodeId = player.activePlaybackEpisodeId.value,
                isPlaybackFromOfflineDownload = isOffline,
                manifestItemId = manifest.libraryItemId,
                manifestEpisodeId = manifest.episodeId,
                globalPosition = player.globalPosition.value,
                isPlaying = player.isPlaying.value,
            ) { PlaybackController.allLocalTracksPresentForOfflinePlayback(folder, stub) }
        } ?: return
        val sleep = player.sleepTimerSnapshot()
        if (plan.episodeId != null) {
            PlaybackTranscription.setTranscriptionLanguageOverride(manifest.libraryItemId, podcastShowTranscriptionLanguage(manifest.libraryItemId))
        }
        try {
            player.playBook(
                client = c,
                book = stub,
                resumeAt = plan.resumeAt,
                localDownloadRoot = folder,
                episodeId = plan.episodeId,
                autoPlay = plan.autoPlay,
                attemptServerPlaySession = session.mayUseServerNetwork && session.isNetworkReachable.value,
            )
            sleep?.let { player.restoreSleepTimer(it) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "playBook failed: ${e.message}")
        }
    }

    // MARK: - Hörverlauf im Vollplayer (iOS: `loadCoverPanelDataIfNeeded` → `.sessions`)

    /** iOS: `model.isNetworkReachable` für den Leertext der Sessions-Liste. */
    val networkReachable: StateFlow<Boolean> get() = session.isNetworkReachable

    /**
     * iOS: Sessions-Panel — Folge über `loadPodcastEpisodeListeningSessions`, sonst Buchdetail (für die
     * `mediaId`) und `loadBookListeningSessions`. Beide cachen in Room und liefern offline den Cache.
     */
    suspend fun loadListeningSessionsForActivePlayback(): List<AbsListeningSession> {
        val book = player.activeBook.value ?: return emptyList()
        podcastEpisodeForActivePlayback()?.let { return model.podcasts.loadPodcastEpisodeListeningSessions(it) }
        val detail = model.catalog.loadBookDetail(book.id)
        return model.catalog.loadBookListeningSessions(book.id, detail?.mediaId ?: book.mediaId)
    }

    /** iOS: `onJumpToSessionStart` — Titel ab Session-Start neu starten (Folge bzw. Buch), Autoplay. */
    fun playFromListeningSessionStart(listeningSession: AbsListeningSession) {
        val book = player.activeBook.value ?: return
        val episode = podcastEpisodeForActivePlayback()
        model.scope.launch {
            if (episode != null) {
                playPodcastEpisode(episode, autoPlay = true, resumeAtOverride = listeningSession.startTime)
            } else {
                playBook(book, resumeAtOverride = listeningSession.startTime, autoPlay = true)
            }
        }
    }

    // MARK: - BrowseSource (Android Auto)

    override val isLoggedIn: Boolean get() = session.isLoggedIn.value

    override suspend fun continueListeningRows(): List<AbsStartShelfMergedRow> {
        fun rows() = model.home.startShelves.value
            .firstOrNull { it.category == HomeShelfLogic.homeContinueCategory }
            ?.let { s -> s.books.map { AbsStartShelfMergedRow.Book(it) } + s.podcastEpisodes.map { AbsStartShelfMergedRow.PodcastEpisode(it) } }
            .orEmpty()
        val current = rows()
        if (current.isNotEmpty()) return current
        runCatching { model.home.loadStartDashboard() }
        return rows()
    }

    override suspend fun downloadedRows(): List<AbsStartShelfMergedRow> = downloads.downloadedRows()

    override suspend fun libraryBookRows(): List<AbsStartShelfMergedRow>? =
        model.catalog.mergedInMemoryCatalogBooks().filter { it.isPlayableAudiobook }.takeIf { it.isNotEmpty() }
            ?.take(AUTO_ROW_LIMIT)?.map { AbsStartShelfMergedRow.Book(it) }

    override suspend fun podcastEpisodeRows(): List<AbsStartShelfMergedRow>? =
        model.podcasts.podcastEpisodes.value.takeIf { it.isNotEmpty() }?.take(AUTO_ROW_LIMIT)?.map { AbsStartShelfMergedRow.PodcastEpisode(it) }

    override fun coverUrl(libraryItemId: String): String? =
        AbsApiClient.normalizeServerURL(session.serverURL.value)?.let { AbsApiClient.itemCoverURL(it, libraryItemId, CoverImageTier.thumbnail) }

    override suspend fun play(row: AbsStartShelfMergedRow) {
        when (row) {
            is AbsStartShelfMergedRow.Book -> playBook(row.book)
            is AbsStartShelfMergedRow.PodcastEpisode -> playPodcastEpisode(row.episode)
        }
    }

    override suspend fun restoreLastPlayback(): Boolean {
        restoreLastPlayedOnLaunch()
        return player.activeBook.value != null
    }

    // MARK: - SessionParticipant

    override fun onSessionActivated() {
        downloads.loadForActiveAccount()
    }

    override fun onTokensRefreshed(accessToken: String, refreshToken: String) {
        player.adoptRefreshedTokens(accessToken, refreshToken)
    }

    override fun onSessionCleared(clearCredentials: Boolean) {
        if (clearCredentials) {
            player.tearDownPlayer()
            player.setMiniPlayerPlaceholder(false)
        }
        _nowPlayingPresented.value = false
        downloads.clearInMemory()
    }

    override suspend fun willSwitchAccount() {
        if (::bridge.isInitialized) bridge.recordActivePlaybackProgressLocally(markPendingServerSync = true)
        downloads.persistDownloads(skipRefresh = true)
        dismissPlayer(idlePlaceholder = false)
    }

    override fun onDeferredWorkAfterConnect() {
        model.scope.launch { syncPendingProgressToServer() }
    }

    override suspend fun prepareForOfflineHomeMode() {
        if (player.activeBook.value == null) return
        bridge.recordActivePlaybackProgressLocally(markPendingServerSync = true)
        player.suspendServerNetworkingForOfflineMode()
    }

    override suspend fun onOfflineHomeModeExited() {
        syncPendingProgressToServer()
    }

    // MARK: - Podcast-Brücke

    private inner class PlayerPodcastActions : PodcastActions {
        override val revision: StateFlow<Long> get() = _revision.asStateFlow()

        override fun play(episode: AbsPodcastEpisodeListItem, resumeAt: Double?) {
            if (resumeAt == null && _nowPlaying.value.isActive(episode.libraryItemId, episode.episodeId)) {
                player.play()
                return
            }
            model.scope.launch { playPodcastEpisode(episode, resumeAtOverride = resumeAt) }
        }

        override fun pause() = player.pause()

        override fun isPlaying(itemId: String, episodeId: String): Boolean = _nowPlaying.value.isPlaying(itemId, episodeId)

        override fun enqueueDownload(episode: AbsPodcastEpisodeListItem) {
            NotificationPermission.requestIfNeeded(model.appContext)
            DownloadManager.startDownloadPodcastEpisode(episode, episode.libraryId ?: session.resolvedPodcastLibraryId())
        }

        override fun removeDownload(itemId: String, episodeId: String) =
            downloads.removeLocalDownload(DownloadStatusSource.storageId(itemId, episodeId))

        override fun isDownloaded(itemId: String, episodeId: String): Boolean =
            downloads.isDownloaded(DownloadStatusSource.storageId(itemId, episodeId))

        override fun downloadProgress(itemId: String, episodeId: String): Double? =
            downloads.states.value[DownloadStatusSource.storageId(itemId, episodeId)]?.takeIf { it.isDownloading }?.progress

        override fun downloadedEpisodes(showId: String?, libraryId: String?): List<AbsPodcastEpisodeListItem> =
            downloads.downloadedEpisodes().filter { ep ->
                (showId == null || ep.libraryItemId == showId) &&
                    (libraryId == null || ep.libraryId == null || ep.libraryId == libraryId)
            }

        override fun removeAllDownloadsForShow(showId: String) {
            if (player.activeBook.value?.id == showId && !player.activePlaybackEpisodeId.value.isNullOrBlank()) {
                model.scope.launch { dismissPlayer(idlePlaceholder = false) }
            }
            downloads.storageIdsForLibraryItem(showId).forEach { downloads.removeLocalDownload(it) }
        }

        override fun isLocallyMarkedFinished(progressKey: String): Boolean = progressStore.isLocallyMarkedFinished(progressKey)
    }

    companion object {
        private const val TAG = "AbstandPlayer"
        /** Android Auto: Zeilen je zusätzlichem Tab (Bücher, Folgen — nicht in iOS-CarPlay). */
        private const val AUTO_ROW_LIMIT = 50
    }
}
