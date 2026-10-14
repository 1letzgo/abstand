package de.letzgo.abstand.ui.transcript

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.abstand.transcript.PlayerLiveTranscriptionController
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandLabeledLoadingState
import de.letzgo.abstand.ui.components.AbstandSheet

/**
 * iOS: `PlayerTranscriptRecapCard` — „Last 5 minutes". Startet beim Öffnen [PlayerLiveTranscriptionController.generateRecap]
 * (Cache zuerst, Lücken werden auf dem Gerät nachtranskribiert). Android zeigt immer das Transkript
 * (kein On-Device-Sprachmodell für Zusammenfassungen, iOS-Fallbackpfad).
 */
@Composable
fun TranscriptRecapSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val controller = remember { PlayerLiveTranscriptionController.shared(context) }
    LaunchedEffect(Unit) { controller.generateRecap() }
    AbstandSheet(title = "Recap", onDismiss = onDismiss, onConfirm = onDismiss, confirmLabel = "Done") {
        Box(Modifier.fillMaxWidth().heightIn(min = RecapMinHeight, max = RecapMaxHeight)) {
            TranscriptRecapContent(controller)
        }
    }
}

/** Inhalt ohne Sheet-Rahmen (z. B. in einer Player-Karte). */
@Composable
fun TranscriptRecapContent(controller: PlayerLiveTranscriptionController, modifier: Modifier = Modifier) {
    val palette = Theme.palette
    val generating by controller.isGeneratingRecap.collectAsState()
    val text by controller.recapText.collectAsState()
    val error by controller.recapErrorMessage.collectAsState()
    val notice by controller.recapFallbackNotice.collectAsState()
    val showsTranscript by controller.recapShowsTranscript.collectAsState()

    androidx.compose.foundation.layout.Column(
        modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
            Text(
                "LAST 5 MINUTES",
                style = IosType.caption.copy(fontWeight = FontWeight.Bold, letterSpacing = RecapTitleTracking),
                color = palette.textSecondary,
            )
            if (showsTranscript) {
                Text(
                    "transcript",
                    style = IosType.caption2.copy(fontWeight = FontWeight.Medium),
                    color = palette.textSecondary,
                    modifier = Modifier
                        .background(palette.card.copy(alpha = 0.9f), CircleShape)
                        .padding(horizontal = AppTheme.Layout.compactSpacing, vertical = AppTheme.Layout.hairlineSpacing),
                )
            }
        }
        when {
            generating -> AbstandLabeledLoadingState(text = "Creating on-device recap…", modifier = Modifier.heightIn(min = RecapMinHeight))
            !text.isNullOrEmpty() -> {
                SelectionContainer(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
                    Text(text!!, style = IosType.body, color = palette.textPrimary, modifier = Modifier.fillMaxWidth())
                }
                notice?.let { NoticeText(it) }
            }
            error != null -> {
                AbstandEmptyScreen(title = "Recap unavailable", icon = SF.sparkles, description = error, modifier = Modifier.heightIn(min = RecapMinHeight))
                notice?.let { NoticeText(it) }
            }
            else -> AbstandEmptyScreen(
                title = "No recap yet",
                icon = SF.sparkles,
                description = "Listen a little longer, then try creating a recap again.",
                modifier = Modifier.heightIn(min = RecapMinHeight),
            )
        }
    }
}

@Composable
private fun NoticeText(notice: String) {
    val palette = Theme.palette
    Text(
        notice,
        style = IosType.caption,
        color = palette.textSecondary,
        maxLines = 3,
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.card.copy(alpha = 0.9f))
            .padding(AppTheme.Layout.withinSectionSpacing),
    )
}

private val RecapMinHeight = 220.dp
private val RecapMaxHeight = 520.dp
private val RecapTitleTracking = 0.6.sp
