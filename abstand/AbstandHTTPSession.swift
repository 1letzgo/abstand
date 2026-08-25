import Foundation

/// Gemeinsame `URLSession` für Cover-/Cache-GETs außerhalb von `ABSAPIClient`.
/// Vermeidet `URLSession.shared` (keine Timeouts / `waitsForConnectivity`).
enum AbstandHTTPSession {
  static let coverAndCache: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.waitsForConnectivity = true
    cfg.timeoutIntervalForRequest = 30
    cfg.timeoutIntervalForResource = 120
    cfg.requestCachePolicy = .returnCacheDataElseLoad
    return URLSession(configuration: cfg)
  }()

  /// URLRequest mit zentralem Bearer-Header — für alle Cover-/Cache-GETs außerhalb des API-Clients.
  /// `nil`/leerer Token → kein Authorization-Header (externe URLs, z. B. Apple Podcasts Directory).
  static func authorizedRequest(url: URL, token: String?, timeout: TimeInterval = 30) -> URLRequest {
    var req = URLRequest(url: url, timeoutInterval: timeout)
    if let trimmed = token?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty {
      req.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
    }
    return req
  }

  /// Header-Options für `AVURLAsset` (Streaming-/Transkript-Laden) mit Bearer-Auth.
  static func authorizedAssetHeaders(token: String) -> [String: Any] {
    ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
  }
}
