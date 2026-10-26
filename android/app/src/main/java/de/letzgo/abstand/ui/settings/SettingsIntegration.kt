package de.letzgo.abstand.ui.settings

import kotlinx.coroutines.flow.StateFlow

/**
 * Andockpunkte der Settings an Stores anderer Domänen (Home, Transkript-Vorproduktion). Der
 * Integrator setzt sie beim App-Start; ohne Belegung blendet Settings die betroffene Zeile aus
 * bzw. zeigt den Standardtext.
 */
object SettingsIntegration {
    /** iOS: `SettingsAppearanceHomeView` — Home-Regale ein-/ausblenden und sortieren (Home-Store). */
    @Volatile var homeShelfSettings: HomeShelfSettings? = null

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

/** iOS: `startSettingsCategoryList`, `isStartCategoryEnabled`, `setStartCategoryEnabled`, `moveStartSettingsCategory`. */
interface HomeShelfSettings {
    /** Regale in Anzeige-Reihenfolge: (category, label). */
    val categories: StateFlow<List<Pair<String, String>>>
    /** Deaktivierte Kategorien (für Rekomposition der Schalter). */
    val disabledCategories: StateFlow<Set<String>>

    /** iOS: `refreshStartSettingsCategoryListLabels`. */
    fun refreshLabels()
    fun setEnabled(category: String, enabled: Boolean)
    /** iOS: `moveStartSettingsCategory(dragging:onto:)`. */
    fun move(dragging: String, onto: String)
}
