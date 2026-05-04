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

  var isBookLibrary: Bool { (mediaType ?? "book") == "book" }
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

  enum CodingKeys: String, CodingKey {
    case title, titleIgnorePrefix, subtitle, authors, narrators, series
    case publishedYear, publishedDate, authorName, narratorName, seriesName
    case publisher, description, descriptionPlain, genres, language
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
    authorName = try c.decodeIfPresent(String.self, forKey: .authorName)
    narratorName = try c.decodeIfPresent(String.self, forKey: .narratorName)
    seriesName = try c.decodeIfPresent(String.self, forKey: .seriesName)
    publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
    description = try c.decodeIfPresent(String.self, forKey: .description)
    descriptionPlain = try c.decodeIfPresent(String.self, forKey: .descriptionPlain)
    genres = try c.decodeIfPresent([String].self, forKey: .genres)
    language = try c.decodeIfPresent(String.self, forKey: .language)

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

  enum CodingKeys: String, CodingKey {
    case metadata, duration, size, numTracks, chapters, tracks, audioFiles
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    metadata = try c.decode(ABSBookMediaMetadata.self, forKey: .metadata)
    duration = try c.decodeIfPresent(Double.self, forKey: .duration)
    size = try c.decodeIfPresent(Int64.self, forKey: .size)
    numTracks = try c.decodeIfPresent(Int.self, forKey: .numTracks)
    chapters = try c.decodeIfPresent([ABSChapter].self, forKey: .chapters)
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
    title = offlineTitle.isEmpty ? "Hörbuch" : offlineTitle
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
  }
}

extension ABSBookMedia {
  init(
    metadata: ABSBookMediaMetadata,
    duration: Double?,
    size: Int64? = nil,
    numTracks: Int?,
    chapters: [ABSChapter]? = nil,
    tracks: [ABSAudioTrack]?
  ) {
    self.metadata = metadata
    self.duration = duration
    self.size = size
    self.numTracks = numTracks
    self.chapters = chapters
    self.tracks = tracks
  }
}

extension ABSBook {
  /// Hörbuch nur aus lokalem `ABSDownloadManifest` (Offline-Liste / Wiedergabe ohne Item-API).
  static func fromDownloadManifest(_ m: ABSDownloadManifest) -> ABSBook {
    let t = m.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let title = t.isEmpty ? "Hörbuch" : t
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
  let authors: [ABSAuthorShelfEntity]

  var hasBooks: Bool { !books.isEmpty }
  var hasAuthors: Bool { !authors.isEmpty }
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
  let book: [ABSSearchBookRow]
  let authors: [ABSSearchAuthorRow]
  let narrators: [ABSSearchNarratorRow]
  let series: [ABSSearchSeriesRow]
  let tags: [ABSSearchNamedCount]
  let genres: [ABSSearchNamedCount]

  enum CodingKeys: String, CodingKey {
    case book, authors, narrators, series, tags, genres
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    book = (try? c.decode([ABSSearchBookRow].self, forKey: .book)) ?? []
    authors = (try? c.decode([ABSSearchAuthorRow].self, forKey: .authors)) ?? []
    narrators = (try? c.decode([ABSSearchNarratorRow].self, forKey: .narrators)) ?? []
    series = (try? c.decode([ABSSearchSeriesRow].self, forKey: .series)) ?? []
    tags = (try? c.decode([ABSSearchNamedCount].self, forKey: .tags)) ?? []
    genres = (try? c.decode([ABSSearchNamedCount].self, forKey: .genres)) ?? []
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

  enum CodingKeys: String, CodingKey {
    case id, userId, libraryItemId, episodeId, mediaType
    case currentTime, duration, audioTracks, chapters, libraryItem
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
    if mediaType == "podcast" {
      throw DecodingError.dataCorruptedError(
        forKey: .libraryItem,
        in: c,
        debugDescription: "Podcasts are not supported in this app yet."
      )
    }
    libraryItem = try c.decode(ABSBook.self, forKey: .libraryItem)
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
