package de.letzgo.abstand.logic

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.float
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

/** Akustische Einsatz-Erkennung (`SpeechOnsetRefiner`, iOS: SpeechOnsetRefinement.swift) mit synthetischen Hüllkurven. */
class SpeechOnsetRefinementTest {
    private val speech = -20f
    private val silence = -80f

    /** Hüllkurve ab [start] aus Abschnitten (bis-Zeit, Pegel); 10-ms-Fenster. */
    private fun envelope(start: Double, vararg parts: Pair<Double, Float>): SpeechEnvelope {
        val levels = ArrayList<Float>()
        for ((until, level) in parts) {
            val endFrame = Math.round((until - start) / 0.01).toInt()
            while (levels.size < endFrame) levels.add(level)
        }
        return SpeechEnvelope(start, levels.toFloatArray())
    }

    private fun w(text: String, s: Double, e: Double) = SpeechOnsetWord(text, s, e)

    @Test
    fun wordAfterPauseStartsAtOnsetAndPreviousEndsAtSilence() {
        // Sprache bis 2,0 s, Pause bis 2,6 s, dann Sprache. Erkenner: Vorwort-Ende und Wortanfang in der Pause.
        val env = envelope(0.0, 2.0 to speech, 2.6 to silence, 4.0 to speech)
        val out = SpeechOnsetRefiner.refine(listOf(w("eins", 1.0, 2.3), w("zwei", 2.3, 3.0)), env)
        assertEquals(2.59, out[1].start, 1e-9)
        assertEquals(3.0, out[1].end, 0.0)
        assertEquals(2.0, out[0].end, 1e-9)
        assertEquals(1.0, out[0].start, 0.0)
    }

    @Test
    fun breathInPauseIsNotAnOnset() {
        // 60-ms-Atmer mitten in der Pause (unter 9 von 15 Fenstern) gehört zur Stille.
        val env = envelope(0.0, 2.0 to speech, 2.3 to silence, 2.36 to -30f, 2.8 to silence, 4.0 to speech)
        val out = SpeechOnsetRefiner.refine(listOf(w("eins", 1.0, 2.0), w("zwei", 2.1, 3.2)), env)
        assertEquals(2.79, out[1].start, 1e-9)
    }

    @Test
    fun inhaleBeforeSpeechIsSkipped() {
        // Atmer 0,3 s bei −36 dBFS (16 dB unter der Sprache), 50 ms Einbruch, dann Sprache ab 2,85 s.
        val env = envelope(0.0, 2.0 to speech, 2.5 to silence, 2.8 to -36f, 2.85 to silence, 4.0 to speech)
        val out = SpeechOnsetRefiner.refine(listOf(w("eins", 1.0, 2.0), w("zwei", 2.3, 3.4)), env)
        assertEquals(2.85 - 0.01, out[1].start, 1e-9)
        // Ohne Einbruch (Anlaut geht direkt in Sprache über) bleibt der erste Einsatz.
        val soft = envelope(0.0, 2.0 to speech, 2.5 to silence, 2.8 to -36f, 4.0 to speech)
        assertEquals(2.49, SpeechOnsetRefiner.refine(listOf(w("eins", 1.0, 2.0), w("zwei", 2.3, 3.4)), soft)[1].start, 1e-9)
        // Lauter Anlaut (über Sprachpegel − 12 dB) ist kein Atmer.
        val loud = envelope(0.0, 2.0 to speech, 2.5 to silence, 2.8 to -28f, 2.85 to silence, 4.0 to speech)
        assertEquals(2.49, SpeechOnsetRefiner.refine(listOf(w("eins", 1.0, 2.0), w("zwei", 2.3, 3.4)), loud)[1].start, 1e-9)
    }

