package de.letzgo.abstand.model

import android.util.Log
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsLibraryAuthorListItem
import de.letzgo.abstand.data.AbsLibraryCollectionListItem
import de.letzgo.abstand.data.AbsLibraryGenreStat
import de.letzgo.abstand.data.AbsLibraryNarratorListItem
import de.letzgo.abstand.data.AbsLibrarySeriesListItem
import de.letzgo.abstand.data.AbsLibraryTagStat
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.AbsListeningSessionsPayload
import de.letzgo.abstand.data.AbsProgressPatch
import de.letzgo.abstand.data.BooksBrowseGenreListItem
import de.letzgo.abstand.data.BooksBrowseTagListItem
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.data.trimmedOrEmpty
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.logic.BookDetailLogic
import de.letzgo.abstand.logic.BooksBrowseAuthorsSortField
import de.letzgo.abstand.logic.BooksBrowseCollectionsSortField
import de.letzgo.abstand.logic.BooksBrowseFacetSortField
import de.letzgo.abstand.logic.BooksBrowseNarratorsSortField
import de.letzgo.abstand.logic.BooksBrowseSection
import de.letzgo.abstand.logic.BooksBrowseSeriesSortField
import de.letzgo.abstand.logic.BooksLibraryToolbarSnapshot
import de.letzgo.abstand.logic.CatalogLogic
import de.letzgo.abstand.logic.CatalogSortField
import de.letzgo.abstand.logic.LibraryCatalogQuickFilter
import de.letzgo.abstand.logic.PlayerTranscriptCacheStore
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.store.EbookLocalStore
import de.letzgo.abstand.store.LocalLibraryStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable

/** iOS: `LibraryBookCardStyle` (AppAppearance.swift) — gleiche Raw-Values unter `Keys.libraryBookCardStyle`. */
enum class LibraryBookCardStyle(val rawValue: String, val label: String) {
    compact("compact", "Compact row"),
    heroCover("heroCover", "Cover card");

    /** Mehrspaltiges Cover-Raster statt einspaltiger Liste. */
    val usesMultiColumnGrid: Boolean get() = this == heroCover

    /** Spalten auf dem Phone; Tablets legen zwei drauf (`LibraryHeroMultiColumnRows`). */
    val phoneGridColumns: Int get() = if (this == heroCover) 2 else 1

    fun persist() = Prefs.setString(Keys.libraryBookCardStyle, rawValue)

    companion object {
        /** iOS: `load` — entfernter Stil „coverOnly" → „Cover card". */
        fun load(): LibraryBookCardStyle {
            val raw = Prefs.string(Keys.libraryBookCardStyle) ?: return compact
            if (raw == "coverOnly") return heroCover
            return entries.firstOrNull { it.rawValue == raw } ?: compact
        }
    }
}

/** Sortierzustand des Bücher-Tabs (iOS: die `catalogSort*`/`browse*Sort*`-`@Published` mit `didSet`-Persistenz). */
data class CatalogSortState(
    val catalogField: CatalogSortField,
    val catalogDescending: Boolean,
    val authorsField: BooksBrowseAuthorsSortField,
    val authorsDescending: Boolean,
    val narratorsField: BooksBrowseNarratorsSortField,
    val narratorsDescending: Boolean,
    val seriesField: BooksBrowseSeriesSortField,
    val seriesDescending: Boolean,
    val collectionsField: BooksBrowseCollectionsSortField,
    val collectionsDescending: Boolean,
    val genresField: BooksBrowseFacetSortField,
    val genresDescending: Boolean,
    val tagsField: BooksBrowseFacetSortField,
    val tagsDescending: Boolean,
) {
    companion object {
        /** iOS: `loadCatalogSortState` + `loadBrowse*SortState`. */
        fun load(): CatalogSortState {
            val (field, desc) = CatalogLogic.resolveCatalogSortState(
                legacy = Prefs.string(Keys.legacyCatalogItemsSort),
                storedField = Prefs.string(Keys.catalogSortField),
                storedDescending = Prefs.bool(Keys.catalogSortDescending),
            ) { f, d ->
                Prefs.remove(Keys.legacyCatalogItemsSort)
                Prefs.setString(Keys.catalogSortField, f.rawValue)
                Prefs.setBool(Keys.catalogSortDescending, d)
            }
            if (Prefs.has(Keys.legacyCatalogItemsSort)) Prefs.remove(Keys.legacyCatalogItemsSort)
            return CatalogSortState(
                catalogField = field,
                catalogDescending = desc,
                authorsField = BooksBrowseAuthorsSortField.fromRaw(Prefs.string(Keys.browseAuthorsSortField)) ?: BooksBrowseAuthorsSortField.NAME,
                authorsDescending = Prefs.bool(Keys.browseAuthorsSortDescending),
                narratorsField = BooksBrowseNarratorsSortField.fromRaw(Prefs.string(Keys.browseNarratorsSortField)) ?: BooksBrowseNarratorsSortField.NAME,
                narratorsDescending = Prefs.bool(Keys.browseNarratorsSortDescending),
                seriesField = BooksBrowseSeriesSortField.fromRaw(Prefs.string(Keys.browseSeriesSortField)) ?: BooksBrowseSeriesSortField.NAME,
                seriesDescending = Prefs.bool(Keys.browseSeriesSortDescending),
                collectionsField = BooksBrowseCollectionsSortField.fromRaw(Prefs.string(Keys.browseCollectionsSortField)) ?: BooksBrowseCollectionsSortField.NAME,
                collectionsDescending = Prefs.bool(Keys.browseCollectionsSortDescending),
                genresField = BooksBrowseFacetSortField.fromRaw(Prefs.string(Keys.browseGenresSortField)) ?: BooksBrowseFacetSortField.NAME,
                genresDescending = Prefs.bool(Keys.browseGenresSortDescending),
                tagsField = BooksBrowseFacetSortField.fromRaw(Prefs.string(Keys.browseTagsSortField)) ?: BooksBrowseFacetSortField.NAME,
                tagsDescending = Prefs.bool(Keys.browseTagsSortDescending),
            )
        }
    }
}

/** Filterzustand (iOS: `activeLibraryFilter`, `activeLibraryFilterSummary`, `libraryCatalogQuickFilter`, `ebookCatalogQuickFilter`). */
data class CatalogFilterState(
    val activeLibraryFilter: String? = null,
    val activeLibraryFilterSummary: String? = null,
    val libraryCatalogQuickFilter: LibraryCatalogQuickFilter? = null,
    val ebookCatalogQuickFilter: LibraryCatalogQuickFilter? = null,
) {
    /** iOS: `isLibraryCatalogFiltered`. */
    val isLibraryCatalogFiltered: Boolean
        get() = libraryCatalogQuickFilter != null || !activeLibraryFilter?.swiftTrim().isNullOrEmpty()

    /** iOS: `BooksLibraryToolbarState.isAllFilterActive`. */
    val isAllFilterActive: Boolean
        get() = libraryCatalogQuickFilter == null && activeLibraryFilter?.swiftTrim().isNullOrEmpty()
}

/** Browse-Listen des Bücher-Tabs (iOS: `browseAuthors`, `browseSeries`, … samt Lade-Flags). */
data class BrowseListsState(
    val authors: List<AbsLibraryAuthorListItem> = emptyList(),
    val authorsTotal: Int = 0,
    val authorsLoading: Boolean = false,
    val narrators: List<AbsLibraryNarratorListItem> = emptyList(),
    val narratorsLoading: Boolean = false,
    val narratorCoverItemIdByName: Map<String, String> = emptyMap(),
    val series: List<AbsLibrarySeriesListItem> = emptyList(),
    val seriesTotal: Int = 0,
    val seriesLoading: Boolean = false,
    val collections: List<AbsLibraryCollectionListItem> = emptyList(),
    val collectionsTotal: Int = 0,
    val collectionsLoading: Boolean = false,
    val collectionBooksById: Map<String, List<AbsBook>> = emptyMap(),
    val genres: List<BooksBrowseGenreListItem> = emptyList(),
    val genresLoading: Boolean = false,
    val tags: List<BooksBrowseTagListItem> = emptyList(),
    val tagsLoading: Boolean = false,
    val ebooks: List<AbsBook> = emptyList(),
    val ebooksSupplementary: List<AbsBook> = emptyList(),
    val ebooksLoading: Boolean = false,
)

/**
 * iOS: Katalog-/Browse-Teil von `AppModel.swift` + `AppModelCatalogPodcasts.reloadLibrary` — Bücher-
 * Katalog mit Paging (Server-Reihenfolge, cache-first aus [LocalLibraryStore]), Sortierung/Filter,
 * Browse-Listen (Autoren, Sprecher, Serien, Sammlungen, Genres, Tags, eBooks), Download-Zustand der
 * Karten und Buch-Aktionen (Detail laden, fertig/zurücksetzen, Lesezeichen, löschen).
 *
 * Fortschritt/Lesezeichen selbst liegen in [ProgressStore] (`model.progress`).
 */
class CatalogStore(private val model: AppModel) : SessionParticipant {
    private val session get() = model.session
    private val progress get() = model.progress
    private val scope get() = model.scope

    // MARK: - Zustand

    private val _books = MutableStateFlow<List<AbsBook>>(emptyList())
    /** iOS: `books` — Server-Seiten des Katalogs (Reihenfolge = Server). */
    val books: StateFlow<List<AbsBook>> = _books.asStateFlow()

    private val _libraryTotal = MutableStateFlow(0)
    val libraryTotal: StateFlow<Int> = _libraryTotal.asStateFlow()

    private val _isLoadingLibrary = MutableStateFlow(false)
    val isLoadingLibrary: StateFlow<Boolean> = _isLoadingLibrary.asStateFlow()

    private val _sort = MutableStateFlow(CatalogSortState.load())
    val sort: StateFlow<CatalogSortState> = _sort.asStateFlow()

    private val _filter = MutableStateFlow(CatalogFilterState())
    val filter: StateFlow<CatalogFilterState> = _filter.asStateFlow()

    private val _booksBrowseSection = MutableStateFlow(BooksBrowseSection.BOOKS)
    /** iOS: `booksBrowseSection` — aktive Sektion der Browse-Leiste. */
    val booksBrowseSection: StateFlow<BooksBrowseSection> = _booksBrowseSection.asStateFlow()

    private val _scrollToTopEpoch = MutableStateFlow(0)
    /** iOS: `libraryCatalogScrollToTopEpoch` — Erhöhen springt die Liste an den Anfang. */
    val libraryCatalogScrollToTopEpoch: StateFlow<Int> = _scrollToTopEpoch.asStateFlow()

    private val _browse = MutableStateFlow(BrowseListsState())
    val browse: StateFlow<BrowseListsState> = _browse.asStateFlow()

    private val _cardStyle = MutableStateFlow(LibraryBookCardStyle.load())
    /** iOS: `libraryBookCardStyle`. */
    val libraryBookCardStyle: StateFlow<LibraryBookCardStyle> = _cardStyle.asStateFlow()

    private val _downloadedItemIds = MutableStateFlow<Set<String>>(emptySet())
    /** iOS: `downloadedItemIds` — Speicher-IDs fertiger Downloads (Ordner mit `download.json`). */
    val downloadedItemIds: StateFlow<Set<String>> = _downloadedItemIds.asStateFlow()

    private val _downloadedBooks = MutableStateFlow<List<AbsBook>>(emptyList())
    /** iOS: `downloadedAudiobooksWithFullMetadata()` — Downloads (nur Hörbücher) mit Katalog-Metadaten. */
    val downloadedBooks: StateFlow<List<AbsBook>> = _downloadedBooks.asStateFlow()

