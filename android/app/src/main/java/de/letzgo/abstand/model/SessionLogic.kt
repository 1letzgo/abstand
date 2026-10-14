package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsApiError
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsStoredAccount
import de.letzgo.abstand.data.AbsUser
import de.letzgo.abstand.data.ContinueRefreshAttemptResult
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.swiftTrim
import java.text.Collator
import java.util.Locale

/**
 * Reine Entscheidungslogik aus `AppModelSessionAuth.swift`/`AppModel.swift` (Bootstrap, Accounts,
 * Bibliothekswahl) — ohne Prefs/Netz, damit sie per JUnit prüfbar ist. [SessionStore] wendet die
 * Ergebnisse an.
 */
object SessionLogic {
    /** iOS: `isAuthHTTPStatus` — 401 kommt zentral als `.unauthorized`, 403 als `.httpStatus`. */
    fun isAuthHTTPStatus(error: Throwable?): Boolean = when (error) {
        null -> false
        is AbsApiError.Unauthorized -> true
        is AbsApiError.HttpStatus -> error.code == 401 || error.code == 403
        else -> false
    }

    /**
     * iOS: `needsAuthorizeFallbackForContinue` — nach fehlgeschlagenem Token-Continue `/authorize` nötig?
     * [hasCachedContent] = `hasCachedContinueInLocalStore() || hasCachedBootstrapContent`;
     * [continueShelfMissingOpenProgress] = offener Fortschritt, aber leeres Continue-Regal (nach Reparatur).
     */
    fun needsAuthorizeFallbackForContinue(
        result: ContinueRefreshAttemptResult,
        attemptedOnline: Boolean,
        hasCachedContent: () -> Boolean,
        continueShelfMissingOpenProgress: () -> Boolean,
    ): Boolean {
        if (isAuthHTTPStatus(result.error)) return true
        if (!attemptedOnline) return false
        if (!result.appliedOnline) return !hasCachedContent()
        return continueShelfMissingOpenProgress()
    }

    /** Gespeicherte Accounts + aktiver Key nach dem Laden (iOS: `bootstrapStoredAccountsState`). */
    data class StoredAccountsState(val accounts: List<AbsStoredAccount>, val activeKey: String?, val activeKeyChanged: Boolean)

    fun bootstrapStoredAccountsState(accounts: List<AbsStoredAccount>, storedActiveKey: String?): StoredAccountsState {
        var activeKey = storedActiveKey
        var changed = false
        if (activeKey == null && accounts.isNotEmpty()) {
            activeKey = accounts.first().accountKey
            changed = true
        }
        if (activeKey != null && accounts.none { it.accountKey == activeKey } && accounts.isNotEmpty()) {
            activeKey = accounts.first().accountKey
            changed = true
        }
        return StoredAccountsState(accounts, activeKey, changed)
    }

    /** iOS: `migrateLegacySingleAccountIntoStore` — alter Einzel-Login → Account-Liste. */
    fun migrateLegacySingleAccount(
        server: String?, token: String?, userId: String?, booksLibraryId: String?, podcastsLibraryId: String?, now: Long,
    ): AbsStoredAccount? {
        val s = server?.swiftTrim().orEmpty()
        val t = token?.swiftTrim().orEmpty()
        val u = userId?.swiftTrim().orEmpty()
        if (AbsApiClient.normalizeServerURL(s) == null || t.isEmpty() || u.isEmpty()) return null
        return AbsStoredAccount(
            accountKey = AbsStoredAccount.makeKey(s, u),
            serverURL = s,
            token = t,
            userId = u,
            username = "",
            userType = null,
            booksLibraryId = booksLibraryId,
            podcastsLibraryId = podcastsLibraryId,
            // iOS-Altlast: eBooks-Bibliothek = Books-Bibliothek.
            ebooksLibraryId = booksLibraryId,
            lastUsedAt = now,
        )
    }

    /**
     * iOS: `adoptRefreshedSessionTokens`-Guard — nur Tokens der eigenen Session übernehmen (nach Wechsel
     * A→B auf demselben Server darf ein alter Client von A nicht B überschreiben).
     */
    fun shouldAdoptRefreshedTokens(
        activeServerURL: String, refreshedServerURL: String, currentRefreshToken: String, previousRefreshToken: String, accessToken: String,
    ): Boolean {
        if (accessToken.isEmpty()) return false
        val active = AbsApiClient.normalizeServerURL(activeServerURL) ?: return false
        if (!active.equals(refreshedServerURL, ignoreCase = true)) return false
        val current = currentRefreshToken.swiftTrim()
        // Legacy-Session ohne Refresh-Token erneuert nie selbst — fremde Rotation ignorieren.
        return current.isNotEmpty() && current == previousRefreshToken
    }

