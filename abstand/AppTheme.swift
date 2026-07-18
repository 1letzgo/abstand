import SwiftUI
import UIKit

/// Zentrale Farben und Abstände für die gesamte App.
enum AppTheme {
  private(set) static var palette: AppColorPalette = AppColorPalette.derived(
    from: defaultAccent, isDarkLike: true)

  static var background: Color { palette.background }
  static var card: Color { palette.card }
  static var textPrimary: Color { palette.textPrimary }
  static var textSecondary: Color { palette.textSecondary }
  static var progressTrack: Color { palette.progressTrack }
  static func foregroundOnAccent(_ accent: Color) -> Color {
    palette.foregroundOnAccent(accent)
  }
  static var heroCardShadow: Color { palette.heroCardShadow }
  static var cardShadow: Color { palette.cardShadow }
  static var coverPlayBadgeBackground: Color { palette.coverPlayBadgeBackground }

  /// Schatten-Metriken (Farbe kommt aus `AppColorPalette`).
  enum CardElevation {
    /// Browse-Icon-Kacheln, kleine Chips.
    case subtle
    /// Library-Zeilen, Achievements, Stats-Karten.
    case standard
    /// Continue-Hero-Karten.
    case hero

    var radius: CGFloat {
      switch self {
      case .subtle: Layout.cardShadowRadiusSubtle
      case .standard: Layout.cardShadowRadius
      case .hero: Layout.heroCardShadowRadius
      }
    }

    var y: CGFloat {
      switch self {
      case .subtle: Layout.cardShadowYSubtle
      case .standard: Layout.cardShadowY
      case .hero: Layout.heroCardShadowY
      }
    }
  }

  /// Dark-Mode-Akzent (Standard Gelb).
  static let defaultAccent = Color(red: 251 / 255, green: 192 / 255, blue: 45 / 255)
  /// Light-Mode-Akzent (Standard #00374A).
  static let defaultLightAccent = Color(red: 0 / 255, green: 55 / 255, blue: 74 / 255)
  /// Aktuelle Akzentfarbe (Standard: Gelb; überschreibbar in Einstellungen → Appearance).
  /// In SwiftUI-Views bevorzugt `Color.accentColor` (folgt `.tint` am Root). `AppTheme.accent` für UIKit/Charts.
  private(set) static var accent: Color = defaultAccent
  static let danger = Color(red: 0.92, green: 0.32, blue: 0.32)
  static let success = Color(red: 0.35, green: 0.82, blue: 0.55)

  /// Home-Browse „Expanding Dock“ — Layout; Farben über `Colors` aus Palette + Akzent.
  enum ExpandingDock {
    static let inactiveIconOpacity: CGFloat = 0.72

    static let itemSpacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 4
    static let circleSize: CGFloat = 46
    static let iconSize: CGFloat = 21
    static let activeCoverSize: CGFloat = 28
    static let activeHeight: CGFloat = 46
    static let activeLeadingPadding: CGFloat = 14
    static let activeTrailingPadding: CGFloat = 18
    static let iconLabelSpacing: CGFloat = 9
    static let centerWhenFewThreshold = 4

    static let selectionAnimation = Animation.spring(response: 0.32, dampingFraction: 0.72)

    static var inactiveIconSideInset: CGFloat { (circleSize - iconSize) / 2 }

    /// Theme-abhängige Dock-Farben (wie Continue-Hero-Play-Pille + Browse-Kacheln).
    struct Colors {
      let activeBackground: Color
      let activeForeground: Color
      let inactiveBackground: Color
      let inactiveForeground: Color
      let activeShadow: Color

      init(palette: AppColorPalette, accent: Color, inactiveBackground: Color? = nil) {
        activeBackground = accent
        activeForeground = palette.foregroundOnAccent(accent)
        self.inactiveBackground = inactiveBackground ?? palette.card
        inactiveForeground = palette.textSecondary
        activeShadow = palette.cardShadow
      }
    }
  }

