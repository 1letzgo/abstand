import SwiftUI
import UIKit

/// Erscheinungsbild der App (Einstellungen → Appearance). Standard: `.light` (Paper).
enum AppearanceMode: String, CaseIterable, Identifiable, Hashable {
  case dark
  case light
  case system

  var id: String { rawValue }

  var label: String {
    switch self {
    case .dark: "Dark"
    case .light: "Light"
    case .system: "System"
    }
  }

  private static let storageKey = AppModel.Keys.appearanceMode

  static func load(from defaults: UserDefaults = .standard) -> AppearanceMode {
    guard let raw = defaults.string(forKey: storageKey),
      let mode = AppearanceMode(rawValue: raw)
    else { return .light }
    return mode
  }

  func persist(to defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.storageKey)
  }
}

/// Darstellung von Hörbuch-Zeilen in Library, Suche und Entitäts-Details.
enum LibraryBookCardStyle: String, CaseIterable, Identifiable, Hashable {
  case compact
  case heroCover

  var id: String { rawValue }

  var label: String {
    switch self {
    case .compact: "Compact row"
    case .heroCover: "Cover card"
    }
  }

  /// Mehrspaltiges Cover-Raster statt einspaltiger Liste.
  var usesMultiColumnGrid: Bool {
    switch self {
    case .compact: false
    case .heroCover: true
    }
  }

  /// Spalten auf iPhone (`compact` Width); iPad legt in `LibraryHeroMultiColumnRows` +2 drauf.
  var phoneGridColumns: Int {
    switch self {
    case .compact: 1
    case .heroCover: 2
    }
  }

  private static let storageKey = AppModel.Keys.libraryBookCardStyle

  /// Entfernter Stil „Cover only“ → nächstverwandtes Raster („Cover card“).
  private static let removedCoverOnlyRawValue = "coverOnly"

  static func load(from defaults: UserDefaults = .standard) -> LibraryBookCardStyle {
    guard let raw = defaults.string(forKey: storageKey) else { return .compact }
    if raw == removedCoverOnlyRawValue { return .heroCover }
    return LibraryBookCardStyle(rawValue: raw) ?? .compact
  }

  func persist(to defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.storageKey)
  }
}

/// Darstellung von Podcast-Episoden in Library und Downloads.
enum LibraryPodcastCardStyle: String, CaseIterable, Identifiable, Hashable {
  case compact
  case heroCover

  var id: String { rawValue }

  var label: String {
    switch self {
    case .compact: "Compact row"
    case .heroCover: "Cover card"
    }
  }

  private static let storageKey = AppModel.Keys.libraryPodcastCardStyle

  static func load(from defaults: UserDefaults = .standard) -> LibraryPodcastCardStyle {
    guard let raw = defaults.string(forKey: storageKey),
      let style = LibraryPodcastCardStyle(rawValue: raw)
    else { return .compact }
    return style
  }

  func persist(to defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.storageKey)
  }
}

/// Zielsprache für Teleprompter-Wortübersetzung (Quelle = Buch-/Transkriptsprache).
enum TranslationTargetLanguage {
  private static let storageKey = AppModel.Keys.translationTargetLanguageCode

  /// Häufige Zielsprachen für Picker in Settings und Wort-Sheet.
  static let selectableLanguageCodes: [String] = [
    "de", "en", "fr", "es", "it", "nl", "pt", "pl", "ru", "ja", "zh", "ko",
    "ar", "hi", "tr", "sv", "da", "nb", "fi", "cs", "hu", "uk", "el", "he", "vi", "th", "id", "ro",
  ]

  static var defaultLanguageCode: String {
    languageCode(from: Locale.preferredLanguages.first ?? Locale.current.identifier(.bcp47)) ?? "en"
  }

  static func load(from defaults: UserDefaults = .standard) -> String {
    let raw = defaults.string(forKey: storageKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !raw.isEmpty { return normalized(raw) }
    return defaultLanguageCode
  }

  /// Gültiger Picker-Wert (nur bekannte ISO-639-1-Codes).
  static func normalized(_ code: String) -> String {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return defaultLanguageCode }
    let base = languageCode(from: trimmed) ?? trimmed
    let allowed = Set(selectableLanguageCodes + [defaultLanguageCode])
    return allowed.contains(base) ? base : defaultLanguageCode
  }

