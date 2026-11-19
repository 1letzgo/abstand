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
  // 2: Wortzeiten am PTS des ersten dekodierten Samples verankert, präzises VBR-Timing,
  // Mehrwort-Runs nach Zeichenzahl verteilt — ältere Transkripte waren zeitversetzt.
  // 3: nie veröffentlicht (nur ein Debug-Build): konnte nach einem Abbruch fälschlich „bis Track-Ende
  //    abgedeckt" eintragen und dabei einen vollständigen alten Stand ersetzen — wird verworfen.
  // 4: Wortanfänge nach Sprechpausen auf den akustischen Einsatz gelegt (`SpeechOnsetRefiner`),
  //    Läufe mit Vor-/Nachlauf an den Lückengrenzen (`PlayerTranscriptRunWindow`).
  static let currentVersion = 4
  /// Ältere, weiter lesbare Stände. Version 2 hat dieselbe Zeitbasis, nur unverfeinerte Anfänge:
  /// Die Anzeige korrigiert sie per `ReadAlongWordTiming`, bis der Track neu erzeugt ist. Das erste
  /// neu produzierte Segment ersetzt den ganzen alten Stand (`insert`) — ein Track ist immer
  /// entweder ganz alt oder ganz verfeinert. Version 3 fehlt hier absichtlich (gilt als „kein Transkript").
  static let readableLegacyVersions: Set<Int> = [2]

  /// Wortanfänge akustisch verfeinert? Sonst greift beim Anzeigen die Heuristik.
  var isOnsetRefined: Bool { version >= 4 }

  /// Ein alter Stand wird nur ersetzt, wenn das neue Segment in seinem Bereich mindestens diesen Anteil
  /// der alten Wörter mitbringt — sonst behauptete es Abdeckung, die es nicht hat (Abbruch, leeres
  /// „bis Track-Ende"-Segment). Erst ab `legacyReplacementMinimumWords` alten Wörtern im Bereich.
  static let legacyReplacementMinimumRatio = 0.5
  static let legacyReplacementMinimumWords = 10
  /// Doppelte an Segmentgrenzen: so weit vor dem Ende eines vorhandenen Segments dürfen Wörter eines
  /// angrenzenden neuen Laufs noch beginnen (Zeitversatz desselben Worts zwischen zwei Läufen).
  static let boundaryToleranceSeconds = 0.3

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

  /// Beginn des nächsten schon transkribierten Segments nach `time` — Endpunkt für den
  /// Producer, damit er nicht über bereits Vorhandenes hinweg erneut transkribiert.
  func nextCoveredStart(after time: Double) -> Double? {
    segments.map(\.start).filter { $0 > time + 0.5 }.min()
  }

  /// Segment einfügen und mit überlappenden/angrenzenden Segmenten verschmelzen.
  /// Sortiert wird nur, wenn die Reihenfolge nicht ohnehin stimmt (Normalfall: das neue Segment
  /// schließt hinten an) — das Ergebnis ist dasselbe wie mit stabiler Sortierung.
  /// `false`: nichts geändert (leeres Segment, oder ein alter Stand ginge dabei verloren).
  @discardableResult
  mutating func insert(segment: Segment) -> Bool {
    guard !segment.words.isEmpty || segment.end > segment.start else { return false }
    // Neue Segmente kommen immer verfeinert aus dem Producer. Ein alter Stand wird dabei verworfen
    // statt gemischt — sonst wüsste niemand mehr, welche Wörter die Anzeige-Heuristik brauchen.
    if version != Self.currentVersion {
      // Aber nie durch etwas, das in seinem Bereich viel weniger Wörter hat als der alte Stand: Das
      // behauptete Abdeckung, die es nicht gibt (Gerätefund: 217 Wörter „deckten" 14 h ab).
      guard Self.mayReplaceLegacy(segments, with: segment) else { return false }
      segments = []
      version = Self.currentVersion
    }
    var merged: [Segment] = []
    merged.reserveCapacity(segments.count + 1)
    var pending = segment
    let ordered = Self.isSorted(segments, by: \.start) ? segments : segments.sorted(by: { $0.start < $1.start })
    for existing in ordered {
      if existing.end < pending.start - 0.5 {
        merged.append(existing)
        continue
      }
      if existing.start > pending.end + 0.5 {
        merged.append(existing)
        continue
      }
      // Überlappung: im Bereich des vorhandenen Segments gewinnt es. Vom neuen nur Wörter, die davor
      // beginnen oder ab kurz vor seinem Ende — und keins, das ein vorhandenes Wort an der Grenze
      // doppelt (dasselbe Wort aus zwei Läufen liegt um einige Hundertstel versetzt).
      let tolerance = Self.boundaryToleranceSeconds
      let head = existing.words.prefix { $0.s < existing.start + Self.boundaryDuplicateWindowSeconds }
      let tail = existing.words.reversed().prefix { $0.e > existing.end - Self.boundaryDuplicateWindowSeconds }
      let before = pending.words.filter { word in
        word.s < existing.start && !head.contains { Self.isSameSpokenWord($0, word) }
      }
      let after = pending.words.filter { word in
        word.s >= existing.start && word.s >= existing.end - tolerance
          && !tail.contains { Self.isSameSpokenWord($0, word) }
      }
      let words = before + existing.words + after
      pending = Segment(
        start: min(existing.start, pending.start),
        end: max(existing.end, pending.end),
        words: Self.isSorted(words, by: \.s) ? words : words.sorted { $0.s < $1.s }
      )
    }
    merged.append(pending)
    segments = Self.isSorted(merged, by: \.start) ? merged : merged.sorted { $0.start < $1.start }
    return true
  }

  /// Nur Wörter so nah an einer Segmentgrenze können Doppelte eines angrenzenden Laufs sein.
  private static let boundaryDuplicateWindowSeconds = 2.0

  /// Darf `segment` einen alten Stand (`segments`) ersetzen? Nein, wenn es in seinem Bereich weniger als
  /// `legacyReplacementMinimumRatio` der dort vorhandenen alten Wörter mitbringt.
  static func mayReplaceLegacy(_ segments: [Segment], with segment: Segment) -> Bool {
    var legacyWords = 0
    for existing in segments where existing.end > segment.start && existing.start < segment.end {
      legacyWords += existing.words.lazy.filter { $0.s >= segment.start && $0.s < segment.end }.count
    }
    guard legacyWords >= legacyReplacementMinimumWords else { return true }
    return Double(segment.words.count) >= Double(legacyWords) * legacyReplacementMinimumRatio
  }

  /// Dasselbe gesprochene Wort aus zwei Läufen: Zeiten überlappen mindestens zur Hälfte des kürzeren
  /// (zeitlose Wörter: Anfänge höchstens 50 ms auseinander).
  static func isSameSpokenWord(_ a: Word, _ b: Word) -> Bool {
    let shorter = min(a.e - a.s, b.e - b.s)
    guard shorter > 0.02 else { return abs(a.s - b.s) < 0.05 }
    return min(a.e, b.e) - max(a.s, b.s) >= shorter * 0.5
  }

  var allWords: [Word] {
    let words = segments.flatMap(\.words)
    return Self.isSorted(words, by: \.s) ? words : words.sorted { $0.s < $1.s }
  }

  /// Aufsteigend (gleiche Werte erlaubt)? Dann ändert eine stabile Sortierung nichts.
  private static func isSorted<T>(_ items: [T], by key: KeyPath<T, Double>) -> Bool {
    guard items.count > 1 else { return true }
    for i in 1..<items.count where items[i][keyPath: key] < items[i - 1][keyPath: key] { return false }
    return true
  }
}

