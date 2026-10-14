package de.letzgo.abstand.player

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.max

/** iOS: `SleepTimerMode` — aktive Sleep-Timer-Konfiguration (Menü-Haken, Beschriftung). */
sealed class SleepTimerMode {
    data object Off : SleepTimerMode()
    data class Minutes(val minutes: Int) : SleepTimerMode()
    data class Chapters(val chapters: Int) : SleepTimerMode()
}

/** iOS: `SleepTimerMetrics` (MiniPlayerView.swift) + Menü-Beschriftungen. */
object SleepTimerMetrics {
    /** Feste Auswahl wie in Apple Podcasts/Books — ein Tipp statt Stepper-Klicks. */
    val minutePresets: List<Int> = listOf(5, 10, 15, 30, 45, 60, 90, 120)
    /** „Ende von n Kapiteln“: Auswahl bis maximal so viele Kapitel (begrenzt auf die verbleibenden). */
    const val maxChapterOption = 5

    /** iOS: `SleepTimerUtilityMenu.chapterOptions`. */
    fun chapterOptions(chapterCount: Int, maxSleepChapterCount: Int): List<Int> {
        if (chapterCount <= 0) return emptyList()
        val available = minOf(maxChapterOption, maxSleepChapterCount)
        return if (available >= 1) (1..available).toList() else emptyList()
    }

    fun offLabel(): String = "Off"

    fun minutesLabel(minutes: Int): String = if (minutes <= 0) offLabel() else "$minutes min"

    fun chaptersMenuLabel(count: Int): String = if (count <= 1) "End of Chapter" else "End of $count Chapters"
}

/**
 * iOS: Sleep-Timer-Teil von `PlaybackController` (`sleepEndDate`, `sleepTimerMode`,
 * `sleepTimerRemaining`, `sleepTimerPaused`, `sleepTimerChapterTarget`, Grace-Restart, Fade-out).
 *
 * Wanduhr-basiert für den Minuten-Modus (läuft nur während der Wiedergabe, bei Pause eingefroren),
 * positionsbasiert für den Kapitel-Modus. Der Combine-Sink auf `$sleepEndDate` ist als
 * [setSleepEndDate] nachgebaut: jede Zuweisung von `null` schaltet den Modus aus, solange der
 * Timer weder pausiert noch ein Kapitel-Ziel hat.
 *
 * @param clockMillis Wanduhr (Tests: steuerbar).
 */
class SleepTimer(private val clockMillis: () -> Long = System::currentTimeMillis) {
    private val _sleepEndDate = MutableStateFlow<Long?>(null)
    /** Ende in Millisekunden seit 1970 — nur während der Wiedergabe gesetzt (iOS: `sleepEndDate`). */
    val sleepEndDate: StateFlow<Long?> = _sleepEndDate.asStateFlow()

    private val _sleepTimerMode = MutableStateFlow<SleepTimerMode>(SleepTimerMode.Off)
    val sleepTimerMode: StateFlow<SleepTimerMode> = _sleepTimerMode.asStateFlow()

    /** Verbleibende Laufzeit in Sekunden; bei Pause eingefroren. */
    var remaining: Double? = null
        private set
    var isPaused: Boolean = false
        private set
    /** Ziel-Kapitelindex (0-basiert) für den Kapitel-Timer; `null` = nicht aktiv. */
    var chapterTarget: Int? = null
        private set

    private var lastExpiredMode: SleepTimerMode? = null
    private var lastExpiredSeconds: Double? = null
    private var lastExpiredDate: Long? = null

    /** AppModel setzt den Modus vor `applySleepTimerRemaining` / `applySleepTimerChapterTarget`. */
    fun setMode(mode: SleepTimerMode) {
        _sleepTimerMode.value = mode
    }

    /** Nachbau des `$sleepEndDate`-Sinks. */
    private fun setSleepEndDate(value: Long?) {
        _sleepEndDate.value = value
        if (value == null) {
            // Kapitel-Timer nutzt bewusst kein `sleepEndDate` — nicht als „aus“ werten.
            if (!isPaused && chapterTarget == null) {
                _sleepTimerMode.value = SleepTimerMode.Off
                remaining = null
            }
        }
    }

    /** Sleep-Timer komplett aus (manuell „Aus“, Track-Ende) — inkl. Grace-Daten. */
    fun clear() {
        remaining = null
        isPaused = false
        setSleepEndDate(null)
        chapterTarget = null
        lastExpiredMode = null
        lastExpiredSeconds = null
        lastExpiredDate = null
    }

    fun applyRemaining(seconds: Double, isPlaying: Boolean) {
        remaining = max(0.0, seconds)
        // Minuten-Modus aktiv: Kapitel-Ziel verwerfen (beide Modi schließen sich aus).
        chapterTarget = null
        val mode = _sleepTimerMode.value
        if (seconds > 0 && mode is SleepTimerMode.Minutes && mode.minutes > 0) {
            lastExpiredMode = SleepTimerMode.Minutes(mode.minutes)
            lastExpiredSeconds = mode.minutes * 60.0
        }
        lastExpiredDate = null
        if (isPlaying) {
            isPaused = false
            scheduleWakeIfNeeded(isPlaying = true)
        } else {
            // Erst als pausiert markieren: sonst wertet der Sink `null` als „Timer aus“.
            // Start mit dem nächsten Play (`resumeIfNeeded`).
            isPaused = true
            setSleepEndDate(null)
        }
    }

