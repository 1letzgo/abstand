package de.letzgo.abstand.logic

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/**
 * `shared/fixtures/transcript_cache/`: Dateien, die der Kotlin-Writer erzeugt (Abgleich-Binärdatei und
 * Track-Transkript-JSON) plus `contents.json` mit ihrem Inhalt, damit iOS beweisen kann, dass es sie
 * identisch liest. Neu schreiben: `ABSTAND_WRITE_FIXTURES=1 ./gradlew testSideloadDebugUnitTest`.
 */
class TranscriptCacheGoldenTest {
    private val bookId = "li_8f3c2a91-4d7e-4b2a-9c1f-0e5d6b7a8c90"
    private val trackIndex = 3
    private val locale = "en-US"

    private fun alignment() = EbookTrackAlignment(
        ebookWordCount = 1234,
        spokenWordCount = 987,
        spokenEnd = 412.345678,
        words = intArrayOf(0, 1, 2, 5, 6, 1233),
        starts = floatArrayOf(0.5f, 0.82f, 1.1f, 2.25f, 2.6f, 410.0f),
        ends = floatArrayOf(0.8f, 1.05f, 1.6f, 2.55f, 3.125f, 412.3f),
        flags = byteArrayOf(1, 1, 0, 1, 0, 1),
    )

    private fun transcript() = PlayerTranscriptTrackCache(
        localeIdentifier = locale,
        trackIndex = trackIndex,
        segments = listOf(
            PlayerTranscriptTrackCache.Segment(
                0.0, 120.5,
                listOf(
                    PlayerTranscriptTrackCache.Word("the", 0.5, 0.8),
                    PlayerTranscriptTrackCache.Word("lighthouse", 0.82, 1.6),
                    PlayerTranscriptTrackCache.Word("don't", 2.25, 2.55),
                    PlayerTranscriptTrackCache.Word("Straße", 2.6, 3.125),
                ),
            ),
            PlayerTranscriptTrackCache.Segment(300.0, 412.4, listOf(PlayerTranscriptTrackCache.Word("end", 410.0, 412.3))),
        ),
    )

    private val binName get() = PlayerTranscriptCacheStore.alignmentFileName(trackIndex, locale)
    private val jsonName get() = PlayerTranscriptCacheStore.transcriptFileName(trackIndex, locale)

