import SwiftUI
import UIKit

// MARK: - Home tab root

/// Eigener View-Typ — stabile Identität; Nav-Bar + Offline-Button überleben Bootstrap-Schritte.
struct HomeTabRootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    NavigationStack {
      ZStack {
        StartDashboardView()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .abstandTabScreenChrome()
      .abstandHomeTabNavigationTitle()
      .toolbar {
        HomeGoOfflineToolbarContent()
      }
      .task(id: "\(model.sessionUserId)-\(model.isAppBootstrapInProgress)") {
        guard !model.isAppBootstrapInProgress else { return }
        await model.probeServerConnectionIfNeeded()
      }
      .booksEntityDetailNavigation(for: .start)
    }
  }
}

/// Nav-Bar-Trailing — statischer Offline-Schalter, rechts daneben der Zugang zu Settings
/// (Settings ist kein eigener Tab mehr, sondern wird auf den Home-Stack gepusht).
struct HomeGoOfflineToolbarContent: ToolbarContent {
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      HomeGoOfflineToolbarButton()
      HomeSettingsToolbarButton()
    }
  }
}

struct HomeSettingsToolbarButton: View {
  var body: some View {
    NavigationLink {
      SettingsScreen()
    } label: {
      Label("Settings", systemImage: "gearshape")
        .labelStyle(.iconOnly)
    }
    .accessibilityLabel("Settings")
    .accessibilityIdentifier("home-settings-toolbar-button")
  }
}

/// Settings als gepushte Seite auf dem Home-Stack — Inhalt unverändert der frühere Settings-Tab.
struct SettingsScreen: View {
  var body: some View {
    SettingsHubRootView()
      .abstandTabScreenChrome()
      .navigationTitle("Settings")
      .toolbarTitleDisplayMode(.inline)
  }
}

struct HomeGoOfflineToolbarButton: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Button {
      model.homeGoOfflineToolbarTapped()
    } label: {
      Label {
        Text(buttonTitle)
      } icon: {
        Image(systemName: buttonIcon)
      }
      .labelStyle(.iconOnly)
    }
    .accessibilityLabel(buttonTitle)
    .accessibilityIdentifier("home-go-offline-toolbar-button")
  }

  private var buttonTitle: String {
    model.offlineHomeUIActive ? "Go online" : "Go offline"
  }

  private var buttonIcon: String {
    model.offlineHomeUIActive ? "icloud.slash" : "icloud"
  }
}

// MARK: - Home dashboard

