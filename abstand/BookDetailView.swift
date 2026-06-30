import SwiftUI
import UIKit

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
    .task(id: bookId) {
      detail = nil
      coverImageForTint = nil
      let loaded = await model.loadBookDetail(id: bookId)
      detail = loaded
      await loadCoverTint()
      listeningSessions = await model.loadBookListeningSessions(
        libraryItemId: bookId, bookMediaId: loaded?.mediaId ?? book.mediaId)
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
    guard let url = model.coverURL(for: bookId, tier: .hero) else { return }
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
    let b = detail ?? book
    let heroScope = model.coverImageCacheScopeId(for: bookId, tier: .hero)
    let cover = CoverImageView(
      url: model.coverURL(for: bookId, tier: .hero),
      token: model.token,
      itemId: bookId,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheScopeId: heroScope,
      cacheRevision: model.coverImageCacheRevision,
      contentMode: .fit
    )
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))

    return Group {
      if b.isPureEbookLibraryItem {
        cover
          .frame(maxWidth: DetailHeroLayoutMetrics.ebookCoverMaxWidth)
          .frame(maxWidth: .infinity)
      } else {
        cover
          .aspectRatio(1, contentMode: .fit)
          .frame(maxWidth: .infinity)
      }
    }
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
          ForEach(tags, id: \.self) { tag in
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
          ForEach(genres, id: \.self) { genre in
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
          ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, ch in
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