  static func persist(_ code: String, to defaults: UserDefaults = .standard) {
    defaults.set(code, forKey: storageKey)
  }

  static func displayName(for code: String, locale: Locale = .current) -> String {
    locale.localizedString(forLanguageCode: code) ?? code.uppercased()
  }

  static func pickerOptions(locale: Locale = .current) -> [(id: String, label: String)] {
    var codes = Set(selectableLanguageCodes)
    codes.insert(defaultLanguageCode)
    codes.insert(load())
    return codes.sorted { displayName(for: $0, locale: locale) < displayName(for: $1, locale: locale) }
      .map { (id: $0, label: displayName(for: $0, locale: locale)) }
  }

  static func toLocaleLanguage(_ code: String) -> Locale.Language {
    Locale.Language(identifier: code)
  }

  static func languageCode(from locale: Locale) -> String? {
    if let code = locale.language.languageCode?.identifier, !code.isEmpty {
      return code.lowercased()
    }
    return languageCode(from: locale.identifier(.bcp47))
  }

  static func sameLanguage(_ a: Locale?, _ targetCode: String) -> Bool {
    guard let a, let src = languageCode(from: a) else { return false }
    return src.lowercased() == targetCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func languageCode(from identifier: String) -> String? {
    let id = identifier.lowercased()
    if let dash = id.firstIndex(of: "-") { return String(id[..<dash]) }
    if let underscore = id.firstIndex(of: "_") { return String(id[..<underscore]) }
    return id.count >= 2 ? String(id.prefix(2)) : (id.isEmpty ? nil : id)
  }
}

/// UI-Farben — Hintergrund/Karten leicht aus der Appearance-Akzentfarbe abgeleitet.
struct AppColorPalette: Equatable {
  let isDarkLike: Bool
  let background: Color
  let card: Color
  let textPrimary: Color
  let textSecondary: Color
  /// Dezenter Fortschritts-/Track-Hintergrund auf Karten.
  let progressTrack: Color
  /// Haarlinien (Trenner, Kartenkante) — Papier-Linie statt Schatten.
  let rule: Color
  /// Schatten unter Hero-Karten (Continue Listening).
  let heroCardShadow: Color
  /// Schatten für Listen- und Gruppen-Karten.
  let cardShadow: Color
  /// Play-/Read-Badge auf Cover-Thumbnails (Library-Zeilen).
  let coverPlayBadgeBackground: Color

  static func palette(
    for mode: AppearanceMode,
    system: ColorScheme,
    accent: Color
  ) -> AppColorPalette {
    let isDarkLike: Bool
    switch mode {
    case .dark: isDarkLike = true
    case .light: isDarkLike = false
    case .system: isDarkLike = system == .dark
    }
    return derived(from: accent, isDarkLike: isDarkLike)
  }

  /// „Paper“ (design-demos/direction-approved.md): Light = warmes Papier mit Tinte, Dark = Tinte
  /// mit Papier-Schrift. Feste Flächen — der Akzent färbt nur Fortschritt und Links, nie Flächen.
  static func derived(from accent: Color, isDarkLike: Bool) -> AppColorPalette {
    isDarkLike ? inkPalette : paperPalette
  }

  private static let paperPalette = AppColorPalette(
    isDarkLike: false,
    background: Color(red: 243 / 255, green: 238 / 255, blue: 227 / 255),
    // Karten als hellerer Bogen auf dem Papier (statt Schatten).
    card: Color(red: 250 / 255, green: 247 / 255, blue: 240 / 255),
    textPrimary: Color(red: 31 / 255, green: 27 / 255, blue: 22 / 255),
    textSecondary: Color(red: 124 / 255, green: 114 / 255, blue: 99 / 255),
    progressTrack: Color(red: 220 / 255, green: 210 / 255, blue: 192 / 255),
    rule: Color(red: 220 / 255, green: 210 / 255, blue: 192 / 255),
    heroCardShadow: Color(red: 60 / 255, green: 40 / 255, blue: 10 / 255).opacity(0.10),
    cardShadow: Color(red: 60 / 255, green: 40 / 255, blue: 10 / 255).opacity(0.05),
    coverPlayBadgeBackground: Color(red: 31 / 255, green: 27 / 255, blue: 22 / 255).opacity(0.72)
  )

