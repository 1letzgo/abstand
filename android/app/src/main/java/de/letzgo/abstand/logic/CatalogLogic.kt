package de.letzgo.abstand.logic

import de.letzgo.abstand.data.AbsAuthorDetail
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsLibraryAuthorListItem
import de.letzgo.abstand.data.AbsLibraryCollectionListItem
import de.letzgo.abstand.data.AbsLibraryNarratorListItem
import de.letzgo.abstand.data.BooksBrowseGenreListItem
import de.letzgo.abstand.data.BooksBrowseTagListItem
import de.letzgo.abstand.data.EntityDetailAuthorSeriesSection
import de.letzgo.abstand.data.swiftTrim
import java.text.Collator
import java.util.Base64
import java.util.Locale

// Reine Katalog-Logik aus iOS `AppModel.swift` (Katalog-/Browse-/Entity-Detail-Teile) — ohne
// Zustand, damit sie per JUnit prüfbar ist. Der Zustand selbst liegt in `model/CatalogStore`.

/** iOS: `localizedCaseInsensitiveCompare` (Groß/Klein egal, Akzente zählen). */
internal fun caseInsensitiveCollator(): Collator =
    Collator.getInstance(Locale.getDefault()).apply { strength = Collator.SECONDARY }

/** iOS: `localizedCaseInsensitiveCompare(…) == .orderedSame`. */
internal fun String.equalsLocalizedCaseInsensitive(other: String): Boolean =
    caseInsensitiveCollator().compare(this, other) == 0

/** iOS: `localizedCaseInsensitiveContains`. */
internal fun String.containsLocalizedCaseInsensitive(other: String): Boolean =
    FoundationText.foldCaseAndDiacritics(this).contains(FoundationText.foldCaseAndDiacritics(other)) ||
        lowercase(Locale.getDefault()).contains(other.lowercase(Locale.getDefault()))

object CatalogLogic {
    /** iOS: `AppModel.libraryCatalogPageLimit`. */
    const val LIBRARY_CATALOG_PAGE_LIMIT = 80

    /** iOS: `catalogPrefetchItemsFromEnd`. */
    const val CATALOG_PREFETCH_ITEMS_FROM_END = 12

    /** iOS: `browseFacetNetworkConcurrency`. */
    const val BROWSE_FACET_NETWORK_CONCURRENCY = 4

    /** iOS: `catalogStaleRefreshInterval` (15 min). */
    const val CATALOG_STALE_REFRESH_INTERVAL_MS = 15 * 60 * 1000L

    /** iOS: `AppModel.catalogFilterKey(group:value:)` — `gruppe.<base64(wert)>`. */
    fun catalogFilterKey(group: String, value: String): String =
        "$group.${Base64.getEncoder().encodeToString(value.toByteArray(Charsets.UTF_8))}"

    // MARK: - Sortierung (Persistenz + Legacy-Migration)

    /**
     * iOS: `loadCatalogSortState` — Mapping des alten `abstand_catalog_items_sort`-Werts auf
     * (Feld, absteigend). `null` = unbekannter Wert (dann gilt das gespeicherte Feld).
     */
    fun migrateLegacyCatalogSort(legacy: String): Pair<CatalogSortField, Boolean>? = when (legacy) {
        "titleAsc" -> CatalogSortField.TITLE to false
        "titleDesc" -> CatalogSortField.TITLE to true
        "authorNameAsc" -> CatalogSortField.AUTHOR_NAME to false
        "authorNameDesc" -> CatalogSortField.AUTHOR_NAME to true
        "authorNameLFAsc" -> CatalogSortField.AUTHOR_NAME_LF to false
        "authorNameLFDesc" -> CatalogSortField.AUTHOR_NAME_LF to true
        "addedAtNewest" -> CatalogSortField.ADDED_AT to true
        "addedAtOldest" -> CatalogSortField.ADDED_AT to false
        "publishedYearNewest" -> CatalogSortField.PUBLISHED_YEAR to true
        "publishedYearOldest" -> CatalogSortField.PUBLISHED_YEAR to false
        "durationLongest" -> CatalogSortField.DURATION to true
        "durationShortest" -> CatalogSortField.DURATION to false
        "sizeLargest" -> CatalogSortField.SIZE to true
        "sizeSmallest" -> CatalogSortField.SIZE to false
        "birthtimeNewest" -> CatalogSortField.BIRTHTIME_MS to true
        "birthtimeOldest" -> CatalogSortField.BIRTHTIME_MS to false
        "mtimeNewest" -> CatalogSortField.MTIME_MS to true
        "mtimeOldest" -> CatalogSortField.MTIME_MS to false
        "progressUpdated" -> CatalogSortField.PROGRESS to true
        "progressCreated" -> CatalogSortField.PROGRESS_CREATED_AT to true
        "progressFinished" -> CatalogSortField.PROGRESS_FINISHED_AT to true
        "randomOrder" -> CatalogSortField.RANDOM to false
        else -> null
    }

