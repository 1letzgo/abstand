package de.letzgo.abstand.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.text.Collator
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

// iOS: ABSModels.swift (Teil 1: Auth, Fortschritt, Bibliotheken, Podcasts).
// Dekodierung über [SwiftObjectSerializer]: gleiche Pflicht-/Optional-/`try?`-Regeln wie die Swift-`init(from:)`.

/** iOS: `Double.rounded()` — kaufmännisch, bei .5 weg von null (Kotlin `Math.round` rundet zu +∞). */
internal fun Double.roundedSwift(): Double = if (this < 0) -Math.floor(-this + 0.5) else Math.floor(this + 0.5)

/** iOS: `localizedCaseInsensitiveCompare` (< 0 = `.orderedAscending`). */
internal fun localizedCaseInsensitiveCompare(a: String, b: String): Int =
    Collator.getInstance().apply { strength = Collator.SECONDARY }.compare(a, b)

// MARK: - Auth & User

/** iOS: `ABSLoginRequest`. */
@Serializable
data class AbsLoginRequest(val username: String, val password: String)

/** iOS: `ABSChangePasswordRequest`. */
@Serializable
data class AbsChangePasswordRequest(val password: String, val newPassword: String)

/** iOS: `ABSLoginResponse`. */
@Serializable(with = AbsLoginResponseSerializer::class)
data class AbsLoginResponse(
    val user: AbsUser,
    val userDefaultLibraryId: String?,
    val serverSettings: AbsServerSettings?,
)

object AbsLoginResponseSerializer : SwiftObjectSerializer<AbsLoginResponse>("ABSLoginResponse") {
    override fun decode(c: JObj) = AbsLoginResponse(
        user = c.obj("user", AbsUserSerializer),
        userDefaultLibraryId = c.stringOrNull("userDefaultLibraryId"),
        serverSettings = c.objOrNull("serverSettings", AbsServerSettingsSerializer),
    )
}

/** iOS: `ABSUser`. */
@Serializable(with = AbsUserSerializer::class)
data class AbsUser(
    val id: String,
    val username: String,
    /** Legacy-Token ohne Ablauf (serverseitig deprecated ab v2.26). */
    val token: String,
    /** Kurzlebiges JWT (Server-Default 1 h) — nur auf Servern mit neuem Auth-System. */
    val accessToken: String?,
    /** Rotierendes Refresh-Token — nur wenn der Request `x-return-tokens: true` bzw. `x-refresh-token` trug. */
    val refreshToken: String?,
    /** `guest`, `user`, oder `admin` (Audiobookshelf). */
    val type: String?,
    val mediaProgress: List<AbsUserMediaProgress>?,
    val bookmarks: List<AbsAudioBookmark>?,
) {
    val normalizedType: String get() = type?.swiftTrim()?.lowercase() ?: ""

    /** Bearer für API-Calls: neues Access-Token bevorzugt, sonst Legacy-Token (alte Server). */
    val effectiveBearerToken: String
        get() {
            val access = accessToken?.swiftTrim() ?: ""
            return access.ifEmpty { token }
        }

    val isRoot: Boolean get() = normalizedType == "root"

    /** Entspricht `User.isAdminOrUp` auf dem Server (`root` oder `admin`). */
    val isAdmin: Boolean get() = normalizedType.let { it == "admin" || it == "root" }
}

object AbsUserSerializer : SwiftObjectSerializer<AbsUser>("ABSUser") {
    override fun decode(c: JObj) = AbsUser(
        id = c.string("id"),
        username = c.string("username"),
        // Legacy-Token ist serverseitig deprecated (JWT-Umstellung ab v2.26) — fehlendes Feld darf Login/Authorize nicht hart brechen.
        token = c.stringOrNull("token") ?: "",
        accessToken = c.stringOrNull("accessToken"),
        refreshToken = c.stringOrNull("refreshToken"),
        type = c.stringOrNull("type"),
        mediaProgress = c.listOrNull("mediaProgress", AbsUserMediaProgressSerializer),
        bookmarks = c.listOrNull("bookmarks", AbsAudioBookmarkSerializer),
    )
}

/** iOS: `ABSAudioBookmark` — Lesezeichen (`POST/PATCH/DELETE …/api/me/item/:id/bookmark`). */
@Serializable(with = AbsAudioBookmarkSerializer::class)
data class AbsAudioBookmark(
    val libraryItemId: String,
    val title: String,
    val time: Int,
    val createdAt: Long? = null,
) {
    val id: String get() = "$libraryItemId-$time"
}

object AbsAudioBookmarkSerializer : SwiftObjectSerializer<AbsAudioBookmark>("ABSAudioBookmark") {
    override fun decode(c: JObj): AbsAudioBookmark {
        val time = c.tryInt("time") ?: c.tryDouble("time")?.roundedSwift()?.toInt() ?: 0
        // Swift: `if let s = try decodeIfPresent(Int64)` — Typfehler wirft (Double-Zweig nur bei fehlendem Key).
        val createdAt = c.longOrNull("createdAt") ?: c.doubleOrNull("createdAt")?.roundedSwift()?.toLong()
        return AbsAudioBookmark(
            libraryItemId = c.string("libraryItemId"),
            title = c.stringOrNull("title") ?: "",
            time = time,
            createdAt = createdAt,
        )
    }

