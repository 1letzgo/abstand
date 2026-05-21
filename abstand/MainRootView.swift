import Combine
import SwiftUI

struct MainRootView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @Binding var nowPlayingSheetPresented: Bool
  @StateObject private var booksLibraryToolbarState = BooksLibraryToolbarState()
  @StateObject private var podcastCatalogToolbarState = PodcastCatalogToolbarState()
  @State private var booksBrowseCollectionNav: BooksBrowseCollectionNav?

  var body: some View {
    tabViewBody
      .tint(AppTheme.accent)
      .background(AppTheme.background.ignoresSafeArea())
    .fullScreenCover(item: $model.ebookReaderSession) { session in
      ReadiumReaderView(
        title: session.title,
        author: session.author,
        libraryItemId: session.libraryItemId,
        localFileURL: session.localFileURL,
        format: session.format
      )
    }
    .onReceive(model.player.$isPlaying.dropFirst()) { playing in
      guard !playing else { return }
      Task { await model.handlePlaybackPaused() }
    }
    .onChange(of: model.mainTab) { _, tab in
      if tab == .start, model.startShelves.isEmpty, !model.offlineHomeUIActive {
        Task { await model.loadStartDashboard() }
      }
      if tab == .search {
        model.scheduleSearch()
      }
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
      if model.selectedPodcastLibrary == nil && model.mainTab == .podcasts {
        model.mainTab = .start
      }
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
    TabView(selection: $model.mainTab) {
      Tab(AppModel.MainTab.start.rawValue, systemImage: "house.fill", value: AppModel.MainTab.start) {
        homeTabRoot
      }

      if !model.offlineHomeUIActive {
        if model.selectedBooksLibrary != nil {
          Tab(AppModel.MainTab.library.rawValue, systemImage: "books.vertical", value: AppModel.MainTab.library) {
            libraryTabRoot
          }
        }

        if model.selectedPodcastLibrary != nil {
          Tab(AppModel.MainTab.podcasts.rawValue, systemImage: "mic.fill", value: AppModel.MainTab.podcasts) {
            podcastsTabRoot
          }
        }

        Tab(
          AppModel.MainTab.search.rawValue, systemImage: "magnifyingglass", value: AppModel.MainTab.search,
          role: .search
        ) {
          searchTabRoot
        }

        Tab(AppModel.MainTab.settings.rawValue, systemImage: "gearshape.fill", value: AppModel.MainTab.settings) {
          settingsTabRoot
        }
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
  }

  // MARK: - Home tab

  private var homeTabRoot: some View {
    NavigationStack {
      StartDashboardView()
        .abstandTabScreenChrome()
        .navigationTitle(AppModel.MainTab.start.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
          ToolbarItemGroup(placement: .topBarTrailing) {
            HomeServerConnectionIndicatorButton()
          }
        }
        .task {
          await model.probeServerConnectionIfNeeded()
        }
        .booksEntityDetailNavigation()
    }
  }

  // MARK: - Settings tab root

  private var settingsTabRoot: some View {
    NavigationStack {
      SettingsHubRootView()
        .abstandTabScreenChrome()
        .booksEntityDetailNavigation()
    }
    .tint(AppTheme.accent)
  }

  // MARK: - Library tab

  private var libraryTabRoot: some View {
    BooksLibraryTabShell(
      toolbarState: booksLibraryToolbarState,
      collectionNav: $booksBrowseCollectionNav,
      catalog: { booksCatalogScrollView },
      collectionDetail: { nav in
        AnyView(booksBrowseCollectionDetailView(nav: nav))
      }
    )
    .id("books-library-tab")
    .booksEntityDetailNavigation()
    .onAppear { booksLibraryToolbarState.attach(model) }
    .onDisappear { booksLibraryToolbarState.detach() }
  }

  private var booksCatalogScrollView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        booksBrowseSectionStrip
        booksBrowseMainContent
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .abstandScrollScreenBackground()
    .refreshable {
      await model.refreshBooksCatalog()
    }
  }

  private var booksBrowseSectionStrip: some View {
    let tile = AppTheme.Layout.horizontalBrowseStripTile
    let captionW = tile + AppTheme.Layout.horizontalBrowseStripLabelWidthExtra
    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: AppTheme.Layout.horizontalBrowseStripInterTileSpacing) {
        ForEach(BooksBrowseSection.allCases) { section in
          Button {
            model.selectBooksBrowseSection(section)
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
                    model.booksBrowseSection == section ? AppTheme.accent : AppTheme.textSecondary)
              }
              .overlay {
                RoundedRectangle(
                  cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous
                )
                .strokeBorder(
                  model.booksBrowseSection == section ? AppTheme.accent : Color.clear, lineWidth: 2.5)
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

  @ViewBuilder
  private var booksBrowseMainContent: some View {
    switch model.booksBrowseSection {
    case .books:
      booksCatalogBookListBody
    case .author:
      booksBrowseAuthorListBody
    case .narrators:
      booksBrowseNarratorListBody
    case .series:
      booksBrowseSeriesListBody
    case .collections:
      booksBrowseCollectionsListBody
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
      ForEach(rows) { book in
        BookRowCard(book: book, model: model)
          .task(id: book.id) {
            await model.loadMoreIfNeeded(currentItemId: book.id)
          }
      }
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
      .tint(AppTheme.accent)
      .scaleEffect(1.35)
      .padding(.vertical, 48)
      .frame(maxWidth: .infinity)
  }

  private func booksBrowseCountLine(count: Int?) -> String? {
    browseEntityBooksCountLine(count: count)
  }

  private var booksBrowseAuthorListBody: some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Author")
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
            BrowseEntityRowCard(
              title: author.name,
              detailLabel: "Books",
              detailValue: booksBrowseCountLine(count: author.numBooks),
              cacheItemId: "author:\(author.id)",
              coverURL: author.hasAuthorImage ? model.authorImageURL(authorId: author.id) : nil
            )
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
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
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
        ForEach(model.browseNarrators) { narrator in
          Button {
            model.openNarratorDetail(narratorName: narrator.name, numBooks: narrator.numBooks)
          } label: {
            browseNarratorRow(narrator)
          }
          .buttonStyle(.plain)
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
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
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
        ForEach(model.browseCollections) { collection in
          Button {
            booksBrowseCollectionNav = BooksBrowseCollectionNav(id: collection.id, title: collection.name)
          } label: {
            browseCollectionRow(collection)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private func browseNarratorRow(_ narrator: ABSLibraryNarratorListItem) -> some View {
    let bookId = model.browseNarratorCoverItemIdByNarratorName[narrator.name]
    BrowseEntityRowCard(
      title: narrator.name,
      detailLabel: "Books",
      detailValue: booksBrowseCountLine(count: narrator.numBooks),
      cacheItemId: bookId ?? "narrator-ph:\(narrator.id)",
      coverURL: bookId.flatMap { model.coverURL(for: $0) }
    )
  }

  @ViewBuilder
  private func browseSeriesRow(_ series: ABSLibrarySeriesListItem) -> some View {
    let bookId = model.browseRepresentativeBookItemId(from: series.books)
    BrowseEntityRowCard(
      title: series.name,
      detailLabel: "Books",
      detailValue: booksBrowseCountLine(count: series.books?.count),
      cacheItemId: bookId ?? "series-ph:\(series.id)",
      coverURL: bookId.flatMap { model.coverURL(for: $0) }
    )
  }

  @ViewBuilder
  private func browseCollectionRow(_ collection: ABSLibraryCollectionListItem) -> some View {
    let bookId = model.browseRepresentativeBookItemId(from: collection.books)
    BrowseEntityRowCard(
      title: collection.name,
      detailLabel: "Books",
      detailValue: booksBrowseCountLine(count: collection.books?.count),
      cacheItemId: bookId ?? "collection-ph:\(collection.id)",
      coverURL: bookId.flatMap { model.coverURL(for: $0) }
    )
  }

  private func booksBrowseCollectionDetailView(nav: BooksBrowseCollectionNav) -> some View {
    let books = model.booksInBrowseCollection(id: nav.id)
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        if books.isEmpty {
          Text("No books in this collection.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.vertical, 8)
        } else {
          ForEach(books) { book in
            BookRowCard(book: book, model: model)
          }
        }
      }
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .abstandScrollScreenBackground()
    .navigationTitle(nav.title)
    .toolbarTitleDisplayMode(.inline)
  }

  // MARK: - Search tab

  private var searchTabRoot: some View {
    NavigationStack {
      SearchTabView()
        .abstandTabScreenChrome()
        .navigationTitle(AppModel.MainTab.search.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $model.searchText, prompt: "Title, author, series…")
        .onChange(of: model.searchText) { _, _ in model.scheduleSearch() }
        .onSubmit(of: .search) { model.scheduleSearch() }
        .booksEntityDetailNavigation()
    }
  }

  private var catalogFilterBanner: some View {
    HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
      Image(systemName: "line.3.horizontal.decrease.circle")
        .foregroundStyle(AppTheme.textSecondary)
      Text(model.activeLibraryFilterSummary ?? "Library filtered")
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(2)
      Spacer(minLength: 0)
      Button("Show all") {
        model.clearCatalogFilter()
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(AppTheme.accent)
    }
    .padding(.horizontal, AppTheme.Layout.tabPaddingH)
    .padding(.vertical, 8)
    .background(AppTheme.card)
    .clipShape(Capsule())
  }

  private var podcastsTabRoot: some View {
    PodcastCatalogTabShell(toolbarState: podcastCatalogToolbarState) {
      podcastCatalogScrollView
    }
    .id("podcast-catalog-tab")
    .booksEntityDetailNavigation()
    .onAppear { podcastCatalogToolbarState.attach(model) }
    .onDisappear { podcastCatalogToolbarState.detach() }
  }

  private var podcastCatalogBodyIdentity: String {
    let show = model.podcastSelectedShowId ?? "new"
    let rss = model.podcastRssFeedPreviewForShowId ?? "off"
    return "\(show)-\(rss)"
  }

  private var podcastCatalogScrollView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
          podcastShowsCoverStrip
            .id("podcastScrollTop")
          podcastCatalogMainBody
            .id("podcastCatalogBody-\(podcastCatalogBodyIdentity)")
        }
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.withinSectionSpacing)
        .padding(
          .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
      }
      .abstandScrollScreenBackground()
      .refreshable {
        await model.refreshPodcastsTab()
      }
      .onChange(of: model.podcastRssFeedPreviewForShowId) { _, _ in
        scrollPodcastCatalogToTop(proxy: proxy, animated: true)
      }
    }
  }

  private func scrollPodcastCatalogToTop(proxy: ScrollViewProxy, animated: Bool) {
    if animated {
      withAnimation(.easeOut(duration: 0.25)) {
        proxy.scrollTo("podcastScrollTop", anchor: .top)
      }
    } else {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        proxy.scrollTo("podcastScrollTop", anchor: .top)
      }
    }
  }

  @ViewBuilder
  private var podcastCatalogMainBody: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title:"Episodes")
      podcastPodcastsTabEpisodesContent
    }
  }

  private var podcastShowsCoverStrip: some View {
    let cover = AppTheme.Layout.horizontalBrowseStripTile
    let captionW = cover + AppTheme.Layout.horizontalBrowseStripLabelWidthExtra
    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: AppTheme.Layout.horizontalBrowseStripInterTileSpacing) {
        Button {
          Task { await model.selectPodcastShowFilter(nil) }
        } label: {
          VStack(spacing: AppTheme.Layout.horizontalBrowseStripTileLabelSpacing) {
            ZStack {
              RoundedRectangle(
                cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous)
                .fill(AppTheme.card)
                .frame(width: cover, height: cover)
              Image(systemName: "square.grid.2x2")
                .font(.title2)
                .foregroundStyle(model.podcastSelectedShowId == nil ? AppTheme.accent : AppTheme.textSecondary)
            }
            .overlay {
              RoundedRectangle(
                cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous)
                .strokeBorder(
                  model.podcastSelectedShowId == nil ? AppTheme.accent : Color.clear, lineWidth: 2.5)
            }
            Text("New")
              .font(.caption2.weight(.medium))
              .foregroundStyle(AppTheme.textPrimary)
              .lineLimit(1)
              .frame(width: captionW)
          }
        }
        .buttonStyle(.plain)

        if model.podcastShowsLoading, model.podcastShows.isEmpty {
          ProgressView()
            .frame(width: cover, height: cover)
        }

        ForEach(model.podcastShows) { show in
          Button {
            Task { await model.selectPodcastShowFilter(show.id) }
          } label: {
            VStack(spacing: AppTheme.Layout.horizontalBrowseStripTileLabelSpacing) {
              CoverImageView(
                url: model.coverURL(for: show.id),
                token: model.token,
                itemId: show.id,
                cacheAccount: model.coverImageCacheAccountDirectory(),
                cacheRevision: model.coverImageCacheRevision
              )
              .frame(width: cover, height: cover)
              .clipShape(
                RoundedRectangle(cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous))
              .overlay {
                RoundedRectangle(
                  cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous)
                  .strokeBorder(
                    model.podcastSelectedShowId == show.id ? AppTheme.accent : Color.clear, lineWidth: 2.5)
              }
              Text(show.displayTitle)
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

  private var podcastPodcastsTabEpisodesContent: some View {
    let sel = model.podcastSelectedShowId
    let rssConsolidated =
      sel != nil && sel == model.podcastRssFeedPreviewForShowId
    let rssDrafts =
      sel.flatMap { model.podcastRssFeedCachedDrafts(forShowId: $0) }
      ?? model.podcastRssFeedPreviewEpisodes
    let episodes = model.podcastEpisodesForPodcastsTab

    let rssListLoading: Bool = {
      guard rssConsolidated, let sid = sel else { return false }
      return rssDrafts.isEmpty && model.podcastRssFeedLoadInProgressShowIds.contains(sid)
    }()

    let listLoading: Bool = {
      if rssConsolidated { return rssListLoading }
      if model.podcastSelectedShowId != nil {
        return model.isLoadingPodcastShowEpisodes && episodes.isEmpty
      }
      return model.isLoadingPodcasts && episodes.isEmpty
    }()

    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      if listLoading {
        ProgressView()
          .controlSize(.large)
          .tint(AppTheme.accent)
          .padding(.vertical, 32)
          .frame(maxWidth: .infinity)
      }

      if rssConsolidated {
        if !listLoading && rssDrafts.isEmpty && !model.isLoadingPodcastShowEpisodes {
          Text("No episodes found in the feed.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.vertical, 8)
        }
        ForEach(rssDrafts) { draft in
          PodcastRssFeedDraftRow(draft: draft)
        }
      } else {
        if episodes.isEmpty,
          !model.isLoadingPodcasts,
          !model.isLoadingPodcastShowEpisodes
        {
          if model.podcastSelectedShowId != nil {
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

        ForEach(episodes, id: \.progressLookupKey) { episode in
          PodcastEpisodeRowCard(episode: episode, model: model)
            .task(id: episode.progressLookupKey) {
              await model.loadMorePodcastsIfNeeded(currentItemId: episode.id)
            }
        }
      }

      if !rssConsolidated,
        model.podcastSelectedShowId != nil,
        model.isLoadingPodcastShowEpisodes,
        !episodes.isEmpty
      {
        ProgressView()
          .controlSize(.small)
          .tint(AppTheme.accent)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      }
    }
  }
}

// MARK: - Home server connection indicator

private struct HomeServerConnectionIndicatorButton: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Button {
      model.homeToolbarServerConnectionTapped()
    } label: {
      Group {
        if model.isServerConnectionProbeInProgress {
          ProgressView()
            .controlSize(.small)
            .tint(AppTheme.warning)
        } else {
          Image(systemName: "circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(indicatorColor)
        }
      }
      .frame(width: 28, height: 28)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }

  private var indicatorColor: Color {
    switch model.serverConnectionIndicatorState {
    case .online:
      return AppTheme.success
    case .connecting:
      return AppTheme.warning
    case .offline:
      return AppTheme.danger
    }
  }

  private var accessibilityLabel: String {
    switch model.serverConnectionIndicatorState {
    case .online:
      return "Connected to server. Tap to enable offline mode."
    case .connecting:
      return "Checking server connection."
    case .offline:
      if model.offlineHomeUIActive {
        return "Offline mode. Tap to go online."
      }
      return "Not connected to server. Tap to retry."
    }
  }
}

// MARK: - Home dashboard

private struct StartDashboardView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        let hasHomeDownloads =
          !model.downloadedItemIds.isEmpty || model.downloads.activeItemId != nil
        if model.offlineHomeUIActive {
          let hasOfflineContinue = model.startShelves.contains { shelf in
            startDashboardIsContinueShelf(shelf) && (shelf.hasBooks || shelf.hasPodcastEpisodes)
          }
          let showOfflineEmpty =
            !hasHomeDownloads && model.downloadedTitlesForHome.isEmpty && !hasOfflineContinue
          if showOfflineEmpty {
            startDashboardOfflineOnlyEmptyState
          }
          ForEach(model.startShelves) { shelf in
            if startDashboardIsContinueShelf(shelf), shelf.hasBooks || shelf.hasPodcastEpisodes {
              startDashboardContinueListeningSection(shelf)
            }
          }
          if hasHomeDownloads {
            VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
              TabContentSectionTitle(title:"Downloaded")
              ForEach(model.downloadedTitlesForHome) { book in
                BookRowCard(book: book, model: model)
              }
            }
          }
        } else {
          let showStartEmpty =
            model.startShelves.isEmpty && model.startBooks.isEmpty && !hasHomeDownloads
              && model.downloadedTitlesForHome.isEmpty
          if showStartEmpty {
            startDashboardEmptyState
          }
          ForEach(model.startShelves) { shelf in
            let continueSplit =
              startDashboardIsContinueShelf(shelf) && (shelf.hasBooks || shelf.hasPodcastEpisodes)
            Group {
              if continueSplit {
                VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
                  if shelf.hasBooks || shelf.hasPodcastEpisodes {
                    startDashboardContinueListeningSection(shelf)
                  }
                  if shelf.hasAuthors {
                    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
                      TabContentSectionTitle(title:shelf.displayTitle)
                      startDashboardAuthorsContent(shelf.authors, shelf: shelf)
                    }
                  }
                }
              } else {
                // Kompaktes „Listen“-Layout (Zeilen wie Bibliothek); „Recently added“ = Cover-Streifen
                VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
                  if shelf.hasBooks || shelf.hasAuthors || shelf.hasSeries || shelf.hasPodcastEpisodes {
                    TabContentSectionTitle(title:shelf.displayTitle)
                  }
                  if shelf.hasSeries {
                    startDashboardSeriesContent(shelf.series, shelf: shelf)
                  } else if shelf.hasBooks {
                    if startDashboardUsesCompactLayout(shelf) {
                      StartShelfCoverSwipeRow(books: shelf.books)
                    } else {
                      ForEach(shelf.books) { book in
                        BookRowCard(
                          book: book,
                          model: model,
                          opensEbookOnCover: shelf.category == "continueEbooks"
                        )
                      }
                    }
                  }
                  if shelf.hasAuthors {
                    startDashboardAuthorsContent(shelf.authors, shelf: shelf)
                  }
                }
              }
            }
          }
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .abstandScrollScreenBackground()
    .refreshable {
      await model.refreshStartTabPullToRefresh()
    }
    .onAppear {
      model.refreshEbookContinueReadingShelf()
      if model.offlineHomeUIActive {
        Task { await model.loadStartDashboard() }
      }
    }
  }

  private var startDashboardAllShelvesDisabled: Bool {
    let cats = model.startSettingsCategoryList.map(\.category)
    let basis = cats.isEmpty ? ABSStartShelfLocalization.settingsCategoryOrder : cats
    return basis.allSatisfy { !model.isStartCategoryEnabled($0) }
  }

  private func startDashboardIsContinueShelf(_ shelf: ABSStartShelfSection) -> Bool {
    shelf.category == "recentlyListened"
  }

  @ViewBuilder
  private func startDashboardContinueListeningSection(_ shelf: ABSStartShelfSection) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: shelf.displayTitle)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(
            ABSStartShelfMergedRow.merged(
              books: shelf.books,
              podcastEpisodes: shelf.podcastEpisodes,
              progress: model.progressByItemId
            )
          ) { row in
            switch row {
            case .book(let book):
              ContinueListeningHeroBookCard(book: book)
            case .podcastEpisode(let episode):
              ContinueListeningHeroPodcastCard(episode: episode)
            }
          }
        }
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.vertical, 2)
      }
      .padding(.horizontal, -AppTheme.Layout.tabPaddingH)
    }
  }

  private func startDashboardUsesCompactLayout(_ shelf: ABSStartShelfSection) -> Bool {
    model.startShelfBookLayout(for: shelf.category) == .compact
  }

  @ViewBuilder
  private func startDashboardSeriesContent(
    _ series: [ABSLibrarySeriesListItem],
    shelf: ABSStartShelfSection
  ) -> some View {
    if startDashboardUsesCompactLayout(shelf) {
      StartShelfSeriesCoverSwipeRow(series: series)
    } else {
      ForEach(series) { item in
        startDashboardSeriesRow(item)
      }
    }
  }

  private func startDashboardSeriesRow(_ series: ABSLibrarySeriesListItem) -> some View {
    Button {
      model.openSeriesDetail(
        seriesId: series.id,
        displayName: series.name,
        numBooks: series.books?.count)
    } label: {
      let bookId = model.browseRepresentativeBookItemId(from: series.books)
      BrowseEntityRowCard(
        title: series.name,
        detailLabel: "Books",
        detailValue: browseEntityBooksCountLine(count: series.books?.count),
        cacheItemId: bookId ?? "series-ph:\(series.id)",
        coverURL: bookId.flatMap { model.coverURL(for: $0) }
      )
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func startDashboardAuthorsContent(
    _ authors: [ABSAuthorShelfEntity],
    shelf: ABSStartShelfSection
  ) -> some View {
    if startDashboardUsesCompactLayout(shelf) {
      StartShelfAuthorCoverSwipeRow(authors: authors)
    } else {
      ForEach(authors) { author in
        startDashboardAuthorRow(author)
      }
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

  @ViewBuilder
  private var startDashboardEmptyState: some View {
    if startDashboardAllShelvesDisabled {
      ContentUnavailableView(
        "All shelves are off",
        systemImage: "gearshape.2",
        description: Text("Open Settings to turn home shelves back on.")
      )
    } else {
      ContentUnavailableView(
        "No personalized content",
        systemImage: "books.vertical",
        description: Text("Personalized shelves appear here when your server provides them.")
      )
    }
  }

  private var startDashboardOfflineOnlyEmptyState: some View {
    ContentUnavailableView(
      "No Downloads",
      systemImage: "arrow.down.circle",
      description: Text("Pull to refresh once the server is reachable again.")
    )
  }
}

// MARK: - Library search results

private struct SearchTabView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    let q = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    ScrollView {
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
          ForEach(model.searchBooks) { book in
            BookRowCard(book: book, model: model)
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
            let bookId = model.browseRepresentativeBookItemId(from: s.books)
            searchNavRow(
              title: s.name,
              detailLabel: "Books",
              detailValue: (s.books?.count).map { "\($0)" },
              cacheItemId: bookId ?? "series-ph:\(s.id)",
              coverURL: bookId.flatMap { model.coverURL(for: $0) }
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
              model.applyTagFilter(tagName: t.name)
            }
          }
        }
        searchSection(title: "Genres", isEmpty: model.searchGenres.isEmpty) {
          ForEach(model.searchGenres) { g in
            searchNavRow(
              title: g.name, detailLabel: "Books", detailValue: g.numItems.map { "\($0)" }
            ) {
              model.applyGenreFilter(genreName: g.name)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .abstandScrollScreenBackground()
    .refreshable {
      await model.refreshBooksSearchResults()
    }
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

private extension SearchTabView {
  @ViewBuilder
  func searchNavRow(
    title: String,
    detailLabel: String = "Books",
    detailValue: String? = nil,
    cacheItemId: String = "",
    coverURL: URL? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      BrowseEntityRowCard(
        title: title,
        detailLabel: detailLabel,
        detailValue: detailValue,
        cacheItemId: cacheItemId.isEmpty ? "search:\(title)" : cacheItemId,
        coverURL: coverURL
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Books tab sort (eigenes Toolbar-Item, Reload entkoppelt)

struct BooksCatalogSortToolbarMenu: View, Equatable {
  var sortField: CatalogSortField
  var sortDescending: Bool
  var onSortFieldChange: (CatalogSortField) -> Void
  var onSortDescendingChange: (Bool) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sortField == rhs.sortField && lhs.sortDescending == rhs.sortDescending
  }

  var body: some View {
    Menu {
      Picker("Sort by", selection: sortFieldBinding) {
        ForEach(CatalogSortField.allCases) { f in
          Text(f.menuTitle).tag(f)
        }
      }
      if sortField != .random {
        Picker("Order", selection: sortDescendingBinding) {
          Label("Ascending", systemImage: "arrow.up").tag(false)
          Label("Descending", systemImage: "arrow.down").tag(true)
        }
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }

  private var sortFieldBinding: Binding<CatalogSortField> {
    Binding(get: { sortField }, set: onSortFieldChange)
  }

  private var sortDescendingBinding: Binding<Bool> {
    Binding(get: { sortDescending }, set: onSortDescendingChange)
  }
}

struct BrowseAuthorsSortToolbarMenu: View, Equatable {
  var sortField: BooksBrowseAuthorsSortField
  var sortDescending: Bool
  var onSortFieldChange: (BooksBrowseAuthorsSortField) -> Void
  var onSortDescendingChange: (Bool) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sortField == rhs.sortField && lhs.sortDescending == rhs.sortDescending
  }

  var body: some View {
    Menu {
      Picker("Sort by", selection: sortFieldBinding) {
        ForEach(BooksBrowseAuthorsSortField.allCases) { f in
          Text(f.menuTitle).tag(f)
        }
      }
      Picker("Order", selection: sortDescendingBinding) {
        Label("Ascending", systemImage: "arrow.up").tag(false)
        Label("Descending", systemImage: "arrow.down").tag(true)
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }

  private var sortFieldBinding: Binding<BooksBrowseAuthorsSortField> {
    Binding(get: { sortField }, set: onSortFieldChange)
  }

  private var sortDescendingBinding: Binding<Bool> {
    Binding(get: { sortDescending }, set: onSortDescendingChange)
  }
}

struct BrowseNarratorsSortToolbarMenu: View, Equatable {
  var sortField: BooksBrowseNarratorsSortField
  var sortDescending: Bool
  var onSortFieldChange: (BooksBrowseNarratorsSortField) -> Void
  var onSortDescendingChange: (Bool) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sortField == rhs.sortField && lhs.sortDescending == rhs.sortDescending
  }

  var body: some View {
    Menu {
      Picker("Sort by", selection: sortFieldBinding) {
        ForEach(BooksBrowseNarratorsSortField.allCases) { f in
          Text(f.menuTitle).tag(f)
        }
      }
      Picker("Order", selection: sortDescendingBinding) {
        Label("Ascending", systemImage: "arrow.up").tag(false)
        Label("Descending", systemImage: "arrow.down").tag(true)
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }

  private var sortFieldBinding: Binding<BooksBrowseNarratorsSortField> {
    Binding(get: { sortField }, set: onSortFieldChange)
  }

  private var sortDescendingBinding: Binding<Bool> {
    Binding(get: { sortDescending }, set: onSortDescendingChange)
  }
}

struct BrowseSeriesSortToolbarMenu: View, Equatable {
  var sortField: BooksBrowseSeriesSortField
  var sortDescending: Bool
  var onSortFieldChange: (BooksBrowseSeriesSortField) -> Void
  var onSortDescendingChange: (Bool) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sortField == rhs.sortField && lhs.sortDescending == rhs.sortDescending
  }

  var body: some View {
    Menu {
      Picker("Sort by", selection: sortFieldBinding) {
        ForEach(BooksBrowseSeriesSortField.allCases) { f in
          Text(f.menuTitle).tag(f)
        }
      }
      if sortField != .random {
        Picker("Order", selection: sortDescendingBinding) {
          Label("Ascending", systemImage: "arrow.up").tag(false)
          Label("Descending", systemImage: "arrow.down").tag(true)
        }
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }

  private var sortFieldBinding: Binding<BooksBrowseSeriesSortField> {
    Binding(get: { sortField }, set: onSortFieldChange)
  }

  private var sortDescendingBinding: Binding<Bool> {
    Binding(get: { sortDescending }, set: onSortDescendingChange)
  }
}

struct BrowseCollectionsSortToolbarMenu: View, Equatable {
  var sortField: BooksBrowseCollectionsSortField
  var sortDescending: Bool
  var onSortFieldChange: (BooksBrowseCollectionsSortField) -> Void
  var onSortDescendingChange: (Bool) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sortField == rhs.sortField && lhs.sortDescending == rhs.sortDescending
  }

  var body: some View {
    Menu {
      Picker("Sort by", selection: sortFieldBinding) {
        ForEach(BooksBrowseCollectionsSortField.allCases) { f in
          Text(f.menuTitle).tag(f)
        }
      }
      Picker("Order", selection: sortDescendingBinding) {
        Label("Ascending", systemImage: "arrow.up").tag(false)
        Label("Descending", systemImage: "arrow.down").tag(true)
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }

  private var sortFieldBinding: Binding<BooksBrowseCollectionsSortField> {
    Binding(get: { sortField }, set: onSortFieldChange)
  }

  private var sortDescendingBinding: Binding<Bool> {
    Binding(get: { sortDescending }, set: onSortDescendingChange)
  }
}

// MARK: - Podcast catalog sort (eigenes Toolbar-Item, Reload entkoppelt)

struct PodcastCatalogSortToolbarMenu: View, Equatable {
  var sortField: PodcastCatalogSortField
  var sortDescending: Bool
  var onSortFieldChange: (PodcastCatalogSortField) -> Void
  var onSortDescendingChange: (Bool) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sortField == rhs.sortField && lhs.sortDescending == rhs.sortDescending
  }

  var body: some View {
    Menu {
      Picker("Sort by", selection: sortFieldBinding) {
        ForEach(PodcastCatalogSortField.allCases) { f in
          Text(f.menuTitle).tag(f)
        }
      }
      if sortField != .random {
        Picker("Order", selection: sortDescendingBinding) {
          Label("Ascending", systemImage: "arrow.up").tag(false)
          Label("Descending", systemImage: "arrow.down").tag(true)
        }
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }

  private var sortFieldBinding: Binding<PodcastCatalogSortField> {
    Binding(get: { sortField }, set: onSortFieldChange)
  }

  private var sortDescendingBinding: Binding<Bool> {
    Binding(get: { sortDescending }, set: onSortDescendingChange)
  }
}

// MARK: - Podcast show settings sheet

struct PodcastShowSettingsSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let showId: String
  let showTitle: String
  let onRemove: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section("Auto download") {
          PodcastShowAutoDownloadSettingsContent(showId: showId)
        }

        if model.isServerAdmin {
          Section {
            Button {
              Task { await model.checkAndDownloadNewPodcastEpisodes(showId: showId) }
            } label: {
              HStack {
                Text("Check & download new episodes")
                Spacer()
                if model.podcastCheckNewInProgressShowId == showId {
                  ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.accent)
                }
              }
            }
            .disabled(
              !model.isNetworkReachable || model.podcastCheckNewInProgressShowId == showId
            )
          }
        }

        Section {
          Button("Unsubscribe", role: .destructive) {
            dismiss()
            onRemove()
          }
          .disabled(!model.isNetworkReachable)
        }
      }
      .abstandScrollScreenBackground(ignoreSafeArea: true)
      .navigationTitle(showTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .tint(AppTheme.accent)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}

struct PodcastShowAutoDownloadSettingsContent: View {
  @EnvironmentObject private var model: AppModel
  let showId: String

  private var intervalBinding: Binding<PodcastAutoDownloadInterval> {
    Binding(
      get: { model.podcastAutoDownloadInterval },
      set: { interval in
        model.podcastAutoDownloadInterval = interval
        Task { await model.savePodcastAutoDownloadSettings(showId: showId) }
      }
    )
  }

  private var episodesToKeepBinding: Binding<Int> {
    Binding(
      get: { model.podcastMaxEpisodesToKeep },
      set: { value in
        model.podcastMaxEpisodesToKeep = value
        Task { await model.savePodcastAutoDownloadSettings(showId: showId) }
      }
    )
  }

  private var newEpisodesPerCheckBinding: Binding<Int> {
    Binding(
      get: { model.podcastMaxNewEpisodesToDownload },
      set: { value in
        model.podcastMaxNewEpisodesToDownload = value
        Task { await model.savePodcastAutoDownloadSettings(showId: showId) }
      }
    )
  }

  var body: some View {
    Group {
      if model.podcastAutoDownloadSettingsShowId != showId {
        ProgressView()
          .controlSize(.small)
          .tint(AppTheme.accent)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 8)
      } else {
        Toggle(
          "Download new episodes automatically",
          isOn: Binding(
            get: { model.podcastAutoDownloadEnabled },
            set: { enabled in
              model.podcastAutoDownloadEnabled = enabled
              Task { await model.savePodcastAutoDownloadSettings(showId: showId) }
            }
          )
        )
        .tint(AppTheme.accent)
        .disabled(!model.isNetworkReachable || model.podcastAutoDownloadSettingsSaving)

        if model.podcastAutoDownloadEnabled {
          Picker("Interval", selection: intervalBinding) {
            ForEach(PodcastAutoDownloadInterval.allCases) { interval in
              Text(interval.label).tag(interval)
            }
          }
          .disabled(!model.isNetworkReachable || model.podcastAutoDownloadSettingsSaving)
        }

        if model.podcastAutoDownloadSettingsSaving {
          ProgressView()
            .controlSize(.small)
            .tint(AppTheme.accent)
        }

        PodcastEpisodeLimitStepperRow(
          title: "Max. episodes to keep",
          valueLabel: PodcastAutoDownloadLimitInfo.episodesToKeepLabel(model.podcastMaxEpisodesToKeep),
          value: episodesToKeepBinding,
          range: 0 ... 500
        )
        .disabled(!model.isNetworkReachable || model.podcastAutoDownloadSettingsSaving)

        PodcastEpisodeLimitStepperRow(
          title: "Max. new episodes per check",
          valueLabel: PodcastAutoDownloadLimitInfo.newEpisodesPerCheckLabel(
            model.podcastMaxNewEpisodesToDownload),
          value: newEpisodesPerCheckBinding,
          range: 0 ... 100
        )
        .disabled(!model.isNetworkReachable || model.podcastAutoDownloadSettingsSaving)
      }
    }
    .task(id: showId) {
      if model.podcastAutoDownloadSettingsShowId != showId {
        await model.loadPodcastAutoDownloadSettings(showId: showId)
      }
    }
  }
}

private enum PodcastAutoDownloadLimitInfo {
  static func episodesToKeepLabel(_ value: Int) -> String {
    value == 0 ? "All episodes" : "\(value)"
  }

  static func newEpisodesPerCheckLabel(_ value: Int) -> String {
    value == 0 ? "No limit" : "\(value)"
  }
}

private struct PodcastEpisodeLimitStepperRow: View {
  let title: String
  let valueLabel: String
  @Binding var value: Int
  let range: ClosedRange<Int>

  var body: some View {
    Stepper(value: $value, in: range) {
      HStack {
        Text(title)
        Spacer()
        Text(valueLabel)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
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
    guard let sid = showId, model.podcastSelectedShowId == sid else { return nil }
    return model.podcastFilteredEpisodes.first { draft.matchesLibraryEpisode($0) }
  }

  private var inLibrary: Bool { matchingLibraryEpisode != nil }

  var body: some View {
    let sid = (showId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    VStack(alignment: .leading, spacing: 0) {
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
              .foregroundStyle(AppTheme.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text("Show")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
              Text(showTitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
              Text(publishedCaption)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
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
    .background(AppTheme.card)
    .clipShape(LibraryRowLayout.cardShape)
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
          .foregroundStyle(AppTheme.success)
          .font(.caption)
        Text("In library")
          .font(.caption.weight(.medium))
          .foregroundStyle(AppTheme.textSecondary)
      }
      .frame(minWidth: 88, alignment: .trailing)
    } else if model.podcastRssDraftDownloadCompletedIds.contains(draft.id) {
      Text("Downloading")
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary)
        .lineLimit(1)
        .frame(minWidth: 88, alignment: .trailing)
        .accessibilityLabel("Downloading to server")
    } else if model.podcastRssEpisodeDownloadInProgressDraftIds.contains(draft.id) {
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Downloading")
          .font(.caption.weight(.medium))
          .foregroundStyle(AppTheme.textSecondary)
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
          .foregroundStyle(AppTheme.accent)
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
  let label: String
  let value: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
      let line = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

private struct PodcastEpisodeCollapsedShowLine: View {
  let episode: ABSPodcastEpisodeListItem

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text("Show")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
      Text(episode.showTitle)
        .font(.footnote)
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(2)
        .minimumScaleFactor(0.88)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private func continueHeroAuthorSingleLine(for book: ABSBook) -> String {
  let line = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
  if line.isEmpty || line == "—" { return "—" }
  return line
}

/// Einheitliche Typografie und feste Höhe für Bücher- und Podcast-Continue-Hero-Karten.
private struct ContinueListeningHeroTextBlock<Pill: View>: View {
  let title: String
  let detailLabel: String
  let detailValue: String
  let horizontalInset: CGFloat
  var onTitleTap: () -> Void = {}
  @ViewBuilder private let playPill: () -> Pill

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

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(detailLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppTheme.textSecondary)
          .fixedSize(horizontal: true, vertical: false)
        Text(detailValue)
          .font(.caption)
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: AppTheme.Layout.continueHeroMetadataDetailFixedHeight)
      .padding(.top, AppTheme.Layout.continueHeroMetadataTitleDetailSpacing)

      playPill()
        .padding(.top, AppTheme.Layout.continueHeroMetadataPlayPillTopPadding)
        .padding(.bottom, AppTheme.Layout.continueHeroMetadataExtraBottomPadding)
    }
    .padding(.horizontal, horizontalInset)
    .padding(.top, AppTheme.Layout.continueHeroMetadataVerticalPadding)
    .frame(maxWidth: .infinity)
    .frame(height: AppTheme.Layout.continueHeroMetadataBlockHeight, alignment: .top)
  }
}

/// Oben links auf Continue-Hero-Cover: Medientyp-Pill (Buch oder Podcast).
private struct ContinueListeningHeroTypePill: View {
  enum MediaType {
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
    Image(systemName: type.systemImage)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(.black.opacity(0.48), in: Capsule(style: .continuous))
      .padding(10)
      .allowsHitTesting(false)
  }
}

/// Oben rechts auf Continue-Hero-Cover: fertiger Download oder laufender Download (kein Tap — Cover-Tap bleibt).
private struct ContinueListeningHeroOfflineBadge: View {
  @EnvironmentObject private var model: AppModel
  let storageId: String

  var body: some View {
    Group {
      if model.downloadedItemIds.contains(storageId) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.title3)
          .foregroundStyle(AppTheme.accent)
          .shadow(color: .black.opacity(0.55), radius: 1.5, y: 1)
          .accessibilityLabel("Lokal gespeichert")
      } else if model.downloads.activeItemId == storageId {
        ProgressView(value: model.downloads.progress)
          .progressViewStyle(.circular)
          .tint(.white)
          .scaleEffect(0.82)
          .frame(width: 26, height: 26)
          .background(Circle().fill(.black.opacity(0.42)))
          .accessibilityLabel("Wird heruntergeladen")
      }
    }
    .padding(10)
    .allowsHitTesting(false)
  }
}

// MARK: - Podcast episode row

struct PodcastEpisodeRowCard: View {
  let episode: ABSPodcastEpisodeListItem
  let model: AppModel

  @StateObject private var live: LibraryPodcastEpisodeRowLiveState
  @State private var showDetail = false

  init(episode: ABSPodcastEpisodeListItem, model: AppModel) {
    self.episode = episode
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
    LibraryRowLayout.libraryRowCardChrome(
      showsBottomProgressBar: showsBottomProgressBar,
      progressValue: bottomProgressValue,
      openDetails: { showDetail = true }
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
              .background(Color(white: 0.38, opacity: 0.88))
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
            HStack(spacing: 8) {
              Text(formatPlaybackTime(resolvedTotalDurationSeconds))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
              if prog?.isFinished == true {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(AppTheme.success)
                  .font(.caption)
              }
              podcastDownloadStatusIcon
              Spacer(minLength: 0)
            }
          }
          .padding(.trailing, 4)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityHint("Opens episode details. Play button starts playback.")
    .navigationDestination(isPresented: $showDetail) {
      PodcastEpisodeDetailView(episode: episode)
    }
  }

  @ViewBuilder
  private var podcastDownloadStatusIcon: some View {
    if live.isDownloaded {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(AppTheme.accent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if live.isDownloading {
      ProgressView(value: live.downloadProgress)
        .frame(width: 36)
        .tint(AppTheme.accent)
        .accessibilityLabel("Downloading")
    }
  }

  @ViewBuilder
  private func podcastEpisodeExpandedBlock(_ d: ABSPodcastEpisodeExpandedDetail) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider().background(AppTheme.textSecondary.opacity(0.2))
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
              .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
            ProgressView(value: live.downloadProgress)
              .tint(AppTheme.accent)
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
              .foregroundStyle(AppTheme.accent)
          }
          .buttonStyle(LibraryCardActionButtonStyle(variant: .downloaded))
          .accessibilityLabel("Remove offline copy")
        } else {
          Button {
            model.startDownloadPodcastEpisode(episode)
          } label: {
            Image(systemName: "arrow.down.circle")
              .font(.callout)
              .foregroundStyle(AppTheme.accent)
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
          .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.textPrimary)
      }
      .buttonStyle(LibraryCardActionButtonStyle(variant: isFinished ? .accent : .neutral))
      .accessibilityLabel(isFinished ? "Mark as not finished" : "Finished")
    }
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.top, 8)
  }

  private func podcastMetaRowHostAuthorFilter(detail: ABSPodcastEpisodeExpandedDetail) -> some View {
    let authors = detail.showAuthors
    let line = detail.episode.authorLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return HStack(alignment: .top, spacing: 10) {
      Text("HOST / AUTHOR")
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      Group {
        if !authors.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(authors, id: \.id) { author in
              Button {
                model.openPodcastSearchFromText(author.name)
              } label: {
                Text(author.name)
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.accent)
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
              .foregroundStyle(AppTheme.accent)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
        } else {
          Text("—")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func podcastMetaRowShowFilter(episode: ABSPodcastEpisodeListItem) -> some View {
    let title = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return HStack(alignment: .top, spacing: 10) {
      Text("SHOW")
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      if title.isEmpty || title == "—" {
        Text("—")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Button {
          model.openPodcastSearchFromText(title)
        } label: {
          Text(title)
            .font(.subheadline)
            .foregroundStyle(AppTheme.accent)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func podcastMetaRow(_ k: String, _ v: String) -> some View {
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

/// Fortschritt für Continue-Hero: rechteckig, bündig links/rechts (kein `ProgressView`-Capsule-Stil).
private struct ContinueHeroSquareEdgeProgress: View {
  var value: Double
  var height: CGFloat
  var trackColor: Color
  var fillColor: Color

  var body: some View {
    GeometryReader { geo in
      let w = max(0, geo.size.width)
      let t = min(1, max(0, value))
      ZStack(alignment: .leading) {
        Rectangle().fill(trackColor)
        Rectangle().fill(fillColor).frame(width: w * t)
      }
    }
    .frame(height: height)
  }
}

// MARK: - Home „Recently added“ (horizontal cover strip)

/// Home-Mini-Cover: 82×82 pt, ohne Padding/Hintergrund (wie Library-Cover-Spalte).
private struct StartShelfMiniCover<Cover: View>: View {
  @ViewBuilder let cover: () -> Cover

  private let side = AppTheme.Layout.libraryRowCoverSide

  var body: some View {
    cover()
      .frame(width: side, height: side)
      .clipShape(
        RoundedRectangle(cornerRadius: AppTheme.Layout.libraryRowCornerRadius, style: .continuous))
  }
}

private struct StartShelfCoverSwipeRow: View {
  let books: [ABSBook]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(books) { book in
          StartShelfCoverTile(book: book)
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.vertical, 2)
    }
    .padding(.horizontal, -AppTheme.Layout.tabPaddingH)
  }
}

private struct StartShelfCoverTile: View {
  @EnvironmentObject private var model: AppModel
  let book: ABSBook
  @State private var showDetail = false

  var body: some View {
    Button {
      showDetail = true
    } label: {
      StartShelfMiniCover {
        CoverImageView(
          url: model.coverURL(for: book.id),
          token: model.token,
          itemId: book.id,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision
        )
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(book.displayTitle)
    .accessibilityHint("Opens book details.")
    .navigationDestination(isPresented: $showDetail) {
      BookDetailView(bookId: book.id)
    }
  }
}

private struct StartShelfAuthorCoverSwipeRow: View {
  let authors: [ABSAuthorShelfEntity]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(authors) { author in
          StartShelfAuthorCoverTile(author: author)
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.vertical, 2)
    }
    .padding(.horizontal, -AppTheme.Layout.tabPaddingH)
  }
}

private struct StartShelfSeriesCoverSwipeRow: View {
  let series: [ABSLibrarySeriesListItem]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(series) { item in
          StartShelfSeriesCoverTile(series: item)
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.vertical, 2)
    }
    .padding(.horizontal, -AppTheme.Layout.tabPaddingH)
  }
}

private struct StartShelfSeriesCoverTile: View {
  @EnvironmentObject private var model: AppModel
  let series: ABSLibrarySeriesListItem

  var body: some View {
    let bookId = model.browseRepresentativeBookItemId(from: series.books)
    let cacheId = bookId ?? "series-ph:\(series.id)"
    return Button {
      model.openSeriesDetail(
        seriesId: series.id,
        displayName: series.name,
        numBooks: series.books?.count)
    } label: {
      StartShelfMiniCover {
        CoverImageView(
          url: bookId.flatMap { model.coverURL(for: $0) },
          token: model.token,
          itemId: cacheId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision
        )
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(series.name)
    .accessibilityHint("Opens series details.")
  }
}

private struct StartShelfAuthorCoverTile: View {
  @EnvironmentObject private var model: AppModel
  let author: ABSAuthorShelfEntity

  var body: some View {
    let cacheId = "author:\(author.id)"
    return Button {
      model.openAuthorDetail(
        authorId: author.id, displayName: author.name, numBooks: author.numBooks)
    } label: {
      StartShelfMiniCover {
        CoverImageView(
          url: author.hasAuthorImage ? model.authorImageURL(authorId: author.id) : nil,
          token: model.token,
          itemId: cacheId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision
        )
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(author.name)
    .accessibilityHint("Opens author details.")
  }
}

// MARK: - Home „Continue listening“ (Hero-Karten)

private struct ContinueListeningHeroBookCard: View {
  @EnvironmentObject private var model: AppModel
  let book: ABSBook
  @State private var tint: Color = AppTheme.card
  @State private var showDetail = false

  private var prog: ABSUserMediaProgress? { model.progressByItemId[book.id] }

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
            ContinueHeroSquareEdgeProgress(
              value: v,
              height: barH,
              trackColor: Color.white.opacity(0.22),
              fillColor: AppTheme.accent
            )
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
      }
      .overlay(alignment: .topTrailing) {
        ContinueListeningHeroOfflineBadge(storageId: book.id)
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
        HStack {
          Button {
            Task { await model.play(book: book) }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "play.fill")
                .font(.caption.weight(.bold))
              Text(playPillRemainingCaption)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white, in: Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Wiedergabe")
          .accessibilityValue("Noch \(playPillRemainingCaption)")
          Spacer(minLength: 0)
        }
      }
    }
    .frame(width: w, height: AppTheme.Layout.continueHeroCardTotalHeight, alignment: .top)
    .background(tint)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous))
    .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
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
  @State private var tint: Color = AppTheme.card
  @State private var showDetail = false

  private var prog: ABSUserMediaProgress? { model.progressByItemId[episode.progressLookupKey] }

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
            ContinueHeroSquareEdgeProgress(
              value: v,
              height: barH,
              trackColor: Color.white.opacity(0.22),
              fillColor: AppTheme.accent
            )
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
      }
      .overlay(alignment: .topTrailing) {
        ContinueListeningHeroOfflineBadge(storageId: model.podcastEpisodeOfflineStorageId(episode))
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
        HStack {
          Button {
            Task { await model.playPodcastEpisode(episode) }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "play.fill")
                .font(.caption.weight(.bold))
              Text(playPillRemainingCaption)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white, in: Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Wiedergabe")
          .accessibilityValue("Noch \(playPillRemainingCaption)")
          Spacer(minLength: 0)
        }
      }
    }
    .frame(width: w, height: AppTheme.Layout.continueHeroCardTotalHeight, alignment: .top)
    .background(tint)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous))
    .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
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

private func browseEntityBooksCountLine(count: Int?) -> String? {
  guard let c = count, c > 0 else { return nil }
  return "\(c)"
}

/// Gleiches Kartenlayout wie `BookRowCard`: Cover 82×82, Titel oben am Cover ausgerichtet.
struct BrowseEntityRowCard: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  let detailLabel: String
  let detailValue: String?
  let cacheItemId: String
  let coverURL: URL?

  var body: some View {
    HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
      LibraryRowLayout.coverSlot {
        CoverImageView(
          url: coverURL,
          token: model.token,
          itemId: cacheItemId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision
        )
      }

      LibraryRowLayout.metadataColumn(showsProgressBar: false) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          LibraryRowCollapsedMetaLine(label: detailLabel, value: detailValue)
        }
      }
    }
    .padding(.leading, 0)
    .background(AppTheme.card)
    .clipShape(LibraryRowLayout.cardShape)
  }
}

// MARK: - Podcast show row

/// Podcast-Sendung in Listen — gleiches Layout wie `BookRowCard` (ohne Play-Badge).
struct PodcastShowRowCard: View {
  @EnvironmentObject private var model: AppModel
  let show: ABSBook
  var showsDownloadStatus = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
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
              .foregroundStyle(AppTheme.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            BookCollapsedAuthorLine(book: show)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
              if let episodes = show.media.numTracks, episodes > 0 {
                Text("\(episodes) episodes")
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(AppTheme.textSecondary)
              } else if show.totalDuration > 0 {
                Text(formatPlaybackTime(show.totalDuration))
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(AppTheme.textSecondary)
              }
              downloadIcon
              Spacer(minLength: 0)
            }
          }
        }
      }
      .padding(.leading, 0)
    }
    .background(AppTheme.card)
    .clipShape(LibraryRowLayout.cardShape)
  }

  @ViewBuilder
  private var downloadIcon: some View {
    if !showsDownloadStatus {
      EmptyView()
    } else if model.downloadedItemIds.contains(show.id) {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(AppTheme.accent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if model.downloads.activeItemId == show.id {
      ProgressView(value: model.downloads.progress)
        .frame(width: 36)
        .tint(AppTheme.accent)
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
      ContinueHeroSquareEdgeProgress(
        value: value,
        height: AppTheme.Layout.libraryRowBottomProgressHeight,
        trackColor: Color.white.opacity(0.14),
        fillColor: AppTheme.accent
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
    showsBottomProgressBar: Bool,
    progressValue: Double,
    openDetails: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: coverSide, alignment: .top)
        .padding(.leading, 0)
    }
    .overlay(alignment: .bottom) {
      bottomProgressOverlay(value: progressValue, visible: showsBottomProgressBar)
        .allowsHitTesting(false)
    }
    .background(AppTheme.card)
    .clipShape(cardShape)
    .contentShape(cardShape)
    .onTapGesture(perform: openDetails)
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

  @ViewBuilder
  static func coverSlot<Cover: View, Overlay: View>(
    @ViewBuilder cover: () -> Cover,
    @ViewBuilder overlay: () -> Overlay = { EmptyView() }
  ) -> some View {
    cover()
      .frame(width: coverSide, height: coverSide)
      .clipShape(coverClipShape)
      .overlay(alignment: .bottomTrailing) {
        overlay()
      }
  }
}

// MARK: - Book row

struct BookRowCard: View {
  let book: ABSBook
  let model: AppModel
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
    showsDownloadStatus: Bool = true
  ) {
    self.book = book
    self.model = model
    self.showEbookBadge = showEbookBadge
    self.opensEbookOnCover = opensEbookOnCover
    self.progressOverride = progressOverride
    self.authorLineOverride = authorLineOverride
    self.showsPlaybackControls = showsPlaybackControls
    self.showsDownloadStatus = showsDownloadStatus
    _live = StateObject(
      wrappedValue: LibraryBookRowLiveState(
        bookId: book.id,
        model: model,
        observesProgress: progressOverride == nil,
        observesDownload: showsDownloadStatus
      )
    )
  }

  private var prog: ABSUserMediaProgress? { progressOverride ?? live.progress }

  private var ebookProgress: Double? {
    opensEbookOnCover ? book.ebookReadProgressFraction() : nil
  }

  private var ebookPages: EbookPageDisplayInfo? {
    opensEbookOnCover ? book.ebookPageDisplayInfo() : nil
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
    LibraryRowLayout.libraryRowCardChrome(
      showsBottomProgressBar: showsBottomProgressBar,
      progressValue: bottomProgressValue,
      openDetails: { showDetail = true }
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
                ? (ebookPages?.metadataLabel ?? book.ebookOpenPillCaption)
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
    .accessibilityHint("Opens book details. Play button starts playback.")
    .navigationDestination(isPresented: $showDetail) {
      BookDetailView(bookId: book.id)
    }
  }

  private var libraryRowCoverWithPlayBadge: some View {
    LibraryRowLayout.coverSlot {
      CoverImageView(
        url: model.coverURL(for: book.id),
        token: model.token,
        itemId: book.id,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision
      )
    } overlay: {
      if showsPlaybackControls {
        if opensEbookOnCover, live.isPreparingEbook {
          ProgressView()
            .controlSize(.small)
            .tint(.white)
            .frame(width: 18, height: 18)
            .background(Color(white: 0.38, opacity: 0.88))
            .clipShape(Circle())
            .padding(4)
        } else {
          Image(systemName: opensEbookOnCover ? "book.closed.fill" : "play.fill")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color(white: 0.38, opacity: 0.88))
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
    HStack(spacing: 8) {
      if opensEbookOnCover {
        if let f = ebookProgress, f >= 0.995 {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(AppTheme.success)
            .font(.caption)
        } else if let pages = ebookPages {
          Text(pages.metadataLabel)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
      } else {
        Text(formatPlaybackTime(book.media.duration ?? 0))
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(AppTheme.textSecondary)
        if prog?.isFinished == true {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(AppTheme.success)
            .font(.caption)
        }
      }
      if !opensEbookOnCover,
        showEbookBadge || book.hasAttachedEbook || book.hasSupplementalEpub
      {
        EpubAvailableBadge()
      }
      downloadIcon
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private var downloadIcon: some View {
    if !showsDownloadStatus {
      EmptyView()
    } else if live.isDownloaded {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(AppTheme.accent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if live.isDownloading {
      ProgressView(value: live.downloadProgress)
        .frame(width: 36)
        .tint(AppTheme.accent)
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
      metaRow("Categories", (m.genres ?? []).joined(separator: ", ").nilIfEmpty ?? "—")
      metaRow(
        "Description",
        absPlainText(fromHTML: m.descriptionPlain ?? m.description).nilIfEmpty ?? "—")

      HStack(spacing: 8) {
        Group {
          if isDownloading {
            ZStack {
              RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
              ProgressView(value: downloadProgress)
                .tint(AppTheme.accent)
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
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .downloaded))
            .accessibilityLabel("Remove offline copy")
          } else {
            Button {
              model.startDownload(book: d)
            } label: {
              Image(systemName: "arrow.down.circle")
                .font(.callout)
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .accent))
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
            .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.textPrimary)
        }
        .buttonStyle(LibraryCardActionButtonStyle(variant: isFinished ? .accent : .neutral))
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
                .foregroundStyle(AppTheme.accent)
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
              .foregroundStyle(AppTheme.accent)
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
                .foregroundStyle(AppTheme.accent)
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
                .foregroundStyle(AppTheme.accent)
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

/// Dunkle Kartenfarbe aus dem Cover-Mittel (wie Mini-Player).
private func coverDominantBackgroundTint(from image: UIImage) -> Color {
  guard let ciImage = CIImage(image: image) else { return AppTheme.background }
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
  else { return AppTheme.background }
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
  let r = CGFloat(bitmap[0]) / 255
  let g = CGFloat(bitmap[1]) / 255
  let b = CGFloat(bitmap[2]) / 255
  let mix: CGFloat = 0.25
  let floor: CGFloat = 0.04
  let nr = min(1, r * mix + floor)
  let ng = min(1, g * mix + floor)
  let nb = min(1, b * mix + floor)
  return Color(red: Double(nr), green: Double(ng), blue: Double(nb))
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
    .tint(AppTheme.accent)
  }
}

private struct ListeningHistoryRow: View {
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
            .foregroundStyle(AppTheme.accent)
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
            .fill(AppTheme.accent.opacity(0.88))
            .frame(width: x1 - x0)
            .offset(x: x0)
        }
      }
      .frame(height: 7)
    }
    .padding(.vertical, 4)
  }
}

private struct BookDetailView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let bookId: String
  @State private var detail: ABSBook?
  @State private var coverTintColor: Color = AppTheme.background
  @State private var chaptersExpanded = false
  @State private var bookmarksExpanded = false
  @State private var sessionsExpanded = false
  @State private var listeningSessions: [ABSListeningSession] = []
  @State private var confirmDiscardListeningProgress = false
  @State private var confirmMarkBookFinished = false
  @State private var confirmMarkBookUnfinished = false

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
        coverSection
        infoSection
        if let d = detail {
          detailActionsAndMeta(book: d)
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
    .background(coverTintColor.ignoresSafeArea())
    .task {
      let loaded = await model.loadBookDetail(id: bookId)
      detail = loaded
      await loadCoverTint()
      listeningSessions = await model.loadBookListeningSessions(
        libraryItemId: bookId, bookMediaId: loaded?.mediaId)
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
        coverTintColor = coverDominantBackgroundTint(from: image)
      }
    } catch {}
  }

  private var coverSection: some View {
    HStack {
      Spacer()
      CoverImageView(
        url: model.coverURL(for: bookId),
        token: model.token,
        itemId: bookId,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision
      )
      .aspectRatio(1, contentMode: .fit)
      .containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
      Spacer()
    }
  }

  private var infoSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(book.displayTitle)
        .font(.title2.weight(.bold))
        .foregroundStyle(AppTheme.textPrimary)
      if !book.displayAuthors.isEmpty && book.displayAuthors != "—" {
        Text(book.displayAuthors)
          .font(.title3)
          .foregroundStyle(AppTheme.textSecondary)
      }
      if let p = prog, !p.isFinished, p.duration > 0 {
        ProgressView(value: min(1, max(0, p.progress)))
          .tint(AppTheme.accent)
          .scaleEffect(x: 1, y: 1.15, anchor: .center)
      }
      HStack(spacing: 8) {
        Text(formatPlaybackTime(book.media.duration ?? 0))
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(AppTheme.textSecondary)
        if prog?.isFinished == true {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(AppTheme.success)
            .font(.caption)
        }
        if book.hasSupplementalEpub {
          EpubAvailableBadge()
        }
        Spacer()
      }
    }
  }

  private func detailActionsAndMeta(book d: ABSBook) -> some View {
    let m = d.media.metadata
    let rowProgress = model.progressByItemId[d.id]
    let isFinished = rowProgress?.isFinished == true
    let canDiscardProgress: Bool = {
      guard let p = rowProgress else { return false }
      if p.isFinished { return true }
      if p.currentTime > 1 { return true }
      if p.duration > 0, p.progress > 0.001 { return true }
      return false
    }()
    let discardEnabled = canDiscardProgress && model.isNetworkReachable
    let markToggleEnabled = model.isNetworkReachable
    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      HStack(spacing: 8) {
        Button {
          Task { await model.play(book: d) }
        } label: {
          HStack {
            Image(systemName: "play.fill")
            Text("Play")
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.black)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(AppTheme.accent)
          .clipShape(RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isPreparingEbook)

        if d.hasReadableAttachedEbook {
          Button {
            Task { await model.openAttachedEbook(for: d) }
          } label: {
            Group {
              if model.isPreparingEbook {
                ProgressView()
                  .tint(.white)
              } else {
                HStack {
                  Image(systemName: "book.closed.fill")
                  Text("Read")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
              }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.success)
            .clipShape(RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous))
          }
          .buttonStyle(.plain)
          .disabled(!model.isNetworkReachable || model.isPreparingEbook)
          .accessibilityLabel("Read eBook")
        }

        Group {
          if model.downloads.activeItemId == d.id {
            ZStack {
              RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
              ProgressView(value: model.downloads.progress)
                .tint(AppTheme.accent)
                .scaleEffect(x: 1, y: 1.1, anchor: .center)
                .padding(.horizontal, 8)
            }
          } else if model.downloadedItemIds.contains(d.id) {
            Button {
              model.removeLocalDownload(bookId: d.id)
            } label: {
              Image(systemName: "arrow.down.circle.badge.xmark")
                .font(.callout)
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .downloaded))
          } else {
            Button {
              model.startDownload(book: d)
            } label: {
              Image(systemName: "arrow.down.circle")
                .font(.callout)
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .accent))
          }
        }
        .frame(maxWidth: .infinity)

        Button {
          confirmDiscardListeningProgress = true
        } label: {
          Image(systemName: "arrow.counterclockwise.circle")
            .font(.callout)
            .foregroundStyle(AppTheme.danger)
        }
        .buttonStyle(LibraryCardActionButtonStyle(variant: .danger))
        .disabled(!discardEnabled)
        .accessibilityLabel("Reset listening progress")

        Button {
          if isFinished {
            confirmMarkBookUnfinished = true
          } else {
            confirmMarkBookFinished = true
          }
        } label: {
          Image(systemName: isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle")
            .font(.callout)
            .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.textPrimary)
        }
        .buttonStyle(LibraryCardActionButtonStyle(variant: isFinished ? .accent : .neutral))
        .disabled(!markToggleEnabled)
        .accessibilityLabel(isFinished ? "Mark as not finished" : "Mark as finished")
      }
      .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)

      Divider().background(AppTheme.textSecondary.opacity(0.2))
      if let authors = m.authors, !authors.isEmpty {
        detailMetaLabeledRow(title: "Author") {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(authors, id: \.id) { author in
              Button {
                model.openAuthorDetail(authorId: author.id, displayName: author.name)
              } label: {
                Text(author.name)
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.accent)
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
            model.openNarratorDetail(narratorName: narrators)
          } label: {
            Text(narrators)
              .font(.subheadline)
              .foregroundStyle(AppTheme.accent)
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
                model.openSeriesDetail(seriesId: s.id, displayName: s.name)
              } label: {
                Text(seriesDisplayLine(for: s))
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.accent)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)
            }
          }
        }
      } else if let line = m.resolvedSeriesDisplay, !line.isEmpty {
        detailMetaRow("Series", line)
      }
      detailMetaRow("Year", m.publishedYear ?? "—")
      detailMetaRow("Publisher", m.publisher ?? "—")
      detailMetaRow("Categories", (m.genres ?? []).joined(separator: ", ").nilIfEmpty ?? "—")
      detailMetaRow(
        "Description",
        absPlainText(fromHTML: m.descriptionPlain ?? m.description).nilIfEmpty ?? "—")
    }
  }

  private func detailMetaLabeledRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(title.uppercased())
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func detailMetaRow(_ k: String, _ v: String) -> some View {
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
          .font(.caption.weight(.bold))
          .foregroundStyle(AppTheme.textSecondary)
          .textCase(.uppercase)
          .tracking(0.6)
      }
      .tint(AppTheme.accent)
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
        .foregroundStyle(AppTheme.success)
        .font(.body)
    case .inProgress:
      Image(systemName: "play.circle.fill")
        .foregroundStyle(AppTheme.accent)
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
            .font(.subheadline.weight(.semibold))
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
          .foregroundStyle(AppTheme.accent)
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

private struct PodcastEpisodeDetailView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let episode: ABSPodcastEpisodeListItem
  @State private var detail: ABSPodcastEpisodeExpandedDetail?
  @State private var coverTintColor: Color = AppTheme.background
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

  private var podcastContinueSecondaryCaption: String {
    guard let p = prog, !p.isFinished else {
      return formatPlaybackTime(resolvedTotalDurationSeconds)
    }
    let total = max(p.duration, resolvedTotalDurationSeconds)
    guard total > 0 else { return formatPlaybackTime(resolvedTotalDurationSeconds) }
    let rem = formatPlaybackTime(max(0, total - p.currentTime))
    let pct = min(100, max(0, Int((p.currentTime / total * 100).rounded())))
    return "\(rem) – \(pct)%"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        coverSection
        infoSection
        if let d = detail {
          detailActionsAndMeta(d)
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .background(coverTintColor.ignoresSafeArea())
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
        coverTintColor = coverDominantBackgroundTint(from: image)
      }
    } catch {}
  }

  private var coverSection: some View {
    HStack {
      Spacer()
      CoverImageView(
        url: model.coverURL(for: episode.libraryItemId),
        token: model.token,
        itemId: episode.libraryItemId,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision
      )
      .aspectRatio(1, contentMode: .fit)
      .containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
      Spacer()
    }
  }

  private var infoSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(episode.episodeTitle)
        .font(.title2.weight(.bold))
        .foregroundStyle(AppTheme.textPrimary)
      Text(episode.showTitle)
        .font(.title3)
        .foregroundStyle(AppTheme.textSecondary)
      if let p = prog, !p.isFinished, p.duration > 0 {
        ProgressView(value: min(1, max(0, p.progress)))
          .tint(AppTheme.accent)
          .scaleEffect(x: 1, y: 1.15, anchor: .center)
      }
      HStack(spacing: 8) {
        Text(podcastContinueSecondaryCaption)
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(AppTheme.textSecondary)
        if prog?.isFinished == true {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(AppTheme.success)
            .font(.caption)
        }
        Spacer()
      }
    }
  }

  private func detailActionsAndMeta(_ d: ABSPodcastEpisodeExpandedDetail) -> some View {
    let rowProgress = model.progressByItemId[episode.progressLookupKey]
    let isFinished = rowProgress?.isFinished == true
    let canDiscardProgress: Bool = {
      guard let p = rowProgress else { return false }
      if p.isFinished { return true }
      if p.currentTime > 1 { return true }
      if p.duration > 0, p.progress > 0.001 { return true }
      return false
    }()
    let discardEnabled = canDiscardProgress && model.isNetworkReachable
    let markToggleEnabled = model.isNetworkReachable
    let sid = model.podcastEpisodeOfflineStorageId(episode)
    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      HStack(spacing: 8) {
        Button {
          Task { await model.playPodcastEpisode(episode) }
        } label: {
          HStack {
            Image(systemName: "play.fill")
            Text("Play")
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.black)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(AppTheme.accent)
          .clipShape(RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous))
        }
        .buttonStyle(.plain)

        Group {
          if model.downloads.activeItemId == sid {
            ZStack {
              RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
              ProgressView(value: model.downloads.progress)
                .tint(AppTheme.accent)
                .scaleEffect(x: 1, y: 1.1, anchor: .center)
                .padding(.horizontal, 8)
            }
          } else if model.downloadedItemIds.contains(sid) {
            Button {
              model.removeLocalDownload(bookId: sid)
            } label: {
              Image(systemName: "arrow.down.circle.badge.xmark")
                .font(.callout)
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .downloaded))
          } else {
            Button {
              model.startDownloadPodcastEpisode(episode)
            } label: {
              Image(systemName: "arrow.down.circle")
                .font(.callout)
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .accent))
          }
        }
        .frame(maxWidth: .infinity)

        Button {
          confirmDiscardEpisodeProgress = true
        } label: {
          Image(systemName: "arrow.counterclockwise.circle")
            .font(.callout)
            .foregroundStyle(AppTheme.danger)
        }
        .buttonStyle(LibraryCardActionButtonStyle(variant: .danger))
        .disabled(!discardEnabled)
        .accessibilityLabel("Reset listening progress")

        Button {
          if isFinished {
            confirmMarkEpisodeUnfinished = true
          } else {
            confirmMarkEpisodeFinished = true
          }
        } label: {
          Image(systemName: isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle")
            .font(.callout)
            .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.textPrimary)
        }
        .buttonStyle(LibraryCardActionButtonStyle(variant: isFinished ? .accent : .neutral))
        .disabled(!markToggleEnabled)
        .accessibilityLabel(isFinished ? "Mark as not finished" : "Mark as finished")
      }
      .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)

      Divider().background(AppTheme.textSecondary.opacity(0.2))
      if let show = model.podcastShows.first(where: { $0.id == episode.libraryItemId }) ?? model.podcastSearchBooks.first(where: { $0.id == episode.libraryItemId }) {
        Button {
          Task {
            await model.selectPodcastShowFilter(show.id)
            dismiss()
          }
        } label: {
          HStack(alignment: .top, spacing: 10) {
            Text("SHOW".uppercased())
              .font(.caption.weight(.bold))
              .foregroundStyle(AppTheme.textSecondary)
              .frame(width: 112, alignment: .leading)
            Text(show.displayTitle)
              .font(.subheadline)
              .foregroundStyle(AppTheme.accent)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .buttonStyle(.plain)
      }
      if !d.showAuthors.isEmpty {
        HStack(alignment: .top, spacing: 10) {
          Text("HOST".uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(width: 112, alignment: .leading)
          VStack(alignment: .leading, spacing: 4) {
            ForEach(d.showAuthors, id: \.id) { author in
              Button {
                model.openPodcastSearchFromText(author.name)
                dismiss()
              } label: {
                Text(author.name)
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.accent)
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

private struct BooksEntityDetailNavigationModifier: ViewModifier {
  @EnvironmentObject private var model: AppModel

  func body(content: Content) -> some View {
    content.navigationDestination(item: $model.booksEntityDetailNav) { nav in
      BooksEntityDetailView(nav: nav)
    }
  }
}

private extension View {
  func booksEntityDetailNavigation() -> some View {
    modifier(BooksEntityDetailNavigationModifier())
  }
}

private struct BooksEntityDetailView: View {
  @EnvironmentObject private var model: AppModel
  let nav: BooksEntityDetailNav
  @State private var headerTintColor: Color = AppTheme.background

  private var showsEntityDescription: Bool {
    nav.kind == .author || nav.kind == .series
  }

  private var bookCountLabel: String? {
    let n = nav.numBooks ?? (model.entityDetailTotal > 0 ? model.entityDetailTotal : nil)
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
    .background(headerTintColor.ignoresSafeArea())
    .navigationTitle(nav.title)
    .navigationBarTitleDisplayMode(.inline)
    .task(id: nav.id) {
      await model.reloadEntityDetail(for: nav, reset: true)
      await loadHeaderTint()
    }
    .refreshable {
      await model.refreshEntityDetail(for: nav)
      await loadHeaderTint()
    }
    .onChange(of: model.entityDetailBooks.count) { _, _ in
      if nav.kind != .author {
        Task { await loadHeaderTint() }
      }
    }
  }

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Spacer()
        entityCover
        Spacer()
      }
      VStack(alignment: .leading, spacing: 6) {
        Text(nav.title)
          .font(.title2.weight(.bold))
          .foregroundStyle(AppTheme.textPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(nav.filterSummaryPrefix)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(AppTheme.accent)
        if let bookCountLabel {
          Text(bookCountLabel)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
        }
      }
    }
  }

  @ViewBuilder
  private var entityCover: some View {
    let side: CGFloat = 160
    if nav.kind == .author, let url = model.authorImageURL(authorId: nav.entityId) {
      CoverImageView(
        url: url,
        token: model.token,
        itemId: "author:\(nav.entityId)",
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision
      )
      .frame(width: side, height: side)
      .clipShape(Circle())
    } else if let url = model.entityDetailCoverURL(for: nav) {
      CoverImageView(
        url: url,
        token: model.token,
        itemId: entityCoverCacheItemId,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision
      )
      .frame(width: side, height: side)
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous)
          .fill(AppTheme.card)
          .frame(width: side, height: side)
        Image(systemName: entityPlaceholderIcon)
          .font(.system(size: 44))
          .foregroundStyle(AppTheme.textSecondary)
      }
    }
  }

  private var entityCoverCacheItemId: String {
    switch nav.kind {
    case .author: return "author:\(nav.entityId)"
    case .series: return "series:\(nav.entityId)"
    case .narrator: return "narrator:\(nav.entityId)"
    }
  }

  private var entityPlaceholderIcon: String {
    switch nav.kind {
    case .author: return "person.crop.circle"
    case .series: return "books.vertical"
    case .narrator: return "waveform"
    }
  }

  @ViewBuilder
  private var entityDescriptionSection: some View {
    if !model.entityDetailMetaReady {
      ProgressView()
        .controlSize(.regular)
        .tint(AppTheme.accent)
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

    if model.entityDetailLoading && isEmpty {
      ProgressView()
        .controlSize(.large)
        .tint(AppTheme.accent)
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
            LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
              ForEach(section.books) { book in
                BookRowCard(book: book, model: model)
              }
            }
          }
        }
        if !standalone.isEmpty {
          VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
            entityDetailSectionHeading(seriesSections.isEmpty ? "Books" : "Other books")
            LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
              ForEach(standalone) { book in
                BookRowCard(book: book, model: model)
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
      if model.entityDetailLoading && model.entityDetailBooks.isEmpty {
        ProgressView()
          .controlSize(.large)
          .tint(AppTheme.accent)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
      } else if model.entityDetailBooks.isEmpty {
        Text("No books found.")
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
      } else {
        LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(model.entityDetailBooks) { book in
            BookRowCard(book: book, model: model)
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
    guard let url = model.entityDetailCoverURL(for: nav)
      ?? (nav.kind == .author ? model.authorImageURL(authorId: nav.entityId) : nil)
    else { return }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let image = UIImage(data: data)
      else { return }
      await MainActor.run {
        headerTintColor = coverDominantBackgroundTint(from: image)
      }
    } catch {}
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
