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
