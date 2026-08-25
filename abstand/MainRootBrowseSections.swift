import SwiftUI

/// Browse-Facet-Sections des Bücher-Tabs (Authors/Narrators/Series/Collections/Genres/Tags) —
/// aus `MainRootView` ausgelagert (Struktur-Plan: Views entschlacken). Bindet nur `model`,
/// kein eigener State; Member bewusst internal, damit die Extension in dieser Datei liegt.
extension MainRootView {
  var booksBrowseOfflineHint: some View {
    Text("Connect to the network to load this list.")
      .font(.subheadline)
      .foregroundStyle(AppTheme.textSecondary)
      .padding(.vertical, 8)
  }

  var booksBrowseCenteredProgress: some View {
    ProgressView()
      .controlSize(.extraLarge)
      .tint(model.appearanceAccentColor)
      .scaleEffect(1.35)
      .padding(.vertical, 48)
      .frame(maxWidth: .infinity)
  }

  func booksBrowseCountLine(count: Int?) -> String? {
    browseEntityBooksCountLine(count: count)
  }

  var booksBrowseAuthorListBody: some View {
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

  var booksBrowseNarratorListBody: some View {
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

  var booksBrowseSeriesListBody: some View {
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

  var booksBrowseCollectionsListBody: some View {
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

  var booksBrowseTagsListBody: some View {
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

  var booksBrowseGenresListBody: some View {
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
  func browseAuthorRow(_ author: ABSLibraryAuthorListItem) -> some View {
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
  func browseSeriesRow(_ series: ABSLibrarySeriesListItem) -> some View {
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
}
