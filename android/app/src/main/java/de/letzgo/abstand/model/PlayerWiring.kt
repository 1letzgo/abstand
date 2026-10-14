package de.letzgo.abstand.model

import android.net.ConnectivityManager
import android.util.Log
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsProgressPatch
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import de.letzgo.abstand.data.AbsUser
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.downloads.DownloadMaintenance
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.player.AbstandPlaybackService
import de.letzgo.abstand.player.BrowseSource
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.player.PlaybackHost
import de.letzgo.abstand.player.PlaybackHostBridge
import de.letzgo.abstand.store.LocalLibraryStore
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
import kotlinx.coroutines.withTimeoutOrNull

/**
 * iOS: Player-Teil von `AppModel` — `play(book:)`, `playPodcastEpisode`, `restoreLastPlayedOnLaunch`,
 * `markFinished`/`markPodcastEpisodeFinished` aus der Wiedergabe, `dismissPlayer`, Bookmarks,
 * `requestPresentNowPlayingSheet`, Download-Knopf im Vollplayer — plus die Verdrahtung der Player-
 * Schnittstellen ([PlaybackHost], [BrowseSource] für Android Auto, [PlaybackLauncher] für Karten,
 * [PodcastActions] für den Podcast-Tab, Download-Host über [downloads]).
 *
 * Fortschritt hat eine Quelle: der Home-Store ([HomeStore.progressByItemId], persistiert per
 * `upsertProgress`); der Podcast-Spiegel bekommt jede Player-Zeile mit ([PodcastStore.applyProgressUpdate]).
 *
 * Erzeugt im [AppModel]-Konstruktor (vor `start()`), verdrahtet in `AbstandApplication.onCreate` per [attach].
 */
class PlayerWiring(private val model: AppModel) : SessionParticipant, PlaybackHost, BrowseSource, PlaybackLauncher {
    private val session: SessionStore get() = model.session

    /** iOS: `AppModel.player`. */
    val player: PlaybackController by lazy { PlaybackController.shared(model.appContext) }

    /** Download-Liste je Account, Badges, [de.letzgo.abstand.downloads.DownloadHost]. */
    val downloads = DownloadWiring(model)

    /** iOS: `pendingLocalProgressSyncKeys` / `localFinishedProgressKeys`. */
    val guards = ProgressGuards(model.session)

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

    private val _bookmarks = MutableStateFlow<List<AbsAudioBookmark>>(emptyList())
    /** iOS: `bookmarks` (aus `/authorize`, LocalStore-Spiegel). */
    val bookmarks: StateFlow<List<AbsAudioBookmark>> = _bookmarks.asStateFlow()

    private val _revision = MutableStateFlow(0L)

