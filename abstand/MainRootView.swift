import Combine
import SwiftUI

struct MainRootView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @Binding var nowPlayingSheetPresented: Bool
  @StateObject private var booksLibraryToolbarState = BooksLibraryToolbarState()
  @StateObject private var podcastCatalogToolbarState = PodcastCatalogToolbarState()
  /// Tabs erst bei erstem Besuch aufbauen — Home sofort, Rest lazy (Prewarm nach Bootstrap).
  @State private var activatedTabs: Set<AppModel.MainTab> = [.start]
  @State private var libraryRelayoutEpoch = 0
  @State private var ebooksRelayoutEpoch = 0
  @State private var podcastsRelayoutEpoch = 0

  var body: some View {
    let _ = model.appearanceThemeRevision
    return tabViewBody
      .tint(model.appearanceAccentColor)
      .themeAccentFromAppModel(model)
      .background {
        AppThemeScreenBackground(ignoresSafeArea: true)
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
      case .ebooks:
        ebooksRelayoutEpoch += 1
      case .podcasts:
        podcastsRelayoutEpoch += 1
      default:
        break
      }
      if tab == .start, model.startShelves.isEmpty, !model.offlineHomeUIActive {
        Task { await model.loadStartDashboard() }
      }
      if tab == .ebooks, model.browseEbooks.isEmpty, model.browseEbooksSupplementary.isEmpty {
        Task { await model.ensureBrowseEbooksLoaded() }
      }
    }
    .onChange(of: model.shouldPrewarmSecondaryTabs) { _, prewarm in
      guard prewarm else { return }
      var tabs: Set<AppModel.MainTab> = [.library, .settings]
      if model.showPodcastsTab {
        tabs.insert(.podcasts)
      }
      if model.showEbooksTab {
        tabs.insert(.ebooks)
      }
      activatedTabs.formUnion(tabs)
    }
    .onChange(of: model.offlineHomeMode) { _, _ in
      model.clampMainTabForOfflineHomeIfNeeded()
    }
    .onChange(of: model.offlineHomeModeAuto) { _, _ in
      model.clampMainTabForOfflineHomeIfNeeded()
    }
    .onChange(of: model.ebookReaderSession?.libraryItemId) { _, newId in
      if newId == nil {
        model.refreshEbookContinueReadingShelf()
        model.flushEbookProgressSync()
      }
    }
    .onChange(of: model.selectedBooksLibrary?.id) { _, _ in
      if model.selectedBooksLibrary == nil,
        model.mainTab == .library
      {
        model.mainTab = .start
      }
    }
    .onChange(of: model.selectedPodcastLibrary?.id) { _, _ in
      model.clampMainTabForPodcastsTabIfNeeded()
    }
    .onChange(of: model.showPodcastsTab) { _, _ in
      model.clampMainTabForPodcastsTabIfNeeded()
    }
    .onChange(of: model.selectedEbooksLibrary?.id) { _, _ in
      if model.selectedEbooksLibrary == nil,
        model.mainTab == .ebooks
      {
        model.mainTab = .start
      }
      model.clampMainTabForEbooksTabIfNeeded()
    }
    .onChange(of: model.showEbooksTab) { _, _ in
      model.clampMainTabForEbooksTabIfNeeded()
    }
    .onChange(of: model.accountSessionEpoch) { _, _ in
      activatedTabs = [.start]
      libraryRelayoutEpoch += 1
      ebooksRelayoutEpoch += 1
      podcastsRelayoutEpoch += 1
      booksLibraryToolbarState.resetForAccountSwitch()
      podcastCatalogToolbarState.resetForAccountSwitch()
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
    Group {
      if model.offlineHomeUIActive {
        // Keine TabView — sonst bleibt eine Ein-Tab-Leiste sichtbar.
        HomeTabRootView()
      } else {
        onlineTabView
      }
    }
  }

  private var onlineTabView: some View {
    TabView(selection: $model.mainTab) {
      Tab(AppModel.MainTab.start.rawValue, systemImage: "house.fill", value: AppModel.MainTab.start) {
        HomeTabRootView()
          .id("abstand-home-tab-root-\(model.accountSessionEpoch)")
      }

      // Tabs immer registrieren — sonst baut TabView beim Bootstrap neu (Ampel flackert).
      Tab(AppModel.MainTab.library.rawValue, systemImage: "books.vertical", value: AppModel.MainTab.library) {
        lazyTabContent(.library) {
          if model.selectedBooksLibrary != nil {
            libraryTabRoot
          } else {
            tabLibraryBootstrapPlaceholder
          }
        }
      }

      if model.showEbooksTab {
        Tab(AppModel.MainTab.ebooks.rawValue, systemImage: "book.closed", value: AppModel.MainTab.ebooks) {
          lazyTabContent(.ebooks) {
            if model.selectedEbooksLibrary != nil {
              ebooksTabRoot
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

  // MARK: - eBooks tab

  private var ebooksTabRoot: some View {
    NavigationStack {
      ebooksCatalogScrollView
        .abstandTabScreenChrome()
        .navigationTitle(AppModel.MainTab.ebooks.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            BooksCatalogSortToolbarMenu(
              sortField: model.ebooksCatalogSortField,
              sortDescending: model.ebooksCatalogSortDescending,
              onSortFieldChange: { field in
                model.ebooksCatalogSortField = field
                model.scheduleBooksToolbarSortReload(.browseEbooks)
              },
              onSortDescendingChange: { descending in
                model.ebooksCatalogSortDescending = descending
                model.scheduleBooksToolbarSortReload(.browseEbooks)
              }
            )
            .equatable()
          }
        }
    }
    .id("ebooks-tab-root-\(model.accountSessionEpoch)")
    .tint(model.appearanceAccentColor)
  }

  private var ebooksCatalogScrollView: some View {
    AbstandFixedBrowseStripSectionsLayout(
      relayoutTrigger: ebooksRelayoutEpoch,
      selection: model.ebooksBrowseSection,
      sectionIDs: EbooksBrowseSection.stripOrder,
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      onRefresh: { await model.refreshEbooksCatalog() }
    ) {
      ebooksBrowseSectionStrip
    } sectionBody: { section in
      ebooksBrowseSectionContent(for: section)
    }
  }

  private var ebooksBrowseSectionStrip: some View {
    AbstandBrowseStripIconMenu(
      items: EbooksBrowseSection.stripOrder.map {
        AbstandBrowseStripItem(id: $0.rawValue, label: $0.rawValue, systemImage: $0.systemImage)
      },
      selectionID: model.ebooksBrowseSection.rawValue,
      onSelect: { id in
        if let section = EbooksBrowseSection(rawValue: id) {
          model.selectEbooksBrowseSection(section)
        }
      }
    )
  }

  @ViewBuilder
  private func ebooksBrowseSectionContent(for section: EbooksBrowseSection) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      switch section {
      case .ebooks:
        ebooksPrimaryListBody
      case .supplementary:
        ebooksSupplementaryListBody
      }
    }
  }

  /// Bücher mit primärem eBook (auch ohne Hörbuch), paginiert.
  private var ebooksPrimaryListBody: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
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
      } else if model.ebooksTabCardStyle == .heroCover {
        LibraryHeroMultiColumnRows(
          items: model.browseEbooks,
          columns: AppTheme.Layout.heroCoverColumnsPerRow,
          spacing: AppTheme.Layout.withinSectionSpacing
        ) { book in
          EbookTabListCard(book: book, model: model, isSupplementary: false)
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
        EbooksCardsFlow {
          ForEach(model.browseEbooks) { book in
            EbookTabListCard(book: book, model: model, isSupplementary: false)
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
  }

  /// Hörbücher mit supplementärem eBook.
  private var ebooksSupplementaryListBody: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
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
      } else if model.ebooksTabCardStyle == .heroCover {
        LibraryHeroMultiColumnRows(
          items: model.browseEbooksSupplementary,
          columns: AppTheme.Layout.heroCoverColumnsPerRow,
          spacing: AppTheme.Layout.withinSectionSpacing
        ) { book in
          EbookTabListCard(book: book, model: model, isSupplementary: true)
        }
      } else {
        EbooksCardsFlow {
          ForEach(model.browseEbooksSupplementary) { book in
            EbookTabListCard(book: book, model: model, isSupplementary: true)
          }
        }
      }
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
      selection: model.booksBrowseSection,
      sectionIDs: BooksBrowseSection.stripOrder,
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

  private var booksBrowseSectionStrip: some View {
    AbstandBrowseStripIconMenu(
      items: BooksBrowseSection.stripOrder.map {
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

  private var booksSearchField: some View {
    let palette = model.appearancePalette
    return HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(palette.textSecondary)
      TextField("Title, author, series…", text: $model.searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(palette.textPrimary)
        .onSubmit { model.scheduleSearch() }
      if !model.searchText.isEmpty {
        Button {
          model.searchText = ""
          model.clearSearchResults()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(model.appearancePalette.card)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onChange(of: model.searchText) { _, _ in model.scheduleSearch() }
  }

  @ViewBuilder
  private func booksBrowseSectionScrollContent(for section: BooksBrowseSection) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      if section == .search {
        booksSearchField
      }
      booksBrowseSectionContent(for: section)
    }
  }

  @ViewBuilder
  private func booksBrowseSectionContent(for section: BooksBrowseSection) -> some View {
    switch section {
    case .books:
      booksCatalogBookListBody
    case .search:
      BooksSearchBrowseView()
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

  private var booksCatalogBookListBody: some View {
    let rows = model.booksForDisplay()
    return LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      if let lib = model.selectedBooksLibrary {
        TabContentSectionTitle(title:lib.name)
      }
      if model.isLibraryCatalogFiltered {
        catalogFilterBanner
      }
      if model.libraryBookCardStyle == .heroCover {
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
      opensDetailOnTap: model.libraryCatalogQuickFilter != .downloaded
    )
    .task(id: book.id) {
      await model.loadMoreIfNeeded(currentItemId: book.id)
    }
  }

  @ViewBuilder
  private func libraryHeroMultiColumnBookRows(books: [ABSBook]) -> some View {
    LibraryHeroMultiColumnRows(
      items: books,
      columns: AppTheme.Layout.heroCoverColumnsPerRow,
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
      if !model.isNetworkReachable {
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
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Narrators")
      if !model.isNetworkReachable {
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
      if !model.isNetworkReachable {
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
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Collections")
      if !model.isNetworkReachable {
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
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Tags")
      if !model.isNetworkReachable {
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
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Genres")
      if !model.isNetworkReachable {
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
      coverURL: author.hasAuthorImage ? model.authorImageURL(authorId: author.id) : nil
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

  private static let podcastCatalogNewSectionId = "__new__"

  private var podcastCatalogScrollSectionIDs: [String] {
    [Self.podcastCatalogNewSectionId] + model.podcastShows.map(\.id)
  }

  private var podcastCatalogScrollSelection: String {
    model.podcastSelectedShowId ?? Self.podcastCatalogNewSectionId
  }

  private func podcastCatalogShowId(forSectionId sectionId: String) -> String? {
    sectionId == Self.podcastCatalogNewSectionId ? nil : sectionId
  }

  private var podcastCatalogScrollView: some View {
    AbstandFixedBrowseStripSectionsLayout(
      relayoutTrigger: podcastsRelayoutEpoch,
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
    return AbstandBrowseStripIconMenu(
      items: podcastDockStripItems,
      selectionID: podcastCatalogScrollSelection,
      onSelect: { id in
        if id == Self.podcastCatalogNewSectionId {
          Task { await model.selectPodcastShowFilter(nil) }
        } else {
          model.applyPodcastShowFilterSelection(id)
          Task { await model.loadPodcastEpisodesForShowLibraryItem(id) }
        }
      }
    )
  }

  @ViewBuilder
  private func podcastPodcastsTabEpisodesContent(showId: String?) -> some View {
    let _ = model.appearanceThemeRevision
    let episodes = model.podcastEpisodesForPodcastsTab(showId: showId)
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
      }

      if episodes.isEmpty,
        !model.isLoadingPodcasts,
        !model.isLoadingPodcastShowEpisodes
      {
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

// MARK: - Home tab root

/// Eigener View-Typ — stabile Identität; Nav-Bar + Offline-Button überleben Bootstrap-Schritte.
private struct HomeTabRootView: View {
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
private struct HomeGoOfflineToolbarContent: ToolbarContent {
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      HomeGoOfflineToolbarButton()
    }
  }
}

private struct HomeGoOfflineToolbarButton: View {
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

private struct StartDashboardView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Group {
      if model.offlineHomeUIActive {
        offlineHomeFixedRoot
      } else {
        startDashboardOnlineLayout
      }
    }
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
    .onChange(of: model.offlineHomeUIActive) { _, isOffline in
      guard !isOffline else { return }
      guard !model.isAppBootstrapInProgress else { return }
      Task { await model.loadStartDashboard(force: true) }
    }
  }

  private var showsOfflineHomeMiniPlayer: Bool {
    model.player.activeBook != nil || model.isPlayerConnectionLoading
  }

  /// Offline-Home: Player fix oben, nur „Downloaded“ scrollt darunter.
  private var offlineHomeFixedRoot: some View {
    VStack(spacing: 0) {
      if showsOfflineHomeMiniPlayer {
        offlineHomeFixedPlayerHeader
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
          offlineHomeDownloadsBlock
        }
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.withinSectionSpacing)
        .padding(.bottom, AppTheme.Layout.scrollBottomInsetBase)
      }
      .scrollContentBackground(.hidden)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .refreshable {
        await model.refreshStartTabPullToRefresh()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(model.appearancePalette.background)
  }

  private var offlineHomeFixedPlayerHeader: some View {
    OfflineHomeMiniPlayerCard(gate: model.floatingChrome.gate, chrome: model.floatingChrome)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(.bottom, AppTheme.Layout.withinSectionSpacing)
      .background(model.appearancePalette.background)
  }

  // MARK: - Home tab

  private var startDashboardOnlineLayout: some View {
    let stripIDs = model.homeBrowseStripCategoryIDs
    let layoutSectionIDs =
      stripIDs.isEmpty
      ? [ABSStartShelfLocalization.homeBrowseContinueSectionID]
      : stripIDs
    return AbstandFixedBrowseStripSectionsLayout(
      showsStrip: true,
      selection: model.homeBrowseCategory,
      sectionIDs: layoutSectionIDs,
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      topScrollEdgeEffectStyle: .soft,
      onRefresh: { await model.refreshStartTabPullToRefresh() }
    ) {
      if stripIDs.isEmpty {
        homeBrowseStripBootstrapPlaceholder
      } else {
        homeBrowseSectionStrip
      }
    } sectionBody: { category in
      if stripIDs.isEmpty {
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
            if startDashboardShelfBookUsesEbookTabCard(shelfCategory: shelf.category, book: book) {
              EbookTabListCard(
                book: book, model: model, isSupplementary: false, preferCompactStyle: true)
            } else {
              LibraryBookListCard(book: book, model: model)
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
    return ContentUnavailableView(
      label,
      systemImage: ABSStartShelfLocalization.stripSystemImage(category: category),
      description: Text("Content for this shelf appears when your server provides it.")
    )
    .frame(maxWidth: .infinity)
    .padding(.top, AppTheme.Layout.sectionSpacing)
  }

  @ViewBuilder
  private func downloadedHomeRow(storageId: String) -> some View {
    if let episode = model.podcastEpisodeForDownloadedStorageId(storageId) {
      LibraryPodcastListCard(
        episode: episode,
        model: model,
        opensDetailOnTap: false,
        forceCompactListStyle: true
      )
    } else if let book = model.audiobookForDownloadedStorageId(storageId) {
      LibraryBookListCard(
        book: book,
        model: model,
        opensDetailOnTap: false,
        forceCompactListStyle: true
      )
    }
  }

  @ViewBuilder
  private var offlineHomeDownloadsBlock: some View {
    if model.downloadedTitlesForHome.isEmpty {
      startDashboardOfflineOnlyEmptyState
    } else {
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        TabContentSectionTitle(title: "Downloaded")
        LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(model.downloadedItemIds.sorted(), id: \.self) { storageId in
            downloadedHomeRow(storageId: storageId)
          }
        }
      }
    }
  }

  private func startDashboardIsContinueShelf(_ shelf: ABSStartShelfSection) -> Bool {
    shelf.category == "recentlyListened"
  }

  /// eBooks-Tab-Kartenvariante (nicht Library-`BookRowCard`).
  private func startDashboardShelfBookUsesEbookTabCard(shelfCategory: String, book: ABSBook) -> Bool {
    if shelfCategory == "continueEbooks" { return true }
    if shelfCategory == "continueSeries" { return book.isPureEbookLibraryItem }
    return false
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
        coverURL: author.hasAuthorImage ? model.authorImageURL(authorId: author.id) : nil
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

  private var startDashboardOfflineOnlyEmptyState: some View {
    ContentUnavailableView(
      "No downloads",
      systemImage: "arrow.down.circle",
      description: Text(
        "Offline mode only shows titles you have downloaded. Go back online to browse your library."
      )
    )
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
              coverURL: model.authorImageURL(authorId: a.id)
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
        authorLine: authorLine
      )
    }
    .buttonStyle(.plain)
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
          CoverImageView(
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
private struct ContinueListeningHeroMetadataBlock: View {
  @EnvironmentObject private var model: AppModel
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
          minHeight: AppTheme.Layout.continueHeroMetadataTitleFixedHeight,
          maxHeight: AppTheme.Layout.continueHeroMetadataTitleFixedHeight,
          alignment: .topLeading
        )
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTitleTap() }

      LibraryRowCollapsedMetaLine(label: detailLabel, value: detailValue, valueLineLimit: 1)
        .frame(
          maxWidth: .infinity,
          minHeight: AppTheme.Layout.continueHeroMetadataDetailFixedHeight,
          maxHeight: AppTheme.Layout.continueHeroMetadataDetailFixedHeight,
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
private struct ContinueListeningHeroTextBlock<Pill: View>: View {
  let title: String
  let detailLabel: String
  let detailValue: String
  let horizontalInset: CGFloat
  var onTitleTap: () -> Void = {}
  @ViewBuilder private let playPill: () -> Pill

  private var titleDetailHeight: CGFloat {
    AppTheme.Layout.continueHeroMetadataVerticalPadding
      + AppTheme.Layout.continueHeroMetadataTitleFixedHeight
      + AppTheme.Layout.continueHeroMetadataTitleDetailSpacing
      + AppTheme.Layout.continueHeroMetadataDetailFixedHeight
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
    .frame(height: AppTheme.Layout.continueHeroMetadataBlockHeight, alignment: .top)
  }
}

/// Gemeinsame Cover-Pill (Typ, Download, Länge) — gleiche Kapsel wie Continue Listening.
private struct ContinueListeningHeroCoverPill<Content: View>: View {
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

private enum ContinueListeningHeroCoverPillMetrics {
  static let iconFont = Font.system(size: 11, weight: .semibold)
  static let verticalInset: CGFloat = 8
  static let horizontalInset: CGFloat = 8
}

/// Oben links auf Continue-Hero-Cover: Medientyp-Pill (Buch oder Podcast).
private struct ContinueListeningHeroTypePill: View {
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
private struct ContinueListeningHeroOfflineBadge: View {
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

private struct ContinueListeningHeroBookOfflineBadgeSlot: View {
  @ObservedObject var rowLive: LibraryBookRowLiveState

  var body: some View {
    ContinueListeningHeroOfflineBadge(
      isDownloaded: rowLive.isDownloaded,
      isDownloading: rowLive.isDownloading,
      downloadProgress: rowLive.downloadProgress
    )
  }
}

private struct ContinueListeningHeroPodcastOfflineBadgeSlot: View {
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
private struct ContinueListeningHeroCarousel: View {
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
      openDetails: opensDetailOnTap ? { showDetail = true } : nil
    ) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        Button {
          Task { await model.playPodcastEpisode(episode) }
        } label: {
          LibraryRowLayout.coverSlot {
            CoverImageView(
              url: model.coverURL(for: episode.libraryItemId),
              token: model.token,
              itemId: episode.libraryItemId,
              cacheAccount: model.coverImageCacheAccountDirectory(),
              cacheRevision: model.coverImageCacheRevision
            )
          } overlay: {
            Image(systemName: "play.fill")
              .font(.system(size: 7, weight: .semibold))
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

      VStack(alignment: .leading, spacing: 8) {
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

private struct ContinueListeningHeroBookCard: View {
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
          cacheRevision: model.coverImageCacheRevision,
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
      if let c = CoverDerivedTintLoader.colorFromDiskOrCoverCache(account: account, itemId: book.id) {
        tint = c
      }
      if let c = await CoverDerivedTintLoader.colorFromNetwork(
        account: account,
        itemId: book.id,
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

private struct ContinueListeningHeroPodcastCard: View {
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
  static let iconPointSize: CGFloat = 21
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
      .font(.system(size: FacetBrowseTileMetrics.iconPointSize, weight: .semibold))
      .abstandAccentForeground()
  }
}

private func browseEntityBooksCountLine(count: Int?) -> String? {
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
    CoverImageView(
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

/// Gleiches Kartenlayout wie `BookRowCard`: Cover 82×82, Titel oben am Cover ausgerichtet.
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

  var body: some View {
    HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
      LibraryRowLayout.coverSlot {
        if let ids = coverBookIds, ids.count > 1 {
          SeriesMultiCoverView(bookIds: ids)
        } else {
          CoverImageView(
            url: coverURL,
            token: model.token,
            itemId: cacheItemId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision
          )
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
          CoverImageView(
            url: model.coverURL(for: show.id),
            token: model.token,
            itemId: show.id,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision
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
    }
  }
}

// MARK: - Library row layout (Cover bündig links/oben/unten)

private enum LibraryRowLayout {
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

  /// `coverWidth == nil`: Breite variabel (eBook-Cover im natürlichen Seitenverhältnis).
  @ViewBuilder
  static func coverSlot<Cover: View, Overlay: View>(
    coverWidth: CGFloat? = LibraryRowLayout.coverSide,
    @ViewBuilder cover: () -> Cover,
    @ViewBuilder overlay: () -> Overlay = { EmptyView() }
  ) -> some View {
    cover()
      .frame(width: coverWidth, height: coverSide)
      .clipShape(coverClipShape)
      .overlay(alignment: .bottomTrailing) {
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

/// Oben rechts auf Cover-Karten: fertig + Offline-Download (wie Continue Listening).
private struct LibraryHeroCoverStatusButtons: View {
  var showsDownload: Bool
  var isDownloaded: Bool
  var isDownloading: Bool
  var downloadProgress: Double
  var isFinished: Bool
  var onRemoveDownload: (() -> Void)?
  var onToggleFinished: (() -> Void)?

  var body: some View {
    HStack(spacing: 4) {
      if isFinished {
        coverActionPill(action: onToggleFinished) {
          Image(systemName: "checkmark.circle.fill")
            .font(ContinueListeningHeroCoverPillMetrics.iconFont)
            .foregroundStyle(.white)
        }
        .accessibilityLabel("Finished")
      }
      if showsDownload {
        if isDownloaded {
          coverActionPill(action: onRemoveDownload) {
            Image(systemName: "arrow.down.circle.fill")
              .font(ContinueListeningHeroCoverPillMetrics.iconFont)
              .symbolRenderingMode(.monochrome)
              .foregroundStyle(.white)
          }
          .accessibilityLabel("Saved offline")
        } else if isDownloading {
          coverActionPill(action: nil) {
            ProgressView(value: downloadProgress)
              .progressViewStyle(.circular)
              .tint(.white)
              .scaleEffect(0.72)
              .frame(width: 13, height: 13)
          }
          .accessibilityLabel("Downloading")
        }
      }
    }
    .transaction { $0.animation = nil }
  }

  @ViewBuilder
  private func coverActionPill<Label: View>(
    action: (() -> Void)?,
    @ViewBuilder label: @escaping () -> Label
  ) -> some View {
    if let action {
      Button(action: action) {
        ContinueListeningHeroCoverPill(allowsHitTesting: true, content: label)
      }
      .buttonStyle(.plain)
    } else {
      ContinueListeningHeroCoverPill(content: label)
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

/// eBooks-Tab: 2-spaltiges Hero-Raster (wie Hörbücher) oder kompakte Liste.
private struct EbooksCardsFlow<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    LibraryCoverCardsFlow(content: content)
  }
}

/// Hero-Karten zeilenweise (`LazyVGrid` vermeiden — Tab-Wechsel-Layout-Bug).
private struct LibraryHeroMultiColumnRows<Item: Identifiable, Card: View>: View {
  let items: [Item]
  let columns: Int
  let spacing: CGFloat
  @ViewBuilder let card: (Item) -> Card

  var body: some View {
    let columnCount = max(1, columns)
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

/// Autor-Detail: Hörbücher normal, reine eBooks mit eBook-Badge und Reader-Tap.
private struct AuthorDetailBookListCard: View {
  let book: ABSBook
  let model: AppModel

  var body: some View {
    if book.isPureEbookLibraryItem {
      LibraryBookListCard(
        book: book,
        model: model,
        showEbookBadge: true,
        opensEbookOnCover: true,
        usesTallEbookCover: model.libraryBookCardStyle != .heroCover
      )
    } else {
      LibraryBookListCard(book: book, model: model)
    }
  }
}

/// eBooks-Tab: kompakte Zeile oder Cover-Karte (eigene Settings pro Sektion).
private struct EbookTabListCard: View {
  let book: ABSBook
  let model: AppModel
  var isSupplementary: Bool
  /// Home Continue-Regale: immer kompakte Zeile, unabhängig von eBooks-Tab „Cover card“.
  var preferCompactStyle = false

  private var usesHeroCoverStyle: Bool {
    !preferCompactStyle && model.ebooksTabCardStyle == .heroCover
  }

  var body: some View {
    if usesHeroCoverStyle {
      LibraryHeroBookRowCard(
        book: book,
        model: model,
        showEbookBadge: true,
        usesEbookProgressDisplay: true,
        showsDownloadStatus: isSupplementary,
        coverAspectRatio: isSupplementary ? 1 : AppTheme.Layout.ebookHeroCoverAspectRatio
      )
    } else {
      BookRowCard(
        book: book,
        model: model,
        showEbookBadge: true,
        opensEbookOnCover: true,
        usesTallEbookCover: !isSupplementary
      )
    }
  }
}

/// Wählt kompakte Zeile oder Cover-Karte gemäß `libraryBookCardStyle` (eBooks-Tab hat eigene Settings).
struct LibraryBookListCard: View {
  let book: ABSBook
  let model: AppModel
  var showEbookBadge = false
  var opensEbookOnCover = false
  var progressOverride: ABSUserMediaProgress?
  var authorLineOverride: String?
  var showsPlaybackControls = true
  var showsDownloadStatus = true
  var opensDetailOnTap = true
  /// Offline-Downloadliste: immer kompakte Zeilen, unabhängig von Settings.
  var forceCompactListStyle = false
  /// eBooks-Tab: Cover hochkant 10:16 statt quadratisch.
  var usesTallEbookCover = false

  private var usesHeroCoverStyle: Bool {
    !forceCompactListStyle && model.libraryBookCardStyle == .heroCover && !opensEbookOnCover
  }

  var body: some View {
    if usesHeroCoverStyle {
      LibraryHeroBookRowCard(
        book: book,
        model: model,
        showEbookBadge: showEbookBadge,
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
        opensEbookOnCover: opensEbookOnCover,
        progressOverride: progressOverride,
        authorLineOverride: authorLineOverride,
        showsPlaybackControls: showsPlaybackControls,
        showsDownloadStatus: showsDownloadStatus,
        opensDetailOnTap: opensDetailOnTap,
        usesTallEbookCover: usesTallEbookCover
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
  var opensEbookOnCover = false
  var progressOverride: ABSUserMediaProgress?
  var authorLineOverride: String?
  var showsDownloadStatus = true
  var opensDetailOnTap = true
  /// `1` = quadratisch (Hörbuch); eBooks z. B. `AppTheme.Layout.ebookHeroCoverAspectRatio`.
  var coverAspectRatio: CGFloat = 1
  /// eBook-Lesefortschritt in Balken, Cover-Tap → Detail.
  var usesEbookProgressDisplay = false

  @StateObject private var live: LibraryBookRowLiveState
  @State private var tint: Color = AppTheme.card
  @State private var showDetail = false

  private var usesEbookMetrics: Bool {
    opensEbookOnCover || usesEbookProgressDisplay
  }

  init(
    book: ABSBook,
    model: AppModel,
    showEbookBadge: Bool = false,
    opensEbookOnCover: Bool = false,
    usesEbookProgressDisplay: Bool = false,
    progressOverride: ABSUserMediaProgress? = nil,
    authorLineOverride: String? = nil,
    showsDownloadStatus: Bool = true,
    opensDetailOnTap: Bool = true,
    coverAspectRatio: CGFloat = 1
  ) {
    self.book = book
    self.showEbookBadge = showEbookBadge
    self.opensEbookOnCover = opensEbookOnCover
    self.usesEbookProgressDisplay = usesEbookProgressDisplay
    self.progressOverride = progressOverride
    self.authorLineOverride = authorLineOverride
    self.showsDownloadStatus = showsDownloadStatus
    self.opensDetailOnTap = opensDetailOnTap
    self.coverAspectRatio = coverAspectRatio
    self.model = model
    _live = StateObject(
      wrappedValue: LibraryBookRowLiveState(
        bookId: book.id,
        model: model,
        observesProgress: progressOverride == nil && !opensEbookOnCover && !usesEbookProgressDisplay,
        observesDownload: showsDownloadStatus,
        observesEbookProgress: opensEbookOnCover || usesEbookProgressDisplay
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

  private var showsCoverStatusButtons: Bool {
    if isFinished { return true }
    if showsDownloadStatus, live.isDownloaded || live.isDownloading { return true }
    return false
  }

  var body: some View {
    let _ = themeRevision
    let coverRadius = AppTheme.Layout.continueHeroCardCornerRadius
    let barH = AppTheme.Layout.libraryRowBottomProgressHeight
    let coverClip = RoundedRectangle(cornerRadius: coverRadius, style: .continuous)

    return Group {
      if opensDetailOnTap {
        cardBody(coverClip: coverClip, barH: barH)
          .navigationDestination(isPresented: $showDetail) {
            BookDetailView(bookId: book.id)
          }
      } else {
        cardBody(coverClip: coverClip, barH: barH)
      }
    }
    .abstandThemeRefresh()
    .task(id: book.id) {
      let account = model.coverImageCacheAccountDirectory()
      if let c = CoverDerivedTintLoader.colorFromDiskOrCoverCache(account: account, itemId: book.id) {
        tint = c
      }
      if let c = await CoverDerivedTintLoader.colorFromNetwork(
        account: account,
        itemId: book.id,
        coverURL: model.coverURL(for: book.id),
        token: model.token
      ) {
        tint = c
      }
    }
  }

  @ViewBuilder
  private func cardBody(
    coverClip: RoundedRectangle,
    barH: CGFloat
  ) -> some View {
    ZStack(alignment: .bottom) {
      tint
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      CoverImageView(
        url: model.coverURL(for: book.id),
        token: model.token,
        itemId: book.id,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision,
        contentMode: coverAspectRatio == 1 ? .fit : .fill
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipShape(coverClip)
      .contentShape(coverClip)
      .onTapGesture {
        if opensEbookOnCover {
          guard !live.isPreparingEbook else { return }
          Task { await model.openAttachedEbook(for: book) }
        } else if opensDetailOnTap {
          showDetail = true
        }
      }
      .accessibilityLabel(book.displayTitle)
      .accessibilityHint(
        opensEbookOnCover
          ? "Opens the eBook in the reader."
          : (opensDetailOnTap ? "Opens book details." : "")
      )

      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.5), location: 0),
          .init(color: .black.opacity(0), location: 1),
        ],
        startPoint: .bottom,
        endPoint: .top
      )
      .frame(height: min(88, max(56, 88 * coverAspectRatio)))
      .frame(maxWidth: .infinity)
      .allowsHitTesting(false)

      Group {
        if opensEbookOnCover, live.isPreparingEbook {
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
    .overlay(alignment: .topTrailing) {
      if showsCoverStatusButtons {
        LibraryHeroCoverStatusButtons(
          showsDownload: showsDownloadStatus,
          isDownloaded: live.isDownloaded,
          isDownloading: live.isDownloading,
          downloadProgress: live.downloadProgress,
          isFinished: isFinished,
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
        .fixedSize()
      }
    }
    .background(AppTheme.card)
    .clipShape(coverClip)
    .abstandHeroCardOutline(palette: AppTheme.palette)
    .frame(maxWidth: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityHint(opensDetailOnTap ? "Opens book details." : "")
  }
}

/// Metadaten unter Hero-Cover: Titel + Autor (ohne „Author“-Label).
private struct LibraryHeroPlainAuthorMetadataBlock: View {
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let title: String
  let author: String
  let horizontalInset: CGFloat
  var onTitleTap: () -> Void = {}
  var includesBottomPadding: Bool = false
  var blockHeight: CGFloat

  var body: some View {
    let _ = themeRevision
    return VStack(alignment: .leading, spacing: AppTheme.Layout.continueHeroMetadataTitleDetailSpacing) {
      Text(title)
        .font(.headline.weight(.semibold))
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .minimumScaleFactor(0.85)
        .frame(
          maxWidth: .infinity,
          minHeight: AppTheme.Layout.continueHeroMetadataTitleFixedHeight,
          maxHeight: AppTheme.Layout.continueHeroMetadataTitleFixedHeight,
          alignment: .topLeading
        )
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTitleTap() }

      Text(author)
        .font(.footnote)
        .foregroundStyle(AppTheme.textSecondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(
          maxWidth: .infinity,
          minHeight: AppTheme.Layout.continueHeroMetadataDetailFixedHeight,
          maxHeight: AppTheme.Layout.continueHeroMetadataDetailFixedHeight,
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
    .abstandThemeRefresh()
  }
}

struct BookRowCard: View {
  let book: ABSBook
  /// Kein `@ObservedObject` — Fortschritt/Download über `LibraryBookRowLiveState`.
  let model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  /// In der eBooks-Liste immer das Buch-Badge zeigen (Server-Filter, minified ohne Metadaten).
  var showEbookBadge = false
  /// Cover-Tap öffnet den E-Book-Reader statt Audiobook-Wiedergabe.
  var opensEbookOnCover = false
  /// Fortschritt aus anderem Kontext (z. B. Server-User-Detail), nicht `progressByItemId`.
  var progressOverride: ABSUserMediaProgress?
  /// Autor-Zeile unabhängig vom Stub (z. B. angereicherter Server-User-Fortschritt).
  var authorLineOverride: String?
  var showsPlaybackControls = true
  var showsDownloadStatus = true
  var opensDetailOnTap = true
  /// eBooks-Tab: Cover hochkant 10:16 statt quadratisch.
  var usesTallEbookCover = false

  @StateObject private var live: LibraryBookRowLiveState
  @State private var showDetail = false

  init(
    book: ABSBook,
    model: AppModel,
    showEbookBadge: Bool = false,
    opensEbookOnCover: Bool = false,
    progressOverride: ABSUserMediaProgress? = nil,
    authorLineOverride: String? = nil,
    showsPlaybackControls: Bool = true,
    showsDownloadStatus: Bool = true,
    opensDetailOnTap: Bool = true,
    usesTallEbookCover: Bool = false
  ) {
    self.book = book
    self.showEbookBadge = showEbookBadge
    self.opensEbookOnCover = opensEbookOnCover
    self.progressOverride = progressOverride
    self.authorLineOverride = authorLineOverride
    self.showsPlaybackControls = showsPlaybackControls
    self.showsDownloadStatus = showsDownloadStatus
    self.opensDetailOnTap = opensDetailOnTap
    self.usesTallEbookCover = usesTallEbookCover
    self.model = model
    _live = StateObject(
      wrappedValue: LibraryBookRowLiveState(
        bookId: book.id,
        model: model,
        observesProgress: progressOverride == nil && !opensEbookOnCover,
        observesDownload: showsDownloadStatus,
        observesEbookProgress: opensEbookOnCover
      )
    )
  }

  private var prog: ABSUserMediaProgress? { progressOverride ?? live.progress }

  private var ebookProgress: Double? {
    guard opensEbookOnCover else { return nil }
    return live.ebookProgressFraction
  }

  private var ebookProgressLabel: String? {
    guard opensEbookOnCover else { return nil }
    return LibraryRowLiveState.ebookProgressLabel(for: live.ebookProgressFraction)
  }

  private var showsBottomProgressBar: Bool {
    if opensEbookOnCover {
      guard let f = ebookProgress, f > 0.005, f < 0.995 else { return false }
      return true
    }
    guard let p = prog, !p.isFinished, p.duration > 0 else { return false }
    return true
  }

  private var bottomProgressValue: Double {
    if opensEbookOnCover, let f = ebookProgress { return min(1, max(0, f)) }
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

  /// `nil` = variable Breite (eBooks: natürliches Cover-Seitenverhältnis bei fester Zeilenhöhe).
  private var rowCoverWidth: CGFloat? {
    usesTallEbookCover ? nil : LibraryRowLayout.coverSide
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
          if showsPlaybackControls {
            Button {
              if opensEbookOnCover {
                Task { await model.openAttachedEbook(for: book) }
              } else {
                Task { await model.play(book: book) }
              }
            } label: {
              libraryRowCoverWithPlayBadge
            }
            .buttonStyle(.plain)
            .disabled(opensEbookOnCover && live.isPreparingEbook)
            .accessibilityLabel(
              opensEbookOnCover
                ? (ebookProgressLabel
                  ?? LibraryRowLiveState.ebookOpenPillCaption(for: live.ebookProgressFraction))
                : "Play"
            )
            .accessibilityHint(
              opensEbookOnCover
                ? "Opens the eBook in the reader."
                : "Starts playback of this audiobook."
            )
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
      opensDetailOnTap
        ? "Opens book details. Play button starts playback."
        : "Play button starts playback."
    )
  }

  private var libraryRowCoverWithPlayBadge: some View {
    LibraryRowLayout.coverSlot(coverWidth: rowCoverWidth) {
      CoverImageView(
        url: model.coverURL(for: book.id),
        token: model.token,
        itemId: book.id,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision,
        contentMode: usesTallEbookCover ? .fitVariableWidth : .fill
      )
    } overlay: {
      if showsPlaybackControls {
        if opensEbookOnCover, live.isPreparingEbook {
          ProgressView()
            .controlSize(.small)
            .tint(.white)
            .frame(width: 18, height: 18)
            .background(AppTheme.coverPlayBadgeBackground)
            .clipShape(Circle())
            .padding(4)
        } else {
          Image(systemName: opensEbookOnCover ? "book.closed.fill" : "play.fill")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(AppTheme.coverPlayBadgeBackground)
            .clipShape(Circle())
            .padding(4)
            .accessibilityHidden(true)
        }
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
        if opensEbookOnCover {
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
          if showEbookBadge || book.hasAttachedEbook || book.hasSupplementalEpub {
            EpubAvailableBadge()
          }
        }
      }
    } trailing: {
      libraryRowTrailingStatusIcons
    }
  }

  @ViewBuilder
  private var libraryRowTrailingStatusIcons: some View {
    if opensEbookOnCover, let f = ebookProgress, f >= 0.995 {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(themeAccent)
        .font(.caption)
        .accessibilityLabel("Finished reading")
    } else if !opensEbookOnCover, prog?.isFinished == true {
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
    if model.mainTab == .podcasts {
      let q = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !q.isEmpty { model.openPodcastSearchFromText(q) }
    } else {
      model.applyAuthorFilter(authorId: authorId, displayName: displayName)
    }
  }

  private func applyNarratorFilterForActiveCatalog(narratorName: String) {
    if model.mainTab == .podcasts {
      model.openPodcastSearchFromText(narratorName)
    } else {
      model.applyNarratorFilter(narratorName: narratorName)
    }
  }

  private func applySeriesFilterForActiveCatalog(seriesId: String, displayName: String? = nil) {
    if model.mainTab == .podcasts {
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
            if model.mainTab == .podcasts {
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
          ForEach(Array(names.enumerated()), id: \.offset) { _, name in
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

// MARK: - Book detail view

/// Mittlere Cover-Farbe als Detail-Hintergrund — Dark: gedämpft dunkel; Sepia: warmer Papier-Ton.
private func coverDominantBackgroundTint(from image: UIImage) -> Color {
  guard let (r, g, b) = coverAverageRGB(from: image) else { return AppTheme.background }

  if AppTheme.palette.isDarkLike {
    let mix: CGFloat = 0.25
    let floor: CGFloat = 0.04
    return Color(
      red: Double(min(1, r * mix + floor)),
      green: Double(min(1, g * mix + floor)),
      blue: Double(min(1, b * mix + floor))
    )
  }

  let paper = UIColor(AppTheme.background)
  var pr: CGFloat = 0
  var pg: CGFloat = 0
  var pb: CGFloat = 0
  var pa: CGFloat = 0
  paper.getRed(&pr, green: &pg, blue: &pb, alpha: &pa)
  let coverWeight: CGFloat = 0.2
  let paperWeight = 1 - coverWeight
  return Color(
    red: Double(r * coverWeight + pr * paperWeight),
    green: Double(g * coverWeight + pg * paperWeight),
    blue: Double(b * coverWeight + pb * paperWeight)
  )
}

private func coverAverageRGB(from image: UIImage) -> (CGFloat, CGFloat, CGFloat)? {
  guard let ciImage = CIImage(image: image) else { return nil }
  var extent = ciImage.extent
  if !extent.width.isFinite || extent.width < 1 || !extent.height.isFinite || extent.height < 1 {
    extent = CGRect(origin: .zero, size: image.size)
  }
  guard extent.width >= 1, extent.height >= 1,
    let filter = CIFilter(
      name: "CIAreaAverage",
      parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: CIVector(cgRect: extent)]
    ),
    let output = filter.outputImage
  else { return nil }
  var bitmap = [UInt8](repeating: 0, count: 4)
  let ctx = CIContext(options: [.workingColorSpace: NSNull()])
  ctx.render(
    output,
    toBitmap: &bitmap,
    rowBytes: 4,
    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
    format: .RGBA8,
    colorSpace: CGColorSpaceCreateDeviceRGB()
  )
  return (
    CGFloat(bitmap[0]) / 255,
    CGFloat(bitmap[1]) / 255,
    CGFloat(bitmap[2]) / 255
  )
}

private enum ListeningHistoryDateFormatting {
  static let sessionList: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()
}

private struct ListeningHistoryDisclosure: View {
  @Environment(\.themeAccent) private var themeAccent
  @Binding var expanded: Bool
  let sessions: [ABSListeningSession]
  let isNetworkReachable: Bool
  let emptyOnlineText: String
  let emptyOfflineText: String
  let onJumpToSessionStart: (ABSListeningSession) -> Void

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      Group {
        if sessions.isEmpty {
          Text(
            isNetworkReachable
              ? emptyOnlineText
              : emptyOfflineText
          )
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        } else {
          VStack(alignment: .leading, spacing: 14) {
            ForEach(sessions) { session in
              ListeningHistoryRow(session: session, onJump: onJumpToSessionStart)
            }
          }
          .padding(.top, 6)
        }
      }
    } label: {
      Text("Listening history")
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .textCase(.uppercase)
        .tracking(0.6)
    }
    .tint(themeAccent)
  }
}

private struct ListeningHistoryRow: View {
  @Environment(\.themeAccent) private var themeAccent
  let session: ABSListeningSession
  let onJump: (ABSListeningSession) -> Void

  var body: some View {
    let denom = max(session.duration, session.currentTime, session.startTime, 1)
    let rel0 = CGFloat(session.startTime / denom)
    let rel1 = CGFloat(session.currentTime / denom)
    let started = Date(timeIntervalSince1970: Double(session.startedAt) / 1000)
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(ListeningHistoryDateFormatting.sessionList.string(from: started))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
          Text(
            "Listened \(formatPlaybackTime(Double(session.timeListening))) · \(formatPlaybackTime(session.startTime)) → \(formatPlaybackTime(session.currentTime))"
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(AppTheme.textSecondary)
        }
        Spacer(minLength: 8)
        Button {
          onJump(session)
        } label: {
          Image(systemName: "arrow.counterclockwise.circle.fill")
            .font(.title2)
            .abstandAccentForeground()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to this session")
      }
      GeometryReader { geo in
        let w = geo.size.width
        let x0 = min(max(rel0 * w, 0), w)
        let x1 = min(max(rel1 * w, x0 + 2), w)
        ZStack(alignment: .leading) {
          Capsule()
            .fill(AppTheme.card)
          Capsule()
            .fill(themeAccent.opacity(0.88))
            .frame(width: x1 - x0)
            .offset(x: x0)
        }
      }
      .frame(height: 7)
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Detail navigation toolbar (Download / Reset / Finished)

private struct DetailToolbarDownloadItem: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let storageId: String
  let onStartDownload: () -> Void
  let onRemoveDownload: () -> Void

  var body: some View {
    Group {
      if model.downloads.activeItemId == storageId {
        ProgressView(value: model.downloads.progress)
          .progressViewStyle(.circular)
          .tint(themeAccent)
      } else if model.downloadedItemIds.contains(storageId) {
        Button(action: onRemoveDownload) {
          Image(systemName: "arrow.down.circle.badge.xmark")
            .foregroundStyle(themeAccent)
        }
        .accessibilityLabel("Remove offline copy")
      } else {
        Button(action: onStartDownload) {
          Image(systemName: "arrow.down.circle")
            .foregroundStyle(themeAccent)
        }
        .accessibilityLabel("Download")
      }
    }
  }
}

private struct DetailToolbarResetProgressItem: View {
  let enabled: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      Image(systemName: "clock.arrow.circlepath")
    }
    .disabled(!enabled)
    .accessibilityLabel("Reset listening progress")
  }
}

private struct DetailToolbarMarkFinishedItem: View {
  @Environment(\.themeAccent) private var themeAccent
  let isFinished: Bool
  let enabled: Bool
  let onTap: () -> Void

  private var iconColor: Color {
    enabled ? themeAccent : AppTheme.textSecondary
  }

  var body: some View {
    Button(action: onTap) {
      Image(systemName: isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle")
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(iconColor)
    }
    .disabled(!enabled)
    .accessibilityLabel(isFinished ? "Mark as not finished" : "Mark as finished")
  }
}

/// Gemeinsame Kanten für Play / Read / Mark in der Buch-Detail-Leiste.
private enum DetailActionRowMetrics {
  static let cornerRadius = MiniPlayerMetrics.controlCorner
  static let borderWidth: CGFloat = 1.5
  static let markButtonWidth: CGFloat = 52

  static var corner: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  @ViewBuilder
  static func progressFill(
    width: CGFloat,
    height: CGFloat,
    fillAmount: Double,
    isFinished: Bool,
    color: Color
  ) -> some View {
    let roundTrailing = isFinished || fillAmount >= 0.999
    if roundTrailing {
      corner
        .fill(color)
        .frame(width: width, height: height)
    } else {
      UnevenRoundedRectangle(
        topLeadingRadius: cornerRadius,
        bottomLeadingRadius: cornerRadius,
        bottomTrailingRadius: 0,
        topTrailingRadius: 0,
        style: .continuous
      )
      .fill(color)
      .frame(width: width, height: height)
    }
  }
}

/// Apple-Music-ähnliches Detail-Hero: Cover, Titel und Aktionszeile.
private enum DetailHeroLayoutMetrics {
  static let coverTopPadding: CGFloat = 4
  static let titleTopSpacing: CGFloat = 18
  static let sideControlSize: CGFloat = 52
  static let compactSideControlSize: CGFloat = 46
  static let primaryControlHeight: CGFloat = 52
  static let compactPrimaryControlHeight: CGFloat = 48
  /// Breite der einzelnen Play-/Read-Pille (1 Medien-Aktion).
  static let singlePrimaryWidthFraction: CGFloat = 0.54
  static let actionRowSpacing: CGFloat = 16
  static let compactActionRowSpacing: CGFloat = 10
}

/// System-Typografie für Buch-/Folgen-Detail (Dynamic Type, HIG).
private enum DetailHeroTypography {
  static let heroTitle = Font.title.bold()
  static let heroSubtitle = Font.title2
  static let markIcon = Font.title3
  static let primaryAction = Font.headline
  static let compactPrimaryAction = Font.subheadline
  static let metaLabel = Font.footnote.weight(.semibold)
  static let metaValue = Font.body
  static let metaLink = Font.body
}

private struct DetailHeroMediaAction: Identifiable {
  let id: String
  let markSystemImage: String
  let markAccessibilityLabel: String
  let markEnabled: Bool
  let onMark: () -> Void
  let kind: DetailHeroPrimaryButton.Kind
  let progress01: Double
  let isFinished: Bool
  let primaryEnabled: Bool
  let onPrimary: () -> Void
}

/// Kreis-Button links/rechts neben der Play-Pille (Finish, Read, …).
private struct DetailHeroCircularButton: View {
  let systemImage: String
  let isActive: Bool
  let enabled: Bool
  let size: CGFloat
  let accessibilityLabel: String
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      ZStack {
        Circle()
          .fill(AppTheme.card.opacity(0.88))
        Image(systemName: systemImage)
          .font(DetailHeroTypography.markIcon)
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(isActive ? AppTheme.textPrimary : AppTheme.textSecondary)
      }
      .frame(width: size, height: size)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityLabel(accessibilityLabel)
  }
}

/// Zentrale Play-/Read-Pille: beide in Appearance-Akzent.
private struct DetailHeroPrimaryButton: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent

  enum Kind {
    case play
    case read

    var systemImage: String {
      switch self {
      case .play: "play.fill"
      case .read: "book.closed.fill"
      }
    }

    var title: String {
      switch self {
      case .play: "Play"
      case .read: "Read"
      }
    }

    var accessibilityLabel: String {
      switch self {
      case .play: "Play"
      case .read: "Read eBook"
      }
    }

    func progressAccessibilityValue(fillAmount: Double, isFinished: Bool, isEmpty: Bool) -> String {
      if isFinished { return "Finished" }
      if isEmpty { return "Not started" }
      switch self {
      case .play:
        return "\(Int(fillAmount * 100)) percent listened"
      case .read:
        return "\(Int(fillAmount * 100)) percent read"
      }
    }
  }

  let kind: Kind
  let progress01: Double
  let isFinished: Bool
  let enabled: Bool
  var compact: Bool = false
  let action: () -> Void

  private var fillAmount: Double {
    if isFinished { return 1 }
    return min(1, max(0, progress01))
  }

  private var isEmptyProgress: Bool {
    !isFinished && fillAmount < 0.001
  }

  private var progressAccessibilityLabel: String {
    kind.progressAccessibilityValue(
      fillAmount: fillAmount,
      isFinished: isFinished,
      isEmpty: isEmptyProgress
    )
  }

  private var labelOnAccent: Color {
    let _ = model.appearanceThemeRevision
    return model.appearancePalette.foregroundOnAccent(themeAccent)
  }

  private var actionLabel: some View {
    Label(kind.title, systemImage: kind.systemImage)
      .font(compact ? DetailHeroTypography.compactPrimaryAction : DetailHeroTypography.primaryAction)
      .labelStyle(.titleAndIcon)
  }

  @ViewBuilder
  private func accentLabelColored(fillWidth: CGFloat, in size: CGSize) -> some View {
    let masked = actionLabel
      .foregroundStyle(labelOnAccent)
      .frame(width: size.width, height: size.height)
      .mask(alignment: .leading) {
        Rectangle().frame(width: max(0, fillWidth))
      }

    actionLabel
      .foregroundStyle(themeAccent)
      .frame(width: size.width, height: size.height)
      .overlay(alignment: .leading) { masked }
  }

  @ViewBuilder
  private var buttonLabel: some View {
    if isFinished {
      actionLabel.foregroundStyle(labelOnAccent)
    } else {
      GeometryReader { geo in
        accentLabelColored(
          fillWidth: geo.size.width * fillAmount,
          in: geo.size
        )
        .frame(width: geo.size.width, height: geo.size.height)
      }
    }
  }

  @ViewBuilder
  private var primaryButtonChrome: some View {
    ZStack {
      if isFinished {
        Capsule(style: .continuous)
          .fill(themeAccent)
      } else {
        Capsule(style: .continuous)
          .stroke(themeAccent, lineWidth: DetailActionRowMetrics.borderWidth)
        if !isEmptyProgress {
          capsuleProgressFill(color: themeAccent)
        }
      }
    }
  }

  /// Fortschrittsfüllung in Pillenform — an Capsule-Umriss ausgerichtet (nicht abgeschnitten).
  @ViewBuilder
  private func capsuleProgressFill(color: Color) -> some View {
    Capsule(style: .continuous)
      .fill(color)
      .mask(alignment: .leading) {
        GeometryReader { geo in
          Rectangle()
            .frame(width: max(0, geo.size.width * fillAmount))
        }
      }
  }

  private var controlHeight: CGFloat {
    compact
      ? DetailHeroLayoutMetrics.compactPrimaryControlHeight
      : DetailHeroLayoutMetrics.primaryControlHeight
  }

  var body: some View {
    Button(action: action) {
      ZStack {
        primaryButtonChrome
        buttonLabel
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .frame(height: controlHeight)
      .contentShape(Capsule(style: .continuous))
      .clipShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(kind.accessibilityLabel)
    .accessibilityValue(progressAccessibilityLabel)
    .accessibilityHint(isFinished ? "Starts from the beginning" : "")
  }
}

/// Variable Aktionszeile: 3 Slots (Mark · Play · Balance) oder 4 (Mark · Play · Read · Mark).
private struct DetailHeroActionsBar: View {
  let actions: [DetailHeroMediaAction]

  private var isCompact: Bool { actions.count > 1 }
  private var sideSize: CGFloat {
    isCompact
      ? DetailHeroLayoutMetrics.compactSideControlSize
      : DetailHeroLayoutMetrics.sideControlSize
  }
  private var rowSpacing: CGFloat {
    isCompact
      ? DetailHeroLayoutMetrics.compactActionRowSpacing
      : DetailHeroLayoutMetrics.actionRowSpacing
  }

  var body: some View {
    Group {
      if actions.count > 1 {
        compactActionsRow
      } else if let action = actions.first {
        singleActionRow(action)
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// Vier Buttons: [Mark Hören] [Play] [Read] [Mark Lesen]
  private var compactActionsRow: some View {
    HStack(spacing: rowSpacing) {
      heroMarkButton(actions[0])
      heroPrimaryButton(actions[0], compact: true)
        .frame(maxWidth: .infinity)
      if actions.count > 1 {
        heroPrimaryButton(actions[1], compact: true)
          .frame(maxWidth: .infinity)
        heroMarkButton(actions[1])
      }
    }
    .frame(height: DetailHeroLayoutMetrics.compactPrimaryControlHeight)
  }

  /// Drei Slots: [Mark] [Play/Read] [Balance] — zentriert wie Apple Music.
  private func singleActionRow(_ action: DetailHeroMediaAction) -> some View {
    HStack(spacing: rowSpacing) {
      Spacer(minLength: 0)
      heroMarkButton(action)
      heroPrimaryButton(action, compact: false)
        .containerRelativeFrame(.horizontal) { width, _ in
          width * DetailHeroLayoutMetrics.singlePrimaryWidthFraction
        }
      detailHeroBalanceSlot(size: sideSize)
      Spacer(minLength: 0)
    }
    .frame(height: DetailHeroLayoutMetrics.primaryControlHeight)
  }

  private func heroMarkButton(_ action: DetailHeroMediaAction) -> some View {
    DetailHeroCircularButton(
      systemImage: action.markSystemImage,
      isActive: true,
      enabled: action.markEnabled,
      size: sideSize,
      accessibilityLabel: action.markAccessibilityLabel,
      onTap: action.onMark
    )
  }

  private func heroPrimaryButton(_ action: DetailHeroMediaAction, compact: Bool) -> some View {
    DetailHeroPrimaryButton(
      kind: action.kind,
      progress01: action.progress01,
      isFinished: action.isFinished,
      enabled: action.primaryEnabled,
      compact: compact,
      action: action.onPrimary
    )
  }
}

@ViewBuilder
private func detailHeroBalanceSlot(size: CGFloat) -> some View {
  Color.clear
    .frame(width: size, height: size)
    .accessibilityHidden(true)
}

/// Hintergrund: Rahmen, Fortschrittsfüllung oder Vollfläche — einheitlich für alle Detail-Aktionsbuttons.
private struct DetailActionControlChrome: View {
  @Environment(\.themeAccent) private var themeAccent
  let isFinished: Bool
  var progress01: Double = 0

  private var fillAmount: Double {
    if isFinished { return 1 }
    return min(1, max(0, progress01))
  }

  private var isEmptyProgress: Bool {
    !isFinished && fillAmount < 0.001
  }

  var body: some View {
    ZStack {
      if isFinished {
        DetailActionRowMetrics.corner.fill(themeAccent)
      } else {
        DetailActionRowMetrics.corner.stroke(
          themeAccent, lineWidth: DetailActionRowMetrics.borderWidth)
        if !isEmptyProgress {
          GeometryReader { geo in
            DetailActionRowMetrics.progressFill(
              width: max(0, geo.size.width * fillAmount),
              height: geo.size.height,
              fillAmount: fillAmount,
              isFinished: isFinished,
              color: themeAccent
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          }
        }
      }
    }
    .clipShape(DetailActionRowMetrics.corner)
  }
}

/// Schmaler Mark-Button neben Play/Read in der Detail-Leiste (deutlich schmaler als Hauptaktion).
private struct DetailSecondaryMarkButton: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let isFinished: Bool
  let markAccessibilityLabel: String
  let unmarkAccessibilityLabel: String
  let enabled: Bool
  let onTap: () -> Void

  private var iconColor: Color {
    let _ = model.appearanceThemeRevision
    guard enabled else { return AppTheme.textSecondary }
    if isFinished {
      return model.appearancePalette.foregroundOnAccent(themeAccent)
    }
    return themeAccent
  }

  var body: some View {
    Button(action: onTap) {
      ZStack {
        DetailActionControlChrome(isFinished: isFinished)
        Image(systemName: isFinished ? "arrow.uturn.backward" : "checkmark")
          .font(.subheadline.weight(.semibold))
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(iconColor)
      }
      .frame(width: DetailActionRowMetrics.markButtonWidth)
      .frame(maxHeight: .infinity)
      .contentShape(DetailActionRowMetrics.corner)
      .clipShape(DetailActionRowMetrics.corner)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityLabel(isFinished ? unmarkAccessibilityLabel : markAccessibilityLabel)
  }
}

/// Play-/Read-Button in Details: Akzentfläche füllt sich mit Fortschritt (keine separate Progress-Bar).
private struct DetailProgressFillActionButton: View {
  enum Kind {
    case play
    case read

    var systemImage: String {
      switch self {
      case .play: "play.fill"
      case .read: "book.closed.fill"
      }
    }

    var title: String {
      switch self {
      case .play: "Play"
      case .read: "Read"
      }
    }

    var accessibilityLabel: String {
      switch self {
      case .play: "Play"
      case .read: "Read eBook"
      }
    }

    func progressAccessibilityValue(fillAmount: Double, isFinished: Bool, isEmpty: Bool) -> String {
      if isFinished { return "Finished" }
      if isEmpty { return "Not started" }
      switch self {
      case .play:
        return "\(Int(fillAmount * 100)) percent listened"
      case .read:
        return "\(Int(fillAmount * 100)) percent read"
      }
    }
  }

  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent

  let kind: Kind
  let progress01: Double
  let isFinished: Bool
  let action: () -> Void

  private var fillAmount: Double {
    if isFinished { return 1 }
    return min(1, max(0, progress01))
  }

  /// Kein Fortschritt und nicht abgeschlossen → nur Rahmen, kein Fill-Hintergrund.
  private var isEmptyProgress: Bool {
    !isFinished && fillAmount < 0.001
  }

  private var progressAccessibilityLabel: String {
    kind.progressAccessibilityValue(
      fillAmount: fillAmount,
      isFinished: isFinished,
      isEmpty: isEmptyProgress
    )
  }

  private var labelOnAccentFill: Color {
    let _ = model.appearanceThemeRevision
    return model.appearancePalette.foregroundOnAccent(themeAccent)
  }

  private var actionLabel: some View {
    HStack(spacing: 6) {
      Image(systemName: kind.systemImage)
        .symbolRenderingMode(.monochrome)
      Text(kind.title)
    }
    .font(.subheadline.weight(.semibold))
  }

  /// Solange der Balken Label nicht erreicht hat: Akzent; darunter kontrastreich auf gefüllter Fläche.
  @ViewBuilder
  private func actionLabelColored(fillWidth: CGFloat, in size: CGSize) -> some View {
    let masked = actionLabel
      .foregroundStyle(labelOnAccentFill)
      .frame(width: size.width, height: size.height)
      .mask(alignment: .leading) {
        Rectangle().frame(width: max(0, fillWidth))
      }

    actionLabel
      .foregroundStyle(themeAccent)
      .frame(width: size.width, height: size.height)
      .overlay(alignment: .leading) { masked }
  }

  @ViewBuilder
  private var actionLabelColored: some View {
    if isFinished {
      actionLabel.foregroundStyle(labelOnAccentFill)
    } else {
      GeometryReader { geo in
        actionLabelColored(
          fillWidth: geo.size.width * fillAmount,
          in: geo.size
        )
        .frame(width: geo.size.width, height: geo.size.height)
      }
    }
  }

  private var actionControl: some View {
    ZStack {
      DetailActionControlChrome(isFinished: isFinished, progress01: progress01)
      actionLabelColored
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(DetailActionRowMetrics.corner)
    .clipShape(DetailActionRowMetrics.corner)
  }

  var body: some View {
    Button(action: action) {
      actionControl
    }
    .buttonStyle(.plain)
    .tint(nil)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(kind.accessibilityLabel)
    .accessibilityValue(progressAccessibilityLabel)
    .accessibilityHint(isFinished ? "Starts from the beginning" : "")
  }
}

extension DetailProgressFillActionButton {
  init(progress01: Double, isFinished: Bool, action: @escaping () -> Void) {
    self.init(kind: .play, progress01: progress01, isFinished: isFinished, action: action)
  }
}

struct BookDetailView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.dismiss) private var dismiss
  let bookId: String
  @State private var detail: ABSBook?
  @State private var coverTintColor: Color = AppTheme.background
  @State private var coverImageForTint: UIImage?
  @State private var chaptersExpanded = false
  @State private var bookmarksExpanded = false
  @State private var sessionsExpanded = false
  @State private var listeningSessions: [ABSListeningSession] = []
  @State private var confirmDiscardListeningProgress = false
  @State private var confirmMarkBookFinished = false
  @State private var confirmMarkBookUnfinished = false
  @State private var confirmMarkEbookAsRead = false
  @State private var confirmResetEbookRead = false
  /// Autor/Serie/Genre/Sprecher oberhalb des Buch-Details — nicht `libraryEntityDetailNav` (würde Detail poppen).
  @State private var linkedEntityDetailNav: BooksEntityDetailNav?

  private var book: ABSBook {
    detail
      ?? model.books.first { $0.id == bookId }
      ?? model.startBooks.first { $0.id == bookId }
      ?? model.searchBooks.first { $0.id == bookId }
      ?? model.downloadedShelfBooks.first { $0.id == bookId }
      ?? ABSBook(
        id: bookId,
        libraryId: nil,
        media: ABSBookMedia(
          metadata: ABSBookMediaMetadata(offlineTitle: "…", authorLine: ""),
          duration: nil, numTracks: nil, chapters: nil, tracks: nil),
        addedAt: nil, updatedAt: nil)
  }

  private var prog: ABSUserMediaProgress? { model.progressByItemId[bookId] }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        VStack(spacing: 0) {
          coverSection
          infoSection
          if let d = detail {
            detailActionsAndMeta(book: d)
          }
        }
        if let d = detail {
          bookChaptersSection(book: d)
          BookmarksDisclosure(
            expanded: $bookmarksExpanded,
            libraryItemId: bookId,
            onJump: { mark in
              Task { await model.jumpToBookmark(mark, autoPlay: true) }
            }
          )
          ListeningHistoryDisclosure(
            expanded: $sessionsExpanded,
            sessions: listeningSessions,
            isNetworkReachable: model.isNetworkReachable,
            emptyOnlineText: "No listening sessions recorded for this book yet.",
            emptyOfflineText: "Listening history is unavailable offline.",
            onJumpToSessionStart: { session in
              Task { await model.play(book: d, resumeAtOverride: session.startTime, autoPlay: true) }
            }
          )
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .abstandDetailScrollBackground(coverTintColor)
    .navigationTitle("")
    .toolbarTitleDisplayMode(.inline)
    .tint(model.appearanceAccentColor)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        bookDetailUtilityToolbarItems(book: detail ?? book)
      }
    }
    .onChange(of: model.appearanceThemeRevision) { _, _ in
      applyCoverTintFromStoredImage()
    }
    .task {
      let loaded = await model.loadBookDetail(id: bookId)
      detail = loaded
      await loadCoverTint()
    }
    .task(id: bookId) {
      listeningSessions = await model.loadBookListeningSessions(
        libraryItemId: bookId, bookMediaId: detail?.mediaId ?? book.mediaId)
    }
    .alert("Reset listening progress?", isPresented: $confirmDiscardListeningProgress) {
      Button("Cancel", role: .cancel) {}
      Button("Reset", role: .destructive) {
        Task { await model.discardBookProgress(bookId: bookId) }
      }
    } message: {
      Text("This removes your saved position for this book. You cannot undo this.")
    }
    .alert("Mark as finished?", isPresented: $confirmMarkBookFinished) {
      Button("Cancel", role: .cancel) {}
      Button("Mark as finished") {
        Task { await model.markFinished(bookId: bookId) }
      }
    } message: {
      Text("Your current position will be saved as complete.")
    }
    .alert("Mark as not finished?", isPresented: $confirmMarkBookUnfinished) {
      Button("Cancel", role: .cancel) {}
      Button("Mark as not finished") {
        Task { await model.markUnfinished(bookId: bookId) }
      }
    } message: {
      Text("You can resume from your saved position.")
    }
    .alert("Mark as read?", isPresented: $confirmMarkEbookAsRead) {
      Button("Cancel", role: .cancel) {}
      Button("Mark as read") {
        Task { await markAttachedEbookAsRead(book: detail ?? book) }
      }
    } message: {
      Text("Your reading progress will be saved as complete.")
    }
    .alert("Mark as not read?", isPresented: $confirmResetEbookRead) {
      Button("Cancel", role: .cancel) {}
      Button("Mark as not read", role: .destructive) {
        Task { await resetAttachedEbookReadProgress(book: detail ?? book) }
      }
    } message: {
      Text("This resets your saved eBook position. You cannot undo this.")
    }
    .navigationDestination(item: $linkedEntityDetailNav) { nav in
      BooksEntityDetailView(nav: nav)
    }
  }

  private func openLinkedEntityDetail(_ nav: BooksEntityDetailNav) {
    model.prepareEntityDetail(for: nav)
    linkedEntityDetailNav = nav
  }

  private func applyCoverTintFromStoredImage() {
    if let coverImageForTint {
      coverTintColor = coverDominantBackgroundTint(from: coverImageForTint)
    } else {
      coverTintColor = AppTheme.background
    }
  }

  private func loadCoverTint() async {
    guard let url = model.coverURL(for: bookId) else { return }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let image = UIImage(data: data)
      else { return }
      await MainActor.run {
        coverImageForTint = image
        coverTintColor = coverDominantBackgroundTint(from: image)
      }
    } catch {}
  }

  @ViewBuilder
  private func bookDetailUtilityToolbarItems(book d: ABSBook) -> some View {
    let rowProgress = model.progressByItemId[d.id]
    let canDiscardProgress: Bool = {
      guard let p = rowProgress else { return false }
      if p.isFinished { return true }
      if p.currentTime > 1 { return true }
      if p.duration > 0, p.progress > 0.001 { return true }
      return false
    }()
    let discardEnabled = canDiscardProgress && model.isNetworkReachable
    let storageId = model.downloadStorageIdForLibraryItem(d.id) ?? d.id

    DetailToolbarDownloadItem(
      storageId: storageId,
      onStartDownload: { model.startDownload(book: d) },
      onRemoveDownload: { model.removeLocalDownload(bookId: storageId) }
    )

    DetailToolbarResetProgressItem(enabled: discardEnabled) {
      confirmDiscardListeningProgress = true
    }
    .tint(discardEnabled ? AppTheme.danger : AppTheme.textSecondary)
  }

  private func resolvedEbookFormat(for book: ABSBook) -> ABSEbookFormat? {
    book.readableAttachedEbook?.format ?? book.attachedEbookFormats.first
  }

  private func markAttachedEbookAsRead(book: ABSBook) async {
    guard let format = resolvedEbookFormat(for: book) else { return }
    await model.markEbookAsFinished(libraryItemId: book.id, format: format)
  }

  private func resetAttachedEbookReadProgress(book: ABSBook) async {
    guard let format = resolvedEbookFormat(for: book) else { return }
    await model.resetEbookReadingProgress(libraryItemId: book.id, format: format)
  }

  private var coverSection: some View {
    CoverImageView(
      url: model.coverURL(for: bookId),
      token: model.token,
      itemId: bookId,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheRevision: model.coverImageCacheRevision
    )
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
    .padding(.top, DetailHeroLayoutMetrics.coverTopPadding)
  }

  private var infoSection: some View {
    VStack {
      Text(book.displayTitle)
        .font(DetailHeroTypography.heroTitle)
        .foregroundStyle(AppTheme.textPrimary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
      if !book.displayAuthors.isEmpty && book.displayAuthors != "—" {
        Text(book.displayAuthors)
          .font(DetailHeroTypography.heroSubtitle)
          .foregroundStyle(AppTheme.textSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(.top, DetailHeroLayoutMetrics.titleTopSpacing)
  }

  private var bookPlayProgress01: Double {
    guard let p = prog else { return 0 }
    if p.isFinished { return 1 }
    if p.duration > 0 { return min(1, max(0, p.progress)) }
    let total = book.media.duration ?? 0
    if total > 0 { return min(1, max(0, p.currentTime / total)) }
    return 0
  }

  private var bookEbookReadProgress01: Double {
    guard let f = model.ebookDisplayProgressFraction(libraryItemId: bookId) else { return 0 }
    if f >= 0.995 { return 1 }
    return min(1, max(0, f))
  }

  private var isEbookReadFinished: Bool {
    guard let f = model.ebookDisplayProgressFraction(libraryItemId: bookId) else { return false }
    return f >= 0.995
  }

  private func bookDurationLabel(for d: ABSBook) -> String {
    let sec = d.media.duration ?? prog?.duration ?? 0
    guard sec > 0 else { return "—" }
    return formatPlaybackTime(sec)
  }

  private func bookDetailHeroActions(
    for d: ABSBook,
    isListenFinished: Bool,
    isEbookReadFinished: Bool
  ) -> [DetailHeroMediaAction] {
    var actions: [DetailHeroMediaAction] = []
    if d.isPlayableAudiobook {
      actions.append(
        DetailHeroMediaAction(
          id: "play",
          markSystemImage: isListenFinished ? "arrow.uturn.backward" : "checkmark",
          markAccessibilityLabel: isListenFinished ? "Mark as not finished" : "Mark as finished",
          markEnabled: true,
          onMark: {
            if isListenFinished {
              confirmMarkBookUnfinished = true
            } else {
              confirmMarkBookFinished = true
            }
          },
          kind: .play,
          progress01: bookPlayProgress01,
          isFinished: isListenFinished,
          primaryEnabled: !model.isPreparingEbook,
          onPrimary: {
            Task {
              await model.play(
                book: d,
                resumeAtOverride: isListenFinished ? 0 : nil,
                autoPlay: true
              )
            }
          }
        )
      )
    }
    if d.hasReadableAttachedEbook {
      actions.append(
        DetailHeroMediaAction(
          id: "read",
          markSystemImage: isEbookReadFinished ? "arrow.uturn.backward" : "checkmark",
          markAccessibilityLabel: isEbookReadFinished ? "Mark as not read" : "Mark as read",
          markEnabled: !model.isPreparingEbook && resolvedEbookFormat(for: d) != nil,
          onMark: {
            if isEbookReadFinished {
              confirmResetEbookRead = true
            } else {
              confirmMarkEbookAsRead = true
            }
          },
          kind: .read,
          progress01: bookEbookReadProgress01,
          isFinished: isEbookReadFinished,
          primaryEnabled: !model.isPreparingEbook && model.isNetworkReachable,
          onPrimary: {
            Task { await model.openAttachedEbook(for: d) }
          }
        )
      )
    }
    return actions
  }

  private func detailActionsAndMeta(book d: ABSBook) -> some View {
    let m = d.media.metadata
    let isListenFinished = prog?.isFinished == true
    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      DetailHeroActionsBar(
        actions: bookDetailHeroActions(
          for: d,
          isListenFinished: isListenFinished,
          isEbookReadFinished: isEbookReadFinished
        )
      )
      .padding(.top, AppTheme.Layout.detailPlayButtonTopPadding)
      .padding(.bottom, AppTheme.Layout.detailPlayButtonBottomPadding)

      if let authors = m.authors, !authors.isEmpty {
        detailMetaLabeledRow(title: "Author") {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(authors, id: \.id) { author in
              Button {
                openLinkedEntityDetail(
                  BooksEntityDetailNav(
                    kind: .author,
                    entityId: author.id,
                    title: author.name,
                    numBooks: nil))
              } label: {
                Text(author.name)
                  .font(DetailHeroTypography.metaLink)
                  .foregroundStyle(themeAccent)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      if let narrators = m.narratorName?.trimmingCharacters(in: .whitespacesAndNewlines), !narrators.isEmpty {
        detailMetaLabeledRow(title: "Narrator") {
          Button {
            openLinkedEntityDetail(
              BooksEntityDetailNav(
                kind: .narrator,
                entityId: narrators,
                title: narrators,
                numBooks: nil))
          } label: {
            Text(narrators)
              .font(DetailHeroTypography.metaLink)
              .foregroundStyle(themeAccent)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
        }
      }
      if let seriesList = m.series, !seriesList.isEmpty {
        detailMetaLabeledRow(title: "Series") {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(seriesList, id: \.id) { s in
              Button {
                openLinkedEntityDetail(
                  BooksEntityDetailNav(
                    kind: .series,
                    entityId: s.id,
                    title: s.name,
                    numBooks: nil))
              } label: {
                Text(seriesDisplayLine(for: s))
                  .font(DetailHeroTypography.metaLink)
                  .foregroundStyle(themeAccent)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)
            }
          }
        }
      } else if let line = m.resolvedSeriesDisplay, !line.isEmpty {
        detailMetaRow("Series", line)
      }
      detailMetaRow("Duration", bookDurationLabel(for: d))
      detailMetaRow("Year", m.publishedYear ?? "—")
      detailMetaRow("Publisher", m.publisher ?? "—")
      detailCategoriesRow(metadata: m)
      detailTagsRow(book: d)
      detailMetaRow(
        "Description",
        absPlainText(fromHTML: m.descriptionPlain ?? m.description).nilIfEmpty ?? "—")
    }
  }

  @ViewBuilder
  private func detailTagsRow(book: ABSBook) -> some View {
    let tags = (book.media.tags ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if tags.isEmpty {
      detailMetaRow("Tags", "—")
    } else {
      detailMetaLabeledRow(title: "Tags") {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
            Button {
              openLinkedEntityDetail(
                BooksEntityDetailNav(
                  kind: .tag,
                  entityId: tag,
                  title: tag,
                  numBooks: model.browseTags.first {
                    $0.name.localizedCaseInsensitiveCompare(tag) == .orderedSame
                  }?.numBooks
                ))
            } label: {
              Text(tag)
                .font(DetailHeroTypography.metaLink)
                .foregroundStyle(themeAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func detailCategoriesRow(metadata m: ABSBookMediaMetadata) -> some View {
    let genres = (m.genres ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if genres.isEmpty {
      detailMetaRow("Genres", "—")
    } else {
      detailMetaLabeledRow(title: "Genres") {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(genres.enumerated()), id: \.offset) { _, genre in
            Button {
              openLinkedEntityDetail(
                BooksEntityDetailNav(
                  kind: .genre,
                  entityId: genre,
                  title: genre,
                  numBooks: model.browseGenres.first {
                    $0.name.localizedCaseInsensitiveCompare(genre) == .orderedSame
                  }?.numBooks))
            } label: {
              Text(genre)
                .font(DetailHeroTypography.metaLink)
                .foregroundStyle(themeAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func detailMetaLabeledRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(title.uppercased())
        .font(DetailHeroTypography.metaLabel)
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func detailMetaRow(_ k: String, _ v: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(k.uppercased())
        .font(DetailHeroTypography.metaLabel)
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      Text(v)
        .font(DetailHeroTypography.metaValue)
        .foregroundStyle(AppTheme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private enum ChapterPlayState {
    case notStarted
    case inProgress
    case completed
  }

  @ViewBuilder
  private func bookChaptersSection(book: ABSBook) -> some View {
    let chapters = (book.media.chapters ?? []).sorted { $0.start < $1.start }
    if chapters.isEmpty {
      EmptyView()
    } else {
      DisclosureGroup(isExpanded: $chaptersExpanded) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(chapters.enumerated()), id: \.offset) { idx, ch in
            bookChapterRow(chapter: ch, book: book)
            if idx < chapters.count - 1 {
              Divider().background(AppTheme.textSecondary.opacity(0.15))
            }
          }
        }
        .padding(.top, 4)
      } label: {
        Text("Chapters")
          .font(DetailHeroTypography.metaLabel)
          .foregroundStyle(AppTheme.textSecondary)
          .textCase(.uppercase)
          .tracking(0.6)
      }
      .tint(model.appearanceAccentColor)
    }
  }

  private func chapterProgressState(
    chapter: ABSChapter,
    progress: ABSUserMediaProgress?,
    finished: Bool
  ) -> ChapterPlayState {
    if finished { return .completed }
    let t = progress?.currentTime ?? 0
    let eps = 0.75
    if t + eps >= chapter.end { return .completed }
    if t + eps >= chapter.start { return .inProgress }
    return .notStarted
  }

  @ViewBuilder
  private func chapterStatusIcon(state: ChapterPlayState) -> some View {
    switch state {
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(model.appearanceAccentColor)
        .font(.body)
    case .inProgress:
      Image(systemName: "play.circle.fill")
        .foregroundStyle(model.appearanceAccentColor)
        .font(.body)
    case .notStarted:
      EmptyView()
    }
  }

  @ViewBuilder
  private func bookChapterRow(chapter: ABSChapter, book: ABSBook) -> some View {
    let state = chapterProgressState(chapter: chapter, progress: prog, finished: prog?.isFinished == true)
    Button {
      Task { await model.play(book: book, resumeAtOverride: chapter.start, autoPlay: true) }
    } label: {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(chapter.title)
            .font(.headline)
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
          Text("\(formatPlaybackTime(chapter.start)) – \(formatPlaybackTime(chapter.end))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
        }
        Spacer(minLength: 8)
        chapterStatusIcon(state: state)
        Image(systemName: "play.circle")
          .font(.title3)
          .foregroundStyle(model.appearanceAccentColor)
      }
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Play from chapter \(chapter.title)")
  }

  private func seriesDisplayLine(for s: ABSSeries) -> String {
    if let q = s.sequence?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
      return "\(s.name) (\(q))"
    }
    return s.name
  }
}

// MARK: - Podcast episode detail view

struct PodcastEpisodeDetailView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.dismiss) private var dismiss
  let episode: ABSPodcastEpisodeListItem
  @State private var detail: ABSPodcastEpisodeExpandedDetail?
  @State private var coverTintColor: Color = AppTheme.background
  @State private var coverImageForTint: UIImage?
  @State private var sessionsExpanded = false
  @State private var listeningSessions: [ABSListeningSession] = []
  @State private var confirmDiscardEpisodeProgress = false
  @State private var confirmMarkEpisodeFinished = false
  @State private var confirmMarkEpisodeUnfinished = false

  private var prog: ABSUserMediaProgress? { model.progressByItemId[episode.progressLookupKey] }

  /// `recentEpisode` in „items-in-progress" liefert oft keine Länge; die kommt dann aus `mediaProgress`.
  private var resolvedTotalDurationSeconds: Double {
    if episode.duration > 0 { return episode.duration }
    if let p = prog, p.duration > 0 { return p.duration }
    return 0
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        VStack(spacing: 0) {
          coverSection
          infoSection
          if let d = detail {
            detailActionsAndMeta(d)
          }
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .abstandDetailScrollBackground(coverTintColor)
    .navigationTitle("")
    .toolbarTitleDisplayMode(.inline)
    .tint(model.appearanceAccentColor)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        episodeDetailUtilityToolbarItems
      }
    }
    .onChange(of: model.appearanceThemeRevision) { _, _ in
      applyCoverTintFromStoredImage()
    }
    .task {
      async let d = model.loadPodcastEpisodeDetail(episode)
      let showMid =
        model.podcastShows.first(where: { $0.id == episode.libraryItemId })?.mediaId
        ?? model.podcastSearchBooks.first(where: { $0.id == episode.libraryItemId })?.mediaId
      async let s = model.loadPodcastEpisodeListeningSessions(episode, showMediaId: showMid)
      detail = await d
      listeningSessions = await s
      await loadCoverTint()
    }
    .alert("Reset listening progress?", isPresented: $confirmDiscardEpisodeProgress) {
      Button("Cancel", role: .cancel) {}
      Button("Reset", role: .destructive) {
        Task { await model.discardPodcastEpisodeProgress(episode) }
      }
    } message: {
      Text("This removes your saved position for this episode. You cannot undo this.")
    }
    .alert("Mark as finished?", isPresented: $confirmMarkEpisodeFinished) {
      Button("Cancel", role: .cancel) {}
      Button("Mark as finished") {
        Task { await model.markPodcastEpisodeFinished(episode) }
      }
    } message: {
      Text("Your current position will be saved as complete.")
    }
    .alert("Mark as not finished?", isPresented: $confirmMarkEpisodeUnfinished) {
      Button("Cancel", role: .cancel) {}
      Button("Mark as not finished") {
        Task { await model.markPodcastEpisodeUnfinished(episode) }
      }
    } message: {
      Text("You can resume from your saved position.")
    }
  }

  private func applyCoverTintFromStoredImage() {
    if let coverImageForTint {
      coverTintColor = coverDominantBackgroundTint(from: coverImageForTint)
    } else {
      coverTintColor = AppTheme.background
    }
  }

  private func loadCoverTint() async {
    guard let url = model.coverURL(for: episode.libraryItemId) else { return }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let image = UIImage(data: data)
      else { return }
      await MainActor.run {
        coverImageForTint = image
        coverTintColor = coverDominantBackgroundTint(from: image)
      }
    } catch {}
  }

  @ViewBuilder
  private var episodeDetailUtilityToolbarItems: some View {
    let rowProgress = model.progressByItemId[episode.progressLookupKey]
    let canDiscardProgress: Bool = {
      guard let p = rowProgress else { return false }
      if p.isFinished { return true }
      if p.currentTime > 1 { return true }
      if p.duration > 0, p.progress > 0.001 { return true }
      return false
    }()
    let discardEnabled = canDiscardProgress && model.isNetworkReachable
    let sid = model.podcastEpisodeOfflineStorageId(episode)

    DetailToolbarDownloadItem(
      storageId: sid,
      onStartDownload: { model.startDownloadPodcastEpisode(episode) },
      onRemoveDownload: { model.removeLocalDownload(bookId: sid) }
    )

    DetailToolbarResetProgressItem(enabled: discardEnabled) {
      confirmDiscardEpisodeProgress = true
    }
    .tint(discardEnabled ? AppTheme.danger : AppTheme.textSecondary)
  }

  private var coverSection: some View {
    CoverImageView(
      url: model.coverURL(for: episode.libraryItemId),
      token: model.token,
      itemId: episode.libraryItemId,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheRevision: model.coverImageCacheRevision
    )
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
    .padding(.top, DetailHeroLayoutMetrics.coverTopPadding)
  }

  private var infoSection: some View {
    VStack {
      Text(episode.episodeTitle)
        .font(DetailHeroTypography.heroTitle)
        .foregroundStyle(AppTheme.textPrimary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
      Text(episode.showTitle)
        .font(DetailHeroTypography.heroSubtitle)
        .foregroundStyle(AppTheme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
    .padding(.top, DetailHeroLayoutMetrics.titleTopSpacing)
  }

  private var episodePlayProgress01: Double {
    guard let p = prog else { return 0 }
    if p.isFinished { return 1 }
    if p.duration > 0 { return min(1, max(0, p.progress)) }
    let total = resolvedTotalDurationSeconds
    if total > 0 { return min(1, max(0, p.currentTime / total)) }
    return 0
  }

  private var episodeDurationLabel: String {
    let sec = resolvedTotalDurationSeconds
    guard sec > 0 else { return "—" }
    return formatPlaybackTime(sec)
  }

  private func detailActionsAndMeta(_ d: ABSPodcastEpisodeExpandedDetail) -> some View {
    let isFinished = prog?.isFinished == true
    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      DetailHeroActionsBar(
        actions: [
          DetailHeroMediaAction(
            id: "play",
            markSystemImage: isFinished ? "arrow.uturn.backward" : "checkmark",
            markAccessibilityLabel: isFinished ? "Mark as not finished" : "Mark as finished",
            markEnabled: true,
            onMark: {
              if isFinished {
                confirmMarkEpisodeUnfinished = true
              } else {
                confirmMarkEpisodeFinished = true
              }
            },
            kind: .play,
            progress01: episodePlayProgress01,
            isFinished: isFinished,
            primaryEnabled: true,
            onPrimary: {
              Task {
                await model.playPodcastEpisode(
                  episode,
                  resumeAtOverride: isFinished ? 0 : nil
                )
              }
            }
          ),
        ]
      )
      .padding(.top, AppTheme.Layout.detailPlayButtonTopPadding)
      .padding(.bottom, AppTheme.Layout.detailPlayButtonBottomPadding)

      if let show = model.podcastShows.first(where: { $0.id == episode.libraryItemId }) ?? model.podcastSearchBooks.first(where: { $0.id == episode.libraryItemId }) {
        Button {
          Task {
            await model.selectPodcastShowFilter(show.id)
            dismiss()
          }
        } label: {
          HStack(alignment: .top, spacing: 10) {
            Text("SHOW".uppercased())
              .font(DetailHeroTypography.metaLabel)
              .foregroundStyle(AppTheme.textSecondary)
              .frame(width: 112, alignment: .leading)
            Text(show.displayTitle)
              .font(DetailHeroTypography.metaLink)
              .foregroundStyle(themeAccent)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .buttonStyle(.plain)
      }
      detailMetaRow("Duration", episodeDurationLabel)
      if !d.showAuthors.isEmpty {
        HStack(alignment: .top, spacing: 10) {
          Text("HOST".uppercased())
            .font(DetailHeroTypography.metaLabel)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(width: 112, alignment: .leading)
          VStack(alignment: .leading, spacing: 4) {
            ForEach(d.showAuthors, id: \.id) { author in
              Button {
                model.openPodcastSearchFromText(author.name)
                dismiss()
              } label: {
                Text(author.name)
                  .font(DetailHeroTypography.metaLink)
                  .foregroundStyle(themeAccent)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .multilineTextAlignment(.leading)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      if let s = d.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
        detailMetaRow("Subtitle", s)
      }
      if let pub = d.pubDate?.trimmingCharacters(in: .whitespacesAndNewlines), !pub.isEmpty {
        detailMetaRow("Published", pub)
      }
      if let g = d.showGenres, !g.isEmpty {
        detailMetaRow("Categories", g.joined(separator: ", "))
      }
      detailMetaRow(
        "Episode",
        absPlainText(fromHTML: d.episodeDescriptionHTML).nilIfEmpty ?? "—")
      detailMetaRow(
        "Show notes",
        absPlainText(fromHTML: d.showDescriptionHTML).nilIfEmpty ?? "—")
      ListeningHistoryDisclosure(
        expanded: $sessionsExpanded,
        sessions: listeningSessions,
        isNetworkReachable: model.isNetworkReachable,
        emptyOnlineText: "No listening sessions recorded for this episode yet.",
        emptyOfflineText: "Listening history is unavailable offline.",
        onJumpToSessionStart: { session in
          Task {
            await model.playPodcastEpisode(episode, resumeAtOverride: session.startTime)
          }
        }
      )
    }
  }

  private func detailMetaRow(_ k: String, _ v: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(k.uppercased())
        .font(DetailHeroTypography.metaLabel)
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      Text(v)
        .font(DetailHeroTypography.metaValue)
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
    case .search:
      Binding(
        get: { model.searchEntityDetailNav },
        set: { model.searchEntityDetailNav = $0 }
      )
    case .podcasts, .settings, .ebooks:
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

private struct BooksEntityDetailView: View {
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
      n = nav.numBooks ?? (model.entityDetailTotal > 0 ? model.entityDetailTotal : nil)
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
        cacheRevision: model.coverImageCacheRevision
      )
      .aspectRatio(1, contentMode: .fit)
      .containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }
      .clipShape(Circle())
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

  @ViewBuilder
  private var entityCoverPlaceholder: some View {
    if nav.kind == .author {
      ZStack {
        Circle()
          .fill(AppTheme.card)
        Image(systemName: entityPlaceholderIcon)
          .font(.system(size: 44))
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
          .font(.system(size: 44))
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
            LibraryBookCardsFlow {
              ForEach(section.books) { book in
                AuthorDetailBookListCard(book: book, model: model)
              }
            }
          }
        }
        if !standalone.isEmpty {
          VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
            entityDetailSectionHeading(seriesSections.isEmpty ? "Books" : "Other books")
            LibraryBookCardsFlow {
              ForEach(standalone) { book in
                AuthorDetailBookListCard(book: book, model: model)
              }
            }
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
            LibraryBookListCard(book: book, model: model)
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

    guard let url =
      nav.kind == .author
      ? model.authorImageURL(authorId: nav.entityId)
      : model.entityDetailCoverURL(for: nav)
    else { return }

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

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
