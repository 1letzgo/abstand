package de.letzgo.abstand.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.logic.BookDetailLogic
import de.letzgo.abstand.logic.BooksBrowseSection
import de.letzgo.abstand.logic.LibraryRowLiveState
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.LibraryBookCardStyle
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.store.CoverImageCache
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.LocalAbstandCardShadowEnabled
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCard
import de.letzgo.abstand.ui.components.AbstandCardBottomProgress
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.CoverImageContentMode
import de.letzgo.abstand.ui.components.LocalCoverEnvironment
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.components.abstandCardChrome
import de.letzgo.abstand.ui.detail.BookDetailDestination
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

/** iOS: `LibraryRowLayout` — Konstanten der Library-Zeilen. */
object LibraryRowLayout {
    val coverSide: Dp = AppTheme.Layout.libraryRowCoverSide
    val cornerRadius: Dp = AppTheme.Layout.continueHeroCardCornerRadius
    val cardInset: Dp = AppTheme.Layout.libraryRowCardInset
    val textInset: Dp = AppTheme.Layout.libraryRowTextInset
    /** Beendete Titel: Cover/Text/Play zurückgenommen (Download-Status bleibt voll). */
    const val finishedContentOpacity: Float = 0.35f
    val cardShape = RoundedCornerShape(cornerRadius)
    val coverClipShape = RoundedCornerShape(topStart = cornerRadius, bottomStart = cornerRadius)

    fun bodyBottomInset(showsProgressBar: Boolean): Dp =
        if (showsProgressBar) textInset + AppTheme.Layout.libraryRowBottomProgressHeight else textInset
}

/** iOS: `ContinueListeningHeroCoverPillMetrics`. */
private object CoverPillMetrics {
    val inset = 8.dp
    val iconSize = 12.dp
    val spinnerSize = 13.dp
}

/** iOS: `FacetBrowseTileMetrics`. */
private object FacetTileMetrics {
    val tileHeight = 93.dp
    val iconSize = 22.dp
}

/** Cover-Revision wie iOS `coverImageCacheRevision(forItemUpdatedAt:)` (globaler Zähler + `updatedAt`-Sekunden). */
@Composable
fun coverRevisionFor(updatedAtMs: Long?): Int {
    val base = LocalCoverEnvironment.current.revision
    return if (updatedAtMs == null) base else base + (updatedAtMs / 1000).toInt()
}

/** Buch-Detail im aktuellen Tab öffnen (iOS: `navigationDestination(isPresented:) { BookDetailView }`). */
@Composable
fun rememberOpenBookDetail(): (String) -> Unit {
    val navigator = LocalTabNavigator.current
    return remember(navigator) { { id: String -> navigator?.push(BookDetailDestination(id)) } }
}

/** iOS: `LibraryBookRowLiveState` — Fortschritt, eBook-Anteil, Download-Status einer Zeile. */
data class BookRowLive(
    val progress: AbsUserMediaProgress?,
    val ebookFraction: Double?,
    val isDownloaded: Boolean,
    val isDownloading: Boolean,
    val isQueued: Boolean,
    val downloadProgress: Double,
)

/** Gezielte Beobachtung je Zeile (nicht die ganze Progress-Map) — iOS-Performance-Regel für Lazy-Listen. */
@Composable
fun rememberBookRowLive(bookId: String, model: AppModel = AppModel.shared): BookRowLive {
    val flow = remember(bookId) {
        val progressFlow = model.progress.progressByItemId.map { it[bookId] }.distinctUntilChanged()
        val downloadFlow = combine(
            DownloadManager.activeItemId, DownloadManager.progress, DownloadManager.queuedItemIds, model.catalog.downloadedItemIds,
        ) { active, prog, queued, downloaded ->
            val state = LibraryRowLiveState.bookDownloadState(bookId, null, active, prog, queued)
            Triple(state, bookId in downloaded, prog)
        }.distinctUntilChanged()
        combine(progressFlow, downloadFlow) { p, (state, downloaded, _) ->
            BookRowLive(
                progress = p,
                ebookFraction = model.progress.ebookDisplayProgressFraction(bookId),
                isDownloaded = downloaded,
                isDownloading = state.isDownloading,
                isQueued = state.isQueued,
                downloadProgress = state.downloadProgress,
            )
        }
    }
    val initial = remember(bookId) {
        BookRowLive(model.progress.progress(bookId), model.progress.ebookDisplayProgressFraction(bookId), bookId in model.catalog.downloadedItemIds.value, false, false, 0.0)
    }
    return flow.collectAsState(initial).value
}

