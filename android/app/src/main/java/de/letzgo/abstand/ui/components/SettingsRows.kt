package de.letzgo.abstand.ui.components

import androidx.compose.ui.semantics.heading
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.bold

// iOS: Settings-Zeilen-Set aus ServerAdminViews.swift (dort `private`, hier öffentlich, damit
// Settings-, Admin- und Stats-Screens dieselben Zeilen nutzen). Zeilen liegen in einer
// [AbstandGroupedCard], getrennt durch [SettingsCardDivider].

/** iOS: `ServerAdminLayoutMetrics.inputFieldMaxWidth` — max. Breite von Eingaben in Kartenzeilen. */
private val InputFieldMaxWidth = 180.dp
/** iOS: `.opacity(isEnabled ? 1 : 0.45)` deaktivierter Zeilen. */
private const val DisabledRowOpacity = 0.45f
/** Symbolgröße in Settings-Zeilen (M3-Listen-Leading-Icon: 24 dp). */
private val RowIconSize = AppTheme.Layout.iconSize
/** Trailing-Symbol (Chevron, Statussymbol; M3: 24 dp). */
private val TrailingIconSize = AppTheme.Layout.iconSize
/** Farbfeld im Farbwähler. */
private val ColorSwatchSize = 32.dp
private val ColorPreviewSize = 56.dp

/**
 * iOS: `ServerAdminSection` — Überschrift ([TabContentSectionTitle]) + Inhalt mit
 * `withinSectionSpacing`; Abstand zwischen Sektionen setzt der Container (`sectionSpacing`).
 */
@Composable
fun ServerAdminSection(title: String, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
        AbstandSectionHeader(title)
        content()
    }
}

/** iOS: `SettingsCardIcon` — Symbolspalte (`settingsIconColumnWidth`), Akzent oder [tint]. */
@Composable
fun SettingsCardIcon(icon: ImageVector, tint: Color? = null) {
    Box(Modifier.width(AppTheme.Layout.settingsIconColumnWidth), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = null, tint = tint ?: Theme.palette.textSecondary, modifier = Modifier.size(RowIconSize))
    }
}

/** iOS: `SettingsCardDivider` — Trenner (`textSecondary` 25 %) mit `settingsCardDividerSpacing`. */
@Composable
fun SettingsCardDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(
        modifier.padding(vertical = AppTheme.Layout.settingsCardDividerSpacing),
        thickness = AppTheme.Layout.hairlineWidth,
        color = Theme.palette.scheme.outlineVariant,
    )
}

/**
 * Gemeinsame Zeilenhülle = M3-Listenzeile: Icon-Spalte + Inhalt, 16 dp Abstand, 8 dp oben/unten,
 * Mindesthöhe 56 dp (einzeilig) bzw. 72 dp ([twoLine], mit Untertitel).
 */
@Composable
private fun SettingsRow(
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    twoLine: Boolean = false,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier.abstandCardListRowFrame()
            .heightIn(min = if (twoLine) AppTheme.Layout.listItemTwoLineHeight else AppTheme.Layout.listItemOneLineHeight)
            .padding(vertical = AppTheme.Layout.rowVerticalPadding)
            .alpha(if (enabled) 1f else DisabledRowOpacity),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
        content = content,
    )
}

