package de.letzgo.abstand.logic

/**
 * iOS: `ReadAlongWordTiming` (PlayerTranscriptLineAccumulator.swift) — korrigiert Wortanfänge, die
 * der Erkenner in eine vorausgehende Sprechpause vorzieht.
 *
 * Ein Wort darf höchstens [maxDuration] vor seinem Ende beginnen (Basis + je sichtbarem Zeichen);
 * das Ende bleibt. Werte an iOS-`SpeechTranscriber` mit synthetischer Sprache gemessen — der
 * Android-Erkenner (Vosk) ist nicht vermessen. Seit Transkript-Version 4 legt der Producer die Anfänge
 * auf den akustischen Einsatz ([SpeechOnsetRefiner]); diese Heuristik ist nur noch der Rückfall für alte
 * Transkripte (Version 2) und wirkt nie auf verfeinerte Wörter.
 */
object ReadAlongWordTiming {
    const val BASE_MAX_DURATION = 0.15
    const val MAX_DURATION_PER_CHARACTER = 0.10

    /** Sichtbare Zeichen ohne Leerraum (Swift: Characters ohne `isWhitespace`). */
    fun characterCount(text: String): Int {
        if (text.isEmpty()) return 0
        val b = FoundationText.clusterBoundaries(text)
        var count = 0
        for (k in 0 until b.size - 1) if (!FoundationText.isWhiteSpaceScalar(text.codePointAt(b[k]))) count += 1
        return count
    }

    fun maxDuration(characterCount: Int): Double =
        BASE_MAX_DURATION + MAX_DURATION_PER_CHARACTER * maxOf(0, characterCount).toDouble()

    /**
     * `max(start, end − maxDuration)`, höchstens bis zum (unkorrigierten) Start des Folgeworts —
     * so bleiben die Anfänge monoton. Unverändert bei `end ≤ start` oder ungültigen Zeiten.
     */
    fun correctedStart(start: Double, end: Double, characterCount: Int, nextStart: Double?): Double {
        if (!start.isFinite() || !end.isFinite() || end <= start) return start
        var corrected = maxOf(start, end - maxDuration(characterCount))
        if (nextStart != null && nextStart.isFinite()) {
            corrected = maxOf(start, minOf(corrected, nextStart))
        }
        return corrected
    }

    /**
     * Wörter (nach Startzeit sortiert) mit korrigierten Anfängen; Ende, Text und ID bleiben.
     * Folgewort ist das nächste Nicht-Leerraum-Wort derselben Liste.
     */
    fun corrected(words: List<PlayerTranscriptWord>): List<PlayerTranscriptWord> {
        val out = words.toMutableList()
        var nextStart: Double? = null
        for (index in words.indices.reversed()) {
            val word = words[index]
            if (word.isWhitespaceOnly) continue
            val start = correctedStart(word.globalStart, word.globalEnd, characterCount(word.text), nextStart)
            if (start != word.globalStart) out[index] = word.copy(globalStart = start)
            nextStart = word.globalStart
        }
        return out
    }
}
