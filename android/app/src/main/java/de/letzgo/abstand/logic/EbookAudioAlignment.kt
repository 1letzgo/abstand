package de.letzgo.abstand.logic

import java.nio.ByteBuffer
import java.nio.ByteOrder

// iOS: EbookAudioAlignment.swift — Abgleich Hörbuch ↔ eBook, genau eine Quelle der Wahrheit für
// „welches eBook-Wort wird wann gesprochen".
//
// Je Track wird das Transkript (Erkennung, mit Zeiten) global-monoton gegen das eBook ausgerichtet:
// eindeutige Trigramme und seltene lange Wörter als Fixpunkte (längste aufsteigende Teilfolge), Lücken rekursiv über eindeutige
// Wörter und zuletzt per LCS. Ergebnis wird je Track als `a<track>-<locale>.bin` gespeichert —
// Byte-Format identisch zu iOS (Little Endian wie `withUnsafeBytes` auf arm64).

/** iOS: `AlignmentInputWord` — ein erkanntes Wort mit Zeit in lokalen Track-Sekunden. */
data class AlignmentInputWord(val text: String, val start: Double, val end: Double)

/**
 * iOS: `EbookTrackAlignment` — ausgerichtete eBook-Wörter eines Tracks, streng aufsteigend nach
 * eBook-Position und Zeit. Nicht ausgerichtete Wörter fehlen.
 */