/** „Spielt dieser Titel gerade?" — Player-Identität + `isPlaying` (iOS: `playbackActivePublisher`). */
@Composable
fun rememberIsPlayingMedia(libraryItemId: String, episodeId: String? = null): Boolean {
    val context = LocalContext.current
    val player = remember { PlaybackController.shared(context) }
    val active by player.activeBook.collectAsState()
    val ep by player.activePlaybackEpisodeId.collectAsState()
    val playing by player.isPlaying.collectAsState()
    return playing && active?.id == libraryItemId && ep.orEmpty().trim() == episodeId.orEmpty().trim()
}

// MARK: - Kleine Bausteine

/** iOS: `LibraryRowCollapsedMetaLine` — „AUTHOR  Name" (Label in Versalien). */
@Composable
fun LibraryRowCollapsedMetaLine(
    label: String,
    value: String?,
    modifier: Modifier = Modifier,
    valueLineLimit: Int = 2,
    labelColor: Color? = null,
    valueColor: Color? = null,
) {
    val palette = Theme.palette
    val line = value?.trim().orEmpty()
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
        Text(label.uppercase(), style = IosType.footnote.semibold, color = labelColor ?: palette.textSecondary, maxLines = 1)
        if (line.isEmpty() || line == "—") {
            Text("—", style = IosType.footnote, color = labelColor ?: palette.textSecondary, modifier = Modifier.weight(1f))
        } else {
            Text(
                line, style = IosType.footnote, color = valueColor ?: palette.textPrimary, maxLines = valueLineLimit,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
        }
    }
}

/** iOS: `ContinueListeningHeroCoverPill` — dunkle Kapsel auf Covern (Typ, Download, Anzahl). */
@Composable
fun CoverPill(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier
            .padding(CoverPillMetrics.inset)
            .background(Theme.palette.coverPlayBadgeBackground, CircleShape)
            .padding(horizontal = AppTheme.Layout.compactSpacing, vertical = AppTheme.Layout.pillVerticalPadding),
        contentAlignment = Alignment.Center,
    ) { content() }
}

/** Weißes Symbol in einer [CoverPill] (bewusst Weiß: liegt auf der dunklen Kapsel). */
@Composable
fun CoverPillIcon(icon: ImageVector, description: String?, modifier: Modifier = Modifier) {
    CoverPill(modifier) { Icon(icon, contentDescription = description, tint = Color.White, modifier = Modifier.size(CoverPillMetrics.iconSize)) }
}

/** iOS: `ContinueListeningHeroOfflineBadge` — fertig/aktiver Download oben rechts auf dem Cover. */
@Composable
fun CoverOfflineBadge(isDownloaded: Boolean, isDownloading: Boolean, downloadProgress: Double) {
    when {
        isDownloaded -> CoverPillIcon(SF.arrowDownCircleFill, "Downloaded")
        isDownloading -> CoverPill {
            CircularProgressIndicator(
                progress = { downloadProgress.toFloat().coerceIn(0f, 1f) },
                color = Color.White, strokeWidth = 2.dp, trackColor = Color.White.copy(alpha = 0.3f),
                modifier = Modifier.size(CoverPillMetrics.spinnerSize).semantics { contentDescription = "Downloading" },
            )
        }
    }
}

/** iOS: `LibraryCoverCornerBadge` — kleiner runder Badge unten auf Listen-Covern (eBook). */
@Composable
private fun CoverCornerBadge(icon: ImageVector, description: String?, modifier: Modifier = Modifier) {
    Box(
        modifier.padding(AppTheme.Layout.tightSpacing).size(AppTheme.Layout.coverBadgeSize)
            .background(Theme.palette.coverPlayBadgeBackground, CircleShape),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, contentDescription = description, tint = Color.White, modifier = Modifier.size(11.dp)) }
}

