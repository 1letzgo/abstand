package de.letzgo.abstand.ui.player

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.model.PlayerWiring
import de.letzgo.abstand.player.AudioEQPreset
import de.letzgo.abstand.player.ChapterTimeline
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.player.PlaybackSkipDefaults
import de.letzgo.abstand.player.SleepTimerMetrics
import de.letzgo.abstand.player.SleepTimerMode
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandInlineSpinner
import de.letzgo.abstand.ui.components.AbstandMenu
import de.letzgo.abstand.ui.components.AbstandPickerMenu
import de.letzgo.abstand.ui.components.AbstandProgressBar
import de.letzgo.abstand.ui.formatPlaybackTime
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

// MARK: - Scrubber (iOS: `FullPlayerScrubberSection` + `FullPlayerProgressTrack`)

/** iOS: `.accessibilityHint` der Scrubber-Sektion. */
private const val SCRUB_ACCESSIBILITY_HINT = "Long press and drag on the bar to seek."

/**
 * iOS: `FullPlayerProgressTrack` — Kapsel-Spur mit Füllung und Kapitelmarken; Daumen nur beim Scrubben.
 * Geste wie iOS (`LongPressGesture(0.35)` vor `DragGesture`): erst 350 ms halten, dann ziehen
 * (Live-Vorschau über [onScrub]); gesprungen wird erst beim Loslassen ([onSeek]). Antippen tut nichts.
 * Werte in [onScrub]/[onSeek] beziehen sich auf das beim Scrub-Start gültige [total].
 * TalkBack: Schritte von max(15 s, 2 % der Dauer) als „Skip forward/back“ (iOS: `accessibilityAdjustableAction`).
 */
