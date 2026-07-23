import SwiftUI

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
    guard let sid = showId else { return nil }
    return model.libraryEpisodeMatchingPodcastRssDraft(draft, showId: sid)
  }

  private var inLibrary: Bool { matchingLibraryEpisode != nil }

  var body: some View {
    let palette = model.appearancePalette
    let sid = (showId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        LibraryRowLayout.coverSlot {
          LibraryRowLayout.rowCoverImage(
            url: model.coverURL(for: sid),
            token: model.token,
            itemId: sid,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision(forBookId: sid)
          )
        }
        .accessibilityHidden(true)

        LibraryRowLayout.metadataColumn(showsProgressBar: false) {
          VStack(alignment: .leading, spacing: 2) {
            Text(draft.title)
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            LibraryRowCollapsedMetaLine(label: "Show", value: showTitle)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
              Text(publishedCaption)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(palette.textSecondary)
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
    .background(palette.card)
    .clipShape(LibraryRowLayout.cardShape)
    .abstandCardElevation(.standard)
    .abstandThemeRefresh()
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
    let secondary = model.appearancePalette.textSecondary
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
          .foregroundStyle(model.appearanceAccentColor)
          .font(.caption)
        Text("In library")
          .font(.caption.weight(.medium))
          .foregroundStyle(secondary)
      }
      .frame(minWidth: 88, alignment: .trailing)
    } else if model.podcastRssDraftDownloadCompletedIds.contains(draft.id) {
      Text("Downloading")
        .font(.caption.weight(.medium))
        .foregroundStyle(secondary)
        .lineLimit(1)
        .frame(minWidth: 88, alignment: .trailing)
        .accessibilityLabel("Downloading to server")
    } else if model.podcastRssEpisodeDownloadInProgressDraftIds.contains(draft.id) {
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Downloading")
          .font(.caption.weight(.medium))
          .foregroundStyle(secondary)
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
          .foregroundStyle(model.appearanceAccentColor)
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
struct LibraryRowCollapsedMetaLine: View {
  @EnvironmentObject private var model: AppModel
  let label: String
  let value: String?
  var valueLineLimit: Int = 2
  /// Continue-Hero: lesbare Farben auf Cover-Tint statt Palette.
  var labelColor: Color? = nil
  var valueColor: Color? = nil

  var body: some View {
    let palette = model.appearancePalette
    let resolvedLabel = labelColor ?? palette.textSecondary
    let resolvedValue = valueColor ?? palette.textPrimary
    let resolvedEmpty = labelColor ?? palette.textSecondary
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(resolvedLabel)
        .textCase(.uppercase)
      let line = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if line.isEmpty || line == "—" {
        Text("—")
          .font(.footnote)
          .foregroundStyle(resolvedEmpty)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text(line)
          .font(.footnote)
          .foregroundStyle(resolvedValue)
          .lineLimit(valueLineLimit)
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
    LibraryRowCollapsedMetaLine(label: "Show", value: episode.showTitle)
  }
}

private func continueHeroAuthorSingleLine(for book: ABSBook) -> String {
  let line = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
  if line.isEmpty || line == "—" { return "—" }
  return line
}

@ViewBuilder
private func continueHeroPlayPill(
  accent: Color,
  palette: AppColorPalette,
  caption: String,
  action: @escaping () -> Void
) -> some View {
  let labelOnAccent = palette.foregroundOnAccent(accent)
  HStack {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "play.fill")
          .font(.caption.weight(.bold))
        Text(caption)
          .font(.caption.weight(.semibold))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .foregroundStyle(labelOnAccent)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(accent, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Wiedergabe")
    .accessibilityValue("Noch \(caption)")
    Spacer(minLength: 0)
  }
}
// MARK: - Podcast episode row

struct PodcastEpisodeRowCard: View {
  /// Kein `@ObservedObject` — Fortschritt/Download über `LibraryPodcastEpisodeRowLiveState`.
  let model: AppModel
  let episode: ABSPodcastEpisodeListItem
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  var opensDetailOnTap = true

  @State private var live: LibraryPodcastEpisodeRowLiveState
  @State private var showDetail = false

  init(
    episode: ABSPodcastEpisodeListItem,
    model: AppModel,
    opensDetailOnTap: Bool = true
  ) {
    self.episode = episode
    self.opensDetailOnTap = opensDetailOnTap
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
    let _ = themeRevision
    return Group {
      if opensDetailOnTap {
        podcastEpisodeRowCardBody
          .navigationDestination(isPresented: $showDetail) {
            PodcastEpisodeDetailView(episode: episode)
          }
      } else {
        podcastEpisodeRowCardBody
      }
    }
    .abstandThemeRefresh()
  }

  private var podcastEpisodeRowCardBody: some View {
    LibraryRowLayout.libraryRowCardChrome(
      cardColor: AppTheme.card,
      showsBottomProgressBar: showsBottomProgressBar,
      progressValue: bottomProgressValue,
      openDetails: nil
    ) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        Button {
          Task { await model.playPodcastEpisode(episode) }
        } label: {
          LibraryRowLayout.coverSlot {
            LibraryRowLayout.rowCoverImage(
              url: model.coverURL(for: episode.libraryItemId),
              token: model.token,
              itemId: episode.libraryItemId,
              cacheAccount: model.coverImageCacheAccountDirectory(),
              cacheRevision: model.coverImageCacheRevision(forBookId: episode.libraryItemId)
            )
          } overlay: {
            Image(systemName: "play.fill")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.white)
              .frame(width: 18, height: 18)
              .background(model.appearancePalette.coverPlayBadgeBackground)
              .clipShape(Circle())
              .padding(4)
              .accessibilityHidden(true)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play")
        .accessibilityHint("Starts playback of this episode.")

        Group {
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
              LibraryRowLayout.metadataFooter {
                Text(formatPlaybackTime(resolvedTotalDurationSeconds))
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(AppTheme.textSecondary)
              } trailing: {
                Group {
                  if prog?.isFinished == true {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(themeAccent)
                      .font(.caption)
                      .accessibilityLabel("Finished")
                  }
                  podcastDownloadStatusIcon
                }
              }
            }
            .padding(.trailing, 4)
          }
        }
        .contentShape(Rectangle())
        .onTapGesture {
          guard opensDetailOnTap else { return }
          showDetail = true
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityHint(
      opensDetailOnTap
        ? "Opens episode details. Play button starts playback."
        : "Play button starts playback."
    )
  }

  @ViewBuilder
  private var podcastDownloadStatusIcon: some View {
    if live.isDownloaded {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(themeAccent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if live.isDownloading {
      ProgressView(value: live.downloadProgress)
        .frame(width: 36)
        .tint(themeAccent)
        .accessibilityLabel("Downloading")
    }
  }

  @ViewBuilder
  private func podcastEpisodeExpandedBlock(_ d: ABSPodcastEpisodeExpandedDetail) -> some View {
    let palette = model.appearancePalette
    VStack(alignment: .leading, spacing: 8) {
      Divider().background(palette.textSecondary.opacity(0.2))
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
              .stroke(model.appearanceAccentColor.opacity(0.45), lineWidth: 1)
            ProgressView(value: live.downloadProgress)
              .tint(model.appearanceAccentColor)
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
              .foregroundStyle(model.appearanceAccentColor)
          }
          .buttonStyle(LibraryCardActionButtonStyle(variant: .downloaded))
          .accessibilityLabel("Remove offline copy")
        } else {
          Button {
            model.startDownloadPodcastEpisode(episode)
          } label: {
            Image(systemName: "arrow.down.circle")
              .font(.callout)
              .foregroundStyle(model.appearanceAccentColor)
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
          .foregroundStyle(
            model.isNetworkReachable
              ? model.appearanceAccentColor
              : model.appearancePalette.textSecondary)
      }
      .buttonStyle(LibraryCardActionButtonStyle(variant: isFinished ? .finished : .accent))
      .disabled(!model.isNetworkReachable)
      .accessibilityLabel(isFinished ? "Mark as not finished" : "Finished")
    }
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.top, 8)
  }

  private func podcastMetaRowHostAuthorFilter(detail: ABSPodcastEpisodeExpandedDetail) -> some View {
    let palette = model.appearancePalette
    let authors = detail.showAuthors
    let line = detail.episode.authorLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return HStack(alignment: .top, spacing: 10) {
      Text("HOST / AUTHOR")
        .font(.caption.weight(.bold))
        .foregroundStyle(palette.textSecondary)
        .frame(width: 112, alignment: .leading)
      Group {
        if !authors.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(authors, id: \.id) { author in
              Button {
                model.openPodcastSearchFromText(author.name)
              } label: {
                Text(author.name)
                  .font(DetailHeroTypography.metaLink)
                  .abstandAccentForeground()
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
              .abstandAccentForeground()
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
        } else {
          Text("—")
            .font(.subheadline)
            .foregroundStyle(palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func podcastMetaRowShowFilter(episode: ABSPodcastEpisodeListItem) -> some View {
    let palette = model.appearancePalette
    let title = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return HStack(alignment: .top, spacing: 10) {
      Text("SHOW")
        .font(.caption.weight(.bold))
        .foregroundStyle(palette.textSecondary)
        .frame(width: 112, alignment: .leading)
      if title.isEmpty || title == "—" {
        Text("—")
          .font(.subheadline)
          .foregroundStyle(palette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Button {
          model.openPodcastSearchFromText(title)
        } label: {
          Text(title)
            .font(.subheadline)
            .abstandAccentForeground()
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func podcastMetaRow(_ k: String, _ v: String) -> some View {
    let palette = model.appearancePalette
    return HStack(alignment: .top, spacing: 10) {
      Text(k.uppercased())
        .font(.caption.weight(.bold))
        .foregroundStyle(palette.textSecondary)
        .frame(width: 112, alignment: .leading)
      Text(v)
        .font(.subheadline)
        .foregroundStyle(palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// Wählt kompakte Zeile oder Cover-Karte gemäß `libraryPodcastCardStyle`.
struct LibraryPodcastListCard: View {
  let episode: ABSPodcastEpisodeListItem
  let model: AppModel
  var opensDetailOnTap = true
  /// Offline-Downloadliste: immer kompakte Zeilen, unabhängig von Settings.
  var forceCompactListStyle = false

  private var usesHeroCoverStyle: Bool {
    !forceCompactListStyle && model.libraryPodcastCardStyle == .heroCover
  }

  var body: some View {
    if usesHeroCoverStyle {
      LibraryHeroPodcastEpisodeCard(
        episode: episode,
        model: model,
        opensDetailOnTap: opensDetailOnTap
      )
    } else {
      PodcastEpisodeRowCard(
        episode: episode,
        model: model,
        opensDetailOnTap: opensDetailOnTap
      )
    }
  }
}

/// Podcast-Cover-Karte im Library-Hero-Stil (Rasterzelle, ohne Play-Pille und Typ-Badge).
private struct LibraryHeroPodcastEpisodeCard: View {
  let episode: ABSPodcastEpisodeListItem
  let model: AppModel
  var opensDetailOnTap = true

  @State private var live: LibraryPodcastEpisodeRowLiveState
  @State private var tint: Color = AppTheme.card
  @State private var showDetail = false

  init(
    episode: ABSPodcastEpisodeListItem,
    model: AppModel,
    opensDetailOnTap: Bool = true
  ) {
    self.episode = episode
    self.opensDetailOnTap = opensDetailOnTap
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

  private var resolvedTotalDurationSeconds: Double {
    if episode.duration > 0 { return episode.duration }
    if let p = prog, p.duration > 0 { return p.duration }
    return 0
  }

  private var showLine: String {
    let s = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty ? "—" : s
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

  private var isFinished: Bool { prog?.isFinished == true }

  var body: some View {
    let palette = model.appearancePalette
    let coverInset = AppTheme.Layout.libraryRowCardInset
    let coverTopRadius = AppTheme.Layout.coverCornerRadius
    let barH = AppTheme.Layout.libraryRowBottomProgressHeight
    let coverClip = UnevenRoundedRectangle(
      topLeadingRadius: coverTopRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: coverTopRadius,
      style: .continuous
    )

    Group {
      if opensDetailOnTap {
        cardBody(palette: palette, coverInset: coverInset, coverClip: coverClip, barH: barH)
          .navigationDestination(isPresented: $showDetail) {
            PodcastEpisodeDetailView(episode: episode)
          }
      } else {
        cardBody(palette: palette, coverInset: coverInset, coverClip: coverClip, barH: barH)
      }
    }
    .task(id: episode.progressLookupKey) {
      let account = model.coverImageCacheAccountDirectory()
      let itemId = episode.libraryItemId
      let revision = model.coverImageCacheRevision(forBookId: itemId)
      if let c = await CoverDerivedTintLoader.loadColor(
        account: account,
        itemId: itemId,
        revision: revision,
        coverURL: model.coverURL(for: itemId),
        token: model.token
      ) {
        tint = c
      }
    }
  }

  @ViewBuilder
  private func cardBody(
    palette: AppColorPalette,
    coverInset: CGFloat,
    coverClip: UnevenRoundedRectangle,
    barH: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .bottom) {
        tint
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        CoverImageView(
          url: model.coverURL(for: episode.libraryItemId),
          token: model.token,
          itemId: episode.libraryItemId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forBookId: episode.libraryItemId),
          contentMode: .fit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(coverClip)
        .contentShape(coverClip)
        .onTapGesture {
          if opensDetailOnTap {
            showDetail = true
          }
        }
        .accessibilityLabel(episode.episodeTitle)
        .accessibilityHint(opensDetailOnTap ? "Opens episode details." : "")

        LinearGradient(
          stops: [
            .init(color: .black.opacity(0.45), location: 0),
            .init(color: .black.opacity(0), location: 1),
          ],
          startPoint: .bottom,
          endPoint: .top
        )
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)

        Group {
          if let v = heroProgress01 {
            AbstandCardBottomProgress(value: v, height: barH)
            .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          }
        }
      }
      .aspectRatio(1, contentMode: .fit)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .topTrailing) {
        ContinueListeningHeroPodcastOfflineBadgeSlot(rowLive: live)
          .fixedSize()
      }
      .clipped()

      VStack(alignment: .leading, spacing: 0) {
        ContinueListeningHeroMetadataBlock(
          title: episode.episodeTitle,
          detailLabel: "Show",
          detailValue: showLine,
          horizontalInset: coverInset,
          onTitleTap: { if opensDetailOnTap { showDetail = true } },
          includesBottomPadding: false,
          blockHeight: AppTheme.Layout.libraryHeroMetadataBlockHeight
            - AppTheme.Layout.continueHeroMetadataExtraBottomPadding
        )
        LibraryHeroCardMetadataFooter(
          durationLabel: formatPlaybackTime(resolvedTotalDurationSeconds),
          showsDownload: true,
          isDownloaded: live.isDownloaded,
          isDownloading: live.isDownloading,
          downloadProgress: live.downloadProgress,
          isFinished: isFinished,
          horizontalInset: coverInset,
          onRemoveDownload: {
            model.removeLocalDownload(bookId: model.podcastEpisodeOfflineStorageId(episode))
          },
          onToggleFinished: model.isNetworkReachable
            ? {
              Task {
                if isFinished {
                  await model.markPodcastEpisodeUnfinished(episode)
                } else {
                  await model.markPodcastEpisodeFinished(episode)
                }
              }
            }
            : nil
        )
      }
      .background(palette.card)
    }
    .background(palette.card)
    .clipShape(
      RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous)
    )
    .abstandHeroCardOutline(palette: palette)
    .frame(maxWidth: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityHint(opensDetailOnTap ? "Opens episode details." : "")
  }
}

// MARK: - Home „Continue listening“ (Hero-Karten)

struct ContinueListeningHeroBookCard: View {
  @EnvironmentObject private var model: AppModel
  let book: ABSBook
  var cardWidth: CGFloat = AppTheme.Layout.continueHeroCardWidth
  @State private var rowLive: LibraryBookRowLiveState
  @State private var tint: Color = AppTheme.card
  @State private var showDetail = false

  init(book: ABSBook, model: AppModel, cardWidth: CGFloat = AppTheme.Layout.continueHeroCardWidth) {
    self.book = book
    self.cardWidth = cardWidth
    _rowLive = State(
      wrappedValue: LibraryBookRowLiveState(bookId: book.id, model: model)
    )
    let seeded = CoverDerivedTintLoader.colorFromDiskOrCoverCache(
      account: model.coverImageCacheAccountDirectory(),
      itemId: book.id,
      revision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
    )
    _tint = State(initialValue: seeded ?? AppTheme.card)
  }

  private var prog: ABSUserMediaProgress? { rowLive.progress }

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
    let w = cardWidth
    let h = cardWidth
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
          cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt),
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
            AbstandCardBottomProgress(value: v, height: barH)
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
          .fixedSize()
      }
      .overlay(alignment: .topTrailing) {
        ContinueListeningHeroBookOfflineBadgeSlot(rowLive: rowLive)
          .fixedSize()
      }
      .frame(width: w, height: h)
      .clipped()

      ContinueListeningHeroTextBlock(
        title: book.displayTitle,
        detailLabel: "Author",
        detailValue: continueHeroAuthorSingleLine(for: book),
        horizontalInset: coverInset,
        onTitleTap: { showDetail = true },
        cardTint: tint
      ) {
        continueHeroPlayPill(
          accent: model.appearanceAccentColor,
          palette: model.appearancePalette,
          caption: playPillRemainingCaption
        ) {
          Task { await model.play(book: book) }
        }
      }
      .background(tint)
    }
    .frame(width: w, height: AppTheme.Layout.continueHeroCardTotalHeight(forCardWidth: w), alignment: .top)
    .background(tint)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous))
    .abstandHeroCardOutline(palette: model.appearancePalette)
    .task(id: book.id) {
      await refreshContinueHeroTint()
    }
    .onChange(of: model.appearanceThemeRevision) { _, _ in
      Task { await refreshContinueHeroTint() }
    }
    .navigationDestination(isPresented: $showDetail) {
      BookDetailView(bookId: book.id)
    }
  }

  private func refreshContinueHeroTint() async {
    let account = model.coverImageCacheAccountDirectory()
    let revision = model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
    if let c = await CoverDerivedTintLoader.loadColor(
      account: account,
      itemId: book.id,
      revision: revision,
      coverURL: model.coverURL(for: book.id),
      token: model.token
    ) {
      tint = c
    }
  }
}

struct ContinueListeningHeroPodcastCard: View {
  @EnvironmentObject private var model: AppModel
  let episode: ABSPodcastEpisodeListItem
  var cardWidth: CGFloat = AppTheme.Layout.continueHeroCardWidth
  @State private var rowLive: LibraryPodcastEpisodeRowLiveState
  @State private var tint: Color = AppTheme.card
  @State private var showDetail = false

  init(
    episode: ABSPodcastEpisodeListItem,
    model: AppModel,
    cardWidth: CGFloat = AppTheme.Layout.continueHeroCardWidth
  ) {
    self.episode = episode
    self.cardWidth = cardWidth
    _rowLive = State(
      wrappedValue: LibraryPodcastEpisodeRowLiveState(
        progressLookupKey: episode.progressLookupKey,
        offlineStorageId: model.podcastEpisodeOfflineStorageId(episode),
        model: model
      )
    )
    let itemId = episode.libraryItemId
    let seeded = CoverDerivedTintLoader.colorFromDiskOrCoverCache(
      account: model.coverImageCacheAccountDirectory(),
      itemId: itemId,
      revision: model.coverImageCacheRevision(forBookId: itemId)
    )
    _tint = State(initialValue: seeded ?? AppTheme.card)
  }

  private var prog: ABSUserMediaProgress? { rowLive.progress }

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
    let w = cardWidth
    let h = cardWidth
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
          cacheRevision: model.coverImageCacheRevision(forBookId: episode.libraryItemId),
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
            AbstandCardBottomProgress(value: v, height: barH)
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
          .fixedSize()
      }
      .overlay(alignment: .topTrailing) {
        ContinueListeningHeroPodcastOfflineBadgeSlot(rowLive: rowLive)
          .fixedSize()
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
        onTitleTap: { showDetail = true },
        cardTint: tint
      ) {
        continueHeroPlayPill(
          accent: model.appearanceAccentColor,
          palette: model.appearancePalette,
          caption: playPillRemainingCaption
        ) {
          Task { await model.playPodcastEpisode(episode) }
        }
      }
      .background(tint)
    }
    .frame(width: w, height: AppTheme.Layout.continueHeroCardTotalHeight(forCardWidth: w), alignment: .top)
    .background(tint)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous))
    .abstandHeroCardOutline(palette: model.appearancePalette)
    .task(id: episode.progressLookupKey) {
      await refreshContinueHeroTint()
    }
    .onChange(of: model.appearanceThemeRevision) { _, _ in
      Task { await refreshContinueHeroTint() }
    }
    .navigationDestination(isPresented: $showDetail) {
      PodcastEpisodeDetailView(episode: episode)
    }
  }

  private func refreshContinueHeroTint() async {
    let account = model.coverImageCacheAccountDirectory()
    let itemId = episode.libraryItemId
    let revision = model.coverImageCacheRevision(forBookId: itemId)
    if let c = await CoverDerivedTintLoader.loadColor(
      account: account,
      itemId: itemId,
      revision: revision,
      coverURL: model.coverURL(for: itemId),
      token: model.token
    ) {
      tint = c
    }
  }
}

// MARK: - Browse / search entity row (Autor, Serie, Sprecher, …)

// MARK: - Facet tiles (Collections / Genres / Tags) ohne Cover

private enum FacetBrowseTileMetrics {
  static let tileHeight: CGFloat = 93
  /// Wie `BookRowCard` / `BrowseEntityRowCard` (`libraryRowTitleText`).
  static let titleFont: Font = .headline.weight(.semibold)
  /// Wie `ContinueListeningHeroCoverPill` (äußeres Seiten-Padding).
  static let edgeInset: CGFloat = 8
  static let iconFont: Font = .title3.weight(.semibold)
  static let contentPadding: CGFloat = 14
}

struct FacetBrowseTileCard: View {
  @EnvironmentObject private var model: AppModel
  let kind: BooksBrowseSection
  let title: String
  let count: Int?

  var body: some View {
    facetBrowseTileCardChrome(
      palette: model.appearancePalette,
      title: title,
      count: count,
      accessibilityLabel: facetBrowseTileAccessibilityLabel
    ) {
      facetBrowseTileLeadingIcon(systemImage: kind.systemImage)
    }
  }

  private var facetBrowseTileAccessibilityLabel: String {
    if let c = count, c > 0 {
      return "\(kind.rawValue): \(title), \(c) books"
    }
    return "\(kind.rawValue): \(title)"
  }
}

@ViewBuilder
private func facetBrowseTileCardChrome<Leading: View>(
  palette: AppColorPalette,
  title: String,
  count: Int?,
  accessibilityLabel: String,
  @ViewBuilder leading: () -> Leading
) -> some View {
  let cardShape = RoundedRectangle(
    cornerRadius: LibraryRowLayout.cornerRadius,
    style: .continuous
  )

  ZStack(alignment: .topLeading) {
    cardShape
      .fill(palette.card)
    leading()
      .allowsHitTesting(false)
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 0)
      Text(title)
        .font(FacetBrowseTileMetrics.titleFont)
        .foregroundStyle(palette.textPrimary)
        .lineLimit(2)
        .truncationMode(.tail)
        .multilineTextAlignment(.leading)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(FacetBrowseTileMetrics.contentPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
  }
  .frame(height: FacetBrowseTileMetrics.tileHeight)
  .clipShape(cardShape)
  .abstandCardElevation(.standard)
  .overlay(alignment: .topTrailing) {
    if let c = count, c > 0 {
      ContinueListeningHeroCoverPill {
        Text("\(c) Books")
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.white)
          .lineLimit(1)
      }
      .fixedSize()
    }
  }
  .accessibilityElement(children: .combine)
  .accessibilityLabel(accessibilityLabel)
}

@ViewBuilder
private func facetBrowseTileLeadingInset<Content: View>(@ViewBuilder content: () -> Content) -> some View {
  content()
    .padding(FacetBrowseTileMetrics.edgeInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityHidden(true)
}

@ViewBuilder
private func facetBrowseTileLeadingIcon(systemImage: String) -> some View {
  facetBrowseTileLeadingInset {
    Image(systemName: systemImage)
        .font(FacetBrowseTileMetrics.iconFont)
      .abstandAccentForeground()
  }
}

func browseEntityBooksCountLine(count: Int?) -> String? {
  guard let c = count, c > 0 else { return nil }
  return "\(c)"
}

/// Serien-Cover: bis zu vier Miniatur-Covers im 82×82-Slot (2×2, bei 2–3 Büchern angepasst).
private struct SeriesMultiCoverView: View {
  @EnvironmentObject private var model: AppModel
  let bookIds: [String]

  private static let gap: CGFloat = 1

  var body: some View {
    let ids = Array(bookIds.prefix(4))
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let g = Self.gap
      let cellW = (w - g) / 2
      let cellH = (h - g) / 2

      switch ids.count {
      case 2:
        HStack(spacing: g) {
          coverTile(id: ids[0], width: (w - g) / 2, height: h)
          coverTile(id: ids[1], width: (w - g) / 2, height: h)
        }
      case 3:
        VStack(spacing: g) {
          HStack(spacing: g) {
            coverTile(id: ids[0], width: cellW, height: cellH)
            coverTile(id: ids[1], width: cellW, height: cellH)
          }
          HStack(spacing: g) {
            coverTile(id: ids[2], width: cellW, height: cellH)
            Color.clear.frame(width: cellW, height: cellH)
          }
        }
      default:
        VStack(spacing: g) {
          HStack(spacing: g) {
            coverTile(id: ids[0], width: cellW, height: cellH)
            coverTile(id: ids[1], width: cellW, height: cellH)
          }
          HStack(spacing: g) {
            coverTile(id: ids[2], width: cellW, height: cellH)
            coverTile(id: ids[3], width: cellW, height: cellH)
          }
        }
      }
    }
    .frame(width: LibraryRowLayout.coverSide, height: LibraryRowLayout.coverSide)
  }

  @ViewBuilder
  private func coverTile(id: String, width: CGFloat, height: CGFloat) -> some View {
    SquareCoverImageView(
      url: model.coverURL(for: id),
      token: model.token,
      itemId: id,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheRevision: model.coverImageCacheRevision(forBookId: id)
    )
    .frame(width: width, height: height)
    .clipped()
    .accessibilityHidden(true)
  }
}

/// Gleiches Kartenlayout wie `BookRowCard`: Cover 1:1 mit Letterboxing.
struct BrowseEntityRowCard: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  let detailLabel: String
  let detailValue: String?
  let cacheItemId: String
  let coverURL: URL?
  /// Mehrere Serien-Bücher: 2–4 Covers im gleichen Slot statt einem einzelnen Cover.
  var coverBookIds: [String]? = nil
  /// Optional (z. B. Serien): zweite Meta-Zeile wie bei `BookRowCard`.
  var authorLine: String? = nil
  /// Autoren-Portraits: fest 1:1, Mitte beschnitten.
  var usesSquareCenterCropCover = false

  /// Wie `BookRowCard`: `updatedAt`-Revision für Buch-IDs, sonst globaler Zähler.
  private var coverCacheRevision: Int {
    model.coverImageCacheRevision(forBookId: cacheItemId)
  }

  var body: some View {
    HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
      if usesSquareCenterCropCover, coverBookIds == nil || (coverBookIds?.count ?? 0) <= 1 {
        LibraryRowLayout.coverSlot(coverWidth: LibraryRowLayout.coverSide) {
          LibraryRowLayout.rowCoverImageSquare(
            url: coverURL,
            token: model.token,
            itemId: cacheItemId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: coverCacheRevision
          )
        }
      } else {
        LibraryRowLayout.coverSlot {
          if let ids = coverBookIds, ids.count > 1 {
            SeriesMultiCoverView(bookIds: ids)
          } else {
            LibraryRowLayout.rowCoverImage(
              url: coverURL,
              token: model.token,
              itemId: cacheItemId,
              cacheAccount: model.coverImageCacheAccountDirectory(),
              cacheRevision: coverCacheRevision
            )
          }
        }
      }

      LibraryRowLayout.metadataColumn(showsProgressBar: false) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(model.appearancePalette.textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
          if let authorLine {
            LibraryRowCollapsedMetaLine(label: "Author", value: authorLine, valueLineLimit: 1)
          }
          Spacer(minLength: 0)
          LibraryRowCollapsedMetaLine(label: detailLabel, value: detailValue)
        }
      }
    }
    .padding(.leading, 0)
    .background(model.appearancePalette.card)
    .clipShape(LibraryRowLayout.cardShape)
    .abstandCardElevation(.standard)
  }
}

// MARK: - Podcast show row

/// Podcast-Sendung in Listen — gleiches Layout wie `BookRowCard` (ohne Play-Badge).
struct PodcastShowRowCard: View {
  @EnvironmentObject private var model: AppModel
  let show: ABSBook
  var showsDownloadStatus = true

  var body: some View {
    let palette = model.appearancePalette
    return VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        LibraryRowLayout.coverSlot {
          LibraryRowLayout.rowCoverImage(
            url: model.coverURL(for: show.id),
            token: model.token,
            itemId: show.id,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: show.updatedAt)
          )
          .accessibilityHidden(true)
        }

        LibraryRowLayout.metadataColumn(showsProgressBar: false) {
          VStack(alignment: .leading, spacing: 2) {
            Text(show.displayTitle)
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            BookCollapsedAuthorLine(book: show)
            Spacer(minLength: 0)
            LibraryRowLayout.metadataFooter {
              Group {
                if let episodes = show.media.numTracks, episodes > 0 {
                  Text("\(episodes) episodes")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                } else if show.totalDuration > 0 {
                  Text(formatPlaybackTime(show.totalDuration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                }
              }
            } trailing: {
              downloadIcon
            }
          }
        }
      }
      .padding(.leading, 0)
    }
    .background(palette.card)
    .clipShape(LibraryRowLayout.cardShape)
    .abstandCardElevation(.standard)
    .abstandThemeRefresh()
  }

  @ViewBuilder
  private var downloadIcon: some View {
    if !showsDownloadStatus {
      EmptyView()
    } else if model.downloadedItemIds.contains(show.id) {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(model.appearanceAccentColor)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if model.downloads.activeItemId == show.id {
      ProgressView(value: model.downloads.progress)
        .frame(width: 36)
        .tint(model.appearanceAccentColor)
        .accessibilityLabel("Downloading")
    } else if model.downloads.queuedItemIds.contains(show.id) {
      Image(systemName: "circle.dashed")
        .foregroundStyle(model.appearanceAccentColor)
        .font(.caption)
        .accessibilityLabel("Queued")
    }
  }
}

// MARK: - Library row layout (Cover bündig links/oben/unten)

enum LibraryRowLayout {
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
      AbstandCardBottomProgress(
        value: value,
        height: AppTheme.Layout.libraryRowBottomProgressHeight,
        trackColor: AppTheme.progressTrack
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
    cardColor: Color,
    showsBottomProgressBar: Bool,
    progressValue: Double,
    openDetails: (() -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let base = VStack(alignment: .leading, spacing: 0) {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: coverSide, alignment: .top)
        .padding(.leading, 0)
    }
    .overlay(alignment: .bottom) {
      bottomProgressOverlay(value: progressValue, visible: showsBottomProgressBar)
        .allowsHitTesting(false)
    }
    .background(cardColor)
    .clipShape(cardShape)
    .contentShape(cardShape)
    .abstandCardElevation(.standard)
    .overlay {
      cardShape.strokeBorder(AppTheme.palette.textSecondary.opacity(0.22), lineWidth: 1)
    }

    if let openDetails {
      base.onTapGesture(perform: openDetails)
    } else {
      base
    }
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

  /// Listen-Zeilen: festes 1:1 mit zentriertem Cover und farbigem Letterboxing.
  @ViewBuilder
  static func rowCoverImage(
    url: URL?,
    token: String,
    itemId: String,
    cacheAccount: URL?,
    cacheRevision: Int = 0,
    requiresAuthorization: Bool = true
  ) -> some View {
    SquareCoverImageView(
      url: url,
      token: token,
      itemId: itemId,
      cacheAccount: cacheAccount,
      cacheRevision: cacheRevision,
      requiresAuthorization: requiresAuthorization
    )
  }

  /// Autoren-Portraits / Bücher auf Autor-Detail: fest 1:1, Mitte beschnitten (`scaledToFill`).
  @ViewBuilder
  static func rowCoverImageSquare(
    url: URL?,
    token: String,
    itemId: String,
    cacheAccount: URL?,
    cacheRevision: Int = 0,
    requiresAuthorization: Bool = true
  ) -> some View {
    CoverImageView(
      url: url,
      token: token,
      itemId: itemId,
      cacheAccount: cacheAccount,
      cacheRevision: cacheRevision,
      requiresAuthorization: requiresAuthorization,
      contentMode: .fill
    )
  }

  /// Cover-Slot in Listen-Zeilen: immer 1:1.
  @ViewBuilder
  static func coverSlot<Cover: View, Overlay: View>(
    coverWidth: CGFloat? = nil,
    @ViewBuilder cover: () -> Cover,
    @ViewBuilder overlay: () -> Overlay = { EmptyView() }
  ) -> some View {
    let side = coverWidth ?? coverSide
    cover()
      .frame(width: side, height: side)
      .clipShape(coverClipShape)
      .overlay(alignment: .bottomLeading) {
        overlay()
      }
  }

  /// Untere Meta-Zeile: Laufzeit/Labels links, Status-Icons (Download, Fertig) am rechten Kartenrand.
  @ViewBuilder
  static func metadataFooter<Leading: View, Trailing: View>(
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(alignment: .center, spacing: 8) {
      HStack(spacing: 8) {
        leading()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 6) {
        trailing()
      }
      .fixedSize(horizontal: true, vertical: false)
    }
  }
}

/// Footer unter Cover-Karten — gleiches Layout und Icons wie `BookRowCard` / `PodcastEpisodeRowCard`.
private struct LibraryHeroCardMetadataFooter: View {
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let durationLabel: String
  var showsDownload: Bool
  var isDownloaded: Bool
  var isDownloading: Bool
  var downloadProgress: Double
  var isFinished: Bool
  var horizontalInset: CGFloat
  var onRemoveDownload: (() -> Void)?
  var onToggleFinished: (() -> Void)?

  var body: some View {
    let _ = themeRevision
    return LibraryRowLayout.metadataFooter {
      Text(durationLabel)
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(AppTheme.textSecondary)
    } trailing: {
      HStack(spacing: 6) {
        if isFinished {
          libraryHeroStatusIconButton(action: onToggleFinished) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(themeAccent)
              .font(.caption)
          }
          .accessibilityLabel("Finished")
        }
        if showsDownload {
          libraryHeroDownloadTrailingIcon
        }
      }
    }
    .padding(.horizontal, horizontalInset)
    .padding(.bottom, AppTheme.Layout.continueHeroMetadataExtraBottomPadding)
    .abstandThemeRefresh()
  }

  @ViewBuilder
  private var libraryHeroDownloadTrailingIcon: some View {
    if isDownloaded {
      libraryHeroStatusIconButton(action: onRemoveDownload) {
        Image(systemName: "arrow.down.circle.fill")
          .foregroundStyle(themeAccent)
          .font(.caption)
      }
      .accessibilityLabel("Saved offline")
    } else if isDownloading {
      ProgressView(value: downloadProgress)
        .frame(width: 36)
        .tint(themeAccent)
        .accessibilityLabel("Downloading")
    }
  }

  @ViewBuilder
  private func libraryHeroStatusIconButton<Label: View>(
    action: (() -> Void)?,
    @ViewBuilder label: () -> Label
  ) -> some View {
    if let action {
      Button(action: action) {
        label()
      }
      .buttonStyle(.plain)
    } else {
      label()
    }
  }
}

// MARK: - Book row

/// Einspaltige Lazy-Liste — Hero-Raster (2 Spalten) baut der Aufrufer zeilenweise.
struct LibraryCoverCardsFlow<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      content()
    }
  }
}

