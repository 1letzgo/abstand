import SwiftUI
import UIKit

/// Zentrale Farben und Abstände für die gesamte App.
enum AppTheme {
  static let background = Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
  static let card = Color(red: 37 / 255, green: 37 / 255, blue: 37 / 255)
  static let defaultAccent = Color(red: 251 / 255, green: 192 / 255, blue: 45 / 255)
  /// Aktuelle Akzentfarbe (Standard: Gelb; überschreibbar in Einstellungen → Appearance).
  /// In SwiftUI-Views bevorzugt `Color.accentColor` (folgt `.tint` am Root). `AppTheme.accent` für UIKit/Charts.
  private(set) static var accent: Color = defaultAccent
  static let textPrimary = Color.white
  static let textSecondary = Color(red: 176 / 255, green: 176 / 255, blue: 176 / 255)
  static let danger = Color(red: 0.92, green: 0.32, blue: 0.32)
  static let success = Color(red: 0.35, green: 0.82, blue: 0.55)
  /// Verbindungs-Ampel „prüft …“ (gelb).
  static let warning = Color(red: 0.98, green: 0.78, blue: 0.22)

  /// Stats-Achievement-Stufen 1–4: aufsteigend hellgrau → dunkelorange (Level 5: `success`).
  static let achievementLevel1 = Color(red: 190 / 255, green: 190 / 255, blue: 190 / 255)
  static let achievementLevel2 = Color(red: 158 / 255, green: 152 / 255, blue: 146 / 255)
  static let achievementLevel3 = Color(red: 210 / 255, green: 152 / 255, blue: 88 / 255)
  static let achievementLevel4 = Color(red: 204 / 255, green: 108 / 255, blue: 36 / 255)

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

    /// Kompakte Kachel in der Podcast-„Shows“-Leiste (nicht identisch mit Buch-Cover-Ecken).
    static let podcastShelfCoverCorner: CGFloat = 12

    /// Horizontale Cover-Leiste: Podcast „Shows“ und Books „Browse“ (gleiche Maße).
    static let horizontalBrowseStripTile: CGFloat = 68
    /// Caption breiter als Kachel (`captionW = tile + labelWidthExtra`); Strip-Spalten mit
    /// `.leading` — die Extra-Breite liegt rechts der Kachel (nicht zentriert), damit die Kachel
    /// mit Library-Zeilen bündig ist; HStack-Abstand zieht `labelWidthExtra` ab.
    static let horizontalBrowseStripLabelWidthExtra: CGFloat = 12
    static let horizontalBrowseStripInterTileSpacing: CGFloat = max(
      0, withinSectionSpacing - horizontalBrowseStripLabelWidthExtra)
    /// Abstand Strip ↔ Großtitel oben.
    static let horizontalBrowseStripToTitleSpacing: CGFloat = 8
    /// Abstand Strip ↔ Scroll-Inhalt / Sektionsüberschrift unten.
    static let horizontalBrowseStripToContentSpacing: CGFloat = 16
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
    /// Mindesthöhe für Zeilen in gruppierten Karten (Settings, Stats, …).
    static let listRowMinHeight: CGFloat = 50
    /// Mindesthöhe für interaktive Settings-Zeilen (Toggle, Picker, Eingabe).
    static let settingsCardRowMinHeight: CGFloat = listRowMinHeight
    /// Nur-Lese- oder Nav-Zeilen (Username, Account Type, …).
    static let settingsCardCompactRowHeight: CGFloat = listRowMinHeight
    /// Horizontaler Innenabstand in Settings-Karten.
    static let settingsCardInsetHPadding: CGFloat = 16
    /// Vertikaler Innenabstand in mehrzeiligen Settings-Karten.
    static let settingsCardInsetVPadding: CGFloat = 4
    /// Vertikaler Abstand um Trennlinien zwischen Settings-Zeilen.
    static let settingsCardDividerSpacing: CGFloat = 6
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

