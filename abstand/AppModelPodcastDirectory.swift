import Foundation

/// Verzeichnis-Vorschau („Add podcast“): Sendungsinfos + alle Feed-Folgen einer Sendung,
/// die noch **nicht** in der Bibliothek liegt. Datenquelle ist derselbe Server-Endpunkt wie
/// beim RSS-Tab abonnierter Sendungen (`POST /api/podcasts/feed`) — nur ohne Library-Item.
extension AppModel {
  /// Cache-Schlüssel eines Treffers (normalisierte Feed-URL); `nil` ohne Feed-URL.
  func podcastDirectoryPreviewKey(for hit: ABSPodcastDirectorySearchHit) -> String? {
    Self.normalizedPodcastFeedURL(hit.feedUrl)
  }

  func podcastDirectoryPreview(for hit: ABSPodcastDirectorySearchHit) -> ABSPodcastFeedPreview? {
    guard let key = podcastDirectoryPreviewKey(for: hit) else { return nil }
    return podcastDirectoryPreviewByFeedURL[key]
  }

  func podcastDirectoryPreviewIsLoading(for hit: ABSPodcastDirectorySearchHit) -> Bool {
    guard let key = podcastDirectoryPreviewKey(for: hit) else { return false }
    return podcastDirectoryPreviewLoadingFeedURLs.contains(key)
  }

  func podcastDirectoryPreviewError(for hit: ABSPodcastDirectorySearchHit) -> String? {
    guard let key = podcastDirectoryPreviewKey(for: hit) else {
      return "This result has no RSS feed URL, so its episodes cannot be loaded."
    }
    return podcastDirectoryPreviewErrorByFeedURL[key]
  }

  /// Bibliotheks-Sendung zum Verzeichnis-Treffer (gleiche Feed-URL) — für „In library“ + Sprung dorthin.
  func podcastLibraryShowMatchingDirectoryHit(_ hit: ABSPodcastDirectorySearchHit) -> ABSBook? {
    guard let hitFeed = Self.normalizedPodcastFeedURL(hit.feedUrl) else { return nil }
    return podcastShows.first { show in
      Self.normalizedPodcastFeedURL(show.media.metadata.feedUrl) == hitFeed
    }
  }

  // MARK: Einzeldownload von Feed-Folgen

  /// Schlüssel für Fortschritts-/Erledigt-Zustand einer Feed-Folge.
  func podcastDirectoryEpisodeKey(
    for episode: ABSPodcastFeedPreviewEpisode,
    hit: ABSPodcastDirectorySearchHit
  ) -> String? {
    guard let feedKey = podcastDirectoryPreviewKey(for: hit) else { return nil }
    return "\(feedKey)|\(episode.id)"
  }

  /// Nur Server-Verwalter dürfen Folgen in die Bibliothek laden — wie im RSS-Tab.
  var podcastDirectoryCanDownloadEpisodes: Bool { podcastCanManageShowsOnServer }

  func podcastDirectoryEpisodeIsInLibrary(
    _ episode: ABSPodcastFeedPreviewEpisode,
    hit: ABSPodcastDirectorySearchHit
  ) -> Bool {
    guard let show = podcastLibraryShowMatchingDirectoryHit(hit) else { return false }
    return podcastDirectoryLibraryEpisodeTitlesByShowId[show.id]?
      .contains(episode.normalizedTitleKey) ?? false
  }

  /// Folgentitel der bereits abonnierten Sendung holen, damit vorhandene Folgen keinen
  /// Download-Button bekommen. Nur ein Request und nur, wenn die Sendung in der Bibliothek liegt.
  func loadPodcastDirectoryLibraryEpisodeTitles(
    for hit: ABSPodcastDirectorySearchHit,
    forceReload: Bool = false
  ) async {
    guard let show = podcastLibraryShowMatchingDirectoryHit(hit) else { return }
    if !forceReload, podcastDirectoryLibraryEpisodeTitlesByShowId[show.id] != nil { return }
    guard let c = client, isNetworkReachable else { return }
    do {
      let full = try await c.item(id: show.id, expanded: true)
      guard !Task.isCancelled else { return }
      let titles = Set(
        (full.media.podcastEpisodes ?? []).compactMap {
          $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nilIfEmpty
        }
      )
      podcastDirectoryLibraryEpisodeTitlesByShowId[show.id] = titles
    } catch {
      // Stiller Fehlschlag: ohne Liste zeigen wir den Download-Button, der Server lehnt
      // Doppellieferungen ohnehin nicht ab, sondern überschreibt nichts.
    }
  }