    /** iOS: `booksForDisplay()` für den Bücher-Tab (offline/Downloads-Filter → Downloads). */
    val displayBooks: StateFlow<List<AbsBook>> = combine(
        _books, _downloadedBooks, _filter,
        combine(session.offlineHomeMode, session.offlineHomeModeAuto, session.isNetworkReachable) { o, a, r -> (o || a) to r },
    ) { books, downloaded, filter, (offlineUI, reachable) ->
        when {
            offlineUI || filter.libraryCatalogQuickFilter == LibraryCatalogQuickFilter.DOWNLOADED -> {
                val libId = session.selectedBooksLibrary.value?.id
                downloaded.filter { libId == null || it.libraryId == null || it.libraryId == libId }
            }
            !reachable && books.isNotEmpty() -> books
            !reachable -> downloaded
            else -> books
        }
    }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    /** iOS: `BooksLibraryToolbarSnapshot` — Wertzustand für die Toolbar-Menüs. */
    val toolbarSnapshot: StateFlow<BooksLibraryToolbarSnapshot> = combine(_booksBrowseSection, _sort, _filter) { section, s, f ->
        BooksLibraryToolbarSnapshot(
            booksBrowseSection = section,
            catalogSortField = s.catalogField,
            catalogSortDescending = s.catalogDescending,
            libraryCatalogQuickFilter = f.libraryCatalogQuickFilter,
            ebookCatalogQuickFilter = f.ebookCatalogQuickFilter,
            isLibraryCatalogFiltered = f.isLibraryCatalogFiltered,
            isAllFilterActive = f.isAllFilterActive,
            browseAuthorsSortField = s.authorsField,
            browseAuthorsSortDescending = s.authorsDescending,
            browseNarratorsSortField = s.narratorsField,
            browseNarratorsSortDescending = s.narratorsDescending,
            browseSeriesSortField = s.seriesField,
            browseSeriesSortDescending = s.seriesDescending,
            browseCollectionsSortField = s.collectionsField,
            browseCollectionsSortDescending = s.collectionsDescending,
            browseGenresSortField = s.genresField,
            browseGenresSortDescending = s.genresDescending,
            browseTagsSortField = s.tagsField,
            browseTagsSortDescending = s.tagsDescending,
        )
    }.stateIn(scope, SharingStarted.Eagerly, snapshotPlaceholder())

    // Paging-Interna
    private var libraryPage = 0
    private var libraryReloadSerial = 0
    private var lastBooksCatalogServerSyncAt: Long? = null
    private var browseAuthorsNextPage = 0
    private var browseSeriesNextPage = 0
    private var browseEbooksNextPage = 0
    private var browseEbooksTotal = 0
    private var browseEbooksSessionFetchDone = false
    private var narratorsFetched: List<AbsLibraryNarratorListItem> = emptyList()
    private var collectionsFetched: List<AbsLibraryCollectionListItem> = emptyList()
    private var genresFetched: List<BooksBrowseGenreListItem> = emptyList()
    private var tagsFetched: List<BooksBrowseTagListItem> = emptyList()
    private var sortReloadJob: Job? = null
    private var downloadsWatchStarted = false

    private fun snapshotPlaceholder(): BooksLibraryToolbarSnapshot {
        val s = _sort.value
        return BooksLibraryToolbarSnapshot(
            BooksBrowseSection.BOOKS, s.catalogField, s.catalogDescending, null, null, false, true,
            s.authorsField, s.authorsDescending, s.narratorsField, s.narratorsDescending, s.seriesField,
            s.seriesDescending, s.collectionsField, s.collectionsDescending, s.genresField, s.genresDescending,
            s.tagsField, s.tagsDescending,
        )
    }

    private val libraryCatalog: AbsLibrary? get() = session.booksCatalogLibrary
    private val reachable: Boolean get() = session.isNetworkReachable.value
    private val catalogAscending: Boolean get() = _sort.value.let { CatalogLogic.catalogAscending(it.catalogField, it.catalogDescending) }
    private val catalogSortKey: String get() = _sort.value.catalogField.apiSortParameter

    // MARK: - Katalog laden

    /**
     * iOS: `reloadLibrary(reset:preserveOtherCachedPages:)`. Reset: zuerst exakt passende
     * lokale Seiten (offline auch den Superset), dann Server-Seite 0 verbindlich; sonst Folgeseite.
     */
    suspend fun reloadLibrary(reset: Boolean, preserveOtherCachedPages: Boolean = false) {
        val lib = libraryCatalog ?: return
        val serial = ++libraryReloadSerial
        val expectedLibraryId = lib.id
        val expectedSortKey = catalogSortKey
        val expectedAscending = catalogAscending
        val expectedFilter = _filter.value.activeLibraryFilter

        var warmed = false
        if (reset) warmed = loadLibraryFromLocalStore(allowSupersetFallback = !reachable)
        val c = session.client
        if (!session.mayUseServerNetwork || c == null || !reachable) {
            if (reset && !warmed) loadLibraryFromLocalStore(allowSupersetFallback = true)
            if (!reachable) refreshDownloadedItemIds()
            return
        }
        _isLoadingLibrary.value = true
        try {
            if (reset && !preserveOtherCachedPages && !warmed) {
                _books.value = emptyList()
                _libraryTotal.value = 0
                libraryPage = 0
            }
            if (reset) libraryPage = 0
            val pageIndex = libraryPage
            val (page, _) = c.libraryItems(
                libraryId = expectedLibraryId,
                page = pageIndex,
                limit = CatalogLogic.LIBRARY_CATALOG_PAGE_LIMIT,
                sort = expectedSortKey,
                ascending = expectedAscending,
                minified = true,
                filter = expectedFilter,
            )
            fun stillCurrent() = libraryReloadSerial == serial && !session.offlineHomeUIActive &&
                libraryCatalog?.id == expectedLibraryId && catalogSortKey == expectedSortKey &&
                catalogAscending == expectedAscending && _filter.value.activeLibraryFilter == expectedFilter
            if (!stillCurrent()) return
            val pageBooks = page.results.filter { it.isUsableLibraryCatalogRow }
            session.currentLocalLibraryStore()?.let { store ->
                runCatching {
                    withContext(Dispatchers.IO) {
                        when {
                            reset && preserveOtherCachedPages -> store.refreshCatalogFirstPagePreservingRest(
                                expectedLibraryId, expectedSortKey, expectedAscending, expectedFilter, page.total, pageBooks,
                            )
                            reset -> store.replaceCatalogFirstPage(
                                expectedLibraryId, expectedSortKey, expectedAscending, expectedFilter, page.total, pageBooks,
                            )
                            else -> store.appendCatalogPage(expectedLibraryId, page.total, pageBooks)
                        }
                    }
                }.onFailure { if (it is CancellationException) throw it; Log.w(TAG, "LocalStore catalog write failed: ${it.message}") }
            }
            if (libraryReloadSerial != serial || session.offlineHomeUIActive) return
            when {
                reset && preserveOtherCachedPages -> {
                    val (merged, total) = CatalogLogic.mergeFirstPagePreservingRest(_books.value, pageBooks, page.total)
                    if (merged != null) _books.value = merged
                    _libraryTotal.value = total
                }
                reset -> {
                    if (!CatalogLogic.sameIdsAndUpdatedAt(pageBooks, _books.value)) _books.value = pageBooks
                    _libraryTotal.value = page.total
                }
                else -> {
                    val seen = _books.value.mapTo(HashSet()) { it.id }
                    _books.value = _books.value + pageBooks.filter { it.id !in seen }
                    _libraryTotal.value = page.total
                }
            }
            libraryPage = page.page + 1
            if (reset) lastBooksCatalogServerSyncAt = System.currentTimeMillis()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            if (libraryReloadSerial == serial) _isLoadingLibrary.value = false
        }
    }

    /**
     * iOS: `loadLibraryFromLocalStore(allowSupersetFallback:)` — gecachte Seiten in Server-Reihenfolge,
     * wenn Sort/Filter exakt passen; sonst (nur offline) der lokale Superset client-seitig sortiert.
     */
    private suspend fun loadLibraryFromLocalStore(allowSupersetFallback: Boolean): Boolean {
        val store = session.currentLocalLibraryStore() ?: return false
        val libId = libraryCatalog?.id ?: return false
        val sortKey = catalogSortKey
        val ascending = catalogAscending
        val filterKey = _filter.value.activeLibraryFilter
        val merged = withContext(Dispatchers.IO) {
            runCatching { store.fetchCatalog(libId, sortKey, ascending, filterKey, CatalogLogic.LIBRARY_CATALOG_PAGE_LIMIT) }.getOrNull()
        }
        if (merged != null && merged.items.isNotEmpty()) {
            _books.value = merged.items
            _libraryTotal.value = merged.total
            libraryPage = merged.nextPage
            return true
        }
        val s = _sort.value
        if (!allowSupersetFallback || filterKey != null) return false
        if (!(de.letzgo.abstand.store.LocalLibraryQueries.supportsLocalBookSort(s.catalogField.rawValue) || !reachable)) return false
        val local = withContext(Dispatchers.IO) {
            runCatching { store.fetchAllBooks(libId, s.catalogField.rawValue, s.catalogDescending) }.getOrDefault(emptyList())
        }
        if (local.isEmpty()) return false
        _books.value = local
        _libraryTotal.value = local.size
        libraryPage = maxOf(1, CatalogLogic.run { (local.size + LIBRARY_CATALOG_PAGE_LIMIT - 1) / LIBRARY_CATALOG_PAGE_LIMIT })
        return true
    }

    /** iOS: `restoreBooksCatalogPagesFromLocalStoreAsync` — nur exakt passende Seiten (Kaltstart). */
    private suspend fun restoreBooksCatalogPagesFromLocalStore(store: LocalLibraryStore, libraryId: String?) {
        val libId = libraryId?.swiftTrim().orEmpty()
        if (libId.isEmpty() || libId == Keys.librarySelectionNone) return
        val merged = withContext(Dispatchers.IO) {
            runCatching {
                store.fetchCatalog(libId, catalogSortKey, catalogAscending, _filter.value.activeLibraryFilter, CatalogLogic.LIBRARY_CATALOG_PAGE_LIMIT)
            }.getOrNull()
        } ?: return
        if (_books.value.isNotEmpty()) return
        _books.value = merged.items
        _libraryTotal.value = merged.total
        libraryPage = merged.nextPage
    }

    /** iOS: `loadMoreIfNeeded(currentItemId:)` — nächste Server-Seite nahe dem Listenende. */
    suspend fun loadMoreIfNeeded(currentItemId: String?) {
        if (_booksBrowseSection.value != BooksBrowseSection.BOOKS) return
        if (_filter.value.libraryCatalogQuickFilter == LibraryCatalogQuickFilter.DOWNLOADED) return
        if (session.offlineHomeUIActive || _isLoadingLibrary.value) return
        val list = _books.value
        if (!CatalogLogic.shouldPrefetchNextPage(currentItemId, list) { it.id }) return
        if (list.size >= _libraryTotal.value) return
        reloadLibrary(reset = false)
    }

    /** iOS: `refreshBooksCatalog` (Pull-to-Refresh). */
    suspend fun refreshBooksCatalog() {
        refreshDownloadedItemIds()
        session.refreshProgressFromServer()
        reloadLibrary(reset = true)
        refreshBooksBrowseSectionLists()
    }