    override fun encode(v: AbsAudioBookmark) = jsonObjectOf {
        put("libraryItemId", JsonPrimitive(v.libraryItemId))
        put("title", JsonPrimitive(v.title))
        put("time", JsonPrimitive(v.time))
        putIfPresent("createdAt", v.createdAt)
    }
}

/** iOS: `ABSCreateBookmarkRequest`. */
@Serializable
data class AbsCreateBookmarkRequest(val time: Int, val title: String)

/** iOS: `ABSUserMediaProgress`. */
@Serializable(with = AbsUserMediaProgressSerializer::class)
data class AbsUserMediaProgress(
    /** Primärschlüssel der Progress-Zeile auf dem Server — `DELETE /api/me/progress/:id` erwartet genau diesen Wert. */
    val mediaProgressServerId: String? = null,
    val libraryItemId: String,
    val episodeId: String?,
    val duration: Double,
    val progress: Double,
    val currentTime: Double,
    val isFinished: Boolean,
    val lastUpdate: Long?,
    /** E-Book-Lesefortschritt 0…1 (ABS-Web-Reader speichert ihn in derselben Progress-Zeile). */
    val ebookProgress: Double? = null,
    /** Lesezeichen des Web-Readers (epub.js-CFI) — wird nur durchgereicht, nicht interpretiert. */
    val ebookLocation: String? = null,
) {
    /** Schlüssel für `AppModel.progressByItemId` (Episoden: `libraryItemId-episodeId`). */
    val progressLookupKey: String
        get() {
            val e = episodeId?.swiftTrim() ?: ""
            if (e.isNotEmpty()) return "$libraryItemId-$e"
            return libraryItemId
        }

    /**
     * ABS `DELETE /api/me/progress/:id` — moderner Server erwartet die DB-UUID (`MediaProgress.id`).
     * Fallback auf Lookup-Key nur für Legacy; `deleteMediaProgressForLibraryItem` holt die UUID per GET nach.
     */
    val idForMediaProgressDeleteRequest: String
        get() = mediaProgressServerId?.takeIf { it.isNotEmpty() } ?: progressLookupKey
}

object AbsUserMediaProgressSerializer : SwiftObjectSerializer<AbsUserMediaProgress>("ABSUserMediaProgress") {
    override fun decode(c: JObj): AbsUserMediaProgress {
        val episodeId = c.stringOrNull("episodeId")
        val duration = c.doubleOrNull("duration") ?: 0.0
        val progress = c.doubleOrNull("progress") ?: 0.0
        val currentTime = c.doubleOrNull("currentTime") ?: 0.0
        val isFinished = c.boolOrNull("isFinished") ?: false
        val lastUpdate = c.longOrNull("lastUpdate")
        val ebookProgress = c.tryDouble("ebookProgress")
        val ebookLocation = c.tryString("ebookLocation")

        val explicit = c.stringOrNull("libraryItemId")
        val rawId = c.stringOrNull("id")
        val trimmedId = rawId?.swiftTrim()
        val serverId = trimmedId?.takeIf { it.isNotEmpty() }
        val libraryItemId = when {
            explicit != null && explicit.isNotEmpty() -> explicit
            rawId != null && rawId.isNotEmpty() -> rawId.indexOf("-ep_").let { if (it >= 0) rawId.substring(0, it) else rawId }
            else -> SwiftJson.mismatch("libraryItemId", "mediaProgress missing libraryItemId/id")
        }
        return AbsUserMediaProgress(
            mediaProgressServerId = serverId,
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
    }

    override fun encode(v: AbsUserMediaProgress) = jsonObjectOf {
        if (!v.mediaProgressServerId.isNullOrEmpty()) put("id", JsonPrimitive(v.mediaProgressServerId))
        put("libraryItemId", JsonPrimitive(v.libraryItemId))
        putIfPresent("episodeId", v.episodeId)
        put("duration", JsonPrimitive(v.duration))
        put("progress", JsonPrimitive(v.progress))
        put("currentTime", JsonPrimitive(v.currentTime))
        put("isFinished", JsonPrimitive(v.isFinished))
        putIfPresent("lastUpdate", v.lastUpdate)
        putIfPresent("ebookProgress", v.ebookProgress)
        putIfPresent("ebookLocation", v.ebookLocation)
    }
}

/** iOS: `ABSLibrariesResponse`. */
@Serializable(with = AbsLibrariesResponseSerializer::class)
data class AbsLibrariesResponse(val libraries: List<AbsLibrary>)

object AbsLibrariesResponseSerializer : SwiftObjectSerializer<AbsLibrariesResponse>("ABSLibrariesResponse") {
    override fun decode(c: JObj) = AbsLibrariesResponse(c.list("libraries", AbsLibrarySerializer))
}

/** iOS: `ABSLibrary`. */
@Serializable(with = AbsLibrarySerializer::class)
data class AbsLibrary(
    val id: String,
    val name: String,
    val mediaType: String? = "book",
    /** Server-Reihenfolge in den Einstellungen (siehe `POST /api/libraries/order`). */
    val displayOrder: Int? = null,
) {
    val isBookLibrary: Boolean get() = (mediaType ?: "book").lowercase() == "book"
    val isPodcastLibrary: Boolean get() = (mediaType ?: "").lowercase() == "podcast"
    val displayOrderOrZero: Int get() = displayOrder ?: 0
}

object AbsLibrarySerializer : SwiftObjectSerializer<AbsLibrary>("ABSLibrary") {
    override fun decode(c: JObj) = AbsLibrary(
        id = c.string("id"),
        name = c.string("name"),
        mediaType = c.stringOrNull("mediaType"),
        displayOrder = c.intOrNull("displayOrder"),
    )

