package de.letzgo.abstand.store

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.TypeConverter
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsAuthorShelfEntity
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookSerializer
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsLibraryAuthorListItem
import de.letzgo.abstand.data.AbsLibraryCollectionListItem
import de.letzgo.abstand.data.AbsLibraryGenreStat
import de.letzgo.abstand.data.AbsLibraryNarratorListItem
import de.letzgo.abstand.data.AbsLibrarySerializer
import de.letzgo.abstand.data.AbsLibrarySeriesListItem
import de.letzgo.abstand.data.AbsLibraryTagStat
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfSection
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.swiftTrim
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer

// iOS: LocalLibraryModels.swift — Room-Entities der lokalen "Server-Kopie". Rein persistenzintern;
// `Abs*`-Typen bleiben für Netzwerk/Anzeige bestehen, Mapping über `from(...)`/`to...()` je Typ.
// Tabellennamen = iOS-Klassennamen. Datumswerte als Millisekunden seit 1970 (iOS: `Date`).
// Unique-Keys sind Primärschlüssel; Inserts laufen mit REPLACE (SwiftData-`.unique` = Upsert).

/** iOS: `LocalStoreMeta` — Bootstrap-/Versionsinfo, ein Datensatz pro Account-Store. */
@Entity(tableName = "LocalStoreMeta")
data class LocalStoreMeta(
    @PrimaryKey val id: String = "meta",
    var schemaVersion: Int = LocalLibrarySchema.ebookCatalogFlagsMetaVersion,
    var lastOpenedAt: Long = System.currentTimeMillis(),
)

/**
 * iOS: `LocalProgress` — Wiedergabe-/Lesefortschritt. Unique-Key `progressLookupKey`
 * (`libraryItemId[-episodeId]`, = `progressByItemId`-Schlüssel).
 */
@Entity(tableName = "LocalProgress", indices = [Index("lastUpdate")])
data class LocalProgress(
    @PrimaryKey val progressLookupKey: String,
    val mediaProgressServerId: String?,
    val libraryItemId: String,
    val episodeId: String?,
    val duration: Double,
    val progress: Double,
    val currentTime: Double,
    val isFinished: Boolean,
    val lastUpdate: Long?,
    val ebookProgress: Double?,
    val ebookLocation: String?,
) {
    /**
     * Unterscheidet sich die Zeile vom neuen Stand? Nur bei echtem Unterschied schreiben (iOS: sonst
     * Persistent-History-Wachstum; hier: unnötige Schreib-I/O pro Tick).
     */
    fun differs(p: AbsUserMediaProgress): Boolean = this != from(p)

    fun toAbsUserMediaProgress() = AbsUserMediaProgress(
        mediaProgressServerId = mediaProgressServerId,
        libraryItemId = libraryItemId,
        episodeId = episodeId,
        duration = duration,
        progress = progress,
        currentTime = currentTime,
        isFinished = isFinished,
        lastUpdate = lastUpdate,
        ebookProgress = ebookProgress,
        ebookLocation = ebookLocation,
    )

    companion object {
        fun from(p: AbsUserMediaProgress) = LocalProgress(
            progressLookupKey = p.progressLookupKey,
            mediaProgressServerId = p.mediaProgressServerId,
            libraryItemId = p.libraryItemId,
            episodeId = p.episodeId,
            duration = p.duration,
            progress = p.progress,
            currentTime = p.currentTime,
            isFinished = p.isFinished,
            lastUpdate = p.lastUpdate,
            ebookProgress = p.ebookProgress,
            ebookLocation = p.ebookLocation,
        )
    }
}

/** iOS: `LocalBookmark` — Unique-Key wie `AbsAudioBookmark.id` (`"$libraryItemId-$time"`). */
@Entity(tableName = "LocalBookmark")
data class LocalBookmark(
    @PrimaryKey val id: String,
    val libraryItemId: String,
    val title: String,
    val time: Int,
    val createdAt: Long?,
) {
    fun toAbsAudioBookmark() = AbsAudioBookmark(libraryItemId = libraryItemId, title = title, time = time, createdAt = createdAt)

    companion object {
        fun from(b: AbsAudioBookmark) = LocalBookmark(b.id, b.libraryItemId, b.title, b.time, b.createdAt)
    }
}