class EbookTrackAlignment(
    val ebookWordCount: Int,
    val spokenWordCount: Int,
    /** Ende des letzten erkannten Worts (lokale Sekunden). */
    val spokenEnd: Double,
    val words: IntArray,
    /** Lokale Track-Sekunden. */
    val starts: FloatArray,
    val ends: FloatArray,
    /** 1 = direkt erkannt, 0 = zwischen erkannten Nachbarn verteilt. */
    val flags: ByteArray,
) {
    val isEmpty: Boolean get() = words.isEmpty()

    /**
     * eBook-Wort zur Track-Zeit. In einer Pause bleibt das letzte Wort stehen, nach längerer Lücke
     * gibt es keine Antwort.
     */
    fun ebookWord(atLocalTime: Double, maxGap: Double = 3.0): Int? {
        if (words.isEmpty()) return null
        var low = 0
        var high = words.size
        while (low < high) {
            val mid = (low + high) / 2
            if (starts[mid].toDouble() <= atLocalTime) low = mid + 1 else high = mid
        }
        if (low <= 0) return null
        val i = low - 1
        if (atLocalTime > ends[i].toDouble() + maxGap) return null
        return words[i]
    }

    /**
     * iOS: `lastEbookWord(atOrBeforeLocalTime:)` — zuletzt gesprochenes eBook-Wort bis zur Track-Zeit,
     * auch über lange Pausen hinweg. `null` vor dem ersten ausgerichteten Wort.
     */
    fun lastEbookWord(atOrBeforeLocalTime: Double): Int? {
        if (words.isEmpty()) return null
        var low = 0
        var high = words.size
        while (low < high) {
            val mid = (low + high) / 2
            if (starts[mid].toDouble() <= atOrBeforeLocalTime) low = mid + 1 else high = mid
        }
        return if (low > 0) words[low - 1] else null
    }

    /** iOS: `ebookWordRange` — erstes und letztes ausgerichtetes eBook-Wort. */
    val ebookWordRange: IntRange? get() = if (words.isEmpty()) null else words.first()..words.last()

    /**
     * iOS: `localTime(forEbookWord:)` — Track-Zeit, ab der das eBook-Wort gesprochen wird; ein nicht
     * ausgerichtetes Wort nimmt das nächste ausgerichtete danach. `null` außerhalb von [ebookWordRange].
     */
    fun localTime(forEbookWord: Int): Double? {
        val range = ebookWordRange ?: return null
        if (forEbookWord !in range) return null
        var low = 0
        var high = words.size
        while (low < high) {
            val mid = (low + high) / 2
            if (words[mid] < forEbookWord) low = mid + 1 else high = mid
        }
        return starts.getOrNull(low)?.toDouble()
    }

    /** iOS: `encoded()` — Magic, Version, Zähler, `spokenEnd`, dann die vier Arrays (Little Endian). */
    fun encoded(): ByteArray {
        val n = words.size
        val buffer = ByteBuffer.allocate(4 * 5 + 8 + n * (4 + 4 + 4 + 1)).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(MAGIC)
        buffer.putInt(FORMAT_VERSION)
        buffer.putInt(ebookWordCount)
        buffer.putInt(spokenWordCount)
        buffer.putDouble(spokenEnd)
        buffer.putInt(n)
        for (w in words) buffer.putInt(w)
        for (s in starts) buffer.putFloat(s)
        for (e in ends) buffer.putFloat(e)
        buffer.put(flags)
        return buffer.array()
    }

    /** iOS: `EbookDisplayWords` aus `displayWords(index:globalOffset:)`. */
    fun displayWords(index: EbookReadAlongIndex, globalOffset: Double): EbookDisplayWords {
        val out = ArrayList<PlayerTranscriptWord>(words.size)
        val spans = ArrayList<EbookDisplayWords.Span>()
        var previousPosition = -2
        for (i in words.indices) {
            val position = words[i]
            if (position < 0 || position >= index.words.size) continue
            val start = globalOffset + starts[i].toDouble()
            val end = globalOffset + ends[i].toDouble()
            out.add(PlayerTranscriptWord("e-$position", index.words[position].display, start, end))
            if (position == previousPosition + 1 && spans.isNotEmpty()) {
                spans[spans.size - 1] = spans.last().copy(end = end)
            } else {
                spans.add(EbookDisplayWords.Span(start, end))
            }
            previousPosition = position
        }
        return EbookDisplayWords(out, spans)
    }

    companion object {
        /**
         * 2: Tokenzeiten nach Zeichenzahl, Lückenfüllung mit Pausen (alte Dateien werden neu berechnet).
         * 3: seltene Wörter als zusätzliche Fixpunkte.
         */
        const val FORMAT_VERSION: Int = 3
        /** `0x4142_4C31` („ABL1"). */
        const val MAGIC: Int = 0x41424C31

        fun empty(ebookWordCount: Int, spokenWordCount: Int, spokenEnd: Double) = EbookTrackAlignment(
            ebookWordCount, spokenWordCount, spokenEnd, IntArray(0), FloatArray(0), FloatArray(0), ByteArray(0),
        )

        /** iOS: `init?(data:)` — `null` bei falscher Magic/Version oder zu kurzen Daten. */
        fun decode(data: ByteArray): EbookTrackAlignment? {
            val b = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
            if (b.remaining() < 4 * 5 + 8) return null
            if (b.int != MAGIC) return null
            if (b.int != FORMAT_VERSION) return null
            val ebookCount = b.int
            val spokenCount = b.int
            val spokenEnd = b.double
            val count = b.int
            if (count < 0) return null
            if (b.remaining().toLong() < count.toLong() * 13) return null
            val words = IntArray(count) { b.int }
            val starts = FloatArray(count) { b.float }
            val ends = FloatArray(count) { b.float }
            val flags = ByteArray(count).also { b.get(it) }
            return EbookTrackAlignment(ebookCount, spokenCount, spokenEnd, words, starts, ends, flags)
        }
    }
}

/**
 * iOS: `EbookDisplayWords` — eBook-Wörter eines Tracks in globaler Zeit plus die Zeitspannen, in
 * denen der eBook-Text lückenlos steht.
 */
data class EbookDisplayWords(val words: List<PlayerTranscriptWord>, val spans: List<Span>) {
    data class Span(val start: Double, val end: Double)
}

