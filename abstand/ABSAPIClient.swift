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

  init(baseURL: URL, token: String) {
    self.baseURL = baseURL
    self.token = token
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 120
    cfg.timeoutIntervalForResource = 3_600
    self.urlSession = URLSession(configuration: cfg)
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

  static func login(server: URL, username: String, password: String) async throws -> ABSLoginResponse {
    let url = server.appendingPathComponent("login")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(ABSLoginRequest(username: username, password: password))
    let (data, resp) = try await URLSession.shared.data(for: req)
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

  func libraries() async throws -> [ABSLibrary] {
    let req = try authorizedRequest(path: "api/libraries")
    let res: ABSLibrariesResponse = try await send(req)
    return res.libraries
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
    let (data, resp) = try await urlSession.data(for: req)
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

  func item(id: String, expanded: Bool = true) async throws -> ABSBook {
    let q = ["expanded": expanded ? "1" : "0"]
    let req = try authorizedRequest(path: "api/items/\(id)", query: q)
    return try await send(req)
  }

  func search(libraryId: String, query: String, limit: Int = 48) async throws -> ABSSearchResponse {
    let req = try authorizedRequest(
      path: "api/libraries/\(libraryId)/search",
      query: [
        "q": query,
        "limit": "\(limit)",
      ]
    )
    return try await send(req)
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
            let book = try? dec.decode(ABSBook.self, from: sub),
            book.isPlayableAudiobook
          else { continue }
          books.append(book)
        }
        guard !books.isEmpty else { continue }
        let title = ABSStartShelfLocalization.displayTitle(category: category, serverLabel: label)
        out.append(
          ABSStartShelfSection(
            id: sid, category: category, displayTitle: title, books: books, authors: []))
      } else if type == "series" {
        var books: [ABSBook] = []
        for ser in entities {
          let booksArr = ser["books"] as? [[String: Any]] ?? []
          for e in booksArr {
            if let mt = e["mediaType"] as? String, mt != "book" { continue }
            guard let sub = try? JSONSerialization.data(withJSONObject: e),
              let book = try? dec.decode(ABSBook.self, from: sub),
              book.isPlayableAudiobook
            else { continue }
            books.append(book)
          }
        }
        guard !books.isEmpty else { continue }
        let title = ABSStartShelfLocalization.displayTitle(category: category, serverLabel: label)
        out.append(
          ABSStartShelfSection(
            id: sid, category: category, displayTitle: title, books: books, authors: []))
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
            id: sid, category: category, displayTitle: title, books: [], authors: authors))
      }
    }
    return out
  }

  /// Laufende Hörbücher (Server-Dashboard / „Weiterhören“), unabhängig von der alphabetischen Bibliotheksliste.
  func itemsInProgress(limit: Int = 50) async throws -> [ABSBook] {
    let req = try authorizedRequest(path: "api/me/items-in-progress", query: ["limit": "\(limit)"])
    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw ABSAPIError.emptyBody }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw ABSAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
    }
    return Self.decodeInProgressBooks(from: data)
  }

  /// Dekodiert nur `mediaType == book` (Podcasts werden übersprungen, damit die ganze Antwort nicht scheitert).
  nonisolated private static func decodeInProgressBooks(from data: Data) -> [ABSBook] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = root["libraryItems"] as? [[String: Any]]
    else {
      return []
    }
    let dec = ABSJSON.decoder()
    var out: [ABSBook] = []
    out.reserveCapacity(items.count)
    for obj in items {
      if let mt = obj["mediaType"] as? String, mt != "book" { continue }
      guard let sub = try? JSONSerialization.data(withJSONObject: obj) else { continue }
      if let book = try? dec.decode(ABSBook.self, from: sub) {
        out.append(book)
      }
    }
    return out
  }

  func startPlaySession(itemId: String, deviceId: String, appVersion: String?) async throws -> ABSPlaySession {
    let body = try encoder.encode(ABSPlaySessionRequest(deviceId: deviceId, clientVersion: appVersion))
    let req = try authorizedRequest(
      path: "api/items/\(itemId)/play",
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

  func patchProgress(libraryItemId: String, patch: ABSProgressPatch) async throws {
    let body = try encoder.encode(patch)
    let req = try authorizedRequest(path: "api/me/progress/\(libraryItemId)", method: "PATCH", body: body)
    try await sendData(req)
  }

  func markFinished(libraryItemId: String) async throws {
    try await patchProgress(libraryItemId: libraryItemId, patch: ABSProgressPatch(currentTime: nil, duration: nil, progress: nil, isFinished: true))
  }

  func deleteLibraryItem(id: String) async throws {
    let req = try authorizedRequest(path: "api/items/\(id)", method: "DELETE")
    try await sendData(req)
  }

  func coverURL(itemId: String) -> URL {
    baseURL.appendingPathComponent("api/items/\(itemId)/cover")
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

  /// Lädt die Datei mit optionalen **Wiederholungen** und `NSURLSessionDownloadTaskResumeData`, legt sie unter passender Endung ab.
  /// Mehrteilige Downloads: einzelne Tracks können so robuster über instabiles Netz fertig werden.
  func downloadAuthenticatedFile(
    from streamURL: URL,
    to suggestedDestination: URL,
    maxAttempts: Int = 3
  ) async throws -> URL {
    var lastError: Error?
    var resumeData: Data?

    for attempt in 0..<maxAttempts {
      do {
        let temp: URL
        let resp: URLResponse
        if let data = resumeData {
          (temp, resp) = try await urlSession.download(resumeFrom: data)
          resumeData = nil
        } else {
          var req = URLRequest(url: streamURL, timeoutInterval: 600)
          req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          (temp, resp) = try await urlSession.download(for: req)
        }
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
        resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        if attempt < maxAttempts - 1 {
          let delay = min(12.0, pow(1.6, Double(attempt + 1)))
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
      }
    }
    throw lastError ?? ABSAPIError.emptyBody
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
}
