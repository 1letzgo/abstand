import SwiftUI
import UIKit

// MARK: - Podcast episode detail view

struct PodcastEpisodeDetailView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let episode: ABSPodcastEpisodeListItem
  @State private var detail: ABSPodcastEpisodeExpandedDetail?
  @State private var coverTintColor: Color = AppTheme.background
  @State private var coverImageForTint: UIImage?
  /// Persistierter Cover-Durchschnitts-RGB (`DetailCoverAverageRGBCache`) — Seed beim Öffnen,
  /// bevor das Hero-Cover geladen ist; auch Basis für Theme-Wechsel ohne Bild im Speicher.
  @State private var cachedCoverAverageRGB: (r: Double, g: Double, b: Double)?
  @State private var sessionsExpanded = false
  @State private var descriptionExpanded = false
  @State private var showNotesExpanded = false
  @State private var listeningSessions: [ABSListeningSession] = []
  @State private var confirmDiscardEpisodeProgress = false
  @State private var confirmMarkEpisodeFinished = false
  @State private var confirmMarkEpisodeUnfinished = false
  @State private var didSeedCoverTintFromCache = false

  private var prog: ABSUserMediaProgress? { model.progressByItemId[episode.progressLookupKey] }

  /// Der persistierte Cover-Durchschnitt steht bereits vor `.onAppear` und `.task` zur Verfügung.
  private var resolvedCoverTint: Color {
    let scope = model.coverImageCacheScopeId(for: episode.libraryItemId, tier: .hero)
    return CoverDominantTintSeed.resolve(
      account: model.coverImageCacheAccountDirectory(),
      itemId: episode.libraryItemId,
      heroScopeId: scope,
      fallbackScopeId: episode.libraryItemId,
      revision: model.coverImageCacheRevision
    )?.tint ?? coverTintColor
  }

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
            detailBelowPlaySection(d)
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
        Task {
          await model.discardPodcastEpisodeProgress(episode)
          // Sessions wurden serverseitig mitgelöscht — Liste in der Detail-View nachziehen.
          let showMid =
            model.podcastShows.first(where: { $0.id == episode.libraryItemId })?.mediaId
            ?? model.podcastSearchBooks.first(where: { $0.id == episode.libraryItemId })?.mediaId
          listeningSessions = await model.loadPodcastEpisodeListeningSessions(
            episode, showMediaId: showMid)
        }
      }
    } message: {
      Text("This removes your saved position and listening sessions for this episode. You cannot undo this.")
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
    // Erste Wahl: der beim letzten Besuch persistierte Cover-Durchschnitts-RGB — liefert exakt
    // denselben Tint wie nach dem Cover-Download (sofort, ohne Fetch/CIAreaAverage).
    if let rgb = DetailCoverAverageRGBCache.load(account: account, itemId: episode.libraryItemId) {
      cachedCoverAverageRGB = rgb
      coverTintColor = coverDominantBackgroundTint(
        fromAverageRed: rgb.r, green: rgb.g, blue: rgb.b)
      return
    }
    // Fallback: Hero-Karten-Tint als Näherung, bis `loadCoverTint()` den echten Wert liefert.
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
    } else if let rgb = cachedCoverAverageRGB {
      // Theme-Wechsel ohne Bild im Speicher: Tint aus dem persistierten RGB mit neuer Palette.
      coverTintColor = coverDominantBackgroundTint(
        fromAverageRed: rgb.r, green: rgb.g, blue: rgb.b)
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
        if let (r, g, b) = coverAverageRGB(from: image) {
          cachedCoverAverageRGB = (Double(r), Double(g), Double(b))
          DetailCoverAverageRGBCache.save(
            account: model.coverImageCacheAccountDirectory(),
            itemId: episode.libraryItemId,
            red: Double(r), green: Double(g), blue: Double(b)
          )
        }
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
    DetailHeroCoverFrame {
      SquareCoverImageView(
        url: model.coverURL(for: episode.libraryItemId, tier: .hero),
        token: model.token,
        itemId: episode.libraryItemId,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheScopeId: model.coverImageCacheScopeId(for: episode.libraryItemId, tier: .hero),
        cacheRevision: model.coverImageCacheRevision
      )
    }
  }

  private var infoSection: some View {
    DetailHeroInfoSection(
      title: episode.episodeTitle,
      subtitle: heroShowLinks.isEmpty ? fallbackShowSubtitle : nil,
      authorLinks: heroShowLinks,
      onAuthorTap: { showId, _ in
        Task {
          await model.openPodcastShowCatalog(showId: showId)
          dismiss()
        }
      },
      tertiaryParts: [episodeDurationLabel, episodePublishedYearLabel]
    )
  }

  private var heroShowLinks: [(id: String, name: String)] {
    let name = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name != "—" else { return [] }
    let showId = episode.libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !showId.isEmpty else { return [] }
    return [(showId, name)]
  }

  private var fallbackShowSubtitle: String? {
    let name = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name != "—" else { return nil }
    return name
  }

  private var episodePublishedYearLabel: String {
    guard let pub = detail?.pubDate?.trimmingCharacters(in: .whitespacesAndNewlines), !pub.isEmpty else {
      return ""
    }
    if pub.count >= 4, pub.prefix(4).allSatisfy(\.isNumber) {
      return String(pub.prefix(4))
    }
    return pub
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

  private func detailBelowPlaySection(_ d: ABSPodcastEpisodeExpandedDetail) -> some View {
    let isFinished = prog?.isFinished == true
    let episodeText = episodePlainDescription(d)
    let showNotesText = episodePlainShowNotes(d)
    let subtitle = trimmedMetaValue(d.subtitle)
    let publishedLine = trimmedMetaValue(d.pubDate)
    let categories = resolvedCategories(d)

    return VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.sectionCardSpacing) {
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

      VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.sectionCardSpacing) {
        if let episodeText {
          DetailDetailSectionCard {
            DetailMetaField(title: "Description") {
              DetailMetaExpandableTextBlock(text: episodeText, isExpanded: $descriptionExpanded)
            }
          }
        }

        if !d.showAuthors.isEmpty {
          DetailDetailSectionCard {
            DetailMetaField(title: d.showAuthors.count == 1 ? "Host" : "Hosts") {
              VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.linkRowSpacing) {
                ForEach(d.showAuthors, id: \.id) { author in
                  DetailAuthorLinkRow(authorId: author.id, name: author.name) {
                    model.openPodcastSearchFromText(author.name)
                    dismiss()
                  }
                }
              }
            }
          }
        }

        if let subtitle {
          DetailDetailSectionCard {
            DetailMetaField(title: "Subtitle") {
              DetailMetaTextBlock(text: subtitle)
            }
          }
        }

        if let publishedLine {
          DetailDetailSectionCard {
            DetailMetaField(title: "Published") {
              DetailMetaTextBlock(text: publishedLine)
            }
          }
        }

        if !categories.isEmpty {
          DetailDetailSectionCard {
            DetailMetaField(title: "Categories") {
              DetailMetaTextBlock(text: categories.joined(separator: ", "))
            }
          }
        }

        if let showNotesText {
          DetailDetailSectionCard {
            DetailMetaField(title: "Show notes") {
              DetailMetaExpandableTextBlock(text: showNotesText, isExpanded: $showNotesExpanded)
            }
          }
        }

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
      .padding(.top, AppTheme.Layout.detailMetaAfterPlaySpacing)
    }
  }

  private func episodePlainDescription(_ d: ABSPodcastEpisodeExpandedDetail) -> String? {
    absPlainText(fromHTML: d.episodeDescriptionHTML).nilIfEmpty
  }

  private func episodePlainShowNotes(_ d: ABSPodcastEpisodeExpandedDetail) -> String? {
    absPlainText(fromHTML: d.showDescriptionHTML).nilIfEmpty
  }

  private func trimmedMetaValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, t != "—" else { return nil }
    return t
  }

  private func resolvedCategories(_ d: ABSPodcastEpisodeExpandedDetail) -> [String] {
    (d.showGenres ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
