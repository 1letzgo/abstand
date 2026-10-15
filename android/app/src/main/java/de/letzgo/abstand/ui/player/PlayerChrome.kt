package de.letzgo.abstand.ui.player

import de.letzgo.abstand.ui.AppTheme
import android.os.SystemClock
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.swiftTrim
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flow
import java.text.NumberFormat
import kotlin.math.abs

/**
 * iOS: `MiniPlayerMetrics` / `PlayerChromeLayout` / `FullPlayerUtilityBarLayout` — benannte
 * Player-Maße. Android: Material-3-Raster (64-dp-Mini-Player, 48-dp-Touch-Ziele, Shape-Skala).
 */
object MiniPlayerMetrics {
    /** Cover in der Leiste (M3-Listen-Bild: 48 dp in 64-dp-Zeile; iOS 32 pt). */
    val tabAccessoryCover = 48.dp
    /** Höhe der Mini-Player-Leiste (M3: 64 dp; iOS 48 pt + 16 Marge). */
    val barHeight = 64.dp
    /** Tippbare Fläche der Zeile (M3-Touch-Ziel). */
    val rowMinHeight = AppTheme.Layout.minTapTarget
    /** Transport-Knöpfe der Leiste (Touch-Ziel). */
    val accessoryTransportSide = AppTheme.Layout.minTapTarget
    /** Play-Kapsel der Leiste (iOS 52 × 36; M3-Raster 56 × 40). */
    val accessoryPlayWidth = 56.dp
    val accessoryPlayHeight = AppTheme.Layout.buttonHeight
    /** Innenabstand: (64 − 48) / 2 = 8 dp um das Cover. */
    val accessoryHorizontalPadding = AppTheme.Layout.screenPadding
    /** Ecke der schwebenden Leiste (M3 large). */
    /** Angedockt (fest über der Navigation Bar): keine Ecken. */
    val accessoryCornerRadius = 0.dp
    /** Schatten der schwebenden Leiste (M3 Level 2). */
    val accessoryShadowElevation = 0.dp
    /** Fortschrittslinie am Fuß der Leiste (M3 Linear Progress). */
    val accessoryProgressHeight = 4.dp
    /** Abstand der Leiste zur Navigationsleiste. */
    /** Angedockt: kein Abstand zur Navigation Bar. */
    val accessoryBottomGap = 0.dp

    /** iOS: `fullPlayerCoverInset`. */
    val fullPlayerCoverInset = 20.dp
    /** iOS: `fullPlayerCoverCardMargin`. */
    val fullPlayerCoverCardMargin = 24.dp
    /** iOS: `titleToScrubberSpacing`. */
    val titleToScrubberSpacing = 8.dp
    /** Play/Pause-Kapsel im Vollplayer (iOS 72 pt × Touch-Höhe; M3: 96 × 56 dp). */
    val playPauseButtonWidth = 96.dp
    val playPauseButtonHeight = AppTheme.Layout.fabSize
    /** Griff zum Schließen (M3-Drag-Handle 32 × 4; iOS 36 × 5). */
    val dismissGrabberWidth = AppTheme.Layout.dragHandleWidth
    val dismissGrabberHeight = AppTheme.Layout.dragHandleHeight
    /** iOS: `fullPlayerContentMaxWidth`. */
    val fullPlayerContentMaxWidth = 800.dp
    /** Großes Cover (M3 medium). */
    val coverCornerRadius = AppTheme.Layout.cornerMedium
    /** iOS: `FullPlayerCoverOverlayMetrics.coverSurfaceCornerRadius` (M3 extra-large). */
    val coverSurfaceCornerRadius = AppTheme.Layout.cornerExtraLarge
    /** Symbole der Neben-Transportknöpfe (iOS 30 pt). */
    val transportSymbolSize = 32.dp
    /** Symbol im Play-Knopf (iOS `.largeTitle`). */
    val playSymbolSize = 36.dp
    /** iOS: `FullPlayerTransportLayout`. */
    val scrubberVerticalSpacing = 20.dp
    val spacingAbovePlayRow = 24.dp
    val spacingBelowPlayRow = 8.dp
    /** iOS: `FullPlayerUtilityBarLayout` — Zeilenhöhe = M3-Touch-Ziel. */
    val utilityPrimaryRowHeight = AppTheme.Layout.minTapTarget
    val utilityRowSpacing = 4.dp
    /** iOS: `FullPlayerProgressLayout` / `FullPlayerScrubberLayout`. */
    val progressRowHeight = 16.dp
    val progressTrackHeight = 12.dp
    val scrubThumbDiameter = 16.dp
    val scrubberBlockSpacing = 8.dp
    val scrubberPaddingAboveBar = 8.dp
    val scrubberBarToTimeSpacing = 4.dp
    /** Panel-Knöpfe über dem Cover (M3-Icon-Button-Container 40 dp, Ziel 48 dp). */
    val panelControlButtonSize = AppTheme.Layout.iconButtonSize
    /** Wischweg zum Schließen (iOS: interaktiver Zoom-Dismiss). */
    val dismissDragThreshold = 120.dp
}

/** iOS: `miniPlayerFormatPlaybackRate` — „1,25×“ im Gebietsschema. */
fun formatPlaybackRate(rate: Float): String {
    val f = NumberFormat.getNumberInstance().apply {
        minimumFractionDigits = 0
        maximumFractionDigits = 2
    }
    return "${f.format(rate.toDouble())}×"
}

/** iOS: `playerDashTitleLine` — „Show/Autor – Titel“ (bei Folgen die Show, sonst Autor). */
fun playerDashTitleLine(book: AbsBook, secondaryLine: String?): String {
    val fallback = book.displayAuthorsCardLine.swiftTrim()
    val raw = secondaryLine?.swiftTrim().orEmpty()
    val a = if (raw.isNotEmpty() && raw != "—") raw else fallback
    val t = book.displayTitle.swiftTrim()
    if (a.isEmpty() || a == "—") return t
    return "$a – $t"
}

/**
 * Positions-Drosselung wie iOS (kritisch vs. Burst): Sprünge > [jumpSeconds] (Seek, Kapitelwechsel,
 * Laden) sofort, laufende Ticks höchstens alle [periodMs] — sonst rekomponiert jede Leiste 10×/s.
 */
fun StateFlow<Double>.throttledPosition(periodMs: Long, jumpSeconds: Double = 2.0): Flow<Double> = flow {
    var last = Double.NaN
    var lastAt = 0L
    collect { v ->
        val now = SystemClock.uptimeMillis()
        if (last.isNaN() || abs(v - last) > jumpSeconds || now - lastAt >= periodMs) {
            last = v
            lastAt = now
            emit(v)
        }
    }
}

@Composable
fun rememberThrottledPosition(source: StateFlow<Double>, periodMs: Long): State<Double> {
    val flow = remember(source, periodMs) { source.throttledPosition(periodMs) }
    return flow.collectAsState(initial = source.value)
}

/**
 * iOS: `NowPlayingZoomSource` — Bildschirmrahmen der Mini-Player-Leiste, aus der der Vollplayer
 * wächst und in die er beim Schließen zurückschrumpft. `null` = Leiste nicht sichtbar.
 */
object NowPlayingZoomSource {
    var bounds by mutableStateOf<Rect?>(null)
}