/** iOS: `LibraryRowStatusBadges` — „fertig" + Download-Status oben rechts in kompakten Zeilen. */
@Composable
private fun LibraryRowStatusBadges(isFinished: Boolean, isDownloaded: Boolean, isDownloading: Boolean, downloadProgress: Double) {
    val color = Theme.palette.textSecondary
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing), verticalAlignment = Alignment.CenterVertically) {
        if (isFinished) {
            Icon(SF.checkmarkCircleFill, "Finished", tint = color, modifier = Modifier.size(14.dp).alpha(LibraryRowLayout.finishedContentOpacity))
        }
        if (isDownloaded) {
            Icon(SF.arrowDownCircleFill, "Saved offline", tint = color, modifier = Modifier.size(14.dp))
        } else if (isDownloading) {
            LinearProgressIndicator(
                progress = { downloadProgress.toFloat() }, color = color, trackColor = color.copy(alpha = 0.2f),
                modifier = Modifier.width(AppTheme.Layout.compactIconButtonSize).semantics { contentDescription = "Downloading" },
            )
        }
    }
}

/**
 * iOS: `LibraryRowPlayPill` — Akzent-Kapsel Play/Pause rechts unten in kompakten Zeilen; schaltet
 * beim Tippen sofort optimistisch um und fällt nach 2,5 s auf den echten Zustand zurück.
 */
