package de.letzgo.abstand.ui.components

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.semibold

/** iOS: `AbstandPrimaryButtonStyle.fillOpacity` — deaktiviert 35 % Akzent. */
private const val DisabledFillOpacity = 0.35f
/** Icon-Größe in Button-Labels (iOS: SF-Symbol in `.body`). */
private val ButtonIconSize = 20.dp
/** iOS: `.padding(.vertical, 14)` im Primary-Style. */
private val PrimaryVerticalPadding = 14.dp
/** iOS: `.padding(.horizontal, 14)` / `.padding(.vertical, 8)` im Prominent-Style. */
private val ProminentHorizontalPadding = 14.dp
private val ProminentVerticalPadding = 8.dp

@Composable
private fun accentButtonColors() = ButtonDefaults.buttonColors(
    containerColor = Theme.accent,
    contentColor = Theme.onAccent,
    disabledContainerColor = Theme.accent.copy(alpha = DisabledFillOpacity),
    disabledContentColor = Theme.onAccent,
)

/**
 * iOS: `AbstandPrimaryButtonStyle` — vollbreite Primäraktion (Login, Bestätigen) in
 * Akzentfarbe, `body.semibold`, Ecken `cardCornerRadius`. Material-`Button` mit Ripple
 * statt iOS-Druckskalierung.
 */
@Composable
fun AbstandPrimaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        enabled = enabled,
        shape = RoundedCornerShape(AppTheme.Layout.cardCornerRadius),
        colors = accentButtonColors(),
        contentPadding = PaddingValues(horizontal = AppTheme.Layout.cardPadding, vertical = PrimaryVerticalPadding),
    ) {
        ProvideTextStyle(IosType.body.semibold) { content() }
    }
}

/** [AbstandPrimaryButton] mit Text (+ optionalem Symbol) — häufigster Fall. */
@Composable
fun AbstandPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    isBusy: Boolean = false,
) {
    AbstandPrimaryButton(onClick, modifier, enabled = enabled && !isBusy) {
        ButtonLabel(text, icon, isBusy)
    }
}

/**
 * iOS: `AbstandProminentButtonStyle` — kompakte Akzentaktion (Suche, Subscribe, Retry).
 * [capsule] = Kapselform ohne Extra-Padding (Transport-Play u. ä.; Label liefert die Größe).
 */
@Composable
fun AbstandProminentButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    capsule: Boolean = false,
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        shape = if (capsule) CircleShape else RoundedCornerShape(AppTheme.Layout.cardCornerRadius),
        colors = accentButtonColors(),
        contentPadding = if (capsule) PaddingValues(0.dp) else PaddingValues(
            horizontal = ProminentHorizontalPadding, vertical = ProminentVerticalPadding,
        ),
    ) {
        ProvideTextStyle(IosType.body.semibold) { content() }
    }
}

/** [AbstandProminentButton] mit Text (+ optionalem Symbol). */
@Composable
fun AbstandProminentButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    isBusy: Boolean = false,
) {
    AbstandProminentButton(onClick, modifier, enabled = enabled && !isBusy) {
        ButtonLabel(text, icon, isBusy)
    }
}

/** iOS: `Label(title, systemImage:)` in Buttons — Spinner ersetzt das Symbol, solange [isBusy]. */
@Composable
private fun RowScope.ButtonLabel(text: String, icon: ImageVector?, isBusy: Boolean) {
    if (isBusy) {
        AbstandInlineSpinner(color = Theme.onAccent)
        Spacer(Modifier.size(AppTheme.Layout.inlineSpacing))
    } else if (icon != null) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(ButtonIconSize))
        Spacer(Modifier.size(AppTheme.Layout.inlineSpacing))
    }
    Text(text)
}

