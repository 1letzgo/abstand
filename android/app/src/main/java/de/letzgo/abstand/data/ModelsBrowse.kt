package de.letzgo.abstand.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive

// iOS: ABSModels.swift (Teil 3: Home-Regale, Katalog-Browse, Suche, Play-Session).

// MARK: - Start / Personalized (Home)

/** iOS: `ABSAuthorShelfEntity`. */
@Serializable(with = AbsAuthorShelfEntitySerializer::class)
data class AbsAuthorShelfEntity(val id: String, val name: String, val numBooks: Int?, val imagePath: String?) {
    val hasAuthorImage: Boolean get() = imagePath.trimmedOrEmpty().isNotEmpty()
}

object AbsAuthorShelfEntitySerializer : SwiftObjectSerializer<AbsAuthorShelfEntity>("ABSAuthorShelfEntity") {
    override fun decode(c: JObj) = AbsAuthorShelfEntity(c.string("id"), c.string("name"), c.intOrNull("numBooks"), c.stringOrNull("imagePath"))
    override fun encode(v: AbsAuthorShelfEntity) = jsonObjectOf {
        put("id", JsonPrimitive(v.id)); put("name", JsonPrimitive(v.name))
        putIfPresent("numBooks", v.numBooks); putIfPresent("imagePath", v.imagePath)
    }
}

/** iOS: `ABSStartShelfSection`. */
data class AbsStartShelfSection(
    val id: String,
    val category: String,
    val displayTitle: String,
    val books: List<AbsBook> = emptyList(),
    val podcastEpisodes: List<AbsPodcastEpisodeListItem> = emptyList(),
    val authors: List<AbsAuthorShelfEntity> = emptyList(),
    val series: List<AbsLibrarySeriesListItem> = emptyList(),
) {
    val hasBooks: Boolean get() = books.isNotEmpty()
    val hasPodcastEpisodes: Boolean get() = podcastEpisodes.isNotEmpty()
    val hasAuthors: Boolean get() = authors.isNotEmpty()
    val hasSeries: Boolean get() = series.isNotEmpty()
}

/** iOS: `ABSStartShelfMergedRow` — gemischte Zeilen für Home-Regale (Bücher + Podcast-Folgen). */
sealed class AbsStartShelfMergedRow {
    data class Book(val book: AbsBook) : AbsStartShelfMergedRow()
    data class PodcastEpisode(val episode: AbsPodcastEpisodeListItem) : AbsStartShelfMergedRow()

    val id: String
        get() = when (this) {
            is Book -> "b:${book.id}"
            is PodcastEpisode -> "p:${episode.progressLookupKey}"
        }

    private fun progressTimestamp(progress: Map<String, AbsUserMediaProgress>): Long = when (this) {
        is Book -> progress[book.id]?.lastUpdate ?: 0
        is PodcastEpisode -> progress[episode.progressLookupKey]?.lastUpdate ?: 0
    }

    companion object {
        fun merged(
            books: List<AbsBook>,
            podcastEpisodes: List<AbsPodcastEpisodeListItem>,
            progress: Map<String, AbsUserMediaProgress>,
        ): List<AbsStartShelfMergedRow> {
            val seen = HashSet<String>()
            val uniqueBooks = books.filter { seen.add(it.id) }
            val uniqueEpisodes = AbsPodcastEpisodeListItem.dedupeRows(podcastEpisodes)
            val rows: List<AbsStartShelfMergedRow> = uniqueBooks.map { Book(it) } + uniqueEpisodes.map { PodcastEpisode(it) }
            return rows.sortedWith { a, b ->
                val t0 = a.progressTimestamp(progress)
                val t1 = b.progressTimestamp(progress)
                if (t0 != t1) return@sortedWith t1.compareTo(t0)
                when {
                    a is Book && b is Book -> localizedCaseInsensitiveCompare(a.book.displayTitle, b.book.displayTitle)
                    a is PodcastEpisode && b is PodcastEpisode ->
                        localizedCaseInsensitiveCompare(a.episode.episodeTitle, b.episode.episodeTitle)
                    else -> a.id.compareTo(b.id)
                }
            }
        }
    }
}