struct LibraryBookCardsFlow<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    LibraryCoverCardsFlow(content: content)
  }
}

struct LibraryPodcastCardsFlow<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    LibraryCoverCardsFlow(content: content)
  }
}

/// Hero-Karten zeilenweise (`LazyVGrid` vermeiden — Tab-Wechsel-Layout-Bug).
struct LibraryHeroMultiColumnRows<Item: Identifiable, Card: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  let items: [Item]
  let columns: Int
  let spacing: CGFloat
  @ViewBuilder let card: (Item) -> Card

  /// iPad (`regular`-Breite): mehr Spalten, sonst wirken die großen Cover-Karten in der
  /// vollen Breite winzig verloren. Split View/Slide Over meldet `.compact` — bleibt unverändert.
  private var effectiveColumns: Int {
    let base = max(1, columns)
    return horizontalSizeClass == .regular ? base + 2 : base
  }

  var body: some View {
    let columnCount = effectiveColumns
    ForEach(Array(stride(from: 0, to: items.count, by: columnCount)), id: \.self) { start in
      HStack(alignment: .top, spacing: spacing) {
        ForEach(0..<columnCount, id: \.self) { offset in
          let index = start + offset
          if index < items.count {
            card(items[index])
              .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(maxWidth: .infinity, maxHeight: 1)
              .accessibilityHidden(true)
          }
        }
      }
    }
  }
}

