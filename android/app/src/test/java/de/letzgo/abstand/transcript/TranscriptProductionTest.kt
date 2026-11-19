package de.letzgo.abstand.transcript

import de.letzgo.abstand.logic.PlayerTranscriptCacheStore
import de.letzgo.abstand.logic.PlayerTranscriptLibrary
import de.letzgo.abstand.logic.PlayerTranscriptRunWindow
import de.letzgo.abstand.logic.PlayerTranscriptTrackCache
import de.letzgo.abstand.logic.PlayerTranscriptTrackCache.Segment
import de.letzgo.abstand.logic.PlayerTranscriptTrackCache.Word
import de.letzgo.abstand.logic.PlayerTranscriptTrackSource
import de.letzgo.abstand.logic.SpeechEnvelope
import de.letzgo.abstand.logic.SpeechOnsetRefinementBatcher
import de.letzgo.abstand.logic.SpeechOnsetRefiner
import de.letzgo.abstand.logic.SpeechOnsetWord
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.io.File
import kotlin.io.path.createTempDirectory
import kotlin.random.Random

/**
 * Abbruch, Abdeckung und Laufgrenzen der Transkript-Produktion (iOS: `PlayerTranscriptLibrary.fillGap`/
 * `persistProduction`, `PlayerTranscriptTrackCache.insert`, `PlayerTranscriptRefinementBatcher`) — mit
 * Producer-Ersatz und echtem Dateispeicher.
 */
class TranscriptProductionTest {
    private val bookId = "li_test"
    private val locale = "de-DE"
    private val trackIndex = 33

    // Ein-Datei-Hörbuch wie auf dem iOS-Gerät: Server-Dauer 51 881 s.
    private val source = PlayerTranscriptTrackSource(trackIndex, "/nicht/benutzt.mp3", 0.0, 51881.0)
    private lateinit var account: File

    @Before
    fun setUp() {
        account = createTempDirectory("transcripts").toFile()
    }

    @After
    fun tearDown() {
        account.deleteRecursively()
    }

    private fun file() = PlayerTranscriptCacheStore.fileFor(account, bookId, trackIndex, locale)

    private fun write(version: Int, segments: List<Segment>) {
        PlayerTranscriptCacheStore.save(
            PlayerTranscriptTrackCache(version = version, localeIdentifier = locale, trackIndex = trackIndex, segments = segments),
            account, bookId,
        )
    }

    private fun load() = PlayerTranscriptCacheStore.load(account, bookId, trackIndex, locale)

    /** Wörter alle 0,5 s (0,4 s lang) bis [until]. */
    private fun words(from: Double, until: Double): List<Word> {
        val out = ArrayList<Word>()
        var t = Math.ceil(from * 2) / 2
        while (t + 0.4 <= until) {
            out.add(Word("w${Math.round(t * 2)}", t, t + 0.4)); t += 0.5
        }
        return out
    }

    private val legacyFull get() = listOf(Segment(0.0, 51881.0, words(0.0, 180.0)))

    /** Producer-Ersatz: [batches] nacheinander mit [delayMs] Abstand, dann Ende. */
    private fun fake(delayMs: Long, vararg batches: PlayerTranscriptProductionBatch): Flow<PlayerTranscriptProductionBatch> = flow {
        for (b in batches) {
            delay(delayMs)
            emit(b)
        }
    }

    private suspend fun fill(
        gapStart: Double,
        gapEnd: Double?,
        isCurrent: () -> Boolean = { true },
        onBatch: (suspend (PlayerTranscriptProductionBatch) -> Unit)? = null,
        batches: (PlayerTranscriptRunWindow) -> Flow<PlayerTranscriptProductionBatch>,
    ) = PlayerTranscriptProduction.fillGap(
        null, bookId, source, null, locale, gapStart, gapEnd, isCurrent, account, onBatch, batches,
    )

    private fun produced(w: List<Word>) = w.map { PlayerTranscriptProducedWord(it.t, it.s, it.e) }

    // MARK: Abbruch

    @Test
    fun cancelBeforeFirstResultMarksNothingAndKeepsExistingState() = runBlocking {
        for (existing in listOf(4 to listOf(Segment(0.0, 100.0, words(0.0, 100.0))), 2 to legacyFull)) {
            write(existing.first, existing.second)
            val before = file().readBytes()
            var seen = 0
            val job = async {
                fill(125.82, null, onBatch = { seen += 1 }) {
                    fake(500, PlayerTranscriptProductionBatch(produced(words(126.0, 140.0)), 140.0, false))
                }
            }
            delay(50)
            job.cancel()
            try {
                job.await(); fail("Abbruch muss als Ausnahme enden")
            } catch (_: CancellationException) {
            }
            assertEquals(0, seen)
            assertArrayEquals("Version ${existing.first}: Datei unverändert", before, file().readBytes())
        }
    }

