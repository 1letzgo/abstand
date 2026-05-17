import Foundation

// MARK: - Auth & User

struct ABSLoginRequest: Encodable {
  let username: String
  let password: String
}

struct ABSLoginResponse: Decodable {
  let user: ABSUser
  let userDefaultLibraryId: String?
}

struct ABSUser: Decodable {
  let id: String
  let username: String
  let token: String
  let mediaProgress: [ABSUserMediaProgress]?
  let bookmarks: [ABSAudioBookmark]?

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    username = try c.decode(String.self, forKey: .username)
    token = try c.decode(String.self, forKey: .token)
    mediaProgress = try c.decodeIfPresent([ABSUserMediaProgress].self, forKey: .mediaProgress)
    bookmarks = try c.decodeIfPresent([ABSAudioBookmark].self, forKey: .bookmarks)
  }

  enum CodingKeys: String, CodingKey {
    case id, username, token, mediaProgress, bookmarks
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
    feedUrl = try c.decodeIfPresent(String.self, forKey: .feedUrl)

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

struct ABSChapter: Decodable {
  let id: Int
  let start: Double
  let end: Double
  let title: String
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

  enum CodingKeys: String, CodingKey {
    case metadata, duration, size, numTracks, chapters, tracks, audioFiles
    case podcastEpisodes = "episodes"
    case autoDownloadEpisodes, autoDownloadSchedule
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
  let addedAt: Date?
  let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case libraryId
    case mediaId
    case media
    case addedAt
    case updatedAt
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    libraryId = try c.decodeIfPresent(String.self, forKey: .libraryId)
    mediaId = try c.decodeIfPresent(String.self, forKey: .mediaId)
    media = try c.decode(ABSBookMedia.self, forKey: .media)
    addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt)
    updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
  }

  init(
    id: String,
    libraryId: String?,
    media: ABSBookMedia,
    addedAt: Date?,
    updatedAt: Date?,
    mediaId: String? = nil
  ) {
    self.id = id
    self.libraryId = libraryId
    self.mediaId = mediaId
    self.media = media
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
      if let n = m.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
        return n
      }
      return nil
    }()
    guard let raw else { return "—" }
    return Self.primaryAuthorForCardCompactDisplay(raw)
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
  /// Für Offline-Stubs aus `download.json` (kein vollständiges Server-JSON).
  init(offlineTitle: String, authorLine: String) {
    title = offlineTitle.isEmpty ? "Audiobook" : offlineTitle
    titleIgnorePrefix = nil
    subtitle = nil
    authors = nil
    narrators = nil
    series = nil
    publishedYear = nil
    publishedDate = nil
    authorName = authorLine.isEmpty ? nil : authorLine
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
    autoDownloadSchedule: String? = nil
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
    let media = ABSBookMedia(
      metadata: meta,
      duration: dur,
      numTracks: n > 0 ? n : nil,
      tracks: n > 0 ? trackModels : nil
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
    var rows: [ABSStartShelfMergedRow] = books.map { .book($0) }
    rows.append(contentsOf: podcastEpisodes.map { .podcastEpisode($0) })
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
    "continueSeries": "Continue series",
    "newestItems": "Recently added",
    "newestSeries": "Recent series",
    "recommended": "Recommended",
    "recentlyFinished": "Listen again",
    "newestAuthors": "New authors",
    "itemsInProgressFallback": "Continue listening (fallback)",
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

struct ABSSessionSyncBody: Encodable {
  let timeListened: Int
  let currentTime: Double
}

struct ABSPodcastMediaAutoDownloadPatch: Encodable {
  let autoDownloadEpisodes: Bool
  let autoDownloadSchedule: String
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
