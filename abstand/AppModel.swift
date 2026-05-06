import Combine
import Foundation
import Network
import SwiftUI

private enum Keys {
  static let server = "abstand_server_url"
  static let token = "abstand_token"
  static let library = "abstand_library_id"
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
  @Published var libraries: [ABSLibrary] = []

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
  @Published var selectedLibrary: ABSLibrary?
  @Published var books: [ABSBook] = []
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
  @Published var searchAuthors: [ABSSearchAuthorRow] = []
  @Published var searchNarrators: [ABSSearchNarratorRow] = []
  @Published var searchSeries: [ABSSearchSeriesRow] = []
  @Published var searchTags: [ABSSearchNamedCount] = []
  @Published var searchGenres: [ABSSearchNamedCount] = []
  /// Server-Items-Filter (z. B. `authors.<base64>`), nur Katalog-Tab.
  @Published var activeLibraryFilter: String?
  @Published var mainTab: MainTab = .start
  @Published var expandedItemId: String?
  @Published var expandedDetail: ABSBook?
  @Published var isLoadingLibrary = false
  @Published var errorMessage: String?
  @Published var showSleepPicker = false
  @Published var showPlaybackSpeedPicker = false
  @Published var downloadedItemIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Keys.downloads) ?? [])
  /// Aus `download.json` gebaute Stubs für Home-Regal „Heruntergeladen“ und Offline-Katalog.
  @Published private(set) var downloadedShelfBooks: [ABSBook] = []
  @Published private(set) var isNetworkReachable = true
  /// Mini-Player: Session aus Server-Fortschritt / `item`-Laden; UI kann sofort Skelett zeigen.
  @Published private(set) var isRestoringLaunchPlayback = false

  private(set) var token: String = UserDefaults.standard.string(forKey: Keys.token) ?? ""

  let player = PlaybackController()
  let downloads = DownloadManager()

  private var cancellables = Set<AnyCancellable>()

  private var client: ABSAPIClient?
  private var libraryPage = 0
  private var libraryTotal = 0
  private var searchTask: Task<Void, Never>?
  private let pathMonitor = NWPathMonitor()
  private let pathMonitorQueue = DispatchQueue(label: "de.letzgo.abstand.network")

  enum MainTab: String, CaseIterable, Hashable {
    case start = "Home"
    case library = "Library"
    case search = "Search"
    case settings = "Settings"
  }

  init() {
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
    restoreCatalogAndHomeFromDisk()
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
    case .library:
      if !isNetworkReachable, !books.isEmpty { return books }
      if !isNetworkReachable { return downloadedShelfBooks }
      return books
    case .start, .settings:
      return []
    case .search:
      return searchBooks
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
          libraryId: selectedLibrary?.id,
          media: stubMedia,
          addedAt: nil,
          updatedAt: nil
        ))
    }
    return out
  }

  /// Bibliotheken wie vom Server vorgesehen (`displayOrder`, dann Name).
  var sortedLibraries: [ABSLibrary] {
    libraries.sorted {
      if $0.displayOrderOrZero != $1.displayOrderOrZero {
        return $0.displayOrderOrZero < $1.displayOrderOrZero
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
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
      libraries = try await c.libraries().filter(\.isBookLibrary)
      if let sel = selectedLibrary {
        if !libraries.contains(where: { $0.id == sel.id }) {
          if let first = libraries.first {
            selectLibrary(first, navigateToCatalog: false)
          } else {
            selectedLibrary = nil
          }
        }
      } else if let first = libraries.first {
        selectLibrary(first, navigateToCatalog: false)
      }
      await loadStartDashboard()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Lädt personalisierte Regale der aktuellen Bibliothek; Fallback: `items-in-progress`.
  /// Cache zuerst (beim App-Start), hier nur mit Live-Daten überschreiben — kein blockierender Ladezustand für Home.
  func loadStartDashboard() async {
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
      if let lib = selectedLibrary {
        let data = try await c.personalizedShelves(libraryId: lib.id, limit: 14)
        if let root = cacheAccountURL() {
          try? LibraryDiskCache.savePersonalized(account: root, libraryId: lib.id, data: data)
        }
        let parsed = ABSAPIClient.parsePersonalizedStartShelves(data: data)
        updateStartSettingsCategoryList(parsed: parsed)
        if parsed.isEmpty {
          try await applyStartDashboardInProgressFallback(client: c)
        } else {
          let visible = parsed.filter { isStartCategoryEnabled($0.category) }
          startShelves = visible
          recomputeStartBooksUnion(from: visible)
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

  private func applyStartDashboardInProgressFallback(client: ABSAPIClient) async throws {
    var items = try await client.itemsInProgress(limit: 80)
    if let lib = selectedLibrary {
      items = items.filter { book in
        guard let lid = book.libraryId else { return true }
        return lid == lib.id
      }
    }
    let filtered = items.filter(\.isPlayableAudiobook).sorted {
      (progressByItemId[$0.id]?.lastUpdate ?? 0) > (progressByItemId[$1.id]?.lastUpdate ?? 0)
    }
    let cat = "itemsInProgressFallback"
    let title = ABSStartShelfLocalization.displayTitle(category: cat, serverLabel: "")
    let section = ABSStartShelfSection(
      id: "items-in-progress-fallback",
      category: cat,
      displayTitle: title,
      books: filtered,
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
      libraries = try await c.libraries().filter(\.isBookLibrary)
      if let savedLib = UserDefaults.standard.string(forKey: Keys.library),
        let lib = libraries.first(where: { $0.id == savedLib })
      {
        selectedLibrary = lib
      } else if let first = libraries.first {
        selectLibrary(first)
      }
      async let catalog: Void = await reloadLibrary(reset: true)
      async let mini: Void = await restoreLastPlayedOnLaunch()
      _ = await (catalog, mini)
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
      libraries = try await c.libraries().filter(\.isBookLibrary)
      if let def = res.userDefaultLibraryId, let lib = libraries.first(where: { $0.id == def }) {
        selectLibrary(lib)
      } else if let first = libraries.first {
        selectLibrary(first)
      }
      async let catalog: Void = await reloadLibrary(reset: true)
      async let mini: Void = await restoreLastPlayedOnLaunch()
      _ = await (catalog, mini)
    } catch {
      errorMessage = error.localizedDescription
      isRestoringLaunchPlayback = false
      player.setMiniPlayerPlaceholder(true)
    }
  }

  func logout() {
    token = ""
    UserDefaults.standard.removeObject(forKey: Keys.token)
    client = nil
    libraries = []
    selectedLibrary = nil
    books = []
    startBooks = []
    startShelves = []
    searchBooks = []
    searchAuthors = []
    searchNarrators = []
    searchSeries = []
    searchTags = []
    searchGenres = []
    searchText = ""
    activeLibraryFilter = nil
    progressByItemId = [:]
    expandedItemId = nil
    expandedDetail = nil
    UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
    player.tearDownPlayer()
    downloadedShelfBooks = []
    isRestoringLaunchPlayback = false
    LibraryDiskCache.clearEverything()
  }

  func selectLibrary(_ lib: ABSLibrary, navigateToCatalog: Bool = false) {
    activeLibraryFilter = nil
    selectedLibrary = lib
    UserDefaults.standard.set(lib.id, forKey: Keys.library)
    if navigateToCatalog { mainTab = .library }
    restoreCatalogAndHomeFromDisk(libraryIdOverride: lib.id)
  }

  func reloadLibrary(reset: Bool) async {
    guard let c = client, let lib = selectedLibrary else {
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

  func loadMoreIfNeeded(currentItemId: String?) async {
    guard mainTab == .library, activeLibraryFilter == nil else { return }
    guard let id = currentItemId, let last = books.last?.id, id == last, books.count < libraryTotal else { return }
    await reloadLibrary(reset: false)
  }

  func scheduleSearch() {
    guard mainTab == .search else { return }
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

  private func performSearch(query: String) async {
    guard let c = client, let lib = selectedLibrary else { return }
    if query.count < 2 {
      clearSearchResults()
      return
    }
    isLoadingLibrary = true
    defer { isLoadingLibrary = false }
    do {
      let res = try await c.search(libraryId: lib.id, query: query)
      searchBooks = res.book.map(\.libraryItem).filter {
        ($0.media.numTracks ?? 0) > 0 || bookDuration($0) > 0
      }
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

  func applyAuthorFilter(authorId: String) {
    let b64 = Data(authorId.utf8).base64EncodedString()
    activeLibraryFilter = "authors.\(b64)"
    mainTab = .library
    Task { await reloadLibrary(reset: true) }
  }

  func applySeriesFilter(seriesId: String) {
    let b64 = Data(seriesId.utf8).base64EncodedString()
    activeLibraryFilter = "series.\(b64)"
    mainTab = .library
    Task { await reloadLibrary(reset: true) }
  }

  func applyNarratorFilter(narratorName: String) {
    let b64 = Data(narratorName.utf8).base64EncodedString()
    activeLibraryFilter = "narrators.\(b64)"
    mainTab = .library
    Task { await reloadLibrary(reset: true) }
  }

  func applyTagFilter(tagName: String) {
    let b64 = Data(tagName.utf8).base64EncodedString()
    activeLibraryFilter = "tags.\(b64)"
    mainTab = .library
    Task { await reloadLibrary(reset: true) }
  }

  func applyGenreFilter(genreName: String) {
    let b64 = Data(genreName.utf8).base64EncodedString()
    activeLibraryFilter = "genres.\(b64)"
    mainTab = .library
    Task { await reloadLibrary(reset: true) }
  }

  func clearCatalogFilter() {
    guard activeLibraryFilter != nil else { return }
    activeLibraryFilter = nil
    Task { await reloadLibrary(reset: true) }
  }

  /// Lädt das zuletzt vom **Server** relevante Hörbuch (mediaProgress, `lastUpdate`) in den Player — pausiert.
  /// Fallback: zuletzt auf dem Gerät gestartete ID (`UserDefaults`). Läuft parallel zum Katalog-Refresh.
  func restoreLastPlayedOnLaunch() async {
    isRestoringLaunchPlayback = true
    defer { isRestoringLaunchPlayback = false }
    guard let c = client else {
      player.setMiniPlayerPlaceholder(true)
      return
    }
    guard let id = effectiveResumeLibraryItemId(), !id.isEmpty else {
      player.setMiniPlayerPlaceholder(true)
      return
    }
    UserDefaults.standard.set(id, forKey: Keys.lastPlayedItemId)
    if player.activeBook?.id == id { return }
    let local = localDownloadRoot(for: id)
    let resume = progressByItemId[id]?.currentTime ?? 0
    do {
      let book: ABSBook
      if let root = local, let manifest = ABSDownloadManifest.load(from: root) {
        book = ABSBook.fromDownloadManifest(manifest)
      } else if isNetworkReachable {
        book = try await c.item(id: id, expanded: true)
      } else {
        player.setMiniPlayerPlaceholder(true)
        return
      }
      try await player.playBook(
        client: c, book: book, resumeAt: resume, localDownloadRoot: local, autoPlay: false)
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
    expandedItemId = id
    guard let c = client else { return }
    do {
      expandedDetail = try await c.item(id: id, expanded: true)
    } catch {
      expandedDetail =
        books.first { $0.id == id }
        ?? startBooks.first { $0.id == id }
        ?? searchBooks.first { $0.id == id }
        ?? downloadedShelfBooks.first { $0.id == id }
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
        client: c, book: resolved, resumeAt: resume, localDownloadRoot: local, autoPlay: autoPlay)
      UserDefaults.standard.set(resolved.id, forKey: Keys.lastPlayedItemId)
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
    let wasCurrentPlayback = player.activeBook?.id == bookId
    do {
      try await c.markFinished(libraryItemId: bookId)
      let auth = try await c.authorize()
      applyUserProgress(auth.user.mediaProgress)
      searchBooks.removeAll { $0.id == bookId }
      await reloadLibrary(reset: true)
      expandedItemId = nil
      expandedDetail = nil
      if wasCurrentPlayback {
        await dismissPlayer()
      }
      if UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == bookId {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func markUnfinished(bookId: String) async {
    guard let c = client else { return }
    do {
      try await c.patchProgress(
        libraryItemId: bookId,
        patch: ABSProgressPatch(currentTime: nil, duration: nil, progress: nil, isFinished: false)
      )
      let auth = try await c.authorize()
      applyUserProgress(auth.user.mediaProgress)
      await reloadLibrary(reset: true)
    } catch {
      errorMessage = error.localizedDescription
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
      startBooks.removeAll { $0.id == bookId }
      searchBooks.removeAll { $0.id == bookId }
      if player.activeBook?.id == bookId {
        await dismissPlayer()
      }
      if UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == bookId {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      }
      expandedItemId = nil
      expandedDetail = nil
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

  func applySleepTimer(minutes: Int?) {
    if let m = minutes {
      player.sleepEndDate = Date().addingTimeInterval(TimeInterval(m * 60))
    } else {
      player.sleepEndDate = nil
    }
    showSleepPicker = false
  }

  func applyPlaybackSpeed(_ rate: Float) {
    player.setPlaybackRate(rate)
    showPlaybackSpeedPicker = false
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

  /// Katalog + Home aus dem letzten erfolgreichen Server-Stand (sofort beim Start / Bibliothekswechsel).
  private func restoreCatalogAndHomeFromDisk(libraryIdOverride: String? = nil) {
    guard let account = cacheAccountURL() else { return }
    let dec = ABSJSON.decoder()
    if let list = LibraryDiskCache.loadProgress(account: account, decoder: dec) {
      applyUserProgress(list, persistToDisk: false)
    }
    let libId =
      (libraryIdOverride ?? UserDefaults.standard.string(forKey: Keys.library))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
    if selectedLibrary == nil || selectedLibrary?.id != libId {
      selectedLibrary = ABSLibrary(id: libId, name: "Bibliothek", mediaType: "book", displayOrder: nil)
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

  /// Offline: Regale aus Cache, sonst „Weiterhören“ aus Katalog + gespeichertem Fortschritt.
  private func applyOfflineHomeShelvesIfNeeded() {
    if !startShelves.isEmpty { return }
    guard let account = cacheAccountURL(), let libId = selectedLibrary?.id else {
      applyLocalContinueListeningFromCachedBooks()
      return
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

  /// Ohne `/personalized` und ohne `items-in-progress`: Bücher aus dem Katalog-Cache mit lokalem Fortschritt.
  private func applyLocalContinueListeningFromCachedBooks() {
    let cat = "itemsInProgressFallback"
    guard isStartCategoryEnabled("recentlyListened") else {
      startShelves = []
      startBooks = []
      return
    }
    let pool = books + startBooks
    var seen = Set<String>()
    var candidates: [ABSBook] = []
    for b in pool where !seen.contains(b.id) {
      seen.insert(b.id)
      candidates.append(b)
    }
    let filtered = candidates.filter { b in
      guard let p = progressByItemId[b.id], !p.isFinished, p.currentTime > 2 else { return false }
      return b.isPlayableAudiobook
    }.sorted {
      (progressByItemId[$0.id]?.lastUpdate ?? 0) > (progressByItemId[$1.id]?.lastUpdate ?? 0)
    }
    guard !filtered.isEmpty else {
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
      authors: []
    )
    startShelves = [section]
    recomputeStartBooksUnion(from: [section])
  }

  private func applyUserProgress(_ list: [ABSUserMediaProgress]?, persistToDisk: Bool = true) {
    progressByItemId = [:]
    let flat = (list ?? []).filter { $0.episodeId == nil }
    for p in flat {
      progressByItemId[p.libraryItemId] = p
    }
    syncLastPlayedPreferenceWithServerProgress()
    guard persistToDisk, let account = cacheAccountURL() else { return }
    try? LibraryDiskCache.saveProgress(account: account, list: flat)
  }

  /// Hörbuch mit aktuellstem `lastUpdate` im Server-Fortschritt (nur nicht abgeschlossen).
  private func serverPreferredResumeLibraryItemId() -> String? {
    let items = progressByItemId.values.filter { !$0.isFinished }
    guard !items.isEmpty else { return nil }
    return items.max(by: {
      let t0 = $0.lastUpdate ?? 0
      let t1 = $1.lastUpdate ?? 0
      if t0 != t1 { return t0 < t1 }
      return $0.currentTime < $1.currentTime
    })?.libraryItemId
  }

  private func syncLastPlayedPreferenceWithServerProgress() {
    guard let sid = serverPreferredResumeLibraryItemId(), !sid.isEmpty else { return }
    UserDefaults.standard.set(sid, forKey: Keys.lastPlayedItemId)
  }

  private func effectiveResumeLibraryItemId() -> String? {
    if let s = serverPreferredResumeLibraryItemId() { return s }
    let raw = UserDefaults.standard.string(forKey: Keys.lastPlayedItemId)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return raw.isEmpty ? nil : raw
  }

  private func bookDuration(_ b: ABSBook) -> Double {
    b.media.duration ?? 0
  }
}
