package de.letzgo.abstand.store

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsItemsInProgressPayload
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsLibraryAuthorListItem
import de.letzgo.abstand.data.AbsLibraryCollectionListItem
import de.letzgo.abstand.data.AbsLibrarySeriesListItem
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfSection
import de.letzgo.abstand.data.swiftTrim
import java.text.Collator
import java.util.Locale

/** iOS: Tupel `(items, total, nextPage)` der Listen-Fetches. */
data class LocalPagedList<T>(val items: List<T>, val total: Int, val nextPage: Int)

/** iOS: Tupel `(items, total, pagingFromRecentAPI)` von `podcastEpisodes`. */
data class LocalPodcastEpisodeList(val items: List<AbsPodcastEpisodeListItem>, val total: Int, val pagingFromRecentAPI: Boolean)

/** iOS: Tupel `(reading, series)` der eBook-Continue-Regale. */
data class LocalEbookContinueShelves(val reading: List<AbsBook>, val series: List<AbsBook>)

/** iOS: Tupel `(narrators, coverMap)`. */
data class LocalNarratorList(val narrators: List<de.letzgo.abstand.data.AbsLibraryNarratorListItem>, val coverMap: Map<String, String>)

/** iOS: Tupel `(hasEbook, hasSupplementary)`. */
data class LocalBookEbookFlags(val hasEbook: Boolean, val hasSupplementary: Boolean)

/**
 * iOS: `LocalLibraryQueries` — reine Lesefunktionen. iOS nutzt sie auch synchron auf dem
 * Main-`ModelContext`; Room erlaubt keine Main-Thread-Queries, deshalb hier alles `suspend`
 * (Aufrufer: [LocalLibraryStore] bzw. Stores über `currentLocalLibraryStore()`).
 */
object LocalLibraryQueries {
    /** SQLite-Variablenlimit älterer Android-Versionen (999) — `IN (:ids)` stückeln. */
    private const val IN_CHUNK = 900

    /** `ceil(count / pageLimit)` — Folgeseite nach `count` gecachten Einträgen. */
    fun nextPage(count: Int, pageLimit: Int): Int = if (pageLimit <= 0) 0 else (count + pageLimit - 1) / pageLimit

    internal suspend fun bookRows(dao: LocalLibraryDao, ids: Collection<String>): List<LocalBook> {
        if (ids.isEmpty()) return emptyList()
        return ids.distinct().chunked(IN_CHUNK).flatMap { dao.books(it) }
    }

    /** Bücher zu IDs aus der geteilten [LocalBook]-Tabelle (für Serien/Sammlungen/Shows). */
    internal suspend fun booksById(dao: LocalLibraryDao, ids: Collection<String>): Map<String, AbsBook> {
        val result = HashMap<String, AbsBook>()
        for (row in bookRows(dao, ids)) row.toAbsBook()?.let { result[row.id] = it }
        return result
    }

    suspend fun catalog(
        dao: LocalLibraryDao, libraryId: String, sortField: String, ascending: Boolean, filterKey: String?, pageLimit: Int,
    ): LocalPagedList<AbsBook>? {
        val state = dao.catalogListState(libraryId) ?: return null
        if (state.sortField != sortField || state.ascending != ascending || state.filterKey != filterKey) return null
        val entries = dao.catalogEntries(libraryId)
        if (entries.isEmpty()) return null
        val rowsById = bookRows(dao, entries.map { it.bookId }).associateBy { it.id }
        val items = entries.mapNotNull { rowsById[it.bookId]?.toAbsBook() }
        if (items.isEmpty()) return null
        return LocalPagedList(items, state.total, nextPage(entries.size, pageLimit))
    }

    suspend fun book(dao: LocalLibraryDao, id: String): AbsBook? = dao.book(id)?.toAbsBook()

    /** Persistierte Katalog-eBook-Flags — Filter/Badge ohne Heuristik. */
    suspend fun bookCatalogEbookFlags(dao: LocalLibraryDao, id: String): LocalBookEbookFlags? =
        dao.book(id)?.let { LocalBookEbookFlags(it.catalogHasEbook, it.catalogHasSupplementaryEbook) }

    /** Reine eBooks im Browse-Tab (`catalogHasEbook`, nicht supplementär). */
    suspend fun browsePureEbooks(dao: LocalLibraryDao, libraryId: String): List<AbsBook> = decodeLocalBookRows(dao.pureEbookRows(libraryId))

    /** Hörbücher mit supplementärem eBook im Browse-Tab. */
    suspend fun browseSupplementaryEbooks(dao: LocalLibraryDao, libraryId: String): List<AbsBook> =
        decodeLocalBookRows(dao.supplementaryEbookRows(libraryId))

    /** Detail-Blob bevorzugt; gleiche IDs zusammenführen (reichere Listen-Metadaten gewinnen). Reihenfolge bleibt. */
    private fun decodeLocalBookRows(rows: List<LocalBook>): List<AbsBook> {
        val byId = LinkedHashMap<String, AbsBook>()
        for (row in rows) {
            val book = row.toAbsBookDetail() ?: row.toAbsBook() ?: continue
            val existing = byId[book.id]
            byId[book.id] = existing?.let { book.preferringRicherListMetadata(it) } ?: book
        }
        return byId.values.toList()
    }

