package de.letzgo.abstand.logic

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * iOS: `PlayerTranscriptTrackSource` — eine lokale Track-Datei mit ihrer Lage im Hörbuch.
 * [assetPath] ist der lokale Dateipfad (iOS `assetURL`).
 */
data class PlayerTranscriptTrackSource(
    val trackIndex: Int,
    val assetPath: String,
    val globalOffset: Double,
    val duration: Double,
) {
    val globalRange: ClosedFloatingPointRange<Double> get() = globalOffset..(globalOffset + maxOf(0.0, duration))
}

/**
 * iOS: `PlayerTranscriptLibrary` — gemeinsamer Zugriff auf persistierte Transkripte (ohne die
 * Produktion selbst: die Spracherkennung kommt später über den Producer). Teleprompter, Recap und
 * Vorproduktion teilen dieselben Dateien; Schreibvorgänge je Datei sind serialisiert.
 */
object PlayerTranscriptLibrary {
    /** Zwischenspeichern nach so vielen produzierten Audiosekunden. */
    const val TRANSCRIPT_PERSIST_INTERVAL_SECONDS = 120.0

    /** Aktives Account-Verzeichnis (iOS `PlayerTranscriptCacheStore.activeAccount`). */
    @Volatile
    var activeAccount: File? = null

    @Volatile
    private var priorityWorkCount = 0

    val isPriorityWorkActive: Boolean get() = priorityWorkCount > 0

    @Synchronized
    fun beginPriorityWork() { priorityWorkCount += 1 }

    @Synchronized
    fun endPriorityWork() { priorityWorkCount = maxOf(0, priorityWorkCount - 1) }

    /** Schreib-Ketten je Transkriptdatei (iOS `mergeChains`) — ein Mutex je `bookId|track|locale`. */
    private val mergeLocks = ConcurrentHashMap<String, Mutex>()

    suspend fun cache(bookId: String, trackIndex: Int, localeIdentifier: String, account: File? = activeAccount): PlayerTranscriptTrackCache? =
        withContext(Dispatchers.IO) { PlayerTranscriptCacheStore.load(account, bookId, trackIndex, localeIdentifier) }

    /** Wortliste eines Tracks aus dem Cache (lokale Track-Sekunden). */
    suspend fun cachedWords(bookId: String, trackIndex: Int, localeIdentifier: String, account: File? = activeAccount): List<PlayerTranscriptTrackCache.Word> =
        cache(bookId, trackIndex, localeIdentifier, account)?.allWords ?: emptyList()

    /** Segment atomar in die Transkriptdatei mergen (load → insert → save), gibt den neuen Stand zurück. */
    suspend fun mergeAndSave(
        segment: PlayerTranscriptTrackCache.Segment,
        bookId: String,
        trackIndex: Int,
        localeIdentifier: String,
        account: File? = activeAccount,
    ): PlayerTranscriptTrackCache {
        val lock = mergeLocks.getOrPut("$bookId|$trackIndex|$localeIdentifier") { Mutex() }
        return lock.withLock {
            withContext(Dispatchers.IO) {
                val cache = PlayerTranscriptCacheStore.load(account, bookId, trackIndex, localeIdentifier)
                    ?: PlayerTranscriptTrackCache(localeIdentifier = localeIdentifier, trackIndex = trackIndex)
                cache.insert(segment)
                PlayerTranscriptCacheStore.save(cache, account, bookId)
                cache
            }
        }
    }

    /** Fehlt im Track noch etwas ab [from]? Liefert die erste offene lokale Sekunde. */
    suspend fun firstUncoveredTime(
        bookId: String,
        source: PlayerTranscriptTrackSource,
        localeIdentifier: String,
        from: Double,
        account: File? = activeAccount,
    ): Double? {
        val existing = cache(bookId, source.trackIndex, localeIdentifier, account)
            ?: PlayerTranscriptTrackCache(localeIdentifier = localeIdentifier, trackIndex = source.trackIndex)
        return existing.firstUncoveredTime(from, source.duration)
    }

    /** Lokales Fenster eines Tracks für einen globalen Bereich (iOS `transcriptText`, `nil` = leer). */
    fun localWindow(source: PlayerTranscriptTrackSource, globalRange: ClosedFloatingPointRange<Double>): ClosedFloatingPointRange<Double>? {
        val localStart = maxOf(0.0, globalRange.start - source.globalOffset)
        val localEnd = minOf(
            if (source.duration > 0) source.duration else globalRange.endInclusive - source.globalOffset,
            globalRange.endInclusive - source.globalOffset,
        )
        if (!(localEnd > localStart)) return null
        return localStart..localEnd
    }

    /**
     * Recap-Text aus vorliegenden Cache-Wörtern (ohne Nachproduktion der Lücken): je Track die Wörter,
     * die das lokale Fenster berühren, mit Leerzeichen verbunden.
     */
    fun transcriptText(
        sources: List<PlayerTranscriptTrackSource>,
        globalRange: ClosedFloatingPointRange<Double>,
        wordsForTrack: (Int) -> List<PlayerTranscriptTrackCache.Word>,
    ): String {
        val parts = ArrayList<String>()
        for (source in PlayerTranscriptTrackCache.swiftSorted(sources) { a, b -> a.globalOffset < b.globalOffset }) {
            val window = localWindow(source, globalRange) ?: continue
            val words = wordsForTrack(source.trackIndex).filter { it.e >= window.start && it.s <= window.endInclusive }
            if (words.isEmpty()) continue
            parts.add(words.joinToString(" ") { it.t })
        }
        return FoundationText.trimmingWhitespacesAndNewlines(parts.joinToString(" "))
    }
}

/**
 * iOS: `EbookAlignmentStore.loadOrBuild` — gespeicherten Abgleich nehmen, wenn eBook- und
 * Transkript-Wortzahl passen, sonst neu rechnen und speichern. Blockierend (Hintergrund-Thread).
 */
object EbookAlignmentStore {
    /** iOS: Speicher-Schlüssel `bookId|track|locale|eBook-Wortzahl`. */
    fun key(bookId: String, trackIndex: Int, localeIdentifier: String, index: EbookReadAlongIndex) =
        "$bookId|$trackIndex|$localeIdentifier|${index.words.size}"

    fun loadOrBuild(
        account: File?,
        bookId: String,
        trackIndex: Int,
        localeIdentifier: String,
        words: List<AlignmentInputWord>,
        index: EbookReadAlongIndex,
    ): EbookTrackAlignment {
        val stored = PlayerTranscriptCacheStore.loadAlignment(account, bookId, trackIndex, localeIdentifier)
            ?.let(EbookTrackAlignment::decode)
        if (stored != null && stored.ebookWordCount == index.words.size && stored.spokenWordCount == words.size) return stored
        val built = EbookAlignmentBuilder.build(words, index)
        PlayerTranscriptCacheStore.saveAlignment(built.encoded(), account, bookId, trackIndex, localeIdentifier)
        return built
    }
}
