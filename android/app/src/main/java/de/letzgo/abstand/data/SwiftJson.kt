package de.letzgo.abstand.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject

/**
 * Swift-`Decodable`-Semantik auf kotlinx-`JsonElement` (iOS: `KeyedDecodingContainer` /
 * `JSONSerialization`). Die handgeschriebenen `init(from:)` der Swift-Modelle unterscheiden
 * präzise zwischen
 * - `decode(T.self)` — Pflicht: fehlt/null/falscher Typ → Fehler ([JObj.string] usw.),
 * - `decodeIfPresent(T.self)` — fehlt/null → `nil`, falscher Typ → Fehler ([JObj.stringOrNull]),
 * - `try? decode(T.self)` — jeder Fehler → `nil` ([JObj.tryString]).
 * Genau diese Unterscheidung bestimmt, ob ein kaputtes Feld ein ganzes Objekt (oder eine ganze
 * Liste) verwirft — deshalb wird sie hier 1:1 nachgebaut statt kotlinx-Defaults zu nutzen.
 */
object SwiftJson {
    /** iOS: `String` aus JSON — nur echte Strings. */
    fun string(e: JsonElement?): String? = (e as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun numericContent(e: JsonElement?): String? {
        val p = e as? JsonPrimitive ?: return null
        if (p.isString || p is JsonNull) return null
        val c = p.content
        if (c == "true" || c == "false") return null
        return c
    }

    /** iOS: `Int`/`Int64` aus JSON — Zahl ohne Nachkommaanteil (`3.0` geht, `3.5` nicht). */
    fun long(e: JsonElement?): Long? {
        val c = numericContent(e) ?: return null
        c.toLongOrNull()?.let { return it }
        val d = c.toDoubleOrNull() ?: return null
        if (d.isNaN() || d.isInfinite() || d != Math.floor(d)) return null
        if (d > Long.MAX_VALUE.toDouble() || d < Long.MIN_VALUE.toDouble()) return null
        return d.toLong()
    }

    fun int(e: JsonElement?): Int? = long(e)?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()

    /** iOS: `Double` aus JSON — jede Zahl. */
    fun double(e: JsonElement?): Double? = numericContent(e)?.toDoubleOrNull()

    /** iOS: `Bool` aus JSON — nur `true`/`false` (keine 0/1). */
    fun bool(e: JsonElement?): Boolean? {
        val p = e as? JsonPrimitive ?: return null
        if (p.isString) return null
        return when (p.content) { "true" -> true; "false" -> false; else -> null }
    }

    fun isNull(e: JsonElement?): Boolean = e == null || e is JsonNull

    // --- `JSONSerialization` + `as?`-Bridging (NSNumber) ---

    /** iOS: `value as? String`. */
    fun anyString(e: JsonElement?): String? = string(e)

    /** iOS: `value as? Int` auf NSNumber — ganzzahlige Zahl oder Bool (CFBoolean → 0/1). */
    fun anyInt(e: JsonElement?): Long? {
        long(e)?.let { return it }
        return bool(e)?.let { if (it) 1L else 0L }
    }

    /** iOS: `value as? Double` auf NSNumber — jede Zahl, auch Bool. */
    fun anyDouble(e: JsonElement?): Double? {
        double(e)?.let { return it }
        return bool(e)?.let { if (it) 1.0 else 0.0 }
    }

    /** iOS: `value as? Bool` auf NSNumber — `true`/`false` oder exakt 0/1. */
    fun anyBool(e: JsonElement?): Boolean? {
        bool(e)?.let { return it }
        return when (long(e)) { 1L -> true; 0L -> false; else -> null }
    }

    /** iOS: `value as? [String: Any]`. */
    fun anyObj(e: JsonElement?): JsonObject? = e as? JsonObject

    /** iOS: `value as? [[String: Any]]` — scheitert, sobald ein Element kein Objekt ist. */
    fun anyObjList(e: JsonElement?): List<JsonObject>? {
        val arr = e as? JsonArray ?: return null
        return arr.map { it as? JsonObject ?: return null }
    }

    /** iOS: `value as? [String]` — scheitert, sobald ein Element kein String ist. */
    fun anyStringList(e: JsonElement?): List<String>? {
        val arr = e as? JsonArray ?: return null
        return arr.map { string(it) ?: return null }
    }

    /** iOS: `(value as? [Any])?.compactMap { $0 as? [String: Any] }`. */
    fun anyObjsCompact(e: JsonElement?): List<JsonObject>? = (e as? JsonArray)?.mapNotNull { it as? JsonObject }

    /**
     * iOS: `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` — wirkt auf **alle** Objekt-Keys,
     * auch auf Dictionary-Keys (`[String: T]`). Erste Komponente bleibt unverändert, weitere werden
     * `capitalized`; führende/abschließende Unterstriche bleiben; Keys ohne `_` bleiben unverändert.
     */
    fun convertFromSnakeCase(key: String): String {
        if (key.isEmpty()) return key
        val first = key.indexOfFirst { it != '_' }
        if (first < 0) return key
        val last = key.indexOfLast { it != '_' }
        val core = key.substring(first, last + 1)
        if (!core.contains('_')) return key
        val parts = core.split('_')
        val sb = StringBuilder(key.substring(0, first))
        sb.append(parts[0])
        for (p in parts.drop(1)) {
            if (p.isEmpty()) continue
            sb.append(p.substring(0, 1).uppercase()).append(p.substring(1).lowercase())
        }
        sb.append(key.substring(last + 1))
        return sb.toString()
    }

    /** Wendet [convertFromSnakeCase] rekursiv auf ein JSON-Dokument an. */
    fun convertKeysFromSnakeCase(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.entries.associate { (k, v) -> convertFromSnakeCase(k) to convertKeysFromSnakeCase(v) })
        is JsonArray -> JsonArray(e.map { convertKeysFromSnakeCase(it) })
        else -> e
    }

