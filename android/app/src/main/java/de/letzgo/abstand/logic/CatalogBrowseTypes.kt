package de.letzgo.abstand.logic

import java.util.Base64

// iOS: CatalogBrowseTypes.swift — Sortierfelder, Bereiche und Filter des Katalogs. Raw-Values sind
// identisch zu iOS, weil sie unter `abstand_*`-Keys gespeichert werden.

/** Gemeinsame Sicht der Sortier-Menüs (iOS: `AbstandSortMenuField`). */
interface SortMenuField {
    val rawValue: String
    val menuTitle: String
    /** „Zufällig" blendet die Auf-/Absteigend-Auswahl aus. */
    val suppressesSortOrderPicker: Boolean get() = false
}

private inline fun <reified T> rawLookup(raw: String?): T? where T : Enum<T>, T : SortMenuField =
    enumValues<T>().firstOrNull { it.rawValue == raw }

private fun base64(value: String): String = Base64.getEncoder().encodeToString(value.toByteArray(Charsets.UTF_8))

/** Sortierfeld für `GET /api/libraries/:id/items` (`sort`) bei Bücher-Bibliotheken. */
enum class CatalogSortField(override val rawValue: String, override val menuTitle: String, val apiSortParameter: String) : SortMenuField {
    TITLE("title", "Title", "media.metadata.title"),
    AUTHOR_NAME("authorName", "Author (first name first)", "media.metadata.authorName"),
    AUTHOR_NAME_LF("authorNameLF", "Author (last name first)", "media.metadata.authorNameLF"),
    ADDED_AT("addedAt", "Date added", "addedAt"),
    PUBLISHED_YEAR("publishedYear", "Published year", "media.metadata.publishedYear"),
    DURATION("duration", "Duration", "media.duration"),
    SIZE("size", "File size", "size"),
    BIRTHTIME_MS("birthtimeMs", "File created", "birthtimeMs"),
    MTIME_MS("mtimeMs", "File modified", "mtimeMs"),
    PROGRESS("progress", "Last progress update", "progress"),
    PROGRESS_CREATED_AT("progressCreatedAt", "Progress started", "progress.createdAt"),
    PROGRESS_FINISHED_AT("progressFinishedAt", "Finished", "progress.finishedAt"),
    RANDOM("random", "Random", "random");

    val id: String get() = rawValue
    override val suppressesSortOrderPicker: Boolean get() = this == RANDOM

    companion object { fun fromRaw(raw: String?): CatalogSortField? = rawLookup(raw) }
}

/** Sortierung Podcast-Shows (Server `libraryItemsPodcastFilters.getOrder`). */
enum class PodcastCatalogSortField(override val rawValue: String, override val menuTitle: String, val apiSortParameter: String) : SortMenuField {
    TITLE("title", "Title", "media.metadata.title"),
    AUTHOR("author", "Author", "media.metadata.author"),
    NUM_EPISODES("numEpisodes", "Number of episodes", "media.numTracks"),
    ADDED_AT("addedAt", "Date added", "addedAt"),
    SIZE("size", "Total size", "size"),
    BIRTHTIME_MS("birthtimeMs", "File created", "birthtimeMs"),
    MTIME_MS("mtimeMs", "File modified", "mtimeMs"),
    RANDOM("random", "Random", "random");

    override val suppressesSortOrderPicker: Boolean get() = this == RANDOM

    companion object { fun fromRaw(raw: String?): PodcastCatalogSortField? = rawLookup(raw) }
}

/** Folgen-Sortierung einer Sendung (lokal). */
enum class PodcastEpisodeSortField(override val rawValue: String, override val menuTitle: String) : SortMenuField {
    PUBLISHED_AT("publishedAt", "Release date"),
    TITLE("title", "Title"),
    DURATION("duration", "Duration");

    companion object { fun fromRaw(raw: String?): PodcastEpisodeSortField? = rawLookup(raw) }
}

/** Unterbereiche im Audiobooks-Tab; `rawValue` ist Identität/Auswahl-ID, [title] die Anzeige. */
enum class BooksBrowseSection(val rawValue: String, val systemImage: String) {
    BOOKS("Books", "books.vertical"),
    SEARCH("Search", "magnifyingglass"),
    SERIES("Series", "rectangle.stack"),
    COLLECTIONS("Collections", "folder"),
    GENRES("Genres", "sparkles"),
    TAGS("Tags", "tag"),
    AUTHOR("Authors", "person.text.rectangle"),
    NARRATORS("Narrators", "waveform"),
    EBOOKS("eBooks", "book.closed"),
    EBOOKS_SUPPLEMENTARY("Supplementary", "books.vertical.fill");

