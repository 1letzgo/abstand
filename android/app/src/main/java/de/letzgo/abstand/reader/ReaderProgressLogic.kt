package de.letzgo.abstand.reader

import de.letzgo.abstand.data.AbsEbookFormat
import kotlin.math.abs
import kotlin.math.roundToInt

// Reine Reader-Logik (ohne Readium-Typen, JUnit-testbar): Fortschritts-Bruchteil, Beschriftung,
// buchweite Seitenschätzung, Server-Positions-Angebot und die Regeln des eBook-Fortschritts-Syncs.

/** iOS: `RenderedPageInfo` — gerenderte Spalten/Seiten im aktuellen EPUB-Abschnitt. */
data class RenderedPageInfo(val current: Int, val total: Int)

/** iOS: `BookPageProgress`. */
data class BookPageProgress(val current: Int, val total: Int, val percent: Int)

/** iOS: `ServerPositionOffer`. */
data class ServerPositionOffer(val serverFraction: Double, val localFraction: Double)

/** iOS: `ReadiumReaderProgressInfo` (ohne Readium-`Locator`: der Aufrufer reicht die Locations durch). */
object ReaderProgressInfo {
    /** iOS: `fraction(from:)` — `totalProgression`, sonst `progression`, sonst 0; auf 0…1 begrenzt. */
    fun fraction(totalProgression: Double?, progression: Double?): Double {
        totalProgression?.let { return it.coerceIn(0.0, 1.0) }
        progression?.let { return it.coerceIn(0.0, 1.0) }
        return 0.0
    }

    fun percent(fraction: Double): Int = (fraction * 100).roundToInt()

    /** iOS: `label(from:format:positionCount:bookPages:)`. */
    fun label(
        fraction: Double,
        format: AbsEbookFormat,
        position: Int?,
        positionCount: Int?,
        bookPages: BookPageProgress?,
    ): String {
        val pct = percent(fraction)
        return when (format) {
            AbsEbookFormat.epub ->
                if (bookPages != null) "Page ${bookPages.current} of ${bookPages.total} · ${bookPages.percent}%" else "$pct%"
            AbsEbookFormat.pdf ->
                if (position != null && positionCount != null && positionCount > 0) "Page $position of $positionCount" else "$pct %"
        }
    }

    /** iOS: `ReadiumReaderView.scrubProgressCaption`. */
    fun scrubCaption(scrub: Double, format: AbsEbookFormat, positionCount: Int?): String {
        val pct = percent(scrub)
        if (format == AbsEbookFormat.pdf && positionCount != null && positionCount > 1) {
            val page = (scrub * positionCount).roundToInt().coerceIn(1, positionCount)
            return "Page $page of $positionCount · $pct%"
        }
        return "$pct%"
    }
}

/**
 * iOS: `ReadiumReaderDelegate.bookWidePageProgress` — aus der Kapitel-Paginierung (JS) und dem Cache
 * aller besuchten Kapitel eine buchweite Seitenzahl schätzen. Bei Schriftgrößen-/Layoutwechsel
 * [invalidate] aufrufen.
 */
class EpubBookPageEstimator(readingOrderHrefs: List<String> = emptyList()) {
    private var hrefs: List<String> = readingOrderHrefs.map(::hrefKey)
    private val chapterPageTotalsByHref = HashMap<String, Int>()

    fun configure(readingOrderHrefs: List<String>) {
        hrefs = readingOrderHrefs.map(::hrefKey)
        chapterPageTotalsByHref.clear()
    }

    fun invalidate() = chapterPageTotalsByHref.clear()

    fun bookWidePageProgress(href: String, fraction: Double, chapterPages: RenderedPageInfo): BookPageProgress {
        val key = hrefKey(href)
        chapterPageTotalsByHref[key] = chapterPages.total
        val percent = ReaderProgressInfo.percent(fraction)
        val chapterIndex = hrefs.indexOf(key)
        if (hrefs.isEmpty() || chapterIndex < 0) {
            return BookPageProgress(chapterPages.current, chapterPages.total, percent)
        }
        val knownTotals = hrefs.mapNotNull { chapterPageTotalsByHref[it] }
        val average = maxOf(1, if (knownTotals.isEmpty()) chapterPages.total else knownTotals.sum() / knownTotals.size)
        val bookTotal = maxOf(1, hrefs.sumOf { chapterPageTotalsByHref[it] ?: average })
        val pagesBefore = hrefs.take(chapterIndex).mapNotNull { chapterPageTotalsByHref[it] }.sum()
        val fromChapter = pagesBefore + chapterPages.current
        val fromProgression = (fraction * bookTotal).roundToInt()
        val bookCurrent = maxOf(fromChapter, fromProgression).coerceIn(1, bookTotal)
        return BookPageProgress(bookCurrent, bookTotal, percent)
    }

    companion object {
        /** iOS: `hrefKey` — ohne `#fragment`. */
        fun hrefKey(href: String): String = href.substringBefore('#')
    }
}