    override fun encode(v: AbsLibrary) = jsonObjectOf {
        put("id", JsonPrimitive(v.id))
        put("name", JsonPrimitive(v.name))
        putIfPresent("mediaType", v.mediaType)
        putIfPresent("displayOrder", v.displayOrder)
    }
}

// MARK: - Podcast directory (iTunes search) & library folders

/** iOS: `ABSLibraryFolderRow`. */
@Serializable(with = AbsLibraryFolderRowSerializer::class)
data class AbsLibraryFolderRow(val id: String, val fullPath: String)

object AbsLibraryFolderRowSerializer : SwiftObjectSerializer<AbsLibraryFolderRow>("ABSLibraryFolderRow") {
    override fun decode(c: JObj) = AbsLibraryFolderRow(c.string("id"), c.string("fullPath"))
}

/** iOS: `ABSLibraryDetailFoldersPayload` — nur die Felder, die wir für `POST /api/podcasts` brauchen. */
@Serializable(with = AbsLibraryDetailFoldersPayloadSerializer::class)
data class AbsLibraryDetailFoldersPayload(val folders: List<AbsLibraryFolderRow>?)

object AbsLibraryDetailFoldersPayloadSerializer : SwiftObjectSerializer<AbsLibraryDetailFoldersPayload>("ABSLibraryDetailFoldersPayload") {
    override fun decode(c: JObj) = AbsLibraryDetailFoldersPayload(c.listOrNull("folders", AbsLibraryFolderRowSerializer))
}

/** iOS: `ABSPodcastDirectorySearchHit` — Treffer von `GET /api/search/podcast` (iTunes, vgl. `PodcastFinder`). */
@Serializable(with = AbsPodcastDirectorySearchHitSerializer::class)
data class AbsPodcastDirectorySearchHit(
    val id: String,
    val artistId: String? = null,
    val title: String,
    val artistName: String? = null,
    val descriptionPlain: String? = null,
    val releaseDate: String? = null,
    val genres: List<String>? = null,
    val cover: String? = null,
    val trackCount: Int? = null,
    val feedUrl: String? = null,
    val pageUrl: String? = null,
    val explicit: Boolean? = null,
)

object AbsPodcastDirectorySearchHitSerializer : SwiftObjectSerializer<AbsPodcastDirectorySearchHit>("ABSPodcastDirectorySearchHit") {
    private fun stringish(c: JObj, key: String): String? = c.tryString(key) ?: c.tryLong(key)?.toString()

    override fun decode(c: JObj) = AbsPodcastDirectorySearchHit(
        id = stringish(c, "id") ?: "",
        artistId = stringish(c, "artistId"),
        title = c.tryString("title")?.swiftTrim() ?: "",
        artistName = c.tryString("artistName"),
        descriptionPlain = c.tryString("descriptionPlain") ?: c.tryString("description"),
        releaseDate = c.tryString("releaseDate"),
        genres = c.tryList("genres", ElementDecoder.string),
        cover = c.tryString("cover"),
        trackCount = c.tryInt("trackCount") ?: c.tryString("trackCount")?.toIntOrNull(),
        feedUrl = c.tryString("feedUrl"),
        pageUrl = c.tryString("pageUrl"),
        explicit = c.tryBool("explicit"),
    )
}

// MARK: - Paging

/** iOS: `ABSPage<T>` — `results` oder (Autoren-Endpunkt) `authors`. */
data class AbsPage<T>(val results: List<T>, val total: Int, val page: Int) {
    companion object {
        fun <T> serializer(element: ElementDecoder<T>) = object : SwiftObjectSerializer<AbsPage<T>>("ABSPage") {
            override fun decode(c: JObj) = AbsPage(
                results = c.listOrNull("results", element) ?: c.listOrNull("authors", element) ?: emptyList(),
                total = c.int("total"),
                page = c.int("page"),
            )
        }
    }
}

// MARK: - Podcast episodes (library recent)

/** iOS: `ABSRecentEpisodesResponse`. */
@Serializable(with = AbsRecentEpisodesResponseSerializer::class)
data class AbsRecentEpisodesResponse(
    val episodes: List<AbsRecentPodcastEpisodeDTO>,
    val total: Int,
    val limit: Int,
    val page: Int,
)

object AbsRecentEpisodesResponseSerializer : SwiftObjectSerializer<AbsRecentEpisodesResponse>("ABSRecentEpisodesResponse") {
    private fun intish(c: JObj, key: String): Int? = c.tryInt(key) ?: c.tryString(key)?.toIntOrNull()

