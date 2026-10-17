package de.letzgo.abstand.model

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.util.Log
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsApiError
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsLoginResponse
import de.letzgo.abstand.data.AbsServerSettings
import de.letzgo.abstand.data.AbsStoredAccount
import de.letzgo.abstand.data.AbsStoredAccountsPersistence
import de.letzgo.abstand.data.AbsUser
import de.letzgo.abstand.data.AbstandErrorFilter
import de.letzgo.abstand.data.ApiEvents
import de.letzgo.abstand.data.ContinueRefreshAttemptResult
import de.letzgo.abstand.data.CustomHeadersStore
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Net
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.store.AccountCacheDirectory
import de.letzgo.abstand.store.ActiveLibraryIdsStore
import de.letzgo.abstand.store.CoverImageCache
import de.letzgo.abstand.store.EbookLocalStore
import de.letzgo.abstand.store.LocalLibraryStore
import de.letzgo.abstand.store.LocalLibraryStoreManager
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Session-/Auth-/Bibliotheks-Kern von `AppModel` (iOS: `AppModelSessionAuth.swift` + Bootstrap-,
 * Login-, Account- und Bibliotheks-Teile aus `AppModel.swift`). Zustand als `StateFlow`s, Methoden
 * mit iOS-Namen. Läuft auf dem Main-Dispatcher (iOS: `@MainActor`).
 *
 * Kaltstart cache-first: [start] rendert aus dem LocalStore, [bootstrapFromStoredCredentials] fragt
 * danach das Netz (`/authorize` nur als Fallback bzw. für User-Typ/Progress). Katalog/Home/Player
 * hängen sich über [SessionParticipant] ein.
 */
