import Foundation

/// iTunes Podcast-Charts (öffentliche RSS/Lookup-APIs, vgl. Absorb).
enum ABSPodcastCharts {
  static let defaultLimit = 50

  /// `genreId == nil` → Top-Charts gesamt („All“).
  struct ChartCategory: Identifiable, Hashable {
    let genreId: Int?
    let title: String

    var id: String { genreId.map(String.init) ?? "all" }
  }

  /// Apple-Podcast-Kategorien (iTunes-Genre-IDs für `…/rss/toppodcasts/…/genre=…/json`).
  static let chartCategories: [ChartCategory] = [
    ChartCategory(genreId: nil, title: "All"),
    ChartCategory(genreId: 1301, title: "Arts"),
    ChartCategory(genreId: 1321, title: "Business"),
    ChartCategory(genreId: 1303, title: "Comedy"),
    ChartCategory(genreId: 1304, title: "Education"),
    ChartCategory(genreId: 1483, title: "Fiction"),
    ChartCategory(genreId: 1323, title: "Government"),
    ChartCategory(genreId: 1325, title: "Health"),
    ChartCategory(genreId: 1307, title: "History"),
    ChartCategory(genreId: 1305, title: "Kids"),
    ChartCategory(genreId: 1502, title: "Leisure"),
    ChartCategory(genreId: 1310, title: "Music"),
    ChartCategory(genreId: 1311, title: "News"),
    ChartCategory(genreId: 1314, title: "Religion"),
    ChartCategory(genreId: 1315, title: "Science"),
    ChartCategory(genreId: 1324, title: "Society"),
    ChartCategory(genreId: 1316, title: "Sports"),
    ChartCategory(genreId: 1318, title: "Technology"),
    ChartCategory(genreId: 1488, title: "True Crime"),
    ChartCategory(genreId: 1309, title: "TV & Film"),
  ]

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

  /// Unterstützte iTunes-Storefronts (Ländermenü in Add-Podcast-View).
  static let directoryStorefrontCountryCodes: [String] = [
    "de", "at", "ch", "us", "gb", "fr", "es", "it", "nl", "be", "ie", "ca", "au", "nz",
    "jp", "se", "no", "dk", "fi", "pl", "pt", "br", "mx",
  ]

  static func directoryStorefrontDisplayName(for code: String, locale: Locale = .current) -> String {
    let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard c.count == 2 else { return code.uppercased() }
    return locale.localizedString(forRegionCode: c) ?? c
  }

  /// Vorauswahl zuerst (Auto-Logik), Rest alphabetisch nach Anzeigenamen.
  static func directoryStorefrontMenuCodes(defaultCode: String, locale: Locale = .current) -> [String] {
    let known = Set(directoryStorefrontCountryCodes)
    let raw = defaultCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let primary = known.contains(raw) ? raw : "us"
    var ordered: [String] = [primary]
    let rest =
      known
      .subtracting([primary])
      .sorted {
        directoryStorefrontDisplayName(for: $0, locale: locale)
          .localizedCaseInsensitiveCompare(directoryStorefrontDisplayName(for: $1, locale: locale))
          == .orderedAscending
      }
    ordered.append(contentsOf: rest)
    return ordered
  }

  /// Größerer Pool für Kategorien, bei denen Apple `genre=` ignoriert (z. B. Sports).
  private static let categoryFallbackPoolLimit = 200

  static func chartFeedURL(country: String, genreId: Int?, limit: Int = defaultLimit) -> URL? {
    let c = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !c.isEmpty else { return nil }
    if let genreId {
      return URL(
        string:
          "https://itunes.apple.com/\(c)/rss/toppodcasts/limit=\(limit)/genre=\(genreId)/explicit=true/json"
      )
    }
    return URL(string: "https://itunes.apple.com/\(c)/rss/toppodcasts/limit=\(limit)/explicit=true/json")
  }

  static func fetchChart(
    country: String,
    genreId: Int?,
    limit: Int = defaultLimit
  ) async throws -> [ABSPodcastDirectorySearchHit] {
    guard genreId != nil else {
      let partial = try await fetchChartFeed(country: country, genreId: nil, limit: limit)
      return try await enrichWithLookup(partial)
    }

    let gid = genreId!
    let partial = try await fetchChartFeed(country: country, genreId: gid, limit: limit)
    let allPeek = try await fetchChartFeed(country: country, genreId: nil, limit: 8)
    if chartMatchesOverallTop(genreHits: partial, overallHits: allPeek) {
      let pool = try await fetchChartFeed(
        country: country, genreId: nil, limit: categoryFallbackPoolLimit)
      let filtered = filterHitsByRssCategory(pool, genreId: gid, limit: limit)
      return try await enrichWithLookup(filtered)
    }
    return try await enrichWithLookup(partial)
  }

