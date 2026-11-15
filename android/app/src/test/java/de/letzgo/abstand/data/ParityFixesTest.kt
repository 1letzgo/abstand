package de.letzgo.abstand.data

import de.letzgo.abstand.model.SessionLogic
import de.letzgo.abstand.player.PendingOfflineListening
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Android-Gegenstücke der iOS-Fixes (Token-CAS, Lossy-Paging, Offline-Hörzeit je Account, Socket-Auth). */
class ParityFixesTest {
    @Test
    fun adoptRotatedTokensIsCompareAndSwap() {
        val c = AbsApiClient("https://abs.example.org", "a1", "r1", http = okhttp3.OkHttpClient())
        assertFalse(c.adoptRotatedTokens("a2", "r2", "other"))
        assertEquals("a1", c.currentToken())
        assertTrue(c.adoptRotatedTokens("a2", "r2", "r1"))
        assertEquals("a2", c.currentToken())
        assertEquals("r2", c.currentRefreshToken())
        // Verspätete Meldung derselben Rotation rollt nicht zurück.
        assertFalse(c.adoptRotatedTokens("a1", "r1", "r1"))
        assertEquals("r2", c.currentRefreshToken())
        // Legacy-Client ohne Refresh-Token übernimmt nie.
        assertFalse(AbsApiClient("https://abs.example.org", "t", null, http = okhttp3.OkHttpClient()).adoptRotatedTokens("a", "r", "r"))
    }

    private fun account(key: String, server: String, refresh: String?) = AbsStoredAccount(
        accountKey = key, serverURL = server, token = "old-$key", refreshToken = refresh, userId = "u-$key", username = key,
        userType = null, booksLibraryId = null, podcastsLibraryId = null, ebooksLibraryId = null, lastUsedAt = 0,
    )

    @Test
    fun rotationOfInactiveAccountLandsInStoredAccount() {
        val accounts = listOf(account("a", "abs.example.org", "r1"), account("b", "abs.example.org", "r9"))
        val updated = SessionLogic.adoptRefreshedTokensForStoredAccount(accounts, "https://abs.example.org", "jwt", "r2", "r1")!!
        assertEquals("jwt", updated[0].token)
        assertEquals("r2", updated[0].refreshToken)
        assertEquals(accounts[1], updated[1])
        assertNull(SessionLogic.adoptRefreshedTokensForStoredAccount(accounts, "https://other.org", "jwt", "r2", "r1"))
        assertNull(SessionLogic.adoptRefreshedTokensForStoredAccount(accounts, "https://abs.example.org", "jwt", "r2", "unknown"))
    }

    @Test
    fun pagedEnvelopeSkipsBrokenElements() {
        val env = AbsJson.decoder.decodeFromString(
            AbsLibraryResultsPageEnvelope.serializer(ElementDecoder.string),
            """{"results":["a",{"broken":true},"b"],"total":7}""",
        )
        assertEquals(listOf("a", "b"), env.results)
        assertEquals(7, env.total)
    }

    @Test
    fun pendingOfflineListeningScopeAndSubtraction() {
        val base = Keys.pendingOfflineListeningSeconds
        assertEquals(base, PendingOfflineListening.storageKey(null, "u"))
        assertEquals("$base.https://abs.example.org", PendingOfflineListening.storageKey("https://abs.example.org", " "))
        assertEquals("$base.https://abs.example.org.u1", PendingOfflineListening.storageKey("https://abs.example.org", "u1"))
        // Während des Flushs kamen 5 s für „a" dazu — nur das Gesendete abziehen.
        assertEquals(
            mapOf("a" to 5, "c" to 3),
            PendingOfflineListening.subtractingSent(mapOf("a" to 35, "b" to 10, "c" to 3), mapOf("a" to 30, "b" to 10)),
        )
    }

    @Test
    fun adminSocketAuthEvents() {
        assertEquals(AdminSocketEvent.AuthAccepted, AdminSocketProtocol.parseEventPayload("""["init",{"usersOnline":[]}]"""))
        assertEquals(AdminSocketEvent.AuthRejected, AdminSocketProtocol.parseEventPayload("""["invalid_token"]"""))
        assertTrue(AdminSocketProtocol.handlePacket("40{\"sid\":\"y\"}", "tok").authRequested)
    }
}