@Composable
fun LibraryRowPlayPill(libraryItemId: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val isPlaying = rememberIsPlayingMedia(libraryItemId)
    var optimistic by remember(libraryItemId) { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(isPlaying) { optimistic = null }
    LaunchedEffect(optimistic) {
        if (optimistic != null) {
            delay(2_500)
            optimistic = null
        }
    }
    val showsPause = optimistic ?: isPlaying
    Surface(
        onClick = {
            optimistic = !showsPause
            onClick()
        },
        shape = CircleShape,
        color = Theme.accent,
        contentColor = Theme.onAccent,
        modifier = modifier,
    ) {
        Icon(
            if (showsPause) SF.pauseFill else SF.playFill,
            contentDescription = if (showsPause) "Pause" else "Play",
            modifier = Modifier.padding(horizontal = AppTheme.Layout.cardPadding, vertical = AppTheme.Layout.stackSpacing).size(14.dp),
        )
    }
}

/** iOS: `ContinueHeroPlayPillButton` — Play-Pille mit Restzeit unter Cover-Karten. */
@Composable
private fun HeroPlayPill(libraryItemId: String, caption: String, onClick: () -> Unit) {
    val isPlaying = rememberIsPlayingMedia(libraryItemId)
    var optimistic by remember(libraryItemId) { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(isPlaying) { optimistic = null }
    LaunchedEffect(optimistic) {
        if (optimistic != null) {
            delay(2_500)
            optimistic = null
        }
    }
    val showsPause = optimistic ?: isPlaying
    Surface(
        onClick = {
            optimistic = !showsPause
            onClick()
        },
        shape = CircleShape,
        color = Theme.accent,
        contentColor = Theme.onAccent,
        modifier = Modifier.height(AppTheme.Layout.continueHeroMetadataPlayPillIntrinsicHeight),
    ) {
        Row(
            Modifier.padding(horizontal = AppTheme.Layout.cardPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing),
        ) {
            Icon(if (showsPause) SF.pauseFill else SF.playFill, contentDescription = if (showsPause) "Pause" else "Play", modifier = Modifier.size(14.dp))
            Text(caption, style = IosType.subheadline.semibold, maxLines = 1)
        }
    }
}

// MARK: - Kompakte Buch-Zeile

/**
 * iOS: `BookRowCard` — kompakte Zeile: Cover 1:1 links, Titel + Status oben, Autor, Laufzeit/
 * Lesefortschritt unten links, Play-Pille unten rechts; Fortschrittsstreifen am Kartenfuß.
 * Karte ohne Schatten, mit dezenter Kante (wie iOS); Tipp öffnet das Detail.
 */
@Composable
fun BookRowCard(
    book: AbsBook,
    modifier: Modifier = Modifier,
    showEbookBadge: Boolean = false,
    showsPlaybackControls: Boolean = true,
    showsDownloadStatus: Boolean = true,
    usesSquareCenterCropCover: Boolean = false,
    usesEbookProgressDisplay: Boolean = false,
    onOpen: (() -> Unit)? = rememberOpenBookDetail().let { open -> { open(book.id) } },
) {
    val context = LocalContext.current
    val palette = Theme.palette
    val live = rememberBookRowLive(book.id)
    val isPureEbook = book.isPureEbookLibraryItem
    val ebookMetrics = isPureEbook || usesEbookProgressDisplay
    val prog = live.progress
    val showsBar = if (ebookMetrics) live.ebookFraction?.let { it > 0.005 && it < 0.995 } == true
    else prog != null && !prog.isFinished && prog.duration > 0
    val barValue = if (ebookMetrics) live.ebookFraction ?: 0.0 else if (prog != null && prog.duration > 0) prog.progress else 0.0
    val isFinished = if (ebookMetrics) (live.ebookFraction ?: 0.0) >= 0.995 else prog?.isFinished == true
    val fade = if (isFinished) LibraryRowLayout.finishedContentOpacity else 1f
    val supplementaryBadge = showEbookBadge || AppModel.shared.catalog.bookShowsSupplementaryEbookBadge(book)
    val revision = coverRevisionFor(book.updatedAt)

    CompositionLocalProvider(LocalAbstandCardShadowEnabled provides false) {
        AbstandCard(
            modifier = modifier.fillMaxWidth().border(AppTheme.Layout.hairlineWidth, palette.textSecondary.copy(alpha = 0.22f), LibraryRowLayout.cardShape),
            shape = LibraryRowLayout.cardShape,
            onClick = onOpen,
        ) {
            Box(Modifier.fillMaxWidth().height(LibraryRowLayout.coverSide)) {
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(LibraryRowLayout.cardInset)) {
                    Box(Modifier.size(LibraryRowLayout.coverSide).clip(LibraryRowLayout.coverClipShape).alpha(fade)) {
                        if (usesSquareCenterCropCover) {
                            CoverImage(itemId = book.id, cacheRevision = revision, modifier = Modifier.fillMaxSize())
                        } else {
                            SquareCoverImage(itemId = book.id, cacheRevision = revision, modifier = Modifier.fillMaxSize())
                        }
                        if (isPureEbook) CoverCornerBadge(SF.bookClosedFill, null, Modifier.align(Alignment.BottomStart))
                        if (supplementaryBadge) CoverCornerBadge(SF.bookClosedFill, "eBook available", Modifier.align(Alignment.BottomEnd))
                    }
                    Column(
                        Modifier.weight(1f).fillMaxSize().padding(
                            top = LibraryRowLayout.textInset,
                            end = LibraryRowLayout.textInset + AppTheme.Layout.tightSpacing,
                            bottom = LibraryRowLayout.bodyBottomInset(showsBar),
                        ),
                        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
                            Text(
                                book.displayTitle, style = IosType.headline.semibold, color = palette.textPrimary, maxLines = 1,
                                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).alpha(fade),
                            )
                            LibraryRowStatusBadges(
                                isFinished = isFinished,
                                isDownloaded = showsDownloadStatus && live.isDownloaded,
                                isDownloading = showsDownloadStatus && live.isDownloading,
                                downloadProgress = live.downloadProgress,
                            )
                        }
                        LibraryRowCollapsedMetaLine("Author", book.displayAuthorsCardLine, Modifier.alpha(fade))
                        Spacer(Modifier.weight(1f))
                        Row(verticalAlignment = Alignment.Bottom) {
                            Box(Modifier.weight(1f).alpha(fade)) {
                                val label = if (ebookMetrics) LibraryRowLiveState.ebookProgressLabel(live.ebookFraction)
                                else formatPlaybackTime(book.media.duration ?: 0.0)
                                if (label != null) {
                                    Text(label, style = IosType.subheadline.copy(fontFamily = FontFamily.Default), color = palette.textSecondary, maxLines = 1)
                                }
                            }
                            if (showsPlaybackControls && book.isPlayableAudiobook && !ebookMetrics) {
                                LibraryRowPlayPill(
                                    libraryItemId = book.id,
                                    onClick = { LibraryPlayback.toggle(context, book, prog?.isFinished == true) },
                                    modifier = Modifier.alpha(fade),
                                )
                            }
                        }
                    }
                }
                if (showsBar) {
                    AbstandCardBottomProgress(barValue, Modifier.align(Alignment.BottomCenter))
                }
            }
        }
    }
}

// MARK: - Cover-Karte (Raster)