    @Test
    fun continuousSpeechAndMusicStayUnchanged() {
        val words = listOf(w("a", 1.0, 1.4), w("b", 1.4, 1.9), w("c", 1.9, 2.6), w("d", 2.6, 3.2))
        val wobble = SpeechEnvelope(0.0, FloatArray(400) { -20f + 3f * sin(it / 7.0).toFloat() })
        assertEquals(words, SpeechOnsetRefiner.refine(words, wobble))
        // Musik unter der Stimme: nie 28 dB unter dem Sprachpegel → keine Stille.
        val music = envelope(0.0, 1.5 to speech, 2.2 to -32f, 4.0 to speech)
        assertEquals(words, SpeechOnsetRefiner.refine(words, music))
    }

    @Test
    fun quietPassagesWorkUntilTheReferenceIsSilenceItself() {
        val words = listOf(w("eins", 1.0, 2.3), w("zwei", 2.3, 3.0))
        val quiet = envelope(0.0, 2.0 to -50f, 2.6 to -95f, 4.0 to -50f)
        assertEquals(2.59, SpeechOnsetRefiner.refine(words, quiet)[1].start, 1e-9)
        val nothing = envelope(0.0, 2.0 to -65f, 2.6 to -99f, 4.0 to -65f)
        assertEquals(words, SpeechOnsetRefiner.refine(words, nothing))
    }

    @Test
    fun pauseAfterTheWordBelongsToTheNextWord() {
        // „Komma," wird ohne Pause davor gesprochen (bis 1,5 s), dann Pause; das Folgewort setzt bei 2,5 ein,
        // liegt aber noch im Wortbereich von „Komma,". Die Stille beginnt hinter dem Wortanfang: keine Änderung —
        // und das Folgewort darf nicht vor das Ende seines Vorworts (3,0 − 0,05) zurück.
        val env = envelope(0.0, 1.5 to speech, 2.5 to silence, 4.0 to speech)
        val words = listOf(w("Komma,", 1.0, 3.0), w("weiter", 3.0, 3.6))
        assertEquals(words, SpeechOnsetRefiner.refine(words, env))
    }

    @Test
    fun recognizerLateStartMovesEarlierButNotBeforeThePreviousWord() {
        val env = envelope(0.0, 2.0 to speech, 2.6 to silence, 4.0 to speech)
        val out = SpeechOnsetRefiner.refine(listOf(w("eins", 1.0, 2.0), w("zwei", 2.75, 3.4)), env)
        assertEquals(2.59, out[1].start, 1e-9)
        // Vorwort endet erst kurz vor dem erkannten Anfang, klingt aber vor der Stille (Pause im Vorwort):
        // Einsatz trotz Vorwort-Ende − 0,05 s übernommen, Vorwort endet am Beginn der Stille.
        val tight = SpeechOnsetRefiner.refine(listOf(w("eins", 1.0, 2.7), w("zwei", 2.75, 3.4)), env)
        assertEquals(2.59, tight[1].start, 1e-9)
        assertEquals(2.0, tight[0].end, 1e-9)
    }

    @Test
    fun pauseInsideThePreviousWordLetsTheWordStartAtTheOnset() {
        // Gerätefund „Theorie, so": Erkenner legt die Wörter lückenlos, die Pause steckt im Vorwort
        // (roh 1,0–2,8), der rohe Anfang liegt 0,2 s hinter dem Einsatz bei 2,6.
        val env = envelope(0.0, 2.0 to speech, 2.6 to silence, 4.0 to speech)
        val out = SpeechOnsetRefiner.refine(listOf(w("Theorie,", 1.0, 2.8), w("so", 2.8, 3.1), w("hatte", 3.1, 3.4)), env)
        assertEquals(2.59, out[1].start, 1e-9)
        assertEquals(2.0, out[0].end, 1e-9)
        assertEquals(1.0, out[0].start, 0.0)
        assertEquals(3.1, out[1].end, 0.0)
        assertEquals(3.1, out[2].start, 0.0)
    }

