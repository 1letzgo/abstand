package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsSearchAuthorRow
import de.letzgo.abstand.data.AbsSearchNamedCount
import de.letzgo.abstand.data.AbsSearchNarratorRow
import de.letzgo.abstand.data.AbsSearchResponse
import de.letzgo.abstand.data.AbsSearchSeriesRow
import de.letzgo.abstand.data.localizedCaseInsensitiveCompare
import de.letzgo.abstand.data.swiftTrim

/**
 * Ergebnis der einheitlichen Suche (iOS: `searchBooks`/`searchAuthors`/`searchNarrators`/
 * `searchSeries`/`searchTags`/`searchGenres` + `podcastLibrarySearchShows`/`…Episodes`).
 */
data class SearchResults(
    val books: List<AbsBook> = emptyList(),
    val authors: List<AbsSearchAuthorRow> = emptyList(),
    val series: List<AbsSearchSeriesRow> = emptyList(),
    val narrators: List<AbsSearchNarratorRow> = emptyList(),
    val tags: List<AbsSearchNamedCount> = emptyList(),
    val genres: List<AbsSearchNamedCount> = emptyList(),
    val podcastShows: List<AbsBook> = emptyList(),
    val podcastEpisodes: List<AbsPodcastEpisodeListItem> = emptyList(),
) {
    /** iOS: `hasAnyResults`. */
    val hasAnyResults: Boolean
        get() = books.isNotEmpty() || authors.isNotEmpty() || narrators.isNotEmpty() || series.isNotEmpty() ||
            tags.isNotEmpty() || genres.isNotEmpty() || podcastShows.isNotEmpty() || podcastEpisodes.isNotEmpty()

    val hasBookSideResults: Boolean
        get() = books.isNotEmpty() || authors.isNotEmpty() || narrators.isNotEmpty() || series.isNotEmpty()
}

/** Was der Such-Tab über den Ergebnissen zeigt (iOS: `searchStatusMessage`). */
enum class SearchStatus { Prompt, TooShort, Loading, NoResults, Results }

/** Sektionen in iOS-Reihenfolge (`BooksSearchBrowseView` + `PodcastLibrarySearchResultsView`). */
enum class SearchSection(val title: String) {
    Books("Books"), Authors("Authors"), Series("Series"), Narrators("Narrators"), Tags("Tags"), Genres("Genres"),
    Shows("Shows"), Episodes("Episodes"),
}

/** Reine Such-Logik (Gruppierung, Mehrbibliotheks-Merge, lokale Treffer) — JUnit-testbar. */
object SearchLogic {
    /** iOS: Suche erst ab drei Zeichen. */
    const val minQueryLength = 3

    /** iOS: Debounce `Task.sleep(350 ms)`. */
    const val debounceMillis = 350L

    fun normalizedQuery(raw: String): String = raw.swiftTrim()

    /** iOS: `searchStatusMessage`. */
    fun status(rawQuery: String, isSearching: Boolean, results: SearchResults): SearchStatus {
        val q = normalizedQuery(rawQuery)
        return when {
            q.isEmpty() -> SearchStatus.Prompt
            q.length < minQueryLength -> SearchStatus.TooShort
            isSearching && !results.hasAnyResults -> SearchStatus.Loading
            !results.hasAnyResults -> SearchStatus.NoResults
            else -> SearchStatus.Results
        }
    }

    /** Sichtbare Sektionen (leere fallen weg, Podcast-Sektionen nur mit Podcast-Bibliothek, iOS: `showPodcastsTab`). */
    fun visibleSections(results: SearchResults, showPodcasts: Boolean): List<SearchSection> = buildList {
        if (results.books.isNotEmpty()) add(SearchSection.Books)
        if (results.authors.isNotEmpty()) add(SearchSection.Authors)
        if (results.series.isNotEmpty()) add(SearchSection.Series)
        if (results.narrators.isNotEmpty()) add(SearchSection.Narrators)
        if (results.tags.isNotEmpty()) add(SearchSection.Tags)
        if (results.genres.isNotEmpty()) add(SearchSection.Genres)
        if (showPodcasts && results.podcastShows.isNotEmpty()) add(SearchSection.Shows)
        if (showPodcasts && results.podcastEpisodes.isNotEmpty()) add(SearchSection.Episodes)
    }

