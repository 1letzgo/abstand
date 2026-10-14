package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsPodcastDirectorySearchHit
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsRecentPodcastEpisodeDTO
import de.letzgo.abstand.data.SwiftJson
import de.letzgo.abstand.data.absSanitizedLibraryPathSegment
import de.letzgo.abstand.data.localizedCaseInsensitiveCompare
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.store.LocalLibraryQueries
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.net.URI

/**
 * iOS: `PodcastCatalogSortField` (CatalogBrowseTypes.swift) — Sortierung der Sendungs-Leiste
 * (`GET …/libraries/:id/items`, Podcast-Felder des Servers). `name` = iOS-`rawValue`.
 */
enum class PodcastCatalogSortField(val menuTitle: String, val apiSortParameter: String) {
    title("Title", "media.metadata.title"),
    author("Author", "media.metadata.author"),
    numEpisodes("Number of episodes", "media.numTracks"),
    addedAt("Date added", "addedAt"),
    size("Total size", "size"),
    birthtimeMs("File created", "birthtimeMs"),
    mtimeMs("File modified", "mtimeMs"),
    random("Random", "random");

    /** iOS: `AbstandSortMenuField.suppressesSortOrderPicker`. */
    val suppressesSortOrderPicker: Boolean get() = this == random
}

/** iOS: `PodcastEpisodeSortField` — Folgen einer gewählten Sendung (lokal sortiert). */
enum class PodcastEpisodeSortField(val menuTitle: String) {
    publishedAt("Release date"),
    title("Title"),
    duration("Duration"),
}

/** iOS: `PodcastCatalogStripSection` — IDs der festen Einträge der Podcast-Leiste. */
object PodcastCatalogStripSection {
    const val search = "__search__"
    const val newEpisodes = "__new__"
}

/** iOS: `PodcastAutoDownloadInterval` (PodcastAutoDownloadSchedule.swift) — Cron-Presets für `autoDownloadSchedule`. */
enum class PodcastAutoDownloadInterval(val label: String, val cronExpression: String) {
    everyHour("Every hour", "0 * * * *"),
    every6Hours("Every 6 hours", "0 */6 * * *"),
    every12Hours("Every 12 hours", "0 */12 * * *"),
    daily("Daily", "0 0 * * *"),
    weekly("Weekly", "0 0 * * 1");

    companion object {
        val default: PodcastAutoDownloadInterval = daily

        /**
         * Cron → Preset. Abweichung von iOS: Die Stunden-Felder werden **vor** „daily“ geprüft —
         * iOS meldet für Cron „5 alle-6-Stunden“ fälschlich „Daily“ (Stunden-Zweige dort unerreichbar).
         */
        fun from(cron: String?): PodcastAutoDownloadInterval {
            val normalized = (cron ?: "").swiftTrim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
            entries.firstOrNull { it.cronExpression == normalized }?.let { return it }
            val parts = normalized.split(" ").filter { it.isNotEmpty() }
            if (parts.size < 5) return default
            val hour = parts[1]
            val dom = parts[2]
            val month = parts[3]
            val dow = parts[4]
            if (dom == "*" && month == "*" && dow != "*") return weekly
            if (hour.startsWith("*/12")) return every12Hours
            if (hour.startsWith("*/6")) return every6Hours
            if (hour == "*") return everyHour
            if (dom == "*" && month == "*") return daily
            return default
        }
    }
}

/**
 * Reine Podcast-Logik (iOS: statische Helfer in `AppModel.swift` / `AppModelPodcastDirectory.swift`),
 * ohne Zustand — unit-testbar.
 */
object PodcastLogic {
    /** iOS: `podcastLibraryPage`-Seitengröße von `/recent-episodes`. */
    const val recentEpisodesPageLimit = 40
    /** iOS: `catalogPrefetchItemsFromEnd`. */
    const val catalogPrefetchItemsFromEnd = 8
    /** iOS: `reloadPodcastShowsCatalog` — `limit: 120`. */
    const val showsCatalogLimit = 120

