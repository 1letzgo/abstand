package de.letzgo.abstand.ui.player

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import de.letzgo.abstand.model.PlayerWiring
import de.letzgo.abstand.player.PlaybackSkipDefaults
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandInlineSpinner
import de.letzgo.abstand.ui.components.AbstandMenu
import de.letzgo.abstand.ui.components.AbstandProgressBar
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.formatPlaybackDurationShortHuman
import de.letzgo.abstand.ui.medium
import kotlinx.coroutines.launch

/**
 * iOS: `TabAccessoryMiniPlayerSnapshot` — nur Player-Ereignisse, keine Positions-Ticks
 * (Restzeit als Minuten-Bucket). Gleiche Instanz → keine Rekomposition der Leiste.
 */
@Immutable
data class MiniPlayerSnapshot(
    val activeBookId: String?,
    val primaryLine: String,
    val subtitleText: String?,
    val isPlaying: Boolean,
    val isBuffering: Boolean,
    val canTogglePlayback: Boolean,
    val skipBackwardSeconds: Int,
) {
    /** iOS: `FloatingPlayerChromeController.refresh` — sichtbar nur mit geladenem Titel. */
    val chromeVisible: Boolean
        get() = activeBookId != null && primaryLine.isNotBlank() && primaryLine != "Loading…"

    companion object {
        val hidden = MiniPlayerSnapshot(null, "", null, false, false, false, PlaybackSkipDefaults.backwardSeconds)
    }
}

/**
 * iOS: `FloatingPlayerChromeController` + `FloatingAccessoryGate` — baut den Snapshot aus den
 * Player-Flows; Position nur gedrosselt (Minuten-Bucket der Restzeit).
 */
@Composable
fun rememberMiniPlayerSnapshot(wiring: PlayerWiring): MiniPlayerSnapshot {
    val player = wiring.player
    val book by player.activeBook.collectAsState()
    val episodeId by player.activePlaybackEpisodeId.collectAsState()
    val isPlaying by player.isPlaying.collectAsState()
    val isBuffering by player.isBuffering.collectAsState()
    val preparing by wiring.isPreparingPlayback.collectAsState()
    val skipBack by player.skipBackwardSeconds.collectAsState()
    val total by player.totalDuration.collectAsState()
    val position by rememberThrottledPosition(player.globalPosition, REMAINING_REFRESH_MS)
    val remainingMinutes by remember { derivedStateOf { (maxOf(0.0, maxOf(total, 1.0) - position) / 60).toInt() } }
    val b = book ?: return MiniPlayerSnapshot.hidden
    val connecting = isBuffering || preparing
    val showTitle = remember(b.id, episodeId) { wiring.podcastEpisodeForActivePlayback()?.showTitle }
    val primary = remember(b, showTitle) { playerDashTitleLine(b, showTitle) }.let { line ->
        if (line.isNotBlank() && line != "—" && line != "…") line else if (connecting) "Loading…" else ""
    }
    // Ohne bekannte Dauer (Restore lädt noch) keine Restzeit — sonst kurz „< 1 min“.
    val subtitle = when {
        connecting -> "Loading…"
        total <= 0 -> ""
        else -> formatPlaybackDurationShortHuman(remainingMinutes * 60.0 + REMAINING_ROUNDING_SECONDS)
    }
    return MiniPlayerSnapshot(
        activeBookId = b.id,
        primaryLine = primary,
        subtitleText = subtitle,
        isPlaying = isPlaying,
        isBuffering = isBuffering,
        canTogglePlayback = !connecting,
        skipBackwardSeconds = skipBack,
    )
}

/** Restzeit-Text höchstens alle 5 s neu berechnen (iOS: Minuten-Timer). */
private const val REMAINING_REFRESH_MS = 5_000L
/** Minuten-Bucket auf die Bucket-Mitte runden, damit „x min“ nicht eine Minute zu früh springt. */
private const val REMAINING_ROUNDING_SECONDS = 30.0

/**
 * iOS: `FloatingAccessoryLayer` — schwebende Leiste über der Navigationsleiste. Immer komponiert,
 * nur die Sichtbarkeit animiert (nie die Tab-Struktur umbauen). Meldet ihre Höhe für den
 * Scroll-Inset ([onVisibleHeightChange]) und ihren Rahmen als Zoom-Quelle ([NowPlayingZoomSource]).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MiniPlayerDock(
    wiring: PlayerWiring,
    modifier: Modifier = Modifier,
    onVisibleChange: (Boolean) -> Unit = {},
) {
    val snapshot = rememberMiniPlayerSnapshot(wiring)
    val keyboardVisible = WindowInsets.isImeVisible
    val visible = snapshot.chromeVisible && !keyboardVisible
    androidx.compose.runtime.LaunchedEffect(visible) {
        onVisibleChange(visible)
        if (!visible) NowPlayingZoomSource.bounds = null
    }
    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = slideInVertically { it } + fadeIn(),
        exit = slideOutVertically { it } + fadeOut(),
    ) {
        MiniPlayerBar(
            snapshot = snapshot,
            wiring = wiring,
            modifier = Modifier
                .padding(horizontal = AppTheme.Layout.screenPadding)
                .padding(bottom = MiniPlayerMetrics.accessoryBottomGap)
                .onGloballyPositioned { NowPlayingZoomSource.bounds = it.boundsInRoot() },
        )
    }
}

/** Höhe, die die Leiste über dem Inhalt belegt (für [de.letzgo.abstand.ui.LocalScrollBottomInset]). */
val miniPlayerDockHeight: Dp
    get() = MiniPlayerMetrics.rowMinHeight + MiniPlayerMetrics.rowMinHeightOuterMargin + MiniPlayerMetrics.accessoryBottomGap

