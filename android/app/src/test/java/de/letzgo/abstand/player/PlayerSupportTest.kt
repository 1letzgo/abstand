package de.letzgo.abstand.player

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookMedia
import de.letzgo.abstand.data.AbsBookMediaMetadata
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import de.letzgo.abstand.data.AbsUserMediaProgress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

class PlayerSupportTest {
    private fun book(id: String) = AbsBook(
        id = id, libraryId = "lib", addedAt = null, updatedAt = null,
        media = AbsBookMedia(metadata = AbsBookMediaMetadata.offline(offlineTitle = "Title", authorLine = "Author"), duration = 100.0, numTracks = 1, tracks = null),
    )

    private val episode = AbsPodcastEpisodeListItem(
        libraryItemId = "show-1", libraryId = "lib", episodeId = "ep-1", episodeTitle = "Ep",
        showTitle = "Show", authorLine = "Host", duration = 60.0,
    )

    @Test
    fun autoMediaIdsRoundTrip() {
        val b = AbsStartShelfMergedRow.Book(book("li-1-2"))
        val e = AbsStartShelfMergedRow.PodcastEpisode(episode)
        assertEquals("book|li-1-2", AutoBrowseTree.mediaId(b))
        assertEquals("episode|show-1|ep-1", AutoBrowseTree.mediaId(e))
        assertEquals(AutoBrowseTree.MediaRef.Book("li-1-2"), AutoBrowseTree.parse("book|li-1-2"))
        assertEquals(AutoBrowseTree.MediaRef.Episode("show-1", "ep-1"), AutoBrowseTree.parse("episode|show-1|ep-1"))
        assertNull(AutoBrowseTree.parse("abstand_continue"))
        assertNull(AutoBrowseTree.parse("book|"))
        assertTrue(AutoBrowseTree.isMessageId(AutoBrowseTree.messageId("x")))
        assertEquals("show-1-ep-1", AutoBrowseTree.progressKey(e))
        assertEquals("show-1", AutoBrowseTree.coverItemId(e))
        assertEquals("Show", AutoBrowseTree.subtitle(e))
    }

    @Test
    fun autoRootTabsFollowCarPlay() {
        assertEquals(listOf(AutoBrowseTree.CONTINUE_ID, AutoBrowseTree.DOWNLOADS_ID), AutoBrowseTree.rootChildIds(false, false))
        assertEquals(
            listOf(AutoBrowseTree.CONTINUE_ID, AutoBrowseTree.BOOKS_ID, AutoBrowseTree.PODCASTS_ID, AutoBrowseTree.DOWNLOADS_ID),
            AutoBrowseTree.rootChildIds(true, true),
        )
        assertEquals(48, AutoBrowseTree.clamped((1..100).toList()).size)
    }

    @Test
    fun autoCompletion() {
        val p = AbsUserMediaProgress(libraryItemId = "a", episodeId = null, duration = 100.0, progress = 0.25, currentTime = 25.0, isFinished = false, lastUpdate = 1)
        assertEquals(0.25, AutoBrowseTree.completionFraction(p)!!, 1e-9)
        assertEquals(1, AutoBrowseTree.completionStatus(p))
        assertEquals(2, AutoBrowseTree.completionStatus(p.copy(isFinished = true)))
        assertEquals(0, AutoBrowseTree.completionStatus(null))
        assertNull(AutoBrowseTree.completionFraction(p.copy(duration = 0.0)))
    }

    @Test
    fun pendingOfflineListeningMap() {
        var map = PendingOfflineListening.adding(emptyMap(), "a", 30)
        map = PendingOfflineListening.adding(map, "a", 12)
        map = PendingOfflineListening.adding(map, "b-ep", 0)
        assertEquals(mapOf("a" to 42), map)
        assertEquals(map, PendingOfflineListening.decode(PendingOfflineListening.encode(map)))
        assertTrue(PendingOfflineListening.decode("not json").isEmpty())
        assertTrue(PendingOfflineListening.decode(null).isEmpty())
    }

