package de.letzgo.abstand.data

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

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
     * iOS: `ABSJSON.decoderListeningStats()` — `JSONDecoder` mit `.convertFromSnakeCase`.
     * Swift wandelt dabei **jeden** Objekt-Key (auch Dictionary-Keys) von `snake_case` nach camelCase,
     * camelCase-Keys bleiben unverändert. kotlinx' `JsonNamingStrategy.SnakeCase` macht das Gegenteil
     * (erwartet ausschließlich snake_case) — deshalb werden die Keys hier vorab umgeschrieben und
     * danach mit [decoder] dekodiert.
     */
    object decoderListeningStats {
        fun <T> decodeFromString(deserializer: DeserializationStrategy<T>, string: String): T =
            decoder.decodeFromJsonElement(deserializer, SwiftJson.convertKeysFromSnakeCase(decoder.parseToJsonElement(string)))

        fun <T> decodeFromJsonElement(deserializer: DeserializationStrategy<T>, element: JsonElement): T =
            decoder.decodeFromJsonElement(deserializer, SwiftJson.convertKeysFromSnakeCase(element))
    }
}
