package de.letzgo.abstand.data

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.OkHttpClient
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.nio.file.Files
import java.util.Base64
import java.util.Collections
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/** JWT-Regeln des API-Clients (iOS: `ABSAPIClient.authedData` / `refreshTokens`) gegen einen Fake-ABS. */
class ApiClientAuthTest {
    private lateinit var server: MockWebServer
    private val fake = FakeAbs()
    private val http = OkHttpClient()
    private val now = AtomicLong(1_760_000_000_000L)

    @Before
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = fake
        server.start()
    }

    @After
    fun tearDown() {
        server.close()
    }

    private fun base() = server.url("/").toString().trimEnd('/')

    private fun client(token: String, refresh: String?) = AbsApiClient(base(), token, refresh, http = http, clock = { now.get() })

    private fun jwt(expSeconds: Long): String {
        val enc = Base64.getUrlEncoder().withoutPadding()
        return enc.encodeToString("{}".toByteArray()) + "." + enc.encodeToString("""{"exp":$expSeconds}""".toByteArray()) + ".sig"
    }

    /** Minimaler Audiobookshelf: alle API-Pfade verlangen [validAccess], `/auth/refresh` rotiert die Tokens. */
    class FakeAbs : Dispatcher() {
        @Volatile var validAccess = "access-2"
        @Volatile var refreshCode = 200
        @Volatile var refreshDelayMs = 0L
        @Volatile var nextAccess = "access-2"
        @Volatile var nextRefresh = "refresh-2"
        val refreshCalls = AtomicInteger()
        val log: MutableList<String> = Collections.synchronizedList(mutableListOf())
        val refreshHeaders: MutableList<String?> = Collections.synchronizedList(mutableListOf())
        val loginHeaders: MutableList<String?> = Collections.synchronizedList(mutableListOf())
        var downloadBytes = byteArrayOf()

        override fun dispatch(request: RecordedRequest): MockResponse {
            val path = request.url.encodedPath
            val auth = request.headers["Authorization"]
            log.add("$path $auth")
            return when {
                path == "/auth/refresh" -> {
                    refreshCalls.incrementAndGet()
                    refreshHeaders.add(request.headers["x-refresh-token"])
                    if (refreshDelayMs > 0) Thread.sleep(refreshDelayMs)
                    if (refreshCode != 200) {
                        MockResponse.Builder().code(refreshCode).body("nope").build()
                    } else {
                        validAccess = nextAccess
                        json(200, """{"user":{"id":"u1","username":"demo","accessToken":"$nextAccess","refreshToken":"$nextRefresh"}}""")
                    }
                }
                path == "/login" -> {
                    loginHeaders.add(request.headers["x-return-tokens"])
                    if (request.body?.utf8()?.contains("\"password\":\"secret\"") == true) {
                        json(200, """{"user":{"id":"u1","username":"demo","token":"legacy","accessToken":"a1","refreshToken":"r1"},"userDefaultLibraryId":"lib1"}""")
                    } else {
                        MockResponse.Builder().code(401).body("Invalid username or password").build()
                    }
                }
                auth != "Bearer $validAccess" -> MockResponse.Builder().code(401).body("Unauthorized").build()
                path.endsWith("/download") ->
                    MockResponse.Builder().code(200).addHeader("Content-Type", "application/octet-stream")
                        .body(Buffer().write(downloadBytes)).build()
                path == "/api/libraries" -> json(200, """{"libraries":[{"id":"lib1","name":"Books","mediaType":"book"}]}""")
                else -> MockResponse.Builder().code(404).build()
            }
        }

        private fun json(code: Int, body: String) =
            MockResponse.Builder().code(code).addHeader("Content-Type", "application/json").body(body).build()
    }

    @Test
    fun jwtExpiryParsing() {
        assertEquals(1_900_000_000_000L, AbsApiClient.jwtExpiryMillis(jwt(1_900_000_000)))
        assertEquals(1_900_000_000_500L, AbsApiClient.jwtExpiryMillis("e30." + Base64.getUrlEncoder().withoutPadding().encodeToString("""{"exp":1900000000.5}""".toByteArray()) + ".s"))
        assertNull(AbsApiClient.jwtExpiryMillis("legacy-token-without-dots"))
        assertNull(AbsApiClient.jwtExpiryMillis("a.b"))
        assertNull(AbsApiClient.jwtExpiryMillis("e30.e30.sig")) // kein `exp`
        assertNull(AbsApiClient.jwtExpiryMillis("e30.!!!.sig")) // kein Base64
        // Swift `split` ignoriert leere Teile: "a..b.c" hat drei Teile.
        assertEquals(1_900_000_000_000L, AbsApiClient.jwtExpiryMillis("e30.." + jwt(1_900_000_000).substringAfter(".")))
    }

    @Test
    fun refreshAfter401RetriesWithNewBearerAndPublishesTokens() = runBlocking<Unit> {
        val events = CopyOnWriteArrayList<ApiEvents.TokensRefreshed>()
        val job = launch(Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) { ApiEvents.tokensRefreshed.collect { events.add(it) } }
        val c = client("stale-legacy-token", "refresh-1")

        val libs = c.libraries()

        assertEquals("lib1", libs.single().id)
        assertEquals(1, fake.refreshCalls.get())
        assertEquals(listOf<String?>("refresh-1"), fake.refreshHeaders)
        assertEquals("access-2", c.currentToken())
        assertEquals("refresh-2", c.currentRefreshToken())
        assertEquals(
            listOf("/api/libraries Bearer stale-legacy-token", "/auth/refresh null", "/api/libraries Bearer access-2"),
            fake.log.toList(),
        )
        withTimeout(2_000) { while (events.isEmpty()) delay(10) }
        events.single().let {
            assertEquals(base(), it.serverURL)
            assertEquals("access-2", it.accessToken)
            assertEquals("refresh-2", it.refreshToken)
            assertEquals("refresh-1", it.previousRefreshToken)
        }
        job.cancel()
    }

    @Test
    fun concurrentUnauthorizedRequestsShareOneRefresh() = runBlocking<Unit> {
        fake.refreshDelayMs = 300
        val c = client("stale", "refresh-1")
        val results = (1..6).map { async(Dispatchers.IO) { c.libraries() } }.awaitAll()
        assertEquals(6, results.size)
        assertEquals(1, fake.refreshCalls.get())
        assertEquals("access-2", c.currentToken())
    }

    @Test
    fun failedRefreshBacksOffForSixtySeconds() = runBlocking<Unit> {
        fake.refreshCode = 500
        val unauthorized = AtomicInteger()
        val job = launch(Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            ApiEvents.sessionUnauthorized.collect { unauthorized.incrementAndGet() }
        }
        val c = client("stale", "refresh-1")

        expectUnauthorized { c.libraries() }
        assertEquals(1, fake.refreshCalls.get())
        // 5xx lässt das Refresh-Token stehen.
        assertEquals("refresh-1", c.currentRefreshToken())

        now.addAndGet(59_000)
        expectUnauthorized { c.libraries() }
        assertEquals("innerhalb des Backoffs kein zweiter Refresh", 1, fake.refreshCalls.get())

        now.addAndGet(2_000)
        fake.refreshCode = 200
        assertEquals("lib1", c.libraries().single().id)
        assertEquals(2, fake.refreshCalls.get())

        withTimeout(2_000) { while (unauthorized.get() < 2) delay(10) }
        assertEquals(2, unauthorized.get())
        job.cancel()
    }

    @Test
    fun refresh401DropsRefreshToken() = runBlocking<Unit> {
        fake.refreshCode = 401
        val c = client("stale", "refresh-1")
        expectUnauthorized { c.libraries() }
        assertNull(c.currentRefreshToken())
        now.addAndGet(120_000)
        expectUnauthorized { c.libraries() }
        assertEquals(1, fake.refreshCalls.get())
    }

    @Test
    fun proactiveRefreshWhenJwtExpiresWithinLeeway() = runBlocking<Unit> {
        val soon = jwt(now.get() / 1000 + 60)
        val c = client(soon, "refresh-1")
        c.libraries()
        assertEquals(listOf("/auth/refresh null", "/api/libraries Bearer access-2"), fake.log.toList())
    }

    @Test
    fun noRefreshWhenJwtIsFresh() = runBlocking<Unit> {
        val fresh = jwt(now.get() / 1000 + 600)
        fake.validAccess = fresh
        val c = client(fresh, "refresh-1")
        c.libraries()
        assertEquals(0, fake.refreshCalls.get())
    }

    @Test
    fun legacySessionWithoutRefreshTokenReportsUnauthorized() = runBlocking<Unit> {
        val unauthorized = AtomicInteger()
        val job = launch(Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            ApiEvents.sessionUnauthorized.collect { unauthorized.incrementAndGet() }
        }
        val c = client("legacy", null)
        expectUnauthorized { c.libraries() }
        assertEquals(0, fake.refreshCalls.get())
        withTimeout(2_000) { while (unauthorized.get() < 1) delay(10) }
        job.cancel()
    }

    @Test
    fun loginSendsReturnTokensAndTreats401AsBadCredentials() = runBlocking<Unit> {
        val unauthorized = AtomicInteger()
        val job = launch(Dispatchers.Unconfined, start = CoroutineStart.UNDISPATCHED) {
            ApiEvents.sessionUnauthorized.collect { unauthorized.incrementAndGet() }
        }
        val ok = AbsApiClient.login(base(), "demo", "secret", http)
        assertEquals("a1", ok.user.effectiveBearerToken)
        assertEquals("r1", ok.user.refreshToken)
        assertEquals("lib1", ok.userDefaultLibraryId)
        try {
            AbsApiClient.login(base(), "demo", "wrong", http)
            fail("401 erwartet")
        } catch (e: AbsApiError.HttpStatus) {
            assertEquals(401, e.code)
            assertEquals("Invalid username or password", e.body)
        }
        assertEquals(listOf<String?>("true", "true"), fake.loginHeaders)
        delay(100)
        assertEquals("Login-401 ist kein Session-Ablauf", 0, unauthorized.get())
        job.cancel()
    }

    @Test
    fun downloadRetriesOnceAfter401AndSniffsContainer() = runBlocking<Unit> {
        fake.downloadBytes = byteArrayOf(0x49, 0x44, 0x33, 0x04, 0, 0, 0, 0, 0, 0, 1, 2, 3)
        val dir = Files.createTempDirectory("abs-dl").toFile()
        val c = client("stale", "refresh-1")
        var lastProgress = -1.0
        val file = c.downloadAuthenticatedFile(
            c.itemFileDownloadURL("li_book_0001", "1001"),
            java.io.File(dir, "track-001.part"),
            progress = { lastProgress = it },
        )
        assertEquals("track-001.mp3", file.name)
        assertTrue(file.readBytes().contentEquals(fake.downloadBytes))
        assertEquals(1, fake.refreshCalls.get())
        assertEquals(1.0, lastProgress, 0.0)
        assertEquals(listOf("track-001.mp3"), dir.list()!!.toList())
        dir.deleteRecursively()
    }

    @Test
    fun queryEncodingMatchesUrlComponents() {
        assertEquals("tags.Zm9v%2BYmFy==", AbsApiClient.swiftQueryEncode("tags.Zm9v+YmFy==", isName = false))
        assertEquals("C%2B%2B", AbsApiClient.swiftQueryEncode("C++", isName = false))
        assertEquals("a%20b%26c", AbsApiClient.swiftQueryEncode("a b&c", isName = false))
        assertEquals("k%3D", AbsApiClient.swiftQueryEncode("k=", isName = true))
        assertEquals("%C3%A4", AbsApiClient.swiftQueryEncode("ä", isName = false))
    }

    private suspend fun expectUnauthorized(block: suspend () -> Unit) {
        try {
            block()
            fail("Unauthorized erwartet")
        } catch (e: AbsApiError.Unauthorized) {
            // erwartet
        }
    }
}
