import SwiftUI
import UIKit

// MARK: - Home tab root

/// Eigener View-Typ — stabile Identität; Nav-Bar + Offline-Button überleben Bootstrap-Schritte.
struct HomeTabRootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    NavigationStack {
      ZStack {
        StartDashboardView()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .abstandTabScreenChrome()
      .abstandHomeTabNavigationTitle()
      .toolbar {
        HomeGoOfflineToolbarContent()
      }
      .task(id: "\(model.sessionUserId)-\(model.isAppBootstrapInProgress)") {
        guard !model.isAppBootstrapInProgress else { return }
        await model.probeServerConnectionIfNeeded()
      }
      .booksEntityDetailNavigation(for: .start)
    }
  }
}

/// Nav-Bar-Trailing — statischer Offline-Schalter.
struct HomeGoOfflineToolbarContent: ToolbarContent {
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      HomeGoOfflineToolbarButton()
    }
  }
}

struct HomeGoOfflineToolbarButton: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Button {
      model.homeGoOfflineToolbarTapped()
    } label: {
      Label {
        Text(buttonTitle)
      } icon: {
        Image(systemName: buttonIcon)
      }
      .labelStyle(.iconOnly)
    }
    .accessibilityLabel(buttonTitle)
    .accessibilityIdentifier("home-go-offline-toolbar-button")
  }

  private var buttonTitle: String {
    model.offlineHomeUIActive ? "Go online" : "Go offline"
  }

  private var buttonIcon: String {
    model.offlineHomeUIActive ? "icloud.slash" : "icloud"
  }
}

// MARK: - Home dashboard

