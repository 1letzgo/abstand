package de.letzgo.abstand.transcript

import de.letzgo.abstand.logic.PlayerTranscriptTrackSource
import de.letzgo.abstand.logic.PlayerTranscriptWord
import de.letzgo.abstand.logic.speech.SpeechModelCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class TranscriptPipelineTest {
    // MARK: Dekodierfenster

    @Test
    fun decodeWindowKeepsWholeBufferInsideRange() {
        assertEquals(0 until 1000, DecodeWindow.trim(10.0, 1000, 1000, 5.0, null))
    }

    @Test
    fun decodeWindowDropsFramesBeforeStart() {
        // Puffer beginnt bei 9,5 s, Start 10 s → erste 500 Frames (bei 1 kHz) verwerfen.
        assertEquals(500 until 1000, DecodeWindow.trim(9.5, 1000, 1000, 10.0, null))
    }

    @Test
    fun decodeWindowCutsAtEnd() {
        assertEquals(0 until 250, DecodeWindow.trim(10.0, 1000, 1000, 0.0, 10.25))
    }

    @Test
    fun decodeWindowOutsideRangeIsNull() {
        assertNull(DecodeWindow.trim(0.0, 1000, 1000, 5.0, null))
        assertNull(DecodeWindow.trim(20.0, 1000, 1000, 0.0, 20.0))
        assertNull(DecodeWindow.trim(0.0, 0, 1000, 0.0, null))
    }

    // MARK: Vosk-Ergebnis

    @Test
    fun voskResultParsesWordsWithOffsetAndDropsUnknown() {
        val raw = """{"result":[{"conf":1.0,"end":1.2,"start":0.9,"word":"hello"},""" +
            """{"conf":0.5,"end":1.5,"start":1.3,"word":"[unk]"},{"end":2.0,"start":1.6,"word":" world "}],"text":"hello world"}"""
        val words = VoskResult.words(raw, offset = 100.0)
        assertEquals(listOf("hello", "world"), words.map { it.text })
        assertEquals(100.9, words[0].start, 1e-9)
        assertEquals(101.2, words[0].end, 1e-9)
        assertEquals(101.6, words[1].start, 1e-9)
    }

    @Test
    fun voskResultWithoutWordsIsEmpty() {
        assertTrue(VoskResult.words("""{"text":""}""").isEmpty())
        assertTrue(VoskResult.words("").isEmpty())
        assertTrue(VoskResult.words("not json").isEmpty())
    }

    @Test
    fun voskResultEndBeforeStartIsClamped() {
        val w = VoskResult.words("""{"result":[{"start":2.0,"end":1.0,"word":"x"}]}""").single()
        assertEquals(2.0, w.end, 0.0)
    }

    // MARK: Sprach-/Modellauswahl

    @Test
    fun selectsBookLanguageModel() {
        val s = TranscriptionModelSelection.select("German", listOf(Locale.US))
        assertEquals("de", s.entry.code)
        assertEquals("de", s.localeIdentifier)
        assertFalse(s.usedFallback)
    }

    @Test
    fun selectsRegionalModelFromBookTag() {
        val s = TranscriptionModelSelection.select("en-GB", listOf(Locale.GERMANY))
        assertEquals("en-gb", s.entry.code)
        assertEquals("en-GB", s.localeIdentifier)
    }

    @Test
    fun plainEnglishBookOnUsDeviceUsesUsModel() {
        val s = TranscriptionModelSelection.select("English", listOf(Locale.US))
        assertEquals("en", s.entry.code)
    }

    @Test
    fun unsupportedBookLanguageFallsBackToDeviceLanguage() {
        // Hebräisch hat kein Vosk-Modell → Gerät (Deutsch), mit Fallback-Hinweis.
        val s = TranscriptionModelSelection.select("he", listOf(Locale.GERMANY))
        assertEquals("de", s.entry.code)
        assertTrue(s.usedFallback)
    }

    @Test
    fun noBookLanguageUsesDeviceWithoutFallbackNotice() {
        val s = TranscriptionModelSelection.select(null, listOf(Locale.FRANCE))
        assertEquals("fr", s.entry.code)
        assertFalse(s.usedFallback)
    }

    @Test
    fun prefetchNeedsInstalledModelAndNoFallback() {
        val installed = setOf("vosk-model-small-de-0.15")
        val isInstalled = { e: SpeechModelCatalog.Entry -> e.modelName in installed }
        assertEquals("de", TranscriptionModelSelection.prefetchSelection("de", isInstalled, listOf(Locale.US))?.entry?.code)
        assertNull(TranscriptionModelSelection.prefetchSelection("fr", isInstalled, listOf(Locale.US)))
        // Fallback (Buchsprache ohne Modell) wird nie vorproduziert.
        assertNull(TranscriptionModelSelection.prefetchSelection("he", isInstalled, listOf(Locale.GERMANY)))
    }

    // MARK: Produktionsnachführung

    @Test
    fun followPolicyKeepsRunningProductionAhead() {
        assertFalse(TranscriptFollowPolicy.shouldRestartProduction(50.0, covered = true, isProducing = false, productionStart = 0.0, productionThrough = 0.0))
        // Läuft gerade auf diese Stelle zu (innerhalb der Toleranz).
        assertFalse(TranscriptFollowPolicy.shouldRestartProduction(120.0, covered = false, isProducing = true, productionStart = 100.0, productionThrough = 95.0))
        // Sprung nach vorn über die Toleranz.
        assertTrue(TranscriptFollowPolicy.shouldRestartProduction(200.0, covered = false, isProducing = true, productionStart = 100.0, productionThrough = 120.0))
        // Sprung zurück vor den Laufstart.
        assertTrue(TranscriptFollowPolicy.shouldRestartProduction(50.0, covered = false, isProducing = true, productionStart = 100.0, productionThrough = 120.0))
        assertTrue(TranscriptFollowPolicy.shouldRestartProduction(50.0, covered = false, isProducing = false, productionStart = 0.0, productionThrough = 0.0))
    }

    @Test
    fun mergedByTimeSortsAndDropsDuplicates() {
        fun w(id: String, text: String, s: Double) = PlayerTranscriptWord(id, text, s, s + 0.2)
        val merged = TranscriptWordMerge.mergedByTime(listOf(w("a", "b ", 2.0), w("b", "a ", 1.0), w("c", "b ", 2.01), w("d", "c ", 3.0)))
        assertEquals(listOf("b", "a", "d"), merged.map { it.id })
    }

    // MARK: Vorproduktion

    private fun source(i: Int, offset: Double, duration: Double) = PlayerTranscriptTrackSource(i, "/t$i", offset, duration)

    private fun job(id: String, vararg sources: PlayerTranscriptTrackSource) = PlayerTranscriptJob(id, id, "de", sources.toList())

    @Test
    fun activeTitleComesFirstWithoutDuplicate() {
        val a = job("a", source(0, 0.0, 10.0))
        val b = job("b", source(0, 0.0, 10.0))
        val planned = PrefetchPlanner.orderJobs(a to 5.0, listOf(b, a))
        assertEquals(listOf("a", "b"), planned.map { it.job.storageId })
        assertEquals(5.0, planned[0].startGlobal!!, 0.0)
        assertNull(planned[1].startGlobal)
    }

    @Test
    fun trackOrderStartsAtPlaybackThenWrapsAround() {
        val j = job("a", source(0, 0.0, 100.0), source(1, 100.0, 100.0), source(2, 200.0, 100.0))
        val steps = PrefetchPlanner.trackOrder(PrefetchPlanner.PlannedJob(j, 150.0))
        assertEquals(listOf(1, 2, 0), steps.map { it.source.trackIndex })
        assertEquals(listOf(50.0, 0.0, 0.0), steps.map { it.from })
    }

    @Test
    fun trackOrderWithoutPositionStartsAtBeginning() {
        val j = job("a", source(0, 0.0, 100.0), source(1, 100.0, 100.0))
        val steps = PrefetchPlanner.trackOrder(PrefetchPlanner.PlannedJob(j, null))
        assertEquals(listOf(0, 1), steps.map { it.source.trackIndex })
        assertEquals(listOf(0.0, 0.0), steps.map { it.from })
    }

    @Test
    fun blockingReasonsInPriorityOrder() {
        assertNull(PrefetchPlanner.blockingReason(false, false, false))
        assertEquals("Paused while read along is preparing", PrefetchPlanner.blockingReason(true, true, true))
        assertEquals("Paused in Battery Saver", PrefetchPlanner.blockingReason(false, true, true))
        assertEquals("Paused while the device is warm", PrefetchPlanner.blockingReason(false, false, true))
    }

    @Test
    fun downloadAccountFilter() {
        assertTrue(PrefetchPlanner.belongsToActiveAccount(null, setOf("l1")))
        assertTrue(PrefetchPlanner.belongsToActiveAccount("l2", emptySet()))
        assertTrue(PrefetchPlanner.belongsToActiveAccount(" l1 ", setOf("l1")))
        assertFalse(PrefetchPlanner.belongsToActiveAccount("l2", setOf("l1")))
    }

    @Test
    fun prefetchSubtitleStates() {
        assertNull(TranscriptSettings.prefetchSubtitle(false, null, false, 0, 0, null))
        assertEquals("Paused in Battery Saver", TranscriptSettings.prefetchSubtitle(true, "Paused in Battery Saver", true, 1, 2, "X"))
        assertEquals("Preparing Book · 1 of 3 tracks", TranscriptSettings.prefetchSubtitle(true, null, true, 1, 3, "Book"))
        assertEquals("Preparing… 0 of 3 tracks", TranscriptSettings.prefetchSubtitle(true, null, true, 0, 3, null))
    }

    // MARK: Wort-Sheet

    @Test
    fun translationTargetNormalization() {
        assertEquals("fr", TranslationTargetLanguage.normalized("fr-FR", Locale.GERMANY))
        assertEquals("de", TranslationTargetLanguage.normalized("xx", Locale.GERMANY))
        assertEquals("de", TranslationTargetLanguage.load(stored = null, device = Locale.GERMANY))
        assertEquals("es", TranslationTargetLanguage.load(stored = " ES ", device = Locale.GERMANY))
        assertTrue(TranslationTargetLanguage.sameLanguage(Locale.forLanguageTag("de"), "DE"))
        assertFalse(TranslationTargetLanguage.sameLanguage(null, "de"))
    }

    @Test
    fun lookupLinksEncodeTerm() {
        assertEquals(
            "https://translate.google.com/?sl=de&tl=en&text=sch%C3%B6ne%20Gr%C3%BC%C3%9Fe&op=translate",
            WordLookupLinks.translateUrl("schöne Grüße", "de", "en"),
        )
        assertTrue(WordLookupLinks.translateUrl("x", null, "en").contains("sl=auto"))
        assertEquals("https://www.google.com/search?q=a%26b", WordLookupLinks.searchUrl("a&b"))
    }

    @Test
    fun podcastStorageIdMatchesDownloadFolder() {
        assertEquals("show", PlaybackTranscription.storageId(" show ", null))
        assertEquals("show-ep_1", PlaybackTranscription.storageId("show", " ep/1 "))
    }
}