  private static func fetchChartFeed(
    country: String,
    genreId: Int?,
    limit: Int
  ) async throws -> [ABSPodcastDirectorySearchHit] {
    guard let url = chartFeedURL(country: country, genreId: genreId, limit: limit) else { return [] }
    var req = URLRequest(url: url, timeoutInterval: 30)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, resp) = try await AbstandHTTPSession.coverAndCache.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, nil)
    }
    return try parseChartFeedJSON(data)
  }

  /// Apple liefert für einige Genre-IDs dieselbe Liste wie „All“ (z. B. 1316 Sports).
  private static func chartMatchesOverallTop(
    genreHits: [ABSPodcastDirectorySearchHit],
    overallHits: [ABSPodcastDirectorySearchHit]
  ) -> Bool {
    let genreIds = genreHits.prefix(5).map(\.id)
    let overallIds = overallHits.prefix(5).map(\.id)
    guard genreIds.count >= 3, genreIds == overallIds else { return false }
    return true
  }

  private static func filterHitsByRssCategory(
    _ hits: [ABSPodcastDirectorySearchHit],
    genreId: Int,
    limit: Int
  ) -> [ABSPodcastDirectorySearchHit] {
    let labels = rssCategoryLabels(forGenreId: genreId)
    guard !labels.isEmpty else { return Array(hits.prefix(limit)) }
    var out: [ABSPodcastDirectorySearchHit] = []
    out.reserveCapacity(limit)
    for hit in hits {
      guard let tag = hit.genres?.first?.trimmingCharacters(in: .whitespacesAndNewlines),
        !tag.isEmpty
      else { continue }
      if labels.contains(where: { rssCategoryLabel($0, matches: tag) }) {
        out.append(hit)
        if out.count >= limit { break }
      }
    }
    return out
  }

  private static func rssCategoryLabel(_ pattern: String, matches tag: String) -> Bool {
    let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let t = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !p.isEmpty, !t.isEmpty else { return false }
    if p == t { return true }
    if t.contains(p) || p.contains(t) { return true }
    return false
  }

  /// RSS-`category`-Labels (EN/DE) pro iTunes-Genre — Fallback wenn `genre=` ignoriert wird.
  private static func rssCategoryLabels(forGenreId genreId: Int) -> [String] {
    switch genreId {
    case 1301: return ["Arts", "Kunst", "Books", "Bücher", "Design", "Performing Arts", "Visual Arts"]
    case 1321: return ["Business", "Wirtschaft", "Geldanlage", "Unternehmertum", "Karriere", "Management"]
    case 1303: return ["Comedy", "Komödie"]
    case 1304: return ["Education", "Bildung", "Kurse", "Sprachen lernen", "Training"]
    case 1483: return ["Fiction", "Fiktion", "Drama", "Literatur"]
    case 1323: return ["Government", "Regierung", "Politik"]
    case 1325: return ["Health", "Gesundheit", "Fitness", "Ernährung", "Medizin", "Mentale Gesundheit"]
    case 1307: return ["History", "Geschichte"]
    case 1305: return ["Kids", "Kinder", "Familie", "Kids & Family"]
    case 1502: return ["Leisure", "Freizeit", "Hobbys", "Games", "Spiele"]
    case 1310: return ["Music", "Musik"]
    case 1311: return ["News", "Nachrichten", "Nachrichten des Tages", "Tagesnachrichten", "Politik"]
    case 1314: return ["Religion", "Religion & Spirituality", "Spiritualität"]
    case 1315: return ["Science", "Wissenschaft", "Naturwissenschaften", "Social Sciences"]
    case 1324: return ["Society", "Culture", "Gesellschaft", "Gesellschaft und Kultur", "Philosophie", "Beziehungen"]
    case 1316:
      return [
        "Sport", "Sports", "Fußball", "Soccer", "Football", "Basketball", "Baseball", "Hockey",
        "Tennis", "Golf", "Rugby", "Cricket", "American Football", "Fantasy Sports", "Outdoor",
        "Wilderness", "Running",
      ]
    case 1318: return ["Technology", "Technologie", "Tech"]
    case 1488: return ["True Crime", "Wahre Kriminalfälle", "Krimi"]
    case 1309: return ["TV", "Film", "Fernsehen", "Nachgesprochen", "Filmgeschichte", "TV & Film"]
    default: return []
    }
  }

  static func fetchTopPodcasts(country: String, limit: Int = defaultLimit) async throws -> [ABSPodcastDirectorySearchHit] {
    try await fetchChart(country: country, genreId: nil, limit: limit)
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
    let req = URLRequest(url: url, timeoutInterval: 30)
    let (data, resp) = try await AbstandHTTPSession.coverAndCache.data(for: req)
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
