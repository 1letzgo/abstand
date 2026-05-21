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
  /// Kumulierte Hörsekunden ohne Play-Session (lokale Downloads), später per Session-Flush (Absorb).
  static let pendingOfflineListeningSeconds = "abstand_pending_offline_listening_seconds"
  static let browseAuthorsSortField = "abstand_browse_authors_sort_field"
  static let browseAuthorsSortDescending = "abstand_browse_authors_sort_desc"
  static let browseNarratorsSortField = "abstand_browse_narrators_sort_field"
  static let browseNarratorsSortDescending = "abstand_browse_narrators_sort_desc"
  static let browseSeriesSortField = "abstand_browse_series_sort_field"
  static let browseSeriesSortDescending = "abstand_browse_series_sort_desc"
  static let browseCollectionsSortField = "abstand_browse_collections_sort_field"
  static let browseCollectionsSortDescending = "abstand_browse_collections_sort_desc"
  /// Tab „eBooks“ in der Tab-Leiste (neben Audio).
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

/// Unterbereiche im Library-Tab (horizontale Leiste wie Podcast-„Shows“).
enum BooksBrowseSection: String, CaseIterable, Identifiable, Hashable {
  case books = "Books"
  case series = "Series"
  case collections = "Collections"
  case author = "Author"
  case narrators = "Narrators"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .books: return "books.vertical"
    case .series: return "rectangle.stack"
    case .collections: return "folder"
    case .author: return "person.text.rectangle"
    case .narrators: return "waveform"
    }
  }
}

