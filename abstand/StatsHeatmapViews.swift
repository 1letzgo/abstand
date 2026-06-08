import SwiftUI

// MARK: - Monats-Kalender-Heatmap

private enum HeatmapMetrics {
  static let cardPaddingH = AppTheme.Layout.settingsCardInsetHPadding
  static let cardPaddingV: CGFloat = 12
  /// Zeile mit Monatsüberschrift und Vor/Zurück.
  static let navRowHeight: CGFloat = 36
  static let weekdayHeaderHeight: CGFloat = 16
  static let legendHeight: CGFloat = 14
  /// Zusatzabstand über der „Less … More“-Legende.
  static let legendTopPadding: CGFloat = 8
  static let minColumnGap: CGFloat = 4
  static let rowGap: CGFloat = 4
  /// Anteil der berechneten Zellbreite für die Tag-Kreise (< 1 = kleinere Kreise, mehr Luft).
  static let dayCellScale: CGFloat = 0.84
  static let bodySpacing: CGFloat = 8
  static let summarySpacing: CGFloat = 4
}

struct ListeningMonthHeatmapCard: View {
  @EnvironmentObject private var model: AppModel
  let stats: ABSListeningStatsResponse
  var locale: Locale = Locale(identifier: "en_US")
  var calendar: Calendar = .current

  private var accent: Color { model.appearanceAccentColor }
  private var palette: AppColorPalette { model.appearancePalette }
  /// Dark: Mint-Grün; Sepia-Light: App-Akzent (Grün auf hellem Papier hat zu wenig Kontrast).
  private var heatmapActiveColor: Color {
    palette.isDarkLike ? AppTheme.success : accent
  }

  @State private var monthsBack: Int = 0
  @State private var cardWidth: CGFloat = 0
  @State private var selectedDayKey: String?

  private var currentMonthStart: Date {
    calendar.startOfMonth(for: Date())
  }

  private var visibleMonthStart: Date {
    calendar.date(byAdding: .month, value: -monthsBack, to: currentMonthStart) ?? currentMonthStart
  }

  private var maxMonthsBack: Int {
    guard let earliest = stats.earliestListeningMonthStart(calendar: calendar) else { return 0 }
    let comps = calendar.dateComponents([.month], from: earliest, to: currentMonthStart)
    return max(0, comps.month ?? 0)
  }

  private var canGoBack: Bool { monthsBack < maxMonthsBack }
  private var canGoForward: Bool { monthsBack > 0 }
  private var monthTitleLinksToCurrentMonth: Bool { monthsBack > 0 }