    /**
     * iOS: `loadCatalogSortState` vollständig — [legacy] (alter Key) hat Vorrang und wird von
     * [persist] migriert, sonst [storedField]/[storedDescending]. Unbekanntes Feld → Titel.
     */
    fun resolveCatalogSortState(
        legacy: String?,
        storedField: String?,
        storedDescending: Boolean,
        persist: (CatalogSortField, Boolean) -> Unit = { _, _ -> },
    ): Pair<CatalogSortField, Boolean> {
        if (!legacy.isNullOrEmpty()) {
            migrateLegacyCatalogSort(legacy)?.let { (field, desc) ->
                persist(field, desc)
                return field to desc
            }
        }
        return (CatalogSortField.fromRaw(storedField) ?: CatalogSortField.TITLE) to storedDescending
    }

    /** iOS: `catalogSortField == .random ? true : !catalogSortDescending`. */
    fun catalogAscending(field: CatalogSortField, descending: Boolean): Boolean =
        if (field == CatalogSortField.RANDOM) true else !descending

    /** iOS: `browseSeriesAPIDescending`. */
    fun seriesApiDescending(field: BooksBrowseSeriesSortField, descending: Boolean): Boolean =
        if (field == BooksBrowseSeriesSortField.RANDOM) false else descending

    /** iOS: `browseEbooksSortKey` — Zufall nie absteigend. */
    fun ebooksSortKey(field: CatalogSortField, descending: Boolean): Pair<String, Boolean> =
        field.apiSortParameter to (if (field == CatalogSortField.RANDOM) false else descending)

    // MARK: - Paging

    /** iOS: `shouldPrefetchNextCatalogPage` — Zeile im letzten [fromEnd]-Fenster? */
    fun <T> shouldPrefetchNextPage(
        currentItemId: String?,
        items: List<T>,
        fromEnd: Int = CATALOG_PREFETCH_ITEMS_FROM_END,
        id: (T) -> String,
    ): Boolean {
        if (currentItemId == null || items.isEmpty()) return false
        val idx = items.indexOfFirst { id(it) == currentItemId }
        if (idx < 0) return false
        return idx >= maxOf(0, items.size - fromEnd)
    }

    /**
     * iOS: `mergeServerFirstPageIntoLocalBooksPreservingRest` — stiller Refresh ersetzt nur die
     * ersten `page.size` Positionen; Dubletten fliegen aus dem hinteren Teil. Rückgabe: neue
     * Liste (oder `null` = unverändert) und neues Total.
     */
    fun mergeFirstPagePreservingRest(current: List<AbsBook>, page: List<AbsBook>, total: Int): Pair<List<AbsBook>?, Int> {
        if (page.isEmpty()) return null to maxOf(current.size, total)
        val pageIds = page.mapTo(HashSet()) { it.id }
        val rest = if (current.size > page.size) current.subList(page.size, current.size).filter { it.id !in pageIds } else emptyList()
        val merged = page + rest
        val unchanged = merged.size == current.size && merged.zip(current).all { (a, b) -> a.id == b.id && a.updatedAt == b.updatedAt }
        return (if (unchanged) null else merged) to maxOf(merged.size, total)
    }

    /** iOS: Reset-Zweig in `reloadLibrary` — gleiche IDs/`updatedAt` → Liste nicht ersetzen. */
    fun sameIdsAndUpdatedAt(a: List<AbsBook>, b: List<AbsBook>): Boolean =
        a.size == b.size && a.zip(b).all { (x, y) -> x.id == y.id && x.updatedAt == y.updatedAt }

    /** iOS: Ende-Kriterium `hasMoreBrowseEbookPages`. */
    fun hasMorePages(total: Int, nextPage: Int, pageLimit: Int = LIBRARY_CATALOG_PAGE_LIMIT): Boolean =
        total > 0 && nextPage * pageLimit < total

    // MARK: - Facetten sortieren (lokal)

