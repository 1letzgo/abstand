import Charts
import SwiftUI

/// Listening data from `GET /api/me/listening-stats` — embedded in Settings (Stats scope).
struct StatsTabView: View {
  @EnvironmentObject private var model: AppModel

  /// In Settings hub: content only, parent `ScrollView` + scope strip.
  var embeddedInParentScroll = false

  private static let statsLocale = Locale(identifier: "en_US")

  private static let statsCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2 // Montag
    cal.locale = statsLocale
    return cal
  }()

  private static let cacheDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = statsLocale
    f.dateStyle = .short
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    Group {
      if embeddedInParentScroll {
        statsBody
      } else {
        ScrollView {
          statsBody
            .padding(.horizontal, AppTheme.Layout.tabPaddingH)
            .padding(.top, AppTheme.Layout.withinSectionSpacing)
            .padding(
              .bottom,
              AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset
            )
        }
        .abstandScrollScreenBackground()
        .refreshable {
          await model.loadListeningStats()
        }
      }
    }
    .task {
      await model.loadListeningStats()
    }
  }

  private var statsBody: some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      if let fetched = model.listeningStatsFetchedAt, model.listeningStats != nil,
        !model.isNetworkReachable
      {
        cacheOfflineBanner(fetchedAt: fetched)
      }

      if model.listeningStats == nil {
        if model.listeningStatsLoading {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else if !model.isNetworkReachable {
          Text(
            "No saved statistics. Connect to the server to load and cache your listening data."
          )
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
        } else {
          Text("No statistics loaded.")
            .foregroundStyle(AppTheme.textSecondary)
        }
      } else if let stats = model.listeningStats {
        statsContent(stats)
      }
    }
  }

  private func cacheOfflineBanner(fetchedAt: Date) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "icloud.slash")
        .foregroundStyle(AppTheme.accent)
      Text("Offline — cached \(Self.cacheDateFormatter.string(from: fetchedAt)).")
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }

  @ViewBuilder
  private func statsContent(_ stats: ABSListeningStatsResponse) -> some View {
    let weekSeconds = stats.secondsInLastDays(7)
    let monthSeconds = stats.secondsThisCalendarMonth()
    let yearSeconds = stats.secondsThisCalendarYear()
    let bars = stats.lastSevenDayBars(locale: Self.statsLocale)

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: "Listening Stats")
      totalHero(stats)
      HStack(spacing: 10) {
        summaryPill(title: "Today", seconds: stats.today)
        summaryPill(title: "7 days", seconds: weekSeconds)
        summaryPill(title: "Month", seconds: monthSeconds)
        summaryPill(title: "Year", seconds: yearSeconds)
      }
    }

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: "Activity")
      ListeningYearHeatmapCard(stats: stats, locale: Self.statsLocale, calendar: Self.statsCalendar)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
        .clipped()
      activityStatRow([
        ActivityStatTile(
          id: "year-listened",
          icon: "calendar.badge.clock",
          tint: AppTheme.success,
          value: "\(stats.daysListenedInLastYear)",
          label: "Days listened in the last year"),
      ])
      activityGrid(stats: stats)
    }

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: "Last 7 days")
      weekLineChartCard(bars: bars)
    }
  }

  private func totalHero(_ stats: ABSListeningStatsResponse) -> some View {
    let daysApprox = stats.totalTimeAsCalendarDaysApprox
    let daysLabel = String(format: "%.1f", locale: Self.statsLocale, daysApprox)
    return VStack(alignment: .leading, spacing: 8) {
      Text("Total listening time")
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
        .textCase(.uppercase)
      Text(formatStatsCompact(stats.totalTime))
        .font(.title.weight(.bold))
        .foregroundStyle(AppTheme.textPrimary)
      Text("About \(daysLabel) days of audio.")
        .font(.subheadline)
        .foregroundStyle(AppTheme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }

  private func summaryPill(title: String, seconds: Int) -> some View {
    let lines = formatStatsDurationLines(seconds)
    return VStack(spacing: 6) {
      VStack(spacing: 2) {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
          Text(line)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
      }
      .frame(minHeight: 40)
      .frame(maxWidth: .infinity)
      Text(title)
        .font(.caption2)
        .foregroundStyle(AppTheme.textSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  /// Kacheln im Raster (vgl. Absorb `_accentStatCard`-Zeilen), keine horizontale Streifen-Leiste.
  private func activityGrid(stats: ABSListeningStatsResponse) -> some View {
    VStack(spacing: 10) {
      activityStatRow([
        ActivityStatTile(
          id: "streak", icon: "flame.fill", tint: AppTheme.accent,
          value: "\(stats.currentListeningStreakDays())", label: "Current streak"),
        ActivityStatTile(
          id: "best", icon: "trophy.fill", tint: AppTheme.accent.opacity(0.85),
          value: "\(stats.bestListeningStreakDays())", label: "Longest streak"),
      ])
      activityStatRow([
        ActivityStatTile(
          id: "books", icon: "book.fill", tint: AppTheme.success,
          value: "\(stats.bookLikeItemCount)", label: "Audiobooks"),
        ActivityStatTile(
          id: "podcasts", icon: "dot.radiowaves.left.and.right", tint: AppTheme.textSecondary,
          value: "\(stats.podcastLikeItemCount)", label: "Podcasts"),
      ])
      activityStatRow([
        ActivityStatTile(
          id: "days", icon: "calendar", tint: AppTheme.textPrimary,
          value: "\(stats.daysActive)", label: "Active days"),
        ActivityStatTile(
          id: "avg", icon: "gauge.with.dots.needle.67percent", tint: AppTheme.textSecondary,
          value: formatStatsCompact(stats.dailyAverageSeconds), label: "Daily average"),
      ])
    }
  }

  private struct ActivityStatTile: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let value: String
    let label: String
  }

  @ViewBuilder
  private func activityStatRow(_ tiles: [ActivityStatTile]) -> some View {
    if tiles.count == 1, let tile = tiles.first {
      activityStatCard(icon: tile.icon, tint: tile.tint, value: tile.value, label: tile.label)
    } else {
      HStack(spacing: 10) {
        ForEach(tiles) { tile in
          activityStatCard(icon: tile.icon, tint: tile.tint, value: tile.value, label: tile.label)
        }
      }
    }
  }

  private func activityStatCard(icon: String, tint: Color, value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(tint)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(label)
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }

  private func weekLineChartCard(bars: [(id: String, label: String, seconds: Int)]) -> some View {
    let maxSec = max(bars.map(\.seconds).max() ?? 0, 1)
    let maxHours = max(Double(maxSec) / 3600.0, 0.25)
    return Chart {
      ForEach(bars, id: \.id) { row in
        let hours = Double(row.seconds) / 3600.0
        LineMark(
          x: .value("Day", row.label),
          y: .value("Hours", hours)
        )
        .foregroundStyle(AppTheme.accent)
        .interpolationMethod(.catmullRom)
        PointMark(
          x: .value("Day", row.label),
          y: .value("Hours", hours)
        )
        .foregroundStyle(AppTheme.accent)
        .symbolSize(36)
      }
    }
    .chartYScale(domain: 0 ... maxHours)
    .chartYAxis {
      AxisMarks(position: .leading)
    }
    .chartXAxis {
      AxisMarks { _ in
        AxisValueLabel().font(.caption2)
      }
    }
    .frame(height: 200)
    .padding(12)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }

  /// Englische Kurzform für Hero / Activity (eine Zeile).
  private func formatStatsCompact(_ seconds: Int) -> String {
    formatStatsDurationLines(seconds).joined(separator: " ")
  }

  /// Bis zu zwei Zeilen für die 4er-Reihe (z. B. `3 hrs` / `12 min`).
  private func formatStatsDurationLines(_ seconds: Int) -> [String] {
    let s = max(0, seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    if h == 0, m == 0 { return ["< 1 min"] }
    var lines: [String] = []
    if h > 0 {
      lines.append(h == 1 ? "1 hr" : "\(h) hrs")
    }
    if m > 0 {
      lines.append(m == 1 ? "1 min" : "\(m) min")
    }
    return lines.isEmpty ? ["< 1 min"] : lines
  }
}
