import Combine
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
    // Gleiche Zeilenhülle wie Buch-/Folgen-Zeilen (Kante, minHeight = Cover); Tap bleibt bei den Buttons.
    return LibraryRowLayout.libraryRowCardChrome(
      cardColor: palette.card,
      showsBottomProgressBar: false,
      progressValue: 0,
      openDetails: nil
    ) {
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
          VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
            Text(draft.title)
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            LibraryRowCollapsedMetaLine(label: "Show", value: showTitle)
            Spacer(minLength: 0)
            HStack(spacing: AppTheme.Layout.inlineSpacing) {
              Text(publishedCaption)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(palette.textSecondary)
              Spacer(minLength: 0)
              rssTrailingControl
            }
          }
          .padding(.trailing, AppTheme.Layout.tightSpacing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RSS episode, not in library yet")
      }
    }
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
      .frame(minWidth: AppTheme.Layout.metaValueColumnMinWidth, alignment: .trailing)
      .disabled(!model.isNetworkReachable)
      .accessibilityLabel("Delete episode from library")
    } else if inLibrary {
      // Einheitlich mit den Podcast-Screens: Häkchen + „In library“, beides in Akzentfarbe.
      HStack(spacing: AppTheme.Layout.tightSpacing) {
        Image(systemName: "checkmark.circle.fill")
          .font(.caption)
        Text("In library")
          .font(.caption.weight(.medium))
          .lineLimit(1)
      }
      .foregroundStyle(model.appearanceAccentColor)
      .frame(minWidth: AppTheme.Layout.metaValueColumnMinWidth, alignment: .trailing)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("In library")
    } else if model.podcastRssDraftDownloadCompletedIds.contains(draft.id) {
      Text("Downloading")
        .font(.caption.weight(.medium))
        .foregroundStyle(secondary)
        .lineLimit(1)
        .frame(minWidth: AppTheme.Layout.metaValueColumnMinWidth, alignment: .trailing)
        .accessibilityLabel("Downloading to server")
    } else if model.podcastRssEpisodeDownloadInProgressDraftIds.contains(draft.id) {
      HStack(spacing: AppTheme.Layout.compactSpacing) {
        ProgressView()
          .controlSize(.small)
        Text("Downloading")
          .font(.caption.weight(.medium))
          .foregroundStyle(secondary)
          .lineLimit(1)
      }
      .frame(minWidth: AppTheme.Layout.metaValueColumnMinWidth, alignment: .trailing)
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
      .frame(minWidth: AppTheme.Layout.metaValueColumnMinWidth, alignment: .trailing)
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
    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Layout.compactSpacing) {
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

/// Play↔Pause wie Detail-Hero: bei aktivem Medium Pause/Resume, sonst Start.
@MainActor
private func continueHeroPlayPillToggle(
  model: AppModel,
  libraryItemId: String,
  episodeId: String?,
  isFinished: Bool,
  startPlayback: @escaping () async -> Void
) {
  let isCurrent = model.isActivelyPlayingMedia(
    libraryItemId: libraryItemId,
    episodeId: episodeId
  )
  if isCurrent && model.player.isPlaying {
    model.player.pause()
  } else if isCurrent && !isFinished {
    model.player.play()
  } else {
    Task { await startPlayback() }
  }
}

/// Publisher „dieser Titel spielt gerade“ — Player-Identität + `isPlaying`. Karten halten `model`
/// unbeobachtet (Performance in Lazy-Listen); ohne diesen gezielten Abo hinge Play/Pause am nächsten
/// zufälligen Rerender der Karte.
@MainActor
private func playbackActivePublisher(
  model: AppModel,
  libraryItemId: String,
  episodeId: String?
) -> AnyPublisher<Bool, Never> {
  let player = model.player
  let wantEp = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  return Publishers.CombineLatest3(player.$activeBook, player.$activePlaybackEpisodeId, player.$isPlaying)
    .map { book, ep, playing in
      let activeEp = ep?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return playing && book?.id == libraryItemId && activeEp == wantEp
    }
    .removeDuplicates()
    .dropFirst()
    .eraseToAnyPublisher()
}

private func continueHeroPlayPill(
  model: AppModel,
  libraryItemId: String,
  episodeId: String?,
  accent: Color,
  palette: AppColorPalette,
  caption: String,
  action: @escaping () -> Void
) -> some View {
  HStack {
    ContinueHeroPlayPillButton(
      model: model,
      libraryItemId: libraryItemId,
      episodeId: episodeId,
      accent: accent,
      palette: palette,
      caption: caption,
      action: action
    )
    Spacer(minLength: 0)
  }
}

/// Play-Pille mit Restzeit (Hero-/Continue-Karten) — Play/Pause beobachtet und beim Tippen optimistisch.
private struct ContinueHeroPlayPillButton: View {
  let model: AppModel
  let libraryItemId: String
  let episodeId: String?
  let accent: Color
  let palette: AppColorPalette
  let caption: String
  let action: () -> Void

  @State private var showsPause = false
  /// Einmal im init gebaut — pro Render neu abonniert würde der alte Wert den optimistischen überschreiben.
  private let playerState: AnyPublisher<Bool, Never>

  init(
    model: AppModel,
    libraryItemId: String,
    episodeId: String?,
    accent: Color,
    palette: AppColorPalette,
    caption: String,
    action: @escaping () -> Void
  ) {
    self.model = model
    self.libraryItemId = libraryItemId
    self.episodeId = episodeId
    self.accent = accent
    self.palette = palette
    self.caption = caption
    self.action = action
    playerState = playbackActivePublisher(model: model, libraryItemId: libraryItemId, episodeId: episodeId)
  }

  /// Scheitert die Aktion ohne Player-Änderung (offline, Fehler), käme kein Event — dann nach kurzer
  /// Zeit auf den echten Zustand zurückfallen, statt dauerhaft „Pause“ zu zeigen.
  private func reconcileAfterOptimisticToggle() {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      showsPause = model.player.isPlaying
        && model.isActivelyPlayingMedia(libraryItemId: libraryItemId, episodeId: episodeId)
    }
  }

  var body: some View {
    Button {
      showsPause.toggle()
      action()
      reconcileAfterOptimisticToggle()
    } label: {
      HStack(spacing: AppTheme.Layout.compactSpacing) {
        Image(systemName: showsPause ? "pause.fill" : "play.fill")
          .font(.caption.weight(.bold))
        Text(caption)
          .font(.caption.weight(.semibold))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .foregroundStyle(palette.foregroundOnAccent(accent))
      .padding(.horizontal, AppTheme.Layout.rowSpacing)
      .padding(.vertical, AppTheme.Layout.stackSpacing)
      .background(accent, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(showsPause ? "Pause" : "Play")
    .accessibilityValue(showsPause ? "Playing" : "Noch \(caption)")
    .onAppear {
      showsPause = model.player.isPlaying
        && model.isActivelyPlayingMedia(libraryItemId: libraryItemId, episodeId: episodeId)
    }
    .onReceive(playerState) { showsPause = $0 }
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
  /// Wenn gesetzt, öffnet der Tap diese Aktion statt einer eigenen `navigationDestination`
  /// (nötig in `LazyVStack` — per-Zeile `isPresented` kommt dort oft nicht an).
  var onOpenDetail: (() -> Void)? = nil

  @State private var live: LibraryPodcastEpisodeRowLiveState
  @State private var showDetail = false

  init(
    episode: ABSPodcastEpisodeListItem,
    model: AppModel,
    opensDetailOnTap: Bool = true,
    onOpenDetail: (() -> Void)? = nil
  ) {
    self.episode = episode
    self.opensDetailOnTap = opensDetailOnTap
    self.onOpenDetail = onOpenDetail
    self.model = model
    _live = State(
      wrappedValue: LibraryPodcastEpisodeRowLiveState(
        progressLookupKey: episode.progressLookupKey,
        offlineStorageId: model.podcastEpisodeOfflineStorageId(episode),
        model: model
      )
    )
  }

  private var usesOwnedDetailDestination: Bool {
    opensDetailOnTap && onOpenDetail == nil
  }

  private func openEpisodeDetail() {
    if let onOpenDetail {
      onOpenDetail()
    } else {
      showDetail = true
    }
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
      if usesOwnedDetailDestination {
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

  /// Beendete Folge: Text und Play-Pille zurücknehmen.
  private var episodeFinishedContentOpacity: Double {
    prog?.isFinished == true ? LibraryRowLayout.finishedContentOpacity : 1
  }

  private var podcastEpisodeRowCardBody: some View {
    LibraryRowLayout.libraryRowCardChrome(
      cardColor: model.appearancePalette.card,
      showsBottomProgressBar: showsBottomProgressBar,
      progressValue: bottomProgressValue,
      openDetails: opensDetailOnTap ? { openEpisodeDetail() } : nil
    ) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        // Play sitzt als Pille rechts unten — das Cover gehört zur Karte (öffnet Details).
        LibraryRowLayout.coverSlot {
          LibraryRowLayout.rowCoverImage(
            url: model.coverURL(for: episode.libraryItemId),
            token: model.token,
            itemId: episode.libraryItemId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision(forBookId: episode.libraryItemId)
          )
        }
        .opacity(episodeFinishedContentOpacity)

        LibraryRowLayout.metadataColumn(showsProgressBar: showsBottomProgressBar) {
          VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Layout.compactSpacing) {
              Text(episode.episodeTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(model.appearancePalette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(episodeFinishedContentOpacity)
                .frame(maxWidth: .infinity, alignment: .leading)
              LibraryRowStatusBadges(
                color: model.appearancePalette.textSecondary,
                isFinished: prog?.isFinished == true,
                isDownloaded: live.isDownloaded,
                isDownloading: live.isDownloading,
                downloadProgress: live.downloadProgress
              )
            }
            PodcastEpisodeCollapsedShowLine(episode: episode)
              .opacity(episodeFinishedContentOpacity)
            Spacer(minLength: 0)
            LibraryRowLayout.metadataFooter(alignment: .bottom) {
              LibraryRowLayout.footerLeadingSlot {
                Text(formatPlaybackTime(resolvedTotalDurationSeconds))
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(model.appearancePalette.textSecondary)
                  .opacity(episodeFinishedContentOpacity)
              }
            } trailing: {
              LibraryRowPlayPill(
                model: model,
                libraryItemId: episode.libraryItemId,
                episodeId: episode.episodeId,
                accent: themeAccent
              ) {
                let isFinished = prog?.isFinished == true
                continueHeroPlayPillToggle(
                  model: model,
                  libraryItemId: episode.libraryItemId,
                  episodeId: episode.episodeId,
                  isFinished: isFinished
                ) {
                  await model.playPodcastEpisode(episode, resumeAtOverride: isFinished ? 0 : nil)
                }
              }
              .opacity(episodeFinishedContentOpacity)
            }
          }
          .padding(.trailing, AppTheme.Layout.tightSpacing)
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
}

/// Wählt kompakte Zeile oder Cover-Karte gemäß `libraryPodcastCardStyle`.
struct LibraryPodcastListCard: View {
  let episode: ABSPodcastEpisodeListItem
  let model: AppModel
  var opensDetailOnTap = true
  var onOpenDetail: (() -> Void)? = nil
  /// Offline-Downloadliste: immer kompakte Zeilen, unabhängig von Settings.
  var forceCompactListStyle = false
  /// Home-Regale u. Ä.: Style unabhängig von Library-Settings erzwingen.
  var styleOverride: LibraryPodcastCardStyle? = nil

  private var usesHeroCoverStyle: Bool {
    if forceCompactListStyle { return false }
    let style = styleOverride ?? model.libraryPodcastCardStyle
    return style == .heroCover
  }

  var body: some View {
    if usesHeroCoverStyle {
      LibraryHeroPodcastEpisodeCard(
        episode: episode,
        model: model,
        opensDetailOnTap: opensDetailOnTap,
        onOpenDetail: onOpenDetail
      )
    } else {
      PodcastEpisodeRowCard(
        episode: episode,
        model: model,
        opensDetailOnTap: opensDetailOnTap,
        onOpenDetail: onOpenDetail
      )
    }
  }
}

/// Podcast-Cover-Karte im Library-Hero-Stil (Rasterzelle, ohne Play-Pille und Typ-Badge).
private struct LibraryHeroPodcastEpisodeCard: View {
  let episode: ABSPodcastEpisodeListItem
  let model: AppModel
  var opensDetailOnTap = true
  var onOpenDetail: (() -> Void)? = nil

  @State private var live: LibraryPodcastEpisodeRowLiveState
  @State private var showDetail = false

  init(
    episode: ABSPodcastEpisodeListItem,
    model: AppModel,
    opensDetailOnTap: Bool = true,
    onOpenDetail: (() -> Void)? = nil
  ) {
    self.episode = episode
    self.opensDetailOnTap = opensDetailOnTap
    self.onOpenDetail = onOpenDetail
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

  /// Beendete Folge: Cover und Text zurücknehmen (wie kompakte Zeilen).
  private var episodeFinishedOpacity: Double {
    prog?.isFinished == true ? LibraryRowLayout.finishedContentOpacity : 1
  }

  private var resolvedTotalDurationSeconds: Double {
    if episode.duration > 0 { return episode.duration }
    if let p = prog, p.duration > 0 { return p.duration }
    return 0
  }

  private var showLine: String {
    let s = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty ? "—" : s
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

  private var usesOwnedDetailDestination: Bool {
    opensDetailOnTap && onOpenDetail == nil
  }

  private func openEpisodeDetail() {
    if let onOpenDetail {
      onOpenDetail()
    } else {
      showDetail = true
    }
  }

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
      if usesOwnedDetailDestination {
        cardBody(palette: palette, coverInset: coverInset, coverClip: coverClip, barH: barH)
          .navigationDestination(isPresented: $showDetail) {
            PodcastEpisodeDetailView(episode: episode)
          }
      } else {
        cardBody(palette: palette, coverInset: coverInset, coverClip: coverClip, barH: barH)
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
      // Cover wie Books-Hero: volle Kartenbreite (1:1, SquareCoverImageView).
      ZStack(alignment: .bottom) {
        SquareCoverImageView(
          url: model.coverURL(for: episode.libraryItemId),
          token: model.token,
          itemId: episode.libraryItemId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision(forBookId: episode.libraryItemId)
        )
        .clipShape(coverClip)
        .contentShape(coverClip)
        .opacity(episodeFinishedOpacity)
        .onTapGesture {
          if opensDetailOnTap {
            openEpisodeDetail()
          }
        }
        .accessibilityLabel(episode.episodeTitle)
        .accessibilityHint(opensDetailOnTap ? "Opens episode details." : "")

        AppTheme.coverScrimGradient
        .frame(height: AppTheme.Layout.coverScrimHeight)
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
        HStack(spacing: 0) {
          if prog?.isFinished == true {
            LibraryHeroFinishedBadge()
              .fixedSize()
          }
          ContinueListeningHeroPodcastOfflineBadgeSlot(rowLive: live)
            .fixedSize()
        }
      }
      .clipped()

      // Wie Continue Listening: Dauer als Play-Pille → Play↔Pause wie Detail.
      ContinueListeningHeroTextBlock(
        title: episode.episodeTitle,
        detailLabel: "Show",
        detailValue: showLine,
        horizontalInset: coverInset,
        onTitleTap: { if opensDetailOnTap { openEpisodeDetail() } }
      ) {
        let isFinished = prog?.isFinished == true
        continueHeroPlayPill(
          model: model,
          libraryItemId: episode.libraryItemId,
          episodeId: episode.episodeId,
          accent: model.appearanceAccentColor,
          palette: palette,
          caption: playPillRemainingCaption
        ) {
          continueHeroPlayPillToggle(
            model: model,
            libraryItemId: episode.libraryItemId,
            episodeId: episode.episodeId,
            isFinished: isFinished
          ) {
            await model.playPodcastEpisode(
              episode,
              resumeAtOverride: isFinished ? 0 : nil
            )
          }
        }
      }
      .opacity(episodeFinishedOpacity)
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
    _tint = State(initialValue: seeded ?? model.appearancePalette.card)
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
        .accessibilityHint("Opens details")

        AppTheme.coverScrimGradient
        .frame(height: min(AppTheme.Layout.coverScrimHeight, h * 0.28))
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
        let isFinished = prog?.isFinished == true
        continueHeroPlayPill(
          model: model,
          libraryItemId: book.id,
          episodeId: nil,
          accent: model.appearanceAccentColor,
          palette: model.appearancePalette,
          caption: playPillRemainingCaption
        ) {
          continueHeroPlayPillToggle(
            model: model,
            libraryItemId: book.id,
            episodeId: nil,
            isFinished: isFinished
          ) {
            await model.play(
              book: book,
              resumeAtOverride: isFinished ? 0 : nil
            )
          }
        }
      }
      .background(tint)
    }
    // Höhe aus dem Inhalt (Cover + skalierter Textblock) — eine feste Gesamthöhe aus unskalierten
    // Konstanten ließ bei abweichender Textgröße Luft unter der Play-Pille (anders als Library-/Home-Cards).
    .frame(width: w, alignment: .top)
    .fixedSize(horizontal: false, vertical: true)
    .background(tint)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous))
    .abstandHeroCardOutline(palette: model.appearancePalette)
    // `updatedAt` mit im Key: nach Cover-/Metadaten-Änderung die Hintergrundfarbe neu ableiten.
    .task(id: "\(book.id)|\(book.updatedAt?.timeIntervalSince1970 ?? 0)") {
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
    _tint = State(initialValue: seeded ?? model.appearancePalette.card)
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
        .accessibilityHint("Opens details")

        AppTheme.coverScrimGradient
        .frame(height: min(AppTheme.Layout.coverScrimHeight, h * 0.28))
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
        let isFinished = prog?.isFinished == true
        continueHeroPlayPill(
          model: model,
          libraryItemId: episode.libraryItemId,
          episodeId: episode.episodeId,
          accent: model.appearanceAccentColor,
          palette: model.appearancePalette,
          caption: playPillRemainingCaption
        ) {
          continueHeroPlayPillToggle(
            model: model,
            libraryItemId: episode.libraryItemId,
            episodeId: episode.episodeId,
            isFinished: isFinished
          ) {
            await model.playPodcastEpisode(
              episode,
              resumeAtOverride: isFinished ? 0 : nil
            )
          }
        }
      }
      .background(tint)
    }
    // Höhe aus dem Inhalt (Cover + skalierter Textblock) — eine feste Gesamthöhe aus unskalierten
    // Konstanten ließ bei abweichender Textgröße Luft unter der Play-Pille (anders als Library-/Home-Cards).
    .frame(width: w, alignment: .top)
    .fixedSize(horizontal: false, vertical: true)
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
  static let edgeInset: CGFloat = AppTheme.Layout.inlineSpacing
  static let iconFont: Font = .title3.weight(.semibold)
  static let contentPadding: CGFloat = AppTheme.Layout.cardPadding
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
  // Kachelhöhe ist Teil der Grid-Mathematik (siehe `AbstandFixedBrowseStripSectionsLayout`) und darf
  // nicht mitwachsen. Statt den Text abzuschneiden: Skalierung bis `accessibility1` zulassen und dort
  // deckeln — ohne Deckel kollidiert die größte AX-Stufe mit der festen Höhe.
  .dynamicTypeSize(...DynamicTypeSize.accessibility1)
  .clipShape(cardShape)
  .abstandCardElevation(.standard)
  .overlay(alignment: .topTrailing) {
    if let c = count, c > 0 {
      ContinueListeningHeroCoverPill {
        Text("\(c) Books")
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          // Bewusst Weiß statt Palette: liegt auf der dunklen Pill-Kapsel (`coverPlayBadgeBackground`), nicht auf Kartenfläche.
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
        VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
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
    .abstandCardChrome(model.appearancePalette.card, shape: LibraryRowLayout.cardShape)
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
    // Gleiche Zeilenhülle wie Buch-/Folgen-Zeilen; Tap übernimmt der umgebende Button des Aufrufers.
    return LibraryRowLayout.libraryRowCardChrome(
      cardColor: palette.card,
      showsBottomProgressBar: false,
      progressValue: 0,
      openDetails: nil
    ) {
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
          VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
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
                  Text(episodes == 1 ? "1 episode" : "\(episodes) episodes")
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
    }
    .abstandThemeRefresh()
  }

  @ViewBuilder
  private var downloadIcon: some View {
    if !showsDownloadStatus {
      EmptyView()
    } else if model.downloadedItemIds.contains(show.id) {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(model.appearancePalette.textSecondary)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if model.downloads.activeItemId == show.id {
      ProgressView(value: model.downloads.progress)
        .frame(width: AppTheme.Layout.compactIconButtonSize)
        .tint(model.appearancePalette.textSecondary)
        .accessibilityLabel("Downloading")
    } else if model.downloads.queuedItemIds.contains(show.id) {
      Image(systemName: "circle.dashed")
        .foregroundStyle(model.appearancePalette.textSecondary)
        .font(.caption)
        .accessibilityLabel("Queued")
    }
  }
}

// MARK: - Library row layout (Cover bündig links/oben/unten)

/// Liest `AppTheme` (MainActor-Zustand) und liefert View-Bausteine — gehört damit auf den MainActor.
@MainActor
enum LibraryRowLayout {
  // Reine Layout-Konstanten — nonisolated, damit sie auch außerhalb des MainActors lesbar bleiben.
  nonisolated static let coverSide = AppTheme.Layout.libraryRowCoverSide
  /// Gleicher Radius wie die Home-Cover-Cards — Zeilen und Karten wirken als eine Familie.
  nonisolated static let cornerRadius = AppTheme.Layout.continueHeroCardCornerRadius
  nonisolated static let cardInset = AppTheme.Layout.libraryRowCardInset
  /// Beendete Titel: Cover, Text, Häkchen und Play-Pille zurückgenommen (Download-Status bleibt voll).
  nonisolated static let finishedContentOpacity: Double = 0.35
  nonisolated static let textInset = AppTheme.Layout.libraryRowTextInset

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
    rowHeight: CGFloat = LibraryRowLayout.coverSide,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .frame(height: metadataMinHeight(showsProgressBar: showsProgressBar, rowHeight: rowHeight))
      // Feste Texthöhe neben dem Cover — wie bei der Facet-Kachel bis `accessibility1` skalieren
      // und dort deckeln, statt bei den größten AX-Stufen Titel/Meta zu beschneiden.
      .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
  static func metadataMinHeight(
    showsProgressBar: Bool,
    rowHeight: CGFloat = LibraryRowLayout.coverSide
  ) -> CGFloat {
    rowHeight - textInset - bodyBottomInset(showsProgressBar: showsProgressBar)
  }

  /// Kartenhülle: volle Fläche (inkl. Leerzonen) öffnet Details; Play bleibt eigener Button.
  @ViewBuilder
  static func libraryRowCardChrome<Content: View>(
    cardColor: Color,
    showsBottomProgressBar: Bool,
    progressValue: Double,
    openDetails: (() -> Void)? = nil,
    rowHeight: CGFloat = LibraryRowLayout.coverSide,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let base = VStack(alignment: .leading, spacing: 0) {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: rowHeight, alignment: .top)
        .padding(.leading, 0)
    }
    .overlay(alignment: .bottom) {
      bottomProgressOverlay(value: progressValue, visible: showsBottomProgressBar)
        .allowsHitTesting(false)
    }
    .abstandCardChrome(cardColor, shape: cardShape)
    // Wie Home-Cards: dezente Kante statt Schatten.
    .environment(\.abstandCardShadowEnabled, false)
    .contentShape(cardShape)
    .overlay {
      cardShape.strokeBorder(AppTheme.palette.textSecondary.opacity(0.22), lineWidth: AppTheme.Layout.hairlineWidth)
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
    alignment: VerticalAlignment = .center,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(alignment: alignment, spacing: AppTheme.Layout.inlineSpacing) {
      HStack(spacing: AppTheme.Layout.inlineSpacing) {
        leading()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: AppTheme.Layout.compactSpacing) {
        trailing()
      }
      .fixedSize(horizontal: true, vertical: false)
    }
  }

  /// Linke Fußzeile in einer Box der Textzeilen-Höhe (`.subheadline`) — bleibt auf gleicher Höhe,
  /// auch wenn rechts die höhere Play-Pille steht (Footer unten ausgerichtet).
  static func footerLeadingSlot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    ZStack(alignment: .leading) {
      Text(verbatim: " ")
        .font(.subheadline)
        .hidden()
        .accessibilityHidden(true)
      HStack(spacing: AppTheme.Layout.compactSpacing) {
        content()
      }
    }
  }
}

/// „Fertig“ + Download-Status oben rechts in kompakten Zeilen — schlichte Icons wie früher im Footer.
private struct LibraryRowStatusBadges: View {
  /// Sekundäre Textfarbe (Palette) — Status-Icons treten hinter Titel und Play-Pille zurück.
  let color: Color
  let isFinished: Bool
  let isDownloaded: Bool
  let isDownloading: Bool
  let downloadProgress: Double

  var body: some View {
    HStack(spacing: AppTheme.Layout.compactSpacing) {
      if isFinished {
        // Beendet: Häkchen wie Text und Cover zurückgenommen; Download-Status bleibt voll sichtbar.
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

/// Play/Pause als Akzent-Pille ohne Laufzeit — rechts unten in kompakten Zeilen.
/// Beobachtet gezielt nur Player-Identität + `isPlaying` (die Zeile selbst hält `model` unbeobachtet)
/// und schaltet beim Tippen sofort optimistisch um — sonst hinge das Icon am nächsten Zeilen-Rerender.
private struct LibraryRowPlayPill: View {
  let model: AppModel
  let libraryItemId: String
  let episodeId: String?
  let accent: Color
  let action: () -> Void

  @State private var showsPause = false
  /// Einmal im init gebaut — ein pro Render neu erzeugter Publisher würde bei jedem Update neu
  /// abonniert und den optimistischen Zustand sofort mit dem alten Wert überschreiben.
  private let playerState: AnyPublisher<Bool, Never>

  init(
    model: AppModel,
    libraryItemId: String,
    episodeId: String?,
    accent: Color,
    action: @escaping () -> Void
  ) {
    self.model = model
    self.libraryItemId = libraryItemId
    self.episodeId = episodeId
    self.accent = accent
    self.action = action
    playerState = playbackActivePublisher(model: model, libraryItemId: libraryItemId, episodeId: episodeId)
  }

  /// Scheitert die Aktion ohne Player-Änderung (offline, Fehler), käme kein Event — dann nach kurzer
  /// Zeit auf den echten Zustand zurückfallen, statt dauerhaft „Pause“ zu zeigen.
  private func reconcileAfterOptimisticToggle() {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      showsPause = model.player.isPlaying
        && model.isActivelyPlayingMedia(libraryItemId: libraryItemId, episodeId: episodeId)
    }
  }

  var body: some View {
    Button {
      showsPause.toggle()
      action()
      reconcileAfterOptimisticToggle()
    } label: {
      Image(systemName: showsPause ? "pause.fill" : "play.fill")
        .font(.caption.weight(.bold))
        .foregroundStyle(model.appearancePalette.foregroundOnAccent(accent))
        .padding(.horizontal, AppTheme.Layout.cardPadding)
        .padding(.vertical, AppTheme.Layout.stackSpacing)
        .background(accent, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(showsPause ? "Pause" : "Play")
    .onAppear {
      showsPause = model.player.isPlaying
        && model.isActivelyPlayingMedia(libraryItemId: libraryItemId, episodeId: episodeId)
    }
    .onReceive(playerState) { showsPause = $0 }
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
      HStack(spacing: AppTheme.Layout.compactSpacing) {
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
        .frame(width: AppTheme.Layout.compactIconButtonSize)
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
            // Identität am Item, nicht an der Rasterposition — sonst behalten Karten nach
            // Umsortieren/Filtern ihren `@State` (Live-Zustand des vorherigen Titels).
            card(items[index])
              .id(items[index].id)
              .frame(maxWidth: .infinity)
          } else {
            Color.clear
              .frame(maxWidth: .infinity, maxHeight: AppTheme.Layout.hairlineWidth)
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

/// Wählt kompakte Zeile oder Cover-Karte gemäß `libraryBookCardStyle`.
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
          opensDetailOnTap: opensDetailOnTap
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

/// Library-Cover-Karte im Continue-Hero-Stil (Rasterzelle).
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
    coverAspectRatio: CGFloat = 1
  ) {
    self.showEbookBadge = showEbookBadge
    self.usesEbookProgressDisplay = usesEbookProgressDisplay
    self.progressOverride = progressOverride
    self.authorLineOverride = authorLineOverride
    self.showsDownloadStatus = showsDownloadStatus
    self.opensDetailOnTap = opensDetailOnTap
    self.coverAspectRatio = coverAspectRatio
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

  /// Nur reine eBooks bekommen ein Typ-Badge — Hörbücher haben die Play-Pille unter dem Cover,
  /// ein zusätzliches Play-Badge auf dem Cover wäre doppelt.
  private var typeBadgeSystemImage: String? {
    if book.isPureEbookLibraryItem { return "book.closed.fill" }
    return nil
  }

  @ViewBuilder
  private var typeBadge: some View {
    if let systemImage = typeBadgeSystemImage {
      ContinueListeningHeroCoverPill {
        Image(systemName: systemImage)
          .font(ContinueListeningHeroCoverPillMetrics.iconFont)
          // Bewusst Weiß statt Palette: liegt auf der dunklen Pill-Kapsel (`coverPlayBadgeBackground`), nicht auf Kartenfläche.
          .foregroundStyle(.white)
      }
      .accessibilityLabel("eBook")
      .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var ebookAvailableBadge: some View {
    if showsAttachedEbookCoverBadge {
      ContinueListeningHeroCoverPill {
        Image(systemName: "book.closed.fill")
          .font(ContinueListeningHeroCoverPillMetrics.iconFont)
          // Bewusst Weiß statt Palette: liegt auf der dunklen Pill-Kapsel (`coverPlayBadgeBackground`), nicht auf Kartenfläche.
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

  /// Anzeige in der Play-Pille: Restlaufzeit (ohne Fortschritt = volle Dauer).
  private var playPillRemainingCaption: String {
    let total = max(0, resolvedTotalDurationSeconds)
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

    heroCardWithMetadata(palette: palette, coverInset: coverInset, barH: barH)
    .background(palette.card)
    .clipShape(fullClip)
    .abstandHeroCardOutline(palette: palette)
    .frame(maxWidth: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityHint(opensDetailOnTap ? "Opens book details." : "")
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

      Group {
      if book.isPlayableAudiobook {
        // Wie Continue Listening / Podcast-Cover: Dauer als Play-Pille → Play↔Pause wie Detail.
        ContinueListeningHeroTextBlock(
          title: book.displayTitle,
          detailLabel: "Author",
          detailValue: authorLine,
          horizontalInset: coverInset,
          onTitleTap: {
            if opensDetailOnTap {
              showDetail = true
            }
          }
        ) {
          let isFinished = prog?.isFinished == true
          continueHeroPlayPill(
            model: model,
            libraryItemId: book.id,
            episodeId: nil,
            accent: model.appearanceAccentColor,
            palette: palette,
            caption: playPillRemainingCaption
          ) {
            continueHeroPlayPillToggle(
              model: model,
              libraryItemId: book.id,
              episodeId: nil,
              isFinished: isFinished
            ) {
              await model.play(
                book: book,
                resumeAtOverride: isFinished ? 0 : nil
              )
            }
          }
        }
        .background(palette.card)
      } else {
        // eBook / nicht abspielbar: bisheriger Footer mit Lesefortschritt.
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
            onToggleFinished: nil
          )
        }
        .background(palette.card)
      }
      }
      .opacity(finishedContentOpacity)
    }
  }

  /// Beendet: Cover und Text zurücknehmen (wie kompakte Zeilen).
  private var finishedContentOpacity: Double {
    isFinished ? LibraryRowLayout.finishedContentOpacity : 1
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
      .opacity(finishedContentOpacity)
      .onTapGesture {
        if opensDetailOnTap {
          showDetail = true
        }
      }
      .accessibilityLabel(book.displayTitle)
      .accessibilityHint(opensDetailOnTap ? "Opens book details." : "")

      if showsProgressChrome {
        AppTheme.coverScrimGradient
        .frame(height: AppTheme.Layout.coverScrimHeight)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)

        Group {
          if usesEbookMetrics, live.isPreparingEbook {
            ProgressView()
              // Bewusst Weiß statt Palette: Balken sitzt auf dem Cover-Scrim über beliebigem Artwork.
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
        if isFinished {
          LibraryHeroFinishedBadge()
            .fixedSize()
        }
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

/// „Beendet“ auf Cover-Karten — gleiche Kapsel wie das Download-Badge, zurückgenommen wie der Rest
/// einer beendeten Karte (Download-Status bleibt voll sichtbar).
private struct LibraryHeroFinishedBadge: View {
  var body: some View {
    ContinueListeningHeroCoverPill {
      Image(systemName: "checkmark.circle.fill")
        .font(ContinueListeningHeroCoverPillMetrics.iconFont)
        // Bewusst Weiß statt Palette: liegt auf der dunklen Badge-Kapsel über beliebigem Cover-Artwork.
        .foregroundStyle(.white)
    }
    .opacity(LibraryRowLayout.finishedContentOpacity)
    .accessibilityLabel("Finished")
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
      // Bewusst Weiß statt Palette: liegt auf der dunklen Badge-Kapsel über beliebigem Cover-Artwork.
      .foregroundStyle(.white)
      .frame(width: AppTheme.Layout.coverBadgeSize, height: AppTheme.Layout.coverBadgeSize)
      .background(model.appearancePalette.coverPlayBadgeBackground)
      .clipShape(Circle())
      .padding(AppTheme.Layout.tightSpacing)
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
      cardColor: model.appearancePalette.card,
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
          } else {
            libraryRowCoverWithPlayBadge
          }
        }
        .opacity(rowFinishedContentOpacity)

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
      // Hörbücher: Play sitzt als Pille rechts unten auf der Karte — nur eBooks behalten ihr Cover-Badge.
      if isPureEbookRow {
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

  /// Titel mit „Fertig“-/Download-Kapsel oben rechts in der Karte.
  private var libraryRowTitleText: some View {
    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Layout.compactSpacing) {
      Text(book.displayTitle)
        .font(.headline.weight(.semibold))
        .foregroundStyle(model.appearancePalette.textPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(rowFinishedContentOpacity)
        .frame(maxWidth: .infinity, alignment: .leading)
      LibraryRowStatusBadges(
        color: model.appearancePalette.textSecondary,
        isFinished: rowIsFinished,
        isDownloaded: showsDownloadStatus && live.isDownloaded,
        isDownloading: showsDownloadStatus && live.isDownloading,
        downloadProgress: live.downloadProgress
      )
    }
  }

  /// Beendeter Titel: Text und Play-Pille zurücknehmen (Cover und Status-Icons bleiben voll).
  private var rowFinishedContentOpacity: Double {
    rowIsFinished ? LibraryRowLayout.finishedContentOpacity : 1
  }

  private var rowIsFinished: Bool {
    if usesEbookMetrics {
      guard let f = ebookProgress else { return false }
      return f >= 0.995
    }
    return prog?.isFinished == true
  }

  private var libraryRowInteractiveMetadataBlock: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
      libraryRowTitleText
      BookCollapsedAuthorLine(book: book, authorOverride: authorLineOverride)
        .opacity(rowFinishedContentOpacity)
      Spacer(minLength: 0)
      libraryRowMetaFooter
    }
    .padding(.trailing, AppTheme.Layout.tightSpacing)
  }

  private var libraryRowStaticMetadataBlock: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
      libraryRowTitleText
      BookCollapsedAuthorLine(book: book, authorOverride: authorLineOverride)
        .opacity(rowFinishedContentOpacity)
      Spacer(minLength: 0)
      libraryRowMetaFooter
    }
    .padding(.trailing, AppTheme.Layout.tightSpacing)
  }

  @ViewBuilder
  private var libraryRowMetaFooter: some View {
    LibraryRowLayout.metadataFooter(alignment: .bottom) {
      LibraryRowLayout.footerLeadingSlot {
        Group {
        if usesEbookMetrics {
          if let label = ebookProgressLabel {
            Text(label)
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(model.appearancePalette.textSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
        } else {
          Text(formatPlaybackTime(book.media.duration ?? 0))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(model.appearancePalette.textSecondary)
        }
        }
        .opacity(rowFinishedContentOpacity)
      }
    } trailing: {
      if showsAudiobookPlayControl, !usesEbookMetrics {
        LibraryRowPlayPill(
          model: model,
          libraryItemId: book.id,
          episodeId: nil,
          accent: themeAccent
        ) {
          let isFinished = prog?.isFinished == true
          continueHeroPlayPillToggle(
            model: model,
            libraryItemId: book.id,
            episodeId: nil,
            isFinished: isFinished
          ) {
            await model.play(book: book, resumeAtOverride: isFinished ? 0 : nil)
          }
        }
        .opacity(rowFinishedContentOpacity)
      }
    }
  }
}