@Composable
private fun ProgressTrack(
    value: Double,
    total: Double,
    enabled: Boolean,
    chapterMarkers: List<Double>,
    accessibilityLabel: String,
    onScrubStart: () -> Unit = {},
    onScrub: (Double?) -> Unit,
    onSeek: (Double) -> Unit,
) {
    val palette = Theme.palette
    val accent = Theme.accent
    val haptics = LocalHapticFeedback.current
    val fraction = if (total > 0) (value / total).coerceIn(0.0, 1.0) else 0.0
    var scrubbing by remember { mutableStateOf(false) }
    // pointerInput(enabled) lebt über Recompositions hinweg — immer die aktuellen Werte/Lambdas lesen
    // (sonst springt der Kapitel-Scrubber nach Kapitelwechsel mit dem alten Kapitelstart).
    val currentTotal by rememberUpdatedState(total)
    val currentValue by rememberUpdatedState(value)
    val currentOnScrubStart by rememberUpdatedState(onScrubStart)
    val currentOnScrub by rememberUpdatedState(onScrub)
    val currentOnSeek by rememberUpdatedState(onSeek)
    val markerColor = palette.textSecondary.copy(alpha = 0.65f)
    val hairline = with(LocalDensity.current) { AppTheme.Layout.hairlineWidth.toPx() }
    Box(
        Modifier
            .fillMaxWidth()
            .height(MiniPlayerMetrics.progressRowHeight + MiniPlayerMetrics.scrubberPaddingAboveBar)
            .semantics {
                contentDescription = "$accessibilityLabel. $SCRUB_ACCESSIBILITY_HINT"
                val pct = (fraction * 100).roundToInt()
                stateDescription = if (chapterMarkers.isEmpty()) "$pct percent" else "$pct percent, ${chapterMarkers.size + 1} chapters"
                progressBarRangeInfo = ProgressBarRangeInfo(fraction.toFloat(), 0f..1f)
                if (enabled && total > 0) {
                    val step = max(15.0, total * 0.02)
                    setProgress { v -> currentOnSeek(v.toDouble() * currentTotal); true }
                    customActions = listOf(
                        CustomAccessibilityAction("Skip forward") { currentOnSeek(min(currentTotal, currentValue + step)); true },
                        CustomAccessibilityAction("Skip back") { currentOnSeek(max(0.0, currentValue - step)); true },
                    )
                }
            }
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    var x = down.position.x
                    // Long-Press abwarten; Loslassen oder Bewegen über die Touch-Schwelle bricht ab
                    // (dann gehört die Geste z. B. dem Wischen zum Schließen) — Ergebnis null = gehalten.
                    val aborted = withTimeoutOrNull(MiniPlayerMetrics.scrubLongPressMillis) {
                        var abort = false
                        while (!abort) {
                            val c = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                            abort = c == null || !c.pressed || c.isConsumed ||
                                (c.position - down.position).getDistance() > viewConfiguration.touchSlop
                            if (c != null) x = c.position.x
                        }
                        true
                    }
                    if (aborted != null) return@awaitEachGesture
                    val t = currentTotal
                    fun rel() = (x / size.width).coerceIn(0f, 1f) * t
                    scrubbing = true
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    try {
                        currentOnScrubStart()
                        currentOnScrub(rel())
                        while (true) {
                            val c = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            if (!c.pressed) {
                                c.consume()
                                currentOnSeek(rel())
                                break
                            }
                            x = c.position.x
                            c.consume()
                            currentOnScrub(rel())
                        }
                    } finally {
                        scrubbing = false
                        currentOnScrub(null)
                    }
                }
            },
        contentAlignment = Alignment.BottomStart,
    ) {
        Canvas(Modifier.fillMaxWidth().height(MiniPlayerMetrics.progressRowHeight)) {
            val w = size.width
            if (w <= 0f) return@Canvas
            val trackH = MiniPlayerMetrics.progressTrackHeight.toPx()
            val cy = size.height / 2
            val top = cy - trackH / 2
            val fillW = w * fraction.toFloat()
            // iOS: Spur, Füllung und Marken als gerade Rechtecke — erst die Kapsel schneidet sie rund zu.
            val capsule = Path().apply { addRoundRect(RoundRect(0f, top, w, top + trackH, CornerRadius(trackH / 2))) }
            clipPath(capsule) {
                drawRect(palette.progressTrack, Offset(0f, top), Size(w, trackH))
                if (fillW > 0f) drawRect(accent, Offset(0f, top), Size(fillW, trackH))
                chapterMarkers.forEach { m ->
                    drawRect(markerColor, Offset(max(0f, w * m.toFloat() - hairline / 2), top), Size(hairline, trackH))
                }
            }
            if (scrubbing) {
                val r = MiniPlayerMetrics.scrubThumbDiameter.toPx() / 2
                val stroke = AppTheme.Layout.boldStrokeWidth.toPx()
                val center = Offset(max(r, fillW), cy)
                drawCircle(accent, r, center)
                drawCircle(palette.background, r - stroke / 2, center, style = Stroke(stroke))
            }
        }
    }
}

/** Zeitenzeile unter einer Spur: links verstrichen, Mitte Beschriftung, rechts Rest. */
@Composable
private fun TimesRow(elapsed: Double, remaining: Double, caption: String, showTimes: Boolean = true) {
    val palette = Theme.palette
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(if (showTimes) formatPlaybackTime(elapsed) else "", style = AppType.bodySmall, color = palette.textSecondary)
        Text(
            caption,
            style = AppType.bodySmall,
            color = palette.textPrimary,
            maxLines = 1,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f).padding(horizontal = AppTheme.Layout.stackSpacing),
        )
        Text(if (showTimes) formatPlaybackTime(remaining) else "", style = AppType.bodySmall, color = palette.textSecondary)
    }
}

/**
 * iOS: `FullPlayerScrubberSection` — Buch-Scrubber mit Kapitelmarken, darunter (bei Kapiteln) der
 * Kapitel-Scrubber. Position gedrosselt (iOS: `TimelineView(.periodic(by: 0.5))`). Scrubben nur mit
 * aktivem Titel, bekannter Dauer und ohne Puffern (iOS: `scrubEnabled`).
 */
