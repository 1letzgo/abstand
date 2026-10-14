package de.letzgo.abstand.data

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URI
import java.util.Locale

// iOS: ABSPodcastCharts.swift + reine Hilfen aus AppModelPodcastDirectory.swift

/** iOS: `ABSPodcastCharts` — iTunes Podcast-Charts (öffentliche RSS/Lookup-APIs, vgl. Absorb). */
object AbsPodcastCharts {
    const val defaultLimit = 50

    /** `genreId == null` → Top-Charts gesamt („All“). */
    data class ChartCategory(val genreId: Int?, val title: String) {
        val id: String get() = genreId?.toString() ?: "all"
    }

    /** Apple-Podcast-Kategorien (iTunes-Genre-IDs für `…/rss/toppodcasts/…/genre=…/json`). */
    val chartCategories: List<ChartCategory> = listOf(
        ChartCategory(null, "All"),
        ChartCategory(1301, "Arts"),
        ChartCategory(1321, "Business"),
        ChartCategory(1303, "Comedy"),
        ChartCategory(1304, "Education"),
        ChartCategory(1483, "Fiction"),
        ChartCategory(1323, "Government"),
        ChartCategory(1325, "Health"),
        ChartCategory(1307, "History"),
        ChartCategory(1305, "Kids"),
        ChartCategory(1502, "Leisure"),
        ChartCategory(1310, "Music"),
        ChartCategory(1311, "News"),
        ChartCategory(1314, "Religion"),
        ChartCategory(1315, "Science"),
        ChartCategory(1324, "Society"),
        ChartCategory(1316, "Sports"),
        ChartCategory(1318, "Technology"),
        ChartCategory(1488, "True Crime"),
        ChartCategory(1309, "TV & Film"),
    )

    /** Storefront für `itunes.apple.com/{country}/rss/...` — bevorzugt ABS-Server-Sprache. */
    fun countryCode(serverLanguage: String?, locale: Locale = Locale.getDefault()): String {
        val raw = serverLanguage?.swiftTrim()?.lowercase() ?: ""
        if (raw.isNotEmpty()) {
            val parts = raw.split("-").filter { it.isNotEmpty() }
            if (parts.size >= 2 && parts[0] == "en") {
                val region = parts[1]
                if (region == "gb" || region == "uk") return "gb"
                if (region.length == 2) return region
                return "us"
            }
            if (raw.length == 2) return raw
            when (raw) {
                "deutsch", "german" -> return "de"
                "english" -> return "us"
                "french", "français" -> return "fr"
                "spanish", "español" -> return "es"
                "italian" -> return "it"
                "dutch" -> return "nl"
                "japanese" -> return "jp"
            }
        }
        return locale.country.lowercase().ifEmpty { "us" }
    }

    /** Unterstützte iTunes-Storefronts (Ländermenü in Add-Podcast-View). */
    val directoryStorefrontCountryCodes = listOf(
        "de", "at", "ch", "us", "gb", "fr", "es", "it", "nl", "be", "ie", "ca", "au", "nz",
        "jp", "se", "no", "dk", "fi", "pl", "pt", "br", "mx",
    )

    fun directoryStorefrontDisplayName(code: String, locale: Locale = Locale.getDefault()): String {
        val c = code.swiftTrim().uppercase()
        if (c.length != 2) return code.uppercase()
        return runCatching { Locale.Builder().setRegion(c).build().getDisplayCountry(locale) }.getOrNull()?.ifEmpty { null } ?: c
    }

    /** Vorauswahl zuerst (Auto-Logik), Rest alphabetisch nach Anzeigenamen. */
    fun directoryStorefrontMenuCodes(defaultCode: String, locale: Locale = Locale.getDefault()): List<String> {
        val known = directoryStorefrontCountryCodes.toSet()
        val raw = defaultCode.swiftTrim().lowercase()
        val primary = if (raw in known) raw else "us"
        val rest = (known - primary).sortedWith { a, b ->
            localizedCaseInsensitiveCompare(directoryStorefrontDisplayName(a, locale), directoryStorefrontDisplayName(b, locale))
        }
        return listOf(primary) + rest
    }

