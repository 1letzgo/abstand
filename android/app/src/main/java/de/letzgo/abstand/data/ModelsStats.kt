package de.letzgo.abstand.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.time.temporal.WeekFields
import java.util.Locale

// iOS: ABSModels.swift (Teil 4: Hör-Sitzungen, Server-Admin, Bibliotheks-Statistik, Hörstatistik).

/** iOS: `formatPlaybackDurationShortHuman` (AppTheme.swift). */
fun formatPlaybackDurationShortHuman(seconds: Double): String {
    if (!seconds.isFinite() || seconds < 0) return "< 1 min"
    val s = seconds.roundedSwift().toLong()
    val h = s / 3600
    val m = (s % 3600) / 60
    if (h == 0L && m == 0L) return "< 1 min"
    val parts = mutableListOf<String>()
    if (h > 0) parts.add(if (h == 1L) "1 hr" else "$h hrs")
    if (m > 0) parts.add(if (m == 1L) "1 min" else "$m min")
    return parts.joinToString(" ")
}

/**
 * Näherung an `RelativeDateTimeFormatter` (`unitsStyle = .short`, en_US): größte Einheit ohne
 * Rundung, z. B. „3 hr. ago“, „2 days ago“, „in 5 min.“.
 */
fun relativeShortEnglish(millis: Long, nowMillis: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): String {
    val then = Instant.ofEpochMilli(millis).atZone(zone)
    val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
    val past = !then.isAfter(now)
    val (a, b) = if (past) then to now else now to then
    fun phrase(n: Long, unit: String, plural: String = unit): String {
        val u = if (n == 1L) unit else plural
        return if (past) "$n $u ago" else "in $n $u"
    }
    ChronoUnit.YEARS.between(a, b).takeIf { it > 0 }?.let { return phrase(it, "yr.") }
    ChronoUnit.MONTHS.between(a, b).takeIf { it > 0 }?.let { return phrase(it, "mo.") }
    ChronoUnit.WEEKS.between(a, b).takeIf { it > 0 }?.let { return phrase(it, "wk.") }
    ChronoUnit.DAYS.between(a, b).takeIf { it > 0 }?.let { return phrase(it, "day", "days") }
    ChronoUnit.HOURS.between(a, b).takeIf { it > 0 }?.let { return phrase(it, "hr.") }
    ChronoUnit.MINUTES.between(a, b).takeIf { it > 0 }?.let { return phrase(it, "min.") }
    return phrase(ChronoUnit.SECONDS.between(a, b), "sec.")
}

// MARK: - Listening sessions (`GET /api/me/listening-sessions`)

/** iOS: `ABSListeningSessionsPayload`. */
@Serializable(with = AbsListeningSessionsPayloadSerializer::class)
data class AbsListeningSessionsPayload(
    val total: Int,
    val numPages: Int,
    val page: Int,
    val itemsPerPage: Int,
    val sessions: List<AbsListeningSession>,
) {
    companion object {
        /** Wenn einzelne Session-Objekte vom strikten Decoding abweichen, trotzdem so viele Zeilen wie möglich parsen. */
        fun decodeLenient(data: String): AbsListeningSessionsPayload {
            try {
                return AbsJson.decoder.decodeFromString(AbsListeningSessionsPayloadSerializer, data)
            } catch (primary: Exception) {
                val root = runCatching { AbsJson.decoder.parseToJsonElement(data) as? JsonObject }.getOrNull() ?: throw primary
                fun jsonInt(any: JsonElement?): Int? {
                    SwiftJson.anyInt(any)?.let { return it.toInt() }
                    SwiftJson.double(any)?.let { return it.roundedSwift().toInt() }
                    SwiftJson.anyString(any)?.let { return it.swiftTrim().toIntOrNull() }
                    return null
                }
                val rawList = SwiftJson.anyObjsCompact(root["sessions"]) ?: emptyList()
                val parsed = rawList.mapNotNull { AbsListeningSession.fromLenientDictionary(it) }
                return AbsListeningSessionsPayload(
                    total = jsonInt(root["total"]) ?: parsed.size,
                    numPages = jsonInt(root["numPages"]) ?: jsonInt(root["num_pages"]) ?: (if (parsed.isEmpty()) 0 else 1),
                    page = jsonInt(root["page"]) ?: 0,
                    itemsPerPage = jsonInt(root["itemsPerPage"]) ?: jsonInt(root["items_per_page"]) ?: maxOf(parsed.size, 1),
                    sessions = parsed,
                )
            }
        }
    }
}

object AbsListeningSessionsPayloadSerializer : SwiftObjectSerializer<AbsListeningSessionsPayload>("ABSListeningSessionsPayload") {
    override fun decode(c: JObj) = AbsListeningSessionsPayload(
        total = c.intOrNull("total") ?: 0,
        numPages = c.intOrNull("numPages") ?: 0,
        page = c.intOrNull("page") ?: 0,
        itemsPerPage = c.intOrNull("itemsPerPage") ?: 0,
        sessions = c.listOrNull("sessions", AbsListeningSessionSerializer) ?: emptyList(),
    )
}

/** iOS: `ABSListeningSession` — Gleichheit/Hash nur über `id` (wie Swift). */
@Serializable(with = AbsListeningSessionSerializer::class)
class AbsListeningSession(
    val id: String,
    val libraryItemId: String,
    /** Buch-Medien-UUID (entspricht oft `ABSBook.mediaId`), wenn `libraryItemId` in der API fehlt. */
    val bookId: String?,
    val episodeId: String?,
    val duration: Double,
    val startTime: Double,
    val currentTime: Double,
    val timeListening: Int,
    val startedAt: Long,
    val updatedAt: Long,
) {
    override fun equals(other: Any?) = other is AbsListeningSession && other.id == id
    override fun hashCode() = id.hashCode()
    override fun toString() = "AbsListeningSession(id=$id, libraryItemId=$libraryItemId, episodeId=$episodeId, timeListening=$timeListening)"

    companion object {
        /** iOS: `init?(lenientDictionary:)` — Fallback, wenn der Decoder am Gesamt-Array scheitert. */
        fun fromLenientDictionary(d: JsonObject): AbsListeningSession? {
            fun jsonString(keys: List<String>): String? {
                for (k in keys) {
                    val v = d[k] ?: continue
                    if (SwiftJson.isNull(v)) continue
                    val s = SwiftJson.anyString(v)
                    if (s != null) {
                        val t = s.swiftTrim()
                        if (t.isNotEmpty()) return t
                    } else {
                        SwiftJson.anyInt(v)?.let { return it.toString() }
                        SwiftJson.double(v)?.let { return it.toLong().toString() }
                    }
                }
                return null
            }
            fun jsonDouble(keys: List<String>): Double {
                for (k in keys) {
                    val v = d[k] ?: continue
                    SwiftJson.anyDouble(v)?.let { return it }
                    SwiftJson.anyString(v)?.let { s -> swiftDouble(s.swiftTrim())?.let { return it } }
                }
                return 0.0
            }
            fun jsonInt(keys: List<String>): Long {
                for (k in keys) {
                    val v = d[k] ?: continue
                    SwiftJson.anyInt(v)?.let { return it }
                    SwiftJson.double(v)?.let { return it.roundedSwift().toLong() }
                    SwiftJson.anyString(v)?.let { s -> s.swiftTrim().toLongOrNull()?.let { return it } }
                }
                return 0
            }

            val id = jsonString(listOf("id", "sessionId"))
            if (id.isNullOrEmpty()) return null

            val nestedLi = (d["libraryItem"] as? JsonObject) ?: (d["library_item"] as? JsonObject)
            val fromNested = nestedLi?.let { li ->
                val v = li["id"]
                val s = SwiftJson.anyString(v)
                if (s != null) s.swiftTrim().ifEmpty { null } else SwiftJson.anyInt(v)?.toString()
            }
            val libraryItemId = jsonString(listOf("libraryItemId", "library_item_id")) ?: fromNested ?: ""
            val bookId = jsonString(listOf("bookId", "book_id"))?.ifEmpty { null }
            val episodeId = jsonString(listOf("episodeId", "episode_id"))?.ifEmpty { null }

            return AbsListeningSession(
                id = id,
                libraryItemId = libraryItemId,
                bookId = bookId,
                episodeId = episodeId,
                duration = jsonDouble(listOf("duration")),
                startTime = jsonDouble(listOf("startTime", "start_time")),
                currentTime = jsonDouble(listOf("currentTime", "current_time")),
                timeListening = jsonInt(listOf("timeListening", "time_listening")).toInt(),
                startedAt = jsonInt(listOf("startedAt", "started_at")),
                updatedAt = jsonInt(listOf("updatedAt", "updated_at")),
            )
        }
    }
}

