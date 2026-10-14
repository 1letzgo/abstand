package de.letzgo.abstand.model

import android.util.Log
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsUser
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.store.EbookLocalStore
import de.letzgo.abstand.store.LocalLibraryStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer

/**
 * iOS: Fortschritts- und Lesezeichen-Teil von `AppModel` (`progressByItemId`, `bookmarks`,
 * `applyUserProgress`/`mergedUserMediaProgress`, lokale Schutz-Keys „fertig"/„verworfen"/„ausstehend",
 * `persistProgressToLocalStore`). Quelle der Wahrheit für Karten, Detail, Home und den Player-Host.
 *
 * Schutz-Keys liegen je Server **und** Benutzer in den Prefs (iOS: `progressGuardStorageKey`); auf
 * Android als JSON-Strings (Prefs kennen keine Arrays/Dictionaries).
 */
class ProgressStore(private val model: AppModel) : SessionParticipant {
    private val session get() = model.session

    private val _progressByItemId = MutableStateFlow<Map<String, AbsUserMediaProgress>>(emptyMap())
    /** iOS: `progressByItemId` — Schlüssel = `progressLookupKey`. */
    val progressByItemId: StateFlow<Map<String, AbsUserMediaProgress>> = _progressByItemId.asStateFlow()

    private val _bookmarks = MutableStateFlow<List<AbsAudioBookmark>>(emptyList())
    /** iOS: `bookmarks` (alle Hörbücher, sortiert nach Item + Zeit). */
    val bookmarks: StateFlow<List<AbsAudioBookmark>> = _bookmarks.asStateFlow()

    private val _changes = MutableSharedFlow<String>(extraBufferCapacity = 64)
    /**
     * Geänderte Progress-Keys (lokal markiert, verworfen, Server-Merge: `"*"`). Home hängt hier
     * `syncContinueListeningShelvesWithProgress` an (iOS ruft es direkt auf).
     */
    val changes: SharedFlow<String> = _changes.asSharedFlow()

    /** iOS: `pendingLocalProgressSyncKeys` (persistiert je Server + Benutzer). */
    var pendingLocalProgressSyncKeys: Set<String> = emptySet()
        private set
    private var localFinishedProgressKeys: Set<String> = emptySet()
    private var discardedProgressAtMs: Map<String, Long> = emptyMap()
    /** eBook „Mark as read"/Reset: gewünschter Wert, bis der Server nachzieht. */
    private val pendingEbookProgressOverrideByItemId = HashMap<String, Double>()
    private var localProgressLoaded = false

    private val persistMutex = Mutex()
    private var progressPersistGeneration = 0L
    private var bookmarksPersistGeneration = 0L

    // MARK: - Lesen

    /** iOS: `progressByItemId[key]`. */
    fun progress(key: String): AbsUserMediaProgress? = _progressByItemId.value[key]

    /** iOS: `bookmarks(for:)` — nach Zeit sortiert. */
    fun bookmarks(libraryItemId: String): List<AbsAudioBookmark> =
        _bookmarks.value.filter { it.libraryItemId == libraryItemId }.sortedBy { it.time }

    /** iOS: `isLocallyMarkedFinished(progressKey:)`. */
    fun isLocallyMarkedFinished(progressKey: String): Boolean {
        val k = progressKey.swiftTrim()
        if (k.isEmpty()) return false
        if (k in localFinishedProgressKeys) return true
        return _progressByItemId.value[k]?.isFinished == true
    }

    /** iOS: `isProgressKeyDiscarded`. */
    fun isProgressKeyDiscarded(key: String): Boolean = key in discardedProgressAtMs

    /** iOS: `ebookDisplayProgressFraction(libraryItemId:)` — Override, sonst max(Server, Gerät). */
    fun ebookDisplayProgressFraction(libraryItemId: String): Double? {
        val id = libraryItemId.swiftTrim()
        pendingEbookProgressOverrideByItemId[id]?.let { pending ->
            val c = pending.coerceIn(0.0, 1.0)
            if (c >= 0.995) return 1.0
            return if (c > 0.005) c else null
        }
        val serverF = _progressByItemId.value[id]?.ebookProgress
        val localF = EbookLocalStore.loadProgressFraction(id)
        val f = listOfNotNull(serverF, localF).maxOrNull() ?: return null
        if (!(f > 0.005)) return null
        val c = f.coerceIn(0.0, 1.0)
        return if (c >= 0.995) 1.0 else c
    }

