package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsUser
import de.letzgo.abstand.data.ContinueRefreshAttemptResult
import de.letzgo.abstand.store.LocalLibraryStore

/**
 * iOS: `AppModel.MainTab` — Android hat keine Tab-Leiste: Home ist die einzige Wurzel, Search und
 * Settings sind gepushte Seiten (Symbole in der Home-Kopfzeile), Books und Podcasts die fixierte
 * Bibliotheksleiste auf Home. Ziele für [SessionStore.shellRouteRequests].
 */
enum class ShellRoute(val label: String) {
    home("Home"),
    settings("Settings"),
    search("Search"),
}

/**
 * Erweiterungspunkt für die übrigen Domänen-Stores (Home, Katalog, Podcasts, Player, Downloads,
 * Stats). iOS ruft diese Stellen direkt im `AppModel` auf; Android hält den [SessionStore] frei von
 * Katalog-/Home-Logik und meldet die Lebenszyklus-Punkte stattdessen an registrierte Teilnehmer
 * ([AppModel.register]). Alle Methoden haben No-op-Defaults — ein Store implementiert nur, was er braucht.
 *
 * Aufrufe kommen auf dem Main-Dispatcher; `suspend`-Varianten dürfen selbst auf IO wechseln.
 */
interface SessionParticipant {
    // MARK: - Cache-first-Kaltstart

    /** iOS: Beitrag zu `hasCachedBootstrapContent` (`startShelves`/`books`/`podcastEpisodes` nicht leer). */
    fun hasCachedBootstrapContent(): Boolean = false

    /** iOS: `hasCachedContinueInLocalStore` — Continue-Regal mit Inhalt im LocalStore. */
    suspend fun hasCachedContinueInLocalStore(store: LocalLibraryStore, booksLibraryId: String?): Boolean = false

    /**
     * iOS: `scheduleHomeLaunchRestoreFromLocalStore` / `restoreHomeLaunchStateFromLocalStore` — Regale,
     * Fortschritt, Bookmarks aus der lokalen DB rendern, **bevor** das Netz gefragt wird.
     */
    suspend fun restoreFromLocalStore(store: LocalLibraryStore, booksLibraryId: String?) {}

    /**
     * iOS: `loadStartDashboard(skipAuthorizeRefresh:force:)`. `null` = nicht zuständig (nur der
     * Home-Store liefert ein Ergebnis; ohne ihn prüft der Bootstrap die Verbindung per `/authorize`).
     */
    suspend fun loadStartDashboard(skipAuthorizeRefresh: Boolean, force: Boolean): ContinueRefreshAttemptResult? = null

    /**
     * iOS: `repairContinueListeningShelfFromLocalProgressOnly` + `syncContinueListeningShelvesWithProgress`,
     * dann `hasOpenProgressExpectingContinue() && !continueShelfHasVisibleItems()`.
     */
    fun continueShelfMissingOpenProgress(): Boolean = false

    /** iOS: `restoreLastPlayedOnLaunch` (Player). */
    suspend fun restoreLastPlayedOnLaunch() {}

    /** iOS: `scheduleDeferredWorkAfterConnect` — Katalog-Restore, Tab-Prewarm, Server-Reload. */
    fun onDeferredWorkAfterConnect() {}

    // MARK: - Session

    /** Account ist aktiv (Login, Wechsel, Kaltstart) — iOS: `loadDownloadedItemIdsForActiveAccount`, Progress-Keys laden. */
    fun onSessionActivated() {}

    /** iOS: `applyAuthorizeUser` → `applyUserProgress`/`applyUserBookmarks`. */
    fun onAuthorizeUser(user: AbsUser, persistToDisk: Boolean) {}

    /** Tokens rotiert (iOS: `player.adoptRefreshedTokens`). */
    fun onTokensRefreshed(accessToken: String, refreshToken: String) {}

    /** iOS: `clearInMemorySessionState` — eigenen In-Memory-Zustand verwerfen. */
    fun onSessionCleared(clearCredentials: Boolean) {}

    /** Vor einem Accountwechsel (iOS: `recordActivePlaybackProgressLocally`, `persistDownloads`). */
    suspend fun willSwitchAccount() {}

    /** iOS: `reloadAllViewsAfterAccountSwitch` (Settings/Kataloge/Home neu laden). */
    suspend fun reloadAfterAccountSwitch() {}

    // MARK: - Bibliotheken

    /**
     * Primary-Books-Bibliothek gesetzt (iOS: `selectBooksLibrary` — Filter zurücksetzen, Katalog + Home
     * aus LocalStore). [changed] = andere Bibliothek als zuvor.
     */
    fun onBooksLibrarySelected(library: AbsLibrary, changed: Boolean) {}

    /** iOS: `selectPodcastLibrary`. */
    fun onPodcastLibrarySelected(library: AbsLibrary, changed: Boolean) {}

    /** iOS: `clearBooksLibrarySelection` / „none“ aus Server-Abgleich. */
    fun onBooksLibraryCleared() {}

    /** iOS: `clearPodcastLibrarySelection` / `clearPodcastLibraryStateWithoutPersistingNone`. */
    fun onPodcastLibraryCleared() {}

    /** Katalog-Fokus gewechselt (iOS: `focusBooksLibrary` → `reloadLibrary(reset:)`). */
    fun onBooksLibraryFocused(library: AbsLibrary) {}

    fun onPodcastLibraryFocused(library: AbsLibrary) {}

    /** Aktive Bibliotheks-Mengen geändert (iOS: `loadStartDashboard(force: true)`). */
    fun onActiveLibrariesChanged() {}

    /** iOS: Ende von `resolveLibrariesAfterServerFetch` (`refreshStartSettingsCategoryListLabels`, Newest-Episodes). */
    fun onLibrariesResolved() {}

    /** iOS: `reloadSettingsTab(reloadCatalogs: true)` — Kataloge neu laden. */
    suspend fun reloadCatalogs() {}

    // MARK: - Offline

    /** iOS: `prepareForOfflineHomeMode` — Position lokal sichern, Session schließen, auf Downloads umschalten. */
    suspend fun prepareForOfflineHomeMode() {}

    /** iOS: Offline-Kaltstart `bootstrapLocalSessionOnly` (nur LocalStore + Downloads). */
    suspend fun bootstrapLocalSessionOnly() {}

    /** iOS: Ende von `scheduleOfflineModeTransition(entering: false)` (Sync + Reload). */
    suspend fun onOfflineHomeModeExited() {}
}