/** Titel (+ optionaler Untertitel) als Textspalte einer Zeile. */
@Composable
private fun RowTitles(title: String, subtitle: String?, titleColor: Color, titleMedium: Boolean, modifier: Modifier, subtitleMaxLines: Int = Int.MAX_VALUE) {
    val palette = Theme.palette
    Column(modifier) {
        Text(title, style = if (titleMedium) AppType.titleMedium else AppType.bodyLarge, color = titleColor)
        if (subtitle != null) {
            Text(subtitle, style = AppType.bodyMedium, color = palette.textSecondary, maxLines = subtitleMaxLines, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** iOS: `ServerAdminNavRow` — Navigationszeile (Symbol, Titel/Untertitel, Chevron) zu einer Unterseite. */
@Composable
fun SettingsCardNavRow(icon: ImageVector, title: String, onClick: () -> Unit, subtitle: String? = null) {
    SettingsRow(Modifier.clickable(onClick = onClick), twoLine = subtitle != null) {
        SettingsCardIcon(icon)
        RowTitles(title, subtitle, Theme.palette.textPrimary, titleMedium = true, modifier = Modifier.weight(1f))
        Icon(SF.chevronRight, contentDescription = null, tint = Theme.palette.textSecondary, modifier = Modifier.size(TrailingIconSize))
    }
}

/** iOS: `SettingsCardToggleRow` — Symbol, Titel/Untertitel, Material-`Switch` (ganze Zeile tippbar). */
@Composable
fun SettingsCardToggleRow(
    icon: ImageVector,
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    subtitle: String? = null,
    enabled: Boolean = true,
) {
    SettingsRow(
        Modifier.toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange),
        enabled = enabled,
        twoLine = subtitle != null,
    ) {
        SettingsCardIcon(icon)
        RowTitles(title, subtitle, Theme.palette.textPrimary, titleMedium = false, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = null, enabled = enabled, colors = abstandSwitchColors())
    }
}

/**
 * Switch-Farben: Akzent-Spur, Daumen in `onPrimary` (iOS: `.tint(themeAccent)`); aus nach M3
 * (Spur surfaceContainerHighest, Daumen und Rand outline).
 */
@Composable
fun abstandSwitchColors() = SwitchDefaults.colors(
    checkedTrackColor = Theme.accent,
    checkedThumbColor = Theme.onAccent,
    checkedBorderColor = Theme.accent,
    uncheckedTrackColor = Theme.palette.scheme.surfaceContainerHighest,
    uncheckedThumbColor = Theme.palette.scheme.outline,
    uncheckedBorderColor = Theme.palette.scheme.outline,
)

/**
 * iOS: `SettingsCardPickerRow` (`.pickerStyle(.menu)`) — Titel links, aktueller Wert rechts
 * als [AbstandPickerValueMenu]. Tint bewusst neutral (`textPrimary`): Zustand, kein Aufruf.
 */
@Composable
fun <T> SettingsCardPickerRow(
    icon: ImageVector,
    title: String,
    selection: T,
    options: List<T>,
    label: (T) -> String,
    onSelect: (T) -> Unit,
    enabled: Boolean = true,
) {
    var expanded by remember { mutableStateOf(false) }
    SettingsRow(Modifier.clickable(enabled = enabled) { expanded = true }, enabled = enabled) {
        SettingsCardIcon(icon)
        Text(title, style = AppType.bodyLarge, color = Theme.palette.textPrimary, modifier = Modifier.weight(1f))
        AbstandPickerValueMenu(selection, options, label, onSelect, expanded) { expanded = it }
    }
}

/**
 * iOS: `SettingsCardAppearanceModeRow` (`.pickerStyle(.segmented)`) — Symbol + Titel, darunter
 * ein [AbstandSegmentedControl] über die volle Breite. Generisch für jede
 * kleine Optionsmenge.
 */
@Composable
fun <T> SettingsCardSegmentedRow(
    icon: ImageVector,
    title: String,
    selection: T,
    options: List<T>,
    label: (T) -> String,
    onSelect: (T) -> Unit,
) {
    val palette = Theme.palette
    Column(
        Modifier.abstandCardListRowFrame().padding(vertical = AppTheme.Layout.rowVerticalPadding),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing)) {
            SettingsCardIcon(icon)
            Text(title, style = AppType.bodyLarge, color = palette.textPrimary)
        }
        AbstandSegmentedControl(options, selection, label, onSelect)
    }
}

/**
 * iOS: `SettingsCardColorPickerRow` (System-`ColorPicker`) — Farbfeld rechts; Tipp öffnet einen
 * Material-Dialog mit RGB-Reglern (Android hat keinen System-Farbwähler). [onReset] zeigt
 * zusätzlich „Default“ (iOS: `resetAppearanceAccentToDefault`).
 */
@Composable
fun SettingsCardColorPickerRow(
    icon: ImageVector,
    title: String,
    color: Color,
    onColorChange: (Color) -> Unit,
    onReset: (() -> Unit)? = null,
) {
    var open by remember { mutableStateOf(false) }
    SettingsRow(Modifier.clickable { open = true }) {
        SettingsCardIcon(icon)
        Text(title, style = AppType.bodyLarge, color = Theme.palette.textPrimary, modifier = Modifier.weight(1f))
        Box(
            Modifier.size(ColorSwatchSize).background(color, CircleShape)
                .border(AppTheme.Layout.hairlineWidth, Theme.palette.textSecondary.copy(alpha = 0.4f), CircleShape),
        )
    }
    if (open) AbstandColorDialog(title, color, onDismiss = { open = false }, onConfirm = { onColorChange(it); open = false }, onReset = onReset?.let { { it(); open = false } })
}

@Composable
private fun AbstandColorDialog(title: String, initial: Color, onDismiss: () -> Unit, onConfirm: (Color) -> Unit, onReset: (() -> Unit)?) {
    var r by remember { mutableStateOf(initial.red) }
    var g by remember { mutableStateOf(initial.green) }
    var b by remember { mutableStateOf(initial.blue) }
    val palette = Theme.palette
    AbstandDialog(
        title = title,
        onDismiss = onDismiss,
        confirmLabel = "Done",
        onConfirm = { onConfirm(Color(r, g, b)) },
        dismissOnConfirm = false,
        neutralLabel = if (onReset != null) "Default" else null,
        onNeutral = onReset,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Box(Modifier.size(ColorPreviewSize).background(Color(r, g, b), CircleShape))
            }
            ChannelSlider("Red", r) { r = it }
            ChannelSlider("Green", g) { g = it }
            ChannelSlider("Blue", b) { b = it }
        }
    }
}

