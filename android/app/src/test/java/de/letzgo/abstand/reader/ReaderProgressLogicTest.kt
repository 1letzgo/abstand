package de.letzgo.abstand.reader

import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.reader.EbookProgressRules.SyncDecision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReaderProgressLogicTest {
    @Test
    fun fractionPrefersTotalProgressionAndClamps() {
        assertEquals(0.4, ReaderProgressInfo.fraction(0.4, 0.9), 1e-9)
        assertEquals(0.9, ReaderProgressInfo.fraction(null, 0.9), 1e-9)
        assertEquals(0.0, ReaderProgressInfo.fraction(null, null), 1e-9)
        assertEquals(1.0, ReaderProgressInfo.fraction(1.3, null), 1e-9)
        assertEquals(0.0, ReaderProgressInfo.fraction(-0.2, null), 1e-9)
    }

    @Test
    fun labelsMatchIos() {
        val pages = BookPageProgress(12, 300, 4)
        assertEquals("Page 12 of 300 · 4%", ReaderProgressInfo.label(0.04, AbsEbookFormat.epub, null, null, pages))
        assertEquals("37%", ReaderProgressInfo.label(0.371, AbsEbookFormat.epub, null, null, null))
        assertEquals("Page 5 of 20", ReaderProgressInfo.label(0.2, AbsEbookFormat.pdf, 5, 20, null))
        assertEquals("20 %", ReaderProgressInfo.label(0.2, AbsEbookFormat.pdf, null, 20, null))
        assertEquals("Page 10 of 20 · 50%", ReaderProgressInfo.scrubCaption(0.5, AbsEbookFormat.pdf, 20))
        assertEquals("Page 1 of 20 · 0%", ReaderProgressInfo.scrubCaption(0.0, AbsEbookFormat.pdf, 20))
        assertEquals("50%", ReaderProgressInfo.scrubCaption(0.5, AbsEbookFormat.epub, 20))
    }

    @Test
    fun bookWidePagesEstimateFromVisitedChapters() {
        val estimator = EpubBookPageEstimator(listOf("a.xhtml", "b.xhtml", "c.xhtml"))
        // Unbekannte Kapitel übernehmen den Durchschnitt der bekannten.
        val first = estimator.bookWidePageProgress("a.xhtml#p1", 0.1, RenderedPageInfo(3, 10))
        assertEquals(BookPageProgress(3, 30, 10), first)
        val second = estimator.bookWidePageProgress("b.xhtml", 0.5, RenderedPageInfo(2, 20))
        // total = 10 + 20 + Ø15 = 45; aus Kapitel 10 + 2 = 12, aus Progression 0.5 · 45 ≈ 23 → Maximum.
        assertEquals(BookPageProgress(23, 45, 50), second)
        // Unbekanntes href → nur Kapitelseiten.
        assertEquals(BookPageProgress(4, 8, 90), estimator.bookWidePageProgress("x.xhtml", 0.9, RenderedPageInfo(4, 8)))
        estimator.invalidate()
        assertEquals(BookPageProgress(1, 3, 0), estimator.bookWidePageProgress("c.xhtml", 0.0, RenderedPageInfo(1, 1)))
    }

    @Test
    fun serverOfferOnlyWhenServerClearlyAhead() {
        assertEquals(ServerPositionOffer(0.5, 0.3), EbookProgressRules.serverPositionOffer(0.3, 0.5))
        assertEquals(ServerPositionOffer(0.32, 0.3), EbookProgressRules.serverPositionOffer(0.3, 0.32))
        assertNull(EbookProgressRules.serverPositionOffer(0.3, 0.31))
        assertNull(EbookProgressRules.serverPositionOffer(0.5, 0.3))
        // Ohne lokalen Locator (Server-Stand ist ohnehin Startposition) oder ohne Server-Stand: kein Angebot.
        assertNull(EbookProgressRules.serverPositionOffer(null, 0.8))
        assertNull(EbookProgressRules.serverPositionOffer(0.2, null))
    }

    @Test
    fun serverFractionForReaderIgnoresPendingAndEdges() {
        assertEquals(0.42, EbookProgressRules.serverFractionForReader(0.42, hasPendingSyncForItem = false)!!, 1e-9)
        assertNull(EbookProgressRules.serverFractionForReader(0.42, hasPendingSyncForItem = true))
        assertNull(EbookProgressRules.serverFractionForReader(0.004, false))
        assertNull(EbookProgressRules.serverFractionForReader(0.996, false))
        assertNull(EbookProgressRules.serverFractionForReader(Double.NaN, false))
        assertNull(EbookProgressRules.serverFractionForReader(null, false))
    }

    @Test
    fun resumeProgressionTakesMaximumInsideOpenRange() {
        assertEquals(0.6, EbookProgressRules.resumeProgression(0.6, 0.4)!!, 1e-9)
        assertEquals(0.4, EbookProgressRules.resumeProgression(0.001, 0.4)!!, 1e-9)
        assertNull(EbookProgressRules.resumeProgression(1.0, 0.4))
        assertNull(EbookProgressRules.resumeProgression(null, null))
        assertNull(EbookProgressRules.usableResumeProgression(0.005))
        assertEquals(0.3, EbookProgressRules.usableResumeProgression(0.3)!!, 1e-9)
        assertEquals(0, EbookProgressRules.positionIndex(0.5, 1))
        assertEquals(5, EbookProgressRules.positionIndex(0.5, 11))
        assertEquals(10, EbookProgressRules.positionIndex(1.0, 11))
    }

    @Test
    fun syncDecisionThrottlesAndDefers() {
        fun decide(f: Double, finished: Boolean = false, last: Double? = null, defer: Boolean = false, id: String = "li_1") =
            EbookProgressRules.syncDecision(id, f, finished, last, defer)
        assertEquals(SyncDecision.Ignore, decide(0.0005))
        assertEquals(SyncDecision.Ignore, decide(0.5, id = ""))
        assertEquals(SyncDecision.KeepFinished, decide(0.5, finished = true))
        assertEquals(SyncDecision.Schedule, decide(0.999, finished = true))
        assertEquals(SyncDecision.LocalOnly, decide(0.502, last = 0.5))
        assertEquals(SyncDecision.Schedule, decide(0.504, last = 0.5))
        assertEquals(SyncDecision.Deferred, decide(0.6, defer = true))
        // Bereits gesendet hat Vorrang vor Zurückstellen (kein neuer Pending-Eintrag).
        assertEquals(SyncDecision.LocalOnly, decide(0.6, last = 0.6, defer = true))
    }

    @Test
    fun displayFractionHonoursPendingOverride() {
        assertEquals(1.0, EbookProgressRules.displayFraction(0.999, 0.2, null)!!, 1e-9)
        assertNull(EbookProgressRules.displayFraction(0.0, 0.7, 0.7))
        assertEquals(0.7, EbookProgressRules.displayFraction(null, 0.7, 0.3)!!, 1e-9)
        assertEquals(1.0, EbookProgressRules.displayFraction(null, 0.996, null)!!, 1e-9)
        assertNull(EbookProgressRules.displayFraction(null, 0.003, null))
    }
}
