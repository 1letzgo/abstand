package de.letzgo.abstand.logic

// iOS: EbookReadAlong.swift — eBook-Index (Sätze und Wörter in Lesereihenfolge) für Teleprompter und
// Abgleich, dazu die reine Logik des Buttons im Reader, der zur Seite der Hörposition springt und die
// letzten Wörter markiert. Readium-Typen bleiben draußen: Sätze tragen nur ihren Text-Kontext, den
// Locator baut der Reader aus Segment-Locator + [LocatorTextContext].

/** Ein Token eines Satzes: normalisiertes Wort und UTF-16-Bereich im Satztext. */
data class ReadAlongToken(val word: String, val start: Int, val end: Int)

/** iOS: `ReadAlongText` — vergleichbare Wortform für Transkript und eBook. */
object ReadAlongText {
    /** Klein, ohne Akzente, nur Buchstaben/Ziffern (`CharacterSet.alphanumerics`). */
    fun normalize(token: String): String {
        val folded = FoundationText.foldCaseAndDiacritics(token)
        val sb = StringBuilder(folded.length)
        var i = 0
        while (i < folded.length) {
            val cp = folded.codePointAt(i)
            if (FoundationText.isAlphanumeric(cp)) sb.appendCodePoint(cp)
            i += Character.charCount(cp)
        }
        return sb.toString()
    }

    /**
     * Wörter eines Satzes mit ihren Bereichen — `split(whereSeparator: { !$0.isLetter && !$0.isNumber })`
     * über Grapheme-Cluster, leere Normalformen fallen weg.
     */
    fun words(text: String): List<ReadAlongToken> {
        val out = ArrayList<ReadAlongToken>()
        if (text.isEmpty()) return out
        val b = FoundationText.clusterBoundaries(text)
        var tokenStart = -1
        for (k in 0 until b.size - 1) {
            val isWord = FoundationText.isWordScalar(text.codePointAt(b[k]))
            if (isWord) {
                if (tokenStart < 0) tokenStart = b[k]
            } else if (tokenStart >= 0) {
                emit(text, tokenStart, b[k], out)
                tokenStart = -1
            }
        }
        if (tokenStart >= 0) emit(text, tokenStart, text.length, out)
        return out
    }

    private fun emit(text: String, start: Int, end: Int, out: MutableList<ReadAlongToken>) {
        val word = normalize(text.substring(start, end))
        if (word.isNotEmpty()) out.add(ReadAlongToken(word, start, end))
    }

    /**
     * iOS: `trigramKey` (Swift `Hasher`, pro Prozess zufällig geseedet und nur im Speicher genutzt).
     * Hier als exakter Schlüssel — Normalformen enthalten nie U+0001, Kollisionen gibt es keine.
     */
    fun trigramKey(a: String, b: String, c: String): String = "$a\u0001$b\u0001$c"
}

/** iOS: `Locator.Text` — Kontext eines Highlights (je höchstens 40 Characters davor/danach). */
data class LocatorTextContext(val before: String?, val highlight: String?, val after: String?)