struct StartDashboardView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    startDashboardOnlineLayout
      .abstandScrollScreenBackground()
      .task(
        id: "\(model.offlineHomeUIActive)-\(model.sessionUserId)-\(model.isAppBootstrapInProgress)-\(model.hasCachedBootstrapContent)"
      ) {
        guard model.startShelves.isEmpty,
          !model.isAppBootstrapInProgress,
          !model.hasCachedBootstrapContent
        else { return }
        if model.offlineHomeUIActive {
          await model.loadStartDashboard(force: true)
        } else {
          await model.loadStartDashboard()
        }
      }
      .task(id: "levels-\(model.sessionUserId)-\(model.isAppBootstrapInProgress)") {
        // Cache-first: Snapshot aus SwiftData sofort, Server-Stats nur verzögert und gedrosselt.
        guard !model.isAppBootstrapInProgress else { return }
        await model.refreshHomeListeningLevelsIfStale()
      }
      .onChange(of: model.offlineHomeUIActive) { _, _ in
        guard !model.isAppBootstrapInProgress else { return }
        model.clampHomeBrowseSectionIfNeeded()
        // Dashboard-Reload steuert allein die Mode-Transition im Model — kein paralleles force-Load.
      }
  }

  // MARK: - Home tab

  private var startDashboardOnlineLayout: some View {
    let isRestoringContinue = model.isHomeContinueRestoreInProgress
    let continueID = ABSStartShelfLocalization.homeBrowseContinueSectionID
    // Kein Browse-Menü mehr — Stats liegt in Settings; Home zeigt nur Dashboard-Inhalte.
    return AbstandFixedBrowseStripSectionsLayout(
      showsStrip: false,
      // Stats-Karte bzw. ihre Wochenzeilen erscheinen/verschwinden → Inhaltshöhe ändert sich, neu anwenden.
      relayoutTrigger: AnyHashable(homeListeningSummaryLayoutKey),
      bottomInsetRevalidationTrigger: model.nowPlayingAccessoryScrollBottomInset,
      selection: continueID,
      sectionIDs: [continueID],
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      topScrollEdgeEffectStyle: .soft,
      onRefresh: { await model.refreshStartTabPullToRefresh() }
    ) {
      Color.clear
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    } sectionBody: { _ in
      if isRestoringContinue {
        homeBrowseContentBootstrapPlaceholder
      } else if !model.isAnyHomeBrowseContinueShelfEnabled {
        startDashboardAllShelvesDisabledState
          .frame(maxWidth: .infinity)
      } else {
        startDashboardContinueCombinedContent()
      }
    }
    .onAppear {
      model.homeBrowseCategory = continueID
      model.clampHomeBrowseSectionIfNeeded()
    }
    .onChange(of: model.startDisabledCategories) { _, _ in
      model.clampHomeBrowseSectionIfNeeded()
    }
    .onChange(of: model.startSettingsCategoryList.count) { _, _ in
      model.clampHomeBrowseSectionIfNeeded()
    }
  }

  /// Hält den Home-Inhalt kurz leer, bis alle lokal rekonstruierten Continue-Regale atomar vorliegen.
  private var homeBrowseContentBootstrapPlaceholder: some View {
    Color.clear
      .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.homeBrowseBootstrapMinHeight)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private func startDashboardContinueCombinedContent() -> some View {
    let allShelves = model.startShelves(
      forHomeBrowseSection: ABSStartShelfLocalization.homeBrowseContinueSectionID
    )
    let shelves = allShelves.filter(startDashboardShelfHasVisibleContent)
    // Stats-Karte erst, wenn ein Stats-Snapshot vorliegt (Cache oder Server) — vorher kein Platzhalter.
    let listeningSummary = homeListeningSummary
    // Ohne „Continue listening“-Regal steht die Karte ganz oben; sonst in dessen Slot (auch wenn es leer ist).
    let hasContinueSlot = allShelves.contains(where: startDashboardIsContinueListeningShelf)
    if shelves.isEmpty {
      VStack(alignment: .leading, spacing: AppTheme.Layout.homeSectionSpacing) {
        if let listeningSummary {
          HomeListeningSummaryCard(summary: listeningSummary).equatable()
        }
        startDashboardSectionEmptyState(category: ABSStartShelfLocalization.homeBrowseContinueSectionID)
      }
    } else {
      VStack(alignment: .leading, spacing: AppTheme.Layout.homeSectionSpacing) {
        if let listeningSummary, !hasContinueSlot {
          HomeListeningSummaryCard(summary: listeningSummary).equatable()
        }
        ForEach(allShelves) { shelf in
          if startDashboardShelfHasVisibleContent(shelf)
            || (listeningSummary != nil && startDashboardIsContinueListeningShelf(shelf))
          {
            startDashboardShelfContent(shelf, listeningSummary: listeningSummary)
          }
        }
      }
    }
  }

  /// Werte der Stats-Karte; `nil`, solange kein Stats-Snapshot geladen ist (Cache oder Server).
  private var homeListeningSummary: HomeListeningSummary? {
    let snapshot = model.listeningAchievementsSnapshot
    guard snapshot.savedAt != nil, !snapshot.achievements.isEmpty else { return nil }
    return HomeListeningSummary(snapshot: snapshot, stats: model.listeningStats)
  }

  /// Layout-Schlüssel der Stats-Karte: sichtbar / mit Wochenwerten.
  private var homeListeningSummaryLayoutKey: String {
    guard let summary = homeListeningSummary else { return "none" }
    return summary.weekActiveDays == nil ? "snapshot" : "week"
  }

  private func startDashboardShelfHasVisibleContent(_ shelf: ABSStartShelfSection) -> Bool {
    shelf.hasBooks || shelf.hasPodcastEpisodes || shelf.hasSeries || shelf.hasAuthors
  }

  @ViewBuilder
  private func startDashboardShelfContent(
    _ shelf: ABSStartShelfSection,
    listeningSummary: HomeListeningSummary?
  ) -> some View {
    if startDashboardIsContinueListeningShelf(shelf) {
      VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        if shelf.hasBooks || shelf.hasPodcastEpisodes {
          startDashboardContinueListeningSection(shelf)
        }
        if let listeningSummary {
          HomeListeningSummaryCard(summary: listeningSummary).equatable()
        }
        if shelf.hasAuthors {
          startDashboardAuthorsSection(
            title: shelf.displayTitle,
            authors: shelf.authors
          )
        }
      }
    } else {
      // Alle anderen Settings-Regale: Kompaktkarten (≈ 3/4 Breite), ohne Play — nur Link zur Detailseite.
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        TabContentSectionTitle(title: shelf.displayTitle)
        if shelf.hasBooks {
          HomeBooksCompactCarousel(
            books: shelf.books,
            usesEbookProgressDisplay: shelf.category == "continueEbooks"
          )
        }
        if shelf.hasSeries {
          HomeSeriesCompactCarousel(series: shelf.series)
        }
        if shelf.hasAuthors {
          HomeAuthorsCompactCarousel(authors: shelf.authors)
        }
        if shelf.hasPodcastEpisodes {
          HomePodcastEpisodesCompactCarousel(episodes: shelf.podcastEpisodes)
        }
      }
    }
  }

  @ViewBuilder
  private func startDashboardAuthorsSection(
    title: String,
    authors: [ABSAuthorShelfEntity]
  ) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: title)
      HomeAuthorsCoverCardCarousel(authors: authors)
    }
  }

  private func startDashboardSectionEmptyState(category: String) -> some View {
    let label: String = {
      if category == ABSStartShelfLocalization.homeBrowseContinueSectionID {
        return ABSStartShelfLocalization.homeBrowseContinueStripLabel
      }
      if category == ABSStartShelfLocalization.homeBrowseRecentSectionID {
        return ABSStartShelfLocalization.homeBrowseRecentStripLabel
      }
      return model.startSettingsCategoryList.first { $0.category == category }?.label
        ?? ABSStartShelfLocalization.displayTitle(category: category, serverLabel: "")
    }()
    let description: String = {
      guard model.offlineHomeUIActive else {
        return "Content for this shelf appears when your server provides it."
      }
      return "Titles you're currently playing will appear here once downloaded."
    }()
    return ContentUnavailableView(
      label,
      systemImage: ABSStartShelfLocalization.stripSystemImage(category: category),
      description: Text(description)
    )
    .frame(maxWidth: .infinity)
    .padding(.top, AppTheme.Layout.sectionSpacing)
  }

  private func startDashboardIsContinueListeningShelf(_ shelf: ABSStartShelfSection) -> Bool {
    shelf.category == "recentlyListened"
  }

  @ViewBuilder
  private func startDashboardContinueListeningSection(_ shelf: ABSStartShelfSection) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: shelf.displayTitle)
      ContinueListeningHeroCarousel(shelf: shelf)
    }
  }

  private var startDashboardAllShelvesDisabledState: some View {
    ContentUnavailableView(
      "All shelves are off",
      systemImage: "gearshape.2",
      description: Text("Open Settings → Appearance → Home to turn shelves back on.")
    )
  }

}