    @Test
    fun pauseAtTheStartOfThePreviousWordKeepsTheLock() {
        // Stille beginnt mit dem Vorwort: „und" selbst wandert an den Einsatz; das Folgewort folgt ihm nicht
        // auf denselben Einsatz (Vorwort hat vor der Stille keinen Schall) und bleibt, wie erkannt.
        val env = envelope(0.0, 2.0 to speech, 2.6 to silence, 4.0 to speech)
        val words = listOf(w("Ordnung", 1.4, 2.0), w("und", 2.0, 2.8), w("er", 2.8, 3.0), w("ging", 3.0, 3.4))
        val out = SpeechOnsetRefiner.refine(words, env)
        assertEquals(2.59, out[1].start, 1e-9)
        assertEquals(2.8, out[2].start, 0.0)
        // Mehr als 0,3 s hinter dem Einsatz: auch mit Pause im Vorwort unverändert.
        val far = listOf(w("Theorie,", 1.0, 3.0), w("so", 3.0, 3.3))
        assertEquals(far, SpeechOnsetRefiner.refine(far, env))
    }

    @Test
    fun shortWordInsideThePauseMovesToTheOnset() {
        // Englischer Erkenner: „he" liegt ganz in der Pause (2,3–2,5), die Sprache setzt erst bei 2,6 ein.
        val env = envelope(0.0, 2.0 to speech, 2.6 to silence, 4.0 to speech)
        val words = listOf(w("said.", 1.0, 2.0), w("he", 2.3, 2.5), w(",", 2.5, 2.55), w("began.", 2.9, 3.4))
        val out = SpeechOnsetRefiner.refine(words, env)
        assertEquals(2.59, out[1].start, 1e-9)
        // Ende: Anfang + Mindestlänge (2 Buchstaben × 0,06 s), nie über das Folgewort.
        assertEquals(2.59 + 0.12, out[1].end, 1e-9)
        assertTrue(out[1].end <= out[3].start)
        // Satzzeichen-Token wandert mit ans neue Ende statt vor dem Wort zu liegen.
        assertEquals(out[1].end, out[2].start, 1e-9)
        assertEquals(out[1].end, out[2].end, 1e-9)
        // Folgewort und Vorwort bleiben unverändert, die Anfänge monoton.
        assertEquals(words[3], out[3])
        assertEquals(words[0], out[0])
        for (i in 1 until out.size) assertTrue(out[i].start >= out[i - 1].start)
    }

    @Test
    fun wordInsideThePauseStopsBeforeAContiguousNextWord() {
        // Folgewort beginnt direkt am rohen Ende (typisch): Anfang höchstens bis Folgewort − Mindestlänge.
        val env = envelope(0.0, 2.0 to speech, 2.6 to silence, 4.0 to speech)
        val words = listOf(w("said.", 1.0, 2.0), w("he", 2.3, 2.62), w("began.", 2.62, 3.2))
        val out = SpeechOnsetRefiner.refine(words, env)
        assertEquals(2.62 - 0.08, out[1].start, 1e-9)
        assertEquals(2.62, out[1].end, 0.0)
        assertEquals(words[2], out[2])
    }

    @Test
    fun onsetTooFarBehindTheWordLeavesItUnchanged() {
        // Einsatz 0,4 s hinter dem rohen Ende (> LATE_ONSET_SECONDS): Wort nicht über die Stille hängen.
        val env = envelope(0.0, 1.8 to speech, 2.6 to silence, 4.0 to speech)
        val words = listOf(w("eins", 1.0, 1.8), w("he", 2.0, 2.2), w("zwei", 3.0, 3.5))
        assertEquals(words, SpeechOnsetRefiner.refine(words, env))
    }

    @Test
    fun spokenWordBeforeThePauseIsNotHungOnTheNextOnset() {
        // „du" klingt am rohen Anfang noch (Sprache bis 2,1), die Stille beginnt danach: Der Einsatz bei 2,5
        // gehört zum Folgewort, „du" bleibt (nur sein Ende wird auf den Beginn der Stille gekürzt).
        val env = envelope(0.0, 2.1 to speech, 2.5 to silence, 4.0 to speech)
        val words = listOf(w("Jennifer,", 1.0, 2.0), w("du", 2.0, 2.3), w("liegst", 2.3, 2.9))
        val out = SpeechOnsetRefiner.refine(words, env)
        assertEquals(2.0, out[1].start, 0.0)
        assertEquals(2.1, out[1].end, 1e-9)
        assertEquals(2.49, out[2].start, 1e-9)
    }

