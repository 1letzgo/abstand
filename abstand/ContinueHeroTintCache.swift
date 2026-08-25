import CryptoKit
import Foundation
import SwiftUI
import UIKit

/// Roher Cover-Durchschnitts-RGB für Continue-Listening-Karten — Formel
/// (`continueListeningCardTint`) wird palette-abhängig beim Lesen angewandt.
/// Neuer Ordner `heroTintAvg`: alte gemischte `heroTints`-Caches werden ignoriert.
enum ContinueHeroTintCache {
  private static let fm = FileManager.default
  private static let subdir = "heroTintAvg"

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

  /// `revision`: wie bei `CoverImageView`/`CoverImageCache` optional aus `updatedAt` abgeleitet —
  /// ändert sich das Cover am Server, verfällt die daraus abgeleitete Tönung automatisch mit,
  /// statt bis zum nächsten manuellen „Clear cache" stale zu bleiben.
  private static func cacheKey(itemId: String, revision: Int) -> String {
    revision == 0 ? itemId : "\(itemId)#r\(revision)"
  }

  static func loadRGB(
    account: URL?,
    itemId: String,
    revision: Int = 0
  ) -> (r: Double, g: Double, b: Double)? {
    guard let account else { return nil }
    let u = fileURL(account: account, itemId: cacheKey(itemId: itemId, revision: revision))
    guard fm.fileExists(atPath: u.path),
      let data = try? Data(contentsOf: u),
      let p = try? ABSJSON.decoder().decode(Payload.self, from: data)
    else { return nil }
    return (p.r, p.g, p.b)
  }

  static func load(account: URL?, itemId: String, revision: Int = 0) -> Color? {
    guard let rgb = loadRGB(account: account, itemId: itemId, revision: revision) else { return nil }
    return continueListeningCardTint(
      fromAverageRed: CGFloat(rgb.r),
      green: CGFloat(rgb.g),
      blue: CGFloat(rgb.b)
    )
  }

  static func save(account: URL, itemId: String, revision: Int = 0, red: Double, green: Double, blue: Double) {
    let p = Payload(r: red, g: green, b: blue)
    guard let data = try? ABSJSON.encoder().encode(p) else { return }
    let u = fileURL(account: account, itemId: cacheKey(itemId: itemId, revision: revision))
    try? data.write(to: u, options: .atomic)
  }

  static func clearAll(account: URL) {
    let d = dir(account: account)
    try? fm.removeItem(at: d)
    try? fm.createDirectory(at: d, withIntermediateDirectories: true)
  }
}

/// Roher Cover-Durchschnitts-RGB pro Item (Buch-/Folgen-Detail) — bewusst NICHT die fertige
/// Tint-Farbe: `coverDominantBackgroundTint` rechnet palette-abhängig (Dark/Light), der
/// Durchschnitts-RGB ist dagegen stabil und wird beim Seed mit der aktuellen Palette verrechnet.
/// Beim ersten Detail-Aufruf geschrieben, beim zweiten sofort da (kein Cover-Fetch/CIAreaAverage).
enum DetailCoverAverageRGBCache {
  private static let fm = FileManager.default
  private static let subdir = "detailCoverAvgRGB"

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

  static func load(account: URL?, itemId: String) -> (r: Double, g: Double, b: Double)? {
    guard let account else { return nil }
    let u = fileURL(account: account, itemId: itemId)
    guard fm.fileExists(atPath: u.path),
      let data = try? Data(contentsOf: u),
      let p = try? ABSJSON.decoder().decode(Payload.self, from: data)
    else { return nil }
    return (p.r, p.g, p.b)
  }

  static func save(account: URL?, itemId: String, red: Double, green: Double, blue: Double) {
    guard let account else { return }
    let p = Payload(r: red, g: green, b: blue)
    guard let data = try? ABSJSON.encoder().encode(p) else { return }
    let u = fileURL(account: account, itemId: itemId)
    try? data.write(to: u, options: .atomic)
  }

  static func clearAll(account: URL) {
    let d = dir(account: account)
    try? fm.removeItem(at: d)
    try? fm.createDirectory(at: d, withIntermediateDirectories: true)
  }
}

/// Synchroner Seed für dieselbe palette-abhängige Hintergrundtönung in Detail- und Player-Views.
/// Die Daten liegen bereits lokal vor; dadurch muss die UI nicht erst mit dem neutralen
/// Hintergrund erscheinen und nach dem ersten Frame auf die Cover-Farbe wechseln.
enum CoverDominantTintSeed {
  struct Value {
    let tint: Color
    let image: UIImage?
    let averageRGB: (r: Double, g: Double, b: Double)?
  }

  static func resolve(
    account: URL?,
    itemId: String,
    heroScopeId: String,
    fallbackScopeId: String? = nil,
    revision: Int = 0
  ) -> Value? {
    if let rgb = DetailCoverAverageRGBCache.load(account: account, itemId: itemId) {
      return Value(
        tint: coverDominantBackgroundTint(
          fromAverageRed: rgb.r, green: rgb.g, blue: rgb.b),
        image: nil,
        averageRGB: rgb
      )
    }

    let heroCacheKey = CoverImageCache.cacheKey(scopeId: heroScopeId, revision: revision)
    let fallbackCacheKey = fallbackScopeId.map {
      CoverImageCache.cacheKey(scopeId: $0, revision: revision)
    }
    let image =
      CoverImageCache.syncUIImage(itemId: heroCacheKey, account: account)
      ?? fallbackCacheKey.flatMap { CoverImageCache.syncUIImage(itemId: $0, account: account) }
    guard let image else { return nil }
    let averageRGB = coverAverageRGB(from: image).map {
      (r: Double($0.0), g: Double($0.1), b: Double($0.2))
    }
    return Value(
      tint: coverDominantBackgroundTint(from: image),
      image: image,
      averageRGB: averageRGB
    )
  }
}