/** iOS: `ABSStartShelfLocalization`. */
object AbsStartShelfLocalization {
    /** Einziger Home-Menüpunkt für alle Settings-Regale (Cover-Reihen unter Continue). */
    const val homeBrowseContinueSectionID = "continue"

    /** Historische Continue-Unterregale (weiterhin für Localization / Migration). */
    val homeBrowseContinueCategories = listOf("recentlyListened", "continueEbooks", "continueSeries")

    fun isHomeBrowseContinueCategory(category: String) = category in homeBrowseContinueCategories

    const val homeBrowseContinueStripLabel = "Dashboard"

    /** Legacy-ID — früher eigener Pill; Inhalte liegen unter Continue. */
    const val homeBrowseRecentSectionID = "recent"

    val homeBrowseRecentCategories = listOf("newestItems", "newestSeries")

    fun isHomeBrowseRecentCategory(category: String) = category in homeBrowseRecentCategories

    const val homeBrowseRecentStripLabel = "Recent"

    /** Statistik-Bereich auf Home (nicht mehr unter Settings). */
    const val homeBrowseStatsSectionID = "stats"

    fun isHomeBrowseStatsCategory(category: String) = category == homeBrowseStatsSectionID

    const val homeBrowseStatsStripLabel = "Stats"

    val categoryTitles: Map<String, String> = mapOf(
        "recentlyListened" to "Continue listening",
        "continueEbooks" to "Continue reading",
        "continueSeries" to "Continue series",
        "newestEpisodes" to "New episodes",
        "newestItems" to "Recently added",
        "newestSeries" to "Recent series",
        "recommended" to "Recommended",
        "recentlyFinished" to "Listen again",
        "newestAuthors" to "New authors",
    )

    fun displayTitle(category: String, serverLabel: String): String {
        categoryTitles[category]?.let { return it }
        val trimmed = serverLabel.swiftTrim()
        if (trimmed.isNotEmpty()) return trimmed
        return category
    }

    /** Bekannte Server-`category`-Keys für die Schalter „Regal anzeigen“. */
    val settingsCategoryOrder = listOf(
        "recentlyListened", "continueSeries", "newestEpisodes", "newestItems", "newestSeries",
        "recommended", "recentlyFinished", "newestAuthors",
    )

    /** iOS: SF-Symbol-Name für die Home-Browse-Leiste (Android mappt ihn auf ein Material-Icon). */
    fun stripSystemImage(category: String): String = when (category) {
        homeBrowseContinueSectionID, "recentlyListened" -> "play.circle.fill"
        "continueEbooks" -> "book.closed.fill"
        "continueSeries" -> "rectangle.stack.fill"
        "newestEpisodes" -> "mic.fill"
        homeBrowseRecentSectionID, "newestItems" -> "sparkles"
        homeBrowseStatsSectionID -> "chart.bar.fill"
        "newestSeries" -> "books.vertical.fill"
        "recommended" -> "lightbulb.fill"
        "recentlyFinished" -> "arrow.counterclockwise"
        "newestAuthors" -> "person.fill"
        else -> "square.grid.2x2"
    }

    private val kebabToSettings = mapOf(
        "continue-listening" to "recentlyListened",
        "continue-reading" to "recentlyListened",
        "continue-series" to "continueSeries",
        "recently-added" to "newestItems",
        "recent-series" to "newestSeries",
        "discover" to "recommended",
        "listen-again" to "recentlyFinished",
        "read-again" to "recentlyFinished",
        "newest-authors" to "newestAuthors",
        "newest-episodes" to "newestEpisodes",
    )

    /** `/personalized` liefert oft `id` wie `continue-listening`; die Schalter nutzen camelCase-Keys. */
    fun normalizedSettingsCategory(shelfId: String, apiCategory: String?): String {
        if (apiCategory != null && (apiCategory in settingsCategoryOrder || apiCategory == "continueEbooks")) return apiCategory
        if (shelfId in settingsCategoryOrder || shelfId == "continueEbooks") return shelfId
        return kebabToSettings[shelfId] ?: shelfId
    }
}