    @Test
    fun punctuationTokensAndInvalidWordsStayUnchanged() {
        val env = envelope(0.0, 2.0 to speech, 2.6 to silence, 4.0 to speech)
        val words = listOf(w("eins", 1.0, 2.0), w(".", 2.1, 2.2), w("zwei", 2.2, 3.0), w("drei", 3.5, 3.5))
        val out = SpeechOnsetRefiner.refine(words, env)
        assertEquals(words[1], out[1])
        assertEquals(2.59, out[2].start, 1e-9)
        assertEquals(words[3], out[3])
    }

    @Test
    fun envelopeStartingMidPause() {
        val words = listOf(w("zwei", 2.3, 3.0))
        // Hüllkurve beginnt 0,3 s vor dem Einsatz (Produktion startet mitten in der Pause): reicht.
        assertEquals(2.59, SpeechOnsetRefiner.refine(words, envelope(2.3, 2.6 to silence, 4.0 to speech))[0].start, 1e-9)
        // Nur 0,1 s Stille bekannt: davor ist unbekannt, keine Änderung.
        assertEquals(words, SpeechOnsetRefiner.refine(words, envelope(2.5, 2.6 to silence, 4.0 to speech)))
    }

    @Test
    fun trackStartingWithSilenceMovesTheFirstWordToTheOnset() {
        // Erkenner setzt das erste Wort eines Tracks auf 0,00 s (Gerätefund iOS), die Sprache kommt später.
        val words = listOf(w("Er", 0.0, 0.6), w("bestellte", 0.6, 1.0))
        val long = SpeechOnsetRefiner.refine(words, envelope(0.0, 0.3 to silence, 3.0 to speech))
        assertEquals(0.29, long[0].start, 1e-9)
        assertEquals(words[1], long[1])
        // Kürzer als die Mindeststille: am Track-Anfang reicht sie trotzdem (vorher: unverändert 0,00).
        val short = SpeechOnsetRefiner.refine(words, envelope(0.0, 0.12 to silence, 3.0 to speech))
        assertEquals(0.11, short[0].start, 1e-9)
        assertEquals(0.6, short[0].end, 0.0)
    }

    @Test
    fun trackStartingWithSpeechStaysUnchanged() {
        val words = listOf(w("Er", 0.0, 0.6), w("bestellte", 0.6, 1.0))
        assertEquals(words, SpeechOnsetRefiner.refine(words, envelope(0.0, 3.0 to speech)))
        // Ein digital stilles Fenster vor der Sprache (Decoder) ändert nichts.
        assertEquals(words, SpeechOnsetRefiner.refine(words, envelope(0.0, 0.01 to -140f, 3.0 to speech)))
        // Erkenner zu spät, Sprache ab 0: kein Einsatz nach Stille → unverändert.
        val late = listOf(w("Er", 0.3, 0.6))
        assertEquals(late, SpeechOnsetRefiner.refine(late, envelope(0.0, 3.0 to speech)))
    }

    @Test
    fun breathAtTrackStartIsSkipped() {
        // 0,12 s Stille, 0,2 s Atmer bei −36 dBFS, 50 ms Einbruch, Sprache ab 0,37 s.
        val words = listOf(w("Er", 0.0, 0.6), w("bestellte", 0.6, 1.0))
        val env = envelope(0.0, 0.12 to silence, 0.32 to -36f, 0.37 to silence, 3.0 to speech)
        assertEquals(0.36, SpeechOnsetRefiner.refine(words, env)[0].start, 1e-9)
    }