    val id: String get() = rawValue
    val title: String get() = if (this == BOOKS) "Audiobooks" else rawValue

    companion object {
        /** Reihenfolge der Leiste im Audiobook-Bereich. */
        val audiobookStripOrder = listOf(BOOKS, EBOOKS, SERIES, AUTHOR, COLLECTIONS, GENRES, NARRATORS, TAGS)

        fun fromRaw(raw: String?): BooksBrowseSection? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** Podcast-Tab-Streifen: Search / New / Show-`libraryItemId`. */
object PodcastCatalogStripSection {
    const val SEARCH = "__search__"
    const val NEW_EPISODES = "__new__"
}

/** Schnellfilter im Bücher-Katalog. */
enum class LibraryCatalogQuickFilter(val rawValue: String, val menuTitle: String, val menuSystemImage: String) {
    IN_PROGRESS("inProgress", "In progress", "play.circle"),
    FINISHED("finished", "Finished", "checkmark.circle"),
    NOT_STARTED("notStarted", "Not started", "circle"),
    DOWNLOADED("downloaded", "Downloaded", "arrow.down.circle"),
    EBOOKS("ebooks", "eBooks", "book.closed"),
    EBOOKS_SUPPLEMENTARY("ebooksSupplementary", "Supplementary eBooks", "books.vertical.fill");

    val id: String get() = rawValue
    val isLocalDownloadedOnly: Boolean get() = this == DOWNLOADED

    /** Server-Filter `<gruppe>.<base64(wert)>`; `null` = rein lokal (Downloads). */
    val serverFilterKey: String?
        get() = when (this) {
            DOWNLOADED -> null
            IN_PROGRESS -> "progress.${base64("in-progress")}"
            FINISHED -> "progress.${base64("finished")}"
            NOT_STARTED -> "progress.${base64("not-started")}"
            EBOOKS -> "ebooks.${base64("ebook")}"
            EBOOKS_SUPPLEMENTARY -> "ebooks.${base64("supplementary")}"
        }

    val summaryPrefix: String
        get() = when (this) {
            IN_PROGRESS, FINISHED, NOT_STARTED -> "Progress"
            DOWNLOADED -> "Downloaded"
            EBOOKS -> "eBooks"
            EBOOKS_SUPPLEMENTARY -> "Supplementary"
        }

    val summaryDetail: String?
        get() = when (this) {
            IN_PROGRESS -> "In progress"
            FINISHED -> "Finished"
            NOT_STARTED -> "Not started"
            else -> null
        }

    companion object { fun fromRaw(raw: String?): LibraryCatalogQuickFilter? = entries.firstOrNull { it.rawValue == raw } }
}

/** Navigation zu Autor-, Serien-, Sprecher-, Sammlungs-, Genre- oder Tag-Detail. */
data class BooksEntityDetailNav(
    val kind: Kind,
    val entityId: String,
    val title: String,
    val numBooks: Int?,
    /** Bibliothek des Quell-Titels (eBooks vs. Hörbücher). */
    val libraryId: String? = null,
) {
    enum class Kind(val rawValue: String) { AUTHOR("author"), SERIES("series"), NARRATOR("narrator"), COLLECTION("collection"), GENRE("genre"), TAG("tag") }

    val id: String
        get() {
            val lib = libraryId?.let(FoundationText::trimmingWhitespacesAndNewlines)
            if (!lib.isNullOrEmpty()) return "${kind.rawValue}:$lib:$entityId"
            return "${kind.rawValue}:$entityId"
        }

    val libraryFilter: String
        get() {
            val b64 = base64(entityId)
            return when (kind) {
                Kind.AUTHOR -> "authors.$b64"
                Kind.SERIES -> "series.$b64"
                Kind.NARRATOR -> "narrators.$b64"
                Kind.COLLECTION -> "collections.$b64"
                Kind.GENRE -> "genres.$b64"
                Kind.TAG -> "tags.$b64"
            }
        }

    val filterSummaryPrefix: String
        get() = when (kind) {
            Kind.AUTHOR -> "Author"
            Kind.SERIES -> "Series"
            Kind.NARRATOR -> "Narrator"
            Kind.COLLECTION -> "Collection"
            Kind.GENRE -> "Genre"
            Kind.TAG -> "Tag"
        }
}

/** Sortierung Autorenliste (`GET …/authors`, `sort` = rawValue). */
enum class BooksBrowseAuthorsSortField(override val rawValue: String, override val menuTitle: String) : SortMenuField {
    NAME("name", "Name (first name first)"),
    LAST_FIRST("lastFirst", "Name (last name first)"),
    NUM_BOOKS("numBooks", "Number of books"),
    ADDED_AT("addedAt", "Date added"),
    UPDATED_AT("updatedAt", "Date updated");

    val apiSortParameter: String get() = rawValue

    companion object { fun fromRaw(raw: String?): BooksBrowseAuthorsSortField? = rawLookup(raw) }
}

/** Sortierung Sprecherliste (lokal). */
enum class BooksBrowseNarratorsSortField(override val rawValue: String, override val menuTitle: String) : SortMenuField {
    NAME("name", "Name"),
    NUM_BOOKS("numBooks", "Number of books");

    companion object { fun fromRaw(raw: String?): BooksBrowseNarratorsSortField? = rawLookup(raw) }
}

/** Sortierung Serienliste (`GET …/series`, `sort` = rawValue). */
enum class BooksBrowseSeriesSortField(override val rawValue: String, override val menuTitle: String) : SortMenuField {
    NAME("name", "Series name"),
    NUM_BOOKS("numBooks", "Number of books"),
    TOTAL_DURATION("totalDuration", "Total duration"),
    ADDED_AT("addedAt", "Date added"),
    LAST_BOOK_ADDED("lastBookAdded", "Last book added"),
    LAST_BOOK_UPDATED("lastBookUpdated", "Last book updated"),
    RANDOM("random", "Random");

    val apiSortParameter: String get() = rawValue
    override val suppressesSortOrderPicker: Boolean get() = this == RANDOM

    companion object { fun fromRaw(raw: String?): BooksBrowseSeriesSortField? = rawLookup(raw) }
}

/** Sortierung Genres/Tags (lokal). */
enum class BooksBrowseFacetSortField(override val rawValue: String, override val menuTitle: String) : SortMenuField {
    NAME("name", "Name"),
    BOOK_COUNT("bookCount", "Number of books");

    companion object { fun fromRaw(raw: String?): BooksBrowseFacetSortField? = rawLookup(raw) }
}

/** Sortierung Sammlungen (lokal). */
enum class BooksBrowseCollectionsSortField(override val rawValue: String, override val menuTitle: String) : SortMenuField {
    NAME("name", "Name"),
    CREATED_AT("createdAt", "Date created"),
    LAST_UPDATE("lastUpdate", "Last update"),
    BOOK_COUNT("bookCount", "Number of books");

    companion object { fun fromRaw(raw: String?): BooksBrowseCollectionsSortField? = rawLookup(raw) }
}

/** iOS: `BooksLibraryToolbarSnapshot` — Wertzustand der Bücher-Toolbar (Equatable → `data class`). */
data class BooksLibraryToolbarSnapshot(
    val booksBrowseSection: BooksBrowseSection,
    val catalogSortField: CatalogSortField,
    val catalogSortDescending: Boolean,
    val libraryCatalogQuickFilter: LibraryCatalogQuickFilter?,
    val ebookCatalogQuickFilter: LibraryCatalogQuickFilter?,
    val isLibraryCatalogFiltered: Boolean,
    val isAllFilterActive: Boolean,
    val browseAuthorsSortField: BooksBrowseAuthorsSortField,
    val browseAuthorsSortDescending: Boolean,
    val browseNarratorsSortField: BooksBrowseNarratorsSortField,
    val browseNarratorsSortDescending: Boolean,
    val browseSeriesSortField: BooksBrowseSeriesSortField,
    val browseSeriesSortDescending: Boolean,
    val browseCollectionsSortField: BooksBrowseCollectionsSortField,
    val browseCollectionsSortDescending: Boolean,
    val browseGenresSortField: BooksBrowseFacetSortField,
    val browseGenresSortDescending: Boolean,
    val browseTagsSortField: BooksBrowseFacetSortField,
    val browseTagsSortDescending: Boolean,
)