/** iOS: `TabAccessoryMiniPlayer` — Cover, „Autor – Titel“, Restzeit, −Sekunden, Play/Pause. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MiniPlayerBar(snapshot: MiniPlayerSnapshot, wiring: PlayerWiring, modifier: Modifier = Modifier) {
    val palette = Theme.palette
    val shape = RoundedCornerShape(MiniPlayerMetrics.accessoryCornerRadius)
    val scope = rememberCoroutineScope()
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = shape,
        color = palette.card,
        contentColor = palette.textPrimary,
        shadowElevation = MiniPlayerMetrics.accessoryShadowElevation,
    ) {
        Box {
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = MiniPlayerMetrics.rowMinHeight + MiniPlayerMetrics.rowMinHeightOuterMargin)
                    .padding(horizontal = MiniPlayerMetrics.accessoryHorizontalPadding),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    Modifier
                        .weight(1f)
                        .heightIn(min = MiniPlayerMetrics.rowMinHeight)
                        .clickable(onClickLabel = "Shows the full player") { wiring.openNowPlaying() }
                        .semantics { contentDescription = "Open now playing" },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    var menuOpen by remember { mutableStateOf(false) }
                    Box {
                        val id = snapshot.activeBookId
                        Box(
                            Modifier
                                .size(MiniPlayerMetrics.tabAccessoryCover)
                                .clip(RoundedCornerShape(MiniPlayerMetrics.coverCornerRadius / 2))
                                .combinedClickable(onClick = { wiring.openNowPlaying() }, onLongClick = { menuOpen = true }),
                        ) {
                            if (id != null) CoverImage(itemId = id, modifier = Modifier.size(MiniPlayerMetrics.tabAccessoryCover))
                        }
                        // iOS: Kontextmenü am Cover → „Stop playback“.
                        AbstandMenu(menuOpen, { menuOpen = false }) {
                            item("Stop playback", { scope.launch { wiring.dismissPlayer() } }, icon = SF.xmarkCircle, destructive = true)
                        }
                    }
                    Column(
                        Modifier.weight(1f).padding(start = AppTheme.Layout.withinSectionSpacing),
                        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
                    ) {
                        Text(
                            snapshot.primaryLine,
                            style = IosType.footnote.medium,
                            color = palette.textPrimary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        snapshot.subtitleText?.let {
                            Text(it, style = IosType.caption.medium, color = palette.textSecondary, maxLines = 1)
                        }
                    }
                }
                if (snapshot.canTogglePlayback || snapshot.isBuffering) MiniTransport(snapshot, wiring)
            }
            MiniProgressLine(wiring, Modifier.align(Alignment.BottomCenter).padding(horizontal = MiniPlayerMetrics.accessoryCornerRadius))
        }
    }
}

@Composable
private fun MiniTransport(snapshot: MiniPlayerSnapshot, wiring: PlayerWiring) {
    val palette = Theme.palette
    val busy = snapshot.isBuffering
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing), verticalAlignment = Alignment.CenterVertically) {
        AbstandIconButton(
            SF.gobackward(snapshot.skipBackwardSeconds),
            PlaybackSkipDefaults.accessibilityLabel(true, snapshot.skipBackwardSeconds),
            onClick = { wiring.player.skipBackward() },
            enabled = !busy,
            size = MiniPlayerMetrics.accessoryTransportSide,
            tint = palette.textPrimary,
        )
        Box(
            Modifier
                .size(MiniPlayerMetrics.accessoryTransportSide)
                .clickable(enabled = snapshot.canTogglePlayback) { wiring.player.togglePlayPause() }
                .semantics { contentDescription = if (snapshot.isPlaying) "Pause" else "Play" },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier
                    .size(MiniPlayerMetrics.accessoryPlayWidth, MiniPlayerMetrics.accessoryPlayHeight)
                    .background(Theme.accent, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                if (busy) {
                    AbstandInlineSpinner(
                        color = Theme.onAccent,
                        size = MiniPlayerMetrics.tabAccessoryCover / 2,
                        strokeWidth = AppTheme.Layout.boldStrokeWidth,
                    )
                } else {
                    Icon(
                        if (snapshot.isPlaying) SF.pauseFill else SF.playFill,
                        contentDescription = null,
                        tint = Theme.onAccent,
                    )
                }
            }
        }
    }
}

/** Dünne Fortschrittslinie — eigene Rekompositionsinsel, 1 Hz. */
@Composable
private fun MiniProgressLine(wiring: PlayerWiring, modifier: Modifier = Modifier) {
    val player = wiring.player
    val total by player.totalDuration.collectAsState()
    val position by rememberThrottledPosition(player.globalPosition, PROGRESS_REFRESH_MS)
    val fraction = if (total > 0) (position / total).coerceIn(0.0, 1.0).toFloat() else 0f
    AbstandProgressBar(
        fraction.toDouble(), modifier, height = MiniPlayerMetrics.accessoryProgressHeight, shape = RectangleShape,
        contentDescription = "Playback progress",
    )
}

private const val PROGRESS_REFRESH_MS = 1_000L
