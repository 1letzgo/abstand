import SwiftUI

// MARK: - Jahres-Heatmap (volle Card, kein Scroll, Heatmap zentriert)

private enum HeatmapMetrics {
  static let cardPaddingH: CGFloat = 14
  static let cardPaddingV: CGFloat = 12
  static let labelSpacing: CGFloat = 4
  static let monthRowHeight: CGFloat = 12
  static let legendHeight: CGFloat = 14
  static let minColumnGap: CGFloat = 1
  static let rowGap: CGFloat = 2
  static let weekdayColumnWidth: CGFloat = 14
  static let bodySpacing: CGFloat = 8
}

struct ListeningYearHeatmapCard: View {
  let stats: ABSListeningStatsResponse
  var locale: Locale = Locale(identifier: "en_US")
  var calendar: Calendar = .current

  @State private var cardWidth: CGFloat = 0

  var body: some View {
    Group {
      if cardWidth > 1 {
        heatmapContent(cardWidth: cardWidth)
      } else {
        Color.clear
          .frame(height: HeatmapLayout.estimatedCardHeight(containerWidth: 320))
      }
    }
    .frame(maxWidth: .infinity)
    .background(
      GeometryReader { geo in
        Color.clear
          .preference(key: HeatmapCardWidthKey.self, value: geo.size.width)
      }
    )
    .onPreferenceChange(HeatmapCardWidthKey.self) { cardWidth = $0 }
  }

  @ViewBuilder
  private func heatmapContent(cardWidth: CGFloat) -> some View {
    let layout = HeatmapLayout.make(
      stats: stats,
      containerWidth: cardWidth,
      locale: locale,
      calendar: calendar
    )

    VStack(alignment: .center, spacing: HeatmapMetrics.bodySpacing) {
      heatmapCluster(layout: layout)
        .frame(maxWidth: .infinity, alignment: .center)

      heatmapLegend(blockSize: layout.blockSize)
    }
    .padding(.horizontal, HeatmapMetrics.cardPaddingH)
    .padding(.vertical, HeatmapMetrics.cardPaddingV)
    .frame(maxWidth: .infinity)
    .frame(height: layout.cardHeight, alignment: .center)
  }

  private func heatmapCluster(layout: HeatmapLayout) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      monthLabelRow(layout: layout)
      heatmapGrid(layout: layout)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func weekdayColumn(layout: HeatmapLayout) -> some View {
    VStack(alignment: .trailing, spacing: layout.rowGap) {
      ForEach(0 ..< 7, id: \.self) { row in
        Text(layout.weekdayLabel(row: row))
          .font(.system(size: 7, weight: .medium))
          .foregroundStyle(AppTheme.textSecondary)
          .frame(
            width: HeatmapMetrics.weekdayColumnWidth,
            height: layout.blockSize,
            alignment: .trailing
          )
      }
    }
    .padding(.top, HeatmapMetrics.monthRowHeight)
  }

