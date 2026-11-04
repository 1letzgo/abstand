package de.letzgo.abstand.model

import android.util.Log
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsApiError
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsUser
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.PendingBookmarkChange
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
    /** iOS: `pendingBookmarkChanges` — Schlüssel `AbsAudioBookmark.id`, je Server + Benutzer persistiert. */
    private var pendingBookmarkChanges: Map<String, PendingBookmarkChange> = emptyMap()
    private var isFlushingPendingBookmarkChanges = false
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

    /** iOS: `applyUserBookmarks` — noch ausstehende lokale Änderungen bleiben über dem Server-/Cache-Stand erhalten. */
    fun applyUserBookmarks(list: List<AbsAudioBookmark>?, persistToDisk: Boolean = true) {
        _bookmarks.value = PendingBookmarkChange.overlaying(pendingBookmarkChanges.values, list.orEmpty())
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

    /**
     * iOS: `createBookmark` — zuerst lokal und dauerhaft vorgemerkt, dann an den Server; ohne Verbindung holt
     * [flushPendingBookmarkChanges] das später nach.
     * @return die Ablehnung, wenn der Server das Lesezeichen endgültig abgelehnt hat (z. B. Buch gelöscht), sonst `null`.
     */
    suspend fun createBookmark(libraryItemId: String, time: Int, title: String): Throwable? {
        val change = PendingBookmarkChange(PendingBookmarkChange.Kind.create, libraryItemId, time, title, System.currentTimeMillis())
        recordPendingBookmarkChange(change)
        return sendPendingBookmarkChanges().rejected[change.id]
    }

    /** iOS: `deleteBookmark` — wie [createBookmark] erst lokal, der Server folgt sofort oder beim nächsten Online-Gehen. */
    suspend fun deleteBookmark(bookmark: AbsAudioBookmark): Throwable? {
        val change = PendingBookmarkChange(PendingBookmarkChange.Kind.delete, bookmark.libraryItemId, bookmark.time, bookmark.title, bookmark.createdAt)
        recordPendingBookmarkChange(change)
        return sendPendingBookmarkChanges().rejected[change.id]
    }

    private fun recordPendingBookmarkChange(change: PendingBookmarkChange) {
        setPendingBookmarkChanges(pendingBookmarkChanges + (change.id to change))
        _bookmarks.value = PendingBookmarkChange.overlaying(listOf(change), _bookmarks.value)
        persistBookmarksToLocalStore()
    }

    /** iOS: `schedulePendingBookmarkFlushIfNeeded` — Online-Übergänge, Vordergrund, nach `/authorize`. */
    fun schedulePendingBookmarkFlushIfNeeded() {
        if (pendingBookmarkChanges.isEmpty() || isFlushingPendingBookmarkChanges) return
        model.scope.launch { flushPendingBookmarkChanges() }
    }

    /**
     * iOS: `flushPendingBookmarkChanges` — schickt Ausstehendes und gleicht danach per `/authorize` ab: Ein noch
     * laufendes älteres `/authorize` kennt die gerade gesendeten Änderungen nicht und würde sie sonst aus der Liste werfen.
     */
    suspend fun flushPendingBookmarkChanges() {
        if (sendPendingBookmarkChanges().sentAny) session.refreshProgressFromServer()
    }

    private class BookmarkSendResult(val sentAny: Boolean, val rejected: Map<String, Throwable>)

    /**
     * iOS: `sendPendingBookmarkChanges` — Einträge verschwinden erst nach Erfolg oder endgültiger Ablehnung; alles
     * andere (Netz, 5xx, 401) bleibt liegen und wird beim nächsten Anlass wiederholt.
     */
    private suspend fun sendPendingBookmarkChanges(): BookmarkSendResult {
        val c = session.client
        if (isFlushingPendingBookmarkChanges || c == null || pendingBookmarkChanges.isEmpty() ||
            !session.mayUseServerNetwork || !session.isNetworkReachable.value
        ) {
            return BookmarkSendResult(false, emptyMap())
        }
        isFlushingPendingBookmarkChanges = true
        var sentAny = false
        val rejected = HashMap<String, Throwable>()
        // Jeder Stand einmal pro Lauf — während des Laufs neu vorgemerkte Änderungen werden mit abgearbeitet.
        val attempted = HashSet<PendingBookmarkChange>()
        try {
            while (session.mayUseServerNetwork && session.client === c) {
                val change = pendingBookmarkChanges.values.filter { it !in attempted }.minByOrNull { it.id } ?: break
                attempted += change
                try {
                    val created = sendPendingBookmarkChange(change, c)
                    sentAny = true
                    // Inzwischen überholt (neuere Änderung, Account-Wechsel): Der neuere Stand zählt.
                    if (pendingBookmarkChanges[change.id] != change) continue
                    setPendingBookmarkChanges(pendingBookmarkChanges - change.id)
                    if (created != null) {
                        _bookmarks.value = sortedBookmarks(_bookmarks.value.filterNot { it.id == created.id } + created)
                        persistBookmarksToLocalStore()
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (isPermanentBookmarkRejection(e)) {
                        Log.w(TAG, "Bookmark change rejected: ${e.message}")
                        rejected[change.id] = e
                        if (pendingBookmarkChanges[change.id] != change) continue
                        setPendingBookmarkChanges(pendingBookmarkChanges - change.id)
                        if (change.kind == PendingBookmarkChange.Kind.create) {
                            _bookmarks.value = _bookmarks.value.filterNot { it.id == change.id }
                            persistBookmarksToLocalStore()
                        }
                    } else {
                        Log.i(TAG, "Bookmark sync deferred: ${e.message}")
                        // Server antwortet, mag aber nur diesen Eintrag nicht — die übrigen trotzdem versuchen.
                        if (e is AbsApiError.HttpStatus) continue
                        break
                    }
                }
            }
        } finally {
            isFlushingPendingBookmarkChanges = false
        }
        return BookmarkSendResult(sentAny, rejected)
    }

    /** @return das Lesezeichen laut Server, sobald es angelegt ist (`null` bei Löschen / unlesbarer Antwort). */
    private suspend fun sendPendingBookmarkChange(change: PendingBookmarkChange, c: AbsApiClient): AbsAudioBookmark? {
        when (change.kind) {
            PendingBookmarkChange.Kind.create -> return try {
                c.createBookmark(change.libraryItemId, change.time, change.title)
            } catch (e: AbsApiError.Decoding) {
                null // Server hat mit 2xx angenommen; der nächste `/authorize` liefert die Zeile.
            } catch (e: AbsApiError.EmptyBody) {
                null
            }
            PendingBookmarkChange.Kind.delete -> {
                try {
                    c.deleteBookmark(change.libraryItemId, change.time)
                } catch (e: AbsApiError.HttpStatus) {
                    // 404: schon weg (oder nur lokal vorgemerkt gewesen) — Ziel erreicht.
                    if (e.code != 404) throw e
                }
                return null
            }
        }
    }

    private fun setPendingBookmarkChanges(changes: Map<String, PendingBookmarkChange>) {
        pendingBookmarkChanges = changes
        val key = guardKey(Keys.pendingBookmarkChanges)
        if (changes.isEmpty()) {
            Prefs.remove(key)
        } else {
            Prefs.setString(key, AbsJson.encoder.encodeToString(ListSerializer(PendingBookmarkChange.serializer()), changes.values.toList()))
        }
    }

    /** iOS: `loadPendingBookmarkChanges` — persistierten Stand des aktiven Accounts dazuladen (Speicher gewinnt) und einblenden. */
    private fun loadPendingBookmarkChanges() {
        val raw = Prefs.string(guardKey(Keys.pendingBookmarkChanges)) ?: return
        val stored = runCatching { AbsJson.decoder.decodeFromString(ListSerializer(PendingBookmarkChange.serializer()), raw) }.getOrNull() ?: return
        pendingBookmarkChanges = stored.associateBy { it.id } + pendingBookmarkChanges
        _bookmarks.value = PendingBookmarkChange.overlaying(pendingBookmarkChanges.values, _bookmarks.value)
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
        // Nur Ausstehendes in der Liste zählt als „noch nichts geladen“.
        if (marks.isNotEmpty() && _bookmarks.value.all { it.id in pendingBookmarkChanges }) applyUserBookmarks(marks, persistToDisk = false)
    }

    override fun onAuthorizeUser(user: AbsUser, persistToDisk: Boolean) {
        user.mediaProgress?.let { applyUserProgress(it, persistToDisk) }
        // `sessionUserId` steht erst hier sicher fest — Ausstehendes dieses Accounts vor dem Merge laden.
        loadPendingBookmarkChanges()
        user.bookmarks?.let { applyUserBookmarks(it, persistToDisk) }
        // Server hat geantwortet: guter Moment, Ausstehendes nachzuschicken.
        schedulePendingBookmarkFlushIfNeeded()
    }

    override fun onSessionCleared(clearCredentials: Boolean) {
        _progressByItemId.value = emptyMap()
        _bookmarks.value = emptyList()
        // Nur der Speicher — der persistierte Stand bleibt für den nächsten Sync dieses Accounts erhalten.
        pendingBookmarkChanges = emptyMap()
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
        loadPendingBookmarkChanges()
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

        /** iOS: `isPermanentBookmarkRejection` — 4xx bleibt auch beim Wiederholen 4xx; Auth und Rate-Limits gehen vorüber. */
        fun isPermanentBookmarkRejection(error: Throwable): Boolean =
            error is AbsApiError.HttpStatus && error.code in 400..499 && error.code !in setOf(401, 403, 408, 429)

        /** iOS: Sortierung in `upsertBookmark` (Item, dann Zeit). */
        fun sortedBookmarks(list: List<AbsAudioBookmark>): List<AbsAudioBookmark> =
            list.sortedWith(compareBy<AbsAudioBookmark> { it.libraryItemId }.thenBy { it.time })
    }
}