    override fun decode(c: JObj): AbsRecentEpisodesResponse {
        val episodes = c.tryList("episodes", AbsRecentPodcastEpisodeDTOSerializer) ?: emptyList()
        return AbsRecentEpisodesResponse(
            episodes = episodes,
            total = intish(c, "total") ?: episodes.size,
            limit = intish(c, "limit") ?: 0,
            page = intish(c, "page") ?: 0,
        )
    }
}

/** iOS: `ABSRecentPodcastEpisodeDTO`. */
@Serializable(with = AbsRecentPodcastEpisodeDTOSerializer::class)
data class AbsRecentPodcastEpisodeDTO(
    val libraryItemId: String,
    val id: String,
    val title: String,
    val subtitle: String?,
    val description: String?,
    val pubDate: String?,
    val duration: Double?,
    val publishedAt: Long?,
    val podcast: AbsRecentEpisodePodcastNest?,
)

object AbsRecentPodcastEpisodeDTOSerializer : SwiftObjectSerializer<AbsRecentPodcastEpisodeDTO>("ABSRecentPodcastEpisodeDTO") {
    override fun decode(c: JObj): AbsRecentPodcastEpisodeDTO {
        val rawTitle = c.tryString("title")?.swiftTrim() ?: ""
        return AbsRecentPodcastEpisodeDTO(
            libraryItemId = c.tryString("libraryItemId") ?: "",
            id = c.tryString("id") ?: "",
            title = rawTitle.ifEmpty { "Episode" },
            subtitle = c.tryString("subtitle"),
            description = c.tryString("description"),
            pubDate = c.tryString("pubDate"),
            duration = c.tryDouble("duration"),
            publishedAt = c.tryLong("publishedAt") ?: c.tryDouble("publishedAt")?.roundedSwift()?.toLong(),
            podcast = c.tryObj("podcast", AbsRecentEpisodePodcastNestSerializer),
        )
    }

    // Swift: synthetisiertes `encode(to:)` (encodeIfPresent für Optionals).
    override fun encode(v: AbsRecentPodcastEpisodeDTO) = jsonObjectOf {
        put("libraryItemId", JsonPrimitive(v.libraryItemId))
        put("id", JsonPrimitive(v.id))
        put("title", JsonPrimitive(v.title))
        putIfPresent("subtitle", v.subtitle)
        putIfPresent("description", v.description)
        putIfPresent("pubDate", v.pubDate)
        putIfPresent("duration", v.duration)
        putIfPresent("publishedAt", v.publishedAt)
        putIfPresent("podcast", v.podcast?.let { AbsRecentEpisodePodcastNestSerializer.encode(it) })
    }
}

/** iOS: `ABSRecentEpisodePodcastNest`. */
@Serializable(with = AbsRecentEpisodePodcastNestSerializer::class)
data class AbsRecentEpisodePodcastNest(val metadata: AbsRecentEpisodePodcastMeta?)

object AbsRecentEpisodePodcastNestSerializer : SwiftObjectSerializer<AbsRecentEpisodePodcastNest>("ABSRecentEpisodePodcastNest") {
    override fun decode(c: JObj) = AbsRecentEpisodePodcastNest(c.objOrNull("metadata", AbsRecentEpisodePodcastMetaSerializer))
    override fun encode(v: AbsRecentEpisodePodcastNest) = jsonObjectOf {
        putIfPresent("metadata", v.metadata?.let { AbsRecentEpisodePodcastMetaSerializer.encode(it) })
    }
}

/** iOS: `ABSRecentEpisodePodcastMeta`. */
@Serializable(with = AbsRecentEpisodePodcastMetaSerializer::class)
data class AbsRecentEpisodePodcastMeta(
    val title: String?,
    val author: String?,
    val description: String?,
    val genres: List<String>?,
)

object AbsRecentEpisodePodcastMetaSerializer : SwiftObjectSerializer<AbsRecentEpisodePodcastMeta>("ABSRecentEpisodePodcastMeta") {
    override fun decode(c: JObj) = AbsRecentEpisodePodcastMeta(
        title = c.stringOrNull("title"),
        author = c.stringOrNull("author"),
        description = c.stringOrNull("description"),
        genres = c.listOrNull("genres", ElementDecoder.string),
    )

