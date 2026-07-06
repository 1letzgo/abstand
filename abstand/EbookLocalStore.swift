import Foundation
import ReadiumShared

enum EpubReaderTheme: String, CaseIterable {
  case light
  case sepia
  case dark

  /// Nächstes Theme (Hell → Sepia → Dunkel).
  func next() -> EpubReaderTheme {
    switch self {
    case .light: return .sepia
    case .sepia: return .dark
    case .dark: return .light
    }
  }

  /// Symbol für den Theme-Button (zeigt das nächste Theme an).
  var nextThemeToolbarIcon: String {
    switch next() {
    case .light: return "sun.max.fill"
    case .sepia: return "text.page.fill"
    case .dark: return "moon.fill"
    }
  }
}

/// Leseeinstellungen (global, UserDefaults).
enum EpubReaderSettings {
  /// Readium-Schriftgröße als Faktor (1.0 = 100 %, Standard).
  private static let fontScaleKey = "abstand_epub_font_scale"
  private static let legacyFontSizeKey = "abstand_epub_font_size"
  private static let themeKey = "abstand_epub_reader_theme"
  private static let continuousScrollKey = "abstand_epub_continuous_scroll"

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

  /// Dauerscroll statt Seitenweise-Umblättern (Readium `scroll`).
  static func loadContinuousScroll() -> Bool {
    UserDefaults.standard.bool(forKey: continuousScrollKey)
  }

  static func saveContinuousScroll(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: continuousScrollKey)
  }
}

enum ABSEbookFormat: String, Codable, CaseIterable {
  case epub
  case pdf

  var fileExtension: String { rawValue }

