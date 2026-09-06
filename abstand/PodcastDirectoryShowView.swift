import SwiftUI

/// Sendungsdetail im „Add podcast“-Flow: zeigt alles, was Verzeichnis **und** RSS-Feed über eine
/// noch nicht abonnierte Sendung hergeben — Beschreibung, Kategorien, Sprache, Feedtyp und die
/// vollständige Folgenliste inklusive Folgen, die noch nicht in der Bibliothek liegen.
///
/// Design folgt den Buch-/Folgen-Details: Hero (Cover + Titel), Aktionsbereich, Meta-Karten
/// (`DetailDetailSectionCard` + `DetailMetaField`) und eine Disclosure für die Folgen.
struct PodcastDirectoryShowView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.openURL) private var openURL

  let hit: ABSPodcastDirectorySearchHit

  @State private var descriptionExpanded = false
  @State private var episodesExpanded = true
  @State private var showsAllEpisodes = false
  @State private var expandedEpisodeIds: Set<String> = []
  @State private var subscribeFailed = false

  /// Erste Seite der Folgenliste — lange Feeds (oft 500+) bleiben scrollbar schnell.
  private let initialEpisodeCount = 20

  private var palette: AppColorPalette { model.appearancePalette }
  private var preview: ABSPodcastFeedPreview? { model.podcastDirectoryPreview(for: hit) }
  private var isLoading: Bool { model.podcastDirectoryPreviewIsLoading(for: hit) }
  private var loadError: String? { model.podcastDirectoryPreviewError(for: hit) }
  private var libraryShow: ABSBook? { model.podcastLibraryShowMatchingDirectoryHit(hit) }
  private var isInLibrary: Bool { libraryShow != nil }
  private var isSubscribing: Bool { model.podcastSubscribeInProgressDirectoryHitId == hit.id }

  private var displayTitle: String {
    let fromFeed = preview?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !fromFeed.isEmpty { return fromFeed }
    let raw = hit.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return raw.isEmpty ? "Podcast" : raw
  }

  private var displayAuthor: String? {
    (preview?.author ?? hit.artistName)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
  }

  private var coverURL: URL? {
    let raw = preview?.imageUrl ?? hit.cover
    return raw.flatMap(URL.init(string:))
  }

  /// Cache-Schlüssel wie in der Trefferliste — Cover ist beim Öffnen schon geladen.
  private var coverCacheItemId: String { "podcast-dir:\(hit.id)" }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.sectionCardSpacing) {
        heroSection
        subscribeSection
        feedStateSection
        metadataCards
        episodesSection
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom,
        AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset
      )
    }
    .abstandScrollScreenBackground(ignoreSafeArea: true)
    .navigationTitle(displayTitle)
    .navigationBarTitleDisplayMode(.inline)
    .tint(model.appearanceAccentColor)
    .themeAccentFromAppModel(model)
    .abstandThemeRefresh()
    .task(id: hit.id) {
      await model.loadPodcastDirectoryPreview(for: hit)
    }
    .refreshable {
      await model.loadPodcastDirectoryPreview(for: hit, forceReload: true)
    }
    .alert("Could not subscribe", isPresented: $subscribeFailed) {
      Button("OK", role: .cancel) { subscribeFailed = false }
    } message: {
      Text(model.errorMessage ?? "The show could not be added to your library.")
    }
  }

  // MARK: Hero

  @ViewBuilder
  private var heroSection: some View {
    VStack(spacing: DetailMetaLayoutMetrics.sectionCardSpacing) {
      DetailHeroCoverFrame {
        SquareCoverImageView(
          url: coverURL,
          token: model.token,
          itemId: coverCacheItemId,
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision,
          requiresAuthorization: false
        )
      }
      DetailHeroInfoSection(
        title: displayTitle,
        subtitle: displayAuthor,
        tertiaryParts: heroTertiaryParts
      )
    }
    .frame(maxWidth: .infinity)
  }

  /// „128 episodes · Latest Sep 2, 2026 · Explicit“ — nur vorhandene Angaben.
  private var heroTertiaryParts: [String] {
    var parts: [String] = []
    if let count = episodeCount {
      parts.append(count == 1 ? "1 episode" : "\(count) episodes")
    }
    if let latest = latestEpisodeLabel {
      parts.append("Latest \(latest)")
    }
    if preview?.explicit ?? hit.explicit ?? false {
      parts.append("Explicit")
    }
    return parts
  }

  private var episodeCount: Int? {
    if let preview, !preview.episodes.isEmpty { return preview.episodeCount }
    if let n = hit.trackCount, n > 0 { return n }
    return nil
  }

  private var latestEpisodeLabel: String? {
    guard let ms = preview?.latestEpisodePublishedAt, ms > 0 else { return nil }
    return Self.dateLabel(millis: ms)
  }

  // MARK: Subscribe

  @ViewBuilder
  private var subscribeSection: some View {
    VStack(spacing: DetailMetaLayoutMetrics.linkRowSpacing) {
      if isInLibrary {
        Button {
          guard let show = libraryShow else { return }
          Task { await model.openPodcastShowCatalog(showId: show.id) }
        } label: {
          Label("Open in library", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(AbstandPrimaryButtonStyle())
      } else {
        Button {
          Task {
            // Erfolg zeigt sich am Zustand („Open in library“) — der Feed-Cache bleibt gültig.
            if await model.subscribeToPodcastDirectoryHit(hit) == false {
              subscribeFailed = true
            }
          }
        } label: {
          HStack(spacing: 8) {
            if isSubscribing {
              ProgressView()
                .tint(palette.foregroundOnAccent(model.appearanceAccentColor))
            }
            Text(isSubscribing ? "Subscribing…" : "Subscribe")
          }
        }
        .buttonStyle(AbstandPrimaryButtonStyle())
        .disabled(!canSubscribe || isSubscribing)

        Text(subscribeHint)
          .font(.caption)
          .foregroundStyle(palette.textSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
    }
    .frame(maxWidth: AppTheme.Layout.readableFormMaxWidth)
    .frame(maxWidth: .infinity)
    .padding(.top, AppTheme.Layout.detailPlayButtonTopPadding)
  }

  private var canSubscribe: Bool {
    guard model.isNetworkReachable else { return false }
    return (hit.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
  }

  private var subscribeHint: String {
    if hit.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
      return "This result has no RSS feed URL and cannot be added."
    }
    if !model.isNetworkReachable {
      return "Connect to your server to add this show."
    }
    return "Adds the show to your Audiobookshelf library and downloads new episodes automatically."
  }

  // MARK: Feed load state

  @ViewBuilder
  private var feedStateSection: some View {
    if preview == nil {
      if isLoading {
        AbstandLoadingSpinner(verticalPadding: 32)
      } else if let loadError {
        DetailDetailSectionCard {
          DetailMetaField(title: "Feed") {
            VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.linkRowSpacing) {
              AbstandInlineNotice(text: loadError, isError: true)
              Button("Try again") {
                Task { await model.loadPodcastDirectoryPreview(for: hit, forceReload: true) }
              }
              .buttonStyle(AbstandProminentButtonStyle())
              .disabled(!model.isNetworkReachable)
            }
          }
        }
      }
    }
  }

  // MARK: Metadata cards

  @ViewBuilder
  private var metadataCards: some View {
    if let about = aboutText {
      DetailDetailSectionCard {
        DetailMetaField(title: "Description") {
          DetailMetaExpandableTextBlock(text: about, isExpanded: $descriptionExpanded)
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

    if !showDetailRows.isEmpty {
      DetailDetailSectionCard {
        VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.sectionCardSpacing) {
          ForEach(showDetailRows, id: \.title) { row in
            DetailMetaField(title: row.title) {
              DetailMetaTextBlock(text: row.value)
            }
          }
        }
      }
    }

    if let page = pageURL {
      DetailDetailSectionCard {
        DetailMetaField(title: "Links") {
          DetailMetaLink(title: "Open in Apple Podcasts") { openURL(page) }
        }
      }
    }
  }

  private var aboutText: String? {
    if let d = preview?.descriptionPlain, !d.isEmpty { return d }
    return absPlainText(fromHTML: hit.descriptionPlain).nilIfEmpty
  }

  private var categories: [String] {
    if let c = preview?.categories, !c.isEmpty { return c }
    return (hit.genres ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private var pageURL: URL? {
    (preview?.pageUrl ?? hit.pageUrl).flatMap(URL.init(string:))
  }

  /// Nur Zeilen mit Inhalt — leere Feed-Felder erzeugen keine leeren Karten.
  private var showDetailRows: [(title: String, value: String)] {
    var rows: [(title: String, value: String)] = []
    if let language = preview?.language?.nilIfEmpty {
      rows.append((title: "Language", value: language))
    }
    if let type = preview?.type?.nilIfEmpty {
      rows.append((title: "Feed type", value: type.capitalized))
    }
    if let total = preview?.totalDurationSeconds, total > 0 {
      rows.append((title: "Total runtime", value: formatPlaybackDurationShortHuman(total)))
    }
    if let release = hit.releaseDate?.nilIfEmpty, let label = Self.dateLabel(isoDay: release) {
      rows.append((title: "First release", value: label))
    }
    if let feed = (preview?.feedUrl ?? hit.feedUrl)?.nilIfEmpty {
      rows.append((title: "RSS feed", value: feed))
    }
    return rows
  }

  // MARK: Episodes

  @ViewBuilder
  private var episodesSection: some View {
    if let preview, !preview.episodes.isEmpty {
      DetailMetaDisclosure(title: "Episodes", isExpanded: $episodesExpanded) {
        VStack(alignment: .leading, spacing: 0) {
          let episodes = visibleEpisodes(from: preview.episodes)
          // Position als Identität — manche Feeds vergeben denselben GUID mehrfach.
          ForEach(Array(episodes.enumerated()), id: \.offset) { idx, episode in
            episodeRow(episode)
            if idx < episodes.count - 1 {
              Divider()
                .overlay(palette.textSecondary.opacity(0.15))
            }
          }
          if preview.episodes.count > initialEpisodeCount {
            Button(showsAllEpisodes ? "Show fewer episodes" : "Show all \(preview.episodes.count) episodes") {
              showsAllEpisodes.toggle()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(themeAccent)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DetailMetaLayoutMetrics.linkRowSpacing)
          }
        }
      }
      .tint(model.appearanceAccentColor)
    } else if preview != nil, !isLoading {
      DetailDetailSectionCard {
        DetailMetaField(title: "Episodes") {
          AbstandInlineNotice(text: "This feed does not list any episodes yet.")
        }
      }
    }
  }

  private func visibleEpisodes(
    from episodes: [ABSPodcastFeedPreviewEpisode]
  ) -> [ABSPodcastFeedPreviewEpisode] {
    guard !showsAllEpisodes, episodes.count > initialEpisodeCount else { return episodes }
    return Array(episodes.prefix(initialEpisodeCount))
  }

  @ViewBuilder
  private func episodeRow(_ episode: ABSPodcastFeedPreviewEpisode) -> some View {
    let expanded = expandedEpisodeIds.contains(episode.id)
    VStack(alignment: .leading, spacing: 4) {
      Text(episode.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let meta = episodeMetaLine(episode) {
        Text(meta)
          .font(.caption.monospacedDigit())
          .foregroundStyle(palette.textSecondary)
      }
      if let text = episode.descriptionPlain ?? episode.subtitle {
        Text(text)
          .font(.caption)
          .foregroundStyle(palette.textSecondary)
          .lineLimit(expanded ? nil : 2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .onTapGesture {
      if expanded {
        expandedEpisodeIds.remove(episode.id)
      } else {
        expandedEpisodeIds.insert(episode.id)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint(expanded ? "Collapse episode notes" : "Expand episode notes")
  }

  /// „Sep 2, 2026 · 48 min · S2 · E14 · Trailer“ — nur was der Feed liefert.
  private func episodeMetaLine(_ episode: ABSPodcastFeedPreviewEpisode) -> String? {
    var parts: [String] = []
    if let ms = episode.publishedAt, ms > 0 {
      parts.append(Self.dateLabel(millis: ms))
    }
    if let seconds = episode.durationSeconds, seconds > 0 {
      parts.append(formatPlaybackDurationShortHuman(seconds))
    }
    if let numbering = episode.numberingLabel {
      parts.append(numbering)
    }
    if let special = episode.specialTypeLabel {
      parts.append(special)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  // MARK: Date helpers

  private static func dateLabel(millis: Int64) -> String {
    Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
      .formatted(date: .abbreviated, time: .omitted)
  }

  /// iTunes liefert `releaseDate` als ISO-String — nur den Tag anzeigen.
  private static func dateLabel(isoDay value: String) -> String? {
    let day = String(value.prefix(10))
    guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
      return value.nilIfEmpty
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: day) else { return day }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}