    /** Größerer Pool für Kategorien, bei denen Apple `genre=` ignoriert (z. B. Sports). */
    private const val categoryFallbackPoolLimit = 200

    fun chartFeedURL(country: String, genreId: Int?, limit: Int = defaultLimit): String? {
        val c = country.swiftTrim().lowercase()
        if (c.isEmpty()) return null
        return if (genreId != null) {
            "https://itunes.apple.com/$c/rss/toppodcasts/limit=$limit/genre=$genreId/explicit=true/json"
        } else {
            "https://itunes.apple.com/$c/rss/toppodcasts/limit=$limit/explicit=true/json"
        }
    }

    /** iOS: `AbstandHTTPSession.coverAndCache` — fremde Hosts, ohne Server-Header. */
    private val httpClient: OkHttpClient get() = Net.imageClient

    suspend fun fetchChart(country: String, genreId: Int?, limit: Int = defaultLimit, http: OkHttpClient = httpClient): List<AbsPodcastDirectorySearchHit> {
        if (genreId == null) return enrichWithLookup(fetchChartFeed(country, null, limit, http), http)
        val partial = fetchChartFeed(country, genreId, limit, http)
        val allPeek = fetchChartFeed(country, null, 8, http)
        if (chartMatchesOverallTop(partial, allPeek)) {
            val pool = fetchChartFeed(country, null, categoryFallbackPoolLimit, http)
            return enrichWithLookup(filterHitsByRssCategory(pool, genreId, limit), http)
        }
        return enrichWithLookup(partial, http)
    }

    suspend fun fetchTopPodcasts(country: String, limit: Int = defaultLimit): List<AbsPodcastDirectorySearchHit> =
        fetchChart(country, null, limit)

    private suspend fun fetchChartFeed(country: String, genreId: Int?, limit: Int, http: OkHttpClient): List<AbsPodcastDirectorySearchHit> {
        val url = chartFeedURL(country, genreId, limit) ?: return emptyList()
        val req = Request.Builder().url(url).header("Accept", "application/json").build()
        val res = http.newBuilder().readTimeout(30, java.util.concurrent.TimeUnit.SECONDS).build().awaitResult(req)
        if (!res.isSuccess) throw AbsApiError.HttpStatus(res.code, null)
        return parseChartFeedJSON(res.text)
    }

    /** Apple liefert für einige Genre-IDs dieselbe Liste wie „All“ (z. B. 1316 Sports). */
    private fun chartMatchesOverallTop(genreHits: List<AbsPodcastDirectorySearchHit>, overallHits: List<AbsPodcastDirectorySearchHit>): Boolean {
        val genreIds = genreHits.take(5).map { it.id }
        val overallIds = overallHits.take(5).map { it.id }
        return genreIds.size >= 3 && genreIds == overallIds
    }

    private fun filterHitsByRssCategory(hits: List<AbsPodcastDirectorySearchHit>, genreId: Int, limit: Int): List<AbsPodcastDirectorySearchHit> {
        val labels = rssCategoryLabels(genreId)
        if (labels.isEmpty()) return hits.take(limit)
        val out = ArrayList<AbsPodcastDirectorySearchHit>(limit)
        for (hit in hits) {
            val tag = hit.genres?.firstOrNull()?.swiftTrim()
            if (tag.isNullOrEmpty()) continue
            if (labels.any { rssCategoryLabelMatches(it, tag) }) {
                out.add(hit)
                if (out.size >= limit) break
            }
        }
        return out
    }

    private fun rssCategoryLabelMatches(pattern: String, tag: String): Boolean {
        val p = pattern.swiftTrim().lowercase()
        val t = tag.swiftTrim().lowercase()
        if (p.isEmpty() || t.isEmpty()) return false
        return p == t || t.contains(p) || p.contains(t)
    }

