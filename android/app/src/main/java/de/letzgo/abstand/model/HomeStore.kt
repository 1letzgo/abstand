package de.letzgo.abstand.model

import android.util.Log
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsItemsInProgressPayload
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfLocalization
import de.letzgo.abstand.data.AbsStartShelfSection
import de.letzgo.abstand.data.AbsUser
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.AbstandErrorFilter
import de.letzgo.abstand.data.ContinueRefreshAttemptResult
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.store.ActiveLibraryIdsStore
import de.letzgo.abstand.store.EbookLocalStore
import de.letzgo.abstand.store.LocalLibraryStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield

/**
 * iOS: Home-Teile von `AppModel.swift` — Start-Dashboard (`startShelves`), Continue listening,
 * personalisierte Regale, Regal-Reihenfolge/-Schalter (`Keys.startCategoryOrder`,
 * `Keys.startDisabledCategories`), Home-Browse-Kategorie (`Keys.homeBrowseCategory`), Continue
 * reading (eBooks), „New episodes“ und das Offline-Home aus Downloads.
 *
 * Cache-first: [restoreFromLocalStore] rendert Regale + Fortschritt aus Room, bevor
 * [loadStartDashboard] `/personalized` + `items-in-progress` holt. Die Entscheidungslogik liegt rein
 * in [HomeShelfLogic]; hier nur Zustand, Netz und Persistenz.
 *
 * Fortschritt ([progressByItemId]) liegt vorerst hier (iOS: `AppModel.progressByItemId`), weil Home
 * ihn als Erster braucht; der Player meldet Ticks über [applyProgressUpdate].
 */
class HomeStore internal constructor(private val model: AppModel) : SessionParticipant {
    private val session: SessionStore get() = model.session

    // MARK: - Zustand

    private val _startShelves = MutableStateFlow<List<AbsStartShelfSection>>(emptyList())
    /** iOS: `startShelves` — sichtbare Home-Regale (gefiltert nach Schaltern). */
    val startShelves: StateFlow<List<AbsStartShelfSection>> = _startShelves.asStateFlow()

    private val _startBooks = MutableStateFlow<List<AbsBook>>(emptyList())
    /** iOS: `startBooks` — alle Bücher der Regale (Detail-Fallback, Continue-Kandidaten). */
    val startBooks: StateFlow<List<AbsBook>> = _startBooks.asStateFlow()

    private val _startSettingsCategoryList = MutableStateFlow(
        HomeShelfLogic.categoryList(HomeShelfLogic.effectiveCategoryOrder(loadCategoryOrder(), showNewestEpisodes = false), emptyList()),
    )
    /** iOS: `startSettingsCategoryList` — Reihenfolge + Labels der Regal-Schalter. */
    val startSettingsCategoryList: StateFlow<List<StartCategoryRow>> = _startSettingsCategoryList.asStateFlow()

    private val _startDisabledCategories = MutableStateFlow(loadDisabledCategories())
    /** iOS: `startDisabledCategories` (persistiert). */
    val startDisabledCategories: StateFlow<Set<String>> = _startDisabledCategories.asStateFlow()

    private val _startCategoryOrder = MutableStateFlow(loadCategoryOrder())
    /** iOS: `startCategoryOrder` — Nutzer-Reihenfolge (Continue listening immer zuerst). */
    val startCategoryOrder: StateFlow<List<String>> = _startCategoryOrder.asStateFlow()

    private val _homeBrowseCategory = MutableStateFlow(HomeShelfLogic.initialHomeBrowseCategory(Prefs.string(Keys.homeBrowseCategory)))
    /** iOS: `homeBrowseCategory`. */
    val homeBrowseCategory: StateFlow<String> = _homeBrowseCategory.asStateFlow()

    private val _progressByItemId = MutableStateFlow<Map<String, AbsUserMediaProgress>>(emptyMap())
    /** iOS: `progressByItemId` — Schlüssel = `progressLookupKey`. */
    val progressByItemId: StateFlow<Map<String, AbsUserMediaProgress>> = _progressByItemId.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    /** Pull-to-Refresh läuft (iOS: `.refreshable`-Spinner). */
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    /** iOS: `suppressedContinueListeningKeys` + lokal fertig markierte Keys — vom Player/Detail gepflegt. */
    private val blockedContinueKeys = HashSet<String>()

    /** Letzter `items-in-progress`-Stand (Server oder LocalStore) — Metadaten-Pool für Continue. */
    private var cachedInProgress: AbsItemsInProgressPayload? = null
    private var localProgressLoaded = false
    private var dashboardGeneration = 0
    private var persistGeneration = 0
    private var replaceContinueOnNextLoad = false
    private var postProcessingJob: Job? = null

    private val disabled: Set<String> get() = _startDisabledCategories.value
    private val offline: Boolean get() = session.offlineHomeUIActive

    init {
        HomeShelfLogic.migratedDisabledCategories(_startDisabledCategories.value)?.let { persistDisabled(it) }
    }

    // MARK: - Abgeleitete Werte

    /** iOS: `isAnyHomeBrowseContinueShelfEnabled`. */
    val isAnyShelfEnabled: Boolean
        get() = HomeShelfLogic.isAnyShelfEnabled(_startSettingsCategoryList.value, disabled)

    fun isStartCategoryEnabled(category: String): Boolean = HomeShelfLogic.isEnabled(category, disabled)