    // MARK: Sortierung

    /** iOS: `migratePodcastCatalogSortField(raw:)` (inkl. Bücher-Katalog-Rohwerte). */
    fun migratePodcastCatalogSortField(raw: String): PodcastCatalogSortField {
        PodcastCatalogSortField.entries.firstOrNull { it.name == raw }?.let { return it }
        migratePodcastCatalogSortFromBookCatalog(raw)?.let { return it }
        return when (raw) {
            "media.metadata.title" -> PodcastCatalogSortField.title
            "media.metadata.author", "media.metadata.authorName", "media.metadata.authorNameLF" -> PodcastCatalogSortField.author
            "media.numTracks", "media.duration" -> PodcastCatalogSortField.numEpisodes
            "addedAt" -> PodcastCatalogSortField.addedAt
            "size" -> PodcastCatalogSortField.size
            "birthtimeMs" -> PodcastCatalogSortField.birthtimeMs
            "mtimeMs" -> PodcastCatalogSortField.mtimeMs
            "random" -> PodcastCatalogSortField.random
            else -> PodcastCatalogSortField.title
        }
    }

    /** iOS: `migratePodcastCatalogSortFromBookCatalog` — `null`, wenn [raw] kein `CatalogSortField` ist. */
    fun migratePodcastCatalogSortFromBookCatalog(raw: String): PodcastCatalogSortField? = when (raw) {
        "authorName", "authorNameLF" -> PodcastCatalogSortField.author
        "addedAt" -> PodcastCatalogSortField.addedAt
        "size" -> PodcastCatalogSortField.size
        "birthtimeMs" -> PodcastCatalogSortField.birthtimeMs
        "mtimeMs" -> PodcastCatalogSortField.mtimeMs
        "duration" -> PodcastCatalogSortField.numEpisodes
        "random" -> PodcastCatalogSortField.random
        "title", "publishedYear", "progress", "progressCreatedAt", "progressFinishedAt" -> PodcastCatalogSortField.title
        else -> null
    }

    /** iOS: `sortPodcastEpisodesNewestFirst` — Datum absteigend, Gleichstand Titel absteigend. */
    fun sortEpisodesNewestFirst(rows: List<AbsPodcastEpisodeListItem>): List<AbsPodcastEpisodeListItem> =
        rows.sortedWith { a, b ->
            val pa = a.publishedAt ?: 0L
            val pb = b.publishedAt ?: 0L
            if (pa != pb) pb.compareTo(pa) else -localizedCaseInsensitiveCompare(a.episodeTitle, b.episodeTitle).coerceIn(-1, 1)
        }

    /** iOS: `sortPodcastShowEpisodes` — Folgen einer Sendung nach gewählter Sortierung; Gleichstand → Datum. */
    fun sortShowEpisodes(
        rows: List<AbsPodcastEpisodeListItem>,
        field: PodcastEpisodeSortField,
        descending: Boolean,
    ): List<AbsPodcastEpisodeListItem> = when (field) {
        PodcastEpisodeSortField.publishedAt -> sortEpisodesNewestFirst(rows).let { if (descending) it else it.reversed() }
        PodcastEpisodeSortField.title -> {
            val collator = LocalLibraryQueries.localizedStandardCollator()
            rows.sortedWith { a, b ->
                val order = collator.compare(a.episodeTitle, b.episodeTitle).coerceIn(-1, 1)
                if (order != 0) {
                    if (descending) -order else order
                } else {
                    (b.publishedAt ?: 0L).compareTo(a.publishedAt ?: 0L)
                }
            }
        }
        PodcastEpisodeSortField.duration -> rows.sortedWith { a, b ->
            if (a.duration != b.duration) {
                if (descending) b.duration.compareTo(a.duration) else a.duration.compareTo(b.duration)
            } else {
                (b.publishedAt ?: 0L).compareTo(a.publishedAt ?: 0L)
            }
        }
    }

