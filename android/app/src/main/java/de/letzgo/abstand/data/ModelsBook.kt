package de.letzgo.abstand.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File

// iOS: ABSModels.swift (Teil 2: Buch / Library-Item, Metadaten-Match, Kapitel, Spuren, Dateien).

/** iOS: `ABSAuthor`. */
@Serializable(with = AbsAuthorSerializer::class)
data class AbsAuthor(val id: String, val name: String)

object AbsAuthorSerializer : SwiftObjectSerializer<AbsAuthor>("ABSAuthor") {
    override fun decode(c: JObj) = AbsAuthor(c.string("id"), c.string("name"))
    override fun encode(v: AbsAuthor) = jsonObjectOf {
        put("id", JsonPrimitive(v.id)); put("name", JsonPrimitive(v.name))
    }
}

/** iOS: `ABSSeries`. */
@Serializable(with = AbsSeriesSerializer::class)
data class AbsSeries(val id: String, val name: String, val sequence: String?)

object AbsSeriesSerializer : SwiftObjectSerializer<AbsSeries>("ABSSeries") {
    override fun decode(c: JObj) = AbsSeries(c.string("id"), c.string("name"), c.stringOrNull("sequence"))
    override fun encode(v: AbsSeries) = jsonObjectOf {
        put("id", JsonPrimitive(v.id)); put("name", JsonPrimitive(v.name)); putIfPresent("sequence", v.sequence)
    }
}

/** iOS: `ABSBookMediaMetadata`. */
@Serializable(with = AbsBookMediaMetadataSerializer::class)
data class AbsBookMediaMetadata(
    val title: String,
    val titleIgnorePrefix: String? = null,
    val subtitle: String? = null,
    val authors: List<AbsAuthor>? = null,
    val narrators: List<String>? = null,
    val series: List<AbsSeries>? = null,
    val publishedYear: String? = null,
    val publishedDate: String? = null,
    val authorName: String? = null,
    val narratorName: String? = null,
    val seriesName: String? = null,
    val publisher: String? = null,
    val description: String? = null,
    val descriptionPlain: String? = null,
    val genres: List<String>? = null,
    val language: String? = null,
    /** Optional: Feed-URL aus den Metadaten der Sendung. */
    val feedUrl: String? = null,
    /** Audible-ASIN — genutzt für Kapitel-Lookup via `/api/search/chapters`. */
    val asin: String? = null,
) {
    /** Serienname aus `seriesName` oder den `series`-Einträgen (inkl. Folgennummer). */
    val resolvedSeriesDisplay: String?
        get() {
            seriesName?.swiftTrim()?.takeIf { it.isNotEmpty() }?.let { return it }
            val arr = series
            if (arr.isNullOrEmpty()) return null
            return arr.joinToString(", ") { s ->
                val q = s.sequence?.swiftTrim()
                if (!q.isNullOrEmpty()) "${s.name} ($q)" else s.name
            }
        }

    /** Vollständige Item-API-Metadaten (Serie, Beschreibung, …) vs. schlanker Offline-Stub. */
    val hasRichMetadata: Boolean
        get() {
            if (authors != null || series != null || narrators != null) return true
            if (description != null || descriptionPlain != null) return true
            if (genres != null || narratorName != null || publisher != null) return true
            if (!publishedYear?.swiftTrim().isNullOrEmpty()) return true
            if (!publishedDate?.swiftTrim().isNullOrEmpty()) return true
            if (!subtitle?.swiftTrim().isNullOrEmpty()) return true
            return false
        }

    /** Sprecher-Namen für Zuordnung Bibliotheksitem → Sprecher (exakter Name wie in `/narrators`). */
    fun narratorNamesForLibraryBrowseCoverMatch(): List<String> {
        val seen = HashSet<String>()
        val out = ArrayList<String>()
        fun push(raw: String) {
            val t = raw.swiftTrim()
            if (t.isEmpty() || t in seen) return
            seen.add(t)
            out.add(t)
        }
        narrators?.forEach { push(it) }
        val single = narratorName?.swiftTrim()
        if (!single.isNullOrEmpty()) single.split(",").filter { it.isNotEmpty() }.forEach { push(it) }
        return out
    }

    companion object {
        /** iOS: `init(copying:title:authorName:)` — Kopie mit geändertem Listentitel / Autorzeile. */
        fun copying(base: AbsBookMediaMetadata, title: String, authorName: String?): AbsBookMediaMetadata {
            val a = authorName?.swiftTrim() ?: ""
            return base.copy(title = title, authorName = if (a.isEmpty()) base.authorName else authorName)
        }

        /** iOS: `init(offlineTitle:authorLine:)` — für Offline-Stubs aus `download.json`. */
        fun offline(offlineTitle: String, authorLine: String): AbsBookMediaMetadata {
            val trimmedAuthor = authorLine.swiftTrim()
            val noAuthor = trimmedAuthor.isEmpty() || trimmedAuthor == "—"
            return AbsBookMediaMetadata(
                title = offlineTitle.ifEmpty { "Audiobook" },
                authorName = if (noAuthor) null else trimmedAuthor,
                authors = if (noAuthor) null else trimmedAuthor.split(",").map { it.swiftTrim() }.filter { it.isNotEmpty() }
                    .mapIndexed { i, n -> AbsAuthor(id = "offline-$i", name = n) },
            )
        }
    }
}

object AbsBookMediaMetadataSerializer : SwiftObjectSerializer<AbsBookMediaMetadata>("ABSBookMediaMetadata") {
    /** ABS speichert teils `feedUrl`, teils `feedURL` (vgl. `Podcast.getAbsMetadataJson`). */
    private fun decodeFeedUrl(c: JObj): String? {
        for (key in listOf("feedUrl", "feedURL", "feed_url")) {
            val raw = c.tryString(key) ?: continue
            val t = raw.swiftTrim()
            if (t.isNotEmpty()) return t
        }
        return null
    }

    override fun decode(c: JObj) = AbsBookMediaMetadata(
        title = c.string("title"),
        titleIgnorePrefix = c.stringOrNull("titleIgnorePrefix"),
        subtitle = c.stringOrNull("subtitle"),
        authors = c.listOrNull("authors", AbsAuthorSerializer),
        narrators = c.listOrNull("narrators", ElementDecoder.string),
        publishedYear = c.stringOrNull("publishedYear"),
        publishedDate = c.stringOrNull("publishedDate"),
        authorName = c.stringOrNull("authorName") ?: c.stringOrNull("author"),
        narratorName = c.stringOrNull("narratorName"),
        seriesName = c.stringOrNull("seriesName"),
        publisher = c.stringOrNull("publisher"),
        description = c.stringOrNull("description"),
        descriptionPlain = c.stringOrNull("descriptionPlain"),
        genres = c.listOrNull("genres", ElementDecoder.string),
        language = c.stringOrNull("language"),
        asin = c.stringOrNull("asin"),
        feedUrl = decodeFeedUrl(c),
        series = c.tryList("series", AbsSeriesSerializer) ?: c.tryObj("series", AbsSeriesSerializer)?.let { listOf(it) },
    )

