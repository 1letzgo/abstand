package de.letzgo.abstand.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.logic.BooksBrowseAuthorsSortField
import de.letzgo.abstand.logic.BooksBrowseCollectionsSortField
import de.letzgo.abstand.logic.BooksBrowseFacetSortField
import de.letzgo.abstand.logic.BooksBrowseNarratorsSortField
import de.letzgo.abstand.logic.BooksBrowseSection
import de.letzgo.abstand.logic.BooksBrowseSeriesSortField
import de.letzgo.abstand.logic.BooksLibraryToolbarSnapshot
import de.letzgo.abstand.logic.CatalogLogic
import de.letzgo.abstand.logic.CatalogSortField
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.CatalogStore
import de.letzgo.abstand.model.LibraryBookCardStyle
import de.letzgo.abstand.model.MainTab
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandLabeledLoadingState
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.components.TabRootScaffold
import de.letzgo.abstand.ui.detail.AuthorDetailDestination
import de.letzgo.abstand.ui.detail.CollectionDetailDestination
import de.letzgo.abstand.ui.detail.FacetFilteredBooksDestination
import de.letzgo.abstand.ui.detail.NarratorDetailDestination
import de.letzgo.abstand.ui.detail.SeriesDetailDestination
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.launch

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
 * iOS: `AbstandPinnedBrowseStrip` (Bibliotheks-Picker + Sektionen). Android: Material-`FilterChip`s —
 * links die Bibliothek (Dropdown bei mehreren aktiven), dahinter die Sektionen in iOS-Reihenfolge.
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
    var pickerOpen by remember { mutableStateOf(false) }
    val chipColors = FilterChipDefaults.filterChipColors(
        containerColor = Theme.palette.card,
        labelColor = Theme.palette.textPrimary,
        iconColor = Theme.palette.textSecondary,
        selectedContainerColor = Theme.accent,
        selectedLabelColor = Theme.onAccent,
        selectedLeadingIconColor = Theme.onAccent,
    )
    LazyRow(
        contentPadding = PaddingValues(horizontal = AppTheme.Layout.tabPaddingH),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.horizontalBrowseStripVerticalPadding),
    ) {
        if (current != null) {
            item(key = "library") {
                Box {
                    FilterChip(
                        selected = false,
                        onClick = { if (libraries.size > 1) pickerOpen = true },
                        label = { Text(current.name, maxLines = 1, overflow = TextOverflow.Ellipsis, style = IosType.subheadline.semibold) },
                        leadingIcon = { Icon(SF.booksVerticalFill, null, Modifier.size(FilterChipDefaults.IconSize)) },
                        trailingIcon = if (libraries.size > 1) ({ Icon(SF.chevronDown, "Choose library", Modifier.size(FilterChipDefaults.IconSize)) }) else null,
                        colors = chipColors,
                        shape = CircleShape,
                    )
                    DropdownMenu(expanded = pickerOpen, onDismissRequest = { pickerOpen = false }, containerColor = Theme.palette.card) {
                        libraries.forEach { lib ->
                            DropdownMenuItem(
                                text = { Text(lib.name, style = IosType.body, color = Theme.palette.textPrimary) },
                                trailingIcon = if (lib.id == current.id) ({ Icon(SF.checkmark, "Selected", tint = Theme.accent) }) else null,
                                onClick = {
                                    pickerOpen = false
                                    session.focusBooksLibrary(lib)
                                },
                            )
                        }
                    }
                }
            }
        }
        items(BooksBrowseSection.audiobookStripOrder, key = { it.rawValue }) { s ->
            FilterChip(
                selected = s == section,
                onClick = { catalog.selectBooksBrowseSection(s) },
                label = { Text(s.title, style = IosType.subheadline.semibold, maxLines = 1) },
                leadingIcon = { Icon(s.icon, null, Modifier.size(FilterChipDefaults.IconSize)) },
                colors = chipColors,
                shape = CircleShape,
                border = null,
            )
        }
    }
}

// MARK: - Sektionsinhalt

/** Grid-Spalten der Facetten-Kacheln (iOS: `GridItem(.adaptive(minimum: 160))`). */
@Composable
internal fun facetColumns(): Int {
    val width = LocalConfiguration.current.screenWidthDp.dp - AppTheme.Layout.tabPaddingH * 2
    return maxOf(1, (width / AppTheme.Layout.facetTileMinWidth).toInt())
}