    /** iOS: `startShelves(forHomeBrowseSection:)`. */
    fun startShelvesForHomeBrowseSection(sectionId: String): List<AbsStartShelfSection> =
        HomeShelfLogic.shelvesForHomeBrowseSection(sectionId, _startSettingsCategoryList.value, _startShelves.value, disabled)

    private fun continueContext(): ContinueContext {
        val now = model.playbackLauncher.nowPlaying.value
        return ContinueContext(_progressByItemId.value, blockedContinueKeys.toSet(), now.progressKey)
    }

    private val activeBookLibraryIds: Set<String> get() = session.activeBooksLibraryIds.value.toSet()
    private val activePodcastLibraryIds: Set<String> get() = session.activePodcastLibraryIds.value.toSet()
    private val showNewestEpisodes: Boolean
        get() = session.selectedPodcastLibrary.value != null && !session.podcastsLibraryPreferenceIsNone

    private fun effectiveOrder(): List<String> =
        HomeShelfLogic.effectiveCategoryOrder(_startCategoryOrder.value, showNewestEpisodes)

    // MARK: - Regale setzen

    private fun setShelves(shelves: List<AbsStartShelfSection>) {
        _startShelves.value = shelves
        _startBooks.value = HomeShelfLogic.startBooksUnion(shelves)
    }

    /** iOS: `assignStartShelvesPreservingLocalOnly`. */
    private fun assignPreservingLocalOnly(next: List<AbsStartShelfSection>, prior: List<AbsStartShelfSection>) {
        setShelves(HomeShelfLogic.mergingPreservedLocalOnly(next, prior, disabled, effectiveOrder()))
    }

    /** iOS: `updateStartSettingsCategoryList(parsed:)`. */
    private fun updateCategoryList(parsed: List<AbsStartShelfSection>) {
        _startSettingsCategoryList.value = HomeShelfLogic.categoryList(effectiveOrder(), parsed)
        clampHomeBrowseSectionIfNeeded()
    }

    /** iOS: `refreshStartSettingsCategoryListLabels`. */
    fun refreshStartSettingsCategoryListLabels() {
        _startSettingsCategoryList.value = HomeShelfLogic.categoryListKeepingLabels(effectiveOrder(), _startSettingsCategoryList.value)
        clampHomeBrowseSectionIfNeeded()
    }

    // MARK: - Schalter & Reihenfolge (Settings → Appearance → Home)

    /** iOS: `setStartCategoryEnabled(_:enabled:)`. */
    fun setStartCategoryEnabled(category: String, enabled: Boolean) {
        val next = if (enabled) disabled - category else disabled + category
        persistDisabled(next)
        clampHomeBrowseSectionIfNeeded()
        model.scope.launch { loadStartDashboard(force = true) }
    }

    /** iOS: `moveStartSettingsCategory(dragging:onto:)`. */
    fun moveStartSettingsCategory(fromId: String, ontoId: String) {
        val next = HomeShelfLogic.moveCategory(_startSettingsCategoryList.value.map { it.category }, fromId, ontoId) ?: return
        persistOrder(next)
        refreshStartSettingsCategoryListLabels()
        reorderShelvesToSettings()
    }

    /** Eine Position nach oben/unten (Android-Ersatz für Drag-and-Drop in der Liste). */
    fun moveStartSettingsCategory(category: String, offset: Int) {
        val cats = _startSettingsCategoryList.value.map { it.category }
        val idx = cats.indexOf(category)
        val target = idx + offset
        if (idx < 1 || target < 1 || target >= cats.size) return
        moveStartSettingsCategory(category, cats[target])
    }

    /** Regale sofort in die neue Settings-Reihenfolge bringen (Anzeige folgt ohnehin der Liste). */
    private fun reorderShelvesToSettings() {
        val order = _startSettingsCategoryList.value.map { it.category }
        val sorted = _startShelves.value.sortedBy { order.indexOf(it.category).let { i -> if (i < 0) Int.MAX_VALUE else i } }
        if (sorted != _startShelves.value) setShelves(sorted)
        persistHomeShelvesToLocalStore()
    }

    /** iOS: `selectHomeBrowseSection`. */
    fun selectHomeBrowseSection(category: String) {
        if (category !in homeBrowseStripIds()) return
        setHomeBrowseCategory(category)
    }

    private fun homeBrowseStripIds(): List<String> = HomeShelfLogic.homeBrowseStripIds(offline, isAnyShelfEnabled)

    /** iOS: `clampHomeBrowseSectionIfNeeded`. */
    fun clampHomeBrowseSectionIfNeeded() {
        val next = HomeShelfLogic.clampHomeBrowseCategory(_homeBrowseCategory.value, _startSettingsCategoryList.value, homeBrowseStripIds())
        if (next != _homeBrowseCategory.value || Prefs.string(Keys.homeBrowseCategory) != next) setHomeBrowseCategory(next)
    }

    private fun setHomeBrowseCategory(value: String) {
        _homeBrowseCategory.value = value
        Prefs.setString(Keys.homeBrowseCategory, value)
    }

    private fun persistDisabled(next: Set<String>) {
        _startDisabledCategories.value = next
        Prefs.setString(Keys.startDisabledCategories, ActiveLibraryIdsStore.encode(next.sorted()))
    }

