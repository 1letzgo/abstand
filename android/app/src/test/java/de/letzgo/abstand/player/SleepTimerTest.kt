package de.letzgo.abstand.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SleepTimerTest {
    private var now = 1_000_000L
    private val timer = SleepTimer { now }

    private fun startMinutes(minutes: Int, isPlaying: Boolean) {
        // AppModel.applySleepTimer(minutes:): Modus setzen, dann Restlaufzeit.
        timer.setMode(SleepTimerMode.Minutes(minutes))
        timer.applyRemaining(minutes * 60.0, isPlaying)
    }

    @Test
    fun minutesWhilePlayingSetsEndDate() {
        startMinutes(15, isPlaying = true)
        assertEquals(now + 15 * 60_000L, timer.sleepEndDate.value)
        assertEquals(SleepTimerMode.Minutes(15), timer.sleepTimerMode.value)
        now += 60_000
        assertEquals(14 * 60.0, timer.displaySeconds()!!, 1e-6)
        assertTrue(timer.isActive)
    }

    @Test
    fun minutesWhilePausedWaitsForPlay() {
        startMinutes(5, isPlaying = false)
        // Sink darf das `null`-Ende nicht als „aus“ werten.
        assertEquals(SleepTimerMode.Minutes(5), timer.sleepTimerMode.value)
        assertNull(timer.sleepEndDate.value)
        assertEquals(300.0, timer.displaySeconds()!!, 1e-6)
        timer.resumeIfNeeded(isPlaying = true)
        assertEquals(now + 300_000L, timer.sleepEndDate.value)
    }

    @Test
    fun pauseFreezesAndResumeContinues() {
        startMinutes(10, isPlaying = true)
        now += 120_000
        timer.pause()
        assertNull(timer.sleepEndDate.value)
        assertTrue(timer.isPaused)
        now += 3_600_000 // Pause läuft nicht mit
        assertEquals(480.0, timer.displaySeconds()!!, 1e-6)
        timer.resumeIfNeeded(isPlaying = true)
        assertEquals(now + 480_000L, timer.sleepEndDate.value)
    }

    @Test
    fun expiryOpensGraceWindowForRestart() {
        startMinutes(30, isPlaying = true)
        now += 30 * 60_000L
        assertTrue(timer.isWallClockExpired())
        timer.markExpired()
        assertEquals(SleepTimerMode.Off, timer.sleepTimerMode.value)
        assertFalse(timer.isActive)
        now += 45_000
        assertTrue(timer.restoreIfWithinGrace(isPlaying = true))
        assertEquals(SleepTimerMode.Minutes(30), timer.sleepTimerMode.value)
        assertEquals(now + 30 * 60_000L, timer.sleepEndDate.value)
    }

    @Test
    fun noRestartAfterGraceWindow() {
        startMinutes(5, isPlaying = true)
        now += 5 * 60_000L
        timer.markExpired()
        now += 61_000
        assertFalse(timer.restoreIfWithinGrace(isPlaying = true))
        assertEquals(SleepTimerMode.Off, timer.sleepTimerMode.value)
    }

    @Test
    fun clearDropsGraceData() {
        startMinutes(5, isPlaying = true)
        now += 5 * 60_000L
        timer.markExpired()
        timer.clear()
        assertFalse(timer.restoreIfWithinGrace(isPlaying = true))
    }

    @Test
    fun chapterTargetHasNoWallClock() {
        timer.setMode(SleepTimerMode.Chapters(2))
        timer.applyChapterTarget(4)
        assertEquals(SleepTimerMode.Chapters(2), timer.sleepTimerMode.value)
        assertNull(timer.sleepEndDate.value)
        assertNull(timer.displaySeconds())
        assertTrue(timer.isActive)
        // 30 s Medienzeit bis Kapitelende bei 1,5× → 20 s Echtzeit.
        assertEquals(20.0, timer.secondsUntilStop(true, chapterEnd = 130.0, position = 100.0, playbackRate = 1.5f)!!, 1e-9)
        assertNull(timer.secondsUntilStop(false, chapterEnd = 130.0, position = 100.0, playbackRate = 1f))
        // Kapitel-Timer kennt kein Grace-Restart.
        timer.markExpired()
        assertFalse(timer.restoreIfWithinGrace(isPlaying = true))
    }

    @Test
    fun minutesReplaceChapterTarget() {
        timer.setMode(SleepTimerMode.Chapters(1))
        timer.applyChapterTarget(0)
        startMinutes(10, isPlaying = true)
        assertNull(timer.chapterTarget)
    }

    @Test
    fun reconcileAfterBackground() {
        startMinutes(1, isPlaying = true)
        now += 61_000
        assertTrue(timer.reconcileAfterBackground(isPlaying = true))
        assertEquals(SleepTimerMode.Off, timer.sleepTimerMode.value)

        startMinutes(1, isPlaying = true)
        now += 10_000
        timer.pause()
        assertFalse(timer.reconcileAfterBackground(isPlaying = true))
        assertFalse(timer.isPaused)
    }

    @Test
    fun fadeVolume() {
        assertEquals(1f, SleepTimer.fadeVolume(null))
        assertEquals(1f, SleepTimer.fadeVolume(20.0))
        assertEquals(0.5f, SleepTimer.fadeVolume(7.5), 1e-6f)
        assertEquals(0f, SleepTimer.fadeVolume(-1.0))
    }

    @Test
    fun menuLabels() {
        assertEquals(listOf(5, 10, 15, 30, 45, 60, 90, 120), SleepTimerMetrics.minutePresets)
        assertEquals("Off", SleepTimerMetrics.minutesLabel(0))
        assertEquals("45 min", SleepTimerMetrics.minutesLabel(45))
        assertEquals("End of Chapter", SleepTimerMetrics.chaptersMenuLabel(1))
        assertEquals("End of 3 Chapters", SleepTimerMetrics.chaptersMenuLabel(3))
    }

    // MARK: - Snapshot über Player-Neuaufbau (Download fertig → lokal weiter)

    @Test
    fun snapshotSurvivesClearAndRestoresRemainingWhilePlaying() {
        startMinutes(30, isPlaying = true)
        now += 10 * 60_000L
        val snap = timer.snapshot()!!
        timer.clear() // tearDownPlayer
        assertEquals(SleepTimerMode.Off, timer.sleepTimerMode.value)
        timer.restore(snap, isPlaying = true)
        assertEquals(SleepTimerMode.Minutes(30), timer.sleepTimerMode.value)
        assertEquals(now + 20 * 60_000L, timer.sleepEndDate.value)
        assertTrue(timer.isActive)
    }

    @Test
    fun restoreWhileNotYetPlayingWaitsForPlay() {
        startMinutes(15, isPlaying = false)
        val snap = timer.snapshot()!!
        timer.clear()
        timer.restore(snap, isPlaying = false)
        assertEquals(SleepTimerMode.Minutes(15), timer.sleepTimerMode.value)
        assertNull(timer.sleepEndDate.value)
        assertEquals(900.0, timer.displaySeconds()!!, 1e-6)
        timer.resumeIfNeeded(isPlaying = true)
        assertEquals(now + 900_000L, timer.sleepEndDate.value)
    }

    @Test
    fun chapterTimerSnapshotKeepsTarget() {
        timer.setMode(SleepTimerMode.Chapters(2))
        timer.applyChapterTarget(3)
        val snap = timer.snapshot()!!
        timer.clear()
        timer.restore(snap, isPlaying = true)
        assertEquals(SleepTimerMode.Chapters(2), timer.sleepTimerMode.value)
        assertEquals(3, timer.chapterTarget)
        assertTrue(timer.isActive)
    }

    @Test
    fun inactiveTimerHasNoSnapshot() {
        assertNull(timer.snapshot())
    }
}