    /** Handgeschrieben: Alias-Keys (`author`, `feedURL`, `feed_url`) sind reine Decoder-Fallbacks. */
    override fun encode(v: AbsBookMediaMetadata) = jsonObjectOf {
        put("title", JsonPrimitive(v.title))
        putIfPresent("titleIgnorePrefix", v.titleIgnorePrefix)
        putIfPresent("subtitle", v.subtitle)
        putList("authors", v.authors) { AbsAuthorSerializer.encode(it) }
        putStrings("narrators", v.narrators)
        putList("series", v.series) { AbsSeriesSerializer.encode(it) }
        putIfPresent("publishedYear", v.publishedYear)
        putIfPresent("publishedDate", v.publishedDate)
        putIfPresent("authorName", v.authorName)
        putIfPresent("narratorName", v.narratorName)
        putIfPresent("seriesName", v.seriesName)
        putIfPresent("publisher", v.publisher)
        putIfPresent("description", v.description)
        putIfPresent("descriptionPlain", v.descriptionPlain)
        putStrings("genres", v.genres)
        putIfPresent("language", v.language)
        putIfPresent("asin", v.asin)
        putIfPresent("feedUrl", v.feedUrl)
    }
}

// MARK: - Metadata Match (absorb-style)

/** iOS: `ABSMetadataProvider` — Eintrag aus `/api/search/providers`. */
@Serializable(with = AbsMetadataProviderSerializer::class)
data class AbsMetadataProvider(val text: String, val value: String) {
    val id: String get() = value
}

object AbsMetadataProviderSerializer : SwiftObjectSerializer<AbsMetadataProvider>("ABSMetadataProvider") {
    override fun decode(c: JObj) = AbsMetadataProvider(c.string("text"), c.string("value"))
    override fun encode(v: AbsMetadataProvider) = jsonObjectOf {
        put("text", JsonPrimitive(v.text)); put("value", JsonPrimitive(v.value))
    }
}

/** iOS: `ABSMatchSeries` — Serien-Eintrag eines Match-Treffers. */
@Serializable(with = AbsMatchSeriesSerializer::class)
data class AbsMatchSeries(val name: String, val sequence: String?)

object AbsMatchSeriesSerializer : SwiftObjectSerializer<AbsMatchSeries>("ABSMatchSeries") {
    override fun decode(c: JObj) = AbsMatchSeries(c.string("name"), c.stringOrNull("sequence"))
    override fun encode(v: AbsMatchSeries) = jsonObjectOf {
        put("name", JsonPrimitive(v.name)); putIfPresent("sequence", v.sequence)
    }
}

/** iOS: `ABSMetadataMatch` — ein Treffer aus `/api/search/books` (flach oder unter `book`). */
@Serializable(with = AbsMetadataMatchSerializer::class)
data class AbsMetadataMatch(
    val title: String?,
    val subtitle: String? = null,
    val author: String?,
    val narrator: String? = null,
    val descriptionHTML: String? = null,
    val publisher: String? = null,
    val publishedYear: String? = null,
    val asin: String? = null,
    val isbn: String? = null,
    val language: String? = null,
    val genres: List<String>? = null,
    val tags: List<String>? = null,
    val series: List<AbsMatchSeries>? = null,
    val cover: String? = null,
) {
    /** Stabiler Schlüssel: ASIN, ISBN oder Titel+Autor-Fallback. */
    val id: String get() = asin ?: isbn ?: "${title ?: ""}-${author ?: ""}"

    val displayAuthors: String? get() = if (author?.swiftTrim()?.isEmpty() == false) author else null
    val displayNarrator: String? get() = if (narrator?.swiftTrim()?.isEmpty() == false) narrator else null
    /** Cover-URL (iOS: `URL(string:)`). */
    val displayCoverURL: String? get() = cover
    val displayYear: String?
        get() {
            val raw = publishedYear
            if (raw.isNullOrEmpty()) return null
            return raw.take(4)
        }
    val displaySeries: String?
        get() {
            val arr = series
            if (arr.isNullOrEmpty()) return null
            return arr.joinToString(", ") { s ->
                val q = s.sequence?.swiftTrim()
                if (!q.isNullOrEmpty()) "${s.name} ($q)" else s.name
            }
        }
    /** Beschreibung als Plain-Text (HTML grob entfernt), 1–2 Zeilen Preview. */
    val displayDescription: String?
        get() {
            val html = descriptionHTML
            if (html.isNullOrEmpty()) return null
            var s = html.replace(Regex("<[^>]+>"), "")
            s = s.replace("&amp;", "&").replace("&#39;", "'").replace("&quot;", "\"")
                .replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ")
            s = s.swiftTrim()
            return s.ifEmpty { null }
        }
}

object AbsMetadataMatchSerializer : SwiftObjectSerializer<AbsMetadataMatch>("ABSMetadataMatch") {
    override fun decode(c: JObj): AbsMetadataMatch {
        // Der Server schachtelt die Buchdaten teils unter `book`. Entscheide pro Element.
        val b = c.tryNested("book") ?: c
        val cover = b.stringOrNull("cover")?.takeIf { it.isNotEmpty() } ?: b.stringOrNull("image")?.takeIf { it.isNotEmpty() }
        return AbsMetadataMatch(
            title = b.stringOrNull("title"),
            subtitle = b.stringOrNull("subtitle"),
            author = b.stringOrNull("author"),
            narrator = b.stringOrNull("narrator"),
            descriptionHTML = b.stringOrNull("description"),
            publisher = b.stringOrNull("publisher"),
            publishedYear = b.stringOrNull("publishedYear"),
            asin = b.stringOrNull("asin"),
            isbn = b.stringOrNull("isbn"),
            language = b.stringOrNull("language"),
            genres = b.listOrNull("genres", ElementDecoder.string),
            tags = b.listOrNull("tags", ElementDecoder.string),
            cover = cover,
            // `series` kann String, Array von {name, sequence} oder Einzelobjekt sein.
            series = b.tryList("series", AbsMatchSeriesSerializer) ?: b.tryObj("series", AbsMatchSeriesSerializer)?.let { listOf(it) },
        )
    }
}

/** iOS: `ABSMetadataProvidersResponse` — `{ "providers": { "books": [...] } }` oder ohne Hülle. */
@Serializable(with = AbsMetadataProvidersResponseSerializer::class)
data class AbsMetadataProvidersResponse(
    val books: List<AbsMetadataProvider>,
    val podcasts: List<AbsMetadataProvider>?,
    val booksCovers: List<AbsMetadataProvider>?,
)

object AbsMetadataProvidersResponseSerializer : SwiftObjectSerializer<AbsMetadataProvidersResponse>("ABSMetadataProvidersResponse") {
    override fun decode(c: JObj): AbsMetadataProvidersResponse {
        val lists = if (c.contains("providers")) c.nested("providers") else c
        return AbsMetadataProvidersResponse(
            books = lists.list("books", AbsMetadataProviderSerializer),
            podcasts = lists.listOrNull("podcasts", AbsMetadataProviderSerializer),
            booksCovers = lists.listOrNull("booksCovers", AbsMetadataProviderSerializer),
        )
    }
}