    private fun persistOrder(order: List<String>) {
        _startCategoryOrder.value = order
        val encoded = ActiveLibraryIdsStore.encode(order)
        if (encoded != null) Prefs.setString(Keys.startCategoryOrder, encoded) else Prefs.remove(Keys.startCategoryOrder)
    }

    // MARK: - Fortschritt

    /** iOS: `applyUserProgress(_:persistToDisk:)` (ohne Reset-/Discard-Sonderfälle). */
    fun applyUserProgress(list: List<AbsUserMediaProgress>?, persistToDisk: Boolean = true) {
        if (list.isNullOrEmpty()) return
        val next = _progressByItemId.value.toMutableMap()
        for (p in list) {
            val key = p.progressLookupKey
            if (p.isFinished) blockedContinueKeys.remove(key)
            next[key] = HomeShelfLogic.mergedProgress(next[key], p)
        }
        _progressByItemId.value = next
        localProgressLoaded = true
        syncContinueListeningShelvesWithProgress()
        if (persistToDisk) persistProgress(list)
    }

    /** Player-Tick / Fertig markieren: eine Zeile übernehmen (iOS: `progressByItemId[key] = …`). */
    fun applyProgressUpdate(progress: AbsUserMediaProgress, persistToDisk: Boolean = true) {
        _progressByItemId.value = _progressByItemId.value + (progress.progressLookupKey to progress)
        syncContinueListeningShelvesWithProgress()
        if (persistToDisk) persistProgress(listOf(progress))
    }

    /** iOS: `suppressedContinueListeningKeys` — Titel aus Continue nehmen (z. B. „Remove from Continue“). */
    fun suppressContinueListening(progressKey: String, suppressed: Boolean = true) {
        val k = progressKey.swiftTrim()
        if (k.isEmpty()) return
        if (suppressed) blockedContinueKeys.add(k) else blockedContinueKeys.remove(k)
        syncContinueListeningShelvesWithProgress()
        persistHomeShelvesToLocalStore()
    }

    private fun persistProgress(list: List<AbsUserMediaProgress>) {
        val store = session.currentLocalLibraryStore() ?: return
        model.scope.launch {
            runCatching { store.upsertProgress(list) }.onFailure { Log.w(TAG, "upsertProgress failed: ${it.message}") }
        }
    }

    // MARK: - Dashboard laden

    /**
     * iOS: `loadStartDashboard(skipAuthorizeRefresh:force:forPullToRefresh:replaceContinueShelves:)` —
     * online `/personalized` je aktiver Books-Bibliothek + `items-in-progress`; offline nur Downloads.
     */
    suspend fun loadStartDashboard(
        skipAuthorizeRefresh: Boolean = false,
        force: Boolean = false,
        forPullToRefresh: Boolean = false,
        replaceContinueShelves: Boolean = false,
    ): ContinueRefreshAttemptResult {
        awaitHomeLaunchLocalRestore()
        ensureLocalProgressLoaded()
        val result = ContinueRefreshAttemptResult()
        if (!force && !offline && _startShelves.value.isNotEmpty()) return result

        val generation = ++dashboardGeneration
        val shouldReplaceContinue = forPullToRefresh || replaceContinueShelves || replaceContinueOnNextLoad
        replaceContinueOnNextLoad = false
        var appliedOnline = false
        try {
            if (offline) {
                applyOfflineStartDashboard()
                return result
            }
            if (forPullToRefresh) session.restoreServerClientIfNeeded()
            val c = session.client
            if (c == null) {
                applyCachedStartDashboard()
                if (forPullToRefresh) session.setErrorMessage("Not connected to the server.")
                return result
            }
            if (!forPullToRefresh && !session.isNetworkReachable.value) {
                applyCachedStartDashboard()
                return result
            }
            if (_startShelves.value.isEmpty()) applyCachedStartDashboard()
            result.attemptedNetwork = true
            try {
                val bookLibraryIds = session.activeBooksLibraryIds.value.map { it.swiftTrim() }.filter { it.isNotEmpty() }
                    .ifEmpty { listOfNotNull(session.selectedBooksLibrary.value?.id?.swiftTrim()?.ifEmpty { null }) }
                coroutineScope {
                    val inProgress = async { c.itemsInProgress(limit = 80) }
                    val progressSync = if (skipAuthorizeRefresh) null else launch { session.refreshProgressFromServer() }
                    var merged = emptyList<AbsStartShelfSection>()
                    for (libraryId in bookLibraryIds) {
                        val data = c.personalizedShelves(libraryId, limit = 14)
                        val parsed = withContext(Dispatchers.Default) { AbsApiClient.parsePersonalizedStartShelves(data) }
                        merged = HomeShelfLogic.mergePersonalizedShelves(merged, parsed, _progressByItemId.value)
                    }
                    val payload = inProgress.await()
                    progressSync?.join()
                    if (generation != dashboardGeneration || offline) return@coroutineScope
                    cachedInProgress = payload
                    if (bookLibraryIds.isNotEmpty()) {
                        updateCategoryList(merged)
                        applyOnlineStartDashboard(merged, payload, shouldReplaceContinue)
                    } else {
                        applyStartDashboardFromItemsInProgressOnly(payload)
                    }
                    appliedOnline = true
                    result.appliedOnline = true
                }
                yield()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                result.error = e
                if (!skipAuthorizeRefresh) session.refreshProgressFromServer()
                if (generation != dashboardGeneration) return result
                if (!forPullToRefresh) applyCachedStartDashboard()
                session.publishErrorUnlessBenignCancellation(e, forceDisplay = forPullToRefresh)
            }
            return result
        } finally {
            // Nur die aktuellste Ladung darf Nacharbeit anstoßen.
            if (generation == dashboardGeneration) {
                scheduleStartDashboardPostProcessing(includeEbookShelfRefresh = !appliedOnline, skipContinueSync = appliedOnline)
            }
        }
    }

