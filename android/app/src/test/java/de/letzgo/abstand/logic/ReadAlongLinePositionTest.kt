package de.letzgo.abstand.logic

import de.letzgo.abstand.transcript.DecodeTimingDrift
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.floor

/** Zeilengebundene Teleprompter-Position, Wortmarkierung und Decoder-Drift-Diagnose. */
class ReadAlongLinePositionTest {
    private val tau = PlayerTranscriptTimeline.LINE_TRANSITION_SECONDS
    private val d = PlayerTranscriptTimeline.PAUSE_ONSET_DELAY_SECONDS

    private fun w(id: String, text: String, s: Double, e: Double) = PlayerTranscriptWord(id, text, s, e)

    /** Zeilen mit Start/Ende; je ein Wort über die ganze Zeile. */
    private fun lines(vararg ranges: Pair<Double, Double>) = ranges.mapIndexed { i, (s, e) ->
        PlayerTranscriptLine("l$i", listOf(w("w$i", "x$i ", s, e)), s, e)
    }

    private fun pos(lines: List<PlayerTranscriptLine>, t: Double) = PlayerTranscriptTimeline.fractionalActiveLinePosition(lines, t)

    // Zeilen 0–2 s, 2–4 s, Pause, 6–8 s, 8–10 s. Nur Zeile 2 beginnt nach einer Pause (Anzeige-Start 6 s + d).
    private val sample = lines(0.0 to 2.0, 2.0 to 4.0, 6.0 to 8.0, 8.0 to 10.0)

    @Test
    fun lineMiddleIsExactlyIndex() {
        assertEquals(0.0, pos(sample, 1.0), 0.0)
        assertEquals(1.0, pos(sample, 3.0), 0.0)
        assertEquals(2.0, pos(sample, 7.0), 0.0)
        assertEquals(3.0, pos(sample, 9.0), 0.0)
        // Fenstergrenzen: exakt ganzzahlig
        assertEquals(0.0, pos(sample, 2.0 - tau / 2), 1e-12)
        assertEquals(1.0, pos(sample, 2.0 + tau / 2), 1e-12)
    }

    @Test
    fun pauseStaysOnSpokenLine() {
        // Zeile 1 endet bei 4 s, Zeile 2 beginnt bei 6 s: bis kurz vor dem Fenster bleibt es bei 1.
        for (t in listOf(4.0, 4.5, 5.0, 5.5, 6.0 + d - tau / 2)) assertEquals("t=$t", 1.0, pos(sample, t), 1e-12)
    }

    @Test
    fun lineStartIsHalfway() {
        assertEquals(0.5, pos(sample, 2.0), 1e-12)
        assertEquals(1.5, pos(sample, 6.0 + d), 1e-12)
        assertEquals(2.5, pos(sample, 8.0), 1e-12)
    }

    @Test
    fun lineAfterPauseStartsOneLeadLater() {
        assertEquals(0.01, d, 0.0)
        // Nach Pause: Anzeige-Start = Wortanfang + d; ohne Pause (Start = Ende der Vorzeile): roh.
        assertEquals(6.0 + d, PlayerTranscriptTimeline.displayLineStart(sample, 2), 1e-12)
        assertEquals(2.0, PlayerTranscriptTimeline.displayLineStart(sample, 1), 0.0)
        assertEquals(8.0, PlayerTranscriptTimeline.displayLineStart(sample, 3), 0.0)
        assertEquals(0.0, PlayerTranscriptTimeline.displayLineStart(sample, 0), 0.0)
        // Die mittige Zeile (round(pos)) wechselt erst bei 6 s + d.
        assertTrue(pos(sample, 6.0) < 1.5)
        assertEquals(1, floor(pos(sample, 6.0 + d / 2) + 0.5).toInt())
        assertEquals(2, floor(pos(sample, 6.0 + 1.5 * d) + 0.5).toInt())
    }

