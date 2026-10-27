package de.letzgo.abstand.reader

import android.os.SystemClock
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.logic.EbookNarrationJump
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.shared.publication.Locator

/**
 * iOS: `EbookNarrationJumpController` (EbookReadAlong.swift) — Button im eBook-Reader: springt zur
 * Seite der aktuellen Hörposition und markiert die letzten 25 Wörter davor („wo war ich?" auch bei
 * pausiertem Hörbuch). Die Stelle kommt aus dem Abgleich Transkript ↔ eBook. Kein automatischer
 * Seiten-Sync (bewusst entfernt, siehe CLAUDE.md).
 */
class EbookNarrationJumpController(
    private val libraryItemId: String,
    private val scope: CoroutineScope,
    /** Aktueller EPUB-Navigator (kann nach Neuaufbau wechseln). */
    private val navigator: () -> EpubNavigatorFragment?,
    /** Markierungsfarbe (iOS `.systemYellow`). */
    private val highlightTint: Int,
) {
    private val _isBusy = MutableStateFlow(false)
    val isBusy: StateFlow<Boolean> = _isBusy.asStateFlow()

    /** Hinweis, wenn die Stelle nicht bestimmbar ist (Hörbuch nicht geladen, kein Transkript o. Ä.). */
    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    private val player: PlaybackController get() = PlaybackController.shared(AppModel.shared.appContext)
    private var built: EbookTextIndexProvider.Built? = null
    private var hasMarking = false
    private var lastProgrammaticNavigationAt: Long? = null
    private var job: Job? = null

    /**
     * iOS: `isAvailable` — zum eBook gibt es ein Hörbuch: dann steht der Button immer im Reader, auch wenn
     * der Player nichts oder ein anderes Buch geladen hat (es wird beim Tippen pausiert geladen).
     */
    fun isAvailable(activeBookId: String?, activeEpisodeId: String?): Boolean =
        isLoaded(activeBookId, activeEpisodeId) || hasAudiobook

    private fun isLoaded(activeBookId: String?, activeEpisodeId: String?): Boolean =
        activeBookId == libraryItemId && activeEpisodeId == null

    private val hasAudiobook: Boolean by lazy {
        AppModel.shared.catalog.lookupBookStub(libraryItemId)?.isPlayableAudiobook == true
    }

    fun dismissNotice() {
        _notice.value = null
    }

    fun jumpToNarration() {
        val p = player
        if (_isBusy.value || !isAvailable(p.activeBook.value?.id, p.activePlaybackEpisodeId.value) || navigator() == null) return
        _isBusy.value = true
        job = scope.launch {
            try {
                _notice.value = performJump()
            } finally {
                _isBusy.value = false
            }
        }
    }

    /** Vom Reader bei jeder Positionsänderung: blättert der Nutzer selbst weiter, ist die Markierung erledigt. */
    fun readerLocationDidChange() {
        if (!hasMarking) return
        val at = lastProgrammaticNavigationAt
        if (at != null && SystemClock.elapsedRealtime() - at < (EbookNarrationJump.PROGRAMMATIC_NAVIGATION_GRACE_SECONDS * 1000).toLong()) return
        clearMarking()
    }

    fun stop() {
        job?.cancel()
        clearMarking()
    }

    private fun clearMarking() {
        if (!hasMarking) return
        hasMarking = false
        val nav = navigator() ?: return
        scope.launch { nav.applyDecorations(emptyList(), EbookNarrationJump.MARKING_GROUP) }
    }

    /** `null` bei Erfolg, sonst die Meldung für den Nutzer. */
    private suspend fun performJump(): String? {
        if (!isLoaded(player.activeBook.value?.id, player.activePlaybackEpisodeId.value)) loadAudiobookPaused()?.let { return it }
        if (!player.isUsingLocalTrackFiles) return EbookNarrationJump.NOTICE_DOWNLOAD_REQUIRED
        val built = ensureIndex() ?: return EbookNarrationJump.NOTICE_EBOOK_UNREADABLE
        val end = narrationWord(built) ?: return EbookNarrationJump.NOTICE_NOT_MATCHED
        val marks = EbookNarrationJump.decorations(built.index, end)
        val decorations = marks.mapNotNull { mark ->
            val locator: Locator = built.locator(mark.segment, mark.text) ?: return@mapNotNull null
            Decoration(id = mark.id, locator = locator, style = Decoration.Style.Highlight(tint = highlightTint, isActive = false))
        }
        val first = decorations.firstOrNull() ?: return EbookNarrationJump.NOTICE_EBOOK_UNREADABLE
        val nav = navigator() ?: return EbookNarrationJump.NOTICE_EBOOK_UNREADABLE
        nav.applyDecorations(decorations, EbookNarrationJump.MARKING_GROUP)
        hasMarking = true
        lastProgrammaticNavigationAt = SystemClock.elapsedRealtime()
        nav.go(first.locator, animated = true)
        lastProgrammaticNavigationAt = SystemClock.elapsedRealtime()
        return null
    }

    /**
     * iOS: `loadAudiobookPaused()` — Hörbuch dieses eBooks pausiert laden (an seiner Hörposition). Ein
     * laufender anderer Titel wird nicht ungefragt ersetzt. `null` bei Erfolg.
     */
    private suspend fun loadAudiobookPaused(): String? {
        if (DownloadManager.existingDownloadFolder(libraryItemId) == null) return EbookNarrationJump.NOTICE_DOWNLOAD_REQUIRED
        if (player.isPlaying.value) return NOTICE_OTHER_TITLE_PLAYING
        AppModel.shared.player.playItem(libraryItemId, null, autoPlay = false)
        val deadline = SystemClock.elapsedRealtime() + PLAYER_LOAD_TIMEOUT_MS
        while (SystemClock.elapsedRealtime() < deadline) {
            if (isLoaded(player.activeBook.value?.id, player.activePlaybackEpisodeId.value) && player.isUsingLocalTrackFiles) return null
            delay(200)
        }
        return if (isLoaded(player.activeBook.value?.id, player.activePlaybackEpisodeId.value)) null else "The audiobook couldn't be loaded."
    }

    private suspend fun ensureIndex(): EbookTextIndexProvider.Built? {
        built?.let { return it }
        return EbookTextIndexProvider.index(libraryItemId).also { built = it }
    }

    private companion object {
        const val NOTICE_OTHER_TITLE_PLAYING = "Another title is playing. Pause it first to jump to this audiobook's position."
        /** iOS: `playerLoadTimeout`. */
        const val PLAYER_LOAD_TIMEOUT_MS = 8_000L
    }

    /** iOS: `EbookNarrationSync.narrationWord` — gemeinsame Logik in [EbookNarrationSync]. */
    private suspend fun narrationWord(built: EbookTextIndexProvider.Built): Int? = EbookNarrationSync.narrationWord(built)
}