  static func applyPalette(_ newPalette: AppColorPalette) {
    guard palette != newPalette else { return }
    palette = newPalette
    configureTabBarAppearance()
  }

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
    /// Etwas Luft für Karten-Schatten zwischen Zeilen/Blöcken.
    static let withinSectionSpacing: CGFloat = 14
    /// Buch-/Folgen-Detail: Titelblock → Play.
    static let detailPlayButtonTopPadding: CGFloat = 10
    /// Buch-/Folgen-Detail: Play → Metadaten (ohne Trennlinie).
    static let detailPlayButtonBottomPadding: CGFloat = 12
    /// Buch-/Folgen-Detail: Play → erster Meta-Block (visueller Übergang Hero → Details).
    static let detailMetaAfterPlaySpacing: CGFloat = 18
    /// Innenabstand Detail-Sektionskarten unterhalb Play.
    static let detailSectionCardPadding: CGFloat = 14
    static let detailSectionCardCornerRadius: CGFloat = 12
    /// Zusatz unter Scroll-Inhalten vor dem Tab-Bar-Zubehör (`nowPlayingAccessoryScrollBottomInset` kommt dazu).
    static let scrollBottomInsetBase: CGFloat = 24

    /// Kompakte Kachel in der Podcast-„Shows“-Leiste (nicht identisch mit Buch-Cover-Ecken).
    static let podcastShelfCoverCorner: CGFloat = 12
    /// Textfelder, Suchfeld-Chrome und kleine Control-Karten (gleicher Wert wie Podcast-Shelf).
    static let fieldCornerRadius: CGFloat = podcastShelfCoverCorner
    /// Kleine Cover-Thumbs / Chips in Metadata-Sheets.
    static let chipCornerRadius: CGFloat = 6
    /// Reader-Chrome-Hinweis (Material-Karte über dem EPUB).
    static let readerChromeCornerRadius: CGFloat = 20
    /// Level-Badge auf Achievement-Karten (regular).
    static let achievementBadgeCornerRadius: CGFloat = 10

    /// Abstand Strip ↔ Großtitel oben.
    static let horizontalBrowseStripToTitleSpacing: CGFloat = 8
    /// Abstand Strip ↔ Scroll-Inhalt / Sektionsüberschrift unten.
    static let horizontalBrowseStripToContentSpacing: CGFloat = 16
    static let horizontalBrowseStripVerticalPadding: CGFloat = 4

    /// „Continue listening“-Karten (horizontal scrollbar, einheitliche Höhe).
    static let continueHeroCardCornerRadius: CGFloat = 16
    static let continueHeroCardWidth: CGFloat = 176
    /// Quadrat wie die Kartenbreite: typisches Cover vollständig sichtbar (`scaledToFit`).
    static let continueHeroCoverMaxHeight: CGFloat = 176
    /// Abstand Titel ↔ Autor/Show (wie `BookRowCard` metadata `spacing: 2`).
    static let continueHeroMetadataTitleDetailSpacing: CGFloat = 2
    static let continueHeroMetadataVerticalPadding: CGFloat = 8
    /// Genau zwei Zeilen `headline` (wie `BookRowCard`, fester Slot).
    static let continueHeroMetadataTitleFixedHeight: CGFloat = 44
    /// Eine Zeile `.footnote` für Autor/Show (wie `LibraryRowCollapsedMetaLine`).
    static let continueHeroMetadataDetailFixedHeight: CGFloat = 20
    /// Abstand Autor-/Show-Zeile → Play-Pille.
    static let continueHeroMetadataPlayPillTopPadding: CGFloat = 8
    /// Höhe der Play-/Read-Pille (Capsule inkl. Innen-Padding).
    static let continueHeroMetadataPlayPillIntrinsicHeight: CGFloat = 34
    /// Abstand unter der Play-/Read-Pille (Continue Listening + Library-Cover-Karten).
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
    /// Metadaten unter dem Cover ohne Play-Pille (wie Continue-Hero-Textblock).
    static let libraryHeroMetadataBlockHeight: CGFloat =
      continueHeroMetadataVerticalPadding
      + continueHeroMetadataTitleFixedHeight
      + continueHeroMetadataTitleDetailSpacing
      + continueHeroMetadataDetailFixedHeight
      + continueHeroMetadataExtraBottomPadding

