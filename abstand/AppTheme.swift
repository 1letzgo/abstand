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
  /// Verbindungs-Ampel „prüft …“ (gelb).
  static let warning = Color(red: 0.98, green: 0.78, blue: 0.22)

  /// Raster für Tabs, Listen und Karten (Home / Books / …).
  enum Layout {
    /// Tab-Inhalt horizontal (z. B. Start, Books, Einstellungen).
    static let tabPaddingH: CGFloat = 16
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

    /// Horizontale Cover-Leiste: Podcast „Shows“ und Books „Browse“ (gleiche Maße).
    static let horizontalBrowseStripTile: CGFloat = 68
    /// Caption breiter als Kachel (`captionW = tile + labelWidthExtra`); pro Spalte bleibt
    /// `labelWidthExtra` Luft rechts der Kachel — wird vom HStack-Abstand abgezogen, damit der
    /// sichtbare Abstand zwischen Kacheln wie `withinSectionSpacing` bei Library-Zeilen wirkt.
    static let horizontalBrowseStripLabelWidthExtra: CGFloat = 12
    static let horizontalBrowseStripInterTileSpacing: CGFloat = max(
      0, withinSectionSpacing - horizontalBrowseStripLabelWidthExtra)
    static let horizontalBrowseStripTileLabelSpacing: CGFloat = 6
    static let horizontalBrowseStripVerticalPadding: CGFloat = 4

    /// „Continue listening“-Karten (horizontal scrollbar, einheitliche Höhe).
    static let continueHeroCardCornerRadius: CGFloat = 16
    static let continueHeroCardWidth: CGFloat = 176
    /// Quadrat wie die Kartenbreite: typisches Cover vollständig sichtbar (`scaledToFit`).
    static let continueHeroCoverMaxHeight: CGFloat = 176
    /// Abstand Titel ↔ Unterzeile im Hero-Metablock.
    static let continueHeroMetadataTitleDetailSpacing: CGFloat = 4
    static let continueHeroMetadataVerticalPadding: CGFloat = 8
    /// Genau zwei Zeilen `headline` (wie `BookRowCard`, fester Slot).
    static let continueHeroMetadataTitleFixedHeight: CGFloat = 44
    /// Eine Zeile `caption` für Autor/Show.
    static let continueHeroMetadataDetailFixedHeight: CGFloat = 18
    /// Abstand Autor-/Show-Zeile → Play-Pille.
    static let continueHeroMetadataPlayPillTopPadding: CGFloat = 8
    /// Höhe der Play-/Read-Pille (Capsule inkl. Innen-Padding).
    static let continueHeroMetadataPlayPillIntrinsicHeight: CGFloat = 34
    /// Abstand unter der Play-/Read-Pille (Continue Listening + eBooks-Grid).
    static let continueHeroMetadataExtraBottomPadding: CGFloat = 10
    /// Fester Textblock unter dem Cover — alle Continue-Hero-Karten gleich hoch.
    static let continueHeroMetadataBlockHeight: CGFloat =
      continueHeroMetadataVerticalPadding
      + continueHeroMetadataTitleFixedHeight
      + continueHeroMetadataTitleDetailSpacing
      + continueHeroMetadataDetailFixedHeight
      + continueHeroMetadataPlayPillTopPadding
      + continueHeroMetadataPlayPillIntrinsicHeight
      + continueHeroMetadataExtraBottomPadding
    /// Gesamthöhe Continue-Hero-Karte (Cover + Metadaten).
    static let continueHeroCardTotalHeight: CGFloat = continueHeroCoverMaxHeight + continueHeroMetadataBlockHeight
    static let continueHeroCardHeight: CGFloat = continueHeroCardTotalHeight

    static let cardCornerRadius: CGFloat = 14
    /// Library-Zeilen — gleiche Abrundung wie Browse-/Podcast-Icon-Kacheln.
    static let libraryRowCornerRadius: CGFloat = podcastShelfCoverCorner
    static let coverCornerRadius: CGFloat = 11

    /// Quadratisches Cover in Library-Zeilen (bündig links/oben/unten, `scaledToFill`).
    static let libraryRowCoverSide: CGFloat = 82
    /// Abstand Cover ↔ Textspalte in Library-Zeilen.
    static let libraryRowCardInset: CGFloat = 10
    /// Titel oben / Laufzeit unten (minimal zum Kartenrand).
    static let libraryRowTextInset: CGFloat = 6
    /// Höhe des Fortschrittsstreifens am unteren Kartenrand (Library-Zeilen).
    static let libraryRowBottomProgressHeight: CGFloat = 4
  }
}

private struct AbstandScrollBackgroundModifier: ViewModifier {
  var ignoreSafeArea = false

  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background {
        if ignoreSafeArea {
          AppTheme.background.ignoresSafeArea()
        } else {
          AppTheme.background
        }
      }
  }
}

extension View {
  /// System-Scrollmaterial ausblenden, App-Hintergrund (#121212) — für `ScrollView` und `List`.
  func abstandScrollScreenBackground(ignoreSafeArea: Bool = false) -> some View {
    modifier(AbstandScrollBackgroundModifier(ignoreSafeArea: ignoreSafeArea))
  }

  /// Volle Tab-Fläche inkl. Bereich unter der Navigationsleiste.
  func abstandTabScreenChrome() -> some View {
    frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(AppTheme.background)
  }
}

/// Kategoriezeile über Browse-Strips und Listen (Home, Library, Podcasts, Settings).
struct TabContentSectionTitle: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.title3)
      .bold()
      .foregroundStyle(AppTheme.textPrimary)
      .frame(maxWidth: .infinity, alignment: .leading)
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

/// Gesamtdauer für Pill-Buttons („12 Std. 4 Min.“).
func formatPlaybackDurationShortHuman(_ seconds: Double) -> String {
  guard seconds.isFinite, seconds >= 0 else { return "0 Min." }
  let s = Int(seconds.rounded())
  let h = s / 3600
  let m = (s % 3600) / 60
  if h > 0, m > 0 { return "\(h) Std. \(m) Min." }
  if h > 0 { return m > 0 ? "\(h) Std. \(m) Min." : "\(h) Std." }
  if m > 0 { return "\(m) Min." }
  return "unter 1 Min."
}
