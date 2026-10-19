package de.letzgo.abstand.ui.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.abstand.data.AbsListeningMonthHeatmap
import de.letzgo.abstand.data.AbsListeningStatsResponse
import de.letzgo.abstand.logic.StatsLogic
import de.letzgo.abstand.logic.StatsLogic.HeatmapMetrics
import de.letzgo.abstand.ui.AppColorPalette
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.bold
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.abstandCardListRowFrame
import java.time.LocalDate
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandCapsLabel

/**
 * iOS: `ListeningMonthHeatmapCard` — Monatskalender (Montag zuerst, en_US) mit Vor/Zurück,
 * antippbaren Tagen und der „Listening time“-Karte daneben (breit) bzw. darunter (Telefon).
 */
@Composable
fun ListeningMonthHeatmapCard(stats: AbsListeningStatsResponse, modifier: Modifier = Modifier) {
    var monthsBack by rememberSaveable { mutableIntStateOf(0) }
    var selectedDayKey by rememberSaveable { mutableStateOf<String?>(null) }
    val today = remember { LocalDate.now() }
    val earliest = remember(stats) { stats.earliestListeningMonthStart() }
    val monthStart = StatsLogic.displayedMonthStart(monthsBack, today)
    val heatmap = remember(stats, monthStart) {
        stats.monthListeningHeatmap(monthStart, StatsLogic.statsLocale, StatsLogic.STATS_FIRST_WEEKDAY)
    }
    // iOS: `syncSelectedDay` beim Monatswechsel.
    val selected = StatsLogic.validatedSelectedDay(heatmap, selectedDayKey)
    val isRegular = LocalConfiguration.current.screenWidthDp >= RegularWidthDp

    val calendar: @Composable (Modifier) -> Unit = { m ->
        CalendarCard(
            heatmap = heatmap,
            selectedDayKey = selected,
            canGoBack = StatsLogic.canGoBack(monthsBack, earliest, today),
            canGoForward = StatsLogic.canGoForward(monthsBack),
            onBack = { monthsBack += 1 },
            onForward = { monthsBack -= 1 },
            onToday = { monthsBack = 0; selectedDayKey = null },
            onSelectDay = { key -> selectedDayKey = if (selectedDayKey == key) null else key },
            modifier = m,
        )
    }
    val summary = StatsLogic.listeningSummary(heatmap, selected)
    if (isRegular) {
        Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing), verticalAlignment = Alignment.Top) {
            calendar(Modifier.width(HeatmapMetrics.CALENDAR_CARD_MAX_WIDTH_REGULAR.dp))
            StatsTimelineMetricCard(summary.title, summary.value, summary.accessibility, Modifier.weight(1f))
        }
    } else {
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
            calendar(Modifier.fillMaxWidth())
            StatsTimelineMetricCard(summary.title, summary.value, summary.accessibility)
        }
    }
}

@Composable
private fun CalendarCard(
    heatmap: AbsListeningMonthHeatmap,
    selectedDayKey: String?,
    canGoBack: Boolean,
    canGoForward: Boolean,
    onBack: () -> Unit,
    onForward: () -> Unit,
    onToday: () -> Unit,
    onSelectDay: (String) -> Unit,
    modifier: Modifier,
) {
    val palette = Theme.palette
    val accent = Theme.accent
    // Kein Karteninnenabstand — der Heatmap-Inhalt bringt sein eigenes Padding mit.
    AbstandGroupedCard(modifier, horizontalPadding = 0.dp, verticalPadding = 0.dp) {
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val layout = StatsLogic.monthHeatmapLayout(
                columnCount = heatmap.columnCount,
                rowCount = heatmap.rowCount,
                containerWidth = maxWidth.value.toDouble(),
                cardPaddingH = AppTheme.Layout.settingsCardInsetHPadding.value.toDouble(),
            )
            val block = layout.blockSize.dp
            val colGap = layout.columnGap.dp
            Column(
                Modifier
                    .fillMaxWidth()
                    .height(layout.calendarCardHeight.dp)
                    .padding(horizontal = AppTheme.Layout.settingsCardInsetHPadding, vertical = HeatmapMetrics.CARD_PADDING_V.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(HeatmapMetrics.BODY_SPACING.dp),
            ) {
                // Monatsnavigation.
                Row(Modifier.fillMaxWidth().height(HeatmapMetrics.NAV_ROW_HEIGHT.dp), verticalAlignment = Alignment.CenterVertically) {
                    NavButton(SF.chevronLeft, "Previous month", canGoBack, onBack)
                    val titleModifier = Modifier.weight(1f).let { m ->
                        if (canGoForward) m.clickable(onClick = onToday).semantics { contentDescription = heatmap.monthTitle }
                        else m.semantics { heading() }
                    }
                    Text(
                        heatmap.monthTitle, style = AppType.titleLarge, color = palette.textPrimary,
                        maxLines = 1, textAlign = TextAlign.Center, modifier = titleModifier,
                    )
                    NavButton(SF.chevronRight, "Next month", canGoForward, onForward)
                }
                // Wochentage (Montag zuerst).
                Row(Modifier.width(layout.gridWidth.dp), horizontalArrangement = Arrangement.spacedBy(colGap)) {
                    (0 until 7).forEach { col ->
                        Text(
                            layout.weekdayLabel(col), style = AppType.labelSmall, color = palette.textSecondary,
                            textAlign = TextAlign.Center, maxLines = 1,
                            modifier = Modifier.width(block).height(HeatmapMetrics.WEEKDAY_HEADER_HEIGHT.dp),
                        )
                    }
                }
                // Raster.
                Column(Modifier.width(layout.gridWidth.dp), verticalArrangement = Arrangement.spacedBy(layout.rowGap.dp)) {
                    (0 until heatmap.rowCount).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(colGap)) {
                            (0 until 7).forEach { col ->
                                val cell = heatmap.cell(col, row)
                                DayCell(cell, block.value, cell?.id == selectedDayKey, palette, accent, onSelectDay)
                            }
                        }
                    }
                }
                HeatmapLegend(layout.blockSize, palette, accent)
            }
        }
    }
}