@Composable
fun FullPlayerScrubberSection(wiring: PlayerWiring) {
    val player = wiring.player
    val position by rememberThrottledPosition(player.globalPosition, SCRUBBER_REFRESH_MS)
    val totalDuration by player.totalDuration.collectAsState()
    val chapterCount by player.chapterCount.collectAsState()
    val chapterTitle by player.currentChapterTitle.collectAsState()
    val chapterOrdinal by player.currentChapterOrdinal.collectAsState()
    val buffering by player.isBuffering.collectAsState()
    val book by player.activeBook.collectAsState()
    var scrubGlobal by remember { mutableStateOf<Double?>(null) }
    // Kapitel beim Scrub-Start festhalten — die Spur bleibt beim Ziehen bis ans Kapitelende stabil.
    var scrubChapter by remember { mutableStateOf<ChapterTimeline.ChapterProgress?>(null) }
    val markers = remember(chapterCount, totalDuration, book?.id) { player.chapterMarkerFractions }
    val dur = max(totalDuration, 1.0)
    val display = (scrubGlobal ?: position).coerceIn(0.0, dur)
    val enabled = book != null && totalDuration > 0 && !buffering

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MiniPlayerMetrics.scrubberBlockSpacing)) {
        Column(verticalArrangement = Arrangement.spacedBy(MiniPlayerMetrics.scrubberBarToTimeSpacing)) {
            ProgressTrack(display, dur, enabled, markers, "Playback position", onScrub = { scrubGlobal = it }, onSeek = { player.seek(it) })
            TimesRow(display, max(0.0, dur - display), "")
        }
        // Kapitelzeile reservieren, solange es Kapitel gibt — sonst springt der Block beim Einblenden.
        if (chapterCount > 0) {
            val chapter = scrubChapter?.let { c -> c.copy(position = display - c.start) } ?: player.currentChapterProgress(display)
            val chDur = chapter?.duration ?: 1.0
            val chPos = (chapter?.position ?: 0.0).coerceIn(0.0, chDur)
            val caption = chapterTitle.trim().ifEmpty { if (chapterOrdinal > 0) "Chapter $chapterOrdinal" else "Chapter" }
            Column(verticalArrangement = Arrangement.spacedBy(MiniPlayerMetrics.scrubberBarToTimeSpacing)) {
                ProgressTrack(
                    chPos, chDur, enabled && chapter != null, emptyList(), "Chapter position",
                    onScrubStart = { scrubChapter = player.currentChapterProgress(display) },
                    onScrub = { rel ->
                        val c = scrubChapter
                        if (rel == null || c == null) {
                            scrubGlobal = null
                            scrubChapter = null
                        } else {
                            scrubGlobal = c.start + rel
                        }
                    },
                    // Spur zeigt kapitel-relative Zeit — auf die globale Zeit umrechnen (frischer Kapitelstart).
                    onSeek = { rel ->
                        val c = scrubChapter ?: player.currentChapterProgress(display)
                        if (c != null) player.seek(c.start + rel)
                    },
                )
                TimesRow(chPos, max(0.0, chDur - chPos), caption, showTimes = chapter != null)
            }
        }
    }
}

private const val SCRUBBER_REFRESH_MS = 500L

// MARK: - Transport (iOS: `FullPlayerTransportRowChrome`)

