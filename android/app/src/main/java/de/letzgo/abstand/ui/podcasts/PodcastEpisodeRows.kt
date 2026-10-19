package de.letzgo.abstand.ui.podcasts

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCard
import de.letzgo.abstand.ui.components.AbstandCardBottomProgress
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.LibraryRowCollapsedMetaLine
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.components.AbstandPlayPill
import de.letzgo.abstand.ui.components.AbstandStatusBadges
import de.letzgo.abstand.ui.library.LibraryRowLayout

/** iOS: `LibraryRowLayout` (Ausschnitt) — Maße der Library-Zeilen. */
internal object PodcastRowLayout {
    val coverSide = AppTheme.Layout.libraryRowCoverSide
    val cardInset = AppTheme.Layout.libraryRowCardInset
    const val finishedContentOpacity = 0.35f
    val rowShape = RoundedCornerShape(AppTheme.Layout.libraryRowCornerRadius)
    val statusIconSize = 16.dp
    val playPillIconSize = 12.dp
}

/** Live-Zustand einer Folgen-Zeile (iOS: `LibraryPodcastEpisodeRowLiveState`). */
internal data class PodcastEpisodeRowLive(
    val progress: AbsUserMediaProgress?,
    val isDownloaded: Boolean,
    val downloadProgress: Double?,
    val isPlaying: Boolean,
)

/** iOS: `resolvedTotalDurationSeconds` — `recentEpisode` liefert oft keine Länge, dann aus dem Fortschritt. */
internal fun resolvedEpisodeDuration(episode: AbsPodcastEpisodeListItem, progress: AbsUserMediaProgress?): Double = when {
    episode.duration > 0 -> episode.duration
    progress != null && progress.duration > 0 -> progress.duration
    else -> 0.0
}

/**
 * iOS: `PodcastEpisodeRowCard` — kompakte Folgen-Zeile: Show-Cover links, Titel + Status-Badges,
 * Sendung, unten Dauer und Play-Pille; Fortschrittsstreifen am Kartenfuß; beendete Folgen gedimmt.
 * Tap auf die Karte öffnet das Detail, die Pille spielt/pausiert.
 */
@Composable
internal fun PodcastEpisodeRowCard(
    episode: AbsPodcastEpisodeListItem,
    live: PodcastEpisodeRowLive,
    onOpenDetail: (() -> Unit)?,
    onPlayToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = Theme.palette
    val prog = live.progress
    val isFinished = prog?.isFinished == true
    val total = resolvedEpisodeDuration(episode, prog)
    val showsProgressBar = prog != null && !isFinished && maxOf(prog.duration, total) > 0
    val contentAlpha = if (isFinished) PodcastRowLayout.finishedContentOpacity else 1f
    PodcastRowCardChrome(
        modifier = modifier,
        onClick = onOpenDetail,
        bottomProgress = if (showsProgressBar) prog!!.progress.coerceIn(0.0, 1.0) else null,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(PodcastRowLayout.cardInset)) {
            CoverImage(
                itemId = episode.libraryItemId,
                modifier = Modifier.size(PodcastRowLayout.coverSide).alpha(contentAlpha),
            )
            Column(
                Modifier
                    .weight(1f)
                    .height(PodcastRowLayout.coverSide)
                    .padding(vertical = AppTheme.Layout.libraryRowTextInset)
                    .padding(end = AppTheme.Layout.libraryRowTextInset),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
                    Text(
                        episode.episodeTitle,
                        style = AppType.titleMedium,
                        color = palette.textPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f).alpha(contentAlpha),
                    )
                    AbstandStatusBadges(isFinished, live.isDownloaded, live.downloadProgress != null && !live.isDownloaded, live.downloadProgress ?: 0.0)
                }
                Text(
                    episode.showTitle.ifBlank { "—" },
                    style = AppType.bodyMedium,
                    color = palette.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.alpha(contentAlpha),
                )
                Spacer(Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        formatPlaybackTime(total),
                        style = AppType.bodyMedium,
                        color = palette.textSecondary,
                        modifier = Modifier.weight(1f).alpha(contentAlpha),
                    )
                    PodcastPlayPill(isPlaying = live.isPlaying, onClick = onPlayToggle, modifier = Modifier.alpha(contentAlpha))
                }
            }
        }
    }
}

/**
 * iOS: `LibraryRowLayout.libraryRowCardChrome` — Karte mit Library-Zeilen-Ecken, optionalem
 * Fortschrittsstreifen am unteren Rand und Tap-Ziel.
 */
@Composable
internal fun PodcastRowCardChrome(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    bottomProgress: Double? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    AbstandCard(modifier.fillMaxWidth(), shape = PodcastRowLayout.rowShape, onClick = onClick) {
        content()
        if (bottomProgress != null) AbstandCardBottomProgress(bottomProgress)
    }
}

/** iOS: `LibraryRowPlayPill` — Akzent-Kapsel mit Play/Pause. */
@Composable
internal fun PodcastPlayPill(isPlaying: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    AbstandPlayPill(isPlaying, onClick, modifier)
}

/** Kompakte Text-Zeile „Label: Wert“ (iOS: `LibraryRowCollapsedMetaLine`). */
@Composable
internal fun PodcastRowMetaLine(label: String, value: String) {
    Text(
        "$label: $value",
        style = AppType.bodyMedium,
        color = Theme.palette.textSecondary,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}