    /** RSS-`category`-Labels (EN/DE) pro iTunes-Genre — Fallback wenn `genre=` ignoriert wird. */
    private fun rssCategoryLabels(genreId: Int): List<String> = when (genreId) {
        1301 -> listOf("Arts", "Kunst", "Books", "Bücher", "Design", "Performing Arts", "Visual Arts")
        1321 -> listOf("Business", "Wirtschaft", "Geldanlage", "Unternehmertum", "Karriere", "Management")
        1303 -> listOf("Comedy", "Komödie")
        1304 -> listOf("Education", "Bildung", "Kurse", "Sprachen lernen", "Training")
        1483 -> listOf("Fiction", "Fiktion", "Drama", "Literatur")
        1323 -> listOf("Government", "Regierung", "Politik")
        1325 -> listOf("Health", "Gesundheit", "Fitness", "Ernährung", "Medizin", "Mentale Gesundheit")
        1307 -> listOf("History", "Geschichte")
        1305 -> listOf("Kids", "Kinder", "Familie", "Kids & Family")
        1502 -> listOf("Leisure", "Freizeit", "Hobbys", "Games", "Spiele")
        1310 -> listOf("Music", "Musik")
        1311 -> listOf("News", "Nachrichten", "Nachrichten des Tages", "Tagesnachrichten", "Politik")
        1314 -> listOf("Religion", "Religion & Spirituality", "Spiritualität")
        1315 -> listOf("Science", "Wissenschaft", "Naturwissenschaften", "Social Sciences")
        1324 -> listOf("Society", "Culture", "Gesellschaft", "Gesellschaft und Kultur", "Philosophie", "Beziehungen")
        1316 -> listOf(
            "Sport", "Sports", "Fußball", "Soccer", "Football", "Basketball", "Baseball", "Hockey",
            "Tennis", "Golf", "Rugby", "Cricket", "American Football", "Fantasy Sports", "Outdoor",
            "Wilderness", "Running",
        )
        1318 -> listOf("Technology", "Technologie", "Tech")
        1488 -> listOf("True Crime", "Wahre Kriminalfälle", "Krimi")
        1309 -> listOf("TV", "Film", "Fernsehen", "Nachgesprochen", "Filmgeschichte", "TV & Film")
        else -> emptyList()
    }

    // MARK: - RSS parse

    internal fun parseChartFeedJSON(data: String): List<AbsPodcastDirectorySearchHit> {
        val root = AbsJson.decoder.parseToJsonElement(data) as? JsonObject ?: return emptyList()
        val feed = root["feed"] as? JsonObject ?: return emptyList()
        val entries = SwiftJson.anyObjList(feed["entry"]) ?: (feed["entry"] as? JsonObject)?.let { listOf(it) } ?: return emptyList()
        return entries.mapNotNull(::parseChartEntry)
    }

    private fun parseChartEntry(entry: JsonObject): AbsPodcastDirectorySearchHit? {
        val id = stringAttribute(entry, "id", "im:id")
        if (id.isNullOrEmpty()) return null
        val title = labelString(entry, "im:name") ?: ""
        val genre = labelAttribute(entry, "category", "label")
        return AbsPodcastDirectorySearchHit(
            id = id,
            title = title.ifEmpty { "Podcast" },
            artistName = labelString(entry, "im:artist"),
            descriptionPlain = labelString(entry, "summary"),
            releaseDate = labelAttribute(entry, "im:releaseDate", "label"),
            genres = genre?.let { listOf(it) },
            cover = bestImageURL(entry),
            feedUrl = null,
            pageUrl = linkHref(entry),
            explicit = null,
        )
    }

    private fun labelString(dict: JsonObject, key: String): String? {
        val node = dict[key] as? JsonObject ?: return null
        val label = SwiftJson.anyString(node["label"]) ?: return null
        return label.swiftTrim().ifEmpty { null }
    }

    private fun labelAttribute(dict: JsonObject, key: String, attribute: String): String? {
        val node = dict[key] as? JsonObject ?: return null
        val attrs = node["attributes"] as? JsonObject ?: return null
        val raw = SwiftJson.anyString(attrs[attribute]) ?: return null
        return raw.swiftTrim().ifEmpty { null }
    }

    private fun stringAttribute(dict: JsonObject, key: String, attribute: String): String? {
        val node = dict[key] as? JsonObject
        val attrs = node?.get("attributes") as? JsonObject
        val raw: JsonElement = attrs?.get(attribute) ?: return labelString(dict, key)
        SwiftJson.anyString(raw)?.let { return it.swiftTrim().ifEmpty { null } }
        SwiftJson.anyInt(raw)?.let { return it.toString() }
        return null
    }