// MARK: - Library browse (catalog sections)

private fun intOrIntString(c: JObj, key: String): Int? = c.tryInt(key) ?: c.tryString(key)?.toIntOrNull()

/** iOS: `ABSLibraryAuthorsAPIEnvelope` — ältere Server: nur `authors`, neuere: `results` + `total`. */
@Serializable(with = AbsLibraryAuthorsAPIEnvelopeSerializer::class)
data class AbsLibraryAuthorsAPIEnvelope(
    val authors: List<AbsLibraryAuthorListItem>?,
    val results: List<AbsLibraryAuthorListItem>?,
    val total: Int?,
) {
    fun itemsAndTotal(): Pair<List<AbsLibraryAuthorListItem>, Int> {
        results?.let { return it to (total ?: it.size) }
        val a = authors ?: emptyList()
        return a to (total ?: a.size)
    }
}

object AbsLibraryAuthorsAPIEnvelopeSerializer : SwiftObjectSerializer<AbsLibraryAuthorsAPIEnvelope>("ABSLibraryAuthorsAPIEnvelope") {
    override fun decode(c: JObj) = AbsLibraryAuthorsAPIEnvelope(
        authors = c.listOrNull("authors", AbsLibraryAuthorListItemSerializer),
        results = c.listOrNull("results", AbsLibraryAuthorListItemSerializer),
        total = intOrIntString(c, "total"),
    )
}

/** iOS: `ABSLibraryAuthorsEnvelope` (Legacy-Form ohne Pagination). */
@Serializable(with = AbsLibraryAuthorsEnvelopeSerializer::class)
data class AbsLibraryAuthorsEnvelope(val authors: List<AbsLibraryAuthorListItem>)

object AbsLibraryAuthorsEnvelopeSerializer : SwiftObjectSerializer<AbsLibraryAuthorsEnvelope>("ABSLibraryAuthorsEnvelope") {
    override fun decode(c: JObj) = AbsLibraryAuthorsEnvelope(c.list("authors", AbsLibraryAuthorListItemSerializer))
}

/** iOS: `ABSLibraryAuthorListItem` (`GET /api/libraries/:id/authors`). */
@Serializable(with = AbsLibraryAuthorListItemSerializer::class)
data class AbsLibraryAuthorListItem(val id: String, val name: String, val numBooks: Int?, val imagePath: String?) {
    val hasAuthorImage: Boolean get() = imagePath.trimmedOrEmpty().isNotEmpty()
}

object AbsLibraryAuthorListItemSerializer : SwiftObjectSerializer<AbsLibraryAuthorListItem>("ABSLibraryAuthorListItem") {
    override fun decode(c: JObj) = AbsLibraryAuthorListItem(c.string("id"), c.string("name"), c.intOrNull("numBooks"), c.stringOrNull("imagePath"))
    // Nur für lokale Caches (Swift: Decodable; Roh-JSON wird dort gecacht).
    override fun encode(v: AbsLibraryAuthorListItem) = jsonObjectOf {
        put("id", JsonPrimitive(v.id)); put("name", JsonPrimitive(v.name))
        putIfPresent("numBooks", v.numBooks); putIfPresent("imagePath", v.imagePath)
    }
}

/** iOS: `ABSAuthorDetail` (`GET /api/authors/:id`, optional `include=items,series`). */
@Serializable(with = AbsAuthorDetailSerializer::class)
data class AbsAuthorDetail(
    val id: String,
    val name: String,
    val description: String?,
    val libraryItems: List<AbsBook>?,
    val series: List<AbsAuthorDetailSeries>?,
)

/** iOS: `ABSAuthorDetailSeries`. */
data class AbsAuthorDetailSeries(val id: String, val name: String, val items: List<AbsBook>?)

object AbsAuthorDetailSerializer : SwiftObjectSerializer<AbsAuthorDetail>("ABSAuthorDetail") {
    private val series = object : SwiftObjectSerializer<AbsAuthorDetailSeries>("ABSAuthorDetailSeries") {
        override fun decode(c: JObj) = AbsAuthorDetailSeries(c.string("id"), c.string("name"), c.listOrNull("items", AbsBookSerializer))
    }

