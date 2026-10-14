package de.letzgo.abstand.ui.browse

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsLibraryAuthorListItem
import de.letzgo.abstand.data.AbsLibraryCollectionListItem
import de.letzgo.abstand.data.AbsLibraryNarratorListItem
import de.letzgo.abstand.data.AbsLibrarySeriesListItem
import de.letzgo.abstand.data.BooksBrowseGenreListItem
import de.letzgo.abstand.data.BooksBrowseTagListItem
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.components.abstandCardChrome
import de.letzgo.abstand.ui.home.AuthorImage
import de.letzgo.abstand.ui.home.CoverPill
import de.letzgo.abstand.ui.home.LibraryRowCollapsedMetaLine
import de.letzgo.abstand.ui.home.LibraryRowLayout
import de.letzgo.abstand.ui.home.coverTint
import de.letzgo.abstand.ui.semibold

// iOS: MainRootBrowseSections.swift (+ `BrowseEntityRowCard`/`FacetBrowseTileCard` aus
// LibraryCardViews.swift) — Facetten-Sektionen des Bücher-Tabs. Zustandslos: Listen, Ladeflags und
// Aktionen kommen vom Katalog-Port herein; Suche und Katalog teilen sich die Zeilen-/Kachelkarten.

/** iOS: `BooksBrowseSection` — Unterbereiche des Bücher-Tabs (Streifen-Reihenfolge `audiobookStripOrder`). */
enum class BooksBrowseSection(val rawValue: String, val iconName: String) {
    Books("Books", "books.vertical"),
    Search("Search", "magnifyingglass"),
    Series("Series", "rectangle.stack"),
    Collections("Collections", "folder"),
    Genres("Genres", "sparkles"),
    Tags("Tags", "tag"),
    Author("Authors", "person.text.rectangle"),
    Narrators("Narrators", "waveform"),
    Ebooks("eBooks", "book.closed"),
    EbooksSupplementary("Supplementary", "books.vertical.fill");

    /** Anzeigename in der Leiste (`rawValue` bleibt die Auswahl-ID). */
    val title: String get() = if (this == Books) "Audiobooks" else rawValue

    val icon: ImageVector get() = SF.byName[iconName] ?: SF.squareGrid2x2