/** iOS: `EbookReadAlongIndex` — Sätze und Wörter des eBooks plus Trigramm-Index für den Abgleich. */
class EbookReadAlongIndex(
    val sentences: List<Sentence>,
    val words: List<Word>,
    /** Trigramm → Wortpositionen des ersten Worts. */
    val trigrams: Map<String, IntArray>,
    /** Wort-ID je eBook-Wort (Index in [vocabulary]). */
    val ids: IntArray,
    val vocabulary: Map<String, Int>,
) {
    /** iOS: `Sentence.locator` → hier Segment-Nummer (Locator-Quelle beim Aufrufer) + Text-Kontext. */
    data class Sentence(val segment: Int, val text: LocatorTextContext)

    data class Word(
        val normalized: String,
        val sentence: Int,
        /** Originaltext inkl. folgender Satzzeichen/Leerzeichen — aneinandergereiht wieder der eBook-Text. */
        val display: String,
    )

    val isEmpty: Boolean get() = words.isEmpty()

    /** Wörter eines Satzes (nach Satz sortiert → Binärsuche); halboffen `first until last`. */
    fun wordRange(ofSentence: Int): IntRange {
        fun firstWord(target: Int): Int {
            var low = 0
            var high = words.size
            while (low < high) {
                val mid = (low + high) / 2
                if (words[mid].sentence < target) low = mid + 1 else high = mid
            }
            return low
        }
        return firstWord(ofSentence) until firstWord(ofSentence + 1)
    }

    fun sentenceIndex(forWord: Int): Int? = words.getOrNull(forWord)?.sentence

    /**
     * iOS: `EbookReadAlongIndex.build(publication:)` ohne Readium: der Aufrufer liefert je Text-Segment
     * den Text und die Satzbereiche seines Tokenizers (UTF-16, halboffen). `null` = ganzes Segment.
     */
    class Builder {
        private val sentences = ArrayList<Sentence>()
        private val words = ArrayList<Word>()
        private var segmentCount = 0

        /** Gibt die Segment-Nummer zurück, unter der die Sätze dieses Segments geführt werden. */
        fun addSegment(segmentText: String, sentenceRanges: List<IntRange>? = null): Int {
            val segment = segmentCount++
            val ranges = sentenceRanges ?: listOf(0 until segmentText.length)
            for (range in ranges) {
                val start = range.first
                val end = range.last + 1
                val sentenceText = segmentText.substring(start, end)
                val tokens = ReadAlongText.words(sentenceText)
                if (tokens.isEmpty()) continue
                val sentenceIndex = sentences.size
                for ((offset, token) in tokens.withIndex()) {
                    // Von Wortbeginn bis zum nächsten Wort; das erste Wort übernimmt führende Zeichen,
                    // das letzte den Satzrest.
                    val from = if (offset == 0) 0 else token.start
                    val to = if (offset + 1 < tokens.size) tokens[offset + 1].start else sentenceText.length
                    var display = sentenceText.substring(from, to)
                    if (offset + 1 == tokens.size) {
                        val last = FoundationText.lastCharacter(display)
                        if (last == null || !FoundationText.characterIsWhitespace(last)) display += " "
                    }
                    words.add(Word(token.word, sentenceIndex, display))
                }
                sentences.add(Sentence(segment, highlighting(segmentText, start, end)))
            }
            return segment
        }

        fun build(): EbookReadAlongIndex {
            val trigrams = HashMap<String, MutableList<Int>>()
            if (words.size >= 3) {
                for (i in 0 until words.size - 2) {
                    val key = ReadAlongText.trigramKey(words[i].normalized, words[i + 1].normalized, words[i + 2].normalized)
                    trigrams.getOrPut(key) { ArrayList(1) }.add(i)
                }
            }
            val vocabulary = HashMap<String, Int>()
            val ids = IntArray(words.size)
            for ((i, word) in words.withIndex()) {
                ids[i] = vocabulary.getOrPut(word.normalized) { vocabulary.size }
            }
            return EbookReadAlongIndex(
                sentences.toList(), words.toList(), trigrams.mapValues { it.value.toIntArray() }, ids, vocabulary,
            )
        }
    }

    companion object {
        val empty = EbookReadAlongIndex(emptyList(), emptyList(), emptyMap(), IntArray(0), emptyMap())

        /** Kontextlänge der Locator-Texte (Characters). */
        const val CONTEXT_LENGTH = 40

        /** iOS: `Locator.highlighting(_:in:)` — Satz als Highlight, je 40 Characters Kontext. */
        fun highlighting(text: String, start: Int, end: Int): LocatorTextContext = LocatorTextContext(
            after = prefixCharacters(text.substring(end), CONTEXT_LENGTH).ifEmpty { null },
            before = suffixCharacters(text.substring(0, start), CONTEXT_LENGTH).ifEmpty { null },
            highlight = text.substring(start, end),
        )

        /** Swift `prefix(n)` über Characters. */
        fun prefixCharacters(s: String, n: Int): String {
            if (s.isEmpty()) return s
            val b = FoundationText.clusterBoundaries(s)
            return if (b.size - 1 <= n) s else s.substring(0, b[n])
        }

        /** Swift `suffix(n)` über Characters. */
        fun suffixCharacters(s: String, n: Int): String {
            if (s.isEmpty()) return s
            val b = FoundationText.clusterBoundaries(s)
            val count = b.size - 1
            return if (count <= n) s else s.substring(b[count - n])
        }
    }
}