  /// Wird nach Änderung der Akzentfarbe (Einstellungen) gepostet — für UIKit / manuelle Listener.
  static let appearanceAccentDidChangeNotification = Notification.Name(
    "abstandAppearanceAccentDidChange")

  /// Akzentfarbe setzen und System-Chrome (Tab-Bar) aktualisieren.
  static func applyAccent(_ color: Color) {
    accent = color
    let appearance = makeTabBarAppearance()
    applyTabBarAppearanceToUIKitProxy(appearance)
    refreshLiveTabBars(appearance: appearance)
    NotificationCenter.default.post(name: appearanceAccentDidChangeNotification, object: nil)
  }

  /// Keine schwebende graue Tab-Bar-Kapsel (iOS 18+); Icons behalten Accent-Farben.
  static func configureTabBarAppearance() {
    let appearance = makeTabBarAppearance()
    applyTabBarAppearanceToUIKitProxy(appearance)
  }

  private static func makeTabBarAppearance() -> UITabBarAppearance {
    let selectedAccent = UIColor(accent)
    let appearance = UITabBarAppearance()
    appearance.configureWithTransparentBackground()
    appearance.backgroundEffect = nil
    appearance.backgroundColor = .clear
    appearance.shadowColor = .clear

    let item = UITabBarItemAppearance()
    item.normal.iconColor = UIColor(white: 0.69, alpha: 1)
    item.selected.iconColor = selectedAccent
    appearance.stackedLayoutAppearance = item
    appearance.inlineLayoutAppearance = item
    appearance.compactInlineLayoutAppearance = item
    return appearance
  }

  private static func applyTabBarAppearanceToUIKitProxy(_ appearance: UITabBarAppearance) {
    let bar = UITabBar.appearance()
    bar.standardAppearance = appearance
    bar.scrollEdgeAppearance = appearance
    bar.tintColor = UIColor(accent)
    bar.isTranslucent = true
    bar.backgroundColor = .clear
    bar.barTintColor = .clear
  }

  /// Bereits sichtbare `UITabBar`-Instanzen (SwiftUI `TabView`) sofort aktualisieren.
  private static func refreshLiveTabBars(appearance: UITabBarAppearance) {
    let uiAccent = UIColor(accent)
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        refreshTabBars(in: window, appearance: appearance, uiAccent: uiAccent)
      }
    }
  }

  private static func refreshTabBars(
    in view: UIView,
    appearance: UITabBarAppearance,
    uiAccent: UIColor
  ) {
    if let tabBar = view as? UITabBar {
      tabBar.standardAppearance = appearance
      tabBar.scrollEdgeAppearance = appearance
      tabBar.tintColor = uiAccent
    }
    for subview in view.subviews {
      refreshTabBars(in: subview, appearance: appearance, uiAccent: uiAccent)
    }
  }
}

private struct ThemeAccentColorKey: EnvironmentKey {
  static let defaultValue: Color = AppTheme.defaultAccent
}

extension EnvironmentValues {
  /// Akzentfarbe aus Einstellungen → Appearance (via `.themeAccentFromAppModel` am Root).
  var themeAccent: Color {
    get { self[ThemeAccentColorKey.self] }
    set { self[ThemeAccentColorKey.self] = newValue }
  }
}

/// Fortschrittsstreifen am unteren Kartenrand (Library-Zeilen, Level-Achievements, …).
struct AbstandCardBottomProgress: View {
  @Environment(\.themeAccent) private var themeAccent

  var value: Double
  var height: CGFloat = AppTheme.Layout.libraryRowBottomProgressHeight
  var trackColor: Color = Color.white.opacity(0.14)
  /// `nil` = `themeAccent` aus der Environment (Appearance-Farbe).
  var fillColor: Color?

  private var resolvedFillColor: Color { fillColor ?? themeAccent }

