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
    let stripIDs = model.homeBrowseStripCategoryIDs
    let layoutSectionIDs =
      stripIDs.isEmpty
      ? [ABSStartShelfLocalization.homeBrowseContinueSectionID]
      : stripIDs
    return AbstandFixedBrowseStripSectionsLayout(
      showsStrip: !isRestoringContinue,
      bottomInsetRevalidationTrigger: model.nowPlayingAccessoryScrollBottomInset,
      selection: model.homeBrowseCategory,
      sectionIDs: layoutSectionIDs,
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      topScrollEdgeEffectStyle: .soft,
      onRefresh: { await model.refreshStartTabPullToRefresh() }
    ) {
      if isRestoringContinue || stripIDs.isEmpty {
        homeBrowseStripBootstrapPlaceholder
      } else {
        homeBrowseSectionStrip
      }
    } sectionBody: { category in
      if isRestoringContinue {
        homeBrowseContentBootstrapPlaceholder
      } else if stripIDs.isEmpty {
        startDashboardAllShelvesDisabledState
          .frame(maxWidth: .infinity)
      } else {
        startDashboardSectionScrollContent(category: category)
      }
    }
    .onAppear { model.clampHomeBrowseSectionIfNeeded() }
    .onChange(of: model.startDisabledCategories) { _, _ in
      model.clampHomeBrowseSectionIfNeeded()
    }
    .onChange(of: model.startSettingsCategoryList.count) { _, _ in
      model.clampHomeBrowseSectionIfNeeded()
    }
    .task(id: model.homeBrowseCategory) {
      guard ABSStartShelfLocalization.isHomeBrowseStatsCategory(model.homeBrowseCategory) else { return }
      guard !model.offlineHomeUIActive else { return }
      model.prepareListeningAchievementsForStatsTab()
      await model.loadListeningStats()
    }
  }

  private var homeBrowseSectionStrip: some View {
    AbstandBrowseStripIconMenu(
      items: model.homeBrowseStripRows.map { row in
        AbstandBrowseStripItem(
          id: row.category,
          label: row.label,
          systemImage: ABSStartShelfLocalization.stripSystemImage(category: row.category)
        )
      },
      selectionID: model.homeBrowseCategory,
      onSelect: { model.selectHomeBrowseSection($0) }
    )
  }

  /// Leerer Strip bis Regale da sind — gleiche Layout-Höhe wie echter Strip (kein Nav-Bar-Relayout).
  private var homeBrowseStripBootstrapPlaceholder: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .accessibilityHidden(true)
  }

  /// Hält den Home-Inhalt kurz leer, bis alle lokal rekonstruierten Continue-Regale atomar vorliegen.
  private var homeBrowseContentBootstrapPlaceholder: some View {
    Color.clear
      .frame(maxWidth: .infinity, minHeight: 220)
      .accessibilityHidden(true)
  }

  private func startDashboardSectionScrollContent(category: String) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      if ABSStartShelfLocalization.isHomeBrowseStatsCategory(category) {
        HomeListeningStatsSectionView()
      } else if category == ABSStartShelfLocalization.homeBrowseContinueSectionID {
        startDashboardContinueCombinedContent()
      } else if category == ABSStartShelfLocalization.homeBrowseRecentSectionID {
        startDashboardRecentCombinedContent()
      } else if let shelf = model.startShelf(forCategory: category) {
        startDashboardShelfContent(shelf)
      } else {
        startDashboardSectionEmptyState(category: category)
      }
    }
  }

  @ViewBuilder
  private func startDashboardContinueCombinedContent() -> some View {
    let shelves = model.startShelves(
      forHomeBrowseSection: ABSStartShelfLocalization.homeBrowseContinueSectionID)
    if shelves.isEmpty {
      startDashboardSectionEmptyState(category: ABSStartShelfLocalization.homeBrowseContinueSectionID)
    } else {
      ForEach(shelves) { shelf in
        startDashboardShelfContent(shelf)
      }
    }
  }

  @ViewBuilder
  private func startDashboardRecentCombinedContent() -> some View {
    let shelves = model.startShelves(
      forHomeBrowseSection: ABSStartShelfLocalization.homeBrowseRecentSectionID)
    if shelves.isEmpty {
      startDashboardSectionEmptyState(category: ABSStartShelfLocalization.homeBrowseRecentSectionID)
    } else {
      ForEach(shelves) { shelf in
        startDashboardShelfContent(shelf)
      }
    }
  }

  @ViewBuilder
  private func startDashboardShelfContent(_ shelf: ABSStartShelfSection) -> some View {
    let continueSplit =
      startDashboardIsContinueShelf(shelf) && (shelf.hasBooks || shelf.hasPodcastEpisodes)
    if continueSplit {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        if shelf.hasBooks || shelf.hasPodcastEpisodes {
          startDashboardContinueListeningSection(shelf)
        }
        if shelf.hasAuthors {
          VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
            TabContentSectionTitle(title: shelf.displayTitle)
            startDashboardAuthorsContent(shelf.authors)
          }
        }
      }
    } else {
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        if shelf.hasBooks || shelf.hasAuthors || shelf.hasSeries || shelf.hasPodcastEpisodes {
          TabContentSectionTitle(title: shelf.displayTitle)
        }
        if shelf.hasSeries {
          startDashboardSeriesContent(shelf.series)
        }
        if shelf.hasBooks {
          ForEach(shelf.books) { book in
            if shelf.category == "continueEbooks" {
              LibraryBookListCard(
                book: book,
                model: model,
                showEbookBadge: true,
                showsPlaybackControls: false,
                forceCompactListStyle: true,
                usesEbookProgressDisplay: true,
                onOpen: {
                  Task { await model.openAttachedEbook(for: book) }
                }
              )
            } else {
              LibraryBookListCard(
                book: book,
                model: model,
                showEbookBadge: model.bookShowsSupplementaryEbookBadge(book),
                forceCompactListStyle: true
              )
            }
          }
        }
        if shelf.hasAuthors {
          startDashboardAuthorsContent(shelf.authors)
        }
      }
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
      if category == ABSStartShelfLocalization.homeBrowseDownloadedSectionID {
        return "Offline mode only shows titles you have downloaded. Go back online to download more."
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

  private func startDashboardIsContinueShelf(_ shelf: ABSStartShelfSection) -> Bool {
    shelf.category == "recentlyListened"
  }

  @ViewBuilder
  private func startDashboardContinueListeningSection(_ shelf: ABSStartShelfSection) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: shelf.displayTitle)
      ContinueListeningHeroCarousel(shelf: shelf)
    }
  }

  @ViewBuilder
  private func startDashboardSeriesContent(_ series: [ABSLibrarySeriesListItem]) -> some View {
    ForEach(series) { item in
      startDashboardSeriesRow(item)
    }
  }

  private func startDashboardSeriesRow(_ series: ABSLibrarySeriesListItem) -> some View {
    Button {
      model.openSeriesDetail(
        seriesId: series.id,
        displayName: series.name,
        numBooks: series.books?.count)
    } label: {
      let placeholder = "series-ph:\(series.id)"
      let bookIds = model.browseSeriesCoverBookIds(from: series.books)
      BrowseEntityRowCard(
        title: series.name,
        detailLabel: "Books",
        detailValue: browseEntityBooksCountLine(count: series.books?.count),
        cacheItemId: bookIds.first ?? placeholder,
        coverURL: bookIds.first.flatMap { model.coverURL(for: $0) },
        coverBookIds: bookIds.count > 1 ? bookIds : nil,
        authorLine: series.cardAuthorsLine
      )
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func startDashboardAuthorsContent(_ authors: [ABSAuthorShelfEntity]) -> some View {
    ForEach(authors) { author in
      startDashboardAuthorRow(author)
    }
  }

  private func startDashboardAuthorRow(_ author: ABSAuthorShelfEntity) -> some View {
    Button {
      model.openAuthorDetail(authorId: author.id, displayName: author.name, numBooks: author.numBooks)
    } label: {
      BrowseEntityRowCard(
        title: author.name,
        detailLabel: "Books",
        detailValue: browseEntityBooksCountLine(count: author.numBooks),
        cacheItemId: "author:\(author.id)",
        coverURL: author.hasAuthorImage ? model.authorImageURL(authorId: author.id) : nil,
        usesSquareCenterCropCover: true
      )
    }
    .buttonStyle(.plain)
  }

  private var startDashboardAllShelvesDisabledState: some View {
    ContentUnavailableView(
      "All shelves are off",
      systemImage: "gearshape.2",
      description: Text("Open Settings → Appearance → Home to turn shelves back on.")
    )
  }

}
