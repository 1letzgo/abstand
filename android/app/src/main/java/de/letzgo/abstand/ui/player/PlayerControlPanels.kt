package de.letzgo.abstand.ui.player

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.player.AudioEQBands
import de.letzgo.abstand.player.AudioEQBiquadFilter
import de.letzgo.abstand.player.AudioEQPreset
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.player.PlaybackRates
import de.letzgo.abstand.player.SleepTimerMetrics
import de.letzgo.abstand.player.SleepTimerMode
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.semibold
import java.text.NumberFormat
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest

// iOS: PlayerTickRuler.swift, SleepTimerPanel.swift, PlaybackRatePanel.swift, EqualizerPanel.swift

private object PlayerDialMetrics {
    /** Abstand der Striche. */
    val tickSpacing = 12.dp
    val minorTickHeight = 20.dp
    val majorTickHeight = 36.dp
    val rulerHeight = 76.dp
    val indicatorHeight = 44.dp
    val readoutHeight = 72.dp
    const val EDGE_FADE_FRACTION = 0.14f
    /** Wartezeit nach dem Wischen, bis das Einrasten begonnen hat. */
    const val SETTLE_MILLIS = 80L
    const val MONOSPACED_DIGITS = "tnum"
}

private object EqualizerMetrics {
    val handleSize = 24.dp
    val curveLineWidth = AppTheme.Layout.hairlineSpacing
    /** Luft über dem Griff beim Ziehen. */
    val readoutOffset = 32.dp
    /** Etwas Luft über dem Maximum, damit die Griffe nicht am Rand kleben. */
    const val DISPLAY_RANGE_DB = AudioEQBands.maxGain + 2
    const val CURVE_SAMPLES = 96
    const val FILL_ALPHA = 0.22f
}

/**
 * iOS: `PlayerPanelChipButtonStyle` — Textknopf der Player-Panels: dieselbe Kapsel und Farbe wie die
 * Icon-Knöpfe ([panelButtonColors]), aktiv in Tinte wie die Leiste darunter. [compact] ist so hoch
 * wie die ±-Knöpfe und nur so breit wie der Text, sonst teilen sich die Knöpfe die Zeile.
 */
@Composable
private fun PlayerPanelChip(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    compact: Boolean = false,
    style: TextStyle = AppType.labelLarge,
    accessibilityLabel: String = label,
) {
    val colors = panelButtonColors()
    val palette = Theme.palette
    val height = if (compact) AppTheme.Layout.compactIconButtonSize else MiniPlayerMetrics.panelControlButtonSize
    Box(
        modifier
            .minimumInteractiveComponentSize()
            .heightIn(min = height)
            .clip(CircleShape)
            .background(if (selected) Theme.ink else colors.inactiveBackground)
            .clickable(onClick = onClick)
            .semantics {
                role = Role.Button
                contentDescription = accessibilityLabel
                this.selected = selected
            }
            .padding(horizontal = if (compact) AppTheme.Layout.cardPadding else AppTheme.Layout.tightSpacing),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            style = style.copy(fontFeatureSettings = PlayerDialMetrics.MONOSPACED_DIGITS),
            // Schrift braucht mehr Kontrast als die Icons, deshalb nicht `inactiveForeground`.
            color = if (selected) Theme.onInk else palette.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Clip,
        )
    }
}

/**
 * iOS: `PlayerDialPanelLayout` — Gerüst von Sleep-Timer und Tempo: Hero-Wert und Skala stehen in beiden
 * Panels an derselben Stelle. Dafür haben alle Zeilen feste Höhen, auch ein leerer Zusatz-Platz bleibt reserviert.
 */
@Composable
private fun PlayerDialPanelLayout(
    title: String,
    hero: @Composable () -> Unit,
    actions: @Composable () -> Unit,
    ruler: @Composable () -> Unit,
    accessory: @Composable () -> Unit,
    presets: @Composable () -> Unit,
) {
    PlayerPanelScaffold(title) {
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(start = AppTheme.Layout.cardPadding, end = AppTheme.Layout.cardPadding, bottom = AppTheme.Layout.cardPadding),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
        ) {
            Spacer(Modifier.weight(1f))
            Box(Modifier.fillMaxWidth().height(PlayerDialMetrics.readoutHeight), contentAlignment = Alignment.Center) { hero() }
            Box(Modifier.fillMaxWidth().height(AppTheme.Layout.minTapTarget), contentAlignment = Alignment.Center) { actions() }
            ruler()
            Spacer(Modifier.weight(1f))
            Box(Modifier.fillMaxWidth().height(AppTheme.Layout.minTapTarget), contentAlignment = Alignment.Center) { accessory() }
            presets()
        }
    }
}

