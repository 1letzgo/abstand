package de.letzgo.abstand.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

// iOS: DownloadManifest.swift

/**
 * iOS: `DownloadCatalogEntry` — Anzeige-Metadaten zu einer Download-Storage-ID, unabhängig davon
 * ob Katalog- oder Manifest-Quelle.
 */
data class DownloadCatalogEntry(
    val libraryItemId: String,
    val title: String?,
    val subtitle: String?,
    val isPodcastEpisode: Boolean,
)

/**
 * iOS: `ABSDownloadManifest` — `download.json` neben den Track-Dateien, damit lokale Wiedergabe
 * dieselbe Track-Liste/Indizes wie der Download nutzt. Feldnamen und Key-Sortierung identisch zu iOS
 * (`JSONEncoder.outputFormatting = .sortedKeys`).
 */
@kotlinx.serialization.Serializable(with = AbsDownloadManifestSerializer::class)
data class AbsDownloadManifest(
    /** Schema-Version für spätere Migrationen. */
    val format: Int,
    val libraryItemId: String,
    /** Podcast-Folge (optional); Hörbücher ohne Folge = `null`. */
    val episodeId: String? = null,
    /** Bibliotheks-ID zum Filtern / Anzeige (ohne API offline nutzbar). */
    val libraryId: String?,
    /** Anzeige aus dem Buch zum Zeitpunkt des Downloads (nicht vom Server geliefert). */
    val displayTitle: String?,
    val displayAuthor: String?,
    val playSessionId: String?,
    /** Sekunden seit 1970 (zuverlässiger als ISO8601-Strings zwischen Encoder/Decoder). */
    val savedAtEpoch: Double,
    /** Dateiendung der gespeicherten Tracks (z. B. `m4a`, `mp3`) ohne Punkt. */
    val audioFileExtension: String?,
    val totalDuration: Double?,
    val tracks: List<Track>,
    /** Kapitelmarken für Offline-Wiedergabe und Detailansicht (ältere `download.json` ohne Feld). */
    val chapters: List<Chapter>? = null,
) {
    /** iOS: `ABSDownloadManifest.Track`. */
    data class Track(val index: Int, val startOffset: Double, val duration: Double, val title: String?)

    /** iOS: `ABSDownloadManifest.Chapter`. */
    data class Chapter(val id: Int, val start: Double, val end: Double, val title: String) {
        companion object {
            fun from(ch: AbsChapter) = Chapter(ch.id, ch.start, ch.end, ch.title)
        }
    }

    /** Ordnername unter `Downloads` (bei Podcast-Folgen ≠ `libraryItemId`). */
    val offlineStorageItemId: String
        get() {
            val lid = libraryItemId.swiftTrim()
            val eid = episodeId.trimmedOrEmpty()
            if (lid.isEmpty()) return libraryItemId
            if (eid.isEmpty()) return lid
            return "$lid-$eid".replace("/", "_")
        }

    /** iOS: `write(to:)` — atomar, Keys sortiert. */
    fun write(downloadRoot: File) {
        val target = File(downloadRoot, FILENAME)
        val tmp = File(downloadRoot, "$FILENAME.tmp")
        tmp.writeText(encodeToString(this))
        if (!tmp.renameTo(target)) {
            tmp.copyTo(target, overwrite = true)
            tmp.delete()
        }
    }

    companion object {
        const val FILENAME = "download.json"

        fun load(downloadRoot: File): AbsDownloadManifest? {
            val f = File(downloadRoot, FILENAME)
            val text = runCatching { f.readText() }.getOrNull() ?: return null
            return runCatching { AbsJson.decoder.decodeFromString(AbsDownloadManifestSerializer, text) }.getOrNull()
        }

        /** JSON mit alphabetisch sortierten Keys (auch in verschachtelten Objekten), wie iOS `.sortedKeys`. */
        fun encodeToString(m: AbsDownloadManifest): String = sortKeys(AbsDownloadManifestSerializer.encode(m)).toString()

        private fun sortKeys(e: JsonElement): JsonElement = when (e) {
            is JsonObject -> JsonObject(e.entries.sortedBy { it.key }.associateTo(LinkedHashMap()) { it.key to sortKeys(it.value) })
            is JsonArray -> JsonArray(e.map { sortKeys(it) })
            else -> e
        }
    }
}

object AbsDownloadManifestSerializer : SwiftObjectSerializer<AbsDownloadManifest>("ABSDownloadManifest") {
    private val track = object : SwiftObjectSerializer<AbsDownloadManifest.Track>("ABSDownloadManifest.Track") {
        override fun decode(c: JObj) = AbsDownloadManifest.Track(c.int("index"), c.double("startOffset"), c.double("duration"), c.stringOrNull("title"))
    }
    private val chapter = object : SwiftObjectSerializer<AbsDownloadManifest.Chapter>("ABSDownloadManifest.Chapter") {
        override fun decode(c: JObj) = AbsDownloadManifest.Chapter(c.int("id"), c.double("start"), c.double("end"), c.string("title"))
    }

    private fun isoSeconds(s: String): Double = runCatching {
        val odt = OffsetDateTime.parse(s, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
        odt.toEpochSecond() + odt.nano / 1_000_000_000.0
    }.getOrDefault(0.0)

    override fun decode(c: JObj): AbsDownloadManifest {
        val savedAtEpoch = c.doubleOrNull("savedAtEpoch")
            ?: c.stringOrNull("savedAt")?.let { isoSeconds(it) }
            ?: 0.0
        return AbsDownloadManifest(
            format = c.int("format"),
            libraryItemId = c.string("libraryItemId"),
            episodeId = c.stringOrNull("episodeId"),
            libraryId = c.stringOrNull("libraryId"),
            displayTitle = c.stringOrNull("displayTitle"),
            displayAuthor = c.stringOrNull("displayAuthor"),
            playSessionId = c.stringOrNull("playSessionId"),
            savedAtEpoch = savedAtEpoch,
            audioFileExtension = c.stringOrNull("audioFileExtension"),
            totalDuration = c.doubleOrNull("totalDuration"),
            tracks = c.list("tracks", track),
            chapters = c.listOrNull("chapters", chapter),
        )
    }

    override fun encode(v: AbsDownloadManifest) = jsonObjectOf {
        put("format", JsonPrimitive(v.format))
        put("libraryItemId", JsonPrimitive(v.libraryItemId))
        putIfPresent("episodeId", v.episodeId)
        putIfPresent("libraryId", v.libraryId)
        putIfPresent("displayTitle", v.displayTitle)
        putIfPresent("displayAuthor", v.displayAuthor)
        putIfPresent("playSessionId", v.playSessionId)
        put("savedAtEpoch", JsonPrimitive(v.savedAtEpoch))
        putIfPresent("audioFileExtension", v.audioFileExtension)
        putIfPresent("totalDuration", v.totalDuration)
        putList("tracks", v.tracks) { t ->
            jsonObjectOf {
                put("index", JsonPrimitive(t.index)); put("startOffset", JsonPrimitive(t.startOffset))
                put("duration", JsonPrimitive(t.duration)); putIfPresent("title", t.title)
            }
        }
        putList("chapters", v.chapters) { ch ->
            jsonObjectOf {
                put("id", JsonPrimitive(ch.id)); put("start", JsonPrimitive(ch.start))
                put("end", JsonPrimitive(ch.end)); put("title", JsonPrimitive(ch.title))
            }
        }
    }
}