/** iOS: `LocalGenreStat` — zusammengesetzter Key `"$libraryId|$genre"`. */
@Entity(tableName = "LocalGenreStat", indices = [Index("libraryId")])
data class LocalGenreStat(
    @PrimaryKey val compositeKey: String,
    val libraryId: String,
    val genre: String,
    val count: Int,
) {
    fun toStat() = AbsLibraryGenreStat(genre = genre, count = count)

    companion object {
        fun from(libraryId: String, stat: AbsLibraryGenreStat) =
            LocalGenreStat("$libraryId|${stat.genre}", libraryId, stat.genre, stat.count)
    }
}

/** iOS: `LocalTagStat`. */
@Entity(tableName = "LocalTagStat", indices = [Index("libraryId")])
data class LocalTagStat(
    @PrimaryKey val compositeKey: String,
    val libraryId: String,
    val tag: String,
    val count: Int,
) {
    fun toStat() = AbsLibraryTagStat(tag = tag, count = count)

    companion object {
        fun from(libraryId: String, stat: AbsLibraryTagStat) = LocalTagStat("$libraryId|${stat.tag}", libraryId, stat.tag, stat.count)
    }
}

/**
 * iOS: `LocalAuthorListState` — Sortierung/Gesamtzahl der zuletzt gecachten Autoren-Seite je
 * Bibliothek (nur die zuletzt gesehene Sort-Kombination bleibt offline nutzbar).
 */
@Entity(tableName = "LocalAuthorListState")
data class LocalAuthorListState(
    @PrimaryKey val libraryId: String,
    val sortField: String,
    val descending: Boolean,
    val total: Int,
)

/** iOS: `LocalAuthor` — Autor einer Browse-Liste; `sortRank` = Server-Reihenfolge. Bio liegt in [LocalAuthorDetail]. */
@Entity(tableName = "LocalAuthor", indices = [Index("libraryId")])
data class LocalAuthor(
    @PrimaryKey val id: String,
    val libraryId: String,
    val name: String,
    val numBooks: Int?,
    val imagePath: String?,
    val sortRank: Int,
) {
    fun toItem() = AbsLibraryAuthorListItem(id = id, name = name, numBooks = numBooks, imagePath = imagePath)

    companion object {
        fun from(libraryId: String, item: AbsLibraryAuthorListItem, sortRank: Int) =
            LocalAuthor(item.id, libraryId, item.name, item.numBooks, item.imagePath, sortRank)
    }
}

/** iOS: `LocalAuthorDetail` — getrennt von [LocalAuthor], damit Browse-Reloads die Bio nicht verwerfen. */
@Entity(tableName = "LocalAuthorDetail")
data class LocalAuthorDetail(
    @PrimaryKey val id: String,
    val libraryId: String,
    val authorDescription: String?,
)

/** iOS: `LocalNarrator` — Sprecher einer Browse-Liste (+ Cover-Item als Feld). */
@Entity(tableName = "LocalNarrator", indices = [Index("libraryId")])
data class LocalNarrator(
    @PrimaryKey val id: String,
    val libraryId: String,
    val name: String,
    val numBooks: Int?,
    val coverItemId: String? = null,
) {
    fun toItem() = AbsLibraryNarratorListItem(id = id, name = name, numBooks = numBooks)

    companion object {
        fun from(libraryId: String, item: AbsLibraryNarratorListItem) = LocalNarrator(item.id, libraryId, item.name, item.numBooks)
    }
}

/**
 * iOS: `LocalBook` — Bücher-/eBook-/Podcast-Show-"Server-Kopie", eine Zeile pro `libraryItemId`.
 * Core-Felder für Sortierung/Anzeige echt, restliche Tiefe als JSON-Blob. [detailBlob] = erweiterte
 * Detail-Antwort (`?expanded=1`), bewusst getrennt vom Katalog-Blob.
 */
