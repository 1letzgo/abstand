import SwiftUI

struct MainRootView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var nowPlayingSheetPresented = false
  @State private var showSettingsNav = false

  private var shouldShowFloatingPlayerChrome: Bool {
    let p = model.player
    if p.activeBook != nil { return true }
    if model.isRestoringLaunchPlayback { return true }
    if p.showMiniPlayerPlaceholder && p.activeBook == nil { return true }
    return false
  }

  var body: some View {
    TabView(selection: $model.mainTab) {
      Tab(AppModel.MainTab.start.rawValue, systemImage: "house.fill", value: AppModel.MainTab.start) {
        homeTabRoot
      }

      if model.selectedBooksLibrary != nil {
        Tab(AppModel.MainTab.books.rawValue, systemImage: "books.vertical.fill", value: AppModel.MainTab.books) {
          booksTabRoot
        }
      }

      if model.selectedPodcastLibrary != nil {
        Tab(AppModel.MainTab.podcasts.rawValue, systemImage: "mic.fill", value: AppModel.MainTab.podcasts) {
          podcastsTabRoot
        }
      }

      Tab(AppModel.MainTab.search.rawValue, systemImage: "magnifyingglass", value: AppModel.MainTab.search, role: .search) {
        searchTabRoot
      }
    }
    .tint(AppTheme.accent)
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      Group {
        if shouldShowFloatingPlayerChrome && !nowPlayingSheetPresented {
          FloatingNowPlayingBar {
            nowPlayingSheetPresented = true
          }
        }
      }
      .colorScheme(colorScheme)
    }
    .background(AppTheme.background.ignoresSafeArea())
    .sheet(isPresented: $nowPlayingSheetPresented) {
      NowPlayingDetailView()
        .environmentObject(model)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .onChange(of: model.nowPlayingSheetPresentationCounter) { _, _ in
      nowPlayingSheetPresented = true
    }
    .onChange(of: model.player.isPlaying) { _, playing in
      Task {
        if !playing {
          await model.syncProgressToServer()
        }
        await model.loadStartDashboard()
      }
    }
    .onChange(of: model.mainTab) { _, tab in
      if tab == .start, model.startShelves.isEmpty {
        Task { await model.loadStartDashboard() }
      }
      if tab == .search {
        model.scheduleSearch()
      }
    }
    .onChange(of: model.selectedBooksLibrary?.id) { _, _ in
      if model.selectedBooksLibrary == nil && model.mainTab == .books {
        model.mainTab = .start
      }
    }
    .onChange(of: model.selectedPodcastLibrary?.id) { _, _ in
      if model.selectedPodcastLibrary == nil && model.mainTab == .podcasts {
        model.mainTab = .start
      }
    }
  }

  // MARK: - Home tab

  private var homeTabRoot: some View {
    NavigationStack {
      StartDashboardView()
        .navigationTitle(AppModel.MainTab.start.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              showSettingsNav = true
            } label: {
              Image(systemName: "gearshape.fill")
                .foregroundStyle(AppTheme.accent)
            }
          }
        }
        .navigationDestination(isPresented: $showSettingsNav) {
          settingsTabRoot
        }
    }
  }

  // MARK: - Settings tab root

  private var settingsTabRoot: some View {
    AppSettingsRootView()
      .tint(AppTheme.accent)
      .navigationTitle(AppModel.MainTab.settings.rawValue)
      .toolbarTitleDisplayMode(.inline)
  }

  // MARK: - Katalog-Sortierung (Bücher und Podcasts getrennt)

  @ViewBuilder
  private func catalogSortToolbarMenu(
    field: Binding<CatalogSortField>,
    descending: Binding<Bool>
  ) -> some View {
    Menu {
      Picker("Sort by", selection: field) {
        ForEach(CatalogSortField.allCases) { f in
          Text(f.menuTitle).tag(f)
        }
      }
      if field.wrappedValue != .random {
        Picker("Order", selection: descending) {
          Label("Ascending", systemImage: "arrow.up").tag(false)
          Label("Descending", systemImage: "arrow.down").tag(true)
        }
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }

  private var booksCatalogSortToolbarMenu: some View {
    catalogSortToolbarMenu(
      field: Binding(
        get: { model.catalogSortField },
        set: { newValue in
          model.catalogSortField = newValue
          Task { await model.reloadLibrary(reset: true) }
        }
      ),
      descending: Binding(
        get: { model.catalogSortDescending },
        set: { newValue in
          model.catalogSortDescending = newValue
          Task { await model.reloadLibrary(reset: true) }
        }
      )
    )
  }

  private var podcastCatalogSortToolbarMenu: some View {
    catalogSortToolbarMenu(
      field: Binding(
        get: { model.podcastCatalogSortField },
        set: { newValue in
          model.podcastCatalogSortField = newValue
          Task { await model.reloadPodcastLibrary(reset: true) }
        }
      ),
      descending: Binding(
        get: { model.podcastCatalogSortDescending },
        set: { newValue in
          model.podcastCatalogSortDescending = newValue
          Task { await model.reloadPodcastLibrary(reset: true) }
        }
      )
    )
  }

  // MARK: - Books tab

  private var booksTabRoot: some View {
    NavigationStack {
      catalogBookList
        .navigationTitle(AppModel.MainTab.books.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            booksCatalogSortToolbarMenu
          }
        }
    }
  }

  // MARK: - Search tab

  private var searchTabRoot: some View {
    NavigationStack {
      SearchTabView()
        .navigationTitle(AppModel.MainTab.search.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $model.searchText, prompt: "Title, author, series…")
        .onChange(of: model.searchText) { _, _ in model.scheduleSearch() }
        .onSubmit(of: .search) { model.scheduleSearch() }
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

  private var catalogBookList: some View {
    let rows = model.booksForDisplay()
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        if let lib = model.selectedBooksLibrary {
          tabContentSectionTitle(lib.name)
        }
        if model.activeLibraryFilter != nil {
          catalogFilterBanner
        }
        ForEach(rows) { book in
          BookRowCard(book: book)
            .task(id: book.id) {
              await model.loadMoreIfNeeded(currentItemId: book.id)
            }
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .refreshable {
      await model.refreshBooksCatalog()
    }
  }

  // MARK: - Podcasts tab

  private var podcastsTabRoot: some View {
    NavigationStack {
      podcastCatalogScrollView
        .navigationTitle(AppModel.MainTab.podcasts.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            podcastCatalogSortToolbarMenu
          }
        }
    }
  }

  private var podcastCatalogScrollView: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          tabContentSectionTitle("Shows")
          podcastShowsCoverStrip
        }
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          tabContentSectionTitle("Episodes")
          podcastPodcastsTabEpisodesContent
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .refreshable {
      await model.refreshPodcastsTab()
    }
  }

  private var podcastShowsCoverStrip: some View {
    let cover: CGFloat = 68
    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 6) {
        Button {
          Task { await model.selectPodcastShowFilter(nil) }
        } label: {
          VStack(spacing: 6) {
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
              .font(.caption2.weight(.semibold))
              .foregroundStyle(AppTheme.textPrimary)
              .lineLimit(1)
              .frame(width: cover + 8)
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
            VStack(spacing: 6) {
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
                .frame(width: cover + 16)
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, 4)
    }
    .scrollContentBackground(.hidden)
  }

  private var podcastPodcastsTabEpisodesContent: some View {
    let episodes = model.podcastEpisodesForPodcastsTab
    let listLoading =
      (model.podcastSelectedShowId != nil
        && (model.isLoadingPodcastShowEpisodes || model.isLoadingPodcasts))
      || (model.podcastSelectedShowId == nil && model.isLoadingPodcasts && episodes.isEmpty)
    return LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      if listLoading {
        ProgressView()
          .controlSize(.extraLarge)
          .tint(AppTheme.accent)
          .scaleEffect(1.45)
          .padding(.vertical, 56)
          .frame(maxWidth: .infinity)
      }

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
            "No episodes in the list. If everything is marked finished, we backfill from podcast shows—check your network or refresh."
          )
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .padding(.vertical, 8)
        }
      }

      ForEach(episodes, id: \.progressLookupKey) { episode in
        PodcastEpisodeRowCard(episode: episode)
          .task(id: episode.progressLookupKey) {
            await model.loadMorePodcastsIfNeeded(currentItemId: episode.id)
          }
      }
    }
  }
}

