package de.letzgo.abstand.ui.settings

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.abstand.ui.components.AbstandBrowseStripItem
import de.letzgo.abstand.ui.components.AbstandBrowseTabs

/** Ein Eintrag der Icon-Leiste. */
data class SettingsStripItem<T>(val id: T, val label: String, val icon: ImageVector)

/**
 * iOS: `SettingsIconStrip` (Expanding Dock). Android: Material-3-scrollbare Tabs ([AbstandBrowseTabs]).
 */
@Composable
fun <T> SettingsIconStrip(items: List<SettingsStripItem<T>>, selection: T, onSelect: (T) -> Unit) {
    AbstandBrowseTabs(
        items = items.map { AbstandBrowseStripItem(it.id.toString(), it.label, it.icon) },
        selectionId = selection.toString(),
        onSelect = { id -> items.firstOrNull { it.id.toString() == id }?.let { onSelect(it.id) } },
    )
}
