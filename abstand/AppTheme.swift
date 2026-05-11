import SwiftUI

/// Zentrale Farben und Abstände für die gesamte App.
enum AppTheme {
  static let background = Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
  static let card = Color(red: 37 / 255, green: 37 / 255, blue: 37 / 255)
  static let accent = Color(red: 251 / 255, green: 192 / 255, blue: 45 / 255)
  static let textPrimary = Color.white
  static let textSecondary = Color(red: 176 / 255, green: 176 / 255, blue: 176 / 255)
  static let danger = Color(red: 0.92, green: 0.32, blue: 0.32)
  static let success = Color(red: 0.35, green: 0.82, blue: 0.55)

  /// Raster für Tabs, Listen und Karten (Home / Books / …).
  enum Layout {
    /// Tab-Inhalt horizontal (z. B. Start, Books, Einstellungen).
    static let tabPaddingH: CGFloat = 12
    /// Abstand von der oberen Safe Area zum ersten fixen Element (Großtitel / Kopfblock).
    static let tabPaddingTop: CGFloat = 16
    /// Abstand unter dem Großtitel zur nächsten Kopfzeile (Suche, Shows) — entspricht Titel → erster Scroll-Beginn bei nur Titel+Scroll.
    static let tabTitleToHeaderBlockSpacing: CGFloat = 16
    /// Zwischen Hauptblöcken (Regale, Suchbereich ↔ Liste) — wie Home `LazyVStack`.
    static let sectionSpacing: CGFloat = 22
    /// Kategoriezeile ↔ erste Zeile / Karten innerhalb eines Blocks.
    static let withinSectionSpacing: CGFloat = 12
    /// Zusatz unter Scroll-Inhalten vor dem Tab-Bar-Zubehör (`nowPlayingAccessoryScrollBottomInset` kommt dazu).
    static let scrollBottomInsetBase: CGFloat = 24
    /// Abstand Ende des fixen Kopfbereichs zum ersten Pixel des Scroll-Inhalts (bei zusammengesetztem Kopf nur unten am Block, nicht nochmal im Scroll).
    static let headerToScrollContentSpacing: CGFloat = 16

    /// Kompakte Kachel in der Podcast-„Shows“-Leiste (nicht identisch mit Buch-Cover-Ecken).
    static let podcastShelfCoverCorner: CGFloat = 12

    static let cardCornerRadius: CGFloat = 14
    static let libraryRowCornerRadius: CGFloat = 16
    static let coverCornerRadius: CGFloat = 11

    /// Cover in `BookRowCard` / `PodcastEpisodeRowCard` (Library-Zeilen).
    static let libraryRowCoverSide: CGFloat = 76
    /// Einheitliches Inset um Cover + Text in Library-Zeilen.
    static let libraryRowCardInset: CGFloat = 10
  }
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
