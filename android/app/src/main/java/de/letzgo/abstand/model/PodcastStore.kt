package de.letzgo.abstand.model

import android.util.Log
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.AbsListeningSessionsPayload
import de.letzgo.abstand.data.AbsPodcastCharts
import de.letzgo.abstand.data.AbsPodcastDirectorySearchHit
import de.letzgo.abstand.data.AbsPodcastEpisodeExpandedDetail
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsPodcastFeedPreview
import de.letzgo.abstand.data.AbsPodcastFeedPreviewEpisode
import de.letzgo.abstand.data.AbsPodcastRssFeedEpisodeDraft
import de.letzgo.abstand.data.AbsProgressPatch
import de.letzgo.abstand.data.AbsUser
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.AbstandErrorFilter
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.store.LocalLibraryStore
import de.letzgo.abstand.ui.podcasts.PodcastActions
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

/** Verzeichnis-/Charts-Zustand des „Add podcast“-Flows (iOS: `podcastDirectory*`/`podcastCharts*`). */
data class PodcastDirectoryState(
    val searchHits: List<AbsPodcastDirectorySearchHit> = emptyList(),
    val searchLoading: Boolean = false,
    val chartsHits: List<AbsPodcastDirectorySearchHit> = emptyList(),
    val chartsLoading: Boolean = false,
    val chartsSelectedGenreId: Int? = null,
    val countryOverride: String? = null,
    val effectiveCountry: String = "us",
    val subscribeInProgressHitId: String? = null,
    val previewByFeedURL: Map<String, AbsPodcastFeedPreview> = emptyMap(),
    val previewLoadingFeedURLs: Set<String> = emptySet(),
    val previewErrorByFeedURL: Map<String, String> = emptyMap(),
    val episodeDownloadInProgressKeys: Set<String> = emptySet(),
    val episodeDownloadRequestedKeys: Set<String> = emptySet(),
    val libraryEpisodeTitlesByShowId: Map<String, Set<String>> = emptyMap(),
)

/** iOS: `podcastAutoDownload*`-Entwurf einer Sendung. */
data class PodcastAutoDownloadSettings(
    val showId: String,
    val enabled: Boolean = false,
    val interval: PodcastAutoDownloadInterval = PodcastAutoDownloadInterval.default,
    val maxEpisodesToKeep: Int = 0,
    val maxNewEpisodesToDownload: Int = 3,
)

/** Admin-Zustand je Sendung (iOS: `podcastRss*`, `podcastAutoDownload*`, `podcastCheckNewInProgressShowId`). */
data class PodcastShowAdminState(
    val rssFeedCacheByShowId: Map<String, List<AbsPodcastRssFeedEpisodeDraft>> = emptyMap(),
    val rssFeedUnavailableByShowId: Map<String, String> = emptyMap(),
    val rssFeedLoadInProgressShowIds: Set<String> = emptySet(),
    val rssEpisodeDownloadInProgressDraftIds: Set<UUID> = emptySet(),
    val rssDraftCompletedIdsByShowId: Map<String, Set<UUID>> = emptyMap(),
    val autoDownload: PodcastAutoDownloadSettings? = null,
    val autoDownloadLoading: Boolean = false,
    val autoDownloadSaving: Boolean = false,
    val checkNewInProgressShowId: String? = null,
)

/**
 * Podcast-Domäne (iOS: `AppModelCatalogPodcasts.swift`, `AppModelPodcastDirectory.swift` und die
 * Podcast-Teile von `AppModel.swift`): Sendungs-Leiste, „New“-Feed, Folgen je Sendung mit lokaler
 * Sortierung, Verzeichnissuche/Charts/Abonnieren, RSS-Feed + Server-Download einzelner Folgen,
 * „Check new“, Auto-Download, Folge löschen. Cache-first über den [LocalLibraryStore]; hängt sich
 * per [SessionParticipant] in Bootstrap/Bibliothekswahl/Accountwechsel.
 *
 * Wiedergabe/Offline-Downloads laufen über [actions] (Player/Downloads werden separat portiert).
 * Fortschritt: eigener Spiegel aus `/authorize` + LocalStore ([progressByItemId]) — reicht für
 * Zeilen-Fortschritt und den „New“-Filter, bis ein gemeinsamer Progress-Store existiert.
 */
class PodcastStore(private val model: AppModel) : SessionParticipant {
    private val session: SessionStore get() = model.session

    /** Player-/Download-Brücke; der Integrator setzt die echte Implementierung. */
    @Volatile var actions: PodcastActions = PodcastActions.None

    // MARK: - Sortierung (iOS: `podcastCatalogSort*`, `podcastEpisodeSort*`)

    private val initialCatalogSort = loadPodcastCatalogSortState()
    private val _catalogSortField = MutableStateFlow(initialCatalogSort.first)
    val podcastCatalogSortField: StateFlow<PodcastCatalogSortField> = _catalogSortField.asStateFlow()
    private val _catalogSortDescending = MutableStateFlow(initialCatalogSort.second)
    val podcastCatalogSortDescending: StateFlow<Boolean> = _catalogSortDescending.asStateFlow()

    private val _episodeSortField = MutableStateFlow(
        PodcastEpisodeSortField.entries.firstOrNull { it.name == Prefs.string(Keys.podcastEpisodeSortField) }
            ?: PodcastEpisodeSortField.publishedAt,
    )
    /** Folgen-Sortierung einer gewählten Sendung — Standard: neueste zuerst. */
    val podcastEpisodeSortField: StateFlow<PodcastEpisodeSortField> = _episodeSortField.asStateFlow()
    private val _episodeSortDescending = MutableStateFlow(Prefs.bool(Keys.podcastEpisodeSortDescending, true))
    val podcastEpisodeSortDescending: StateFlow<Boolean> = _episodeSortDescending.asStateFlow()

    // MARK: - Katalog

    private val _podcastEpisodes = MutableStateFlow<List<AbsPodcastEpisodeListItem>>(emptyList())
    /** „New“-Feed (`/recent-episodes`, ohne beendete Folgen). */
    val podcastEpisodes: StateFlow<List<AbsPodcastEpisodeListItem>> = _podcastEpisodes.asStateFlow()

    private val _podcastShows = MutableStateFlow<List<AbsBook>>(emptyList())
    /** Sendungen der fokussierten Podcast-Bibliothek (Leiste), sortiert nach [podcastCatalogSortField]. */
    val podcastShows: StateFlow<List<AbsBook>> = _podcastShows.asStateFlow()

    private val _podcastShowsLoading = MutableStateFlow(false)
    val podcastShowsLoading: StateFlow<Boolean> = _podcastShowsLoading.asStateFlow()

    private val _isLoadingPodcasts = MutableStateFlow(false)
    val isLoadingPodcasts: StateFlow<Boolean> = _isLoadingPodcasts.asStateFlow()

    private val _selectedShowId = MutableStateFlow<String?>(null)
    /** Gewählte Sendung (`null` = „New“). */
    val podcastSelectedShowId: StateFlow<String?> = _selectedShowId.asStateFlow()

    private val _filteredEpisodes = MutableStateFlow<List<AbsPodcastEpisodeListItem>>(emptyList())
    /** Folgen der gewählten Sendung (unsortiert nach Nutzerwahl — Anzeige über [podcastEpisodesForPodcastsTab]). */
    val podcastFilteredEpisodes: StateFlow<List<AbsPodcastEpisodeListItem>> = _filteredEpisodes.asStateFlow()

    private val _episodesByShowId = MutableStateFlow<Map<String, List<AbsPodcastEpisodeListItem>>>(emptyMap())
    /** Cache der Folgenlisten je Sendung (iOS: `podcastFilteredEpisodesByShowId`). */
    val podcastEpisodesByShowId: StateFlow<Map<String, List<AbsPodcastEpisodeListItem>>> = _episodesByShowId.asStateFlow()

    private val _isLoadingShowEpisodes = MutableStateFlow(false)
    val isLoadingPodcastShowEpisodes: StateFlow<Boolean> = _isLoadingShowEpisodes.asStateFlow()

    private val _stripSectionId = MutableStateFlow(PodcastCatalogStripSection.newEpisodes)
    /** Auswahl der Leiste: [PodcastCatalogStripSection.newEpisodes] oder Show-ID. */
    val podcastCatalogStripSectionId: StateFlow<String> = _stripSectionId.asStateFlow()

    private val _progressByItemId = MutableStateFlow<Map<String, AbsUserMediaProgress>>(emptyMap())
    /** Fortschritt nach `progressLookupKey` (iOS: `progressByItemId`, nur Podcast-Sicht). */
    val progressByItemId: StateFlow<Map<String, AbsUserMediaProgress>> = _progressByItemId.asStateFlow()

    private val _directory = MutableStateFlow(PodcastDirectoryState())
    val directory: StateFlow<PodcastDirectoryState> = _directory.asStateFlow()

    private val _showAdmin = MutableStateFlow(PodcastShowAdminState())
    val showAdmin: StateFlow<PodcastShowAdminState> = _showAdmin.asStateFlow()

    // Paging / Serien
    private var podcastLibraryPage = 0
    private var podcastLibraryTotal = 0
    private var podcastEpisodesPagingFromRecentAPI = true
    private var showEpisodesLoadSerial = 0
    private var catalogSortReloadJob: Job? = null
    private var directorySearchJob: Job? = null
    private var directorySearchGeneration = 0
    private var chartsLoadedCountry: String? = null
    private var chartsLoadedGenreId: Int? = null
    private var lastPodcastCatalogServerSyncAt = 0L
    /** Bibliothek, zu der die Listen im Speicher gehören (Fokuswechsel leert sie). */
    private var loadedLibraryId: String? = null

