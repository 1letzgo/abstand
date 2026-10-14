package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
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

/** Akzent- bzw. bei [destructive] Danger-Fläche (iOS: `.environment(\.themeAccent, AppTheme.danger)`). */
@Composable
private fun accentButtonColors(destructive: Boolean = false): androidx.compose.material3.ButtonColors {
    val fill = if (destructive) AppTheme.danger else Theme.accent
    val content = if (destructive) Theme.palette.foregroundOnAccent(AppTheme.danger) else Theme.onAccent
    return ButtonDefaults.buttonColors(
        containerColor = fill,
        contentColor = content,
        disabledContainerColor = fill.copy(alpha = DisabledFillOpacity),
        disabledContentColor = content,
    )
}

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
    destructive: Boolean = false,
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        shape = if (capsule) CircleShape else RoundedCornerShape(AppTheme.Layout.cardCornerRadius),
        colors = accentButtonColors(destructive),
        contentPadding = if (capsule) PaddingValues(0.dp) else PaddingValues(
            horizontal = ProminentHorizontalPadding, vertical = ProminentVerticalPadding,
        ),
    ) {
        ProvideTextStyle(IosType.body.semibold) { content() }
    }
}

/** [AbstandProminentButton] mit Text (+ optionalem Symbol); [destructive] = Danger-Fläche. */
@Composable
fun AbstandProminentButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    isBusy: Boolean = false,
    destructive: Boolean = false,
) {
    AbstandProminentButton(onClick, modifier, enabled = enabled && !isBusy, destructive = destructive) {
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


// MARK: - Icon-Buttons

/** Optik von [AbstandIconButton]. */
enum class AbstandIconButtonStyle {
    /** Nur Symbol (Toolbars, Zeilen-Aktionen). */
    Plain,
    /** Runde Fläche in Palettenfarbe (Stepper, Panel-Knöpfe). */
    Tonal,
    /** Runde Akzentfläche (aktiver Zustand, Primäraktion). */
    Filled,
}

/** Standardmaße für [AbstandIconButton]. */
object AbstandIconButtonDefaults {
    /** Symbolgröße (Material-Standard, iOS: SF-Symbol in `.title3`). */
    val iconSize = 24.dp
    /** Deckkraft deaktivierter Symbole. */
    const val disabledOpacity = 0.35f
}

/**
 * **Der** Icon-Button der App. [size] = Trefferfläche (`minTapTarget`, `iconButtonSize`,
 * `compactIconButtonSize`); [tint] `Unspecified` = Toolbar-/Inhaltsfarbe (Plain), Akzent (Tonal),
 * `onAccent` (Filled). [containerColor] überschreibt die Tonal-Fläche (Standard `palette.card`).
 * Deaktiviert: Symbol mit 35 % Deckkraft.
 */
@Composable
fun AbstandIconButton(
    icon: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    style: AbstandIconButtonStyle = AbstandIconButtonStyle.Plain,
    size: Dp = if (style == AbstandIconButtonStyle.Plain) AppTheme.Layout.minTapTarget else AppTheme.Layout.iconButtonSize,
    iconSize: Dp = AbstandIconButtonDefaults.iconSize,
    tint: Color = Color.Unspecified,
    containerColor: Color = Color.Unspecified,
) {
    AbstandIconButton(onClick, contentDescription, modifier, enabled, style, size, tint, containerColor) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(iconSize))
    }
}

