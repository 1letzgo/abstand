package de.letzgo.abstand.logic

import de.letzgo.abstand.data.AbsJson
import kotlinx.serialization.Serializable
import java.io.File
import java.security.MessageDigest

/** iOS: `PlayerTranscriptWord` (PlayerLiveTranscriptionController.swift). */
data class PlayerTranscriptWord(
    val id: String,
    val text: String,
    val globalStart: Double,
    val globalEnd: Double,
) {
    val isWhitespaceOnly: Boolean get() = FoundationText.allWhitespace(text)
}

/** iOS: `PlayerTranscriptLine` (PlayerTranscriptTeleprompter.swift). */
data class PlayerTranscriptLine(
    val id: String,
    val words: List<PlayerTranscriptWord>,
    val globalStart: Double,
    val globalEnd: Double,
) {
    val spokenWords: List<PlayerTranscriptWord> get() = words.filter { !it.isWhitespaceOnly }
}

/**
 * iOS: `PlayerTranscriptTrackCache` — persistiertes Transkript je Hörbuch-Track. Zeiten sind lokale
 * Track-Sekunden; Abdeckung als Segmentliste. JSON-Schlüssel identisch zu iOS (`t`/`s`/`e`).
 */
@Serializable
data class PlayerTranscriptTrackCache(
    var version: Int = CURRENT_VERSION,
    var localeIdentifier: String,
    var trackIndex: Int,
    var segments: List<Segment> = emptyList(),
) {
    @Serializable
    data class Word(val t: String, val s: Double, val e: Double)

    @Serializable
    data class Segment(val start: Double, val end: Double, val words: List<Word>)

    /** Ist [time] (lokale Track-Sekunde) bereits transkribiert? */
    fun covers(time: Double): Boolean = segments.any { it.start - 0.5 <= time && time < it.end }

    /** Erste noch nicht abgedeckte Sekunde ab [time]; `null`, wenn bis [duration] alles vorliegt. */
    fun firstUncoveredTime(from: Double, duration: Double): Double? {
        var cursor = maxOf(0.0, from)
        for (segment in segments) {
            if (segment.end <= cursor) continue
            if (segment.start > cursor + 0.5) return cursor
            cursor = segment.end
        }
        if (!(duration <= 0 || cursor < duration - 1)) return null
        return cursor
    }

    /** iOS: `nextCoveredStart(after:)` — Beginn des nächsten transkribierten Segments (Ende einer Lücke). */
    fun nextCoveredStart(after: Double): Double? =
        segments.map { it.start }.filter { it > after + 0.5 }.minOrNull()

    /** iOS: `isOnsetRefined` — Wortanfänge akustisch verfeinert? Sonst greift beim Anzeigen die Heuristik. */
    val isOnsetRefined: Boolean get() = version >= 4

    /**
     * iOS: `insert(segment:)` — Segment einfügen und mit überlappenden/angrenzenden Segmenten verschmelzen.
     * `false`: nichts geändert (leeres Segment, oder ein alter Stand ginge dabei verloren).
     */
    fun insert(segment: Segment): Boolean {
        if (segment.words.isEmpty() && segment.end <= segment.start) return false
        // iOS gleich: neue Segmente kommen immer verfeinert aus dem Producer. Ein alter Stand wird dabei
        // verworfen statt gemischt — aber nie durch etwas, das in seinem Bereich viel weniger Wörter hat
        // (behauptete Abdeckung ohne Inhalt, iOS-Gerätefund: 217 Wörter „deckten" 14 h ab).
        if (version != CURRENT_VERSION) {
            if (!mayReplaceLegacy(segments, segment)) return false
            segments = emptyList()
            version = CURRENT_VERSION
        }
        val merged = ArrayList<Segment>()
        var pending = segment
        for (existing in swiftSorted(segments) { a, b -> a.start < b.start }) {
            if (existing.end < pending.start - 0.5) {
                merged.add(existing); continue
            }
            if (existing.start > pending.end + 0.5) {
                merged.add(existing); continue
            }
            // Überlappung: im Bereich des vorhandenen Segments gewinnt es. Vom neuen nur Wörter, die davor
            // beginnen oder ab kurz vor seinem Ende — und keins, das ein vorhandenes Wort an der Grenze doppelt.
            val head = existing.words.takeWhile { it.s < existing.start + BOUNDARY_DUPLICATE_WINDOW_SECONDS }
            val tail = existing.words.asReversed().takeWhile { it.e > existing.end - BOUNDARY_DUPLICATE_WINDOW_SECONDS }
            val before = pending.words.filter { word -> word.s < existing.start && head.none { isSameSpokenWord(it, word) } }
            val after = pending.words.filter { word ->
                word.s >= existing.start && word.s >= existing.end - BOUNDARY_TOLERANCE_SECONDS &&
                    tail.none { isSameSpokenWord(it, word) }
            }
            pending = Segment(
                start = minOf(existing.start, pending.start),
                end = maxOf(existing.end, pending.end),
                words = swiftSorted(before + existing.words + after) { a, b -> a.s < b.s },
            )
        }
        merged.add(pending)
        segments = swiftSorted(merged) { a, b -> a.start < b.start }
        return true
    }

    val allWords: List<Word> get() = swiftSorted(segments.flatMap { it.words }) { a, b -> a.s < b.s }

    companion object {
        /**
         * 2: Wortzeiten exakt verankert (MP3 sequenziell statt `seekTo`-Schätzung, Encoder-Delay
         * abgezogen) — ältere Transkripte waren zeitversetzt und werden neu erzeugt. iOS zieht mit.
         * 3: nie veröffentlicht (iOS-Debug-Build): konnte nach einem Abbruch fälschlich „bis Track-Ende
         *    abgedeckt" eintragen und dabei einen alten Stand ersetzen — wird verworfen (iOS gleich).
         * 4: Wortanfänge nach Sprechpausen auf den akustischen Einsatz gelegt ([SpeechOnsetRefiner]), Läufe
         *    mit Vor-/Nachlauf an den Lückengrenzen ([PlayerTranscriptRunWindow]).
         */
        const val CURRENT_VERSION = 4

        /**
         * iOS: `readableLegacyVersions` — Version 2 hat dieselbe Zeitbasis, nur unverfeinerte Anfänge: die
         * Anzeige korrigiert sie per [ReadAlongWordTiming], bis der Track neu erzeugt ist. Das erste neu
         * produzierte Segment ersetzt den ganzen alten Stand ([insert]). Version 3 fehlt absichtlich.
         */
        val READABLE_LEGACY_VERSIONS = setOf(2)

        /**
         * iOS: `legacyReplacementMinimumRatio`/`…MinimumWords` — ein alter Stand wird nur ersetzt, wenn das neue
         * Segment in seinem Bereich mindestens diesen Anteil der alten Wörter mitbringt (ab so vielen alten Wörtern).
         */
        const val LEGACY_REPLACEMENT_MINIMUM_RATIO = 0.5
        const val LEGACY_REPLACEMENT_MINIMUM_WORDS = 10

        /** iOS: `boundaryToleranceSeconds` — Zeitversatz desselben Worts zwischen zwei Läufen an Segmentgrenzen. */
        const val BOUNDARY_TOLERANCE_SECONDS = 0.3

        /** iOS: `boundaryDuplicateWindowSeconds` — nur so nah an einer Grenze können Doppelte liegen. */
        private const val BOUNDARY_DUPLICATE_WINDOW_SECONDS = 2.0

        /** iOS: `mayReplaceLegacy(_:with:)`. */
        fun mayReplaceLegacy(segments: List<Segment>, segment: Segment): Boolean {
            var legacyWords = 0
            for (existing in segments) {
                if (existing.end > segment.start && existing.start < segment.end) {
                    legacyWords += existing.words.count { it.s >= segment.start && it.s < segment.end }
                }
            }
            if (legacyWords < LEGACY_REPLACEMENT_MINIMUM_WORDS) return true
            return segment.words.size.toDouble() >= legacyWords.toDouble() * LEGACY_REPLACEMENT_MINIMUM_RATIO
        }

        /** iOS: `isSameSpokenWord` — Zeiten überlappen mindestens zur Hälfte des kürzeren (zeitlos: Anfänge ≤ 50 ms). */
        fun isSameSpokenWord(a: Word, b: Word): Boolean {
            val shorter = minOf(a.e - a.s, b.e - b.s)
            if (!(shorter > 0.02)) return kotlin.math.abs(a.s - b.s) < 0.05
            return minOf(a.e, b.e) - maxOf(a.s, b.s) >= shorter * 0.5
        }

        /**
         * Swift `sorted(by:)` ist (seit Swift 5) stabil — `sortedWith` auf der JVM ebenfalls; bei
         * gleichen Schlüsseln bleibt die Eingabereihenfolge.
         */
        internal fun <T> swiftSorted(list: List<T>, less: (T, T) -> Boolean): List<T> =
            list.sortedWith { a, b -> if (less(a, b)) -1 else if (less(b, a)) 1 else 0 }
    }
}