  var body: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      calendarCard
      listeningTimeCard
    }
    .onChange(of: monthsBack) { _, _ in
      let heatmap = stats.monthListeningHeatmap(
        forMonthContaining: visibleMonthStart,
        calendar: calendar,
        locale: locale
      )
      syncSelectedDay(for: heatmap)
    }
  }

  private var calendarCard: some View {
    Group {
      if cardWidth > 1 {
        calendarHeatmapContent(cardWidth: cardWidth)
      } else {
        Color.clear
          .frame(height: MonthHeatmapLayout.estimatedCalendarCardHeight(containerWidth: 320, rowCount: 6))
      }
    }
    .frame(maxWidth: .infinity)
    .background(
      GeometryReader { geo in
        Color.clear
          .preference(key: HeatmapCardWidthKey.self, value: geo.size.width)
      }
    )
    .background(model.appearancePalette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
    .onPreferenceChange(HeatmapCardWidthKey.self) { cardWidth = $0 }
  }

  private var listeningTimeCard: some View {
    let heatmap = stats.monthListeningHeatmap(
      forMonthContaining: visibleMonthStart,
      calendar: calendar,
      locale: locale
    )
    let summary = listeningSummaryContent(heatmap: heatmap)
    return StatsTimelineMetricCard(title: summary.title, value: summary.value)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(summary.accessibility)
      .animation(.easeInOut(duration: 0.15), value: selectedDayKey)
  }

  @ViewBuilder
  private func calendarHeatmapContent(cardWidth: CGFloat) -> some View {
    let heatmap = stats.monthListeningHeatmap(
      forMonthContaining: visibleMonthStart,
      calendar: calendar,
      locale: locale
    )
    let layout = MonthHeatmapLayout.make(
      heatmap: heatmap,
      containerWidth: cardWidth,
      locale: locale,
      calendar: calendar
    )

    VStack(alignment: .center, spacing: HeatmapMetrics.bodySpacing) {
      monthNavigationRow(title: heatmap.monthTitle)
      weekdayHeaderRow(layout: layout)
      monthGrid(layout: layout, heatmap: heatmap)
        .frame(maxWidth: .infinity, alignment: .center)
      heatmapLegend(blockSize: layout.blockSize)
    }
    .padding(.horizontal, HeatmapMetrics.cardPaddingH)
    .padding(.vertical, HeatmapMetrics.cardPaddingV)
    .frame(maxWidth: .infinity)
    .frame(height: layout.calendarCardHeight, alignment: .top)
  }

  private func monthNavigationRow(title: String) -> some View {
    HStack(spacing: 8) {
      Button {
        guard canGoBack else { return }
        monthsBack += 1
      } label: {
        Image(systemName: "chevron.left")
          .font(.body.weight(.semibold))
          .foregroundStyle(canGoBack ? palette.textPrimary : palette.textSecondary.opacity(0.35))
          .frame(width: 36, height: HeatmapMetrics.navRowHeight)
      }
      .buttonStyle(.plain)
      .disabled(!canGoBack)
      .accessibilityLabel("Previous month")

      monthTitleLabel(title)
        .frame(maxWidth: .infinity)

      Button {
        guard canGoForward else { return }
        monthsBack -= 1
      } label: {
        Image(systemName: "chevron.right")
          .font(.body.weight(.semibold))
          .foregroundStyle(canGoForward ? palette.textPrimary : palette.textSecondary.opacity(0.35))
          .frame(width: 36, height: HeatmapMetrics.navRowHeight)
      }
      .buttonStyle(.plain)
      .disabled(!canGoForward)
      .accessibilityLabel("Next month")
    }
    .frame(height: HeatmapMetrics.navRowHeight)
  }

  @ViewBuilder
  private func monthTitleLabel(_ title: String) -> some View {
    let label = Text(title)
      .font(.title2.weight(.bold))
      .foregroundStyle(palette.textPrimary)
      .lineLimit(1)
      .minimumScaleFactor(0.7)

    if monthTitleLinksToCurrentMonth {
      Button {
        goToToday()
      } label: {
        label
      }
      .buttonStyle(.plain)
      .accessibilityLabel(title)
      .accessibilityHint("Shows the current month.")
    } else {
      label
        .accessibilityAddTraits(.isHeader)
    }
  }

  private func weekdayHeaderRow(layout: MonthHeatmapLayout) -> some View {
    HStack(spacing: layout.columnGap) {
      ForEach(0 ..< 7, id: \.self) { col in
        Text(layout.weekdayLabel(column: col))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(palette.textSecondary)
          .frame(width: layout.blockSize, height: HeatmapMetrics.weekdayHeaderHeight)
      }
    }
    .frame(width: layout.gridWidth, alignment: .center)
  }

  private func monthGrid(layout: MonthHeatmapLayout, heatmap: ABSListeningMonthHeatmap) -> some View {
    VStack(spacing: layout.rowGap) {
      ForEach(0 ..< heatmap.rowCount, id: \.self) { row in
        HStack(spacing: layout.columnGap) {
          ForEach(0 ..< 7, id: \.self) { col in
            let cell = heatmap.cell(column: col, row: row)
            heatmapDayCell(
              cell,
              blockSize: layout.blockSize,
              isSelected: cell?.id == selectedDayKey
            )
          }
        }
      }
    }
    .frame(width: layout.gridWidth, alignment: .center)
  }

  private func heatmapDayCell(
    _ cell: ABSListeningMonthHeatmap.Cell?,
    blockSize: CGFloat,
    isSelected: Bool
  ) -> some View {
    let level = cell?.colorLevel ?? 0
    let inMonth = cell?.isInDisplayedMonth ?? false
    let day = cell?.day ?? 0
    let dayFont = max(8, blockSize * 0.38)

    let dayContent = ZStack {
      Circle()
        .fill(heatmapFill(level: inMonth ? level : 0))
        .overlay {
          Circle()
            .strokeBorder(
              heatmapOutline(level: inMonth ? level : 0),
              lineWidth: 0.5
            )
        }
      if isSelected {
        Circle()
          .strokeBorder(accent, lineWidth: 2)
      }
      if day > 0 {
        Text("\(day)")
          .font(.system(size: dayFont, weight: .medium, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(dayNumberColor(level: level, inMonth: inMonth, isSelected: isSelected))
      }
    }
    .frame(width: blockSize, height: blockSize)
    .opacity(inMonth ? 1 : 0.35)

    return Group {
      if inMonth, let cell {
        Button {
          if selectedDayKey == cell.id {
            selectedDayKey = nil
          } else {
            selectedDayKey = cell.id
          }
        } label: {
          dayContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cell.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      } else {
        dayContent
          .accessibilityLabel(cell?.accessibilityLabel ?? "No data")
      }
    }
  }

  private func dayNumberColor(level: Int, inMonth: Bool, isSelected: Bool) -> Color {
    guard inMonth else { return palette.textSecondary.opacity(0.5) }
    if isSelected { return accent }
    if level >= 3 {
      return palette.foregroundOnAccent(accent)
    }
    return palette.textSecondary
  }

  private func syncSelectedDay(for heatmap: ABSListeningMonthHeatmap) {
    if let key = selectedDayKey,
      heatmap.cells.contains(where: { $0.id == key && $0.isInDisplayedMonth })
    {
      return
    }
    selectedDayKey = nil
  }

  private func goToToday() {
    monthsBack = 0
    selectedDayKey = nil
  }

  private struct ListeningSummaryContent {
    let title: String
    let value: String
    let accessibility: String
  }

  private func listeningSummaryContent(heatmap: ABSListeningMonthHeatmap) -> ListeningSummaryContent {
    if let key = selectedDayKey,
      let cell = heatmap.cells.first(where: { $0.id == key && $0.isInDisplayedMonth })
    {
      return ListeningSummaryContent(
        title: selectedDayMetricTitle(key: key),
        value: listeningTimeLabel(seconds: cell.seconds),
        accessibility: selectedDayAccessibilityLabel(key: key, seconds: cell.seconds)
      )
    }
    return ListeningSummaryContent(
      title: String(localized: "Listening time", comment: "Stats timeline metric card title"),
      value: listeningTimeLabel(seconds: heatmap.totalSecondsInMonth),
      accessibility:
        "\(heatmap.monthTitle), \(heatmap.daysListenedInMonth) days, \(listeningTimeLabel(seconds: heatmap.totalSecondsInMonth))"
    )
  }

  private func selectedDayMetricTitle(key: String) -> String {
    guard let date = ABSListeningStatsResponse.parseDayKey(key, calendar: calendar) else { return key }
    let f = DateFormatter()
    f.locale = locale
    f.dateFormat = "EEE, MMM d"
    return f.string(from: date)
  }

  private func listeningTimeLabel(seconds: Int) -> String {
    seconds > 0 ? formatPlaybackDurationShortHuman(Double(seconds)) : "No listening"
  }

  private func selectedDayAccessibilityLabel(key: String, seconds: Int) -> String {
    let dateLabel: String
    if let date = ABSListeningStatsResponse.parseDayKey(key, calendar: calendar) {
      let f = DateFormatter()
      f.locale = locale
      f.dateStyle = .medium
      f.timeStyle = .none
      dateLabel = f.string(from: date)
    } else {
      dateLabel = key
    }
    return "\(dateLabel), \(listeningTimeLabel(seconds: seconds))"
  }

  private func heatmapFill(level: Int) -> Color {
    switch level {
    case 0: return palette.background
    case 1: return heatmapActiveColor.opacity(palette.isDarkLike ? 0.28 : 0.22)
    case 2: return heatmapActiveColor.opacity(palette.isDarkLike ? 0.48 : 0.42)
    case 3: return heatmapActiveColor.opacity(palette.isDarkLike ? 0.72 : 0.66)
    default: return heatmapActiveColor
    }
  }

  private func heatmapOutline(level: Int) -> Color {
    level == 0
      ? palette.textSecondary.opacity(0.12)
      : heatmapActiveColor.opacity(palette.isDarkLike ? 0.35 : 0.5)
  }

  private func heatmapLegend(blockSize: CGFloat) -> some View {
    let dot = min(9, max(5, blockSize * 0.45))
    return HStack(spacing: 3) {
      Text("Less", comment: "Heatmap legend low")
        .font(.caption2)
        .foregroundStyle(palette.textSecondary)
      ForEach(0 ..< 5, id: \.self) { level in
        Circle()
          .fill(heatmapFill(level: level))
          .overlay {
            Circle().strokeBorder(heatmapOutline(level: level), lineWidth: 0.5)
          }
          .frame(width: dot, height: dot)
      }
      Text("More", comment: "Heatmap legend high")
        .font(.caption2)
        .foregroundStyle(palette.textSecondary)
    }
    .padding(.top, HeatmapMetrics.legendTopPadding)
    .frame(maxWidth: .infinity, alignment: .center)
  }
}

/// Wie `summaryPeriodCard` / Today in Stats › Listening time.
private struct StatsTimelineMetricCard: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  let value: String

  var body: some View {
    let palette = model.appearancePalette
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
        .textCase(.uppercase)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
      Text(value)
        .font(.headline.weight(.bold))
        .foregroundStyle(palette.textPrimary)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }
    .abstandCardListRowFrame()
    .padding(.horizontal, AppTheme.Layout.settingsCardInsetHPadding)
    .padding(.vertical, AppTheme.Layout.settingsCardInsetVPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }
}

private struct HeatmapCardWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    let next = nextValue()
    if next > 0 { value = next }
  }
}

