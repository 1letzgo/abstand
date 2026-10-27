package de.letzgo.abstand.ui.transcript

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.logic.PlayerTeleprompterMetrics
import de.letzgo.abstand.logic.PlayerTranscriptLine
import de.letzgo.abstand.logic.PlayerTranscriptWord
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.transcript.PlaybackTranscription
import de.letzgo.abstand.transcript.PlayerLiveTranscriptionController
import de.letzgo.abstand.transcript.SpeechModelOffer
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandLabeledLoadingState
import de.letzgo.abstand.ui.components.AbstandPrimaryButton
import de.letzgo.abstand.ui.components.AbstandProminentButton
import kotlin.math.floor
import kotlin.math.roundToInt
import de.letzgo.abstand.ui.components.AbstandProgressBar

/**
 * iOS: Schriftgröße des Teleprompters (`PlayerTeleprompterMetrics.savedFontSize`/`persistFontSize`,
 * +/- am Player). Compose-State, damit eine Änderung sofort neu umbricht.
 */
object TeleprompterFontSize {
    private var saved by mutableStateOf(load())

    private fun load(): Double? =
        if (Prefs.has(PlayerTeleprompterMetrics.FONT_SIZE_STORAGE_KEY)) {
            PlayerTeleprompterMetrics.clampFontSize(Prefs.double(PlayerTeleprompterMetrics.FONT_SIZE_STORAGE_KEY))
        } else null

    /** Gespeicherte Nutzergröße (`null` = Auto-Fit). */
    val current: Double? get() = saved

    /** iOS: `bumpFontSize(delta:sizingViewportHeight:storedFontSize:)`. */
    fun bump(delta: Double, sizingViewportHeight: Double = 300.0) {
        val next = PlayerTeleprompterMetrics.bumpFontSize(delta, sizingViewportHeight, saved)
        Prefs.setDouble(PlayerTeleprompterMetrics.FONT_SIZE_STORAGE_KEY, next)
        saved = next
    }

    fun increase() = bump(PlayerTeleprompterMetrics.FONT_SIZE_STEP)
    fun decrease() = bump(-PlayerTeleprompterMetrics.FONT_SIZE_STEP)
}

/**
 * iOS: `PlayerLiveTranscriptPanelView` — Read-Along-Teleprompter für den `transcriptContent`-Slot von
 * Now Playing. Startet die Session beim Einblenden ([autoStart]) und beendet sie beim Ausblenden
 * ([stopOnDispose]); präsentiert das Wort-Sheet selbst. Hält den Bildschirm an, solange aktiv.
 */
@Composable
fun TranscriptTeleprompter(
    modifier: Modifier = Modifier,
    autoStart: Boolean = true,
    stopOnDispose: Boolean = true,
) {
    val context = LocalContext.current
    val controller = remember { PlayerLiveTranscriptionController.shared(context) }
    val player = remember { PlaybackController.shared(context) }

    val modeActive by controller.isTeleprompterModeActive.collectAsState()
    val lines by controller.transcriptLines.collectAsState()
    val ready by controller.isTeleprompterReady.collectAsState()
    val error by controller.errorMessage.collectAsState()
    val preparing by controller.isPreparing.collectAsState()
    val downloadProgress by controller.modelDownloadProgress.collectAsState()
    val offer by controller.speechModelOffer.collectAsState()
    val fallbackNotice by controller.localeFallbackNotice.collectAsState()
    val selection by controller.wordLookupSelection.collectAsState()
    val activeBook by player.activeBook.collectAsState()

    LaunchedEffect(activeBook?.id, autoStart) {
        if (autoStart && activeBook != null && !controller.isTeleprompterModeActive.value && !controller.isSessionBusy.value &&
            controller.isReadAlongDownloadReady()
        ) {
            controller.startTeleprompterMode()
        }
    }
    DisposableEffect(stopOnDispose) {
        onDispose { if (stopOnDispose && controller.isTeleprompterModeActive.value) controller.disable() }
    }
    // iOS: `isIdleTimerDisabled` während Read Along.
    val view = LocalView.current
    DisposableEffect(modeActive) {
        view.keepScreenOn = modeActive
        onDispose { view.keepScreenOn = false }
    }

    Box(modifier.fillMaxSize()) {
        val showsContent = lines.isNotEmpty()
        if (showsContent) {
            TeleprompterLines(controller, player, lines, selection?.word?.id)
        }
        when {
            offer != null -> SpeechModelOfferCard(offer!!, onDownload = { controller.approveSpeechModelDownload() })
            !showsContent && error != null -> ErrorOverlay(error!!) {
                controller.disable()
                controller.startTeleprompterMode()
            }
            !showsContent && modeActive && !ready -> {
                val progress = downloadProgress
                if (progress != null) {
                    DownloadingOverlay(progress)
                } else {
                    AbstandLabeledLoadingState(text = if (preparing) "Preparing transcript…" else "Transcribing audio…")
                }
            }
            !showsContent && !modeActive && error == null -> IdleOverlay(
                downloadReady = activeBook != null && controller.isReadAlongDownloadReady(),
                hasBook = activeBook != null,
                onStart = { controller.startTeleprompterMode() },
            )
        }
        fallbackNotice?.let { notice ->
            Text(
                notice,
                style = AppType.bodySmall,
                color = Theme.palette.textSecondary,
                maxLines = 2,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .fillMaxWidth()
                    .background(Theme.palette.card.copy(alpha = 0.9f))
                    .padding(AppTheme.Layout.withinSectionSpacing),
            )
        }
    }

    selection?.let { sel ->
        TranscriptWordLookupSheet(selection = sel, onDismiss = { controller.clearWordLookupSelection() })
    }
}

