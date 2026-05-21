import Foundation

/// iTunes Podcast-Charts (öffentliche RSS/Lookup-APIs, vgl. Absorb).
enum ABSPodcastCharts {
  static let defaultLimit = 50

  /// Storefront für `itunes.apple.com/{country}/rss/...` — bevorzugt ABS-Server-Sprache.
  static func countryCode(serverLanguage: String?, locale: Locale = .current) -> String {
    let raw = serverLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if !raw.isEmpty {
      let parts = raw.split(separator: "-")
      if parts.count >= 2, parts[0] == "en" {
        let region = String(parts[1])
        if region == "gb" || region == "uk" { return "gb" }
        if region.count == 2 { return region }
        return "us"
      }
      if raw.count == 2 { return raw }
      switch raw {
      case "deutsch", "german": return "de"
      case "english": return "us"
      case "french", "français": return "fr"
      case "spanish", "español": return "es"
      case "italian": return "it"
      case "dutch": return "nl"
      case "japanese": return "jp"
      default: break
      }
    }
    return locale.region?.identifier.lowercased() ?? "us"
  }

  static func topPodcastsFeedURL(country: String, limit: Int = defaultLimit) -> URL? {
    let c = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !c.isEmpty else { return nil }
    return URL(string: "https://itunes.apple.com/\(c)/rss/toppodcasts/limit=\(limit)/json")
  }

