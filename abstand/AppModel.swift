import Combine
import Foundation
import Network
import SwiftUI

private enum Keys {
  static let server = "abstand_server_url"
  static let token = "abstand_token"
  /// Legacy; wird nach `booksLibrary` migriert.
  static let library = "abstand_library_id"
  static let booksLibrary = "abstand_books_library_id"
  static let podcastsLibrary = "abstand_podcasts_library_id"
  /// Bewusst keine Bibliothek gewählt (Tabs ausblenden, kein Auto-Pick).
  static let librarySelectionNone = "__abstand_no_library__"
  static let downloads = "abstand_downloaded_ids"
  static let lastPlayedItemId = "abstand_last_played_library_item_id"
  static let startDisabledCategories = "abstand_start_disabled_categories"
  static let catalogSortField = "abstand_catalog_sort_field"
  static let catalogSortDescending = "abstand_catalog_sort_descending"
  /// Früher: kombinierter `CatalogItemsSort`-RawValue (Migration einmalig).
  static let legacyCatalogItemsSort = "abstand_catalog_items_sort"
}

/// Sortierfeld für `GET /api/libraries/:id/items` (`sort`); Richtung über `desc` / `ascending` im Client.
enum CatalogSortField: String, CaseIterable, Identifiable, Hashable {
  case title
  case authorName
  case authorNameLF
  case addedAt
  case publishedYear
  case duration
  case size
  case birthtimeMs
  case mtimeMs
  case progress
  case progressCreatedAt
  case progressFinishedAt
  case random

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .title: return "Title"
    case .authorName: return "Author (first name first)"
    case .authorNameLF: return "Author (last name first)"
    case .addedAt: return "Date added"
    case .publishedYear: return "Published year"
    case .duration: return "Duration"
    case .size: return "File size"
    case .birthtimeMs: return "File created"
    case .mtimeMs: return "File modified"
    case .progress: return "Last progress update"
    case .progressCreatedAt: return "Progress started"
    case .progressFinishedAt: return "Finished"
    case .random: return "Random"
    }
  }

  var apiSortParameter: String {
    switch self {
    case .title: return "media.metadata.title"
    case .authorName: return "media.metadata.authorName"
    case .authorNameLF: return "media.metadata.authorNameLF"
    case .addedAt: return "addedAt"
    case .publishedYear: return "media.metadata.publishedYear"
    case .duration: return "media.duration"
    case .size: return "size"
    case .birthtimeMs: return "birthtimeMs"
    case .mtimeMs: return "mtimeMs"
    case .progress: return "progress"
    case .progressCreatedAt: return "progress.createdAt"
    case .progressFinishedAt: return "progress.finishedAt"
    case .random: return "random"
    }
  }
}

@MainActor
final class AppModel: ObservableObject {
  @Published var serverURL: String = UserDefaults.standard.string(forKey: Keys.server) ?? ""

  private static let initialCatalogSort: (field: CatalogSortField, descending: Bool) = loadCatalogSortState()

  @Published var catalogSortField: CatalogSortField = AppModel.initialCatalogSort.field {
    didSet {
      UserDefaults.standard.set(catalogSortField.rawValue, forKey: Keys.catalogSortField)
    }
  }
  @Published var catalogSortDescending: Bool = AppModel.initialCatalogSort.descending {
    didSet {
      UserDefaults.standard.set(catalogSortDescending, forKey: Keys.catalogSortDescending)
    }
  }
  /// Alle Bibliotheken vom Server (Bücher und Podcasts).
  @Published var libraries: [ABSLibrary] = []
  @Published var selectedBooksLibrary: ABSLibrary?
  @Published var selectedPodcastLibrary: ABSLibrary?
  @Published var books: [ABSBook] = []
  @Published var podcastEpisodes: [ABSPodcastEpisodeListItem] = []
  /// Podcast-Sendungen der Bibliothek (Katalog), für die Cover-Leiste.
  @Published var podcastShows: [ABSBook] = []
  @Published private(set) var podcastShowsLoading = false
  /// `nil` = „New“-Ansicht (recent-Feed); gesetzt = nur diese Sendung (`podcastFilteredEpisodes`).
  @Published var podcastSelectedShowId: String?
  @Published var podcastFilteredEpisodes: [ABSPodcastEpisodeListItem] = []
  @Published private(set) var isLoadingPodcastShowEpisodes = false
  /// Alle Hörbücher auf dem Start-Tab (über alle sichtbaren Regale, für Detailsuche / Fallback).
  @Published var startBooks: [ABSBook] = []
  /// Personalisierte Regale (`/api/libraries/…/personalized`), gefiltert nach Einstellungen.
  @Published var startShelves: [ABSStartShelfSection] = []
  /// Kategorien für die Schalter „Regal anzeigen“ (nur `settingsCategoryOrder`; Server liefert optional schönere Titel).
  @Published var startSettingsCategoryList: [(category: String, label: String)] =
    ABSStartShelfLocalization.settingsCategoryOrder.map {
      (category: $0, label: ABSStartShelfLocalization.displayTitle(category: $0, serverLabel: ""))
    }
  /// Ausgeschaltete Start-`category`-Strings (persistiert).
  @Published var startDisabledCategories: Set<String> = Set(
    UserDefaults.standard.stringArray(forKey: Keys.startDisabledCategories) ?? []
  )
  @Published var progressByItemId: [String: ABSUserMediaProgress] = [:]
  @Published var searchText: String = ""
  @Published var searchBooks: [ABSBook] = []
  @Published var podcastSearchText: String = ""
  @Published var podcastSearchBooks: [ABSBook] = []
  @Published var searchAuthors: [ABSSearchAuthorRow] = []
  @Published var searchNarrators: [ABSSearchNarratorRow] = []
  @Published var searchSeries: [ABSSearchSeriesRow] = []
  @Published var searchTags: [ABSSearchNamedCount] = []
  @Published var searchGenres: [ABSSearchNamedCount] = []
  @Published var podcastSearchAuthors: [ABSSearchAuthorRow] = []
  @Published var podcastSearchNarrators: [ABSSearchNarratorRow] = []
  @Published var podcastSearchSeries: [ABSSearchSeriesRow] = []
  @Published var podcastSearchTags: [ABSSearchNamedCount] = []
  @Published var podcastSearchGenres: [ABSSearchNamedCount] = []
  /// Server-Items-Filter für den Bücher-Katalog.
  @Published var activeLibraryFilter: String?
  /// Anzeige unter der Suche: wonach der Bücher-Katalog gefiltert ist.
  @Published var activeLibraryFilterSummary: String?
  @Published var mainTab: MainTab = .start
  @Published var expandedItemId: String?
  @Published var expandedDetail: ABSBook?
  @Published var expandedPodcastEpisodeId: String?
  @Published var expandedPodcastEpisodeDetail: ABSPodcastEpisodeExpandedDetail?
  @Published var isLoadingLibrary = false
  @Published var isLoadingPodcasts = false
  @Published var errorMessage: String?