    @Test
    fun pauseDelayNeverPassesNextLineStart() {
        // Zeile 1 nach Pause, Zeile 2 schon 5 ms später: Anzeige-Start höchstens am Start von Zeile 2.
        val tight = lines(0.0 to 1.0, 1.5 to 1.5, 1.505 to 2.0, 2.0 to 3.0)
        assertEquals(1.505, PlayerTranscriptTimeline.displayLineStart(tight, 1), 1e-12)
        assertEquals(1.505 + d, PlayerTranscriptTimeline.displayLineStart(tight, 2), 1e-12)
        assertContinuousMonotonicLoose(tight, -0.2, 3.5)
        assertEquals(3.0, pos(tight, 2.5), 0.0)
    }

    @Test
    fun beforeFirstLineAndTailUnchanged() {
        assertEquals(0.0, pos(sample, -1.0), 0.0)
        assertEquals(0.0, pos(sample, 0.0), 0.0)
        // Hinter der letzten Zeile (Ende 10 s): bis 10,25 s stehen bleiben, dann linear (span 2 s)
        assertEquals(3.0, pos(sample, 10.2), 0.0)
        assertEquals(3.375, pos(sample, 11.0), 1e-9)
        // Höchstens 3,5 Zeilen Überhang
        assertEquals(6.5, pos(sample, 100.0), 1e-9)
        assertEquals(0.0, pos(emptyList(), 5.0), 0.0)
    }

    /** Stetig (kleine Schritte) und monoton auf feinem Raster, inklusive Ende-Fall. */
    private fun assertContinuousMonotonic(lines: List<PlayerTranscriptLine>, from: Double, to: Double) {
        val dt = 0.0005
        var prev = pos(lines, from)
        var t = from + dt
        while (t <= to) {
            val p = pos(lines, t)
            assertTrue("monoton t=$t $prev→$p", p >= prev - 1e-12)
            assertTrue("stetig t=$t $prev→$p", abs(p - prev) < 0.02)
            prev = p
            t += dt
        }
    }

    @Test
    fun continuousAndMonotonicOnFineGrid() {
        assertContinuousMonotonic(sample, -0.5, 12.0)
    }

    @Test
    fun closeLineStartsDoNotOverlap() {
        // Starts 0, 1.0, 1.1, 1.15, 2.0 — Abstände kleiner als τ.
        val close = lines(0.0 to 1.0, 1.0 to 1.1, 1.1 to 1.15, 1.15 to 2.0, 2.0 to 3.0)
        assertContinuousMonotonicLoose(close, -0.2, 3.2)
        // Jeder Zeilenstart liegt genau in der Mitte seines Übergangs.
        assertEquals(0.5, pos(close, 1.0), 1e-12)
        assertEquals(1.5, pos(close, 1.1), 1e-12)
        assertEquals(2.5, pos(close, 1.15), 1e-12)
        assertEquals(3.5, pos(close, 2.0), 1e-12)
        // Zwischen 1.1 und 1.15 (Abstand 0.05): Mitte → exakt Zeile 2.
        assertEquals(2.0, pos(close, 1.125), 1e-12)
        assertEquals(4.0, pos(close, 2.5), 0.0)
    }

    /** Wie oben, aber die Steigung darf bei engen Starts steiler sein (Schritt < 0.2 Zeilen je 0,5 ms). */
    private fun assertContinuousMonotonicLoose(lines: List<PlayerTranscriptLine>, from: Double, to: Double) {
        val dt = 0.0001
        var prev = pos(lines, from)
        var t = from + dt
        while (t <= to) {
            val p = pos(lines, t)
            assertTrue("monoton t=$t $prev→$p", p >= prev - 1e-12)
            assertTrue("stetig t=$t $prev→$p", abs(p - prev) < 0.2)
            prev = p
            t += dt
        }
    }

    @Test
    fun identicalLineStartsStepWithoutBreakingMonotonicity() {
        val dup = lines(0.0 to 1.0, 1.0 to 1.0, 1.0 to 2.0)
        assertEquals(0.0, pos(dup, 0.5), 0.0)
        assertEquals(2.0, pos(dup, 1.5), 0.0)
        var prev = pos(dup, 0.0)
        var t = 0.0
        while (t < 2.0) {
            val p = pos(dup, t); assertTrue(p >= prev - 1e-12); prev = p; t += 0.001
        }
    }

