import SwiftUI
import UIKit

struct BookDetailView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let bookId: String
  @State private var detail: ABSBook?
  @State private var coverTintColor: Color = AppTheme.background
  @State private var coverImageForTint: UIImage?
  /// Persistierter Cover-Durchschnitts-RGB (`DetailCoverAverageRGBCache`) — Seed beim Öffnen,
  /// bevor das Hero-Cover geladen ist; auch Basis für Theme-Wechsel ohne Bild im Speicher.
  @State private var cachedCoverAverageRGB: (r: Double, g: Double, b: Double)?
  @State private var chaptersExpanded = false
  @State private var bookmarksExpanded = false
  @State private var sessionsExpanded = false
  @State private var descriptionExpanded = false
  @State private var listeningSessions: [ABSListeningSession] = []
  @State private var confirmDiscardListeningProgress = false
  @State private var confirmMarkBookFinished = false
  @State private var confirmMarkBookUnfinished = false
  @State private var confirmMarkEbookAsRead = false
  @State private var confirmResetEbookRead = false
  /// Root: Buch inkl. Dateien vom Server löschen.
  @State private var confirmDeleteBook = false
  /// Blockierendes Popup, bis `deleteFromServer` die Server-Antwort hat.
  @State private var isDeletingBook = false
  /// Autor/Serie/Genre/Sprecher oberhalb des Buch-Details — nicht `libraryEntityDetailNav` (würde Detail poppen).
  @State private var linkedEntityDetailNav: BooksEntityDetailNav?
  /// Admin-Sheets (Match / Kapitel / Metadaten) — ein Item statt drei Bools.
  @State private var presentedAdminSheet: BookDetailAdminSheet?

  private enum BookDetailAdminSheet: String, Identifiable {
    case match
    case chapters
    case edit
    var id: String { rawValue }
  }

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

  /// Der persistierte Cover-Durchschnitt steht bereits vor `.task` zur Verfügung.
  private var resolvedCoverTint: Color {
    let scope = model.coverImageCacheScopeId(for: bookId, tier: .hero)
    let revision = model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
    return CoverDominantTintSeed.resolve(
      account: model.coverImageCacheAccountDirectory(),
      itemId: bookId,
      heroScopeId: scope,
      fallbackScopeId: bookId,
      revision: revision
    )?.tint ?? coverTintColor
  }

  private var prog: ABSUserMediaProgress? { model.progressByItemId[bookId] }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        VStack(spacing: 0) {
          coverSection
          infoSection
          if let d = detail {
            detailBelowPlaySection(book: d)
          }
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .abstandDetailScrollBackground(resolvedCoverTint)
    // Karten in der Farbfamilie des Cover-Tint-Hintergrunds statt neutraler Palette-`card`.
    .detailSectionCardsTinted(fromBackgroundTint: resolvedCoverTint)
    .navigationTitle("")
    .toolbarTitleDisplayMode(.inline)
    .tint(model.appearanceAccentColor)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        bookDetailUtilityToolbarItems(book: detail ?? book)
          // Während Delete nur Aktionen sperren — Nav-Bar bleibt sichtbar (UI-Konzept).
          .disabled(isDeletingBook)
      }
    }
    .onChange(of: model.appearanceThemeRevision) { _, _ in
      applyCoverTintFromStoredImage()
    }
    .task(id: bookId) {
      // Sofort mit zuletzt gecachter Detail-Antwort starten (Beschreibung/Kapitel bleiben sichtbar) —
      // kein Leer-„Reset“ mehr, nur ein stiller Refresh im Hintergrund.
      if detail?.id != bookId {
        detail = model.cachedBookDetail(id: bookId)
        coverImageForTint = nil
        cachedCoverAverageRGB = nil
      }
      seedCoverTintFromLocalCache()
      let loaded = await model.loadBookDetail(id: bookId)
      if let loaded { detail = loaded }
      await loadCoverTint()
      listeningSessions = await model.loadBookListeningSessions(
        libraryItemId: bookId, bookMediaId: loaded?.mediaId ?? book.mediaId)
    }
    .alert("Reset listening progress?", isPresented: $confirmDiscardListeningProgress) {
      Button("Cancel", role: .cancel) {}
      Button("Reset", role: .destructive) {
        Task {
          await model.discardBookProgress(bookId: bookId)
          // Sessions wurden serverseitig mitgelöscht — Liste in der Detail-View nachziehen.
          listeningSessions = await model.loadBookListeningSessions(
            libraryItemId: bookId, bookMediaId: (detail ?? book).mediaId)
        }
      }
    } message: {
      Text("This removes your saved position and listening sessions for this book. You cannot undo this.")
    }
    .alert("Delete book?", isPresented: $confirmDeleteBook) {
      Button("Cancel", role: .cancel) {}
      Button("Delete including file", role: .destructive) {
        isDeletingBook = true
        Task {
          let ok = await model.deleteFromServer(bookId: bookId, hardDelete: true)
          isDeletingBook = false
          if ok { dismiss() }
        }
      }
    } message: {
      Text(
        "\"\((detail ?? book).displayTitle)\" will be deleted on the server including its files. Local downloads will be removed. You cannot undo this."
      )
    }
    .overlay {
      if isDeletingBook {
        deletingBookPopup
      }
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
    .sheet(item: $presentedAdminSheet, onDismiss: reloadDetailAfterEdit) { sheet in
      Group {
        switch sheet {
        case .match:
          MatchMetadataSheet(
            itemId: bookId,
            currentTitle: (detail ?? book).media.metadata.title,
            currentAuthor: (detail ?? book).media.metadata.authorName
          )
        case .chapters:
          ChaptersEditorSheet(
            itemId: bookId,
            currentASIN: (detail ?? book).media.metadata.asin,
            mediaDuration: (detail ?? book).media.duration
          )
        case .edit:
          EditMetadataSheet(
            itemId: bookId,
            metadata: (detail ?? book).media.metadata,
            tags: (detail ?? book).media.tags
          )
        }
      }
      .environmentObject(model)
      .themeAccentFromAppModel(model)
    }
  }

  /// Nach Admin-Edit-Sheets: Detail + Cover-Tint neu laden (Metadaten/Kapitel/Cover wurden ggf. geändert).
  private func reloadDetailAfterEdit() {
    Task {
      let loaded = await model.loadBookDetail(id: bookId)
      if let loaded { detail = loaded }
      coverImageForTint = nil
      await loadCoverTint()
    }
  }

  private func openLinkedEntityDetail(
    kind: BooksEntityDetailNav.Kind,
    entityId: String,
    title: String,
    from book: ABSBook,
    numBooks: Int? = nil
  ) {
    let nav = BooksEntityDetailNav(
      kind: kind,
      entityId: entityId,
      title: title,
      numBooks: numBooks,
      libraryId: entityDetailLibraryId(for: book))
    model.prepareEntityDetail(for: nav)
    linkedEntityDetailNav = nav
  }

  /// eBooks und Hörbücher teilen dieselbe Server-Bibliothek.
  private func entityDetailLibraryId(for book: ABSBook) -> String? {
    if let lid = book.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
      return lid
    }
    return model.selectedBooksLibrary?.id
  }

  private func applyCoverTintFromStoredImage() {
    if let coverImageForTint {
      coverTintColor = coverDominantBackgroundTint(from: coverImageForTint)
    } else if let rgb = cachedCoverAverageRGB {
      // Theme-Wechsel ohne Bild im Speicher: Tint aus dem persistierten RGB mit neuer Palette.
      coverTintColor = coverDominantBackgroundTint(
        fromAverageRed: rgb.r, green: rgb.g, blue: rgb.b)
    } else {
      coverTintColor = AppTheme.background
    }
  }

  /// Zweiter Aufruf desselben Buchs: Tint sofort aus dem beim ersten Besuch persistierten
  /// Cover-Durchschnitts-RGB — kein Warten auf den Hero-Cover-Download.
  private func seedCoverTintFromLocalCache() {
    guard coverImageForTint == nil else { return }
    guard
      let rgb = DetailCoverAverageRGBCache.load(
        account: model.coverImageCacheAccountDirectory(), itemId: bookId)
    else { return }
    cachedCoverAverageRGB = rgb
    coverTintColor = coverDominantBackgroundTint(
      fromAverageRed: rgb.r, green: rgb.g, blue: rgb.b)
  }

  private func loadCoverTint() async {
    let cacheKey = CoverImageCache.cacheKey(
      scopeId: model.coverImageCacheScopeId(for: bookId, tier: .hero),
      revision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
    )
    guard let image = await CoverImageCache.loadHeroImage(
      itemId: cacheKey,
      account: model.coverImageCacheAccountDirectory(),
      coverURL: model.coverURL(for: bookId, tier: .hero),
      token: model.token
    ) else { return }
    await MainActor.run {
      coverImageForTint = image
      coverTintColor = coverDominantBackgroundTint(from: image)
      if let (r, g, b) = coverAverageRGB(from: image) {
        cachedCoverAverageRGB = (Double(r), Double(g), Double(b))
        DetailCoverAverageRGBCache.save(
          account: model.coverImageCacheAccountDirectory(),
          itemId: bookId,
          red: Double(r), green: Double(g), blue: Double(b)
        )
      }
    }
  }

  private var deletingBookPopup: some View {
    let palette = model.appearancePalette
    return ZStack {
      Color.black.opacity(palette.isDarkLike ? 0.55 : 0.35)
        .ignoresSafeArea()
      VStack(spacing: 14) {
        ProgressView()
          .controlSize(.large)
          .tint(model.appearanceAccentColor)
        Text("Deleting book")
          .font(.headline.weight(.semibold))
          .foregroundStyle(palette.textPrimary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 24)
      .background(palette.card, in: RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
      .abstandCardElevation(.standard)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Deleting book")
    }
  }

  @ViewBuilder
  private func bookDetailUtilityToolbarItems(book d: ABSBook) -> some View {
    let rowProgress = model.progressByItemId[d.id]
    let canDiscardListeningProgress: Bool = {
      guard !isPureEbookDetail else { return false }
      guard let p = rowProgress else { return false }
      if p.isFinished { return true }
      if p.currentTime > 1 { return true }
      if p.duration > 0, p.progress > 0.001 { return true }
      return false
    }()
    let canResetEbookProgress: Bool = {
      guard isPureEbookDetail else { return false }
      guard let f = model.ebookDisplayProgressFraction(libraryItemId: d.id) else { return false }
      return f > 0.005
    }()
    let discardEnabled = (canDiscardListeningProgress || canResetEbookProgress) && model.isNetworkReachable
    let storageId = model.downloadStorageIdForLibraryItem(d.id) ?? d.id

    DetailToolbarDownloadItem(
      storageId: storageId,
      onStartDownload: { model.startDownload(book: d) },
      onRemoveDownload: { model.removeLocalDownload(bookId: storageId) }
    )

    DetailToolbarResetProgressItem(enabled: discardEnabled) {
      if isPureEbookDetail {
        confirmResetEbookRead = true
      } else {
        confirmDiscardListeningProgress = true
      }
    }
    .tint(discardEnabled ? AppTheme.danger : AppTheme.textSecondary)

    // Match-Metadaten + Kapitel-Editor: Admin/Root. Löschen inkl. Datei: nur Root.
    if model.isServerAdmin || model.isServerRoot {
      Menu {
        Button {
          presentedAdminSheet = .edit
        } label: {
          Label("Edit Metadata", systemImage: "pencil")
        }
        Button {
          presentedAdminSheet = .match
        } label: {
          Label("Match Metadata", systemImage: "magnifyingglass")
        }
        Button {
          presentedAdminSheet = .chapters
        } label: {
          Label("Edit Chapters", systemImage: "list.bullet.below.rectangle")
        }
        if model.isServerRoot {
          Divider()
          Button(role: .destructive) {
            confirmDeleteBook = true
          } label: {
            Label("Delete book", systemImage: "trash")
          }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .foregroundStyle(AppTheme.textPrimary)
      }
      .accessibilityLabel(String(localized: "More actions", comment: "Accessibility"))
      .disabled(!model.isNetworkReachable)
    }
  }

  private func resolvedEbookFormat(for book: ABSBook) -> ABSEbookFormat? {
    book.readableAttachedEbook?.format
      ?? book.attachedEbookFormats.first
      ?? model.cachedEbookFormat(libraryItemId: book.id)
  }

  private func markAttachedEbookAsRead(book: ABSBook) async {
    guard let format = resolvedEbookFormat(for: book) else { return }
    await model.markEbookAsFinished(libraryItemId: book.id, format: format)
  }

  private func resetAttachedEbookReadProgress(book: ABSBook) async {
    guard let format = resolvedEbookFormat(for: book) else { return }
    await model.resetEbookReadingProgress(libraryItemId: book.id, format: format)
  }

  private var heroBook: ABSBook { detail ?? book }
  private var isPureEbookDetail: Bool { heroBook.isPureEbookLibraryItem }

  private var coverSection: some View {
    let b = heroBook
    let heroScope = model.coverImageCacheScopeId(for: bookId, tier: .hero)
    return DetailHeroCoverFrame(aspectRatio: 1) {
      SquareCoverImageView(
        url: model.coverURL(for: bookId, tier: .hero),
        token: model.token,
        itemId: bookId,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheScopeId: heroScope,
        cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: b.updatedAt)
      )
    }
  }

  private var infoSection: some View {
    let m = heroBook.media.metadata
    return DetailHeroInfoSection(
      title: heroBook.displayTitle,
      subtitle: heroAuthorLinks.isEmpty ? heroAuthorSubtitle : nil,
      authorLinks: heroAuthorLinks,
      onAuthorTap: { id, name in
        openLinkedEntityDetail(
          kind: .author,
          entityId: id,
          title: name,
          from: heroBook)
      },
      tertiaryParts: isPureEbookDetail
        ? [bookDurationLabel(for: heroBook), m.publishedYear ?? ""].filter { $0 != "—" }
        : [bookDurationLabel(for: heroBook), m.publishedYear ?? ""]
    )
  }

  private var heroAuthorLinks: [(id: String, name: String)] {
    let m = heroBook.media.metadata
    if let authors = m.authors, !authors.isEmpty {
      return authors.map { ($0.id, $0.name) }
    }
    if let name = m.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return [(name, name)]
    }
    let line = heroBook.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty, line != "—" else { return [] }
    return [(line, line)]
  }

  private var heroAuthorSubtitle: String? {
    let authors = heroBook.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !authors.isEmpty, authors != "—" else { return nil }
    return authors
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
      let isCurrentInPlayer = model.isActivelyPlayingMedia(libraryItemId: d.id, episodeId: nil)
      let showsPause = isCurrentInPlayer && model.player.isPlaying
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
          kind: showsPause ? .pause : .play,
          progress01: bookPlayProgress01,
          isFinished: isListenFinished,
          primaryEnabled: !model.isPreparingEbook,
          onPrimary: {
            if isCurrentInPlayer && model.player.isPlaying {
              model.player.pause()
            } else if isCurrentInPlayer && !isListenFinished {
              model.player.play()
            } else {
              Task {
                await model.play(
                  book: d,
                  resumeAtOverride: isListenFinished ? 0 : nil,
                  autoPlay: true
                )
              }
            }
          }
        )
      )
    }
    let cachedEbookFormat = model.cachedEbookFormat(libraryItemId: d.id)
    if d.hasReadableAttachedEbook || cachedEbookFormat != nil {
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
          primaryEnabled: !model.isPreparingEbook
            && (model.isNetworkReachable || cachedEbookFormat != nil),
          onPrimary: {
            Task { await model.openAttachedEbook(for: d) }
          }
        )
      )
    }
    return actions
  }

  private func detailBelowPlaySection(book d: ABSBook) -> some View {
    let m = d.media.metadata
    let isListenFinished = prog?.isFinished == true
    let narrators = m.narratorNamesForLibraryBrowseCoverMatch()
    let hasPeople = !narrators.isEmpty
    let hasSeries = hasSeriesContent(metadata: m)
    let publisher = trimmedMetaValue(m.publisher)
    let year = trimmedMetaValue(m.publishedYear)
    let genres = resolvedGenres(metadata: m)
    let tags = resolvedTags(book: d)
    let aboutText = bookAboutText(metadata: m)

    return VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.sectionCardSpacing) {
      DetailHeroActionsBar(
        actions: bookDetailHeroActions(
          for: d,
          isListenFinished: isListenFinished,
          isEbookReadFinished: isEbookReadFinished
        )
      )
      .padding(.top, AppTheme.Layout.detailPlayButtonTopPadding)
      .padding(.bottom, AppTheme.Layout.detailPlayButtonBottomPadding)

      VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.sectionCardSpacing) {
        if let aboutText {
          DetailDetailSectionCard {
            DetailMetaField(title: "Description") {
              DetailMetaExpandableTextBlock(text: aboutText, isExpanded: $descriptionExpanded)
            }
          }
        }

        if d.isPlayableAudiobook, hasPeople {
          DetailDetailSectionCard {
            DetailMetaField(title: narrators.count == 1 ? "Narrator" : "Narrators") {
              VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.linkRowSpacing) {
                ForEach(narrators, id: \.self) { narrator in
                  DetailMetaLink(title: narrator) {
                    openLinkedEntityDetail(
                      kind: .narrator,
                      entityId: narrator,
                      title: narrator,
                      from: d)
                  }
                }
              }
            }
          }
        }

        if hasSeries {
          DetailDetailSectionCard {
            DetailMetaField(title: "Series") {
              detailSeriesContent(book: d, metadata: m)
            }
          }
        }

        if let publishedLine = publishedDisplayLine(publisher: publisher, year: year) {
          DetailDetailSectionCard {
            DetailMetaField(title: "Published") {
              DetailMetaTextBlock(text: publishedLine)
            }
          }
        }

        if !genres.isEmpty {
          DetailDetailSectionCard {
            DetailMetaField(title: "Genres") {
              detailGenresLinks(genres, book: d)
            }
          }
        }

        if !tags.isEmpty {
          DetailDetailSectionCard {
            DetailMetaField(title: "Tags") {
              detailTagsLinks(tags, book: d)
            }
          }
        }

        if d.isPlayableAudiobook {
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
            emptyOfflineText: "No listening history cached yet.",
            onJumpToSessionStart: { session in
              Task { await model.play(book: d, resumeAtOverride: session.startTime, autoPlay: true) }
            }
          )
        }
      }
      .padding(.top, AppTheme.Layout.detailMetaAfterPlaySpacing)
    }
  }

  private func trimmedMetaValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, t != "—" else { return nil }
    return t
  }

  /// „Verlag - Jahr“ für die Published-Zeile.
  private func publishedDisplayLine(publisher: String?, year: String?) -> String? {
    switch (publisher, year) {
    case let (p?, y?): return "\(p) - \(y)"
    case let (p?, nil): return p
    case let (nil, y?): return y
    case (nil, nil): return nil
    }
  }

  private func hasSeriesContent(metadata m: ABSBookMediaMetadata) -> Bool {
    if let seriesList = m.series, !seriesList.isEmpty { return true }
    if let line = m.resolvedSeriesDisplay?.trimmingCharacters(in: .whitespacesAndNewlines),
      !line.isEmpty
    { return true }
    return false
  }

  private func bookAboutText(metadata m: ABSBookMediaMetadata) -> String? {
    absPlainText(fromHTML: m.descriptionPlain ?? m.description).nilIfEmpty
  }

  private func resolvedGenres(metadata m: ABSBookMediaMetadata) -> [String] {
    (m.genres ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func resolvedTags(book: ABSBook) -> [String] {
    (book.media.tags ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  @ViewBuilder
  private func detailSeriesContent(book: ABSBook, metadata m: ABSBookMediaMetadata) -> some View {
    if let seriesList = m.series, !seriesList.isEmpty {
      VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.linkRowSpacing) {
        ForEach(seriesList, id: \.id) { s in
          DetailMetaLink(title: seriesDisplayLine(for: s)) {
            openLinkedEntityDetail(
              kind: .series,
              entityId: s.id,
              title: s.name,
              from: book)
          }
        }
      }
    } else if let line = m.resolvedSeriesDisplay?.trimmingCharacters(in: .whitespacesAndNewlines),
      !line.isEmpty
    {
      DetailMetaTextBlock(text: line)
    }
  }

  @ViewBuilder
  private func detailGenresLinks(_ genres: [String], book: ABSBook) -> some View {
    VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.linkRowSpacing) {
      ForEach(genres, id: \.self) { genre in
        DetailMetaLink(title: genre) {
          openLinkedEntityDetail(
            kind: .genre,
            entityId: genre,
            title: genre,
            from: book,
            numBooks: model.browseGenres.first {
              $0.name.localizedCaseInsensitiveCompare(genre) == .orderedSame
            }?.numBooks)
        }
      }
    }
  }

  @ViewBuilder
  private func detailTagsLinks(_ tags: [String], book: ABSBook) -> some View {
    VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.linkRowSpacing) {
      ForEach(tags, id: \.self) { tag in
        DetailMetaLink(title: tag) {
          openLinkedEntityDetail(
            kind: .tag,
            entityId: tag,
            title: tag,
            from: book,
            numBooks: model.browseTags.first {
              $0.name.localizedCaseInsensitiveCompare(tag) == .orderedSame
            }?.numBooks)
        }
      }
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
      DetailMetaDisclosure(title: "Chapters", isExpanded: $chaptersExpanded) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, ch in
            bookChapterRow(chapter: ch, book: book)
            if idx < chapters.count - 1 {
              Divider().background(AppTheme.textSecondary.opacity(0.15))
            }
          }
        }
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
        .accessibilityLabel("Completed")
    case .inProgress:
      Image(systemName: "play.circle.fill")
        .foregroundStyle(model.appearanceAccentColor)
        .font(.body)
        .accessibilityLabel("In progress")
    case .notStarted:
      Image(systemName: "circle")
        .foregroundStyle(AppTheme.textSecondary.opacity(0.35))
        .font(.body)
        .accessibilityHidden(true)
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
