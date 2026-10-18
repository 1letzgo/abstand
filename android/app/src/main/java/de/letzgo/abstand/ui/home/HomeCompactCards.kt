package de.letzgo.abstand.ui.home

import androidx.compose.ui.graphics.RectangleShape
import de.letzgo.abstand.logic.BookDetailLogic
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import de.letzgo.abstand.ui.components.AbstandStatusBadges
import de.letzgo.abstand.ui.library.LibraryRowLayout
import de.letzgo.abstand.ui.components.abstandCardChrome

// Home-Regale (Android: alle, auch „Continue listening“): Kompaktkarte — Cover 1:1 links, rechts Titel
// (eine Zeile), Metazeile, unten Laufzeit/Status und (Bücher/Folgen) die Play-Pille wie in Books,
// ≈ 3/4 der Regalbreite; Tippen auf die Karte öffnet die Detailseite (iOS: HomeCompactCards.swift).

/** Cover-Kantenlänge (= Kartenhöhe) der Kompaktkarten; „Continue listening“ setzt sie größer. */
val LocalHomeCompactCardCoverSide = staticCompositionLocalOf { AppTheme.Layout.libraryRowCoverSide }

/** `true` nur in „Continue listening“: Titel zweizeilig, gefüllte Play-Pille mit Restzeit statt Laufzeit-Fußzeile. */
val LocalHomeCompactCardIsHero = staticCompositionLocalOf { false }

/** iOS: `HomeCompactCard` — Grundaufbau. */
@Composable
fun HomeCompactCard(
    title: String,
    subtitleLabel: String,
    subtitle: String,
    accessibilityHint: String,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
    /** Beendet: Cover und Play-Pille mit [AppTheme.disabledContentAlpha], Titel in `onSurfaceVariant` (bleibt lesbar). */
    isFinished: Boolean = false,
    showsProgressBar: Boolean = false,
    progressValue: Double = 0.0,
    cover: @Composable () -> Unit,
    footer: @Composable () -> Unit = {},
    badges: @Composable () -> Unit = {},
    /** Android: Play-Pille unten rechts (wie `LibraryRowPlayPill` in Books); `null` = keine. */
    playAction: (@Composable () -> Unit)? = null,
) {
    val palette = Theme.palette
    val side = LocalHomeCompactCardCoverSide.current
    val isHero = LocalHomeCompactCardIsHero.current
    val dim = if (isFinished) AppTheme.disabledContentAlpha else 1f
    Box(
        modifier
            .fillMaxWidth()
            .height(side)
            // M3 Filled Card (12 dp, ohne Rand) über die gemeinsame Karten-Vorlage.
            // Hero liegt randlos am Bildschirmrand → ohne Eckenrundung.
            .abstandCardChrome(palette.card, if (isHero) RectangleShape else LibraryRowLayout.cardShape, onClick = onOpen)
            .semantics(mergeDescendants = true) {
                role = Role.Button
                contentDescription = "$title. $accessibilityHint"
            },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(LibraryRowLayout.cardInset)) {
            Box(Modifier.size(side).clip(if (isHero) RectangleShape else LibraryRowLayout.coverClipShape).alpha(dim)) { cover() }
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
                    style = AppType.titleMedium,
                    color = if (isFinished) palette.textSecondary else palette.textPrimary,
                    maxLines = if (isHero) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.fillMaxWidth(),
                )
                LibraryRowCollapsedMetaLine(
                    subtitleLabel, subtitle, valueMaxLines = 1,
                    valueColor = if (isFinished) palette.textSecondary else null,
                )
                Spacer(Modifier.weight(1f))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                    Box(Modifier.weight(1f)) { footer() }
                    badges()
                    if (playAction != null) {
                        Spacer(Modifier.width(AppTheme.Layout.stackSpacing))
                        Box(Modifier.alpha(dim)) { playAction() }
                    }
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
    val isHero = LocalHomeCompactCardIsHero.current
    HomeCompactCard(
        title = book.displayTitle,
        subtitleLabel = "Author",
        subtitle = author,
        accessibilityHint = "Opens book details.",
        onOpen = onOpen,
        isFinished = isFinished,
        showsProgressBar = showsProgressBar,
        progressValue = progressValue,
        cover = { SquareCoverImage(itemId = book.id, tint = coverTint(book.id)) },
        footer = {
            when {
                usesEbookMetrics -> ebookProgressLabel(ebookFraction)?.let { HomeCompactFooterText(it) }
                // Hero: Restzeit steht in der Play-Pille, keine doppelte Zeitangabe.
                isHero -> Unit
                else -> HomeCompactFooterText(formatPlaybackTime(book.media.duration ?: 0.0))
            }
        },
        badges = { AbstandStatusBadges(isFinished, download.isDownloaded, download.isDownloading, download.progress) },
        playAction = if (usesEbookMetrics) null else ({
            HomeCompactPlayPill(
                book.id, null, isFinished,
                caption = if (isHero) BookDetailLogic.remainingCaption(book.media.duration ?: 0.0, progress) else null,
            )
        }),
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
    val isHero = LocalHomeCompactCardIsHero.current
    HomeCompactCard(
        title = episode.episodeTitle,
        subtitleLabel = "Show",
        subtitle = episode.showTitle,
        accessibilityHint = "Opens episode details.",
        onOpen = onOpen,
        isFinished = isFinished,
        showsProgressBar = showsProgressBar,
        progressValue = if (showsProgressBar) progress!!.progress.coerceIn(0.0, 1.0) else 0.0,
        cover = { SquareCoverImage(itemId = episode.libraryItemId, tint = coverTint(episode.libraryItemId)) },
        footer = { if (!isHero) HomeCompactFooterText(formatPlaybackTime(total)) },
        badges = { AbstandStatusBadges(isFinished, download.isDownloaded, download.isDownloading, download.progress) },
        playAction = {
            HomeCompactPlayPill(
                episode.libraryItemId, episode.episodeId, isFinished,
                caption = if (isHero) BookDetailLogic.remainingCaption(total, progress) else null,
            )
        },
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
