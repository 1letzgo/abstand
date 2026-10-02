import SwiftUI

// Home-Regale (alle außer „Continue listening“): Kompaktkarte — abgewandelte Variante der Kompaktzeile
// (`BookRowCard` / `PodcastEpisodeRowCard`). Gleiche Hülle und gleiches Cover links, aber ohne
// Play-Pille, schmaler (rund 3/4 der Regalbreite) und mit nur einem Ziel: der Detailseite.

// MARK: - Grundaufbau

/// Cover 1:1 links, rechts Titel (eine Zeile), eine Metazeile, unten Laufzeit/Status. Ein Tipp öffnet.
struct HomeCompactCard<Cover: View, Footer: View, Badges: View>: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let title: String
  let subtitleLabel: String
  let subtitle: String
  /// Beendete Titel: Cover und Text zurücknehmen (Status-Icons bleiben voll).
  var contentOpacity: Double = 1
  var showsProgressBar = false
  var progressValue: Double = 0
  let accessibilityHint: String
  @ViewBuilder let cover: () -> Cover
  @ViewBuilder let footer: () -> Footer
  @ViewBuilder let badges: () -> Badges
  let onOpen: () -> Void

  var body: some View {
    let _ = themeRevision
    let palette = model.appearancePalette
    let side = AppTheme.Layout.homeCompactCardCoverSide
    return LibraryRowLayout.libraryRowCardChrome(
      cardColor: palette.card,
      showsBottomProgressBar: showsProgressBar,
      progressValue: progressValue,
      openDetails: onOpen,
      rowHeight: side
    ) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        LibraryRowLayout.coverSlot(coverWidth: side) { cover() }
          .opacity(contentOpacity)

        LibraryRowLayout.metadataColumn(showsProgressBar: showsProgressBar, rowHeight: side) {
          VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
            Text(title)
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .opacity(contentOpacity)
              .frame(maxWidth: .infinity, alignment: .leading)
            LibraryRowCollapsedMetaLine(label: subtitleLabel, value: subtitle, valueLineLimit: 1)
              .opacity(contentOpacity)
            Spacer(minLength: 0)
            LibraryRowLayout.metadataFooter(alignment: .bottom) {
              LibraryRowLayout.footerLeadingSlot { footer() }
                .opacity(contentOpacity)
            } trailing: {
              badges()
            }
          }
          .padding(.trailing, AppTheme.Layout.tightSpacing)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityHint(accessibilityHint)
    .abstandThemeRefresh()
  }
}

// MARK: - Buch

struct HomeBookCompactCard: View {
  let book: ABSBook
  /// Kein `@ObservedObject` — Fortschritt/Download über `LibraryBookRowLiveState`.
  let model: AppModel
  /// eBook-Regale („Continue reading“): Lesefortschritt statt Hörbuch-Laufzeit.
  var usesEbookProgressDisplay = false

  @State private var live: LibraryBookRowLiveState
  @State private var showDetail = false

  private var usesEbookMetrics: Bool { book.isPureEbookLibraryItem || usesEbookProgressDisplay }

  init(book: ABSBook, model: AppModel, usesEbookProgressDisplay: Bool = false) {
    self.model = model
    self.usesEbookProgressDisplay = usesEbookProgressDisplay
    let resolved = model.bookStubEnrichedForListDisplay(book)
    self.book = resolved
    let ebookMetrics = resolved.isPureEbookLibraryItem || usesEbookProgressDisplay
    _live = State(
      wrappedValue: LibraryBookRowLiveState(
        bookId: resolved.id,
        model: model,
        observesProgress: !ebookMetrics,
        observesDownload: true,
        observesEbookProgress: ebookMetrics
      )
    )
  }

  private var prog: ABSUserMediaProgress? { live.progress }

  private var isFinished: Bool {
    if usesEbookMetrics { return (live.ebookProgressFraction ?? 0) >= 0.995 }
    return prog?.isFinished == true
  }

  private var showsProgressBar: Bool {
    if usesEbookMetrics {
      guard let f = live.ebookProgressFraction, f > 0.005, f < 0.995 else { return false }
      return true
    }
    guard let p = prog, !p.isFinished, p.duration > 0 else { return false }
    return true
  }

  private var progressValue: Double {
    if usesEbookMetrics, let f = live.ebookProgressFraction { return min(1, max(0, f)) }
    if let p = prog, p.duration > 0 { return min(1, max(0, p.progress)) }
    return 0
  }

  private var authorLine: String {
    let line = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return line.isEmpty ? "—" : line
  }