    /** iOS: `refreshCatalogsIfStaleOnForeground` (Bücher-Teil). */
    fun refreshCatalogIfStaleOnForeground() {
        if (!session.isLoggedIn.value || session.offlineHomeUIActive || session.isAppBootstrapInProgress.value) return
        if (!reachable || session.client == null || session.selectedBooksLibrary.value == null) return
        val last = lastBooksCatalogServerSyncAt
        if (last != null && System.currentTimeMillis() - last <= CatalogLogic.CATALOG_STALE_REFRESH_INTERVAL_MS) return
        scope.launch { reloadLibrary(reset = true, preserveOtherCachedPages = true) }
    }

    // MARK: - Filter

    /** iOS: `requestLibraryCatalogScrollToTop`. */
    fun requestLibraryCatalogScrollToTop() {
        _scrollToTopEpoch.value += 1
    }

    /** iOS: `applyLibraryCatalogQuickFilter(_:)`. */
    fun applyLibraryCatalogQuickFilter(filter: LibraryCatalogQuickFilter?) {
        if (filter == null) {
            clearCatalogFilter()
            return
        }
        requestLibraryCatalogScrollToTop()
        _booksBrowseSection.value = BooksBrowseSection.BOOKS
        if (filter.isLocalDownloadedOnly) {
            _filter.update { it.copy(activeLibraryFilter = null, libraryCatalogQuickFilter = filter, activeLibraryFilterSummary = summary(filter.summaryPrefix, filter.summaryDetail)) }
            refreshDownloadedItemIds()
            return
        }
        val key = filter.serverFilterKey ?: run { clearCatalogFilter(); return }
        _filter.update { it.copy(activeLibraryFilter = key, libraryCatalogQuickFilter = filter, activeLibraryFilterSummary = summary(filter.summaryPrefix, filter.summaryDetail)) }
        scope.launch { reloadLibrary(reset = true) }
    }

    /** iOS: `applyCatalogFilter(_:summaryPrefix:summaryDetail:)` (z. B. aus Suche). */
    fun applyCatalogFilter(filter: String?, summaryPrefix: String, summaryDetail: String?) {
        val trimmed = filter?.swiftTrim().orEmpty()
        if (trimmed.isEmpty() || trimmed == "all") {
            clearCatalogFilter()
            return
        }
        requestLibraryCatalogScrollToTop()
        _filter.update { it.copy(libraryCatalogQuickFilter = null, activeLibraryFilter = trimmed, activeLibraryFilterSummary = summary(summaryPrefix, summaryDetail)) }
        _booksBrowseSection.value = BooksBrowseSection.BOOKS
        scope.launch { reloadLibrary(reset = true) }
    }

    fun applyAuthorFilter(authorId: String, displayName: String? = null) =
        applyCatalogFilter(CatalogLogic.catalogFilterKey("authors", authorId), "Author", displayName?.swiftTrim()?.ifEmpty { null })

    fun applySeriesFilter(seriesId: String, displayName: String? = null) =
        applyCatalogFilter(CatalogLogic.catalogFilterKey("series", seriesId), "Series", displayName?.swiftTrim()?.ifEmpty { null })

    fun applyNarratorFilter(narratorName: String) {
        val name = narratorName.swiftTrim().ifEmpty { return }
        applyCatalogFilter(CatalogLogic.catalogFilterKey("narrators", name), "Narrator", name)
    }

    fun applyTagFilter(tagName: String) {
        val name = tagName.swiftTrim().ifEmpty { return }
        applyCatalogFilter(CatalogLogic.catalogFilterKey("tags", name), "Tag", name)
    }

    fun applyGenreFilter(genreName: String) {
        val name = genreName.swiftTrim().ifEmpty { return }
        applyCatalogFilter(CatalogLogic.catalogFilterKey("genres", name), "Genre", name)
    }

    /** iOS: `clearCatalogFilter`. */
    fun clearCatalogFilter() {
        val f = _filter.value
        if (f.activeLibraryFilter == null && f.libraryCatalogQuickFilter == null) return
        requestLibraryCatalogScrollToTop()
        _filter.update { it.copy(activeLibraryFilter = null, activeLibraryFilterSummary = null, libraryCatalogQuickFilter = null) }
        _booksBrowseSection.value = BooksBrowseSection.BOOKS
        scope.launch { reloadLibrary(reset = true) }
    }

    private fun summary(prefix: String, detail: String?): String {
        val d = detail?.swiftTrim().orEmpty()
        return if (d.isEmpty()) prefix else "$prefix: $d"
    }

    /** iOS: `applyEbookCatalogQuickFilter`. */
    fun applyEbookCatalogQuickFilter(filter: LibraryCatalogQuickFilter?) {
        if (_filter.value.ebookCatalogQuickFilter == filter) return
        requestLibraryCatalogScrollToTop()
        _filter.update { it.copy(ebookCatalogQuickFilter = filter) }
    }

    /** iOS: `browseEbooksFiltered` — Fortschritt/Download beziehen sich aufs eBook. */
    fun browseEbooksFiltered(books: List<AbsBook>, filter: LibraryCatalogQuickFilter? = _filter.value.ebookCatalogQuickFilter): List<AbsBook> {
        filter ?: return books
        val account = session.cacheAccountDir()
        return books.filter { book ->
            val f = progress.ebookDisplayProgressFraction(book.id) ?: 0.0
            when (filter) {
                LibraryCatalogQuickFilter.IN_PROGRESS -> f > 0.005 && f < 0.995
                LibraryCatalogQuickFilter.FINISHED -> f >= 0.995
                LibraryCatalogQuickFilter.NOT_STARTED -> f <= 0.005
                LibraryCatalogQuickFilter.DOWNLOADED -> EbookLocalStore.cachedEbookIfPresent(account, book.id) != null
                LibraryCatalogQuickFilter.EBOOKS, LibraryCatalogQuickFilter.EBOOKS_SUPPLEMENTARY -> true
            }
        }
    }

    // MARK: - Sektionen + Sortierung

    /** iOS: `selectBooksBrowseSection` — „Search" öffnet die Suche (Android: gepushte Seite). */
    fun selectBooksBrowseSection(section: BooksBrowseSection) {
        if (section == BooksBrowseSection.SEARCH) {
            session.openSearch()
            return
        }
        _booksBrowseSection.value = section
        scope.launch { loadBooksBrowseSectionContentIfNeeded() }
    }

    /** Beim Erscheinen des Tabs: aktive Sektion nachladen (iOS: `.task` der Sektion). */
    fun ensureActiveSectionLoaded() {
        scope.launch {
            if (_booksBrowseSection.value == BooksBrowseSection.BOOKS) {
                if (_books.value.isEmpty() && !_isLoadingLibrary.value) reloadLibrary(reset = true)
            } else {
                loadBooksBrowseSectionContentIfNeeded()
            }
        }
    }

    private enum class SortReloadKind { AllCatalogs, BrowseAuthors, BrowseSeries }

    /** iOS: `scheduleBooksToolbarSortReload` — 350 ms entkoppeln, dann nach oben + Reload. */
    private fun scheduleSortReload(kind: SortReloadKind) {
        sortReloadJob?.cancel()
        sortReloadJob = scope.launch {
            delay(350)
            requestLibraryCatalogScrollToTop()
            when (kind) {
                SortReloadKind.AllCatalogs -> {
                    prepareBrowseEbooksForSortChange()
                    coroutineScope {
                        launch { reloadLibrary(reset = true) }
                        launch { loadBrowseEbooks(force = true) }
                    }
                }
                SortReloadKind.BrowseAuthors -> loadBrowseAuthors(force = true)
                SortReloadKind.BrowseSeries -> loadBrowseSeries(force = true)
            }
        }
    }

    fun applyCatalogSortField(field: CatalogSortField) {
        if (_sort.value.catalogField == field) return
        _sort.update { it.copy(catalogField = field) }
        Prefs.setString(Keys.catalogSortField, field.rawValue)
        scheduleSortReload(SortReloadKind.AllCatalogs)
    }

    fun applyCatalogSortDescending(descending: Boolean) {
        if (_sort.value.catalogDescending == descending) return
        _sort.update { it.copy(catalogDescending = descending) }
        Prefs.setBool(Keys.catalogSortDescending, descending)
        scheduleSortReload(SortReloadKind.AllCatalogs)
    }

    fun applyBrowseAuthorsSortField(field: BooksBrowseAuthorsSortField) {
        if (_sort.value.authorsField == field) return
        _sort.update { it.copy(authorsField = field) }
        Prefs.setString(Keys.browseAuthorsSortField, field.rawValue)
        scheduleSortReload(SortReloadKind.BrowseAuthors)
    }

    fun applyBrowseAuthorsSortDescending(descending: Boolean) {
        if (_sort.value.authorsDescending == descending) return
        _sort.update { it.copy(authorsDescending = descending) }
        Prefs.setBool(Keys.browseAuthorsSortDescending, descending)
        scheduleSortReload(SortReloadKind.BrowseAuthors)
    }

    fun applyBrowseSeriesSortField(field: BooksBrowseSeriesSortField) {
        if (_sort.value.seriesField == field) return
        _sort.update { it.copy(seriesField = field) }
        Prefs.setString(Keys.browseSeriesSortField, field.rawValue)
        scheduleSortReload(SortReloadKind.BrowseSeries)
    }

    fun applyBrowseSeriesSortDescending(descending: Boolean) {
        if (_sort.value.seriesDescending == descending) return
        _sort.update { it.copy(seriesDescending = descending) }
        Prefs.setBool(Keys.browseSeriesSortDescending, descending)
        scheduleSortReload(SortReloadKind.BrowseSeries)
    }

    fun applyBrowseNarratorsSortField(field: BooksBrowseNarratorsSortField) {
        if (_sort.value.narratorsField == field) return
        _sort.update { it.copy(narratorsField = field) }
        Prefs.setString(Keys.browseNarratorsSortField, field.rawValue)
        resortBrowseNarratorsDisplay()
    }

    fun applyBrowseNarratorsSortDescending(descending: Boolean) {
        if (_sort.value.narratorsDescending == descending) return
        _sort.update { it.copy(narratorsDescending = descending) }
        Prefs.setBool(Keys.browseNarratorsSortDescending, descending)
        resortBrowseNarratorsDisplay()
    }

    fun applyBrowseCollectionsSortField(field: BooksBrowseCollectionsSortField) {
        if (_sort.value.collectionsField == field) return
        _sort.update { it.copy(collectionsField = field) }
        Prefs.setString(Keys.browseCollectionsSortField, field.rawValue)
        resortBrowseCollectionsDisplay()
    }

    fun applyBrowseCollectionsSortDescending(descending: Boolean) {
        if (_sort.value.collectionsDescending == descending) return
        _sort.update { it.copy(collectionsDescending = descending) }
        Prefs.setBool(Keys.browseCollectionsSortDescending, descending)
        resortBrowseCollectionsDisplay()
    }

    fun applyBrowseGenresSortField(field: BooksBrowseFacetSortField) {
        if (_sort.value.genresField == field) return
        _sort.update { it.copy(genresField = field) }
        Prefs.setString(Keys.browseGenresSortField, field.rawValue)
        resortBrowseGenresDisplay()
    }

    fun applyBrowseGenresSortDescending(descending: Boolean) {
        if (_sort.value.genresDescending == descending) return
        _sort.update { it.copy(genresDescending = descending) }
        Prefs.setBool(Keys.browseGenresSortDescending, descending)
        resortBrowseGenresDisplay()
    }

    fun applyBrowseTagsSortField(field: BooksBrowseFacetSortField) {
        if (_sort.value.tagsField == field) return
        _sort.update { it.copy(tagsField = field) }
        Prefs.setString(Keys.browseTagsSortField, field.rawValue)
        resortBrowseTagsDisplay()
    }