object AbsListeningSessionSerializer : SwiftObjectSerializer<AbsListeningSession>("ABSListeningSession") {
    private fun stringish(c: JObj, key: String): String? {
        c.tryString(key)?.takeIf { it.isNotEmpty() }?.let { return it }
        return c.tryInt(key)?.toString()
    }

    override fun decode(c: JObj): AbsListeningSession {
        val id = stringish(c, "id") ?: ""
        val libraryItemId = stringish(c, "libraryItemId")?.takeIf { it.isNotEmpty() }
            ?: c.tryNested("libraryItem")?.let { stringish(it, "id") }?.takeIf { it.isNotEmpty() }
            ?: ""
        val bookId = stringish(c, "bookId")?.takeIf { it.isNotEmpty() }
        val episodeId = c.stringOrNull("episodeId")
        val duration = c.doubleOrNull("duration") ?: 0.0
        val startTime = c.doubleOrNull("startTime") ?: 0.0
        val currentTime = c.doubleOrNull("currentTime") ?: 0.0
        // Swift: `if let i = try decodeIfPresent(Int)` — ein Bruch (12.5) wirft hier bereits (Double-Zweig nur ohne Key).
        val timeListening = c.intOrNull("timeListening") ?: c.doubleOrNull("timeListening")?.roundedSwift()?.toInt() ?: 0
        val startedAt = c.longOrNull("startedAt") ?: c.doubleOrNull("startedAt")?.roundedSwift()?.toLong() ?: 0
        val updatedAt = c.longOrNull("updatedAt") ?: c.doubleOrNull("updatedAt")?.roundedSwift()?.toLong() ?: 0
        return AbsListeningSession(id, libraryItemId, bookId, episodeId, duration, startTime, currentTime, timeListening, startedAt, updatedAt)
    }
}

// MARK: - Server admin (root)

/** iOS: `ABSUsersListResponse`. */
@Serializable(with = AbsUsersListResponseSerializer::class)
data class AbsUsersListResponse(val users: List<AbsAdminUserSummary>)

/** iOS: `ABSAdminUserSummary`. */
data class AbsAdminUserSummary(
    val id: String,
    val username: String,
    val type: String?,
    val isActive: Boolean?,
    val lastSeen: Long?,
) {
    val isRoot: Boolean get() = (type ?: "").lowercase() == "root"
    val typeLabel: String?
        get() {
            val t = type.trimmedOrEmpty().lowercase()
            if (t.isEmpty() || t == "user") return null
            return t
        }
}

object AbsUsersListResponseSerializer : SwiftObjectSerializer<AbsUsersListResponse>("ABSUsersListResponse") {
    private val summary = object : SwiftObjectSerializer<AbsAdminUserSummary>("ABSAdminUserSummary") {
        override fun decode(c: JObj) = AbsAdminUserSummary(
            c.string("id"), c.string("username"), c.stringOrNull("type"), c.boolOrNull("isActive"), c.longOrNull("lastSeen"),
        )
    }
    override fun decode(c: JObj) = AbsUsersListResponse(c.list("users", summary))
}

/** iOS: `ABSAdminUserDetail`. */
data class AbsAdminUserDetail(
    val id: String,
    val username: String,
    val type: String?,
    val lastSeen: Long?,
    val mediaProgress: List<AbsAdminMediaProgressRow>,
) {
    val typeLabel: String?
        get() {
            val t = type.trimmedOrEmpty().lowercase()
            if (t.isEmpty() || t == "user") return null
            return t
        }

    fun lastSeenCaption(nowMillis: Long = System.currentTimeMillis()): String {
        val ms = lastSeen
        if (ms == null || ms <= 0) return "Never signed in"
        return "● Last seen ${relativeShortEnglish(ms, nowMillis)}"
    }

    val mediaProgressSorted: List<AbsAdminMediaProgressRow>
        get() = mediaProgress.sortedByDescending { it.lastUpdate ?: 0 }

    companion object {
        fun decode(data: String): AbsAdminUserDetail {
            val root = AbsJson.decoder.parseToJsonElement(data) as? JsonObject
                ?: throw AbsApiError.Decoding(IllegalStateException("user detail not an object"))
            fun str(keys: List<String>): String {
                for (k in keys) {
                    val v = root[k] ?: continue
                    if (SwiftJson.isNull(v)) continue
                    val s = SwiftJson.anyString(v)
                    if (s != null) {
                        val t = s.swiftTrim()
                        if (t.isNotEmpty()) return t
                    } else SwiftJson.anyInt(v)?.let { return it.toString() }
                }
                return ""
            }
            fun int64(keys: List<String>): Long? {
                for (k in keys) {
                    val v = root[k] ?: continue
                    if (SwiftJson.isNull(v)) continue
                    SwiftJson.anyInt(v)?.let { return it }
                    SwiftJson.double(v)?.let { return it.roundedSwift().toLong() }
                }
                return null
            }
            val libraryItemById = HashMap<String, JsonObject>()
            SwiftJson.anyObjList(root["libraryItems"])?.forEach { li ->
                val id = SwiftJson.anyString(li["id"]) ?: return@forEach
                val tid = id.swiftTrim()
                if (tid.isNotEmpty()) libraryItemById[tid] = li
            }
            val progressRaw = SwiftJson.anyObjsCompact(root["mediaProgress"]) ?: emptyList()
            val rows = progressRaw.mapNotNull { raw ->
                var dict = raw
                if (raw["libraryItem"] == null) {
                    val lid = SwiftJson.anyString(raw["libraryItemId"])?.swiftTrim()
                    val li = lid?.takeIf { it.isNotEmpty() }?.let { libraryItemById[it] }
                    if (li != null) dict = JsonObject(raw + ("libraryItem" to li))
                }
                AbsAdminMediaProgressRow.fromLenientDictionary(dict)
            }
            val type = str(listOf("type"))
            return AbsAdminUserDetail(
                id = str(listOf("id")),
                username = str(listOf("username")),
                type = type.ifEmpty { null },
                lastSeen = int64(listOf("lastSeen", "last_seen")),
                mediaProgress = rows,
            )
        }
    }
}

