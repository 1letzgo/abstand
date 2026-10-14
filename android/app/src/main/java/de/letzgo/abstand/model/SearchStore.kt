package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * iOS: Such-Teil von `AppModel.swift` (`searchText`, `scheduleUnifiedSearch`, `performSearch`,
 * `performPodcastLibrarySearch`, `applyLocalSearchResults`) — ein Suchtext durchsucht Bücher und
 * Podcasts zugleich. Lokale Treffer erscheinen sofort, der Server verfeinert danach.
 *
 * Abweichung: iOS sucht nur in der fokussierten Books-Bibliothek (`booksCatalogLibrary`); Android
 * durchsucht alle aktiven Books-Bibliotheken und führt die Treffer zusammen ([SearchLogic.mergeBookResponses]).
 */
class SearchStore internal constructor(private val model: AppModel) : SessionParticipant {
    private val session: SessionStore get() = model.session

    private val _query = MutableStateFlow("")
    /** iOS: `searchText`. */
    val query: StateFlow<String> = _query.asStateFlow()

    private val _results = MutableStateFlow(SearchResults())
    val results: StateFlow<SearchResults> = _results.asStateFlow()

    private val _isSearching = MutableStateFlow(false)
    /** iOS: `isSearchingBooks || isLoadingPodcasts` während der Suche. */
    val isSearching: StateFlow<Boolean> = _isSearching.asStateFlow()

    private var searchJob: Job? = null

    init {
        // iOS: Search-Tab `onDisappear` — beim Verlassen des Tabs Suche stoppen und leeren
        // (nicht beim Pushen einer Detailseite innerhalb des Tabs).
        model.scope.launch {
            session.mainTab.collect { tab -> if (tab != MainTab.search) cancelAndClear() }
        }
    }

    /** iOS: `searchText`-Binding + `scheduleUnifiedSearch` (Debounce 350 ms). */
    fun updateQuery(text: String) {
        if (text == _query.value) return
        _query.value = text
        scheduleUnifiedSearch()
    }

    /** iOS: `.onSubmit(of: .search)` — sofort statt nach Debounce. */
    fun submit() {
        searchJob?.cancel()
        val q = SearchLogic.normalizedQuery(_query.value)
        searchJob = model.scope.launch { performSearch(q) }
    }

    /** iOS: `scheduleUnifiedSearch`. */
    fun scheduleUnifiedSearch() {
        if (session.mainTab.value != MainTab.search) return
        searchJob?.cancel()
        val q = SearchLogic.normalizedQuery(_query.value)
        searchJob = model.scope.launch {
            delay(SearchLogic.debounceMillis)
            performSearch(q)
        }
    }

    /** iOS: Search-Tab `onDisappear` — `cancelPendingSearches` + Text/Ergebnisse leeren. */
    fun cancelAndClear() {
        searchJob?.cancel()
        searchJob = null
        _query.value = ""
        _results.value = SearchResults()
        _isSearching.value = false
    }

    private fun isCurrent(q: String): Boolean = SearchLogic.normalizedQuery(_query.value) == q

    private suspend fun performSearch(q: String) {
        if (q.length < SearchLogic.minQueryLength) {
            _results.value = SearchResults()
            return
        }
        applyLocalResults(q)
        if (!isCurrent(q)) return
        val c = session.client
        if (!session.mayUseServerNetwork || !session.isNetworkReachable.value || c == null) return

        val bookLibraryIds = session.activeBookLibraries.map { it.id }
            .ifEmpty { listOfNotNull(session.booksCatalogLibrary?.id) }
        val podcastLibraryId = if (session.showPodcastsTab.value) session.podcastCatalogLibrary?.id else null
        _isSearching.value = true
        try {
            val (bookResponses, podcastResponses) = coroutineScope {
                val books = bookLibraryIds.map { id -> async { runCatching { c.search(id, q) } } }
                val pods = listOfNotNull(podcastLibraryId).map { id -> async { runCatching { c.search(id, q) } } }
                books.awaitAll() to pods.awaitAll()
            }
            if (!isCurrent(q)) return
            val bookOk = bookResponses.mapNotNull { it.getOrNull() }
            val podOk = podcastResponses.mapNotNull { it.getOrNull() }
            val local = _results.value
            val bookSide = if (bookOk.isNotEmpty()) SearchLogic.mergeBookResponses(bookOk) else local
            val (shows, episodes) = if (podOk.isNotEmpty()) {
                SearchLogic.mergePodcastResponses(podOk, local.podcastEpisodes)
            } else {
                local.podcastShows to local.podcastEpisodes
            }
            _results.value = bookSide.copy(podcastShows = shows, podcastEpisodes = episodes)
            val firstError = (bookResponses + podcastResponses).firstNotNullOfOrNull { it.exceptionOrNull() }
            if (firstError != null && !_results.value.hasAnyResults) session.publishErrorUnlessBenignCancellation(firstError)
        } catch (e: CancellationException) {
            throw e
        } finally {
            if (isCurrent(q)) _isSearching.value = false
        }
    }

    /** iOS: `applyLocalSearchResults` + `applyLocalPodcastLibrarySearchResults`. */
    private suspend fun applyLocalResults(q: String) {
        val store = session.currentLocalLibraryStore()
        val books = ArrayList<AbsBook>(model.home.startBooks.value)
        val episodes = ArrayList<AbsPodcastEpisodeListItem>(model.home.startShelves.value.flatMap { it.podcastEpisodes })
        if (store != null) {
            val libIds = session.activeBookLibraries.map { it.id }.ifEmpty { listOfNotNull(session.booksCatalogLibrary?.id) }
            for (id in libIds) books += runCatching { store.fetchAllBooks(id, "title", descending = false) }.getOrNull().orEmpty()
            session.podcastCatalogLibrary?.id?.let { id ->
                episodes += runCatching { store.fetchPodcastEpisodes(id) }.getOrNull()?.items.orEmpty()
            }
        }
        if (!isCurrent(q)) return
        _results.value = SearchLogic.localResults(q, books, episodes = episodes)
    }

    // MARK: - SessionParticipant

    override fun onSessionCleared(clearCredentials: Boolean) = cancelAndClear()
}