    /** Kapitel-Timer: feuert, sobald die Wiedergabe das Ende des Ziel-Kapitels erreicht. */
    fun applyChapterTarget(targetIndex: Int) {
        chapterTarget = targetIndex
        remaining = null
        isPaused = false
        setSleepEndDate(null)
        lastExpiredDate = null
    }

    private fun scheduleWakeIfNeeded(isPlaying: Boolean) {
        val r = remaining
        if (r == null || r <= 0 || isPaused || !isPlaying) {
            setSleepEndDate(null)
            return
        }
        setSleepEndDate(clockMillis() + (r * 1000).toLong())
    }

    /** Wiedergabe pausiert: Restlaufzeit einfrieren. */
    fun pause() {
        if (_sleepTimerMode.value == SleepTimerMode.Off) return
        val end = _sleepEndDate.value
        if (end == null && (remaining ?: 0.0) <= 0) return
        if (end != null) remaining = max(0.0, (end - clockMillis()) / 1000.0)
        isPaused = true
        setSleepEndDate(null)
    }

    fun resumeIfNeeded(isPlaying: Boolean) {
        if (_sleepTimerMode.value == SleepTimerMode.Off) return
        val r = remaining ?: return
        if (r <= 0) return
        isPaused = false
        scheduleWakeIfNeeded(isPlaying)
    }

    /** Natürlicher Ablauf: Grace-Fenster (60 s) für den intelligenten Restart öffnen. */
    fun markExpired() {
        val mode = _sleepTimerMode.value
        val seconds = remaining
        remaining = null
        isPaused = false
        setSleepEndDate(null)
        chapterTarget = null
        _sleepTimerMode.value = SleepTimerMode.Off
        if (mode is SleepTimerMode.Minutes && (seconds ?: 0.0) > 0) {
            lastExpiredDate = clockMillis()
        } else {
            lastExpiredMode = null
            lastExpiredSeconds = null
            lastExpiredDate = null
        }
    }

    /**
     * Intelligenter Restart: Wiedergabe startet innerhalb von 60 s nach natürlichem Ablauf →
     * Timer mit derselben Dauer (`Minutes`) neu starten. `true`, wenn wiederhergestellt.
     */
    fun restoreIfWithinGrace(isPlaying: Boolean): Boolean {
        val expired = lastExpiredDate ?: return false
        if (clockMillis() - expired > GRACE_SECONDS * 1000) return false
        val mode = lastExpiredMode as? SleepTimerMode.Minutes ?: return false
        val seconds = lastExpiredSeconds ?: return false
        if (seconds <= 0 || mode.minutes <= 0) return false
        _sleepTimerMode.value = SleepTimerMode.Minutes(mode.minutes)
        applyRemaining(seconds, isPlaying)
        lastExpiredDate = null
        return true
    }

    /** Countdown für die UI (Sekunden) — bei Pause konstant; Kapitel-Timer → `null`. */
    fun displaySeconds(): Double? {
        if (_sleepTimerMode.value == SleepTimerMode.Off) return null
        if (isPaused) return remaining
        _sleepEndDate.value?.let { return max(0.0, (it - clockMillis()) / 1000.0) }
        remaining?.let { if (it > 0) return it }
        return null
    }

    val isActive: Boolean
        get() {
            if (_sleepTimerMode.value == SleepTimerMode.Off) return false
            if (chapterTarget != null) return true
            return (displaySeconds() ?: 0.0) > 0
        }

    /** Minuten-Timer abgelaufen (Tick / Wake)? */
    fun isWallClockExpired(): Boolean {
        val end = _sleepEndDate.value ?: return false
        return clockMillis() >= end
    }

    /**
     * iOS: `reconcileSleepTimerAfterBackground` — `true`, wenn der Timer im Hintergrund abgelaufen ist
     * und die Wiedergabe jetzt pausiert werden muss.
     */
    fun reconcileAfterBackground(isPlaying: Boolean): Boolean {
        if (_sleepTimerMode.value == SleepTimerMode.Off) return false
        if (chapterTarget != null) return false
        val r = remaining
        if (isPaused && r != null) {
            if (r <= 0) {
                markExpired()
                return true
            }
            resumeIfNeeded(isPlaying)
            return false
        }
        if (isWallClockExpired()) {
            markExpired()
            return true
        }
        return false
    }

    /**
     * Echtzeit bis zum Stopp; `null` ohne aktiven Timer oder bei Pause. Kapitel-Timer: Medienzeit bis
     * Kapitelende, umgerechnet über die Wiedergabegeschwindigkeit.
     */
    fun secondsUntilStop(isPlaying: Boolean, chapterEnd: Double?, position: Double, playbackRate: Float): Double? {
        if (!isPlaying) return null
        _sleepEndDate.value?.let { return (it - clockMillis()) / 1000.0 }
        if (chapterTarget != null && chapterEnd != null) {
            return (chapterEnd - position) / max(0.1, playbackRate.toDouble())
        }
        return null
    }

    companion object {
        /** Restart-Fenster nach natürlichem Ablauf. */
        const val GRACE_SECONDS = 60L
        /** Ausblenden vor dem Stopp statt abrupt abzuschneiden. */
        const val FADE_SECONDS = 15.0

        /** Lautstärke in den letzten [FADE_SECONDS] linear auf 0 — sonst 1. */
        fun fadeVolume(secondsUntilStop: Double?): Float {
            if (secondsUntilStop == null || secondsUntilStop >= FADE_SECONDS) return 1f
            return max(0.0, secondsUntilStop / FADE_SECONDS).toFloat()
        }
    }
}
