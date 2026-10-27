package de.letzgo.abstand.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscriptLogicTest {
    private fun w(text: String, s: Double, e: Double, id: String = "x") = PlayerTranscriptWord(id, text, s, e)

    @Test
    fun lineAccumulatorBreaksOnSentenceEndAndWidth() {
        val acc = PlayerTranscriptLineAccumulator()
        acc.maxCharactersPerLine = 13
        acc.appendFinalizedWords(
            listOf(w("Hello ", 0.0, 0.5), w("world. ", 0.5, 1.0), w("  ", 1.0, 1.1), w("This ", 1.2, 1.4), w("is ", 1.4, 1.5), w("long ", 1.5, 1.8), w("text” ", 1.8, 2.0)),
        )
        val lines = acc.publishedLines()
        // „Hello world." (13 Zeichen) schließt per Satzende; „text”" brächte 19 > 13 → Umbruch davor.
        assertEquals(listOf("line-0", "line-1", "line-2"), lines.map { it.id })
        assertEquals(listOf("w-0", "w-1"), lines[0].words.map { it.id })
        // Reines Leerzeichen-Wort am Zeilenanfang wird verworfen (offene Zeile leer), verbraucht aber eine ID.
        assertEquals(listOf("w-3", "w-4", "w-5"), lines[1].words.map { it.id })
        assertEquals(listOf("text” "), lines[2].words.map { it.text })
        assertEquals(0.0, lines[0].globalStart, 0.0)
        assertEquals(1.0, lines[0].globalEnd, 0.0)
        assertEquals(2, acc.closedLines.size)
    }

    @Test
    fun sentenceEndIgnoresClosingQuotes() {
        assertTrue(PlayerTranscriptLineAccumulator.endsSentence("done.\" "))
        assertTrue(PlayerTranscriptLineAccumulator.endsSentence("wirklich?»)"))
        assertTrue(PlayerTranscriptLineAccumulator.endsSentence("so…"))
        assertFalse(PlayerTranscriptLineAccumulator.endsSentence("and,"))
        assertFalse(PlayerTranscriptLineAccumulator.endsSentence("\"\""))
        assertFalse(PlayerTranscriptLineAccumulator.endsSentence("“quoted.”")) // „”" gehört nicht zur iOS-Liste
    }

    @Test
    fun openLineHasMinimumDuration() {
        val acc = PlayerTranscriptLineAccumulator()
        acc.appendFinalizedWords(listOf(w("a ", 5.0, 5.0)))
        val line = acc.publishedLines().single()
        assertEquals(5.05, line.globalEnd, 1e-12)
    }

    private fun line(id: String, start: Double, end: Double, vararg words: PlayerTranscriptWord) =
        PlayerTranscriptLine(id, words.toList(), start, end)

    @Test
    fun timelineActiveLineAndFraction() {
        val lines = listOf(
            line("l0", 0.0, 2.0, w("a ", 0.0, 1.0, "a"), w(" ", 1.0, 1.0, "sp"), w("b ", 1.0, 2.0, "b")),
            line("l1", 3.0, 4.0, w("c ", 3.0, 4.0, "c")),
        )
        assertEquals(0.0, PlayerTranscriptTimeline.fractionalActiveLinePosition(lines, -1.0), 0.0)
        assertEquals(0.5, PlayerTranscriptTimeline.fractionalActiveLinePosition(lines, 1.0), 1e-12)
        // Lücke zwischen Zeilen → Anfang der nächsten
        assertEquals(1.0, PlayerTranscriptTimeline.fractionalActiveLinePosition(lines, 2.5), 0.0)
        // Hinter der letzten Zeile: gap 0.2 ≤ 0.25 → lastIdx + gap/span
        assertEquals(1.2, PlayerTranscriptTimeline.fractionalActiveLinePosition(lines, 4.2), 1e-9)
        // gap 1.0 > 0.25 → lastIdx + 1 + min(2.5, 1.0/1.0)
        assertEquals(3.0, PlayerTranscriptTimeline.fractionalActiveLinePosition(lines, 5.0), 1e-9)

        assertEquals("b", PlayerTranscriptTimeline.activeWordHit(lines, 1.5)!!.word.id)
        assertEquals(0, PlayerTranscriptTimeline.activeWordHit(lines, 1.5)!!.lineIndex)
        assertNull(PlayerTranscriptTimeline.activeWordHit(lines, 2.5))
        assertEquals(1, PlayerTranscriptTimeline.activeLineIndex(lines, 3.0))
        assertEquals(0, PlayerTranscriptTimeline.activeLineIndex(emptyList(), 3.0))
    }

    @Test
    fun recognizedWordsFromCache() {
        val cache = PlayerTranscriptTrackCache(
            localeIdentifier = "en-US", trackIndex = 2,
            segments = listOf(PlayerTranscriptTrackCache.Segment(0.0, 10.0, listOf(PlayerTranscriptTrackCache.Word("hi", 1.0, 0.5)))),
        )
        val words = PlayerTranscriptTimeline.recognizedWords(cache, 2, 100.0)
        assertEquals(PlayerTranscriptWord("c-2-0", "hi ", 101.0, 101.0), words.single())
    }

    @Test
    fun trackCacheInsertMergesOverlaps() {
        val cache = PlayerTranscriptTrackCache(localeIdentifier = "de-DE", trackIndex = 0)
        cache.insert(PlayerTranscriptTrackCache.Segment(10.0, 20.0, listOf(PlayerTranscriptTrackCache.Word("b", 11.0, 12.0))))
        cache.insert(PlayerTranscriptTrackCache.Segment(0.0, 5.0, listOf(PlayerTranscriptTrackCache.Word("a", 1.0, 2.0))))
        assertEquals(listOf(0.0, 10.0), cache.segments.map { it.start })
        // Überlappt [10,20] und grenzt an [0,5] nicht (5.6 > 5 + 0.5)
        cache.insert(
            PlayerTranscriptTrackCache.Segment(
                18.0, 30.0,
                listOf(PlayerTranscriptTrackCache.Word("dup", 18.5, 19.0), PlayerTranscriptTrackCache.Word("c", 21.0, 22.0)),
            ),
        )
        assertEquals(2, cache.segments.size)
        val merged = cache.segments[1]
        assertEquals(10.0, merged.start, 0.0)
        assertEquals(30.0, merged.end, 0.0)
        assertEquals(listOf("b", "c"), merged.words.map { it.t })
        assertEquals(listOf("a", "b", "c"), cache.allWords.map { it.t })

        assertTrue(cache.covers(9.6))
        assertFalse(cache.covers(7.0))
        assertEquals(5.0, cache.firstUncoveredTime(0.0, 100.0)!!, 0.0)
        assertEquals(30.0, cache.firstUncoveredTime(12.0, 100.0)!!, 0.0)
        assertNull(cache.firstUncoveredTime(12.0, 30.5))
        // Leeres, zeitloses Segment wird ignoriert
        cache.insert(PlayerTranscriptTrackCache.Segment(40.0, 40.0, emptyList()))
        assertEquals(2, cache.segments.size)
    }

    @Test
    fun recapTextJoinsWordsInWindow() {
        val sources = listOf(
            PlayerTranscriptTrackSource(1, "/b.mp3", 100.0, 100.0),
            PlayerTranscriptTrackSource(0, "/a.mp3", 0.0, 100.0),
        )
        val words = mapOf(
            0 to listOf(PlayerTranscriptTrackCache.Word("early", 10.0, 11.0), PlayerTranscriptTrackCache.Word("late", 95.0, 96.0)),
            1 to listOf(PlayerTranscriptTrackCache.Word("next", 1.0, 2.0), PlayerTranscriptTrackCache.Word("far", 50.0, 51.0)),
        )
        val text = PlayerTranscriptLibrary.transcriptText(sources, 90.0..105.0) { words[it].orEmpty() }
        assertEquals("late next", text)
        assertNull(PlayerTranscriptLibrary.localWindow(sources[0], 0.0..50.0))
    }

    @Test
    fun wordLookupTerm() {
        assertEquals("Hello", PlayerTranscriptWordLookup.normalizedTerm("  «Hello!» "))
        assertEquals("don't", PlayerTranscriptWordLookup.normalizedTerm("\"don't,\""))
        assertEquals("", PlayerTranscriptWordLookup.normalizedTerm("—"))
        assertEquals("de", PlayerTranscriptWordLookup.translationLanguageTag(java.util.Locale.forLanguageTag("de-AT")))
    }

    @Test
    fun teleprompterMetrics() {
        // 300 / (9 × 1.22) = 27.32… − 4 = 23.32…
        assertEquals(300.0 / (9 * 1.22) - 4, PlayerTeleprompterMetrics.autoFontSize(300.0), 1e-12)
        assertEquals(14.0, PlayerTeleprompterMetrics.autoFontSize(10.0), 0.0)
        val layout = PlayerTeleprompterMetrics.layout(300.0, userFontSize = 40.0)
        assertEquals(34.0, layout.fontSize, 0.0)
        assertEquals(42.0, layout.slotHeight, 0.0) // ceil(34 × 1.22 = 41.48)
        assertEquals(10, layout.linesBeforeCenter)
        assertEquals(21 * 42.0, layout.stackHeight, 0.0)
        assertEquals(18.0, PlayerTeleprompterMetrics.layout(300.0, savedFontSize = 18.0).fontSize, 0.0)
        assertEquals(42, PlayerTeleprompterMetrics.characterLimit(0.5, layout))
        assertEquals(17, PlayerTeleprompterMetrics.characterLimit(330.0, layout)) // 330 / 19.04
        assertEquals(26.0, PlayerTeleprompterMetrics.bumpFontSize(2.0, 300.0, 24.0), 0.0)
    }
}