@Entity(tableName = "LocalBook", indices = [Index("libraryId")])
data class LocalBook(
    @PrimaryKey val id: String,
    val libraryId: String?,
    val title: String,
    val authorName: String,
    val addedAt: Long?,
    val updatedAt: Long?,
    val duration: Double,
    val isUsableLibraryCatalogRow: Boolean,
    val isUsableEbookListRow: Boolean,
    /** Katalogfilter „eBook“ (rein oder supplementär) — aus Server-Metadaten beim Upsert. */
    val catalogHasEbook: Boolean = false,
    /** Hörbuch mit supplementärem eBook — Cover-Badge. */
    val catalogHasSupplementaryEbook: Boolean = false,
    /** iOS-Schema-V1-Altlast, ungenutzt — Spalte bleibt für Parität. */
    val isEbookSupplementary: Boolean = false,
    val blob: String,
    val detailBlob: String? = null,
) {
    /** iOS: `apply(_:)` — Katalog-Felder aktualisieren; eBook-Flags werden nur ODER-verknüpft. */
    fun applying(book: AbsBook): LocalBook = copy(
        libraryId = book.libraryId,
        title = book.displayTitle,
        authorName = book.displayAuthorsCardLine,
        addedAt = book.addedAt,
        updatedAt = book.updatedAt,
        duration = book.totalDuration,
        isUsableLibraryCatalogRow = book.isUsableLibraryCatalogRow,
        isUsableEbookListRow = book.isUsableEbookListRow,
        catalogHasEbook = book.matchesBooksEbookCatalogFilter || catalogHasEbook,
        catalogHasSupplementaryEbook = book.isCatalogSupplementaryEbook || catalogHasSupplementaryEbook,
        blob = encodeBook(book) ?: blob,
    )

    /** iOS: `applyDetail(_:)`. */
    fun applyingDetail(book: AbsBook): LocalBook = copy(
        detailBlob = encodeBook(book),
        catalogHasEbook = book.matchesBooksEbookCatalogFilter || catalogHasEbook,
        catalogHasSupplementaryEbook = book.isCatalogSupplementaryEbook || catalogHasSupplementaryEbook,
    )

    fun toAbsBook(): AbsBook? = decodeBook(blob)

    fun toAbsBookDetail(): AbsBook? = detailBlob?.let(::decodeBook)

    companion object {
        fun from(book: AbsBook) = LocalBook(
            id = book.id,
            libraryId = book.libraryId,
            title = book.displayTitle,
            authorName = book.displayAuthorsCardLine,
            addedAt = book.addedAt,
            updatedAt = book.updatedAt,
            duration = book.totalDuration,
            isUsableLibraryCatalogRow = book.isUsableLibraryCatalogRow,
            isUsableEbookListRow = book.isUsableEbookListRow,
            catalogHasEbook = book.matchesBooksEbookCatalogFilter,
            catalogHasSupplementaryEbook = book.isCatalogSupplementaryEbook,
            isEbookSupplementary = false,
            blob = encodeBook(book) ?: "",
        )

        fun encodeBook(book: AbsBook): String? = runCatching { AbsJson.encoder.encodeToString(AbsBookSerializer, book) }.getOrNull()

        fun decodeBook(text: String): AbsBook? =
            if (text.isEmpty()) null else runCatching { AbsJson.decoder.decodeFromString(AbsBookSerializer, text) }.getOrNull()
    }
}

/** iOS: `LocalCatalogListState` — Filter/Sortierung/Gesamtzahl der zuletzt gecachten Katalogseite. */
@Entity(tableName = "LocalCatalogListState")
data class LocalCatalogListState(
    @PrimaryKey val libraryId: String,
    val sortField: String,
    val ascending: Boolean,
    val filterKey: String?,
    val total: Int,
)

/** iOS: `LocalCatalogEntry` — Reihenfolge-Index der zuletzt gecachten Katalogseite (Key `"$libraryId|$rank"`). */
@Entity(tableName = "LocalCatalogEntry", indices = [Index("libraryId"), Index("bookId")])
data class LocalCatalogEntry(
    @PrimaryKey val compositeKey: String,
    val libraryId: String,
    val rank: Int,
    val bookId: String,
) {
    companion object {
        fun of(libraryId: String, rank: Int, bookId: String) = LocalCatalogEntry("$libraryId|$rank", libraryId, rank, bookId)
    }
}

/** iOS: `LocalSeriesListState`. */
@Entity(tableName = "LocalSeriesListState")
data class LocalSeriesListState(
    @PrimaryKey val libraryId: String,
    val sortField: String,
    val descending: Boolean,
    val total: Int,
)

