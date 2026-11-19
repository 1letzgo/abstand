package de.letzgo.abstand.logic

import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Wort mit lokalen Track-Sekunden (iOS: `PlayerTranscriptProducedWord`) — Ein- und Ausgabe der Verfeinerung. */
data class SpeechOnsetWord(val text: String, val start: Double, val end: Double)

/** iOS: `SpeechEnvelope` — Pegel (dBFS) je 10-ms-Fenster ab [startTime] (lokale Track-Sekunden). */
class SpeechEnvelope(val startTime: Double, val levels: FloatArray)

/**
 * iOS: `SpeechOnsetRefiner` (SpeechOnsetRefinement.swift) — legt Wortanfänge nach Sprechpausen auf den
 * akustischen Einsatz. Der Erkenner setzt die Grenze zwischen zwei Wörtern irgendwo in die Pause; das
 * Wort danach begann dadurch zu früh. Konstanten und Ablauf 1:1 wie iOS (dort an einem echten
 * deutschen Hörbuch eingestellt); mit Vosk ist das Verfahren nicht vermessen.
 */
object SpeechOnsetRefiner {
    const val HOP_SECONDS = 0.01
    const val REFERENCE_WINDOW_SECONDS = 10.0
    const val REFERENCE_PERCENTILE = 0.95
    const val SILENCE_BELOW_REFERENCE_DB = 28.0
    const val MINIMUM_REFERENCE_DB = -60.0
    const val MINIMUM_SILENCE_SECONDS = 0.2
    const val STABILITY_FRAMES = 15
    const val STABILITY_MINIMUM_ABOVE_FRAMES = 9
    /** iOS: `breathBelowReferenceDB` … — Einatmen vor dem Sprechen: schwacher Einsatz mit Einbruch vor der Sprache. */
    const val BREATH_BELOW_REFERENCE_DB = 12.0
    const val BREATH_WINDOW_FRAMES = 60
    const val BREATH_MINIMUM_FRAMES = 10
    const val LEAD_SECONDS = 0.01
    const val MAXIMUM_EARLIER_SHIFT_SECONDS = 0.3
    const val SILENCE_START_TOLERANCE_SECONDS = 0.15
    const val MINIMUM_WORD_SECONDS = 0.08
    /**
     * iOS: `lateOnsetSeconds` — Wort (fast) ganz in der Pause (englischer Erkenner: he, as, said, The …):
     * Suche bis so weit hinter das rohe Wortende; ein Einsatz dort verschiebt das ganze Wort.
     */
    const val LATE_ONSET_SECONDS = 0.3
    /** iOS: `shiftedWordSecondsPerCharacter` — Mindestlänge eines verschobenen Worts je Buchstabe. */
    const val SHIFTED_WORD_SECONDS_PER_CHARACTER = 0.06
    /**
     * iOS: `shiftedSilenceStartToleranceSeconds` — verschoben wird nur, wenn die Stille spätestens so kurz
     * nach dem rohen Anfang beginnt (sonst ist das Wort gesprochen und der Einsatz gehört zum Folgewort).
     */
    const val SHIFTED_SILENCE_START_TOLERANCE_SECONDS = 0.03
    /**
     * iOS: `previousEndSlackSeconds` — nicht vor das Ende des Vorworts (minus diesen Rest) zurück. Ausnahme
     * „Pause im Vorwort“: Beginnt die Stille vor dem Einsatz mindestens [MINIMUM_WORD_SECONDS] nach dem Anfang
     * des Vorworts (der Erkenner hat die Pause ins Vorwort gelegt), fällt die Sperre; das Vorwort endet am
     * Beginn der Stille. Messung siehe iOS.
     */
    const val PREVIOUS_END_SLACK_SECONDS = 0.05
    const val SCAN_BACK_SECONDS = 1.0
    /** iOS: `trackStartToleranceSeconds` — Hüllkurve beginnt höchstens so spät: Lauf ab Track-Anfang. */
    const val TRACK_START_TOLERANCE_SECONDS = 0.05
    const val HISTOGRAM_FLOOR_DB = -100

