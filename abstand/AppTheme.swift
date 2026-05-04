import SwiftUI

enum AppTheme {
  static let background = Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
  static let card = Color(red: 37 / 255, green: 37 / 255, blue: 37 / 255)
  static let accent = Color(red: 251 / 255, green: 192 / 255, blue: 45 / 255)
  static let textPrimary = Color.white
  static let textSecondary = Color(red: 176 / 255, green: 176 / 255, blue: 176 / 255)
  static let danger = Color(red: 0.92, green: 0.32, blue: 0.32)
  static let success = Color(red: 0.35, green: 0.82, blue: 0.55)
}

func formatPlaybackTime(_ seconds: Double) -> String {
  guard seconds.isFinite, seconds >= 0 else { return "0:00" }
  let s = Int(seconds.rounded())
  let h = s / 3600
  let m = (s % 3600) / 60
  let r = s % 60
  if h > 0 {
    return String(format: "%d:%02d:%02d", h, m, r)
  }
  return String(format: "%d:%02d", m, r)
}
