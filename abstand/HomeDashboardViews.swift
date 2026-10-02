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
      .task(
        id: "\(model.offlineHomeUIActive)-\(model.sessionUserId)-\(model.isAppBootstrapInProgress)-\(model.hasCachedBootstrapContent)"
      ) {
        guard model.startShelves.isEmpty,
          !model.isAppBootstrapInProgress,
          !model.hasCachedBootstrapContent
        else { return }
        if model.offlineHomeUIActive {
          await model.loadStartDashboard(force: true)
        } else {
          await model.loadStartDashboard()
        }
      }
      .onChange(of: model.offlineHomeUIActive) { _, _ in
        guard !model.isAppBootstrapInProgress else { return }
        model.clampHomeBrowseSectionIfNeeded()
        // Dashboard-Reload steuert allein die Mode-Transition im Model — kein paralleles force-Load.
      }
  }

  // MARK: - Home tab

  private var startDashboardOnlineLayout: some View {
    let isRestoringContinue = model.isHomeContinueRestoreInProgress
    let continueID = ABSStartShelfLocalization.homeBrowseContinueSectionID
    // Kein Browse-Menü mehr — Stats liegt in Settings; Home zeigt nur Dashboard-Inhalte.
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
      .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.homeBrowseBootstrapMinHeight)
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
          startDashboardAuthorsSection(
            title: shelf.displayTitle,
            authors: shelf.authors
          )
        }
      }
    } else {
      // Alle anderen Settings-Regale: Kompaktkarten (≈ 3/4 Breite), ohne Play — nur Link zur Detailseite.
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        TabContentSectionTitle(title: shelf.displayTitle)
        if shelf.hasBooks {
          HomeBooksCompactCarousel(
            books: shelf.books,
            usesEbookProgressDisplay: shelf.category == "continueEbooks"
          )
        }
        if shelf.hasSeries {
          HomeSeriesCompactCarousel(series: shelf.series)
        }
        if shelf.hasAuthors {
          HomeAuthorsCompactCarousel(authors: shelf.authors)
        }
        if shelf.hasPodcastEpisodes {
          HomePodcastEpisodesCompactCarousel(episodes: shelf.podcastEpisodes)
        }
      }
    }
  }

  @ViewBuilder
  private func startDashboardAuthorsSection(
    title: String,
    authors: [ABSAuthorShelfEntity]
  ) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: title)
      HomeAuthorsCoverCardCarousel(authors: authors)
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

// MARK: - Home: Cover-Card-Reihen (einheitlich wie „New episodes“)

private struct HomeShelfCoverViewportWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