    fun applyBrowseTagsSortDescending(descending: Boolean) {
        if (_sort.value.tagsDescending == descending) return
        _sort.update { it.copy(tagsDescending = descending) }
        Prefs.setBool(Keys.browseTagsSortDescending, descending)
        resortBrowseTagsDisplay()
    }

    /** iOS: `libraryBookCardStyle = …` (Settings „Appearance"). */
    fun setLibraryBookCardStyle(style: LibraryBookCardStyle) {
        if (_cardStyle.value == style) return
        _cardStyle.value = style
        style.persist()
    }

    private fun resortBrowseNarratorsDisplay() = _sort.value.let { s ->
        _browse.update { it.copy(narrators = CatalogLogic.sortedNarrators(narratorsFetched, s.narratorsField, s.narratorsDescending)) }
    }

    private fun resortBrowseCollectionsDisplay() = _sort.value.let { s ->
        _browse.update { it.copy(collections = CatalogLogic.sortedCollections(collectionsFetched, s.collectionsField, s.collectionsDescending)) }
    }

    private fun resortBrowseGenresDisplay() = _sort.value.let { s ->
        _browse.update { it.copy(genres = CatalogLogic.sortedGenres(genresFetched, s.genresField, s.genresDescending)) }
    }

    private fun resortBrowseTagsDisplay() = _sort.value.let { s ->
        _browse.update { it.copy(tags = CatalogLogic.sortedTags(tagsFetched, s.tagsField, s.tagsDescending)) }
    }

    private suspend fun loadBooksBrowseSectionContentIfNeeded() = when (_booksBrowseSection.value) {
        BooksBrowseSection.BOOKS, BooksBrowseSection.SEARCH -> Unit
        BooksBrowseSection.EBOOKS, BooksBrowseSection.EBOOKS_SUPPLEMENTARY -> loadBrowseEbooks(force = false)
        BooksBrowseSection.AUTHOR -> loadBrowseAuthors(force = false)
        BooksBrowseSection.NARRATORS -> loadBrowseNarrators(force = false)
        BooksBrowseSection.SERIES -> loadBrowseSeries(force = false)
        BooksBrowseSection.COLLECTIONS -> loadBrowseCollections(force = false)
        BooksBrowseSection.GENRES -> loadBrowseGenres(force = false)
        BooksBrowseSection.TAGS -> loadBrowseTags(force = false)
    }

    private suspend fun refreshBooksBrowseSectionLists() = when (_booksBrowseSection.value) {
        BooksBrowseSection.BOOKS, BooksBrowseSection.SEARCH -> Unit
        BooksBrowseSection.EBOOKS, BooksBrowseSection.EBOOKS_SUPPLEMENTARY -> loadBrowseEbooks(force = true)
        BooksBrowseSection.AUTHOR -> loadBrowseAuthors(force = true)
        BooksBrowseSection.NARRATORS -> loadBrowseNarrators(force = true)
        BooksBrowseSection.SERIES -> loadBrowseSeries(force = true)
        BooksBrowseSection.COLLECTIONS -> loadBrowseCollections(force = true)
        BooksBrowseSection.GENRES -> loadBrowseGenres(force = true)
        BooksBrowseSection.TAGS -> loadBrowseTags(force = true)
    }

    /** iOS: `resetBooksBrowseLists`. */
    private fun resetBooksBrowseLists() {
        _browse.value = BrowseListsState()
        narratorsFetched = emptyList()
        collectionsFetched = emptyList()
        genresFetched = emptyList()
        tagsFetched = emptyList()
        browseAuthorsNextPage = 0
        browseSeriesNextPage = 0
        browseEbooksNextPage = 0
        browseEbooksTotal = 0
        browseEbooksSessionFetchDone = false
        _filter.update { it.copy(ebookCatalogQuickFilter = null) }
    }

    // MARK: - Browse: Autoren

    private suspend fun restoreBrowseAuthorsFromLocalStore(): Boolean {
        val store = session.currentLocalLibraryStore() ?: return false
        val lib = libraryCatalog ?: return false
        val s = _sort.value
        val m = withContext(Dispatchers.IO) {
            runCatching { store.fetchAuthors(lib.id, s.authorsField.apiSortParameter, s.authorsDescending) }.getOrNull()
        } ?: return false
        _browse.update { it.copy(authors = m.items, authorsTotal = m.total) }
        browseAuthorsNextPage = m.nextPage
        return true
    }

    private suspend fun loadBrowseAuthors(force: Boolean) {
        if (session.offlineHomeUIActive) {
            if (!force && _browse.value.authors.isNotEmpty()) return
            val rows = CatalogLogic.offlineAuthors(_downloadedBooks.value)
            _browse.update { it.copy(authors = rows, authorsTotal = rows.size) }
            return
        }
        if (session.client == null || libraryCatalog == null) return
        if (_browse.value.authorsLoading) return
        if (!force && _browse.value.authors.isNotEmpty()) return
        if (_browse.value.authors.isEmpty()) restoreBrowseAuthorsFromLocalStore()
        if (!force && _browse.value.authors.isNotEmpty()) return
        if (!reachable) return
        loadBrowseAuthorsPage(reset = true)
    }

    private suspend fun loadBrowseAuthorsPage(reset: Boolean) {
        val c = session.client ?: return
        val lib = libraryCatalog ?: return
        if (!reachable) {
            restoreBrowseAuthorsFromLocalStore()
            return
        }
        if (_browse.value.authorsLoading) return
        if (reset) {
            browseAuthorsNextPage = 0
            if (_browse.value.authors.isEmpty()) restoreBrowseAuthorsFromLocalStore()
            if (_browse.value.authors.isEmpty()) _browse.update { it.copy(authorsTotal = 0) }
        } else {
            val b = _browse.value
            if (b.authorsTotal <= 0 || b.authors.size >= b.authorsTotal) return
        }
        val page = browseAuthorsNextPage
        val s = _sort.value
        _browse.update { it.copy(authorsLoading = true) }
        try {
            val (items, total, _) = c.libraryAuthorsPage(lib.id, page, 50, s.authorsField.apiSortParameter, s.authorsDescending)
            if (session.offlineHomeUIActive) return
            session.currentLocalLibraryStore()?.let { store ->
                runCatching {
                    withContext(Dispatchers.IO) {
                        if (reset && page == 0) store.replaceAuthorsFirstPage(lib.id, s.authorsField.apiSortParameter, s.authorsDescending, total, items)
                        else store.appendAuthorsPage(lib.id, total, items)
                    }
                }
            }
            _browse.update { it.copy(authorsTotal = total) }
            if (items.isEmpty() && !reset) return
            _browse.update { b -> b.copy(authors = if (reset) items else b.authors + items) }
            browseAuthorsNextPage = page + 1
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _browse.update { it.copy(authorsLoading = false) }
        }
    }

    /** iOS: `loadMoreBrowseAuthorsIfNeeded`. */
    suspend fun loadMoreBrowseAuthorsIfNeeded(currentItemId: String?) {
        if (_booksBrowseSection.value != BooksBrowseSection.AUTHOR) return
        val b = _browse.value
        if (b.authorsTotal <= 0) return
        if (!CatalogLogic.shouldPrefetchNextPage(currentItemId, b.authors) { it.id }) return
        if (b.authors.size >= b.authorsTotal) return
        loadBrowseAuthorsPage(reset = false)
    }

    // MARK: - Browse: Sprecher

    private suspend fun restoreBrowseNarratorsFromLocalStore(): Boolean {
        val store = session.currentLocalLibraryStore() ?: return false
        val lib = libraryCatalog ?: return false
        val rows = withContext(Dispatchers.IO) { runCatching { store.fetchNarrators(lib.id) }.getOrNull() } ?: return false
        narratorsFetched = rows.narrators
        val s = _sort.value
        _browse.update {
            it.copy(
                narrators = CatalogLogic.sortedNarrators(rows.narrators, s.narratorsField, s.narratorsDescending),
                narratorCoverItemIdByName = rows.coverMap,
            )
        }
        return true
    }

    private suspend fun loadBrowseNarrators(force: Boolean) {
        if (session.offlineHomeUIActive) {
            if (!force && _browse.value.narrators.isNotEmpty()) return
            narratorsFetched = CatalogLogic.offlineNarrators(_downloadedBooks.value)
            resortBrowseNarratorsDisplay()
            _browse.update { it.copy(narratorCoverItemIdByName = emptyMap()) }
            return
        }
        val c = session.client ?: return
        val lib = libraryCatalog ?: return
        if (_browse.value.narratorsLoading) return
        if (!force && _browse.value.narrators.isNotEmpty()) return
        if (_browse.value.narrators.isEmpty()) restoreBrowseNarratorsFromLocalStore()
        if (!force && _browse.value.narrators.isNotEmpty()) return
        if (!reachable) return
        _browse.update { it.copy(narratorsLoading = true) }
        try {
            val (items, _) = c.libraryNarrators(lib.id)
            if (session.offlineHomeUIActive) return
            narratorsFetched = items
            resortBrowseNarratorsDisplay()
            _browse.update { it.copy(narratorCoverItemIdByName = emptyMap()) }
            session.currentLocalLibraryStore()?.let { store -> runCatching { withContext(Dispatchers.IO) { store.replaceNarrators(lib.id, items) } } }
            fillBrowseNarratorCoverItemIds()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _browse.update { it.copy(narratorsLoading = false) }
        }
    }

    /** iOS: `fillBrowseNarratorCoverItemIds` — Cover-Buch je Sprecher aus Titel-sortierten Seiten. */
    private suspend fun fillBrowseNarratorCoverItemIds() {
        val c = session.client ?: return
        val lib = libraryCatalog ?: return
        if (!reachable) return
        val missing = _browse.value.narrators.mapTo(HashSet()) { it.name }
        if (missing.isEmpty()) return
        val map = HashMap<String, String>()
        for (page in 0 until 40) {
            if (missing.isEmpty()) break
            val pg = try {
                c.libraryItems(lib.id, page, 100, CatalogSortField.TITLE.apiSortParameter, ascending = true, minified = true, filter = null).first
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                break
            }
            for (book in pg.results) for (n in book.media.metadata.narratorNamesForLibraryBrowseCoverMatch()) {
                if (n in missing) {
                    map[n] = book.id
                    missing.remove(n)
                }
            }
            if (pg.results.size < 100) break
        }
        _browse.update { it.copy(narratorCoverItemIdByName = map) }
        if (map.isNotEmpty()) {
            session.currentLocalLibraryStore()?.let { store -> runCatching { withContext(Dispatchers.IO) { store.updateNarratorCoverMap(lib.id, map) } } }
        }
    }

    // MARK: - Browse: Serien

    private suspend fun restoreBrowseSeriesFromLocalStore(): Boolean {
        val store = session.currentLocalLibraryStore() ?: return false
        val lib = libraryCatalog ?: return false
        val s = _sort.value
        val desc = CatalogLogic.seriesApiDescending(s.seriesField, s.seriesDescending)
        val m = withContext(Dispatchers.IO) { runCatching { store.fetchSeries(lib.id, s.seriesField.apiSortParameter, desc) }.getOrNull() }
            ?: return false
        _browse.update { it.copy(series = m.items, seriesTotal = m.total) }
        browseSeriesNextPage = m.nextPage
        return true
    }

