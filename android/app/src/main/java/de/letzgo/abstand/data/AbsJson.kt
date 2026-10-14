package de.letzgo.abstand.data

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNamingStrategy

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

    /** iOS: `ABSJSON.decoderListeningStats()` — Hördaten-Endpunkt liefert teils `snake_case`. */
    @OptIn(ExperimentalSerializationApi::class)
    val decoderListeningStats: Json = Json(decoder) {
        namingStrategy = JsonNamingStrategy.SnakeCase
    }
}
