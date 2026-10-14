package de.letzgo.abstand.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.components.AbstandDockChip

/** Ein Eintrag der Icon-Leiste. */
data class SettingsStripItem<T>(val id: T, val label: String, val icon: ImageVector)

/**
 * iOS: `SettingsIconStrip` (`AbstandBrowseStripIconMenu`, „Expanding Dock“) — aktiver Eintrag als
 * Akzent-Kapsel mit Symbol + Label, inaktive als runde Symbol-Knöpfe. Horizontal scrollbar.
 */
@Composable
fun <T> SettingsIconStrip(items: List<SettingsStripItem<T>>, selection: T, onSelect: (T) -> Unit) {
    val dock = AppTheme.ExpandingDock
    val listState = rememberLazyListState()
    val selectedIndex = items.indexOfFirst { it.id == selection }
    LaunchedEffect(selectedIndex) { if (selectedIndex >= 0) listState.animateScrollToItem(selectedIndex) }
    LazyRow(
        state = listState,
        contentPadding = PaddingValues(horizontal = AppTheme.Layout.tabPaddingH, vertical = dock.verticalPadding),
        horizontalArrangement = Arrangement.spacedBy(dock.itemSpacing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(items, key = { it.id.toString() }) { item ->
            AbstandDockChip(item.label, item.icon, item.id == selection, onClick = { onSelect(item.id) })
        }
    }
}