/** iOS: `ABSAdminMediaProgressRow`. */
data class AbsAdminMediaProgressRow(
    val libraryItemId: String,
    val episodeId: String?,
    val duration: Double,
    val progress: Double,
    val currentTime: Double,
    val isFinished: Boolean,
    val lastUpdate: Long?,
    val title: String,
    val author: String,
) {
    val id: String get() = if (!episodeId.isNullOrEmpty()) "$libraryItemId-$episodeId" else libraryItemId

    val isInProgress: Boolean get() = !isFinished && (progress > 0.02 || currentTime > 1)

    val displayProgressFraction: Double
        get() {
            if (isFinished) return 1.0
            if (progress > 0) return minOf(1.0, progress)
            if (duration <= 0) return 0.0
            return minOf(1.0, currentTime / duration)
        }

    val progressCaption: String
        get() = if (isFinished) "Finished" else "${(displayProgressFraction * 100).roundedSwift().toInt()}%"

    val durationCaption: String
        get() = "${formatPlaybackDurationShortHuman(currentTime)} / ${formatPlaybackDurationShortHuman(maxOf(duration, currentTime, 1.0))}"

    fun timeCaption(nowMillis: Long = System.currentTimeMillis()): String {
        val ms = lastUpdate
        if (ms == null || ms <= 0) return ""
        return relativeShortEnglish(ms, nowMillis)
    }

    val resolvedDisplayTitle: String
        get() {
            val t = title.swiftTrim()
            return if (t.isEmpty() || t == "—") libraryItemId else t
        }

    val resolvedDisplayAuthor: String
        get() {
            val a = author.swiftTrim()
            return if (a.isEmpty() || a == "—") "—" else a
        }

    /** Für `BookRowCard.authorLineOverride` — nur wenn ein echter Autorenname vorliegt. */
    val resolvedAuthorForCard: String?
        get() {
            val a = author.swiftTrim()
            return if (a.isEmpty() || a == "—") null else a
        }

    fun asUserMediaProgress(): AbsUserMediaProgress {
        val progVal = when {
            progress > 0 -> minOf(1.0, maxOf(0.0, progress))
            duration <= 0 -> 0.0
            else -> minOf(1.0, currentTime / duration)
        }
        return AbsUserMediaProgress(
            libraryItemId = libraryItemId,
            episodeId = episodeId,
            duration = maxOf(duration, currentTime, 1.0),
            progress = if (isFinished) 1.0 else progVal,
            currentTime = currentTime,
            isFinished = isFinished,
            lastUpdate = lastUpdate,
        )
    }

    fun asBookStub(): AbsBook {
        val meta = AbsBookMediaMetadata.offline(offlineTitle = resolvedDisplayTitle, authorLine = resolvedDisplayAuthor)
        val media = AbsBookMedia(metadata = meta, duration = if (duration > 0) duration else null, numTracks = null, tracks = null)
        return AbsBook(id = libraryItemId, libraryId = null, media = media, addedAt = null, updatedAt = null, mediaId = null)
    }

    val needsTitleEnrichment: Boolean get() = isPlaceholderMetadata(title)
    val needsAuthorEnrichment: Boolean get() = isPlaceholderMetadata(author)
    val needsDisplayMetadataEnrichment: Boolean get() = needsTitleEnrichment || needsAuthorEnrichment

    /** Podcast-Folge — Titel muss Episoden-Titel sein (Show-Name allein reicht nie). */
    val hasPodcastEpisodeId: Boolean get() = episodeId.trimmedOrEmpty().isNotEmpty()

    /** Episoden-Zeilen immer auflösen: API liefert oft den Show-Namen als `title`. */
    val needsEpisodeTitleResolution: Boolean get() = hasPodcastEpisodeId

    fun withDisplayMetadata(title: String, author: String) = copy(title = title, author = author)

    /** Erzwingt Titel/Autor (ohne Placeholder-Gate) — für Episoden-Titel nach Lookup. */
    fun replacingDisplayMetadata(title: String?, author: String?): AbsAdminMediaProgressRow {
        val nextTitle = title?.swiftTrim()?.ifEmpty { null } ?: this.title
        val nextAuthor = author?.swiftTrim()?.ifEmpty { null } ?: this.author
        return withDisplayMetadata(nextTitle, nextAuthor)
    }

    companion object {
        fun isPlaceholderMetadata(value: String): Boolean {
            val t = value.swiftTrim()
            return t.isEmpty() || t == "—"
        }

        private fun nonBlankString(e: JsonElement?): String? =
            SwiftJson.anyString(e)?.takeIf { it.swiftTrim().isNotEmpty() }

        private class Meta(var title: String, var author: String)

        private fun applyMetadata(m: Meta, meta: JsonObject) {
            nonBlankString(meta["title"])?.let { if (isPlaceholderMetadata(m.title)) m.title = it }
            nonBlankString(meta["displayTitle"])?.let { if (isPlaceholderMetadata(m.title)) m.title = it }
            nonBlankString(meta["author"])?.let { if (isPlaceholderMetadata(m.author)) m.author = it }
            nonBlankString(meta["authorName"])?.let { if (isPlaceholderMetadata(m.author)) m.author = it }
            nonBlankString(meta["displayAuthor"])?.let { if (isPlaceholderMetadata(m.author)) m.author = it }
        }

        private fun episodeIdMatches(epId: String, eid: String) = epId == eid || eid.endsWith(epId) || epId.endsWith(eid)

        /** Titel/Autor einer Podcast-Folge aus `GET /api/items/:id?expanded=1`. */
        fun episodeMetadata(fromItemJSON: String, episodeId: String): Pair<String, String>? {
            val eid = episodeId.swiftTrim()
            if (eid.isEmpty()) return null
            val root = runCatching { AbsJson.decoder.parseToJsonElement(fromItemJSON) as? JsonObject }.getOrNull() ?: return null
            val itemRoot = (root["libraryItem"] as? JsonObject) ?: root
            var showTitle: String? = nonBlankString(itemRoot["displayTitle"])
            var showAuthor: String? = nonBlankString(itemRoot["displayAuthor"])
            val media = itemRoot["media"] as? JsonObject
            (media?.get("metadata") as? JsonObject)?.let { meta ->
                if (showTitle == null) showTitle = nonBlankString(meta["title"])
                if (showAuthor == null) showAuthor = nonBlankString(meta["author"])
            }
            val episodeLists = listOf(SwiftJson.anyObjList(itemRoot["episodes"]), SwiftJson.anyObjList(media?.get("episodes")))
            for (episodes in episodeLists) {
                if (episodes == null) continue
                for (ep in episodes) {
                    val epId = SwiftJson.anyString(ep["id"])?.swiftTrim() ?: ""
                    if (epId.isEmpty() || !episodeIdMatches(epId, eid)) continue
                    // Swift: `?? displayTitle` greift nur, wenn `title` fehlt (nicht bei leerem Titel).
                    val title = SwiftJson.anyString(ep["title"])?.swiftTrim() ?: SwiftJson.anyString(ep["displayTitle"])?.swiftTrim()
                    if (title.isNullOrEmpty()) continue
                    val author = showTitle ?: showAuthor ?: SwiftJson.anyString(ep["displayAuthor"])?.swiftTrim() ?: "—"
                    return title to author.ifEmpty { "—" }
                }
            }
            return null
        }

        private fun applyLibraryItemMetadata(m: Meta, libraryItem: JsonObject, episodeId: String?) {
            val eid = episodeId.trimmedOrEmpty()
            var showTitle: String? = nonBlankString(libraryItem["displayTitle"])
            var showAuthor: String? = nonBlankString(libraryItem["displayAuthor"])
            val media = libraryItem["media"] as? JsonObject
            val meta = media?.get("metadata") as? JsonObject
            if (meta != null) {
                if (showTitle == null) showTitle = nonBlankString(meta["title"])
                if (showAuthor == null) showAuthor = nonBlankString(meta["author"])
                if (showAuthor == null) showAuthor = nonBlankString(meta["authorName"])
            }

            if (eid.isNotEmpty()) {
                val episodeLists = listOf(SwiftJson.anyObjList(libraryItem["episodes"]), SwiftJson.anyObjList(media?.get("episodes")))
                outer@ for (episodes in episodeLists) {
                    if (episodes == null) continue
                    for (ep in episodes) {
                        val epId = SwiftJson.anyString(ep["id"])?.swiftTrim() ?: ""
                        if (epId.isEmpty() || !episodeIdMatches(epId, eid)) continue
                        val t = nonBlankString(ep["title"]) ?: nonBlankString(ep["displayTitle"])
                        if (t != null) m.title = t
                        // Swift: `break` verlässt nur die innere Schleife.
                        continue@outer
                    }
                }
                if (isPlaceholderMetadata(m.title)) {
                    val recent = libraryItem["recentEpisode"] as? JsonObject
                    if (recent != null && SwiftJson.anyString(recent["id"]) == eid) {
                        nonBlankString(recent["title"])?.let { m.title = it }
                    }
                }
                // Show-Name gehört bei Episodes in die Autoren-/Show-Zeile, nicht in den Titel.
                if (isPlaceholderMetadata(m.author)) {
                    val sa = showAuthor
                    val st = showTitle
                    if (!sa.isNullOrEmpty()) m.author = sa else if (!st.isNullOrEmpty()) m.author = st
                }
                return
            }

            val st = showTitle
            if (st != null && isPlaceholderMetadata(m.title)) m.title = st
            val sa = showAuthor
            if (sa != null && isPlaceholderMetadata(m.author)) {
                m.author = sa
            } else if (meta != null) {
                applyMetadata(m, meta)
            }
        }

        /** iOS: `init?(lenientDictionary:)`. */
        fun fromLenientDictionary(d: JsonObject): AbsAdminMediaProgressRow? {
            fun jsonString(keys: List<String>): String? {
                for (k in keys) {
                    val v = d[k] ?: continue
                    if (SwiftJson.isNull(v)) continue
                    val s = SwiftJson.anyString(v)
                    if (s != null) {
                        val t = s.swiftTrim()
                        if (t.isNotEmpty()) return t
                    } else SwiftJson.anyInt(v)?.let { return it.toString() }
                }
                return null
            }
            fun jsonDouble(keys: List<String>): Double {
                for (k in keys) {
                    val v = d[k] ?: continue
                    if (SwiftJson.isNull(v)) continue
                    SwiftJson.anyDouble(v)?.let { return it }
                    SwiftJson.anyString(v)?.let { s -> swiftDouble(s.swiftTrim())?.let { return it } }
                }
                return 0.0
            }
            fun jsonInt64(keys: List<String>): Long? {
                for (k in keys) {
                    val v = d[k] ?: continue
                    if (SwiftJson.isNull(v)) continue
                    SwiftJson.anyInt(v)?.let { return it }
                    SwiftJson.double(v)?.let { return it.roundedSwift().toLong() }
                }
                return null
            }
            fun jsonBool(keys: List<String>): Boolean {
                for (k in keys) {
                    val v = d[k] ?: continue
                    if (SwiftJson.isNull(v)) continue
                    SwiftJson.anyBool(v)?.let { return it }
                    SwiftJson.anyInt(v)?.let { return it != 0L }
                }
                return false
            }

            val rawId = jsonString(listOf("id")) ?: ""
            val explicitLi = jsonString(listOf("libraryItemId", "library_item_id"))
            val epIdx = rawId.indexOf("-ep_")
            val resolvedLibraryItemId = when {
                !explicitLi.isNullOrEmpty() -> explicitLi
                epIdx >= 0 -> rawId.substring(0, epIdx)
                else -> rawId
            }
            if (resolvedLibraryItemId.isEmpty()) return null

            // episodeId oft nur in Composite-`id` (`<libraryItemId>-ep_…`), nicht als eigenes Feld.
            val resolvedEpisodeId: String? = run {
                val e = jsonString(listOf("episodeId", "episode_id"))
                if (!e.isNullOrEmpty()) return@run e
                if (epIdx >= 0) return@run rawId.substring(epIdx + 1)
                val prefix = "$resolvedLibraryItemId-"
                if (rawId.startsWith(prefix)) rawId.removePrefix(prefix).ifEmpty { null } else null
            }
            val isEpisode = !resolvedEpisodeId.isNullOrEmpty()
            val m = Meta("—", "—")
            ((d["media"] as? JsonObject)?.get("metadata") as? JsonObject)?.let { meta ->
                if (isEpisode) {
                    // Podcast-Show-Metadaten → nur Show-Zeile, nie Episoden-Titel.
                    val ignored = Meta("—", m.author)
                    applyMetadata(ignored, meta)
                    m.author = ignored.author
                } else {
                    applyMetadata(m, meta)
                }
            }
            (d["episode"] as? JsonObject)?.let { applyMetadata(m, it) }
            (d["libraryItem"] as? JsonObject)?.let { applyLibraryItemMetadata(m, it, resolvedEpisodeId) }
            // Top-Level `title`/`displayTitle` bei Episodes oft = Show-Name — ignorieren wenn noch kein Episoden-Titel.
            if (!isEpisode) {
                val topTitle = jsonString(listOf("title", "displayTitle"))
                if (topTitle != null && isPlaceholderMetadata(m.title)) m.title = topTitle
            }
            val topAuthor = jsonString(listOf("author", "authorName", "displayAuthor"))
            if (topAuthor != null && isPlaceholderMetadata(m.author)) m.author = topAuthor

            return AbsAdminMediaProgressRow(
                libraryItemId = resolvedLibraryItemId,
                episodeId = resolvedEpisodeId,
                duration = jsonDouble(listOf("duration")),
                progress = jsonDouble(listOf("progress")),
                currentTime = jsonDouble(listOf("currentTime", "current_time")),
                isFinished = jsonBool(listOf("isFinished", "is_finished")),
                lastUpdate = jsonInt64(listOf("lastUpdate", "last_update")),
                title = m.title,
                author = m.author,
            )
        }
    }
}

