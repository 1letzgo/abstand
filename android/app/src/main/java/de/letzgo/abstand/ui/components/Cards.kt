package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppColorPalette
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppTheme.CardElevation
import de.letzgo.abstand.ui.LocalAbstandCardShadowEnabled
import de.letzgo.abstand.ui.Theme

/** Standard-Kartenform (iOS: `RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)`). */
val AbstandCardShape: Shape = RoundedCornerShape(AppTheme.Layout.cardCornerRadius)

/** Form eingelassener Felder / Suchfeld (iOS: `fieldCornerRadius`). */
val AbstandFieldShape: Shape = RoundedCornerShape(AppTheme.Layout.fieldCornerRadius)

/**
 * iOS: `View.abstandCardElevation(_:)` — Schatten in Palettenfarbe (Hero: `heroCardShadow`,
 * sonst `cardShadow`). Abgeschaltet über [LocalAbstandCardShadowEnabled] (horizontale Reihen).
 */
fun Modifier.abstandCardElevation(
    shape: Shape = AbstandCardShape,
    elevation: CardElevation = CardElevation.Standard,
): Modifier = composed {
    if (!LocalAbstandCardShadowEnabled.current) return@composed this
    val palette = Theme.palette
    val color = if (elevation == CardElevation.Hero) palette.heroCardShadow else palette.cardShadow
    shadow(elevation.shadowElevation, shape, clip = false, ambientColor = color, spotColor = color)
}

/**
 * iOS: `View.abstandCardChrome(_:shape:elevation:)` — **einzige** Kombination aus Schatten,
 * Form und Füllung. Sonderformen (Library-Zeile, Detail-Sektion mit Cover-Tint, Popup) nutzen
 * das hier statt `shadow` + `clip` + `background` von Hand. [onClick] gibt Material-Ripple
 * innerhalb der Form (Android-Ersatz für die iOS-Button-Hülle).
 */
fun Modifier.abstandCardChrome(
    fill: Color,
    shape: Shape = AbstandCardShape,
    elevation: CardElevation = CardElevation.Standard,
    onClick: (() -> Unit)? = null,
): Modifier = this
    .abstandCardElevation(shape, elevation)
    .clip(shape)
    .background(fill)
    .let { if (onClick != null) it.clickable(onClick = onClick) else it }

/** iOS: `abstandCardListRowFrame(alignment:)` — volle Breite, Mindesthöhe `listRowMinHeight`. */
fun Modifier.abstandCardListRowFrame(): Modifier =
    fillMaxWidth().heightIn(min = AppTheme.Layout.listRowMinHeight)

/** iOS: `abstandHeroCardOutline(palette:)` — dezente Kante statt Schatten in horizontalen Reihen. */
fun Modifier.abstandHeroCardOutline(palette: AppColorPalette): Modifier = border(
    AppTheme.Layout.hairlineWidth,
    palette.scheme.outlineVariant,
    RoundedCornerShape(AppTheme.Layout.continueHeroCardCornerRadius),
)

/**
 * Material-`ElevatedCard` in abstand-Optik — Container für alle Karten mit Inhalt
 * ([AbstandGroupedCard], Detail-Sektionen, Library-Zeilen). Füllung [fill] (Standard
 * `palette.card`), Form [shape], Schatten-Stufe [elevation]; in horizontalen Reihen
 * ([LocalAbstandCardShadowEnabled] = false) ohne Schatten. [onClick] = Material-Ripple.
 * Für Nicht-Container (Bild, Box) gibt es dasselbe als Modifier [abstandCardChrome].
 */
@Composable
fun AbstandCard(
    modifier: Modifier = Modifier,
    fill: Color = Theme.palette.card,
    shape: Shape = AbstandCardShape,
    elevation: CardElevation = CardElevation.Standard,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = CardDefaults.elevatedCardColors(containerColor = fill, contentColor = Theme.palette.textPrimary)
    val dp = if (LocalAbstandCardShadowEnabled.current) elevation.shadowElevation else 0.dp
    val el = CardDefaults.elevatedCardElevation(
        defaultElevation = dp, pressedElevation = dp, focusedElevation = dp, hoveredElevation = dp, draggedElevation = dp,
    )
    if (onClick != null) {
        ElevatedCard(onClick = onClick, modifier = modifier, shape = shape, colors = colors, elevation = el, content = content)
    } else {
        ElevatedCard(modifier = modifier, shape = shape, colors = colors, elevation = el, content = content)
    }
}

/**
 * iOS: `AbstandGroupedCard` — gruppierte Kartenfläche (Settings, Stats, Admin). Zeilen liegen
 * untereinander ohne Abstand; Trenner per [SettingsCardDivider].
 */
@Composable
fun AbstandGroupedCard(
    modifier: Modifier = Modifier,
    horizontalPadding: Dp = AppTheme.Layout.settingsCardInsetHPadding,
    verticalPadding: Dp = AppTheme.Layout.settingsCardInsetVPadding,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    AbstandCard(modifier.fillMaxWidth(), onClick = onClick) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = horizontalPadding, vertical = verticalPadding),
            content = content,
        )
    }
}

/**
 * iOS: `AbstandCardBottomProgress` — Fortschrittsstreifen am unteren Kartenrand.
 * [fillColor] `null` = Akzentfarbe.
 */
@Composable
fun AbstandCardBottomProgress(
    value: Double,
    modifier: Modifier = Modifier,
    height: Dp = AppTheme.Layout.libraryRowBottomProgressHeight,
    trackColor: Color = Theme.palette.progressTrack,
    fillColor: Color? = null,
) {
    AbstandProgressBar(value, modifier, height, trackColor, fillColor ?: Theme.accent, RectangleShape)
}
