package de.letzgo.abstand.reader

import android.util.Log
import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.data.AbsProgressPatch
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.store.EbookLocalStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * iOS: eBook-Fortschrittsteil von `AppModel` (`scheduleEbookProgressSync`, `flushEbookProgressSync`,
 * `pushPendingEbookProgressSyncIfSafe`, `patchPreservingAudiobookFields`, `ebookResumeProgressionForReader`,
 * `serverEbookFractionForReader`, `markEbookAsFinished`, `resetEbookReadingProgress`).
 *
 * Server kennt nur `ebookProgress` (Bruchteil); der seitengenaue Readium-Locator bleibt lokal
 * ([EbookLocalStore]). Main-Thread-gebunden wie der iOS-`@MainActor`.
 */
object EbookProgressSync {
    private const val TAG = "EbookProgressSync"

    private val model: AppModel get() = AppModel.shared

    private data class Pending(val libraryItemId: String, val fraction: Double)

    private var pending: Pending? = null
    private val lastSyncedFractionByItemId = HashMap<String, Double>()
    /** Mark-as-finished / Reset, bis `/authorize` nachzieht (iOS `pendingEbookProgressOverrideByItemId`). */
    private val pendingOverrideByItemId = HashMap<String, Double>()
    private var syncJob: Job? = null
    /** Zustand gehört zu einem Account — bei Accountwechsel verwerfen (iOS: `clearInMemorySessionState`). */
    private var epoch: Long? = null

    private fun ensureEpoch() {
        val current = model.session.accountSessionEpoch.value
        if (epoch == current) return
        epoch = current
        pending = null
        lastSyncedFractionByItemId.clear()
        pendingOverrideByItemId.clear()
        syncJob?.cancel()
        syncJob = null
    }

    private val player: PlaybackController get() = PlaybackController.shared(model.appContext)

    // MARK: - Reader-Fortschritt

    /** Lesefortschritt (0…1): Hilfs-Cache sofort; Server-PATCH nur wenn Hörbuch-Fortschritt nicht gefährdet wird. */
    fun schedule(libraryItemId: String, fraction: Double) {
        ensureEpoch()
        val id = libraryItemId.swiftTrim()
        val f = fraction.coerceIn(0.0, 1.0)
        val decision = EbookProgressRules.syncDecision(
            libraryItemId = id,
            fraction = f,
            isMarkedFinished = id.isNotEmpty() && EbookLocalStore.isMarkedFinished(id),
            lastSyncedFraction = lastSyncedFractionByItemId[id],
            deferForActivePlaySession = shouldDeferServerPatch(id),
        )
        when (decision) {
            EbookProgressRules.SyncDecision.Ignore, EbookProgressRules.SyncDecision.KeepFinished -> return
            else -> EbookLocalStore.saveProgressFraction(f, id)
        }
        if (decision == EbookProgressRules.SyncDecision.LocalOnly) return
        pending = Pending(id, f)
        // Während aktiver Hörbuch-Play-Session kein PATCH — wartet auf Pause/Close.
        if (decision == EbookProgressRules.SyncDecision.Deferred) return
        syncJob?.cancel()
        syncJob = model.scope.launch {
            delay(EbookProgressRules.SYNC_DEBOUNCE_MS)
            pushPendingIfSafe()
        }
    }

    /** Reader geschlossen: letzten Stand senden (ohne `/authorize` — der überschreibt laufenden Hör-Fortschritt). */
    fun flush() {
        ensureEpoch()
        syncJob?.cancel()
        syncJob = null
        model.scope.launch {
            pushPendingIfSafe()
            model.home.refreshEbookContinueReadingShelf()
        }
    }