@Composable
private fun ChannelSlider(label: String, value: Float, onChange: (Float) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing)) {
        Text(label, style = AppType.bodySmall, color = Theme.palette.textSecondary, modifier = Modifier.width(AppTheme.Layout.metaValueColumnMinWidth / 2))
        Slider(
            value = value, onValueChange = onChange, modifier = Modifier.weight(1f),
            colors = SliderDefaults.colors(thumbColor = Theme.accent, activeTrackColor = Theme.accent),
        )
        Text("${(value * 255).toInt()}", style = AppType.bodySmall, color = Theme.palette.textSecondary, textAlign = TextAlign.End,
            modifier = Modifier.width(AppTheme.Layout.compactIconButtonSize))
    }
}

/** iOS: `SettingsCardSecureFieldRow` — Titel links, maskierte Eingabe rechts (max. 180 dp). */
@Composable
fun SettingsCardSecureFieldRow(
    icon: ImageVector,
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String = "••••••••",
) {
    val palette = Theme.palette
    SettingsRow {
        SettingsCardIcon(icon)
        Text(title, style = AppType.bodyLarge, color = palette.textPrimary, modifier = Modifier.weight(1f))
        Box(Modifier.widthIn(max = InputFieldMaxWidth), contentAlignment = Alignment.CenterEnd) {
            if (value.isEmpty()) Text(placeholder, style = AppType.bodyLarge, color = palette.textSecondary.copy(alpha = 0.55f))
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = AppType.bodyLarge.copy(color = palette.textPrimary, textAlign = TextAlign.End),
                cursorBrush = SolidColor(Theme.accent),
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = title },
            )
        }
    }
}

/**
 * iOS: `SettingsCardStepperRow` — Titel, Wertlabel (`metaValueColumnMinWidth`, rechtsbündig)
 * und −/+ als Tonal-[AbstandIconButton]s (iOS-`Stepper`).
 */