/** iOS: `ABSUsersOnlineResponse`. */
@Serializable(with = AbsUsersOnlineResponseSerializer::class)
data class AbsUsersOnlineResponse(val usersOnline: List<AbsAdminUserOnlineRow>?)

/** iOS: `ABSAdminUserOnlineRow`. */
data class AbsAdminUserOnlineRow(val id: String)

object AbsUsersOnlineResponseSerializer : SwiftObjectSerializer<AbsUsersOnlineResponse>("ABSUsersOnlineResponse") {
    private val row = object : SwiftObjectSerializer<AbsAdminUserOnlineRow>("ABSAdminUserOnlineRow") {
        override fun decode(c: JObj) = AbsAdminUserOnlineRow(c.string("id"))
    }
    override fun decode(c: JObj) = AbsUsersOnlineResponse(c.listOrNull("usersOnline", row))
}

/** iOS: `ABSLibraryItemDurationStat` — Eintrag in `longestItems`. */
data class AbsLibraryItemDurationStat(val id: String, val title: String, val duration: Double)

/** iOS: `ABSLibraryItemSizeStat` — Eintrag in `largestItems`. */
data class AbsLibraryItemSizeStat(val id: String, val title: String, val size: Long)

/** iOS: `ABSLibraryAuthorStat` — Eintrag in `authorsWithCount`. */
data class AbsLibraryAuthorStat(val id: String, val name: String, val count: Int)

/** iOS: `ABSLibraryAdminDetail` — `GET /api/libraries/:id?include=filterdata`. */
@Serializable(with = AbsLibraryAdminDetailSerializer::class)
data class AbsLibraryAdminDetail(
    val id: String,
    val name: String,
    val mediaType: String?,
    val icon: String?,
    val provider: String?,
    val folders: List<AbsLibraryFolderRow>?,
    val displayOrder: Int?,
)

object AbsLibraryAdminDetailSerializer : SwiftObjectSerializer<AbsLibraryAdminDetail>("ABSLibraryAdminDetail") {
    override fun decode(c: JObj) = AbsLibraryAdminDetail(
        id = c.string("id"),
        name = c.string("name"),
        mediaType = c.stringOrNull("mediaType"),
        icon = c.stringOrNull("icon"),
        provider = c.stringOrNull("provider"),
        folders = c.listOrNull("folders", AbsLibraryFolderRowSerializer),
        displayOrder = c.intOrNull("displayOrder"),
    )
}

/** iOS: `ABSLibraryDetailEnvelope` — Envelope bei `include=filterdata`. */
@Serializable(with = AbsLibraryDetailEnvelopeSerializer::class)
data class AbsLibraryDetailEnvelope(val library: AbsLibraryAdminDetail, val issues: Int?, val numUserPlaylists: Int?)

object AbsLibraryDetailEnvelopeSerializer : SwiftObjectSerializer<AbsLibraryDetailEnvelope>("ABSLibraryDetailEnvelope") {
    override fun decode(c: JObj) = AbsLibraryDetailEnvelope(
        library = c.obj("library", AbsLibraryAdminDetailSerializer),
        issues = c.intOrNull("issues"),
        numUserPlaylists = c.intOrNull("numUserPlaylists"),
    )
}

/** iOS: `ABSPodcastEpisodeDownload` — aus `GET /api/libraries/:id/episode-downloads`. */
data class AbsPodcastEpisodeDownload(
    val id: String,
    val episodeDisplayTitle: String?,
    val podcastTitle: String?,
    val libraryItemId: String?,
    val isFinished: Boolean?,
    val failed: Boolean?,
    val createdAt: Double?,
)

/** iOS: `ABSLibraryEpisodeDownloadsPayload`. */
@Serializable(with = AbsLibraryEpisodeDownloadsPayloadSerializer::class)
data class AbsLibraryEpisodeDownloadsPayload(
    val currentDownload: AbsPodcastEpisodeDownload?,
    val queue: List<AbsPodcastEpisodeDownload>?,
) {
    val allRows: List<AbsPodcastEpisodeDownload> get() = listOfNotNull(currentDownload) + (queue ?: emptyList())
}

object AbsLibraryEpisodeDownloadsPayloadSerializer : SwiftObjectSerializer<AbsLibraryEpisodeDownloadsPayload>("ABSLibraryEpisodeDownloadsPayload") {
    private val row = object : SwiftObjectSerializer<AbsPodcastEpisodeDownload>("ABSPodcastEpisodeDownload") {
        override fun decode(c: JObj) = AbsPodcastEpisodeDownload(
            id = c.string("id"),
            episodeDisplayTitle = c.stringOrNull("episodeDisplayTitle"),
            podcastTitle = c.stringOrNull("podcastTitle"),
            libraryItemId = c.stringOrNull("libraryItemId"),
            isFinished = c.boolOrNull("isFinished"),
            failed = c.boolOrNull("failed"),
            createdAt = c.doubleOrNull("createdAt"),
        )
    }
    override fun decode(c: JObj) = AbsLibraryEpisodeDownloadsPayload(c.objOrNull("currentDownload", row), c.listOrNull("queue", row))
}