/**
 * iOS: `LibraryHeroBookRowCard` — Cover-Karte im Continue-Hero-Stil: 1:1-Cover mit Scrim und
 * Fortschritt, Typ-/Fertig-/eBook-/Download-Pillen; darunter Titel, Autor und Play-Pille mit
 * Restlaufzeit (eBooks: Lesefortschritt + Download-Status).
 */
@Composable
fun LibraryHeroBookCard(
    book: AbsBook,
    modifier: Modifier = Modifier,
    showEbookBadge: Boolean = false,
    usesEbookProgressDisplay: Boolean = false,
    showsDownloadStatus: Boolean = true,
    onOpen: (() -> Unit)? = rememberOpenBookDetail().let { open -> { open(book.id) } },
) {
    val context = LocalContext.current
    val palette = Theme.palette
    val live = rememberBookRowLive(book.id)
    val ebookMetrics = book.isPureEbookLibraryItem || usesEbookProgressDisplay
    val prog = live.progress
    val heroProgress: Double? = if (ebookMetrics) live.ebookFraction?.takeIf { it > 0.005 && it < 0.995 }
    else prog?.takeIf { !it.isFinished && it.duration > 0 }?.progress?.coerceIn(0.0, 1.0)
    val isFinished = if (ebookMetrics) (live.ebookFraction ?: 0.0) >= 0.995 else prog?.isFinished == true
    val fade = if (isFinished) LibraryRowLayout.finishedContentOpacity else 1f
    val supplementaryBadge = showEbookBadge || AppModel.shared.catalog.bookShowsSupplementaryEbookBadge(book)
    val inset = AppTheme.Layout.libraryRowCardInset
    val outer = RoundedCornerShape(AppTheme.Layout.continueHeroCardCornerRadius)
    val coverTop = RoundedCornerShape(topStart = AppTheme.Layout.coverCornerRadius, topEnd = AppTheme.Layout.coverCornerRadius)
    val authorLine = book.displayAuthorsCardLine.trim().ifEmpty { "—" }
    val totalDuration = maxOf(book.media.duration ?: 0.0, prog?.duration ?: 0.0)

    CompositionLocalProvider(LocalAbstandCardShadowEnabled provides false) {
        AbstandCard(
            modifier = modifier.fillMaxWidth().border(AppTheme.Layout.hairlineWidth, palette.textSecondary.copy(alpha = 0.22f), outer),
            shape = outer,
            onClick = onOpen,
        ) {
            Box(Modifier.fillMaxWidth().aspectRatio(1f).clip(coverTop)) {
                SquareCoverImage(itemId = book.id, cacheRevision = coverRevisionFor(book.updatedAt), modifier = Modifier.fillMaxSize().alpha(fade))
                Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(AppTheme.Layout.coverScrimHeight).background(AppTheme.coverScrimGradient))
                if (heroProgress != null) {
                    AbstandCardBottomProgress(heroProgress, Modifier.align(Alignment.BottomCenter))
                }
                if (book.isPureEbookLibraryItem) CoverPillIcon(SF.bookClosedFill, "eBook", Modifier.align(Alignment.TopStart))
                Row(Modifier.align(Alignment.TopEnd)) {
                    if (isFinished) CoverPillIcon(SF.checkmarkCircleFill, "Finished", Modifier.alpha(LibraryRowLayout.finishedContentOpacity))
                    if (supplementaryBadge) CoverPillIcon(SF.bookClosedFill, "eBook available")
                    if (showsDownloadStatus) CoverOfflineBadge(live.isDownloaded, live.isDownloading, live.downloadProgress)
                }
            }
            Column(
                Modifier.fillMaxWidth().alpha(fade).padding(
                    start = inset, end = inset,
                    top = AppTheme.Layout.continueHeroMetadataVerticalPadding,
                    bottom = AppTheme.Layout.continueHeroMetadataExtraBottomPadding,
                ),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.continueHeroMetadataTitleDetailSpacing),
            ) {
                Text(
                    book.displayTitle, style = IosType.headline.semibold, color = palette.textPrimary, maxLines = 2,
                    minLines = 2, overflow = TextOverflow.Ellipsis,
                )
                LibraryRowCollapsedMetaLine("Author", authorLine, valueLineLimit = 1)
                if (book.isPlayableAudiobook) {
                    Box(Modifier.padding(top = AppTheme.Layout.continueHeroMetadataPlayPillTopPadding)) {
                        HeroPlayPill(book.id, BookDetailLogic.remainingCaption(totalDuration, prog)) {
                            LibraryPlayback.toggle(context, book, prog?.isFinished == true)
                        }
                    }
                } else {
                    Row(Modifier.padding(top = AppTheme.Layout.continueHeroMetadataPlayPillTopPadding), verticalAlignment = Alignment.CenterVertically) {
                        val label = if (ebookMetrics) LibraryRowLiveState.ebookProgressLabel(live.ebookFraction) ?: formatPlaybackTime(0.0)
                        else formatPlaybackTime(totalDuration)
                        Text(label, style = IosType.subheadline, color = palette.textSecondary, modifier = Modifier.weight(1f))
                        if (isFinished) Icon(SF.checkmarkCircleFill, "Finished", tint = Theme.accent, modifier = Modifier.size(14.dp))
                        if (showsDownloadStatus && live.isDownloaded) {
                            Icon(SF.arrowDownCircleFill, "Saved offline", tint = Theme.accent, modifier = Modifier.size(14.dp))
                        }
                    }
                }
            }
        }
    }
}

