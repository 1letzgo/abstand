package de.letzgo.abstand.ui

import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import de.letzgo.abstand.model.AdminStore
import de.letzgo.abstand.reader.EbookReaderLauncher
import de.letzgo.abstand.reader.EbookTextIndexProvider
import de.letzgo.abstand.transcript.TeleprompterEbookTextProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.ui.detail.BookDetailDestination
import de.letzgo.abstand.ui.metadata.ChaptersEditorSheet
import de.letzgo.abstand.ui.metadata.EditMetadataSheet
import de.letzgo.abstand.ui.metadata.MatchMetadataSheet
import de.letzgo.abstand.ui.metadata.MetadataActions
import de.letzgo.abstand.ui.podcasts.PodcastEpisodeDetailDestination
import de.letzgo.abstand.ui.settings.SettingsIntegration
import de.letzgo.abstand.transcript.TranscriptSettings
import de.letzgo.abstand.ui.stats.StatsNavigation
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Verdrahtung zwischen den parallel portierten UI-Teilen (iOS: alles hängt am selben `AppModel`
 * und denselben `navigationDestination`s). Einmal aus `Application.onCreate`:
 * Detail-Admin-Sheets, Stats-Navigation, `bookUpdated` → Katalog/Home, Settings-Andockpunkte,
 * Transkript-Vorproduktion, Admin-Jobs.
 */
object AppIntegration {
    /** Offenes Metadaten-Sheet (iOS: `.sheet(item:)` an der Detailseite). */
    enum class MetadataSheet { Edit, Match, Chapters }

    private var sheet by mutableStateOf<Pair<MetadataSheet, String>?>(null)

    fun install(model: AppModel) {
        BookDetailDestination.defaultEditMetadata = { sheet = MetadataSheet.Edit to it.id }
        BookDetailDestination.defaultMatchMetadata = { sheet = MetadataSheet.Match to it.id }
        BookDetailDestination.defaultEditChapters = { sheet = MetadataSheet.Chapters to it.id }
        // eBook-Reader (Detailseite, Now Playing) und eBook-Text im Teleprompter.
        BookDetailDestination.defaultOpenEbook = { EbookReaderLauncher.open(it) }
        TeleprompterEbookTextProvider.indexLoader = { id ->
            withContext(Dispatchers.Main) { EbookTextIndexProvider.index(id)?.index }
        }
        StatsNavigation.bookDetail = { id -> BookDetailDestination(id) }
        StatsNavigation.episodeDetail = { ep -> PodcastEpisodeDetailDestination(ep) }
        // iOS: `applyUpdatedBookToLoadedLists` — frischer Stand nach Metadaten-/Kapitel-Änderung.
        model.scope.launch {
            MetadataActions.bookUpdated.collect { fresh ->
                model.catalog.applyUpdatedBook(fresh)
                model.home.applyUpdatedBook(fresh)
            }
        }
        // Transkript-Vorproduktion an den App-Lebenszyklus koppeln.
        TranscriptSettings.install(model.appContext)
        // Settings-Andockpunkte (Vorproduktions-Status, Download löschen).
        SettingsIntegration.transcriptPrefetchStatus =
            TranscriptSettings.prefetchSubtitle().stateIn(model.scope, SharingStarted.WhileSubscribed(STATUS_STOP_TIMEOUT_MS), null)
        SettingsIntegration.removeLocalDownload = { id -> model.player.downloads.removeLocalDownload(id) }
        // Laufende M4B-Encode-Jobs des aktiven Servers wieder aufnehmen (iOS: beim Start).
        model.scope.launch {
            model.session.isLoggedIn.collect { loggedIn -> if (loggedIn) AdminStore.prepared() }
        }
    }

    private const val STATUS_STOP_TIMEOUT_MS = 5_000L
    /** In der Tab-Shell: zeigt das angeforderte Metadaten-Sheet. */
    @Composable
    fun MetadataSheetsHost() {
        val (kind, itemId) = sheet ?: return
        val dismiss = { sheet = null }
        when (kind) {
            MetadataSheet.Edit -> EditMetadataSheet(itemId, onDismiss = dismiss)
            MetadataSheet.Match -> MatchMetadataSheet(itemId, onDismiss = dismiss)
            MetadataSheet.Chapters -> ChaptersEditorSheet(itemId, onDismiss = dismiss)
        }
    }
}