/** iOS: `ABSLibraryStatsResponse`. */
@Serializable(with = AbsLibraryStatsResponseSerializer::class)
data class AbsLibraryStatsResponse(
    val totalItems: Int,
    val totalAuthors: Int,
    val totalGenres: Int,
    val totalDuration: Double,
    val totalSize: Long,
    val numAudioTrack: Int,
    val genresWithCount: List<AbsLibraryGenreStat>,
    val authorsWithCount: List<AbsLibraryAuthorStat>,
    val longestItems: List<AbsLibraryItemDurationStat>,
    val largestItems: List<AbsLibraryItemSizeStat>,
)

object AbsLibraryStatsResponseSerializer : SwiftObjectSerializer<AbsLibraryStatsResponse>("ABSLibraryStatsResponse") {
    private val durationStat = object : SwiftObjectSerializer<AbsLibraryItemDurationStat>("ABSLibraryItemDurationStat") {
        override fun decode(c: JObj) = AbsLibraryItemDurationStat(
            c.string("id"), c.stringOrNull("title") ?: "", c.tryDouble("duration") ?: c.tryInt("duration")?.toDouble() ?: 0.0,
        )
    }
    private val sizeStat = object : SwiftObjectSerializer<AbsLibraryItemSizeStat>("ABSLibraryItemSizeStat") {
        override fun decode(c: JObj) = AbsLibraryItemSizeStat(c.string("id"), c.stringOrNull("title") ?: "", c.tryLong("size") ?: 0)
    }
    private val authorStat = object : SwiftObjectSerializer<AbsLibraryAuthorStat>("ABSLibraryAuthorStat") {
        override fun decode(c: JObj) = AbsLibraryAuthorStat(
            c.string("id"), c.stringOrNull("name") ?: "", c.tryInt("count") ?: c.tryInt("numItems") ?: 0,
        )
    }
    /** iOS: `ABSLibraryGenreStatLoose` — Fallback falls einzelne Zeilen abweichende Keys haben. */
    private val genreLoose = object : SwiftObjectSerializer<AbsLibraryGenreStat?>("ABSLibraryGenreStatLoose") {
        override fun decode(c: JObj): AbsLibraryGenreStat? {
            val genre = c.stringOrNull("genre")
            val count = c.intOrNull("count")
            val numItems = c.intOrNull("numItems")
            val name = genre.trimmedOrEmpty()
            if (name.isEmpty()) return null
            return AbsLibraryGenreStat(name, count ?: numItems ?: 0)
        }
    }

    override fun decode(c: JObj) = AbsLibraryStatsResponse(
        totalItems = c.intOrNull("totalItems") ?: 0,
        totalAuthors = c.intOrNull("totalAuthors") ?: 0,
        totalGenres = c.intOrNull("totalGenres") ?: 0,
        totalDuration = c.tryDouble("totalDuration") ?: 0.0,
        totalSize = c.tryLong("totalSize") ?: 0,
        numAudioTrack = c.intOrNull("numAudioTrack") ?: 0,
        genresWithCount = c.tryList("genresWithCount", AbsLibraryGenreStatSerializer)
            ?: c.tryList("genresWithCount", genreLoose)?.filterNotNull() ?: emptyList(),
        authorsWithCount = c.tryList("authorsWithCount", authorStat) ?: emptyList(),
        longestItems = c.tryList("longestItems", durationStat) ?: emptyList(),
        largestItems = c.tryList("largestItems", sizeStat) ?: emptyList(),
    )
}

/** iOS: `ABSServerSettings` — aus `/login`, `/authorize` und `PATCH /api/settings`. */
@Serializable(with = AbsServerSettingsSerializer::class)
data class AbsServerSettings(
    var scannerFindCovers: Boolean? = null,
    var scannerParseSubtitle: Boolean? = null,
    var scannerPreferMatchedMetadata: Boolean? = null,
    var scannerDisableWatcher: Boolean? = null,
    var storeCoverWithItem: Boolean? = null,
    var storeMetadataWithItem: Boolean? = null,
    var chromecastEnabled: Boolean? = null,
    var sortingIgnorePrefix: Boolean? = null,
    var logLevel: Int? = null,
    var language: String? = null,
    var version: String? = null,
)

object AbsServerSettingsSerializer : SwiftObjectSerializer<AbsServerSettings>("ABSServerSettings") {
    override fun decode(c: JObj) = AbsServerSettings(
        scannerFindCovers = c.boolOrNull("scannerFindCovers"),
        scannerParseSubtitle = c.boolOrNull("scannerParseSubtitle"),
        scannerPreferMatchedMetadata = c.boolOrNull("scannerPreferMatchedMetadata"),
        scannerDisableWatcher = c.boolOrNull("scannerDisableWatcher"),
        storeCoverWithItem = c.boolOrNull("storeCoverWithItem"),
        storeMetadataWithItem = c.boolOrNull("storeMetadataWithItem"),
        chromecastEnabled = c.boolOrNull("chromecastEnabled"),
        sortingIgnorePrefix = c.boolOrNull("sortingIgnorePrefix"),
        logLevel = c.intOrNull("logLevel"),
        language = c.stringOrNull("language"),
        version = c.stringOrNull("version"),
    )

    override fun encode(v: AbsServerSettings) = jsonObjectOf {
        putIfPresent("scannerFindCovers", v.scannerFindCovers)
        putIfPresent("scannerParseSubtitle", v.scannerParseSubtitle)
        putIfPresent("scannerPreferMatchedMetadata", v.scannerPreferMatchedMetadata)
        putIfPresent("scannerDisableWatcher", v.scannerDisableWatcher)
        putIfPresent("storeCoverWithItem", v.storeCoverWithItem)
        putIfPresent("storeMetadataWithItem", v.storeMetadataWithItem)
        putIfPresent("chromecastEnabled", v.chromecastEnabled)
        putIfPresent("sortingIgnorePrefix", v.sortingIgnorePrefix)
        putIfPresent("logLevel", v.logLevel)
        putIfPresent("language", v.language)
        putIfPresent("version", v.version)
    }
}

/** iOS: `ABSServerSettingsPatchResponse`. */
@Serializable(with = AbsServerSettingsPatchResponseSerializer::class)
data class AbsServerSettingsPatchResponse(val success: Boolean?, val serverSettings: AbsServerSettings?)

object AbsServerSettingsPatchResponseSerializer : SwiftObjectSerializer<AbsServerSettingsPatchResponse>("ABSServerSettingsPatchResponse") {
    override fun decode(c: JObj) = AbsServerSettingsPatchResponse(c.boolOrNull("success"), c.objOrNull("serverSettings", AbsServerSettingsSerializer))
}

/** iOS: `ABSSessionSyncBody`. */
@Serializable
data class AbsSessionSyncBody(val timeListened: Int, val currentTime: Double)

/** iOS: `ABSPodcastMediaAutoDownloadPatch`. */
@Serializable
data class AbsPodcastMediaAutoDownloadPatch(
    val autoDownloadEpisodes: Boolean,
    val autoDownloadSchedule: String,
    val maxEpisodesToKeep: Int,
    val maxNewEpisodesToDownload: Int,
)

/** iOS: `ABSProgressPatch` — nur gesetzte Felder werden kodiert. */
@Serializable
data class AbsProgressPatch(
    val currentTime: Double? = null,
    val duration: Double? = null,
    val progress: Double? = null,
    val isFinished: Boolean? = null,
    /** E-Book-Lesefortschritt 0…1 — eigene Spalte in der Progress-Zeile, unabhängig vom Hör-Fortschritt. */
    val ebookProgress: Double? = null,
)

// MARK: - Listening stats (`GET /api/me/listening-stats`)

/** Wochentag nach Swift-`Calendar` (1 = Sonntag … 7 = Samstag). */
internal fun LocalDate.swiftWeekday(): Int = dayOfWeek.value % 7 + 1