/**
 * iOS: `LibraryBookListCard` — kompakte Zeile oder Cover-Karte nach `libraryBookCardStyle`
 * ([forceCompact]: Autor-/Serien-Detail, Downloads).
 */
@Composable
fun LibraryBookListCard(
    book: AbsBook,
    style: LibraryBookCardStyle,
    modifier: Modifier = Modifier,
    showEbookBadge: Boolean = false,
    usesEbookProgressDisplay: Boolean = false,
    forceCompact: Boolean = false,
    usesSquareCenterCropCover: Boolean = false,
    showsPlaybackControls: Boolean = true,
) {
    if (!forceCompact && style == LibraryBookCardStyle.heroCover) {
        LibraryHeroBookCard(book, modifier, showEbookBadge = showEbookBadge, usesEbookProgressDisplay = usesEbookProgressDisplay)
    } else {
        BookRowCard(
            book, modifier, showEbookBadge = showEbookBadge, usesSquareCenterCropCover = usesSquareCenterCropCover,
            usesEbookProgressDisplay = usesEbookProgressDisplay, showsPlaybackControls = showsPlaybackControls,
        )
    }
}

/** iOS: `LibraryHeroMultiColumnRows` — Spaltenzahl; Tablets (≥ 600 dp) bekommen zwei Spalten mehr. */
@Composable
fun libraryGridColumns(style: LibraryBookCardStyle): Int {
    val wide = LocalConfiguration.current.screenWidthDp >= 600
    val base = maxOf(1, style.phoneGridColumns)
    return if (wide && style.usesMultiColumnGrid) base + 2 else base
}

/** Eine Rasterzeile mit [columns] gleich breiten Zellen (leere Zellen füllen auf). */
@Composable
fun <T> LibraryGridRow(items: List<T>, columns: Int, spacing: Dp = AppTheme.Layout.withinSectionSpacing, card: @Composable (T) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(spacing), verticalAlignment = Alignment.Top) {
        for (i in 0 until columns) {
            Box(Modifier.weight(1f)) { items.getOrNull(i)?.let { card(it) } }
        }
    }
}

// MARK: - Browse-Karten

/** iOS: `SeriesMultiCoverView` — 2–4 Mini-Cover im Cover-Slot (2×2). */
@Composable
private fun SeriesMultiCover(bookIds: List<String>, modifier: Modifier = Modifier) {
    val ids = bookIds.take(4)
    val gap = 1.dp
    @Composable
    fun tile(id: String?, m: Modifier) {
        Box(m) { if (id != null) SquareCoverImage(itemId = id, modifier = Modifier.fillMaxSize()) }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(gap)) {
        if (ids.size == 2) {
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(gap)) {
                tile(ids[0], Modifier.weight(1f).fillMaxSize())
                tile(ids[1], Modifier.weight(1f).fillMaxSize())
            }
        } else {
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap)) {
                tile(ids.getOrNull(0), Modifier.weight(1f).fillMaxSize())
                tile(ids.getOrNull(1), Modifier.weight(1f).fillMaxSize())
            }
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap)) {
                tile(ids.getOrNull(2), Modifier.weight(1f).fillMaxSize())
                tile(ids.getOrNull(3), Modifier.weight(1f).fillMaxSize())
            }
        }
    }
}

