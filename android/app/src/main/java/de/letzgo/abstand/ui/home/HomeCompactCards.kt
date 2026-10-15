package de.letzgo.abstand.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCardBottomProgress
import de.letzgo.abstand.ui.components.LibraryRowCollapsedMetaLine
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.semibold
import de.letzgo.abstand.ui.components.AbstandStatusBadges
import de.letzgo.abstand.ui.library.LibraryRowLayout

// Home-Regale (alle außer „Continue listening“): Kompaktkarte — Cover 1:1 links, rechts Titel
// (eine Zeile), Metazeile, unten Laufzeit/Status. Ohne Play-Pille, ≈ 3/4 der Regalbreite, ein Ziel:
// die Detailseite (iOS: HomeCompactCards.swift).

/** iOS: `HomeCompactCard` — Grundaufbau. */
@Composable
fun HomeCompactCard(
    title: String,
    subtitleLabel: String,
    subtitle: String,
    accessibilityHint: String,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
    contentOpacity: Float = 1f,
    showsProgressBar: Boolean = false,
    progressValue: Double = 0.0,
    cover: @Composable () -> Unit,
    footer: @Composable () -> Unit = {},
    badges: @Composable () -> Unit = {},
) {
    val palette = Theme.palette
    val side = AppTheme.Layout.homeCompactCardCoverSide
    Box(
        modifier
            .fillMaxWidth()
            .height(side)
            .libraryRowCardChrome(palette.card, palette.textSecondary.copy(alpha = 0.22f), onOpen)
            .semantics(mergeDescendants = true) {
                role = Role.Button
                contentDescription = "$title. $accessibilityHint"
            },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(LibraryRowLayout.cardInset)) {
            Box(Modifier.size(side).clip(LibraryRowLayout.coverClipShape).alpha(contentOpacity)) { cover() }
            Column(
                Modifier
                    .weight(1f)
                    .height(side)
                    .padding(
                        top = LibraryRowLayout.textInset,
                        end = LibraryRowLayout.textInset + AppTheme.Layout.tightSpacing,
                        bottom = LibraryRowLayout.bodyBottomInset(showsProgressBar),
                    ),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
            ) {
                Text(
                    title,
                    style = AppType.titleMedium.semibold,
                    color = palette.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.fillMaxWidth().alpha(contentOpacity),
                )
                LibraryRowCollapsedMetaLine(subtitleLabel, subtitle, valueMaxLines = 1, modifier = Modifier.alpha(contentOpacity))
                Spacer(Modifier.weight(1f))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                    Box(Modifier.weight(1f).alpha(contentOpacity)) { footer() }
                    badges()
                }
            }
        }
        if (showsProgressBar) {
            AbstandCardBottomProgress(progressValue, Modifier.align(Alignment.BottomCenter))
        }
    }
}

