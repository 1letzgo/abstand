import SwiftUI

/// Titel + Metadaten unter Continue-Hero-/Library-Cover (ohne Play-Pille).
struct ContinueListeningHeroMetadataBlock: View {
  @EnvironmentObject private var model: AppModel
  @ScaledMetric(relativeTo: .headline) private var titleFixedHeight = AppTheme.Layout.continueHeroMetadataTitleFixedHeight
  @ScaledMetric(relativeTo: .footnote) private var detailFixedHeight = AppTheme.Layout.continueHeroMetadataDetailFixedHeight
  let title: String
  let detailLabel: String
  let detailValue: String
  let horizontalInset: CGFloat
  var onTitleTap: () -> Void = {}
  var includesBottomPadding: Bool = false
  var blockHeight: CGFloat
  /// Cover-Tint der Karte — steuert lesbare Titel-/Author-Farben.
  var cardTint: Color? = nil

  var body: some View {
    let readable = cardTint.map { model.appearancePalette.readableTextOnTintedCard($0) }
    let titleColor = readable?.primary ?? model.appearancePalette.textPrimary
    let labelColor = readable?.secondary
    let valueColor = readable?.primary
    VStack(alignment: .leading, spacing: AppTheme.Layout.continueHeroMetadataTitleDetailSpacing) {
      Text(title)
        .font(.headline.weight(.semibold))
        .foregroundStyle(titleColor)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .minimumScaleFactor(0.85)
        .frame(
          maxWidth: .infinity,
          minHeight: titleFixedHeight,
          maxHeight: titleFixedHeight,
          alignment: .topLeading
        )
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTitleTap() }

      LibraryRowCollapsedMetaLine(
        label: detailLabel,
        value: detailValue,
        valueLineLimit: 1,
        labelColor: labelColor,
        valueColor: valueColor
      )
      .frame(
        maxWidth: .infinity,
        minHeight: detailFixedHeight,
        maxHeight: detailFixedHeight,
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
struct ContinueListeningHeroTextBlock<Pill: View>: View {
  @ScaledMetric(relativeTo: .headline) private var titleFixedHeight = AppTheme.Layout.continueHeroMetadataTitleFixedHeight
  @ScaledMetric(relativeTo: .footnote) private var detailFixedHeight = AppTheme.Layout.continueHeroMetadataDetailFixedHeight
  let title: String
  let detailLabel: String
  let detailValue: String
  let horizontalInset: CGFloat
  var onTitleTap: () -> Void = {}
  var cardTint: Color? = nil
  @ViewBuilder private let playPill: () -> Pill

  private var titleDetailHeight: CGFloat {
    AppTheme.Layout.continueHeroMetadataVerticalPadding
      + titleFixedHeight
      + AppTheme.Layout.continueHeroMetadataTitleDetailSpacing
      + detailFixedHeight
  }

  private var scaledBlockHeight: CGFloat {
    titleDetailHeight
      + AppTheme.Layout.continueHeroMetadataPlayPillTopPadding
      + AppTheme.Layout.continueHeroMetadataPlayPillIntrinsicHeight
      + AppTheme.Layout.continueHeroMetadataExtraBottomPadding
  }

  init(
    title: String,
    detailLabel: String,
    detailValue: String,
    horizontalInset: CGFloat,
    onTitleTap: @escaping () -> Void = {},
    cardTint: Color? = nil,
    @ViewBuilder playPill: @escaping () -> Pill
  ) {
    self.title = title
    self.detailLabel = detailLabel
    self.detailValue = detailValue
    self.horizontalInset = horizontalInset
    self.onTitleTap = onTitleTap
    self.cardTint = cardTint
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
        blockHeight: titleDetailHeight,
        cardTint: cardTint
      )

      playPill()
        .padding(.horizontal, horizontalInset)
        .padding(.top, AppTheme.Layout.continueHeroMetadataPlayPillTopPadding)
        .padding(.bottom, AppTheme.Layout.continueHeroMetadataExtraBottomPadding)
    }
    .frame(maxWidth: .infinity)
    .frame(height: scaledBlockHeight, alignment: .top)
  }
}

/// Gemeinsame Cover-Pill (Typ, Download, Länge) — gleiche Kapsel wie Continue Listening.
struct ContinueListeningHeroCoverPill<Content: View>: View {
  @EnvironmentObject private var model: AppModel
  var allowsHitTesting = false
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .padding(.horizontal, 6)
      .padding(.vertical, 5)
      .background(model.appearancePalette.coverPlayBadgeBackground, in: Capsule(style: .continuous))
      .fixedSize()
      .padding(.vertical, ContinueListeningHeroCoverPillMetrics.verticalInset)
      .padding(.horizontal, ContinueListeningHeroCoverPillMetrics.horizontalInset)
      .allowsHitTesting(allowsHitTesting)
  }
}

enum ContinueListeningHeroCoverPillMetrics {
  static let iconFont = Font.caption2.weight(.semibold)
  static let verticalInset: CGFloat = 8
  static let horizontalInset: CGFloat = 8
}

/// Oben links auf Continue-Hero-Cover: Medientyp-Pill (Buch oder Podcast).
struct ContinueListeningHeroTypePill: View {
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
struct ContinueListeningHeroOfflineBadge: View {
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

struct ContinueListeningHeroBookOfflineBadgeSlot: View {
  var rowLive: LibraryBookRowLiveState