/** iOS: `LocalSeries` — referenziert Bücher nur über [bookIds] (geteilte [LocalBook]-Tabelle). */
@Entity(tableName = "LocalSeries", indices = [Index("libraryId")])
data class LocalSeries(
    @PrimaryKey val id: String,
    val libraryId: String,
    val name: String,
    val bookIds: List<String>,
    val sortRank: Int,
) {
    fun toItem(booksById: Map<String, AbsBook>): AbsLibrarySeriesListItem {
        val books = bookIds.mapNotNull { booksById[it] }
        return AbsLibrarySeriesListItem(id = id, name = name, books = books.ifEmpty { null })
    }

    companion object {
        fun from(libraryId: String, item: AbsLibrarySeriesListItem, sortRank: Int) =
            LocalSeries(item.id, libraryId, item.name, (item.books ?: emptyList()).map { it.id }, sortRank)
    }
}

/** iOS: `LocalCollectionListState` — Cache-Existenz-/Zähler-Marker (Sammlungen = ein Voll-Fetch). */
@Entity(tableName = "LocalCollectionListState")
data class LocalCollectionListState(
    @PrimaryKey val libraryId: String,
    val total: Int,
)

/** iOS: `LocalCollection` — Bücher nur über [bookIds]. */
@Entity(tableName = "LocalCollection", indices = [Index("libraryId")])
data class LocalCollection(
    @PrimaryKey val id: String,
    val libraryId: String,
    val name: String,
    val collectionDescription: String?,
    val bookIds: List<String>,
    val createdAt: Double?,
    val lastUpdate: Double?,
) {
    fun toItem(booksById: Map<String, AbsBook>): AbsLibraryCollectionListItem {
        val books = bookIds.mapNotNull { booksById[it] }
        return AbsLibraryCollectionListItem(
            id = id, name = name, description = collectionDescription, books = books.ifEmpty { null },
            createdAt = createdAt, lastUpdate = lastUpdate,
        )
    }

    companion object {
        fun from(libraryId: String, item: AbsLibraryCollectionListItem) = LocalCollection(
            id = item.id, libraryId = libraryId, name = item.name, collectionDescription = item.description,
            bookIds = (item.books ?: emptyList()).map { it.id }, createdAt = item.createdAt, lastUpdate = item.lastUpdate,
        )
    }
}

/** iOS: `LocalPodcastEpisodeListState` — `pagingFromRecentAPI = false` markiert den Expand-Fallback. */
@Entity(tableName = "LocalPodcastEpisodeListState")
data class LocalPodcastEpisodeListState(
    @PrimaryKey val libraryId: String,
    val total: Int,
    val pagingFromRecentAPI: Boolean,
)

/** iOS: `LocalPodcastEpisode` — Unique-Key `progressLookupKey` (`"$libraryItemId-$episodeId"`). */
@Entity(tableName = "LocalPodcastEpisode", indices = [Index("libraryId")])
data class LocalPodcastEpisode(
    @PrimaryKey val progressLookupKey: String,
    val libraryId: String,
    val libraryItemId: String,
    val episodeId: String,
    val episodeTitle: String,
    val showTitle: String,
    val authorLine: String,
    val duration: Double,
    val publishedAt: Long?,
    val rank: Int,
) {
    fun toItem() = AbsPodcastEpisodeListItem(
        libraryItemId = libraryItemId, libraryId = libraryId, episodeId = episodeId, episodeTitle = episodeTitle,
        showTitle = showTitle, authorLine = authorLine, duration = duration, publishedAt = publishedAt,
    )

    companion object {
        fun from(libraryId: String, item: AbsPodcastEpisodeListItem, rank: Int) = LocalPodcastEpisode(
            progressLookupKey = item.progressLookupKey, libraryId = libraryId, libraryItemId = item.libraryItemId,
            episodeId = item.episodeId, episodeTitle = item.episodeTitle, showTitle = item.showTitle,
            authorLine = item.authorLine, duration = item.duration, publishedAt = item.publishedAt, rank = rank,
        )
    }
}

/** iOS: `LocalPodcastShowListState`. */
@Entity(tableName = "LocalPodcastShowListState")
data class LocalPodcastShowListState(
    @PrimaryKey val libraryId: String,
    val sortField: String,
    val ascending: Boolean,
    val total: Int,
)

/** iOS: `LocalPodcastShowEntry` — Reihenfolge-Index der Show-Liste (Shows liegen in [LocalBook]). */
@Entity(tableName = "LocalPodcastShowEntry", indices = [Index("libraryId")])
data class LocalPodcastShowEntry(
    @PrimaryKey val compositeKey: String,
    val libraryId: String,
    val rank: Int,
    val bookId: String,
) {
    companion object {
        fun of(libraryId: String, rank: Int, bookId: String) = LocalPodcastShowEntry("$libraryId|$rank", libraryId, rank, bookId)
    }
}