    override fun decode(c: JObj) = AbsAuthorDetail(
        id = c.string("id"),
        name = c.string("name"),
        description = c.stringOrNull("description"),
        libraryItems = c.listOrNull("libraryItems", AbsBookSerializer),
        series = c.listOrNull("series", series),
    )
}

/** iOS: `EntityDetailAuthorSeriesSection` — Autor-Detail: eine Serie mit ihren Büchern. */
data class EntityDetailAuthorSeriesSection(val id: String, val name: String, val books: List<AbsBook>)

/** iOS: `ABSSeriesDetail` (`GET /api/series/:id`). */
@Serializable(with = AbsSeriesDetailSerializer::class)
data class AbsSeriesDetail(val id: String, val name: String, val description: String?)

object AbsSeriesDetailSerializer : SwiftObjectSerializer<AbsSeriesDetail>("ABSSeriesDetail") {
    override fun decode(c: JObj) = AbsSeriesDetail(c.string("id"), c.string("name"), c.stringOrNull("description"))
}

/** iOS: `ABSLibraryNarratorListItem` (`GET /api/libraries/:id/narrators`). */
data class AbsLibraryNarratorListItem(val id: String, val name: String, val numBooks: Int?)

/** iOS: `ABSLibraryNarratorsEnvelope`. */
@Serializable(with = AbsLibraryNarratorsEnvelopeSerializer::class)
data class AbsLibraryNarratorsEnvelope(val narrators: List<AbsLibraryNarratorListItem>)

object AbsLibraryNarratorsEnvelopeSerializer : SwiftObjectSerializer<AbsLibraryNarratorsEnvelope>("ABSLibraryNarratorsEnvelope") {
    private val item = object : SwiftObjectSerializer<AbsLibraryNarratorListItem>("ABSLibraryNarratorListItem") {
        override fun decode(c: JObj) = AbsLibraryNarratorListItem(c.string("id"), c.string("name"), c.intOrNull("numBooks"))
    }
    override fun decode(c: JObj) = AbsLibraryNarratorsEnvelope(c.list("narrators", item))
}

/** iOS: `ABSLibrarySeriesListItem` — Eintrag aus `GET /api/libraries/:id/series`. */
@Serializable(with = AbsLibrarySeriesListItemSerializer::class)
data class AbsLibrarySeriesListItem(val id: String, val name: String, val books: List<AbsBook>?) {
    /** API: kein Serien-`author` — alle Autoren aus `books`. */
    val cardAuthorsLine: String? get() = AbsBook.cardAuthorsLine(books)
}

object AbsLibrarySeriesListItemSerializer : SwiftObjectSerializer<AbsLibrarySeriesListItem>("ABSLibrarySeriesListItem") {
    override fun decode(c: JObj) = AbsLibrarySeriesListItem(c.string("id"), c.string("name"), c.listOrNull("books", AbsBookSerializer))
    override fun encode(v: AbsLibrarySeriesListItem) = jsonObjectOf {
        put("id", JsonPrimitive(v.id)); put("name", JsonPrimitive(v.name))
        putList("books", v.books) { AbsBookSerializer.encode(it) }
    }
}

/** iOS: `ABSLibraryCollectionListItem` — Eintrag aus `GET /api/libraries/:id/collections`. */
@Serializable(with = AbsLibraryCollectionListItemSerializer::class)
data class AbsLibraryCollectionListItem(
    val id: String,
    val name: String,
    val description: String?,
    val books: List<AbsBook>?,
    /** Sekunden seit 1970 (iOS: `TimeInterval`, Server liefert Millisekunden). */
    val createdAt: Double?,
    val lastUpdate: Double?,
)

object AbsLibraryCollectionListItemSerializer : SwiftObjectSerializer<AbsLibraryCollectionListItem>("ABSLibraryCollectionListItem") {
    private fun millis(c: JObj, key: String): Double? {
        c.tryDouble(key)?.let { return it / 1000.0 }
        c.tryLong(key)?.let { return it.toDouble() / 1000.0 }
        c.tryString(key)?.let { s -> swiftDouble(s)?.let { return it / 1000.0 } }
        return null
    }

