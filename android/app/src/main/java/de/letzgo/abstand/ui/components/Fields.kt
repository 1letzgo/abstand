package de.letzgo.abstand.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.TextFieldColors
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme

/**
 * iOS: `abstandSearchFieldChrome()` — Android: bewusst **kein** 56-dp-M3-Search-Bar, sondern
 * dieselbe kompakte Form wie die Bereichs-Pills der Kopfzeilen (32 dp hoch, [AbstandChipShape]
 * mit 8-dp-Ecken, `surfaceContainerHigh`, 8 dp seitlich) um selbst gebaute Eingabezeilen
 * (Symbol + Feld). Gewollte Design-Entscheidung — nicht auf 56 dp „korrigieren“.
 */
fun Modifier.abstandSearchFieldChrome(): Modifier = composed {
    // Gleiche Form/Höhe wie die Bereichs-Pills der Kopfzeilen (AbstandChipShape, `activeHeight`).
    height(AppTheme.ExpandingDock.activeHeight).clip(AbstandChipShape).background(Theme.palette.scheme.surfaceContainerHigh)
        .padding(horizontal = AppTheme.ExpandingDock.activeLeadingPadding)
}

/**
 * Kern-Vorlage für Formularfelder (M3 Outlined Text Field): Label im Feld (schwebt beim Fokus
 * bzw. mit Inhalt in die Kontur), Eingabe `bodyLarge`, Kontur 4 dp (extra-small), Fokus
 * `primary`, unfokussiert `outline`, Label `onSurfaceVariant`. [supportingText] steht unter dem
 * Feld (Hinweis/Fußnote); [errorText] setzt `isError` und ersetzt den Hinweis in `error`.
 * [isSecure] maskiert und zeigt den Android-üblichen Sichtbarkeits-Schalter; [trailing] ist ein
 * eigenes Endsymbol (nur ohne [isSecure]). [monospace] für technische Werte (Header-Namen).
 * Nur in Formularen auf Kartenflächen — die kompakte Such-Pill bleibt [AbstandSearchField].
 */
@Composable
fun AbstandOutlinedTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    supportingText: String? = null,
    errorText: String? = null,
    isSecure: Boolean = false,
    keyboardType: KeyboardType = if (isSecure) KeyboardType.Password else KeyboardType.Text,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.None,
    autoCorrect: Boolean = false,
    imeAction: ImeAction = ImeAction.Done,
    onSubmit: (() -> Unit)? = null,
    enabled: Boolean = true,
    minLines: Int = 1,
    maxLines: Int = 1,
    textAlign: TextAlign = TextAlign.Start,
    monospace: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
    /** Accessibility-Name, falls er vom sichtbaren Label abweicht (z. B. „#“ → „Series number“). */
    contentDescription: String = label,
) {
    val palette = Theme.palette
    val scheme = palette.scheme
    var revealed by rememberSaveable { mutableStateOf(false) }
    val isError = errorText != null
    val footer = errorText ?: supportingText
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth().semantics { this.contentDescription = contentDescription },
        enabled = enabled,
        textStyle = AppType.bodyLarge.copy(
            textAlign = textAlign,
            fontFamily = if (monospace && !isSecure) FontFamily.Monospace else null,
        ),
        label = { Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        placeholder = placeholder?.let { { Text(it, style = AppType.bodyLarge, maxLines = maxLines) } },
        trailingIcon = when {
            isSecure -> {
                {
                    AbstandIconButton(
                        if (revealed) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                        if (revealed) "Hide password" else "Show password",
                        onClick = { revealed = !revealed },
                        tint = scheme.onSurfaceVariant,
                    )
                }
            }
            else -> trailing
        },
        supportingText = footer?.let { { Text(it, style = AppType.bodySmall) } },
        isError = isError,
        visualTransformation = if (isSecure && !revealed) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(
            capitalization = capitalization,
            autoCorrectEnabled = autoCorrect && !isSecure,
            keyboardType = keyboardType,
            imeAction = imeAction,
        ),
        keyboardActions = KeyboardActions(onAny = { onSubmit?.invoke() ?: defaultKeyboardAction(imeAction) }),
        singleLine = maxLines == 1,
        minLines = minLines,
        maxLines = maxLines,
        shape = AbstandFieldShape,
        colors = abstandTextFieldColors(),
    )
}

