import Charts
import SwiftUI

/// Hördaten aus `GET /api/me/listening-stats` ([Audiobookshelf API](https://api.audiobookshelf.org)), Darstellung wie Home/Books (`LazyVStack`, gleiche Abschnittsüberschriften).
struct StatsTabView: View {
  @EnvironmentObject private var model: AppModel

  private static let cacheDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "de_DE")
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
            Text("Keine gespeicherte Statistik. Mit Serververbindung werden die Daten geladen und zwischengespeichert.")
              .font(.subheadline)
              .foregroundStyle(AppTheme.textSecondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 32)
          } else {
            Text("Keine Statistik geladen.")
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
      Text(
        "Offline — zwischengespeichert vom \(Self.cacheDateFormatter.string(from: fetchedAt))."
      )
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
    let bars = stats.lastSevenDayBars(locale: Locale(identifier: "de_DE"))

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      tabSectionHeading("Überblick")
      totalHero(stats)
      HStack(spacing: 10) {
        summaryPill(title: "Heute", seconds: stats.today)
        summaryPill(title: "7 Tage", seconds: weekSeconds)
        summaryPill(title: "Monat", seconds: monthSeconds)
      }
    }

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      tabSectionHeading("Aktivität")
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
        spacing: 10
      ) {
        activityCell(
          icon: "flame.fill", color: .orange, value: "\(stats.currentListeningStreakDays())",
          label: "Aktuelle Serie")
        activityCell(
          icon: "trophy.fill", color: .yellow, value: "\(stats.bestListeningStreakDays())",
          label: "Längste Serie")
        activityCell(
          icon: "book.fill", color: .green, value: "\(stats.bookLikeItemCount)", label: "Hörbücher")
        activityCell(
          icon: "dot.radiowaves.left.and.right", color: .purple,
          value: "\(stats.podcastLikeItemCount)", label: "Podcasts")
        activityCell(
          icon: "calendar", color: .blue, value: "\(stats.daysActive)", label: "Aktive Tage")
        activityCell(
          icon: "gauge.with.dots.needle.67percent", color: .gray,
          value: formatStatsCompact(stats.dailyAverageSeconds),
          label: "Tagesdurchschnitt")
        activityCell(
          icon: "books.vertical.fill", color: Color(red: 0.2, green: 0.72, blue: 0.68),
          value: formatStatsCompact(yearSeconds),
          label: "Hörzeit \(Calendar.current.component(.year, from: Date()))")
      }
    }

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      tabSectionHeading("Letzte 7 Tage")
      chartCard(bars: bars)
    }
  }

  /// Wie `tabContentSectionTitle` in `MainRootView` (Home / Books).
  private func tabSectionHeading(_ title: String) -> some View {
    Text(title)
      .font(.title3)
      .bold()
      .foregroundStyle(AppTheme.textPrimary)
  }

  private func totalHero(_ stats: ABSListeningStatsResponse) -> some View {
    let daysApprox = stats.totalTimeAsCalendarDaysApprox
    let daysLabel = String(format: "%.1f", locale: Locale(identifier: "de_DE"), daysApprox)
    return VStack(alignment: .leading, spacing: 8) {
      Text("Gesamthörzeit")
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
        .textCase(.uppercase)
      Text(formatStatsCompact(stats.totalTime))
        .font(.title.weight(.bold))
        .foregroundStyle(AppTheme.textPrimary)
      Text("Das sind ca. \(daysLabel) Tage Audio.")
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

  private func activityCell(icon: String, color: Color, value: String, label: String) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(color)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(1)
        Text(label)
          .font(.caption2)
          .foregroundStyle(AppTheme.textSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func chartCard(bars: [(id: String, label: String, seconds: Int)]) -> some View {
    let maxSec = max(bars.map(\.seconds).max() ?? 0, 1)
    return Chart {
      ForEach(bars, id: \.id) { row in
        BarMark(
          x: .value("Tag", row.label),
          y: .value("h", Double(row.seconds) / 3600.0)
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
