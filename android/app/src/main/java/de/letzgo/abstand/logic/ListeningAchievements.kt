package de.letzgo.abstand.logic

import de.letzgo.abstand.data.AbsListeningStatsResponse
import kotlinx.serialization.Serializable
import java.time.LocalDate

/** iOS: `ListeningAchievementTier` (Level 1–5). */
enum class ListeningAchievementTier(val rawValue: Int) {
    LOCKED(0), LEVEL1(1), LEVEL2(2), LEVEL3(3), LEVEL4(4), LEVEL5(5);

    val levelNumber: Int? get() = if (this == LOCKED) null else rawValue

    val accessibilityLabel: String
        get() = when (this) {
            LOCKED -> "Not unlocked"
            LEVEL1 -> "Level 1"
            LEVEL2 -> "Level 2"
            LEVEL3 -> "Level 3"
            LEVEL4 -> "Level 4"
            LEVEL5 -> "Maximum level"
        }

    /** Deckkraft, mit der die Akzentfarbe getönt wird (`adaptiveTint`); `null` = Akzent pur, LOCKED nutzt `textSecondary` 0.45. */
    fun adaptiveTintOpacity(isDarkLike: Boolean): Double = when (this) {
        LOCKED -> 0.45
        LEVEL1 -> if (isDarkLike) 0.48 else 0.38
        LEVEL2 -> if (isDarkLike) 0.60 else 0.52
        LEVEL3 -> if (isDarkLike) 0.74 else 0.68
        LEVEL4 -> if (isDarkLike) 0.88 else 0.84
        LEVEL5 -> 1.0
    }

    /** Deckung der Badge-Fläche: je höher das Level, desto deckender. */
    fun badgeFillOpacity(isDarkLike: Boolean): Double = when (this) {
        LOCKED -> if (isDarkLike) 0.10 else 0.08
        LEVEL1 -> if (isDarkLike) 0.14 else 0.12
        LEVEL2 -> if (isDarkLike) 0.26 else 0.22
        LEVEL3 -> if (isDarkLike) 0.42 else 0.36
        LEVEL4 -> if (isDarkLike) 0.70 else 0.62
        LEVEL5 -> 1.0
    }

    /** Ab Level 4 ist das Badge flächig gefüllt. */
    val usesSolidBadgeFill: Boolean get() = this == LEVEL4 || this == LEVEL5