    // MARK: - Laden / Anwenden

    /** iOS: `ensureLocalProgressLoaded` — Schutz-Keys + Room-Progress einmalig mergen. */
    suspend fun ensureLocalProgressLoaded() {
        if (localProgressLoaded) return
        loadGuardKeys()
        val store = session.currentLocalLibraryStore() ?: return
        localProgressLoaded = true
        val list = withContext(Dispatchers.IO) { runCatching { store.fetchAllProgress() }.getOrDefault(emptyList()) }
        if (list.isNotEmpty()) applyUserProgress(list, persistToDisk = false)
    }

    /** iOS: `applyUserProgress(_:persistToDisk:)`. */
    fun applyUserProgress(list: List<AbsUserMediaProgress>?, persistToDisk: Boolean = true) {
        var strippedDiscarded = false
        val next = HashMap(_progressByItemId.value)
        for (p in list.orEmpty()) {
            val key = p.progressLookupKey
            if (isProgressKeyDiscarded(key)) {
                if (isStaleDiscardedServerRow(p)) {
                    next.remove(key)
                    strippedDiscarded = true
                    continue
                }
                clearDiscardedProgressKey(key)
            }
            if (p.isFinished) clearLocallyFinishedProgressKey(key)
            next[key] = mergedUserMediaProgress(next[key], p)
        }
        _progressByItemId.value = next
        _changes.tryEmit("*")
        if (!persistToDisk && !strippedDiscarded) return
        persistProgressToLocalStore()
    }

    /** iOS: `applyUserBookmarks`. */
    fun applyUserBookmarks(list: List<AbsAudioBookmark>?, persistToDisk: Boolean = true) {
        _bookmarks.value = sortedBookmarks(list.orEmpty())
        if (persistToDisk) persistBookmarksToLocalStore()
    }

    /**
     * Für den Player-Host (iOS: Kern von `recordActivePlaybackProgressLocally`): Zeile setzen, als
     * Einzel-Zeile in Room schreiben (`upsertProgress`, nie `replaceAllProgress`), optional als
     * „noch nicht am Server" merken.
     */
    fun upsertProgressLocally(progress: AbsUserMediaProgress, markPendingServerSync: Boolean) {
        val key = progress.progressLookupKey
        _progressByItemId.value = _progressByItemId.value + (key to progress)
        if (markPendingServerSync) setPendingKeys(pendingLocalProgressSyncKeys + key)
        _changes.tryEmit(key)
        val store = session.currentLocalLibraryStore() ?: return
        session.setHasCachedLaunchArtifacts(true)
        model.scope.launch(Dispatchers.IO) {
            runCatching { store.upsertProgress(listOf(progress)) }.onFailure { Log.w(TAG, "upsertProgress failed: ${it.message}") }
        }
    }

    /** iOS: `pendingLocalProgressSyncKeys.remove(key)`. */
    fun clearPendingLocalProgressSync(progressKey: String) {
        if (progressKey in pendingLocalProgressSyncKeys) setPendingKeys(pendingLocalProgressSyncKeys - progressKey)
    }

    fun markPendingLocalProgressSync(progressKey: String) {
        if (progressKey !in pendingLocalProgressSyncKeys) setPendingKeys(pendingLocalProgressSyncKeys + progressKey)
    }

    // MARK: - Lokale Markierungen