    // MARK: - Abgeleitete Werte

    val podcastCatalogLibrary: AbsLibrary? get() = session.podcastCatalogLibrary

    /** iOS: `podcastCanManageShowsOnServer` — Admin/Root: abonnieren, RSS, Show-Einstellungen. */
    val podcastCanManageShowsOnServer: Boolean get() = session.isServerAdmin.value || session.isServerRoot.value

    private val isNetworkReachable: Boolean get() = session.isNetworkReachable.value

    private fun isLocallyMarkedFinished(progressKey: String): Boolean {
        val k = progressKey.swiftTrim()
        if (k.isEmpty()) return false
        if (actions.isLocallyMarkedFinished(k)) return true
        return _progressByItemId.value[k]?.isFinished == true
    }

    fun progress(episode: AbsPodcastEpisodeListItem): AbsUserMediaProgress? = _progressByItemId.value[episode.progressLookupKey]

    // MARK: - SessionParticipant

    override fun hasCachedBootstrapContent(): Boolean = _podcastEpisodes.value.isNotEmpty()

    override suspend fun restoreFromLocalStore(store: LocalLibraryStore, booksLibraryId: String?) {
        restoreProgressFromLocalStoreIfEmpty(store)
        restorePodcastCatalogFromLocalStore()
    }

    override fun onDeferredWorkAfterConnect() {
        if (session.selectedPodcastLibrary.value == null) return
        model.scope.launch { reloadPodcastLibrary(reset = true) }
    }

    override fun onAuthorizeUser(user: AbsUser, persistToDisk: Boolean) {
        val list = user.mediaProgress ?: return
        _progressByItemId.value = list.associateBy { it.progressLookupKey }
        pruneFinishedEpisodesFromNewFeed()
    }

    override fun onSessionCleared(clearCredentials: Boolean) {
        clearInMemoryState()
        _progressByItemId.value = emptyMap()
        _directory.value = PodcastDirectoryState()
    }

    override suspend fun reloadAfterAccountSwitch() {
        clearInMemoryState()
        _progressByItemId.value = emptyMap()
        session.currentLocalLibraryStore()?.let { restoreProgressFromLocalStoreIfEmpty(it) }
        restorePodcastCatalogFromLocalStore()
        reloadPodcastLibrary(reset = true)
    }

    override fun onPodcastLibrarySelected(library: AbsLibrary, changed: Boolean) {
        if (!changed && loadedLibraryId == library.id) return
        model.scope.launch {
            restorePodcastCatalogFromLocalStore()
            reloadPodcastLibrary(reset = true)
        }
    }

    override fun onPodcastLibraryCleared() = clearInMemoryState()

    override fun onPodcastLibraryFocused(library: AbsLibrary) {
        model.scope.launch {
            restorePodcastCatalogFromLocalStore()
            reloadPodcastLibrary(reset = true)
        }
    }

    override suspend fun reloadCatalogs() = reloadPodcastLibrary(reset = true)

    override suspend fun bootstrapLocalSessionOnly() {
        session.currentLocalLibraryStore()?.let { restoreProgressFromLocalStoreIfEmpty(it) }
        restorePodcastCatalogFromLocalStore()
    }

    override suspend fun onOfflineHomeModeExited() = reloadPodcastLibrary(reset = true)

    private fun clearInMemoryState() {
        catalogSortReloadJob?.cancel()
        showEpisodesLoadSerial++
        loadedLibraryId = null
        _podcastEpisodes.value = emptyList()
        _podcastShows.value = emptyList()
        _selectedShowId.value = null
        _filteredEpisodes.value = emptyList()
        _episodesByShowId.value = emptyMap()
        _stripSectionId.value = PodcastCatalogStripSection.newEpisodes
        _showAdmin.value = PodcastShowAdminState()
        podcastLibraryPage = 0
        podcastLibraryTotal = 0
        podcastEpisodesPagingFromRecentAPI = true
        lastPodcastCatalogServerSyncAt = 0L
    }

    private suspend fun restoreProgressFromLocalStoreIfEmpty(store: LocalLibraryStore) {
        if (_progressByItemId.value.isNotEmpty()) return
        val rows = runCatching { store.fetchAllProgress() }.getOrNull() ?: return
        if (_progressByItemId.value.isEmpty()) _progressByItemId.value = rows.associateBy { it.progressLookupKey }
    }

    /** iOS: `restorePodcastCatalogFromLocalStore` — Listen der Podcast-Bibliothek aus der lokalen DB. */
    suspend fun restorePodcastCatalogFromLocalStore() {
        val lib = podcastCatalogLibrary
        if (lib == null) {
            clearInMemoryState()
            return
        }
        if (loadedLibraryId != lib.id) {
            clearInMemoryState()
            loadedLibraryId = lib.id
        }
        val store = session.currentLocalLibraryStore() ?: return
        if (_podcastEpisodes.value.isEmpty()) applyPodcastListFromLocalStore(store, lib.id)
        val (sortKey, ascending) = currentShowsSortParams()
        store.fetchPodcastShows(lib.id, sortKey, ascending)?.let { if (podcastCatalogLibrary?.id == lib.id) _podcastShows.value = it }
    }

    /** iOS: `applyPodcastListFromLocalStore`. */
    private suspend fun applyPodcastListFromLocalStore(store: LocalLibraryStore, libraryId: String) {
        val lid = libraryId.swiftTrim()
        if (lid.isEmpty()) return
        val cached = runCatching { store.fetchPodcastEpisodes(lid) }.getOrNull() ?: return
        if (cached.items.isEmpty()) return
        if (podcastCatalogLibrary?.id != lid) return
        val rows = PodcastLogic.unplayedForNewFeed(AbsPodcastEpisodeListItem.dedupeRows(cached.items), ::isLocallyMarkedFinished)
        _podcastEpisodes.value = rows
        podcastLibraryTotal = maxOf(cached.total, rows.size)
        podcastEpisodesPagingFromRecentAPI = cached.pagingFromRecentAPI
        podcastLibraryPage = if (cached.pagingFromRecentAPI) (rows.size + PodcastLogic.recentEpisodesPageLimit - 1) / PodcastLogic.recentEpisodesPageLimit else 1
    }

    private fun currentShowsSortParams(): Pair<String, Boolean> {
        val field = _catalogSortField.value
        val ascending = if (field == PodcastCatalogSortField.random) true else !_catalogSortDescending.value
        return field.apiSortParameter to ascending
    }

    // MARK: - Sortierung setzen

    /** iOS: `PodcastCatalogToolbarState.applySortField` → `schedulePodcastCatalogSortReload`. */
    fun setPodcastCatalogSortField(field: PodcastCatalogSortField) {
        if (_catalogSortField.value == field) return
        _catalogSortField.value = field
        Prefs.setString(Keys.podcastCatalogSortField, field.name)
        schedulePodcastCatalogSortReload()
    }

    fun setPodcastCatalogSortDescending(descending: Boolean) {
        if (_catalogSortDescending.value == descending) return
        _catalogSortDescending.value = descending
        Prefs.setBool(Keys.podcastCatalogSortDescending, descending)
        schedulePodcastCatalogSortReload()
    }

    /** Folgen werden lokal sortiert — kein Server-Reload. */
    fun setPodcastEpisodeSortField(field: PodcastEpisodeSortField) {
        if (_episodeSortField.value == field) return
        _episodeSortField.value = field
        Prefs.setString(Keys.podcastEpisodeSortField, field.name)
    }

    fun setPodcastEpisodeSortDescending(descending: Boolean) {
        if (_episodeSortDescending.value == descending) return
        _episodeSortDescending.value = descending
        Prefs.setBool(Keys.podcastEpisodeSortDescending, descending)
    }

    /** iOS: `schedulePodcastCatalogSortReload` — 350 ms entprellt, Shows neu; Feed nur in „New“. */
    fun schedulePodcastCatalogSortReload() {
        catalogSortReloadJob?.cancel()
        catalogSortReloadJob = model.scope.launch {
            delay(350)
            reloadPodcastShowsCatalog()
            if (_selectedShowId.value == null) reloadPodcastLibrary(reset = true)
        }
    }

    // MARK: - „New“-Feed

    /** iOS: `refreshCatalogsIfStaleOnForeground` (Podcast-Teil) — 15 min alter Abgleich → still neu laden. */
    fun refreshIfStaleOnForeground() {
        if (session.selectedPodcastLibrary.value == null || !session.mayUseServerNetwork || !isNetworkReachable) return
        if (System.currentTimeMillis() - lastPodcastCatalogServerSyncAt < CATALOG_STALE_REFRESH_MS) return
        model.scope.launch { reloadPodcastLibrary(reset = true) }
    }

