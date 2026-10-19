package de.letzgo.abstand.ui.library

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.logic.BooksBrowseAuthorsSortField
import de.letzgo.abstand.logic.BooksBrowseCollectionsSortField
import de.letzgo.abstand.logic.BooksBrowseFacetSortField
import de.letzgo.abstand.logic.BooksBrowseNarratorsSortField
import de.letzgo.abstand.logic.BooksBrowseSection
import de.letzgo.abstand.logic.BooksBrowseSeriesSortField
import de.letzgo.abstand.logic.BooksLibraryToolbarSnapshot
import de.letzgo.abstand.logic.CatalogSortField
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.CatalogStore
import de.letzgo.abstand.model.MainTab
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.components.AbstandBrowseStripItem
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandFixedBrowseStripSectionsLayout
import de.letzgo.abstand.ui.components.AbstandLabeledLoadingState
import de.letzgo.abstand.ui.components.AbstandPinnedBrowseStrip
import de.letzgo.abstand.ui.components.TabRootScaffold

/**
 * iOS: Bücher-Tab-Root (`MainRootView.libraryTabRoot` → `BooksLibraryTabShell` +
 * `AbstandFixedBrowseStripSectionsLayout` + `MainRootBrowseSections`). Großtitel „Books", fixe
 * Browse-Leiste (Bibliothek + Sektionen), Toolbar je Sektion (Filter + Sortierung), Pull-to-Refresh,
 * Paging am Listenende, Leerzustände je Sektion.
 */
@Composable
fun BooksLibraryTabRoot(model: AppModel = AppModel.shared) {
    val session = model.session
    val catalog = model.catalog
    val selected by session.selectedBooksLibrary.collectAsState()
    val bootstrapping by session.isAppBootstrapInProgress.collectAsState()
    val section by catalog.booksBrowseSection.collectAsState()
    val snapshot by catalog.toolbarSnapshot.collectAsState()

    LaunchedEffect(selected?.id) { if (selected != null) catalog.ensureActiveSectionLoaded() }

    TabRootScaffold(
        title = MainTab.library.label,
        actions = { if (selected != null) BooksLibraryToolbar(snapshot, catalog) },
        header = if (selected != null) ({ BooksBrowseStrip(model) }) else null,
    ) { padding ->
        if (selected == null) {
            if (bootstrapping) {
                AbstandLabeledLoadingState(Modifier.padding(padding))
            } else {
                AbstandEmptyScreen(
                    title = "No library selected",
                    icon = SF.booksVertical,
                    description = "Choose an audiobook library in Settings.",
                    modifier = Modifier.padding(padding),
                )
            }
            return@TabRootScaffold
        }
        BooksBrowseSectionPane(section, catalog, padding)
    }
}

// MARK: - Toolbar