    private class Onset(val time: Double, val silenceStart: Double, val isLate: Boolean)

    private class Previous(val start: Double, val end: Double, val index: Int?)

    /**
     * iOS: `refine(_:envelope:previous:)` — Wörter (zeitlich sortiert) mit korrigierten Anfängen. Vor einem
     * Wort mit erkennbarer Stille beginnt es am Einsatz danach (minus [LEAD_SECONDS]), höchstens bis
     * `Ende − MINIMUM_WORD_SECONDS` und nie vor dem Folgewort; das Vorwort endet dann am Beginn der Stille.
     * Liegt der Einsatz erst dahinter (bis [LATE_ONSET_SECONDS] nach dem rohen Ende) und beginnt die Stille
     * spätestens kurz nach dem rohen Anfang ([SHIFTED_SILENCE_START_TOLERANCE_SECONDS]), wandert das ganze Wort an den Einsatz — höchstens bis
     * [MINIMUM_WORD_SECONDS] vor das nächste gesprochene Wort (dessen Anfang bleibt); das Ende wächst bei
     * Bedarf auf eine Mindestlänge, nie über das Folgewort; Satzzeichen-Token dazwischen werden mitgeführt.
     * Wörter ohne Stille, reine Satzzeichen und Wörter außerhalb der Hüllkurve bleiben unverändert; die
     * Anfänge bleiben monoton. [previous]: letztes Wort vor der Liste (Batch-Grenze), Anfang schon korrigiert.
     * Das erste Wort eines Laufs ab Track-Anfang (kein [previous], Hüllkurve ab 0) zählt die Stille ab
     * Track-Beginn in jeder Länge (siehe [onset]).
     */
    fun refine(words: List<SpeechOnsetWord>, envelope: SpeechEnvelope, previous: SpeechOnsetWord? = null): List<SpeechOnsetWord> {
        if (words.isEmpty() || envelope.levels.isEmpty()) return words
        val levels = envelope.levels
        val t0 = envelope.startTime
        val need = Math.round(MINIMUM_SILENCE_SECONDS / HOP_SECONDS).toInt()
        val starts = DoubleArray(words.size) { words[it].start }
        val ends = DoubleArray(words.size) { words[it].end }
        var previousSpoken: Previous? = previous?.let { Previous(it.start, it.end, null) }

        for (i in words.indices) {
            val s = words[i].start
            val e = words[i].end
            val spoken = isSpoken(words[i].text)
            if (!spoken || !s.isFinite() || !e.isFinite() || !(e > s)) {
                if (spoken) previousSpoken = Previous(s, e, i)
                continue
            }
            var lower = s - MAXIMUM_EARLIER_SHIFT_SECONDS
            if (i > 0) lower = max(lower, starts[i - 1])
            // Untergrenze ohne die Sperre am Vorwort-Ende („Pause im Vorwort“, siehe PREVIOUS_END_SLACK_SECONDS).
            var unlockedLower: Double? = null
            previousSpoken?.let {
                lower = max(lower, it.start + MINIMUM_WORD_SECONDS)
                val locked = max(lower, min(s, it.end - PREVIOUS_END_SLACK_SECONDS))
                if (locked > lower) unlockedLower = lower
                lower = locked
            }
            var upper = e - MINIMUM_WORD_SECONDS
            if (i + 1 < words.size) upper = min(upper, words[i + 1].start)
            // Wort in der Pause: Anfang höchstens bis kurz vor das nächste gesprochene Wort.
            var next = i + 1
            while (next < words.size && !isSpoken(words[next].text)) next += 1
            val nextStart = if (next < words.size) words[next].start else Double.POSITIVE_INFINITY
            val shiftUpper = max(upper, nextStart - MINIMUM_WORD_SECONDS)

            if (lower <= shiftUpper) {
                val isTrackStart = previousSpoken == null && t0 <= TRACK_START_TOLERANCE_SECONDS
                var found = onset(levels, t0, need, s, e, lower, isTrackStart)
                // Pause im Vorwort: früherer Einsatz vor der Sperre, wenn das Vorwort vor der Stille klingt
                // (dieselbe Bedingung, unter der das Vorwort unten auf den Stille-Beginn gekürzt wird).
                val free = unlockedLower
                val prev = previousSpoken
                if (free != null && prev != null) {
                    val early = onset(levels, t0, need, s, e, free, false)
                    if (early != null && early.time < lower && !early.isLate &&
                        early.silenceStart >= prev.start + MINIMUM_WORD_SECONDS
                    ) {
                        found = early
                        lower = free
                    }
                }
                val onset = found?.takeIf {
                    if (it.isLate) it.silenceStart <= s + SHIFTED_SILENCE_START_TOLERANCE_SECONDS else lower <= upper
                }
                if (onset != null) {
                    val target = max(onset.time - LEAD_SECONDS, lower)
                    if (!onset.isLate || target <= upper) {
                        starts[i] = min(target, upper)
                    } else {
                        // Ganzes Wort an den Einsatz: Ende mindestens Anfang + Mindestlänge, nie über das Folgewort.
                        val start = min(target, shiftUpper)
                        starts[i] = start
                        if (start > upper) {
                            val length = max(MINIMUM_WORD_SECONDS, min(e - s, SHIFTED_WORD_SECONDS_PER_CHARACTER * letterCount(words[i].text)))
                            val end = max(e, min(start + length, nextStart))
                            ends[i] = end
                            // Satzzeichen-Token, die sonst vor dem Wort lägen, ans neue Ende mitnehmen.
                            for (j in i + 1 until next) {
                                if (starts[j] < end) {
                                    starts[j] = end
                                    ends[j] = max(ends[j], end)
                                }
                            }
                        }
                    }
                    val index = previousSpoken?.index
                    if (index != null && ends[index] > onset.silenceStart &&
                        onset.silenceStart >= starts[index] + MINIMUM_WORD_SECONDS
                    ) {
                        ends[index] = onset.silenceStart
                    }
                }
            }
            previousSpoken = Previous(starts[i], e, i)
        }
        return words.mapIndexed { i, w ->
            if (starts[i] == w.start && ends[i] == w.end) w else w.copy(start = starts[i], end = ends[i])
        }
    }

