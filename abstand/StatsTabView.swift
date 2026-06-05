import Charts
import SwiftUI

private enum StatsBrowseSection: String, CaseIterable, Identifiable {
  case level = "Level"
  case mostListened = "Top 10"
  case listening = "Listening"
  case calendar = "Timeline"
  case recentSessions = "Sessions"

  var id: String { rawValue }

  static let stripOrder: [StatsBrowseSection] = [
    .level, .listening, .calendar, .mostListened, .recentSessions,
  ]

  var systemImage: String {
    switch self {
    case .level: return "medal.fill"
    case .mostListened: return "list.star"
    case .listening: return "clock.fill"
    case .calendar: return "calendar"
    case .recentSessions: return "play.circle.fill"
    }
  }
}

private struct StatsBrowseSectionStrip: View {
  @EnvironmentObject private var model: AppModel
  let selection: StatsBrowseSection
  let onSelect: (StatsBrowseSection) -> Void

  var body: some View {
    AbstandBrowseStripIconMenu(
      items: StatsBrowseSection.stripOrder.map {
        AbstandBrowseStripItem(id: $0.rawValue, label: $0.rawValue, systemImage: $0.systemImage)
      },
      selectionID: selection.rawValue,
      onSelect: { id in
        if let section = StatsBrowseSection(rawValue: id) {
          onSelect(section)
        }
      }
    )
  }
}

/// Mehrere Listenzeilen in einer Karte (wie Settings), ohne Abstand zwischen den Zeilen.
private struct StatsGroupedListCard<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    AbstandGroupedCard(horizontalPadding: 0, verticalPadding: 0, content: content)
  }
}

private struct StatsListRowDivider: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Divider().overlay(model.appearancePalette.textSecondary.opacity(0.25))
  }
}

private extension View {
  func statsListRowFrame(alignment: Alignment = .leading) -> some View {
    abstandCardListRowFrame(alignment: alignment)
  }
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
  @State private var browseSection: StatsBrowseSection = .level

  private static let statsLocale = Locale(identifier: "en_US")
  private static let periodColumns = [
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
    Group {
      if model.listeningStats != nil {
        AbstandFixedBrowseStripSectionsLayout(
          selection: browseSection,
          sectionIDs: StatsBrowseSection.stripOrder,
          scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
            + model.nowPlayingAccessoryScrollBottomInset,
          onRefresh: { await model.loadListeningStats() }
        ) {
          StatsBrowseSectionStrip(selection: browseSection) { browseSection = $0 }
        } sectionBody: { section in
          statsSectionScrollBody(section: section)
        }
      } else {
        AbstandFixedBrowseStripTabLayout(
          showsStrip: false,
          scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
            + model.nowPlayingAccessoryScrollBottomInset,
          onRefresh: { await model.loadListeningStats() }
        ) {
          EmptyView()
        } scrollBody: {
          statsLoadingScrollBody
        }
      }
    }
    .tint(model.appearanceAccentColor)
    .task {
      model.prepareListeningAchievementsForStatsTab()
      await model.loadListeningStats()
    }
  }

