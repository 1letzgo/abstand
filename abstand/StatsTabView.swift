import SwiftUI

// MARK: - Settings hub categories (Top 10 / Sessions detail links)


enum SettingsStatsCategory: String, CaseIterable, Identifiable {
  case topListened = "Top 10"
  case sessions = "Sessions"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .topListened: return "list.star"
    case .sessions: return "play.circle.fill"
    }
  }

  var subtitle: String {
    switch self {
    case .topListened: return "Most listened titles"
    case .sessions: return "Recent playback sessions"
    }
  }

  @ViewBuilder
  var detailView: some View {
    switch self {
    case .topListened: StatsTopListenedDetailView()
    case .sessions: StatsSessionsDetailView()
    }
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
  var showsTitle: Bool = true
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: showsTitle ? AppTheme.Layout.withinSectionSpacing : 0) {
      if showsTitle {
        TabContentSectionTitle(title: title)
      }
      content()
    }
  }
}

// MARK: - Shared stats layout

private enum StatsLayout {
  static let statsLocale = Locale(identifier: "en_US")
  static let statsCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2 // Montag
    cal.locale = statsLocale
    return cal
  }()

  static let cacheDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = statsLocale
    f.dateStyle = .short
    f.timeStyle = .short
    return f
  }()

  /// Level-Karten: 2 Spalten (iPhone), 4 auf iPad/`regular`-Breite.
  static func levelColumns(isRegularWidth: Bool) -> [GridItem] {
    let spacing = AppTheme.Layout.withinSectionSpacing
    let count = isRegularWidth ? 4 : 2
    return Array(
      repeating: GridItem(.flexible(), spacing: spacing),
      count: count
    )
  }

  /// Top-10-/Sessions-Listen: 1 Spalte (iPhone), 2 auf iPad/`regular`-Breite.
  static func detailListColumns(isRegularWidth: Bool) -> [GridItem] {
    let spacing = AppTheme.Layout.withinSectionSpacing
    if isRegularWidth {
      return [
        GridItem(.flexible(), spacing: spacing),
        GridItem(.flexible(), spacing: spacing),
      ]
    }
    return [GridItem(.flexible(), spacing: spacing)]
  }
}

/// Settings-Unterseiten: Scroll + Offline-Hinweis + Ladezustand.
struct StatsDetailScrollScreen<Content: View>: View {
  @EnvironmentObject private var model: AppModel
  @ViewBuilder let content: (ABSListeningStatsResponse) -> Content

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        if let fetched = model.listeningStatsFetchedAt, model.listeningStats != nil,
          !model.isNetworkReachable
        {
          StatsOfflineCacheBanner(fetchedAt: fetched)
        }

        if model.listeningStatsLoading, model.listeningStats == nil {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else if let stats = model.listeningStats {
          content(stats)
        } else if !model.isNetworkReachable {
          Text(
            "No saved statistics. Connect to the server to load and cache your listening data."
          )
          .font(.subheadline)
          .foregroundStyle(model.appearancePalette.textSecondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
        } else {
          Text("No statistics loaded.")
            .foregroundStyle(model.appearancePalette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom,
        AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset
      )
    }
    .abstandScrollScreenBackground(ignoreSafeArea: true)
    .refreshable { await model.loadListeningStats() }
  }
}

struct StatsOfflineCacheBanner: View {
  @EnvironmentObject private var model: AppModel
  let fetchedAt: Date

  var body: some View {
    let palette = model.appearancePalette
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "icloud.slash")
        .foregroundStyle(model.appearanceAccentColor)
      Text("Offline — cached \(StatsLayout.cacheDateFormatter.string(from: fetchedAt)).")
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
}

// MARK: - Settings detail views

struct StatsTopListenedDetailView: View {
  var body: some View {
    StatsDetailScrollScreen { stats in
      StatsTopListenedSectionView(stats: stats)
    }
  }
}

struct StatsSessionsDetailView: View {
  var body: some View {
    StatsDetailScrollScreen { stats in
      StatsSessionsSectionView(stats: stats)
    }
  }
}

// MARK: - Section content

struct StatsLevelSectionView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  var showsSectionTitle: Bool = true

  var body: some View {
    let levelAchievements = ListeningAchievementKind.sortedForDisplay(
      model.listeningAchievementsSnapshot.achievements
    )
    let columns = StatsLayout.levelColumns(isRegularWidth: horizontalSizeClass == .regular)
    return StatsContentSection(title: "Level", showsTitle: showsSectionTitle) {
      LazyVGrid(columns: columns, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(levelAchievements) { achievement in
          ListeningAchievementCard(achievement: achievement, compact: true)
        }
      }
    }
  }
}

struct StatsTimelineHubSectionView: View {
  @EnvironmentObject private var model: AppModel
  var showsSectionTitle: Bool = true

  var body: some View {
    StatsContentSection(title: "Timeline", showsTitle: showsSectionTitle) {
      if model.listeningStatsLoading, model.listeningStats == nil {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding(.vertical, 24)
      } else if let stats = model.listeningStats {
        ListeningMonthHeatmapCard(
          stats: stats,
          locale: StatsLayout.statsLocale,
          calendar: StatsLayout.statsCalendar
        )
      }
    }
  }
}

struct StatsTopListenedSectionView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  let stats: ABSListeningStatsResponse
  var showsSectionTitle: Bool = true

  var body: some View {
    let topItems = Array(stats.itemsSortedByListeningTime.prefix(10))
    let columns = StatsLayout.detailListColumns(isRegularWidth: horizontalSizeClass == .regular)
    return StatsContentSection(title: "Top 10", showsTitle: showsSectionTitle) {
      if topItems.isEmpty {
        Text("No listening history for individual titles yet.")
          .font(.subheadline)
          .foregroundStyle(model.appearancePalette.textSecondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
      } else {
        LazyVGrid(columns: columns, spacing: AppTheme.Layout.withinSectionSpacing) {
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
}

struct StatsSessionsSectionView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  let stats: ABSListeningStatsResponse
  var showsSectionTitle: Bool = true

  var body: some View {
    let sessions = stats.recentSessions
    let columns = StatsLayout.detailListColumns(isRegularWidth: horizontalSizeClass == .regular)
    return StatsContentSection(title: "Sessions", showsTitle: showsSectionTitle) {
      if sessions.isEmpty {
        Text("No listening sessions yet.")
          .font(.subheadline)
          .foregroundStyle(model.appearancePalette.textSecondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
      } else {
        LazyVGrid(columns: columns, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(sessions) { session in
            StatsRecentSessionCard(session: session)
          }
        }
      }
    }
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
      .overlay(alignment: .bottomLeading) {
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
          SquareCoverImageView(
            url: model.coverURL(for: book.id),
            token: model.token,
            itemId: book.id,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
          )
        } overlay: {
          Text("\(rank)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(model.appearancePalette.coverPlayBadgeBackground)
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
          SquareCoverImageView(
            url: model.coverURL(for: libraryItemId),
            token: model.token,
            itemId: libraryItemId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision(forBookId: libraryItemId)
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