private val heroStyle: TextStyle
    get() = AppType.displayLarge.semibold.copy(fontFeatureSettings = PlayerDialMetrics.MONOSPACED_DIGITS)

/** Zustand der Skala: [value] folgt dem Strich in der Mitte, [isAdjusting] gilt vom Wischen bis zum Einrasten. */
@Stable
private class PlayerRulerState(initial: Int) {
    var value by mutableIntStateOf(initial)
    var isAdjusting by mutableStateOf(false)
}

/**
 * iOS: `PlayerTickRuler` — Skala der Player-Panels, rastet je Strich ein. Übernommen wird erst beim
 * Ausrollen ([onCommit]), sonst löste jeder überstrichene Wert die Aktion aus. [target] ist der
 * Wert von außen (Vorgabe getippt): dorthin läuft die Skala, solange niemand wischt.
 */
@Composable
private fun PlayerTickRuler(
    state: PlayerRulerState,
    target: Int,
    range: IntRange,
    majorInterval: Int,
    accessibilityLabel: String,
    label: (Int) -> String,
    accessibilityValue: (Int) -> String,
    onCommit: (Int) -> Unit,
) {
    val palette = Theme.palette
    val accent = Theme.accent
    val haptics = LocalHapticFeedback.current
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = (target - range.first).coerceIn(0, range.last - range.first))
    val dragged by listState.interactionSource.collectIsDraggedAsState()
    val currentOnCommit by rememberUpdatedState(onCommit)
    val ticks = remember(range) { range.toList() }
    val centered by remember(range) {
        derivedStateOf {
            val info = listState.layoutInfo
            val center = (info.viewportStartOffset + info.viewportEndOffset) / 2
            info.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - center) }
                ?.let { range.first + it.index }
                ?: (range.first + listState.firstVisibleItemIndex)
        }
    }
    LaunchedEffect(centered) {
        if (state.isAdjusting && centered != state.value) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        state.value = centered
    }
    LaunchedEffect(listState) {
        snapshotFlow { dragged to listState.isScrollInProgress }.collectLatest { (isDragged, isScrolling) ->
            if (isDragged) {
                state.isAdjusting = true
            } else if (!isScrolling && state.isAdjusting) {
                // Zwischen Wischen und Einrasten kann die Skala kurz stehen, erst danach zählt es.
                delay(PlayerDialMetrics.SETTLE_MILLIS)
                state.isAdjusting = false
                currentOnCommit(state.value)
            }
        }
    }
    LaunchedEffect(target) {
        if (!state.isAdjusting && target != state.value) listState.animateScrollToItem(target - range.first)
    }
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .height(PlayerDialMetrics.rulerHeight)
            .semantics(mergeDescendants = true) {
                contentDescription = accessibilityLabel
                stateDescription = accessibilityValue(state.value)
                customActions = listOf(
                    CustomAccessibilityAction("Increase") {
                        currentOnCommit(minOf(state.value + majorInterval, range.last)); true
                    },
                    CustomAccessibilityAction("Decrease") {
                        currentOnCommit(maxOf(state.value - majorInterval, range.first)); true
                    },
                )
            },
    ) {
        val edge = ((maxWidth - PlayerDialMetrics.tickSpacing) / 2).coerceAtLeast(0.dp)
        LazyRow(
            state = listState,
            flingBehavior = rememberSnapFlingBehavior(listState, SnapPosition.Center),
            contentPadding = PaddingValues(horizontal = edge),
            modifier = Modifier
                .fillMaxSize()
                .clearAndSetSemantics { }
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    drawRect(
                        Brush.horizontalGradient(
                            0f to Color.Transparent,
                            PlayerDialMetrics.EDGE_FADE_FRACTION to Color.Black,
                            1 - PlayerDialMetrics.EDGE_FADE_FRACTION to Color.Black,
                            1f to Color.Transparent,
                        ),
                        blendMode = BlendMode.DstIn,
                    )
                },
        ) {
            items(ticks, key = { it }) { tick ->
                val isMajor = tick % majorInterval == 0
                Box(Modifier.width(PlayerDialMetrics.tickSpacing).height(PlayerDialMetrics.rulerHeight)) {
                    Box(
                        Modifier
                            .align(Alignment.TopCenter)
                            .height(PlayerDialMetrics.indicatorHeight),
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(
                            Modifier
                                .width(AppTheme.Layout.hairlineWidth)
                                .height(if (isMajor) PlayerDialMetrics.majorTickHeight else PlayerDialMetrics.minorTickHeight)
                                .background(if (isMajor) palette.textSecondary else palette.rule),
                        )
                    }
                    if (isMajor) {
                        Text(
                            label(tick),
                            style = AppType.labelSmall.copy(fontFeatureSettings = PlayerDialMetrics.MONOSPACED_DIGITS),
                            color = palette.textSecondary,
                            maxLines = 1,
                            softWrap = false,
                            modifier = Modifier.align(Alignment.BottomCenter).wrapContentWidth(unbounded = true),
                        )
                    }
                }
            }
        }
        Box(
            Modifier
                .align(Alignment.TopCenter)
                .width(AppTheme.Layout.hairlineSpacing)
                .height(PlayerDialMetrics.indicatorHeight)
                .background(accent, CircleShape),
        )
    }
}

