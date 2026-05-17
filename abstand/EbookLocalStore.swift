import Foundation
import ReadiumShared

enum EpubReaderTheme: String, CaseIterable {
  case light
  case dark
}

/// Leseeinstellungen (global, UserDefaults).
enum EpubReaderSettings {
  /// Readium-Schriftgröße als Faktor (1.0 = 100 %, Standard).
  private static let fontScaleKey = "abstand_epub_font_scale"
  private static let legacyFontSizeKey = "abstand_epub_font_size"
  private static let themeKey = "abstand_epub_reader_theme"

  static let defaultFontSize: Double = 1.0
  static let minFontSize: Double = 0.7
  static let maxFontSize: Double = 1.8
  static let fontSizeStep: Double = 0.1

  static func loadTheme() -> EpubReaderTheme {
    EpubReaderTheme(rawValue: UserDefaults.standard.string(forKey: themeKey) ?? "") ?? .light
  }

  static func saveTheme(_ theme: EpubReaderTheme) {
    UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
  }

  static func loadFontSize() -> Double {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: fontScaleKey) != nil {
      let v = defaults.double(forKey: fontScaleKey)
      if v >= minFontSize, v <= maxFontSize { return v }
      return defaultFontSize
    }
    // Alte Pixel-Werte (24–48) aus WKWebView-Reader → Readium-Standard.
    if defaults.object(forKey: legacyFontSizeKey) != nil {
      resetFontSizeToDefault()
      return defaultFontSize
    }
    return defaultFontSize
  }

  static func saveFontSize(_ size: Double) {
    let clamped = min(maxFontSize, max(minFontSize, size))
    UserDefaults.standard.set(clamped, forKey: fontScaleKey)
    UserDefaults.standard.removeObject(forKey: legacyFontSizeKey)
  }

  static func resetFontSizeToDefault() {
    UserDefaults.standard.set(defaultFontSize, forKey: fontScaleKey)
    UserDefaults.standard.removeObject(forKey: legacyFontSizeKey)
  }
}

enum ABSEbookFormat: String, Codable, CaseIterable {
  case epub
  case pdf

  var fileExtension: String { rawValue }