    static let cardCornerRadius: CGFloat = 14
    /// Karten-Schatten (siehe `abstandCardElevation`).
    static let cardShadowRadiusSubtle: CGFloat = 6
    static let cardShadowYSubtle: CGFloat = 2
    static let cardShadowRadius: CGFloat = 10
    static let cardShadowY: CGFloat = 4
    static let heroCardShadowRadius: CGFloat = 14
    static let heroCardShadowY: CGFloat = 6
    /// Mindesthöhe für Zeilen in gruppierten Karten (Settings, Stats, …).
    static let listRowMinHeight: CGFloat = 50
    /// Horizontaler Innenabstand in Settings-Karten.
    static let settingsCardInsetHPadding: CGFloat = 16
    /// Vertikaler Innenabstand in Settings-Karten (symmetrisch, ~iOS Inset Grouped).
    static let settingsCardInsetVPadding: CGFloat = 8
    /// Vertikaler Abstand um Trennlinien zwischen Settings-Zeilen.
    static let settingsCardDividerSpacing: CGFloat = 6
    /// Library-Zeilen — gleiche Abrundung wie Browse-/Podcast-Icon-Kacheln.
    static let libraryRowCornerRadius: CGFloat = podcastShelfCoverCorner
    static let coverCornerRadius: CGFloat = 11

    /// Cover in Library-Zeilen: festes 1:1 (`SquareCoverImageView`, Letterboxing mit Cover-Farbe).
    static let libraryRowCoverSide: CGFloat = 100
    /// Abstand Cover ↔ Textspalte in Library-Zeilen.
    static let libraryRowCardInset: CGFloat = 10
    /// Titel oben / Laufzeit unten (minimal zum Kartenrand).
    static let libraryRowTextInset: CGFloat = 6
    /// Höhe des Fortschrittsstreifens am unteren Kartenrand (Library-Zeilen).
    static let libraryRowBottomProgressHeight: CGFloat = 4

    /// Max. Breite für Formulare (Login, Settings-Sheets) auf großen Screens (iPad) — sonst
    /// laufen Textfelder/Buttons über die volle Breite oder hängen links im leeren Raum.
    static let readableFormMaxWidth: CGFloat = 480

    /// Facet-Kacheln (Narrators/Collections/Genres/Tags): adaptive statt starrer 2 Spalten —
    /// auf iPad passen so automatisch mehr Kacheln pro Zeile.
    static let facetTileGridColumns: [GridItem] = [
      GridItem(.adaptive(minimum: 160), spacing: withinSectionSpacing)
    ]
  }

  /// Akzentfarbe setzen und System-Chrome (Tab-Bar) aktualisieren.
  static func applyAccent(_ color: Color) {
    accent = color
    let appearance = makeTabBarAppearance()
    applyTabBarAppearanceToUIKitProxy(appearance)
    refreshLiveTabBars(appearance: appearance)
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
    item.normal.iconColor = UIColor(textSecondary)
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

private struct AppearanceThemeRevisionKey: EnvironmentKey {
  static let defaultValue = 0
}

/// In horizontalen Scroll-Reihen keine Karten-Schatten — sonst überlappen sie zu einem „Streifen“-BG.
private struct AbstandCardShadowEnabledKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  /// Akzentfarbe aus Einstellungen → Appearance (via `.themeAccentFromAppModel` am Root).
  var themeAccent: Color {
    get { self[ThemeAccentColorKey.self] }
    set { self[ThemeAccentColorKey.self] = newValue }
  }

  /// Inkrement bei Paletten- + Akzent-Wechsel — Views mit `AppTheme.*` / `.tint` müssen das lesen.
  var appearanceThemeRevision: Int {
    get { self[AppearanceThemeRevisionKey.self] }
    set { self[AppearanceThemeRevisionKey.self] = newValue }
  }

  var abstandCardShadowEnabled: Bool {
    get { self[AbstandCardShadowEnabledKey.self] }
    set { self[AbstandCardShadowEnabledKey.self] = newValue }
  }
}