/** Fußzeile (Laufzeit/Lesefortschritt) — `subheadline`, monospaced-Ziffern-Rolle, `textSecondary`. */
@Composable
fun HomeCompactFooterText(text: String) {
    Text(text, style = AppType.bodyMedium, color = Theme.palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
}



/** iOS: `HomeBookCompactCard` — Hörbuch oder (Continue reading) eBook mit Lesefortschritt. */
@Composable
fun HomeBookCompactCard(book: AbsBook, onOpen: () -> Unit, usesEbookProgressDisplay: Boolean = false) {
    val usesEbookMetrics = book.isPureEbookLibraryItem || usesEbookProgressDisplay
    val progress = rememberProgress(book.id)
    val download = rememberDownloadBadge(book.id)
    val ebookFraction = if (usesEbookMetrics) AppModel.shared.home.ebookDisplayProgressFraction(book.id) else null
    val isFinished = if (usesEbookMetrics) (ebookFraction ?: 0.0) >= 0.995 else progress?.isFinished == true
    val showsProgressBar = if (usesEbookMetrics) {
        ebookFraction != null && ebookFraction > 0.005 && ebookFraction < 0.995
    } else {
        progress != null && !progress.isFinished && progress.duration > 0
    }
    val progressValue = when {
        usesEbookMetrics && ebookFraction != null -> ebookFraction.coerceIn(0.0, 1.0)
        progress != null && progress.duration > 0 -> progress.progress.coerceIn(0.0, 1.0)
        else -> 0.0
    }
    val author = book.displayAuthorsCardLine.trim().ifEmpty { "—" }
    HomeCompactCard(
        title = book.displayTitle,
        subtitleLabel = "Author",
        subtitle = author,
        accessibilityHint = "Opens book details.",
        onOpen = onOpen,
        contentOpacity = if (isFinished) LibraryRowLayout.finishedContentOpacity else 1f,
        showsProgressBar = showsProgressBar,
        progressValue = progressValue,
        cover = { SquareCoverImage(itemId = book.id, tint = coverTint(book.id)) },
        footer = {
            if (usesEbookMetrics) {
                ebookProgressLabel(ebookFraction)?.let { HomeCompactFooterText(it) }
            } else {
                HomeCompactFooterText(formatPlaybackTime(book.media.duration ?: 0.0))
            }
        },
        badges = { AbstandStatusBadges(isFinished, download.isDownloaded, download.isDownloading, download.progress) },
    )
}

/** iOS: `LibraryRowLiveState.ebookProgressLabel(for:)` — „42% read“; fertig = kein Label. */
fun ebookProgressLabel(fraction: Double?): String? {
    val f = fraction ?: return null
    if (f >= 0.995) return null
    return "${Math.round(f * 100)}% read"
}

/** iOS: `HomeEpisodeCompactCard`. */
@Composable
fun HomeEpisodeCompactCard(episode: AbsPodcastEpisodeListItem, onOpen: () -> Unit) {
    val progress = rememberProgress(episode.progressLookupKey)
    val download = rememberDownloadBadge(episode.libraryItemId, episode.episodeId)
    val total = ContinueHeroMath.episodeTotalSeconds(episode.duration, progress)
    val isFinished = progress?.isFinished == true
    val showsProgressBar = progress != null && !progress.isFinished && maxOf(progress.duration, total) > 0
    HomeCompactCard(
        title = episode.episodeTitle,
        subtitleLabel = "Show",
        subtitle = episode.showTitle,
        accessibilityHint = "Opens episode details.",
        onOpen = onOpen,
        contentOpacity = if (isFinished) LibraryRowLayout.finishedContentOpacity else 1f,
        showsProgressBar = showsProgressBar,
        progressValue = if (showsProgressBar) progress!!.progress.coerceIn(0.0, 1.0) else 0.0,
        cover = { SquareCoverImage(itemId = episode.libraryItemId, tint = coverTint(episode.libraryItemId)) },
        footer = { HomeCompactFooterText(formatPlaybackTime(total)) },
        badges = { AbstandStatusBadges(isFinished, download.isDownloaded, download.isDownloading, download.progress) },
    )
}

/** iOS: `HomeEntityCompactCard` — Serie/Autor: Cover links, Name, Metazeile, Buchanzahl unten. */
@Composable
fun HomeEntityCompactCard(
    title: String,
    subtitleLabel: String,
    subtitle: String,
    footer: String,
    accessibilityHint: String,
    onOpen: () -> Unit,
    cover: @Composable () -> Unit,
) {
    HomeCompactCard(
        title = title,
        subtitleLabel = subtitleLabel,
        subtitle = subtitle,
        accessibilityHint = accessibilityHint,
        onOpen = onOpen,
        cover = cover,
        footer = { if (footer.isNotEmpty()) HomeCompactFooterText(footer) },
    )
}

/** iOS: Buchanzahl-Fußzeile („1 book“ / „3 books“). */
fun booksCountLabel(count: Int?): String = when {
    count == null || count <= 0 -> ""
    count == 1 -> "1 book"
    else -> "$count books"
}

/**
 * iOS: `HomeEntityCoverCard` — Autor im Aufbau der Hero-Card (1:1-Cover oben, Titel + Meta darunter,
 * ohne Play-Pille). Für Autoren im Continue-listening-Regal.
 */
@Composable
fun HomeEntityCoverCard(
    title: String,
    detailLabel: String,
    detailValue: String,
    accessibilityHint: String,
    cardWidth: Dp,
    onOpen: () -> Unit,
    cover: @Composable () -> Unit,
) {
    val palette = Theme.palette
    val coverShape = RoundedCornerShape(topStart = AppTheme.Layout.coverCornerRadius, topEnd = AppTheme.Layout.coverCornerRadius)
    Column(
        Modifier
            .width(cardWidth)
            .libraryRowCardChrome(palette.card, palette.textSecondary.copy(alpha = 0.22f), onOpen)
            .semantics(mergeDescendants = true) {
                role = Role.Button
                contentDescription = "$title. $accessibilityHint"
            },
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f).clip(coverShape).background(palette.card)) { cover() }
        ContinueListeningHeroMetadataBlock(
            title = title,
            detailLabel = detailLabel,
            detailValue = detailValue,
            horizontalInset = AppTheme.Layout.libraryRowCardInset,
            blockHeight = AppTheme.Layout.libraryHeroMetadataBlockHeight,
            onTitleTap = onOpen,
            includesBottomPadding = true,
        )
    }
}