    @Test
    fun centeredLineIsTheSpokenLine() {
        // Mittig steht round(pos); außerhalb der Übergänge ist das genau die Zeile, deren Anzeige-Start erreicht ist.
        var t = 0.0
        while (t < 10.0) {
            val p = pos(sample, t)
            val active = sample.indices.last { it == 0 || PlayerTranscriptTimeline.displayLineStart(sample, it) <= t }
            val centered = floor(p + 0.5).toInt()
            if (abs(p - floor(p) - 0.5) > 1e-9) assertEquals("t=$t", active, centered)
            t += 0.01
        }
    }

    // MARK: - Wortmarkierung

    private val wordLine = PlayerTranscriptLine(
        "l",
        listOf(w("a", "One ", 1.0, 1.4), w("sp", " ", 1.4, 1.4), w("b", "two ", 1.6, 2.0), w("c", "three ", 2.0, 2.5)),
        1.0, 2.5,
    )

    @Test
    fun spokenWordIndexHoldsThroughPauses() {
        assertNull(PlayerTranscriptTimeline.spokenWordIndex(wordLine, 0.9))
        assertEquals(0, PlayerTranscriptTimeline.spokenWordIndex(wordLine, 1.0))
        // Pause 1.4–1.6: „One" bleibt aktiv (Leerzeichen-Wort zählt nicht)
        assertEquals(0, PlayerTranscriptTimeline.spokenWordIndex(wordLine, 1.5))
        assertEquals(2, PlayerTranscriptTimeline.spokenWordIndex(wordLine, 1.6))
        assertEquals(3, PlayerTranscriptTimeline.spokenWordIndex(wordLine, 9.0))
        assertNull(PlayerTranscriptTimeline.spokenWordIndex(null, 1.0))
    }

    @Test
    fun spokenWordIndexAgreesWithActiveWordHit() {
        val lines = listOf(wordLine)
        var t = 1.0
        while (t < 2.5) {
            val hit = PlayerTranscriptTimeline.activeWordHit(lines, t)
            if (hit != null) assertEquals("t=$t", hit.word.id, wordLine.words[PlayerTranscriptTimeline.spokenWordIndex(wordLine, t)!!].id)
            t += 0.01
        }
    }

    @Test
    fun wordOpacityHasThreeTiers() {
        val m = PlayerTeleprompterMetrics
        assertEquals(1.0, m.wordTextOpacity(isActiveLine = true, isInActiveParagraph = true, wordIndex = 0, spokenWordIndex = 2), 0.0)
        assertEquals(1.0, m.wordTextOpacity(true, true, 2, 2), 0.0)
        assertEquals(m.UPCOMING_WORD_TEXT_OPACITY, m.wordTextOpacity(true, true, 3, 2), 0.0)
        assertEquals(m.UPCOMING_WORD_TEXT_OPACITY, m.wordTextOpacity(true, true, 0, null), 0.0)
        assertEquals(m.ACTIVE_PARAGRAPH_LINE_TEXT_OPACITY, m.wordTextOpacity(false, true, 0, null), 0.0)
        assertEquals(m.INACTIVE_LINE_TEXT_OPACITY, m.wordTextOpacity(false, false, 0, null), 0.0)
    }

    // MARK: - Decoder-Drift

    @Test
    fun decodeDriftMeasuresGapsAndOverlaps() {
        val d = DecodeTimingDrift(sampleRate = 16_000)
        assertNull(d.summary(0.0, 0.0))
        d.anchor(10.0)
        d.record(10.0); d.addSamples(16_000)
        d.record(11.0); d.addSamples(16_000)
        assertEquals(0.0, d.maxDeviation, 1e-12)
        // Lücke: Paket 30 ms später als gezählt
        d.record(12.03); d.addSamples(8_000)
        assertEquals(0.03, d.maxDeviation, 1e-9)
        assertEquals(12.03, d.maxDeviationAt, 1e-12)
        // Kleinere Überlappung ändert das Maximum nicht
        d.record(12.52); d.addSamples(100)
        assertEquals(0.03, d.maxDeviation, 1e-9)
        assertEquals(4, d.buffers)
        assertTrue(d.summary(10.0, 13.0)!!.contains("max drift +30.0 ms"))
    }
}