    @Test
    fun cancelMidRunPersistsOnlyRealWordsAndNeverMarksTheRest() = runBlocking {
        write(4, listOf(Segment(0.0, 100.0, words(0.0, 100.0))))
        var seen = 0
        val job = async {
            fill(100.0, null, onBatch = { seen += 1 }) {
                fake(
                    20,
                    // Wie der echte Producer: verarbeitet bis zum Ende des letzten Worts.
                    PlayerTranscriptProductionBatch(produced(words(97.0, 110.0)), 109.9, false),
                    PlayerTranscriptProductionBatch(produced(words(110.0, 120.0)), 119.9, false),
                    PlayerTranscriptProductionBatch(emptyList(), 180.0, true),
                )
            }
        }
        while (seen < 1) delay(1)
        job.cancel()
        try {
            job.await(); fail()
        } catch (_: CancellationException) {
        }
        val c = load()!!
        val maxEnd = c.segments.maxOf { it.end }
        assertTrue("keine Abdeckung über das letzte Wort hinaus ($maxEnd)", maxEnd <= c.allWords.last().e + 1e-9)
        assertTrue(maxEnd < 1000)
        assertEquals(0.0, c.segments.first().start, 0.0)
        // Keine Doppelten aus dem Vorlauf (97–100 s gehören dem vorhandenen Segment).
        assertEquals(c.allWords.size, c.allWords.map { it.t }.toSet().size)
    }

    @Test
    fun supersededRunDoesNotMarkTheRest() = runBlocking {
        write(4, listOf(Segment(0.0, 100.0, emptyList())))
        try {
            fill(100.0, null, isCurrent = { false }) {
                fake(0, PlayerTranscriptProductionBatch(emptyList(), 100.0, true))
            }
            fail()
        } catch (_: CancellationException) {
        }
        assertEquals(listOf(0.0 to 100.0), load()!!.segments.map { it.start to it.end })
    }

    @Test
    fun streamEndingWithoutFinalBatchIsNotCompletion() = runBlocking {
        write(4, listOf(Segment(0.0, 100.0, emptyList())))
        val before = file().readBytes()
        try {
            fill(100.0, null) { emptyFlow() }
            fail()
        } catch (_: PlayerTranscriptEndedWithoutFinalBatch) {
        }
        assertArrayEquals(before, file().readBytes())
    }

    @Test
    fun finalBatchBeforeServerDurationMarksRestWithoutWords() = runBlocking {
        val next = fill(0.0, null) { w ->
            fake(0, PlayerTranscriptProductionBatch(produced(words(w.runStart, 180.0)), 179.9, false), PlayerTranscriptProductionBatch(emptyList(), 180.0, true))
        }
        assertEquals(51881.0, next, 0.0)
        val c = load()!!
        assertNull(c.firstUncoveredTime(0.0, source.duration))
        assertEquals(360, c.allWords.size)
    }

    // MARK: Versionen und alter Stand

    @Test
    fun version3IsDiscardedVersion2ReadVersion4Current() = runBlocking {
        write(3, legacyFull)
        assertNull(load())
        // Vorproduktion behandelt die Datei als leer und ersetzt sie durch Version 4.
        assertEquals(PlayerTranscriptLibrary.Gap(0.0, null), PlayerTranscriptLibrary.nextGap(bookId, source, locale, 0.0, account))
        PlayerTranscriptLibrary.mergeAndSave(Segment(0.0, 5.0, listOf(Word("neu", 1.0, 1.5))), bookId, trackIndex, locale, account)
        assertEquals(4, load()!!.version)
        assertEquals(listOf(0.0 to 5.0), load()!!.segments.map { it.start to it.end })
        write(2, legacyFull)
        assertFalse(load()!!.isOnsetRefined)
        assertEquals(2, load()!!.version)
        assertEquals(4, PlayerTranscriptTrackCache.CURRENT_VERSION)
    }