@Composable
fun FullPlayerTransportRow(wiring: PlayerWiring, modifier: Modifier = Modifier) {
    val player = wiring.player
    val book by player.activeBook.collectAsState()
    val isPlaying by player.isPlaying.collectAsState()
    val buffering by player.isBuffering.collectAsState()
    val chapterCount by player.chapterCount.collectAsState()
    val back by player.skipBackwardSeconds.collectAsState()
    val fwd by player.skipForwardSeconds.collectAsState()
    // Kapitel-Ränder hängen von der Position ab (iOS: „Zurück“ im ersten Kapitel erst nach 1,5 s) —
    // Position nur im derivedStateOf lesen, damit die Zeile nur beim Umschalten neu zeichnet.
    val globalPosition = player.globalPosition.collectAsState()
    val canPrev by remember(chapterCount, book?.id) { derivedStateOf { globalPosition.value; player.canSkipToPreviousChapter } }
    val canNext by remember(chapterCount, book?.id) { derivedStateOf { globalPosition.value; player.canSkipToNextChapter } }
    // iOS: `.sensoryFeedback(.impact(weight: .light), trigger: isPlaying)` — nicht beim ersten Aufbau.
    val haptics = LocalHapticFeedback.current
    var lastPlaying by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(isPlaying) {
        if (lastPlaying != null && lastPlaying != isPlaying) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        lastPlaying = isPlaying
    }
    val hasBook = book != null
    val busy = hasBook && buffering
    val hasChapters = chapterCount > 0
    Row(
        modifier.fillMaxWidth().padding(bottom = MiniPlayerMetrics.spacingBelowPlayRow),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TransportIcon(SF.backwardEnd, "Previous chapter", enabled = hasChapters && canPrev, visible = hasChapters) { player.skipToPreviousChapter() }
        TransportIcon(SF.gobackward(back), PlaybackSkipDefaults.accessibilityLabel(true, back), enabled = !busy) { player.skipBackward() }
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .size(MiniPlayerMetrics.playPauseButtonWidth, MiniPlayerMetrics.playPauseButtonHeight)
                    .clip(CircleShape)
                    .background(Theme.ink)
                    .clickable(enabled = hasBook) { player.togglePlayPause() }
                    .semantics { contentDescription = if (busy) "Loading" else if (isPlaying) "Pause" else "Play" },
                contentAlignment = Alignment.Center,
            ) {
                if (busy) {
                    AbstandInlineSpinner(color = Theme.onInk, size = AppTheme.Layout.compactIconColumnWidth, strokeWidth = AppTheme.Layout.boldStrokeWidth)
                } else {
                    Icon(if (isPlaying) SF.pauseFill else SF.playFill, contentDescription = null, tint = Theme.onInk, modifier = Modifier.size(MiniPlayerMetrics.playSymbolSize))
                }
            }
        }
        TransportIcon(SF.goforward(fwd), PlaybackSkipDefaults.accessibilityLabel(false, fwd), enabled = !busy) { player.skipForward() }
        TransportIcon(SF.forwardEnd, "Next chapter", enabled = hasChapters && canNext, visible = hasChapters) { player.skipToNextChapter() }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.TransportIcon(
    icon: ImageVector,
    label: String,
    enabled: Boolean,
    visible: Boolean = true,
    onClick: () -> Unit,
) {
    val palette = Theme.palette
    Box(
        Modifier
            .weight(1f)
            .height(AppTheme.Layout.minTapTarget)
            .clip(CircleShape)
            .clickable(enabled = enabled && visible, onClick = onClick)
            .semantics { if (visible) contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        if (visible) {
            Icon(
                icon,
                contentDescription = null,
                tint = palette.textPrimary.copy(alpha = if (enabled) 1f else AppTheme.disabledContentAlpha),
                modifier = Modifier.size(MiniPlayerMetrics.transportSymbolSize),
            )
        }
    }
}

// MARK: - Utility-Leiste (iOS: `FullPlayerUtilityBar`)

/** iOS: `AudioEQPreset.systemImage`. */
private val AudioEQPreset.icon: ImageVector
    get() = when (this) {
        AudioEQPreset.flat -> SF.sliderHorizontal3
        AudioEQPreset.voiceFocus -> SF.waveform
        AudioEQPreset.bassBoost -> SF.speakerWave1
        AudioEQPreset.trebleBoost -> SF.speakerWave3
    }

/** Spalte der Leiste: Primärzeile (Symbol/Text, 48 hoch) + Beschriftung (`labelSmall`). */
@Composable
private fun androidx.compose.foundation.layout.RowScope.UtilityColumn(
    caption: String,
    accessibilityLabel: String,
    onClick: (() -> Unit)?,
    menu: (@Composable () -> Unit)? = null,
    primary: @Composable () -> Unit,
) {
    val palette = Theme.palette
    Box(Modifier.weight(1f)) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(AppTheme.Layout.cornerMedium))
                .clickable(enabled = onClick != null) { onClick?.invoke() }
                .semantics { contentDescription = accessibilityLabel },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(MiniPlayerMetrics.utilityRowSpacing),
        ) {
            Box(Modifier.fillMaxWidth().height(MiniPlayerMetrics.utilityPrimaryRowHeight), contentAlignment = Alignment.Center) { primary() }
            Text(caption, style = AppType.labelSmall, color = palette.textSecondary)
        }
        menu?.invoke()
    }
}