/// Kategoriezeile im iOS-Standard-Stil (z. B. „Hörbücher”, Home-Regal-Titel).
private func tabContentSectionTitle(_ title: String) -> some View {
  Text(title)
    .font(.title3)
    .bold()
    .foregroundStyle(AppTheme.textPrimary)
}

// MARK: - Home dashboard

private struct StartDashboardView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
          let hasHomeDownloads =
            !model.downloadedItemIds.isEmpty || model.downloads.activeItemId != nil
          let showStartEmpty =
            model.startShelves.isEmpty && model.startBooks.isEmpty && !hasHomeDownloads
              && model.downloadedTitlesForHome.isEmpty
          if showStartEmpty {
            startDashboardEmptyState
          }
          if hasHomeDownloads {
            VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
              tabContentSectionTitle("Downloaded")
              ForEach(model.downloadedTitlesForHome) { book in
                BookRowCard(book: book)
              }
            }
          }
          ForEach(model.startShelves) { shelf in
            let continueSplit =
              startDashboardIsContinueShelf(shelf) && (shelf.hasBooks || shelf.hasPodcastEpisodes)
            Group {
              if continueSplit {
                VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
                  if shelf.hasBooks || shelf.hasPodcastEpisodes {
                    // Hero-Karten (horizontal scrollbar, kompakter als Vollbreite)
                    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
                      tabContentSectionTitle(shelf.displayTitle)
                      ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
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
                  if shelf.hasAuthors {
                    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
                      tabContentSectionTitle(shelf.displayTitle)
                      ForEach(shelf.authors) { author in
                        startDashboardAuthorRow(author)
                      }
                    }
                  }
                }
              } else {
                // Kompaktes „Listen“-Layout (Zeilen wie Bibliothek)
                VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
                  if shelf.hasBooks || shelf.hasAuthors || shelf.hasPodcastEpisodes {
                    tabContentSectionTitle(shelf.displayTitle)
                  }
                  if shelf.hasBooks {
                    ForEach(shelf.books) { book in
                      BookRowCard(book: book)
                    }
                  }
                  if shelf.hasAuthors {
                    ForEach(shelf.authors) { author in
                      startDashboardAuthorRow(author)
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
      .scrollContentBackground(.hidden)
      .refreshable {
        await model.loadStartDashboard()
        model.refreshDownloadedShelfFromManifests()
      }
  }

  private var startDashboardAllShelvesDisabled: Bool {
    let cats = model.startSettingsCategoryList.map(\.category)
    let basis = cats.isEmpty ? ABSStartShelfLocalization.settingsCategoryOrder : cats
    return basis.allSatisfy { !model.isStartCategoryEnabled($0) }
  }

  private func startDashboardIsContinueShelf(_ shelf: ABSStartShelfSection) -> Bool {
    shelf.category == "recentlyListened" || shelf.category == "itemsInProgressFallback"
  }

  private func startDashboardAuthorRow(_ author: ABSAuthorShelfEntity) -> some View {
    Button {
      model.applyAuthorFilter(authorId: author.id, displayName: author.name)
    } label: {
      LabeledContent {
        Image(systemName: "chevron.right")
          .font(.footnote)
          .foregroundStyle(.tertiary)
      } label: {
        Label(author.name, systemImage: "person.crop.circle")
          .labelStyle(.titleAndIcon)
          .foregroundStyle(AppTheme.textPrimary)
      }
      .padding(14)
      .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius))
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
}

// MARK: - Settings tab

private struct AppSettingsRootView: View {
  @EnvironmentObject private var model: AppModel
  @State private var coverCacheByteCount: Int64 = 0

  private var booksLibraryPickerSelection: Binding<String> {
    Binding(
      get: {
        if model.booksLibraryPreferenceIsNone { return AppModel.libraryPickerNoneTag }
        return model.selectedBooksLibrary?.id ?? AppModel.libraryPickerNoneTag
      },
      set: { newId in
        if newId == AppModel.libraryPickerNoneTag {
          model.clearBooksLibrarySelection()
        } else if let lib = model.sortedBookLibraries.first(where: { $0.id == newId }) {
          model.selectBooksLibrary(lib, navigateToCatalog: true)
          Task { await model.reloadLibrary(reset: true) }
        }
      })
  }

  private var podcastsLibraryPickerSelection: Binding<String> {
    Binding(
      get: {
        if model.podcastsLibraryPreferenceIsNone { return AppModel.libraryPickerNoneTag }
        return model.selectedPodcastLibrary?.id ?? AppModel.libraryPickerNoneTag
      },
      set: { newId in
        if newId == AppModel.libraryPickerNoneTag {
          model.clearPodcastLibrarySelection()
        } else if let lib = model.sortedPodcastLibraries.first(where: { $0.id == newId }) {
          model.selectPodcastLibrary(lib, navigateToCatalog: true)
          Task { await model.reloadPodcastLibrary(reset: true) }
        }
      })
  }

  private var coverCacheSizeLabel: String {
    guard model.coverImageCacheAccountDirectory() != nil else {
      return "Cover art is cached after you sign in."
    }
    if coverCacheByteCount == 0 {
      return "No cover cache in use."
    }
    return ByteCountFormatter.string(fromByteCount: coverCacheByteCount, countStyle: .file)
  }

  private func refreshCoverCacheByteCount() {
    coverCacheByteCount = model.coverImageCacheByteCount()
  }

  var body: some View {
    Form {
      Section("Books library") {
        if model.sortedBookLibraries.isEmpty {
          Text("No book libraries on this server.")
            .foregroundStyle(.secondary)
        } else {
          Picker("Library", selection: booksLibraryPickerSelection) {
            Text("None").tag(AppModel.libraryPickerNoneTag)
            ForEach(model.sortedBookLibraries) { lib in
              Text(lib.name).tag(lib.id)
            }
          }
        }
      }

      Section("Podcasts library") {
        if model.sortedPodcastLibraries.isEmpty {
          Text("No podcast libraries on this server.")
            .foregroundStyle(.secondary)
        } else {
          Picker("Library", selection: podcastsLibraryPickerSelection) {
            Text("None").tag(AppModel.libraryPickerNoneTag)
            ForEach(model.sortedPodcastLibraries) { lib in
              Text(lib.name).tag(lib.id)
            }
          }
        }
      }

      Section("Home shelves") {
        ForEach(model.startSettingsCategoryList, id: \.category) { row in
          Toggle(
            row.label,
            isOn: Binding(
              get: { model.isStartCategoryEnabled(row.category) },
              set: { model.setStartCategoryEnabled(row.category, enabled: $0) }
            )
          )
        }
      }

      Section("Cover") {
        Button {
          model.clearCoverImageCache()
          refreshCoverCacheByteCount()
        } label: {
          LabeledContent {
            Image(systemName: "trash")
              .foregroundStyle(.secondary)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text("Clear cover cache")
              Text(coverCacheSizeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .disabled(model.coverImageCacheAccountDirectory() == nil)
      }

      Section("Account") {
        Button("Log out", role: .destructive) {
          model.logout()
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(AppTheme.background.ignoresSafeArea())
    .tint(AppTheme.accent)
    .onAppear {
      refreshCoverCacheByteCount()
    }
    .onChange(of: model.coverImageCacheRevision) { _, _ in
      refreshCoverCacheByteCount()
    }
  }
}

// MARK: - Library search results

private struct SearchTabView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    let q = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
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
            BookRowCard(book: book)
          }
        }
        searchSection(title: "Authors", isEmpty: model.searchAuthors.isEmpty) {
          ForEach(model.searchAuthors) { a in
            searchNavRow(title: a.name, subtitle: a.numBooks.map { "\($0) titles" }) {
              model.applyAuthorFilter(authorId: a.id, displayName: a.name)
            }
          }
        }
        searchSection(title: "Series", isEmpty: model.searchSeries.isEmpty) {
          ForEach(model.searchSeries) { s in
            searchNavRow(title: s.name, subtitle: nil) {
              model.applySeriesFilter(seriesId: s.id, displayName: s.name)
            }
          }
        }
        searchSection(title: "Narrators", isEmpty: model.searchNarrators.isEmpty) {
          ForEach(model.searchNarrators) { n in
            searchNavRow(title: n.name, subtitle: n.numBooks.map { "\($0) titles" }) {
              model.applyNarratorFilter(narratorName: n.name)
            }
          }
        }
        searchSection(title: "Tags", isEmpty: model.searchTags.isEmpty) {
          ForEach(model.searchTags) { t in
            searchNavRow(title: t.name, subtitle: t.numItems.map { "\($0)" }) {
              model.applyTagFilter(tagName: t.name)
            }
          }
        }
        searchSection(title: "Genres", isEmpty: model.searchGenres.isEmpty) {
          ForEach(model.searchGenres) { g in
            searchNavRow(title: g.name, subtitle: g.numItems.map { "\($0)" }) {
              model.applyGenreFilter(genreName: g.name)
            }
          }
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
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
        tabContentSectionTitle(title)
        content()
      }
    }
  }
}

private extension SearchTabView {
  @ViewBuilder
  func searchNavRow(title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(AppTheme.textSecondary)
          }
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppTheme.textSecondary)
      }
      .padding(14)
      .background(AppTheme.card)
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Podcast episode row

private struct PodcastEpisodeRowCard: View {
  @EnvironmentObject private var model: AppModel
  let episode: ABSPodcastEpisodeListItem
  @State private var showDetail = false

  private var prog: ABSUserMediaProgress? { model.progressByItemId[episode.progressLookupKey] }

  /// `recentEpisode` in „items-in-progress" liefert oft keine Länge; die kommt dann aus `mediaProgress`.
  private var resolvedTotalDurationSeconds: Double {
    if episode.duration > 0 { return episode.duration }
    if let p = prog, p.duration > 0 { return p.duration }
    return 0
  }

  private var podcastRowProgress01: Double? {
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

  private var showsBottomProgressBar: Bool { podcastRowProgress01 != nil }

  private var offlinePodcastEpisodeStorageId: String {
    model.podcastEpisodeOfflineStorageId(episode)
  }

  /// Wie Mini-Player: Restzeit und Prozent bei laufendem Fortschritt, sonst Gesamtdauer.
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
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 10) {
        Button {
          Task { await model.playPodcastEpisode(episode) }
        } label: {
          ZStack(alignment: .bottomTrailing) {
            CoverImageView(
              url: model.coverURL(for: episode.libraryItemId),
              token: model.token,
              itemId: episode.libraryItemId,
              cacheAccount: model.coverImageCacheAccountDirectory(),
              cacheRevision: model.coverImageCacheRevision
            )
            .frame(width: AppTheme.Layout.libraryRowCoverSide, height: AppTheme.Layout.libraryRowCoverSide)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
            Image(systemName: "play.fill")
              .font(.system(size: 7, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 18, height: 18)
              .background(Color(white: 0.38, opacity: 0.88))
              .clipShape(Circle())
              .padding(4)
              .accessibilityHidden(true)
          }
          .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play")
        .accessibilityHint("Starts playback of this episode.")

        ZStack(alignment: .topLeading) {
          VStack(alignment: .leading, spacing: 2) {
            Text(episode.episodeTitle)
              .font(.headline.weight(.semibold))
              .foregroundStyle(AppTheme.textPrimary)
              .lineLimit(2)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text("Show")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
              Text(episode.showTitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture {
            showDetail = true
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .padding(.trailing, 4)

          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              Text(podcastContinueSecondaryCaption)
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
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          .contentShape(Rectangle())
          .onTapGesture {
            showDetail = true
          }
        }
        .frame(minHeight: AppTheme.Layout.libraryRowCoverSide)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Show details")
      }
      .padding(.horizontal, AppTheme.Layout.libraryRowCardInset)
      .padding(.top, AppTheme.Layout.libraryRowCardInset)
      .padding(
        .bottom, showsBottomProgressBar ? 8 : AppTheme.Layout.libraryRowCardInset)

      if let v = podcastRowProgress01 {
        ProgressView(value: v)
          .progressViewStyle(.linear)
          .labelsHidden()
          .tint(AppTheme.accent)
          .frame(maxWidth: .infinity)
          .frame(height: AppTheme.Layout.libraryRowBottomProgressHeight)
      }
    }
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.libraryRowCornerRadius, style: .continuous))
    .navigationDestination(isPresented: $showDetail) {
      PodcastEpisodeDetailView(episode: episode)
    }
  }

  @ViewBuilder
  private var podcastDownloadStatusIcon: some View {
    let sid = offlinePodcastEpisodeStorageId
    if model.downloadedItemIds.contains(sid) {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(AppTheme.accent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if model.downloads.activeItemId == sid {
      ProgressView(value: model.downloads.progress)
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
    let rowProgress = model.progressByItemId[episode.progressLookupKey]
    let isFinished = rowProgress?.isFinished == true
    let sid = model.podcastEpisodeOfflineStorageId(episode)
    return HStack(spacing: 8) {
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
          .frame(maxWidth: .infinity)
          .frame(height: MiniPlayerMetrics.controlMinHeight)
          .accessibilityLabel("Download in progress")
        } else if model.downloadedItemIds.contains(sid) {
          Button {
            model.removeLocalDownload(bookId: sid)
          } label: {
            Image(systemName: "arrow.down.circle.badge.xmark")
              .font(.callout)
              .foregroundStyle(AppTheme.textPrimary)
          }
          .buttonStyle(LibraryCardActionButtonStyle(variant: .neutral))
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
    let pillLeadingPadding: CGFloat = 18
    let pillToProgressSpacing: CGFloat = 12

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
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
      .padding(AppTheme.Layout.libraryRowCardInset)
      .contentShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
      .onTapGesture { showDetail = true }
      .accessibilityLabel(book.displayTitle)
      .accessibilityHint("Informationen öffnen")

      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.55), location: 0),
          .init(color: .black.opacity(0), location: 1),
        ],
        startPoint: .bottom,
        endPoint: .top
      )
      .frame(height: min(120, h * 0.45))
      .frame(maxWidth: .infinity)
      .allowsHitTesting(false)

      VStack(spacing: pillToProgressSpacing) {
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
        .padding(.leading, pillLeadingPadding)
        .padding(.trailing, coverInset)

        Group {
          if let v = heroProgress01 {
            ProgressView(value: v)
              .progressViewStyle(.linear)
              .labelsHidden()
              .tint(AppTheme.accent)
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          } else {
            Color.clear
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          }
        }
      }
    }
    .frame(width: w, height: h)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous))
    .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    .task(id: book.id) { await loadTint() }
    .navigationDestination(isPresented: $showDetail) {
      BookDetailView(bookId: book.id)
    }
  }

  private func loadTint() async {
    guard let url = model.coverURL(for: book.id) else { return }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let image = UIImage(data: data)
      else { return }
      let c = PlaybackController.coverBarTintFromCoverImage(image)
      await MainActor.run { tint = c }
    } catch {}
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
    let pillLeadingPadding: CGFloat = 18
    let pillToProgressSpacing: CGFloat = 12

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
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
      .padding(AppTheme.Layout.libraryRowCardInset)
      .contentShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
      .onTapGesture { showDetail = true }
      .accessibilityLabel(episode.episodeTitle)
      .accessibilityHint("Informationen öffnen")

      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.55), location: 0),
          .init(color: .black.opacity(0), location: 1),
        ],
        startPoint: .bottom,
        endPoint: .top
      )
      .frame(height: min(120, h * 0.45))
      .frame(maxWidth: .infinity)
      .allowsHitTesting(false)

      VStack(spacing: pillToProgressSpacing) {
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
        .padding(.leading, pillLeadingPadding)
        .padding(.trailing, coverInset)

        Group {
          if let v = heroProgress01 {
            ProgressView(value: v)
              .progressViewStyle(.linear)
              .labelsHidden()
              .tint(AppTheme.accent)
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          } else {
            Color.clear
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          }
        }
      }
    }
    .frame(width: w, height: h)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous))
    .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    .task(id: episode.progressLookupKey) { await loadTint() }
    .navigationDestination(isPresented: $showDetail) {
      PodcastEpisodeDetailView(episode: episode)
    }
  }

  private func loadTint() async {
    guard let url = model.coverURL(for: episode.libraryItemId) else { return }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let image = UIImage(data: data)
      else { return }
      let c = PlaybackController.coverBarTintFromCoverImage(image)
      await MainActor.run { tint = c }
    } catch {}
  }
}

