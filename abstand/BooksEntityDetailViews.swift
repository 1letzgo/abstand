import SwiftUI

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
    case .settings, .podcasts:
      Binding.constant(nil)
    case .search:
      Binding(
        get: { model.searchEntityDetailNav },
        set: { model.searchEntityDetailNav = $0 }
      )
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
