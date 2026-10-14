package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsApiError
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsStoredAccount
import de.letzgo.abstand.data.AbsUser
import de.letzgo.abstand.data.ContinueRefreshAttemptResult
import de.letzgo.abstand.data.Keys
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionLogicTest {
    private fun account(key: String, userId: String = "u1", server: String = "https://abs.example.org") = AbsStoredAccount(
        accountKey = key, serverURL = server, token = "t", userId = userId, username = "name", userType = "user",
        booksLibraryId = null, podcastsLibraryId = null, ebooksLibraryId = null, lastUsedAt = 0,
    )

    private fun user(id: String = "u1", token: String = "legacy", access: String? = "jwt", refresh: String? = "r1") = AbsUser(
        id = id, username = "alice", token = token, accessToken = access, refreshToken = refresh, type = "admin",
        mediaProgress = null, bookmarks = null,
    )

    @Test
    fun accountKeyNormalization() {
        // Schema ergänzt, Slash weg, Kleinschreibung, User-ID getrimmt.
        assertEquals("https://abs.example.org|u1", AbsStoredAccount.makeKey(" ABS.example.org/ ", " u1 "))
        assertEquals(AbsStoredAccount.makeKey("https://abs.example.org", "u1"), AbsStoredAccount.makeKey("abs.example.org//", "u1"))
    }

    @Test
    fun authHttpStatus() {
        assertTrue(SessionLogic.isAuthHTTPStatus(AbsApiError.Unauthorized(null)))
        assertTrue(SessionLogic.isAuthHTTPStatus(AbsApiError.HttpStatus(403, null)))
        assertFalse(SessionLogic.isAuthHTTPStatus(AbsApiError.HttpStatus(500, null)))
        assertFalse(SessionLogic.isAuthHTTPStatus(java.io.IOException("x")))
        assertFalse(SessionLogic.isAuthHTTPStatus(null))
    }

    @Test
    fun authorizeFallbackDecision() {
        val authErr = ContinueRefreshAttemptResult(error = AbsApiError.Unauthorized(null))
        assertTrue(SessionLogic.needsAuthorizeFallbackForContinue(authErr, attemptedOnline = false, { true }, { false }))
        val notAttempted = ContinueRefreshAttemptResult()
        assertFalse(SessionLogic.needsAuthorizeFallbackForContinue(notAttempted, false, { false }, { true }))
        val failedOnline = ContinueRefreshAttemptResult(appliedOnline = false, attemptedNetwork = true)
        assertTrue(SessionLogic.needsAuthorizeFallbackForContinue(failedOnline, true, { false }, { false }))
        assertFalse(SessionLogic.needsAuthorizeFallbackForContinue(failedOnline, true, { true }, { false }))
        val applied = ContinueRefreshAttemptResult(appliedOnline = true, attemptedNetwork = true)
        assertFalse(SessionLogic.needsAuthorizeFallbackForContinue(applied, true, { false }, { false }))
        assertTrue(SessionLogic.needsAuthorizeFallbackForContinue(applied, true, { false }, { true }))
    }

    @Test
    fun storedAccountsBootstrapState() {
        val a = account("a")
        val b = account("b")
        assertEquals(SessionLogic.StoredAccountsState(emptyList(), null, false), SessionLogic.bootstrapStoredAccountsState(emptyList(), null))
        assertEquals("a", SessionLogic.bootstrapStoredAccountsState(listOf(a, b), null).activeKey)
        assertTrue(SessionLogic.bootstrapStoredAccountsState(listOf(a, b), null).activeKeyChanged)
        assertEquals("b", SessionLogic.bootstrapStoredAccountsState(listOf(a, b), "b").activeKey)
        assertFalse(SessionLogic.bootstrapStoredAccountsState(listOf(a, b), "b").activeKeyChanged)
        // Unbekannter aktiver Key → erster Account.
        assertEquals("a", SessionLogic.bootstrapStoredAccountsState(listOf(a, b), "gone").activeKey)
        // Ohne Accounts bleibt ein unbekannter Key stehen (iOS-Verhalten).
        assertEquals("gone", SessionLogic.bootstrapStoredAccountsState(emptyList(), "gone").activeKey)
    }

    @Test
    fun legacySingleAccountMigration() {
        assertNull(SessionLogic.migrateLegacySingleAccount("", "t", "u", null, null, 1))
        assertNull(SessionLogic.migrateLegacySingleAccount("https://x.test", " ", "u", null, null, 1))
        assertNull(SessionLogic.migrateLegacySingleAccount("https://x.test", "t", null, null, null, 1))
        val m = SessionLogic.migrateLegacySingleAccount(" x.test ", "t", " u ", "lib", "pod", 7)!!
        assertEquals("https://x.test|u", m.accountKey)
        assertEquals("lib", m.ebooksLibraryId)
        assertEquals("pod", m.podcastsLibraryId)
        assertEquals(7, m.lastUsedAt)
    }

    @Test
    fun refreshedTokensAdoptionGuard() {
        val server = "abs.example.org/"
        assertTrue(SessionLogic.shouldAdoptRefreshedTokens(server, "https://ABS.example.org", "r1", "r1", "jwt"))
        assertFalse(SessionLogic.shouldAdoptRefreshedTokens(server, "https://other.org", "r1", "r1", "jwt"))
        // Fremde Session (anderes Refresh-Token) auf demselben Server.
        assertFalse(SessionLogic.shouldAdoptRefreshedTokens(server, "https://abs.example.org", "r2", "r1", "jwt"))
        // Legacy-Session ohne Refresh-Token.
        assertFalse(SessionLogic.shouldAdoptRefreshedTokens(server, "https://abs.example.org", "", "", "jwt"))
        assertFalse(SessionLogic.shouldAdoptRefreshedTokens(server, "https://abs.example.org", "r1", "r1", ""))
    }

    private fun snapshot(userId: String = "u1") = SessionLogic.SessionSnapshot(
        serverURL = "https://abs.example.org", token = "tok", refreshToken = "", userId = userId, username = "alice",
        userType = "", booksLibraryId = "lib", podcastsLibraryId = Keys.librarySelectionNone,
        activeBooksLibraryIds = listOf("lib"), activePodcastLibraryIds = emptyList(),
    )

    @Test
    fun syncStoredAccountsUpdatesInsertsAndMigrates() {
        assertNull(SessionLogic.syncStoredAccounts(emptyList(), null, snapshot(userId = " "), 1))
        val (inserted, key) = SessionLogic.syncStoredAccounts(emptyList(), null, snapshot(), 5)!!
        assertEquals("https://abs.example.org|u1", key)
        assertEquals(1, inserted.size)
        assertNull(inserted[0].refreshToken)
        assertNull(inserted[0].userType)
        assertEquals("lib", inserted[0].ebooksLibraryId)

        val existing = account(key).apply { token = "old" }
        val (updated, _) = SessionLogic.syncStoredAccounts(listOf(existing), key, snapshot(), 9)!!
        assertEquals("tok", updated.single().token)
        assertEquals("old", existing.token) // Eingabe bleibt unverändert.

        // Legacy-Eintrag ohne User-ID wird umbenannt statt dupliziert.
        val legacy = account("legacy", userId = "")
        val (migrated, newKey) = SessionLogic.syncStoredAccounts(listOf(legacy), "legacy", snapshot(), 9)!!
        assertEquals(1, migrated.size)
        assertEquals(newKey, migrated.single().accountKey)
    }

    @Test
    fun upsertStoredAccountFromUserKeepsTokenWhenEmpty() {
        val key = "https://abs.example.org|u1"
        val (list, k) = SessionLogic.upsertStoredAccountFromUser(listOf(account(key).apply { token = "keep" }), user(token = "", access = null), "https://abs.example.org", 1)!!
        assertEquals(key, k)
        assertEquals("keep", list.single().token)
        val (list2, _) = SessionLogic.upsertStoredAccountFromUser(emptyList(), user(), "https://abs.example.org", 1)!!
        assertEquals("jwt", list2.single().token)
        assertEquals("r1", list2.single().refreshToken)
        assertNull(SessionLogic.upsertStoredAccountFromUser(emptyList(), user(id = " "), "https://x", 1))
    }

    @Test
    fun accountScopedKeys() {
        assertEquals(Keys.hasCachedLaunchArtifacts, SessionLogic.accountScopedKey(Keys.hasCachedLaunchArtifacts, null))
        assertEquals("${Keys.activeBooksLibraryIds}.k", SessionLogic.accountScopedKey(Keys.activeBooksLibraryIds, " k "))
    }

    private val libs = listOf(
        AbsLibrary("p2", "Pods", "podcast", 2),
        AbsLibrary("b2", "beta", "book", 1),
        AbsLibrary("b1", "Alpha", "book", 1),
        AbsLibrary("b0", "Zeta", "book", 0),
    )

    @Test
    fun librarySortingAndResolution() {
        assertEquals(listOf("b0", "b1", "b2"), SessionLogic.sortedBookLibraries(libs).map { it.id })
        assertEquals(listOf("p2"), SessionLogic.sortedPodcastLibraries(libs).map { it.id })
        assertEquals(SessionLogic.LibraryResolution.PreferenceNone, SessionLogic.resolveBooksLibrary(Keys.librarySelectionNone, null, libs))
        assertEquals("b2", (SessionLogic.resolveBooksLibrary("b2", null, libs) as SessionLogic.LibraryResolution.Select).library.id)
        // Unbekannte Präferenz → Server-Default → erste sortierte.
        assertEquals("b1", (SessionLogic.resolveBooksLibrary("gone", "b1", libs) as SessionLogic.LibraryResolution.Select).library.id)
        assertEquals("b0", (SessionLogic.resolveBooksLibrary("", "p2", libs) as SessionLogic.LibraryResolution.Select).library.id)
        assertEquals(SessionLogic.LibraryResolution.NoneAvailable, SessionLogic.resolveBooksLibrary("", null, libs.filter { it.isPodcastLibrary }))
        assertEquals("p2", (SessionLogic.resolvePodcastLibrary("", libs) as SessionLogic.LibraryResolution.Select).library.id)
        assertEquals(SessionLogic.LibraryResolution.NoneAvailable, SessionLogic.resolvePodcastLibrary("x", libs.filter { it.isBookLibrary }))
    }

    @Test
    fun activeIdReconciliation() {
        val valid = setOf("a", "b", "c")
        assertEquals(listOf("a", "b"), SessionLogic.normalizeActiveIds(listOf(" a", "b", "a", "")))
        assertNull(SessionLogic.reconcileActiveIds(listOf("a"), emptySet(), false, "a"))
        assertEquals(emptyList<String>(), SessionLogic.reconcileActiveIds(listOf("a"), valid, true, "a"))
        // Migration: leer → nur Primary.
        assertEquals(listOf("b"), SessionLogic.reconcileActiveIds(emptyList(), valid, false, "b"))
        // Ungültige raus, Primary vorne ergänzt.
        assertEquals(listOf("c", "a"), SessionLogic.reconcileActiveIds(listOf("x", "a"), valid, false, "c"))
        assertEquals(listOf("a", "c"), SessionLogic.reconcileActiveIds(listOf("a", "c"), valid, false, "c"))
    }

    @Test
    fun tabVisibility() {
        assertTrue(SessionLogic.cachedTabVisibility(null, null))
        assertFalse(SessionLogic.cachedTabVisibility(null, " ${Keys.librarySelectionNone} "))
        assertFalse(SessionLogic.cachedTabVisibility(false, "lib"))
        assertTrue(SessionLogic.tabVisibleFromLibraries(preferenceIsNone = false, hasLibrariesOfType = true))
        assertFalse(SessionLogic.tabVisibleFromLibraries(preferenceIsNone = true, hasLibrariesOfType = true))
        assertFalse(SessionLogic.tabVisibleFromLibraries(preferenceIsNone = false, hasLibrariesOfType = false))
    }
}
