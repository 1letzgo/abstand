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
import androidx.compose.material3.minimumInteractiveComponentSize
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
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme

/** iOS: `AbstandPrimaryButtonStyle.fillOpacity` — deaktiviert 35 % Akzent. */
private const val DisabledFillOpacity = 0.35f
/** Icon-Größe in Button-Labels (M3: 18 dp). */
private val ButtonIconSize = AppTheme.Layout.smallIconSize
/** M3 Filled Button: 24 dp seitlich, Höhe [AppTheme.Layout.buttonHeight] (40 dp). */
private val ButtonContentPadding = PaddingValues(horizontal = AppTheme.Layout.buttonHorizontalPadding)

/** Akzent- bzw. bei [destructive] Danger-Fläche (iOS: `.environment(\.themeAccent, AppTheme.danger)`). */
@Composable
private fun accentButtonColors(destructive: Boolean = false): androidx.compose.material3.ButtonColors {
    val fill = if (destructive) AppTheme.danger else Theme.accent
    val content = if (destructive) Theme.palette.foregroundOnAccent(AppTheme.danger) else Theme.onAccent
    // M3: deaktiviert = onSurface 12 % Fläche / 38 % Inhalt.
    val onSurface = Theme.palette.scheme.onSurface
    return ButtonDefaults.buttonColors(
        containerColor = fill,
        contentColor = content,
        disabledContainerColor = onSurface.copy(alpha = 0.12f),
        disabledContentColor = onSurface.copy(alpha = 0.38f),
    )
}

/**
 * iOS: `AbstandPrimaryButtonStyle` — vollbreite Primäraktion (Login, Bestätigen) in
 * Akzentfarbe. Android: M3 Filled Button (40 dp hoch, volle Rundung, `labelLarge`, 24 dp
 * seitlich), Ripple statt iOS-Druckskalierung.
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
        shape = CircleShape,
        colors = accentButtonColors(),
        contentPadding = ButtonContentPadding,
    ) {
        ProvideTextStyle(AppType.labelLarge) { content() }
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
        shape = CircleShape,
        colors = accentButtonColors(destructive),
        contentPadding = if (capsule) PaddingValues(0.dp) else ButtonContentPadding,
    ) {
        ProvideTextStyle(AppType.labelLarge) { content() }
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
    /** Symbolgröße (M3: 24 dp, iOS: SF-Symbol in `.title3`). */
    val iconSize = AppTheme.Layout.iconSize
    /** Deckkraft deaktivierter Symbole. */
    const val disabledOpacity = 0.35f
}

/**
 * **Der** Icon-Button der App (M3: 40-dp-Container, 24-dp-Symbol). [size] = sichtbarer Container
 * (`iconButtonSize`, `compactIconButtonSize`, größere Player-Knöpfe); die Trefferfläche ist immer
 * mindestens `minTapTarget` (48 dp, `minimumInteractiveComponentSize`). [tint] `Unspecified` = Toolbar-/Inhaltsfarbe (Plain), Akzent (Tonal),
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
    size: Dp = AppTheme.Layout.iconButtonSize,
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
    size: Dp = AppTheme.Layout.iconButtonSize,
    tint: Color = Color.Unspecified,
    containerColor: Color = Color.Unspecified,
    content: @Composable () -> Unit,
) {
    val palette = Theme.palette
    val foreground = when {
        tint != Color.Unspecified -> tint
        style == AbstandIconButtonStyle.Tonal -> palette.scheme.onSecondaryContainer
        style == AbstandIconButtonStyle.Filled -> Theme.onAccent
        else -> LocalContentColor.current
    }
    val container = when (style) {
        AbstandIconButtonStyle.Plain -> Color.Transparent
        AbstandIconButtonStyle.Tonal -> if (containerColor != Color.Unspecified) containerColor else palette.scheme.secondaryContainer
        AbstandIconButtonStyle.Filled -> if (containerColor != Color.Unspecified) containerColor else Theme.accent
    }
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .minimumInteractiveComponentSize()
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
    /** Play/Pause-Symbol in der Pille (M3-Button-Symbol). */
    val iconSize = AppTheme.Layout.smallIconSize
    /** iOS: Rückfall auf den echten Player-Zustand nach optimistischem Umschalten. */
    const val optimisticResetMillis = 2_500L
}

/**
 * iOS: `LibraryRowPlayPill` / `ContinueHeroPlayPillButton` — Akzent-Kapsel mit Play/Pause und
 * optionalem [caption] (Restzeit). [isPlaying] = echter Zustand; der Tap schaltet sofort
 * optimistisch um und fällt nach 2,5 s auf [isPlaying] zurück. Android: M3-Button-Maße — mit
 * [caption] 40 dp hoch (`labelLarge`, 18-dp-Symbol, 8 dp Abstand), nur Symbol 32 dp
 * (kompakte Zeilen). [height] überschreibt die Höhe.
 */
@Composable
fun AbstandPlayPill(
    isPlaying: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    caption: String? = null,
    height: Dp = if (caption != null) AppTheme.Layout.buttonHeight else AppTheme.Layout.compactIconButtonSize,
    captionStyle: androidx.compose.ui.text.TextStyle = AppType.labelLarge,
    horizontalPadding: Dp = if (caption != null) AppTheme.Layout.screenPadding else AppTheme.Layout.menuItemHorizontalPadding,
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
    // M3: mit Restzeit = Filled Button (primary), nur Symbol = Filled-Tonal-Icon-Button (secondaryContainer).
    val scheme = Theme.palette.scheme
    val container = if (caption != null) Theme.accent else scheme.secondaryContainer
    val onAccent = if (caption != null) Theme.onAccent else scheme.onSecondaryContainer
    Row(
        modifier
            .height(height)
            .clip(CircleShape)
            .background(container)
            .clickable(role = Role.Button) {
                optimistic = !showsPause
                onClick()
            }
            .semantics {
                contentDescription = if (showsPause) "Pause" else "Play"
                if (caption != null) stateDescription = if (showsPause) "Playing" else "$caption left"
            }
            // M3 Button mit Symbol: Symbolseite schmaler, Textseite + 8 dp.
            .padding(start = horizontalPadding, end = if (caption != null) horizontalPadding + AppTheme.Layout.inlineSpacing else horizontalPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing),
    ) {
        Icon(if (showsPause) SF.pauseFill else SF.playFill, contentDescription = null, tint = onAccent, modifier = Modifier.size(AbstandPlayPillMetrics.iconSize))
        if (caption != null) Text(caption, style = captionStyle, color = onAccent, maxLines = 1)
    }
}

// MARK: - Text-Aktion

/**
 * Text-Knopf ohne Fläche (Dialog-/Toolbar-Aktionen, „Show all“): Akzent, [destructive] = danger,
 * [emphasized] = semibold, [compact] = schmalerer Innenabstand (8 dp) für Aktionen im Inhalt.
 * M3 Text Button: `labelLarge`, 12 dp seitlich, 40 dp hoch. Ersetzt rohes `TextButton { Text(…) }`.
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
    androidx.compose.material3.TextButton(
        onClick = onClick, enabled = enabled, modifier = modifier,
        contentPadding = if (compact) PaddingValues(horizontal = AppTheme.Layout.inlineSpacing) else ButtonDefaults.TextButtonContentPadding,
    ) {
        Text(
            text,
            style = if (emphasized) AppType.labelLarge else AppType.labelLarge,
            color = if (enabled) base else Theme.palette.textSecondary.copy(alpha = 0.5f),
            maxLines = 1,
        )
    }
}