    /** iOS: `applyLocalMarkFinished`. */
    fun applyLocalMarkFinished(libraryItemId: String, episodeId: String?, bookDuration: Double?) {
        val key = progressKey(libraryItemId, episodeId)
        markProgressKeyLocallyFinished(key)
        val existing = _progressByItemId.value[key]
        val dur = maxOf(existing?.duration ?: 0.0, bookDuration ?: 0.0, existing?.currentTime ?: 0.0, 1.0)
        val now = System.currentTimeMillis()
        val ep = episodeId?.swiftTrim().orEmpty()
        val row = AbsUserMediaProgress(
            mediaProgressServerId = existing?.mediaProgressServerId,
            libraryItemId = libraryItemId,
            episodeId = ep.ifEmpty { null },
            duration = dur,
            progress = 1.0,
            currentTime = dur,
            isFinished = true,
            lastUpdate = maxOf(now, (existing?.lastUpdate ?: 0) + 1),
            ebookProgress = existing?.ebookProgress,
            ebookLocation = existing?.ebookLocation,
        )
        _progressByItemId.value = _progressByItemId.value + (key to row)
        _changes.tryEmit(key)
        persistProgressToLocalStore()
    }

    /** iOS: `applyLocalMarkUnfinished`. */
    fun applyLocalMarkUnfinished(libraryItemId: String, episodeId: String?) {
        val key = progressKey(libraryItemId, episodeId)
        clearLocallyFinishedProgressKey(key)
        val now = System.currentTimeMillis()
        val ep = episodeId?.swiftTrim().orEmpty()
        val existing = _progressByItemId.value[key]
        val row = existing?.copy(isFinished = false, lastUpdate = maxOf(now, (existing.lastUpdate ?: 0) + 1))
            ?: AbsUserMediaProgress(
                libraryItemId = libraryItemId, episodeId = ep.ifEmpty { null }, duration = 0.0, progress = 0.0,
                currentTime = 0.0, isFinished = false, lastUpdate = now,
            )
        _progressByItemId.value = _progressByItemId.value + (key to row)
        _changes.tryEmit(key)
        persistProgressToLocalStore()
    }

    /** iOS: `reconcileProgressAfterMarkFinished`. */
    fun reconcileProgressAfterMarkFinished(libraryItemId: String, episodeId: String?, bookDuration: Double?) {
        val key = progressKey(libraryItemId, episodeId)
        if (key in localFinishedProgressKeys) {
            if (_progressByItemId.value[key]?.isFinished != true) {
                applyLocalMarkFinished(libraryItemId, episodeId, bookDuration)
            } else {
                persistProgressToLocalStore()
            }
            return
        }
        if (_progressByItemId.value[key]?.isFinished == true) {
            persistProgressToLocalStore()
            return
        }
        _progressByItemId.value = _progressByItemId.value - key
        clearLocallyFinishedProgressKey(key)
        _changes.tryEmit(key)
        persistProgressToLocalStore()
    }

    /** iOS: Discard-Teil von `discardBookProgress` — Zeile weg, Schutz gegen Wiedereinspielen. */
    suspend fun discardProgressLocally(key: String) {
        markProgressKeyDiscarded(key)
        _progressByItemId.value = _progressByItemId.value - key
        clearPendingLocalProgressSync(key)
        clearLocallyFinishedProgressKey(key)
        if (Prefs.string(Keys.lastPlayedItemId) == key) Prefs.remove(Keys.lastPlayedItemId)
        _changes.tryEmit(key)
        persistProgressToLocalStoreNow()
    }

    /** iOS: `clearLocallyFinishedProgressKey` (öffentlich für Neustart nach „Fertig"). */
    fun clearLocallyFinishedProgressKey(key: String) {
        val k = key.swiftTrim()
        if (k.isEmpty() || k !in localFinishedProgressKeys) return
        localFinishedProgressKeys = localFinishedProgressKeys - k
        saveStringSet(Keys.localFinishedProgressKeys, localFinishedProgressKeys)
    }

    /** iOS: `pendingEbookProgressOverrideByItemId` setzen/aufheben (Mark as read / Reset). */
    fun setEbookProgressOverride(libraryItemId: String, fraction: Double?) {
        if (fraction == null) pendingEbookProgressOverrideByItemId.remove(libraryItemId)
        else pendingEbookProgressOverrideByItemId[libraryItemId] = fraction
        _changes.tryEmit(libraryItemId)
        // Karten beobachten die Map — neue Instanz erzwingt Neuzeichnen.
        _progressByItemId.value = HashMap(_progressByItemId.value)
    }