    private fun frame(time: Double, t0: Double): Int = floor((time - t0) / HOP_SECONDS).toInt()

    /**
     * iOS: `onset(...)` — erster stabiler Einsatz nach Stille, nicht vor [lower] und höchstens
     * [LATE_ONSET_SECONDS] nach [e], Stille begann bis kurz nach [s]. `isLate`: Einsatz erst hinter
     * `e − MINIMUM_WORD_SECONDS` (Wort ganz in der Pause).
     *
     * Track-Anfang ([isTrackStart]: kein Vorwort, Hüllkurve ab Track-Sekunde 0, Suche reicht bis an ihren
     * Anfang): vor dem Track liegt kein Schall, die Stille ab dem ersten Fenster zählt auch kürzer als
     * [MINIMUM_SILENCE_SECONDS] (Gerätefund iOS: erstes Wort klebte in 9 von 40 Tracks bei 0,00 s, Sprache
     * erst nach 0,08–0,45 s). Track beginnt sofort mit Sprache oder Lauf mitten im Track: wie bisher. Der
     * Sprachpegel nimmt dort statt der kurzen Vorgeschichte die ersten [REFERENCE_WINDOW_SECONDS] der Hüllkurve.
     */
    private fun onset(
        levels: FloatArray, t0: Double, need: Int, s: Double, e: Double, lower: Double, isTrackStart: Boolean,
    ): Onset? {
        val n = levels.size
        val windowFrames = Math.round(REFERENCE_WINDOW_SECONDS / HOP_SECONDS).toInt()
        val scanStart = frame(lower - SCAN_BACK_SECONDS, t0)
        val atEnvelopeStart = isTrackStart && scanStart <= 0
        var k1 = min(n, frame(e, t0) + 1)
        val k0 = max(0, frame(e - REFERENCE_WINDOW_SECONDS, t0))
        if (atEnvelopeStart) k1 = max(k1, min(n, k0 + windowFrames))
        if (k1 - k0 < 10) return null
        val reference = percentileLevel(levels, k0, k1) ?: return null
        if (reference.toDouble() < MINIMUM_REFERENCE_DB) return null
        val threshold = reference.toDouble() - SILENCE_BELOW_REFERENCE_DB
        // Bis hinter das rohe Ende: Wort (fast) ganz in der Pause (siehe LATE_ONSET_SECONDS).
        val last = min(n - 1, frame(e + LATE_ONSET_SECONDS, t0))
        // Atmer-Korrektur nur bis `Ende − MINIMUM_WORD_SECONDS` (dahinter war der „Atmer“ meist das leise Wort).
        val breathLast = min(n - 1, frame(e - MINIMUM_WORD_SECONDS, t0))
        var k = max(0, scanStart)
        // Fenster vor der Hüllkurve gelten als unbekannt (keine Stille) — Lauf beginnt bei 0. Ausnahme
        // Track-Anfang: eine Stille ab dem ersten Fenster (`k - run == 0`) reicht in jeder Länge.
        var run = 0
        while (k <= last) {
            if (!(levels[k].toDouble() > threshold)) {
                run += 1
            } else if (run < need && !(atEnvelopeStart && run > 0 && k - run == 0)) {
                run = 0
            } else {
                var above = 0
                for (j in k until min(n, k + STABILITY_FRAMES)) if (levels[j].toDouble() > threshold) above += 1
                if (above < STABILITY_MINIMUM_ABOVE_FRAMES) {
                    // Kurze Spitze in der Pause (Atmer, Klick): gehört zur Stille.
                    run += 1
                } else {
                    val time = t0 + k * HOP_SECONDS
                    val silenceStart = t0 + (k - run) * HOP_SECONDS
                    if (time >= lower && silenceStart <= s + SILENCE_START_TOLERANCE_SECONDS) {
                        return Onset(t0 + afterBreath(levels, k, breathLast, reference, threshold) * HOP_SECONDS, silenceStart, k > breathLast)
                    }
                    run = 0
                }
            }
            k += 1
        }
        return null
    }