    override fun encode(v: AbsRecentEpisodePodcastMeta) = jsonObjectOf {
        putIfPresent("title", v.title)
        putIfPresent("author", v.author)
        putIfPresent("description", v.description)
        putStrings("genres", v.genres)
    }
}

/**
 * iOS: `ABSPodcastRssFeedEpisodeDraft` — einzelne Folge aus `POST /api/podcasts/feed` (noch nicht
 * als Library-Episode); Payload für `POST …/download-episodes`. [episodePayloadJSON] ist das rohe
 * JSON-Objekt als Text (iOS: `Data`).
 */
data class AbsPodcastRssFeedEpisodeDraft(
    val id: UUID,
    val title: String,
    val publishedAt: Long?,
    val subtitle: String?,
    val episodePayloadJSON: String,
) {
    fun matchesLibraryEpisode(row: AbsPodcastEpisodeListItem): Boolean {
        val t0 = normTitle(title)
        val t1 = normTitle(row.episodeTitle)
        if (t0.isEmpty() || t0 != t1) return false
        val pa = publishedAt?.let { it / 1000 }
        val pb = row.publishedAt?.let { it / 1000 }
        if (pa != null && pb != null && pa != 0L && pb != 0L && Math.abs(pa - pb) <= 2) return true
        if ((publishedAt == null || publishedAt == 0L) && (row.publishedAt == null || row.publishedAt == 0L)) return true
        return false
    }

    companion object {
        private fun normTitle(s: String) = s.swiftTrim().lowercase()

        fun episodesFromFeedApiResponse(data: String): List<AbsPodcastRssFeedEpisodeDraft> {
            val root = AbsJson.decoder.parseToJsonElement(data) as? JsonObject
            val podcast = root?.get("podcast") as? JsonObject
            val episodes = SwiftJson.anyObjList(podcast?.get("episodes")) ?: return emptyList()
            val out = ArrayList<AbsPodcastRssFeedEpisodeDraft>(episodes.size)
            for (ep in episodes) {
                val payload = ep.toString()
                val titleRaw = SwiftJson.anyString(ep["title"])?.swiftTrim() ?: ""
                val title = titleRaw.ifEmpty { "Episode" }
                val subRaw = SwiftJson.anyString(ep["subtitle"])?.swiftTrim() ?: ""
                val subtitle = subRaw.ifEmpty { null }
                val publishedAt = int64Millis(ep["publishedAt"]) ?: int64Millis(ep["pubDate"])
                out.add(AbsPodcastRssFeedEpisodeDraft(UUID.randomUUID(), title, publishedAt, subtitle, payload))
            }
            return out.sortedWith { a, b ->
                val pa = a.publishedAt ?: 0
                val pb = b.publishedAt ?: 0
                if (pa != pb) pb.compareTo(pa) else -localizedCaseInsensitiveCompare(a.title, b.title).coerceIn(-1, 1)
            }
        }

        private fun int64Millis(value: JsonElement?): Long? {
            SwiftJson.anyInt(value)?.let { return it }
            SwiftJson.double(value)?.let { n ->
                if (n > 10_000_000_000.0) return n.toLong()
                if (n > 1_000_000_000.0) return (n * 1000).toLong()
                return (n * 1000).toLong()
            }
            SwiftJson.anyString(value)?.let { s -> return s.swiftTrim().toLongOrNull() }
            return null
        }
    }
}

/**
 * iOS: `ABSPodcastFeedPreview` — vollständige Feed-Vorschau einer **noch nicht abonnierten**
 * Sendung (`POST /api/podcasts/feed`).
 */
data class AbsPodcastFeedPreview(
    var title: String,
    var author: String?,
    var descriptionPlain: String?,
    var imageUrl: String?,
    var categories: List<String>,
    var language: String?,
    var explicit: Boolean,
    /** `episodic` / `serial` (iTunes-Feedtyp). */
    var type: String?,
    var feedUrl: String?,
    var pageUrl: String?,
    var publishedAt: Long?,
    var episodes: List<AbsPodcastFeedPreviewEpisode>,
) {
    val episodeCount: Int get() = episodes.size

    /** Neueste Folge des Feeds (Liste ist absteigend sortiert). */
    val latestEpisodePublishedAt: Long? get() = episodes.mapNotNull { it.publishedAt }.filter { it > 0 }.maxOrNull()

    /** Gesamtlaufzeit aller Folgen mit bekannter Dauer (`null`, wenn der Feed keine Dauern liefert). */
    val totalDurationSeconds: Double?
        get() {
            val known = episodes.mapNotNull { it.durationSeconds }.filter { it > 0 }
            if (known.isEmpty()) return null
            return known.sum()
        }

    /**
     * iOS: `mergingDirectoryHitFallbacks` (AppModelPodcastDirectory.swift) — Feeds lassen häufig
     * Felder aus, die iTunes kennt; dann die Verzeichnisdaten des Treffers verwenden.
     */
    fun mergingDirectoryHitFallbacks(hit: AbsPodcastDirectorySearchHit): AbsPodcastFeedPreview {
        val merged = copy()
        if (merged.title.isEmpty()) merged.title = hit.title.swiftTrim()
        if (merged.author.isNullOrEmpty()) merged.author = hit.artistName?.swiftTrim()?.nilIfEmpty()
        if (merged.descriptionPlain.isNullOrEmpty()) merged.descriptionPlain = absPlainText(hit.descriptionPlain).nilIfEmpty()
        if (merged.imageUrl.isNullOrEmpty()) merged.imageUrl = hit.cover?.swiftTrim()?.nilIfEmpty()
        if (merged.categories.isEmpty()) merged.categories = (hit.genres ?: emptyList()).map { it.swiftTrim() }.filter { it.isNotEmpty() }
        if (merged.feedUrl.isNullOrEmpty()) merged.feedUrl = hit.feedUrl?.swiftTrim()?.nilIfEmpty()
        if (merged.pageUrl.isNullOrEmpty()) merged.pageUrl = hit.pageUrl?.swiftTrim()?.nilIfEmpty()
        if (!merged.explicit) merged.explicit = hit.explicit ?: false
        return merged
    }

    companion object {
        fun fromFeedApiResponse(data: String): AbsPodcastFeedPreview {
            val root = AbsJson.decoder.parseToJsonElement(data) as? JsonObject
            val podcast = root?.get("podcast") as? JsonObject
            val meta = podcast?.get("metadata") as? JsonObject ?: JsonObject(emptyMap())

            val rawTitle = string(meta["title"]) ?: ""
            val description = absPlainText(string(meta["descriptionPlain"])).nilIfEmpty()
                ?: absPlainText(string(meta["description"])).nilIfEmpty()

            var categories: List<String> = SwiftJson.anyStringList(meta["categories"])
                ?: SwiftJson.anyStringList(meta["genres"]) ?: emptyList()
            categories = categories.map { it.swiftTrim() }.filter { it.isNotEmpty() }

            val episodesRaw = SwiftJson.anyObjList(podcast?.get("episodes")) ?: emptyList()
            val episodes = episodesRaw.mapIndexed { index, ep -> AbsPodcastFeedPreviewEpisode.fromJson(ep, index) }
                .sortedWith { a, b ->
                    val pa = a.publishedAt ?: 0
                    val pb = b.publishedAt ?: 0
                    if (pa != pb) pb.compareTo(pa) else localizedCaseInsensitiveCompare(a.title, b.title).coerceIn(-1, 1)
                }

            return AbsPodcastFeedPreview(
                title = rawTitle.swiftTrim(),
                author = string(meta["author"]),
                descriptionPlain = description,
                imageUrl = string(meta["image"]) ?: string(meta["imageUrl"]),
                categories = categories,
                language = string(meta["language"]),
                explicit = bool(meta["explicit"]) ?: false,
                type = string(meta["type"]),
                feedUrl = string(meta["feedUrl"]),
                pageUrl = string(meta["link"]) ?: string(meta["itunesPageUrl"]),
                publishedAt = AbsPodcastFeedEpisodeParsing.millis(meta["pubDate"]),
                episodes = episodes,
            )
        }

        internal fun string(value: JsonElement?): String? {
            val s = SwiftJson.anyString(value) ?: return null
            return s.swiftTrim().ifEmpty { null }
        }

        internal fun bool(value: JsonElement?): Boolean? {
            SwiftJson.anyBool(value)?.let { return it }
            SwiftJson.anyInt(value)?.let { return it != 0L }
            SwiftJson.anyString(value)?.let { s ->
                return when (s.swiftTrim().lowercase()) {
                    "true", "yes", "1" -> true
                    "false", "no", "0" -> false
                    else -> null
                }
            }
            return null
        }
    }
}

/** iOS: `ABSPodcastFeedPreviewEpisode` — eine Folge aus der Feed-Vorschau (reine Anzeige). */
data class AbsPodcastFeedPreviewEpisode(
    val id: String,
    val title: String,
    val subtitle: String?,
    val descriptionPlain: String?,
    val publishedAt: Long?,
    val durationSeconds: Double?,
    val season: String?,
    val episodeNumber: String?,
    /** `full` / `trailer` / `bonus`. */
    val episodeType: String?,
    val explicit: Boolean,
    /**
     * Rohes Folgenobjekt aus der Feed-Antwort — unverändert als Payload für
     * `POST /api/podcasts/:id/download-episodes` (leer = defektes Feed-Objekt).
     */
    val episodePayloadJSON: String,
) {
    /** Ohne Payload kann die Folge nicht auf den Server geladen werden (defektes Feed-Objekt). */
    val canDownloadToServer: Boolean get() = episodePayloadJSON.isNotEmpty()

    /** Vergleichsform für „liegt schon in der Bibliothek“ — Feeds schreiben Titel uneinheitlich. */
    val normalizedTitleKey: String get() = title.swiftTrim().lowercase()

    /** „S2 · E14“ — nur was der Feed liefert. */
    val numberingLabel: String?
        get() {
            val parts = mutableListOf<String>()
            if (!season.isNullOrEmpty()) parts.add("S$season")
            if (!episodeNumber.isNullOrEmpty()) parts.add("E$episodeNumber")
            return if (parts.isEmpty()) null else parts.joinToString(" · ")
        }

    /** Nur nicht-reguläre Typen anzeigen (Trailer, Bonus). */
    val specialTypeLabel: String?
        get() {
            val t = episodeType?.lowercase() ?: return null
            if (t == "full") return null
            return swiftCapitalized(t)
        }

    companion object {
        fun fromJson(ep: JsonObject, fallbackIndex: Int): AbsPodcastFeedPreviewEpisode {
            val rawTitle = AbsPodcastFeedPreview.string(ep["title"]) ?: ""
            val resolvedTitle = rawTitle.ifEmpty { "Episode ${fallbackIndex + 1}" }
            return AbsPodcastFeedPreviewEpisode(
                // GUIDs fehlen in manchen Feeds — dann Index + Titel als stabiler Listenschlüssel.
                id = AbsPodcastFeedPreview.string(ep["guid"]) ?: AbsPodcastFeedPreview.string(ep["id"])
                    ?: "feed-episode-$fallbackIndex-$resolvedTitle",
                title = resolvedTitle,
                subtitle = absPlainText(AbsPodcastFeedPreview.string(ep["subtitle"])).nilIfEmpty(),
                descriptionPlain = absPlainText(AbsPodcastFeedPreview.string(ep["descriptionPlain"])).nilIfEmpty()
                    ?: absPlainText(AbsPodcastFeedPreview.string(ep["description"])).nilIfEmpty(),
                publishedAt = AbsPodcastFeedEpisodeParsing.millis(ep["publishedAt"])
                    ?: AbsPodcastFeedEpisodeParsing.millis(ep["pubDate"]),
                durationSeconds = AbsPodcastFeedEpisodeParsing.durationSeconds(ep["duration"]),
                season = AbsPodcastFeedPreview.string(ep["season"]),
                episodeNumber = AbsPodcastFeedPreview.string(ep["episode"]) ?: SwiftJson.anyInt(ep["episode"])?.toString(),
                episodeType = AbsPodcastFeedPreview.string(ep["episodeType"]),
                explicit = AbsPodcastFeedPreview.bool(ep["explicit"]) ?: false,
                episodePayloadJSON = ep.toString(),
            )
        }
    }
}

/** iOS: `String.capitalized` — erster Buchstabe jedes Wortes groß, Rest klein. */
internal fun swiftCapitalized(s: String): String =
    s.split(" ").joinToString(" ") { w -> w.lowercase().replaceFirstChar { it.titlecase(Locale.ROOT) } }

/** iOS: `ABSPodcastFeedEpisodeParsing` — Feed-Zeitstempel und -Dauern (RSS liefert viele Formate). */
object AbsPodcastFeedEpisodeParsing {
    fun millis(value: JsonElement?): Long? {
        SwiftJson.anyInt(value)?.let { return normalizedMillis(it) }
        SwiftJson.double(value)?.let { return normalizedMillis(it.toLong()) }
        val s = SwiftJson.anyString(value) ?: return null
        val t = s.swiftTrim()
        if (t.isEmpty()) return null
        t.toLongOrNull()?.let { return normalizedMillis(it) }
        rfc822Millis(t)?.let { return it }
        isoMillis(t)?.let { return it }
        return null
    }

