package de.letzgo.abstand.player

import de.letzgo.abstand.data.AbsAudioTrack
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalDownloadSwitchTest {
    private fun plan(
        activeItemId: String? = "li_1",
        activeEpisodeId: String? = null,
        offline: Boolean = false,
        manifestItemId: String = "li_1",
        manifestEpisodeId: String? = null,
        position: Double = 1234.5,
        playing: Boolean = true,
        tracksPresent: Boolean = true,
    ) = LocalDownloadSwitch.plan(
        activeItemId, activeEpisodeId, offline, manifestItemId, manifestEpisodeId, position, playing,
    ) { tracksPresent }

    @Test
    fun streamingSameBookSwitchesAtSamePositionAndKeepsPlaying() {
        val p = plan()!!
        assertEquals(1234.5, p.resumeAt, 1e-9)
        assertTrue(p.autoPlay)
        assertNull(p.episodeId)
    }

    @Test
    fun pausedStreamStaysPaused() {
        assertFalse(plan(playing = false)!!.autoPlay)
    }

    @Test
    fun alreadyLocalDoesNotSwitch() {
        assertNull(plan(offline = true))
    }

    @Test
    fun otherItemOrNothingPlayingDoesNotSwitch() {
        assertNull(plan(manifestItemId = "li_2"))
        assertNull(plan(activeItemId = null))
    }

    @Test
    fun episodesMustMatchTrimmed() {
        val p = plan(activeEpisodeId = " ep_1 ", manifestEpisodeId = "ep_1")!!
        assertEquals("ep_1", p.episodeId)
        assertNull(plan(activeEpisodeId = "ep_1", manifestEpisodeId = "ep_2"))
        // Hörbuch-Download darf eine laufende Folge desselben Items nicht übernehmen (und umgekehrt).
        assertNull(plan(activeEpisodeId = "ep_1", manifestEpisodeId = null))
        assertNull(plan(activeEpisodeId = null, manifestEpisodeId = "ep_1"))
        assertEquals(null, plan(activeEpisodeId = "  ", manifestEpisodeId = "")!!.episodeId)
    }

    @Test
    fun incompleteDownloadDoesNotSwitch() {
        assertNull(plan(tracksPresent = false))
    }

    @Test
    fun trackCheckOnlyAfterCheapGuards() {
        var checked = false
        LocalDownloadSwitch.plan("li_1", null, true, "li_1", null, 0.0, true) { checked = true; true }
        assertFalse(checked)
        LocalDownloadSwitch.plan("li_1", null, false, "li_2", null, 0.0, true) { checked = true; true }
        assertFalse(checked)
    }

    @Test
    fun negativePositionClampedToStart() {
        assertEquals(0.0, plan(position = -3.0)!!.resumeAt, 1e-9)
    }

    @Test
    fun globalPositionMapsToSameTrackInLocalTimeline() {
        // Stream-Session (Server-Offsets) und Download-Manifest (gleiche Tracks) teilen die Buchzeit:
        // die globale Position landet lokal im selben Track an derselben Stelle.
        val stream = TrackTimeline(listOf(AbsAudioTrack(1, 0.0, 600.0, "a"), AbsAudioTrack(2, 600.0, 900.0, "b")))
        val local = TrackTimeline(listOf(AbsAudioTrack(2, 600.0, 900.0, "b"), AbsAudioTrack(1, 0.0, 600.0, "a")))
        val resumeAt = plan(position = 1000.0)!!.resumeAt
        assertEquals(stream.trackIndex(resumeAt), local.trackIndex(resumeAt))
        assertEquals(1, local.trackIndex(resumeAt))
        assertEquals(400.0, local.offsetInTrack(resumeAt), 1e-9)
    }
}