struct LibraryHeroTwoColumnRows<Item: Identifiable, Card: View>: View {
  let items: [Item]
  let spacing: CGFloat
  @ViewBuilder let card: (Item) -> Card

  var body: some View {
    LibraryHeroMultiColumnRows(items: items, columns: 2, spacing: spacing, card: card)
  }
}

/// Autor-/Serien-Detail: immer kompakte Zeile — unabhängig von Library-Card-Settings.
struct AuthorDetailBookListCard: View {
  let book: ABSBook
  let model: AppModel

  var body: some View {
    LibraryBookListCard(
      book: book,
      model: model,
      forceCompactListStyle: true,
      usesSquareCenterCropCover: !book.isPureEbookLibraryItem
    )
  }
}

/// eBooks-Bereich im Books-Tab: kompakte Zeile oder Cover-Karte.
/// Karte für eBooks-/Supplementary-Tab — beide Listen sehen identisch aus; ob Play-Kontrollen
/// erscheinen, entscheidet einzig `book.isPlayableAudiobook`, nicht der Tab.
private struct EbookTabListCard: View {
  let book: ABSBook
  let model: AppModel

  var body: some View {
    LibraryBookListCard(
      book: book,
      model: model,
      showEbookBadge: true,
      showsPlaybackControls: book.isPlayableAudiobook,
      opensDetailOnTap: true,
      usesEbookProgressDisplay: true
    )
  }
}

