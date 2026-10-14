package de.letzgo.abstand.downloads

import de.letzgo.abstand.data.AbsAudioTrack
import de.letzgo.abstand.data.AbsBook
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * iOS: `DownloadManager.downloadQueue` + `activeItemId` — FIFO, höchstens ein aktiver Lauf,
 * idempotentes Einreihen (bereits aktiv oder wartend → No-Op). Rein (keine Threads), JUnit-testbar.
 */
class DownloadQueue<T>(private val keyOf: (T) -> String) {
    private val waiting = ArrayDeque<T>()

    var active: T? = null
        private set

    val activeId: String? get() = active?.let(keyOf)

    /** Wartende IDs in Startreihenfolge (iOS: `queuedItemIds`). */
    val queuedIds: List<String> get() = waiting.map(keyOf)

    val isIdle: Boolean get() = active == null && waiting.isEmpty()

    fun contains(id: String): Boolean = activeId == id || waiting.any { keyOf(it) == id }

    /** `false`, wenn die ID schon aktiv oder wartend ist. */
    fun enqueue(entry: T): Boolean {
        if (contains(keyOf(entry))) return false
        waiting.addLast(entry)
        return true
    }

    /** Nächsten Eintrag aktiv setzen, sofern keiner läuft (iOS: `startNextQueuedDownload`). */
    fun takeNext(): T? {
        if (active != null) return null
        val next = waiting.removeFirstOrNull() ?: return null
        active = next
        return next
    }

    /** Aktiven Lauf beenden (Erfolg, Fehler oder Abbruch). */
    fun finishActive(): T? = active.also { active = null }

    /** Wartenden Eintrag entfernen (iOS: `cancel(itemId:)` für die Queue). */
    fun removeQueued(id: String): Boolean {
        val idx = waiting.indexOfFirst { keyOf(it) == id }
        if (idx < 0) return false
        waiting.removeAt(idx)
        return true
    }

    /** Unterbrochener Worker (System-Stopp): aktiven Eintrag wieder vorn einreihen. */
    fun requeueActiveAtFront() {
        val a = active ?: return
        active = null
        waiting.addFirst(a)
    }

    /** Persistenz: aktiver Eintrag zuerst, dann die Warteschlange. */
    fun snapshot(): List<T> = listOfNotNull(active) + waiting

    fun restore(entries: List<T>) {
        waiting.clear()
        active = null
        val seen = HashSet<String>()
        entries.forEach { if (seen.add(keyOf(it))) waiting.addLast(it) }
    }
}

/**
 * iOS: `QueuedDownload` — alle Parameter eines Download-Wunsches. Persistiert (WorkManager kann den
 * Prozess neu starten); der API-Client kommt zur Laufzeit vom [DownloadHost].
 */
@Serializable
data class QueuedDownloadRecord(
    val storageItemId: String,
    val book: AbsBook,
    val episodeId: String? = null,
    val reusePlaySessionId: String? = null,
    val reusePlaySessionTracks: List<AbsAudioTrack>? = null,
    /** Anzeige vor dem Manifest (iOS: `pendingDownloadCatalog`). */
    val title: String? = null,
    val subtitle: String? = null,
)

/** iOS: `DownloadWIP` (`download-wip.json`) — fertige Spuren für Wiederaufnahme nach Abbruch. */
@Serializable
data class DownloadWip(
    @SerialName("storageItemId") val storageItemId: String,
    @SerialName("libraryItemId") val libraryItemId: String,
    @SerialName("episodeId") val episodeId: String? = null,
    @SerialName("completedTrackIndexes") val completedTrackIndexes: List<Int>,
) {
    companion object {
        const val FILENAME = "download-wip.json"
    }
}

/** iOS: Gewichtung im `runDownload` — Gesamtfortschritt nach Spurdauer (min. 30 s, unbekannt 300 s). */
object DownloadProgressWeights {
    fun weights(tracks: List<AbsAudioTrack>): List<Double> = tracks.map { tr ->
        val d = tr.duration
        if (d.isFinite() && d > 0) maxOf(d, 30.0) else 300.0
    }

    fun sum(weights: List<Double>): Double = maxOf(weights.sum(), 1.0)

    /** Fortschritt 0…1 aus erledigtem Gewicht plus Anteil der laufenden Spur. */
    fun fraction(doneWeight: Double, trackWeight: Double, trackFraction: Double, sumWeights: Double): Double =
        minOf(1.0, (doneWeight + trackFraction.coerceIn(0.0, 1.0) * trackWeight) / sumWeights)
}