    /** iOS: `refreshStartTabPullToRefresh` (Dashboard-Zweig). */
    suspend fun refreshStartTabPullToRefresh() {
        _isRefreshing.value = true
        try {
            session.refreshProgressFromServer()
            loadStartDashboard(skipAuthorizeRefresh = true, force = true, forPullToRefresh = true)
        } finally {
            _isRefreshing.value = false
        }
    }

    /** iOS: `awaitHomeLaunchLocalRestore` — Kaltstart-Restore ist alleiniger Erst-Schreiber. */
    private suspend fun awaitHomeLaunchLocalRestore() {
        session.isHomeContinueRestoreInProgress.first { !it }
    }

    /** iOS: `ensureLocalProgressLoaded`. */
    private suspend fun ensureLocalProgressLoaded() {
        if (localProgressLoaded) return
        val store = session.currentLocalLibraryStore() ?: return
        val list = runCatching { store.fetchAllProgress() }.getOrNull().orEmpty()
        localProgressLoaded = true
        if (list.isNotEmpty()) applyUserProgress(list, persistToDisk = false)
    }

    /** iOS: `scheduleStartDashboardPostProcessing`. */
    private fun scheduleStartDashboardPostProcessing(includeEbookShelfRefresh: Boolean, skipContinueSync: Boolean) {
        postProcessingJob?.cancel()
        postProcessingJob = model.scope.launch {
            yield()
            if (offline) {
                applyOfflineStartDashboard()
                return@launch
            }
            repairContinueListeningShelfFromLocalProgressOnly()
            if (!skipContinueSync) syncContinueListeningShelvesWithProgress()
            HomeShelfLogic.normalizeContinueShelves(_startShelves.value, disabled, _progressByItemId.value)?.let { setShelves(it) }
            if (!includeEbookShelfRefresh) return@launch
            yield()
            refreshEbookContinueReadingShelf()
            yield()
            refreshNewestEpisodesShelf()
        }
    }

    // MARK: - Online anwenden

    /** iOS: `applyOnlineStartDashboard(parsed:itemsInProgress:replaceContinueShelves:)`. */
    private suspend fun applyOnlineStartDashboard(
        parsed: List<AbsStartShelfSection>,
        itemsInProgress: AbsItemsInProgressPayload,
        replaceContinueShelves: Boolean,
    ) {
        val prior = _startShelves.value
        if (!isStartCategoryEnabled(HomeShelfLogic.homeContinueCategory)) {
            assignPreservingLocalOnly(parsed.filter { isStartCategoryEnabled(it.category) }, prior)
            refreshEbookContinueReadingShelf()
            persistHomeShelvesToLocalStore()
            return
        }
        if (parsed.isEmpty()) {
            applyStartDashboardFromItemsInProgressOnly(itemsInProgress)
            return
        }
        val visible = parsed.filter { isStartCategoryEnabled(it.category) }
        if (replaceContinueShelves) {
            assignPreservingLocalOnly(visible, prior)
        } else {
            val priorContinue = prior.filter { HomeShelfLogic.isContinueCategory(it.category) }
            if (!HomeShelfLogic.haveSameLayout(prior.filter { !HomeShelfLogic.isLocalOnlyCategory(it.category) }, visible)) {
                assignPreservingLocalOnly(visible, prior)
            }
            preserveValidContinueListeningItems(priorContinue.flatMap { it.books }, priorContinue.flatMap { it.podcastEpisodes })
        }
        mergeServerItemsIntoContinue(itemsInProgress, "continue-from-items-in-progress")
        syncContinueListeningShelvesWithProgress()
        refreshEbookContinueReadingShelf()
        persistHomeShelvesToLocalStore()
    }

    /** iOS: `applyStartDashboardFromItemsInProgressOnly`. */
    private suspend fun applyStartDashboardFromItemsInProgressOnly(payload: AbsItemsInProgressPayload) {
        val prior = _startShelves.value
        if (!isStartCategoryEnabled(HomeShelfLogic.homeContinueCategory)) {
            assignPreservingLocalOnly(emptyList(), prior)
        } else {
            val ctx = continueContext()
            val books = HomeShelfLogic.inProgressAudiobookCandidates(payload, ctx, activeBookLibraryIds, session.selectedBooksLibrary.value?.id)
            val eps = HomeShelfLogic.inProgressPodcastEpisodeCandidates(payload, ctx, activePodcastLibraryIds, session.resolvedPodcastLibraryId())
            if (books.isEmpty() && eps.isEmpty()) {
                assignPreservingLocalOnly(emptyList(), prior)
            } else {
                assignPreservingLocalOnly(listOf(HomeShelfLogic.makeContinueShelf("items-in-progress", books, eps)), prior)
                syncContinueListeningShelvesWithProgress()
            }
        }
        refreshEbookContinueReadingShelf()
        persistHomeShelvesToLocalStore()
    }