/** iOS: `BooksLibraryToolbarContent` — Aktionen je Sektion (Genres/Tags/… nur Sortierung). */
@Composable
private fun BooksLibraryToolbar(snapshot: BooksLibraryToolbarSnapshot, catalog: CatalogStore) {
    when (snapshot.booksBrowseSection) {
        BooksBrowseSection.BOOKS -> {
            BooksCatalogFilterToolbarMenu(
                isActive = snapshot.isLibraryCatalogFiltered,
                quickFilter = snapshot.libraryCatalogQuickFilter,
                isAllFilterActive = snapshot.isAllFilterActive,
                onClear = catalog::clearCatalogFilter,
                onSelect = catalog::applyLibraryCatalogQuickFilter,
            )
            AbstandSortToolbarMenu(
                CatalogSortField.entries, snapshot.catalogSortField, snapshot.catalogSortDescending,
                catalog::applyCatalogSortField, catalog::applyCatalogSortDescending,
            )
        }
        BooksBrowseSection.EBOOKS, BooksBrowseSection.EBOOKS_SUPPLEMENTARY -> {
            BooksCatalogFilterToolbarMenu(
                isActive = snapshot.ebookCatalogQuickFilter != null,
                quickFilter = snapshot.ebookCatalogQuickFilter,
                isAllFilterActive = snapshot.ebookCatalogQuickFilter == null,
                onClear = { catalog.applyEbookCatalogQuickFilter(null) },
                onSelect = catalog::applyEbookCatalogQuickFilter,
            )
            AbstandSortToolbarMenu(
                CatalogSortField.entries, snapshot.catalogSortField, snapshot.catalogSortDescending,
                catalog::applyCatalogSortField, catalog::applyCatalogSortDescending,
            )
        }
        BooksBrowseSection.AUTHOR -> AbstandSortToolbarMenu(
            BooksBrowseAuthorsSortField.entries, snapshot.browseAuthorsSortField, snapshot.browseAuthorsSortDescending,
            catalog::applyBrowseAuthorsSortField, catalog::applyBrowseAuthorsSortDescending,
        )
        BooksBrowseSection.NARRATORS -> AbstandSortToolbarMenu(
            BooksBrowseNarratorsSortField.entries, snapshot.browseNarratorsSortField, snapshot.browseNarratorsSortDescending,
            catalog::applyBrowseNarratorsSortField, catalog::applyBrowseNarratorsSortDescending,
        )
        BooksBrowseSection.SERIES -> AbstandSortToolbarMenu(
            BooksBrowseSeriesSortField.entries, snapshot.browseSeriesSortField, snapshot.browseSeriesSortDescending,
            catalog::applyBrowseSeriesSortField, catalog::applyBrowseSeriesSortDescending,
        )
        BooksBrowseSection.COLLECTIONS -> AbstandSortToolbarMenu(
            BooksBrowseCollectionsSortField.entries, snapshot.browseCollectionsSortField, snapshot.browseCollectionsSortDescending,
            catalog::applyBrowseCollectionsSortField, catalog::applyBrowseCollectionsSortDescending,
        )
        BooksBrowseSection.GENRES -> AbstandSortToolbarMenu(
            BooksBrowseFacetSortField.entries, snapshot.browseGenresSortField, snapshot.browseGenresSortDescending,
            catalog::applyBrowseGenresSortField, catalog::applyBrowseGenresSortDescending,
        )
        BooksBrowseSection.TAGS -> AbstandSortToolbarMenu(
            BooksBrowseFacetSortField.entries, snapshot.browseTagsSortField, snapshot.browseTagsSortDescending,
            catalog::applyBrowseTagsSortField, catalog::applyBrowseTagsSortDescending,
        )
        BooksBrowseSection.SEARCH -> Unit
    }
}

// MARK: - Browse-Leiste

/**
 * iOS: `AbstandPinnedBrowseStrip` (Bibliotheks-Picker + Sektionen) — eine aktive Bibliothek:
 * Dock-Streifen der Sektionen in iOS-Reihenfolge; mehrere: zwei Auswahl-Pillen.
 */
@Composable
private fun BooksBrowseStrip(model: AppModel) {
    val session = model.session
    val catalog = model.catalog
    val section by catalog.booksBrowseSection.collectAsState()
    val focused by session.focusedBooksLibrary.collectAsState()
    val selected by session.selectedBooksLibrary.collectAsState()
    session.activeBooksLibraryIds.collectAsState().value
    session.libraries.collectAsState().value
    val libraries = session.activeBookLibraries
    val current = focused ?: selected ?: libraries.firstOrNull()
    val sections = BooksBrowseSection.audiobookStripOrder
    AbstandPinnedBrowseStrip(
        secondaryItems = sections.map { AbstandBrowseStripItem(it.rawValue, it.title, it.icon) },
        secondarySelectionId = section.rawValue,
        onSelectSecondary = { id -> sections.firstOrNull { it.rawValue == id }?.let(catalog::selectBooksBrowseSection) },
        libraryPickerItems = libraries.map { AbstandBrowseStripItem(it.id, it.name, SF.booksVerticalFill) },
        libraryPickerSelectionId = current?.id.orEmpty(),
        onSelectLibrary = { id -> libraries.firstOrNull { it.id == id }?.let(session::focusBooksLibrary) },
    )
}

// MARK: - Sektionsinhalt

/** Grid-Spalten der Facetten-Kacheln (iOS: `GridItem(.adaptive(minimum: 160))`). */
@Composable
internal fun facetColumns(): Int {
    val width = LocalConfiguration.current.screenWidthDp.dp - AppTheme.Layout.tabPaddingH * 2
    return maxOf(1, (width / AppTheme.Layout.facetTileMinWidth).toInt())
}