/** Sekundentakt für Anzeigen, die aus dem Player gelesen werden. */
@Composable
private fun rememberSecondTick(): Long {
    var tick by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) {
        while (true) {
            tick = System.currentTimeMillis()
            delay(1_000)
        }
    }
    return tick
}

/** Minuten-Timer: die gewählte Dauer. Kapitel-Timer: Restzeit bis Kapitelende, gerundet. */
private fun sleepRulerValue(player: PlaybackController): Int {
    val minutes = when (val mode = player.sleepTimerMode.value) {
        SleepTimerMode.Off -> 0
        is SleepTimerMode.Minutes -> mode.minutes
        is SleepTimerMode.Chapters -> ((player.sleepTimerDisplaySeconds() ?: 0.0) / 60).roundToInt()
    }
    return minutes.coerceIn(0, SleepTimerMetrics.MAX_RULER_MINUTES)
}

/**
 * iOS: `SleepTimerPanel` — Sleep-Timer im Cover-Kasten: große Restzeit, Minuten-Skala, Vorgaben und Kapitelende.
 */
@Composable
fun SleepTimerPanel(player: PlaybackController) {
    val mode by player.sleepTimerMode.collectAsState()
    val palette = Theme.palette
    val ruler = remember { PlayerRulerState(sleepRulerValue(player)) }
    var target by remember { mutableIntStateOf(ruler.value) }
    // Erst nach dem Anwenden lesen: der Modus meldet vor dem Setzen des Kapitelziels.
    LaunchedEffect(mode) { target = sleepRulerValue(player) }
    val maxChapters = remember(mode) { if (player.chapterCount.value > 0) player.maxSleepChapterCount() else 0 }

    PlayerDialPanelLayout(
        title = "Sleep Timer",
        hero = {
            val tick = rememberSecondTick()
            val text = remember(tick, mode, ruler.isAdjusting, ruler.value) {
                if (ruler.isAdjusting) {
                    if (ruler.value > 0) formatPlaybackTime(ruler.value * 60.0) else SleepTimerMetrics.offLabel()
                } else {
                    player.sleepTimerDisplaySeconds()?.takeIf { it > 0 }?.let { formatPlaybackTime(it) } ?: SleepTimerMetrics.offLabel()
                }
            }
            Text(
                text,
                style = heroStyle,
                color = if (mode == SleepTimerMode.Off && !ruler.isAdjusting) palette.textSecondary else palette.textPrimary,
                maxLines = 1,
            )
        },
        actions = {
            // Platz bleibt reserviert, damit die Skala beim Ein- und Ausschalten nicht springt.
            if (mode != SleepTimerMode.Off) {
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing)) {
                    PlayerPanelChip("Reset", compact = true, onClick = {
                        when (val m = mode) {
                            SleepTimerMode.Off -> Unit
                            is SleepTimerMode.Minutes -> player.applySleepTimer(m.minutes)
                            is SleepTimerMode.Chapters -> player.applySleepTimerChapters(m.chapters)
                        }
                    })
                    PlayerPanelChip("Turn Off", compact = true, onClick = { player.applySleepTimer(0) })
                }
            }
        },
        ruler = {
            PlayerTickRuler(
                state = ruler,
                target = target,
                range = 0..SleepTimerMetrics.MAX_RULER_MINUTES,
                majorInterval = SleepTimerMetrics.MAJOR_TICK_INTERVAL,
                accessibilityLabel = "Sleep timer duration",
                label = { "$it" },
                accessibilityValue = { SleepTimerMetrics.minutesLabel(it) },
                onCommit = { player.applySleepTimer(it) },
            )
        },
        accessory = {
            if (maxChapters > 0) SleepChapterStepper(player, mode, maxChapters)
        },
        presets = {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing)) {
                SleepTimerMetrics.minutePresets.forEach { minutes ->
                    PlayerPanelChip(
                        "$minutes",
                        onClick = { player.applySleepTimer(minutes) },
                        modifier = Modifier.weight(1f),
                        selected = mode == SleepTimerMode.Minutes(minutes),
                        accessibilityLabel = SleepTimerMetrics.minutesLabel(minutes),
                    )
                }
            }
        },
    )
}