/**
 * iOS: `FullPlayerUtilityBar` — EQ · Tempo · Sleep · AirPlay (Android: Ausgabe-Umschalter) · Download.
 */
@Composable
fun FullPlayerUtilityBar(wiring: PlayerWiring, modifier: Modifier = Modifier) {
    val player = wiring.player
    val palette = Theme.palette
    val accent = Theme.accent
    val context = LocalContext.current
    val eq by player.eqPreset.collectAsState()
    val rate by player.playbackRate.collectAsState()
    val book by player.activeBook.collectAsState()
    val episodeId by player.activePlaybackEpisodeId.collectAsState()
    val sid = remember(book?.id, episodeId) { wiring.currentPlaybackOfflineStorageId() }
    val downloadStates by wiring.downloads.states.collectAsState()
    val dlState = sid?.let { downloadStates[it] }
    val activeDownload by DownloadManager.activeItemId.collectAsState()
    val queued by DownloadManager.queuedItemIds.collectAsState()
    val downloadProgress by DownloadManager.progress.collectAsState()
    // iOS: `.disabled(!isLoggedIn)` am Download-Knopf.
    val loggedIn by wiring.loggedIn.collectAsState()
    var eqMenu by remember { mutableStateOf(false) }
    var rateMenu by remember { mutableStateOf(false) }

    Row(modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.stackSpacing)) {
        UtilityColumn("EQ", "Equalizer, ${eq.label}", onClick = { eqMenu = true }, menu = {
            AbstandPickerMenu(eqMenu, { eqMenu = false }, AudioEQPreset.entries, eq, { it.label }, { player.setEQPreset(it) }, icon = { it.icon })
        }) {
            Icon(eq.icon, contentDescription = null, tint = if (eq == AudioEQPreset.flat) palette.textPrimary else accent)
        }

        UtilityColumn("Tempo", "Playback speed, ${formatPlaybackRate(rate)}", onClick = { rateMenu = true }, menu = {
            AbstandPickerMenu(rateMenu, { rateMenu = false }, PlaybackController.playbackRatePresets, rate, { formatPlaybackRate(it) }, { player.setPlaybackRate(it) })
        }) {
            Text(formatPlaybackRate(rate), style = AppType.titleSmall, color = palette.textPrimary, maxLines = 1)
        }

        SleepTimerColumn(wiring)

        UtilityColumn("Output", "Audio output", onClick = { AudioOutputSwitcher.show(context) }) {
            Icon(SF.speakerWave3, contentDescription = null, tint = palette.textPrimary)
        }

        if (sid != null) {
            when {
                dlState?.isDownloaded == true -> UtilityColumn("Download", "Remove download", onClick = { wiring.removeLocalDownloadForActivePlayback() }.takeIf { loggedIn }) {
                    Icon(SF.arrowDownCircleFill, contentDescription = null, tint = accent)
                }
                activeDownload == sid -> UtilityColumn("Download", "Download in progress", onClick = null) {
                    AbstandProgressBar(dlState?.progress ?: downloadProgress, Modifier.padding(horizontal = AppTheme.Layout.screenPadding))
                }
                // iOS: wartend in der Download-Warteschlange → gestrichelter Kreis in Akzent.
                sid in queued -> UtilityColumn("Download", "Queued", onClick = null) {
                    Icon(SF.circleDashed, contentDescription = null, tint = accent)
                }
                else -> UtilityColumn("Download", "Download", onClick = { wiring.startDownloadForActivePlayback() }.takeIf { loggedIn }) {
                    Icon(SF.arrowDownCircle, contentDescription = null, tint = palette.textPrimary.copy(alpha = if (loggedIn) 1f else AppTheme.disabledContentAlpha))
                }
            }
        }
    }
}

