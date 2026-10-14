package de.letzgo.abstand.ui.settings

import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import de.letzgo.abstand.model.AppSettings
import de.letzgo.abstand.model.TranslationTargetLanguage
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardPickerRow
import de.letzgo.abstand.ui.components.SettingsCardToggleRow
import kotlinx.coroutines.flow.MutableStateFlow

/** iOS: `SettingsPlaybackView` — Sektionen „Playback“ und „Teleprompter“. */
fun LazyListScope.settingsPlaybackSections() {
    item(key = "playback") { SettingsPlaybackSection() }
    item(key = "teleprompter") { SettingsTeleprompterSection() }
}

@Composable
private fun SettingsPlaybackSection() {
    val context = LocalContext.current
    val player = remember { PlaybackController.shared(context) }
    val back by player.skipBackwardSeconds.collectAsState()
    val forward by player.skipForwardSeconds.collectAsState()
    val openPlayer by AppSettings.openPlayerWhenStartPlaying.collectAsState()
    ServerAdminSection("Playback") {
        AbstandGroupedCard {
            SettingsCardPickerRow(
                icon = SF.gobackward(back),
                title = "Skip back",
                selection = back,
                options = PlaybackController.skipIntervalOptions,
                label = { "$it s" },
                onSelect = { player.setSkipBackwardSeconds(it) },
            )
        }
        AbstandGroupedCard {
            SettingsCardPickerRow(
                icon = SF.goforward(forward),
                title = "Skip forward",
                selection = forward,
                options = PlaybackController.skipIntervalOptions,
                label = { "$it s" },
                onSelect = { player.setSkipForwardSeconds(it) },
            )
        }
        AbstandGroupedCard {
            SettingsCardToggleRow(
                icon = SF.playCircle,
                title = "Open player when start playing",
                checked = openPlayer,
                onCheckedChange = { AppSettings.setOpenPlayerWhenStartPlaying(it) },
            )
        }
    }
}

@Composable
private fun SettingsTeleprompterSection() {
    val language by AppSettings.translationTargetLanguageCode.collectAsState()
    val prefetch by AppSettings.readAlongPrefetchEnabled.collectAsState()
    val statusFlow = remember { SettingsIntegration.transcriptPrefetchStatus ?: MutableStateFlow(null) }
    val status by statusFlow.collectAsState()
    val options = remember(language) { TranslationTargetLanguage.pickerOptions(language) }
    ServerAdminSection("Teleprompter") {
        AbstandGroupedCard {
            SettingsCardPickerRow(
                icon = SF.translate,
                title = "Translation language",
                selection = options.firstOrNull { it.first == language } ?: (language to TranslationTargetLanguage.displayName(language)),
                options = options,
                label = { it.second },
                onSelect = { AppSettings.setTranslationTargetLanguageCode(it.first) },
            )
        }
        AbstandGroupedCard {
            SettingsCardToggleRow(
                icon = SF.textBubble,
                title = "Prepare transcripts in background",
                // iOS: nur bei eingeschaltetem Schalter ein Statustext.
                subtitle = if (prefetch) status ?: PREFETCH_IDLE_TEXT else null,
                checked = prefetch,
                onCheckedChange = { AppSettings.setReadAlongPrefetchEnabled(it) },
            )
        }
    }
}

/** iOS: Ruhetext der Transkript-Vorproduktion. */
private const val PREFETCH_IDLE_TEXT = "Downloaded titles are up to date. More is prepared overnight while charging."
