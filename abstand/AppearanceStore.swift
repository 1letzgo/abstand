import SwiftUI
import UIKit

/// Appearance-Persistenz und Farb-Hilfen — von `AppModel` genutzt (Fassade bleibt API-stabil).
enum AppearanceStore {
  static func migrateAccentKeysIfNeeded() {
    let d = UserDefaults.standard
    if d.string(forKey: AppModel.Keys.appearanceAccentRGBDark) == nil,
      let legacy = d.string(forKey: AppModel.Keys.appearanceAccentRGB),
      color(fromAccentRGBString: legacy) != nil
    {
      d.set(legacy, forKey: AppModel.Keys.appearanceAccentRGBDark)
    }
    if d.string(forKey: AppModel.Keys.appearanceAccentRGBLight) == nil {
      persistAccentColor(AppTheme.defaultLightAccent, slot: .light)
    }
  }

  static func loadAccentColor(slot: AppearanceAccentSlot) -> Color {
    let d = UserDefaults.standard
    if let raw = d.string(forKey: slot.userDefaultsKey),
      let color = color(fromAccentRGBString: raw)
    {
      return color
    }
    return slot.defaultAccent
  }

  static func persistAccentColor(_ color: Color, slot: AppearanceAccentSlot) {
    guard let rgb = rgbComponents(from: color) else { return }
    let raw = String(format: "%.4f,%.4f,%.4f", rgb.r, rgb.g, rgb.b)
    UserDefaults.standard.set(raw, forKey: slot.userDefaultsKey)
  }

  static func color(fromAccentRGBString raw: String) -> Color? {
    let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 3 else { return nil }
    return Color(red: parts[0], green: parts[1], blue: parts[2])
  }

  static func rgbComponents(from color: Color) -> (r: Double, g: Double, b: Double)? {
    let ui = UIColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return (Double(r), Double(g), Double(b))
  }

  static func accentColorsEqual(_ lhs: Color, _ rhs: Color) -> Bool {
    guard let a = rgbComponents(from: lhs), let b = rgbComponents(from: rhs) else { return false }
    let eps = 0.002
    return abs(a.r - b.r) < eps && abs(a.g - b.g) < eps && abs(a.b - b.b) < eps
  }

  static func currentAccentSlot(mode: AppearanceMode, system: ColorScheme) -> AppearanceAccentSlot {
    AppearanceAccentSlot.slot(for: mode, system: system)
  }
}