    /** Offline eBook-Katalogfilter — alte Browse-Logik (rein: `isUsableEbookListRow`, supplementär: `isPlayableAudiobook`). */
    suspend fun ebookCatalogBooks(dao: LocalLibraryDao, libraryId: String): List<AbsBook> {
        val byId = LinkedHashMap<String, AbsBook>()
        for (row in dao.booksInLibrary(libraryId)) {
            val stub = row.toAbsBook()
            val detail = row.toAbsBookDetail()
            val candidate: AbsBook? = when {
                row.catalogHasEbook && (stub ?: detail) != null -> stub ?: detail
                stub != null && stub.isUsableEbookListRow && !stub.isPlayableAudiobook -> stub
                else -> (stub ?: detail)?.takeIf {
                    it.isPlayableAudiobook && (row.catalogHasSupplementaryEbook || it.isCatalogSupplementaryEbook)
                }
            }
            val book = candidate ?: continue
            val existing = byId[book.id]
            byId[book.id] = existing?.let { book.preferringRicherListMetadata(it) } ?: book
        }
        val collator = localizedStandardCollator()
        return byId.values.sortedWith { a, b -> collator.compare(a.displayTitle, b.displayTitle) }
    }

    /** Erweiterte Detail-Kopie, falls schon einmal per `?expanded=1` geladen. */
    suspend fun bookDetail(dao: LocalLibraryDao, id: String): AbsBook? = dao.book(id)?.toAbsBookDetail()

    /**
     * Voller lokaler Katalog aus [LocalBook] (Superset). [sortField] = `CatalogSortField.rawValue`;
     * nicht lokal abbildbare Felder fallen auf Titel zurück (siehe [supportsLocalBookSort]).
     */
    suspend fun allBooks(dao: LocalLibraryDao, libraryId: String, sortField: String, descending: Boolean): List<AbsBook> {
        val rows = dao.booksInLibrary(libraryId)
        return decodeLocalBookRows(sortLocalBookRows(rows, sortField, descending))
    }

    /** `true`, wenn das Sortierfeld direkt auf [LocalBook] liegt (iOS: `supportsLocalBookSort`). */
    fun supportsLocalBookSort(sortField: String): Boolean =
        sortField in setOf("title", "authorName", "authorNameLF", "addedAt", "duration")

    /** Primär nach Feld, dann Titel + ID als Tiebreaker (sonst springt die Liste bei gleichen Werten). */
    internal fun sortLocalBookRows(rows: List<LocalBook>, sortField: String, descending: Boolean): List<LocalBook> {
        val primary: Comparator<LocalBook> = when (sortField) {
            "authorName", "authorNameLF" -> compareBy { it.authorName }
            "addedAt" -> compareBy(nullsFirst()) { it.addedAt }
            "duration" -> compareBy { it.duration }
            else -> compareBy { it.title }
        }
        val ordered = if (descending) primary.reversed() else primary
        return rows.sortedWith(ordered.thenBy { it.title }.thenBy { it.id })
    }

    suspend fun series(dao: LocalLibraryDao, libraryId: String, sortField: String, descending: Boolean): LocalPagedList<AbsLibrarySeriesListItem>? {
        val state = dao.seriesListState(libraryId) ?: return null
        if (state.sortField != sortField || state.descending != descending) return null
        val rows = dao.series(libraryId)
        if (rows.isEmpty()) return null
        val books = booksById(dao, rows.flatMap { it.bookIds }.toSet())
        val items = rows.map { it.toItem(books) }
        return LocalPagedList(items, state.total, nextPage(items.size, 40))
    }

    suspend fun authors(dao: LocalLibraryDao, libraryId: String, sortField: String, descending: Boolean): LocalPagedList<AbsLibraryAuthorListItem>? {
        val state = dao.authorListState(libraryId) ?: return null
        if (state.sortField != sortField || state.descending != descending) return null
        val rows = dao.authors(libraryId)
        if (rows.isEmpty()) return null
        val items = rows.map { it.toItem() }
        return LocalPagedList(items, state.total, nextPage(items.size, 50))
    }

    suspend fun collections(dao: LocalLibraryDao, libraryId: String): Pair<List<AbsLibraryCollectionListItem>, Int>? {
        val state = dao.collectionListState(libraryId) ?: return null
        val rows = dao.collections(libraryId)
        if (rows.isEmpty()) return null
        val books = booksById(dao, rows.flatMap { it.bookIds }.toSet())
        return rows.map { it.toItem(books) } to state.total
    }