    /** Podcast-Tab-Brücke (iOS: `playPodcastEpisode`, `startDownloadPodcastEpisode`, …). */
    val podcastActions: PodcastActions = PlayerPodcastActions()

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
            }.distinctUntilChanged().collect {
                _nowPlaying.value = it
                _revision.value += 1
            }
        }
        model.scope.launch { downloads.revision.collect { _revision.value += 1 } }
        // Ohne Titel kein Vollplayer (z. B. nach „Fertig“ oder Logout).
        model.scope.launch {
            player.activeBook.collect { if (it == null && !_isPreparingPlayback.value) _nowPlayingPresented.value = false }
        }
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

    // MARK: - PlaybackHost

    override val apiClient: AbsApiClient?
        get() = session.client ?: if (session.offlineHomeUIActive) session.clientForOfflineLocalPlayback() else null

    override val mayUseServerNetwork: Boolean get() = session.mayUseServerNetwork

    override val isNetworkReachable: Boolean get() = session.isNetworkReachable.value

    override val isNetworkUnmetered: Boolean
        get() = model.appContext.getSystemService(ConnectivityManager::class.java)?.let { !it.isActiveNetworkMetered } ?: false

    override fun progress(progressKey: String): AbsUserMediaProgress? =
        model.home.progressByItemId.value[progressKey] ?: model.podcasts.progressByItemId.value[progressKey]

    override fun upsertProgress(progress: AbsUserMediaProgress, markPendingServerSync: Boolean) {
        model.home.applyProgressUpdate(progress, persistToDisk = true)
        model.podcasts.applyProgressUpdate(progress)
        if (markPendingServerSync) guards.addPending(progress.progressLookupKey)
    }

    override fun clearPendingLocalProgressSync(progressKey: String) = guards.removePending(progressKey)

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
        applyLocalMarkFinished(libraryItemId, ep, key)
        guards.addPending(key)
        val client = session.client
        if (!session.mayUseServerNetwork || !session.isNetworkReachable.value || client == null) {
            finishMarkFinishedLocally(storageId, wasCurrent, libraryItemId)
            return
        }
        try {
            // Play-Session VOR dem PATCH schließen — sonst setzt deren letzter Sync `isFinished` zurück (iOS-Kommentar).
            if (wasCurrent) dismissPlayer(idlePlaceholder = false)
            client.markFinished(libraryItemId, ep)
            guards.clearLocallyFinished(key)
            guards.removePending(key)
            session.refreshProgressFromServer()
            finishMarkFinishedLocally(storageId, wasPlaying = false, clearLastPlayedIfBookId = libraryItemId)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    /** iOS: `applyLocalMarkFinished` — Zeile auf fertig setzen und lokal merken. */
    private fun applyLocalMarkFinished(libraryItemId: String, episodeId: String?, key: String) {
        guards.markLocallyFinished(key)
        val existing = progress(key)
        val bookDur = model.home.startBooks.value.firstOrNull { it.id == libraryItemId }?.media?.duration
            ?: player.activeBook.value?.takeIf { it.id == libraryItemId }?.media?.duration
        val dur = maxOf(existing?.duration ?: 0.0, bookDur ?: 0.0, existing?.currentTime ?: 0.0, 1.0)
        val now = System.currentTimeMillis()
        val row = AbsUserMediaProgress(
            mediaProgressServerId = existing?.mediaProgressServerId,
            libraryItemId = libraryItemId,
            episodeId = episodeId,
            duration = dur,
            progress = 1.0,
            currentTime = dur,
            isFinished = true,
            lastUpdate = maxOf(now, (existing?.lastUpdate ?: 0L) + 1),
            ebookProgress = existing?.ebookProgress,
            ebookLocation = existing?.ebookLocation,
        )
        upsertProgress(row, markPendingServerSync = false)
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

    /** Item per ID auflösen (Regale, Downloads, LocalStore, Server) und starten. */
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
        downloads.downloadedBooks().firstOrNull { it.id == itemId }?.let { return it }
        val store = session.currentLocalLibraryStore()
        if (store != null) {
            val local = runCatching { store.fetchBookDetail(itemId) ?: store.fetchBook(itemId) }.getOrNull()
            if (local != null) return local
        }
        val c = session.client ?: return null
        if (!session.mayUseServerNetwork || !session.isNetworkReachable.value) return null
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

    /** iOS: `resolvedPlaybackStart(progressKey:resumeAtOverride:)`. */
    private fun resolvedPlaybackStart(progressKey: String, resumeAtOverride: Double?): Pair<Double, Boolean> {
        if (resumeAtOverride != null) return maxOf(0.0, resumeAtOverride) to (resumeAtOverride <= 0.001)
        if (guards.isLocallyFinished(progressKey) || progress(progressKey)?.isFinished == true) return 0.0 to true
        return (progress(progressKey)?.currentTime ?: 0.0) to false
    }

    /** iOS: `preparePlaybackRestartFromBeginning`. */
    private fun preparePlaybackRestartFromBeginning(libraryItemId: String, episodeId: String?, progressKey: String) {
        guards.clearLocallyFinished(progressKey)
        progress(progressKey)?.let { old ->
            upsertProgress(
                old.copy(isFinished = false, currentTime = 0.0, progress = 0.0, lastUpdate = maxOf(System.currentTimeMillis(), (old.lastUpdate ?: 0L) + 1)),
                markPendingServerSync = true,
            )
        }
        val c = session.client
        if (session.mayUseServerNetwork && session.isNetworkReachable.value && c != null) {
            // Nicht abwarten: lokal ist der Fortschritt schon zurückgesetzt.
            model.scope.launch {
                runCatching { c.patchProgress(libraryItemId, episodeId, AbsProgressPatch(currentTime = 0.0, progress = 0.0, isFinished = false)) }
            }
        }
    }

    private fun onPlaybackStarting() {
        NotificationPermission.requestIfNeeded(model.appContext)
    }

    /** iOS: `presentNowPlayingSheetOnAutoPlayIfNeeded` — Standard „an“, wenn nie gesetzt. */
    private fun presentNowPlayingOnAutoPlayIfNeeded() {
        if (session.offlineHomeUIActive) return
        if (!Prefs.bool(Keys.openPlayerWhenStartPlaying, true)) return
        _nowPlayingPresented.value = true
    }

    private val canUseServer: Boolean get() = session.mayUseServerNetwork && session.isNetworkReachable.value

    /** iOS: `AppModel.play(book:resumeAtOverride:autoPlay:)`. */
    suspend fun playBook(book: AbsBook, resumeAtOverride: Double? = null, autoPlay: Boolean = true) {
        val localInfo = DownloadManager.resolvedLocalDownloadForPlayback(book, downloads.downloadedIds.value)
        val local = localInfo?.root
        if (session.offlineHomeUIActive && local == null) {
            session.setErrorMessage("Download this title to play it offline.")
            return
        }
        val c = session.clientForOfflineLocalPlayback() ?: return
        if (autoPlay) onPlaybackStarting()
        _isPreparingPlayback.value = true
        try {
            session.setErrorMessage(null)
            val playbackItemId = localInfo?.libraryItemId ?: book.id
            val manifestEpisodeId = localInfo?.episodeId
            val progressKey = NowPlayingState.progressKeyOf(playbackItemId, manifestEpisodeId)
            val (resume, restart) = resolvedPlaybackStart(progressKey, resumeAtOverride)
            if (restart) preparePlaybackRestartFromBeginning(playbackItemId, manifestEpisodeId, progressKey)
            var resolved = book
            val manifest = local?.let { withContext(Dispatchers.IO) { AbsDownloadManifest.load(it) } }
            if (manifest != null) {
                val fromManifest = AbsBook.fromDownloadManifest(manifest)
                // Download liegt vor: Metadaten nur kurz nachladen — schlechter Empfang darf den Start nicht blockieren.
                val expanded = if (canUseServer && !book.media.metadata.hasRichMetadata) {
                    withTimeoutOrNull(2_000) { runCatching { c.item(playbackItemId, expanded = true) }.getOrNull() }
                } else null
                resolved = (expanded ?: book).mergingLocalDownloadPlayback(fromManifest)
            } else if (canUseServer) {
                val needsExpanded = local != null || book.media.tracks.isNullOrEmpty() || book.media.chapters.isNullOrEmpty()
                if (needsExpanded) {
                    try {
                        resolved = c.item(playbackItemId, expanded = true)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        Log.w(TAG, "Server item resolve failed, keeping local fallback: ${e.message}")
                    }
                }
            }
            player.playBook(
                client = c,
                book = resolved,
                resumeAt = resume,
                localDownloadRoot = local,
                episodeId = manifestEpisodeId,
                autoPlay = autoPlay,
                attemptServerPlaySession = canUseServer,
                preferClientResumePosition = restart || resumeAtOverride != null,
            )
            Prefs.setString(Keys.lastPlayedItemId, resolved.id)
            if (autoPlay) {
                bumpOptimisticProgress(playbackItemId, manifestEpisodeId, resume, resolved.media.duration ?: 0.0)
                presentNowPlayingOnAutoPlayIfNeeded()
                refreshDashboardAfterPlaybackStart()
            }
        } catch (e: CancellationException) {
            // Überholt von einem neueren Start — kein Fehler.
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
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
        if (autoPlay) onPlaybackStarting()
        _isPreparingPlayback.value = true
        try {
            session.setErrorMessage(null)
            val progressKey = episode.progressLookupKey
            val (resume, restart) = resolvedPlaybackStart(progressKey, resumeAtOverride)
            if (restart) preparePlaybackRestartFromBeginning(episode.libraryItemId, episode.episodeId, progressKey)
            val stub = episode.playbackStubBook(session.selectedPodcastLibrary.value?.id ?: episode.libraryId)
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
                bumpOptimisticProgress(episode.libraryItemId, episode.episodeId, resume, episode.duration)
                presentNowPlayingOnAutoPlayIfNeeded()
                refreshDashboardAfterPlaybackStart()
            }
        } catch (e: CancellationException) {
            // Überholt.
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _isPreparingPlayback.value = false
        }
    }

    /** iOS: `bumpOptimisticContinueListeningFor…` — Continue-Regal sofort mit lokalem Stand. */
    private fun bumpOptimisticProgress(itemId: String, episodeId: String?, resumeAt: Double, duration: Double) {
        val key = NowPlayingState.progressKeyOf(itemId, episodeId)
        val p = PlaybackHostBridge.optimisticProgress(progress(key), itemId, episodeId?.swiftTrim()?.ifEmpty { null }, resumeAt, duration, System.currentTimeMillis())
        upsertProgress(p, markPendingServerSync = false)
    }

    private fun refreshDashboardAfterPlaybackStart() {
        if (!session.mayUseServerNetwork) return
        model.scope.launch { runCatching { model.home.loadStartDashboard() } }
    }

    // MARK: - Launch-Restore (iOS: `restoreLastPlayedOnLaunch`)

    override suspend fun restoreLastPlayedOnLaunch() {
        if (player.activeBook.value != null) return
        val c = session.client ?: (if (session.offlineHomeUIActive) session.clientForOfflineLocalPlayback() else null) ?: return
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
        val all = model.home.progressByItemId.value.values
        val open = all.filter { !it.isFinished && it.currentTime > HomeShelfLogic.continueListeningMinPositionSeconds && !guards.isLocallyFinished(it.progressLookupKey) }
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
        for (key in guards.pendingKeys) {
            // Laufende Remote-Session synct selbst.
            if (key == activeKey && player.isRemotePlaySessionActive) continue
            val p = progress(key) ?: run { guards.removePending(key); null } ?: continue
            try {
                if (p.isFinished) {
                    c.markFinished(p.libraryItemId, p.episodeId)
                    guards.clearLocallyFinished(key)
                } else {
                    c.patchProgress(p.libraryItemId, p.episodeId, AbsProgressPatch(currentTime = p.currentTime, duration = p.duration, progress = p.progress, isFinished = false))
                }
                guards.removePending(key)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Pending progress sync failed for $key: ${e.message}")
            }
        }
    }

    // MARK: - Bookmarks (iOS: `bookmarks`, `createBookmark`, `deleteBookmark`)

    /** Bookmarks eines Hörbuchs, nach Zeit sortiert. */
    fun bookmarksFor(libraryItemId: String): List<AbsAudioBookmark> =
        _bookmarks.value.filter { it.libraryItemId == libraryItemId }.sortedBy { it.time }

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
        val t = title.swiftTrim().ifEmpty { "Bookmark at ${de.letzgo.abstand.ui.formatPlaybackTime(time.toDouble())}" }
        return try {
            val created = c.createBookmark(itemId, time, t)
            _bookmarks.value = _bookmarks.value.filterNot { it.id == created.id } + created
            persistBookmarks()
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
            _bookmarks.value = _bookmarks.value.filterNot { it.id == bookmark.id }
            persistBookmarks()
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e, forceDisplay = true)
            false
        }
    }

    private fun persistBookmarks() {
        val store = session.currentLocalLibraryStore() ?: return
        val list = _bookmarks.value
        model.scope.launch { runCatching { store.replaceAllBookmarks(list) } }
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

    override suspend fun podcastEpisodeRows(): List<AbsStartShelfMergedRow>? =
        model.podcasts.podcastEpisodes.value.takeIf { it.isNotEmpty() }?.take(AUTO_EPISODE_LIMIT)?.map { AbsStartShelfMergedRow.PodcastEpisode(it) }

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

    override suspend fun restoreFromLocalStore(store: LocalLibraryStore, booksLibraryId: String?) {
        if (_bookmarks.value.isEmpty()) _bookmarks.value = runCatching { store.fetchAllBookmarks() }.getOrDefault(emptyList())
    }

    override fun onSessionActivated() {
        guards.load()
        downloads.loadForActiveAccount()
    }

    override fun onAuthorizeUser(user: AbsUser, persistToDisk: Boolean) {
        val list = user.bookmarks ?: return
        _bookmarks.value = list
        if (persistToDisk) persistBookmarks()
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
        _bookmarks.value = emptyList()
        guards.clearInMemory()
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

        override fun isLocallyMarkedFinished(progressKey: String): Boolean = guards.isLocallyFinished(progressKey)
    }

    companion object {
        private const val TAG = "AbstandPlayer"
        /** Android Auto: neueste Folgen (nicht in iOS-CarPlay). */
        private const val AUTO_EPISODE_LIMIT = 50
    }
}