/**
 * iOS: `PlayerTranscriptRunWindow` — Lauf-Fenster für eine Transkript-Lücke `[gapStart, gapEnd)`. Ein Lauf,
 * der mitten in der Sprache beginnt, setzt sein erstes Wort auf den Laufstart; einer, der mitten in einem Wort
 * endet, verliert es. Deshalb wird ab [PRE_ROLL_SECONDS] vor der Lücke bis [POST_ROLL_SECONDS] nach ihrem Ende
 * gefüttert; übernommen werden nur Wörter, die in der Lücke beginnen ([keeps]). Das gespeicherte Segment
 * beginnt bei [gapStart], damit die Abdeckung nie den Vorlauf mitbehauptet.
 */
data class PlayerTranscriptRunWindow(val gapStart: Double, val gapEnd: Double?) {
    /** Lokale Track-Sekunde, ab der gefüttert wird (nie vor dem Track-Anfang). */
    val runStart: Double get() = maxOf(0.0, gapStart - PRE_ROLL_SECONDS)

    /** Ende des Fütterns (`null` = bis Dateiende). */
    val runEnd: Double? get() = gapEnd?.let { it + POST_ROLL_SECONDS }

    /** Wort mit diesem Anfang übernehmen? Vorlauf gehört dem Segment davor, ab [gapEnd] dem danach. */
    fun keeps(start: Double): Boolean {
        if (start < gapStart - PlayerTranscriptTrackCache.BOUNDARY_TOLERANCE_SECONDS) return false
        if (gapEnd != null && start >= gapEnd) return false
        return true
    }