    /** iOS: `reloadPodcastLibrary(reset:)`. */
    suspend fun reloadPodcastLibrary(reset: Boolean) {
        val lib = podcastCatalogLibrary ?: return
        val store = session.currentLocalLibraryStore()
        if (session.offlineHomeUIActive) {
            if (_podcastEpisodes.value.isEmpty() && store != null) applyPodcastListFromLocalStore(store, lib.id)
            reloadPodcastShowsCatalog()
            return
        }
        if (!isNetworkReachable) {
            if (_podcastEpisodes.value.isEmpty() && store != null) applyPodcastListFromLocalStore(store, lib.id)
            if (_podcastShows.value.isEmpty() && store != null) {
                val (sortKey, ascending) = currentShowsSortParams()
                store.fetchPodcastShows(lib.id, sortKey, ascending)?.let { _podcastShows.value = it }
            }
            return
        }
        val c = session.client ?: return
        _isLoadingPodcasts.value = true
        try {
            // Local-DB-First: bei Reset immer zuerst lokal anzeigen.
            if (reset && store != null) applyPodcastListFromLocalStore(store, lib.id)
            if (reset) {
                podcastLibraryPage = 0
                podcastEpisodesPagingFromRecentAPI = true
            }
            val pageIndex = podcastLibraryPage
            if (podcastEpisodesPagingFromRecentAPI) {
                val (res, _) = c.recentPodcastEpisodes(lib.id, page = pageIndex, limit = PodcastLogic.recentEpisodesPageLimit)
                if (podcastCatalogLibrary?.id != lib.id) return
                val rows = res.episodes.mapNotNull { AbsPodcastEpisodeListItem.fromDTO(it, libraryId = lib.id) }

                if (rows.isEmpty() && pageIndex == 0) {
                    val fallback = PodcastLogic.unplayedForNewFeed(loadPodcastEpisodesFallback(lib.id), ::isLocallyMarkedFinished)
                    if (fallback.isNotEmpty()) {
                        podcastEpisodesPagingFromRecentAPI = false
                        _podcastEpisodes.value = fallback
                        podcastLibraryTotal = fallback.size
                        podcastLibraryPage = 1
                        persistNewEpisodes(lib.id, fallback.size, pagingFromRecentAPI = false, fallback)
                        lastPodcastCatalogServerSyncAt = System.currentTimeMillis()
                        if (reset) reloadPodcastShowsCatalog()
                        return
                    }
                }

                if (reset) {
                    _podcastEpisodes.value = PodcastLogic.unplayedForNewFeed(AbsPodcastEpisodeListItem.dedupeRows(rows), ::isLocallyMarkedFinished)
                } else if (rows.isNotEmpty()) {
                    _podcastEpisodes.value = PodcastLogic.unplayedForNewFeed(
                        AbsPodcastEpisodeListItem.dedupeRows(_podcastEpisodes.value + rows), ::isLocallyMarkedFinished,
                    )
                }
                val count = _podcastEpisodes.value.size
                podcastLibraryTotal = if (rows.size >= PodcastLogic.recentEpisodesPageLimit) maxOf(res.total, count + 1) else count
                podcastLibraryPage = res.page + 1
                persistNewEpisodes(lib.id, podcastLibraryTotal, pagingFromRecentAPI = true, _podcastEpisodes.value)
                if (reset) lastPodcastCatalogServerSyncAt = System.currentTimeMillis()
                // Ganze Seite schon gehört → Liste leer ohne „mehr laden“-Zeile: nächste Seite direkt holen.
                if (_podcastEpisodes.value.isEmpty() && rows.size >= PodcastLogic.recentEpisodesPageLimit && res.page < 5) {
                    _isLoadingPodcasts.value = false
                    reloadPodcastLibrary(reset = false)
                }
            }
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _isLoadingPodcasts.value = false
        }
        if (reset) reloadPodcastShowsCatalog()
    }

    private suspend fun persistNewEpisodes(libraryId: String, total: Int, pagingFromRecentAPI: Boolean, items: List<AbsPodcastEpisodeListItem>) {
        val store = session.currentLocalLibraryStore() ?: return
        try {
            store.replacePodcastEpisodes(libraryId, total, pagingFromRecentAPI, items)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            Log.w(TAG, "LocalStore replacePodcastEpisodes failed: ${e.message}")
        }
    }

