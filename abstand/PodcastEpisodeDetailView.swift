import SwiftUI
import UIKit

// MARK: - Podcast episode detail view

struct PodcastEpisodeDetailView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.dismiss) private var dismiss
  let episode: ABSPodcastEpisodeListItem
  @State private var detail: ABSPodcastEpisodeExpandedDetail?
  @State private var coverTintColor: Color = AppTheme.background
  @State private var coverImageForTint: UIImage?
  @State private var sessionsExpanded = false
  @State private var listeningSessions: [ABSListeningSession] = []
  @State private var confirmDiscardEpisodeProgress = false
  @State private var confirmMarkEpisodeFinished = false
  @State private var confirmMarkEpisodeUnfinished = false
  @State private var didSeedCoverTintFromCache = false

  private var prog: ABSUserMediaProgress? { model.progressByItemId[episode.progressLookupKey] }

  /// `recentEpisode` in „items-in-progress" liefert oft keine Länge; die kommt dann aus `mediaProgress`.
  private var resolvedTotalDurationSeconds: Double {
    if episode.duration > 0 { return episode.duration }
    if let p = prog, p.duration > 0 { return p.duration }
    return 0
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        VStack(spacing: 0) {
          coverSection
          infoSection
          if let d = detail {
            detailActionsAndMeta(d)
          }
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
        episodeDetailUtilityToolbarItems
      }
    }
    .onChange(of: model.appearanceThemeRevision) { _, _ in
      applyCoverTintFromStoredImage()
    }
    .onAppear {
      seedEpisodeCoverTintFromCacheIfNeeded()
    }
    .task {
      seedEpisodeCoverTintFromCacheIfNeeded()
      // Sofort mit zuletzt gecachter Show-Detail-Antwort starten (Beschreibung bleibt sichtbar) —
      // kein Leerzustand mehr, nur ein stiller Refresh im Hintergrund.
      if detail == nil {
        detail = model.cachedPodcastEpisodeDetail(episode)
      }
      async let d = model.loadPodcastEpisodeDetail(episode)
      let showMid =
        model.podcastShows.first(where: { $0.id == episode.libraryItemId })?.mediaId
        ?? model.podcastSearchBooks.first(where: { $0.id == episode.libraryItemId })?.mediaId
      async let s = model.loadPodcastEpisodeListeningSessions(episode, showMediaId: showMid)
      if let loaded = await d { detail = loaded }
      listeningSessions = await s
      await loadCoverTint()
    }
    .alert("Reset listening progress?", isPresented: $confirmDiscardEpisodeProgress) {
      Button("Cancel", role: .cancel) {}
      Button("Reset", role: .destructive) {
        Task { await model.discardPodcastEpisodeProgress(episode) }
      }
    } message: {
      Text("This removes your saved position for this episode. You cannot undo this.")
    }
    .alert("Mark as finished?", isPresented: $confirmMarkEpisodeFinished) {
      Button("Cancel", role: .cancel) {}
      Button("Mark as finished") {
        Task { await model.markPodcastEpisodeFinished(episode) }
      }
    } message: {
      Text("Your current position will be saved as complete.")
    }
    .alert("Mark as not finished?", isPresented: $confirmMarkEpisodeUnfinished) {
      Button("Cancel", role: .cancel) {}
      Button("Mark as not finished") {
        Task { await model.markPodcastEpisodeUnfinished(episode) }
      }
    } message: {
      Text("You can resume from your saved position.")
    }
  }

  private func seedEpisodeCoverTintFromCacheIfNeeded() {
    guard !didSeedCoverTintFromCache else { return }
    didSeedCoverTintFromCache = true
    let fallback = model.appearancePalette.background
    guard let account = model.coverImageCacheAccountDirectory() else {
      coverTintColor = fallback
      return
    }
    if let cached = CoverDerivedTintLoader.colorFromDiskOrCoverCache(
      account: account,
      itemId: episode.libraryItemId
    ) {
      coverTintColor = cached
    } else {
      coverTintColor = fallback
    }
  }

  private func applyCoverTintFromStoredImage() {
    if let coverImageForTint {
      coverTintColor = coverDominantBackgroundTint(from: coverImageForTint)
    } else {
      coverTintColor = model.appearancePalette.background
    }
  }

  private func loadCoverTint() async {
    guard let url = model.coverURL(for: episode.libraryItemId, tier: .hero) else { return }
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
  private var episodeDetailUtilityToolbarItems: some View {
    let rowProgress = model.progressByItemId[episode.progressLookupKey]
    let canDiscardProgress: Bool = {
      guard let p = rowProgress else { return false }
      if p.isFinished { return true }
      if p.currentTime > 1 { return true }
      if p.duration > 0, p.progress > 0.001 { return true }
      return false
    }()
    let discardEnabled = canDiscardProgress && model.isNetworkReachable
    let sid = model.podcastEpisodeOfflineStorageId(episode)

    DetailToolbarDownloadItem(
      storageId: sid,
      onStartDownload: { model.startDownloadPodcastEpisode(episode) },
      onRemoveDownload: { model.removeLocalDownload(bookId: sid) }
    )

    DetailToolbarResetProgressItem(enabled: discardEnabled) {
      confirmDiscardEpisodeProgress = true
    }
    .tint(discardEnabled ? AppTheme.danger : AppTheme.textSecondary)
  }

  private var coverSection: some View {
    CoverImageView(
      url: model.coverURL(for: episode.libraryItemId, tier: .hero),
      token: model.token,
      itemId: episode.libraryItemId,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheScopeId: model.coverImageCacheScopeId(for: episode.libraryItemId, tier: .hero),
      cacheRevision: model.coverImageCacheRevision,
      contentMode: .fit
    )
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
    .padding(.top, DetailHeroLayoutMetrics.coverTopPadding)
  }

  private var infoSection: some View {
    VStack {
      Text(episode.episodeTitle)
        .font(DetailHeroTypography.heroTitle)
        .foregroundStyle(AppTheme.textPrimary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
      Text(episode.showTitle)
        .font(DetailHeroTypography.heroSubtitle)
        .foregroundStyle(AppTheme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
    .padding(.top, DetailHeroLayoutMetrics.titleTopSpacing)
  }

  private var episodePlayProgress01: Double {
    guard let p = prog else { return 0 }
    if p.isFinished { return 1 }
    if p.duration > 0 { return min(1, max(0, p.progress)) }
    let total = resolvedTotalDurationSeconds
    if total > 0 { return min(1, max(0, p.currentTime / total)) }
    return 0
  }

  private var episodeDurationLabel: String {
    let sec = resolvedTotalDurationSeconds
    guard sec > 0 else { return "—" }
    return formatPlaybackTime(sec)
  }

  private func detailActionsAndMeta(_ d: ABSPodcastEpisodeExpandedDetail) -> some View {
    let isFinished = prog?.isFinished == true
    return VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      DetailHeroActionsBar(
        actions: [
          DetailHeroMediaAction(
            id: "play",
            markSystemImage: isFinished ? "arrow.uturn.backward" : "checkmark",
            markAccessibilityLabel: isFinished ? "Mark as not finished" : "Mark as finished",
            markEnabled: true,
            onMark: {
              if isFinished {
                confirmMarkEpisodeUnfinished = true
              } else {
                confirmMarkEpisodeFinished = true
              }
            },
            kind: .play,
            progress01: episodePlayProgress01,
            isFinished: isFinished,
            primaryEnabled: true,
            onPrimary: {
              Task {
                await model.playPodcastEpisode(
                  episode,
                  resumeAtOverride: isFinished ? 0 : nil
                )
              }
            }
          ),
        ]
      )
      .padding(.top, AppTheme.Layout.detailPlayButtonTopPadding)
      .padding(.bottom, AppTheme.Layout.detailPlayButtonBottomPadding)

      if let show = model.podcastShows.first(where: { $0.id == episode.libraryItemId }) ?? model.podcastSearchBooks.first(where: { $0.id == episode.libraryItemId }) {
        Button {
          Task {
            await model.selectPodcastShowFilter(show.id)
            dismiss()
          }
        } label: {
          HStack(alignment: .top, spacing: 10) {
            Text("SHOW".uppercased())
              .font(DetailHeroTypography.metaLabel)
              .foregroundStyle(AppTheme.textSecondary)
              .frame(width: 112, alignment: .leading)
            Text(show.displayTitle)
              .font(DetailHeroTypography.metaLink)
              .foregroundStyle(themeAccent)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .buttonStyle(.plain)
      }
      detailMetaRow("Duration", episodeDurationLabel)
      if !d.showAuthors.isEmpty {
        HStack(alignment: .top, spacing: 10) {
          Text("HOST".uppercased())
            .font(DetailHeroTypography.metaLabel)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(width: 112, alignment: .leading)
          VStack(alignment: .leading, spacing: 4) {
            ForEach(d.showAuthors, id: \.id) { author in
              Button {
                model.openPodcastSearchFromText(author.name)
                dismiss()
              } label: {
                Text(author.name)
                  .font(DetailHeroTypography.metaLink)
                  .foregroundStyle(themeAccent)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .multilineTextAlignment(.leading)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      if let s = d.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
        detailMetaRow("Subtitle", s)
      }
      if let pub = d.pubDate?.trimmingCharacters(in: .whitespacesAndNewlines), !pub.isEmpty {
        detailMetaRow("Published", pub)
      }
      if let g = d.showGenres, !g.isEmpty {
        detailMetaRow("Categories", g.joined(separator: ", "))
      }
      detailMetaRow(
        "Episode",
        absPlainText(fromHTML: d.episodeDescriptionHTML).nilIfEmpty ?? "—")
      detailMetaRow(
        "Show notes",
        absPlainText(fromHTML: d.showDescriptionHTML).nilIfEmpty ?? "—")
      ListeningHistoryDisclosure(
        expanded: $sessionsExpanded,
        sessions: listeningSessions,
        isNetworkReachable: model.isNetworkReachable,
        emptyOnlineText: "No listening sessions recorded for this episode yet.",
        emptyOfflineText: "Listening history is unavailable offline.",
        onJumpToSessionStart: { session in
          Task {
            await model.playPodcastEpisode(episode, resumeAtOverride: session.startTime)
          }
        }
      )
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
}
