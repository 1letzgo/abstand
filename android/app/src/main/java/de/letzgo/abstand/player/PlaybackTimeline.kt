package de.letzgo.abstand.player

import de.letzgo.abstand.data.AbsAudioTrack
import de.letzgo.abstand.data.AbsChapter
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// iOS: PlaybackController.swift — reine Zeit-/Kapitel-/Hörzeit-Logik, ohne Player (JUnit-testbar).

/**
 * iOS: `PlaybackController.tracks` + `trackStarts` (`rebuildTrackStarts`, `trackIndex(forGlobal:)`,
 * `globalTime(trackIndex:localSeconds:)`). Mehrspurige Hörbücher laufen als eine globale Zeitachse;
 * ExoPlayer spielt die Spuren als Playlist, die globale Position ist `trackStarts[i] + lokal`.
 */
class TrackTimeline(tracks: List<AbsAudioTrack>) {
    /** Nach `index` sortiert (wie iOS `sorted { $0.index < $1.index }`). */
    val tracks: List<AbsAudioTrack> = tracks.sortedBy { it.index }
    val trackStarts: List<Double> = rebuildTrackStarts(this.tracks)

    val isEmpty: Boolean get() = tracks.isEmpty()

    /** Letzter Track, dessen Start ≤ `g` (vor dem ersten Start → 0). */
    fun trackIndex(forGlobal: Double): Int {
        if (trackStarts.isEmpty()) return 0
        for (i in trackStarts.indices.reversed()) {
            if (forGlobal >= trackStarts[i]) return i
        }
        return 0
    }

    fun globalTime(trackIndex: Int, localSeconds: Double): Double {
        if (trackIndex !in trackStarts.indices) return localSeconds
        return trackStarts[trackIndex] + localSeconds
    }

    /** Offset innerhalb des Tracks, in dem `global` liegt (nie negativ). */
    fun offsetInTrack(global: Double): Double {
        val idx = trackIndex(global)
        if (idx !in trackStarts.indices) return max(0.0, global)
        return max(0.0, global - trackStarts[idx])
    }

    /** Fallback-Gesamtdauer: Start + Dauer des letzten Tracks (iOS: `trackStarts.last! + tracks.last!.duration`). */
    val summedDuration: Double
        get() = if (tracks.isEmpty()) 0.0 else trackStarts.last() + tracks.last().duration

    companion object {
        val EMPTY = TrackTimeline(emptyList())

        /** Globale Startzeiten: Server-`startOffset`, falls plausibel (monoton); sonst aus Dauern kumulieren. */
        fun rebuildTrackStarts(tracks: List<AbsAudioTrack>): List<Double> {
            if (tracks.isEmpty()) return emptyList()
            val offsets = tracks.map { it.startOffset }
            val allOffsetsZero = offsets.all { it == 0.0 }
            val monotonic = offsets.zipWithNext().all { (a, b) -> b + 0.001 >= a }
            if (tracks.size > 1 && (allOffsetsZero || !monotonic)) {
                var t = 0.0
                return tracks.map { tr -> t.also { t += tr.duration } }
            }
            return offsets
        }
    }
}

/**
 * iOS: `PlaybackController.sortedChapters` mit `chapterIndex(for:)`, `chapterEndTime(at:)`,
 * `chapterMarkerFractions`, `currentChapterProgress`, Kapitel-Sprüngen und Sleep-Kapitelzählung.
 */
class ChapterTimeline(chapters: List<AbsChapter>) {
    val sortedChapters: List<AbsChapter> = chapters.sortedBy { it.start }
    val count: Int get() = sortedChapters.size
    val isEmpty: Boolean get() = sortedChapters.isEmpty()

    /** Index des Kapitels, in dem `global` liegt; `null` ohne Kapitel. */
    fun chapterIndex(global: Double): Int? {
        if (sortedChapters.isEmpty()) return null
        var idx = 0
        sortedChapters.forEachIndexed { i, ch -> if (global >= ch.start) idx = i }
        return idx
    }

