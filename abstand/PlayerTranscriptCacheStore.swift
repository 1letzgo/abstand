import CryptoKit
import os
import Foundation

/// Persistiertes Transkript je Hörbuch-Track — Grundlage für den vorproduzierten Teleprompter.
///
/// Zeiten sind **lokale Track-Sekunden**, nicht globale Hörbuchzeit: Trackreihenfolge und
/// Kapitelversatz können sich serverseitig ändern, die Datei bleibt trotzdem gültig.
/// Abdeckung wird als Segmentliste geführt, weil beim ersten Einschalten typischerweise nur
/// ab der Abspielposition transkribiert wird und der Rest später dazukommt.
struct PlayerTranscriptTrackCache: Codable {
  static let currentVersion = 1

  struct Word: Codable {
    /// Kurze Schlüssel: eine Stunde Hörbuch sind ~9.000 Wörter pro Datei.
    let t: String
    let s: Double
    let e: Double
  }

  struct Segment: Codable {
    var start: Double
    var end: Double
    var words: [Word]
  }

  var version: Int
  var localeIdentifier: String
  var trackIndex: Int
  var segments: [Segment]

  init(localeIdentifier: String, trackIndex: Int, segments: [Segment] = []) {
    self.version = Self.currentVersion
    self.localeIdentifier = localeIdentifier
    self.trackIndex = trackIndex
    self.segments = segments
  }

  /// Ist `time` (lokale Track-Sekunde) bereits transkribiert?
  func covers(_ time: Double) -> Bool {
    segments.contains { $0.start - 0.5 <= time && time < $0.end }
  }

  /// Erste noch nicht abgedeckte Sekunde ab `time` — Startpunkt für den Producer.
  /// `nil`, wenn ab `time` alles bis `duration` vorliegt.
  func firstUncoveredTime(from time: Double, duration: Double) -> Double? {
    var cursor = max(0, time)
    // Segmente sind sortiert und überschneidungsfrei (siehe `merged`).
    for segment in segments where segment.end > cursor {
      if segment.start > cursor + 0.5 { return cursor }
      cursor = segment.end
    }
    guard duration <= 0 || cursor < duration - 1 else { return nil }
    return cursor
  }

  /// Segment einfügen und mit überlappenden/angrenzenden Segmenten verschmelzen.
  mutating func insert(segment: Segment) {
    guard !segment.words.isEmpty || segment.end > segment.start else { return }
    var merged: [Segment] = []
    var pending = segment
    for existing in segments.sorted(by: { $0.start < $1.start }) {
      if existing.end < pending.start - 0.5 {
        merged.append(existing)
        continue
      }
      if existing.start > pending.end + 0.5 {
        merged.append(existing)
        continue
      }
      // Überlappung: Wörter zusammenführen, doppelte Zeitbereiche verwerfen.
      var words = existing.words
      let existingEnd = existing.end
      words.append(contentsOf: pending.words.filter { $0.s >= existingEnd - 0.05 })
      let keptFromPending = pending.words.filter { $0.e <= existing.start + 0.05 }
      words.insert(contentsOf: keptFromPending, at: 0)
      pending = Segment(
        start: min(existing.start, pending.start),
        end: max(existing.end, pending.end),
        words: words.sorted { $0.s < $1.s }
      )
    }
    merged.append(pending)
    segments = merged.sorted { $0.start < $1.start }
  }

  var allWords: [Word] {
    segments.flatMap(\.words).sorted { $0.s < $1.s }
  }
}

/// Dateibasierter Speicher für Track-Transkripte unter dem Account-Cache.
/// Eigener Ordner `transcripts`, damit „Clear cache" ihn wie Cover/eBook-Daten mitnimmt.
enum PlayerTranscriptCacheStore {
  // `FileManager.default` ist für diese Datei-Operationen thread-safe (Strict Concurrency).
  nonisolated(unsafe) private static let fm = FileManager.default
  private static let subdir = "transcripts"

  /// Aktives Account-Verzeichnis — wie bei `EbookLocalStore` vom `AppModel` gesetzt, damit der
  /// Player-Controller den Cache ohne Kenntnis von Server-URL/User erreicht.
  @MainActor private(set) static var activeAccount: URL?

  @MainActor
  static func updateActiveAccount(_ account: URL?) {
    activeAccount = account
  }

  private static func bookDir(account: URL, bookId: String) -> URL {
    let digest = SHA256.hash(data: Data(bookId.utf8)).map { String(format: "%02x", $0) }.joined()
    let url = account.appendingPathComponent(subdir, isDirectory: true)
      .appendingPathComponent(digest, isDirectory: true)
    try? fm.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func fileURL(
    account: URL,
    bookId: String,
    trackIndex: Int,
    localeIdentifier: String
  ) -> URL {
    // Sprache im Dateinamen: ein Wechsel der Erkennungssprache liefert ein anderes Transkript
    // und darf das vorhandene nicht überschreiben.
    let locale = localeIdentifier.replacingOccurrences(of: "/", with: "_")
    return bookDir(account: account, bookId: bookId)
      .appendingPathComponent("t\(trackIndex)-\(locale).json")
  }

  static func load(
    account: URL?,
    bookId: String,
    trackIndex: Int,
    localeIdentifier: String
  ) -> PlayerTranscriptTrackCache? {
    guard let account, !bookId.isEmpty else { return nil }
    let url = fileURL(
      account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeIdentifier)
    guard let data = try? Data(contentsOf: url) else { return nil }
    do {
      let cache = try ABSJSON.decoder().decode(PlayerTranscriptTrackCache.self, from: data)
      guard cache.version == PlayerTranscriptTrackCache.currentVersion else {
        AppLog.playback.warning("transcript cache version mismatch — reproducing track")
        return nil
      }
      return cache
    } catch {
      // Korruptes File kostet Minuten Neuproduktion — das darf nicht spurlos passieren.
      AppLog.playback.warning(
        "transcript cache decode failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  static func save(
    _ cache: PlayerTranscriptTrackCache,
    account: URL?,
    bookId: String
  ) {
    guard let account, !bookId.isEmpty else { return }
    let url = fileURL(
      account: account,
      bookId: bookId,
      trackIndex: cache.trackIndex,
      localeIdentifier: cache.localeIdentifier
    )
    guard let data = try? ABSJSON.encoder().encode(cache) else {
      AppLog.playback.warning("transcript cache encode failed")
      return
    }
    do {
      try data.write(to: url, options: .atomic)
      var fileURL = url
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? fileURL.setResourceValues(values)
    } catch {
      AppLog.playback.warning(
        "transcript cache write failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Alle Transkripte eines Buchs entfernen (Download gelöscht, Sprache gewechselt).
  static func removeAll(account: URL?, bookId: String) {
    guard let account, !bookId.isEmpty else { return }
    try? fm.removeItem(at: bookDir(account: account, bookId: bookId))
  }

  /// Gesamtgröße aller Transkripte des Accounts (Einstellungen → Speicher).
  static func totalSizeBytes(account: URL?) -> Int64 {
    guard let account else { return 0 }
    let root = account.appendingPathComponent(subdir, isDirectory: true)
    guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total: Int64 = 0
    for case let url as URL in e {
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      total += Int64(size)
    }
    return total
  }
}