    /** Momentaufnahme der Session für [syncStoredAccounts] (iOS: Felder von `AppModel`). */
    data class SessionSnapshot(
        val serverURL: String,
        val token: String,
        val refreshToken: String,
        val userId: String,
        val username: String,
        val userType: String,
        val booksLibraryId: String?,
        val podcastsLibraryId: String?,
        val activeBooksLibraryIds: List<String>,
        val activePodcastLibraryIds: List<String>,
    )

    /**
     * iOS: `syncStoredAccountFromSession(markActive:)` — Account-Liste mit der laufenden Session
     * abgleichen. `null`, wenn die Session unvollständig ist (keine URL/kein Token/keine User-ID).
     * Liefert neue Liste + Key des Session-Accounts.
     */
    fun syncStoredAccounts(
        accounts: List<AbsStoredAccount>, activeAccountKey: String?, s: SessionSnapshot, now: Long,
    ): Pair<List<AbsStoredAccount>, String>? {
        if (AbsApiClient.normalizeServerURL(s.serverURL) == null || s.token.isEmpty()) return null
        val userId = s.userId.swiftTrim()
        if (userId.isEmpty()) return null
        val key = AbsStoredAccount.makeKey(s.serverURL, userId)
        val list = accounts.map { it.copy() }.toMutableList()
        fun fill(a: AbsStoredAccount) {
            a.token = s.token
            a.refreshToken = s.refreshToken.ifEmpty { null }
            a.serverURL = s.serverURL
            a.userId = userId
            a.username = s.username
            a.userType = s.userType.ifEmpty { null }
            a.booksLibraryId = s.booksLibraryId
            a.podcastsLibraryId = s.podcastsLibraryId
            a.ebooksLibraryId = s.booksLibraryId
            a.activeBooksLibraryIds = s.activeBooksLibraryIds
            a.activePodcastLibraryIds = s.activePodcastLibraryIds
        }
        val idx = list.indexOfFirst { it.accountKey == key }
        val legacyIdx = activeAccountKey?.let { k -> list.indexOfFirst { it.accountKey == k } } ?: -1
        when {
            idx >= 0 -> fill(list[idx])
            legacyIdx >= 0 && list[legacyIdx].userId.swiftTrim().isEmpty() -> {
                // Migration: userId war beim ersten Speichern noch leer — Eintrag umbenennen.
                list[legacyIdx].accountKey = key
                fill(list[legacyIdx])
            }
            else -> list.add(
                AbsStoredAccount(
                    accountKey = key, serverURL = s.serverURL, token = s.token, refreshToken = s.refreshToken.ifEmpty { null },
                    userId = userId, username = s.username, userType = s.userType.ifEmpty { null },
                    booksLibraryId = s.booksLibraryId, podcastsLibraryId = s.podcastsLibraryId, ebooksLibraryId = s.booksLibraryId,
                    activeBooksLibraryIds = s.activeBooksLibraryIds, activePodcastLibraryIds = s.activePodcastLibraryIds,
                    lastUsedAt = now,
                ),
            )
        }
        return list to key
    }

    /** iOS: `upsertStoredAccountFromUser` — Account aus Login-Antwort anlegen/aktualisieren. */
    fun upsertStoredAccountFromUser(accounts: List<AbsStoredAccount>, user: AbsUser, serverURL: String, now: Long): Pair<List<AbsStoredAccount>, String>? {
        val userId = user.id.swiftTrim()
        if (userId.isEmpty()) return null
        val key = AbsStoredAccount.makeKey(serverURL, userId)
        val list = accounts.map { it.copy() }.toMutableList()
        val idx = list.indexOfFirst { it.accountKey == key }
        if (idx >= 0) {
            val a = list[idx]
            // Leeres Token (Server liefert Legacy-Feld nicht mehr) darf gespeichertes Token nicht überschreiben.
            if (user.effectiveBearerToken.isNotEmpty()) a.token = user.effectiveBearerToken
            a.refreshToken = user.refreshToken
            a.serverURL = serverURL
            a.userId = userId
            a.username = user.username
            a.userType = user.type
        } else {
            list.add(
                AbsStoredAccount(
                    accountKey = key, serverURL = serverURL, token = user.effectiveBearerToken, refreshToken = user.refreshToken,
                    userId = userId, username = user.username, userType = user.type,
                    booksLibraryId = null, podcastsLibraryId = null, ebooksLibraryId = null, lastUsedAt = now,
                ),
            )
        }
        return list to key
    }

    /** iOS: `"\(Keys.x).\(activeAccountKey)"` — account-gebundene Pref-Keys. */
    fun accountScopedKey(base: String, activeAccountKey: String?): String {
        val k = activeAccountKey?.swiftTrim().orEmpty()
        return if (k.isEmpty()) base else "$base.$k"
    }

