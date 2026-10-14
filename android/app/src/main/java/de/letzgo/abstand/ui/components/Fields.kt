package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.medium

/** iOS: `.padding(12)` in Feld- und Suchfeld-Chrome. */
private val FieldInnerPadding = 12.dp

/**
 * iOS: `abstandSearchFieldChrome()` — Karte (`palette.card`) mit `fieldCornerRadius` und
 * 12 dp Innenabstand um selbst gebaute Eingabezeilen (Symbol + Feld).
 */
fun Modifier.abstandSearchFieldChrome(): Modifier = composed {
    clip(AbstandFieldShape).background(Theme.palette.card).padding(FieldInnerPadding)
}

/**
 * iOS: `AbstandLabeledTextField` — beschriftetes Eingabefeld (Login, Formulare): Label
 * `caption.medium`/`textSecondary` oben, Feld auf `palette.card` darunter. [isSecure] maskiert
 * und zeigt den Android-üblichen Sichtbarkeits-Schalter. Keine Autokorrektur/-Großschreibung
 * (wie iOS `.never`/`.autocorrectionDisabled()`).
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
) {
    val palette = Theme.palette
    var revealed by rememberSaveable { mutableStateOf(false) }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
        Text(title, style = IosType.caption.medium, color = palette.textSecondary)
        Row(
            Modifier.fillMaxWidth().clip(AbstandFieldShape).background(palette.card),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                enabled = enabled,
                singleLine = true,
                textStyle = IosType.body.copy(color = palette.textPrimary),
                cursorBrush = SolidColor(Theme.accent),
                visualTransformation = if (isSecure && !revealed) PasswordVisualTransformation() else VisualTransformation.None,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    keyboardType = keyboardType,
                    imeAction = imeAction,
                ),
                keyboardActions = KeyboardActions(onAny = { onSubmit?.invoke() }),
                modifier = Modifier.weight(1f).padding(FieldInnerPadding).semantics { contentDescription = title },
            )
            if (isSecure) {
                IconButton(onClick = { revealed = !revealed }) {
                    Icon(
                        if (revealed) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                        contentDescription = if (revealed) "Hide password" else "Show password",
                        tint = palette.textSecondary,
                    )
                }
            }
        }
    }
}

/**
 * Suchfeld im App-Stil (iOS: `HStack { Image("magnifyingglass"); TextField }.abstandSearchFieldChrome()`).
 * Löschen-Symbol erscheint bei Text.
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
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing),
    ) {
        Icon(SF.magnifyingglass, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(SearchIconSize))
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) Text(placeholder, style = IosType.body, color = palette.textSecondary)
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = IosType.body.copy(color = palette.textPrimary),
                cursorBrush = SolidColor(Theme.accent),
                keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSubmit?.invoke() }),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = placeholder },
            )
        }
        if (query.isNotEmpty()) {
            IconButton(onClick = { onQueryChange("") }, modifier = Modifier.size(AppTheme.Layout.compactIconButtonSize)) {
                Icon(SF.xmarkCircleFill, contentDescription = "Clear", tint = palette.textSecondary, modifier = Modifier.size(SearchIconSize))
            }
        }
    }
}

/** Symbolgröße im Suchfeld (iOS: SF-Symbol in `.body`). */
private val SearchIconSize = 20.dp

