import Charts
import SwiftUI

private enum StatsBrowseSection: String, CaseIterable, Identifiable {
  case overview = "Listening"
  case mostListened = "Most listened"
  case activity = "Activity"
  case week = "7 days"
  case recentSessions = "Sessions"

  var id: String { rawValue }

  static let stripOrder: [StatsBrowseSection] = [
    .overview, .activity, .week, .mostListened, .recentSessions,
  ]

  var systemImage: String {
    switch self {
    case .overview: return "clock.fill"
    case .mostListened: return "list.star"
    case .activity: return "calendar"
    case .week: return "chart.xyaxis.line"
    case .recentSessions: return "play.circle.fill"
    }
  }
}

private struct StatsBrowseSectionStrip: View {
  let selection: StatsBrowseSection
  let onSelect: (StatsBrowseSection) -> Void

  var body: some View {
    let tile = AppTheme.Layout.horizontalBrowseStripTile
    let captionW = tile + AppTheme.Layout.horizontalBrowseStripLabelWidthExtra
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: AppTheme.Layout.horizontalBrowseStripInterTileSpacing) {
        ForEach(StatsBrowseSection.stripOrder) { section in
          Button {
            onSelect(section)
          } label: {
            VStack(spacing: AppTheme.Layout.horizontalBrowseStripTileLabelSpacing) {
              ZStack {
                RoundedRectangle(
                  cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous
                )
                .fill(AppTheme.card)
                .frame(width: tile, height: tile)
                Image(systemName: section.systemImage)
                  .font(.title2)
                  .foregroundStyle(
                    selection == section ? AppTheme.accent : AppTheme.textSecondary)
              }
              .overlay {
                RoundedRectangle(
                  cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous
                )
                .strokeBorder(
                  selection == section ? AppTheme.accent : Color.clear, lineWidth: 2.5)
              }
              Text(section.rawValue)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(width: captionW)
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, AppTheme.Layout.horizontalBrowseStripVerticalPadding)
    }
    .scrollContentBackground(.hidden)
  }
}

/// Mehrere Listenzeilen in einer Karte (wie Settings), ohne Abstand zwischen den Zeilen.
private struct StatsGroupedListCard<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }
}

private var statsListRowDivider: some View {
  Divider().overlay(AppTheme.textSecondary.opacity(0.25))
}

/// Wie Home: enger Abstand Überschrift → Inhalt; `sectionSpacing` nur zwischen mehreren Blöcken.
private struct StatsContentSection<Content: View>: View {
  let title: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: title)
      content()
    }
  }
}

/// Listening data from `GET /api/me/listening-stats` (eigener Stats-Tab).
struct StatsTabView: View {
  @EnvironmentObject private var model: AppModel
  @State private var browseSection: StatsBrowseSection = .overview

  private static let statsLocale = Locale(identifier: "en_US")
  private static let periodColumns = [
    GridItem(.flexible(), spacing: AppTheme.Layout.withinSectionSpacing),
    GridItem(.flexible(), spacing: AppTheme.Layout.withinSectionSpacing),
  ]
  private static let activityColumns = [
    GridItem(.flexible(), spacing: AppTheme.Layout.withinSectionSpacing),
    GridItem(.flexible(), spacing: AppTheme.Layout.withinSectionSpacing),
  ]

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

  private static let sessionDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = statsLocale
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  var body: some View {
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
        StatsBrowseSectionStrip(selection: browseSection) { browseSection = $0 }
        statsSectionContent(stats)
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
  private func statsSectionContent(_ stats: ABSListeningStatsResponse) -> some View {
    switch browseSection {
    case .overview:
      statsOverviewSection(stats)
    case .mostListened:
      statsTopListenedSection(stats)
    case .activity:
      statsActivitySection(stats)
    case .week:
      statsWeekSection(stats)
    case .recentSessions:
      statsRecentSessionsSection(stats)
    }
  }

  // MARK: - Listing

  private func statsOverviewSection(_ stats: ABSListeningStatsResponse) -> some View {
    StatsContentSection(title: "Listening time") {
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        totalHero(stats)
        LazyVGrid(columns: Self.periodColumns, spacing: AppTheme.Layout.withinSectionSpacing) {
          summaryPeriodCard(title: "Today", seconds: stats.today)
          summaryPeriodCard(title: "7 days", seconds: stats.secondsInLastDays(7))
          summaryPeriodCard(title: "Month", seconds: stats.secondsThisCalendarMonth())
          summaryPeriodCard(title: "Year", seconds: stats.secondsThisCalendarYear())
        }
      }
    }
  }

  // MARK: - Top listened