// MARK: - Home: Stats-Karte (Settings → Stats)

/// Werte der Home-Stats-Karte — nur aus vorhandenen Stats: Streak und „Finished books“ aus dem
/// Achievement-Snapshot (wie Settings → Stats → Level), Wochenwerte aus den Tageswerten der Hörstatistik.
struct HomeListeningSummary: Equatable {
  /// „Current streak“-Achievement (Tage).
  let streakDays: Int
  /// „Finished books“-Achievement inkl. Stufe und Fortschritt zur nächsten.
  let finishedBooks: ListeningAchievementState?
  /// Hörzeit der laufenden Woche; `nil` ohne Tageswerte im Cache.
  let weekSeconds: Int?
  /// Je Wochentag (ab Wochenanfang laut Kalender), ob gehört wurde; `nil` ohne Tageswerte.
  let weekActiveDays: [Bool]?
  /// Einbuchstabige Wochentage in derselben Reihenfolge („M T W …“).
  let weekdaySymbols: [String]

  @MainActor
  init(snapshot: ListeningAchievementsSnapshot, stats: ABSListeningStatsResponse?) {
    streakDays = snapshot.achievements.first { $0.kind == .currentStreak }?.currentValue ?? 0
    finishedBooks = snapshot.achievements.first { $0.kind == .finishedBooks }
    let calendar = Calendar.current
    let week = stats?.currentWeekActivity(calendar: calendar)
    weekSeconds = week?.seconds
    weekActiveDays = week?.activeDays
    // UI-Texte englisch, Wochenanfang aber nach Nutzer-Kalender.
    var english = Calendar(identifier: .gregorian)
    english.locale = Locale(identifier: "en_US")
    let symbols = english.veryShortStandaloneWeekdaySymbols
    let start = max(0, calendar.firstWeekday - 1) % max(symbols.count, 1)
    weekdaySymbols = Array(symbols[start...] + symbols[..<start])
  }
}

