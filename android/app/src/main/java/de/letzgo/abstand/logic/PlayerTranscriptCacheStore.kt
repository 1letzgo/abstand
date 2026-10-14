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

    /** Segment einfügen und mit überlappenden/angrenzenden Segmenten verschmelzen. */
    fun insert(segment: Segment) {
        if (segment.words.isEmpty() && segment.end <= segment.start) return
        val merged = ArrayList<Segment>()
        var pending = segment
        for (existing in swiftSorted(segments) { a, b -> a.start < b.start }) {
            if (existing.end < pending.start - 0.5) {
                merged.add(existing); continue
            }
            if (existing.start > pending.end + 0.5) {
                merged.add(existing); continue
            }
            // Überlappung: Wörter zusammenführen, doppelte Zeitbereiche verwerfen.
            val words = ArrayList(existing.words)
            val existingEnd = existing.end
            words.addAll(pending.words.filter { it.s >= existingEnd - 0.05 })
            val keptFromPending = pending.words.filter { it.e <= existing.start + 0.05 }
            words.addAll(0, keptFromPending)
            pending = Segment(
                start = minOf(existing.start, pending.start),
                end = maxOf(existing.end, pending.end),
                words = swiftSorted(words) { a, b -> a.s < b.s },
            )
        }
        merged.add(pending)
        segments = swiftSorted(merged) { a, b -> a.start < b.start }
    }

    val allWords: List<Word> get() = swiftSorted(segments.flatMap { it.words }) { a, b -> a.s < b.s }

    companion object {
        const val CURRENT_VERSION = 1

        /**
         * Swift `sorted(by:)` ist (seit Swift 5) stabil — `sortedWith` auf der JVM ebenfalls; bei
         * gleichen Schlüsseln bleibt die Eingabereihenfolge.
         */
        internal fun <T> swiftSorted(list: List<T>, less: (T, T) -> Boolean): List<T> =
            list.sortedWith { a, b -> if (less(a, b)) -1 else if (less(b, a)) 1 else 0 }
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
        // Andere Version → Track neu produzieren.
        return cache.takeIf { it.version == PlayerTranscriptTrackCache.CURRENT_VERSION }
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