  var body: some View {
    HomeCompactCard(
      title: book.displayTitle,
      subtitleLabel: "Author",
      subtitle: authorLine,
      contentOpacity: isFinished ? LibraryRowLayout.finishedContentOpacity : 1,
      showsProgressBar: showsProgressBar,
      progressValue: progressValue,
      accessibilityHint: "Opens book details.",
      cover: {
        LibraryRowLayout.rowCoverImage(
          url: model.coverURL(for: book.id),
          token: model.token,
          itemId: book.id,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
        )
      },
      footer: {
        if usesEbookMetrics {
          if let label = LibraryRowLiveState.ebookProgressLabel(for: live.ebookProgressFraction) {
            footerText(label)
          }
        } else {
          footerText(formatPlaybackTime(book.media.duration ?? 0))
        }
      },
      badges: {
        HomeCompactCardStatusBadges(
          isFinished: isFinished,
          isDownloaded: live.isDownloaded,
          isDownloading: live.isDownloading,
          downloadProgress: live.downloadProgress
        )
      },
      onOpen: { showDetail = true }
    )
    .navigationDestination(isPresented: $showDetail) {
      BookDetailView(bookId: book.id)
    }
  }

  private func footerText(_ text: String) -> some View {
    Text(text)
      .font(.subheadline.monospacedDigit())
      .foregroundStyle(model.appearancePalette.textSecondary)
      .lineLimit(1)
      .minimumScaleFactor(0.85)
  }
}

// MARK: - Podcast-Folge

struct HomeEpisodeCompactCard: View {
  let episode: ABSPodcastEpisodeListItem
  /// Kein `@ObservedObject` — Fortschritt/Download über `LibraryPodcastEpisodeRowLiveState`.
  let model: AppModel

  @State private var live: LibraryPodcastEpisodeRowLiveState
  @State private var showDetail = false

  init(episode: ABSPodcastEpisodeListItem, model: AppModel) {
    self.episode = episode
    self.model = model
    _live = State(
      wrappedValue: LibraryPodcastEpisodeRowLiveState(
        progressLookupKey: episode.progressLookupKey,
        offlineStorageId: model.podcastEpisodeOfflineStorageId(episode),
        model: model
      )
    )
  }

  private var prog: ABSUserMediaProgress? { live.progress }

  /// `recentEpisode` liefert oft keine Länge; die kommt dann aus `mediaProgress`.
  private var totalDurationSeconds: Double {
    if episode.duration > 0 { return episode.duration }
    if let p = prog, p.duration > 0 { return p.duration }
    return 0
  }

  private var isFinished: Bool { prog?.isFinished == true }

  private var showsProgressBar: Bool {
    guard let p = prog, !p.isFinished else { return false }
    return max(p.duration, totalDurationSeconds) > 0
  }

  private var progressValue: Double {
    guard showsProgressBar, let p = prog else { return 0 }
    return min(1, max(0, p.progress))
  }

  var body: some View {
    HomeCompactCard(
      title: episode.episodeTitle,
      subtitleLabel: "Show",
      subtitle: episode.showTitle,
      contentOpacity: isFinished ? LibraryRowLayout.finishedContentOpacity : 1,
      showsProgressBar: showsProgressBar,
      progressValue: progressValue,
      accessibilityHint: "Opens episode details.",
      cover: {
        LibraryRowLayout.rowCoverImage(
          url: model.coverURL(for: episode.libraryItemId),
          token: model.token,
          itemId: episode.libraryItemId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forBookId: episode.libraryItemId)
        )
      },
      footer: {
        Text(formatPlaybackTime(totalDurationSeconds))
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(model.appearancePalette.textSecondary)
          .lineLimit(1)
      },
      badges: {
        HomeCompactCardStatusBadges(
          isFinished: isFinished,
          isDownloaded: live.isDownloaded,
          isDownloading: live.isDownloading,
          downloadProgress: live.downloadProgress
        )
      },
      onOpen: { showDetail = true }
    )
    .navigationDestination(isPresented: $showDetail) {
      PodcastEpisodeDetailView(episode: episode)
    }
  }
}

// MARK: - Status-Icons

/// „Fertig“ + Download-Status rechts unten — schlichte Icons wie in der Kompaktzeile.
struct HomeCompactCardStatusBadges: View {
  @EnvironmentObject private var model: AppModel
  let isFinished: Bool
  let isDownloaded: Bool
  let isDownloading: Bool
  let downloadProgress: Double

  var body: some View {
    let color = model.appearancePalette.textSecondary
    HStack(spacing: AppTheme.Layout.compactSpacing) {
      if isFinished {
        Image(systemName: "checkmark.circle.fill")
          .opacity(LibraryRowLayout.finishedContentOpacity)
          .accessibilityLabel("Finished")
      }
      if isDownloaded {
        Image(systemName: "arrow.down.circle.fill")
          .accessibilityLabel("Saved offline")
      } else if isDownloading {
        ProgressView(value: downloadProgress)
          .frame(width: AppTheme.Layout.compactIconButtonSize)
          .tint(color)
          .accessibilityLabel("Downloading")
      }
    }
    .font(.caption)
    .foregroundStyle(color)
    .fixedSize()
  }
}
