package de.letzgo.abstand.downloads

import de.letzgo.abstand.data.AbsAudioTrack
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.Fixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class DownloadsTest {

    @Test
    fun manifestGoldenFileRoundTripsByteIdentically() {
        val golden = Fixtures.text("download_manifest.json").trimEnd('\n')
        val m = AbsJson.decoder.decodeFromString(de.letzgo.abstand.data.AbsDownloadManifestSerializer, golden)
        assertEquals(1, m.format)
        assertEquals("li-1234-abcd", m.libraryItemId)
        assertNull(m.episodeId)
        assertEquals("Das Testbuch – Teil 1/2", m.displayTitle)
        assertEquals(1760450000.5, m.savedAtEpoch, 1e-6)
        assertEquals(3600.0, m.totalDuration!!, 1e-9)
        assertEquals(listOf(1, 2), m.tracks.map { it.index })
        assertEquals(1800.5, m.tracks[1].startOffset, 1e-9)
        assertEquals("Kapitel 2 / Mitte", m.chapters!![1].title)
        assertEquals("li-1234-abcd", m.offlineStorageItemId)
        // iOS `JSONEncoder` + `.sortedKeys`: gleiche Bytes.
        assertEquals(golden, AbsDownloadManifest.encodeToString(m))
    }

    @Test
    fun manifestWriteAndLoad() {
        val dir = Files.createTempDirectory("abs-manifest").toFile()
        try {
            val m = AbsDownloadManifest(
                format = 1, libraryItemId = "show", episodeId = "ep/1", libraryId = null, displayTitle = "Episode",
                displayAuthor = "Show", playSessionId = "", savedAtEpoch = 1.0, audioFileExtension = "mp3",
                totalDuration = null, tracks = listOf(AbsDownloadManifest.Track(0, 0.0, 61.25, null)), chapters = null,
            )
            m.write(dir)
            val text = File(dir, AbsDownloadManifest.FILENAME).readText()
            assertEquals(
                """{"audioFileExtension":"mp3","displayAuthor":"Show","displayTitle":"Episode","episodeId":"ep\/1","format":1,""" +
                    """"libraryItemId":"show","playSessionId":"","savedAtEpoch":1,"tracks":[{"duration":61.25,"index":0,"startOffset":0}]}""",
                text,
            )
            assertEquals(m, AbsDownloadManifest.load(dir))
            assertEquals("show-ep_1", m.offlineStorageItemId)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun swiftNumberFormatting() {
        assertEquals("0", AbsDownloadManifest.swiftNumber(0.0))
        assertEquals("3600", AbsDownloadManifest.swiftNumber(3600.0))
        assertEquals("1760450000.123", AbsDownloadManifest.swiftNumber(1760450000.123))
        assertEquals("0.0001", AbsDownloadManifest.swiftNumber(0.0001))
        assertEquals("-2.5", AbsDownloadManifest.swiftNumber(-2.5))
    }

    @Test
    fun legacyManifestWithIsoDateDecodes() {
        val text = """{"format":1,"libraryItemId":"x","savedAt":"2024-05-01T12:00:00Z","tracks":[]}"""
        val m = AbsJson.decoder.decodeFromString(de.letzgo.abstand.data.AbsDownloadManifestSerializer, text)
        assertEquals(1714564800.0, m.savedAtEpoch, 1e-6)
        assertNull(m.chapters)
    }

    @Test
    fun queueIsFifoWithSingleActiveRun() {
        val q = DownloadQueue<String> { it }
        assertTrue(q.enqueue("a"))
        assertTrue(q.enqueue("b"))
        assertTrue(q.enqueue("c"))
        assertFalse(q.enqueue("b")) // idempotent
        assertEquals("a", q.takeNext())
        assertNull(q.takeNext()) // höchstens ein aktiver Lauf
        assertFalse(q.enqueue("a")) // aktiv → No-Op
        assertEquals(listOf("b", "c"), q.queuedIds)
        assertTrue(q.removeQueued("b"))
        assertFalse(q.removeQueued("a")) // aktiv, nicht wartend
        assertEquals("a", q.finishActive())
        assertEquals("c", q.takeNext())
        q.requeueActiveAtFront()
        assertNull(q.active)
        assertEquals(listOf("c"), q.queuedIds)
        q.enqueue("d")
        assertEquals(listOf("c", "d"), q.snapshot())
        q.restore(listOf("x", "y", "x"))
        assertEquals(listOf("x", "y"), q.queuedIds)
        assertTrue(q.contains("y"))
    }

    @Test
    fun progressWeights() {
        val tracks = listOf(
            AbsAudioTrack(0, 0.0, 10.0, null),
            AbsAudioTrack(1, 10.0, 600.0, null),
            AbsAudioTrack(2, 610.0, 0.0, null),
        )
        val w = DownloadProgressWeights.weights(tracks)
        assertEquals(listOf(30.0, 600.0, 300.0), w)
        val sum = DownloadProgressWeights.sum(w)
        assertEquals(930.0, sum, 1e-9)
        assertEquals((30.0 + 300.0) / 930.0, DownloadProgressWeights.fraction(30.0, 600.0, 0.5, sum), 1e-9)
        assertEquals(1.0, DownloadProgressWeights.fraction(930.0, 300.0, 1.0, sum), 1e-9)
        assertEquals(1.0, DownloadProgressWeights.sum(emptyList()), 1e-9)
    }

    @Test
    fun wipUsesIosKeys() {
        val text = AbsJson.encoder.encodeToString(DownloadWip.serializer(), DownloadWip("s", "l", null, listOf(0, 2)))
        assertEquals("""{"storageItemId":"s","libraryItemId":"l","completedTrackIndexes":[0,2]}""", text)
        val decoded = AbsJson.decoder.decodeFromString(
            DownloadWip.serializer(),
            """{"completedTrackIndexes":[1],"episodeId":"e","libraryItemId":"l","storageItemId":"s-e"}""",
        )
        assertEquals(DownloadWip("s-e", "l", "e", listOf(1)), decoded)
    }

    @Test
    fun podcastAutoDownloadIntervals() {
        assertEquals(PodcastAutoDownloadInterval.everyHour, PodcastAutoDownloadInterval.from("0 * * * *"))
        assertEquals(PodcastAutoDownloadInterval.every6Hours, PodcastAutoDownloadInterval.from("  0  */6 * * * "))
        assertEquals(PodcastAutoDownloadInterval.weekly, PodcastAutoDownloadInterval.from("30 4 * * 5"))
        assertEquals(PodcastAutoDownloadInterval.daily, PodcastAutoDownloadInterval.from("15 3 * * *"))
        // Stunden-Feld vor „täglich“: kein Fehlgriff auf daily.
        assertEquals(PodcastAutoDownloadInterval.every6Hours, PodcastAutoDownloadInterval.from("5 */6 * * *"))
        assertEquals(PodcastAutoDownloadInterval.every12Hours, PodcastAutoDownloadInterval.from("5 */12 * * *"))
        assertEquals(PodcastAutoDownloadInterval.everyHour, PodcastAutoDownloadInterval.from("5 * * * *"))
        assertEquals(PodcastAutoDownloadInterval.everyHour, PodcastAutoDownloadInterval.from("0 * 1 * *"))
        assertEquals(PodcastAutoDownloadInterval.daily, PodcastAutoDownloadInterval.from(null))
        assertEquals(PodcastAutoDownloadInterval.daily, PodcastAutoDownloadInterval.from("bogus"))
    }

    @Test
    fun staleTempFilesRemovedOnlyWhenOld() {
        val root = Files.createTempDirectory("abs-downloads").toFile()
        try {
            val item = File(root, "book-1").apply { mkdirs() }
            val oldPart = File(item, "abs-dl-123.part").apply { writeText("xx"); setLastModified(1_000) }
            val newPart = File(item, "abs-dl-456.part").apply { writeText("yy") }
            val track = File(item, "track_0.m4a").apply { writeText("audio"); setLastModified(1_000) }
            val removed = DownloadMaintenance.removeStaleDownloadTempFiles(root, nowMs = System.currentTimeMillis())
            assertEquals(2L, removed)
            assertFalse(oldPart.exists())
            assertTrue(newPart.exists())
            assertTrue(track.exists())
            assertTrue(DownloadMaintenance.isDownloadTempFile("download-wip.json.tmp"))
        } finally {
            root.deleteRecursively()
        }
    }
}