    /** Kapitelende: Start des nächsten Kapitels (nicht `chapter.end`, falls der die Buchlänge trägt). */
    fun chapterEndTime(index: Int, totalDuration: Double): Double {
        val ch = sortedChapters[index]
        if (index + 1 < sortedChapters.size) {
            val nextStart = sortedChapters[index + 1].start
            if (ch.end > ch.start + 0.5 && ch.end <= nextStart + 0.5) return ch.end
            return nextStart
        }
        // Letztes Kapitel reicht bis zum Buchende — auch wenn der Server eine unvollständige
        // Kapitelliste liefert, die vor dem Buchende aufhört (sonst „Kapitel voll, 0:00“).
        val bookEnd = if (totalDuration > 0) totalDuration else ch.end
        return max(bookEnd, ch.start + 1)
    }

    /** iOS: `currentChapterProgress(global:)` — (Position im Kapitel, Kapiteldauer, Kapitelstart). */
    fun chapterProgress(global: Double, totalDuration: Double): ChapterProgress? {
        val idx = chapterIndex(global) ?: return null
        val start = sortedChapters[idx].start
        val end = chapterEndTime(idx, totalDuration)
        val duration = max(end - start, 0.001)
        val position = min(max(global - start, 0.0), duration)
        return ChapterProgress(position, duration, start)
    }

    /** Relative Kapitelgrenzen (0…1) für Markierungen im Fortschrittsbalken; ohne Start bei 0. */
    fun chapterMarkerFractions(totalDuration: Double): List<Double> {
        if (totalDuration <= 0 || sortedChapters.size <= 1) return emptyList()
        val minGap = max(2.0, totalDuration * 0.005)
        return sortedChapters.drop(1).map { it.start }
            .filter { it >= minGap && it <= totalDuration - minGap }
            .map { min(1.0, max(0.0, it / totalDuration)) }
    }

    /** iOS: `skipToPreviousChapter` — Ziel: Kapitelanfang, innerhalb von 1,5 s das vorherige Kapitel. */
    fun previousChapterTarget(global: Double): Double? {
        val idx = chapterIndex(global) ?: return null
        val start = sortedChapters[idx].start
        return when {
            global > start + 1.5 -> start
            idx > 0 -> sortedChapters[idx - 1].start
            else -> 0.0
        }
    }

    /** iOS: `skipToNextChapter` — Anfang des nächsten Kapitels; `null` im letzten Kapitel. */
    fun nextChapterTarget(global: Double): Double? {
        val idx = chapterIndex(global) ?: return null
        if (idx + 1 >= sortedChapters.size) return null
        return sortedChapters[idx + 1].start
    }

    fun canSkipToPreviousChapter(global: Double): Boolean {
        val idx = chapterIndex(global) ?: return false
        return idx > 0 || global > sortedChapters[idx].start + 1.5
    }

    fun canSkipToNextChapter(global: Double): Boolean {
        val idx = chapterIndex(global) ?: return false
        return idx + 1 < sortedChapters.size
    }

    /** Ziel-Kapitelindex (0-basiert) für den Kapitel-Sleep-Timer; `count == 1` = aktuelles Kapitel. */
    fun chapterTargetIndex(forCount: Int, global: Double): Int? {
        if (forCount < 1) return null
        val idx = chapterIndex(global) ?: return null
        val target = idx + forCount - 1
        return if (target < sortedChapters.size) target else null
    }

    /** Wie viele Kapitel im Sleep-Menü wählbar sind (laufendes = 1, bis zum letzten Kapitel). */
    fun maxSleepChapterCount(global: Double): Int {
        val idx = chapterIndex(global) ?: return 0
        return max(1, sortedChapters.size - idx)
    }

    data class ChapterProgress(val position: Double, val duration: Double, val start: Double)

    companion object {
        val EMPTY = ChapterTimeline(emptyList())

        /**
         * iOS: `applyChapters(from:sessionChapters:libraryItemFallback:manifestChapters:)` — die Play-Session
         * liefert oft `chapters: []`; `??` allein würde die eingebetteten Item-Kapitel verwerfen.
         * Reihenfolge: Session → Manifest → Buch → Fallback-Item.
         */
        fun select(
            sessionChapters: List<AbsChapter>?,
            manifestChapters: List<AbsChapter>?,
            bookChapters: List<AbsChapter>?,
            fallbackChapters: List<AbsChapter>?,
        ): List<AbsChapter> = listOf(sessionChapters, manifestChapters, bookChapters, fallbackChapters)
            .firstOrNull { !it.isNullOrEmpty() }.orEmpty()
    }
}