struct StartDashboardView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    startDashboardOnlineLayout
      .abstandScrollScreenBackground()
      .onAppear {
        guard model.startShelves.isEmpty,
          !model.isAppBootstrapInProgress,
          !model.hasCachedBootstrapContent
        else { return }
        Task {
          if model.offlineHomeUIActive {
            await model.loadStartDashboard(force: true)
          } else {
            await model.loadStartDashboard()
          }
        }
      }
      .onChange(of: model.offlineHomeUIActive) { _, _ in
        guard !model.isAppBootstrapInProgress else { return }
        model.clampHomeBrowseSectionIfNeeded()
        Task { await model.loadStartDashboard(force: true) }
      }
  }

  // MARK: - Home tab

  private var startDashboardOnlineLayout: some View {
    let isRestoringContinue = model.isHomeContinueRestoreInProgress
    let continueID = ABSStartShelfLocalization.homeBrowseContinueSectionID
    // Kein Browse-Menü mehr — Stats ist eigener Tab; Home zeigt nur Dashboard-Inhalte.
    return AbstandFixedBrowseStripSectionsLayout(
      showsStrip: false,
      bottomInsetRevalidationTrigger: model.nowPlayingAccessoryScrollBottomInset,
      selection: continueID,
      sectionIDs: [continueID],
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      topScrollEdgeEffectStyle: .soft,
      onRefresh: { await model.refreshStartTabPullToRefresh() }
    ) {
      Color.clear
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    } sectionBody: { _ in
      if isRestoringContinue {
        homeBrowseContentBootstrapPlaceholder
      } else if !model.isAnyHomeBrowseContinueShelfEnabled {
        startDashboardAllShelvesDisabledState
          .frame(maxWidth: .infinity)
      } else {
        startDashboardContinueCombinedContent()
      }
    }
    .onAppear {
      model.homeBrowseCategory = continueID
      model.clampHomeBrowseSectionIfNeeded()
    }
    .onChange(of: model.startDisabledCategories) { _, _ in
      model.clampHomeBrowseSectionIfNeeded()
    }
    .onChange(of: model.startSettingsCategoryList.count) { _, _ in
      model.clampHomeBrowseSectionIfNeeded()
    }
  }

  /// Hält den Home-Inhalt kurz leer, bis alle lokal rekonstruierten Continue-Regale atomar vorliegen.
  private var homeBrowseContentBootstrapPlaceholder: some View {
    Color.clear
      .frame(maxWidth: .infinity, minHeight: 220)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private func startDashboardContinueCombinedContent() -> some View {
    let shelves = model.startShelves(
      forHomeBrowseSection: ABSStartShelfLocalization.homeBrowseContinueSectionID
    ).filter(startDashboardShelfHasVisibleContent)
    if shelves.isEmpty {
      startDashboardSectionEmptyState(category: ABSStartShelfLocalization.homeBrowseContinueSectionID)
    } else {
      VStack(alignment: .leading, spacing: AppTheme.Layout.homeSectionSpacing) {
        ForEach(shelves) { shelf in
          startDashboardShelfContent(shelf)
        }
      }
    }
  }

  private func startDashboardShelfHasVisibleContent(_ shelf: ABSStartShelfSection) -> Bool {
    shelf.hasBooks || shelf.hasPodcastEpisodes || shelf.hasSeries || shelf.hasAuthors
  }

  @ViewBuilder
  private func startDashboardShelfContent(_ shelf: ABSStartShelfSection) -> some View {
    if startDashboardIsContinueListeningShelf(shelf) {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        if shelf.hasBooks || shelf.hasPodcastEpisodes {
          startDashboardContinueListeningSection(shelf)
        }
        if shelf.hasAuthors {
          startDashboardCoverOnlyAuthorsSection(
            title: shelf.displayTitle,
            authors: shelf.authors
          )
        }
      }
    } else {
      // Alle anderen Settings-Regale: Cover-only horizontale Scroll-Reihen (wie Library „Cover only“).
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        TabContentSectionTitle(title: shelf.displayTitle)
        if shelf.hasBooks {
          HomeCoverOnlyBooksCarousel(
            books: shelf.books,
            usesEbookProgressDisplay: shelf.category == "continueEbooks"
          )
        }
        if shelf.hasSeries {
          HomeCoverOnlySeriesCarousel(series: shelf.series)
        }
        if shelf.hasAuthors {
          HomeCoverOnlyAuthorsCarousel(authors: shelf.authors)
        }
        if shelf.hasPodcastEpisodes {
          HomeCoverOnlyPodcastEpisodesCarousel(episodes: shelf.podcastEpisodes)
        }
      }
    }
  }

  @ViewBuilder
  private func startDashboardCoverOnlyAuthorsSection(
    title: String,
    authors: [ABSAuthorShelfEntity]
  ) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: title)
      HomeCoverOnlyAuthorsCarousel(authors: authors)
    }
  }

  private func startDashboardSectionEmptyState(category: String) -> some View {
    let label: String = {
      if category == ABSStartShelfLocalization.homeBrowseContinueSectionID {
        return ABSStartShelfLocalization.homeBrowseContinueStripLabel
      }
      if category == ABSStartShelfLocalization.homeBrowseRecentSectionID {
        return ABSStartShelfLocalization.homeBrowseRecentStripLabel
      }
      return model.startSettingsCategoryList.first { $0.category == category }?.label
        ?? ABSStartShelfLocalization.displayTitle(category: category, serverLabel: "")
    }()
    let description: String = {
      guard model.offlineHomeUIActive else {
        return "Content for this shelf appears when your server provides it."
      }
      return "Titles you're currently playing will appear here once downloaded."
    }()
    return ContentUnavailableView(
      label,
      systemImage: ABSStartShelfLocalization.stripSystemImage(category: category),
      description: Text(description)
    )
    .frame(maxWidth: .infinity)
    .padding(.top, AppTheme.Layout.sectionSpacing)
  }

  private func startDashboardIsContinueListeningShelf(_ shelf: ABSStartShelfSection) -> Bool {
    shelf.category == "recentlyListened"
  }

  @ViewBuilder
  private func startDashboardContinueListeningSection(_ shelf: ABSStartShelfSection) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: shelf.displayTitle)
      ContinueListeningHeroCarousel(shelf: shelf)
    }
  }

  private var startDashboardAllShelvesDisabledState: some View {
    ContentUnavailableView(
      "All shelves are off",
      systemImage: "gearshape.2",
      description: Text("Open Settings → Appearance → Home to turn shelves back on.")
    )
  }

}

// MARK: - Home Continue: Cover-only horizontal rows

private struct HomeShelfCoverViewportWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

/// Gemeinsame Viewport-Messung für Cover-only-Home-Regale (≈3 sichtbar).
private struct HomeCoverOnlyShelfScrollRow<Content: View>: View {
  @State private var viewportWidth: CGFloat = 0
  @ViewBuilder var content: (_ cardWidth: CGFloat) -> Content

  private var cardWidth: CGFloat {
    AppTheme.Layout.homeShelfCoverCardWidth(forViewportWidth: viewportWidth)
  }

  var body: some View {
    AbstandHorizontalBrowseStripScroll(
      appliesHorizontalContentInset: false,
      verticalContentPadding: 0
    ) {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        content(cardWidth)
      }
    }
    .frame(height: cardWidth)
    .background {
      GeometryReader { geo in
        Color.clear.preference(key: HomeShelfCoverViewportWidthKey.self, value: geo.size.width)
      }
    }
    .onPreferenceChange(HomeShelfCoverViewportWidthKey.self) { viewportWidth = $0 }
  }
}

private struct HomeCoverOnlyBooksCarousel: View {
  @EnvironmentObject private var model: AppModel
  let books: [ABSBook]
  var usesEbookProgressDisplay = false

