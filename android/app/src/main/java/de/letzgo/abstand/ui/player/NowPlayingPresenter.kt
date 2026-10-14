package de.letzgo.abstand.ui.player

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.Velocity
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.model.PlayerWiring
import kotlinx.coroutines.launch

/**
 * iOS: `NowPlayingZoomPresenter` + `FullScreenOverlayPresenter` — Vollbild-Player über den Tabs
 * (inkl. Navigationsleiste), wächst aus der Mini-Player-Leiste ([NowPlayingZoomSource]) und schrumpft
 * beim Schließen dorthin zurück. Schließen: nach unten ziehen (überall, in Listen erst ab ihrem
 * Anfang — iOS: `interactiveDismissShouldBegin`), System-Zurück oder Griff antippen.
 *
 * Immer komponiert lassen (außerhalb des Tab-Baums); der Inhalt wird nur während Sichtbarkeit/
 * Animation aufgebaut.
 */
@Composable
fun NowPlayingOverlay(
    wiring: PlayerWiring,
    readAlong: NowPlayingReadAlong? = null,
    onOpenEbook: ((AbsBook) -> Unit)? = null,
) {
    val presented by wiring.nowPlayingPresented.collectAsState()
    val progress = remember { Animatable(0f) }
    var dragOffset by remember { mutableFloatStateOf(0f) }
    val scope = rememberCoroutineScope()
    val thresholdPx = with(LocalDensity.current) { MiniPlayerMetrics.dismissDragThreshold.toPx() }

    LaunchedEffect(presented) {
        if (presented) {
            dragOffset = 0f
            progress.animateTo(1f, spring(dampingRatio = PRESENT_DAMPING, stiffness = Spring.StiffnessMediumLow))
        } else {
            val from = dragOffset
            launch { animate(from, 0f, animationSpec = tween(DISMISS_MS)) { v, _ -> dragOffset = v } }
            progress.animateTo(0f, tween(DISMISS_MS))
        }
    }
    BackHandler(enabled = presented) { wiring.dismissNowPlaying() }
    if (!presented && progress.value == 0f) return

    fun settle(velocityY: Float) {
        if (dragOffset > thresholdPx || velocityY > DISMISS_VELOCITY) {
            wiring.dismissNowPlaying()
        } else {
            val from = dragOffset
            scope.launch { animate(from, 0f, animationSpec = spring()) { v, _ -> dragOffset = v } }
        }
    }

    val dragState = rememberDraggableState { delta -> dragOffset = (dragOffset + delta).coerceAtLeast(0f) }
    // Listen (Kapitel, Bookmarks, Teleprompter): erst ziehen, wenn die Liste oben angekommen ist.
    val nested = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (dragOffset > 0f && available.y < 0f) {
                    val used = maxOf(available.y, -dragOffset)
                    dragOffset += used
                    return Offset(0f, used)
                }
                return Offset.Zero
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput && available.y > 0f) {
                    dragOffset += available.y
                    return Offset(0f, available.y)
                }
                return Offset.Zero
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (dragOffset > 0f) {
                    settle(available.y)
                    return available
                }
                return Velocity.Zero
            }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().semantics { traversalIndex = -1f }) {
        val w = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val h = constraints.maxHeight.toFloat().coerceAtLeast(1f)
        val src = NowPlayingZoomSource.bounds
        val p = progress.value
        val startScale = src?.let { (it.width / w).coerceIn(MIN_START_SCALE, 1f) } ?: FALLBACK_START_SCALE
        val scale = startScale + (1f - startScale) * p
        val origin = src?.let { TransformOrigin((it.center.x / w).coerceIn(0f, 1f), (it.center.y / h).coerceIn(0f, 1f)) }
            ?: TransformOrigin(0.5f, 1f)
        val dragFraction = (dragOffset / h).coerceIn(0f, 1f)

        // Abdunkeln des Hintergrunds während Ein-/Ausblenden und Ziehen.
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = SCRIM_ALPHA * p * (1f - dragFraction))))
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = scale * (1f - dragFraction * DRAG_SHRINK)
                    scaleY = scale * (1f - dragFraction * DRAG_SHRINK)
                    transformOrigin = origin
                    translationY = dragOffset
                    alpha = (p * ALPHA_RAMP).coerceAtMost(1f)
                    clip = true
                    shape = RoundedCornerShape(percent = (CORNER_PERCENT * (1f - p + dragFraction)).toInt().coerceIn(0, MAX_CORNER_PERCENT))
                }
                .nestedScroll(nested)
                .draggable(dragState, Orientation.Vertical, onDragStopped = { v -> settle(v) }),
        ) {
            NowPlayingScreen(
                wiring = wiring,
                onDismiss = { wiring.dismissNowPlaying() },
                readAlong = readAlong,
                onOpenEbook = onOpenEbook?.let { open -> { book: AbsBook -> wiring.dismissNowPlaying(); open(book) } },
            )
        }
    }
}

private const val PRESENT_DAMPING = 0.86f
private const val DISMISS_MS = 320
/** px/s nach unten, ab der ein kurzes Wischen schließt. */
private const val DISMISS_VELOCITY = 1_800f
private const val MIN_START_SCALE = 0.2f
private const val FALLBACK_START_SCALE = 0.9f
private const val SCRIM_ALPHA = 0.35f
/** Inhalt wird schneller sichtbar als er wächst (sonst wirkt die Leiste „leer“). */
private const val ALPHA_RAMP = 2.5f
/** Beim Ziehen leicht verkleinern (iOS-Zoom-Dismiss). */
private const val DRAG_SHRINK = 0.25f
/** Eckenradius in Prozent der kürzeren Seite (am Anfang/Ende der Zoom-Animation). */
private const val CORNER_PERCENT = 8f
private const val MAX_CORNER_PERCENT = 50
