package de.letzgo.abstand.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import de.letzgo.abstand.data.AbsStartShelfSection
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.NowPlayingState
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.LocalAbstandCardShadowEnabled
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCardBottomProgress
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.CoverImageContentMode
import de.letzgo.abstand.ui.components.LibraryRowCollapsedMetaLine
import de.letzgo.abstand.ui.components.abstandHeroCardOutline
import de.letzgo.abstand.ui.destinations.BookDetailDestination
import de.letzgo.abstand.ui.destinations.EpisodeDestination
import de.letzgo.abstand.ui.formatPlaybackDurationShortHuman
import de.letzgo.abstand.ui.semibold
import de.letzgo.abstand.ui.components.AbstandCoverDownloadBadge
import de.letzgo.abstand.ui.components.AbstandCoverPillIcon
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

/** Medientyp-Pille oben links (iOS: `ContinueListeningHeroTypePill`). */
enum class HeroMediaType { Audiobook, Podcast }

@Composable
fun ContinueListeningHeroTypePill(type: HeroMediaType) {
    AbstandCoverPillIcon(
        if (type == HeroMediaType.Audiobook) SF.bookFill else SF.micFill,
        contentDescription = if (type == HeroMediaType.Audiobook) "Audiobook" else "Podcast",
    )
}

/**
 * iOS: `ContinueListeningHeroMetadataBlock` — Titel (2 Zeilen, feste Höhe) + Meta-Zeile unter dem
 * Cover; [cardTint] steuert lesbare Farben auf getönten Karten.
 */
@Composable
fun ContinueListeningHeroMetadataBlock(
    title: String,
    detailLabel: String,
    detailValue: String,
    horizontalInset: Dp,
    blockHeight: Dp,
    onTitleTap: () -> Unit,
    includesBottomPadding: Boolean = false,
    cardTint: Color? = null,
) {
    val palette = Theme.palette
    val readable = cardTint?.let { palette.readableTextOnTintedCard(it) }
    Column(
        Modifier
            .fillMaxWidth()
            .height(blockHeight)
            .padding(horizontal = horizontalInset)
            .padding(
                top = AppTheme.Layout.continueHeroMetadataVerticalPadding,
                bottom = if (includesBottomPadding) AppTheme.Layout.continueHeroMetadataExtraBottomPadding else 0.dp,
            ),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.continueHeroMetadataTitleDetailSpacing),
    ) {
        Text(
            title,
            style = IosType.headline.semibold,
            color = readable?.first ?: palette.textPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .height(AppTheme.Layout.continueHeroMetadataTitleFixedHeight)
                .clickable(onClick = onTitleTap),
        )
        LibraryRowCollapsedMetaLine(
            label = detailLabel,
            value = detailValue,
            valueMaxLines = 1,
            labelColor = readable?.second,
            valueColor = readable?.first,
            modifier = Modifier.heightIn(max = AppTheme.Layout.continueHeroMetadataDetailFixedHeight),
        )
    }
}

/**
 * iOS: `ContinueHeroPlayPillButton` — Akzent-Kapsel mit Play/Pause und Restzeit. Optimistisch:
 * der Tap schaltet sofort um und fällt nach 2,5 s auf den echten Player-Zustand zurück.
 */
