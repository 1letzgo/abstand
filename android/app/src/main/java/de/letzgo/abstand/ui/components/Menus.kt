package de.letzgo.abstand.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme

// iOS: SwiftUI `Menu` mit `Button`/`Picker`/`Section`/`Divider`/`role: .destructive`.
// **Jedes** Menü der App läuft über [AbstandMenu] — nie rohes `DropdownMenu` bauen.

/** Maße des Menü-Chromes (iOS-Kontextmenü: ~250 pt breit, 44 pt Zeilen). */
object AbstandMenuMetrics {
    /** Mindestbreite des Menüs (Material: 112 dp — zu schmal für „Sort by“-Listen). */
    val minWidth = 200.dp
    /** Symbolgröße in Menüzeilen. */
    val iconSize = 20.dp
    /** Container-Form (Karten-Ecken). */
    val shape: Shape = RoundedCornerShape(AppTheme.Layout.cardCornerRadius)
    /** Deckkraft deaktivierter Einträge (wie Settings-Zeilen). */
    const val disabledOpacity = 0.45f
}

/**
 * Inhalt eines [AbstandMenu] (DSL wie `LazyListScope`): [item], [section], [picker], [divider].
 * Einträge schließen das Menü nach dem Tippen selbst.
 */
@Stable
class AbstandMenuScope internal constructor(private val dismiss: () -> Unit) {

    /**
     * Ein Menüeintrag — optionales Symbol links, Häkchen in Akzentfarbe rechts bei [selected],
     * [destructive] = `AppTheme.danger` (iOS: `role: .destructive`).
     */
    @Composable
    fun item(
        label: String,
        onClick: () -> Unit,
        icon: ImageVector? = null,
        selected: Boolean = false,
        destructive: Boolean = false,
        enabled: Boolean = true,
    ) {
        val palette = Theme.palette
        val color = if (destructive) AppTheme.danger else palette.textPrimary
        Row(
            Modifier
                .widthIn(min = AbstandMenuMetrics.minWidth)
                .heightIn(min = AppTheme.Layout.minTapTarget)
                .clickable(enabled = enabled, role = Role.Button) {
                    dismiss()
                    onClick()
                }
                .semantics { this.selected = selected }
                .alpha(if (enabled) 1f else AbstandMenuMetrics.disabledOpacity)
                .padding(horizontal = AppTheme.Layout.screenPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
        ) {
            if (icon != null) {
                Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(AbstandMenuMetrics.iconSize))
            }
            Text(
                label, style = IosType.body, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (selected) {
                Icon(SF.checkmark, contentDescription = "Selected", tint = Theme.accent, modifier = Modifier.size(AbstandMenuMetrics.iconSize))
            } else {
                Spacer(Modifier.width(AbstandMenuMetrics.iconSize))
            }
        }
    }

    /** Abschnitt mit optionaler Überschrift (iOS: `Section("…")` / `Picker`-Titel im Menü). */
    @Composable
    fun section(title: String?, content: @Composable AbstandMenuScope.() -> Unit) {
        if (title != null) {
            Text(
                title,
                style = IosType.footnote,
                color = Theme.palette.textSecondary,
                maxLines = 1,
                modifier = Modifier
                    .widthIn(min = AbstandMenuMetrics.minWidth)
                    .padding(
                        start = AppTheme.Layout.screenPadding, end = AppTheme.Layout.screenPadding,
                        top = AppTheme.Layout.compactSpacing, bottom = AppTheme.Layout.tightSpacing,
                    )
                    .semantics { heading() },
            )
        }
        content()
    }

    /** Einzelauswahl als Abschnitt (iOS: `Picker` im `Menu`) — Häkchen an [selected]. */
    @Composable
    fun <T> picker(
        options: List<T>,
        selected: T?,
        label: (T) -> String,
        onSelect: (T) -> Unit,
        title: String? = null,
        icon: ((T) -> ImageVector?)? = null,
    ) {
        section(title) {
            options.forEach { option ->
                item(label(option), onClick = { onSelect(option) }, icon = icon?.invoke(option), selected = option == selected)
            }
        }
    }

    /** Trenner zwischen Gruppen (iOS: `Divider()` im Menü). */
    @Composable
    fun divider() {
        HorizontalDivider(
            Modifier.widthIn(min = AbstandMenuMetrics.minWidth).padding(vertical = AppTheme.Layout.tightSpacing),
            thickness = AppTheme.Layout.hairlineStrokeWidth,
            color = Theme.palette.textSecondary.copy(alpha = 0.25f),
        )
    }
}

/**
 * Menü-Chrome der App: Karte (`palette.card`, Karten-Ecken, Karten-Schatten, Hairline-Kante),
 * Inhalt per [AbstandMenuScope]. Verankert am umgebenden `Box` (wie Material-`DropdownMenu`).
 */
@Composable
fun AbstandMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    offset: DpOffset = DpOffset.Zero,
    content: @Composable AbstandMenuScope.() -> Unit,
) {
    val palette = Theme.palette
    val scope = remember(onDismiss) { AbstandMenuScope(onDismiss) }
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
        modifier = modifier,
        offset = offset,
        shape = AbstandMenuMetrics.shape,
        containerColor = palette.card,
        tonalElevation = 0.dp,
        shadowElevation = AppTheme.CardElevation.Hero.shadowElevation,
        border = BorderStroke(AppTheme.Layout.hairlineStrokeWidth, palette.textSecondary.copy(alpha = 0.2f)),
    ) {
        scope.content()
    }
}

