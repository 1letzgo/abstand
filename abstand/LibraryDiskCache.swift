import CryptoKit
import Foundation

/// Lokaler Cache (Application Support): Katalog-Seiten als Server-JSON, personalisierte Regale, Fortschritt.
enum LibraryDiskCache {
  private static let fm = FileManager.default

  private static var baseDir: URL {
    let app = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return app.appendingPathComponent("ABStandLibraryCache", isDirectory: true)
  }

  /// Nur Server-URL (normalisiert), damit der Ordner bei Token-Refresh stabil bleibt.
  static func accountDir(serverURL: String) -> URL {
    let digest = SHA256.hash(data: Data(serverURL.utf8))
    let id = digest.map { String(format: "%02x", $0) }.joined()
    let u = baseDir.appendingPathComponent("accounts", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }

  static func clearEverything() {
    try? fm.removeItem(at: baseDir)
  }

  private static func catalogSlug(filter: String?, sortField: String, ascending: Bool) -> String {
    let f = filter ?? ""
    let raw = "\(f)|\(sortField)|\(ascending)"
    let h = SHA256.hash(data: Data(raw.utf8))
    return h.map { String(format: "%02x", $0) }.joined()
  }

  private static func catalogFolder(
    account: URL, libraryId: String, filter: String?, sortField: String, ascending: Bool
  ) -> URL {
    let slug = catalogSlug(filter: filter, sortField: sortField, ascending: ascending)
    let u = account.appendingPathComponent("catalog", isDirectory: true)
      .appendingPathComponent(libraryId, isDirectory: true)
      .appendingPathComponent(slug, isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }

  /// Vor einem neuen Katalog-`reset`-Fetch: alte Seiten dieses Slugs entfernen.
  static func wipeCatalogSlug(
    account: URL, libraryId: String, filter: String?, sortField: String, ascending: Bool
  ) throws {
    let u = catalogFolder(account: account, libraryId: libraryId, filter: filter, sortField: sortField, ascending: ascending)
    if fm.fileExists(atPath: u.path) {
      try fm.removeItem(at: u)
    }
    try fm.createDirectory(at: u, withIntermediateDirectories: true)
  }

  static func saveCatalogPage(
    account: URL, libraryId: String, filter: String?, sortField: String, ascending: Bool, pageIndex: Int, data: Data
  ) throws {
    let dir = catalogFolder(account: account, libraryId: libraryId, filter: filter, sortField: sortField, ascending: ascending)
    let file = dir.appendingPathComponent("page_\(pageIndex).json")
    try data.write(to: file, options: .atomic)
  }

  static func loadMergedCatalog(
    account: URL,
    libraryId: String,
    filter: String?,
    sortField: String,
    ascending: Bool,
    decoder: JSONDecoder
  ) -> (books: [ABSBook], total: Int, nextPage: Int)? {
    let dir = catalogFolder(account: account, libraryId: libraryId, filter: filter, sortField: sortField, ascending: ascending)
    guard fm.fileExists(atPath: dir.path) else { return nil }
    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    let pageFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("page_") }
    guard !pageFiles.isEmpty else { return nil }

    func pageIndex(_ url: URL) -> Int {
      let base = url.deletingPathExtension().lastPathComponent
      let parts = base.split(separator: "_")
      return Int(parts.last ?? "0") ?? 0
    }
    let sorted = pageFiles.sorted { pageIndex($0) < pageIndex($1) }

    var all: [ABSBook] = []
    var total = 0
    for url in sorted {
      guard let data = try? Data(contentsOf: url) else { continue }
      guard let page = try? decoder.decode(ABSPage<ABSBook>.self, from: data) else { continue }
      total = page.total
      let filtered = page.results.filter { ($0.media.numTracks ?? 0) > 0 || (($0.media.duration ?? 0) > 0) }
      all.append(contentsOf: filtered)
    }
    if sorted.isEmpty { return nil }
    return (all, total, sorted.count)
  }

  static func savePersonalized(account: URL, libraryId: String, data: Data) throws {
    let dir = account.appendingPathComponent("personalized", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent("\(libraryId).json"), options: .atomic)
  }

  static func loadPersonalized(account: URL, libraryId: String) -> Data? {
    let u = account.appendingPathComponent("personalized", isDirectory: true).appendingPathComponent("\(libraryId).json")
    guard fm.fileExists(atPath: u.path) else { return nil }
    return try? Data(contentsOf: u)
  }

  static func saveProgress(account: URL, list: [ABSUserMediaProgress]) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(list)
    try data.write(to: account.appendingPathComponent("progress.json"), options: .atomic)
  }

  static func loadProgress(account: URL, decoder: JSONDecoder) -> [ABSUserMediaProgress]? {
    let u = account.appendingPathComponent("progress.json")
    guard let data = try? Data(contentsOf: u) else { return nil }
    return try? decoder.decode([ABSUserMediaProgress].self, from: data)
  }
}