  static func resolve(format: String?, ext: String?, filename: String?) -> ABSEbookFormat? {
    let f = (format ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if f == "epub" || f.contains("epub") { return .epub }
    if f == "application/epub+zip" || f == "application/x-epub+zip" { return .epub }
    if f == "pdf" || f.contains("pdf") { return .pdf }
    if f == "application/pdf" { return .pdf }
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
  private static let legacyProgressMigratedFlag = "abstand_ebook_legacy_progress_migrated_v1"

  private static var knownFormatsByItemId: [String: String] = [:]
  private static var knownFormatsLoadedForSessionKey: String?

  private static func knownFormatsFileURL(account: URL, userId: String) -> URL {
    readingProgressDir(account: account, userId: userId)
      .appendingPathComponent("known_formats.json", isDirectory: false)
  }

  private static func loadKnownFormatsIfNeeded(account: URL, userId: String) {
    let sessionKey = "\(account.lastPathComponent)|\(userId)"
    if knownFormatsLoadedForSessionKey == sessionKey { return }
    knownFormatsLoadedForSessionKey = sessionKey
    let url = knownFormatsFileURL(account: account, userId: userId)
    guard let data = try? Data(contentsOf: url),
      let dict = try? JSONDecoder().decode([String: String].self, from: data)
    else {
      knownFormatsByItemId = [:]
      return
    }
    knownFormatsByItemId = dict
  }

  private static func persistKnownFormats(account: URL, userId: String) {
    let url = knownFormatsFileURL(account: account, userId: userId)
    guard let data = try? JSONEncoder().encode(knownFormatsByItemId) else { return }
    try? data.write(to: url, options: .atomic)
  }

  static func rememberKnownFormat(_ format: ABSEbookFormat, libraryItemId: String) {
    guard let session = requireSession() else { return }
    loadKnownFormatsIfNeeded(account: session.account, userId: session.userId)
    knownFormatsByItemId[libraryItemId] = format.rawValue
    persistKnownFormats(account: session.account, userId: session.userId)
  }

  static func knownFormat(libraryItemId: String) -> ABSEbookFormat? {
    guard let session = requireSession() else { return nil }
    loadKnownFormatsIfNeeded(account: session.account, userId: session.userId)
    guard let raw = knownFormatsByItemId[libraryItemId] else { return nil }
    return ABSEbookFormat(rawValue: raw)
  }

  /// Bereits heruntergeladene Dateien / Meta-JSON → `knownFormat`, damit EPUB/PDF-Filter ohne vorheriges Öffnen greifen.
  static func syncKnownFormatsFromDisk(account: URL?) {
    guard let account else { return }
    let dir = account.appendingPathComponent("ebooks", isDirectory: true)
    guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
    for url in urls {
      let name = url.lastPathComponent
      if name.hasSuffix(".meta.json") {
        let stem = String(name.dropLast(".meta.json".count))
        guard let dot = stem.lastIndex(of: ".") else { continue }
        let itemId = String(stem[..<dot])
        let ext = String(stem[stem.index(after: dot)...]).lowercased()
        guard let fmt = ABSEbookFormat(rawValue: ext) else { continue }
        rememberKnownFormat(fmt, libraryItemId: itemId)
        continue
      }
      let ext = url.pathExtension.lowercased()
      guard let fmt = ABSEbookFormat(rawValue: ext) else { continue }
      let itemId = url.deletingPathExtension().lastPathComponent
      guard !itemId.isEmpty else { continue }
      rememberKnownFormat(fmt, libraryItemId: itemId)
    }
  }
}

/// Metadaten zu einer lokal gecachten E-Book-Datei (für Offline-Wiederverwendung).
struct EbookDownloadMeta: Codable {
  let libraryItemId: String
  let ino: String
  let format: ABSEbookFormat
  let title: String?
}

/// Lokale E-Book-Dateien (EPUB/PDF) pro Account; Lesestand pro angemeldetem User.
enum EbookLocalStore {
  private static let fm = FileManager.default
  private static var activeAccount: URL?
  private static var activeUserId: String?

  /// Nach Login / `applyAuthorizeUser` setzen; bei Logout `nil`.
  static func updateActiveSession(account: URL?, userId: String?) {
    let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    activeAccount = account
    activeUserId = uid.isEmpty ? nil : uid
    knownFormatsLoadedForSessionKey = nil
    knownFormatsByItemId = [:]
    if let account, let activeUserId {
      migrateLegacyGlobalReadingProgressIfNeeded(account: account, userId: activeUserId)
    }
  }

  private static func requireSession() -> (account: URL, userId: String)? {
    guard let activeAccount, let activeUserId else { return nil }
    return (activeAccount, activeUserId)
  }

  private static func readingProgressDir(account: URL, userId: String) -> URL {
    let u = account
      .appendingPathComponent("ebooks", isDirectory: true)
      .appendingPathComponent("reading", isDirectory: true)
      .appendingPathComponent(userId, isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }

  private static func locatorFileURL(
    account: URL, userId: String, libraryItemId: String, format: ABSEbookFormat
  ) -> URL {
    readingProgressDir(account: account, userId: userId)
      .appendingPathComponent("\(libraryItemId).\(format.rawValue).locator.json", isDirectory: false)
  }

  private static func pageProgressFileURL(
    account: URL, userId: String, libraryItemId: String, format: ABSEbookFormat
  ) -> URL {
    readingProgressDir(account: account, userId: userId)
      .appendingPathComponent("\(libraryItemId).\(format.rawValue).pages.json", isDirectory: false)
  }

  private static func migrateLegacyGlobalReadingProgressIfNeeded(account: URL, userId: String) {
    let flagKey = "\(legacyProgressMigratedFlag)_\(account.lastPathComponent)_\(userId)"
    guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
    let ud = UserDefaults.standard
    var migratedAny = false

    for key in ud.dictionaryRepresentation().keys {
      if key.hasPrefix("abstand_readium_loc_") {
        let suffix = String(key.dropFirst("abstand_readium_loc_".count))
        guard let parsed = parseLegacyLibraryItemSuffix(suffix),
          let json = ud.string(forKey: key)
        else { continue }
        let url = locatorFileURL(
          account: account, userId: userId, libraryItemId: parsed.itemId, format: parsed.format)
        if !fm.fileExists(atPath: url.path) {
          try? json.data(using: .utf8)?.write(to: url, options: .atomic)
          migratedAny = true
        }
        ud.removeObject(forKey: key)
      } else if key.hasPrefix("abstand_readium_pages_") {
        let suffix = String(key.dropFirst("abstand_readium_pages_".count))
        guard let parsed = parseLegacyLibraryItemSuffix(suffix),
          let dict = ud.dictionary(forKey: key) as? [String: Int],
          let total = dict["total"], total > 0,
          let current = dict["current"]
        else { continue }
        let url = pageProgressFileURL(
          account: account, userId: userId, libraryItemId: parsed.itemId, format: parsed.format)
        if !fm.fileExists(atPath: url.path) {
          let payload: [String: Int] = ["current": current, "total": total]
          if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: url, options: .atomic)
            migratedAny = true
          }
        }
        ud.removeObject(forKey: key)
      } else if key.hasPrefix("abstand_ebook_fmt_") {
        let itemId = String(key.dropFirst("abstand_ebook_fmt_".count))
        guard !itemId.isEmpty, let raw = ud.string(forKey: key) else { continue }
        loadKnownFormatsIfNeeded(account: account, userId: userId)
        if knownFormatsByItemId[itemId] == nil {
          knownFormatsByItemId[itemId] = raw
          migratedAny = true
        }
        ud.removeObject(forKey: key)
      }
    }

    if migratedAny {
      persistKnownFormats(account: account, userId: userId)
    }
    UserDefaults.standard.set(true, forKey: flagKey)
  }

  private static func parseLegacyLibraryItemSuffix(_ suffix: String) -> (
    format: ABSEbookFormat, itemId: String
  )? {
    for fmt in ABSEbookFormat.allCases {
      let mid = "\(fmt.rawValue)_"
      guard suffix.hasPrefix(mid) else { continue }
      let itemId = String(suffix.dropFirst(mid.count))
      guard !itemId.isEmpty else { return nil }
      return (fmt, itemId)
    }
    return nil
  }

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

  static func cachedEbookFileByteCount(account: URL?, libraryItemId: String) -> Int64? {
    guard let cached = cachedEbookIfPresent(account: account, libraryItemId: libraryItemId) else { return nil }
    let values = try? cached.url.resourceValues(forKeys: [.fileSizeKey])
    return values?.fileSize.map(Int64.init)
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

  static func loadReadiumLocator(libraryItemId: String, format: ABSEbookFormat) -> Locator? {
    guard let session = requireSession() else { return nil }
    let url = locatorFileURL(
      account: session.account, userId: session.userId, libraryItemId: libraryItemId, format: format)
    guard let data = try? Data(contentsOf: url),
      let json = String(data: data, encoding: .utf8)
    else { return nil }
    return try? Locator(jsonString: json)
  }

  /// Seitengenauer Readium-Stand (lokal); Server bekommt parallel nur `ebookProgress`-Prozent.
  static func saveReadiumLocator(_ locator: Locator, libraryItemId: String, format: ABSEbookFormat) {
    guard let session = requireSession() else { return }
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }
    if let finished = loadProgressFraction(libraryItemId: id), finished >= 0.995 { return }
    guard let json = try? locator.jsonString() else { return }
    let url = locatorFileURL(
      account: session.account, userId: session.userId, libraryItemId: id, format: format)
    try? json.data(using: .utf8)?.write(to: url, options: .atomic)
  }

  static func clearReadiumLocator(libraryItemId: String, format: ABSEbookFormat) {
    guard let session = requireSession() else { return }
    let locatorURL = locatorFileURL(
      account: session.account, userId: session.userId, libraryItemId: libraryItemId, format: format)
    try? fm.removeItem(at: locatorURL)
    clearPageProgress(libraryItemId: libraryItemId, format: format)
  }

  /// Buchweite Seiten (EPUB, gerendert) — für Listen-Metadaten und Resume-Hilfe.
  static func savePageProgress(
    current: Int, total: Int, libraryItemId: String, format: ABSEbookFormat
  ) {
    guard let session = requireSession() else { return }
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty, total > 0 else { return }
    let payload: [String: Int] = [
      "current": min(total, max(1, current)),
      "total": total,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
    let url = pageProgressFileURL(
      account: session.account, userId: session.userId, libraryItemId: id, format: format)
    try? data.write(to: url, options: .atomic)
  }

  static func loadPageProgress(libraryItemId: String, format: ABSEbookFormat) -> (current: Int, total: Int)? {
    guard let session = requireSession() else { return nil }
    let url = pageProgressFileURL(
      account: session.account, userId: session.userId, libraryItemId: libraryItemId, format: format)
    guard let data = try? Data(contentsOf: url),
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Int],
      let total = dict["total"], total > 0,
      let current = dict["current"]
    else { return nil }
    return (min(total, max(1, current)), total)
  }

  static func clearPageProgress(libraryItemId: String, format: ABSEbookFormat) {
    guard let session = requireSession() else { return }
    let url = pageProgressFileURL(
      account: session.account, userId: session.userId, libraryItemId: libraryItemId, format: format)
    try? fm.removeItem(at: url)
  }

  private static func progressFractionFileURL(
    account: URL, userId: String, libraryItemId: String
  ) -> URL {
    readingProgressDir(account: account, userId: userId)
      .appendingPathComponent("\(libraryItemId).ebook_fraction.json", isDirectory: false)
  }

  /// On-Device-Hilfs-Fortschritt (0…1) — ergänzt Server-`ebookProgress`, kein Readium-Locator.
  static func saveProgressFraction(_ fraction: Double, libraryItemId: String) {
    guard let session = requireSession() else { return }
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }
    let incoming = min(1, max(0, fraction))
    if let existing = loadProgressFraction(libraryItemId: id), existing >= 0.995, incoming < 0.995 {
      return
    }
    let f = incoming
    let payload: [String: Double] = [
      "fraction": f,
      "updatedAt": Date().timeIntervalSince1970 * 1000,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
    let url = progressFractionFileURL(
      account: session.account, userId: session.userId, libraryItemId: id)
    try? data.write(to: url, options: .atomic)
  }

  /// Alle lokal gespeicherten Lesefortschritte (`*.ebook_fraction.json`) — für Continue-reading ohne Server-Progress-Zeile.
  static func inProgressLibraryItemIds(
    minFraction: Double = 0.005,
    maxFraction: Double = 0.995
  ) -> [String] {
    guard let session = requireSession() else { return [] }
    let dir = readingProgressDir(account: session.account, userId: session.userId)
    guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
    let suffix = ".ebook_fraction.json"
    var ids: [String] = []
    ids.reserveCapacity(urls.count)
    for url in urls {
      let name = url.lastPathComponent
      guard name.hasSuffix(suffix) else { continue }
      let itemId = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !itemId.isEmpty,
        let fraction = loadProgressFraction(libraryItemId: itemId),
        fraction > minFraction, fraction < maxFraction
      else { continue }
      ids.append(itemId)
    }
    return ids
  }

  static func loadProgressFraction(libraryItemId: String) -> Double? {
    guard let session = requireSession() else { return nil }
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return nil }
    let url = progressFractionFileURL(
      account: session.account, userId: session.userId, libraryItemId: id)
    guard let data = try? Data(contentsOf: url),
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
      let f = dict["fraction"], f.isFinite, f > 0.001
    else { return nil }
    return min(1, max(0, f))
  }

  static func clearProgressFraction(libraryItemId: String) {
    guard let session = requireSession() else { return }
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }
    let url = progressFractionFileURL(
      account: session.account, userId: session.userId, libraryItemId: id)
    try? fm.removeItem(at: url)
  }
}

// MARK: - Lesefortschritt (Home / Listenkarten)

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