/// Wählt kompakte Zeile, Cover-Karte oder Cover-only gemäß `libraryBookCardStyle`.
struct LibraryBookListCard: View {
  let book: ABSBook
  let model: AppModel
  var showEbookBadge = false
  var progressOverride: ABSUserMediaProgress?
  var authorLineOverride: String?
  var showsPlaybackControls = true
  var showsDownloadStatus = true
  var opensDetailOnTap = true
  /// Optionaler Cover-Tap, z. B. „Weiterlesen“ aus dem Continue-Reading-Regal.
  var onCoverOpen: (() -> Void)?
  /// Offline-Downloadliste: immer kompakte Zeilen, unabhängig von Settings.
  var forceCompactListStyle = false
  /// Autor-Detail: Cover fest 1:1, Mitte beschnitten.
  var usesSquareCenterCropCover = false
  /// eBooks-/Supplementary-Tab: Lesefortschritt statt Hörbuch-Dauer/-Fortschritt anzeigen.
  var usesEbookProgressDisplay = false
  /// Home-Cover-Reihen u. Ä.: Style unabhängig von Library-Settings erzwingen.
  var styleOverride: LibraryBookCardStyle? = nil

  private var resolvedCardStyle: LibraryBookCardStyle {
    styleOverride ?? model.libraryBookCardStyle
  }

