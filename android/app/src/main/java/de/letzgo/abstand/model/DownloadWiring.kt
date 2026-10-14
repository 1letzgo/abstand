package de.letzgo.abstand.model

import android.util.Log
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.trimmedOrEmpty
import de.letzgo.abstand.downloads.DownloadHost
import de.letzgo.abstand.downloads.DownloadManager
import de.letzgo.abstand.store.ActiveLibraryIdsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * iOS: Download-Teile von `AppModel` — `downloadedItemIds` (je Account unter `Keys.downloads.<account>`),
 * `persistDownloads`, `loadDownloadedItemIdsForActiveAccount`, `removeLocalDownload`,
 * `downloadManifestBelongsToActiveAccount`, `refreshDownloadedShelfFromManifests` und der
 * Completion-Block von `beginOfflineItemDownload`.
 *
 * Implementiert [DownloadHost] (für [DownloadManager]) und [DownloadStatusSource] (Karten-Badges,
 * Offline-Home). Manifeste werden einmal von der Platte gelesen und im Speicher gehalten
 * ([manifests]) — Home ruft [downloadedBooks] synchron auf dem Main-Thread.
 */
class DownloadWiring(private val model: AppModel) : DownloadHost, DownloadStatusSource {
    private val session: SessionStore get() = model.session

    private val _downloadedIds = MutableStateFlow<Set<String>>(emptySet())
    /** iOS: `downloadedItemIds` — fertige Downloads des aktiven Accounts (Speicher-IDs). */
    val downloadedIds: StateFlow<Set<String>> = _downloadedIds.asStateFlow()

    private val _states = MutableStateFlow<Map<String, DownloadBadgeState>>(emptyMap())
    override val states: StateFlow<Map<String, DownloadBadgeState>> = _states.asStateFlow()

    /** Fertige Downloads mit Manifest (gefiltert auf [downloadedIds]). */
    @Volatile private var manifests: List<DownloadManager.OfflineDownload>? = null

    /** Zählt bei jeder Änderung (Liste, Fortschritt) hoch — Podcast-Zeilen beobachten ihn. */
    private val _revision = MutableStateFlow(0L)
    val revision: StateFlow<Long> = _revision.asStateFlow()

    fun attach() {
        model.scope.launch {
            combine(_downloadedIds, DownloadManager.activeItemId, DownloadManager.progress, DownloadManager.queuedItemIds) { ids, active, progress, queued ->
                buildMap {
                    ids.forEach { put(it, DownloadBadgeState(isDownloaded = true)) }
                    queued.forEach { if (it !in ids) put(it, DownloadBadgeState(isDownloading = true, progress = 0.0)) }
                    if (active != null) put(active, DownloadBadgeState(isDownloading = true, progress = progress))
                }
            }.collect {
                _states.value = it
                _revision.value += 1
            }
        }
    }

    // MARK: - Laden / Persistieren (iOS: `downloadsUserDefaultsKey`)

    private fun downloadsPrefsKey(): String = SessionLogic.accountScopedKey(Keys.downloads, session.activeAccountKey.value)

    /** iOS: `loadDownloadedItemIdsForActiveAccount` (+ einmalige Migration der globalen Liste). */
    fun loadForActiveAccount() {
        val key = downloadsPrefsKey()
        if (!Prefs.has(key)) {
            Prefs.string(Keys.downloads)?.takeIf { ActiveLibraryIdsStore.decode(it).isNotEmpty() }?.let { Prefs.setString(key, it) }
        }
        val stored = ActiveLibraryIdsStore.decode(Prefs.string(key)).toSet()
        _downloadedIds.value = stored
        manifests = null
        model.scope.launch { refreshManifests() }
    }

    /** iOS: `persistDownloads(skipRefresh:)`. */
    fun persistDownloads(skipRefresh: Boolean = false) {
        ActiveLibraryIdsStore.encode(_downloadedIds.value.sorted())?.let { Prefs.setString(downloadsPrefsKey(), it) }
        if (!skipRefresh) model.scope.launch { refreshManifests() }
    }

    fun clearInMemory() {
        _downloadedIds.value = emptySet()
        manifests = emptyList()
    }