/** iOS: `LocalHomeShelfSectionDTO` — kodierbarer Spiegel von [AbsStartShelfSection]. */
@Serializable
internal data class LocalHomeShelfSectionDTO(
    val id: String,
    val category: String,
    val displayTitle: String,
    val books: List<AbsBook> = emptyList(),
    val podcastEpisodes: List<AbsPodcastEpisodeListItem> = emptyList(),
    val authors: List<AbsAuthorShelfEntity> = emptyList(),
    val series: List<AbsLibrarySeriesListItem> = emptyList(),
) {
    fun toSection() = AbsStartShelfSection(
        id = id, category = category, displayTitle = displayTitle, books = books,
        podcastEpisodes = podcastEpisodes, authors = authors, series = series,
    )

    companion object {
        fun from(s: AbsStartShelfSection) = LocalHomeShelfSectionDTO(
            s.id, s.category, s.displayTitle, s.books, s.podcastEpisodes, s.authors, s.series,
        )
    }
}

/** iOS: `LocalHomeShelvesSnapshot` — Home-Regale als ein Voll-Snapshot pro Bibliothek. */
@Entity(tableName = "LocalHomeShelvesSnapshot")
data class LocalHomeShelvesSnapshot(
    @PrimaryKey val libraryId: String,
    val blob: String,
) {
    fun toSections(): List<AbsStartShelfSection>? = LocalBlobCodec.decodeShelves(blob)

    companion object {
        fun encode(sections: List<AbsStartShelfSection>): String? = LocalBlobCodec.encodeShelves(sections)
    }
}

/** iOS: `LocalEbookContinueEntry` — lokal injizierte eBook-Continue-Regalzeilen (`kind` = reading/series). */
@Entity(tableName = "LocalEbookContinueEntry", indices = [Index("libraryId")])
data class LocalEbookContinueEntry(
    @PrimaryKey val compositeKey: String,
    val libraryId: String,
    val kind: String,
    val rank: Int,
    val bookId: String,
) {
    companion object {
        const val KIND_READING = "reading"
        const val KIND_SERIES = "series"

        fun of(libraryId: String, kind: String, rank: Int, bookId: String) =
            LocalEbookContinueEntry("$libraryId|$kind|$rank", libraryId, kind, rank, bookId)
    }
}

/** iOS: `LocalListeningStatsSnapshot` — Rohantwort `/api/me/listening-stats`, ein Datensatz pro Store. */
@Entity(tableName = "LocalListeningStatsSnapshot")
data class LocalListeningStatsSnapshot(
    @PrimaryKey val id: String = "stats",
    val fetchedAt: Long,
    val blob: String,
)

/**
 * iOS: `LocalAchievementState` — Level-Achievement je `ListeningAchievementKind.rawValue`. Android
 * führt `kind` als String (der Stats-Port mappt auf seinen Enum).
 */
@Entity(tableName = "LocalAchievementState")
data class LocalAchievementState(
    @PrimaryKey val kind: String,
    val currentValue: Int,
    val savedAt: Long?,
)

/** iOS: `LocalLibrariesSnapshot` — Account-weite Bibliotheksliste als Blob. */
@Entity(tableName = "LocalLibrariesSnapshot")
data class LocalLibrariesSnapshot(
    @PrimaryKey val id: String = "libraries",
    val fetchedAt: Long,
    val blob: String,
) {
    fun toLibraries(): List<AbsLibrary>? = runCatching { AbsJson.decoder.decodeFromString(serializer, blob) }.getOrNull()

    companion object {
        private val serializer = ListSerializer(AbsLibrarySerializer)

        fun encode(libraries: List<AbsLibrary>): String? = runCatching { AbsJson.encoder.encodeToString(serializer, libraries) }.getOrNull()
    }
}