// MARK: - Layout

private struct MonthHeatmapLayout {
  let blockSize: CGFloat
  let columnGap: CGFloat
  let rowGap: CGFloat
  let gridWidth: CGFloat
  let weekdayLabels: [String]
  let calendarCardHeight: CGFloat

  static func make(
    heatmap: ABSListeningMonthHeatmap,
    containerWidth: CGFloat,
    locale: Locale,
    calendar: Calendar
  ) -> MonthHeatmapLayout {
    var cal = calendar
    cal.locale = locale
    let contentWidth = max(0, containerWidth - 2 * HeatmapMetrics.cardPaddingH)
    let n = CGFloat(heatmap.columnCount)
    let minGap = HeatmapMetrics.minColumnGap
    let rawBlock = max(24, (contentWidth - (n - 1) * minGap) / n)
    let block = floor(rawBlock * HeatmapMetrics.dayCellScale)
    let used = n * block
    let columnGap = n > 1 ? max(minGap, (contentWidth - used) / (n - 1)) : 0
    let rowGap = HeatmapMetrics.rowGap
    let gridWidth = n * block + max(0, n - 1) * columnGap

    let allSymbols = cal.shortWeekdaySymbols.count == 7
      ? cal.shortWeekdaySymbols
      : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    let firstIdx = cal.firstWeekday - 1
    let weekdays = (0 ..< 7).map { allSymbols[(firstIdx + $0) % 7] }

    return MonthHeatmapLayout(
      blockSize: block,
      columnGap: columnGap,
      rowGap: rowGap,
      gridWidth: gridWidth,
      weekdayLabels: weekdays,
      calendarCardHeight: estimatedCalendarCardHeight(
        block: block, rowCount: max(heatmap.rowCount, 1), rowGap: rowGap)
    )
  }

