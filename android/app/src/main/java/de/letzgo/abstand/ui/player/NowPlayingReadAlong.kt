package de.letzgo.abstand.ui.player

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import de.letzgo.abstand.transcript.PlayerLiveTranscriptionController
import de.letzgo.abstand.ui.transcript.TeleprompterFontSize
import de.letzgo.abstand.ui.transcript.TranscriptRecapSheet
import de.letzgo.abstand.ui.transcript.TranscriptTeleprompter
import kotlinx.coroutines.flow.StateFlow

/**
 * Read-along-Anbindung des Vollplayers (iOS: `ReadAlongPanelButton`, Recap-Knopf, Teleprompter-
 * Karte mit ±-Schriftgröße). Als Parameter, damit [NowPlayingScreen] ohne Transkript-Pipeline
 * (Vorschau, Tests) funktioniert — `null` blendet Read along und Recap aus.
 */
@Stable
class NowPlayingReadAlong(
    /** iOS: `liveTranscription.isTeleprompterModeActive`. */
    val isModeActive: StateFlow<Boolean>,
    /** iOS: `player.isReadAlongDownloadReady` — nur mit vollständigem Download. */
    val isDownloadReady: () -> Boolean,
    /** iOS: `liveTranscription.toggle(player:)`. */
    val toggle: () -> Unit,
    val increaseFont: () -> Unit,
    val decreaseFont: () -> Unit,
    /** Teleprompter (iOS: `PlayerLiveTranscriptPanelView`). */
    val content: @Composable () -> Unit,
    /** Recap der letzten 5 Minuten (iOS: `recapKaraokeCard`; Android als Sheet). */
    val recapSheet: (@Composable (onDismiss: () -> Unit) -> Unit)?,
)

/** Standard-Anbindung an [PlayerLiveTranscriptionController] (`null`, wenn Read along nicht verfügbar ist). */
@Composable
fun rememberTranscriptReadAlong(): NowPlayingReadAlong? {
    val context = LocalContext.current
    return remember {
        val controller = PlayerLiveTranscriptionController.shared(context)
        if (!controller.isReadAlongAvailable) {
            null
        } else {
            NowPlayingReadAlong(
                isModeActive = controller.isTeleprompterModeActive,
                isDownloadReady = { controller.isReadAlongDownloadReady() },
                toggle = { controller.toggle() },
                increaseFont = { TeleprompterFontSize.increase() },
                decreaseFont = { TeleprompterFontSize.decrease() },
                content = { TranscriptTeleprompter(autoStart = true, stopOnDispose = true) },
                recapSheet = if (controller.canGenerateRecap) { onDismiss -> TranscriptRecapSheet(onDismiss) } else null,
            )
        }
    }
}