    private suspend fun pushPendingIfSafe() {
        val p = pending ?: return
        if (shouldDeferServerPatch(p.libraryItemId)) return
        val session = model.session
        if (!session.mayUseServerNetwork || !session.isNetworkReachable.value) return
        val c = session.client ?: return
        val patch = patchPreservingAudiobookFields(p.libraryItemId, p.fraction) ?: return
        try {
            c.patchProgress(p.libraryItemId, patch = patch)
            lastSyncedFractionByItemId[p.libraryItemId] = p.fraction
            if (pending == p) pending = null
            mergeEbookProgressIntoRow(p.libraryItemId, p.fraction)
            model.home.refreshEbookContinueReadingShelf()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "eBook progress flush failed: ${e.message}")
        }
    }

    /** Hörbuch-Play-Session läuft — eBook-PATCH würde Session/Fortschritt stören. */
    private fun shouldDeferServerPatch(libraryItemId: String): Boolean {
        val p = player
        return p.isRemotePlaySessionActive &&
            p.activeBook.value?.id == libraryItemId &&
            p.activePlaybackEpisodeId.value?.swiftTrim().isNullOrEmpty()
    }

    private fun isActivelyPlayingBook(libraryItemId: String): Boolean {
        val p = player
        return p.activeBook.value?.id == libraryItemId && p.activePlaybackEpisodeId.value?.swiftTrim().isNullOrEmpty()
    }

    /** Titel mit Hörbuch-Spur: PATCH nur mit `currentTime`/`duration` — sonst `null` (nur lokaler Cache). */
    private suspend fun itemNeedsAudiobookFields(libraryItemId: String): Boolean {
        if (isActivelyPlayingBook(libraryItemId)) return true
        model.home.progressByItemId.value[libraryItemId]?.let { row ->
            if (row.episodeId == null && (row.isFinished || row.currentTime > 0.5 || row.duration > 0)) return true
        }
        if (model.home.startBooks.value.any { it.id == libraryItemId && it.isPlayableAudiobook }) return true
        if (model.downloadStatus.downloadedBooks().any { it.id == libraryItemId && it.isPlayableAudiobook }) return true
        val store = model.session.currentLocalLibraryStore() ?: return false
        val book = runCatching { withContext(Dispatchers.IO) { store.fetchBook(libraryItemId) } }.getOrNull()
        return book?.isPlayableAudiobook == true
    }

    private data class AudiobookFields(val currentTime: Double, val duration: Double, val progress: Double, val isFinished: Boolean)

    private fun audiobookFields(libraryItemId: String): AudiobookFields? {
        if (isActivelyPlayingBook(libraryItemId)) {
            val dur = player.totalDuration.value
            if (dur <= 0) return null
            val pos = maxOf(0.0, player.globalPosition.value)
            return AudiobookFields(pos, dur, (pos / dur).coerceIn(0.0, 1.0), false)
        }
        val row = model.home.progressByItemId.value[libraryItemId]?.takeIf { it.episodeId == null } ?: return null
        if (!(row.currentTime > 0.5 || row.duration > 0 || row.isFinished)) return null
        val dur = row.duration
        val prog = if (dur > 0) (if (row.progress > 0) row.progress else row.currentTime / dur).coerceIn(0.0, 1.0) else row.progress.coerceIn(0.0, 1.0)
        return AudiobookFields(row.currentTime, dur, prog, row.isFinished)
    }

    /**
     * Hörbuch-Felder beim eBook-PATCH mitschicken — sonst setzt ABS `currentTime` zurück. Reine
     * eBook-Items: nur `ebookProgress`. Hörbuch+EPUB ohne bekannte Hörposition: kein PATCH (`null`).
     */
    private suspend fun patchPreservingAudiobookFields(libraryItemId: String, ebookProgress: Double): AbsProgressPatch? {
        if (!itemNeedsAudiobookFields(libraryItemId)) return AbsProgressPatch(ebookProgress = ebookProgress)
        val fields = audiobookFields(libraryItemId) ?: return null
        return AbsProgressPatch(
            currentTime = fields.currentTime,
            duration = fields.duration.takeIf { it > 0 },
            progress = fields.progress.takeIf { fields.duration > 0 },
            isFinished = fields.isFinished,
            ebookProgress = ebookProgress,
        )
    }

    /** Nur `ebookProgress` in der bestehenden Zeile aktualisieren — Hörbuch-Felder unangetastet. */
    private fun mergeEbookProgressIntoRow(libraryItemId: String, fraction: Double?) {
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty()) return
        if (fraction != null) EbookLocalStore.saveProgressFraction(fraction, id)
        val existing = model.home.progressByItemId.value[id]
        val next = when {
            existing != null -> existing.copy(ebookProgress = fraction ?: existing.ebookProgress)
            fraction != null -> AbsUserMediaProgress(
                libraryItemId = id, episodeId = null, duration = 0.0, progress = 0.0, currentTime = 0.0,
                isFinished = false, lastUpdate = null, ebookProgress = fraction,
            )
            else -> return
        }
        model.home.applyProgressUpdate(next)
    }

    // MARK: - Öffnen

    /** iOS: `ebookDisplayProgressFraction` (mit ausstehendem Override). */
    fun displayFraction(libraryItemId: String): Double? {
        ensureEpoch()
        val id = libraryItemId.swiftTrim()
        return EbookProgressRules.displayFraction(
            pendingOverrideByItemId[id],
            model.home.progressByItemId.value[id]?.ebookProgress,
            EbookLocalStore.loadProgressFraction(id),
        )
    }

    /** iOS: `ebookResumeProgressionForReader` — Maximum aus Server und On-Device-Cache, lokal gemerkt. */
    fun resumeProgression(libraryItemId: String): Double? {
        val f = EbookProgressRules.resumeProgression(
            model.home.progressByItemId.value[libraryItemId]?.ebookProgress,
            EbookLocalStore.loadProgressFraction(libraryItemId),
        ) ?: return null
        EbookLocalStore.saveProgressFraction(f, libraryItemId)
        return f
    }

    /** iOS: `serverEbookFractionForReader`. */
    fun serverFractionForReader(libraryItemId: String): Double? {
        ensureEpoch()
        val id = libraryItemId.swiftTrim()
        return EbookProgressRules.serverFractionForReader(
            model.home.progressByItemId.value[id]?.ebookProgress,
            hasPendingSyncForItem = pending?.libraryItemId == id,
        )
    }

    // MARK: - Aktionen

    /** iOS: `markEbookAsFinished` — 100 %, Reader schließen, aus Continue reading nehmen. */
    suspend fun markFinished(libraryItemId: String, format: AbsEbookFormat) {
        ensureEpoch()
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty()) return
        syncJob?.cancel()
        syncJob = null
        pending = null
        pendingOverrideByItemId[id] = 1.0
        EbookLocalStore.clearReadiumLocator(id, format)
        EbookLocalStore.saveProgressFraction(1.0, id, markFinished = true)
        lastSyncedFractionByItemId[id] = 1.0
        mergeEbookProgressIntoRow(id, 1.0)
        if (EbookReaderLauncher.session.value?.libraryItemId == id) EbookReaderLauncher.close()
        model.home.refreshEbookContinueReadingShelf()
        if (!pushOverride(id, 1.0)) return
        val serverF = model.home.progressByItemId.value[id]?.ebookProgress
        if (serverF != null && serverF >= 0.995) pendingOverrideByItemId.remove(id)
        model.home.refreshEbookContinueReadingShelf()
    }

    /** iOS: `resetEbookReadingProgress` — Lesezeichen zurücksetzen: Server-PATCH + Hilfs-Cache löschen. */
    suspend fun reset(libraryItemId: String, format: AbsEbookFormat) {
        ensureEpoch()
        val id = libraryItemId.swiftTrim()
        if (id.isEmpty()) return
        syncJob?.cancel()
        syncJob = null
        pending = null
        pendingOverrideByItemId[id] = 0.0
        lastSyncedFractionByItemId.remove(id)
        EbookLocalStore.clearReadiumLocator(id, format)
        EbookLocalStore.clearProgressFraction(id)
        mergeEbookProgressIntoRow(id, 0.0)
        model.home.refreshEbookContinueReadingShelf()
        if (!pushOverride(id, 0.0)) return
        val serverF = model.home.progressByItemId.value[id]?.ebookProgress
        if (serverF == null || serverF <= 0.005) pendingOverrideByItemId.remove(id)
        // `/authorize` kann noch den alten Stand liefern — Override hält Anzeige/Merge auf 0.
        mergeEbookProgressIntoRow(id, 0.0)
        EbookLocalStore.clearProgressFraction(id)
        model.home.refreshEbookContinueReadingShelf()
    }

    /** PATCH + `/authorize`; `true`, wenn beides durchlief. */
    private suspend fun pushOverride(id: String, fraction: Double): Boolean {
        val session = model.session
        if (!session.mayUseServerNetwork || !session.isNetworkReachable.value) return false
        val c = session.client ?: return false
        val patch = patchPreservingAudiobookFields(id, fraction) ?: return false
        return try {
            c.patchProgress(id, patch = patch)
            session.refreshProgressFromServer()
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "eBook progress sync failed: ${e.message}")
            false
        }
    }
}
