package de.letzgo.abstand.player

import de.letzgo.abstand.data.AbsAudioTrack
import de.letzgo.abstand.data.AbsChapter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackTimelineTest {
    private fun track(index: Int, start: Double, duration: Double) = AbsAudioTrack(index, start, duration, "t$index")

    @Test
    fun serverOffsetsUsedWhenMonotonic() {
        val t = TrackTimeline(listOf(track(1, 0.0, 100.0), track(2, 100.0, 50.0), track(3, 150.0, 25.0)))
        assertEquals(listOf(0.0, 100.0, 150.0), t.trackStarts)
        assertEquals(175.0, t.summedDuration, 1e-9)
    }

    @Test
    fun allZeroOffsetsAreAccumulatedFromDurations() {
        val t = TrackTimeline(listOf(track(1, 0.0, 100.0), track(2, 0.0, 50.0), track(3, 0.0, 25.0)))
        assertEquals(listOf(0.0, 100.0, 150.0), t.trackStarts)
    }

    @Test
    fun nonMonotonicOffsetsAreAccumulated() {
        val t = TrackTimeline(listOf(track(1, 0.0, 100.0), track(2, 300.0, 50.0), track(3, 120.0, 25.0)))
        assertEquals(listOf(0.0, 100.0, 150.0), t.trackStarts)
    }

    @Test
    fun singleTrackKeepsItsOffset() {
        val t = TrackTimeline(listOf(track(0, 0.0, 3600.0)))
        assertEquals(listOf(0.0), t.trackStarts)
    }

    @Test
    fun tracksAreSortedByIndex() {
        val t = TrackTimeline(listOf(track(2, 100.0, 50.0), track(1, 0.0, 100.0)))
        assertEquals(listOf(1, 2), t.tracks.map { it.index })
        assertEquals(listOf(0.0, 100.0), t.trackStarts)
    }

    @Test
    fun globalToTrackMapping() {
        val t = TrackTimeline(listOf(track(1, 0.0, 100.0), track(2, 100.0, 50.0), track(3, 150.0, 25.0)))
        assertEquals(0, t.trackIndex(-5.0))
        assertEquals(0, t.trackIndex(99.9))
        assertEquals(1, t.trackIndex(100.0))
        assertEquals(2, t.trackIndex(174.0))
        assertEquals(2, t.trackIndex(500.0))
        assertEquals(24.0, t.offsetInTrack(174.0), 1e-9)
        assertEquals(0.0, t.offsetInTrack(-3.0), 1e-9)
        assertEquals(130.0, t.globalTime(1, 30.0), 1e-9)
        // Unbekannter Track: lokale Zeit unverändert (iOS-Verhalten).
        assertEquals(30.0, t.globalTime(9, 30.0), 1e-9)
    }

    private val chapters = ChapterTimeline(
        listOf(
            AbsChapter(1, 600.0, 1200.0, "Two"),
            AbsChapter(0, 0.0, 600.0, "One"),
            AbsChapter(2, 1200.0, 7200.0, "Three"), // `end` trägt die Buchlänge
        ),
    )

    @Test
    fun chaptersSortedAndLookedUp() {
        assertEquals(listOf("One", "Two", "Three"), chapters.sortedChapters.map { it.title })
        assertEquals(0, chapters.chapterIndex(0.0))
        assertEquals(1, chapters.chapterIndex(600.0))
        assertEquals(2, chapters.chapterIndex(5000.0))
        assertNull(ChapterTimeline.EMPTY.chapterIndex(10.0))
    }

    @Test
    fun chapterEndTimeRules() {
        assertEquals(600.0, chapters.chapterEndTime(0, 1800.0), 1e-9)
        // Letztes Kapitel: `end` jenseits der Buchlänge → Buchende.
        assertEquals(1800.0, chapters.chapterEndTime(2, 1800.0), 1e-9)
        // Ohne Gesamtdauer: eigenes `end`.
        assertEquals(7200.0, chapters.chapterEndTime(2, 0.0), 1e-9)
        // `end` größer als nächster Start → nächster Start.
        val overlapping = ChapterTimeline(listOf(AbsChapter(0, 0.0, 900.0, "a"), AbsChapter(1, 600.0, 900.0, "b")))
        assertEquals(600.0, overlapping.chapterEndTime(0, 900.0), 1e-9)
        // Unvollständige Kapitelliste (endet vor dem Buch): letztes Kapitel reicht bis zum Buchende.
        val truncated = ChapterTimeline(listOf(AbsChapter(0, 0.0, 180.0, "a"), AbsChapter(1, 180.0, 360.0, "b")))
        assertEquals(42_000.0, truncated.chapterEndTime(1, 42_000.0), 1e-9)
        assertEquals(41_820.0, truncated.chapterProgress(42_000.0, 42_000.0)!!.duration, 1e-9)
    }

    @Test
    fun chapterSkipTargets() {
        assertEquals(600.0, chapters.previousChapterTarget(610.0)!!, 1e-9)
        assertEquals(0.0, chapters.previousChapterTarget(601.0)!!, 1e-9)
        assertEquals(0.0, chapters.previousChapterTarget(1.0)!!, 1e-9)
        assertEquals(1200.0, chapters.nextChapterTarget(610.0)!!, 1e-9)
        assertNull(chapters.nextChapterTarget(1300.0))
        assertTrue(chapters.canSkipToPreviousChapter(2.0))
        assertFalse(chapters.canSkipToPreviousChapter(1.0))
        assertFalse(chapters.canSkipToNextChapter(1300.0))
    }

    @Test
    fun chapterProgressAndMarkers() {
        val p = chapters.chapterProgress(700.0, 1800.0)!!
        assertEquals(100.0, p.position, 1e-9)
        assertEquals(600.0, p.duration, 1e-9)
        assertEquals(600.0, p.start, 1e-9)
        assertEquals(listOf(600.0 / 1800.0, 1200.0 / 1800.0), chapters.chapterMarkerFractions(1800.0))
        assertTrue(chapters.chapterMarkerFractions(0.0).isEmpty())
    }

    @Test
    fun sleepChapterCounts() {
        assertEquals(0, chapters.chapterTargetIndex(1, 100.0))
        assertEquals(2, chapters.chapterTargetIndex(2, 700.0))
        assertNull(chapters.chapterTargetIndex(3, 700.0))
        assertNull(chapters.chapterTargetIndex(0, 700.0))
        assertEquals(3, chapters.maxSleepChapterCount(10.0))
        assertEquals(1, chapters.maxSleepChapterCount(1500.0))
        assertEquals(listOf(1, 2, 3), SleepTimerMetrics.chapterOptions(3, 3))
        assertEquals(listOf(1, 2, 3, 4, 5), SleepTimerMetrics.chapterOptions(12, 9))
        assertTrue(SleepTimerMetrics.chapterOptions(0, 0).isEmpty())
    }

    @Test
    fun chapterSourcePriority() {
        val a = listOf(AbsChapter(0, 0.0, 1.0, "session"))
        val b = listOf(AbsChapter(0, 0.0, 1.0, "manifest"))
        val c = listOf(AbsChapter(0, 0.0, 1.0, "book"))
        val d = listOf(AbsChapter(0, 0.0, 1.0, "fallback"))
        assertEquals("session", ChapterTimeline.select(a, b, c, d).single().title)
        // Session liefert oft `[]` — darf die übrigen Quellen nicht verdecken.
        assertEquals("manifest", ChapterTimeline.select(emptyList(), b, c, d).single().title)
        assertEquals("book", ChapterTimeline.select(null, null, c, d).single().title)
        assertEquals("fallback", ChapterTimeline.select(null, emptyList(), emptyList(), d).single().title)
        assertTrue(ChapterTimeline.select(null, null, null, null).isEmpty())
    }

    @Test
    fun listenTimeAccumulatesOnlyWhilePlaying() {
        var now = 0L
        val acc = ListenTimeAccumulator { now }
        now = 2_500
        acc.accumulate(isPlaying = true)
        now = 10_000
        acc.accumulate(isPlaying = false) // Pause zählt nicht
        now = 11_000
        acc.accumulate(isPlaying = true)
        assertEquals(3.5, acc.pendingListenSeconds, 1e-9)
        assertEquals(3, acc.takeWholeSeconds())
        assertEquals(0.5, acc.pendingListenSeconds, 1e-9)
        acc.restore(3)
        assertEquals(3.5, acc.pendingListenSeconds, 1e-9)
        now = 20_000
        acc.resetTick()
        now = 21_000
        acc.accumulate(isPlaying = true)
        assertEquals(4.5, acc.pendingListenSeconds, 1e-9)
    }

    @Test
    fun syncPlanMatchesIosFlushRules() {
        assertEquals(SyncPlan.Skip, SyncPlan.decide(0.7, force = false, hasSession = true, isLocalPlayback = false))
        assertEquals(SyncPlan.SessionSync(0), SyncPlan.decide(0.7, force = true, hasSession = true, isLocalPlayback = false))
        assertEquals(SyncPlan.SessionSync(20), SyncPlan.decide(20.9, force = false, hasSession = true, isLocalPlayback = true))
        // Stream ohne Session: nichts zu tun.
        assertEquals(SyncPlan.Skip, SyncPlan.decide(30.0, force = true, hasSession = false, isLocalPlayback = false))
        // Lokale Datei ohne Session: Callback (PATCH/Offline-Hörzeit), bei `force` auch mit 0 s.
        assertEquals(SyncPlan.LocalWithoutSession(5), SyncPlan.decide(5.2, force = false, hasSession = false, isLocalPlayback = true))
        assertEquals(SyncPlan.LocalWithoutSession(0), SyncPlan.decide(0.2, force = true, hasSession = false, isLocalPlayback = true))
        assertEquals(SyncPlan.Skip, SyncPlan.decide(0.2, force = false, hasSession = false, isLocalPlayback = true))
        assertEquals(20_000L, SyncPlan.PERIODIC_SYNC_INTERVAL_MS)
    }

    @Test
    fun playbackRatesSnapAndCycle() {
        assertEquals(1.25f, PlaybackRates.snapped(1.3f))
        assertEquals(0.5f, PlaybackRates.snapped(0.1f))
        assertEquals(2.0f, PlaybackRates.snapped(3.0f))
        assertEquals(1.0f, PlaybackRates.fromSaved(0.0))
        assertEquals(1.5f, PlaybackRates.fromSaved(1.5))
        assertEquals(1.25f, PlaybackRates.next(1.0f))
        assertEquals(0.5f, PlaybackRates.next(2.0f))
    }

    @Test
    fun skipIntervals() {
        assertEquals(15, PlaybackSkipDefaults.clamped(15, 30))
        assertEquals(30, PlaybackSkipDefaults.clamped(20, 30))
        assertEquals("Back 15 seconds", PlaybackSkipDefaults.accessibilityLabel(true, 15))
        assertEquals("Forward 30 seconds", PlaybackSkipDefaults.accessibilityLabel(false, 30))
    }
}