  var body: some View {
    if forceCompactListStyle {
      BookRowCard(
        book: book,
        model: model,
        showEbookBadge: showEbookBadge,
        progressOverride: progressOverride,
        authorLineOverride: authorLineOverride,
        showsPlaybackControls: showsPlaybackControls,
        showsDownloadStatus: showsDownloadStatus,
        opensDetailOnTap: opensDetailOnTap,
        onCoverOpen: onCoverOpen,
        usesSquareCenterCropCover: usesSquareCenterCropCover,
        usesEbookProgressDisplay: usesEbookProgressDisplay
      )
    } else {
      switch resolvedCardStyle {
      case .heroCover:
        // `LibraryHeroBookRowCard` erkennt reine eBooks selbst (`isPureEbookLibraryItem`) und
        // zeigt automatisch Lesefortschritt statt Hörbuch-Dauer — kein Sonderfall nötig.
        LibraryHeroBookRowCard(
          book: book,
          model: model,
          showEbookBadge: showEbookBadge,
          usesEbookProgressDisplay: usesEbookProgressDisplay,
          progressOverride: progressOverride,
          authorLineOverride: authorLineOverride,
          showsDownloadStatus: showsDownloadStatus,
          opensDetailOnTap: opensDetailOnTap,
          showsMetadataBlock: true
        )
      case .coverOnly:
        LibraryHeroBookRowCard(
          book: book,
          model: model,
          showEbookBadge: showEbookBadge,
          usesEbookProgressDisplay: usesEbookProgressDisplay,
          progressOverride: progressOverride,
          authorLineOverride: authorLineOverride,
          showsDownloadStatus: showsDownloadStatus,
          opensDetailOnTap: opensDetailOnTap,
          showsMetadataBlock: false
        )
      case .compact:
        BookRowCard(
          book: book,
          model: model,
          showEbookBadge: showEbookBadge,
          progressOverride: progressOverride,
          authorLineOverride: authorLineOverride,
          showsPlaybackControls: showsPlaybackControls,
          showsDownloadStatus: showsDownloadStatus,
          opensDetailOnTap: opensDetailOnTap,
          onCoverOpen: onCoverOpen,
          usesSquareCenterCropCover: usesSquareCenterCropCover,
          usesEbookProgressDisplay: usesEbookProgressDisplay
        )
      }
    }
  }
}