/// Cover → Kartenfarbe (Cache, lokales Cover, optional Netz) für Continue-Hero und Home-Mini-Karten.
/// Achtung Main-Thread: `syncUIImage` (Disk-Read) und `coverAverageRGB` (Pixel-Analyse, Hero-Größe)
/// sind teuer — beides läuft bewusst in `Task.detached`, nicht auf dem MainActor (Launch-Jank).
/// Die sync aufrufbaren Seeds (View-`init`) beschränken sich auf die winzigen Tint-JSONs.
@MainActor
enum CoverDerivedTintLoader {
  /// Disk-Tint zuerst; sonst Cover aus Memory/Disk (Scope inkl. Hero); erst dann Netz.
  /// Schreibt Netz-Treffer in `CoverImageCache`, damit `CoverImageView` denselben Key nutzt.
  static func loadColor(
    account: URL?,
    itemId: String,
    cacheScopeId: String? = nil,
    revision: Int = 0,
    coverURL: URL?,
    token: String
  ) async -> Color? {
    if let c = colorFromDiskOrCoverCache(
      account: account, itemId: itemId, cacheScopeId: cacheScopeId, revision: revision)
    {
      return c
    }
    return await colorFromNetwork(
      account: account,
      itemId: itemId,
      cacheScopeId: cacheScopeId,
      revision: revision,
      coverURL: coverURL,
      token: token
    )
  }

  /// Billiger Sync-Pfad (View-`init`-Seeds): nur persistierte Tint-JSON lesen — kleine Datei,
  /// kein Bild-I/O, keine Pixel-Analyse. Bild-basierte Ableitung läuft über `loadColor`/`colorFromNetwork`.
  static func colorFromDiskOrCoverCache(
    account: URL?,
    itemId: String,
    cacheScopeId: String? = nil,
    revision: Int = 0
  ) -> Color? {
    ContinueHeroTintCache.load(account: account, itemId: itemId, revision: revision)
  }

  static func colorFromNetwork(
    account: URL?,
    itemId: String,
    cacheScopeId: String? = nil,
    revision: Int = 0,
    coverURL: URL?,
    token: String
  ) async -> Color? {
    // Liegt das Cover schon lokal (Memory/Disk, Scope inkl. Hero/Thumbnail)? → Farbe off-main ableiten.
    if let c = await colorFromLocalImage(
      account: account, itemId: itemId, cacheScopeId: cacheScopeId, revision: revision)
    {
      return c
    }
    guard let coverURL else { return nil }
    let req = AbstandHTTPSession.authorizedRequest(url: coverURL, token: token)
    let payload: (data: Data, response: URLResponse)?
    do {
      payload = try await AbstandHTTPSession.coverAndCache.data(for: req)
    } catch {
      return nil
    }
    guard let (data, resp) = payload else { return nil }
    let cacheKey = CoverImageCache.cacheKey(scopeId: cacheScopeId ?? itemId, revision: revision)
    // Decode + Pixel-Analyse + Persistenz off-main — dieselben Bytes wie `CoverImageView` speichern,
    // damit es beim nächsten Öffnen denselben Key trifft (kein zweiter Download).
    return await Task.detached(priority: .userInitiated) { () -> Color? in
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let image = UIImage(data: data),
        let avg = coverAverageRGB(from: image)
      else { return nil }
      if let account {
        try? CoverImageCache.saveToDisk(account: account, itemId: cacheKey, data: data)
        CoverImageCache.storeMemory(itemId: cacheKey, image: image)
        ContinueHeroTintCache.save(
          account: account,
          itemId: itemId,
          revision: revision,
          red: Double(avg.0),
          green: Double(avg.1),
          blue: Double(avg.2)
        )
      }
      return continueListeningCardTint(fromAverageRed: avg.0, green: avg.1, blue: avg.2)
    }.value
  }

  /// Lokales Bild (Memory/Disk) → Farbe. Schwerer Teil (Disk-Read, Decode, `coverAverageRGB`)
  /// läuft off-main; nur das Ergebnis kommt zurück auf den MainActor.
  private static func colorFromLocalImage(
    account: URL?,
    itemId: String,
    cacheScopeId: String?,
    revision: Int
  ) async -> Color? {
    guard let account else { return nil }
    let primaryKey = CoverImageCache.cacheKey(scopeId: cacheScopeId ?? itemId, revision: revision)
    let thumbnailKey = CoverImageCache.cacheKey(scopeId: itemId, revision: revision)
    return await Task.detached(priority: .userInitiated) { () -> Color? in
      let img =
        CoverImageCache.syncUIImage(itemId: primaryKey, account: account)
        ?? (primaryKey != thumbnailKey
          ? CoverImageCache.syncUIImage(itemId: thumbnailKey, account: account) : nil)
      guard let img, let avg = coverAverageRGB(from: img) else { return nil }
      ContinueHeroTintCache.save(
        account: account,
        itemId: itemId,
        revision: revision,
        red: Double(avg.0),
        green: Double(avg.1),
        blue: Double(avg.2)
      )
      return continueListeningCardTint(fromAverageRed: avg.0, green: avg.1, blue: avg.2)
    }.value
  }
}