    /**
     * iOS: `ensureContinueListeningShelfIfMissing` + `mergeServerAudiobooksIntoContinueShelves` +
     * `mergeServerPodcastEpisodesIntoContinueShelves` — Server-`items-in-progress` ins Regal.
     */
    private fun mergeServerItemsIntoContinue(payload: AbsItemsInProgressPayload, newShelfId: String) {
        if (!isStartCategoryEnabled(HomeShelfLogic.homeContinueCategory)) return
        val ctx = continueContext()
        val books = HomeShelfLogic.inProgressAudiobookCandidates(payload, ctx, activeBookLibraryIds, session.selectedBooksLibrary.value?.id)
        val eps = HomeShelfLogic.inProgressPodcastEpisodeCandidates(payload, ctx, activePodcastLibraryIds, session.resolvedPodcastLibraryId())
        HomeShelfLogic.mergeIntoContinueShelf(_startShelves.value, books, eps, disabled, ctx.progress, newShelfId)?.let { setShelves(it) }
    }

    /** iOS: `preserveValidContinueListeningItems`. */
    private fun preserveValidContinueListeningItems(books: List<AbsBook>, episodes: List<AbsPodcastEpisodeListItem>) {
        if (!isStartCategoryEnabled(HomeShelfLogic.homeContinueCategory)) return
        val ctx = continueContext()
        val validBooks = books.filter { HomeShelfLogic.qualifiesForContinue(it.id, ctx) }
        val validEps = episodes.filter { HomeShelfLogic.qualifiesForContinue(it.progressLookupKey, ctx) }
        HomeShelfLogic.mergeIntoContinueShelf(_startShelves.value, validBooks, validEps, disabled, ctx.progress, "preserved-continue")
            ?.let { setShelves(it) }
    }

    /** iOS: `syncContinueListeningShelvesWithProgress` → `applyContinueListeningFinishedFilter`. */
    fun syncContinueListeningShelvesWithProgress() {
        HomeShelfLogic.applyFinishedFilter(_startShelves.value, continueContext())?.let { setShelves(it) }
    }

    /**
     * iOS: `repairContinueListeningShelfFromLocalProgressOnly` — Continue aus Katalog-/Download-Cache
     * und gespeichertem Fortschritt ergänzen (nicht offline: dort nur Downloads).
     */
    fun repairContinueListeningShelfFromLocalProgressOnly() {
        if (offline || !isStartCategoryEnabled(HomeShelfLogic.homeContinueCategory)) return
        val ctx = continueContext()
        val books = localContinueBookCandidates(ctx)
        val eps = localContinueEpisodeCandidates(ctx)
        HomeShelfLogic.mergeIntoContinueShelf(
            _startShelves.value, books, eps, disabled, ctx.progress, "local-cache-continue", forceCanonicalCategory = true,
        )?.let { setShelves(it) }
    }

    private fun localContinueBookCandidates(ctx: ContinueContext): List<AbsBook> {
        val downloaded = model.downloadStatus.downloadedBooks()
        val pool = _startBooks.value + cachedInProgress?.books.orEmpty() + downloaded
        return HomeShelfLogic.localContinueAudiobookCandidates(
            pool, downloaded.mapTo(HashSet()) { it.id }, ctx, activeBookLibraryIds, session.selectedBooksLibrary.value?.id,
        )
    }

    private fun localContinueEpisodeCandidates(ctx: ContinueContext): List<AbsPodcastEpisodeListItem> {
        val pool = AbsPodcastEpisodeListItem.dedupeRows(
            _startShelves.value.flatMap { it.podcastEpisodes } + cachedInProgress?.podcastEpisodes.orEmpty() +
                model.downloadStatus.downloadedEpisodes(),
        )
        return HomeShelfLogic.localContinueEpisodeCandidates(pool, ctx, activePodcastLibraryIds, session.resolvedPodcastLibraryId())
    }

    // MARK: - Cache / LocalStore

    /** iOS: `applyCachedStartDashboard` — gecachter Snapshot + Continue aus lokalem Fortschritt. */
    private suspend fun applyCachedStartDashboard() {
        val store = session.currentLocalLibraryStore()
        val libId = session.selectedBooksLibrary.value?.id
        if (_startShelves.value.isEmpty() && store != null && libId != null) {
            val cached = runCatching { store.fetchHomeShelves(libId) }.getOrNull()
            if (cached != null) {
                val visible = cached.filter { isStartCategoryEnabled(it.category) }
                if (visible.isNotEmpty()) {
                    setShelves(visible)
                    updateCategoryList(cached)
                }
            }
        }
        applyHomeContinueCacheFromLocalStore()
        repairContinueListeningShelfFromLocalProgressOnly()
        syncContinueListeningShelvesWithProgress()
    }

    /** iOS: `applyHomeContinueCacheFromLocalStore`. */
    private suspend fun applyHomeContinueCacheFromLocalStore() {
        if (offline) return
        val store = session.currentLocalLibraryStore()
        val payload = store?.let { runCatching { it.fetchItemsInProgressPayload(limit = 80) }.getOrNull() }
        if (payload != null) {
            if (cachedInProgress == null) cachedInProgress = payload
            mergeServerItemsIntoContinue(payload, "continue-from-items-in-progress")
        }
        refreshEbookContinueReadingShelf()
    }