    /** iOS: `afterBreath` — Einsatz eines Atmers → Fenster nach dessen letztem Einbruch (sonst [k]). */
    private fun afterBreath(levels: FloatArray, k: Int, last: Int, reference: Int, threshold: Double): Int {
        val speechLevel = reference.toDouble() - BREATH_BELOW_REFERENCE_DB
        var speech = -1
        for (j in k until min(levels.size, k + BREATH_WINDOW_FRAMES)) {
            if (levels[j].toDouble() >= speechLevel) { speech = j; break }
        }
        if (speech < 0 || speech - k < BREATH_MINIMUM_FRAMES) return k
        var dip = -1
        for (j in speech - 1 downTo k + 1) {
            if (!(levels[j].toDouble() > threshold)) { dip = j; break }
        }
        if (dip < 0 || dip + 1 > last) return k
        return dip + 1
    }

    /** iOS: `percentileLevel` — Perzentil über 1-dB-Klassen (Untergrenze der Klasse), ganzzahlig. */
    fun percentileLevel(levels: FloatArray, from: Int, to: Int): Int? {
        if (to <= from) return null
        val histogram = IntArray(-HISTOGRAM_FLOOR_DB + 1)
        for (k in from until to) {
            val bin = min(0, max(HISTOGRAM_FLOOR_DB, floor(levels[k].toDouble()).toInt())) - HISTOGRAM_FLOOR_DB
            histogram[bin] += 1
        }
        val target = Math.ceil(REFERENCE_PERCENTILE * (to - from)).toInt()
        var cumulative = 0
        for (bin in histogram.indices) {
            cumulative += histogram[bin]
            if (cumulative >= target) return bin + HISTOGRAM_FLOOR_DB
        }
        return 0
    }

