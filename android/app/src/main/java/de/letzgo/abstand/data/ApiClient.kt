package de.letzgo.abstand.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Dispatcher
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** iOS: `ABSAPIError`. */
sealed class AbsApiError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class InvalidUrl : AbsApiError("Invalid server URL")
    class HttpStatus(val code: Int, val body: String?) :
        AbsApiError(if (!body.isNullOrEmpty()) "Server error $code: $body" else "Server error $code")
    class Unauthorized(val body: String?) :
        AbsApiError(if (!body.isNullOrEmpty()) "Session expired (401): $body" else "Session expired (401) — please sign in again.")
    class Decoding(val error: Throwable) : AbsApiError("Could not read response: ${error.message}", error)
    class EmptyBody : AbsApiError("Empty server response")

    /** iOS: `errorDescription`. */
    val errorDescription: String get() = message ?: ""
}

/**
 * iOS: `Notification.Name.abstandSessionUnauthorized` / `.abstandSessionTokensRefreshed`
 * (`NotificationCenter.default`) — hier als prozessweite `SharedFlow`s.
 */
object ApiEvents {
    /** iOS: `userInfo` von `.abstandSessionTokensRefreshed`. */
    data class TokensRefreshed(
        val serverURL: String,
        val accessToken: String,
        val refreshToken: String,
        /** Identifiziert die Session, die erneuert wurde — AppModel übernimmt nur, wenn es seine eigene ist. */
        val previousRefreshToken: String,
    )

    private val _sessionUnauthorized = MutableSharedFlow<Unit>(extraBufferCapacity = 16)
    private val _tokensRefreshed = MutableSharedFlow<TokensRefreshed>(extraBufferCapacity = 16)

    /** 401 nach (erfolglosem) Refresh — AppModel zeigt den Re-Login. */
    val sessionUnauthorized: SharedFlow<Unit> = _sessionUnauthorized.asSharedFlow()
    /** Access-/Refresh-Token wurden per `/auth/refresh` erneuert. */
    val tokensRefreshed: SharedFlow<TokensRefreshed> = _tokensRefreshed.asSharedFlow()

    internal fun postSessionUnauthorized() { _sessionUnauthorized.tryEmit(Unit) }
    internal fun postTokensRefreshed(e: TokensRefreshed) { _tokensRefreshed.tryEmit(e) }
}

/** iOS: `CoverImageTier` (CoverImageView.swift) — Cover-Auflösung. */
enum class CoverImageTier {
    /** Listen, Karten, Mini-Player. */
    thumbnail,
    /** Buch-/Folgen-Detail, Vollplayer, Now Playing. */
    hero,
}

/** Vollständig gelesene HTTP-Antwort (iOS: `(Data, HTTPURLResponse)`). */
class HttpResult(val code: Int, val body: ByteArray, val mimeType: String?) {
    val text: String get() = body.decodeToString()
    val isSuccess: Boolean get() = code in 200..299
}

/** Wartet auf die OkHttp-Antwort, ohne den Body zu lesen (Aufrufer schließt die [Response]). */
internal suspend fun OkHttpClient.awaitResponse(request: Request): Response = suspendCancellableCoroutine { cont ->
    val call = newCall(request)
    cont.invokeOnCancellation { call.cancel() }
    call.enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) = cont.resumeWithException(e)
        override fun onResponse(call: Call, response: Response) = cont.resume(response)
    })
}

/** Request ausführen und Body vollständig lesen. */
internal suspend fun OkHttpClient.awaitResult(request: Request): HttpResult {
    val response = awaitResponse(request)
    return response.use { r ->
        withContext(Dispatchers.IO) {
            HttpResult(r.code, r.body.bytes(), r.body.contentType()?.let { "${it.type}/${it.subtype}" })
        }
    }
}

/**
 * iOS: `ABSAPIClient` (actor) — alle Server-Requests mit eigenem baseUrl/Token/Refresh-Token.
 *
 * JWT-Regeln (Server ≥ 2.26) wie iOS: [login] sendet `x-return-tokens: true` und wertet 401 als
 * falsche Zugangsdaten; [authedData] erneuert proaktiv (`exp` < 120 s) und nach einem 401 einmal per
 * `POST /auth/refresh` (`x-refresh-token`, Single-Flight, 60 s Backoff), dann Retry; erst danach
 * [ApiEvents.sessionUnauthorized]. `/api/authorize` liefert nur das Legacy-Token — der Client
 * überschreibt damit nie ein gesetztes Refresh-Token.
 *
 * @param http Basis-Client (Produktion: [Net.client]; Tests: eigener Client gegen MockWebServer).
 * @param clock Millisekunden seit 1970 (für JWT-`exp` und Refresh-Backoff; in Tests steuerbar).
 */