/** iOS: `ABSMatchField` — einzeln wählbares Metadaten-Feld für den Match-Apply-Dialog. */
enum class AbsMatchField(val rawValue: String, val label: String) {
    title("title", "Title"),
    subtitle("subtitle", "Subtitle"),
    author("author", "Author"),
    narrator("narrator", "Narrator"),
    description("description", "Description"),
    publisher("publisher", "Publisher"),
    publishedYear("publishedYear", "Published Year"),
    asin("asin", "ASIN"),
    isbn("isbn", "ISBN"),
    language("language", "Language"),
    genres("genres", "Genres"),
    tags("tags", "Tags"),
    series("series", "Series"),
    cover("cover", "Cover");

    val id: String get() = rawValue
}

/**
 * iOS: `ABSItemMediaMetadataPatch` — Body für `PATCH /api/items/:id/media`; nur gesetzte Felder.
 * Authors → `[{ "name": ... }]`, Series → `[{ "name": ..., "sequence": ... }]`.
 */
data class AbsItemMediaMetadataPatch(
    var title: String? = null,
    var subtitle: String? = null,
    var authorNames: List<String>? = null,
    var narratorNames: List<String>? = null,
    var descriptionText: String? = null,
    var publisher: String? = null,
    var publishedYear: String? = null,
    var asin: String? = null,
    var isbn: String? = null,
    var language: String? = null,
    var genres: List<String>? = null,
    var tags: List<String>? = null,
    var series: List<SeriesPayload>? = null,
) {
    data class SeriesPayload(val name: String, val sequence: String?)

    fun toJson(): JsonObject = jsonObjectOf {
        put("metadata", jsonObjectOf {
            putIfPresent("title", title)
            putIfPresent("subtitle", subtitle)
            authorNames?.let { names -> put("authors", JsonArray(names.map { jsonObjectOf { put("name", JsonPrimitive(it)) } })) }
            putStrings("narrators", narratorNames)
            putIfPresent("description", descriptionText)
            putIfPresent("publisher", publisher)
            putIfPresent("publishedYear", publishedYear)
            putIfPresent("asin", asin)
            putIfPresent("isbn", isbn)
            putIfPresent("language", language)
            putStrings("genres", genres)
            putList("series", series) { s -> jsonObjectOf { put("name", JsonPrimitive(s.name)); putIfPresent("sequence", s.sequence) } }
        })
        putStrings("tags", tags)
    }
}

// MARK: - Cover online search (`GET /api/search/covers`)

/**
 * iOS: `ABSCoverSearchResponse` — flaches Array aus URL-Strings, Array aus `{cover|url|image}`-Objekten
 * oder `{results: [...]}`.
 */
data class AbsCoverSearchResponse(val urls: List<String>) {
    companion object {
        private fun entryUrl(e: JsonElement): String? {
            SwiftJson.string(e)?.takeIf { it.isNotEmpty() }?.let { return it }
            val o = e as? JsonObject ?: return null
            for (k in listOf("cover", "url", "image")) {
                SwiftJson.string(o[k])?.takeIf { it.isNotEmpty() }?.let { return it }
            }
            return null
        }

        fun decode(root: JsonElement): AbsCoverSearchResponse {
            (root as? JsonArray)?.let { arr -> return AbsCoverSearchResponse(arr.mapNotNull(::entryUrl).filter { it.isNotEmpty() }) }
            ((root as? JsonObject)?.get("results") as? JsonArray)?.let { arr ->
                return AbsCoverSearchResponse(arr.mapNotNull(::entryUrl).filter { it.isNotEmpty() })
            }
            return AbsCoverSearchResponse(emptyList())
        }
    }
}

/** iOS: `ABSChapter`. */
@Serializable(with = AbsChapterSerializer::class)
data class AbsChapter(val id: Int, val start: Double, val end: Double, val title: String) {
    companion object {
        fun fromManifest(ch: AbsDownloadManifest.Chapter) = AbsChapter(ch.id, ch.start, ch.end, ch.title)
    }
}

object AbsChapterSerializer : SwiftObjectSerializer<AbsChapter>("ABSChapter") {
    override fun decode(c: JObj) = AbsChapter(c.int("id"), c.double("start"), c.double("end"), c.string("title"))
    override fun encode(v: AbsChapter) = jsonObjectOf {
        put("id", JsonPrimitive(v.id)); put("start", JsonPrimitive(v.start))
        put("end", JsonPrimitive(v.end)); put("title", JsonPrimitive(v.title))
    }
}

// MARK: - Audible chapter lookup (Audnexus via `/api/search/chapters`)

/** iOS: `ABSAudibleChapter` — Zeiten in Sekunden normalisiert. */
data class AbsAudibleChapter(val title: String, val start: Double, val length: Double) {
    val id: Double get() = start
}

object AbsAudibleChapterSerializer : SwiftObjectSerializer<AbsAudibleChapter>("ABSAudibleChapter") {
    override fun decode(c: JObj): AbsAudibleChapter {
        val start = c.tryDouble("startOffsetMs")?.let { it / 1000.0 } ?: c.tryDouble("startOffsetSec") ?: 0.0
        val ms = c.tryDouble("lengthMs") ?: 0.0
        return AbsAudibleChapter(title = c.tryString("title") ?: "", start = start, length = ms / 1000.0)
    }
}

/** iOS: `ABSAudibleChaptersResponse` — Antwort von `/api/search/chapters` (oder `{ error }`). */
@Serializable(with = AbsAudibleChaptersResponseSerializer::class)
data class AbsAudibleChaptersResponse(
    val chapters: List<AbsAudibleChapter>,
    val runtimeLengthSec: Double?,
    val brandIntroDurationMs: Double?,
    val brandOutroDurationMs: Double?,
    /** Server-Fehlermeldung (Lookup fehlgeschlagen, ASIN nicht gefunden, …). */
    val error: String?,
) {
    companion object {
        val empty = AbsAudibleChaptersResponse(emptyList(), null, null, null, null)
    }
}

object AbsAudibleChaptersResponseSerializer : SwiftObjectSerializer<AbsAudibleChaptersResponse>("ABSAudibleChaptersResponse") {
    override fun decode(c: JObj) = AbsAudibleChaptersResponse(
        chapters = c.tryList("chapters", AbsAudibleChapterSerializer) ?: emptyList(),
        runtimeLengthSec = c.tryDouble("runtimeLengthSec"),
        brandIntroDurationMs = c.tryDouble("brandIntroDurationMs"),
        brandOutroDurationMs = c.tryDouble("brandOutroDurationMs"),
        error = c.tryString("error"),
    )
}

/** iOS: `ABSItemChaptersPayload` — Body für `POST /api/items/:id/chapters` (Top-Level `chapters`). */
@Serializable
data class AbsItemChaptersPayload(val chapters: List<Chapter>) {
    @Serializable
    data class Chapter(val id: Int, val start: Double, val end: Double, val title: String)
}

/** iOS: `ABSAudioTrack`. */
@Serializable(with = AbsAudioTrackSerializer::class)
data class AbsAudioTrack(
    val index: Int,
    val startOffset: Double,
    val duration: Double,
    val title: String?,
    /** Bibliotheksdatei-Inode (ABS); ermöglicht direkten Download statt Session-Stream. */
    val ino: String? = null,
)

object AbsAudioTrackSerializer : SwiftObjectSerializer<AbsAudioTrack>("ABSAudioTrack") {
    /**
     * Swift: `if let s = try decodeIfPresent(String.self)` — ein **numerisches** `ino` wirft dort
     * bereits einen Typfehler (der Int64-Zweig greift nie); hier identisch nachgebildet.
     */
    private fun inoOf(c: JObj): String? {
        val s = c.stringOrNull("ino")
        if (s != null && s.isNotEmpty()) return s
        return c.longOrNull("ino")?.toString()
    }