    private fun linkHref(entry: JsonObject): String? {
        val link = entry["link"] as? JsonObject ?: return null
        val attrs = link["attributes"] as? JsonObject ?: return null
        val href = SwiftJson.anyString(attrs["href"]) ?: return null
        return href.swiftTrim().ifEmpty { null }
    }

    private fun bestImageURL(entry: JsonObject): String? {
        val images = SwiftJson.anyObjList(entry["im:image"])
        if (images == null) {
            val one = entry["im:image"] as? JsonObject ?: return null
            return labelString(one, "label")?.ifEmpty { null } ?: SwiftJson.anyString(one["label"])
        }
        var best: Pair<Int, String>? = null
        for (img in images) {
            val url = SwiftJson.anyString(img["label"])?.swiftTrim()
            if (url.isNullOrEmpty()) continue
            val hRaw = (img["attributes"] as? JsonObject)?.get("height")
            val h = SwiftJson.anyInt(hRaw)?.toInt() ?: SwiftJson.anyString(hRaw)?.toIntOrNull() ?: 0
            if (best == null || h > best.first) best = h to url
        }
        return best?.second
    }

    // MARK: - Lookup (feedUrl)

    private data class LookupRow(val feedUrl: String?, val artistId: String?, val trackCount: Int?)

    private suspend fun enrichWithLookup(hits: List<AbsPodcastDirectorySearchHit>, http: OkHttpClient): List<AbsPodcastDirectorySearchHit> {
        val ids = hits.map { it.id }.filter { it.isNotEmpty() }
        if (ids.isEmpty()) return hits
        val lookupById = HashMap<String, LookupRow>()
        for (chunk in ids.chunked(50)) lookupById.putAll(lookupPodcasts(chunk, http))
        return hits.map { hit ->
            val extra = lookupById[hit.id] ?: return@map hit
            hit.copy(
                artistId = extra.artistId ?: hit.artistId,
                trackCount = extra.trackCount ?: hit.trackCount,
                feedUrl = extra.feedUrl ?: hit.feedUrl,
            )
        }
    }

    private suspend fun lookupPodcasts(ids: List<String>, http: OkHttpClient): Map<String, LookupRow> {
        val url = "https://itunes.apple.com/lookup?id=${ids.joinToString(",")}&entity=podcast"
        val req = Request.Builder().url(url).build()
        val res = http.newBuilder().readTimeout(30, java.util.concurrent.TimeUnit.SECONDS).build().awaitResult(req)
        if (!res.isSuccess) throw AbsApiError.HttpStatus(res.code, null)
        val root = AbsJson.decoder.parseToJsonElement(res.text) as? JsonObject ?: return emptyMap()
        val results = SwiftJson.anyObjList(root["results"]) ?: return emptyMap()
        val out = HashMap<String, LookupRow>()
        for (row in results) {
            val cid = SwiftJson.anyInt(row["collectionId"])?.toString() ?: SwiftJson.anyString(row["collectionId"])
            if (cid.isNullOrEmpty()) continue
            val feed = SwiftJson.anyString(row["feedUrl"])?.swiftTrim()
            val artistId = SwiftJson.anyInt(row["artistId"])?.toString() ?: SwiftJson.anyString(row["artistId"])
            val trackCount = SwiftJson.anyInt(row["trackCount"])?.toInt()
            out[cid] = LookupRow(feed?.ifEmpty { null }, artistId, trackCount)
        }
        return out
    }
}

/**
 * iOS: `AppModel.normalizedPodcastFeedURL` — Vergleichsform einer Feed-URL (Host klein,
 * ohne abschließende `/`, Query bleibt).
 */
fun normalizedPodcastFeedURL(raw: String?): String? {
    var s = raw.trimmedOrEmpty()
    if (s.isEmpty()) return null
    val uri = runCatching { URI(s) }.getOrNull()
    val host = uri?.host?.lowercase()
    if (uri != null && host != null) {
        var path = uri.path ?: ""
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