@Composable
private fun NavButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    val palette = Theme.palette
    AbstandIconButton(
        icon,
        label,
        onClick = onClick,
        enabled = enabled,
        size = AppTheme.Layout.compactIconButtonSize,
        tint = if (enabled) palette.textPrimary else palette.textPrimary.copy(alpha = AppTheme.disabledContentAlpha),
    )
}

@Composable
private fun DayCell(
    cell: AbsListeningMonthHeatmap.Cell?,
    blockSize: Float,
    isSelected: Boolean,
    palette: AppColorPalette,
    accent: Color,
    onSelect: (String) -> Unit,
) {
    val level = cell?.colorLevel ?: 0
    val inMonth = cell?.isInDisplayedMonth ?: false
    val day = cell?.day ?: 0
    val shownLevel = if (inMonth) level else 0
    val dayFont = maxOf(8f, blockSize * 0.38f)
    var m = Modifier
        .size(blockSize.dp)
        .alpha(if (inMonth) 1f else OutOfMonthAlpha)
        .background(HeatmapColors.fill(shownLevel, palette, accent), CircleShape)
        .border(AppTheme.Layout.hairlineWidth, HeatmapColors.outline(shownLevel, palette, accent), CircleShape)
    if (isSelected) m = m.border(AppTheme.Layout.boldStrokeWidth, accent, CircleShape)
    if (cell != null && cell.isInDisplayedMonth) {
        m = m.clickable { onSelect(cell.id) }.semantics {
            contentDescription = cell.accessibilityLabel
            selected = isSelected
        }
    } else {
        m = m.semantics { contentDescription = cell?.accessibilityLabel ?: "No data" }
    }
    Box(m, contentAlignment = Alignment.Center) {
        if (day > 0) {
            Text(
                "$day",
                fontSize = dayFont.sp,
                fontWeight = FontWeight.Medium,
                fontFamily = FontFamily.Default,
                color = HeatmapColors.dayNumber(level, inMonth, isSelected, palette, accent),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun HeatmapLegend(blockSize: Double, palette: AppColorPalette, accent: Color) {
    val dot = minOf(9.0, maxOf(5.0, blockSize * 0.45)).dp
    Row(
        Modifier.fillMaxWidth().padding(top = HeatmapMetrics.LEGEND_TOP_PADDING.dp),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Less", style = AppType.labelSmall, color = palette.textSecondary)
        (0 until 5).forEach { level ->
            Box(
                Modifier.size(dot)
                    .background(HeatmapColors.fill(level, palette, accent), CircleShape)
                    .border(AppTheme.Layout.hairlineWidth, HeatmapColors.outline(level, palette, accent), CircleShape),
            )
        }
        Text("More", style = AppType.labelSmall, color = palette.textSecondary)
    }
}

/** iOS: `heatmapFill` / `heatmapOutline` / `dayNumberColor`. */
object HeatmapColors {
    fun fill(level: Int, palette: AppColorPalette, accent: Color): Color = when (level) {
        0 -> palette.background
        1 -> accent.copy(alpha = if (palette.isDarkLike) 0.28f else 0.22f)
        2 -> accent.copy(alpha = if (palette.isDarkLike) 0.48f else 0.42f)
        3 -> accent.copy(alpha = if (palette.isDarkLike) 0.72f else 0.66f)
        else -> accent
    }

    fun outline(level: Int, palette: AppColorPalette, accent: Color): Color =
        if (level == 0) palette.textSecondary.copy(alpha = 0.12f) else accent.copy(alpha = if (palette.isDarkLike) 0.35f else 0.5f)

    fun dayNumber(level: Int, inMonth: Boolean, isSelected: Boolean, palette: AppColorPalette, accent: Color): Color = when {
        !inMonth -> palette.textSecondary.copy(alpha = 0.5f)
        isSelected -> accent
        level >= 3 -> palette.foregroundOnAccent(accent)
        else -> palette.textSecondary
    }
}

/** iOS: `StatsTimelineMetricCard` — Titel in Versalien, Wert fett. */
@Composable
fun StatsTimelineMetricCard(title: String, value: String, accessibility: String, modifier: Modifier = Modifier) {
    val palette = Theme.palette
    AbstandGroupedCard(modifier.semantics { contentDescription = accessibility }) {
        Column(Modifier.abstandCardListRowFrame(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing, Alignment.CenterVertically)) {
            AbstandCapsLabel(title, maxLines = 2)
            Text(value, style = AppType.titleMedium.bold, color = palette.textPrimary, maxLines = 1)
        }
    }
}

/** iOS: Tage außerhalb des Monats `.opacity(0.35)`. */
private const val OutOfMonthAlpha = 0.35f
/** iOS `horizontalSizeClass == .regular` ≈ ab 600 dp Breite. */
internal const val RegularWidthDp = 600