/// Library-Cover-Karte im Continue-Hero-Stil (Rasterzelle, ohne Play-Pille).
/// Mit `showsMetadataBlock == false`: nur Cover + Cover-Icons, Tap → Detail (kein Start).
private struct LibraryHeroBookRowCard: View {
  let book: ABSBook
  let model: AppModel
  @Environment(\.appearanceThemeRevision) private var themeRevision
  var showEbookBadge = false
  var progressOverride: ABSUserMediaProgress?
  var authorLineOverride: String?
  var showsDownloadStatus = true
  var opensDetailOnTap = true
  /// Hero-Raster: immer 1:1 (`SquareCoverImageView` in `LibraryHeroBookRowCard`).
  var coverAspectRatio: CGFloat = 1
  /// eBook-Lesefortschritt in Balken auf dem Cover.
  var usesEbookProgressDisplay = false
  /// `false` = Cover-only (keine Titel/Autor-Zeile, keine Fortschrittsleiste/Gradient).
  var showsMetadataBlock = true

  @State private var live: LibraryBookRowLiveState
  @State private var showDetail = false
  private let supplementaryEbookBadge: Bool

  private var usesEbookMetrics: Bool {
    book.isPureEbookLibraryItem || usesEbookProgressDisplay
  }

  init(
    book: ABSBook,
    model: AppModel,
    showEbookBadge: Bool = false,
    usesEbookProgressDisplay: Bool = false,
    progressOverride: ABSUserMediaProgress? = nil,
    authorLineOverride: String? = nil,
    showsDownloadStatus: Bool = true,
    opensDetailOnTap: Bool = true,
    coverAspectRatio: CGFloat = 1,
    showsMetadataBlock: Bool = true
  ) {
    self.showEbookBadge = showEbookBadge
    self.usesEbookProgressDisplay = usesEbookProgressDisplay
    self.progressOverride = progressOverride
    self.authorLineOverride = authorLineOverride
    self.showsDownloadStatus = showsDownloadStatus
    self.opensDetailOnTap = opensDetailOnTap
    self.coverAspectRatio = coverAspectRatio
    self.showsMetadataBlock = showsMetadataBlock
    self.model = model
    self.supplementaryEbookBadge = model.bookShowsSupplementaryEbookBadge(book)
    let resolvedBook = model.bookStubEnrichedForListDisplay(book)
    self.book = resolvedBook
    let ebookMetrics = resolvedBook.isPureEbookLibraryItem || usesEbookProgressDisplay
    _live = State(
      wrappedValue: LibraryBookRowLiveState(
        bookId: resolvedBook.id,
        model: model,
        observesProgress: progressOverride == nil && !ebookMetrics,
        observesDownload: showsDownloadStatus,
        observesEbookProgress: ebookMetrics
      )
    )
  }

  private var prog: ABSUserMediaProgress? { progressOverride ?? live.progress }

  private var ebookProgress: Double? {
    guard usesEbookMetrics else { return nil }
    return live.ebookProgressFraction
  }

  private var heroProgress01: Double? {
    if usesEbookMetrics {
      guard let f = ebookProgress, f > 0.005, f < 0.995 else { return nil }
      return min(1, max(0, f))
    }
    guard let p = prog, !p.isFinished, p.duration > 0 else { return nil }
    return min(1, max(0, p.progress))
  }

  private var isFinished: Bool {
    if usesEbookMetrics {
      guard let f = ebookProgress else { return false }
      return f >= 0.995
    }
    return prog?.isFinished == true
  }

  private var showsAttachedEbookCoverBadge: Bool {
    supplementaryEbookBadge
  }

  /// Wie `ContinueListeningHeroTypePill`: Play für Hörbücher, Buch für reine eBooks.
  private var typeBadgeSystemImage: String? {
    if book.isPlayableAudiobook { return "play.fill" }
    if book.isPureEbookLibraryItem { return "book.closed.fill" }
    return nil
  }

