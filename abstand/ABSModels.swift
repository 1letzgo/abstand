import Foundation

// MARK: - Auth & User

struct ABSLoginRequest: Encodable {
  let username: String
  let password: String
}

struct ABSLoginResponse: Decodable {
  let user: ABSUser
  let userDefaultLibraryId: String?
  let serverSettings: ABSServerSettings?
}

struct ABSUser: Decodable {
  let id: String
  let username: String
  let token: String
  /// `guest`, `user`, oder `admin` (Audiobookshelf).
  let type: String?
  let mediaProgress: [ABSUserMediaProgress]?
  let bookmarks: [ABSAudioBookmark]?

  var normalizedType: String {
    type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
  }

  var isRoot: Bool { normalizedType == "root" }

  /// Entspricht `User.isAdminOrUp` auf dem Server (`root` oder `admin`).
  var isAdmin: Bool {
    let t = normalizedType
    return t == "admin" || t == "root"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    username = try c.decode(String.self, forKey: .username)
    token = try c.decode(String.self, forKey: .token)
    type = try c.decodeIfPresent(String.self, forKey: .type)
    mediaProgress = try c.decodeIfPresent([ABSUserMediaProgress].self, forKey: .mediaProgress)
    bookmarks = try c.decodeIfPresent([ABSAudioBookmark].self, forKey: .bookmarks)
  }

  enum CodingKeys: String, CodingKey {
    case id, username, token, type, mediaProgress, bookmarks
  }
}

/// Lesezeichen in einem Hörbuch (`POST/PATCH/DELETE …/api/me/item/:id/bookmark`).
struct ABSAudioBookmark: Codable, Hashable, Identifiable {
  let libraryItemId: String
  let title: String
  let time: Int
  let createdAt: Int64?

  var id: String { "\(libraryItemId)-\(time)" }

  enum CodingKeys: String, CodingKey {
    case libraryItemId, title, time, createdAt
  }

  init(libraryItemId: String, title: String, time: Int, createdAt: Int64? = nil) {
    self.libraryItemId = libraryItemId
    self.title = title
    self.time = time
    self.createdAt = createdAt
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    libraryItemId = try c.decode(String.self, forKey: .libraryItemId)
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    if let t = try? c.decode(Int.self, forKey: .time) {
      time = t
    } else if let d = try? c.decode(Double.self, forKey: .time) {
      time = Int(d.rounded())
    } else {
      time = 0
    }
    if let s = try c.decodeIfPresent(Int64.self, forKey: .createdAt) {
      createdAt = s
    } else if let d = try c.decodeIfPresent(Double.self, forKey: .createdAt) {
      createdAt = Int64(d.rounded())
    } else {
      createdAt = nil
    }
  }
}

struct ABSCreateBookmarkRequest: Encodable {
  let time: Int
  let title: String
}

struct ABSUserMediaProgress: Codable {
  /// Primärschlüssel der Progress-Zeile auf dem Server — `DELETE /api/me/progress/:id` erwartet genau diesen Wert.
  let mediaProgressServerId: String?
  let libraryItemId: String
  let episodeId: String?
  let duration: Double
  let progress: Double
  let currentTime: Double
  let isFinished: Bool
  let lastUpdate: Int64?

  enum CodingKeys: String, CodingKey {
    case id
    case libraryItemId
    case episodeId
    case duration
    case progress
    case currentTime
    case isFinished
    case lastUpdate
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    episodeId = try c.decodeIfPresent(String.self, forKey: .episodeId)
    duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
    progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
    currentTime = try c.decodeIfPresent(Double.self, forKey: .currentTime) ?? 0
    isFinished = try c.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
    lastUpdate = try c.decodeIfPresent(Int64.self, forKey: .lastUpdate)

    let explicit = try c.decodeIfPresent(String.self, forKey: .libraryItemId)
    let rawId = try c.decodeIfPresent(String.self, forKey: .id)
    let trimmedId = rawId?.trimmingCharacters(in: .whitespacesAndNewlines)
    mediaProgressServerId =
      (trimmedId?.isEmpty == false) ? trimmedId : nil
    if let explicit, !explicit.isEmpty {
      libraryItemId = explicit
    } else if let rawId, !rawId.isEmpty {
      if let r = rawId.range(of: "-ep_") {
        libraryItemId = String(rawId[..<r.lowerBound])
      } else {
        libraryItemId = rawId
      }
    } else {
      throw DecodingError.dataCorruptedError(
        forKey: .libraryItemId,
        in: c,
        debugDescription: "mediaProgress missing libraryItemId/id"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    if let mediaProgressServerId, !mediaProgressServerId.isEmpty {
      try c.encode(mediaProgressServerId, forKey: .id)
    }
    try c.encode(libraryItemId, forKey: .libraryItemId)
    try c.encodeIfPresent(episodeId, forKey: .episodeId)
    try c.encode(duration, forKey: .duration)
    try c.encode(progress, forKey: .progress)
    try c.encode(currentTime, forKey: .currentTime)
    try c.encode(isFinished, forKey: .isFinished)
    try c.encodeIfPresent(lastUpdate, forKey: .lastUpdate)
  }

  /// Lokaler/optimistischer Fortschritt (z. B. sofort nach Play-Start für „Continue listening“).
  init(
    mediaProgressServerId: String? = nil,
    libraryItemId: String,
    episodeId: String?,
    duration: Double,
    progress: Double,
    currentTime: Double,
    isFinished: Bool,
    lastUpdate: Int64?
  ) {
    self.mediaProgressServerId = mediaProgressServerId
    self.libraryItemId = libraryItemId
    self.episodeId = episodeId
    self.duration = duration
    self.progress = progress
    self.currentTime = currentTime
    self.isFinished = isFinished
    self.lastUpdate = lastUpdate
  }

  /// Schlüssel für `AppModel.progressByItemId` (Episoden: `libraryItemId-episodeId`).
  var progressLookupKey: String {
    let e = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !e.isEmpty { return "\(libraryItemId)-\(e)" }
    return libraryItemId
  }

  /// ABS `DELETE /api/me/progress/:id` — der Server prüft `MediaProgress.id`, nicht `libraryItemId`.
  var idForMediaProgressDeleteRequest: String {
    if let s = mediaProgressServerId, !s.isEmpty { return s }
    return progressLookupKey
  }
}

struct ABSLibrariesResponse: Decodable {
  let libraries: [ABSLibrary]
}

struct ABSLibrary: Decodable, Identifiable, Equatable {
  let id: String
  let name: String
  let mediaType: String?
  /// Server-Reihenfolge in den Einstellungen (siehe `POST /api/libraries/order`).
  let displayOrder: Int?

  var isBookLibrary: Bool { (mediaType ?? "book").lowercased() == "book" }
  var isPodcastLibrary: Bool { (mediaType ?? "").lowercased() == "podcast" }
  var displayOrderOrZero: Int { displayOrder ?? 0 }

  /// Offline / bis die Bibliotheksliste vom Server da ist.
  init(id: String, name: String, mediaType: String? = "book", displayOrder: Int? = nil) {
    self.id = id
    self.name = name
    self.mediaType = mediaType
    self.displayOrder = displayOrder
  }
}

// MARK: - Podcast directory (iTunes search) & library folders

struct ABSLibraryFolderRow: Decodable, Identifiable, Hashable {
  let id: String
  let fullPath: String
}

/// Nur die Felder, die wir für `POST /api/podcasts` brauchen (`GET /api/libraries/:id`).
struct ABSLibraryDetailFoldersPayload: Decodable {
  let folders: [ABSLibraryFolderRow]?

  enum CodingKeys: String, CodingKey {
    case folders
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    folders = try c.decodeIfPresent([ABSLibraryFolderRow].self, forKey: .folders)
  }
}

/// Treffer von `GET /api/search/podcast` (iTunes, vgl. `PodcastFinder`).
struct ABSPodcastDirectorySearchHit: Decodable, Identifiable, Hashable {
  let id: String
  let artistId: String?
  let title: String
  let artistName: String?
  let descriptionPlain: String?
  let releaseDate: String?
  let genres: [String]?
  let cover: String?
  let trackCount: Int?
  let feedUrl: String?
  let pageUrl: String?
  let explicit: Bool?

  enum CodingKeys: String, CodingKey {
    case id
    case artistId
    case title
    case artistName
    case descriptionPlain
    case description
    case releaseDate
    case genres
    case cover
    case trackCount
    case feedUrl
    case pageUrl
    case explicit
  }

  init(
    id: String,
    artistId: String? = nil,
    title: String,
    artistName: String? = nil,
    descriptionPlain: String? = nil,
    releaseDate: String? = nil,
    genres: [String]? = nil,
    cover: String? = nil,
    trackCount: Int? = nil,
    feedUrl: String? = nil,
    pageUrl: String? = nil,
    explicit: Bool? = nil
  ) {
    self.id = id
    self.artistId = artistId
    self.title = title
    self.artistName = artistName
    self.descriptionPlain = descriptionPlain
    self.releaseDate = releaseDate
    self.genres = genres
    self.cover = cover
    self.trackCount = trackCount
    self.feedUrl = feedUrl
    self.pageUrl = pageUrl
    self.explicit = explicit
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = Self.decodeRequiredString(c, forKey: .id)
    artistId = Self.decodeOptionalString(c, forKey: .artistId)
    title = (try? c.decode(String.self, forKey: .title))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    artistName = try? c.decode(String.self, forKey: .artistName)
    if let p = try? c.decode(String.self, forKey: .descriptionPlain) {
      descriptionPlain = p
    } else {
      descriptionPlain = try? c.decode(String.self, forKey: .description)
    }
    releaseDate = try? c.decode(String.self, forKey: .releaseDate)
    genres = try? c.decode([String].self, forKey: .genres)
    cover = try? c.decode(String.self, forKey: .cover)
    trackCount = Self.decodeOptionalInt(c, forKey: .trackCount)
    feedUrl = try? c.decode(String.self, forKey: .feedUrl)
    pageUrl = try? c.decode(String.self, forKey: .pageUrl)
    explicit = try? c.decode(Bool.self, forKey: .explicit)
  }

  private static func decodeRequiredString(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String {
    if let s = try? c.decode(String.self, forKey: key) { return s }
    if let i = try? c.decode(Int64.self, forKey: key) { return "\(i)" }
    if let i = try? c.decode(Int.self, forKey: key) { return "\(i)" }
    return ""
  }

  private static func decodeOptionalString(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
    if let s = try? c.decode(String.self, forKey: key) { return s }
    if let i = try? c.decode(Int64.self, forKey: key) { return "\(i)" }
    if let i = try? c.decode(Int.self, forKey: key) { return "\(i)" }
    return nil
  }

  private static func decodeOptionalInt(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
    if let v = try? c.decode(Int.self, forKey: key) { return v }
    if let s = try? c.decode(String.self, forKey: key), let v = Int(s) { return v }
    return nil
  }
}

// MARK: - Paging

struct ABSPage<T: Decodable>: Decodable {
  let results: [T]
  let total: Int
  let page: Int

  enum CodingKeys: String, CodingKey {
    case results, authors
    case total, page
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let r = try c.decodeIfPresent([T].self, forKey: .results) {
      results = r
    } else if let a = try c.decodeIfPresent([T].self, forKey: .authors) {
      results = a
    } else {
      results = []
    }
    total = try c.decode(Int.self, forKey: .total)
    page = try c.decode(Int.self, forKey: .page)
  }
}

// MARK: - Podcast episodes (library recent)

struct ABSRecentEpisodesResponse: Decodable {
  let episodes: [ABSRecentPodcastEpisodeDTO]
  let total: Int
  let limit: Int
  let page: Int

  enum CodingKeys: String, CodingKey {
    case episodes, total, limit, page
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    episodes = (try? c.decode([ABSRecentPodcastEpisodeDTO].self, forKey: .episodes)) ?? []
    total = Self.decodeInt(c, forKey: .total) ?? episodes.count
    limit = Self.decodeInt(c, forKey: .limit) ?? 0
    page = Self.decodeInt(c, forKey: .page) ?? 0
  }

  private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
    if let v = try? c.decode(Int.self, forKey: key) { return v }
    if let s = try? c.decode(String.self, forKey: key), let v = Int(s) { return v }
    return nil
  }
}

struct ABSRecentPodcastEpisodeDTO: Decodable {
  let libraryItemId: String
  let id: String
  let title: String
  let subtitle: String?
  let description: String?
  let pubDate: String?
  let duration: Double?
  let publishedAt: Int64?
  let podcast: ABSRecentEpisodePodcastNest?
}

struct ABSRecentEpisodePodcastNest: Decodable {
  let metadata: ABSRecentEpisodePodcastMeta?
}

struct ABSRecentEpisodePodcastMeta: Decodable {
  let title: String?
  let author: String?
  let description: String?
  let genres: [String]?
}

/// Einzelne Folge aus `POST /api/podcasts/feed` (noch nicht als Library-Episode); Payload für `POST …/download-episodes`.
struct ABSPodcastRssFeedEpisodeDraft: Identifiable, Hashable {
  let id: UUID
  let title: String
  let publishedAt: Int64?
  let subtitle: String?
  let episodePayloadJSON: Data

  func matchesLibraryEpisode(_ row: ABSPodcastEpisodeListItem) -> Bool {
    let t0 = Self.normTitle(title)
    let t1 = Self.normTitle(row.episodeTitle)
    guard !t0.isEmpty, t0 == t1 else { return false }
    let pa = publishedAt.map { $0 / 1000 }
    let pb = row.publishedAt.map { $0 / 1000 }
    if let pa, let pb, pa != 0, pb != 0, abs(pa - pb) <= 2 { return true }
    if (publishedAt == nil || publishedAt == 0), (row.publishedAt == nil || row.publishedAt == 0) { return true }
    return false
  }

