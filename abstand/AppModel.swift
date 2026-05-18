import Combine
import Foundation
import Network
import SwiftUI
import UIKit

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
  /// Pro Home-`category`: `list` oder `compact` (Cover-Streifen).
  static let startShelfBookLayouts = "abstand_start_shelf_book_layouts"
  static let catalogSortField = "abstand_catalog_sort_field"
  static let catalogSortDescending = "abstand_catalog_sort_descending"
  /// Sortierung nur Podcast-Bibliothek (Shows-Leiste + Fallback `libraryItems` für Folgen).
  static let podcastCatalogSortField = "abstand_podcast_catalog_sort_field"
  static let podcastCatalogSortDescending = "abstand_podcast_catalog_sort_descending"
  /// Früher: kombinierter `CatalogItemsSort`-RawValue (Migration einmalig).
  static let legacyCatalogItemsSort = "abstand_catalog_items_sort"
  static let smartDlAutoWifi = "abstand_smart_dl_auto_wifi"
  static let smartDlRemoveWhenFinished = "abstand_smart_dl_remove_when_finished"
  /// Nur Home mit „Heruntergeladen“; andere Tabs ausgeblendet.
  static let offlineHomeMode = "abstand_offline_home_mode"
  static let browseAuthorsSortField = "abstand_browse_authors_sort_field"
  static let browseAuthorsSortDescending = "abstand_browse_authors_sort_desc"
  static let browseNarratorsSortField = "abstand_browse_narrators_sort_field"
  static let browseNarratorsSortDescending = "abstand_browse_narrators_sort_desc"
  static let browseSeriesSortField = "abstand_browse_series_sort_field"
  static let browseSeriesSortDescending = "abstand_browse_series_sort_desc"
  static let browseCollectionsSortField = "abstand_browse_collections_sort_field"
  static let browseCollectionsSortDescending = "abstand_browse_collections_sort_desc"
  /// Tab „eBooks“ in der Tab-Leiste (neben Audio).
  static let ebooksTabEnabled = "abstand_ebooks_tab_enabled"
}

/// Sortierfeld für `GET /api/libraries/:id/items` (`sort`) bei **Bücher**-Bibliotheken.
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

/// Sortierung Podcast-Shows (`GET …/libraries/:id/items`, `mediaType=podcast`).
/// Server: `libraryItemsPodcastFilters.getOrder` — nicht dieselben Felder wie bei Büchern.
enum PodcastCatalogSortField: String, CaseIterable, Identifiable, Hashable {
  case title
  case author
  case numEpisodes
  case addedAt
  case size
  case birthtimeMs
  case mtimeMs
  case random

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .title: return "Title"
    case .author: return "Author"
    case .numEpisodes: return "Number of episodes"
    case .addedAt: return "Date added"
    case .size: return "Total size"
    case .birthtimeMs: return "File created"
    case .mtimeMs: return "File modified"
    case .random: return "Random"
    }
  }

  var apiSortParameter: String {
    switch self {
    case .title: return "media.metadata.title"
    case .author: return "media.metadata.author"
    case .numEpisodes: return "media.numTracks"
    case .addedAt: return "addedAt"
    case .size: return "size"
    case .birthtimeMs: return "birthtimeMs"
    case .mtimeMs: return "mtimeMs"
    case .random: return "random"
    }
  }
}

/// Unterbereiche im Audiobooks-Tab (horizontale Leiste wie Podcast-„Shows“).
enum BooksBrowseSection: String, CaseIterable, Identifiable, Hashable {
  case books = "Books"
  case series = "Series"
  case author = "Author"
  case narrators = "Narrators"
  case collections = "Collections"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .books: return "books.vertical"
    case .series: return "rectangle.stack"
    case .author: return "person.text.rectangle"
    case .narrators: return "waveform"
    case .collections: return "folder"
    }
  }
}

/// Format-Filter im Tab „eBooks“ (horizontale Leiste): All · eBooks (EPUB) · PDF.
enum EbooksBrowseFormatSection: String, CaseIterable, Identifiable, Hashable {
  case all = "All"
  case ebooks = "eBooks"
  case pdf = "PDF"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .all: return "books.vertical"
    case .ebooks: return "book.closed.fill"
    case .pdf: return "doc.fill"
    }
  }
}

/// Navigation zu Autor-, Serien- oder Sprecher-Detail (eigene Liste, nicht Hauptkatalog filtern).
struct BooksEntityDetailNav: Hashable, Identifiable {
  enum Kind: String, Hashable {
    case author
    case series
    case narrator
  }

  let kind: Kind
  let entityId: String
  let title: String
  let numBooks: Int?

  var id: String { "\(kind.rawValue):\(entityId)" }

  var libraryFilter: String {
    let b64 = Data(entityId.utf8).base64EncodedString()
    switch kind {
    case .author: return "authors.\(b64)"
    case .series: return "series.\(b64)"
    case .narrator: return "narrators.\(b64)"
    }
  }

  var filterSummaryPrefix: String {
    switch kind {
    case .author: return "Author"
    case .series: return "Series"
    case .narrator: return "Narrator"
    }
  }
}

/// Sortierung Autorenliste (`GET …/authors`, Query `sort`).
enum BooksBrowseAuthorsSortField: String, CaseIterable, Identifiable, Hashable {
  case name
  case lastFirst
  case numBooks
  case addedAt
  case updatedAt

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .name: return "Name (first name first)"
    case .lastFirst: return "Name (last name first)"
    case .numBooks: return "Number of books"
    case .addedAt: return "Date added"
    case .updatedAt: return "Date updated"
    }
  }

  var apiSortParameter: String { rawValue }
}

/// Sortierung Sprecherliste (lokal, Server liefert unsortierte Namensliste).
enum BooksBrowseNarratorsSortField: String, CaseIterable, Identifiable, Hashable {
  case name
  case numBooks

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .name: return "Name"
    case .numBooks: return "Number of books"
    }
  }
}

/// Sortierung Serienliste (`GET …/series`, Query `sort`).
enum BooksBrowseSeriesSortField: String, CaseIterable, Identifiable, Hashable {
  case name
  case numBooks
  case totalDuration
  case addedAt
  case lastBookAdded
  case lastBookUpdated
  case random

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .name: return "Series name"
    case .numBooks: return "Number of books"
    case .totalDuration: return "Total duration"
    case .addedAt: return "Date added"
    case .lastBookAdded: return "Last book added"
    case .lastBookUpdated: return "Last book updated"
    case .random: return "Random"
    }
  }

  var apiSortParameter: String { rawValue }
}

/// Sortierung Sammlungen (lokal nach vollständigem Abruf `limit=0`).
enum BooksBrowseCollectionsSortField: String, CaseIterable, Identifiable, Hashable {
  case name
  case createdAt
  case lastUpdate
  case bookCount

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .name: return "Name"
    case .createdAt: return "Date created"
    case .lastUpdate: return "Last update"
    case .bookCount: return "Number of books"
    }
  }
}

@MainActor
final class AppModel: ObservableObject {
  @Published var serverURL: String = UserDefaults.standard.string(forKey: Keys.server) ?? ""

  private static let initialCatalogSort: (field: CatalogSortField, descending: Bool) = loadCatalogSortState()
  private static let initialPodcastCatalogSort: (field: PodcastCatalogSortField, descending: Bool) =
    loadPodcastCatalogSortState()

  private static let initialBrowseAuthorsSort: (field: BooksBrowseAuthorsSortField, descending: Bool) =
    loadBrowseAuthorsSortState()
  private static let initialBrowseNarratorsSort: (field: BooksBrowseNarratorsSortField, descending: Bool) =
    loadBrowseNarratorsSortState()
  private static let initialBrowseSeriesSort: (field: BooksBrowseSeriesSortField, descending: Bool) =
    loadBrowseSeriesSortState()
  private static let initialBrowseCollectionsSort: (field: BooksBrowseCollectionsSortField, descending: Bool) =
    loadBrowseCollectionsSortState()

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

  @Published var podcastCatalogSortField: PodcastCatalogSortField = AppModel.initialPodcastCatalogSort.field {
    didSet {
      UserDefaults.standard.set(podcastCatalogSortField.rawValue, forKey: Keys.podcastCatalogSortField)
    }
  }
  @Published var podcastCatalogSortDescending: Bool = AppModel.initialPodcastCatalogSort.descending {
    didSet {
      UserDefaults.standard.set(podcastCatalogSortDescending, forKey: Keys.podcastCatalogSortDescending)
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
  @Published var podcastDirectorySearchHits: [ABSPodcastDirectorySearchHit] = []
  @Published private(set) var podcastDirectorySearchLoading = false
  @Published private(set) var podcastSubscribeInProgressDirectoryHitId: String?
  /// `nil` = „New“-Ansicht (recent-Feed); gesetzt = nur diese Sendung (`podcastFilteredEpisodes`).
  @Published var podcastSelectedShowId: String?
  @Published var podcastFilteredEpisodes: [ABSPodcastEpisodeListItem] = []
  @Published private(set) var isLoadingPodcastShowEpisodes = false
  @Published private(set) var podcastRssFeedLoadInProgressShowIds: Set<String> = []
  /// Aus `POST /api/podcasts/feed` für die aktuell gewählte Sendung (`podcastRssFeedPreviewForShowId`).
  @Published private(set) var podcastRssFeedPreviewEpisodes: [ABSPodcastRssFeedEpisodeDraft] = []
  @Published private(set) var podcastRssFeedPreviewForShowId: String?
  @Published private(set) var podcastRssEpisodeDownloadInProgressDraftIds: Set<UUID> = []
  /// Nach erfolgreichem `download-episodes`: Download-Button ausblenden, Karte bleibt in der RSS-Liste.
  @Published private(set) var podcastRssDraftDownloadCompletedIds: Set<UUID> = []
  @Published var podcastAutoDownloadEnabled = false
  @Published var podcastAutoDownloadInterval = PodcastAutoDownloadInterval.default
  @Published private(set) var podcastAutoDownloadSettingsLoading = false
  @Published private(set) var podcastAutoDownloadSettingsSaving = false
  @Published private(set) var podcastAutoDownloadSettingsShowId: String?
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
  @Published var startShelfBookLayoutByCategory: [String: String] =
    UserDefaults.standard.dictionary(forKey: Keys.startShelfBookLayouts) as? [String: String] ?? [:]
  @Published var progressByItemId: [String: ABSUserMediaProgress] = [:]
  @Published private(set) var bookmarks: [ABSAudioBookmark] = []
  @Published var ebookReaderSession: EbookReaderPresentation?
  @Published var isPreparingEbook = false
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
  @Published var booksBrowseSection: BooksBrowseSection = .books
  @Published private(set) var browseAuthors: [ABSLibraryAuthorListItem] = []
  @Published private(set) var browseNarrators: [ABSLibraryNarratorListItem] = []
  @Published private(set) var browseSeries: [ABSLibrarySeriesListItem] = []
  @Published private(set) var browseCollections: [ABSLibraryCollectionListItem] = []
  @Published private(set) var browseCollectionBooksById: [String: [ABSBook]] = [:]
  @Published private(set) var browseAuthorsLoading = false
  @Published private(set) var browseNarratorsLoading = false
  @Published private(set) var browseSeriesLoading = false
  @Published private(set) var browseCollectionsLoading = false
  @Published private(set) var browseSeriesTotal = 0
  @Published private(set) var browseAuthorsTotal = 0
  @Published private(set) var browseCollectionsTotal = 0
  @Published private(set) var browseNarratorCoverItemIdByNarratorName: [String: String] = [:]
  @Published var ebooksBrowseFormatSection: EbooksBrowseFormatSection = .all
  @Published private(set) var browseEbooksBooks: [ABSBook] = []
  @Published private(set) var browseEbooksLoading = false
  @Published private(set) var browseEbooksTotal = 0
  private var browseEbooksPage = 0

  @Published var booksEntityDetailNav: BooksEntityDetailNav?
  @Published private(set) var entityDetailBooks: [ABSBook] = []
  @Published private(set) var entityDetailLoading = false
  @Published private(set) var entityDetailTotal = 0
  @Published private(set) var entityDetailDescription: String?
  @Published private(set) var entityDetailMetaReady = false
  @Published private(set) var entityDetailAuthorSeriesSections: [EntityDetailAuthorSeriesSection] = []
  @Published private(set) var entityDetailAuthorStandaloneBooks: [ABSBook] = []
  private var entityDetailNavKey: String?
  private var entityDetailPage = 0
  private var entityDetailUsesLibraryItemFilter = false

  @Published var browseAuthorsSortField: BooksBrowseAuthorsSortField = AppModel.initialBrowseAuthorsSort.field {
    didSet { UserDefaults.standard.set(browseAuthorsSortField.rawValue, forKey: Keys.browseAuthorsSortField) }
  }
  @Published var browseAuthorsSortDescending: Bool = AppModel.initialBrowseAuthorsSort.descending {
    didSet { UserDefaults.standard.set(browseAuthorsSortDescending, forKey: Keys.browseAuthorsSortDescending) }
  }
  @Published var browseNarratorsSortField: BooksBrowseNarratorsSortField = AppModel.initialBrowseNarratorsSort.field {
    didSet { UserDefaults.standard.set(browseNarratorsSortField.rawValue, forKey: Keys.browseNarratorsSortField) }
  }
  @Published var browseNarratorsSortDescending: Bool = AppModel.initialBrowseNarratorsSort.descending {
    didSet { UserDefaults.standard.set(browseNarratorsSortDescending, forKey: Keys.browseNarratorsSortDescending) }
  }
  @Published var browseSeriesSortField: BooksBrowseSeriesSortField = AppModel.initialBrowseSeriesSort.field {
    didSet { UserDefaults.standard.set(browseSeriesSortField.rawValue, forKey: Keys.browseSeriesSortField) }
  }
  @Published var browseSeriesSortDescending: Bool = AppModel.initialBrowseSeriesSort.descending {
    didSet { UserDefaults.standard.set(browseSeriesSortDescending, forKey: Keys.browseSeriesSortDescending) }
  }
  @Published var browseCollectionsSortField: BooksBrowseCollectionsSortField =
    AppModel.initialBrowseCollectionsSort.field
  {
    didSet {
      UserDefaults.standard.set(browseCollectionsSortField.rawValue, forKey: Keys.browseCollectionsSortField)
    }
  }
  @Published var browseCollectionsSortDescending: Bool = AppModel.initialBrowseCollectionsSort.descending {
    didSet {
      UserDefaults.standard.set(browseCollectionsSortDescending, forKey: Keys.browseCollectionsSortDescending)
    }
  }

  @Published var mainTab: MainTab = .start
  /// Wird von `MainRootView` beobachtet: bei jedem Inkrement öffnet sich das Now-Playing-Sheet, ohne den Tab zu wechseln.
  @Published private(set) var nowPlayingSheetPresentationCounter: UInt = 0
  @Published var isLoadingLibrary = false
  @Published var isLoadingPodcasts = false
  @Published var errorMessage: String?
  @Published private(set) var listeningStats: ABSListeningStatsResponse?
  @Published private(set) var listeningStatsFetchedAt: Date?
  @Published private(set) var listeningStatsLoading = false

  /// Erhöhen nach `clearCoverImageCache()`, damit `CoverImageView` neu lädt.
  @Published private(set) var coverImageCacheRevision = 0
  @Published var downloadedItemIds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Keys.downloads) ?? [])
  /// Aus `download.json` gebaute Stubs für Home-Regal „Heruntergeladen“ und Offline-Katalog.
  @Published private(set) var downloadedShelfBooks: [ABSBook] = []
  @Published private(set) var isNetworkReachable = true
  /// `true`, wenn die aktive Route Wi‑Fi (oder Ethernet) nutzt und erreichbar ist — für Smart-Download nur im WLAN.
  @Published private(set) var networkUsesUnmeteredLAN: Bool = false
  /// Nach 3 Minuten Wiedergabe im WLAN: aktuellen Titel (Hörbuch oder Podcast) automatisch herunterladen.
  @Published var smartDownloadOnWiFi: Bool = AppModel.initialSmartDownloadOnWiFi() {
    didSet { UserDefaults.standard.set(smartDownloadOnWiFi, forKey: Keys.smartDlAutoWifi) }
  }
  /// Lokale Downloads entfernen, sobald Hörbuch oder Podcast-Folge als fertig markiert ist.
  @Published var smartDownloadRemoveWhenFinished: Bool = AppModel.initialSmartDownloadRemoveWhenFinished() {
    didSet {
      UserDefaults.standard.set(smartDownloadRemoveWhenFinished, forKey: Keys.smartDlRemoveWhenFinished)
    }
  }
  /// Separater Tab „eBooks“ für die gewählte Bücher-Bibliothek.
  @Published var ebooksTabEnabled: Bool = AppModel.initialEbooksTabEnabled() {
    didSet {
      UserDefaults.standard.set(ebooksTabEnabled, forKey: Keys.ebooksTabEnabled)
      guard oldValue != ebooksTabEnabled else { return }
      clampMainTabForEbooksTabIfNeeded()
      updateStartSettingsCategoryList(parsed: startShelves)
      Task { await loadStartDashboard() }
    }
  }
  /// Nur Home mit Regal „Heruntergeladen“ (persistiert). Fortschritt beim Deaktivieren an den Server senden.
  @Published var offlineHomeMode: Bool = AppModel.initialOfflineHomeMode() {
    didSet {
      UserDefaults.standard.set(offlineHomeMode, forKey: Keys.offlineHomeMode)
      guard !suppressOfflineModeSideEffects else { return }
      guard oldValue != offlineHomeMode else { return }
      if offlineHomeMode {
        offlineHomeModeAuto = false
        mainTab = .start
        Task { await loadStartDashboard() }
      } else {
        offlineHomeModeAuto = false
        Task {
          let ok = await syncOfflineProgressToServer()
          if !ok { pendingPostOfflineModeProgressSync = true }
          await loadStartDashboard()
        }
      }
    }
  }
  /// Nach fehlgeschlagenem Start-`bootstrap`: gleiche Oberfläche wie manueller Offline-Modus, ohne UserDefaults.
  @Published private(set) var offlineHomeModeAuto = false

  /// Home nur mit „Heruntergeladen“ (manuell oder automatisch nach Start ohne Server).
  var offlineHomeUIActive: Bool { offlineHomeMode || offlineHomeModeAuto }

  func clampMainTabForOfflineHomeIfNeeded() {
    if offlineHomeUIActive, mainTab != .start {
      mainTab = .start
    }
  }

  func clampMainTabForEbooksTabIfNeeded() {
    guard !ebooksTabEnabled, mainTab == .ebooks else { return }
    mainTab = selectedBooksLibrary != nil ? .audio : .start
  }

  private static func initialEbooksTabEnabled() -> Bool {
    let d = UserDefaults.standard
    if d.object(forKey: Keys.ebooksTabEnabled) == nil { return true }
    return d.bool(forKey: Keys.ebooksTabEnabled)
  }

  /// Mini-Player: Session aus Server-Fortschritt / `item`-Laden; UI kann sofort Skelett zeigen.
  @Published private(set) var isRestoringLaunchPlayback = false