/// Schnellfilter im Bücher-Katalog (Toolbar neben Sort).
enum LibraryCatalogQuickFilter: String, CaseIterable, Identifiable, Hashable {
  case inProgress
  case finished
  case notStarted
  case downloaded
  case ebook

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .inProgress: return "In progress"
    case .finished: return "Finished"
    case .notStarted: return "Not started"
    case .downloaded: return "Downloaded"
    case .ebook: return "eBook"
    }
  }

  var menuSystemImage: String {
    switch self {
    case .inProgress: return "play.circle"
    case .finished: return "checkmark.circle"
    case .notStarted: return "circle"
    case .downloaded: return "arrow.down.circle"
    case .ebook: return "book.closed.fill"
    }
  }

  var isLocalDownloadedOnly: Bool { self == .downloaded }

  var serverFilterKey: String? {
    func key(group: String, value: String) -> String {
      let b64 = Data(value.utf8).base64EncodedString()
      return "\(group).\(b64)"
    }
    switch self {
    case .downloaded: return nil
    case .inProgress: return key(group: "progress", value: "in-progress")
    case .finished: return key(group: "progress", value: "finished")
    case .notStarted: return key(group: "progress", value: "not-started")
    case .ebook: return key(group: "ebooks", value: "supplementary")
    }
  }

  var summaryPrefix: String {
    switch self {
    case .inProgress, .finished, .notStarted: return "Progress"
    case .downloaded: return "Downloaded"
    case .ebook: return "eBook"
    }
  }

  var summaryDetail: String? {
    switch self {
    case .inProgress: return "In progress"
    case .finished: return "Finished"
    case .notStarted: return "Not started"
    case .downloaded: return nil
    case .ebook: return "Has supplementary eBook"
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
  @Published private(set) var podcastChartsHits: [ABSPodcastDirectorySearchHit] = []
  @Published private(set) var podcastChartsLoading = false
  @Published private(set) var podcastSubscribeInProgressDirectoryHitId: String?
  /// `nil` = „New“-Ansicht (recent-Feed); gesetzt = nur diese Sendung (`podcastFilteredEpisodes`).
  @Published var podcastSelectedShowId: String?
  @Published var podcastFilteredEpisodes: [ABSPodcastEpisodeListItem] = []
  @Published private(set) var isLoadingPodcastShowEpisodes = false
  @Published private(set) var podcastRssFeedLoadInProgressShowIds: Set<String> = []
  /// Aus `POST /api/podcasts/feed` — aktive Vorschau (Podcast-Tab RSS-Toggle).
  @Published private(set) var podcastRssFeedPreviewEpisodes: [ABSPodcastRssFeedEpisodeDraft] = []
  @Published private(set) var podcastRssFeedPreviewForShowId: String?
  /// Pro Sendung gecachte RSS-Vorschau (wie Absorb: einmal laden, Tabs wechseln ohne Neu-Fetch).
  @Published private(set) var podcastRssFeedCacheByShowId: [String: [ABSPodcastRssFeedEpisodeDraft]] = [:]
  /// Inline-Hinweis statt globalem Alert, wenn kein RSS (z. B. Ordner-Import).
  @Published private(set) var podcastRssFeedUnavailableByShowId: [String: String] = [:]
  @Published private(set) var podcastRssEpisodeDownloadInProgressDraftIds: Set<UUID> = []
  /// Nach erfolgreichem `download-episodes`: Download-Button ausblenden, Karte bleibt in der RSS-Liste.
  @Published private(set) var podcastRssDraftDownloadCompletedIds: Set<UUID> = []
  @Published private(set) var podcastRssDraftCompletedIdsByShowId: [String: Set<UUID>] = [:]
  @Published var podcastAutoDownloadEnabled = false
  @Published var podcastAutoDownloadInterval = PodcastAutoDownloadInterval.default
  @Published var podcastMaxEpisodesToKeep = 0
  @Published var podcastMaxNewEpisodesToDownload = 3
  @Published private(set) var podcastAutoDownloadSettingsLoading = false
  @Published private(set) var podcastAutoDownloadSettingsSaving = false
  @Published private(set) var podcastAutoDownloadSettingsShowId: String?
  @Published private(set) var podcastCheckNewInProgressShowId: String?
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
  @Published var libraryCatalogQuickFilter: LibraryCatalogQuickFilter?
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
  @Published private(set) var isServerAdmin = false
  @Published private(set) var isServerRoot = false
  @Published private(set) var serverSettings: ABSServerSettings?
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
  /// Nur Home mit Regal „Heruntergeladen“ (persistiert). Fortschritt beim Deaktivieren an den Server senden.
  @Published var offlineHomeMode: Bool = AppModel.initialOfflineHomeMode() {
    didSet {
      UserDefaults.standard.set(offlineHomeMode, forKey: Keys.offlineHomeMode)
      guard !suppressOfflineModeSideEffects else { return }
      guard oldValue != offlineHomeMode else { return }
      if offlineHomeMode {
        offlineHomeModeAuto = false
        mainTab = .start
        Task {
          await prepareForOfflineHomeMode()
          await loadStartDashboard()
        }
      } else {
        offlineHomeModeAuto = false
        Task {
          await finishLeavingOfflineHomeMode()
        }
      }
    }
  }
  /// Nach fehlgeschlagenem Start-`bootstrap`: gleiche Oberfläche wie manueller Offline-Modus, ohne UserDefaults.
  @Published private(set) var offlineHomeModeAuto = false

  /// Home nur mit „Heruntergeladen“ (manuell oder automatisch nach Start ohne Server).
  var offlineHomeUIActive: Bool { offlineHomeMode || offlineHomeModeAuto }

  /// Kein `/authorize`, PATCH, Katalog-Reload o. Ä. — nur lokaler Cache und Downloads.
  var mayUseServerNetwork: Bool { !offlineHomeUIActive }

  enum ServerConnectionIndicatorState: Equatable {
    case online
    case connecting
    case offline
  }

  @Published private(set) var isServerReachable = false
  @Published private(set) var isServerConnectionProbeInProgress = false

  var serverConnectionIndicatorState: ServerConnectionIndicatorState {
    if offlineHomeUIActive || !isNetworkReachable { return .offline }
    if isServerConnectionProbeInProgress { return .connecting }
    if isRestoringLaunchPlayback, client == nil { return .connecting }
    if isServerReachable, client != nil { return .online }
    return .offline
  }

  @Published var showOfflineModeConfirmation = false

  /// Offline-Modus nur nach Bestätigung (Ampel / Einstellungen).
  func requestEnterOfflineHomeMode() {
    guard !offlineHomeUIActive else { return }
    showOfflineModeConfirmation = true
  }

  func confirmEnterOfflineHomeMode() {
    showOfflineModeConfirmation = false
    guard !offlineHomeMode else { return }
    offlineHomeMode = true
  }

  func cancelEnterOfflineHomeModeConfirmation() {
    showOfflineModeConfirmation = false
  }

  func clampMainTabForOfflineHomeIfNeeded() {
    if offlineHomeUIActive, mainTab != .start {
      mainTab = .start
    }
  }

  /// Home-Toolbar: Ampel — online → Offline-Modus; offline → wieder verbinden.
  func homeToolbarServerConnectionTapped() {
    if offlineHomeUIActive {
      exitOfflineHomeUI()
      return
    }
    if serverConnectionIndicatorState == .online {
      requestEnterOfflineHomeMode()
      return
    }
    Task { await probeServerConnection() }
  }

  func probeServerConnectionIfNeeded() async {
    guard mayUseServerNetwork, isNetworkReachable else { return }
    if isServerReachable, client != nil { return }
    await probeServerConnection()
  }

  /// Kurzer `/authorize`, ob der Audiobookshelf-Server erreichbar ist.
  func probeServerConnection() async {
    guard mayUseServerNetwork else {
      isServerReachable = false
      return
    }
    guard isNetworkReachable,
      ABSAPIClient.normalizeServerURL(serverURL) != nil,
      !token.isEmpty
    else {
      isServerReachable = false
      return
    }
    isServerConnectionProbeInProgress = true
    defer { isServerConnectionProbeInProgress = false }
    restoreServerClientIfNeeded()
    guard let c = client else {
      isServerReachable = false
      return
    }
    do {
      let auth = try await c.authorize()
      applyAuthorizeSession(auth)
      let t = auth.user.token
      if !t.isEmpty {
        token = t
        UserDefaults.standard.set(t, forKey: Keys.token)
        await c.setToken(t)
      }
      isServerReachable = true
    } catch {
      isServerReachable = false
    }
  }

  /// Offline-Home beenden (Navbar auf Home); synchronisiert Fortschritt, wenn manuell aktiv war.
  func exitOfflineHomeUI() {
    if offlineHomeMode {
      offlineHomeMode = false
    } else if offlineHomeModeAuto {
      offlineHomeModeAuto = false
      Task { await finishLeavingOfflineHomeMode() }
    }
  }

  /// Nach Offline-Modus: Client, Fortschritt, Bibliotheken für Settings, Home.
  private func finishLeavingOfflineHomeMode() async {
    restoreServerClientIfNeeded()
    ensureLocalProgressLoadedFromDisk()
    let ok = await syncOfflineProgressToServer()
    if !ok { pendingPostOfflineModeProgressSync = true }
    await reloadSettingsTab()
    await flushPendingOfflineListeningTime()
    await loadStartDashboard()
    await probeServerConnectionIfNeeded()
  }

  /// Mini-Player: Session aus Server-Fortschritt / `item`-Laden; UI kann sofort Skelett zeigen.
  @Published private(set) var isRestoringLaunchPlayback = false
  /// `play` / `playPodcastEpisode`: Item- oder Stream-Session wird aufgebaut, noch kein `activeBook`.
  @Published private(set) var isPreparingPlayback = false

  /// Verbindung prüfen / Wiedergabe vorbereiten — Now Playing zeigt „Loading…“, Floating Bar bleibt aus bis `activeBook`.
  var isPlayerConnectionLoading: Bool {
    isRestoringLaunchPlayback || isPreparingPlayback
  }

  private(set) var token: String = UserDefaults.standard.string(forKey: Keys.token) ?? ""

  let player = PlaybackController()
  let downloads = DownloadManager()
  /// Nur Player-Chrome — entkoppelt `tabViewBottomAccessory` von übrigen `@Published`-Feldern in `AppModel`.
  let floatingChrome = FloatingPlayerChromeController()

  /// Zusatz für `ScrollView`-Inhalt, damit `tabViewBottomAccessory` die letzten Zeilen nicht verdeckt.
  var nowPlayingAccessoryScrollBottomInset: CGFloat {
    player.activeBook != nil ? 56 : 0
  }

  private var cancellables = Set<AnyCancellable>()

  private var client: ABSAPIClient?
  private static let libraryCatalogPageLimit = 80
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
  /// Lokale Fortschritts-Schreibungen, die noch nicht am Server sind (vgl. Absorb `pending_syncs`).
  private var pendingLocalProgressSyncKeys: Set<String> = []
  private var lastPeriodicPlaybackProgressSaveAt: Date?
  private static let periodicPlaybackProgressSaveInterval: TimeInterval = 5

  enum MainTab: String, CaseIterable, Hashable {
    case start = "Home"
    case library = "Library"
    case podcasts = "Podcasts"
    case stats = "Stats"
    case search = "Search"
    case settings = "Settings"
  }

  /// Einziges Home-Regal für „Continue listening“ (kein separates Fallback-Regal).
  private static let homeContinueCategory = "recentlyListened"

  init() {
    Self.migrateLibraryKeysIfNeeded()
    migrateStartDisabledCategoriesIfNeeded()
    // Player-Ticks nicht pauschal an `AppModel` — Floating-Bar hat `FloatingPlayerChromeController`.
    // Nur Mini-Player-Einblendung (Scroll-Inset) bei aktivem Titel.
    player.$activeBook
      .map { $0?.id }
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    // Download-Fortschritt nur gedrosselt — Karten nutzen `LibraryRowLiveState` direkt.
    downloads.$activeItemId
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)
    downloads.$progress
      .throttle(for: .milliseconds(450), scheduler: RunLoop.main, latest: true)
      .removeDuplicates()
      .receive(on: RunLoop.main)
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
        if !reachable {
          model.isServerReachable = false
          if !model.offlineHomeUIActive {
            model.handleNetworkBecameUnreachable()
          }
        } else if !model.offlineHomeUIActive {
          Task { await model.probeServerConnectionIfNeeded() }
        }
        if reachable, !wasReachable, !model.offlineHomeUIActive {
          Task {
            if model.pendingPostOfflineModeProgressSync {
              model.pendingPostOfflineModeProgressSync = false
              let ok = await model.syncOfflineProgressToServer()
              if !ok { model.pendingPostOfflineModeProgressSync = true }
            }
            model.ensureLocalProgressLoadedFromDisk()
            await model.flushPendingOfflineListeningTime()
            await model.loadStartDashboard()
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
      self?.maybeRecordActivePlaybackProgressPeriodically()
    }
    player.onLocalPlaybackWithoutSessionSync = { [weak self] timeListened, position, duration in
      await self?.syncLocalDownloadedPlaybackToServer(
        timeListened: timeListened,
        position: position,
        duration: duration
      )
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
    if !startShelves.isEmpty, !isNetworkReachable, !offlineHomeUIActive {
      repairContinueListeningShelfFromLocalProgressOnly()
    }
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
    case .library:
      if libraryCatalogQuickFilter == .downloaded {
        let libId = selectedBooksLibrary?.id
        return downloadedShelfBooks.filter { book in
          guard let libId else { return true }
          return book.libraryId == nil || book.libraryId == libId
        }
      }
      if !isNetworkReachable, !books.isEmpty { return books }
      if !isNetworkReachable { return downloadedShelfBooks }
      return books
    case .podcasts:
      return []
    case .start, .settings, .search, .stats:
      return []
    }
  }

  /// ABS erwartet `gruppe.<base64(wert)>` (vgl. Tags/Autoren / Audiobookshelf-Web-UI).
  static func catalogFilterKey(group: String, value: String) -> String {
    let b64 = Data(value.utf8).base64EncodedString()
    return "\(group).\(b64)"
  }

  /// Schnellfilter aus der Library-Toolbar.
  func applyLibraryCatalogQuickFilter(_ filter: LibraryCatalogQuickFilter?) {
    searchTask?.cancel()
    searchText = ""
    clearSearchResults()
    guard let filter else {
      clearCatalogFilter()
      return
    }
    libraryCatalogQuickFilter = filter
    booksBrowseSection = .books
    mainTab = .library
    if filter.isLocalDownloadedOnly {
      activeLibraryFilter = nil
      setBooksLibraryFilterSummary(prefix: filter.summaryPrefix, detail: filter.summaryDetail)
      refreshDownloadedShelfFromManifests()
      return
    }
    guard let key = filter.serverFilterKey else {
      clearCatalogFilter()
      return
    }
    activeLibraryFilter = key
    setBooksLibraryFilterSummary(prefix: filter.summaryPrefix, detail: filter.summaryDetail)
    Task { await reloadLibrary(reset: true) }
  }

  /// Katalog-Filter setzen (z. B. aus Suche) und Liste neu laden.
  func applyCatalogFilter(_ filter: String?, summaryPrefix: String, summaryDetail: String?) {
    searchTask?.cancel()
    searchText = ""
    clearSearchResults()
    let trimmed = filter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmed.isEmpty || trimmed == "all" {
      clearCatalogFilter()
      return
    }
    libraryCatalogQuickFilter = nil
    activeLibraryFilter = trimmed
    setBooksLibraryFilterSummary(prefix: summaryPrefix, detail: summaryDetail)
    booksBrowseSection = .books
    mainTab = .library
    Task { await reloadLibrary(reset: true) }
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
    guard mayUseServerNetwork, let c = client else { return }
    ensureLocalProgressLoadedFromDisk()
    do {
      let auth = try await c.authorize()
      isServerReachable = true
      applyAuthorizeSession(auth)
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

  /// Kurz nach Netzverlust: Disk-Fortschritt laden und Continue-Regal reparieren (ohne Server).
  func handleNetworkBecameUnreachable() {
    ensureLocalProgressLoadedFromDisk()
    if !startShelves.isEmpty {
      repairContinueListeningShelfFromLocalProgressOnly()
    }
  }

  /// Lädt Home-Regale: online `/personalized` + `items-in-progress`; offline nur Cache + lokaler Fortschritt.
  func loadStartDashboard() async {
    ensureLocalProgressLoadedFromDisk()
    defer {
      refreshDownloadedShelfFromManifests()
      repairContinueListeningShelfFromLocalProgressOnly()
      syncContinueListeningShelvesWithProgress()
      normalizeHomeContinueListeningShelves()
      injectEbookContinueReadingShelfIfNeeded()
    }
    if offlineHomeUIActive {
      ensureLocalProgressLoadedFromDisk()
      applyCachedStartDashboard()
      refreshDownloadedShelfFromManifests()
      return
    }
    guard let c = client else {
      refreshDownloadedShelfFromManifests()
      return
    }
    if !isNetworkReachable {
      applyCachedStartDashboard()
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
        applyOnlineStartDashboard(parsed: parsed, itemsInProgress: payload)
      } else {
        let payload = try await c.itemsInProgress(limit: 80)
        applyStartDashboardFromItemsInProgressOnly(payload)
      }
    } catch {
      await refreshProgressFromServer()
      applyCachedStartDashboard()
    }
  }

  private static func normalizedStartSettingsCategory(_ category: String) -> String {
    category == "itemsInProgressFallback" ? homeContinueCategory : category
  }

  private func migrateStartDisabledCategoriesIfNeeded() {
    guard startDisabledCategories.contains("itemsInProgressFallback") else { return }
    var next = startDisabledCategories
    next.insert(Self.homeContinueCategory)
    next.remove("itemsInProgressFallback")
    startDisabledCategories = next
    UserDefaults.standard.set(Array(next), forKey: Keys.startDisabledCategories)
  }

  func isStartCategoryEnabled(_ category: String) -> Bool {
    !startDisabledCategories.contains(Self.normalizedStartSettingsCategory(category))
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
    guard selectedBooksLibrary != nil, isStartCategoryEnabled("continueEbooks") else {
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
    for b in books + startBooks + downloadedShelfBooks {
      absorb(b)
    }
    candidates.sort { ($0.ebookReadProgressFraction() ?? 0) > ($1.ebookReadProgressFraction() ?? 0) }
    return Array(candidates.prefix(14))
  }

  /// Buch zu gespeicherter Readium-Position (Katalog, Disk-Cache, Download-Meta).
  private func bookForEbookContinue(libraryItemId: String) -> ABSBook? {
    if let b = books.first(where: { $0.id == libraryItemId }) { return b }
    if let b = startBooks.first(where: { $0.id == libraryItemId }) { return b }
    if let b = downloadedShelfBooks.first(where: { $0.id == libraryItemId }) { return b }
    if let b = bookFromMergedDiskCaches(libraryItemId: libraryItemId) { return b }
    guard let account = cacheAccountURL(), let lib = selectedBooksLibrary else { return nil }
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

  private func bookFromMergedDiskCaches(libraryItemId: String) -> ABSBook? {
    guard let account = cacheAccountURL(), let lib = selectedBooksLibrary else { return nil }
    let dec = ABSJSON.decoder()
    let ascending = catalogSortField == .random ? true : !catalogSortDescending
    let sortKey = catalogSortField.apiSortParameter
    if let merged = LibraryDiskCache.loadMergedCatalog(
      account: account,
      libraryId: lib.id,
      filter: activeLibraryFilter,
      sortField: sortKey,
      ascending: ascending,
      decoder: dec
    ), let b = merged.books.first(where: { $0.id == libraryItemId }) {
      return b
    }
    if let merged = LibraryDiskCache.loadMergedBrowseEbooks(
      account: account,
      libraryId: lib.id,
      sort: sortKey,
      descending: !ascending,
      decoder: dec
    ), let b = merged.books.first(where: { $0.id == libraryItemId }) {
      return b
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

  private func isHomeContinueCategory(_ category: String) -> Bool {
    Self.normalizedStartSettingsCategory(category) == Self.homeContinueCategory
  }

  private func continueListeningDisplayTitle(serverLabel: String = "") -> String {
    ABSStartShelfLocalization.displayTitle(
      category: Self.homeContinueCategory,
      serverLabel: serverLabel
    )
  }

  private func makeContinueListeningShelf(
    id: String,
    books: [ABSBook],
    podcastEpisodes: [ABSPodcastEpisodeListItem],
    displayTitle: String? = nil
  ) -> ABSStartShelfSection {
    ABSStartShelfSection(
      id: id,
      category: Self.homeContinueCategory,
      displayTitle: displayTitle ?? continueListeningDisplayTitle(),
      books: books,
      podcastEpisodes: podcastEpisodes,
      authors: []
    )
  }

  private func inProgressPodcastEpisodeCandidates(from payload: ABSItemsInProgressPayload) -> [ABSPodcastEpisodeListItem] {
    guard let plid = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !plid.isEmpty
    else { return [] }
    var eps = payload.podcastEpisodes.filter { ($0.libraryId ?? "") == plid || $0.libraryId == nil }
    eps = eps.filter { ep in
      guard let p = progressByItemId[ep.progressLookupKey] else { return false }
      return !p.isFinished
    }
    eps.sort {
      (progressByItemId[$0.progressLookupKey]?.lastUpdate ?? 0)
        > (progressByItemId[$1.progressLookupKey]?.lastUpdate ?? 0)
    }
    return dedupePodcastEpisodesForHomeContinueList(eps)
  }

  /// Gleiche Regal-Reihenfolge und -Kategorien — vermeidet sichtbares Home-Neuzeichnen nach dem Start.
  private func startShelvesHaveSameLayout(_ lhs: [ABSStartShelfSection], _ rhs: [ABSStartShelfSection]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (a, b) in zip(lhs, rhs) {
      if a.category != b.category || a.id != b.id { return false }
    }
    return true
  }

  /// Online: personalisierte Regale; fehlendes „Continue listening“ aus `items-in-progress` ergänzen.
  private func applyOnlineStartDashboard(
    parsed: [ABSStartShelfSection],
    itemsInProgress: ABSItemsInProgressPayload
  ) {
    guard isStartCategoryEnabled(Self.homeContinueCategory) else {
      if parsed.isEmpty {
        startShelves = []
        startBooks = []
      } else {
        let visible = parsed.filter { isStartCategoryEnabled($0.category) }
        startShelves = visible
        recomputeStartBooksUnion(from: visible)
      }
      return
    }
    if parsed.isEmpty {
      applyStartDashboardFromItemsInProgressOnly(itemsInProgress)
      return
    }
    let priorContinueBooks = startShelves.filter { isHomeContinueCategory($0.category) }.flatMap(\.books)
    let priorContinueEpisodes = startShelves.filter { isHomeContinueCategory($0.category) }.flatMap(
      \.podcastEpisodes)
    let visible = parsed.filter { isStartCategoryEnabled($0.category) }
    if !startShelvesHaveSameLayout(startShelves, visible) {
      startShelves = visible
      recomputeStartBooksUnion(from: visible)
    }
    preserveValidContinueListeningItems(books: priorContinueBooks, episodes: priorContinueEpisodes)
    ensureContinueListeningShelfIfMissing(itemsInProgress: itemsInProgress)
    mergeServerAudiobooksIntoContinueShelves(itemsInProgress)
    mergeServerPodcastEpisodesIntoContinueShelves(itemsInProgress)
    syncContinueListeningShelvesWithProgress()
  }

  /// Nur `items-in-progress` (leeres `/personalized` oder keine Bibliothek gewählt).
  private func applyStartDashboardFromItemsInProgressOnly(_ payload: ABSItemsInProgressPayload) {
    guard isStartCategoryEnabled(Self.homeContinueCategory) else {
      startShelves = []
      startBooks = []
      return
    }
    let books = inProgressAudiobookCandidates(from: payload)
    let podcastEps = inProgressPodcastEpisodeCandidates(from: payload)
    guard !books.isEmpty || !podcastEps.isEmpty else {
      startShelves = []
      startBooks = []
      return
    }
    let section = makeContinueListeningShelf(
      id: "items-in-progress",
      books: books,
      podcastEpisodes: podcastEps
    )
    startShelves = [section]
    recomputeStartBooksUnion(from: [section])
    syncContinueListeningShelvesWithProgress()
  }

  private func ensureContinueListeningShelfIfMissing(itemsInProgress: ABSItemsInProgressPayload) {
    guard preferredHomeContinueShelfIndex() == nil else { return }
    let books = inProgressAudiobookCandidates(from: itemsInProgress)
    let podcastEps = inProgressPodcastEpisodeCandidates(from: itemsInProgress)
    guard !books.isEmpty || !podcastEps.isEmpty else { return }
    let section = makeContinueListeningShelf(
      id: "continue-from-items-in-progress",
      books: books,
      podcastEpisodes: podcastEps
    )
    startShelves.insert(section, at: 0)
    recomputeStartBooksUnion(from: startShelves)
  }

  /// Offline / Netzwerkfehler: gecachtes `/personalized`, Continue listening aus lokalem Fortschritt.
  private func applyCachedStartDashboard() {
    if startShelves.isEmpty, let account = cacheAccountURL(), let libId = selectedBooksLibrary?.id,
      let pdata = LibraryDiskCache.loadPersonalized(account: account, libraryId: libId)
    {
      let parsed = ABSAPIClient.parsePersonalizedStartShelves(data: pdata)
      let visible = parsed.filter { isStartCategoryEnabled($0.category) }
      if !visible.isEmpty {
        startShelves = visible
        recomputeStartBooksUnion(from: visible)
        updateStartSettingsCategoryList(parsed: parsed)
      }
    }
    repairContinueListeningShelfFromLocalProgressOnly()
    syncContinueListeningShelvesWithProgress()
  }

  /// Continue-Regale sofort an `progressByItemId` halten (verhindert Cache-Flash fertiger Titel).
  private func syncContinueListeningShelvesWithProgress() {
    applyContinueListeningFinishedFilter()
  }

  /// Ergänzt „Continue listening“ aus Katalog-/Download-Cache und gespeichertem Fortschritt (nur offline).
  private func repairContinueListeningShelfFromLocalProgressOnly() {
    guard isStartCategoryEnabled(Self.homeContinueCategory) else { return }
    let books = localContinueAudiobookBookCandidates()
    let eps = localContinuePodcastEpisodeCandidates()
    guard !books.isEmpty || !eps.isEmpty else { return }
    if let idx = preferredHomeContinueShelfIndex() {
      var shelves = startShelves
      let shelf = shelves[idx]
      let existingBookIds = Set(shelf.books.map(\.id))
      let booksToAdd = books.filter { !existingBookIds.contains($0.id) }
      let existingEpKeys = Set(shelf.podcastEpisodes.map(\.progressLookupKey))
      let epsToAdd = eps.filter { !existingEpKeys.contains($0.progressLookupKey) }
      let mergedBooks = dedupeContinueListeningBooks(shelf.books + booksToAdd)
      let mergedEps = dedupePodcastEpisodesForHomeContinueList(shelf.podcastEpisodes + epsToAdd)
      let booksChanged = mergedBooks.map(\.id) != shelf.books.map(\.id)
      let epsChanged = mergedEps.map(\.progressLookupKey) != shelf.podcastEpisodes.map(\.progressLookupKey)
      let categoryChanged = shelf.category != Self.homeContinueCategory
      guard booksChanged || epsChanged || categoryChanged else { return }
      shelves[idx] = makeContinueListeningShelf(
        id: shelf.id,
        books: mergedBooks,
        podcastEpisodes: mergedEps,
        displayTitle: shelf.displayTitle
      )
      startShelves = shelves
      recomputeStartBooksUnion(from: shelves)
    } else {
      let section = makeContinueListeningShelf(
        id: "local-cache-continue",
        books: books,
        podcastEpisodes: eps
      )
      startShelves.insert(section, at: 0)
      recomputeStartBooksUnion(from: startShelves)
    }
  }

  private func isActivelyPlayingMedia(libraryItemId: String, episodeId: String?) -> Bool {
    guard let active = player.activeBook, active.id == libraryItemId else { return false }
    let activeEp = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let wantEp = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return activeEp == wantEp
  }

  private func isActivelyPlayingProgress(_ progress: ABSUserMediaProgress) -> Bool {
    isActivelyPlayingMedia(libraryItemId: progress.libraryItemId, episodeId: progress.episodeId)
  }

  private func qualifiesForContinueListeningShelf(bookId: String) -> Bool {
    if isActivelyPlayingMedia(libraryItemId: bookId, episodeId: nil) { return true }
    guard let p = progressByItemId[bookId], !p.isFinished else { return false }
    return p.currentTime > Self.continueListeningMinPositionSeconds
  }

  private func qualifiesForContinueListeningShelf(episodeKey: String) -> Bool {
    if let p = progressByItemId[episodeKey], isActivelyPlayingProgress(p) { return true }
    guard let p = progressByItemId[episodeKey], !p.isFinished else { return false }
    return p.currentTime > Self.continueListeningMinPositionSeconds
  }

  /// Regal um gültige lokale Kandidaten ergänzen (nach `/personalized`-Reload, Play-Start).
  private func preserveValidContinueListeningItems(
    books: [ABSBook],
    episodes: [ABSPodcastEpisodeListItem]
  ) {
    guard isStartCategoryEnabled(Self.homeContinueCategory) else { return }
    let validBooks = books.filter { qualifiesForContinueListeningShelf(bookId: $0.id) }
    let validEps = episodes.filter {
      qualifiesForContinueListeningShelf(episodeKey: $0.progressLookupKey)
    }
    guard !validBooks.isEmpty || !validEps.isEmpty else { return }

    if let idx = preferredHomeContinueShelfIndex() {
      var shelves = startShelves
      let shelf = shelves[idx]
      let existingBookIds = Set(shelf.books.map(\.id))
      let existingEpKeys = Set(shelf.podcastEpisodes.map(\.progressLookupKey))
      let booksToAdd = validBooks.filter { !existingBookIds.contains($0.id) }
      let epsToAdd = validEps.filter { !existingEpKeys.contains($0.progressLookupKey) }
      guard !booksToAdd.isEmpty || !epsToAdd.isEmpty else { return }
      shelves[idx] = makeContinueListeningShelf(
        id: shelf.id,
        books: dedupeContinueListeningBooks(shelf.books + booksToAdd),
        podcastEpisodes: dedupePodcastEpisodesForHomeContinueList(shelf.podcastEpisodes + epsToAdd),
        displayTitle: shelf.displayTitle
      )
      startShelves = shelves
      recomputeStartBooksUnion(from: shelves)
    } else {
      let section = makeContinueListeningShelf(
        id: "preserved-continue",
        books: dedupeContinueListeningBooks(validBooks),
        podcastEpisodes: dedupePodcastEpisodesForHomeContinueList(validEps)
      )
      startShelves.insert(section, at: 0)
      recomputeStartBooksUnion(from: startShelves)
    }
  }

  /// Entfernt aus „Continue listening“-Regalen Einträge ohne passenden Server-Fortschritt oder mit `isFinished`.
  /// (`items-in-progress` / personalisierte Regale können nach `DELETE …/progress` kurz noch alte Zeilen liefern.)
  private func applyContinueListeningFinishedFilter() {
    guard !startShelves.isEmpty else { return }
    let newShelves = startShelves.map { shelf -> ABSStartShelfSection in
      guard isHomeContinueCategory(shelf.category) else { return shelf }
      let books = shelf.books.filter { qualifiesForContinueListeningShelf(bookId: $0.id) }
      let eps = shelf.podcastEpisodes.filter {
        qualifiesForContinueListeningShelf(episodeKey: $0.progressLookupKey)
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

  private func mergeServerPodcastEpisodesIntoContinueShelves(_ payload: ABSItemsInProgressPayload) {
    guard isStartCategoryEnabled(Self.homeContinueCategory) else { return }
    let episodes = inProgressPodcastEpisodeCandidates(from: payload)
    guard !episodes.isEmpty else { return }

    if let idx = preferredHomeContinueShelfIndex() {
      var shelves = startShelves
      let shelf = shelves[idx]
      let existingKeys = Set(shelf.podcastEpisodes.map(\.progressLookupKey))
      let toAdd = episodes.filter { !existingKeys.contains($0.progressLookupKey) }
      guard !toAdd.isEmpty else { return }
      let merged = dedupePodcastEpisodesForHomeContinueList(shelf.podcastEpisodes + toAdd)
      shelves[idx] = ABSStartShelfSection(
        id: shelf.id,
        category: shelf.category,
        displayTitle: shelf.displayTitle,
        books: shelf.books,
        podcastEpisodes: merged,
        authors: shelf.authors,
        series: shelf.series
      )
      startShelves = shelves
      recomputeStartBooksUnion(from: shelves)
    } else {
      let section = makeContinueListeningShelf(
        id: "podcast-continue-supplement",
        books: [],
        podcastEpisodes: episodes
      )
      startShelves.insert(section, at: 0)
      recomputeStartBooksUnion(from: startShelves)
    }
  }

  /// Hörbücher mit lokalem Fortschritt, die im Katalog-Cache, Start-Union oder Download-Manifest stehen.
  private func localContinueAudiobookBookCandidates() -> [ABSBook] {
    guard selectedBooksLibrary != nil else { return [] }
    var seen = Set<String>()
    var out: [ABSBook] = []
    let pool = books + startBooks + downloadedShelfBooks
    for b in pool {
      guard !seen.contains(b.id) else { continue }
      seen.insert(b.id)
      guard b.isPlayableAudiobook else { continue }
      let isDownloaded = downloadedShelfBooks.contains(where: { $0.id == b.id })
      if !isDownloaded {
        if let lid = b.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty,
          let selected = selectedBooksLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines),
          !selected.isEmpty, lid != selected
        {
          continue
        }
      }
      guard let p = progressByItemId[b.id],
        !p.isFinished,
        p.currentTime > Self.continueListeningMinPositionSeconds,
        (p.episodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { continue }
      out.append(b)
    }
    out.sort {
      (progressByItemId[$0.id]?.lastUpdate ?? 0) > (progressByItemId[$1.id]?.lastUpdate ?? 0)
    }
    return out
  }

  private func inProgressAudiobookCandidates(from payload: ABSItemsInProgressPayload) -> [ABSBook] {
    guard let lib = selectedBooksLibrary else { return [] }
    return payload.books.filter { book in
      guard let lid = book.libraryId else { return true }
      return lid == lib.id
    }
    .filter(\.isPlayableAudiobook)
    .filter { book in
      guard let p = progressByItemId[book.id],
        !p.isFinished,
        p.currentTime > Self.continueListeningMinPositionSeconds
      else { return false }
      return true
    }
    .sorted {
      (progressByItemId[$0.id]?.lastUpdate ?? 0) > (progressByItemId[$1.id]?.lastUpdate ?? 0)
    }
  }

  private func preferredHomeContinueShelfIndex() -> Int? {
    startShelves.firstIndex(where: {
      isHomeContinueCategory($0.category) && isStartCategoryEnabled($0.category)
    })
  }

  private func preferredContinueListeningBook(_ a: ABSBook, _ b: ABSBook) -> ABSBook {
    let ta = a.media.numTracks ?? 0
    let tb = b.media.numTracks ?? 0
    if ta != tb { return ta > tb ? a : b }
    if a.displayTitle.count != b.displayTitle.count {
      return a.displayTitle.count >= b.displayTitle.count ? a : b
    }
    return a
  }

  private func dedupeContinueListeningBooks(_ books: [ABSBook]) -> [ABSBook] {
    var byId: [String: ABSBook] = [:]
    var order: [String] = []
    order.reserveCapacity(books.count)
    for b in books {
      if let existing = byId[b.id] {
        byId[b.id] = preferredContinueListeningBook(existing, b)
      } else {
        byId[b.id] = b
        order.append(b.id)
      }
    }
    var out = order.compactMap { byId[$0] }
    out.sort {
      (progressByItemId[$0.id]?.lastUpdate ?? 0) > (progressByItemId[$1.id]?.lastUpdate ?? 0)
    }
    return out
  }

  private func normalizedContinueListeningShelf(_ shelf: ABSStartShelfSection) -> ABSStartShelfSection {
    let books = dedupeContinueListeningBooks(shelf.books)
    let eps = dedupePodcastEpisodesForHomeContinueList(shelf.podcastEpisodes)
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

  /// Legacy-Fallback-Kategorie normalisieren und doppelte Continue-Regale zusammenführen.
  private func normalizeHomeContinueListeningShelves() {
    var shelves = startShelves
    var remapped = false
    for (idx, shelf) in shelves.enumerated() where shelf.category == "itemsInProgressFallback" {
      shelves[idx] = makeContinueListeningShelf(
        id: shelf.id,
        books: shelf.books,
        podcastEpisodes: shelf.podcastEpisodes,
        displayTitle: shelf.displayTitle
      )
      remapped = true
    }
    if remapped {
      startShelves = shelves
      recomputeStartBooksUnion(from: shelves)
    }
    consolidateHomeContinueListeningShelves()
  }

  private func consolidateHomeContinueListeningShelves() {
    var slots: [(index: Int, shelf: ABSStartShelfSection)] = []
    slots.reserveCapacity(3)
    for (idx, shelf) in startShelves.enumerated() {
      guard isHomeContinueCategory(shelf.category), isStartCategoryEnabled(shelf.category) else { continue }
      slots.append((idx, shelf))
    }
    guard !slots.isEmpty else { return }

    if slots.count == 1 {
      let only = slots[0]
      let normalized = normalizedContinueListeningShelf(only.shelf)
      let booksChanged = normalized.books.map(\.id) != only.shelf.books.map(\.id)
      let epsChanged = normalized.podcastEpisodes.map(\.progressLookupKey)
        != only.shelf.podcastEpisodes.map(\.progressLookupKey)
      guard booksChanged || epsChanged else { return }
      var shelves = startShelves
      shelves[only.index] = normalized
      startShelves = shelves
      recomputeStartBooksUnion(from: shelves)
      return
    }

    let preferred =
      slots.first(where: { isHomeContinueCategory($0.shelf.category) }) ?? slots[0]
    var allBooks: [ABSBook] = []
    var allEps: [ABSPodcastEpisodeListItem] = []
    for slot in slots {
      allBooks.append(contentsOf: slot.shelf.books)
      allEps.append(contentsOf: slot.shelf.podcastEpisodes)
    }
    allBooks = dedupeContinueListeningBooks(allBooks)
    allEps = dedupePodcastEpisodesForHomeContinueList(allEps)

    let merged = makeContinueListeningShelf(
      id: preferred.shelf.id,
      books: allBooks,
      podcastEpisodes: allEps,
      displayTitle: preferred.shelf.displayTitle
    )
    let removeIndices = Set(slots.map(\.index).filter { $0 != preferred.index })
    var newShelves: [ABSStartShelfSection] = []
    newShelves.reserveCapacity(startShelves.count - removeIndices.count)
    for (idx, shelf) in startShelves.enumerated() {
      if removeIndices.contains(idx) { continue }
      newShelves.append(idx == preferred.index ? merged : shelf)
    }
    startShelves = newShelves
    recomputeStartBooksUnion(from: newShelves)
  }

  /// Ergänzt „Continue listening“ online nur mit `items-in-progress` (kein Katalog-Merge).
  private func mergeServerAudiobooksIntoContinueShelves(_ payload: ABSItemsInProgressPayload) {
    guard isStartCategoryEnabled(Self.homeContinueCategory) else { return }
    let candidates = dedupeContinueListeningBooks(inProgressAudiobookCandidates(from: payload))
    guard !candidates.isEmpty else { return }

    if let idx = preferredHomeContinueShelfIndex() {
      var shelves = startShelves
      let shelf = shelves[idx]
      let existing = Set(shelf.books.map(\.id))
      let toAdd = candidates.filter { !existing.contains($0.id) }
      guard !toAdd.isEmpty else { return }
      let books = dedupeContinueListeningBooks(shelf.books + toAdd)
      shelves[idx] = ABSStartShelfSection(
        id: shelf.id,
        category: shelf.category,
        displayTitle: shelf.displayTitle,
        books: books,
        podcastEpisodes: shelf.podcastEpisodes,
        authors: shelf.authors,
        series: shelf.series
      )
      startShelves = shelves
      recomputeStartBooksUnion(from: shelves)
    } else {
      let section = makeContinueListeningShelf(
        id: "audiobook-continue-supplement",
        books: candidates,
        podcastEpisodes: []
      )
      startShelves.insert(section, at: 0)
      recomputeStartBooksUnion(from: startShelves)
    }
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
    if !mayUseServerNetwork {
      await bootstrapLocalSessionOnly()
      return
    }
    isRestoringLaunchPlayback = true
    player.setMiniPlayerPlaceholder(true)
    let c = ABSAPIClient(baseURL: url, token: token)
    client = c
    do {
      let auth = try await c.authorize()
      offlineHomeModeAuto = false
      applyAuthorizeSession(auth)
      token = auth.user.token
      UserDefaults.standard.set(token, forKey: Keys.token)
      isServerReachable = true
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
      isServerReachable = false
      if !offlineHomeMode {
        offlineHomeModeAuto = true
      }
      mainTab = .start
      await prepareForOfflineHomeMode()
      await bootstrapLocalSessionOnly()
    }
  }

  /// App-Start / Auto-Offline: nur Disk-Cache und Downloads, kein Netzwerk.
  private func bootstrapLocalSessionOnly() async {
    ensureLocalProgressLoadedFromDisk()
    await loadStartDashboard()
    isRestoringLaunchPlayback = false
    player.setMiniPlayerPlaceholder(player.activeBook == nil)
  }

  /// Vor Offline-Modus: aktuelle Position lokal + Play-Session an den Server, dann Netzwerk trennen.
  private func prepareForOfflineHomeMode() async {
    recordActivePlaybackProgressLocally(markPendingServerSync: true)
    if let c = client {
      await player.flushPendingPlaySessionSync()
      if player.isRemotePlaySessionActive, let book = player.activeBook {
        let dur = player.totalDuration
        if dur > 0 {
          let pos = player.globalPosition
          let prog = min(1, max(0, pos / dur))
          try? await c.patchProgress(
            libraryItemId: book.id,
            episodeId: player.activePlaybackEpisodeId,
            patch: ABSProgressPatch(
              currentTime: pos, duration: dur, progress: prog, isFinished: nil
            )
          )
        }
      }
    }
    isServerReachable = false
    player.suspendServerNetworkingForOfflineMode()
    client = nil
  }

  private func restoreServerClientIfNeeded() {
    guard client == nil,
      let url = ABSAPIClient.normalizeServerURL(serverURL),
      !token.isEmpty
    else { return }
    client = ABSAPIClient(baseURL: url, token: token)
  }

  /// Client nur für lokale Wiedergabe (kein Authorize); entsteht nach `suspendServerClientForOfflineHome`.
  private func clientForOfflineLocalPlayback() -> ABSAPIClient? {
    if let c = client { return c }
    guard let url = ABSAPIClient.normalizeServerURL(serverURL), !token.isEmpty else { return nil }
    return ABSAPIClient(baseURL: url, token: token)
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
      applyAuthorizeSession(res)
      isServerReachable = true
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
      isServerReachable = false
    }
  }

  func logout() {
    clearCoverImageCache()
    suppressOfflineModeSideEffects = true
    offlineHomeMode = false
    offlineHomeModeAuto = false
    isServerReachable = false
    pendingPostOfflineModeProgressSync = false
    pendingLocalProgressSyncKeys = []
    UserDefaults.standard.removeObject(forKey: Keys.pendingOfflineListeningSeconds)
    suppressOfflineModeSideEffects = false
    token = ""
    isServerAdmin = false
    isServerRoot = false
    serverSettings = nil
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
    clearPodcastRssFeedCache()
    podcastRssFeedLoadInProgressShowIds = []
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
    libraryCatalogQuickFilter = nil
    booksBrowseSection = .books
    resetBooksBrowseLists()
    clearSearchResults()
    clearPodcastSearchResults()
    clearPodcastDirectorySearch()
    clearPodcastCharts()
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
    isPreparingPlayback = false
    LibraryDiskCache.clearEverything()
  }

  func selectBooksLibrary(_ lib: ABSLibrary, navigateToCatalog: Bool = false) {
    if selectedBooksLibrary?.id == lib.id {
      if selectedBooksLibrary?.name != lib.name || selectedBooksLibrary?.mediaType != lib.mediaType {
        selectedBooksLibrary = lib
      }
      if navigateToCatalog { mainTab = .library }
      return
    }
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    libraryCatalogQuickFilter = nil
    booksBrowseSection = .books
    resetBooksBrowseLists()
    selectedBooksLibrary = lib
    UserDefaults.standard.set(lib.id, forKey: Keys.booksLibrary)
    if navigateToCatalog { mainTab = .library }
    restoreBooksCatalogAndHomeFromDisk(libraryIdOverride: lib.id)
    restoreAllBrowseListsFromDisk()
  }

  func selectPodcastLibrary(_ lib: ABSLibrary, navigateToCatalog: Bool = false) {
    if selectedPodcastLibrary?.id == lib.id {
      if selectedPodcastLibrary?.name != lib.name || selectedPodcastLibrary?.mediaType != lib.mediaType {
        selectedPodcastLibrary = lib
      }
      if navigateToCatalog { mainTab = .podcasts }
      return
    }
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
    if mainTab == .library { mainTab = .start }
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
  }

  func reloadLibrary(reset: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else {
      await loadStartDashboard()
      return
    }
    if !isNetworkReachable {
      refreshDownloadedShelfFromManifests()
      applyCachedStartDashboard()
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
        limit: Self.libraryCatalogPageLimit,
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
      let pageBooks = page.results.filter(\.isUsableLibraryCatalogRow)
      if reset {
        let sameIds = pageBooks.count == books.count && zip(pageBooks, books).allSatisfy { $0.id == $1.id }
        if !sameIds { books = pageBooks }
      } else {
        books.append(contentsOf: pageBooks)
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
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
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

  /// Server-Admin: Sendung abonnieren, RSS-Feed, Show-Einstellungen auf dem Server.
  var podcastCanManageShowsOnServer: Bool { isServerAdmin || isServerRoot }

  /// Anzahl lokaler Folgen-Downloads für eine Sendung (`progressLookupKey` → Storage-ID).
  func podcastOfflineDownloadCount(forShowId showId: String) -> Int {
    let prefix = "\(showId)_"
    return downloadedItemIds.filter { $0.hasPrefix(prefix) }.count
  }

  func podcastLibraryEpisodeCountLabel(for show: ABSBook) -> String {
    let n = show.media.numTracks ?? 0
    if n == 1 { return "1 episode" }
    if n > 1 { return "\(n) episodes" }
    return "0 episodes"
  }

  func podcastDownloadedEpisodes(forShowId showId: String) -> [ABSPodcastEpisodeListItem] {
    guard podcastSelectedShowId == showId else { return [] }
    return podcastFilteredEpisodes.filter {
      downloadedItemIds.contains(podcastEpisodeOfflineStorageId($0))
    }
  }

  func podcastFeedEpisodes(forShowId showId: String) -> [ABSPodcastEpisodeListItem] {
    guard podcastSelectedShowId == showId else { return [] }
    return podcastFilteredEpisodes
  }

  /// Gecachte RSS-Folgen für eine Sendung (leer = noch nicht geladen).
  func podcastRssFeedCachedDrafts(forShowId showId: String) -> [ABSPodcastRssFeedEpisodeDraft] {
    podcastRssFeedCacheByShowId[showId] ?? []
  }

  /// Admin-Show-Detail: Bibliothek + Settings + RSS-Vorschau vorladen (Absorb: initState).
  func preloadPodcastShowAdminContext(showId: String) async {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return }
    await selectPodcastShowFilter(sid)
    async let settings: Void = loadPodcastAutoDownloadSettings(showId: sid)
    async let feed: Void = loadPodcastRssFeedIntoEpisodeList(podcastLibraryItemId: sid, forceReload: false)
    _ = await (settings, feed)
  }

  /// RSS-Tab: nur laden wenn Cache leer (oder `forceReload`).
  func ensurePodcastRssFeedLoaded(forShowId showId: String, forceReload: Bool = false) async {
    guard podcastCanManageShowsOnServer, !showId.isEmpty else { return }
    applyActivePodcastRssFeedPreview(showId: showId)
    if !forceReload, podcastRssFeedUnavailableByShowId[showId] != nil { return }
    if !forceReload, !podcastRssFeedCachedDrafts(forShowId: showId).isEmpty { return }
    await loadPodcastRssFeedIntoEpisodeList(podcastLibraryItemId: showId, forceReload: forceReload)
  }

  func activatePodcastRssFeedTab(forShowId showId: String) async {
    await ensurePodcastRssFeedLoaded(forShowId: showId, forceReload: false)
  }

  /// Nur aktive Podcast-Tab-Vorschau zurücksetzen — Cache bleibt erhalten.
  func deactivatePodcastRssFeedTab(forShowId showId: String) {
    guard podcastRssFeedPreviewForShowId == showId else { return }
    clearActivePodcastRssFeedPreview()
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
      clearActivePodcastRssFeedPreview()
      if showId == nil {
        clearPodcastAutoDownloadSettingsDraft()
      }
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
    guard mainTab == .library, booksBrowseSection == .books, libraryCatalogQuickFilter != .downloaded else {
      return
    }
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

  /// Pull-to-Refresh: Library-Katalog (Server-Fortschritt + erste Seite neu).
  func refreshBooksCatalog() async {
    await performPullToRefresh { [self] in
      await refreshProgressFromServer()
      await reloadLibrary(reset: true)
      await refreshBooksBrowseSectionLists()
    }
  }

  /// Pull-to-Refresh: Start-Tab (Regale / Offline-Reconnect).
  func refreshStartTabPullToRefresh() async {
    await performPullToRefresh { [self] in
      if offlineHomeUIActive {
        ensureLocalProgressLoadedFromDisk()
        await loadStartDashboard()
        refreshDownloadedShelfFromManifests()
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
  }

  private func rememberEbookFormatsFromCatalog(_ books: [ABSBook]) {
    EbookLocalStore.syncKnownFormatsFromDisk(account: cacheAccountURL())
    for book in books {
      for fmt in book.attachedEbookFormats {
        EbookLocalStore.rememberKnownFormat(fmt, libraryItemId: book.id)
      }
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
    await performPullToRefresh { [self] in
      await refreshProgressFromServer()
      await reloadPodcastShowsCatalog()
      if let showId = podcastSelectedShowId {
        await reloadPodcastLibrary(reset: true)
        await loadPodcastEpisodesForShowLibraryItem(showId)
      } else {
        await reloadPodcastLibrary(reset: true)
      }
    }
  }

  /// Folgen der gewählten Sendung neu laden (nach RSS ein-/ausblenden; ohne „New“-Feed-Reload).
  func reloadPodcastShowEpisodeListForCurrentShow(_ showId: String) async {
    guard podcastSelectedShowId == showId else { return }
    await refreshProgressFromServer()
    await reloadPodcastShowsCatalog()
    await loadPodcastEpisodesForShowLibraryItem(showId)
  }

  private func clearActivePodcastRssFeedPreview() {
    podcastRssFeedPreviewEpisodes = []
    podcastRssFeedPreviewForShowId = nil
    podcastRssDraftDownloadCompletedIds = []
  }

  private func clearPodcastRssFeedCache(forShowId showId: String? = nil) {
    if let showId {
      podcastRssFeedCacheByShowId.removeValue(forKey: showId)
      podcastRssDraftCompletedIdsByShowId.removeValue(forKey: showId)
      podcastRssFeedUnavailableByShowId.removeValue(forKey: showId)
      if podcastRssFeedPreviewForShowId == showId {
        clearActivePodcastRssFeedPreview()
      }
    } else {
      podcastRssFeedCacheByShowId = [:]
      podcastRssDraftCompletedIdsByShowId = [:]
      podcastRssFeedUnavailableByShowId = [:]
      clearActivePodcastRssFeedPreview()
    }
  }

  func podcastRssFeedUnavailableMessage(forShowId showId: String) -> String? {
    podcastRssFeedUnavailableByShowId[showId]
  }

  private func applyActivePodcastRssFeedPreview(showId: String) {
    podcastRssFeedPreviewForShowId = showId
    podcastRssFeedPreviewEpisodes = podcastRssFeedCacheByShowId[showId] ?? []
    podcastRssDraftDownloadCompletedIds = podcastRssDraftCompletedIdsByShowId[showId] ?? []
  }

  /// RSS-Vorschau im Podcast-Tab ausblenden; Cache bleibt. Optional Bibliothek neu laden.
  func closePodcastRssFeedPreview(reloadLibrary: Bool = true) async {
    let sid = podcastRssFeedPreviewForShowId
    guard let sid, !sid.isEmpty else { return }
    clearActivePodcastRssFeedPreview()
    errorMessage = nil
    if reloadLibrary, podcastSelectedShowId == sid {
      await reloadPodcastShowEpisodeListForCurrentShow(sid)
    }
  }

  /// Show-Settings: Auto-Download laden (RSS-Cache unangetastet).
  func preparePodcastShowSettingsSheet(showId: String) async {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return }
    await loadPodcastAutoDownloadSettings(showId: sid)
  }

  /// Toolbar: Feed-Vorschau ein-/ausblenden; jeweils mit Reload der Episoden-Ansicht.
  func togglePodcastRssFeedToolbar(podcastLibraryItemId: String) async {
    guard podcastCanManageShowsOnServer else { return }
    guard !podcastLibraryItemId.isEmpty else { return }
    if podcastRssFeedPreviewForShowId == podcastLibraryItemId {
      clearActivePodcastRssFeedPreview()
      errorMessage = nil
      if podcastSelectedShowId == podcastLibraryItemId {
        await reloadPodcastShowEpisodeListForCurrentShow(podcastLibraryItemId)
        await loadStartDashboard()
      }
      return
    }

    errorMessage = nil
    applyActivePodcastRssFeedPreview(showId: podcastLibraryItemId)

    if podcastSelectedShowId == podcastLibraryItemId {
      await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.reloadPodcastShowEpisodeListForCurrentShow(podcastLibraryItemId) }
        group.addTask {
          await self.loadPodcastRssFeedIntoEpisodeList(
            podcastLibraryItemId: podcastLibraryItemId, forceReload: false)
        }
      }
    } else {
      await loadPodcastRssFeedIntoEpisodeList(
        podcastLibraryItemId: podcastLibraryItemId, forceReload: false)
    }
  }

  /// RSS-Feed parsen (`POST /api/podcasts/feed`) und pro Sendung cachen.
  func loadPodcastRssFeedIntoEpisodeList(
    podcastLibraryItemId: String,
    forceReload: Bool = false
  ) async {
    guard podcastCanManageShowsOnServer else { return }
    let sid = podcastLibraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty, let c = client else { return }

    if !forceReload, podcastRssFeedUnavailableByShowId[sid] != nil {
      applyActivePodcastRssFeedPreview(showId: sid)
      return
    }

    if !forceReload, let cached = podcastRssFeedCacheByShowId[sid], !cached.isEmpty {
      applyActivePodcastRssFeedPreview(showId: sid)
      return
    }

    guard isNetworkReachable else {
      errorMessage = "No network connection."
      revertPodcastRssFeedPreviewIfEmpty(showId: sid)
      return
    }
    guard !podcastRssFeedLoadInProgressShowIds.contains(sid) else { return }
    podcastRssFeedLoadInProgressShowIds.insert(sid)
    defer { podcastRssFeedLoadInProgressShowIds.remove(sid) }
    do {
      guard let feedUrl = await rssFeedUrlForPodcastShow(libraryItemId: sid) else {
        podcastRssFeedUnavailableByShowId[sid] =
          "This show has no RSS feed URL. It may have been added from a folder instead of a feed subscription."
        podcastRssFeedCacheByShowId[sid] = []
        applyActivePodcastRssFeedPreview(showId: sid)
        return
      }
      podcastRssFeedUnavailableByShowId.removeValue(forKey: sid)
      let data = try await c.fetchPodcastRssFeed(rssFeedUrl: feedUrl)
      let drafts = try ABSPodcastRssFeedEpisodeDraft.episodesFromFeedApiResponse(data)
      podcastRssFeedCacheByShowId[sid] = drafts
      if forceReload {
        podcastRssDraftCompletedIdsByShowId[sid] = []
      }
      applyActivePodcastRssFeedPreview(showId: sid)
      if drafts.isEmpty {
        errorMessage = "No episodes found in the feed."
      } else {
        errorMessage = nil
      }
    } catch {
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      errorMessage = error.localizedDescription
      revertPodcastRssFeedPreviewIfEmpty(showId: sid)
    }
  }

  /// RSS-Vorschau zurücknehmen, wenn der Feed nicht geladen werden konnte (keine Folgen).
  private func revertPodcastRssFeedPreviewIfEmpty(showId: String) {
    guard podcastRssFeedPreviewForShowId == showId,
      podcastRssFeedCachedDrafts(forShowId: showId).isEmpty
    else { return }
    podcastRssFeedCacheByShowId.removeValue(forKey: showId)
    clearActivePodcastRssFeedPreview()
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
        autoDownloadSchedule: podcastAutoDownloadInterval.cronExpression,
        maxEpisodesToKeep: podcastMaxEpisodesToKeep,
        maxNewEpisodesToDownload: podcastMaxNewEpisodesToDownload
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
    podcastMaxEpisodesToKeep = item.media.maxEpisodesToKeep ?? 0
    podcastMaxNewEpisodesToDownload = item.media.maxNewEpisodesToDownload ?? 3
  }

  private func clearPodcastAutoDownloadSettingsDraft() {
    podcastAutoDownloadSettingsShowId = nil
    podcastAutoDownloadEnabled = false
    podcastAutoDownloadInterval = .default
    podcastMaxEpisodesToKeep = 0
    podcastMaxNewEpisodesToDownload = 3
  }

  private func replacePodcastShowInCatalog(_ updated: ABSBook) {
    guard let idx = podcastShows.firstIndex(where: { $0.id == updated.id }) else { return }
    podcastShows[idx] = updated
  }

  /// Server: RSS prüfen und neue Folgen herunterladen (`GET …/checknew`).
  func checkAndDownloadNewPodcastEpisodes(showId: String) async {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty, let c = client else { return }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    guard podcastCheckNewInProgressShowId != sid else { return }
    podcastCheckNewInProgressShowId = sid
    defer { podcastCheckNewInProgressShowId = nil }
    do {
      let limit = podcastCheckNewDownloadLimit(forShowId: sid)
      _ = try await c.checkNewPodcastEpisodes(podcastLibraryItemId: sid, limit: limit)
      await mergeNewPodcastLibraryEpisodesFromExpandedItem(showLibraryItemId: sid)
      await refreshProgressFromServer()
      if podcastSelectedShowId == sid {
        await reloadPodcastShowEpisodeListForCurrentShow(sid)
      }
      podcastRssFeedCacheByShowId.removeValue(forKey: sid)
      podcastRssDraftCompletedIdsByShowId.removeValue(forKey: sid)
      await loadPodcastRssFeedIntoEpisodeList(podcastLibraryItemId: sid, forceReload: true)
      await loadPodcastAutoDownloadSettings(showId: sid)
      await loadStartDashboard()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func podcastCheckNewDownloadLimit(forShowId sid: String) -> Int? {
    if podcastAutoDownloadSettingsShowId == sid {
      return podcastMaxNewEpisodesToDownload
    }
    if let n = podcastShows.first(where: { $0.id == sid })?.media.maxNewEpisodesToDownload {
      return n
    }
    return nil
  }

  /// Podcast-Folge von der Server-Bibliothek löschen.
  func deletePodcastEpisodeFromLibrary(
    showLibraryItemId: String,
    episode: ABSPodcastEpisodeListItem
  ) async {
    let sid = showLibraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    let eid = episode.episodeId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty, !eid.isEmpty, let c = client else { return }
    guard podcastCanManageShowsOnServer else { return }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    do {
      try await c.deletePodcastEpisode(podcastLibraryItemId: sid, episodeId: eid)
      podcastFilteredEpisodes.removeAll { $0.episodeId == eid }
      let storageId = podcastEpisodeOfflineStorageId(episode)
      if downloadedItemIds.contains(storageId) {
        downloads.deleteDownload(itemId: storageId)
        downloadedItemIds.remove(storageId)
        persistDownloads()
        refreshDownloadedShelfFromManifests()
      }
      progressByItemId.removeValue(forKey: episode.progressLookupKey)
      await refreshProgressFromServer()
      await reloadPodcastShowsCatalog()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Eine Feed-Folge auf den Server laden (`download-episodes`).
  func downloadPodcastRssEpisodeDraft(_ draft: ABSPodcastRssFeedEpisodeDraft, podcastLibraryItemId: String) async {
    guard podcastCanManageShowsOnServer else { return }
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
      var done = podcastRssDraftCompletedIdsByShowId[podcastLibraryItemId] ?? []
      done.insert(draftId)
      podcastRssDraftCompletedIdsByShowId[podcastLibraryItemId] = done
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
      let u = normalizedPodcastFeedURL(s.media.metadata.feedUrl)
    {
      return u
    }
    guard let c = client else { return nil }
    do {
      let data = try await c.itemResponseData(id: libraryItemId, expanded: true)
      if let u = Self.extractPodcastFeedURL(fromItemJSON: data) { return u }
      let full = try ABSJSON.decoder().decode(ABSBook.self, from: data)
      return normalizedPodcastFeedURL(full.media.metadata.feedUrl)
    } catch {
      return nil
    }
  }

  private func normalizedPodcastFeedURL(_ raw: String?) -> String? {
    Self.normalizedPodcastFeedURL(raw)
  }

  /// ABS liefert `feedUrl` oder `feedURL` in `media.metadata` (vgl. Server `Podcast.getAbsMetadataJson`).
  private static func extractPodcastFeedURL(fromItemJSON data: Data) -> String? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    func pick(from dict: [String: Any]?) -> String? {
      guard let dict else { return nil }
      for key in ["feedUrl", "feedURL", "feed_url"] {
        if let raw = dict[key] as? String, let u = normalizedPodcastFeedURL(raw) { return u }
      }
      return nil
    }
    if let u = pick(from: root["metadata"] as? [String: Any]) { return u }
    if let media = root["media"] as? [String: Any] {
      if let u = pick(from: media["metadata"] as? [String: Any]) { return u }
      if let u = pick(from: media) { return u }
    }
    return pick(from: root)
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
    guard mainTab == .library || mainTab == .search else { return }
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

  /// Alle Hörbuch-Stubs aus Speicher + Disk-Caches (wie Library-Katalog beim Start).
  private func mergedLocalCatalogBooks() -> [ABSBook] {
    var byId: [String: ABSBook] = [:]
    func add(_ list: [ABSBook]) {
      for book in list where book.isUsableLibraryCatalogRow {
        byId[book.id] = book
      }
    }
    add(books)
    add(startBooks)
    add(searchBooks)
    add(downloadedShelfBooks)
    add(entityDetailBooks)
    add(entityDetailAuthorStandaloneBooks)
    for section in entityDetailAuthorSeriesSections {
      add(section.books)
    }
    for list in browseCollectionBooksById.values {
      add(list)
    }
    for item in browseSeries {
      add(item.books ?? [])
    }
    return Array(byId.values)
  }

  /// Browse-Listen und Katalog aus `LibraryDiskCache` in `@Published`, falls noch leer.
  private func ensureLocalCatalogCachesInMemory() {
    guard selectedBooksLibrary != nil else { return }
    if books.isEmpty {
      restoreBooksCatalogAndHomeFromDisk()
    }
    if browseAuthors.isEmpty { _ = restoreBrowseAuthorsFromDisk() }
    if browseSeries.isEmpty { _ = restoreBrowseSeriesFromDisk() }
    if browseNarrators.isEmpty { _ = restoreBrowseNarratorsFromDisk() }
    if browseCollections.isEmpty { _ = restoreBrowseCollectionsFromDisk() }
    ensureLocalProgressLoadedFromDisk()
  }

  private func bookMatchesSearchQuery(_ book: ABSBook, query: String) -> Bool {
    let q = query.lowercased()
    if book.displayTitle.lowercased().contains(q) { return true }
    if book.displayAuthorsCardLine.lowercased().contains(q) { return true }
    if let series = book.media.metadata.series {
      for s in series where s.name.lowercased().contains(q) {
        return true
      }
    }
    return false
  }

  private func bookMatchesAuthor(_ book: ABSBook, authorId: String, displayName: String) -> Bool {
    let aid = authorId.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    if let authors = book.media.metadata.authors {
      if !aid.isEmpty, authors.contains(where: { $0.id == aid }) { return true }
      if !name.isEmpty,
        authors.contains(where: { $0.name.localizedCaseInsensitiveContains(name) })
      {
        return true
      }
    }
    if !name.isEmpty, book.displayAuthorsCardLine.localizedCaseInsensitiveContains(name) {
      return true
    }
    return false
  }

  private func bookMatchesNarrator(_ book: ABSBook, narratorName: String) -> Bool {
    let want = narratorName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !want.isEmpty else { return false }
    return book.media.metadata.narratorNamesForLibraryBrowseCoverMatch().contains {
      $0.localizedCaseInsensitiveCompare(want) == .orderedSame
    }
  }

  private func booksInLocalSeries(seriesId: String, displayName: String) -> [ABSBook] {
    if let cached = browseSeries.first(where: { $0.id == seriesId })?.books {
      return cached.filter(\.isUsableLibraryCatalogRow)
    }
    let sid = seriesId.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return mergedLocalCatalogBooks().filter { book in
      guard let series = book.media.metadata.series else { return false }
      return series.contains { item in
        if !sid.isEmpty, item.id == sid { return true }
        if !name.isEmpty, item.name.localizedCaseInsensitiveContains(name) { return true }
        return false
      }
    }
  }

  /// Offline / ohne Server: Suche in gecachten Katalog- und Browse-Daten (analog Library-Liste).
  private func applyLocalSearchResults(query: String) {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.count < 2 {
      clearSearchResults()
      return
    }
    ensureLocalCatalogCachesInMemory()
    searchBooks = mergedLocalCatalogBooks()
      .filter { bookMatchesSearchQuery($0, query: q) }
      .sorted {
        $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
      }
    searchAuthors = browseAuthors
      .filter { $0.name.localizedCaseInsensitiveContains(q) }
      .prefix(40)
      .map { ABSSearchAuthorRow(id: $0.id, name: $0.name, numBooks: $0.numBooks) }
    searchNarrators = browseNarrators
      .filter { $0.name.localizedCaseInsensitiveContains(q) }
      .prefix(40)
      .map { ABSSearchNarratorRow(name: $0.name, numBooks: $0.numBooks) }
    searchSeries = browseSeries
      .filter { $0.name.localizedCaseInsensitiveContains(q) }
      .prefix(40)
      .map { ABSSearchSeriesRow(id: $0.id, name: $0.name, books: $0.books) }
    searchTags = []
    searchGenres = []
  }

  private func applyEntityDetailFromLocalCache(for nav: BooksEntityDetailNav) {
    ensureLocalCatalogCachesInMemory()
    entityDetailDescription = nil
    entityDetailAuthorSeriesSections = []
    entityDetailAuthorStandaloneBooks = []
    entityDetailUsesLibraryItemFilter = false
    switch nav.kind {
    case .author:
      let rows = mergedLocalCatalogBooks().filter {
        bookMatchesAuthor($0, authorId: nav.entityId, displayName: nav.title)
      }
      entityDetailBooks = entityDetailSortBooksBySeriesOrder(rows)
      entityDetailTotal = rows.count
    case .series:
      let rows = entityDetailSortBooksBySeriesOrder(
        booksInLocalSeries(seriesId: nav.entityId, displayName: nav.title))
      entityDetailBooks = rows
      entityDetailTotal = rows.count
    case .narrator:
      let rows = mergedLocalCatalogBooks().filter { bookMatchesNarrator($0, narratorName: nav.entityId) }
      entityDetailBooks = rows
      entityDetailTotal = rows.count
    }
  }

  private func performSearch(query: String) async {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.count < 2 {
      clearSearchResults()
      return
    }
    guard selectedBooksLibrary != nil else { return }
    if !mayUseServerNetwork || !isNetworkReachable || client == nil {
      applyLocalSearchResults(query: q)
      return
    }
    guard let c = client, let lib = selectedBooksLibrary else {
      applyLocalSearchResults(query: q)
      return
    }
    isLoadingLibrary = true
    defer { isLoadingLibrary = false }
    do {
      let res = try await c.search(libraryId: lib.id, query: q)
      searchBooks = res.bookSearchPlayableLibraryItems { bookDuration($0) }
      searchAuthors = res.authors
      searchNarrators = res.narrators
      searchSeries = res.series
      searchTags = res.tags
      searchGenres = res.genres
    } catch {
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      applyLocalSearchResults(query: q)
      if searchBooks.isEmpty, searchAuthors.isEmpty, searchNarrators.isEmpty, searchSeries.isEmpty {
        errorMessage = error.localizedDescription
      }
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
    let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    applyCatalogFilter(
      Self.catalogFilterKey(group: "authors", value: authorId),
      summaryPrefix: "Author",
      summaryDetail: name.isEmpty ? nil : name
    )
  }

  func applySeriesFilter(seriesId: String, displayName: String? = nil) {
    let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    applyCatalogFilter(
      Self.catalogFilterKey(group: "series", value: seriesId),
      summaryPrefix: "Series",
      summaryDetail: name.isEmpty ? nil : name
    )
  }

  func applyNarratorFilter(narratorName: String) {
    let name = narratorName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    applyCatalogFilter(
      Self.catalogFilterKey(group: "narrators", value: name),
      summaryPrefix: "Narrator",
      summaryDetail: name
    )
  }

  /// Detailseite: Entity-API wo vorhanden (`/api/authors/:id`, `/api/series/:id`), sonst gefilterte Library-Items.
  func reloadEntityDetail(for nav: BooksEntityDetailNav, reset: Bool) async {
    guard selectedBooksLibrary != nil else { return }
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
    if !mayUseServerNetwork || !isNetworkReachable || client == nil {
      applyEntityDetailFromLocalCache(for: nav)
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
    guard let c = client, let lib = selectedBooksLibrary else {
      applyEntityDetailFromLocalCache(for: nav)
      return
    }
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
      applyEntityDetailFromLocalCache(for: nav)
      if entityDetailBooks.isEmpty {
        errorMessage = error.localizedDescription
      }
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
      limit: Self.libraryCatalogPageLimit,
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
    let name = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    applyCatalogFilter(
      Self.catalogFilterKey(group: "tags", value: name),
      summaryPrefix: "Tag",
      summaryDetail: name
    )
  }

  func applyGenreFilter(genreName: String) {
    let name = genreName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    applyCatalogFilter(
      Self.catalogFilterKey(group: "genres", value: name),
      summaryPrefix: "Genre",
      summaryDetail: name
    )
  }

  func clearCatalogFilter() {
    guard activeLibraryFilter != nil || libraryCatalogQuickFilter != nil else { return }
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    libraryCatalogQuickFilter = nil
    booksBrowseSection = .books
    Task { await reloadLibrary(reset: true) }
  }

  var isLibraryCatalogFiltered: Bool {
    libraryCatalogQuickFilter != nil
      || !(activeLibraryFilter?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
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
    guard let progress = effectiveResumeProgress(), !progress.isFinished else {
      player.setMiniPlayerPlaceholder(true)
      UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      return
    }
    let libraryItemId = progress.libraryItemId
    if let live = progressByItemId[progress.progressLookupKey], live.isFinished {
      player.setMiniPlayerPlaceholder(true)
      UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      return
    }
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
          autoPlay: false,
          attemptServerPlaySession: mayUseServerNetwork && isNetworkReachable
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
        client: c,
        book: book,
        resumeAt: resume,
        localDownloadRoot: local,
        episodeId: nil,
        autoPlay: false,
        attemptServerPlaySession: mayUseServerNetwork && isNetworkReachable
      )
    } catch {
      UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      player.setMiniPlayerPlaceholder(true)
    }
  }

  private func cachedBookFallback(id: String) -> ABSBook? {
    if let book = mergedLocalCatalogBooks().first(where: { $0.id == id }) { return book }
    if let book = podcastShows.first(where: { $0.id == id }) { return book }
    if let book = podcastSearchBooks.first(where: { $0.id == id }) { return book }
    if let episode = podcastEpisodes.first(where: { $0.libraryItemId == id }) {
      return episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
    }
    return nil
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
    if startShelves.isEmpty {
      startShelves = [
        makeContinueListeningShelf(
          id: "optimistic-continue-seed-book",
          books: [book],
          podcastEpisodes: []
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
    if startShelves.isEmpty {
      startShelves = [
        makeContinueListeningShelf(
          id: "optimistic-continue-seed-pod",
          books: [],
          podcastEpisodes: [episode]
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
    guard isStartCategoryEnabled(Self.homeContinueCategory) else { return }
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
    guard isStartCategoryEnabled(Self.homeContinueCategory) else { return }
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
    let local = localDownloadRoot(for: book.id)
    if offlineHomeUIActive, local == nil {
      errorMessage = "Download this title to play it offline."
      return
    }
    guard let c = clientForOfflineLocalPlayback() else { return }
    isPreparingPlayback = true
    defer { isPreparingPlayback = false }
    errorMessage = nil
    let resume = resumeAtOverride ?? progressByItemId[book.id]?.currentTime ?? 0
    do {
      var resolved = book
      if let root = local, let manifest = ABSDownloadManifest.load(from: root) {
        let fromManifest = ABSBook.fromDownloadManifest(manifest)
        if mayUseServerNetwork, isNetworkReachable, !book.media.metadata.hasRichMetadata,
          let expanded = try? await c.item(id: book.id, expanded: true)
        {
          resolved = expanded.mergingLocalDownloadPlayback(fromManifest)
        } else {
          resolved = book.mergingLocalDownloadPlayback(fromManifest)
        }
      } else if mayUseServerNetwork, isNetworkReachable {
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
        client: c,
        book: resolved,
        resumeAt: resume,
        localDownloadRoot: local,
        episodeId: nil,
        autoPlay: autoPlay,
        attemptServerPlaySession: mayUseServerNetwork && isNetworkReachable
      )
      UserDefaults.standard.set(resolved.id, forKey: Keys.lastPlayedItemId)
      if autoPlay {
        bumpOptimisticContinueListeningForAudiobook(resolved, resumeAt: resume)
        requestPresentNowPlayingSheet()
        if mayUseServerNetwork {
          Task { await loadStartDashboard() }
        }
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
    let offlineKey = podcastEpisodeOfflineStorageId(episode)
    let local = localDownloadRoot(for: offlineKey)
    if offlineHomeUIActive, local == nil {
      errorMessage = "Download this episode to play it offline."
      return
    }
    guard let c = clientForOfflineLocalPlayback() else { return }
    isPreparingPlayback = true
    defer { isPreparingPlayback = false }
    errorMessage = nil
    let resume =
      resumeAtOverride ?? progressByItemId[episode.progressLookupKey]?.currentTime ?? 0
    let stub = episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
    do {
      try await player.playBook(
        client: c,
        book: stub,
        resumeAt: resume,
        localDownloadRoot: local,
        episodeId: episode.episodeId,
        autoPlay: autoPlay,
        attemptServerPlaySession: mayUseServerNetwork && isNetworkReachable
      )
      UserDefaults.standard.set(stub.id, forKey: Keys.lastPlayedItemId)
      if autoPlay {
        bumpOptimisticContinueListeningForPodcastEpisode(episode, resumeAt: resume)
        requestPresentNowPlayingSheet()
        if mayUseServerNetwork {
          Task { await loadStartDashboard() }
        }
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
    applyLocalMarkFinished(libraryItemId: bookId, episodeId: nil)
    patchBooksCatalogAfterAudiobookProgressChange(bookId: bookId, finished: true)
    do {
      try await c.markFinished(libraryItemId: bookId)
      let auth = try await c.authorize()
      applyAuthorizeUser(auth.user)
      reconcileProgressAfterMarkFinished(libraryItemId: bookId, episodeId: nil)
      syncContinueListeningShelvesWithProgress()
      invalidateCachedPersonalizedHome(libraryId: selectedBooksLibrary?.id)
      searchBooks.removeAll { $0.id == bookId }
      podcastSearchBooks.removeAll { $0.id == bookId }
      if needsFullLibraryReloadAfterAudiobookProgressChange(bookId: bookId, finished: true) {
        await reloadLibrary(reset: true)
      }
      if wasCurrentPlayback {
        await dismissPlayer(idlePlaceholder: false)
      }
      if UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == bookId {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      }
      removeLocalDownloadIfFinishedSetting(bookId: bookId)
      await refreshStartDashboardIfNeeded()
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
      applyLocalMarkUnfinished(libraryItemId: bookId, episodeId: nil)
      patchBooksCatalogAfterAudiobookProgressChange(bookId: bookId, finished: false)
      let auth = try await c.authorize()
      applyAuthorizeSession(auth)
      syncContinueListeningShelvesWithProgress()
      if needsFullLibraryReloadAfterAudiobookProgressChange(bookId: bookId, finished: false) {
        await reloadLibrary(reset: true)
      }
      await refreshStartDashboardIfNeeded()
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
    progressByItemId.removeValue(forKey: bookId)
    pendingLocalProgressSyncKeys.remove(bookId)
    persistProgressToDisk()
    patchBooksCatalogAfterAudiobookProgressDiscard(bookId: bookId)
    do {
      try await c.deleteMediaProgress(progressRowId: row.idForMediaProgressDeleteRequest)
      syncContinueListeningShelvesWithProgress()
      let auth = try await c.authorize()
      applyAuthorizeSession(auth)
      if needsFullLibraryReloadAfterAudiobookProgressDiscard(bookId: bookId) {
        await reloadLibrary(reset: true)
      }
      if playing {
        player.seek(global: 0)
      }
      await refreshStartDashboardIfNeeded()
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
      reconcileProgressAfterMarkFinished(
        libraryItemId: episode.libraryItemId, episodeId: episode.episodeId)
      syncContinueListeningShelvesWithProgress()
      invalidateCachedPersonalizedHome(libraryId: selectedBooksLibrary?.id)
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
      applyLocalMarkUnfinished(libraryItemId: episode.libraryItemId, episodeId: episode.episodeId)
      let auth = try await c.authorize()
      applyAuthorizeSession(auth)
      syncContinueListeningShelvesWithProgress()
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
    progressByItemId.removeValue(forKey: key)
    pendingLocalProgressSyncKeys.remove(key)
    persistProgressToDisk()
    do {
      try await c.deleteMediaProgress(progressRowId: row.idForMediaProgressDeleteRequest)
      syncContinueListeningShelvesWithProgress()
      let auth = try await c.authorize()
      applyAuthorizeSession(auth)
      if playing {
        player.seek(global: 0)
      }
      await refreshStartDashboardIfNeeded()
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
        autoPlay: auto,
        attemptServerPlaySession: mayUseServerNetwork && isNetworkReachable
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

  /// Schreibt die aktuelle Player-Position in `progressByItemId` und auf Disk (vor Server-PATCH).
  private func recordActivePlaybackProgressLocally(markPendingServerSync: Bool = true) {
    guard let book = player.activeBook else { return }
    let dur = player.totalDuration
    guard dur > 0 else { return }
    let pos = player.globalPosition
    let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let p: ABSUserMediaProgress
    if ep.isEmpty {
      p = progressForOptimisticAudiobook(book, resumeAt: pos)
    } else if let episode = podcastEpisodeForSmartDownloadFromActivePlayback() {
      p = progressForOptimisticPodcastEpisode(episode, resumeAt: pos)
    } else {
      p = progressForOptimisticAudiobook(book, resumeAt: pos)
    }
    progressByItemId[p.progressLookupKey] = p
    if markPendingServerSync {
      pendingLocalProgressSyncKeys.insert(p.progressLookupKey)
    }
    persistProgressToDisk()
    syncContinueListeningShelvesWithProgress()
  }

  private func maybeRecordActivePlaybackProgressPeriodically() {
    guard player.activeBook != nil, player.totalDuration > 0 else { return }
    let now = Date()
    if let last = lastPeriodicPlaybackProgressSaveAt,
      now.timeIntervalSince(last) < Self.periodicPlaybackProgressSaveInterval
    {
      return
    }
    lastPeriodicPlaybackProgressSaveAt = now
    recordActivePlaybackProgressLocally()
  }

  /// Pause / Offline: immer lokal sichern; Server nur wenn online (Absorb: `saveLocal` zuerst).
  func handlePlaybackPaused() async {
    recordActivePlaybackProgressLocally()
    if mayUseServerNetwork {
      if player.isRemotePlaySessionActive {
        await player.flushPendingPlaySessionSync()
      } else {
        await syncProgressToServer()
      }
      if mainTab == .start {
        await loadStartDashboard()
      }
    }
  }

  /// Fortschritt per PATCH, wenn kein Stream-Session-Sync läuft (z. B. nur lokale Dateien).
  func syncProgressToServer() async {
    recordActivePlaybackProgressLocally()
    guard mayUseServerNetwork, let c = client, let book = player.activeBook else { return }
    if player.isRemotePlaySessionActive {
      await player.flushPendingPlaySessionSync()
      return
    }
    let dur = player.totalDuration
    guard dur > 0 else { return }
    let pos = player.globalPosition
    let prog = min(1, max(0, pos / dur))
    let key: String = {
      let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if ep.isEmpty { return book.id }
      return "\(book.id)-\(ep)"
    }()
    do {
      try await c.patchProgress(
        libraryItemId: book.id,
        episodeId: player.activePlaybackEpisodeId,
        patch: ABSProgressPatch(currentTime: pos, duration: dur, progress: prog, isFinished: nil)
      )
      pendingLocalProgressSyncKeys.remove(key)
    } catch {}
  }

  /// Kumulierte Hörzeit ohne aktive Play-Session (lokale Dateien, vgl. Absorb `offline_listening_*`).
  private func addPendingOfflineListeningSeconds(progressKey: String, seconds: Int) {
    guard seconds > 0 else { return }
    var map = Self.loadPendingOfflineListeningSecondsMap()
    map[progressKey, default: 0] += seconds
    Self.savePendingOfflineListeningSecondsMap(map)
  }

  private static func loadPendingOfflineListeningSecondsMap() -> [String: Int] {
    guard let data = UserDefaults.standard.data(forKey: Keys.pendingOfflineListeningSeconds),
      let map = try? JSONDecoder().decode([String: Int].self, from: data)
    else { return [:] }
    return map
  }

  private static func savePendingOfflineListeningSecondsMap(_ map: [String: Int]) {
    if map.isEmpty {
      UserDefaults.standard.removeObject(forKey: Keys.pendingOfflineListeningSeconds)
      return
    }
    if let data = try? JSONEncoder().encode(map) {
      UserDefaults.standard.set(data, forKey: Keys.pendingOfflineListeningSeconds)
    }
  }

  /// Sendet gespeicherte Offline-Hörsekunden per kurzer Play-Session (Absorb `flushOfflineListeningTime`).
  func flushPendingOfflineListeningTime() async {
    guard let c = client, isNetworkReachable, mayUseServerNetwork else { return }
    var map = Self.loadPendingOfflineListeningSecondsMap()
    guard !map.isEmpty else { return }

    var flushedKeys: [String] = []
    for (key, seconds) in map where seconds > 0 {
      guard let p = progressByItemId[key] else {
        flushedKeys.append(key)
        continue
      }
      let pos = max(0, p.currentTime)
      do {
        let session = try await c.startPlaySession(
          itemId: p.libraryItemId,
          episodeId: p.episodeId,
          deviceId: PlaybackController.stableDeviceId(),
          appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
        try await c.syncPlaySession(
          sessionId: session.id,
          timeListened: seconds,
          currentTime: pos
        )
        try? await c.closePlaySession(sessionId: session.id)
        flushedKeys.append(key)
      } catch {
        if Self.isTransientURLFailure(error) { break }
      }
    }
    for key in flushedKeys {
      map.removeValue(forKey: key)
    }
    Self.savePendingOfflineListeningSecondsMap(map)
  }

  private static func isTransientURLFailure(_ error: Error) -> Bool {
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain {
      switch ns.code {
      case NSURLErrorNotConnectedToInternet,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorTimedOut,
        NSURLErrorDataNotAllowed:
        return true
      default:
        break
      }
    }
    return false
  }

  /// Lokale Download-Wiedergabe: Fortschritt lokal, dann Session-Sync oder PATCH / Offline-Hörzeit.
  func syncLocalDownloadedPlaybackToServer(
    timeListened: Int,
    position: Double,
    duration: Double
  ) async {
    recordActivePlaybackProgressLocally(markPendingServerSync: true)
    guard let book = player.activeBook else { return }
    let progressKey = activePlaybackProgressLookupKey() ?? book.id

    guard mayUseServerNetwork, isNetworkReachable, let c = client else {
      if timeListened > 0 {
        addPendingOfflineListeningSeconds(progressKey: progressKey, seconds: timeListened)
      }
      return
    }

    if player.isRemotePlaySessionActive { return }

    let ep = player.activePlaybackEpisodeId
    let dur = duration > 0 ? duration : player.totalDuration
    guard dur > 0 else { return }
    let pos = max(0, position)
    let prog = min(1, max(0, pos / dur))
    do {
      try await c.patchProgress(
        libraryItemId: book.id,
        episodeId: ep,
        patch: ABSProgressPatch(currentTime: pos, duration: dur, progress: prog, isFinished: nil)
      )
      pendingLocalProgressSyncKeys.remove(progressKey)
    } catch {
      if timeListened > 0 {
        addPendingOfflineListeningSeconds(progressKey: progressKey, seconds: timeListened)
      }
    }
  }

  private func activePlaybackProgressLookupKey() -> String? {
    guard let book = player.activeBook else { return nil }
    let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if ep.isEmpty { return book.id }
    if let episode = podcastEpisodeForSmartDownloadFromActivePlayback() {
      return episode.progressLookupKey
    }
    return "\(book.id)/ep/\(ep)"
  }

  /// Nach Offline-Modus: Session-Sync, dann alle lokalen `progressByItemId`-Einträge per PATCH; zuletzt `/authorize` zum Abgleich.
  /// - Returns: `true`, wenn Netzwerk und Client vorhanden waren und der Ablauf durchlief (Patches können trotzdem einzeln fehlschlagen).
  @discardableResult
  func syncOfflineProgressToServer() async -> Bool {
    guard let c = client, isNetworkReachable else { return false }
    ensureLocalProgressLoadedFromDisk()
    await player.flushPendingPlaySessionSync()
    await flushPendingOfflineListeningTime()
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
        pendingLocalProgressSyncKeys.remove(p.progressLookupKey)
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
      repairContinueListeningShelfFromLocalProgressOnly()
      return
    }
    guard !libId.isEmpty else {
      repairContinueListeningShelfFromLocalProgressOnly()
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
        repairContinueListeningShelfFromLocalProgressOnly()
        syncContinueListeningShelvesWithProgress()
        injectEbookContinueReadingShelfIfNeeded()
        return
      }
    }
    repairContinueListeningShelfFromLocalProgressOnly()
    syncContinueListeningShelvesWithProgress()
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
    if selectedPodcastLibrary == nil || selectedPodcastLibrary?.id != libId {
      selectedPodcastLibrary = ABSLibrary(id: libId, name: "Podcasts", mediaType: "podcast", displayOrder: nil)
      podcastEpisodes = []
      podcastLibraryPage = 0
      podcastLibraryTotal = 0
      applyPodcastListFromDisk(libraryId: libId)
    } else if podcastEpisodes.isEmpty {
      applyPodcastListFromDisk(libraryId: libId)
    }
    let ascending = podcastCatalogSortField == .random ? true : !podcastCatalogSortDescending
    let sortKey = podcastCatalogSortField.apiSortParameter
    if let account = cacheAccountURL(),
      let rows = LibraryDiskCache.loadPodcastShows(
        account: account, libraryId: libId, sortField: sortKey, ascending: ascending,
        decoder: ABSJSON.decoder())
    {
      podcastShows = rows
    }
    if !startShelves.isEmpty, !isNetworkReachable, !offlineHomeUIActive {
      repairContinueListeningShelfFromLocalProgressOnly()
    }
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

  func applyAuthorizeSession(_ auth: ABSLoginResponse, persistToDisk: Bool = true) {
    applyAuthorizeUser(auth.user, persistToDisk: persistToDisk)
    if let settings = auth.serverSettings {
      serverSettings = settings
    }
  }

  func applyAuthorizeUser(_ user: ABSUser, persistToDisk: Bool = true) {
    isServerRoot = user.isRoot
    isServerAdmin = user.isAdmin
    applyUserProgress(user.mediaProgress, persistToDisk: persistToDisk)
    applyUserBookmarks(user.bookmarks, persistToDisk: persistToDisk)
  }

  func fetchServerUsers() async throws -> [ABSAdminUserSummary] {
    guard isServerRoot, let c = client else { return [] }
    return try await c.serverUsers()
  }

  func fetchServerOnlineUserIds() async throws -> Set<String> {
    guard isServerRoot, let c = client else { return [] }
    return try await c.serverOnlineUserIds()
  }

  func fetchServerUserDetail(userId: String) async throws -> ABSAdminUserDetail {
    guard isServerRoot, let c = client else {
      throw ABSAPIError.emptyBody
    }
    let data = try await c.serverUserDetailData(userId: userId)
    var detail = try ABSAdminUserDetail.decode(data: data)
    let enriched = await enrichAdminMediaProgressRows(detail.mediaProgress, client: c)
    detail = ABSAdminUserDetail(
      id: detail.id,
      username: detail.username,
      type: detail.type,
      lastSeen: detail.lastSeen,
      mediaProgress: enriched
    )
    return detail
  }

  private func localDisplayMetadataForAdminProgress(
    libraryItemId: String,
    episodeId: String?
  ) -> (title: String, author: String)? {
    let eid = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !eid.isEmpty {
      for ep in podcastEpisodes where ep.libraryItemId == libraryItemId && ep.episodeId == eid {
        return (ep.episodeTitle, ep.showTitle)
      }
    }
    for b in mergedLocalCatalogBooks() + podcastShows + podcastSearchBooks
    where b.id == libraryItemId
    {
      return (b.displayTitle, b.displayAuthorsCardLine)
    }
    return nil
  }

  private func mergeAdminProgressRowMetadata(
    _ row: ABSAdminMediaProgressRow,
    title: String,
    author: String
  ) -> ABSAdminMediaProgressRow {
    row.withDisplayMetadata(
      title: row.needsTitleEnrichment ? title : row.resolvedDisplayTitle,
      author: row.needsAuthorEnrichment ? author : row.resolvedDisplayAuthor
    )
  }

  private func enrichAdminMediaProgressRows(
    _ rows: [ABSAdminMediaProgressRow],
    client: ABSAPIClient
  ) async -> [ABSAdminMediaProgressRow] {
    guard !rows.isEmpty else { return rows }
    var out: [ABSAdminMediaProgressRow] = []
    out.reserveCapacity(rows.count)
    var pending: [ABSAdminMediaProgressRow] = []
    for row in rows {
      var working = row
      if working.needsDisplayMetadataEnrichment,
        let meta = localDisplayMetadataForAdminProgress(
          libraryItemId: row.libraryItemId,
          episodeId: row.episodeId
        )
      {
        working = mergeAdminProgressRowMetadata(working, title: meta.title, author: meta.author)
      }
      if working.needsDisplayMetadataEnrichment {
        pending.append(working)
      } else {
        out.append(working)
      }
    }
    guard !pending.isEmpty, isNetworkReachable else {
      out.append(contentsOf: pending)
      return out.sorted {
        ($0.lastUpdate ?? 0) > ($1.lastUpdate ?? 0)
      }
    }
    await withTaskGroup(of: (Int, ABSAdminMediaProgressRow).self) { group in
      for (index, row) in pending.enumerated() {
        group.addTask { [weak self] in
          guard let self else { return (index, row) }
          let enriched = await self.fetchAdminProgressRowMetadata(row, client: client)
          return (index, enriched)
        }
      }
      var fetched: [(Int, ABSAdminMediaProgressRow)] = []
      fetched.reserveCapacity(pending.count)
      for await pair in group {
        fetched.append(pair)
      }
      out.append(contentsOf: fetched.sorted { $0.0 < $1.0 }.map(\.1))
    }
    return out.sorted { ($0.lastUpdate ?? 0) > ($1.lastUpdate ?? 0) }
  }

  private func fetchAdminProgressRowMetadata(
    _ row: ABSAdminMediaProgressRow,
    client: ABSAPIClient
  ) async -> ABSAdminMediaProgressRow {
    do {
      let data = try await client.itemResponseData(id: row.libraryItemId, expanded: true)
      let eid = row.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !eid.isEmpty,
        let epMeta = ABSAdminMediaProgressRow.episodeMetadata(fromItemJSON: data, episodeId: eid)
      {
        return mergeAdminProgressRowMetadata(row, title: epMeta.title, author: epMeta.author)
      }
      let item = try ABSJSON.decoder().decode(ABSBook.self, from: data)
      return mergeAdminProgressRowMetadata(
        row,
        title: item.displayTitle,
        author: item.displayAuthorsCardLine
      )
    } catch {
      return row
    }
  }

  func fetchServerUserListeningSessions(userId: String) async throws -> ABSListeningSessionsPayload {
    guard isServerRoot, let c = client else {
      return ABSListeningSessionsPayload(total: 0, numPages: 0, page: 0, itemsPerPage: 0, sessions: [])
    }
    return try await c.serverUserListeningSessions(userId: userId)
  }

  func fetchServerLibraryStats(libraryId: String) async throws -> ABSLibraryStatsResponse {
    guard isServerRoot, let c = client else { throw ABSAPIError.emptyBody }
    return try await c.serverLibraryStats(libraryId: libraryId)
  }

  func scanServerLibrary(libraryId: String) async throws {
    guard isServerRoot, let c = client, isNetworkReachable else { return }
    try await c.scanServerLibrary(libraryId: libraryId)
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
        author: book.displayAuthors,
        libraryItemId: book.id,
        localFileURL: cached.url,
        format: cached.format
      )
      return
    }

    guard mayUseServerNetwork, isNetworkReachable, let c = client, let account = cacheAccountURL() else {
      errorMessage =
        "No server connection. Open the eBook once while online to cache it on this device."
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
        author: resolved.displayAuthors,
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

  /// Neueren `lastUpdate` behalten; bei abweichendem `isFinished` gewinnt die Server-Zeile — außer bei aktiver Wiedergabe / frischerem lokalem „nicht fertig“.
  private func mergedUserMediaProgress(
    existing: ABSUserMediaProgress?,
    incoming: ABSUserMediaProgress
  ) -> ABSUserMediaProgress {
    guard let existing else { return incoming }
    let key = incoming.progressLookupKey
    if pendingLocalProgressSyncKeys.contains(key) {
      if !existing.isFinished, incoming.isFinished {
        return existing
      }
      let localTs = existing.lastUpdate ?? 0
      let serverTs = incoming.lastUpdate ?? 0
      if existing.currentTime + 1 >= incoming.currentTime || localTs >= serverTs {
        return existing
      }
    }
    if incoming.isFinished != existing.isFinished {
      if isActivelyPlayingProgress(existing) || isActivelyPlayingProgress(incoming) {
        return existing.isFinished ? incoming : existing
      }
      if !existing.isFinished, (existing.lastUpdate ?? 0) >= (incoming.lastUpdate ?? 0) {
        return existing
      }
      if existing.isFinished, !incoming.isFinished { return incoming }
      return incoming
    }
    let t0 = existing.lastUpdate ?? 0
    let t1 = incoming.lastUpdate ?? 0
    if t0 > t1 { return existing }
    if t1 > t0 { return incoming }
    return existing.currentTime >= incoming.currentTime ? existing : incoming
  }

  /// Katalog nutzt Server-Filter auf Fortschritt (nicht „Alle“ / nur Download/eBook).
  private func catalogUsesProgressServerFilter() -> Bool {
    switch libraryCatalogQuickFilter {
    case .inProgress, .finished, .notStarted:
      return true
    case .downloaded, .ebook, nil:
      break
    }
    let f = activeLibraryFilter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return f.hasPrefix("progress.")
  }

  /// Nur wenn die Zeile im gefilterten Katalog fehlen würde und kein Stub lokal existiert.
  private func needsFullLibraryReloadAfterAudiobookProgressChange(bookId: String, finished: Bool) -> Bool {
    guard catalogUsesProgressServerFilter() else { return false }
    if libraryCatalogQuickFilter == .finished, finished {
      return !books.contains { $0.id == bookId }
    }
    if libraryCatalogQuickFilter == .inProgress, !finished {
      return !books.contains { $0.id == bookId } && lookupBookStub(id: bookId) == nil
    }
    return false
  }

  private func needsFullLibraryReloadAfterAudiobookProgressDiscard(bookId: String) -> Bool {
    guard catalogUsesProgressServerFilter() else { return false }
    if libraryCatalogQuickFilter == .notStarted {
      return !books.contains { $0.id == bookId } && lookupBookStub(id: bookId) == nil
    }
    let f = activeLibraryFilter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if f.contains("not-started") {
      return !books.contains { $0.id == bookId } && lookupBookStub(id: bookId) == nil
    }
    return false
  }

  private func lookupBookStub(id: String) -> ABSBook? {
    books.first { $0.id == id }
      ?? startBooks.first { $0.id == id }
      ?? searchBooks.first { $0.id == id }
      ?? downloadedShelfBooks.first { $0.id == id }
  }

  /// Liste ohne Netz-Neuladen anpassen; `progressByItemId` aktualisiert die Karten per Live-State.
  private func patchBooksCatalogAfterAudiobookProgressChange(bookId: String, finished: Bool) {
    guard booksBrowseSection == .books, selectedBooksLibrary != nil else { return }

    switch libraryCatalogQuickFilter {
    case .inProgress, .notStarted:
      if finished { removeBookFromCatalogList(bookId) }
      else if !books.contains(where: { $0.id == bookId }), let stub = lookupBookStub(id: bookId) {
        books.insert(stub, at: 0)
      }
    case .finished:
      if finished {
        if !books.contains(where: { $0.id == bookId }), let stub = lookupBookStub(id: bookId) {
          books.insert(stub, at: 0)
        }
      } else {
        removeBookFromCatalogList(bookId)
      }
    case .downloaded, .ebook, nil:
      let f = activeLibraryFilter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard f.hasPrefix("progress.") else { return }
      if f.contains("in-progress") || f.contains("not-started") {
        if finished { removeBookFromCatalogList(bookId) }
        else if !books.contains(where: { $0.id == bookId }), let stub = lookupBookStub(id: bookId) {
          books.insert(stub, at: 0)
        }
      } else if f.contains("finished") {
        if finished, !books.contains(where: { $0.id == bookId }), let stub = lookupBookStub(id: bookId) {
          books.insert(stub, at: 0)
        } else if !finished {
          removeBookFromCatalogList(bookId)
        }
      }
    }
  }

  private func removeBookFromCatalogList(_ bookId: String) {
    books.removeAll { $0.id == bookId }
  }

  /// Nach Fortschritt-Reset: „not started“ — Karte über Live-State, Liste nur bei Fortschritts-Filtern anpassen.
  private func patchBooksCatalogAfterAudiobookProgressDiscard(bookId: String) {
    guard booksBrowseSection == .books, selectedBooksLibrary != nil else { return }

    switch libraryCatalogQuickFilter {
    case .inProgress, .finished:
      removeBookFromCatalogList(bookId)
    case .notStarted:
      if !books.contains(where: { $0.id == bookId }), let stub = lookupBookStub(id: bookId) {
        books.insert(stub, at: 0)
      }
    case .downloaded, .ebook, nil:
      let f = activeLibraryFilter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard f.hasPrefix("progress.") else { return }
      if f.contains("in-progress") || f.contains("finished") {
        removeBookFromCatalogList(bookId)
      } else if f.contains("not-started"),
        !books.contains(where: { $0.id == bookId }),
        let stub = lookupBookStub(id: bookId)
      {
        books.insert(stub, at: 0)
      }
    }
  }

  private func applyLocalMarkFinished(libraryItemId: String, episodeId: String?) {
    let key: String = {
      let ep = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if ep.isEmpty { return libraryItemId }
      return "\(libraryItemId)-\(ep)"
    }()
    let existing = progressByItemId[key]
    let bookDur =
      books.first(where: { $0.id == libraryItemId })?.media.duration
      ?? startBooks.first(where: { $0.id == libraryItemId })?.media.duration
    let dur = max(existing?.duration ?? 0, bookDur ?? 0, existing?.currentTime ?? 0, 1)
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let ep = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    progressByItemId[key] = ABSUserMediaProgress(
      mediaProgressServerId: existing?.mediaProgressServerId,
      libraryItemId: libraryItemId,
      episodeId: ep.isEmpty ? nil : ep,
      duration: dur,
      progress: 1,
      currentTime: dur,
      isFinished: true,
      lastUpdate: max(now, (existing?.lastUpdate ?? 0) + 1)
    )
    persistProgressToDisk()
  }

  private func refreshStartDashboardIfNeeded() async {
    guard mainTab == .start else { return }
    await loadStartDashboard()
  }

  private func applyLocalMarkUnfinished(libraryItemId: String, episodeId: String?) {
    let key: String = {
      let ep = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if ep.isEmpty { return libraryItemId }
      return "\(libraryItemId)-\(ep)"
    }()
    guard let existing = progressByItemId[key] else { return }
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    progressByItemId[key] = ABSUserMediaProgress(
      mediaProgressServerId: existing.mediaProgressServerId,
      libraryItemId: existing.libraryItemId,
      episodeId: existing.episodeId,
      duration: existing.duration,
      progress: existing.progress,
      currentTime: existing.currentTime,
      isFinished: false,
      lastUpdate: max(now, (existing.lastUpdate ?? 0) + 1)
    )
    persistProgressToDisk()
  }

  /// Nach „Fertig“: Server-Zeile übernehmen oder lokalen Eintrag entfernen (ABS liefert den Eintrag oft nicht mehr).
  private func reconcileProgressAfterMarkFinished(libraryItemId: String, episodeId: String?) {
    let key: String = {
      let ep = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if ep.isEmpty { return libraryItemId }
      return "\(libraryItemId)-\(ep)"
    }()
    if let row = progressByItemId[key], row.isFinished {
      persistProgressToDisk()
      return
    }
    progressByItemId.removeValue(forKey: key)
    persistProgressToDisk()
  }

  private func persistProgressToDisk() {
    guard let account = cacheAccountURL() else { return }
    try? LibraryDiskCache.saveProgress(account: account, list: Array(progressByItemId.values))
  }

  /// Disk-Cache (`LibraryDiskCache`) in `progressByItemId` mergen — z. B. Offline-Home ohne vorherigen `/authorize`.
  private func ensureLocalProgressLoadedFromDisk() {
    guard let account = cacheAccountURL() else { return }
    let dec = ABSJSON.decoder()
    guard let list = LibraryDiskCache.loadProgress(account: account, decoder: dec), !list.isEmpty else { return }
    applyUserProgress(list, persistToDisk: false)
  }

  /// Veraltetes `/personalized` (z. B. nach „Fertig“) — sonst kurzer Continue-Flash beim Bibliotheks-Restore.
  private func invalidateCachedPersonalizedHome(libraryId: String?) {
    let lid = libraryId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !lid.isEmpty, let account = cacheAccountURL() else { return }
    let url = account
      .appendingPathComponent("personalized", isDirectory: true)
      .appendingPathComponent("\(lid).json")
    try? FileManager.default.removeItem(at: url)
  }

  private func applyUserProgress(_ list: [ABSUserMediaProgress]?, persistToDisk: Bool = true) {
    for p in list ?? [] {
      let key = p.progressLookupKey
      progressByItemId[key] = mergedUserMediaProgress(existing: progressByItemId[key], incoming: p)
    }
    syncLastPlayedPreferenceWithServerProgress()
    syncContinueListeningShelvesWithProgress()
    guard persistToDisk else { return }
    persistProgressToDisk()
  }

  private func resumeProgressOrderedBefore(_ a: ABSUserMediaProgress, _ b: ABSUserMediaProgress) -> Bool {
    let t0 = a.lastUpdate ?? 0
    let t1 = b.lastUpdate ?? 0
    if t0 != t1 { return t0 < t1 }
    return a.currentTime < b.currentTime
  }

  /// Kein Mini-Player für bloße Klicks ohne echte Position.
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
    localContinueAudiobookBookCandidates().compactMap { progressByItemId[$0.id] }
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

  /// iTunes-Storefront: ABS-Server-Sprache, sonst Geräte-Region.
  func podcastDirectoryCountryCode() -> String {
    ABSPodcastCharts.countryCode(serverLanguage: serverSettings?.language)
  }

  func clearPodcastCharts() {
    podcastChartsHits = []
    podcastChartsLoading = false
  }

  func loadPodcastCharts(force: Bool = false) async {
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    if podcastChartsLoading { return }
    if !force, !podcastChartsHits.isEmpty { return }
    podcastChartsLoading = true
    defer { podcastChartsLoading = false }
    do {
      let country = podcastDirectoryCountryCode()
      podcastChartsHits = try await ABSPodcastCharts.fetchTopPodcasts(country: country)
      errorMessage = nil
    } catch {
      if Task.isCancelled || Self.isBenignCancellationError(error) { return }
      errorMessage = error.localizedDescription
      podcastChartsHits = []
    }
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
    let region = podcastDirectoryCountryCode()
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
    guard podcastSubscribeInProgressDirectoryHitId == nil else { return false }
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
      _ = try await c.createPodcastInLibrary(jsonBody: body)
      await refreshProgressFromServer()
      await reloadPodcastShowsCatalog()
      await loadStartDashboard()
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  /// Entfernt eine Podcast-Sendung von der Bibliothek (`DELETE /api/items/:id`). Erfordert Lösch-Rechte auf dem Server.
  @discardableResult
  func removePodcastShowFromLibrary(showLibraryItemId: String) async -> Bool {
    guard let c = client else { return false }
    guard isNetworkReachable else {
      errorMessage = "Keine Netzwerkverbindung."
      return false
    }
    let sid = showLibraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return false }

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
      return false
    }

    errorMessage = nil
    podcastRssFeedLoadInProgressShowIds.remove(sid)
    clearPodcastRssFeedCache(forShowId: sid)
    clearPodcastAutoDownloadSettingsDraft()

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
    return true
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