/**
 * iOS: `pendingListenSeconds` + `lastListenTick` + `accumulateListenTime()` — Hörzeit läuft nur,
 * solange `isPlaying`; ganze Sekunden gehen an den Server, der Rest bleibt stehen.
 */
class ListenTimeAccumulator(private val clockMillis: () -> Long = System::currentTimeMillis) {
    var pendingListenSeconds: Double = 0.0
        private set
    private var lastListenTick: Long = clockMillis()

    fun accumulate(isPlaying: Boolean) {
        val now = clockMillis()
        if (isPlaying) pendingListenSeconds += (now - lastListenTick).coerceAtLeast(0) / 1000.0
        lastListenTick = now
    }

    /** iOS: `lastListenTick = Date()` (Start/Resume — Pausenzeit nicht mitzählen). */
    fun resetTick() {
        lastListenTick = clockMillis()
    }

    /** Ganze Sekunden entnehmen, Bruchteil bleibt (iOS: `Int(floor(raw))`, `raw - tl`). */
    fun takeWholeSeconds(): Int {
        val tl = floor(pendingListenSeconds).toInt()
        pendingListenSeconds = max(0.0, pendingListenSeconds - tl)
        return max(0, tl)
    }

    /** Fehlgeschlagener Sync: entnommene Sekunden zurücklegen. */
    fun restore(seconds: Int) {
        pendingListenSeconds += seconds
    }

    fun reset() {
        pendingListenSeconds = 0.0
        lastListenTick = clockMillis()
    }
}

/** iOS: Entscheidungslogik am Anfang von `PlaybackController.flushSync(force:)`. */
sealed class SyncPlan {
    /** Nichts senden. */
    data object Skip : SyncPlan()
    /** `POST /api/session/:id/sync` mit `timeListened`. */
    data class SessionSync(val timeListened: Int) : SyncPlan()
    /** Lokale Datei ohne Session: AppModel-Callback (PATCH oder Offline-Hörzeit). */
    data class LocalWithoutSession(val timeListened: Int) : SyncPlan()

    companion object {
        /** Periodischer Sync alle 20 s (iOS: `startPeriodicSync`). */
        const val PERIODIC_SYNC_INTERVAL_MS = 20_000L

        fun decide(pendingSeconds: Double, force: Boolean, hasSession: Boolean, isLocalPlayback: Boolean): SyncPlan {
            val tl = floor(pendingSeconds).toInt()
            if (!force && tl < 1 && hasSession) return Skip
            if (hasSession) {
                if (tl < 1 && !force) return Skip
                return SessionSync(max(0, tl))
            }
            if (!isLocalPlayback || !(tl > 0 || force)) return Skip
            return LocalWithoutSession(max(0, tl))
        }
    }
}

/** iOS: `PlaybackController.playbackRatePresets` / `setPlaybackRate` (auf nächstes Preset einrasten). */
object PlaybackRates {
    val presets: List<Float> = listOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f)

    fun snapped(rate: Float): Float = presets.minByOrNull { kotlin.math.abs(it - rate) } ?: 1.0f

    /** iOS: `loadSavedPlaybackRate` — `≤ 0.09` (nicht gesetzt) → 1×. */
    fun fromSaved(value: Double): Float = if (value > 0.09) snapped(value.toFloat()) else 1.0f

    /** CarPlay-/Auto-Knopf: nächstes Preset zyklisch (iOS: `CarPlayCoordinator.advancePlaybackRate`). */
    fun next(current: Float): Float = presets.firstOrNull { it > current + 0.01f } ?: presets.first()
}

/** iOS: `ABSPlaybackSkipDefaults` — nur Werte mit SF-Symbolen `gobackward.N` / `goforward.N`. */
object PlaybackSkipDefaults {
    val intervalOptions: List<Int> = listOf(5, 10, 15, 30, 45, 60)
    const val backwardSeconds = 15
    const val forwardSeconds = 30

    fun clamped(value: Int, fallback: Int): Int = if (value in intervalOptions) value else fallback

    /** iOS: `skipAccessibilityLabel(backward:seconds:)`. */
    fun accessibilityLabel(backward: Boolean, seconds: Int): String =
        if (backward) "Back $seconds seconds" else "Forward $seconds seconds"
}