  private(set) var token: String = UserDefaults.standard.string(forKey: Keys.token) ?? ""

  let player = PlaybackController()
  let downloads = DownloadManager()
  /// Nur Player-Chrome — entkoppelt `tabViewBottomAccessory` von übrigen `@Published`-Feldern in `AppModel`.
  let floatingChrome = FloatingPlayerChromeController()

  /// Zusatz für `ScrollView`-Inhalt, damit `tabViewBottomAccessory` die letzten Zeilen nicht verdeckt.
  var nowPlayingAccessoryScrollBottomInset: CGFloat {
    let p = player
    if p.activeBook != nil { return 56 }
    if isRestoringLaunchPlayback { return 56 }
    if p.showMiniPlayerPlaceholder && p.activeBook == nil { return 56 }
    return 0
  }

  /// Stabiler Zustand für `tabViewBottomAccessory` — nur bei echten Player-/UI-Wechseln, nicht bei `globalPosition`-Ticks.
  func floatingPlayerAccessoryState(nowPlayingSheetPresented: Bool) -> FloatingPlayerAccessoryState {
    let p = player
    let showChrome =
      p.activeBook != nil || isRestoringLaunchPlayback
      || (p.showMiniPlayerPlaceholder && p.activeBook == nil)
    return FloatingPlayerAccessoryState(
      isVisible: showChrome && !nowPlayingSheetPresented,
      bar: FloatingNowPlayingBarSnapshot.make(model: self)
    )
  }

  private var cancellables = Set<AnyCancellable>()

  private var client: ABSAPIClient?
  private var libraryPage = 0
  private var libraryTotal = 0
  private var browseAuthorsNextPage = 0
  private var browseSeriesNextPage = 0
  private var browseNarratorsFetched: [ABSLibraryNarratorListItem] = []
  private var browseCollectionsFetched: [ABSLibraryCollectionListItem] = []
  private var podcastLibraryPage = 0
  private var podcastLibraryTotal = 0
  /// Solange `true`, lädt „Mehr“ über `/recent-episodes`. Nach Fallback über Podcast-Shows ist Pagination aus.
  private var podcastEpisodesPagingFromRecentAPI = true
  /// Verhindert, dass ein verzögertes `item(id:expanded:)` eine neue Sendungswahl überschreibt.
  private var podcastShowEpisodesLoadSerial = 0
  /// Entkoppelt Sort-Menü von schnellen `@Published`-Updates während des Reloads.
  private var podcastCatalogSortReloadTask: Task<Void, Never>?
  private var booksToolbarSortReloadTask: Task<Void, Never>?
  /// Fehlende EPUB/PDF-Metadaten für den eBooks-Tab (expandiertes Item), ohne jedes Buch zu öffnen.
  private var enrichBrowseEbookFormatsTask: Task<Void, Never>?
  private var searchTask: Task<Void, Never>?
  private var podcastSearchTask: Task<Void, Never>?
  private var podcastDirectorySearchTask: Task<Void, Never>?
  /// Erhöht bei jeder neuen Podcast-Verzeichnissuche; verhindert, dass abgebrochene Requests Treffer löschen oder Fehler setzen.
  private var podcastDirectorySearchGeneration: Int = 0
  private let pathMonitor = NWPathMonitor()
  private let pathMonitorQueue = DispatchQueue(label: "de.letzgo.abstand.network")

  private static let smartDownloadWiFiListenThresholdSeconds: Double = 180
  private var smartDlPlaybackKey: String?
  private var smartDlAccumulatedSeconds: Double = 0
  private var smartDlLastTickAt: Date?
  private var smartDlFiredForCurrentKey = false
  private var downloadBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  /// `logout` / init: kein Tab-Wechsel oder Sync bei programmatischer Änderung von `offlineHomeMode`.
  private var suppressOfflineModeSideEffects = false
  /// Nach Abschalten des Offline-Modus ohne Netz: erneuter Sync, sobald `NWPathMonitor` wieder „satisfied“ meldet.
  private var pendingPostOfflineModeProgressSync = false

  enum MainTab: String, CaseIterable, Hashable {
    case start = "Home"
    case audio = "Audio"
    case ebooks = "eBooks"
    case podcasts = "Podcasts"
    case stats = "Stats"
    case search = "Search"
    case settings = "Settings"
  }

