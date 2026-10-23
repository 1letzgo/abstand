package de.letzgo.abstand.ui.settings

import kotlinx.coroutines.flow.StateFlow

/**
 * Andockpunkte der Settings an Stores anderer Domänen (Transkript-Vorproduktion, Downloads). Der
 * Integrator setzt sie beim App-Start; ohne Belegung blendet Settings die betroffene Zeile aus
 * bzw. zeigt den Standardtext.
 */
object SettingsIntegration {
    /**
     * iOS: `transcriptPrefetcher` — laufender Status für „Prepare transcripts in background“
     * (`null` = nichts läuft → Standardtext).
     */
    @Volatile var transcriptPrefetchStatus: StateFlow<String?>? = null

    /**
     * iOS: `removeLocalDownload(bookId:)` — Download abbrechen/löschen und Regale/Download-Liste
     * nachziehen. Standard ohne Integrator: nur Queue + Dateien ([DownloadManager]).
     */
    @Volatile var removeLocalDownload: (storageItemId: String) -> Unit = { id ->
        de.letzgo.abstand.downloads.DownloadManager.cancel(id)
        de.letzgo.abstand.downloads.DownloadManager.deleteDownload(id)
    }
}