/** iOS: `EbookAlignmentBuilder`. */
object EbookAlignmentBuilder {
    /** Mindestanzahl erkannter Wörter und Anteil am Transkript. */
    private const val MINIMUM_MATCHES = 12
    private const val MINIMUM_MATCH_RATIO = 0.2
    /**
     * Lückenfüllung: Höchstdauer eines nicht erkannten Worts mittlerer Länge (Gewicht
     * [REFERENCE_WORD_WEIGHT] = 5 Zeichen + 2); längere Wörter dürfen anteilig länger dauern.
     */
    private const val MAX_FILLED_WORD_SECONDS = 0.5
    private const val REFERENCE_WORD_WEIGHT = 7.0
    /** Kürzere Reste gelten nicht als Pause (Rundung), die Wörter füllen die Lücke dann ganz. */
    private const val MINIMUM_FILLED_PAUSE_SECONDS = 0.05
    /** Seltene Wörter als Fixpunkt erst ab dieser Länge — kurze Wörter sind zu oft Erkennungs-Zufall. */
    private const val RARE_WORD_MINIMUM_LENGTH = 7

    /**
     * iOS: `pauseSlot(afterWord:gap:index:)` — Index des ersten Lückenworts nach der Pause (`gap` =
     * direkt vor dem nächsten erkannten Wort). Bevorzugt die letzte Satzgrenze in der Lücke.
     */
    fun pauseSlot(previousE: Int, gap: Int, index: EbookReadAlongIndex): Int {
        var slot = gap
        while (slot >= 0) {
            val before = previousE + slot
            if (index.words[before].sentence != index.words[before + 1].sentence) return slot
            slot -= 1
        }
        return gap
    }

    private data class Anchor(val e: Int, val s: Int, val length: Int)