    private suspend fun loadBrowseSeries(force: Boolean) {
        if (session.offlineHomeUIActive) {
            if (!force && _browse.value.series.isNotEmpty()) return
            restoreBrowseSeriesFromLocalStore()
            val ids = _downloadedItemIds.value
            val rows = _browse.value.series.mapNotNull { s ->
                val books = s.books.orEmpty().filter { it.id in ids }
                if (books.isEmpty()) null else AbsLibrarySeriesListItem(s.id, s.name, books)
            }
            _browse.update { it.copy(series = rows, seriesTotal = rows.size) }
            browseSeriesNextPage = 1
            return
        }
        if (session.client == null || libraryCatalog == null) return
        if (_browse.value.seriesLoading) return
        if (!force && _browse.value.series.isNotEmpty()) return
        if (_browse.value.series.isEmpty()) restoreBrowseSeriesFromLocalStore()
        if (!force && _browse.value.series.isNotEmpty()) return
        if (!reachable) return
        loadBrowseSeriesPage(reset = true)
    }

    private suspend fun loadBrowseSeriesPage(reset: Boolean) {
        val c = session.client ?: return
        val lib = libraryCatalog ?: return
        if (!reachable) {
            restoreBrowseSeriesFromLocalStore()
            return
        }
        if (_browse.value.seriesLoading) return
        if (reset) {
            browseSeriesNextPage = 0
            if (_browse.value.series.isEmpty()) restoreBrowseSeriesFromLocalStore()
            if (_browse.value.series.isEmpty()) _browse.update { it.copy(seriesTotal = 0) }
        } else {
            val b = _browse.value
            if (b.seriesTotal <= 0 || b.series.size >= b.seriesTotal) return
        }
        val page = browseSeriesNextPage
        val s = _sort.value
        val desc = CatalogLogic.seriesApiDescending(s.seriesField, s.seriesDescending)
        _browse.update { it.copy(seriesLoading = true) }
        try {
            val (items, total, _) = c.librarySeriesPage(lib.id, page, 40, s.seriesField.apiSortParameter, desc)
            if (session.offlineHomeUIActive) return
            session.currentLocalLibraryStore()?.let { store ->
                runCatching {
                    withContext(Dispatchers.IO) {
                        if (reset && page == 0) store.replaceSeriesFirstPage(lib.id, s.seriesField.apiSortParameter, desc, total, items)
                        else store.appendSeriesPage(lib.id, total, items)
                    }
                }
            }
            _browse.update { it.copy(seriesTotal = total) }
            if (items.isEmpty() && !reset) return
            _browse.update { b -> b.copy(series = if (reset) items else b.series + items) }
            browseSeriesNextPage = page + 1
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _browse.update { it.copy(seriesLoading = false) }
        }
    }

    /** iOS: `loadMoreBrowseSeriesIfNeeded`. */
    suspend fun loadMoreBrowseSeriesIfNeeded(currentItemId: String?) {
        if (_booksBrowseSection.value != BooksBrowseSection.SERIES) return
        val b = _browse.value
        if (b.seriesTotal <= 0) return
        if (!CatalogLogic.shouldPrefetchNextPage(currentItemId, b.series) { it.id }) return
        if (b.series.size >= b.seriesTotal) return
        loadBrowseSeriesPage(reset = false)
    }

    // MARK: - Browse: Sammlungen

    private fun applyCollections(items: List<AbsLibraryCollectionListItem>, total: Int) {
        collectionsFetched = items
        val s = _sort.value
        _browse.update {
            it.copy(
                collections = CatalogLogic.sortedCollections(items, s.collectionsField, s.collectionsDescending),
                collectionsTotal = total,
                collectionBooksById = items.associate { c -> c.id to c.books.orEmpty() },
            )
        }
    }

    private suspend fun restoreBrowseCollectionsFromLocalStore(): Boolean {
        val store = session.currentLocalLibraryStore() ?: return false
        val lib = libraryCatalog ?: return false
        val pair = withContext(Dispatchers.IO) { runCatching { store.fetchCollections(lib.id) }.getOrNull() } ?: return false
        applyCollections(pair.first, pair.second)
        return true
    }

    private suspend fun loadBrowseCollections(force: Boolean) {
        if (session.offlineHomeUIActive) {
            if (!force && _browse.value.collections.isNotEmpty()) return
            restoreBrowseCollectionsFromLocalStore()
            val ids = _downloadedItemIds.value
            val rows = collectionsFetched.mapNotNull { c ->
                val books = c.books.orEmpty().filter { it.id in ids }
                if (books.isEmpty()) null else c.copy(books = books)
            }
            applyCollections(rows, rows.size)
            return
        }
        val c = session.client ?: return
        val lib = libraryCatalog ?: return
        if (_browse.value.collectionsLoading) return
        if (!force && _browse.value.collections.isNotEmpty()) return
        if (_browse.value.collections.isEmpty()) restoreBrowseCollectionsFromLocalStore()
        if (!force && _browse.value.collections.isNotEmpty()) return
        if (!reachable) return
        _browse.update { it.copy(collectionsLoading = true) }
        try {
            val (items, total, _) = c.libraryCollectionsAll(lib.id, minified = true)
            if (session.offlineHomeUIActive) return
            session.currentLocalLibraryStore()?.let { store -> runCatching { withContext(Dispatchers.IO) { store.replaceCollections(lib.id, total, items) } } }
            applyCollections(items, total)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _browse.update { it.copy(collectionsLoading = false) }
        }
    }

    // MARK: - Browse: Genres / Tags

    private fun applyBrowseGenresFromStats(rows: List<AbsLibraryGenreStat>) {
        genresFetched = rows.mapNotNull { r -> r.genre.swiftTrim().takeIf { it.isNotEmpty() }?.let { BooksBrowseGenreListItem(it, r.count.takeIf { c -> c > 0 }) } }
        resortBrowseGenresDisplay()
    }

    private suspend fun restoreBrowseGenresFromLocalStore(): Boolean {
        val store = session.currentLocalLibraryStore() ?: return false
        val lib = libraryCatalog ?: return false
        val cached = withContext(Dispatchers.IO) { runCatching { store.fetchGenreStats(lib.id) }.getOrDefault(emptyList()) }
        if (cached.isEmpty()) return false
        applyBrowseGenresFromStats(cached)
        return _browse.value.genres.any { it.numBooks != null }
    }

    private suspend fun loadBrowseGenres(force: Boolean) {
        if (session.offlineHomeUIActive) {
            if (!force && _browse.value.genres.isNotEmpty()) return
            genresFetched = CatalogLogic.offlineGenres(_downloadedBooks.value)
            resortBrowseGenresDisplay()
            return
        }
        val c = session.client ?: return
        val lib = libraryCatalog ?: return
        if (_browse.value.genresLoading) return
        if (_browse.value.genres.isEmpty()) restoreBrowseGenresFromLocalStore()
        if (!force && _browse.value.genres.any { it.numBooks != null }) return
        if (!reachable) return
        _browse.update { it.copy(genresLoading = true) }
        try {
            val stats = c.serverLibraryStats(lib.id)
            if (stats.genresWithCount.isNotEmpty()) {
                session.currentLocalLibraryStore()?.let { store ->
                    runCatching { withContext(Dispatchers.IO) { store.replaceGenreStats(lib.id, stats.genresWithCount) } }
                }
            }
            applyBrowseGenresFromStats(stats.genresWithCount)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (_browse.value.genres.isEmpty()) restoreBrowseGenresFromLocalStore()
            if (_browse.value.genres.isEmpty()) session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _browse.update { it.copy(genresLoading = false) }
        }
    }

    private fun applyBrowseTagsFromStats(rows: List<AbsLibraryTagStat>) {
        tagsFetched = rows.mapNotNull { r -> r.tag.swiftTrim().takeIf { it.isNotEmpty() }?.let { BooksBrowseTagListItem(it, r.count.takeIf { c -> c > 0 }) } }
        resortBrowseTagsDisplay()
    }

    private suspend fun restoreBrowseTagsFromLocalStore(): Boolean {
        val store = session.currentLocalLibraryStore() ?: return false
        val lib = libraryCatalog ?: return false
        val cached = withContext(Dispatchers.IO) { runCatching { store.fetchTagStats(lib.id) }.getOrDefault(emptyList()) }
        if (cached.isEmpty()) return false
        applyBrowseTagsFromStats(cached)
        return _browse.value.tags.any { it.numBooks != null }
    }

    private suspend fun loadBrowseTags(force: Boolean) {
        if (session.offlineHomeUIActive) {
            if (!force && _browse.value.tags.isNotEmpty()) return
            tagsFetched = CatalogLogic.offlineTags(_downloadedBooks.value)
            resortBrowseTagsDisplay()
            return
        }
        val c = session.client ?: return
        val lib = libraryCatalog ?: return
        if (_browse.value.tagsLoading) return
        if (_browse.value.tags.isEmpty()) restoreBrowseTagsFromLocalStore()
        if (!force && _browse.value.tags.any { it.numBooks != null }) return
        if (!reachable) return
        _browse.update { it.copy(tagsLoading = true) }
        try {
            val filterData = c.libraryFilterData(lib.id)
            val collator = de.letzgo.abstand.store.LocalLibraryQueries.localizedStandardCollator()
            val names = filterData.tags.orEmpty().map { it.swiftTrim() }.filter { it.isNotEmpty() }.distinct().sortedWith(collator)
            tagsFetched = names.map { BooksBrowseTagListItem(it, null) }
            resortBrowseTagsDisplay()
            val stats = fetchBrowseTagBookCounts(names)
            if (stats.isNotEmpty()) {
                session.currentLocalLibraryStore()?.let { store -> runCatching { withContext(Dispatchers.IO) { store.replaceTagStats(lib.id, stats) } } }
            }
            applyBrowseTagsFromStats(stats)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (_browse.value.tags.isEmpty()) restoreBrowseTagsFromLocalStore()
            if (_browse.value.tags.isEmpty()) session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _browse.update { it.copy(tagsLoading = false) }
        }
    }

    /** iOS: `fetchBrowseTagBookCounts` — je Tag eine `limit=1`-Abfrage (Total), max. 120, 4 parallel. */
    private suspend fun fetchBrowseTagBookCounts(tagNames: List<String>): List<AbsLibraryTagStat> {
        val c = session.client ?: return emptyList()
        val lib = libraryCatalog ?: return emptyList()
        val names = tagNames.map { it.swiftTrim() }.filter { it.isNotEmpty() }.distinct().take(120)
        if (names.isEmpty()) return emptyList()
        val sortKey = catalogSortKey
        val ascending = catalogAscending
        val out = ArrayList<AbsLibraryTagStat>()
        for (chunk in names.chunked(CatalogLogic.BROWSE_FACET_NETWORK_CONCURRENCY)) {
            out += coroutineScope {
                chunk.map { name ->
                    async {
                        try {
                            val (page, _) = c.libraryItems(lib.id, 0, 1, sortKey, ascending, true, CatalogLogic.catalogFilterKey("tags", name))
                            AbsLibraryTagStat(name, page.total)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            null
                        }
                    }
                }.awaitAll().filterNotNull()
            }
        }
        val collator = de.letzgo.abstand.store.LocalLibraryQueries.localizedStandardCollator()
        return out.sortedWith { a, b -> collator.compare(a.tag, b.tag) }
    }

    // MARK: - Browse: eBooks

    @Serializable
    private data class BrowseEbooksOrderSnapshot(val sortKey: String, val pure: List<String>, val supplementary: List<String>)

    private fun browseEbooksOrderSortKey(): String {
        val s = _sort.value
        val (sort, desc) = CatalogLogic.ebooksSortKey(s.catalogField, s.catalogDescending)
        return "$sort|$desc"
    }