    /** iOS: `loadPodcastEpisodesFallback` — `/recent-episodes` leer: Folgen aus den ersten 15 Sendungen. */
    private suspend fun loadPodcastEpisodesFallback(libraryId: String): List<AbsPodcastEpisodeListItem> {
        val c = session.client ?: return emptyList()
        return try {
            val (sortKey, ascending) = currentShowsSortParams()
            val (page, _) = c.libraryItems(libraryId, page = 0, limit = 15, sort = sortKey, ascending = ascending, minified = true)
            val collected = ArrayList<AbsPodcastEpisodeListItem>(160)
            for (show in page.results.filter { it.isListablePodcastLibraryItem }) {
                val full = try { c.item(show.id, expanded = true) } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    continue
                }
                val eps = full.media.podcastEpisodes
                if (eps.isNullOrEmpty()) continue
                eps.mapNotNullTo(collected) { AbsPodcastEpisodeListItem.fromDTO(it, fallbackShow = full, libraryId = libraryId, forceLibraryItemId = full.id) }
            }
            AbsPodcastEpisodeListItem.dedupeRows(PodcastLogic.sortEpisodesNewestFirst(collected)).take(80)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            emptyList()
        }
    }

    /** iOS: `pruneFinishedEpisodesFromNewFeed` — nach Fortschritts-Updates beendete Folgen aus „New“ nehmen. */
    private fun pruneFinishedEpisodesFromNewFeed() {
        val current = _podcastEpisodes.value
        val kept = PodcastLogic.unplayedForNewFeed(current, ::isLocallyMarkedFinished)
        if (kept.size == current.size) return
        val removed = current.size - kept.size
        _podcastEpisodes.value = kept
        podcastLibraryTotal = maxOf(kept.size, podcastLibraryTotal - removed)
    }

    /** iOS: `loadMorePodcastsIfNeeded(currentItemId:)` — nächste `/recent-episodes`-Seite nahe dem Ende. */
    suspend fun loadMorePodcastsIfNeeded(currentItemId: String?) {
        if (session.offlineHomeUIActive) return
        if (_selectedShowId.value != null) return
        if (!podcastEpisodesPagingFromRecentAPI) return
        if (_isLoadingPodcasts.value) return
        val episodes = _podcastEpisodes.value
        if (!PodcastLogic.shouldPrefetchNextPage(currentItemId, episodes.map { it.id })) return
        if (episodes.size >= podcastLibraryTotal) return
        reloadPodcastLibrary(reset = false)
    }

    /** iOS: `refreshPodcastsTab` — Pull-to-Refresh (Fortschritt, Shows, „New“ bzw. gewählte Sendung). */
    suspend fun refreshPodcastsTab() {
        session.refreshProgressFromServer()
        reloadPodcastShowsCatalog()
        reloadPodcastLibrary(reset = true)
        _selectedShowId.value?.let { loadPodcastEpisodesForShowLibraryItem(it) }
    }

    // MARK: - Sendungen

    /** iOS: `reloadPodcastShowsCatalog`. */
    suspend fun reloadPodcastShowsCatalog() {
        val lib = podcastCatalogLibrary ?: return
        val (sortKey, ascending) = currentShowsSortParams()
        val store = session.currentLocalLibraryStore()
        if (session.offlineHomeUIActive) {
            // Offline: nur Sendungen mit mindestens einer heruntergeladenen Folge.
            val all = store?.fetchPodcastShows(lib.id, sortKey, ascending) ?: _podcastShows.value
            _podcastShows.value = all.filter { actions.downloadedEpisodes(it.id, null).isNotEmpty() }
            return
        }
        if (!isNetworkReachable) {
            store?.fetchPodcastShows(lib.id, sortKey, ascending)?.let { _podcastShows.value = it }
            return
        }
        val c = session.client ?: return
        _podcastShowsLoading.value = true
        try {
            val (page, _) = c.libraryItems(lib.id, page = 0, limit = PodcastLogic.showsCatalogLimit, sort = sortKey, ascending = ascending, minified = true)
            val rows = page.results.filter { it.isListablePodcastLibraryItem }
            if (store != null) {
                try {
                    store.replacePodcastShows(lib.id, sortKey, ascending, rows)
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    Log.w(TAG, "LocalStore replacePodcastShows failed: ${e.message}")
                }
            }
            if (podcastCatalogLibrary?.id == lib.id && currentShowsSortParams() == (sortKey to ascending)) _podcastShows.value = rows
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            Log.w(TAG, "Podcast shows refresh failed: ${e.message}")
        } finally {
            _podcastShowsLoading.value = false
        }
    }

    private fun replacePodcastShowInCatalog(updated: AbsBook) {
        _podcastShows.update { list -> list.map { if (it.id == updated.id) updated else it } }
    }

    /** iOS: `selectPodcastShowFilter` — sofort UI, danach Netz (Cache zuerst). */
    suspend fun selectPodcastShowFilter(showId: String?) {
        applyPodcastShowFilterSelection(showId)
        if (showId == null) {
            val lib = podcastCatalogLibrary
            val store = session.currentLocalLibraryStore()
            if (_podcastEpisodes.value.isEmpty() && lib != null && store != null) applyPodcastListFromLocalStore(store, lib.id)
            if (_podcastEpisodes.value.isEmpty()) reloadPodcastLibrary(reset = true)
            return
        }
        loadPodcastEpisodesForShowLibraryItem(showId)
    }

    /** Leiste: „New“ oder Sendung wählen (iOS: `onSelectSecondary` im Podcast-Strip). */
    fun selectStripSection(sectionId: String) {
        if (sectionId == PodcastCatalogStripSection.newEpisodes) {
            model.scope.launch { selectPodcastShowFilter(null) }
        } else {
            model.scope.launch { selectPodcastShowFilter(sectionId) }
        }
    }

    /** iOS: `applyPodcastShowFilterSelection`. */
    fun applyPodcastShowFilterSelection(showId: String?) {
        val sid = showId?.swiftTrim()?.ifEmpty { null }
        _selectedShowId.value = sid
        _stripSectionId.value = sid ?: PodcastCatalogStripSection.newEpisodes
        _filteredEpisodes.value = sid?.let { _episodesByShowId.value[it] } ?: emptyList()
    }

    private fun cacheShowEpisodes(showId: String, rows: List<AbsPodcastEpisodeListItem>) {
        _episodesByShowId.update { it + (showId to rows) }
        if (_selectedShowId.value == showId) _filteredEpisodes.value = rows
    }

    /** iOS: `loadPodcastEpisodesForShowLibraryItem` — Cache-first aus dem Show-Detail, dann Server. */
    suspend fun loadPodcastEpisodesForShowLibraryItem(showId: String) {
        val lib = podcastCatalogLibrary ?: run { _filteredEpisodes.value = emptyList(); return }
        val sid = showId.swiftTrim()
        if (sid.isEmpty()) {
            _filteredEpisodes.value = emptyList()
            return
        }
        if (!session.mayUseServerNetwork || !isNetworkReachable) {
            if (_selectedShowId.value != sid) return
            val pool = _podcastEpisodes.value.filter { it.libraryItemId == sid } + actions.downloadedEpisodes(sid, lib.id)
            val local = podcastShowEpisodesFromLocalStore(sid, lib.id) ?: emptyList()
            cacheShowEpisodes(sid, PodcastLogic.sortEpisodesNewestFirst(AbsPodcastEpisodeListItem.dedupeRows(local + pool)))
            return
        }
        val c = session.client ?: run { _filteredEpisodes.value = emptyList(); return }
        if (_episodesByShowId.value[sid].isNullOrEmpty()) {
            podcastShowEpisodesFromLocalStore(sid, lib.id)?.takeIf { it.isNotEmpty() }?.let { cacheShowEpisodes(sid, it) }
        }
        val serial = ++showEpisodesLoadSerial
        _isLoadingShowEpisodes.value = true
        try {
            var full = c.item(sid, expanded = true)
            if (serial != showEpisodesLoadSerial || _selectedShowId.value != sid) return
            if (full.media.podcastEpisodes.isNullOrEmpty()) {
                // Server liefert direkt nach dem Abonnieren gelegentlich noch keine Folgen.
                delay(450)
                if (serial != showEpisodesLoadSerial || _selectedShowId.value != sid) return
                full = c.item(sid, expanded = true)
                if (serial != showEpisodesLoadSerial || _selectedShowId.value != sid) return
            }
            val eps = full.media.podcastEpisodes
            if (eps.isNullOrEmpty()) {
                cacheShowEpisodes(sid, emptyList())
                return
            }
            cacheShowEpisodes(sid, PodcastLogic.episodesFromShowDetail(eps, full, lib.id))
            persistBookDetail(full)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            if (serial == showEpisodesLoadSerial && _selectedShowId.value == sid) session.publishErrorUnlessBenignCancellation(e)
        } finally {
            if (serial == showEpisodesLoadSerial) _isLoadingShowEpisodes.value = false
        }
    }

    private suspend fun podcastShowEpisodesFromLocalStore(showId: String, libraryId: String): List<AbsPodcastEpisodeListItem>? {
        val show = cachedBookDetail(showId) ?: return null
        val eps = show.media.podcastEpisodes
        if (eps.isNullOrEmpty()) return null
        return PodcastLogic.episodesFromShowDetail(eps, show, libraryId).ifEmpty { null }
    }

    private suspend fun cachedBookDetail(id: String): AbsBook? =
        session.currentLocalLibraryStore()?.let { runCatching { it.fetchBookDetail(id) }.getOrNull() }

    private suspend fun persistBookDetail(book: AbsBook) {
        val store = session.currentLocalLibraryStore() ?: return
        try {
            store.upsertBookDetail(book)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            Log.w(TAG, "LocalStore upsertBookDetail failed: ${e.message}")
        }
    }

    /**
     * iOS: `podcastEpisodesForPodcastsTab(showId:)` — `null` = „New“ (neueste zuerst), sonst die Folgen
     * der Sendung in Nutzer-Sortierung. Offline-Modus: nur heruntergeladene Folgen.
     */
    fun podcastEpisodesForPodcastsTab(showId: String?): List<AbsPodcastEpisodeListItem> {
        val sid = showId?.swiftTrim()?.ifEmpty { null }
        val libId = podcastCatalogLibrary?.id
        if (session.offlineHomeUIActive) {
            val downloaded = AbsPodcastEpisodeListItem.dedupeRows(actions.downloadedEpisodes(sid, libId))
            return if (sid == null) PodcastLogic.sortEpisodesNewestFirst(downloaded) else sortPodcastShowEpisodes(downloaded)
        }
        val offlineList = !isNetworkReachable
        if (sid != null) {
            var pool = when {
                _selectedShowId.value == sid && _filteredEpisodes.value.isNotEmpty() -> _filteredEpisodes.value
                _episodesByShowId.value[sid] != null -> _episodesByShowId.value.getValue(sid)
                else -> _podcastEpisodes.value.filter { it.libraryItemId == sid }
            }
            if (offlineList && pool.isEmpty()) pool = _podcastEpisodes.value.filter { it.libraryItemId == sid }
            if (offlineList) pool = pool + actions.downloadedEpisodes(sid, libId)
            return sortPodcastShowEpisodes(AbsPodcastEpisodeListItem.dedupeRows(pool))
        }
        var pool = _podcastEpisodes.value
        if (offlineList) pool = pool + actions.downloadedEpisodes(null, libId)
        return PodcastLogic.sortEpisodesNewestFirst(AbsPodcastEpisodeListItem.dedupeRows(pool))
    }

    fun sortPodcastShowEpisodes(rows: List<AbsPodcastEpisodeListItem>): List<AbsPodcastEpisodeListItem> =
        PodcastLogic.sortShowEpisodes(rows, _episodeSortField.value, _episodeSortDescending.value)

    // MARK: - Folgen-Detail

    /** iOS: `cachedPodcastEpisodeDetail` — aus dem persistierten Show-Detail. */
    suspend fun cachedPodcastEpisodeDetail(episode: AbsPodcastEpisodeListItem): AbsPodcastEpisodeExpandedDetail? =
        cachedBookDetail(episode.libraryItemId)?.let { makePodcastEpisodeDetail(episode, it) }

    /** iOS: `loadPodcastEpisodeDetail`. */
    suspend fun loadPodcastEpisodeDetail(episode: AbsPodcastEpisodeListItem): AbsPodcastEpisodeExpandedDetail {
        val c = session.client
        if (c == null || !isNetworkReachable || !session.mayUseServerNetwork) {
            return cachedPodcastEpisodeDetail(episode) ?: emptyPodcastEpisodeDetail(episode)
        }
        return try {
            val show = c.item(episode.libraryItemId, expanded = true)
            persistBookDetail(show)
            makePodcastEpisodeDetail(episode, show)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            cachedPodcastEpisodeDetail(episode) ?: emptyPodcastEpisodeDetail(episode)
        }
    }

    /** iOS: `loadPodcastEpisodeListeningSessions` — Item-Endpunkt, sonst gefilterte `/me/listening-sessions`. */
    suspend fun loadPodcastEpisodeListeningSessions(episode: AbsPodcastEpisodeListItem, maxPages: Int = 20): List<AbsListeningSession> {
        val bid = episode.libraryItemId.swiftTrim()
        val eid = episode.episodeId.swiftTrim()
        if (bid.isEmpty() || eid.isEmpty()) return emptyList()
        val store = session.currentLocalLibraryStore()
        val cached = store?.let { runCatching { it.fetchListeningSessions(bid, eid) }.getOrNull() }
        val c = session.client
        if (c == null || !isNetworkReachable || !session.mayUseServerNetwork) return cached ?: emptyList()
        val showMediaId = _podcastShows.value.firstOrNull { it.id == bid }?.mediaId?.swiftTrim()?.ifEmpty { null }

        suspend fun collectPaged(load: suspend (Int) -> AbsListeningSessionsPayload): List<AbsListeningSession> {
            val out = ArrayList<AbsListeningSession>()
            var page = 0
            while (page < maxPages) {
                val res = load(page)
                out.addAll(res.sessions)
                page++
                if (page >= res.numPages || res.sessions.isEmpty()) break
            }
            return out
        }

        suspend fun legacy(): List<AbsListeningSession> {
            val out = ArrayList<AbsListeningSession>()
            val eidLower = eid.lowercase()
            var page = 0
            while (page < maxPages) {
                val res = try { c.listeningSessionsMe(itemsPerPage = 100, page = page) } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    break
                }
                res.sessions.filterTo(out) { s ->
                    val sEp = s.episodeId?.swiftTrim() ?: ""
                    if (sEp.isEmpty() || sEp.lowercase() != eidLower) return@filterTo false
                    if (s.libraryItemId == bid) return@filterTo true
                    val b = s.bookId?.swiftTrim()
                    showMediaId != null && !b.isNullOrEmpty() && b == showMediaId
                }
                page++
                if (page >= res.numPages) break
            }
            return out.sortedByDescending { it.startedAt }
        }

        suspend fun persist(rows: List<AbsListeningSession>) {
            try {
                store?.replaceListeningSessions(bid, eid, rows)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
            }
        }

        return try {
            val rows = collectPaged { p -> c.listeningSessionsForLibraryItem(bid, eid, itemsPerPage = 100, page = p) }
            val sorted = if (rows.isNotEmpty()) rows.sortedByDescending { it.startedAt } else legacy()
            persist(sorted)
            sorted
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            val legacyRows = legacy()
            if (legacyRows.isNotEmpty()) {
                persist(legacyRows)
                legacyRows
            } else {
                cached ?: emptyList()
            }
        }
    }

    // MARK: - Fortschritt (iOS: `markPodcastEpisodeFinished/Unfinished`, `discardPodcastEpisodeProgress`)

    private fun applyLocalProgress(key: String, progress: AbsUserMediaProgress?) {
        _progressByItemId.update { if (progress == null) it - key else it + (key to progress) }
    }

    /**
     * Player-Tick / „Fertig“ aus der Wiedergabe ([PlayerWiring]): eine Zeile übernehmen. Persistiert
     * nicht — das übernimmt der Home-Store (eine Room-Zeile je Key, kein Doppel-Write).
     */
    fun applyProgressUpdate(progress: AbsUserMediaProgress) {
        if (progress.episodeId.isNullOrBlank()) return
        applyLocalProgress(progress.progressLookupKey, progress)
        if (progress.isFinished) pruneFinishedEpisodesFromNewFeed()
    }

    /** Folge als beendet markieren (`PATCH /api/me/progress/:id/:episodeId`). `true` bei Erfolg. */
    suspend fun markPodcastEpisodeFinished(episode: AbsPodcastEpisodeListItem): Boolean {
        val c = session.client ?: return false
        if (!isNetworkReachable) {
            session.setErrorMessage("No network connection.")
            return false
        }
        return try {
            c.markFinished(episode.libraryItemId, episode.episodeId)
            val old = progress(episode)
            val duration = maxOf(old?.duration ?: 0.0, episode.duration)
            val updated = AbsUserMediaProgress(
                mediaProgressServerId = old?.mediaProgressServerId, libraryItemId = episode.libraryItemId,
                episodeId = episode.episodeId, duration = duration, progress = 1.0, currentTime = duration,
                isFinished = true, lastUpdate = System.currentTimeMillis(),
            )
            applyLocalProgress(episode.progressLookupKey, updated)
            persistProgress(updated)
            pruneFinishedEpisodesFromNewFeed()
            session.refreshProgressFromServer()
            true
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
            false
        }
    }

    suspend fun markPodcastEpisodeUnfinished(episode: AbsPodcastEpisodeListItem): Boolean {
        val c = session.client ?: return false
        if (!isNetworkReachable) {
            session.setErrorMessage("No network connection.")
            return false
        }
        return try {
            c.patchProgress(episode.libraryItemId, episode.episodeId, AbsProgressPatch(isFinished = false))
            progress(episode)?.let { old ->
                val updated = old.copy(isFinished = false, lastUpdate = System.currentTimeMillis())
                applyLocalProgress(episode.progressLookupKey, updated)
                persistProgress(updated)
            }
            session.refreshProgressFromServer()
            true
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
            false
        }
    }

    /** Fortschritt + Hör-Sitzungen der Folge auf dem Server löschen. */
    suspend fun discardPodcastEpisodeProgress(episode: AbsPodcastEpisodeListItem): Boolean {
        val c = session.client ?: return false
        if (!isNetworkReachable) {
            session.setErrorMessage("No network connection.")
            return false
        }
        return try {
            val old = progress(episode)
            c.deleteMediaProgressForLibraryItem(episode.libraryItemId, episode.episodeId, listOfNotNull(old?.mediaProgressServerId))
            for (s in loadPodcastEpisodeListeningSessions(episode)) {
                try {
                    c.deleteListeningSession(s.id)
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                }
            }
            applyLocalProgress(episode.progressLookupKey, null)
            session.currentLocalLibraryStore()?.let { store ->
                runCatching { store.pruneProgress(_progressByItemId.value.keys) }
                runCatching { store.replaceListeningSessions(episode.libraryItemId, episode.episodeId, emptyList()) }
            }
            session.refreshProgressFromServer()
            true
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
            false
        }
    }

    private suspend fun persistProgress(p: AbsUserMediaProgress) {
        val store = session.currentLocalLibraryStore() ?: return
        try {
            store.upsertProgress(listOf(p))
        } catch (e: Exception) {
            if (e is CancellationException) throw e
        }
    }

    // MARK: - Verzeichnis (Apple Podcasts) + Charts

    /** iOS: `podcastDirectoryHitIsInLibrary`. */
    fun podcastDirectoryHitIsInLibrary(hit: AbsPodcastDirectorySearchHit): Boolean =
        podcastLibraryShowMatchingDirectoryHit(hit) != null

    /** iOS: `podcastLibraryShowMatchingDirectoryHit` — gleiche normalisierte Feed-URL. */
    fun podcastLibraryShowMatchingDirectoryHit(hit: AbsPodcastDirectorySearchHit): AbsBook? {
        val hitFeed = PodcastLogic.normalizedPodcastFeedURL(hit.feedUrl) ?: return null
        return _podcastShows.value.firstOrNull { PodcastLogic.normalizedPodcastFeedURL(it.media.metadata.feedUrl) == hitFeed }
    }

    /** iOS: `schedulePodcastDirectorySearch` — 420 ms entprellt, ab 2 Zeichen. */
    fun schedulePodcastDirectorySearch(term: String) {
        directorySearchJob?.cancel()
        val t = term.swiftTrim()
        val generation = ++directorySearchGeneration
        if (t.length < 2) {
            _directory.update { it.copy(searchHits = emptyList(), searchLoading = false) }
            return
        }
        _directory.update { it.copy(searchLoading = true) }
        directorySearchJob = model.scope.launch {
            delay(420)
            performPodcastDirectorySearch(t, generation)
        }
    }

    private suspend fun performPodcastDirectorySearch(term: String, generation: Int) {
        try {
            if (generation != directorySearchGeneration) return
            val c = session.client
            if (c == null || !isNetworkReachable) {
                _directory.update { it.copy(searchHits = emptyList()) }
                return
            }
            val hits = c.searchPodcastsDirectory(term, podcastDirectoryCountryCode())
            if (generation != directorySearchGeneration) return
            _directory.update { it.copy(searchHits = hits) }
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            if (generation != directorySearchGeneration) return
            session.publishErrorUnlessBenignCancellation(e)
            _directory.update { it.copy(searchHits = emptyList()) }
        } finally {
            if (generation == directorySearchGeneration) _directory.update { it.copy(searchLoading = false) }
        }
    }

    fun clearPodcastDirectorySearch() {
        directorySearchJob?.cancel()
        directorySearchGeneration++
        _directory.update { it.copy(searchHits = emptyList(), searchLoading = false) }
    }

    /** iOS: `defaultPodcastDirectoryCountryCode` — Server-Sprache, sonst Geräte-Region. */
    fun defaultPodcastDirectoryCountryCode(): String = AbsPodcastCharts.countryCode(session.serverSettings.value?.language)

    fun podcastDirectoryCountryCode(): String {
        val raw = _directory.value.countryOverride?.swiftTrim()?.lowercase() ?: ""
        return raw.ifEmpty { defaultPodcastDirectoryCountryCode() }
    }

    fun syncPodcastDirectoryEffectiveCountry() {
        val code = podcastDirectoryCountryCode()
        if (_directory.value.effectiveCountry != code) _directory.update { it.copy(effectiveCountry = code) }
    }

    fun setPodcastDirectoryCountryOverride(code: String) {
        val c = code.swiftTrim().lowercase()
        if (c.isEmpty()) return
        val changed = _directory.value.countryOverride != c
        _directory.update { it.copy(countryOverride = c) }
        syncPodcastDirectoryEffectiveCountry()
        if (!changed) return
        resetLoadedCharts()
    }

    fun clearPodcastDirectoryCountryOverride() {
        if (_directory.value.countryOverride == null) return
        _directory.update { it.copy(countryOverride = null) }
        syncPodcastDirectoryEffectiveCountry()
        resetLoadedCharts()
    }

    private fun resetLoadedCharts() {
        _directory.update { it.copy(chartsHits = emptyList()) }
        chartsLoadedCountry = null
        chartsLoadedGenreId = null
    }

    fun clearPodcastCharts() {
        _directory.update { it.copy(chartsHits = emptyList(), chartsLoading = false, chartsSelectedGenreId = null) }
        chartsLoadedCountry = null
        chartsLoadedGenreId = null
    }

    fun selectPodcastChartsCategory(genreId: Int?) {
        if (_directory.value.chartsSelectedGenreId == genreId) return
        _directory.update { it.copy(chartsSelectedGenreId = genreId, chartsHits = emptyList()) }
        model.scope.launch { loadPodcastCharts(force = true) }
    }

    /** iOS: `loadPodcastCharts(force:)` — iTunes-Charts (direkt, nicht über den ABS-Server). */
    suspend fun loadPodcastCharts(force: Boolean = false) {
        if (!isNetworkReachable) {
            session.setErrorMessage("No network connection.")
            return
        }
        val state = _directory.value
        if (state.chartsLoading) return
        val country = podcastDirectoryCountryCode()
        val genreId = state.chartsSelectedGenreId
        if (!force && state.chartsHits.isNotEmpty() && chartsLoadedCountry == country && chartsLoadedGenreId == genreId) return
        _directory.update { it.copy(chartsLoading = true) }
        try {
            val hits = AbsPodcastCharts.fetchChart(country, genreId)
            _directory.update { it.copy(chartsHits = hits) }
            chartsLoadedCountry = country
            chartsLoadedGenreId = genreId
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
            _directory.update { it.copy(chartsHits = emptyList()) }
            chartsLoadedCountry = null
            chartsLoadedGenreId = null
        } finally {
            _directory.update { it.copy(chartsLoading = false) }
        }
    }

    /**
     * iOS: `subscribeToPodcastDirectoryHitReportingError` — `POST /api/podcasts` in den ersten
     * Ordner der Podcast-Bibliothek. `null` = Erfolg, sonst Fehlertext (leer = still).
     */
    suspend fun subscribeToPodcastDirectoryHitReportingError(hit: AbsPodcastDirectorySearchHit): String? {
        if (_directory.value.subscribeInProgressHitId != null) return ""
        val c = session.client
        val lib = podcastCatalogLibrary
        if (c == null || lib == null || !isNetworkReachable) return "No network connection."
        if ((hit.feedUrl ?: "").swiftTrim().isEmpty()) return "Missing RSS feed URL for this result."
        _directory.update { it.copy(subscribeInProgressHitId = hit.id) }
        return try {
            val first = c.libraryFolders(lib.id).firstOrNull() ?: return "No library folders found for this podcast library."
            c.createPodcastInLibrary(PodcastLogic.buildSubscribeRequestBody(hit, first.id, lib.id, first.fullPath))
            session.refreshProgressFromServer()
            reloadPodcastShowsCatalog()
            session.loadStartDashboard(skipAuthorizeRefresh = true, force = false)
            null
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            if (AbstandErrorFilter.isBenignCancellation(e)) "" else (e.message ?: e.toString())
        } finally {
            _directory.update { it.copy(subscribeInProgressHitId = null) }
        }
    }

    /** Abonnieren mit globaler Fehleranzeige (iOS: `subscribeToPodcastDirectoryHit`). */
    suspend fun subscribeToPodcastDirectoryHit(hit: AbsPodcastDirectorySearchHit): Boolean {
        val failure = subscribeToPodcastDirectoryHitReportingError(hit) ?: return true
        if (failure.isNotEmpty()) session.setErrorMessage(failure)
        return false
    }

    fun podcastDirectoryPreviewKey(hit: AbsPodcastDirectorySearchHit): String? = PodcastLogic.normalizedPodcastFeedURL(hit.feedUrl)

    fun podcastDirectoryPreview(hit: AbsPodcastDirectorySearchHit): AbsPodcastFeedPreview? =
        podcastDirectoryPreviewKey(hit)?.let { _directory.value.previewByFeedURL[it] }

    fun podcastDirectoryPreviewIsLoading(hit: AbsPodcastDirectorySearchHit): Boolean =
        podcastDirectoryPreviewKey(hit)?.let { it in _directory.value.previewLoadingFeedURLs } ?: false

    fun podcastDirectoryPreviewError(hit: AbsPodcastDirectorySearchHit): String? {
        val key = podcastDirectoryPreviewKey(hit) ?: return "This result has no RSS feed URL, so its episodes cannot be loaded."
        return _directory.value.previewErrorByFeedURL[key]
    }

    /** iOS: `loadPodcastDirectoryPreview` — Feed einmal je Sendung (Sitzungs-Cache). */
    suspend fun loadPodcastDirectoryPreview(hit: AbsPodcastDirectorySearchHit, forceReload: Boolean = false) {
        val key = podcastDirectoryPreviewKey(hit) ?: return
        val state = _directory.value
        if (!forceReload && state.previewByFeedURL[key] != null) return
        if (key in state.previewLoadingFeedURLs) return
        val c = session.client ?: return
        if (!isNetworkReachable) {
            _directory.update { it.copy(previewErrorByFeedURL = it.previewErrorByFeedURL + (key to "No network connection.")) }
            return
        }
        _directory.update { it.copy(previewLoadingFeedURLs = it.previewLoadingFeedURLs + key, previewErrorByFeedURL = it.previewErrorByFeedURL - key) }
        try {
            val requestFeedUrl = hit.feedUrl?.swiftTrim()?.ifEmpty { null } ?: key
            val data = c.fetchPodcastRssFeed(requestFeedUrl)
            val preview = AbsPodcastFeedPreview.fromFeedApiResponse(data).mergingDirectoryHitFallbacks(hit)
            _directory.update { it.copy(previewByFeedURL = it.previewByFeedURL + (key to preview), previewErrorByFeedURL = it.previewErrorByFeedURL - key) }
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            _directory.update { it.copy(previewErrorByFeedURL = it.previewErrorByFeedURL + (key to (e.message ?: e.toString()))) }
        } finally {
            _directory.update { it.copy(previewLoadingFeedURLs = it.previewLoadingFeedURLs - key) }
        }
    }

    fun podcastDirectoryEpisodeKey(episode: AbsPodcastFeedPreviewEpisode, hit: AbsPodcastDirectorySearchHit): String? =
        podcastDirectoryPreviewKey(hit)?.let { PodcastLogic.directoryEpisodeKey(it, episode.id) }

    /** Nur Server-Verwalter dürfen Folgen in die Bibliothek laden. */
    val podcastDirectoryCanDownloadEpisodes: Boolean get() = podcastCanManageShowsOnServer

    fun podcastDirectoryEpisodeIsInLibrary(episode: AbsPodcastFeedPreviewEpisode, hit: AbsPodcastDirectorySearchHit): Boolean {
        val show = podcastLibraryShowMatchingDirectoryHit(hit) ?: return false
        return _directory.value.libraryEpisodeTitlesByShowId[show.id]?.contains(episode.normalizedTitleKey) ?: false
    }

    /** iOS: `loadPodcastDirectoryLibraryEpisodeTitles` — vorhandene Folgen ohne Download-Button. */
    suspend fun loadPodcastDirectoryLibraryEpisodeTitles(hit: AbsPodcastDirectorySearchHit, forceReload: Boolean = false) {
        val show = podcastLibraryShowMatchingDirectoryHit(hit) ?: return
        if (!forceReload && _directory.value.libraryEpisodeTitlesByShowId[show.id] != null) return
        val c = session.client ?: return
        if (!isNetworkReachable) return
        try {
            val full = c.item(show.id, expanded = true)
            val titles = PodcastLogic.libraryEpisodeTitleKeys(full.media.podcastEpisodes ?: emptyList())
            _directory.update { it.copy(libraryEpisodeTitlesByShowId = it.libraryEpisodeTitlesByShowId + (show.id to titles)) }
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            // Still: ohne Liste bleibt der Download-Button sichtbar.
        }
    }

    /** iOS: `downloadPodcastDirectoryEpisode` — eine Feed-Folge auf den Server laden. */
    suspend fun downloadPodcastDirectoryEpisode(episode: AbsPodcastFeedPreviewEpisode, hit: AbsPodcastDirectorySearchHit): Boolean {
        if (!podcastDirectoryCanDownloadEpisodes || !episode.canDownloadToServer) return false
        val key = podcastDirectoryEpisodeKey(episode, hit) ?: return false
        val show = podcastLibraryShowMatchingDirectoryHit(hit) ?: return false
        val c = session.client ?: return false
        if (!isNetworkReachable) {
            session.setErrorMessage("No network connection.")
            return false
        }
        val state = _directory.value
        if (key in state.episodeDownloadInProgressKeys || key in state.episodeDownloadRequestedKeys) return false
        _directory.update { it.copy(episodeDownloadInProgressKeys = it.episodeDownloadInProgressKeys + key) }
        return try {
            c.downloadPodcastEpisodesToLibrary(show.id, PodcastLogic.singleEpisodeArrayBody(episode.episodePayloadJSON))
            // Server lädt asynchron — Titel sofort als vorhanden vormerken.
            _directory.update {
                val titles = (it.libraryEpisodeTitlesByShowId[show.id] ?: emptySet()) + episode.normalizedTitleKey
                it.copy(
                    episodeDownloadRequestedKeys = it.episodeDownloadRequestedKeys + key,
                    libraryEpisodeTitlesByShowId = it.libraryEpisodeTitlesByShowId + (show.id to titles),
                )
            }
            true
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
            false
        } finally {
            _directory.update { it.copy(episodeDownloadInProgressKeys = it.episodeDownloadInProgressKeys - key) }
        }
    }

    // MARK: - Sendungs-Verwaltung (Admin): RSS, Auto-Download, Check new, Löschen

    /** iOS: `preloadPodcastShowAdminContext` — Folgen, Auto-Download und RSS parallel. */
    suspend fun preloadPodcastShowAdminContext(showId: String) = coroutineScope {
        val sid = showId.swiftTrim()
        if (sid.isEmpty()) return@coroutineScope
        applyPodcastShowFilterSelection(sid)
        val episodes = async { loadPodcastEpisodesForShowLibraryItem(sid) }
        val settings = async { loadPodcastAutoDownloadSettings(sid) }
        val feed = async { loadPodcastRssFeedIntoEpisodeList(sid, forceReload = false) }
        episodes.await(); settings.await(); feed.await()
    }

    /** Gecachte RSS-Folgen einer Sendung (leer = noch nicht geladen). */
    fun podcastRssFeedCachedDrafts(showId: String): List<AbsPodcastRssFeedEpisodeDraft> =
        _showAdmin.value.rssFeedCacheByShowId[showId] ?: emptyList()

    /** iOS: `podcastFeedEpisodes(forShowId:)` — Bibliotheks-Folgen der gewählten Sendung. */
    fun podcastFeedEpisodes(showId: String): List<AbsPodcastEpisodeListItem> =
        if (_selectedShowId.value == showId) _filteredEpisodes.value else emptyList()

    /** iOS: `libraryEpisodeMatchingPodcastRssDraft` — Titel + Veröffentlichungsdatum. */
    fun libraryEpisodeMatchingPodcastRssDraft(draft: AbsPodcastRssFeedEpisodeDraft, showId: String): AbsPodcastEpisodeListItem? {
        val sid = showId.swiftTrim()
        if (sid.isEmpty() || _selectedShowId.value != sid) return null
        return _filteredEpisodes.value.firstOrNull { draft.matchesLibraryEpisode(it) }
    }

    /** iOS: `ensurePodcastRssFeedLoaded` — nur laden, wenn Cache leer (oder [forceReload]). */
    suspend fun ensurePodcastRssFeedLoaded(showId: String, forceReload: Boolean = false) {
        if (!podcastCanManageShowsOnServer || showId.isEmpty()) return
        val st = _showAdmin.value
        if (!forceReload && st.rssFeedUnavailableByShowId[showId] != null) return
        if (!forceReload && podcastRssFeedCachedDrafts(showId).isNotEmpty()) return
        loadPodcastRssFeedIntoEpisodeList(showId, forceReload)
    }

    /** iOS: `loadPodcastRssFeedIntoEpisodeList` — `POST /api/podcasts/feed`, je Sendung gecacht (Memory + Room). */
    suspend fun loadPodcastRssFeedIntoEpisodeList(podcastLibraryItemId: String, forceReload: Boolean = false) {
        if (!podcastCanManageShowsOnServer) return
        val sid = podcastLibraryItemId.swiftTrim()
        if (sid.isEmpty()) return
        val st = _showAdmin.value
        if (!forceReload && st.rssFeedUnavailableByShowId[sid] != null) return
        if (!forceReload && !st.rssFeedCacheByShowId[sid].isNullOrEmpty()) return
        // Local-DB-First.
        if (!forceReload && hydratePodcastRssFeedCacheFromLocalStore(sid)) {
            if (!session.mayUseServerNetwork || !isNetworkReachable || session.client == null) return
        }
        val c = session.client ?: return
        if (!isNetworkReachable) {
            if (podcastRssFeedCachedDrafts(sid).isEmpty()) session.setErrorMessage("No network connection.")
            return
        }
        if (sid in _showAdmin.value.rssFeedLoadInProgressShowIds) return
        _showAdmin.update { it.copy(rssFeedLoadInProgressShowIds = it.rssFeedLoadInProgressShowIds + sid) }
        try {
            val feedUrl = rssFeedUrlForPodcastShow(sid)
            if (feedUrl == null) {
                _showAdmin.update {
                    it.copy(
                        rssFeedUnavailableByShowId = it.rssFeedUnavailableByShowId + (sid to
                            "This show has no RSS feed URL. It may have been added from a folder instead of a feed subscription."),
                        rssFeedCacheByShowId = it.rssFeedCacheByShowId + (sid to emptyList()),
                    )
                }
                return
            }
            _showAdmin.update { it.copy(rssFeedUnavailableByShowId = it.rssFeedUnavailableByShowId - sid) }
            val data = c.fetchPodcastRssFeed(feedUrl)
            val drafts = AbsPodcastRssFeedEpisodeDraft.episodesFromFeedApiResponse(data)
            _showAdmin.update {
                it.copy(
                    rssFeedCacheByShowId = it.rssFeedCacheByShowId + (sid to drafts),
                    rssDraftCompletedIdsByShowId = if (forceReload) it.rssDraftCompletedIdsByShowId + (sid to emptySet()) else it.rssDraftCompletedIdsByShowId,
                )
            }
            session.currentLocalLibraryStore()?.let { store ->
                try {
                    store.replacePodcastRssFeed(sid, data.encodeToByteArray())
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    Log.w(TAG, "LocalStore replacePodcastRssFeed failed: ${e.message}")
                }
            }
            session.setErrorMessage(if (drafts.isEmpty()) "No episodes found in the feed." else null)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            if (podcastRssFeedCachedDrafts(sid).isEmpty()) session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _showAdmin.update { it.copy(rssFeedLoadInProgressShowIds = it.rssFeedLoadInProgressShowIds - sid) }
        }
    }

    private suspend fun hydratePodcastRssFeedCacheFromLocalStore(showId: String): Boolean {
        if (podcastRssFeedCachedDrafts(showId).isNotEmpty()) return true
        val store = session.currentLocalLibraryStore() ?: return false
        val raw = runCatching { store.fetchPodcastRssFeedRaw(showId) }.getOrNull() ?: return false
        val drafts = runCatching { AbsPodcastRssFeedEpisodeDraft.episodesFromFeedApiResponse(raw.decodeToString()) }.getOrNull()
        if (drafts.isNullOrEmpty()) return false
        _showAdmin.update { it.copy(rssFeedCacheByShowId = it.rssFeedCacheByShowId + (showId to drafts)) }
        return true
    }

    /** iOS: `rssFeedUrlForPodcastShow` — aus der Leiste, sonst aus dem rohen Item-JSON. */
    private suspend fun rssFeedUrlForPodcastShow(libraryItemId: String): String? {
        _podcastShows.value.firstOrNull { it.id == libraryItemId }?.let { show ->
            PodcastLogic.normalizedPodcastFeedURL(show.media.metadata.feedUrl)?.let { return it }
        }
        val c = session.client ?: return null
        return try {
            val data = c.itemResponseData(libraryItemId, expanded = true)
            PodcastLogic.extractPodcastFeedURL(data)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            null
        }
    }

    /** iOS: `downloadPodcastRssEpisodeDraft` — eine Feed-Folge auf den Server laden (`download-episodes`). */
    suspend fun downloadPodcastRssEpisodeDraft(draft: AbsPodcastRssFeedEpisodeDraft, podcastLibraryItemId: String) {
        if (!podcastCanManageShowsOnServer) return
        val c = session.client ?: return
        val sid = podcastLibraryItemId.swiftTrim()
        if (sid.isEmpty()) return
        if (!isNetworkReachable) {
            session.setErrorMessage("No network connection.")
            return
        }
        if (_selectedShowId.value != sid) applyPodcastShowFilterSelection(sid)
        if (_filteredEpisodes.value.isEmpty()) loadPodcastEpisodesForShowLibraryItem(sid)
        val st = _showAdmin.value
        if (draft.id in st.rssEpisodeDownloadInProgressDraftIds) return
        if (st.rssDraftCompletedIdsByShowId[sid]?.contains(draft.id) == true) return
        if (libraryEpisodeMatchingPodcastRssDraft(draft, sid) != null) return
        _showAdmin.update { it.copy(rssEpisodeDownloadInProgressDraftIds = it.rssEpisodeDownloadInProgressDraftIds + draft.id) }
        try {
            c.downloadPodcastEpisodesToLibrary(sid, PodcastLogic.singleEpisodeArrayBody(draft.episodePayloadJSON))
            _showAdmin.update {
                val done = (it.rssDraftCompletedIdsByShowId[sid] ?: emptySet()) + draft.id
                it.copy(rssDraftCompletedIdsByShowId = it.rssDraftCompletedIdsByShowId + (sid to done))
            }
            session.refreshProgressFromServer()
            mergeNewPodcastLibraryEpisodesFromExpandedItem(sid)
            session.setErrorMessage(null)
            session.loadStartDashboard(skipAuthorizeRefresh = true, force = false)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _showAdmin.update { it.copy(rssEpisodeDownloadInProgressDraftIds = it.rssEpisodeDownloadInProgressDraftIds - draft.id) }
        }
    }

    /** iOS: `mergeNewPodcastLibraryEpisodesFromExpandedItem` — nach `download-episodes` neue Folgen anhängen (mit Retry). */
    private suspend fun mergeNewPodcastLibraryEpisodesFromExpandedItem(showLibraryItemId: String) {
        val c = session.client ?: return
        val lib = podcastCatalogLibrary ?: return
        val sid = showLibraryItemId.swiftTrim()
        if (sid.isEmpty()) return
        if (_selectedShowId.value != sid) applyPodcastShowFilterSelection(sid)

        suspend fun attemptMerge(): Int {
            val full = c.item(sid, expanded = true)
            if (_selectedShowId.value != sid) return 0
            val eps = full.media.podcastEpisodes
            if (eps.isNullOrEmpty()) return 0
            val fetched = eps.mapNotNull { AbsPodcastEpisodeListItem.fromDTO(it, fallbackShow = full, libraryId = lib.id, forceLibraryItemId = full.id) }
            val merged = PodcastLogic.mergeNewShowEpisodes(_filteredEpisodes.value, fetched, sid) ?: return 0
            // Abweichung von iOS: auch den Show-Cache fortschreiben (iOS lässt ihn veralten).
            cacheShowEpisodes(sid, merged)
            return merged.size
        }

        delay(400)
        try {
            if (attemptMerge() == 0) {
                delay(650)
                attemptMerge()
            }
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            Log.w(TAG, "Deferred episode merge failed: ${e.message}")
        }
    }

    /** iOS: `loadPodcastAutoDownloadSettings`. */
    suspend fun loadPodcastAutoDownloadSettings(showId: String) {
        val sid = showId.swiftTrim()
        val c = session.client
        if (sid.isEmpty() || c == null) return
        _showAdmin.update { it.copy(autoDownloadLoading = true) }
        try {
            applyPodcastAutoDownloadSettings(c.item(sid, expanded = true), sid)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            if (_showAdmin.value.autoDownload?.showId == sid) session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _showAdmin.update { it.copy(autoDownloadLoading = false) }
        }
    }

    private fun applyPodcastAutoDownloadSettings(item: AbsBook, showId: String) {
        val m = item.media
        _showAdmin.update {
            it.copy(
                autoDownload = PodcastAutoDownloadSettings(
                    showId = showId,
                    enabled = m.autoDownloadEpisodes ?: false,
                    interval = PodcastAutoDownloadInterval.from(m.autoDownloadSchedule),
                    maxEpisodesToKeep = m.maxEpisodesToKeep ?: 0,
                    maxNewEpisodesToDownload = m.maxNewEpisodesToDownload ?: 3,
                ),
            )
        }
    }

    /**
     * iOS: Setter der Auto-Download-Bindings + `savePodcastAutoDownloadSettings` — Entwurf sofort
     * übernehmen und auf dem Server speichern (`PATCH /api/items/:id/media`).
     */
    suspend fun savePodcastAutoDownloadSettings(settings: PodcastAutoDownloadSettings) {
        val sid = settings.showId.swiftTrim()
        val c = session.client
        if (sid.isEmpty() || c == null || !isNetworkReachable) return
        val st = _showAdmin.value
        if (st.autoDownloadLoading || st.autoDownload?.showId != sid) return
        _showAdmin.update { it.copy(autoDownload = settings, autoDownloadSaving = true) }
        try {
            c.patchPodcastMediaAutoDownload(
                itemId = sid,
                autoDownloadEpisodes = settings.enabled,
                autoDownloadSchedule = settings.interval.cronExpression,
                maxEpisodesToKeep = settings.maxEpisodesToKeep,
                maxNewEpisodesToDownload = settings.maxNewEpisodesToDownload,
            )
            val item = c.item(sid, expanded = true)
            replacePodcastShowInCatalog(item)
            applyPodcastAutoDownloadSettings(item, sid)
            session.setErrorMessage(null)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _showAdmin.update { it.copy(autoDownloadSaving = false) }
        }
    }

    /** iOS: `checkAndDownloadNewPodcastEpisodes` — `GET …/checknew`, danach Listen + Feed neu. */
    suspend fun checkAndDownloadNewPodcastEpisodes(showId: String) {
        val sid = showId.swiftTrim()
        val c = session.client
        if (sid.isEmpty() || c == null) return
        if (!isNetworkReachable) {
            session.setErrorMessage("No network connection.")
            return
        }
        if (_showAdmin.value.checkNewInProgressShowId == sid) return
        _showAdmin.update { it.copy(checkNewInProgressShowId = sid) }
        try {
            c.checkNewPodcastEpisodes(sid, podcastCheckNewDownloadLimit(sid))
            mergeNewPodcastLibraryEpisodesFromExpandedItem(sid)
            session.refreshProgressFromServer()
            if (_selectedShowId.value == sid) {
                reloadPodcastShowsCatalog()
                loadPodcastEpisodesForShowLibraryItem(sid)
            }
            _showAdmin.update {
                it.copy(rssFeedCacheByShowId = it.rssFeedCacheByShowId - sid, rssDraftCompletedIdsByShowId = it.rssDraftCompletedIdsByShowId - sid)
            }
            loadPodcastRssFeedIntoEpisodeList(sid, forceReload = true)
            loadPodcastAutoDownloadSettings(sid)
            session.loadStartDashboard(skipAuthorizeRefresh = true, force = false)
            session.setErrorMessage(null)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _showAdmin.update { it.copy(checkNewInProgressShowId = null) }
        }
    }

    /** `null` = kein API-Limit („No limit“ = 0). */
    private fun podcastCheckNewDownloadLimit(sid: String): Int? {
        val draft = _showAdmin.value.autoDownload
        val raw = if (draft?.showId == sid) draft.maxNewEpisodesToDownload
        else _podcastShows.value.firstOrNull { it.id == sid }?.media?.maxNewEpisodesToDownload
        return raw?.takeIf { it > 0 }
    }

    /** iOS: `deletePodcastEpisodeFromLibrary` — Folge auf dem Server löschen (Admin). */
    suspend fun deletePodcastEpisodeFromLibrary(showLibraryItemId: String, episode: AbsPodcastEpisodeListItem) {
        val sid = showLibraryItemId.swiftTrim()
        val eid = episode.episodeId.swiftTrim()
        val c = session.client
        if (sid.isEmpty() || eid.isEmpty() || c == null || !podcastCanManageShowsOnServer) return
        if (!isNetworkReachable) {
            session.setErrorMessage("No network connection.")
            return
        }
        try {
            c.deletePodcastEpisode(sid, eid)
            // Abweichung von iOS: auch Show-Cache und „New“-Feed bereinigen (iOS zeigt die Folge dort weiter).
            val key = episode.progressLookupKey
            _filteredEpisodes.update { list -> list.filterNot { it.libraryItemId == sid && it.episodeId == eid } }
            _episodesByShowId.update { map -> map[sid]?.let { map + (sid to it.filterNot { e -> e.episodeId == eid }) } ?: map }
            _podcastEpisodes.update { list -> list.filterNot { it.progressLookupKey == key } }
            if (actions.isDownloaded(sid, eid)) actions.removeDownload(sid, eid)
            applyLocalProgress(key, null)
            session.refreshProgressFromServer()
            reloadPodcastShowsCatalog()
            session.setErrorMessage(null)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    /** iOS: `removePodcastShowFromLibrary` — Sendung auf dem Server löschen (`DELETE /api/items/:id`). */
    suspend fun removePodcastShowFromLibrary(showLibraryItemId: String): Boolean {
        val c = session.client ?: return false
        if (!isNetworkReachable) {
            session.setErrorMessage("No network connection.")
            return false
        }
        val sid = showLibraryItemId.swiftTrim()
        if (sid.isEmpty()) return false
        showEpisodesLoadSerial++
        try {
            c.deleteLibraryItem(sid)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            session.publishErrorUnlessBenignCancellation(e)
            return false
        }
        session.setErrorMessage(null)
        _showAdmin.update {
            it.copy(
                rssFeedLoadInProgressShowIds = it.rssFeedLoadInProgressShowIds - sid,
                rssFeedCacheByShowId = it.rssFeedCacheByShowId - sid,
                rssDraftCompletedIdsByShowId = it.rssDraftCompletedIdsByShowId - sid,
                rssFeedUnavailableByShowId = it.rssFeedUnavailableByShowId - sid,
                autoDownload = null,
            )
        }
        session.currentLocalLibraryStore()?.let { runCatching { it.deletePodcastRssFeed(sid) } }
        actions.removeAllDownloadsForShow(sid)
        _podcastShows.update { list -> list.filterNot { it.id == sid } }
        _podcastEpisodes.update { list -> list.filterNot { it.libraryItemId == sid } }
        _filteredEpisodes.update { list -> list.filterNot { it.libraryItemId == sid } }
        _episodesByShowId.update { it - sid }
        if (_selectedShowId.value == sid) selectPodcastShowFilter(null) else reloadPodcastLibrary(reset = true)
        reloadPodcastShowsCatalog()
        session.refreshProgressFromServer()
        session.loadStartDashboard(skipAuthorizeRefresh = true, force = false)
        return true
    }

    // MARK: - Sortier-Startzustand

    /** iOS: `loadPodcastCatalogSortState` — ohne eigenen Wert aus der Bücher-Sortierung migrieren. */
    private fun loadPodcastCatalogSortState(): Pair<PodcastCatalogSortField, Boolean> {
        if (Prefs.has(Keys.podcastCatalogSortField)) {
            val field = PodcastLogic.migratePodcastCatalogSortField(Prefs.string(Keys.podcastCatalogSortField) ?: "")
            return field to Prefs.bool(Keys.podcastCatalogSortDescending)
        }
        val bookRaw = Prefs.string(Keys.catalogSortField) ?: ""
        val field = PodcastLogic.migratePodcastCatalogSortFromBookCatalog(bookRaw) ?: PodcastCatalogSortField.title
        val descending = Prefs.bool(Keys.catalogSortDescending)
        Prefs.setString(Keys.podcastCatalogSortField, field.name)
        Prefs.setBool(Keys.podcastCatalogSortDescending, descending)
        return field to descending
    }

    companion object {
        private const val TAG = "PodcastStore"
        /** iOS: `catalogStaleRefreshInterval` (15 min). */
        private const val CATALOG_STALE_REFRESH_MS = 15 * 60 * 1000L

        /** iOS: `makePodcastEpisodeDetail(episode:show:)`. */
        fun makePodcastEpisodeDetail(episode: AbsPodcastEpisodeListItem, show: AbsBook): AbsPodcastEpisodeExpandedDetail {
            val dto = show.media.podcastEpisodes?.firstOrNull { it.id == episode.episodeId }
            val meta = show.media.metadata
            return AbsPodcastEpisodeExpandedDetail(
                episode = episode,
                subtitle = dto?.subtitle,
                episodeDescriptionHTML = dto?.description,
                showDescriptionHTML = meta.descriptionPlain ?: meta.description,
                pubDate = dto?.pubDate,
                showGenres = meta.genres,
                showAuthors = meta.authors ?: emptyList(),
            )
        }

        /** iOS: `emptyPodcastEpisodeDetail`. */
        fun emptyPodcastEpisodeDetail(episode: AbsPodcastEpisodeListItem) = AbsPodcastEpisodeExpandedDetail(
            episode = episode, subtitle = null, episodeDescriptionHTML = null, showDescriptionHTML = null,
            pubDate = null, showGenres = null, showAuthors = emptyList(),
        )
    }
}