    /** Sekunden vs. Millisekunden anhand der Größenordnung unterscheiden. */
    private fun normalizedMillis(value: Long): Long? {
        if (value <= 0) return null
        return if (value < 100_000_000_000L) value * 1000 else value
    }

    /** `"3600"`, `"01:02:03"` oder `"12:34"`. */
    fun durationSeconds(value: JsonElement?): Double? {
        SwiftJson.anyDouble(value)?.let { n -> return if (n > 0) n else null }
        val s = SwiftJson.anyString(value) ?: return null
        val t = s.swiftTrim()
        if (t.isEmpty()) return null
        if (t.contains(":")) {
            // Swift `split` lässt leere Teilstücke weg.
            val parts = t.split(":").filter { it.isNotEmpty() }.map { swiftDouble(it) ?: 0.0 }
            val seconds = when (parts.size) {
                3 -> parts[0] * 3600 + parts[1] * 60 + parts[2]
                2 -> parts[0] * 60 + parts[1]
                else -> return null
            }
            return if (seconds > 0) seconds else null
        }
        val n = swiftDouble(t) ?: return null
        return if (n > 0) n else null
    }

    private fun rfc822Millis(value: String): Long? {
        val f = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss Z", Locale.US).apply { isLenient = false }
        val pos = ParsePosition(0)
        val d = f.parse(value, pos) ?: return null
        // DateFormatter verlangt vollständigen Match.
        if (pos.index != value.length) return null
        return d.time
    }