    /**
     * Buch-Seite mehrerer Books-Bibliotheken zusammenführen (iOS sucht nur in `booksCatalogLibrary`;
     * Android durchsucht alle aktiven). Reihenfolge der ersten Fundstelle, Zählwerte addiert.
     */
    fun mergeBookResponses(responses: List<AbsSearchResponse>): SearchResults {
        val books = LinkedHashMap<String, AbsBook>()
        val authors = LinkedHashMap<String, AbsSearchAuthorRow>()
        val series = LinkedHashMap<String, AbsSearchSeriesRow>()
        val narrators = LinkedHashMap<String, AbsSearchNarratorRow>()
        val tags = LinkedHashMap<String, AbsSearchNamedCount>()
        val genres = LinkedHashMap<String, AbsSearchNamedCount>()
        for (res in responses) {
            res.bookSearchLibraryItems().forEach { b -> books[b.id] = books[b.id]?.preferringRicherListMetadata(b) ?: b }
            res.authors.forEach { a ->
                authors[a.id] = authors[a.id]?.let { it.copy(numBooks = sumCounts(it.numBooks, a.numBooks)) } ?: a
            }
            res.series.forEach { s ->
                series[s.id] = series[s.id]?.let { it.copy(books = mergeBooks(it.books, s.books)) } ?: s
            }
            res.narrators.forEach { n ->
                narrators[n.name] = narrators[n.name]?.let { it.copy(numBooks = sumCounts(it.numBooks, n.numBooks)) } ?: n
            }
            res.tags.forEach { t -> tags[t.name] = tags[t.name]?.let { it.copy(numItems = sumCounts(it.numItems, t.numItems)) } ?: t }
            res.genres.forEach { g -> genres[g.name] = genres[g.name]?.let { it.copy(numItems = sumCounts(it.numItems, g.numItems)) } ?: g }
        }
        return SearchResults(
            books = books.values.toList(),
            authors = authors.values.toList(),
            series = series.values.toList(),
            narrators = narrators.values.toList(),
            tags = tags.values.toList(),
            genres = genres.values.toList(),
        )
    }

    /**
     * Podcast-Seite (iOS: `podcastSearchShowLibraryItems()` + `mergedPodcastLibrarySearchEpisodes`):
     * Shows ohne Dubletten, Folgen dedupliziert und nach Titel sortiert.
     */
    fun mergePodcastResponses(responses: List<AbsSearchResponse>, localEpisodes: List<AbsPodcastEpisodeListItem> = emptyList()): Pair<List<AbsBook>, List<AbsPodcastEpisodeListItem>> {
        val shows = LinkedHashMap<String, AbsBook>()
        responses.forEach { res -> res.podcastSearchShowLibraryItems().forEach { if (it.id !in shows) shows[it.id] = it } }
        val episodes = AbsPodcastEpisodeListItem.dedupeRows(responses.flatMap { it.podcastEpisodeMatches } + localEpisodes)
            .sortedWith { a, b -> localizedCaseInsensitiveCompare(a.episodeTitle, b.episodeTitle) }
        return shows.values.toList() to episodes
    }

    /** iOS: `bookMatchesSearchQuery` — Titel, Autorzeile oder Serienname enthält die Suche. */
    fun bookMatches(book: AbsBook, query: String): Boolean {
        val q = query.lowercase()
        if (q.isEmpty()) return false
        if (book.displayTitle.lowercase().contains(q)) return true
        if (book.displayAuthorsCardLine.lowercase().contains(q)) return true
        return book.media.metadata.series.orEmpty().any { it.name.lowercase().contains(q) }
    }

    /** iOS: `localPodcastEpisodesMatchingSearch` — Folgentitel + Sendung. */
    fun episodeMatches(episode: AbsPodcastEpisodeListItem, query: String): Boolean {
        val q = query.lowercase()
        if (q.isEmpty()) return false
        return "${episode.episodeTitle} ${episode.showTitle}".lowercase().contains(q)
    }

    /**
     * iOS: `applyLocalSearchResults` — sofortige Treffer aus der lokalen DB, alphabetisch
     * (`localizedStandardCompare`), bevor der Server antwortet.
     */
    fun localResults(
        query: String,
        books: List<AbsBook>,
        shows: List<AbsBook> = emptyList(),
        episodes: List<AbsPodcastEpisodeListItem> = emptyList(),
    ): SearchResults {
        val q = normalizedQuery(query)
        if (q.length < minQueryLength) return SearchResults()
        fun dedupeSorted(list: List<AbsBook>): List<AbsBook> {
            val byId = LinkedHashMap<String, AbsBook>()
            list.filter { bookMatches(it, q) }.forEach { b -> byId[b.id] = byId[b.id]?.preferringRicherListMetadata(b) ?: b }
            return byId.values.sortedWith { a, b -> localizedCaseInsensitiveCompare(a.displayTitle, b.displayTitle) }
        }
        return SearchResults(
            books = dedupeSorted(books.filter { it.isUsableLibraryCatalogRow }),
            podcastShows = dedupeSorted(shows),
            podcastEpisodes = AbsPodcastEpisodeListItem.dedupeRows(episodes.filter { episodeMatches(it, q) })
                .sortedWith { a, b -> localizedCaseInsensitiveCompare(a.episodeTitle, b.episodeTitle) },
        )
    }

    private fun sumCounts(a: Int?, b: Int?): Int? = if (a == null && b == null) null else (a ?: 0) + (b ?: 0)

    private fun mergeBooks(a: List<AbsBook>?, b: List<AbsBook>?): List<AbsBook>? {
        if (a == null) return b
        if (b == null) return a
        val seen = HashSet<String>()
        return (a + b).filter { seen.add(it.id) }
    }
}
