import CryptoKit
import Foundation

/// Account-Cache-Wurzel für weiterhin dateibasierte Subsysteme (Downloads, Cover, eBook-Lokaldaten) — liegen
/// außerhalb der SwiftData-Vollmigration. Pfadschema unverändert aus dem ehemaligen `LibraryDiskCache.accountDir`
/// übernommen, damit bestehende Downloads/Cover/eBooks nach Entfernen des JSON-Katalogcaches erreichbar bleiben.
enum AccountCacheDirectory {
  private static let fm = FileManager.default

  private static var baseDir: URL {
    let app = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return app.appendingPathComponent("ABStandLibraryCache", isDirectory: true)
  }

  /// Server-URL (+ optional User) — getrennte Caches pro Audiobookshelf-Nutzer auf demselben Host.
  static func accountDir(serverURL: String, userId: String? = nil) -> URL {
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