    private fun saveBrowseEbooksOrder(libraryId: String, pure: List<AbsBook>, supplementary: List<AbsBook>) {
        val snap = BrowseEbooksOrderSnapshot(browseEbooksOrderSortKey(), pure.map { it.id }, supplementary.map { it.id })
        Prefs.setString(Keys.ebookBrowseOrderPrefix + libraryId, AbsJson.encoder.encodeToString(BrowseEbooksOrderSnapshot.serializer(), snap))
    }

    private fun loadBrowseEbooksOrder(libraryId: String): BrowseEbooksOrderSnapshot? {
        val raw = Prefs.string(Keys.ebookBrowseOrderPrefix + libraryId) ?: return null
        val snap = runCatching { AbsJson.decoder.decodeFromString(BrowseEbooksOrderSnapshot.serializer(), raw) }.getOrNull() ?: return null
        return snap.takeIf { it.sortKey == browseEbooksOrderSortKey() }
    }

    /** iOS: `restoreBrowseEbooksFromLocalStore(requireOrderSnapshot:)`. */
    private suspend fun restoreBrowseEbooksFromLocalStore(requireOrderSnapshot: Boolean = false): Boolean {
        val store = session.currentLocalLibraryStore() ?: return false
        val lib = libraryCatalog ?: return false
        val (pureAll, suppAll) = withContext(Dispatchers.IO) {
            val dao = store.dao
            runCatching {
                de.letzgo.abstand.store.LocalLibraryQueries.browsePureEbooks(dao, lib.id) to
                    de.letzgo.abstand.store.LocalLibraryQueries.browseSupplementaryEbooks(dao, lib.id)
            }.getOrDefault(emptyList<AbsBook>() to emptyList())
        }
        var pure = pureAll
        var supp = suppAll
        val snap = loadBrowseEbooksOrder(lib.id)
        if (snap != null) {
            val byId = (pure + supp).associateBy { it.id }
            val orderedPure = snap.pure.mapNotNull { byId[it] }
            val orderedSupp = snap.supplementary.mapNotNull { byId[it] }
            if (orderedPure.isNotEmpty() || orderedSupp.isNotEmpty()) {
                pure = orderedPure
                supp = orderedSupp
            } else if (requireOrderSnapshot) {
                return false
            }
        } else if (requireOrderSnapshot) {
            return false
        }
        if (pure.isEmpty() && supp.isEmpty()) return false
        _browse.update { it.copy(ebooks = pure, ebooksSupplementary = supp) }
        browseEbooksTotal = pure.size
        browseEbooksNextPage = (pure.size + CatalogLogic.LIBRARY_CATALOG_PAGE_LIMIT - 1) / CatalogLogic.LIBRARY_CATALOG_PAGE_LIMIT
        return true
    }

    /** iOS: `prepareBrowseEbooksForSortChange`. */
    private suspend fun prepareBrowseEbooksForSortChange() {
        if (restoreBrowseEbooksFromLocalStore(requireOrderSnapshot = reachable)) return
        _browse.update { it.copy(ebooks = emptyList(), ebooksSupplementary = emptyList()) }
        browseEbooksTotal = 0
        browseEbooksNextPage = 0
    }

    private suspend fun loadBrowseEbooks(force: Boolean) {
        if (session.client == null || libraryCatalog == null) return
        if (_browse.value.ebooksLoading) return
        if (_browse.value.ebooks.isEmpty() && _browse.value.ebooksSupplementary.isEmpty()) {
            restoreBrowseEbooksFromLocalStore(requireOrderSnapshot = reachable)
        }
        if (!force && browseEbooksSessionFetchDone) return
        if (!reachable) {
            restoreBrowseEbooksFromLocalStore()
            return
        }
        loadBrowseEbooksPage(reset = true)
        browseEbooksSessionFetchDone = true
    }

    /** iOS: `loadMoreBrowseEbooksIfNeeded`. */
    suspend fun loadMoreBrowseEbooksIfNeeded(currentItemId: String) {
        if (_browse.value.ebooksLoading || !CatalogLogic.hasMorePages(browseEbooksTotal, browseEbooksNextPage)) return
        val list = _browse.value.ebooks
        val idx = list.indexOfFirst { it.id == currentItemId }
        if (idx < 0 || idx < list.size - 8) return
        loadBrowseEbooksPage(reset = false)
    }

    private fun rememberEbookFormatsFromCatalog(books: List<AbsBook>) {
        EbookLocalStore.syncKnownFormatsFromDisk(session.cacheAccountDir())
        for (b in books) for (fmt in b.attachedEbookFormats) EbookLocalStore.rememberKnownFormat(fmt, b.id)
    }

