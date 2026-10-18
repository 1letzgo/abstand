package de.letzgo.abstand.ui.settings

import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.runtime.Composable
import de.letzgo.abstand.ui.Appearance
import de.letzgo.abstand.ui.AppearanceMode
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardActionRow
import de.letzgo.abstand.ui.components.SettingsCardColorPickerRow
import de.letzgo.abstand.ui.components.SettingsCardSegmentedRow
import de.letzgo.abstand.ui.components.SettingsCardToggleRow

/** iOS: `SettingsAppearanceView` — Android: nur „Theme“ (Regal-Auswahl entfällt, alle Regale sind immer an). */
fun LazyListScope.settingsAppearanceSections() {
    item(key = "theme") { SettingsThemeSection() }
}

@Composable
private fun SettingsThemeSection() {
    val systemDark = Theme.systemDark
    val accent = Theme.accent
    ServerAdminSection("Theme") {
        AbstandGroupedCard {
            SettingsCardSegmentedRow(
                icon = SF.circleLefthalfFilled,
                title = "Appearance",
                selection = Appearance.mode,
                options = AppearanceMode.entries,
                label = { it.label },
                onSelect = { Appearance.updateMode(it) },
            )
        }
        // Android-only: Dynamic Color (Wallpaper-Farben, Android 12+) ersetzt den Akzent als Seed.
        val dynamic = Appearance.dynamicColor && Appearance.dynamicColorSupported
        if (Appearance.dynamicColorSupported) {
            AbstandGroupedCard {
                SettingsCardToggleRow(
                    icon = SF.photo,
                    title = "Dynamic color",
                    subtitle = "Use wallpaper colors",
                    checked = Appearance.dynamicColor,
                    onCheckedChange = { Appearance.updateDynamicColor(it) },
                )
            }
        }
        if (!dynamic) {
            AbstandGroupedCard {
                SettingsCardColorPickerRow(
                    icon = SF.paintpaletteFill,
                    title = "Accent color",
                    color = accent,
                    onColorChange = { Appearance.updateAccent(it, systemDark) },
                )
            }
            val matchesDefault = Appearance.accentMatchesDefault(systemDark)
            AbstandGroupedCard {
                SettingsCardActionRow(
                    icon = SF.arrowCounterclockwise,
                    title = "Reset to default",
                    onClick = { Appearance.resetAccentToDefault(systemDark) },
                    enabled = !matchesDefault,
                )
            }
        }
    }
}
