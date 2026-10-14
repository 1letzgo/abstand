package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.swiftTrim
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Was gerade im Player liegt (iOS: `player.activeBook` + `activePlaybackEpisodeId` + `isPlaying`).
 * [progressKey] = `progressLookupKey` des Mediums (`<itemId>` bzw. `<itemId>-<episodeId>`).
 */
data class NowPlayingState(val progressKey: String? = null, val isPlaying: Boolean = false) {
    /** iOS: `isActivelyPlayingMedia(libraryItemId:episodeId:)` — genau dieses Medium ist geladen. */
    fun isActive(itemId: String, episodeId: String?): Boolean {
        val key = progressKey ?: return false
        return key == progressKeyOf(itemId, episodeId)
    }

    /** Geladen **und** spielt. */
    fun isPlaying(itemId: String, episodeId: String?): Boolean = isPlaying && isActive(itemId, episodeId)

    companion object {
        /** Gleiche Regel wie `AbsUserMediaProgress.progressLookupKey` (beide IDs getrimmt). */
        fun progressKeyOf(itemId: String, episodeId: String?): String {
            val e = episodeId?.swiftTrim().orEmpty()
            val i = itemId.swiftTrim()
            return if (e.isEmpty()) i else "$i-$e"
        }
    }
}

/**
 * Brücke von Karten (Home, Suche, Kataloge) zum Player — Play/Pause-Pille, „Now Playing“ öffnen.
 * Der Player-Port verdrahtet eine echte Implementierung in [AppModel.playbackLauncher]; bis dahin
 * [None] (keine Wirkung, nichts spielt).
 */
interface PlaybackLauncher {
    /** Aktuelles Medium + Spielzustand (iOS: `player.$activeBook`/`$activePlaybackEpisodeId`/`$isPlaying`). */
    val nowPlaying: StateFlow<NowPlayingState>

    /** iOS: `model.play(book:)` / `playPodcastEpisode(_:)` — startet bzw. setzt fort. */
    fun play(itemId: String, episodeId: String? = null)

    /** iOS: Vollbild-Player zeigen (`FullScreenOverlayPresenter`). */
    fun openNowPlaying()

    /** iOS: `player.pause()` — nur für das bereits geladene Medium. */
    fun pause() {}

    /** iOS: `player.play()` — geladenes Medium fortsetzen. */
    fun resume() {}

    /** No-op-Standard bis zur Player-Verdrahtung. */
    object None : PlaybackLauncher {
        override val nowPlaying: StateFlow<NowPlayingState> = MutableStateFlow(NowPlayingState()).asStateFlow()
        override fun play(itemId: String, episodeId: String?) {}
        override fun openNowPlaying() {}
    }
}

/** Download-Zustand eines Mediums für Karten-Badges (iOS: `LibraryBookRowLiveState.isDownloaded/…`). */
data class DownloadBadgeState(
    val isDownloaded: Boolean = false,
    val isDownloading: Boolean = false,
    /** 0…1 während des Downloads. */
    val progress: Double = 0.0,
)

/**
 * Brücke zu den Downloads (Badges auf Karten, Offline-Home „nur Heruntergeladenes“). Schlüssel ist
 * die Offline-Storage-ID wie auf iOS: Hörbuch = `libraryItemId`, Podcast-Folge =
 * `progressLookupKey` mit `/` → `_` (iOS: `podcastEpisodeOfflineStorageId`). Der Download-Port
 * ersetzt [None] über [AppModel.downloadStatus].
 */
interface DownloadStatusSource {
    /** Laufende und fertige Downloads je Storage-ID. */
    val states: StateFlow<Map<String, DownloadBadgeState>>

    /** iOS: `downloadedShelfBooks` — heruntergeladene Hörbücher (volle Metadaten oder Manifest-Stub). */
    fun downloadedBooks(): List<AbsBook> = emptyList()

    /** Heruntergeladene Podcast-Folgen (aus `download.json`-Manifesten). */
    fun downloadedEpisodes(): List<AbsPodcastEpisodeListItem> = emptyList()

    object None : DownloadStatusSource {
        override val states: StateFlow<Map<String, DownloadBadgeState>> = MutableStateFlow(emptyMap<String, DownloadBadgeState>()).asStateFlow()
    }

    companion object {
        /** iOS: `podcastEpisodeOfflineStorageId`. */
        fun storageId(itemId: String, episodeId: String?): String =
            NowPlayingState.progressKeyOf(itemId, episodeId).replace("/", "_")
    }
}