    @Test
    fun legacyStateIsNeverReplacedByLessCoverageClaimingMore() = runBlocking {
        val legacy = PlayerTranscriptTrackCache(version = 2, localeIdentifier = locale, trackIndex = trackIndex, segments = legacyFull)
        assertFalse(legacy.insert(Segment(125.82, 51881.0, emptyList())))
        assertFalse(legacy.insert(Segment(125.82, 51881.0, words(126.0, 129.0))))
        assertEquals(2, legacy.version)
        assertEquals(360, legacy.allWords.size)
        // Ehrliches Teilsegment (gleich viele Wörter in seinem Bereich) ersetzt den alten Stand.
        assertTrue(legacy.insert(Segment(125.82, 160.0, words(126.0, 160.0))))
        assertEquals(4, legacy.version)
        assertEquals(listOf(125.82 to 160.0), legacy.segments.map { it.start to it.end })
        // mergeAndSave schreibt bei Ablehnung nicht.
        write(2, legacyFull)
        val before = file().readBytes()
        PlayerTranscriptLibrary.mergeAndSave(Segment(125.82, 51881.0, emptyList()), bookId, trackIndex, locale, account)
        assertArrayEquals(before, file().readBytes())
    }

    // MARK: Laufgrenzen

    @Test
    fun runWindowPreRollAndPostRoll() {
        val w = PlayerTranscriptRunWindow(10.0, 20.0)
        assertEquals(7.0, w.runStart, 0.0)
        assertEquals(22.5, w.runEnd!!, 0.0)
        assertFalse(w.keeps(7.0)) // am Laufstart klebendes erstes Wort
        assertFalse(w.keeps(9.6))
        assertTrue(w.keeps(9.75))
        assertTrue(w.keeps(19.9))
        assertFalse(w.keeps(20.0))
        assertEquals(0.0, PlayerTranscriptRunWindow(1.0, null).runStart, 0.0)
        assertNull(PlayerTranscriptRunWindow(1.0, null).runEnd)
    }

    @Test
    fun mergeAtRunBoundariesHasNoDuplicatesAndKeepsBoundaryWord() {
        val cache = PlayerTranscriptTrackCache(localeIdentifier = locale, trackIndex = trackIndex)
        cache.insert(Segment(0.0, 10.0, listOf(Word("das", 9.2, 9.5), Word("Haus", 9.5, 10.0))))
        val window = PlayerTranscriptRunWindow(10.0, null)
        val run = listOf(Word("Pre", 7.5, 7.9), Word("das", 9.21, 9.5), Word("Haus", 9.72, 10.01), Word("steht", 10.02, 10.4))
        val kept = run.filter { window.keeps(it.s) }
        assertEquals(listOf("Haus", "steht"), kept.map { it.t })
        cache.insert(Segment(10.0, 12.0, kept))
        assertEquals(listOf("das", "Haus", "steht"), cache.allWords.map { it.t })

        val right = PlayerTranscriptTrackCache(localeIdentifier = locale, trackIndex = trackIndex)
        right.insert(Segment(20.0, 40.0, listOf(Word("zwei", 20.1, 20.5), Word("drei", 20.6, 21.0))))
        val w2 = PlayerTranscriptRunWindow(0.0, 20.0)
        val left = listOf(Word("eins", 19.4, 20.05), Word("zwei", 20.08, 20.5), Word("drei", 20.6, 21.0))
        right.insert(Segment(0.0, 22.5, left.filter { w2.keeps(it.s) }))
        assertEquals(listOf("eins", "zwei", "drei"), right.allWords.map { it.t })
        assertNull(right.firstUncoveredTime(0.0, 40.5))
    }

    /** Ablauf wie `PlayerTranscriptPrefetcher.prepare` (ohne Pausen); Rückgabe: Läufe, −1 = Schutz gegriffen. */
    private suspend fun prefetch(from: Double, batches: (PlayerTranscriptRunWindow) -> Flow<PlayerTranscriptProductionBatch>): Int {
        var cursor = from
        var last: Double? = null
        var runs = 0
        while (true) {
            val gap = PlayerTranscriptLibrary.nextGap(bookId, source, locale, cursor, account) ?: break
            if (last != null && gap.start <= last + 0.5) return -1
            runs += 1
            if (runs > 50) return -999
            cursor = fill(gap.start, gap.end, batches = batches)
            if (gap.end == null) break
            last = gap.start
        }
        return runs
    }

    /** Producer-Ersatz über eine 180-s-Datei: liefert alle Wörter des Lauf-Fensters, dann den finalen Batch. */
    private val file180: (PlayerTranscriptRunWindow) -> Flow<PlayerTranscriptProductionBatch> = { w ->
        val end = minOf(180.0, w.runEnd ?: 180.0)
        val ws = produced(words(w.runStart, end))
        flow {
            emit(PlayerTranscriptProductionBatch(ws, ws.lastOrNull()?.end ?: w.runStart, false))
            emit(PlayerTranscriptProductionBatch(emptyList(), end, true))
        }
    }

