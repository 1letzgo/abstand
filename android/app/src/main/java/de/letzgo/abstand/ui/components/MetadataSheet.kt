package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppTheme.CardElevation
import de.letzgo.abstand.ui.DetailMetaLabelIcon
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.medium
import de.letzgo.abstand.ui.semibold

/** iOS: `MetadataSheetMetrics` — Maße der Admin-Metadaten-Sheets. */
object MetadataSheetMetrics {
    /** Abstand zwischen Formularzeilen innerhalb einer Karte. */
    val fieldSpacing = 14.dp
    /** Innenabstand eingelassener Felder. */
    val fieldInsetH = 12.dp
    val fieldInsetV = 10.dp
    /** Hairline um eingelassene Felder. */
    const val fieldBorderOpacity = 0.18f
    /** Kartenform (wie Detail-Sektionskarte). */
    val cardShape: Shape = RoundedCornerShape(AppTheme.Layout.detailSectionCardCornerRadius)
    /** Form eingelassener Felder. */
    val fieldShape: Shape = RoundedCornerShape(AppTheme.Layout.fieldCornerRadius)
    /** iOS: `DetailMetaLayoutMetrics.labelIconSpacing` / `labelToContentSpacing`. */
    val labelIconSpacing = 5.dp
    val labelToContentSpacing = AppTheme.Layout.compactSpacing
}

/** Symbolgröße in Sektionslabels (iOS: `.caption2.weight(.semibold)`). */
private val SectionLabelIconSize = 12.dp

/**
 * iOS: `MetadataSheetSectionLabel` — Versalien-Überschrift (`footnote.semibold`, Laufweite 0,6,
 * `textSecondary`) mit optionalem Symbol aus [DetailMetaLabelIcon].
 */
@Composable
fun MetadataSheetSectionLabel(title: String, modifier: Modifier = Modifier) {
    val color = Theme.palette.textSecondary
    Row(
        modifier.fillMaxWidth().semantics { heading() },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(MetadataSheetMetrics.labelIconSpacing),
    ) {
        DetailMetaLabelIcon.icon(title)?.let { Icon(it, contentDescription = null, tint = color, modifier = Modifier.size(SectionLabelIconSize)) }
        Text(title.uppercase(), style = IosType.footnote.semibold.copy(letterSpacing = 0.6.sp), color = color)
    }
}

/** iOS: `MetadataSheetSection` — Label + Inhalt im Detail-Abstand (`withinSectionSpacing`). */
@Composable
fun MetadataSheetSection(
    title: String,
    modifier: Modifier = Modifier,
    spacing: Dp = AppTheme.Layout.withinSectionSpacing,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(spacing)) {
        MetadataSheetSectionLabel(title)
        content()
    }
}

/** iOS: `MetadataSheetCard` — Karte (`palette.card`, Detail-Ecken, `.subtle`-Schatten). */
@Composable
fun MetadataSheetCard(
    modifier: Modifier = Modifier,
    spacing: Dp = MetadataSheetMetrics.fieldSpacing,
    content: @Composable ColumnScope.() -> Unit,
) {
    AbstandCard(modifier.fillMaxWidth(), shape = MetadataSheetMetrics.cardShape, elevation = CardElevation.Subtle) {
        Column(
            Modifier.fillMaxWidth().padding(AppTheme.Layout.detailSectionCardPadding),
            verticalArrangement = Arrangement.spacedBy(spacing),
            content = content,
        )
    }
}

/** iOS: `MetadataSheetCardDivider`. */
@Composable
fun MetadataSheetCardDivider() {
    HorizontalDivider(thickness = AppTheme.Layout.hairlineStrokeWidth, color = Theme.palette.textSecondary.copy(alpha = 0.25f))
}

/** iOS: `metadataSheetFieldChrome()` — eingelassenes Feld (App-Hintergrund + Hairline). */
fun Modifier.metadataSheetFieldChrome(
    horizontalPadding: Dp = MetadataSheetMetrics.fieldInsetH,
    verticalPadding: Dp = MetadataSheetMetrics.fieldInsetV,
): Modifier = composed {
    val palette = Theme.palette
    fillMaxWidth()
        .clip(MetadataSheetMetrics.fieldShape)
        .background(palette.background)
        .border(AppTheme.Layout.hairlineWidth, palette.textSecondary.copy(alpha = MetadataSheetMetrics.fieldBorderOpacity), MetadataSheetMetrics.fieldShape)
        .padding(horizontal = horizontalPadding, vertical = verticalPadding)
}