/** iOS: `SleepTimerControl` + `SleepTimerMenu` + `SleepTimerUtilityMenuLabel` (Countdown statt Mond). */
@Composable
private fun androidx.compose.foundation.layout.RowScope.SleepTimerColumn(wiring: PlayerWiring) {
    val player = wiring.player
    val palette = Theme.palette
    val accent = Theme.accent
    val mode by player.sleepTimerMode.collectAsState()
    val endDate by player.sleepEndDate.collectAsState()
    val chapterCount by player.chapterCount.collectAsState()
    var menu by remember { mutableStateOf(false) }
    // Countdown: Wanduhr-Takt nur solange ein Ende gesetzt ist.
    var tick by remember { mutableLongStateOf(0L) }
    LaunchedEffect(endDate, mode) {
        while (endDate != null) {
            tick = System.currentTimeMillis()
            delay(1_000)
        }
    }
    val seconds = remember(tick, mode, endDate) { player.sleepTimerDisplaySeconds() }
    val chapters = (mode as? SleepTimerMode.Chapters)?.chapters ?: 0
    // iOS: `sleepAccessibilityLabel`.
    val a11yLabel = when {
        seconds != null && seconds > 0 -> "Sleep timer, ${formatPlaybackTime(max(0.0, seconds))} remaining"
        chapters > 0 -> "Sleep timer, $chapters chapter(s)"
        else -> "Sleep timer, Off"
    }
    UtilityColumn("Sleep", a11yLabel, onClick = { menu = true }, menu = {
        AbstandMenu(menu, { menu = false }) {
            item(SleepTimerMetrics.offLabel(), { player.applySleepTimer(0) }, selected = mode == SleepTimerMode.Off, selectable = true)
            divider()
            picker(SleepTimerMetrics.minutePresets, (mode as? SleepTimerMode.Minutes)?.minutes, { SleepTimerMetrics.minutesLabel(it) }, { player.applySleepTimer(it) })
            val options = remember(menu, chapterCount) { player.sleepTimerChapterOptions() }
            if (options.isNotEmpty()) {
                divider()
                picker(options, (mode as? SleepTimerMode.Chapters)?.chapters, { SleepTimerMetrics.chaptersMenuLabel(it) }, { player.applySleepTimerChapters(it) })
            }
        }
    }) {
        // iOS: `SleepTimerUtilityMenuLabel` — Countdown, sonst „n ch/chs“ (Akzent), sonst „Off“.
        val s = seconds
        when {
            s != null && s > 0 -> Text(formatPlaybackTime(s), style = AppType.titleSmall, color = accent, maxLines = 1)
            chapters > 0 -> Text(if (chapters == 1) "$chapters ch" else "$chapters chs", style = AppType.titleSmall, color = accent, maxLines = 1)
            else -> Text("Off", style = AppType.titleSmall, color = palette.textSecondary, maxLines = 1)
        }
    }
}