/// Entfernt den opaken UIScrollView-Hintergrund (SwiftUI-ScrollView).
struct AbstandUIScrollViewClearBackground: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    DispatchQueue.main.async {
      Self.clearScrollViews(startingAt: uiView)
    }
  }

  private static func clearScrollViews(startingAt view: UIView) {
    var ancestor: UIView? = view.superview
    while let current = ancestor {
      if let scroll = current as? UIScrollView {
        scroll.backgroundColor = .clear
        scroll.isOpaque = false
        for sub in scroll.subviews {
          sub.backgroundColor = .clear
        }
        return
      }
      ancestor = current.superview
    }
  }
}

/// App-Hintergrundfarbe; neu zeichnen wenn Dark ↔ Sepia wechselt.
struct AppThemeScreenBackground: View {
  @EnvironmentObject private var model: AppModel
  var ignoresSafeArea = false

  var body: some View {
    Group {
      if ignoresSafeArea {
        model.appearancePalette.background.ignoresSafeArea()
      } else {
        model.appearancePalette.background
      }
    }
  }
}

/// Fortschrittsstreifen am unteren Kartenrand (Library-Zeilen, Level-Achievements, …).
struct AbstandCardBottomProgress: View {
  @Environment(\.themeAccent) private var themeAccent

  var value: Double
  var height: CGFloat = AppTheme.Layout.libraryRowBottomProgressHeight
  var trackColor: Color = AppTheme.progressTrack
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
  @EnvironmentObject private var model: AppModel
  var ignoreSafeArea = false

  func body(content: Content) -> some View {
    let background = model.appearancePalette.background
    return content
      .scrollContentBackground(.hidden)
      .background {
        if ignoreSafeArea {
          background.ignoresSafeArea()
        } else {
          background
        }
      }
  }
}

private struct AbstandTabScreenChromeModifier: ViewModifier {
  @EnvironmentObject private var model: AppModel

  func body(content: Content) -> some View {
    let background = model.appearancePalette.background
    return content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(background)
      .toolbarBackground(background, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
  }
}

/// Hintergrund unter ganzen Detail-Screen inkl. Tab-Bar — nicht nur ScrollView-Höhe.
private struct AbstandDetailScreenBackgroundModifier: ViewModifier {
  @EnvironmentObject private var model: AppModel
  let tint: Color

