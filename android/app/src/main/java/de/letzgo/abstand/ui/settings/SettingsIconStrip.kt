package de.letzgo.abstand.ui.settings

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.semibold

/** Ein Eintrag der Icon-Leiste. */
data class SettingsStripItem<T>(val id: T, val label: String, val icon: ImageVector)

/**
 * iOS: `SettingsIconStrip` (`AbstandBrowseStripIconMenu`, „Expanding Dock“) — aktiver Eintrag als
 * Akzent-Kapsel mit Symbol + Label, inaktive als runde Symbol-Knöpfe. Horizontal scrollbar.
 */
@Composable
fun <T> SettingsIconStrip(items: List<SettingsStripItem<T>>, selection: T, onSelect: (T) -> Unit) {
    val dock = AppTheme.ExpandingDock
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
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
            val active = item.id == selection
            Row(
                Modifier
                    .height(dock.activeHeight)
                    .clip(CircleShape)
                    .background(if (active) colors.activeBackground else colors.inactiveBackground)
                    .clickable(role = Role.Tab) { onSelect(item.id) }
                    .semantics {
                        contentDescription = item.label
                        selected = active
                    }
                    .animateContentSize()
                    .padding(
                        start = if (active) dock.activeLeadingPadding else 0.dp,
                        end = if (active) dock.activeTrailingPadding else 0.dp,
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dock.iconLabelSpacing),
            ) {
                if (active) {
                    Icon(item.icon, contentDescription = null, tint = colors.activeForeground, modifier = Modifier.size(dock.iconSize))
                    Text(item.label, style = IosType.subheadline.semibold, color = colors.activeForeground, maxLines = 1)
                } else {
                    Box(Modifier.size(dock.circleSize), contentAlignment = Alignment.Center) {
                        Icon(
                            item.icon, contentDescription = null,
                            tint = colors.inactiveForeground.copy(alpha = dock.inactiveIconOpacity),
                            modifier = Modifier.size(dock.iconSize),
                        )
                    }
                }
            }
        }
    }
}