/** [AbstandIconButton] mit freiem Inhalt (z. B. Fortschrittsring statt Symbol). */
@Composable
fun AbstandIconButton(
    onClick: () -> Unit,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    style: AbstandIconButtonStyle = AbstandIconButtonStyle.Plain,
    size: Dp = if (style == AbstandIconButtonStyle.Plain) AppTheme.Layout.minTapTarget else AppTheme.Layout.iconButtonSize,
    tint: Color = Color.Unspecified,
    containerColor: Color = Color.Unspecified,
    content: @Composable () -> Unit,
) {
    val palette = Theme.palette
    val foreground = when {
        tint != Color.Unspecified -> tint
        style == AbstandIconButtonStyle.Tonal -> Theme.accent
        style == AbstandIconButtonStyle.Filled -> Theme.onAccent
        else -> LocalContentColor.current
    }
    val container = when (style) {
        AbstandIconButtonStyle.Plain -> Color.Transparent
        AbstandIconButtonStyle.Tonal -> if (containerColor != Color.Unspecified) containerColor else palette.card
        AbstandIconButtonStyle.Filled -> if (containerColor != Color.Unspecified) containerColor else Theme.accent
    }
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(container)
            .let { m -> if (contentDescription != null) m.semantics { this.contentDescription = contentDescription } else m },
    ) {
        CompositionLocalProvider(LocalContentColor provides foreground) {
            Box(Modifier.alpha(if (enabled) 1f else AbstandIconButtonDefaults.disabledOpacity), contentAlignment = Alignment.Center) {
                content()
            }
        }
    }
}

// MARK: - Play-Pille

/** Maße der [AbstandPlayPill]. */
object AbstandPlayPillMetrics {
    /** Play/Pause-Symbol in der Pille. */
    val iconSize = 14.dp
    /** iOS: Rückfall auf den echten Player-Zustand nach optimistischem Umschalten. */
    const val optimisticResetMillis = 2_500L
}

/**
 * iOS: `LibraryRowPlayPill` / `ContinueHeroPlayPillButton` — Akzent-Kapsel mit Play/Pause und
 * optionalem [caption] (Restzeit). [isPlaying] = echter Zustand; der Tap schaltet sofort
 * optimistisch um und fällt nach 2,5 s auf [isPlaying] zurück. [height] `null` = Inhaltshöhe.
 */
@Composable
fun AbstandPlayPill(
    isPlaying: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    caption: String? = null,
    height: Dp? = null,
    captionStyle: androidx.compose.ui.text.TextStyle = IosType.subheadline.semibold,
    horizontalPadding: Dp = AppTheme.Layout.cardPadding,
) {
    var optimistic by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(isPlaying) { optimistic = null }
    LaunchedEffect(optimistic) {
        if (optimistic != null) {
            kotlinx.coroutines.delay(AbstandPlayPillMetrics.optimisticResetMillis)
            optimistic = null
        }
    }
    val showsPause = optimistic ?: isPlaying
    val onAccent = Theme.onAccent
    Row(
        modifier
            .let { if (height != null) it.height(height) else it }
            .clip(CircleShape)
            .background(Theme.accent)
            .clickable(role = Role.Button) {
                optimistic = !showsPause
                onClick()
            }
            .semantics {
                contentDescription = if (showsPause) "Pause" else "Play"
                if (caption != null) stateDescription = if (showsPause) "Playing" else "$caption left"
            }
            .padding(horizontal = horizontalPadding, vertical = if (height == null) AppTheme.Layout.stackSpacing else 0.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing),
    ) {
        Icon(if (showsPause) SF.pauseFill else SF.playFill, contentDescription = null, tint = onAccent, modifier = Modifier.size(AbstandPlayPillMetrics.iconSize))
        if (caption != null) Text(caption, style = captionStyle, color = onAccent, maxLines = 1)
    }
}

// MARK: - Text-Aktion

/**
 * Text-Knopf ohne Fläche (Dialog-/Toolbar-Aktionen, „Show all“): Akzent, [destructive] = danger,
 * [emphasized] = semibold, [compact] = `subheadline` statt `body` (Aktionen im Inhalt).
 * Ersetzt rohes `TextButton { Text(…) }`.
 */
@Composable
fun AbstandTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    destructive: Boolean = false,
    emphasized: Boolean = false,
    compact: Boolean = false,
    color: Color = Color.Unspecified,
) {
    val base = when {
        color != Color.Unspecified -> color
        destructive -> AppTheme.danger
        else -> Theme.accent
    }
    androidx.compose.material3.TextButton(onClick = onClick, enabled = enabled, modifier = modifier) {
        Text(
            text,
            style = (if (compact) IosType.subheadline else IosType.body).let { if (emphasized) it.semibold else it },
            color = if (enabled) base else Theme.palette.textSecondary.copy(alpha = 0.5f),
            maxLines = 1,
        )
    }
}