    private fun <T> sortByNameOrCount(
        rows: List<T>,
        byCount: Boolean,
        descending: Boolean,
        name: (T) -> String,
        count: (T) -> Long,
    ): List<T> {
        val collator = caseInsensitiveCollator()
        val byName = Comparator<T> { a, b -> collator.compare(name(a), name(b)) }
        if (!byCount) return rows.sortedWith(if (descending) byName.reversed() else byName)
        return rows.sortedWith { a, b ->
            val ca = count(a)
            val cb = count(b)
            if (ca == cb) byName.compare(a, b) else if (descending) cb.compareTo(ca) else ca.compareTo(cb)
        }
    }

    /** iOS: `sortedBrowseGenres`. */
    fun sortedGenres(rows: List<BooksBrowseGenreListItem>, field: BooksBrowseFacetSortField, descending: Boolean) =
        sortByNameOrCount(rows, field == BooksBrowseFacetSortField.BOOK_COUNT, descending, { it.name }, { (it.numBooks ?: 0).toLong() })

    /** iOS: `sortedBrowseTags`. */
    fun sortedTags(rows: List<BooksBrowseTagListItem>, field: BooksBrowseFacetSortField, descending: Boolean) =
        sortByNameOrCount(rows, field == BooksBrowseFacetSortField.BOOK_COUNT, descending, { it.name }, { (it.numBooks ?: 0).toLong() })

    /** iOS: `sortedBrowseNarrators`. */
    fun sortedNarrators(rows: List<AbsLibraryNarratorListItem>, field: BooksBrowseNarratorsSortField, descending: Boolean) =
        sortByNameOrCount(rows, field == BooksBrowseNarratorsSortField.NUM_BOOKS, descending, { it.name }, { (it.numBooks ?: 0).toLong() })

    /** iOS: `sortedBrowseCollections` (Zeitstempel als Sekunden → für den Vergleich in ms). */
    fun sortedCollections(rows: List<AbsLibraryCollectionListItem>, field: BooksBrowseCollectionsSortField, descending: Boolean) =
        when (field) {
            BooksBrowseCollectionsSortField.NAME -> sortByNameOrCount(rows, false, descending, { it.name }, { 0 })
            BooksBrowseCollectionsSortField.BOOK_COUNT ->
                sortByNameOrCount(rows, true, descending, { it.name }, { (it.books?.size ?: 0).toLong() })
            BooksBrowseCollectionsSortField.CREATED_AT ->
                sortByNameOrCount(rows, true, descending, { it.name }, { ((it.createdAt ?: 0.0) * 1000).toLong() })
            BooksBrowseCollectionsSortField.LAST_UPDATE ->
                sortByNameOrCount(rows, true, descending, { it.name }, { ((it.lastUpdate ?: 0.0) * 1000).toLong() })
        }

    // MARK: - Offline-Aggregation aus Downloads

    /** iOS: `applyOfflineBrowseGenres` (Reihenfolge der Map egal — der Aufrufer sortiert). */
    fun offlineGenres(books: List<AbsBook>): List<BooksBrowseGenreListItem> {
        val counts = LinkedHashMap<String, Int>()
        for (b in books) for (g in b.media.metadata.genres.orEmpty()) {
            val n = g.swiftTrim()
            if (n.isNotEmpty()) counts[n] = (counts[n] ?: 0) + 1
        }
        return counts.map { BooksBrowseGenreListItem(it.key, it.value) }
    }

    /** iOS: `applyOfflineBrowseTags`. */
    fun offlineTags(books: List<AbsBook>): List<BooksBrowseTagListItem> {
        val counts = LinkedHashMap<String, Int>()
        for (b in books) for (t in b.media.tags.orEmpty()) {
            val n = t.swiftTrim()
            if (n.isNotEmpty()) counts[n] = (counts[n] ?: 0) + 1
        }
        return counts.map { BooksBrowseTagListItem(it.key, it.value) }
    }

    /** iOS: `applyOfflineBrowseAuthors` — Schlüssel Autor-ID, sonst `name:<klein>`; nach Name sortiert. */
    fun offlineAuthors(books: List<AbsBook>): List<AbsLibraryAuthorListItem> {
        val byKey = LinkedHashMap<String, Pair<String, Int>>()
        for (b in books) for (a in b.media.metadata.authors.orEmpty()) {
            val name = a.name.swiftTrim()
            if (name.isEmpty()) continue
            val id = a.id.swiftTrim()
            val key = if (id.isEmpty()) "name:${name.lowercase()}" else id
            val prev = byKey[key]
            byKey[key] = (prev?.first ?: name) to ((prev?.second ?: 0) + 1)
        }
        val collator = caseInsensitiveCollator()
        return byKey.map { (k, v) -> AbsLibraryAuthorListItem(k, v.first, v.second, null) }
            .sortedWith { x, y -> collator.compare(x.name, y.name) }
    }

