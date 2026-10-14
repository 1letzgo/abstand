package de.letzgo.abstand.player

import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer

/**
 * iOS: `AppModel.addPendingOfflineListeningSeconds` / `flushPendingOfflineListeningTime` — Hörzeit ohne
 * aktive Play-Session (lokale Dateien offline, vgl. Absorb `offline_listening_*`), als JSON-Map
 * `progressKey → Sekunden` unter [Keys.pendingOfflineListeningSeconds].
 */
object PendingOfflineListening {
    private val serializer = MapSerializer(String.serializer(), Int.serializer())

    /** Reine Map-Logik (Tests): Sekunden zu einem Key addieren. */
    fun adding(map: Map<String, Int>, progressKey: String, seconds: Int): Map<String, Int> {
        if (seconds <= 0) return map
        return map.toMutableMap().apply { this[progressKey] = (this[progressKey] ?: 0) + seconds }
    }

    fun encode(map: Map<String, Int>): String = AbsJson.encoder.encodeToString(serializer, map)

    fun decode(text: String?): Map<String, Int> =
        text?.let { runCatching { AbsJson.decoder.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()

    @Synchronized
    fun load(): Map<String, Int> = decode(Prefs.string(Keys.pendingOfflineListeningSeconds))

    @Synchronized
    fun save(map: Map<String, Int>) {
        if (map.isEmpty()) Prefs.remove(Keys.pendingOfflineListeningSeconds)
        else Prefs.commitString(Keys.pendingOfflineListeningSeconds, encode(map))
    }

    @Synchronized
    fun add(progressKey: String, seconds: Int) {
        if (seconds <= 0) return
        save(adding(load(), progressKey, seconds))
    }

    @Synchronized
    fun clear() = Prefs.remove(Keys.pendingOfflineListeningSeconds)

    /**
     * Sendet gespeicherte Offline-Hörsekunden per kurzer Play-Session (start → sync → close).
     * Keys ohne bekannten Fortschritt werden verworfen; bei Netzfehlern bricht die Schleife ab und der
     * Rest bleibt für den nächsten Versuch liegen.
     */
    suspend fun flush(client: AbsApiClient, progress: (String) -> AbsUserMediaProgress?) {
        val map = load().toMutableMap()
        if (map.isEmpty()) return
        val flushed = ArrayList<String>()
        for ((key, seconds) in map) {
            if (seconds <= 0) continue
            val p = progress(key)
            if (p == null) {
                flushed.add(key)
                continue
            }
            try {
                val session = client.startPlaySession(p.libraryItemId, p.episodeId, PlaybackController.stableDeviceId(), PlaybackController.appVersion())
                client.syncPlaySession(session.id, seconds, maxOf(0.0, p.currentTime))
                runCatching { client.closePlaySession(session.id) }
                flushed.add(key)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (PlaybackController.isTransientNetworkError(e)) break
            }
        }
        // Erneut laden: während des Flushs hinzugekommene Sekunden nicht verlieren.
        val latest = load().toMutableMap()
        for (key in flushed) {
            val sent = map[key] ?: 0
            val now = latest[key] ?: continue
            if (now <= sent) latest.remove(key) else latest[key] = now - sent
        }
        save(latest)
    }
}