    // MARK: - Bibliotheken

    private val nameCollator: Collator get() = Collator.getInstance(Locale.getDefault()).apply { strength = Collator.SECONDARY }

    /** iOS: `sortedBookLibraries` — Server-Reihenfolge, dann Name. */
    fun sortedBookLibraries(libraries: List<AbsLibrary>): List<AbsLibrary> = sortLibraries(libraries.filter { it.isBookLibrary })

    fun sortedPodcastLibraries(libraries: List<AbsLibrary>): List<AbsLibrary> = sortLibraries(libraries.filter { it.isPodcastLibrary })

    private fun sortLibraries(list: List<AbsLibrary>): List<AbsLibrary> {
        val c = nameCollator
        return list.sortedWith { a, b ->
            if (a.displayOrderOrZero != b.displayOrderOrZero) a.displayOrderOrZero.compareTo(b.displayOrderOrZero) else c.compare(a.name, b.name)
        }
    }

    /** Ergebnis von [resolveBooksLibrary]/[resolvePodcastLibrary] (iOS: Zweige in `resolveLibrariesAfterServerFetch`). */
    sealed interface LibraryResolution {
        /** Nutzer hat bewusst „keine Bibliothek“ gewählt. */
        data object PreferenceNone : LibraryResolution
        data class Select(val library: AbsLibrary) : LibraryResolution
        /** Server hat keine passende Bibliothek — „none“ persistieren, Tab ausblenden. */
        data object NoneAvailable : LibraryResolution
    }

    fun resolveBooksLibrary(preference: String, userDefaultLibraryId: String?, libraries: List<AbsLibrary>): LibraryResolution {
        if (preference == Keys.librarySelectionNone) return LibraryResolution.PreferenceNone
        if (preference.isNotEmpty()) libraries.firstOrNull { it.id == preference && it.isBookLibrary }?.let { return LibraryResolution.Select(it) }
        if (userDefaultLibraryId != null) {
            libraries.firstOrNull { it.id == userDefaultLibraryId && it.isBookLibrary }?.let { return LibraryResolution.Select(it) }
        }
        return sortedBookLibraries(libraries).firstOrNull()?.let { LibraryResolution.Select(it) } ?: LibraryResolution.NoneAvailable
    }

    fun resolvePodcastLibrary(preference: String, libraries: List<AbsLibrary>): LibraryResolution {
        if (preference == Keys.librarySelectionNone) return LibraryResolution.PreferenceNone
        if (preference.isNotEmpty()) libraries.firstOrNull { it.id == preference && it.isPodcastLibrary }?.let { return LibraryResolution.Select(it) }
        return sortedPodcastLibraries(libraries).firstOrNull()?.let { LibraryResolution.Select(it) } ?: LibraryResolution.NoneAvailable
    }

    /** iOS: `applyActive*LibraryIds` — getrimmt, leer verworfen, Duplikate entfernt (Reihenfolge bleibt). */
    fun normalizeActiveIds(ids: List<String>): List<String> {
        val out = ArrayList<String>()
        for (id in ids.map { it.swiftTrim() }) if (id.isNotEmpty() && id !in out) out.add(id)
        return out
    }

    /**
     * iOS: `reconcileActiveLibraryIdsWithServerLibraries` (je Medientyp). `null` = nichts zu tun
     * (Server kennt keine Bibliothek dieses Typs).
     */
    fun reconcileActiveIds(current: List<String>, validIds: Set<String>, preferenceIsNone: Boolean, primaryId: String?): List<String>? {
        if (validIds.isEmpty()) return null
        var ids = current.filter { it in validIds }
        if (preferenceIsNone) {
            ids = emptyList()
        } else if (ids.isEmpty()) {
            // Migration: nur Primary aktiv, alle übrigen default inaktiv.
            if (primaryId != null && primaryId in validIds) ids = listOf(primaryId)
        } else if (primaryId != null && primaryId in validIds && primaryId !in ids) {
            ids = listOf(primaryId) + ids
        }
        return ids
    }

    /** iOS: `sync*TabVisibilityFromLibraries` — Tab sichtbar, wenn nicht „none“ und Bibliotheken existieren. */
    fun tabVisibleFromLibraries(preferenceIsNone: Boolean, hasLibrariesOfType: Boolean): Boolean = !preferenceIsNone && hasLibrariesOfType

    /** iOS: `loadShow*TabCached` — gecachter Wert, sonst aus der Bibliotheks-Präferenz. */
    fun cachedTabVisibility(cached: Boolean?, libraryPreference: String?): Boolean =
        cached ?: (libraryPreference?.swiftTrim().orEmpty() != Keys.librarySelectionNone)
}
