package de.letzgo.abstand.transcript

import de.letzgo.abstand.logic.EbookReadAlongIndex
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import java.util.concurrent.ConcurrentHashMap

/**
 * iOS: `TeleprompterEbookTextProvider` — eBook-Index für den Teleprompter: ist dem Hörbuch ein
 * (bereits geladenes) EPUB angehängt, zeigt der Teleprompter dessen Sätze statt des Erkennungstexts;
 * die Spracherkennung bleibt nur Zeitgeber (Abgleich: `logic/EbookAudioAlignment.kt`).
 *
 * Das Öffnen des EPUB (Readium) gehört zum Reader-Port: er setzt [indexLoader] — nur lokale Dateien,
 * kein Download. Ohne Loader zeigt der Teleprompter den Erkennungstext.
 */
object TeleprompterEbookTextProvider {
    /** Baut den Index für eine Library-Item-ID aus dem lokal vorhandenen EPUB; `null` = kein eBook. */
    @Volatile
    var indexLoader: (suspend (libraryItemId: String) -> EbookReadAlongIndex?)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val cache = ConcurrentHashMap<String, Deferred<EbookReadAlongIndex?>>()

    suspend fun index(libraryItemId: String): EbookReadAlongIndex? {
        val loader = indexLoader ?: return null
        val task = cache.getOrPut(libraryItemId) {
            scope.async { runCatching { loader(libraryItemId) }.getOrNull()?.takeIf { !it.isEmpty } }
        }
        val result = task.await()
        // Fehlschlag nicht merken — sonst bleibt der eBook-Text bis zum App-Neustart aus.
        if (result == null) cache.remove(libraryItemId, task)
        return result
    }

    /** eBook gelöscht/ersetzt: Index neu bauen lassen. */
    fun invalidate(libraryItemId: String? = null) {
        if (libraryItemId == null) cache.clear() else cache.remove(libraryItemId)
    }
}