/** Entscheidungen des eBook-Fortschritts (iOS: eBook-Teil von `AppModel`). */
object EbookProgressRules {
    /** So weit (Anteil am Buch) muss der Server vorn sein, damit das Angebot erscheint. */
    const val SERVER_POSITION_OFFER_THRESHOLD = 0.02

    /** Änderungen unter diesem Abstand zum zuletzt gesendeten Stand lösen keinen PATCH aus. */
    const val MIN_SYNC_DELTA = 0.003

    /** Entprellung vor dem PATCH (iOS: 450 ms). */
    const val SYNC_DEBOUNCE_MS = 450L

    /**
     * iOS: Ende von `loadNavigator` — lokaler Locator vorhanden, Server aber deutlich weiter:
     * Angebot statt stillem Öffnen der alten Seite.
     */
    fun serverPositionOffer(localLocatorFraction: Double?, serverFraction: Double?): ServerPositionOffer? {
        val local = localLocatorFraction ?: return null
        val server = serverFraction ?: return null
        return if (server - local >= SERVER_POSITION_OFFER_THRESHOLD) ServerPositionOffer(server, local) else null
    }

    /**
     * iOS: `serverEbookFractionForReader` — `null` bei fertig gelesen, ohne Stand oder wenn ein lokaler
     * Stand für dieses Buch noch nicht gesendet wurde (dann ist er der neuere).
     */
    fun serverFractionForReader(serverEbookProgress: Double?, hasPendingSyncForItem: Boolean): Double? {
        if (hasPendingSyncForItem) return null
        val f = serverEbookProgress ?: return null
        if (!f.isFinite() || f <= 0.005 || f >= 0.995) return null
        return minOf(1.0, f)
    }

    /** iOS: `ebookResumeProgressionForReader` — Maximum aus Server und lokalem Hilfs-Cache. */
    fun resumeProgression(serverFraction: Double?, localFraction: Double?): Double? {
        val f = listOfNotNull(serverFraction, localFraction).filter { it > 0.005 }.maxOrNull() ?: return null
        if (f >= 0.995) return null
        return f.coerceIn(0.0, 1.0)
    }

    /** iOS: Guard in `resolveInitialLocator` — Start/Ende ignorieren. */
    fun usableResumeProgression(raw: Double?): Double? {
        val r = raw ?: return null
        if (r <= 0.005 || r >= 0.995) return null
        return r.coerceIn(0.0, 1.0)
    }

    /** Positions-Index für einen Bruchteil (iOS-Fallback in `resolveInitialLocator`). */
    fun positionIndex(fraction: Double, positionCount: Int): Int {
        if (positionCount <= 1) return 0
        return (fraction * (positionCount - 1)).roundToInt().coerceIn(0, positionCount - 1)
    }

    enum class SyncDecision {
        /** Unter 0,1 % oder leere ID — nichts tun. */
        Ignore,
        /** Explizit gelesen markiert, Stand < 99,5 % — nicht überschreiben. */
        KeepFinished,
        /** Lokal gemerkt, Server kennt den Stand schon (Abstand < [MIN_SYNC_DELTA]). */
        LocalOnly,
        /** Lokal gemerkt und als ausstehend vorgemerkt; PATCH wartet auf das Ende der Play-Session. */
        Deferred,
        /** Lokal gemerkt, PATCH nach Entprellung. */
        Schedule,
    }

    /** iOS: `scheduleEbookProgressSync` — Entscheidung ohne Seiteneffekte. */
    fun syncDecision(
        libraryItemId: String,
        fraction: Double,
        isMarkedFinished: Boolean,
        lastSyncedFraction: Double?,
        deferForActivePlaySession: Boolean,
    ): SyncDecision {
        val f = fraction.coerceIn(0.0, 1.0)
        if (libraryItemId.isEmpty() || f <= 0.001) return SyncDecision.Ignore
        if (isMarkedFinished && f < 0.995) return SyncDecision.KeepFinished
        if (lastSyncedFraction != null && abs(lastSyncedFraction - f) < MIN_SYNC_DELTA) return SyncDecision.LocalOnly
        return if (deferForActivePlaySession) SyncDecision.Deferred else SyncDecision.Schedule
    }

    /** iOS: `ebookDisplayProgressFraction` mit ausstehendem Override (Mark as finished / Reset). */
    fun displayFraction(pendingOverride: Double?, serverFraction: Double?, localFraction: Double?): Double? {
        if (pendingOverride != null) {
            val c = pendingOverride.coerceIn(0.0, 1.0)
            if (c >= 0.995) return 1.0
            return if (c > 0.005) c else null
        }
        val f = listOfNotNull(serverFraction, localFraction).maxOrNull() ?: return null
        if (f <= 0.005) return null
        val c = f.coerceIn(0.0, 1.0)
        return if (c >= 0.995) 1.0 else c
    }
}