    /** iOS: `applyOfflineBrowseNarrators`. */
    fun offlineNarrators(books: List<AbsBook>): List<AbsLibraryNarratorListItem> {
        val counts = LinkedHashMap<String, Int>()
        for (b in books) for (n in b.media.metadata.narrators.orEmpty()) {
            val name = n.swiftTrim()
            if (name.isNotEmpty()) counts[name] = (counts[name] ?: 0) + 1
        }
        return counts.map { AbsLibraryNarratorListItem(it.key, it.key, it.value) }
    }

    // MARK: - Entity-Detail

    /** iOS: `parseSeriesSequenceNumber` — `"1"`, `"1.5"`, `"01"`, `"2a"`, `"1.0 (ebook)"`. */
    fun parseSeriesSequenceNumber(raw: String): Double? {
        val trimmed = raw.swiftTrim()
        if (trimmed.isEmpty()) return null
        trimmed.toDoubleOrNull()?.takeIf { trimmed.none { it.isLetter() } }?.let { return it }
        val num = StringBuilder()
        var sawDot = false
        for (ch in trimmed) {
            if (ch.isDigit()) {
                num.append(ch)
            } else if (ch == '.' && !sawDot && num.isNotEmpty()) {
                num.append(ch)
                sawDot = true
            } else if (num.isEmpty()) {
                continue
            } else {
                break
            }
        }
        if (num.endsWith(".")) num.setLength(num.length - 1)
        return num.toString().toDoubleOrNull()
    }

    /** iOS: `entityDetailSeriesSortKey` — (Nummer, Text); fehlende Nummer = +∞. */
    fun seriesSortKey(book: AbsBook, seriesId: String? = null, seriesName: String? = null): Pair<Double, String> {
        val all = book.media.metadata.series.orEmpty()
        val wantId = seriesId?.swiftTrim().orEmpty()
        val wantName = seriesName?.swiftTrim().orEmpty()
        val series = if (wantId.isNotEmpty() || wantName.isNotEmpty()) {
            all.firstOrNull { wantId.isNotEmpty() && it.id == wantId }
                ?: all.firstOrNull { wantName.isNotEmpty() && it.name.equalsLocalizedCaseInsensitive(wantName) }
                ?: return Double.POSITIVE_INFINITY to book.displayTitle
        } else {
            all.firstOrNull()
        } ?: return Double.POSITIVE_INFINITY to book.displayTitle
        val seq = series.sequence?.swiftTrim().orEmpty()
        parseSeriesSequenceNumber(seq)?.let { return it to seq }
        if (seq.isNotEmpty()) return Double.POSITIVE_INFINITY to seq
        return Double.POSITIVE_INFINITY to series.name
    }

    /**
     * iOS: `entityDetailSortBooksBySeriesOrder` — nur umsortieren, wenn mindestens zwei echte
     * Sequenznummern vorliegen (sonst bleibt die Server-Reihenfolge).
     */
    fun sortBooksBySeriesOrder(books: List<AbsBook>, seriesId: String? = null, seriesName: String? = null): List<AbsBook> {
        if (books.size <= 1) return books
        val keyed = books.map { b -> seriesSortKey(b, seriesId, seriesName).let { Triple(b, it.first, it.second) } }
        if (keyed.count { it.second.isFinite() } < 2) return books
        val std = LocalLibraryQueriesCollator.standard()
        return keyed.sortedWith { l, r ->
            when {
                l.second != r.second -> l.second.compareTo(r.second)
                l.third != r.third -> std.compare(l.third, r.third)
                else -> std.compare(l.first.displayTitle, r.first.displayTitle)
            }
        }.map { it.first }
    }

    /** iOS: `applyAuthorDetailBooksLayout` — Serien-Sektionen + Einzeltitel. */
    data class AuthorDetailLayout(
        val seriesSections: List<EntityDetailAuthorSeriesSection>,
        val standalone: List<AbsBook>,
        val all: List<AbsBook>,
    )

    fun authorDetailLayout(detail: AbsAuthorDetail): AuthorDetailLayout {
        val allItems = detail.libraryItems.orEmpty().filter { it.isUsableAuthorDetailRow }
        val inSeries = HashSet<String>()
        val sections = ArrayList<EntityDetailAuthorSeriesSection>()
        for (s in detail.series.orEmpty()) {
            val books = sortBooksBySeriesOrder(s.items.orEmpty().filter { it.isUsableAuthorDetailRow }, s.id, s.name)
            if (books.isEmpty()) continue
            books.mapTo(inSeries) { it.id }
            sections += EntityDetailAuthorSeriesSection(s.id, s.name, books)
        }
        val standalone = sortBooksBySeriesOrder(allItems.filter { it.id !in inSeries })
        return AuthorDetailLayout(sections, standalone, allItems)
    }

