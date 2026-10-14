package de.letzgo.abstand.data

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * iOS: `ABSJSON`. Nie eigene `Json { }`-Instanzen bauen — falscher Decoder = still falsche Werte.
 * Datumswerte der API sind Millisekunden seit 1970 und werden in den Modellen als `Long` geführt
 * (iOS dekodiert sie zu `Date`; die Zahl ist dieselbe).
 */
object AbsJson {
    /** iOS: `ABSJSON.decoder()` — tolerant wie die Swift-Decoder (unbekannte Keys ignoriert). */
    val decoder: Json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        explicitNulls = false
        isLenient = true
    }

    /** iOS: `ABSJSON.encoder()`. */
    val encoder: Json = Json {
        explicitNulls = false
        encodeDefaults = true
    }

    /**
     * iOS: `ABSJSON.decoderListeningStats()` — snake_case → camelCase wie `.convertFromSnakeCase`.
     * Ausnahmen wie iOS: die Keys der Top-Level-Maps `items` (Library-Item-IDs wie `li_x_1`),
     * `days` und `dayOfWeek` bleiben unverändert (Swift-`[String: T]` konvertiert keine Keys;
     * `items` bewahrt iOS über eine eigene Key-Strategie). Die Keys werden vorab umgeschrieben
     * und danach mit [decoder] dekodiert.
     */
    object decoderListeningStats {
        fun <T> decodeFromString(deserializer: DeserializationStrategy<T>, string: String): T =
            decoder.decodeFromJsonElement(deserializer, convertStatsKeys(decoder.parseToJsonElement(string)))

        fun <T> decodeFromJsonElement(deserializer: DeserializationStrategy<T>, element: JsonElement): T =
            decoder.decodeFromJsonElement(deserializer, convertStatsKeys(element))

        private val mapKeys = setOf("items", "days", "dayOfWeek")

        private fun convertStatsKeys(e: JsonElement): JsonElement {
            val root = e as? JsonObject ?: return SwiftJson.convertKeysFromSnakeCase(e)
            return JsonObject(
                root.entries.associate { (k, v) ->
                    val key = SwiftJson.convertFromSnakeCase(k)
                    val value = if (key in mapKeys && v is JsonObject) {
                        JsonObject(v.entries.associate { (id, item) -> id to SwiftJson.convertKeysFromSnakeCase(item) })
                    } else {
                        SwiftJson.convertKeysFromSnakeCase(v)
                    }
                    key to value
                },
            )
        }
    }
}