    @Test
    fun smartDownloadFiresOnceAfterThreeMinutes() {
        var now = 0L
        val tracker = SmartDownloadTracker { now }
        assertFalse(tracker.tick("audiobook:a", eligible = true, enabled = true))
        now += 179_000
        assertFalse(tracker.tick("audiobook:a", eligible = true, enabled = true))
        now += 1_000
        assertTrue(tracker.tick("audiobook:a", eligible = true, enabled = true))
        now += 1_000
        assertFalse(tracker.tick("audiobook:a", eligible = true, enabled = true))
        // Pause (nicht berechtigt) unterbricht die Messung; neuer Titel beginnt von vorn.
        assertFalse(tracker.tick("audiobook:b", eligible = false, enabled = true))
        now += 500_000
        assertFalse(tracker.tick("audiobook:b", eligible = true, enabled = true))
        now += 100_000
        assertFalse(tracker.tick("audiobook:b", eligible = true, enabled = false))
    }

    @Test
    fun optimisticProgressKeepsServerFields() {
        val existing = AbsUserMediaProgress(
            mediaProgressServerId = "uuid", libraryItemId = "a", episodeId = null, duration = 100.0,
            progress = 1.0, currentTime = 100.0, isFinished = true, lastUpdate = 5_000, ebookProgress = 0.4,
        )
        val p = PlaybackHostBridge.optimisticProgress(existing, "a", null, 50.0, 200.0, nowMillis = 4_000)
        assertEquals("uuid", p.mediaProgressServerId)
        assertEquals(0.4, p.ebookProgress!!, 1e-9)
        assertFalse(p.isFinished)
        assertEquals(0.25, p.progress, 1e-9)
        assertEquals(5_001L, p.lastUpdate)
        val fresh = PlaybackHostBridge.optimisticProgress(null, "show", "ep", 30.0, 0.0, nowMillis = 9)
        assertEquals(30.0, fresh.duration, 1e-9)
        assertEquals("show-ep", fresh.progressLookupKey)
    }

    @Test
    fun transientNetworkErrors() {
        assertTrue(PlaybackController.isTransientNetworkError(UnknownHostException()))
        assertTrue(PlaybackController.isTransientNetworkError(SocketTimeoutException()))
        assertTrue(PlaybackController.isTransientNetworkError(IOException("x", java.net.ConnectException())))
        assertFalse(PlaybackController.isTransientNetworkError(IOException("x")))
        assertFalse(PlaybackController.isTransientNetworkError(de.letzgo.abstand.data.AbsApiError.HttpStatus(404, null)))
    }

    @Test
    fun eqCoefficients() {
        // Peaking ohne Verstärkung ist neutral (b == a).
        val c = AudioEQBiquadCoefficients.compute(AudioEQBiquadFilter(AudioEQBiquadFilter.Kind.peaking, 2500.0, 0.0, 1.0), 44100.0)
        assertEquals(1.0, c.b0, 1e-12)
        assertEquals(c.a1, c.b1, 1e-12)
        assertEquals(c.a2, c.b2, 1e-12)
        // Hochpass: Gleichanteil (z = 1) wird vollständig gesperrt.
        val hp = AudioEQBiquadCoefficients.compute(AudioEQBiquadFilter(AudioEQBiquadFilter.Kind.highPass, 80.0, 0.0, 0.707), 48000.0)
        assertEquals(0.0, (hp.b0 + hp.b1 + hp.b2) / (1 + hp.a1 + hp.a2), 1e-9)
        assertEquals(AudioEQPreset.voiceFocus, AudioEQPreset.fromRaw("voiceFocus"))
        assertEquals(3, AudioEQPreset.voiceFocus.filters.size)
        assertTrue(AudioEQPreset.flat.filters.isEmpty())
        assertNull(AudioEQPreset.fromRaw("loud"))
    }
}
