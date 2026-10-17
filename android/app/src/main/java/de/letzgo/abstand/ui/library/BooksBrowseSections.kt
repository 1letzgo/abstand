package de.letzgo.abstand.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.logic.BooksBrowseSection
import de.letzgo.abstand.logic.BooksEntityDetailNav
import de.letzgo.abstand.logic.CatalogLogic
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.CatalogFilterState
import de.letzgo.abstand.model.CatalogStore
import de.letzgo.abstand.model.BrowseListsState
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.model.LibraryBookCardStyle
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.detail.AuthorDetailDestination
import de.letzgo.abstand.ui.detail.CollectionDetailDestination
import de.letzgo.abstand.ui.detail.FacetFilteredBooksDestination
import de.letzgo.abstand.ui.detail.NarratorDetailDestination
import de.letzgo.abstand.ui.detail.SeriesDetailDestination
import de.letzgo.abstand.ui.components.AbstandTextButton

/** Kachel einer Facetten-Sektion (Sprecher, Sammlung, Genre, Tag). */
private data class FacetTile(val key: String, val title: String, val count: Int?, val open: () -> Unit)

/**
 * Zustand des Bücher-Sektionsinhalts (iOS: Quellen von `booksCatalogBookListBody`,
 * `booksEbookListBody`, `MainRootBrowseSections`) — gesammelt von [rememberBooksBrowseSectionContent],
 * gerendert von [booksBrowseSectionItems].
 */
internal class BooksBrowseSectionContent(
    val section: BooksBrowseSection,
    val catalog: CatalogStore,
    val books: List<AbsBook>,
    val loading: Boolean,
    val filter: CatalogFilterState,
    val browse: BrowseListsState,
    val style: LibraryBookCardStyle,
    val columns: Int,
    val tileColumns: Int,
    val showsOfflineHint: Boolean,
    val navigator: TabNavigator?,
)

/** Sammelt die Flows des Bücher-Sektionsinhalts (Android: Home-Bibliotheksleiste mit Books-Bibliothek). */
@Composable
internal fun rememberBooksBrowseSectionContent(catalog: CatalogStore, model: AppModel = AppModel.shared): BooksBrowseSectionContent {
    val section by catalog.booksBrowseSection.collectAsState()
    val books by catalog.displayBooks.collectAsState()
    val loading by catalog.isLoadingLibrary.collectAsState()
    val filter by catalog.filter.collectAsState()
    val browse by catalog.browse.collectAsState()
    val style by catalog.libraryBookCardStyle.collectAsState()
    val reachable by model.session.isNetworkReachable.collectAsState()
    val offline by model.session.offlineHomeMode.collectAsState()
    val offlineAuto by model.session.offlineHomeModeAuto.collectAsState()
    // eBook-Filter hängt am Lesefortschritt — bei Fortschrittsänderungen neu filtern (Recomposition).
    model.progress.progressByItemId.collectAsState().value
    return BooksBrowseSectionContent(
        section = section,
        catalog = catalog,
        books = books,
        loading = loading,
        filter = filter,
        browse = browse,
        style = style,
        columns = libraryGridColumns(style),
        tileColumns = facetColumns(),
        showsOfflineHint = !reachable && !(offline || offlineAuto),
        navigator = LocalTabNavigator.current,
    )
}

/**
 * iOS: Sektionsinhalt des Bücher-Tabs (`booksCatalogBookListBody`, `booksEbookListBody`,
 * `MainRootBrowseSections`) als Listen-Einträge — Überschrift, Filter-Banner, Lade-/Leerzustand,
 * Karten bzw. Kacheln mit Paging am Listenende. Die Liste (Padding `tabPaddingH`, Abstand
 * `withinSectionSpacing`, Pull-to-Refresh) stellt der Aufrufer (Home).
 */
