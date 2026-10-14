package de.letzgo.abstand.ui.player

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

/** iOS: `MiniPlayerMetrics` / `PlayerChromeLayout` / `FullPlayerUtilityBarLayout` — benannte Player-Maße. */
object MiniPlayerMetrics {
    /** iOS: `PlayerChromeLayout.tabAccessoryCover`. */
    val tabAccessoryCover = 32.dp
    /** iOS: `TabAccessoryMiniPlayer.rowMinHeight` (+ äußere Marge 16). */
    val rowMinHeight = 48.dp
    val rowMinHeightOuterMargin = 16.dp
    /** iOS: `accessoryTransportSide`. */
    val accessoryTransportSide = 44.dp
    /** iOS: Play-Kapsel der Leiste 52 × 36. */
    val accessoryPlayWidth = 52.dp
    val accessoryPlayHeight = 36.dp
    /** iOS: `accessoryHorizontalPaddingCompact`. */
    val accessoryHorizontalPadding = 12.dp
    /** Android: Kapsel-Ecke der schwebenden Leiste (iOS: System-Tab-Accessory-Kapsel). */
    val accessoryCornerRadius = 22.dp
    /** Android: Schatten der schwebenden Leiste. */
    val accessoryShadowElevation = 6.dp
    /** Android: Fortschrittslinie am Fuß der Leiste. */
    val accessoryProgressHeight = 2.dp
    /** Abstand der Leiste zur Navigationsleiste. */
    val accessoryBottomGap = 6.dp

    /** iOS: `fullPlayerCoverInset`. */
    val fullPlayerCoverInset = 20.dp
    /** iOS: `fullPlayerCoverCardMargin`. */
    val fullPlayerCoverCardMargin = 28.dp
    /** iOS: `titleToScrubberSpacing`. */
    val titleToScrubberSpacing = 8.dp
    /** iOS: `playPauseButtonWidth`. */
    val playPauseButtonWidth = 72.dp
    /** iOS: `dismissGrabberWidth`/`Height`. */
    val dismissGrabberWidth = 36.dp
    val dismissGrabberHeight = 5.dp
    /** iOS: `fullPlayerContentMaxWidth`. */
    val fullPlayerContentMaxWidth = 800.dp
    /** iOS: `DetailHeroLayoutMetrics.coverCornerRadius` für das große Cover. */
    val coverCornerRadius = 12.dp
    /** iOS: `FullPlayerCoverOverlayMetrics.coverSurfaceCornerRadius`. */
    val coverSurfaceCornerRadius = 24.dp
    /** iOS: `FullPlayerTransportLayout.auxiliarySymbolFont` (30 pt). */
    val transportSymbolSize = 30.dp
    /** iOS: `.largeTitle`-Symbol im Play-Knopf. */
    val playSymbolSize = 34.dp
    /** iOS: `FullPlayerTransportLayout`. */
    val scrubberVerticalSpacing = 20.dp
    val spacingAbovePlayRow = 24.dp
    val spacingBelowPlayRow = 8.dp
    /** iOS: `FullPlayerUtilityBarLayout`. */
    val utilityPrimaryRowHeight = 44.dp
    val utilityRowSpacing = 4.dp
    /** iOS: `FullPlayerProgressLayout` / `FullPlayerScrubberLayout`. */
    val progressRowHeight = 14.dp
    val progressTrackHeight = 12.dp
    val scrubThumbDiameter = 16.dp
    val scrubberBlockSpacing = 10.dp
    val scrubberPaddingAboveBar = 6.dp
    val scrubberBarToTimeSpacing = 2.dp
    /** iOS: `FullPlayerCoverOverlayMetrics.panelControlButtonSize`. */
    val panelControlButtonSize = 44.dp
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