    override fun decode(c: JObj) = AbsLibraryCollectionListItem(
        id = c.string("id"),
        name = c.string("name"),
        description = c.stringOrNull("description"),
        books = c.listOrNull("books", AbsBookSerializer),
        createdAt = millis(c, "createdAt"),
        lastUpdate = millis(c, "lastUpdate"),
    )
}

/** iOS: `ABSLibraryResultsPageEnvelope<T>`. */
data class AbsLibraryResultsPageEnvelope<T>(val results: List<T>, val total: Int) {
    companion object {
        fun <T> serializer(element: ElementDecoder<T>) = object : SwiftObjectSerializer<AbsLibraryResultsPageEnvelope<T>>("ABSLibraryResultsPageEnvelope") {
            override fun decode(c: JObj): AbsLibraryResultsPageEnvelope<T> {
                val results = c.tryList("results", element) ?: emptyList()
                return AbsLibraryResultsPageEnvelope(results, intOrIntString(c, "total") ?: results.size)
            }
        }
    }
}

// MARK: - Search

/** iOS: `ABSSearchBookRow`. */
data class AbsSearchBookRow(val libraryItem: AbsBook)

/** iOS: `ABSSearchAuthorRow`. */
data class AbsSearchAuthorRow(val id: String, val name: String, val numBooks: Int?)

/** iOS: `ABSSearchNarratorRow`. */
data class AbsSearchNarratorRow(val name: String, val numBooks: Int?) {
    val id: String get() = name
}

/** iOS: `ABSSearchSeriesRow` — flach oder unter `series` geschachtelt. */
data class AbsSearchSeriesRow(val id: String, val name: String, val books: List<AbsBook>?) {
    val cardAuthorsLine: String? get() = AbsBook.cardAuthorsLine(books)
}

/** iOS: `ABSSearchNamedCount`. */
data class AbsSearchNamedCount(val name: String, val numItems: Int?) {
    val id: String get() = name
}

/** iOS: `ABSLibraryFilterAuthor`. */
@Serializable
data class AbsLibraryFilterAuthor(val id: String, val name: String)

/** iOS: `ABSLibraryFilterSeries`. */
@Serializable
data class AbsLibraryFilterSeries(val id: String, val name: String)

/** iOS: `ABSLibraryFilterData` — `GET /api/libraries/:id/filterdata`. */
@Serializable(with = AbsLibraryFilterDataSerializer::class)
data class AbsLibraryFilterData(
    val authors: List<AbsLibraryFilterAuthor>? = null,
    val tags: List<String>? = null,
    val series: List<AbsLibraryFilterSeries>? = null,
    val narrators: List<String>? = null,
    val languages: List<String>? = null,
    val publishers: List<String>? = null,
    val publishedDecades: List<String>? = null,
    val genres: List<String>? = null,
)

object AbsLibraryFilterDataSerializer : SwiftObjectSerializer<AbsLibraryFilterData>("ABSLibraryFilterData") {
    private val author = object : SwiftObjectSerializer<AbsLibraryFilterAuthor>("ABSLibraryFilterAuthor") {
        override fun decode(c: JObj) = AbsLibraryFilterAuthor(c.string("id"), c.string("name"))
    }
    private val series = object : SwiftObjectSerializer<AbsLibraryFilterSeries>("ABSLibraryFilterSeries") {
        override fun decode(c: JObj) = AbsLibraryFilterSeries(c.string("id"), c.string("name"))
    }

    override fun decode(c: JObj) = AbsLibraryFilterData(
        authors = c.listOrNull("authors", author),
        tags = c.listOrNull("tags", ElementDecoder.string),
        series = c.listOrNull("series", series),
        narrators = c.listOrNull("narrators", ElementDecoder.string),
        languages = c.listOrNull("languages", ElementDecoder.string),
        publishers = c.listOrNull("publishers", ElementDecoder.string),
        publishedDecades = c.listOrNull("publishedDecades", ElementDecoder.string),
        genres = c.listOrNull("genres", ElementDecoder.string),
    )