  static func fetchTopPodcasts(country: String, limit: Int = defaultLimit) async throws -> [ABSPodcastDirectorySearchHit] {
    guard let url = topPodcastsFeedURL(country: country, limit: limit) else { return [] }
    var req = URLRequest(url: url, timeoutInterval: 30)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, nil)
    }
    let partial = try parseChartFeedJSON(data)
    return try await enrichWithLookup(partial)
  }

  // MARK: - RSS parse

  private static func parseChartFeedJSON(_ data: Data) throws -> [ABSPodcastDirectorySearchHit] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let feed = root["feed"] as? [String: Any]
    else { return [] }
    let entries: [[String: Any]]
    if let arr = feed["entry"] as? [[String: Any]] {
      entries = arr
    } else if let one = feed["entry"] as? [String: Any] {
      entries = [one]
    } else {
      return []
    }
    return entries.compactMap(parseChartEntry)
  }

  private static func parseChartEntry(_ entry: [String: Any]) -> ABSPodcastDirectorySearchHit? {
    guard let id = stringAttribute(entry, key: "id", attribute: "im:id"), !id.isEmpty else { return nil }
    let title = labelString(entry, key: "im:name") ?? ""
    let artist = labelString(entry, key: "im:artist")
    let summary = labelString(entry, key: "summary")
    let page = linkHref(entry)
    let cover = bestImageURL(entry)
    let genre = labelAttribute(entry, key: "category", attribute: "label")
    let genres = genre.map { [$0] }
    let release = labelAttribute(entry, key: "im:releaseDate", attribute: "label")
    return ABSPodcastDirectorySearchHit(
      id: id,
      title: title.isEmpty ? "Podcast" : title,
      artistName: artist,
      descriptionPlain: summary,
      releaseDate: release,
      genres: genres,
      cover: cover,
      feedUrl: nil,
      pageUrl: page,
      explicit: nil
    )
  }

  private static func labelString(_ dict: [String: Any], key: String) -> String? {
    guard let node = dict[key] as? [String: Any], let label = node["label"] as? String else { return nil }
    let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
  }

  private static func labelAttribute(_ dict: [String: Any], key: String, attribute: String) -> String? {
    guard let node = dict[key] as? [String: Any],
      let attrs = node["attributes"] as? [String: Any],
      let raw = attrs[attribute] as? String
    else { return nil }
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
  }

  private static func stringAttribute(_ dict: [String: Any], key: String, attribute: String) -> String? {
    guard let node = dict[key] as? [String: Any],
      let attrs = node["attributes"] as? [String: Any],
      let raw = attrs[attribute]
    else { return labelString(dict, key: key) }
    if let s = raw as? String {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      return t.isEmpty ? nil : t
    }
    if let i = raw as? Int { return "\(i)" }
    if let i = raw as? Int64 { return "\(i)" }
    return nil
  }

  private static func linkHref(_ entry: [String: Any]) -> String? {
    guard let link = entry["link"] as? [String: Any],
      let attrs = link["attributes"] as? [String: Any],
      let href = attrs["href"] as? String
    else { return nil }
    let t = href.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
  }

  private static func bestImageURL(_ entry: [String: Any]) -> String? {
    guard let images = entry["im:image"] as? [[String: Any]] else {
      if let one = entry["im:image"] as? [String: Any] {
        return labelString(one, key: "label").flatMap { $0.isEmpty ? nil : $0 }
          ?? (one["label"] as? String)
      }
      return nil
    }
    var best: (height: Int, url: String)?
    for img in images {
      guard let url = (img["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !url.isEmpty
      else { continue }
      let h =
        (img["attributes"] as? [String: Any])?["height"].flatMap { h -> Int? in
          if let n = h as? Int { return n }
          if let s = h as? String, let n = Int(s) { return n }
          return nil
        } ?? 0
      if best == nil || h > best!.height {
        best = (h, url)
      }
    }
    return best?.url
  }

  // MARK: - Lookup (feedUrl)

  private static func enrichWithLookup(_ hits: [ABSPodcastDirectorySearchHit]) async throws -> [ABSPodcastDirectorySearchHit] {
    let ids = hits.map(\.id).filter { !$0.isEmpty }
    guard !ids.isEmpty else { return hits }
    var lookupById: [String: (feedUrl: String?, artistId: String?, trackCount: Int?)] = [:]
    let chunkSize = 50
    var index = ids.startIndex
    while index < ids.endIndex {
      let end = ids.index(index, offsetBy: chunkSize, limitedBy: ids.endIndex) ?? ids.endIndex
      let chunk = Array(ids[index ..< end])
      index = end
      let batch = try await lookupPodcasts(ids: chunk)
      for (k, v) in batch { lookupById[k] = v }
    }
    return hits.map { hit in
      guard let extra = lookupById[hit.id] else { return hit }
      return ABSPodcastDirectorySearchHit(
        id: hit.id,
        artistId: extra.artistId ?? hit.artistId,
        title: hit.title,
        artistName: hit.artistName,
        descriptionPlain: hit.descriptionPlain,
        releaseDate: hit.releaseDate,
        genres: hit.genres,
        cover: hit.cover,
        trackCount: extra.trackCount ?? hit.trackCount,
        feedUrl: extra.feedUrl ?? hit.feedUrl,
        pageUrl: hit.pageUrl,
        explicit: hit.explicit
      )
    }
  }

  private static func lookupPodcasts(ids: [String]) async throws -> [String: (feedUrl: String?, artistId: String?, trackCount: Int?)] {
    let idList = ids.joined(separator: ",")
    guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(idList)&entity=podcast") else { return [:] }
    var req = URLRequest(url: url, timeoutInterval: 30)
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, nil)
    }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let results = root["results"] as? [[String: Any]]
    else { return [:] }
    var out: [String: (feedUrl: String?, artistId: String?, trackCount: Int?)] = [:]
    for row in results {
      let collectionId: String? = {
        if let n = row["collectionId"] as? Int { return "\(n)" }
        if let s = row["collectionId"] as? String { return s }
        return nil
      }()
      guard let cid = collectionId, !cid.isEmpty else { continue }
      let feed = (row["feedUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let artistId: String? = {
        if let n = row["artistId"] as? Int { return "\(n)" }
        if let s = row["artistId"] as? String { return s }
        return nil
      }()
      let trackCount = row["trackCount"] as? Int
      out[cid] = (feed?.isEmpty == false ? feed : nil, artistId, trackCount)
    }
    return out
  }
}
