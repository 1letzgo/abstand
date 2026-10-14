package de.letzgo.abstand.logic

import de.letzgo.abstand.data.AbsUserMediaProgress
import kotlin.math.abs

/**
 * iOS: `LibraryRowLiveState` (reine Teile). Der lokale eBook-Fortschritt kommt als Parameter
 * (iOS liest ihn selbst aus `EbookLocalStore`).
 */
object LibraryRowLiveState {
    /** Größerer von Server- und lokalem Fortschritt; unter 0,5 % = keiner, ab 99,5 % = fertig. */
    fun resolveEbookProgressFraction(serverEbookProgress: Double?, localFraction: Double?): Double? {
        val f = listOfNotNull(serverEbookProgress, localFraction).maxOrNull() ?: return null
        if (!(f > 0.005)) return null
        val clamped = minOf(1.0, maxOf(0.0, f))
        if (clamped >= 0.995) return 1.0
        return clamped
    }

    fun ebookProgressLabel(fraction: Double?): String? {
        val f = fraction ?: return null
        if (!(f < 0.995)) return null
        return "${swiftRounded(f * 100)}% read"
    }

    fun ebookOpenPillCaption(fraction: Double?): String {
        val f = fraction ?: return "Read"
        if (f >= 0.995) return "Finished"
        if (f > 0.005) return "Continue reading"
        return "Read"
    }

    /** Gleich genug, um eine Zeile nicht neu zu zeichnen. */
    fun progressMateriallyEqual(lhs: AbsUserMediaProgress?, rhs: AbsUserMediaProgress?): Boolean {
        if (lhs == null && rhs == null) return true
        if (lhs == null || rhs == null) return false
        return lhs.isFinished == rhs.isFinished &&
            abs(lhs.currentTime - rhs.currentTime) < 1.0 &&
            abs(lhs.progress - rhs.progress) < 0.01 &&
            abs(lhs.duration - rhs.duration) < 0.5
    }

    /** Download-Status einer Buch-Zeile (iOS `LibraryBookRowLiveState.syncDownloadState`). */
    data class DownloadState(val isDownloading: Boolean, val isQueued: Boolean, val downloadProgress: Double)

    fun bookDownloadState(
        bookId: String,
        storageId: String?,
        activeItemId: String?,
        progress: Double,
        queuedItemIds: List<String>,
    ): DownloadState {
        val active = activeItemId?.let(FoundationText::trimmingWhitespacesAndNewlines) ?: ""
        val storage = storageId ?: bookId
        val isQueued = queuedItemIds.contains(bookId) || queuedItemIds.contains(storage)
        if (active.isEmpty()) return DownloadState(false, isQueued, 0.0)
        val isDownloading = active == bookId || active == storage
        return DownloadState(isDownloading, isQueued, if (isDownloading) progress else 0.0)
    }

    /** Podcast-Folge (iOS `LibraryPodcastEpisodeRowLiveState.syncDownloadState`). */
    fun episodeDownloadState(offlineStorageId: String, activeItemId: String?, progress: Double, queuedItemIds: List<String>): DownloadState {
        val active = activeItemId == offlineStorageId
        return DownloadState(active, queuedItemIds.contains(offlineStorageId), if (active) progress else 0.0)
    }

    /** Swift `Double.rounded()` (kaufmännisch, .5 von null weg). */
    private fun swiftRounded(v: Double): Long = if (v >= 0) kotlin.math.floor(v + 0.5).toLong() else -kotlin.math.floor(-v + 0.5).toLong()
}