  static func estimatedCalendarCardHeight(containerWidth: CGFloat, rowCount: Int) -> CGFloat {
    let contentWidth = max(0, containerWidth - 2 * HeatmapMetrics.cardPaddingH)
    let rawBlock = max(24, (contentWidth - 6 * HeatmapMetrics.minColumnGap) / 7)
    let block = floor(rawBlock * HeatmapMetrics.dayCellScale)
    return estimatedCalendarCardHeight(block: block, rowCount: rowCount, rowGap: HeatmapMetrics.rowGap)
  }

  private static func estimatedCalendarCardHeight(block: CGFloat, rowCount: Int, rowGap: CGFloat) -> CGFloat {
    let rows = CGFloat(rowCount)
    let gridH = rows * block + max(0, rows - 1) * rowGap
    let verticalPad = 2 * HeatmapMetrics.cardPaddingV
    return verticalPad
      + HeatmapMetrics.navRowHeight
      + HeatmapMetrics.bodySpacing
      + HeatmapMetrics.weekdayHeaderHeight
      + HeatmapMetrics.bodySpacing
      + gridH
      + HeatmapMetrics.bodySpacing
      + HeatmapMetrics.legendTopPadding
      + HeatmapMetrics.legendHeight
  }

  func weekdayLabel(column: Int) -> String {
    guard column >= 0, column < weekdayLabels.count else { return "" }
    return String(weekdayLabels[column].prefix(2))
  }
}

private extension Calendar {
  func startOfMonth(for date: Date) -> Date {
    let comps = dateComponents([.year, .month], from: date)
    return self.date(from: comps) ?? date
  }
}