    override fun decode(c: JObj): AbsAudioTrack {
        val index = c.int("index")
        val startOffset = c.doubleOrNull("startOffset") ?: 0.0
        val duration = c.double("duration")
        val title = c.stringOrNull("title")
        var ino = inoOf(c)
        if (ino == null) c.tryNested("metadata")?.let { ino = inoOf(it) }
        return AbsAudioTrack(index, startOffset, duration, title, ino)
    }

    /** Handgeschrieben: `metadata` ist nur ein Decoder-Fallback (verschachteltes `ino`). */
    override fun encode(v: AbsAudioTrack) = jsonObjectOf {
        put("index", JsonPrimitive(v.index))
        put("startOffset", JsonPrimitive(v.startOffset))
        put("duration", JsonPrimitive(v.duration))
        putIfPresent("title", v.title)
        putIfPresent("ino", v.ino)
    }
}

/** iOS: `ABSSearchAudioFile` (privat) — `audioFiles`-Fallback für `tracks`. */
private data class AbsSearchAudioFile(val index: Int, val duration: Double?, val filename: String?)

private object AbsSearchAudioFileSerializer : SwiftObjectSerializer<AbsSearchAudioFile>("ABSSearchAudioFile") {
    /** iOS: `ABSSearchAudioFile.FileMeta` — nur `filename`. */
    private val fileMeta = object : SwiftObjectSerializer<String?>("FileMeta") {
        override fun decode(c: JObj) = c.stringOrNull("filename")
    }

    override fun decode(c: JObj) = AbsSearchAudioFile(
        index = c.int("index"),
        duration = c.doubleOrNull("duration"),
        filename = c.objOrNull("metadata", fileMeta),
    )
}

/** iOS: `ABSLibraryFile` — Datei auf Library-Item-Ebene (`libraryFiles`). */
@Serializable(with = AbsLibraryFileSerializer::class)
data class AbsLibraryFile(
    val ino: String,
    val fileType: String?,
    val isSupplementary: Boolean?,
    val metadata: Metadata?,
) {
    /** iOS: `ABSLibraryFile.Metadata`. */
    data class Metadata(val filename: String?, val ext: String?, val format: String?, val size: Long?)

    val isEpub: Boolean
        get() {
            val fmt = metadata?.format.trimmedOrEmpty().lowercase()
            if (fmt == "epub") return true
            val ext = metadata?.ext.trimmedOrEmpty().lowercase()
            if (ext == ".epub" || ext == "epub") return true
            return (metadata?.filename ?: "").lowercase().endsWith(".epub")
        }

    val isPdf: Boolean
        get() {
            val fmt = metadata?.format.trimmedOrEmpty().lowercase()
            if (fmt == "pdf") return true
            val ext = metadata?.ext.trimmedOrEmpty().lowercase()
            if (ext == ".pdf" || ext == "pdf") return true
            return (metadata?.filename ?: "").lowercase().endsWith(".pdf")
        }

    val isEbook: Boolean
        get() {
            if (isEpub || isPdf) return true
            val fmt = metadata?.format.trimmedOrEmpty().lowercase()
            if (fmt in listOf("pdf", "mobi", "azw3", "azw", "cbz", "cbr")) return true
            val ext = metadata?.ext.trimmedOrEmpty().lowercase()
            if (ext in listOf(".pdf", ".mobi", ".azw3", ".azw", ".cbz", ".cbr")) return true
            val name = (metadata?.filename ?: "").lowercase()
            return name.endsWith(".pdf") || name.endsWith(".mobi") || name.endsWith(".azw3") ||
                name.endsWith(".cbz") || name.endsWith(".cbr")
        }
}

/** Gemeinsam für `ABSLibraryFile` / `ABSEbookFile`: `ino` als String oder Int64, sonst `keyNotFound`. */
private fun requiredIno(c: JObj): String {
    val s = c.stringOrNull("ino")
    if (s != null && s.isNotEmpty()) return s
    return c.longOrNull("ino")?.toString() ?: SwiftJson.mismatch("ino", "ino")
}

object AbsLibraryFileSerializer : SwiftObjectSerializer<AbsLibraryFile>("ABSLibraryFile") {
    private val meta = object : SwiftObjectSerializer<AbsLibraryFile.Metadata>("ABSLibraryFile.Metadata") {
        override fun decode(c: JObj) = AbsLibraryFile.Metadata(
            c.stringOrNull("filename"), c.stringOrNull("ext"), c.stringOrNull("format"), c.longOrNull("size"),
        )
    }

    override fun decode(c: JObj) = AbsLibraryFile(
        ino = requiredIno(c),
        fileType = c.stringOrNull("fileType"),
        isSupplementary = c.boolOrNull("isSupplementary"),
        metadata = c.objOrNull("metadata", meta),
    )

    override fun encode(v: AbsLibraryFile) = jsonObjectOf {
        put("ino", JsonPrimitive(v.ino))
        putIfPresent("fileType", v.fileType)
        putIfPresent("isSupplementary", v.isSupplementary)
        v.metadata?.let { m ->
            put("metadata", jsonObjectOf {
                putIfPresent("filename", m.filename); putIfPresent("ext", m.ext)
                putIfPresent("format", m.format); putIfPresent("size", m.size)
            })
        }
    }
}

/** iOS: `ABSEbookFile` — supplementärer E-Book-Eintrag aus `media.ebookFile`. */
@Serializable(with = AbsEbookFileSerializer::class)
data class AbsEbookFile(val ino: String, val ebookFormat: String?, val metadata: Metadata?) {
    /** iOS: `ABSEbookFile.Metadata`. */
    data class Metadata(val filename: String?, val ext: String?, val format: String?)

    val isEpub: Boolean
        get() {
            val fmt = (ebookFormat ?: metadata?.format ?: "").swiftTrim().lowercase()
            if (fmt == "epub") return true
            val ext = metadata?.ext.trimmedOrEmpty().lowercase()
            if (ext == ".epub" || ext == "epub") return true
            return (metadata?.filename ?: "").lowercase().endsWith(".epub")
        }
}

object AbsEbookFileSerializer : SwiftObjectSerializer<AbsEbookFile>("ABSEbookFile") {
    private val meta = object : SwiftObjectSerializer<AbsEbookFile.Metadata>("ABSEbookFile.Metadata") {
        override fun decode(c: JObj) = AbsEbookFile.Metadata(c.stringOrNull("filename"), c.stringOrNull("ext"), c.stringOrNull("format"))
    }

    override fun decode(c: JObj) = AbsEbookFile(
        ino = requiredIno(c),
        ebookFormat = c.stringOrNull("ebookFormat"),
        metadata = c.objOrNull("metadata", meta),
    )

    override fun encode(v: AbsEbookFile) = jsonObjectOf {
        put("ino", JsonPrimitive(v.ino))
        putIfPresent("ebookFormat", v.ebookFormat)
        v.metadata?.let { m ->
            put("metadata", jsonObjectOf { putIfPresent("filename", m.filename); putIfPresent("ext", m.ext); putIfPresent("format", m.format) })
        }
    }
}

