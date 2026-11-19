package de.letzgo.abstand.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** In Sprechpausen vorgezogene Wortanfänge (`ReadAlongWordTiming`). */
class ReadAlongWordTimingTest {
    private fun w(id: String, text: String, s: Double, e: Double) = PlayerTranscriptWord(id, text, s, e)

    @Test
    fun constantsAndCharacterCount() {
        assertEquals(0.15, ReadAlongWordTiming.BASE_MAX_DURATION, 0.0)
        assertEquals(0.10, ReadAlongWordTiming.MAX_DURATION_PER_CHARACTER, 0.0)
        // Leerraum zählt nicht, Satzzeichen schon.
        assertEquals(6, ReadAlongWordTiming.characterCount("ruhig. "))
        assertEquals(0, ReadAlongWordTiming.characterCount("  "))
        assertEquals(1.05, ReadAlongWordTiming.maxDuration(9), 1e-12)
    }

    @Test
    fun wordAfterPauseIsClamped() {
        // „Gestern" (7 Zeichen): erkannt ab Ende des Vorworts (2.1), endet 3.78 → frühestens 3.78 − 0.85.
        val words = ReadAlongWordTiming.corrected(listOf(w("a", "ruhig. ", 1.62, 2.1), w("b", "Gestern ", 2.1, 3.78)))
        assertEquals(3.78 - 0.85, words[1].globalStart, 1e-9)
        assertEquals(3.78, words[1].globalEnd, 0.0)
        assertEquals("b", words[1].id)
        assertEquals("Gestern ", words[1].text)
        // „ruhig." (6 Zeichen, 0.48 s ≤ 0.75 s) bleibt.
        assertEquals(1.62, words[0].globalStart, 0.0)
    }

    @Test
    fun normalWordStaysUnchanged() {
        val input = listOf(w("a", "Der ", 1.02, 1.32), w("b", "Morgen ", 1.32, 1.62), w("c", "begann ", 1.62, 2.1))
        assertEquals(input, ReadAlongWordTiming.corrected(input))
    }

    @Test
    fun startsStayMonotonic() {
        // Überlappende Erkennung: korrigierter Start darf nicht hinter den Start des Folgeworts.
        val input = listOf(w("a", "a ", 0.0, 3.0), w("b", "b ", 1.0, 1.5), w("c", "c ", 1.5, 2.0))
        val out = ReadAlongWordTiming.corrected(input)
        assertEquals(1.0, out[0].globalStart, 0.0)
        for (i in 1 until out.size) assertTrue(out[i - 1].globalStart <= out[i].globalStart)
        // Leerzeichen-Wörter werden übersprungen, das Folgewort ist das nächste gesprochene.
        val spaced = ReadAlongWordTiming.corrected(listOf(w("a", "a ", 0.0, 3.0), w("s", " ", 0.5, 0.5), w("b", "b ", 1.0, 1.5)))
        assertEquals(1.0, spaced[0].globalStart, 0.0)
        assertEquals(0.5, spaced[1].globalStart, 0.0)
        // Einzelfunktion: Begrenzung, aber nie vor den eigenen Start.
        assertEquals(1.0, ReadAlongWordTiming.correctedStart(0.0, 3.0, 1, 1.0), 0.0)
        assertEquals(0.5, ReadAlongWordTiming.correctedStart(0.5, 3.0, 1, 0.2), 0.0)
    }

    @Test
    fun invalidTimesAreLeftAlone() {
        assertEquals(5.0, ReadAlongWordTiming.correctedStart(5.0, 5.0, 3, null), 0.0)
        assertEquals(5.0, ReadAlongWordTiming.correctedStart(5.0, 4.0, 3, null), 0.0)
        assertEquals(Double.NaN, ReadAlongWordTiming.correctedStart(Double.NaN, 4.0, 3, null), 0.0)
        assertEquals(1.0, ReadAlongWordTiming.correctedStart(1.0, Double.POSITIVE_INFINITY, 3, null), 0.0)
        assertEquals(1.0, ReadAlongWordTiming.correctedStart(1.0, Double.NaN, 3, null), 0.0)
        // Ungültiger Folgestart begrenzt nicht.
        assertEquals(10.0 - 0.45, ReadAlongWordTiming.correctedStart(1.0, 10.0, 3, Double.NaN), 1e-12)
    }

    @Test
    fun lineStartFollowsCorrectedWordStart() {
        // Cache mit Pause nach „ruhig.": „Gestern" vom Erkenner ab dessen Ende (2.6) statt ab ~2.9.
        // Alter Stand (Version 2, unverfeinert) — nur dort greift die Anzeige-Heuristik noch.
        val cache = PlayerTranscriptTrackCache(
            version = 2,
            localeIdentifier = "de-DE", trackIndex = 0,
            segments = listOf(
                PlayerTranscriptTrackCache.Segment(
                    0.0, 10.0,
                    listOf(
                        PlayerTranscriptTrackCache.Word("Der", 1.02, 1.32),
                        PlayerTranscriptTrackCache.Word("Morgen", 1.32, 1.62),
                        PlayerTranscriptTrackCache.Word("begann", 1.62, 2.1),
                        PlayerTranscriptTrackCache.Word("ruhig.", 2.1, 2.6),
                        PlayerTranscriptTrackCache.Word("Gestern", 2.6, 3.78),
                        PlayerTranscriptTrackCache.Word("regnete", 3.78, 4.2),
                    ),
                ),
            ),
        )
        val words = PlayerTranscriptTimeline.recognizedWords(cache, 0, 100.0)
        // „Gestern" (7 Zeichen) frühestens 103.78 − 0.85; die übrigen bleiben.
        assertEquals(103.78 - 0.85, words[4].globalStart, 1e-9)
        listOf(101.02, 101.32, 101.62, 102.1).forEachIndexed { i, t -> assertEquals(t, words[i].globalStart, 1e-9) }
        assertEquals(103.78, words[5].globalStart, 1e-9)
        // Cache bleibt roh.
        assertEquals(2.6, cache.allWords[4].s, 0.0)

        val acc = PlayerTranscriptLineAccumulator()
        acc.rebuildLines(words, 84)
        val lines = acc.publishedLines()
        assertEquals(2, lines.size)
        assertEquals(101.02, lines[0].globalStart, 1e-9)
        assertEquals(103.78 - 0.85, lines[1].globalStart, 1e-9)
        // In der Pause bleibt die erste Zeile aktiv, die zweite beginnt erst am korrigierten Start.
        assertEquals(0, PlayerTranscriptTimeline.activeLineIndex(lines, 102.8))
        assertEquals(null, PlayerTranscriptTimeline.spokenWordIndex(lines[1], 102.8))
        assertEquals(1, PlayerTranscriptTimeline.activeLineIndex(lines, 103.0))
        assertEquals(0, PlayerTranscriptTimeline.spokenWordIndex(lines[1], 103.0))
    }
}