    @Test
    fun speechLevelAtTrackStartUsesTheFirstSeconds() {
        // Leiser Anfang (−26 dBFS), danach lauter (−14): aus nur [0, Wortende] läge der Sprachpegel bei −26
        // und der Atmer (−30) zählte als Sprache. Mit den ersten 10 s (Pegel −14) ist er ein Atmer.
        val words = listOf(w("ich", 0.0, 0.6), w("weiß", 0.6, 1.0))
        val env = envelope(0.0, 0.21 to silence, 0.36 to -30f, 0.39 to silence, 0.6 to -26f, 6.0 to -14f)
        assertEquals(0.38, SpeechOnsetRefiner.refine(words, env)[0].start, 1e-9)
    }

    @Test
    fun runInsideTheTrackStaysAsBefore() {
        // Lauf ab Track-Sekunde 100 (Vorlauf mitten im Track): vor der Hüllkurve ist unbekannt — 0,12 s Stille
        // reichen nicht, Wort bleibt (wie `envelopeStartingMidPause`).
        val words = listOf(w("Er", 100.0, 100.6), w("bestellte", 100.6, 101.0))
        assertEquals(words, SpeechOnsetRefiner.refine(words, envelope(100.0, 100.12 to silence, 103.0 to speech)))
        // Mit Vorwort (Batch-Grenze) gilt die Regel auch am Track-Anfang nicht.
        val first = listOf(w("Er", 0.0, 0.6))
        val env = envelope(0.0, 0.12 to silence, 3.0 to speech)
        assertEquals(first, SpeechOnsetRefiner.refine(first, env, previous = w("davor", 0.0, 0.0001)))
    }

    @Test
    fun batchBoundaryGivesTheSameResultAsOneList() {
        val env = envelope(
            0.0, 1.0 to silence, 2.0 to speech, 2.6 to silence, 3.4 to speech, 3.9 to silence, 5.0 to speech,
        )
        val words = listOf(
            w("a", 0.8, 1.5), w("b", 1.5, 2.3), w("c", 2.3, 3.0), w("d", 3.0, 3.6), w("e", 3.6, 4.4), w("f", 4.4, 5.0),
        )
        val whole = SpeechOnsetRefiner.refine(words, env)
        val first = SpeechOnsetRefiner.refine(words.subList(0, 3), env)
        val second = SpeechOnsetRefiner.refine(words.subList(3, 6), env, previous = first.last())
        assertEquals(whole.map { it.start }, (first + second).map { it.start })
        assertEquals(listOf(0.99, 1.5, 2.59, 3.0, 3.89, 4.4), whole.map { Math.round(it.start * 100) / 100.0 })
    }

    @Test
    fun startsStayMonotonic() {
        // Überlappende Erkennerzeiten und viele Pausen: Anfänge nie rückwärts.
        val parts = ArrayList<Pair<Double, Float>>()
        var t = 0.0
        var on = false
        while (t < 30.0) {
            t += if (on) 0.4 + (t * 7 % 1.0) else 0.25 + (t * 3 % 0.5)
            parts.add(t to if (on) speech else silence)
            on = !on
        }
        val env = envelope(0.0, *parts.toTypedArray())
        val words = (0 until 70).map { i -> w("w$i", i * 0.4, i * 0.4 + 0.55) }
        val out = SpeechOnsetRefiner.refine(words, env)
        for (i in 1 until out.size) assertTrue("Wort $i", out[i].start >= out[i - 1].start)
        for (i in out.indices) assertTrue(out[i].start <= out[i].end - SpeechOnsetRefiner.MINIMUM_WORD_SECONDS + 1e-9 || out[i] == words[i])
    }

    @Test
    fun percentileUsesWholeDecibelClasses() {
        val levels = FloatArray(100) { if (it < 90) -70.4f else -20.6f }
        assertEquals(-21, SpeechOnsetRefiner.percentileLevel(levels, 0, 100))
        assertEquals(-71, SpeechOnsetRefiner.percentileLevel(levels, 0, 90))
        assertEquals(null, SpeechOnsetRefiner.percentileLevel(levels, 5, 5))
    }