    /** Buchstaben und Ziffern (iOS: `isLetter || isNumber` je Zeichen) — Mindestlänge verschobener Wörter. */
    private fun letterCount(text: String): Int {
        var count = 0
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            if (Character.isLetterOrDigit(cp)) count += 1
            i += Character.charCount(cp)
        }
        return count
    }

    /** iOS: `isSpoken` — mindestens ein Buchstabe oder eine Ziffer (keine reinen Satzzeichen-Token). */
    fun isSpoken(text: String): Boolean {
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            if (Character.isLetterOrDigit(cp)) return true
            i += Character.charCount(cp)
        }
        return false
    }
}

/**
 * iOS: `SpeechEnvelopeTracker` — Hüllkurve des gefütterten PCM während eines Producer-Laufs. Gehalten wird
 * nur, was noch gebraucht wird: ab ~12 s vor dem letzten korrigierten Wort, höchstens [MAXIMUM_FRAMES].
 */
class SpeechEnvelopeTracker {
    private var origin: Double? = null
    private var levels = FloatArray(1024)
    private var count = 0
    /** Index (ab Ursprung) von `levels[0]`. */
    private var firstFrame = 0
    private var samplesPerFrame = 0
    private var sumOfSquares = 0.0
    private var sampleCount = 0

    /** Track-Sekunde des ersten Samples. */
    @Synchronized
    fun setOrigin(time: Double) {
        origin = time
    }

    /** 16-Bit-PCM (mono) anhängen — vor dem Erkennen. */
    @Synchronized
    fun append(pcm: ShortArray, length: Int = pcm.size, sampleRate: Int) {
        if (length <= 0) return
        if (samplesPerFrame == 0) samplesPerFrame = max(1, Math.round(sampleRate * SpeechOnsetRefiner.HOP_SECONDS).toInt())
        for (i in 0 until length) {
            val v = pcm[i].toDouble() / 32768.0
            sumOfSquares += v * v
            sampleCount += 1
            if (sampleCount == samplesPerFrame) {
                push(level(sumOfSquares, sampleCount))
                sumOfSquares = 0.0
                sampleCount = 0
            }
        }
        if (count > MAXIMUM_FRAMES + TRIM_CHUNK_FRAMES) drop(count - MAXIMUM_FRAMES)
    }

    private fun push(value: Float) {
        if (count == levels.size) levels = levels.copyOf(levels.size * 2)
        levels[count++] = value
    }

    private fun drop(frames: Int) {
        val d = min(frames, count)
        if (d <= 0) return
        System.arraycopy(levels, d, levels, 0, count - d)
        count -= d
        firstFrame += d
    }

    /** Wörter eines Ergebnisses korrigieren und Hüllkurve davor freigeben. */
    @Synchronized
    fun refine(words: List<SpeechOnsetWord>, previous: SpeechOnsetWord?): List<SpeechOnsetWord> {
        if (words.isEmpty()) return words
        val o = origin ?: return words
        if (count == 0) return words
        val hop = SpeechOnsetRefiner.HOP_SECONDS
        val earliest = words.minOf { it.start }
        val latest = words.maxOf { it.end }
        val from = max(firstFrame, floor((earliest - LOOK_BACK_SECONDS - o) / hop).toInt())
        val to = min(firstFrame + count, Math.ceil((latest + LOOK_AHEAD_SECONDS - o) / hop).toInt())
        if (to <= from) return words
        val slice = levels.copyOfRange(from - firstFrame, to - firstFrame)
        val keepFrom = floor((words.last().start - LOOK_BACK_SECONDS - o) / hop).toInt()
        if (keepFrom > firstFrame) drop(keepFrom - firstFrame)
        return SpeechOnsetRefiner.refine(words, SpeechEnvelope(o + from * hop, slice), previous)
    }