internal fun LazyListScope.booksBrowseSectionItems(content: BooksBrowseSectionContent) {
    val section = content.section
    val catalog = content.catalog
    val books = content.books
    val loading = content.loading
    val filter = content.filter
    val browse = content.browse
    val style = content.style
    val columns = content.columns
    val tileColumns = content.tileColumns
    val showsOfflineHint = content.showsOfflineHint
    val navigator = content.navigator
    when (section) {
        BooksBrowseSection.BOOKS, BooksBrowseSection.SEARCH -> {
            // Immer „Audiobooks" — welche Bibliothek gemeint ist, sagt die Leiste darüber.
            if (filter.isLibraryCatalogFiltered) {
                item(key = "books-filter") { CatalogFilterBanner(filter.activeLibraryFilterSummary, catalog::clearCatalogFilter) }
            }
            when {
                loading && books.isEmpty() -> item(key = "books-loading") { AbstandLoadingSpinner() }
                // Leerzustand verhindert eine „weiße" Liste nach Filter/Mark-as-finished.
                books.isEmpty() -> item(key = "books-empty") { AbstandSectionEmptyState("No books match the current filter.") }
                else -> bookCards(books, style, columns, "book", onAppear = { catalog.loadMoreIfNeeded(it.id) })
            }
        }
        BooksBrowseSection.EBOOKS, BooksBrowseSection.EBOOKS_SUPPLEMENTARY -> {
            val pure = catalog.browseEbooksFiltered(browse.ebooks, filter.ebookCatalogQuickFilter)
            val supplementary = catalog.browseEbooksFiltered(browse.ebooksSupplementary, filter.ebookCatalogQuickFilter)
            when {
                browse.ebooksLoading && pure.isEmpty() && supplementary.isEmpty() -> item(key = "ebooks-loading") { AbstandLoadingSpinner() }
                pure.isEmpty() -> item(key = "ebooks-empty") {
                    AbstandSectionEmptyState(
                        if (filter.ebookCatalogQuickFilter == null) "No eBooks in this library." else "No eBooks match the current filter.",
                    )
                }
                else -> bookCards(pure, style, columns, "ebook", usesEbookProgressDisplay = true, onAppear = { catalog.loadMoreBrowseEbooksIfNeeded(it.id) })
            }
            if (supplementary.isNotEmpty()) {
                item(key = "ebooks-supp-title") {
                    TabContentSectionTitle("Audiobooks with eBook", Modifier.padding(top = AppTheme.Layout.sectionSpacing))
                }
                bookCards(supplementary, style, columns, "ebook-supp", usesEbookProgressDisplay = true)
            }
        }
        BooksBrowseSection.AUTHOR -> {
            when {
                showsOfflineHint -> item(key = "authors-offline") { BrowseOfflineHint() }
                browse.authorsLoading && browse.authors.isEmpty() -> item(key = "authors-loading") { AbstandLoadingSpinner() }
                browse.authors.isEmpty() -> item(key = "authors-empty") { AbstandSectionEmptyState("No authors found.") }
                else -> items(browse.authors, key = { "author-${it.id}" }) { author ->
                    BrowseEntityRowCard(
                        title = author.name,
                        detailLabel = "Books",
                        detailValue = CatalogLogic.booksCountLine(author.numBooks),
                        onClick = { navigator?.push(AuthorDetailDestination(author.id, author.name, author.numBooks)) },
                        coverUrl = if (author.hasAuthorImage) catalog.authorImageURL(author.id) else null,
                        coverCacheScopeId = authorCoverScopeId(author.id),
                        usesSquareCenterCropCover = true,
                    )
                    LaunchedEffect(author.id) { catalog.loadMoreBrowseAuthorsIfNeeded(author.id) }
                }
            }
        }
        BooksBrowseSection.SERIES -> {
            when {
                showsOfflineHint -> item(key = "series-offline") { BrowseOfflineHint() }
                browse.seriesLoading && browse.series.isEmpty() -> item(key = "series-loading") { AbstandLoadingSpinner() }
                browse.series.isEmpty() -> item(key = "series-empty") { AbstandSectionEmptyState("No series found.") }
                else -> items(browse.series, key = { "series-${it.id}" }) { series ->
                    val ids = CatalogLogic.seriesCoverBookIds(series.books)
                    BrowseEntityRowCard(
                        title = series.name,
                        detailLabel = "Books",
                        detailValue = CatalogLogic.booksCountLine(series.books?.size),
                        onClick = { navigator?.push(SeriesDetailDestination(series.id, series.name, series.books?.size)) },
                        coverItemId = ids.firstOrNull(),
                        coverBookIds = ids.takeIf { it.size > 1 },
                        authorLine = series.cardAuthorsLine,
                        placeholderIcon = SF.booksVertical,
                    )
                    LaunchedEffect(series.id) { catalog.loadMoreBrowseSeriesIfNeeded(series.id) }
                }
            }
        }
        BooksBrowseSection.NARRATORS, BooksBrowseSection.COLLECTIONS, BooksBrowseSection.GENRES, BooksBrowseSection.TAGS -> {
            val (tiles, isLoading, emptyText) = when (section) {
                BooksBrowseSection.NARRATORS -> Triple(
                    browse.narrators.map { n -> FacetTile(n.id, n.name, n.numBooks) { navigator?.push(NarratorDetailDestination(n.name, n.numBooks)) } },
                    browse.narratorsLoading, "No narrators found.",
                )
                BooksBrowseSection.COLLECTIONS -> Triple(
                    browse.collections.map { c ->
                        FacetTile(c.id, c.name, c.books?.size) { navigator?.push(CollectionDetailDestination(c.id, c.name, c.books?.size)) }
                    },
                    browse.collectionsLoading, "No collections found.",
                )
                BooksBrowseSection.GENRES -> Triple(
                    browse.genres.map { g ->
                        FacetTile(g.name, g.name, g.numBooks) {
                            navigator?.push(FacetFilteredBooksDestination(BooksEntityDetailNav.Kind.GENRE, g.name, g.numBooks))
                        }
                    },
                    browse.genresLoading, "No genres found.",
                )
                else -> Triple(
                    browse.tags.map { t ->
                        FacetTile(t.name, t.name, t.numBooks) {
                            navigator?.push(FacetFilteredBooksDestination(BooksEntityDetailNav.Kind.TAG, t.name, t.numBooks))
                        }
                    },
                    browse.tagsLoading, "No tags found.",
                )
            }
            when {
                showsOfflineHint -> item(key = "facet-offline") { BrowseOfflineHint() }
                isLoading && tiles.isEmpty() -> item(key = "facet-loading") { AbstandLoadingSpinner() }
                tiles.isEmpty() -> item(key = "facet-empty") { AbstandSectionEmptyState(emptyText) }
                else -> items(tiles.chunked(tileColumns), key = { "facet-${section.rawValue}-${it.first().key}" }) { row ->
                    LibraryGridRow(row, tileColumns) { tile -> FacetBrowseTileCard(section, tile.title, tile.count, tile.open) }
                }
            }
        }
    }
}

