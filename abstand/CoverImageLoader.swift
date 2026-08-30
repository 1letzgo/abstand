import Foundation
import UIKit

/// Einziger Weg, ein Cover zu laden: Memory → Disk → Netzwerk, pro Cache-Key **einmal**.
///
/// Vorher hatte jede `CoverImageView` ihren eigenen Ladepfad; zwei Views mit demselben Key
/// (Continue-Karte und Listenzeile, oder View und Prefetcher) luden, dekodierten und schrieben
/// dasselbe Bild doppelt. Hier hängen sich alle Interessenten an denselben Task.
///
/// Zwei weitere Eigenschaften, die den View-Pfad vorher nicht hatte:
/// - **Decode off-main**: `UIImage(data:)` dekodiert erst beim Zeichnen, also auf dem Main Thread.
///   `byPreparingForDisplay()` erledigt das vorher im Hintergrund.
/// - **Negative-Cache**: Ein Item ohne Coverdatei antwortet mit 404. Ohne Merker ging bei jedem
///   Erscheinen der Zelle erneut ein Request raus, der garantiert nichts liefert.
actor CoverImageLoader {
  static let shared = CoverImageLoader()

  /// So lange gilt ein 404 als „kein Cover vorhanden“, bevor erneut gefragt wird.
  private static let missingRetryDelay: TimeInterval = 600

  private enum LoadOutcome {
    case image(UIImage)
    /// Server hat geantwortet, es gibt kein Cover (404/410) — merken.
    case missing
    /// Netzwerkfehler, Abbruch, kaputte Daten — nicht merken, beim nächsten Mal neu versuchen.
    case failed
  }

  private var inFlight: [String: Task<LoadOutcome, Never>] = [:]
  private var missingUntil: [String: Date] = [:]

  /// Bild für `key` besorgen. Mehrfachaufrufe während eines laufenden Ladevorgangs teilen sich
  /// dessen Ergebnis. Ein abbrechender Aufrufer beendet den Ladevorgang **nicht** — der Task ist
  /// bewusst unstrukturiert, damit ein weggescrolltes Cover trotzdem im Cache landet.
  func image(
    key: String,
    account: URL?,
    url: URL,
    token: String?
  ) async -> UIImage? {
    if let cached = CoverImageCache.memoryImage(itemId: key) { return cached }
    if let until = missingUntil[key] {
      if until > Date() { return nil }
      missingUntil.removeValue(forKey: key)
    }

    if let running = inFlight[key] {
      return image(from: await running.value)
    }

    let task = Task.detached(priority: .userInitiated) { () -> LoadOutcome in
      await Self.fetch(key: key, account: account, url: url, token: token)
    }
    inFlight[key] = task
    let outcome = await task.value
    inFlight.removeValue(forKey: key)
    if case .missing = outcome {
      missingUntil[key] = Date().addingTimeInterval(Self.missingRetryDelay)
    }
    return image(from: outcome)
  }

  private func image(from outcome: LoadOutcome) -> UIImage? {
    if case .image(let ui) = outcome { return ui }
    return nil
  }

  /// Merker zurücksetzen (Account-Wechsel, „Clear cache“, Pull-to-Refresh).
  func resetMissingCache() {
    missingUntil.removeAll()
  }

  /// Disk → Netzwerk. Läuft off-main; Decode inklusive.
  private static func fetch(
    key: String,
    account: URL?,
    url: URL,
    token: String?
  ) async -> LoadOutcome {
    if let account, let data = CoverImageCache.loadFromDisk(account: account, itemId: key),
      let ui = await decoded(data)
    {
      CoverImageCache.storeMemory(itemId: key, image: ui)
      return .image(ui)
    }

    let request = AbstandHTTPSession.authorizedRequest(url: url, token: token)
    do {
      let (data, response) = try await AbstandHTTPSession.coverAndCache.data(for: request)
      guard let http = response as? HTTPURLResponse else { return .failed }
      if http.statusCode == 404 || http.statusCode == 410 { return .missing }
      guard (200 ..< 300).contains(http.statusCode) else { return .failed }
      guard let ui = await decoded(data) else { return .failed }
      if let account {
        try? CoverImageCache.saveToDisk(account: account, itemId: key, data: data)
      }
      CoverImageCache.storeMemory(itemId: key, image: ui)
      return .image(ui)
    } catch {
      return .failed
    }
  }

  /// Dekodieren und fürs Zeichnen vorbereiten — sonst passiert der Decode im ersten Frame,
  /// der das Bild zeigt, und der liegt auf dem Main Thread.
  private static func decoded(_ data: Data) async -> UIImage? {
    guard let ui = UIImage(data: data) else { return nil }
    return await ui.byPreparingForDisplay() ?? ui
  }
}
