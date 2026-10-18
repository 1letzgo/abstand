package de.letzgo.abstand.ui.home

import androidx.compose.runtime.Composable
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.NowPlayingState
import de.letzgo.abstand.ui.components.AbstandPlayPill

/** Reine Rechenlogik der Continue-Hero-Karten (Restzeit in der Play-Pille, Fortschrittsbalken). */
object ContinueHeroMath {
    /** iOS: `ContinueListeningHeroBookCard.playPillRemainingCaption` (Sekunden). */
    fun bookRemainingSeconds(bookDuration: Double?, progress: AbsUserMediaProgress?): Double {
        val total = maxOf(bookDuration ?: 0.0, progress?.duration ?: 0.0, 0.0)
        if (total <= 0) return 0.0
        val p = progress ?: return total
        if (p.isFinished) return 0.0
        val elapsed = when {
            p.currentTime > 0 -> minOf(total, p.currentTime)
            p.duration > 0 && p.progress > 0 && p.progress <= 1 -> minOf(total, p.progress * p.duration)
            else -> 0.0
        }
        return maxOf(0.0, total - elapsed)
    }

    /** iOS: `ContinueListeningHeroBookCard.heroProgress01`. */
    fun bookProgress(progress: AbsUserMediaProgress?): Double? {
        val p = progress ?: return null
        if (p.isFinished || p.duration <= 0) return null
        return p.progress.coerceIn(0.0, 1.0)
    }

    /** iOS: `resolvedTotalDurationSeconds` — `recentEpisode` liefert oft keine Länge. */
    fun episodeTotalSeconds(episodeDuration: Double, progress: AbsUserMediaProgress?): Double = when {
        episodeDuration > 0 -> episodeDuration
        progress != null && progress.duration > 0 -> progress.duration
        else -> 0.0
    }

    /** iOS: `ContinueListeningHeroPodcastCard.playPillRemainingCaption` (Sekunden). */
    fun episodeRemainingSeconds(episodeDuration: Double, progress: AbsUserMediaProgress?): Double {
        val total = maxOf(0.0, episodeTotalSeconds(episodeDuration, progress))
        if (total <= 0) return 0.0
        val p = progress ?: return total
        if (p.isFinished) return 0.0
        val elapsed = if (p.currentTime > 0) {
            minOf(total, p.currentTime)
        } else {
            val basis = maxOf(p.duration, total)
            if (basis > 0 && p.progress > 0 && p.progress <= 1) minOf(total, p.progress * basis) else 0.0
        }
        return maxOf(0.0, total - elapsed)
    }

    /** iOS: `ContinueListeningHeroPodcastCard.heroProgress01`. */
    fun episodeProgress(episodeDuration: Double, progress: AbsUserMediaProgress?): Double? {
        val p = progress ?: return null
        if (p.isFinished) return null
        val total = maxOf(p.duration, episodeTotalSeconds(episodeDuration, p))
        if (total > 0) {
            val t = p.currentTime / total
            if (t.isFinite()) return t.coerceIn(0.0, 1.0)
        }
        return if (p.progress > 0 && p.progress <= 1) p.progress else null
    }

    /** iOS: `continueHeroAuthorSingleLine`. */
    fun authorLine(book: AbsBook): String = book.displayAuthorsCardLine.trim().let { if (it.isEmpty() || it == "—") "—" else it }
}

/** Android: Play-Pille der Home-Kompaktkarten (Symbol, wie `LibraryRowPlayPill` in Books). */
@Composable
internal fun HomeCompactPlayPill(itemId: String, episodeId: String?, isFinished: Boolean, caption: String? = null) {
    val nowPlaying = rememberNowPlaying()
    AbstandPlayPill(
        isPlaying = nowPlaying.isPlaying(itemId, episodeId),
        caption = caption,
        onClick = { continueHeroPlayPillToggle(nowPlaying, itemId, episodeId, isFinished) },
    )
}

/** iOS: `continueHeroPlayPillToggle` — aktives Medium pausieren/fortsetzen, sonst starten. */
private fun continueHeroPlayPillToggle(nowPlaying: NowPlayingState, itemId: String, episodeId: String?, isFinished: Boolean) {
    val launcher = AppModel.shared.playbackLauncher
    val isCurrent = nowPlaying.isActive(itemId, episodeId)
    when {
        isCurrent && nowPlaying.isPlaying -> launcher.pause()
        isCurrent && !isFinished -> launcher.resume()
        else -> launcher.play(itemId, episodeId)
    }
}