    companion object {
        /** 10 min; gekürzt wird blockweise. */
        const val MAXIMUM_FRAMES = 60_000
        private const val TRIM_CHUNK_FRAMES = 6_000
        const val LOOK_BACK_SECONDS = 11.5
        const val LOOK_AHEAD_SECONDS = 0.5

        /** dBFS eines Fensters (Untergrenze −140 dB für digitale Stille). */
        fun level(sumOfSquares: Double, count: Int): Float =
            (20 * log10(max(sqrt(sumOfSquares / max(1, count)), 1e-7))).toFloat()
    }
}

/**
 * iOS: `PlayerTranscriptRefinementBatcher` — hält das letzte gesprochene Wort jedes Ergebnis-Batches (samt
 * folgender Satzzeichen-Token) zurück und verfeinert es mit dem nächsten Batch zusammen. [SpeechOnsetRefiner]
 * kürzt das Ende eines Worts auf den Beginn der Pause vor dem Folgewort — das geht nur, wenn beide in derselben
 * Liste stehen; über eine Batch-Grenze hinweg blieb das Ende sonst lang. Ergebnis wie mit einer einzigen Liste;
 * jedes Wort genau einmal, in Reihenfolge. [finish] gibt das Zurückgehaltene aus.
 */
class SpeechOnsetRefinementBatcher {
    /** Letztes ausgegebenes gesprochenes Wort: verfeinerter Anfang, erkanntes Ende (wie `refine` intern). */
    private var previous: SpeechOnsetWord? = null

    /** Zurückgehaltene Wörter, unverfeinert. */
    private var held: List<SpeechOnsetWord> = emptyList()

    /** Neuen Batch aufnehmen; liefert die fertigen Wörter (alles vor dem neuen letzten gesprochenen Wort). */
    fun add(words: List<SpeechOnsetWord>, refine: (List<SpeechOnsetWord>, SpeechOnsetWord?) -> List<SpeechOnsetWord>): List<SpeechOnsetWord> {
        if (words.isEmpty()) return emptyList()
        val batch = held + words
        val lastSpoken = batch.indexOfLast { SpeechOnsetRefiner.isSpoken(it.text) }
        if (lastSpoken < 0) {
            // Nur Satzzeichen: mit dem nächsten Batch zusammen ausgeben.
            held = batch
            return emptyList()
        }
        // Satzzeichen direkt davor mit zurückhalten — dann endet die Ausgabe auf einem gesprochenen Wort.
        var holdFrom = lastSpoken
        while (holdFrom > 0 && !SpeechOnsetRefiner.isSpoken(batch[holdFrom - 1].text)) holdFrom -= 1
        val refined = refine(batch, previous)
        held = batch.subList(holdFrom, batch.size).toList()
        val out = refined.subList(0, holdFrom).toList()
        rememberPrevious(out, batch)
        return out
    }

    /** Lauf zu Ende (oder abgebrochen): das Zurückgehaltene verfeinert ausgeben. */
    fun finish(refine: (List<SpeechOnsetWord>, SpeechOnsetWord?) -> List<SpeechOnsetWord>): List<SpeechOnsetWord> {
        if (held.isEmpty()) return emptyList()
        val batch = held
        held = emptyList()
        val out = refine(batch, previous)
        rememberPrevious(out, batch)
        return out
    }

    private fun rememberPrevious(out: List<SpeechOnsetWord>, raw: List<SpeechOnsetWord>) {
        val i = out.indexOfLast { SpeechOnsetRefiner.isSpoken(it.text) }
        if (i < 0) return
        previous = SpeechOnsetWord(out[i].text, out[i].start, raw[i].end)
    }
}
