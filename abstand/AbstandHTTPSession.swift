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
}