    private fun contents(): JsonObject {
        val a = alignment()
        return buildJsonObject {
            put("description", "Written by the Android Kotlin writer (EbookTrackAlignment.encoded / PlayerTranscriptCacheStore.encode). iOS must decode both files to exactly these values.")
            put("bookId", bookId)
            put("bookDirectory", "transcripts/" + PlayerTranscriptCacheStore.sha256Hex(bookId))
            put("alignmentFile", binName)
            put("transcriptFile", jsonName)
            put("alignment", buildJsonObject {
                put("magic", "0x41424C31")
                put("formatVersion", EbookTrackAlignment.FORMAT_VERSION)
                put("byteOrder", "little-endian")
                put("layout", "u32 magic, u32 version, i32 ebookWordCount, i32 spokenWordCount, f64 spokenEnd, i32 count, i32[count] words, f32[count] starts, f32[count] ends, u8[count] flags")
                put("ebookWordCount", a.ebookWordCount)
                put("spokenWordCount", a.spokenWordCount)
                put("spokenEnd", a.spokenEnd)
                put("words", buildJsonArray { a.words.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } })
                put("starts", buildJsonArray { a.starts.forEach { add(kotlinx.serialization.json.JsonPrimitive(it.toDouble())) } })
                put("ends", buildJsonArray { a.ends.forEach { add(kotlinx.serialization.json.JsonPrimitive(it.toDouble())) } })
                put("flags", buildJsonArray { a.flags.forEach { add(kotlinx.serialization.json.JsonPrimitive(it.toInt())) } })
                put("byteCount", a.encoded().size)
            })
            put("transcript", Json.parseToJsonElement(PlayerTranscriptCacheStore.encode(transcript())))
        }
    }

    private fun resource(name: String) = javaClass.classLoader!!.getResource("transcript_cache/$name")

    @Test
    fun kotlinWriterMatchesCommittedFixture() {
        if (System.getenv("ABSTAND_WRITE_FIXTURES") == "1") {
            val dir = File("../../shared/fixtures/transcript_cache").apply { mkdirs() }
            File(dir, binName).writeBytes(alignment().encoded())
            File(dir, jsonName).writeText(PlayerTranscriptCacheStore.encode(transcript()))
            File(dir, "contents.json").writeText(
                Json { prettyPrint = true }.encodeToString(JsonObject.serializer(), contents()) + "\n",
            )
        }
        assertArrayEquals(resource(binName)!!.readBytes(), alignment().encoded())
        assertEquals(resource(jsonName)!!.readText(), PlayerTranscriptCacheStore.encode(transcript()))

        val c = Json.parseToJsonElement(resource("contents.json")!!.readText()).jsonObject
        val expected = c["alignment"]!!.jsonObject
        val decoded = EbookTrackAlignment.decode(resource(binName)!!.readBytes())!!
        assertEquals(expected["ebookWordCount"]!!.jsonPrimitive.int, decoded.ebookWordCount)
        assertEquals(expected["spokenWordCount"]!!.jsonPrimitive.int, decoded.spokenWordCount)
        assertEquals(expected["spokenEnd"]!!.jsonPrimitive.double, decoded.spokenEnd, 0.0)
        assertEquals(expected["words"]!!.jsonArray.map { it.jsonPrimitive.int }, decoded.words.toList())
        assertEquals(expected["starts"]!!.jsonArray.map { it.jsonPrimitive.double.toFloat() }, decoded.starts.toList())
        assertEquals(expected["flags"]!!.jsonArray.map { it.jsonPrimitive.int }, decoded.flags.map { it.toInt() })
        assertEquals("transcripts/" + PlayerTranscriptCacheStore.sha256Hex(bookId), c["bookDirectory"]!!.jsonPrimitive.content)

        val roundTrip = PlayerTranscriptCacheStore.decode(resource(jsonName)!!.readText())!!
        assertEquals(transcript(), roundTrip)
    }

    @Test
    fun fileNamesAndPaths() {
        assertEquals("a3-en-US.bin", PlayerTranscriptCacheStore.alignmentFileName(3, "en-US"))
        assertEquals("t0-zh-Hans_x.json", PlayerTranscriptCacheStore.transcriptFileName(0, "zh-Hans/x"))
        // SHA-256 von "abc" (bekannter Testvektor).
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", PlayerTranscriptCacheStore.sha256Hex("abc"))
        val account = File("/acc")
        assertEquals(
            File("/acc/transcripts/ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad/a1-de-DE.bin"),
            PlayerTranscriptCacheStore.alignmentFileFor(account, "abc", 1, "de-DE"),
        )
    }

    @Test
    fun versionMismatchIsRejected() {
        val json = PlayerTranscriptCacheStore.encode(transcript()).replace("\"version\":1", "\"version\":2")
        assertEquals(null, PlayerTranscriptCacheStore.decode(json))
    }

    @Test
    fun storeRoundTripOnDisk() {
        val account = createTempDir()
        try {
            PlayerTranscriptCacheStore.save(transcript(), account, bookId)
            assertEquals(transcript(), PlayerTranscriptCacheStore.load(account, bookId, trackIndex, locale))
            PlayerTranscriptCacheStore.saveAlignment(alignment().encoded(), account, bookId, trackIndex, locale)
            assertArrayEquals(alignment().encoded(), PlayerTranscriptCacheStore.loadAlignment(account, bookId, trackIndex, locale))
            PlayerTranscriptCacheStore.removeAll(account, bookId)
            assertEquals(null, PlayerTranscriptCacheStore.load(account, bookId, trackIndex, locale))
        } finally {
            account.deleteRecursively()
        }
    }
}
