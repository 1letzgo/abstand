package de.letzgo.abstand.reader

import android.os.SystemClock
import de.letzgo.abstand.data.AbsAudioTrack
import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.logic.AlignmentInputWord
import de.letzgo.abstand.logic.EbookAlignmentStore
import de.letzgo.abstand.logic.EbookNarrationJump
import de.letzgo.abstand.logic.EbookTrackLookup
import de.letzgo.abstand.logic.EbookTranscriptCoverage
import de.letzgo.abstand.logic.PlayerTranscriptLibrary
import de.letzgo.abstand.logic.speech.SpeechTranscriptionLocaleResolver
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.player.TrackTimeline
import de.letzgo.abstand.transcript.PlayerTranscriptPrefetcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator

/**
 * iOS: `EbookNarrationSync` (EbookReadAlong.swift) — Hörposition ↔ eBook-Wort über den Abgleich, in beide
 * Richtungen: Reader-Button (Hörposition → Seite) und Player-Button (Leseposition → Hörposition). Beides
 * nur auf Knopfdruck — bewusst kein automatischer Seiten-Sync.
 */
object EbookNarrationSync {
    const val NOTICE_NO_READING_POSITION = "Open the ebook first — there's no reading position yet."
    const val NOTICE_EBOOK_NOT_MATCHED =
        "This part of the ebook can't be matched to the audiobook yet. If its transcript is still being prepared, try again later."

    /** iOS: `alignmentMaxAge` — so lange gilt ein Abgleich im Speicher. */
    private const val ALIGNMENT_MAX_AGE_MS = 30_000L
    private val memo = HashMap<String, Pair<EbookTrackLookup, Long>>()
    private val locales = HashMap<String, String>()

    private val player: PlaybackController get() = PlaybackController.shared(AppModel.shared.appContext)

    private class Context(val bookId: String, val localeId: String, val tracks: TrackTimeline)

    /**
     * iOS: `narrationWord(player:index:)` — zuletzt gesprochenes eBook-Wort an der Hörposition. Steht sie vor
     * dem ersten erkannten Wort des Tracks (Kapitelansage, Musik), gilt das letzte Wort des Vortracks. `null`,
     * wenn die Hörposition nicht im Transkript liegt oder das nächste ausgerichtete Wort zu weit weg ist.
     */
    suspend fun narrationWord(built: EbookTextIndexProvider.Built): Int? {
        val c = context() ?: return null
        val position = player.playbackGlobalPosition()
        val trackIndex = c.tracks.trackIndex(position)
        val offset = c.tracks.trackStarts.getOrNull(trackIndex) ?: return null
        val duration = c.tracks.tracks[trackIndex].duration
        if (position < offset || position > offset + maxOf(0.0, duration)) return null
        val lookup = lookup(trackIndex, c, built) ?: return null
        val local = position - offset
        return when (val narrated = lookup.narratedWord(local)) {
            is EbookTrackLookup.NarratedWord.Word -> narrated.position
            EbookTrackLookup.NarratedWord.Unavailable -> null
            EbookTrackLookup.NarratedWord.BeforeFirstWord -> {
                if (trackIndex <= 0 || local > EbookTrackLookup.MAX_GAP_SECONDS) return null
                lookup(trackIndex - 1, c, built)?.trailingWord(c.tracks.tracks[trackIndex - 1].duration)
            }
        }
    }

    /**
     * iOS: `playbackPosition(forEbookWord:player:index:)` — globale Hörposition, ab der das Wort gesprochen
     * wird. Zuerst der anteilig passende Track, sonst alle der Reihe nach; zwischen zwei Tracks beginnt die
     * Wiedergabe am Anfang des nächsten. Liegt ein Track ohne Transkript davor: keine (falsche) Antwort.
     */
    suspend fun playbackPosition(word: Int, built: EbookTextIndexProvider.Built): Double? {
        val c = context() ?: return null
        val tracks = c.tracks
        val total = tracks.trackStarts.last() + tracks.tracks.last().duration
        val estimate = word.toDouble() / maxOf(1, built.index.words.size).toDouble() * total
        val guess = tracks.trackIndex(estimate)
        lookup(guess, c, built)?.localTime(word)?.let { return tracks.trackStarts[guess] + it }

        // Ein Track ohne (vollständiges) Transkript: dahinter ist offen, wo das Wort liegt — lieber keine
        // Antwort als eine falsche.
        var previousTailCovered = true
        for (i in tracks.tracks.indices) {
            val duration = tracks.tracks[i].duration
            val lookup = lookup(i, c, built)
            if (lookup == null) {
                previousTailCovered = false
                continue
            }
            val range = lookup.alignment.ebookWordRange
            if (range == null) {
                // Transkript ohne eBook-Treffer (Musik, Vorspann): durchlässig, solange es vollständig ist.
                previousTailCovered = previousTailCovered && lookup.isFullyCovered(duration)
                continue
            }
            if (word < range.first) {
                if (!previousTailCovered) return null
                return lookup.leadingWordTime?.let { tracks.trackStarts[i] + it }
            }
            if (word <= range.last) return lookup.localTime(word)?.let { tracks.trackStarts[i] + it }
            previousTailCovered = lookup.trailingWord(duration) != null
        }
        return null
    }

    /** iOS: `PlayerJumpTarget` — berechnetes Ziel, bestätigt wird erst danach. */
    data class PlayerJumpTarget(val bookId: String, val position: Double, val chapterTitle: String?)