@Composable
private fun SleepChapterStepper(player: PlaybackController, mode: SleepTimerMode, maxChapters: Int) {
    val palette = Theme.palette
    val count = (mode as? SleepTimerMode.Chapters)?.chapters ?: 0
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            if (count > 0) SleepTimerMetrics.chaptersMenuLabel(count) else "No chapter timer",
            style = AppType.bodyMedium,
            color = if (count > 0) palette.textPrimary else palette.textSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        CompactPanelButton(SF.minus, "One chapter less", enabled = count > 0) {
            if (count == 1) player.applySleepTimer(0) else player.applySleepTimerChapters(count - 1)
        }
        CompactPanelButton(SF.plus, "One chapter more", enabled = count < maxChapters) {
            player.applySleepTimerChapters(count + 1)
        }
    }
}

// MARK: - Tempo

private const val RATE_MAJOR_TICK_INTERVAL = PlaybackRates.STEPS_PER_UNIT / 2
private val ratePresets = listOf(0.5f, 1.0f, 1.5f, 2.0f)

private fun rateTicks(rate: Float): Int = (rate * PlaybackRates.STEPS_PER_UNIT).roundToInt()

private fun rateValue(ticks: Int): Float = ticks.toFloat() / PlaybackRates.STEPS_PER_UNIT

/** „1,0“, „1,25“ — mindestens eine Nachkommastelle, anders als die kompakte Anzeige in der Leiste. */
private fun rateText(rate: Float): String = NumberFormat.getNumberInstance().apply {
    minimumFractionDigits = 1
    maximumFractionDigits = 2
}.format(rate.toDouble())

/** iOS: `PlaybackRatePanel` — Tempo im Cover-Kasten, gleicher Aufbau wie [SleepTimerPanel]. */
@Composable
fun PlaybackRatePanel(player: PlaybackController) {
    val rate by player.playbackRate.collectAsState()
    val palette = Theme.palette
    val ruler = remember { PlayerRulerState(rateTicks(player.playbackRate.value)) }
    val range = remember { rateTicks(PlaybackRates.range.start)..rateTicks(PlaybackRates.range.endInclusive) }
    val displayed = if (ruler.isAdjusting) rateValue(ruler.value) else rate

    PlayerDialPanelLayout(
        title = "Tempo",
        hero = { Text("${rateText(displayed)}×", style = heroStyle, color = palette.textPrimary, maxLines = 1) },
        actions = {
            // Platz bleibt reserviert, damit nichts springt.
            if (rate != 1f) PlayerPanelChip("Reset", compact = true, onClick = { player.setPlaybackRate(1f) })
        },
        ruler = {
            PlayerTickRuler(
                state = ruler,
                target = rateTicks(rate),
                range = range,
                majorInterval = RATE_MAJOR_TICK_INTERVAL,
                accessibilityLabel = "Playback speed",
                label = { rateText(rateValue(it)) },
                accessibilityValue = { "${rateText(rateValue(it))}×" },
                onCommit = { player.setPlaybackRate(rateValue(it)) },
            )
        },
        accessory = {},
        presets = {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing)) {
                ratePresets.forEach { preset ->
                    PlayerPanelChip(
                        rateText(preset),
                        onClick = { player.setPlaybackRate(preset) },
                        modifier = Modifier.weight(1f),
                        selected = rate == preset,
                        accessibilityLabel = "${rateText(preset)}×",
                    )
                }
            }
        },
    )
}

// MARK: - Equalizer

private val AudioEQPreset.chipTitle: String
    get() = when (this) {
        AudioEQPreset.flat -> "Flat"
        AudioEQPreset.voiceFocus -> "Voice"
        AudioEQPreset.bassBoost -> "Bass"
        AudioEQPreset.trebleBoost -> "Treble"
        AudioEQPreset.custom -> "Custom"
    }