    companion object {
        /** iOS gleich (am Mac gemessen: 3 s Vorlauf traf 119 von 120 ersten Wörtern, ohne nur 57). */
        const val PRE_ROLL_SECONDS = 3.0
        const val POST_ROLL_SECONDS = 2.5
    }
}

/**
 * iOS: `PlayerTranscriptCacheStore` — dateibasierter Speicher für Track-Transkripte und Abgleiche
 * unter `<account>/transcripts/<sha256(bookId)>/`.
 */
object PlayerTranscriptCacheStore {
    const val SUBDIR = "transcripts"

    /** Hex-SHA-256 (klein) — iOS `SHA256.hash(data: Data(bookId.utf8))`. */
    fun sha256Hex(value: String): String =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    fun bookDir(account: File, bookId: String): File =
        File(File(account, SUBDIR), sha256Hex(bookId))

    /** Sprache im Dateinamen; `/` → `_`. */
    private fun localeComponent(localeIdentifier: String) = localeIdentifier.replace("/", "_")

    /** `t<track>-<locale>.json` */
    fun transcriptFileName(trackIndex: Int, localeIdentifier: String) = "t$trackIndex-${localeComponent(localeIdentifier)}.json"

    /** `a<track>-<locale>.bin` */
    fun alignmentFileName(trackIndex: Int, localeIdentifier: String) = "a$trackIndex-${localeComponent(localeIdentifier)}.bin"

    fun fileFor(account: File, bookId: String, trackIndex: Int, localeIdentifier: String) =
        File(bookDir(account, bookId), transcriptFileName(trackIndex, localeIdentifier))

    fun alignmentFileFor(account: File, bookId: String, trackIndex: Int, localeIdentifier: String) =
        File(bookDir(account, bookId), alignmentFileName(trackIndex, localeIdentifier))

    fun decode(json: String): PlayerTranscriptTrackCache? {
        val cache = runCatching { AbsJson.decoder.decodeFromString(PlayerTranscriptTrackCache.serializer(), json) }.getOrNull()
            ?: return null
        // Unbekannte Version → Track neu produzieren; Version 2 bleibt lesbar (Anzeige-Heuristik).
        return cache.takeIf {
            it.version == PlayerTranscriptTrackCache.CURRENT_VERSION ||
                it.version in PlayerTranscriptTrackCache.READABLE_LEGACY_VERSIONS
        }
    }

    fun encode(cache: PlayerTranscriptTrackCache): String =
        AbsJson.encoder.encodeToString(PlayerTranscriptTrackCache.serializer(), cache)

    fun load(account: File?, bookId: String, trackIndex: Int, localeIdentifier: String): PlayerTranscriptTrackCache? {
        if (account == null || bookId.isEmpty()) return null
        val file = fileFor(account, bookId, trackIndex, localeIdentifier)
        val text = runCatching { file.readText() }.getOrNull() ?: return null
        return decode(text)
    }

    fun save(cache: PlayerTranscriptTrackCache, account: File?, bookId: String) {
        if (account == null || bookId.isEmpty()) return
        val file = fileFor(account, bookId, cache.trackIndex, cache.localeIdentifier)
        writeAtomically(file, encode(cache).toByteArray(Charsets.UTF_8))
    }

    fun loadAlignment(account: File?, bookId: String, trackIndex: Int, localeIdentifier: String): ByteArray? {
        if (account == null || bookId.isEmpty()) return null
        return runCatching { alignmentFileFor(account, bookId, trackIndex, localeIdentifier).readBytes() }.getOrNull()
    }

    fun saveAlignment(data: ByteArray, account: File?, bookId: String, trackIndex: Int, localeIdentifier: String) {
        if (account == null || bookId.isEmpty()) return
        writeAtomically(alignmentFileFor(account, bookId, trackIndex, localeIdentifier), data)
    }

    /** Alle Transkripte eines Buchs entfernen (Download gelöscht, Sprache gewechselt). */
    fun removeAll(account: File?, bookId: String) {
        if (account == null || bookId.isEmpty()) return
        bookDir(account, bookId).deleteRecursively()
    }

    fun totalSizeBytes(account: File?): Long {
        if (account == null) return 0
        return File(account, SUBDIR).walkBottomUp().filter { it.isFile }.sumOf { it.length() }
    }

    private fun writeAtomically(file: File, bytes: ByteArray) {
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeBytes(bytes)
            if (!tmp.renameTo(file)) {
                file.delete()
                tmp.renameTo(file)
            }
        }
    }
}