    /** iOS: `playerReadingTarget(model:)` — Ziel oder die Meldung für den Nutzer. */
    suspend fun playerReadingTarget(): Result<PlayerJumpTarget> {
        val p = player
        val book = p.activeBook.value
        if (book == null || p.activePlaybackEpisodeId.value != null) return notice(EbookNarrationJump.NOTICE_EBOOK_UNREADABLE)
        if (!p.isUsingLocalTrackFiles) return notice(EbookNarrationJump.NOTICE_DOWNLOAD_REQUIRED)
        val locator = EbookReadingAnchorStore.anchor(book.id) ?: ReadiumReaderService.loadLocator(book.id, AbsEbookFormat.epub)
            ?: return notice(NOTICE_NO_READING_POSITION)
        val built = EbookTextIndexProvider.index(book.id) ?: return notice(EbookNarrationJump.NOTICE_EBOOK_UNREADABLE)
        val word = built.wordPosition(locator) ?: return notice(EbookNarrationJump.NOTICE_EBOOK_UNREADABLE)
        val position = playbackPosition(word, built) ?: run {
            PlayerTranscriptPrefetcher.scheduleIfNeeded()
            return notice(NOTICE_EBOOK_NOT_MATCHED)
        }
        val chapter = p.sortedChapters.lastOrNull { position >= it.start }?.title
        return Result.success(PlayerJumpTarget(book.id, position, chapter))
    }

    /** iOS: `jumpPlayer(to:model:)` — nach der Rückfrage springen und abspielen; Buch gewechselt → nichts. */
    fun jumpPlayer(target: PlayerJumpTarget) {
        val p = player
        if (p.activeBook.value?.id != target.bookId) return
        p.seek(target.position)
        if (!p.isPlaying.value) p.play()
    }

    class NoticeException(message: String) : Exception(message)

    private fun <T> notice(message: String): Result<T> = Result.failure(NoticeException(message))

    private suspend fun context(): Context? {
        val p = player
        val book = p.activeBook.value ?: return null
        val language = book.media.metadata.language
        val key = language ?: ""
        val localeId = locales[key] ?: runCatching {
            SpeechTranscriptionLocaleResolver.bcp47(SpeechTranscriptionLocaleResolver.resolve(language).locale)
        }.getOrNull()?.also { locales[key] = it } ?: return null
        // iOS `transcriptionStorageId` (Hörbuch ohne Folge → Buch-ID).
        val bookId = book.id.swiftTrim()
        val tracks = localTrackTimeline(bookId, book.media.tracks.orEmpty())
        if (tracks.isEmpty) return null
        return Context(bookId, localeId, tracks)
    }

    /** Wie der Player bei lokaler Wiedergabe: Tracks aus dem `download.json`, sonst aus dem Item. */
    private suspend fun localTrackTimeline(bookId: String, fallback: List<AbsAudioTrack>): TrackTimeline = withContext(Dispatchers.IO) {
        val manifest = DownloadManager.existingDownloadFolder(bookId)?.let { AbsDownloadManifest.load(it) }
        val fromManifest = manifest?.tracks?.takeIf { it.isNotEmpty() }?.map { row ->
            AbsAudioTrack(index = row.index, startOffset = row.startOffset, duration = row.duration, title = row.title, ino = null)
        }
        TrackTimeline(fromManifest ?: fallback)
    }

    /**
     * iOS: `EbookAlignmentStore.lookup(forTrack:…)` — Abgleich samt Abdeckung des Transkripts. Im Speicher
     * 30 s gültig (iOS prüft stattdessen den Datei-Stempel des Transkripts — hier bewusst nicht portiert).
     */
    private suspend fun lookup(trackIndex: Int, c: Context, built: EbookTextIndexProvider.Built): EbookTrackLookup? {
        val key = EbookAlignmentStore.key(c.bookId, trackIndex, c.localeId, built.index)
        memo[key]?.let { (lookup, at) -> if (SystemClock.elapsedRealtime() - at < ALIGNMENT_MAX_AGE_MS) return lookup }
        val account = AppModel.shared.session.cacheAccountDir()
        val cache = PlayerTranscriptLibrary.cache(c.bookId, trackIndex, c.localeId, account) ?: return null
        val cached = cache.allWords
        if (cached.isEmpty()) return null
        val input = cached.map { AlignmentInputWord(it.t, it.s, it.e) }
        val alignment = withContext(Dispatchers.Default) {
            EbookAlignmentStore.loadOrBuild(account, c.bookId, trackIndex, c.localeId, input, built.index)
        }
        val result = EbookTrackLookup(alignment, EbookTranscriptCoverage.of(cache))
        memo[key] = result to SystemClock.elapsedRealtime()
        return result
    }
}

/**
 * iOS: `EbookReadingAnchorStore` — letzte Leseposition je eBook mit dem Text des ersten sichtbaren Elements,
 * genauer als der gespeicherte Locator. Nur im Speicher; Grundlage für „Jump to ebook position".
 */
object EbookReadingAnchorStore {
    private val anchors = HashMap<String, Locator>()

    fun anchor(libraryItemId: String): Locator? = anchors[libraryItemId]

    /** Aktuelle Seite samt Text ihres ersten sichtbaren Elements merken. */
    @OptIn(ExperimentalReadiumApi::class)
    suspend fun capture(navigator: EpubNavigatorFragment, locator: Locator, libraryItemId: String) {
        val visible = runCatching { navigator.firstVisibleElementLocator() }.getOrNull()
        anchors[libraryItemId] = if (visible != null && visible.href == locator.href) locator.copy(text = visible.text) else locator
    }
}
