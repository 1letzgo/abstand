import CryptoKit
import Foundation
import UIKit

/// Cover-Bilder unter `…/accounts/<sha>/covers/`; Dateiname = SHA256(itemId).
enum CoverImageCache {
  private static let fm = FileManager.default
  private static let subdir = "covers"
  /// Kosten in dekodierten Bytes (nicht Dateigröße) — begrenzt reales Speicherwachstum bei langen Scroll-Sessions.
  private static let memory: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 300
    cache.totalCostLimit = 100 * 1024 * 1024
    return cache
  }()

  private static func coversDir(for account: URL) -> URL {
    let u = account.appendingPathComponent(subdir, isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }

  private static func fileURL(account: URL, itemId: String) -> URL {
    let h = SHA256.hash(data: Data(itemId.utf8))
    let name = h.map { String(format: "%02x", $0) }.joined() + ".img"
    return coversDir(for: account).appendingPathComponent(name)
  }

  static func memoryImage(itemId: String) -> UIImage? {
    memory.object(forKey: itemId as NSString)
  }

  /// Storage-Key für Memory-/Disk-Cache inkl. Revision — geteilt zwischen `CoverImageView` und Prefetch.
  static func cacheKey(scopeId: String, revision: Int) -> String {
    revision == 0 ? scopeId : "\(scopeId)#r\(revision)"
  }

  /// Memory first, then disk (and promotes disk hits into memory). Fully synchronous.
  static func syncUIImage(itemId: String, account: URL?) -> UIImage? {
    if let m = memoryImage(itemId: itemId) { return m }
    guard let account, let data = loadFromDisk(account: account, itemId: itemId),
      let ui = UIImage(data: data)
    else { return nil }
    storeMemory(itemId: itemId, image: ui)
    return ui
  }

  static func storeMemory(itemId: String, image: UIImage) {
    memory.setObject(image, forKey: itemId as NSString, cost: decodedByteCost(of: image))
  }

  /// Dekodierte Bildgröße (Breite × Höhe × Bytes/Pixel) statt Datei-/Encoded-Größe — reflektiert den
  /// tatsächlichen Speicherverbrauch im `NSCache`.
  private static func decodedByteCost(of image: UIImage) -> Int {
    guard let cg = image.cgImage else { return 0 }
    return cg.bytesPerRow * cg.height
  }

  static func loadFromDisk(account: URL, itemId: String) -> Data? {
    let u = fileURL(account: account, itemId: itemId)
    guard fm.fileExists(atPath: u.path) else { return nil }
    return try? Data(contentsOf: u)
  }

  static func saveToDisk(account: URL, itemId: String, data: Data) throws {
    let u = fileURL(account: account, itemId: itemId)
    try data.write(to: u, options: .atomic)
  }

  /// Hero-Coverbild holen: erst Memory/Disk-Cache, dann Netzwerk.
  /// Wird in beide Cache-Tiers geschrieben, sodass `CoverImageView` und die Tint-Extraktion
  /// denselben Bestand teilen — keine doppelten 1200px-Requests beim Öffnen einer Detail-Seite.
  /// `itemId` ist der vollständige Cache-Key (Scope-ID ggf. mit Revision, z. B. `id#cover-hero#r42`).
  static func loadHeroImage(
    itemId: String,
    account: URL?,
    coverURL: URL?,
    token: String
  ) async -> UIImage? {
    if let cached = syncUIImage(itemId: itemId, account: account) {
      return cached
    }
    guard let coverURL, !token.isEmpty else { return nil }
    var req = URLRequest(url: coverURL)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await AbstandHTTPSession.coverAndCache.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let image = UIImage(data: data)
      else { return nil }
      if let account {
        try? saveToDisk(account: account, itemId: itemId, data: data)
      }
      storeMemory(itemId: itemId, image: image)
      return image
    } catch {
      return nil
    }
  }

  /// In-Memory leeren (Account-Wechsel); Disk-Cache pro Server bleibt erhalten.
  static func evictMemory() {
    memory.removeAllObjects()
  }

  /// Entfernt alle Cover-Dateien für dieses Konto und leert den In-Memory-Cache.
  static func clearAll(account: URL) {
    memory.removeAllObjects()
    let dir = coversDir(for: account)
    try? fm.removeItem(at: dir)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  static func totalByteCount(account: URL) -> Int64 {
    let dir = account.appendingPathComponent(subdir, isDirectory: true)
    guard fm.fileExists(atPath: dir.path),
      let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
    else { return 0 }
    var sum: Int64 = 0
    for u in urls {
      let n = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
      sum += n
    }
    return sum
  }

  /// Ohne Eviction wachsen alte Sort-/Filter-Slugs und verwaiste Revision-Dateien (nach Cover-Wechsel)
  /// unbegrenzt. Grobe LRU/TTL-Bereinigung statt echtem Delta-Sync: alles über `maxAgeDays` seit dem
  /// letzten Zugriff (`contentAccessDateKey`) fliegt raus; danach älteste Dateien, bis `maxTotalBytes`
  /// unterschritten ist. Günstig genug für einen periodischen Hintergrund-Sweep, kein Live-Pfad.
  static func pruneStaleEntries(
    account: URL,
    maxAgeDays: Int = 45,
    maxTotalBytes: Int64 = 200 * 1024 * 1024
  ) {
    let dir = coversDir(for: account)
    guard
      let urls = try? fm.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey])
    else { return }

    let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
    var survivors: [(url: URL, size: Int64, lastUsed: Date)] = []
    survivors.reserveCapacity(urls.count)

    for u in urls {
      let values = try? u.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey])
      let size = Int64(values?.fileSize ?? 0)
      let lastUsed = values?.contentAccessDate ?? values?.contentModificationDate ?? .distantPast
      if lastUsed < cutoff {
        try? fm.removeItem(at: u)
        continue
      }
      survivors.append((u, size, lastUsed))
    }

    var totalBytes = survivors.reduce(0) { $0 + $1.size }
    guard totalBytes > maxTotalBytes else { return }
    for entry in survivors.sorted(by: { $0.lastUsed < $1.lastUsed }) {
      guard totalBytes > maxTotalBytes else { break }
      try? fm.removeItem(at: entry.url)
      totalBytes -= entry.size
    }
  }
}