/**
 * iOS: `BrowseEntityRowCard` — Autoren-/Serien-Zeile im Layout der Buch-Zeile: Cover links (Autor:
 * Foto mittig beschnitten; Serie: bis zu vier Cover), Titel, optional Autorzeile, unten „BOOKS n".
 */
@Composable
fun BrowseEntityRowCard(
    title: String,
    detailLabel: String,
    detailValue: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    coverItemId: String? = null,
    coverUrl: String? = null,
    coverCacheScopeId: String? = null,
    coverBookIds: List<String>? = null,
    authorLine: String? = null,
    usesSquareCenterCropCover: Boolean = false,
    placeholderIcon: ImageVector = SF.personCropCircle,
) {
    val palette = Theme.palette
    Row(
        modifier.fillMaxWidth().height(LibraryRowLayout.coverSide)
            .abstandCardChrome(palette.card, LibraryRowLayout.cardShape, onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(LibraryRowLayout.cardInset),
    ) {
        Box(Modifier.size(LibraryRowLayout.coverSide).clip(LibraryRowLayout.coverClipShape).background(palette.card)) {
            when {
                coverBookIds != null && coverBookIds.size > 1 -> SeriesMultiCover(coverBookIds, Modifier.fillMaxSize())
                coverUrl != null && coverCacheScopeId != null -> CoverImage(
                    url = coverUrl, cacheScopeId = coverCacheScopeId, cacheRevision = LocalCoverEnvironment.current.revision,
                    contentMode = if (usesSquareCenterCropCover) CoverImageContentMode.Fill else CoverImageContentMode.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
                coverItemId != null -> if (usesSquareCenterCropCover) {
                    CoverImage(itemId = coverItemId, modifier = Modifier.fillMaxSize())
                } else {
                    SquareCoverImage(itemId = coverItemId, modifier = Modifier.fillMaxSize())
                }
                else -> Icon(placeholderIcon, null, tint = palette.textSecondary, modifier = Modifier.align(Alignment.Center).size(36.dp))
            }
        }
        Column(
            Modifier.weight(1f).fillMaxSize().padding(top = LibraryRowLayout.textInset, end = LibraryRowLayout.textInset, bottom = LibraryRowLayout.textInset),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
        ) {
            Text(title, style = IosType.headline.semibold, color = palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (authorLine != null) LibraryRowCollapsedMetaLine("Author", authorLine, valueLineLimit = 1)
            Spacer(Modifier.weight(1f))
            LibraryRowCollapsedMetaLine(detailLabel, detailValue)
        }
    }
}

/** Symbol einer Browse-Sektion (iOS: `BooksBrowseSection.systemImage`). */
val BooksBrowseSection.icon: ImageVector get() = SF.named(systemImage) ?: SF.booksVertical

/**
 * iOS: `FacetBrowseTileCard` — Kachel (Sprecher, Sammlung, Genre, Tag): Symbol oben links, Titel
 * unten, „n Books"-Pille oben rechts. Feste Höhe 93 dp (Raster-Mathematik).
 */
@Composable
fun FacetBrowseTileCard(kind: BooksBrowseSection, title: String, count: Int?, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val palette = Theme.palette
    val label = if (count != null && count > 0) "${kind.rawValue}: $title, $count books" else "${kind.rawValue}: $title"
    AbstandCard(
        modifier = modifier.fillMaxWidth().height(FacetTileMetrics.tileHeight).semantics { contentDescription = label },
        shape = LibraryRowLayout.cardShape,
        onClick = onClick,
    ) {
        Box(Modifier.fillMaxSize()) {
            Icon(kind.icon, null, tint = Theme.accent, modifier = Modifier.padding(CoverPillMetrics.inset).size(FacetTileMetrics.iconSize))
            Text(
                title, style = IosType.headline.semibold, color = palette.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.align(Alignment.BottomStart).padding(AppTheme.Layout.cardPadding),
            )
            if (count != null && count > 0) {
                CoverPill(Modifier.align(Alignment.TopEnd)) {
                    Text("$count Books", style = IosType.caption2.semibold, color = Color.White, maxLines = 1)
                }
            }
        }
    }
}

/** Cache-Scope eines Autorenfotos (iOS: `author:<id>`). */
fun authorCoverScopeId(authorId: String): String = CoverImageCache.scopeId("author:$authorId", CoverImageTier.thumbnail)