  private func statsTopListenedSection(_ stats: ABSListeningStatsResponse) -> some View {
    let topItems = Array(stats.itemsSortedByListeningTime.prefix(10))
    return StatsContentSection(title: "Most listened") {
      if topItems.isEmpty {
        Text("No listening history for individual titles yet.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
      } else {
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(Array(topItems.enumerated()), id: \.element.id) { index, row in
            StatsTopListenedBookCard(
              rank: index + 1,
              lookupId: row.id,
              item: row.item
            )
          }
        }
      }
    }
  }

  private func totalHero(_ stats: ABSListeningStatsResponse) -> some View {
    let daysApprox = stats.totalTimeAsCalendarDaysApprox
    let daysLabel = String(format: "%.1f", locale: Self.statsLocale, daysApprox)
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "headphones.circle.fill")
          .font(.system(size: 44))
          .foregroundStyle(AppTheme.accent)
        VStack(alignment: .leading, spacing: 6) {
          Text(formatStatsCompact(stats.totalTime))
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.textPrimary)
            .minimumScaleFactor(0.7)
            .lineLimit(2)
          Text("About \(daysLabel) days of audio")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }

  /// Kompakte Stat-Karte: zwei Zeilen (Titel oben, Wert unten); optional Icon links.
  private func statsMetricCard(
    icon: String? = nil,
    tint: Color = AppTheme.accent,
    title: String,
    value: String,
    uppercaseTitle: Bool = false,
    valueFont: Font = .headline.weight(.bold)
  ) -> some View {
    let textColumn = VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
        .textCase(uppercaseTitle ? .uppercase : nil)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
      Text(value)
        .font(valueFont)
        .foregroundStyle(AppTheme.textPrimary)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }

    return Group {
      if let icon {
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 26, alignment: .center)
          textColumn
          Spacer(minLength: 0)
        }
      } else {
        textColumn
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }

  private func summaryPeriodCard(title: String, seconds: Int) -> some View {
    statsMetricCard(
      title: title,
      value: formatStatsCompact(seconds),
      uppercaseTitle: true
    )
  }

  // MARK: - Activity

  private func statsActivitySection(_ stats: ABSListeningStatsResponse) -> some View {
    let weekdayBars = stats.dayOfWeekBars(calendar: Self.statsCalendar, locale: Self.statsLocale)
    return VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      StatsContentSection(title: "Year overview") {
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          ListeningYearHeatmapCard(stats: stats, locale: Self.statsLocale, calendar: Self.statsCalendar)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
            .clipped()
          HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
            featuredStatCard(
              icon: "flame.fill",
              tint: AppTheme.accent,
              value: "\(stats.currentListeningStreakDays(calendar: Self.statsCalendar))",
              label: "Current streak",
              subtitle: "days in a row"
            )
            featuredStatCard(
              icon: "trophy.fill",
              tint: AppTheme.accent.opacity(0.85),
              value: "\(stats.bestListeningStreakDays(calendar: Self.statsCalendar))",
              label: "Longest streak",
              subtitle: "best run"
            )
          }
        }
      }

      if weekdayBars.contains(where: { $0.seconds > 0 }) {
        StatsContentSection(title: "By weekday") {
          weekdayBarChartCard(bars: weekdayBars)
        }
      }

      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        featuredStatCard(
          icon: "calendar.badge.clock",
          tint: AppTheme.success,
          value: "\(stats.daysListenedInLastYear)",
          label: "Days with listening",
          subtitle: "in the last 12 months"
        )
        LazyVGrid(columns: Self.activityColumns, spacing: AppTheme.Layout.withinSectionSpacing) {
          statsMetricCard(
            icon: "book.fill", tint: AppTheme.success,
            title: "Audiobooks", value: "\(stats.bookLikeItemCount)")
          statsMetricCard(
            icon: "dot.radiowaves.left.and.right", tint: AppTheme.textSecondary,
            title: "Podcasts", value: "\(stats.podcastLikeItemCount)")
          statsMetricCard(
            icon: "calendar", tint: AppTheme.textPrimary,
            title: "Active days", value: "\(stats.daysActive)")
          statsMetricCard(
            icon: "gauge.with.dots.needle.67percent", tint: AppTheme.textSecondary,
            title: "Daily average", value: formatStatsCompact(stats.dailyAverageSeconds))
        }
      }
    }
  }

  private func featuredStatCard(
    icon: String,
    tint: Color,
    value: String,
    label: String,
    subtitle: String
  ) -> some View {
    let title = subtitle.isEmpty ? label : "\(label) — \(subtitle)"
    return statsMetricCard(
      icon: icon,
      tint: tint,
      title: title,
      value: value
    )
  }

  private func weekdayBarChartCard(bars: [(id: String, label: String, seconds: Int)]) -> some View {
    let maxSec = max(bars.map(\.seconds).max() ?? 0, 1)
    let maxHours = max(Double(maxSec) / 3600.0, 0.25)
    return Chart {
      ForEach(bars, id: \.id) { row in
        let hours = Double(row.seconds) / 3600.0
        BarMark(
          x: .value("Day", row.label),
          y: .value("Hours", hours)
        )
        .foregroundStyle(AppTheme.accent.gradient)
        .cornerRadius(4)
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
    .frame(height: 220)
    .padding(12)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }

  // MARK: - Week

  private func statsWeekSection(_ stats: ABSListeningStatsResponse) -> some View {
    let bars = stats.lastSevenDayBars(calendar: Self.statsCalendar, locale: Self.statsLocale)
    return VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      StatsContentSection(title: "Last 7 days") {
        weekLineChartCard(bars: bars, height: 260)
      }
      StatsContentSection(title: "Daily breakdown") {
        StatsGroupedListCard {
          ForEach(Array(bars.enumerated()), id: \.element.id) { index, row in
            if index > 0 { statsListRowDivider }
            weekDayRow(row: row, maxSeconds: max(bars.map(\.seconds).max() ?? 1, 1))
          }
        }
      }
    }
  }

  // MARK: - Sessions

  private func statsRecentSessionsSection(_ stats: ABSListeningStatsResponse) -> some View {
    let sessions = stats.recentSessions
    return StatsContentSection(title: "Sessions") {
      if sessions.isEmpty {
        Text("No listening sessions yet.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
      } else {
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(sessions) { session in
            StatsRecentSessionCard(session: session)
          }
        }
      }
    }
  }

  private func weekDayRow(
    row: (id: String, label: String, seconds: Int),
    maxSeconds: Int
  ) -> some View {
    let fraction = CGFloat(row.seconds) / CGFloat(maxSeconds)
    return HStack(spacing: 12) {
      Text(row.label)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(AppTheme.textPrimary)
        .frame(width: 36, alignment: .leading)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppTheme.background)
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppTheme.accent.opacity(0.5))
            .frame(width: max(4, geo.size.width * fraction))
        }
      }
      .frame(height: 10)
      Text(formatStatsCompact(row.seconds))
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 64, alignment: .trailing)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  private func weekLineChartCard(bars: [(id: String, label: String, seconds: Int)], height: CGFloat) -> some View {
    let maxSec = max(bars.map(\.seconds).max() ?? 0, 1)
    let maxHours = max(Double(maxSec) / 3600.0, 0.25)
    return Chart {
      ForEach(bars, id: \.id) { row in
        let hours = Double(row.seconds) / 3600.0
        AreaMark(
          x: .value("Day", row.label),
          y: .value("Hours", hours)
        )
        .foregroundStyle(
          LinearGradient(
            colors: [AppTheme.accent.opacity(0.35), AppTheme.accent.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .interpolationMethod(.catmullRom)
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
        .symbolSize(48)
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
    .frame(height: height)
    .padding(14)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }

  // MARK: - Formatting

  private func formatStatsCompact(_ seconds: Int) -> String {
    formatPlaybackDurationShortHuman(Double(seconds))
  }
}

// MARK: - Most listened (Library-Kartenlayout)

private enum StatsLibraryRowLayout {
  static let coverSide = AppTheme.Layout.libraryRowCoverSide
  static let cornerRadius = AppTheme.Layout.libraryRowCornerRadius
  static let cardInset = AppTheme.Layout.libraryRowCardInset
  static let textInset = AppTheme.Layout.libraryRowTextInset

  static var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  static var coverClipShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: cornerRadius,
      bottomLeadingRadius: cornerRadius,
      bottomTrailingRadius: 0,
      topTrailingRadius: 0,
      style: .continuous
    )
  }

  static var metadataMinHeight: CGFloat {
    coverSide - 2 * textInset
  }

  @ViewBuilder
  static func metadataColumn<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .frame(height: metadataMinHeight)
      .padding(.top, textInset)
      .padding(.trailing, textInset)
      .padding(.bottom, textInset)
  }

  @ViewBuilder
  static func coverSlot<Cover: View>(
    @ViewBuilder cover: () -> Cover,
    @ViewBuilder overlay: () -> some View = { EmptyView() }
  ) -> some View {
    cover()
      .frame(width: coverSide, height: coverSide)
      .clipShape(coverClipShape)
      .overlay(alignment: .bottomTrailing) {
        overlay()
      }
  }

  @ViewBuilder
  static func libraryRowCardChrome<Content: View>(
    openDetails: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: coverSide, alignment: .top)
    }
    .background(AppTheme.card)
    .clipShape(cardShape)
    .contentShape(cardShape)
    .onTapGesture(perform: openDetails)
  }
}

