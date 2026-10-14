package de.letzgo.abstand.store

import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.swiftTrim
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer

/**
 * iOS: `ActiveLibraryIdsStore` — persistierte Aktivierung von Server-Libraries pro Medientyp
 * (Primary bleibt separat). iOS speichert JSON-`Data`, Android denselben JSON-Text als String-Pref.
 */
object ActiveLibraryIdsStore {
    private val serializer = ListSerializer(String.serializer())

    /** Getrimmt, leere IDs verworfen; `null` nur bei Kodierfehler (iOS: `try?`). */
    fun encode(ids: List<String>): String? {
        val normalized = ids.map { it.swiftTrim() }.filter { it.isNotEmpty() }
        return runCatching { AbsJson.encoder.encodeToString(serializer, normalized) }.getOrNull()
    }

    fun decode(data: String?): List<String> {
        if (data.isNullOrEmpty()) return emptyList()
        val ids = runCatching { AbsJson.decoder.decodeFromString(serializer, data) }.getOrNull() ?: return emptyList()
        return ids.map { it.swiftTrim() }.filter { it.isNotEmpty() }
    }
}
