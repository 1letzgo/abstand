import CryptoKit
import Foundation

/// Account-Cache-Wurzel für weiterhin dateibasierte Subsysteme (Downloads, Cover, eBook-Lokaldaten) — liegen
/// außerhalb der SwiftData-Vollmigration. Pfadschema unverändert aus dem früheren JSON-Katalog-Cache
/// übernommen, damit bestehende Downloads/Cover/eBooks nach Entfernen des JSON-Katalogcaches erreichbar bleiben.
enum AccountCacheDirectory {
  // `FileManager.default` ist für diese Datei-Operationen thread-safe (Strict Concurrency).
  nonisolated(unsafe) private static let fm = FileManager.default

  private static var baseDir: URL {
    let app = URL.applicationSupportDirectory
    return app.appendingPathComponent("ABStandLibraryCache", isDirectory: true)
  }

  /// Ergebnis je (Server, User) — die Funktion läuft u. a. in View-`body`s (Cover-Cache-Pfade je Karte);
  /// ungecacht kostete jeder Aufruf zwei SHA256 + zwei `createDirectory`-Syscalls. Account-Verzeichnisse
  /// werden nie als Ganzes gelöscht, der Cache kann also nicht auf ein fehlendes Verzeichnis zeigen.
  private static let memoLock = NSLock()
  nonisolated(unsafe) private static var memo: [String: URL] = [:]

  /// Server-URL (+ optional User) — getrennte Caches pro Audiobookshelf-Nutzer auf demselben Host.
  static func accountDir(serverURL: String, userId: String? = nil) -> URL {
    let key = serverURL + "\u{0}" + (userId ?? "")
    if let cached = memoLock.withLock({ memo[key] }) { return cached }
    let url = computeAccountDir(serverURL: serverURL, userId: userId)
    memoLock.withLock { memo[key] = url }
    return url
  }

  private static func computeAccountDir(serverURL: String, userId: String?) -> URL {
    let digest = SHA256.hash(data: Data(serverURL.utf8))
    let id = digest.map { String(format: "%02x", $0) }.joined()
    let serverRoot = baseDir.appendingPathComponent("accounts", isDirectory: true)
      .appendingPathComponent(id, isDirectory: true)
    try? fm.createDirectory(at: serverRoot, withIntermediateDirectories: true)

    let trimmedUser = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmedUser.isEmpty else { return serverRoot }

    let userDigest = SHA256.hash(data: Data(trimmedUser.utf8))
    let userIdComponent = userDigest.map { String(format: "%02x", $0) }.joined()
    let userRoot = serverRoot.appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(userIdComponent, isDirectory: true)
    try? fm.createDirectory(at: userRoot, withIntermediateDirectories: true)
    return userRoot
  }
}
