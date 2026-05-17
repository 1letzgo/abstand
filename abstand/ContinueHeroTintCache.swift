import CryptoKit
import Foundation
import SwiftUI
import UIKit

/// Gespeicherte Cover-abgeleitete Hero-Karten-Hintergrundfarbe (`PlaybackController.coverBarTintRGB`),
/// pro `itemId` unter dem Account-Ordner — erscheint sofort beim nächsten Start, ohne erneutes Cover-Fetch.
enum ContinueHeroTintCache {
  private static let fm = FileManager.default
  private static let subdir = "heroTints"

  private struct Payload: Codable {
    var r: Double
    var g: Double
    var b: Double
  }

  private static func dir(account: URL) -> URL {
    let u = account.appendingPathComponent(subdir, isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }

  private static func fileURL(account: URL, itemId: String) -> URL {
    let h = SHA256.hash(data: Data(itemId.utf8))
    let name = h.map { String(format: "%02x", $0) }.joined() + ".json"
    return dir(account: account).appendingPathComponent(name)
  }

  static func load(account: URL?, itemId: String) -> Color? {
    guard let account else { return nil }
    let u = fileURL(account: account, itemId: itemId)
    guard fm.fileExists(atPath: u.path),
      let data = try? Data(contentsOf: u),
      let p = try? JSONDecoder().decode(Payload.self, from: data)
    else { return nil }
    return Color(red: p.r, green: p.g, blue: p.b)
  }

  static func save(account: URL, itemId: String, red: Double, green: Double, blue: Double) {
    let p = Payload(r: red, g: green, b: blue)
    guard let data = try? JSONEncoder().encode(p) else { return }
    let u = fileURL(account: account, itemId: itemId)
    try? data.write(to: u, options: .atomic)
  }

  static func clearAll(account: URL) {
    let d = dir(account: account)
    try? fm.removeItem(at: d)
    try? fm.createDirectory(at: d, withIntermediateDirectories: true)
  }
}

/// Cover → Kartenfarbe (Cache, lokales Cover, optional Netz) für Continue-Hero und Home-Mini-Karten.
@MainActor
enum CoverDerivedTintLoader {
  static func colorFromDiskOrCoverCache(account: URL?, itemId: String) -> Color? {
    if let c = ContinueHeroTintCache.load(account: account, itemId: itemId) { return c }
    guard let account,
      let img = CoverImageCache.syncUIImage(itemId: itemId, account: account),
      let rgb = PlaybackController.coverBarTintRGB(from: img)
    else { return nil }
    ContinueHeroTintCache.save(account: account, itemId: itemId, red: rgb.0, green: rgb.1, blue: rgb.2)
    return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
  }

  static func colorFromNetwork(account: URL?, itemId: String, coverURL: URL?, token: String) async
    -> Color?
  {
    if CoverImageCache.syncUIImage(itemId: itemId, account: account) != nil { return nil }
    guard let coverURL else { return nil }
    var req = URLRequest(url: coverURL)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let image = UIImage(data: data),
        let rgb = PlaybackController.coverBarTintRGB(from: image)
      else { return nil }
      if let account {
        ContinueHeroTintCache.save(account: account, itemId: itemId, red: rgb.0, green: rgb.1, blue: rgb.2)
      }
      return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    } catch {
      return nil
    }
  }
}
