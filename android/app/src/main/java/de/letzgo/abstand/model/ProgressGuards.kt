package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.store.ActiveLibraryIdsStore

/**
 * iOS: `pendingLocalProgressSyncKeys` + `localFinishedProgressKeys` in `AppModel` — lokale
 * Fortschritts-Schreibungen, die noch nicht am Server sind, und lokal gesetztes „Fertig“.
 * Persistiert je Server + Benutzer (iOS: `progressGuardStorageKey(base:)` = `<base>.<server>.<userId>`),
 * als JSON-String-Liste (iOS: `[String]` in UserDefaults).
 */
class ProgressGuards(private val session: SessionStore) {
    private var pending = LinkedHashSet<String>()
    private var localFinished = LinkedHashSet<String>()

    /** iOS: `progressGuardStorageKey(base:)`. */
    private fun storageKey(base: String): String {
        val u = AbsApiClient.normalizeServerURL(session.serverURL.value)?.ifEmpty { null } ?: return base
        val uid = session.resolvedLocalStoreUserId()?.swiftTrim().orEmpty()
        return if (uid.isEmpty()) "$base.$u" else "$base.$u.$uid"
    }

    /** Beim Aktivieren eines Accounts (iOS: `loadProgressGuardsForActiveAccount`). */
    fun load() {
        pending = LinkedHashSet(ActiveLibraryIdsStore.decode(Prefs.string(storageKey(Keys.pendingLocalProgressSyncKeys))))
        localFinished = LinkedHashSet(ActiveLibraryIdsStore.decode(Prefs.string(storageKey(Keys.localFinishedProgressKeys))))
    }

    /** Nur Speicher leeren (Accountwechsel) — persistierte Keys bleiben. */
    fun clearInMemory() {
        pending = LinkedHashSet()
        localFinished = LinkedHashSet()
    }

    val pendingKeys: Set<String> get() = pending.toSet()

    fun addPending(key: String) {
        val k = key.swiftTrim()
        if (k.isEmpty() || !pending.add(k)) return
        persist(Keys.pendingLocalProgressSyncKeys, pending)
    }

    fun removePending(key: String) {
        if (!pending.remove(key.swiftTrim())) return
        persist(Keys.pendingLocalProgressSyncKeys, pending)
    }

    fun isLocallyFinished(key: String): Boolean = key.swiftTrim() in localFinished

    fun markLocallyFinished(key: String) {
        val k = key.swiftTrim()
        if (k.isEmpty() || !localFinished.add(k)) return
        persist(Keys.localFinishedProgressKeys, localFinished)
    }

    fun clearLocallyFinished(key: String) {
        if (!localFinished.remove(key.swiftTrim())) return
        persist(Keys.localFinishedProgressKeys, localFinished)
    }

    private fun persist(base: String, set: Set<String>) {
        val key = storageKey(base)
        if (set.isEmpty()) Prefs.remove(key) else ActiveLibraryIdsStore.encode(set.toList())?.let { Prefs.setString(key, it) }
    }
}