  private var statsLoadingScrollBody: some View {
    let palette = model.appearancePalette
    return LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      if model.listeningStatsLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding(.vertical, 48)
      } else if !model.isNetworkReachable {
        Text(
          "No saved statistics. Connect to the server to load and cache your listening data."
        )
        .font(.subheadline)
        .foregroundStyle(palette.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
      } else {
        Text("No statistics loaded.")
          .foregroundStyle(palette.textSecondary)
      }
    }
  }

  @ViewBuilder
  private func statsSectionScrollBody(section: StatsBrowseSection) -> some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      if let fetched = model.listeningStatsFetchedAt, model.listeningStats != nil,
        !model.isNetworkReachable
      {
        cacheOfflineBanner(fetchedAt: fetched)
      }

      if let stats = model.listeningStats {
        statsSectionContent(stats, section: section)
      }
    }
  }

  private func cacheOfflineBanner(fetchedAt: Date) -> some View {
    let palette = model.appearancePalette
    return HStack(alignment: .top, spacing: 10) {
      Image(systemName: "icloud.slash")
        .foregroundStyle(model.appearanceAccentColor)
      Text("Offline — cached \(Self.cacheDateFormatter.string(from: fetchedAt)).")
        .font(.caption)
        .foregroundStyle(palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }

  @ViewBuilder
  private func statsSectionContent(_ stats: ABSListeningStatsResponse, section: StatsBrowseSection) -> some View {
    switch section {
    case .level:
      statsLevelSection
    case .mostListened:
      statsTopListenedSection(stats)
    case .listening:
      statsListeningSection(stats)
    case .calendar:
      statsCalendarSection(stats)
    case .recentSessions:
      statsRecentSessionsSection(stats)
    }
  }

  // MARK: - Listing

  private func statsListeningTimeSection(_ stats: ABSListeningStatsResponse) -> some View {
    StatsContentSection(title: "Listening time") {
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        totalHero(stats)
        LazyVGrid(columns: Self.periodColumns, spacing: AppTheme.Layout.withinSectionSpacing) {
          summaryPeriodCard(title: "Today", seconds: stats.today)
          summaryPeriodCard(title: "7 days", seconds: stats.secondsInLastDays(7))
          summaryPeriodCard(title: "Month", seconds: stats.secondsThisCalendarMonth())
          summaryPeriodCard(title: "Year", seconds: stats.secondsThisCalendarYear())
          summaryPeriodCard(title: "Daily average", seconds: stats.dailyAverageSeconds)
        }
      }
    }
  }

  private var statsLevelSection: some View {
    let levelAchievements = ListeningAchievementKind.sortedForDisplay(
      model.listeningAchievementsSnapshot.achievements
    )
    return StatsContentSection(title: "Level") {
      LazyVGrid(columns: Self.periodColumns, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(levelAchievements) { achievement in
          ListeningAchievementCard(achievement: achievement, compact: true)
        }
      }
    }
  }

  // MARK: - Top listened

  private func statsTopListenedSection(_ stats: ABSListeningStatsResponse) -> some View {
    let topItems = Array(stats.itemsSortedByListeningTime.prefix(10))
    return StatsContentSection(title: "Top 10") {
      if topItems.isEmpty {
        Text("No listening history for individual titles yet.")
          .font(.subheadline)
          .foregroundStyle(model.appearancePalette.textSecondary)
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
    let palette = model.appearancePalette
    let daysApprox = stats.totalTimeAsCalendarDaysApprox
    let daysLabel = String(format: "%.1f", locale: Self.statsLocale, daysApprox)
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "headphones.circle.fill")
          .font(.system(size: 44))
          .foregroundStyle(model.appearanceAccentColor)
        VStack(alignment: .leading, spacing: 6) {
          Text(formatStatsCompact(stats.totalTime))
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(palette.textPrimary)
            .minimumScaleFactor(0.7)
            .lineLimit(2)
          Text("About \(daysLabel) days of audio")
            .font(.subheadline)
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(palette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }

  /// Kompakte Stat-Karte: zwei Zeilen (Titel oben, Wert unten); optional Icon links.
  private func statsMetricCard(
    icon: String? = nil,
    tint: Color? = nil,
    title: String,
    value: String,
    uppercaseTitle: Bool = false,
    valueFont: Font = .headline.weight(.bold)
  ) -> some View {
    let palette = model.appearancePalette
    let resolvedTint = tint ?? model.appearanceAccentColor
    let textColumn = VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
        .textCase(uppercaseTitle ? .uppercase : nil)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
      Text(value)
        .font(valueFont)
        .foregroundStyle(palette.textPrimary)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }

    return Group {
      if let icon {
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(resolvedTint)
            .frame(width: 26, alignment: .center)
          textColumn
          Spacer(minLength: 0)
        }
      } else {
        textColumn
      }
    }
    .statsListRowFrame()
    .padding(.horizontal, AppTheme.Layout.settingsCardInsetHPadding)
    .padding(.vertical, AppTheme.Layout.settingsCardInsetVPadding)
    .background(palette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }

  private func summaryPeriodCard(title: String, seconds: Int) -> some View {
    statsMetricCard(
      title: title,
      value: formatStatsCompact(seconds),
      uppercaseTitle: true
    )
  }

  // MARK: - Listening

  private func statsListeningSection(_ stats: ABSListeningStatsResponse) -> some View {
    let weekdayBars = stats.dayOfWeekBars(calendar: Self.statsCalendar, locale: Self.statsLocale)
    return VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      statsListeningTimeSection(stats)

      if weekdayBars.contains(where: { $0.seconds > 0 }) {
        StatsContentSection(title: "By weekday") {
          weekdayBarChartCard(bars: weekdayBars)
        }
      }
    }
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
        .foregroundStyle(model.appearanceAccentColor.gradient)
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
    .background(model.appearancePalette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }

  // MARK: - Timeline

  private func statsCalendarSection(_ stats: ABSListeningStatsResponse) -> some View {
    StatsContentSection(title: "Timeline") {
      ListeningMonthHeatmapCard(stats: stats, locale: Self.statsLocale, calendar: Self.statsCalendar)
    }
  }

  // MARK: - Sessions

  private func statsRecentSessionsSection(_ stats: ABSListeningStatsResponse) -> some View {
    let sessions = stats.recentSessions
    return StatsContentSection(title: "Sessions") {
      if sessions.isEmpty {
        Text("No listening sessions yet.")
          .font(.subheadline)
          .foregroundStyle(model.appearancePalette.textSecondary)
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

  // MARK: - Formatting

  private func formatStatsCompact(_ seconds: Int) -> String {
    formatPlaybackDurationShortHuman(Double(seconds))
  }
}

// MARK: - Top 10 (Library-Kartenlayout)

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
    cardColor: Color,
    openDetails: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: coverSide, alignment: .top)
    }
    .background(cardColor)
    .clipShape(cardShape)
    .contentShape(cardShape)
    .onTapGesture(perform: openDetails)
  }
}

private struct StatsTopListenedAuthorLine: View {
  @EnvironmentObject private var model: AppModel
  let authorLine: String

  var body: some View {
    let palette = model.appearancePalette
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text("Author")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
      let line = authorLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line == "—" {
        Text("—")
          .font(.footnote)
          .foregroundStyle(palette.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text(line)
          .font(.footnote)
          .foregroundStyle(palette.textPrimary)
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
    StatsLibraryRowLayout.libraryRowCardChrome(
      cardColor: model.appearancePalette.card,
      openDetails: { showDetail = true }
    ) {
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
              .foregroundStyle(model.appearancePalette.textPrimary)
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
                .foregroundStyle(model.appearanceAccentColor)
              Text("listened")
                .font(.subheadline)
                .foregroundStyle(model.appearancePalette.textSecondary)
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
    StatsLibraryRowLayout.libraryRowCardChrome(
      cardColor: model.appearancePalette.card,
      openDetails: openSessionDetails
    ) {
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
              .foregroundStyle(model.appearancePalette.textPrimary)
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
                .foregroundStyle(model.appearanceAccentColor)
              if !startedAtCaption.isEmpty {
                Text(startedAtCaption)
                  .font(.subheadline)
                  .foregroundStyle(model.appearancePalette.textSecondary)
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