class SessionStore internal constructor(
    private val appContext: Context,
    private val scope: CoroutineScope,
    private val participants: CopyOnWriteArrayList<SessionParticipant>,
) {
    // MARK: - Credentials

    private val _serverURL = MutableStateFlow(Prefs.string(Keys.server) ?: "")
    /** Server-URL wie eingegeben (iOS: `serverURL`); normalisiert über [AbsApiClient.normalizeServerURL]. */
    val serverURL: StateFlow<String> = _serverURL.asStateFlow()

    /** Bearer der aktiven Session (iOS: `token`) — bewusst kein Flow; Änderungen zählen [tokenRevision] hoch. */
    @Volatile var token: String = Prefs.string(Keys.token) ?: ""
        private set

    /** Refresh-Token; leer = Legacy-Session ohne Ablauf/Refresh. */
    @Volatile var refreshToken: String = Prefs.string(Keys.refreshToken) ?: ""
        private set

    private val _tokenRevision = MutableStateFlow(0)
    /** iOS: `objectWillChange.send()` nach Token-Rotation — Cover-/Asset-Views neu binden. */
    val tokenRevision: StateFlow<Int> = _tokenRevision.asStateFlow()

    private val _isLoggedIn = MutableStateFlow(computeIsLoggedIn())
    /** iOS: `isLoggedIn` (gültige Server-URL + Token). */
    val isLoggedIn: StateFlow<Boolean> = _isLoggedIn.asStateFlow()

    /** iOS: `client` — API-Client der aktiven Session (`null` offline/vor Login). */
    @Volatile var client: AbsApiClient? = null
        private set

    // MARK: - Benutzer

    /** iOS: `sessionUserId` (kein `@Published`). */
    var sessionUserId: String = ""
        private set
    private val _sessionUsername = MutableStateFlow("")
    val sessionUsername: StateFlow<String> = _sessionUsername.asStateFlow()
    private val _sessionUserType = MutableStateFlow("")
    val sessionUserType: StateFlow<String> = _sessionUserType.asStateFlow()
    private val _isServerAdmin = MutableStateFlow(false)
    val isServerAdmin: StateFlow<Boolean> = _isServerAdmin.asStateFlow()
    private val _isServerRoot = MutableStateFlow(false)
    val isServerRoot: StateFlow<Boolean> = _isServerRoot.asStateFlow()
    private val _serverSettings = MutableStateFlow<AbsServerSettings?>(null)
    val serverSettings: StateFlow<AbsServerSettings?> = _serverSettings.asStateFlow()

    /** iOS: `isSessionGuest`. */
    val isSessionGuest: Boolean get() = _sessionUserType.value.swiftTrim().lowercase() == "guest"

    /** iOS: `sessionAccountTypeLabel`. */
    val sessionAccountTypeLabel: String
        get() {
            val t = _sessionUserType.value.swiftTrim().lowercase()
            return if (t.isEmpty()) "User" else t.replaceFirstChar { it.uppercase() }
        }

    // MARK: - Accounts

    private val _storedAccounts = MutableStateFlow<List<AbsStoredAccount>>(emptyList())
    /** iOS: `storedAccounts` — gespeicherte Accounts für schnellen Wechsel. */
    val storedAccounts: StateFlow<List<AbsStoredAccount>> = _storedAccounts.asStateFlow()
    private val _activeAccountKey = MutableStateFlow<String?>(null)
    val activeAccountKey: StateFlow<String?> = _activeAccountKey.asStateFlow()
    private val _isSwitchingAccount = MutableStateFlow(false)
    val isSwitchingAccount: StateFlow<Boolean> = _isSwitchingAccount.asStateFlow()
    private val _accountSessionEpoch = MutableStateFlow(0L)
    /** iOS: `accountSessionEpoch` — erhöht nach Account-Wechsel; Tab-Views/Toolbars invalidieren. */
    val accountSessionEpoch: StateFlow<Long> = _accountSessionEpoch.asStateFlow()
    private val _coverImageCacheRevision = MutableStateFlow(0)
    /** iOS: `coverImageCacheRevision` — erzwingt neue Cover-Keys nach Cache-Leeren/Accountwechsel. */
    val coverImageCacheRevision: StateFlow<Int> = _coverImageCacheRevision.asStateFlow()

    // MARK: - Bibliotheken

    private val _libraries = MutableStateFlow<List<AbsLibrary>>(emptyList())
    /** Alle Bibliotheken vom Server (Bücher und Podcasts). */
    val libraries: StateFlow<List<AbsLibrary>> = _libraries.asStateFlow()
    private val _selectedBooksLibrary = MutableStateFlow<AbsLibrary?>(null)
    /** Primary Books-Library (Settings / Persistenz). */
    val selectedBooksLibrary: StateFlow<AbsLibrary?> = _selectedBooksLibrary.asStateFlow()
    private val _selectedPodcastLibrary = MutableStateFlow<AbsLibrary?>(null)
    val selectedPodcastLibrary: StateFlow<AbsLibrary?> = _selectedPodcastLibrary.asStateFlow()
    private val _focusedBooksLibrary = MutableStateFlow<AbsLibrary?>(null)
    /** Temporärer Katalog-Fokus Books (Session; schreibt Primary nicht). */
    val focusedBooksLibrary: StateFlow<AbsLibrary?> = _focusedBooksLibrary.asStateFlow()
    private val _focusedPodcastLibrary = MutableStateFlow<AbsLibrary?>(null)
    val focusedPodcastLibrary: StateFlow<AbsLibrary?> = _focusedPodcastLibrary.asStateFlow()
    private val _activeBooksLibraryIds = MutableStateFlow<List<String>>(emptyList())
    /** Aktive Books-Library-IDs (inkl. Primary), account-gebunden. */
    val activeBooksLibraryIds: StateFlow<List<String>> = _activeBooksLibraryIds.asStateFlow()
    private val _activePodcastLibraryIds = MutableStateFlow<List<String>>(emptyList())
    val activePodcastLibraryIds: StateFlow<List<String>> = _activePodcastLibraryIds.asStateFlow()

    private val _showAudiobooksTab = MutableStateFlow(
        SessionLogic.cachedTabVisibility(cachedBool(Keys.showAudiobooksTab), Prefs.string(Keys.booksLibrary)),
    )
    /** Books-Tab — aus gecachter Präferenz (nicht erst nach `libraries`-Fetch). */
    val showAudiobooksTab: StateFlow<Boolean> = _showAudiobooksTab.asStateFlow()
    private val _showPodcastsTab = MutableStateFlow(
        SessionLogic.cachedTabVisibility(cachedBool(Keys.showPodcastsTab), Prefs.string(Keys.podcastsLibrary)),
    )
    val showPodcastsTab: StateFlow<Boolean> = _showPodcastsTab.asStateFlow()

    private val _mainTab = MutableStateFlow(MainTab.start)
    /** iOS: `mainTab`. */
    val mainTab: StateFlow<MainTab> = _mainTab.asStateFlow()

    // MARK: - Verbindung / Offline

    private val _offlineHomeMode = MutableStateFlow(Prefs.bool(Keys.offlineHomeMode))
    /** Manueller Offline-Modus (persistiert): Tab-Struktur bleibt, Inhalte auf Downloads beschränkt. */
    val offlineHomeMode: StateFlow<Boolean> = _offlineHomeMode.asStateFlow()
    private val _offlineHomeModeAuto = MutableStateFlow(false)
    /** Nach fehlgeschlagenem Start-Bootstrap: gleiche Oberfläche wie manuell, ohne Persistenz. */
    val offlineHomeModeAuto: StateFlow<Boolean> = _offlineHomeModeAuto.asStateFlow()
    /** iOS: `offlineHomeUIActive`. */
    val offlineHomeUIActive: Boolean get() = _offlineHomeMode.value || _offlineHomeModeAuto.value
    /** iOS: `mayUseServerNetwork`. */
    val mayUseServerNetwork: Boolean get() = !offlineHomeUIActive

    private val _isNetworkReachable = MutableStateFlow(true)
    val isNetworkReachable: StateFlow<Boolean> = _isNetworkReachable.asStateFlow()
    private val _isServerReachable = MutableStateFlow(false)
    val isServerReachable: StateFlow<Boolean> = _isServerReachable.asStateFlow()
    private val _isServerConnectionProbeInProgress = MutableStateFlow(false)
    val isServerConnectionProbeInProgress: StateFlow<Boolean> = _isServerConnectionProbeInProgress.asStateFlow()
    private val _isAppBootstrapInProgress = MutableStateFlow(false)
    /** App-Start: Verbindungs-Overlay bis Home/Player bereit (nur ohne Cache). */
    val isAppBootstrapInProgress: StateFlow<Boolean> = _isAppBootstrapInProgress.asStateFlow()
    private val _isDeferredBootstrapNetworkRefreshInProgress = MutableStateFlow(false)
    val isDeferredBootstrapNetworkRefreshInProgress: StateFlow<Boolean> = _isDeferredBootstrapNetworkRefreshInProgress.asStateFlow()
    private val _isHomeContinueRestoreInProgress = MutableStateFlow(false)
    val isHomeContinueRestoreInProgress: StateFlow<Boolean> = _isHomeContinueRestoreInProgress.asStateFlow()
    private val _sessionRejected = MutableStateFlow(false)
    /** Letzter Request bekam 401 trotz Refresh (iOS loggt nur; Android markiert zusätzlich für die UI). */
    val sessionRejected: StateFlow<Boolean> = _sessionRejected.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    /** iOS: `errorMessage` (Root-Alert) — abgebrochene Requests werden gefiltert. */
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    // MARK: - Interne Steuerung

    /** Nutzer hat „Go offline“ während Bootstrap — laufenden Server-Sync abbrechen. */
    private var bootstrapSupersededByOffline = false
    /** Account-Wechsel: gestaffelte Katalog-Reloads überspringen (sofortiger Reload folgt). */
    private var suppressDeferredWorkAfterBootstrap = false
    private var authorizeApplyGeneration = 0
    private var librariesPersistGeneration = 0
    private var homeLaunchLocalRestoreTask: Job? = null
    private var storedCredentialsBootstrapTask: Job? = null
    private var deferredBootstrapNetworkTask: Job? = null
    private var deferredBootstrapAuthorizeTask: Job? = null
    private var deferredLibrariesFetchTask: Job? = null
    private var postLaunchDashboardTask: Job? = null
    private var modeTransitionTask: Job? = null
    private var started = false

    // MARK: - Start (iOS: Teil von `AppModel.init`)

    /**
     * Kaltstart-Verdrahtung: Accounts laden, `Net.activeBearer` setzen, Events abonnieren,
     * Home aus dem LocalStore wiederherstellen, Bootstrap anstoßen. Einmalig aus [AppModel.start].
     */
    internal fun start() {
        if (started) return
        started = true
        migrateLibraryKeysIfNeeded()
        Net.activeBearer = ::activeBearer
        scope.launch { ApiEvents.sessionUnauthorized.collect { handleSessionUnauthorized() } }
        scope.launch {
            ApiEvents.tokensRefreshed.collect { e ->
                adoptRefreshedSessionTokens(e.serverURL, e.accessToken, e.refreshToken, e.previousRefreshToken)
            }
        }
        watchNetworkReachability()

        val accountBootstrap = bootstrapStoredAccountsState()
        _storedAccounts.value = accountBootstrap.accounts
        _activeAccountKey.value = accountBootstrap.activeKey
        hydrateSessionUserIdForLocalStore()
        loadActiveLibraryIdsFromPrefs()
        if (_isLoggedIn.value) {
            cacheAccountDir()?.let { EbookLocalStore.updateActiveSession(it, sessionUserId.ifEmpty { null }) }
            participants.forEach { it.onSessionActivated() }
        }
        scheduleHomeLaunchRestoreFromLocalStore()
        if (offlineHomeUIActive) {
            _mainTab.value = MainTab.start
            scope.launch { loadStartDashboard(skipAuthorizeRefresh = false, force = true) }
        } else if (_isLoggedIn.value) {
            // Overlay bis Home/Player bereit; Bootstrap sofort (nicht auf die erste Komposition warten).
            _isAppBootstrapInProgress.value = true
            scheduleBootstrapFromStoredCredentials()
        }
    }

    /** Origin + Bearer für den Net-Interceptor (Cover, Media3, Downloads ohne eigenen Header). */
    private fun activeBearer(): Pair<String, String>? {
        val t = token
        if (t.isEmpty()) return null
        val origin = CustomHeadersStore.originKeyForServer(_serverURL.value) ?: return null
        return origin to t
    }

    private fun computeIsLoggedIn(): Boolean = AbsApiClient.normalizeServerURL(_serverURL.value) != null && token.isNotEmpty()

    private fun refreshLoggedIn() {
        _isLoggedIn.value = computeIsLoggedIn()
    }

    private fun setCredentials(server: String, newToken: String, newRefresh: String) {
        _serverURL.value = server
        token = newToken
        refreshToken = newRefresh
        Prefs.setString(Keys.server, server.ifEmpty { null })
        Prefs.setString(Keys.token, newToken.ifEmpty { null })
        Prefs.setString(Keys.refreshToken, newRefresh)
        refreshLoggedIn()
    }

    private fun cachedBool(key: String): Boolean? = if (Prefs.has(key)) Prefs.bool(key) else null

    /** Migriert `abstand_library_id` → `abstand_books_library_id` und entfernt die alte eBooks-Bibliothek. */
    private fun migrateLibraryKeysIfNeeded() {
        if (Prefs.string(Keys.booksLibrary) == null) {
            Prefs.string(Keys.library)?.swiftTrim()?.takeIf { it.isNotEmpty() }?.let { Prefs.setString(Keys.booksLibrary, it) }
        }
        Prefs.remove(Keys.ebooksLibrary)
    }

    // MARK: - Pfade / LocalStore

    /** iOS: `resolvedLocalStoreUserId` — Session-User, sonst User des aktiven gespeicherten Accounts. */
    fun resolvedLocalStoreUserId(): String? {
        sessionUserId.swiftTrim().takeIf { it.isNotEmpty() }?.let { return it }
        val key = _activeAccountKey.value ?: return null
        return _storedAccounts.value.firstOrNull { it.accountKey == key }?.userId?.swiftTrim()?.ifEmpty { null }
    }

    /** iOS: `hydrateSessionUserIdForLocalStore` — vor dem ersten LocalStore-Zugriff (sonst falsches Verzeichnis). */
    private fun hydrateSessionUserIdForLocalStore() {
        if (sessionUserId.swiftTrim().isNotEmpty()) return
        val fromPrefs = Prefs.string(Keys.sessionUserId)?.swiftTrim().orEmpty()
        sessionUserId = fromPrefs.ifEmpty { resolvedLocalStoreUserId() ?: "" }
    }

    /** iOS: `cacheAccountURL()` / `coverImageCacheAccountDirectory()` — `null` ohne Login. */
    fun cacheAccountDir(): File? {
        val u = AbsApiClient.normalizeServerURL(_serverURL.value) ?: return null
        if (token.isEmpty()) return null
        return AccountCacheDirectory.accountDir(u, resolvedLocalStoreUserId())
    }

    /** iOS: `coverImageCacheByteCount()`. */
    fun coverImageCacheByteCount(): Long = cacheAccountDir()?.let { CoverImageCache.totalByteCount(it) } ?: 0L

    /** iOS: `clearCoverImageCache()` — Cover- und Tint-Caches des Kontos leeren, Revision erhöhen. */
    fun clearCoverImageCache() {
        val account = cacheAccountDir() ?: return
        CoverImageCache.clearAll(appContext, account)
        de.letzgo.abstand.logic.CoverAverageRgbCache.continueHero.clearAll(account)
        de.letzgo.abstand.logic.CoverAverageRgbCache.detailCover.clearAll(account)
        _coverImageCacheRevision.value += 1
    }

    /** iOS: `currentLocalLibraryStore()` — Room-DB des aktiven Accounts, `null` vor Login. */
    fun currentLocalLibraryStore(): LocalLibraryStore? {
        if (!computeIsLoggedIn()) return null
        return LocalLibraryStoreManager.store(_serverURL.value, resolvedLocalStoreUserId())
    }

    /** iOS: `restoreServerClientIfNeeded`. */
    fun restoreServerClientIfNeeded() {
        if (client != null) return
        val url = AbsApiClient.normalizeServerURL(_serverURL.value) ?: return
        if (token.isEmpty()) return
        client = AbsApiClient(url, token, refreshToken.ifEmpty { null })
    }

    /** iOS: `clientForOfflineLocalPlayback` — Client nur für lokale Wiedergabe (kein Authorize). */
    fun clientForOfflineLocalPlayback(): AbsApiClient? {
        client?.let { return it }
        val url = AbsApiClient.normalizeServerURL(_serverURL.value) ?: return null
        if (token.isEmpty()) return null
        return AbsApiClient(url, token, refreshToken.ifEmpty { null })
    }

    // MARK: - Fehler

    fun setErrorMessage(message: String?) {
        _errorMessage.value = message?.takeUnless { AbstandErrorFilter.isBenignCancellationMessage(it) }
    }

    /** iOS: `publishErrorUnlessBenignCancellation` — Kaltstart mit Cache: Netz-Hiccups nicht melden. */
    fun publishErrorUnlessBenignCancellation(error: Throwable, forceDisplay: Boolean = false) {
        if (AbstandErrorFilter.isBenignCancellation(error)) return
        if (!forceDisplay && hasCachedBootstrapContent() && AbstandErrorFilter.isTransientNetworkError(error)) return
        setErrorMessage(error.message ?: error.toString())
    }

    private fun handleSessionUnauthorized() {
        // iOS: nur prominent loggen; der Client wird beim nächsten Request neu aufgebaut.
        Log.w(TAG, "401 from server — token rejected")
        _sessionRejected.value = true
    }

    // MARK: - Bootstrap (iOS: AppModelSessionAuth.swift)

    /** Bootstrap direkt nach Start — nicht auf die erste Komposition warten. */
    fun scheduleBootstrapFromStoredCredentials() {
        storedCredentialsBootstrapTask?.cancel()
        storedCredentialsBootstrapTask = scope.launch { bootstrapFromStoredCredentials() }
    }

    suspend fun bootstrapFromStoredCredentials() {
        if (!computeIsLoggedIn()) return
        bootstrapSupersededByOffline = false
        // Store für den aktiven Account öffnen/wechseln; Schreibtest im Hintergrund.
        currentLocalLibraryStore()?.let { store -> scope.launch(Dispatchers.IO) { store.markOpened() } }

        if (offlineHomeUIActive) {
            _isAppBootstrapInProgress.value = false
            bootstrapLocalSessionOnly()
            scheduleDeferredWorkAfterConnect()
            return
        }

        // Continue-Cache aus dem Start fertig anwenden, bevor Cache-vs-Network entschieden wird.
        waitForHomeContinueLaunchRestoreIfNeeded()
        if (bootstrapSupersededByOffline) return

        val hadCachedBootstrap = hasCachedBootstrapContent()
        if (!hadCachedBootstrap) _isAppBootstrapInProgress.value = true
        try {
            restoreServerClientIfNeeded()
            if (hadCachedBootstrap) {
                // LocalStore: Netzwerk parallel; Home ist bereits bedienbar.
                deferredBootstrapNetworkTask?.cancel()
                deferredBootstrapNetworkTask = scope.launch { performDeferredBootstrapNetworkRefresh() }
                finishLaunchPresentationAfterBootstrap()
                return
            }
            // Ohne Cache: Overlay bis Continue online (ggf. nach Authorize-Fallback).
            performDeferredBootstrapNetworkRefresh()
            if (bootstrapSupersededByOffline || offlineHomeUIActive) return
            finishLaunchPresentationAfterBootstrap()
        } finally {
            if (!bootstrapSupersededByOffline) {
                _isAppBootstrapInProgress.value = false
                flushTabVisibilityAfterBootstrap()
            }
            bootstrapSupersededByOffline = false
        }
    }

    /** Home-Refresh und Player-Restore nach Bootstrap — blockiert den Kaltstart nur ohne Cache. */
    private suspend fun finishLaunchPresentationAfterBootstrap() {
        if (bootstrapSupersededByOffline || offlineHomeUIActive) return
        waitForHomeContinueLaunchRestoreIfNeeded()
        if (bootstrapSupersededByOffline || offlineHomeUIActive) return
        val hadCachedHome = participants.any { it.hasCachedBootstrapContent() }
        coroutineScope {
            launch { loadStartDashboard(skipAuthorizeRefresh = true, force = !hadCachedHome) }
            launch { participants.forEach { it.restoreLastPlayedOnLaunch() } }
        }
        if (hadCachedHome) {
            // Server-Abgleich im Hintergrund — local-first.
            postLaunchDashboardTask?.cancel()
            postLaunchDashboardTask = scope.launch {
                delay(400)
                if (offlineHomeUIActive || bootstrapSupersededByOffline) return@launch
                loadStartDashboard(skipAuthorizeRefresh = true, force = true)
            }
        }
        scheduleDeferredWorkAfterConnect()
    }

    /** Katalog-Caches, Tab-Prewarm und Server-Reload — erst nach Connect, Home und Player. */
    private fun scheduleDeferredWorkAfterConnect() {
        if (suppressDeferredWorkAfterBootstrap) return
        participants.forEach { it.onDeferredWorkAfterConnect() }
    }

    /** iOS: `loadStartDashboard` — an den zuständigen Teilnehmer (Home) delegiert. */
    suspend fun loadStartDashboard(skipAuthorizeRefresh: Boolean, force: Boolean): ContinueRefreshAttemptResult {
        for (p in participants) p.loadStartDashboard(skipAuthorizeRefresh, force)?.let { return it }
        return ContinueRefreshAttemptResult()
    }

    /** iOS: `hasCachedBootstrapContent` — Teilnehmer oder persistiertes Kaltstart-Signal. */
    fun hasCachedBootstrapContent(): Boolean {
        if (participants.any { it.hasCachedBootstrapContent() }) return true
        return hasCachedLaunchArtifactsFlag()
    }

    /** iOS: `cachedLaunchArtifactsDefaultsKey`. */
    fun cachedLaunchArtifactsPrefsKey(): String = SessionLogic.accountScopedKey(Keys.hasCachedLaunchArtifacts, _activeAccountKey.value)

    /** Persistiertes Kaltstart-Signal statt DB-Fetch (Room erlaubt keine Main-Thread-Queries). */
    private fun hasCachedLaunchArtifactsFlag(): Boolean {
        if (cacheAccountDir() == null) return false
        val key = cachedLaunchArtifactsPrefsKey()
        return Prefs.has(key) && Prefs.bool(key)
    }

    /** Flag nachziehen — nach Persists und nach dem Restore, der den echten Zustand kennt. */
    fun setHasCachedLaunchArtifacts(available: Boolean) {
        if (cacheAccountDir() == null) return
        Prefs.setBool(cachedLaunchArtifactsPrefsKey(), available)
    }

    /**
     * iOS: `scheduleHomeLaunchRestoreFromLocalStore` — Bibliothekswahl synchron (billig, nur Prefs),
     * Bibliotheksliste + Home/Progress aus der Room-DB off-main.
     */
    private fun scheduleHomeLaunchRestoreFromLocalStore(libraryIdOverride: String? = null) {
        if (cacheAccountDir() == null) return
        val libId = libraryIdOverride?.swiftTrim() ?: Prefs.string(Keys.booksLibrary)?.swiftTrim().orEmpty()
        if (libId == Keys.librarySelectionNone) {
            _selectedBooksLibrary.value = null
        } else if (libId.isNotEmpty() && _selectedBooksLibrary.value?.id != libId) {
            _selectedBooksLibrary.value = _libraries.value.firstOrNull { it.id == libId && it.isBookLibrary }
                ?: AbsLibrary(id = libId, name = "Books", mediaType = "book")
        }
        val podId = Prefs.string(Keys.podcastsLibrary)?.swiftTrim().orEmpty()
        if (podId.isNotEmpty() && podId != Keys.librarySelectionNone && _selectedPodcastLibrary.value?.id != podId) {
            _selectedPodcastLibrary.value = _libraries.value.firstOrNull { it.id == podId && it.isPodcastLibrary }
                ?: AbsLibrary(id = podId, name = "Podcasts", mediaType = "podcast")
        }
        val store = currentLocalLibraryStore() ?: return
        homeLaunchLocalRestoreTask?.cancel()
        _isHomeContinueRestoreInProgress.value = true
        val booksLibraryId = _selectedBooksLibrary.value?.id
        homeLaunchLocalRestoreTask = scope.launch {
            try {
                restoreLibrariesFromLocalStore(store)
                participants.forEach { it.restoreFromLocalStore(store, booksLibraryId) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Home launch restore failed: ${e.message}")
            } finally {
                _isHomeContinueRestoreInProgress.value = false
            }
        }
    }

    private suspend fun waitForHomeContinueLaunchRestoreIfNeeded() {
        homeLaunchLocalRestoreTask?.join()
    }

    /**
     * Kaltstart: Bibliotheksliste aus der lokalen Server-Kopie. Nicht überschreiben, wenn bereits eine
     * Liste im Speicher ist (sonst spielt ein Restore direkt nach `applyLibrariesFromServer` einen alten
     * Snapshot zurück).
     */
    private suspend fun restoreLibrariesFromLocalStore(store: LocalLibraryStore): Boolean {
        if (_libraries.value.isNotEmpty()) return true
        val cached = store.fetchLibraries()?.takeIf { it.isNotEmpty() } ?: return false
        if (_libraries.value.isNotEmpty()) return true
        _libraries.value = cached
        enrichSelectedLibrariesFromCachedList()
        return true
    }

    /**
     * Lazy-Bootstrap: Continue ohne `/authorize`; Authorize nur bei fehlgeschlagenem Continue-Refresh.
     * Nach erfolgreichem Continue: `/authorize` deferred für User-Type/Admin-Status/Progress.
     */
    private suspend fun performDeferredBootstrapNetworkRefresh() {
        _isDeferredBootstrapNetworkRefreshInProgress.value = true
        try {
            if (bootstrapSupersededByOffline || offlineHomeUIActive) return
            if (!computeIsLoggedIn()) return
            restoreServerClientIfNeeded()
            if (client == null) return
            _offlineHomeModeAuto.value = false

            val forceContinue = !hasCachedBootstrapContent()
            var result = loadStartDashboard(skipAuthorizeRefresh = true, force = forceContinue)
            val needsFallback = SessionLogic.needsAuthorizeFallbackForContinue(
                result, result.attemptedNetwork,
                hasCachedContent = { hasCachedBootstrapContent() },
                continueShelfMissingOpenProgress = { participants.any { it.continueShelfMissingOpenProgress() } },
            )
            if (needsFallback) {
                refreshProgressFromServer()
                if (bootstrapSupersededByOffline || offlineHomeUIActive) return
                result = loadStartDashboard(skipAuthorizeRefresh = true, force = true)
                val error = result.error
                if (!result.appliedOnline && error != null && !hasCachedBootstrapContent()) {
                    publishErrorUnlessBenignCancellation(error)
                    if (!SessionLogic.isAuthHTTPStatus(error)) {
                        _isServerReachable.value = false
                        _offlineHomeModeAuto.value = true
                        _mainTab.value = MainTab.start
                        prepareForOfflineHomeMode()
                        bootstrapLocalSessionOnly()
                    }
                    return
                }
            }
            if (bootstrapSupersededByOffline || offlineHomeUIActive) return

            if (!result.attemptedNetwork) {
                // `loadStartDashboard` hat keinen Request gestartet — Erreichbarkeit nicht annehmen, echter Probe-Call.
                probeServerConnection()
                if (!_isServerReachable.value) return
                scheduleDeferredLibrariesFetchFromServer()
                return
            }

            _isServerReachable.value = true
            deferredBootstrapAuthorizeTask?.cancel()
            deferredBootstrapAuthorizeTask = scope.launch {
                val c = client ?: return@launch
                val epoch = _accountSessionEpoch.value
                val generation = ++authorizeApplyGeneration
                try {
                    val auth = c.authorize()
                    if (bootstrapSupersededByOffline || offlineHomeUIActive || _accountSessionEpoch.value != epoch ||
                        authorizeApplyGeneration != generation
                    ) return@launch
                    applyAuthorizeSession(auth)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.w(TAG, "Deferred authorize failed: ${e.message}")
                }
            }
            scheduleDeferredLibrariesFetchFromServer()
        } finally {
            _isDeferredBootstrapNetworkRefreshInProgress.value = false
        }
    }

    /** Bibliotheksliste nach Lazy-Bootstrap — nicht blockierend für Home. */
    private fun scheduleDeferredLibrariesFetchFromServer() {
        deferredLibrariesFetchTask?.cancel()
        deferredLibrariesFetchTask = scope.launch { refreshLibrariesFromServerInBackground() }
    }

    private suspend fun refreshLibrariesFromServerInBackground() {
        if (bootstrapSupersededByOffline || offlineHomeUIActive) return
        if (!mayUseServerNetwork || !_isNetworkReachable.value) return
        val epoch = _accountSessionEpoch.value
        restoreServerClientIfNeeded()
        val c = client ?: return
        try {
            val list = c.libraries()
            if (bootstrapSupersededByOffline || offlineHomeUIActive || _accountSessionEpoch.value != epoch) return
            applyLibrariesFromServer(list)
            resolveLibrariesAfterServerFetch(Prefs.string(Keys.userDefaultLibraryId)?.swiftTrim()?.ifEmpty { null })
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "Deferred libraries fetch failed: ${e.message}")
        }
    }

    /** App-Start / Auto-Offline: nur LocalStore und Downloads, kein Netzwerk. */
    private suspend fun bootstrapLocalSessionOnly() {
        loadStartDashboard(skipAuthorizeRefresh = false, force = false)
        participants.forEach { it.bootstrapLocalSessionOnly() }
        participants.forEach { it.restoreLastPlayedOnLaunch() }
    }

    /** iOS: `prepareForOfflineHomeMode` — Teilnehmer sichern, dann Netzwerk trennen. */
    suspend fun prepareForOfflineHomeMode() {
        participants.forEach { it.prepareForOfflineHomeMode() }
        if (!offlineHomeUIActive) return
        _isServerReachable.value = false
        client = null
    }

    /** Laufende Bootstrap-Tasks abbrechen (Account-Wechsel, Logout, Offline während Bootstrap). */
    fun cancelDeferredBootstrapWork() {
        listOf(
            homeLaunchLocalRestoreTask, deferredBootstrapNetworkTask, deferredBootstrapAuthorizeTask,
            deferredLibrariesFetchTask, storedCredentialsBootstrapTask, postLaunchDashboardTask,
        ).forEach { it?.cancel() }
        homeLaunchLocalRestoreTask = null
        deferredBootstrapNetworkTask = null
        deferredBootstrapAuthorizeTask = null
        deferredLibrariesFetchTask = null
        storedCredentialsBootstrapTask = null
        postLaunchDashboardTask = null
        authorizeApplyGeneration++
    }

    // MARK: - Verbindung

    fun probeServerConnectionIfNeededAsync() {
        scope.launch { probeServerConnectionIfNeeded() }
    }

    suspend fun probeServerConnectionIfNeeded() {
        if (_isAppBootstrapInProgress.value || _isDeferredBootstrapNetworkRefreshInProgress.value) return
        if (!mayUseServerNetwork || !_isNetworkReachable.value) return
        if (_isServerReachable.value && client != null) return
        probeServerConnection()
    }

    /** Kurzer `/authorize`, ob der Server erreichbar ist. */
    suspend fun probeServerConnection() {
        if (!mayUseServerNetwork || !_isNetworkReachable.value || !computeIsLoggedIn()) {
            _isServerReachable.value = false
            return
        }
        _isServerConnectionProbeInProgress.value = true
        try {
            restoreServerClientIfNeeded()
            val c = client ?: run { _isServerReachable.value = false; return }
            val epoch = _accountSessionEpoch.value
            val generation = ++authorizeApplyGeneration
            try {
                val auth = c.authorize()
                if (_accountSessionEpoch.value != epoch || authorizeApplyGeneration != generation || !mayUseServerNetwork) return
                applyAuthorizeSession(auth)
                adoptLegacyTokenIfNeeded(auth, c)
                _isServerReachable.value = true
                _sessionRejected.value = false
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _isServerReachable.value = false
            }
        } finally {
            _isServerConnectionProbeInProgress.value = false
        }
    }

    /** iOS: `refreshProgressFromServer` — `/authorize` als Progress-Quelle. */
    suspend fun refreshProgressFromServer() {
        if (!mayUseServerNetwork) return
        val c = client ?: return
        val epoch = _accountSessionEpoch.value
        val generation = ++authorizeApplyGeneration
        try {
            val auth = c.authorize()
            if (_accountSessionEpoch.value != epoch || authorizeApplyGeneration != generation || !mayUseServerNetwork) return
            _isServerReachable.value = true
            applyAuthorizeSession(auth)
            adoptLegacyTokenIfNeeded(auth, c)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // 401/403 und abgebrochene Requests sind kein Erreichbarkeits-Signal.
            if (!SessionLogic.isAuthHTTPStatus(e) && !AbstandErrorFilter.isBenignCancellation(e)) _isServerReachable.value = false
        }
    }

    /** `/api/authorize` liefert nur das Legacy-Token — bei gesetztem Refresh-Token nie damit überschreiben. */
    private fun adoptLegacyTokenIfNeeded(auth: AbsLoginResponse, c: AbsApiClient) {
        val t = auth.user.token
        if (refreshToken.isEmpty() && t.isNotEmpty() && t != token) {
            token = t
            Prefs.setString(Keys.token, t)
            c.setToken(t)
        }
    }

    /** Settings/Online-Rückkehr: Bibliotheken vom Server; Kataloge nur bei [reloadCatalogs]. `true` bei Erfolg. */
    suspend fun reloadSettingsTab(reloadCatalogs: Boolean = false): Boolean {
        val c = client ?: return false
        return try {
            applyLibrariesFromServer(c.libraries())
            resolveLibrariesAfterServerFetch(Prefs.string(Keys.userDefaultLibraryId)?.swiftTrim()?.ifEmpty { null })
            if (reloadCatalogs) participants.forEach { it.reloadCatalogs() }
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            publishErrorUnlessBenignCancellation(e)
            false
        }
    }

    private fun watchNetworkReachability() {
        val cm = appContext.getSystemService(ConnectivityManager::class.java) ?: return
        _isNetworkReachable.value = cm.activeNetwork != null
        runCatching {
            cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    scope.launch { onNetworkReachabilityChanged(true) }
                }

                override fun onLost(network: Network) {
                    scope.launch { onNetworkReachabilityChanged(cm.activeNetwork != null && cm.activeNetwork != network) }
                }
            })
        }
    }

    private fun onNetworkReachabilityChanged(reachable: Boolean) {
        val was = _isNetworkReachable.value
        _isNetworkReachable.value = reachable
        if (!reachable) {
            _isServerReachable.value = false
        } else if (!was && !offlineHomeUIActive && !_isAppBootstrapInProgress.value && !_isDeferredBootstrapNetworkRefreshInProgress.value) {
            probeServerConnectionIfNeededAsync()
        }
    }

    // MARK: - Offline-Modus

    /** iOS: `offlineHomeMode.didSet` — persistieren und Übergang anstoßen. */
    fun setOfflineHomeMode(enabled: Boolean) {
        if (_offlineHomeMode.value == enabled) return
        _offlineHomeMode.value = enabled
        Prefs.setBool(Keys.offlineHomeMode, enabled)
        _offlineHomeModeAuto.value = false
        scheduleOfflineModeTransition(entering = enabled)
    }

    /** Offline-Home beenden (manuell oder automatisch). */
    fun exitOfflineHomeUI() {
        if (_offlineHomeMode.value) {
            setOfflineHomeMode(false)
        } else if (_offlineHomeModeAuto.value) {
            _offlineHomeModeAuto.value = false
            scheduleOfflineModeTransition(entering = false)
        }
    }

    /** Serialisiert Offline↔Online: eine laufende Transition. */
    private fun scheduleOfflineModeTransition(entering: Boolean) {
        modeTransitionTask?.cancel()
        modeTransitionTask = scope.launch {
            if (entering) {
                if (_isAppBootstrapInProgress.value) bootstrapSupersededByOffline = true
                cancelDeferredBootstrapWork()
                _isAppBootstrapInProgress.value = false
                _mainTab.value = MainTab.start
                prepareForOfflineHomeMode()
                bootstrapLocalSessionOnly()
            } else {
                restoreServerClientIfNeeded()
                probeServerConnection()
                if (_isServerReachable.value) reloadSettingsTab(reloadCatalogs = false)
                participants.forEach { it.onOfflineHomeModeExited() }
                loadStartDashboard(skipAuthorizeRefresh = true, force = true)
            }
        }
    }

    // MARK: - Login / Logout / Accounts

    suspend fun login(server: String, username: String, password: String) {
        setErrorMessage(null)
        val url = AbsApiClient.normalizeServerURL(server) ?: run {
            setErrorMessage("Please enter a valid server URL.")
            return
        }
        if (_isLoggedIn.value) syncStoredAccountFromSession()
        bootstrapSupersededByOffline = false
        _isAppBootstrapInProgress.value = true
        _offlineHomeModeAuto.value = false
        var serverSessionEstablished = false
        try {
            val res = AbsApiClient.login(url, username, password)
            if (bootstrapSupersededByOffline || offlineHomeUIActive) return
            // Ohne Token keine Session — lieber sauberer Login-Fehler als leerer Bearer.
            if (res.user.effectiveBearerToken.isEmpty()) throw AbsApiError.Unauthorized("Server returned no session token.")
            val newRefresh = res.user.refreshToken?.swiftTrim().orEmpty()
            setCredentials(server.swiftTrim(), res.user.effectiveBearerToken, newRefresh)
            val c = AbsApiClient(url, token, newRefresh.ifEmpty { null })
            client = c
            serverSessionEstablished = true
            _sessionRejected.value = false
            applyAuthorizeSession(res)
            syncStoredAccountFromSession()
            participants.forEach { it.onSessionActivated() }
            _isServerReachable.value = true
            applyLibrariesFromServer(c.libraries())
            if (bootstrapSupersededByOffline || offlineHomeUIActive) return
            resolveLibrariesAfterServerFetch(res.userDefaultLibraryId)
            if (bootstrapSupersededByOffline || offlineHomeUIActive) return
            _mainTab.value = MainTab.start
            finishLaunchPresentationAfterBootstrap()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (bootstrapSupersededByOffline || offlineHomeUIActive) return
            publishErrorUnlessBenignCancellation(e)
            if (serverSessionEstablished) {
                _isServerReachable.value = true
                _mainTab.value = MainTab.start
                finishLaunchPresentationAfterBootstrap()
                return
            }
            _isServerReachable.value = false
        } finally {
            if (!bootstrapSupersededByOffline) {
                _isAppBootstrapInProgress.value = false
                flushTabVisibilityAfterBootstrap()
            }
            bootstrapSupersededByOffline = false
        }
    }

    /** Entfernt den aktiven Account und wechselt zum nächsten gespeicherten — oder zeigt Login. */
    fun logout() {
        val key = _activeAccountKey.value ?: resolvedStoredAccountKey()
        if (key == null) {
            clearInMemorySessionState(clearCredentials = true)
            return
        }
        removeStoredAccount(key)
    }

    /** Account aus der Liste entfernen; beim aktiven Account wie [logout] zum nächsten wechseln. */
    fun removeStoredAccount(accountKey: String) {
        val key = accountKey.swiftTrim()
        if (key.isEmpty()) return
        val removingActive = key == _activeAccountKey.value
        // Serverseitige Session beenden, damit das Refresh-Token nicht 30 Tage gültig bleibt (best effort).
        _storedAccounts.value.firstOrNull { it.accountKey == key }?.let { removed ->
            val refresh = removed.refreshToken
            val url = AbsApiClient.normalizeServerURL(removed.serverURL)
            if (!refresh.isNullOrEmpty() && url != null) {
                scope.launch(Dispatchers.IO) { AbsApiClient.logout(url, refresh) }
            }
        }
        _storedAccounts.value = _storedAccounts.value.filterNot { it.accountKey == key }
        persistStoredAccounts()
        if (!removingActive) return
        val next = _storedAccounts.value.firstOrNull()
        if (next != null) {
            // Den entfernten Account beim Wechsel nicht wieder aus der laufenden Session einsortieren.
            scope.launch { switchToAccount(next.accountKey, savingCurrentSession = false) }
            return
        }
        _activeAccountKey.value = null
        AbsStoredAccountsPersistence.saveActiveAccountKey(null)
        clearInMemorySessionState(clearCredentials = true)
    }

    fun isActiveStoredAccount(account: AbsStoredAccount): Boolean = account.accountKey == _activeAccountKey.value

    /**
     * Auf gespeicherten Account wechseln. [savingCurrentSession] `false` beim Entfernen des aktiven
     * Accounts — sonst legt `syncStoredAccountFromSession()` ihn mit den abgemeldeten Tokens wieder an.
     */
    suspend fun switchToAccount(accountKey: String, savingCurrentSession: Boolean = true) {
        if (_isSwitchingAccount.value) return
        if (accountKey == _activeAccountKey.value) return
        val account = _storedAccounts.value.firstOrNull { it.accountKey == accountKey } ?: return
        _isSwitchingAccount.value = true
        try {
            if (savingCurrentSession) syncStoredAccountFromSession()
            participants.forEach { it.willSwitchAccount() }
            CoverImageCache.evictMemory(appContext)
            _coverImageCacheRevision.value += 1
            clearInMemorySessionState(clearCredentials = false)
            Net.resetConnections()
            setCredentials(account.serverURL, account.token, account.refreshToken ?: "")
            _activeAccountKey.value = accountKey
            AbsStoredAccountsPersistence.saveActiveAccountKey(accountKey)
            // Vor Authorize: UserId setzen, damit LocalStore und Home sofort zum richtigen Account zeigen.
            val switchedUserId = account.userId.swiftTrim()
            if (switchedUserId.isNotEmpty()) {
                sessionUserId = switchedUserId
                Prefs.setString(Keys.sessionUserId, switchedUserId)
            }
            _sessionUsername.value = account.username
            _sessionUserType.value = account.userType ?: "user"
            applyLibraryPreferencesFromStoredAccount(account)
            cacheAccountDir()?.let { EbookLocalStore.updateActiveSession(it, switchedUserId.ifEmpty { null }) }
            participants.forEach { it.onSessionActivated() }
            scheduleHomeLaunchRestoreFromLocalStore(account.booksLibraryId)
            _isAppBootstrapInProgress.value = true
            storedCredentialsBootstrapTask?.cancel()
            storedCredentialsBootstrapTask = null
            suppressDeferredWorkAfterBootstrap = true
            try {
                bootstrapFromStoredCredentials()
            } finally {
                suppressDeferredWorkAfterBootstrap = false
            }
            _accountSessionEpoch.value += 1
            reloadAllViewsAfterAccountSwitch()
        } finally {
            _isSwitchingAccount.value = false
        }
    }

    /** Nach Account-Wechsel: Bibliotheken + Kataloge/Home für alle Tabs neu aufbauen. */
    private suspend fun reloadAllViewsAfterAccountSwitch() {
        if (offlineHomeUIActive) return
        coroutineScope {
            launch { reloadSettingsTab(reloadCatalogs = true) }
            launch { participants.forEach { it.reloadAfterAccountSwitch() } }
        }
    }

    /**
     * Neuen Account speichern, ohne die aktuelle Session zu wechseln. `null` bei Erfolg, sonst
     * Fehlertext für das Sheet (leer = abgebrochen). Kein globales [errorMessage].
     */
    suspend fun addStoredAccount(server: String, username: String, password: String): String? {
        val url = AbsApiClient.normalizeServerURL(server) ?: return "Please enter a valid server URL."
        syncStoredAccountFromSession()
        val preserveActiveKey = _activeAccountKey.value
        return try {
            val res = AbsApiClient.login(url, username, password)
            SessionLogic.upsertStoredAccountFromUser(_storedAccounts.value, res.user, server.swiftTrim(), System.currentTimeMillis())
                ?.let { (list, _) -> _storedAccounts.value = list }
            _activeAccountKey.value = preserveActiveKey
            AbsStoredAccountsPersistence.saveActiveAccountKey(preserveActiveKey)
            persistStoredAccounts()
            null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (AbstandErrorFilter.isBenignCancellation(e)) "" else (e.message ?: e.toString())
        }
    }

    /** iOS: `upsertStoredAccountFromUser`. */
    fun upsertStoredAccountFromUser(user: AbsUser, serverURL: String, markActive: Boolean) {
        val (list, key) = SessionLogic.upsertStoredAccountFromUser(_storedAccounts.value, user, serverURL, System.currentTimeMillis()) ?: return
        _storedAccounts.value = list
        if (markActive) {
            _activeAccountKey.value = key
            AbsStoredAccountsPersistence.saveActiveAccountKey(key)
        }
        persistStoredAccounts()
    }

    /** iOS: `bootstrapStoredAccountsState` inkl. Legacy-Einzel-Login-Migration. */
    private fun bootstrapStoredAccountsState(): SessionLogic.StoredAccountsState {
        var accounts = AbsStoredAccountsPersistence.loadAccounts()
        if (accounts.isEmpty()) {
            SessionLogic.migrateLegacySingleAccount(
                Prefs.string(Keys.server), Prefs.string(Keys.token), Prefs.string(Keys.sessionUserId),
                Prefs.string(Keys.booksLibrary), Prefs.string(Keys.podcastsLibrary), System.currentTimeMillis(),
            )?.let { migrated ->
                accounts = listOf(migrated)
                AbsStoredAccountsPersistence.saveAccounts(accounts)
                AbsStoredAccountsPersistence.saveActiveAccountKey(migrated.accountKey)
            }
        }
        val state = SessionLogic.bootstrapStoredAccountsState(accounts, AbsStoredAccountsPersistence.loadActiveAccountKey())
        if (state.activeKeyChanged) AbsStoredAccountsPersistence.saveActiveAccountKey(state.activeKey)
        return state
    }

    /**
     * Vom Client erneuerte Tokens übernehmen — nur, wenn sie zur aktiven Session gehören (nach einem
     * Account-Wechsel kann noch ein Refresh des alten Clients eintreffen).
     */
    fun adoptRefreshedSessionTokens(serverURL: String, accessToken: String, refreshToken: String, previousRefreshToken: String) {
        if (!SessionLogic.shouldAdoptRefreshedTokens(_serverURL.value, serverURL, this.refreshToken, previousRefreshToken, accessToken)) return
        token = accessToken
        Prefs.setString(Keys.token, accessToken)
        if (refreshToken.isNotEmpty()) {
            this.refreshToken = refreshToken
            Prefs.setString(Keys.refreshToken, refreshToken)
        }
        syncStoredAccountFromSession(markActive = false)
        // Alle lebenden Clients angleichen — sonst erneuert ein anderer später mit dem rotierten Token und fliegt raus.
        client?.let { c ->
            c.setToken(accessToken)
            if (refreshToken.isNotEmpty()) c.setRefreshToken(refreshToken)
        }
        participants.forEach { it.onTokensRefreshed(accessToken, refreshToken) }
        _sessionRejected.value = false
        _tokenRevision.value += 1
    }

    fun syncStoredAccountFromSession() = syncStoredAccountFromSession(markActive = true)

    fun syncStoredAccountFromSession(markActive: Boolean) {
        val snapshot = SessionLogic.SessionSnapshot(
            serverURL = _serverURL.value,
            token = token,
            refreshToken = refreshToken,
            userId = sessionUserId,
            username = _sessionUsername.value,
            userType = _sessionUserType.value,
            booksLibraryId = Prefs.string(Keys.booksLibrary),
            podcastsLibraryId = Prefs.string(Keys.podcastsLibrary),
            activeBooksLibraryIds = _activeBooksLibraryIds.value,
            activePodcastLibraryIds = _activePodcastLibraryIds.value,
        )
        val (list, key) = SessionLogic.syncStoredAccounts(_storedAccounts.value, _activeAccountKey.value, snapshot, System.currentTimeMillis())
            ?: return
        _storedAccounts.value = list
        if (markActive) {
            _activeAccountKey.value = key
            AbsStoredAccountsPersistence.saveActiveAccountKey(key)
        }
        persistStoredAccounts()
    }

    fun resolvedStoredAccountKey(): String? {
        val userId = sessionUserId.swiftTrim()
        if (userId.isEmpty()) return _activeAccountKey.value
        return AbsStoredAccount.makeKey(_serverURL.value, userId)
    }

    fun persistStoredAccounts() = AbsStoredAccountsPersistence.saveAccounts(_storedAccounts.value)

    /** iOS: `applyLibraryPreferencesFromStoredAccount`. */
    fun applyLibraryPreferencesFromStoredAccount(account: AbsStoredAccount) {
        applyStoredLibraryPreference(account.booksLibraryId, Keys.booksLibrary)
        applyStoredLibraryPreference(account.podcastsLibraryId, Keys.podcastsLibrary)
        val booksPref = account.booksLibraryId?.swiftTrim().orEmpty()
        val podcastsPref = account.podcastsLibraryId?.swiftTrim().orEmpty()
        updateShowAudiobooksTab(booksPref != Keys.librarySelectionNone)
        updateShowPodcastsTab(podcastsPref != Keys.librarySelectionNone)
        applyActiveBooksLibraryIds(
            account.activeBooksLibraryIds
                ?: if (booksPref.isNotEmpty() && booksPref != Keys.librarySelectionNone) listOf(booksPref) else emptyList(),
        )
        applyActivePodcastLibraryIds(
            account.activePodcastLibraryIds
                ?: if (podcastsPref.isNotEmpty() && podcastsPref != Keys.librarySelectionNone) listOf(podcastsPref) else emptyList(),
        )
        _focusedBooksLibrary.value = null
        _focusedPodcastLibrary.value = null
    }

    private fun applyStoredLibraryPreference(value: String?, key: String) {
        if (!value.isNullOrEmpty()) Prefs.setString(key, value) else Prefs.remove(key)
    }

    /** iOS: `clearInMemorySessionState` — Session-Zustand verwerfen; [clearCredentials] = Logout. */
    fun clearInMemorySessionState(clearCredentials: Boolean) {
        cancelDeferredBootstrapWork()
        _mainTab.value = MainTab.start
        if (clearCredentials) {
            cacheAccountDir()?.let { CoverImageCache.clearAll(appContext, it) }
            _coverImageCacheRevision.value += 1
        }
        _offlineHomeMode.value = false
        Prefs.setBool(Keys.offlineHomeMode, false)
        _offlineHomeModeAuto.value = false
        _isServerReachable.value = false
        _isAppBootstrapInProgress.value = false
        _sessionRejected.value = false
        Prefs.remove(Keys.pendingOfflineListeningSeconds)
        participants.forEach { it.onSessionCleared(clearCredentials) }
        if (clearCredentials) {
            EbookLocalStore.updateActiveSession(null, null)
            LocalLibraryStoreManager.closeActiveStore()
            setCredentials("", "", "")
            Prefs.remove(Keys.refreshToken)
            Net.resetConnections()
        } else {
            EbookLocalStore.updateActiveSession(cacheAccountDir(), null)
        }
        _isServerAdmin.value = false
        _isServerRoot.value = false
        _serverSettings.value = null
        client = null
        _libraries.value = emptyList()
        _selectedBooksLibrary.value = null
        _selectedPodcastLibrary.value = null
        _focusedBooksLibrary.value = null
        _focusedPodcastLibrary.value = null
        _activeBooksLibraryIds.value = emptyList()
        _activePodcastLibraryIds.value = emptyList()
        sessionUserId = ""
        _sessionUsername.value = ""
        _sessionUserType.value = ""
        Prefs.remove(Keys.sessionUserId)
        Prefs.remove(Keys.lastPlayedItemId)
        if (clearCredentials) {
            Prefs.remove(Keys.booksLibrary)
            Prefs.remove(Keys.ebooksLibrary)
            Prefs.remove(Keys.podcastsLibrary)
            Prefs.remove(Keys.library)
            Prefs.remove(activeBooksLibraryIdsPrefsKey())
            Prefs.remove(activePodcastLibraryIdsPrefsKey())
        }
        Prefs.remove(Keys.startDisabledCategories)
        Prefs.remove(Keys.homeBrowseCategory)
        Prefs.remove(cachedLaunchArtifactsPrefsKey())
    }

    // MARK: - Authorize anwenden

    /** iOS: `applyAuthorizeSession`. */
    fun applyAuthorizeSession(auth: AbsLoginResponse, persistToDisk: Boolean = true) {
        applyAuthorizeUser(auth.user, persistToDisk)
        auth.serverSettings?.let { _serverSettings.value = it }
        auth.userDefaultLibraryId?.swiftTrim()?.takeIf { it.isNotEmpty() }?.let { Prefs.setString(Keys.userDefaultLibraryId, it) }
        if (persistToDisk) syncStoredAccountFromSession()
    }

    /** iOS: `applyAuthorizeUser` — Rolle, User-ID, eBook-Session; Progress/Bookmarks an Teilnehmer. */
    fun applyAuthorizeUser(user: AbsUser, persistToDisk: Boolean = true) {
        _isServerRoot.value = user.isRoot
        _isServerAdmin.value = user.isAdmin
        sessionUserId = user.id
        _sessionUsername.value = user.username
        _sessionUserType.value = user.type ?: "user"
        Prefs.setString(Keys.sessionUserId, user.id)
        EbookLocalStore.updateActiveSession(cacheAccountDir(), user.id)
        participants.forEach { it.onAuthorizeUser(user, persistToDisk) }
    }

    // MARK: - Bibliotheken

    /** Bibliotheksliste in Memory + Room übernehmen (Local-DB-First für den Library-Picker). */
    fun applyLibrariesFromServer(list: List<AbsLibrary>) {
        _libraries.value = list
        persistLibrariesToLocalStore(list)
        enrichSelectedLibrariesFromCachedList()
    }

    private fun persistLibrariesToLocalStore(list: List<AbsLibrary>) {
        val store = currentLocalLibraryStore() ?: return
        val generation = ++librariesPersistGeneration
        scope.launch {
            if (librariesPersistGeneration != generation) return@launch
            try {
                withContext(Dispatchers.IO) { store.replaceLibraries(list) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "LocalStore replaceLibraries failed: ${e.message}")
            }
            // Neuerer Apply während des Writes — aktuellen Stand nachziehen.
            if (librariesPersistGeneration != generation) persistLibrariesToLocalStore(_libraries.value)
        }
    }

    private fun enrichSelectedLibrariesFromCachedList() {
        val libs = _libraries.value
        _selectedBooksLibrary.value?.let { sel -> libs.firstOrNull { it.id == sel.id && it.isBookLibrary }?.let { _selectedBooksLibrary.value = it } }
        _selectedPodcastLibrary.value?.let { sel -> libs.firstOrNull { it.id == sel.id && it.isPodcastLibrary }?.let { _selectedPodcastLibrary.value = it } }
        _focusedBooksLibrary.value?.let { f -> libs.firstOrNull { it.id == f.id && it.isBookLibrary }?.let { _focusedBooksLibrary.value = it } }
        _focusedPodcastLibrary.value?.let { f -> libs.firstOrNull { it.id == f.id && it.isPodcastLibrary }?.let { _focusedPodcastLibrary.value = it } }
    }

    val sortedBookLibraries: List<AbsLibrary> get() = SessionLogic.sortedBookLibraries(_libraries.value)
    val sortedPodcastLibraries: List<AbsLibrary> get() = SessionLogic.sortedPodcastLibraries(_libraries.value)

    private fun libraryPreference(key: String): String = Prefs.string(key)?.swiftTrim().orEmpty()

    val booksLibraryPreferenceIsNone: Boolean get() = libraryPreference(Keys.booksLibrary) == Keys.librarySelectionNone
    val podcastsLibraryPreferenceIsNone: Boolean get() = libraryPreference(Keys.podcastsLibrary) == Keys.librarySelectionNone

    /** Browse/Reload: Fokus, sonst Primary. */
    val booksCatalogLibrary: AbsLibrary? get() = _focusedBooksLibrary.value ?: _selectedBooksLibrary.value
    val podcastCatalogLibrary: AbsLibrary? get() = _focusedPodcastLibrary.value ?: _selectedPodcastLibrary.value

    val activeBookLibraries: List<AbsLibrary>
        get() {
            val order = _activeBooksLibraryIds.value.withIndex().associate { it.value to it.index }
            return sortedBookLibraries.filter { it.id in order }.sortedBy { order[it.id] ?: Int.MAX_VALUE }
        }

    val activePodcastLibraries: List<AbsLibrary>
        get() {
            val order = _activePodcastLibraryIds.value.withIndex().associate { it.value to it.index }
            return sortedPodcastLibraries.filter { it.id in order }.sortedBy { order[it.id] ?: Int.MAX_VALUE }
        }

    fun isBooksLibraryActive(libraryId: String): Boolean = libraryId.swiftTrim().let { it.isNotEmpty() && it in _activeBooksLibraryIds.value }
    fun isPodcastLibraryActive(libraryId: String): Boolean = libraryId.swiftTrim().let { it.isNotEmpty() && it in _activePodcastLibraryIds.value }

    /** iOS: `resolvedPodcastLibraryId` — gewählte Podcast-Bibliothek oder gespeicherter Stub. */
    fun resolvedPodcastLibraryId(): String? {
        _selectedPodcastLibrary.value?.id?.swiftTrim()?.takeIf { it.isNotEmpty() }?.let { return it }
        val stored = libraryPreference(Keys.podcastsLibrary)
        return stored.takeUnless { it.isEmpty() || it == Keys.librarySelectionNone }
    }

    /** iOS: `resolveLibrariesAfterServerFetch` — Primary-Auswahl, Tab-Sichtbarkeit, Active-Sets. */
    fun resolveLibrariesAfterServerFetch(userDefaultLibraryId: String?) {
        val libs = _libraries.value
        when (val books = SessionLogic.resolveBooksLibrary(libraryPreference(Keys.booksLibrary), userDefaultLibraryId, libs)) {
            SessionLogic.LibraryResolution.PreferenceNone -> {
                _selectedBooksLibrary.value = null
                participants.forEach { it.onBooksLibraryCleared() }
                setShowAudiobooksTab(false)
            }
            is SessionLogic.LibraryResolution.Select -> selectBooksLibrary(books.library, navigateToCatalog = false)
            SessionLogic.LibraryResolution.NoneAvailable -> {
                _selectedBooksLibrary.value = null
                participants.forEach { it.onBooksLibraryCleared() }
                Prefs.setString(Keys.booksLibrary, Keys.librarySelectionNone)
                setShowAudiobooksTab(false)
            }
        }
        syncAudiobooksTabVisibilityFromLibraries()

        when (val pods = SessionLogic.resolvePodcastLibrary(libraryPreference(Keys.podcastsLibrary), libs)) {
            SessionLogic.LibraryResolution.PreferenceNone -> {
                _selectedPodcastLibrary.value = null
                participants.forEach { it.onPodcastLibraryCleared() }
            }
            is SessionLogic.LibraryResolution.Select -> selectPodcastLibrary(pods.library, navigateToCatalog = false)
            SessionLogic.LibraryResolution.NoneAvailable -> {
                _selectedPodcastLibrary.value = null
                _focusedPodcastLibrary.value = null
                participants.forEach { it.onPodcastLibraryCleared() }
                Prefs.setString(Keys.podcastsLibrary, Keys.librarySelectionNone)
                setShowPodcastsTab(false)
            }
        }
        syncPodcastsTabVisibilityFromLibraries()
        reconcileActiveLibraryIdsWithServerLibraries()
        participants.forEach { it.onLibrariesResolved() }
    }

    fun selectBooksLibrary(lib: AbsLibrary, navigateToCatalog: Boolean = false) {
        val current = _selectedBooksLibrary.value
        if (current?.id == lib.id) {
            if (current.name != lib.name || current.mediaType != lib.mediaType) _selectedBooksLibrary.value = lib
            if (lib.id !in _activeBooksLibraryIds.value) applyActiveBooksLibraryIds(listOf(lib.id) + _activeBooksLibraryIds.value)
            _focusedBooksLibrary.value = lib
            participants.forEach { it.onBooksLibrarySelected(lib, changed = false) }
            setShowAudiobooksTab(true)
            if (navigateToCatalog) showBooksLibraryOnHome(lib)
            return
        }
        _selectedBooksLibrary.value = lib
        Prefs.setString(Keys.booksLibrary, lib.id)
        val next = _activeBooksLibraryIds.value.let { if (lib.id in it) it else listOf(lib.id) + it }
        applyActiveBooksLibraryIds(next)
        _focusedBooksLibrary.value = lib
        syncStoredAccountFromSession()
        setShowAudiobooksTab(true)
        if (navigateToCatalog) showBooksLibraryOnHome(lib)
        participants.forEach { it.onBooksLibrarySelected(lib, changed = true) }
    }

    fun selectPodcastLibrary(lib: AbsLibrary, navigateToCatalog: Boolean = false) {
        val current = _selectedPodcastLibrary.value
        if (current?.id == lib.id) {
            if (current.name != lib.name || current.mediaType != lib.mediaType) _selectedPodcastLibrary.value = lib
            if (lib.id !in _activePodcastLibraryIds.value) applyActivePodcastLibraryIds(listOf(lib.id) + _activePodcastLibraryIds.value)
            _focusedPodcastLibrary.value = lib
            participants.forEach { it.onPodcastLibrarySelected(lib, changed = false) }
            setShowPodcastsTab(true)
            if (navigateToCatalog) showPodcastLibraryOnHome(lib)
            return
        }
        _selectedPodcastLibrary.value = lib
        Prefs.setString(Keys.podcastsLibrary, lib.id)
        val next = _activePodcastLibraryIds.value.let { if (lib.id in it) it else listOf(lib.id) + it }
        applyActivePodcastLibraryIds(next)
        _focusedPodcastLibrary.value = lib
        syncStoredAccountFromSession()
        setShowPodcastsTab(true)
        if (navigateToCatalog) showPodcastLibraryOnHome(lib)
        participants.forEach { it.onPodcastLibrarySelected(lib, changed = true) }
    }

    /** iOS: `clearBooksLibrarySelection` — bewusst keine Books-Bibliothek. */
    fun clearBooksLibrarySelection() {
        _selectedBooksLibrary.value = null
        _focusedBooksLibrary.value = null
        applyActiveBooksLibraryIds(emptyList())
        Prefs.setString(Keys.booksLibrary, Keys.librarySelectionNone)
        syncStoredAccountFromSession()
        setShowAudiobooksTab(false)
        participants.forEach { it.onBooksLibraryCleared() }
    }

    /** iOS: `clearPodcastLibrarySelection`. */
    fun clearPodcastLibrarySelection() {
        _selectedPodcastLibrary.value = null
        _focusedPodcastLibrary.value = null
        applyActivePodcastLibraryIds(emptyList())
        Prefs.setString(Keys.podcastsLibrary, Keys.librarySelectionNone)
        syncStoredAccountFromSession()
        setShowPodcastsTab(false)
        participants.forEach { it.onPodcastLibraryCleared() }
    }

    /** Settings: Library aktivieren/deaktivieren (Books). Primary bleibt in der aktiven Menge. */
    fun setBooksLibraryActive(libraryId: String, enabled: Boolean) {
        val id = libraryId.swiftTrim()
        if (id.isEmpty() || sortedBookLibraries.none { it.id == id }) return
        if (enabled) {
            applyActiveBooksLibraryIds(_activeBooksLibraryIds.value + id)
            participants.forEach { it.onActiveLibrariesChanged() }
            return
        }
        val next = _activeBooksLibraryIds.value - id
        if (_selectedBooksLibrary.value?.id == id) {
            val replacement = next.firstOrNull()?.let { rid -> sortedBookLibraries.firstOrNull { it.id == rid } }
            if (replacement != null) {
                applyActiveBooksLibraryIds(next)
                selectBooksLibrary(replacement)
                participants.forEach { it.onBooksLibraryFocused(replacement) }
            } else {
                applyActiveBooksLibraryIds(emptyList())
                clearBooksLibrarySelection()
            }
            return
        }
        applyActiveBooksLibraryIds(next)
        if (_focusedBooksLibrary.value?.id == id) {
            resetFocusedBooksLibraryToPrimaryOrFirstActive()
            _focusedBooksLibrary.value?.let { f -> participants.forEach { it.onBooksLibraryFocused(f) } }
        }
        participants.forEach { it.onActiveLibrariesChanged() }
    }

    /** Settings: Library aktivieren/deaktivieren (Podcasts). */
    fun setPodcastLibraryActive(libraryId: String, enabled: Boolean) {
        val id = libraryId.swiftTrim()
        if (id.isEmpty() || sortedPodcastLibraries.none { it.id == id }) return
        if (enabled) {
            applyActivePodcastLibraryIds(_activePodcastLibraryIds.value + id)
            participants.forEach { it.onActiveLibrariesChanged() }
            return
        }
        val next = _activePodcastLibraryIds.value - id
        if (_selectedPodcastLibrary.value?.id == id) {
            val replacement = next.firstOrNull()?.let { rid -> sortedPodcastLibraries.firstOrNull { it.id == rid } }
            if (replacement != null) {
                applyActivePodcastLibraryIds(next)
                selectPodcastLibrary(replacement)
                participants.forEach { it.onPodcastLibraryFocused(replacement) }
            } else {
                applyActivePodcastLibraryIds(emptyList())
                clearPodcastLibrarySelection()
            }
            return
        }
        applyActivePodcastLibraryIds(next)
        if (_focusedPodcastLibrary.value?.id == id) {
            resetFocusedPodcastLibraryToPrimaryOrFirstActive()
            _focusedPodcastLibrary.value?.let { f -> participants.forEach { it.onPodcastLibraryFocused(f) } }
        }
        participants.forEach { it.onActiveLibrariesChanged() }
    }

    /** Nav-Dropdown: nur Katalog-Fokus wechseln — Primary bleibt. */
    fun focusBooksLibrary(lib: AbsLibrary) {
        if (!lib.isBookLibrary || lib.id !in _activeBooksLibraryIds.value) return
        if (_focusedBooksLibrary.value?.id == lib.id) {
            if (_focusedBooksLibrary.value?.name != lib.name) _focusedBooksLibrary.value = lib
            return
        }
        _focusedBooksLibrary.value = lib
        participants.forEach { it.onBooksLibraryFocused(lib) }
    }

    fun focusPodcastLibrary(lib: AbsLibrary) {
        if (!lib.isPodcastLibrary || lib.id !in _activePodcastLibraryIds.value) return
        if (_focusedPodcastLibrary.value?.id == lib.id) {
            if (_focusedPodcastLibrary.value?.name != lib.name) _focusedPodcastLibrary.value = lib
            return
        }
        _focusedPodcastLibrary.value = lib
        participants.forEach { it.onPodcastLibraryFocused(lib) }
    }

    fun resetFocusedBooksLibraryToPrimaryOrFirstActive() {
        val primary = _selectedBooksLibrary.value
        _focusedBooksLibrary.value = if (primary != null && primary.id in _activeBooksLibraryIds.value) primary else activeBookLibraries.firstOrNull()
    }

    fun resetFocusedPodcastLibraryToPrimaryOrFirstActive() {
        val primary = _selectedPodcastLibrary.value
        _focusedPodcastLibrary.value = if (primary != null && primary.id in _activePodcastLibraryIds.value) primary else activePodcastLibraries.firstOrNull()
    }

    private fun activeBooksLibraryIdsPrefsKey() = SessionLogic.accountScopedKey(Keys.activeBooksLibraryIds, _activeAccountKey.value)
    private fun activePodcastLibraryIdsPrefsKey() = SessionLogic.accountScopedKey(Keys.activePodcastLibraryIds, _activeAccountKey.value)

    private fun applyActiveBooksLibraryIds(ids: List<String>) {
        val unique = SessionLogic.normalizeActiveIds(ids)
        _activeBooksLibraryIds.value = unique
        Prefs.setString(activeBooksLibraryIdsPrefsKey(), ActiveLibraryIdsStore.encode(unique))
        syncStoredAccountFromSession(markActive = false)
    }

    private fun applyActivePodcastLibraryIds(ids: List<String>) {
        val unique = SessionLogic.normalizeActiveIds(ids)
        _activePodcastLibraryIds.value = unique
        Prefs.setString(activePodcastLibraryIdsPrefsKey(), ActiveLibraryIdsStore.encode(unique))
        syncStoredAccountFromSession(markActive = false)
    }

    private fun loadActiveLibraryIdsFromPrefs() {
        _activeBooksLibraryIds.value = ActiveLibraryIdsStore.decode(Prefs.string(activeBooksLibraryIdsPrefsKey()))
        _activePodcastLibraryIds.value = ActiveLibraryIdsStore.decode(Prefs.string(activePodcastLibraryIdsPrefsKey()))
    }

    /** Nach Server-Libraries: Active-Sets migrieren/bereinigen und Fokus auf Primary setzen. */
    private fun reconcileActiveLibraryIdsWithServerLibraries() {
        loadActiveLibraryIdsFromPrefs()
        // Ohne Serverliste nicht bereinigen — sonst bleibt nur die Primary übrig.
        if (_libraries.value.isEmpty()) return
        SessionLogic.reconcileActiveIds(
            _activeBooksLibraryIds.value, sortedBookLibraries.map { it.id }.toSet(), booksLibraryPreferenceIsNone, _selectedBooksLibrary.value?.id,
        )?.let { ids -> if (ids != _activeBooksLibraryIds.value) applyActiveBooksLibraryIds(ids) }
        SessionLogic.reconcileActiveIds(
            _activePodcastLibraryIds.value, sortedPodcastLibraries.map { it.id }.toSet(), podcastsLibraryPreferenceIsNone, _selectedPodcastLibrary.value?.id,
        )?.let { ids -> if (ids != _activePodcastLibraryIds.value) applyActivePodcastLibraryIds(ids) }
        resetFocusedBooksLibraryToPrimaryOrFirstActive()
        resetFocusedPodcastLibraryToPrimaryOrFirstActive()
    }

    // MARK: - Tabs

    /**
     * iOS: `showAudiobooksTab.didSet` — persistieren. Android: kein eigener Tab mehr (Books liegt in
     * der Home-Bibliotheksleiste); das Flag sagt nur noch, ob es eine Books-Bibliothek gibt.
     */
    private fun updateShowAudiobooksTab(visible: Boolean) {
        _showAudiobooksTab.value = visible
        Prefs.setBool(Keys.showAudiobooksTab, visible)
    }

    /** Wie [updateShowAudiobooksTab] — Podcast-Bibliothek vorhanden (Suche, Home-Leiste). */
    private fun updateShowPodcastsTab(visible: Boolean) {
        _showPodcastsTab.value = visible
        Prefs.setBool(Keys.showPodcastsTab, visible)
    }

    /** Tab-Struktur bleibt während des Bootstraps stabil (iOS-Regel: kein strukturelles Umschalten). */
    private fun setShowAudiobooksTab(visible: Boolean) {
        if (_isAppBootstrapInProgress.value) return
        if (_showAudiobooksTab.value != visible) updateShowAudiobooksTab(visible)
    }

    private fun setShowPodcastsTab(visible: Boolean) {
        if (_isAppBootstrapInProgress.value) return
        if (_showPodcastsTab.value != visible) updateShowPodcastsTab(visible)
    }

    /** Tab-Leiste erst nach Bootstrap aktualisieren. */
    fun flushTabVisibilityAfterBootstrap() {
        syncAudiobooksTabVisibilityFromLibraries()
        syncPodcastsTabVisibilityFromLibraries()
    }

    private fun syncPodcastsTabVisibilityFromLibraries() {
        if (_isAppBootstrapInProgress.value) return
        // Ohne geladene Liste nichts ableiten (iOS: leere Liste blendet aus — siehe Bericht).
        if (_libraries.value.isEmpty()) return
        setShowPodcastsTab(SessionLogic.tabVisibleFromLibraries(podcastsLibraryPreferenceIsNone, sortedPodcastLibraries.isNotEmpty()))
    }

    private fun syncAudiobooksTabVisibilityFromLibraries() {
        if (_isAppBootstrapInProgress.value) return
        if (_libraries.value.isEmpty()) return
        setShowAudiobooksTab(SessionLogic.tabVisibleFromLibraries(booksLibraryPreferenceIsNone, sortedBookLibraries.isNotEmpty()))
    }

    /** iOS: `mainTab = …` aus Views (Tab-Leiste). */
    fun selectMainTab(tab: MainTab) {
        _mainTab.value = tab
    }

    // MARK: - Home-Bibliotheksleiste (Android)

    private val _homeLibraryChoiceId = MutableStateFlow(Prefs.string(HomeLibraryLogic.prefsKey).orEmpty())
    /** Gewählte Bibliothek der Home-Bibliotheksleiste (`b:<id>` / `p:<id>`, siehe [HomeLibraryLogic]). */
    val homeLibraryChoiceId: StateFlow<String> = _homeLibraryChoiceId.asStateFlow()

    private val _homeLibraryRevealEpoch = MutableStateFlow(0)
    /** Zählt hoch, wenn Home zur Bibliotheksleiste scrollen soll (Sprung aus Suche/Detail). */
    val homeLibraryRevealEpoch: StateFlow<Int> = _homeLibraryRevealEpoch.asStateFlow()

    /** Kombinierte Auswahl (aktive Books- + Podcast-Bibliotheken). */
    val homeLibraryChoices: List<HomeLibraryLogic.Choice>
        get() = HomeLibraryLogic.choices(activeBookLibraries, activePodcastLibraries)

    /** Aktuell gültige Home-Bibliothek (gespeichert, sonst fokussiert, sonst erste). */
    fun resolvedHomeLibraryChoice(): HomeLibraryLogic.Choice? = HomeLibraryLogic.resolve(
        homeLibraryChoices, _homeLibraryChoiceId.value,
        _focusedBooksLibrary.value?.id, _focusedPodcastLibrary.value?.id,
    )

    /** Bibliothek der Home-Leiste wählen (merken + fokussieren, damit Katalog bzw. Feed sie laden). */
    fun selectHomeLibraryChoice(choiceId: String) {
        val choice = homeLibraryChoices.firstOrNull { it.id == choiceId } ?: return
        if (_homeLibraryChoiceId.value != choice.id) {
            _homeLibraryChoiceId.value = choice.id
            Prefs.setString(HomeLibraryLogic.prefsKey, choice.id)
        }
        if (choice.isPodcast) focusPodcastLibrary(choice.library) else focusBooksLibrary(choice.library)
    }

    /**
     * Statt Books-Tab: Home mit der Books-Bibliothek in der Leiste zeigen (fokussiert, sonst Primary,
     * sonst erste aktive) und zur Leiste scrollen.
     */
    fun showBooksLibraryOnHome(library: AbsLibrary? = null) {
        val lib = library ?: _focusedBooksLibrary.value ?: _selectedBooksLibrary.value ?: activeBookLibraries.firstOrNull()
        lib?.let { selectHomeLibraryChoice(HomeLibraryLogic.booksChoiceId(it.id)) }
        revealHomeLibrary()
    }

    /** Statt Podcasts-Tab: Home mit der Podcast-Bibliothek in der Leiste zeigen. */
    fun showPodcastLibraryOnHome(library: AbsLibrary? = null) {
        val lib = library ?: _focusedPodcastLibrary.value ?: _selectedPodcastLibrary.value ?: activePodcastLibraries.firstOrNull()
        lib?.let { selectHomeLibraryChoice(HomeLibraryLogic.podcastChoiceId(it.id)) }
        revealHomeLibrary()
    }

    private fun revealHomeLibrary() {
        _mainTab.value = MainTab.start
        _homeLibraryRevealEpoch.value += 1
    }

    private companion object {
        const val TAG = "SessionStore"
    }
}
