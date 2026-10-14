package de.letzgo.abstand.transcript

import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.logic.PlayerTranscriptTrackSource
import de.letzgo.abstand.player.PlaybackController
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max

/**
 * iOS: `PlayerTranscriptionAudioContext` — Audioquelle des aktuellen Tracks. [assetFile] ist die
 * lokale Track-Datei (iOS: `assetURL`; Read Along läuft wie auf iOS nur mit vollständig
 * heruntergeladenen Titeln, `isReadAlongDownloadReady`).
 */
data class PlayerTranscriptionAudioContext(
    val assetFile: File,
    /** Globale Hörbuch-Zeit (s) am Anfang des Tracks. */
    val trackGlobalOffset: Double,
    /** Sprach-Tag der Transkription (BCP-47, iOS `locale.identifier(.bcp47)`). */
    val localeIdentifier: String,
    /** Position in der Track-Liste (iOS `currentTrackIndex`) — Schlüssel der Transkriptdateien. */
    val trackIndex: Int,
)

/**
 * iOS: Transkriptions-Teil von `PlaybackController` (`transcriptionTrackKey`, `transcriptionStorageId`,
 * `preferredTranscriptionLanguageTag`, `makeTranscriptionAudioContext`, `localTranscriptionTrackSources` …).
 * Als Erweiterung, damit der Player-Kern unberührt bleibt; Zugriff auf Tracks/Download-Ordner über
 * `transcriptionTimeline`/`transcriptionLocalRoot`. Nur auf dem Main-Thread aufrufen (wie der Player).
 */
object PlaybackTranscription {
    /**
     * iOS: `transcriptionLanguageOverride` (bei Podcast-Folgen die Sprache der Show). Schlüssel ist die
     * Item-ID; gilt nur, solange dieses Item aktiv ist.
     */
    private val languageOverrides = ConcurrentHashMap<String, String>()

    /** iOS: `setTranscriptionLanguageOverride` — `null`/leer entfernt den Override. */
    fun setTranscriptionLanguageOverride(libraryItemId: String, languageTag: String?) {
        val tag = languageTag?.swiftTrim().orEmpty()
        if (tag.isEmpty()) languageOverrides.remove(libraryItemId) else languageOverrides[libraryItemId] = tag
    }

    /**
     * iOS: `liveGlobalPlaybackPosition` — frisch vom Player, ohne `globalPosition` zu schreiben
     * (sonst triggert jeder Lesezugriff die Tick-Beobachter erneut).
     */
    fun livePosition(player: PlaybackController): Double = player.globalPositionMsForSession() / 1000.0

    /** Position des aktuell wiedergegebenen Tracks in der Track-Liste. */
    fun currentTrackIndex(player: PlaybackController): Int =
        player.transcriptionTimeline.trackIndex(livePosition(player))

    /** iOS: `transcriptionTrackKey` — `<bookId>-<trackIndex>`. */
    fun transcriptionTrackKey(player: PlaybackController): String =
        "${player.activeBook.value?.id ?: ""}-${currentTrackIndex(player)}"

    /**
     * iOS: `transcriptionStorageId` — wie der Download-Ordner: Hörbuch = Item-ID,
     * Podcast-Folge = `<Show-ID>-<Folgen-ID>` (`/` → `_`).
     */
    fun transcriptionStorageId(player: PlaybackController): String? {
        val book = player.activeBook.value ?: return null
        return storageId(book.id, player.activePlaybackEpisodeId.value)
    }

    fun storageId(libraryItemId: String, episodeId: String?): String {
        val ep = episodeId?.swiftTrim().orEmpty()
        val bookId = libraryItemId.swiftTrim()
        if (ep.isEmpty()) return bookId
        return "$bookId-$ep".replace("/", "_")
    }

    /** iOS: `preferredTranscriptionLanguageTag` — Override, sonst Buch-Metadaten. */
    fun preferredTranscriptionLanguageTag(player: PlaybackController): String? {
        val book = player.activeBook.value ?: return null
        return languageOverrides[book.id] ?: book.media.metadata.language
    }

    /** iOS: `isReadAlongDownloadReady` — nur bei vollständig heruntergeladenem Titel. */
    fun isReadAlongDownloadReady(player: PlaybackController): Boolean = player.isUsingLocalTrackFiles

    /** iOS: `currentTranscriptionTrackDuration`. */
    fun currentTranscriptionTrackDuration(player: PlaybackController): Double {
        val tracks = player.transcriptionTimeline.tracks
        val idx = currentTrackIndex(player)
        return tracks.getOrNull(idx)?.duration ?: 0.0
    }

    /** iOS: `transcriptionLocalPlaybackSeconds(trackGlobalOffset:)`. */
    fun localPlaybackSeconds(player: PlaybackController, trackGlobalOffset: Double): Double =
        max(0.0, PlaybackTranscription.livePosition(player) - trackGlobalOffset)

    /**
     * iOS: `makeTranscriptionAudioContext()` — lokale Datei des aktuellen Tracks. Den Stream-Zweig von
     * iOS gibt es nicht: iOS erlaubt Read Along ohnehin nur mit lokalen Dateien (`isReadAlongDownloadReady`).
     * [localeIdentifier] wird vom Aufrufer gesetzt (Platzhalter wie iOS `Locale.current`).
     */
    fun makeTranscriptionAudioContext(player: PlaybackController, localeIdentifier: String = ""): PlayerTranscriptionAudioContext? {
        if (player.activeBook.value == null) return null
        val timeline = player.transcriptionTimeline
        if (timeline.isEmpty) return null
        val idx = currentTrackIndex(player)
        if (idx !in timeline.trackStarts.indices) return null
        if (!player.isUsingLocalTrackFiles) return null
        val root = player.transcriptionLocalRoot ?: return null
        val manifest = AbsDownloadManifest.load(root)
        val file = PlaybackController.resolvedLocalTrackFile(root, timeline.tracks[idx].index, manifest) ?: return null
        return PlayerTranscriptionAudioContext(file, timeline.trackStarts[idx], localeIdentifier, idx)
    }

    /** iOS: `localTranscriptionTrackSources()` — alle lokalen Tracks des aktiven Downloads. */
    fun localTranscriptionTrackSources(player: PlaybackController): List<PlayerTranscriptTrackSource> {
        if (player.activeBook.value == null || !player.isUsingLocalTrackFiles) return emptyList()
        val root = player.transcriptionLocalRoot ?: return emptyList()
        val timeline = player.transcriptionTimeline
        if (timeline.tracks.size != timeline.trackStarts.size) return emptyList()
        val manifest = AbsDownloadManifest.load(root)
        return timeline.tracks.mapIndexedNotNull { index, track ->
            val file = PlaybackController.resolvedLocalTrackFile(root, track.index, manifest) ?: return@mapIndexedNotNull null
            PlayerTranscriptTrackSource(index, file.absolutePath, timeline.trackStarts[index], track.duration)
        }
    }
}