// MARK: - Book row

struct BookRowCard: View {
  @EnvironmentObject private var model: AppModel
  let book: ABSBook
  @State private var showDetail = false
  private var prog: ABSUserMediaProgress? { model.progressByItemId[book.id] }

  private var showsBottomProgressBar: Bool {
    guard let p = prog, !p.isFinished, p.duration > 0 else { return false }
    return true
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 10) {
        Button {
          Task { await model.play(book: book) }
        } label: {
          ZStack(alignment: .bottomTrailing) {
            CoverImageView(
              url: model.coverURL(for: book.id),
              token: model.token,
              itemId: book.id,
              cacheAccount: model.coverImageCacheAccountDirectory(),
              cacheRevision: model.coverImageCacheRevision
            )
              .frame(width: AppTheme.Layout.libraryRowCoverSide, height: AppTheme.Layout.libraryRowCoverSide)
              .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
            Image(systemName: "play.fill")
              .font(.system(size: 7, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 18, height: 18)
              .background(Color(white: 0.38, opacity: 0.88))
              .clipShape(Circle())
              .padding(4)
              .accessibilityHidden(true)
          }
          .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play")
        .accessibilityHint("Starts playback of this audiobook.")

        ZStack(alignment: .topLeading) {
          VStack(alignment: .leading, spacing: 2) {
            Text(book.displayTitle)
              .font(.headline.weight(.semibold))
              .foregroundStyle(AppTheme.textPrimary)
              .lineLimit(2)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
              .contentShape(Rectangle())
              .onTapGesture {
                showDetail = true
              }
            collapsedAuthorLine(book: book)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .padding(.trailing, 4)

          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              Text(formatPlaybackTime(book.media.duration ?? 0))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
              if prog?.isFinished == true {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(AppTheme.success)
                  .font(.caption)
              }
              downloadIcon
              Spacer(minLength: 0)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          .contentShape(Rectangle())
          .onTapGesture {
            showDetail = true
          }
        }
        .frame(minHeight: AppTheme.Layout.libraryRowCoverSide)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Show details")
      }
      .padding(.horizontal, AppTheme.Layout.libraryRowCardInset)
      .padding(.top, AppTheme.Layout.libraryRowCardInset)
      .padding(
        .bottom, showsBottomProgressBar ? 8 : AppTheme.Layout.libraryRowCardInset)

      if showsBottomProgressBar, let p = prog, p.duration > 0 {
        ProgressView(value: min(1, max(0, p.progress)))
          .progressViewStyle(.linear)
          .labelsHidden()
          .tint(AppTheme.accent)
          .frame(maxWidth: .infinity)
          .frame(height: AppTheme.Layout.libraryRowBottomProgressHeight)
      }
    }
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.libraryRowCornerRadius, style: .continuous))
    .navigationDestination(isPresented: $showDetail) {
      BookDetailView(bookId: book.id)
    }
  }

  @ViewBuilder
  private var downloadIcon: some View {
    if model.downloadedItemIds.contains(book.id) {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(AppTheme.accent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if model.downloads.activeItemId == book.id {
      ProgressView(value: model.downloads.progress)
        .frame(width: 36)
        .tint(AppTheme.accent)
        .accessibilityLabel("Downloading")
    }
  }

  @ViewBuilder
  private func expandedBlock(_ d: ABSBook) -> some View {
    let m = d.media.metadata
    let rowProgress = model.progressByItemId[d.id]
    let isFinished = rowProgress?.isFinished == true

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
          if model.downloads.activeItemId == d.id {
            ZStack {
              RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
              ProgressView(value: model.downloads.progress)
                .tint(AppTheme.accent)
                .scaleEffect(x: 1, y: 1.1, anchor: .center)
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: MiniPlayerMetrics.controlMinHeight)
            .accessibilityLabel("Download in progress")
          } else if model.downloadedItemIds.contains(d.id) {
            Button {
              model.removeLocalDownload(bookId: d.id)
            } label: {
              Image(systemName: "arrow.down.circle.badge.xmark")
                .font(.callout)
                .foregroundStyle(AppTheme.textPrimary)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .neutral))
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

  @ViewBuilder
  private func collapsedAuthorLine(book: ABSBook) -> some View {
    let m = book.media.metadata
    if let authors = m.authors, !authors.isEmpty {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("Author")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(AppTheme.textSecondary)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          ForEach(Array(authors.enumerated()), id: \.element.id) { idx, author in
            if idx > 0 {
              Text(",")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
            }
            Text(author.name)
              .font(.footnote)
              .foregroundStyle(AppTheme.textPrimary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      let line = book.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("Author")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(AppTheme.textSecondary)
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
  let bookId: String
  @State private var detail: ABSBook?
  @State private var coverTintColor: Color = AppTheme.background
  @State private var chaptersExpanded = false
  @State private var sessionsExpanded = false
  @State private var listeningSessions: [ABSListeningSession] = []

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
        Spacer()
      }
    }
  }

  private func detailActionsAndMeta(book d: ABSBook) -> some View {
    let m = d.media.metadata
    let rowProgress = model.progressByItemId[d.id]
    let isFinished = rowProgress?.isFinished == true
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
                .foregroundStyle(AppTheme.textPrimary)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .neutral))
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
      }
      .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)

      Divider().background(AppTheme.textSecondary.opacity(0.2))
      if let authors = m.authors, !authors.isEmpty {
        detailMetaLabeledRow(title: "Author") {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(authors, id: \.id) { author in
              Button {
                model.applyAuthorFilter(authorId: author.id, displayName: author.name)
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
            model.applyNarratorFilter(narratorName: narrators)
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
                model.applySeriesFilter(seriesId: s.id, displayName: s.name)
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
  let episode: ABSPodcastEpisodeListItem
  @State private var detail: ABSPodcastEpisodeExpandedDetail?
  @State private var coverTintColor: Color = AppTheme.background
  @State private var sessionsExpanded = false
  @State private var listeningSessions: [ABSListeningSession] = []

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
                .foregroundStyle(AppTheme.textPrimary)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .neutral))
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
      }
      .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)

      Divider().background(AppTheme.textSecondary.opacity(0.2))
      if let show = model.podcastShows.first(where: { $0.id == episode.libraryItemId }) ?? model.podcastSearchBooks.first(where: { $0.id == episode.libraryItemId }) {
        Button {
          Task { await model.selectPodcastShowFilter(show.id) }
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

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