  static func resolve(format: String?, ext: String?, filename: String?) -> ABSEbookFormat? {
    let f = (format ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if f == "epub" || f.contains("epub") { return .epub }
    if f == "pdf" || f.contains("pdf") { return .pdf }
    let e = (ext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if e == ".epub" || e == "epub" { return .epub }
    if e == ".pdf" || e == "pdf" { return .pdf }
    let name = (filename ?? "").lowercased()
    if name.hasSuffix(".epub") { return .epub }
    if name.hasSuffix(".pdf") { return .pdf }
    return nil
  }
}

extension EbookLocalStore {
  private static func knownFormatKey(libraryItemId: String) -> String {
    "abstand_ebook_fmt_\(libraryItemId)"
  }

  static func rememberKnownFormat(_ format: ABSEbookFormat, libraryItemId: String) {
    UserDefaults.standard.set(format.rawValue, forKey: knownFormatKey(libraryItemId: libraryItemId))
  }

  static func knownFormat(libraryItemId: String) -> ABSEbookFormat? {
    guard let raw = UserDefaults.standard.string(forKey: knownFormatKey(libraryItemId: libraryItemId)) else {
      return nil
    }
    return ABSEbookFormat(rawValue: raw)
  }
}

/// Metadaten zu einer lokal gecachten E-Book-Datei (für Offline-Wiederverwendung).
struct EbookDownloadMeta: Codable {
  let libraryItemId: String
  let ino: String
  let format: ABSEbookFormat
  let title: String?
}

/// Lokale E-Book-Dateien (EPUB/PDF) pro Account.
enum EbookLocalStore {
  private static let fm = FileManager.default

  private static func metaURL(account: URL, libraryItemId: String, format: ABSEbookFormat) -> URL {
    account
      .appendingPathComponent("ebooks", isDirectory: true)
      .appendingPathComponent("\(libraryItemId).\(format.fileExtension).meta.json", isDirectory: false)
  }

  static func ebookFileURL(account: URL, libraryItemId: String, format: ABSEbookFormat) -> URL {
    account
      .appendingPathComponent("ebooks", isDirectory: true)
      .appendingPathComponent("\(libraryItemId).\(format.fileExtension)", isDirectory: false)
  }

  static func hasCachedEbook(account: URL?, libraryItemId: String, format: ABSEbookFormat) -> Bool {
    guard let account else { return false }
    return fm.fileExists(atPath: ebookFileURL(account: account, libraryItemId: libraryItemId, format: format).path)
  }

  /// Bereits heruntergeladene Datei (EPUB vor PDF).
  static func cachedEbookIfPresent(account: URL?, libraryItemId: String) -> (url: URL, format: ABSEbookFormat)? {
    guard let account else { return nil }
    for format in ABSEbookFormat.allCases {
      let url = ebookFileURL(account: account, libraryItemId: libraryItemId, format: format)
      if fm.fileExists(atPath: url.path) {
        return (url, format)
      }
    }
    return nil
  }

  static func saveDownloadMeta(account: URL, meta: EbookDownloadMeta) throws {
    try ensureAccountDirs(account: account)
    let data = try ABSJSON.encoder().encode(meta)
    try data.write(to: metaURL(account: account, libraryItemId: meta.libraryItemId, format: meta.format), options: .atomic)
  }

  static func loadDownloadMeta(account: URL, libraryItemId: String, format: ABSEbookFormat) -> EbookDownloadMeta? {
    let url = metaURL(account: account, libraryItemId: libraryItemId, format: format)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? ABSJSON.decoder().decode(EbookDownloadMeta.self, from: data)
  }

  static func ensureAccountDirs(account: URL) throws {
    try fm.createDirectory(
      at: account.appendingPathComponent("ebooks", isDirectory: true),
      withIntermediateDirectories: true)
  }

  private static func locatorKey(libraryItemId: String, format: ABSEbookFormat) -> String {
    "abstand_readium_loc_\(format.rawValue)_\(libraryItemId)"
  }

  static func loadReadiumLocator(libraryItemId: String, format: ABSEbookFormat) -> Locator? {
    guard let json = UserDefaults.standard.string(forKey: locatorKey(libraryItemId: libraryItemId, format: format)) else {
      return nil
    }
    return try? Locator(jsonString: json)
  }

  static func saveReadiumLocator(_ locator: Locator, libraryItemId: String, format: ABSEbookFormat) {
    guard let json = try? locator.jsonString() else { return }
    UserDefaults.standard.set(json, forKey: locatorKey(libraryItemId: libraryItemId, format: format))
  }

  static func clearReadiumLocator(libraryItemId: String, format: ABSEbookFormat) {
    UserDefaults.standard.removeObject(forKey: locatorKey(libraryItemId: libraryItemId, format: format))
    clearPageProgress(libraryItemId: libraryItemId, format: format)
  }

  private static func pageProgressKey(libraryItemId: String, format: ABSEbookFormat) -> String {
    "abstand_readium_pages_\(format.rawValue)_\(libraryItemId)"
  }

  static func savePageProgress(
    current: Int, total: Int, libraryItemId: String, format: ABSEbookFormat
  ) {
    let totalClamped = max(1, total)
    let currentClamped = min(totalClamped, max(1, current))
    let payload: [String: Int] = ["current": currentClamped, "total": totalClamped]
    UserDefaults.standard.set(payload, forKey: pageProgressKey(libraryItemId: libraryItemId, format: format))
  }

  static func loadPageProgress(libraryItemId: String, format: ABSEbookFormat) -> (current: Int, total: Int)? {
    guard let dict = UserDefaults.standard.dictionary(
      forKey: pageProgressKey(libraryItemId: libraryItemId, format: format)
    ) as? [String: Int],
      let total = dict["total"], total > 0,
      let current = dict["current"]
    else { return nil }
    return (min(total, max(1, current)), total)
  }

  static func clearPageProgress(libraryItemId: String, format: ABSEbookFormat) {
    UserDefaults.standard.removeObject(forKey: pageProgressKey(libraryItemId: libraryItemId, format: format))
  }

  /// Lesefortschritt 0…1, nil wenn kein Locator oder noch am Anfang.
  static func readProgressFraction(libraryItemId: String, format: ABSEbookFormat) -> Double? {
    guard let locator = loadReadiumLocator(libraryItemId: libraryItemId, format: format) else { return nil }
    let f = ReadiumReaderProgressInfo.fraction(from: locator)
    guard f.isFinite, f > 0.005 else { return nil }
    return min(1, max(0, f))
  }

  static func isInProgressReading(libraryItemId: String, format: ABSEbookFormat) -> Bool {
    guard let f = readProgressFraction(libraryItemId: libraryItemId, format: format) else { return false }
    return f < 0.995
  }

  /// Alle lokal gespeicherten, nicht abgeschlossenen Lesezeichen (unabhängig vom Katalog-Cache).
  static func inProgressReadingRefs() -> [(libraryItemId: String, format: ABSEbookFormat)] {
    let prefix = "abstand_readium_loc_"
    var refs: [(String, ABSEbookFormat)] = []
    for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
      let suffix = String(key.dropFirst(prefix.count))
      for fmt in ABSEbookFormat.allCases {
        let mid = "\(fmt.rawValue)_"
        guard suffix.hasPrefix(mid) else { continue }
        let itemId = String(suffix.dropFirst(mid.count))
        guard !itemId.isEmpty, isInProgressReading(libraryItemId: itemId, format: fmt) else { continue }
        refs.append((itemId, fmt))
        break
      }
    }
    return refs
  }
}

// MARK: - Lesefortschritt (Home / eBooks-Tab)

/// Seitenanzeige für eBook-Listenkarten (Cover + Metadatenzeile).
struct EbookPageDisplayInfo {
  let current: Int?
  let total: Int

