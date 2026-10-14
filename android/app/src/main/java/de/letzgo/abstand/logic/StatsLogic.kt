package de.letzgo.abstand.logic

import de.letzgo.abstand.data.AbsListeningMonthHeatmap
import de.letzgo.abstand.data.formatPlaybackDurationShortHuman
import java.time.LocalDate
import java.util.Locale
import kotlin.math.floor

/**
 * Reine Rechenteile aus iOS `StatsTabView.swift` / `StatsHeatmapViews.swift`. Bucketing, Streaks und
 * Summen der Heatmaps liegen bereits in `data/ModelsStats.kt` (`AbsListeningStatsResponse`); hier
 * folgen Layout-Mathe, Wochentag-Reihenfolge (`firstWeekday`), Monatsnavigation und Zusammenfassung.
 */
object StatsLogic {
    /** iOS: `StatsLayout.statsLocale` — Stats sind bewusst immer en_US mit Montag als Wochenbeginn. */
    val statsLocale: Locale = Locale.US
    const val STATS_FIRST_WEEKDAY = 2

    /** iOS: `SettingsStatsCategory` (Raw-Values = Titel). */
    enum class SettingsStatsCategory(val rawValue: String, val icon: String, val subtitle: String) {
        TOP_LISTENED("Top 10", "list.star", "Most listened titles"),
        SESSIONS("Sessions", "play.circle.fill", "Recent playback sessions");

        val id: String get() = rawValue
    }

    /** iOS: `HeatmapMetrics` (pt → dp). */
    object HeatmapMetrics {
        const val CARD_PADDING_V = 12.0
        const val NAV_ROW_HEIGHT = 36.0
        const val WEEKDAY_HEADER_HEIGHT = 16.0
        const val LEGEND_HEIGHT = 14.0
        const val LEGEND_TOP_PADDING = 8.0
        const val MIN_COLUMN_GAP = 4.0
        const val ROW_GAP = 4.0
        const val DAY_CELL_SCALE = 0.84
        const val BODY_SPACING = 8.0
        const val SUMMARY_SPACING = 4.0
        const val CALENDAR_CARD_MAX_WIDTH_REGULAR = 440.0
        const val FALLBACK_CONTAINER_WIDTH_ESTIMATE = 320.0
        const val FALLBACK_ROW_COUNT_ESTIMATE = 6
    }

    /** iOS: `MonthHeatmapLayout`. [cardPaddingH] = `AppTheme.Layout.settingsCardInsetHPadding`. */
    data class MonthHeatmapLayout(
        val blockSize: Double,
        val columnGap: Double,
        val rowGap: Double,
        val gridWidth: Double,
        val weekdayLabels: List<String>,
        val calendarCardHeight: Double,
    ) {
        /** Zweibuchstabiges Kürzel der Spalte. */
        fun weekdayLabel(column: Int): String {
            if (column < 0 || column >= weekdayLabels.size) return ""
            return weekdayLabels[column].take(2)
        }
    }

    fun monthHeatmapLayout(
        columnCount: Int,
        rowCount: Int,
        containerWidth: Double,
        cardPaddingH: Double,
        firstWeekday: Int = STATS_FIRST_WEEKDAY,
        shortWeekdaySymbols: List<String> = shortWeekdaySymbols(statsLocale),
    ): MonthHeatmapLayout {
        val contentWidth = maxOf(0.0, containerWidth - 2 * cardPaddingH)
        val n = columnCount.toDouble()
        val minGap = HeatmapMetrics.MIN_COLUMN_GAP
        val rawBlock = maxOf(24.0, (contentWidth - (n - 1) * minGap) / n)
        val block = floor(rawBlock * HeatmapMetrics.DAY_CELL_SCALE)
        val used = n * block
        val columnGap = if (n > 1) maxOf(minGap, (contentWidth - used) / (n - 1)) else 0.0
        val rowGap = HeatmapMetrics.ROW_GAP
        val gridWidth = n * block + maxOf(0.0, n - 1) * columnGap
        return MonthHeatmapLayout(
            blockSize = block,
            columnGap = columnGap,
            rowGap = rowGap,
            gridWidth = gridWidth,
            weekdayLabels = orderedWeekdaySymbols(firstWeekday, shortWeekdaySymbols),
            calendarCardHeight = cardHeightForBlock(block, maxOf(rowCount, 1), rowGap),
        )
    }

    fun estimatedCalendarCardHeight(containerWidth: Double, rowCount: Int, cardPaddingH: Double): Double {
        val contentWidth = maxOf(0.0, containerWidth - 2 * cardPaddingH)
        val rawBlock = maxOf(24.0, (contentWidth - 6 * HeatmapMetrics.MIN_COLUMN_GAP) / 7)
        val block = floor(rawBlock * HeatmapMetrics.DAY_CELL_SCALE)
        return cardHeightForBlock(block, rowCount, HeatmapMetrics.ROW_GAP)
    }

