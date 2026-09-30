import Foundation
import Security

// Server-Zugang wie in stashy: selbstsignierte Zertifikate nur für lokale/private Hosts,
// frei definierbare HTTP-Header je Server (z. B. SSO- oder Reverse-Proxy-Token) im Keychain.

// MARK: - Custom HTTP headers

/// Ein frei definierbarer Header, der mit jedem Request an den eigenen Server geht.
nonisolated struct ServerHTTPHeader: Codable, Equatable, Hashable, Identifiable, Sendable {
  var id: UUID = UUID()
  var name: String
  var value: String

  init(id: UUID = UUID(), name: String, value: String) {
    self.id = id
    self.name = name
    self.value = value
  }

  /// Header, die URLSession / der Player selbst verwalten; sie zu setzen bricht Requests.
  /// `authorization` zusätzlich: der Bearer-Token der App darf nicht überschrieben werden.
  nonisolated static let reservedNames: Set<String> = [
    "host", "content-length", "content-type", "connection", "transfer-encoding",
    "upgrade", "range", "accept-encoding", "te", "trailer", "keep-alive", "proxy-connection",
    "authorization",
  ]

  nonisolated var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  nonisolated var trimmedValue: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// Nur RFC-7230-Token-Zeichen, nicht reserviert, Wert vorhanden.
  nonisolated var isUsable: Bool {
    let n = trimmedName
    guard !n.isEmpty, !trimmedValue.isEmpty else { return false }
    guard !Self.reservedNames.contains(n.lowercased()) else { return false }
    let token = CharacterSet(
      charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return n.unicodeScalars.allSatisfy { token.contains($0) }
      && !trimmedValue.contains("\n") && !trimmedValue.contains("\r")
  }

  /// Leere Zeilen werden stillschweigend verworfen; ungültige Namen meldet das Formular.
  nonisolated static func sanitized(_ headers: [ServerHTTPHeader]) -> [ServerHTTPHeader] {
    headers
      .filter { $0.isUsable }
      .map { ServerHTTPHeader(id: $0.id, name: $0.trimmedName, value: $0.trimmedValue) }
  }
}

/// Custom-Header je Server im Keychain (Werte sind oft SSO-Bypass-Tokens) — Schlüssel ist der
/// Origin des Servers (Schema + Host + Port), damit auch Login und weitere Accounts desselben
/// Servers sie nutzen. Gecacht: jeder Cover-Request liest sie.
nonisolated enum AbstandCustomHeadersStore {
  private static let service = "de.letzgo.abstand.customHeaders"
  private static let lock = NSLock()
  nonisolated(unsafe) private static var cache: [String: [ServerHTTPHeader]] = [:]

  /// `https://host:port` — `nil` für ungültige oder Datei-URLs.
  static func originKey(for url: URL) -> String? {
    guard !url.isFileURL, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
      !host.isEmpty
    else { return nil }
    let port = url.port ?? (scheme == "https" ? 443 : 80)
    return "\(scheme)://\(host):\(port)"
  }

  static func originKey(forServer raw: String) -> String? {
    ABSAPIClient.normalizeServerURL(raw).flatMap(originKey(for:))
  }

  static func load(forServer raw: String) -> [ServerHTTPHeader] {
    guard let key = originKey(forServer: raw) else { return [] }
    return load(originKey: key)
  }

  @discardableResult
  static func save(_ headers: [ServerHTTPHeader], forServer raw: String) -> Bool {
    guard let key = originKey(forServer: raw) else { return false }
    let clean = ServerHTTPHeader.sanitized(headers)
    lock.lock(); cache[key] = nil; lock.unlock()
    guard !clean.isEmpty else { return delete(originKey: key) }
    guard let data = try? JSONEncoder().encode(clean) else { return false }
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(baseQuery(account: key) as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return true }
    guard updateStatus == errSecItemNotFound else { return false }
    var addQuery = baseQuery(account: key)
    attributes.forEach { addQuery[$0.key] = $0.value }
    return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
  }

  /// Header für einen Request an `url` — nur, wenn er an einen Server mit gespeicherten Headern
  /// geht. Fremde Hosts (Apple-Podcast-Verzeichnis, Feed-Cover) bekommen sie nie.
  static func headers(for url: URL) -> [String: String] {
    guard let key = originKey(for: url) else { return [:] }
    return load(originKey: key).reduce(into: [:]) { $0[$1.name] = $1.value }
  }

  /// Setzt die Header in `request` (vorhandene App-Header wie `Authorization` bleiben unangetastet).
  static func apply(to request: inout URLRequest) {
    guard let url = request.url else { return }
    for (name, value) in headers(for: url) where request.value(forHTTPHeaderField: name) == nil {
      request.setValue(value, forHTTPHeaderField: name)
    }
  }

  private static func load(originKey key: String) -> [ServerHTTPHeader] {
    lock.lock()
    if let cached = cache[key] {
      lock.unlock()
      return cached
    }
    lock.unlock()
    var query = baseQuery(account: key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    var loaded: [ServerHTTPHeader] = []
    if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
      let decoded = try? JSONDecoder().decode([ServerHTTPHeader].self, from: data)
    {
      loaded = decoded
    }
    lock.lock(); cache[key] = loaded; lock.unlock()
    return loaded
  }

  @discardableResult
  private static func delete(originKey key: String) -> Bool {
    let status = SecItemDelete(baseQuery(account: key) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  private static func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

// MARK: - Self-signed certificates

/// Akzeptiert selbstsignierte Zertifikate nur für lokale / private Server. Jeder öffentliche Host —
/// Domain oder IP — fällt auf die normale TLS-Prüfung zurück, damit nichts aus dem Internet ein
/// gefälschtes Zertifikat vorlegen kann.
nonisolated final class AbstandTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate,
  @unchecked Sendable
{
  static let shared = AbstandTrustDelegate()

  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    Self.handle(challenge, completionHandler: completionHandler)
  }

  /// Manche Sessions (WebSocket, Downloads) liefern die Challenge pro Task statt pro Session.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    Self.handle(challenge, completionHandler: completionHandler)
  }

  private static func handle(
    _ challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let trust = challenge.protectionSpace.serverTrust,
      acceptsSelfSigned(host: challenge.protectionSpace.host)
    else {
      completionHandler(.performDefaultHandling, nil)
      return
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }

  /// `true` für Hosts, die nur aus dem lokalen Netz erreichbar sind: Loopback, mDNS (`.local`),
  /// die privaten IPv4-Bereiche, der CGNAT-Bereich von Tailscale und private / link-local IPv6.
  static func acceptsSelfSigned(host: String) -> Bool {
    var normalizedHost = host.lowercased()
    // URL-Hosts können IPv6-Klammern und eine Zone-ID tragen („[fe80::1%en0]“).
    normalizedHost = normalizedHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if let zone = normalizedHost.firstIndex(of: "%") {
      normalizedHost = String(normalizedHost[..<zone])
    }

    if normalizedHost == "localhost" || normalizedHost.hasSuffix(".local") { return true }
    if normalizedHost.contains(":") { return isLocalIPv6(normalizedHost) }

    let octets = normalizedHost.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
    switch (octets[0], octets[1]) {
    case (127, _), (10, _): return true
    case (192, 168): return true
    case (172, 16...31): return true
    // 100.64.0.0/10 — Carrier-Grade-NAT, der Bereich, den Tailscale vergibt.
    case (100, 64...127): return true
    default: return false
    }
  }

  /// `::1`, Unique-Local `fc00::/7` (fc…, fd…) und Link-Local `fe80::/10` (fe8…–feb…).
  private static func isLocalIPv6(_ host: String) -> Bool {
    if host == "::1" { return true }
    let firstGroup =
      host.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    guard !firstGroup.isEmpty, let value = UInt16(firstGroup, radix: 16) else { return false }
    if value & 0xFE00 == 0xFC00 { return true }
    if value & 0xFFC0 == 0xFE80 { return true }
    return false
  }
}
