import SwiftUI

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

/// UI-Farben für Dark-Mode (#121212) bzw. Sepia-Light (kein Weiß).
struct AppColorPalette: Equatable {
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

  static let dark = AppColorPalette(
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

  /// Warmes Sepia-Light (Papier, keine weiße Fläche).
  static let sepia = AppColorPalette(
    background: Color(red: 238 / 255, green: 228 / 255, blue: 208 / 255),
    card: Color(red: 200 / 255, green: 182 / 255, blue: 150 / 255),
    textPrimary: Color(red: 42 / 255, green: 32 / 255, blue: 24 / 255),
    textSecondary: Color(red: 92 / 255, green: 78 / 255, blue: 62 / 255),
    achievementLevel1: Color(red: 168 / 255, green: 155 / 255, blue: 138 / 255),
    achievementLevel2: Color(red: 148 / 255, green: 128 / 255, blue: 102 / 255),
    achievementLevel3: Color(red: 196 / 255, green: 138 / 255, blue: 72 / 255),
    achievementLevel4: Color(red: 178 / 255, green: 98 / 255, blue: 32 / 255),
    progressTrack: Color(red: 42 / 255, green: 32 / 255, blue: 24 / 255).opacity(0.14),
    heroPlayPillBackground: Color(red: 42 / 255, green: 32 / 255, blue: 24 / 255),
    heroPlayPillForeground: Color(red: 248 / 255, green: 240 / 255, blue: 220 / 255),
    heroCardShadow: Color(red: 42 / 255, green: 32 / 255, blue: 24 / 255).opacity(0.24),
    cardShadow: Color(red: 42 / 255, green: 32 / 255, blue: 24 / 255).opacity(0.2)
  )

  static func palette(for mode: AppearanceMode, system: ColorScheme) -> AppColorPalette {
    switch mode {
    case .dark: return .dark
    case .light: return .sepia
    case .system: return system == .dark ? .dark : .sepia
    }
  }

  var isDarkLike: Bool { self == .dark }
}

/// Akzentfarbe pro Paletten-Familie (Dark vs. Sepia-Light); System nutzt aufgelöst Dark oder Light.
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