    /** iOS: `persistHomeShelvesToLocalStore` — nie offline (Downloads-Sicht würde den Server-Snapshot ersetzen). */
    private fun persistHomeShelvesToLocalStore() {
        if (offline) return
        val store = session.currentLocalLibraryStore() ?: return
        val libraryId = session.selectedBooksLibrary.value?.id ?: Keys.librarySelectionNone
        val sections = _startShelves.value
        if (sections.isNotEmpty()) session.setHasCachedLaunchArtifacts(true)
        val generation = ++persistGeneration
        model.scope.launch {
            if (generation != persistGeneration) return@launch
            runCatching { store.replaceHomeShelves(libraryId, sections) }
                .onFailure { Log.w(TAG, "replaceHomeShelves failed: ${it.message}") }
        }
    }

    /** iOS: `homeShelvesCacheLibraryIds(primary:)`. */
    private fun homeShelvesCacheLibraryIds(primary: String): List<String> {
        val ids = mutableListOf<String>()
        primary.swiftTrim().takeIf { it.isNotEmpty() }?.let { ids.add(it) }
        session.activeBooksLibraryIds.value.map { it.swiftTrim() }.filter { it.isNotEmpty() && it !in ids }.forEach { ids.add(it) }
        return ids
    }

    /** iOS: `restoreHomeLaunchStateFromLocalStore` / async Kaltstart-Teil von `scheduleHomeLaunchRestoreFromLocalStore`. */
    private suspend fun restoreHomeFromLocalStore(store: LocalLibraryStore, booksLibraryId: String?) {
        val progress = runCatching { store.fetchAllProgress() }.getOrNull().orEmpty()
        localProgressLoaded = true
        val libId = booksLibraryId?.swiftTrim().orEmpty()
        var cached: List<AbsStartShelfSection>? = null
        if (libId.isNotEmpty() && libId != Keys.librarySelectionNone) {
            for (id in homeShelvesCacheLibraryIds(libId)) {
                val shelves = runCatching { store.fetchHomeShelves(id) }.getOrNull()
                if (!shelves.isNullOrEmpty()) {
                    cached = shelves
                    break
                }
            }
        }
        cachedInProgress = runCatching { store.fetchItemsInProgressPayload(limit = 200) }.getOrNull()
        session.setHasCachedLaunchArtifacts(progress.isNotEmpty() || !cached.isNullOrEmpty())
        if (progress.isNotEmpty()) applyUserProgress(progress, persistToDisk = false)
        if (offline) {
            applyOfflineStartDashboard()
            return
        }
        if (cached != null && applyRestoredHomeShelvesFromCache(cached)) return
        // iOS: `applyLaunchHomeContinueAndEbookCache`.
        if (libId.isNotEmpty() && libId != Keys.librarySelectionNone) applyHomeContinueCacheFromLocalStore()
        repairContinueListeningShelfFromLocalProgressOnly()
        if (_progressByItemId.value.isNotEmpty()) syncContinueListeningShelvesWithProgress()
        updateCategoryList(cached.orEmpty())
    }

    /** iOS: `applyRestoredHomeShelvesFromCache` — Finished-Filter nur mit geladenem Fortschritt. */
    private suspend fun applyRestoredHomeShelvesFromCache(parsed: List<AbsStartShelfSection>): Boolean {
        val visible = parsed.filter { isStartCategoryEnabled(it.category) }
        if (visible.isEmpty()) return false
        setShelves(visible)
        updateCategoryList(parsed)
        applyHomeContinueCacheFromLocalStore()
        repairContinueListeningShelfFromLocalProgressOnly()
        if (_progressByItemId.value.isNotEmpty()) syncContinueListeningShelvesWithProgress()
        return _startShelves.value.isNotEmpty()
    }

    // MARK: - Offline-Home

    /**
     * iOS: `applyOfflineStartDashboard` / `rebuildOfflineStartDashboardShelvesOnly` — nur Continue aus
     * heruntergeladenen Titeln (Downloads über [AppModel.downloadStatus]).
     */
    private fun applyOfflineStartDashboard() {
        val ctx = continueContext()
        val shelves = mutableListOf<AbsStartShelfSection>()
        if (isStartCategoryEnabled(HomeShelfLogic.homeContinueCategory)) {
            val downloadedBooks = model.downloadStatus.downloadedBooks()
            val downloadedIds = downloadedBooks.mapTo(HashSet()) { it.id }
            val books = HomeShelfLogic.localContinueAudiobookCandidates(
                downloadedBooks + _startBooks.value, downloadedIds, ctx, activeBookLibraryIds, session.selectedBooksLibrary.value?.id,
            ).filter { it.id in downloadedIds }
            val downloadedEps = model.downloadStatus.downloadedEpisodes()
            val epIds = downloadedEps.mapTo(HashSet()) { DownloadStatusSource.storageId(it.libraryItemId, it.episodeId) }
            val eps = HomeShelfLogic.localContinueEpisodeCandidates(downloadedEps, ctx, activePodcastLibraryIds, session.resolvedPodcastLibraryId())
                .filter { DownloadStatusSource.storageId(it.libraryItemId, it.episodeId) in epIds }
            if (books.isNotEmpty() || eps.isNotEmpty()) shelves.add(HomeShelfLogic.makeContinueShelf("offline-continue", books, eps))
        }
        // Fortschritt noch nicht geladen → aufgebaute Regale nicht wegwerfen; der Restore ruft erneut.
        if (shelves.isEmpty() && _startShelves.value.isNotEmpty() && _progressByItemId.value.isEmpty() && !localProgressLoaded) return
        setShelves(shelves)
        updateCategoryList(shelves)
    }