  var body: some View {
    HomeCoverOnlyShelfScrollRow { cardWidth in
      ForEach(books) { book in
        LibraryBookListCard(
          book: book,
          model: model,
          showEbookBadge: model.bookShowsSupplementaryEbookBadge(book),
          showsPlaybackControls: false,
          opensDetailOnTap: true,
          usesEbookProgressDisplay: usesEbookProgressDisplay || book.isPureEbookLibraryItem,
          styleOverride: .coverOnly
        )
        .frame(width: cardWidth)
      }
    }
  }
}

private struct HomeCoverOnlySeriesCarousel: View {
  @EnvironmentObject private var model: AppModel
  let series: [ABSLibrarySeriesListItem]

  var body: some View {
    HomeCoverOnlyShelfScrollRow { cardWidth in
      ForEach(series) { item in
        HomeCoverOnlySeriesCard(series: item, cardWidth: cardWidth)
      }
    }
  }
}

private struct HomeCoverOnlySeriesCard: View {
  @EnvironmentObject private var model: AppModel
  let series: ABSLibrarySeriesListItem
  let cardWidth: CGFloat

  var body: some View {
    let bookIds = model.browseSeriesCoverBookIds(from: series.books)
    let coverId = bookIds.first
    let clip = RoundedRectangle(
      cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius,
      style: .continuous
    )

    Button {
      model.openSeriesDetail(
        seriesId: series.id,
        displayName: series.name,
        numBooks: series.books?.count
      )
    } label: {
      Group {
        if let coverId {
          SquareCoverImageView(
            url: model.coverURL(for: coverId),
            token: model.token,
            itemId: coverId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision(forBookId: coverId)
          )
        } else {
          model.appearancePalette.card
        }
      }
      .frame(width: cardWidth, height: cardWidth)
      .clipShape(clip)
      .abstandHeroCardOutline(palette: model.appearancePalette)
      .contentShape(clip)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(series.name)
    .accessibilityHint("Opens series details.")
  }
}

private struct HomeCoverOnlyAuthorsCarousel: View {
  @EnvironmentObject private var model: AppModel
  let authors: [ABSAuthorShelfEntity]

  var body: some View {
    HomeCoverOnlyShelfScrollRow { cardWidth in
      ForEach(authors) { author in
        HomeCoverOnlyAuthorCard(author: author, cardWidth: cardWidth)
      }
    }
  }
}

private struct HomeCoverOnlyAuthorCard: View {
  @EnvironmentObject private var model: AppModel
  let author: ABSAuthorShelfEntity
  let cardWidth: CGFloat

  var body: some View {
    let clip = RoundedRectangle(
      cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius,
      style: .continuous
    )
    let cacheId = "author:\(author.id)"

    Button {
      model.openAuthorDetail(
        authorId: author.id,
        displayName: author.name,
        numBooks: author.numBooks
      )
    } label: {
      Group {
        if author.hasAuthorImage {
          SquareCoverImageView(
            url: model.authorImageURL(authorId: author.id),
            token: model.token,
            itemId: cacheId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: 0
          )
        } else {
          model.appearancePalette.card
            .overlay {
              Image(systemName: "person.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(model.appearancePalette.textSecondary)
            }
        }
      }
      .frame(width: cardWidth, height: cardWidth)
      .clipShape(clip)
      .abstandHeroCardOutline(palette: model.appearancePalette)
      .contentShape(clip)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(author.name)
    .accessibilityHint("Opens author details.")
  }
}

private struct HomeCoverOnlyPodcastEpisodesCarousel: View {
  @EnvironmentObject private var model: AppModel
  let episodes: [ABSPodcastEpisodeListItem]

  var body: some View {
    HomeCoverOnlyShelfScrollRow { cardWidth in
      ForEach(episodes) { episode in
        HomeCoverOnlyPodcastEpisodeCard(episode: episode, cardWidth: cardWidth)
      }
    }
  }
}

private struct HomeCoverOnlyPodcastEpisodeCard: View {
  @EnvironmentObject private var model: AppModel
  let episode: ABSPodcastEpisodeListItem
  let cardWidth: CGFloat
  @State private var showDetail = false

  var body: some View {
    let clip = RoundedRectangle(
      cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius,
      style: .continuous
    )
    let itemId = episode.libraryItemId

    Button {
      showDetail = true
    } label: {
      SquareCoverImageView(
        url: model.coverURL(for: itemId),
        token: model.token,
        itemId: itemId,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision(forBookId: itemId)
      )
      .frame(width: cardWidth, height: cardWidth)
      .clipShape(clip)
      .abstandHeroCardOutline(palette: model.appearancePalette)
      .contentShape(clip)
    }
    .buttonStyle(.plain)
    .navigationDestination(isPresented: $showDetail) {
      PodcastEpisodeDetailView(episode: episode)
    }
    .accessibilityLabel(episode.episodeTitle)
    .accessibilityHint("Opens episode details.")
  }
}
