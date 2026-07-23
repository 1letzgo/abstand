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
        var tabs: Set<AppModel.MainTab> = [.settings]
        if model.showAudiobooksTab { tabs.insert(.library) }
        if model.showPodcastsTab { tabs.insert(.podcasts) }
        activatedTabs.formUnion(tabs)
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
    .onChange(of: model.mainTab) { _, tab in
      activatedTabs.insert(tab)
      switch tab {
      case .library:
        libraryRelayoutEpoch += 1
        model.mediaCatalogKind = .audiobooks
        let previousFocus = model.focusedBooksLibrary?.id
        model.resetFocusedBooksLibraryToPrimaryOrFirstActive()
        if model.focusedBooksLibrary?.id != previousFocus {
          Task { await model.reloadLibrary(reset: true) }
        }
      case .podcasts:
        podcastsRelayoutEpoch += 1
        model.mediaCatalogKind = .podcasts
        let previousFocus = model.focusedPodcastLibrary?.id
        model.resetFocusedPodcastLibraryToPrimaryOrFirstActive()
        if model.focusedPodcastLibrary?.id != previousFocus {
          Task { await model.reloadPodcastLibrary(reset: true) }
        }
      default:
        break
      }
      if tab == .start, model.startShelves.isEmpty {
        Task { await model.loadStartDashboard() }
      }
    }
    .onChange(of: model.shouldPrewarmSecondaryTabs) { _, prewarm in
      guard prewarm else { return }
      var tabs: Set<AppModel.MainTab> = [.settings]
      if model.showAudiobooksTab { tabs.insert(.library) }
      if model.showPodcastsTab { tabs.insert(.podcasts) }
      activatedTabs.formUnion(tabs)
    }
    .onChange(of: model.ebookReaderSession?.libraryItemId) { _, newId in
      if newId == nil {
        model.refreshEbookContinueReadingShelf()
        model.flushEbookProgressSync()
      }
    }
    .onChange(of: model.selectedBooksLibrary?.id) { _, _ in
      model.clampMediaCatalogKindIfNeeded()
      if !model.showAudiobooksTab, model.mainTab == .library {
        model.mainTab = .start
      }
    }
    .onChange(of: model.selectedPodcastLibrary?.id) { _, _ in
      model.clampMediaCatalogKindIfNeeded()
    }
    .onChange(of: model.showAudiobooksTab) { _, visible in
      model.clampMediaCatalogKindIfNeeded()
      if visible { activatedTabs.insert(.library) }
    }
    .onChange(of: model.showPodcastsTab) { _, visible in
      model.clampMediaCatalogKindIfNeeded()
      if visible { activatedTabs.insert(.podcasts) }
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

  private var onlineTabView: some View {
    TabView(selection: $model.mainTab) {
      Tab(AppModel.MainTab.start.rawValue, systemImage: "house.fill", value: AppModel.MainTab.start) {
        HomeTabRootView()
          .id("abstand-home-tab-root-\(model.accountSessionEpoch)")
      }

      // Sichtbarkeit folgt Settings (Library != None). Während Bootstrap gecachte Flags nutzen,
      // damit die TabView-Struktur nicht mitten im Start umgebaut wird.
      if model.showAudiobooksTab {
        Tab(AppModel.MainTab.library.rawValue, systemImage: "books.vertical", value: AppModel.MainTab.library) {
          lazyTabContent(.library) {
            if model.selectedBooksLibrary != nil {
              libraryTabRoot
            } else {
              tabLibraryBootstrapPlaceholder
            }
          }
        }
      }

      if model.showPodcastsTab {
        Tab(AppModel.MainTab.podcasts.rawValue, systemImage: "mic.fill", value: AppModel.MainTab.podcasts) {
          lazyTabContent(.podcasts) {
            if model.selectedPodcastLibrary != nil {
              podcastsTabRoot
            } else {
              tabLibraryBootstrapPlaceholder
            }
          }
        }
      }

      Tab(AppModel.MainTab.settings.rawValue, systemImage: "gearshape.fill", value: AppModel.MainTab.settings) {
        lazyTabContent(.settings) { settingsTabRoot }
      }

      // iOS-26-nativer Such-Tab (`role: .search`): System pinnt den Tab an den Rand der
      // Tabbar und morpht das Icon beim Aktivieren in ein Suchfeld (Liquid Glass).
      // `.searchable` liegt lokal auf SearchTabRootView, damit das Feld NUR hier erscheint.
      Tab(
        AppModel.MainTab.search.rawValue, systemImage: "magnifyingglass",
        value: AppModel.MainTab.search, role: .search
      ) {
        lazyTabContent(.search) {
          SearchTabRootView()
        }
        .id("abstand-search-tab-root-\(model.accountSessionEpoch)")
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
      scrollToTopTrigger: model.libraryCatalogScrollToTopEpoch,
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

  private var booksBrowseSectionStrip: some View {
    let libraryItems = model.activeBookLibraries.map {
      AbstandBrowseStripItem(id: $0.id, label: $0.name, systemImage: "books.vertical.fill")
    }
    let librarySelectionID =
      model.focusedBooksLibrary?.id
      ?? model.selectedBooksLibrary?.id
      ?? libraryItems.first?.id
      ?? ""
    let sectionItems = BooksBrowseSection.audiobookStripOrder.map {
      AbstandBrowseStripItem(id: $0.rawValue, label: $0.rawValue, systemImage: $0.systemImage)
    }
    return AbstandPinnedBrowseStrip(
      libraryPickerItems: libraryItems,
      libraryPickerSelectionID: librarySelectionID,
      onSelectLibrary: { id in
        guard let lib = model.activeBookLibraries.first(where: { $0.id == id }) else { return }
        model.focusBooksLibrary(lib)
      },
      secondaryItems: sectionItems,
      secondarySelectionID: model.booksBrowseSection.rawValue,
      onSelectSecondary: { id in
        if let section = BooksBrowseSection(rawValue: id) {
          model.selectBooksBrowseSection(section)
        }
      },
      secondaryAccessibilityLabel: "Browse",
      secondaryAccessibilityHint: "Chooses which catalog section to browse"
    )
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
    case .ebooks, .ebooksSupplementary:
      // eBooks/Supplementary sind jetzt Katalog-Filter, keine eigenen Abschnitte mehr.
      booksCatalogBookListBody
    }
  }

  private var booksCatalogBookListBody: some View {
    let rows = model.booksForDisplay()
    return LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      // Bei mehreren Aktiven steht der Name in der fixierten Picker-Pill.
      if model.activeBookLibraries.count <= 1, let lib = model.booksCatalogLibrary {
        TabContentSectionTitle(title: lib.name)
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
      } else if model.libraryBookCardStyle.usesMultiColumnGrid {
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
    LibraryHeroMultiColumnRows(
      items: books,
      columns: model.libraryBookCardStyle.phoneGridColumns,
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
    let libraryItems = model.activePodcastLibraries.map {
      AbstandBrowseStripItem(id: $0.id, label: $0.name, systemImage: "mic.fill")
    }
    let librarySelectionID =
      model.focusedPodcastLibrary?.id
      ?? model.selectedPodcastLibrary?.id
      ?? libraryItems.first?.id
      ?? ""
    return AbstandPinnedBrowseStrip(
      libraryPickerItems: libraryItems,
      libraryPickerSelectionID: librarySelectionID,
      onSelectLibrary: { id in
        guard let lib = model.activePodcastLibraries.first(where: { $0.id == id }) else { return }
        model.focusPodcastLibrary(lib)
      },
      secondaryItems: podcastDockStripItems,
      secondarySelectionID: podcastCatalogScrollSelection,
      onSelectSecondary: { id in
        if id == Self.podcastCatalogNewSectionId {
          model.podcastCatalogStripSectionId = id
          Task { await model.selectPodcastShowFilter(nil) }
        } else {
          model.podcastCatalogStripSectionId = id
          model.applyPodcastShowFilterSelection(id)
          Task { await model.loadPodcastEpisodesForShowLibraryItem(id) }
        }
      },
      secondaryAccessibilityLabel: "Shows",
      secondaryAccessibilityHint: "Chooses which podcast show to browse"
    )
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