  /// Erhöhen nach `clearCoverImageCache()`, damit `CoverImageView` neu lädt.
  @Published private(set) var coverImageCacheRevision = 0
  @Published var downloadedItemIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Keys.downloads) ?? [])
  /// Aus `download.json` gebaute Stubs für Home-Regal „Heruntergeladen“ und Offline-Katalog.
  @Published private(set) var downloadedShelfBooks: [ABSBook] = []
  @Published private(set) var isNetworkReachable = true
  /// Mini-Player: Session aus Server-Fortschritt / `item`-Laden; UI kann sofort Skelett zeigen.
  @Published private(set) var isRestoringLaunchPlayback = false

  private(set) var token: String = UserDefaults.standard.string(forKey: Keys.token) ?? ""

  let player = PlaybackController()
  let downloads = DownloadManager()

  /// Zusatz für `ScrollView`-Inhalt, damit `tabViewBottomAccessory` die letzten Zeilen nicht verdeckt.
  var nowPlayingAccessoryScrollBottomInset: CGFloat {
    let p = player
    if p.activeBook != nil { return 56 }
    if isRestoringLaunchPlayback { return 56 }
    if p.showMiniPlayerPlaceholder && p.activeBook == nil { return 56 }
    return 0
  }

  private var cancellables = Set<AnyCancellable>()

  private var client: ABSAPIClient?
  private var libraryPage = 0
  private var libraryTotal = 0
  private var podcastLibraryPage = 0
  private var podcastLibraryTotal = 0
  /// Solange `true`, lädt „Mehr“ über `/recent-episodes`. Nach Fallback über Podcast-Shows ist Pagination aus.
  private var podcastEpisodesPagingFromRecentAPI = true
  /// Verhindert, dass ein verzögertes `item(id:expanded:)` eine neue Sendungswahl überschreibt.
  private var podcastShowEpisodesLoadSerial = 0
  private var searchTask: Task<Void, Never>?
  private var podcastSearchTask: Task<Void, Never>?
  private let pathMonitor = NWPathMonitor()
  private let pathMonitorQueue = DispatchQueue(label: "de.letzgo.abstand.network")

  enum MainTab: String, CaseIterable, Hashable {
    case start = "Home"
    case books = "Books"
    case podcasts = "Podcasts"
    case settings = "Settings"
  }

  init() {
    Self.migrateLibraryKeysIfNeeded()
    player.objectWillChange
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)
    downloads.objectWillChange
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    pathMonitor.pathUpdateHandler = { [weak self] path in
      let reachable = path.status == .satisfied
      Task { @MainActor [weak self] in
        guard let model = self else { return }
        model.isNetworkReachable = reachable
        model.refreshDownloadedShelfFromManifests()
      }
    }
    pathMonitor.start(queue: pathMonitorQueue)
    refreshDownloadedShelfFromManifests()
    restoreAllFromDiskOnLaunch()
    if isLoggedIn {
      isRestoringLaunchPlayback = true
      player.setMiniPlayerPlaceholder(true)
    }
  }

  deinit {
    pathMonitor.cancel()
  }

  /// Liest alle `Downloads/*/download.json` für bekannte `downloadedItemIds` und baut Stubs für UI / Offline-Wiedergabe.
  func refreshDownloadedShelfFromManifests() {
    var list: [ABSBook] = []
    for id in downloadedItemIds.sorted() {
      guard let root = try? downloads.downloadFolder(for: id),
        let manifest = ABSDownloadManifest.load(from: root)
      else { continue }
      list.append(ABSBook.fromDownloadManifest(manifest))
    }
    downloadedShelfBooks = list
  }

  var isLoggedIn: Bool {
    ABSAPIClient.normalizeServerURL(serverURL) != nil && !token.isEmpty
  }

  func booksForDisplay() -> [ABSBook] {
    switch mainTab {
    case .books:
      if !isNetworkReachable, !books.isEmpty { return books }
      if !isNetworkReachable { return downloadedShelfBooks }
      return books
    case .podcasts:
      return []
    case .start, .settings:
      return []
    }
  }

  /// Home-Regal „Heruntergeladen“: Manifest-Zeilen plus Platzhalter für laufende / unfertige Downloads ohne `download.json`.
  var downloadedTitlesForHome: [ABSBook] {
    var seen = Set<String>()
    var out: [ABSBook] = []
    out.reserveCapacity(downloadedItemIds.count)
    for b in downloadedShelfBooks where !seen.contains(b.id) {
      seen.insert(b.id)
      out.append(b)
    }
    for id in downloadedItemIds.sorted() where !seen.contains(id) {
      seen.insert(id)
      let stubMedia = ABSBookMedia(
        metadata: ABSBookMediaMetadata(offlineTitle: "Download", authorLine: "…"),
        duration: nil,
        numTracks: nil,
        chapters: nil,
        tracks: nil
      )
      out.append(
        ABSBook(
          id: id,
          libraryId: selectedBooksLibrary?.id,
          media: stubMedia,
          addedAt: nil,
          updatedAt: nil
        ))
    }
    return out
  }

  /// Migriert `abstand_library_id` → `abstand_books_library_id` (einmalig).
  private static func migrateLibraryKeysIfNeeded() {
    let d = UserDefaults.standard
    if d.string(forKey: Keys.booksLibrary) == nil,
      let legacy = d.string(forKey: Keys.library)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !legacy.isEmpty
    {
      d.set(legacy, forKey: Keys.booksLibrary)
    }
  }

  var sortedBookLibraries: [ABSLibrary] {
    libraries.filter(\.isBookLibrary).sorted {
      if $0.displayOrderOrZero != $1.displayOrderOrZero {
        return $0.displayOrderOrZero < $1.displayOrderOrZero
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  var sortedPodcastLibraries: [ABSLibrary] {
    libraries.filter(\.isPodcastLibrary).sorted {
      if $0.displayOrderOrZero != $1.displayOrderOrZero {
        return $0.displayOrderOrZero < $1.displayOrderOrZero
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  var booksLibraryPreferenceIsNone: Bool {
    normalizedLibraryPreferenceKey(Keys.booksLibrary) == Keys.librarySelectionNone
  }

  var podcastsLibraryPreferenceIsNone: Bool {
    normalizedLibraryPreferenceKey(Keys.podcastsLibrary) == Keys.librarySelectionNone
  }

  private func normalizedLibraryPreferenceKey(_ key: String) -> String {
    UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  /// Einmalige Migration von `abstand_catalog_items_sort` → Feld + absteigend-Flag.
  private static func loadCatalogSortState() -> (field: CatalogSortField, descending: Bool) {
    let legacy = UserDefaults.standard.string(forKey: Keys.legacyCatalogItemsSort) ?? ""
    if !legacy.isEmpty {
      UserDefaults.standard.removeObject(forKey: Keys.legacyCatalogItemsSort)
      let migrated: (CatalogSortField, Bool)? = {
        switch legacy {
        case "titleAsc": return (.title, false)
        case "titleDesc": return (.title, true)
        case "authorNameAsc": return (.authorName, false)
        case "authorNameDesc": return (.authorName, true)
        case "authorNameLFAsc": return (.authorNameLF, false)
        case "authorNameLFDesc": return (.authorNameLF, true)
        case "addedAtNewest": return (.addedAt, true)
        case "addedAtOldest": return (.addedAt, false)
        case "publishedYearNewest": return (.publishedYear, true)
        case "publishedYearOldest": return (.publishedYear, false)
        case "durationLongest": return (.duration, true)
        case "durationShortest": return (.duration, false)
        case "sizeLargest": return (.size, true)
        case "sizeSmallest": return (.size, false)
        case "birthtimeNewest": return (.birthtimeMs, true)
        case "birthtimeOldest": return (.birthtimeMs, false)
        case "mtimeNewest": return (.mtimeMs, true)
        case "mtimeOldest": return (.mtimeMs, false)
        case "progressUpdated": return (.progress, true)
        case "progressCreated": return (.progressCreatedAt, true)
        case "progressFinished": return (.progressFinishedAt, true)
        case "randomOrder": return (.random, false)
        default: return nil
        }
      }()
      if let migrated {
        UserDefaults.standard.set(migrated.0.rawValue, forKey: Keys.catalogSortField)
        UserDefaults.standard.set(migrated.1, forKey: Keys.catalogSortDescending)
        return (field: migrated.0, descending: migrated.1)
      }
    }
    let raw = UserDefaults.standard.string(forKey: Keys.catalogSortField) ?? ""
    let field = CatalogSortField(rawValue: raw) ?? .title
    let descending = UserDefaults.standard.bool(forKey: Keys.catalogSortDescending)
    return (field: field, descending: descending)
  }

  /// Aktualisiert `progressByItemId` vom Server (POST /api/authorize).
  func refreshProgressFromServer() async {
    guard let c = client else { return }
    do {
      let auth = try await c.authorize()
      applyUserProgress(auth.user.mediaProgress)
      let t = auth.user.token
      if !t.isEmpty {
        token = t
        UserDefaults.standard.set(t, forKey: Keys.token)
        await c.setToken(t)
      }
    } catch {}
  }

  /// Beim Öffnen des Settings-Tabs: Bibliotheksliste und Start-/Regal-Metadaten wie nach Login neu laden.
  func reloadSettingsTab() async {
    guard let c = client else { return }
    do {
      libraries = try await c.libraries()

      if podcastsLibraryPreferenceIsNone {
        selectedPodcastLibrary = nil
        podcastEpisodes = []
        podcastShows = []
        podcastSelectedShowId = nil
        podcastFilteredEpisodes = []
        podcastLibraryPage = 0
        podcastLibraryTotal = 0
      } else if let sel = selectedPodcastLibrary, !sortedPodcastLibraries.contains(where: { $0.id == sel.id })
      {
        if let first = sortedPodcastLibraries.first {
          selectPodcastLibrary(first, navigateToCatalog: false)
        } else {
          selectedPodcastLibrary = nil
          podcastEpisodes = []
          podcastShows = []
          podcastSelectedShowId = nil
          podcastFilteredEpisodes = []
          podcastLibraryPage = 0
          podcastLibraryTotal = 0
        }
      } else if selectedPodcastLibrary == nil, !podcastsLibraryPreferenceIsNone,
        let first = sortedPodcastLibraries.first
      {
        selectPodcastLibrary(first, navigateToCatalog: false)
      }

      if booksLibraryPreferenceIsNone {
        selectedBooksLibrary = nil
        books = []
        libraryPage = 0
        libraryTotal = 0
      } else if let sel = selectedBooksLibrary, !sortedBookLibraries.contains(where: { $0.id == sel.id }) {
        if let first = sortedBookLibraries.first {
          selectBooksLibrary(first, navigateToCatalog: false)
        } else {
          selectedBooksLibrary = nil
          books = []
          libraryPage = 0
          libraryTotal = 0
        }
      } else if selectedBooksLibrary == nil, !booksLibraryPreferenceIsNone, let first = sortedBookLibraries.first {
        selectBooksLibrary(first, navigateToCatalog: false)
      }

      await reloadPodcastLibrary(reset: true)
      await reloadLibrary(reset: true)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Lädt personalisierte Regale der aktuellen Bibliothek; Fallback: `items-in-progress`.
  /// Cache zuerst (beim App-Start), hier nur mit Live-Daten überschreiben — kein blockierender Ladezustand für Home.
  func loadStartDashboard() async {
    defer { applyContinueListeningFinishedFilter() }
    guard let c = client else {
      refreshDownloadedShelfFromManifests()
      return
    }
    if !isNetworkReachable {
      applyOfflineHomeShelvesIfNeeded()
      refreshDownloadedShelfFromManifests()
      return
    }
    do {
      await refreshProgressFromServer()
      if let lib = selectedBooksLibrary {
        async let shelvesData = c.personalizedShelves(libraryId: lib.id, limit: 14)
        async let inProgressPayload = c.itemsInProgress(limit: 80)
        let (data, payload) = try await (shelvesData, inProgressPayload)
        if let root = cacheAccountURL() {
          try? LibraryDiskCache.savePersonalized(account: root, libraryId: lib.id, data: data)
        }
        let parsed = ABSAPIClient.parsePersonalizedStartShelves(data: data)
        updateStartSettingsCategoryList(parsed: parsed)
        if parsed.isEmpty {
          applyStartDashboardInProgressFromPayload(payload)
        } else {
          let visible = parsed.filter { isStartCategoryEnabled($0.category) }
          startShelves = visible
          recomputeStartBooksUnion(from: visible)
          mergePodcastEpisodesIntoContinueShelves(payload: payload)
        }
      } else {
        try await applyStartDashboardInProgressFallback(client: c)
      }
    } catch {
      await refreshProgressFromServer()
      do {
        try await applyStartDashboardInProgressFallback(client: c)
      } catch {
        if startShelves.isEmpty {
          applyLocalContinueListeningFromCachedBooks()
        }
      }
    }
  }

  func isStartCategoryEnabled(_ category: String) -> Bool {
    !startDisabledCategories.contains(category)
  }

  func setStartCategoryEnabled(_ category: String, enabled: Bool) {
    var next = startDisabledCategories
    if enabled {
      next.remove(category)
    } else {
      next.insert(category)
    }
    startDisabledCategories = next
    UserDefaults.standard.set(Array(startDisabledCategories), forKey: Keys.startDisabledCategories)
    Task { await loadStartDashboard() }
  }

  private func updateStartSettingsCategoryList(parsed: [ABSStartShelfSection]) {
    var fromServer: [String: String] = [:]
    for s in parsed {
      fromServer[s.category] = s.displayTitle
    }
    startSettingsCategoryList = ABSStartShelfLocalization.settingsCategoryOrder.map { cat in
      let label =
        fromServer[cat]
        ?? ABSStartShelfLocalization.displayTitle(category: cat, serverLabel: "")
      return (category: cat, label: label)
    }
  }

  private func recomputeStartBooksUnion(from shelves: [ABSStartShelfSection]) {
    var seen = Set<String>()
    var acc: [ABSBook] = []
    acc.reserveCapacity(64)
    for s in shelves {
      for b in s.books where !seen.contains(b.id) {
        seen.insert(b.id)
        acc.append(b)
      }
    }
    startBooks = acc
  }

  private func applyStartDashboardInProgressFromPayload(_ payload: ABSItemsInProgressPayload) {
    let filtered: [ABSBook]
    if let lib = selectedBooksLibrary {
      let bookItems = payload.books.filter { book in
        guard let lid = book.libraryId else { return true }
        return lid == lib.id
      }
      filtered = bookItems.filter(\.isPlayableAudiobook).sorted {
        (progressByItemId[$0.id]?.lastUpdate ?? 0) > (progressByItemId[$1.id]?.lastUpdate ?? 0)
      }
    } else {
      filtered = []
    }
    let podcastEps: [ABSPodcastEpisodeListItem]
    if let plid = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !plid.isEmpty {
      var eps = payload.podcastEpisodes.filter { ($0.libraryId ?? "") == plid || $0.libraryId == nil }
      eps.sort {
        (progressByItemId[$0.progressLookupKey]?.lastUpdate ?? 0)
          > (progressByItemId[$1.progressLookupKey]?.lastUpdate ?? 0)
      }
      podcastEps = dedupePodcastEpisodesForHomeContinueList(eps)
    } else {
      podcastEps = []
    }
    let cat = "itemsInProgressFallback"
    let title = ABSStartShelfLocalization.displayTitle(category: cat, serverLabel: "")
    let section = ABSStartShelfSection(
      id: "items-in-progress-fallback",
      category: cat,
      displayTitle: title,
      books: filtered,
      podcastEpisodes: podcastEps,
      authors: []
    )
    if isStartCategoryEnabled("recentlyListened") {
      startShelves = [section]
      recomputeStartBooksUnion(from: [section])
    } else {
      startShelves = []
      startBooks = []
    }
  }

  private func applyStartDashboardInProgressFallback(client: ABSAPIClient) async throws {
    let payload = try await client.itemsInProgress(limit: 80)
    applyStartDashboardInProgressFromPayload(payload)
  }

  private func isHomeContinueCategory(_ category: String) -> Bool {
    category == "recentlyListened" || category == "itemsInProgressFallback"
  }

  /// Entfernt aus „Continue listening“-Regalen Einträge, die laut `progressByItemId` bereits fertig sind
  /// (Server-`/personalized`-Payload kann kurz hinterherhängen).
  private func applyContinueListeningFinishedFilter() {
    guard !startShelves.isEmpty else { return }
    let newShelves = startShelves.map { shelf -> ABSStartShelfSection in
      guard isHomeContinueCategory(shelf.category) else { return shelf }
      let books = shelf.books.filter { book in
        !(progressByItemId[book.id]?.isFinished ?? false)
      }
      let eps = shelf.podcastEpisodes.filter { episode in
        !(progressByItemId[episode.progressLookupKey]?.isFinished ?? false)
      }
      if books.count == shelf.books.count, eps.count == shelf.podcastEpisodes.count { return shelf }
      return ABSStartShelfSection(
        id: shelf.id,
        category: shelf.category,
        displayTitle: shelf.displayTitle,
        books: books,
        podcastEpisodes: eps,
        authors: shelf.authors
      )
    }
    startShelves = newShelves
    recomputeStartBooksUnion(from: newShelves)
  }

  /// Eine Folge pro `episodeId` (neuester Fortschritt gewinnt). Behebt Doppelzeilen, wenn z. B. `libraryItemId` je API-Pfad abweicht.
  private func dedupePodcastEpisodesForHomeContinueList(_ items: [ABSPodcastEpisodeListItem]) -> [ABSPodcastEpisodeListItem] {
    let sorted = items.sorted {
      (progressByItemId[$0.progressLookupKey]?.lastUpdate ?? 0)
        > (progressByItemId[$1.progressLookupKey]?.lastUpdate ?? 0)
    }
    var seen = Set<String>()
    var out: [ABSPodcastEpisodeListItem] = []
    out.reserveCapacity(sorted.count)
    for e in sorted {
      let eid = e.episodeId.trimmingCharacters(in: .whitespacesAndNewlines)
      let key = eid.isEmpty ? e.progressLookupKey : eid
      guard seen.insert(key).inserted else { continue }
      out.append(e)
    }
    return out
  }

  private func mergePodcastEpisodesIntoContinueShelves(payload: ABSItemsInProgressPayload) {
    var episodes = payload.podcastEpisodes
    if selectedPodcastLibrary == nil {
      episodes = []
    } else if let lid = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
      episodes = episodes.filter { ($0.libraryId ?? "") == lid || $0.libraryId == nil }
    } else {
      episodes = []
    }
    episodes = dedupePodcastEpisodesForHomeContinueList(episodes)
    if episodes.isEmpty {
      startShelves = startShelves.map { shelf in
        guard isHomeContinueCategory(shelf.category), !shelf.podcastEpisodes.isEmpty else { return shelf }
        return ABSStartShelfSection(
          id: shelf.id,
          category: shelf.category,
          displayTitle: shelf.displayTitle,
          books: shelf.books,
          podcastEpisodes: [],
          authors: shelf.authors
        )
      }
      return
    }
    var remaining = episodes
    var newShelves: [ABSStartShelfSection] = []
    for shelf in startShelves {
      if isHomeContinueCategory(shelf.category), !remaining.isEmpty {
        newShelves.append(
          ABSStartShelfSection(
            id: shelf.id,
            category: shelf.category,
            displayTitle: shelf.displayTitle,
            books: shelf.books,
            podcastEpisodes: remaining,
            authors: shelf.authors
          ))
        remaining = []
      } else {
        newShelves.append(shelf)
      }
    }
    if !remaining.isEmpty {
      let title = ABSStartShelfLocalization.displayTitle(category: "recentlyListened", serverLabel: "")
      newShelves.insert(
        ABSStartShelfSection(
          id: "podcast-continue-supplement",
          category: "recentlyListened",
          displayTitle: title,
          books: [],
          podcastEpisodes: remaining,
          authors: []
        ),
        at: 0
      )
    }
    startShelves = newShelves
  }

  private func resolveLibrariesAfterServerFetch(userDefaultLibraryId: String?) async {
    let booksKey = normalizedLibraryPreferenceKey(Keys.booksLibrary)
    if booksKey == Keys.librarySelectionNone {
      selectedBooksLibrary = nil
      books = []
      libraryPage = 0
      libraryTotal = 0
    } else if !booksKey.isEmpty,
      let lib = libraries.first(where: { $0.id == booksKey && $0.isBookLibrary })
    {
      selectBooksLibrary(lib, navigateToCatalog: false)
    } else if let def = userDefaultLibraryId,
      let lib = libraries.first(where: { $0.id == def && $0.isBookLibrary })
    {
      selectBooksLibrary(lib, navigateToCatalog: false)
    } else if let first = sortedBookLibraries.first {
      selectBooksLibrary(first, navigateToCatalog: false)
    } else {
      selectedBooksLibrary = nil
      books = []
      libraryPage = 0
      libraryTotal = 0
    }

    let podKey = normalizedLibraryPreferenceKey(Keys.podcastsLibrary)
    if podKey == Keys.librarySelectionNone {
      selectedPodcastLibrary = nil
      podcastEpisodes = []
      podcastLibraryPage = 0
      podcastLibraryTotal = 0
    } else if !podKey.isEmpty,
      let lib = libraries.first(where: { $0.id == podKey && $0.isPodcastLibrary })
    {
      selectPodcastLibrary(lib, navigateToCatalog: false)
    } else if let first = sortedPodcastLibraries.first {
      selectPodcastLibrary(first, navigateToCatalog: false)
    } else {
      selectedPodcastLibrary = nil
      podcastEpisodes = []
      podcastLibraryPage = 0
      podcastLibraryTotal = 0
    }
  }

  func bootstrapFromStoredCredentials() async {
    guard let url = ABSAPIClient.normalizeServerURL(serverURL), !token.isEmpty else { return }
    defer { refreshDownloadedShelfFromManifests() }
    isRestoringLaunchPlayback = true
    player.setMiniPlayerPlaceholder(true)
    let c = ABSAPIClient(baseURL: url, token: token)
    client = c
    do {
      let auth = try await c.authorize()
      applyUserProgress(auth.user.mediaProgress)
      token = auth.user.token
      UserDefaults.standard.set(token, forKey: Keys.token)
      libraries = try await c.libraries()
      await resolveLibrariesAfterServerFetch(userDefaultLibraryId: auth.userDefaultLibraryId)
      async let catalog: Void = await reloadLibrary(reset: true)
      async let pod: Void = await reloadPodcastLibrary(reset: true)
      async let mini: Void = await restoreLastPlayedOnLaunch()
      _ = await (catalog, pod, mini)
    } catch {
      errorMessage = error.localizedDescription
      isRestoringLaunchPlayback = false
      player.setMiniPlayerPlaceholder(true)
    }
  }

  func login(server: String, username: String, password: String) async {
    errorMessage = nil
    guard let url = ABSAPIClient.normalizeServerURL(server) else {
      errorMessage = "Please enter a valid server URL."
      return
    }
    defer { refreshDownloadedShelfFromManifests() }
    do {
      let res = try await ABSAPIClient.login(server: url, username: username, password: password)
      token = res.user.token
      serverURL = server.trimmingCharacters(in: .whitespacesAndNewlines)
      UserDefaults.standard.set(serverURL, forKey: Keys.server)
      UserDefaults.standard.set(token, forKey: Keys.token)
      let c = ABSAPIClient(baseURL: url, token: token)
      client = c
      isRestoringLaunchPlayback = true
      player.setMiniPlayerPlaceholder(true)
      applyUserProgress(res.user.mediaProgress)
      libraries = try await c.libraries()
      await resolveLibrariesAfterServerFetch(userDefaultLibraryId: res.userDefaultLibraryId)
      async let catalog: Void = await reloadLibrary(reset: true)
      async let pod: Void = await reloadPodcastLibrary(reset: true)
      async let mini: Void = await restoreLastPlayedOnLaunch()
      _ = await (catalog, pod, mini)
    } catch {
      errorMessage = error.localizedDescription
      isRestoringLaunchPlayback = false
      player.setMiniPlayerPlaceholder(true)
    }
  }

  func logout() {
    clearCoverImageCache()
    token = ""
    UserDefaults.standard.removeObject(forKey: Keys.token)
    client = nil
    libraries = []
    selectedBooksLibrary = nil
    selectedPodcastLibrary = nil
    books = []
    podcastEpisodes = []
    podcastShows = []
    podcastSelectedShowId = nil
    podcastFilteredEpisodes = []
    podcastLibraryPage = 0
    podcastLibraryTotal = 0
    startBooks = []
    startShelves = []
    searchBooks = []
    searchAuthors = []
    searchNarrators = []
    searchSeries = []
    searchTags = []
    searchGenres = []
    searchText = ""
    podcastSearchText = ""
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    clearSearchResults()
    clearPodcastSearchResults()
    progressByItemId = [:]
    expandedItemId = nil
    expandedDetail = nil
    expandedPodcastEpisodeId = nil
    expandedPodcastEpisodeDetail = nil
    UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
    UserDefaults.standard.removeObject(forKey: Keys.booksLibrary)
    UserDefaults.standard.removeObject(forKey: Keys.podcastsLibrary)
    UserDefaults.standard.removeObject(forKey: Keys.library)
    player.tearDownPlayer()
    downloadedShelfBooks = []
    isRestoringLaunchPlayback = false
    LibraryDiskCache.clearEverything()
  }

  func selectBooksLibrary(_ lib: ABSLibrary, navigateToCatalog: Bool = false) {
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    selectedBooksLibrary = lib
    UserDefaults.standard.set(lib.id, forKey: Keys.booksLibrary)
    if navigateToCatalog { mainTab = .books }
    restoreBooksCatalogAndHomeFromDisk(libraryIdOverride: lib.id)
  }

  func selectPodcastLibrary(_ lib: ABSLibrary, navigateToCatalog: Bool = false) {
    podcastSelectedShowId = nil
    podcastFilteredEpisodes = []
    selectedPodcastLibrary = lib
    UserDefaults.standard.set(lib.id, forKey: Keys.podcastsLibrary)
    if navigateToCatalog { mainTab = .podcasts }
    restorePodcastCatalogFromDisk(libraryIdOverride: lib.id)
  }

  func clearBooksLibrarySelection() {
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    selectedBooksLibrary = nil
    books = []
    libraryPage = 0
    libraryTotal = 0
    UserDefaults.standard.set(Keys.librarySelectionNone, forKey: Keys.booksLibrary)
    if mainTab == .books { mainTab = .start }
    Task { await loadStartDashboard() }
  }

  func clearPodcastLibrarySelection() {
    selectedPodcastLibrary = nil
    podcastEpisodes = []
    podcastShows = []
    podcastSelectedShowId = nil
    podcastFilteredEpisodes = []
    podcastLibraryPage = 0
    podcastLibraryTotal = 0
    UserDefaults.standard.set(Keys.librarySelectionNone, forKey: Keys.podcastsLibrary)
    if mainTab == .podcasts { mainTab = .start }
    Task { await loadStartDashboard() }
  }

  private func restoreAllFromDiskOnLaunch() {
    restoreBooksCatalogAndHomeFromDisk()
    restorePodcastCatalogFromDisk()
  }

  func reloadLibrary(reset: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else {
      await loadStartDashboard()
      return
    }
    if !isNetworkReachable {
      refreshDownloadedShelfFromManifests()
      applyOfflineHomeShelvesIfNeeded()
      return
    }
    isLoadingLibrary = true
    defer { isLoadingLibrary = false }
    let ascending = catalogSortField == .random ? true : !catalogSortDescending
    let sortKey = catalogSortField.apiSortParameter
    do {
      if reset {
        libraryPage = 0
      }
      let pageIndex = libraryPage
      let (page, raw) = try await c.libraryItems(
        libraryId: lib.id,
        page: libraryPage,
        limit: 40,
        sort: sortKey,
        ascending: ascending,
        minified: true,
        filter: activeLibraryFilter
      )
      if reset, pageIndex == 0, let account = cacheAccountURL() {
        try? LibraryDiskCache.wipeCatalogSlug(
          account: account, libraryId: lib.id, filter: activeLibraryFilter, sortField: sortKey, ascending: ascending)
      }
      if let account = cacheAccountURL() {
        try? LibraryDiskCache.saveCatalogPage(
          account: account,
          libraryId: lib.id,
          filter: activeLibraryFilter,
          sortField: sortKey,
          ascending: ascending,
          pageIndex: pageIndex,
          data: raw
        )
      }
      if reset {
        books = page.results.filter { ($0.media.numTracks ?? 0) > 0 || (bookDuration($0) > 0) }
      } else {
        books.append(contentsOf: page.results.filter { ($0.media.numTracks ?? 0) > 0 || (bookDuration($0) > 0) })
      }
      libraryTotal = page.total
      libraryPage = page.page + 1
    } catch {
      errorMessage = error.localizedDescription
    }
    if reset || startShelves.isEmpty {
      await loadStartDashboard()
    }
  }

  func reloadPodcastLibrary(reset: Bool) async {
    guard let lib = selectedPodcastLibrary else { return }
    if !isNetworkReachable {
      if podcastEpisodes.isEmpty {
        applyPodcastListFromDisk(libraryId: lib.id)
      }
      return
    }
    guard let c = client else { return }
    isLoadingPodcasts = true
    defer { isLoadingPodcasts = false }
    do {
      if reset {
        podcastLibraryPage = 0
        podcastEpisodesPagingFromRecentAPI = true
        if let account = cacheAccountURL() {
          try? LibraryDiskCache.wipePodcastRecent(account: account, libraryId: lib.id)
        }
      }
      let pageIndex = podcastLibraryPage

      if podcastEpisodesPagingFromRecentAPI {
        let (res, raw) = try await c.recentPodcastEpisodes(libraryId: lib.id, page: pageIndex, limit: 40)
        let rows = res.episodes.compactMap { ABSPodcastEpisodeListItem.fromDTO($0, libraryId: lib.id) }

        if rows.isEmpty, pageIndex == 0 {
          let fallback = await loadPodcastEpisodesFallback(client: c, libraryId: lib.id)
          if !fallback.isEmpty {
            podcastEpisodesPagingFromRecentAPI = false
            podcastEpisodes = fallback
            podcastLibraryTotal = fallback.count
            podcastLibraryPage = 1
            if let account = cacheAccountURL() {
              try? LibraryDiskCache.savePodcastFallback(account: account, libraryId: lib.id, episodes: fallback)
            }
            if reset { await reloadPodcastShowsCatalog() }
            return
          }
        }

        if let account = cacheAccountURL() {
          try? LibraryDiskCache.savePodcastRecentPage(
            account: account, libraryId: lib.id, pageIndex: pageIndex, data: raw)
        }

        if reset {
          podcastEpisodes = rows
        } else if !rows.isEmpty {
          podcastEpisodes.append(contentsOf: rows)
        }
        if rows.count >= 40 {
          podcastLibraryTotal = max(res.total, podcastEpisodes.count + 1)
        } else {
          podcastLibraryTotal = podcastEpisodes.count
        }
        podcastLibraryPage = res.page + 1
      }
    } catch {
      errorMessage = error.localizedDescription
    }
    if reset {
      await reloadPodcastShowsCatalog()
    }
  }

  /// Wenn `/recent-episodes` leer ist (z. B. alle Folgen fertig oder keine unbearbeiteten): Folgen aus expandierten Podcast-Items.
  private func loadPodcastEpisodesFallback(client: ABSAPIClient, libraryId: String) async -> [ABSPodcastEpisodeListItem] {
    do {
      let ascending = catalogSortField == .random ? true : !catalogSortDescending
      let sortKey = catalogSortField.apiSortParameter
      let (page, _) = try await client.libraryItems(
        libraryId: libraryId,
        page: 0,
        limit: 15,
        sort: sortKey,
        ascending: ascending,
        minified: true,
        filter: nil
      )
      let shows = page.results.filter(\.isListablePodcastLibraryItem)
      var collected: [ABSPodcastEpisodeListItem] = []
      collected.reserveCapacity(160)
      for show in shows {
        guard let full = try? await client.item(id: show.id, expanded: true) else { continue }
        guard let eps = full.media.podcastEpisodes, !eps.isEmpty else { continue }
        for dto in eps {
          if let row = ABSPodcastEpisodeListItem.fromDTO(
            dto, fallbackShow: full, libraryId: libraryId, forceLibraryItemId: full.id)
          {
            collected.append(row)
          }
        }
      }
      collected.sort {
        let pa = $0.publishedAt ?? 0
        let pb = $1.publishedAt ?? 0
        if pa != pb { return pa > pb }
        return $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedDescending
      }
      var seen = Set<String>()
      var deduped: [ABSPodcastEpisodeListItem] = []
      deduped.reserveCapacity(collected.count)
      for e in collected {
        let k = e.progressLookupKey
        if seen.insert(k).inserted { deduped.append(e) }
      }
      return Array(deduped.prefix(80))
    } catch {
      return []
    }
  }

  /// Folgenliste auf dem Podcast-Tab (recent „New“ oder eine Sendung).
  /// Abgeschlossene Folgen ausblenden, sobald `progressByItemId` es meldet (ohne auf `reloadPodcastLibrary` zu warten).
  var podcastEpisodesForPodcastsTab: [ABSPodcastEpisodeListItem] {
    let base = podcastSelectedShowId != nil ? podcastFilteredEpisodes : podcastEpisodes
    return base.filter { episode in
      !(progressByItemId[episode.progressLookupKey]?.isFinished ?? false)
    }
  }

  func reloadPodcastShowsCatalog() async {
    guard let c = client, let lib = selectedPodcastLibrary, isNetworkReachable else { return }
    podcastShowsLoading = true
    defer { podcastShowsLoading = false }
    do {
      let ascending = catalogSortField == .random ? true : !catalogSortDescending
      let sortKey = catalogSortField.apiSortParameter
      let (page, _) = try await c.libraryItems(
        libraryId: lib.id,
        page: 0,
        limit: 120,
        sort: sortKey,
        ascending: ascending,
        minified: true,
        filter: nil
      )
      podcastShows = page.results.filter(\.isListablePodcastLibraryItem)
    } catch {}
  }

  func selectPodcastShowFilter(_ showId: String?) async {
    podcastSelectedShowId = showId
    guard let showId else {
      podcastFilteredEpisodes = []
      await reloadPodcastLibrary(reset: true)
      return
    }
    podcastFilteredEpisodes = []
    await reloadPodcastLibrary(reset: true)
    await loadPodcastEpisodesForShowLibraryItem(showId)
  }

  private func loadPodcastEpisodesForShowLibraryItem(_ showId: String) async {
    guard let c = client, let lib = selectedPodcastLibrary else {
      podcastFilteredEpisodes = []
      return
    }
    podcastShowEpisodesLoadSerial &+= 1
    let serial = podcastShowEpisodesLoadSerial
    isLoadingPodcastShowEpisodes = true
    defer {
      if serial == podcastShowEpisodesLoadSerial {
        isLoadingPodcastShowEpisodes = false
      }
    }
    do {
      let full = try await c.item(id: showId, expanded: true)
      guard serial == podcastShowEpisodesLoadSerial, podcastSelectedShowId == showId else { return }
      guard let eps = full.media.podcastEpisodes, !eps.isEmpty else {
        guard serial == podcastShowEpisodesLoadSerial, podcastSelectedShowId == showId else { return }
        podcastFilteredEpisodes = []
        return
      }
      let rows: [ABSPodcastEpisodeListItem] = eps.compactMap {
        ABSPodcastEpisodeListItem.fromDTO(
          $0, fallbackShow: full, libraryId: lib.id, forceLibraryItemId: full.id)
      }
      var seen = Set<String>()
      let deduped = rows.filter { seen.insert($0.progressLookupKey).inserted }
      guard serial == podcastShowEpisodesLoadSerial, podcastSelectedShowId == showId else { return }
      podcastFilteredEpisodes = Self.sortPodcastEpisodesNewestFirst(deduped)
    } catch {
      guard serial == podcastShowEpisodesLoadSerial, podcastSelectedShowId == showId else { return }
      errorMessage = error.localizedDescription
      podcastFilteredEpisodes = []
    }
  }

  private static func sortPodcastEpisodesNewestFirst(_ rows: [ABSPodcastEpisodeListItem]) -> [ABSPodcastEpisodeListItem] {
    rows.sorted {
      let pa = $0.publishedAt ?? 0
      let pb = $1.publishedAt ?? 0
      if pa != pb { return pa > pb }
      return $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedDescending
    }
  }

  func loadMoreIfNeeded(currentItemId: String?) async {
    guard mainTab == .books else { return }
    guard let id = currentItemId, let last = books.last?.id, id == last, books.count < libraryTotal else { return }
    await reloadLibrary(reset: false)
  }

  func loadMorePodcastsIfNeeded(currentItemId: String?) async {
    guard mainTab == .podcasts else { return }
    guard podcastSelectedShowId == nil else { return }
    guard podcastEpisodesPagingFromRecentAPI else { return }
    guard
      let id = currentItemId, let last = podcastEpisodes.last?.id, id == last,
      podcastEpisodes.count < podcastLibraryTotal
    else { return }
    await reloadPodcastLibrary(reset: false)
  }

  /// Pull-to-Refresh: Bücher-Katalog (Server-Fortschritt + erste Seite neu).
  func refreshBooksCatalog() async {
    await refreshProgressFromServer()
    await reloadLibrary(reset: true)
  }

  /// Pull-to-Refresh: Podcast-Tab (Sendungsleiste, „New“-Liste oder gewählte Sendung).
  func refreshPodcastsTab() async {
    await refreshProgressFromServer()
    await reloadPodcastShowsCatalog()
    if let showId = podcastSelectedShowId {
      podcastFilteredEpisodes = []
      await reloadPodcastLibrary(reset: true)
      await loadPodcastEpisodesForShowLibraryItem(showId)
    } else {
      await reloadPodcastLibrary(reset: true)
    }
  }

  /// Pull-to-Refresh: Bibliothekssuche (aktueller Suchtext, ohne Debounce).
  func refreshBooksSearchResults() async {
    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    searchTask?.cancel()
    await performSearch(query: q)
  }

  func scheduleSearch() {
    guard mainTab == .books else { return }
    searchTask?.cancel()
    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    searchTask = Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      await performSearch(query: q)
    }
  }

  func clearSearchResults() {
    searchBooks = []
    searchAuthors = []
    searchNarrators = []
    searchSeries = []
    searchTags = []
    searchGenres = []
  }

  func clearPodcastSearchResults() {
    podcastSearchBooks = []
    podcastSearchAuthors = []
    podcastSearchNarrators = []
    podcastSearchSeries = []
    podcastSearchTags = []
    podcastSearchGenres = []
  }

  private func performSearch(query: String) async {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if query.count < 2 {
      clearSearchResults()
      return
    }
    isLoadingLibrary = true
    defer { isLoadingLibrary = false }
    do {
      let res = try await c.search(libraryId: lib.id, query: query)
      searchBooks = res.bookSearchPlayableLibraryItems { bookDuration($0) }
      searchAuthors = res.authors
      searchNarrators = res.narrators
      searchSeries = res.series
      searchTags = res.tags
      searchGenres = res.genres
    } catch {
      errorMessage = error.localizedDescription
      clearSearchResults()
    }
  }

  private func collapseExpandedBookRowsForCatalogFilter() {
    expandedItemId = nil
    expandedDetail = nil
  }

  private func setBooksLibraryFilterSummary(prefix: String, detail: String?) {
    let d = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    activeLibraryFilterSummary = d.isEmpty ? prefix : "\(prefix): \(d)"
  }

  func applyAuthorFilter(authorId: String, displayName: String? = nil) {
    searchTask?.cancel()
    searchText = ""
    clearSearchResults()
    collapseExpandedBookRowsForCatalogFilter()
    setBooksLibraryFilterSummary(prefix: "Author", detail: displayName)
    let b64 = Data(authorId.utf8).base64EncodedString()
    activeLibraryFilter = "authors.\(b64)"
    mainTab = .books
    Task { await reloadLibrary(reset: true) }
  }

  func applySeriesFilter(seriesId: String, displayName: String? = nil) {
    searchTask?.cancel()
    searchText = ""
    clearSearchResults()
    collapseExpandedBookRowsForCatalogFilter()
    setBooksLibraryFilterSummary(prefix: "Series", detail: displayName)
    let b64 = Data(seriesId.utf8).base64EncodedString()
    activeLibraryFilter = "series.\(b64)"
    mainTab = .books
    Task { await reloadLibrary(reset: true) }
  }

  func applyNarratorFilter(narratorName: String) {
    searchTask?.cancel()
    searchText = ""
    clearSearchResults()
    collapseExpandedBookRowsForCatalogFilter()
    setBooksLibraryFilterSummary(prefix: "Narrator", detail: narratorName)
    let b64 = Data(narratorName.utf8).base64EncodedString()
    activeLibraryFilter = "narrators.\(b64)"
    mainTab = .books
    Task { await reloadLibrary(reset: true) }
  }

  func applyTagFilter(tagName: String) {
    searchTask?.cancel()
    searchText = ""
    clearSearchResults()
    collapseExpandedBookRowsForCatalogFilter()
    setBooksLibraryFilterSummary(prefix: "Tag", detail: tagName)
    let b64 = Data(tagName.utf8).base64EncodedString()
    activeLibraryFilter = "tags.\(b64)"
    mainTab = .books
    Task { await reloadLibrary(reset: true) }
  }

  func applyGenreFilter(genreName: String) {
    searchTask?.cancel()
    searchText = ""
    clearSearchResults()
    collapseExpandedBookRowsForCatalogFilter()
    setBooksLibraryFilterSummary(prefix: "Genre", detail: genreName)
    let b64 = Data(genreName.utf8).base64EncodedString()
    activeLibraryFilter = "genres.\(b64)"
    mainTab = .books
    Task { await reloadLibrary(reset: true) }
  }

  func clearCatalogFilter() {
    guard activeLibraryFilter != nil else { return }
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    Task { await reloadLibrary(reset: true) }
  }

  /// Suche nach freiem Autor-String (z. B. nur `authorName` ohne `authors`-IDs): Bücher-Tab.
  func openBooksSearchFromText(_ raw: String) {
    let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty, q != "—" else { return }
    searchTask?.cancel()
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    searchText = q
    mainTab = .books
    Task { await performSearch(query: q) }
  }

  /// Katalog durchsuchender Sprung: Podcast-Tab, passende Sendung wählen oder Suche nach Show.
  func openPodcastSearchFromText(_ raw: String) {
    let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty, q != "—" else { return }
    podcastSearchTask?.cancel()
    expandedPodcastEpisodeId = nil
    expandedPodcastEpisodeDetail = nil
    podcastSearchText = ""
    mainTab = .podcasts
    Task { await navigatePodcastsToShowMatchingQuery(q) }
  }

  private func navigatePodcastsToShowMatchingQuery(_ query: String) async {
    if podcastShows.isEmpty { await reloadPodcastShowsCatalog() }
    let folded = { (s: String) -> String in
      s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
    let ql = folded(query)
    if let show = podcastShows.first(where: {
      let t = folded($0.displayTitle)
      return t.contains(ql) || (!t.isEmpty && ql.contains(t))
    }) {
      await selectPodcastShowFilter(show.id)
      return
    }
    guard let c = client, let lib = selectedPodcastLibrary else {
      await selectPodcastShowFilter(nil)
      return
    }
    do {
      let res = try await c.search(libraryId: lib.id, query: query, limit: 32)
      let shows = res.podcastSearchShowLibraryItems()
      if let first = shows.first {
        await selectPodcastShowFilter(first.id)
      } else {
        await selectPodcastShowFilter(nil)
      }
    } catch {
      errorMessage = error.localizedDescription
      await selectPodcastShowFilter(nil)
    }
  }

  /// Lädt den zuletzt relevanten Fortschritt (`mediaProgress`) in den Player — pausiert (Hörbuch oder Podcast-Folge).
  /// Fallback: gespeicherte Library-Item-ID (`UserDefaults`). Läuft parallel zum Katalog-Refresh.
  func restoreLastPlayedOnLaunch() async {
    isRestoringLaunchPlayback = true
    defer { isRestoringLaunchPlayback = false }
    guard let c = client else {
      player.setMiniPlayerPlaceholder(true)
      return
    }
    guard let progress = effectiveResumeProgress() else {
      player.setMiniPlayerPlaceholder(true)
      return
    }
    let libraryItemId = progress.libraryItemId
    UserDefaults.standard.set(libraryItemId, forKey: Keys.lastPlayedItemId)
    let trimmedEp = (progress.episodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let epId: String? = trimmedEp.isEmpty ? nil : trimmedEp
    if player.activeBook?.id == libraryItemId, player.activePlaybackEpisodeId == epId {
      return
    }

    if let episode = ABSPodcastEpisodeListItem.forResumePlayback(
      progress: progress,
      libraryId: selectedPodcastLibrary?.id
    ) {
      errorMessage = nil
      let resume = progressByItemId[episode.progressLookupKey]?.currentTime ?? progress.currentTime
      let stub = episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
      let local = localDownloadRoot(for: podcastEpisodeOfflineStorageId(episode))
      do {
        try await player.playBook(
          client: c,
          book: stub,
          resumeAt: resume,
          localDownloadRoot: local,
          episodeId: episode.episodeId,
          autoPlay: false
        )
      } catch {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
        player.setMiniPlayerPlaceholder(true)
        errorMessage = error.localizedDescription
      }
      return
    }

    let local = localDownloadRoot(for: libraryItemId)
    let resume = progress.currentTime
    do {
      let book: ABSBook
      if let root = local, let manifest = ABSDownloadManifest.load(from: root) {
        book = ABSBook.fromDownloadManifest(manifest)
      } else if isNetworkReachable {
        book = try await c.item(id: libraryItemId, expanded: true)
      } else {
        player.setMiniPlayerPlaceholder(true)
        return
      }
      try await player.playBook(
        client: c, book: book, resumeAt: resume, localDownloadRoot: local, episodeId: nil, autoPlay: false)
    } catch {
      UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      player.setMiniPlayerPlaceholder(true)
    }
  }

  func expandItem(_ id: String) async {
    if expandedItemId == id {
      expandedItemId = nil
      expandedDetail = nil
      return
    }
    expandedPodcastEpisodeId = nil
    expandedPodcastEpisodeDetail = nil
    expandedItemId = id
    guard let c = client else { return }
    do {
      expandedDetail = try await c.item(id: id, expanded: true)
    } catch {
      expandedDetail =
        books.first { $0.id == id }
        ?? podcastSearchBooks.first { $0.id == id }
        ?? podcastEpisodes.first { $0.libraryItemId == id }.map { $0.playbackStubBook(libraryId: selectedPodcastLibrary?.id) }
        ?? startBooks.first { $0.id == id }
        ?? searchBooks.first { $0.id == id }
        ?? downloadedShelfBooks.first { $0.id == id }
    }
  }

  func expandPodcastEpisode(_ episode: ABSPodcastEpisodeListItem) async {
    let key = episode.progressLookupKey
    if expandedPodcastEpisodeId == key {
      expandedPodcastEpisodeId = nil
      expandedPodcastEpisodeDetail = nil
      return
    }
    expandedItemId = nil
    expandedDetail = nil
    expandedPodcastEpisodeId = key
    expandedPodcastEpisodeDetail = nil
    guard let c = client, isNetworkReachable else {
      expandedPodcastEpisodeDetail = ABSPodcastEpisodeExpandedDetail(
        episode: episode,
        subtitle: nil,
        episodeDescriptionHTML: nil,
        showDescriptionHTML: nil,
        pubDate: nil,
        showGenres: nil,
        showAuthors: []
      )
      return
    }
    do {
      let show = try await c.item(id: episode.libraryItemId, expanded: true)
      let dto = show.media.podcastEpisodes?.first { $0.id == episode.episodeId }
      let showMeta = show.media.metadata
      let epDesc = dto?.description
      let subtitle = dto?.subtitle
      let pub = dto?.pubDate
      let genres = showMeta.genres
      let showDesc = showMeta.descriptionPlain ?? showMeta.description
      let authors = showMeta.authors ?? []
      expandedPodcastEpisodeDetail = ABSPodcastEpisodeExpandedDetail(
        episode: episode,
        subtitle: subtitle,
        episodeDescriptionHTML: epDesc,
        showDescriptionHTML: showDesc,
        pubDate: pub,
        showGenres: genres,
        showAuthors: authors
      )
    } catch {
      expandedPodcastEpisodeDetail = ABSPodcastEpisodeExpandedDetail(
        episode: episode,
        subtitle: nil,
        episodeDescriptionHTML: nil,
        showDescriptionHTML: nil,
        pubDate: nil,
        showGenres: nil,
        showAuthors: []
      )
    }
  }

  func play(book: ABSBook, autoPlay: Bool = true) async {
    guard let c = client else { return }
    errorMessage = nil
    let resume = progressByItemId[book.id]?.currentTime ?? 0
    let local = localDownloadRoot(for: book.id)
    do {
      var resolved = book
      if let root = local, let manifest = ABSDownloadManifest.load(from: root) {
        resolved = ABSBook.fromDownloadManifest(manifest)
      } else if isNetworkReachable {
        if local != nil {
          do {
            resolved = try await c.item(id: book.id, expanded: true)
          } catch {}
        } else if book.media.tracks == nil || book.media.tracks?.isEmpty == true {
          resolved = try await c.item(id: book.id, expanded: true)
        }
      }
      try await player.playBook(
        client: c, book: resolved, resumeAt: resume, localDownloadRoot: local, episodeId: nil,
        autoPlay: autoPlay)
      UserDefaults.standard.set(resolved.id, forKey: Keys.lastPlayedItemId)
      if autoPlay {
        mainTab = .start
        await loadStartDashboard()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func playPodcastEpisode(_ episode: ABSPodcastEpisodeListItem, autoPlay: Bool = true) async {
    guard let c = client else { return }
    errorMessage = nil
    let resume = progressByItemId[episode.progressLookupKey]?.currentTime ?? 0
    let stub = episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
    let offlineKey = podcastEpisodeOfflineStorageId(episode)
    let local = localDownloadRoot(for: offlineKey)
    do {
      try await player.playBook(
        client: c,
        book: stub,
        resumeAt: resume,
        localDownloadRoot: local,
        episodeId: episode.episodeId,
        autoPlay: autoPlay
      )
      UserDefaults.standard.set(stub.id, forKey: Keys.lastPlayedItemId)
      if autoPlay {
        mainTab = .start
        await loadStartDashboard()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func dismissPlayer() async {
    await player.closeSessionIfNeeded()
    player.tearDownPlayer()
    player.setMiniPlayerPlaceholder(true)
  }

  func markFinished(bookId: String) async {
    guard let c = client else { return }
    let wasCurrentPlayback = player.activeBook?.id == bookId && player.activePlaybackEpisodeId == nil
    do {
      try await c.markFinished(libraryItemId: bookId)
      let auth = try await c.authorize()
      applyUserProgress(auth.user.mediaProgress)
      searchBooks.removeAll { $0.id == bookId }
      podcastSearchBooks.removeAll { $0.id == bookId }
      await reloadLibrary(reset: true)
      await reloadPodcastLibrary(reset: true)
      expandedItemId = nil
      expandedDetail = nil
      if expandedPodcastEpisodeDetail?.episode.libraryItemId == bookId {
        expandedPodcastEpisodeId = nil
        expandedPodcastEpisodeDetail = nil
      }
      if wasCurrentPlayback {
        await dismissPlayer()
      }
      if UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == bookId {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      }
      await loadStartDashboard()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func markUnfinished(bookId: String) async {
    guard let c = client else { return }
    do {
      try await c.patchProgress(
        libraryItemId: bookId,
        episodeId: nil,
        patch: ABSProgressPatch(currentTime: nil, duration: nil, progress: nil, isFinished: false)
      )
      let auth = try await c.authorize()
      applyUserProgress(auth.user.mediaProgress)
      await reloadLibrary(reset: true)
      await reloadPodcastLibrary(reset: true)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func removePodcastEpisodeFromLocalCatalogLists(_ episode: ABSPodcastEpisodeListItem) {
    let ep = episode.episodeId.trimmingCharacters(in: .whitespacesAndNewlines)
    let show = episode.libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    let key = episode.progressLookupKey
    guard !ep.isEmpty, !show.isEmpty else { return }
    podcastEpisodes.removeAll {
      $0.progressLookupKey == key
        || ($0.episodeId.trimmingCharacters(in: .whitespacesAndNewlines) == ep
          && $0.libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines) == show)
    }
    podcastFilteredEpisodes.removeAll {
      $0.progressLookupKey == key
        || ($0.episodeId.trimmingCharacters(in: .whitespacesAndNewlines) == ep
          && $0.libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines) == show)
    }
  }

  func markPodcastEpisodeFinished(_ episode: ABSPodcastEpisodeListItem) async {
    guard let c = client else { return }
    let wasPlaying =
      player.activeBook?.id == episode.libraryItemId && player.activePlaybackEpisodeId == episode.episodeId
    do {
      try await c.markFinished(libraryItemId: episode.libraryItemId, episodeId: episode.episodeId)
      let auth = try await c.authorize()
      applyUserProgress(auth.user.mediaProgress)
      removePodcastEpisodeFromLocalCatalogLists(episode)
      await reloadPodcastLibrary(reset: true)
      if let d = expandedPodcastEpisodeDetail,
        d.episode.progressLookupKey == episode.progressLookupKey
          || (d.episode.episodeId == episode.episodeId && d.episode.libraryItemId == episode.libraryItemId)
      {
        expandedPodcastEpisodeId = nil
        expandedPodcastEpisodeDetail = nil
      }
      if wasPlaying {
        await dismissPlayer()
      }
      await loadStartDashboard()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func markPodcastEpisodeUnfinished(_ episode: ABSPodcastEpisodeListItem) async {
    guard let c = client else { return }
    do {
      try await c.patchProgress(
        libraryItemId: episode.libraryItemId,
        episodeId: episode.episodeId,
        patch: ABSProgressPatch(currentTime: nil, duration: nil, progress: nil, isFinished: false)
      )
      let auth = try await c.authorize()
      applyUserProgress(auth.user.mediaProgress)
      await reloadPodcastLibrary(reset: true)
      await loadStartDashboard()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Ordnername unter `Documents/Downloads` für eine Podcast-Folge (nicht `libraryItemId` allein).
  func podcastEpisodeOfflineStorageId(_ episode: ABSPodcastEpisodeListItem) -> String {
    episode.progressLookupKey.replacingOccurrences(of: "/", with: "_")
  }

  func startDownloadPodcastEpisode(_ episode: ABSPodcastEpisodeListItem) {
    guard let c = client else { return }
    let stub = episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
    let sid = podcastEpisodeOfflineStorageId(episode)
    downloads.startDownload(
      client: c, book: stub, episodeId: episode.episodeId, storageItemId: sid
    ) { [weak self] ok in
      Task { @MainActor [weak self] in
        guard let model = self, ok else { return }
        model.downloadedItemIds.insert(sid)
        model.persistDownloads()
      }
    }
  }

  /// Entfernt den Eintrag aus der Audiobookshelf-Datenbank (wie Web-UI „Löschen“).
  func deleteFromServer(bookId: String) async {
    guard let c = client else { return }
    do {
      try await c.deleteLibraryItem(id: bookId)
      downloads.deleteDownload(itemId: bookId)
      downloadedItemIds.remove(bookId)
      persistDownloads()
      progressByItemId[bookId] = nil
      books.removeAll { $0.id == bookId }
      podcastEpisodes.removeAll { $0.libraryItemId == bookId }
      startBooks.removeAll { $0.id == bookId }
      searchBooks.removeAll { $0.id == bookId }
      podcastSearchBooks.removeAll { $0.id == bookId }
      if player.activeBook?.id == bookId {
        await dismissPlayer()
      }
      if UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == bookId {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      }
      expandedItemId = nil
      expandedDetail = nil
      if expandedPodcastEpisodeDetail?.episode.libraryItemId == bookId {
        expandedPodcastEpisodeId = nil
        expandedPodcastEpisodeDetail = nil
      }
      await refreshProgressFromServer()
      await loadStartDashboard()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func startDownload(book: ABSBook) {
    guard let c = client else { return }
    downloads.startDownload(client: c, book: book) { [weak self] ok in
      Task { @MainActor [weak self] in
        guard let model = self, ok else { return }
        model.downloadedItemIds.insert(book.id)
        model.persistDownloads()
      }
    }
  }

  func removeLocalDownload(bookId: String) {
    downloads.deleteDownload(itemId: bookId)
    downloadedItemIds.remove(bookId)
    persistDownloads()
  }

  func localDownloadRoot(for itemId: String) -> URL? {
    guard downloadedItemIds.contains(itemId) else { return nil }
    return try? downloads.downloadFolder(for: itemId)
  }

  func coverURL(for itemId: String) -> URL? {
    guard let url = ABSAPIClient.normalizeServerURL(serverURL) else { return nil }
    return url.appendingPathComponent("api/items/\(itemId)/cover")
  }

  /// Ordner für Library-Cache inkl. Cover (`LibraryDiskCache.accountDir`); nil ohne Login/URL.
  func coverImageCacheAccountDirectory() -> URL? {
    cacheAccountURL()
  }

  func coverImageCacheByteCount() -> Int64 {
    guard let account = cacheAccountURL() else { return 0 }
    return CoverImageCache.totalByteCount(account: account)
  }

  func clearCoverImageCache() {
    guard let account = cacheAccountURL() else { return }
    CoverImageCache.clearAll(account: account)
    coverImageCacheRevision &+= 1
  }

  func applySleepTimer(minutes: Int?) {
    if let m = minutes {
      player.sleepEndDate = Date().addingTimeInterval(TimeInterval(m * 60))
    } else {
      player.sleepEndDate = nil
    }
  }

  func applyPlaybackSpeed(_ rate: Float) {
    player.setPlaybackRate(rate)
  }

  /// Fortschritt per PATCH, wenn kein Stream-Session-Sync läuft (z. B. nur lokale Dateien).
  func syncProgressToServer() async {
    guard let c = client, let bid = player.activeBook?.id, !player.isRemotePlaySessionActive else { return }
    let dur = player.totalDuration
    guard dur > 0 else { return }
    let pos = player.globalPosition
    let prog = min(1, max(0, pos / dur))
    do {
      try await c.patchProgress(
        libraryItemId: bid,
        episodeId: player.activePlaybackEpisodeId,
        patch: ABSProgressPatch(currentTime: pos, duration: dur, progress: prog, isFinished: nil)
      )
    } catch {}
  }

  private func persistDownloads() {
    UserDefaults.standard.set(Array(downloadedItemIds), forKey: Keys.downloads)
    refreshDownloadedShelfFromManifests()
  }

  private func cacheAccountURL() -> URL? {
    guard let u = ABSAPIClient.normalizeServerURL(serverURL)?.absoluteString, !token.isEmpty else { return nil }
    return LibraryDiskCache.accountDir(serverURL: u)
  }

  /// Bücher-Katalog + Home-Regale aus dem letzten Server-Stand.
  private func restoreBooksCatalogAndHomeFromDisk(libraryIdOverride: String? = nil) {
    guard let account = cacheAccountURL() else { return }
    let dec = ABSJSON.decoder()
    if let list = LibraryDiskCache.loadProgress(account: account, decoder: dec) {
      applyUserProgress(list, persistToDisk: false)
    }
    let libId =
      (libraryIdOverride ?? UserDefaults.standard.string(forKey: Keys.booksLibrary))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if libId == Keys.librarySelectionNone {
      selectedBooksLibrary = nil
      books = []
      libraryTotal = 0
      libraryPage = 0
      applyLocalContinueListeningFromCachedBooks()
      return
    }
    guard !libId.isEmpty else {
      applyLocalContinueListeningFromCachedBooks()
      return
    }
    let ascending = catalogSortField == .random ? true : !catalogSortDescending
    let sortKey = catalogSortField.apiSortParameter
    if let merged = LibraryDiskCache.loadMergedCatalog(
      account: account,
      libraryId: libId,
      filter: activeLibraryFilter,
      sortField: sortKey,
      ascending: ascending,
      decoder: dec
    ) {
      books = merged.books
      libraryTotal = merged.total
      libraryPage = merged.nextPage
    } else if libraryIdOverride != nil {
      books = []
      libraryTotal = 0
      libraryPage = 0
    }
    if selectedBooksLibrary == nil || selectedBooksLibrary?.id != libId {
      selectedBooksLibrary = ABSLibrary(id: libId, name: "Books", mediaType: "book", displayOrder: nil)
    }
    if let pdata = LibraryDiskCache.loadPersonalized(account: account, libraryId: libId) {
      let parsed = ABSAPIClient.parsePersonalizedStartShelves(data: pdata)
      let visible = parsed.filter { isStartCategoryEnabled($0.category) }
      if !visible.isEmpty {
        startShelves = visible
        recomputeStartBooksUnion(from: visible)
        return
      }
    }
    applyLocalContinueListeningFromCachedBooks()
  }

  /// Lädt gespeicherte Podcast-Folgen (recent-episodes-Seiten oder Expand-Fallback) vom Datenträger.
  private func applyPodcastListFromDisk(libraryId: String) {
    let lid = libraryId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lid.isEmpty, let account = cacheAccountURL() else { return }
    let dec = ABSJSON.decoder()
    if let merged = LibraryDiskCache.loadMergedPodcastRecent(
      account: account,
      libraryId: lid,
      libraryIdForRows: lid,
      decoder: dec
    ), !merged.episodes.isEmpty {
      podcastEpisodes = merged.episodes
      podcastLibraryTotal = max(merged.total, merged.episodes.count)
      podcastLibraryPage = merged.nextPageIndex
      podcastEpisodesPagingFromRecentAPI = true
      return
    }
    if let fb = LibraryDiskCache.loadPodcastFallback(account: account, libraryId: lid), !fb.isEmpty {
      podcastEpisodes = fb
      podcastLibraryTotal = fb.count
      podcastLibraryPage = 1
      podcastEpisodesPagingFromRecentAPI = false
    }
  }

  private func restorePodcastCatalogFromDisk(libraryIdOverride: String? = nil) {
    let libId =
      (libraryIdOverride ?? UserDefaults.standard.string(forKey: Keys.podcastsLibrary))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if libId == Keys.librarySelectionNone {
      selectedPodcastLibrary = nil
      podcastEpisodes = []
      podcastLibraryPage = 0
      podcastLibraryTotal = 0
      return
    }
    guard !libId.isEmpty else {
      podcastEpisodes = []
      podcastLibraryPage = 0
      podcastLibraryTotal = 0
      return
    }
    podcastEpisodes = []
    podcastLibraryPage = 0
    podcastLibraryTotal = 0
    if selectedPodcastLibrary == nil || selectedPodcastLibrary?.id != libId {
      selectedPodcastLibrary = ABSLibrary(id: libId, name: "Podcasts", mediaType: "podcast", displayOrder: nil)
    }
    applyPodcastListFromDisk(libraryId: libId)
    /// Bücher-/Home-Cache wird in `selectBooksLibrary` zuerst geladen; Podcast-Folgen danach — ohne Merge fehlen Episoden im Personalized-Regal bis zum Netzwerk-Refresh.
    if !startShelves.isEmpty {
      mergePodcastContinueFromLocalProgress()
    }
  }

  /// Offline: Regale aus Cache, sonst „Weiterhören“ aus Katalog + gespeichertem Fortschritt.
  private func applyOfflineHomeShelvesIfNeeded() {
    if !startShelves.isEmpty { return }
    guard let account = cacheAccountURL(), let libId = selectedBooksLibrary?.id else {
      applyLocalContinueListeningFromCachedBooks()
      return
    }
    if let pdata = LibraryDiskCache.loadPersonalized(account: account, libraryId: libId) {
      let parsed = ABSAPIClient.parsePersonalizedStartShelves(data: pdata)
      let visible = parsed.filter { isStartCategoryEnabled($0.category) }
      if !visible.isEmpty {
        startShelves = visible
        recomputeStartBooksUnion(from: visible)
        mergePodcastContinueFromLocalProgress()
        return
      }
    }
    applyLocalContinueListeningFromCachedBooks()
  }

  /// Ohne `/personalized` und ohne `items-in-progress`: Bücher aus dem Katalog-Cache mit lokalem Fortschritt.
  private func applyLocalContinueListeningFromCachedBooks() {
    let cat = "itemsInProgressFallback"
    guard isStartCategoryEnabled("recentlyListened") else {
      startShelves = []
      startBooks = []
      return
    }
    let filtered: [ABSBook]
    if selectedBooksLibrary == nil {
      filtered = []
    } else {
      let pool = books + startBooks
      var seen = Set<String>()
      var candidates: [ABSBook] = []
      for b in pool where !seen.contains(b.id) {
        seen.insert(b.id)
        candidates.append(b)
      }
      filtered = candidates.filter { b in
        guard let p = progressByItemId[b.id], !p.isFinished, p.currentTime > 2 else { return false }
        return b.isPlayableAudiobook
      }.sorted {
        (progressByItemId[$0.id]?.lastUpdate ?? 0) > (progressByItemId[$1.id]?.lastUpdate ?? 0)
      }
    }
    let podcastEps = localContinuePodcastEpisodeCandidates()
    guard !filtered.isEmpty || !podcastEps.isEmpty else {
      startShelves = []
      startBooks = []
      return
    }
    let title = ABSStartShelfLocalization.displayTitle(category: cat, serverLabel: "")
    let section = ABSStartShelfSection(
      id: "local-cache-continue",
      category: cat,
      displayTitle: title,
      books: filtered,
      podcastEpisodes: podcastEps,
      authors: []
    )
    startShelves = [section]
    recomputeStartBooksUnion(from: [section])
  }

  private func localContinuePodcastEpisodeCandidates() -> [ABSPodcastEpisodeListItem] {
    guard selectedPodcastLibrary != nil else { return [] }
    var pool: [ABSPodcastEpisodeListItem] = []
    for e in podcastEpisodes {
      guard let p = progressByItemId[e.progressLookupKey], !p.isFinished, p.currentTime > 2 else { continue }
      pool.append(e)
    }
    if let lid = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
      pool = pool.filter { ($0.libraryId ?? "") == lid || $0.libraryId == nil }
    }
    return dedupePodcastEpisodesForHomeContinueList(pool)
  }

  private func mergePodcastContinueFromLocalProgress() {
    let eps = localContinuePodcastEpisodeCandidates()
    mergePodcastEpisodesIntoContinueShelves(
      payload: ABSItemsInProgressPayload(books: [], podcastEpisodes: eps))
  }

  private func applyUserProgress(_ list: [ABSUserMediaProgress]?, persistToDisk: Bool = true) {
    progressByItemId = [:]
    let all = list ?? []
    for p in all {
      progressByItemId[p.progressLookupKey] = p
    }
    syncLastPlayedPreferenceWithServerProgress()
    applyContinueListeningFinishedFilter()
    guard persistToDisk, let account = cacheAccountURL() else { return }
    try? LibraryDiskCache.saveProgress(account: account, list: all)
  }

  private func resumeProgressOrderedBefore(_ a: ABSUserMediaProgress, _ b: ABSUserMediaProgress) -> Bool {
    let t0 = a.lastUpdate ?? 0
    let t1 = b.lastUpdate ?? 0
    if t0 != t1 { return t0 < t1 }
    return a.currentTime < b.currentTime
  }

  private func serverPreferredResumeProgress() -> ABSUserMediaProgress? {
    let items = progressByItemId.values.filter { !$0.isFinished }
    guard !items.isEmpty else { return nil }
    return items.max(by: resumeProgressOrderedBefore)
  }

  /// Hörbuch mit aktuellstem `lastUpdate` im Server-Fortschritt (nur nicht abgeschlossen).
  private func serverPreferredResumeLibraryItemId() -> String? {
    serverPreferredResumeProgress()?.libraryItemId
  }

  private func effectiveResumeProgress() -> ABSUserMediaProgress? {
    if let p = serverPreferredResumeProgress() { return p }
    let raw =
      UserDefaults.standard.string(forKey: Keys.lastPlayedItemId)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !raw.isEmpty else { return nil }
    let candidates = progressByItemId.values.filter { !$0.isFinished && $0.libraryItemId == raw }
    return candidates.max(by: resumeProgressOrderedBefore)
  }

  private func syncLastPlayedPreferenceWithServerProgress() {
    guard let sid = serverPreferredResumeLibraryItemId(), !sid.isEmpty else { return }
    UserDefaults.standard.set(sid, forKey: Keys.lastPlayedItemId)
  }

  private func bookDuration(_ b: ABSBook) -> Double {
    b.media.duration ?? 0
  }
}

extension AppModel {
  /// SwiftUI-`Picker`/`tag` für „keine Bibliothek“ (persistiert als `Keys.librarySelectionNone`).
  static var libraryPickerNoneTag: String { Keys.librarySelectionNone }
}