    suspend fun podcastEpisodes(dao: LocalLibraryDao, libraryId: String): LocalPodcastEpisodeList? {
        val state = dao.podcastEpisodeListState(libraryId) ?: return null
        val rows = dao.podcastEpisodes(libraryId)
        if (rows.isEmpty()) return null
        return LocalPodcastEpisodeList(rows.map { it.toItem() }, state.total, state.pagingFromRecentAPI)
    }

    /** Einzelne Folge über ihren `progressLookupKey` — Pendant zu [book]. */
    suspend fun podcastEpisode(dao: LocalLibraryDao, progressLookupKey: String): AbsPodcastEpisodeListItem? =
        dao.podcastEpisode(progressLookupKey)?.toItem()

    suspend fun podcastShows(dao: LocalLibraryDao, libraryId: String, sortField: String, ascending: Boolean): List<AbsBook>? {
        val state = dao.podcastShowListState(libraryId) ?: return null
        if (state.sortField != sortField || state.ascending != ascending) return null
        val entries = dao.podcastShowEntries(libraryId)
        if (entries.isEmpty()) return null
        val books = booksById(dao, entries.map { it.bookId })
        return entries.mapNotNull { books[it.bookId] }.ifEmpty { null }
    }

    suspend fun homeShelves(dao: LocalLibraryDao, libraryId: String): List<AbsStartShelfSection>? = dao.homeShelves(libraryId)?.toSections()

    suspend fun ebookContinueEntries(dao: LocalLibraryDao, libraryId: String): LocalEbookContinueShelves? {
        val rows = dao.ebookContinueEntries(libraryId)
        if (rows.isEmpty()) return null
        val books = booksById(dao, rows.map { it.bookId })
        val reading = rows.filter { it.kind == LocalEbookContinueEntry.KIND_READING }.mapNotNull { books[it.bookId] }
        val series = rows.filter { it.kind == LocalEbookContinueEntry.KIND_SERIES }.mapNotNull { books[it.bookId] }
        if (reading.isEmpty() && series.isEmpty()) return null
        return LocalEbookContinueShelves(reading, series)
    }

    /**
     * Ersetzt den `items-in-progress`-Snapshot: Top-[limit] [LocalProgress]-Zeilen nach `lastUpdate`,
     * gejoint mit [LocalBook]/[LocalPodcastEpisode].
     */
    suspend fun itemsInProgressPayload(dao: LocalLibraryDao, limit: Int): AbsItemsInProgressPayload? {
        val rows = dao.recentProgress(limit)
        if (rows.isEmpty()) return null
        val bookRows = rows.filter { (it.episodeId ?: "").swiftTrim().isEmpty() }
        val episodeRows = rows.filter { (it.episodeId ?: "").swiftTrim().isNotEmpty() }
        val books = booksById(dao, bookRows.map { it.libraryItemId })
        val episodesByKey = if (episodeRows.isEmpty()) emptyMap() else
            episodeRows.map { it.progressLookupKey }.chunked(IN_CHUNK).flatMap { dao.podcastEpisodes(it) }
                .associate { it.progressLookupKey to it.toItem() }
        val outBooks = ArrayList<AbsBook>()
        val outEpisodes = ArrayList<AbsPodcastEpisodeListItem>()
        for (row in rows) {
            if ((row.episodeId ?: "").swiftTrim().isEmpty()) {
                books[row.libraryItemId]?.let(outBooks::add)
            } else {
                episodesByKey[row.progressLookupKey]?.let(outEpisodes::add)
            }
        }
        if (outBooks.isEmpty() && outEpisodes.isEmpty()) return null
        return AbsItemsInProgressPayload(books = outBooks, podcastEpisodes = outEpisodes)
    }

    /** iOS: `achievementsSnapshot` — Android liefert die Rohzeilen (Kind als String); `null` ohne Zeilen. */
    suspend fun achievementStates(dao: LocalLibraryDao): List<LocalAchievementState>? = dao.achievementStates().ifEmpty { null }

    suspend fun libraries(dao: LocalLibraryDao): List<AbsLibrary>? = dao.librariesSnapshot()?.toLibraries()

    suspend fun authorDescription(dao: LocalLibraryDao, authorId: String): String? {
        val aid = authorId.swiftTrim()
        if (aid.isEmpty()) return null
        return dao.authorDetail(aid)?.authorDescription?.swiftTrim()?.ifEmpty { null }
    }

    suspend fun listeningSessions(dao: LocalLibraryDao, libraryItemId: String, episodeId: String?): List<AbsListeningSession>? =
        dao.listeningSessions(LocalListeningSessionsSnapshot.makeKey(libraryItemId, episodeId))?.toSessions()

    suspend fun podcastRssFeedRaw(dao: LocalLibraryDao, showId: String): ByteArray? {
        val sid = showId.swiftTrim()
        if (sid.isEmpty()) return null
        return dao.podcastRssFeed(sid)?.blob
    }

    /** iOS: `localizedStandardCompare` (Finder-Sortierung, Groß-/Kleinschreibung egal). */
    fun localizedStandardCollator(): Collator = Collator.getInstance(Locale.getDefault()).apply { strength = Collator.SECONDARY }
}