  var body: some View {
    ContinueListeningHeroOfflineBadge(
      isDownloaded: rowLive.isDownloaded,
      isDownloading: rowLive.isDownloading,
      downloadProgress: rowLive.downloadProgress
    )
  }
}

struct ContinueListeningHeroPodcastOfflineBadgeSlot: View {
  var rowLive: LibraryPodcastEpisodeRowLiveState

  var body: some View {
    ContinueListeningHeroOfflineBadge(
      isDownloaded: rowLive.isDownloaded,
      isDownloading: rowLive.isDownloading,
      downloadProgress: rowLive.downloadProgress
    )
  }
}

private struct ContinueCarouselViewportWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

/// Feste Reihenfolge solange sich die `lastUpdate`-Rangfolge nicht ändert
/// (kein Neu-Sortieren bei Fortschritt-Ticks der bereits vordersten Karte).
/// Eine Karte je Reihe über die volle Streifenbreite, einrastend, mit Seitenpunkten darunter.
struct ContinueListeningHeroCarousel: View {
  @EnvironmentObject private var model: AppModel
  let shelf: ABSStartShelfSection

  @State private var rows: [ABSStartShelfMergedRow] = []
  @State private var viewportWidth: CGFloat = 0
  @State private var currentRowID: ABSStartShelfMergedRow.ID?

/// Reihenfolge nach `lastUpdate`, aber nicht bei jedem Fortschritt-Tick.
/// Nur IDs zu beobachten reicht nicht: nach einem Play-Start bleiben dieselben Titel
/// im Regal, die gespielte Karte muss trotzdem nach vorne.
private var orderSignature: String {
  ABSStartShelfMergedRow.merged(
    books: shelf.books,
    podcastEpisodes: shelf.podcastEpisodes,
    progress: model.progressByItemId
  ).map(\.id).joined(separator: "\u{1f}")
}

  private var cardWidth: CGFloat {
    AppTheme.Layout.continueHeroFullWidthCardWidth(forViewportWidth: viewportWidth)
  }

  private var cardTotalHeight: CGFloat {
    AppTheme.Layout.continueHeroCardTotalHeight(forCardWidth: cardWidth)
  }

  var body: some View {
    VStack(spacing: AppTheme.Layout.stackSpacing) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(rows) { row in
            switch row {
            case .book(let book):
              ContinueListeningHeroBookCard(book: book, model: model, cardWidth: cardWidth)
            case .podcastEpisode(let episode):
              ContinueListeningHeroPodcastCard(episode: episode, model: model, cardWidth: cardWidth)
            }
          }
        }
        .scrollTargetLayout()
      }
      .scrollContentBackground(.hidden)
      // Eine Karte je Reihe: der Streifen rastet auf der Karte ein, statt frei auszulaufen.
      .scrollTargetBehavior(.viewAligned)
      .scrollPosition(id: $currentRowID)
      .frame(height: cardTotalHeight)
      .abstandHorizontalScrollRow()

      pageIndicator
    }
    .background {
      GeometryReader { geo in
        Color.clear.preference(key: ContinueCarouselViewportWidthKey.self, value: geo.size.width)
      }
    }
    .onPreferenceChange(ContinueCarouselViewportWidthKey.self) { viewportWidth = $0 }
    .onAppear { rebuildRows() }
    .onChange(of: orderSignature) { _, _ in rebuildRows() }
    .abstandThemeRefresh()
  }

  /// Position im Streifen — ohne Peek der Nachbarkarte ist sonst nicht erkennbar,
  /// dass überhaupt weitere Titel folgen.
  @ViewBuilder
  private var pageIndicator: some View {
    if rows.count > 1 {
      let palette = model.appearancePalette
      let accent = model.appearanceAccentColor
      HStack(spacing: AppTheme.Layout.continueHeroPageDotSpacing) {
        ForEach(rows) { row in
          Circle()
            .fill(row.id == activeRowID ? accent : palette.textSecondary.opacity(0.3))
            .frame(
              width: AppTheme.Layout.continueHeroPageDotSize,
              height: AppTheme.Layout.continueHeroPageDotSize
            )
        }
      }
      .frame(maxWidth: .infinity)
      .animation(.easeInOut(duration: 0.2), value: activeRowID)
      .accessibilityElement()
      .accessibilityLabel("Page \(activePageNumber) of \(rows.count)")
    }
  }

  /// `scrollPosition` meldet erst nach der ersten Bewegung etwas — bis dahin ist die
  /// erste Karte sichtbar, und der erste Punkt muss gefüllt sein.
  private var activeRowID: ABSStartShelfMergedRow.ID? {
    currentRowID ?? rows.first?.id
  }

  private var activePageNumber: Int {
    guard let activeRowID, let index = rows.firstIndex(where: { $0.id == activeRowID }) else {
      return 1
    }
    return index + 1
  }

  private func rebuildRows() {
    rows = ABSStartShelfMergedRow.merged(
      books: shelf.books,
      podcastEpisodes: shelf.podcastEpisodes,
      progress: model.progressByItemId
    )
  }
}