    override fun encode(v: AbsLibraryFilterData) = jsonObjectOf {
        putList("authors", v.authors) { a -> jsonObjectOf { put("id", JsonPrimitive(a.id)); put("name", JsonPrimitive(a.name)) } }
        putStrings("tags", v.tags)
        putList("series", v.series) { a -> jsonObjectOf { put("id", JsonPrimitive(a.id)); put("name", JsonPrimitive(a.name)) } }
        putStrings("narrators", v.narrators)
        putStrings("languages", v.languages)
        putStrings("publishers", v.publishers)
        putStrings("publishedDecades", v.publishedDecades)
        putStrings("genres", v.genres)
    }
}

/** iOS: `BooksBrowseGenreListItem` — Genre-Zeile in der Library-Browse-Liste. */
data class BooksBrowseGenreListItem(val name: String, val numBooks: Int?) {
    val id: String get() = name
}

/** iOS: `BooksBrowseTagListItem` — Tag-Zeile in der Library-Browse-Liste. */
data class BooksBrowseTagListItem(val name: String, val numBooks: Int?) {
    val id: String get() = name
}

/** `count` oder `numItems` — Int, Int64, String oder Double (in dieser Reihenfolge wie iOS). */
private fun flexibleCount(c: JObj): Int {
    c.tryInt("count")?.let { return it }
    c.tryInt("numItems")?.let { return it }
    c.tryLong("count")?.let { return it.toInt() }
    c.tryLong("numItems")?.let { return it.toInt() }
    c.tryString("count")?.toIntOrNull()?.let { return it }
    c.tryString("numItems")?.toIntOrNull()?.let { return it }
    c.tryDouble("count")?.let { return it.toInt() }
    c.tryDouble("numItems")?.let { return it.toInt() }
    return 0
}

/** iOS: `ABSLibraryTagStat` — Persistenz für Tag-Browse (`browseTags/<libraryId>.json`). */
@Serializable(with = AbsLibraryTagStatSerializer::class)
data class AbsLibraryTagStat(val tag: String, val count: Int)

object AbsLibraryTagStatSerializer : SwiftObjectSerializer<AbsLibraryTagStat>("ABSLibraryTagStat") {
    override fun decode(c: JObj) = AbsLibraryTagStat(c.string("tag"), flexibleCount(c))
    override fun encode(v: AbsLibraryTagStat) = jsonObjectOf { put("tag", JsonPrimitive(v.tag)); put("count", JsonPrimitive(v.count)) }
}

/** iOS: `ABSLibraryGenreStat` — `GET /api/libraries/:id/stats` → `genresWithCount`. */
@Serializable(with = AbsLibraryGenreStatSerializer::class)
data class AbsLibraryGenreStat(val genre: String, val count: Int)

object AbsLibraryGenreStatSerializer : SwiftObjectSerializer<AbsLibraryGenreStat>("ABSLibraryGenreStat") {
    override fun decode(c: JObj) = AbsLibraryGenreStat(c.string("genre"), flexibleCount(c))
    override fun encode(v: AbsLibraryGenreStat) = jsonObjectOf { put("genre", JsonPrimitive(v.genre)); put("count", JsonPrimitive(v.count)) }
}