  /// Eine einzelne Feed-Folge auf den Server laden (`POST /api/podcasts/:id/download-episodes`).
  /// Setzt eine abonnierte Sendung voraus — Audiobookshelf kennt Folgen nur innerhalb eines
  /// Library-Items. Rückgabe `false` = nichts angestoßen (Fehler steht in `errorMessage`).
  @discardableResult
  func downloadPodcastDirectoryEpisode(
    _ episode: ABSPodcastFeedPreviewEpisode,
    hit: ABSPodcastDirectorySearchHit
  ) async -> Bool {
    guard podcastDirectoryCanDownloadEpisodes else { return false }
    guard episode.canDownloadToServer else { return false }
    guard let key = podcastDirectoryEpisodeKey(for: episode, hit: hit) else { return false }
    guard let show = podcastLibraryShowMatchingDirectoryHit(hit) else { return false }
    guard let c = client else { return false }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return false
    }
    guard !podcastDirectoryEpisodeDownloadInProgressKeys.contains(key) else { return false }
    guard !podcastDirectoryEpisodeDownloadRequestedKeys.contains(key) else { return false }

    podcastDirectoryEpisodeDownloadInProgressKeys.insert(key)
    defer { podcastDirectoryEpisodeDownloadInProgressKeys.remove(key) }
    do {
      let obj = try JSONSerialization.jsonObject(
        with: episode.episodePayloadJSON, options: [.fragmentsAllowed])
      let body = try JSONSerialization.data(withJSONObject: [obj])
      try await c.downloadPodcastEpisodesToLibrary(
        podcastLibraryItemId: show.id,
        episodesJsonArray: body
      )
      podcastDirectoryEpisodeDownloadRequestedKeys.insert(key)
      // Der Server lädt asynchron; die Titelliste erst danach neu holen wäre eine Wette.
      // Stattdessen den Titel sofort als vorhanden vormerken.
      var titles = podcastDirectoryLibraryEpisodeTitlesByShowId[show.id] ?? []
      titles.insert(episode.normalizedTitleKey)
      podcastDirectoryLibraryEpisodeTitlesByShowId[show.id] = titles
      errorMessage = nil
      return true
    } catch {
      publishErrorUnlessBenignCancellation(error)
      return false
    }
  }

  /// Feed einmal je Sendung laden (Cache bleibt für die Sitzung bestehen).
  func loadPodcastDirectoryPreview(
    for hit: ABSPodcastDirectorySearchHit,
    forceReload: Bool = false
  ) async {
    guard let key = podcastDirectoryPreviewKey(for: hit) else { return }
    if !forceReload, podcastDirectoryPreviewByFeedURL[key] != nil { return }
    guard !podcastDirectoryPreviewLoadingFeedURLs.contains(key) else { return }
    guard let c = client else { return }
    guard isNetworkReachable else {
      podcastDirectoryPreviewErrorByFeedURL[key] = "No network connection."
      return
    }

    podcastDirectoryPreviewLoadingFeedURLs.insert(key)
    podcastDirectoryPreviewErrorByFeedURL.removeValue(forKey: key)
    defer { podcastDirectoryPreviewLoadingFeedURLs.remove(key) }

    let requestFeedUrl =
      hit.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? key
    do {
      let data = try await c.fetchPodcastRssFeed(rssFeedUrl: requestFeedUrl)
      guard !Task.isCancelled else { return }
      var preview = try ABSPodcastFeedPreview.from(feedApiResponse: data)
      preview = preview.mergingDirectoryHitFallbacks(hit)
      podcastDirectoryPreviewByFeedURL[key] = preview
      podcastDirectoryPreviewErrorByFeedURL.removeValue(forKey: key)
    } catch is CancellationError {
      // Stille — View wurde verlassen.
    } catch {
      guard !Task.isCancelled else { return }
      podcastDirectoryPreviewErrorByFeedURL[key] = error.localizedDescription
    }
  }
}

extension ABSPodcastFeedPreview {
  /// Feeds lassen häufig Felder aus, die iTunes kennt (Autor, Cover, Kategorien, Beschreibung) —
  /// dann die Verzeichnisdaten des Treffers verwenden.
  func mergingDirectoryHitFallbacks(_ hit: ABSPodcastDirectorySearchHit) -> ABSPodcastFeedPreview {
    var merged = self
    if merged.title.isEmpty {
      merged.title = hit.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if merged.author?.isEmpty != false {
      merged.author = hit.artistName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
    if merged.descriptionPlain?.isEmpty != false {
      merged.descriptionPlain = absPlainText(fromHTML: hit.descriptionPlain).nilIfEmpty
    }
    if merged.imageUrl?.isEmpty != false {
      merged.imageUrl = hit.cover?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
    if merged.categories.isEmpty {
      merged.categories = (hit.genres ?? [])
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
    if merged.feedUrl?.isEmpty != false {
      merged.feedUrl = hit.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
    if merged.pageUrl?.isEmpty != false {
      merged.pageUrl = hit.pageUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
    if merged.explicit == false {
      merged.explicit = hit.explicit ?? false
    }
    return merged
  }
}