    companion object {
        fun fromRaw(raw: Int): ListeningAchievementTier? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** iOS: `ListeningAchievementKind` — Raw-Values identisch (Disk-Cache). */
@Serializable
enum class ListeningAchievementKind(val rawValue: String) {
    listeningTimeHours("listeningTimeHours"),
    activeDays("activeDays"),
    longestStreak("longestStreak"),
    currentStreak("currentStreak"),
    marathonDay("marathonDay"),
    finishedBooks("finishedBooks"),
    finishedEpisodes("finishedEpisodes"),
    libraryDepthAuthors("libraryDepthAuthors");

    val id: String get() = rawValue

    val title: String
        get() = when (this) {
            longestStreak -> "Longest streak"
            currentStreak -> "Current streak"
            listeningTimeHours -> "Listening time"
            activeDays -> "Active days"
            marathonDay -> "Marathon day"
            finishedBooks -> "Finished books"
            finishedEpisodes -> "Finished episodes"
            libraryDepthAuthors -> "Authors listened"
        }

    /** SF-Symbol-Name (Mapping in `ui/Icons.kt`). */
    val systemImage: String
        get() = when (this) {
            longestStreak -> "flame.fill"
            currentStreak -> "bolt.fill"
            listeningTimeHours -> "headphones.circle.fill"
            activeDays -> "calendar"
            marathonDay -> "sun.max.fill"
            finishedBooks -> "book.fill"
            finishedEpisodes -> "mic.fill"
            libraryDepthAuthors -> "person.2.fill"
        }

    /** Schwellen je Level 1–5 in der Einheit von `currentValue`. */
    val thresholds: List<Int>
        get() = when (this) {
            longestStreak -> listOf(50, 100, 250, 400, 600)
            currentStreak -> listOf(3, 7, 14, 30, 90)
            listeningTimeHours -> listOf(100, 250, 500, 1000, 2500)
            activeDays -> listOf(50, 250, 500, 750, 1000)
            marathonDay -> listOf(3_600, 7_200, 14_400, 21_600, 28_800)
            finishedBooks -> listOf(25, 50, 100, 250, 400)
            finishedEpisodes -> listOf(25, 50, 100, 250, 400)
            libraryDepthAuthors -> listOf(10, 25, 50, 100, 200)
        }

    private fun achievedCount(value: Int): Int = thresholds.count { value >= it }

    fun tier(value: Int): ListeningAchievementTier {
        val count = achievedCount(value)
        if (count <= 0) return ListeningAchievementTier.LOCKED
        return ListeningAchievementTier.fromRaw(minOf(count, ListeningAchievementTier.LEVEL5.rawValue)) ?: ListeningAchievementTier.LEVEL5
    }

    fun nextThreshold(after: Int): Int? = thresholds.firstOrNull { after < it }

    fun progressFraction(toward: Int): Double {
        val t = thresholds
        if (t.isEmpty()) return 0.0
        val achieved = achievedCount(toward)
        if (achieved >= t.size) return 1.0
        if (achieved == 0) {
            val goal = t[0].toDouble()
            if (goal <= 0) return 0.0
            return minOf(1.0, maxOf(0.0, toward / goal))
        }
        val span = (t[achieved] - t[achieved - 1]).toDouble()
        if (span <= 0) return 1.0
        return minOf(1.0, maxOf(0.0, (toward - t[achieved - 1]) / span))
    }

    fun formattedValue(value: Int): String = when (this) {
        listeningTimeHours -> "$value h"
        marathonDay -> formatMarathonDaySeconds(value)
        else -> "$value"
    }

    fun formattedThreshold(threshold: Int): String = when (this) {
        listeningTimeHours -> "$threshold h"
        marathonDay -> formatMarathonDaySeconds(threshold)
        else -> "$threshold"
    }

    val explanation: String
        get() = when (this) {
            listeningTimeHours -> "Total listening time on this account (hours)."
            longestStreak -> "Longest run of consecutive calendar days with any listening."
            currentStreak -> "Your current streak of consecutive days with listening."
            activeDays -> "Total number of calendar days on which you listened."
            marathonDay -> "Most listening time on a single calendar day."
            finishedBooks -> "Audiobooks marked as finished."
            finishedEpisodes -> "Podcast episodes marked as finished."
            libraryDepthAuthors -> "Distinct authors you have listened to."
        }

    private val thresholdsDescription: String
        get() = thresholds.mapIndexed { index, threshold -> "Level ${index + 1}: ${formattedThreshold(threshold)}" }.joinToString("\n")

    fun alertMessage(state: ListeningAchievementState): String {
        val progress = when (state.tier) {
            ListeningAchievementTier.LOCKED -> "Not unlocked yet. ${formattedValue(state.currentValue)}"
            ListeningAchievementTier.LEVEL5 -> formattedValue(state.currentValue)
            else -> "${state.tier.accessibilityLabel}. ${state.valueLine}"
        }
        return "$explanation\n\n$thresholdsDescription\n\n$progress"
    }

    companion object {
        /** Reihenfolge der Level-Ansicht (Deklarationsreihenfolge = iOS `allCases`). */
        fun sortedForDisplay(achievements: List<ListeningAchievementState>): List<ListeningAchievementState> =
            entries.mapNotNull { kind -> achievements.firstOrNull { it.kind == kind } }

        fun fromRaw(raw: String): ListeningAchievementKind? = entries.firstOrNull { it.rawValue == raw }

        private fun formatMarathonDaySeconds(seconds: Int): String {
            val h = seconds / 3600
            val m = (seconds % 3600) / 60
            if (h > 0 && m > 0) return "$h h $m m"
            if (h > 0) return "$h h"
            if (m > 0) return "$m m"
            return "0 m"
        }
    }
}

/** iOS: `ListeningAchievementState`. */
@Serializable
data class ListeningAchievementState(val kind: ListeningAchievementKind, val currentValue: Int) {
    val id: String get() = kind.id
    val tier: ListeningAchievementTier get() = kind.tier(currentValue)
    val nextThreshold: Int? get() = kind.nextThreshold(currentValue)
    val progressToNext: Double get() = kind.progressFraction(currentValue)

    val valueLine: String
        get() {
            val next = nextThreshold ?: return kind.formattedValue(currentValue)
            return "${kind.formattedValue(currentValue)} / ${kind.formattedThreshold(next)}"
        }
}

/** iOS: `ListeningAchievementsSnapshot` (Disk-Cache; `savedAt` in Millisekunden). */
@Serializable
data class ListeningAchievementsSnapshot(
    val achievements: List<ListeningAchievementState>,
    val savedAt: Long? = null,
) {
    companion object {
        val empty = ListeningAchievementsSnapshot(ListeningAchievementKind.entries.map { ListeningAchievementState(it, 0) }, null)

        fun make(
            stats: AbsListeningStatsResponse,
            finishedBooks: Int,
            finishedEpisodes: Int,
            today: LocalDate = LocalDate.now(),
            nowMillis: Long = System.currentTimeMillis(),
        ): ListeningAchievementsSnapshot {
            val values = mapOf(
                ListeningAchievementKind.longestStreak to stats.bestListeningStreakDays(),
                ListeningAchievementKind.currentStreak to stats.currentListeningStreakDays(today),
                ListeningAchievementKind.listeningTimeHours to maxOf(0, stats.totalTime / 3600),
                ListeningAchievementKind.activeDays to stats.daysActive,
                ListeningAchievementKind.marathonDay to stats.marathonDayListeningSeconds,
                ListeningAchievementKind.finishedBooks to finishedBooks,
                ListeningAchievementKind.finishedEpisodes to finishedEpisodes,
                ListeningAchievementKind.libraryDepthAuthors to stats.distinctListenedAuthorCount,
            )
            return ListeningAchievementsSnapshot(
                ListeningAchievementKind.entries.map { ListeningAchievementState(it, values[it] ?: 0) },
                nowMillis,
            )
        }
    }
}
