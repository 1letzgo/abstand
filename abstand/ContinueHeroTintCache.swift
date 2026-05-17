import CryptoKit
import Foundation
import SwiftUI

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
