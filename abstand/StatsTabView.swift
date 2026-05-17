import Charts
import SwiftUI

/// Listening data from `GET /api/me/listening-stats` — layout aligned with Home/Books and Podcast shows strip.
struct StatsTabView: View {
  @EnvironmentObject private var model: AppModel

  private static let statsLocale = Locale(identifier: "en_US")

  private static let cacheDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = statsLocale
    f.dateStyle = .short
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    ScrollView {
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
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .refreshable {
      await model.loadListeningStats()
    }
    .task {
      await model.loadListeningStats()
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
    let year = Calendar.current.component(.year, from: Date())

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      tabSectionHeading("Activity")
      activityStrip(stats: stats, yearSeconds: yearSeconds, year: year)
    }

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      tabSectionHeading("Overview")
      totalHero(stats)
      HStack(spacing: 10) {
        summaryPill(title: "Today", seconds: stats.today)
        summaryPill(title: "7 days", seconds: weekSeconds)
        summaryPill(title: "Month", seconds: monthSeconds)
      }
    }

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      tabSectionHeading("Last 7 days")
      chartCard(bars: bars)
    }
  }

  private func tabSectionHeading(_ title: String) -> some View {
    Text(title)
      .font(.title3)
      .bold()
      .foregroundStyle(AppTheme.textPrimary)
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
    VStack(spacing: 6) {
      Text(formatStatsCompact(seconds))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(title)
        .font(.caption2)
        .foregroundStyle(AppTheme.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  /// Horizontal strip — same tile geometry as Podcast „Shows“ (`podcastShowsCoverStrip`).
  private func activityStrip(stats: ABSListeningStatsResponse, yearSeconds: Int, year: Int) -> some View {
    let cover = AppTheme.Layout.horizontalBrowseStripTile
    let captionW = cover + AppTheme.Layout.horizontalBrowseStripLabelWidthExtra
    let tiles: [(id: String, icon: String, color: Color, value: String, label: String)] = [
      (
        "streak", "flame.fill", AppTheme.accent, "\(stats.currentListeningStreakDays())",
        "Current streak"
      ),
      (
        "best", "trophy.fill", AppTheme.accent.opacity(0.85), "\(stats.bestListeningStreakDays())",
        "Longest streak"
      ),
      ("books", "book.fill", AppTheme.success, "\(stats.bookLikeItemCount)", "Audiobooks"),
      (
        "podcasts", "dot.radiowaves.left.and.right", AppTheme.textSecondary,
        "\(stats.podcastLikeItemCount)", "Podcasts"
      ),
      ("days", "calendar", AppTheme.textPrimary, "\(stats.daysActive)", "Active days"),
      (
        "avg", "gauge.with.dots.needle.67percent", AppTheme.textSecondary,
        formatStatsCompact(stats.dailyAverageSeconds), "Daily average"
      ),
      (
        "year", "books.vertical.fill", AppTheme.success.opacity(0.9),
        formatStatsCompact(yearSeconds), "\(year) listening"
      ),
    ]

    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: AppTheme.Layout.horizontalBrowseStripInterTileSpacing) {
        ForEach(tiles, id: \.id) { tile in
          activityStripTile(
            icon: tile.icon,
            color: tile.color,
            value: tile.value,
            label: tile.label,
            cover: cover,
            captionW: captionW
          )
        }
      }
      .padding(.vertical, AppTheme.Layout.horizontalBrowseStripVerticalPadding)
    }
    .scrollContentBackground(.hidden)
  }

  private func activityStripTile(
    icon: String,
    color: Color,
    value: String,
    label: String,
    cover: CGFloat,
    captionW: CGFloat
  ) -> some View {
    VStack(spacing: AppTheme.Layout.horizontalBrowseStripTileLabelSpacing) {
      ZStack {
        RoundedRectangle(cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous)
          .fill(AppTheme.card)
          .frame(width: cover, height: cover)
        Image(systemName: icon)
          .font(.title2)
          .foregroundStyle(color)
      }
      Text(value)
        .font(.caption2.weight(.medium))
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(width: captionW)
      Text(label)
        .font(.caption2)
        .foregroundStyle(AppTheme.textSecondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(width: captionW)
    }
  }

  private func chartCard(bars: [(id: String, label: String, seconds: Int)]) -> some View {
    let maxSec = max(bars.map(\.seconds).max() ?? 0, 1)
    return Chart {
      ForEach(bars, id: \.id) { row in
        BarMark(
          x: .value("Day", row.label),
          y: .value("Hours", Double(row.seconds) / 3600.0)
        )
        .foregroundStyle(AppTheme.accent.opacity(0.9))
      }
    }
    .chartYScale(domain: 0 ... max(Double(maxSec) / 3600.0, 0.25))
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

  private func formatStatsCompact(_ seconds: Int) -> String {
    formatPlaybackDurationShortHuman(Double(max(0, seconds)))
  }
}