@Composable
fun SettingsCardStepperRow(
    icon: ImageVector,
    title: String,
    valueLabel: String,
    value: Int,
    range: IntRange,
    onValueChange: (Int) -> Unit,
    step: Int = 1,
) {
    val palette = Theme.palette
    SettingsRow {
        SettingsCardIcon(icon)
        Text(title, style = AppType.bodyLarge, color = palette.textPrimary, modifier = Modifier.weight(1f))
        Text(
            valueLabel, style = AppType.bodyMedium.copy(fontFeatureSettings = "tnum"), color = palette.textSecondary,
            textAlign = TextAlign.End, modifier = Modifier.widthIn(min = AppTheme.Layout.metaValueColumnMinWidth),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
            AbstandIconButton(
                SF.minus, "Decrease", onClick = { onValueChange((value - step).coerceIn(range)) }, enabled = value > range.first,
                style = AbstandIconButtonStyle.Tonal, size = AppTheme.Layout.compactIconButtonSize, containerColor = palette.background,
            )
            AbstandIconButton(
                SF.plus, "Increase", onClick = { onValueChange((value + step).coerceIn(range)) }, enabled = value < range.last,
                style = AbstandIconButtonStyle.Tonal, size = AppTheme.Layout.compactIconButtonSize, containerColor = palette.background,
            )
        }
    }
}

/**
 * iOS: `SettingsCardActionRow` — Aktionszeile (Clear cache, Log out, …). [tint] färbt Symbol +
 * Titel (z. B. [AppTheme.danger]); [isBusy] ersetzt das Endsymbol durch einen Spinner.
 */
@Composable
fun SettingsCardActionRow(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
    subtitle: String? = null,
    trailingIcon: ImageVector? = null,
    tint: Color? = null,
    enabled: Boolean = true,
    isBusy: Boolean = false,
) {
    val palette = Theme.palette
    SettingsRow(Modifier.clickable(enabled = enabled && !isBusy, onClick = onClick), enabled = enabled, twoLine = subtitle != null) {
        SettingsCardIcon(icon, tint)
        RowTitles(title, subtitle, tint ?: palette.textPrimary, titleMedium = true, modifier = Modifier.weight(1f))
        if (isBusy) {
            AbstandInlineSpinner()
        } else if (trailingIcon != null) {
            Icon(trailingIcon, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(TrailingIconSize))
        }
    }
}

/** iOS: `SettingsCardInfoRow` — reine Anzeigezeile (Wert, Status), Untertitel max. 2 Zeilen. */
@Composable
fun SettingsCardInfoRow(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    trailingIcon: ImageVector? = null,
    trailingTint: Color? = null,
) {
    val palette = Theme.palette
    SettingsRow(twoLine = subtitle != null) {
        SettingsCardIcon(icon)
        RowTitles(title, subtitle, palette.textPrimary, titleMedium = true, modifier = Modifier.weight(1f), subtitleMaxLines = 2)
        if (trailingIcon != null) {
            Icon(trailingIcon, contentDescription = null, tint = trailingTint ?: palette.textSecondary, modifier = Modifier.size(TrailingIconSize))
        }
    }
}

/** iOS: `SettingsMetricCard` — kompakte Info-Karte (Symbol, Titel oben, Wert unten). */
@Composable
fun SettingsMetricCard(icon: ImageVector, title: String, value: String, modifier: Modifier = Modifier, tint: Color? = null) {
    val palette = Theme.palette
    AbstandGroupedCard(modifier) {
        Row(
            Modifier.abstandCardListRowFrame().padding(vertical = AppTheme.Layout.rowVerticalPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
        ) {
            Box(Modifier.width(AppTheme.Layout.settingsIconColumnWidth), contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = null, tint = tint ?: Theme.accent)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
                Text(title, style = AppType.labelMedium, color = palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(value.ifEmpty { "—" }, style = AppType.titleMedium.bold, color = palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** iOS: `ServerAdminMetricTile` — gleich hohe Kachel (Wert groß, Label darunter). */
@Composable
fun ServerAdminMetricTile(value: String, label: String, modifier: Modifier = Modifier, valueColor: Color? = null) {
    val palette = Theme.palette
    AbstandGroupedCard(modifier, horizontalPadding = AppTheme.Layout.inlineSpacing, verticalPadding = AppTheme.Layout.cardPadding) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing),
        ) {
            Text(value.ifEmpty { "—" }, style = AppType.titleLarge.bold, color = valueColor ?: palette.textPrimary, maxLines = 1)
            Text(label, style = AppType.bodySmall, color = palette.textSecondary, textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}

