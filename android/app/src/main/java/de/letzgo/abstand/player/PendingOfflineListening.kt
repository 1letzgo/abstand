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

    /**
     * iOS: `pendingOfflineListeningStorageKey()` = `progressGuardStorageKey(base:)` — je Server **und** Benutzer.
     * Ein globaler Key ging beim Account-Wechsel verloren bzw. wäre mit dem Client des nächsten Accounts gesendet worden.
     */
    fun storageKey(normalizedServerURL: String?, userId: String?): String {
        val base = Keys.pendingOfflineListeningSeconds
        val u = normalizedServerURL.orEmpty()
        if (u.isEmpty()) return base
        val uid = userId?.trim().orEmpty()
        return if (uid.isEmpty()) "$base.$u" else "$base.$u.$uid"
    }

    /**
     * Map des Scopes [storageKey]. [migrateLegacy]: einmalige Migration — der frühere globale Key gehört zum damals
     * aktiven Account; nur übernehmen, wenn der Scope vollständig (Server + User) feststeht.
     */
    @Synchronized
    fun load(storageKey: String, migrateLegacy: Boolean = false): Map<String, Int> {
        val legacy = Keys.pendingOfflineListeningSeconds
        var map = decode(Prefs.string(storageKey))
        if (migrateLegacy && storageKey != legacy && Prefs.string(legacy) != null) {
            for ((k, v) in decode(Prefs.string(legacy))) map = adding(map, k, v)
            save(map, storageKey)
            Prefs.remove(legacy)
        }
        return map
    }

    @Synchronized
    fun save(map: Map<String, Int>, storageKey: String) {
        if (map.isEmpty()) Prefs.remove(storageKey)
        else Prefs.commitString(storageKey, encode(map))
    }

    /** Mit vorab festgehaltenem Scope — Aufrufer, die zwischen Erfassen und Schreiben suspendieren. */
    @Synchronized
    fun add(progressKey: String, seconds: Int, storageKey: String) {
        if (seconds <= 0) return
        save(adding(load(storageKey), progressKey, seconds), storageKey)
    }

    /** Reset Progress: aufgelaufene Sekunden eines Keys verwerfen (iOS: `clearPendingOfflineListeningSeconds`). */
    @Synchronized
    fun remove(progressKey: String, storageKey: String) {
        val map = load(storageKey)
        if (progressKey in map) save(map - progressKey, storageKey)
    }

    /** Reine Map-Logik (Tests): nur das Gesendete abziehen — während des Flushs hinzugekommene Sekunden bleiben. */
    fun subtractingSent(latest: Map<String, Int>, sent: Map<String, Int>): Map<String, Int> {
        val out = latest.toMutableMap()
        for ((key, s) in sent) {
            val remaining = (out[key] ?: 0) - s
            if (remaining > 0) out[key] = remaining else out.remove(key)
        }
        return out
    }

    /** Re-Entrancy-Schutz (Netz-Callback + Offline-Sync parallel). Main-Thread. */
    private var isFlushing = false

    /**
     * Sendet gespeicherte Offline-Hörsekunden per kurzer Play-Session (start → sync → close). Single-Flight;
     * Scope ([storageKey]) vom Aufrufer vor dem ersten Suspend festgehalten, [isCurrent] bricht nach einem
     * Account-/Client-Wechsel ab. Keys ohne bekannten Fortschritt werden verworfen; bei Netzfehlern bricht die
     * Schleife ab und der Rest bleibt liegen. Zum Schluss nur das Gesendete von einer frisch geladenen Map abziehen.
     */
    suspend fun flush(
        client: AbsApiClient,
        storageKey: String,
        migrateLegacy: Boolean,
        isCurrent: () -> Boolean,
        progress: (String) -> AbsUserMediaProgress?,
    ) {
        if (isFlushing) return
        val snapshot = load(storageKey, migrateLegacy)
        if (snapshot.isEmpty()) return
        isFlushing = true
        try {
            val sent = HashMap<String, Int>()
            for ((key, seconds) in snapshot) {
                if (seconds <= 0) continue
                if (!isCurrent()) break
                val p = progress(key)
                if (p == null) {
                    sent[key] = seconds
                    continue
                }
                try {
                    val session = client.startPlaySession(p.libraryItemId, p.episodeId, PlaybackController.stableDeviceId(), PlaybackController.appVersion())
                    client.syncPlaySession(session.id, seconds, maxOf(0.0, p.currentTime))
                    runCatching { client.closePlaySession(session.id) }
                    sent[key] = seconds
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (PlaybackController.isTransientNetworkError(e)) break
                }
            }
            if (sent.isEmpty()) return
            synchronized(this) { save(subtractingSent(load(storageKey), sent), storageKey) }
        } finally {
            isFlushing = false
        }
    }
}