  @ViewBuilder
  private var typeBadge: some View {
    if let systemImage = typeBadgeSystemImage {
      ContinueListeningHeroCoverPill {
        Image(systemName: systemImage)
          .font(ContinueListeningHeroCoverPillMetrics.iconFont)
          .foregroundStyle(.white)
      }
      .accessibilityLabel(book.isPlayableAudiobook ? "Playable as audiobook" : "eBook")
      .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var ebookAvailableBadge: some View {
    if showsAttachedEbookCoverBadge {
      ContinueListeningHeroCoverPill {
        Image(systemName: "book.closed.fill")
          .font(ContinueListeningHeroCoverPillMetrics.iconFont)
          .foregroundStyle(.white)
      }
      .accessibilityLabel("eBook available")
    }
  }

  var body: some View {
    let _ = themeRevision
    let palette = model.appearancePalette
    let coverInset = AppTheme.Layout.libraryRowCardInset
    let barH = AppTheme.Layout.libraryRowBottomProgressHeight

    return Group {
      if opensDetailOnTap {
        cardBody(palette: palette, coverInset: coverInset, barH: barH)
          .navigationDestination(isPresented: $showDetail) {
            BookDetailView(bookId: book.id)
          }
      } else {
        cardBody(palette: palette, coverInset: coverInset, barH: barH)
      }
    }
    .abstandThemeRefresh()
  }

  private var authorLine: String {
    let override = authorLineOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !override.isEmpty { return override }
    let line = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
    return line.isEmpty ? "—" : line
  }

  private var resolvedTotalDurationSeconds: Double {
    max(book.media.duration ?? 0, prog?.duration ?? 0)
  }

  private var heroDurationLabel: String {
    if usesEbookMetrics {
      return LibraryRowLiveState.ebookProgressLabel(for: live.ebookProgressFraction)
        ?? formatPlaybackTime(0)
    }
    return formatPlaybackTime(resolvedTotalDurationSeconds)
  }

  private var outerCornerRadius: CGFloat {
    AppTheme.Layout.continueHeroCardCornerRadius
  }

  @ViewBuilder
  private func cardBody(
    palette: AppColorPalette,
    coverInset: CGFloat,
    barH: CGFloat
  ) -> some View {
    let fullClip = RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)

    Group {
      if showsMetadataBlock {
        heroCardWithMetadata(palette: palette, coverInset: coverInset, barH: barH)
      } else {
        coverOnlyCard()
      }
    }
    .background(palette.card)
    .clipShape(fullClip)
    .abstandHeroCardOutline(palette: palette)
    .frame(maxWidth: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityHint(opensDetailOnTap ? "Opens book details." : "")
  }

  /// Reines 1:1-Cover mit denselben Cover-Icons wie die Cover-Karte; Tap → Detail.
  private func coverOnlyCard() -> some View {
    let fullClip = RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
    return coverStack(clip: fullClip, showsProgressChrome: false)
  }

  private func heroCardWithMetadata(
    palette: AppColorPalette,
    coverInset: CGFloat,
    barH: CGFloat
  ) -> some View {
    let coverTopRadius = AppTheme.Layout.coverCornerRadius
    let heroCoverClip = UnevenRoundedRectangle(
      topLeadingRadius: coverTopRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: coverTopRadius,
      style: .continuous
    )

    return VStack(alignment: .leading, spacing: 0) {
      coverStack(clip: heroCoverClip, showsProgressChrome: true, barH: barH)

      VStack(alignment: .leading, spacing: 0) {
        ContinueListeningHeroMetadataBlock(
          title: book.displayTitle,
          detailLabel: "Author",
          detailValue: authorLine,
          horizontalInset: coverInset,
          onTitleTap: {
            if opensDetailOnTap {
              showDetail = true
            }
          },
          includesBottomPadding: false,
          blockHeight: AppTheme.Layout.libraryHeroMetadataBlockHeight
            - AppTheme.Layout.continueHeroMetadataExtraBottomPadding
        )
        LibraryHeroCardMetadataFooter(
          durationLabel: heroDurationLabel,
          showsDownload: showsDownloadStatus,
          isDownloaded: live.isDownloaded,
          isDownloading: live.isDownloading,
          downloadProgress: live.downloadProgress,
          isFinished: isFinished,
          horizontalInset: coverInset,
          onRemoveDownload: { model.removeLocalDownload(bookId: book.id) },
          onToggleFinished: usesEbookMetrics || !model.isNetworkReachable
            ? nil
            : {
              Task {
                if isFinished {
                  await model.markUnfinished(bookId: book.id)
                } else {
                  await model.markFinished(bookId: book.id)
                }
              }
            }
        )
      }
      .background(palette.card)
    }
  }

  private func coverStack<Clip: Shape>(
    clip: Clip,
    showsProgressChrome: Bool,
    barH: CGFloat = AppTheme.Layout.libraryRowBottomProgressHeight
  ) -> some View {
    ZStack(alignment: .bottom) {
      SquareCoverImageView(
        url: model.coverURL(for: book.id),
        token: model.token,
        itemId: book.id,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
      )
      .clipShape(clip)
      .contentShape(clip)
      .onTapGesture {
        if opensDetailOnTap {
          showDetail = true
        }
      }
      .accessibilityLabel(book.displayTitle)
      .accessibilityHint(opensDetailOnTap ? "Opens book details." : "")

      if showsProgressChrome {
        LinearGradient(
          stops: [
            .init(color: .black.opacity(0.45), location: 0),
            .init(color: .black.opacity(0), location: 1),
          ],
          startPoint: .bottom,
          endPoint: .top
        )
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)

        Group {
          if usesEbookMetrics, live.isPreparingEbook {
            ProgressView()
              .tint(.white)
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          } else if let v = heroProgress01 {
            AbstandCardBottomProgress(value: v, height: barH)
              .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(maxWidth: .infinity)
              .frame(height: barH)
          }
        }
      }
    }
    .aspectRatio(coverAspectRatio, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .overlay(alignment: .topLeading) {
      typeBadge
        .fixedSize()
    }
    .overlay(alignment: .topTrailing) {
      HStack(spacing: 0) {
        ebookAvailableBadge
        if showsDownloadStatus {
          ContinueListeningHeroBookOfflineBadgeSlot(rowLive: live)
            .fixedSize()
        }
      }
    }
    .clipped()
  }
}

/// Kompaktes Cover-Badge (Play / eBook) — unten links oder rechts auf Listen-Covers.
private struct LibraryCoverCornerBadge: View {
  @EnvironmentObject private var model: AppModel
  let systemImage: String
  let accessibilityLabel: String
  var accessibilityHidden: Bool = false

  var body: some View {
    Image(systemName: systemImage)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.white)
      .frame(width: 18, height: 18)
      .background(model.appearancePalette.coverPlayBadgeBackground)
      .clipShape(Circle())
      .padding(4)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHidden(accessibilityHidden)
  }
}

struct BookRowCard: View {
  let book: ABSBook
  /// Kein `@ObservedObject` — Fortschritt/Download über `LibraryBookRowLiveState`.
  let model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  /// In Listen mit eBook-Badge das Buch-Symbol auf dem Cover (unten rechts).
  var showEbookBadge = false
  /// Fortschritt aus anderem Kontext (z. B. Server-User-Detail), nicht `progressByItemId`.
  var progressOverride: ABSUserMediaProgress?
  /// Autor-Zeile unabhängig vom Stub (z. B. angereicherter Server-User-Fortschritt).
  var authorLineOverride: String?
  var showsPlaybackControls = true
  var showsDownloadStatus = true
  var opensDetailOnTap = true
  var onCoverOpen: (() -> Void)?
  /// Autor-Detail: Cover fest 1:1, Mitte beschnitten.
  var usesSquareCenterCropCover = false
  /// eBooks-/Supplementary-Tab: Lesefortschritt statt Hörbuch-Dauer/-Fortschritt anzeigen.
  var usesEbookProgressDisplay = false

  @State private var live: LibraryBookRowLiveState
  @State private var showDetail = false
  private let supplementaryEbookBadge: Bool

  private var isPureEbookRow: Bool { book.isPureEbookLibraryItem }
  /// Reines eBook oder Hörbuch mit angehängtem eBook im eBooks-Tab — beide zeigen Lesefortschritt.
  private var usesEbookMetrics: Bool { isPureEbookRow || usesEbookProgressDisplay }
  private var showsAudiobookPlayControl: Bool { book.isPlayableAudiobook && showsPlaybackControls }
  private var showsAttachedEbookCoverBadge: Bool {
    supplementaryEbookBadge
  }

  init(
    book: ABSBook,
    model: AppModel,
    showEbookBadge: Bool = false,
    progressOverride: ABSUserMediaProgress? = nil,
    authorLineOverride: String? = nil,
    showsPlaybackControls: Bool = true,
    showsDownloadStatus: Bool = true,
    opensDetailOnTap: Bool = true,
    onCoverOpen: (() -> Void)? = nil,
    usesSquareCenterCropCover: Bool = false,
    usesEbookProgressDisplay: Bool = false
  ) {
    self.showEbookBadge = showEbookBadge
    self.progressOverride = progressOverride
    self.authorLineOverride = authorLineOverride
    self.showsPlaybackControls = showsPlaybackControls
    self.showsDownloadStatus = showsDownloadStatus
    self.opensDetailOnTap = opensDetailOnTap
    self.onCoverOpen = onCoverOpen
    self.usesSquareCenterCropCover = usesSquareCenterCropCover
    self.usesEbookProgressDisplay = usesEbookProgressDisplay
    self.model = model
    self.supplementaryEbookBadge = model.bookShowsSupplementaryEbookBadge(book)
    let resolvedBook = model.bookStubEnrichedForListDisplay(book)
    self.book = resolvedBook
    let ebookMetrics = resolvedBook.isPureEbookLibraryItem || usesEbookProgressDisplay
    _live = State(
      wrappedValue: LibraryBookRowLiveState(
        bookId: resolvedBook.id,
        model: model,
        observesProgress: progressOverride == nil && !ebookMetrics,
        observesDownload: showsDownloadStatus,
        observesEbookProgress: ebookMetrics
      )
    )
  }

