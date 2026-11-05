package de.letzgo.abstand.logic

/**
 * iOS: `PlayerTranscriptLineAccumulator` — baut Teleprompter-Zeilen inkrementell; bei
 * Schriftgrößenwechsel komplett neu umbrechen. Nur finalisierte Wörter.
 */
/**
 * iOS: `PlayerTranscriptParagraphs` — Absätze für die Read-Along-Markierung. Das Transkript kennt
 * selbst keine Absätze, daher abgeleitet: ein Absatz endet an einem Satzende mit Sprechpause oder
 * nach einigen Sätzen, spätestens nach einer festen Zeilenzahl (Text ganz ohne Satzzeichen).
 */
object PlayerTranscriptParagraphs {
    const val MIN_PAUSE_SECONDS = 0.7
    const val MAX_SENTENCES = 3
    const val MAX_LINES = 6

    /** Je Zeile die laufende Nummer ihres Absatzes. */
    fun paragraphIndices(lines: List<PlayerTranscriptLine>): List<Int> {
        val result = ArrayList<Int>(lines.size)
        var paragraph = 0
        var sentences = 0
        var linesInParagraph = 0
        lines.forEachIndexed { index, line ->
            result.add(paragraph)
            linesInParagraph += 1
            val endsSentence = line.spokenWords.lastOrNull()?.let { PlayerTranscriptLineAccumulator.endsSentence(it.text) } ?: false
            if (endsSentence) sentences += 1
            val pause = if (index + 1 < lines.size) lines[index + 1].globalStart - line.globalEnd else 0.0
            if ((endsSentence && (pause >= MIN_PAUSE_SECONDS || sentences >= MAX_SENTENCES)) || linesInParagraph >= MAX_LINES) {
                paragraph += 1
                sentences = 0
                linesInParagraph = 0
            }
        }
        return result
    }
}

class PlayerTranscriptLineAccumulator {
    var closedLines: List<PlayerTranscriptLine> = emptyList()
        private set
    private val closed = ArrayList<PlayerTranscriptLine>()
    private var openWords = ArrayList<PlayerTranscriptWord>()
    private var openCharCount = 0
    private var nextLineIndex = 0
    private var nextWordIndex = 0

    /** Aus Panel-Breite abgeleitet; Fallback bis Layout bekannt ist. */
    var maxCharactersPerLine = 84

    fun reset() {
        closed.clear()
        closedLines = emptyList()
        openWords = ArrayList()
        openCharCount = 0
        nextLineIndex = 0
        nextWordIndex = 0
    }

    /** Bestehende Wörter mit neuem Zeichenlimit neu umbrechen. */
    fun rebuildLines(words: List<PlayerTranscriptWord>, maxCharactersPerLine: Int) {
        this.maxCharactersPerLine = maxCharactersPerLine
        reset()
        appendFinalizedWords(words)
    }

    fun appendFinalizedWords(incoming: List<PlayerTranscriptWord>) {
        for (raw in incoming) {
            val word = stabilized(raw)
            if (word.isWhitespaceOnly) {
                if (openWords.isNotEmpty()) openWords.add(word)
                continue
            }
            val add = FoundationText.characterCount(word.text)
            if (openCharCount > 0 && openCharCount + add > maxCharactersPerLine) closeOpenLine()
            openWords.add(word)
            openCharCount += add
            if (endsSentence(word.text)) closeOpenLine()
        }
        closedLines = closed.toList()
    }

    fun publishedLines(): List<PlayerTranscriptLine> {
        val all = ArrayList(closed)
        openLineSnapshot()?.let { all.add(it) }
        return all
    }

    private fun openLineSnapshot(): PlayerTranscriptLine? {
        val spoken = openWords.filter { !it.isWhitespaceOnly }
        if (spoken.isEmpty()) return null
        return PlayerTranscriptLine(
            id = "line-$nextLineIndex",
            words = openWords.toList(),
            globalStart = spoken.first().globalStart,
            globalEnd = maxOf(spoken.last().globalEnd, spoken.first().globalStart + 0.05),
        )
    }

    private fun closeOpenLine() {
        val snapshot = openLineSnapshot()
        if (snapshot != null) {
            closed.add(snapshot)
            nextLineIndex += 1
        }
        openWords = ArrayList()
        openCharCount = 0
    }

    private fun stabilized(word: PlayerTranscriptWord): PlayerTranscriptWord {
        val id = "w-$nextWordIndex"
        nextWordIndex += 1
        return word.copy(id = id)
    }

    companion object {
        private const val CLOSING_QUOTES = "'\"»」)]}"
        private const val SENTENCE_ENDS = ".!?…"

        /** Satzende: nach `.` `!` `?` `…` (Anführungszeichen/Klammern am Ende ignorieren). */
        fun endsSentence(text: String): Boolean {
            var t = FoundationText.trimmingWhitespacesAndNewlines(text)
            while (true) {
                val last = FoundationText.lastCharacter(t) ?: return false
                if (last.length == 1 && CLOSING_QUOTES.contains(last[0])) {
                    t = t.substring(0, t.length - last.length)
                    continue
                }
                return last.length == 1 && SENTENCE_ENDS.contains(last[0])
            }
        }
    }
}
