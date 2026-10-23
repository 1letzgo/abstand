package de.letzgo.abstand.ui.library

import androidx.compose.runtime.Composable
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
import de.letzgo.abstand.model.CatalogStore
import de.letzgo.abstand.ui.AppTheme

// MARK: - Toolbar

/**
 * iOS: `BooksLibraryToolbarContent` — Aktionen je Sektion (Genres/Tags/… nur Sortierung).
 * Android: rechts in der Home-Bibliotheksleiste, wenn eine Books-Bibliothek gewählt ist.
 */
@Composable
internal fun BooksLibraryToolbar(snapshot: BooksLibraryToolbarSnapshot, catalog: CatalogStore) {
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

// MARK: - Sektionsinhalt

/** Grid-Spalten der Facetten-Kacheln (iOS: `GridItem(.adaptive(minimum: 160))`). */
@Composable
internal fun facetColumns(): Int {
    val width = LocalConfiguration.current.screenWidthDp.dp - AppTheme.Layout.tabPaddingH * 2
    return maxOf(1, (width / AppTheme.Layout.facetTileMinWidth).toInt())
}
