package de.letzgo.abstand.ui.player

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
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
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.model.PlayerWiring
import de.letzgo.abstand.player.AudioEQPreset
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.player.PlaybackSkipDefaults
import de.letzgo.abstand.player.SleepTimerMetrics
import de.letzgo.abstand.player.SleepTimerMode
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.medium
import kotlinx.coroutines.delay
import kotlin.math.max

// MARK: - Scrubber (iOS: `FullPlayerScrubberSection` + `FullPlayerProgressTrack`)

/**
 * iOS: `FullPlayerProgressTrack` — Kapsel-Spur mit Füllung und Kapitelmarken; Daumen nur beim Ziehen.
 * Antippen springt, horizontales Ziehen scrubbt (iOS: Long-Press + Ziehen).
 */
@Composable
private fun ProgressTrack(
    value: Double,
    total: Double,
    enabled: Boolean,
    chapterMarkers: List<Double>,
    accessibilityLabel: String,
    onScrub: (Double?) -> Unit,
    onSeek: (Double) -> Unit,
) {
    val palette = Theme.palette
    val accent = Theme.accent
    val fraction = if (total > 0) (value / total).coerceIn(0.0, 1.0) else 0.0
    var scrubbing by remember { mutableStateOf(false) }
    val currentTotal by rememberUpdatedState(total)
    val markerColor = palette.textSecondary.copy(alpha = 0.65f)
    val hairline = with(LocalDensity.current) { AppTheme.Layout.hairlineWidth.toPx() }
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .height(MiniPlayerMetrics.progressRowHeight + MiniPlayerMetrics.scrubberPaddingAboveBar)
            .semantics {
                contentDescription = accessibilityLabel
                stateDescription = "${(fraction * 100).toInt()} percent"
                progressBarRangeInfo = ProgressBarRangeInfo(fraction.toFloat(), 0f..1f)
                if (enabled) setProgress { v -> onSeek(v.toDouble() * currentTotal); true }
            }
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                detectTapGestures { o -> onSeek((o.x / size.width).coerceIn(0f, 1f) * currentTotal) }
            }
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                var x = 0f
                detectHorizontalDragGestures(
                    onDragStart = { o ->
                        scrubbing = true
                        x = o.x
                        onScrub((x / size.width).coerceIn(0f, 1f) * currentTotal)
                    },
                    onDragEnd = {
                        scrubbing = false
                        onSeek((x / size.width).coerceIn(0f, 1f) * currentTotal)
                        onScrub(null)
                    },
                    onDragCancel = {
                        scrubbing = false
                        onScrub(null)
                    },
                ) { change, dx ->
                    change.consume()
                    x += dx
                    onScrub((x / size.width).coerceIn(0f, 1f) * currentTotal)
                }
            },
        contentAlignment = Alignment.BottomStart,
    ) {
        val w = maxWidth
        Box(Modifier.fillMaxWidth().height(MiniPlayerMetrics.progressRowHeight), contentAlignment = Alignment.CenterStart) {
            Canvas(Modifier.fillMaxWidth().height(MiniPlayerMetrics.progressTrackHeight).clip(CircleShape)) {
                drawRect(palette.progressTrack)
                drawRect(accent, size = Size(size.width * fraction.toFloat(), size.height))
                chapterMarkers.forEach { m ->
                    val x = max(0f, size.width * m.toFloat() - hairline / 2)
                    drawRect(markerColor, topLeft = Offset(x, 0f), size = Size(hairline, size.height))
                }
            }
            if (scrubbing) {
                val thumb = MiniPlayerMetrics.scrubThumbDiameter
                Box(
                    Modifier
                        .offset(x = (w * fraction.toFloat() - thumb / 2).coerceAtLeast(0.dp))
                        .size(thumb)
                        .background(accent, CircleShape)
                        .border(AppTheme.Layout.boldStrokeWidth, palette.background, CircleShape),
                )
            }
        }
    }
}

/** Zeitenzeile unter einer Spur: links verstrichen, Mitte Beschriftung, rechts Rest. */
@Composable
private fun TimesRow(elapsed: Double, remaining: Double, caption: String, showTimes: Boolean = true) {
    val palette = Theme.palette
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(if (showTimes) formatPlaybackTime(elapsed) else "", style = IosType.caption, color = palette.textSecondary)
        Text(
            caption,
            style = IosType.caption,
            color = palette.textPrimary,
            maxLines = 1,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f).padding(horizontal = AppTheme.Layout.stackSpacing),
        )
        Text(if (showTimes) formatPlaybackTime(remaining) else "", style = IosType.caption, color = palette.textSecondary)
    }
}