    fun mismatch(key: String, what: String): Nothing = throw SerializationException("Key '$key': expected $what")
}

/** Element-Decoder für Listen (iOS: `[T].self`). Wirft bei falschem Typ. */
fun interface ElementDecoder<T> {
    fun decode(e: JsonElement): T

    companion object {
        val string = ElementDecoder { SwiftJson.string(it) ?: throw SerializationException("expected String") }
        val int = ElementDecoder { SwiftJson.int(it) ?: throw SerializationException("expected Int") }
        val double = ElementDecoder { SwiftJson.double(it) ?: throw SerializationException("expected Double") }
        fun <T> of(serializer: KSerializer<T>) = ElementDecoder { AbsJson.decoder.decodeFromJsonElement(serializer, it) }
    }
}

/** iOS: `KeyedDecodingContainer` über einem JSON-Objekt. */
class JObj(val o: JsonObject) {
    /** iOS: `container.contains(key)` — auch bei explizitem `null` `true`. */
    fun contains(key: String) = o.containsKey(key)
    operator fun get(key: String): JsonElement? = o[key]

    private fun present(key: String): JsonElement? = o[key]?.takeUnless { it is JsonNull }

    // Pflicht (`decode`)
    fun string(key: String): String = SwiftJson.string(o[key]) ?: SwiftJson.mismatch(key, "String")
    fun int(key: String): Int = SwiftJson.int(o[key]) ?: SwiftJson.mismatch(key, "Int")
    fun long(key: String): Long = SwiftJson.long(o[key]) ?: SwiftJson.mismatch(key, "Int64")
    fun double(key: String): Double = SwiftJson.double(o[key]) ?: SwiftJson.mismatch(key, "Double")
    fun bool(key: String): Boolean = SwiftJson.bool(o[key]) ?: SwiftJson.mismatch(key, "Bool")

    // `decodeIfPresent`
    fun stringOrNull(key: String): String? = present(key)?.let { SwiftJson.string(it) ?: SwiftJson.mismatch(key, "String") }
    fun intOrNull(key: String): Int? = present(key)?.let { SwiftJson.int(it) ?: SwiftJson.mismatch(key, "Int") }
    fun longOrNull(key: String): Long? = present(key)?.let { SwiftJson.long(it) ?: SwiftJson.mismatch(key, "Int64") }
    fun doubleOrNull(key: String): Double? = present(key)?.let { SwiftJson.double(it) ?: SwiftJson.mismatch(key, "Double") }
    fun boolOrNull(key: String): Boolean? = present(key)?.let { SwiftJson.bool(it) ?: SwiftJson.mismatch(key, "Bool") }

    // `try? decode`
    fun tryString(key: String): String? = SwiftJson.string(o[key])
    fun tryInt(key: String): Int? = SwiftJson.int(o[key])
    fun tryLong(key: String): Long? = SwiftJson.long(o[key])
    fun tryDouble(key: String): Double? = SwiftJson.double(o[key])
    fun tryBool(key: String): Boolean? = SwiftJson.bool(o[key])

