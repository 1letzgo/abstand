import SwiftUI

// MARK: - Unified Search Tab

/// Zentraler Such-Tab (nativ als iOS-26-Such-Icon in der Tabbar, `role: .search` — siehe
/// `MainRootView.onlineTabView`). Ein Suchtext durchsucht Bücher UND Podcasts gleichzeitig —
/// dieselbe Suche für alle Szenarien, unabhängig davon, von wo man in den Tab gewechselt ist.
struct SearchTabRootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
          searchStatusMessage
          BooksSearchBrowseView()
          if model.showPodcastsTab {
            PodcastLibrarySearchResultsView()
          }
        }
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.withinSectionSpacing)
        .padding(
          .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
      }
      .abstandTabScreenChrome()
      .abstandScrollScreenBackground(ignoreSafeArea: true)
      .navigationTitle(AppModel.MainTab.search.rawValue)
      .toolbarTitleDisplayMode(.inline)
      .booksEntityDetailNavigation(for: .search)
      .searchable(text: $model.searchText, prompt: Text("Title, author, show, episode…"))
      .onSubmit(of: .search) { model.scheduleUnifiedSearch() }
      .onChange(of: model.searchText) { _, _ in model.scheduleUnifiedSearch() }
    }
    .tint(model.appearanceAccentColor)
    .onDisappear {
      // Suche zurücksetzen, wenn der Search-Tab verlassen wird.
      model.searchText = ""
      model.podcastLibrarySearchText = ""
      model.clearSearchResults()
      model.clearPodcastLibrarySearchResults()
    }
  }

  private var trimmedQuery: String {
    model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var hasAnyResults: Bool {
    !model.searchBooks.isEmpty || !model.searchAuthors.isEmpty || !model.searchNarrators.isEmpty
      || !model.searchSeries.isEmpty || !model.searchTags.isEmpty || !model.searchGenres.isEmpty
      || !model.podcastLibrarySearchShows.isEmpty || !model.podcastLibrarySearchEpisodes.isEmpty
  }

  @ViewBuilder
  private var searchStatusMessage: some View {
    let q = trimmedQuery
    if q.isEmpty {
      ContentUnavailableView(
        "Search",
        systemImage: "magnifyingglass",
        description: Text("Search your audiobooks and podcasts at once.")
      )
      .frame(maxWidth: .infinity)
      .padding(.vertical, 48)
    } else if q.count < 3 {
      Text("Enter at least three characters.")
        .font(.subheadline)
        .foregroundStyle(AppTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(24)
    } else if model.isLoadingLibrary || model.isLoadingPodcasts, !hasAnyResults {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding()
    } else if !hasAnyResults {
      Text("No results.")
        .font(.subheadline)
        .foregroundStyle(AppTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(24)
    }
  }
}


// MARK: - Library search results

private struct BooksSearchBrowseView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        searchSection(title: "Books", isEmpty: model.searchBooks.isEmpty) {
          if model.libraryBookCardStyle.usesMultiColumnGrid {
            LibraryHeroMultiColumnRows(
              items: model.searchBooks,
              columns: model.libraryBookCardStyle.phoneGridColumns,
              spacing: AppTheme.Layout.withinSectionSpacing
            ) { book in
              LibraryBookListCard(book: book, model: model)
            }
          } else {
            LibraryBookCardsFlow {
              ForEach(model.searchBooks) { book in
                LibraryBookListCard(book: book, model: model)
              }
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
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      if !model.podcastLibrarySearchShows.isEmpty {
        LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          TabContentSectionTitle(title:"Shows")
          ForEach(model.podcastLibrarySearchShows) { show in
            Button {
              model.applyPodcastShowFilterSelection(show.id)
              model.navigateToMedia(.podcasts)
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
