package de.letzgo.abstand.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.logic.BooksBrowseSection
import de.letzgo.abstand.logic.LibraryRowLiveState
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.store.CoverImageCache
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.LocalAbstandCardShadowEnabled
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCard
import de.letzgo.abstand.ui.components.AbstandCardBottomProgress
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.CoverImageContentMode
import de.letzgo.abstand.ui.components.LibraryRowCollapsedMetaLine
import de.letzgo.abstand.ui.components.LocalCoverEnvironment
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.components.abstandCardChrome
import de.letzgo.abstand.ui.detail.BookDetailDestination
import de.letzgo.abstand.ui.formatPlaybackTime
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import de.letzgo.abstand.ui.components.AbstandCoverCornerBadge
import de.letzgo.abstand.ui.components.AbstandCoverPillMetrics
import de.letzgo.abstand.ui.components.AbstandCoverPillText
import de.letzgo.abstand.ui.components.AbstandPlayPill
import de.letzgo.abstand.ui.components.AbstandStatusBadges

/** iOS: `LibraryRowLayout` — Konstanten der Library-Zeilen. */
object LibraryRowLayout {
    val coverSide: Dp = AppTheme.Layout.libraryRowCoverSide
    /** M3-Karten: alle Karten 12 dp ([AppTheme.Layout.cardCornerRadius]). */
    val cornerRadius: Dp = AppTheme.Layout.cardCornerRadius
    val cardInset: Dp = AppTheme.Layout.libraryRowCardInset
    val textInset: Dp = AppTheme.Layout.libraryRowTextInset
    val cardShape = RoundedCornerShape(cornerRadius)
    val coverClipShape = RoundedCornerShape(topStart = cornerRadius, bottomStart = cornerRadius)

    fun bodyBottomInset(showsProgressBar: Boolean): Dp =
        if (showsProgressBar) textInset + AppTheme.Layout.libraryRowBottomProgressHeight else textInset
}

/** iOS: `FacetBrowseTileMetrics`. */
private object FacetTileMetrics {
    val tileHeight = 96.dp
    val iconSize = AppTheme.Layout.iconSize
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


/**
 * iOS: `LibraryRowPlayPill` — Akzent-Kapsel Play/Pause rechts unten in kompakten Zeilen; schaltet
 * beim Tippen sofort optimistisch um und fällt nach 2,5 s auf den echten Zustand zurück.
 */
@Composable
fun LibraryRowPlayPill(libraryItemId: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    AbstandPlayPill(rememberIsPlayingMedia(libraryItemId), onClick, modifier)
}

// MARK: - Kompakte Buch-Zeile

/**
 * iOS: `BookRowCard` — kompakte Zeile: Cover 1:1 links, Titel + Status oben, Autor, Laufzeit/
 * Lesefortschritt unten links, Play-Pille unten rechts; Fortschrittsstreifen am Kartenfuß.
 * M3 Filled Card (ohne Schatten und ohne Rand); Tipp öffnet das Detail. Beendet: Cover und
 * Play-Pille mit [AppTheme.disabledContentAlpha], Titel in `onSurfaceVariant`.
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
    val fade = if (isFinished) AppTheme.disabledContentAlpha else 1f
    val titleColor = if (isFinished) palette.textSecondary else palette.textPrimary
    val supplementaryBadge = showEbookBadge || AppModel.shared.catalog.bookShowsSupplementaryEbookBadge(book)
    val revision = coverRevisionFor(book.updatedAt)

    CompositionLocalProvider(LocalAbstandCardShadowEnabled provides false) {
        AbstandCard(
            modifier = modifier.fillMaxWidth(),
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
                        if (isPureEbook) AbstandCoverCornerBadge(SF.bookClosedFill, null, Modifier.align(Alignment.BottomStart))
                        if (supplementaryBadge) AbstandCoverCornerBadge(SF.bookClosedFill, "eBook available", Modifier.align(Alignment.BottomEnd))
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
                                book.displayTitle, style = AppType.titleMedium, color = titleColor, maxLines = 1,
                                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                            )
                            AbstandStatusBadges(
                                isFinished = isFinished,
                                isDownloaded = showsDownloadStatus && live.isDownloaded,
                                isDownloading = showsDownloadStatus && live.isDownloading,
                                downloadProgress = live.downloadProgress,
                            )
                        }
                        LibraryRowCollapsedMetaLine("Author", book.displayAuthorsCardLine, valueMaxLines = 1, valueColor = if (isFinished) titleColor else null)
                        Spacer(Modifier.weight(1f))
                        Row(verticalAlignment = Alignment.Bottom) {
                            Box(Modifier.weight(1f)) {
                                val label = if (ebookMetrics) LibraryRowLiveState.ebookProgressLabel(live.ebookFraction)
                                else formatPlaybackTime(book.media.duration ?: 0.0)
                                if (label != null) {
                                    Text(label, style = AppType.bodyMedium, color = palette.textSecondary, maxLines = 1)
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

/**
 * iOS: `LibraryBookListCard` — auf Android immer die kompakte Zeile ([BookRowCard]); die
 * iOS-Kartenstil-Auswahl (`libraryBookCardStyle`) gibt es hier nicht.
 */
@Composable
fun LibraryBookListCard(
    book: AbsBook,
    modifier: Modifier = Modifier,
    showEbookBadge: Boolean = false,
    usesEbookProgressDisplay: Boolean = false,
    usesSquareCenterCropCover: Boolean = false,
    showsPlaybackControls: Boolean = true,
) {
    BookRowCard(
        book, modifier, showEbookBadge = showEbookBadge, usesSquareCenterCropCover = usesSquareCenterCropCover,
        usesEbookProgressDisplay = usesEbookProgressDisplay, showsPlaybackControls = showsPlaybackControls,
    )
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
    authorImageId: String? = null,
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
                authorImageId != null -> de.letzgo.abstand.ui.home.AuthorImage(authorImageId, Modifier.fillMaxSize())
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
                else -> Icon(placeholderIcon, null, tint = palette.textSecondary, modifier = Modifier.align(Alignment.Center).size(EntityPlaceholderIconSize))
            }
        }
        Column(
            Modifier.weight(1f).fillMaxSize().padding(top = LibraryRowLayout.textInset, end = LibraryRowLayout.textInset, bottom = LibraryRowLayout.textInset),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
        ) {
            Text(title, style = AppType.titleMedium, color = palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (authorLine != null) LibraryRowCollapsedMetaLine("Author", authorLine, valueMaxLines = 1)
            Spacer(Modifier.weight(1f))
            LibraryRowCollapsedMetaLine(detailLabel, detailValue, valueMaxLines = 1)
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
            Icon(kind.icon, null, tint = Theme.accent, modifier = Modifier.padding(AbstandCoverPillMetrics.inset).size(FacetTileMetrics.iconSize))
            Text(
                title, style = AppType.titleMedium, color = palette.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.align(Alignment.BottomStart).padding(AppTheme.Layout.cardPadding),
            )
            if (count != null && count > 0) {
                AbstandCoverPillText("$count Books", Modifier.align(Alignment.TopEnd))
            }
        }
    }
}

/** Cache-Scope eines Autorenfotos (iOS: `author:<id>`). */
fun authorCoverScopeId(authorId: String): String = CoverImageCache.scopeId("author:$authorId", CoverImageTier.thumbnail)

/** Status-Symbole auf Hero-Karten (iOS: `.caption`). */
/** Platzhalter-Symbol in Entity-Zeilen ohne Cover. */
private val EntityPlaceholderIconSize = 36.dp
