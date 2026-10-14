package de.letzgo.abstand.logic

import kotlin.math.ceil
import kotlin.math.floor

/** iOS: `PlayerTeleprompterLayout` (Maße in dp statt pt). */
data class PlayerTeleprompterLayout(
    val slotHeight: Double,
    val lineSpacing: Double,
    val fontSize: Double,
    /** Immer gerenderte Zeilen (Mitte ± Puffer). */
    val renderedLineCount: Int,
) {
    val linesBeforeCenter: Int get() = (renderedLineCount - 1) / 2
    val rowStride: Double get() = slotHeight + lineSpacing
    val stackHeight: Double get() = renderedLineCount * slotHeight + maxOf(0, renderedLineCount - 1) * lineSpacing
}

/**
 * iOS: `PlayerTeleprompterMetrics` — ohne `UserDefaults`: die gespeicherte Nutzergröße
 * ([FONT_SIZE_STORAGE_KEY]) liest/schreibt der Aufrufer und reicht sie herein.
 */
object PlayerTeleprompterMetrics {
    const val COLLAPSED_VISIBLE_LINE_COUNT = 9
    const val RENDERED_LINES_BEFORE_CENTER = 10
    const val RENDERED_LINE_COUNT = RENDERED_LINES_BEFORE_CENTER * 2 + 1
    const val CARD_CONTENT_PADDING = 14.0
    const val DEFAULT_LINE_SPACING = 0.0
    const val LINE_HEIGHT_FACTOR = 1.22
    const val FONT_SIZE_REDUCTION = 4.0
    const val DEFAULT_FONT_SIZE = 24.0
    const val MIN_FONT_SIZE = 14.0
    const val MAX_FONT_SIZE = 34.0
    const val FONT_SIZE_STEP = 2.0
    const val FONT_SIZE_STORAGE_KEY = "abstand_teleprompter_font_size"
    const val INACTIVE_LINE_TEXT_OPACITY = 0.32
    const val ACTIVE_LINE_TEXT_OPACITY = 0.65

    fun clampFontSize(size: Double): Double = minOf(MAX_FONT_SIZE, maxOf(MIN_FONT_SIZE, size))

    /** Automatische Schriftgröße aus Kartenbreite (9 Zeilen Referenz). */
    fun autoFontSize(sizingViewportHeight: Double): Double {
        val lineSpacing = DEFAULT_LINE_SPACING
        val sizingCount = COLLAPSED_VISIBLE_LINE_COUNT.toDouble()
        val gaps = sizingCount - 1
        val fitSize = if (sizingViewportHeight > gaps * lineSpacing) {
            (sizingViewportHeight - gaps * lineSpacing) / (sizingCount * LINE_HEIGHT_FACTOR)
        } else {
            DEFAULT_FONT_SIZE + FONT_SIZE_REDUCTION
        }
        return clampFontSize(fitSize - FONT_SIZE_REDUCTION)
    }

    val defaultLayout: PlayerTeleprompterLayout get() = layout(300.0)

    /** Nutzer-Schriftgröße schlägt gespeicherte Größe schlägt Auto-Fit. */
    fun layout(sizingViewportHeight: Double, userFontSize: Double? = null, savedFontSize: Double? = null): PlayerTeleprompterLayout {
        val resolved = when {
            userFontSize != null -> clampFontSize(userFontSize)
            savedFontSize != null -> clampFontSize(savedFontSize)
            else -> autoFontSize(sizingViewportHeight)
        }
        return PlayerTeleprompterLayout(
            slotHeight = ceil(resolved * LINE_HEIGHT_FACTOR),
            lineSpacing = DEFAULT_LINE_SPACING,
            fontSize = resolved,
            renderedLineCount = RENDERED_LINE_COUNT,
        )
    }

    /** +/- am Player: neue Größe (der Aufrufer persistiert sie unter [FONT_SIZE_STORAGE_KEY]). */
    fun bumpFontSize(delta: Double, sizingViewportHeight: Double, storedFontSize: Double?): Double {
        val current = storedFontSize?.let(::clampFontSize) ?: autoFontSize(sizingViewportHeight)
        return clampFontSize(current + delta)
    }

    /** Zeichen pro Teleprompter-Zeile aus verfügbarer Breite. */
    fun characterLimit(contentWidth: Double, layout: PlayerTeleprompterLayout): Int {
        if (contentWidth <= 1) return 42
        val charWidth = layout.fontSize * 0.56
        return maxOf(12, floor(contentWidth / charWidth).toInt())
    }
}

/**
 * Zeit → Zeile/Wort des Teleprompters (iOS: `activeWordHit`, `fractionalActiveLinePosition`,
 * `activeLineIndex` und `merged(display:recognized:)` aus `PlayerLiveTranscriptionController`).
 */
object PlayerTranscriptTimeline {
    data class WordHit(val lineIndex: Int, val word: PlayerTranscriptWord)

