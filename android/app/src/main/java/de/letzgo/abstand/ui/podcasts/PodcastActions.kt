package de.letzgo.abstand.ui.podcasts

import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Brücke vom Podcast-Port zu Player und Download-Manager (iOS: `playPodcastEpisode`,
 * `startDownloadPodcastEpisode`, `removeLocalDownload`, `downloadedItemIds`, `player.isPlaying` …).
 * Player/Downloads werden parallel portiert; bis der Integrator eine echte Implementierung in
 * [de.letzgo.abstand.model.PodcastStore.actions] setzt, gilt [None] (alles No-op).
 *
 * [revision] muss bei **jeder** Änderung von Download- oder Wiedergabezustand hochzählen — die
 * Zeilen lesen ihn, um neu zu rendern (iOS: `LibraryPodcastEpisodeRowLiveState`).
 */
interface PodcastActions {
    /** Zähler für Download-/Wiedergabeänderungen (Compose beobachtet ihn). */
    val revision: StateFlow<Long> get() = NoRevision

    /** iOS: `playPodcastEpisode(_:resumeAtOverride:)` — [resumeAt] `0` = von vorn (nach „Finished“). */
    fun play(episode: AbsPodcastEpisodeListItem, resumeAt: Double? = null) {}

    /** iOS: `player.pause()` für die laufende Folge. */
    fun pause() {}

    /** iOS: `isActivelyPlayingMedia(libraryItemId:episodeId:) && player.isPlaying`. */
    fun isPlaying(itemId: String, episodeId: String): Boolean = false

    /** iOS: `startDownloadPodcastEpisode` — lokaler Offline-Download (FIFO-Queue). */
    fun enqueueDownload(episode: AbsPodcastEpisodeListItem) {}

    /** iOS: `removeLocalDownload(bookId: podcastEpisodeOfflineStorageId(episode))`. */
    fun removeDownload(itemId: String, episodeId: String) {}

    /** Folge liegt vollständig lokal (iOS: `downloadedItemIds.contains(storageId)`). */
    fun isDownloaded(itemId: String, episodeId: String): Boolean = false

    /** Download-Fortschritt 0…1, solange aktiv/wartend; `null` = kein laufender Download. */
    fun downloadProgress(itemId: String, episodeId: String): Double? = null

    /**
     * Offline-Stubs aus den `download.json`-Manifesten (iOS: `podcastEpisodesFromLocalDownloadManifests`).
     * [showId] `null` = alle Sendungen; [libraryId] grenzt nur ein, wenn beide Seiten eine ID haben.
     */
    fun downloadedEpisodes(showId: String?, libraryId: String?): List<AbsPodcastEpisodeListItem> = emptyList()

    /** Alle lokalen Downloads einer Sendung entfernen + ggf. Wiedergabe beenden (iOS: `removePodcastShowFromLibrary`). */
    fun removeAllDownloadsForShow(showId: String) {}

    /** iOS: `localFinishedProgressKeys` (offline beendet, noch nicht synchronisiert). */
    fun isLocallyMarkedFinished(progressKey: String): Boolean = false

    /** No-op-Standard bis zur Verdrahtung mit Player/Downloads. */
    object None : PodcastActions

    companion object {
        internal val NoRevision: StateFlow<Long> = MutableStateFlow(0L).asStateFlow()
    }
}

/** iOS: `podcastEpisodeOfflineStorageId` — Ordnername eines Folgen-Downloads. */
fun podcastEpisodeOfflineStorageId(episode: AbsPodcastEpisodeListItem): String =
    episode.progressLookupKey.replace("/", "_")