/** iOS: `ABSBookMedia`. */
@Serializable(with = AbsBookMediaSerializer::class)
data class AbsBookMedia(
    val metadata: AbsBookMediaMetadata,
    val duration: Double?,
    val size: Long? = null,
    val numTracks: Int?,
    val chapters: List<AbsChapter>? = null,
    val tracks: List<AbsAudioTrack>?,
    /** Nur Podcast-`media.episodes` (expandiertes Library-Item). */
    val podcastEpisodes: List<AbsRecentPodcastEpisodeDTO>? = null,
    val autoDownloadEpisodes: Boolean? = null,
    val autoDownloadSchedule: String? = null,
    val maxEpisodesToKeep: Int? = null,
    val maxNewEpisodesToDownload: Int? = null,
    /** Supplementäres E-Book (expandiert); `null` wenn nur Hörbuch. */
    val ebookFile: AbsEbookFile? = null,
    /** Katalog/minified: Format-Hinweis ohne vollständiges `ebookFile`. */
    val ebookFormat: String? = null,
    /** ABS: Tags am Medien-Objekt (`media.tags`), nicht in `metadata`. */
    val tags: List<String>? = null,
)

object AbsBookMediaSerializer : SwiftObjectSerializer<AbsBookMedia>("ABSBookMedia") {
    override fun decode(c: JObj): AbsBookMedia {
        val metadata = c.obj("metadata", AbsBookMediaMetadataSerializer)
        val tags = c.listOrNull("tags", ElementDecoder.string)
        val duration = c.doubleOrNull("duration")
        val size = c.longOrNull("size")
        val numTracks = c.intOrNull("numTracks")
        val chapters = c.listOrNull("chapters", AbsChapterSerializer)
        val podcastEpisodes = c.listOrNull("episodes", AbsRecentPodcastEpisodeDTOSerializer)
        val autoDownloadEpisodes = c.boolOrNull("autoDownloadEpisodes")
        val autoDownloadSchedule = c.stringOrNull("autoDownloadSchedule")
        val maxEpisodesToKeep = c.intOrNull("maxEpisodesToKeep")
        val maxNewEpisodesToDownload = c.intOrNull("maxNewEpisodesToDownload")
        val ebookFile = c.objOrNull("ebookFile", AbsEbookFileSerializer)
        val ebookFormat = c.stringOrNull("ebookFormat") ?: c.stringOrNull("ebookFileFormat")
        val ts = c.listOrNull("tracks", AbsAudioTrackSerializer)
        val tracks: List<AbsAudioTrack>? = if (!ts.isNullOrEmpty()) ts else {
            val files = c.listOrNull("audioFiles", AbsSearchAudioFileSerializer)
            if (!files.isNullOrEmpty()) {
                var off = 0.0
                files.sortedBy { it.index }.map { f ->
                    val d = f.duration ?: 0.0
                    val t = AbsAudioTrack(index = f.index, startOffset = off, duration = d, title = f.filename, ino = null)
                    off += d
                    t
                }
            } else null
        }
        return AbsBookMedia(
            metadata = metadata, duration = duration, size = size, numTracks = numTracks, chapters = chapters,
            tracks = tracks, podcastEpisodes = podcastEpisodes, autoDownloadEpisodes = autoDownloadEpisodes,
            autoDownloadSchedule = autoDownloadSchedule, maxEpisodesToKeep = maxEpisodesToKeep,
            maxNewEpisodesToDownload = maxNewEpisodesToDownload, ebookFile = ebookFile, ebookFormat = ebookFormat, tags = tags,
        )
    }

    /** Handgeschrieben: `audioFiles`/`ebookFileFormat` sind nur Decoder-Fallbacks ohne eigene Property. */
    override fun encode(v: AbsBookMedia) = jsonObjectOf {
        put("metadata", AbsBookMediaMetadataSerializer.encode(v.metadata))
        putIfPresent("duration", v.duration)
        putIfPresent("size", v.size)
        putIfPresent("numTracks", v.numTracks)
        putList("chapters", v.chapters) { AbsChapterSerializer.encode(it) }
        putList("tracks", v.tracks) { AbsAudioTrackSerializer.encode(it) }
        putList("episodes", v.podcastEpisodes) { AbsRecentPodcastEpisodeDTOSerializer.encode(it) }
        putIfPresent("autoDownloadEpisodes", v.autoDownloadEpisodes)
        putIfPresent("autoDownloadSchedule", v.autoDownloadSchedule)
        putIfPresent("maxEpisodesToKeep", v.maxEpisodesToKeep)
        putIfPresent("maxNewEpisodesToDownload", v.maxNewEpisodesToDownload)
        putIfPresent("ebookFile", v.ebookFile?.let { AbsEbookFileSerializer.encode(it) })
        putIfPresent("ebookFormat", v.ebookFormat)
        putStrings("tags", v.tags)
    }
}

/** iOS: `ABSEbookFormat` (EbookLocalStore.swift). */
enum class AbsEbookFormat(val rawValue: String) {
    epub("epub"), pdf("pdf");

    val fileExtension: String get() = rawValue

    companion object {
        fun resolve(format: String?, ext: String?, filename: String?): AbsEbookFormat? {
            val f = format.trimmedOrEmpty().lowercase()
            if (f == "epub" || f.contains("epub")) return epub
            if (f == "application/epub+zip" || f == "application/x-epub+zip") return epub
            if (f == "pdf" || f.contains("pdf")) return pdf
            if (f == "application/pdf") return pdf
            val e = ext.trimmedOrEmpty().lowercase()
            if (e == ".epub" || e == "epub") return epub
            if (e == ".pdf" || e == "pdf") return pdf
            val name = (filename ?: "").lowercase()
            if (name.endsWith(".epub")) return epub
            if (name.endsWith(".pdf")) return pdf
            return null
        }
    }
}

/**
 * Platzhalter für die Abfragen, die `ABSBook` auf iOS an `EbookLocalStore` stellt (lokaler
 * E-Book-Cache). Der Store selbst ist noch nicht portiert; er hängt sich hier ein, sobald es ihn gibt.
 */
object EbookLocalStoreHooks {
    /** iOS: `EbookLocalStore.knownFormat(libraryItemId:)`. */
    @Volatile var knownFormat: (libraryItemId: String) -> AbsEbookFormat? = { null }
    /** iOS: `EbookLocalStore.cachedEbookIfPresent(account:libraryItemId:)?.format`. */
    @Volatile var cachedEbookFormat: (account: File, libraryItemId: String) -> AbsEbookFormat? = { _, _ -> null }
    /** iOS: `EbookLocalStore.cachedEbookFileByteCount(account:libraryItemId:)`. */
    @Volatile var cachedEbookFileByteCount: (account: File?, libraryItemId: String) -> Long? = { _, _ -> null }
}