/** Zeilen-Stack: aktive Zeile in der Mitte, fließend nach Zeilenfortschritt verschoben (60 fps). */
@Composable
private fun TeleprompterLines(
    controller: PlayerLiveTranscriptionController,
    player: PlaybackController,
    lines: List<PlayerTranscriptLine>,
    selectedWordId: String?,
) {
    val palette = Theme.palette
    val accent = Theme.accent
    val syncGeneration by controller.teleprompterSyncGeneration.collectAsState()
    var displayTime by remember { mutableDoubleStateOf(PlaybackTranscription.livePosition(player)) }
    // iOS: `TimelineView(.animation)` + `ReadAlongPlaybackClock` — direkt die Player-Zeit je Frame.
    LaunchedEffect(syncGeneration) {
        while (true) {
            withFrameNanos { }
            displayTime = PlaybackTranscription.livePosition(player)
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().clipToBounds()) {
        val widthDp = maxWidth.value.toDouble()
        val heightPx = constraints.maxHeight.toFloat()
        val fontSizeOverride = TeleprompterFontSize.current
        val layout = remember(widthDp, fontSizeOverride) {
            // Schrift wie im quadratischen Cover (Breite) — iOS `sizingViewportHeight = width`.
            PlayerTeleprompterMetrics.layout(sizingViewportHeight = maxOf(widthDp, 1.0), userFontSize = fontSizeOverride)
        }
        val padding = PlayerTeleprompterMetrics.CARD_CONTENT_PADDING
        LaunchedEffect(widthDp, layout) {
            controller.updateTeleprompterContentWidth(maxOf(0.0, widthDp - 2 * padding), layout)
        }
        val density = LocalDensity.current
        val rowStridePx = with(density) { layout.rowStride.dp.toPx() }
        val slotHeightPx = with(density) { layout.slotHeight.dp.toPx() }

        val fractional by remember(lines) { derivedStateOf { controller.fractionalActiveLinePosition(displayTime) } }
        val centerIdx by remember(lines) { derivedStateOf { floor(fractional).toInt() } }
        val hit by remember(lines) { derivedStateOf { controller.activeWordHit(displayTime) } }
        val activeWordId = hit?.word?.id
        val activeLineIndex = hit?.lineIndex ?: centerIdx
        val style = remember(layout.fontSize) { TextStyle(fontSize = layout.fontSize.sp, fontWeight = FontWeight.Bold, lineHeight = layout.slotHeight.sp) }

        Column(
            Modifier
                .fillMaxWidth()
                .wrapContentHeight(Alignment.Top, unbounded = true)
                .graphicsLayer {
                    // Aktive Zeile (Mitte des Stacks) auf Viewport-Mitte, plus Fortschritt in der Zeile.
                    val activeLineCenterY = layout.linesBeforeCenter * rowStridePx + slotHeightPx / 2
                    val progress = fractional - floor(fractional)
                    translationY = heightPx / 2 - activeLineCenterY - (progress * rowStridePx).toFloat()
                }
                .padding(horizontal = padding.dp),
        ) {
            for (delta in -layout.linesBeforeCenter..layout.linesBeforeCenter) {
                val lineIndex = centerIdx + delta
                Box(Modifier.fillMaxWidth().height(layout.slotHeight.dp), contentAlignment = Alignment.CenterStart) {
                    val line = lines.getOrNull(lineIndex)
                    if (line != null) {
                        LineText(
                            line = line,
                            isOnActiveLine = lineIndex == activeLineIndex,
                            activeWordId = activeWordId,
                            selectedWordId = selectedWordId,
                            style = style,
                            textColor = palette.textPrimary,
                            accent = accent,
                            onWordTap = controller::selectWordForLookup,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LineText(
    line: PlayerTranscriptLine,
    isOnActiveLine: Boolean,
    activeWordId: String?,
    selectedWordId: String?,
    style: TextStyle,
    textColor: androidx.compose.ui.graphics.Color,
    accent: androidx.compose.ui.graphics.Color,
    onWordTap: (PlayerTranscriptWord) -> Unit,
) {
    val baseOpacity = if (isOnActiveLine) PlayerTeleprompterMetrics.ACTIVE_LINE_TEXT_OPACITY else PlayerTeleprompterMetrics.INACTIVE_LINE_TEXT_OPACITY
    Row(Modifier.fillMaxWidth()) {
        for (word in line.words) {
            if (word.isWhitespaceOnly) {
                Text(word.text, style = style, color = androidx.compose.ui.graphics.Color.Transparent, maxLines = 1, softWrap = false)
                continue
            }
            val selected = word.id == selectedWordId
            val active = word.id == activeWordId
            Text(
                word.text,
                style = style,
                color = if (selected || active) accent else textColor.copy(alpha = baseOpacity.toFloat()),
                textDecoration = if (selected) TextDecoration.Underline else null,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Clip,
                modifier = Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClickLabel = "Look up or translate this word",
                ) { onWordTap(word) },
            )
        }
    }
}

/** Android: Sprachmodell fehlt — Download nur nach ausdrücklichem Tap (wie stashy/iOS-Sprachpakete). */
@Composable
private fun SpeechModelOfferCard(offer: SpeechModelOffer, onDownload: () -> Unit) {
    val palette = Theme.palette
    Column(
        Modifier.fillMaxSize().padding(horizontal = AppTheme.Layout.overlayPadding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.screenPadding, Alignment.CenterVertically),
    ) {
        Icon(Icons.Outlined.GraphicEq, contentDescription = null, tint = Theme.accent, modifier = Modifier.size(OverlayIconSize))
        Text("Speech model needed", style = AppType.titleMedium, color = palette.textPrimary, textAlign = TextAlign.Center)
        Text(
            "Read along transcribes the audiobook on this device. It needs the ${offer.languageName} speech model " +
                "(${offer.sizeText}), downloaded once.",
            style = AppType.bodyMedium,
            color = palette.textSecondary,
            textAlign = TextAlign.Center,
        )
        AbstandProminentButton(text = "Download ${offer.sizeText}", onClick = onDownload, icon = SF.arrowDownCircle)
    }
}

private val OverlayIconSize = 36.dp

@Composable
private fun DownloadingOverlay(progress: Double) {
    val palette = Theme.palette
    Column(
        Modifier.fillMaxSize().padding(horizontal = AppTheme.Layout.overlayPadding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing, Alignment.CenterVertically),
    ) {
        Text("Downloading speech model…", style = AppType.bodyMedium, color = palette.textSecondary)
        AbstandProgressBar(progress, trackColor = palette.card, contentDescription = "Speech model download")
        Text("${(progress * 100).roundToInt()} %", style = AppType.bodySmall, color = palette.textSecondary)
    }
}

@Composable
private fun ErrorOverlay(message: String, onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(horizontal = AppTheme.Layout.overlayPadding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.screenPadding, Alignment.CenterVertically),
    ) {
        Text(message, style = AppType.bodyMedium, color = AppTheme.danger, textAlign = TextAlign.Center)
        AbstandProminentButton(text = "Try again", onClick = onRetry)
    }
}

/** Aus (z. B. nach Medienwechsel) — iOS zeigt hier den Button im Player-Chrome. */
@Composable
private fun IdleOverlay(downloadReady: Boolean, hasBook: Boolean, onStart: () -> Unit) {
    val palette = Theme.palette
    Column(
        Modifier.fillMaxSize().padding(horizontal = AppTheme.Layout.overlayPadding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.screenPadding, Alignment.CenterVertically),
    ) {
        Icon(SF.textQuote, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(OverlayIconSize))
        Text(
            when {
                !hasBook -> "Nothing is playing."
                !downloadReady -> "Download the audiobook to read along."
                else -> "Read along with the narration."
            },
            style = AppType.bodyMedium,
            color = palette.textSecondary,
            textAlign = TextAlign.Center,
        )
        if (hasBook && downloadReady) {
            Spacer(Modifier.height(AppTheme.Layout.hairlineSpacing))
            AbstandPrimaryButton(text = "Read along", onClick = onStart)
        }
    }
}