/**
 * iOS: `FullPlayerScrubberSection` — Buch-Scrubber mit Kapitelmarken, darunter (bei Kapiteln) der
 * Kapitel-Scrubber. Position gedrosselt (iOS: `TimelineView(.periodic(by: 0.5))`).
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
            val chapter = player.currentChapterProgress(display)
            val chDur = chapter?.duration ?: 1.0
            val chPos = (chapter?.position ?: 0.0).coerceIn(0.0, chDur)
            val caption = chapterTitle.trim().ifEmpty { if (chapterOrdinal > 0) "Chapter $chapterOrdinal" else "Chapter" }
            Column(verticalArrangement = Arrangement.spacedBy(MiniPlayerMetrics.scrubberBarToTimeSpacing)) {
                ProgressTrack(
                    chPos, chDur, enabled && chapter != null, emptyList(), "Chapter position",
                    onScrub = { rel -> scrubGlobal = rel?.let { (chapter?.start ?: 0.0) + it } },
                    onSeek = { rel -> player.seek((chapter?.start ?: 0.0) + rel) },
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
    // Kapitel-Ränder hängen von der Position ab — nur bei Kapitelwechsel neu prüfen.
    val ordinal by player.currentChapterOrdinal.collectAsState()
    val canPrev = remember(ordinal, chapterCount, book?.id) { player.canSkipToPreviousChapter }
    val canNext = remember(ordinal, chapterCount, book?.id) { player.canSkipToNextChapter }
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
                    .size(MiniPlayerMetrics.playPauseButtonWidth, AppTheme.Layout.minTapTarget)
                    .clip(CircleShape)
                    .background(Theme.accent)
                    .clickable(enabled = hasBook) { player.togglePlayPause() }
                    .semantics { contentDescription = if (busy) "Loading" else if (isPlaying) "Pause" else "Play" },
                contentAlignment = Alignment.Center,
            ) {
                if (busy) {
                    CircularProgressIndicator(color = Theme.onAccent, strokeWidth = AppTheme.Layout.boldStrokeWidth, modifier = Modifier.size(AppTheme.Layout.compactIconColumnWidth))
                } else {
                    Icon(if (isPlaying) SF.pauseFill else SF.playFill, contentDescription = null, tint = Theme.onAccent, modifier = Modifier.size(MiniPlayerMetrics.playSymbolSize))
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
                tint = palette.textPrimary.copy(alpha = if (enabled) 1f else DISABLED_ALPHA),
                modifier = Modifier.size(MiniPlayerMetrics.transportSymbolSize),
            )
        }
    }
}

private const val DISABLED_ALPHA = 0.35f

// MARK: - Utility-Leiste (iOS: `FullPlayerUtilityBar`)

/** iOS: `AudioEQPreset.systemImage`. */
private val AudioEQPreset.icon: ImageVector
    get() = when (this) {
        AudioEQPreset.flat -> SF.sliderHorizontal3
        AudioEQPreset.voiceFocus -> SF.waveform
        AudioEQPreset.bassBoost -> SF.speakerWave1
        AudioEQPreset.trebleBoost -> SF.speakerWave3
    }

/** Spalte der Leiste: Primärzeile (Symbol/Text, 44 hoch) + Beschriftung (`caption2`). */
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
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(AppTheme.Layout.fieldCornerRadius))
                .clickable(enabled = onClick != null) { onClick?.invoke() }
                .semantics { contentDescription = accessibilityLabel },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(MiniPlayerMetrics.utilityRowSpacing),
        ) {
            Box(Modifier.fillMaxWidth().height(MiniPlayerMetrics.utilityPrimaryRowHeight), contentAlignment = Alignment.Center) { primary() }
            Text(caption, style = IosType.caption2, color = palette.textSecondary)
        }
        menu?.invoke()
    }
}