    /** Hook für den Download-Port: Downloads geändert → Offline-Home neu aufbauen bzw. Continue ergänzen. */
    fun refreshDownloadedShelf() {
        if (offline) applyOfflineStartDashboard() else repairContinueListeningShelfFromLocalProgressOnly()
    }

    // MARK: - Continue reading (eBooks)

    /** iOS: `ebookDisplayProgressFraction`. */
    fun ebookDisplayProgressFraction(libraryItemId: String): Double? {
        val id = libraryItemId.swiftTrim()
        return HomeShelfLogic.ebookDisplayFraction(_progressByItemId.value[id]?.ebookProgress, EbookLocalStore.loadProgressFraction(id))
    }

    /**
     * iOS: `refreshEbookContinueReadingShelf` / `injectEbookContinueReadingShelfIfNeeded` — Regal
     * „Continue reading“ aus Server-`ebookProgress` und lokalen Readium-Fraktionen.
     */
    suspend fun refreshEbookContinueReadingShelf() {
        if (offline) return
        val category = HomeShelfLogic.continueEbooksCategory
        if (session.selectedBooksLibrary.value == null || !isStartCategoryEnabled(category)) {
            stripShelf(category)
            return
        }
        val books = buildEbookContinueReadingBooks()
        if (books.isEmpty()) {
            stripShelf(category)
            return
        }
        val existing = _startShelves.value.firstOrNull { it.category == category }
        if (existing != null && existing.books.map { it.id } == books.map { it.id }) return
        val section = AbsStartShelfSection(
            id = "continue-ebooks-local",
            category = category,
            displayTitle = AbsStartShelfLocalization.displayTitle(category, ""),
            books = books,
        )
        val shelves = HomeShelfLogic.upsertLocalOnlyShelf(section, _startShelves.value, effectiveOrder())
        setShelves(shelves)
        updateCategoryList(shelves)
        persistHomeShelvesToLocalStore()
    }

    private suspend fun buildEbookContinueReadingBooks(): List<AbsBook> {
        val ids = LinkedHashSet<String>()
        _progressByItemId.value.values.filter { it.episodeId == null }.forEach { ids.add(it.libraryItemId.swiftTrim()) }
        ids.addAll(withContext(Dispatchers.IO) { EbookLocalStore.inProgressLibraryItemIds() })
        val fractions = HashMap<String, Double>()
        val candidates = ArrayList<AbsBook>()
        val store = session.currentLocalLibraryStore()
        for (id in ids) {
            if (id.isEmpty()) continue
            val f = ebookDisplayProgressFraction(id) ?: continue
            if (f <= 0.005 || f >= 0.995) continue
            val book = bookForEbookContinue(id, store) ?: continue
            if (book.isPlayableAudiobook) continue
            fractions[id] = f
            candidates.add(book)
        }
        return candidates.sortedByDescending { fractions[it.id] ?: 0.0 }.take(14)
    }

    /** iOS: `bookForEbookContinue` (Katalog, Start-Union, LocalStore). */
    private suspend fun bookForEbookContinue(id: String, store: LocalLibraryStore?): AbsBook? {
        _startBooks.value.firstOrNull { it.id == id }?.let { return it }
        model.downloadStatus.downloadedBooks().firstOrNull { it.id == id }?.let { return it }
        if (store == null) return null
        return runCatching { store.fetchBook(id) ?: store.fetchBookDetail(id) }.getOrNull()
    }

    private fun stripShelf(category: String) {
        if (_startShelves.value.none { it.category == category }) return
        setShelves(_startShelves.value.filter { it.category != category })
        persistHomeShelvesToLocalStore()
    }

    // MARK: - New episodes

    /** iOS: `refreshNewestEpisodesShelf` — `recent-episodes` der Primary-Podcast-Bibliothek. */
    suspend fun refreshNewestEpisodesShelf() {
        if (offline) return
        refreshStartSettingsCategoryListLabels()
        val category = HomeShelfLogic.newestEpisodesCategory
        val lib = session.selectedPodcastLibrary.value
        if (lib == null || !isStartCategoryEnabled(category)) {
            stripShelf(category)
            return
        }
        val episodes = loadNewestEpisodes(lib)
        if (episodes.isEmpty()) {
            stripShelf(category)
            return
        }
        val existing = _startShelves.value.firstOrNull { it.category == category }
        if (existing != null && existing.podcastEpisodes.map { it.id } == episodes.map { it.id }) return
        val section = AbsStartShelfSection(
            id = "newest-episodes-local",
            category = category,
            displayTitle = AbsStartShelfLocalization.displayTitle(category, ""),
            podcastEpisodes = episodes,
        )
        val shelves = HomeShelfLogic.upsertLocalOnlyShelf(section, _startShelves.value, effectiveOrder())
        setShelves(shelves)
        updateCategoryList(shelves)
        persistHomeShelvesToLocalStore()
    }

