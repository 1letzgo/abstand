import Foundation

/// Gemeinsame `URLSession` für Cover-/Cache-GETs außerhalb von `ABSAPIClient`.
/// Vermeidet `URLSession.shared` (keine Timeouts / `waitsForConnectivity`).
enum AbstandHTTPSession {
  static let coverAndCache: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.waitsForConnectivity = true
    cfg.timeoutIntervalForRequest = 30
    cfg.timeoutIntervalForResource = 120
    // Kein `URLCache`: Cover liegen bereits in `CoverImageCache` (eigener Account-Ordner mit
    // Prune). Der geteilte URLCache hätte dieselben Bytes ein zweites Mal auf der Platte —
    // in einer Größe, die hier niemand steuert und die der eigene Prune nicht anfasst.
    cfg.urlCache = nil
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: cfg, delegate: AbstandTrustDelegate.shared, delegateQueue: nil)
  }()

  /// URLRequest mit zentralem Bearer-Header — für alle Cover-/Cache-GETs außerhalb des API-Clients.
  /// `nil`/leerer Token → kein Authorization-Header (externe URLs, z. B. Apple Podcasts Directory).
  static func authorizedRequest(url: URL, token: String?, timeout: TimeInterval = 30) -> URLRequest {
    var req = URLRequest(url: url, timeoutInterval: timeout)
    if let trimmed = token?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty {
      req.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
    }
    // Custom-Header nur für den eigenen Server — externe Hosts bekommen nichts (Origin-Abgleich).
    AbstandCustomHeadersStore.apply(to: &req)
    return req
  }

  /// Header-Options für `AVURLAsset` (Streaming-/Transkript-Laden) mit Bearer-Auth und den
  /// Custom-Headern des Servers.
  static func authorizedAssetHeaders(token: String, url: URL) -> [String: Any] {
    var headers = AbstandCustomHeadersStore.headers(for: url)
    headers["Authorization"] = "Bearer \(token)"
    return ["AVURLAssetHTTPHeaderFieldsKey": headers]
  }
}