/**
 * Anker + Menü in einem: [anchor] bekommt die Öffnen-Aktion (Pill, Text-Knopf, Zeile …).
 * Für Icon-Anker [AbstandMenuButton] nehmen.
 */
@Composable
fun AbstandMenuBox(
    modifier: Modifier = Modifier,
    anchor: @Composable (open: () -> Unit) -> Unit,
    content: @Composable AbstandMenuScope.() -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier) {
        anchor { expanded = true }
        AbstandMenu(expanded, { expanded = false }, content = content)
    }
}

/**
 * Symbol-Knopf, der ein [AbstandMenu] öffnet (iOS: `Menu { … } label: { Image(systemName:) }`
 * in Toolbars). [tint] `Unspecified` = Toolbar-Inhaltsfarbe.
 */
@Composable
fun AbstandMenuButton(
    icon: ImageVector,
    contentDescription: String,
    modifier: Modifier = Modifier,
    tint: Color = Color.Unspecified,
    enabled: Boolean = true,
    content: @Composable AbstandMenuScope.() -> Unit,
) {
    AbstandMenuBox(modifier, anchor = { open ->
        AbstandIconButton(icon, contentDescription, onClick = open, enabled = enabled, tint = tint)
    }, content = content)
}

/**
 * Einzelauswahl-Menü (iOS: `.pickerStyle(.menu)`-Inhalt) — eine Option je Zeile, Häkchen an
 * [selected]. Wählen schließt das Menü.
 */
@Composable
fun <T> AbstandPickerMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    options: List<T>,
    selected: T?,
    label: (T) -> String,
    onSelect: (T) -> Unit,
    title: String? = null,
    icon: ((T) -> ImageVector?)? = null,
) {
    AbstandMenu(expanded, onDismiss) { picker(options, selected, label, onSelect, title, icon) }
}

/** Wert + Auf/Ab-Chevron als Anker eines Menü-Pickers (iOS: Menü-Picker-Label). */
@Composable
fun AbstandMenuValueLabel(text: String, color: Color = Theme.palette.textPrimary) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.badgeSpacing)) {
        Text(text, style = IosType.body, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Icon(SF.chevronUpChevronDown, contentDescription = null, tint = color, modifier = Modifier.size(AbstandMenuValueChevronSize))
    }
}

private val AbstandMenuValueChevronSize = 18.dp

/**
 * Zeile „Titel links, Wert-Menü rechts“ (iOS: `Picker(.menu)` in Formularen). Gemeinsamer Kern
 * von [SettingsCardPickerRow] und [MetadataSheetMenuPicker].
 */
@Composable
fun <T> AbstandPickerValueMenu(
    selection: T,
    options: List<T>,
    label: (T) -> String,
    onSelect: (T) -> Unit,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
) {
    Box {
        AbstandMenuValueLabel(label(selection))
        AbstandPickerMenu(expanded, { onExpandedChange(false) }, options, selection, label, onSelect)
    }
}
