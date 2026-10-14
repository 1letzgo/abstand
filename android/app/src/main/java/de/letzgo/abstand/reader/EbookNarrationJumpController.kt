package de.letzgo.abstand.reader

import android.os.SystemClock
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsAudioTrack
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.logic.AlignmentInputWord
import de.letzgo.abstand.logic.EbookAlignmentStore
import de.letzgo.abstand.logic.EbookNarrationJump
import de.letzgo.abstand.logic.EbookTrackAlignment
import de.letzgo.abstand.logic.PlayerTranscriptLibrary
import de.letzgo.abstand.logic.speech.SpeechTranscriptionLocaleResolver
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.player.TrackTimeline
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
    private var localeId: String? = null
    private var hasMarking = false
    private var lastProgrammaticNavigationAt: Long? = null
    private var job: Job? = null

    /** iOS: `isAvailable` — nur sinnvoll, wenn genau dieses Hörbuch im Player geladen ist. */
    fun isAvailable(activeBookId: String?, activeEpisodeId: String?): Boolean =
        activeBookId == libraryItemId && activeEpisodeId == null

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

    private suspend fun ensureIndex(): EbookTextIndexProvider.Built? {
        built?.let { return it }
        return EbookTextIndexProvider.index(libraryItemId).also { built = it }
    }

    /** eBook-Wort an der aktuellen Hörposition (Abgleich des laufenden Tracks). */
    private suspend fun narrationWord(built: EbookTextIndexProvider.Built): Int? {
        val p = player
        val book = p.activeBook.value ?: return null
        val locale = localeId ?: runCatching {
            SpeechTranscriptionLocaleResolver.bcp47(SpeechTranscriptionLocaleResolver.resolve(book.media.metadata.language).locale)
        }.getOrNull()?.also { localeId = it } ?: return null
        // iOS `transcriptionStorageId` (Hörbuch ohne Folge → Buch-ID).
        val bookId = book.id.swiftTrim()
        val position = p.playbackGlobalPosition()
        val tracks = localTrackTimeline(bookId, book.media.tracks.orEmpty())
        if (tracks.isEmpty) return null
        val trackIndex = tracks.trackIndex(position)
        val offset = tracks.trackStarts.getOrNull(trackIndex) ?: return null
        val duration = tracks.tracks[trackIndex].duration
        if (position < offset || position > offset + maxOf(0.0, duration)) return null
        val alignment = alignment(trackIndex, bookId, locale, built) ?: return null
        return alignment.ebookWord(position - offset)
    }

    /** Wie der Player bei lokaler Wiedergabe: Tracks aus dem `download.json`, sonst aus dem Item. */
    private suspend fun localTrackTimeline(bookId: String, fallback: List<AbsAudioTrack>): TrackTimeline = withContext(Dispatchers.IO) {
        val manifest = DownloadManager.existingDownloadFolder(bookId)?.let { AbsDownloadManifest.load(it) }
        val fromManifest = manifest?.tracks?.takeIf { it.isNotEmpty() }?.map { row ->
            AbsAudioTrack(index = row.index, startOffset = row.startOffset, duration = row.duration, title = row.title, ino = null)
        }
        TrackTimeline(fromManifest ?: fallback)
    }

    /** iOS: `EbookAlignmentStore.alignment(forTrack:…, maxAge: 5)` — Speicher-Treffer 5 s gültig. */
    private suspend fun alignment(trackIndex: Int, bookId: String, localeId: String, built: EbookTextIndexProvider.Built): EbookTrackAlignment? {
        val key = EbookAlignmentStore.key(bookId, trackIndex, localeId, built.index)
        memo[key]?.let { (alignment, at) -> if (SystemClock.elapsedRealtime() - at < ALIGNMENT_MAX_AGE_MS) return alignment }
        val account = AppModel.shared.session.cacheAccountDir()
        val cached = PlayerTranscriptLibrary.cachedWords(bookId, trackIndex, localeId, account)
        if (cached.isEmpty()) return null
        val input = cached.map { AlignmentInputWord(it.t, it.s, it.e) }
        val result = withContext(Dispatchers.Default) {
            EbookAlignmentStore.loadOrBuild(account, bookId, trackIndex, localeId, input, built.index)
        }
        memo[key] = result to SystemClock.elapsedRealtime()
        return result
    }

    private companion object {
        const val ALIGNMENT_MAX_AGE_MS = 5_000L
        val memo = HashMap<String, Pair<EbookTrackAlignment, Long>>()
    }
}