    /**
     * Manifeste neu einlesen (IO), Liste auf vorhandene Ordner eingrenzen, Home-Regal angleichen
     * (iOS: `refreshDownloadedShelfFromManifests`).
     */
    suspend fun refreshManifests() {
        val ids = _downloadedIds.value
        val scanned = withContext(Dispatchers.IO) { DownloadManager.scanDownloads().filter { it.storageItemId in ids } }
        manifests = scanned
        // Gespeicherte IDs ohne Manifest (Ordner gelöscht) nicht als „heruntergeladen“ führen.
        val present = scanned.mapTo(HashSet()) { it.storageItemId }
        if (present != ids) {
            _downloadedIds.value = present
            ActiveLibraryIdsStore.encode(present.sorted())?.let { Prefs.setString(downloadsPrefsKey(), it) }
        }
        _revision.value += 1
        model.home.refreshDownloadedShelf()
    }

    private fun cachedManifests(): List<DownloadManager.OfflineDownload> {
        manifests?.let { return it }
        // Erster synchroner Zugriff (Offline-Kaltstart) — kleine JSON-Dateien, einmalig.
        val ids = _downloadedIds.value
        val scanned = DownloadManager.scanDownloads().filter { it.storageItemId in ids }
        manifests = scanned
        return scanned
    }

    // MARK: - Abfragen

    fun isDownloaded(storageId: String): Boolean = storageId in _downloadedIds.value

    /** iOS: `downloadManifestBelongsToActiveAccount` — Manifest ohne Bibliothek zählt immer. */
    fun manifestBelongsToActiveAccount(manifest: AbsDownloadManifest): Boolean {
        val lid = manifest.libraryId.trimmedOrEmpty()
        if (lid.isEmpty()) return true
        val active = session.activeBooksLibraryIds.value + session.activePodcastLibraryIds.value
        if (active.isEmpty()) return true
        return lid in active
    }

    /** iOS: `downloadedRowsForCarPlay()`. */
    fun downloadedRows(): List<AbsStartShelfMergedRow> =
        cachedManifests().filter { manifestBelongsToActiveAccount(it.manifest) }.map { DownloadManager.offlineRow(it.manifest) }

    override fun downloadedBooks(): List<AbsBook> =
        cachedManifests()
            .filter { it.manifest.episodeId.trimmedOrEmpty().isEmpty() && manifestBelongsToActiveAccount(it.manifest) }
            .map { AbsBook.fromDownloadManifest(it.manifest) }

    override fun downloadedEpisodes(): List<AbsPodcastEpisodeListItem> =
        cachedManifests()
            .filter { it.manifest.episodeId.trimmedOrEmpty().isNotEmpty() && manifestBelongsToActiveAccount(it.manifest) }
            .mapNotNull { (DownloadManager.offlineRow(it.manifest) as? AbsStartShelfMergedRow.PodcastEpisode)?.episode }

    /** Manifest eines fertigen Downloads (aus dem Cache). */
    fun manifest(storageId: String): AbsDownloadManifest? = cachedManifests().firstOrNull { it.storageItemId == storageId }?.manifest

    /** Alle Downloads (Speicher-IDs) zu einem Library-Item (Hörbuch oder Sendung). */
    fun storageIdsForLibraryItem(libraryItemId: String): List<String> =
        cachedManifests().filter { it.manifest.libraryItemId == libraryItemId }.map { it.storageItemId }

    // MARK: - Ändern

    /** iOS: `removeLocalDownload(bookId:)` — Lauf abbrechen, Ordner löschen, Liste persistieren. */
    fun removeLocalDownload(storageId: String) {
        DownloadManager.cancel(storageId)
        _downloadedIds.value = _downloadedIds.value - storageId
        manifests = manifests?.filterNot { it.storageItemId == storageId }
        persistDownloads(skipRefresh = true)
        model.scope.launch {
            withContext(Dispatchers.IO) { DownloadManager.deleteDownload(storageId) }
            refreshManifests()
        }
    }

    /** Nach „Fertig“: iOS `removeLocalDownloadIfFinishedSetting`. */
    fun removeIfFinishedSetting(storageId: String) {
        if (DownloadManager.removeLocalDownloadIfFinishedSetting(storageId, isDownloaded(storageId))) {
            _downloadedIds.value = _downloadedIds.value - storageId
            manifests = manifests?.filterNot { it.storageItemId == storageId }
            persistDownloads()
        }
    }

    // MARK: - DownloadHost

    override val apiClient: AbsApiClient?
        get() = session.client ?: session.clientForOfflineLocalPlayback()

    override fun onDownloadFinished(storageItemId: String, ok: Boolean) {
        model.scope.launch {
            if (ok) {
                _downloadedIds.value = _downloadedIds.value + storageItemId
                persistDownloads()
            } else {
                Log.w(TAG, "Download failed: $storageItemId")
                session.setErrorMessage("Download failed.")
            }
        }
    }

    companion object {
        private const val TAG = "AbstandDownloads"
    }
}