  func body(content: Content) -> some View {
    let background = model.appearancePalette.background
    return ZStack {
      ZStack {
        background
        if model.appearancePalette.isDarkLike {
          tint
        } else {
          tint.opacity(0.52)
        }
      }
      .ignoresSafeArea()
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

private struct AbstandThemeRefreshModifier: ViewModifier {
  @Environment(\.appearanceThemeRevision) private var themeRevision

  func body(content: Content) -> some View {
    let _ = themeRevision
    content
  }
}

extension View {
  /// Liest `appearanceThemeRevision`, damit statische `AppTheme.*`-Farben neu gebunden werden.
  func abstandThemeRefresh() -> some View {
    modifier(AbstandThemeRefreshModifier())
  }

  /// Propagiert `AppModel.appearanceAccentColor` — Fortschrittsbalken & `.themeAccent` reagieren sofort.
  func themeAccentFromAppModel(_ model: AppModel) -> some View {
    self
      .environment(\.themeAccent, model.appearanceAccentColor)
      .environment(\.appearanceThemeRevision, model.appearanceThemeRevision)
  }

  /// System-Scrollmaterial ausblenden, App-Hintergrund (#121212) — für `ScrollView` und `List`.
  func abstandScrollScreenBackground(ignoreSafeArea: Bool = false) -> some View {
    modifier(AbstandScrollBackgroundModifier(ignoreSafeArea: ignoreSafeArea))
  }

  /// Volle Tab-Fläche inkl. Bereich unter der Navigationsleiste.
  func abstandTabScreenChrome() -> some View {
    modifier(AbstandTabScreenChromeModifier())
  }

  /// Home-Tab: Großtitel + sichtbare Nav-Bar (wie Library/Podcasts).
  func abstandHomeTabNavigationTitle() -> some View {
    navigationTitle(AppModel.MainTab.start.rawValue)
      .toolbarTitleDisplayMode(.inlineLarge)
      .toolbar(.visible, for: .navigationBar)
      .toolbarVisibility(.visible, for: .navigationBar)
      .toolbarVisibility(.visible, for: .automatic)
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

  /// Mindesthöhe für eine Zeile in `AbstandGroupedCard` / `StatsGroupedListCard`.
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
    modifier(AbstandBrowseStripHeaderChromeModifier())
  }
}

private struct AbstandBrowseStripHeaderChromeModifier: ViewModifier {
  @EnvironmentObject private var model: AppModel

  func body(content: Content) -> some View {
    content
      .padding(.top, AppTheme.Layout.horizontalBrowseStripToTitleSpacing)
      .padding(.bottom, AppTheme.Layout.horizontalBrowseStripToContentSpacing)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct AbstandTopScrollEdgeEffectModifier: ViewModifier {
  let style: ScrollEdgeEffectStyle?

  func body(content: Content) -> some View {
    if let style {
      content.scrollEdgeEffectStyle(style, for: .top)
    } else {
      content
    }
  }
}

/// Horizontale Scroll-Reihe (Browse-Menü, Continue Listening, …).
struct AbstandHorizontalBrowseStripScroll<Content: View>: View {
  /// `true`: volle Tab-Breite, Inset per `contentMargins` (fixer Browse-Streifen).
  /// `false`: Parent hat bereits `.padding(.horizontal, tabPaddingH)` — kein doppeltes Inset.
  var appliesHorizontalContentInset: Bool = true
  var verticalContentPadding: CGFloat = AppTheme.Layout.horizontalBrowseStripVerticalPadding
  @ViewBuilder var content: () -> Content

  var body: some View {
    let scroll = ScrollView(.horizontal, showsIndicators: false) {
      content()
        .padding(.vertical, verticalContentPadding)
    }
    .scrollContentBackground(.hidden)

    Group {
      if appliesHorizontalContentInset {
        scroll
          .contentMargins(.horizontal, AppTheme.Layout.tabPaddingH, for: .scrollContent)
      } else {
        scroll
      }
    }
    .abstandHorizontalScrollRow()
    .abstandThemeRefresh()
  }
}

/// Eintrag im Icon-Menüstreifen (Home, Library, Stats, Settings, Podcasts).
struct AbstandBrowseStripItem: Identifiable, Hashable {
  let id: String
  let label: String
  let systemImage: String
  /// Optional: Cover statt SF Symbol (z. B. Podcast-Sendungen).
  var coverItemId: String?
}

/// Horizontales Kategorie-Menü (Expanding Dock) — Home, Library, Stats, Settings.
struct AbstandBrowseStripIconMenu: View {
  let items: [AbstandBrowseStripItem]
  let selectionID: String
  /// `false`: kein Leading-Padding (z. B. als Sekundär-Strip nach einem Pinned-Bereich).
  var appliesLeadingPadding: Bool = true
  let onSelect: (String) -> Void

  var body: some View {
    AbstandExpandingDockBrowseStrip(
      items: items,
      selectionID: selectionID,
      appliesLeadingPadding: appliesLeadingPadding,
      onSelect: onSelect
    )
  }
}

/// Großtitel → fixer Browse-Menüstreifen → je Sektion ein eigener `ScrollView` (Scrollposition bleibt erhalten).
/// Nur bereits besuchte Sektionen werden aufgebaut — verhindert N× schwere Listen (z. B. jede Podcast-Sendung).
struct AbstandFixedBrowseStripSectionsLayout<ID: Hashable, Strip: View, Content: View>: View {
  @EnvironmentObject private var model: AppModel

  var showsStrip: Bool = true
  /// `false`: nur aktive Sektion (schneller Wechsel, z. B. Settings); `true`: besuchte Sektionen behalten Scroll-Position.
  var retainOffscreenSections: Bool = true
  /// Tab-Wechsel o. Ä.: gespeicherte Scroll-Position erneut anwenden, damit Lazy-Inhalte layouten.
  var relayoutTrigger: AnyHashable?
  /// Wenn sich dieser Wert ändert (z. B. `nowPlayingAccessoryScrollBottomInset` 56↔0, wenn die
  /// Floating Bar erscheint/verschwindet), wird die Scroll-Position revalidiert. Ohne das behält
  /// `sectionScrollPositions` eine veraltete Position für die alte Content-Höhe → weißer View.
  var bottomInsetRevalidationTrigger: AnyHashable?
  /// Sort/Filter: Katalog wird auf Seite 0 ersetzt. Scroll muss nach oben — nicht `relayoutTrigger`
  /// nutzen, der die alte (tiefe) Position erneut anwenden und den weißen Viewport auslösen würde.
  var scrollToTopTrigger: AnyHashable?
  let selection: ID
  let sectionIDs: [ID]
  let scrollBottomInset: CGFloat
  /// Home-Nav: Trailing-Toolbar bleibt beim Scrollen sichtbar (iOS 26 Scroll-Edge).
  var topScrollEdgeEffectStyle: ScrollEdgeEffectStyle?
  var onRefresh: (() async -> Void)?
  @ViewBuilder var strip: () -> Strip
  @ViewBuilder var sectionBody: (ID) -> Content

  @State private var mountedSectionIDs: Set<ID> = []
  @State private var sectionScrollPositions: [ID: ScrollPosition] = [:]

  var body: some View {
    let screenBackground = model.appearancePalette.background
    VStack(spacing: 0) {
      if showsStrip {
        strip().abstandFixedBrowseStripHeaderChrome()
      }
      ZStack {
        screenBackground
        if shouldRenderSection(selection) {
          sectionScrollView(for: selection, screenBackground: screenBackground)
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
    .onChange(of: relayoutTrigger) { _, _ in
      guard relayoutTrigger != nil else { return }
      DebugLogCollector.shared.log("layout onChange relayoutTrigger selection=\(String(describing: selection))")
      reapplyScrollPosition(for: selection)
    }
    .onChange(of: bottomInsetRevalidationTrigger) { _, newValue in
      DebugLogCollector.shared.log("layout onChange bottomInsetRevalidationTrigger newValue=\(String(describing: newValue)) selection=\(String(describing: selection))")
      reapplyScrollPosition(for: selection)
    }
    .onChange(of: scrollToTopTrigger) { _, _ in
      guard scrollToTopTrigger != nil else { return }
      DebugLogCollector.shared.log("layout onChange scrollToTopTrigger selection=\(String(describing: selection))")
      scrollActiveSectionToTop()
    }
  }

  private func shouldRenderSection(_ sectionID: ID) -> Bool {
    // Die aktive Sektion wird IMMER gerendert — `mountedSectionIDs` steuert nur, ob
    // zusätzlich besuchte (inaktive) Sektionen offscreen behalten werden.
    if selection == sectionID { return true }
    return retainOffscreenSections
      ? mountedSectionIDs.contains(sectionID)
      : false
  }

  private func scrollPositionBinding(for sectionID: ID) -> Binding<ScrollPosition> {
    Binding(
      get: { sectionScrollPositions[sectionID] ?? ScrollPosition(edge: .top) },
      set: { sectionScrollPositions[sectionID] = $0 }
    )
  }

  /// Nach Tab-Wechsel: gespeicherte Offset-Position erneut setzen → Lazy-Inhalte layouten.
  private func reapplyScrollPosition(for sectionID: ID) {
    let saved = sectionScrollPositions[sectionID]
    sectionScrollPositions[sectionID] = nil
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 32_000_000)
      sectionScrollPositions[sectionID] = saved ?? ScrollPosition(edge: .top)
    }
  }

  /// Sort/Filter/Delete: aktive Sektion an den Anfang.
  /// Zuerst `nil` (wie `reapplyScrollPosition`), sonst bleibt ein point-basierter Offset past
  /// Content erhalten → weißer Viewport / kein Scrollen mehr (SwiftUI clamped Edge, nicht Point).
  private func scrollActiveSectionToTop() {
    sectionScrollPositions[selection] = nil
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 32_000_000)
      sectionScrollPositions[selection] = ScrollPosition(edge: .top)
    }
  }

  @ViewBuilder
  private func sectionScrollView(for sectionID: ID, screenBackground: Color) -> some View {
    // Horizontales Inset per `contentMargins` — nicht als Padding auf `scrollTargetLayout`,
    // sonst falsche Scroll-Breite (Settings-Karten ragen links aus dem Rand).
    let base = ScrollView {
      sectionBody(sectionID)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(
          .top,
          showsStrip ? 0 : AppTheme.Layout.tabTitleToHeaderBlockSpacing
        )
        .padding(.bottom, scrollBottomInset)
        .background(screenBackground)
        .scrollTargetLayout()
    }
    .contentMargins(.horizontal, AppTheme.Layout.tabPaddingH, for: .scrollContent)
    .scrollPosition(scrollPositionBinding(for: sectionID))
    .scrollContentBackground(.hidden)
    .background(screenBackground)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .id(sectionID)
    .modifier(AbstandTopScrollEdgeEffectModifier(style: topScrollEdgeEffectStyle))

    if let onRefresh {
      base.refreshable { await onRefresh() }
    } else {
      base
    }
  }
}

// MARK: - Design system (Karten, Buttons, Felder, Ladeindikatoren)

/// Gruppierte Kartenfläche (Settings, Stats, Admin).
struct AbstandGroupedCard<Content: View>: View {
  @EnvironmentObject private var model: AppModel
  var horizontalPadding: CGFloat = AppTheme.Layout.settingsCardInsetHPadding
  var verticalPadding: CGFloat = AppTheme.Layout.settingsCardInsetVPadding
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, horizontalPadding)
    .padding(.vertical, verticalPadding)
    .background(model.appearancePalette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }
}

private struct AbstandCardElevationModifier: ViewModifier {
  @EnvironmentObject private var model: AppModel
  @Environment(\.abstandCardShadowEnabled) private var cardShadowEnabled
  let elevation: AppTheme.CardElevation

  private var shadowColor: Color {
    switch elevation {
    case .hero: model.appearancePalette.heroCardShadow
    case .subtle, .standard: model.appearancePalette.cardShadow
    }
  }

  func body(content: Content) -> some View {
    if cardShadowEnabled {
      content
        .compositingGroup()
        .shadow(color: shadowColor, radius: elevation.radius, x: 0, y: elevation.y)
    } else {
      content
    }
  }
}

/// Primäraktion (Login, Bestätigen) — Appearance-Akzent mit Druck-Feedback.
struct AbstandPrimaryButtonStyle: ButtonStyle {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .foregroundStyle(model.appearancePalette.foregroundOnAccent(themeAccent))
      .background(
        RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
          .fill(themeAccent.opacity(Self.fillOpacity(isPressed: configuration.isPressed, isEnabled: isEnabled)))
      )
      .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }

  fileprivate static func fillOpacity(isPressed: Bool, isEnabled: Bool) -> Double {
    guard isEnabled else { return 0.35 }
    return isPressed ? 0.88 : 1
  }
}

/// Kompakte Primäraktion (Suche, Subscribe, Retry) — Appearance-Akzent ohne Vollbreite.
struct AbstandProminentButtonStyle: ButtonStyle {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.isEnabled) private var isEnabled

  /// Transport-Play u.ä.: Kapsel; Label liefert die Größe (kein Extra-Padding).
  var capsule = false

  func makeBody(configuration: Configuration) -> some View {
    let fill = themeAccent.opacity(
      AbstandPrimaryButtonStyle.fillOpacity(isPressed: configuration.isPressed, isEnabled: isEnabled)
    )
    configuration.label
      .font(.body.weight(.semibold))
      .padding(.horizontal, capsule ? 0 : 14)
      .padding(.vertical, capsule ? 0 : 8)
      .foregroundStyle(model.appearancePalette.foregroundOnAccent(themeAccent))
      .background {
        if capsule {
          Capsule(style: .continuous).fill(fill)
        } else {
          RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
            .fill(fill)
        }
      }
      .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// Expanding-Dock-Chips ohne System-Rahmen/Glass.
struct AbstandExpandingDockButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.9 : 1)
  }
}

/// Beschriftetes Eingabefeld (Login, Formulare).
struct AbstandLabeledTextField: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  @Binding var text: String
  var isSecure = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.medium))
        .foregroundStyle(model.appearancePalette.textSecondary)
      Group {
        if isSecure {
          SecureField("", text: $text)
        } else {
          TextField("", text: $text)
        }
      }
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .foregroundStyle(model.appearancePalette.textPrimary)
      .background(model.appearancePalette.card)
      .clipShape(
        RoundedRectangle(cornerRadius: AppTheme.Layout.fieldCornerRadius, style: .continuous)
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .abstandThemeRefresh()
  }
}

