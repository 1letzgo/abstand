package de.letzgo.abstand.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppTheme.CardElevation
import de.letzgo.abstand.ui.DetailMetaLabelIcon
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.medium

/** iOS: `MetadataSheetMetrics` — Maße der Admin-Metadaten-Sheets. */
object MetadataSheetMetrics {
    /** Abstand zwischen Formularzeilen innerhalb einer Karte. */
    val fieldSpacing = 16.dp
    /** Horizontaler Innenabstand eingelassener Listen (M3-Textfeld: 16 dp). */
    val fieldInsetH = 16.dp
    /** Kartenform (wie Detail-Sektionskarte). */
    val cardShape: Shape = RoundedCornerShape(AppTheme.Layout.detailSectionCardCornerRadius)
    /** Form eingelassener Felder. */
    val fieldShape: Shape = RoundedCornerShape(AppTheme.Layout.fieldCornerRadius)
    /** iOS: `DetailMetaLayoutMetrics.labelIconSpacing` / `labelToContentSpacing`. */
    val labelIconSpacing = AppTheme.Layout.tightSpacing
    val labelToContentSpacing = AppTheme.Layout.compactSpacing
}

/**
 * iOS: `MetadataSheetSectionLabel` — Versalien-Überschrift (`labelMedium`, `textSecondary`) mit optionalem Symbol aus [DetailMetaLabelIcon].
 */
@Composable
fun MetadataSheetSectionLabel(title: String, modifier: Modifier = Modifier) {
    AbstandCapsLabel(title, modifier.fillMaxWidth(), icon = DetailMetaLabelIcon.icon(title))
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
    AbstandDivider()
}

/** iOS: `MetadataSheetFieldLabel` — Feldtitel (`caption.medium`) + optionaler Hinweis. */
@Composable
fun MetadataSheetFieldLabel(title: String, hint: String? = null) {
    val palette = Theme.palette
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = AppType.labelMedium, color = palette.textSecondary)
        if (hint != null) Text(hint, style = AppType.labelSmall, color = palette.textSecondary.copy(alpha = 0.7f))
    }
}

/**
 * iOS: `MetadataSheetTextField` — Label oben, eingelassenes Feld darunter. Android: M3 Outlined
 * Text Field ([AbstandOutlinedTextField]) — [title] als schwebendes Label, [hint] als
 * Supporting Text darunter. [minLines]/[maxLines] ersetzen iOS `axis: .vertical` + `lineLimit`.
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
    errorText: String? = null,
) {
    AbstandOutlinedTextField(
        label = title, value = value, onValueChange = onValueChange, modifier = modifier,
        placeholder = placeholder, supportingText = hint, errorText = errorText,
        keyboardType = keyboardType, capitalization = capitalization, autoCorrect = autoCorrect,
        imeAction = imeAction, onSubmit = onSubmit, minLines = minLines, maxLines = maxLines,
    )
}

/**
 * Kurzes Feld ohne eigene Überschrift (Serienname/-nummer, Dialog-Eingaben): M3 Outlined Text
 * Field mit [placeholder] als schwebendem Label; [label] ist der Accessibility-Name. [centered]
 * für kurze Zahlenfelder.
 */
@Composable
fun AbstandInsetTextField(
    value: String,
    placeholder: String,
    label: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    keyboardType: KeyboardType = KeyboardType.Text,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.None,
    centered: Boolean = false,
) {
    AbstandOutlinedTextField(
        label = placeholder, value = value, onValueChange = onValueChange, modifier = modifier,
        keyboardType = keyboardType, capitalization = capitalization,
        textAlign = if (centered) TextAlign.Center else TextAlign.Start,
        contentDescription = label,
    )
}

/**
 * iOS: `MetadataSheetMenuPicker` — Titel links, [AbstandPickerValueMenu] rechts; neutraler Tint
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
        Text(title, style = AppType.bodyLarge, color = Theme.palette.textPrimary, modifier = Modifier.weight(1f))
        AbstandPickerValueMenu(selection, options, label, onSelect, expanded) { expanded = it }
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
            Text(title, style = AppType.bodyLarge, color = palette.textPrimary)
            if (subtitle != null) Text(subtitle, style = AppType.bodySmall, color = palette.textSecondary, maxLines = subtitleMaxLines)
        }
        Switch(checked = checked, onCheckedChange = null, colors = abstandSwitchColors())
    }
}