/** iOS: `ABSBook` (Library-Item: Hörbuch, eBook oder Podcast-Sendung). */
@Serializable(with = AbsBookSerializer::class)
data class AbsBook(
    val id: String,
    val libraryId: String?,
    val media: AbsBookMedia,
    /** Millisekunden seit 1970 (iOS: `Date`). */
    val addedAt: Long?,
    val updatedAt: Long?,
    /** Referenz auf die Medien-Zeile (Buch/Podcast) — für Playback-Sessions nötig. */
    val mediaId: String? = null,
    /** Nur bei expandiertem Item; supplementäre EPUBs können hier statt in `media.ebookFile` stehen. */
    val libraryFiles: List<AbsLibraryFile>? = null,
) {
    val displayTitle: String get() = media.metadata.title

    val displayAuthors: String
        get() {
            val m = media.metadata
            if (!m.authorName.isNullOrEmpty()) return m.authorName
            if (!m.authors.isNullOrEmpty()) return m.authors.joinToString(", ") { it.name }
            return "—"
        }

    /** Alle Autoren für kompakte UI (Listenkarten, Continue-Hero, Miniplayer). */
    val displayAuthorsCardLine: String get() = displayAuthors

    val totalDuration: Double get() = media.duration ?: 0.0

    /** Enough metadata to play or show in lists. */
    val isPlayableAudiobook: Boolean get() = (media.numTracks ?: 0) > 0 || (media.duration ?: 0.0) > 0

    /** Einzelnes M4B (kein Merge nötig) — anhand Track-Anzahl und Dateiendung. */
    val isSingleM4BAudiobook: Boolean
        get() {
            val trackCount = media.numTracks ?: media.tracks?.size ?: 0
            if (trackCount != 1) return false
            media.tracks?.forEach { t ->
                if ((t.title ?: "").swiftTrim().lowercase().endsWith(".m4b")) return true
            }
            libraryFiles?.let { files ->
                val audioNames = files.mapNotNull { file ->
                    val ft = (file.fileType ?: "").lowercase()
                    val ext = (file.metadata?.ext ?: "").lowercase()
                    val name = (file.metadata?.filename ?: "").lowercase()
                    if (ft == "audio" || ext.contains("m4b") || name.endsWith(".m4b") || ext == ".m4b" || ext == "m4b") {
                        name.ifEmpty { ext }
                    } else null
                }
                if (audioNames.size == 1) {
                    val n = audioNames[0]
                    if (n.endsWith(".m4b") || n.contains(".m4b") || n == "m4b" || n == ".m4b") return true
                }
            }
            return false
        }

    /** Kandidat für Server-Tool „Encode M4B“. */
    val isM4BConversionCandidate: Boolean
        get() {
            if (isPureEbookLibraryItem) return false
            if (!isPlayableAudiobook) return false
            return !isSingleM4BAudiobook
        }

    /**
     * Listen-Katalog (`GET …/libraries/:id/items`, oft `minified=1`): Spuren/Dauer fehlen häufig —
     * ohne Fallback verschwinden neu hinzugefügte Titel aus der Liste.
     */
    val isUsableLibraryCatalogRow: Boolean
        get() {
            if (isPlayableAudiobook) return true
            if (isPureEbookLibraryItem) return displayTitle.swiftTrim().isNotEmpty()
            if (media.numTracks == null && (media.duration ?: 0.0) <= 0) return displayTitle.swiftTrim().isNotEmpty()
            return false
        }

    /** eBooks-Browse-Listen: reine eBook-Items haben `numTracks: 0` und keine Dauer. */
    val isUsableEbookListRow: Boolean get() = hasAttachedEbook || isUsableLibraryCatalogRow

    /** Autor-Detail: Hörbücher plus reine eBook-Titel (ohne Hörspuren). */
    val isUsableAuthorDetailRow: Boolean
        get() {
            if (isUsableLibraryCatalogRow || isUsableEbookListRow) return true
            if (isPlayableAudiobook) return false
            if (libraryFiles?.any { it.isEbook } == true) return true
            val tracks = media.numTracks ?: 0
            val dur = media.duration ?: 0.0
            if (tracks == 0 && dur <= 0) return displayTitle.swiftTrim().isNotEmpty()
            return false
        }

    /**
     * Buch gehört zu einer Bibliotheks-Serie (für Continue-series eBooks). Serien-Einträge ohne
     * echten Namen (Server-Stub `{ id, name: "" }`) zählen nicht als Serie.
     */
    val belongsToLibrarySeries: Boolean
        get() {
            if (media.metadata.series?.any { it.name.swiftTrim().isNotEmpty() } == true) return true
            return media.metadata.seriesName.trimmedOrEmpty().isNotEmpty()
        }

    /** Reines eBook ohne Hörbuch-Spuren — in Autor-Detail als eBook-Karte darstellen. */
    val isPureEbookLibraryItem: Boolean
        get() {
            if (isPlayableAudiobook) return false
            if (hasAttachedEbook || hasReadableAttachedEbook) return true
            if (libraryFiles?.any { it.isEbook } == true) return true
            if (!media.ebookFormat?.swiftTrim().isNullOrEmpty()) return true
            val tracks = media.numTracks ?: 0
            val dur = media.duration ?: 0.0
            return tracks == 0 && dur <= 0 && displayTitle.swiftTrim().isNotEmpty()
        }

    /** Autorzeile aus reicherem Stub übernehmen (z. B. Continue-reading ohne Metadaten). */
    fun withAuthorLineIfMissing(authorLine: String): AbsBook {
        val current = displayAuthorsCardLine.swiftTrim()
        if (!(current.isEmpty() || current == "—")) return this
        val author = authorLine.swiftTrim()
        if (author.isEmpty() || author == "—") return this
        val newMeta = if (media.metadata.hasRichMetadata) {
            AbsBookMediaMetadata.copying(media.metadata, title = displayTitle, authorName = author)
        } else {
            AbsBookMediaMetadata.offline(offlineTitle = displayTitle, authorLine = author)
        }
        val newMedia = AbsBookMedia(
            metadata = newMeta, duration = media.duration, size = media.size, numTracks = media.numTracks,
            chapters = media.chapters, tracks = media.tracks, ebookFile = media.ebookFile,
            ebookFormat = media.ebookFormat, tags = media.tags,
        )
        return AbsBook(id, libraryId, newMedia, addedAt, updatedAt, mediaId, libraryFiles)
    }

    // --- extension ABSBook (eBook-Erkennung) ---

    private val isAudiobookLibraryItem: Boolean get() = (media.numTracks ?: 0) > 0 || (media.duration ?: 0.0) > 0

    private val epubLibraryFiles: List<AbsLibraryFile> get() = libraryFiles?.filter { it.isEpub } ?: emptyList()

    /** Hörbuch mit angehängter E-Book-Datei (EPUB, PDF, …); für Listenfilter und Badge. */
    val hasAttachedEbook: Boolean
        get() {
            if (media.ebookFile != null) return true
            if (!media.ebookFormat?.swiftTrim().isNullOrEmpty()) return true
            if (libraryFiles?.any { it.isEbook } == true) return true
            return false
        }

    /** Primäre oder supplementäre E-Book-Datei zum Lesen (EPUB bevorzugt, sonst PDF). */
    val readableAttachedEbook: Pair<String, AbsEbookFormat>?
        get() {
            media.ebookFile?.let { ef ->
                val fmt = AbsEbookFormat.resolve(ef.ebookFormat, ef.metadata?.ext, ef.metadata?.filename)
                if (fmt != null) {
                    val ino = ef.ino.swiftTrim()
                    if (ino.isNotEmpty()) return ino to fmt
                }
            }
            libraryFiles?.let { files ->
                files.firstOrNull { it.isEpub }?.let { return it.ino to AbsEbookFormat.epub }
                files.firstOrNull { it.isPdf }?.let { return it.ino to AbsEbookFormat.pdf }
            }
            return null
        }

    val hasReadableAttachedEbook: Boolean get() = readableAttachedEbook != null || hasAttachedEbook

    /** Alle erkennbaren E-Book-Formate (primär, supplementär, Katalog-Hinweis). */
    val attachedEbookFormats: Set<AbsEbookFormat>
        get() {
            val out = LinkedHashSet<AbsEbookFormat>()
            media.ebookFile?.let { ef ->
                AbsEbookFormat.resolve(ef.ebookFormat, ef.metadata?.ext, ef.metadata?.filename)?.let(out::add)
            }
            AbsEbookFormat.resolve(media.ebookFormat, null, null)?.let(out::add)
            libraryFiles?.let { files ->
                if (files.any { it.isEpub }) out.add(AbsEbookFormat.epub)
                if (files.any { it.isPdf }) out.add(AbsEbookFormat.pdf)
            }
            EbookLocalStoreHooks.knownFormat(id)?.let(out::add)
            return out
        }

    /** Hat eine lesbare oder angehängte Datei des angegebenen Formats (EPUB/PDF). */
    fun hasAttachedEbookFormat(format: AbsEbookFormat, account: File? = null): Boolean {
        if (format in attachedEbookFormats) return true
        if (account != null && EbookLocalStoreHooks.cachedEbookFormat(account, id) == format) return true
        // Hörbuch in der E-Book-Liste ohne Format-Metadaten (minified): meist supplementäres EPUB.
        if (format == AbsEbookFormat.epub && isAudiobookLibraryItem && hasAttachedEbook && attachedEbookFormats.isEmpty()) return true
        return false
    }

    /** Hörbuch mit supplementärer EPUB-Version (Katalog oder expandiertes Item). */
    val hasSupplementalEpub: Boolean
        get() {
            if (epubIno != null) return true
            val fmt = media.ebookFormat.trimmedOrEmpty().lowercase()
            return fmt == "epub" && isAudiobookLibraryItem
        }

    /** Reines eBook laut Server-Metadaten — kein minified „nur Titel ohne Spuren“-Fallback. */
    val isCatalogPureEbookLibraryItem: Boolean
        get() {
            if (isPlayableAudiobook) return false
            if (media.ebookFile != null) return true
            if (libraryFiles?.any { it.isEbook } == true) return true
            if (!media.ebookFormat?.swiftTrim().isNullOrEmpty()) return true
            return false
        }

    /** Hörbuch mit lesbarem supplementärem eBook (EPUB/PDF) — Badge unten rechts auf dem Cover. */
    val isCatalogSupplementaryEbook: Boolean
        get() {
            if (!isPlayableAudiobook) return false
            if (hasSupplementalEpub) return true
            if (readableAttachedEbook != null) return true
            // Minified-Katalog: oft `ebookFormat`/`ebookFile` ohne vollständiges `readableAttachedEbook`.
            if (media.ebookFile != null) return true
            if (libraryFiles?.any { it.isEbook } == true) return true
            if (!media.ebookFormat?.swiftTrim().isNullOrEmpty()) return true
            return false
        }

    /** Bücher-Katalogfilter „eBook“: reines eBook oder Hörbuch mit supplementärem eBook. */
    val matchesBooksEbookCatalogFilter: Boolean get() = isCatalogPureEbookLibraryItem || isCatalogSupplementaryEbook

    /** eBook-Symbol unten rechts auf Hörbuch-Cover (Listen, Detail, Continue). */
    val showsAttachedEbookCoverBadge: Boolean get() = isCatalogSupplementaryEbook

    /** Listen-Merge: eBook-/Spur-Felder zählen stärker als bloße Titel-Stubs. */
    val listMetadataRichnessScore: Int
        get() {
            var score = 0
            if (media.ebookFile != null) score += 8
            if (!media.ebookFormat?.swiftTrim().isNullOrEmpty()) score += 6
            if (libraryFiles?.any { it.isEbook } == true) score += 8
            if (libraryFiles?.isEmpty() == false) score += 2
            if (media.tracks?.isEmpty() == false) score += 3
            if ((media.numTracks ?: 0) > 0) score += 1
            if ((media.duration ?: 0.0) > 0) score += 1
            if (media.metadata.hasRichMetadata) score += 1
            return score
        }

    /** Zwei Stubs derselben ID zusammenführen — reichere eBook-/Spur-Metadaten behalten. */
    fun preferringRicherListMetadata(other: AbsBook): AbsBook =
        if (listMetadataRichnessScore >= other.listMetadataRichnessScore) mergingListMetadata(other) else other.mergingListMetadata(this)

    private fun mergedLibraryFilesForList(other: AbsBook): List<AbsLibraryFile>? {
        // Swift: Dictionary nach `ino` (letzter gewinnt); Reihenfolge der Werte ist dort undefiniert.
        val byIno = LinkedHashMap<String, AbsLibraryFile>()
        for (file in (libraryFiles ?: emptyList()) + (other.libraryFiles ?: emptyList())) byIno[file.ino] = file
        return if (byIno.isEmpty()) null else byIno.values.toList()
    }

    val epubIno: String?
        get() {
            media.ebookFile?.let { ef ->
                if (ef.isEpub) {
                    val ino = ef.ino.swiftTrim()
                    if (ino.isNotEmpty()) return ino
                }
            }
            val epubs = epubLibraryFiles
            if (epubs.isEmpty()) return null
            if (isAudiobookLibraryItem) {
                val primary = media.ebookFile
                if (primary != null && !primary.isEpub) return epubs.firstOrNull()?.ino
                epubs.firstOrNull { it.isSupplementary == true }?.let { return it.ino }
                if (media.ebookFile == null) return epubs.firstOrNull()?.ino
            }
            return null
        }

    /** Größe der angehängten E-Book-Datei(en) aus `libraryFiles` (supplementär bevorzugt). */
    val attachedEbookLibraryFileByteCount: Long?
        get() {
            val files = libraryFiles ?: return null
            val ebookFiles = files.filter { it.isEbook }
            if (ebookFiles.isEmpty()) return null
            val supplementary = ebookFiles.filter { it.isSupplementary == true }
            val targets = supplementary.ifEmpty { ebookFiles }
            val total = targets.mapNotNull { it.metadata?.size }.sum()
            return if (total > 0) total else null
        }

    /** E-Book-Dateigröße: lokal gecacht oder aus expandiertem `libraryFiles` — nie Hörbuch-`media.size`. */
    fun resolvedAttachedEbookFileByteCount(account: File?): Long? =
        EbookLocalStoreHooks.cachedEbookFileByteCount(account, id) ?: attachedEbookLibraryFileByteCount

    /** Podcast-Sendungen in `GET /libraries/…/items`: meist **ohne** `numTracks`/Dauer. */
    val isListablePodcastLibraryItem: Boolean
        get() {
            if (id.isEmpty()) return false
            if ((media.numTracks ?: 0) > 0 || (media.duration ?: 0.0) > 0) return true
            if (media.metadata.title.swiftTrim().isNotEmpty()) return true
            val a = displayAuthors.swiftTrim()
            return a.isNotEmpty() && a != "—"
        }

    /** Lokale Tracks/Kapitel aus `download.json`, Metadaten vom Server-Buch wenn vorhanden. */
    fun mergingLocalDownloadPlayback(local: AbsBook): AbsBook {
        val lm = local.media
        val meta = if (media.metadata.hasRichMetadata) media.metadata else lm.metadata
        val mergedMedia = AbsBookMedia(
            metadata = meta,
            duration = lm.duration ?: media.duration,
            size = media.size ?: lm.size,
            numTracks = lm.numTracks ?: media.numTracks,
            chapters = lm.chapters ?: media.chapters,
            tracks = lm.tracks ?: media.tracks,
            podcastEpisodes = media.podcastEpisodes ?: lm.podcastEpisodes,
            ebookFile = media.ebookFile ?: lm.ebookFile,
            ebookFormat = media.ebookFormat ?: lm.ebookFormat,
            tags = media.tags ?: lm.tags,
        )
        return AbsBook(id, libraryId ?: local.libraryId, mergedMedia, addedAt, updatedAt, mediaId, libraryFiles ?: local.libraryFiles)
    }

    /** Metadaten aus Katalog-/Detail-Stub übernehmen (eBook-Felder, `libraryFiles`, Spuren). */
    fun mergingListMetadata(other: AbsBook): AbsBook {
        if (id != other.id) return this
        val mergedMedia = AbsBookMedia(
            metadata = if (media.metadata.hasRichMetadata) media.metadata else other.media.metadata,
            duration = media.duration ?: other.media.duration,
            size = media.size ?: other.media.size,
            numTracks = media.numTracks ?: other.media.numTracks,
            chapters = media.chapters ?: other.media.chapters,
            tracks = media.tracks ?: other.media.tracks,
            podcastEpisodes = media.podcastEpisodes ?: other.media.podcastEpisodes,
            ebookFile = media.ebookFile ?: other.media.ebookFile,
            ebookFormat = media.ebookFormat ?: other.media.ebookFormat,
            tags = media.tags ?: other.media.tags,
        )
        return AbsBook(
            id, libraryId ?: other.libraryId, mergedMedia, addedAt ?: other.addedAt, updatedAt ?: other.updatedAt,
            mediaId ?: other.mediaId, mergedLibraryFilesForList(other),
        )
    }

    /**
     * Nur Metadaten (Titel, Autor, Beschreibung …) und `updatedAt` aus [other] übernehmen — Spuren,
     * Kapitel und Dauer der laufenden Wiedergabe bleiben (Metadaten-Edit während des Hörens).
     */
    fun replacingMetadata(other: AbsBook): AbsBook {
        if (id != other.id) return this
        val mergedMedia = AbsBookMedia(
            metadata = other.media.metadata,
            duration = media.duration,
            size = media.size,
            numTracks = media.numTracks,
            chapters = media.chapters,
            tracks = media.tracks,
            podcastEpisodes = media.podcastEpisodes,
            ebookFile = media.ebookFile ?: other.media.ebookFile,
            ebookFormat = media.ebookFormat ?: other.media.ebookFormat,
            tags = other.media.tags ?: media.tags,
        )
        return AbsBook(id, libraryId, mergedMedia, addedAt, other.updatedAt ?: updatedAt, mediaId, libraryFiles)
    }

    /** Kapitel aus anderer Quelle übernehmen (z. B. Katalog, wenn altes Manifest ohne `chapters`). */
    fun withChapters(chapters: List<AbsChapter>): AbsBook {
        if (chapters.isEmpty()) return this
        // Swift: `tags` und `libraryFiles` fallen hier (unbeabsichtigt?) weg — identisch übernommen.
        val m = AbsBookMedia(
            metadata = media.metadata, duration = media.duration, size = media.size, numTracks = media.numTracks,
            chapters = chapters, tracks = media.tracks, podcastEpisodes = media.podcastEpisodes,
            ebookFile = media.ebookFile, ebookFormat = media.ebookFormat,
        )
        return AbsBook(id, libraryId, m, addedAt, updatedAt, mediaId)
    }

    companion object {
        /** Autorenzeile für Serien-Karten — alle `displayAuthorsCardLine` der eingebetteten Bücher (dedupliziert). */
        fun cardAuthorsLine(books: List<AbsBook>?): String? {
            if (books.isNullOrEmpty()) return null
            val distinct = ArrayList<String>()
            for (book in books) {
                val line = book.displayAuthorsCardLine.swiftTrim()
                if (line.isEmpty() || line == "—") continue
                if (line !in distinct) distinct.add(line)
            }
            return if (distinct.isEmpty()) null else distinct.joinToString(", ")
        }

        /** Hörbuch nur aus lokalem [AbsDownloadManifest] (Offline-Liste / Wiedergabe ohne Item-API). */
        fun fromDownloadManifest(m: AbsDownloadManifest): AbsBook {
            val title = m.displayTitle.trimmedOrEmpty().ifEmpty { "Audiobook" }
            val authorLine = m.displayAuthor.trimmedOrEmpty().ifEmpty { "—" }
            val trackModels = m.tracks.map { row ->
                AbsAudioTrack(index = row.index, startOffset = row.startOffset, duration = row.duration, title = row.title, ino = null)
            }
            val n = trackModels.size
            val sumDur = trackModels.sumOf { it.duration }
            val dur = (m.totalDuration ?: (if (sumDur > 0) sumDur else null))?.takeIf { it > 0 }
            val meta = AbsBookMediaMetadata.offline(offlineTitle = title, authorLine = authorLine)
            val chapterModels = m.chapters?.map { AbsChapter.fromManifest(it) }
            val media = AbsBookMedia(
                metadata = meta,
                duration = dur,
                numTracks = if (n > 0) n else null,
                chapters = chapterModels?.takeIf { it.isNotEmpty() },
                tracks = if (n > 0) trackModels else null,
                ebookFile = null,
                ebookFormat = null,
            )
            return AbsBook(id = m.libraryItemId, libraryId = m.libraryId, media = media, addedAt = null, updatedAt = null, mediaId = null)
        }
    }
}

object AbsBookSerializer : SwiftObjectSerializer<AbsBook>("ABSBook") {
    override fun decode(c: JObj) = AbsBook(
        id = c.string("id"),
        libraryId = c.stringOrNull("libraryId"),
        mediaId = c.stringOrNull("mediaId"),
        media = c.obj("media", AbsBookMediaSerializer),
        libraryFiles = c.listOrNull("libraryFiles", AbsLibraryFileSerializer),
        // `ABSJSON`-Datumsstrategie: Int64-Millisekunden.
        addedAt = c.longOrNull("addedAt"),
        updatedAt = c.longOrNull("updatedAt"),
    )

    // Swift: synthetisiertes `encode(to:)`; Datum als Int64-Millisekunden (`ABSJSON.encoder()`).
    override fun encode(v: AbsBook) = jsonObjectOf {
        put("id", JsonPrimitive(v.id))
        putIfPresent("libraryId", v.libraryId)
        putIfPresent("mediaId", v.mediaId)
        put("media", AbsBookMediaSerializer.encode(v.media))
        putList("libraryFiles", v.libraryFiles) { AbsLibraryFileSerializer.encode(it) }
        putIfPresent("addedAt", v.addedAt)
        putIfPresent("updatedAt", v.updatedAt)
    }
}