  private func monthLabelRow(layout: HeatmapLayout) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(layout.heatmap.monthLabels) { label in
        Text(label.label)
          .font(.system(size: 7, weight: .medium))
          .foregroundStyle(AppTheme.textSecondary)
          .lineLimit(1)
          .offset(x: layout.columnOffset(for: label.column))
      }
    }
    .frame(width: layout.gridWidth, height: HeatmapMetrics.monthRowHeight, alignment: .topLeading)
    .clipped()
  }

  private func heatmapGrid(layout: HeatmapLayout) -> some View {
    heatmapColumns(layout: layout)
      .frame(width: layout.actualGridWidth, height: layout.gridHeight, alignment: .leading)
      .frame(width: layout.gridWidth, alignment: .center)
  }

  private func heatmapColumns(layout: HeatmapLayout) -> some View {
    HStack(alignment: .top, spacing: layout.columnGap) {
      ForEach(0 ..< layout.heatmap.columnCount, id: \.self) { column in
        VStack(spacing: layout.rowGap) {
          ForEach(0 ..< 7, id: \.self) { row in
            heatmapBlock(
              layout.heatmap.cell(column: column, row: row),
              blockSize: layout.blockSize
            )
          }
        }
      }
    }
  }

  private func heatmapBlock(_ cell: ABSListeningYearHeatmap.Cell?, blockSize: CGFloat) -> some View {
    Circle()
      .fill(heatmapFill(level: cell?.colorLevel ?? 0))
      .overlay {
        Circle()
          .strokeBorder(heatmapOutline(level: cell?.colorLevel ?? 0), lineWidth: 0.5)
      }
      .frame(width: blockSize, height: blockSize)
      .accessibilityLabel(cell?.accessibilityLabel ?? "No data")
  }

  private func heatmapFill(level: Int) -> Color {
    switch level {
    case 0: return AppTheme.background
    case 1: return AppTheme.success.opacity(0.28)
    case 2: return AppTheme.success.opacity(0.48)
    case 3: return AppTheme.success.opacity(0.72)
    default: return AppTheme.success
    }
  }

  private func heatmapOutline(level: Int) -> Color {
    level == 0
      ? AppTheme.textSecondary.opacity(0.12)
      : AppTheme.success.opacity(0.35)
  }

  private func heatmapLegend(blockSize: CGFloat) -> some View {
    let dot = min(9, max(5, blockSize))
    return HStack(spacing: 3) {
      Text("Less", comment: "Heatmap legend low")
        .font(.caption2)
        .foregroundStyle(AppTheme.textSecondary)
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
        .foregroundStyle(AppTheme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .center)
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

private struct HeatmapLayout {
  let heatmap: ABSListeningYearHeatmap
  let blockSize: CGFloat
  let columnGap: CGFloat
  let rowGap: CGFloat
  /// Zielbreite des Raster-Bereichs (zentriert im Cluster).
  let gridWidth: CGFloat
  /// Tatsächliche Breite der Kreis-Spalten (für Zentrierung im Raster-Rahmen).
  let actualGridWidth: CGFloat
  let gridHeight: CGFloat
  let weekdayLabels: [String]
  let cardHeight: CGFloat
  private let columnOffsets: [Int: CGFloat]

  static func make(
    stats: ABSListeningStatsResponse,
    containerWidth: CGFloat,
    locale: Locale,
    calendar: Calendar = .current
  ) -> HeatmapLayout {
    var cal = calendar
    cal.locale = locale
    let heatmap = stats.yearListeningHeatmap(weeksToShow: 52, calendar: cal, locale: locale)
    let columnCount = max(heatmap.columnCount, 1)
    let n = CGFloat(columnCount)

    let contentWidth = max(0, containerWidth - 2 * HeatmapMetrics.cardPaddingH)
    let gridArea = contentWidth

    let minColGap = HeatmapMetrics.minColumnGap
    let block = max(2, (gridArea - (n - 1) * minColGap) / n)
    let usedBlocks = n * block
    let columnGap = n > 1 ? max(minColGap, (gridArea - usedBlocks) / (n - 1)) : 0
    let actualGridWidth = n * block + max(0, n - 1) * columnGap
    let rowGap = HeatmapMetrics.rowGap
    let gridHeight = 7 * block + 6 * rowGap

    var offsets: [Int: CGFloat] = [:]
    for col in 0 ..< columnCount {
      offsets[col] = CGFloat(col) * (block + columnGap)
    }

    let allSymbols = cal.shortWeekdaySymbols.count == 7
      ? cal.shortWeekdaySymbols
      : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    let firstIdx = cal.firstWeekday - 1
    let weekdays = (0 ..< 7).map { allSymbols[(firstIdx + $0) % 7] }

    return HeatmapLayout(
      heatmap: heatmap,
      blockSize: block,
      columnGap: columnGap,
      rowGap: rowGap,
      gridWidth: gridArea,
      actualGridWidth: actualGridWidth,
      gridHeight: gridHeight,
      weekdayLabels: weekdays,
      cardHeight: estimatedCardHeight(block: block, rowGap: rowGap),
      columnOffsets: offsets
    )
  }

  static func estimatedCardHeight(containerWidth: CGFloat) -> CGFloat {
    let contentWidth = max(0, containerWidth - 2 * HeatmapMetrics.cardPaddingH)
    let gridArea = contentWidth
    let n = CGFloat(53)
    let block = max(2, (gridArea - (n - 1) * HeatmapMetrics.minColumnGap) / n)
    return estimatedCardHeight(block: block, rowGap: HeatmapMetrics.rowGap)
  }

  private static func estimatedCardHeight(block: CGFloat, rowGap: CGFloat) -> CGFloat {
    let gridRows = 7 * block + 6 * rowGap
    let verticalPad = 2 * HeatmapMetrics.cardPaddingV
    return verticalPad + HeatmapMetrics.monthRowHeight + gridRows
      + HeatmapMetrics.bodySpacing + HeatmapMetrics.legendHeight
  }

  func columnOffset(for column: Int) -> CGFloat {
    columnOffsets[column] ?? 0
  }

  func weekdayLabel(row: Int) -> String {
    guard row >= 0, row < weekdayLabels.count else { return "" }
    return String(weekdayLabels[row].prefix(1))
  }
}