    fun build(input: List<AlignmentInputWord>, index: EbookReadAlongIndex): EbookTrackAlignment {
        val spokenEnd = input.lastOrNull()?.end ?: 0.0
        val empty = EbookTrackAlignment.empty(index.words.size, input.size, spokenEnd)
        if (index.isEmpty || input.size < 8) return empty

        // Erkannte Wörter in eBook-Tokens zerlegen („don't" → „don", „t"), Zeit nach Zeichenzahl verteilen
        // (ein langes Wort dauert länger als ein kurzes — gleichmäßig verteilt liefe die Markierung voraus).
        val sNorm = ArrayList<String>(input.size)
        val sStartList = ArrayList<Double>(input.size)
        val sEndList = ArrayList<Double>(input.size)
        for (word in input) {
            val tokens = ReadAlongText.words(word.text)
            if (tokens.isEmpty()) continue
            val duration = maxOf(0.0, word.end - word.start)
            val weights = DoubleArray(tokens.size) { maxOf(1, FoundationText.characterCount(tokens[it].word)).toDouble() }
            // Swift `reduce(0, +)`: linksassoziativ von 0 an.
            var total = 0.0
            for (w in weights) total += w
            var cumulative = 0.0
            for ((offset, token) in tokens.withIndex()) {
                sNorm.add(token.word)
                sStartList.add(word.start + duration * cumulative / total)
                cumulative += weights[offset]
                sEndList.add(word.start + duration * cumulative / total)
            }
        }
        val n = sNorm.size
        if (n < 8) return empty
        val sStart = sStartList.toDoubleArray()
        val sEnd = sEndList.toDoubleArray()
        val sIds = IntArray(n) { index.vocabulary[sNorm[it]] ?: -1 }

        // 1. Fixpunkte: Trigramme, die im eBook und im Transkript genau einmal vorkommen.
        val keys = arrayOfNulls<String>(n - 2)
        val firstPosition = HashMap<String, Int>()
        for (i in 0 until n - 2) {
            val key = ReadAlongText.trigramKey(sNorm[i], sNorm[i + 1], sNorm[i + 2])
            keys[i] = key
            firstPosition[key] = if (firstPosition[key] == null) i else -1
        }
        var anchors = ArrayList<Anchor>()
        for (i in 0 until n - 2) {
            val key = keys[i]!!
            if (firstPosition[key] != i) continue
            val positions = index.trigrams[key] ?: continue
            if (positions.size != 1) continue
            val e = positions[0]
            if (!(e + 2 < index.ids.size)) continue
            if (!(sIds[i] >= 0 && sIds[i] == index.ids[e] && sIds[i + 1] == index.ids[e + 1] && sIds[i + 2] == index.ids[e + 2])) continue
            anchors.add(Anchor(e, i, 3))
        }

        // 1b. Seltene lange Wörter, die im eBook und im Transkript genau einmal vorkommen. Ein einzelner
        // Erkennungsfehler zerstört drei Trigramme, ein seltenes Wort („Thornfield") bleibt oft erhalten.
        val spokenCount = HashMap<Int, Int>()
        for (id in sIds) if (id >= 0) spokenCount[id] = (spokenCount[id] ?: 0) + 1
        val trigramStarts = anchors.mapTo(HashSet()) { it.s }
        val rare = ArrayList<Anchor>()
        for (s in 0 until n) {
            val id = sIds[s]
            if (id < 0 || FoundationText.characterCount(sNorm[s]) < RARE_WORD_MINIMUM_LENGTH || spokenCount[id] != 1) continue
            val e = index.uniquePosition(id) ?: continue
            // Schon von einem Trigramm-Fixpunkt abgedeckt?
            if (s in trigramStarts || (s - 1) in trigramStarts || (s - 2) in trigramStarts) continue
            rare.add(Anchor(e, s, 1))
        }
        if (rare.isNotEmpty()) anchors = ArrayList((anchors + rare).sortedBy { it.s })
        if (anchors.isEmpty()) return empty

        // 2. Globale Ordnung: längste aufsteigende Teilfolge — Zufallstreffer fallen heraus.
        val chain = longestIncreasingSubsequence(IntArray(anchors.size) { anchors[it].e }).map { anchors[it] }

        // 3. Kleine Inseln (unplausibles Tempo, weniger als drei Anker) verwerfen.
        val clusters = ArrayList<ArrayList<Anchor>>()
        for (anchor in chain) {
            val last = clusters.lastOrNull()?.lastOrNull()
            if (last != null) {
                val de = anchor.e - last.e
                val ds = anchor.s - last.s
                val ratio = de.toDouble() / maxOf(ds, 1).toDouble()
                if (de >= 1 && ds >= 1 && ((de <= 12 && ds <= 12) || (ratio >= 0.25 && ratio <= 4.0))) {
                    clusters.last().add(anchor)
                    continue
                }
            }
            clusters.add(arrayListOf(anchor))
        }
        val kept = clusters.filter { it.size >= 3 }.flatten()
        val first = kept.firstOrNull() ?: return empty

        // 4. Lücken zwischen den Fixpunkten füllen.
        val aligner = GapAligner(index, sIds, sNorm)
        aligner.fill(maxOf(0, first.e - (first.s * 2 + 12)), first.e, 0, first.s, 0)
        for ((i, anchor) in kept.withIndex()) {
            for (k in 0 until anchor.length) aligner.add(anchor.e + k, anchor.s + k)
            if (aligner.matchE.isEmpty()) continue
            val lastE = aligner.matchE.last()
            val lastS = aligner.matchS.last()
            if (i + 1 < kept.size) {
                aligner.fill(lastE + 1, kept[i + 1].e, lastS + 1, kept[i + 1].s, 0)
            }
        }
        if (aligner.matchE.isNotEmpty()) {
            val tailEbook = aligner.matchE.last() + 1
            val tailSpoken = aligner.matchS.last() + 1
            aligner.fill(tailEbook, minOf(index.words.size, tailEbook + (n - tailSpoken) * 2 + 12), tailSpoken, n, 0)
        }

        val matchCount = aligner.matchE.size
        if (matchCount < MINIMUM_MATCHES || matchCount.toDouble() < MINIMUM_MATCH_RATIO * n.toDouble()) return empty

        // 5. Zeiten: erkannte Wörter übernehmen ihre Zeit, Wörter dazwischen werden nach Länge verteilt.
        val outWords = ArrayList<Int>(matchCount)
        val outStarts = ArrayList<Float>(matchCount)
        val outEnds = ArrayList<Float>(matchCount)
        val outFlags = ArrayList<Byte>(matchCount)
        var lastEnd = 0.0
        for (m in 0 until matchCount) {
            val e = aligner.matchE[m]
            val s = aligner.matchS[m]
            if (m > 0) {
                val previousE = aligner.matchE[m - 1]
                val gap = e - previousE - 1
                if (gap > 0) {
                    val from = lastEnd
                    val to = maxOf(sStart[s], from)
                    val span = to - from
                    val plausible = if (gap <= 3) {
                        span <= 15
                    } else {
                        val rate = gap.toDouble() / maxOf(span, 0.001)
                        span <= 120 && rate >= 0.3 && rate <= 9
                    }
                    if (plausible) {
                        val weights = DoubleArray(e - previousE - 1) {
                            (maxOf(1, FoundationText.characterCount(index.words[previousE + 1 + it].normalized)) + 2).toDouble()
                        }
                        // Swift `reduce(0, +)`: linksassoziativ von 0 an.
                        var total = 0.0
                        for (w in weights) total += w
                        // Je Wort höchstens so lange wie gesprochen plausibel; der Rest ist eine Pause
                        // (Atempause, Satzende) und wird nicht über die Wörter verschmiert.
                        val lengths = DoubleArray(weights.size) {
                            val weight = weights[it]
                            minOf(span * weight / total, MAX_FILLED_WORD_SECONDS * maxOf(1.0, weight / REFERENCE_WORD_WEIGHT))
                        }
                        var used = 0.0
                        for (l in lengths) used += l
                        var pause = span - used
                        if (pause < MINIMUM_FILLED_PAUSE_SECONDS) pause = 0.0
                        val pauseBefore = if (pause > 0) pauseSlot(previousE, weights.size, index) else weights.size
                        var cursor = from
                        for ((offset, length) in lengths.withIndex()) {
                            if (offset == pauseBefore) cursor += pause
                            outWords.add(previousE + 1 + offset)
                            outStarts.add(cursor.toFloat())
                            outEnds.add((cursor + length).toFloat())
                            outFlags.add(0)
                            cursor += length
                        }
                        if (pauseBefore == weights.size) cursor += pause
                        lastEnd = cursor
                    }
                }
            }
            val start = maxOf(sStart[s], lastEnd)
            val end = maxOf(sEnd[s], start + 0.02)
            outWords.add(e)
            outStarts.add(start.toFloat())
            outEnds.add(end.toFloat())
            outFlags.add(1)
            lastEnd = end
        }
        return EbookTrackAlignment(
            index.words.size, input.size, spokenEnd,
            outWords.toIntArray(), outStarts.toFloatArray(), outEnds.toFloatArray(), outFlags.toByteArray(),
        )
    }