@Composable
fun ContinueHeroPlayPill(itemId: String, episodeId: String?, caption: String, isFinished: Boolean) {
    val nowPlaying = rememberNowPlaying()
    AbstandPlayPill(
        isPlaying = nowPlaying.isPlaying(itemId, episodeId),
        onClick = { continueHeroPlayPillToggle(nowPlaying, itemId, episodeId, isFinished) },
        caption = caption,
        captionStyle = IosType.caption.semibold,
        horizontalPadding = AppTheme.Layout.rowSpacing,
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

/**
 * Gemeinsamer Aufbau der Hero-Karte (iOS: `ContinueListeningHeroBookCard`/`…PodcastCard`):
 * 1:1-Cover mit Tint-Letterboxing, Scrim, Fortschrittsstreifen, Typ-Pille links oben, Download-Badge
 * rechts oben; darunter Titel, Meta-Zeile und Play-Pille auf Cover-Tint.
 */
@Composable
private fun ContinueHeroCardScaffold(
    coverItemId: String,
    cardWidth: Dp,
    type: HeroMediaType,
    title: String,
    detailLabel: String,
    detailValue: String,
    progress01: Double?,
    downloadItemId: String,
    downloadEpisodeId: String?,
    onOpen: () -> Unit,
    playPill: @Composable () -> Unit,
) {
    val palette = Theme.palette
    val tint = coverTint(coverItemId)
    val download = rememberDownloadBadge(downloadItemId, downloadEpisodeId)
    val coverShape = RoundedCornerShape(topStart = AppTheme.Layout.coverCornerRadius, topEnd = AppTheme.Layout.coverCornerRadius)
    val cardShape = RoundedCornerShape(AppTheme.Layout.continueHeroCardCornerRadius)
    Column(
        Modifier
            .width(cardWidth)
            .clip(cardShape)
            .background(tint)
            .abstandHeroCardOutline(palette),
    ) {
        Box(Modifier.size(cardWidth).background(tint)) {
            CoverImage(
                itemId = coverItemId,
                contentMode = CoverImageContentMode.Fit,
                contentDescription = title,
                modifier = Modifier.fillMaxSize().clip(coverShape).clickable(onClick = onOpen),
            )
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(minOf(AppTheme.Layout.coverScrimHeight, cardWidth * 0.28f))
                    .background(AppTheme.coverScrimGradient),
            )
            if (progress01 != null) {
                AbstandCardBottomProgress(progress01, Modifier.align(Alignment.BottomCenter))
            }
            Box(Modifier.align(Alignment.TopStart)) { ContinueListeningHeroTypePill(type) }
            Box(Modifier.align(Alignment.TopEnd)) {
                AbstandCoverDownloadBadge(download.isDownloaded, download.isDownloading, download.progress)
            }
        }
        ContinueListeningHeroMetadataBlock(
            title = title,
            detailLabel = detailLabel,
            detailValue = detailValue,
            horizontalInset = AppTheme.Layout.libraryRowCardInset,
            blockHeight = AppTheme.Layout.continueHeroMetadataVerticalPadding +
                AppTheme.Layout.continueHeroMetadataTitleFixedHeight +
                AppTheme.Layout.continueHeroMetadataTitleDetailSpacing +
                AppTheme.Layout.continueHeroMetadataDetailFixedHeight,
            onTitleTap = onOpen,
            cardTint = tint,
        )
        Box(
            Modifier.padding(
                start = AppTheme.Layout.libraryRowCardInset,
                end = AppTheme.Layout.libraryRowCardInset,
                top = AppTheme.Layout.continueHeroMetadataPlayPillTopPadding,
                bottom = AppTheme.Layout.continueHeroMetadataExtraBottomPadding,
            ),
        ) { playPill() }
    }
}

/** iOS: `ContinueListeningHeroBookCard`. */
@Composable
fun ContinueListeningHeroBookCard(book: AbsBook, cardWidth: Dp) {
    val navigator = LocalTabNavigator.current
    val progress = rememberProgress(book.id)
    ContinueHeroCardScaffold(
        coverItemId = book.id,
        cardWidth = cardWidth,
        type = HeroMediaType.Audiobook,
        title = book.displayTitle,
        detailLabel = "Author",
        detailValue = ContinueHeroMath.authorLine(book),
        progress01 = ContinueHeroMath.bookProgress(progress),
        downloadItemId = book.id,
        downloadEpisodeId = null,
        onOpen = { navigator?.push(BookDetailDestination(book.id)) },
    ) {
        ContinueHeroPlayPill(
            itemId = book.id,
            episodeId = null,
            caption = formatPlaybackDurationShortHuman(ContinueHeroMath.bookRemainingSeconds(book.media.duration, progress)),
            isFinished = progress?.isFinished == true,
        )
    }
}

/** iOS: `ContinueListeningHeroPodcastCard`. */
@Composable
fun ContinueListeningHeroPodcastCard(episode: AbsPodcastEpisodeListItem, cardWidth: Dp) {
    val navigator = LocalTabNavigator.current
    val progress = rememberProgress(episode.progressLookupKey)
    ContinueHeroCardScaffold(
        coverItemId = episode.libraryItemId,
        cardWidth = cardWidth,
        type = HeroMediaType.Podcast,
        title = episode.episodeTitle,
        detailLabel = "Show",
        detailValue = episode.showTitle,
        progress01 = ContinueHeroMath.episodeProgress(episode.duration, progress),
        downloadItemId = episode.libraryItemId,
        downloadEpisodeId = episode.episodeId,
        onOpen = { navigator?.push(EpisodeDestination(episode.libraryItemId, episode.episodeId)) },
    ) {
        ContinueHeroPlayPill(
            itemId = episode.libraryItemId,
            episodeId = episode.episodeId,
            caption = formatPlaybackDurationShortHuman(ContinueHeroMath.episodeRemainingSeconds(episode.duration, progress)),
            isFinished = progress?.isFinished == true,
        )
    }
}

/**
 * iOS: `ContinueListeningHeroCarousel` — gemischte Buch-/Folgen-Karten nach `lastUpdate`; die
 * Reihenfolge wird nur neu gebaut, wenn sich die Rangfolge ändert (nicht bei jedem Tick).
 * Kartenbreite adaptiv (Compact 1½ sichtbar, Tablet +2), Reihe rastet ein (Material-Hero-Carousel).
 */
@Composable
fun ContinueListeningHeroCarousel(shelf: AbsStartShelfSection, contentPadding: PaddingValues) {
    val progress by AppModel.shared.home.progressByItemId.collectAsState()
    val merged = AbsStartShelfMergedRow.merged(shelf.books, shelf.podcastEpisodes, progress)
    val signature = merged.joinToString("\u001f") { it.id }
    val rows = remember(signature) { merged }
    val isRegular = LocalConfiguration.current.screenWidthDp >= TabletWidthDp
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val viewport = maxWidth - contentPadding.calculateLeftPadding(LayoutDirection.Ltr) -
            contentPadding.calculateRightPadding(LayoutDirection.Ltr)
        val cardWidth = AppTheme.Layout.continueHeroCardWidth(viewport, isRegular)
        val state = rememberLazyListState()
        CompositionLocalProvider(LocalAbstandCardShadowEnabled provides false) {
            LazyRow(
                state = state,
                flingBehavior = rememberSnapFlingBehavior(state),
                contentPadding = contentPadding,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
                verticalAlignment = Alignment.Top,
                modifier = Modifier.fillMaxWidth().heightIn(min = cardWidth + AppTheme.Layout.continueHeroMetadataBlockHeight),
            ) {
                items(rows, key = { it.id }) { row ->
                    when (row) {
                        is AbsStartShelfMergedRow.Book -> ContinueListeningHeroBookCard(row.book, cardWidth)
                        is AbsStartShelfMergedRow.PodcastEpisode -> ContinueListeningHeroPodcastCard(row.episode, cardWidth)
                    }
                }
            }
        }
    }
}

/** iOS: `horizontalSizeClass == .regular` ≈ ab 600 dp Breite (Tablets). */
internal const val TabletWidthDp = 600
