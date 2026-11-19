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
    /** Zeilen außerhalb des aktiven Absatzes (symmetrisch ausgeblendet). */
    const val INACTIVE_LINE_TEXT_OPACITY = 0.32
    /** Übrige Zeilen des aktiven Absatzes (Stufen identisch zu iOS). */
    const val ACTIVE_PARAGRAPH_LINE_TEXT_OPACITY = 0.58
    /** Aktive Zeile: noch nicht gesprochene Wörter (gesprochene volle Tinte). */
    const val UPCOMING_WORD_TEXT_OPACITY = 0.72

    /**
     * Deckkraft eines Worts in drei Stufen: aktive Zeile volle Tinte (noch nicht gesprochene Wörter
     * [UPCOMING_WORD_TEXT_OPACITY]), übrige Zeilen des aktiven Absatzes [ACTIVE_PARAGRAPH_LINE_TEXT_OPACITY],
     * Rest [INACTIVE_LINE_TEXT_OPACITY]. [spokenWordIndex] aus `PlayerTranscriptTimeline.spokenWordIndex`.
     */
    fun wordTextOpacity(isActiveLine: Boolean, isInActiveParagraph: Boolean, wordIndex: Int, spokenWordIndex: Int?): Double = when {
        isActiveLine -> if (spokenWordIndex != null && wordIndex <= spokenWordIndex) 1.0 else UPCOMING_WORD_TEXT_OPACITY
        isInActiveParagraph -> ACTIVE_PARAGRAPH_LINE_TEXT_OPACITY
        else -> INACTIVE_LINE_TEXT_OPACITY
    }

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

    /** iOS: `ReadAlongLinePosition.transitionSeconds` — Übergangsdauer τ zwischen zwei Zeilen (s). */
    const val LINE_TRANSITION_SECONDS = 0.3
    /**
     * iOS: `ReadAlongLinePosition.pauseOnsetDelaySeconds` — Wortanfänge nach Sprechpausen legt der Refiner
     * `SpeechOnsetRefiner.LEAD_SECONDS` (10 ms) vor den Anfang des ersten Hüllkurvenfensters über der
     * Schwelle; für den Zeilenwechsel wird dieser Vorlauf zurückgenommen (nur Scroll-Position, nicht die
     * Wortmarkierung; wirkt auch auf gespeicherte Transkripte).
     */
    const val PAUSE_ONSET_DELAY_SECONDS = 0.01
    /** iOS: `endHoldSeconds` — so lange bleibt die letzte Zeile nach ihrem Ende noch stehen (s). */
    const val END_HOLD_SECONDS = 0.25
    /** iOS: `endMinimumSpan` — Mindest-Zeilendauer für das Weiterscrollen hinter der letzten Zeile (s). */
    const val END_MINIMUM_SPAN = 0.35
    /** iOS: `endMaximumOvershoot` — höchstens so viele Zeilen in den leeren Bereich scrollen. */
    const val END_MAXIMUM_OVERSHOOT = 3.5

    /**
     * iOS: `ReadAlongLinePosition.halfWindow` — halbe Fensterbreite um den Start von Zeile [k] (k ≥ 1):
     * `min(τ/2, (s_k − s_{k−1})/2, (s_{k+1} − s_k)/2)`, negative Abstände zählen als 0.
     */
    fun transitionHalfWidth(lines: List<PlayerTranscriptLine>, k: Int): Double {
        var h = LINE_TRANSITION_SECONDS / 2
        h = minOf(h, maxOf(0.0, displayLineStart(lines, k) - displayLineStart(lines, k - 1)) / 2)
        if (k + 1 < lines.size) h = minOf(h, maxOf(0.0, displayLineStart(lines, k + 1) - displayLineStart(lines, k)) / 2)
        return h
    }

    /**
     * iOS: `ReadAlongLinePosition.displayStart` — Anzeige-Start der Zeile [k]: nach einer Sprechpause (Start
     * hinter dem Ende der Vorzeile) [PAUSE_ONSET_DELAY_SECONDS] später, höchstens bis zum Start der
     * Folgezeile — die Starts bleiben aufsteigend, die Position stetig und monoton. Sonst der rohe Start.
     */
    fun displayLineStart(lines: List<PlayerTranscriptLine>, k: Int): Double {
        val raw = lines[k].globalStart
        if (k < 1 || raw <= lines[k - 1].globalEnd) return raw
        var shifted = raw + PAUSE_ONSET_DELAY_SECONDS
        if (k + 1 < lines.size) shifted = minOf(shifted, lines[k + 1].globalStart)
        return maxOf(raw, shifted)
    }

    /** iOS: `smoothFraction` — Smoothstep 3x² − 2x³ über `[0, width]`; Breite 0 = harter Schritt. */
    fun smoothFraction(elapsed: Double, width: Double): Double {
        if (width <= 0) return if (elapsed >= 0) 1.0 else 0.0
        val x = minOf(1.0, maxOf(0.0, elapsed / width))
        return x * x * (3 - 2 * x)
    }

    /**
     * iOS: `ReadAlongLinePosition.position` — zeilengebundene Scroll-Position. Sei `i` die letzte Zeile mit
     * `s_i ≤ t`: die Position ist exakt `i`, solange die Zeile gesprochen wird, auch in Pausen. Nur um
     * jeden Zeilenstart `s_k` (k ≥ 1) gleitet sie im Fenster `[s_k − h_k, s_k + h_k]` per Smoothstep von
     * `k − 1` nach `k` (bei `t = s_k` genau `k − 0,5`). Stetig und monoton. Hinter der letzten Zeile
     * (Transkript hinkt hinterher) nach [END_HOLD_SECONDS] linear in den leeren Bereich. `s_k` ist der
     * Anzeige-Start [displayLineStart] (nach Sprechpausen um [PAUSE_ONSET_DELAY_SECONDS] später).
     */
    fun fractionalActiveLinePosition(lines: List<PlayerTranscriptLine>, globalTime: Double): Double {
        if (lines.isEmpty()) return 0.0
        val t = globalTime
        if (t <= displayLineStart(lines, 0)) return 0.0
        val lastIdx = lines.size - 1
        // Anzeige-Starts liegen höchstens einen Vorlauf hinter den rohen: Zeile `i` kann für die Anzeige
        // noch nicht begonnen haben, dann ist es die vorige.
        var i = activeLineIndex(lines, t)
        if (i > 0 && t < displayLineStart(lines, i)) i -= 1

        // Übergang in die nächste Zeile (erste Hälfte des Fensters um s_{i+1}).
        if (i < lastIdx) {
            val h = transitionHalfWidth(lines, i + 1)
            val windowStart = displayLineStart(lines, i + 1) - h
            if (t >= windowStart) return i + smoothFraction(t - windowStart, 2 * h)
        }
        // Ausklang des Übergangs aus der vorigen Zeile (zweite Hälfte des Fensters um s_i).
        var holdUntil = displayLineStart(lines, i)
        if (i >= 1) {
            val h = transitionHalfWidth(lines, i)
            val windowStart = displayLineStart(lines, i) - h
            holdUntil = displayLineStart(lines, i) + h
            if (t < holdUntil) return (i - 1) + smoothFraction(t - windowStart, 2 * h)
        }
        // Hinter der letzten Zeile: kurz stehen bleiben, dann in den leeren Bereich scrollen.
        if (i == lastIdx) {
            val lastEnd = lines[lastIdx].globalEnd
            val endStart = maxOf(lastEnd, holdUntil) + END_HOLD_SECONDS
            if (t > endStart) {
                val span = maxOf(END_MINIMUM_SPAN, lastEnd - lines[lastIdx].globalStart)
                return lastIdx + minOf(END_MAXIMUM_OVERSHOOT, (t - endStart) / span)
            }
        }
        return i.toDouble()
    }

    /**
     * Index (in `line.words`) des zuletzt begonnenen gesprochenen Worts: letztes Nicht-Leerzeichen-Wort
     * mit Start ≤ [globalTime]; bleibt in Pausen stehen (anders als [activeWordHit]). `null`, solange
     * noch kein Wort der Zeile begonnen hat.
     */
    fun spokenWordIndex(line: PlayerTranscriptLine?, globalTime: Double): Int? {
        if (line == null) return null
        var result: Int? = null
        line.words.forEachIndexed { index, word ->
            if (!word.isWhitespaceOnly && word.globalStart <= globalTime) result = index
        }
        return result
    }

    /**
     * iOS: `rebuildDisplayFromCache` — Cache-Wörter eines Tracks als Teleprompter-Wörter
     * (`c-<track>-<n>`, Text mit angehängtem Leerzeichen, globale Zeit). Verfeinerte Transkripte tragen
     * schon die akustischen Einsätze; nur alte Stände (Version 2) bekommen die Anzeige-Heuristik
     * [ReadAlongWordTiming] für in Pausen vorgezogene Wortanfänge.
     */
    fun recognizedWords(cache: PlayerTranscriptTrackCache, trackIndex: Int, trackGlobalOffset: Double): List<PlayerTranscriptWord> {
        val words = cache.allWords.mapIndexed { index, word ->
            PlayerTranscriptWord(
                id = "c-$trackIndex-$index",
                text = word.t + " ",
                globalStart = trackGlobalOffset + word.s,
                globalEnd = maxOf(trackGlobalOffset + word.s, trackGlobalOffset + word.e),
            )
        }
        return if (cache.isOnsetRefined) words else ReadAlongWordTiming.corrected(words)
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