/// Lauf-Fenster für eine Transkript-Lücke `[gapStart, gapEnd)`. Ein Lauf, der mitten in der Sprache
/// beginnt, setzt sein erstes Wort auf den Laufstart; ein Lauf, der mitten in einem Wort endet, verliert
/// es. Deshalb füttert der Producer ab `preRollSeconds` vor der Lücke und bis `postRollSeconds` nach
/// ihrem Ende; übernommen werden nur Wörter, die in der Lücke beginnen (`keeps`) — der Vorlauf gehört
/// dem Segment davor, der Nachlauf dem danach. Das gespeicherte Segment beginnt bei `gapStart`, damit
/// die Abdeckung nie den Vorlauf mitbehauptet (sonst fände `firstUncoveredTime` immer dieselbe Lücke).
nonisolated struct PlayerTranscriptRunWindow: Sendable, Equatable {
  /// Am Mac gemessen (40 Startpunkte mitten in Wörtern, 8 echte Tracks): ohne Vorlauf stimmten nur 57 von
  /// 120 ersten Wörtern (±0,1 s), mit 2 s 115, 2,5 s 112, 3 s 119 — die Erkennung braucht Anlauf.
  static let preRollSeconds: Double = 3
  /// Muss nur länger sein als ein Wort: das Wort über dem Lückenende soll ganz gehört werden.
  static let postRollSeconds: Double = 2.5

  let gapStart: Double
  let gapEnd: Double?

  /// Lokale Track-Sekunde, ab der gefüttert wird (nie vor dem Track-Anfang).
  var runStart: Double { max(0, gapStart - Self.preRollSeconds) }
  /// Ende des Fütterns (`nil` = bis Dateiende).
  var runEnd: Double? { gapEnd.map { $0 + Self.postRollSeconds } }

  /// Wort mit diesem Anfang in die Lücke übernehmen? Wörter im Vorlauf (auch das am Laufstart
  /// klebende erste) gehören dem vorhandenen Segment davor, Wörter ab `gapEnd` dem danach.
  /// Die Toleranz deckt den Zeitversatz desselben Worts zwischen zwei Läufen; Doppelte räumt `insert`.
  func keeps(start: Double) -> Bool {
    guard start >= gapStart - PlayerTranscriptTrackCache.boundaryToleranceSeconds else { return false }
    if let gapEnd, start >= gapEnd { return false }
    return true
  }
}

