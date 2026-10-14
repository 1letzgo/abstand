package de.letzgo.abstand.ui.library

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.abstand.logic.LibraryCatalogQuickFilter
import de.letzgo.abstand.logic.SortMenuField
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.semibold

/** Abschnittsüberschrift im Dropdown (iOS: `Picker`-Titel im Menü). */
@Composable
private fun MenuSectionLabel(text: String) {
    DropdownMenuItem(
        text = { Text(text, style = IosType.footnote.semibold, color = Theme.palette.textSecondary) },
        onClick = {},
        enabled = false,
    )
}

@Composable
private fun CheckedMenuItem(title: String, selected: Boolean, leading: ImageVector? = null, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(title, style = IosType.body, color = Theme.palette.textPrimary) },
        leadingIcon = leading?.let { { Icon(it, null, tint = if (selected) Theme.accent else Theme.palette.textSecondary) } },
        trailingIcon = if (selected) {
            { Icon(SF.checkmark, contentDescription = "Selected", tint = Theme.accent) }
        } else null,
        onClick = onClick,
    )
}

/**
 * iOS: `AbstandCatalogSortToolbarMenu` — Sortier-Icon mit verankertem Dropdown: „Sort by"-Felder,
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
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(SF.arrowUpArrowDown, contentDescription = "Sort", tint = Theme.palette.textPrimary)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = Theme.palette.card) {
            MenuSectionLabel("Sort by")
            fields.forEach { field ->
                CheckedMenuItem(field.menuTitle, field == sortField) {
                    onSortFieldChange(field)
                    expanded = false
                }
            }
            if (!sortField.suppressesSortOrderPicker) {
                HorizontalDivider()
                MenuSectionLabel("Order")
                CheckedMenuItem("Ascending", !sortDescending, SF.arrowUp) {
                    onSortDescendingChange(false)
                    expanded = false
                }
                CheckedMenuItem("Descending", sortDescending, SF.arrowDown) {
                    onSortDescendingChange(true)
                    expanded = false
                }
            }
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
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(
                if (isActive) SF.line3HorizontalDecreaseCircleFill else SF.line3HorizontalDecreaseCircle,
                contentDescription = "Filter",
                tint = if (isActive) Theme.accent else Theme.palette.textPrimary,
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = Theme.palette.card) {
            CheckedMenuItem("All", isAllFilterActive, SF.line3HorizontalDecreaseCircle) {
                onClear()
                expanded = false
            }
            listOf(LibraryCatalogQuickFilter.IN_PROGRESS, LibraryCatalogQuickFilter.FINISHED, LibraryCatalogQuickFilter.NOT_STARTED).forEach { f ->
                CheckedMenuItem(f.menuTitle, quickFilter == f, f.icon) {
                    onSelect(f)
                    expanded = false
                }
            }
            HorizontalDivider()
            CheckedMenuItem(LibraryCatalogQuickFilter.DOWNLOADED.menuTitle, quickFilter == LibraryCatalogQuickFilter.DOWNLOADED, LibraryCatalogQuickFilter.DOWNLOADED.icon) {
                onSelect(LibraryCatalogQuickFilter.DOWNLOADED)
                expanded = false
            }
        }
    }
}
