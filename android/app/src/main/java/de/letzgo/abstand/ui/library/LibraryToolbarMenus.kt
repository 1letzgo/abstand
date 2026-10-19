package de.letzgo.abstand.ui.library

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.abstand.logic.LibraryCatalogQuickFilter
import de.letzgo.abstand.logic.SortMenuField
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandMenuButton

/**
 * iOS: `AbstandCatalogSortToolbarMenu` — Sortier-Icon mit verankertem Menü: „Sort by"-Felder,
 * darunter Auf-/Absteigend (bei „Random" ausgeblendet).
 */
@Composable
fun <F : SortMenuField> AbstandSortToolbarMenu(
    fields: List<F>,
    sortField: F,
    sortDescending: Boolean,
    onSortFieldChange: (F) -> Unit,
    onSortDescendingChange: (Boolean) -> Unit,
) {
    AbstandMenuButton(SF.arrowUpArrowDown, "Sort", tint = Theme.palette.textPrimary) {
        picker(fields, sortField, { it.menuTitle }, onSortFieldChange, title = "Sort by")
        if (!sortField.suppressesSortOrderPicker) {
            divider()
            picker(
                listOf(false, true), sortDescending, { if (it) "Descending" else "Ascending" }, onSortDescendingChange,
                title = "Order", icon = { if (it) SF.arrowDown else SF.arrowUp },
            )
        }
    }
}

/** Material-Symbol eines Schnellfilters (iOS: `menuSystemImage`). */
private val LibraryCatalogQuickFilter.icon: ImageVector get() = SF.named(menuSystemImage) ?: SF.circle

/**
 * iOS: `BooksCatalogFilterToolbarMenu` — Filter-Icon (gefüllt + Akzent, wenn aktiv) mit „All",
 * In progress / Finished / Not started und — abgesetzt — Downloaded.
 */
@Composable
fun BooksCatalogFilterToolbarMenu(
    isActive: Boolean,
    quickFilter: LibraryCatalogQuickFilter?,
    isAllFilterActive: Boolean,
    onClear: () -> Unit,
    onSelect: (LibraryCatalogQuickFilter) -> Unit,
) {
    AbstandMenuButton(
        if (isActive) SF.line3HorizontalDecreaseCircleFill else SF.line3HorizontalDecreaseCircle,
        "Filter",
        tint = if (isActive) Theme.accent else Theme.palette.textPrimary,
    ) {
        item("All", onClear, icon = SF.line3HorizontalDecreaseCircle, selected = isAllFilterActive)
        listOf(LibraryCatalogQuickFilter.IN_PROGRESS, LibraryCatalogQuickFilter.FINISHED, LibraryCatalogQuickFilter.NOT_STARTED).forEach { f ->
            item(f.menuTitle, { onSelect(f) }, icon = f.icon, selected = quickFilter == f)
        }
        divider()
        val downloaded = LibraryCatalogQuickFilter.DOWNLOADED
        item(downloaded.menuTitle, { onSelect(downloaded) }, icon = downloaded.icon, selected = quickFilter == downloaded)
    }
}