/// Stempel einer Transkriptdatei (Größe + Änderungszeit): billige Gültigkeitsprüfung für Daten, die
/// aus ihr abgeleitet im Speicher liegen — ohne das JSON erneut zu dekodieren.
struct PlayerTranscriptFileStamp: Equatable, Sendable {
  let size: Int
  let modified: Date
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
    // Nur Pfad bauen — Ordner legen erst die Schreibpfade an (`ensureParentDirectory`),
    // sonst erzeugt jeder Lesezugriff leere Buch-Ordner.
    return account.appendingPathComponent(subdir, isDirectory: true)
      .appendingPathComponent(digest, isDirectory: true)
  }

  private static func ensureParentDirectory(of url: URL) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
      guard
        cache.version == PlayerTranscriptTrackCache.currentVersion
          || PlayerTranscriptTrackCache.readableLegacyVersions.contains(cache.version)
      else {
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

  /// Stempel der Transkriptdatei, `nil` wenn sie fehlt.
  static func transcriptStamp(
    account: URL?,
    bookId: String,
    trackIndex: Int,
    localeIdentifier: String
  ) -> PlayerTranscriptFileStamp? {
    guard let account, !bookId.isEmpty else { return nil }
    return stamp(
      of: fileURL(account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeIdentifier))
  }

  private static func stamp(of url: URL) -> PlayerTranscriptFileStamp? {
    guard let attributes = try? fm.attributesOfItem(atPath: url.path),
      let size = (attributes[.size] as? NSNumber)?.intValue,
      let modified = attributes[.modificationDate] as? Date
    else { return nil }
    return PlayerTranscriptFileStamp(size: size, modified: modified)
  }

  /// Wie `load`, plus Stempel der gelesenen Datei. Der Stempel wird vor dem Lesen genommen — ändert
  /// sich die Datei dazwischen, passt er beim nächsten Vergleich nicht mehr und es wird neu gelesen.
  static func loadStamped(
    account: URL?,
    bookId: String,
    trackIndex: Int,
    localeIdentifier: String
  ) -> (cache: PlayerTranscriptTrackCache, stamp: PlayerTranscriptFileStamp)? {
    guard
      let stamp = transcriptStamp(
        account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeIdentifier),
      let cache = load(
        account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeIdentifier)
    else { return nil }
    return (cache, stamp)
  }

  /// Gibt den Stempel der geschriebenen Datei zurück (`nil` bei Fehler).
  @discardableResult
  static func save(
    _ cache: PlayerTranscriptTrackCache,
    account: URL?,
    bookId: String
  ) -> PlayerTranscriptFileStamp? {
    guard let account, !bookId.isEmpty else { return nil }
    let url = fileURL(
      account: account,
      bookId: bookId,
      trackIndex: cache.trackIndex,
      localeIdentifier: cache.localeIdentifier
    )
    guard let data = try? ABSJSON.encoder().encode(cache) else {
      AppLog.playback.warning("transcript cache encode failed")
      return nil
    }
    ensureParentDirectory(of: url)
    do {
      try data.write(to: url, options: .atomic)
      var fileURL = url
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? fileURL.setResourceValues(values)
      return stamp(of: url)
    } catch {
      AppLog.playback.warning(
        "transcript cache write failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  // MARK: eBook-Abgleich

  /// Abgleich Transkript ↔ eBook (`EbookTrackAlignment`) liegt neben dem Transkript desselben Tracks —
  /// `removeAll` und „Clear cache" nehmen ihn dadurch automatisch mit.
  private static func alignmentFileURL(
    account: URL,
    bookId: String,
    trackIndex: Int,
    localeIdentifier: String
  ) -> URL {
    let locale = localeIdentifier.replacingOccurrences(of: "/", with: "_")
    return bookDir(account: account, bookId: bookId)
      .appendingPathComponent("a\(trackIndex)-\(locale).bin")
  }

  static func loadAlignment(
    account: URL?,
    bookId: String,
    trackIndex: Int,
    localeIdentifier: String
  ) -> Data? {
    guard let account, !bookId.isEmpty else { return nil }
    return try? Data(
      contentsOf: alignmentFileURL(
        account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeIdentifier))
  }

  static func saveAlignment(
    _ data: Data,
    account: URL?,
    bookId: String,
    trackIndex: Int,
    localeIdentifier: String
  ) {
    guard let account, !bookId.isEmpty else { return }
    var url = alignmentFileURL(
      account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeIdentifier)
    ensureParentDirectory(of: url)
    do {
      try data.write(to: url, options: .atomic)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
    } catch {
      AppLog.playback.warning(
        "ebook alignment write failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Alle Transkripte eines Buchs entfernen (Download gelöscht, Sprache gewechselt).
  static func removeAll(account: URL?, bookId: String) {
    guard let account, !bookId.isEmpty else { return }
    try? fm.removeItem(at: bookDir(account: account, bookId: bookId))
  }

  /// Gesamtgröße aller Transkripte des Accounts — vorgesehen für eine spätere
  /// Speicher-Anzeige in den Einstellungen (analog `CoverImageCache.totalByteCount`).
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