/** iOS: `ABSSearchResponse`. */
@Serializable(with = AbsSearchResponseSerializer::class)
data class AbsSearchResponse(
    /** Hörbücher-Suche: Treffer unter `book`. */
    val book: List<AbsSearchBookRow>,
    /** Podcast-Suche: Shows unter `podcast`, Folgen-Treffer oft unter `episodes`. */
    val podcast: List<AbsSearchBookRow>,
    val episodes: List<AbsSearchBookRow>,
    val authors: List<AbsSearchAuthorRow>,
    val narrators: List<AbsSearchNarratorRow>,
    val series: List<AbsSearchSeriesRow>,
    val tags: List<AbsSearchNamedCount>,
    val genres: List<AbsSearchNamedCount>,
    /** Folgen-Treffer aus der Search-API (`episodes` mit `recentEpisode` je Show). */
    var podcastEpisodeMatches: List<AbsPodcastEpisodeListItem> = emptyList(),
) {
    /** Einträge für die Bücher-Suche (nur `book`-Key). */
    fun bookSearchPlayableLibraryItems(minDuration: (AbsBook) -> Double): List<AbsBook> =
        book.map { it.libraryItem }.filter { (it.media.numTracks ?: 0) > 0 || minDuration(it) > 0 }

    /** Bücher-Suche: minified-Stubs ohne Spuren/Dauer behalten (wie Katalog-Listen). */
    fun bookSearchLibraryItems(): List<AbsBook> = book.map { it.libraryItem }.filter { it.isUsableLibraryCatalogRow }

    /** Podcast-Library-Suche: `podcast` + `book`, ohne Dubletten nach Show-ID. */
    fun podcastSearchShowLibraryItems(): List<AbsBook> = listableShows(podcast + book)

    /** Wie [podcastSearchShowLibraryItems], inkl. Show-Treffer aus der `episodes`-Liste (Navigation). */
    fun podcastSearchShowLibraryItemsIncludingEpisodeMatches(): List<AbsBook> = listableShows(podcast + episodes + book)

    private fun listableShows(rows: List<AbsSearchBookRow>): List<AbsBook> {
        val seen = HashSet<String>()
        return rows.map { it.libraryItem }.filter { it.isListablePodcastLibraryItem && seen.add(it.id) }
    }
}

object AbsSearchResponseSerializer : SwiftObjectSerializer<AbsSearchResponse>("ABSSearchResponse") {
    private val bookRow = object : SwiftObjectSerializer<AbsSearchBookRow>("ABSSearchBookRow") {
        override fun decode(c: JObj) = AbsSearchBookRow(c.obj("libraryItem", AbsBookSerializer))
    }
    private val authorRow = object : SwiftObjectSerializer<AbsSearchAuthorRow>("ABSSearchAuthorRow") {
        override fun decode(c: JObj) = AbsSearchAuthorRow(c.string("id"), c.string("name"), c.intOrNull("numBooks"))
    }
    private val narratorRow = object : SwiftObjectSerializer<AbsSearchNarratorRow>("ABSSearchNarratorRow") {
        override fun decode(c: JObj) = AbsSearchNarratorRow(c.string("name"), c.intOrNull("numBooks"))
    }
    private val seriesRow = object : SwiftObjectSerializer<AbsSearchSeriesRow>("ABSSearchSeriesRow") {
        override fun decode(c: JObj): AbsSearchSeriesRow {
            val src = if (c.contains("series")) c.nested("series") else c
            return AbsSearchSeriesRow(src.string("id"), src.string("name"), c.tryList("books", AbsBookSerializer))
        }
    }
    private val namedCount = object : SwiftObjectSerializer<AbsSearchNamedCount>("ABSSearchNamedCount") {
        override fun decode(c: JObj) = AbsSearchNamedCount(c.string("name"), c.intOrNull("numItems"))
    }

    override fun decode(c: JObj) = AbsSearchResponse(
        book = c.tryList("book", bookRow) ?: emptyList(),
        podcast = c.tryList("podcast", bookRow) ?: emptyList(),
        episodes = c.tryList("episodes", bookRow) ?: emptyList(),
        authors = c.tryList("authors", authorRow) ?: emptyList(),
        narrators = c.tryList("narrators", narratorRow) ?: emptyList(),
        series = c.tryList("series", seriesRow) ?: emptyList(),
        tags = c.tryList("tags", namedCount) ?: emptyList(),
        genres = c.tryList("genres", namedCount) ?: emptyList(),
    )
}

// MARK: - Play Session

