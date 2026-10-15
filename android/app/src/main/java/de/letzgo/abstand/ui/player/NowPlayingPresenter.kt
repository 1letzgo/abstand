package de.letzgo.abstand.ui.player

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.util.lerp
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.model.PlayerWiring
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.Theme
import kotlinx.coroutines.launch

/**
 * iOS: `NowPlayingZoomPresenter` + `FullScreenOverlayPresenter` — Vollbild-Player über den Tabs.
 * Android: Material-3-**Container-Transform**: der Container der Mini-Player-Leiste
 * ([NowPlayingZoomSource]) wächst mit Emphasized-Easing zum Vollbild (Ecken → 0, Farbe Karte →
 * Hintergrund), der Vollbild-Inhalt blendet per Fade-Through ein. Schließen: nach unten ziehen —
 * die Oberkante folgt dem Finger und der Container schrumpft kontinuierlich zurück in die Leiste
 * (in Listen erst ab ihrem Anfang — iOS: `interactiveDismissShouldBegin`), System-Zurück oder
 * Griff antippen.
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
    // 0 = eingeklappt (Rahmen der Mini-Player-Leiste), 1 = Vollbild.
    val expand = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val thresholdPx = with(density) { MiniPlayerMetrics.dismissDragThreshold.toPx() }
    val cornerPx = with(density) { MiniPlayerMetrics.accessoryCornerRadius.toPx() }
    val fallbackInsetPx = with(density) { AppTheme.Layout.screenPadding.toPx() }
    val fallbackHeightPx = with(density) { MiniPlayerMetrics.barHeight.toPx() }
    val palette = Theme.palette

    LaunchedEffect(presented) {
        if (presented) expand.animateTo(1f, tween(ENTER_MS, easing = EmphasizedEasing))
        else expand.animateTo(0f, tween(EXIT_MS, easing = EmphasizedAccelerateEasing))
    }
    BackHandler(enabled = presented) { wiring.dismissNowPlaying() }
    if (!presented && expand.value == 0f) return

    BoxWithConstraints(Modifier.fillMaxSize().semantics { traversalIndex = -1f }) {
        val w = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val h = constraints.maxHeight.toFloat().coerceAtLeast(1f)
        val src = NowPlayingZoomSource.bounds
            ?: Rect(fallbackInsetPx, h - fallbackHeightPx * 2, w - fallbackInsetPx, h - fallbackHeightPx)
        // Weg, den die Oberkante beim Ziehen bis zum vollständigen Einklappen zurücklegt.
        val collapseDistance = src.top.coerceAtLeast(1f)

        fun dragBy(deltaY: Float) {
            val next = (expand.value - deltaY / collapseDistance).coerceIn(0f, 1f)
            scope.launch { expand.snapTo(next) }
        }

        fun settle(velocityY: Float) {
            val draggedPx = (1f - expand.value) * collapseDistance
            if (draggedPx > thresholdPx || velocityY > DISMISS_VELOCITY) {
                wiring.dismissNowPlaying()
            } else {
                scope.launch { expand.animateTo(1f, tween(SETTLE_MS, easing = EmphasizedDecelerateEasing)) }
            }
        }

        val dragState = rememberDraggableState { delta -> dragBy(delta) }
        // Listen (Kapitel, Bookmarks, Teleprompter): erst ziehen, wenn die Liste oben angekommen ist.
        val nested = remember(collapseDistance) {
            object : NestedScrollConnection {
                override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                    if (expand.value < 1f && available.y < 0f) {
                        val draggedPx = (1f - expand.value) * collapseDistance
                        val used = maxOf(available.y, -draggedPx)
                        dragBy(used)
                        return Offset(0f, used)
                    }
                    return Offset.Zero
                }

                override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                    if (source == NestedScrollSource.UserInput && available.y > 0f) {
                        dragBy(available.y)
                        return Offset(0f, available.y)
                    }
                    return Offset.Zero
                }

                override suspend fun onPreFling(available: Velocity): Velocity {
                    if (expand.value < 1f) {
                        settle(available.y)
                        return available
                    }
                    return Velocity.Zero
                }
            }
        }

        val f = expand.value
        val left = lerp(src.left, 0f, f)
        val top = lerp(src.top, 0f, f)
        val right = lerp(src.right, w, f)
        val bottom = lerp(src.bottom, h, f)
        val radius = lerp(cornerPx, 0f, f)
        val containerShape = remember(left, top, right, bottom, radius) {
            GenericShape { _, _ -> addRoundRect(RoundRect(left, top, right, bottom, CornerRadius(radius))) }
        }
        // Fade-Through: Inhalt erst ab ~35 % sichtbar, damit die Leiste nicht „leer“ aufgezogen wird.
        val contentAlpha = ((f - FADE_THROUGH_START) / (1f - FADE_THROUGH_START)).coerceIn(0f, 1f)
        // Ausgehender Inhalt (Mini-Player darunter) bleibt im ersten Abschnitt sichtbar: der Container
        // deckt erst allmählich ab, statt sofort eine leere Leiste zu zeigen.
        val containerAlpha = (f / FADE_OUT_END).coerceIn(0f, 1f)

        // Scrim hinter dem Container (M3: Abdunkeln proportional zum Fortschritt).
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = SCRIM_ALPHA * f)))
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer { clip = true; shape = containerShape }
                .background(lerp(palette.card, palette.background, f).copy(alpha = containerAlpha))
                .nestedScroll(nested)
                .draggable(dragState, Orientation.Vertical, onDragStopped = { v -> settle(v) }),
        ) {
            // Inhalt in voller Größe, an der Container-Oberkante verankert und vom Container beschnitten.
            Box(Modifier.fillMaxSize().graphicsLayer { translationY = top; alpha = contentAlpha }) {
                NowPlayingScreen(
                    wiring = wiring,
                    onDismiss = { wiring.dismissNowPlaying() },
                    readAlong = readAlong,
                    onOpenEbook = onOpenEbook?.let { open -> { book: AbsBook -> wiring.dismissNowPlaying(); open(book) } },
                )
            }
        }
    }
}

// M3-Motion-Tokens (m3.material.io → Styles → Motion → Easing and duration).
private val EmphasizedEasing = CubicBezierEasing(0.2f, 0f, 0f, 1f)
private val EmphasizedDecelerateEasing = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f)
private val EmphasizedAccelerateEasing = CubicBezierEasing(0.3f, 0f, 0.8f, 0.15f)
/** `long2` — Container-Transform beim Öffnen. */
private const val ENTER_MS = 500
/** `short4` — Schließen (Emphasized Accelerate). */
private const val EXIT_MS = 200
/** `medium2` — Zurückschnappen nach abgebrochenem Ziehen. */
private const val SETTLE_MS = 300
/** px/s nach unten, ab der ein kurzes Wischen schließt. */
private const val DISMISS_VELOCITY = 1_800f
private const val SCRIM_ALPHA = 0.32f
private const val FADE_THROUGH_START = 0.35f
private const val FADE_OUT_END = 0.3f