/// Zentrierter Lade-Spinner in Listen/Sheets.
struct AbstandLoadingSpinner: View {
  @Environment(\.themeAccent) private var themeAccent
  var controlSize: ControlSize = .large
  var verticalPadding: CGFloat = 48
  var scale: CGFloat = 1

  var body: some View {
    ProgressView()
      .controlSize(controlSize)
      .tint(themeAccent)
      .scaleEffect(scale)
      .frame(maxWidth: .infinity)
      .padding(.vertical, verticalPadding)
  }
}

private struct AbstandSearchFieldChromeModifier: ViewModifier {
  @EnvironmentObject private var model: AppModel

  func body(content: Content) -> some View {
    content
      .padding(12)
      .background(model.appearancePalette.card)
      .clipShape(
        RoundedRectangle(cornerRadius: AppTheme.Layout.fieldCornerRadius, style: .continuous)
      )
      .abstandThemeRefresh()
  }
}

private struct AbstandAccentForegroundModifier: ViewModifier {
  @Environment(\.themeAccent) private var themeAccent

  func body(content: Content) -> some View {
    content.foregroundStyle(themeAccent)
  }
}

extension View {
  /// Suchfeld-Hintergrund (Karte, abgerundet) — Inhalt (HStack + TextField) von außen.
  func abstandSearchFieldChrome() -> some View {
    modifier(AbstandSearchFieldChromeModifier())
  }