    private fun isoMillis(value: String): Long? =
        runCatching { OffsetDateTime.parse(value, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant().toEpochMilli() }.getOrNull()
}

/** iOS: `Double(String)` — keine Leerzeichen, kein Hex-Suffix wie Kotlins `d`/`f`. */
internal fun swiftDouble(s: String): Double? {
    if (s.isEmpty() || s.any { it.isWhitespace() }) return null
    if (s.last().let { it == 'd' || it == 'D' || it == 'f' || it == 'F' }) return null
    return s.toDoubleOrNull()
}

/** iOS: `ABSPodcastCheckNewResponse` — Antwort von `GET /api/podcasts/:id/checknew`. */
@Serializable(with = AbsPodcastCheckNewResponseSerializer::class)
data class AbsPodcastCheckNewResponse(val episodes: List<AbsPodcastCheckNewFeedEpisode>)

/** iOS: `ABSPodcastCheckNewFeedEpisode`. */
data class AbsPodcastCheckNewFeedEpisode(val title: String?)

object AbsPodcastCheckNewResponseSerializer : SwiftObjectSerializer<AbsPodcastCheckNewResponse>("ABSPodcastCheckNewResponse") {
    private val episode = object : SwiftObjectSerializer<AbsPodcastCheckNewFeedEpisode>("ABSPodcastCheckNewFeedEpisode") {
        override fun decode(c: JObj) = AbsPodcastCheckNewFeedEpisode(c.stringOrNull("title"))
    }
    override fun decode(c: JObj) = AbsPodcastCheckNewResponse(c.list("episodes", episode))
}

/** iOS: `ABSPodcastEpisodeListItem`. */
@Serializable
data class AbsPodcastEpisodeListItem(
    val libraryItemId: String,
    /** Bibliothek (z. B. für Home-„Weiterhören“ nach gewählter Podcast-Bibliothek). */
    val libraryId: String? = null,
    val episodeId: String,
    val episodeTitle: String,
    val showTitle: String,
    val authorLine: String,
    val duration: Double,
    val publishedAt: Long? = null,
) {
    /** Stabil über Sendungen hinweg — `episodeId` allein kann in gemischten Listen kollidieren. */
    val id: String get() = progressLookupKey

    /**
     * Getrimmt — muss exakt zu [AbsUserMediaProgress.progressLookupKey] passen (dort ebenfalls getrimmt),
     * sonst divergieren Fortschritts-Lookup und Dedupe-Key bei Whitespace in IDs.
     */
    val progressLookupKey: String get() = "${libraryItemId.swiftTrim()}-${episodeId.swiftTrim()}"

    /** Stabiler Schlüssel für Deduplizierung (Cache, Manifest, Fortschritt). */
    val canonicalDedupeKey: String
        get() {
            val lid = libraryItemId.swiftTrim()
            val eid = episodeId.swiftTrim()
            if (lid.isNotEmpty() && eid.isNotEmpty()) return "$lid|$eid"
            return progressLookupKey
        }

    /** Höher = vollständigere Anzeige (Titel, Sendung, Datum). */
    val metadataRichnessScore: Int
        get() {
            var score = 0
            val et = episodeTitle.swiftTrim()
            if (et.isNotEmpty() && et != "Episode") score += 4
            val st = showTitle.swiftTrim()
            if (st.isNotEmpty() && st != "—") score += 3
            val al = authorLine.swiftTrim()
            if (al.isNotEmpty() && al != "—" && al != st) score += 1
            if (publishedAt != null && publishedAt > 0) score += 1
            if (duration > 0) score += 1
            return score
        }

    fun preferringRicherMetadata(other: AbsPodcastEpisodeListItem): AbsPodcastEpisodeListItem =
        if (metadataRichnessScore >= other.metadataRichnessScore) this else other

    /** Minimaler [AbsBook] für `PlaybackController.playBook` (Cover/Item-ID = Sendung). */
    fun playbackStubBook(libraryId: String?): AbsBook {
        val meta = AbsBookMediaMetadata.offline(offlineTitle = episodeTitle, authorLine = authorLine)
        val dur = if (duration > 0) duration else null
        val media = AbsBookMedia(metadata = meta, duration = dur, numTracks = 1, chapters = null, tracks = null)
        return AbsBook(id = libraryItemId, libraryId = libraryId ?: this.libraryId, media = media, addedAt = null, updatedAt = null)
    }

    companion object {
        /** Gleiche Folge nur einmal; Zeile mit mehr Metadaten gewinnt (Offline: Cache + Manifest). */
        fun dedupeRows(items: List<AbsPodcastEpisodeListItem>): List<AbsPodcastEpisodeListItem> {
            val byKey = HashMap<String, AbsPodcastEpisodeListItem>()
            val order = ArrayList<String>(items.size)
            for (item in items) {
                val key = item.canonicalDedupeKey
                val existing = byKey[key]
                if (existing != null) {
                    byKey[key] = item.preferringRicherMetadata(existing)
                } else {
                    byKey[key] = item
                    order.add(key)
                }
            }
            return order.mapNotNull { byKey[it] }
        }

        fun fromDTO(
            e: AbsRecentPodcastEpisodeDTO,
            fallbackShow: AbsBook? = null,
            libraryId: String? = null,
            forceLibraryItemId: String? = null,
        ): AbsPodcastEpisodeListItem? {
            val lid = (forceLibraryItemId ?: e.libraryItemId).swiftTrim()
            val eid = e.id.swiftTrim()
            if (lid.isEmpty() || eid.isEmpty()) return null
            val et = e.title.swiftTrim()
            val episodeTitle = et.ifEmpty { "Episode" }
            var show = e.podcast?.metadata?.title?.swiftTrim() ?: ""
            if (show.isEmpty() && fallbackShow != null) {
                val t = fallbackShow.displayTitle.swiftTrim()
                if (t.isNotEmpty()) show = t
            }
            val showTitle = show.ifEmpty { "—" }
            var auth = e.podcast?.metadata?.author?.swiftTrim() ?: ""
            if (auth.isEmpty() && fallbackShow != null) {
                val a = fallbackShow.displayAuthors.swiftTrim()
                if (a.isNotEmpty() && a != "—") auth = a
            }
            val authorLine = auth.ifEmpty { showTitle }
            val dur = e.duration ?: 0.0
            val libIdRaw = libraryId?.swiftTrim() ?: ""
            return AbsPodcastEpisodeListItem(
                libraryItemId = lid,
                libraryId = libIdRaw.ifEmpty { null },
                episodeId = eid,
                episodeTitle = episodeTitle,
                showTitle = showTitle,
                authorLine = authorLine,
                duration = dur,
                publishedAt = e.publishedAt,
            )
        }

        /** Minimale Zeile für Wiederherstellung nach App-Start (`mediaProgress` mit `episodeId`). */
        fun forResumePlayback(progress: AbsUserMediaProgress, libraryId: String?): AbsPodcastEpisodeListItem? {
            val eid = progress.episodeId?.swiftTrim() ?: ""
            if (eid.isEmpty()) return null
            return AbsPodcastEpisodeListItem(
                libraryItemId = progress.libraryItemId,
                libraryId = libraryId,
                episodeId = eid,
                episodeTitle = "Episode",
                showTitle = "—",
                authorLine = "—",
                duration = progress.duration,
                publishedAt = null,
            )
        }
    }
}

/** iOS: `ABSPodcastEpisodeExpandedDetail` — Zusatzinfos nach `expandPodcastEpisode`. */
data class AbsPodcastEpisodeExpandedDetail(
    val episode: AbsPodcastEpisodeListItem,
    val subtitle: String?,
    val episodeDescriptionHTML: String?,
    val showDescriptionHTML: String?,
    val pubDate: String?,
    val showGenres: List<String>?,
    /** Autoren der Sendung (`media.metadata.authors`) für klickbaren Katalog-Filter. */
    val showAuthors: List<AbsAuthor>,
)

/** iOS: `ABSItemsInProgressPayload`. */
data class AbsItemsInProgressPayload(
    val books: List<AbsBook>,
    val podcastEpisodes: List<AbsPodcastEpisodeListItem>,
)
