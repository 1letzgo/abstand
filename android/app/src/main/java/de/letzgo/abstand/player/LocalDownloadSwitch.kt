package de.letzgo.abstand.player

import de.letzgo.abstand.data.swiftTrim
import kotlin.math.max

/**
 * iOS: Entscheidung aus `AppModel.applyLocalPlaybackIfDownloadMatchesCurrent(storageId:)` — nach
 * abgeschlossenem Download auf lokale Dateien umschalten, wenn noch derselbe Titel aus dem Stream läuft.
 *
 * Umgeschaltet wird per `playBook` mit dem Manifest-Ordner an derselben globalen Position (Stream- und
 * Download-Timeline sind dieselbe Buchzeit) und mit dem bisherigen Play/Pause-Zustand. Die alte
 * Stream-Session wird dabei synchronisiert und geschlossen, die lokale Wiedergabe öffnet (online) eine
 * neue — wie iOS. Tempo ist global gespeichert; den Sleep-Timer rettet der Aufrufer über
 * [SleepTimer.snapshot]/[SleepTimer.restore].
 */
object LocalDownloadSwitch {
    data class Plan(
        /** Globale Buchposition (Sekunden), an der die lokale Wiedergabe weiterläuft. */
        val resumeAt: Double,
        /** Lief der Stream, läuft auch die lokale Wiedergabe sofort weiter. */
        val autoPlay: Boolean,
        /** Folgen-ID aus dem Manifest (`null` für Hörbücher). */
        val episodeId: String?,
    )

    /**
     * `null` = nicht umschalten: läuft schon lokal, anderer Titel/andere Folge oder Download unvollständig.
     * [allTracksPresent] wird erst nach den billigen Prüfungen ausgewertet (Dateisystem).
     */
    fun plan(
        activeItemId: String?,
        activeEpisodeId: String?,
        isPlaybackFromOfflineDownload: Boolean,
        manifestItemId: String,
        manifestEpisodeId: String?,
        globalPosition: Double,
        isPlaying: Boolean,
        allTracksPresent: () -> Boolean,
    ): Plan? {
        if (isPlaybackFromOfflineDownload) return null
        if (activeItemId == null || activeItemId != manifestItemId) return null
        val curEp = activeEpisodeId?.swiftTrim().orEmpty()
        val manEp = manifestEpisodeId?.swiftTrim().orEmpty()
        if (curEp != manEp) return null
        if (!allTracksPresent()) return null
        return Plan(resumeAt = max(0.0, globalPosition), autoPlay = isPlaying, episodeId = manEp.ifEmpty { null })
    }
}
