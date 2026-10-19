package de.letzgo.abstand.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.semibold

// Listenzeilen, Trenner, Versalien-Labels und Segment-Umschalter.

/**
 * Generische Listenzeile: [leading] (Cover/Symbol) · Titel + Untertitel · [trailing]
 * (Aktion, Status). M3-Liste: Mindesthöhe 56 dp (mit Untertitel 72 dp), Titel `bodyLarge`,
 * Untertitel `bodyMedium`, 16 dp zwischen Leading/Text/Trailing, 8 dp oben/unten.
 * Für Zeilen in Settings-Karten die `SettingsCard*Row`s nehmen.
 */
@Composable
fun AbstandListRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    onClick: (() -> Unit)? = null,
    titleStyle: TextStyle = AppType.bodyLarge,
    titleColor: Color = Color.Unspecified,
    titleMaxLines: Int = 1,
    subtitleMaxLines: Int = 1,
    verticalPadding: Dp = AppTheme.Layout.rowVerticalPadding,
    leading: (@Composable () -> Unit)? = null,
    below: (@Composable () -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    val palette = Theme.palette
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = if (subtitle.isNullOrEmpty()) AppTheme.Layout.listItemOneLineHeight else AppTheme.Layout.listItemTwoLineHeight)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(vertical = verticalPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        leading?.invoke()
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing)) {
            Text(
                title, style = titleStyle,
                color = if (titleColor != Color.Unspecified) titleColor else palette.textPrimary,
                maxLines = titleMaxLines, overflow = TextOverflow.Ellipsis,
            )
            if (!subtitle.isNullOrEmpty()) {
                Text(subtitle, style = AppType.bodyMedium, color = palette.textSecondary, maxLines = subtitleMaxLines, overflow = TextOverflow.Ellipsis)
            }
            below?.invoke()
        }
        trailing?.invoke(this)
    }
}

/** Hairline-Trenner zwischen Listenzeilen (ohne Abstand; Settings-Karten: [SettingsCardDivider]). */
@Composable
fun AbstandDivider(modifier: Modifier = Modifier, opacity: Float = 0.2f) {
    HorizontalDivider(modifier, thickness = AppTheme.Layout.hairlineWidth, color = Theme.palette.textSecondary.copy(alpha = opacity))
}

/** Symbolgröße in [AbstandCapsLabel] (iOS: `.caption2.weight(.semibold)`). */
private val CapsLabelIconSize = 16.dp

/**
 * Meta-Überschrift (M3 `labelLarge`, normale Schreibweise statt iOS-Versalien, `textSecondary`) mit optionalem
 * Symbol — Meta-Labels in Details, Metadata-Sheets, Entity-Listen und Stats-Kacheln.
 */
@Composable
fun AbstandCapsLabel(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    color: Color = Color.Unspecified,
    maxLines: Int = 1,
) {
    val tint = if (color != Color.Unspecified) color else Theme.palette.textSecondary
    Row(
        modifier.semantics { heading() },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(MetadataSheetMetrics.labelIconSpacing),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(CapsLabelIconSize))
        Text(
            title, style = AppType.labelLarge, color = tint,
            maxLines = maxLines, overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * iOS: `LibraryRowCollapsedMetaLine` — „AUTHOR  Name“ (Label in Versalien, Wert ein-/zweizeilig).
 * Leerer Wert oder „—“ → Gedankenstrich in Label-Farbe.
 */
@Composable
fun LibraryRowCollapsedMetaLine(
    label: String,
    value: String?,
    modifier: Modifier = Modifier,
    valueMaxLines: Int = 2,
    labelColor: Color? = null,
    valueColor: Color? = null,
) {
    val palette = Theme.palette
    val line = value?.trim().orEmpty()
    val empty = line.isEmpty() || line == "—"
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
        Text(
            label,
            style = AppType.labelMedium,
            color = labelColor ?: palette.textSecondary,
            maxLines = 1,
            modifier = Modifier.alignByBaseline(),
        )
        Text(
            if (empty) "—" else line,
            style = AppType.bodySmall,
            color = if (empty) labelColor ?: palette.textSecondary else valueColor ?: palette.textPrimary,
            maxLines = valueMaxLines,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).alignByBaseline(),
        )
    }
}

/**
 * iOS: `Picker(.segmented)` — **der** Segment-Umschalter (M3 Segmented Buttons, 40 dp hoch,
 * `labelLarge`, in Akzentfarbe, volle Breite).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> AbstandSegmentedControl(
    options: List<T>,
    selection: T,
    label: (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = Theme.palette
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { index, option ->
            SegmentedButton(
                selected = option == selection,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = Theme.accent,
                    activeContentColor = Theme.onAccent,
                    activeBorderColor = Theme.accent,
                    inactiveContainerColor = palette.card,
                    inactiveContentColor = palette.textPrimary,
                    inactiveBorderColor = palette.textSecondary.copy(alpha = 0.35f),
                ),
                icon = {},
            ) { Text(label(option), style = AppType.labelLarge, maxLines = 1) }
        }
    }
}