    @Test
    fun preRollMergeHasNoDuplicatesNoGapsAndNoEndlessLoop() = runBlocking {
        assertEquals(1, prefetch(77.3, file180))
        assertEquals(1, prefetch(0.0, file180))
        val names = load()!!.allWords.map { it.t }
        assertEquals(names.size, names.toSet().size)
        assertEquals(360, names.size)
        assertNull(load()!!.firstUncoveredTime(0.0, source.duration))
        // Kurze Lücke in der Mitte: ein Lauf schließt sie.
        write(4, listOf(Segment(0.0, 60.0, emptyList()), Segment(61.0, 51881.0, emptyList())))
        assertEquals(1, prefetch(0.0, file180))
        // Lauf ohne Wörter, Datei endet vor der Lücke (finaler Batch belegt es): Lücke geschlossen, keine Wiederholung.
        write(4, listOf(Segment(0.0, 60.0, emptyList()), Segment(300.0, 51881.0, emptyList())))
        assertEquals(1, prefetch(0.0) { w -> flow { emit(PlayerTranscriptProductionBatch(emptyList(), minOf(200.0, w.runEnd ?: 200.0), true)) } })
        assertNull(load()!!.firstUncoveredTime(0.0, source.duration))
    }

    // MARK: Batch-Enden

    @Test
    fun batchEndIsTrimmedLikeASingleList() {
        val rnd = Random(42)
        val levels = FloatArray(6000) { -20f }
        val raw = ArrayList<SpeechOnsetWord>()
        var t = 1.0
        var i = 0
        while (t < 55) {
            val dur = 0.2 + rnd.nextDouble() * 0.4
            val pause = if (rnd.nextBoolean()) 0.3 + rnd.nextDouble() * 0.5 else 0.0
            raw.add(SpeechOnsetWord("w$i", t, t + dur + pause * 0.7))
            if (pause > 0) for (k in ((t + dur) * 100).toInt() until minOf(levels.size, ((t + dur + pause) * 100).toInt())) levels[k] = -80f
            t += dur + pause
            i += 1
        }
        // Anfänge wie der Erkenner: bei 70 % der Pause davor (= Ende des Vorworts).
        val words = raw.mapIndexed { j, w -> if (j == 0) w else SpeechOnsetWord(w.text, raw[j - 1].end, w.end) }
        val env = SpeechEnvelope(0.0, levels)
        val refine = { ws: List<SpeechOnsetWord>, p: SpeechOnsetWord? -> SpeechOnsetRefiner.refine(ws, env, p) }
        val single = refine(words, null)
        var oldLong = 0
        repeat(100) {
            val cuts = (0 until 8).map { 1 + rnd.nextInt(words.size - 1) }.toSortedSet().toList()
            val bounds = listOf(0) + cuts + listOf(words.size)
            val batcher = SpeechOnsetRefinementBatcher()
            val out = ArrayList<SpeechOnsetWord>()
            val old = ArrayList<SpeechOnsetWord>()
            var oldPrevious: SpeechOnsetWord? = null
            for (k in 0 until bounds.size - 1) {
                val chunk = words.subList(bounds[k], bounds[k + 1])
                out += batcher.add(chunk, refine)
                val o = refine(chunk, oldPrevious)
                oldPrevious = o.last()
                old += o
            }
            out += batcher.finish(refine)
            assertEquals(single, out)
            for (b in bounds.drop(1).dropLast(1)) if (old[b - 1].end - single[b - 1].end > 0.05) oldLong += 1
        }
        assertTrue("bisher blieben Batch-Enden lang ($oldLong)", oldLong > 0)
    }

    @Test
    fun batcherKeepsPunctuationAndEmitsEverythingOnce() {
        val env = SpeechEnvelope(0.0, FloatArray(500) { -20f })
        val refine = { ws: List<SpeechOnsetWord>, p: SpeechOnsetWord? -> SpeechOnsetRefiner.refine(ws, env, p) }
        val b = SpeechOnsetRefinementBatcher()
        val out = ArrayList<SpeechOnsetWord>()
        out += b.add(listOf(SpeechOnsetWord("a", 1.0, 1.3), SpeechOnsetWord(",", 1.3, 1.3)), refine)
        out += b.add(listOf(SpeechOnsetWord(".", 1.4, 1.4)), refine)
        out += b.add(listOf(SpeechOnsetWord("b", 2.0, 2.3)), refine)
        out += b.finish(refine)
        assertEquals(listOf("a", ",", ".", "b"), out.map { it.text })
        assertTrue(b.finish(refine).isEmpty())
    }
}