  /// Tippbare Metadaten-Links (Autor, Serie, Show).
  func abstandAccentForeground() -> some View {
    modifier(AbstandAccentForegroundModifier())
  }

  /// Tiefe unter abgerundeten Karten — nach `.clipShape` anwenden.
  func abstandCardElevation(_ elevation: AppTheme.CardElevation = .standard) -> some View {
    modifier(AbstandCardElevationModifier(elevation: elevation))
  }

  /// Horizontale Menü-/Carousel-Zeile: kein Schatten-Bleed, UIScrollView transparent.
  func abstandHorizontalScrollRow() -> some View {
    environment(\.abstandCardShadowEnabled, false)
      .background { AbstandUIScrollViewClearBackground() }
  }

  /// Dezente Kante statt Schatten (Continue-Hero in horizontaler Reihe).
  func abstandHeroCardOutline(palette: AppColorPalette) -> some View {
    overlay {
      RoundedRectangle(
        cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius,
        style: .continuous
      )
      .strokeBorder(palette.textSecondary.opacity(0.22), lineWidth: 1)
    }
  }
}

/// Kategoriezeile über Browse-Strips und Listen (Home, Library, Podcasts, Stats).
struct TabContentSectionTitle: View {
  @EnvironmentObject private var model: AppModel
  let title: String

  var body: some View {
    Text(title)
      .font(.title3)
      .bold()
      .foregroundStyle(model.appearancePalette.textPrimary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
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