    @Test
    fun trackerBuildsEnvelopeFromPcmAndReleasesOldFrames() {
        val rate = 16_000
        // 2 s Ton, 0,6 s Stille, 2 s Ton; Ursprung bei Track-Sekunde 100.
        fun tone(seconds: Double) = ShortArray((seconds * rate).toInt()) { (8000 * sin(2 * PI * 220 * it / rate)).toInt().toShort() }
        val pcm = tone(2.0) + ShortArray((0.6 * rate).toInt()) + tone(2.0)
        val tracker = SpeechEnvelopeTracker()
        tracker.setOrigin(100.0)
        // In ungeraden Blöcken anhängen (Fenster über Blockgrenzen).
        var offset = 0
        while (offset < pcm.size) {
            val n = minOf(3001, pcm.size - offset)
            tracker.append(pcm.copyOfRange(offset, offset + n), n, rate)
            offset += n
        }
        val out = tracker.refine(listOf(w("eins", 101.0, 102.3), w("zwei", 102.3, 103.0)), previous = null)
        assertEquals(102.59, out[1].start, 1e-6)
        assertEquals(102.0, out[0].end, 1e-6)
        assertEquals(-140f, SpeechEnvelopeTracker.level(0.0, 160), 0f)
    }

    @Test
    fun displayHeuristicOnlyForLegacyTranscripts() {
        val segment = PlayerTranscriptTrackCache.Segment(0.0, 10.0, listOf(PlayerTranscriptTrackCache.Word("Gestern", 2.1, 3.78)))
        val refined = PlayerTranscriptTrackCache(localeIdentifier = "de-DE", trackIndex = 0, segments = listOf(segment))
        val legacy = refined.copy(version = 2)
        assertEquals(2.1, PlayerTranscriptTimeline.recognizedWords(refined, 0, 0.0).single().globalStart, 0.0)
        assertEquals(3.78 - ReadAlongWordTiming.maxDuration(7), PlayerTranscriptTimeline.recognizedWords(legacy, 0, 0.0).single().globalStart, 1e-9)
    }

    /**
     * Gleichheit mit der iOS-Funktion an echten Hörbuch-Tracks: Hüllkurve und von Swift korrigierte Wörter,
     * exportiert vom Mess-Harness (`harness --refine`). Läuft nur mit `ABSTAND_ONSET_PARITY_DIR` — die Daten
     * stammen aus einem urheberrechtlich geschützten Hörbuch und liegen deshalb nicht im Repo.
     */
    @Test
    fun matchesSwiftOnExportedRealTracks() {
        val dir = System.getenv("ABSTAND_ONSET_PARITY_DIR")?.let(::File) ?: return
        val files = dir.listFiles { f -> f.name.endsWith(".parity.json") }.orEmpty().sortedBy { it.name }
        assertTrue("keine *.parity.json in $dir", files.isNotEmpty())
        var words = 0
        var changed = 0
        var maxDiff = 0.0
        for (file in files) {
            val root = Json.parseToJsonElement(file.readText()).jsonObject
            val levels = root["levels"]!!.jsonArray.map { it.jsonPrimitive.float }.toFloatArray()
            fun list(key: String) = root[key]!!.jsonArray.map {
                val o = it.jsonObject
                SpeechOnsetWord(o["t"]!!.jsonPrimitive.content, o["s"]!!.jsonPrimitive.double, o["e"]!!.jsonPrimitive.double)
            }
            val input = list("input")
            val swift = list("swift")
            val kotlin = SpeechOnsetRefiner.refine(input, SpeechEnvelope(0.0, levels))
            assertEquals(swift.size, kotlin.size)
            for (i in kotlin.indices) {
                maxDiff = maxOf(maxDiff, abs(kotlin[i].start - swift[i].start), abs(kotlin[i].end - swift[i].end))
                if (kotlin[i] != input[i]) changed += 1
            }
            words += kotlin.size
        }
        println("Parität Kotlin↔Swift: ${files.size} Tracks, $words Wörter, $changed verändert, max |Δ| = $maxDiff s")
        assertEquals(0.0, maxDiff, 1e-9)
    }
}