    /** iOS: `unplayedEpisodesForNewFeed` — „New“ zeigt keine (lokal oder serverseitig) beendeten Folgen. */
    fun unplayedForNewFeed(
        rows: List<AbsPodcastEpisodeListItem>,
        isFinished: (progressKey: String) -> Boolean,
    ): List<AbsPodcastEpisodeListItem> = rows.filter { !isFinished(it.progressLookupKey) }

    /** iOS: `shouldPrefetchNextCatalogPage` — Zeile liegt in den letzten [fromEnd] Einträgen. */
    fun shouldPrefetchNextPage(currentItemId: String?, ids: List<String>, fromEnd: Int = catalogPrefetchItemsFromEnd): Boolean {
        if (currentItemId == null || ids.isEmpty()) return false
        val idx = ids.indexOf(currentItemId)
        if (idx < 0) return false
        return idx >= maxOf(0, ids.size - fromEnd)
    }

    // MARK: Folgen aus Show-Detail

    /** iOS: `fromDTO(…forceLibraryItemId:)` + dedupe + newest-first über alle `media.episodes`. */
    fun episodesFromShowDetail(
        episodes: List<AbsRecentPodcastEpisodeDTO>,
        show: de.letzgo.abstand.data.AbsBook,
        libraryId: String?,
    ): List<AbsPodcastEpisodeListItem> {
        val rows = episodes.mapNotNull {
            AbsPodcastEpisodeListItem.fromDTO(it, fallbackShow = show, libraryId = libraryId, forceLibraryItemId = show.id)
        }
        return sortEpisodesNewestFirst(AbsPodcastEpisodeListItem.dedupeRows(rows))
    }

    /**
     * iOS: `mergeNewPodcastLibraryEpisodesFromExpandedItem` — nur neue `progressLookupKey`s der
     * Sendung [showId] anhängen. `null` = nichts Neues.
     */
    fun mergeNewShowEpisodes(
        existing: List<AbsPodcastEpisodeListItem>,
        fetched: List<AbsPodcastEpisodeListItem>,
        showId: String,
    ): List<AbsPodcastEpisodeListItem>? {
        val seen = existing.mapTo(HashSet()) { it.progressLookupKey }
        val merged = existing.toMutableList()
        var added = 0
        for (row in fetched) {
            if (row.libraryItemId != showId) continue
            if (!seen.add(row.progressLookupKey)) continue
            merged.add(row)
            added++
        }
        if (added == 0) return null
        return sortEpisodesNewestFirst(AbsPodcastEpisodeListItem.dedupeRows(merged))
    }

    /** Titel-Schlüssel der Bibliotheks-Folgen (iOS: `loadPodcastDirectoryLibraryEpisodeTitles`). */
    fun libraryEpisodeTitleKeys(episodes: List<AbsRecentPodcastEpisodeDTO>): Set<String> =
        episodes.mapNotNull { it.title.swiftTrim().lowercase().ifEmpty { null } }.toSet()

    /** iOS: `podcastLibraryEpisodeCountLabel(for:)`. */
    fun episodeCountLabel(numTracks: Int?): String {
        val n = numTracks ?: 0
        return when {
            n == 1 -> "1 episode"
            n > 1 -> "$n episodes"
            else -> "0 episodes"
        }
    }

    // MARK: Feed-URLs

    /**
     * iOS: `normalizedPodcastFeedURL` — Schema/Host klein, Port, Pfad ohne abschließende `/`, Query
     * getrimmt. Ohne Host: komplett klein, abschließende `/` weg. `null` für leer.
     */
    fun normalizedPodcastFeedURL(raw: String?): String? {
        var s = (raw ?: "").swiftTrim()
        if (s.isEmpty()) return null
        val uri = runCatching { URI(s) }.getOrNull()
        val host = uri?.host?.lowercase()
        if (uri != null && !host.isNullOrEmpty()) {
            var path = uri.rawPath ?: ""
            while (path.endsWith("/")) path = path.dropLast(1)
            val port = if (uri.port >= 0) ":${uri.port}" else ""
            s = "${uri.scheme?.lowercase() ?: "https"}://$host$port$path"
            val q = uri.rawQuery?.swiftTrim()
            if (!q.isNullOrEmpty()) s += "?$q"
        } else {
            s = s.lowercase()
            while (s.endsWith("/")) s = s.dropLast(1)
        }
        return s
    }

