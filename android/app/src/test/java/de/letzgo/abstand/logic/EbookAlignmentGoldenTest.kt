package de.letzgo.abstand.logic

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

/**
 * Abgleich-Goldens (`shared/fixtures/alignment/<fall>.json`), erzeugt mit dem unveränderten iOS-Code:
 * Index (Wörter, Anzeige-Text, Satz-Kontext), Abgleich byte-genau (`a<track>-<locale>.bin`),
 * Zeit-Abfragen, Teleprompter-Anzeigewörter und Sprung-Markierungen.
 */
class EbookAlignmentGoldenTest {
    private val cases = listOf("clean_chapter", "ocr_noise", "repeated_refrain", "missing_passage", "too_few_matches", "german_unicode")

    private fun fixture(name: String): JsonObject =
        Json.parseToJsonElement(javaClass.classLoader!!.getResource("alignment/$name.json")!!.readText()).jsonObject

    private fun str(e: kotlinx.serialization.json.JsonElement?): String? = if (e == null || e is JsonNull) null else e.jsonPrimitive.content

    private data class Case(val json: JsonObject, val index: EbookReadAlongIndex, val words: List<AlignmentInputWord>, val globalOffset: Double)

    private fun load(name: String): Case {
        val json = fixture(name)
        val input = json["input"]!!.jsonObject
        val builder = EbookReadAlongIndex.Builder()
        for (seg in input["segments"]!!.jsonArray) {
            val o = seg.jsonObject
            val ranges = o["sentenceRanges"]!!.jsonArray.map { val r = it.jsonArray; r[0].jsonPrimitive.int until r[1].jsonPrimitive.int }
            builder.addSegment(o["text"]!!.jsonPrimitive.content, ranges)
        }
        val words = input["transcript"]!!.jsonArray.map {
            val w = it.jsonObject
            AlignmentInputWord(w["t"]!!.jsonPrimitive.content, w["s"]!!.jsonPrimitive.double, w["e"]!!.jsonPrimitive.double)
        }
        return Case(json, builder.build(), words, input["globalOffset"]!!.jsonPrimitive.double)
    }

    @Test
    fun indexMatchesSwift() {
        for (name in cases) {
            val c = load(name)
            val expected = c.json["expected"]!!.jsonObject["index"]!!.jsonObject
            val words = expected["words"]!!.jsonArray
            assertEquals(name, words.size, c.index.words.size)
            for ((i, w) in words.withIndex()) {
                val o = w.jsonObject
                val actual = c.index.words[i]
                assertEquals("$name word $i", o["n"]!!.jsonPrimitive.content, actual.normalized)
                assertEquals("$name word $i", o["s"]!!.jsonPrimitive.int, actual.sentence)
                assertEquals("$name word $i", o["d"]!!.jsonPrimitive.content, actual.display)
            }
            val sentences = expected["sentences"]!!.jsonArray
            assertEquals(name, sentences.size, c.index.sentences.size)
            for ((i, s) in sentences.withIndex()) {
                val o = s.jsonObject
                val actual = c.index.sentences[i]
                assertEquals(o["segment"]!!.jsonPrimitive.int, actual.segment)
                assertEquals("$name sentence $i", LocatorTextContext(str(o["before"]), str(o["highlight"]), str(o["after"])), actual.text)
            }
            assertEquals(name, expected["vocabularySize"]!!.jsonPrimitive.int, c.index.vocabulary.size)
        }
    }

    @Test
    fun alignmentIsByteIdenticalToSwift() {
        for (name in cases) {
            val c = load(name)
            val expected = c.json["expected"]!!.jsonObject["alignment"]!!.jsonObject
            val alignment = EbookAlignmentBuilder.build(c.words, c.index)
            assertEquals(name, expected["words"]!!.jsonArray.map { it.jsonPrimitive.int }, alignment.words.toList())
            assertEquals(name, expected["flags"]!!.jsonArray.map { it.jsonPrimitive.int }, alignment.flags.map { it.toInt() })
            assertEquals(name, expected["starts"]!!.jsonArray.map { it.jsonPrimitive.double.toFloat() }, alignment.starts.toList())
            assertEquals(name, expected["ends"]!!.jsonArray.map { it.jsonPrimitive.double.toFloat() }, alignment.ends.toList())
            val bin = Base64.getDecoder().decode(expected["binBase64"]!!.jsonPrimitive.content)
            assertArrayEquals(name, bin, alignment.encoded())

            // Swift-Datei lesen → identisch zurückschreiben.
            val decoded = EbookTrackAlignment.decode(bin)!!
            assertEquals(expected["ebookWordCount"]!!.jsonPrimitive.int, decoded.ebookWordCount)
            assertEquals(expected["spokenWordCount"]!!.jsonPrimitive.int, decoded.spokenWordCount)
            assertEquals(expected["spokenEnd"]!!.jsonPrimitive.double, decoded.spokenEnd, 0.0)
            assertArrayEquals(bin, decoded.encoded())
        }
    }

