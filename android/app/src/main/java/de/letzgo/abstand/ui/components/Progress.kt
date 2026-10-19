package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.Theme

// Fortschrittsanzeigen: ein Balken ([AbstandProgressBar]) für Karten, Zeilen, Downloads und
// Mini-Player; ein Ring ([AbstandProgressRing]) für Download-Status auf Covern/Toolbars.

/** Standardmaße der Fortschrittsanzeigen. */
object AbstandProgressMetrics {
    /** Dünner Balken in Zeilen/Downloads (iOS: `ProgressView(.linear)` ≈ 4 pt). */
    val barHeight = 4.dp
    /** Strichstärke des Download-Rings (M3 Circular Progress: 4 dp). */
    val ringStrokeWidth = 4.dp
    /** Dünnere Strichstärke für Mini-Ringe (12 dp auf Cover-Pillen), wo 4 dp den Ring zulaufen ließen. */
    val miniRingStrokeWidth = 2.dp
    /** Standard-Ringgröße in Toolbars/Zeilen (= M3-Symbol 24 dp). */
    val ringSize = AppTheme.Layout.iconSize
}

/**
 * **Der** lineare Fortschrittsbalken: Spur [trackColor] (Standard `palette.progressTrack`),
 * Füllung [fillColor] (Standard Akzent). [shape] `CircleShape` = abgerundet (Standard),
 * `RectangleShape` für Kartenränder. [value] wird auf 0…1 begrenzt.
 */
@Composable
fun AbstandProgressBar(
    value: Double,
    modifier: Modifier = Modifier,
    height: Dp = AbstandProgressMetrics.barHeight,
    trackColor: Color = Theme.palette.progressTrack,
    fillColor: Color = Theme.accent,
    shape: Shape = CircleShape,
    contentDescription: String = "Progress",
) {
    val t = value.coerceIn(0.0, 1.0).toFloat()
    val percent = (t * 100).toInt()
    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(shape)
            .background(trackColor)
            .semantics {
                this.contentDescription = contentDescription
                stateDescription = "$percent percent"
            },
    ) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(t).clip(shape).background(fillColor))
    }
}

/**
 * Bestimmter Fortschrittsring (laufender Download). M3: 4-dp-Strich, [color] Standard Akzent,
 * Spur [trackColor] Standard `secondaryContainer`. Für unbestimmtes Laden
 * [AbstandInlineSpinner]/[AbstandLoadingSpinner] nehmen.
 */
@Composable
fun AbstandProgressRing(
    value: Double,
    modifier: Modifier = Modifier,
    color: Color = Theme.accent,
    size: Dp = AbstandProgressMetrics.ringSize,
    strokeWidth: Dp = AbstandProgressMetrics.ringStrokeWidth,
    trackColor: Color = Theme.palette.scheme.secondaryContainer,
    contentDescription: String? = null,
) {
    CircularProgressIndicator(
        progress = { value.toFloat().coerceIn(0f, 1f) },
        color = color,
        strokeWidth = strokeWidth,
        trackColor = trackColor,
        modifier = modifier.size(size).let { m ->
            if (contentDescription != null) m.semantics { this.contentDescription = contentDescription } else m
        },
    )
}