/// Gemeinsames Karussell aller Home-Regale: gleiche Kartenbreite wie „New episodes“
/// (Compact 2¼ sichtbar, Regular +2; Max-Breite gegen iPad-Riesenkarten).
/// Keine feste Zeilenhöhe — sonst wird das 1:1-Cover gestaucht (`aspectRatio(.fit)`).
private struct HomeCoverCardCarousel<Item: Identifiable, Card: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  let items: [Item]
  @ViewBuilder let card: (Item) -> Card
  @State private var viewportWidth: CGFloat = 0

  private var cardWidth: CGFloat {
    AppTheme.Layout.homeNewestEpisodesCardWidth(
      forViewportWidth: viewportWidth,
      horizontalSizeClass: horizontalSizeClass
    )
  }

  var body: some View {
    AbstandHorizontalBrowseStripScroll(
      appliesHorizontalContentInset: false,
      verticalContentPadding: 0
    ) {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(items) { item in
          card(item)
            .frame(width: cardWidth)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    // Mindesthöhe vorab (Cover + Textblock) — sonst springt das Regal, sobald die Breite gemessen ist.
    .frame(minHeight: cardWidth + AppTheme.Layout.libraryHeroMetadataBlockHeight, alignment: .top)
    .background {
      GeometryReader { geo in
        Color.clear.preference(key: HomeShelfCoverViewportWidthKey.self, value: geo.size.width)
      }
    }
    .onPreferenceChange(HomeShelfCoverViewportWidthKey.self) { viewportWidth = $0 }
  }
}

// MARK: - Home: Kompaktkarten-Reihen

/// Karussell der Kompaktkarten: Karte ≈ 3/4 der Regalbreite, Scrollverhalten und Abstände wie bei den
/// Cover-Cards. Feste Mindesthöhe (Cover-Seite) — das Regal springt nicht, sobald die Breite gemessen ist.
private struct HomeCompactCardCarousel<Item: Identifiable, Card: View>: View {
  let items: [Item]
  @ViewBuilder let card: (Item) -> Card
  @State private var viewportWidth: CGFloat = 0

  private var cardWidth: CGFloat {
    AppTheme.Layout.homeCompactCardWidth(forViewportWidth: viewportWidth)
  }

  var body: some View {
    AbstandHorizontalBrowseStripScroll(
      appliesHorizontalContentInset: false,
      verticalContentPadding: 0
    ) {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(items) { item in
          card(item)
            .frame(width: cardWidth)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(minHeight: AppTheme.Layout.homeCompactCardCoverSide, alignment: .top)
    .background {
      GeometryReader { geo in
        Color.clear.preference(key: HomeShelfCoverViewportWidthKey.self, value: geo.size.width)
      }
    }
    .onPreferenceChange(HomeShelfCoverViewportWidthKey.self) { viewportWidth = $0 }
  }
}

private struct HomeBooksCompactCarousel: View {
  @EnvironmentObject private var model: AppModel
  let books: [ABSBook]
  var usesEbookProgressDisplay = false

  var body: some View {
    HomeCompactCardCarousel(items: books) { book in
      HomeBookCompactCard(book: book, model: model, usesEbookProgressDisplay: usesEbookProgressDisplay)
    }
  }
}

private struct HomePodcastEpisodesCompactCarousel: View {
  @EnvironmentObject private var model: AppModel
  let episodes: [ABSPodcastEpisodeListItem]

  var body: some View {
    HomeCompactCardCarousel(items: episodes) { episode in
      HomeEpisodeCompactCard(episode: episode, model: model)
    }
  }
}

private struct HomeSeriesCompactCarousel: View {
  @EnvironmentObject private var model: AppModel
  let series: [ABSLibrarySeriesListItem]

  var body: some View {
    HomeCompactCardCarousel(items: series) { item in
      let coverId = model.browseSeriesCoverBookIds(from: item.books).first
      let count = item.books?.count ?? 0
      let authors = item.cardAuthorsLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      HomeEntityCompactCard(
        title: item.name,
        subtitleLabel: authors.isEmpty ? "Books" : "Author",
        subtitle: authors.isEmpty ? (count > 0 ? "\(count)" : "—") : authors,
        footer: count > 0 ? (count == 1 ? "1 book" : "\(count) books") : "",
        accessibilityHint: "Opens series details."
      ) {
        if let coverId {
          SquareCoverImageView(
            url: model.coverURL(for: coverId),
            token: model.token,
            itemId: coverId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision(forBookId: coverId)
          )
        } else {
          HomeEntityCoverPlaceholder(systemImage: "books.vertical.fill")
        }
      } onOpen: {
        model.openSeriesDetail(
          seriesId: item.id,
          displayName: item.name,
          numBooks: item.books?.count
        )
      }
    }
  }
}

private struct HomeAuthorsCompactCarousel: View {
  @EnvironmentObject private var model: AppModel
  let authors: [ABSAuthorShelfEntity]

  var body: some View {
    HomeCompactCardCarousel(items: authors) { author in
      HomeEntityCompactCard(
        title: author.name,
        subtitleLabel: "Books",
        subtitle: author.numBooks.map { "\($0)" } ?? "—",
        footer: author.numBooks.map { $0 == 1 ? "1 book" : "\($0) books" } ?? "",
        accessibilityHint: "Opens author details."
      ) {
        if author.hasAuthorImage {
          SquareCoverImageView(
            url: model.authorImageURL(authorId: author.id),
            token: model.token,
            itemId: "author:\(author.id)",
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: 0
          )
        } else {
          HomeEntityCoverPlaceholder(systemImage: "person.fill")
        }
      } onOpen: {
        model.openAuthorDetail(
          authorId: author.id,
          displayName: author.name,
          numBooks: author.numBooks
        )
      }
    }
  }
}

/// Serie/Autor als Kompaktkarte: Cover links, Name (eine Zeile), Metazeile, Buchanzahl unten.
private struct HomeEntityCompactCard<Cover: View>: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  let subtitleLabel: String
  let subtitle: String
  let footer: String
  let accessibilityHint: String
  @ViewBuilder let cover: () -> Cover
  let onOpen: () -> Void

  var body: some View {
    HomeCompactCard(
      title: title,
      subtitleLabel: subtitleLabel,
      subtitle: subtitle,
      accessibilityHint: accessibilityHint,
      cover: cover,
      footer: {
        if !footer.isEmpty {
          Text(footer)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(model.appearancePalette.textSecondary)
            .lineLimit(1)
        }
      },
      badges: { EmptyView() },
      onOpen: onOpen
    )
  }
}

private struct HomeAuthorsCoverCardCarousel: View {
  @EnvironmentObject private var model: AppModel
  let authors: [ABSAuthorShelfEntity]

  var body: some View {
    HomeCoverCardCarousel(items: authors) { author in
      HomeEntityCoverCard(
        title: author.name,
        detailLabel: "Books",
        detailValue: author.numBooks.map { "\($0)" } ?? "—",
        accessibilityHint: "Opens author details."
      ) {
        if author.hasAuthorImage {
          SquareCoverImageView(
            url: model.authorImageURL(authorId: author.id),
            token: model.token,
            itemId: "author:\(author.id)",
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: 0
          )
        } else {
          HomeEntityCoverPlaceholder(systemImage: "person.fill")
        }
      } onOpen: {
        model.openAuthorDetail(
          authorId: author.id,
          displayName: author.name,
          numBooks: author.numBooks
        )
      }
    }
  }
}

private struct HomeEntityCoverPlaceholder: View {
  @EnvironmentObject private var model: AppModel
  let systemImage: String

  var body: some View {
    model.appearancePalette.card
      .overlay {
        Image(systemName: systemImage)
          .font(.title2.weight(.semibold))
          .foregroundStyle(model.appearancePalette.textSecondary)
      }
  }
}

/// Serie/Autor im Aufbau der Hero-Cover-Card (Buch/Folge): 1:1-Cover oben, Titel + Metazeile darunter —
/// ohne Play-Pille, Höhe wie die eBook-Variante der Buchkarte.
private struct HomeEntityCoverCard<Cover: View>: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  let detailLabel: String
  let detailValue: String
  let accessibilityHint: String
  @ViewBuilder let cover: () -> Cover
  let onOpen: () -> Void

  var body: some View {
    let palette = model.appearancePalette
    let coverTopRadius = AppTheme.Layout.coverCornerRadius
    let coverClip = UnevenRoundedRectangle(
      topLeadingRadius: coverTopRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: coverTopRadius,
      style: .continuous
    )
    let cardShape = RoundedRectangle(
      cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius,
      style: .continuous
    )

    Button(action: onOpen) {
      VStack(alignment: .leading, spacing: 0) {
        Color.clear
          .aspectRatio(1, contentMode: .fit)
          .frame(maxWidth: .infinity)
          .overlay { cover() }
          .clipShape(coverClip)

        ContinueListeningHeroMetadataBlock(
          title: title,
          detailLabel: detailLabel,
          detailValue: detailValue,
          horizontalInset: AppTheme.Layout.libraryRowCardInset,
          onTitleTap: onOpen,
          includesBottomPadding: true,
          blockHeight: AppTheme.Layout.libraryHeroMetadataBlockHeight
        )
      }
      .background(palette.card)
      .clipShape(cardShape)
      .abstandHeroCardOutline(palette: palette)
      .contentShape(cardShape)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityHint(accessibilityHint)
  }
}
