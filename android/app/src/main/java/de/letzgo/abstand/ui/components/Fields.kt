package de.letzgo.abstand.ui.components

import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
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
import de.letzgo.abstand.ui.medium

/** M3-Textfeld: 16 dp Innenabstand (mit `bodyLarge` 56 dp hoch; iOS: 12 pt). */
private val FieldInnerPadding = 16.dp

/**
 * iOS: `abstandSearchFieldChrome()` — Android: M3 Search Bar (`palette.card`, volle Rundung,
 * 56 dp hoch, 16 dp seitlich) um selbst gebaute Eingabezeilen (Symbol + Feld).
 */
fun Modifier.abstandSearchFieldChrome(): Modifier = composed {
    // Gleiche Form/Höhe wie die Bereichs-Pills der Kopfzeilen (AbstandChipShape, `activeHeight`).
    height(AppTheme.ExpandingDock.activeHeight).clip(AbstandChipShape).background(Theme.palette.scheme.surfaceContainerHigh)
        .padding(horizontal = AppTheme.ExpandingDock.activeLeadingPadding)
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
        Text(title, style = AppType.labelMedium, color = palette.textSecondary)
        Row(
            Modifier.fillMaxWidth().clip(AbstandFieldShape).background(palette.card),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                enabled = enabled,
                singleLine = true,
                textStyle = AppType.labelLarge.copy(color = palette.textPrimary),
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
                AbstandIconButton(
                    if (revealed) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                    if (revealed) "Hide password" else "Show password",
                    onClick = { revealed = !revealed },
                    tint = palette.textSecondary,
                )
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
    /** Fokus von außen setzen (z. B. Autofokus beim Öffnen der Suche). */
    focusRequester: FocusRequester? = null,
) {
    val palette = Theme.palette
    Row(
        modifier.fillMaxWidth().abstandSearchFieldChrome(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.ExpandingDock.iconLabelSpacing),
    ) {
        Icon(SF.magnifyingglass, contentDescription = null, tint = Theme.accent, modifier = Modifier.size(SearchIconSize))
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) Text(placeholder, style = AppType.labelLarge, color = palette.textSecondary, maxLines = 1)
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = AppType.labelLarge.copy(color = palette.textPrimary),
                cursorBrush = SolidColor(Theme.accent),
                keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSubmit?.invoke() }),
                modifier = Modifier
                    .fillMaxWidth()
                    .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
                    .semantics { contentDescription = placeholder },
            )
        }
        if (query.isNotEmpty()) {
            Icon(
                SF.xmarkCircleFill,
                contentDescription = "Clear",
                tint = palette.textSecondary,
                modifier = Modifier.size(SearchIconSize).clip(CircleShape).clickable { onQueryChange("") },
            )
        }
    }
}

/** Symbolgröße im Suchfeld (wie in den Bereichs-Pills). */
private val SearchIconSize = AppTheme.ExpandingDock.iconSize

