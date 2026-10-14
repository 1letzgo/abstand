package de.letzgo.abstand.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** `progressLookupKey`-Parität gegen `shared/fixtures/progress_keys.json`. */
class ProgressKeysTest {
    private val root = AbsJson.decoder.parseToJsonElement(Fixtures.text("progress_keys.json")) as JsonObject

    private fun str(o: JsonObject, k: String): String? = SwiftJson.string(o[k])

    @Test
    fun lookupKeys() {
        val cases = root["cases"] as JsonArray
        assertTrue(cases.isNotEmpty())
        for (c in cases.map { it as JsonObject }) {
            val lid = str(c, "libraryItemId")!!
            val eid = str(c, "episodeId")
            val progress = AbsUserMediaProgress(
                libraryItemId = lid, episodeId = eid, duration = 0.0, progress = 0.0,
                currentTime = 0.0, isFinished = false, lastUpdate = null,
            )
            assertEquals("mediaProgress $c", str(c, "mediaProgress"), progress.progressLookupKey)
            if (eid != null) {
                val row = AbsPodcastEpisodeListItem(
                    libraryItemId = lid, episodeId = eid, episodeTitle = "t", showTitle = "s",
                    authorLine = "a", duration = 0.0,
                )
                assertEquals("episodeListItem $c", str(c, "episodeListItem"), row.progressLookupKey)
                assertEquals(row.progressLookupKey, row.id)
            }
        }
    }

    @Test
    fun decodedFromServerId() {
        for (c in (root["decodedFromServerId"] as JsonArray).map { it as JsonObject }) {
            val p = AbsJson.decoder.decodeFromJsonElement(AbsUserMediaProgressSerializer, c["json"]!!)
            assertEquals(str(c, "libraryItemId"), p.libraryItemId)
            assertEquals(str(c, "mediaProgressServerId"), p.mediaProgressServerId)
            assertEquals(str(c, "progressLookupKey"), p.progressLookupKey)
            assertEquals(str(c, "deleteId"), p.idForMediaProgressDeleteRequest)
        }
    }
}