    // MARK: - Lesezeichen

    /** iOS: `upsertBookmark` + Persist. */
    fun upsertBookmark(bookmark: AbsAudioBookmark) {
        val list = _bookmarks.value.filterNot { it.libraryItemId == bookmark.libraryItemId && it.time == bookmark.time } + bookmark
        _bookmarks.value = sortedBookmarks(list)
        persistBookmarksToLocalStore()
    }

    fun removeBookmark(bookmark: AbsAudioBookmark) {
        _bookmarks.value = _bookmarks.value.filterNot { it.libraryItemId == bookmark.libraryItemId && it.time == bookmark.time }
        persistBookmarksToLocalStore()
    }

    // MARK: - SessionParticipant

    override fun onSessionActivated() {
        localProgressLoaded = false
        loadGuardKeys()
    }

    override suspend fun restoreFromLocalStore(store: LocalLibraryStore, booksLibraryId: String?) {
        loadGuardKeys()
        val (progress, marks) = withContext(Dispatchers.IO) {
            runCatching { store.fetchAllProgress() }.getOrDefault(emptyList()) to
                runCatching { store.fetchAllBookmarks() }.getOrDefault(emptyList())
        }
        localProgressLoaded = true
        if (progress.isNotEmpty()) applyUserProgress(progress, persistToDisk = false)
        if (marks.isNotEmpty() && _bookmarks.value.isEmpty()) _bookmarks.value = sortedBookmarks(marks)
    }

    override fun onAuthorizeUser(user: AbsUser, persistToDisk: Boolean) {
        user.mediaProgress?.let { applyUserProgress(it, persistToDisk) }
        user.bookmarks?.let { applyUserBookmarks(it, persistToDisk) }
    }

    override fun onSessionCleared(clearCredentials: Boolean) {
        _progressByItemId.value = emptyMap()
        _bookmarks.value = emptyList()
        pendingLocalProgressSyncKeys = emptySet()
        localFinishedProgressKeys = emptySet()
        discardedProgressAtMs = emptyMap()
        pendingEbookProgressOverrideByItemId.clear()
        localProgressLoaded = false
    }

    override suspend fun bootstrapLocalSessionOnly() = ensureLocalProgressLoaded()

    // MARK: - Merge (iOS `mergedUserMediaProgress`)

    private fun isActivelyPlaying(p: AbsUserMediaProgress): Boolean {
        val player = PlaybackController.sharedOrNull() ?: return false
        val active = player.activeBook.value ?: return false
        if (active.id != p.libraryItemId) return false
        val activeEp = player.activePlaybackEpisodeId.value?.swiftTrim().orEmpty()
        return activeEp == p.episodeId?.swiftTrim().orEmpty() && player.isPlaying.value
    }

    private fun mergedUserMediaProgress(existing: AbsUserMediaProgress?, incoming: AbsUserMediaProgress): AbsUserMediaProgress {
        fun finish(base: AbsUserMediaProgress): AbsUserMediaProgress = mergedEbookProgress(incoming, base)
        val key = incoming.progressLookupKey
        if (key in localFinishedProgressKeys) {
            if (incoming.isFinished) return finish(incoming)
            if (existing?.isFinished == true) return finish(existing)
            val dur = maxOf(existing?.duration ?: 0.0, incoming.duration, existing?.currentTime ?: 0.0, 1.0)
            return finish(
                AbsUserMediaProgress(
                    mediaProgressServerId = existing?.mediaProgressServerId ?: incoming.mediaProgressServerId,
                    libraryItemId = incoming.libraryItemId,
                    episodeId = incoming.episodeId,
                    duration = dur,
                    progress = 1.0,
                    currentTime = dur,
                    isFinished = true,
                    lastUpdate = maxOf(existing?.lastUpdate ?: 0, incoming.lastUpdate ?: 0, System.currentTimeMillis()),
                    ebookProgress = incoming.ebookProgress ?: existing?.ebookProgress,
                    ebookLocation = incoming.ebookLocation ?: existing?.ebookLocation,
                ),
            )
        }
        existing ?: return finish(incoming)
        if (key in pendingLocalProgressSyncKeys) {
            if (existing.isFinished != incoming.isFinished) return finish(existing)
            val localTs = existing.lastUpdate ?: 0
            val serverTs = incoming.lastUpdate ?: 0
            if (existing.currentTime + 1 >= incoming.currentTime || localTs >= serverTs) return finish(existing)
        }
        if (incoming.isFinished != existing.isFinished) {
            if (isActivelyPlaying(existing) || isActivelyPlaying(incoming)) {
                return finish(if (existing.isFinished) incoming else existing)
            }
            if (!existing.isFinished && (existing.lastUpdate ?: 0) >= (incoming.lastUpdate ?: 0)) return finish(existing)
            if (existing.isFinished && !incoming.isFinished) return finish(existing)
            return finish(incoming)
        }
        val t0 = existing.lastUpdate ?: 0
        val t1 = incoming.lastUpdate ?: 0
        if (t0 > t1) return finish(existing)
        if (t1 > t0) return finish(incoming)
        return finish(if (existing.currentTime >= incoming.currentTime) existing else incoming)
    }