    private fun cardHeightForBlock(block: Double, rowCount: Int, rowGap: Double): Double {
        val rows = rowCount.toDouble()
        val gridH = rows * block + maxOf(0.0, rows - 1) * rowGap
        return 2 * HeatmapMetrics.CARD_PADDING_V +
            HeatmapMetrics.NAV_ROW_HEIGHT +
            HeatmapMetrics.BODY_SPACING +
            HeatmapMetrics.WEEKDAY_HEADER_HEIGHT +
            HeatmapMetrics.BODY_SPACING +
            gridH +
            HeatmapMetrics.BODY_SPACING +
            HeatmapMetrics.LEGEND_TOP_PADDING +
            HeatmapMetrics.LEGEND_HEIGHT
    }

    /** Swift `Calendar.shortWeekdaySymbols` (Sonntag zuerst). */
    fun shortWeekdaySymbols(locale: Locale): List<String> {
        val symbols = java.text.DateFormatSymbols.getInstance(locale).shortWeekdays // Index 1 = Sonntag
        val list = (1..7).map { symbols[it] }
        return if (list.size == 7 && list.all { it.isNotEmpty() }) list else listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
    }

    /** Wochentage ab `firstWeekday` (1 = Sonntag, 2 = Montag). */
    fun orderedWeekdaySymbols(firstWeekday: Int, symbols: List<String>): List<String> {
        val all = if (symbols.size == 7) symbols else listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
        val firstIdx = firstWeekday - 1
        return (0 until 7).map { all[((firstIdx + it) % 7 + 7) % 7] }
    }

    /** Monat der Heatmap: `monthsBack` Monate vor dem aktuellen (Monatsanfang). */
    fun displayedMonthStart(monthsBack: Int, today: LocalDate = LocalDate.now()): LocalDate =
        today.withDayOfMonth(1).minusMonths(monthsBack.toLong())

    /** iOS: `maxMonthsBack` — ganze Monate vom frühesten Monat mit Daten bis zum aktuellen. */
    fun maxMonthsBack(earliestMonthStart: LocalDate?, today: LocalDate = LocalDate.now()): Int {
        val earliest = earliestMonthStart ?: return 0
        return maxOf(0, java.time.temporal.ChronoUnit.MONTHS.between(earliest, today.withDayOfMonth(1)).toInt())
    }

    fun canGoBack(monthsBack: Int, earliestMonthStart: LocalDate?, today: LocalDate = LocalDate.now()): Boolean =
        monthsBack < maxMonthsBack(earliestMonthStart, today)

    fun canGoForward(monthsBack: Int): Boolean = monthsBack > 0

    fun listeningTimeLabel(seconds: Int): String =
        if (seconds > 0) formatPlaybackDurationShortHuman(seconds.toDouble()) else "No listening"

    data class ListeningSummary(val title: String, val value: String, val accessibility: String)

    /** Ausgewählter Tag (nur im angezeigten Monat) oder Monatssumme. */
    fun listeningSummary(heatmap: AbsListeningMonthHeatmap, selectedDayKey: String?, locale: Locale = statsLocale): ListeningSummary {
        if (selectedDayKey != null) {
            val cell = heatmap.cells.firstOrNull { it.id == selectedDayKey && it.isInDisplayedMonth }
            if (cell != null) {
                val date = de.letzgo.abstand.data.AbsListeningStatsResponse.parseDayKey(selectedDayKey)
                val title = date?.let { java.time.format.DateTimeFormatter.ofPattern("EEE, MMM d", locale).format(it) } ?: selectedDayKey
                val dateLabel = date?.let {
                    java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM).withLocale(locale).format(it)
                } ?: selectedDayKey
                return ListeningSummary(title, listeningTimeLabel(cell.seconds), "$dateLabel, ${listeningTimeLabel(cell.seconds)}")
            }
        }
        return ListeningSummary(
            "Listening time",
            listeningTimeLabel(heatmap.totalSecondsInMonth),
            "${heatmap.monthTitle}, ${heatmap.daysListenedInMonth} days, ${listeningTimeLabel(heatmap.totalSecondsInMonth)}",
        )
    }

    /** iOS: `syncSelectedDay` — Auswahl bleibt nur, wenn der Tag im angezeigten Monat liegt. */
    fun validatedSelectedDay(heatmap: AbsListeningMonthHeatmap, selectedDayKey: String?): String? =
        selectedDayKey?.takeIf { key -> heatmap.cells.any { it.id == key && it.isInDisplayedMonth } }

    /** Level-Raster: 2 Spalten (Telefon), 4 bei regulärer Breite. */
    fun levelColumnCount(isRegularWidth: Boolean): Int = if (isRegularWidth) 4 else 2
}
