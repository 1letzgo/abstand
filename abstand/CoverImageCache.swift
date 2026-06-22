import CryptoKit
import Foundation
import UIKit

/// Cover-Bilder unter `…/accounts/<sha>/covers/`; Dateiname = SHA256(itemId).
enum CoverImageCache {
  private static let fm = FileManager.default
  private static let subdir = "covers"
  private static let memory = NSCache<NSString, UIImage>()

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
    memory.setObject(image, forKey: itemId as NSString)
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
}
