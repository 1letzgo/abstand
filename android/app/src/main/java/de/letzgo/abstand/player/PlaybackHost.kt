package de.letzgo.abstand.player

import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import de.letzgo.abstand.data.AbsUserMediaProgress

/**
 * Was der Player-Teil vom App-Zustand braucht (iOS: die Stellen von `AppModel`, die
 * `PlaybackController`-Callbacks bedienen). Implementiert vom Session-/Store-Teil (Integrator) und
 * in [PlaybackHostBridge] mit dem [PlaybackController] verdrahtet.
 */
interface PlaybackHost {
    /** iOS: `AppModel.client` — Client der aktiven Session; `null` ohne Login. */
    val apiClient: AbsApiClient?

    /** iOS: `mayUseServerNetwork` — `false` im Offline-Home-Modus (`Keys.offlineHomeMode`). */
    val mayUseServerNetwork: Boolean

    /** iOS: `isNetworkReachable`. */
    val isNetworkReachable: Boolean

    /** iOS: `networkUsesUnmeteredLAN` (WLAN/Ethernet) — Bedingung für Smart-Download. */
    val isNetworkUnmetered: Boolean

    /** iOS: `progressByItemId[key]`. */
    fun progress(progressKey: String): AbsUserMediaProgress?

    /**
     * iOS: Kern von `recordActivePlaybackProgressLocally` — Zeile in `progressByItemId` + Room
     * (`LocalLibraryStore.upsertProgress`, nie `replaceAllProgress`) schreiben, Continue-Regal angleichen;
     * `markPendingServerSync` → Key in `Keys.pendingLocalProgressSyncKeys` aufnehmen.
     */
    fun upsertProgress(progress: AbsUserMediaProgress, markPendingServerSync: Boolean)

    /** iOS: `pendingLocalProgressSyncKeys.remove(key)` nach erfolgreichem PATCH. */
    fun clearPendingLocalProgressSync(progressKey: String)

    /**
     * Folge der aktuellen Wiedergabe (iOS: `podcastEpisodeForSmartDownloadFromActivePlayback`) —
     * aus Listen/Manifest oder `null`; der Bridge baut sonst eine synthetische Zeile.
     */
    fun podcastEpisode(libraryItemId: String, episodeId: String): AbsPodcastEpisodeListItem?

    /**
     * iOS: `handleAudiobookPlaybackCompleted` → `markFinished(bookId:)` bzw.
     * `handlePodcastEpisodePlaybackCompleted` → `markPodcastEpisodeFinished(_:)` — inkl. lokalem
     * „Fertig“ (`Keys.localFinishedProgressKeys`), Player schließen und
     * [de.letzgo.abstand.downloads.DownloadManager.removeLocalDownloadIfFinishedSetting].
     */
    suspend fun markPlaybackFinished(libraryItemId: String, episodeId: String?)

    /** Smart-Download hat für den laufenden Titel einen Download gestartet (Speicher-ID). */
    fun onSmartDownloadStarted(storageItemId: String) {}
}

/**
 * Daten für Android Auto (iOS: was `CarPlayCoordinator` aus `AppModel` liest). Implementiert vom
 * Integrator; [AbstandPlaybackService] baut daraus den Browse-Baum.
 */
interface BrowseSource {
    /** iOS: `model.isLoggedIn`. */
    val isLoggedIn: Boolean

    /**
     * iOS: Regal `recentlyListened`/`itemsInProgressFallback` gemischt per
     * `ABSStartShelfMergedRow.merged` — lädt bei Bedarf das Dashboard (`loadStartDashboard`).
     */
    suspend fun continueListeningRows(): List<AbsStartShelfMergedRow>

    /** iOS: `downloadedRowsForCarPlay()` (Default: [de.letzgo.abstand.downloads.DownloadManager.downloadedRows]). */
    suspend fun downloadedRows(): List<AbsStartShelfMergedRow>

    /** Optional (nicht in iOS-CarPlay): Hörbücher der aktiven Bibliothek; `null` = Tab ausblenden. */
    suspend fun libraryBookRows(): List<AbsStartShelfMergedRow>? = null

    /** Optional (nicht in iOS-CarPlay): neueste Podcast-Folgen; `null` = Tab ausblenden. */
    suspend fun podcastEpisodeRows(): List<AbsStartShelfMergedRow>? = null

    /** iOS: `progressByItemId[key]` für den Fortschrittsbalken der Zeile. */
    fun progress(progressKey: String): AbsUserMediaProgress?

    /** Cover-URL (iOS: `model.coverURL(for:)`), `null` ohne Server. */
    fun coverUrl(libraryItemId: String): String?

    /**
     * Wiedergabe starten (iOS: `model.play(book:)` / `model.playPodcastEpisode(_:)`); kehrt zurück,
     * wenn der Titel geladen ist (oder der Start fehlschlug).
     */
    suspend fun play(row: AbsStartShelfMergedRow)

    /**
     * Medien-Wiederaufnahme (Auto/Systemkarte „Fortsetzen“): letzten Titel ohne Auto-Play laden
     * (iOS: Launch-Restore `play(book:autoPlay: false)`). `false`, wenn nichts wiederherstellbar ist.
     */
    suspend fun restoreLastPlayback(): Boolean = false
}