    private suspend fun loadNewestEpisodes(lib: AbsLibrary): List<AbsPodcastEpisodeListItem> {
        val c = session.client
        if (session.mayUseServerNetwork && session.isNetworkReachable.value && c != null) {
            try {
                val (res, _) = c.recentPodcastEpisodes(lib.id, page = 0, limit = 14)
                val rows = AbsPodcastEpisodeListItem.dedupeRows(res.episodes.mapNotNull { AbsPodcastEpisodeListItem.fromDTO(it, libraryId = lib.id) })
                if (rows.isNotEmpty()) return rows.take(14)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Fallback unten (offline / Fehler).
            }
        }
        val store = session.currentLocalLibraryStore()
        val cachedEpisodes = store?.let { runCatching { it.fetchPodcastEpisodes(lib.id) }.getOrNull() }?.items.orEmpty()
        return HomeShelfLogic.newestEpisodeCandidates(cachedEpisodes + model.downloadStatus.downloadedEpisodes(), lib.id)
    }

    // MARK: - SessionParticipant

    override fun hasCachedBootstrapContent(): Boolean = _startShelves.value.isNotEmpty()

    override suspend fun hasCachedContinueInLocalStore(store: LocalLibraryStore, booksLibraryId: String?): Boolean {
        val libId = booksLibraryId ?: return false
        val shelves = runCatching { store.fetchHomeShelves(libId) }.getOrNull().orEmpty()
        if (shelves.any { HomeShelfLogic.isContinueCategory(it.category) && (it.hasBooks || it.hasPodcastEpisodes) }) return true
        val payload = runCatching { store.fetchItemsInProgressPayload(limit = 1) }.getOrNull()
        return payload != null && (payload.books.isNotEmpty() || payload.podcastEpisodes.isNotEmpty())
    }

    override suspend fun restoreFromLocalStore(store: LocalLibraryStore, booksLibraryId: String?) =
        restoreHomeFromLocalStore(store, booksLibraryId)

    override suspend fun loadStartDashboard(skipAuthorizeRefresh: Boolean, force: Boolean): ContinueRefreshAttemptResult =
        loadStartDashboard(skipAuthorizeRefresh, force, forPullToRefresh = false, replaceContinueShelves = false)

    override fun continueShelfMissingOpenProgress(): Boolean {
        repairContinueListeningShelfFromLocalProgressOnly()
        syncContinueListeningShelvesWithProgress()
        return HomeShelfLogic.hasOpenProgressExpectingContinue(_progressByItemId.value) &&
            !HomeShelfLogic.continueShelfHasVisibleItems(_startShelves.value, disabled)
    }

    override fun onAuthorizeUser(user: AbsUser, persistToDisk: Boolean) = applyUserProgress(user.mediaProgress, persistToDisk)

    override fun onSessionCleared(clearCredentials: Boolean) {
        dashboardGeneration++
        persistGeneration++
        postProcessingJob?.cancel()
        setShelves(emptyList())
        _progressByItemId.value = emptyMap()
        blockedContinueKeys.clear()
        cachedInProgress = null
        localProgressLoaded = false
        replaceContinueOnNextLoad = false
        // SessionStore löscht `startDisabledCategories`/`homeBrowseCategory` aus den Prefs (wie iOS).
        _startDisabledCategories.value = emptySet()
        _homeBrowseCategory.value = AbsStartShelfLocalization.homeBrowseContinueSectionID
        _startSettingsCategoryList.value = HomeShelfLogic.categoryList(effectiveOrder(), emptyList())
    }

    override suspend fun reloadAfterAccountSwitch() {
        loadStartDashboard(skipAuthorizeRefresh = false, force = true)
    }

    override fun onBooksLibrarySelected(library: AbsLibrary, changed: Boolean) {
        if (!changed) return
        val store = session.currentLocalLibraryStore()
        model.scope.launch {
            if (store != null) {
                setShelves(emptyList())
                restoreHomeFromLocalStore(store, library.id)
            }
            loadStartDashboard(force = true)
        }
    }

    override fun onBooksLibraryCleared() {
        model.scope.launch { loadStartDashboard(force = true) }
    }

    override fun onPodcastLibrarySelected(library: AbsLibrary, changed: Boolean) {
        refreshStartSettingsCategoryListLabels()
        if (changed) model.scope.launch { refreshNewestEpisodesShelf() }
    }

    override fun onPodcastLibraryCleared() {
        refreshStartSettingsCategoryListLabels()
        model.scope.launch { refreshNewestEpisodesShelf() }
    }

    override fun onActiveLibrariesChanged() {
        model.scope.launch { loadStartDashboard(force = true) }
    }

    override fun onLibrariesResolved() {
        refreshStartSettingsCategoryListLabels()
        model.scope.launch { refreshNewestEpisodesShelf() }
    }

    override suspend fun bootstrapLocalSessionOnly() = applyOfflineStartDashboard()

    override suspend fun onOfflineHomeModeExited() {
        // iOS: Offline→Online baut Continue neu aus dem Server auf.
        replaceContinueOnNextLoad = true
    }

    private fun loadDisabledCategories(): Set<String> = ActiveLibraryIdsStore.decode(Prefs.string(Keys.startDisabledCategories)).toSet()

    private fun loadCategoryOrder(): List<String> = ActiveLibraryIdsStore.decode(Prefs.string(Keys.startCategoryOrder))

    private companion object {
        const val TAG = "HomeStore"
    }
}
