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
}

struct ABSUserMediaProgress: Codable {
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
    try c.encode(libraryItemId, forKey: .libraryItemId)
    try c.encodeIfPresent(episodeId, forKey: .episodeId)
    try c.encode(duration, forKey: .duration)
    try c.encode(progress, forKey: .progress)
    try c.encode(currentTime, forKey: .currentTime)
    try c.encode(isFinished, forKey: .isFinished)
    try c.encodeIfPresent(lastUpdate, forKey: .lastUpdate)
  }

  /// Schlüssel für `AppModel.progressByItemId` (Episoden: `libraryItemId-episodeId`).
  var progressLookupKey: String {
    let e = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !e.isEmpty { return "\(libraryItemId)-\(e)" }
    return libraryItemId
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

  enum CodingKeys: String, CodingKey {
    case metadata, duration, size, numTracks, chapters, tracks, audioFiles
    case podcastEpisodes = "episodes"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    metadata = try c.decode(ABSBookMediaMetadata.self, forKey: .metadata)
    duration = try c.decodeIfPresent(Double.self, forKey: .duration)
    size = try c.decodeIfPresent(Int64.self, forKey: .size)
    numTracks = try c.decodeIfPresent(Int.self, forKey: .numTracks)
    chapters = try c.decodeIfPresent([ABSChapter].self, forKey: .chapters)
    podcastEpisodes = try c.decodeIfPresent([ABSRecentPodcastEpisodeDTO].self, forKey: .podcastEpisodes)
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
  let media: ABSBookMedia
  let addedAt: Date?
  let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case libraryId = "libraryId"
    case media
    case addedAt
    case updatedAt
  }

  var displayTitle: String { media.metadata.title }
  var displayAuthors: String {
    let m = media.metadata
    if let n = m.authorName, !n.isEmpty { return n }
    if let a = m.authors, !a.isEmpty { return a.map(\.name).joined(separator: ", ") }
    return "—"
  }
  var totalDuration: Double { media.duration ?? 0 }

  /// Enough metadata to play or show in lists.
  var isPlayableAudiobook: Bool {
    (media.numTracks ?? 0) > 0 || (media.duration ?? 0) > 0
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
    podcastEpisodes: [ABSRecentPodcastEpisodeDTO]? = nil
  ) {
    self.metadata = metadata
    self.duration = duration
    self.size = size
    self.numTracks = numTracks
    self.chapters = chapters
    self.tracks = tracks
    self.podcastEpisodes = podcastEpisodes
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
      updatedAt: nil
    )
  }
}

// MARK: - Start / Personalized (Home)

struct ABSAuthorShelfEntity: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let numBooks: Int?
}

struct ABSStartShelfSection: Identifiable {
  let id: String
  let category: String
  let displayTitle: String
  let books: [ABSBook]
  let podcastEpisodes: [ABSPodcastEpisodeListItem]
  let authors: [ABSAuthorShelfEntity]

  var hasBooks: Bool { !books.isEmpty }
  var hasPodcastEpisodes: Bool { !podcastEpisodes.isEmpty }
  var hasAuthors: Bool { !authors.isEmpty }
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
        return false
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
      updatedAt: libraryItem.updatedAt
    )
  }
}

struct ABSSessionSyncBody: Encodable {
  let timeListened: Int
  let currentTime: Double
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
