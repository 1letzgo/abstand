package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.EntityDetailAuthorSeriesSection
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.logic.BooksEntityDetailNav
import de.letzgo.abstand.logic.CatalogLogic
import de.letzgo.abstand.logic.CatalogSortField
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Anzeigezustand einer Entity-Detailseite (iOS: die `entityDetail*`-`@Published` von `AppModel`). */
data class EntityDetailState(
    val books: List<AbsBook> = emptyList(),
    val total: Int = 0,
    val loading: Boolean = true,
    val description: String? = null,
    val metaReady: Boolean = false,
    val authorSeriesSections: List<EntityDetailAuthorSeriesSection> = emptyList(),
    val authorStandaloneBooks: List<AbsBook> = emptyList(),
) {
    val hasContent: Boolean
        get() = books.isNotEmpty() || authorStandaloneBooks.isNotEmpty() || authorSeriesSections.isNotEmpty() || description != null
}

/**
 * iOS: `reloadEntityDetail(for:reset:)`, `loadMoreEntityDetailIfNeeded`, `applyEntityDetailFromLocalCache`
 * — **pro Seite** statt geteiltem AppModel-Zustand (iOS teilt `entityDetail*` zwischen allen Tabs und
 * muss deshalb `entityDetailNavKey` prüfen). Local-first: lokale Kopie sofort, Netz verfeinert still.
 */
class EntityDetailLoader(val nav: BooksEntityDetailNav, private val model: AppModel = AppModel.shared) {
    private val session get() = model.session
    private val catalog get() = model.catalog

    private val _state = MutableStateFlow(EntityDetailState())
    val state: StateFlow<EntityDetailState> = _state.asStateFlow()

    private var page = 0
    private var usesLibraryItemFilter = false
    private var generation = 0

    /** iOS: `libraryForEntityDetail(for:)` — eBooks und Hörbücher teilen dieselbe Bibliothek. */
    private fun library(): AbsLibrary? {
        val raw = nav.libraryId?.swiftTrim().orEmpty()
        if (raw.isNotEmpty()) {
            session.booksCatalogLibrary?.takeIf { it.id == raw }?.let { return it }
            session.selectedBooksLibrary.value?.takeIf { it.id == raw }?.let { return it }
            session.libraries.value.firstOrNull { it.id == raw }?.let { return it }
        }
        return session.booksCatalogLibrary
    }

    private fun offlineFiltered(books: List<AbsBook>): List<AbsBook> {
        if (!session.offlineHomeUIActive) return books
        val ids = catalog.downloadedItemIds.value
        return books.filter { it.id in ids }
    }

    /** Lokaler Superset: In-Memory-Listen + komplette `LocalBook`-Tabelle der Bibliothek. */
    private suspend fun localSuperset(): List<AbsBook> {
        val libId = library()?.id
        val stored = session.currentLocalLibraryStore()?.let { store ->
            if (libId == null) emptyList() else withContext(Dispatchers.IO) {
                runCatching { store.fetchAllBooks(libId, CatalogSortField.TITLE.rawValue, false) }.getOrDefault(emptyList())
            }
        }.orEmpty()
        return CatalogLogic.mergeBooksPreferringRicher(listOf(catalog.mergedInMemoryCatalogBooks(), stored)) {
            CatalogLogic.bookMatchesLibrary(it, nav.libraryId)
        }
    }

    /** iOS: `applyEntityDetailFromLocalCache(for:)`. */
    private suspend fun applyFromLocalCache() {
        val next = when (nav.kind) {
            BooksEntityDetailNav.Kind.AUTHOR -> {
                val desc = session.currentLocalLibraryStore()?.let { s -> withContext(Dispatchers.IO) { runCatching { s.fetchAuthorDescription(nav.entityId) }.getOrNull() } }
                val rows = offlineFiltered(localSuperset().filter { it.isUsableAuthorDetailRow && CatalogLogic.bookMatchesAuthor(it, nav.entityId, nav.title) })
                val sorted = CatalogLogic.sortBooksBySeriesOrder(rows)
                EntityDetailState(books = sorted, total = rows.size, description = desc, authorStandaloneBooks = sorted)
            }
            BooksEntityDetailNav.Kind.SERIES -> {
                val cached = catalog.browse.value.series.firstOrNull { it.id == nav.entityId }?.books.orEmpty()
                    .filter { it.isUsableAuthorDetailRow && CatalogLogic.bookMatchesLibrary(it, nav.libraryId) }
                val base = cached.ifEmpty { localSuperset().filter { CatalogLogic.bookMatchesSeries(it, nav.entityId, nav.title) } }
                val rows = CatalogLogic.sortBooksBySeriesOrder(offlineFiltered(base), nav.entityId, nav.title)
                EntityDetailState(books = rows, total = rows.size)
            }
            BooksEntityDetailNav.Kind.NARRATOR -> localList { CatalogLogic.bookMatchesNarrator(it, nav.entityId) }
            BooksEntityDetailNav.Kind.GENRE -> localList { CatalogLogic.bookMatchesGenre(it, nav.entityId) }
            BooksEntityDetailNav.Kind.TAG -> localList { CatalogLogic.bookMatchesTag(it, nav.entityId) }
            BooksEntityDetailNav.Kind.COLLECTION -> {
                val rows = offlineFiltered(catalog.booksInBrowseCollection(nav.entityId).filter { it.isUsableLibraryCatalogRow })
                EntityDetailState(books = rows, total = rows.size, description = collectionDescription())
            }
        }
        usesLibraryItemFilter = false
        _state.value = next.copy(loading = _state.value.loading, metaReady = _state.value.metaReady)
    }

