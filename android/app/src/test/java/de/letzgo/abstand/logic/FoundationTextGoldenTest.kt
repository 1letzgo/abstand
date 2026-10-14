package de.letzgo.abstand.logic

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Parität der Text-Normalisierung mit Foundation: Tabellen und Tokenisierung wurden mit Swift auf
 * macOS erzeugt (`shared/fixtures/alignment/unicode_tables.json`, `tokenization.json`).
 */
class FoundationTextGoldenTest {
    private fun fixture(name: String): JsonObject =
        Json.parseToJsonElement(javaClass.classLoader!!.getResource("alignment/$name")!!.readText()).jsonObject

    private fun hexScalars(s: String): String = s.codePoints().toArray().joinToString(" ") { Integer.toHexString(it) }

    private fun fromHex(hex: String): String =
        if (hex.isEmpty()) "" else hex.split(" ").joinToString("") { String(Character.toChars(it.toInt(16))) }

    /**
     * Jeder Skalar, den sowohl das JDK als auch macOS kennen: Wortzeichen-Eigenschaft und `normalize`
     * müssen übereinstimmen. Unterschiede der Unicode-Versionen (JDK 17 = Unicode 13) sind erlaubt,
     * solange sie selten bleiben; alle Lateinisch/Griechisch/Kyrillisch-Skalare müssen exakt passen.
     */
    @Test
    fun singleScalarsMatchFoundation() {
        val t = fixture("unicode_tables.json")
        fun ranges(key: String) = t[key]!!.jsonArray.map { val r = it.jsonArray; r[0].jsonPrimitive.int..r[1].jsonPrimitive.int }
        val word = ranges("wordRanges")
        val removed = ranges("removedRanges")
        val mapped = t["mapped"]!!.jsonObject.mapKeys { it.key.toInt(16) }.mapValues { it.value.jsonPrimitive.content }
        fun inRanges(r: List<IntRange>, cp: Int): Boolean {
            var lo = 0; var hi = r.size - 1
            while (lo <= hi) {
                val mid = (lo + hi) / 2
                if (cp < r[mid].first) hi = mid - 1 else if (cp > r[mid].last) lo = mid + 1 else return true
            }
            return false
        }
        val wordMismatches = ArrayList<String>()
        val normMismatches = ArrayList<String>()
        var checked = 0
        for (cp in (0..0x3FFFF) + (0xE0000..0xE01EF)) {
            if (cp in 0xD800..0xDFFF || !Character.isDefined(cp)) continue
            // Skalare, die macOS (noch) nicht kennt, tauchen in keiner Tabelle auf.
            val known = inRanges(word, cp) || inRanges(removed, cp) || mapped.containsKey(cp) ||
                FoundationText.isAlphanumeric(cp)
            if (!known) continue
            checked++
            if (FoundationText.isWordScalar(cp) != inRanges(word, cp)) wordMismatches.add(Integer.toHexString(cp))
            val expected = when {
                inRanges(removed, cp) -> ""
                mapped.containsKey(cp) -> fromHex(mapped.getValue(cp))
                else -> String(Character.toChars(cp))
            }
            val actual = ReadAlongText.normalize(String(Character.toChars(cp)))
            if (actual != expected) normMismatches.add("${Integer.toHexString(cp)}:${hexScalars(actual)}≠${hexScalars(expected)}")
        }
        println("checked $checked scalars; word mismatches ${wordMismatches.size}: ${wordMismatches.take(60)}")
        println("normalize mismatches ${normMismatches.size}: ${normMismatches.take(60)}")
        println("normalize mismatch blocks: " + normMismatches.map { it.substringBefore(':').toInt(16) }
            .groupBy { Character.UnicodeBlock.of(it)?.toString() ?: "?" }.mapValues { it.value.size })
        val coreScripts = { s: String -> s.substringBefore(':').toInt(16) < 0x0530 || s.substringBefore(':').toInt(16) in 0x1E00..0x1FFF }
        assertEquals("Lateinisch/Griechisch/Kyrillisch", emptyList<String>(), normMismatches.filter(coreScripts))
        assertEquals("Wortzeichen Lateinisch/Griechisch/Kyrillisch", emptyList<String>(), wordMismatches.filter(coreScripts))
        assertTrue("normalize mismatches ${normMismatches.size}", normMismatches.size <= MAX_VERSION_MISMATCHES)
        assertTrue("word mismatches ${wordMismatches.size}", wordMismatches.size <= MAX_VERSION_MISMATCHES)
    }

    @Test
    fun tokenizationCasesMatchSwift() {
        val t = fixture("tokenization.json")
        for (c in t["cases"]!!.jsonArray) {
            val o = c.jsonObject
            val text = o["text"]!!.jsonPrimitive.content
            assertEquals(text, o["normalized"]!!.jsonPrimitive.content, ReadAlongText.normalize(text))
            assertEquals(text, o["count"]!!.jsonPrimitive.int, FoundationText.characterCount(text))
            val expected = o["tokens"]!!.jsonArray.map {
                val tok = it.jsonObject
                ReadAlongToken(tok["word"]!!.jsonPrimitive.content, tok["start"]!!.jsonPrimitive.int, tok["end"]!!.jsonPrimitive.int)
            }
            assertEquals(text, expected, ReadAlongText.words(text))
        }
    }

    @Test
    fun randomStringsMatchSwift() {
        val t = fixture("tokenization.json")
        val mismatches = ArrayList<String>()
        val random = t["random"]!!.jsonArray
        for (c in random) {
            val o = c.jsonObject
            val s = fromHex(o["s"]!!.jsonPrimitive.content)
            val n = fromHex(o["n"]!!.jsonPrimitive.content)
            val words = (o["w"] as JsonArray).map {
                val a = it.jsonArray
                ReadAlongToken(a[0].jsonPrimitive.content, a[1].jsonPrimitive.int, a[2].jsonPrimitive.int)
            }
            val ok = ReadAlongText.normalize(s) == n && ReadAlongText.words(s) == words &&
                FoundationText.characterCount(s) == o["c"]!!.jsonPrimitive.int
            if (!ok) mismatches.add(
                "${o["s"]!!.jsonPrimitive.content} → n=${hexScalars(ReadAlongText.normalize(s))} (swift ${o["n"]!!.jsonPrimitive.content}) " +
                    "c=${FoundationText.characterCount(s)} (swift ${o["c"]}) w=${ReadAlongText.words(s)} (swift $words)",
            )
        }
        println("random mismatches ${mismatches.size}/${random.size}")
        mismatches.take(40).forEach(::println)
        assertTrue("random mismatches ${mismatches.size}", mismatches.size <= random.size / 200)
    }

    private companion object {
        /** Toleranz für Skalare, deren Eigenschaften sich zwischen Unicode 13 (JDK 17) und macOS unterscheiden. */
        const val MAX_VERSION_MISMATCHES = 40
    }
}