    /** iOS: `bookMatchesAuthor`. */
    fun bookMatchesAuthor(book: AbsBook, authorId: String, displayName: String): Boolean {
        val aid = authorId.swiftTrim()
        val name = displayName.swiftTrim()
        book.media.metadata.authors?.let { authors ->
            if (aid.isNotEmpty() && authors.any { it.id == aid }) return true
            if (name.isNotEmpty() && authors.any { it.name.containsLocalizedCaseInsensitive(name) }) return true
        }
        return name.isNotEmpty() && book.displayAuthorsCardLine.containsLocalizedCaseInsensitive(name)
    }

    /** iOS: `bookMatchesNarrator`. */
    fun bookMatchesNarrator(book: AbsBook, narratorName: String): Boolean {
        val want = narratorName.swiftTrim()
        if (want.isEmpty()) return false
        return book.media.metadata.narratorNamesForLibraryBrowseCoverMatch().any { it.equalsLocalizedCaseInsensitive(want) }
    }

    /** iOS: `bookMatchesGenre`. */
    fun bookMatchesGenre(book: AbsBook, genreName: String): Boolean {
        val want = genreName.swiftTrim()
        if (want.isEmpty()) return false
        return book.media.metadata.genres.orEmpty().any { it.swiftTrim().equalsLocalizedCaseInsensitive(want) }
    }

    /** iOS: `bookMatchesTag`. */
    fun bookMatchesTag(book: AbsBook, tagName: String): Boolean {
        val want = tagName.swiftTrim()
        if (want.isEmpty()) return false
        return book.media.tags.orEmpty().any { it.swiftTrim().equalsLocalizedCaseInsensitive(want) }
    }

    /** iOS: Serien-Fallback in `booksInLocalSeries` (ID gleich oder Name enthalten). */
    fun bookMatchesSeries(book: AbsBook, seriesId: String, displayName: String): Boolean {
        val sid = seriesId.swiftTrim()
        val name = displayName.swiftTrim()
        return book.media.metadata.series.orEmpty().any { s ->
            (sid.isNotEmpty() && s.id == sid) || (name.isNotEmpty() && s.name.containsLocalizedCaseInsensitive(name))
        }
    }

    /** iOS: `bookMatchesEntityDetailLibrary` — fehlende IDs gelten als passend. */
    fun bookMatchesLibrary(book: AbsBook, libraryId: String?): Boolean {
        val want = libraryId?.swiftTrim().orEmpty()
        if (want.isEmpty()) return true
        val lid = book.libraryId?.swiftTrim().orEmpty()
        if (lid.isEmpty()) return true
        return lid == want
    }

    /** iOS: `browseEntityBooksCountLine`. */
    fun booksCountLine(count: Int?): String? = count?.takeIf { it > 0 }?.toString()

    /** iOS: `bookCountLabel` im Entity-Detail. */
    fun bookCountLabel(n: Int?): String? = n?.takeIf { it > 0 }?.let { if (it == 1) "1 book" else "$it books" }

    /** iOS: `browseSeriesCoverBookIds` — bis zu [maxCount] Buch-IDs für das Multi-Cover. */
    fun seriesCoverBookIds(books: List<AbsBook>?, maxCount: Int = 4): List<String> {
        if (books.isNullOrEmpty() || maxCount <= 0) return emptyList()
        return books.asSequence().map { it.id }.filter { it.isNotEmpty() }.take(maxCount).toList()
    }

    /** iOS: `mergedLocalCatalogBooks` — reichere Listen-Metadaten gewinnen, Reihenfolge der ersten Quelle. */
    fun mergeBooksPreferringRicher(lists: List<List<AbsBook>>, include: (AbsBook) -> Boolean): List<AbsBook> {
        val byId = LinkedHashMap<String, AbsBook>()
        for (list in lists) for (b in list) {
            if (!include(b)) continue
            val existing = byId[b.id]
            byId[b.id] = existing?.let { b.preferringRicherListMetadata(it) } ?: b
        }
        return byId.values.toList()
    }
}

/** iOS: `localizedStandardCompare` (Finder-Sortierung) — gemeinsamer Kollator mit `LocalLibraryQueries`. */
internal object LocalLibraryQueriesCollator {
    fun standard(): Collator = de.letzgo.abstand.store.LocalLibraryQueries.localizedStandardCollator()
}