    /** Indizes einer längsten streng aufsteigenden Teilfolge (O(n log n)), identisch zu iOS. */
    fun longestIncreasingSubsequence(values: IntArray): List<Int> {
        val tails = ArrayList<Int>()
        val previous = IntArray(values.size) { -1 }
        for (i in values.indices) {
            var low = 0
            var high = tails.size
            while (low < high) {
                val mid = (low + high) / 2
                if (values[tails[mid]] < values[i]) low = mid + 1 else high = mid
            }
            if (low > 0) previous[i] = tails[low - 1]
            if (low == tails.size) tails.add(i) else tails[low] = i
        }
        val result = ArrayList<Int>()
        var k = tails.lastOrNull() ?: -1
        while (k >= 0) {
            result.add(k)
            k = previous[k]
        }
        result.reverse()
        return result
    }
}

/**
 * iOS: `GapAligner` — füllt den Bereich zwischen zwei Fixpunkten: kleine Lücken per LCS, große
 * rekursiv über Wörter, die in beiden Bereichen genau einmal vorkommen („patience diff").
 */
private class GapAligner(
    private val index: EbookReadAlongIndex,
    private val sIds: IntArray,
    private val sNorm: List<String>,
) {
    val matchE = ArrayList<Int>()
    val matchS = ArrayList<Int>()

    fun add(e: Int, s: Int) {
        if (e < 0 || e >= index.words.size || s < 0 || s >= sIds.size) return
        if (matchE.isNotEmpty() && (e <= matchE.last() || s <= matchS.last())) return
        matchE.add(e)
        matchS.add(s)
    }

    /** Gleich oder (ab 4 Characters) gemeinsamer Wortanfang — die Erkennung trifft Endungen oft nicht. */
    private fun wordsMatch(e: Int, s: Int): Boolean {
        if (sIds[s] >= 0 && sIds[s] == index.ids[e]) return true
        val a = index.words[e].normalized
        val b = sNorm[s]
        if (FoundationText.characterCount(a) < 4 || FoundationText.characterCount(b) < 4) return false
        return a.startsWith(b) || b.startsWith(a)
    }

    fun fill(eLo: Int, eHi: Int, sLo: Int, sHi: Int, depth: Int) {
        val n = eHi - eLo
        val m = sHi - sLo
        if (n <= 0 || m <= 0) return
        // Völlig unterschiedlich lange Bereiche gehören nicht zusammen.
        if (!(n <= 8 * m + 24 && m <= 8 * n + 24)) return
        if (n.toLong() * m <= LCS_CELL_LIMIT) {
            lcs(eLo, n, sLo, m)
            return
        }
        if (depth >= MAX_DEPTH) return

        val ebookCount = HashMap<Int, Int>()
        val ebookPosition = HashMap<Int, Int>()
        for (e in eLo until eHi) {
            val id = index.ids[e]
            ebookCount[id] = (ebookCount[id] ?: 0) + 1
            ebookPosition[id] = e
        }
        val spokenCount = HashMap<Int, Int>()
        for (s in sLo until sHi) if (sIds[s] >= 0) spokenCount[sIds[s]] = (spokenCount[sIds[s]] ?: 0) + 1
        val pairE = ArrayList<Int>()
        val pairS = ArrayList<Int>()
        for (s in sLo until sHi) {
            val id = sIds[s]
            if (id < 0 || spokenCount[id] != 1 || ebookCount[id] != 1) continue
            val e = ebookPosition[id] ?: continue
            pairE.add(e)
            pairS.add(s)
        }
        if (pairE.isEmpty()) return

        var previousE = eLo
        var previousS = sLo
        for (i in EbookAlignmentBuilder.longestIncreasingSubsequence(pairE.toIntArray())) {
            fill(previousE, pairE[i], previousS, pairS[i], depth + 1)
            add(pairE[i], pairS[i])
            previousE = pairE[i] + 1
            previousS = pairS[i] + 1
        }
        fill(previousE, eHi, previousS, sHi, depth + 1)
    }

    private fun lcs(eLo: Int, n: Int, sLo: Int, m: Int) {
        val width = m + 1
        // iOS: UInt16-Tabelle; Längen ≤ min(n, m) ≤ 500 passen auch in Short.
        val table = ShortArray((n + 1) * width)
        for (i in n - 1 downTo 0) {
            for (j in m - 1 downTo 0) {
                table[i * width + j] = if (wordsMatch(eLo + i, sLo + j)) {
                    (table[(i + 1) * width + j + 1] + 1).toShort()
                } else {
                    maxOf(table[(i + 1) * width + j], table[i * width + j + 1])
                }
            }
        }
        var i = 0
        var j = 0
        while (i < n && j < m) {
            if (wordsMatch(eLo + i, sLo + j) && table[i * width + j] == (table[(i + 1) * width + j + 1] + 1).toShort()) {
                add(eLo + i, sLo + j)
                i += 1
                j += 1
            } else if (table[(i + 1) * width + j] >= table[i * width + j + 1]) {
                i += 1
            } else {
                j += 1
            }
        }
    }

    companion object {
        private const val LCS_CELL_LIMIT = 250_000
        private const val MAX_DEPTH = 12
    }
}