    // Objekte
    fun <T> obj(key: String, dec: ElementDecoder<T>): T {
        val e = present(key) ?: SwiftJson.mismatch(key, "object")
        return dec.decode(e)
    }
    fun <T> objOrNull(key: String, dec: ElementDecoder<T>): T? = present(key)?.let { dec.decode(it) }
    fun <T> tryObj(key: String, dec: ElementDecoder<T>): T? = present(key)?.let { runCatching { dec.decode(it) }.getOrNull() }

    /** Verschachtelter Container (iOS: `nestedContainer(keyedBy:forKey:)`). */
    fun nested(key: String): JObj = JObj(o[key] as? JsonObject ?: SwiftJson.mismatch(key, "object"))
    fun tryNested(key: String): JObj? = (o[key] as? JsonObject)?.let { JObj(it) }

    // Listen
    fun <T> list(key: String, dec: ElementDecoder<T>): List<T> {
        val arr = o[key] as? JsonArray ?: SwiftJson.mismatch(key, "array")
        return arr.map { dec.decode(it) }
    }
    fun <T> listOrNull(key: String, dec: ElementDecoder<T>): List<T>? {
        val e = present(key) ?: return null
        val arr = e as? JsonArray ?: SwiftJson.mismatch(key, "array")
        return arr.map { dec.decode(it) }
    }
    fun <T> tryList(key: String, dec: ElementDecoder<T>): List<T>? = runCatching { list(key, dec) }.getOrNull()
}

/**
 * Basis für Modelle mit handgeschriebenem Swift-`init(from:)`/`encode(to:)`.
 * Nur mit [AbsJson]-Instanzen nutzbar (JSON-Decoder/-Encoder).
 */
abstract class SwiftObjectSerializer<T>(serialName: String) : KSerializer<T>, ElementDecoder<T> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor(serialName)

    abstract fun decode(c: JObj): T

    /** iOS: `encode(to:)`. Standard: nicht kodierbar (Swift-Typ ist nur `Decodable`). */
    open fun encode(v: T): JsonElement = throw SerializationException("$this is decode-only (Swift: Decodable)")

    override fun decode(e: JsonElement): T = decode(JObj(e as? JsonObject ?: throw SerializationException("expected object")))

    override fun deserialize(decoder: Decoder): T {
        val jd = decoder as? JsonDecoder ?: throw SerializationException("JSON only")
        return decode(jd.decodeJsonElement())
    }

    override fun serialize(encoder: Encoder, value: T) {
        val je = encoder as? JsonEncoder ?: throw SerializationException("JSON only")
        je.encodeJsonElement(encode(value))
    }
}

// --- Encoder-Helfer (iOS: `encode` / `encodeIfPresent`) ---

fun JsonObjectBuilder.putIfPresent(key: String, value: String?) { if (value != null) put(key, JsonPrimitive(value)) }
fun JsonObjectBuilder.putIfPresent(key: String, value: Number?) { if (value != null) put(key, JsonPrimitive(value)) }
fun JsonObjectBuilder.putIfPresent(key: String, value: Boolean?) { if (value != null) put(key, JsonPrimitive(value)) }
fun JsonObjectBuilder.putIfPresent(key: String, value: JsonElement?) { if (value != null) put(key, value) }
fun JsonObjectBuilder.putStrings(key: String, value: List<String>?) {
    if (value != null) put(key, buildJsonArray { value.forEach { add(JsonPrimitive(it)) } })
}
fun <T> JsonObjectBuilder.putList(key: String, value: List<T>?, enc: (T) -> JsonElement) {
    if (value != null) put(key, JsonArray(value.map(enc)))
}

fun <T> KSerializer<T>.toJson(value: T): JsonElement = AbsJson.encoder.encodeToJsonElement(this, value)

/** iOS: `trimmingCharacters(in: .whitespacesAndNewlines)`. */
internal fun String.swiftTrim(): String = trim { it.isWhitespace() || it == ' ' || it == '\u0085' }

internal fun String?.trimmedOrEmpty(): String = this?.swiftTrim() ?: ""

/** iOS: `nilIfEmpty`. */
internal fun String.nilIfEmpty(): String? = ifEmpty { null }

internal fun jsonObjectOf(builder: JsonObjectBuilder.() -> Unit): JsonObject = buildJsonObject(builder)