/** iOS: `MetadataSheetFieldLabel` — Feldtitel (`caption.medium`) + optionaler Hinweis. */
@Composable
fun MetadataSheetFieldLabel(title: String, hint: String? = null) {
    val palette = Theme.palette
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = IosType.caption.medium, color = palette.textSecondary)
        if (hint != null) Text(hint, style = IosType.caption2, color = palette.textSecondary.copy(alpha = 0.7f))
    }
}

/**
 * iOS: `MetadataSheetTextField` — Label oben, eingelassenes Feld darunter. [minLines]/[maxLines]
 * ersetzen iOS `axis: .vertical` + `lineLimit`.
 */
@Composable
fun MetadataSheetTextField(
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    hint: String? = null,
    placeholder: String? = null,
    minLines: Int = 1,
    maxLines: Int = 1,
    keyboardType: KeyboardType = KeyboardType.Text,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
    autoCorrect: Boolean = true,
    imeAction: ImeAction = ImeAction.Done,
    onSubmit: (() -> Unit)? = null,
) {
    val palette = Theme.palette
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MetadataSheetMetrics.labelToContentSpacing)) {
        MetadataSheetFieldLabel(title, hint)
        Box(Modifier.metadataSheetFieldChrome()) {
            if (value.isEmpty() && placeholder != null) {
                Text(placeholder, style = IosType.body, color = palette.textSecondary.copy(alpha = 0.55f))
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = maxLines == 1,
                minLines = minLines,
                maxLines = maxLines,
                textStyle = IosType.body.copy(color = palette.textPrimary),
                cursorBrush = SolidColor(Theme.accent),
                keyboardOptions = KeyboardOptions(
                    capitalization = capitalization, autoCorrectEnabled = autoCorrect,
                    keyboardType = keyboardType, imeAction = imeAction,
                ),
                keyboardActions = KeyboardActions(onAny = { onSubmit?.invoke() }),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = title },
            )
        }
    }
}

/**
 * iOS: `MetadataSheetMenuPicker` — Titel links, Material-Dropdown rechts; neutraler Tint
 * (ein Dropdown ist kein Aufruf zur Tat).
 */
@Composable
fun <T> MetadataSheetMenuPicker(
    title: String,
    selection: T,
    options: List<T>,
    label: (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    Row(
        modifier.fillMaxWidth().clickable { expanded = true },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        Text(title, style = IosType.body, color = Theme.palette.textPrimary, modifier = Modifier.weight(1f))
        Box {
            MenuValueLabel(label(selection))
            AbstandDropdownMenu(expanded, { expanded = false }, options, selection, label) { onSelect(it); expanded = false }
        }
    }
}

/** iOS: `MetadataSheetSearchButton` — Suchaktion über volle Kartenbreite (Prominent-Stil). */
@Composable
fun MetadataSheetSearchButton(onClick: () -> Unit, title: String = "Search", enabled: Boolean = true) {
    AbstandProminentButton(title, onClick, Modifier.fillMaxWidth(), icon = SF.magnifyingglass, enabled = enabled)
}

/** iOS: `MetadataSheetToggleRow` — Titel + optionale Erläuterung, akzentgetönter Switch. */
@Composable
fun MetadataSheetToggleRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    subtitle: String? = null,
    subtitleMaxLines: Int = Int.MAX_VALUE,
) {
    val palette = Theme.palette
    Row(
        Modifier.fillMaxWidth().toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing)) {
            Text(title, style = IosType.body, color = palette.textPrimary)
            if (subtitle != null) Text(subtitle, style = IosType.caption, color = palette.textSecondary, maxLines = subtitleMaxLines)
        }
        Switch(checked = checked, onCheckedChange = null, colors = abstandSwitchColors())
    }
}