private fun eqBandX(band: Int, width: Float): Float = width * (band + 0.5f) / AudioEQBands.frequencies.size

private fun eqY(db: Double, height: Float): Float {
    val range = EqualizerMetrics.DISPLAY_RANGE_DB
    return height / 2 - (db.coerceIn(-range, range) / range).toFloat() * (height / 2)
}

/** Bänder liegen gleichmäßig, dazwischen wird logarithmisch interpoliert. */
private fun eqFrequency(x: Float, width: Float): Double {
    val f = AudioEQBands.frequencies
    val position = (x / width).toDouble() * f.size - 0.5
    val lower = position.toInt().coerceIn(0, f.size - 2)
    val fraction = position - lower
    return exp(ln(f[lower]) + fraction * (ln(f[lower + 1]) - ln(f[lower])))
}

private fun eqSnapped(db: Double): Double =
    ((db / AudioEQBands.gainStep).roundToInt() * AudioEQBands.gainStep).coerceIn(-AudioEQBands.maxGain, AudioEQBands.maxGain)

private fun eqGainText(gain: Double): String {
    val number = NumberFormat.getNumberInstance().apply { maximumFractionDigits = 1 }.format(gain)
    return if (gain > 0) "+$number dB" else "$number dB"
}

private fun eqBandLabel(band: Int): String {
    val frequency = AudioEQBands.frequencies[band]
    if (frequency >= 1000) {
        val kilohertz = NumberFormat.getNumberInstance().apply { maximumFractionDigits = 1 }.format(frequency / 1000)
        return "$kilohertz kHz"
    }
    return "${frequency.toInt()} Hz"
}

/**
 * iOS: `EqualizerPanel` — sechs ziehbare Bänder über dem echten Betragsgang, darunter die Vorlagen.
 * Ziehen an einer Vorlage übernimmt deren Werte als Startpunkt für [AudioEQPreset.custom].
 */