/// Home-Stats-Karte unter „Continue listening“: Kopfzeile + drei Spalten (Streak · Finished books · diese
/// Woche) mit senkrechten Haarlinien. Tippen öffnet die Stats-Seite.
/// `Equatable` + kein `@EnvironmentObject`: rendert nur neu, wenn sich die Werte ändern.
private struct HomeListeningSummaryCard: View, Equatable {
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .title2) private var ringEdge = Metrics.ringEdge
  @ScaledMetric(relativeTo: .title2) private var ringLineWidth = Metrics.ringLineWidth
  let summary: HomeListeningSummary

  private enum Metrics {
    static let ringEdge: CGFloat = 20
    static let ringLineWidth: CGFloat = 3
  }

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.summary == rhs.summary
  }

  private var valueFont: Font { .title2.weight(.bold).monospacedDigit() }

  var body: some View {
    let _ = themeRevision
    let palette = AppTheme.palette
    // Überschrift über der Karte wie bei den übrigen Home-Sektionen; erscheint nur zusammen mit ihr.
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: "Your Listening")
      // Die ganze Kartenreihe ist ein Tap-Ziel (Stats-Seite) und ein zusammengefasstes Accessibility-Element.
      NavigationLink {
        ListeningStatsScreen()
      } label: {
        cards(palette: palette)
          .contentShape(Rectangle())
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(accessibilitySummary)
          .accessibilityHint("Opens your listening stats.")
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("home-listening-stats-card")
    }
  }

  /// Je Wert eine eigene Karte, gleich breit und gleich hoch nebeneinander; bei Accessibility-Schriftgrößen
  /// untereinander in voller Breite. Fehlende Werte → weniger Karten, die sich die Breite teilen.
  @ViewBuilder
  private func cards(palette: AppColorPalette) -> some View {
    let items = columnViews(palette: palette)
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(items.indices, id: \.self) { index in
          statCard(items[index])
        }
      }
    } else {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(items.indices, id: \.self) { index in
          statCard(items[index])
        }
      }
      // Ideale Höhe der höchsten Karte für alle — Inhalt bleibt oben ausgerichtet.
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func statCard(_ content: AnyView) -> some View {
    AbstandGroupedCard(
      horizontalPadding: AppTheme.Layout.withinSectionSpacing,
      verticalPadding: AppTheme.Layout.cardPadding
    ) {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func columnViews(palette: AppColorPalette) -> [AnyView] {
    var result: [AnyView] = [AnyView(streakColumn(palette: palette))]
    if let finished = summary.finishedBooks {
      result.append(AnyView(finishedBooksColumn(finished, palette: palette)))
    }
    if let seconds = summary.weekSeconds {
      result.append(AnyView(weekColumn(seconds: seconds, palette: palette)))
    }
    return result
  }

  private func streakColumn(palette: AppColorPalette) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.tightSpacing) {
      HStack(spacing: AppTheme.Layout.compactSpacing) {
        Image(systemName: "flame.fill")
          .font(.title3)
          .foregroundStyle(themeAccent)
        Text("\(summary.streakDays)")
          .font(valueFont)
          .foregroundStyle(palette.textPrimary)
      }
      columnLabel("day streak", palette: palette)
      if let active = summary.weekActiveDays, active.count == summary.weekdaySymbols.count {
        HStack(spacing: AppTheme.Layout.hairlineSpacing) {
          ForEach(active.indices, id: \.self) { index in
            Text(summary.weekdaySymbols[index])
              .font(.caption2.weight(active[index] ? .bold : .regular))
              .foregroundStyle(active[index] ? themeAccent : palette.textSecondary)
          }
        }
      }
    }
  }

  private func finishedBooksColumn(_ finished: ListeningAchievementState, palette: AppColorPalette) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.tightSpacing) {
      HStack(spacing: AppTheme.Layout.compactSpacing) {
        progressRing(finished.tier == .level5 ? 1 : finished.progressToNext, palette: palette)
        Text("\(finished.currentValue)")
          .font(valueFont)
          .foregroundStyle(palette.textPrimary)
      }
      columnLabel("books finished", palette: palette)
      columnDetail(finishedBooksDetail(finished), palette: palette)
    }
  }

  private func weekColumn(seconds: Int, palette: AppColorPalette) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.tightSpacing) {
      Text(ListeningAchievementKind.formatMarathonDaySeconds(seconds))
        .font(valueFont)
        .foregroundStyle(palette.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      columnLabel("this week", palette: palette)
      if let active = summary.weekActiveDays {
        columnDetail("\(active.filter { $0 }.count) of \(active.count) days", palette: palette)
      }
    }
  }

  private func progressRing(_ value: Double, palette: AppColorPalette) -> some View {
    ZStack {
      Circle()
        .stroke(palette.rule, lineWidth: ringLineWidth)
      Circle()
        .trim(from: 0, to: min(max(value, 0), 1))
        .stroke(themeAccent, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .frame(width: ringEdge, height: ringEdge)
    .accessibilityHidden(true)
  }

  private func columnLabel(_ text: String, palette: AppColorPalette) -> some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(palette.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func columnDetail(_ text: String, palette: AppColorPalette) -> some View {
    Text(text)
      .font(.caption.monospacedDigit())
      .foregroundStyle(palette.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// Stufe aus `ListeningAchievements` (Schwellen wie in Settings → Stats → Level).
  private func finishedBooksDetail(_ finished: ListeningAchievementState) -> String {
    guard let next = finished.nextThreshold else { return "Max level" }
    let remaining = max(0, next - finished.currentValue)
    guard let level = finished.tier.levelNumber else { return "\(remaining) to Level 1" }
    return "Level \(level) · \(remaining) to go"
  }

  private var accessibilitySummary: String {
    var parts = ["\(summary.streakDays) day streak"]
    if let finished = summary.finishedBooks {
      parts.append("\(finished.currentValue) books finished, \(finishedBooksDetail(finished))")
    }
    if let seconds = summary.weekSeconds {
      let hours = seconds / 3600
      let minutes = (seconds % 3600) / 60
      var week = "\(hours) hours \(minutes) minutes this week"
      if let active = summary.weekActiveDays {
        week += ", \(active.filter { $0 }.count) of \(active.count) days"
      }
      parts.append(week)
    }
    return parts.joined(separator: ". ")
  }
}

/// Stats als gepushte Seite auf dem Home-Stack (Ziel der Stats-Karte) — derselbe Inhalt wie Settings → Stats.
struct ListeningStatsScreen: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ServerAdminScrollScreen {
      SettingsStatsSectionView()
    }
    .navigationTitle("Stats")
    .toolbarTitleDisplayMode(.inline)
    .refreshable {
      guard !model.offlineHomeUIActive else { return }
      await model.loadListeningStats()
    }
    .task {
      // Wie Settings → Stats: offline nur der gecachte Stand.
      guard !model.offlineHomeUIActive else { return }
      await model.loadListeningStats()
    }
  }
}

// MARK: - Home: Cover-Card-Reihen (einheitlich wie „New episodes“)

private struct HomeShelfCoverViewportWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

/// Gemeinsames Karussell aller Home-Regale: gleiche Kartenbreite wie „New episodes“
/// (Compact 2¼ sichtbar, Regular +2; Max-Breite gegen iPad-Riesenkarten).
/// Keine feste Zeilenhöhe — sonst wird das 1:1-Cover gestaucht (`aspectRatio(.fit)`).
private struct HomeCoverCardCarousel<Item: Identifiable, Card: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  let items: [Item]
  @ViewBuilder let card: (Item) -> Card
  @State private var viewportWidth: CGFloat = 0

  private var cardWidth: CGFloat {
    AppTheme.Layout.homeNewestEpisodesCardWidth(
      forViewportWidth: viewportWidth,
      horizontalSizeClass: horizontalSizeClass
    )
  }

  var body: some View {
    AbstandHorizontalBrowseStripScroll(
      appliesHorizontalContentInset: false,
      verticalContentPadding: 0
    ) {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(items) { item in
          card(item)
            .frame(width: cardWidth)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    // Mindesthöhe vorab (Cover + Textblock) — sonst springt das Regal, sobald die Breite gemessen ist.
    .frame(minHeight: cardWidth + AppTheme.Layout.libraryHeroMetadataBlockHeight, alignment: .top)
    .background {
      GeometryReader { geo in
        Color.clear.preference(key: HomeShelfCoverViewportWidthKey.self, value: geo.size.width)
      }
    }
    .onPreferenceChange(HomeShelfCoverViewportWidthKey.self) { viewportWidth = $0 }
  }
}

// MARK: - Home: Kompaktkarten-Reihen

/// Karussell der Kompaktkarten: Karte ≈ 3/4 der Regalbreite, Scrollverhalten und Abstände wie bei den
/// Cover-Cards. Feste Mindesthöhe (Cover-Seite) — das Regal springt nicht, sobald die Breite gemessen ist.
private struct HomeCompactCardCarousel<Item: Identifiable, Card: View>: View {
  let items: [Item]
  @ViewBuilder let card: (Item) -> Card
  @State private var viewportWidth: CGFloat = 0

  private var cardWidth: CGFloat {
    AppTheme.Layout.homeCompactCardWidth(forViewportWidth: viewportWidth)
  }

  var body: some View {
    AbstandHorizontalBrowseStripScroll(
      appliesHorizontalContentInset: false,
      verticalContentPadding: 0
    ) {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(items) { item in
          card(item)
            .frame(width: cardWidth)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(minHeight: AppTheme.Layout.homeCompactCardCoverSide, alignment: .top)
    .background {
      GeometryReader { geo in
        Color.clear.preference(key: HomeShelfCoverViewportWidthKey.self, value: geo.size.width)
      }
    }
    .onPreferenceChange(HomeShelfCoverViewportWidthKey.self) { viewportWidth = $0 }
  }
}

private struct HomeBooksCompactCarousel: View {
  @EnvironmentObject private var model: AppModel
  let books: [ABSBook]
  var usesEbookProgressDisplay = false

  var body: some View {
    // Dieser `body` läuft bei jeder `AppModel`-Änderung — während der Wiedergabe u. a. alle paar
    // Sekunden durch den periodischen Fortschritts-Save. Die eigentliche Arbeit (Anreicherung per
    // Katalog + SwiftData, Karten-Inits) liegt deshalb im `Equatable`-Inhalt und läuft nur, wenn sich
    // die Regal-Bücher ändern. Fortschritt/Download beobachten die Karten selbst (`LibraryBookRowLiveState`).
    HomeBooksCompactCarouselContent(
      books: books,
      catalogRevision: model.books.count,
      usesEbookProgressDisplay: usesEbookProgressDisplay,
      model: model
    )
    .equatable()
  }
}

private struct HomeBooksCompactCarouselContent: View, Equatable {
  let books: [ABSBook]
  /// Katalog nachgeladen → Anreicherung neu (Stubs bekommen dann eBook-/Spur-Metadaten).
  let catalogRevision: Int
  let usesEbookProgressDisplay: Bool
  /// Bewusst nicht beobachtet (kein `@EnvironmentObject`) — siehe `HomeBooksCompactCarousel`.
  let model: AppModel

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.catalogRevision == rhs.catalogRevision
      && lhs.usesEbookProgressDisplay == rhs.usesEbookProgressDisplay
      && lhs.books.map(\.id) == rhs.books.map(\.id)
      && lhs.books.map(\.updatedAt) == rhs.books.map(\.updatedAt)
  }

  var body: some View {
    // Anreicherung (Katalog + SwiftData) einmal hier statt im Karten-Init — siehe `HomeBookCompactCard.init`.
    let enriched = books.map { model.bookStubEnrichedForListDisplay($0) }
    HomeCompactCardCarousel(items: enriched) { book in
      HomeBookCompactCard(book: book, model: model, usesEbookProgressDisplay: usesEbookProgressDisplay)
    }
  }
}

private struct HomePodcastEpisodesCompactCarousel: View {
  @EnvironmentObject private var model: AppModel
  let episodes: [ABSPodcastEpisodeListItem]

  var body: some View {
    HomeCompactCardCarousel(items: episodes) { episode in
      HomeEpisodeCompactCard(episode: episode, model: model)
    }
  }
}

private struct HomeSeriesCompactCarousel: View {
  @EnvironmentObject private var model: AppModel
  let series: [ABSLibrarySeriesListItem]

  var body: some View {
    HomeCompactCardCarousel(items: series) { item in
      let coverId = model.browseSeriesCoverBookIds(from: item.books).first
      let count = item.books?.count ?? 0
      let authors = item.cardAuthorsLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      HomeEntityCompactCard(
        title: item.name,
        subtitleLabel: authors.isEmpty ? "Books" : "Author",
        subtitle: authors.isEmpty ? (count > 0 ? "\(count)" : "—") : authors,
        footer: count > 0 ? (count == 1 ? "1 book" : "\(count) books") : "",
        accessibilityHint: "Opens series details."
      ) {
        if let coverId {
          SquareCoverImageView(
            url: model.coverURL(for: coverId),
            token: model.token,
            itemId: coverId,
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision(forBookId: coverId)
          )
        } else {
          HomeEntityCoverPlaceholder(systemImage: "books.vertical.fill")
        }
      } onOpen: {
        model.openSeriesDetail(
          seriesId: item.id,
          displayName: item.name,
          numBooks: item.books?.count
        )
      }
    }
  }
}

private struct HomeAuthorsCompactCarousel: View {
  @EnvironmentObject private var model: AppModel
  let authors: [ABSAuthorShelfEntity]

  var body: some View {
    HomeCompactCardCarousel(items: authors) { author in
      HomeEntityCompactCard(
        title: author.name,
        subtitleLabel: "Books",
        subtitle: author.numBooks.map { "\($0)" } ?? "—",
        footer: author.numBooks.map { $0 == 1 ? "1 book" : "\($0) books" } ?? "",
        accessibilityHint: "Opens author details."
      ) {
        if author.hasAuthorImage {
          SquareCoverImageView(
            url: model.authorImageURL(authorId: author.id),
            token: model.token,
            itemId: "author:\(author.id)",
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: 0
          )
        } else {
          HomeEntityCoverPlaceholder(systemImage: "person.fill")
        }
      } onOpen: {
        model.openAuthorDetail(
          authorId: author.id,
          displayName: author.name,
          numBooks: author.numBooks
        )
      }
    }
  }
}

/// Serie/Autor als Kompaktkarte: Cover links, Name (eine Zeile), Metazeile, Buchanzahl unten.
private struct HomeEntityCompactCard<Cover: View>: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  let subtitleLabel: String
  let subtitle: String
  let footer: String
  let accessibilityHint: String
  @ViewBuilder let cover: () -> Cover
  let onOpen: () -> Void

  var body: some View {
    HomeCompactCard(
      title: title,
      subtitleLabel: subtitleLabel,
      subtitle: subtitle,
      accessibilityHint: accessibilityHint,
      cover: cover,
      footer: {
        if !footer.isEmpty {
          Text(footer)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(model.appearancePalette.textSecondary)
            .lineLimit(1)
        }
      },
      badges: { EmptyView() },
      onOpen: onOpen
    )
  }
}

private struct HomeAuthorsCoverCardCarousel: View {
  @EnvironmentObject private var model: AppModel
  let authors: [ABSAuthorShelfEntity]

  var body: some View {
    HomeCoverCardCarousel(items: authors) { author in
      HomeEntityCoverCard(
        title: author.name,
        detailLabel: "Books",
        detailValue: author.numBooks.map { "\($0)" } ?? "—",
        accessibilityHint: "Opens author details."
      ) {
        if author.hasAuthorImage {
          SquareCoverImageView(
            url: model.authorImageURL(authorId: author.id),
            token: model.token,
            itemId: "author:\(author.id)",
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: 0
          )
        } else {
          HomeEntityCoverPlaceholder(systemImage: "person.fill")
        }
      } onOpen: {
        model.openAuthorDetail(
          authorId: author.id,
          displayName: author.name,
          numBooks: author.numBooks
        )
      }
    }
  }
}

private struct HomeEntityCoverPlaceholder: View {
  @EnvironmentObject private var model: AppModel
  let systemImage: String

  var body: some View {
    model.appearancePalette.card
      .overlay {
        Image(systemName: systemImage)
          .font(.title2.weight(.semibold))
          .foregroundStyle(model.appearancePalette.textSecondary)
      }
  }
}

/// Serie/Autor im Aufbau der Hero-Cover-Card (Buch/Folge): 1:1-Cover oben, Titel + Metazeile darunter —
/// ohne Play-Pille, Höhe wie die eBook-Variante der Buchkarte.
private struct HomeEntityCoverCard<Cover: View>: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  let detailLabel: String
  let detailValue: String
  let accessibilityHint: String
  @ViewBuilder let cover: () -> Cover
  let onOpen: () -> Void

  var body: some View {
    let palette = model.appearancePalette
    let coverTopRadius = AppTheme.Layout.coverCornerRadius
    let coverClip = UnevenRoundedRectangle(
      topLeadingRadius: coverTopRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: coverTopRadius,
      style: .continuous
    )
    let cardShape = RoundedRectangle(
      cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius,
      style: .continuous
    )

    Button(action: onOpen) {
      VStack(alignment: .leading, spacing: 0) {
        Color.clear
          .aspectRatio(1, contentMode: .fit)
          .frame(maxWidth: .infinity)
          .overlay { cover() }
          .clipShape(coverClip)

        ContinueListeningHeroMetadataBlock(
          title: title,
          detailLabel: detailLabel,
          detailValue: detailValue,
          horizontalInset: AppTheme.Layout.libraryRowCardInset,
          onTitleTap: onOpen,
          includesBottomPadding: true,
          blockHeight: AppTheme.Layout.libraryHeroMetadataBlockHeight
        )
      }
      .background(palette.card)
      .clipShape(cardShape)
      .abstandHeroCardOutline(palette: palette)
      .contentShape(cardShape)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityHint(accessibilityHint)
  }
}