  init() {
    Self.migrateLibraryKeysIfNeeded()
    // Nicht jedes `globalPosition`-Tick (~0,35 s) an `AppModel` durchreichen — sonst baut SwiftUI
    // ständig die ganze `TabView` inkl. `tabViewBottomAccessory` neu um; Touches gehen dabei leicht verloren.
    Publishers.MergeMany(
      player.$activeBook.map { _ in () }.eraseToAnyPublisher(),
      player.$activePlaybackEpisodeId.map { _ in () }.eraseToAnyPublisher(),
      player.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
      player.$totalDuration.map { _ in () }.eraseToAnyPublisher(),
      player.$isBuffering.map { _ in () }.eraseToAnyPublisher(),
      player.$sleepEndDate.map { _ in () }.eraseToAnyPublisher(),
      player.$showMiniPlayerPlaceholder.map { _ in () }.eraseToAnyPublisher(),
      player.$miniPlayerBarFillColor.map { _ in () }.eraseToAnyPublisher(),
      player.$chapterCount.map { _ in () }.eraseToAnyPublisher(),
      player.$currentChapterOrdinal.map { _ in () }.eraseToAnyPublisher(),
      player.$currentChapterTitle.map { _ in () }.eraseToAnyPublisher(),
      player.$playbackRate.map { _ in () }.eraseToAnyPublisher()
    )
    .receive(on: RunLoop.main)
    .sink { [weak self] in
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
      let onWiFiOrEthernet =
        path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
      Task { @MainActor [weak self] in
        guard let model = self else { return }
        let wasReachable = model.isNetworkReachable
        model.isNetworkReachable = reachable
        model.networkUsesUnmeteredLAN = reachable && onWiFiOrEthernet
        model.refreshDownloadedShelfFromManifests()
        if reachable, !wasReachable, model.pendingPostOfflineModeProgressSync {
          model.pendingPostOfflineModeProgressSync = false
          Task {
            let ok = await model.syncOfflineProgressToServer()
            if ok { await model.loadStartDashboard() }
            else { model.pendingPostOfflineModeProgressSync = true }
          }
        }
      }
    }
    pathMonitor.start(queue: pathMonitorQueue)
    let initialPath = pathMonitor.currentPath
    isNetworkReachable = initialPath.status == .satisfied
    networkUsesUnmeteredLAN =
      initialPath.status == .satisfied
      && (initialPath.usesInterfaceType(.wifi) || initialPath.usesInterfaceType(.wiredEthernet))
    player.onPlaybackTick = { [weak self] in
      self?.handleSmartDownloadPlaybackTick()
    }
    player.onAudiobookPlaybackCompleted = { [weak self] in
      Task { @MainActor [weak self] in
        await self?.handleAudiobookPlaybackCompleted()
      }
    }
    floatingChrome.bind(model: self)
    refreshDownloadedShelfFromManifests()
    restoreAllFromDiskOnLaunch()
    if offlineHomeUIActive {
      mainTab = .start
    }
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

  private func currentSmartDownloadPlaybackKey() -> String? {
    guard let bookId = player.activeBook?.id else { return nil }
    let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if ep.isEmpty { return "audiobook:\(bookId)" }
    return "podcast:\(bookId):\(ep)"
  }

  /// Folge für `startDownloadPodcastEpisode` aus aktueller Wiedergabe; sonst synthetische Zeile.
  private func podcastEpisodeForSmartDownloadFromActivePlayback() -> ABSPodcastEpisodeListItem? {
    guard let book = player.activeBook else { return nil }
    let epRaw = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !epRaw.isEmpty else { return nil }
    let lookup = "\(book.id)-\(epRaw)"
    if let e = podcastEpisodes.first(where: { $0.progressLookupKey == lookup }) { return e }
    if let e = podcastFilteredEpisodes.first(where: { $0.progressLookupKey == lookup }) { return e }
    let showTitle =
      podcastShows.first(where: { $0.id == book.id })?.displayTitle.trimmingCharacters(
        in: .whitespacesAndNewlines) ?? "Podcast"
    let libId = selectedPodcastLibrary?.id
    let epTitle = book.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let authors = book.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
    return ABSPodcastEpisodeListItem(
      libraryItemId: book.id,
      libraryId: libId,
      episodeId: epRaw,
      episodeTitle: epTitle.isEmpty ? "Episode" : epTitle,
      showTitle: showTitle,
      authorLine: authors.isEmpty ? showTitle : authors,
      duration: book.media.duration ?? 0,
      publishedAt: nil
    )
  }

  private func offlineStorageIdForActivePlayback() -> String? {
    guard let book = player.activeBook else { return nil }
    let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if ep.isEmpty { return book.id }
    guard let episode = podcastEpisodeForSmartDownloadFromActivePlayback() else {
      return "\(book.id)-\(ep)".replacingOccurrences(of: "/", with: "_")
    }
    return podcastEpisodeOfflineStorageId(episode)
  }

  /// Nach ≥3 Minuten **Wiedergabe** im WLAN: einmaliger Auto-Download des aktuellen Titels.
  private func handleSmartDownloadPlaybackTick() {
    guard client != nil else {
      smartDlPlaybackKey = nil
      smartDlLastTickAt = nil
      return
    }

    guard let key = currentSmartDownloadPlaybackKey() else {
      smartDlPlaybackKey = nil
      smartDlLastTickAt = nil
      return
    }

    if smartDlPlaybackKey != key {
      smartDlPlaybackKey = key
      smartDlAccumulatedSeconds = 0
      smartDlLastTickAt = nil
      smartDlFiredForCurrentKey = false
    }

    guard player.isPlaying, isNetworkReachable, networkUsesUnmeteredLAN,
      !player.isPlaybackFromOfflineDownload
    else {
      smartDlLastTickAt = nil
      return
    }

    guard smartDownloadOnWiFi else { return }

    let now = Date()
    let dt: Double
    if let t = smartDlLastTickAt {
      dt = now.timeIntervalSince(t)
    } else {
      dt = 0
    }
    smartDlLastTickAt = now

    smartDlAccumulatedSeconds += max(0, dt)
    guard smartDlAccumulatedSeconds >= Self.smartDownloadWiFiListenThresholdSeconds else { return }
    guard !smartDlFiredForCurrentKey else { return }

    guard let storageId = offlineStorageIdForActivePlayback() else { return }
    if downloadedItemIds.contains(storageId) {
      smartDlFiredForCurrentKey = true
      return
    }
    if downloads.activeItemId == storageId {
      smartDlFiredForCurrentKey = true
      return
    }

    smartDlFiredForCurrentKey = true
    let isPodcast = !(player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
      .isEmpty
    if isPodcast {
      guard let episode = podcastEpisodeForSmartDownloadFromActivePlayback() else { return }
      startDownloadPodcastEpisode(episode)
    } else if let book = player.activeBook {
      startDownload(book: book)
    }
  }

  var isLoggedIn: Bool {
    ABSAPIClient.normalizeServerURL(serverURL) != nil && !token.isEmpty
  }

  func booksForDisplay() -> [ABSBook] {
    switch mainTab {
    case .audio:
      if !isNetworkReachable, !books.isEmpty { return books }
      if !isNetworkReachable { return downloadedShelfBooks }
      return books
    case .ebooks:
      return browseEbooksBooks
    case .podcasts:
      return []
    case .start, .settings, .search, .stats:
      return []
    }
  }

  /// Bücher mit angehängter E-Book-Datei (Tab „eBooks“; servergefiltert, optional nach Format).
  func booksWithEbookForDisplay() -> [ABSBook] {
    Self.filterEbooks(browseEbooksBooks, format: ebooksBrowseFormatSection, account: cacheAccountURL())
  }

  static func filterEbooks(
    _ books: [ABSBook], format: EbooksBrowseFormatSection, account: URL?
  ) -> [ABSBook] {
    switch format {
    case .all:
      return books
    case .ebooks:
      return books.filter { $0.hasAttachedEbookFormat(.epub, account: account) }
    case .pdf:
      return books.filter { $0.hasAttachedEbookFormat(.pdf, account: account) }
    }
  }

  func selectEbooksBrowseFormatSection(_ section: EbooksBrowseFormatSection) {
    ebooksBrowseFormatSection = section
    scheduleEnrichBrowseEbookFormats()
    if section != .all, booksWithEbookForDisplay().isEmpty, !browseEbooksBooks.isEmpty {
      Task { await loadBrowseEbooks(force: true) }
    }
  }

  /// ABS erwartet `gruppe.<base64(wert)>` (vgl. Tags/Autoren in dieser App).
  private static func absLibraryFilter(group: String, value: String) -> String {
    let b64 = Data(value.utf8).base64EncodedString()
    return "\(group).\(b64)"
  }

  private static let ebooksBrowsePrimaryFilter = absLibraryFilter(group: "ebooks", value: "ebook")
  private static let ebooksBrowseSupplementaryFilter = absLibraryFilter(
    group: "ebooks", value: "supplementary")

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

  private static var smartDownloadDefaultsMigrationDone = false

  /// V4 getrennte Smart-Download-Keys → gemeinsame Keys (einmalig).
  private static func migrateSmartDownloadKeysIfNeeded() {
    if smartDownloadDefaultsMigrationDone { return }
    smartDownloadDefaultsMigrationDone = true
    let d = UserDefaults.standard
    guard d.object(forKey: Keys.smartDlAutoWifi) == nil else { return }
    let legacyAuto =
      d.bool(forKey: "abstand_smart_dl_audiobooks_wifi") || d.bool(forKey: "abstand_smart_dl_podcasts_wifi")
    let legacyRemove =
      d.bool(forKey: "abstand_smart_dl_audiobooks_remove_finished")
      || d.bool(forKey: "abstand_smart_dl_podcasts_remove_finished")
    d.set(legacyAuto, forKey: Keys.smartDlAutoWifi)
    d.set(legacyRemove, forKey: Keys.smartDlRemoveWhenFinished)
  }

  private static func initialSmartDownloadOnWiFi() -> Bool {
    migrateSmartDownloadKeysIfNeeded()
    return UserDefaults.standard.bool(forKey: Keys.smartDlAutoWifi)
  }

  private static func initialSmartDownloadRemoveWhenFinished() -> Bool {
    migrateSmartDownloadKeysIfNeeded()
    return UserDefaults.standard.bool(forKey: Keys.smartDlRemoveWhenFinished)
  }

  private static func initialOfflineHomeMode() -> Bool {
    UserDefaults.standard.bool(forKey: Keys.offlineHomeMode)
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

  /// Podcast-Sort aus UserDefaults; alte Buch-`CatalogSortField`-Werte werden auf gültige Podcast-API-Keys gemappt.
  private static func loadPodcastCatalogSortState() -> (field: PodcastCatalogSortField, descending: Bool) {
    if UserDefaults.standard.object(forKey: Keys.podcastCatalogSortField) != nil {
      let raw = UserDefaults.standard.string(forKey: Keys.podcastCatalogSortField) ?? ""
      let field = migratePodcastCatalogSortField(raw: raw)
      let descending = UserDefaults.standard.bool(forKey: Keys.podcastCatalogSortDescending)
      return (field: field, descending: descending)
    }
    let bookRaw = UserDefaults.standard.string(forKey: Keys.catalogSortField) ?? ""
    let field = migratePodcastCatalogSortFromBookCatalog(CatalogSortField(rawValue: bookRaw) ?? .title)
    let descending = UserDefaults.standard.bool(forKey: Keys.catalogSortDescending)
    UserDefaults.standard.set(field.rawValue, forKey: Keys.podcastCatalogSortField)
    UserDefaults.standard.set(descending, forKey: Keys.podcastCatalogSortDescending)
    return (field: field, descending: descending)
  }

  private static func migratePodcastCatalogSortField(raw: String) -> PodcastCatalogSortField {
    if let field = PodcastCatalogSortField(rawValue: raw) { return field }
    if let book = CatalogSortField(rawValue: raw) {
      return migratePodcastCatalogSortFromBookCatalog(book)
    }
    switch raw {
    case "media.metadata.title": return .title
    case "media.metadata.author", "media.metadata.authorName", "media.metadata.authorNameLF": return .author
    case "media.numTracks", "media.duration": return .numEpisodes
    case "addedAt": return .addedAt
    case "size": return .size
    case "birthtimeMs": return .birthtimeMs
    case "mtimeMs": return .mtimeMs
    case "random": return .random
    default: return .title
    }
  }

  /// Entspricht `checkUpdateLibrarySortFilter` in der Audiobookshelf-Web-UI.
  private static func migratePodcastCatalogSortFromBookCatalog(_ book: CatalogSortField)
    -> PodcastCatalogSortField
  {
    switch book {
    case .authorName, .authorNameLF: return .author
    case .addedAt: return .addedAt
    case .size: return .size
    case .birthtimeMs: return .birthtimeMs
    case .mtimeMs: return .mtimeMs
    case .duration: return .numEpisodes
    case .random: return .random
    case .title, .publishedYear, .progress, .progressCreatedAt, .progressFinishedAt: return .title
    }
  }

  private static func loadBrowseAuthorsSortState() -> (field: BooksBrowseAuthorsSortField, descending: Bool) {
    let raw = UserDefaults.standard.string(forKey: Keys.browseAuthorsSortField) ?? ""
    let field = BooksBrowseAuthorsSortField(rawValue: raw) ?? .name
    let descending = UserDefaults.standard.bool(forKey: Keys.browseAuthorsSortDescending)
    return (field, descending)
  }

  private static func loadBrowseNarratorsSortState() -> (field: BooksBrowseNarratorsSortField, descending: Bool) {
    let raw = UserDefaults.standard.string(forKey: Keys.browseNarratorsSortField) ?? ""
    let field = BooksBrowseNarratorsSortField(rawValue: raw) ?? .name
    let descending = UserDefaults.standard.bool(forKey: Keys.browseNarratorsSortDescending)
    return (field, descending)
  }

  private static func loadBrowseSeriesSortState() -> (field: BooksBrowseSeriesSortField, descending: Bool) {
    let raw = UserDefaults.standard.string(forKey: Keys.browseSeriesSortField) ?? ""
    let field = BooksBrowseSeriesSortField(rawValue: raw) ?? .name
    let descending = UserDefaults.standard.bool(forKey: Keys.browseSeriesSortDescending)
    return (field, descending)
  }

  private static func loadBrowseCollectionsSortState() -> (
    field: BooksBrowseCollectionsSortField, descending: Bool
  ) {
    let raw = UserDefaults.standard.string(forKey: Keys.browseCollectionsSortField) ?? ""
    let field = BooksBrowseCollectionsSortField(rawValue: raw) ?? .name
    let descending = UserDefaults.standard.bool(forKey: Keys.browseCollectionsSortDescending)
    return (field, descending)
  }

  /// Aktualisiert Fortschritt und Lesezeichen vom Server (`POST /api/authorize`).
  func refreshProgressFromServer() async {
    guard let c = client else { return }
    do {
      let auth = try await c.authorize()
      applyAuthorizeUser(auth.user)
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
    defer {
      applyContinueListeningFinishedFilter()
      injectEbookContinueReadingShelfIfNeeded()
    }
    if offlineHomeUIActive {
      refreshDownloadedShelfFromManifests()
      return
    }
    guard let c = client else {
      refreshDownloadedShelfFromManifests()
      return
    }
    if !isNetworkReachable {
      applyOfflineHomeShelvesIfNeeded()
      if ebooksTabEnabled, selectedBooksLibrary != nil {
        _ = restoreBrowseEbooksFromDisk()
      }
      refreshDownloadedShelfFromManifests()
      return
    }
    do {
      await refreshProgressFromServer()
      if ebooksTabEnabled, selectedBooksLibrary != nil {
        await loadBrowseEbooks(force: false)
      }
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

  func supportsStartShelfBookLayoutSetting(_ category: String) -> Bool {
    ABSStartShelfLocalization.supportsBookLayoutSetting(category: category)
  }

  func startShelfBookLayout(for category: String) -> StartShelfBookLayout {
    if let raw = startShelfBookLayoutByCategory[category],
      let layout = StartShelfBookLayout(rawValue: raw)
    {
      return layout
    }
    return StartShelfBookLayout.defaultForCategory(category)
  }

  func setStartShelfBookLayout(_ category: String, layout: StartShelfBookLayout) {
    var next = startShelfBookLayoutByCategory
    next[category] = layout.rawValue
    startShelfBookLayoutByCategory = next
    UserDefaults.standard.set(next, forKey: Keys.startShelfBookLayouts)
  }

  /// Schalter-Reihenfolge inkl. optionalem eBook-„Continue reading“ direkt nach „Continue listening“.
  private func effectiveStartSettingsCategoryOrder() -> [String] {
    var order = ABSStartShelfLocalization.settingsCategoryOrder
    guard ebooksTabEnabled else { return order }
    guard !order.contains("continueEbooks") else { return order }
    if let idx = order.firstIndex(of: "recentlyListened") {
      order.insert("continueEbooks", at: idx + 1)
    } else {
      order.insert("continueEbooks", at: 0)
    }
    return order
  }

  private func updateStartSettingsCategoryList(parsed: [ABSStartShelfSection]) {
    var fromServer: [String: String] = [:]
    for s in parsed {
      fromServer[s.category] = s.displayTitle
    }
    startSettingsCategoryList = effectiveStartSettingsCategoryOrder().map { cat in
      let label =
        fromServer[cat]
        ?? ABSStartShelfLocalization.displayTitle(category: cat, serverLabel: "")
      return (category: cat, label: label)
    }
  }

  /// Home-Regal „Continue reading“ aus lokalem Readium-Fortschritt (nur bei aktivem eBook-Tab).
  func refreshEbookContinueReadingShelf() {
    injectEbookContinueReadingShelfIfNeeded()
  }

  private func injectEbookContinueReadingShelfIfNeeded() {
    var shelves = startShelves.filter { $0.category != "continueEbooks" }
    guard ebooksTabEnabled, isStartCategoryEnabled("continueEbooks") else {
      if shelves.count != startShelves.count {
        startShelves = shelves
        recomputeStartBooksUnion(from: shelves)
      }
      return
    }
    let books = buildEbookContinueReadingBooks()
    guard !books.isEmpty else {
      if shelves.count != startShelves.count {
        startShelves = shelves
        recomputeStartBooksUnion(from: shelves)
      }
      return
    }
    let section = ABSStartShelfSection(
      id: "continue-ebooks-local",
      category: "continueEbooks",
      displayTitle: ABSStartShelfLocalization.displayTitle(category: "continueEbooks", serverLabel: ""),
      books: books
    )
    if let idx = shelves.firstIndex(where: { isHomeContinueCategory($0.category) }) {
      shelves.insert(section, at: idx + 1)
    } else {
      shelves.insert(section, at: 0)
    }
    startShelves = shelves
    recomputeStartBooksUnion(from: shelves)
  }

  private func buildEbookContinueReadingBooks() -> [ABSBook] {
    if browseEbooksBooks.isEmpty, selectedBooksLibrary != nil {
      _ = restoreBrowseEbooksFromDisk()
    }
    var seen = Set<String>()
    var candidates: [ABSBook] = []
    func absorb(_ book: ABSBook) {
      guard book.isEbookContinueReadingCandidate, seen.insert(book.id).inserted else { return }
      candidates.append(book)
    }
    for ref in EbookLocalStore.inProgressReadingRefs() {
      if let book = bookForEbookContinue(libraryItemId: ref.libraryItemId) {
        absorb(book)
      }
    }
    for b in browseEbooksBooks + books + startBooks {
      absorb(b)
    }
    candidates.sort { ($0.ebookReadProgressFraction() ?? 0) > ($1.ebookReadProgressFraction() ?? 0) }
    return Array(candidates.prefix(14))
  }

  /// Buch zu gespeicherter Readium-Position (Katalog, eBooks-Cache, Download-Meta).
  private func bookForEbookContinue(libraryItemId: String) -> ABSBook? {
    if let b = browseEbooksBooks.first(where: { $0.id == libraryItemId }) { return b }
    if let b = books.first(where: { $0.id == libraryItemId }) { return b }
    if let b = startBooks.first(where: { $0.id == libraryItemId }) { return b }
    guard let account = cacheAccountURL(), let lib = selectedBooksLibrary else { return nil }
    let dec = ABSJSON.decoder()
    if let merged = LibraryDiskCache.loadMergedBrowseEbooks(
      account: account,
      libraryId: lib.id,
      sort: ebooksBrowseSortKey,
      descending: !ebooksBrowseSortAscending,
      decoder: dec
    ), let b = merged.books.first(where: { $0.id == libraryItemId }) {
      return b
    }
    let ascending = catalogSortField == .random ? true : !catalogSortDescending
    if let merged = LibraryDiskCache.loadMergedCatalog(
      account: account,
      libraryId: lib.id,
      filter: activeLibraryFilter,
      sortField: catalogSortField.apiSortParameter,
      ascending: ascending,
      decoder: dec
    ), let b = merged.books.first(where: { $0.id == libraryItemId }) {
      return b
    }
    for fmt in ABSEbookFormat.allCases {
      if let meta = EbookLocalStore.loadDownloadMeta(account: account, libraryItemId: libraryItemId, format: fmt) {
        let title = meta.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayTitle = title.isEmpty ? "eBook" : title
        let bookMeta = ABSBookMediaMetadata(offlineTitle: displayTitle, authorLine: "—")
        let media = ABSBookMedia(
          metadata: bookMeta,
          duration: nil,
          numTracks: nil,
          chapters: nil,
          tracks: nil,
          ebookFile: nil,
          ebookFormat: fmt.rawValue
        )
        return ABSBook(
          id: libraryItemId,
          libraryId: lib.id,
          media: media,
          addedAt: nil,
          updatedAt: nil,
          mediaId: nil
        )
      }
    }
    return nil
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
      for ser in s.series {
        for b in ser.books ?? [] where !seen.contains(b.id) {
          seen.insert(b.id)
          acc.append(b)
        }
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
      filtered =
        bookItems
        .filter(\.isPlayableAudiobook)
        .filter { book in
          guard let p = progressByItemId[book.id] else { return false }
          return !p.isFinished
        }
        .sorted {
          (progressByItemId[$0.id]?.lastUpdate ?? 0) > (progressByItemId[$1.id]?.lastUpdate ?? 0)
        }
    } else {
      filtered = []
    }
    let podcastEps: [ABSPodcastEpisodeListItem]
    if let plid = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !plid.isEmpty {
      var eps = payload.podcastEpisodes.filter { ($0.libraryId ?? "") == plid || $0.libraryId == nil }
      eps = eps.filter { ep in
        guard let p = progressByItemId[ep.progressLookupKey] else { return false }
        return !p.isFinished
      }
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

  /// Entfernt aus „Continue listening“-Regalen Einträge ohne passenden Server-Fortschritt oder mit `isFinished`.
  /// (`items-in-progress` / personalisierte Regale können nach `DELETE …/progress` kurz noch alte Zeilen liefern.)
  private func applyContinueListeningFinishedFilter() {
    guard !startShelves.isEmpty else { return }
    let newShelves = startShelves.map { shelf -> ABSStartShelfSection in
      guard isHomeContinueCategory(shelf.category) else { return shelf }
      let books = shelf.books.filter { book in
        guard let p = progressByItemId[book.id] else { return false }
        return !p.isFinished
      }
      let eps = shelf.podcastEpisodes.filter { episode in
        guard let p = progressByItemId[episode.progressLookupKey] else { return false }
        return !p.isFinished
      }
      if books.count == shelf.books.count, eps.count == shelf.podcastEpisodes.count { return shelf }
      return ABSStartShelfSection(
        id: shelf.id,
        category: shelf.category,
        displayTitle: shelf.displayTitle,
        books: books,
        podcastEpisodes: eps,
        authors: shelf.authors,
        series: shelf.series
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
    startShelves = startShelves.map { shelf in
      guard isHomeContinueCategory(shelf.category), !isStartCategoryEnabled(shelf.category),
        !shelf.podcastEpisodes.isEmpty
      else { return shelf }
      return ABSStartShelfSection(
        id: shelf.id,
        category: shelf.category,
        displayTitle: shelf.displayTitle,
        books: shelf.books,
        podcastEpisodes: [],
        authors: shelf.authors,
        series: shelf.series
      )
    }
    if episodes.isEmpty {
      startShelves = startShelves.map { shelf in
        guard isHomeContinueCategory(shelf.category), !shelf.podcastEpisodes.isEmpty else { return shelf }
        return ABSStartShelfSection(
          id: shelf.id,
          category: shelf.category,
          displayTitle: shelf.displayTitle,
          books: shelf.books,
          podcastEpisodes: [],
          authors: shelf.authors,
          series: shelf.series
        )
      }
      return
    }
    var remaining = episodes
    var newShelves: [ABSStartShelfSection] = []
    for shelf in startShelves {
      if isHomeContinueCategory(shelf.category), isStartCategoryEnabled(shelf.category), !remaining.isEmpty {
        newShelves.append(
          ABSStartShelfSection(
            id: shelf.id,
            category: shelf.category,
            displayTitle: shelf.displayTitle,
            books: shelf.books,
            podcastEpisodes: remaining,
            authors: shelf.authors,
            series: shelf.series
          ))
        remaining = []
      } else {
        newShelves.append(shelf)
      }
    }
    if !remaining.isEmpty {
      if isStartCategoryEnabled("recentlyListened") {
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
      } else if isStartCategoryEnabled("itemsInProgressFallback") {
        let cat = "itemsInProgressFallback"
        let title = ABSStartShelfLocalization.displayTitle(category: cat, serverLabel: "")
        newShelves.insert(
          ABSStartShelfSection(
            id: "podcast-continue-supplement-fallback",
            category: cat,
            displayTitle: title,
            books: [],
            podcastEpisodes: remaining,
            authors: []
          ),
          at: 0
        )
      }
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
      offlineHomeModeAuto = false
      applyAuthorizeUser(auth.user)
      token = auth.user.token
      UserDefaults.standard.set(token, forKey: Keys.token)
      libraries = try await c.libraries()
      await resolveLibrariesAfterServerFetch(userDefaultLibraryId: auth.userDefaultLibraryId)
      async let catalog: Void = await reloadLibrary(reset: true)
      async let pod: Void = await reloadPodcastLibrary(reset: true)
      _ = await (catalog, pod)
      await restoreLastPlayedOnLaunch()
    } catch {
      errorMessage = error.localizedDescription
      isRestoringLaunchPlayback = false
      player.setMiniPlayerPlaceholder(true)
      if !offlineHomeMode {
        offlineHomeModeAuto = true
      }
      mainTab = .start
    }
  }

  /// Pull-to-Refresh auf der Offline-Home: Verbindung zum Server testen; bei Erfolg Auto-Offline beenden bzw. manuellen Offline-Modus ausschalten.
  func tryReconnectFromOfflineHomePullToRefresh() async {
    refreshDownloadedShelfFromManifests()
    guard offlineHomeUIActive else { return }
    guard isNetworkReachable, let url = ABSAPIClient.normalizeServerURL(serverURL), !token.isEmpty else {
      return
    }
    let c = ABSAPIClient(baseURL: url, token: token)
    client = c
    isRestoringLaunchPlayback = true
    player.setMiniPlayerPlaceholder(true)
    do {
      let auth = try await c.authorize()
      applyAuthorizeUser(auth.user)
      token = auth.user.token
      UserDefaults.standard.set(token, forKey: Keys.token)
      libraries = try await c.libraries()
      await resolveLibrariesAfterServerFetch(userDefaultLibraryId: auth.userDefaultLibraryId)
      async let catalog: Void = await reloadLibrary(reset: true)
      async let pod: Void = await reloadPodcastLibrary(reset: true)
      _ = await (catalog, pod)
      await restoreLastPlayedOnLaunch()
      offlineHomeModeAuto = false
      if offlineHomeMode {
        offlineHomeMode = false
      } else {
        await loadStartDashboard()
      }
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
      applyAuthorizeUser(res.user)
      libraries = try await c.libraries()
      await resolveLibrariesAfterServerFetch(userDefaultLibraryId: res.userDefaultLibraryId)
      async let catalog: Void = await reloadLibrary(reset: true)
      async let pod: Void = await reloadPodcastLibrary(reset: true)
      _ = await (catalog, pod)
      await restoreLastPlayedOnLaunch()
      offlineHomeModeAuto = false
    } catch {
      errorMessage = error.localizedDescription
      isRestoringLaunchPlayback = false
      player.setMiniPlayerPlaceholder(true)
    }
  }

  func logout() {
    clearCoverImageCache()
    suppressOfflineModeSideEffects = true
    offlineHomeMode = false
    offlineHomeModeAuto = false
    pendingPostOfflineModeProgressSync = false
    suppressOfflineModeSideEffects = false
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
    booksBrowseSection = .books
    resetBooksBrowseLists()
    clearSearchResults()
    clearPodcastSearchResults()
    clearPodcastDirectorySearch()
    progressByItemId = [:]
    bookmarks = []
    ebookReaderSession = nil
    isPreparingEbook = false
    listeningStats = nil
    listeningStatsFetchedAt = nil
    UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
    UserDefaults.standard.removeObject(forKey: Keys.booksLibrary)
    UserDefaults.standard.removeObject(forKey: Keys.podcastsLibrary)
    UserDefaults.standard.removeObject(forKey: Keys.library)
    UserDefaults.standard.removeObject(forKey: "abstand_podcast_show_settings_v1")
    player.tearDownPlayer()
    downloadedShelfBooks = []
    isRestoringLaunchPlayback = false
    LibraryDiskCache.clearEverything()
  }

  func selectBooksLibrary(_ lib: ABSLibrary, navigateToCatalog: Bool = false) {
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    booksBrowseSection = .books
    resetBooksBrowseLists()
    selectedBooksLibrary = lib
    UserDefaults.standard.set(lib.id, forKey: Keys.booksLibrary)
    if navigateToCatalog { mainTab = .audio }
    restoreBooksCatalogAndHomeFromDisk(libraryIdOverride: lib.id)
    restoreAllBrowseListsFromDisk()
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
    booksBrowseSection = .books
    resetBooksBrowseLists()
    selectedBooksLibrary = nil
    books = []
    libraryPage = 0
    libraryTotal = 0
    UserDefaults.standard.set(Keys.librarySelectionNone, forKey: Keys.booksLibrary)
    if mainTab == .audio || mainTab == .ebooks { mainTab = .start }
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
    restoreAllBrowseListsFromDisk()
  }

  /// Browse-Listen (Autoren, Serien, …) aus dem Datenträger — sofort sichtbar beim Tab-Wechsel.
  private func restoreAllBrowseListsFromDisk() {
    guard cacheAccountURL() != nil, selectedBooksLibrary != nil else { return }
    _ = restoreBrowseAuthorsFromDisk()
    _ = restoreBrowseSeriesFromDisk()
    _ = restoreBrowseNarratorsFromDisk()
    _ = restoreBrowseCollectionsFromDisk()
    _ = restoreBrowseEbooksFromDisk()
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
        books = page.results.filter(\.isUsableLibraryCatalogRow)
      } else {
        books.append(contentsOf: page.results.filter(\.isUsableLibraryCatalogRow))
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
      if podcastShows.isEmpty {
        let ascending = podcastCatalogSortField == .random ? true : !podcastCatalogSortDescending
        let sortKey = podcastCatalogSortField.apiSortParameter
        if let account = cacheAccountURL(),
          let rows = LibraryDiskCache.loadPodcastShows(
            account: account, libraryId: lib.id, sortField: sortKey, ascending: ascending,
            decoder: ABSJSON.decoder())
        {
          podcastShows = rows
        }
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
      let ascending = podcastCatalogSortField == .random ? true : !podcastCatalogSortDescending
      let sortKey = podcastCatalogSortField.apiSortParameter
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

  /// Folgenliste auf dem Podcast-Tab (recent „New“ oder eine Sendung), inkl. abgeschlossener Folgen.
  /// Abgeschlossene Zeilen: gleiche Kennzeichnung wie bei Büchern (`checkmark.circle.fill` in `PodcastEpisodeRowCard`).
  var podcastEpisodesForPodcastsTab: [ABSPodcastEpisodeListItem] {
    podcastSelectedShowId != nil ? podcastFilteredEpisodes : podcastEpisodes
  }

  /// Nach Sortieränderung: Shows-Leiste neu laden; Episoden-Feed nur in der „New“-Ansicht.
  func schedulePodcastCatalogSortReload() {
    podcastCatalogSortReloadTask?.cancel()
    podcastCatalogSortReloadTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      await applyPodcastCatalogSortReload()
    }
  }

  private func applyPodcastCatalogSortReload() async {
    await reloadPodcastShowsCatalog()
    if podcastSelectedShowId == nil {
      await reloadPodcastLibrary(reset: true)
    }
  }

  func reloadPodcastShowsCatalog() async {
    guard let lib = selectedPodcastLibrary else { return }
    let ascending = podcastCatalogSortField == .random ? true : !podcastCatalogSortDescending
    let sortKey = podcastCatalogSortField.apiSortParameter
    let dec = ABSJSON.decoder()

    if !isNetworkReachable {
      if let account = cacheAccountURL(),
        let rows = LibraryDiskCache.loadPodcastShows(
          account: account, libraryId: lib.id, sortField: sortKey, ascending: ascending, decoder: dec)
      {
        podcastShows = rows
      }
      return
    }

    guard let c = client else { return }
    podcastShowsLoading = true
    defer { podcastShowsLoading = false }
    do {
      let (page, raw) = try await c.libraryItems(
        libraryId: lib.id,
        page: 0,
        limit: 120,
        sort: sortKey,
        ascending: ascending,
        minified: true,
        filter: nil
      )
      if let account = cacheAccountURL() {
        try? LibraryDiskCache.wipePodcastShowsSlug(
          account: account, libraryId: lib.id, sortField: sortKey, ascending: ascending)
        try? LibraryDiskCache.savePodcastShows(
          account: account, libraryId: lib.id, sortField: sortKey, ascending: ascending, data: raw)
      }
      podcastShows = page.results.filter(\.isListablePodcastLibraryItem)
    } catch {}
  }

  func selectPodcastShowFilter(_ showId: String?) async {
    let newKey = showId ?? ""
    let previewKey = podcastRssFeedPreviewForShowId ?? ""
    if newKey != previewKey {
      podcastRssFeedPreviewEpisodes = []
      podcastRssFeedPreviewForShowId = nil
      podcastRssDraftDownloadCompletedIds = []
      clearPodcastAutoDownloadSettingsDraft()
    }
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
      var full = try await c.item(id: showId, expanded: true)
      guard serial == podcastShowEpisodesLoadSerial, podcastSelectedShowId == showId else { return }
      if (full.media.podcastEpisodes ?? []).isEmpty {
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard serial == podcastShowEpisodesLoadSerial, podcastSelectedShowId == showId else { return }
        full = try await c.item(id: showId, expanded: true)
        guard serial == podcastShowEpisodesLoadSerial, podcastSelectedShowId == showId else { return }
      }
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
    if mainTab == .ebooks {
      await loadMoreBrowseEbooksIfNeeded(currentItemId: currentItemId)
      return
    }
    guard mainTab == .audio else { return }
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

  /// Pull-to-Refresh: Audio-Katalog (Server-Fortschritt + erste Seite neu).
  func refreshBooksCatalog() async {
    await performPullToRefresh { [self] in
      await refreshProgressFromServer()
      await reloadLibrary(reset: true)
      await refreshBooksBrowseSectionLists()
    }
  }

  /// Pull-to-Refresh: eBooks-Liste.
  func refreshEbooksCatalog() async {
    await performPullToRefresh { [self] in
      await refreshProgressFromServer()
      await loadBrowseEbooks(force: true)
    }
  }

  /// Pull-to-Refresh: Start-Tab (Regale / Offline-Reconnect).
  func refreshStartTabPullToRefresh() async {
    await performPullToRefresh { [self] in
      if offlineHomeUIActive {
        await tryReconnectFromOfflineHomePullToRefresh()
      } else {
        await loadStartDashboard()
        refreshDownloadedShelfFromManifests()
      }
    }
  }

  /// Pull-to-Refresh: Entity-Detail (Autor/Serie/…).
  func refreshEntityDetail(for nav: BooksEntityDetailNav) async {
    await performPullToRefresh { [self] in
      await reloadEntityDetail(for: nav, reset: true)
    }
  }

  private func resetBooksBrowseLists() {
    browseAuthors = []
    browseNarrators = []
    browseSeries = []
    browseCollections = []
    browseCollectionBooksById = [:]
    browseNarratorCoverItemIdByNarratorName = [:]
    browseNarratorsFetched = []
    browseCollectionsFetched = []
    browseAuthorsLoading = false
    browseNarratorsLoading = false
    browseSeriesLoading = false
    browseCollectionsLoading = false
    browseAuthorsNextPage = 0
    browseAuthorsTotal = 0
    browseSeriesNextPage = 0
    browseSeriesTotal = 0
    browseCollectionsTotal = 0
    browseEbooksBooks = []
    browseEbooksLoading = false
    browseEbooksTotal = 0
    browseEbooksPage = 0
    ebooksBrowseFormatSection = .all
  }

  private var ebooksBrowseSortAscending: Bool {
    catalogSortField == .random ? true : !catalogSortDescending
  }

  private var ebooksBrowseSortKey: String {
    catalogSortField.apiSortParameter
  }

  @discardableResult
  private func restoreBrowseEbooksFromDisk() -> Bool {
    guard let account = cacheAccountURL(), let lib = selectedBooksLibrary else { return false }
    guard
      let m = LibraryDiskCache.loadMergedBrowseEbooks(
        account: account,
        libraryId: lib.id,
        sort: ebooksBrowseSortKey,
        descending: !ebooksBrowseSortAscending,
        decoder: ABSJSON.decoder()
      )
    else { return false }
    // Server-Filter „ebooks“; minified-Einträge haben oft kein hasAttachedEbook-Flag.
    browseEbooksBooks = m.books.filter(\.isUsableLibraryCatalogRow)
    rememberEbookFormatsFromCatalog(browseEbooksBooks)
    browseEbooksTotal = max(m.total, browseEbooksBooks.count)
    browseEbooksPage = m.nextPage
    scheduleEnrichBrowseEbookFormats()
    return !browseEbooksBooks.isEmpty
  }

  /// Beim Wechsel in den Tab „eBooks“: Liste laden (ohne erzwungenen Reload).
  func loadBrowseEbooksOnTabAppear() async {
    await loadBrowseEbooks(force: false)
    scheduleEnrichBrowseEbookFormats()
  }

  private func loadBrowseEbooks(force: Bool) async {
    guard selectedBooksLibrary != nil else { return }
    if browseEbooksLoading { return }
    if !force, !browseEbooksBooks.isEmpty { return }
    if browseEbooksBooks.isEmpty {
      _ = restoreBrowseEbooksFromDisk()
    }
    if !force, !browseEbooksBooks.isEmpty { return }
    if !isNetworkReachable || client == nil {
      if browseEbooksBooks.isEmpty {
        browseEbooksBooks = offlineEbookFallbackFromAudioCatalog()
      }
      return
    }
    await loadBrowseEbooksPage(reset: true)
  }

  private func rememberEbookFormatsFromCatalog(_ books: [ABSBook]) {
    EbookLocalStore.syncKnownFormatsFromDisk(account: cacheAccountURL())
    for book in books {
      for fmt in book.attachedEbookFormats {
        EbookLocalStore.rememberKnownFormat(fmt, libraryItemId: book.id)
      }
    }
  }

  private func scheduleEnrichBrowseEbookFormats() {
    enrichBrowseEbookFormatsTask?.cancel()
    enrichBrowseEbookFormatsTask = Task { @MainActor [weak self] in
      await self?.enrichBrowseEbookFormatMetadata()
    }
  }

  private func bookNeedsEbookFormatEnrichment(_ book: ABSBook) -> Bool {
    if !book.attachedEbookFormats.isEmpty { return false }
    if EbookLocalStore.knownFormat(libraryItemId: book.id) != nil { return false }
    return true
  }

  /// `GET /api/items/:id?expanded=1` — liefert `libraryFiles` / `ebookFile` für EPUB/PDF-Filter im Tab.
  private func enrichBrowseEbookFormatMetadata() async {
    guard let c = client, isNetworkReachable else { return }
    let targets = browseEbooksBooks.filter { bookNeedsEbookFormatEnrichment($0) }
    guard !targets.isEmpty else { return }
    let batchSize = 4
    var offset = 0
    while offset < targets.count {
      if Task.isCancelled { return }
      let batch = Array(targets[offset..<min(offset + batchSize, targets.count)])
      offset += batch.count
      await withTaskGroup(of: (String, ABSBook)?.self) { group in
        for book in batch {
          let id = book.id
          group.addTask { @MainActor in
            guard !Task.isCancelled else { return nil }
            guard let expanded = try? await c.item(id: id, expanded: true) else { return nil }
            return (id, expanded)
          }
        }
        for await pair in group {
          guard let (id, expanded) = pair else { continue }
          guard let i = browseEbooksBooks.firstIndex(where: { $0.id == id }) else { continue }
          browseEbooksBooks[i] = expanded
          for fmt in expanded.attachedEbookFormats {
            EbookLocalStore.rememberKnownFormat(fmt, libraryItemId: id)
          }
        }
      }
    }
  }

  private func offlineEbookFallbackFromAudioCatalog() -> [ABSBook] {
    let catalog = books.isEmpty ? downloadedShelfBooks : books
    return catalog.filter(\.hasAttachedEbook)
  }

  private func loadBrowseEbooksPage(reset: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if !isNetworkReachable {
      if browseEbooksBooks.isEmpty {
        _ = restoreBrowseEbooksFromDisk()
      }
      if browseEbooksBooks.isEmpty {
        browseEbooksBooks = offlineEbookFallbackFromAudioCatalog()
      }
      return
    }
    if browseEbooksLoading { return }
    if reset {
      browseEbooksPage = 0
      if browseEbooksBooks.isEmpty {
        _ = restoreBrowseEbooksFromDisk()
      }
      if browseEbooksBooks.isEmpty {
        browseEbooksTotal = 0
      }
    } else {
      guard browseEbooksTotal > 0, browseEbooksBooks.count < browseEbooksTotal else { return }
    }
    let pageIndex = browseEbooksPage
    browseEbooksLoading = true
    defer { browseEbooksLoading = false }
    let ascending = ebooksBrowseSortAscending
    let sortKey = ebooksBrowseSortKey
    let descending = !ascending
    do {
      let (page, raw) = try await c.libraryItems(
        libraryId: lib.id,
        page: pageIndex,
        limit: 40,
        sort: sortKey,
        ascending: ascending,
        minified: false,
        filter: Self.ebooksBrowsePrimaryFilter
      )
      if let account = cacheAccountURL() {
        if reset, pageIndex == 0 {
          try? LibraryDiskCache.wipeBrowseEbooksSlug(
            account: account, libraryId: lib.id, sort: sortKey, descending: descending)
        }
        try? LibraryDiskCache.saveBrowseEbooksPage(
          account: account, libraryId: lib.id, sort: sortKey, descending: descending,
          pageIndex: pageIndex, data: raw)
      }
      let rawRows = page.results.filter(\.isUsableLibraryCatalogRow)
      let trustServer = serverEbookFilterLooksApplied(ebookPageTotal: page.total)
      let rows = trustServer ? rawRows : rawRows.filter(\.hasAttachedEbook)
      if reset {
        browseEbooksBooks = rows
      } else {
        browseEbooksBooks.append(contentsOf: rows)
      }
      rememberEbookFormatsFromCatalog(rows)
      browseEbooksTotal = page.total
      browseEbooksPage = page.page + 1
      if reset {
        await appendSupplementaryEbooksPage(client: c, libraryId: lib.id, sortKey: sortKey, descending: descending)
        if browseEbooksBooks.isEmpty, !trustServer {
          browseEbooksBooks = await collectEbooksFromLoadedCatalog(client: c, libraryId: lib.id)
          browseEbooksTotal = browseEbooksBooks.count
          browseEbooksPage = 1
        }
      }
      scheduleEnrichBrowseEbookFormats()
    } catch {
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      errorMessage = error.localizedDescription
    }
  }

  /// Server-Filter greift nur, wenn die Trefferzahl deutlich unter dem Gesamtkatalog liegt.
  private func serverEbookFilterLooksApplied(ebookPageTotal: Int) -> Bool {
    guard ebookPageTotal > 0 else { return false }
    guard libraryTotal > 0 else { return true }
    return ebookPageTotal < libraryTotal * 9 / 10
  }

  /// Fallback, wenn der Server-Filter ignoriert wird: Katalog durchsuchen (mit `ebookFormat` in minified).
  private func collectEbooksFromLoadedCatalog(client: ABSAPIClient, libraryId: String) async -> [ABSBook] {
    var seen = Set<String>()
    var out: [ABSBook] = []
    out.reserveCapacity(64)
    func absorb(_ batch: [ABSBook]) {
      for b in batch where b.hasAttachedEbook && seen.insert(b.id).inserted {
        out.append(b)
      }
    }
    absorb(books)
    var page = 0
    let limit = 100
    while page < 100 {
      do {
        let (pg, _) = try await client.libraryItems(
          libraryId: libraryId,
          page: page,
          limit: limit,
          sort: catalogSortField.apiSortParameter,
          ascending: catalogSortField == .random ? true : !catalogSortDescending,
          minified: true,
          filter: nil
        )
        absorb(pg.results.filter(\.isUsableLibraryCatalogRow))
        page += 1
        if pg.results.count < limit { break }
      } catch {
        break
      }
    }
    return out
  }

  /// Einmalig supplementäre E-Books ergänzen (kein Vollscan der Bibliothek).
  private func appendSupplementaryEbooksPage(
    client: ABSAPIClient, libraryId: String, sortKey: String, descending: Bool
  ) async {
    let ascending = !descending
    var seen = Set(browseEbooksBooks.map(\.id))
    guard
      let (pg, raw) = try? await client.libraryItems(
        libraryId: libraryId,
        page: 0,
        limit: 100,
        sort: sortKey,
        ascending: ascending,
        minified: false,
        filter: Self.ebooksBrowseSupplementaryFilter
      ),
      serverEbookFilterLooksApplied(ebookPageTotal: pg.total)
    else { return }
    if let account = cacheAccountURL() {
      try? LibraryDiskCache.saveBrowseEbooksSupplementary(
        account: account, libraryId: libraryId, sort: sortKey, descending: descending, data: raw)
    }
    let rows = pg.results.filter(\.isUsableLibraryCatalogRow)
    for book in rows where seen.insert(book.id).inserted {
      browseEbooksBooks.append(book)
    }
    rememberEbookFormatsFromCatalog(rows)
    scheduleEnrichBrowseEbookFormats()
  }

  func loadMoreBrowseEbooksIfNeeded(currentItemId: String?) async {
    guard mainTab == .ebooks else { return }
    guard browseEbooksTotal > 0 else { return }
    let initialDisplayed = booksWithEbookForDisplay()
    guard let id = currentItemId, let last = initialDisplayed.last?.id, id == last else { return }
    var attempts = 0
    while browseEbooksBooks.count < browseEbooksTotal, attempts < 10 {
      let countBefore = browseEbooksBooks.count
      await loadBrowseEbooksPage(reset: false)
      attempts += 1
      if browseEbooksBooks.count <= countBefore { break }
      if ebooksBrowseFormatSection == .all { break }
      if booksWithEbookForDisplay().count > initialDisplayed.count { break }
    }
  }

  func booksInBrowseCollection(id: String) -> [ABSBook] {
    browseCollectionBooksById[id] ?? []
  }

  func selectBooksBrowseSection(_ section: BooksBrowseSection) {
    booksBrowseSection = section
    Task { await loadBooksBrowseSectionContentIfNeeded() }
  }

  func reloadBrowseAuthorsAfterSortChange() async {
    await loadBrowseAuthors(force: true)
  }

  func reloadBrowseSeriesAfterSortChange() async {
    await loadBrowseSeries(force: true)
  }

  enum BooksToolbarSortReloadKind: Hashable {
    case mainCatalog
    case browseAuthors
    case browseSeries
  }

  /// Nach Sortierwechsel im Books-Tab: kurz entkoppeln, damit das Sort-`Menu` nicht bei jedem `@Published`-Takt zuklappt.
  func scheduleBooksToolbarSortReload(_ kind: BooksToolbarSortReloadKind) {
    booksToolbarSortReloadTask?.cancel()
    booksToolbarSortReloadTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      switch kind {
      case .mainCatalog:
        await reloadLibrary(reset: true)
        if mainTab == .ebooks {
          await loadBrowseEbooks(force: true)
        }
      case .browseAuthors:
        await reloadBrowseAuthorsAfterSortChange()
      case .browseSeries:
        await reloadBrowseSeriesAfterSortChange()
      }
    }
  }

  func reloadBrowseCollectionsAfterSortChange() async {
    await loadBrowseCollections(force: true)
  }

  private func loadBooksBrowseSectionContentIfNeeded() async {
    switch booksBrowseSection {
    case .books: break
    case .author: await loadBrowseAuthors(force: false)
    case .narrators: await loadBrowseNarrators(force: false)
    case .series: await loadBrowseSeries(force: false)
    case .collections: await loadBrowseCollections(force: false)
    }
  }

  private func refreshBooksBrowseSectionLists() async {
    switch booksBrowseSection {
    case .books: break
    case .author: await loadBrowseAuthors(force: true)
    case .narrators: await loadBrowseNarrators(force: true)
    case .series: await loadBrowseSeries(force: true)
    case .collections: await loadBrowseCollections(force: true)
    }
  }

  private func browseSeriesAPIDescending() -> Bool {
    browseSeriesSortField == .random ? false : browseSeriesSortDescending
  }

  @discardableResult
  private func restoreBrowseAuthorsFromDisk() -> Bool {
    guard let account = cacheAccountURL(), let lib = selectedBooksLibrary else { return false }
    let dec = ABSJSON.decoder()
    let descending = browseAuthorsSortDescending
    let sort = browseAuthorsSortField.apiSortParameter
    guard
      let m = LibraryDiskCache.loadMergedBrowseAuthors(
        account: account, libraryId: lib.id, sort: sort, descending: descending, decoder: dec)
    else { return false }
    browseAuthors = m.items
    browseAuthorsTotal = m.total
    browseAuthorsNextPage = m.nextPage
    return true
  }

  @discardableResult
  private func restoreBrowseSeriesFromDisk() -> Bool {
    guard let account = cacheAccountURL(), let lib = selectedBooksLibrary else { return false }
    let dec = ABSJSON.decoder()
    let descending = browseSeriesAPIDescending()
    let sort = browseSeriesSortField.apiSortParameter
    guard
      let m = LibraryDiskCache.loadMergedBrowseSeries(
        account: account, libraryId: lib.id, sort: sort, descending: descending, decoder: dec)
    else { return false }
    browseSeries = m.items
    browseSeriesTotal = m.total
    browseSeriesNextPage = m.nextPage
    return true
  }

  @discardableResult
  private func restoreBrowseCollectionsFromDisk() -> Bool {
    guard let account = cacheAccountURL(), let lib = selectedBooksLibrary else { return false }
    guard
      let pair = LibraryDiskCache.loadBrowseCollections(
        account: account, libraryId: lib.id, decoder: ABSJSON.decoder())
    else { return false }
    browseCollectionsFetched = pair.items
    browseCollections = sortedBrowseCollections(pair.items)
    browseCollectionsTotal = pair.total
    var dict: [String: [ABSBook]] = [:]
    dict.reserveCapacity(pair.items.count)
    for item in pair.items {
      dict[item.id] = item.books ?? []
    }
    browseCollectionBooksById = dict
    return true
  }

  @discardableResult
  private func restoreBrowseNarratorsFromDisk() -> Bool {
    guard let account = cacheAccountURL(), let lib = selectedBooksLibrary else { return false }
    guard
      let pair = LibraryDiskCache.loadBrowseNarrators(
        account: account, libraryId: lib.id, decoder: ABSJSON.decoder())
    else { return false }
    browseNarratorsFetched = pair.narrators
    browseNarrators = sortedBrowseNarrators(pair.narrators)
    browseNarratorCoverItemIdByNarratorName = pair.coverMap
    return true
  }

  private func loadBrowseAuthors(force: Bool) async {
    guard client != nil, selectedBooksLibrary != nil else { return }
    if browseAuthorsLoading { return }
    if !force, !browseAuthors.isEmpty { return }
    if browseAuthors.isEmpty {
      _ = restoreBrowseAuthorsFromDisk()
    }
    if !force, !browseAuthors.isEmpty { return }
    if !isNetworkReachable {
      _ = restoreBrowseAuthorsFromDisk()
      return
    }
    await loadBrowseAuthorsPage(reset: true)
  }

  private func loadBrowseAuthorsPage(reset: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if !isNetworkReachable {
      _ = restoreBrowseAuthorsFromDisk()
      return
    }
    if browseAuthorsLoading { return }
    if reset {
      browseAuthorsNextPage = 0
      if browseAuthors.isEmpty {
        _ = restoreBrowseAuthorsFromDisk()
      }
      if browseAuthors.isEmpty {
        browseAuthorsTotal = 0
      }
    } else {
      guard browseAuthorsTotal > 0, browseAuthors.count < browseAuthorsTotal else { return }
    }
    let page = browseAuthorsNextPage
    browseAuthorsLoading = true
    defer { browseAuthorsLoading = false }
    do {
      let descending = browseAuthorsSortDescending
      let (items, total, raw) = try await c.libraryAuthorsPage(
        libraryId: lib.id,
        page: page,
        limit: 50,
        sort: browseAuthorsSortField.apiSortParameter,
        descending: descending
      )
      if let account = cacheAccountURL() {
        if reset, page == 0 {
          try? LibraryDiskCache.wipeBrowseAuthorsSlug(
            account: account, libraryId: lib.id,
            sort: browseAuthorsSortField.apiSortParameter, descending: descending)
        }
        try? LibraryDiskCache.saveBrowseAuthorsPage(
          account: account, libraryId: lib.id,
          sort: browseAuthorsSortField.apiSortParameter, descending: descending,
          pageIndex: page, data: raw)
      }
      browseAuthorsTotal = total
      if items.isEmpty, !reset { return }
      if reset {
        browseAuthors = items
      } else {
        browseAuthors.append(contentsOf: items)
      }
      browseAuthorsNextPage = page + 1
    } catch {
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      errorMessage = error.localizedDescription
    }
  }

  private func loadBrowseNarrators(force: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if browseNarratorsLoading { return }
    if !force, !browseNarrators.isEmpty { return }
    if browseNarrators.isEmpty {
      _ = restoreBrowseNarratorsFromDisk()
    }
    if !force, !browseNarrators.isEmpty { return }
    if !isNetworkReachable {
      _ = restoreBrowseNarratorsFromDisk()
      return
    }
    browseNarratorsLoading = true
    defer { browseNarratorsLoading = false }
    do {
      let (items, narratorsData) = try await c.libraryNarrators(libraryId: lib.id)
      browseNarratorsFetched = items
      browseNarrators = sortedBrowseNarrators(items)
      browseNarratorCoverItemIdByNarratorName = [:]
      if let account = cacheAccountURL() {
        try? LibraryDiskCache.saveBrowseNarrators(
          account: account, libraryId: lib.id, narratorsJSON: narratorsData, coverMap: nil)
      }
      await fillBrowseNarratorCoverItemIds()
    } catch {
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      errorMessage = error.localizedDescription
    }
  }

  func resortBrowseNarratorsDisplay() {
    browseNarrators = sortedBrowseNarrators(browseNarratorsFetched)
  }

  func resortBrowseCollectionsDisplay() {
    browseCollections = sortedBrowseCollections(browseCollectionsFetched)
  }

  private func sortedBrowseNarrators(_ rows: [ABSLibraryNarratorListItem]) -> [ABSLibraryNarratorListItem] {
    let desc = browseNarratorsSortDescending
    switch browseNarratorsSortField {
    case .name:
      return rows.sorted {
        desc
          ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
          : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
    case .numBooks:
      return rows.sorted {
        let a = $0.numBooks ?? 0
        let b = $1.numBooks ?? 0
        if a == b {
          return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return desc ? a > b : a < b
      }
    }
  }

  private func sortedBrowseCollections(_ rows: [ABSLibraryCollectionListItem]) -> [ABSLibraryCollectionListItem] {
    let desc = browseCollectionsSortDescending
    switch browseCollectionsSortField {
    case .name:
      return rows.sorted {
        desc
          ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
          : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
    case .bookCount:
      return rows.sorted {
        let a = $0.books?.count ?? 0
        let b = $1.books?.count ?? 0
        if a == b {
          return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return desc ? a > b : a < b
      }
    case .createdAt:
      return rows.sorted {
        let a = $0.createdAt ?? 0
        let b = $1.createdAt ?? 0
        if a == b {
          return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return desc ? a > b : a < b
      }
    case .lastUpdate:
      return rows.sorted {
        let a = $0.lastUpdate ?? 0
        let b = $1.lastUpdate ?? 0
        if a == b {
          return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return desc ? a > b : a < b
      }
    }
  }

  private func fillBrowseNarratorCoverItemIds() async {
    guard let c = client, let lib = selectedBooksLibrary, isNetworkReachable else { return }
    var missing = Set(browseNarrators.map(\.name))
    guard !missing.isEmpty else { return }
    var map: [String: String] = [:]
    let maxPages = 40
    for page in 0..<maxPages where !missing.isEmpty {
      let pg: ABSPage<ABSBook>
      do {
        let (p, _) = try await c.libraryItems(
          libraryId: lib.id,
          page: page,
          limit: 100,
          sort: CatalogSortField.title.apiSortParameter,
          ascending: true,
          minified: true,
          filter: nil
        )
        pg = p
      } catch {
        break
      }
      for book in pg.results {
        for n in book.media.metadata.narratorNamesForLibraryBrowseCoverMatch() where missing.contains(n) {
          map[n] = book.id
          missing.remove(n)
        }
      }
      if pg.results.count < 100 { break }
    }
    browseNarratorCoverItemIdByNarratorName = map
    if let account = cacheAccountURL(), let lib = selectedBooksLibrary, !map.isEmpty {
      try? LibraryDiskCache.saveBrowseNarratorCoverMap(
        account: account, libraryId: lib.id, coverMap: map)
    }
  }

  private func loadBrowseSeries(force: Bool) async {
    guard client != nil, selectedBooksLibrary != nil else { return }
    if browseSeriesLoading { return }
    if !force, !browseSeries.isEmpty { return }
    if browseSeries.isEmpty {
      _ = restoreBrowseSeriesFromDisk()
    }
    if !force, !browseSeries.isEmpty { return }
    if !isNetworkReachable {
      _ = restoreBrowseSeriesFromDisk()
      return
    }
    await loadBrowseSeriesPage(reset: true)
  }

  private func loadBrowseSeriesPage(reset: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if !isNetworkReachable {
      _ = restoreBrowseSeriesFromDisk()
      return
    }
    if browseSeriesLoading { return }
    if reset {
      browseSeriesNextPage = 0
      if browseSeries.isEmpty {
        _ = restoreBrowseSeriesFromDisk()
      }
      if browseSeries.isEmpty {
        browseSeriesTotal = 0
      }
    } else {
      guard browseSeriesTotal > 0, browseSeries.count < browseSeriesTotal else { return }
    }
    let page = browseSeriesNextPage
    browseSeriesLoading = true
    defer { browseSeriesLoading = false }
    do {
      let descending = browseSeriesAPIDescending()
      let (items, total, raw) = try await c.librarySeriesPage(
        libraryId: lib.id,
        page: page,
        limit: 40,
        sort: browseSeriesSortField.apiSortParameter,
        descending: descending
      )
      if let account = cacheAccountURL() {
        if reset, page == 0 {
          try? LibraryDiskCache.wipeBrowseSeriesSlug(
            account: account, libraryId: lib.id,
            sort: browseSeriesSortField.apiSortParameter, descending: descending)
        }
        try? LibraryDiskCache.saveBrowseSeriesPage(
          account: account, libraryId: lib.id,
          sort: browseSeriesSortField.apiSortParameter, descending: descending,
          pageIndex: page, data: raw)
      }
      browseSeriesTotal = total
      if items.isEmpty, !reset { return }
      if reset {
        browseSeries = items
      } else {
        browseSeries.append(contentsOf: items)
      }
      browseSeriesNextPage = page + 1
    } catch {
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      errorMessage = error.localizedDescription
    }
  }

  private func loadBrowseCollections(force: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if browseCollectionsLoading { return }
    if !force, !browseCollections.isEmpty { return }
    if browseCollections.isEmpty {
      _ = restoreBrowseCollectionsFromDisk()
    }
    if !force, !browseCollections.isEmpty { return }
    if !isNetworkReachable {
      _ = restoreBrowseCollectionsFromDisk()
      return
    }
    browseCollectionsLoading = true
    defer { browseCollectionsLoading = false }
    do {
      let (items, total, raw) = try await c.libraryCollectionsAll(libraryId: lib.id, minified: true)
      if let account = cacheAccountURL() {
        try? LibraryDiskCache.saveBrowseCollections(account: account, libraryId: lib.id, data: raw)
      }
      browseCollectionsFetched = items
      browseCollections = sortedBrowseCollections(items)
      browseCollectionsTotal = total
      var dict: [String: [ABSBook]] = [:]
      dict.reserveCapacity(items.count)
      for item in items {
        dict[item.id] = item.books ?? []
      }
      browseCollectionBooksById = dict
    } catch {
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      errorMessage = error.localizedDescription
    }
  }

  func loadMoreBrowseAuthorsIfNeeded(currentItemId: String?) async {
    guard booksBrowseSection == .author else { return }
    guard browseAuthorsTotal > 0 else { return }
    guard let id = currentItemId, let last = browseAuthors.last?.id, id == last else { return }
    guard browseAuthors.count < browseAuthorsTotal else { return }
    await loadBrowseAuthorsPage(reset: false)
  }

  func loadMoreBrowseSeriesIfNeeded(currentItemId: String?) async {
    guard booksBrowseSection == .series else { return }
    guard browseSeriesTotal > 0 else { return }
    guard let id = currentItemId, let last = browseSeries.last?.id, id == last else { return }
    guard browseSeries.count < browseSeriesTotal else { return }
    await loadBrowseSeriesPage(reset: false)
  }

  /// Pull-to-Refresh: Podcast-Tab (Sendungsleiste, „New“-Liste oder gewählte Sendung).
  func refreshPodcastsTab() async {
    await refreshProgressFromServer()
    await reloadPodcastShowsCatalog()
    if let showId = podcastSelectedShowId {
      await reloadPodcastLibrary(reset: true)
      await loadPodcastEpisodesForShowLibraryItem(showId)
    } else {
      await reloadPodcastLibrary(reset: true)
    }
  }

  /// Folgen der gewählten Sendung neu laden (nach RSS ein-/ausblenden; ohne „New“-Feed-Reload).
  private func reloadPodcastShowEpisodeListForCurrentShow(_ showId: String) async {
    guard podcastSelectedShowId == showId else { return }
    await refreshProgressFromServer()
    await reloadPodcastShowsCatalog()
    await loadPodcastEpisodesForShowLibraryItem(showId)
  }

  private func clearPodcastRssFeedPreviewState() {
    podcastRssFeedPreviewEpisodes = []
    podcastRssFeedPreviewForShowId = nil
    podcastRssDraftDownloadCompletedIds = []
    clearPodcastAutoDownloadSettingsDraft()
  }

  /// RSS-Vorschau schließen und Bibliotheks-Folgen neu laden.
  func closePodcastRssFeedPreview(reloadLibrary: Bool = true) async {
    let sid = podcastRssFeedPreviewForShowId
    guard let sid, !sid.isEmpty else { return }
    clearPodcastRssFeedPreviewState()
    errorMessage = nil
    if reloadLibrary, podcastSelectedShowId == sid {
      await reloadPodcastShowEpisodeListForCurrentShow(sid)
    }
  }

  /// Vor dem Settings-Sheet: RSS aus und Einstellungen laden.
  func preparePodcastShowSettingsSheet(showId: String) async {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty, podcastSelectedShowId == sid else { return }
    if podcastRssFeedPreviewForShowId == sid {
      await closePodcastRssFeedPreview(reloadLibrary: true)
    }
    await loadPodcastAutoDownloadSettings(showId: sid)
  }

  /// Toolbar: Feed-Vorschau ein-/ausblenden; jeweils mit Reload der Episoden-Ansicht.
  func togglePodcastRssFeedToolbar(podcastLibraryItemId: String) async {
    guard !podcastLibraryItemId.isEmpty else { return }
    if podcastRssFeedPreviewForShowId == podcastLibraryItemId {
      clearPodcastRssFeedPreviewState()
      errorMessage = nil
      if podcastSelectedShowId == podcastLibraryItemId {
        await reloadPodcastShowEpisodeListForCurrentShow(podcastLibraryItemId)
        await loadStartDashboard()
      }
      return
    }

    clearPodcastRssFeedPreviewState()
    podcastRssFeedPreviewForShowId = podcastLibraryItemId
    errorMessage = nil

    if podcastSelectedShowId == podcastLibraryItemId {
      async let libraryReload = reloadPodcastShowEpisodeListForCurrentShow(podcastLibraryItemId)
      async let rssLoad = loadPodcastRssFeedIntoEpisodeList(podcastLibraryItemId: podcastLibraryItemId)
      _ = await (libraryReload, rssLoad)
    } else {
      await loadPodcastRssFeedIntoEpisodeList(podcastLibraryItemId: podcastLibraryItemId)
    }
  }

  /// RSS-Feed parsen und Vorschau für diese Sendung setzen (Kontextmenü / intern).
  func loadPodcastRssFeedIntoEpisodeList(podcastLibraryItemId: String) async {
    guard !podcastLibraryItemId.isEmpty, let c = client else { return }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      revertPodcastRssFeedPreviewIfEmpty(showId: podcastLibraryItemId)
      return
    }
    guard !podcastRssFeedLoadInProgressShowIds.contains(podcastLibraryItemId) else { return }
    podcastRssFeedLoadInProgressShowIds.insert(podcastLibraryItemId)
    defer { podcastRssFeedLoadInProgressShowIds.remove(podcastLibraryItemId) }
    do {
      guard let feedUrl = await rssFeedUrlForPodcastShow(libraryItemId: podcastLibraryItemId) else {
        errorMessage = "No RSS feed URL for this show."
        revertPodcastRssFeedPreviewIfEmpty(showId: podcastLibraryItemId)
        return
      }
      let data = try await c.fetchPodcastRssFeed(rssFeedUrl: feedUrl)
      let drafts = try ABSPodcastRssFeedEpisodeDraft.episodesFromFeedApiResponse(data)
      podcastRssFeedPreviewForShowId = podcastLibraryItemId
      podcastRssFeedPreviewEpisodes = drafts
      podcastRssDraftDownloadCompletedIds = []
      if drafts.isEmpty {
        errorMessage = "No episodes found in the feed."
      } else {
        errorMessage = nil
      }
      await loadPodcastAutoDownloadSettings(showId: podcastLibraryItemId)
    } catch {
      errorMessage = error.localizedDescription
      revertPodcastRssFeedPreviewIfEmpty(showId: podcastLibraryItemId)
    }
  }

  /// RSS-Vorschau zurücknehmen, wenn der Feed nicht geladen werden konnte (keine Folgen).
  private func revertPodcastRssFeedPreviewIfEmpty(showId: String) {
    guard podcastRssFeedPreviewForShowId == showId, podcastRssFeedPreviewEpisodes.isEmpty else {
      return
    }
    podcastRssFeedPreviewForShowId = nil
    clearPodcastAutoDownloadSettingsDraft()
  }

  func loadPodcastAutoDownloadSettings(showId: String) async {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty, let c = client else { return }
    podcastAutoDownloadSettingsLoading = true
    defer { podcastAutoDownloadSettingsLoading = false }
    do {
      let item = try await c.item(id: sid, expanded: true)
      applyPodcastAutoDownloadSettings(from: item, showId: sid)
    } catch {
      if podcastAutoDownloadSettingsShowId == sid {
        errorMessage = error.localizedDescription
      }
    }
  }

  func savePodcastAutoDownloadSettings(showId: String) async {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty, let c = client, isNetworkReachable else { return }
    guard !podcastAutoDownloadSettingsLoading else { return }
    guard podcastAutoDownloadSettingsShowId == sid else { return }
    podcastAutoDownloadSettingsSaving = true
    defer { podcastAutoDownloadSettingsSaving = false }
    do {
      try await c.patchPodcastMediaAutoDownload(
        itemId: sid,
        autoDownloadEpisodes: podcastAutoDownloadEnabled,
        autoDownloadSchedule: podcastAutoDownloadInterval.cronExpression
      )
      let item = try await c.item(id: sid, expanded: true)
      replacePodcastShowInCatalog(item)
      applyPodcastAutoDownloadSettings(from: item, showId: sid)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func applyPodcastAutoDownloadSettings(from item: ABSBook, showId: String) {
    podcastAutoDownloadSettingsShowId = showId
    podcastAutoDownloadEnabled = item.media.autoDownloadEpisodes ?? false
    podcastAutoDownloadInterval = PodcastAutoDownloadInterval.from(cron: item.media.autoDownloadSchedule)
  }

  private func clearPodcastAutoDownloadSettingsDraft() {
    podcastAutoDownloadSettingsShowId = nil
    podcastAutoDownloadEnabled = false
    podcastAutoDownloadInterval = .default
  }

  private func replacePodcastShowInCatalog(_ updated: ABSBook) {
    guard let idx = podcastShows.firstIndex(where: { $0.id == updated.id }) else { return }
    podcastShows[idx] = updated
  }

  /// Eine Feed-Folge auf den Server laden (`download-episodes`).
  func downloadPodcastRssEpisodeDraft(_ draft: ABSPodcastRssFeedEpisodeDraft, podcastLibraryItemId: String) async {
    guard let c = client else { return }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    guard podcastSelectedShowId == podcastLibraryItemId else { return }
    guard !podcastRssEpisodeDownloadInProgressDraftIds.contains(draft.id) else { return }
    guard !podcastRssDraftDownloadCompletedIds.contains(draft.id) else { return }
    if podcastFilteredEpisodes.contains(where: { draft.matchesLibraryEpisode($0) }) { return }

    podcastRssEpisodeDownloadInProgressDraftIds.insert(draft.id)
    defer { podcastRssEpisodeDownloadInProgressDraftIds.remove(draft.id) }
    let draftId = draft.id
    do {
      let obj = try JSONSerialization.jsonObject(with: draft.episodePayloadJSON, options: [.fragmentsAllowed])
      let body = try JSONSerialization.data(withJSONObject: [obj])
      try await c.downloadPodcastEpisodesToLibrary(
        podcastLibraryItemId: podcastLibraryItemId,
        episodesJsonArray: body
      )
      var done = podcastRssDraftDownloadCompletedIds
      done.insert(draftId)
      podcastRssDraftDownloadCompletedIds = done
      await refreshProgressFromServer()
      await mergeNewPodcastLibraryEpisodesFromExpandedItem(showLibraryItemId: podcastLibraryItemId)
      errorMessage = nil
      await loadStartDashboard()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func rssFeedUrlForPodcastShow(libraryItemId: String) async -> String? {
    if let s = podcastShows.first(where: { $0.id == libraryItemId }),
      let u = s.media.metadata.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
      !u.isEmpty
    {
      return u
    }
    guard let c = client else { return nil }
    do {
      let full = try await c.item(id: libraryItemId, expanded: true)
      let u = full.media.metadata.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return u.isEmpty ? nil : u
    } catch {
      return nil
    }
  }

  /// Nach `download-episodes`: nur neue `episodeId`s an `podcastFilteredEpisodes` anhängen (kein kompletter Listenersatz).
  private func mergeNewPodcastLibraryEpisodesFromExpandedItem(showLibraryItemId: String) async {
    guard let c = client, let lib = selectedPodcastLibrary else { return }
    guard podcastSelectedShowId == showLibraryItemId else { return }

    func attemptMerge() async throws -> Int {
      let full = try await c.item(id: showLibraryItemId, expanded: true)
      guard podcastSelectedShowId == showLibraryItemId else { return 0 }
      guard let eps = full.media.podcastEpisodes, !eps.isEmpty else { return 0 }
      let rows: [ABSPodcastEpisodeListItem] = eps.compactMap {
        ABSPodcastEpisodeListItem.fromDTO(
          $0, fallbackShow: full, libraryId: lib.id, forceLibraryItemId: full.id)
      }
      var seenKeys = Set(podcastFilteredEpisodes.map(\.progressLookupKey))
      var merged = podcastFilteredEpisodes
      var added = 0
      for row in rows {
        let k = row.progressLookupKey
        guard seenKeys.insert(k).inserted else { continue }
        merged.append(row)
        added += 1
      }
      guard added > 0 else { return 0 }
      podcastFilteredEpisodes = Self.sortPodcastEpisodesNewestFirst(merged)
      return added
    }

    try? await Task.sleep(nanoseconds: 400_000_000)
    do {
      var n = try await attemptMerge()
      if n == 0 {
        try? await Task.sleep(nanoseconds: 650_000_000)
        n = try await attemptMerge()
      }
    } catch {}
  }

  /// Pull-to-Refresh: Bibliothekssuche (aktueller Suchtext, ohne Debounce).
  func refreshBooksSearchResults() async {
    await performPullToRefresh { [self] in
      searchTask?.cancel()
      let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      await performSearch(query: q)
    }
  }

  func scheduleSearch() {
    guard mainTab == .audio || mainTab == .search else { return }
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
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      errorMessage = error.localizedDescription
      clearSearchResults()
    }
  }

  private func setBooksLibraryFilterSummary(prefix: String, detail: String?) {
    let d = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    activeLibraryFilterSummary = d.isEmpty ? prefix : "\(prefix): \(d)"
  }

  func openAuthorDetail(authorId: String, displayName: String? = nil, numBooks: Int? = nil) {
    let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    booksEntityDetailNav = BooksEntityDetailNav(
      kind: .author,
      entityId: authorId,
      title: name.isEmpty ? "Author" : name,
      numBooks: numBooks
    )
  }

  func openSeriesDetail(seriesId: String, displayName: String? = nil, numBooks: Int? = nil) {
    let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    booksEntityDetailNav = BooksEntityDetailNav(
      kind: .series,
      entityId: seriesId,
      title: name.isEmpty ? "Series" : name,
      numBooks: numBooks
    )
  }

  func openNarratorDetail(narratorName: String, numBooks: Int? = nil) {
    let name = narratorName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    booksEntityDetailNav = BooksEntityDetailNav(
      kind: .narrator,
      entityId: name,
      title: name,
      numBooks: numBooks
    )
  }

  func applyAuthorFilter(authorId: String, displayName: String? = nil) {
    openAuthorDetail(authorId: authorId, displayName: displayName)
  }

  func applySeriesFilter(seriesId: String, displayName: String? = nil) {
    openSeriesDetail(seriesId: seriesId, displayName: displayName)
  }

  func applyNarratorFilter(narratorName: String) {
    openNarratorDetail(narratorName: narratorName)
  }

  /// Detailseite: Entity-API wo vorhanden (`/api/authors/:id`, `/api/series/:id`), sonst gefilterte Library-Items.
  func reloadEntityDetail(for nav: BooksEntityDetailNav, reset: Bool) async {
    guard client != nil, selectedBooksLibrary != nil else { return }
    let key = nav.id
    if reset {
      entityDetailNavKey = key
      entityDetailPage = 0
      entityDetailBooks = []
      entityDetailTotal = 0
      entityDetailDescription = nil
      entityDetailMetaReady = false
      entityDetailAuthorSeriesSections = []
      entityDetailAuthorStandaloneBooks = []
      entityDetailUsesLibraryItemFilter = false
    }
    guard entityDetailNavKey == key else { return }
    if !isNetworkReachable {
      entityDetailBooks = []
      entityDetailTotal = 0
      entityDetailAuthorSeriesSections = []
      entityDetailAuthorStandaloneBooks = []
      entityDetailMetaReady = true
      return
    }
    entityDetailLoading = true
    defer {
      if entityDetailNavKey == key {
        entityDetailLoading = false
        entityDetailMetaReady = true
      }
    }
    guard let c = client, let lib = selectedBooksLibrary else { return }
    do {
      switch nav.kind {
      case .author:
        let detail = try await c.authorDetail(
          authorId: nav.entityId,
          libraryId: lib.id,
          includeItems: true,
          includeSeries: true
        )
        guard entityDetailNavKey == key else { return }
        entityDetailDescription = detail.description
        applyAuthorDetailBooksLayout(detail: detail)
        entityDetailUsesLibraryItemFilter = false
      case .series:
        let detail = try await c.seriesDetail(seriesId: nav.entityId)
        guard entityDetailNavKey == key else { return }
        entityDetailDescription = detail.description
        if let cached = browseSeries.first(where: { $0.id == nav.entityId })?.books {
          let rows = cached.filter(\.isUsableLibraryCatalogRow)
          entityDetailBooks = rows
          entityDetailTotal = rows.count
          entityDetailUsesLibraryItemFilter = false
        } else {
          entityDetailUsesLibraryItemFilter = true
          try await reloadEntityDetailBooksViaLibraryFilter(for: nav, reset: true, key: key)
        }
      case .narrator:
        entityDetailDescription = nil
        entityDetailUsesLibraryItemFilter = true
        try await reloadEntityDetailBooksViaLibraryFilter(for: nav, reset: true, key: key)
      }
    } catch {
      guard entityDetailNavKey == key else { return }
      errorMessage = error.localizedDescription
    }
  }

  private func applyAuthorDetailBooksLayout(detail: ABSAuthorDetail) {
    let allItems = (detail.libraryItems ?? []).filter(\.isUsableLibraryCatalogRow)
    var inSeriesIds = Set<String>()
    var sections: [EntityDetailAuthorSeriesSection] = []
    for series in detail.series ?? [] {
      let books = entityDetailSortBooksBySeriesOrder(
        (series.items ?? []).filter(\.isUsableLibraryCatalogRow))
      guard !books.isEmpty else { continue }
      inSeriesIds.formUnion(books.map(\.id))
      sections.append(
        EntityDetailAuthorSeriesSection(id: series.id, name: series.name, books: books))
    }
    let standalone = entityDetailSortBooksBySeriesOrder(
      allItems.filter { !inSeriesIds.contains($0.id) })
    entityDetailAuthorSeriesSections = sections
    entityDetailAuthorStandaloneBooks = standalone
    entityDetailBooks = allItems
    entityDetailTotal = allItems.count
  }

  private func entityDetailSortBooksBySeriesOrder(_ books: [ABSBook]) -> [ABSBook] {
    books.sorted { lhs, rhs in
      let lk = entityDetailSeriesSortKey(for: lhs)
      let rk = entityDetailSeriesSortKey(for: rhs)
      if lk.number != rk.number { return lk.number < rk.number }
      if lk.text != rk.text { return lk.text.localizedStandardCompare(rk.text) == .orderedAscending }
      return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
    }
  }

  private func entityDetailSeriesSortKey(for book: ABSBook) -> (number: Double, text: String) {
    guard let series = book.media.metadata.series?.first else {
      return (.infinity, book.displayTitle)
    }
    let seq = series.sequence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if let n = Double(seq) { return (n, seq) }
    if !seq.isEmpty { return (.infinity, seq) }
    return (.infinity, series.name)
  }

  private func reloadEntityDetailBooksViaLibraryFilter(
    for nav: BooksEntityDetailNav, reset: Bool, key: String
  ) async throws {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if reset {
      entityDetailPage = 0
      entityDetailBooks = []
      entityDetailTotal = 0
      entityDetailAuthorSeriesSections = []
      entityDetailAuthorStandaloneBooks = []
    } else {
      guard entityDetailTotal > 0, entityDetailBooks.count < entityDetailTotal else { return }
    }
    let ascending = catalogSortField == .random ? true : !catalogSortDescending
    let sortKey = catalogSortField.apiSortParameter
    let pageIndex = entityDetailPage
    let (page, _) = try await c.libraryItems(
      libraryId: lib.id,
      page: pageIndex,
      limit: 40,
      sort: sortKey,
      ascending: ascending,
      minified: true,
      filter: nav.libraryFilter
    )
    guard entityDetailNavKey == key else { return }
    let rows = page.results.filter(\.isUsableLibraryCatalogRow)
    if reset || pageIndex == 0 {
      entityDetailBooks = rows
    } else {
      entityDetailBooks.append(contentsOf: rows)
    }
    entityDetailTotal = page.total
    entityDetailPage = page.page + 1
  }

  func loadMoreEntityDetailIfNeeded(nav: BooksEntityDetailNav, currentItemId: String?) async {
    guard entityDetailUsesLibraryItemFilter else { return }
    guard nav.id == entityDetailNavKey else { return }
    guard let id = currentItemId, let last = entityDetailBooks.last?.id, id == last else { return }
    guard entityDetailBooks.count < entityDetailTotal else { return }
    let key = nav.id
    entityDetailLoading = true
    defer {
      if entityDetailNavKey == key {
        entityDetailLoading = false
      }
    }
    do {
      try await reloadEntityDetailBooksViaLibraryFilter(for: nav, reset: false, key: key)
    } catch {
      guard entityDetailNavKey == key else { return }
      errorMessage = error.localizedDescription
    }
  }

  func entityDetailCoverURL(for nav: BooksEntityDetailNav) -> URL? {
    switch nav.kind {
    case .author:
      return authorImageURL(authorId: nav.entityId)
    case .narrator:
      if let bookId = browseNarratorCoverItemIdByNarratorName[nav.entityId] {
        return coverURL(for: bookId)
      }
      return nil
    case .series:
      if let first = entityDetailBooks.first {
        return coverURL(for: first.id)
      }
      return nil
    }
  }

  func applyTagFilter(tagName: String) {
    searchTask?.cancel()
    searchText = ""
    clearSearchResults()
    setBooksLibraryFilterSummary(prefix: "Tag", detail: tagName)
    let b64 = Data(tagName.utf8).base64EncodedString()
    activeLibraryFilter = "tags.\(b64)"
    mainTab = .audio
    Task { await reloadLibrary(reset: true) }
  }

  func applyGenreFilter(genreName: String) {
    searchTask?.cancel()
    searchText = ""
    clearSearchResults()
    setBooksLibraryFilterSummary(prefix: "Genre", detail: genreName)
    let b64 = Data(genreName.utf8).base64EncodedString()
    activeLibraryFilter = "genres.\(b64)"
    mainTab = .audio
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
    mainTab = .search
    Task { await performSearch(query: q) }
  }

  /// Katalog durchsuchender Sprung: Podcast-Tab, passende Sendung wählen oder Suche nach Show.
  func openPodcastSearchFromText(_ raw: String) {
    let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty, q != "—" else { return }
    podcastSearchTask?.cancel()
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

  private func cachedBookFallback(id: String) -> ABSBook? {
    if let book = books.first(where: { $0.id == id }) { return book }
    if let book = podcastSearchBooks.first(where: { $0.id == id }) { return book }
    if let episode = podcastEpisodes.first(where: { $0.libraryItemId == id }) {
      return episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
    }
    if let book = startBooks.first(where: { $0.id == id }) { return book }
    if let book = searchBooks.first(where: { $0.id == id }) { return book }
    return downloadedShelfBooks.first(where: { $0.id == id })
  }

  func loadBookDetail(id: String) async -> ABSBook? {
    if let root = localDownloadRoot(for: id),
      let manifest = ABSDownloadManifest.load(from: root)
    {
      let fromManifest = ABSBook.fromDownloadManifest(manifest)
      if !isNetworkReachable {
        return fromManifest
      }
      guard let c = client else { return fromManifest }
      if let expanded = try? await c.item(id: id, expanded: true) {
        return expanded.mergingLocalDownloadPlayback(fromManifest)
      }
      return fromManifest
    }
    guard let c = client else { return cachedBookFallback(id: id) }
    do {
      return try await c.item(id: id, expanded: true)
    } catch {
      return cachedBookFallback(id: id)
    }
  }

  /// Hör-Sitzungen zu einem **Hörbuch** (ohne Podcast-Folgen). Nutzt `GET /api/me/item/listening-sessions/:id`, mit Fallback auf die globale Liste (ältere Server, leere Antwort, oder Sessions nur per `bookId`/`mediaId` zuordenbar).
  func loadBookListeningSessions(
    libraryItemId: String,
    bookMediaId: String? = nil,
    maxPages: Int = 20
  ) async -> [ABSListeningSession] {
    guard let c = client, isNetworkReachable else { return [] }
    let bid = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bid.isEmpty else { return [] }
    let mediaKey = bookMediaId
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }

    func collectPaged(_ load: (Int) async throws -> ABSListeningSessionsPayload) async throws
      -> [ABSListeningSession]
    {
      var collected: [ABSListeningSession] = []
      collected.reserveCapacity(32)
      var page = 0
      while page < maxPages {
        let res = try await load(page)
        collected.append(contentsOf: res.sessions)
        page += 1
        if page >= res.numPages || res.sessions.isEmpty { break }
      }
      return collected
    }

    func legacy() async -> [ABSListeningSession] {
      await loadBookListeningSessionsLegacyFiltered(
        client: c, libraryItemId: bid, bookMediaId: mediaKey, maxPages: maxPages)
    }

    do {
      let rows = try await collectPaged { p in
        try await c.listeningSessionsForLibraryItem(
          libraryItemId: bid, episodeId: nil, itemsPerPage: 100, page: p)
      }
      if !rows.isEmpty {
        return rows.sorted { $0.startedAt > $1.startedAt }
      }
      return await legacy()
    } catch {
      return await legacy()
    }
  }

  private func loadBookListeningSessionsLegacyFiltered(
    client: ABSAPIClient,
    libraryItemId bid: String,
    bookMediaId: String?,
    maxPages: Int
  ) async -> [ABSListeningSession] {
    var collected: [ABSListeningSession] = []
    collected.reserveCapacity(32)
    var page = 0
    let mid = bookMediaId
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }
    while page < maxPages {
      do {
        let res = try await client.listeningSessionsMe(itemsPerPage: 100, page: page)
        let filtered = res.sessions.filter { s in
          let ep = s.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          guard ep.isEmpty else { return false }
          if s.libraryItemId == bid { return true }
          if let mid, let raw = s.bookId {
            let b = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !b.isEmpty, b == mid { return true }
          }
          return false
        }
        collected.append(contentsOf: filtered)
        page += 1
        if page >= res.numPages { break }
      } catch {
        break
      }
    }
    return collected.sorted { $0.startedAt > $1.startedAt }
  }

  /// Hör-Sitzungen zu **einer Podcast-Folge** (`libraryItemId` = Sendung, `episodeId` = Folge).
  func loadPodcastEpisodeListeningSessions(
    _ episode: ABSPodcastEpisodeListItem,
    showMediaId: String? = nil,
    maxPages: Int = 20
  ) async -> [ABSListeningSession] {
    guard let c = client, isNetworkReachable else { return [] }
    let bid = episode.libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    let eid = episode.episodeId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bid.isEmpty, !eid.isEmpty else { return [] }
    let mediaKey = showMediaId
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }

    func collectPaged(_ load: (Int) async throws -> ABSListeningSessionsPayload) async throws
      -> [ABSListeningSession]
    {
      var collected: [ABSListeningSession] = []
      collected.reserveCapacity(16)
      var page = 0
      while page < maxPages {
        let res = try await load(page)
        collected.append(contentsOf: res.sessions)
        page += 1
        if page >= res.numPages || res.sessions.isEmpty { break }
      }
      return collected
    }

    func legacy() async -> [ABSListeningSession] {
      await loadPodcastEpisodeListeningSessionsLegacyFiltered(
        client: c,
        libraryItemId: bid,
        episodeId: eid,
        showMediaId: mediaKey,
        maxPages: maxPages)
    }

    do {
      let rows = try await collectPaged { p in
        try await c.listeningSessionsForLibraryItem(
          libraryItemId: bid, episodeId: eid, itemsPerPage: 100, page: p)
      }
      if !rows.isEmpty {
        return rows.sorted { $0.startedAt > $1.startedAt }
      }
      return await legacy()
    } catch {
      return await legacy()
    }
  }

  private func loadPodcastEpisodeListeningSessionsLegacyFiltered(
    client: ABSAPIClient,
    libraryItemId bid: String,
    episodeId eid: String,
    showMediaId: String?,
    maxPages: Int
  ) async -> [ABSListeningSession] {
    var collected: [ABSListeningSession] = []
    collected.reserveCapacity(16)
    var page = 0
    let mid = showMediaId
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }
    let eidLower = eid.lowercased()
    while page < maxPages {
      do {
        let res = try await client.listeningSessionsMe(itemsPerPage: 100, page: page)
        let filtered = res.sessions.filter { s in
          let sEp = s.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          guard !sEp.isEmpty, sEp.lowercased() == eidLower else { return false }
          if s.libraryItemId == bid { return true }
          if let mid, let raw = s.bookId {
            let b = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !b.isEmpty, b == mid { return true }
          }
          return false
        }
        collected.append(contentsOf: filtered)
        page += 1
        if page >= res.numPages { break }
      } catch {
        break
      }
    }
    return collected.sorted { $0.startedAt > $1.startedAt }
  }

  func loadPodcastEpisodeDetail(_ episode: ABSPodcastEpisodeListItem) async -> ABSPodcastEpisodeExpandedDetail? {
    guard let c = client, isNetworkReachable else {
      return ABSPodcastEpisodeExpandedDetail(
        episode: episode,
        subtitle: nil,
        episodeDescriptionHTML: nil,
        showDescriptionHTML: nil,
        pubDate: nil,
        showGenres: nil,
        showAuthors: []
      )
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
      return ABSPodcastEpisodeExpandedDetail(
        episode: episode,
        subtitle: subtitle,
        episodeDescriptionHTML: epDesc,
        showDescriptionHTML: showDesc,
        pubDate: pub,
        showGenres: genres,
        showAuthors: authors
      )
    } catch {
      return ABSPodcastEpisodeExpandedDetail(
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

  /// Öffnet in `MainRootView` das große Now-Playing-Sheet (Tab bleibt unverändert).
  func requestPresentNowPlayingSheet() {
    nowPlayingSheetPresentationCounter &+= 1
  }

  /// Sofort „Continue listening“ mit lokalem Fortschritt füllen; `loadStartDashboard()` gleicht später mit dem Server ab.
  private func applyOptimisticProgressOnly(_ p: ABSUserMediaProgress) {
    progressByItemId[p.progressLookupKey] = p
  }

  private func progressForOptimisticAudiobook(_ book: ABSBook, resumeAt: Double) -> ABSUserMediaProgress {
    let dur = max(book.media.duration ?? 0, resumeAt, 1)
    let progVal = dur > 0 ? min(1, max(0, resumeAt / dur)) : 0
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let prev = progressByItemId[book.id]?.lastUpdate ?? 0
    let lastUp = max(nowMs, prev + 1)
    return ABSUserMediaProgress(
      mediaProgressServerId: progressByItemId[book.id]?.mediaProgressServerId,
      libraryItemId: book.id,
      episodeId: nil,
      duration: dur,
      progress: progVal,
      currentTime: resumeAt,
      isFinished: false,
      lastUpdate: lastUp
    )
  }

  private func progressForOptimisticPodcastEpisode(
    _ episode: ABSPodcastEpisodeListItem,
    resumeAt: Double
  ) -> ABSUserMediaProgress {
    let dur = max(episode.duration, resumeAt, 1)
    let progVal = dur > 0 ? min(1, max(0, resumeAt / dur)) : 0
    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let prev = progressByItemId[episode.progressLookupKey]?.lastUpdate ?? 0
    let lastUp = max(nowMs, prev + 1)
    return ABSUserMediaProgress(
      mediaProgressServerId: progressByItemId[episode.progressLookupKey]?.mediaProgressServerId,
      libraryItemId: episode.libraryItemId,
      episodeId: episode.episodeId,
      duration: dur,
      progress: progVal,
      currentTime: resumeAt,
      isFinished: false,
      lastUpdate: lastUp
    )
  }

  private func mergeOptimisticAudiobookIntoContinueShelves(_ book: ABSBook) {
    let cat = "itemsInProgressFallback"
    let title = ABSStartShelfLocalization.displayTitle(category: cat, serverLabel: "")
    if startShelves.isEmpty {
      startShelves = [
        ABSStartShelfSection(
          id: "optimistic-continue-seed-book",
          category: cat,
          displayTitle: title,
          books: [book],
          podcastEpisodes: [],
          authors: []
        )
      ]
      return
    }
    guard let idx = startShelves.firstIndex(where: { isHomeContinueCategory($0.category) }) else { return }
    var newShelves = startShelves
    let shelf = newShelves[idx]
    var books = shelf.books.filter { $0.id != book.id }
    books.append(book)
    books.sort {
      (progressByItemId[$0.id]?.lastUpdate ?? 0) > (progressByItemId[$1.id]?.lastUpdate ?? 0)
    }
    newShelves[idx] = ABSStartShelfSection(
      id: shelf.id,
      category: shelf.category,
      displayTitle: shelf.displayTitle,
      books: books,
      podcastEpisodes: shelf.podcastEpisodes,
      authors: shelf.authors,
      series: shelf.series
    )
    startShelves = newShelves
  }

  private func mergeOptimisticPodcastEpisodeIntoContinueShelves(_ episode: ABSPodcastEpisodeListItem) {
    let cat = "itemsInProgressFallback"
    let title = ABSStartShelfLocalization.displayTitle(category: cat, serverLabel: "")
    if startShelves.isEmpty {
      startShelves = [
        ABSStartShelfSection(
          id: "optimistic-continue-seed-pod",
          category: cat,
          displayTitle: title,
          books: [],
          podcastEpisodes: [episode],
          authors: []
        )
      ]
      return
    }
    guard let idx = startShelves.firstIndex(where: { isHomeContinueCategory($0.category) }) else { return }
    var newShelves = startShelves
    let shelf = newShelves[idx]
    var eps = shelf.podcastEpisodes.filter { $0.progressLookupKey != episode.progressLookupKey }
    eps.append(episode)
    eps = dedupePodcastEpisodesForHomeContinueList(eps)
    newShelves[idx] = ABSStartShelfSection(
      id: shelf.id,
      category: shelf.category,
      displayTitle: shelf.displayTitle,
      books: shelf.books,
      podcastEpisodes: eps,
      authors: shelf.authors,
      series: shelf.series
    )
    startShelves = newShelves
  }

  private func bumpOptimisticContinueListeningForAudiobook(_ book: ABSBook, resumeAt: Double) {
    guard isStartCategoryEnabled("recentlyListened") else { return }
    if let libId = selectedBooksLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !libId.isEmpty {
      if let lid = book.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty, lid != libId {
        applyOptimisticProgressOnly(progressForOptimisticAudiobook(book, resumeAt: resumeAt))
        return
      }
    }
    let p = progressForOptimisticAudiobook(book, resumeAt: resumeAt)
    progressByItemId[p.progressLookupKey] = p
    mergeOptimisticAudiobookIntoContinueShelves(book)
    recomputeStartBooksUnion(from: startShelves)
    applyContinueListeningFinishedFilter()
  }

  private func bumpOptimisticContinueListeningForPodcastEpisode(
    _ episode: ABSPodcastEpisodeListItem,
    resumeAt: Double
  ) {
    guard isStartCategoryEnabled("recentlyListened") else { return }
    if let plid = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !plid.isEmpty {
      if let eLib = episode.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !eLib.isEmpty, eLib != plid {
        applyOptimisticProgressOnly(progressForOptimisticPodcastEpisode(episode, resumeAt: resumeAt))
        return
      }
    }
    let p = progressForOptimisticPodcastEpisode(episode, resumeAt: resumeAt)
    progressByItemId[p.progressLookupKey] = p
    mergeOptimisticPodcastEpisodeIntoContinueShelves(episode)
    recomputeStartBooksUnion(from: startShelves)
    applyContinueListeningFinishedFilter()
  }

  func play(book: ABSBook, resumeAtOverride: Double? = nil, autoPlay: Bool = true) async {
    guard let c = client else { return }
    errorMessage = nil
    let resume = resumeAtOverride ?? progressByItemId[book.id]?.currentTime ?? 0
    let local = localDownloadRoot(for: book.id)
    do {
      var resolved = book
      if let root = local, let manifest = ABSDownloadManifest.load(from: root) {
        let fromManifest = ABSBook.fromDownloadManifest(manifest)
        if isNetworkReachable, !book.media.metadata.hasRichMetadata,
          let expanded = try? await c.item(id: book.id, expanded: true)
        {
          resolved = expanded.mergingLocalDownloadPlayback(fromManifest)
        } else {
          resolved = book.mergingLocalDownloadPlayback(fromManifest)
        }
      } else if isNetworkReachable {
        let needsExpanded =
          local != nil
          || book.media.tracks == nil || book.media.tracks?.isEmpty == true
          || book.media.chapters == nil || book.media.chapters?.isEmpty == true
        if needsExpanded {
          do {
            resolved = try await c.item(id: book.id, expanded: true)
          } catch {}
        }
      }
      try await player.playBook(
        client: c, book: resolved, resumeAt: resume, localDownloadRoot: local, episodeId: nil,
        autoPlay: autoPlay)
      UserDefaults.standard.set(resolved.id, forKey: Keys.lastPlayedItemId)
      if autoPlay {
        bumpOptimisticContinueListeningForAudiobook(resolved, resumeAt: resume)
        requestPresentNowPlayingSheet()
        Task { await loadStartDashboard() }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func playPodcastEpisode(
    _ episode: ABSPodcastEpisodeListItem,
    autoPlay: Bool = true,
    resumeAtOverride: Double? = nil
  ) async {
    guard let c = client else { return }
    errorMessage = nil
    let resume =
      resumeAtOverride ?? progressByItemId[episode.progressLookupKey]?.currentTime ?? 0
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
        bumpOptimisticContinueListeningForPodcastEpisode(episode, resumeAt: resume)
        requestPresentNowPlayingSheet()
        Task { await loadStartDashboard() }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func loadListeningStats() async {
    listeningStatsLoading = true
    defer { listeningStatsLoading = false }

    if listeningStats == nil, let account = cacheAccountURL(),
      let data = LibraryDiskCache.loadListeningStatsResponse(account: account),
      let cached = try? ABSListeningStatsResponse.decodeAPIPayload(data)
    {
      listeningStats = cached
      listeningStatsFetchedAt = LibraryDiskCache.listeningStatsResponseModificationDate(account: account)
    }

    guard let c = client else { return }

    if !isNetworkReachable {
      return
    }

    errorMessage = nil
    do {
      let result = try await c.listeningStats()
      listeningStats = result.stats
      listeningStatsFetchedAt = Date()
      if let account = cacheAccountURL() {
        try? LibraryDiskCache.saveListeningStatsResponse(account: account, data: result.rawData)
      }
    } catch {
      if listeningStats == nil, let account = cacheAccountURL(),
        let data = LibraryDiskCache.loadListeningStatsResponse(account: account),
        let cached = try? ABSListeningStatsResponse.decodeAPIPayload(data)
      {
        listeningStats = cached
        listeningStatsFetchedAt = LibraryDiskCache.listeningStatsResponseModificationDate(account: account)
      }
      if listeningStats == nil {
        errorMessage = error.localizedDescription
      }
    }
  }

  /// Wiedergabe beenden. `idlePlaceholder: false` entfernt die Mini-Player-Leiste vollständig (z. B. nach „Fertig“).
  func dismissPlayer(idlePlaceholder: Bool = true) async {
    await player.closeSessionIfNeeded()
    player.tearDownPlayer()
    player.setMiniPlayerPlaceholder(idlePlaceholder)
  }

  /// Hörbuch bis zum Ende gehört: auf dem Server als fertig markieren und Player entladen.
  private func handleAudiobookPlaybackCompleted() async {
    guard let bookId = player.activeBook?.id,
      player.activePlaybackEpisodeId == nil
    else { return }
    if client != nil, isNetworkReachable {
      await markFinished(bookId: bookId)
    } else {
      if wasCurrentPlaybackForBook(bookId) {
        await dismissPlayer(idlePlaceholder: false)
      }
      removeLocalDownloadIfFinishedSetting(bookId: bookId)
      if UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == bookId {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      }
    }
  }

  private func wasCurrentPlaybackForBook(_ bookId: String) -> Bool {
    player.activeBook?.id == bookId && player.activePlaybackEpisodeId == nil
  }

  /// Lokale Dateien entfernen, wenn „Download nach Fertigstellung löschen“ aktiv ist.
  private func removeLocalDownloadIfFinishedSetting(bookId: String) {
    guard smartDownloadRemoveWhenFinished, downloadedItemIds.contains(bookId) else { return }
    removeLocalDownload(bookId: bookId)
    refreshDownloadedShelfFromManifests()
  }

  func markFinished(bookId: String) async {
    guard let c = client else { return }
    let wasCurrentPlayback = wasCurrentPlaybackForBook(bookId)
    do {
      try await c.markFinished(libraryItemId: bookId)
      let auth = try await c.authorize()
      applyAuthorizeUser(auth.user)
      searchBooks.removeAll { $0.id == bookId }
      podcastSearchBooks.removeAll { $0.id == bookId }
      await reloadLibrary(reset: true)
      await reloadPodcastLibrary(reset: true)
      if wasCurrentPlayback {
        await dismissPlayer(idlePlaceholder: false)
      }
      if UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == bookId {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      }
      removeLocalDownloadIfFinishedSetting(bookId: bookId)
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
      applyAuthorizeUser(auth.user)
      await reloadLibrary(reset: true)
      await reloadPodcastLibrary(reset: true)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Hörbuch: Media-Progress-Eintrag löschen (wie Web „Fortschritt verwerfen“ / `DELETE /api/me/progress/:id`).
  func discardBookProgress(bookId: String) async {
    guard let c = client else { return }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    guard let row = progressByItemId[bookId] else { return }
    let playing = player.activeBook?.id == bookId && player.activePlaybackEpisodeId == nil
    do {
      try await c.deleteMediaProgress(progressRowId: row.idForMediaProgressDeleteRequest)
      let auth = try await c.authorize()
      applyAuthorizeUser(auth.user)
      await reloadLibrary(reset: true)
      await reloadPodcastLibrary(reset: true)
      if playing {
        player.seek(global: 0)
      }
      await loadStartDashboard()
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
      applyAuthorizeUser(auth.user)
      removePodcastEpisodeFromLocalCatalogLists(episode)
      await reloadPodcastLibrary(reset: true)
      if wasPlaying {
        await dismissPlayer(idlePlaceholder: false)
      }
      removeLocalDownloadIfFinishedSetting(bookId: podcastEpisodeOfflineStorageId(episode))
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
      applyAuthorizeUser(auth.user)
      await reloadPodcastLibrary(reset: true)
      await loadStartDashboard()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Podcast-Folge: Media-Progress-Eintrag löschen (`DELETE /api/me/progress/:id` wie beim Hörbuch).
  func discardPodcastEpisodeProgress(_ episode: ABSPodcastEpisodeListItem) async {
    guard let c = client else { return }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    let key = episode.progressLookupKey
    guard let row = progressByItemId[key] else { return }
    let playing =
      player.activeBook?.id == episode.libraryItemId && player.activePlaybackEpisodeId == episode.episodeId
    do {
      try await c.deleteMediaProgress(progressRowId: row.idForMediaProgressDeleteRequest)
      let auth = try await c.authorize()
      applyAuthorizeUser(auth.user)
      await reloadPodcastLibrary(reset: true)
      if playing {
        player.seek(global: 0)
      }
      await loadStartDashboard()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func endDownloadBackgroundExecution() {
    guard downloadBackgroundTaskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(downloadBackgroundTaskId)
    downloadBackgroundTaskId = .invalid
  }

  private func beginDownloadBackgroundExecution() {
    endDownloadBackgroundExecution()
    downloadBackgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "de.letzgo.abstand.media-download") {
      [weak self] in
      Task { @MainActor [weak self] in
        self?.endDownloadBackgroundExecution()
      }
    }
  }

  /// Nach abgeschlossenem Download auf lokale Dateien umschalten, wenn noch derselbe Titel aus dem Stream läuft.
  private func applyLocalPlaybackIfDownloadMatchesCurrent(storageId: String) async {
    guard let c = client else { return }
    guard let folder = try? downloads.downloadFolder(for: storageId),
      let manifest = ABSDownloadManifest.load(from: folder)
    else { return }
    let stub = ABSBook.fromDownloadManifest(manifest)
    guard !player.isPlaybackFromOfflineDownload else { return }
    guard player.activeBook?.id == stub.id else { return }
    let curEp = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let manEp = manifest.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard curEp == manEp else { return }
    guard PlaybackController.allLocalTracksPresentForOfflinePlayback(root: folder, book: stub) else { return }
    let resume = player.globalPosition
    let auto = player.isPlaying
    let ep: String? = manEp.isEmpty ? nil : manEp
    do {
      try await player.playBook(
        client: c,
        book: stub,
        resumeAt: resume,
        localDownloadRoot: folder,
        episodeId: ep,
        autoPlay: auto
      )
    } catch {}
  }

  /// Ordnername unter `Documents/Downloads` für eine Podcast-Folge (nicht `libraryItemId` allein).
  func podcastEpisodeOfflineStorageId(_ episode: ABSPodcastEpisodeListItem) -> String {
    episode.progressLookupKey.replacingOccurrences(of: "/", with: "_")
  }

  /// Lokaler Download-Ordner für den aktuell laufenden Titel (`nil` ohne aktives Medium).
  func currentPlaybackOfflineStorageId() -> String? {
    offlineStorageIdForActivePlayback()
  }

  func startDownloadForActivePlayback() {
    guard client != nil, let book = player.activeBook else { return }
    let epRaw = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if epRaw.isEmpty {
      startDownload(book: book)
      return
    }
    guard let episode = podcastEpisodeForSmartDownloadFromActivePlayback() else { return }
    startDownloadPodcastEpisode(episode)
  }

  func removeLocalDownloadForActivePlayback() {
    guard let id = offlineStorageIdForActivePlayback() else { return }
    removeLocalDownload(bookId: id)
    refreshDownloadedShelfFromManifests()
  }

  func startDownloadPodcastEpisode(_ episode: ABSPodcastEpisodeListItem) {
    guard let c = client else { return }
    let stub = episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
    let sid = podcastEpisodeOfflineStorageId(episode)
    beginDownloadBackgroundExecution()
    let reuse = player.playSessionIdForReuseWhenDownloadingSameItem(
      libraryItemId: stub.id,
      episodeId: episode.episodeId
    )
    downloads.startDownload(
      client: c,
      book: stub,
      episodeId: episode.episodeId,
      storageItemId: sid,
      reusePlaySessionId: reuse
    ) { [weak self] ok in
      Task { @MainActor [weak self] in
        self?.endDownloadBackgroundExecution()
        guard let model = self, ok else { return }
        model.downloadedItemIds.insert(sid)
        model.persistDownloads()
        await model.applyLocalPlaybackIfDownloadMatchesCurrent(storageId: sid)
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
        await dismissPlayer(idlePlaceholder: false)
      }
      if UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == bookId {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      }
      await refreshProgressFromServer()
      await loadStartDashboard()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func startDownload(book: ABSBook) {
    guard let c = client else { return }
    beginDownloadBackgroundExecution()
    let reuse = player.playSessionIdForReuseWhenDownloadingSameItem(
      libraryItemId: book.id,
      episodeId: nil
    )
    Task { @MainActor in
      var bookToDownload = book
      if (book.media.chapters ?? []).isEmpty, isNetworkReachable,
        let expanded = try? await c.item(id: book.id, expanded: true)
      {
        bookToDownload = expanded
      }
      downloads.startDownload(client: c, book: bookToDownload, reusePlaySessionId: reuse) { [weak self] ok in
      Task { @MainActor [weak self] in
        self?.endDownloadBackgroundExecution()
        guard let model = self, ok else { return }
        model.downloadedItemIds.insert(book.id)
        model.persistDownloads()
        await model.applyLocalPlaybackIfDownloadMatchesCurrent(storageId: book.id)
      }
      }
    }
  }

  func removeLocalDownload(bookId: String) {
    if downloads.activeItemId == bookId {
      downloads.cancel()
    }
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

  /// Autorenfoto (`GET /api/authors/:id/image`).
  func authorImageURL(authorId: String) -> URL? {
    guard let url = ABSAPIClient.normalizeServerURL(serverURL) else { return nil }
    return url.appendingPathComponent("api/authors/\(authorId)/image")
  }

  /// Erstes Hörbuch in einer Serie/Sammlung für das Cover.
  func browseRepresentativeBookItemId(from books: [ABSBook]?) -> String? {
    guard let first = books?.first(where: { !$0.id.isEmpty }) else { return nil }
    return first.id
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
    ContinueHeroTintCache.clearAll(account: account)
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

  /// Nach Offline-Modus: Session-Sync, dann alle lokalen `progressByItemId`-Einträge per PATCH; zuletzt `/authorize` zum Abgleich.
  /// - Returns: `true`, wenn Netzwerk und Client vorhanden waren und der Ablauf durchlief (Patches können trotzdem einzeln fehlschlagen).
  @discardableResult
  func syncOfflineProgressToServer() async -> Bool {
    guard let c = client, isNetworkReachable else { return false }
    await player.flushPendingPlaySessionSync()
    for p in progressByItemId.values {
      let dur = max(p.duration, 0)
      let pos = max(0, p.currentTime)
      let prog: Double = {
        if dur > 0 { return min(1, max(0, pos / dur)) }
        return min(1, max(0, p.progress))
      }()
      do {
        try await c.patchProgress(
          libraryItemId: p.libraryItemId,
          episodeId: p.episodeId,
          patch: ABSProgressPatch(
            currentTime: pos,
            duration: dur > 0 ? dur : nil,
            progress: prog,
            isFinished: p.isFinished
          )
        )
      } catch {}
    }
    await refreshProgressFromServer()
    return true
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
    if let marks = LibraryDiskCache.loadBookmarks(account: account, decoder: dec) {
      applyUserBookmarks(marks, persistToDisk: false)
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
        injectEbookContinueReadingShelfIfNeeded()
        return
      }
    }
    applyLocalContinueListeningFromCachedBooks()
    injectEbookContinueReadingShelfIfNeeded()
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
    let ascending = podcastCatalogSortField == .random ? true : !podcastCatalogSortDescending
    let sortKey = podcastCatalogSortField.apiSortParameter
    if let account = cacheAccountURL(),
      let rows = LibraryDiskCache.loadPodcastShows(
        account: account, libraryId: libId, sortField: sortKey, ascending: ascending,
        decoder: ABSJSON.decoder())
    {
      podcastShows = rows
    }
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

  func applyAuthorizeUser(_ user: ABSUser, persistToDisk: Bool = true) {
    applyUserProgress(user.mediaProgress, persistToDisk: persistToDisk)
    applyUserBookmarks(user.bookmarks, persistToDisk: persistToDisk)
  }

  func bookmarks(for libraryItemId: String) -> [ABSAudioBookmark] {
    bookmarks
      .filter { $0.libraryItemId == libraryItemId }
      .sorted { $0.time < $1.time }
  }

  func bookHasSupplementalEpub(_ book: ABSBook) -> Bool {
    book.hasSupplementalEpub
  }

  /// EPUB oder PDF öffnen: lokaler Cache zuerst, sonst Download vom Server.
  func openAttachedEbook(for book: ABSBook) async {
    isPreparingEbook = true
    errorMessage = nil
    defer { isPreparingEbook = false }

    if let account = cacheAccountURL(),
      let cached = EbookLocalStore.cachedEbookIfPresent(account: account, libraryItemId: book.id)
    {
      let meta = EbookLocalStore.loadDownloadMeta(
        account: account, libraryItemId: book.id, format: cached.format)
      let title = meta?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
      EbookLocalStore.rememberKnownFormat(cached.format, libraryItemId: book.id)
      ebookReaderSession = EbookReaderPresentation(
        title: (title?.isEmpty == false ? title! : book.displayTitle),
        libraryItemId: book.id,
        localFileURL: cached.url,
        format: cached.format
      )
      return
    }

    guard isNetworkReachable, let c = client, let account = cacheAccountURL() else {
      errorMessage =
        "Keine Verbindung zum Server. Öffne das eBook einmal online, damit es lokal zwischengespeichert wird."
      return
    }

    do {
      var resolved = book
      if resolved.readableAttachedEbook == nil {
        if let expanded = await loadBookDetail(id: book.id) {
          resolved = expanded
        }
      }
      guard let (ino, format) = resolved.readableAttachedEbook else {
        errorMessage = "Für dieses Hörbuch ist keine eBook- oder PDF-Datei verfügbar."
        return
      }
      EbookLocalStore.rememberKnownFormat(format, libraryItemId: resolved.id)
      rememberEbookFormatsFromCatalog([resolved])
      try EbookLocalStore.ensureAccountDirs(account: account)
      let fileURL = EbookLocalStore.ebookFileURL(
        account: account, libraryItemId: resolved.id, format: format)
      if !EbookLocalStore.hasCachedEbook(account: account, libraryItemId: resolved.id, format: format) {
        _ = try await c.downloadEbookFile(
          itemId: resolved.id,
          ino: ino,
          format: format,
          to: fileURL.deletingPathExtension()
        )
        try EbookLocalStore.saveDownloadMeta(
          account: account,
          meta: EbookDownloadMeta(
            libraryItemId: resolved.id,
            ino: ino,
            format: format,
            title: resolved.displayTitle
          )
        )
      }
      ebookReaderSession = EbookReaderPresentation(
        title: resolved.displayTitle,
        libraryItemId: resolved.id,
        localFileURL: fileURL,
        format: format
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func defaultBookmarkTitle(atSeconds time: Int) -> String {
    let t = max(0, time)
    if t >= 3600 { return formatPlaybackDurationShortHuman(Double(t)) }
    return formatPlaybackTime(Double(t))
  }

  /// Lesezeichen anlegen (nur Hörbücher, nicht Podcast-Folgen).
  @discardableResult
  func createBookmark(libraryItemId: String, time: Int, title: String) async -> Bool {
    guard let c = client, isNetworkReachable else {
      errorMessage = "Bookmarks require a server connection."
      return false
    }
    let lid = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lid.isEmpty else { return false }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalTitle = trimmedTitle.isEmpty ? defaultBookmarkTitle(atSeconds: time) : trimmedTitle
    errorMessage = nil
    do {
      let created = try await c.createBookmark(libraryItemId: lid, time: time, title: finalTitle)
      upsertBookmark(created)
      persistBookmarksToDisk()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func deleteBookmark(_ bookmark: ABSAudioBookmark) async {
    guard let c = client, isNetworkReachable else {
      errorMessage = "Bookmarks require a server connection."
      return
    }
    errorMessage = nil
    do {
      try await c.deleteBookmark(libraryItemId: bookmark.libraryItemId, time: bookmark.time)
      bookmarks.removeAll { $0.libraryItemId == bookmark.libraryItemId && $0.time == bookmark.time }
      persistBookmarksToDisk()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Zur Lesezeichen-Position springen (gleiches Hörbuch: nur Seek, sonst laden und abspielen).
  func jumpToBookmark(_ bookmark: ABSAudioBookmark, autoPlay: Bool = true) async {
    let lid = bookmark.libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lid.isEmpty else { return }
    let at = Double(bookmark.time)
    if player.activeBook?.id == lid,
      (player.activePlaybackEpisodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      player.seek(global: at)
      if autoPlay { player.play() }
      return
    }
    guard let c = client else { return }
    errorMessage = nil
    do {
      let detail = try await c.item(id: lid, expanded: true)
      await play(book: detail, resumeAtOverride: at, autoPlay: autoPlay)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func upsertBookmark(_ bookmark: ABSAudioBookmark) {
    bookmarks.removeAll { $0.libraryItemId == bookmark.libraryItemId && $0.time == bookmark.time }
    bookmarks.append(bookmark)
    bookmarks.sort { a, b in
      if a.libraryItemId != b.libraryItemId { return a.libraryItemId < b.libraryItemId }
      return a.time < b.time
    }
  }

  private func persistBookmarksToDisk() {
    guard let account = cacheAccountURL() else { return }
    try? LibraryDiskCache.saveBookmarks(account: account, list: bookmarks)
  }

  private func applyUserBookmarks(_ list: [ABSAudioBookmark]?, persistToDisk: Bool = true) {
    bookmarks = list ?? []
    guard persistToDisk, let account = cacheAccountURL() else { return }
    try? LibraryDiskCache.saveBookmarks(account: account, list: bookmarks)
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

  /// Wie `applyLocalContinueListeningFromCachedBooks`: kein Mini-Player für bloße Klicks ohne echte Position.
  private static let continueListeningMinPositionSeconds: Double = 2

  /// Fortschritt, der auf Home in „Continue listening“ steht — nicht jeder offene `mediaProgress`-Eintrag.
  private func preferredContinueListeningResumeProgress() -> ABSUserMediaProgress? {
    var shelfCandidates: [ABSUserMediaProgress] = []
    for shelf in startShelves where isHomeContinueCategory(shelf.category) {
      for book in shelf.books {
        guard book.isPlayableAudiobook,
          let p = progressByItemId[book.id],
          !p.isFinished,
          (p.episodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { continue }
        shelfCandidates.append(p)
      }
      for episode in shelf.podcastEpisodes {
        guard let p = progressByItemId[episode.progressLookupKey], !p.isFinished else { continue }
        shelfCandidates.append(p)
      }
    }
    if let best = shelfCandidates.max(by: resumeProgressOrderedBefore) { return best }

    var localCandidates: [ABSUserMediaProgress] = []
    localCandidates.append(contentsOf: localContinueAudiobookResumeProgresses())
    for episode in localContinuePodcastEpisodeCandidates() {
      if let p = progressByItemId[episode.progressLookupKey] {
        localCandidates.append(p)
      }
    }
    return localCandidates.max(by: resumeProgressOrderedBefore)
  }

  private func localContinueAudiobookResumeProgresses() -> [ABSUserMediaProgress] {
    guard selectedBooksLibrary != nil else { return [] }
    var seen = Set<String>()
    var out: [ABSUserMediaProgress] = []
    for b in books + startBooks {
      guard !seen.contains(b.id) else { continue }
      seen.insert(b.id)
      guard b.isPlayableAudiobook,
        let p = progressByItemId[b.id],
        !p.isFinished,
        p.currentTime > Self.continueListeningMinPositionSeconds,
        (p.episodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { continue }
      out.append(p)
    }
    return out
  }

  private func effectiveResumeProgress() -> ABSUserMediaProgress? {
    preferredContinueListeningResumeProgress()
  }

  private func syncLastPlayedPreferenceWithServerProgress() {
    guard let p = preferredContinueListeningResumeProgress() else {
      UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      return
    }
    UserDefaults.standard.set(p.libraryItemId, forKey: Keys.lastPlayedItemId)
  }

  /// SwiftUI `.refreshable` bricht die Struktur-Task oft ab, bevor Netzwerk fertig ist.
  @MainActor
  private func performPullToRefresh(_ work: @MainActor @escaping () async -> Void) async {
    await Task.detached(priority: .userInitiated) { @MainActor in
      await work()
    }.value
  }

  /// Abgebrochene/debounced Requests sollen keinen Fehlerdialog auslösen.
  private static func isBenignCancellationError(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
    return false
  }

  /// Normalisierte Feed-URL für Abgleich Verzeichnis ↔ Bibliothek.
  private static func normalizedPodcastFeedURL(_ raw: String?) -> String? {
    var s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if let url = URL(string: s), let host = url.host?.lowercased() {
      var path = url.path
      while path.hasSuffix("/") { path.removeLast() }
      let port =
        url.port.map { ":\($0)" } ?? ""
      s = "\(url.scheme?.lowercased() ?? "https")://\(host)\(port)\(path)"
      if let q = url.query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
        s += "?\(q)"
      }
    } else {
      s = s.lowercased()
      while s.hasSuffix("/") { s.removeLast() }
    }
    return s
  }

  /// Sendung aus Apple-Podcasts-Suche ist bereits in der gewählten Podcast-Bibliothek.
  func podcastDirectoryHitIsInLibrary(_ hit: ABSPodcastDirectorySearchHit) -> Bool {
    guard let hitFeed = Self.normalizedPodcastFeedURL(hit.feedUrl) else { return false }
    return podcastShows.contains { show in
      Self.normalizedPodcastFeedURL(show.media.metadata.feedUrl) == hitFeed
    }
  }

  func schedulePodcastDirectorySearch(term: String) {
    podcastDirectorySearchTask?.cancel()
    let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.count < 2 {
      podcastDirectorySearchGeneration += 1
      podcastDirectorySearchHits = []
      podcastDirectorySearchLoading = false
      return
    }
    podcastDirectorySearchGeneration += 1
    let generation = podcastDirectorySearchGeneration
    podcastDirectorySearchTask = Task { @MainActor in
      podcastDirectorySearchLoading = true
      try? await Task.sleep(nanoseconds: 420_000_000)
      guard !Task.isCancelled else {
        if generation == podcastDirectorySearchGeneration {
          podcastDirectorySearchLoading = false
        }
        return
      }
      await performPodcastDirectorySearch(term: t, generation: generation)
    }
  }

  func clearPodcastDirectorySearch() {
    podcastDirectorySearchTask?.cancel()
    podcastDirectorySearchGeneration += 1
    podcastDirectorySearchHits = []
    podcastDirectorySearchLoading = false
  }

  private func performPodcastDirectorySearch(term: String, generation: Int) async {
    defer {
      if generation == podcastDirectorySearchGeneration {
        podcastDirectorySearchLoading = false
      }
    }
    guard generation == podcastDirectorySearchGeneration else { return }
    guard let c = client, isNetworkReachable else {
      if generation == podcastDirectorySearchGeneration {
        podcastDirectorySearchHits = []
      }
      return
    }
    let region = Locale.current.region?.identifier.lowercased() ?? "us"
    do {
      let hits = try await c.searchPodcastsDirectory(term: term, country: region)
      guard generation == podcastDirectorySearchGeneration else { return }
      podcastDirectorySearchHits = hits
    } catch {
      guard generation == podcastDirectorySearchGeneration else { return }
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      errorMessage = error.localizedDescription
      podcastDirectorySearchHits = []
    }
  }

  /// Abonniert einen Podcast aus der Verzeichnissuche (`POST /api/podcasts`). Erfordert typischerweise Admin-Rechte auf dem Server.
  func subscribeToPodcastDirectoryHit(_ hit: ABSPodcastDirectorySearchHit) async -> Bool {
    guard let c = client, let lib = selectedPodcastLibrary, isNetworkReachable else {
      errorMessage = "No network connection."
      return false
    }
    let feed = (hit.feedUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !feed.isEmpty else {
      errorMessage = "Missing RSS feed URL for this result."
      return false
    }
    podcastSubscribeInProgressDirectoryHitId = hit.id
    defer { podcastSubscribeInProgressDirectoryHitId = nil }
    do {
      let folders = try await c.libraryFolders(libraryId: lib.id)
      guard let first = folders.first else {
        errorMessage = "No library folders found for this podcast library."
        return false
      }
      let body = try buildPodcastSubscribeRequestBody(
        hit: hit, folderId: first.id, libraryId: lib.id, folderFullPath: first.fullPath)
      let newId = try await c.createPodcastInLibrary(jsonBody: body)
      await refreshProgressFromServer()
      await reloadPodcastShowsCatalog()
      await selectPodcastShowFilter(newId)
      await loadStartDashboard()
      errorMessage = nil
      clearPodcastDirectorySearch()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  /// Entfernt eine Podcast-Sendung von der Bibliothek (`DELETE /api/items/:id`). Erfordert Lösch-Rechte auf dem Server.
  func removePodcastShowFromLibrary(showLibraryItemId: String) async {
    guard let c = client else { return }
    guard isNetworkReachable else {
      errorMessage = "Keine Netzwerkverbindung."
      return
    }
    let sid = showLibraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return }

    podcastShowEpisodesLoadSerial &+= 1
    let playingThisShow = player.activeBook?.id == sid

    var offlineStorageIds = Set<String>()
    if downloadedItemIds.contains(sid) { offlineStorageIds.insert(sid) }
    for ep in podcastEpisodes where ep.libraryItemId == sid {
      offlineStorageIds.insert(podcastEpisodeOfflineStorageId(ep))
    }
    for ep in podcastFilteredEpisodes where ep.libraryItemId == sid {
      offlineStorageIds.insert(podcastEpisodeOfflineStorageId(ep))
    }
    for dlId in downloadedItemIds {
      guard let root = try? downloads.downloadFolder(for: dlId),
        let manifest = ABSDownloadManifest.load(from: root),
        manifest.libraryItemId == sid
      else { continue }
      offlineStorageIds.insert(dlId)
    }

    do {
      try await c.deleteLibraryItem(id: sid)
    } catch {
      errorMessage = error.localizedDescription
      return
    }

    errorMessage = nil
    podcastRssFeedLoadInProgressShowIds.remove(sid)

    if podcastRssFeedPreviewForShowId == sid {
      podcastRssFeedPreviewEpisodes = []
      podcastRssFeedPreviewForShowId = nil
      podcastRssDraftDownloadCompletedIds = []
      clearPodcastAutoDownloadSettingsDraft()
    }

    if playingThisShow {
      await dismissPlayer(idlePlaceholder: false)
    }
    if UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == sid {
      UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
    }

    for oid in offlineStorageIds {
      downloads.deleteDownload(itemId: oid)
      downloadedItemIds.remove(oid)
    }
    persistDownloads()
    refreshDownloadedShelfFromManifests()

    podcastShows.removeAll { $0.id == sid }
    podcastEpisodes.removeAll { $0.libraryItemId == sid }
    podcastFilteredEpisodes.removeAll { $0.libraryItemId == sid }
    podcastSearchBooks.removeAll { $0.id == sid }
    searchBooks.removeAll { $0.id == sid }
    startBooks.removeAll { $0.id == sid }
    books.removeAll { $0.id == sid }

    let wasSelected = podcastSelectedShowId == sid
    if wasSelected {
      await selectPodcastShowFilter(nil)
    } else {
      await reloadPodcastLibrary(reset: true)
    }
    await reloadPodcastShowsCatalog()
    await refreshProgressFromServer()
    await loadStartDashboard()
  }

  private func buildPodcastSubscribeRequestBody(
    hit: ABSPodcastDirectorySearchHit,
    folderId: String,
    libraryId: String,
    folderFullPath: String
  ) throws -> Data {
    let rawTitle = hit.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = rawTitle.isEmpty ? "Podcast" : rawTitle
    let segment = title.absSanitizedLibraryPathSegment()
    let folder = folderFullPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let path: String =
      folder.hasSuffix("/") ? folder + segment : folder + "/" + segment
    let feed = (hit.feedUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let genres = hit.genres ?? []
    let desc = (hit.descriptionPlain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let cover = (hit.cover ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let page = (hit.pageUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let artist = (hit.artistName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let release = (hit.releaseDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let itunesId = hit.id.trimmingCharacters(in: .whitespacesAndNewlines)
    let artistId = (hit.artistId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    let metadata: [String: Any] = [
      "title": title,
      "author": artist,
      "description": desc,
      "releaseDate": release,
      "genres": genres,
      "feedUrl": feed,
      "imageUrl": cover,
      "itunesPageUrl": page,
      "itunesId": itunesId,
      "itunesArtistId": artistId,
      "language": "",
      "explicit": hit.explicit ?? false,
      "type": "episodic",
    ]
    let media: [String: Any] = [
      "metadata": metadata,
      "autoDownloadEpisodes": true,
      "autoDownloadSchedule": PodcastAutoDownloadInterval.default.cronExpression,
    ]
    let rootObj: [String: Any] = [
      "path": path,
      "folderId": folderId,
      "libraryId": libraryId,
      "media": media,
    ]
    return try JSONSerialization.data(withJSONObject: rootObj)
  }

  private func bookDuration(_ b: ABSBook) -> Double {
    b.media.duration ?? 0
  }
}

extension AppModel {
  /// SwiftUI-`Picker`/`tag` für „keine Bibliothek“ (persistiert als `Keys.librarySelectionNone`).
  static var libraryPickerNoneTag: String { Keys.librarySelectionNone }
}