class AbsApiClient(
    baseUrl: String,
    token: String,
    refreshToken: String? = null,
    private val http: OkHttpClient = Net.client,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val baseURL: String = baseUrl

    @Volatile private var token: String = token

    /** Rotierendes Refresh-Token (neues JWT-Auth ab Server v2.26); `null` auf alten Servern / Legacy-Sessions. */
    @Volatile private var refreshToken: String? = refreshToken?.swiftTrim()?.ifEmpty { null }

    private val refreshLock = Mutex()
    /** Single-Flight: parallele 401er teilen sich einen Refresh (das Token rotiert pro Aufruf). */
    private var refreshTask: Deferred<Boolean>? = null
    /** Letzter fehlgeschlagener Refresh — Backoff, damit offline nicht jeder Request auf `/auth/refresh` wartet. */
    private var lastRefreshFailureAt: Long? = null
    /** Refresh läuft unabhängig vom aufrufenden Coroutine-Scope (iOS: unstrukturierter `Task`). */
    private val refreshScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val decoder = AbsJson.decoder
    private val encoder = AbsJson.encoder

    private val clientsByTimeout = ConcurrentHashMap<Long, OkHttpClient>()

    /** iOS: `urlSession` — Request-Timeout je Aufruf (URLRequest.timeoutInterval ≙ Lese-/Schreib-Timeout). */
    private fun apiClient(timeoutSeconds: Long): OkHttpClient = clientsByTimeout.getOrPut(timeoutSeconds) {
        http.newBuilder()
            .readTimeout(timeoutSeconds, TimeUnit.SECONDS)
            .writeTimeout(timeoutSeconds, TimeUnit.SECONDS)
            .callTimeout(API_RESOURCE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()
    }

    /**
     * iOS: `downloadURLSession` — eigener Dispatcher, damit langlaufende Downloads API-Calls
     * (z. B. `startPlaySession` für Streaming) nicht blockieren.
     */
    private val downloadClient: OkHttpClient by lazy {
        http.newBuilder()
            .dispatcher(Dispatcher().apply { maxRequestsPerHost = 4 })
            .readTimeout(DOWNLOAD_REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .writeTimeout(DOWNLOAD_REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .callTimeout(API_RESOURCE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()
    }

    fun setToken(newToken: String) { token = newToken }
    fun currentToken(): String = token
    fun setRefreshToken(newToken: String?) { refreshToken = newToken?.swiftTrim()?.ifEmpty { null } }
    /** Nur Android (Tests/Diagnose): aktuelles Refresh-Token. */
    fun currentRefreshToken(): String? = refreshToken

    // MARK: - JWT-Refresh

    /** Erneuert das Access-Token, wenn es bald abläuft. No-op ohne Refresh-Token oder ohne `exp`. */
    private suspend fun refreshIfExpiringSoon() {
        if (refreshToken == null) return
        val exp = jwtExpiryMillis(token) ?: return
        if (exp - clock() < ACCESS_TOKEN_REFRESH_LEEWAY_MS) refreshTokens()
    }

    /** `POST /auth/refresh` mit `x-refresh-token`. Liefert `true`, wenn ein neues Access-Token gesetzt wurde. */
    suspend fun refreshTokens(): Boolean {
        val task: Deferred<Boolean>
        refreshLock.withLock {
            val running = refreshTask
            if (running != null) {
                task = running
                return@withLock
            }
            val current = refreshToken ?: return false
            val failed = lastRefreshFailureAt
            if (failed != null && clock() - failed < REFRESH_FAILURE_BACKOFF_MS) return false
            val base = baseURL
            task = refreshScope.async { performRefresh(current, base) }
            refreshTask = task
        }
        val ok = task.await()
        refreshLock.withLock {
            // Nur der Starter des Refreshs räumt auf (iOS: nur dieser Pfad setzt `refreshTask = nil`).
            if (refreshTask === task) {
                refreshTask = null
                lastRefreshFailureAt = if (ok) null else clock()
            }
        }
        return ok
    }

    private suspend fun performRefresh(current: String, base: String): Boolean {
        val req = Request.Builder()
            .url(joinPath(base, "auth/refresh") ?: return false)
            .post(ByteArray(0).toRequestBody(null))
            .header("Content-Type", "application/json")
            .header("x-refresh-token", current)
            .build()
        val res = try {
            loginClient(http, readTimeoutSeconds = 20).awaitResult(req)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return false
        }
        if (!res.isSuccess) {
            // 401 = Refresh-Token ungültig/abgelaufen → verwerfen, damit der nächste 401 sauber zum Re-Login führt.
            // Andere Fehler (Netz, 5xx, Rate-Limit) lassen das Token stehen.
            if (res.code == 401) refreshToken = null
            return false
        }
        val parsed = runCatching { decoder.decodeFromString(AbsLoginResponseSerializer, res.text) }.getOrNull() ?: return false
        val access = parsed.user.accessToken?.swiftTrim()
        if (access.isNullOrEmpty()) return false
        token = access
        parsed.user.refreshToken?.swiftTrim()?.takeIf { it.isNotEmpty() }?.let { refreshToken = it }
        ApiEvents.postTokensRefreshed(
            ApiEvents.TokensRefreshed(
                serverURL = base,
                accessToken = access,
                refreshToken = refreshToken ?: "",
                previousRefreshToken = current,
            ),
        )
        return true
    }

    /**
     * Zentraler Daten-Request: proaktiver Refresh, bei 401 einmal erneuern und mit neuem Bearer wiederholen.
     * Bleibt es bei 401, meldet [throwForStatus] wie bisher [ApiEvents.sessionUnauthorized].
     */
    private suspend fun authedData(request: Request, timeoutSeconds: Long): HttpResult {
        refreshIfExpiringSoon()
        var req = request
        if (req.header("Authorization") != null) req = req.newBuilder().header("Authorization", "Bearer $token").build()
        val res = apiClient(timeoutSeconds).awaitResult(req)
        if (res.code != 401 || req.header("Authorization") == null || !refreshTokens()) return res
        req = req.newBuilder().header("Authorization", "Bearer $token").build()
        return apiClient(timeoutSeconds).awaitResult(req)
    }

    /** Für Download-Schleifen: `true`, wenn nach 401 erneuert wurde und der Versuch wiederholt werden soll. */
    private suspend fun shouldRetryDownloadAfterRefresh(code: Int): Boolean = code == 401 && refreshTokens()

    /** Bricht laufende Downloads ab (ergänzt Coroutine-Cancel). */
    fun cancelInFlightDownloads() {
        downloadClient.dispatcher.cancelAll()
    }

    fun publicStreamURL(sessionId: String, trackIndex: Int): String =
        buildURL("public/session/$sessionId/track/$trackIndex", emptyMap())

    /** Direkter Dateidownload (wie AudioBooth/ABS-Web); zuverlässiger als Session-Stream für lokale Kopien. */
    fun itemFileDownloadURL(itemId: String, ino: String): String = buildURL("api/items/$itemId/file/$ino/download", emptyMap())

    /** E-Book- oder PDF-Datei eines Hörbuchs herunterladen. */
    suspend fun downloadEbookFile(itemId: String, ino: String, format: AbsEbookFormat, suggestedDestination: File): File {
        val streamURL = itemFileDownloadURL(itemId, ino)
        val dest = File(suggestedDestination.parentFile, "${suggestedDestination.nameWithoutExtension}.${format.fileExtension}")
        var lastError: Throwable? = null
        // Ein Retry nach Token-Refresh zählt nicht als Versuch.
        var attemptLimit = 3
        var refreshRetryUsed = false
        var attempt = -1
        while (attempt + 1 < attemptLimit) {
            attempt += 1
            try {
                refreshIfExpiringSoon()
                val outcome = downloadOnce(streamURL, dest.parentFile ?: File("."), null, null) { code ->
                    if (!refreshRetryUsed && shouldRetryDownloadAfterRefresh(code)) {
                        refreshRetryUsed = true
                        attemptLimit += 1
                        true
                    } else false
                } ?: continue
                if (dest.exists()) dest.delete()
                moveFile(outcome.temp, dest)
                return dest
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                lastError = e
                if (attempt < 2) delay((600L * (attempt + 1)))
            }
        }
        throw lastError ?: AbsApiError.EmptyBody()
    }

    private class DownloadOutcome(val temp: File, val mimeType: String?)

    /**
     * Ein Download-Versuch in eine Temp-Datei. `null` = nach 401 erneuert, Versuch wiederholen.
     * Wirft bei HTTP-Fehlern wie iOS `cleanupAndThrowForDownloadStatus`.
     */
    private suspend fun downloadOnce(
        url: String,
        dir: File,
        progress: ((Double) -> Unit)?,
        knownSize: Long?,
        retryAfter401: suspend (Int) -> Boolean,
    ): DownloadOutcome? {
        val req = Request.Builder().url(url).header("Authorization", "Bearer $token").build()
        val response = downloadClient.awaitResponse(req)
        response.use { r ->
            if (retryAfter401(r.code)) return null
            throwForDownloadStatus(r.code)
            dir.mkdirs()
            val temp = File.createTempFile("abs-dl-", ".part", dir)
            try {
                withContext(Dispatchers.IO) {
                    val expected = r.body.contentLength().takeIf { it > 0 } ?: knownSize
                    r.body.byteStream().use { input ->
                        temp.outputStream().use { out ->
                            val buf = ByteArray(64 * 1024)
                            var written = 0L
                            while (true) {
                                ensureActive()
                                val n = input.read(buf)
                                if (n < 0) break
                                out.write(buf, 0, n)
                                written += n
                                if (progress != null && expected != null && expected > 0) {
                                    progress((written.toDouble() / expected).coerceIn(0.0, 1.0))
                                }
                            }
                        }
                    }
                }
            } catch (e: Throwable) {
                temp.delete()
                throw e
            }
            return DownloadOutcome(temp, r.body.contentType()?.let { "${it.type}/${it.subtype}" })
        }
    }

    // MARK: - Instance requests

    private fun buildURL(path: String, query: Map<String, String>): String {
        val baseStr = baseURL.trim('/')
        val pathClean = path.trim('/')
        val raw = "$baseStr/$pathClean"
        val url = raw.toHttpUrlOrNull() ?: throw AbsApiError.InvalidUrl()
        if (query.isEmpty()) return url.toString()
        val b = url.newBuilder()
        // Kodierung wie `URLComponents.queryItems` (u. a. bleibt `+` unkodiert — wie iOS auf der Leitung).
        for ((k, v) in query) b.addEncodedQueryParameter(swiftQueryEncode(k, isName = true), swiftQueryEncode(v, isName = false))
        return b.build().toString()
    }

    private class ApiRequest(val request: Request, val timeoutSeconds: Long)

    private fun authorizedRequest(
        path: String,
        method: String = "GET",
        query: Map<String, String> = emptyMap(),
        body: ByteArray? = null,
        timeout: Long = 30,
    ): ApiRequest {
        val url = buildURL(path, query)
        val rb = when {
            body != null -> body.toRequestBody(null)
            method == "POST" || method == "PATCH" || method == "PUT" -> ByteArray(0).toRequestBody(null)
            else -> null
        }
        val req = Request.Builder().url(url)
            .method(method, rb)
            .header("Content-Type", "application/json")
            .header("Authorization", "Bearer $token")
            .build()
        return ApiRequest(req, timeout)
    }

    private suspend fun authed(r: ApiRequest): HttpResult = authedData(r.request, r.timeoutSeconds)

    private suspend fun <T> send(r: ApiRequest, deserializer: DeserializationStrategy<T>): T {
        val res = authed(r)
        throwForStatus(res)
        return try {
            decoder.decodeFromString(deserializer, res.text)
        } catch (e: Exception) {
            throw AbsApiError.Decoding(e)
        }
    }

    /** Hör-Sitzungen: striktes Decoding, bei Fehler zeilenweise per `decodeLenient`. */
    private suspend fun sendListeningSessionsPayload(r: ApiRequest): AbsListeningSessionsPayload {
        val res = authed(r)
        throwForStatus(res)
        return try {
            AbsListeningSessionsPayload.decodeLenient(res.text)
        } catch (e: Exception) {
            throw AbsApiError.Decoding(e)
        }
    }

    private suspend fun sendData(r: ApiRequest) {
        throwForStatus(authed(r))
    }

    private suspend fun dataChecked(r: ApiRequest): HttpResult = authed(r).also { throwForStatus(it) }

    private fun <T> decodeWrapped(text: String, deserializer: DeserializationStrategy<T>): T = try {
        decoder.decodeFromString(deserializer, text)
    } catch (e: Exception) {
        throw AbsApiError.Decoding(e)
    }

    suspend fun authorize(): AbsLoginResponse = send(authorizedRequest("api/authorize", method = "POST"), AbsLoginResponseSerializer)

    /** Eigenes Passwort ändern (`PATCH /api/me/password`). */
    suspend fun changePassword(current: String, new: String) {
        val body = encoder.encodeToString(AbsChangePasswordRequest.serializer(), AbsChangePasswordRequest(current, new)).encodeToByteArray()
        sendData(authorizedRequest("api/me/password", method = "PATCH", body = body))
    }

    // MARK: - Server admin (root)

    suspend fun serverUsers(): List<AbsAdminUserSummary> = send(authorizedRequest("api/users"), AbsUsersListResponseSerializer).users

    suspend fun serverOnlineUserIds(): Set<String> =
        (send(authorizedRequest("api/users/online"), AbsUsersOnlineResponseSerializer).usersOnline ?: emptyList()).map { it.id }.toSet()

    suspend fun serverUserDetailData(userId: String): String = dataChecked(authorizedRequest("api/users/$userId")).text

    suspend fun serverUserListeningSessions(userId: String, itemsPerPage: Int = 50, page: Int = 0): AbsListeningSessionsPayload =
        sendListeningSessionsPayload(
            authorizedRequest(
                "api/users/$userId/listening-sessions",
                query = mapOf("itemsPerPage" to "${itemsPerPage.coerceIn(1, 100)}", "page" to "${maxOf(0, page)}"),
            ),
        )

    suspend fun serverLibraryStats(libraryId: String): AbsLibraryStatsResponse =
        send(authorizedRequest("api/libraries/$libraryId/stats"), AbsLibraryStatsResponseSerializer)

    suspend fun scanServerLibrary(libraryId: String) =
        sendData(authorizedRequest("api/libraries/$libraryId/scan", method = "POST", timeout = 300))

    /** M4B-Merge starten (`POST /api/tools/item/:id/encode-m4b`). Admin/Root. */
    suspend fun encodeLibraryItemM4B(libraryItemId: String, bitrate: String = "64k", codec: String = "aac", channels: Int = 2) {
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty()) throw AbsApiError.InvalidUrl()
        sendData(
            authorizedRequest(
                "api/tools/item/$id/encode-m4b",
                method = "POST",
                query = mapOf("bitrate" to bitrate, "codec" to codec, "channels" to "$channels"),
                timeout = 60,
            ),
        )
    }

    /** Laufende M4B-Konvertierung abbrechen (`DELETE /api/tools/item/:id/encode-m4b`). */
    suspend fun cancelLibraryItemM4BEncode(libraryItemId: String) {
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty()) throw AbsApiError.InvalidUrl()
        val res = authed(authorizedRequest("api/tools/item/$id/encode-m4b", method = "DELETE"))
        if (res.code == 404) return
        throwForStatus(res)
    }

    /** Items-Media-Cache leeren (`POST /api/cache/items/purge`) — Originale nach M4B-Merge liegen hier. */
    suspend fun purgeItemsMediaCache() = sendData(authorizedRequest("api/cache/items/purge", method = "POST", timeout = 120))

    /** Gesamten Server-Cache leeren (`POST /api/cache/purge`). */
    suspend fun purgeAllServerCache() = sendData(authorizedRequest("api/cache/purge", method = "POST", timeout = 120))

    suspend fun libraries(): List<AbsLibrary> = send(authorizedRequest("api/libraries"), AbsLibrariesResponseSerializer).libraries

    suspend fun libraryFilterData(libraryId: String): AbsLibraryFilterData =
        send(authorizedRequest("api/libraries/$libraryId/filterdata"), AbsLibraryFilterDataSerializer)

    suspend fun libraryItems(
        libraryId: String,
        page: Int = 0,
        limit: Int = 50,
        sort: String = "media.metadata.title",
        ascending: Boolean = true,
        minified: Boolean = true,
        filter: String? = null,
    ): Pair<AbsPage<AbsBook>, String> {
        val q = linkedMapOf("minified" to if (minified) "1" else "0", "limit" to "$limit", "page" to "$page", "sort" to sort)
        if (!ascending) q["desc"] = "1"
        if (!filter.isNullOrEmpty()) q["filter"] = filter
        val r = authorizedRequest("api/libraries/$libraryId/items", query = q)
        // iOS: `.reloadIgnoringLocalCacheData`.
        val noCache = ApiRequest(r.request.newBuilder().cacheControl(okhttp3.CacheControl.FORCE_NETWORK).build(), r.timeoutSeconds)
        val res = dataChecked(noCache)
        return decodeWrapped(res.text, AbsPage.serializer(AbsBookSerializer)) to res.text
    }

    /** Neueste unbearbeitete Podcast-Folgen (wie Web „Latest episodes“). */
    suspend fun recentPodcastEpisodes(libraryId: String, page: Int = 0, limit: Int = 40): Pair<AbsRecentEpisodesResponse, String> {
        val res = dataChecked(authorizedRequest("api/libraries/$libraryId/recent-episodes", query = mapOf("limit" to "$limit", "page" to "$page")))
        return decodeWrapped(res.text, AbsRecentEpisodesResponseSerializer) to res.text
    }

    /** RSS parsen ohne Library zu ändern (`POST /api/podcasts/feed`). */
    suspend fun fetchPodcastRssFeed(rssFeedUrl: String): String {
        val body = jsonObjectOf { put("rssFeed", JsonPrimitive(rssFeedUrl)) }.toString().encodeToByteArray()
        return dataChecked(authorizedRequest("api/podcasts/feed", method = "POST", body = body, timeout = 180)).text
    }

    /** Ausgewählte Feed-Folgen auf den Server laden (Body = JSON-Array von Folgenobjekten). */
    suspend fun downloadPodcastEpisodesToLibrary(podcastLibraryItemId: String, episodesJsonArray: String) =
        sendData(
            authorizedRequest(
                "api/podcasts/$podcastLibraryItemId/download-episodes",
                method = "POST",
                body = episodesJsonArray.encodeToByteArray(),
                timeout = 300,
            ),
        )

    /** RSS prüfen und neue Folgen auf dem Server laden (`GET /api/podcasts/:id/checknew`). */
    suspend fun checkNewPodcastEpisodes(podcastLibraryItemId: String, limit: Int?): AbsPodcastCheckNewResponse {
        val query = if (limit != null) mapOf("limit" to "$limit") else emptyMap()
        return send(authorizedRequest("api/podcasts/$podcastLibraryItemId/checknew", query = query, timeout = 180), AbsPodcastCheckNewResponseSerializer)
    }

    /** iOS: Decoding-Fehler werden hier **nicht** in `.decoding` verpackt. */
    suspend fun item(id: String, expanded: Boolean = true): AbsBook =
        decoder.decodeFromString(AbsBookSerializer, itemResponseData(id, expanded))

    suspend fun itemResponseData(id: String, expanded: Boolean = true): String =
        dataChecked(authorizedRequest("api/items/$id", query = mapOf("expanded" to if (expanded) "1" else "0"))).text

    /** Podcast: Auto-Download und Cron-Zeitplan (`PATCH /api/items/:id/media`). */
    suspend fun patchPodcastMediaAutoDownload(
        itemId: String,
        autoDownloadEpisodes: Boolean,
        autoDownloadSchedule: String,
        maxEpisodesToKeep: Int,
        maxNewEpisodesToDownload: Int,
    ) {
        val body = encoder.encodeToString(
            AbsPodcastMediaAutoDownloadPatch.serializer(),
            AbsPodcastMediaAutoDownloadPatch(autoDownloadEpisodes, autoDownloadSchedule, maxEpisodesToKeep, maxNewEpisodesToDownload),
        ).encodeToByteArray()
        sendData(authorizedRequest("api/items/$itemId/media", method = "PATCH", body = body))
    }

    /** Verfügbare Metadaten-Provider (`GET /api/search/providers`). */
    suspend fun metadataProviders(): AbsMetadataProvidersResponse =
        send(authorizedRequest("api/search/providers"), AbsMetadataProvidersResponseSerializer)

    /** Online-Metadaten-Suche für Match (`GET /api/search/books`). */
    suspend fun searchBooks(title: String, author: String?, provider: String = "audible", region: String? = null): List<AbsMetadataMatch> {
        val query = linkedMapOf("title" to title, "provider" to provider)
        if (!author.isNullOrEmpty()) query["author"] = author
        if (!region.isNullOrEmpty()) query["region"] = region
        val res = dataChecked(authorizedRequest("api/search/books", query = query))
        // Leere Antwort = keine Treffer.
        if (res.body.isEmpty()) return emptyList()
        val raw = try {
            decoder.parseToJsonElement(res.text) as? JsonArray ?: JsonArray(emptyList())
        } catch (e: Exception) {
            throw AbsApiError.Decoding(e)
        }
        // Manche Provider liefern `{ book: {...} }`-Wrapper pro Treffer.
        return raw.mapNotNull { item ->
            val dict = item as? JsonObject ?: return@mapNotNull null
            val nested = dict["book"] as? JsonObject
            val source = if (nested != null) {
                val merged = LinkedHashMap<String, JsonElement>(nested)
                for ((k, v) in dict) if (k != "book" && merged[k] == null) merged[k] = v
                JsonObject(merged)
            } else dict
            runCatching { AbsMetadataMatchSerializer.decode(source) }.getOrNull()
        }
    }

    /** Wendet ausgewählte Match-Felder an (`PATCH /api/items/:id/media` + optional `POST /api/items/:id/cover`). */
    suspend fun updateItemMedia(itemId: String, patch: AbsItemMediaMetadataPatch, coverURL: String?) {
        sendData(authorizedRequest("api/items/$itemId/media", method = "PATCH", body = patch.toJson().toString().encodeToByteArray()))
        if (!coverURL.isNullOrEmpty()) postCoverURL(itemId, coverURL)
    }

    /** Setzt ein Cover per Remote-URL (`POST /api/items/:id/cover` mit `{ url }`-JSON). */
    suspend fun applyCoverURL(itemId: String, url: String) = postCoverURL(itemId, url)

    private suspend fun postCoverURL(itemId: String, url: String) {
        val payload = encoder.encodeToString(MapSerializer(String.serializer(), String.serializer()), mapOf("url" to url)).encodeToByteArray()
        sendData(authorizedRequest("api/items/$itemId/cover", method = "POST", body = payload))
    }

    /** Online-Cover-Suche (`GET /api/search/covers`) — normalisierte, deduplizierte URL-Strings. */
    suspend fun searchCovers(title: String, author: String?, provider: String = "google"): List<String> {
        val query = linkedMapOf("title" to title, "provider" to provider)
        if (!author.isNullOrEmpty()) query["author"] = author
        val res = dataChecked(authorizedRequest("api/search/covers", query = query, timeout = 25))
        if (res.body.isEmpty()) return emptyList()
        val parsed = try {
            AbsCoverSearchResponse.decode(decoder.parseToJsonElement(res.text))
        } catch (e: Exception) {
            throw AbsApiError.Decoding(e)
        }
        val seen = HashSet<String>()
        return parsed.urls.filter { seen.add(it) }
    }

    /** Audible-Kapitel-Lookup via Audnexus (`GET /api/search/chapters?asin=&region=`). */
    suspend fun searchChapters(asin: String, region: String = "us"): AbsAudibleChaptersResponse {
        val res = dataChecked(authorizedRequest("api/search/chapters", query = mapOf("asin" to asin, "region" to region), timeout = 20))
        return decodeWrapped(res.text, AbsAudibleChaptersResponseSerializer)
    }

    /** Speichert Kapitel (`POST /api/items/:id/chapters`). */
    suspend fun updateItemChapters(itemId: String, chapters: List<AbsItemChaptersPayload.Chapter>) {
        val body = encoder.encodeToString(AbsItemChaptersPayload.serializer(), AbsItemChaptersPayload(chapters)).encodeToByteArray()
        sendData(authorizedRequest("api/items/$itemId/chapters", method = "POST", body = body))
    }

    suspend fun search(libraryId: String, query: String, limit: Int = 48): AbsSearchResponse {
        val res = dataChecked(authorizedRequest("api/libraries/$libraryId/search", query = mapOf("q" to query, "limit" to "$limit")))
        val result = decodeWrapped(res.text, AbsSearchResponseSerializer)
        result.podcastEpisodeMatches = decodePodcastSearchEpisodes(res.text, libraryId)
        return result
    }

    /** Personalisierte Regale wie in der Web-App (`GET /api/libraries/:id/personalized`). */
    suspend fun personalizedShelves(libraryId: String, limit: Int = 14): String =
        dataChecked(authorizedRequest("api/libraries/$libraryId/personalized", query = mapOf("limit" to "$limit"))).text

    /** Laufende Titel (Bücher + Podcast-Folgen mit Fortschritt), vgl. `GET /api/me/items-in-progress`. */
    suspend fun itemsInProgress(limit: Int = 50): AbsItemsInProgressPayload = itemsInProgressWithRawData(limit).first

    /** Wie [itemsInProgress], zusätzlich Roh-JSON für den Disk-Cache (Continue listening). */
    suspend fun itemsInProgressWithRawData(limit: Int = 50): Pair<AbsItemsInProgressPayload, String> {
        val res = dataChecked(authorizedRequest("api/me/items-in-progress", query = mapOf("limit" to "$limit")))
        return decodeInProgressPayload(res.text) to res.text
    }

    /** Paginierte Hör-Sitzungen des eingeloggten Nutzers. */
    suspend fun listeningSessionsMe(itemsPerPage: Int = 50, page: Int = 0): AbsListeningSessionsPayload =
        sendListeningSessionsPayload(
            authorizedRequest(
                "api/me/listening-sessions",
                query = mapOf("itemsPerPage" to "${itemsPerPage.coerceIn(1, 100)}", "page" to "${maxOf(0, page)}"),
            ),
        )

    /** Hör-Sitzungen zu **einem** Medium (ab Server ~2.8; für Bücher ohne `episodeId`). */
    suspend fun listeningSessionsForLibraryItem(
        libraryItemId: String,
        episodeId: String? = null,
        itemsPerPage: Int = 100,
        page: Int = 0,
    ): AbsListeningSessionsPayload {
        var path = "api/me/item/listening-sessions/${libraryItemId.swiftTrim()}"
        episodeId?.swiftTrim()?.takeIf { it.isNotEmpty() }?.let { path += "/$it" }
        return sendListeningSessionsPayload(
            authorizedRequest(path, query = mapOf("itemsPerPage" to "${itemsPerPage.coerceIn(1, 100)}", "page" to "${maxOf(0, page)}")),
        )
    }

    suspend fun createBookmark(libraryItemId: String, time: Int, title: String): AbsAudioBookmark {
        val body = encoder.encodeToString(AbsCreateBookmarkRequest.serializer(), AbsCreateBookmarkRequest(time, title)).encodeToByteArray()
        return send(authorizedRequest("api/me/item/$libraryItemId/bookmark", method = "POST", body = body), AbsAudioBookmarkSerializer)
    }

    suspend fun deleteBookmark(libraryItemId: String, time: Int) =
        sendData(authorizedRequest("api/me/item/$libraryItemId/bookmark/$time", method = "DELETE"))

    /** Aggregierte Statistik; liefert zusätzlich die Rohantwort für den lokalen Cache. */
    suspend fun listeningStats(): Pair<AbsListeningStatsResponse, String> {
        val res = dataChecked(authorizedRequest("api/me/listening-stats"))
        val stats = try {
            AbsListeningStatsResponse.decodeAPIPayload(res.text)
        } catch (e: Exception) {
            throw AbsApiError.Decoding(e)
        }
        return stats to res.text
    }

    suspend fun startPlaySession(itemId: String, episodeId: String? = null, deviceId: String, appVersion: String?): AbsPlaySession {
        val body = encoder.encodeToString(AbsPlaySessionRequest.serializer(), AbsPlaySessionRequest.create(deviceId, appVersion)).encodeToByteArray()
        val eid = episodeId?.swiftTrim()
        val path = if (!eid.isNullOrEmpty()) "api/items/$itemId/play/$eid" else "api/items/$itemId/play"
        return send(authorizedRequest(path, method = "POST", body = body, timeout = 60), AbsPlaySessionSerializer)
    }

    suspend fun syncPlaySession(sessionId: String, timeListened: Int, currentTime: Double) {
        val body = encoder.encodeToString(AbsSessionSyncBody.serializer(), AbsSessionSyncBody(timeListened, currentTime)).encodeToByteArray()
        sendData(authorizedRequest("api/session/$sessionId/sync", method = "POST", body = body))
    }

    suspend fun closePlaySession(sessionId: String) = sendData(authorizedRequest("api/session/$sessionId/close", method = "POST"))

    suspend fun patchProgress(libraryItemId: String, episodeId: String? = null, patch: AbsProgressPatch) {
        val body = encoder.encodeToString(AbsProgressPatch.serializer(), patch).encodeToByteArray()
        val eid = episodeId?.swiftTrim()
        val path = if (!eid.isNullOrEmpty()) "api/me/progress/$libraryItemId/$eid" else "api/me/progress/$libraryItemId"
        sendData(authorizedRequest(path, method = "PATCH", body = body))
    }

    /** Liest einen Progress-Eintrag (`GET /api/me/progress/:libraryItemId[/:episodeId]`); `404` → `null`. */
    suspend fun fetchMediaProgress(libraryItemId: String, episodeId: String? = null): AbsUserMediaProgress? {
        val lid = libraryItemId.swiftTrim()
        if (lid.isEmpty()) throw AbsApiError.InvalidUrl()
        val eid = episodeId?.swiftTrim()
        val path = if (!eid.isNullOrEmpty()) "api/me/progress/$lid/$eid" else "api/me/progress/$lid"
        val res = authed(authorizedRequest(path))
        if (res.code == 404) return null
        throwForStatus(res)
        return decoder.decodeFromString(AbsUserMediaProgressSerializer, res.text)
    }

    /** Entfernt den Media-Progress-Eintrag (`DELETE /api/me/progress/:id`); `404` wird geworfen. */
    suspend fun deleteMediaProgress(progressRowId: String) {
        val id = progressRowId.swiftTrim()
        if (id.isEmpty()) throw AbsApiError.InvalidUrl()
        throwForStatus(authed(authorizedRequest("api/me/progress/$id", method = "DELETE")))
    }

    /** Löscht Progress robust: frische UUID per GET, dann Kandidaten-IDs; Erfolg wenn Eintrag weg ist. */
    suspend fun deleteMediaProgressForLibraryItem(
        libraryItemId: String,
        episodeId: String? = null,
        preferredRowIds: List<String> = emptyList(),
    ) {
        val lid = libraryItemId.swiftTrim()
        if (lid.isEmpty()) throw AbsApiError.InvalidUrl()
        val episodePart = episodeId?.swiftTrim()?.takeIf { it.isNotEmpty() }

        val candidates = ArrayList<String>()
        fun appendCandidate(raw: String?) {
            val t = raw?.swiftTrim()
            if (t.isNullOrEmpty()) return
            if (t !in candidates) candidates.add(t)
        }
        preferredRowIds.forEach { appendCandidate(it) }
        val fresh = try {
            fetchMediaProgress(lid, episodePart)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
        if (fresh != null) {
            appendCandidate(fresh.mediaProgressServerId)
            appendCandidate(fresh.idForMediaProgressDeleteRequest)
        }
        appendCandidate(lid)
        if (episodePart != null) appendCandidate("$lid-$episodePart")

        var lastError: Throwable? = null
        for (id in candidates) {
            try {
                deleteMediaProgress(id)
                return
            } catch (e: CancellationException) {
                throw e
            } catch (e: AbsApiError.HttpStatus) {
                if (e.code == 404) {
                    lastError = AbsApiError.HttpStatus(404, "Media progress id not found: $id")
                    continue
                }
                lastError = e
                // Nicht-404: trotzdem weitere Kandidaten versuchen; 5xx bricht ab.
                if (e.code in 500..599) throw e
            } catch (e: Exception) {
                lastError = e
            }
        }
        // Alle Deletes 404 / fehlgeschlagen — wenn GET leer ist, war der Eintrag schon weg.
        if (fetchMediaProgress(lid, episodePart) == null) return
        throw lastError ?: AbsApiError.HttpStatus(404, "Media progress still present after delete attempts")
    }

    /** Löscht eine Hör-Sitzung (`DELETE /api/sessions/:id`). `404` = schon weg. */
    suspend fun deleteListeningSession(sessionId: String) {
        val id = sessionId.swiftTrim()
        if (id.isEmpty()) throw AbsApiError.InvalidUrl()
        val res = authed(authorizedRequest("api/sessions/$id", method = "DELETE"))
        if (res.code == 404) return
        throwForStatus(res)
    }

    suspend fun markFinished(libraryItemId: String, episodeId: String? = null) =
        patchProgress(libraryItemId, episodeId, AbsProgressPatch(isFinished = true))

    /** `hardDelete`: Dateien auf dem Server-Dateisystem mitlöschen (`?hard=1`, wie ABS-Web-UI). */
    suspend fun deleteLibraryItem(id: String, hardDelete: Boolean = false) =
        sendData(authorizedRequest("api/items/$id", method = "DELETE", query = if (hardDelete) mapOf("hard" to "1") else emptyMap()))

    /** Podcast-Folge von der Bibliothek entfernen (`DELETE /api/podcasts/:id/episode/:episodeId`). */
    suspend fun deletePodcastEpisode(podcastLibraryItemId: String, episodeId: String) =
        sendData(authorizedRequest("api/podcasts/$podcastLibraryItemId/episode/$episodeId", method = "DELETE"))

    fun coverURL(itemId: String, tier: CoverImageTier = CoverImageTier.thumbnail): String = itemCoverURL(baseURL, itemId, tier)

    suspend fun authenticatedData(url: String): ByteArray {
        val req = Request.Builder().url(url).apply {
            token.trim().takeIf { it.isNotEmpty() }?.let { header("Authorization", "Bearer $it") }
        }.build()
        val res = authedData(req, 60)
        throwForStatus(res)
        return res.body
    }

    /**
     * Lädt die Datei mit Wiederholungen (jeweils neuer Request, gleiche URL). Mit [progress] wird —
     * wie die zweite iOS-Überladung — vorab per HEAD die Größe ermittelt und Byte-Fortschritt 0…1 gemeldet.
     */
    suspend fun downloadAuthenticatedFile(
        streamURL: String,
        suggestedDestination: File,
        maxAttempts: Int = 3,
        progress: ((Double) -> Unit)? = null,
    ): File {
        val knownSize = if (progress != null) fetchExpectedContentLength(streamURL) else null
        var lastError: Throwable? = null
        var attemptLimit = maxAttempts
        var refreshRetryUsed = false
        var attempt = -1
        val dir = suggestedDestination.parentFile ?: File(".")
        while (attempt + 1 < attemptLimit) {
            attempt += 1
            try {
                refreshIfExpiringSoon()
                val outcome = downloadOnce(streamURL, dir, progress, knownSize) { code ->
                    if (!refreshRetryUsed && shouldRetryDownloadAfterRefresh(code)) {
                        refreshRetryUsed = true
                        attemptLimit += 1
                        true
                    } else false
                } ?: continue
                val ext = pickAudioFileExtension(outcome.mimeType, outcome.temp)
                val finalFile = File(dir, "${suggestedDestination.nameWithoutExtension}.$ext")
                if (finalFile.exists()) finalFile.delete()
                moveFile(outcome.temp, finalFile)
                return finalFile
            } catch (e: CancellationException) {
                throw e
            } catch (e: AbsApiError.Unauthorized) {
                // 401 (Token abgelaufen) ist nicht wiederholbar — sofort werfen.
                throw e
            } catch (e: IOException) {
                lastError = e
                // OkHttp-Abbruch (`cancelInFlightDownloads`) ≙ `URLError.cancelled`.
                if (e.message == "Canceled") throw e
                if (attempt < maxAttempts - 1) delay(minOf(8000L, (600L * (attempt + 1))))
            } catch (e: Exception) {
                lastError = e
                if (attempt < maxAttempts - 1) delay(minOf(8000L, (600L * (attempt + 1))))
            }
        }
        throw lastError ?: AbsApiError.EmptyBody()
    }

    /** Content-Length via HEAD (`null` bei Fehler oder unbekannter Größe). */
    private suspend fun fetchExpectedContentLength(url: String): Long? = try {
        val req = Request.Builder().url(url).head().header("Authorization", "Bearer $token").build()
        downloadClient.awaitResponse(req).use { r ->
            if (r.code !in 200..299) null else r.header("Content-Length")?.toLongOrNull()?.takeIf { it > 0 }
        }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }

    /** Apple-Podcasts-Suche (`GET /api/search/podcast`). Decoding-Fehler unverpackt (wie iOS). */
    suspend fun searchPodcastsDirectory(term: String, country: String): List<AbsPodcastDirectorySearchHit> {
        val t = term.swiftTrim()
        if (t.isEmpty()) return emptyList()
        val res = dataChecked(authorizedRequest("api/search/podcast", query = mapOf("term" to t, "country" to country)))
        return decoder.decodeFromString(ListSerializer(AbsPodcastDirectorySearchHitSerializer), res.text)
    }

    /** Autoren der Bibliothek (`GET /api/libraries/:id/authors`), mit Pagination und `sort`/`desc`. */
    suspend fun libraryAuthorsPage(
        libraryId: String,
        page: Int,
        limit: Int = 50,
        sort: String,
        descending: Boolean,
    ): Triple<List<AbsLibraryAuthorListItem>, Int, String> {
        val q = linkedMapOf("limit" to "$limit", "page" to "$page", "sort" to sort)
        if (descending) q["desc"] = "1"
        val res = dataChecked(authorizedRequest("api/libraries/$libraryId/authors", query = q))
        try {
            val (items, total) = decoder.decodeFromString(AbsLibraryAuthorsAPIEnvelopeSerializer, res.text).itemsAndTotal()
            return Triple(items, total, res.text)
        } catch (e: Exception) {
            if (page != 0) throw AbsApiError.Decoding(e)
            val res2 = dataChecked(authorizedRequest("api/libraries/$libraryId/authors"))
            val legacy = decodeWrapped(res2.text, AbsLibraryAuthorsEnvelopeSerializer)
            return Triple(legacy.authors, legacy.authors.size, res2.text)
        }
    }

    /** Autor inkl. optionaler Bücher/Serien (`GET /api/authors/:id`). */
    suspend fun authorDetail(authorId: String, libraryId: String?, includeItems: Boolean, includeSeries: Boolean): AbsAuthorDetail {
        val q = linkedMapOf<String, String>()
        val include = mutableListOf<String>()
        if (includeItems) include.add("items")
        if (includeSeries && includeItems) include.add("series")
        if (include.isNotEmpty()) q["include"] = include.joinToString(",")
        if (!libraryId.isNullOrEmpty()) q["library"] = libraryId
        return decodeWrapped(dataChecked(authorizedRequest("api/authors/$authorId", query = q)).text, AbsAuthorDetailSerializer)
    }

    /** Sammlung inkl. Beschreibung (`GET /api/collections/:id`). */
    suspend fun collectionDetail(collectionId: String): AbsLibraryCollectionListItem =
        decodeWrapped(dataChecked(authorizedRequest("api/collections/$collectionId")).text, AbsLibraryCollectionListItemSerializer)

    /** Serie (`GET /api/series/:id`). */
    suspend fun seriesDetail(seriesId: String): AbsSeriesDetail =
        decodeWrapped(dataChecked(authorizedRequest("api/series/$seriesId")).text, AbsSeriesDetailSerializer)

    /** Alle Sprecher:innen (`GET /api/libraries/:id/narrators`). */
    suspend fun libraryNarrators(libraryId: String): Pair<List<AbsLibraryNarratorListItem>, String> {
        val res = dataChecked(authorizedRequest("api/libraries/$libraryId/narrators"))
        return decodeWrapped(res.text, AbsLibraryNarratorsEnvelopeSerializer).narrators to res.text
    }

    /** Serien mit Paginierung (`GET /api/libraries/:id/series`). */
    suspend fun librarySeriesPage(
        libraryId: String,
        page: Int,
        limit: Int = 40,
        sort: String,
        descending: Boolean,
    ): Triple<List<AbsLibrarySeriesListItem>, Int, String> {
        val q = linkedMapOf("limit" to "$limit", "page" to "$page", "sort" to sort, "minified" to "1")
        if (descending) q["desc"] = "1"
        val res = dataChecked(authorizedRequest("api/libraries/$libraryId/series", query = q))
        val env = decodeWrapped(res.text, AbsLibraryResultsPageEnvelope.serializer(AbsLibrarySeriesListItemSerializer))
        return Triple(env.results, env.total, res.text)
    }

    /** Alle Sammlungen (`limit=0` = vollständig — Sortierung im Client). */
    suspend fun libraryCollectionsAll(libraryId: String, minified: Boolean = true): Triple<List<AbsLibraryCollectionListItem>, Int, String> {
        val q = mapOf("limit" to "0", "page" to "0", "minified" to if (minified) "1" else "0")
        val res = dataChecked(authorizedRequest("api/libraries/$libraryId/collections", query = q))
        val env = decodeWrapped(res.text, AbsLibraryResultsPageEnvelope.serializer(AbsLibraryCollectionListItemSerializer))
        return Triple(env.results, env.total, res.text)
    }

    /** Ordner der Bibliothek (`GET /api/libraries/:id`, Feld `folders`). Decoding-Fehler unverpackt. */
    suspend fun libraryFolders(libraryId: String): List<AbsLibraryFolderRow> {
        val res = dataChecked(authorizedRequest("api/libraries/$libraryId"))
        return decoder.decodeFromString(AbsLibraryDetailFoldersPayloadSerializer, res.text).folders ?: emptyList()
    }

    /** Bibliotheks-Detail inkl. Issues/Folders (`GET /api/libraries/:id?include=filterdata`). */
    suspend fun libraryDetail(id: String, includeFilterData: Boolean = true): AbsLibraryDetailEnvelope {
        val res = dataChecked(authorizedRequest("api/libraries/$id", query = if (includeFilterData) mapOf("include" to "filterdata") else emptyMap()))
        if (includeFilterData) return decoder.decodeFromString(AbsLibraryDetailEnvelopeSerializer, res.text)
        val lib = decoder.decodeFromString(AbsLibraryAdminDetailSerializer, res.text)
        return AbsLibraryDetailEnvelope(lib, null, null)
    }

    /** Podcast-Episode-Downloads einer Bibliothek (`GET /api/libraries/:id/episode-downloads`). */
    suspend fun libraryEpisodeDownloads(libraryId: String): AbsLibraryEpisodeDownloadsPayload =
        decoder.decodeFromString(AbsLibraryEpisodeDownloadsPayloadSerializer, dataChecked(authorizedRequest("api/libraries/$libraryId/episode-downloads")).text)

    /** Neuen Podcast anlegen (`POST /api/podcasts`); liefert die neue Item-ID. */
    suspend fun createPodcastInLibrary(jsonBody: String): String {
        val res = dataChecked(authorizedRequest("api/podcasts", method = "POST", body = jsonBody.encodeToByteArray(), timeout = 180))
        val obj = decoder.parseToJsonElement(res.text) as? JsonObject ?: throw AbsApiError.Decoding(IllegalStateException("expected object"))
        val idEl = obj["id"]
        if (idEl != null && !SwiftJson.isNull(idEl) && SwiftJson.string(idEl) == null) throw AbsApiError.Decoding(IllegalStateException("id not a string"))
        val id = SwiftJson.string(idEl)?.swiftTrim()
        if (id.isNullOrEmpty()) throw AbsApiError.Decoding(IllegalStateException("Missing podcast id in response"))
        return id
    }

    companion object {
        /** Vorlauf vor Ablauf, ab dem proaktiv erneuert wird (vermeidet 401 mitten in Download/Sync). */
        const val ACCESS_TOKEN_REFRESH_LEEWAY_MS = 120_000L
        const val REFRESH_FAILURE_BACKOFF_MS = 60_000L
        private const val API_RESOURCE_TIMEOUT_SECONDS = 3_600L
        private const val DOWNLOAD_REQUEST_TIMEOUT_SECONDS = 600L

        /** `exp`-Claim eines JWT in Millisekunden; `null` bei Legacy-Token ohne Ablauf oder unlesbarem Payload. */
        fun jwtExpiryMillis(jwt: String): Long? {
            // Swift `split` lässt leere Teilstücke weg.
            val parts = jwt.split(".").filter { it.isNotEmpty() }
            if (parts.size != 3) return null
            var b64 = parts[1].replace("-", "+").replace("_", "/")
            while (b64.length % 4 != 0) b64 += "="
            val data = runCatching { Base64.getDecoder().decode(b64) }.getOrNull() ?: return null
            val obj = runCatching { AbsJson.decoder.parseToJsonElement(data.decodeToString()) as? JsonObject }.getOrNull() ?: return null
            val exp = SwiftJson.anyDouble(obj["exp"]) ?: return null
            return (exp * 1000).toLong()
        }

        /** iOS: `normalizeServerURL` — als String (iOS `absoluteString`, ohne OkHttp-Normalisierung). */
        fun normalizeServerURL(raw: String): String? {
            var s = raw.swiftTrim()
            if (s.isEmpty()) return null
            if (!s.lowercase().startsWith("http://") && !s.lowercase().startsWith("https://")) s = "https://$s"
            while (s.endsWith("/")) s = s.dropLast(1)
            return s.takeIf { it.toHttpUrlOrNull() != null }
        }

        /** iOS: `loginSession` — 12 s Request-, 20 s Gesamt-Timeout. */
        private fun loginClient(http: OkHttpClient, readTimeoutSeconds: Long = 12): OkHttpClient =
            http.newBuilder()
                .readTimeout(readTimeoutSeconds, TimeUnit.SECONDS)
                .writeTimeout(readTimeoutSeconds, TimeUnit.SECONDS)
                .callTimeout(20, TimeUnit.SECONDS)
                .build()

        /** iOS: `URL.appendingPathComponent` auf der Server-Basis-URL. */
        private fun joinPath(base: String, path: String): String? {
            val b = if (base.endsWith("/")) base else "$base/"
            return (b + path).toHttpUrlOrNull()?.toString()
        }

        suspend fun login(server: String, username: String, password: String, http: OkHttpClient = Net.client): AbsLoginResponse {
            val url = joinPath(server, "login") ?: throw AbsApiError.InvalidUrl()
            val body = AbsJson.encoder.encodeToString(AbsLoginRequest.serializer(), AbsLoginRequest(username, password)).encodeToByteArray()
            val req = Request.Builder().url(url)
                .post(body.toRequestBody(null))
                .header("Content-Type", "application/json")
                // Neues JWT-Auth: Refresh-Token im Body statt nur als Cookie (alte Server ignorieren den Header).
                .header("x-return-tokens", "true")
                .build()
            val res = loginClient(http).awaitResult(req)
            // Bewusst NICHT `throwForStatus`: 401 beim Login heißt falsche Zugangsdaten, nicht abgelaufener
            // Token — kein Session-Unauthorized-Event, Klartext-Serverfehler für die Login-UI.
            if (!res.isSuccess) throw AbsApiError.HttpStatus(res.code, res.text)
            return try {
                AbsJson.decoder.decodeFromString(AbsLoginResponseSerializer, res.text)
            } catch (e: Exception) {
                throw AbsApiError.Decoding(e)
            }
        }

        /** `POST /logout` mit `x-refresh-token` — Fehler werden ignoriert (offline abmelden muss funktionieren). */
        suspend fun logout(server: String, refreshToken: String, http: OkHttpClient = Net.client) {
            val url = joinPath(server, "logout") ?: return
            val req = Request.Builder().url(url).post(ByteArray(0).toRequestBody(null)).header("x-refresh-token", refreshToken).build()
            try {
                loginClient(http, readTimeoutSeconds = 10).awaitResult(req)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            }
        }

        /** Statuscode prüfen; 401 zentral als [AbsApiError.Unauthorized] werfen und melden. */
        internal fun throwForStatus(res: HttpResult) {
            if (res.isSuccess) return
            if (res.code == 401) {
                ApiEvents.postSessionUnauthorized()
                throw AbsApiError.Unauthorized(res.text)
            }
            throw AbsApiError.HttpStatus(res.code, res.text)
        }

        /** Statusprüfung für Download-Pfade: 401 zentral melden. */
        private fun throwForDownloadStatus(code: Int) {
            if (code in 200..299) return
            if (code == 401) {
                ApiEvents.postSessionUnauthorized()
                throw AbsApiError.Unauthorized(null)
            }
            throw AbsApiError.HttpStatus(code, null)
        }

        fun itemCoverURL(baseURL: String, itemId: String, tier: CoverImageTier): String {
            val b = if (baseURL.endsWith("/")) baseURL else "$baseURL/"
            val width = when (tier) {
                CoverImageTier.thumbnail -> "400"
                CoverImageTier.hero -> "1200"
            }
            return "${b}api/items/$itemId/cover?width=$width&format=jpeg"
        }

        /** Dateiendung ohne Punkt, Kleinbuchstaben. */
        fun pickAudioFileExtension(mimeType: String?, file: File): String {
            val m = mimeType?.lowercase() ?: ""
            if (m.contains("mpeg") || m.contains("mp3")) return "mp3"
            if (m.contains("aac") && !m.contains("mp4")) return "aac"
            if (m.contains("flac")) return "flac"
            if (m.contains("ogg") || m.contains("opus") || m.contains("vorbis")) return "ogg"
            if (m.contains("mp4") || m.contains("m4a") || m.contains("m4b")) return "m4a"
            if (m.contains("wav")) return "wav"
            return runCatching { sniffAudioContainer(file) }.getOrNull() ?: "m4a"
        }

        fun sniffAudioContainer(file: File): String {
            val data = file.inputStream().use { input ->
                val buf = ByteArray(16)
                var n = 0
                while (n < 16) {
                    val r = input.read(buf, n, 16 - n)
                    if (r < 0) break
                    n += r
                }
                buf.copyOf(n)
            }
            if (data.size < 4) return "m4a"
            fun u(i: Int) = data[i].toInt() and 0xFF
            if (u(0) == 0x49 && u(1) == 0x44 && u(2) == 0x33) return "mp3"
            if (u(0) == 0xFF && (u(1) and 0xE0) == 0xE0) return "mp3"
            if (data.size >= 8 && u(4) == 0x66 && u(5) == 0x74 && u(6) == 0x79 && u(7) == 0x70) return "m4a"
            return "m4a"
        }

        private fun moveFile(from: File, to: File) {
            if (!from.renameTo(to)) {
                from.copyTo(to, overwrite = true)
                from.delete()
            }
        }

        /** Dekodiert Regale mit Typ `book`, `series` (Bücher aus Serienobjekten) und `authors`. */
        fun parsePersonalizedStartShelves(data: String): List<AbsStartShelfSection> {
            val root = runCatching { AbsJson.decoder.parseToJsonElement(data) }.getOrNull()
            val shelves = SwiftJson.anyObjList(root) ?: return emptyList()
            val out = ArrayList<AbsStartShelfSection>(shelves.size)
            for (shelf in shelves) {
                val sid = SwiftJson.anyString(shelf["id"]) ?: continue
                val label = SwiftJson.anyString(shelf["label"]) ?: continue
                val type = SwiftJson.anyString(shelf["type"]) ?: continue
                val category = AbsStartShelfLocalization.normalizedSettingsCategory(sid, SwiftJson.anyString(shelf["category"]))
                val entities = SwiftJson.anyObjList(shelf["entities"]) ?: emptyList()
                val title = AbsStartShelfLocalization.displayTitle(category, label)
                when (type) {
                    "book" -> {
                        val books = entities.mapNotNull { e ->
                            val mt = SwiftJson.anyString(e["mediaType"])
                            if (mt != null && mt != "book") return@mapNotNull null
                            val book = runCatching { AbsBookSerializer.decode(e) }.getOrNull() ?: return@mapNotNull null
                            val include = if (category == "continueSeries") book.isPlayableAudiobook || book.isPureEbookLibraryItem else book.isPlayableAudiobook
                            if (include) book else null
                        }
                        if (books.isEmpty()) continue
                        out.add(AbsStartShelfSection(id = sid, category = category, displayTitle = title, books = books))
                    }
                    "series" -> {
                        val isContinueSeries = category == "continueSeries"
                        val series = entities.mapNotNull { ser ->
                            val item = runCatching { AbsLibrarySeriesListItemSerializer.decode(ser) }.getOrNull() ?: return@mapNotNull null
                            val books = item.books ?: emptyList()
                            val named = item.name.swiftTrim().isNotEmpty()
                            if (isContinueSeries) {
                                val hasContent = books.any { it.isPlayableAudiobook || it.isPureEbookLibraryItem }
                                return@mapNotNull if (hasContent || named) item else null
                            }
                            val playable = books.any { it.isPlayableAudiobook }
                            val hasEbook = books.any { it.isUsableEbookListRow }
                            if (playable || hasEbook || named) item else null
                        }
                        if (series.isEmpty()) continue
                        out.add(AbsStartShelfSection(id = sid, category = category, displayTitle = title, series = series))
                    }
                    "authors" -> {
                        val authors = entities.mapNotNull { runCatching { AbsAuthorShelfEntitySerializer.decode(it) }.getOrNull() }
                        if (authors.isEmpty()) continue
                        out.add(AbsStartShelfSection(id = sid, category = category, displayTitle = title, authors = authors))
                    }
                }
            }
            return out
        }

        fun decodeInProgressPayload(data: String): AbsItemsInProgressPayload {
            val root = runCatching { AbsJson.decoder.parseToJsonElement(data) as? JsonObject }.getOrNull()
            val items = SwiftJson.anyObjList(root?.get("libraryItems")) ?: return AbsItemsInProgressPayload(emptyList(), emptyList())
            val books = ArrayList<AbsBook>(items.size)
            val podcastEpisodes = ArrayList<AbsPodcastEpisodeListItem>()
            for (obj in items) {
                val mt = SwiftJson.anyString(obj["mediaType"])?.lowercase() ?: ""
                if (mt == "book") {
                    val book = runCatching { AbsBookSerializer.decode(obj) }.getOrNull()
                    if (book != null && book.isPlayableAudiobook) books.add(book)
                } else if (mt == "podcast") {
                    var recent = obj["recentEpisode"] as? JsonObject ?: continue
                    val liId = SwiftJson.anyString(obj["id"])?.swiftTrim() ?: ""
                    if (liId.isEmpty()) continue
                    val existing = SwiftJson.anyString(recent["libraryItemId"])?.swiftTrim() ?: ""
                    if (existing.isEmpty()) recent = JsonObject(recent + ("libraryItemId" to JsonPrimitive(liId)))
                    val dto = runCatching { AbsRecentPodcastEpisodeDTOSerializer.decode(recent) }.getOrNull() ?: continue
                    val libId = SwiftJson.anyString(obj["libraryId"])
                    val show = runCatching { AbsBookSerializer.decode(obj) }.getOrNull()
                    AbsPodcastEpisodeListItem.fromDTO(dto, fallbackShow = show, libraryId = libId)?.let(podcastEpisodes::add)
                }
            }
            return AbsItemsInProgressPayload(books, podcastEpisodes)
        }

        /** Search-API: `episodes` sind Library-Items mit `recentEpisode` (wie Home/In-Progress). */
        fun decodePodcastSearchEpisodes(data: String, libraryId: String?): List<AbsPodcastEpisodeListItem> {
            val root = runCatching { AbsJson.decoder.parseToJsonElement(data) as? JsonObject }.getOrNull()
            val items = SwiftJson.anyObjList(root?.get("episodes")) ?: return emptyList()
            val libId = libraryId?.swiftTrim()?.ifEmpty { null }
            val rows = items.mapNotNull { decodePodcastSearchEpisodeRow(it, libId) }
            return AbsPodcastEpisodeListItem.dedupeRows(rows)
        }

        /** Ein Search-Treffer: Show-Library-Item mit `recentEpisode`. */
        private fun decodePodcastSearchEpisodeRow(obj: JsonObject, libraryId: String?): AbsPodcastEpisodeListItem? {
            val showId = SwiftJson.anyString(obj["id"])?.swiftTrim() ?: ""
            val itemLibId = SwiftJson.anyString(obj["libraryId"])?.swiftTrim()
            val resolvedLibId = if (!itemLibId.isNullOrEmpty()) itemLibId else libraryId
            val show = if (showId.isNotEmpty()) runCatching { AbsBookSerializer.decode(obj) }.getOrNull() else null
            var recent = obj["recentEpisode"] as? JsonObject ?: return null
            val existing = SwiftJson.anyString(recent["libraryItemId"])?.swiftTrim() ?: ""
            // Ohne Show-ID greift `showIdFallback` — liest dieselbe (leere) ID, also kein Effekt.
            if (showId.isNotEmpty() && existing.isEmpty()) recent = JsonObject(recent + ("libraryItemId" to JsonPrimitive(showId)))
            val dto = runCatching { AbsRecentPodcastEpisodeDTOSerializer.decode(recent) }.getOrNull() ?: return null
            return AbsPodcastEpisodeListItem.fromDTO(dto, fallbackShow = show, libraryId = resolvedLibId, forceLibraryItemId = showId.ifEmpty { null })
        }

        private const val UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        private const val QUERY_EXTRA = "!$'()*,;:@/?"

        /**
         * Kodierung wie iOS `buildURL`: erlaubt bleiben `urlQueryAllowed` ohne `&` und `+` (und
         * ohne `=` in Namen). `+` wird kodiert, sonst liest der Server es als Leerzeichen.
         */
        internal fun swiftQueryEncode(s: String, isName: Boolean): String {
            val sb = StringBuilder()
            for (b in s.encodeToByteArray()) {
                val c = (b.toInt() and 0xFF).toChar()
                val allowed = b >= 0 && (c in UNRESERVED || c in QUERY_EXTRA || (!isName && c == '='))
                if (allowed) sb.append(c) else sb.append('%').append(String.format("%02X", b.toInt() and 0xFF))
            }
            return sb.toString()
        }
    }
}