private struct StatsTopListenedAuthorLine: View {
  let authorLine: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text("Author")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
      let line = authorLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line == "—" {
        Text("—")
          .font(.footnote)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text(line)
          .font(.footnote)
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(0.88)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

private struct StatsTopListenedBookCard: View {
  @EnvironmentObject private var model: AppModel
  let rank: Int
  /// Schlüssel aus `listening-stats` `items` (kanonische Library-Item-ID).
  let lookupId: String
  let item: ABSListeningStatsItemAggregate

  @State private var showDetail = false

  private var libraryItemId: String {
    model.normalizedStatsLibraryItemId(lookupId)
  }

  private var book: ABSBook {
    model.bookForStatsNavigation(libraryItemId: lookupId, metadata: item.mediaMetadata)
  }

  private var authorLine: String {
    let fromStats = item.mediaMetadata?.displayAuthorLine.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !fromStats.isEmpty, fromStats != "—" { return fromStats }
    let fromCatalog = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return fromCatalog.isEmpty ? "—" : fromCatalog
  }

  var body: some View {
    StatsLibraryRowLayout.libraryRowCardChrome(openDetails: { showDetail = true }) {
      HStack(alignment: .top, spacing: StatsLibraryRowLayout.cardInset) {
        StatsLibraryRowLayout.coverSlot {
          CoverImageView(
            url: model.coverURL(for: book.id),
            token: model.token,
            itemId: book.id,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision
          )
        } overlay: {
          Text("\(rank)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(white: 0.2, opacity: 0.88))
            .clipShape(Capsule())
            .padding(4)
            .accessibilityLabel("Rank \(rank)")
        }
        .accessibilityHidden(true)

        StatsLibraryRowLayout.metadataColumn {
          VStack(alignment: .leading, spacing: 2) {
            Text(book.displayTitle)
              .font(.headline.weight(.semibold))
              .foregroundStyle(AppTheme.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            StatsTopListenedAuthorLine(authorLine: authorLine)
              .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
              Text(formatPlaybackDurationShortHuman(Double(item.timeListening)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppTheme.accent)
              Text("listened")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
              Spacer(minLength: 0)
            }
          }
          .padding(.trailing, 4)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint("Opens book details.")
    .navigationDestination(isPresented: $showDetail) {
      BookDetailView(bookId: libraryItemId)
    }
  }
}

private struct StatsRecentSessionCard: View {
  private static let sessionDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  @EnvironmentObject private var model: AppModel
  let session: ABSListeningStatsRecentSession

  @State private var showBookDetail = false
  @State private var episodeNav: ABSPodcastEpisodeListItem?

  private var podcastEpisode: ABSPodcastEpisodeListItem? {
    model.podcastEpisodeForStatsSession(session)
  }

  private var libraryItemId: String {
    model.normalizedStatsLibraryItemId(session.libraryItemId)
  }

  private var book: ABSBook {
    model.bookForStatsNavigation(libraryItemId: session.libraryItemId, metadata: nil)
  }

  private var titleLine: String {
    let fromSession = session.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !fromSession.isEmpty { return fromSession }
    return book.displayTitle
  }

  private var authorLine: String {
    let fromSession = session.displayAuthor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !fromSession.isEmpty { return fromSession }
    let fromCatalog = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return fromCatalog.isEmpty ? "—" : fromCatalog
  }

  private var startedAtCaption: String {
    guard session.startedAt > 0 else { return "" }
    return Self.sessionDateFormatter.string(
      from: Date(timeIntervalSince1970: TimeInterval(session.startedAt) / 1000.0)
    )
  }

  private func openSessionDetails() {
    if let episode = podcastEpisode {
      episodeNav = episode
    } else {
      showBookDetail = true
    }
  }

  var body: some View {
    StatsLibraryRowLayout.libraryRowCardChrome(openDetails: openSessionDetails) {
      HStack(alignment: .top, spacing: StatsLibraryRowLayout.cardInset) {
        StatsLibraryRowLayout.coverSlot {
          CoverImageView(
            url: model.coverURL(for: libraryItemId),
            token: model.token,
            itemId: libraryItemId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision
          )
        }

        StatsLibraryRowLayout.metadataColumn {
          VStack(alignment: .leading, spacing: 2) {
            Text(titleLine)
              .font(.headline.weight(.semibold))
              .foregroundStyle(AppTheme.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            StatsTopListenedAuthorLine(authorLine: authorLine)
              .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
              Text(formatPlaybackDurationShortHuman(Double(session.timeListening)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppTheme.accent)
              if !startedAtCaption.isEmpty {
                Text(startedAtCaption)
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.textSecondary)
                  .lineLimit(1)
                  .minimumScaleFactor(0.85)
              }
              Spacer(minLength: 0)
            }
          }
          .padding(.trailing, 4)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint(
      podcastEpisode != nil ? "Opens episode details." : "Opens book details."
    )
    .navigationDestination(isPresented: $showBookDetail) {
      BookDetailView(bookId: libraryItemId)
    }
    .navigationDestination(item: $episodeNav) { episode in
      PodcastEpisodeDetailView(episode: episode)
    }
  }
}