  var body: some View {
    GeometryReader { geo in
      let w = max(0, geo.size.width)
      let t = min(1, max(0, value))
      ZStack(alignment: .leading) {
        Rectangle().fill(trackColor)
        Rectangle().fill(resolvedFillColor).frame(width: w * t)
      }
    }
    .frame(height: height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Progress")
    .accessibilityValue("\(Int(min(100, max(0, value * 100)))) percent")
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

/// Hintergrund unter ganzen Detail-Screen inkl. Tab-Bar — nicht nur ScrollView-Höhe.
private struct AbstandDetailScreenBackgroundModifier: ViewModifier {
  let tint: Color

  func body(content: Content) -> some View {
    ZStack {
      ZStack {
        AppTheme.background
        tint
      }
      .ignoresSafeArea()
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

extension View {
  /// Propagiert `AppModel.appearanceAccentColor` — Fortschrittsbalken & `.themeAccent` reagieren sofort.
  func themeAccentFromAppModel(_ model: AppModel) -> some View {
    environment(\.themeAccent, model.appearanceAccentColor)
  }

  /// System-Scrollmaterial ausblenden, App-Hintergrund (#121212) — für `ScrollView` und `List`.
  func abstandScrollScreenBackground(ignoreSafeArea: Bool = false) -> some View {
    modifier(AbstandScrollBackgroundModifier(ignoreSafeArea: ignoreSafeArea))
  }

  /// Volle Tab-Fläche inkl. Bereich unter der Navigationsleiste.
  func abstandTabScreenChrome() -> some View {
    frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(AppTheme.background)
  }

  /// Detail-Screens (Autor/Serie/Buch/Folge): Tint + `#121212` bis unter die Tab-Bar (nicht am ScrollView abgeschnitten).
  func abstandDetailScrollBackground(_ color: Color) -> some View {
    modifier(AbstandDetailScreenBackgroundModifier(tint: color))
      .abstandPushedDetailTabBarChrome()
  }

  /// Auf gepushten Details: schwebende System-Tab-Bar-Platte ausblenden.
  func abstandPushedDetailTabBarChrome() -> some View {
    toolbarBackgroundVisibility(.hidden, for: .tabBar)
      .toolbarBackground(.hidden, for: .tabBar)
  }

  /// Mindesthöhe für eine Zeile in `ServerAdminCard` / `StatsGroupedListCard`.
  func abstandCardListRowFrame(alignment: Alignment = .leading) -> some View {
    frame(
      maxWidth: .infinity,
      minHeight: AppTheme.Layout.listRowMinHeight,
      alignment: alignment
    )
  }

  /// Fixer horizontaler Browse-Strip direkt unter dem Tab-Großtitel (Library / Stats / Podcasts).
  /// Horizontales Einrücken nur im Strip-`ScrollView` (wie Tab-Scroll-Inhalt), nicht hier — sonst doppeltes Padding.
  func abstandFixedBrowseStripHeaderChrome() -> some View {
    padding(.top, AppTheme.Layout.horizontalBrowseStripToTitleSpacing)
      .padding(.bottom, AppTheme.Layout.horizontalBrowseStripToContentSpacing)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(AppTheme.background)
  }
}

/// Horizontaler Icon-/Cover-Strip unter dem Tab-Großtitel; Parent: `abstandFixedBrowseStripHeaderChrome()`.
struct AbstandHorizontalBrowseStripScroll<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      content()
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.vertical, AppTheme.Layout.horizontalBrowseStripVerticalPadding)
    }
    .contentMargins(.horizontal, 0, for: .scrollContent)
    .scrollContentBackground(.hidden)
  }
}

/// Großtitel → fixer Browse-Menüstreifen → scrollender Inhalt (einheitlich auf Library, Stats, Podcasts).
struct AbstandFixedBrowseStripTabLayout<Strip: View, ScrollBody: View>: View {
  var showsStrip: Bool = true
  let scrollBottomInset: CGFloat
  var onRefresh: (() async -> Void)?
  @ViewBuilder var strip: () -> Strip
  @ViewBuilder var scrollBody: () -> ScrollBody

  var body: some View {
    VStack(spacing: 0) {
      if showsStrip {
        strip().abstandFixedBrowseStripHeaderChrome()
      }
      scrollView
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .abstandScrollScreenBackground()
  }

  @ViewBuilder
  private var scrollView: some View {
    let base = ScrollView {
      scrollBody()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(
          .top,
          showsStrip ? 0 : AppTheme.Layout.tabTitleToHeaderBlockSpacing
        )
        .padding(.bottom, scrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .frame(maxWidth: .infinity, maxHeight: .infinity)

    if let onRefresh {
      base.refreshable { await onRefresh() }
    } else {
      base
    }
  }
}

/// Wie `AbstandFixedBrowseStripTabLayout`, aber je Sektion ein eigener `ScrollView` (Scrollposition bleibt erhalten).
/// Nur bereits besuchte Sektionen werden aufgebaut — verhindert N× schwere Listen (z. B. jede Podcast-Sendung).
struct AbstandFixedBrowseStripSectionsLayout<ID: Hashable, Strip: View, Content: View>: View {
  var showsStrip: Bool = true
  /// `false`: nur aktive Sektion (schneller Wechsel, z. B. Settings); `true`: besuchte Sektionen behalten Scroll-Position.
  var retainOffscreenSections: Bool = true
  let selection: ID
  let sectionIDs: [ID]
  let scrollBottomInset: CGFloat
  var onRefresh: (() async -> Void)?
  @ViewBuilder var strip: () -> Strip
  @ViewBuilder var sectionBody: (ID) -> Content

  @State private var mountedSectionIDs: Set<ID> = []

  var body: some View {
    VStack(spacing: 0) {
      if showsStrip {
        strip().abstandFixedBrowseStripHeaderChrome()
      }
      ZStack {
        ForEach(sectionIDs, id: \.self) { sectionID in
          if shouldRenderSection(sectionID) {
            sectionScrollView(for: sectionID)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .abstandScrollScreenBackground()
    .onAppear {
      if retainOffscreenSections {
        mountedSectionIDs.insert(selection)
      }
    }
    .onChange(of: selection) { _, newSelection in
      if retainOffscreenSections {
        mountedSectionIDs.insert(newSelection)
      }
    }
  }

  private func shouldRenderSection(_ sectionID: ID) -> Bool {
    retainOffscreenSections
      ? mountedSectionIDs.contains(sectionID)
      : selection == sectionID
  }

  @ViewBuilder
  private func sectionScrollView(for sectionID: ID) -> some View {
    let isSelected = selection == sectionID
    let base = ScrollView {
      sectionBody(sectionID)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(
          .top,
          showsStrip ? 0 : AppTheme.Layout.tabTitleToHeaderBlockSpacing
        )
        .padding(.bottom, scrollBottomInset)
    }
    .scrollContentBackground(.hidden)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .opacity(isSelected ? 1 : 0)
    .allowsHitTesting(isSelected)
    .accessibilityHidden(!isSelected)
    .zIndex(isSelected ? 1 : 0)

    if let onRefresh, isSelected {
      base.refreshable { await onRefresh() }
    } else {
      base
    }
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

/// Compact duration for pills and stats (e.g. „2 hrs 15 min“).
func formatPlaybackDurationShortHuman(_ seconds: Double) -> String {
  guard seconds.isFinite, seconds >= 0 else { return "< 1 min" }
  let s = Int(seconds.rounded())
  let h = s / 3600
  let m = (s % 3600) / 60
  if h == 0, m == 0 { return "< 1 min" }
  var parts: [String] = []
  if h > 0 { parts.append(h == 1 ? "1 hr" : "\(h) hrs") }
  if m > 0 { parts.append(m == 1 ? "1 min" : "\(m) min") }
  return parts.joined(separator: " ")
}
