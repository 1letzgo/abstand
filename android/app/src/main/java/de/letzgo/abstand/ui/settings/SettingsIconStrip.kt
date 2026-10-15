package de.letzgo.abstand.ui.settings

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.abstand.ui.components.AbstandDockButtons
import de.letzgo.abstand.ui.components.AbstandBrowseStripItem

/** Ein Eintrag der Bereichsauswahl. */
data class SettingsStripItem<T>(val id: T, val label: String, val icon: ImageVector)

/**
 * iOS: `SettingsIconStrip` (Expanding Dock). Android: Bereichs-Buttons im Pill-Stil
 * ([AbstandDockButtons]: aktiver Bereich als Akzent-Kapsel, übrige als runde Symbol-Buttons).
 */
@Composable
fun <T> SettingsIconStrip(items: List<SettingsStripItem<T>>, selection: T, onSelect: (T) -> Unit) {
    AbstandDockButtons(
        items = items.map { AbstandBrowseStripItem(it.id.toString(), it.label, it.icon) },
        selectionId = selection.toString(),
        onSelect = { id -> items.firstOrNull { it.id.toString() == id }?.let { onSelect(it.id) } },
    )
}