@Composable
private fun MenuRow(title: String, selected: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(title) },
        trailingIcon = { if (selected) Icon(SF.checkmark, contentDescription = null, tint = Theme.accent) },
        onClick = onClick,
    )
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
    var eqMenu by remember { mutableStateOf(false) }
    var rateMenu by remember { mutableStateOf(false) }

    Row(modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.stackSpacing)) {
        UtilityColumn("EQ", "Equalizer, ${eq.label}", onClick = { eqMenu = true }, menu = {
            DropdownMenu(expanded = eqMenu, onDismissRequest = { eqMenu = false }) {
                AudioEQPreset.entries.forEach { p -> MenuRow(p.label, eq == p) { eqMenu = false; player.setEQPreset(p) } }
            }
        }) {
            Icon(eq.icon, contentDescription = null, tint = if (eq == AudioEQPreset.flat) palette.textPrimary else accent)
        }

        UtilityColumn("Tempo", "Playback speed, ${formatPlaybackRate(rate)}", onClick = { rateMenu = true }, menu = {
            DropdownMenu(expanded = rateMenu, onDismissRequest = { rateMenu = false }) {
                PlaybackController.playbackRatePresets.forEach { r -> MenuRow(formatPlaybackRate(r), rate == r) { rateMenu = false; player.setPlaybackRate(r) } }
            }
        }) {
            Text(formatPlaybackRate(rate), style = IosType.subheadline.medium, color = palette.textPrimary, maxLines = 1)
        }

        SleepTimerColumn(wiring)

        UtilityColumn("Output", "Audio output", onClick = { AudioOutputSwitcher.show(context) }) {
            Icon(SF.speakerWave3, contentDescription = null, tint = palette.textPrimary)
        }

        if (sid != null) {
            when {
                dlState?.isDownloaded == true -> UtilityColumn("Download", "Remove download", onClick = { wiring.removeLocalDownloadForActivePlayback() }) {
                    Icon(SF.arrowDownCircleFill, contentDescription = null, tint = accent)
                }
                dlState?.isDownloading == true && activeDownload == sid -> UtilityColumn("Download", "Download in progress", onClick = null) {
                    LinearProgressIndicator(
                        progress = { dlState.progress.toFloat() },
                        color = accent,
                        trackColor = palette.progressTrack,
                        modifier = Modifier.padding(horizontal = AppTheme.Layout.screenPadding),
                    )
                }
                dlState?.isDownloading == true -> UtilityColumn("Download", "Queued", onClick = null) {
                    Icon(SF.arrowDownCircle, contentDescription = null, tint = accent.copy(alpha = DISABLED_ALPHA))
                }
                else -> UtilityColumn("Download", "Download", onClick = { wiring.startDownloadForActivePlayback() }) {
                    Icon(SF.arrowDownCircle, contentDescription = null, tint = palette.textPrimary)
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
    val label = when (val m = mode) {
        SleepTimerMode.Off -> SleepTimerMetrics.offLabel()
        is SleepTimerMode.Minutes -> SleepTimerMetrics.minutesLabel(m.minutes)
        is SleepTimerMode.Chapters -> SleepTimerMetrics.chaptersMenuLabel(m.chapters)
    }
    UtilityColumn("Sleep", "Sleep timer, $label", onClick = { menu = true }, menu = {
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            MenuRow(SleepTimerMetrics.offLabel(), mode == SleepTimerMode.Off) { menu = false; player.applySleepTimer(0) }
            HorizontalDivider()
            SleepTimerMetrics.minutePresets.forEach { minutes ->
                MenuRow(SleepTimerMetrics.minutesLabel(minutes), mode == SleepTimerMode.Minutes(minutes)) { menu = false; player.applySleepTimer(minutes) }
            }
            val options = remember(menu, chapterCount) { player.sleepTimerChapterOptions() }
            if (options.isNotEmpty()) {
                HorizontalDivider()
                options.forEach { n ->
                    MenuRow(SleepTimerMetrics.chaptersMenuLabel(n), mode == SleepTimerMode.Chapters(n)) { menu = false; player.applySleepTimerChapters(n) }
                }
            }
        }
    }) {
        val s = seconds
        if (s != null && s > 0) {
            Text(formatPlaybackTime(s), style = IosType.subheadline.medium, color = accent, maxLines = 1)
        } else {
            Icon(SF.moon, contentDescription = null, tint = if (mode == SleepTimerMode.Off) palette.textPrimary else accent)
        }
    }
}
