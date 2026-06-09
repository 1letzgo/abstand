import SwiftUI
import UIKit

/// Erscheinungsbild der App (Einstellungen → Appearance). Standard: `.dark`.
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

  private static let storageKey = "abstand_appearance_mode"

  static func load(from defaults: UserDefaults = .standard) -> AppearanceMode {
    guard let raw = defaults.string(forKey: storageKey),
      let mode = AppearanceMode(rawValue: raw)
    else { return .dark }
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

  private static let storageKey = "abstand_library_book_card_style"

  static func load(from defaults: UserDefaults = .standard) -> LibraryBookCardStyle {
    guard let raw = defaults.string(forKey: storageKey),
      let style = LibraryBookCardStyle(rawValue: raw)
    else { return .compact }
    return style
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

  private static let storageKey = "abstand_library_podcast_card_style"

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
  private static let storageKey = "abstand_translation_target_language"

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
  let achievementLevel1: Color
  let achievementLevel2: Color
  let achievementLevel3: Color
  let achievementLevel4: Color
  /// Dezenter Fortschritts-/Track-Hintergrund auf Karten.
  let progressTrack: Color
  /// Continue-Hero: Play-Pille unter dem Cover.
  let heroPlayPillBackground: Color
  let heroPlayPillForeground: Color
  /// Schatten unter Hero-Karten (Continue Listening).
  let heroCardShadow: Color
  /// Schatten für Listen- und Gruppen-Karten.
  let cardShadow: Color

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

  /// Light: Hintergrund/Karten aus Akzentfarbe; Dark: feste Flächen (#121212 / #252525).
  static func derived(from accent: Color, isDarkLike: Bool) -> AppColorPalette {
    if isDarkLike {
      return fixedDarkPalette()
    }

    guard let accentRGB = Self.rgbComponents(from: accent) else {
      return neutralLightFallback
    }

    return AppColorPalette(
      isDarkLike: false,
      background: Self.mix(
        base: (252 / 255, 252 / 255, 250 / 255),
        accent: accentRGB,
        accentWeight: 0.1
      ),
      card: Self.mix(
        base: (230 / 255, 230 / 255, 228 / 255),
        accent: accentRGB,
        accentWeight: 0.16
      ),
      textPrimary: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
      textSecondary: Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255),
      achievementLevel1: Color(red: 190 / 255, green: 190 / 255, blue: 194 / 255),
      achievementLevel2: Color(red: 158 / 255, green: 158 / 255, blue: 163 / 255),
      achievementLevel3: Color(red: 255 / 255, green: 176 / 255, blue: 72 / 255),
      achievementLevel4: Color(red: 230 / 255, green: 140 / 255, blue: 48 / 255),
      progressTrack: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.1),
      heroPlayPillBackground: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
      heroPlayPillForeground: .white,
      heroCardShadow: Color.black.opacity(0.1),
      cardShadow: Color.black.opacity(0.1)
    )
  }

  private static func fixedDarkPalette() -> AppColorPalette {
    AppColorPalette(
      isDarkLike: true,
      background: Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255),
      card: Color(red: 37 / 255, green: 37 / 255, blue: 37 / 255),
      textPrimary: .white,
      textSecondary: Color(red: 176 / 255, green: 176 / 255, blue: 176 / 255),
      achievementLevel1: Color(red: 190 / 255, green: 190 / 255, blue: 190 / 255),
      achievementLevel2: Color(red: 158 / 255, green: 152 / 255, blue: 146 / 255),
      achievementLevel3: Color(red: 210 / 255, green: 152 / 255, blue: 88 / 255),
      achievementLevel4: Color(red: 204 / 255, green: 108 / 255, blue: 36 / 255),
      progressTrack: Color.white.opacity(0.14),
      heroPlayPillBackground: .white,
      heroPlayPillForeground: .white,
      heroCardShadow: Color.black.opacity(0.32),
      cardShadow: Color.black.opacity(0.36)
    )
  }

  private static let neutralLightFallback = derived(
    from: AppTheme.defaultLightAccent, isDarkLike: false)

  private static func mix(
    base: (r: Double, g: Double, b: Double),
    accent: (r: Double, g: Double, b: Double),
    accentWeight: Double
  ) -> Color {
    let w = min(1, max(0, accentWeight))
    let inv = 1 - w
    return Color(
      red: base.r * inv + accent.r * w,
      green: base.g * inv + accent.g * w,
      blue: base.b * inv + accent.b * w
    )
  }

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