    @Test
    fun queriesDisplayWordsAndJumpsMatchSwift() {
        for (name in cases) {
            val c = load(name)
            val expected = c.json["expected"]!!.jsonObject
            val alignment = EbookAlignmentBuilder.build(c.words, c.index)
            for (q in expected["queries"]!!.jsonArray) {
                val o = q.jsonObject
                val t = o["t"]!!.jsonPrimitive.double
                assertEquals("$name t=$t", str(o["word"])?.toInt(), alignment.ebookWord(t))
            }
            val display = alignment.displayWords(c.index, c.globalOffset)
            val words = expected["displayWords"]!!.jsonArray
            assertEquals(name, words.size, display.words.size)
            for ((i, w) in words.withIndex()) {
                val o = w.jsonObject
                assertEquals(
                    PlayerTranscriptWord(o["id"]!!.jsonPrimitive.content, o["text"]!!.jsonPrimitive.content, o["start"]!!.jsonPrimitive.double, o["end"]!!.jsonPrimitive.double),
                    display.words[i],
                )
            }
            assertEquals(
                name,
                expected["displaySpans"]!!.jsonArray.map { val a = it.jsonArray; EbookDisplayWords.Span(a[0].jsonPrimitive.double, a[1].jsonPrimitive.double) },
                display.spans,
            )
            for (j in expected["narrationJumps"]!!.jsonArray) {
                val o = j.jsonObject
                val word = alignment.ebookWord(o["t"]!!.jsonPrimitive.double)
                assertEquals(str(o["word"])?.toInt(), word)
                val decorations = if (word == null) emptyList() else EbookNarrationJump.decorations(c.index, word)
                val exp = o["decorations"]!!.jsonArray
                assertEquals("$name jump", exp.size, decorations.size)
                for ((k, d) in exp.withIndex()) {
                    val e = d.jsonObject
                    val a = decorations[k]
                    assertEquals(e["id"]!!.jsonPrimitive.content, a.id)
                    assertEquals(e["wordStart"]!!.jsonPrimitive.int, a.wordStart)
                    assertEquals(e["wordEnd"]!!.jsonPrimitive.int, a.wordEnd)
                    assertEquals("$name jump $k", LocatorTextContext(str(e["before"]), str(e["highlight"]), str(e["after"])), a.text)
                }
            }
        }
    }

    @Test
    fun casesCoverTheInterestingPaths() {
        val tooFew = EbookAlignmentBuilder.build(load("too_few_matches").words, load("too_few_matches").index)
        assertTrue(tooFew.isEmpty)
        val missing = load("missing_passage")
        val a = EbookAlignmentBuilder.build(missing.words, missing.index)
        // Übersprungener Absatz: dessen Wörter fehlen im Abgleich, Intro-Wörter des Sprechers ebenso.
        assertTrue(a.words.size < missing.index.words.size)
        assertTrue(a.flags.any { it.toInt() == 1 })
        assertNull(EbookTrackAlignment.decode(ByteArray(8)))
    }

    @Test
    fun longestIncreasingSubsequence() {
        val values = intArrayOf(3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9)
        val lis = EbookAlignmentBuilder.longestIncreasingSubsequence(values)
        assertEquals(6, lis.size)
        for (k in 1 until lis.size) {
            assertTrue(lis[k] > lis[k - 1])
            assertTrue(values[lis[k]] > values[lis[k - 1]])
        }
        assertEquals(emptyList<Int>(), EbookAlignmentBuilder.longestIncreasingSubsequence(IntArray(0)))
    }
}
