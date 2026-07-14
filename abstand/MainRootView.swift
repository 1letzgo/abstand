import Combine
import SwiftUI

struct MainRootView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @StateObject private var booksLibraryToolbarState = BooksLibraryToolbarState()
  @StateObject private var podcastCatalogToolbarState = PodcastCatalogToolbarState()
  /// Tabs erst bei erstem Besuch aufbauen — Home sofort, Rest lazy (Prewarm nach Bootstrap).
  @State private var activatedTabs: Set<AppModel.MainTab> = [.start]
  @State private var libraryRelayoutEpoch = 0
  @State private var podcastsRelayoutEpoch = 0

  var body: some View {
    let _ = model.appearanceThemeRevision
    return tabViewBody
      .tint(model.appearanceAccentColor)
      .themeAccentFromAppModel(model)
      .background {
        AppThemeScreenBackground(ignoresSafeArea: true)
      }
    // Selbstheilung: Sollte dieser View je seine Strukturidentität verlieren (alle `@State`
    // zurückgesetzt, `activatedTabs` wieder `[.start]`), den gerade sichtbaren Tab sofort
    // reaktivieren — sonst rendert `lazyTabContent` für ihn dauerhaft `Color.clear` (weißer
    // Screen), weil `.onChange(of: model.mainTab)` ohne Tab-Wechsel nie feuert.
    .onAppear {
      activatedTabs.insert(model.mainTab)
      if model.shouldPrewarmSecondaryTabs {
        activatedTabs.formUnion([.library, .settings])
      }
    }
    .fullScreenCover(item: $model.ebookReaderSession) { session in
      ReadiumReaderView(
        title: session.title,
        author: session.author,
        libraryItemId: session.libraryItemId,
        localFileURL: session.localFileURL,
        format: session.format,
        serverResumeProgression: session.serverResumeProgression
      )
      .themeAccentFromAppModel(model)
      .tint(model.appearanceAccentColor)
    }
    .onReceive(model.player.$isPlaying.dropFirst()) { playing in
      guard !playing else { return }
      Task { await model.handlePlaybackPaused() }
    }
    .onChange(of: model.mainTab) { oldTab, tab in
      activatedTabs.insert(tab)
      // Beim Wechsel vom Library-Tab zum Search-Tab: Suchkontext merken
      // (audiobooks vs podcasts), damit der Search-Tab die richtige Suche zeigt.
      if tab == .search, oldTab == .library {
        model.searchTabMediaKind = model.mediaCatalogKind
      }
      switch tab {
      case .library:
        bumpActiveMediaRelayoutEpoch()
      default:
        break
      }
      if tab == .start, model.startShelves.isEmpty {
        Task { await model.loadStartDashboard() }
      }
    }
    .onChange(of: model.shouldPrewarmSecondaryTabs) { _, prewarm in
      guard prewarm else { return }
      activatedTabs.formUnion([.library, .settings])
    }
    .onChange(of: model.ebookReaderSession?.libraryItemId) { _, newId in
      if newId == nil {
        model.refreshEbookContinueReadingShelf()
        model.flushEbookProgressSync()
      }
    }
    .onChange(of: model.selectedBooksLibrary?.id) { _, _ in
      model.clampMediaCatalogKindIfNeeded()
      if model.visibleMediaCatalogKinds.isEmpty, model.mainTab == .library {
        model.mainTab = .start
      }
    }
    .onChange(of: model.selectedPodcastLibrary?.id) { _, _ in
      model.clampMediaCatalogKindIfNeeded()
    }
    .onChange(of: model.showPodcastsTab) { _, _ in
      model.clampMediaCatalogKindIfNeeded()
    }
    .onChange(of: model.mediaCatalogKind) { _, _ in
      bumpActiveMediaRelayoutEpoch()
    }
    .onChange(of: model.accountSessionEpoch) { _, _ in
      activatedTabs = [.start]
      libraryRelayoutEpoch += 1
      podcastsRelayoutEpoch += 1
      booksLibraryToolbarState.resetForAccountSwitch()
      podcastCatalogToolbarState.resetForAccountSwitch()
    }
    .onChange(of: model.nowPlayingSheetDismissCounter) { _, _ in
      // UIKit-Overlay-Dismiss kann die Katalog-ScrollViews aus dem Layout bringen.
      libraryRelayoutEpoch += 1
      podcastsRelayoutEpoch += 1
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .alert("Enable offline mode?", isPresented: $model.showOfflineModeConfirmation) {
      Button("Cancel", role: .cancel) {
        model.cancelEnterOfflineHomeModeConfirmation()
      }
      Button("Go offline") {
        model.confirmEnterOfflineHomeMode()
      }
    } message: {
      Text(
        "The server connection will be paused. You can only play downloaded content. Progress syncs when you go back online."
      )
    }
  }

  private var tabViewBody: some View {
    // Tab-Struktur bleibt auch offline erhalten — Inhalte filtern sich selbst auf Downloads.
    onlineTabView
  }

  private func bumpActiveMediaRelayoutEpoch() {
    switch model.mediaCatalogKind {
    case .audiobooks: libraryRelayoutEpoch += 1
    case .podcasts: podcastsRelayoutEpoch += 1
    }
  }

  private var onlineTabView: some View {
    TabView(selection: $model.mainTab) {
      Tab(AppModel.MainTab.start.rawValue, systemImage: "house.fill", value: AppModel.MainTab.start) {
        HomeTabRootView()
          .id("abstand-home-tab-root-\(model.accountSessionEpoch)")
      }

      // Tabs immer registrieren — sonst baut TabView beim Bootstrap neu (Ampel flackert).
      Tab(AppModel.MainTab.library.rawValue, systemImage: "square.grid.2x2.fill", value: AppModel.MainTab.library) {
        lazyTabContent(.library) {
          mediaTabRoot
        }
      }

      Tab(AppModel.MainTab.search.rawValue, systemImage: "magnifyingglass", value: AppModel.MainTab.search) {
        lazyTabContent(.search) {
          SearchTabRootView()
        }
        .id("abstand-search-tab-root-\(model.accountSessionEpoch)")
      }

      Tab(AppModel.MainTab.settings.rawValue, systemImage: "gearshape.fill", value: AppModel.MainTab.settings) {
        lazyTabContent(.settings) { settingsTabRoot }
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
  }

  /// Platzhalter bis Bibliotheken aus Bootstrap da sind — Tab-Struktur bleibt stabil.
  private var tabLibraryBootstrapPlaceholder: some View {
    Color.clear
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .abstandTabScreenChrome()
  }

  @ViewBuilder
  private var mediaTabRoot: some View {
    switch model.mediaCatalogKind {
    case .audiobooks:
      if model.selectedBooksLibrary != nil {
        libraryTabRoot
      } else {
        tabLibraryBootstrapPlaceholder
      }
    case .podcasts:
      if model.showPodcastsTab, model.selectedPodcastLibrary != nil {
        podcastsTabRoot
      } else {
        tabLibraryBootstrapPlaceholder
      }
    }
  }

  @ViewBuilder
  private func lazyTabContent<Content: View>(
    _ tab: AppModel.MainTab,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if activatedTabs.contains(tab) {
      content()
    } else {
      Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  // MARK: - Settings tab root

  private var settingsTabRoot: some View {
    NavigationStack {
      SettingsHubRootView()
        .abstandTabScreenChrome()
        .navigationTitle(AppModel.MainTab.settings.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
    }
    .tint(model.appearanceAccentColor)
  }

  // MARK: - Library tab

  private var libraryTabRoot: some View {
    BooksLibraryTabShell(
      toolbarState: booksLibraryToolbarState,
      catalog: { booksCatalogScrollView }
    )
    .id("books-library-tab-\(model.accountSessionEpoch)")
    .onAppear { booksLibraryToolbarState.attach(model) }
    .onDisappear { booksLibraryToolbarState.detach() }
  }

  private var booksCatalogScrollView: some View {
    AbstandFixedBrowseStripSectionsLayout(
      relayoutTrigger: libraryRelayoutEpoch,
      bottomInsetRevalidationTrigger: model.nowPlayingAccessoryScrollBottomInset,
      selection: model.booksBrowseSection,
      sectionIDs: BooksBrowseSection.audiobookStripOrder,
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      onRefresh: { await model.refreshBooksCatalog() }
    ) {
      booksBrowseSectionStrip
    } sectionBody: { section in
      booksBrowseSectionScrollContent(for: section)
    }
  }

  private var browseStripAccent: Color { model.appearanceAccentColor }

  private var mediaKindStripItems: [AbstandBrowseStripItem] {
    model.visibleMediaCatalogKinds.map {
      AbstandBrowseStripItem(id: $0.rawValue, label: $0.rawValue, systemImage: $0.systemImage)
    }
  }

  private func mediaBrowseStrip<Secondary: View>(
    @ViewBuilder secondary: @escaping () -> Secondary
  ) -> some View {
    AbstandPinnedBrowseStrip(
      pinnedItems: mediaKindStripItems,
      pinnedSelectionID: model.mediaCatalogKind.rawValue,
      onSelectPinned: { id in
        guard let kind = AppModel.MediaCatalogKind(rawValue: id) else { return }
        model.mediaCatalogKind = kind
      },
      secondary: secondary
    )
  }

  private var booksBrowseSectionStrip: some View {
    mediaBrowseStrip {
      AbstandBrowseStripIconMenu(
        items: BooksBrowseSection.audiobookStripOrder.map {
          AbstandBrowseStripItem(id: $0.rawValue, label: $0.rawValue, systemImage: $0.systemImage)
        },
        selectionID: model.booksBrowseSection.rawValue,
        onSelect: { id in
          if let section = BooksBrowseSection(rawValue: id) {
            model.selectBooksBrowseSection(section)
          }
        }
      )
    }
  }

  @ViewBuilder
  private func booksBrowseSectionScrollContent(for section: BooksBrowseSection) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      booksBrowseSectionContent(for: section)
    }
  }

  @ViewBuilder
  private func booksBrowseSectionContent(for section: BooksBrowseSection) -> some View {
    switch section {
    case .books:
      booksCatalogBookListBody
    case .ebooks:
      ebooksPrimaryListBody
    case .ebooksSupplementary:
      ebooksSupplementaryListBody
    case .search:
      EmptyView()
    case .author:
      booksBrowseAuthorListBody
    case .narrators:
      booksBrowseNarratorListBody
    case .series:
      booksBrowseSeriesListBody
    case .collections:
      booksBrowseCollectionsListBody
    case .genres:
      booksBrowseGenresListBody
    case .tags:
      booksBrowseTagsListBody
    }
  }

  private var ebooksPrimaryListBody: some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: "eBooks")
      if !model.isNetworkReachable, model.browseEbooks.isEmpty {
        booksBrowseOfflineHint
      } else if model.browseEbooksLoading && model.browseEbooks.isEmpty {
        booksBrowseCenteredProgress
      } else if model.browseEbooks.isEmpty {
        Text("No eBooks found in this library.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
      } else if model.libraryBookCardStyle == .heroCover {
        LibraryHeroMultiColumnRows(
          items: model.browseEbooks,
          columns: AppTheme.Layout.ebookHeroCoverColumnsPerRow,
          spacing: AppTheme.Layout.withinSectionSpacing
        ) { book in
          EbookTabListCard(book: book, model: model)
            .task(id: book.id) {
              await model.loadMoreBrowseEbooksIfNeeded(currentItemId: book.id)
            }
        }
        if model.browseEbooksLoading {
          ProgressView()
            .tint(model.appearanceAccentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
      } else {
        ForEach(model.browseEbooks) { book in
          EbookTabListCard(book: book, model: model)
            .task(id: book.id) {
              await model.loadMoreBrowseEbooksIfNeeded(currentItemId: book.id)
            }
        }
        if model.browseEbooksLoading {
          ProgressView()
            .tint(model.appearanceAccentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
      }
    }
  }

  private var ebooksSupplementaryListBody: some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: "Supplementary eBooks")
      if !model.isNetworkReachable, model.browseEbooksSupplementary.isEmpty {
        booksBrowseOfflineHint
      } else if model.browseEbooksLoading && model.browseEbooksSupplementary.isEmpty {
        booksBrowseCenteredProgress
      } else if model.browseEbooksSupplementary.isEmpty {
        Text("No supplementary eBooks found in this library.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
      } else if model.libraryBookCardStyle == .heroCover {
        LibraryHeroMultiColumnRows(
          items: model.browseEbooksSupplementary,
          columns: AppTheme.Layout.ebookHeroCoverColumnsPerRow,
          spacing: AppTheme.Layout.withinSectionSpacing
        ) { book in
          EbookTabListCard(book: book, model: model)
        }
      } else {
        ForEach(model.browseEbooksSupplementary) { book in
          EbookTabListCard(book: book, model: model)
        }
      }
    }
  }

  private var booksCatalogBookListBody: some View {
    let rows = model.booksForDisplay()
    return LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      if let lib = model.selectedBooksLibrary {
        TabContentSectionTitle(title:lib.name)
      }
      if model.isLibraryCatalogFiltered {
        catalogFilterBanner
      }
      if model.isLoadingLibrary, rows.isEmpty {
        ProgressView()
          .controlSize(.large)
          .tint(model.appearanceAccentColor)
          .padding(.vertical, 32)
          .frame(maxWidth: .infinity)
      } else if rows.isEmpty {
        // Empty-State (wie eBooks/Podcasts) — verhindert den „weißen" View, wenn die Liste
        // nach Filterwechsel, „Mark as finished" oder Progress-Sync leer wird.
        Text("No books match the current filter.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
      } else if model.libraryBookCardStyle == .heroCover {
        libraryHeroMultiColumnBookRows(books: rows)
      } else {
        ForEach(rows) { book in
          libraryCatalogBookCard(book)
        }
      }
    }
  }

  private func libraryCatalogBookCard(_ book: ABSBook) -> some View {
    LibraryBookListCard(
      book: book,
      model: model,
      showEbookBadge: model.bookShowsSupplementaryEbookBadge(book)
    )
    .task(id: book.id) {
      await model.loadMoreIfNeeded(currentItemId: book.id)
      model.prefetchUpcomingBookCovers(currentItemId: book.id)
    }
  }

  @ViewBuilder
  private func libraryHeroMultiColumnBookRows(books: [ABSBook]) -> some View {
    LibraryHeroTwoColumnRows(
      items: books,
      spacing: AppTheme.Layout.withinSectionSpacing
    ) { book in
      libraryCatalogBookCard(book)
    }
  }

  private var booksBrowseOfflineHint: some View {
    Text("Connect to the network to load this list.")
      .font(.subheadline)
      .foregroundStyle(AppTheme.textSecondary)
      .padding(.vertical, 8)
  }

  private var booksBrowseCenteredProgress: some View {
    ProgressView()
      .controlSize(.extraLarge)
      .tint(model.appearanceAccentColor)
      .scaleEffect(1.35)
      .padding(.vertical, 48)
      .frame(maxWidth: .infinity)
  }

  private func booksBrowseCountLine(count: Int?) -> String? {
    browseEntityBooksCountLine(count: count)
  }

  private var booksBrowseAuthorListBody: some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Authors")
      if !model.isNetworkReachable, !model.offlineHomeUIActive {
        booksBrowseOfflineHint
      } else if model.browseAuthorsLoading && model.browseAuthors.isEmpty {
        booksBrowseCenteredProgress
      } else if model.browseAuthors.isEmpty {
        Text("No authors found.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
      } else {
        ForEach(model.browseAuthors) { author in
          Button {
            model.openAuthorDetail(
              authorId: author.id, displayName: author.name, numBooks: author.numBooks)
          } label: {
            browseAuthorRow(author)
          }
          .buttonStyle(.plain)
          .task(id: author.id) {
            await model.loadMoreBrowseAuthorsIfNeeded(currentItemId: author.id)
          }
        }
      }
    }
  }

  private var booksBrowseNarratorListBody: some View {
    let columns = AppTheme.Layout.facetTileGridColumns

    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Narrators")
      if !model.isNetworkReachable, !model.offlineHomeUIActive {
        booksBrowseOfflineHint
      } else if model.browseNarratorsLoading && model.browseNarrators.isEmpty {
        booksBrowseCenteredProgress
      } else if model.browseNarrators.isEmpty {
        Text("No narrators found.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
      } else {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(model.browseNarrators) { narrator in
            Button {
              model.openNarratorDetail(narratorName: narrator.name, numBooks: narrator.numBooks)
            } label: {
              FacetBrowseTileCard(
                kind: .narrators,
                title: narrator.name,
                count: narrator.numBooks
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private var booksBrowseSeriesListBody: some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Series")
      if !model.isNetworkReachable, !model.offlineHomeUIActive {
        booksBrowseOfflineHint
      } else if model.browseSeriesLoading && model.browseSeries.isEmpty {
        booksBrowseCenteredProgress
      } else if model.browseSeries.isEmpty {
        Text("No series found.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
      } else {
        ForEach(model.browseSeries) { series in
          Button {
            model.openSeriesDetail(
              seriesId: series.id,
              displayName: series.name,
              numBooks: series.books?.count)
          } label: {
            browseSeriesRow(series)
          }
          .buttonStyle(.plain)
          .task(id: series.id) {
            await model.loadMoreBrowseSeriesIfNeeded(currentItemId: series.id)
          }
        }
      }
    }
  }

  private var booksBrowseCollectionsListBody: some View {
    let columns = AppTheme.Layout.facetTileGridColumns

    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Collections")
      if !model.isNetworkReachable, !model.offlineHomeUIActive {
        booksBrowseOfflineHint
      } else if model.browseCollectionsLoading && model.browseCollections.isEmpty {
        booksBrowseCenteredProgress
      } else if model.browseCollections.isEmpty {
        Text("No collections found.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
      } else {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(model.browseCollections) { collection in
            Button {
              model.openCollectionDetail(
                collectionId: collection.id,
                displayName: collection.name,
                numBooks: collection.books?.count
              )
            } label: {
              FacetBrowseTileCard(
                kind: .collections,
                title: collection.name,
                count: collection.books?.count
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private var booksBrowseTagsListBody: some View {
    let columns = AppTheme.Layout.facetTileGridColumns

    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Tags")
      if !model.isNetworkReachable, !model.offlineHomeUIActive {
        booksBrowseOfflineHint
      } else if model.browseTagsLoading && model.browseTags.isEmpty {
        booksBrowseCenteredProgress
      } else if model.browseTags.isEmpty {
        Text("No tags found.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
      } else {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(model.browseTags) { tag in
            Button {
              model.openTagDetail(tagName: tag.name, numBooks: tag.numBooks)
            } label: {
              FacetBrowseTileCard(
                kind: .tags,
                title: tag.name,
                count: tag.numBooks
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private var booksBrowseGenresListBody: some View {
    let columns = AppTheme.Layout.facetTileGridColumns

    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Genres")
      if !model.isNetworkReachable, !model.offlineHomeUIActive {
        booksBrowseOfflineHint
      } else if model.browseGenresLoading && model.browseGenres.isEmpty {
        booksBrowseCenteredProgress
      } else if model.browseGenres.isEmpty {
        Text("No genres found.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
      } else {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(model.browseGenres) { genre in
            Button {
              model.openGenreDetail(genreName: genre.name, numBooks: genre.numBooks)
            } label: {
              FacetBrowseTileCard(
                kind: .genres,
                title: genre.name,
                count: genre.numBooks
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func browseAuthorRow(_ author: ABSLibraryAuthorListItem) -> some View {
    BrowseEntityRowCard(
      title: author.name,
      detailLabel: "Books",
      detailValue: browseEntityBooksCountLine(count: author.numBooks),
      cacheItemId: "author:\(author.id)",
      coverURL: author.hasAuthorImage ? model.authorImageURL(authorId: author.id) : nil,
      usesSquareCenterCropCover: true
    )
  }

  @ViewBuilder
  private func browseSeriesRow(_ series: ABSLibrarySeriesListItem) -> some View {
    let placeholder = "series-ph:\(series.id)"
    let bookIds = model.browseSeriesCoverBookIds(from: series.books)
    BrowseEntityRowCard(
      title: series.name,
      detailLabel: "Books",
      detailValue: booksBrowseCountLine(count: series.books?.count),
      cacheItemId: bookIds.first ?? placeholder,
      coverURL: bookIds.first.flatMap { model.coverURL(for: $0) },
      coverBookIds: bookIds.count > 1 ? bookIds : nil,
      authorLine: series.cardAuthorsLine
    )
  }

  private var catalogFilterBanner: some View {
    let palette = model.appearancePalette
    return HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
      Image(systemName: "line.3.horizontal.decrease.circle")
        .foregroundStyle(palette.textSecondary)
      Text(model.activeLibraryFilterSummary ?? "Library filtered")
        .font(.body)
        .foregroundStyle(palette.textPrimary)
        .lineLimit(2)
      Spacer(minLength: 0)
      Button("Show all") {
        model.clearCatalogFilter()
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(model.appearanceAccentColor)
    }
    .padding(.horizontal, AppTheme.Layout.tabPaddingH)
    .padding(.vertical, 8)
    .background(palette.card)
    .clipShape(Capsule())
  }

  private var podcastsTabRoot: some View {
    PodcastCatalogTabShell(toolbarState: podcastCatalogToolbarState) {
      podcastCatalogScrollView
    }
    .id("podcast-catalog-tab-\(model.accountSessionEpoch)")
    .onAppear { podcastCatalogToolbarState.attach(model) }
    .onDisappear { podcastCatalogToolbarState.detach() }
  }

  private static let podcastCatalogNewSectionId = PodcastCatalogStripSection.newEpisodes
  private static let podcastCatalogSearchSectionId = PodcastCatalogStripSection.search

  private var podcastCatalogScrollSectionIDs: [String] {
    [Self.podcastCatalogNewSectionId] + model.podcastShows.map(\.id)
  }

  private var podcastCatalogScrollSelection: String {
    model.podcastCatalogStripSectionId
  }

  private func podcastCatalogShowId(forSectionId sectionId: String) -> String? {
    sectionId == Self.podcastCatalogNewSectionId
      ? nil : sectionId
  }

  private var podcastCatalogScrollView: some View {
    AbstandFixedBrowseStripSectionsLayout(
      relayoutTrigger: podcastsRelayoutEpoch,
      bottomInsetRevalidationTrigger: model.nowPlayingAccessoryScrollBottomInset,
      selection: podcastCatalogScrollSelection,
      sectionIDs: podcastCatalogScrollSectionIDs,
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      onRefresh: { await model.refreshPodcastsTab() }
    ) {
      podcastShowsDockStrip
    } sectionBody: { sectionId in
      podcastCatalogSectionScrollContent(showId: podcastCatalogShowId(forSectionId: sectionId))
    }
  }

  @ViewBuilder
  private func podcastCatalogSectionScrollContent(showId: String?) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        TabContentSectionTitle(title:"Episodes")
        podcastPodcastsTabEpisodesContent(showId: showId)
      }
    }
  }

  private var podcastDockStripItems: [AbstandBrowseStripItem] {
    [
      AbstandBrowseStripItem(
        id: Self.podcastCatalogNewSectionId,
        label: "New",
        systemImage: "square.grid.2x2"
      ),
    ] + model.podcastShows.map { show in
      AbstandBrowseStripItem(
        id: show.id,
        label: show.displayTitle,
        systemImage: "mic.fill",
        coverItemId: show.id
      )
    }
  }

  private var podcastShowsDockStrip: some View {
    let _ = model.appearanceThemeRevision
    return mediaBrowseStrip {
      AbstandBrowseStripIconMenu(
        items: podcastDockStripItems,
        selectionID: podcastCatalogScrollSelection,
        onSelect: { id in
          if id == Self.podcastCatalogNewSectionId {
            model.podcastCatalogStripSectionId = id
            Task { await model.selectPodcastShowFilter(nil) }
          } else {
            model.podcastCatalogStripSectionId = id
            model.applyPodcastShowFilterSelection(id)
            Task { await model.loadPodcastEpisodesForShowLibraryItem(id) }
          }
        }
      )
    }
  }

  @ViewBuilder
  private func podcastPodcastsTabEpisodesContent(showId: String?) -> some View {
    let _ = model.appearanceThemeRevision
    let episodes = model.podcastEpisodesForPodcastsTab(showId: showId)
    let _ = {
      let dbgShow = showId ?? "nil"
      let dbgEp = episodes.count
      let dbgLoading = model.isLoadingPodcasts
      let dbgChrome = model.floatingChrome.gate.chromeVisible
      let dbgInset = model.nowPlayingAccessoryScrollBottomInset
      let dbgTab = String(describing: model.mainTab)
      DebugLogCollector.shared.log("podcastTabContent RENDER showId=\(dbgShow) episodes=\(dbgEp) isLoadingPodcasts=\(dbgLoading) chromeVisible=\(dbgChrome) inset=\(dbgInset) tab=\(dbgTab)")
    }()
    let isShowPane = showId != nil
    let isActivePane =
      isShowPane
      ? model.podcastSelectedShowId == showId
      : model.podcastSelectedShowId == nil
    let listLoading: Bool = {
      guard isActivePane else { return false }
      if isShowPane {
        return model.isLoadingPodcastShowEpisodes && episodes.isEmpty
      }
      return model.isLoadingPodcasts && episodes.isEmpty
    }()

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      if listLoading {
        ProgressView()
          .controlSize(.large)
          .tint(model.appearanceAccentColor)
          .padding(.vertical, 32)
          .frame(maxWidth: .infinity)
      } else if episodes.isEmpty {
        // Leerzustand — Bibliothek hat keine Folgen für diese Sendung bzw. der Feed ist leer.
        if isShowPane {
          Text("No episodes in the library for this show.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.vertical, 8)
        } else {
          Text(
            "No episodes in the list. Pull to refresh or check your network."
          )
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
        }
      }

      if model.libraryPodcastCardStyle == .heroCover {
        LibraryHeroTwoColumnRows(
          items: episodes,
          spacing: AppTheme.Layout.withinSectionSpacing
        ) { episode in
          LibraryPodcastListCard(episode: episode, model: model)
            .task(id: episode.progressLookupKey) {
              if showId == nil {
                await model.loadMorePodcastsIfNeeded(currentItemId: episode.id)
              }
            }
        }
      } else {
        LibraryPodcastCardsFlow {
          ForEach(episodes, id: \.progressLookupKey) { episode in
            LibraryPodcastListCard(episode: episode, model: model)
              .task(id: episode.progressLookupKey) {
                if showId == nil {
                  await model.loadMorePodcastsIfNeeded(currentItemId: episode.id)
                }
              }
          }
        }
      }

      if isShowPane,
        isActivePane,
        model.isLoadingPodcastShowEpisodes,
        !episodes.isEmpty
      {
        ProgressView()
          .controlSize(.small)
          .tint(model.appearanceAccentColor)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      }
    }
  }
}


// MARK: - Unified Search Tab

/// Zentraler Such-Tab: Buch-Suche (default) oder Podcast-Suche,
/// je nachdem von wo der User gekommen ist (`searchTabMediaKind`).
struct SearchTabRootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        unifiedSearchField
        searchResultsContent
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .abstandScrollScreenBackground()
    .navigationTitle("Search")
    .toolbarTitleDisplayMode(.inline)
    .tint(model.appearanceAccentColor)
  }

  /// Ein einziges Suchfeld — bindet je nach Modus an searchText oder podcastLibrarySearchText.
  private var unifiedSearchField: some View {
    let palette = model.appearancePalette
    let isPodcasts = model.searchTabMediaKind == .podcasts
    return HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(palette.textSecondary)
      if isPodcasts {
        TextField("Show or episode…", text: $model.podcastLibrarySearchText)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .textFieldStyle(.plain)
          .foregroundStyle(palette.textPrimary)
          .onSubmit { model.schedulePodcastLibrarySearch() }
      } else {
        TextField("Title, author, series…", text: $model.searchText)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .textFieldStyle(.plain)
          .foregroundStyle(palette.textPrimary)
          .onSubmit { model.scheduleSearch() }
      }
      clearButton
    }
    .padding(12)
    .background(palette.card)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  @ViewBuilder
  private var clearButton: some View {
    let isPodcasts = model.searchTabMediaKind == .podcasts
    let hasText = isPodcasts ? !model.podcastLibrarySearchText.isEmpty : !model.searchText.isEmpty
    if hasText {
      Button {
        if isPodcasts {
          model.podcastLibrarySearchText = ""
          model.clearPodcastLibrarySearchResults()
        } else {
          model.searchText = ""
          model.clearSearchResults()
        }
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(AppTheme.textSecondary)
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private var searchResultsContent: some View {
    if model.searchTabMediaKind == .podcasts {
      PodcastLibrarySearchResultsView()
    } else {
      BooksSearchBrowseView()
    }
  }
}


// MARK: - Library search results

private struct BooksSearchBrowseView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    let q = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        if q.isEmpty {
          ContentUnavailableView(
            "Search",
            systemImage: "magnifyingglass",
            description: Text("Enter at least two characters to search your libraries.")
          )
          .frame(maxWidth: .infinity)
          .padding(.vertical, 48)
        }
        if model.isLoadingLibrary, q.count >= 2 {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding()
        }
        if q.count > 0, q.count < 2 {
          Text("Enter at least two characters.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(24)
        }
        if q.count >= 2, !model.isLoadingLibrary, model.searchBooks.isEmpty,
          model.searchAuthors.isEmpty, model.searchNarrators.isEmpty, model.searchSeries.isEmpty,
          model.searchTags.isEmpty, model.searchGenres.isEmpty
        {
          Text("No results.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(24)
        }

        searchSection(title: "Books", isEmpty: model.searchBooks.isEmpty) {
          LibraryBookCardsFlow {
            ForEach(model.searchBooks) { book in
              LibraryBookListCard(book: book, model: model)
            }
          }
        }
        searchSection(title: "Authors", isEmpty: model.searchAuthors.isEmpty) {
          ForEach(model.searchAuthors) { a in
            searchNavRow(
              title: a.name,
              detailLabel: "Books",
              detailValue: a.numBooks.map { "\($0)" },
              cacheItemId: "author:\(a.id)",
              coverURL: model.authorImageURL(authorId: a.id),
              usesSquareCenterCropCover: true
            ) {
              model.openAuthorDetail(authorId: a.id, displayName: a.name, numBooks: a.numBooks)
            }
          }
        }
        searchSection(title: "Series", isEmpty: model.searchSeries.isEmpty) {
          ForEach(model.searchSeries) { s in
            let placeholder = "series-ph:\(s.id)"
            let bookIds = model.browseSeriesCoverBookIds(from: s.books)
            searchNavRow(
              title: s.name,
              detailLabel: "Books",
              detailValue: (s.books?.count).map { "\($0)" },
              cacheItemId: bookIds.first ?? placeholder,
              coverURL: bookIds.first.flatMap { model.coverURL(for: $0) },
              coverBookIds: bookIds.count > 1 ? bookIds : nil,
              authorLine: s.cardAuthorsLine
            ) {
              model.openSeriesDetail(
                seriesId: s.id, displayName: s.name, numBooks: s.books?.count)
            }
          }
        }
        searchSection(title: "Narrators", isEmpty: model.searchNarrators.isEmpty) {
          ForEach(model.searchNarrators) { n in
            let bookId = model.browseNarratorCoverItemIdByNarratorName[n.name]
            searchNavRow(
              title: n.name,
              detailLabel: "Books",
              detailValue: n.numBooks.map { "\($0)" },
              cacheItemId: bookId ?? "narrator-ph:\(n.id)",
              coverURL: bookId.flatMap { model.coverURL(for: $0) }
            ) {
              model.openNarratorDetail(narratorName: n.name, numBooks: n.numBooks)
            }
          }
        }
        searchSection(title: "Tags", isEmpty: model.searchTags.isEmpty) {
          ForEach(model.searchTags) { t in
            searchNavRow(
              title: t.name, detailLabel: "Books", detailValue: t.numItems.map { "\($0)" }
            ) {
              model.openTagDetail(tagName: t.name, numBooks: t.numItems)
            }
          }
        }
        searchSection(title: "Genres", isEmpty: model.searchGenres.isEmpty) {
          ForEach(model.searchGenres) { g in
            searchNavRow(
              title: g.name, detailLabel: "Books", detailValue: g.numItems.map { "\($0)" }
            ) {
              model.openGenreDetail(genreName: g.name, numBooks: g.numItems)
            }
          }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func searchSection<Content: View>(
    title: String,
    isEmpty: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if !isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        TabContentSectionTitle(title:title)
        content()
      }
    }
  }
}

private extension BooksSearchBrowseView {
  @ViewBuilder
  func searchNavRow(
    title: String,
    detailLabel: String = "Books",
    detailValue: String? = nil,
    cacheItemId: String = "",
    coverURL: URL? = nil,
    coverBookIds: [String]? = nil,
    authorLine: String? = nil,
    usesSquareCenterCropCover: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      BrowseEntityRowCard(
        title: title,
        detailLabel: detailLabel,
        detailValue: detailValue,
        cacheItemId: cacheItemId.isEmpty ? "search:\(title)" : cacheItemId,
        coverURL: coverURL,
        coverBookIds: coverBookIds,
        authorLine: authorLine,
        usesSquareCenterCropCover: usesSquareCenterCropCover
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Podcast library search (Shows innerhalb der Podcast-Bibliothek)

private struct PodcastLibrarySearchResultsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    let q = model.podcastLibrarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      if q.isEmpty {
        ContentUnavailableView(
          "Search",
          systemImage: "magnifyingglass",
          description: Text("Enter at least two characters to search your podcasts.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
      }
      if model.isLoadingPodcasts, q.count >= 2 {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding()
      }
      if q.count > 0, q.count < 2 {
        Text("Enter at least two characters.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity)
          .multilineTextAlignment(.center)
          .padding(24)
      }
      if q.count >= 2, !model.isLoadingPodcasts, model.podcastLibrarySearchShows.isEmpty,
        model.podcastLibrarySearchEpisodes.isEmpty
      {
        Text("No results.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity)
          .padding(24)
      }

      if !model.podcastLibrarySearchShows.isEmpty {
        LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          TabContentSectionTitle(title:"Shows")
          ForEach(model.podcastLibrarySearchShows) { show in
            Button {
              model.applyPodcastShowFilterSelection(show.id)
              Task { await model.loadPodcastEpisodesForShowLibraryItem(show.id) }
            } label: {
              PodcastShowRowCard(show: show)
            }
            .buttonStyle(.plain)
          }
        }
      }

      if !model.podcastLibrarySearchEpisodes.isEmpty {
        LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          TabContentSectionTitle(title:"Episodes")
          ForEach(model.podcastLibrarySearchEpisodes) { episode in
            LibraryPodcastListCard(
              episode: episode,
              model: model
            )
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Podcast RSS feed rows (same layout as library rows; download only)

struct PodcastRssFeedDraftRow: View {
  @EnvironmentObject private var model: AppModel
  let draft: ABSPodcastRssFeedEpisodeDraft
  /// Optional: Admin-Show-Detail (sonst `podcastSelectedShowId`).
  var podcastLibraryItemId: String?
  /// Admin-Feed: Mülltonne statt „In library“, wenn die Folge schon in der Bibliothek ist.
  var showsDeleteWhenInLibrary = false

  @State private var deleteEpisodeConfirmation: ABSPodcastEpisodeListItem?

  private var showId: String? {
    let explicit = podcastLibraryItemId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !explicit.isEmpty { return explicit }
    return model.podcastSelectedShowId
  }

  private var showTitle: String {
    guard let sid = showId else { return "—" }
    if let t = model.podcastShows.first(where: { $0.id == sid })?.displayTitle.trimmingCharacters(
      in: .whitespacesAndNewlines),
      !t.isEmpty
    {
      return t
    }
    return "—"
  }

  private var publishedCaption: String {
    guard let ms = draft.publishedAt, ms > 0 else { return "—" }
    let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    return d.formatted(date: .abbreviated, time: .omitted)
  }

  private var matchingLibraryEpisode: ABSPodcastEpisodeListItem? {
    guard let sid = showId else { return nil }
    return model.libraryEpisodeMatchingPodcastRssDraft(draft, showId: sid)
  }

  private var inLibrary: Bool { matchingLibraryEpisode != nil }

  var body: some View {
    let palette = model.appearancePalette
    let sid = (showId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        LibraryRowLayout.coverSlot {
          LibraryRowLayout.rowCoverImage(
            url: model.coverURL(for: sid),
            token: model.token,
            itemId: sid,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision
          )
        }
        .accessibilityHidden(true)

        LibraryRowLayout.metadataColumn(showsProgressBar: false) {
          VStack(alignment: .leading, spacing: 2) {
            Text(draft.title)
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            LibraryRowCollapsedMetaLine(label: "Show", value: showTitle)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
              Text(publishedCaption)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(palette.textSecondary)
              Spacer(minLength: 0)
              rssTrailingControl
            }
          }
          .padding(.trailing, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RSS episode, not in library yet")
      }
      .padding(.leading, 0)
    }
    .background(palette.card)
    .clipShape(LibraryRowLayout.cardShape)
    .abstandCardElevation(.standard)
    .abstandThemeRefresh()
    .alert(
      "Delete episode?",
      isPresented: Binding(
        get: { deleteEpisodeConfirmation != nil },
        set: { if !$0 { deleteEpisodeConfirmation = nil } }
      )
    ) {
      Button("Delete", role: .destructive) {
        if let episode = deleteEpisodeConfirmation, let sid = showId {
          Task { await model.deletePodcastEpisodeFromLibrary(showLibraryItemId: sid, episode: episode) }
        }
        deleteEpisodeConfirmation = nil
      }
      Button("Cancel", role: .cancel) {
        deleteEpisodeConfirmation = nil
      }
    } message: {
      if let episode = deleteEpisodeConfirmation {
        Text("\"\(episode.episodeTitle)\" will be removed from the server library.")
      }
    }
  }

  @ViewBuilder
  private var rssTrailingControl: some View {
    let secondary = model.appearancePalette.textSecondary
    if inLibrary, showsDeleteWhenInLibrary, let episode = matchingLibraryEpisode {
      Button {
        deleteEpisodeConfirmation = episode
      } label: {
        Image(systemName: "trash")
          .font(.title3)
          .foregroundStyle(AppTheme.danger)
      }
      .buttonStyle(.plain)
      .frame(minWidth: 88, alignment: .trailing)
      .disabled(!model.isNetworkReachable)
      .accessibilityLabel("Delete episode from library")
    } else if inLibrary {
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(model.appearanceAccentColor)
          .font(.caption)
        Text("In library")
          .font(.caption.weight(.medium))
          .foregroundStyle(secondary)
      }
      .frame(minWidth: 88, alignment: .trailing)
    } else if model.podcastRssDraftDownloadCompletedIds.contains(draft.id) {
      Text("Downloading")
        .font(.caption.weight(.medium))
        .foregroundStyle(secondary)
        .lineLimit(1)
        .frame(minWidth: 88, alignment: .trailing)
        .accessibilityLabel("Downloading to server")
    } else if model.podcastRssEpisodeDownloadInProgressDraftIds.contains(draft.id) {
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Downloading")
          .font(.caption.weight(.medium))
          .foregroundStyle(secondary)
          .lineLimit(1)
      }
      .frame(minWidth: 88, alignment: .trailing)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Downloading to server")
    } else {
      Button {
        guard let sid = showId else { return }
        Task { await model.downloadPodcastRssEpisodeDraft(draft, podcastLibraryItemId: sid) }
      } label: {
        Image(systemName: "arrow.down.circle")
          .font(.title3)
          .foregroundStyle(model.appearanceAccentColor)
      }
      .buttonStyle(.plain)
      .frame(minWidth: 88, alignment: .trailing)
      .disabled(!model.isNetworkReachable)
      .accessibilityLabel("Download to server")
    }
  }
}

// MARK: - Shared list / hero metadata (title + author or show)

private struct BookCollapsedAuthorLine: View {
  let book: ABSBook
  var authorOverride: String?

  var body: some View {
    let line: String = {
      if let authorOverride {
        let t = authorOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != "—" { return t }
      }
      return book.displayAuthorsCardLine
    }()
    .trimmingCharacters(in: .whitespacesAndNewlines)
    LibraryRowCollapsedMetaLine(label: "Author", value: line.isEmpty || line == "—" ? "—" : line)
  }
}

/// Zweite Zeile in Library-Karten (Label + Wert), z. B. „Author …“ oder „Books 3 books“.
private struct LibraryRowCollapsedMetaLine: View {
  @EnvironmentObject private var model: AppModel
  let label: String
  let value: String?
  var valueLineLimit: Int = 2

  var body: some View {
    let palette = model.appearancePalette
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
        .textCase(.uppercase)
      let line = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if line.isEmpty || line == "—" {
        Text("—")
          .font(.footnote)
          .foregroundStyle(palette.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text(line)
          .font(.footnote)
          .foregroundStyle(palette.textPrimary)
          .lineLimit(valueLineLimit)
          .minimumScaleFactor(0.88)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

private struct PodcastEpisodeCollapsedShowLine: View {
  let episode: ABSPodcastEpisodeListItem

  var body: some View {
    LibraryRowCollapsedMetaLine(label: "Show", value: episode.showTitle)
  }
}

private func continueHeroAuthorSingleLine(for book: ABSBook) -> String {
  let line = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
  if line.isEmpty || line == "—" { return "—" }
  return line
}

@ViewBuilder
private func continueHeroPlayPill(
  accent: Color,
  palette: AppColorPalette,
  caption: String,
  action: @escaping () -> Void
) -> some View {
  let labelOnAccent = palette.foregroundOnAccent(accent)
  HStack {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "play.fill")
          .font(.caption.weight(.bold))
        Text(caption)
          .font(.caption.weight(.semibold))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .foregroundStyle(labelOnAccent)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(accent, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Wiedergabe")
    .accessibilityValue("Noch \(caption)")
    Spacer(minLength: 0)
  }
}

/// Titel + Metadaten unter Continue-Hero-/Library-Cover (ohne Play-Pille).
struct ContinueListeningHeroMetadataBlock: View {
  @EnvironmentObject private var model: AppModel
  @ScaledMetric(relativeTo: .headline) private var titleFixedHeight = AppTheme.Layout.continueHeroMetadataTitleFixedHeight
  @ScaledMetric(relativeTo: .footnote) private var detailFixedHeight = AppTheme.Layout.continueHeroMetadataDetailFixedHeight
  let title: String
  let detailLabel: String
  let detailValue: String
  let horizontalInset: CGFloat
  var onTitleTap: () -> Void = {}
  var includesBottomPadding: Bool = false
  var blockHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.continueHeroMetadataTitleDetailSpacing) {
      Text(title)
        .font(.headline.weight(.semibold))
        .foregroundStyle(model.appearancePalette.textPrimary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .minimumScaleFactor(0.85)
        .frame(
          maxWidth: .infinity,
          minHeight: titleFixedHeight,
          maxHeight: titleFixedHeight,
          alignment: .topLeading
        )
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTitleTap() }

      LibraryRowCollapsedMetaLine(label: detailLabel, value: detailValue, valueLineLimit: 1)
        .frame(
          maxWidth: .infinity,
          minHeight: detailFixedHeight,
          maxHeight: detailFixedHeight,
          alignment: .topLeading
        )
    }
    .padding(.horizontal, horizontalInset)
    .padding(.top, AppTheme.Layout.continueHeroMetadataVerticalPadding)
    .padding(
      .bottom,
      includesBottomPadding ? AppTheme.Layout.continueHeroMetadataExtraBottomPadding : 0
    )
    .frame(maxWidth: .infinity)
    .frame(height: blockHeight, alignment: .top)
  }
}

/// Einheitliche Typografie und feste Höhe für Bücher- und Podcast-Continue-Hero-Karten.
struct ContinueListeningHeroTextBlock<Pill: View>: View {
  @ScaledMetric(relativeTo: .headline) private var titleFixedHeight = AppTheme.Layout.continueHeroMetadataTitleFixedHeight
  @ScaledMetric(relativeTo: .footnote) private var detailFixedHeight = AppTheme.Layout.continueHeroMetadataDetailFixedHeight
  let title: String
  let detailLabel: String
  let detailValue: String
  let horizontalInset: CGFloat
  var onTitleTap: () -> Void = {}
  @ViewBuilder private let playPill: () -> Pill

  private var titleDetailHeight: CGFloat {
    AppTheme.Layout.continueHeroMetadataVerticalPadding
      + titleFixedHeight
      + AppTheme.Layout.continueHeroMetadataTitleDetailSpacing
      + detailFixedHeight
  }

  private var scaledBlockHeight: CGFloat {
    titleDetailHeight
      + AppTheme.Layout.continueHeroMetadataPlayPillTopPadding
      + AppTheme.Layout.continueHeroMetadataPlayPillIntrinsicHeight
      + AppTheme.Layout.continueHeroMetadataExtraBottomPadding
  }

  init(
    title: String,
    detailLabel: String,
    detailValue: String,
    horizontalInset: CGFloat,
    onTitleTap: @escaping () -> Void = {},
    @ViewBuilder playPill: @escaping () -> Pill
  ) {
    self.title = title
    self.detailLabel = detailLabel
    self.detailValue = detailValue
    self.horizontalInset = horizontalInset
    self.onTitleTap = onTitleTap
    self.playPill = playPill
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ContinueListeningHeroMetadataBlock(
        title: title,
        detailLabel: detailLabel,
        detailValue: detailValue,
        horizontalInset: horizontalInset,
        onTitleTap: onTitleTap,
        blockHeight: titleDetailHeight
      )

      playPill()
        .padding(.horizontal, horizontalInset)
        .padding(.top, AppTheme.Layout.continueHeroMetadataPlayPillTopPadding)
        .padding(.bottom, AppTheme.Layout.continueHeroMetadataExtraBottomPadding)
    }
    .frame(maxWidth: .infinity)
    .frame(height: scaledBlockHeight, alignment: .top)
  }
}

/// Gemeinsame Cover-Pill (Typ, Download, Länge) — gleiche Kapsel wie Continue Listening.
struct ContinueListeningHeroCoverPill<Content: View>: View {
  var allowsHitTesting = false
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .padding(.horizontal, 6)
      .padding(.vertical, 5)
      .background(.black.opacity(0.48), in: Capsule(style: .continuous))
      .fixedSize()
      .padding(.vertical, ContinueListeningHeroCoverPillMetrics.verticalInset)
      .padding(.horizontal, ContinueListeningHeroCoverPillMetrics.horizontalInset)
      .allowsHitTesting(allowsHitTesting)
  }
}

enum ContinueListeningHeroCoverPillMetrics {
  static let iconFont = Font.caption2.weight(.semibold)
  static let verticalInset: CGFloat = 8
  static let horizontalInset: CGFloat = 8
}

/// Oben links auf Continue-Hero-Cover: Medientyp-Pill (Buch oder Podcast).
struct ContinueListeningHeroTypePill: View {
  enum MediaType: Equatable {
    case audiobook, podcast
    var systemImage: String {
      switch self {
      case .audiobook: return "book.fill"
      case .podcast: return "mic.fill"
      }
    }
  }
  let type: MediaType

  var body: some View {
    ContinueListeningHeroCoverPill {
      Image(systemName: type.systemImage)
        .font(ContinueListeningHeroCoverPillMetrics.iconFont)
        .foregroundStyle(.white)
    }
  }
}

/// Oben rechts auf Continue-Hero-Cover: fertiger Download oder laufender Download (kein Tap — Cover-Tap bleibt).
struct ContinueListeningHeroOfflineBadge: View {
  let isDownloaded: Bool
  let isDownloading: Bool
  let downloadProgress: Double

  var body: some View {
    Group {
      if isDownloaded {
        ContinueListeningHeroCoverPill {
          Image(systemName: "arrow.down.circle.fill")
            .font(ContinueListeningHeroCoverPillMetrics.iconFont)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
        }
        .accessibilityLabel("Downloaded")
      } else if isDownloading {
        ContinueListeningHeroCoverPill {
          ProgressView(value: downloadProgress)
            .progressViewStyle(.circular)
            .tint(.white)
            .scaleEffect(0.72)
            .frame(width: 13, height: 13)
        }
        .accessibilityLabel("Downloading")
      }
    }
    .transaction { $0.animation = nil }
  }
}

struct ContinueListeningHeroBookOfflineBadgeSlot: View {
  @ObservedObject var rowLive: LibraryBookRowLiveState

  var body: some View {
    ContinueListeningHeroOfflineBadge(
      isDownloaded: rowLive.isDownloaded,
      isDownloading: rowLive.isDownloading,
      downloadProgress: rowLive.downloadProgress
    )
  }
}

struct ContinueListeningHeroPodcastOfflineBadgeSlot: View {
  @ObservedObject var rowLive: LibraryPodcastEpisodeRowLiveState

  var body: some View {
    ContinueListeningHeroOfflineBadge(
      isDownloaded: rowLive.isDownloaded,
      isDownloading: rowLive.isDownloading,
      downloadProgress: rowLive.downloadProgress
    )
  }
}

/// Feste Reihenfolge solange sich Regal-Inhalt nicht ändert (kein Neu-Sortieren bei Fortschritt-Ticks).
struct ContinueListeningHeroCarousel: View {
  @EnvironmentObject private var model: AppModel
  let shelf: ABSStartShelfSection

  @State private var rows: [ABSStartShelfMergedRow] = []

  private var contentSignature: String {
    let bookPart = shelf.books.map(\.id).joined(separator: "\u{1f}")
    let episodePart = shelf.podcastEpisodes.map(\.progressLookupKey).joined(separator: "\u{1f}")
    return "\(bookPart)\u{1e}\(episodePart)"
  }

  var body: some View {
    AbstandHorizontalBrowseStripScroll(
      appliesHorizontalContentInset: false,
      verticalContentPadding: 0
    ) {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(rows) { row in
          switch row {
          case .book(let book):
            ContinueListeningHeroBookCard(book: book, model: model)
          case .podcastEpisode(let episode):
            ContinueListeningHeroPodcastCard(episode: episode, model: model)
          }
        }
      }
    }
    .onAppear { rebuildRows() }
    .onChange(of: contentSignature) { _, _ in rebuildRows() }
  }

  private func rebuildRows() {
    rows = ABSStartShelfMergedRow.merged(
      books: shelf.books,
      podcastEpisodes: shelf.podcastEpisodes,
      progress: model.progressByItemId
    )
  }
}

// MARK: - Podcast episode row

struct PodcastEpisodeRowCard: View {
  /// Kein `@ObservedObject` — Fortschritt/Download über `LibraryPodcastEpisodeRowLiveState`.
  let model: AppModel
  let episode: ABSPodcastEpisodeListItem
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  var opensDetailOnTap = true

  @StateObject private var live: LibraryPodcastEpisodeRowLiveState
  @State private var showDetail = false

  init(
    episode: ABSPodcastEpisodeListItem,
    model: AppModel,
    opensDetailOnTap: Bool = true
  ) {
    self.episode = episode
    self.opensDetailOnTap = opensDetailOnTap
    self.model = model
    _live = StateObject(
      wrappedValue: LibraryPodcastEpisodeRowLiveState(
        progressLookupKey: episode.progressLookupKey,
        offlineStorageId: model.podcastEpisodeOfflineStorageId(episode),
        model: model
      )
    )
  }

  private var prog: ABSUserMediaProgress? { live.progress }

  /// `recentEpisode` in „items-in-progress" liefert oft keine Länge; die kommt dann aus `mediaProgress`.
  private var resolvedTotalDurationSeconds: Double {
    if episode.duration > 0 { return episode.duration }
    if let p = prog, p.duration > 0 { return p.duration }
    return 0
  }

  private var showsBottomProgressBar: Bool {
    guard let p = prog, !p.isFinished else { return false }
    return max(p.duration, resolvedTotalDurationSeconds) > 0
  }

  private var bottomProgressValue: Double {
    guard showsBottomProgressBar, let p = prog, max(p.duration, resolvedTotalDurationSeconds) > 0 else {
      return 0
    }
    return min(1, max(0, p.progress))
  }

  var body: some View {
    let _ = themeRevision
    return Group {
      if opensDetailOnTap {
        podcastEpisodeRowCardBody
          .navigationDestination(isPresented: $showDetail) {
            PodcastEpisodeDetailView(episode: episode)
          }
      } else {
        podcastEpisodeRowCardBody
      }
    }
    .abstandThemeRefresh()
  }

  private var podcastEpisodeRowCardBody: some View {
    LibraryRowLayout.libraryRowCardChrome(
      cardColor: AppTheme.card,
      showsBottomProgressBar: showsBottomProgressBar,
      progressValue: bottomProgressValue,
      openDetails: nil
    ) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        Button {
          Task { await model.playPodcastEpisode(episode) }
        } label: {
          LibraryRowLayout.coverSlot {
            LibraryRowLayout.rowCoverImage(
              url: model.coverURL(for: episode.libraryItemId),
              token: model.token,
              itemId: episode.libraryItemId,
              cacheAccount: model.coverImageCacheAccountDirectory(),
              cacheRevision: model.coverImageCacheRevision
            )
          } overlay: {
            Image(systemName: "play.fill")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.white)
              .frame(width: 18, height: 18)
              .background(AppTheme.coverPlayBadgeBackground)
              .clipShape(Circle())
              .padding(4)
              .accessibilityHidden(true)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play")
        .accessibilityHint("Starts playback of this episode.")

        Group {
          LibraryRowLayout.metadataColumn(showsProgressBar: showsBottomProgressBar) {
            VStack(alignment: .leading, spacing: 2) {
              Text(episode.episodeTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
              PodcastEpisodeCollapsedShowLine(episode: episode)
              Spacer(minLength: 0)
              LibraryRowLayout.metadataFooter {
                Text(formatPlaybackTime(resolvedTotalDurationSeconds))
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(AppTheme.textSecondary)
              } trailing: {
                Group {
                  if prog?.isFinished == true {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(themeAccent)
                      .font(.caption)
                      .accessibilityLabel("Finished")
                  }
                  podcastDownloadStatusIcon
                }
              }
            }
            .padding(.trailing, 4)
          }
        }
        .contentShape(Rectangle())
        .onTapGesture {
          guard opensDetailOnTap else { return }
          showDetail = true
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityHint(
      opensDetailOnTap
        ? "Opens episode details. Play button starts playback."
        : "Play button starts playback."
    )
  }

  @ViewBuilder
  private var podcastDownloadStatusIcon: some View {
    if live.isDownloaded {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(themeAccent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if live.isDownloading {
      ProgressView(value: live.downloadProgress)
        .frame(width: 36)
        .tint(themeAccent)
        .accessibilityLabel("Downloading")
    }
  }

  @ViewBuilder
  private func podcastEpisodeExpandedBlock(_ d: ABSPodcastEpisodeExpandedDetail) -> some View {
    let palette = model.appearancePalette
    VStack(alignment: .leading, spacing: 8) {
      Divider().background(palette.textSecondary.opacity(0.2))
      podcastMetaRowShowFilter(episode: d.episode)
      podcastMetaRowHostAuthorFilter(detail: d)
      if let s = d.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
        podcastMetaRow("Subtitle", s)
      }
      if let pub = d.pubDate?.trimmingCharacters(in: .whitespacesAndNewlines), !pub.isEmpty {
        podcastMetaRow("Published", pub)
      }
      if let g = d.showGenres, !g.isEmpty {
        podcastMetaRow("Categories", g.joined(separator: ", "))
      }
      podcastMetaRow(
        "Episode",
        absPlainText(fromHTML: d.episodeDescriptionHTML).nilIfEmpty ?? "—")
      podcastMetaRow(
        "Show notes",
        absPlainText(fromHTML: d.showDescriptionHTML).nilIfEmpty ?? "—")
      podcastEpisodeExpandedActionRow(episode: d.episode)
    }
    .padding(.horizontal, AppTheme.Layout.libraryRowCardInset)
    .padding(.bottom, 10)
  }

  private func podcastEpisodeExpandedActionRow(episode: ABSPodcastEpisodeListItem) -> some View {
    let rowProgress = live.progress
    let isFinished = rowProgress?.isFinished == true
    return HStack(spacing: 8) {
      Group {
        if live.isDownloading {
          ZStack {
            RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
              .stroke(model.appearanceAccentColor.opacity(0.45), lineWidth: 1)
            ProgressView(value: live.downloadProgress)
              .tint(model.appearanceAccentColor)
              .scaleEffect(x: 1, y: 1.1, anchor: .center)
              .padding(.horizontal, 8)
          }
          .frame(maxWidth: .infinity)
          .frame(height: MiniPlayerMetrics.controlMinHeight)
          .accessibilityLabel("Download in progress")
        } else if live.isDownloaded {
          Button {
            model.removeLocalDownload(bookId: model.podcastEpisodeOfflineStorageId(episode))
          } label: {
            Image(systemName: "arrow.down.circle.badge.xmark")
              .font(.callout)
              .foregroundStyle(model.appearanceAccentColor)
          }
          .buttonStyle(LibraryCardActionButtonStyle(variant: .downloaded))
          .accessibilityLabel("Remove offline copy")
        } else {
          Button {
            model.startDownloadPodcastEpisode(episode)
          } label: {
            Image(systemName: "arrow.down.circle")
              .font(.callout)
              .foregroundStyle(model.appearanceAccentColor)
          }
          .buttonStyle(LibraryCardActionButtonStyle(variant: .accent))
          .accessibilityLabel("Download")
        }
      }
      .frame(maxWidth: .infinity)

      Button {
        Task {
          if isFinished {
            await model.markPodcastEpisodeUnfinished(episode)
          } else {
            await model.markPodcastEpisodeFinished(episode)
          }
        }
      } label: {
        Image(systemName: isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle")
          .font(.callout)
          .foregroundStyle(
            model.isNetworkReachable
              ? model.appearanceAccentColor
              : model.appearancePalette.textSecondary)
      }
      .buttonStyle(LibraryCardActionButtonStyle(variant: isFinished ? .finished : .accent))
      .disabled(!model.isNetworkReachable)
      .accessibilityLabel(isFinished ? "Mark as not finished" : "Finished")
    }
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.top, 8)
  }

  private func podcastMetaRowHostAuthorFilter(detail: ABSPodcastEpisodeExpandedDetail) -> some View {
    let palette = model.appearancePalette
    let authors = detail.showAuthors
    let line = detail.episode.authorLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return HStack(alignment: .top, spacing: 10) {
      Text("HOST / AUTHOR")
        .font(.caption.weight(.bold))
        .foregroundStyle(palette.textSecondary)
        .frame(width: 112, alignment: .leading)
      Group {
        if !authors.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(authors, id: \.id) { author in
              Button {
                model.openPodcastSearchFromText(author.name)
              } label: {
                Text(author.name)
                  .font(DetailHeroTypography.metaLink)
                  .abstandAccentForeground()
                  .multilineTextAlignment(.leading)
                  .fixedSize(horizontal: false, vertical: true)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)
            }
          }
        } else if !line.isEmpty, line != "—" {
          Button {
            model.openPodcastSearchFromText(line)
          } label: {
            Text(line)
              .font(.subheadline)
              .abstandAccentForeground()
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
        } else {
          Text("—")
            .font(.subheadline)
            .foregroundStyle(palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func podcastMetaRowShowFilter(episode: ABSPodcastEpisodeListItem) -> some View {
    let palette = model.appearancePalette
    let title = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return HStack(alignment: .top, spacing: 10) {
      Text("SHOW")
        .font(.caption.weight(.bold))
        .foregroundStyle(palette.textSecondary)
        .frame(width: 112, alignment: .leading)
      if title.isEmpty || title == "—" {
        Text("—")
          .font(.subheadline)
          .foregroundStyle(palette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Button {
          model.openPodcastSearchFromText(title)
        } label: {
          Text(title)
            .font(.subheadline)
            .abstandAccentForeground()
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func podcastMetaRow(_ k: String, _ v: String) -> some View {
    let palette = model.appearancePalette
    return HStack(alignment: .top, spacing: 10) {
      Text(k.uppercased())
        .font(.caption.weight(.bold))
        .foregroundStyle(palette.textSecondary)
        .frame(width: 112, alignment: .leading)
      Text(v)
        .font(.subheadline)
        .foregroundStyle(palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// Wählt kompakte Zeile oder Cover-Karte gemäß `libraryPodcastCardStyle`.
struct LibraryPodcastListCard: View {
  let episode: ABSPodcastEpisodeListItem
  let model: AppModel
  var opensDetailOnTap = true
  /// Offline-Downloadliste: immer kompakte Zeilen, unabhängig von Settings.
  var forceCompactListStyle = false

  private var usesHeroCoverStyle: Bool {
    !forceCompactListStyle && model.libraryPodcastCardStyle == .heroCover
  }

  var body: some View {
    if usesHeroCoverStyle {
      LibraryHeroPodcastEpisodeCard(
        episode: episode,
        model: model,
        opensDetailOnTap: opensDetailOnTap
      )
    } else {
      PodcastEpisodeRowCard(
        episode: episode,
        model: model,
        opensDetailOnTap: opensDetailOnTap
      )
    }
  }
}

/// Podcast-Cover-Karte im Library-Hero-Stil (Rasterzelle, ohne Play-Pille und Typ-Badge).
private struct LibraryHeroPodcastEpisodeCard: View {
  let episode: ABSPodcastEpisodeListItem
  let model: AppModel
  var opensDetailOnTap = true

  @StateObject private var live: LibraryPodcastEpisodeRowLiveState
  @State private var tint: Color = AppTheme.card
  @State private var showDetail = false

  init(
    episode: ABSPodcastEpisodeListItem,
    model: AppModel,
    opensDetailOnTap: Bool = true
  ) {
    self.episode = episode
    self.opensDetailOnTap = opensDetailOnTap
    self.model = model
    _live = StateObject(
      wrappedValue: LibraryPodcastEpisodeRowLiveState(
        progressLookupKey: episode.progressLookupKey,
        offlineStorageId: model.podcastEpisodeOfflineStorageId(episode),
        model: model
      )
    )
  }

  private var prog: ABSUserMediaProgress? { live.progress }

  private var resolvedTotalDurationSeconds: Double {
    if episode.duration > 0 { return episode.duration }
    if let p = prog, p.duration > 0 { return p.duration }
    return 0
  }

  private var showLine: String {
    let s = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty ? "—" : s
  }

  private var heroProgress01: Double? {
    guard let p = prog, !p.isFinished else { return nil }
    let total = max(p.duration, resolvedTotalDurationSeconds)
    if total > 0 {
      let t = p.currentTime / total
      if t.isFinite { return min(1, max(0, t)) }
    }
    let g = p.progress
    if g > 0, g <= 1 { return min(1, max(0, g)) }
    return nil
  }

  private var isFinished: Bool { prog?.isFinished == true }

  var body: some View {
    let palette = model.appearancePalette
    let coverInset = AppTheme.Layout.libraryRowCardInset
    let coverTopRadius = AppTheme.Layout.coverCornerRadius
    let barH = AppTheme.Layout.libraryRowBottomProgressHeight
    let coverClip = UnevenRoundedRectangle(
      topLeadingRadius: coverTopRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: coverTopRadius,
      style: .continuous
    )

    Group {
      if opensDetailOnTap {
        cardBody(palette: palette, coverInset: coverInset, coverClip: coverClip, barH: barH)
          .navigationDestination(isPresented: $showDetail) {
            PodcastEpisodeDetailView(episode: episode)
          }
      } else {
        cardBody(palette: palette, coverInset: coverInset, coverClip: coverClip, barH: barH)
      }
    }
    .task(id: episode.progressLookupKey) {
      let account = model.coverImageCacheAccountDirectory()
      let itemId = episode.libraryItemId
      if let c = CoverDerivedTintLoader.colorFromDiskOrCoverCache(account: account, itemId: itemId) {
        tint = c
      }
      if let c = await CoverDerivedTintLoader.colorFromNetwork(
        account: account,
        itemId: itemId,
        coverURL: model.coverURL(for: itemId),
        token: model.token
      ) {
        tint = c
      }
    }
  }

  @ViewBuilder
  private func cardBody(
    palette: AppColorPalette,
    coverInset: CGFloat,
    coverClip: UnevenRoundedRectangle,
    barH: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .bottom) {
        tint
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        CoverImageView(
          url: model.coverURL(for: episode.libraryItemId),
          token: model.token,
          itemId: episode.libraryItemId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision,
          contentMode: .fit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(coverClip)
        .contentShape(coverClip)
        .onTapGesture {
          if opensDetailOnTap {
            showDetail = true
          }
        }
        .accessibilityLabel(episode.episodeTitle)
        .accessibilityHint(opensDetailOnTap ? "Opens episode details." : "")

        LinearGradient(
          stops: [
            .init(color: .black.opacity(0.45), location: 0),
            .init(color: .black.opacity(0), location: 1),
          ],
          startPoint: .bottom,
          endPoint: .top
        )
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)

        Group {
          if let v = heroProgress01 {
            AbstandCardBottomProgress(value: v, height: barH)
            .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          }
        }
      }
      .aspectRatio(1, contentMode: .fit)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .topTrailing) {
        ContinueListeningHeroPodcastOfflineBadgeSlot(rowLive: live)
          .fixedSize()
      }
      .clipped()

      VStack(alignment: .leading, spacing: 0) {
        ContinueListeningHeroMetadataBlock(
          title: episode.episodeTitle,
          detailLabel: "Show",
          detailValue: showLine,
          horizontalInset: coverInset,
          onTitleTap: { if opensDetailOnTap { showDetail = true } },
          includesBottomPadding: false,
          blockHeight: AppTheme.Layout.libraryHeroMetadataBlockHeight
            - AppTheme.Layout.continueHeroMetadataExtraBottomPadding
        )
        LibraryHeroCardMetadataFooter(
          durationLabel: formatPlaybackTime(resolvedTotalDurationSeconds),
          showsDownload: true,
          isDownloaded: live.isDownloaded,
          isDownloading: live.isDownloading,
          downloadProgress: live.downloadProgress,
          isFinished: isFinished,
          horizontalInset: coverInset,
          onRemoveDownload: {
            model.removeLocalDownload(bookId: model.podcastEpisodeOfflineStorageId(episode))
          },
          onToggleFinished: model.isNetworkReachable
            ? {
              Task {
                if isFinished {
                  await model.markPodcastEpisodeUnfinished(episode)
                } else {
                  await model.markPodcastEpisodeFinished(episode)
                }
              }
            }
            : nil
        )
      }
      .background(palette.card)
    }
    .background(palette.card)
    .clipShape(
      RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous)
    )
    .abstandHeroCardOutline(palette: palette)
    .frame(maxWidth: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityHint(opensDetailOnTap ? "Opens episode details." : "")
  }
}

// MARK: - Home „Continue listening“ (Hero-Karten)

struct ContinueListeningHeroBookCard: View {
  @EnvironmentObject private var model: AppModel
  let book: ABSBook
  @StateObject private var rowLive: LibraryBookRowLiveState
  @State private var tint: Color = AppTheme.card
  @State private var showDetail = false

  init(book: ABSBook, model: AppModel) {
    self.book = book
    _rowLive = StateObject(
      wrappedValue: LibraryBookRowLiveState(bookId: book.id, model: model)
    )
  }

  private var prog: ABSUserMediaProgress? { rowLive.progress }

  private var totalDuration: Double {
    max(book.media.duration ?? 0, prog?.duration ?? 0)
  }

  /// Anzeige in der Play-Pille: Restlaufzeit (ohne Fortschritt = volle Dauer).
  private var playPillRemainingCaption: String {
    let total = max(0, totalDuration)
    guard total > 0 else { return formatPlaybackDurationShortHuman(0) }
    guard let p = prog else { return formatPlaybackDurationShortHuman(total) }
    if p.isFinished { return formatPlaybackDurationShortHuman(0) }
    let elapsed: Double
    if p.currentTime > 0 {
      elapsed = min(total, p.currentTime)
    } else if p.duration > 0, p.progress > 0, p.progress <= 1 {
      elapsed = min(total, p.progress * p.duration)
    } else {
      elapsed = 0
    }
    return formatPlaybackDurationShortHuman(max(0, total - elapsed))
  }

  private var heroProgress01: Double? {
    guard let p = prog, !p.isFinished, p.duration > 0 else { return nil }
    return min(1, max(0, p.progress))
  }

  var body: some View {
    let w = AppTheme.Layout.continueHeroCardWidth
    let h = AppTheme.Layout.continueHeroCoverMaxHeight
    let barH = AppTheme.Layout.libraryRowBottomProgressHeight
    let coverInset = AppTheme.Layout.libraryRowCardInset
    let coverTopRadius = AppTheme.Layout.coverCornerRadius
    let coverClip = UnevenRoundedRectangle(
      topLeadingRadius: coverTopRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: coverTopRadius,
      style: .continuous
    )

    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .bottom) {
        tint
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        CoverImageView(
          url: model.coverURL(for: book.id),
          token: model.token,
          itemId: book.id,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt),
          contentMode: .fit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(coverClip)
        .contentShape(coverClip)
        .onTapGesture { showDetail = true }
        .accessibilityLabel(book.displayTitle)
        .accessibilityHint("Informationen öffnen")

        LinearGradient(
          stops: [
            .init(color: .black.opacity(0.45), location: 0),
            .init(color: .black.opacity(0), location: 1),
          ],
          startPoint: .bottom,
          endPoint: .top
        )
        .frame(height: min(72, h * 0.28))
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)

        Group {
          if let v = heroProgress01 {
            AbstandCardBottomProgress(value: v, height: barH)
            .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          }
        }
      }
      .overlay(alignment: .topLeading) {
        ContinueListeningHeroTypePill(type: .audiobook)
          .fixedSize()
      }
      .overlay(alignment: .topTrailing) {
        ContinueListeningHeroBookOfflineBadgeSlot(rowLive: rowLive)
          .fixedSize()
      }
      .frame(width: w, height: h)
      .clipped()

      ContinueListeningHeroTextBlock(
        title: book.displayTitle,
        detailLabel: "Author",
        detailValue: continueHeroAuthorSingleLine(for: book),
        horizontalInset: coverInset,
        onTitleTap: { showDetail = true }
      ) {
        continueHeroPlayPill(
          accent: model.appearanceAccentColor,
          palette: model.appearancePalette,
          caption: playPillRemainingCaption
        ) {
          Task { await model.play(book: book) }
        }
      }
      .background(model.appearancePalette.card)
    }
    .frame(width: w, height: AppTheme.Layout.continueHeroCardTotalHeight, alignment: .top)
    .background(model.appearancePalette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous))
    .abstandHeroCardOutline(palette: model.appearancePalette)
    .task(id: book.id) {
      let account = model.coverImageCacheAccountDirectory()
      let revision = model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
      if let c = CoverDerivedTintLoader.colorFromDiskOrCoverCache(
        account: account, itemId: book.id, revision: revision)
      {
        tint = c
      }
      if let c = await CoverDerivedTintLoader.colorFromNetwork(
        account: account,
        itemId: book.id,
        revision: revision,
        coverURL: model.coverURL(for: book.id),
        token: model.token
      ) {
        tint = c
      }
    }
    .navigationDestination(isPresented: $showDetail) {
      BookDetailView(bookId: book.id)
    }
  }
}

struct ContinueListeningHeroPodcastCard: View {
  @EnvironmentObject private var model: AppModel
  let episode: ABSPodcastEpisodeListItem
  @StateObject private var rowLive: LibraryPodcastEpisodeRowLiveState
  @State private var tint: Color = AppTheme.card
  @State private var showDetail = false

  init(episode: ABSPodcastEpisodeListItem, model: AppModel) {
    self.episode = episode
    _rowLive = StateObject(
      wrappedValue: LibraryPodcastEpisodeRowLiveState(
        progressLookupKey: episode.progressLookupKey,
        offlineStorageId: model.podcastEpisodeOfflineStorageId(episode),
        model: model
      )
    )
  }

  private var prog: ABSUserMediaProgress? { rowLive.progress }

  private var resolvedTotalDurationSeconds: Double {
    if episode.duration > 0 { return episode.duration }
    if let p = prog, p.duration > 0 { return p.duration }
    return 0
  }

  /// Anzeige in der Play-Pille: Restlaufzeit (ohne Fortschritt = volle Dauer).
  private var playPillRemainingCaption: String {
    let total = max(0, resolvedTotalDurationSeconds)
    guard total > 0 else { return formatPlaybackDurationShortHuman(0) }
    guard let p = prog else { return formatPlaybackDurationShortHuman(total) }
    if p.isFinished { return formatPlaybackDurationShortHuman(0) }
    let elapsed: Double
    if p.currentTime > 0 {
      elapsed = min(total, p.currentTime)
    } else {
      let basis = max(p.duration, total)
      if basis > 0, p.progress > 0, p.progress <= 1 {
        elapsed = min(total, p.progress * basis)
      } else {
        elapsed = 0
      }
    }
    return formatPlaybackDurationShortHuman(max(0, total - elapsed))
  }

  private var heroProgress01: Double? {
    guard let p = prog, !p.isFinished else { return nil }
    let total = max(p.duration, resolvedTotalDurationSeconds)
    if total > 0 {
      let t = p.currentTime / total
      if t.isFinite { return min(1, max(0, t)) }
    }
    let g = p.progress
    if g > 0, g <= 1 { return min(1, max(0, g)) }
    return nil
  }

  var body: some View {
    let w = AppTheme.Layout.continueHeroCardWidth
    let h = AppTheme.Layout.continueHeroCoverMaxHeight
    let barH = AppTheme.Layout.libraryRowBottomProgressHeight
    let coverInset = AppTheme.Layout.libraryRowCardInset
    let coverTopRadius = AppTheme.Layout.coverCornerRadius
    let coverClip = UnevenRoundedRectangle(
      topLeadingRadius: coverTopRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: coverTopRadius,
      style: .continuous
    )

    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .bottom) {
        tint
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        CoverImageView(
          url: model.coverURL(for: episode.libraryItemId),
          token: model.token,
          itemId: episode.libraryItemId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision,
          contentMode: .fit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(coverClip)
        .contentShape(coverClip)
        .onTapGesture { showDetail = true }
        .accessibilityLabel(episode.episodeTitle)
        .accessibilityHint("Informationen öffnen")

        LinearGradient(
          stops: [
            .init(color: .black.opacity(0.45), location: 0),
            .init(color: .black.opacity(0), location: 1),
          ],
          startPoint: .bottom,
          endPoint: .top
        )
        .frame(height: min(72, h * 0.28))
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)

        Group {
          if let v = heroProgress01 {
            AbstandCardBottomProgress(value: v, height: barH)
            .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          }
        }
      }
      .overlay(alignment: .topLeading) {
        ContinueListeningHeroTypePill(type: .podcast)
          .fixedSize()
      }
      .overlay(alignment: .topTrailing) {
        ContinueListeningHeroPodcastOfflineBadgeSlot(rowLive: rowLive)
          .fixedSize()
      }
      .frame(width: w, height: h)
      .clipped()

      ContinueListeningHeroTextBlock(
        title: episode.episodeTitle,
        detailLabel: "Show",
        detailValue: {
          let s = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
          return s.isEmpty ? "—" : s
        }(),
        horizontalInset: coverInset,
        onTitleTap: { showDetail = true }
      ) {
        continueHeroPlayPill(
          accent: model.appearanceAccentColor,
          palette: model.appearancePalette,
          caption: playPillRemainingCaption
        ) {
          Task { await model.playPodcastEpisode(episode) }
        }
      }
      .background(model.appearancePalette.card)
    }
    .frame(width: w, height: AppTheme.Layout.continueHeroCardTotalHeight, alignment: .top)
    .background(model.appearancePalette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous))
    .abstandHeroCardOutline(palette: model.appearancePalette)
    .task(id: episode.progressLookupKey) {
      let account = model.coverImageCacheAccountDirectory()
      let itemId = episode.libraryItemId
      if let c = CoverDerivedTintLoader.colorFromDiskOrCoverCache(account: account, itemId: itemId) {
        tint = c
      }
      if let c = await CoverDerivedTintLoader.colorFromNetwork(
        account: account,
        itemId: itemId,
        coverURL: model.coverURL(for: itemId),
        token: model.token
      ) {
        tint = c
      }
    }
    .navigationDestination(isPresented: $showDetail) {
      PodcastEpisodeDetailView(episode: episode)
    }
  }
}

// MARK: - Browse / search entity row (Autor, Serie, Sprecher, …)

// MARK: - Facet tiles (Collections / Genres / Tags) ohne Cover

private enum FacetBrowseTileMetrics {
  static let tileHeight: CGFloat = 93
  /// Wie `BookRowCard` / `BrowseEntityRowCard` (`libraryRowTitleText`).
  static let titleFont: Font = .headline.weight(.semibold)
  /// Wie `ContinueListeningHeroCoverPill` (äußeres Seiten-Padding).
  static let edgeInset: CGFloat = 8
  static let iconFont: Font = .title3.weight(.semibold)
  static let contentPadding: CGFloat = 14
}

private struct FacetBrowseTileCard: View {
  @EnvironmentObject private var model: AppModel
  let kind: BooksBrowseSection
  let title: String
  let count: Int?

  var body: some View {
    facetBrowseTileCardChrome(
      palette: model.appearancePalette,
      title: title,
      count: count,
      accessibilityLabel: facetBrowseTileAccessibilityLabel
    ) {
      facetBrowseTileLeadingIcon(systemImage: kind.systemImage)
    }
  }

  private var facetBrowseTileAccessibilityLabel: String {
    if let c = count, c > 0 {
      return "\(kind.rawValue): \(title), \(c) books"
    }
    return "\(kind.rawValue): \(title)"
  }
}

@ViewBuilder
private func facetBrowseTileCardChrome<Leading: View>(
  palette: AppColorPalette,
  title: String,
  count: Int?,
  accessibilityLabel: String,
  @ViewBuilder leading: () -> Leading
) -> some View {
  let cardShape = RoundedRectangle(
    cornerRadius: LibraryRowLayout.cornerRadius,
    style: .continuous
  )

  ZStack(alignment: .topLeading) {
    cardShape
      .fill(palette.card)
    leading()
      .allowsHitTesting(false)
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 0)
      Text(title)
        .font(FacetBrowseTileMetrics.titleFont)
        .foregroundStyle(palette.textPrimary)
        .lineLimit(2)
        .truncationMode(.tail)
        .multilineTextAlignment(.leading)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(FacetBrowseTileMetrics.contentPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
  }
  .frame(height: FacetBrowseTileMetrics.tileHeight)
  .clipShape(cardShape)
  .abstandCardElevation(.standard)
  .overlay(alignment: .topTrailing) {
    if let c = count, c > 0 {
      ContinueListeningHeroCoverPill {
        Text("\(c) Books")
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.white)
          .lineLimit(1)
      }
      .fixedSize()
    }
  }
  .accessibilityElement(children: .combine)
  .accessibilityLabel(accessibilityLabel)
}

@ViewBuilder
private func facetBrowseTileLeadingInset<Content: View>(@ViewBuilder content: () -> Content) -> some View {
  content()
    .padding(FacetBrowseTileMetrics.edgeInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityHidden(true)
}

@ViewBuilder
private func facetBrowseTileLeadingIcon(systemImage: String) -> some View {
  facetBrowseTileLeadingInset {
    Image(systemName: systemImage)
        .font(FacetBrowseTileMetrics.iconFont)
      .abstandAccentForeground()
  }
}

func browseEntityBooksCountLine(count: Int?) -> String? {
  guard let c = count, c > 0 else { return nil }
  return "\(c)"
}

/// Serien-Cover: bis zu vier Miniatur-Covers im 82×82-Slot (2×2, bei 2–3 Büchern angepasst).
private struct SeriesMultiCoverView: View {
  @EnvironmentObject private var model: AppModel
  let bookIds: [String]

  private static let gap: CGFloat = 1

  var body: some View {
    let ids = Array(bookIds.prefix(4))
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let g = Self.gap
      let cellW = (w - g) / 2
      let cellH = (h - g) / 2

      switch ids.count {
      case 2:
        HStack(spacing: g) {
          coverTile(id: ids[0], width: (w - g) / 2, height: h)
          coverTile(id: ids[1], width: (w - g) / 2, height: h)
        }
      case 3:
        VStack(spacing: g) {
          HStack(spacing: g) {
            coverTile(id: ids[0], width: cellW, height: cellH)
            coverTile(id: ids[1], width: cellW, height: cellH)
          }
          HStack(spacing: g) {
            coverTile(id: ids[2], width: cellW, height: cellH)
            Color.clear.frame(width: cellW, height: cellH)
          }
        }
      default:
        VStack(spacing: g) {
          HStack(spacing: g) {
            coverTile(id: ids[0], width: cellW, height: cellH)
            coverTile(id: ids[1], width: cellW, height: cellH)
          }
          HStack(spacing: g) {
            coverTile(id: ids[2], width: cellW, height: cellH)
            coverTile(id: ids[3], width: cellW, height: cellH)
          }
        }
      }
    }
    .frame(width: LibraryRowLayout.coverSide, height: LibraryRowLayout.coverSide)
  }

  @ViewBuilder
  private func coverTile(id: String, width: CGFloat, height: CGFloat) -> some View {
    SquareCoverImageView(
      url: model.coverURL(for: id),
      token: model.token,
      itemId: id,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheRevision: model.coverImageCacheRevision
    )
    .frame(width: width, height: height)
    .clipped()
    .accessibilityHidden(true)
  }
}

/// Gleiches Kartenlayout wie `BookRowCard`: Cover 1:1 mit Letterboxing.
struct BrowseEntityRowCard: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  let detailLabel: String
  let detailValue: String?
  let cacheItemId: String
  let coverURL: URL?
  /// Mehrere Serien-Bücher: 2–4 Covers im gleichen Slot statt einem einzelnen Cover.
  var coverBookIds: [String]? = nil
  /// Optional (z. B. Serien): zweite Meta-Zeile wie bei `BookRowCard`.
  var authorLine: String? = nil
  /// Autoren-Portraits: fest 1:1, Mitte beschnitten.
  var usesSquareCenterCropCover = false

  var body: some View {
    HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
      if usesSquareCenterCropCover, coverBookIds == nil || (coverBookIds?.count ?? 0) <= 1 {
        LibraryRowLayout.coverSlot(coverWidth: LibraryRowLayout.coverSide) {
          LibraryRowLayout.rowCoverImageSquare(
            url: coverURL,
            token: model.token,
            itemId: cacheItemId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision
          )
        }
      } else {
        LibraryRowLayout.coverSlot {
          if let ids = coverBookIds, ids.count > 1 {
            SeriesMultiCoverView(bookIds: ids)
          } else {
            LibraryRowLayout.rowCoverImage(
              url: coverURL,
              token: model.token,
              itemId: cacheItemId,
              cacheAccount: model.coverImageCacheAccountDirectory(),
              cacheRevision: model.coverImageCacheRevision
            )
          }
        }
      }

      LibraryRowLayout.metadataColumn(showsProgressBar: false) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(model.appearancePalette.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
          if let authorLine {
            LibraryRowCollapsedMetaLine(label: "Author", value: authorLine, valueLineLimit: 1)
          }
          Spacer(minLength: 0)
          LibraryRowCollapsedMetaLine(label: detailLabel, value: detailValue)
        }
      }
    }
    .padding(.leading, 0)
    .background(model.appearancePalette.card)
    .clipShape(LibraryRowLayout.cardShape)
    .abstandCardElevation(.standard)
  }
}

// MARK: - Podcast show row

/// Podcast-Sendung in Listen — gleiches Layout wie `BookRowCard` (ohne Play-Badge).
struct PodcastShowRowCard: View {
  @EnvironmentObject private var model: AppModel
  let show: ABSBook
  var showsDownloadStatus = true

  var body: some View {
    let palette = model.appearancePalette
    return VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        LibraryRowLayout.coverSlot {
          LibraryRowLayout.rowCoverImage(
            url: model.coverURL(for: show.id),
            token: model.token,
            itemId: show.id,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: show.updatedAt)
          )
          .accessibilityHidden(true)
        }

        LibraryRowLayout.metadataColumn(showsProgressBar: false) {
          VStack(alignment: .leading, spacing: 2) {
            Text(show.displayTitle)
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            BookCollapsedAuthorLine(book: show)
            Spacer(minLength: 0)
            LibraryRowLayout.metadataFooter {
              Group {
                if let episodes = show.media.numTracks, episodes > 0 {
                  Text("\(episodes) episodes")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                } else if show.totalDuration > 0 {
                  Text(formatPlaybackTime(show.totalDuration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                }
              }
            } trailing: {
              downloadIcon
            }
          }
        }
      }
      .padding(.leading, 0)
    }
    .background(palette.card)
    .clipShape(LibraryRowLayout.cardShape)
    .abstandCardElevation(.standard)
    .abstandThemeRefresh()
  }

  @ViewBuilder
  private var downloadIcon: some View {
    if !showsDownloadStatus {
      EmptyView()
    } else if model.downloadedItemIds.contains(show.id) {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(model.appearanceAccentColor)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if model.downloads.activeItemId == show.id {
      ProgressView(value: model.downloads.progress)
        .frame(width: 36)
        .tint(model.appearanceAccentColor)
        .accessibilityLabel("Downloading")
    } else if model.downloads.queuedItemIds.contains(show.id) {
      Image(systemName: "circle.dashed")
        .foregroundStyle(model.appearanceAccentColor)
        .font(.caption)
        .accessibilityLabel("Queued")
    }
  }
}

// MARK: - Library row layout (Cover bündig links/oben/unten)

enum LibraryRowLayout {
  static let coverSide = AppTheme.Layout.libraryRowCoverSide
  static let cornerRadius = AppTheme.Layout.libraryRowCornerRadius
  static let cardInset = AppTheme.Layout.libraryRowCardInset
  static let textInset = AppTheme.Layout.libraryRowTextInset

  static var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  static func bodyBottomInset(showsProgressBar: Bool) -> CGFloat {
    showsProgressBar
      ? textInset + AppTheme.Layout.libraryRowBottomProgressHeight
      : textInset
  }

  /// Textspalte: feste Höhe neben dem Cover, Titel oben / Meta unten.
  @ViewBuilder
  static func metadataColumn<Content: View>(
    showsProgressBar: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .frame(height: metadataMinHeight(showsProgressBar: showsProgressBar))
      .padding(.top, textInset)
      .padding(.trailing, textInset)
      .padding(.bottom, bodyBottomInset(showsProgressBar: showsProgressBar))
  }

  @ViewBuilder
  static func bottomProgressOverlay(value: Double, visible: Bool) -> some View {
    if visible {
      AbstandCardBottomProgress(
        value: value,
        height: AppTheme.Layout.libraryRowBottomProgressHeight,
        trackColor: AppTheme.progressTrack
      )
      .frame(maxWidth: .infinity)
      .accessibilityLabel("Playback progress")
      .accessibilityValue("\(Int(min(100, max(0, value * 100)))) percent")
    }
  }

  /// Text-Inhalt innerhalb der Zeile; mit `textInset` oben/unten = `coverSide`.
  static func metadataMinHeight(showsProgressBar: Bool) -> CGFloat {
    coverSide - textInset - bodyBottomInset(showsProgressBar: showsProgressBar)
  }

  /// Kartenhülle: volle Fläche (inkl. Leerzonen) öffnet Details; Play bleibt eigener Button.
  @ViewBuilder
  static func libraryRowCardChrome<Content: View>(
    cardColor: Color,
    showsBottomProgressBar: Bool,
    progressValue: Double,
    openDetails: (() -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let base = VStack(alignment: .leading, spacing: 0) {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: coverSide, alignment: .top)
        .padding(.leading, 0)
    }
    .overlay(alignment: .bottom) {
      bottomProgressOverlay(value: progressValue, visible: showsBottomProgressBar)
        .allowsHitTesting(false)
    }
    .background(cardColor)
    .clipShape(cardShape)
    .contentShape(cardShape)
    .abstandCardElevation(.standard)
    .overlay {
      cardShape.strokeBorder(AppTheme.palette.textSecondary.opacity(0.22), lineWidth: 1)
    }

    if let openDetails {
      base.onTapGesture(perform: openDetails)
    } else {
      base
    }
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

  /// Listen-Zeilen: festes 1:1 mit zentriertem Cover und farbigem Letterboxing.
  @ViewBuilder
  static func rowCoverImage(
    url: URL?,
    token: String,
    itemId: String,
    cacheAccount: URL?,
    cacheRevision: Int = 0,
    requiresAuthorization: Bool = true
  ) -> some View {
    SquareCoverImageView(
      url: url,
      token: token,
      itemId: itemId,
      cacheAccount: cacheAccount,
      cacheRevision: cacheRevision,
      requiresAuthorization: requiresAuthorization
    )
  }

  /// Autoren-Portraits / Bücher auf Autor-Detail: fest 1:1, Mitte beschnitten (`scaledToFill`).
  @ViewBuilder
  static func rowCoverImageSquare(
    url: URL?,
    token: String,
    itemId: String,
    cacheAccount: URL?,
    cacheRevision: Int = 0,
    requiresAuthorization: Bool = true
  ) -> some View {
    CoverImageView(
      url: url,
      token: token,
      itemId: itemId,
      cacheAccount: cacheAccount,
      cacheRevision: cacheRevision,
      requiresAuthorization: requiresAuthorization,
      contentMode: .fill
    )
  }

  /// Cover-Slot in Listen-Zeilen: immer 1:1.
  @ViewBuilder
  static func coverSlot<Cover: View, Overlay: View>(
    coverWidth: CGFloat? = nil,
    @ViewBuilder cover: () -> Cover,
    @ViewBuilder overlay: () -> Overlay = { EmptyView() }
  ) -> some View {
    let side = coverWidth ?? coverSide
    cover()
      .frame(width: side, height: side)
      .clipShape(coverClipShape)
      .overlay(alignment: .bottomLeading) {
        overlay()
      }
  }

  /// Untere Meta-Zeile: Laufzeit/Labels links, Status-Icons (Download, Fertig) am rechten Kartenrand.
  @ViewBuilder
  static func metadataFooter<Leading: View, Trailing: View>(
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(alignment: .center, spacing: 8) {
      HStack(spacing: 8) {
        leading()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 6) {
        trailing()
      }
      .fixedSize(horizontal: true, vertical: false)
    }
  }
}

/// Footer unter Cover-Karten — gleiches Layout und Icons wie `BookRowCard` / `PodcastEpisodeRowCard`.
private struct LibraryHeroCardMetadataFooter: View {
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let durationLabel: String
  var showsDownload: Bool
  var isDownloaded: Bool
  var isDownloading: Bool
  var downloadProgress: Double
  var isFinished: Bool
  var horizontalInset: CGFloat
  var onRemoveDownload: (() -> Void)?
  var onToggleFinished: (() -> Void)?

  var body: some View {
    let _ = themeRevision
    return LibraryRowLayout.metadataFooter {
      Text(durationLabel)
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(AppTheme.textSecondary)
    } trailing: {
      HStack(spacing: 6) {
        if isFinished {
          libraryHeroStatusIconButton(action: onToggleFinished) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(themeAccent)
              .font(.caption)
          }
          .accessibilityLabel("Finished")
        }
        if showsDownload {
          libraryHeroDownloadTrailingIcon
        }
      }
    }
    .padding(.horizontal, horizontalInset)
    .padding(.bottom, AppTheme.Layout.continueHeroMetadataExtraBottomPadding)
    .abstandThemeRefresh()
  }

  @ViewBuilder
  private var libraryHeroDownloadTrailingIcon: some View {
    if isDownloaded {
      libraryHeroStatusIconButton(action: onRemoveDownload) {
        Image(systemName: "arrow.down.circle.fill")
          .foregroundStyle(themeAccent)
          .font(.caption)
      }
      .accessibilityLabel("Saved offline")
    } else if isDownloading {
      ProgressView(value: downloadProgress)
        .frame(width: 36)
        .tint(themeAccent)
        .accessibilityLabel("Downloading")
    }
  }

  @ViewBuilder
  private func libraryHeroStatusIconButton<Label: View>(
    action: (() -> Void)?,
    @ViewBuilder label: () -> Label
  ) -> some View {
    if let action {
      Button(action: action) {
        label()
      }
      .buttonStyle(.plain)
    } else {
      label()
    }
  }
}

// MARK: - Book row

/// Einspaltige Lazy-Liste — Hero-Raster (2 Spalten) baut der Aufrufer zeilenweise.
private struct LibraryCoverCardsFlow<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      content()
    }
  }
}

private struct LibraryBookCardsFlow<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    LibraryCoverCardsFlow(content: content)
  }
}

private struct LibraryPodcastCardsFlow<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    LibraryCoverCardsFlow(content: content)
  }
}

/// Hero-Karten zeilenweise (`LazyVGrid` vermeiden — Tab-Wechsel-Layout-Bug).
private struct LibraryHeroMultiColumnRows<Item: Identifiable, Card: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  let items: [Item]
  let columns: Int
  let spacing: CGFloat
  @ViewBuilder let card: (Item) -> Card

  /// iPad (`regular`-Breite): mehr Spalten, sonst wirken die großen Cover-Karten in der
  /// vollen Breite winzig verloren. Split View/Slide Over meldet `.compact` — bleibt unverändert.
  private var effectiveColumns: Int {
    let base = max(1, columns)
    return horizontalSizeClass == .regular ? base + 2 : base
  }

  var body: some View {
    let columnCount = effectiveColumns
    ForEach(Array(stride(from: 0, to: items.count, by: columnCount)), id: \.self) { start in
      HStack(alignment: .top, spacing: spacing) {
        ForEach(0..<columnCount, id: \.self) { offset in
          let index = start + offset
          if index < items.count {
            card(items[index])
              .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(maxWidth: .infinity, maxHeight: 1)
              .accessibilityHidden(true)
          }
        }
      }
    }
  }
}

private struct LibraryHeroTwoColumnRows<Item: Identifiable, Card: View>: View {
  let items: [Item]
  let spacing: CGFloat
  @ViewBuilder let card: (Item) -> Card

  var body: some View {
    LibraryHeroMultiColumnRows(items: items, columns: 2, spacing: spacing, card: card)
  }
}

/// Autor-/Serien-Detail: immer kompakte Zeile — unabhängig von Library-Card-Settings.
private struct AuthorDetailBookListCard: View {
  let book: ABSBook
  let model: AppModel

  var body: some View {
    LibraryBookListCard(
      book: book,
      model: model,
      forceCompactListStyle: true,
      usesSquareCenterCropCover: !book.isPureEbookLibraryItem
    )
  }
}

/// eBooks-Bereich im Books-Tab: kompakte Zeile oder Cover-Karte.
/// Karte für eBooks-/Supplementary-Tab — beide Listen sehen identisch aus; ob Play-Kontrollen
/// erscheinen, entscheidet einzig `book.isPlayableAudiobook`, nicht der Tab.
private struct EbookTabListCard: View {
  let book: ABSBook
  let model: AppModel

  private var usesHeroCoverStyle: Bool {
    model.libraryBookCardStyle == .heroCover
  }

  var body: some View {
    if usesHeroCoverStyle {
      // 1:1-Cover wie überall im Katalog — Portrait-eBook-Cover werden per Letterboxing gefüllt,
      // nicht als eigenes Seitenverhältnis behandelt.
      LibraryHeroBookRowCard(
        book: book,
        model: model,
        showEbookBadge: true,
        usesEbookProgressDisplay: true,
        showsDownloadStatus: true
      )
    } else {
      LibraryBookListCard(
        book: book,
        model: model,
        showEbookBadge: true,
        showsPlaybackControls: book.isPlayableAudiobook,
        opensDetailOnTap: true,
        usesEbookProgressDisplay: true
      )
    }
  }
}

/// Wählt kompakte Zeile oder Cover-Karte gemäß `libraryBookCardStyle`.
struct LibraryBookListCard: View {
  let book: ABSBook
  let model: AppModel
  var showEbookBadge = false
  var progressOverride: ABSUserMediaProgress?
  var authorLineOverride: String?
  var showsPlaybackControls = true
  var showsDownloadStatus = true
  var opensDetailOnTap = true
  /// Optionaler Cover-Tap, z. B. „Weiterlesen“ aus dem Continue-Reading-Regal.
  var onCoverOpen: (() -> Void)?
  /// Offline-Downloadliste: immer kompakte Zeilen, unabhängig von Settings.
  var forceCompactListStyle = false
  /// Autor-Detail: Cover fest 1:1, Mitte beschnitten.
  var usesSquareCenterCropCover = false
  /// eBooks-/Supplementary-Tab: Lesefortschritt statt Hörbuch-Dauer/-Fortschritt anzeigen.
  var usesEbookProgressDisplay = false

  private var usesHeroCoverStyle: Bool {
    !forceCompactListStyle && model.libraryBookCardStyle == .heroCover
  }

  var body: some View {
    if usesHeroCoverStyle {
      // `LibraryHeroBookRowCard` erkennt reine eBooks selbst (`isPureEbookLibraryItem`) und
      // zeigt automatisch Lesefortschritt statt Hörbuch-Dauer — kein Sonderfall nötig.
      LibraryHeroBookRowCard(
        book: book,
        model: model,
        showEbookBadge: showEbookBadge,
        usesEbookProgressDisplay: usesEbookProgressDisplay,
        progressOverride: progressOverride,
        authorLineOverride: authorLineOverride,
        showsDownloadStatus: showsDownloadStatus,
        opensDetailOnTap: opensDetailOnTap
      )
    } else {
      BookRowCard(
        book: book,
        model: model,
        showEbookBadge: showEbookBadge,
        progressOverride: progressOverride,
        authorLineOverride: authorLineOverride,
        showsPlaybackControls: showsPlaybackControls,
        showsDownloadStatus: showsDownloadStatus,
        opensDetailOnTap: opensDetailOnTap,
        onCoverOpen: onCoverOpen,
        usesSquareCenterCropCover: usesSquareCenterCropCover,
        usesEbookProgressDisplay: usesEbookProgressDisplay
      )
    }
  }
}

/// Library-Cover-Karte im Continue-Hero-Stil (Rasterzelle, ohne Play-Pille und Typ-Badge).
private struct LibraryHeroBookRowCard: View {
  let book: ABSBook
  let model: AppModel
  @Environment(\.appearanceThemeRevision) private var themeRevision
  var showEbookBadge = false
  var progressOverride: ABSUserMediaProgress?
  var authorLineOverride: String?
  var showsDownloadStatus = true
  var opensDetailOnTap = true
  /// Hero-Raster: immer 1:1 (`SquareCoverImageView` in `LibraryHeroBookRowCard`).
  var coverAspectRatio: CGFloat = 1
  /// eBook-Lesefortschritt in Balken auf dem Cover.
  var usesEbookProgressDisplay = false

  @StateObject private var live: LibraryBookRowLiveState
  @State private var showDetail = false
  private let supplementaryEbookBadge: Bool

  private var usesEbookMetrics: Bool {
    book.isPureEbookLibraryItem || usesEbookProgressDisplay
  }

  init(
    book: ABSBook,
    model: AppModel,
    showEbookBadge: Bool = false,
    usesEbookProgressDisplay: Bool = false,
    progressOverride: ABSUserMediaProgress? = nil,
    authorLineOverride: String? = nil,
    showsDownloadStatus: Bool = true,
    opensDetailOnTap: Bool = true,
    coverAspectRatio: CGFloat = 1
  ) {
    self.showEbookBadge = showEbookBadge
    self.usesEbookProgressDisplay = usesEbookProgressDisplay
    self.progressOverride = progressOverride
    self.authorLineOverride = authorLineOverride
    self.showsDownloadStatus = showsDownloadStatus
    self.opensDetailOnTap = opensDetailOnTap
    self.coverAspectRatio = coverAspectRatio
    self.model = model
    self.supplementaryEbookBadge = model.bookShowsSupplementaryEbookBadge(book)
    let resolvedBook = model.bookStubEnrichedForListDisplay(book)
    self.book = resolvedBook
    let ebookMetrics = resolvedBook.isPureEbookLibraryItem || usesEbookProgressDisplay
    _live = StateObject(
      wrappedValue: LibraryBookRowLiveState(
        bookId: resolvedBook.id,
        model: model,
        observesProgress: progressOverride == nil && !ebookMetrics,
        observesDownload: showsDownloadStatus,
        observesEbookProgress: ebookMetrics
      )
    )
  }

  private var prog: ABSUserMediaProgress? { progressOverride ?? live.progress }

  private var ebookProgress: Double? {
    guard usesEbookMetrics else { return nil }
    return live.ebookProgressFraction
  }

  private var heroProgress01: Double? {
    if usesEbookMetrics {
      guard let f = ebookProgress, f > 0.005, f < 0.995 else { return nil }
      return min(1, max(0, f))
    }
    guard let p = prog, !p.isFinished, p.duration > 0 else { return nil }
    return min(1, max(0, p.progress))
  }

  private var isFinished: Bool {
    if usesEbookMetrics {
      guard let f = ebookProgress else { return false }
      return f >= 0.995
    }
    return prog?.isFinished == true
  }

  private var showsAttachedEbookCoverBadge: Bool {
    supplementaryEbookBadge
  }

  /// Wie `ContinueListeningHeroTypePill`: Play für Hörbücher, Buch für reine eBooks.
  private var typeBadgeSystemImage: String? {
    if book.isPlayableAudiobook { return "play.fill" }
    if book.isPureEbookLibraryItem { return "book.closed.fill" }
    return nil
  }

  @ViewBuilder
  private var typeBadge: some View {
    if let systemImage = typeBadgeSystemImage {
      ContinueListeningHeroCoverPill {
        Image(systemName: systemImage)
          .font(ContinueListeningHeroCoverPillMetrics.iconFont)
          .foregroundStyle(.white)
      }
      .accessibilityLabel(book.isPlayableAudiobook ? "Playable as audiobook" : "eBook")
      .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var ebookAvailableBadge: some View {
    if showsAttachedEbookCoverBadge {
      ContinueListeningHeroCoverPill {
        Image(systemName: "book.closed.fill")
          .font(ContinueListeningHeroCoverPillMetrics.iconFont)
          .foregroundStyle(.white)
      }
      .accessibilityLabel("eBook available")
    }
  }

  var body: some View {
    let _ = themeRevision
    let palette = model.appearancePalette
    let coverInset = AppTheme.Layout.libraryRowCardInset
    let coverTopRadius = AppTheme.Layout.coverCornerRadius
    let barH = AppTheme.Layout.libraryRowBottomProgressHeight
    let coverClip = UnevenRoundedRectangle(
      topLeadingRadius: coverTopRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: coverTopRadius,
      style: .continuous
    )

    return Group {
      if opensDetailOnTap {
        cardBody(palette: palette, coverInset: coverInset, coverClip: coverClip, barH: barH)
          .navigationDestination(isPresented: $showDetail) {
            BookDetailView(bookId: book.id)
          }
      } else {
        cardBody(palette: palette, coverInset: coverInset, coverClip: coverClip, barH: barH)
      }
    }
    .abstandThemeRefresh()
  }

  private var authorLine: String {
    let override = authorLineOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !override.isEmpty { return override }
    let line = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return line.isEmpty ? "—" : line
  }

  private var resolvedTotalDurationSeconds: Double {
    max(book.media.duration ?? 0, prog?.duration ?? 0)
  }

  private var heroDurationLabel: String {
    if usesEbookMetrics {
      return LibraryRowLiveState.ebookProgressLabel(for: live.ebookProgressFraction)
        ?? formatPlaybackTime(0)
    }
    return formatPlaybackTime(resolvedTotalDurationSeconds)
  }

  @ViewBuilder
  private func cardBody(
    palette: AppColorPalette,
    coverInset: CGFloat,
    coverClip: UnevenRoundedRectangle,
    barH: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .bottom) {
        SquareCoverImageView(
          url: model.coverURL(for: book.id),
          token: model.token,
          itemId: book.id,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
        )
        .clipShape(coverClip)
        .contentShape(coverClip)
        .onTapGesture {
          if opensDetailOnTap {
            showDetail = true
          }
        }
        .accessibilityLabel(book.displayTitle)
        .accessibilityHint(opensDetailOnTap ? "Opens book details." : "")

        LinearGradient(
          stops: [
            .init(color: .black.opacity(0.45), location: 0),
            .init(color: .black.opacity(0), location: 1),
          ],
          startPoint: .bottom,
          endPoint: .top
        )
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)

        Group {
          if usesEbookMetrics, live.isPreparingEbook {
            ProgressView()
              .tint(.white)
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          } else if let v = heroProgress01 {
            AbstandCardBottomProgress(value: v, height: barH)
              .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          }
        }
      }
      .aspectRatio(coverAspectRatio, contentMode: .fit)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .topLeading) {
        // Wie `ContinueListeningHeroTypePill` — gleiche Größe/Padding, oben statt unten.
        typeBadge
          .fixedSize()
      }
      .overlay(alignment: .topTrailing) {
        HStack(spacing: 0) {
          ebookAvailableBadge
          if showsDownloadStatus {
            ContinueListeningHeroBookOfflineBadgeSlot(rowLive: live)
              .fixedSize()
          }
        }
      }
      .clipped()

      VStack(alignment: .leading, spacing: 0) {
        ContinueListeningHeroMetadataBlock(
          title: book.displayTitle,
          detailLabel: "Author",
          detailValue: authorLine,
          horizontalInset: coverInset,
          onTitleTap: {
            if opensDetailOnTap {
              showDetail = true
            }
          },
          includesBottomPadding: false,
          blockHeight: AppTheme.Layout.libraryHeroMetadataBlockHeight
            - AppTheme.Layout.continueHeroMetadataExtraBottomPadding
        )
        LibraryHeroCardMetadataFooter(
          durationLabel: heroDurationLabel,
          showsDownload: showsDownloadStatus,
          isDownloaded: live.isDownloaded,
          isDownloading: live.isDownloading,
          downloadProgress: live.downloadProgress,
          isFinished: isFinished,
          horizontalInset: coverInset,
          onRemoveDownload: { model.removeLocalDownload(bookId: book.id) },
          onToggleFinished: usesEbookMetrics || !model.isNetworkReachable
            ? nil
            : {
              Task {
                if isFinished {
                  await model.markUnfinished(bookId: book.id)
                } else {
                  await model.markFinished(bookId: book.id)
                }
              }
            }
        )
      }
      .background(palette.card)
    }
    .background(palette.card)
    .clipShape(
      RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous)
    )
    .abstandHeroCardOutline(palette: palette)
    .frame(maxWidth: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityHint(opensDetailOnTap ? "Opens book details." : "")
  }
}

/// Kompaktes Cover-Badge (Play / eBook) — unten links oder rechts auf Listen-Covers.
private struct LibraryCoverCornerBadge: View {
  let systemImage: String
  let accessibilityLabel: String
  var accessibilityHidden: Bool = false

  var body: some View {
    Image(systemName: systemImage)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.white)
      .frame(width: 18, height: 18)
      .background(AppTheme.coverPlayBadgeBackground)
      .clipShape(Circle())
      .padding(4)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHidden(accessibilityHidden)
  }
}

struct BookRowCard: View {
  let book: ABSBook
  /// Kein `@ObservedObject` — Fortschritt/Download über `LibraryBookRowLiveState`.
  let model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  /// In Listen mit eBook-Badge das Buch-Symbol auf dem Cover (unten rechts).
  var showEbookBadge = false
  /// Fortschritt aus anderem Kontext (z. B. Server-User-Detail), nicht `progressByItemId`.
  var progressOverride: ABSUserMediaProgress?
  /// Autor-Zeile unabhängig vom Stub (z. B. angereicherter Server-User-Fortschritt).
  var authorLineOverride: String?
  var showsPlaybackControls = true
  var showsDownloadStatus = true
  var opensDetailOnTap = true
  var onCoverOpen: (() -> Void)?
  /// Autor-Detail: Cover fest 1:1, Mitte beschnitten.
  var usesSquareCenterCropCover = false
  /// eBooks-/Supplementary-Tab: Lesefortschritt statt Hörbuch-Dauer/-Fortschritt anzeigen.
  var usesEbookProgressDisplay = false

  @StateObject private var live: LibraryBookRowLiveState
  @State private var showDetail = false
  private let supplementaryEbookBadge: Bool

  private var isPureEbookRow: Bool { book.isPureEbookLibraryItem }
  /// Reines eBook oder Hörbuch mit angehängtem eBook im eBooks-Tab — beide zeigen Lesefortschritt.
  private var usesEbookMetrics: Bool { isPureEbookRow || usesEbookProgressDisplay }
  private var showsAudiobookPlayControl: Bool { book.isPlayableAudiobook && showsPlaybackControls }
  private var showsAttachedEbookCoverBadge: Bool {
    supplementaryEbookBadge
  }

  init(
    book: ABSBook,
    model: AppModel,
    showEbookBadge: Bool = false,
    progressOverride: ABSUserMediaProgress? = nil,
    authorLineOverride: String? = nil,
    showsPlaybackControls: Bool = true,
    showsDownloadStatus: Bool = true,
    opensDetailOnTap: Bool = true,
    onCoverOpen: (() -> Void)? = nil,
    usesSquareCenterCropCover: Bool = false,
    usesEbookProgressDisplay: Bool = false
  ) {
    self.showEbookBadge = showEbookBadge
    self.progressOverride = progressOverride
    self.authorLineOverride = authorLineOverride
    self.showsPlaybackControls = showsPlaybackControls
    self.showsDownloadStatus = showsDownloadStatus
    self.opensDetailOnTap = opensDetailOnTap
    self.onCoverOpen = onCoverOpen
    self.usesSquareCenterCropCover = usesSquareCenterCropCover
    self.usesEbookProgressDisplay = usesEbookProgressDisplay
    self.model = model
    self.supplementaryEbookBadge = model.bookShowsSupplementaryEbookBadge(book)
    let resolvedBook = model.bookStubEnrichedForListDisplay(book)
    self.book = resolvedBook
    let ebookMetrics = resolvedBook.isPureEbookLibraryItem || usesEbookProgressDisplay
    _live = StateObject(
      wrappedValue: LibraryBookRowLiveState(
        bookId: resolvedBook.id,
        model: model,
        observesProgress: progressOverride == nil && !ebookMetrics,
        observesDownload: showsDownloadStatus,
        observesEbookProgress: ebookMetrics
      )
    )
  }

  private var prog: ABSUserMediaProgress? { progressOverride ?? live.progress }

  private var ebookProgress: Double? {
    guard usesEbookMetrics else { return nil }
    return live.ebookProgressFraction
  }

  private var ebookProgressLabel: String? {
    guard usesEbookMetrics else { return nil }
    return LibraryRowLiveState.ebookProgressLabel(for: live.ebookProgressFraction)
  }

  private var showsBottomProgressBar: Bool {
    if usesEbookMetrics {
      guard let f = ebookProgress, f > 0.005, f < 0.995 else { return false }
      return true
    }
    guard let p = prog, !p.isFinished, p.duration > 0 else { return false }
    return true
  }

  private var bottomProgressValue: Double {
    if usesEbookMetrics, let f = ebookProgress { return min(1, max(0, f)) }
    if let p = prog, p.duration > 0 { return min(1, max(0, p.progress)) }
    return 0
  }

  var body: some View {
    let _ = themeRevision
    return Group {
      if opensDetailOnTap {
        bookRowCardBody
          .navigationDestination(isPresented: $showDetail) {
            BookDetailView(bookId: book.id)
          }
      } else {
        bookRowCardBody
      }
    }
    .abstandThemeRefresh()
  }

  private var bookRowCardBody: some View {
    LibraryRowLayout.libraryRowCardChrome(
      cardColor: AppTheme.card,
      showsBottomProgressBar: showsBottomProgressBar,
      progressValue: bottomProgressValue,
      openDetails: opensDetailOnTap ? { showDetail = true } : nil
    ) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        Group {
          if let onCoverOpen {
            Button(action: onCoverOpen) {
              libraryRowCoverWithPlayBadge
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue reading")
            .accessibilityHint("Opens this eBook at your reading position.")
          } else if showsAudiobookPlayControl {
            Button {
              Task { await model.play(book: book) }
            } label: {
              libraryRowCoverWithPlayBadge
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play")
            .accessibilityHint("Starts playback of this audiobook.")
          } else {
            libraryRowCoverWithPlayBadge
          }
        }

        LibraryRowLayout.metadataColumn(showsProgressBar: showsBottomProgressBar) {
          if showsPlaybackControls {
            libraryRowInteractiveMetadataBlock
          } else {
            libraryRowStaticMetadataBlock
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityHint(
      onCoverOpen != nil
        ? "Cover opens this eBook at your reading position. The rest opens book details."
        : opensDetailOnTap
          ? "Opens book details. Play button starts playback."
          : "Play button starts playback."
    )
  }

  private var libraryRowCoverWithPlayBadge: some View {
    let side = LibraryRowLayout.coverSide
    return Group {
      if usesSquareCenterCropCover {
        LibraryRowLayout.rowCoverImageSquare(
          url: model.coverURL(for: book.id),
          token: model.token,
          itemId: book.id,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
        )
      } else {
        LibraryRowLayout.rowCoverImage(
          url: model.coverURL(for: book.id),
          token: model.token,
          itemId: book.id,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
        )
      }
    }
    .frame(width: side, height: side)
    .clipShape(LibraryRowLayout.coverClipShape)
    .overlay(alignment: .bottomLeading) {
      // Badge zeigt die tatsächliche Fähigkeit des Items (Hörbuch vs. eBook) — unabhängig davon,
      // ob der Cover-Tap in diesem Kontext auch wirklich Play auslöst (`showsAudiobookPlayControl`).
      if book.isPlayableAudiobook {
        LibraryCoverCornerBadge(systemImage: "play.fill", accessibilityLabel: "Play", accessibilityHidden: true)
      } else if isPureEbookRow {
        LibraryCoverCornerBadge(
          systemImage: "book.closed.fill", accessibilityLabel: "eBook", accessibilityHidden: true)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if showsAttachedEbookCoverBadge {
        LibraryCoverCornerBadge(systemImage: "book.closed.fill", accessibilityLabel: "eBook available")
      }
    }
  }

  private var libraryRowTitleText: some View {
    Text(book.displayTitle)
      .font(.headline.weight(.semibold))
      .foregroundStyle(AppTheme.textPrimary)
      .lineLimit(1)
      .truncationMode(.tail)
      .minimumScaleFactor(0.85)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var libraryRowInteractiveMetadataBlock: some View {
    VStack(alignment: .leading, spacing: 2) {
      libraryRowTitleText
      BookCollapsedAuthorLine(book: book, authorOverride: authorLineOverride)
      Spacer(minLength: 0)
      libraryRowMetaFooter
    }
    .padding(.trailing, 4)
  }

  private var libraryRowStaticMetadataBlock: some View {
    VStack(alignment: .leading, spacing: 2) {
      libraryRowTitleText
      BookCollapsedAuthorLine(book: book, authorOverride: authorLineOverride)
      Spacer(minLength: 0)
      libraryRowMetaFooter
    }
    .padding(.trailing, 4)
  }

  @ViewBuilder
  private var libraryRowMetaFooter: some View {
    LibraryRowLayout.metadataFooter {
      Group {
        if usesEbookMetrics {
          if let label = ebookProgressLabel {
            Text(label)
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(AppTheme.textSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
        } else {
          Text(formatPlaybackTime(book.media.duration ?? 0))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
        }
      }
    } trailing: {
      libraryRowTrailingStatusIcons
    }
  }

  @ViewBuilder
  private var libraryRowTrailingStatusIcons: some View {
    if usesEbookMetrics, let f = ebookProgress, f >= 0.995 {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(themeAccent)
        .font(.caption)
        .accessibilityLabel("Finished reading")
    } else if !usesEbookMetrics, prog?.isFinished == true {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(themeAccent)
        .font(.caption)
        .accessibilityLabel("Finished")
    }
    downloadIcon
  }

  @ViewBuilder
  private var downloadIcon: some View {
    if !showsDownloadStatus {
      EmptyView()
    } else if live.isDownloaded {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(themeAccent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if live.isDownloading {
      ProgressView(value: live.downloadProgress)
        .frame(width: 36)
        .tint(themeAccent)
        .accessibilityLabel("Downloading")
    }
  }

  @ViewBuilder
  private func expandedBlock(_ d: ABSBook) -> some View {
    let m = d.media.metadata
    let rowProgress = d.id == book.id ? (progressOverride ?? live.progress) : model.progressByItemId[d.id]
    let isFinished = rowProgress?.isFinished == true
    let isDownloaded = d.id == book.id ? live.isDownloaded : model.downloadedItemIds.contains(d.id)
    let isDownloading = d.id == book.id ? live.isDownloading : model.downloads.activeItemId == d.id
    let isQueued = d.id == book.id ? live.isQueued : model.downloads.queuedItemIds.contains(d.id)
    let downloadProgress = d.id == book.id ? live.downloadProgress : model.downloads.progress

    VStack(alignment: .leading, spacing: 8) {
      Divider().background(AppTheme.textSecondary.opacity(0.2))
      expandedAuthorRow(metadata: m)
      expandedNarratorRow(metadata: m)
      expandedSeriesRow(metadata: m)
      metaRow("Year", m.publishedYear ?? "—")
      metaRow("Publisher", m.publisher ?? "—")
      metaRow("Genres", (m.genres ?? []).joined(separator: ", ").nilIfEmpty ?? "—")
      metaRow(
        "Description",
        absPlainText(fromHTML: m.descriptionPlain ?? m.description).nilIfEmpty ?? "—")

      HStack(spacing: 8) {
        Group {
          if isDownloading {
            ZStack {
              RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
                .stroke(themeAccent.opacity(0.45), lineWidth: 1)
              ProgressView(value: downloadProgress)
                .tint(themeAccent)
                .scaleEffect(x: 1, y: 1.1, anchor: .center)
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: MiniPlayerMetrics.controlMinHeight)
            .accessibilityLabel("Download in progress")
          } else if isQueued {
            // Wartet in der Download-Queue — noch nicht aktiv, kein Cancel hier (nur über Entfernen).
            Image(systemName: "circle.dashed")
              .font(.callout)
              .foregroundStyle(themeAccent)
              .frame(maxWidth: .infinity)
              .frame(height: MiniPlayerMetrics.controlMinHeight)
              .accessibilityLabel("Queued")
          } else if isDownloaded {
            Button {
              model.removeLocalDownload(bookId: d.id)
            } label: {
              Image(systemName: "arrow.down.circle.badge.xmark")
                .font(.callout)
                .foregroundStyle(themeAccent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .downloaded))
            .accessibilityLabel("Remove offline copy")
          } else {
            Button {
              model.startDownload(book: d)
            } label: {
              Image(systemName: "arrow.down.circle")
                .font(.callout)
                .foregroundStyle(themeAccent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .neutral))
            .accessibilityLabel("Download")
          }
        }
        .frame(maxWidth: .infinity)

        Button {
          Task {
            if isFinished {
              await model.markUnfinished(bookId: d.id)
            } else {
              await model.markFinished(bookId: d.id)
            }
          }
        } label: {
          Image(systemName: isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle")
            .font(.callout)
            .foregroundStyle(
              model.isNetworkReachable
                ? themeAccent
                : AppTheme.textSecondary)
        }
        .buttonStyle(LibraryCardActionButtonStyle(variant: isFinished ? .finished : .accent))
        .disabled(!model.isNetworkReachable)
        .accessibilityLabel(isFinished ? "Mark as not finished" : "Finished")
      }
      .frame(maxWidth: .infinity)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 8)
    }
    .padding(.horizontal, AppTheme.Layout.libraryRowCardInset)
    .padding(.bottom, 12)
  }

  private func seriesDisplayLine(for s: ABSSeries) -> String {
    if let q = s.sequence?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
      return "\(s.name) (\(q))"
    }
    return s.name
  }

  private func applyAuthorFilterForActiveCatalog(authorId: String, displayName: String? = nil) {
    if model.mainTab == .library, model.mediaCatalogKind == .podcasts {
      let q = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !q.isEmpty { model.openPodcastSearchFromText(q) }
    } else {
      model.applyAuthorFilter(authorId: authorId, displayName: displayName)
    }
  }

  private func applyNarratorFilterForActiveCatalog(narratorName: String) {
    if model.mainTab == .library, model.mediaCatalogKind == .podcasts {
      model.openPodcastSearchFromText(narratorName)
    } else {
      model.applyNarratorFilter(narratorName: narratorName)
    }
  }

  private func applySeriesFilterForActiveCatalog(seriesId: String, displayName: String? = nil) {
    if model.mainTab == .library, model.mediaCatalogKind == .podcasts {
      let q = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !q.isEmpty { model.openPodcastSearchFromText(q) }
    } else {
      model.applySeriesFilter(seriesId: seriesId, displayName: displayName)
    }
  }

  private func narratorNamesForFilter(_ m: ABSBookMediaMetadata) -> [String] {
    var ordered: [String] = []
    var seen = Set<String>()
    func add(_ raw: String) {
      let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !t.isEmpty, seen.insert(t).inserted else { return }
      ordered.append(t)
    }
    if let n = m.narratorName {
      for part in n.split(separator: ",") {
        add(String(part))
      }
    }
    if let arr = m.narrators {
      for s in arr { add(s) }
    }
    return ordered
  }

  private func authorPlainDisplayLine(_ m: ABSBookMediaMetadata) -> String {
    let fromName = m.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !fromName.isEmpty { return fromName }
    if let a = m.authors, !a.isEmpty { return a.map(\.name).joined(separator: ", ") }
    return "—"
  }

  @ViewBuilder
  private func expandedAuthorRow(metadata: ABSBookMediaMetadata) -> some View {
    if let authors = metadata.authors, !authors.isEmpty {
      libraryMetaLabeledRow(title: "Author") {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(authors, id: \.id) { author in
            Button {
              applyAuthorFilterForActiveCatalog(authorId: author.id, displayName: author.name)
            } label: {
              Text(author.name)
                .font(.subheadline)
                .abstandAccentForeground()
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
          }
        }
      }
    } else {
      let line = authorPlainDisplayLine(metadata)
      if line == "—" {
        metaRow("Author", "—")
      } else {
        libraryMetaLabeledRow(title: "Author") {
          Button {
            if model.mainTab == .library, model.mediaCatalogKind == .podcasts {
              model.openPodcastSearchFromText(line)
            } else {
              model.openBooksSearchFromText(line)
            }
          } label: {
            Text(line)
              .font(.subheadline)
              .abstandAccentForeground()
              .frame(maxWidth: .infinity, alignment: .leading)
              .multilineTextAlignment(.leading)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private func expandedNarratorRow(metadata: ABSBookMediaMetadata) -> some View {
    let names = narratorNamesForFilter(metadata)
    if names.isEmpty {
      metaRow("Narrator", "—")
    } else {
      libraryMetaLabeledRow(title: "Narrator") {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(names, id: \.self) { name in
            Button {
              applyNarratorFilterForActiveCatalog(narratorName: name)
            } label: {
              Text(name)
                .font(.subheadline)
                .abstandAccentForeground()
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func expandedSeriesRow(metadata: ABSBookMediaMetadata) -> some View {
    if let seriesList = metadata.series, !seriesList.isEmpty {
      libraryMetaLabeledRow(title: "Series") {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(seriesList, id: \.id) { s in
            Button {
              applySeriesFilterForActiveCatalog(seriesId: s.id, displayName: s.name)
            } label: {
              Text(seriesDisplayLine(for: s))
                .font(.subheadline)
                .abstandAccentForeground()
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
          }
        }
      }
    } else if let line = metadata.resolvedSeriesDisplay, !line.isEmpty {
      metaRow("Series", line)
    }
  }

  private func libraryMetaLabeledRow<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(title.uppercased())
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func metaRow(_ k: String, _ v: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(k.uppercased())
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      Text(v)
        .font(.subheadline)
        .foregroundStyle(AppTheme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Entity detail (author / series / narrator)

struct BooksEntityDetailNavigationModifier: ViewModifier {
  @EnvironmentObject private var model: AppModel
  let tab: AppModel.MainTab

  private var navBinding: Binding<BooksEntityDetailNav?> {
    switch tab {
    case .library:
      Binding(
        get: { model.libraryEntityDetailNav },
        set: { model.libraryEntityDetailNav = $0 }
      )
    case .start:
      Binding(
        get: { model.homeEntityDetailNav },
        set: { model.homeEntityDetailNav = $0 }
      )
    case .settings:
      Binding.constant(nil)
    case .search:
      Binding.constant(nil)
    }
  }

  func body(content: Content) -> some View {
    content.navigationDestination(item: navBinding) { nav in
      BooksEntityDetailView(nav: nav)
    }
  }
}

extension View {
  func booksEntityDetailNavigation(for tab: AppModel.MainTab) -> some View {
    modifier(BooksEntityDetailNavigationModifier(tab: tab))
  }
}

struct BooksEntityDetailView: View {
  @EnvironmentObject private var model: AppModel
  let nav: BooksEntityDetailNav
  @State private var headerTintColor: Color = AppTheme.background
  @State private var headerCoverImageForTint: UIImage?

  /// Kein Cover, kein Cover-Tint — nur Standard-Hintergrund (#121212).
  private var usesPlainDetailBackground: Bool {
    switch nav.kind {
    case .narrator, .genre, .tag, .collection: return true
    default: return false
    }
  }

  private var detailScrollBackgroundColor: Color {
    usesPlainDetailBackground ? AppTheme.background : headerTintColor
  }

  private var showsEntityDescription: Bool {
    nav.kind == .author || nav.kind == .collection
  }

  private var entityDetailIsCurrent: Bool {
    model.entityDetailMatches(nav)
  }

  private var bookCountLabel: String? {
    let n: Int?
    if entityDetailIsCurrent {
      if model.entityDetailTotal > 0 {
        n = model.entityDetailTotal
      } else if !model.entityDetailBooks.isEmpty {
        n = model.entityDetailBooks.count
      } else if model.entityDetailLoading {
        n = nav.numBooks
      } else {
        n = nil
      }
    } else {
      n = nav.numBooks
    }
    guard let n, n > 0 else { return nil }
    return n == 1 ? "1 book" : "\(n) books"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        headerSection
        if showsEntityDescription {
          entityDescriptionSection
        }
        booksSection
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .abstandDetailScrollBackground(detailScrollBackgroundColor)
    .task(id: nav.id) {
      if !model.entityDetailMatches(nav) {
        model.prepareEntityDetail(for: nav)
      }
      if !usesPlainDetailBackground {
        headerTintColor = AppTheme.background
      }
      await model.reloadEntityDetail(for: nav, reset: true)
      if !usesPlainDetailBackground {
        await loadHeaderTint()
      }
    }
    .refreshable {
      await model.refreshEntityDetail(for: nav)
      if !usesPlainDetailBackground {
        await loadHeaderTint()
      }
    }
    .onChange(of: model.entityDetailBooks.count) { _, _ in
      guard nav.kind == .series else { return }
      Task { await loadHeaderTint() }
    }
    .onChange(of: model.appearanceThemeRevision) { _, _ in
      applyHeaderTintFromStoredImage()
    }
  }

  private func applyHeaderTintFromStoredImage() {
    guard !usesPlainDetailBackground else {
      headerTintColor = AppTheme.background
      return
    }
    if let headerCoverImageForTint {
      headerTintColor = coverDominantBackgroundTint(from: headerCoverImageForTint)
    } else {
      headerTintColor = AppTheme.background
    }
  }

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      if showsEntityDetailCover {
        HStack {
          Spacer()
          entityCover
          Spacer()
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        Text(nav.title)
          .font(.title2.weight(.bold))
          .foregroundStyle(AppTheme.textPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(nav.filterSummaryPrefix)
          .font(.subheadline.weight(.semibold))
          .abstandAccentForeground()
        if let bookCountLabel {
          Text(bookCountLabel)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
        }
      }
    }
  }

  /// Narrator / Genre / Tag / Collection: kein Cover — nur Titelblock.
  private var showsEntityDetailCover: Bool {
    !usesPlainDetailBackground
  }

  @ViewBuilder
  private var entityCover: some View {
    if nav.kind == .author, let url = model.authorImageURL(authorId: nav.entityId) {
      CoverImageView(
        url: url,
        token: model.token,
        itemId: "author:\(nav.entityId)",
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision,
        contentMode: .fill
      )
      .aspectRatio(1, contentMode: .fill)
      .containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }
      .clipShape(Circle())
    } else if nav.kind == .series {
      seriesDetailCover
    } else if let url = model.entityDetailCoverURL(for: nav) {
      CoverImageView(
        url: url,
        token: model.token,
        itemId: entityCoverCacheItemId,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision
      )
      .aspectRatio(1, contentMode: .fit)
      .containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
    } else {
      entityCoverPlaceholder
    }
  }

  /// Erstes Serien-Band: 1:1 mit zentriertem Cover und Letterboxing.
  @ViewBuilder
  private var seriesDetailCover: some View {
    let book = model.entityDetailBooks.first
    let bookId = book?.id ?? ""
    DetailHeroCoverFrame(aspectRatio: 1) {
      if let book, !bookId.isEmpty, let url = model.coverURL(for: bookId, tier: .hero) {
        SquareCoverImageView(
          url: url,
          token: model.token,
          itemId: bookId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheScopeId: model.coverImageCacheScopeId(for: bookId, tier: .hero),
          cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
        )
      } else {
        ZStack {
          AppTheme.card
          Image(systemName: "books.vertical")
            .font(.largeTitle)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  @ViewBuilder
  private var entityCoverPlaceholder: some View {
    if nav.kind == .author {
      ZStack {
        Circle()
          .fill(AppTheme.card)
        Image(systemName: entityPlaceholderIcon)
          .font(.largeTitle)
          .foregroundStyle(AppTheme.textSecondary)
      }
      .aspectRatio(1, contentMode: .fit)
      .containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }
      .clipShape(Circle())
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous)
          .fill(AppTheme.card)
        Image(systemName: entityPlaceholderIcon)
          .font(.largeTitle)
          .foregroundStyle(AppTheme.textSecondary)
      }
      .aspectRatio(1, contentMode: .fit)
      .containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
    }
  }

  private var entityCoverCacheItemId: String {
    switch nav.kind {
    case .author: return "author:\(nav.entityId)"
    case .series: return "series:\(nav.entityId)"
    case .narrator: return "narrator:\(nav.entityId)"
    case .collection: return "collection:\(nav.entityId)"
    case .genre: return "genre:\(nav.entityId)"
    case .tag: return "tag:\(nav.entityId)"
    }
  }

  private var entityPlaceholderIcon: String {
    switch nav.kind {
    case .author: return "person.crop.circle"
    case .series: return "books.vertical"
    case .narrator: return "waveform"
    case .collection: return "folder"
    case .genre: return "sparkles"
    case .tag: return "tag"
    }
  }

  @ViewBuilder
  private var entityDescriptionSection: some View {
    if !entityDetailIsCurrent || !model.entityDetailMetaReady {
      ProgressView()
        .controlSize(.regular)
        .tint(model.appearanceAccentColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    } else {
      entityDetailMetaRow(
        "Description",
        absPlainText(fromHTML: model.entityDetailDescription).nilIfEmpty ?? "—")
    }
  }

  @ViewBuilder
  private var booksSection: some View {
    if nav.kind == .author {
      authorGroupedBooksSection
    } else {
      flatEntityDetailBooksSection
    }
  }

  @ViewBuilder
  private var authorGroupedBooksSection: some View {
    let seriesSections = model.entityDetailAuthorSeriesSections
    let standalone = model.entityDetailAuthorStandaloneBooks
    let isEmpty = seriesSections.isEmpty && standalone.isEmpty

    if !entityDetailIsCurrent || (model.entityDetailLoading && isEmpty) {
      ProgressView()
        .controlSize(.large)
        .tint(model.appearanceAccentColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    } else if isEmpty {
      Text("No books found.")
        .font(.subheadline)
        .foregroundStyle(AppTheme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    } else {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        ForEach(seriesSections) { section in
          VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
            entityDetailSectionHeading(section.name)
            authorDetailBooksList(books: section.books)
          }
        }
        if !standalone.isEmpty {
          VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
            entityDetailSectionHeading(seriesSections.isEmpty ? "Books" : "Other books")
            authorDetailBooksList(books: standalone)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var flatEntityDetailBooksSection: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      entityDetailSectionHeading("Books")
      if !entityDetailIsCurrent || (model.entityDetailLoading && model.entityDetailBooks.isEmpty) {
        ProgressView()
          .controlSize(.large)
          .tint(model.appearanceAccentColor)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
      } else if model.entityDetailBooks.isEmpty {
        Text("No books found.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
      } else {
        LibraryBookCardsFlow {
          ForEach(model.entityDetailBooks) { book in
            AuthorDetailBookListCard(book: book, model: model)
              .task(id: book.id) {
                await model.loadMoreEntityDetailIfNeeded(nav: nav, currentItemId: book.id)
              }
          }
        }
      }
    }
  }

  private func entityDetailSectionHeading(_ title: String) -> some View {
    Text(title.uppercased())
      .font(.caption.weight(.bold))
      .foregroundStyle(AppTheme.textSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func authorDetailBooksList(books: [ABSBook]) -> some View {
    LibraryBookCardsFlow {
      ForEach(books) { book in
        AuthorDetailBookListCard(book: book, model: model)
      }
    }
  }

  private func entityDetailMetaRow(_ key: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(key.uppercased())
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      Text(value)
        .font(.subheadline)
        .foregroundStyle(AppTheme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func loadHeaderTint() async {
    guard !usesPlainDetailBackground else { return }

    let url: URL?
    if nav.kind == .author {
      url = model.authorImageURL(authorId: nav.entityId)
    } else if nav.kind == .series, let bookId = model.entityDetailBooks.first?.id {
      url = model.coverURL(for: bookId, tier: .hero)
    } else {
      url = model.entityDetailCoverURL(for: nav)
    }
    guard let url else { return }

    var req = URLRequest(url: url)
    req.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let image = UIImage(data: data)
      else { return }
      await MainActor.run {
        headerCoverImageForTint = image
        headerTintColor = coverDominantBackgroundTint(from: image)
      }
    } catch {}
  }
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
