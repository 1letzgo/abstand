package de.letzgo.abstand.logic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS: `EbookTrackLookup` — Abfragen nur innerhalb der Transkript-Abdeckung und höchstens 120 s Abstand. */
class EbookTrackLookupTest {
    /** eBook-Wörter 10, 11, 13 (12 nicht ausgerichtet) bei 5 s, 10 s, 200 s; 20, 21 bei 590/595 s. */
    private fun alignment() = EbookTrackAlignment(
        ebookWordCount = 100, spokenWordCount = 5, spokenEnd = 596.0,
        words = intArrayOf(10, 11, 13, 20, 21),
        starts = floatArrayOf(5f, 10f, 200f, 590f, 595f),
        ends = floatArrayOf(6f, 11f, 201f, 591f, 596f),
        flags = ByteArray(5) { 1 },
    )

    private fun lookup(vararg spans: Pair<Double, Double>) =
        EbookTrackLookup(alignment(), EbookTranscriptCoverage(spans.map { EbookTranscriptCoverage.Span(it.first, it.second) }))

    @Test
    fun narratedWordRespectsCoverageAndDistance() {
        val full = lookup(0.0 to 600.0)
        assertEquals(EbookTrackLookup.NarratedWord.Word(11), full.narratedWord(50.0))
        // Mehr als 120 s nach dem letzten ausgerichteten Wort: keine Antwort.
        assertEquals(EbookTrackLookup.NarratedWord.Unavailable, full.narratedWord(150.0))
        assertEquals(EbookTrackLookup.NarratedWord.BeforeFirstWord, full.narratedWord(2.0))
        // Lücke im Transkript: keine Antwort.
        val gap = lookup(0.0 to 100.0, 180.0 to 600.0)
        assertEquals(EbookTrackLookup.NarratedWord.Unavailable, gap.narratedWord(120.0))
        // Letztes Wort außerhalb des Segments der Abfragezeit.
        assertEquals(EbookTrackLookup.NarratedWord.Unavailable, gap.narratedWord(190.0))
        assertEquals(EbookTrackLookup.NarratedWord.Word(13), gap.narratedWord(205.0))
        // Segment beginnt nicht am Trackanfang: kein „vor dem ersten Wort".
        assertEquals(EbookTrackLookup.NarratedWord.Unavailable, lookup(2.0 to 600.0).narratedWord(3.0))
    }

    @Test
    fun localTimeForUnalignedWordNeedsContinuousShortStretch() {
        val full = lookup(0.0 to 600.0)
        assertEquals(10.0, full.localTime(11)!!, 0.001)
        // Wort 12 → nächstes ausgerichtetes (13), aber Nachbarn 189 s auseinander.
        assertNull(full.localTime(12))
        // Wort 15 → 20 bei 590 s, Abstand zu 13 (201 s) zu groß.
        assertNull(full.localTime(15))
        val close = EbookTrackLookup(
            EbookTrackAlignment(10, 2, 30.0, intArrayOf(1, 3), floatArrayOf(10f, 20f), floatArrayOf(11f, 21f), ByteArray(2)),
            EbookTranscriptCoverage(listOf(EbookTranscriptCoverage.Span(0.0, 30.0))),
        )
        assertEquals(20.0, close.localTime(2)!!, 0.001)
        val holed = EbookTrackLookup(
            close.alignment,
            EbookTranscriptCoverage(listOf(EbookTranscriptCoverage.Span(0.0, 12.0), EbookTranscriptCoverage.Span(18.0, 30.0))),
        )
        assertNull(holed.localTime(2))
        assertEquals(20.0, holed.localTime(3)!!, 0.001)
    }

    @Test
    fun trackBoundaryChecks() {
        val full = lookup(0.0 to 600.0)
        assertEquals(5.0, full.leadingWordTime!!, 0.001)
        assertEquals(21, full.trailingWord(600.0))
        assertTrue(full.isFullyCovered(600.0))
        // Ende nicht transkribiert / letztes Wort zu weit vom Ende.
        assertNull(lookup(0.0 to 597.0).trailingWord(600.0))
        assertNull(full.trailingWord(900.0))
        assertFalse(lookup(0.0 to 300.0).isFullyCovered(600.0))
        assertNull(lookup(3.0 to 600.0).leadingWordTime)
    }
}