/** iOS: `ABSPlaySessionRequest`. */
@Serializable
data class AbsPlaySessionRequest(
    val forceDirectPlay: Boolean,
    val forceTranscode: Boolean,
    val supportedMimeTypes: List<String>,
    val mediaPlayer: String,
    val deviceInfo: DeviceInfo,
) {
    @Serializable
    data class DeviceInfo(val clientName: String, val clientVersion: String? = null, val deviceId: String)

    companion object {
        /**
         * iOS: `init(deviceId:clientVersion:)`. `mediaPlayer`/`clientName` bleiben bewusst wie iOS
         * (`ios` / `Abstand`), damit der Server beide Clients gleich behandelt (Direct Play).
         */
        fun create(deviceId: String, clientVersion: String?) = AbsPlaySessionRequest(
            forceDirectPlay = true,
            forceTranscode = false,
            supportedMimeTypes = listOf(
                "audio/flac", "audio/mpeg", "audio/mp4", "audio/ogg", "audio/aac", "audio/x-aiff", "audio/webm",
            ),
            mediaPlayer = "ios",
            deviceInfo = DeviceInfo(clientName = "Abstand", clientVersion = clientVersion, deviceId = deviceId),
        )
    }
}

/** iOS: `ABSPlaySession`. */
@Serializable(with = AbsPlaySessionSerializer::class)
data class AbsPlaySession(
    val id: String,
    val userId: String?,
    val libraryItemId: String,
    val episodeId: String?,
    val mediaType: String?,
    val currentTime: Double,
    val duration: Double,
    val audioTracks: List<AbsAudioTrack>?,
    val chapters: List<AbsChapter>?,
    val libraryItem: AbsBook,
    val displayTitle: String?,
    val displayAuthor: String?,
) {
    /** Mini-Player / Sperrbildschirm: Podcast-Folgentitel statt Sendungsname allein. */
    fun bookForPlayerUI(): AbsBook {
        if ((mediaType ?: "").lowercase() != "podcast") return libraryItem
        val raw = displayTitle?.swiftTrim()
        if (raw.isNullOrEmpty()) return libraryItem
        val authRaw = displayAuthor.trimmedOrEmpty()
        val authOpt = if (authRaw.isEmpty()) null else displayAuthor
        val meta = AbsBookMediaMetadata.copying(libraryItem.media.metadata, title = raw, authorName = authOpt)
        val dur = if (duration > 0) duration else libraryItem.media.duration
        val trackCount = audioTracks?.size ?: libraryItem.media.numTracks ?: 0
        val media = AbsBookMedia(
            metadata = meta,
            duration = dur,
            size = libraryItem.media.size,
            numTracks = maxOf(trackCount, 1),
            chapters = libraryItem.media.chapters,
            tracks = libraryItem.media.tracks,
        )
        return AbsBook(libraryItem.id, libraryItem.libraryId, media, libraryItem.addedAt, libraryItem.updatedAt, libraryItem.mediaId)
    }
}

object AbsPlaySessionSerializer : SwiftObjectSerializer<AbsPlaySession>("ABSPlaySession") {
    override fun decode(c: JObj) = AbsPlaySession(
        id = c.string("id"),
        userId = c.stringOrNull("userId"),
        libraryItemId = c.string("libraryItemId"),
        episodeId = c.stringOrNull("episodeId"),
        mediaType = c.stringOrNull("mediaType"),
        currentTime = c.double("currentTime"),
        duration = c.double("duration"),
        audioTracks = c.listOrNull("audioTracks", AbsAudioTrackSerializer),
        chapters = c.listOrNull("chapters", AbsChapterSerializer),
        displayTitle = c.stringOrNull("displayTitle"),
        displayAuthor = c.stringOrNull("displayAuthor"),
        libraryItem = c.obj("libraryItem", AbsBookSerializer),
    )
}

/** iOS: `String.absSanitizedLibraryPathSegment()` — ein POSIX-Segment für Server-Bibliothekspfade. */
fun String.absSanitizedLibraryPathSegment(): String {
    val t = swiftTrim()
    val base = t.ifEmpty { "Podcast" }
    val invalid = "/\\:?*\"<>|\u0000"
    var s = base.map { if (it in invalid) '_' else it }.joinToString("")
    s = s.replace("..", "_")
    if (s.isEmpty()) return "Podcast"
    return s.take(120)
}