    /** iOS: `mergedApplyingServerEbookProgress` + `resolvedEbookProgressFraction`. */
    private fun mergedEbookProgress(incoming: AbsUserMediaProgress, base: AbsUserMediaProgress): AbsUserMediaProgress {
        val id = base.libraryItemId
        val resolved: Double? = pendingEbookProgressOverrideByItemId[id]?.let { pending ->
            val c = pending.coerceIn(0.0, 1.0)
            if (c >= 0.995) 1.0 else c.takeIf { it > 0.001 }
        } ?: run {
            val f = listOfNotNull(base.ebookProgress, incoming.ebookProgress, EbookLocalStore.loadProgressFraction(id)).maxOrNull()
            f?.coerceIn(0.0, 1.0)?.let { c -> if (c >= 0.995) 1.0 else c.takeIf { it > 0.001 } }
        }
        resolved ?: return base
        return base.copy(ebookProgress = resolved, ebookLocation = incoming.ebookLocation ?: base.ebookLocation)
    }

    // MARK: - Schutz-Keys (je Server + Benutzer)

    /** iOS: `progressGuardStorageKey(base:)`. */
    private fun guardKey(base: String): String {
        val u = AbsApiClient.normalizeServerURL(session.serverURL.value).orEmpty()
        if (u.isEmpty()) return base
        val uid = session.sessionUserId.swiftTrim().ifEmpty { Prefs.string(Keys.sessionUserId)?.swiftTrim().orEmpty() }
        return if (uid.isEmpty()) "$base.$u" else "$base.$u.$uid"
    }

    private fun loadGuardKeys() {
        localFinishedProgressKeys = loadStringSet(Keys.localFinishedProgressKeys)
        pendingLocalProgressSyncKeys = pendingLocalProgressSyncKeys + loadStringSet(Keys.pendingLocalProgressSyncKeys)
        val now = System.currentTimeMillis()
        val raw = Prefs.string(guardKey(Keys.discardedProgressKeys))
        val loaded = raw?.let {
            runCatching { AbsJson.decoder.decodeFromString(MapSerializer(String.serializer(), Long.serializer()), it) }.getOrNull()
                ?: runCatching { AbsJson.decoder.decodeFromString(ListSerializer(String.serializer()), it).associateWith { now } }.getOrNull()
        }.orEmpty()
        discardedProgressAtMs = loaded.filterValues { now - it < DISCARDED_MAX_AGE_MS }
    }

    private fun loadStringSet(base: String): Set<String> {
        val raw = Prefs.string(guardKey(base)) ?: return emptySet()
        return runCatching { AbsJson.decoder.decodeFromString(ListSerializer(String.serializer()), raw).toSet() }.getOrDefault(emptySet())
    }

    private fun saveStringSet(base: String, set: Set<String>) {
        Prefs.setString(guardKey(base), AbsJson.encoder.encodeToString(ListSerializer(String.serializer()), set.toList()))
    }

    private fun setPendingKeys(keys: Set<String>) {
        pendingLocalProgressSyncKeys = keys
        saveStringSet(Keys.pendingLocalProgressSyncKeys, keys)
    }