/** iOS: `LocalListeningSessionDTO` — kodierbarer Spiegel von [AbsListeningSession]. */
@Serializable
internal data class LocalListeningSessionDTO(
    val id: String,
    val libraryItemId: String,
    val bookId: String? = null,
    val episodeId: String? = null,
    val duration: Double,
    val startTime: Double,
    val currentTime: Double,
    val timeListening: Int,
    val startedAt: Long,
    val updatedAt: Long,
) {
    fun toSession() = AbsListeningSession(
        id = id, libraryItemId = libraryItemId, bookId = bookId, episodeId = episodeId, duration = duration,
        startTime = startTime, currentTime = currentTime, timeListening = timeListening, startedAt = startedAt, updatedAt = updatedAt,
    )

    companion object {
        fun from(s: AbsListeningSession) = LocalListeningSessionDTO(
            s.id, s.libraryItemId, s.bookId, s.episodeId, s.duration, s.startTime, s.currentTime, s.timeListening, s.startedAt, s.updatedAt,
        )
    }
}

/** iOS: `LocalListeningSessionsSnapshot` — Hör-Sitzungen je Medium, Key `libraryItemId|episodeId`. */
@Entity(tableName = "LocalListeningSessionsSnapshot")
data class LocalListeningSessionsSnapshot(
    @PrimaryKey val compositeKey: String,
    val libraryItemId: String,
    val episodeId: String,
    val fetchedAt: Long,
    val blob: String,
) {
    fun toSessions(): List<AbsListeningSession>? = LocalBlobCodec.decodeSessions(blob)

    companion object {
        fun makeKey(libraryItemId: String, episodeId: String?): String =
            "${libraryItemId.swiftTrim()}|${(episodeId ?: "").swiftTrim()}"

        fun encode(sessions: List<AbsListeningSession>): String? = LocalBlobCodec.encodeSessions(sessions)
    }
}

/** iOS: `LocalPodcastRssFeedSnapshot` — Roh-RSS-Feed je Sendung. */
@Entity(tableName = "LocalPodcastRssFeedSnapshot")
data class LocalPodcastRssFeedSnapshot(
    @PrimaryKey val showId: String,
    val fetchedAt: Long,
    val blob: ByteArray,
) {
    override fun equals(other: Any?) = other is LocalPodcastRssFeedSnapshot && other.showId == showId &&
        other.fetchedAt == fetchedAt && other.blob.contentEquals(blob)

    override fun hashCode() = showId.hashCode()
}

/** Room-Konverter für `List<String>`-Spalten (iOS: SwiftData-Arrays) — als JSON-Text. */
class LocalLibraryConverters {
    private val serializer = ListSerializer(String.serializer())

    @TypeConverter
    fun fromStringList(value: List<String>): String = AbsJson.encoder.encodeToString(serializer, value)

    @TypeConverter
    fun toStringList(value: String): List<String> =
        runCatching { AbsJson.decoder.decodeFromString(serializer, value) }.getOrDefault(emptyList())
}

/** iOS: `LocalLibrarySchema`. */
object LocalLibrarySchema {
    /** Room-Schema-Version (iOS: `LocalLibrarySchemaV4` — Android startet ohne V1–V3-Altlasten bei 1). */
    const val ROOM_VERSION = 1

    /** Logische Meta-Version in [LocalStoreMeta] — Backfill der eBook-Katalog-Flags (iOS: 3). */
    const val ebookCatalogFlagsMetaVersion = 3
}

/**
 * JSON-Kodierung der DTO-Blobs — bewusst außerhalb der Entities: Room-KSP sieht die vom
 * Serialization-Plugin generierten `serializer()` nicht und bricht sonst ab.
 */
internal object LocalBlobCodec {
    private val shelvesSerializer by lazy { ListSerializer(LocalHomeShelfSectionDTO.serializer()) }
    private val sessionsSerializer by lazy { ListSerializer(LocalListeningSessionDTO.serializer()) }

    fun encodeShelves(sections: List<AbsStartShelfSection>): String? =
        runCatching { AbsJson.encoder.encodeToString(shelvesSerializer, sections.map(LocalHomeShelfSectionDTO::from)) }.getOrNull()

    fun decodeShelves(blob: String): List<AbsStartShelfSection>? =
        runCatching { AbsJson.decoder.decodeFromString(shelvesSerializer, blob).map { it.toSection() } }.getOrNull()

    fun encodeSessions(sessions: List<AbsListeningSession>): String? =
        runCatching { AbsJson.encoder.encodeToString(sessionsSerializer, sessions.map(LocalListeningSessionDTO::from)) }.getOrNull()

    fun decodeSessions(blob: String): List<AbsListeningSession>? =
        runCatching { AbsJson.decoder.decodeFromString(sessionsSerializer, blob).map { it.toSession() } }.getOrNull()
}