  private static func normTitle(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  static func episodesFromFeedApiResponse(_ data: Data) throws -> [ABSPodcastRssFeedEpisodeDraft] {
    let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any]
    let podcast = root?["podcast"] as? [String: Any]
    guard let episodes = podcast?["episodes"] as? [[String: Any]] else {
      return []
    }
    var out: [ABSPodcastRssFeedEpisodeDraft] = []
    out.reserveCapacity(episodes.count)
    for ep in episodes {
      guard JSONSerialization.isValidJSONObject(ep) else { continue }
      let payload = try JSONSerialization.data(withJSONObject: ep)
      let titleRaw = (ep["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let title = titleRaw.isEmpty ? "Episode" : titleRaw
      let subRaw = (ep["subtitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let subtitle: String? = subRaw.isEmpty ? nil : subRaw
      let publishedAt = int64Millis(from: ep["publishedAt"]) ?? int64Millis(from: ep["pubDate"])
      out.append(
        ABSPodcastRssFeedEpisodeDraft(
          id: UUID(),
          title: title,
          publishedAt: publishedAt,
          subtitle: subtitle,
          episodePayloadJSON: payload
        )
      )
    }
    return out.sorted {
      let pa = $0.publishedAt ?? 0
      let pb = $1.publishedAt ?? 0
      if pa != pb { return pa > pb }
      return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending
    }
  }

  private static func int64Millis(from value: Any?) -> Int64? {
    switch value {
    case let n as Int64:
      return n
    case let n as Int:
      return Int64(n)
    case let n as UInt64:
      return Int64(clamping: n)
    case let n as Double:
      if n > 10_000_000_000 { return Int64(n) }
      if n > 1_000_000_000 { return Int64(n * 1000) }
      return Int64(n * 1000)
    case let s as String:
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if let i = Int64(t) { return i }
      return nil
    default:
      return nil
    }
  }
}

/// Antwort von `GET /api/podcasts/:id/checknew`.
struct ABSPodcastCheckNewResponse: Decodable {
  let episodes: [ABSPodcastCheckNewFeedEpisode]
}

struct ABSPodcastCheckNewFeedEpisode: Decodable {
  let title: String?
}

struct ABSPodcastEpisodeListItem: Identifiable, Hashable, Codable {
  let libraryItemId: String
  /// Bibliothek (z. B. für Home-„Weiterhören“ nach gewählter Podcast-Bibliothek).
  let libraryId: String?
  let episodeId: String
  let episodeTitle: String
  let showTitle: String
  let authorLine: String
  let duration: Double
  let publishedAt: Int64?

  var id: String { episodeId }

  var progressLookupKey: String { "\(libraryItemId)-\(episodeId)" }

  /// Stabiler Schlüssel für Deduplizierung (Cache, Manifest, Fortschritt).
  var canonicalDedupeKey: String {
    let lid = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    let eid = episodeId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !lid.isEmpty, !eid.isEmpty { return "\(lid)|\(eid)" }
    return progressLookupKey
  }

  /// Höher = vollständigere Anzeige (Titel, Sendung, Datum).
  var metadataRichnessScore: Int {
    var score = 0
    let et = episodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !et.isEmpty, et != "Episode" { score += 4 }
    let st = showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !st.isEmpty, st != "—" { score += 3 }
    let al = authorLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if !al.isEmpty, al != "—", al != st { score += 1 }
    if let ms = publishedAt, ms > 0 { score += 1 }
    if duration > 0 { score += 1 }
    return score
  }

  func preferringRicherMetadata(than other: ABSPodcastEpisodeListItem) -> ABSPodcastEpisodeListItem {
    metadataRichnessScore >= other.metadataRichnessScore ? self : other
  }

  /// Gleiche Folge nur einmal; Zeile mit mehr Metadaten gewinnt (Offline: Cache + Manifest).
  static func dedupeRows(_ items: [ABSPodcastEpisodeListItem]) -> [ABSPodcastEpisodeListItem] {
    var byKey: [String: ABSPodcastEpisodeListItem] = [:]
    var order: [String] = []
    order.reserveCapacity(items.count)
    for item in items {
      let key = item.canonicalDedupeKey
      if let existing = byKey[key] {
        byKey[key] = item.preferringRicherMetadata(than: existing)
      } else {
        byKey[key] = item
        order.append(key)
      }
    }
    return order.compactMap { byKey[$0] }
  }

  static func fromDTO(
    _ e: ABSRecentPodcastEpisodeDTO,
    fallbackShow: ABSBook? = nil,
    libraryId: String? = nil,
    forceLibraryItemId: String? = nil
  ) -> ABSPodcastEpisodeListItem? {
    let lidRaw = (forceLibraryItemId ?? e.libraryItemId).trimmingCharacters(in: .whitespacesAndNewlines)
    let lid = lidRaw
    let eid = e.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lid.isEmpty, !eid.isEmpty else { return nil }
    let et = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let episodeTitle = et.isEmpty ? "Episode" : et
    var show = e.podcast?.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if show.isEmpty, let s = fallbackShow {
      let t = s.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      if !t.isEmpty { show = t }
    }
    let showTitle = show.isEmpty ? "—" : show
    var auth = e.podcast?.metadata?.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if auth.isEmpty, let s = fallbackShow {
      let a = s.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
      if !a.isEmpty, a != "—" { auth = a }
    }
    let authorLine = auth.isEmpty ? showTitle : auth
    let dur = e.duration ?? 0
    let libIdRaw = libraryId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let libId: String? = libIdRaw.isEmpty ? nil : libIdRaw
    return ABSPodcastEpisodeListItem(
      libraryItemId: lid,
      libraryId: libId,
      episodeId: eid,
      episodeTitle: episodeTitle,
      showTitle: showTitle,
      authorLine: authorLine,
      duration: dur,
      publishedAt: e.publishedAt
    )
  }

  /// Minimaler `ABSBook` für `PlaybackController.playBook` (Cover/Item-ID = Sendung).
  func playbackStubBook(libraryId: String?) -> ABSBook {
    let meta = ABSBookMediaMetadata(offlineTitle: episodeTitle, authorLine: authorLine)
    let dur = duration > 0 ? duration : nil
    let media = ABSBookMedia(
      metadata: meta,
      duration: dur,
      numTracks: 1,
      chapters: nil,
      tracks: nil
    )
    return ABSBook(
      id: libraryItemId,
      libraryId: libraryId ?? self.libraryId,
      media: media,
      addedAt: nil,
      updatedAt: nil
    )
  }

  /// Minimale Zeile für Wiederherstellung nach App-Start (`mediaProgress` mit `episodeId`).
  static func forResumePlayback(progress: ABSUserMediaProgress, libraryId: String?) -> ABSPodcastEpisodeListItem? {
    let eid = progress.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !eid.isEmpty else { return nil }
    let dur = progress.duration
    return ABSPodcastEpisodeListItem(
      libraryItemId: progress.libraryItemId,
      libraryId: libraryId,
      episodeId: eid,
      episodeTitle: "Episode",
      showTitle: "—",
      authorLine: "—",
      duration: dur,
      publishedAt: nil
    )
  }
}

/// Zusatzinfos nach `expandPodcastEpisode` (expandiertes Library-Item).
struct ABSPodcastEpisodeExpandedDetail: Hashable {
  let episode: ABSPodcastEpisodeListItem
  let subtitle: String?
  let episodeDescriptionHTML: String?
  let showDescriptionHTML: String?
  let pubDate: String?
  let showGenres: [String]?
  /// Autoren der Sendung (`media.metadata.authors`) für klickbaren Katalog-Filter.
  let showAuthors: [ABSAuthor]
}

struct ABSItemsInProgressPayload {
  let books: [ABSBook]
  let podcastEpisodes: [ABSPodcastEpisodeListItem]
}

// MARK: - Book / Library Item

struct ABSAuthor: Decodable, Hashable {
  let id: String
  let name: String
}

struct ABSSeries: Decodable, Hashable {
  let id: String
  let name: String
  let sequence: String?
}

struct ABSBookMediaMetadata: Decodable {
  let title: String
  let titleIgnorePrefix: String?
  let subtitle: String?
  let authors: [ABSAuthor]?
  let narrators: [String]?
  let series: [ABSSeries]?
  let publishedYear: String?
  let publishedDate: String?
  let authorName: String?
  let narratorName: String?
  let seriesName: String?
  let publisher: String?
  let description: String?
  let descriptionPlain: String?
  let genres: [String]?
  let language: String?
  /// Optional: Feed-URL aus den Metadaten der Sendung.
  let feedUrl: String?

  enum CodingKeys: String, CodingKey {
    case title, titleIgnorePrefix, subtitle, authors, narrators, series
    case publishedYear, publishedDate, authorName, author, narratorName, seriesName
    case publisher, description, descriptionPlain, genres, language
    case feedUrl
    case feedURL
    case feed_url
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = try c.decode(String.self, forKey: .title)
    titleIgnorePrefix = try c.decodeIfPresent(String.self, forKey: .titleIgnorePrefix)
    subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
    authors = try c.decodeIfPresent([ABSAuthor].self, forKey: .authors)
    narrators = try c.decodeIfPresent([String].self, forKey: .narrators)
    publishedYear = try c.decodeIfPresent(String.self, forKey: .publishedYear)
    publishedDate = try c.decodeIfPresent(String.self, forKey: .publishedDate)
    if let explicit = try c.decodeIfPresent(String.self, forKey: .authorName) {
      authorName = explicit
    } else {
      authorName = try c.decodeIfPresent(String.self, forKey: .author)
    }
    narratorName = try c.decodeIfPresent(String.self, forKey: .narratorName)
    seriesName = try c.decodeIfPresent(String.self, forKey: .seriesName)
    publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
    description = try c.decodeIfPresent(String.self, forKey: .description)
    descriptionPlain = try c.decodeIfPresent(String.self, forKey: .descriptionPlain)
    genres = try c.decodeIfPresent([String].self, forKey: .genres)
    language = try c.decodeIfPresent(String.self, forKey: .language)
    feedUrl = Self.decodeFeedUrl(from: c)

    if let arr = try? c.decode([ABSSeries].self, forKey: .series) {
      series = arr
    } else if let one = try? c.decode(ABSSeries.self, forKey: .series) {
      series = [one]
    } else {
      series = nil
    }
  }

  /// Serienname aus `seriesName` oder den `series`-Einträgen (inkl. Folgennummer).
  var resolvedSeriesDisplay: String? {
    if let sn = seriesName?.trimmingCharacters(in: .whitespacesAndNewlines), !sn.isEmpty { return sn }
    guard let arr = series, !arr.isEmpty else { return nil }
    return arr.map { s in
      if let q = s.sequence?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
        return "\(s.name) (\(q))"
      }
      return s.name
    }.joined(separator: ", ")
  }

  /// Kopie mit geändertem Listentitel / Autorzeile (z. B. Podcast-Folge statt Feed-Name).
  init(copying base: ABSBookMediaMetadata, title: String, authorName: String?) {
    self.title = title
    titleIgnorePrefix = base.titleIgnorePrefix
    subtitle = base.subtitle
    authors = base.authors
    narrators = base.narrators
    series = base.series
    publishedYear = base.publishedYear
    publishedDate = base.publishedDate
    let a = authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.authorName = a.isEmpty ? base.authorName : authorName
    narratorName = base.narratorName
    seriesName = base.seriesName
    publisher = base.publisher
    description = base.description
    descriptionPlain = base.descriptionPlain
    genres = base.genres
    language = base.language
    feedUrl = base.feedUrl
  }
}

extension ABSBookMediaMetadata {
  /// Sprecher-Namen für Zuordnung Bibliotheksitem → Sprecher (exakter Name wie in `/narrators`).
  func narratorNamesForLibraryBrowseCoverMatch() -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    func push(_ raw: String) {
      let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !t.isEmpty, !seen.contains(t) else { return }
      seen.insert(t)
      out.append(t)
    }
    if let arr = narrators {
      for raw in arr { push(raw) }
    }
    if let single = narratorName?.trimmingCharacters(in: .whitespacesAndNewlines), !single.isEmpty {
      for part in single.split(separator: ",") {
        push(String(part))
      }
    }
    return out
  }
}

struct ABSChapter: Codable {
  let id: Int
  let start: Double
  let end: Double
  let title: String
}

extension ABSChapter {
  init(manifest ch: ABSDownloadManifest.Chapter) {
    id = ch.id
    start = ch.start
    end = ch.end
    title = ch.title
  }
}

extension ABSDownloadManifest.Chapter {
  init(_ ch: ABSChapter) {
    id = ch.id
    start = ch.start
    end = ch.end
    title = ch.title
  }
}

struct ABSAudioTrack: Decodable {
  let index: Int
  let startOffset: Double
  let duration: Double
  let title: String?
  /// Bibliotheksdatei-Inode (ABS); ermöglicht direkten Download statt Session-Stream.
  let ino: String?

  enum CodingKeys: String, CodingKey {
    case index, startOffset, duration, title, ino, metadata
  }

  private enum MetadataKeys: String, CodingKey {
    case ino
  }

  init(index: Int, startOffset: Double, duration: Double, title: String?, ino: String? = nil) {
    self.index = index
    self.startOffset = startOffset
    self.duration = duration
    self.title = title
    self.ino = ino
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    index = try c.decode(Int.self, forKey: .index)
    startOffset = try c.decodeIfPresent(Double.self, forKey: .startOffset) ?? 0
    duration = try c.decode(Double.self, forKey: .duration)
    title = try c.decodeIfPresent(String.self, forKey: .title)
    var resolvedIno: String?
    if let s = try c.decodeIfPresent(String.self, forKey: .ino), !s.isEmpty {
      resolvedIno = s
    } else if let n = try c.decodeIfPresent(Int64.self, forKey: .ino) {
      resolvedIno = String(n)
    }
    if resolvedIno == nil,
      let meta = try? c.nestedContainer(keyedBy: MetadataKeys.self, forKey: .metadata)
    {
      if let s = try meta.decodeIfPresent(String.self, forKey: .ino), !s.isEmpty {
        resolvedIno = s
      } else if let n = try meta.decodeIfPresent(Int64.self, forKey: .ino) {
        resolvedIno = String(n)
      }
    }
    ino = resolvedIno
  }
}

private struct ABSSearchAudioFile: Decodable {
  let index: Int
  let duration: Double?
  let metadata: FileMeta?
  struct FileMeta: Decodable {
    let filename: String?
  }
}

/// Datei auf Library-Item-Ebene (`libraryFiles`); supplementäre EPUBs hängen oft nur hier.
struct ABSLibraryFile: Decodable {
  let ino: String
  let fileType: String?
  let isSupplementary: Bool?
  let metadata: Metadata?

  struct Metadata: Decodable {
    let filename: String?
    let ext: String?
    let format: String?
  }

  enum CodingKeys: String, CodingKey {
    case ino, fileType, isSupplementary, metadata
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let s = try c.decodeIfPresent(String.self, forKey: .ino), !s.isEmpty {
      ino = s
    } else if let n = try c.decodeIfPresent(Int64.self, forKey: .ino) {
      ino = String(n)
    } else {
      throw DecodingError.keyNotFound(CodingKeys.ino, .init(codingPath: decoder.codingPath, debugDescription: "ino"))
    }
    fileType = try c.decodeIfPresent(String.self, forKey: .fileType)
    isSupplementary = try c.decodeIfPresent(Bool.self, forKey: .isSupplementary)
    metadata = try c.decodeIfPresent(Metadata.self, forKey: .metadata)
  }

  var isEpub: Bool {
    let fmt = (metadata?.format ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if fmt == "epub" { return true }
    let ext = (metadata?.ext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ext == ".epub" || ext == "epub" { return true }
    let name = (metadata?.filename ?? "").lowercased()
    return name.hasSuffix(".epub")
  }

  var isPdf: Bool {
    let fmt = (metadata?.format ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if fmt == "pdf" { return true }
    let ext = (metadata?.ext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ext == ".pdf" || ext == "pdf" { return true }
    let name = (metadata?.filename ?? "").lowercased()
    return name.hasSuffix(".pdf")
  }

  var isEbook: Bool {
    if isEpub || isPdf { return true }
    let fmt = (metadata?.format ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["pdf", "mobi", "azw3", "azw", "cbz", "cbr"].contains(fmt) { return true }
    let ext = (metadata?.ext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if [".pdf", ".mobi", ".azw3", ".azw", ".cbz", ".cbr"].contains(ext) { return true }
    let name = (metadata?.filename ?? "").lowercased()
    return name.hasSuffix(".pdf") || name.hasSuffix(".mobi") || name.hasSuffix(".azw3")
      || name.hasSuffix(".cbz") || name.hasSuffix(".cbr")
  }
}

/// Supplementärer E-Book-Eintrag (z. B. EPUB neben Hörbuch), aus `media.ebookFile`.
struct ABSEbookFile: Codable {
  let ino: String
  let ebookFormat: String?
  let metadata: Metadata?

  struct Metadata: Codable {
    let filename: String?
    let ext: String?
    let format: String?
  }

  enum CodingKeys: String, CodingKey {
    case ino, ebookFormat, metadata
  }

  init(ino: String, ebookFormat: String?, metadata: Metadata?) {
    self.ino = ino
    self.ebookFormat = ebookFormat
    self.metadata = metadata
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let s = try c.decodeIfPresent(String.self, forKey: .ino), !s.isEmpty {
      ino = s
    } else if let n = try c.decodeIfPresent(Int64.self, forKey: .ino) {
      ino = String(n)
    } else {
      throw DecodingError.keyNotFound(CodingKeys.ino, .init(codingPath: decoder.codingPath, debugDescription: "ino"))
    }
    ebookFormat = try c.decodeIfPresent(String.self, forKey: .ebookFormat)
    metadata = try c.decodeIfPresent(Metadata.self, forKey: .metadata)
  }

  var isEpub: Bool {
    let fmt = (ebookFormat ?? metadata?.format ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if fmt == "epub" { return true }
    let ext = (metadata?.ext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ext == ".epub" || ext == "epub" { return true }
    let name = (metadata?.filename ?? "").lowercased()
    return name.hasSuffix(".epub")
  }
}

struct ABSBookMedia: Decodable {
  let metadata: ABSBookMediaMetadata
  let duration: Double?
  let size: Int64?
  let numTracks: Int?
  let chapters: [ABSChapter]?
  let tracks: [ABSAudioTrack]?
  /// Nur Podcast-`media.episodes` (expandiertes Library-Item).
  let podcastEpisodes: [ABSRecentPodcastEpisodeDTO]?
  let autoDownloadEpisodes: Bool?
  let autoDownloadSchedule: String?
  let maxEpisodesToKeep: Int?
  let maxNewEpisodesToDownload: Int?
  /// Supplementäres E-Book (expandiert); `nil` wenn nur Hörbuch.
  let ebookFile: ABSEbookFile?
  /// Katalog/minified: Format-Hinweis ohne vollständiges `ebookFile`.
  let ebookFormat: String?

  enum CodingKeys: String, CodingKey {
    case metadata, duration, size, numTracks, chapters, tracks, audioFiles
    case podcastEpisodes = "episodes"
    case autoDownloadEpisodes, autoDownloadSchedule
    case maxEpisodesToKeep, maxNewEpisodesToDownload
    case ebookFile, ebookFormat, ebookFileFormat
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    metadata = try c.decode(ABSBookMediaMetadata.self, forKey: .metadata)
    duration = try c.decodeIfPresent(Double.self, forKey: .duration)
    size = try c.decodeIfPresent(Int64.self, forKey: .size)
    numTracks = try c.decodeIfPresent(Int.self, forKey: .numTracks)
    chapters = try c.decodeIfPresent([ABSChapter].self, forKey: .chapters)
    podcastEpisodes = try c.decodeIfPresent([ABSRecentPodcastEpisodeDTO].self, forKey: .podcastEpisodes)
    autoDownloadEpisodes = try c.decodeIfPresent(Bool.self, forKey: .autoDownloadEpisodes)
    autoDownloadSchedule = try c.decodeIfPresent(String.self, forKey: .autoDownloadSchedule)
    maxEpisodesToKeep = try c.decodeIfPresent(Int.self, forKey: .maxEpisodesToKeep)
    maxNewEpisodesToDownload = try c.decodeIfPresent(Int.self, forKey: .maxNewEpisodesToDownload)
    ebookFile = try c.decodeIfPresent(ABSEbookFile.self, forKey: .ebookFile)
    ebookFormat = try c.decodeIfPresent(String.self, forKey: .ebookFormat)
      ?? c.decodeIfPresent(String.self, forKey: .ebookFileFormat)
    if let ts = try c.decodeIfPresent([ABSAudioTrack].self, forKey: .tracks), !ts.isEmpty {
      tracks = ts
    } else if let files = try c.decodeIfPresent([ABSSearchAudioFile].self, forKey: .audioFiles), !files.isEmpty {
      var off = 0.0
      tracks = files.sorted { $0.index < $1.index }.map { f in
        let d = f.duration ?? 0
        let t = ABSAudioTrack(index: f.index, startOffset: off, duration: d, title: f.metadata?.filename, ino: nil)
        off += d
        return t
      }
    } else {
      tracks = nil
    }
  }
}

struct ABSBook: Decodable, Identifiable {
  let id: String
  let libraryId: String?
  /// Referenz auf die Medien-Zeile (Buch/Podcast), vgl. `libraryItems.mediaId` — für Playback-Sessions nötig.
  let mediaId: String?
  let media: ABSBookMedia
  /// Nur bei expandiertem Item; supplementäre EPUBs können hier statt in `media.ebookFile` stehen.
  let libraryFiles: [ABSLibraryFile]?
  let addedAt: Date?
  let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case libraryId
    case mediaId
    case media
    case libraryFiles
    case addedAt
    case updatedAt
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    libraryId = try c.decodeIfPresent(String.self, forKey: .libraryId)
    mediaId = try c.decodeIfPresent(String.self, forKey: .mediaId)
    media = try c.decode(ABSBookMedia.self, forKey: .media)
    libraryFiles = try c.decodeIfPresent([ABSLibraryFile].self, forKey: .libraryFiles)
    addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt)
    updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
  }

  init(
    id: String,
    libraryId: String?,
    media: ABSBookMedia,
    addedAt: Date?,
    updatedAt: Date?,
    mediaId: String? = nil,
    libraryFiles: [ABSLibraryFile]? = nil
  ) {
    self.id = id
    self.libraryId = libraryId
    self.mediaId = mediaId
    self.media = media
    self.libraryFiles = libraryFiles
    self.addedAt = addedAt
    self.updatedAt = updatedAt
  }

  var displayTitle: String { media.metadata.title }
  var displayAuthors: String {
    let m = media.metadata
    if let n = m.authorName, !n.isEmpty { return n }
    if let a = m.authors, !a.isEmpty { return a.map(\.name).joined(separator: ", ") }
    return "—"
  }
  /// Erste Autor:in für kompakte UI (Listenkarten, Continue-Hero, Miniplayer); Detail- und Filterzeilen nutzen `displayAuthors`.
  var displayAuthorsCardLine: String {
    let m = media.metadata
    let raw: String? = {
      if let a = m.authors, let first = a.first {
        let t = first.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
      }
      if let n = m.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty, n != "—" {
        return n
      }
      return nil
    }()
    if let raw {
      return Self.primaryAuthorForCardCompactDisplay(raw)
    }
    let fallback = displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fallback.isEmpty, fallback != "—" else { return "—" }
    return Self.primaryAuthorForCardCompactDisplay(fallback)
  }

  /// Katalog liefert oft einen langen `authorName` („Autor1, Autor2 - Übersetzer, …“). Nur den ersten Namen zeigen,
  /// außer bei typischem „Nachname, Vorname“ (zwei Segmente ohne Rollenhinweis).
  private static func primaryAuthorForCardCompactDisplay(_ full: String) -> String {
    let t = full.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return "—" }
    let parts = t.components(separatedBy: ", ")
    guard parts.count >= 2 else { return t }
    let p1 = parts[1]
    let p1Lower = p1.lowercased()
    let looksLikeMultiPersonOrCreditsList =
      parts.count >= 3
      || p1.contains(" - ")
      || p1Lower.contains("überset")
      || p1Lower.contains("translat")
      || p1Lower.contains("traduct")
      || p1Lower.contains("lector")
      || p1Lower.contains("bearbeit")
    if looksLikeMultiPersonOrCreditsList {
      return parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return t
  }

  var totalDuration: Double { media.duration ?? 0 }

  /// Enough metadata to play or show in lists.
  var isPlayableAudiobook: Bool {
    (media.numTracks ?? 0) > 0 || (media.duration ?? 0) > 0
  }

  /// Listen-Katalog (`GET …/libraries/:id/items`, oft `minified=1`): Spuren/Dauer fehlen häufig — ohne Fallback
  /// verschwinden neu hinzugefügte Titel aus der Liste.
  var isUsableLibraryCatalogRow: Bool {
    if isPlayableAudiobook { return true }
    let tracks = media.numTracks
    if tracks == nil, (media.duration ?? 0) <= 0 {
      return !displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return false
  }
}

extension ABSBookMediaMetadata {
  /// ABS speichert teils `feedUrl`, teils `feedURL` (vgl. `Podcast.getAbsMetadataJson`).
  static func decodeFeedUrl(from c: KeyedDecodingContainer<CodingKeys>) -> String? {
    for key in [CodingKeys.feedUrl, .feedURL, .feed_url] {
      if let raw = try? c.decode(String.self, forKey: key) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
      }
    }
    return nil
  }

  /// Vollständige Item-API-Metadaten (Serie, Beschreibung, …) vs. schlanker Offline-Stub.
  var hasRichMetadata: Bool {
    if authors != nil || series != nil || narrators != nil { return true }
    if description != nil || descriptionPlain != nil { return true }
    if genres != nil || narratorName != nil || publisher != nil { return true }
    if let y = publishedYear?.trimmingCharacters(in: .whitespacesAndNewlines), !y.isEmpty { return true }
    if let d = publishedDate?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { return true }
    if let s = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return true }
    return false
  }

  /// Für Offline-Stubs aus `download.json` (kein vollständiges Server-JSON).
  init(offlineTitle: String, authorLine: String) {
    title = offlineTitle.isEmpty ? "Audiobook" : offlineTitle
    titleIgnorePrefix = nil
    subtitle = nil
    let trimmedAuthor = authorLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedAuthor.isEmpty || trimmedAuthor == "—" {
      authors = nil
      authorName = nil
    } else {
      authorName = trimmedAuthor
      authors = trimmedAuthor
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .enumerated()
        .map { ABSAuthor(id: "offline-\($0.offset)", name: $0.element) }
    }
    narrators = nil
    series = nil
    publishedYear = nil
    publishedDate = nil
    narratorName = nil
    seriesName = nil
    publisher = nil
    description = nil
    descriptionPlain = nil
    genres = nil
    language = nil
    feedUrl = nil
  }
}

extension ABSBookMedia {
  init(
    metadata: ABSBookMediaMetadata,
    duration: Double?,
    size: Int64? = nil,
    numTracks: Int?,
    chapters: [ABSChapter]? = nil,
    tracks: [ABSAudioTrack]?,
    podcastEpisodes: [ABSRecentPodcastEpisodeDTO]? = nil,
    autoDownloadEpisodes: Bool? = nil,
    autoDownloadSchedule: String? = nil,
    maxEpisodesToKeep: Int? = nil,
    maxNewEpisodesToDownload: Int? = nil,
    ebookFile: ABSEbookFile? = nil,
    ebookFormat: String? = nil
  ) {
    self.metadata = metadata
    self.duration = duration
    self.size = size
    self.numTracks = numTracks
    self.chapters = chapters
    self.tracks = tracks
    self.podcastEpisodes = podcastEpisodes
    self.autoDownloadEpisodes = autoDownloadEpisodes
    self.autoDownloadSchedule = autoDownloadSchedule
    self.maxEpisodesToKeep = maxEpisodesToKeep
    self.maxNewEpisodesToDownload = maxNewEpisodesToDownload
    self.ebookFile = ebookFile
    self.ebookFormat = ebookFormat
  }
}

extension ABSBook {
  private var isAudiobookLibraryItem: Bool {
    (media.numTracks ?? 0) > 0 || (media.duration ?? 0) > 0
  }

  private var epubLibraryFiles: [ABSLibraryFile] {
    libraryFiles?.filter(\.isEpub) ?? []
  }

  /// Hörbuch mit angehängter E-Book-Datei (EPUB, PDF, …); für Listenfilter und Badge.
  var hasAttachedEbook: Bool {
    if media.ebookFile != nil { return true }
    if let fmt = media.ebookFormat?.trimmingCharacters(in: .whitespacesAndNewlines), !fmt.isEmpty {
      return true
    }
    if let files = libraryFiles, files.contains(where: \.isEbook) { return true }
    return false
  }

  /// Primäre oder supplementäre E-Book-Datei zum Lesen (EPUB bevorzugt, sonst PDF).
  var readableAttachedEbook: (ino: String, format: ABSEbookFormat)? {
    if let ef = media.ebookFile,
      let fmt = ABSEbookFormat.resolve(
        format: ef.ebookFormat, ext: ef.metadata?.ext, filename: ef.metadata?.filename)
    {
      let ino = ef.ino.trimmingCharacters(in: .whitespacesAndNewlines)
      if !ino.isEmpty { return (ino, fmt) }
    }
    if let files = libraryFiles {
      if let epub = files.first(where: \.isEpub) { return (epub.ino, .epub) }
      if let pdf = files.first(where: \.isPdf) { return (pdf.ino, .pdf) }
    }
    return nil
  }

  var hasReadableAttachedEbook: Bool {
    readableAttachedEbook != nil || hasAttachedEbook
  }

  /// Alle erkennbaren E-Book-Formate (primär, supplementär, Katalog-Hinweis).
  var attachedEbookFormats: Set<ABSEbookFormat> {
    var out = Set<ABSEbookFormat>()
    if let ef = media.ebookFile,
      let fmt = ABSEbookFormat.resolve(
        format: ef.ebookFormat, ext: ef.metadata?.ext, filename: ef.metadata?.filename)
    {
      out.insert(fmt)
    }
    if let fmt = ABSEbookFormat.resolve(format: media.ebookFormat, ext: nil, filename: nil) {
      out.insert(fmt)
    }
    if let files = libraryFiles {
      if files.contains(where: \.isEpub) { out.insert(.epub) }
      if files.contains(where: \.isPdf) { out.insert(.pdf) }
    }
    if let known = EbookLocalStore.knownFormat(libraryItemId: id) {
      out.insert(known)
    }
    return out
  }

  /// Hat eine lesbare oder angehängte Datei des angegebenen Formats (EPUB/PDF).
  func hasAttachedEbookFormat(_ format: ABSEbookFormat, account: URL? = nil) -> Bool {
    if attachedEbookFormats.contains(format) { return true }
    if let account,
      let cached = EbookLocalStore.cachedEbookIfPresent(account: account, libraryItemId: id),
      cached.format == format
    {
      return true
    }
    // Hörbuch in der E-Book-Liste ohne Format-Metadaten (minified): meist supplementäres EPUB.
    if format == .epub, isAudiobookLibraryItem, hasAttachedEbook, attachedEbookFormats.isEmpty {
      return true
    }
    return false
  }

  /// Hörbuch mit supplementärer EPUB-Version (Katalog oder expandiertes Item).
  var hasSupplementalEpub: Bool {
    if epubIno != nil { return true }
    let fmt = (media.ebookFormat ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return fmt == "epub" && isAudiobookLibraryItem
  }

  var epubIno: String? {
    if let ef = media.ebookFile, ef.isEpub {
      let ino = ef.ino.trimmingCharacters(in: .whitespacesAndNewlines)
      if !ino.isEmpty { return ino }
    }
    let epubs = epubLibraryFiles
    guard !epubs.isEmpty else { return nil }
    if isAudiobookLibraryItem {
      if let primary = media.ebookFile, !primary.isEpub {
        return epubs.first?.ino
      }
      if let sup = epubs.first(where: { $0.isSupplementary == true }) {
        return sup.ino
      }
      if media.ebookFile == nil {
        return epubs.first?.ino
      }
    }
    return nil
  }
}

extension ABSBook {
  /// Podcast-Sendungen in `GET /libraries/…/items`: meist **ohne** `numTracks`/Dauer (Audio hängt an Episoden).
  var isListablePodcastLibraryItem: Bool {
    guard !id.isEmpty else { return false }
    if (media.numTracks ?? 0) > 0 || (media.duration ?? 0) > 0 { return true }
    let t = media.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !t.isEmpty { return true }
    let a = displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
    return !a.isEmpty && a != "—"
  }

  /// Hörbuch nur aus lokalem `ABSDownloadManifest` (Offline-Liste / Wiedergabe ohne Item-API).
  static func fromDownloadManifest(_ m: ABSDownloadManifest) -> ABSBook {
    let t = m.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let title = t.isEmpty ? "Audiobook" : t
    let a = m.displayAuthor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let authorLine = a.isEmpty ? "—" : a
    let trackModels = m.tracks.map { row in
      ABSAudioTrack(
        index: row.index,
        startOffset: row.startOffset,
        duration: row.duration,
        title: row.title,
        ino: nil
      )
    }
    let n = trackModels.count
    let sumDur = trackModels.reduce(0.0) { $0 + $1.duration }
    let dur = (m.totalDuration ?? (sumDur > 0 ? sumDur : nil)).flatMap { $0 > 0 ? $0 : nil }
    let meta = ABSBookMediaMetadata(offlineTitle: title, authorLine: authorLine)
    let chapterModels = m.chapters?.map { ABSChapter(manifest: $0) }
    let media = ABSBookMedia(
      metadata: meta,
      duration: dur,
      numTracks: n > 0 ? n : nil,
      chapters: chapterModels.flatMap { $0.isEmpty ? nil : $0 },
      tracks: n > 0 ? trackModels : nil,
      ebookFile: nil,
      ebookFormat: nil
    )
    return ABSBook(
      id: m.libraryItemId,
      libraryId: m.libraryId,
      media: media,
      addedAt: nil,
      updatedAt: nil,
      mediaId: nil
    )
  }

  /// Lokale Tracks/Kapitel aus `download.json`, Metadaten vom Server-Buch wenn vorhanden.
  func mergingLocalDownloadPlayback(_ local: ABSBook) -> ABSBook {
    let lm = local.media
    let meta = media.metadata.hasRichMetadata ? media.metadata : lm.metadata
    let mergedMedia = ABSBookMedia(
      metadata: meta,
      duration: lm.duration ?? media.duration,
      size: media.size ?? lm.size,
      numTracks: lm.numTracks ?? media.numTracks,
      chapters: lm.chapters ?? media.chapters,
      tracks: lm.tracks ?? media.tracks,
      podcastEpisodes: media.podcastEpisodes ?? lm.podcastEpisodes,
      ebookFile: media.ebookFile ?? lm.ebookFile,
      ebookFormat: media.ebookFormat ?? lm.ebookFormat
    )
    return ABSBook(
      id: id,
      libraryId: libraryId ?? local.libraryId,
      media: mergedMedia,
      addedAt: addedAt,
      updatedAt: updatedAt,
      mediaId: mediaId,
      libraryFiles: libraryFiles ?? local.libraryFiles
    )
  }

  /// Kapitel aus anderer Quelle übernehmen (z. B. Katalog, wenn altes Manifest ohne `chapters`).
  func withChapters(_ chapters: [ABSChapter]) -> ABSBook {
    guard !chapters.isEmpty else { return self }
    let media = ABSBookMedia(
      metadata: media.metadata,
      duration: media.duration,
      size: media.size,
      numTracks: media.numTracks,
      chapters: chapters,
      tracks: media.tracks,
      podcastEpisodes: media.podcastEpisodes,
      ebookFile: media.ebookFile,
      ebookFormat: media.ebookFormat
    )
    return ABSBook(
      id: id,
      libraryId: libraryId,
      media: media,
      addedAt: addedAt,
      updatedAt: updatedAt,
      mediaId: mediaId
    )
  }
}

// MARK: - Start / Personalized (Home)

struct ABSAuthorShelfEntity: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let numBooks: Int?
  let imagePath: String?

  var hasAuthorImage: Bool {
    let s = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !s.isEmpty
  }
}

struct ABSStartShelfSection: Identifiable {
  let id: String
  let category: String
  let displayTitle: String
  let books: [ABSBook]
  let podcastEpisodes: [ABSPodcastEpisodeListItem]
  let authors: [ABSAuthorShelfEntity]
  let series: [ABSLibrarySeriesListItem]

  var hasBooks: Bool { !books.isEmpty }
  var hasPodcastEpisodes: Bool { !podcastEpisodes.isEmpty }
  var hasAuthors: Bool { !authors.isEmpty }
  var hasSeries: Bool { !series.isEmpty }

  init(
    id: String,
    category: String,
    displayTitle: String,
    books: [ABSBook] = [],
    podcastEpisodes: [ABSPodcastEpisodeListItem] = [],
    authors: [ABSAuthorShelfEntity] = [],
    series: [ABSLibrarySeriesListItem] = []
  ) {
    self.id = id
    self.category = category
    self.displayTitle = displayTitle
    self.books = books
    self.podcastEpisodes = podcastEpisodes
    self.authors = authors
    self.series = series
  }
}

/// Gemischte Zeilen für Home-Regale (Weiterhören mit Büchern + Podcast-Folgen).
enum ABSStartShelfMergedRow: Identifiable {
  case book(ABSBook)
  case podcastEpisode(ABSPodcastEpisodeListItem)

  var id: String {
    switch self {
    case .book(let b): return "b:\(b.id)"
    case .podcastEpisode(let e): return "p:\(e.progressLookupKey)"
    }
  }

  private func progressTimestamp(_ progress: [String: ABSUserMediaProgress]) -> Int64 {
    switch self {
    case .book(let b):
      return progress[b.id]?.lastUpdate ?? 0
    case .podcastEpisode(let e):
      return progress[e.progressLookupKey]?.lastUpdate ?? 0
    }
  }

  static func merged(
    books: [ABSBook],
    podcastEpisodes: [ABSPodcastEpisodeListItem],
    progress: [String: ABSUserMediaProgress]
  ) -> [ABSStartShelfMergedRow] {
    var seenBookIds = Set<String>()
    var uniqueBooks: [ABSBook] = []
    uniqueBooks.reserveCapacity(books.count)
    for b in books where seenBookIds.insert(b.id).inserted {
      uniqueBooks.append(b)
    }
    let uniqueEpisodes = ABSPodcastEpisodeListItem.dedupeRows(podcastEpisodes)
    var rows: [ABSStartShelfMergedRow] = uniqueBooks.map { .book($0) }
    rows.append(contentsOf: uniqueEpisodes.map { .podcastEpisode($0) })
    rows.sort {
      let t0 = $0.progressTimestamp(progress)
      let t1 = $1.progressTimestamp(progress)
      if t0 != t1 { return t0 > t1 }
      switch ($0, $1) {
      case (.book(let a), .book(let b)):
        return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
      case (.podcastEpisode(let a), .podcastEpisode(let b)):
        return a.episodeTitle.localizedCaseInsensitiveCompare(b.episodeTitle) == .orderedAscending
      default:
        return $0.id < $1.id
      }
    }
    return rows
  }
}

enum ABSStartShelfLocalization {
  static let categoryTitles: [String: String] = [
    "recentlyListened": "Continue listening",
    "continueEbooks": "Continue reading",
    "continueSeries": "Continue series",
    "newestItems": "Recently added",
    "newestSeries": "Recent series",
    "recommended": "Recommended",
    "recentlyFinished": "Listen again",
    "newestAuthors": "New authors",
  ]

  static func displayTitle(category: String, serverLabel: String) -> String {
    if let t = categoryTitles[category] { return t }
    let trimmed = serverLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return category
  }

  /// Bekannte Server-`category`-Keys für die Schalter „Regal anzeigen“ (kein separates Fallback; gehört zu „Continue listening“).
  static let settingsCategoryOrder: [String] = [
    "recentlyListened", "continueSeries", "newestItems", "newestSeries",
    "recommended", "recentlyFinished", "newestAuthors",
  ]

  /// Regale mit Listen- vs. Cover-Streifen-Layout (Bücher und/oder Autoren) — kein Hero.
  static let categoriesWithBookLayoutSetting: Set<String> = [
    "continueSeries", "newestItems", "newestSeries", "recommended", "recentlyFinished",
    "newestAuthors",
  ]

  static func supportsBookLayoutSetting(category: String) -> Bool {
    categoriesWithBookLayoutSetting.contains(category)
  }
}

/// Home-Regal: volle Zeilenkarte oder horizontaler Cover-Streifen.
enum StartShelfBookLayout: String, CaseIterable, Identifiable {
  case list
  case compact

  var id: String { rawValue }

  var label: String {
    switch self {
    case .list: "List"
    case .compact: "Covers"
    }
  }

  static func defaultForCategory(_ category: String) -> StartShelfBookLayout {
    category == "newestItems" ? .compact : .list
  }
}

extension ABSStartShelfLocalization {
  /// `/personalized` liefert oft `id` wie `continue-listening`; die Schalter nutzen camelCase-Keys wie `recentlyListened`.
  static func normalizedSettingsCategory(shelfId: String, apiCategory: String?) -> String {
    if let c = apiCategory, settingsCategoryOrder.contains(c) { return c }
    if settingsCategoryOrder.contains(shelfId) { return shelfId }
    let kebabToSettings: [String: String] = [
      "continue-listening": "recentlyListened",
      "continue-reading": "recentlyListened",
      "continue-series": "continueSeries",
      "recently-added": "newestItems",
      "recent-series": "newestSeries",
      "discover": "recommended",
      "listen-again": "recentlyFinished",
      "read-again": "recentlyFinished",
      "newest-authors": "newestAuthors",
      "newest-episodes": "newestItems",
    ]
    return kebabToSettings[shelfId] ?? shelfId
  }
}

// MARK: - Library browse (catalog sections)

/// `GET /api/libraries/:id/authors` (ältere Server: nur `authors`, neuere: `results` + `total` mit Pagination).
struct ABSLibraryAuthorsAPIEnvelope: Decodable {
  let authors: [ABSLibraryAuthorListItem]?
  let results: [ABSLibraryAuthorListItem]?
  let total: Int?

  enum CodingKeys: String, CodingKey {
    case authors, results, total
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    authors = try c.decodeIfPresent([ABSLibraryAuthorListItem].self, forKey: .authors)
    results = try c.decodeIfPresent([ABSLibraryAuthorListItem].self, forKey: .results)
    if let t = try? c.decode(Int.self, forKey: .total) {
      total = t
    } else if let s = try? c.decode(String.self, forKey: .total), let t = Int(s) {
      total = t
    } else {
      total = nil
    }
  }

  func itemsAndTotal() -> ([ABSLibraryAuthorListItem], Int) {
    if let results {
      return (results, total ?? results.count)
    }
    let a = authors ?? []
    return (a, total ?? a.count)
  }
}

/// `GET /api/libraries/:id/authors` (Legacy-Form ohne Pagination).
struct ABSLibraryAuthorsEnvelope: Decodable {
  let authors: [ABSLibraryAuthorListItem]
}

/// `GET /api/libraries/:id/authors`
struct ABSLibraryAuthorListItem: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let numBooks: Int?
  let imagePath: String?

  var hasAuthorImage: Bool {
    let s = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !s.isEmpty
  }
}

/// `GET /api/authors/:id` (optional `include=items,series` und `library`).
struct ABSAuthorDetail: Decodable {
  let id: String
  let name: String
  let description: String?
  let libraryItems: [ABSBook]?
  let series: [ABSAuthorDetailSeries]?
}

/// Serien unter einem Autor (`include=items,series`).
struct ABSAuthorDetailSeries: Decodable, Identifiable {
  let id: String
  let name: String
  let items: [ABSBook]?
}

/// Darstellung Autor-Detail: eine Serie mit ihren Büchern (Reihenfolge aus API/`sequence`).
struct EntityDetailAuthorSeriesSection: Identifiable {
  let id: String
  let name: String
  let books: [ABSBook]
}

/// `GET /api/series/:id`.
struct ABSSeriesDetail: Decodable {
  let id: String
  let name: String
  let description: String?
}

/// `GET /api/libraries/:id/narrators`
struct ABSLibraryNarratorListItem: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let numBooks: Int?
}

struct ABSLibraryNarratorsEnvelope: Decodable {
  let narrators: [ABSLibraryNarratorListItem]
}

/// Eintrag aus `GET /api/libraries/:id/series`
struct ABSLibrarySeriesListItem: Decodable, Identifiable {
  let id: String
  let name: String
  let books: [ABSBook]?

  enum CodingKeys: String, CodingKey {
    case id, name, books
  }
}

/// Eintrag aus `GET /api/libraries/:id/collections`
struct ABSLibraryCollectionListItem: Decodable, Identifiable {
  let id: String
  let name: String
  let books: [ABSBook]?
  let createdAt: TimeInterval?
  let lastUpdate: TimeInterval?

  enum CodingKeys: String, CodingKey {
    case id, name, books, createdAt, lastUpdate
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    books = try c.decodeIfPresent([ABSBook].self, forKey: .books)
    createdAt = Self.decodeOptionalMillis(c, key: .createdAt)
    lastUpdate = Self.decodeOptionalMillis(c, key: .lastUpdate)
  }

  private static func decodeOptionalMillis(
    _ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
  ) -> TimeInterval? {
    if let d = try? c.decode(Double.self, forKey: key) { return d / 1000.0 }
    if let i = try? c.decode(Int64.self, forKey: key) { return TimeInterval(i) / 1000.0 }
    if let i = try? c.decode(Int.self, forKey: key) { return TimeInterval(i) / 1000.0 }
    if let s = try? c.decode(String.self, forKey: key), let d = Double(s) { return d / 1000.0 }
    return nil
  }
}

struct ABSLibraryResultsPageEnvelope<T: Decodable>: Decodable {
  let results: [T]
  let total: Int

  enum CodingKeys: String, CodingKey {
    case results, total
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    results = (try? c.decode([T].self, forKey: .results)) ?? []
    if let t = try? c.decode(Int.self, forKey: .total) {
      total = t
    } else if let s = try? c.decode(String.self, forKey: .total), let t = Int(s) {
      total = t
    } else {
      total = results.count
    }
  }
}

// MARK: - Search

struct ABSSearchBookRow: Decodable {
  let libraryItem: ABSBook
}

struct ABSSearchAuthorRow: Decodable, Identifiable {
  let id: String
  let name: String
  let numBooks: Int?
}

struct ABSSearchNarratorRow: Decodable, Identifiable {
  let name: String
  let numBooks: Int?
  var id: String { name }
}

struct ABSSearchSeriesRow: Decodable, Identifiable {
  let id: String
  let name: String
  let books: [ABSBook]?

  enum CodingKeys: String, CodingKey {
    case id, name, books, series
  }

  init(id: String, name: String, books: [ABSBook]?) {
    self.id = id
    self.name = name
    self.books = books
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if c.contains(.series) {
      let nested = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: .series)
      id = try nested.decode(String.self, forKey: .id)
      name = try nested.decode(String.self, forKey: .name)
    } else {
      id = try c.decode(String.self, forKey: .id)
      name = try c.decode(String.self, forKey: .name)
    }
    books = try? c.decode([ABSBook].self, forKey: .books)
  }
}

struct ABSSearchNamedCount: Decodable, Identifiable {
  let name: String
  let numItems: Int?
  var id: String { name }
}

/// `GET /api/libraries/:id/filterdata` — Optionen für Katalog-Filter (Audiobookshelf-Web-UI).
struct ABSLibraryFilterAuthor: Codable, Identifiable, Hashable {
  let id: String
  let name: String
}

struct ABSLibraryFilterSeries: Codable, Identifiable, Hashable {
  let id: String
  let name: String
}

struct ABSLibraryFilterData: Codable {
  let authors: [ABSLibraryFilterAuthor]?
  let tags: [String]?
  let series: [ABSLibraryFilterSeries]?
  let narrators: [String]?
  let languages: [String]?
  let publishers: [String]?
  let publishedDecades: [String]?
  let genres: [String]?
}

struct ABSSearchResponse: Decodable {
  /// Hörbücher-Suche: Treffer unter `book`.
  let book: [ABSSearchBookRow]
  /// Podcast-Suche: Shows unter `podcast`, Folgen-Treffer oft unter `episodes` (je Show mit `recentEpisode`).
  let podcast: [ABSSearchBookRow]
  let episodes: [ABSSearchBookRow]
  let authors: [ABSSearchAuthorRow]
  let narrators: [ABSSearchNarratorRow]
  let series: [ABSSearchSeriesRow]
  let tags: [ABSSearchNamedCount]
  let genres: [ABSSearchNamedCount]

  enum CodingKeys: String, CodingKey {
    case book, podcast, episodes, authors, narrators, series, tags, genres
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    book = (try? c.decode([ABSSearchBookRow].self, forKey: .book)) ?? []
    podcast = (try? c.decode([ABSSearchBookRow].self, forKey: .podcast)) ?? []
    episodes = (try? c.decode([ABSSearchBookRow].self, forKey: .episodes)) ?? []
    authors = (try? c.decode([ABSSearchAuthorRow].self, forKey: .authors)) ?? []
    narrators = (try? c.decode([ABSSearchNarratorRow].self, forKey: .narrators)) ?? []
    series = (try? c.decode([ABSSearchSeriesRow].self, forKey: .series)) ?? []
    tags = (try? c.decode([ABSSearchNamedCount].self, forKey: .tags)) ?? []
    genres = (try? c.decode([ABSSearchNamedCount].self, forKey: .genres)) ?? []
  }

  /// Einträge für die Bücher-Suche (nur `book`-Key).
  func bookSearchPlayableLibraryItems(minDuration: (ABSBook) -> Double) -> [ABSBook] {
    book.map(\.libraryItem).filter {
      ($0.media.numTracks ?? 0) > 0 || minDuration($0) > 0
    }
  }

  /// Podcast-Library-Suche: `podcast` + `episodes` + ggf. `book`, ohne Dubletten nach Show-ID.
  func podcastSearchShowLibraryItems() -> [ABSBook] {
    var seen = Set<String>()
    var out: [ABSBook] = []
    out.reserveCapacity(book.count + podcast.count + episodes.count)
    for row in podcast + episodes + book {
      let li = row.libraryItem
      guard li.isListablePodcastLibraryItem else { continue }
      if seen.insert(li.id).inserted { out.append(li) }
    }
    return out
  }
}

// MARK: - Play Session

struct ABSPlaySessionRequest: Encodable {
  let forceDirectPlay: Bool
  let forceTranscode: Bool
  let supportedMimeTypes: [String]
  let mediaPlayer: String
  let deviceInfo: DeviceInfo

  struct DeviceInfo: Encodable {
    let clientName: String
    let clientVersion: String?
    let deviceId: String
  }

  init(deviceId: String, clientVersion: String?) {
    forceDirectPlay = true
    forceTranscode = false
    supportedMimeTypes = [
      "audio/flac", "audio/mpeg", "audio/mp4", "audio/ogg", "audio/aac", "audio/x-aiff",
      "audio/webm",
    ]
    mediaPlayer = "ios"
    deviceInfo = DeviceInfo(
      clientName: "Abstand",
      clientVersion: clientVersion,
      deviceId: deviceId
    )
  }
}

struct ABSPlaySession: Decodable {
  let id: String
  let userId: String?
  let libraryItemId: String
  let episodeId: String?
  let mediaType: String?
  let currentTime: Double
  let duration: Double
  let audioTracks: [ABSAudioTrack]?
  let chapters: [ABSChapter]?
  let libraryItem: ABSBook
  let displayTitle: String?
  let displayAuthor: String?

  enum CodingKeys: String, CodingKey {
    case id, userId, libraryItemId, episodeId, mediaType
    case currentTime, duration, audioTracks, chapters, libraryItem
    case displayTitle, displayAuthor
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    userId = try c.decodeIfPresent(String.self, forKey: .userId)
    libraryItemId = try c.decode(String.self, forKey: .libraryItemId)
    episodeId = try c.decodeIfPresent(String.self, forKey: .episodeId)
    mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
    currentTime = try c.decode(Double.self, forKey: .currentTime)
    duration = try c.decode(Double.self, forKey: .duration)
    audioTracks = try c.decodeIfPresent([ABSAudioTrack].self, forKey: .audioTracks)
    chapters = try c.decodeIfPresent([ABSChapter].self, forKey: .chapters)
    displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
    displayAuthor = try c.decodeIfPresent(String.self, forKey: .displayAuthor)
    libraryItem = try c.decode(ABSBook.self, forKey: .libraryItem)
  }

  /// Mini-Player / Sperrbildschirm: Podcast-Folgentitel statt Sendungsname allein.
  func bookForPlayerUI() -> ABSBook {
    guard (mediaType ?? "").lowercased() == "podcast",
      let raw = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else { return libraryItem }
    let authRaw = displayAuthor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let authOpt: String? = authRaw.isEmpty ? nil : displayAuthor
    let meta = ABSBookMediaMetadata(copying: libraryItem.media.metadata, title: raw, authorName: authOpt)
    let dur = duration > 0 ? duration : libraryItem.media.duration
    let trackCount = audioTracks?.count ?? libraryItem.media.numTracks ?? 0
    let nt = max(trackCount, 1)
    let media = ABSBookMedia(
      metadata: meta,
      duration: dur,
      size: libraryItem.media.size,
      numTracks: nt,
      chapters: libraryItem.media.chapters,
      tracks: libraryItem.media.tracks
    )
    return ABSBook(
      id: libraryItem.id,
      libraryId: libraryItem.libraryId,
      media: media,
      addedAt: libraryItem.addedAt,
      updatedAt: libraryItem.updatedAt,
      mediaId: libraryItem.mediaId
    )
  }
}

// MARK: - Listening sessions (`GET /api/me/listening-sessions`)

struct ABSListeningSessionsPayload: Decodable {
  let total: Int
  let numPages: Int
  let page: Int
  let itemsPerPage: Int
  let sessions: [ABSListeningSession]

  enum CodingKeys: String, CodingKey {
    case total, numPages, page, itemsPerPage, sessions
  }

  init(total: Int, numPages: Int, page: Int, itemsPerPage: Int, sessions: [ABSListeningSession]) {
    self.total = total
    self.numPages = numPages
    self.page = page
    self.itemsPerPage = itemsPerPage
    self.sessions = sessions
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
    numPages = try c.decodeIfPresent(Int.self, forKey: .numPages) ?? 0
    page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 0
    itemsPerPage = try c.decodeIfPresent(Int.self, forKey: .itemsPerPage) ?? 0
    sessions = try c.decodeIfPresent([ABSListeningSession].self, forKey: .sessions) ?? []
  }

  /// Wenn einzelne Session-Objekte vom strikten `Decodable` abweichen, trotzdem so viele Zeilen wie möglich parsen.
  static func decodeLenient(data: Data, jsonDecoder: JSONDecoder) throws -> ABSListeningSessionsPayload {
    do {
      return try jsonDecoder.decode(ABSListeningSessionsPayload.self, from: data)
    } catch let primary {
      guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw primary
      }
      func jsonInt(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let i as Int64: return Int(i)
        case let d as Double: return Int(d.rounded())
        case let s as String: return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
      }
      let rawList = (root["sessions"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
      var parsed: [ABSListeningSession] = []
      parsed.reserveCapacity(rawList.count)
      for d in rawList {
        if let s = ABSListeningSession(lenientDictionary: d) {
          parsed.append(s)
        }
      }
      let total = jsonInt(root["total"]) ?? parsed.count
      let numPages = jsonInt(root["numPages"]) ?? jsonInt(root["num_pages"]) ?? (parsed.isEmpty ? 0 : 1)
      let page = jsonInt(root["page"]) ?? 0
      let itemsPerPage =
        jsonInt(root["itemsPerPage"]) ?? jsonInt(root["items_per_page"]) ?? max(parsed.count, 1)
      return ABSListeningSessionsPayload(
        total: total, numPages: numPages, page: page, itemsPerPage: itemsPerPage, sessions: parsed)
    }
  }
}

struct ABSListeningSession: Decodable, Identifiable, Hashable {
  let id: String
  let libraryItemId: String
  /// Buch-Medien-UUID (entspricht oft `ABSBook.mediaId`), wenn `libraryItemId` in der API fehlt.
  let bookId: String?
  let episodeId: String?
  let duration: Double
  let startTime: Double
  let currentTime: Double
  let timeListening: Int
  let startedAt: Int64
  let updatedAt: Int64

  enum CodingKeys: String, CodingKey {
    case id, libraryItemId, bookId, episodeId, duration, startTime, currentTime, timeListening, startedAt, updatedAt
    case libraryItem
  }

  init(
    id: String,
    libraryItemId: String,
    bookId: String?,
    episodeId: String?,
    duration: Double,
    startTime: Double,
    currentTime: Double,
    timeListening: Int,
    startedAt: Int64,
    updatedAt: Int64
  ) {
    self.id = id
    self.libraryItemId = libraryItemId
    self.bookId = bookId
    self.episodeId = episodeId
    self.duration = duration
    self.startTime = startTime
    self.currentTime = currentTime
    self.timeListening = timeListening
    self.startedAt = startedAt
    self.updatedAt = updatedAt
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = Self.decodeStringish(c, forKey: .id) ?? ""
    if let lid = Self.decodeStringish(c, forKey: .libraryItemId), !lid.isEmpty {
      libraryItemId = lid
    } else if let nested = try? c.nestedContainer(keyedBy: NestedLibraryItemKeys.self, forKey: .libraryItem),
      let lid = Self.decodeStringish(nested, forKey: .id), !lid.isEmpty
    {
      libraryItemId = lid
    } else {
      libraryItemId = ""
    }
    if let b = Self.decodeStringish(c, forKey: .bookId), !b.isEmpty {
      bookId = b
    } else {
      bookId = nil
    }
    episodeId = try c.decodeIfPresent(String.self, forKey: .episodeId)
    duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
    startTime = try c.decodeIfPresent(Double.self, forKey: .startTime) ?? 0
    currentTime = try c.decodeIfPresent(Double.self, forKey: .currentTime) ?? 0
    if let i = try c.decodeIfPresent(Int.self, forKey: .timeListening) {
      timeListening = i
    } else if let d = try c.decodeIfPresent(Double.self, forKey: .timeListening) {
      timeListening = Int(d.rounded())
    } else {
      timeListening = 0
    }
    if let ms = try c.decodeIfPresent(Int64.self, forKey: .startedAt) {
      startedAt = ms
    } else if let d = try c.decodeIfPresent(Double.self, forKey: .startedAt) {
      startedAt = Int64(d.rounded())
    } else {
      startedAt = 0
    }
    if let ms = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) {
      updatedAt = ms
    } else if let d = try c.decodeIfPresent(Double.self, forKey: .updatedAt) {
      updatedAt = Int64(d.rounded())
    } else {
      updatedAt = 0
    }
  }

  private enum NestedLibraryItemKeys: String, CodingKey {
    case id
  }

  private static func decodeStringish(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
    if let s = try? c.decode(String.self, forKey: key), !s.isEmpty { return s }
    if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
    return nil
  }

  private static func decodeStringish(_ c: KeyedDecodingContainer<NestedLibraryItemKeys>, forKey key: NestedLibraryItemKeys)
    -> String?
  {
    if let s = try? c.decode(String.self, forKey: key), !s.isEmpty { return s }
    if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
    return nil
  }

  func hash(into hasher: inout Hasher) { hasher.combine(id) }
  static func == (lhs: ABSListeningSession, rhs: ABSListeningSession) -> Bool { lhs.id == rhs.id }
}

extension ABSListeningSession {
  /// Fallback-Parsing einzelner Session-Dictionaries, wenn `JSONDecoder` am Gesamt-Array scheitert.
  init?(lenientDictionary d: [String: Any]) {
    func jsonString(_ keys: [String]) -> String? {
      for k in keys {
        guard let v = d[k] else { continue }
        if v is NSNull { continue }
        if let s = v as? String {
          let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
          if !t.isEmpty { return t }
        } else if let i = v as? Int { return String(i) }
        else if let i = v as? Int64 { return String(i) }
        else if let x = v as? Double { return String(Int(x)) }
      }
      return nil
    }
    func jsonDouble(_ keys: [String]) -> Double {
      for k in keys {
        guard let v = d[k] else { continue }
        if let x = v as? Double { return x }
        if let i = v as? Int { return Double(i) }
        if let i = v as? Int64 { return Double(i) }
        if let s = v as? String, let x = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return x }
      }
      return 0
    }
    func jsonInt(_ keys: [String]) -> Int {
      for k in keys {
        guard let v = d[k] else { continue }
        if let i = v as? Int { return i }
        if let i = v as? Int64 { return Int(i) }
        if let x = v as? Double { return Int(x.rounded()) }
        if let s = v as? String, let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return i }
      }
      return 0
    }
    func jsonInt64(_ keys: [String]) -> Int64 {
      for k in keys {
        guard let v = d[k] else { continue }
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let x = v as? Double { return Int64(x.rounded()) }
        if let s = v as? String, let i = Int64(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return i }
      }
      return 0
    }

    guard let id = jsonString(["id", "sessionId"]), !id.isEmpty else { return nil }

    let nestedLi = (d["libraryItem"] as? [String: Any]) ?? (d["library_item"] as? [String: Any])
    let fromNested = nestedLi.flatMap { li -> String? in
      for k in ["id"] {
        guard let v = li[k] else { continue }
        if let s = v as? String {
          let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
          if !t.isEmpty { return t }
        } else if let i = v as? Int { return String(i) }
        else if let i = v as? Int64 { return String(i) }
      }
      return nil
    }

    let libraryItemId =
      jsonString(["libraryItemId", "library_item_id"]) ?? fromNested ?? ""
    let bookRaw = jsonString(["bookId", "book_id"])
    let bookId = bookRaw.flatMap { $0.isEmpty ? nil : $0 }

    let episodeRaw = jsonString(["episodeId", "episode_id"])
    let episodeId = episodeRaw.flatMap { $0.isEmpty ? nil : $0 }

    self.init(
      id: id,
      libraryItemId: libraryItemId,
      bookId: bookId,
      episodeId: episodeId,
      duration: jsonDouble(["duration"]),
      startTime: jsonDouble(["startTime", "start_time"]),
      currentTime: jsonDouble(["currentTime", "current_time"]),
      timeListening: jsonInt(["timeListening", "time_listening"]),
      startedAt: jsonInt64(["startedAt", "started_at"]),
      updatedAt: jsonInt64(["updatedAt", "updated_at"])
    )
  }
}

/// Server-Einstellungen aus `/login`, `/authorize` und `PATCH /api/settings`.
// MARK: - Server admin (root)

struct ABSUsersListResponse: Decodable {
  let users: [ABSAdminUserSummary]
}

struct ABSAdminUserSummary: Decodable, Identifiable {
  let id: String
  let username: String
  let type: String?
  let isActive: Bool?
  let lastSeen: Int64?

  var isRoot: Bool { (type ?? "").lowercased() == "root" }

  var typeLabel: String? {
    let t = (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !t.isEmpty, t != "user" else { return nil }
    return t
  }
}

struct ABSAdminUserDetail {
  let id: String
  let username: String
  let type: String?
  let lastSeen: Int64?
  let mediaProgress: [ABSAdminMediaProgressRow]

  init(
    id: String,
    username: String,
    type: String?,
    lastSeen: Int64?,
    mediaProgress: [ABSAdminMediaProgressRow]
  ) {
    self.id = id
    self.username = username
    self.type = type
    self.lastSeen = lastSeen
    self.mediaProgress = mediaProgress
  }

  var typeLabel: String? {
    let t = (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !t.isEmpty, t != "user" else { return nil }
    return t
  }

  var lastSeenCaption: String {
    guard let ms = lastSeen, ms > 0 else { return "Never signed in" }
    let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    let rel = RelativeDateTimeFormatter()
    rel.unitsStyle = .short
    return "● Last seen \(rel.localizedString(for: d, relativeTo: Date()))"
  }

  var mediaProgressSorted: [ABSAdminMediaProgressRow] {
    mediaProgress.sorted { ($0.lastUpdate ?? 0) > ($1.lastUpdate ?? 0) }
  }

  static func decode(data: Data) throws -> ABSAdminUserDetail {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ABSAPIError.decoding(
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "user detail not an object")))
    }
    func str(_ keys: [String]) -> String {
      for k in keys {
        guard let v = root[k], !(v is NSNull) else { continue }
        if let s = v as? String {
          let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
          if !t.isEmpty { return t }
        } else if let i = v as? Int { return String(i) }
      }
      return ""
    }
    func int64(_ keys: [String]) -> Int64? {
      for k in keys {
        guard let v = root[k], !(v is NSNull) else { continue }
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let d = v as? Double { return Int64(d.rounded()) }
      }
      return nil
    }
    var libraryItemById: [String: [String: Any]] = [:]
    if let items = root["libraryItems"] as? [[String: Any]] {
      for li in items {
        guard let id = li["id"] as? String else { continue }
        let tid = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tid.isEmpty else { continue }
        libraryItemById[tid] = li
      }
    }
    let progressRaw = (root["mediaProgress"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    let rows = progressRaw.compactMap { raw -> ABSAdminMediaProgressRow? in
      var dict = raw
      if dict["libraryItem"] == nil,
        let lid = (raw["libraryItemId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !lid.isEmpty,
        let li = libraryItemById[lid]
      {
        dict["libraryItem"] = li
      }
      return ABSAdminMediaProgressRow(lenientDictionary: dict)
    }
    return ABSAdminUserDetail(
      id: str(["id"]),
      username: str(["username"]),
      type: str(["type"]).isEmpty ? nil : str(["type"]),
      lastSeen: int64(["lastSeen", "last_seen"]),
      mediaProgress: rows
    )
  }
}

struct ABSAdminMediaProgressRow: Identifiable {
  let libraryItemId: String
  let episodeId: String?
  let duration: Double
  let progress: Double
  let currentTime: Double
  let isFinished: Bool
  let lastUpdate: Int64?
  let title: String
  let author: String

  var id: String {
    if let e = episodeId, !e.isEmpty { return "\(libraryItemId)-\(e)" }
    return libraryItemId
  }

  var isInProgress: Bool { !isFinished && (progress > 0.02 || currentTime > 1) }

  var displayProgressFraction: Double {
    if isFinished { return 1 }
    if progress > 0 { return min(1, progress) }
    guard duration > 0 else { return 0 }
    return min(1, currentTime / duration)
  }

  var progressCaption: String {
    isFinished ? "Finished" : "\(Int((displayProgressFraction * 100).rounded()))%"
  }

  var durationCaption: String {
    "\(formatPlaybackDurationShortHuman(currentTime)) / \(formatPlaybackDurationShortHuman(max(duration, currentTime, 1)))"
  }

  var timeCaption: String {
    guard let ms = lastUpdate, ms > 0 else { return "" }
    let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    let rel = RelativeDateTimeFormatter()
    rel.unitsStyle = .short
    return rel.localizedString(for: d, relativeTo: Date())
  }

  var resolvedDisplayTitle: String {
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty || t == "—" ? libraryItemId : t
  }

  var resolvedDisplayAuthor: String {
    let a = author.trimmingCharacters(in: .whitespacesAndNewlines)
    return a.isEmpty || a == "—" ? "—" : a
  }

  /// Für `BookRowCard.authorLineOverride` — nur wenn ein echter Autorenname vorliegt.
  var resolvedAuthorForCard: String? {
    let a = author.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !a.isEmpty, a != "—" else { return nil }
    return a
  }

  func asUserMediaProgress() -> ABSUserMediaProgress {
    let progVal: Double = {
      if progress > 0 { return min(1, max(0, progress)) }
      guard duration > 0 else { return 0 }
      return min(1, currentTime / duration)
    }()
    return ABSUserMediaProgress(
      libraryItemId: libraryItemId,
      episodeId: episodeId,
      duration: max(duration, currentTime, 1),
      progress: isFinished ? 1 : progVal,
      currentTime: currentTime,
      isFinished: isFinished,
      lastUpdate: lastUpdate
    )
  }

  func asBookStub() -> ABSBook {
    let meta = ABSBookMediaMetadata(
      offlineTitle: resolvedDisplayTitle,
      authorLine: resolvedDisplayAuthor
    )
    let dur = duration > 0 ? duration : nil
    let media = ABSBookMedia(
      metadata: meta,
      duration: dur,
      numTracks: nil,
      chapters: nil,
      tracks: nil,
      ebookFile: nil,
      ebookFormat: nil
    )
    return ABSBook(
      id: libraryItemId,
      libraryId: nil,
      media: media,
      addedAt: nil,
      updatedAt: nil,
      mediaId: nil
    )
  }

  var needsTitleEnrichment: Bool { Self.isPlaceholderMetadata(title) }

  var needsAuthorEnrichment: Bool { Self.isPlaceholderMetadata(author) }

  var needsDisplayMetadataEnrichment: Bool { needsTitleEnrichment || needsAuthorEnrichment }

  func withDisplayMetadata(title: String, author: String) -> ABSAdminMediaProgressRow {
    ABSAdminMediaProgressRow(
      libraryItemId: libraryItemId,
      episodeId: episodeId,
      duration: duration,
      progress: progress,
      currentTime: currentTime,
      isFinished: isFinished,
      lastUpdate: lastUpdate,
      title: title,
      author: author
    )
  }

  init(
    libraryItemId: String,
    episodeId: String?,
    duration: Double,
    progress: Double,
    currentTime: Double,
    isFinished: Bool,
    lastUpdate: Int64?,
    title: String,
    author: String
  ) {
    self.libraryItemId = libraryItemId
    self.episodeId = episodeId
    self.duration = duration
    self.progress = progress
    self.currentTime = currentTime
    self.isFinished = isFinished
    self.lastUpdate = lastUpdate
    self.title = title
    self.author = author
  }

  static func isPlaceholderMetadata(_ value: String) -> Bool {
    let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty || t == "—"
  }

  private static func applyMetadata(
    title: inout String,
    author: inout String,
    from meta: [String: Any]
  ) {
    if let t = meta["title"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      isPlaceholderMetadata(title)
    {
      title = t
    }
    if let t = meta["displayTitle"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      isPlaceholderMetadata(title)
    {
      title = t
    }
    if let a = meta["author"] as? String, !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      isPlaceholderMetadata(author)
    {
      author = a
    }
    if let a = meta["authorName"] as? String, !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      isPlaceholderMetadata(author)
    {
      author = a
    }
    if let a = meta["displayAuthor"] as? String, !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      isPlaceholderMetadata(author)
    {
      author = a
    }
  }

  /// Titel/Autor einer Podcast-Folge aus `GET /api/items/:id?expanded=1`.
  static func episodeMetadata(fromItemJSON data: Data, episodeId: String) -> (title: String, author: String)? {
    let eid = episodeId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !eid.isEmpty,
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let itemRoot = (root["libraryItem"] as? [String: Any]) ?? root
    var showTitle: String?
    var showAuthor: String?
    if let dt = itemRoot["displayTitle"] as? String,
      !dt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      showTitle = dt
    }
    if let da = itemRoot["displayAuthor"] as? String,
      !da.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      showAuthor = da
    }
    if let media = itemRoot["media"] as? [String: Any],
      let meta = media["metadata"] as? [String: Any]
    {
      if showTitle == nil, let t = meta["title"] as? String,
        !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        showTitle = t
      }
      if showAuthor == nil, let a = meta["author"] as? String,
        !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        showAuthor = a
      }
    }
    let episodeLists = [
      itemRoot["episodes"] as? [[String: Any]],
      (itemRoot["media"] as? [String: Any])?["episodes"] as? [[String: Any]],
    ]
    for list in episodeLists {
      guard let episodes = list else { continue }
      for ep in episodes {
        guard (ep["id"] as? String) == eid else { continue }
        let title =
          (ep["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
          ?? (ep["displayTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { break }
        let author =
          (ep["displayAuthor"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
          ?? showAuthor
          ?? "—"
        return (title, author.isEmpty ? "—" : author)
      }
    }
    return nil
  }

  private static func applyLibraryItemMetadata(
    title: inout String,
    author: inout String,
    libraryItem: [String: Any],
    episodeId: String?
  ) {
    if let dt = libraryItem["displayTitle"] as? String,
      !dt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      isPlaceholderMetadata(title)
    {
      title = dt
    }
    if let da = libraryItem["displayAuthor"] as? String,
      !da.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      isPlaceholderMetadata(author)
    {
      author = da
    }
    if let media = libraryItem["media"] as? [String: Any],
      let meta = media["metadata"] as? [String: Any]
    {
      applyMetadata(title: &title, author: &author, from: meta)
    }
    let eid = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !eid.isEmpty, let episodes = libraryItem["episodes"] as? [[String: Any]] {
      for ep in episodes {
        guard let id = ep["id"] as? String, id == eid else { continue }
        if let t = ep["title"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          title = t
        }
        break
      }
    }
    if isPlaceholderMetadata(title), let recent = libraryItem["recentEpisode"] as? [String: Any] {
      if let t = recent["title"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        title = t
      }
    }
  }

  init?(lenientDictionary d: [String: Any]) {
    func jsonString(_ keys: [String]) -> String? {
      for k in keys {
        guard let v = d[k], !(v is NSNull) else { continue }
        if let s = v as? String {
          let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
          if !t.isEmpty { return t }
        } else if let i = v as? Int { return String(i) }
      }
      return nil
    }
    func jsonDouble(_ keys: [String]) -> Double {
      for k in keys {
        guard let v = d[k], !(v is NSNull) else { continue }
        if let x = v as? Double { return x }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String, let x = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return x }
      }
      return 0
    }
    func jsonInt64(_ keys: [String]) -> Int64? {
      for k in keys {
        guard let v = d[k], !(v is NSNull) else { continue }
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let x = v as? Double { return Int64(x.rounded()) }
      }
      return nil
    }
    func jsonBool(_ keys: [String]) -> Bool {
      for k in keys {
        guard let v = d[k], !(v is NSNull) else { continue }
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i != 0 }
      }
      return false
    }

    let rawId = jsonString(["id"]) ?? ""
    let explicitLi = jsonString(["libraryItemId", "library_item_id"])
    let resolvedLibraryItemId: String = {
      if let explicitLi, !explicitLi.isEmpty { return explicitLi }
      if let r = rawId.range(of: "-ep_") { return String(rawId[..<r.lowerBound]) }
      return rawId
    }()
    guard !resolvedLibraryItemId.isEmpty else { return nil }

    let resolvedEpisodeId = jsonString(["episodeId", "episode_id"])
    let resolvedDuration = jsonDouble(["duration"])
    let resolvedProgress = jsonDouble(["progress"])
    let resolvedCurrentTime = jsonDouble(["currentTime", "current_time"])
    let resolvedIsFinished = jsonBool(["isFinished", "is_finished"])
    let resolvedLastUpdate = jsonInt64(["lastUpdate", "last_update"])

    var resolvedTitle = "—"
    var resolvedAuthor = "—"
    if let media = d["media"] as? [String: Any],
      let meta = media["metadata"] as? [String: Any]
    {
      Self.applyMetadata(title: &resolvedTitle, author: &resolvedAuthor, from: meta)
    }
    if let ep = d["episode"] as? [String: Any] {
      Self.applyMetadata(title: &resolvedTitle, author: &resolvedAuthor, from: ep)
    }
    if let li = d["libraryItem"] as? [String: Any] {
      Self.applyLibraryItemMetadata(
        title: &resolvedTitle,
        author: &resolvedAuthor,
        libraryItem: li,
        episodeId: resolvedEpisodeId
      )
    }
    if let topTitle = jsonString(["title", "displayTitle"]), Self.isPlaceholderMetadata(resolvedTitle) {
      resolvedTitle = topTitle
    }
    if let topAuthor = jsonString(["author", "authorName", "displayAuthor"]),
      Self.isPlaceholderMetadata(resolvedAuthor)
    {
      resolvedAuthor = topAuthor
    }
    self.init(
      libraryItemId: resolvedLibraryItemId,
      episodeId: resolvedEpisodeId,
      duration: resolvedDuration,
      progress: resolvedProgress,
      currentTime: resolvedCurrentTime,
      isFinished: resolvedIsFinished,
      lastUpdate: resolvedLastUpdate,
      title: resolvedTitle,
      author: resolvedAuthor
    )
  }
}

struct ABSUsersOnlineResponse: Decodable {
  let usersOnline: [ABSAdminUserOnlineRow]?

  enum CodingKeys: String, CodingKey {
    case usersOnline
  }
}

struct ABSAdminUserOnlineRow: Decodable {
  let id: String
}

struct ABSLibraryStatsResponse: Decodable {
  let totalItems: Int
  let totalAuthors: Int
  let totalGenres: Int
  let totalDuration: Double
  let totalSize: Int64
  let numAudioTrack: Int

  enum CodingKeys: String, CodingKey {
    case totalItems, totalAuthors, totalGenres, totalDuration, totalSize, numAudioTrack
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    totalItems = try c.decodeIfPresent(Int.self, forKey: .totalItems) ?? 0
    totalAuthors = try c.decodeIfPresent(Int.self, forKey: .totalAuthors) ?? 0
    totalGenres = try c.decodeIfPresent(Int.self, forKey: .totalGenres) ?? 0
    if let d = try? c.decode(Double.self, forKey: .totalDuration) {
      totalDuration = d
    } else if let i = try? c.decode(Int.self, forKey: .totalDuration) {
      totalDuration = Double(i)
    } else {
      totalDuration = 0
    }
    if let s = try? c.decode(Int64.self, forKey: .totalSize) {
      totalSize = s
    } else if let i = try? c.decode(Int.self, forKey: .totalSize) {
      totalSize = Int64(i)
    } else {
      totalSize = 0
    }
    numAudioTrack = try c.decodeIfPresent(Int.self, forKey: .numAudioTrack) ?? 0
  }
}

struct ABSServerSettings: Codable, Equatable {
  var scannerFindCovers: Bool?
  var scannerParseSubtitle: Bool?
  var scannerPreferMatchedMetadata: Bool?
  var scannerDisableWatcher: Bool?
  var storeCoverWithItem: Bool?
  var storeMetadataWithItem: Bool?
  var chromecastEnabled: Bool?
  var sortingIgnorePrefix: Bool?
  var logLevel: Int?
  var language: String?
  var version: String?

  enum CodingKeys: String, CodingKey {
    case scannerFindCovers, scannerParseSubtitle, scannerPreferMatchedMetadata
    case scannerDisableWatcher, storeCoverWithItem, storeMetadataWithItem
    case chromecastEnabled, sortingIgnorePrefix, logLevel, language, version
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(scannerFindCovers, forKey: .scannerFindCovers)
    try c.encodeIfPresent(scannerParseSubtitle, forKey: .scannerParseSubtitle)
    try c.encodeIfPresent(scannerPreferMatchedMetadata, forKey: .scannerPreferMatchedMetadata)
    try c.encodeIfPresent(scannerDisableWatcher, forKey: .scannerDisableWatcher)
    try c.encodeIfPresent(storeCoverWithItem, forKey: .storeCoverWithItem)
    try c.encodeIfPresent(storeMetadataWithItem, forKey: .storeMetadataWithItem)
    try c.encodeIfPresent(chromecastEnabled, forKey: .chromecastEnabled)
    try c.encodeIfPresent(sortingIgnorePrefix, forKey: .sortingIgnorePrefix)
    try c.encodeIfPresent(logLevel, forKey: .logLevel)
    try c.encodeIfPresent(language, forKey: .language)
    try c.encodeIfPresent(version, forKey: .version)
  }
}

struct ABSServerSettingsPatchResponse: Decodable {
  let success: Bool?
  let serverSettings: ABSServerSettings?
}

struct ABSSessionSyncBody: Encodable {
  let timeListened: Int
  let currentTime: Double
}

struct ABSPodcastMediaAutoDownloadPatch: Encodable {
  let autoDownloadEpisodes: Bool
  let autoDownloadSchedule: String
  let maxEpisodesToKeep: Int
  let maxNewEpisodesToDownload: Int
}

struct ABSProgressPatch: Encodable {
  var currentTime: Double?
  var duration: Double?
  var progress: Double?
  var isFinished: Bool?

  enum CodingKeys: String, CodingKey {
    case currentTime, duration, progress, isFinished
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(currentTime, forKey: .currentTime)
    try c.encodeIfPresent(duration, forKey: .duration)
    try c.encodeIfPresent(progress, forKey: .progress)
    try c.encodeIfPresent(isFinished, forKey: .isFinished)
  }
}

// MARK: - Listening stats (`GET /api/me/listening-stats`)

/// String-Keys für das `items`-Objekt (Library-Item-ID → Aggregat).
private struct ABSListeningStatsItemsCodingKey: CodingKey, Hashable {
  var stringValue: String
  var intValue: Int? { nil }
  init?(intValue: Int) { nil }
  init(stringValue: String) { self.stringValue = stringValue }
}

/// Antwortgemäß [API: Get Your Listening Stats](https://api.audiobookshelf.org).
/// Tolerant gegen Float-Zahlen, fehlende Teilfelder und kaputte einzelne `items`-Einträge.
struct ABSListeningStatsResponse: Decodable {
  let totalTime: Int
  let today: Int
  let days: [String: Int]
  let dayOfWeek: [String: Int]
  let items: [String: ABSListeningStatsItemAggregate]
  let recentSessions: [ABSListeningStatsRecentSession]

  enum CodingKeys: String, CodingKey {
    case totalTime, today, days, dayOfWeek, items, recentSessions
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    totalTime = ABSListeningStatsDecode.flexibleInt(c, forKey: .totalTime)
    today = ABSListeningStatsDecode.flexibleInt(c, forKey: .today)
    days = Self.decodeStringIntDictionary(c, forKey: .days)
    dayOfWeek = Self.decodeStringIntDictionary(c, forKey: .dayOfWeek)
    items = Self.decodeItemsSkippingBroken(c)
    recentSessions = Self.decodeRecentSessionsLenient(c)
  }

  /// Tag / Wochentag → Sekunden (Server liefert manchmal `Double`).
  private static func decodeStringIntDictionary(
    _ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
  ) -> [String: Int] {
    guard c.contains(key) else { return [:] }
    if let m = try? c.decode([String: Int].self, forKey: key) { return m }
    if let m = try? c.decode([String: Double].self, forKey: key) {
      return m.mapValues { Int($0.rounded()) }
    }
    return [:]
  }

  private static func decodeItemsSkippingBroken(_ c: KeyedDecodingContainer<CodingKeys>)
    -> [String: ABSListeningStatsItemAggregate]
  {
    guard c.contains(.items) else { return [:] }
    guard let nested = try? c.nestedContainer(keyedBy: ABSListeningStatsItemsCodingKey.self, forKey: .items) else {
      return [:]
    }
    var out: [String: ABSListeningStatsItemAggregate] = [:]
    out.reserveCapacity(nested.allKeys.count)
    for key in nested.allKeys {
      guard let item = try? nested.decode(ABSListeningStatsItemAggregate.self, forKey: key) else { continue }
      let kid = key.stringValue
      if item.id.isEmpty {
        out[kid] = item.withLibraryItemIdFallback(kid)
      } else {
        out[kid] = item
      }
    }
    return out
  }

  private static func decodeRecentSessionsLenient(_ c: KeyedDecodingContainer<CodingKeys>)
    -> [ABSListeningStatsRecentSession]
  {
    guard c.contains(.recentSessions) else { return [] }
    if let sessions = try? c.decode([ABSListeningStatsRecentSession].self, forKey: .recentSessions) {
      return sessions
    }
    return []
  }
}

struct ABSListeningStatsItemAggregate: Decodable, Identifiable {
  let id: String
  let timeListening: Int
  let mediaMetadata: ABSListeningStatsMetadata?

  enum CodingKeys: String, CodingKey {
    case id, timeListening, mediaMetadata
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
    timeListening = ABSListeningStatsDecode.flexibleInt(c, forKey: .timeListening)
    mediaMetadata = try? c.decode(ABSListeningStatsMetadata.self, forKey: .mediaMetadata)
  }

  func withLibraryItemIdFallback(_ libraryItemId: String) -> ABSListeningStatsItemAggregate {
    ABSListeningStatsItemAggregate(
      id: id.isEmpty ? libraryItemId : id,
      timeListening: timeListening,
      mediaMetadata: mediaMetadata
    )
  }

  init(id: String, timeListening: Int, mediaMetadata: ABSListeningStatsMetadata?) {
    self.id = id
    self.timeListening = timeListening
    self.mediaMetadata = mediaMetadata
  }
}

private enum ABSListeningStatsDecode {
  static func flexibleInt<K: CodingKey>(_ c: KeyedDecodingContainer<K>, forKey key: K) -> Int {
    if let v = try? c.decode(Int.self, forKey: key) { return v }
    if let v = try? c.decode(Double.self, forKey: key) { return Int(v.rounded()) }
    if let v = try? c.decode(Int64.self, forKey: key) { return Int(v) }
    return 0
  }

  static func flexibleDouble<K: CodingKey>(_ c: KeyedDecodingContainer<K>, forKey key: K) -> Double {
    if let v = try? c.decode(Double.self, forKey: key) { return v }
    if let v = try? c.decode(Int.self, forKey: key) { return Double(v) }
    if let v = try? c.decode(Int64.self, forKey: key) { return Double(v) }
    return 0
  }
}

struct ABSListeningStatsMetadata: Decodable {
  let title: String?
  let author: String?
  let authorName: String?
  let feedUrl: String?
  let type: String?

  var displayTitle: String {
    let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? "—" : t
  }

  var displaySubtitle: String {
    let a = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !a.isEmpty { return a }
    let an = authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return an.isEmpty ? "—" : an
  }

  /// Heuristik Buch vs. Podcast-Show (Server liefert unterschiedliche Metadaten).
  var isPodcastLike: Bool {
    if feedUrl != nil { return true }
    let t = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if t == "episodic" || t == "serial" { return true }
    return false
  }
}

struct ABSListeningStatsRecentSession: Decodable, Identifiable {
  let id: String
  let libraryItemId: String
  let episodeId: String?
  let displayTitle: String?
  let displayAuthor: String?
  let mediaType: String?
  let timeListening: Int
  let startTime: Double
  let startedAt: Int64

  enum CodingKeys: String, CodingKey {
    case id, libraryItemId, episodeId, displayTitle, displayAuthor, mediaType
    case timeListening, startTime, startedAt
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
    if let lid = try c.decodeIfPresent(String.self, forKey: .libraryItemId), !lid.isEmpty {
      libraryItemId = lid
    } else {
      libraryItemId = ""
    }
    episodeId = try c.decodeIfPresent(String.self, forKey: .episodeId)
    displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
    displayAuthor = try c.decodeIfPresent(String.self, forKey: .displayAuthor)
    mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
    timeListening = ABSListeningStatsDecode.flexibleInt(c, forKey: .timeListening)
    startTime = ABSListeningStatsDecode.flexibleDouble(c, forKey: .startTime)
    if let s = try c.decodeIfPresent(Int64.self, forKey: .startedAt) {
      startedAt = s
    } else if let d = try c.decodeIfPresent(Double.self, forKey: .startedAt) {
      startedAt = Int64(d.rounded())
    } else {
      startedAt = 0
    }
  }
}

extension ABSListeningStatsResponse {
  /// Dekodierung: zuerst Standard-JSON (camelCase wie in der API-Doku), sonst mit `convertFromSnakeCase` (Proxys / ältere Server).
  static func decodeAPIPayload(_ data: Data) throws -> ABSListeningStatsResponse {
    if let s = try? ABSJSON.decoder().decode(ABSListeningStatsResponse.self, from: data) {
      return s
    }
    return try ABSJSON.decoderListeningStats().decode(ABSListeningStatsResponse.self, from: data)
  }
}

extension ABSListeningStatsResponse {
  /// Höchste Hördauer zuerst (für „Meist gehört“).
  var itemsSortedByListeningTime: [(id: String, item: ABSListeningStatsItemAggregate)] {
    items.map { (id: $0.key, item: $0.value) }
      .filter { !$0.item.id.isEmpty }
      .sorted { $0.item.timeListening > $1.item.timeListening }
  }

  func secondsInLastDays(_ dayCount: Int, calendar: Calendar = .current, now: Date = Date()) -> Int {
    let start = calendar.startOfDay(for: now)
    var sum = 0
    for i in 0 ..< max(0, dayCount) {
      guard let d = calendar.date(byAdding: .day, value: -i, to: start) else { continue }
      let k = Self.dayKey(d, calendar: calendar)
      sum += days[k, default: 0]
    }
    return sum
  }

  /// Letzte 7 Tage (ältester Tag zuerst) für Diagramme — Schlüssel `id` = `yyyy-MM-dd`.
  func lastSevenDayBars(calendar: Calendar = .current, now: Date = Date(), locale: Locale = .current)
    -> [(id: String, label: String, seconds: Int)]
  {
    let start = calendar.startOfDay(for: now)
    let df = DateFormatter()
    df.locale = locale
    df.setLocalizedDateFormatFromTemplate("EEE")
    var rows: [(String, String, Int)] = []
    for offset in 0 ..< 7 {
      guard let d = calendar.date(byAdding: .day, value: offset - 6, to: start) else { continue }
      let k = Self.dayKey(d, calendar: calendar)
      rows.append((k, df.string(from: d), days[k, default: 0]))
    }
    return rows
  }

  /// Sekunden im aktuellen Kalendermonat (lokale Zeitzone).
  func secondsThisCalendarMonth(calendar: Calendar = .current, now: Date = Date()) -> Int {
    let comps = calendar.dateComponents([.year, .month], from: now)
    guard let y = comps.year, let m = comps.month else { return 0 }
    var sum = 0
    for (key, sec) in days where sec > 0 {
      guard let d = Self.parseDayKey(key, calendar: calendar) else { continue }
      let c2 = calendar.dateComponents([.year, .month], from: d)
      if c2.year == y, c2.month == m { sum += sec }
    }
    return sum
  }

  /// Summe der `days`-Einträge im laufenden Kalenderjahr (lokal).
  func secondsThisCalendarYear(calendar: Calendar = .current, now: Date = Date()) -> Int {
    let y = calendar.component(.year, from: now)
    var sum = 0
    for (key, sec) in days where sec > 0 {
      guard let d = Self.parseDayKey(key, calendar: calendar) else { continue }
      if calendar.component(.year, from: d) == y { sum += sec }
    }
    return sum
  }

  var daysActive: Int {
    days.values.filter { $0 > 0 }.count
  }

  /// Tage mit Hörzeit im rollierenden Jahr (Heatmap-Zähler, unabhängig von sichtbaren Wochen).
  var daysListenedInLastYear: Int {
    yearListeningHeatmap(weeksToShow: 52).daysListenedInLastYear
  }

  /// Tagesdurchschnitt über Tage mit Aktivität (wie typische Statistik-Übersichten).
  var dailyAverageSeconds: Int {
    let d = max(daysActive, 1)
    return totalTime / d
  }

  var totalTimeAsCalendarDaysApprox: Double {
    Double(totalTime) / 86_400.0
  }

  func currentListeningStreakDays(calendar: Calendar = .current, now: Date = Date()) -> Int {
    let active = activeDayStarts(calendar: calendar)
    guard !active.isEmpty else { return 0 }
    let today = calendar.startOfDay(for: now)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    var cursor: Date
    if active.contains(today) {
      cursor = today
    } else if active.contains(yesterday) {
      cursor = yesterday
    } else {
      return 0
    }
    var streak = 0
    while active.contains(cursor) {
      streak += 1
      guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
      cursor = prev
    }
    return streak
  }

  func bestListeningStreakDays(calendar: Calendar = .current) -> Int {
    let daysSorted = activeDayStarts(calendar: calendar).sorted()
    guard daysSorted.count >= 2 else { return daysSorted.isEmpty ? 0 : 1 }
    var best = 1
    var run = 1
    for i in 1 ..< daysSorted.count {
      let prev = daysSorted[i - 1]
      let cur = daysSorted[i]
      if let next = calendar.date(byAdding: .day, value: 1, to: prev), calendar.isDate(next, inSameDayAs: cur) {
        run += 1
        best = max(best, run)
      } else {
        run = 1
      }
    }
    return best
  }

  var bookLikeItemCount: Int {
    items.values.filter { !($0.mediaMetadata?.isPodcastLike ?? false) }.count
  }

  var podcastLikeItemCount: Int {
    items.values.filter { $0.mediaMetadata?.isPodcastLike ?? false }.count
  }

  private func activeDayStarts(calendar: Calendar) -> Set<Date> {
    var set = Set<Date>()
    for (key, sec) in days where sec > 0 {
      if let d = Self.parseDayKey(key, calendar: calendar) {
        set.insert(calendar.startOfDay(for: d))
      }
    }
    return set
  }

  private static func dayKey(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  /// Erste Spalte jedes Kalendermonats; `labelEveryNthMonth` 1 = alle, 2 = jeden zweiten.
  private static func monthLabelsForHeatmapColumns(
    columnCount: Int,
    cells: [ABSListeningYearHeatmap.Cell],
    calendar: Calendar,
    locale: Locale,
    labelEveryNthMonth: Int
  ) -> [ABSListeningYearHeatmap.MonthLabel] {
    let stride = max(1, labelEveryNthMonth)
    let monthFormatter = DateFormatter()
    monthFormatter.locale = locale
    monthFormatter.setLocalizedDateFormatFromTemplate("MMM")

    var labels: [ABSListeningYearHeatmap.MonthLabel] = []
    var lastMonthKey: String?
    var monthIndex = 0
    for col in 0 ..< columnCount {
      let anchor =
        cells.first { $0.column == col && $0.row == 0 }
        ?? cells.filter { $0.column == col }.min(by: { $0.row < $1.row })
      guard let anchor, let date = parseDayKey(anchor.id, calendar: calendar) else { continue }
      let y = calendar.component(.year, from: date)
      let m = calendar.component(.month, from: date)
      let key = "\(y)-\(m)"
      guard key != lastMonthKey else { continue }
      lastMonthKey = key
      if monthIndex % stride == 0 {
        labels.append(
          ABSListeningYearHeatmap.MonthLabel(
            id: "\(anchor.id)-month",
            column: col,
            label: monthFormatter.string(from: date)
          ))
      }
      monthIndex += 1
    }
    return labels
  }

  private static func parseDayKey(_ key: String, calendar: Calendar) -> Date? {
    let p = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = p.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var comp = DateComponents()
    comp.year = parts[0]
    comp.month = parts[1]
    comp.day = parts[2]
    return calendar.date(from: comp)
  }

  /// GitHub-ähnliche Heatmap (vgl. Audiobookshelf `Heatmap.vue` / Server-UI Stats).
  func yearListeningHeatmap(
    weeksToShow: Int = 52,
    calendar: Calendar = .current,
    now: Date = Date(),
    locale: Locale = .current
  ) -> ABSListeningYearHeatmap {
    var cal = calendar
    cal.locale = locale
    let todayStart = cal.startOfDay(for: now)
    let rawWeekday = cal.component(.weekday, from: now) // 1=Sun … 7=Sat
    let dayOfWeekToday = (rawWeekday - cal.firstWeekday + 7) % 7
    let cappedWeeks = min(52, max(1, weeksToShow))
    let daysToShow = cappedWeeks * 7 + dayOfWeekToday
    let numDaysInLastYear = 52 * 7 + dayOfWeekToday

    guard let firstDay = cal.date(byAdding: .day, value: -numDaysInLastYear, to: todayStart) else {
      return .empty
    }

    let monthFormatter = DateFormatter()
    monthFormatter.locale = locale
    monthFormatter.setLocalizedDateFormatFromTemplate("MMM")
    let prettyFormatter = DateFormatter()
    prettyFormatter.locale = locale
    prettyFormatter.dateStyle = .medium
    prettyFormatter.timeStyle = .none

    var daysListenedInLastYear = 0
    var staged: [(col: Int, row: Int, key: String, date: Date, seconds: Int)] = []
    var maxValue = 0
    var minValue = 0

    for i in 0 ... numDaysInLastYear {
      guard let date = cal.date(byAdding: .day, value: i, to: firstDay) else { continue }
      let key = Self.dayKey(date, calendar: cal)
      let seconds = days[key, default: 0]
      if seconds > 0 {
        daysListenedInLastYear += 1
      }

      let visibleDayIndex = i - (numDaysInLastYear - daysToShow)
      if visibleDayIndex < 0 { continue }

      let col = visibleDayIndex / 7
      let row = visibleDayIndex % 7
      staged.append((col, row, key, date, seconds))

      if seconds > 0 {
        maxValue = max(maxValue, seconds)
        minValue = minValue == 0 ? seconds : min(minValue, seconds)
      }
    }

    let range = Double(max(maxValue - minValue, 0)) + 0.01
    var cells: [ABSListeningYearHeatmap.Cell] = []
    cells.reserveCapacity(staged.count)
    for item in staged {
      let level: Int
      if item.seconds <= 0 {
        level = 0
      } else if maxValue == minValue {
        level = 4
      } else {
        let pct = Double(item.seconds - minValue) / range
        level = min(4, Int(pct * 4.0) + 1)
      }
      let pretty = prettyFormatter.string(from: item.date)
      let a11y =
        item.seconds > 0
        ? "\(pretty), \(formatPlaybackDurationShortHuman(Double(item.seconds)))"
        : "\(pretty), no listening"
      cells.append(
        ABSListeningYearHeatmap.Cell(
          id: item.key,
          column: item.col,
          row: item.row,
          seconds: item.seconds,
          colorLevel: level,
          accessibilityLabel: a11y
        ))
    }

    let columnCount = (cells.map(\.column).max() ?? 0) + 1
    let monthLabels = Self.monthLabelsForHeatmapColumns(
      columnCount: columnCount,
      cells: cells,
      calendar: cal,
      locale: locale,
      labelEveryNthMonth: columnCount > 44 ? 2 : 1
    )
    return ABSListeningYearHeatmap(
      daysListenedInLastYear: daysListenedInLastYear,
      cells: cells,
      monthLabels: monthLabels,
      columnCount: columnCount
    )
  }
}

/// Jahres-Heatmap aus `days` (`yyyy-MM-dd` → Sekunden).
struct ABSListeningYearHeatmap: Equatable {
  struct Cell: Identifiable, Equatable {
    let id: String
    let column: Int
    let row: Int
    let seconds: Int
    let colorLevel: Int
    let accessibilityLabel: String
  }

  struct MonthLabel: Identifiable, Equatable {
    let id: String
    let column: Int
    let label: String
  }

  let daysListenedInLastYear: Int
  let cells: [Cell]
  let monthLabels: [MonthLabel]
  let columnCount: Int

  static let empty = ABSListeningYearHeatmap(
    daysListenedInLastYear: 0,
    cells: [],
    monthLabels: [],
    columnCount: 0
  )

  func cell(column: Int, row: Int) -> Cell? {
    cells.first { $0.column == column && $0.row == row }
  }
}

extension String {
  /// Ein POSIX-Segment für Server-Bibliothekspfade (Unterordner unter dem Bibliotheksordner).
  func absSanitizedLibraryPathSegment() -> String {
    let t = trimmingCharacters(in: .whitespacesAndNewlines)
    let base = t.isEmpty ? "Podcast" : t
    let invalid = CharacterSet(charactersIn: "/\\:?*\"<>|\u{0000}")
    var s = base.components(separatedBy: invalid).joined(separator: "_")
    s = s.replacingOccurrences(of: "..", with: "_")
    if s.isEmpty { return "Podcast" }
    return String(s.prefix(120))
  }
}