    private suspend fun localList(match: (AbsBook) -> Boolean): EntityDetailState {
        val rows = offlineFiltered(localSuperset().filter { it.isUsableLibraryCatalogRow && match(it) })
        return EntityDetailState(books = rows, total = rows.size)
    }

    private fun collectionDescription(): String? = catalog.browse.value.collections.firstOrNull { it.id == nav.entityId }?.description

    /** iOS: `reloadEntityDetail(for:reset:)` (reset = true; Paging über [loadMoreIfNeeded]). */
    suspend fun reload() {
        val gen = ++generation
        page = 0
        _state.value = EntityDetailState(loading = true)
        applyFromLocalCache()
        if (gen != generation) return
        if (_state.value.hasContent) _state.value = _state.value.copy(metaReady = true)
        val c = session.client
        val lib = library()
        if (!session.mayUseServerNetwork || !session.isNetworkReachable.value || c == null || lib == null) {
            _state.value = _state.value.copy(loading = false, metaReady = true)
            return
        }
        _state.value = _state.value.copy(loading = !_state.value.hasContent)
        try {
            when (nav.kind) {
                BooksEntityDetailNav.Kind.AUTHOR -> {
                    val detail = c.authorDetail(nav.entityId, lib.id, includeItems = true, includeSeries = true)
                    if (gen != generation) return
                    val layout = CatalogLogic.authorDetailLayout(detail)
                    _state.value = _state.value.copy(
                        description = detail.description,
                        authorSeriesSections = layout.seriesSections,
                        authorStandaloneBooks = layout.standalone,
                        books = layout.all,
                        total = layout.all.size,
                    )
                    usesLibraryItemFilter = false
                    session.currentLocalLibraryStore()?.let { store ->
                        model.scope.launch(Dispatchers.IO) { runCatching { store.upsertAuthorDetail(detail.id, lib.id, detail.description) } }
                    }
                }
                BooksEntityDetailNav.Kind.SERIES -> {
                    val cached = catalog.browse.value.series.firstOrNull { it.id == nav.entityId }?.books
                        ?.filter { it.isUsableAuthorDetailRow && CatalogLogic.bookMatchesLibrary(it, nav.libraryId) }.orEmpty()
                    if (cached.isNotEmpty()) {
                        val rows = CatalogLogic.sortBooksBySeriesOrder(cached, nav.entityId, nav.title)
                        _state.value = _state.value.copy(description = null, books = rows, total = rows.size)
                        usesLibraryItemFilter = false
                    } else {
                        usesLibraryItemFilter = true
                        loadViaLibraryFilter(reset = true, gen = gen)
                    }
                }
                BooksEntityDetailNav.Kind.NARRATOR, BooksEntityDetailNav.Kind.GENRE, BooksEntityDetailNav.Kind.TAG -> {
                    usesLibraryItemFilter = true
                    loadViaLibraryFilter(reset = true, gen = gen)
                }
                BooksEntityDetailNav.Kind.COLLECTION -> {
                    usesLibraryItemFilter = false
                    try {
                        val detail = c.collectionDetail(nav.entityId)
                        if (gen != generation) return
                        val rows = detail.books.orEmpty().filter { it.isUsableLibraryCatalogRow }
                        _state.value = _state.value.copy(description = detail.description, books = rows, total = rows.size)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        applyFromLocalCache()
                    }
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (gen != generation) return
            applyFromLocalCache()
            if (_state.value.books.isEmpty()) session.publishErrorUnlessBenignCancellation(e)
        } finally {
            if (gen == generation) _state.value = _state.value.copy(loading = false, metaReady = true)
        }
    }

    /** iOS: `reloadEntityDetailBooksViaLibraryFilter` — Serien in Lesereihenfolge (`sort=sequence`). */
    private suspend fun loadViaLibraryFilter(reset: Boolean, gen: Int) {
        val c = session.client ?: return
        val lib = library() ?: return
        if (reset) {
            page = 0
            _state.value = _state.value.copy(books = emptyList(), total = 0, authorSeriesSections = emptyList(), authorStandaloneBooks = emptyList())
        } else {
            val s = _state.value
            if (s.total <= 0 || s.books.size >= s.total) return
        }
        val sortField = catalog.sort.value
        val (sortKey, ascending) = if (nav.kind == BooksEntityDetailNav.Kind.SERIES) "sequence" to true
        else sortField.catalogField.apiSortParameter to CatalogLogic.catalogAscending(sortField.catalogField, sortField.catalogDescending)
        val pageIndex = page
        val (result, _) = c.libraryItems(lib.id, pageIndex, CatalogLogic.LIBRARY_CATALOG_PAGE_LIMIT, sortKey, ascending, true, nav.libraryFilter)
        if (gen != generation) return
        val raw = result.results.filter { it.isUsableAuthorDetailRow }
        val rows = if (nav.kind == BooksEntityDetailNav.Kind.SERIES) CatalogLogic.sortBooksBySeriesOrder(raw, nav.entityId, nav.title) else raw
        _state.value = _state.value.copy(
            books = if (reset || pageIndex == 0) rows else _state.value.books + rows,
            total = result.total,
        )
        page = result.page + 1
    }

    /** iOS: `loadMoreEntityDetailIfNeeded(nav:currentItemId:)`. */
    suspend fun loadMoreIfNeeded(currentItemId: String) {
        if (!usesLibraryItemFilter) return
        val s = _state.value
        if (!CatalogLogic.shouldPrefetchNextPage(currentItemId, s.books) { it.id }) return
        if (s.books.size >= s.total || s.loading) return
        val gen = generation
        _state.value = s.copy(loading = true)
        try {
            loadViaLibraryFilter(reset = false, gen = gen)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        } finally {
            if (gen == generation) _state.value = _state.value.copy(loading = false)
        }
    }
}