    private fun markProgressKeyLocallyFinished(key: String) {
        val k = key.swiftTrim()
        if (k.isEmpty()) return
        localFinishedProgressKeys = localFinishedProgressKeys + k
        saveStringSet(Keys.localFinishedProgressKeys, localFinishedProgressKeys)
    }

    private fun persistDiscarded() {
        Prefs.setString(
            guardKey(Keys.discardedProgressKeys),
            AbsJson.encoder.encodeToString(MapSerializer(String.serializer(), Long.serializer()), discardedProgressAtMs),
        )
    }

    private fun markProgressKeyDiscarded(key: String) {
        val k = key.swiftTrim()
        if (k.isEmpty()) return
        discardedProgressAtMs = discardedProgressAtMs + (k to System.currentTimeMillis())
        persistDiscarded()
    }

    private fun clearDiscardedProgressKey(key: String) {
        val k = key.swiftTrim()
        if (k.isEmpty() || k !in discardedProgressAtMs) return
        discardedProgressAtMs = discardedProgressAtMs - k
        persistDiscarded()
    }

    /** iOS: `isStaleDiscardedServerRow`. */
    private fun isStaleDiscardedServerRow(row: AbsUserMediaProgress): Boolean {
        val discardedAt = discardedProgressAtMs[row.progressLookupKey] ?: return false
        val updated = row.lastUpdate?.takeIf { it > 0 } ?: return true
        return updated <= discardedAt + DISCARDED_CLOCK_SKEW_MS
    }

    // MARK: - Persistenz

    /** iOS: `persistProgressToLocalStore` — Voll-Snapshot, ältere Writes verlieren. */
    fun persistProgressToLocalStore() {
        val store = session.currentLocalLibraryStore() ?: return
        val generation = ++progressPersistGeneration
        val list = _progressByItemId.value.values.toList()
        if (list.isNotEmpty()) session.setHasCachedLaunchArtifacts(true)
        model.scope.launch(Dispatchers.IO) {
            persistMutex.withLock {
                if (generation != progressPersistGeneration) return@withLock
                try {
                    store.replaceAllProgress(list)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.w(TAG, "replaceAllProgress failed: ${e.message}")
                }
            }
        }
    }

    /** iOS: `persistProgressToLocalStoreNow` (Reset: synchron, vor weiteren Writes). */
    suspend fun persistProgressToLocalStoreNow() {
        val store = session.currentLocalLibraryStore() ?: return
        val generation = ++progressPersistGeneration
        val list = _progressByItemId.value.values.toList()
        withContext(Dispatchers.IO) {
            persistMutex.withLock {
                if (generation == progressPersistGeneration) runCatching { store.replaceAllProgress(list) }
            }
        }
    }

    private fun persistBookmarksToLocalStore() {
        val store = session.currentLocalLibraryStore() ?: return
        val generation = ++bookmarksPersistGeneration
        val list = _bookmarks.value
        model.scope.launch(Dispatchers.IO) {
            if (generation != bookmarksPersistGeneration) return@launch
            runCatching { store.replaceAllBookmarks(list) }.onFailure { Log.w(TAG, "replaceAllBookmarks failed: ${it.message}") }
        }
    }

    companion object {
        private const val TAG = "ProgressStore"
        private const val DISCARDED_MAX_AGE_MS = 30L * 24 * 60 * 60 * 1000
        private const val DISCARDED_CLOCK_SKEW_MS = 5_000L

        /** iOS: Progress-Key aus Item + optionaler Folge. */
        fun progressKey(libraryItemId: String, episodeId: String?): String {
            val ep = episodeId?.swiftTrim().orEmpty()
            return if (ep.isEmpty()) libraryItemId else "$libraryItemId-$ep"
        }

        /** iOS: Sortierung in `upsertBookmark` (Item, dann Zeit). */
        fun sortedBookmarks(list: List<AbsAudioBookmark>): List<AbsAudioBookmark> =
            list.sortedWith(compareBy<AbsAudioBookmark> { it.libraryItemId }.thenBy { it.time })
    }
}