/** M3-Farbrollen der Formularfelder aus `palette.scheme` (Fokus = `primary` = App-Akzent). */
@Composable
fun abstandTextFieldColors(): TextFieldColors {
    val scheme = Theme.palette.scheme
    return OutlinedTextFieldDefaults.colors(
        focusedTextColor = scheme.onSurface,
        unfocusedTextColor = scheme.onSurface,
        disabledTextColor = scheme.onSurface.copy(alpha = DisabledContentAlpha),
        errorTextColor = scheme.onSurface,
        focusedContainerColor = Color.Transparent,
        unfocusedContainerColor = Color.Transparent,
        disabledContainerColor = Color.Transparent,
        errorContainerColor = Color.Transparent,
        cursorColor = scheme.primary,
        errorCursorColor = scheme.error,
        focusedBorderColor = scheme.primary,
        unfocusedBorderColor = scheme.outline,
        disabledBorderColor = scheme.onSurface.copy(alpha = DisabledBorderAlpha),
        errorBorderColor = scheme.error,
        focusedLabelColor = scheme.primary,
        unfocusedLabelColor = scheme.onSurfaceVariant,
        disabledLabelColor = scheme.onSurface.copy(alpha = DisabledContentAlpha),
        errorLabelColor = scheme.error,
        focusedPlaceholderColor = scheme.onSurfaceVariant,
        unfocusedPlaceholderColor = scheme.onSurfaceVariant,
        focusedSupportingTextColor = scheme.onSurfaceVariant,
        unfocusedSupportingTextColor = scheme.onSurfaceVariant,
        errorSupportingTextColor = scheme.error,
        focusedTrailingIconColor = scheme.onSurfaceVariant,
        unfocusedTrailingIconColor = scheme.onSurfaceVariant,
        errorTrailingIconColor = scheme.error,
    )
}

/** M3: deaktivierter Inhalt 38 %, deaktivierte Kontur 12 %. */
private const val DisabledContentAlpha = 0.38f
private const val DisabledBorderAlpha = 0.12f

/**
 * iOS: `AbstandLabeledTextField` — beschriftetes Eingabefeld (Login, Formulare). Android: M3
 * Outlined Text Field über [AbstandOutlinedTextField] ([title] = schwebendes Label). Keine
 * Autokorrektur/-Großschreibung (wie iOS `.never`/`.autocorrectionDisabled()`).
 */
@Composable
fun AbstandLabeledTextField(
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    isSecure: Boolean = false,
    keyboardType: KeyboardType = if (isSecure) KeyboardType.Password else KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Done,
    onSubmit: (() -> Unit)? = null,
    enabled: Boolean = true,
    supportingText: String? = null,
    errorText: String? = null,
) {
    AbstandOutlinedTextField(
        label = title, value = value, onValueChange = onValueChange, modifier = modifier,
        isSecure = isSecure, keyboardType = keyboardType, imeAction = imeAction, onSubmit = onSubmit,
        enabled = enabled, supportingText = supportingText, errorText = errorText,
    )
}

/**
 * Suchfeld im App-Stil (iOS: `HStack { Image("magnifyingglass"); TextField }.abstandSearchFieldChrome()`):
 * kompakte 32-dp-Pill ([abstandSearchFieldChrome]), Lupe `onSurfaceVariant`, Eingabe `bodyLarge`
 * (passt in 32 dp), Löschen-Knopf als [AbstandIconButton] (48-dp-Trefferfläche), sobald Text da ist.
 */
@Composable
fun AbstandSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "Search",
    onSubmit: (() -> Unit)? = null,
) {
    val palette = Theme.palette
    Row(
        modifier.fillMaxWidth().abstandSearchFieldChrome(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.ExpandingDock.iconLabelSpacing),
    ) {
        Icon(SF.magnifyingglass, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(SearchIconSize))
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) Text(placeholder, style = AppType.bodyLarge, color = palette.textSecondary, maxLines = 1)
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = AppType.bodyLarge.copy(color = palette.textPrimary),
                cursorBrush = SolidColor(Theme.accent),
                keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSubmit?.invoke() }),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = placeholder },
            )
        }
        if (query.isNotEmpty()) {
            AbstandIconButton(
                SF.xmarkCircleFill,
                "Clear",
                onClick = { onQueryChange("") },
                size = AppTheme.Layout.compactIconButtonSize,
                iconSize = SearchIconSize,
                tint = palette.textSecondary,
            )
        }
    }
}

/** Symbolgröße im Suchfeld (wie in den Bereichs-Pills). */
private val SearchIconSize = AppTheme.ExpandingDock.iconSize

