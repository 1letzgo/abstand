import SwiftUI

struct MainRootView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var nowPlayingSheetPresented = false

  private var shouldShowFloatingPlayerChrome: Bool {
    let p = model.player
    if p.activeBook != nil { return true }
    if model.isRestoringLaunchPlayback { return true }
    if p.showMiniPlayerPlaceholder && p.activeBook == nil { return true }
    return false
  }

  var body: some View {
    ZStack(alignment: .top) {
      AppTheme.background.ignoresSafeArea()
      VStack(spacing: 0) {
        TabView(selection: $model.mainTab) {
          StartDashboardView()
            .tabItem {
              Label(AppModel.MainTab.start.rawValue, systemImage: "house.fill")
            }
            .tag(AppModel.MainTab.start)

          if model.selectedBooksLibrary != nil {
            booksTabRoot
              .tabItem {
                Label(AppModel.MainTab.books.rawValue, systemImage: "books.vertical.fill")
              }
              .tag(AppModel.MainTab.books)
          }

          if model.selectedPodcastLibrary != nil {
            podcastsTabRoot
              .tabItem {
                Label(AppModel.MainTab.podcasts.rawValue, systemImage: "mic.fill")
              }
              .tag(AppModel.MainTab.podcasts)
          }

          AppSettingsRootView()
            .tabItem {
              Label(AppModel.MainTab.settings.rawValue, systemImage: "gearshape.fill")
            }
            .tag(AppModel.MainTab.settings)
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
        .background(AppTheme.background)
        .toolbarBackground(AppTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
      }
    }
    .sheet(isPresented: $nowPlayingSheetPresented) {
      NowPlayingDetailView()
        .environmentObject(model)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .onChange(of: model.player.isPlaying) { _, playing in
      if !playing {
        Task {
          await model.syncProgressToServer()
          await model.loadStartDashboard()
        }
      }
    }
    .onChange(of: model.mainTab) { _, tab in
      if tab == .start, model.startShelves.isEmpty {
        Task { await model.loadStartDashboard() }
      }
      if tab == .books {
        model.scheduleSearch()
      }
      if tab == .settings {
        Task { await model.reloadSettingsTab() }
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

  @ViewBuilder
  private var booksCatalogSortControls: some View {
    HStack(spacing: 10) {
      Button {
        model.catalogSortDescending.toggle()
        Task {
          await model.reloadLibrary(reset: true)
          await model.reloadPodcastLibrary(reset: true)
        }
      } label: {
        Label {
          Text(
            model.catalogSortField == .random
              ? "Random"
              : (model.catalogSortDescending ? "Desc" : "Asc"))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        } icon: {
          Image(systemName: model.catalogSortDescending ? "arrow.down.circle" : "arrow.up.circle")
            .foregroundStyle(AppTheme.textPrimary)
        }
        .labelStyle(.titleAndIcon)
      }
      .disabled(model.catalogSortField == .random)
      .buttonStyle(.plain)
      .padding(.vertical, 6)
      .padding(.horizontal, 4)
      .accessibilityLabel(
        model.catalogSortField == .random
          ? "Sort direction (not available for random)"
          : (model.catalogSortDescending ? "Descending" : "Ascending"))
      .accessibilityHint("Toggles between ascending and descending sort order.")

      Menu {
        ForEach(CatalogSortField.allCases) { field in
          Button {
            model.catalogSortField = field
            Task {
              await model.reloadLibrary(reset: true)
              await model.reloadPodcastLibrary(reset: true)
            }
          } label: {
            HStack {
              Text(field.menuTitle)
              Spacer(minLength: 8)
              if model.catalogSortField == field {
                Image(systemName: "checkmark")
              }
            }
          }
        }
      } label: {
        Label {
          Text("Sort")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        } icon: {
          Image(systemName: "arrow.up.arrow.down.circle")
            .foregroundStyle(AppTheme.textPrimary)
        }
        .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.plain)
      .padding(.vertical, 6)
      .padding(.horizontal, 4)
      .accessibilityLabel("Sort order")
    }
  }

  private var booksTabRoot: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: AppTheme.Layout.tabTitleToHeaderBlockSpacing) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          tabRootTitle(AppModel.MainTab.books.rawValue, expandMaxWidth: false)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          Spacer(minLength: 4)
          booksCatalogSortControls
        }
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          tabContentSectionTitle("Search")
          searchFieldRow
          if model.activeLibraryFilter != nil {
            catalogFilterBanner
          }
        }
        .padding(.bottom, AppTheme.Layout.headerToScrollContentSpacing)
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.tabPaddingTop)
      Group {
        if booksShowsSearchResults {
          SearchTabView()
        } else {
          catalogBookList
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(AppTheme.background)
  }

  private var podcastsTabRoot: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: AppTheme.Layout.tabTitleToHeaderBlockSpacing) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          tabRootTitle(AppModel.MainTab.podcasts.rawValue, expandMaxWidth: false)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          Spacer(minLength: 4)
        }
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          tabContentSectionTitle("Shows")
          podcastShowsCoverStrip
        }
        .padding(.bottom, AppTheme.Layout.headerToScrollContentSpacing)
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.tabPaddingTop)

      Group {
        podcastCatalogList
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(AppTheme.background)
  }

  private var podcastCatalogList: some View {
    ScrollView {
      podcastPodcastsTabEpisodesContent
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, 0)
        .padding(
          .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .refreshable {
      await model.refreshPodcastsTab()
    }
  }

  private var booksShowsSearchResults: Bool {
    !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                .lineLimit(2)
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

  private var searchFieldRow: some View {
    HStack {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(AppTheme.textSecondary)
      TextField("Title, author, series…", text: $model.searchText)
        .foregroundStyle(AppTheme.textPrimary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onChange(of: model.searchText) { _, _ in
          model.scheduleSearch()
        }
      if !model.searchText.isEmpty {
        Button {
          model.searchText = ""
          model.clearSearchResults()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(AppTheme.textSecondary)
        }
      }
    }
    .padding(.horizontal, AppTheme.Layout.tabPaddingH)
    .padding(.vertical, 8)
    .background(AppTheme.card)
    .clipShape(Capsule())
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
        ForEach(rows) { book in
          BookRowCard(book: book)
            .task(id: book.id) {
              await model.loadMoreIfNeeded(currentItemId: book.id)
            }
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, 0)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .refreshable {
      await model.refreshBooksCatalog()
    }
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

/// Large heading for main tabs (Home / Books / Podcasts / Settings).
private func tabRootTitle(_ title: String, expandMaxWidth: Bool = true) -> some View {
  Text(title)
    .font(.title)
    .fontWeight(.semibold)
    .foregroundStyle(AppTheme.textPrimary)
    .frame(maxWidth: expandMaxWidth ? .infinity : nil, alignment: .leading)
}

/// Kleine Kategoriezeile wie auf Home (`shelf.displayTitle`).
private func tabContentSectionTitle(_ title: String) -> some View {
  Text(title)
    .font(.caption.weight(.bold))
    .foregroundStyle(AppTheme.textSecondary)
    .textCase(.uppercase)
    .tracking(0.6)
}

// MARK: - Home dashboard

private struct StartDashboardView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      tabRootTitle(AppModel.MainTab.start.rawValue)
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.tabPaddingTop)
        .frame(maxWidth: .infinity, alignment: .leading)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
          let hasHomeDownloads =
            !model.downloadedItemIds.isEmpty || model.downloads.activeItemId != nil
          let showStartEmpty =
            model.startShelves.isEmpty && model.startBooks.isEmpty && !hasHomeDownloads
              && model.downloadedTitlesForHome.isEmpty
          if showStartEmpty {
            startDashboardEmptyVisual
              .frame(maxWidth: .infinity)
              .padding(32)
              .accessibilityElement(children: .ignore)
              .accessibilityLabel(startDashboardEmptyAccessibility)
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
                  if shelf.hasBooks {
                    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
                      tabContentSectionTitle("\(shelf.displayTitle) - Books")
                      ForEach(startDashboardContinueBooksSorted(shelf.books)) { book in
                        BookRowCard(book: book)
                      }
                    }
                  }
                  if shelf.hasPodcastEpisodes {
                    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
                      tabContentSectionTitle("\(shelf.displayTitle) - Podcasts")
                      ForEach(startDashboardContinuePodcastsSorted(shelf.podcastEpisodes), id: \.progressLookupKey) { episode in
                        PodcastEpisodeRowCard(episode: episode)
                      }
                    }
                  }
                  if shelf.hasAuthors {
                    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
                      tabContentSectionTitle(shelf.displayTitle)
                      ForEach(shelf.authors) { author in
                        Button {
                          model.applyAuthorFilter(authorId: author.id, displayName: author.name)
                        } label: {
                          HStack {
                            Text(author.name)
                              .font(.subheadline.weight(.semibold))
                              .foregroundStyle(AppTheme.textPrimary)
                              .multilineTextAlignment(.leading)
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
                  }
                }
              } else {
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
                      Button {
                        model.applyAuthorFilter(authorId: author.id, displayName: author.name)
                      } label: {
                        HStack {
                          Text(author.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.leading)
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
                }
              }
            }
          }
        }
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.headerToScrollContentSpacing)
        .padding(
          .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
      }
      .scrollContentBackground(.hidden)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .refreshable {
        await model.loadStartDashboard()
        model.refreshDownloadedShelfFromManifests()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(AppTheme.background)
  }

  private func startDashboardContinueBooksSorted(_ books: [ABSBook]) -> [ABSBook] {
    books.sorted {
      (model.progressByItemId[$0.id]?.lastUpdate ?? 0) > (model.progressByItemId[$1.id]?.lastUpdate ?? 0)
    }
  }

  private func startDashboardContinuePodcastsSorted(_ episodes: [ABSPodcastEpisodeListItem])
    -> [ABSPodcastEpisodeListItem]
  {
    episodes.sorted {
      (model.progressByItemId[$0.progressLookupKey]?.lastUpdate ?? 0)
        > (model.progressByItemId[$1.progressLookupKey]?.lastUpdate ?? 0)
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

  @ViewBuilder
  private var startDashboardEmptyVisual: some View {
    Image(
      systemName: startDashboardAllShelvesDisabled
        ? "gearshape.2"
        : "books.vertical"
    )
    .font(.system(size: 44, weight: .light))
    .foregroundStyle(AppTheme.textSecondary.opacity(0.45))
    .symbolRenderingMode(.hierarchical)
  }

  private var startDashboardEmptyAccessibility: String {
    if startDashboardAllShelvesDisabled {
      return
        "All home shelves are turned off in Settings. Open Settings to turn shelves back on."
    }
    return
      "Personalized shelves appear here when your server provides them."
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
    VStack(spacing: 0) {
      tabRootTitle(AppModel.MainTab.settings.rawValue)
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.tabPaddingTop)
        .frame(maxWidth: .infinity, alignment: .leading)

      ScrollView {
        VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
          VStack(alignment: .leading, spacing: 10) {
            settingsSheetSectionTitle("Books library")

            if model.sortedBookLibraries.isEmpty {
              Text("No book libraries on this server.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
            } else {
              Picker(selection: booksLibraryPickerSelection) {
                Text("None").tag(AppModel.libraryPickerNoneTag)
                ForEach(model.sortedBookLibraries) { lib in
                  Text(lib.name).tag(lib.id)
                }
              } label: {
                EmptyView()
              }
              .labelsHidden()
              .accessibilityLabel("Books library")
              .pickerStyle(.menu)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(AppTheme.textPrimary)
              .tint(AppTheme.accent)
              .padding(14)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(AppTheme.card)
              .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            settingsSheetSectionTitle("Podcasts library")

            if model.sortedPodcastLibraries.isEmpty {
              Text("No podcast libraries on this server.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
            } else {
              Picker(selection: podcastsLibraryPickerSelection) {
                Text("None").tag(AppModel.libraryPickerNoneTag)
                ForEach(model.sortedPodcastLibraries) { lib in
                  Text(lib.name).tag(lib.id)
                }
              } label: {
                EmptyView()
              }
              .labelsHidden()
              .accessibilityLabel("Podcasts library")
              .pickerStyle(.menu)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(AppTheme.textPrimary)
              .tint(AppTheme.accent)
              .padding(14)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(AppTheme.card)
              .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            settingsSheetSectionTitle("Home shelves")

            VStack(spacing: 0) {
              ForEach(
                Array(model.startSettingsCategoryList.enumerated()),
                id: \.element.category
              ) { index, row in
                Toggle(
                  row.label,
                  isOn: Binding(
                    get: { model.isStartCategoryEnabled(row.category) },
                    set: { model.setStartCategoryEnabled(row.category, enabled: $0) }
                  )
                )
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .tint(AppTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                if index < model.startSettingsCategoryList.count - 1 {
                  Divider()
                    .background(AppTheme.textSecondary.opacity(0.2))
                    .padding(.leading, 14)
                }
              }
            }
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
          }

          VStack(alignment: .leading, spacing: 10) {
            settingsSheetSectionTitle("Cover")

            Button {
              model.clearCoverImageCache()
              refreshCoverCacheByteCount()
            } label: {
              HStack(alignment: .center, spacing: AppTheme.Layout.withinSectionSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                  Text("Clear cover cache")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                  Text(coverCacheSizeLabel)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "trash")
                  .font(.body)
                  .foregroundStyle(AppTheme.textSecondary)
              }
              .padding(14)
              .background(AppTheme.card)
              .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.coverImageCacheAccountDirectory() == nil)
            .opacity(model.coverImageCacheAccountDirectory() == nil ? 0.45 : 1)
          }

          VStack(alignment: .leading, spacing: 10) {
            settingsSheetSectionTitle("Account")
            Button {
              model.logout()
            } label: {
              Text("Log out")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .foregroundStyle(AppTheme.danger)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.headerToScrollContentSpacing)
        .padding(
          .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background)
      }
      .scrollContentBackground(.hidden)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .onAppear {
        refreshCoverCacheByteCount()
      }
      .onChange(of: model.coverImageCacheRevision) { _, _ in
        refreshCoverCacheByteCount()
      }
      .tint(AppTheme.accent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(AppTheme.background)
  }
}

private func settingsSheetSectionTitle(_ title: String) -> some View {
  Text(title)
    .font(.caption.weight(.bold))
    .foregroundStyle(AppTheme.textSecondary)
    .textCase(.uppercase)
    .tracking(0.6)
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
      .padding(.top, 0)
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

  private var expanded: Bool { model.expandedPodcastEpisodeId == episode.progressLookupKey }
  private var detail: ABSPodcastEpisodeExpandedDetail? {
    guard expanded, let d = model.expandedPodcastEpisodeDetail,
      d.episode.progressLookupKey == episode.progressLookupKey
    else { return nil }
    return d
  }

  private var prog: ABSUserMediaProgress? { model.progressByItemId[episode.progressLookupKey] }

  /// `recentEpisode` in „items-in-progress“ liefert oft keine Länge; die kommt dann aus `mediaProgress`.
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
            Task { await model.expandPodcastEpisode(episode) }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .padding(.trailing, 4)

          VStack(alignment: .leading, spacing: 4) {
            if let v = podcastRowProgress01 {
              ProgressView(value: v)
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
              podcastDownloadStatusIcon
              Spacer(minLength: 0)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          .contentShape(Rectangle())
          .onTapGesture {
            Task { await model.expandPodcastEpisode(episode) }
          }
        }
        .frame(minHeight: AppTheme.Layout.libraryRowCoverSide)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(expanded ? "Hide details" : "Show details")
      }
      .padding(AppTheme.Layout.libraryRowCardInset)

      if let d = detail {
        podcastEpisodeExpandedBlock(d)
      }
    }
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.libraryRowCornerRadius, style: .continuous))
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

// MARK: - Book row

struct BookRowCard: View {
  @EnvironmentObject private var model: AppModel
  let book: ABSBook

  private var expanded: Bool { model.expandedItemId == book.id }
  private var detail: ABSBook? { expanded ? (model.expandedDetail ?? book) : book }
  private var prog: ABSUserMediaProgress? { model.progressByItemId[book.id] }

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
                Task { await model.expandItem(book.id) }
              }
            collapsedAuthorLine(book: book)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .padding(.trailing, 4)

          VStack(alignment: .leading, spacing: 4) {
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
              downloadIcon
              Spacer(minLength: 0)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          .contentShape(Rectangle())
          .onTapGesture {
            Task { await model.expandItem(book.id) }
          }
        }
        .frame(minHeight: AppTheme.Layout.libraryRowCoverSide)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(expanded ? "Hide details" : "Show details")
      }
      .padding(AppTheme.Layout.libraryRowCardInset)

      if expanded, let d = detail {
        expandedBlock(d)
      }
    }
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.libraryRowCornerRadius, style: .continuous))
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

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}