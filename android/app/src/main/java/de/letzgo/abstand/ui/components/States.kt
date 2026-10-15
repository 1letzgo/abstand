package de.letzgo.abstand.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.Theme

/**
 * iOS: `TabContentSectionTitle` — **die** Sektionsüberschrift für Tabs, Settings und Details
 * (M3 `titleLarge`, `textPrimary`, als Überschrift ausgezeichnet; iOS: `.title3.bold()`).
 */
@Composable
fun TabContentSectionTitle(title: String, modifier: Modifier = Modifier) {
    AbstandSectionHeader(title, modifier)
}

/**
 * Die eine Abschnittsüberschrift der App (M3-Listen-Subheader: `titleSmall` in Akzentfarbe, an der
 * Karteninnenkante eingerückt). Genutzt von [TabContentSectionTitle] (Home-Regale, Stats, Bereiche)
 * und `ServerAdminSection` (Settings) — alle Ansichten haben so dieselben Überschriften.
 */
@Composable
fun AbstandSectionHeader(title: String, modifier: Modifier = Modifier) {
    Text(
        title,
        style = AppType.titleSmall,
        color = Theme.accent,
        modifier = modifier
            .fillMaxWidth()
            .padding(top = AppTheme.Layout.stackSpacing, start = AppTheme.Layout.settingsCardInsetHPadding)
            .semantics { heading() },
    )
}

/**
 * iOS: `AbstandSectionEmptyState` — Leerzustand **innerhalb** einer Sektion/Liste (eine Zeile,
 * kein Symbol). [isStandalone] = Scroll-Bereich ohne umgebende Sektion (großzügigeres Padding).
 */
@Composable
fun AbstandSectionEmptyState(text: String, modifier: Modifier = Modifier, isStandalone: Boolean = false) {
    Text(
        text,
        style = AppType.bodyMedium,
        color = Theme.palette.textSecondary,
        modifier = modifier.fillMaxWidth().padding(
            vertical = if (isStandalone) AppTheme.Layout.emptyStateVerticalPadding else AppTheme.Layout.rowVerticalPadding,
        ),
    )
}

/** iOS: `AbstandCardEmptyState` — Leerzustand **in einer Karte** (Titel + optionale Erklärzeile). */
@Composable
fun AbstandCardEmptyState(title: String, modifier: Modifier = Modifier, message: String? = null) {
    val palette = Theme.palette
    Column(
        modifier.abstandCardListRowFrame(),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing, Alignment.CenterVertically),
    ) {
        Text(title, style = AppType.bodyLarge, color = palette.textPrimary)
        if (message != null) Text(message, style = AppType.bodySmall, color = palette.textSecondary)
    }
}

/**
 * iOS: `ContentUnavailableView` — ganzer Screen/Panel leer: Symbol, Titel, Beschreibung und
 * optionale Aktionen (z. B. [AbstandProminentButton]), mittig.
 */
@Composable
fun AbstandEmptyScreen(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    description: String? = null,
    actions: (@Composable ColumnScope.() -> Unit)? = null,
) {
    val palette = Theme.palette
    Column(
        modifier.fillMaxSize().padding(horizontal = AppTheme.Layout.modalHorizontalPadding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(EmptyScreenIconSize))
            Box(Modifier.padding(top = AppTheme.Layout.stackSpacing))
        }
        Text(
            title, style = AppType.headlineSmall, color = palette.textPrimary, textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        if (description != null) {
            Text(
                description, style = AppType.bodyMedium, color = palette.textSecondary, textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = AppTheme.Layout.stackSpacing),
            )
        }
        if (actions != null) {
            Column(
                Modifier.padding(top = AppTheme.Layout.blockSpacing),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing),
                content = actions,
            )
        }
    }
}

/** Symbolgröße in [AbstandEmptyScreen] (iOS `ContentUnavailableView`: ~48 pt). */
private val EmptyScreenIconSize = 48.dp

/** iOS: `AbstandInlineNotice` — kurzer Hinweis/Fehler in Karte oder Sektion (`footnote`). */
@Composable
fun AbstandInlineNotice(text: String, modifier: Modifier = Modifier, isError: Boolean = false) {
    Text(
        text,
        style = AppType.bodySmall,
        color = if (isError) AppTheme.danger else Theme.palette.textSecondary,
        modifier = modifier.fillMaxWidth(),
    )
}

/**
 * Spinner-Größen (iOS: `ControlSize` von `ProgressView` 16/20/37 pt). Android: M3-Raster —
 * Large = M3-Standard (48 dp, 4 dp Strich).
 */
enum class AbstandSpinnerSize(val diameter: Dp, val strokeWidth: Dp) {
    Small(20.dp, 2.dp),
    Regular(32.dp, 3.dp),
    Large(48.dp, 4.dp),
}

/**
 * iOS: `AbstandLoadingSpinner` — zentrierter Spinner in Listen/Sheets (Akzentfarbe, volle
 * Breite, vertikales Padding `loadingVerticalPadding`). Nie rohes `CircularProgressIndicator`.
 */
@Composable
fun AbstandLoadingSpinner(
    modifier: Modifier = Modifier,
    size: AbstandSpinnerSize = AbstandSpinnerSize.Large,
    verticalPadding: Dp = AppTheme.Layout.loadingVerticalPadding,
    scale: Float = 1f,
) {
    Box(modifier.fillMaxWidth().padding(vertical = verticalPadding), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(
            color = Theme.accent,
            strokeWidth = size.strokeWidth,
            modifier = Modifier.size(size.diameter).scale(scale),
        )
    }
}

/**
 * Kleiner Inline-Spinner in Buttons/Zeilen (iOS: `ProgressView().controlSize(.small)`).
 * [color] `null` = Akzent; [size]/[strokeWidth] für Transport-Knöpfe (Spinner auf Akzentfläche).
 */
@Composable
fun AbstandInlineSpinner(
    modifier: Modifier = Modifier,
    color: Color? = null,
    size: Dp = AbstandSpinnerSize.Small.diameter,
    strokeWidth: Dp = AbstandSpinnerSize.Small.strokeWidth,
) {
    CircularProgressIndicator(
        color = color ?: Theme.accent,
        strokeWidth = strokeWidth,
        modifier = modifier.size(size),
    )
}

/**
 * iOS: `AbstandLabeledLoadingState` — ganzflächiger Ladezustand mit optionalem Hinweistext
 * (Spinner + Label mittig, `subheadline`/`textSecondary`).
 */
@Composable
fun AbstandLabeledLoadingState(
    modifier: Modifier = Modifier,
    text: String = "",
    size: AbstandSpinnerSize = AbstandSpinnerSize.Regular,
) {
    Column(
        modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing, Alignment.CenterVertically),
    ) {
        CircularProgressIndicator(color = Theme.accent, strokeWidth = size.strokeWidth, modifier = Modifier.size(size.diameter))
        if (text.isNotEmpty()) {
            Text(text, style = AppType.bodyMedium, color = Theme.palette.textSecondary, textAlign = TextAlign.Center)
        }
    }
}