/** iOS: `booksBrowseOfflineHint`. */
@Composable
private fun BrowseOfflineHint() {
    Text(
        "Connect to the network to load this list.",
        style = AppType.bodyMedium,
        color = Theme.palette.textSecondary,
        modifier = Modifier.padding(vertical = AppTheme.Layout.rowVerticalPadding),
    )
}

/** Buchkarten als Liste oder zeilenweises Raster (iOS: `LibraryHeroMultiColumnRows`). */
internal fun LazyListScope.bookCards(
    books: List<AbsBook>,
    style: LibraryBookCardStyle,
    columns: Int,
    keyPrefix: String,
    usesEbookProgressDisplay: Boolean = false,
    forceCompact: Boolean = false,
    onAppear: (suspend (AbsBook) -> Unit)? = null,
) {
    if (!forceCompact && style.usesMultiColumnGrid && columns > 1) {
        items(books.chunked(columns), key = { "$keyPrefix-row-${it.first().id}" }) { row ->
            LibraryGridRow(row, columns) { book ->
                LibraryBookListCard(book, style, usesEbookProgressDisplay = usesEbookProgressDisplay)
            }
            if (onAppear != null) LaunchedEffect(row.last().id) { onAppear(row.last()) }
        }
    } else {
        items(books, key = { "$keyPrefix-${it.id}" }) { book ->
            LibraryBookListCard(
                book, style, usesEbookProgressDisplay = usesEbookProgressDisplay, forceCompact = forceCompact,
                usesSquareCenterCropCover = forceCompact && !book.isPureEbookLibraryItem,
            )
            if (onAppear != null) LaunchedEffect(book.id) { onAppear(book) }
        }
    }
}

/** iOS: `catalogFilterBanner` — Kapsel mit Filtertext und „Show all". */
@Composable
private fun CatalogFilterBanner(summary: String?, onShowAll: () -> Unit) {
    val palette = Theme.palette
    Row(
        Modifier.fillMaxWidth().background(palette.card, CircleShape)
            .padding(start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.tightSpacing),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
    ) {
        Icon(SF.line3HorizontalDecreaseCircle, null, tint = palette.textSecondary)
        Text(summary ?: "Library filtered", style = AppType.bodyLarge, color = palette.textPrimary, maxLines = 2, modifier = Modifier.weight(1f))
        AbstandTextButton("Show all", onShowAll, emphasized = true, compact = true)
    }
}