    /** Letzte Zeile, die nicht nach [globalTime] beginnt (Binärsuche; 0 bei leerer Liste). */
    fun activeLineIndex(lines: List<PlayerTranscriptLine>, globalTime: Double): Int {
        if (lines.isEmpty()) return 0
        var low = 0
        var high = lines.size - 1
        var candidate = 0
        while (low <= high) {
            val mid = low + (high - low) / 2
            if (lines[mid].globalStart <= globalTime) {
                candidate = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return candidate
    }

    fun activeWord(line: PlayerTranscriptLine, globalTime: Double): PlayerTranscriptWord? =
        line.spokenWords.firstOrNull { globalTime >= it.globalStart && globalTime < it.globalEnd }

    fun activeWordHit(lines: List<PlayerTranscriptLine>, globalTime: Double): WordHit? {
        if (lines.isEmpty()) return null
        val idx = activeLineIndex(lines, globalTime)
        val line = lines[idx]
        if (!(globalTime >= line.globalStart && globalTime < line.globalEnd)) return null
        val word = activeWord(line, globalTime) ?: return null
        return WordHit(idx, word)
    }

    /** Fortlaufende Zeilenposition (Ganzzahl = Zeilenanfang, Nachkomma = Fortschritt in der Zeile). */
    fun fractionalActiveLinePosition(lines: List<PlayerTranscriptLine>, globalTime: Double): Double {
        if (lines.isEmpty()) return 0.0
        if (globalTime <= lines[0].globalStart) return 0.0
        val lastIdx = lines.size - 1
        if (globalTime >= lines[lastIdx].globalEnd) {
            val gap = globalTime - lines[lastIdx].globalEnd
            val span = maxOf(0.35, lines[lastIdx].globalEnd - lines[lastIdx].globalStart)
            // Wiedergabe voraus: in den leeren Bereich hinter der letzten Zeile scrollen.
            if (gap > 0.25) return (lastIdx + 1).toDouble() + minOf(2.5, gap / span)
            return lastIdx.toDouble() + minOf(0.92, gap / span)
        }
        val idx = activeLineIndex(lines, globalTime)
        val line = lines[idx]
        if (globalTime < line.globalEnd) {
            val span = line.globalEnd - line.globalStart
            val progress = if (span > 0) (globalTime - line.globalStart) / span else 0.0
            return idx.toDouble() + minOf(1.0, maxOf(0.0, progress))
        }
        // Lücke zwischen zwei Zeilen — am Anfang der nächsten stehen bleiben.
        return minOf(lastIdx, idx + 1).toDouble()
    }

    /**
     * Anzeige-Wörter: eBook-Text, wo der Abgleich greift — sonst der Erkennungstext. `isShowingEbookText`
     * entspricht `display != null && display.words.isNotEmpty() && recognized.isNotEmpty()`.
     */
    fun displayWords(display: EbookDisplayWords?, recognized: List<PlayerTranscriptWord>): List<PlayerTranscriptWord> {
        if (display == null || display.words.isEmpty() || recognized.isEmpty()) return recognized
        return merged(display, recognized)
    }

    /** eBook-Wörter plus die Erkennungswörter außerhalb der lückenlosen eBook-Läufe, nach Zeit gemischt. */
    fun merged(display: EbookDisplayWords, recognized: List<PlayerTranscriptWord>): List<PlayerTranscriptWord> {
        val kept = ArrayList<PlayerTranscriptWord>()
        var span = 0
        for (word in recognized) {
            val middle = (word.globalStart + word.globalEnd) / 2
            while (span < display.spans.size && display.spans[span].end <= middle) span += 1
            if (span < display.spans.size && display.spans[span].start <= middle) continue
            kept.add(word)
        }
        val out = ArrayList<PlayerTranscriptWord>(display.words.size + kept.size)
        var i = 0
        var j = 0
        while (i < display.words.size || j < kept.size) {
            if (j >= kept.size || (i < display.words.size && display.words[i].globalStart <= kept[j].globalStart)) {
                out.add(display.words[i]); i += 1
            } else {
                out.add(kept[j]); j += 1
            }
        }
        return out
    }

    /**
     * iOS: `rebuildDisplayFromCache` — Cache-Wörter eines Tracks als Teleprompter-Wörter
     * (`c-<track>-<n>`, Text mit angehängtem Leerzeichen, globale Zeit).
     */
    fun recognizedWords(cache: PlayerTranscriptTrackCache, trackIndex: Int, trackGlobalOffset: Double): List<PlayerTranscriptWord> =
        cache.allWords.mapIndexed { index, word ->
            PlayerTranscriptWord(
                id = "c-$trackIndex-$index",
                text = word.t + " ",
                globalStart = trackGlobalOffset + word.s,
                globalEnd = maxOf(trackGlobalOffset + word.s, trackGlobalOffset + word.e),
            )
        }
}

/** iOS: `PlayerTranscriptWordLookup` — reine Teile (Lemma, Sprachcode). */
object PlayerTranscriptWordLookup {
    /** Lemma für Wörterbuch / Übersetzung (ohne Rand-Interpunktion). */
    fun normalizedTerm(raw: String): String {
        var t = FoundationText.trimmingWhitespacesAndNewlines(raw)
        t = FoundationText.trimming(t, FoundationText::isPunctuation)
        return FoundationText.trimmingWhitespacesAndNewlines(t)
    }

    /** iOS: `translationLanguage(from:)` — Sprachcode der Transkriptions-Locale, sonst BCP-47. */
    fun translationLanguageTag(locale: java.util.Locale): String =
        locale.language.takeIf { it.isNotEmpty() } ?: locale.toLanguageTag()

    /** iOS: `PlayerTranscriptWordLookupSelection.id` — `term|globalStart` (Swift-Double-Darstellung). */
    fun selectionId(term: String, globalStart: Double): String = "$term|${swiftDoubleDescription(globalStart)}"

    /** Swift `"\(Double)"`: kürzeste Darstellung, ganzzahlige Werte mit `.0` (wie Kotlin für normale Größen). */
    fun swiftDoubleDescription(value: Double): String = value.toString()
}