/** Swift-`Calendar.firstWeekday` für eine Locale (1 = Sonntag, 2 = Montag). */
internal fun swiftFirstWeekday(locale: Locale): Int = WeekFields.of(locale).firstDayOfWeek.value % 7 + 1

/**
 * iOS: `ABSListeningStatsResponse` — tolerant gegen Float-Zahlen, fehlende Teilfelder und kaputte
 * einzelne `items`-Einträge.
 */
@Serializable(with = AbsListeningStatsResponseSerializer::class)
data class AbsListeningStatsResponse(
    val totalTime: Int,
    val today: Int,
    val days: Map<String, Int>,
    val dayOfWeek: Map<String, Int>,
    val items: Map<String, AbsListeningStatsItemAggregate>,
    val recentSessions: List<AbsListeningStatsRecentSession>,
) {
    /** Höchste Hördauer zuerst (für „Meist gehört“). */
    val itemsSortedByListeningTime: List<Pair<String, AbsListeningStatsItemAggregate>>
        get() = items.map { it.key to it.value }.filter { it.second.id.isNotEmpty() }.sortedByDescending { it.second.timeListening }

    fun secondsInLastDays(dayCount: Int, today: LocalDate = LocalDate.now()): Int {
        var sum = 0
        for (i in 0 until maxOf(0, dayCount)) sum += days[dayKey(today.minusDays(i.toLong()))] ?: 0
        return sum
    }

    /** Wochentage Mo–So für Balkendiagramm (`dayOfWeek`: Server oft `0` = Sonntag). */
    fun dayOfWeekBars(locale: Locale = Locale.getDefault()): List<Triple<String, String, Int>> {
        if (dayOfWeek.isEmpty()) return emptyList()
        val label = DateTimeFormatter.ofPattern("EEE", locale)
        val monday = LocalDate.of(2024, 1, 1)
        return (0 until 7).map { offset ->
            val d = monday.plusDays(offset.toLong())
            val weekday = d.swiftWeekday()
            val jsDow = weekday - 1
            val sec = dayOfWeek[jsDow.toString()] ?: dayOfWeek[weekday.toString()] ?: 0
            Triple(offset.toString(), label.format(d), sec)
        }
    }

    /** Letzte 7 Tage (ältester Tag zuerst) für Diagramme — Schlüssel `id` = `yyyy-MM-dd`. */
    fun lastSevenDayBars(today: LocalDate = LocalDate.now(), locale: Locale = Locale.getDefault()): List<Triple<String, String, Int>> {
        val df = DateTimeFormatter.ofPattern("EEE", locale)
        return (0 until 7).map { offset ->
            val d = today.plusDays((offset - 6).toLong())
            val k = dayKey(d)
            Triple(k, df.format(d), days[k] ?: 0)
        }
    }

    /** Sekunden im aktuellen Kalendermonat (lokale Zeitzone). */
    fun secondsThisCalendarMonth(today: LocalDate = LocalDate.now()): Int =
        days.entries.filter { it.value > 0 }.sumOf { (key, sec) ->
            val d = parseDayKey(key) ?: return@sumOf 0
            if (d.year == today.year && d.monthValue == today.monthValue) sec else 0
        }

    /** Summe der `days`-Einträge im laufenden Kalenderjahr (lokal). */
    fun secondsThisCalendarYear(today: LocalDate = LocalDate.now()): Int =
        days.entries.filter { it.value > 0 }.sumOf { (key, sec) ->
            val d = parseDayKey(key) ?: return@sumOf 0
            if (d.year == today.year) sec else 0
        }

    val daysActive: Int get() = days.values.count { it > 0 }

    /** Höchste Hörzeit an einem einzelnen Tag (`days`-Map), in Sekunden. */
    val marathonDayListeningSeconds: Int get() = days.values.maxOrNull() ?: 0

    /** Verschiedene Autoren/Podcast-Ersteller mit Hörzeit > 0 (normalisiert, case-insensitive). */
    val distinctListenedAuthorCount: Int
        get() {
            val keys = HashSet<String>()
            for (item in items.values) {
                if (item.timeListening <= 0) continue
                val meta = item.mediaMetadata ?: continue
                meta.listeningStatsAuthorKeys().filter { it.isNotEmpty() }.forEach { keys.add(it) }
            }
            return keys.size
        }

    /** Tage mit Hörzeit im rollierenden Jahr (Heatmap-Zähler, unabhängig von sichtbaren Wochen). */
    fun daysListenedInLastYear(today: LocalDate = LocalDate.now(), locale: Locale = Locale.getDefault()): Int =
        yearListeningHeatmap(weeksToShow = 52, today = today, locale = locale).daysListenedInLastYear

    /** Tagesdurchschnitt über Tage mit Aktivität. */
    val dailyAverageSeconds: Int get() = totalTime / maxOf(daysActive, 1)

    val totalTimeAsCalendarDaysApprox: Double get() = totalTime.toDouble() / 86_400.0

    fun currentListeningStreakDays(today: LocalDate = LocalDate.now()): Int {
        val active = activeDayStarts()
        if (active.isEmpty()) return 0
        val yesterday = today.minusDays(1)
        var cursor = when {
            today in active -> today
            yesterday in active -> yesterday
            else -> return 0
        }
        var streak = 0
        while (cursor in active) {
            streak += 1
            cursor = cursor.minusDays(1)
        }
        return streak
    }

    fun bestListeningStreakDays(): Int {
        val sorted = activeDayStarts().sorted()
        if (sorted.size < 2) return if (sorted.isEmpty()) 0 else 1
        var best = 1
        var run = 1
        for (i in 1 until sorted.size) {
            if (sorted[i - 1].plusDays(1) == sorted[i]) {
                run += 1
                best = maxOf(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    val bookLikeItemCount: Int get() = items.values.count { !(it.mediaMetadata?.isPodcastLike ?: false) }
    val podcastLikeItemCount: Int get() = items.values.count { it.mediaMetadata?.isPodcastLike ?: false }

    private fun activeDayStarts(): Set<LocalDate> =
        days.entries.filter { it.value > 0 }.mapNotNull { parseDayKey(it.key) }.toSet()

    /** Frühester Kalendermonat mit mindestens einem `days`-Eintrag (Navigation untere Grenze). */
    fun earliestListeningMonthStart(): LocalDate? = days.keys.mapNotNull { parseDayKey(it) }.minOrNull()?.withDayOfMonth(1)

    /** Monats-Kalender-Heatmap (7 Spalten, Mo–So bei `firstWeekday == 2`). */
    fun monthListeningHeatmap(
        monthContaining: LocalDate,
        locale: Locale = Locale.getDefault(),
        firstWeekday: Int = swiftFirstWeekday(locale),
    ): AbsListeningMonthHeatmap {
        val monthStart = monthContaining.withDayOfMonth(1)
        val dayCount = monthStart.lengthOfMonth()
        val leading = (monthStart.swiftWeekday() - firstWeekday + 7) % 7
        val rowCount = (leading + dayCount + 6) / 7
        val slotCount = rowCount * 7
        val monthFormatter = DateTimeFormatter.ofPattern("LLLL yyyy", locale)
        val prettyFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)

        data class Staged(val col: Int, val row: Int, val key: String, val date: LocalDate, val day: Int, val seconds: Int, val inMonth: Boolean)
        val inMonthPositive = ArrayList<Int>()
        val staged = ArrayList<Staged>(slotCount)
        for (slot in 0 until slotCount) {
            val dayOffset = slot - leading
            val cellDate = monthStart.plusDays(dayOffset.toLong())
            val inMonth = dayOffset in 0 until dayCount
            val key = dayKey(cellDate)
            val seconds = days[key] ?: 0
            if (inMonth && seconds > 0) inMonthPositive.add(seconds)
            staged.add(Staged(slot % 7, slot / 7, key, cellDate, cellDate.dayOfMonth, seconds, inMonth))
        }
        val minValue = inMonthPositive.minOrNull() ?: 0
        val maxValue = inMonthPositive.maxOrNull() ?: 0
        var daysListenedInMonth = 0
        var totalSecondsInMonth = 0
        val cells = staged.map { item ->
            if (item.inMonth) {
                if (item.seconds > 0) daysListenedInMonth += 1
                totalSecondsInMonth += item.seconds
            }
            val level = heatmapColorLevel(if (item.inMonth) item.seconds else 0, minValue, maxValue)
            val pretty = prettyFormatter.format(item.date)
            val a11y = when {
                !item.inMonth -> "$pretty, outside month"
                item.seconds > 0 -> "$pretty, ${formatPlaybackDurationShortHuman(item.seconds.toDouble())}"
                else -> "$pretty, no listening"
            }
            AbsListeningMonthHeatmap.Cell(item.key, item.col, item.row, item.day, item.inMonth, item.seconds, level, a11y)
        }
        return AbsListeningMonthHeatmap(
            year = monthStart.year,
            month = monthStart.monthValue,
            monthTitle = monthFormatter.format(monthStart),
            rowCount = rowCount,
            daysListenedInMonth = daysListenedInMonth,
            totalSecondsInMonth = totalSecondsInMonth,
            cells = cells,
        )
    }

    /** GitHub-ähnliche Heatmap (vgl. Audiobookshelf `Heatmap.vue` / Server-UI Stats). */
    fun yearListeningHeatmap(
        weeksToShow: Int = 52,
        today: LocalDate = LocalDate.now(),
        locale: Locale = Locale.getDefault(),
        firstWeekday: Int = swiftFirstWeekday(locale),
    ): AbsListeningYearHeatmap {
        val dayOfWeekToday = (today.swiftWeekday() - firstWeekday + 7) % 7
        val cappedWeeks = minOf(52, maxOf(1, weeksToShow))
        val daysToShow = cappedWeeks * 7 + dayOfWeekToday
        val numDaysInLastYear = 52 * 7 + dayOfWeekToday
        val firstDay = today.minusDays(numDaysInLastYear.toLong())
        val prettyFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)

        var daysListenedInLastYear = 0
        data class Staged(val col: Int, val row: Int, val key: String, val date: LocalDate, val seconds: Int)
        val staged = ArrayList<Staged>()
        var maxValue = 0
        var minValue = 0
        for (i in 0..numDaysInLastYear) {
            val date = firstDay.plusDays(i.toLong())
            val key = dayKey(date)
            val seconds = days[key] ?: 0
            if (seconds > 0) daysListenedInLastYear += 1
            val visibleDayIndex = i - (numDaysInLastYear - daysToShow)
            if (visibleDayIndex < 0) continue
            staged.add(Staged(visibleDayIndex / 7, visibleDayIndex % 7, key, date, seconds))
            if (seconds > 0) {
                maxValue = maxOf(maxValue, seconds)
                minValue = if (minValue == 0) seconds else minOf(minValue, seconds)
            }
        }
        val cells = staged.map { item ->
            val level = heatmapColorLevel(item.seconds, minValue, maxValue)
            val pretty = prettyFormatter.format(item.date)
            val a11y = if (item.seconds > 0) "$pretty, ${formatPlaybackDurationShortHuman(item.seconds.toDouble())}" else "$pretty, no listening"
            AbsListeningYearHeatmap.Cell(item.key, item.col, item.row, item.seconds, level, a11y)
        }
        val columnCount = (cells.maxOfOrNull { it.column } ?: 0) + 1
        val monthLabels = monthLabelsForHeatmapColumns(columnCount, cells, locale, if (columnCount > 44) 2 else 1)
        return AbsListeningYearHeatmap(daysListenedInLastYear, cells, monthLabels, columnCount)
    }

    companion object {
        private fun dayKey(date: LocalDate): String = String.format(Locale.ROOT, "%04d-%02d-%02d", date.year, date.monthValue, date.dayOfMonth)

        /** iOS: `parseDayKey` — `Calendar.date(from:)` ist nachsichtig (31.02. → 02.03.), hier ebenso. */
        fun parseDayKey(key: String): LocalDate? {
            val parts = key.swiftTrim().split("-").filter { it.isNotEmpty() }.mapNotNull { it.toIntOrNull() }
            if (parts.size != 3) return null
            return runCatching {
                LocalDate.of(parts[0], 1, 1).plusMonths((parts[1] - 1).toLong()).plusDays((parts[2] - 1).toLong())
            }.getOrNull()
        }

        private fun heatmapColorLevel(seconds: Int, minValue: Int, maxValue: Int): Int {
            if (seconds <= 0) return 0
            if (maxValue <= 0) return 0
            if (maxValue == minValue) return 4
            val range = maxOf(maxValue - minValue, 0).toDouble() + 0.01
            val pct = (seconds - minValue).toDouble() / range
            return minOf(4, (pct * 4.0).toInt() + 1)
        }

        /** Erste Spalte jedes Kalendermonats; `labelEveryNthMonth` 1 = alle, 2 = jeden zweiten. */
        private fun monthLabelsForHeatmapColumns(
            columnCount: Int,
            cells: List<AbsListeningYearHeatmap.Cell>,
            locale: Locale,
            labelEveryNthMonth: Int,
        ): List<AbsListeningYearHeatmap.MonthLabel> {
            val stride = maxOf(1, labelEveryNthMonth)
            val monthFormatter = DateTimeFormatter.ofPattern("LLL", locale)
            val labels = ArrayList<AbsListeningYearHeatmap.MonthLabel>()
            var lastMonthKey: String? = null
            var monthIndex = 0
            for (col in 0 until columnCount) {
                val anchor = cells.firstOrNull { it.column == col && it.row == 0 }
                    ?: cells.filter { it.column == col }.minByOrNull { it.row } ?: continue
                val date = parseDayKey(anchor.id) ?: continue
                val key = "${date.year}-${date.monthValue}"
                if (key == lastMonthKey) continue
                lastMonthKey = key
                if (monthIndex % stride == 0) {
                    labels.add(AbsListeningYearHeatmap.MonthLabel("${anchor.id}-month", col, monthFormatter.format(date)))
                }
                monthIndex += 1
            }
            return labels
        }

        /**
         * Dekodierung: Standard-JSON (camelCase wie in der API-Doku) oder `snake_case` (Proxys / ältere
         * Server). Der camelCase-Decoder scheitert an snake_case nie — daher wie iOS anhand der
         * Top-Level-Keys bewusst wählen.
         */
        fun decodeAPIPayload(data: String): AbsListeningStatsResponse =
            if (usesSnakeCaseKeys(data)) {
                AbsJson.decoderListeningStats.decodeFromString(AbsListeningStatsResponseSerializer, data)
            } else {
                AbsJson.decoder.decodeFromString(AbsListeningStatsResponseSerializer, data)
            }

        /** iOS: `usesSnakeCaseKeys` — `total_time`/`day_of_week`/`recent_sessions` statt camelCase. */
        fun usesSnakeCaseKeys(data: String): Boolean {
            val root = runCatching { AbsJson.decoder.parseToJsonElement(data) }.getOrNull() as? JsonObject ?: return false
            if (root.keys.any { it in setOf("totalTime", "dayOfWeek", "recentSessions") }) return false
            return root.keys.any { it in setOf("total_time", "day_of_week", "recent_sessions") }
        }
    }
}

private fun flexibleInt(c: JObj, key: String): Int =
    c.tryInt(key) ?: c.tryDouble(key)?.roundedSwift()?.toInt() ?: c.tryLong(key)?.toInt() ?: 0

private fun flexibleDouble(c: JObj, key: String): Double =
    c.tryDouble(key) ?: c.tryInt(key)?.toDouble() ?: c.tryLong(key)?.toDouble() ?: 0.0

object AbsListeningStatsResponseSerializer : SwiftObjectSerializer<AbsListeningStatsResponse>("ABSListeningStatsResponse") {
    /** Tag / Wochentag → Sekunden (Server liefert manchmal `Double`). */
    private fun stringIntDictionary(c: JObj, key: String): Map<String, Int> {
        if (!c.contains(key)) return emptyMap()
        val obj = c[key] as? JsonObject ?: return emptyMap()
        val ints = obj.mapValues { SwiftJson.int(it.value) }
        if (ints.values.all { it != null }) return ints.mapValues { it.value!! }
        val doubles = obj.mapValues { SwiftJson.double(it.value) }
        if (doubles.values.all { it != null }) return doubles.mapValues { it.value!!.roundedSwift().toInt() }
        return emptyMap()
    }

    private fun itemsSkippingBroken(c: JObj): Map<String, AbsListeningStatsItemAggregate> {
        if (!c.contains("items")) return emptyMap()
        val nested = c["items"] as? JsonObject ?: return emptyMap()
        val out = LinkedHashMap<String, AbsListeningStatsItemAggregate>()
        for ((kid, value) in nested) {
            val item = runCatching { AbsListeningStatsItemAggregateSerializer.decode(value) }.getOrNull() ?: continue
            out[kid] = if (item.id.isEmpty()) item.withLibraryItemIdFallback(kid) else item
        }
        return out
    }

    override fun decode(c: JObj) = AbsListeningStatsResponse(
        totalTime = flexibleInt(c, "totalTime"),
        today = flexibleInt(c, "today"),
        days = stringIntDictionary(c, "days"),
        dayOfWeek = stringIntDictionary(c, "dayOfWeek"),
        items = itemsSkippingBroken(c),
        // Zeilenweise tolerant (iOS `decodeRecentSessionsLenient`): eine kaputte Zeile leert nicht die Liste.
        recentSessions = (c["recentSessions"] as? JsonArray)
            ?.mapNotNull { row -> runCatching { AbsListeningStatsRecentSessionSerializer.decode(row) }.getOrNull() }
            ?: emptyList(),
    )
}

/** iOS: `ABSListeningStatsItemAggregate`. */
data class AbsListeningStatsItemAggregate(
    val id: String,
    val timeListening: Int,
    val mediaMetadata: AbsListeningStatsMetadata?,
) {
    fun withLibraryItemIdFallback(libraryItemId: String) = copy(id = id.ifEmpty { libraryItemId })
}

object AbsListeningStatsItemAggregateSerializer : SwiftObjectSerializer<AbsListeningStatsItemAggregate>("ABSListeningStatsItemAggregate") {
    override fun decode(c: JObj) = AbsListeningStatsItemAggregate(
        id = c.stringOrNull("id") ?: "",
        timeListening = flexibleInt(c, "timeListening"),
        mediaMetadata = c.tryObj("mediaMetadata", AbsListeningStatsMetadataSerializer),
    )
}

/** iOS: `ABSListeningStatsMetadata`. */
data class AbsListeningStatsMetadata(
    val title: String?,
    val author: String?,
    val authorName: String?,
    val authors: List<AbsAuthor>?,
    val feedUrl: String?,
    val type: String?,
) {
    val displayTitle: String get() = title.trimmedOrEmpty().ifEmpty { "—" }

    /** Autorzeile für Stats-Karten (Bücher: `authorName` / `authors`; Podcasts: oft `author`). */
    val displayAuthorLine: String
        get() {
            if (!authors.isNullOrEmpty()) {
                val t = authors.joinToString(", ") { it.name }.swiftTrim()
                if (t.isNotEmpty()) return t
            }
            val a = author.trimmedOrEmpty()
            if (a.isNotEmpty()) return a
            return authorName.trimmedOrEmpty().ifEmpty { "—" }
        }

    /** Alias für ältere Aufrufer. */
    val displaySubtitle: String get() = displayAuthorLine

    /** Autor-Schlüssel für Achievements (ein Eintrag pro Person/Show-Zeile). */
    fun listeningStatsAuthorKeys(): List<String> {
        if (!authors.isNullOrEmpty()) return authors.map { it.name.swiftTrim().lowercase() }.filter { it.isNotEmpty() }
        val line = displayAuthorLine
        if (line == "—") return emptyList()
        return line.split(",").filter { it.isNotEmpty() }.map { it.swiftTrim().lowercase() }.filter { it.isNotEmpty() }
    }

    /** Heuristik Buch vs. Podcast-Show (Server liefert unterschiedliche Metadaten). */
    val isPodcastLike: Boolean
        get() {
            if (feedUrl != null) return true
            val t = type.trimmedOrEmpty().lowercase()
            return t == "episodic" || t == "serial"
        }

    /** Minimaler Katalog-Stub für Stats-Navigation, wenn das Item nicht im lokalen Cache liegt. */
    fun stubBook(libraryItemId: String) = AbsBook(
        id = libraryItemId,
        libraryId = null,
        media = AbsBookMedia(
            metadata = AbsBookMediaMetadata.offline(offlineTitle = displayTitle, authorLine = displayAuthorLine),
            duration = null, numTracks = null, chapters = null, tracks = null,
        ),
        addedAt = null,
        updatedAt = null,
    )
}

object AbsListeningStatsMetadataSerializer : SwiftObjectSerializer<AbsListeningStatsMetadata>("ABSListeningStatsMetadata") {
    private fun authorsLenient(c: JObj): List<AbsAuthor>? {
        c.tryList("authors", AbsAuthorSerializer)?.takeIf { it.isNotEmpty() }?.let { return it }
        c.tryList("authors", ElementDecoder.string)?.let { names ->
            val mapped = names.map { it.swiftTrim() }.filter { it.isNotEmpty() }.mapIndexed { i, n -> AbsAuthor("stats-author-$i", n) }
            return mapped.ifEmpty { null }
        }
        return null
    }

    override fun decode(c: JObj) = AbsListeningStatsMetadata(
        title = c.stringOrNull("title"),
        author = c.stringOrNull("author"),
        authorName = c.stringOrNull("authorName"),
        authors = authorsLenient(c),
        feedUrl = c.stringOrNull("feedUrl"),
        type = c.stringOrNull("type"),
    )
}

/** iOS: `ABSListeningStatsRecentSession`. */
data class AbsListeningStatsRecentSession(
    val id: String,
    val libraryItemId: String,
    val episodeId: String?,
    val displayTitle: String?,
    val displayAuthor: String?,
    val mediaType: String?,
    val timeListening: Int,
    val startTime: Double,
    val startedAt: Long,
) {
    /** Podcast-Folge (nicht Hörbuch) — `episodeId` und/oder `mediaType == podcast`. */
    val isPodcastEpisodeSession: Boolean get() = episodeId.trimmedOrEmpty().isNotEmpty()
}

object AbsListeningStatsRecentSessionSerializer : SwiftObjectSerializer<AbsListeningStatsRecentSession>("ABSListeningStatsRecentSession") {
    override fun decode(c: JObj) = AbsListeningStatsRecentSession(
        id = c.stringOrNull("id") ?: "",
        libraryItemId = c.stringOrNull("libraryItemId")?.takeIf { it.isNotEmpty() } ?: "",
        episodeId = c.stringOrNull("episodeId"),
        displayTitle = c.stringOrNull("displayTitle"),
        displayAuthor = c.stringOrNull("displayAuthor"),
        mediaType = c.stringOrNull("mediaType"),
        timeListening = flexibleInt(c, "timeListening"),
        startTime = flexibleDouble(c, "startTime"),
        startedAt = c.tryLong("startedAt") ?: c.tryDouble("startedAt")?.roundedSwift()?.toLong() ?: 0,
    )
}

/** iOS: `ABSListeningYearHeatmap` — Jahres-Heatmap aus `days` (`yyyy-MM-dd` → Sekunden). */
data class AbsListeningYearHeatmap(
    val daysListenedInLastYear: Int,
    val cells: List<Cell>,
    val monthLabels: List<MonthLabel>,
    val columnCount: Int,
) {
    data class Cell(val id: String, val column: Int, val row: Int, val seconds: Int, val colorLevel: Int, val accessibilityLabel: String)
    data class MonthLabel(val id: String, val column: Int, val label: String)

    fun cell(column: Int, row: Int): Cell? = cells.firstOrNull { it.column == column && it.row == row }

    companion object {
        val empty = AbsListeningYearHeatmap(0, emptyList(), emptyList(), 0)
    }
}

/** iOS: `ABSListeningMonthHeatmap` — Monats-Kalender-Heatmap (Wochenzeilen, 7 Spalten). */
data class AbsListeningMonthHeatmap(
    val year: Int,
    val month: Int,
    val monthTitle: String,
    val rowCount: Int,
    val daysListenedInMonth: Int,
    val totalSecondsInMonth: Int,
    val cells: List<Cell>,
) {
    data class Cell(
        val id: String,
        val column: Int,
        val row: Int,
        val day: Int,
        val isInDisplayedMonth: Boolean,
        val seconds: Int,
        val colorLevel: Int,
        val accessibilityLabel: String,
    )

    val columnCount: Int get() = 7

    fun cell(column: Int, row: Int): Cell? = cells.firstOrNull { it.column == column && it.row == row }

    companion object {
        val empty = AbsListeningMonthHeatmap(0, 0, "—", 0, 0, 0, emptyList())
    }
}
