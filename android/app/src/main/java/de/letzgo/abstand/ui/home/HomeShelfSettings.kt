package de.letzgo.abstand.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import de.letzgo.abstand.data.AbsStartShelfLocalization
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.HomeShelfLogic
import de.letzgo.abstand.model.StartCategoryRow
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.SettingsCardIcon
import de.letzgo.abstand.ui.components.SettingsSubpageScaffold
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.components.abstandCardListRowFrame
import de.letzgo.abstand.ui.components.abstandSwitchColors

/**
 * iOS: `SettingsAppearanceHomeView` (Settings → Appearance → Home) — je Regal eine Karte mit
 * Schalter; Reihenfolge änderbar, Continue listening bleibt oben. Android: statt Drag-Griff
 * Hoch/Runter-Knöpfe (Material-Listen-Reorder ohne Drag-and-Drop-Bibliothek).
 * Der Settings-Port verlinkt diese Seite aus „Appearance“ (`HomeShelvesSettingsDestination`).
 */
object HomeShelvesSettingsDestination : TabDestination {
    override val key: String get() = "settings/appearance/home"

    @Composable
    override fun Content(navigator: TabNavigator) = HomeShelvesSettingsScreen(onBack = { navigator.pop() })
}

@Composable
fun HomeShelvesSettingsScreen(onBack: () -> Unit) {
    val home = AppModel.shared.home
    val rows by home.startSettingsCategoryList.collectAsState()
    val disabled by home.startDisabledCategories.collectAsState()
    LaunchedEffect(Unit) { home.refreshStartSettingsCategoryListLabels() }
    SettingsSubpageScaffold(title = "Home", onBack = onBack, spacing = AppTheme.Layout.withinSectionSpacing) {
        item(key = "title") { TabContentSectionTitle("Home") }
        items(rows, key = { it.category }) { row ->
            val index = rows.indexOf(row)
            HomeShelfSettingsCard(
                row = row,
                enabled = HomeShelfLogic.isEnabled(row.category, disabled),
                canMoveUp = index > 1,
                canMoveDown = index in 1 until rows.lastIndex,
                onToggle = { home.setStartCategoryEnabled(row.category, it) },
                onMove = { offset -> home.moveStartSettingsCategory(row.category, offset = offset) },
            )
        }
    }
}

/** iOS: `SettingsHomeShelfCard`. */
@Composable
private fun HomeShelfSettingsCard(
    row: StartCategoryRow,
    enabled: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onToggle: (Boolean) -> Unit,
    onMove: (Int) -> Unit,
) {
    val palette = Theme.palette
    val isContinue = row.category == HomeShelfLogic.homeContinueCategory
    AbstandGroupedCard {
        Row(
            Modifier.abstandCardListRowFrame(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
        ) {
            SettingsCardIcon(SF.byName[AbsStartShelfLocalization.stripSystemImage(row.category)] ?: SF.squareGrid2x2)
            Row(
                Modifier.weight(1f).toggleable(value = enabled, role = Role.Switch, onValueChange = onToggle),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(row.label, style = IosType.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
                Switch(checked = enabled, onCheckedChange = null, colors = abstandSwitchColors())
            }
            if (!isContinue) {
                IconButton(onClick = { onMove(-1) }, enabled = canMoveUp, modifier = Modifier.size(AppTheme.Layout.compactIconButtonSize)) {
                    Icon(SF.arrowUp, contentDescription = "Move up", tint = palette.textSecondary)
                }
                IconButton(onClick = { onMove(1) }, enabled = canMoveDown, modifier = Modifier.size(AppTheme.Layout.compactIconButtonSize)) {
                    Icon(SF.arrowDown, contentDescription = "Move down", tint = palette.textSecondary)
                }
            }
        }
    }
}