  var coverLabel: String {
    if let current, current > 0 { return "\(current)/\(total)" }
    return "\(total)"
  }

  var metadataLabel: String {
    if let current, current > 0 { return "Page \(current) of \(total)" }
    return "\(total) pages"
  }
}

extension ABSBook {
  private func primaryEbookFormatForProgress() -> ABSEbookFormat? {
    if let ef = readableAttachedEbook?.format { return ef }
    if let fmt = attachedEbookFormats.first { return fmt }
    return EbookLocalStore.knownFormat(libraryItemId: id)
  }

  /// Gespeicherte Seitenzahl (nach Lesen im Reader); nil wenn noch keine Paginierung bekannt.
  func ebookPageDisplayInfo() -> EbookPageDisplayInfo? {
    var formats = attachedEbookFormats
    if let known = EbookLocalStore.knownFormat(libraryItemId: id) { formats.insert(known) }
    if formats.isEmpty, let primary = primaryEbookFormatForProgress() { formats.insert(primary) }

    for fmt in formats {
      guard let saved = EbookLocalStore.loadPageProgress(libraryItemId: id, format: fmt) else { continue }
      let inProgress = EbookLocalStore.isInProgressReading(libraryItemId: id, format: fmt)
      let current: Int? = inProgress ? saved.current : nil
      return EbookPageDisplayInfo(current: current, total: saved.total)
    }
    return nil
  }
  /// Lokaler Readium-Fortschritt (0…1), nil wenn noch nicht begonnen.
  func ebookReadProgressFraction() -> Double? {
    if let ef = readableAttachedEbook?.format,
      let f = EbookLocalStore.readProgressFraction(libraryItemId: id, format: ef)
    {
      return f
    }
    for fmt in attachedEbookFormats {
      if let f = EbookLocalStore.readProgressFraction(libraryItemId: id, format: fmt) { return f }
    }
    if let known = EbookLocalStore.knownFormat(libraryItemId: id),
      let f = EbookLocalStore.readProgressFraction(libraryItemId: id, format: known)
    {
      return f
    }
    return nil
  }

  /// Für Home-Regal „Continue reading“: angefangen, aber nicht abgeschlossen.
  var isEbookContinueReadingCandidate: Bool {
    var formats = attachedEbookFormats
    if let known = EbookLocalStore.knownFormat(libraryItemId: id) { formats.insert(known) }
    for fmt in formats where EbookLocalStore.isInProgressReading(libraryItemId: id, format: fmt) {
      return true
    }
    for fmt in ABSEbookFormat.allCases where EbookLocalStore.isInProgressReading(libraryItemId: id, format: fmt) {
      return true
    }
    return false
  }

  var ebookOpenPillCaption: String {
    if let f = ebookReadProgressFraction(), f >= 0.99 {
      return "Finished"
    }
    if let f = ebookReadProgressFraction(), f > 0.02 {
      return "Continue reading"
    }
    return "Read"
  }
}
