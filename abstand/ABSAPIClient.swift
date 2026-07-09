import Foundation

enum ABSAPIError: LocalizedError {
  case invalidURL
  case httpStatus(Int, String?)
  case decoding(Error)
  case emptyBody

  var errorDescription: String? {
    switch self {
    case .invalidURL: return "Invalid server URL"
    case .httpStatus(let code, let body):
      if let body, !body.isEmpty { return "Server error \(code): \(body)" }
      return "Server error \(code)"
    case .decoding(let e): return "Could not read response: \(e.localizedDescription)"
    case .emptyBody: return "Empty server response"
    }
  }
}

actor ABSAPIClient {
  private let baseURL: URL
  private var token: String
  private let decoder = ABSJSON.decoder()
  private let encoder = ABSJSON.encoder()
  private let urlSession: URLSession
  /// Separate Session für Datei-Downloads — eigener Connection-Pool, damit langlaufende Downloads
  /// API-Calls (z. B. `startPlaySession` für Streaming) nicht blockieren (vgl. `waitsForConnectivity`).
  private let downloadURLSession: URLSession

  init(baseURL: URL, token: String) {
    self.baseURL = baseURL
    self.token = token
    let cfg = URLSessionConfiguration.default
    // Bootstrap-Polling durch URLSession übernehmen — Requests warten im Queue, bis ein Interface up ist
    // (vgl. ios-networking-Skill: `waitsForConnectivity = true`). Gewinnt Dead-Time beim Kaltstart.
    cfg.waitsForConnectivity = true
    // Deutlich kürzer als 120 s, damit Offline-Fallback bei Bootstrap schneller greift; große Downloads
    // setzen eigene `URLRequest.timeoutInterval`-Overrides.
    cfg.timeoutIntervalForRequest = 12
    cfg.timeoutIntervalForResource = 3_600
    self.urlSession = URLSession(configuration: cfg)

    // Download-Session: eigenes Limit, damit Streaming-API nicht hinter Downloads in die Warteschlange gerät.
    let dlCfg = URLSessionConfiguration.default
    dlCfg.waitsForConnectivity = true
    dlCfg.timeoutIntervalForRequest = 60
    dlCfg.timeoutIntervalForResource = 3_600
    dlCfg.httpMaximumConnectionsPerHost = 4
    self.downloadURLSession = URLSession(configuration: dlCfg)
  }


  func setToken(_ newToken: String) {
    token = newToken
  }

  func currentToken() -> String {
    token
  }

  func publicStreamURL(sessionId: String, trackIndex: Int) throws -> URL {
    try buildURL(path: "public/session/\(sessionId)/track/\(trackIndex)", query: [:])
  }

  /// Direkter Dateidownload (wie AudioBooth/ABS-Web); zuverlässiger als Session-Stream für lokale Kopien.
  func itemFileDownloadURL(itemId: String, ino: String) throws -> URL {
    try buildURL(path: "api/items/\(itemId)/file/\(ino)/download", query: [:])
  }

  /// E-Book- oder PDF-Datei eines Hörbuchs herunterladen.
  func downloadEbookFile(
    itemId: String,
    ino: String,
    format: ABSEbookFormat,
    to suggestedDestination: URL
  ) async throws -> URL {
    let streamURL = try itemFileDownloadURL(itemId: itemId, ino: ino)
    let dir = suggestedDestination.deletingLastPathComponent()
    let stem = suggestedDestination.deletingPathExtension().lastPathComponent
    let dest = dir.appendingPathComponent("\(stem).\(format.fileExtension)")
    var lastError: Error?
    for attempt in 0..<3 {
      do {
        var req = URLRequest(url: streamURL, timeoutInterval: 600)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (temp, resp) = try await downloadURLSession.download(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
          try? FileManager.default.removeItem(at: temp)
          throw ABSAPIError.httpStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, nil)
        }
        if FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
      } catch {
        lastError = error
        if error is CancellationError { throw error }
        if attempt < 2 {
          try await Task.sleep(nanoseconds: UInt64(0.6 * Double(attempt + 1) * 1_000_000_000))
        }
      }
    }
    throw lastError ?? ABSAPIError.emptyBody
  }

  // MARK: - Static helpers

  static func normalizeServerURL(_ raw: String) -> URL? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return nil }
    if !s.lowercased().hasPrefix("http://"), !s.lowercased().hasPrefix("https://") {
      s = "https://" + s
    }
    while s.hasSuffix("/") { s.removeLast() }
    return URL(string: s)
  }

  /// Kurze `waitsForConnectivity`-Toleranz wie beim Bootstrap-Client, aber mit begrenztem
  /// Resource-Timeout — Login soll bei echtem Offline-Zustand zeitnah fehlschlagen, nicht
  /// per `URLSession.shared`-Default sofort ohne jede Toleranz für kurze Netz-Hänger.
  private static let loginSession: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.waitsForConnectivity = true
    cfg.timeoutIntervalForRequest = 12
    cfg.timeoutIntervalForResource = 20
    return URLSession(configuration: cfg)
  }()

  static func login(server: URL, username: String, password: String) async throws -> ABSLoginResponse {
    let url = server.appendingPathComponent("login")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(ABSLoginRequest(username: username, password: password))
    let (data, resp) = try await loginSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      return try ABSJSON.decoder().decode(ABSLoginResponse.self, from: data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  // MARK: - Instance requests

  private func buildURL(path: String, query: [String: String]) throws -> URL {
    let baseStr = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let pathClean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard var comp = URLComponents(string: baseStr + "/" + pathClean) else { throw ABSAPIError.invalidURL }
    if !query.isEmpty {
      comp.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    guard let url = comp.url else { throw ABSAPIError.invalidURL }
    return url
  }

  private func authorizedRequest(
    path: String,
    method: String = "GET",
    query: [String: String] = [:],
    body: Data? = nil,
    timeout: TimeInterval = 30
  ) throws -> URLRequest {
    let url = try buildURL(path: path, query: query)
    var req = URLRequest(url: url, timeoutInterval: timeout)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.httpBody = body
    return req
  }

  private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
    let (data, resp) = try await urlSession.data(for: request)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Hör-Sitzungen: striktes Decoding, bei Fehler Zeilenweise per `decodeLenient` (kaputte Einträge fallen weg statt die ganze Seite).
  private func sendListeningSessionsPayload(_ request: URLRequest) async throws -> ABSListeningSessionsPayload {
    let (data, resp) = try await urlSession.data(for: request)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      return try ABSListeningSessionsPayload.decodeLenient(data: data, jsonDecoder: decoder)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  private func sendData(_ request: URLRequest) async throws {
    let (data, resp) = try await urlSession.data(for: request)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    _ = data
  }

  func authorize() async throws -> ABSLoginResponse {
    let req = try authorizedRequest(path: "api/authorize", method: "POST")
    return try await send(req)
  }

  /// Eigenes Passwort ändern (`PATCH /api/me/password`).
  func changePassword(current: String, new: String) async throws {
    let body = try encoder.encode(ABSChangePasswordRequest(password: current, newPassword: new))
    let req = try authorizedRequest(path: "api/me/password", method: "PATCH", body: body)
    try await sendData(req)
  }

  // MARK: - Server admin (root)

  func serverUsers() async throws -> [ABSAdminUserSummary] {
    let req = try authorizedRequest(path: "api/users")
    let res: ABSUsersListResponse = try await send(req)
    return res.users
  }

  func serverOnlineUserIds() async throws -> Set<String> {
    let req = try authorizedRequest(path: "api/users/online")
    let res: ABSUsersOnlineResponse = try await send(req)
    return Set((res.usersOnline ?? []).map(\.id))
  }

  func serverUserDetailData(userId: String) async throws -> Data {
    let req = try authorizedRequest(path: "api/users/\(userId)")
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    return data
  }

  func serverUserListeningSessions(
    userId: String,
    itemsPerPage: Int = 50,
    page: Int = 0
  ) async throws -> ABSListeningSessionsPayload {
    let req = try authorizedRequest(
      path: "api/users/\(userId)/listening-sessions",
      query: [
        "itemsPerPage": "\(max(1, min(itemsPerPage, 100)))",
        "page": "\(max(0, page))",
      ]
    )
    return try await sendListeningSessionsPayload(req)
  }

  func serverLibraryStats(libraryId: String) async throws -> ABSLibraryStatsResponse {
    let req = try authorizedRequest(path: "api/libraries/\(libraryId)/stats")
    return try await send(req)
  }

  func scanServerLibrary(libraryId: String) async throws {
    let req = try authorizedRequest(path: "api/libraries/\(libraryId)/scan", method: "POST", timeout: 300)
    try await sendData(req)
  }

  func libraries() async throws -> [ABSLibrary] {
    let req = try authorizedRequest(path: "api/libraries")
    let res: ABSLibrariesResponse = try await send(req)
    return res.libraries
  }

  func libraryFilterData(libraryId: String) async throws -> ABSLibraryFilterData {
    let req = try authorizedRequest(path: "api/libraries/\(libraryId)/filterdata")
    return try await send(req)
  }

  func libraryItems(
    libraryId: String,
    page: Int = 0,
    limit: Int = 50,
    sort: String = "media.metadata.title",
    ascending: Bool = true,
    minified: Bool = true,
    filter: String? = nil
  ) async throws -> (ABSPage<ABSBook>, Data) {
    var q: [String: String] = [
      "minified": minified ? "1" : "0",
      "limit": "\(limit)",
      "page": "\(page)",
      "sort": sort,
    ]
    if !ascending { q["desc"] = "1" }
    if let filter, !filter.isEmpty {
      q["filter"] = filter
    }
    let req = try authorizedRequest(path: "api/libraries/\(libraryId)/items", query: q)
    var reqNoCache = req
    reqNoCache.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, resp) = try await urlSession.data(for: reqNoCache)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      let page = try decoder.decode(ABSPage<ABSBook>.self, from: data)
      return (page, data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Neueste unbearbeitete Podcast-Folgen (wie Web „Latest episodes“).
  func recentPodcastEpisodes(libraryId: String, page: Int = 0, limit: Int = 40) async throws
    -> (response: ABSRecentEpisodesResponse, raw: Data)
  {
    let req = try authorizedRequest(
      path: "api/libraries/\(libraryId)/recent-episodes",
      query: [
        "limit": "\(limit)",
        "page": "\(page)",
      ]
    )
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      let r = try decoder.decode(ABSRecentEpisodesResponse.self, from: data)
      return (r, data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  private struct ABSPodcastRssFeedRequestBody: Encodable {
    let rssFeed: String
  }

  /// RSS parsen ohne Library zu ändern (`POST /api/podcasts/feed`).
  func fetchPodcastRssFeed(rssFeedUrl: String) async throws -> Data {
    let body = try encoder.encode(ABSPodcastRssFeedRequestBody(rssFeed: rssFeedUrl))
    let req = try authorizedRequest(
      path: "api/podcasts/feed",
      method: "POST",
      body: body,
      timeout: 180
    )
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    return data
  }

  /// Ausgewählte Feed-Folgen auf den Server laden (`POST /api/podcasts/:id/download-episodes`, Body = JSON-Array von Folgenobjekten).
  func downloadPodcastEpisodesToLibrary(podcastLibraryItemId: String, episodesJsonArray: Data) async throws {
    let req = try authorizedRequest(
      path: "api/podcasts/\(podcastLibraryItemId)/download-episodes",
      method: "POST",
      body: episodesJsonArray,
      timeout: 300
    )
    try await sendData(req)
  }

  /// RSS prüfen und neue Folgen auf dem Server laden (`GET /api/podcasts/:id/checknew`).
  @discardableResult
  func checkNewPodcastEpisodes(podcastLibraryItemId: String, limit: Int?) async throws -> ABSPodcastCheckNewResponse {
    var query: [String: String] = [:]
    if let limit {
      query["limit"] = "\(limit)"
    }
    let req = try authorizedRequest(
      path: "api/podcasts/\(podcastLibraryItemId)/checknew",
      query: query,
      timeout: 180
    )
    return try await send(req)
  }

  func item(id: String, expanded: Bool = true) async throws -> ABSBook {
    let data = try await itemResponseData(id: id, expanded: expanded)
    return try decoder.decode(ABSBook.self, from: data)
  }

  func itemResponseData(id: String, expanded: Bool = true) async throws -> Data {
    let q = ["expanded": expanded ? "1" : "0"]
    let req = try authorizedRequest(path: "api/items/\(id)", query: q)
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    return data
  }

  /// Podcast: Auto-Download und Cron-Zeitplan (`PATCH /api/items/:id/media`).
  func patchPodcastMediaAutoDownload(
    itemId: String,
    autoDownloadEpisodes: Bool,
    autoDownloadSchedule: String,
    maxEpisodesToKeep: Int,
    maxNewEpisodesToDownload: Int
  ) async throws {
    let body = try encoder.encode(
      ABSPodcastMediaAutoDownloadPatch(
        autoDownloadEpisodes: autoDownloadEpisodes,
        autoDownloadSchedule: autoDownloadSchedule,
        maxEpisodesToKeep: maxEpisodesToKeep,
        maxNewEpisodesToDownload: maxNewEpisodesToDownload
      ))
    let req = try authorizedRequest(path: "api/items/\(itemId)/media", method: "PATCH", body: body)
    try await sendData(req)
  }

  /// Verfügbare Metadaten-Provider (`GET /api/search/providers`).
  func metadataProviders() async throws -> ABSMetadataProvidersResponse {
    let req = try authorizedRequest(path: "api/search/providers")
    return try await send(req)
  }

  /// Online-Metadaten-Suche für Match (`GET /api/search/books`).
  func searchBooks(title: String, author: String?, provider: String = "audible", region: String? = nil) async throws -> [ABSMetadataMatch] {
    var query: [String: String] = ["title": title, "provider": provider]
    if let author, !author.isEmpty { query["author"] = author }
    if let region, !region.isEmpty { query["region"] = region }
    let req = try authorizedRequest(path: "api/search/books", query: query)
    // Antwort ist flaches JSON-Array; einzelne Treffer defensively dekodiert.
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    // Leere Antwort = keine Treffer.
    guard !data.isEmpty else { return [] }
    do {
      let raw = try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
      // Manche Provider lieern `{ book: {...} }`-Wrapper pro Treffer.
      return raw.compactMap { item in
        guard let dict = item as? [String: Any] else { return nil }
        // Wenn ein `book`-Sub-Objekt existiert, dessen Felder nach oben heben (für einheitliche Dekodierung).
        if let nested = dict["book"] as? [String: Any] {
          var merged = nested
          for (k, v) in dict where k != "book" { merged[k] = merged[k] ?? v }
          if let d = try? JSONSerialization.data(withJSONObject: merged) {
            return try? decoder.decode(ABSMetadataMatch.self, from: d)
          }
        }
        if let d = try? JSONSerialization.data(withJSONObject: dict) {
          return try? decoder.decode(ABSMetadataMatch.self, from: d)
        }
        return nil
      }
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Wendet ausgewählte Match-Felder an (`PATCH /api/items/:id/media` + optional `POST /api/items/:id/cover`).
  func updateItemMedia(itemId: String, patch: ABSItemMediaMetadataPatch, coverURL: String?) async throws {
    let body = try encoder.encode(patch)
    let req = try authorizedRequest(path: "api/items/\(itemId)/media", method: "PATCH", body: body)
    try await sendData(req)
    // Cover separater Endpunkt, falls gewünscht.
    if let coverURL, !coverURL.isEmpty {
      try await postCoverURL(itemId: itemId, url: coverURL)
    }
  }

  /// Setzt ein Cover per Remote-URL (`POST /api/items/:id/cover` mit `{ url }`-JSON).
  func applyCoverURL(itemId: String, url: String) async throws {
    try await postCoverURL(itemId: itemId, url: url)
  }

  /// Gemeinsamer Cover-Apply-Pfad — von `updateItemMedia` und `applyCoverURL` genutzt.
  private func postCoverURL(itemId: String, url: String) async throws {
    guard let payload = try? encoder.encode(["url": url]) else { return }
    let req = try authorizedRequest(path: "api/items/\(itemId)/cover", method: "POST", body: payload)
    try await sendData(req)
  }

  /// Online-Cover-Suche (`GET /api/search/covers?title=&author=&provider=`).
  /// Liefert normalisierte URL-Strings — unabhängig von der variablen Server-Antwortform.
  func searchCovers(title: String, author: String?, provider: String = "google") async throws -> [String] {
    var query: [String: String] = ["title": title, "provider": provider]
    if let author, !author.isEmpty { query["author"] = author }
    let req = try authorizedRequest(path: "api/search/covers", query: query, timeout: 25)
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    guard !data.isEmpty else { return [] }
    do {
      let parsed = try decoder.decode(ABSCoverSearchResponse.self, from: data)
      // Deduplizieren, Reihenfolge erhalten.
      var seen = Set<String>()
      return parsed.urls.filter { seen.insert($0).inserted }
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Audible-Kapitel-Lookup via Audnexus (`GET /api/search/chapters?asin=&region=`).
  /// Liefert die Roh-Antwort inkl. `chapters`, `runtimeLengthSec` und Branding-Dauern — oder `{ error }`.
  func searchChapters(asin: String, region: String = "us") async throws -> ABSAudibleChaptersResponse {
    let req = try authorizedRequest(
      path: "api/search/chapters",
      query: ["asin": asin, "region": region],
      timeout: 20
    )
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      return try decoder.decode(ABSAudibleChaptersResponse.self, from: data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Speichert Kapitel (`POST /api/items/:id/chapters`). Body: `{ "chapters": [{ id, start, end, title }] }`.
  func updateItemChapters(itemId: String, chapters: [ABSItemChaptersPayload.Chapter]) async throws {
    let body = try encoder.encode(ABSItemChaptersPayload(chapters: chapters))
    let req = try authorizedRequest(path: "api/items/\(itemId)/chapters", method: "POST", body: body)
    try await sendData(req)
  }

  func search(libraryId: String, query: String, limit: Int = 48) async throws -> ABSSearchResponse {
    let req = try authorizedRequest(
      path: "api/libraries/\(libraryId)/search",
      query: [
        "q": query,
        "limit": "\(limit)",
      ]
    )
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      var result = try decoder.decode(ABSSearchResponse.self, from: data)
      result.podcastEpisodeMatches = Self.decodePodcastSearchEpisodes(
        from: data, libraryId: libraryId)
      return result
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Personalisierte Regale wie in der Web-App (`GET /api/libraries/:id/personalized`).
  func personalizedShelves(libraryId: String, limit: Int = 14) async throws -> Data {
    let req = try authorizedRequest(
      path: "api/libraries/\(libraryId)/personalized",
      query: ["limit": "\(limit)"]
    )
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    return data
  }

  /// Dekodiert Regale mit Typ `book`, `series` (Bücher aus Serienobjekten) und `authors`.
  nonisolated static func parsePersonalizedStartShelves(data: Data) -> [ABSStartShelfSection] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }
    let dec = ABSJSON.decoder()
    var out: [ABSStartShelfSection] = []
    out.reserveCapacity(root.count)
    for shelf in root {
      guard let sid = shelf["id"] as? String,
        let label = shelf["label"] as? String,
        let type = shelf["type"] as? String
      else { continue }
      let category = ABSStartShelfLocalization.normalizedSettingsCategory(
        shelfId: sid,
        apiCategory: shelf["category"] as? String
      )
      let entities = shelf["entities"] as? [[String: Any]] ?? []

      if type == "book" {
        var books: [ABSBook] = []
        for e in entities {
          if let mt = e["mediaType"] as? String, mt != "book" { continue }
          guard let sub = try? JSONSerialization.data(withJSONObject: e),
            let book = try? dec.decode(ABSBook.self, from: sub)
          else { continue }
          let include: Bool
          if category == "continueSeries" {
            include = book.isPlayableAudiobook || book.isPureEbookLibraryItem
          } else {
            include = book.isPlayableAudiobook
          }
          guard include else { continue }
          books.append(book)
        }
        guard !books.isEmpty else { continue }
        let title = ABSStartShelfLocalization.displayTitle(category: category, serverLabel: label)
        out.append(
          ABSStartShelfSection(
            id: sid, category: category, displayTitle: title, books: books, podcastEpisodes: [],
            authors: []))
      } else if type == "series" {
        let isContinueSeries = category == "continueSeries"
        var series: [ABSLibrarySeriesListItem] = []
        for ser in entities {
          guard let sub = try? JSONSerialization.data(withJSONObject: ser),
            let item = try? dec.decode(ABSLibrarySeriesListItem.self, from: sub)
          else { continue }
          if isContinueSeries {
            let books = item.books ?? []
            let hasContent = books.contains(where: { $0.isPlayableAudiobook || $0.isPureEbookLibraryItem })
            if hasContent || !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              series.append(item)
            }
            continue
          }
          let playable = (item.books ?? []).contains(where: \.isPlayableAudiobook)
          let hasEbook = (item.books ?? []).contains(where: \.isUsableEbookListRow)
          if playable || hasEbook || !(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            series.append(item)
          }
        }
        guard !series.isEmpty else { continue }
        let title = ABSStartShelfLocalization.displayTitle(category: category, serverLabel: label)
        out.append(
          ABSStartShelfSection(
            id: sid, category: category, displayTitle: title, books: [], series: series))
      } else if type == "authors" {
        var authors: [ABSAuthorShelfEntity] = []
        for e in entities {
          guard let sub = try? JSONSerialization.data(withJSONObject: e),
            let a = try? dec.decode(ABSAuthorShelfEntity.self, from: sub)
          else { continue }
          authors.append(a)
        }
        guard !authors.isEmpty else { continue }
        let title = ABSStartShelfLocalization.displayTitle(category: category, serverLabel: label)
        out.append(
          ABSStartShelfSection(
            id: sid, category: category, displayTitle: title, books: [], podcastEpisodes: [],
            authors: authors))
      }
    }
    return out
  }

  /// Laufende Titel (Bücher + Podcast-Folgen mit Fortschritt), vgl. `GET /api/me/items-in-progress`.
  func itemsInProgress(limit: Int = 50) async throws -> ABSItemsInProgressPayload {
    try await itemsInProgressWithRawData(limit: limit).payload
  }

  /// Wie `itemsInProgress`, zusätzlich Roh-JSON für den Disk-Cache (Continue listening).
  func itemsInProgressWithRawData(limit: Int = 50) async throws -> (
    payload: ABSItemsInProgressPayload, rawData: Data
  ) {
    let req = try authorizedRequest(path: "api/me/items-in-progress", query: ["limit": "\(limit)"])
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    return (Self.decodeInProgressPayload(from: data), data)
  }

  nonisolated static func decodeInProgressPayload(from data: Data) -> ABSItemsInProgressPayload {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = root["libraryItems"] as? [[String: Any]]
    else {
      return ABSItemsInProgressPayload(books: [], podcastEpisodes: [])
    }
    let dec = ABSJSON.decoder()
    var books: [ABSBook] = []
    var podcastEpisodes: [ABSPodcastEpisodeListItem] = []
    books.reserveCapacity(items.count)
    podcastEpisodes.reserveCapacity(min(32, items.count))
    for obj in items {
      let mt = (obj["mediaType"] as? String)?.lowercased() ?? ""
      if mt == "book" {
        guard let sub = try? JSONSerialization.data(withJSONObject: obj) else { continue }
        if let book = try? dec.decode(ABSBook.self, from: sub), book.isPlayableAudiobook {
          books.append(book)
        }
      } else if mt == "podcast" {
        guard var recent = obj["recentEpisode"] as? [String: Any] else { continue }
        let liId = (obj["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !liId.isEmpty else { continue }
        let existing = (recent["libraryItemId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existing.isEmpty {
          recent["libraryItemId"] = liId
        }
        guard let subEp = try? JSONSerialization.data(withJSONObject: recent) else { continue }
        guard let dto = try? dec.decode(ABSRecentPodcastEpisodeDTO.self, from: subEp) else { continue }
        let libId = obj["libraryId"] as? String
        var show: ABSBook?
        if let subLi = try? JSONSerialization.data(withJSONObject: obj) {
          show = try? dec.decode(ABSBook.self, from: subLi)
        }
        if let row = ABSPodcastEpisodeListItem.fromDTO(dto, fallbackShow: show, libraryId: libId) {
          podcastEpisodes.append(row)
        }
      }
    }
    return ABSItemsInProgressPayload(books: books, podcastEpisodes: podcastEpisodes)
  }

  /// Search-API: `episodes` sind Library-Items mit `recentEpisode` (wie Home/In-Progress).
  nonisolated static func decodePodcastSearchEpisodes(
    from data: Data,
    libraryId: String?
  ) -> [ABSPodcastEpisodeListItem] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = root["episodes"] as? [[String: Any]]
    else {
      return []
    }
    let dec = ABSJSON.decoder()
    let libIdRaw = libraryId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let libId: String? = libIdRaw.isEmpty ? nil : libIdRaw
    var podcastEpisodes: [ABSPodcastEpisodeListItem] = []
    podcastEpisodes.reserveCapacity(items.count)
    for obj in items {
      if let row = decodePodcastSearchEpisodeRow(obj, libraryId: libId, decoder: dec) {
        podcastEpisodes.append(row)
      }
    }
    return ABSPodcastEpisodeListItem.dedupeRows(podcastEpisodes)
  }

  /// Ein Search-Treffer: Show-Library-Item mit `recentEpisode` oder direktes Episoden-Objekt.
  nonisolated private static func decodePodcastSearchEpisodeRow(
    _ obj: [String: Any],
    libraryId: String?,
    decoder: JSONDecoder
  ) -> ABSPodcastEpisodeListItem? {
    let showId = (obj["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let itemLibId = (obj["libraryId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedLibId = (itemLibId?.isEmpty == false) ? itemLibId : libraryId
    var show: ABSBook?
    if !showId.isEmpty, let subLi = try? JSONSerialization.data(withJSONObject: obj) {
      show = try? decoder.decode(ABSBook.self, from: subLi)
    }

    if var recent = obj["recentEpisode"] as? [String: Any] {
      if !showId.isEmpty {
        let existing = (recent["libraryItemId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existing.isEmpty { recent["libraryItemId"] = showId }
      } else {
        showIdFallback(from: obj, into: &recent)
      }
      guard let subEp = try? JSONSerialization.data(withJSONObject: recent),
        let dto = try? decoder.decode(ABSRecentPodcastEpisodeDTO.self, from: subEp)
      else { return nil }
      let forceLi = showId.isEmpty ? nil : showId
      return ABSPodcastEpisodeListItem.fromDTO(
        dto, fallbackShow: show, libraryId: resolvedLibId, forceLibraryItemId: forceLi)
    }

    return nil
  }

  nonisolated private static func showIdFallback(from obj: [String: Any], into recent: inout [String: Any]) {
    let existing = (recent["libraryItemId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard existing.isEmpty else { return }
    let showId = (obj["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !showId.isEmpty { recent["libraryItemId"] = showId }
  }

  /// Paginierte Hör-Sitzungen des eingeloggten Nutzers (`libraryItemId` + ggf. `episodeId` pro Eintrag).
  func listeningSessionsMe(itemsPerPage: Int = 50, page: Int = 0) async throws -> ABSListeningSessionsPayload {
    let req = try authorizedRequest(
      path: "api/me/listening-sessions",
      query: [
        "itemsPerPage": "\(max(1, min(itemsPerPage, 100)))",
        "page": "\(max(0, page))",
      ]
    )
    return try await sendListeningSessionsPayload(req)
  }

  /// Hör-Sitzungen zu **einem** Medium (ab Server ~2.8; für Bücher ohne `episodeId`).
  func listeningSessionsForLibraryItem(
    libraryItemId: String,
    episodeId: String? = nil,
    itemsPerPage: Int = 100,
    page: Int = 0
  ) async throws -> ABSListeningSessionsPayload {
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    var path = "api/me/item/listening-sessions/\(id)"
    if let e = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
      path += "/\(e)"
    }
    let req = try authorizedRequest(
      path: path,
      query: [
        "itemsPerPage": "\(max(1, min(itemsPerPage, 100)))",
        "page": "\(max(0, page))",
      ]
    )
    return try await sendListeningSessionsPayload(req)
  }

  func createBookmark(libraryItemId: String, time: Int, title: String) async throws -> ABSAudioBookmark {
    let body = try encoder.encode(ABSCreateBookmarkRequest(time: time, title: title))
    let req = try authorizedRequest(
      path: "api/me/item/\(libraryItemId)/bookmark",
      method: "POST",
      body: body
    )
    return try await send(req)
  }

  func deleteBookmark(libraryItemId: String, time: Int) async throws {
    let req = try authorizedRequest(
      path: "api/me/item/\(libraryItemId)/bookmark/\(time)",
      method: "DELETE"
    )
    try await sendData(req)
  }

  /// Aggregierte Statistik (Hördauer pro Tag, meist gehört, letzte Sitzungen).
  /// Liefert die Rohantwort für den lokalen SwiftData-Cache (`LocalListeningStatsSnapshot`).
  func listeningStats() async throws -> (stats: ABSListeningStatsResponse, rawData: Data) {
    let req = try authorizedRequest(path: "api/me/listening-stats")
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      let stats = try ABSListeningStatsResponse.decodeAPIPayload(data)
      return (stats, data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  func startPlaySession(
    itemId: String,
    episodeId: String? = nil,
    deviceId: String,
    appVersion: String?
  ) async throws -> ABSPlaySession {
    let body = try encoder.encode(ABSPlaySessionRequest(deviceId: deviceId, clientVersion: appVersion))
    let path: String
    if let eid = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines), !eid.isEmpty {
      path = "api/items/\(itemId)/play/\(eid)"
    } else {
      path = "api/items/\(itemId)/play"
    }
    let req = try authorizedRequest(
      path: path,
      method: "POST",
      body: body,
      timeout: 60
    )
    return try await send(req)
  }

  func syncPlaySession(sessionId: String, timeListened: Int, currentTime: Double) async throws {
    let body = try encoder.encode(ABSSessionSyncBody(timeListened: timeListened, currentTime: currentTime))
    let req = try authorizedRequest(path: "api/session/\(sessionId)/sync", method: "POST", body: body)
    try await sendData(req)
  }

  func closePlaySession(sessionId: String) async throws {
    let req = try authorizedRequest(path: "api/session/\(sessionId)/close", method: "POST")
    try await sendData(req)
  }

  func patchProgress(
    libraryItemId: String,
    episodeId: String? = nil,
    patch: ABSProgressPatch
  ) async throws {
    let body = try encoder.encode(patch)
    let path: String
    if let eid = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines), !eid.isEmpty {
      path = "api/me/progress/\(libraryItemId)/\(eid)"
    } else {
      path = "api/me/progress/\(libraryItemId)"
    }
    let req = try authorizedRequest(path: path, method: "PATCH", body: body)
    try await sendData(req)
  }

  /// Entfernt den Media-Progress-Eintrag (`DELETE /api/me/progress/:id` mit `MediaProgress.id` aus `/authorize`).
  func deleteMediaProgress(progressRowId: String) async throws {
    let id = progressRowId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { throw ABSAPIError.invalidURL }
    let path = "api/me/progress/\(id)"
    let req = try authorizedRequest(path: path, method: "DELETE")
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    if http.statusCode == 404 { return }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
  }

  func markFinished(libraryItemId: String, episodeId: String? = nil) async throws {
    try await patchProgress(
      libraryItemId: libraryItemId,
      episodeId: episodeId,
      patch: ABSProgressPatch(currentTime: nil, duration: nil, progress: nil, isFinished: true)
    )
  }

  func deleteLibraryItem(id: String) async throws {
    let req = try authorizedRequest(path: "api/items/\(id)", method: "DELETE")
    try await sendData(req)
  }

  /// Podcast-Folge von der Bibliothek entfernen (`DELETE /api/podcasts/:id/episode/:episodeId`).
  func deletePodcastEpisode(podcastLibraryItemId: String, episodeId: String) async throws {
    let req = try authorizedRequest(
      path: "api/podcasts/\(podcastLibraryItemId)/episode/\(episodeId)",
      method: "DELETE"
    )
    try await sendData(req)
  }

  func coverURL(itemId: String, tier: CoverImageTier = .thumbnail) -> URL {
    Self.itemCoverURL(baseURL: baseURL, itemId: itemId, tier: tier)
  }

  nonisolated static func itemCoverURL(baseURL: URL, itemId: String, tier: CoverImageTier) -> URL {
    var components = URLComponents(
      url: baseURL.appendingPathComponent("api/items/\(itemId)/cover"),
      resolvingAgainstBaseURL: false
    )!
    switch tier {
    case .thumbnail:
      components.queryItems = [
        URLQueryItem(name: "width", value: "400"),
        URLQueryItem(name: "format", value: "jpeg"),
      ]
    case .hero:
      components.queryItems = [
        URLQueryItem(name: "width", value: "1200"),
        URLQueryItem(name: "format", value: "jpeg"),
      ]
    }
    return components.url ?? baseURL.appendingPathComponent("api/items/\(itemId)/cover")
  }

  func authenticatedData(from url: URL) async throws -> Data {
    var req = URLRequest(url: url, timeoutInterval: 60)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
      let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
      throw ABSAPIError.httpStatus(code, nil)
    }
    return data
  }

  /// Lädt die Datei mit optionalen **Wiederholungen** (jeweils neuer Request, gleicher URL) — ohne `resumeFrom`,
  /// damit keine inkompatiblen Resume-Daten die komplette Download-Kette blockieren.
  func downloadAuthenticatedFile(
    from streamURL: URL,
    to suggestedDestination: URL,
    maxAttempts: Int = 3
  ) async throws -> URL {
    var lastError: Error?
    for attempt in 0..<maxAttempts {
      do {
        var req = URLRequest(url: streamURL, timeoutInterval: 600)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (temp, resp) = try await downloadURLSession.download(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
          try? FileManager.default.removeItem(at: temp)
          throw ABSAPIError.httpStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, nil)
        }
        let ext = Self.pickAudioFileExtension(mimeType: http.mimeType, fileURL: temp)
        let stem = suggestedDestination.deletingPathExtension().lastPathComponent
        let dir = suggestedDestination.deletingLastPathComponent()
        let finalURL = dir.appendingPathComponent("\(stem).\(ext)")
        if FileManager.default.fileExists(atPath: finalURL.path) {
          try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: temp, to: finalURL)
        return finalURL
      } catch {
        lastError = error
        if error is CancellationError { throw error }
        if let urlErr = error as? URLError, urlErr.code == .cancelled { throw error }
        if attempt < maxAttempts - 1 {
          let delay = min(8.0, 0.6 * Double(attempt + 1))
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
      }
    }
    throw lastError ?? ABSAPIError.emptyBody
  }

  /// Lädt die Datei mit Byte-Fortschritt-Rückruf (`fractionCompleted` 0…1) und Wiederholungen.
  /// Für Aufrufer, die Intra-Track-Fortschritt zeigen wollen (z. B. `DownloadManager` bei Einzel-Tracks).
  func downloadAuthenticatedFile(
    from streamURL: URL,
    to suggestedDestination: URL,
    maxAttempts: Int = 3,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    // Content-Length vorab via HEAD ermitteln — viele Stream-Responses liefern keine
    // `expectedContentLength` an den Download-Delegate (dann ist `totalBytesExpectedToWrite == -1`
    // und der Fortschritts-Callback schweigt → Sprung von 0 auf fertig bei Einzel-Track-Folgen).
    let knownSize: Int64? = await fetchExpectedContentLength(url: streamURL)
    var lastError: Error?
    for attempt in 0..<maxAttempts {
      do {
        var req = URLRequest(url: streamURL, timeoutInterval: 600)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let delegate = FileDownloadProgressDelegate(onProgress: progress, knownExpectedBytes: knownSize)
        let (temp, resp) = try await downloadURLSession.download(for: req, delegate: delegate)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
          try? FileManager.default.removeItem(at: temp)
          throw ABSAPIError.httpStatus((resp as? HTTPURLResponse)?.statusCode ?? -1, nil)
        }
        let ext = Self.pickAudioFileExtension(mimeType: http.mimeType, fileURL: temp)
        let stem = suggestedDestination.deletingPathExtension().lastPathComponent
        let dir = suggestedDestination.deletingLastPathComponent()
        let finalURL = dir.appendingPathComponent("\(stem).\(ext)")
        if FileManager.default.fileExists(atPath: finalURL.path) {
          try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: temp, to: finalURL)
        return finalURL
      } catch {
        lastError = error
        if error is CancellationError { throw error }
        if let urlErr = error as? URLError, urlErr.code == .cancelled { throw error }
        if attempt < maxAttempts - 1 {
          let delay = min(8.0, 0.6 * Double(attempt + 1))
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
      }
    }
    throw lastError ?? ABSAPIError.emptyBody
  }

  /// Ermittelt die Content-Length via HEAD-Request. Liefert `nil` bei Fehler oder unbekannter Größe
  /// (z. B. Server ohne `Content-Length`-Header). Wird für den Intra-Track-Download-Fortschritt gebraucht,
  /// da `URLSessionDownloadTask.expectedContentLength` bei gestreamten Responses oft -1 ist.
  private func fetchExpectedContentLength(url: URL) async -> Int64? {
    var req = URLRequest(url: url, timeoutInterval: 30)
    req.httpMethod = "HEAD"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    guard let resp = try? await downloadURLSession.data(for: req).1 as? HTTPURLResponse,
      (200..<300).contains(resp.statusCode) else {
      return nil
    }
    let len = resp.expectedContentLength
    return len > 0 ? len : nil
  }

  /// Dateiendung ohne Punkt, Kleinbuchstaben.
  private static func pickAudioFileExtension(mimeType: String?, fileURL: URL) -> String {
    let m = mimeType?.lowercased() ?? ""
    if m.contains("mpeg") || m.contains("mp3") { return "mp3" }
    if m.contains("aac"), !m.contains("mp4") { return "aac" }
    if m.contains("flac") { return "flac" }
    if m.contains("ogg") || m.contains("opus") || m.contains("vorbis") { return "ogg" }
    if m.contains("mp4") || m.contains("m4a") || m.contains("m4b") { return "m4a" }
    if m.contains("wav") { return "wav" }
    if m.contains("octet-stream") || m.isEmpty {
      if let s = try? sniffAudioContainer(fileURL: fileURL) { return s }
    }
    if let s = try? sniffAudioContainer(fileURL: fileURL) { return s }
    return "m4a"
  }

  private static func sniffAudioContainer(fileURL: URL) throws -> String {
    let h = try FileHandle(forReadingFrom: fileURL)
    defer { try? h.close() }
    let data = try h.read(upToCount: 16) ?? Data()
    guard data.count >= 4 else { return "m4a" }
    if data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 { return "mp3" }
    if data.count >= 2, data[0] == 0xFF, (data[1] & 0xE0) == 0xE0 { return "mp3" }
    if data.count >= 8 {
      let ftyp = data.subdata(in: 4 ..< 8)
      if ftyp == Data([0x66, 0x74, 0x79, 0x70]) { return "m4a" }  // "ftyp"
    }
    return "m4a"
  }

  /// Apple-Podcasts-Suche (`GET /api/search/podcast`).
  func searchPodcastsDirectory(term: String, country: String) async throws -> [ABSPodcastDirectorySearchHit] {
    let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return [] }
    let req = try authorizedRequest(
      path: "api/search/podcast",
      query: [
        "term": t,
        "country": country,
      ]
    )
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    return try decoder.decode([ABSPodcastDirectorySearchHit].self, from: data)
  }

  /// Autoren der Bibliothek (`GET /api/libraries/:id/authors`), mit Pagination und `sort`/`desc`.
  func libraryAuthorsPage(
    libraryId: String,
    page: Int,
    limit: Int = 50,
    sort: String,
    descending: Bool
  ) async throws -> (results: [ABSLibraryAuthorListItem], total: Int, raw: Data) {
    var q: [String: String] = [
      "limit": "\(limit)",
      "page": "\(page)",
      "sort": sort,
    ]
    if descending { q["desc"] = "1" }
    let req = try authorizedRequest(path: "api/libraries/\(libraryId)/authors", query: q)
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      let env = try decoder.decode(ABSLibraryAuthorsAPIEnvelope.self, from: data)
      let pair = env.itemsAndTotal()
      return (pair.0, pair.1, data)
    } catch {
      if page != 0 { throw ABSAPIError.decoding(error) }
      let plain = try authorizedRequest(path: "api/libraries/\(libraryId)/authors")
      let (data2, resp2) = try await urlSession.data(for: plain)
      guard let http2 = resp2 as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
      guard (200 ..< 300).contains(http2.statusCode) else {
        throw ABSAPIError.httpStatus(http2.statusCode, String(data: data2, encoding: .utf8))
      }
      do {
        let legacy = try decoder.decode(ABSLibraryAuthorsEnvelope.self, from: data2)
        let list = legacy.authors
        return (list, list.count, data2)
      } catch {
        throw ABSAPIError.decoding(error)
      }
    }
  }

  /// Autor inkl. optionaler Bücher/Serien (`GET /api/authors/:id`).
  func authorDetail(
    authorId: String,
    libraryId: String?,
    includeItems: Bool,
    includeSeries: Bool
  ) async throws -> ABSAuthorDetail {
    var q: [String: String] = [:]
    var include: [String] = []
    if includeItems { include.append("items") }
    if includeSeries, includeItems { include.append("series") }
    if !include.isEmpty { q["include"] = include.joined(separator: ",") }
    if let libraryId, !libraryId.isEmpty { q["library"] = libraryId }
    let req = try authorizedRequest(path: "api/authors/\(authorId)", query: q)
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      return try decoder.decode(ABSAuthorDetail.self, from: data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Sammlung inkl. Beschreibung (`GET /api/collections/:id`).
  func collectionDetail(collectionId: String) async throws -> ABSLibraryCollectionListItem {
    let req = try authorizedRequest(path: "api/collections/\(collectionId)")
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      return try decoder.decode(ABSLibraryCollectionListItem.self, from: data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Serie (`GET /api/series/:id`) — ohne nutzerbeschreibbares Description-Feld in der UI.
  func seriesDetail(seriesId: String) async throws -> ABSSeriesDetail {
    let req = try authorizedRequest(path: "api/series/\(seriesId)")
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      return try decoder.decode(ABSSeriesDetail.self, from: data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Alle Sprecher:innen (`GET /api/libraries/:id/narrators`).
  func libraryNarrators(libraryId: String) async throws -> (results: [ABSLibraryNarratorListItem], raw: Data) {
    let req = try authorizedRequest(path: "api/libraries/\(libraryId)/narrators")
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      let env = try decoder.decode(ABSLibraryNarratorsEnvelope.self, from: data)
      return (env.narrators, data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Serien mit Paginierung (`GET /api/libraries/:id/series`).
  func librarySeriesPage(
    libraryId: String,
    page: Int,
    limit: Int = 40,
    sort: String,
    descending: Bool
  ) async throws -> (results: [ABSLibrarySeriesListItem], total: Int, raw: Data) {
    var q: [String: String] = [
      "limit": "\(limit)",
      "page": "\(page)",
      "sort": sort,
      "minified": "1",
    ]
    if descending { q["desc"] = "1" }
    let req = try authorizedRequest(path: "api/libraries/\(libraryId)/series", query: q)
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      let env = try decoder.decode(ABSLibraryResultsPageEnvelope<ABSLibrarySeriesListItem>.self, from: data)
      return (env.results, env.total, data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Alle Sammlungen (`GET /api/libraries/:id/collections`, `limit=0` = vollständig — Sortierung im Client).
  func libraryCollectionsAll(libraryId: String, minified: Bool = true) async throws -> (
    results: [ABSLibraryCollectionListItem], total: Int, raw: Data
  ) {
    let q: [String: String] = [
      "limit": "0",
      "page": "0",
      "minified": minified ? "1" : "0",
    ]
    let req = try authorizedRequest(path: "api/libraries/\(libraryId)/collections", query: q)
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    do {
      let env = try decoder.decode(ABSLibraryResultsPageEnvelope<ABSLibraryCollectionListItem>.self, from: data)
      return (env.results, env.total, data)
    } catch {
      throw ABSAPIError.decoding(error)
    }
  }

  /// Ordner der Bibliothek (`GET /api/libraries/:id`, Feld `folders`).
  func libraryFolders(libraryId: String) async throws -> [ABSLibraryFolderRow] {
    let req = try authorizedRequest(path: "api/libraries/\(libraryId)")
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    let parsed = try decoder.decode(ABSLibraryDetailFoldersPayload.self, from: data)
    return parsed.folders ?? []
  }

  /// Neuen Podcast anlegen (`POST /api/podcasts`).
  func createPodcastInLibrary(jsonBody: Data) async throws -> String {
    let req = try authorizedRequest(path: "api/podcasts", method: "POST", body: jsonBody, timeout: 180)
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    struct IdRow: Decodable {
      let id: String?
    }
    let row = try decoder.decode(IdRow.self, from: data)
    guard let id = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
      throw ABSAPIError.decoding(
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing podcast id in response")))
    }
    return id
  }
}

/// Downloads-Fortschritt-Delegate: reicht `bytesWritten/totalBytes` als `fractionCompleted` weiter.
/// Läuft auf der URLSession-Delegate-Queue (nicht isoliert) — `onProgress` muss thread-safe sein.
private final class FileDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
  private let onProgress: @Sendable (Double) -> Void
  /// Fallback-Größe (via HEAD ermittelt) — genutzt, wenn `totalBytesExpectedToWrite == -1`
  /// (Server ohne `Content-Length`-Header).
  private let knownExpectedBytes: Int64?

  init(onProgress: @escaping @Sendable (Double) -> Void, knownExpectedBytes: Int64?) {
    self.onProgress = onProgress
    self.knownExpectedBytes = knownExpectedBytes
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    // Erwartete Größe: bevorzugt aus dem URLSession-Callback, Fallback aus HEAD-Request.
    let expected = totalBytesExpectedToWrite > 0
      ? totalBytesExpectedToWrite
      : (knownExpectedBytes ?? -1)
    guard expected > 0 else { return }
    let fraction = Double(totalBytesWritten) / Double(expected)
    onProgress(min(max(0, fraction), 1))
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // `download(for:delegate:)` kümmert sich um die temporäre Datei; kein Handling nötig.
  }
}