@Composable
fun EqualizerPanel(player: PlaybackController) {
    val preset by player.eqPreset.collectAsState()
    val customGains by player.eqCustomGains.collectAsState()
    val palette = Theme.palette
    val filters: List<AudioEQBiquadFilter> = remember(preset, customGains) {
        if (preset == AudioEQPreset.custom) AudioEQBands.filters(customGains) else preset.filters
    }
    // Griffposition: bei Custom der eingestellte Wert, sonst die Kurve der Vorlage an dieser Frequenz.
    val handleGains = remember(preset, customGains, filters) {
        if (preset == AudioEQPreset.custom) {
            customGains
        } else {
            AudioEQBands.frequencies.map { AudioEQBands.responseDB(filters, it).coerceIn(-AudioEQBands.maxGain, AudioEQBands.maxGain) }
        }
    }

    PlayerPanelScaffold("Equalizer") {
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(start = AppTheme.Layout.cardPadding, end = AppTheme.Layout.cardPadding, bottom = AppTheme.Layout.cardPadding),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
        ) {
            EqualizerGraph(player, preset, customGains, filters, handleGains, Modifier.weight(1f).fillMaxWidth())
            Row(Modifier.fillMaxWidth()) {
                AudioEQBands.frequencies.indices.forEach { band ->
                    Box(Modifier.weight(1f).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                        Text(eqBandLabel(band), style = AppType.labelSmall, color = palette.textSecondary, maxLines = 1, softWrap = false)
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
                AudioEQPreset.entries.forEach { option ->
                    PlayerPanelChip(
                        option.chipTitle,
                        onClick = { player.setEQPreset(option) },
                        modifier = Modifier.weight(1f),
                        selected = preset == option,
                        style = AppType.labelMedium,
                        accessibilityLabel = option.label,
                    )
                }
            }
        }
    }
}

@Composable
private fun EqualizerGraph(
    player: PlaybackController,
    preset: AudioEQPreset,
    customGains: List<Double>,
    filters: List<AudioEQBiquadFilter>,
    handleGains: List<Double>,
    modifier: Modifier,
) {
    val palette = Theme.palette
    val accent = Theme.accent
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    var draggedBand by remember { mutableStateOf<Int?>(null) }
    val currentPreset by rememberUpdatedState(preset)
    val currentCustom by rememberUpdatedState(customGains)
    val currentHandles by rememberUpdatedState(handleGains)
    val hairline = with(density) { AppTheme.Layout.hairlineWidth.toPx() }
    val curveWidth = with(density) { EqualizerMetrics.curveLineWidth.toPx() }

    fun gainAt(y: Float, height: Float): Double =
        eqSnapped(((height / 2 - y) / (height / 2)).toDouble() * EqualizerMetrics.DISPLAY_RANGE_DB)

    BoxWithConstraints(
        modifier.pointerInput(Unit) {
            val w = size.width.toFloat()
            val h = size.height.toFloat()
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val count = AudioEQBands.frequencies.size
                val band = (down.position.x / w * count).toInt().coerceIn(0, count - 1)
                draggedBand = band
                var y = down.position.y
                fun apply() {
                    val gains = (if (currentPreset == AudioEQPreset.custom) currentCustom else currentHandles.map(::eqSnapped)).toMutableList()
                    val gain = gainAt(y, h)
                    if (gains[band] != gain) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    gains[band] = gain
                    if (gains != currentCustom || currentPreset != AudioEQPreset.custom) player.setEQCustomGains(gains, persist = false)
                }
                down.consume()
                apply()
                while (true) {
                    val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                    if (!change.pressed) {
                        change.consume()
                        break
                    }
                    y = change.position.y
                    change.consume()
                    apply()
                }
                draggedBand = null
                if (currentPreset == AudioEQPreset.custom) player.setEQCustomGains(currentCustom, persist = true)
            }
        },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height
            if (w <= 0f || h <= 0f) return@Canvas
            AudioEQBands.frequencies.indices.forEach { band ->
                val x = eqBandX(band, w)
                drawLine(palette.rule, Offset(x, 0f), Offset(x, h), hairline)
            }
            drawLine(palette.rule, Offset(0f, h / 2), Offset(w, h / 2), hairline)
            val curve = Path().apply {
                for (sample in 0..EqualizerMetrics.CURVE_SAMPLES) {
                    val x = w * sample / EqualizerMetrics.CURVE_SAMPLES
                    val y = eqY(AudioEQBands.responseDB(filters, eqFrequency(x, w)), h)
                    if (sample == 0) moveTo(x, y) else lineTo(x, y)
                }
            }
            val area = Path().apply {
                addPath(curve)
                lineTo(w, h)
                lineTo(0f, h)
                close()
            }
            drawPath(area, Brush.verticalGradient(listOf(accent.copy(alpha = EqualizerMetrics.FILL_ALPHA), Color.Transparent)))
            drawPath(curve, accent, style = Stroke(curveWidth, join = StrokeJoin.Round))
        }
        val widthPx = constraints.maxWidth.toFloat()
        val heightPx = constraints.maxHeight.toFloat()
        val handlePx = with(density) { EqualizerMetrics.handleSize.toPx() }
        handleGains.forEachIndexed { band, gain ->
            val x = eqBandX(band, widthPx)
            val y = eqY(gain, heightPx)
            Box(
                Modifier
                    .offset { IntOffset((x - handlePx / 2).roundToInt(), (y - handlePx / 2).roundToInt()) }
                    .size(EqualizerMetrics.handleSize)
                    .background(palette.textPrimary, CircleShape)
                    .semantics {
                        contentDescription = eqBandLabel(band)
                        stateDescription = eqGainText(gain)
                        fun step(delta: Double): Boolean {
                            val gains = handleGains.toMutableList()
                            gains[band] = (gains[band] + delta).coerceIn(-AudioEQBands.maxGain, AudioEQBands.maxGain)
                            player.setEQCustomGains(gains, persist = true)
                            return true
                        }
                        customActions = listOf(
                            CustomAccessibilityAction("Increase") { step(AudioEQBands.gainStep * 2) },
                            CustomAccessibilityAction("Decrease") { step(-AudioEQBands.gainStep * 2) },
                        )
                    },
            )
            if (draggedBand == band) {
                val above: Dp = if (gain >= 0) EqualizerMetrics.readoutOffset else -EqualizerMetrics.readoutOffset
                Text(
                    eqGainText(gain),
                    style = AppType.labelMedium.copy(fontFeatureSettings = PlayerDialMetrics.MONOSPACED_DIGITS),
                    color = palette.textPrimary,
                    maxLines = 1,
                    softWrap = false,
                    modifier = Modifier
                        .offset { IntOffset(x.roundToInt() - widthPx.roundToInt() / 2, y.roundToInt() - heightPx.roundToInt() / 2) }
                        .offset(y = above)
                        .fillMaxSize()
                        .wrapContentSize(Alignment.Center, unbounded = true),
                )
            }
        }
    }
}