/**
 * Reine Logik von iOS `EbookNarrationJumpController` (EbookReadAlong.swift): aus dem eBook-Wort an der
 * Hörposition die Markierungen der letzten [RECENT_WORD_COUNT] Wörter, je Satz eine Dekoration mit
 * Text-Kontext. Der Reader springt zur ersten.
 */
object EbookNarrationJump {
    const val MARKING_GROUP = "abstand-recent-words"
    /** So viele der zuletzt gehörten Wörter werden markiert. */
    const val RECENT_WORD_COUNT = 25
    /** Nach einem programmatischen Sprung so lange Positionsänderungen nicht als Nutzer-Blättern werten. */
    const val PROGRAMMATIC_NAVIGATION_GRACE_SECONDS = 1.5

    const val NOTICE_DOWNLOAD_REQUIRED = "Download the audiobook to jump to its position in the ebook."
    const val NOTICE_EBOOK_UNREADABLE = "The ebook couldn't be read."
    const val NOTICE_NOT_MATCHED =
        "This part of the audiobook can't be matched to the ebook yet. If its transcript is still being prepared, try again later."

    data class Decoration(
        /** `recent-<Satz>` */
        val id: String,
        val sentence: Int,
        /** Segment des Satzes (Locator-Quelle beim Aufrufer). */
        val segment: Int,
        /** Wortbereich (halboffen) im Index. */
        val wordStart: Int,
        val wordEnd: Int,
        val text: LocatorTextContext,
    )

    /** Dekorationen für die Wörter `end-24 … end` (leer, wenn [end] nicht im Index liegt). */
    fun decorations(index: EbookReadAlongIndex, end: Int): List<Decoration> {
        val endSentence = index.sentenceIndex(end) ?: return emptyList()
        val start = maxOf(0, end - RECENT_WORD_COUNT + 1)
        val startSentence = index.sentenceIndex(start) ?: return emptyList()
        val out = ArrayList<Decoration>()
        for (sentence in startSentence..endSentence) {
            val range = index.wordRange(sentence)
            val lo = maxOf(range.first, start)
            val hi = minOf(range.last + 1, end + 1)
            if (lo >= hi) continue
            out.add(
                Decoration(
                    "recent-$sentence", sentence, index.sentences[sentence].segment, lo, hi,
                    chunkText(sentence, lo, hi, index),
                ),
            )
        }
        return out
    }

    /**
     * iOS: `chunkLocator` — Satz-Locator mit Teilstring als Highlight, der restliche Satz dient als
     * Kontext davor/danach.
     */
    fun chunkText(sentence: Int, wordStart: Int, wordEnd: Int, index: EbookReadAlongIndex): LocatorTextContext {
        val base = index.sentences[sentence].text
        val all = index.wordRange(sentence)
        val prefix = (all.first until wordStart).joinToString("") { index.words[it].display }
        val suffix = (wordEnd until all.last + 1).joinToString("") { index.words[it].display }
        val highlight = FoundationText.trimmingWhitespacesAndNewlines(
            (wordStart until wordEnd).joinToString("") { index.words[it].display },
        )
        val n = EbookReadAlongIndex.CONTEXT_LENGTH
        return LocatorTextContext(
            after = EbookReadAlongIndex.prefixCharacters(suffix + (base.after ?: ""), n).ifEmpty { null },
            before = EbookReadAlongIndex.suffixCharacters((base.before ?: "") + prefix, n).ifEmpty { null },
            highlight = highlight,
        )
    }
}