    private suspend fun loadBrowseEbooksPage(reset: Boolean) {
        val c = session.client ?: return
        val lib = libraryCatalog ?: return
        if (!reachable) {
            restoreBrowseEbooksFromLocalStore()
            return
        }
        if (_browse.value.ebooksLoading) return
        if (reset) {
            if (_browse.value.ebooks.isEmpty() && _browse.value.ebooksSupplementary.isEmpty()) restoreBrowseEbooksFromLocalStore(requireOrderSnapshot = true)
        } else if (!CatalogLogic.hasMorePages(browseEbooksTotal, browseEbooksNextPage)) {
            return
        }
        _browse.update { it.copy(ebooksLoading = true) }
        try {
            val s = _sort.value
            val (sort, desc) = CatalogLogic.ebooksSortKey(s.catalogField, s.catalogDescending)
            var page = if (reset) 0 else browseEbooksNextPage
            var total = browseEbooksTotal
            val fetched = ArrayList<AbsBook>()
            do {
                val (p, _) = c.libraryItems(
                    lib.id, page, CatalogLogic.LIBRARY_CATALOG_PAGE_LIMIT, sort, !desc, true,
                    CatalogLogic.catalogFilterKey("ebooks", "ebook"),
                )
                total = p.total
                fetched += p.results
                page += 1
                if (p.results.isEmpty()) break
            } while (reset && page * CatalogLogic.LIBRARY_CATALOG_PAGE_LIMIT < total)
            val usable = fetched.filter { it.isUsableEbookListRow }
            val rows = usable.filter { !it.isPlayableAudiobook }
            val audiobooksWithEbook = usable.filter { it.isPlayableAudiobook }
            rememberEbookFormatsFromCatalog(usable)
            val store = session.currentLocalLibraryStore()
            if (reset) {
                val (supPage, _) = c.libraryItems(lib.id, 0, 200, sort, !desc, false, CatalogLogic.catalogFilterKey("ebooks", "supplementary"))
                val supRows = supPage.results.filter { it.isPlayableAudiobook }.toMutableList()
                val supIds = supRows.mapTo(HashSet()) { it.id }
                supRows += audiobooksWithEbook.filter { it.id !in supIds }
                rememberEbookFormatsFromCatalog(supRows)
                browseEbooksTotal = total
                browseEbooksNextPage = page
                _browse.update { it.copy(ebooks = rows, ebooksSupplementary = supRows) }
                saveBrowseEbooksOrder(lib.id, rows, supRows)
                store?.let { runCatching { withContext(Dispatchers.IO) { it.upsertEbookCatalogBooks(rows, supRows) } } }
            } else {
                browseEbooksTotal = total
                browseEbooksNextPage = page
                val b = _browse.value
                val seen = b.ebooks.mapTo(HashSet()) { it.id }
                val seenSup = b.ebooksSupplementary.mapTo(HashSet()) { it.id }
                val newAudio = audiobooksWithEbook.filter { it.id !in seenSup }
                _browse.update { it.copy(ebooks = it.ebooks + rows.filter { r -> r.id !in seen }, ebooksSupplementary = it.ebooksSupplementary + newAudio) }
                store?.let { runCatching { withContext(Dispatchers.IO) { it.upsertEbookCatalogBooks(rows, newAudio) } } }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            _browse.update { it.copy(ebooksLoading = false) }
        }
    }

    // MARK: - Browse-Listen gesamt aus der lokalen DB

    /** iOS: `restoreAllBrowseListsFromLocalStore`. */
    suspend fun restoreAllBrowseListsFromLocalStore() {
        if (session.cacheAccountDir() == null || libraryCatalog == null) return
        restoreBrowseAuthorsFromLocalStore()
        restoreBrowseSeriesFromLocalStore()
        restoreBrowseNarratorsFromLocalStore()
        restoreBrowseCollectionsFromLocalStore()
        restoreBrowseGenresFromLocalStore()
        restoreBrowseTagsFromLocalStore()
    }

    /** iOS: `booksInBrowseCollection(id:)`. */
    fun booksInBrowseCollection(id: String): List<AbsBook> = _browse.value.collectionBooksById[id].orEmpty()

    /** iOS: `bookShowsSupplementaryEbookBadge` (Stub-Flag oder bekannte Supplementary-Liste). */
    fun bookShowsSupplementaryEbookBadge(book: AbsBook): Boolean =
        book.isCatalogSupplementaryEbook || _browse.value.ebooksSupplementary.any { it.id == book.id }

    /** iOS: `mergedLocalCatalogBooks` (In-Memory-Teil). */
    fun mergedInMemoryCatalogBooks(): List<AbsBook> {
        val b = _browse.value
        return CatalogLogic.mergeBooksPreferringRicher(
            listOf(_books.value, _downloadedBooks.value, b.ebooks, b.ebooksSupplementary) +
                b.collectionBooksById.values + b.series.map { it.books.orEmpty() },
        ) { it.isUsableLibraryCatalogRow || it.isUsableEbookListRow }
    }

    /** iOS: `applyUpdatedBookToLoadedLists` — frischen Serverstand (Metadaten-Sheet) in die Listen übernehmen. */
    fun applyUpdatedBook(fresh: AbsBook) {
        fun List<AbsBook>.patched() = if (any { it.id == fresh.id }) map { if (it.id == fresh.id) fresh else it } else this
        _books.value = _books.value.patched()
        _downloadedBooks.value = _downloadedBooks.value.patched()
    }

    /** iOS: `lookupBookStub(id:)`. */
    fun lookupBookStub(id: String): AbsBook? {
        _books.value.firstOrNull { it.id == id }?.let { return it }
        val b = _browse.value
        b.ebooks.firstOrNull { it.id == id }?.let { return it }
        b.ebooksSupplementary.firstOrNull { it.id == id }?.let { return it }
        return _downloadedBooks.value.firstOrNull { it.id == id }
    }

    // MARK: - Downloads

    /** Download-Liste neu von der Platte lesen (iOS: `downloadedItemIds` + `refreshDownloadedShelfFromManifests`). */
    fun refreshDownloadedItemIds() {
        startDownloadsWatchIfNeeded()
        scope.launch {
            val ids = withContext(Dispatchers.IO) { runCatching { DownloadManager.scanDownloadedStorageIds() }.getOrDefault(emptySet()) }
            _downloadedItemIds.value = ids
            _downloadedBooks.value = computeDownloadedBooks(ids)
        }
    }

    private fun startDownloadsWatchIfNeeded() {
        if (downloadsWatchStarted) return
        downloadsWatchStarted = true
        scope.launch {
            var first = true
            DownloadManager.completedDownloadCount.collect {
                if (first) first = false else refreshDownloadedItemIds()
            }
        }
    }

    /** iOS: `downloadedAudiobooksWithFullMetadata` — Katalog-/Store-Metadaten vor Manifest-Stub. */
    private suspend fun computeDownloadedBooks(ids: Set<String>): List<AbsBook> {
        val inMemory = mergedInMemoryCatalogBooks().associateBy { it.id }
        val store = session.currentLocalLibraryStore()
        return withContext(Dispatchers.IO) {
            ids.sorted().mapNotNull { sid ->
                val folder = DownloadManager.existingDownloadFolder(sid) ?: return@mapNotNull null
                val manifest = AbsDownloadManifest.load(folder) ?: return@mapNotNull null
                if (manifest.episodeId.trimmedOrEmpty().isNotEmpty()) return@mapNotNull null
                inMemory[sid] ?: runCatching { store?.fetchBook(sid) }.getOrNull() ?: AbsBook.fromDownloadManifest(manifest)
            }
        }
    }

    /** iOS: `downloadStorageIdForLibraryItem` — Ordner-ID (Folgen: `li_…-ep_…`). */
    fun downloadStorageIdForLibraryItem(libraryItemId: String): String? {
        val lid = libraryItemId.swiftTrim()
        if (lid.isEmpty()) return null
        val ids = _downloadedItemIds.value
        if (lid in ids) return lid
        return ids.firstOrNull { it.startsWith("$lid-") }
    }

    /** iOS: `startDownload(book:)`. */
    fun startDownload(book: AbsBook) {
        if (session.client == null) return
        DownloadManager.startDownload(book = book, storageItemId = book.id)
    }

    /** iOS: `removeLocalDownload(bookId:)` — Abbruch/Entfernen + Transkripte des Titels. */
    fun removeLocalDownload(bookId: String) {
        DownloadManager.cancel(bookId)
        DownloadManager.deleteDownload(bookId)
        _downloadedItemIds.value = _downloadedItemIds.value - bookId
        _downloadedBooks.value = _downloadedBooks.value.filterNot { it.id == bookId }
        runCatching { PlayerTranscriptCacheStore.removeAll(session.cacheAccountDir(), bookId) }
        refreshDownloadedItemIds()
    }

    // MARK: - Buch-Detail

    /** iOS: `immediateBookDetail(id:)` — Detail-Cache, sonst Download-Manifest. */
    suspend fun immediateBookDetail(id: String): AbsBook? {
        cachedBookDetail(id)?.let { return it }
        return withContext(Dispatchers.IO) {
            if (id !in _downloadedItemIds.value) return@withContext null
            DownloadManager.existingDownloadFolder(id)?.let { AbsDownloadManifest.load(it) }?.let { AbsBook.fromDownloadManifest(it) }
        }
    }

    /** iOS: `cachedBookDetail(id:)` (+ `cachedBookFallback`: Katalog-Stub). */
    suspend fun cachedBookDetail(id: String): AbsBook? {
        val store = session.currentLocalLibraryStore()
        val detail = store?.let { withContext(Dispatchers.IO) { runCatching { it.fetchBookDetail(id) }.getOrNull() } }
        return detail ?: lookupBookStub(id) ?: store?.let { withContext(Dispatchers.IO) { runCatching { it.fetchBook(id) }.getOrNull() } }
    }

    /** iOS: `loadBookDetail(id:)` — erweiterte Antwort laden, mit Download-Manifest mergen, persistieren. */
    suspend fun loadBookDetail(id: String): AbsBook? {
        val manifest = if (id in _downloadedItemIds.value) {
            withContext(Dispatchers.IO) { DownloadManager.existingDownloadFolder(id)?.let { AbsDownloadManifest.load(it) } }
        } else null
        val c = session.client
        if (manifest != null) {
            val fromManifest = AbsBook.fromDownloadManifest(manifest)
            val cached = cachedBookDetail(id)
            if (!reachable || c == null || !session.mayUseServerNetwork) return cached ?: fromManifest
            val expanded = runCatching { c.item(id, expanded = true) }.getOrNull() ?: return cached ?: fromManifest
            val merged = expanded.mergingLocalDownloadPlayback(fromManifest)
            persistBookDetail(merged)
            return merged
        }
        if (c == null || !session.mayUseServerNetwork) return cachedBookDetail(id)
        return try {
            val expanded = c.item(id, expanded = true)
            persistBookDetail(expanded)
            expanded
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            cachedBookDetail(id)
        }
    }

    /** iOS: `persistBookDetail`. */
    fun persistBookDetail(book: AbsBook) {
        val store = session.currentLocalLibraryStore() ?: return
        scope.launch(Dispatchers.IO) { runCatching { store.upsertBookDetail(book) } }
    }

    /**
     * iOS: `loadBookListeningSessions(libraryItemId:bookMediaId:)` — `/api/me/item/listening-sessions/:id`,
     * Fallback globale Liste gefiltert nach Item/`mediaId`; Ergebnis in Room gecacht.
     */
    suspend fun loadBookListeningSessions(libraryItemId: String, bookMediaId: String?, maxPages: Int = 20): List<AbsListeningSession> {
        val bid = libraryItemId.swiftTrim()
        if (bid.isEmpty()) return emptyList()
        val store = session.currentLocalLibraryStore()
        val cached = store?.let { withContext(Dispatchers.IO) { runCatching { it.fetchListeningSessions(bid, null) }.getOrNull() } }
        val c = session.client
        if (c == null || !reachable || !session.mayUseServerNetwork) return cached.orEmpty()
        val mid = bookMediaId?.swiftTrim()?.ifEmpty { null }

        suspend fun collectPaged(load: suspend (Int) -> AbsListeningSessionsPayload): List<AbsListeningSession> {
            val out = ArrayList<AbsListeningSession>()
            var page = 0
            while (page < maxPages) {
                val res = load(page)
                out += res.sessions
                page += 1
                if (page >= res.numPages || res.sessions.isEmpty()) break
            }
            return out
        }

        suspend fun legacy(): List<AbsListeningSession> {
            val out = ArrayList<AbsListeningSession>()
            var page = 0
            while (page < maxPages) {
                val res = try {
                    c.listeningSessionsMe(100, page)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    break
                }
                out += res.sessions.filter { s ->
                    if (!s.episodeId?.swiftTrim().isNullOrEmpty()) return@filter false
                    if (s.libraryItemId == bid) return@filter true
                    mid != null && s.bookId?.swiftTrim() == mid
                }
                page += 1
                if (page >= res.numPages) break
            }
            return out.sortedByDescending { it.startedAt }
        }

        val result = try {
            val rows = collectPaged { p -> c.listeningSessionsForLibraryItem(bid, null, 100, p) }
            if (rows.isNotEmpty()) rows.sortedByDescending { it.startedAt } else legacy()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            legacy().ifEmpty { return cached.orEmpty() }
        }
        store?.let { s -> scope.launch(Dispatchers.IO) { runCatching { s.replaceListeningSessions(bid, null, result) } } }
        return result
    }

    /** iOS: `serverWebURL(forLibraryItemId:)` — Web-Oberfläche des Servers (`/item/<id>`). */
    fun serverWebURL(libraryItemId: String): String? {
        val id = libraryItemId.swiftTrim().ifEmpty { return null }
        val base = AbsApiClient.normalizeServerURL(session.serverURL.value) ?: return null
        return base.trimEnd('/') + "/item/" + id
    }

    /** iOS: `authorImageURL(authorId:)`. */
    fun authorImageURL(authorId: String): String? {
        val base = AbsApiClient.normalizeServerURL(session.serverURL.value) ?: return null
        return base.trimEnd('/') + "/api/authors/" + authorId + "/image"
    }

    // MARK: - Fortschritt-Aktionen (Detail/Karten)

    private fun bookDuration(id: String): Double? = lookupBookStub(id)?.media?.duration

    private fun wasCurrentPlaybackForBook(bookId: String): Boolean {
        val p = PlaybackController.sharedOrNull() ?: return false
        return p.activeBook.value?.id == bookId && p.activePlaybackEpisodeId.value == null
    }

    private fun catalogUsesProgressServerFilter(): Boolean {
        val f = _filter.value
        when (f.libraryCatalogQuickFilter) {
            LibraryCatalogQuickFilter.IN_PROGRESS, LibraryCatalogQuickFilter.FINISHED, LibraryCatalogQuickFilter.NOT_STARTED -> return true
            else -> Unit
        }
        return f.activeLibraryFilter?.swiftTrim().orEmpty().startsWith("progress.")
    }

    private fun insertStubIfMissing(bookId: String) {
        if (_books.value.any { it.id == bookId }) return
        lookupBookStub(bookId)?.let { _books.value = listOf(it) + _books.value }
    }

    private fun removeFromCatalogList(bookId: String) {
        _books.value = _books.value.filterNot { it.id == bookId }
    }

    /** iOS: `patchBooksCatalogAfterAudiobookProgressChange`. */
    private fun patchCatalogAfterProgressChange(bookId: String, finished: Boolean) {
        if (_booksBrowseSection.value != BooksBrowseSection.BOOKS || session.selectedBooksLibrary.value == null) return
        when (_filter.value.libraryCatalogQuickFilter) {
            LibraryCatalogQuickFilter.IN_PROGRESS, LibraryCatalogQuickFilter.NOT_STARTED ->
                if (finished) removeFromCatalogList(bookId) else insertStubIfMissing(bookId)
            LibraryCatalogQuickFilter.FINISHED -> if (finished) insertStubIfMissing(bookId) else removeFromCatalogList(bookId)
            else -> {
                val f = _filter.value.activeLibraryFilter?.swiftTrim().orEmpty()
                if (!f.startsWith("progress.")) return
                val decoded = decodedProgressFilter(f)
                when {
                    decoded == "in-progress" || decoded == "not-started" -> if (finished) removeFromCatalogList(bookId) else insertStubIfMissing(bookId)
                    decoded == "finished" -> if (finished) insertStubIfMissing(bookId) else removeFromCatalogList(bookId)
                }
            }
        }
    }

    /** iOS: `patchBooksCatalogAfterAudiobookProgressDiscard`. */
    private fun patchCatalogAfterProgressDiscard(bookId: String) {
        if (_booksBrowseSection.value != BooksBrowseSection.BOOKS || session.selectedBooksLibrary.value == null) return
        when (_filter.value.libraryCatalogQuickFilter) {
            LibraryCatalogQuickFilter.IN_PROGRESS, LibraryCatalogQuickFilter.FINISHED -> removeFromCatalogList(bookId)
            LibraryCatalogQuickFilter.NOT_STARTED -> insertStubIfMissing(bookId)
            else -> {
                val f = _filter.value.activeLibraryFilter?.swiftTrim().orEmpty()
                if (!f.startsWith("progress.")) return
                when (decodedProgressFilter(f)) {
                    "in-progress", "finished" -> removeFromCatalogList(bookId)
                    "not-started" -> insertStubIfMissing(bookId)
                }
            }
        }
    }

    /**
     * Wert eines `progress.<base64>`-Filters. iOS prüft `f.contains("in-progress")` auf dem
     * **Base64**-String — trifft nie (siehe Report); Android dekodiert den Wert.
     */
    private fun decodedProgressFilter(f: String): String =
        runCatching { String(java.util.Base64.getDecoder().decode(f.removePrefix("progress.")), Charsets.UTF_8) }.getOrDefault("")

    private fun needsFullLibraryReloadAfterProgressChange(bookId: String, finished: Boolean): Boolean {
        if (!catalogUsesProgressServerFilter()) return false
        val q = _filter.value.libraryCatalogQuickFilter
        if (q == LibraryCatalogQuickFilter.FINISHED && finished) return _books.value.none { it.id == bookId }
        if (q == LibraryCatalogQuickFilter.IN_PROGRESS && !finished) return _books.value.none { it.id == bookId } && lookupBookStub(bookId) == null
        return false
    }

    /** iOS: `markFinished(bookId:)`. */
    suspend fun markFinished(bookId: String) {
        progress.ensureLocalProgressLoaded()
        val wasPlaying = wasCurrentPlaybackForBook(bookId)
        progress.applyLocalMarkFinished(bookId, null, bookDuration(bookId))
        patchCatalogAfterProgressChange(bookId, finished = true)
        progress.markPendingLocalProgressSync(bookId)
        val c = session.client
        if (!session.mayUseServerNetwork || c == null) {
            finishMarkFinishedLocally(bookId, wasPlaying)
            return
        }
        try {
            if (wasPlaying) PlaybackController.sharedOrNull()?.tearDownPlayer()
            c.markFinished(bookId)
            val auth = c.authorize()
            session.applyAuthorizeUser(auth.user)
            progress.clearLocallyFinishedProgressKey(bookId)
            progress.clearPendingLocalProgressSync(bookId)
            progress.reconcileProgressAfterMarkFinished(bookId, null, bookDuration(bookId))
            if (needsFullLibraryReloadAfterProgressChange(bookId, finished = true)) reloadLibrary(reset = true)
            finishMarkFinishedLocally(bookId, wasPlaying = false)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    /** iOS: `finishMarkFinishedLocally` (ohne Home-Teile). */
    private fun finishMarkFinishedLocally(bookId: String, wasPlaying: Boolean) {
        if (wasPlaying) PlaybackController.sharedOrNull()?.tearDownPlayer()
        if (Prefs.string(Keys.lastPlayedItemId) == bookId) Prefs.remove(Keys.lastPlayedItemId)
        if (DownloadManager.removeLocalDownloadIfFinishedSetting(bookId, bookId in _downloadedItemIds.value)) {
            removeLocalDownload(bookId)
        }
    }

    /** iOS: `markUnfinished(bookId:)`. */
    suspend fun markUnfinished(bookId: String) {
        progress.ensureLocalProgressLoaded()
        progress.applyLocalMarkUnfinished(bookId, null)
        progress.markPendingLocalProgressSync(bookId)
        val c = session.client
        if (!session.mayUseServerNetwork || c == null) return
        try {
            c.patchProgress(bookId, null, AbsProgressPatch(isFinished = false))
            patchCatalogAfterProgressChange(bookId, finished = false)
            val auth = c.authorize()
            session.applyAuthorizeSession(auth)
            progress.clearPendingLocalProgressSync(bookId)
            if (needsFullLibraryReloadAfterProgressChange(bookId, finished = false)) reloadLibrary(reset = true)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    /**
     * iOS: `discardBookProgress(bookId:)` — Fortschritt **und** Hör-Sitzungen löschen; läuft der
     * Titel, wird die Wiedergabe vorher beendet.
     */
    suspend fun discardBookProgress(bookId: String) {
        val c = session.client ?: return
        if (!reachable) {
            session.setErrorMessage("No network connection.")
            return
        }
        val row = progress.progress(bookId) ?: return
        val playing = wasCurrentPlaybackForBook(bookId)
        val preferredDeleteIds = listOfNotNull(row.mediaProgressServerId, row.idForMediaProgressDeleteRequest, bookId)
        progress.discardProgressLocally(bookId)
        patchCatalogAfterProgressDiscard(bookId)
        try {
            if (playing) PlaybackController.sharedOrNull()?.tearDownPlayer()
            de.letzgo.abstand.player.PendingOfflineListening.run { load().let { m -> if (bookId in m) save(m - bookId) } }
            val mediaId = lookupBookStub(bookId)?.mediaId
            for (s in loadBookListeningSessions(bookId, mediaId)) runCatching { c.deleteListeningSession(s.id) }
            session.currentLocalLibraryStore()?.let { s -> runCatching { withContext(Dispatchers.IO) { s.replaceListeningSessions(bookId, null, emptyList()) } } }
            c.deleteMediaProgressForLibraryItem(bookId, null, preferredDeleteIds)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    /** iOS: `deleteFromServer(bookId:hardDelete:)` — nur Root. */
    suspend fun deleteFromServer(bookId: String, hardDelete: Boolean = true): Boolean {
        if (!session.isServerRoot.value) {
            session.setErrorMessage("Only the root user can delete books.")
            return false
        }
        val c = session.client
        if (!reachable || c == null) {
            session.setErrorMessage("No network connection.")
            return false
        }
        val id = bookId.swiftTrim().ifEmpty { return false }
        return try {
            c.deleteLibraryItem(id, hardDelete)
            session.setErrorMessage(null)
            removeLocalDownload(id)
            if (_books.value.any { it.id == id }) {
                _books.value = _books.value.filterNot { it.id == id }
                _libraryTotal.value = maxOf(_books.value.size, _libraryTotal.value - 1)
                requestLibraryCatalogScrollToTop()
            }
            _browse.update { b -> b.copy(ebooks = b.ebooks.filterNot { it.id == id }, ebooksSupplementary = b.ebooksSupplementary.filterNot { it.id == id }) }
            session.currentLocalLibraryStore()?.let { s -> runCatching { withContext(Dispatchers.IO) { s.deleteBook(id) } } }
            if (PlaybackController.sharedOrNull()?.activeBook?.value?.id == id) PlaybackController.sharedOrNull()?.tearDownPlayer()
            if (Prefs.string(Keys.lastPlayedItemId) == id) Prefs.remove(Keys.lastPlayedItemId)
            session.refreshProgressFromServer()
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
            false
        }
    }

    // MARK: - eBook-Fortschritt (Detail „Mark as read")

    private fun patchPreservingAudiobookFields(libraryItemId: String, ebookProgress: Double): AbsProgressPatch {
        val row = progress.progress(libraryItemId)
        return AbsProgressPatch(
            currentTime = row?.currentTime, duration = row?.duration, progress = row?.progress,
            isFinished = row?.isFinished, ebookProgress = ebookProgress,
        )
    }

    /** iOS: `markEbookAsFinished(libraryItemId:format:)`. */
    suspend fun markEbookAsFinished(libraryItemId: String, format: AbsEbookFormat) {
        val id = libraryItemId.swiftTrim().ifEmpty { return }
        progress.setEbookProgressOverride(id, 1.0)
        EbookLocalStore.clearReadiumLocator(id, format)
        EbookLocalStore.saveProgressFraction(1.0, id, markFinished = true)
        val c = session.client
        if (!session.mayUseServerNetwork || !reachable || c == null) return
        try {
            c.patchProgress(id, null, patchPreservingAudiobookFields(id, 1.0))
            session.applyAuthorizeUser(c.authorize().user)
            if ((progress.progress(id)?.ebookProgress ?: 0.0) >= 0.995) progress.setEbookProgressOverride(id, null)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "eBook progress sync failed: ${e.message}")
        }
    }

    /** iOS: `resetEbookReadingProgress(libraryItemId:format:)`. */
    suspend fun resetEbookReadingProgress(libraryItemId: String, format: AbsEbookFormat) {
        val id = libraryItemId.swiftTrim().ifEmpty { return }
        progress.setEbookProgressOverride(id, 0.0)
        EbookLocalStore.clearReadiumLocator(id, format)
        EbookLocalStore.clearProgressFraction(id)
        val c = session.client
        if (!session.mayUseServerNetwork || !reachable || c == null) return
        try {
            c.patchProgress(id, null, patchPreservingAudiobookFields(id, 0.0))
            session.applyAuthorizeUser(c.authorize().user)
            val f = progress.progress(id)?.ebookProgress
            if (f == null || f <= 0.005) progress.setEbookProgressOverride(id, null)
            EbookLocalStore.clearProgressFraction(id)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "eBook reset sync failed: ${e.message}")
        }
    }

    /** iOS: `cachedEbookFormat(libraryItemId:)`. */
    fun cachedEbookFormat(libraryItemId: String): AbsEbookFormat? =
        EbookLocalStore.cachedEbookIfPresent(session.cacheAccountDir(), libraryItemId)?.second

    // MARK: - Lesezeichen

    /** iOS: `createBookmark(libraryItemId:time:title:)` — leerer Titel → Position. */
    suspend fun createBookmark(libraryItemId: String, time: Int, title: String): Boolean {
        val c = session.client
        if (c == null || !reachable) {
            session.setErrorMessage("Bookmarks require a server connection.")
            return false
        }
        val lid = libraryItemId.swiftTrim().ifEmpty { return false }
        val finalTitle = title.swiftTrim().ifEmpty { BookDetailLogic.defaultBookmarkTitle(time) }
        return try {
            progress.upsertBookmark(c.createBookmark(lid, time, finalTitle))
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
            false
        }
    }

    /** iOS: `deleteBookmark(_:)`. */
    suspend fun deleteBookmark(bookmark: AbsAudioBookmark) {
        val c = session.client
        if (c == null || !reachable) {
            session.setErrorMessage("Bookmarks require a server connection.")
            return
        }
        try {
            c.deleteBookmark(bookmark.libraryItemId, bookmark.time)
            progress.removeBookmark(bookmark)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    // MARK: - SessionParticipant

    override fun hasCachedBootstrapContent(): Boolean = _books.value.isNotEmpty()

    override fun onSessionActivated() {
        refreshDownloadedItemIds()
    }

    override suspend fun restoreFromLocalStore(store: LocalLibraryStore, booksLibraryId: String?) {
        restoreBooksCatalogPagesFromLocalStore(store, booksLibraryId)
        restoreAllBrowseListsFromLocalStore()
        refreshDownloadedItemIds()
    }

    override fun onDeferredWorkAfterConnect() {
        scope.launch {
            if (libraryCatalog == null) return@launch
            reloadLibrary(reset = true, preserveOtherCachedPages = _books.value.isNotEmpty())
            if (_booksBrowseSection.value != BooksBrowseSection.BOOKS) loadBooksBrowseSectionContentIfNeeded()
        }
    }

    override fun onSessionCleared(clearCredentials: Boolean) {
        libraryReloadSerial++
        sortReloadJob?.cancel()
        _books.value = emptyList()
        _libraryTotal.value = 0
        _isLoadingLibrary.value = false
        libraryPage = 0
        lastBooksCatalogServerSyncAt = null
        _filter.value = CatalogFilterState()
        _booksBrowseSection.value = BooksBrowseSection.BOOKS
        resetBooksBrowseLists()
        _downloadedItemIds.value = emptySet()
        _downloadedBooks.value = emptyList()
    }

    override suspend fun reloadAfterAccountSwitch() {
        refreshDownloadedItemIds()
        reloadLibrary(reset = true)
    }

    override fun onBooksLibrarySelected(library: AbsLibrary, changed: Boolean) {
        if (!changed) return
        resetForLibraryChange()
    }

    override fun onBooksLibraryFocused(library: AbsLibrary) = resetForLibraryChange()

    private fun resetForLibraryChange() {
        libraryReloadSerial++
        _filter.value = CatalogFilterState()
        _books.value = emptyList()
        _libraryTotal.value = 0
        libraryPage = 0
        resetBooksBrowseLists()
        requestLibraryCatalogScrollToTop()
        scope.launch {
            reloadLibrary(reset = true)
            loadBooksBrowseSectionContentIfNeeded()
        }
    }

    override fun onBooksLibraryCleared() {
        libraryReloadSerial++
        _books.value = emptyList()
        _libraryTotal.value = 0
        resetBooksBrowseLists()
    }

    override suspend fun reloadCatalogs() {
        reloadLibrary(reset = true)
        refreshBooksBrowseSectionLists()
    }

    override suspend fun bootstrapLocalSessionOnly() {
        refreshDownloadedItemIds()
        session.currentLocalLibraryStore()?.let { restoreBooksCatalogPagesFromLocalStore(it, libraryCatalog?.id) }
        restoreAllBrowseListsFromLocalStore()
    }

    override suspend fun onOfflineHomeModeExited() {
        refreshDownloadedItemIds()
        reloadLibrary(reset = true)
    }

    private companion object {
        const val TAG = "CatalogStore"
    }
}