    companion object {
        val audiobookStripOrder = listOf(Books, Ebooks, Series, Author, Collections, Genres, Narrators, Tags)

        fun fromRaw(raw: String): BooksBrowseSection? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** iOS: `browseEntityBooksCountLine(count:)`. */
fun browseEntityBooksCountLine(count: Int?): String? = count?.takeIf { it > 0 }?.toString()

/**
 * iOS: `BrowseEntityRowCard` — Autor/Serie/Sprecher/Tag als Listenzeile: Cover links (Autor-Portrait
 * 1:1 beschnitten), Titel, optionale Autorzeile, unten „BOOKS n“.
 */
@Composable
fun BrowseEntityRowCard(
    title: String,
    detailLabel: String,
    detailValue: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    coverItemId: String? = null,
    authorImageId: String? = null,
    authorLine: String? = null,
    placeholderIcon: ImageVector = SF.booksVerticalFill,
) {
    val palette = Theme.palette
    val side = LibraryRowLayout.coverSide
    Row(
        modifier
            .fillMaxWidth()
            .height(side)
            .abstandCardChrome(palette.card, LibraryRowLayout.cardShape, onClick = onClick)
            .semantics(mergeDescendants = true) { role = Role.Button },
        horizontalArrangement = Arrangement.spacedBy(LibraryRowLayout.cardInset),
    ) {
        Box(Modifier.size(side).clip(LibraryRowLayout.coverClipShape).background(palette.card)) {
            when {
                authorImageId != null -> AuthorImage(authorImageId, Modifier.fillMaxSize())
                coverItemId != null -> SquareCoverImage(itemId = coverItemId, modifier = Modifier.fillMaxSize(), tint = coverTint(coverItemId))
                else -> Icon(placeholderIcon, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.align(Alignment.Center))
            }
        }
        Column(
            Modifier.weight(1f).fillMaxSize().padding(
                top = LibraryRowLayout.textInset, end = LibraryRowLayout.textInset, bottom = LibraryRowLayout.textInset,
            ),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
        ) {
            Text(title, style = IosType.headline.semibold, color = palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (authorLine != null) LibraryRowCollapsedMetaLine("Author", authorLine, valueMaxLines = 1)
            Spacer(Modifier.weight(1f))
            LibraryRowCollapsedMetaLine(detailLabel, detailValue)
        }
    }
}

/** iOS: `FacetBrowseTileMetrics`. */
object FacetBrowseTileMetrics {
    val tileHeight = 93.dp
    val edgeInset = AppTheme.Layout.inlineSpacing
    val iconSize = 22.dp
    val contentPadding = AppTheme.Layout.cardPadding
}

/** iOS: `FacetBrowseTileCard` — Kachel mit Akzent-Symbol, Titel unten links, „n Books“-Pille oben rechts. */
@Composable
fun FacetBrowseTileCard(kind: BooksBrowseSection, title: String, count: Int?, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val palette = Theme.palette
    Box(
        modifier
            .fillMaxWidth()
            .height(FacetBrowseTileMetrics.tileHeight)
            .abstandCardChrome(palette.card, LibraryRowLayout.cardShape, onClick = onClick)
            .semantics(mergeDescendants = true) {
                role = Role.Button
                contentDescription = if (count != null && count > 0) "${kind.rawValue}: $title, $count books" else "${kind.rawValue}: $title"
            },
    ) {
        Icon(
            kind.icon, contentDescription = null, tint = Theme.accent,
            modifier = Modifier.padding(FacetBrowseTileMetrics.contentPadding).size(FacetBrowseTileMetrics.iconSize),
        )
        Text(
            title, style = IosType.headline.semibold, color = palette.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.BottomStart).padding(FacetBrowseTileMetrics.contentPadding),
        )
        if (count != null && count > 0) {
            Box(Modifier.align(Alignment.TopEnd)) {
                CoverPill { Text("$count Books", style = IosType.caption2.semibold, color = Color.White, maxLines = 1) }
            }
        }
    }
}

/**
 * Zustand einer Facetten-Liste (iOS: `browseAuthors` + `browseAuthorsLoading`, …).
 * [isOfflineUnavailable] = `!isNetworkReachable && !offlineHomeUIActive`.
 */
data class BrowseFacetListState<T>(
    val items: List<T>,
    val isLoading: Boolean,
    val isOfflineUnavailable: Boolean = false,
)

/** Kopfzeile + Lade/Leer/Offline-Zustand; `true` = Inhalte rendern. */
private fun <T> LazyListScope.facetHeader(title: String, state: BrowseFacetListState<T>, emptyText: String): Boolean {
    item(key = "facet-title-$title") { TabContentSectionTitle(title) }
    when {
        state.isOfflineUnavailable -> item(key = "facet-offline-$title") {
            AbstandSectionEmptyState("Connect to the network to load this list.")
        }
        state.isLoading && state.items.isEmpty() -> item(key = "facet-loading-$title") { AbstandLoadingSpinner() }
        state.items.isEmpty() -> item(key = "facet-empty-$title") { AbstandSectionEmptyState(emptyText) }
        else -> return true
    }
    return false
}

/** Adaptive Kachelreihen (iOS: `LazyVGrid(.adaptive(minimum: 160))`) innerhalb einer `LazyColumn`. */
private fun <T> LazyListScope.facetTileGrid(keyPrefix: String, items: List<T>, itemKey: (T) -> String, tile: @Composable (T) -> Unit) {
    item(key = "$keyPrefix-grid") {
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val spacing = AppTheme.Layout.withinSectionSpacing
            val columns = maxOf(1, ((maxWidth + spacing) / (AppTheme.Layout.facetTileMinWidth + spacing)).toInt())
            Column(verticalArrangement = Arrangement.spacedBy(spacing)) {
                items.chunked(columns).forEach { rowItems ->
                    Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
                        rowItems.forEach { item -> Box(Modifier.weight(1f)) { key(itemKey(item)) { tile(item) } } }
                        repeat(columns - rowItems.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
}

/** iOS: `booksBrowseAuthorListBody`. [onItemShown] = Nachladen (`loadMoreBrowseAuthorsIfNeeded`). */
fun LazyListScope.booksBrowseAuthorList(
    state: BrowseFacetListState<AbsLibraryAuthorListItem>,
    onOpen: (AbsLibraryAuthorListItem) -> Unit,
    onItemShown: (AbsLibraryAuthorListItem) -> Unit = {},
) {
    if (!facetHeader("Authors", state, "No authors found.")) return
    items(state.items, key = { "author-${it.id}" }) { author ->
        LaunchedEffect(author.id) { onItemShown(author) }
        BrowseEntityRowCard(
            title = author.name,
            detailLabel = "Books",
            detailValue = browseEntityBooksCountLine(author.numBooks),
            onClick = { onOpen(author) },
            authorImageId = author.id.takeIf { author.hasAuthorImage },
            placeholderIcon = SF.personFill,
        )
    }
}

/** iOS: `booksBrowseSeriesListBody`. */
fun LazyListScope.booksBrowseSeriesList(
    state: BrowseFacetListState<AbsLibrarySeriesListItem>,
    onOpen: (AbsLibrarySeriesListItem) -> Unit,
    onItemShown: (AbsLibrarySeriesListItem) -> Unit = {},
) {
    if (!facetHeader("Series", state, "No series found.")) return
    items(state.items, key = { "series-${it.id}" }) { series ->
        LaunchedEffect(series.id) { onItemShown(series) }
        BrowseEntityRowCard(
            title = series.name,
            detailLabel = "Books",
            detailValue = browseEntityBooksCountLine(series.books?.size),
            onClick = { onOpen(series) },
            coverItemId = series.books?.firstOrNull()?.id,
            authorLine = series.cardAuthorsLine,
        )
    }
}

/** iOS: `booksBrowseNarratorListBody`. */
fun LazyListScope.booksBrowseNarratorGrid(state: BrowseFacetListState<AbsLibraryNarratorListItem>, onOpen: (AbsLibraryNarratorListItem) -> Unit) {
    if (!facetHeader("Narrators", state, "No narrators found.")) return
    facetTileGrid("narrators", state.items, { it.id }) { FacetBrowseTileCard(BooksBrowseSection.Narrators, it.name, it.numBooks, { onOpen(it) }) }
}

/** iOS: `booksBrowseCollectionsListBody`. */
fun LazyListScope.booksBrowseCollectionsGrid(state: BrowseFacetListState<AbsLibraryCollectionListItem>, onOpen: (AbsLibraryCollectionListItem) -> Unit) {
    if (!facetHeader("Collections", state, "No collections found.")) return
    facetTileGrid("collections", state.items, { it.id }) { FacetBrowseTileCard(BooksBrowseSection.Collections, it.name, it.books?.size, { onOpen(it) }) }
}

/** iOS: `booksBrowseTagsListBody`. */
fun LazyListScope.booksBrowseTagsGrid(state: BrowseFacetListState<BooksBrowseTagListItem>, onOpen: (BooksBrowseTagListItem) -> Unit) {
    if (!facetHeader("Tags", state, "No tags found.")) return
    facetTileGrid("tags", state.items, { it.id }) { FacetBrowseTileCard(BooksBrowseSection.Tags, it.name, it.numBooks, { onOpen(it) }) }
}

/** iOS: `booksBrowseGenresListBody`. */
fun LazyListScope.booksBrowseGenresGrid(state: BrowseFacetListState<BooksBrowseGenreListItem>, onOpen: (BooksBrowseGenreListItem) -> Unit) {
    if (!facetHeader("Genres", state, "No genres found.")) return
    facetTileGrid("genres", state.items, { it.id }) { FacetBrowseTileCard(BooksBrowseSection.Genres, it.name, it.numBooks, { onOpen(it) }) }
}