    /** iOS: `extractPodcastFeedURL(fromItemJSON:)` — `feedUrl`/`feedURL`/`feed_url` in `media.metadata` & Co. */
    fun extractPodcastFeedURL(itemJson: String): String? {
        val root = runCatching { AbsJson.decoder.parseToJsonElement(itemJson) as? JsonObject }.getOrNull() ?: return null
        fun pick(dict: JsonObject?): String? {
            if (dict == null) return null
            for (key in listOf("feedUrl", "feedURL", "feed_url")) {
                val raw = SwiftJson.anyString(dict[key]) ?: continue
                normalizedPodcastFeedURL(raw)?.let { return it }
            }
            return null
        }
        pick(root["metadata"] as? JsonObject)?.let { return it }
        (root["media"] as? JsonObject)?.let { media ->
            pick(media["metadata"] as? JsonObject)?.let { return it }
            pick(media)?.let { return it }
        }
        return pick(root)
    }

    /** iOS: `podcastDirectoryEpisodeKey` — `<normalisierte Feed-URL>|<Folgen-ID>`. */
    fun directoryEpisodeKey(feedKey: String, episodeId: String): String = "$feedKey|$episodeId"

    // MARK: Abonnieren

    /** iOS: `buildPodcastSubscribeRequestBody` — Body für `POST /api/podcasts`. */
    fun buildSubscribeRequestBody(
        hit: AbsPodcastDirectorySearchHit,
        folderId: String,
        libraryId: String,
        folderFullPath: String,
    ): String {
        val rawTitle = hit.title.swiftTrim()
        val title = rawTitle.ifEmpty { "Podcast" }
        val segment = title.absSanitizedLibraryPathSegment()
        val folder = folderFullPath.swiftTrim()
        val path = if (folder.endsWith("/")) folder + segment else "$folder/$segment"
        fun s(v: String?) = JsonPrimitive((v ?: "").swiftTrim())
        val metadata = JsonObject(
            linkedMapOf<String, JsonElement>(
                "title" to JsonPrimitive(title),
                "author" to s(hit.artistName),
                "description" to s(hit.descriptionPlain),
                "releaseDate" to s(hit.releaseDate),
                "genres" to JsonArray((hit.genres ?: emptyList()).map { JsonPrimitive(it) }),
                "feedUrl" to s(hit.feedUrl),
                "imageUrl" to s(hit.cover),
                "itunesPageUrl" to s(hit.pageUrl),
                "itunesId" to s(hit.id),
                "itunesArtistId" to s(hit.artistId),
                "language" to JsonPrimitive(""),
                "explicit" to JsonPrimitive(hit.explicit ?: false),
                "type" to JsonPrimitive("episodic"),
            ),
        )
        val media = JsonObject(
            linkedMapOf(
                "metadata" to metadata,
                "autoDownloadEpisodes" to JsonPrimitive(true),
                "autoDownloadSchedule" to JsonPrimitive(PodcastAutoDownloadInterval.default.cronExpression),
            ),
        )
        return JsonObject(
            linkedMapOf(
                "path" to JsonPrimitive(path),
                "folderId" to JsonPrimitive(folderId),
                "libraryId" to JsonPrimitive(libraryId),
                "media" to media,
            ),
        ).toString()
    }

    /** Ein rohes Folgenobjekt als JSON-Array (Body für `download-episodes`). */
    fun singleEpisodeArrayBody(episodePayloadJSON: String): String {
        val obj = AbsJson.decoder.parseToJsonElement(episodePayloadJSON)
        return JsonArray(listOf(obj)).toString()
    }
}