  private static let inkPalette = AppColorPalette(
    isDarkLike: true,
    background: Color(red: 27 / 255, green: 25 / 255, blue: 21 / 255),
    // Karten eine Stufe heller als die Tinte.
    card: Color(red: 39 / 255, green: 36 / 255, blue: 31 / 255),
    textPrimary: Color(red: 239 / 255, green: 232 / 255, blue: 218 / 255),
    textSecondary: Color(red: 163 / 255, green: 154 / 255, blue: 138 / 255),
    progressTrack: Color(red: 239 / 255, green: 232 / 255, blue: 218 / 255).opacity(0.16),
    rule: Color(red: 239 / 255, green: 232 / 255, blue: 218 / 255).opacity(0.14),
    heroCardShadow: Color.black.opacity(0.32),
    cardShadow: Color.black.opacity(0.24),
    coverPlayBadgeBackground: Color(red: 27 / 255, green: 25 / 255, blue: 21 / 255).opacity(0.72)
  )

  private static func rgbComponents(from color: Color) -> (r: Double, g: Double, b: Double)? {
    let ui = UIColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return (Double(r), Double(g), Double(b))
  }

  /// WCAG-Relative Luminanz (sRGB), 0 … 1.
  private static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
    func channel(_ value: Double) -> Double {
      value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let R = channel(r)
    let G = channel(g)
    let B = channel(b)
    return 0.2126 * R + 0.7152 * G + 0.0722 * B
  }

  /// Lesbare Schrift auf voller Akzentfläche — bei hellem Akzent dunkle Schrift.
  func foregroundOnAccent(_ accent: Color) -> Color {
    guard let rgb = Self.rgbComponents(from: accent) else {
      return isDarkLike
        ? Color(red: 42 / 255, green: 32 / 255, blue: 24 / 255)
        : textPrimary
    }
    if Self.relativeLuminance(r: rgb.r, g: rgb.g, b: rgb.b) > 0.55 {
      return isDarkLike
        ? Color(red: 42 / 255, green: 32 / 255, blue: 24 / 255)
        : textPrimary
    }
    return .white
  }

  /// Primär-/Sekundärtext auf Cover-getönten Continue-Karten (stärkerer Tint als Detail).
  func readableTextOnTintedCard(_ tint: Color) -> (primary: Color, secondary: Color) {
    guard let rgb = Self.rgbComponents(from: tint) else {
      return (textPrimary, textSecondary)
    }
    let lum = Self.relativeLuminance(r: rgb.r, g: rgb.g, b: rgb.b)
    if lum > 0.48 {
      // Helle/kräftige Tönung → dunkle Schrift.
      return (
        Color(red: 22 / 255, green: 22 / 255, blue: 24 / 255),
        Color(red: 70 / 255, green: 70 / 255, blue: 78 / 255)
      )
    }
    // Dunkle Tönung → helle Schrift (sekundär etwas weicher).
    return (
      Color.white,
      Color.white.opacity(0.78)
    )
  }
}

/// Akzentfarbe pro Paletten-Familie (Dark vs. Light); System nutzt aufgelöst Dark oder Light.
enum AppearanceAccentSlot: String {
  case dark
  case light

  static func slot(for mode: AppearanceMode, system: ColorScheme) -> AppearanceAccentSlot {
    switch mode {
    case .dark: return .dark
    case .light: return .light
    case .system: return system == .dark ? .dark : .light
    }
  }

  var userDefaultsKey: String {
    switch self {
    case .dark: return "abstand_appearance_accent_rgb_dark"
    case .light: return "abstand_appearance_accent_rgb_light"
    }
  }

  var defaultAccent: Color {
    switch self {
    case .dark: return AppTheme.defaultAccent
    case .light: return AppTheme.defaultLightAccent
    }
  }
}