  private var prog: ABSUserMediaProgress? { progressOverride ?? live.progress }

  private var ebookProgress: Double? {
    guard usesEbookMetrics else { return nil }
    return live.ebookProgressFraction
  }

  private var ebookProgressLabel: String? {
    guard usesEbookMetrics else { return nil }
    return LibraryRowLiveState.ebookProgressLabel(for: live.ebookProgressFraction)
  }

  private var showsBottomProgressBar: Bool {
    if usesEbookMetrics {
      guard let f = ebookProgress, f > 0.005, f < 0.995 else { return false }
      return true
    }
    guard let p = prog, !p.isFinished, p.duration > 0 else { return false }
    return true
  }

  private var bottomProgressValue: Double {
    if usesEbookMetrics, let f = ebookProgress { return min(1, max(0, f)) }
    if let p = prog, p.duration > 0 { return min(1, max(0, p.progress)) }
    return 0
  }

  var body: some View {
    let _ = themeRevision
    return Group {
      if opensDetailOnTap {
        bookRowCardBody
          .navigationDestination(isPresented: $showDetail) {
            BookDetailView(bookId: book.id)
          }
      } else {
        bookRowCardBody
      }
    }
    .abstandThemeRefresh()
  }

  private var bookRowCardBody: some View {
    LibraryRowLayout.libraryRowCardChrome(
      cardColor: AppTheme.card,
      showsBottomProgressBar: showsBottomProgressBar,
      progressValue: bottomProgressValue,
      openDetails: opensDetailOnTap ? { showDetail = true } : nil
    ) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        Group {
          if let onCoverOpen {
            Button(action: onCoverOpen) {
              libraryRowCoverWithPlayBadge
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue reading")
            .accessibilityHint("Opens this eBook at your reading position.")
          } else if showsAudiobookPlayControl {
            Button {
              Task { await model.play(book: book) }
            } label: {
              libraryRowCoverWithPlayBadge
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play")
            .accessibilityHint("Starts playback of this audiobook.")
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
    .accessibilityHint(
      onCoverOpen != nil
        ? "Cover opens this eBook at your reading position. The rest opens book details."
        : opensDetailOnTap
          ? "Opens book details. Play button starts playback."
          : "Play button starts playback."
    )
  }

  private var libraryRowCoverWithPlayBadge: some View {
    let side = LibraryRowLayout.coverSide
    return Group {
      if usesSquareCenterCropCover {
        LibraryRowLayout.rowCoverImageSquare(
          url: model.coverURL(for: book.id),
          token: model.token,
          itemId: book.id,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
        )
      } else {
        LibraryRowLayout.rowCoverImage(
          url: model.coverURL(for: book.id),
          token: model.token,
          itemId: book.id,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt)
        )
      }
    }
    .frame(width: side, height: side)
    .clipShape(LibraryRowLayout.coverClipShape)
    .overlay(alignment: .bottomLeading) {
      // Badge zeigt die tatsächliche Fähigkeit des Items (Hörbuch vs. eBook) — unabhängig davon,
      // ob der Cover-Tap in diesem Kontext auch wirklich Play auslöst (`showsAudiobookPlayControl`).
      if book.isPlayableAudiobook {
        LibraryCoverCornerBadge(systemImage: "play.fill", accessibilityLabel: "Play", accessibilityHidden: true)
      } else if isPureEbookRow {
        LibraryCoverCornerBadge(
          systemImage: "book.closed.fill", accessibilityLabel: "eBook", accessibilityHidden: true)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if showsAttachedEbookCoverBadge {
        LibraryCoverCornerBadge(systemImage: "book.closed.fill", accessibilityLabel: "eBook available")
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
    LibraryRowLayout.metadataFooter {
      Group {
        if usesEbookMetrics {
          if let label = ebookProgressLabel {
            Text(label)
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(AppTheme.textSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
        } else {
          Text(formatPlaybackTime(book.media.duration ?? 0))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
        }
      }
    } trailing: {
      libraryRowTrailingStatusIcons
    }
  }

  @ViewBuilder
  private var libraryRowTrailingStatusIcons: some View {
    if usesEbookMetrics, let f = ebookProgress, f >= 0.995 {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(themeAccent)
        .font(.caption)
        .accessibilityLabel("Finished reading")
    } else if !usesEbookMetrics, prog?.isFinished == true {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(themeAccent)
        .font(.caption)
        .accessibilityLabel("Finished")
    }
    downloadIcon
  }

  @ViewBuilder
  private var downloadIcon: some View {
    if !showsDownloadStatus {
      EmptyView()
    } else if live.isDownloaded {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(themeAccent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if live.isDownloading {
      ProgressView(value: live.downloadProgress)
        .frame(width: 36)
        .tint(themeAccent)
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
    let isQueued = d.id == book.id ? live.isQueued : model.downloads.queuedItemIds.contains(d.id)
    let downloadProgress = d.id == book.id ? live.downloadProgress : model.downloads.progress

    VStack(alignment: .leading, spacing: 8) {
      Divider().background(AppTheme.textSecondary.opacity(0.2))
      expandedAuthorRow(metadata: m)
      expandedNarratorRow(metadata: m)
      expandedSeriesRow(metadata: m)
      metaRow("Year", m.publishedYear ?? "—")
      metaRow("Publisher", m.publisher ?? "—")
      metaRow("Genres", (m.genres ?? []).joined(separator: ", ").nilIfEmpty ?? "—")
      metaRow(
        "Description",
        absPlainText(fromHTML: m.descriptionPlain ?? m.description).nilIfEmpty ?? "—")

      HStack(spacing: 8) {
        Group {
          if isDownloading {
            ZStack {
              RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
                .stroke(themeAccent.opacity(0.45), lineWidth: 1)
              ProgressView(value: downloadProgress)
                .tint(themeAccent)
                .scaleEffect(x: 1, y: 1.1, anchor: .center)
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: MiniPlayerMetrics.controlMinHeight)
            .accessibilityLabel("Download in progress")
          } else if isQueued {
            // Wartet in der Download-Queue — noch nicht aktiv, kein Cancel hier (nur über Entfernen).
            Image(systemName: "circle.dashed")
              .font(.callout)
              .foregroundStyle(themeAccent)
              .frame(maxWidth: .infinity)
              .frame(height: MiniPlayerMetrics.controlMinHeight)
              .accessibilityLabel("Queued")
          } else if isDownloaded {
            Button {
              model.removeLocalDownload(bookId: d.id)
            } label: {
              Image(systemName: "arrow.down.circle.badge.xmark")
                .font(.callout)
                .foregroundStyle(themeAccent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .downloaded))
            .accessibilityLabel("Remove offline copy")
          } else {
            Button {
              model.startDownload(book: d)
            } label: {
              Image(systemName: "arrow.down.circle")
                .font(.callout)
                .foregroundStyle(themeAccent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .neutral))
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
            .foregroundStyle(
              model.isNetworkReachable
                ? themeAccent
                : AppTheme.textSecondary)
        }
        .buttonStyle(LibraryCardActionButtonStyle(variant: isFinished ? .finished : .accent))
        .disabled(!model.isNetworkReachable)
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
                .abstandAccentForeground()
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
              .abstandAccentForeground()
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
          ForEach(names, id: \.self) { name in
            Button {
              applyNarratorFilterForActiveCatalog(narratorName: name)
            } label: {
              Text(name)
                .font(.subheadline)
                .abstandAccentForeground()
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
                .abstandAccentForeground()
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
