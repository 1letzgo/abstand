import Combine
import Foundation
import Network
import os
import ReadiumShared
import SwiftData
import SwiftUI
import UIKit

private enum Keys {
  static let server = "abstand_server_url"
  static let token = "abstand_token"
  /// Letzter `authorize`-User — für Readium/eBook-Fortschritt vor erneutem `/authorize`.
  static let sessionUserId = "abstand_session_user_id"
  /// Server-Standardbibliothek aus letztem `/authorize` (Lazy-Bootstrap ohne erneutes Authorize).
  static let userDefaultLibraryId = "abstand_user_default_library_id"
  /// Legacy; wird nach `booksLibrary` migriert.
  static let library = "abstand_library_id"
  static let booksLibrary = "abstand_books_library_id"
  static let ebooksLibrary = "abstand_ebooks_library_id"
  static let podcastsLibrary = "abstand_podcasts_library_id"
  /// Bewusst keine Bibliothek gewählt (Tabs ausblenden, kein Auto-Pick).
  static let librarySelectionNone = "__abstand_no_library__"
  static let downloads = "abstand_downloaded_ids"
  static let lastPlayedItemId = "abstand_last_played_library_item_id"
  static let startDisabledCategories = "abstand_start_disabled_categories"
  static let homeBrowseCategory = "abstand_home_browse_category"
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
  /// Vollplayer-Sheet beim Start der Wiedergabe (nicht im Offline-Home).
  static let openPlayerWhenStartPlaying = "abstand_open_player_when_start_playing"
  /// Kumulierte Hörsekunden ohne Play-Session (lokale Downloads), später per Session-Flush (Absorb).
  static let pendingOfflineListeningSeconds = "abstand_pending_offline_listening_seconds"
  /// Fortschrittsschlüssel, die offline/lokal als fertig markiert wurden (bis Server bestätigt).
  static let localFinishedProgressKeys = "abstand_local_finished_progress_keys"
  static let browseAuthorsSortField = "abstand_browse_authors_sort_field"
  static let browseAuthorsSortDescending = "abstand_browse_authors_sort_desc"
  static let browseNarratorsSortField = "abstand_browse_narrators_sort_field"
  static let browseNarratorsSortDescending = "abstand_browse_narrators_sort_desc"
  static let browseSeriesSortField = "abstand_browse_series_sort_field"
  static let browseSeriesSortDescending = "abstand_browse_series_sort_desc"
  static let browseCollectionsSortField = "abstand_browse_collections_sort_field"
  static let browseCollectionsSortDescending = "abstand_browse_collections_sort_desc"
  static let browseGenresSortField = "abstand_browse_genres_sort_field"
  static let browseGenresSortDescending = "abstand_browse_genres_sort_desc"
  static let browseTagsSortField = "abstand_browse_tags_sort_field"
  static let browseTagsSortDescending = "abstand_browse_tags_sort_desc"
  /// Podcast-Tab in der Tab-Leiste (gecacht; unabhängig vom Bootstrap-Fetch).
  static let showPodcastsTab = "abstand_show_podcasts_tab"
  /// eBooks/Supplementary als eigener Tab statt Einträge im Books-Tab.
  /// Akzentfarbe als „r,g,b“ (0…1) in sRGB.
  static let appearanceAccentRGB = "abstand_appearance_accent_rgb"
  static let appearanceAccentRGBDark = "abstand_appearance_accent_rgb_dark"
  static let appearanceAccentRGBLight = "abstand_appearance_accent_rgb_light"
  static let appearanceMode = "abstand_appearance_mode"
  static let libraryBookCardStyle = "abstand_library_book_card_style"
  static let libraryPodcastCardStyle = "abstand_library_podcast_card_style"
  static let translationTargetLanguageCode = "abstand_translation_target_language"
}

/// Ergebnis eines Online-Continue-Refreshs (Lazy-Bootstrap / Fallback-Entscheidung).
struct ContinueRefreshAttemptResult {
  var appliedOnline = false
  var error: Error?
  /// `true`, sobald `loadStartDashboard` tatsächlich einen Request gestartet hat
  /// (nicht nur früh per Cache/Guard zurückgekehrt ist). Wird gebraucht, um
  /// Server-Erreichbarkeit nicht ungeprüft aus einem übersprungenen Refresh abzuleiten.
  var attemptedNetwork = false
}

/// Abgebrochene Requests/Tasks nicht als Fehlerdialog anzeigen.
enum AbstandErrorFilter {
  static func isBenignCancellationMessage(_ message: String) -> Bool {
    let desc = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !desc.isEmpty else { return false }
    if desc == "cancelled" || desc == "canceled" { return true }
    if desc.contains("cancelled") || desc.contains("canceled") { return true }
    if desc.contains("error -999") { return true }
    return false
  }

  static func isBenignCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
    if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return true }
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error,
      isBenignCancellation(underlying)
    {
      return true
    }
    if isBenignCancellationMessage(error.localizedDescription) { return true }
    return false
  }

  /// Timeouts/Netz-Hiccups beim Kaltstart mit Cache — kein Fehlerdialog.
  static func isTransientNetworkError(_ error: Error) -> Bool {
    if let url = error as? URLError {
      switch url.code {
      case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed:
        return true
      default:
        break
      }
    }
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain,
      [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
       NSURLErrorCannotConnectToHost]
        .contains(ns.code)
    {
      return true
    }
    let desc = error.localizedDescription.lowercased()
    return desc.contains("timed out") || desc.contains("timeout")
  }
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
  case search = "Search"
  case series = "Series"
  case collections = "Collections"
  case genres = "Genres"
  case tags = "Tags"
  case author = "Authors"
  case narrators = "Narrators"
  case ebooks = "eBooks"
  case ebooksSupplementary = "Supplementary"

  var id: String { rawValue }

  /// Unterbereiche im Audiobook-Bereich des gemeinsamen Medien-Tabs.
  /// eBooks/Supplementary sind als Katalog-Filter verfügbar (nicht als eigener Strip-Abschnitt).
  static let audiobookStripOrder: [BooksBrowseSection] = [
    .books, .series, .author, .collections, .genres, .narrators, .tags,
  ]

  var systemImage: String {
    switch self {
    case .books: return "books.vertical"
    case .search: return "magnifyingglass"
    case .series: return "rectangle.stack"
    case .collections: return "folder"
    case .genres: return "sparkles"
    case .tags: return "tag"
    case .author: return "person.text.rectangle"
    case .narrators: return "waveform"
    case .ebooks: return "book.closed"
    case .ebooksSupplementary: return "books.vertical.fill"
    }
  }
}

/// Podcast-Tab-Streifen: Search / New / Show-`libraryItemId`.
enum PodcastCatalogStripSection {
  static let search = "__search__"
  static let newEpisodes = "__new__"
}

/// Schnellfilter im Bücher-Katalog (Toolbar neben Sort).
enum LibraryCatalogQuickFilter: String, CaseIterable, Identifiable, Hashable {
  case inProgress
  case finished
  case notStarted
  case downloaded
  case ebooks
  case ebooksSupplementary

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .inProgress: return "In progress"
    case .finished: return "Finished"
    case .notStarted: return "Not started"
    case .downloaded: return "Downloaded"
    case .ebooks: return "eBooks"
    case .ebooksSupplementary: return "Supplementary eBooks"
    }
  }

  var menuSystemImage: String {
    switch self {
    case .inProgress: return "play.circle"
    case .finished: return "checkmark.circle"
    case .notStarted: return "circle"
    case .downloaded: return "arrow.down.circle"
    case .ebooks: return "book.closed"
    case .ebooksSupplementary: return "books.vertical.fill"
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
    case .ebooks: return key(group: "ebooks", value: "ebook")
    case .ebooksSupplementary: return key(group: "ebooks", value: "supplementary")
    }
  }

  var summaryPrefix: String {
    switch self {
    case .inProgress, .finished, .notStarted: return "Progress"
    case .downloaded: return "Downloaded"
    case .ebooks: return "eBooks"
    case .ebooksSupplementary: return "Supplementary"
    }
  }

  var summaryDetail: String? {
    switch self {
    case .inProgress: return "In progress"
    case .finished: return "Finished"
    case .notStarted: return "Not started"
    case .downloaded: return nil
    case .ebooks: return nil
    case .ebooksSupplementary: return nil
    }
  }
}

/// Navigation zu Autor-, Serien- oder Sprecher-Detail (eigene Liste, nicht Hauptkatalog filtern).
struct BooksEntityDetailNav: Hashable, Identifiable {
  enum Kind: String, Hashable {
    case author
    case series
    case narrator
    case collection
    case genre
    case tag
  }

  let kind: Kind
  let entityId: String
  let title: String
  let numBooks: Int?
  /// Bibliothek des Quell-Titels (eBooks vs. Hörbücher) — Entity-API/Filter sonst falsche Library.
  var libraryId: String? = nil

  var id: String {
    if let lib = libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !lib.isEmpty {
      return "\(kind.rawValue):\(lib):\(entityId)"
    }
    return "\(kind.rawValue):\(entityId)"
  }

  var libraryFilter: String {
    let b64 = Data(entityId.utf8).base64EncodedString()
    switch kind {
    case .author: return "authors.\(b64)"
    case .series: return "series.\(b64)"
    case .narrator: return "narrators.\(b64)"
    case .collection: return "collections.\(b64)"
    case .genre: return "genres.\(b64)"
    case .tag: return "tags.\(b64)"
    }
  }

  var filterSummaryPrefix: String {
    switch kind {
    case .author: return "Author"
    case .series: return "Series"
    case .narrator: return "Narrator"
    case .collection: return "Collection"
    case .genre: return "Genre"
    case .tag: return "Tag"
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

/// Sortierung Genres/Tags (lokal, nach vollständiger Liste).
enum BooksBrowseFacetSortField: String, CaseIterable, Identifiable, Hashable {
  case name
  case bookCount

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .name: return "Name"
    case .bookCount: return "Number of books"
    }
  }
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

extension CatalogSortField: AbstandSortMenuField {
  var suppressesSortOrderPicker: Bool { self == .random }
}

extension PodcastCatalogSortField: AbstandSortMenuField {
  var suppressesSortOrderPicker: Bool { self == .random }
}

extension BooksBrowseAuthorsSortField: AbstandSortMenuField {}
extension BooksBrowseNarratorsSortField: AbstandSortMenuField {}
extension BooksBrowseSeriesSortField: AbstandSortMenuField {
  var suppressesSortOrderPicker: Bool { self == .random }
}
extension BooksBrowseFacetSortField: AbstandSortMenuField {}
extension BooksBrowseCollectionsSortField: AbstandSortMenuField {}

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
  private static let initialBrowseGenresSort: (field: BooksBrowseFacetSortField, descending: Bool) =
    loadBrowseGenresSortState()
  private static let initialBrowseTagsSort: (field: BooksBrowseFacetSortField, descending: Bool) =
    loadBrowseTagsSortState()

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
  /// Set, wenn eine Podcast-Folge im gesperrten/offline Zustand beendet wurde — dann ist die
  /// Liste lokal erleichtert, aber kein Server-Reload gelaufen. Beim nächsten Vordergrund-Wechsel
  /// via `applyPendingPodcastRefreshIfNeeded()` nachladen, sonst bleibt die Liste u. U. leer.
  @Published private(set) var pendingPodcastRefreshOnResume = false
  /// Podcast-Sendungen der Bibliothek (Katalog), für die Cover-Leiste.
  @Published var podcastShows: [ABSBook] = []
  @Published private(set) var podcastShowsLoading = false
  @Published var podcastDirectorySearchHits: [ABSPodcastDirectorySearchHit] = []
  @Published private(set) var podcastDirectorySearchLoading = false
  @Published private(set) var podcastChartsHits: [ABSPodcastDirectorySearchHit] = []
  @Published private(set) var podcastChartsLoading = false
  /// `nil` = Top-Charts gesamt („All“).
  @Published var podcastChartsSelectedGenreId: Int?
  /// Nur Add-Podcast-View: manuelles Storefront; `nil` = Auto (Server-Sprache / Gerät).
  @Published var podcastDirectoryCountryOverride: String?
  @Published private(set) var podcastDirectoryEffectiveCountry: String = "us"
  private var podcastChartsLoadedCountry: String?
  private var podcastChartsLoadedGenreId: Int?
  @Published private(set) var podcastSubscribeInProgressDirectoryHitId: String?
  /// `nil` = „New“-Ansicht (recent-Feed); gesetzt = nur diese Sendung (`podcastFilteredEpisodes`).
  @Published var podcastSelectedShowId: String?
  @Published var podcastFilteredEpisodes: [ABSPodcastEpisodeListItem] = []
  /// Geladene Sendungs-Folgen für Scroll-Panes im Podcast-Tab (unabhängig von `podcastSelectedShowId`).
  private var podcastFilteredEpisodesByShowId: [String: [ABSPodcastEpisodeListItem]] = [:]
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
  /// Server-Metadaten der Podcast-Show für Teleprompter und Recap.
  @Published var podcastShowTranscriptionLanguage = ""
  @Published private(set) var podcastShowTranscriptionLanguageShowId: String?
  @Published private(set) var podcastShowTranscriptionLanguageSaving = false
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
  /// Aktives Regal in der Home-Browse-Leiste (Kategorie-Key aus Appearance → Home).
  @Published var homeBrowseCategory: String = {
    let saved = UserDefaults.standard.string(forKey: Keys.homeBrowseCategory) ?? ""
    if ABSStartShelfLocalization.isHomeBrowseContinueCategory(saved) {
      return ABSStartShelfLocalization.homeBrowseContinueSectionID
    }
    if ABSStartShelfLocalization.isHomeBrowseRecentCategory(saved) {
      return ABSStartShelfLocalization.homeBrowseRecentSectionID
    }
    if !saved.isEmpty { return saved }
    return ABSStartShelfLocalization.homeBrowseContinueSectionID
  }()
  @Published var progressByItemId: [String: ABSUserMediaProgress] = [:]
  /// Audiobookshelf-User-ID der aktiven Session (Lesestand E-Books pro User).
  private(set) var sessionUserId: String = ""
  @Published private(set) var sessionUsername: String = ""
  @Published private(set) var sessionUserType: String = ""
  @Published private(set) var bookmarks: [ABSAudioBookmark] = []
  @Published var ebookReaderSession: EbookReaderPresentation?
  @Published var isPreparingEbook = false
  /// Debounce für `PATCH /api/me/progress` mit `ebookProgress` (Lese-Sync wie ABS-Web).
  private var ebookProgressSyncTask: Task<Void, Never>?
  private var pendingEbookProgressSync: (libraryItemId: String, fraction: Double)?
  private var lastSyncedEbookFractionByItemId: [String: Double] = [:]
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
  /// Podcast-Tab Katalog-Suche (Shows + Episoden innerhalb der Podcast-Bibliothek).
  @Published var podcastLibrarySearchText: String = ""
  @Published var podcastLibrarySearchShows: [ABSBook] = []
  @Published var podcastLibrarySearchEpisodes: [ABSPodcastEpisodeListItem] = []
  /// Aktiver Streifen im Podcast-Tab (`__search__`, `__new__` oder Show-ID).
  @Published var podcastCatalogStripSectionId: String = PodcastCatalogStripSection.newEpisodes
  /// Server-Items-Filter für den Bücher-Katalog.
  @Published var activeLibraryFilter: String?
  /// Anzeige unter der Suche: wonach der Bücher-Katalog gefiltert ist.
  @Published var activeLibraryFilterSummary: String?
  @Published var libraryCatalogQuickFilter: LibraryCatalogQuickFilter?
  @Published var booksBrowseSection: BooksBrowseSection = .books
  @Published private(set) var browseEbooks: [ABSBook] = []
  @Published private(set) var browseEbooksSupplementary: [ABSBook] = []
  @Published private(set) var browseEbooksLoading = false
  @Published private(set) var browseEbooksTotal = 0
  private var browseEbooksNextPage = 0
  @Published private(set) var browseAuthors: [ABSLibraryAuthorListItem] = []
  @Published private(set) var browseNarrators: [ABSLibraryNarratorListItem] = []
  @Published private(set) var browseSeries: [ABSLibrarySeriesListItem] = []
  @Published private(set) var browseCollections: [ABSLibraryCollectionListItem] = []
  @Published private(set) var browseGenres: [BooksBrowseGenreListItem] = []
  private var browseGenresFetched: [BooksBrowseGenreListItem] = []
  @Published private(set) var browseTags: [BooksBrowseTagListItem] = []
  private var browseTagsFetched: [BooksBrowseTagListItem] = []
  @Published private(set) var browseTagsLoading = false
  /// Podcast-Tab: gecachte Nutzer-/Server-Präferenz (nicht erst nach `libraries`-Fetch).
  @Published var showPodcastsTab: Bool = AppModel.loadShowPodcastsTabCached() {
    didSet {
      UserDefaults.standard.set(showPodcastsTab, forKey: Keys.showPodcastsTab)
      clampMediaCatalogKindIfNeeded()
    }
  }
  @Published private(set) var browseCollectionBooksById: [String: [ABSBook]] = [:]
  @Published private(set) var browseAuthorsLoading = false
  @Published private(set) var browseNarratorsLoading = false
  @Published private(set) var browseSeriesLoading = false
  @Published private(set) var browseCollectionsLoading = false
  @Published private(set) var browseGenresLoading = false
  @Published private(set) var browseSeriesTotal = 0
  @Published private(set) var browseAuthorsTotal = 0
  @Published private(set) var browseCollectionsTotal = 0
  @Published private(set) var browseNarratorCoverItemIdByNarratorName: [String: String] = [:]
  /// Pro Tab eigener Navigationszustand (sonst zeigt z. B. Settings den Library-Autor).
  @Published var libraryEntityDetailNav: BooksEntityDetailNav?
  @Published var homeEntityDetailNav: BooksEntityDetailNav?
  @Published var searchEntityDetailNav: BooksEntityDetailNav?
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
  @Published var browseGenresSortField: BooksBrowseFacetSortField = AppModel.initialBrowseGenresSort.field {
    didSet { UserDefaults.standard.set(browseGenresSortField.rawValue, forKey: Keys.browseGenresSortField) }
  }
  @Published var browseGenresSortDescending: Bool = AppModel.initialBrowseGenresSort.descending {
    didSet { UserDefaults.standard.set(browseGenresSortDescending, forKey: Keys.browseGenresSortDescending) }
  }
  @Published var browseTagsSortField: BooksBrowseFacetSortField = AppModel.initialBrowseTagsSort.field {
    didSet { UserDefaults.standard.set(browseTagsSortField.rawValue, forKey: Keys.browseTagsSortField) }
  }
  @Published var browseTagsSortDescending: Bool = AppModel.initialBrowseTagsSort.descending {
    didSet { UserDefaults.standard.set(browseTagsSortDescending, forKey: Keys.browseTagsSortDescending) }
  }

  @Published var mainTab: MainTab = .start
  @Published var mediaCatalogKind: MediaCatalogKind = .audiobooks
  @Published private(set) var nowPlayingSheetPresentationCounter: UInt = 0
  @Published private(set) var nowPlayingSheetDismissCounter: UInt = 0
  @Published var isLoadingLibrary = false
  @Published var isLoadingPodcasts = false
  @Published var errorMessage: String? {
    didSet {
      guard let message = errorMessage, AbstandErrorFilter.isBenignCancellationMessage(message) else {
        return
      }
      errorMessage = nil
    }
  }
  @Published private(set) var isServerAdmin = false
  @Published private(set) var isServerRoot = false
  @Published private(set) var serverSettings: ABSServerSettings?
  @Published private(set) var listeningStats: ABSListeningStatsResponse?
  @Published private(set) var listeningStatsFetchedAt: Date?
  @Published private(set) var listeningStatsLoading = false
  /// Stats-Achievements: zuerst leer/Cache, danach asynchron aus Stats + Fortschritt.
  @Published private(set) var listeningAchievementsSnapshot: ListeningAchievementsSnapshot = .empty
  @Published private(set) var listeningOneTimeSnapshot: ListeningOneTimeAchievementsSnapshot = .empty
  private var listeningAchievementsRebuildTask: Task<Void, Never>?

  /// Erhöhen nach `clearCoverImageCache()`, damit `CoverImageView` neu lädt.
  @Published private(set) var coverImageCacheRevision = 0
  @Published var downloadedItemIds: Set<String> = []
  /// Anzeige-Metadaten für laufende/wartende Downloads — wird beim Download-Start gefüllt,
  /// damit der Download-Manager (Settings) Titel/Show zeigt, BEVOR das Manifest geschrieben ist.
  /// Besonders wichtig für Podcast-Folgen, deren In-Memory-Katalog oft leer ist (Relaunch, BG-Download).
  @Published private(set) var pendingDownloadCatalog: [String: DownloadCatalogEntry] = [:]
  /// Aus `download.json` gebaute Stubs für Home-Regal „Heruntergeladen“ und Offline-Katalog.
  @Published private(set) var downloadedShelfBooks: [ABSBook] = []
  /// Re-Entry-Guard für `refreshDownloadedShelfFromManifests` — verhindert redundante Manifest-Scans
  /// beim Start (Pfadmonitor + Deferred-Restore + `loadStartDashboard` feuern oft gleichzeitig).
  private var isRefreshingDownloadedShelves = false
  @Published private(set) var isNetworkReachable = true
  /// `true`, wenn die aktive Route Wi‑Fi (oder Ethernet) nutzt und erreichbar ist — für Smart-Download nur im WLAN.
  @Published private(set) var networkUsesUnmeteredLAN: Bool = false
  /// Nach 3 Minuten Wiedergabe im WLAN: aktuellen Titel (Hörbuch oder Podcast) automatisch herunterladen.
  /// Akzentfarbe der App (Tabs, Buttons, Highlights) — Einstellungen → Appearance.
  @Published private(set) var appearanceAccentColor: Color = AppTheme.defaultAccent

  /// Akzent aus ColorPicker / Settings — Side-Effects zentral (nicht in `@Published`-`didSet`).
  func setAppearanceAccentColor(_ color: Color) {
    guard !suppressAppearanceAccentSideEffects else {
      appearanceAccentColor = color
      AppTheme.applyAccent(color)
      return
    }
    guard !Self.appearanceAccentColorsEqual(color, appearanceAccentColor) else { return }
    appearanceAccentColor = color
    Self.persistAppearanceAccentColor(
      color,
      slot: Self.currentAppearanceAccentSlot(
        mode: appearanceMode, system: lastSystemColorScheme))
    AppTheme.applyAccent(color)
    applyResolvedPalette()
    player.refreshMiniPlayerBarFillForAppearance()
    appearanceThemeRevision += 1
  }

  /// Dark / Sepia-Light / System — Standard Dark.
  @Published var appearanceMode: AppearanceMode = AppearanceMode.load() {
    didSet {
      guard appearanceMode != oldValue else { return }
      guard !suppressAppearanceAccentSideEffects else { return }
      appearanceMode.persist()
      reapplyAppearance(systemColorScheme: lastSystemColorScheme, previousMode: oldValue)
    }
  }

  /// Library-Zeilen: kompakte Zeile oder große Cover-Karte (Continue-Hero-Stil ohne Play-Pille).
  @Published var libraryBookCardStyle: LibraryBookCardStyle = LibraryBookCardStyle.load() {
    didSet {
      guard libraryBookCardStyle != oldValue else { return }
      libraryBookCardStyle.persist()
    }
  }

  /// Podcast-Episoden: kompakte Zeile oder Cover-Karte (eigenes Setting, unabhängig von Büchern).
  @Published var libraryPodcastCardStyle: LibraryPodcastCardStyle = LibraryPodcastCardStyle.load() {
    didSet {
      guard libraryPodcastCardStyle != oldValue else { return }
      libraryPodcastCardStyle.persist()
    }
  }

  /// Standard-Zielsprache für Teleprompter-Übersetzung (Quelle = Buch-/Transkriptsprache).
  @Published var translationTargetLanguageCode: String = TranslationTargetLanguage.load() {
    didSet {
      let normalized = TranslationTargetLanguage.normalized(translationTargetLanguageCode)
      if normalized != translationTargetLanguageCode {
        translationTargetLanguageCode = normalized
        return
      }
      guard translationTargetLanguageCode != oldValue else { return }
      TranslationTargetLanguage.persist(translationTargetLanguageCode)
    }
  }

  /// Einmal hochzählen nach Paletten- + Akzent-Wechsel — SwiftUI/`.tint` hängen daran (kein Full-UI-Reset).
  @Published private(set) var appearanceThemeRevision = 0

  /// Aktuelle UI-Palette für SwiftUI (`AppTheme.*` allein triggert keine Updates in NavigationLink-Labels).
  @Published private(set) var appearancePalette: AppColorPalette = AppColorPalette.derived(
    from: AppTheme.defaultAccent, isDarkLike: true)

  private var lastSystemColorScheme: ColorScheme = .dark
  private var suppressAppearanceAccentSideEffects = false

  var appearanceAccentMatchesDefault: Bool {
    let slot = Self.currentAppearanceAccentSlot(
      mode: appearanceMode, system: lastSystemColorScheme)
    return Self.appearanceAccentColorsEqual(appearanceAccentColor, slot.defaultAccent)
  }

  /// Für `.preferredColorScheme` am Root; bei `.system` → `nil`.
  var preferredSwiftUIColorScheme: ColorScheme? {
    switch appearanceMode {
    case .dark: return .dark
    case .light: return .light
    case .system: return nil
    }
  }

  /// Toolbar / Sheets: aufgelöstes Hell-Dunkel (Sepia zählt als `.light`).
  var resolvedInterfaceColorScheme: ColorScheme {
    switch appearanceMode {
    case .dark: return .dark
    case .light: return .light
    case .system: return lastSystemColorScheme
    }
  }

  func resetAppearanceAccentToDefault() {
    let slot = Self.currentAppearanceAccentSlot(
      mode: appearanceMode, system: lastSystemColorScheme)
    setAppearanceAccentColor(slot.defaultAccent)
  }

  /// Palette, Akzent pro Slot und UIKit-Chrome — ein Einstieg statt verstreuter Listener.
  func reapplyAppearance(systemColorScheme: ColorScheme, previousMode: AppearanceMode? = nil) {
    if let previousMode {
      let slot = Self.currentAppearanceAccentSlot(mode: previousMode, system: lastSystemColorScheme)
      Self.persistAppearanceAccentColor(appearanceAccentColor, slot: slot)
    } else if appearanceMode == .system {
      let oldSlot = Self.currentAppearanceAccentSlot(mode: .system, system: lastSystemColorScheme)
      let newSlot = Self.currentAppearanceAccentSlot(mode: .system, system: systemColorScheme)
      if oldSlot != newSlot {
        Self.persistAppearanceAccentColor(appearanceAccentColor, slot: oldSlot)
      }
    }

    lastSystemColorScheme = systemColorScheme

    applyAppearanceAccentForCurrentSlot()
    applyResolvedPalette()
    player.refreshMiniPlayerBarFillForAppearance()
    appearanceThemeRevision += 1
  }

  /// Palette aus Modus + aktueller Akzentfarbe (Hintergrund leicht getönt).
  private func applyResolvedPalette() {
    let palette = AppColorPalette.palette(
      for: appearanceMode,
      system: lastSystemColorScheme,
      accent: appearanceAccentColor
    )
    if AppTheme.palette != palette {
      AppTheme.applyPalette(palette)
    }
    appearancePalette = palette
  }

  private func applyAppearanceAccentForCurrentSlot() {
    let slot = Self.currentAppearanceAccentSlot(
      mode: appearanceMode, system: lastSystemColorScheme)
    let loaded = Self.loadAppearanceAccentColor(slot: slot)
    suppressAppearanceAccentSideEffects = true
    appearanceAccentColor = loaded
    suppressAppearanceAccentSideEffects = false
    AppTheme.applyAccent(loaded)
  }

  private static func currentAppearanceAccentSlot(
    mode: AppearanceMode,
    system: ColorScheme
  ) -> AppearanceAccentSlot {
    AppearanceAccentSlot.slot(for: mode, system: system)
  }
  @Published var smartDownloadOnWiFi: Bool = AppModel.initialSmartDownloadOnWiFi() {
    didSet { UserDefaults.standard.set(smartDownloadOnWiFi, forKey: Keys.smartDlAutoWifi) }
  }
  /// Lokale Downloads entfernen, sobald Hörbuch oder Podcast-Folge als fertig markiert ist.
  @Published var smartDownloadRemoveWhenFinished: Bool = AppModel.initialSmartDownloadRemoveWhenFinished() {
    didSet {
      UserDefaults.standard.set(smartDownloadRemoveWhenFinished, forKey: Keys.smartDlRemoveWhenFinished)
    }
  }
  /// Normale Tab-Struktur bleibt erhalten (persistiert), nur Inhalte auf Downloads eingeschränkt.
  /// Fortschritt beim Deaktivieren an den Server senden.
  @Published var offlineHomeMode: Bool = AppModel.initialOfflineHomeMode() {
    didSet {
      UserDefaults.standard.set(offlineHomeMode, forKey: Keys.offlineHomeMode)
      guard !suppressOfflineModeSideEffects else { return }
      guard oldValue != offlineHomeMode else { return }
      if offlineHomeMode {
        offlineHomeModeAuto = false
        Task {
          await prepareForOfflineHomeMode()
          await loadStartDashboard(force: true)
          await reloadLibraryViewsForModeTransition()
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

  @Published var openPlayerWhenStartPlaying: Bool = AppModel.initialOpenPlayerWhenStartPlaying() {
    didSet {
      UserDefaults.standard.set(openPlayerWhenStartPlaying, forKey: Keys.openPlayerWhenStartPlaying)
    }
  }

  /// Normale Tab-Struktur, aber alle Inhalte auf heruntergeladene Titel eingeschränkt
  /// (manuell oder automatisch nach Start ohne Server).
  var offlineHomeUIActive: Bool { offlineHomeMode || offlineHomeModeAuto }

  /// Kein `/authorize`, PATCH, Katalog-Reload o. Ä. — nur lokaler Cache und Downloads.
  var mayUseServerNetwork: Bool { !offlineHomeUIActive }

  /// Fortschritt und „Fertig“ nur lokal; Server beim Verlassen des Offline-Modus (`syncOfflineProgressToServer`).
  private var defersProgressSyncToServer: Bool {
    !mayUseServerNetwork || !isNetworkReachable
  }

  @Published private(set) var isServerReachable = false
  @Published private(set) var isServerConnectionProbeInProgress = false
  /// App-Start (Bootstrap): Verbindungs-Alert bis Floating Bar bereit (oder kein Resume).
  @Published private(set) var isAppBootstrapInProgress = false
  /// Lokaler Home-Snapshot, Fortschritt und beide Continue-Regale werden gemeinsam zusammengeführt.
  @Published private(set) var isHomeContinueRestoreInProgress = false
  /// Nutzer hat „Go offline“ während Bootstrap — laufenden Server-Sync abbrechen.
  private var bootstrapSupersededByOffline = false
  /// Nach Bootstrap: Tab-Inhalte im Hintergrund vorbauen (kein Erstaufbau beim Tab-Wechsel).
  @Published private(set) var shouldPrewarmSecondaryTabs = false
  /// Erhöht nach Account-Wechsel — Tab-Views und Toolbars invalidieren.
  @Published private(set) var accountSessionEpoch: UInt = 0
  /// Account-Wechsel: gestaffelte Katalog-Reloads überspringen (sofortiger Reload folgt).
  private var suppressDeferredWorkAfterBootstrap = false

  /// System-Alert während App-Bootstrap (Server-Verbindung + Launch-UI).
  var showsServerConnectionConnectingOverlay: Bool {
    isLoggedIn && !offlineHomeUIActive && isAppBootstrapInProgress
  }

  @Published var showOfflineModeConfirmation = false

  /// Offline-Modus nur nach Bestätigung (Toolbar / Einstellungen).
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

  /// Verbindungs-Alert / Toolbar: Bootstrap abbrechen und manuell offline starten.
  func goOfflineDuringBootstrap() {
    guard !offlineHomeUIActive else { return }
    guard isAppBootstrapInProgress || isServerConnectionProbeInProgress else {
      requestEnterOfflineHomeMode()
      return
    }
    bootstrapSupersededByOffline = true
    isAppBootstrapInProgress = false
    isServerConnectionProbeInProgress = false
    cancelDeferredBootstrapWork()
    offlineHomeMode = true
    isServerReachable = false
    Task { await bootstrapLocalSessionOnly() }
  }

  /// Home-Toolbar: statischer Offline-/Online-Schalter.
  func homeGoOfflineToolbarTapped() {
    if offlineHomeUIActive {
      exitOfflineHomeUI()
      return
    }
    if isAppBootstrapInProgress || isServerConnectionProbeInProgress {
      goOfflineDuringBootstrap()
      return
    }
    requestEnterOfflineHomeMode()
  }

  var visibleMediaCatalogKinds: [MediaCatalogKind] {
    var kinds: [MediaCatalogKind] = []
    if selectedBooksLibrary != nil {
      kinds.append(.audiobooks)
    }
    if showPodcastsTab, selectedPodcastLibrary != nil {
      kinds.append(.podcasts)
    }
    return kinds
  }

  func clampMediaCatalogKindIfNeeded() {
    let visibleKinds = visibleMediaCatalogKinds
    guard !visibleKinds.contains(mediaCatalogKind) else { return }
    mediaCatalogKind = visibleKinds.first ?? .audiobooks
    if visibleKinds.isEmpty, mainTab == .library {
      mainTab = .start
    }
  }

  func navigateToMedia(_ kind: MediaCatalogKind) {
    guard visibleMediaCatalogKinds.contains(kind) else {
      clampMediaCatalogKindIfNeeded()
      if !visibleMediaCatalogKinds.isEmpty {
        mainTab = .library
      }
      return
    }
    mediaCatalogKind = kind
    mainTab = .library
  }

  func probeServerConnectionIfNeeded() async {
    guard !isAppBootstrapInProgress, !isDeferredBootstrapNetworkRefreshInProgress else { return }
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
    ensureLocalProgressLoaded()
    await probeServerConnection()
    persistHomeShelvesSnapshot()
    // Fortschritts-Sync (viele einzelne PATCH-Requests) und Katalog-Reload sind unabhängig — parallel statt
    // sequenziell, sonst bleiben Bücher/Episoden leer, bis der komplette Sync durchgelaufen ist.
    async let progressSync: Bool = syncOfflineProgressToServer()
    async let catalogReload: Bool = reloadSettingsTab(reloadCatalogs: true)
    let (progressOk, catalogOk) = await (progressSync, catalogReload)
    if !progressOk { pendingPostOfflineModeProgressSync = true }
    if !catalogOk { pendingPostOfflineModeCatalogReload = true }
    await loadStartDashboard(force: true)
    await reloadLibraryViewsForModeTransition()
  }

  /// Nach Online-/Offline-Wechsel: Browse-Listen + eBooks einmal neu laden — sonst zeigen sie per Guard in
  /// `loadBrowseX(force:)` weiter den Stand des vorherigen Modus (Arrays werden beim Moduswechsel nicht
  /// geleert, `!force, !array.isEmpty` überspringt den Reload). Bücher/Podcast-Katalog laufen bereits über
  /// `reloadSettingsTab(reloadCatalogs:)` beim Verlassen des Offline-Modus — hier nicht doppeln.
  private func reloadLibraryViewsForModeTransition() async {
    async let authors: Void = loadBrowseAuthors(force: true)
    async let narrators: Void = loadBrowseNarrators(force: true)
    async let series: Void = loadBrowseSeries(force: true)
    async let collections: Void = loadBrowseCollections(force: true)
    async let genres: Void = loadBrowseGenres(force: true)
    async let tags: Void = loadBrowseTags(force: true)
    _ = await (authors, narrators, series, collections, genres, tags)
  }

  /// Mini-Player: Session aus Server-Fortschritt / `item`-Laden; UI kann sofort Skelett zeigen.
  @Published private(set) var isRestoringLaunchPlayback = false
  /// `play` / `playPodcastEpisode`: Item- oder Stream-Session wird aufgebaut, noch kein `activeBook`.
  @Published private(set) var isPreparingPlayback = false

  /// Verbindung prüfen / Wiedergabe vorbereiten — Now Playing und Floating Bar zeigen „Loading…“ bis `activeBook`.
  var isPlayerConnectionLoading: Bool {
    isRestoringLaunchPlayback || isPreparingPlayback
  }

  private(set) var token: String = UserDefaults.standard.string(forKey: Keys.token) ?? ""

  /// Gespeicherte Accounts für schnellen Wechsel ohne erneute Passwort-Eingabe.
  @Published private(set) var storedAccounts: [ABSStoredAccount] = []
  @Published private(set) var activeAccountKey: String?
  @Published private(set) var isSwitchingAccount = false

  let player = PlaybackController()
  let downloads = DownloadManager()
  /// Nur Player-Chrome — entkoppelt `tabViewBottomAccessory` von übrigen `@Published`-Feldern in `AppModel`.
  let floatingChrome = FloatingPlayerChromeController()

  /// Zusatz für `ScrollView`-Inhalt, damit `tabViewBottomAccessory` die letzten Zeilen nicht verdeckt.
  /// Auch offline sichtbar — der Mini-Player bleibt im Offline-Modus wie online erhalten.
  var nowPlayingAccessoryScrollBottomInset: CGFloat {
    guard floatingChrome.gate.chromeVisible else { return 0 }
    return 56
  }

  private var cancellables = Set<AnyCancellable>()

  private var client: ABSAPIClient?
  private static let libraryCatalogPageLimit = 80

  /// Temporäre Debug-Logger für White-View-Diagnose (In-Memory, exportierbar).
  private static let debugLog = DebugLogCollector.shared
  /// Tag-Buchzähler: begrenzte Parallelität — `ABSAPIClient` ist ein Actor.
  private static let browseFacetNetworkConcurrency = 4
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
  private var podcastLibrarySearchTask: Task<Void, Never>?
  private var startDashboardPostProcessingTask: Task<Void, Never>?
  /// Kaltstart: Home-Regale-Restore off-MainActor — bei Logout/Account-Wechsel während Bootstrap abbrechen.
  private var homeLaunchLocalRestoreTask: Task<Void, Never>?
  /// Verhindert, dass ein abgebrochener, älterer Restore den Aufbauzustand vorzeitig beendet.
  private var homeContinueRestoreGeneration: UInt = 0
  private var launchLocalRestoreTask: Task<Void, Never>?
  private var bootstrapCatalogReloadTask: Task<Void, Never>?
  private var deferredCatalogLocalRestoreTask: Task<Void, Never>?
  /// Lazy-Bootstrap: Continue/Bibliotheken im Hintergrund — kein paralleles `/authorize`.
  private var deferredBootstrapNetworkTask: Task<Void, Never>?
  private var isDeferredBootstrapNetworkRefreshInProgress = false
  /// Deferred `/authorize` und Bibliotheks-Refresh nach Lazy-Bootstrap — bei Logout/Account-Wechsel abbrechen.
  private var deferredBootstrapAuthorizeTask: Task<Void, Never>?
  private var deferredLibrariesFetchTask: Task<Void, Never>?
  private var storedCredentialsBootstrapTask: Task<Void, Never>?
  /// Erhöht bei jeder neuen Podcast-Verzeichnissuche; verhindert, dass abgebrochene Requests Treffer löschen oder Fehler setzen.
  private var podcastDirectorySearchGeneration: Int = 0
  private let pathMonitor = NWPathMonitor()
  private let pathMonitorQueue = DispatchQueue(label: "de.letzgo.abstand.network")

  private static let smartDownloadWiFiListenThresholdSeconds: Double = 180
  /// Nächste Katalog-Seite laden, sobald eine Zeile in den letzten N Einträgen per `.task` erscheint.
  private static let catalogPrefetchItemsFromEnd = 12
  private var smartDlPlaybackKey: String?
  private var smartDlAccumulatedSeconds: Double = 0
  private var smartDlLastTickAt: Date?
  private var smartDlFiredForCurrentKey = false
  private var downloadBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  /// `logout` / init: kein Tab-Wechsel oder Sync bei programmatischer Änderung von `offlineHomeMode`.
  private var suppressOfflineModeSideEffects = false
  /// Nach Abschalten des Offline-Modus ohne Netz: erneuter Sync, sobald `NWPathMonitor` wieder „satisfied“ meldet.
  private var pendingPostOfflineModeProgressSync = false
  /// Wie oben, aber für Katalog/Bibliotheken: `reloadSettingsTab` beim Verlassen des Offline-Modus fehlgeschlagen
  /// (z. B. Server noch nicht bereit direkt nach Reconnect) — sonst bleiben Bücher/Episoden ohne Retry leer.
  private var pendingPostOfflineModeCatalogReload = false
  /// Lokale Fortschritts-Schreibungen, die noch nicht am Server sind (vgl. Absorb `pending_syncs`).
  private var pendingLocalProgressSyncKeys: Set<String> = []
  /// „Fertig“ lokal gesetzt — schützt vor veraltetem `mediaProgress` nach Offline-Sync.
  private var localFinishedProgressKeys: Set<String> = []
  /// Nach Fortschritt-Reset: kurz blockieren, damit veraltetes `authorize` / Cache nicht wieder in „Continue listening“ landet.
  private var suppressedContinueListeningKeys: Set<String> = []
  private var lastPeriodicPlaybackProgressSaveAt: Date?
  private static let periodicPlaybackProgressSaveInterval: TimeInterval = 5

  enum MainTab: String, CaseIterable, Hashable {
    case start = "Home"
    case search = "Search"
    case library = "Library"
    case settings = "Settings"
  }

  enum MediaCatalogKind: String, CaseIterable, Identifiable, Hashable {
    case audiobooks = "Audiobooks"
    case podcasts = "Podcasts"

    var id: Self { self }

    var systemImage: String {
      switch self {
      case .audiobooks: return "books.vertical"
      case .podcasts: return "mic.fill"
      }
    }
  }

  /// Einziges Home-Regal für „Continue listening“ (kein separates Fallback-Regal).
  private static let homeContinueCategory = "recentlyListened"

  init() {
    let sp = AppLog.launchSignposter.beginInterval("appModelInit")
    defer { AppLog.launchSignposter.endInterval("appModelInit", sp) }
    Self.migrateLibraryKeysIfNeeded()
    Self.migrateAppearanceAccentKeysIfNeeded()
    migrateStartDisabledCategoriesIfNeeded()
    loadLocalFinishedProgressKeys()
    reapplyAppearance(systemColorScheme: .dark)
    CarPlayCoordinator.shared.bind(appModel: self)
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
    downloads.$queuedItemIds
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
        } else if !model.offlineHomeUIActive, !model.isAppBootstrapInProgress,
          !model.isDeferredBootstrapNetworkRefreshInProgress
        {
          Task { await model.probeServerConnectionIfNeeded() }
        }
        if reachable, !wasReachable, !model.offlineHomeUIActive,
          !model.isDeferredBootstrapNetworkRefreshInProgress
        {
          Task {
            if model.pendingPostOfflineModeProgressSync {
              model.pendingPostOfflineModeProgressSync = false
              let ok = await model.syncOfflineProgressToServer()
              if !ok { model.pendingPostOfflineModeProgressSync = true }
            }
            if model.pendingPostOfflineModeCatalogReload {
              model.pendingPostOfflineModeCatalogReload = false
              let ok = await model.reloadSettingsTab(reloadCatalogs: true)
              if !ok {
                model.pendingPostOfflineModeCatalogReload = true
              } else {
                await model.reloadLibraryViewsForModeTransition()
              }
            }
            model.ensureLocalProgressLoaded()
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
    player.onPodcastEpisodePlaybackCompleted = { [weak self] in
      Task { @MainActor [weak self] in
        await self?.handlePodcastEpisodePlaybackCompleted()
      }
    }
    floatingChrome.bind(model: self)
    let accountBootstrap = Self.bootstrapStoredAccountsState()
    storedAccounts = accountBootstrap.accounts
    activeAccountKey = accountBootstrap.activeKey
    loadDownloadedItemIdsForActiveAccount()
    // Home-Regale off-MainActor laden (SwiftData blockiert nicht den ersten Frame); Katalog/Podcasts/Downloads deferred.
    scheduleHomeLaunchRestoreFromLocalStore()
    if offlineHomeUIActive {
      mainTab = .start
    } else if isLoggedIn {
      // Overlay bis Floating Bar / Resume-Restore fertig; Bootstrap sofort (nicht auf SwiftUI-.task warten).
      isAppBootstrapInProgress = true
      homeBrowseCategory = ABSStartShelfLocalization.homeBrowseContinueSectionID
      UserDefaults.standard.set(homeBrowseCategory, forKey: Keys.homeBrowseCategory)
      scheduleBootstrapFromStoredCredentials()
      // Kataloge (Bücher/Podcasts/Browse) sofort aus der lokalen DB aufbauen — nicht erst nach
      // dem Server-Connect. Der Guard-Flag verhindert die Doppel-Ausführung nach Bootstrap;
      // der Server-Reload (`scheduleDeferredCatalogReloadAfterBootstrap`) aktualisiert später nur noch.
      scheduleDeferredCatalogLocalRestoreAfterBootstrap()
    }
  }

  deinit {
    pathMonitor.cancel()
  }

  /// Abgleich `downloadedItemIds` mit vorhandenen `download.json` auf Disk (vgl. Absorb `_validateDownloads`).
  func reconcileDownloadedItemIdsWithDisk() {
    guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return
    }
    let downloadsRoot = base.appendingPathComponent("Downloads", isDirectory: true)
    guard FileManager.default.fileExists(atPath: downloadsRoot.path) else {
      if !downloadedItemIds.isEmpty {
        downloadedItemIds = []
        persistDownloads()
      }
      return
    }
    let validated = downloadedItemIds.filter { id in
      let dir = downloadsRoot.appendingPathComponent(id, isDirectory: true)
      guard let manifest = ABSDownloadManifest.load(from: dir) else { return false }
      return downloadManifestBelongsToActiveAccount(manifest)
    }
    guard validated != downloadedItemIds else { return }
    downloadedItemIds = validated
    persistDownloads(skipRefresh: true)
  }

  /// Liest alle `Downloads/*/download.json` für bekannte `downloadedItemIds` und baut Stubs für UI / Offline-Wiedergabe.
  /// Re-Entry-Guard: Mehrfache Trigger beim Start (Pfadmonitor, Deferred-Restore, Home-Reload) werden koalesziert.
  func refreshDownloadedShelfFromManifests() {
    guard !isRefreshingDownloadedShelves else { return }
    isRefreshingDownloadedShelves = true
    defer { isRefreshingDownloadedShelves = false }
    let sp = AppLog.launchSignposter.beginInterval("refreshDownloadedShelves")
    defer { AppLog.launchSignposter.endInterval("refreshDownloadedShelves", sp) }
    reconcileDownloadedItemIdsWithDisk()
    var list: [ABSBook] = []
    for id in downloadedItemIds.sorted() {
      guard let root = try? downloads.downloadFolder(for: id),
        let manifest = ABSDownloadManifest.load(from: root),
        downloadManifestBelongsToActiveAccount(manifest)
      else { continue }
      list.append(ABSBook.fromDownloadManifest(manifest))
    }
    downloadedShelfBooks = list
    if !startShelves.isEmpty {
      purgeForeignContinueListeningItems()
    }
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

  /// Folge der aktuellen Wiedergabe (Listen, Manifest-Stub oder synthetisch).
  func podcastEpisodeForActivePlayback() -> ABSPodcastEpisodeListItem? {
    podcastEpisodeForSmartDownloadFromActivePlayback()
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
    switch (mainTab, mediaCatalogKind) {
    case (.library, .audiobooks):
      if offlineHomeUIActive || libraryCatalogQuickFilter == .downloaded {
        // Offline bzw. Downloads-Filter: volle Katalog-Metadaten statt schlanker Manifest-Stubs.
        let libId = selectedBooksLibrary?.id
        return downloadedAudiobooksWithFullMetadata().filter { book in
          guard let libId else { return true }
          return book.libraryId == nil || book.libraryId == libId
        }
      }
      if !isNetworkReachable, !books.isEmpty { return books }
      if !isNetworkReachable { return downloadedShelfBooks }
      return books
    default:
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
    navigateToMedia(.audiobooks)
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
    navigateToMedia(.audiobooks)
    Task { await reloadLibrary(reset: true) }
  }

  /// Podcast-Folge aus lokalem `download.json` (Home „Downloaded“, Offline) — Auflösungsreihenfolge
  /// wie `audiobookForDownloadedStorageId`: Manifest-Stub → gemergter In-Memory-Katalog → persistenter
  /// SwiftData-Store → Show-Titel-Anreicherung → roher Stub.
  func podcastEpisodeForDownloadedStorageId(_ storageId: String) -> ABSPodcastEpisodeListItem? {
    guard let root = try? downloads.downloadFolder(for: storageId),
      let manifest = ABSDownloadManifest.load(from: root)
    else { return nil }
    let libId = selectedPodcastLibrary?.id ?? manifest.libraryId
    guard var row = Self.podcastEpisodeListItem(from: manifest, libraryId: libId) else { return nil }
    let key = row.canonicalDedupeKey
    if let cached = mergedLocalPodcastEpisodes().first(where: { $0.canonicalDedupeKey == key }) {
      row = cached.preferringRicherMetadata(than: row)
    } else if let context = currentLocalLibraryMainContext(),
      let cached = LocalLibraryQueries.podcastEpisode(context: context, progressLookupKey: row.progressLookupKey)
    {
      row = cached.preferringRicherMetadata(than: row)
    } else if let show = podcastShows.first(where: { $0.id == row.libraryItemId }) {
      let showTitle = show.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      if !showTitle.isEmpty, row.showTitle == "—" || row.showTitle == row.authorLine {
        row = ABSPodcastEpisodeListItem(
          libraryItemId: row.libraryItemId,
          libraryId: row.libraryId,
          episodeId: row.episodeId,
          episodeTitle: row.episodeTitle,
          showTitle: showTitle,
          authorLine: row.authorLine == "—" ? showTitle : row.authorLine,
          duration: row.duration,
          publishedAt: row.publishedAt
        )
      }
    }
    return row
  }

  /// Hörbuch aus dem lokalen Katalog (volle Metadaten) oder `download.json`-Stub (`nil` bei Podcast-Folge).
  func audiobookForDownloadedStorageId(_ storageId: String) -> ABSBook? {
    guard let root = try? downloads.downloadFolder(for: storageId),
      let manifest = ABSDownloadManifest.load(from: root)
    else { return nil }
    let eid = manifest.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard eid.isEmpty else { return nil }
    if let cached = mergedLocalCatalogBooks().first(where: { $0.id == storageId }) {
      return cached
    }
    return ABSBook.fromDownloadManifest(manifest)
  }

  /// Ob ein Hörbuch oder eine Podcast-Folge (Manifest) lokal vorliegt.
  func isLibraryItemDownloaded(libraryItemId: String) -> Bool {
    let lid = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lid.isEmpty else { return false }
    if downloadedItemIds.contains(lid) { return true }
    for storageId in downloadedItemIds {
      guard let root = try? downloads.downloadFolder(for: storageId),
        let manifest = ABSDownloadManifest.load(from: root),
        manifest.libraryItemId == lid
      else { continue }
      return true
    }
    return false
  }

  /// Speicherordner-ID für Download-Badge / aktiven Download (Folge: `li_…-ep_…`).
  func downloadStorageIdForLibraryItem(_ libraryItemId: String) -> String? {
    let lid = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lid.isEmpty else { return nil }
    if downloadedItemIds.contains(lid) { return lid }
    for storageId in downloadedItemIds {
      guard let root = try? downloads.downloadFolder(for: storageId),
        let manifest = ABSDownloadManifest.load(from: root),
        manifest.libraryItemId == lid
      else { continue }
      return storageId
    }
    return nil
  }

  /// Anzeige-Metadaten für eine Storage-ID — zuerst aus dem Katalog (auch während des Downloads,
  /// bevor das Manifest geschrieben wird), dann als Fallback aus dem Manifest. `nil`, wenn beides fehlt.
  func downloadCatalogEntry(forStorageId storageId: String) -> DownloadCatalogEntry? {
    let trimmed = storageId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    // In-Memory-Cache für laufende/wartende Downloads (gefüllt beim Download-Start).
    // Wichtig für Podcast-Folgen, deren In-Memory-Katalog oft leer ist (Relaunch, BG-Download),
    // und für ALLE Downloads, bevor das Manifest geschrieben ist.
    if let cached = pendingDownloadCatalog[trimmed] {
      return cached
    }
    // Podcast-Folge: Storage-ID = „<libraryItemId>-<episodeId>".
    if trimmed.contains("-") {
      let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
      if parts.count == 2 {
        let lid = String(parts[0])
        let eid = String(parts[1])
        if let ep = (mergedLocalPodcastEpisodes() + podcastEpisodes).first(where: {
          $0.libraryItemId == lid && $0.episodeId == eid
        }) {
          return DownloadCatalogEntry(
            libraryItemId: lid,
            title: ep.episodeTitle,
            subtitle: ep.showTitle,
            isPodcastEpisode: true
          )
        }
      }
    }
    // Hörbuch: Storage-ID == libraryItemId.
    if let book = mergedLocalCatalogBooks().first(where: { $0.id == trimmed }) {
      return DownloadCatalogEntry(
        libraryItemId: book.id,
        title: book.displayTitle,
        subtitle: book.displayAuthors,
        isPodcastEpisode: false
      )
    }
    // Fallback: Manifest von der Platte (falls bereits vorhanden).
    if let root = try? downloads.downloadFolder(for: trimmed),
      let manifest = ABSDownloadManifest.load(from: root)
    {
      return DownloadCatalogEntry(
        libraryItemId: manifest.libraryItemId,
        title: manifest.displayTitle,
        subtitle: manifest.displayAuthor,
        isPodcastEpisode: manifest.episodeId != nil
      )
    }
    return nil
  }

  /// Lokaler Download-Ordner und ggf. Podcast-`episodeId` (Speicherordner kann von `book.id` abweichen).
  private func resolvedLocalDownloadForPlayback(book: ABSBook)
    -> (root: URL, libraryItemId: String, episodeId: String?)?
  {
    if downloadedItemIds.contains(book.id),
      let root = try? downloads.downloadFolder(for: book.id)
    {
      let manifest = ABSDownloadManifest.load(from: root)
      let lid = manifest?.libraryItemId ?? book.id
      let ep = manifest?.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return (root, lid, ep.isEmpty ? nil : ep)
    }
    for storageId in downloadedItemIds {
      guard let root = try? downloads.downloadFolder(for: storageId),
        let manifest = ABSDownloadManifest.load(from: root),
        manifest.libraryItemId == book.id
      else { continue }
      let ep = manifest.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return (root, manifest.libraryItemId, ep.isEmpty ? nil : ep)
    }
    return nil
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
    dropLegacyEbooksLibraryKeyIfNeeded()
  }

  /// Entfernt frühere separate eBooks-Bibliothek und Tab-Einstellungen (Migration).
  private static func dropLegacyEbooksLibraryKeyIfNeeded() {
    let d = UserDefaults.standard
    d.removeObject(forKey: Keys.ebooksLibrary)
    d.removeObject(forKey: "abstand_show_ebooks_tab")
    d.removeObject(forKey: "abstand_ebooks_catalog_sort_field")
    d.removeObject(forKey: "abstand_ebooks_catalog_sort_desc")
    d.removeObject(forKey: "abstand_ebooks_tab_card_style")
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

  private static func initialOpenPlayerWhenStartPlaying() -> Bool {
    let d = UserDefaults.standard
    if d.object(forKey: Keys.openPlayerWhenStartPlaying) == nil { return true }
    return d.bool(forKey: Keys.openPlayerWhenStartPlaying)
  }

  /// Legacy `abstand_appearance_accent_rgb` → Dark; Light startet mit Sepia-Braun.
  private static func migrateAppearanceAccentKeysIfNeeded() {
    let d = UserDefaults.standard
    if d.string(forKey: Keys.appearanceAccentRGBDark) == nil,
      let legacy = d.string(forKey: Keys.appearanceAccentRGB),
      color(fromAccentRGBString: legacy) != nil
    {
      d.set(legacy, forKey: Keys.appearanceAccentRGBDark)
    }
    if d.string(forKey: Keys.appearanceAccentRGBLight) == nil {
      persistAppearanceAccentColor(AppTheme.defaultLightAccent, slot: .light)
    }
  }

  private static func loadAppearanceAccentColor(slot: AppearanceAccentSlot) -> Color {
    let d = UserDefaults.standard
    if let raw = d.string(forKey: slot.userDefaultsKey),
      let color = color(fromAccentRGBString: raw)
    {
      return color
    }
    return slot.defaultAccent
  }

  private static func persistAppearanceAccentColor(_ color: Color, slot: AppearanceAccentSlot) {
    guard let rgb = rgbComponents(from: color) else { return }
    let raw = String(format: "%.4f,%.4f,%.4f", rgb.r, rgb.g, rgb.b)
    UserDefaults.standard.set(raw, forKey: slot.userDefaultsKey)
  }

  private static func color(fromAccentRGBString raw: String) -> Color? {
    let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 3 else { return nil }
    return Color(red: parts[0], green: parts[1], blue: parts[2])
  }

  private static func rgbComponents(from color: Color) -> (r: Double, g: Double, b: Double)? {
    let ui = UIColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return (Double(r), Double(g), Double(b))
  }

  private static func appearanceAccentColorsEqual(_ lhs: Color, _ rhs: Color) -> Bool {
    guard let a = rgbComponents(from: lhs), let b = rgbComponents(from: rhs) else { return false }
    let eps = 0.002
    return abs(a.r - b.r) < eps && abs(a.g - b.g) < eps && abs(a.b - b.b) < eps
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

  private static func loadShowPodcastsTabCached() -> Bool {
    if let cached = UserDefaults.standard.object(forKey: Keys.showPodcastsTab) as? Bool {
      return cached
    }
    let podKey =
      UserDefaults.standard.string(forKey: Keys.podcastsLibrary)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return podKey != Keys.librarySelectionNone
  }

  private func setShowPodcastsTab(_ visible: Bool) {
    if isAppBootstrapInProgress { return }
    if showPodcastsTab != visible {
      showPodcastsTab = visible
    }
  }

  /// Tab-Bar-Struktur erst nach Bootstrap aktualisieren (Offline-Button auf Home bleibt sichtbar).
  private func flushTabVisibilityAfterBootstrap() {
    syncPodcastsTabVisibilityFromLibraries()
  }

  /// Nach Server-Fetch: Tab-Sichtbarkeit mit Bibliotheksliste abgleichen und cachen.
  private func syncPodcastsTabVisibilityFromLibraries() {
    if isAppBootstrapInProgress { return }
    if podcastsLibraryPreferenceIsNone {
      setShowPodcastsTab(false)
    } else {
      setShowPodcastsTab(!sortedPodcastLibraries.isEmpty)
    }
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

  private static func loadBrowseGenresSortState() -> (field: BooksBrowseFacetSortField, descending: Bool) {
    let raw = UserDefaults.standard.string(forKey: Keys.browseGenresSortField) ?? ""
    let field = BooksBrowseFacetSortField(rawValue: raw) ?? .name
    let descending = UserDefaults.standard.bool(forKey: Keys.browseGenresSortDescending)
    return (field, descending)
  }

  private static func loadBrowseTagsSortState() -> (field: BooksBrowseFacetSortField, descending: Bool) {
    let raw = UserDefaults.standard.string(forKey: Keys.browseTagsSortField) ?? ""
    let field = BooksBrowseFacetSortField(rawValue: raw) ?? .name
    let descending = UserDefaults.standard.bool(forKey: Keys.browseTagsSortDescending)
    return (field, descending)
  }

  /// Aktualisiert Fortschritt und Lesezeichen vom Server (`POST /api/authorize`).
  func refreshProgressFromServer() async {
    guard mayUseServerNetwork, let c = client else { return }
    ensureLocalProgressLoaded()
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
    } catch {
      // 401/403 und abgebrochene Requests sind kein Erreichbarkeits-Signal.
      if !isAuthHTTPStatus(error), !AbstandErrorFilter.isBenignCancellation(error) {
        isServerReachable = false
      }
    }
  }

  /// Settings: Bibliotheken vom Server; Kataloge nur bei `reloadCatalogs` oder nach Offline.
  /// Rückgabewert: `true` bei Erfolg — Aufrufer können damit einen Retry einplanen (z. B. nach Offline-Wechsel).
  @discardableResult
  func reloadSettingsTab(reloadCatalogs: Bool = false) async -> Bool {
    guard let c = client else { return false }
    do {
      libraries = try await c.libraries()

      if podcastsLibraryPreferenceIsNone {
        clearPodcastLibraryStateWithoutPersistingNone()
        setShowPodcastsTab(false)
      } else if let sel = selectedPodcastLibrary, !sortedPodcastLibraries.contains(where: { $0.id == sel.id })
      {
        if let first = sortedPodcastLibraries.first {
          selectPodcastLibrary(first, navigateToCatalog: false)
        } else {
          clearPodcastLibraryStateWithoutPersistingNone()
          UserDefaults.standard.set(Keys.librarySelectionNone, forKey: Keys.podcastsLibrary)
          setShowPodcastsTab(false)
        }
      } else if selectedPodcastLibrary == nil, !podcastsLibraryPreferenceIsNone,
        let first = sortedPodcastLibraries.first
      {
        selectPodcastLibrary(first, navigateToCatalog: false)
      } else {
        syncPodcastsTabVisibilityFromLibraries()
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

      guard reloadCatalogs else { return true }
      async let pod: Void = reloadPodcastLibrary(reset: true)
      async let lib: Void = reloadLibrary(reset: true)
      _ = await (pod, lib)
      return true
    } catch {
      publishErrorUnlessBenignCancellation(error)
      return false
    }
  }

  /// Kurz nach Netzverlust: lokalen Fortschritt laden und Continue-Regal reparieren (ohne Server).
  func handleNetworkBecameUnreachable() {
    ensureLocalProgressLoaded()
    if !startShelves.isEmpty {
      repairContinueListeningShelfFromLocalProgressOnly()
    }
  }

  /// Lädt Home-Regale: online `/personalized` + `items-in-progress`; offline nur Cache + lokaler Fortschritt.
  /// `skipAuthorizeRefresh`: nach frischem `authorize` in Bootstrap/Login — kein zweites `/authorize`.
  /// `force`: Netzwerk-Refresh auch wenn Regale schon da sind (Pull-to-Refresh, Bootstrap, Settings).
  /// `forPullToRefresh`: expliziter Pull — Netz trotz PathMonitor versuchen, Fehler anzeigen.
  @discardableResult
  func loadStartDashboard(
    skipAuthorizeRefresh: Bool = false,
    force: Bool = false,
    forPullToRefresh: Bool = false
  ) async -> ContinueRefreshAttemptResult {
    ensureLocalProgressLoaded()

    // Tab-Wechsel / erneutes onAppear: `startShelves` aus init/Cache behalten, kein Reload.
    if !force, !offlineHomeUIActive, !startShelves.isEmpty {
      return ContinueRefreshAttemptResult()
    }

    var result = ContinueRefreshAttemptResult()
    var didApplyOnlineStartDashboard = false
    defer {
      // Online-Apply aktualisiert Continue reading bereits synchron — kein zweites Re-Inject nach Yields.
      scheduleStartDashboardPostProcessing(
        includeEbookShelfRefresh: !didApplyOnlineStartDashboard,
        skipContinueSync: didApplyOnlineStartDashboard
      )
    }
    if offlineHomeUIActive {
      ensureLocalProgressLoaded()
      applyOfflineStartDashboard()
      return result
    }
    if forPullToRefresh {
      restoreServerClientIfNeeded()
    }
    guard let c = client else {
      applyCachedStartDashboard()
      if forPullToRefresh {
        errorMessage = "Not connected to the server."
      }
      return result
    }
    if !forPullToRefresh, !isNetworkReachable {
      applyCachedStartDashboard()
      return result
    }
    if startShelves.isEmpty {
      applyCachedStartDashboard()
    }
    result.attemptedNetwork = true
    do {
      if let lib = selectedBooksLibrary {
        async let shelvesData = c.personalizedShelves(libraryId: lib.id, limit: 14)
        async let inProgressTask = c.itemsInProgressWithRawData(limit: 80)
        let progressSync: Task<Void, Never>? =
          skipAuthorizeRefresh
          ? nil
          : Task { await refreshProgressFromServer() }
        let (data, inProgressPacked) = try await (shelvesData, inProgressTask)
        if let progressSync { await progressSync.value }
        let parsed = await Task.detached {
          ABSAPIClient.parsePersonalizedStartShelves(data: data)
        }.value
        updateStartSettingsCategoryList(parsed: parsed)
        // `force` nur: Early-Exit umgehen. Continue-Replace nur bei Pull-to-Refresh —
        // Hintergrund-Refresh bleibt local-first (Merge + lokale Continue-Reading-Regale erhalten).
        applyOnlineStartDashboard(
          parsed: parsed,
          itemsInProgress: inProgressPacked.payload,
          replaceContinueShelves: forPullToRefresh
        )
        didApplyOnlineStartDashboard = true
        result.appliedOnline = true
        isServerReachable = true
        await Task.yield()
      } else {
        let progressSync: Task<Void, Never>? =
          skipAuthorizeRefresh
          ? nil
          : Task { await refreshProgressFromServer() }
        let inProgressPacked = try await c.itemsInProgressWithRawData(limit: 80)
        if let progressSync { await progressSync.value }
        applyStartDashboardFromItemsInProgressOnly(inProgressPacked.payload)
        didApplyOnlineStartDashboard = true
        result.appliedOnline = true
        isServerReachable = true
        await Task.yield()
      }
    } catch {
      result.error = error
      // 401/403: Server hat geantwortet, nur Credentials falsch — Erreichbarkeit unberührt lassen.
      if !isAuthHTTPStatus(error), !AbstandErrorFilter.isBenignCancellation(error) {
        isServerReachable = false
      }
      if !skipAuthorizeRefresh {
        await refreshProgressFromServer()
      }
      if !forPullToRefresh {
        applyCachedStartDashboard()
      }
      publishErrorUnlessBenignCancellation(error, forceDisplay: forPullToRefresh)
    }
    return result
  }

  /// Schwere Home-Nacharbeit (Downloads, Continue, eBooks) — nicht synchron blockieren (Pull-to-Refresh / UI).
  private func scheduleStartDashboardPostProcessing(
    includeEbookShelfRefresh: Bool = true,
    skipContinueSync: Bool = false
  ) {
    startDashboardPostProcessingTask?.cancel()
    startDashboardPostProcessingTask = Task(priority: .utility) { @MainActor [weak self] in
      await Task.yield()
      guard let self, !Task.isCancelled else { return }
      self.refreshDownloadedShelfFromManifests()
      guard !self.offlineHomeUIActive else { return }
      await Task.yield()
      guard !Task.isCancelled else { return }
      self.repairContinueListeningShelfFromLocalProgressOnly()
      self.purgeForeignContinueListeningItems()
      if !skipContinueSync {
        self.syncContinueListeningShelvesWithProgress()
      }
      self.normalizeHomeContinueListeningShelves()
      guard includeEbookShelfRefresh else { return }
      await Task.yield()
      guard !Task.isCancelled else { return }
      self.refreshEbookContinueReadingShelf()
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

  /// Eingeschaltete Home-Regale für die horizontale Leiste (Continue-Regale als ein Eintrag).
  /// Stats links neben Continue; Continue bleibt der Standard-Tab (`homeBrowseCategory`).
  var homeBrowseStripRows: [(category: String, label: String)] {
    if offlineHomeUIActive {
      // Offline nur Regale, die rein lokal befüllbar sind — keine Server-Personalisierung/Stats.
      return [
        (
          ABSStartShelfLocalization.homeBrowseContinueSectionID,
          ABSStartShelfLocalization.homeBrowseContinueStripLabel
        ),
        (
          ABSStartShelfLocalization.homeBrowseDownloadedSectionID,
          ABSStartShelfLocalization.homeBrowseDownloadedStripLabel
        ),
      ]
    }
    var rows: [(category: String, label: String)] = []
    var insertedContinue = false
    var insertedRecent = false
    for row in startSettingsCategoryList {
      if ABSStartShelfLocalization.isHomeBrowseContinueCategory(row.category) {
        if !insertedContinue, isAnyHomeBrowseContinueShelfEnabled {
          rows.append(
            (
              ABSStartShelfLocalization.homeBrowseStatsSectionID,
              ABSStartShelfLocalization.homeBrowseStatsStripLabel
            ))
          rows.append(
            (
              ABSStartShelfLocalization.homeBrowseContinueSectionID,
              ABSStartShelfLocalization.homeBrowseContinueStripLabel
            ))
          insertedContinue = true
        }
        continue
      }
      if ABSStartShelfLocalization.isHomeBrowseRecentCategory(row.category) {
        if !insertedRecent, isAnyHomeBrowseRecentShelfEnabled {
          rows.append(
            (
              ABSStartShelfLocalization.homeBrowseRecentSectionID,
              ABSStartShelfLocalization.homeBrowseRecentStripLabel
            ))
          insertedRecent = true
        }
        continue
      }
      if isStartCategoryEnabled(row.category) {
        rows.append((row.category, row.label))
      }
    }
    if !rows.contains(where: {
      ABSStartShelfLocalization.isHomeBrowseStatsCategory($0.category)
    }) {
      rows.insert(
        (
          ABSStartShelfLocalization.homeBrowseStatsSectionID,
          ABSStartShelfLocalization.homeBrowseStatsStripLabel
        ),
        at: 0
      )
    }
    return rows
  }

  var homeBrowseStripCategoryIDs: [String] {
    homeBrowseStripRows.map(\.category)
  }

  var isAnyHomeBrowseContinueShelfEnabled: Bool {
    ABSStartShelfLocalization.homeBrowseContinueCategories.contains { isStartCategoryEnabled($0) }
  }

  var isAnyHomeBrowseRecentShelfEnabled: Bool {
    ABSStartShelfLocalization.homeBrowseRecentCategories.contains { isStartCategoryEnabled($0) }
  }

  func startShelf(forCategory category: String) -> ABSStartShelfSection? {
    startShelves.first { $0.category == category }
  }

  /// Regale für einen Home-Menüpunkt (`continue` = alle eingeschalteten Continue-Regale).
  func startShelves(forHomeBrowseSection sectionID: String) -> [ABSStartShelfSection] {
    if sectionID == ABSStartShelfLocalization.homeBrowseContinueSectionID {
      return ABSStartShelfLocalization.homeBrowseContinueCategories.compactMap { cat in
        guard isStartCategoryEnabled(cat) else { return nil }
        return startShelf(forCategory: cat)
      }
    }
    if sectionID == ABSStartShelfLocalization.homeBrowseRecentSectionID {
      return ABSStartShelfLocalization.homeBrowseRecentCategories.compactMap { cat in
        guard isStartCategoryEnabled(cat) else { return nil }
        return startShelf(forCategory: cat)
      }
    }
    if let shelf = startShelf(forCategory: sectionID) { return [shelf] }
    return []
  }

  func selectHomeBrowseSection(_ category: String) {
    guard homeBrowseStripCategoryIDs.contains(category) else { return }
    homeBrowseCategory = category
    // Stats nur für die Session — Kaltstart beginnt immer bei Continue.
    if !ABSStartShelfLocalization.isHomeBrowseStatsCategory(category) {
      UserDefaults.standard.set(category, forKey: Keys.homeBrowseCategory)
    }
  }

  func clampHomeBrowseSectionIfNeeded() {
    if ABSStartShelfLocalization.isHomeBrowseContinueCategory(homeBrowseCategory) {
      homeBrowseCategory = ABSStartShelfLocalization.homeBrowseContinueSectionID
      UserDefaults.standard.set(homeBrowseCategory, forKey: Keys.homeBrowseCategory)
    }
    if ABSStartShelfLocalization.isHomeBrowseRecentCategory(homeBrowseCategory) {
      homeBrowseCategory = ABSStartShelfLocalization.homeBrowseRecentSectionID
      UserDefaults.standard.set(homeBrowseCategory, forKey: Keys.homeBrowseCategory)
    }
    let ids = homeBrowseStripCategoryIDs
    guard !ids.isEmpty else { return }
    guard !ids.contains(homeBrowseCategory), let first = ids.first else { return }
    homeBrowseCategory = first
    UserDefaults.standard.set(first, forKey: Keys.homeBrowseCategory)
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
    clampHomeBrowseSectionIfNeeded()
    Task { await loadStartDashboard(force: true) }
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
      let label = ABSStartShelfLocalization.displayTitle(
        category: cat,
        serverLabel: fromServer[cat] ?? ""
      )
      return (category: cat, label: label)
    }
    clampHomeBrowseSectionIfNeeded()
  }

  /// Home-Regale „Continue reading“ / „Continue series“ aus lokalem Readium-Fortschritt.
  /// Offline: `applyOfflineStartDashboard()` ist alleiniger Eigentümer von `startShelves` (nur Downloads) —
  /// diese Regale würden sonst auch nicht heruntergeladene eBooks mit Fortschritt einschleusen.
  func refreshEbookContinueReadingShelf() {
    guard !offlineHomeUIActive else { return }
    ensureEbookLocalSessionIfNeeded()
    injectEbookContinueReadingShelfIfNeeded()
  }

  /// Item-IDs mit Lesefortschritt (Server-Progress + lokale Readium-Dateien).
  private func inProgressEbookLibraryItemIds() -> [String] {
    var seen = Set<String>()
    var ids: [String] = []
    func absorb(_ raw: String) {
      let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !id.isEmpty, seen.insert(id).inserted else { return }
      guard let fraction = ebookDisplayProgressFraction(libraryItemId: id),
        fraction > 0.005, fraction < 0.995
      else { return }
      ids.append(id)
    }
    for progress in progressByItemId.values where progress.episodeId == nil {
      absorb(progress.libraryItemId)
    }
    for id in EbookLocalStore.inProgressLibraryItemIds() {
      absorb(id)
    }
    return ids
  }

  /// Kaltstart: Beide Continue-Regale live aus dem lokalen Fortschritt aufbauen.
  /// Dadurch ist „Continue reading“ nicht mehr von einem separaten Rank-Snapshot abhängig.
  private func applyHomeContinueCacheFromLocalStore() {
    if let context = currentLocalLibraryMainContext(),
      let payload = LocalLibraryQueries.itemsInProgressPayload(context: context, limit: 80)
    {
      ensureContinueListeningShelfIfMissing(itemsInProgress: payload)
      mergeServerAudiobooksIntoContinueShelves(payload)
      mergeServerPodcastEpisodesIntoContinueShelves(payload)
    }
    refreshEbookContinueReadingShelf()
  }

  /// Home-Regale (inkl. gemergter Continue-Zeilen) — ein SwiftData-Snapshot je Bibliothek,
  /// 1:1-Ersatz für `homeContinue.json`/`personalized/<libraryId>.json` (Migrationsplan Etappe 8).
  private func persistHomeShelvesToLocalStore() {
    guard let store = currentLocalLibraryStore() else { return }
    let libraryId = selectedBooksLibrary?.id ?? Keys.librarySelectionNone
    let sections = startShelves
    Task.detached(priority: .utility) {
      try? await store.replaceHomeShelves(libraryId: libraryId, sections: sections)
    }
  }

  /// Nach erstem Frame: Fortschritt aus `ebook_fraction.json` einlesen und Regale aktualisieren.
  private func scheduleDeferredEbookContinueShelfRefresh() {
    Task { @MainActor [weak self] in
      self?.refreshEbookContinueReadingShelf()
    }
  }

  private func stripContinueEbooks(from shelves: [ABSStartShelfSection]) -> [ABSStartShelfSection] {
    shelves.filter { $0.category != "continueEbooks" }
  }

  private func applyEbookContinueReadingInjection(_ books: [ABSBook]) {
    guard selectedBooksLibrary != nil, isStartCategoryEnabled("continueEbooks"), !books.isEmpty else { return }
    if let existing = startShelves.first(where: { $0.category == "continueEbooks" }),
      existing.books.map(\.id) == books.map(\.id)
    { return }
    var shelves = stripContinueEbooks(from: startShelves)
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
    // Wenn Continue Reading das erste lokal rekonstruierte Regal ist, existiert noch kein
    // Server-/Snapshot-Regal, das die Browse-Strip-Konfiguration initialisiert. Ohne dieses
    // Update wird die Continue-Ansicht erst sichtbar, sobald ein anderes Regal geladen ist.
    updateStartSettingsCategoryList(parsed: shelves)
    persistHomeShelvesToLocalStore()
  }

  private func injectEbookContinueReadingShelfIfNeeded() {
    guard selectedBooksLibrary != nil, isStartCategoryEnabled("continueEbooks") else {
      guard startShelves.contains(where: { $0.category == "continueEbooks" }) else { return }
      let shelves = stripContinueEbooks(from: startShelves)
      startShelves = shelves
      recomputeStartBooksUnion(from: shelves)
      persistHomeShelvesToLocalStore()
      return
    }
    let books = buildEbookContinueReadingBooks()
    guard !books.isEmpty else {
      guard startShelves.contains(where: { $0.category == "continueEbooks" }) else { return }
      let shelves = stripContinueEbooks(from: startShelves)
      startShelves = shelves
      recomputeStartBooksUnion(from: shelves)
      persistHomeShelvesToLocalStore()
      return
    }
    applyEbookContinueReadingInjection(books)
  }

  /// eBooks mit Lesefortschritt — IDs aus Progress/LocalStore, Metadaten gezielt nachladen.
  private func allInProgressEbookCandidates() -> [ABSBook] {
    var candidates: [ABSBook] = []
    for id in inProgressEbookLibraryItemIds() {
      guard let book = bookForEbookContinue(libraryItemId: id) else { continue }
      guard !book.isPlayableAudiobook else { continue }
      candidates.append(book)
    }
    return candidates.sorted {
      (ebookDisplayProgressFraction(libraryItemId: $0.id) ?? 0)
        > (ebookDisplayProgressFraction(libraryItemId: $1.id) ?? 0)
    }
  }

  /// eBooks mit Lesefortschritt für das Continue-reading-Regal.
  private func buildEbookContinueReadingBooks() -> [ABSBook] {
    Array(
      allInProgressEbookCandidates()
        .filter { !$0.isPlayableAudiobook }
        .prefix(14)
    )
    .map(enrichEbookContinueBookAuthorIfNeeded)
  }

  /// Continue-reading: Autor aus Katalog/eBooks-Listen nachziehen, wenn der Stub nur „—“ hat.
  private func enrichEbookContinueBookAuthorIfNeeded(_ book: ABSBook) -> ABSBook {
    let current = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard current.isEmpty || current == "—" else { return book }
    guard let author = localBookAuthorLine(libraryItemId: book.id) else { return book }
    return book.withAuthorLineIfMissing(author)
  }

  private func localBookAuthorLine(libraryItemId: String) -> String? {
    for list in [
      books, startBooks, downloadedShelfBooks,
      entityDetailBooks, entityDetailAuthorStandaloneBooks,
    ] {
      if let line = authorLineFromBookList(list, libraryItemId: libraryItemId) { return line }
    }
    for section in entityDetailAuthorSeriesSections {
      if let line = authorLineFromBookList(section.books, libraryItemId: libraryItemId) {
        return line
      }
    }
    if let book = bookFromLocalStore(libraryItemId: libraryItemId) {
      let line = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if !line.isEmpty, line != "—" { return line }
    }
    return nil
  }

  private func authorLineFromBookList(_ list: [ABSBook], libraryItemId: String) -> String? {
    guard let book = list.first(where: { $0.id == libraryItemId }) else { return nil }
    let line = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty, line != "—" else { return nil }
    return line
  }

  /// Buch zu gespeicherter Readium-Position (Katalog, LocalStore, Download-Meta).
  private func bookForEbookContinue(libraryItemId: String) -> ABSBook? {
    if let b = books.first(where: { $0.id == libraryItemId }) { return b }
    if let b = startBooks.first(where: { $0.id == libraryItemId }) { return b }
    if let b = downloadedShelfBooks.first(where: { $0.id == libraryItemId }) { return b }
    if let b = bookFromLocalStore(libraryItemId: libraryItemId) { return b }
    if let context = currentLocalLibraryMainContext(),
      let b = LocalLibraryQueries.bookDetail(context: context, id: libraryItemId)
    {
      return b
    }
    guard let account = cacheAccountURL(),
      let lib = selectedBooksLibrary
    else { return nil }
    for fmt in ABSEbookFormat.allCases {
      if let meta = EbookLocalStore.loadDownloadMeta(account: account, libraryItemId: libraryItemId, format: fmt) {
        let title = meta.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayTitle = title.isEmpty ? "eBook" : title
        let authorLine = localBookAuthorLine(libraryItemId: libraryItemId) ?? "—"
        let bookMeta = ABSBookMediaMetadata(offlineTitle: displayTitle, authorLine: authorLine)
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

  private func bookFromLocalStore(libraryItemId: String) -> ABSBook? {
    guard let context = currentLocalLibraryMainContext() else { return nil }
    return LocalLibraryQueries.book(context: context, id: libraryItemId)
  }

  /// Stats-`items`-Key oder Folgen-ID → `libraryItemId` für Katalog/Details.
  func normalizedStatsLibraryItemId(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return "" }
    if let ep = t.range(of: "/ep/") {
      return String(t[..<ep.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if t.hasPrefix("li_"), let dash = t.range(of: "-ep_") {
      return String(t[..<dash.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return t
  }

  /// Alle in-memory Stubs für ID-Lookup (ohne `isUsableLibraryCatalogRow`-Filter).
  private func allInMemoryBooksForIdLookup() -> [ABSBook] {
    var byId: [String: ABSBook] = [:]
    func add(_ list: [ABSBook]) {
      for book in list {
        let id = book.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { continue }
        byId[id] = book
      }
    }
    add(books)
    add(startBooks)
    add(searchBooks)
    add(downloadedShelfBooks)
    add(browseEbooks)
    add(browseEbooksSupplementary)
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

  /// Nur lokal gebaut — nicht in `/personalized`, beim Server-Merge erhalten.
  private func isLocalOnlyHomeShelfCategory(_ category: String) -> Bool {
    category == "continueEbooks"
  }

  private func serverLayoutHomeShelves(from shelves: [ABSStartShelfSection]) -> [ABSStartShelfSection] {
    shelves.filter { !isLocalOnlyHomeShelfCategory($0.category) }
  }

  /// Server-Layout übernehmen, lokal-only Regale (Continue reading) an der Continue-Position behalten.
  private func mergingPreservedLocalOnlyHomeShelves(
    into next: [ABSStartShelfSection],
    prior: [ABSStartShelfSection]
  ) -> [ABSStartShelfSection] {
    let preserved = prior.filter {
      isLocalOnlyHomeShelfCategory($0.category) && isStartCategoryEnabled($0.category)
    }
    var result = stripContinueEbooks(from: next)
    guard !preserved.isEmpty else { return result }
    for section in preserved {
      if let idx = result.firstIndex(where: { isHomeContinueCategory($0.category) }) {
        result.insert(section, at: idx + 1)
      } else {
        result.insert(section, at: 0)
      }
    }
    return result
  }

  /// `startShelves` setzen und lokal-only Regale aus `prior` mitnehmen (kein Continue-Reading-Flash).
  private func assignStartShelvesPreservingLocalOnly(
    _ next: [ABSStartShelfSection],
    prior: [ABSStartShelfSection]
  ) {
    let merged = mergingPreservedLocalOnlyHomeShelves(into: next, prior: prior)
    startShelves = merged
    recomputeStartBooksUnion(from: merged)
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
    guard let plid = resolvedPodcastLibraryId() else { return [] }
    var eps = payload.podcastEpisodes.filter { ($0.libraryId ?? "") == plid || $0.libraryId == nil }
    eps = eps.filter { ep in
      let key = ep.progressLookupKey
      if isProgressKeyBlockedFromContinueListening(key) { return false }
      guard let p = progressByItemId[key] else { return false }
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
  /// Local-first: vorhandene Continue-Reading-Regale bleiben beim Server-Apply sichtbar und werden
  /// am Ende aus lokalem Lesefortschritt aktualisiert (kein Verschwinden → späteres Re-Inject).
  private func applyOnlineStartDashboard(
    parsed: [ABSStartShelfSection],
    itemsInProgress: ABSItemsInProgressPayload,
    replaceContinueShelves: Bool = false
  ) {
    let priorShelves = startShelves
    guard isStartCategoryEnabled(Self.homeContinueCategory) else {
      if parsed.isEmpty {
        assignStartShelvesPreservingLocalOnly([], prior: priorShelves)
      } else {
        let visible = parsed.filter { isStartCategoryEnabled($0.category) }
        assignStartShelvesPreservingLocalOnly(visible, prior: priorShelves)
      }
      refreshEbookContinueReadingShelf()
      persistHomeShelvesToLocalStore()
      return
    }
    if parsed.isEmpty {
      applyStartDashboardFromItemsInProgressOnly(itemsInProgress)
      return
    }
    let visible = parsed.filter { isStartCategoryEnabled($0.category) }
    if replaceContinueShelves {
      assignStartShelvesPreservingLocalOnly(visible, prior: priorShelves)
    } else {
      let priorContinueBooks = priorShelves.filter { isHomeContinueCategory($0.category) }.flatMap(\.books)
      let priorContinueEpisodes = priorShelves.filter { isHomeContinueCategory($0.category) }.flatMap(
        \.podcastEpisodes)
      if !startShelvesHaveSameLayout(serverLayoutHomeShelves(from: priorShelves), visible) {
        assignStartShelvesPreservingLocalOnly(visible, prior: priorShelves)
      }
      preserveValidContinueListeningItems(books: priorContinueBooks, episodes: priorContinueEpisodes)
    }
    ensureContinueListeningShelfIfMissing(itemsInProgress: itemsInProgress)
    mergeServerAudiobooksIntoContinueShelves(itemsInProgress)
    mergeServerPodcastEpisodesIntoContinueShelves(itemsInProgress)
    syncContinueListeningShelvesWithProgress()
    // Continue reading parallel zu Listening: lokal aktualisieren, nicht erst in Post-Processing.
    refreshEbookContinueReadingShelf()
    persistHomeShelvesToLocalStore()
  }

  /// Nur `items-in-progress` (leeres `/personalized` oder keine Bibliothek gewählt).
  private func applyStartDashboardFromItemsInProgressOnly(_ payload: ABSItemsInProgressPayload) {
    let priorShelves = startShelves
    guard isStartCategoryEnabled(Self.homeContinueCategory) else {
      assignStartShelvesPreservingLocalOnly([], prior: priorShelves)
      refreshEbookContinueReadingShelf()
      persistHomeShelvesToLocalStore()
      return
    }
    let books = inProgressAudiobookCandidates(from: payload)
    let podcastEps = inProgressPodcastEpisodeCandidates(from: payload)
    guard !books.isEmpty || !podcastEps.isEmpty else {
      assignStartShelvesPreservingLocalOnly([], prior: priorShelves)
      refreshEbookContinueReadingShelf()
      persistHomeShelvesToLocalStore()
      return
    }
    let section = makeContinueListeningShelf(
      id: "items-in-progress",
      books: books,
      podcastEpisodes: podcastEps
    )
    assignStartShelvesPreservingLocalOnly([section], prior: priorShelves)
    syncContinueListeningShelvesWithProgress()
    refreshEbookContinueReadingShelf()
    persistHomeShelvesToLocalStore()
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

  /// Offline / Netzwerkfehler: gecachter Home-Regal-Snapshot, Continue listening aus lokalem Fortschritt.
  private func applyCachedStartDashboard() {
    if startShelves.isEmpty, let context = currentLocalLibraryMainContext(), let libId = selectedBooksLibrary?.id,
      let cached = LocalLibraryQueries.homeShelves(context: context, libraryId: libId)
    {
      let visible = cached.filter { isStartCategoryEnabled($0.category) }
      if !visible.isEmpty {
        startShelves = visible
        recomputeStartBooksUnion(from: visible)
        updateStartSettingsCategoryList(parsed: cached)
      }
    }
    applyHomeContinueCacheFromLocalStore()
    repairContinueListeningShelfFromLocalProgressOnly()
    syncContinueListeningShelvesWithProgress()
  }

  /// Gecachtes Home-Continue (Hörbücher, Podcasts, eBooks) beim Kaltstart.
  private func applyContinueListeningFromCachedItemsInProgress() {
    applyHomeContinueCacheFromLocalStore()
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
      let existingEpKeys = Set(shelf.podcastEpisodes.map(\.canonicalDedupeKey))
      let epsToAdd = eps.filter { !existingEpKeys.contains($0.canonicalDedupeKey) }
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

  /// Offline: `startShelves` komplett aus lokalem Katalog + Downloads aufbauen (kein Server-Request).
  /// Ersetzt statt zu mergen — Home zeigt ausschließlich, was gerade heruntergeladen ist.
  private func applyOfflineStartDashboard() {
    var shelves: [ABSStartShelfSection] = []

    if isStartCategoryEnabled(Self.homeContinueCategory) {
      let continueBooks = localContinueAudiobookBookCandidates()
        .filter { downloadedItemIds.contains($0.id) }
      let continueEpisodes = localContinuePodcastEpisodeCandidates()
        .filter { downloadedItemIds.contains(podcastEpisodeOfflineStorageId($0)) }
      if !continueBooks.isEmpty || !continueEpisodes.isEmpty {
        shelves.append(
          makeContinueListeningShelf(
            id: "offline-continue", books: continueBooks, podcastEpisodes: continueEpisodes)
        )
      }
    }

    let downloadedBooks = downloadedAudiobooksWithFullMetadata()
    if !downloadedBooks.isEmpty {
      shelves.append(
        ABSStartShelfSection(
          id: "offline-downloaded",
          category: ABSStartShelfLocalization.homeBrowseDownloadedSectionID,
          displayTitle: ABSStartShelfLocalization.homeBrowseDownloadedStripLabel,
          books: downloadedBooks
        )
      )
    }

    startShelves = shelves
    recomputeStartBooksUnion(from: shelves)
  }

  /// Downloads (nur Hörbücher, keine Podcast-Folgen) mit vollen Katalog-Metadaten statt Manifest-Stub —
  /// nutzt den bereits synchronisierten lokalen Katalog (Genres, Serien, Autoren, Cover) statt der schlanken
  /// `download.json`-Stubs, sofern der Titel noch im lokalen Katalog bekannt ist.
  private func downloadedAudiobooksWithFullMetadata() -> [ABSBook] {
    let catalogById = Dictionary(
      mergedLocalCatalogBooks().map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var out: [ABSBook] = []
    out.reserveCapacity(downloadedItemIds.count)
    for storageId in downloadedItemIds.sorted() {
      if let full = catalogById[storageId] {
        out.append(full)
      } else if let stub = audiobookForDownloadedStorageId(storageId) {
        out.append(stub)
      }
    }
    return out
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
    if isProgressKeyBlockedFromContinueListening(bookId) { return false }
    if isActivelyPlayingMedia(libraryItemId: bookId, episodeId: nil) { return true }
    guard let p = progressByItemId[bookId], !p.isFinished else { return false }
    return p.currentTime > Self.continueListeningMinPositionSeconds
  }

  private func qualifiesForContinueListeningShelf(episodeKey: String) -> Bool {
    if isProgressKeyBlockedFromContinueListening(episodeKey) { return false }
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
      let existingEpKeys = Set(shelf.podcastEpisodes.map(\.canonicalDedupeKey))
      let booksToAdd = validBooks.filter { !existingBookIds.contains($0.id) }
      let epsToAdd = validEps.filter { !existingEpKeys.contains($0.canonicalDedupeKey) }
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

  private func removeAudiobookFromContinueListeningShelves(bookId: String) {
    let id = bookId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty, !startShelves.isEmpty else { return }
    let newShelves = startShelves.map { shelf -> ABSStartShelfSection in
      guard isHomeContinueCategory(shelf.category) else { return shelf }
      let books = shelf.books.filter { $0.id != id }
      if books.count == shelf.books.count { return shelf }
      return ABSStartShelfSection(
        id: shelf.id,
        category: shelf.category,
        displayTitle: shelf.displayTitle,
        books: books,
        podcastEpisodes: shelf.podcastEpisodes,
        authors: shelf.authors,
        series: shelf.series
      )
    }
    startShelves = newShelves
    recomputeStartBooksUnion(from: newShelves)
  }

  private func removePodcastEpisodeFromContinueListeningShelves(_ episode: ABSPodcastEpisodeListItem) {
    guard !startShelves.isEmpty else { return }
    let key = episode.progressLookupKey
    let dedupe = episode.canonicalDedupeKey
    let newShelves = startShelves.map { shelf -> ABSStartShelfSection in
      guard isHomeContinueCategory(shelf.category) else { return shelf }
      let eps = shelf.podcastEpisodes.filter {
        $0.progressLookupKey != key && $0.canonicalDedupeKey != dedupe
      }
      if eps.count == shelf.podcastEpisodes.count { return shelf }
      return ABSStartShelfSection(
        id: shelf.id,
        category: shelf.category,
        displayTitle: shelf.displayTitle,
        books: shelf.books,
        podcastEpisodes: eps,
        authors: shelf.authors,
        series: shelf.series
      )
    }
    startShelves = newShelves
    recomputeStartBooksUnion(from: newShelves)
  }

  private func purgeLocalProgressForPodcastEpisode(_ episode: ABSPodcastEpisodeListItem) {
    let key = episode.progressLookupKey
    progressByItemId.removeValue(forKey: key)
    pendingLocalProgressSyncKeys.remove(key)
    clearLocallyFinishedProgressKey(key)
    let alt = "\(episode.libraryItemId)/ep/\(episode.episodeId)"
    if alt != key {
      progressByItemId.removeValue(forKey: alt)
      pendingLocalProgressSyncKeys.remove(alt)
      clearLocallyFinishedProgressKey(alt)
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

  /// Eine Folge pro Sendung+Folge; Zeile mit mehr Metadaten gewinnt (Cache vs. Manifest).
  private func dedupePodcastEpisodesForHomeContinueList(_ items: [ABSPodcastEpisodeListItem]) -> [ABSPodcastEpisodeListItem] {
    let sorted = items.sorted {
      (progressByItemId[$0.progressLookupKey]?.lastUpdate ?? 0)
        > (progressByItemId[$1.progressLookupKey]?.lastUpdate ?? 0)
    }
    return ABSPodcastEpisodeListItem.dedupeRows(sorted)
  }

  private func mergeServerPodcastEpisodesIntoContinueShelves(_ payload: ABSItemsInProgressPayload) {
    guard isStartCategoryEnabled(Self.homeContinueCategory) else { return }
    let episodes = inProgressPodcastEpisodeCandidates(from: payload)
    guard !episodes.isEmpty else { return }

    if let idx = preferredHomeContinueShelfIndex() {
      var shelves = startShelves
      let shelf = shelves[idx]
      let existingKeys = Set(shelf.podcastEpisodes.map(\.canonicalDedupeKey))
      let toAdd = episodes.filter { !existingKeys.contains($0.canonicalDedupeKey) }
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
      if isDownloaded {
        guard downloadBookBelongsToActiveAccount(b) else { continue }
      } else if let lid = b.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty,
        let selected = selectedBooksLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines),
        !selected.isEmpty, lid != selected
      {
        continue
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
      if isProgressKeyBlockedFromContinueListening(book.id) { return false }
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
      clearPodcastLibraryStateWithoutPersistingNone()
      UserDefaults.standard.set(Keys.librarySelectionNone, forKey: Keys.podcastsLibrary)
      setShowPodcastsTab(false)
    }
    syncPodcastsTabVisibilityFromLibraries()
  }

  func bootstrapFromStoredCredentials() async {
    if Task.isCancelled { return }
    let sp = AppLog.launchSignposter.beginInterval("bootstrap")
    defer { AppLog.launchSignposter.endInterval("bootstrap", sp) }
    guard ABSAPIClient.normalizeServerURL(serverURL) != nil, !token.isEmpty else { return }
    bootstrapSupersededByOffline = false

    // SwiftData-Store für den aktiven Account öffnen/wechseln (noch ohne Domänen-Daten, siehe Migrationsplan).
    if let localStore = currentLocalLibraryStore() {
      Task.detached(priority: .utility) {
        await localStore.markOpened()
      }
    }

    if offlineHomeMode {
      isAppBootstrapInProgress = false
      scheduleFinishDeferredLaunchLocalRestore()
      await bootstrapLocalSessionOnly()
      scheduleDeferredWorkAfterConnect()
      return
    }

    // Nur Downloads-Manifest früh — Katalog/Prewarm erst nach Connect + Home/Player.
    scheduleFinishDeferredLaunchLocalRestore()

    // `restoreHomeLaunchStateFromLocalStore()` in init — Home/Katalog sofort aus Cache.
    let hadCachedBootstrap = hasCachedBootstrapContent
    if !hadCachedBootstrap {
      isAppBootstrapInProgress = true
    }
    defer {
      if !bootstrapSupersededByOffline {
        isAppBootstrapInProgress = false
        flushTabVisibilityAfterBootstrap()
      }
      bootstrapSupersededByOffline = false
    }
    restoreServerClientIfNeeded()

    if hadCachedBootstrap {
      // LocalStore: Netzwerk parallel; Overlay bleibt bis Floating Bar bereit.
      deferredBootstrapNetworkTask?.cancel()
      deferredBootstrapNetworkTask = Task(priority: .utility) { @MainActor in
        await self.performDeferredBootstrapNetworkRefresh()
      }
      await finishLaunchPresentationAfterBootstrap()
      return
    }

    // Ohne Cache: Overlay bis Continue online (ggf. nach Authorize-Fallback).
    await performDeferredBootstrapNetworkRefresh()
    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
    await finishLaunchPresentationAfterBootstrap()
  }

  /// Home-Refresh und Mini-Player nach Bootstrap — blockiert Kaltstart nur ohne Cache.
  private func finishLaunchPresentationAfterBootstrap() async {
    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
    let hadCachedHome = !startShelves.isEmpty
    async let home = loadStartDashboard(
      skipAuthorizeRefresh: true,
      force: !hadCachedHome
    )
    async let player: Void = restoreLastPlayedOnLaunch()
    _ = await (home, player)
    await waitForLaunchFloatingPlayerReady()
    floatingChrome.syncChrome()
    if hadCachedHome {
      // Server-Abgleich im Hintergrund — local-first: kein Continue-Replace, Continue reading bleibt.
      Task(priority: .utility) { @MainActor in
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !self.offlineHomeUIActive, !self.bootstrapSupersededByOffline else { return }
        await self.loadStartDashboard(skipAuthorizeRefresh: true, force: true)
      }
    }
    scheduleDeferredWorkAfterConnect()
  }

  /// Katalog-Caches, Tab-Prewarm und Server-Reload — erst nach Connect, Home und Player.
  private func scheduleDeferredWorkAfterConnect() {
    guard !suppressDeferredWorkAfterBootstrap else { return }
    scheduleDeferredCatalogLocalRestoreAfterBootstrap()
    scheduleSecondaryTabPrewarm()
    scheduleDeferredCatalogReloadAfterBootstrap()
  }

  /// Laufende Bootstrap-/Katalog-Tasks abbrechen (Account-Wechsel, Logout, Offline während Bootstrap).
  private func cancelDeferredBootstrapWork() {
    bootstrapCatalogReloadTask?.cancel()
    bootstrapCatalogReloadTask = nil
    deferredCatalogLocalRestoreTask?.cancel()
    deferredCatalogLocalRestoreTask = nil
    launchLocalRestoreTask?.cancel()
    launchLocalRestoreTask = nil
    homeLaunchLocalRestoreTask?.cancel()
    homeLaunchLocalRestoreTask = nil
    deferredBootstrapNetworkTask?.cancel()
    deferredBootstrapNetworkTask = nil
    deferredBootstrapAuthorizeTask?.cancel()
    deferredBootstrapAuthorizeTask = nil
    deferredLibrariesFetchTask?.cancel()
    deferredLibrariesFetchTask = nil
    storedCredentialsBootstrapTask?.cancel()
    storedCredentialsBootstrapTask = nil
    startDashboardPostProcessingTask?.cancel()
    startDashboardPostProcessingTask = nil
    booksToolbarSortReloadTask?.cancel()
    booksToolbarSortReloadTask = nil
    podcastCatalogSortReloadTask?.cancel()
    podcastCatalogSortReloadTask = nil
    searchTask?.cancel()
    searchTask = nil
    podcastSearchTask?.cancel()
    podcastSearchTask = nil
    podcastDirectorySearchTask?.cancel()
    podcastDirectorySearchTask = nil
    podcastLibrarySearchTask?.cancel()
    podcastLibrarySearchTask = nil
    deferredBooksCatalogLocalRestoreScheduled = false
    deferredBrowseListsLocalRestoreScheduled = false
    shouldPrewarmSecondaryTabs = false
  }

  /// Nach Account-Wechsel: LocalStore + Server-Kataloge für alle Tabs neu aufbauen.
  private func reloadAllViewsAfterAccountSwitch() async {
    guard !offlineHomeUIActive else { return }
    cancelDeferredBootstrapWork()
    await finishDeferredLaunchLocalRestore()
    async let settings: Bool = reloadSettingsTab(reloadCatalogs: true)
    async let home = loadStartDashboard(skipAuthorizeRefresh: true, force: true)
    _ = await (settings, home)
    scheduleSecondaryTabPrewarm()
  }

  /// Floating Bar: kurz stabilisieren bis Titel/Controls sichtbar (oder kein Resume).
  private func waitForLaunchFloatingPlayerReady() async {
    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
    var stableReadyStreak = 0
    for _ in 0..<120 {
      if bootstrapSupersededByOffline || offlineHomeUIActive { return }
      floatingChrome.syncChrome()
      if isLaunchFloatingPlayerReadyForInteraction() {
        stableReadyStreak += 1
        if stableReadyStreak >= 3 {
          try? await Task.sleep(nanoseconds: 150_000_000)
          floatingChrome.syncChrome()
          return
        }
      } else {
        stableReadyStreak = 0
      }
      // Kein Resume — Restore abgeschlossen, Floating Bar entfällt.
      if !isRestoringLaunchPlayback, !isPreparingPlayback, player.activeBook == nil {
        return
      }
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  private func isLaunchFloatingPlayerReadyForInteraction() -> Bool {
    guard !isRestoringLaunchPlayback, !isPreparingPlayback else { return false }
    guard player.activeBook != nil else { return true }
    guard player.isPlaybackControlsReady else { return false }
    let snap = TabAccessoryMiniPlayerSnapshot.make(model: self)
    guard snap.activeBookId != nil, snap.canTogglePlayback, !snap.showsConnectionLoading else { return false }
    let title = snap.primaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title != "Loading…" else { return false }
    return floatingChrome.gate.chromeVisible
  }

  /// Lazy-Bootstrap: Continue ohne `/authorize`; Authorize nur bei fehlgeschlagenem Continue-Refresh.
  /// URLSession mit `waitsForConnectivity = true` queued Requests automatisch — kein `NWPathMonitor`-Polling nötig.
  /// Nach erfolgreichem Continue: `/authorize` deferred nachladen für User-Type/Admin-Status.
  private func performDeferredBootstrapNetworkRefresh() async {
    let sp = AppLog.launchSignposter.beginInterval("refreshBootstrap")
    defer { AppLog.launchSignposter.endInterval("refreshBootstrap", sp) }
    isDeferredBootstrapNetworkRefreshInProgress = true
    defer { isDeferredBootstrapNetworkRefreshInProgress = false }

    if bootstrapSupersededByOffline || offlineHomeMode { return }

    guard ABSAPIClient.normalizeServerURL(serverURL) != nil, !token.isEmpty else { return }
    restoreServerClientIfNeeded()
    guard client != nil else { return }
    offlineHomeModeAuto = false

    let forceContinue = !hasCachedBootstrapContent
    var result = await loadStartDashboard(skipAuthorizeRefresh: true, force: forceContinue)
    if needsAuthorizeFallbackForContinue(result, attemptedOnline: result.attemptedNetwork) {
      await refreshProgressFromServer()
      guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
      result = await loadStartDashboard(skipAuthorizeRefresh: true, force: true)
      if !result.appliedOnline, let error = result.error, !hasCachedBootstrapContent {
        isRestoringLaunchPlayback = false
        player.setMiniPlayerPlaceholder(false)
        publishErrorUnlessBenignCancellation(error)
        if !isAuthHTTPStatus(error) {
          isServerReachable = false
          offlineHomeModeAuto = true
          mainTab = .start
          await prepareForOfflineHomeMode()
          await bootstrapLocalSessionOnly()
          await reloadLibraryViewsForModeTransition()
        }
        return
      }
    }

    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }

    if !result.attemptedNetwork {
      // Cache bereits vorhanden → `loadStartDashboard` hat früh zurückgegeben, ohne
      // tatsächlich einen Request zu starten. Erreichbarkeit darf dann nicht einfach
      // angenommen werden — echter Probe-Call statt Blindvertrauen.
      await probeServerConnection()
      guard isServerReachable else { return }
      // Bereits per `probeServerConnection()` autorisiert — kein zweiter `/authorize`-Call nötig,
      // aber Bibliotheksliste im Hintergrund trotzdem wie im Normalpfad nachziehen.
      scheduleDeferredLibrariesFetchFromServer()
      return
    }

    isServerReachable = true
    // `/authorize` deferred: User-Type (admin/root), Media-Progress, Bookmarks.
    // Nicht blockierend für Home — läuft parallel zum Libraries-Fetch.
    deferredBootstrapAuthorizeTask?.cancel()
    deferredBootstrapAuthorizeTask = Task(priority: .utility) { @MainActor [weak self] in
      guard let self, let c = self.client else { return }
      do {
        let auth = try await c.authorize()
        guard !Task.isCancelled, !self.bootstrapSupersededByOffline else { return }
        self.applyAuthorizeSession(auth)
      } catch {
        if !AbstandErrorFilter.isBenignCancellation(error) {
          AppLog.bootstrap.warning("Deferred authorize failed: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
    scheduleDeferredLibrariesFetchFromServer()
  }

  private func isAuthHTTPStatus(_ error: Error?) -> Bool {
    guard let error else { return false }
    guard case ABSAPIError.httpStatus(let code, _) = error else { return false }
    return code == 401 || code == 403
  }

  private func hasCachedContinueInLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext() else { return false }
    var progressDescriptor = FetchDescriptor<LocalProgress>()
    progressDescriptor.fetchLimit = 1
    if !((try? context.fetch(progressDescriptor)) ?? []).isEmpty { return true }
    guard let libId = selectedBooksLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines),
      !libId.isEmpty
    else { return false }
    if let cached = LocalLibraryQueries.homeShelves(context: context, libraryId: libId) {
      return cached.contains { isHomeContinueCategory($0.category) && ($0.hasBooks || $0.hasPodcastEpisodes) }
    }
    return false
  }

  /// Gewählte Podcast-Bibliothek oder gespeicherter Stub (Kaltstart vor Katalog-Restore).
  private func resolvedPodcastLibraryId() -> String? {
    if let id = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
      return id
    }
    let stored =
      UserDefaults.standard.string(forKey: Keys.podcastsLibrary)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if stored.isEmpty || stored == Keys.librarySelectionNone { return nil }
    return stored
  }

  private func hasOpenProgressExpectingContinue() -> Bool {
    progressByItemId.values.contains {
      !$0.isFinished && $0.currentTime > Self.continueListeningMinPositionSeconds
    }
  }

  private func continueShelfHasVisibleItems() -> Bool {
    guard let idx = preferredHomeContinueShelfIndex() else { return false }
    let shelf = startShelves[idx]
    return !shelf.books.isEmpty || !shelf.podcastEpisodes.isEmpty
  }

  /// Entscheidet, ob nach fehlgeschlagenem Token-Continue ein `/authorize` nötig ist.
  private func needsAuthorizeFallbackForContinue(
    _ result: ContinueRefreshAttemptResult,
    attemptedOnline: Bool
  ) -> Bool {
    if isAuthHTTPStatus(result.error) { return true }
    guard attemptedOnline else { return false }
    if !result.appliedOnline {
      if hasCachedContinueInLocalStore() || hasCachedBootstrapContent { return false }
      return true
    }
    repairContinueListeningShelfFromLocalProgressOnly()
    syncContinueListeningShelvesWithProgress()
    if hasOpenProgressExpectingContinue(), !continueShelfHasVisibleItems() {
      return true
    }
    return false
  }

  /// Bibliotheksliste nach Lazy-Bootstrap — nicht blockierend für Home/Overlay.
  private func scheduleDeferredLibrariesFetchFromServer() {
    deferredLibrariesFetchTask?.cancel()
    deferredLibrariesFetchTask = Task(priority: .utility) { @MainActor [weak self] in
      await self?.refreshLibrariesFromServerInBackground()
    }
  }

  private func refreshLibrariesFromServerInBackground() async {
    guard !bootstrapSupersededByOffline, !offlineHomeUIActive else { return }
    guard mayUseServerNetwork, isNetworkReachable else { return }
    restoreServerClientIfNeeded()
    guard let c = client else { return }
    do {
      libraries = try await c.libraries()
      if bootstrapSupersededByOffline || offlineHomeUIActive { return }
      let defaultLibId = UserDefaults.standard.string(forKey: Keys.userDefaultLibraryId)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      await resolveLibrariesAfterServerFetch(
        userDefaultLibraryId: (defaultLibId?.isEmpty == false) ? defaultLibId : nil
      )
    } catch {}
  }

  var hasCachedBootstrapContent: Bool {
    if !startShelves.isEmpty || !books.isEmpty || !podcastEpisodes.isEmpty { return true }
    return hasCachedLaunchArtifactsInLocalStore()
  }

  /// LocalStore-Artefakte für schnellen Kaltstart (auch wenn Regale im Speicher noch leer sind).
  private func hasCachedLaunchArtifactsInLocalStore() -> Bool {
    guard cacheAccountURL() != nil else { return false }
    if hasCachedContinueInLocalStore() { return true }
    guard let context = currentLocalLibraryMainContext() else { return false }
    var descriptor = FetchDescriptor<LocalProgress>()
    descriptor.fetchLimit = 1
    return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
  }

  /// Bootstrap direkt nach init — `.task` auf der Root-View kommt oft erst Sekunden später.
  private func scheduleBootstrapFromStoredCredentials() {
    storedCredentialsBootstrapTask?.cancel()
    storedCredentialsBootstrapTask = Task(priority: .userInitiated) { @MainActor [weak self] in
      await self?.bootstrapFromStoredCredentials()
    }
  }

  /// Katalog-Caches aus LocalStore — gestaffelt nach Bootstrap, nicht beim Tab-Wechsel.
  private func scheduleDeferredCatalogLocalRestoreAfterBootstrap() {
    guard !deferredBooksCatalogLocalRestoreScheduled else { return }
    deferredBooksCatalogLocalRestoreScheduled = true
    deferredCatalogLocalRestoreTask?.cancel()
    deferredCatalogLocalRestoreTask = Task(priority: .utility) { @MainActor [weak self] in
      // Ein Yield statt fixem Sleep — Home-Frame hat Vorrang, LocalStore-Restore folgt sofort danach.
      await Task.yield()
      try? await Task.sleep(nanoseconds: 500_000_000)
      await Task.yield()
      guard let self, !Task.isCancelled, !self.offlineHomeUIActive, !self.bootstrapSupersededByOffline else { return }
      if self.books.isEmpty {
        await self.restoreBooksCatalogPagesFromLocalStoreAsync()
      }
      await Task.yield()
      guard !Task.isCancelled else { return }
      if !self.deferredBrowseListsLocalRestoreScheduled {
        self.deferredBrowseListsLocalRestoreScheduled = true
        self.restoreAllBrowseListsFromLocalStore()
      }
      await Task.yield()
      guard !Task.isCancelled else { return }
      if self.podcastEpisodes.isEmpty, self.podcastShows.isEmpty {
        self.restorePodcastCatalogFromLocalStore()
      }
      await Task.yield()
      guard !Task.isCancelled else { return }
      guard let account = self.cacheAccountURL() else { return }
      // Ganz am Ende der Idle-Kette, außerhalb des MainActor-Takts: alte/verwaiste Cover
      // (nach Revision-Wechsel) begrenzen, ohne den Start zu belasten.
      Task.detached(priority: .background) {
        CoverImageCache.pruneStaleEntries(account: account)
      }
    }
  }

  /// Tab-Views nach kurzer Idle-Phase vorbauen — Wechsel ohne Erst-Mount-Ruckler.
  private func scheduleSecondaryTabPrewarm() {
    Task { @MainActor [weak self] in
      await Task.yield()
      try? await Task.sleep(nanoseconds: 500_000_000)
      self?.shouldPrewarmSecondaryTabs = true
    }
  }

  /// Bibliotheks-Kataloge nach Bootstrap — niedrige Priorität, Home bleibt bedienbar.
  private func scheduleDeferredCatalogReloadAfterBootstrap() {
    bootstrapCatalogReloadTask?.cancel()
    bootstrapCatalogReloadTask = Task(priority: .utility) { @MainActor [weak self] in
      // Statt eines geschätzten Fix-Delays: auf den LocalStore-Restore warten (der eigentliche
      // Vorlauf, den wir abpuffern wollen) und danach nur noch eine kurze Sicherheitsspanne.
      await self?.deferredCatalogLocalRestoreTask?.value
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      await Task.yield()
      guard let self, !Task.isCancelled, !self.offlineHomeUIActive, !self.bootstrapSupersededByOffline else { return }
      // Bücher- und Podcast-Katalog sind unabhängig — parallel laden.
      // `preserveOtherCachedPages`: stiller Hintergrund-Refresh mit unverändertem Sort/Filter —
      // Folgeseiten im LocalStore nicht wegen der frischen Seite 0 wegwerfen.
      async let books: Void = self.reloadLibrary(reset: true, preserveOtherCachedPages: true)
      async let podcasts: Void = self.reloadPodcastLibrary(reset: true)
      _ = await (books, podcasts)
    }
  }

  /// App-Start / Auto-Offline: nur LocalStore und Downloads, kein Netzwerk.
  private func bootstrapLocalSessionOnly() async {
    ensureLocalProgressLoaded()
    await loadStartDashboard()
    isRestoringLaunchPlayback = false
    player.setMiniPlayerPlaceholder(false)
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
    await adaptActivePlaybackForOfflineHomeMode()
    isServerReachable = false
    player.suspendServerNetworkingForOfflineMode()
    client = nil
  }

  /// Stream-Wiedergabe ohne Download beenden; bei lokalem Download auf Dateien umschalten.
  private func adaptActivePlaybackForOfflineHomeMode() async {
    guard player.activeBook != nil else { return }
    if player.isUsingLocalTrackFiles { return }

    let position = player.globalPosition
    let wasPlaying = player.isPlaying

    if let episode = podcastEpisodeForActivePlayback() {
      let storageKey = podcastEpisodeOfflineStorageId(episode)
      if localDownloadRoot(for: storageKey) != nil {
        player.tearDownPlayer()
        await playPodcastEpisode(episode, autoPlay: wasPlaying, resumeAtOverride: position)
        floatingChrome.syncChrome()
        return
      }
    } else if let book = player.activeBook, resolvedLocalDownloadForPlayback(book: book) != nil {
      player.tearDownPlayer()
      await play(book: book, resumeAtOverride: position, autoPlay: wasPlaying)
      floatingChrome.syncChrome()
      return
    }

    await dismissPlayer(idlePlaceholder: false)
    floatingChrome.syncChrome()
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
    if isLoggedIn {
      syncStoredAccountFromSession()
    }
    defer { refreshDownloadedShelfFromManifests() }
    bootstrapSupersededByOffline = false
    isAppBootstrapInProgress = true
    defer {
      if !bootstrapSupersededByOffline {
        isAppBootstrapInProgress = false
        flushTabVisibilityAfterBootstrap()
      }
      bootstrapSupersededByOffline = false
    }
    offlineHomeModeAuto = false
    var serverSessionEstablished = false
    do {
      let res = try await ABSAPIClient.login(server: url, username: username, password: password)
      if bootstrapSupersededByOffline || offlineHomeMode { return }
      token = res.user.token
      serverURL = server.trimmingCharacters(in: .whitespacesAndNewlines)
      UserDefaults.standard.set(serverURL, forKey: Keys.server)
      UserDefaults.standard.set(token, forKey: Keys.token)
      let c = ABSAPIClient(baseURL: url, token: token)
      client = c
      serverSessionEstablished = true
      applyAuthorizeSession(res)
      syncStoredAccountFromSession()
      loadDownloadedItemIdsForActiveAccount()
      isServerReachable = true
      libraries = try await c.libraries()
      if bootstrapSupersededByOffline || offlineHomeMode { return }
      await resolveLibrariesAfterServerFetch(userDefaultLibraryId: res.userDefaultLibraryId)
      if bootstrapSupersededByOffline || offlineHomeMode { return }
      mainTab = .start
      await finishLaunchPresentationAfterBootstrap()
    } catch {
      if bootstrapSupersededByOffline || offlineHomeMode { return }
      isRestoringLaunchPlayback = false
      player.setMiniPlayerPlaceholder(false)
      publishErrorUnlessBenignCancellation(error)
      if serverSessionEstablished {
        isServerReachable = true
        mainTab = .start
        await finishLaunchPresentationAfterBootstrap()
        return
      }
      isServerReachable = false
    }
  }

  /// Entfernt den aktiven Account und wechselt zum nächsten gespeicherten — oder zeigt Login.
  func logout() {
    guard let key = activeAccountKey ?? resolvedStoredAccountKey() else {
      clearInMemorySessionState(clearCredentials: true)
      return
    }
    removeStoredAccount(accountKey: key)
  }

  /// Account aus der Liste entfernen; bei aktivem Account wie `logout()` zum nächsten wechseln.
  func removeStoredAccount(accountKey: String) {
    let key = accountKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return }
    let removingActive = key == activeAccountKey
    if removingActive { syncStoredAccountFromSession() }
    storedAccounts.removeAll { $0.accountKey == key }
    persistStoredAccounts()
    guard removingActive else { return }
    if let next = storedAccounts.first {
      Task { await switchToAccount(next.accountKey) }
      return
    }
    activeAccountKey = nil
    ABSStoredAccountsPersistence.saveActiveAccountKey(nil)
    clearInMemorySessionState(clearCredentials: true)
  }

  func isActiveStoredAccount(_ account: ABSStoredAccount) -> Bool {
    account.accountKey == activeAccountKey
  }

  func switchToAccount(_ accountKey: String) async {
    guard !isSwitchingAccount else { return }
    guard accountKey != activeAccountKey,
      let account = storedAccounts.first(where: { $0.accountKey == accountKey })
    else { return }
    isSwitchingAccount = true
    defer { isSwitchingAccount = false }
    syncStoredAccountFromSession()
    persistDownloads(skipRefresh: true)
    CoverImageCache.evictMemory()
    coverImageCacheRevision &+= 1
    clearInMemorySessionState(clearCredentials: false)
    serverURL = account.serverURL
    token = account.token
    UserDefaults.standard.set(serverURL, forKey: Keys.server)
    UserDefaults.standard.set(token, forKey: Keys.token)
    activeAccountKey = accountKey
    ABSStoredAccountsPersistence.saveActiveAccountKey(accountKey)
    // Vor Authorize: UserId setzen, damit LocalStore und Home sofort zum richtigen Account zeigen.
    let switchedUserId = account.userId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !switchedUserId.isEmpty {
      sessionUserId = switchedUserId
      UserDefaults.standard.set(switchedUserId, forKey: Keys.sessionUserId)
    }
    sessionUsername = account.username
    sessionUserType = account.userType ?? "user"
    applyLibraryPreferencesFromStoredAccount(account)
    loadDownloadedItemIdsForActiveAccount()
    if let cacheRoot = cacheAccountURL() {
      EbookLocalStore.updateActiveSession(account: cacheRoot, userId: switchedUserId.isEmpty ? nil : switchedUserId)
    }
    restoreHomeLaunchStateFromLocalStore(libraryIdOverride: account.booksLibraryId)
    isAppBootstrapInProgress = true
    storedCredentialsBootstrapTask?.cancel()
    storedCredentialsBootstrapTask = nil
    suppressDeferredWorkAfterBootstrap = true
    defer { suppressDeferredWorkAfterBootstrap = false }
    await bootstrapFromStoredCredentials()
    accountSessionEpoch &+= 1
    await reloadAllViewsAfterAccountSwitch()
  }

  private static func bootstrapStoredAccountsState() -> (accounts: [ABSStoredAccount], activeKey: String?) {
    var accounts = ABSStoredAccountsPersistence.loadAccounts()
    if accounts.isEmpty {
      accounts = migrateLegacySingleAccountIntoStore()
    }
    var activeKey = ABSStoredAccountsPersistence.loadActiveAccountKey()
    if activeKey == nil, let first = accounts.first {
      activeKey = first.accountKey
      ABSStoredAccountsPersistence.saveActiveAccountKey(activeKey)
    }
    if let currentKey = activeKey, !accounts.contains(where: { $0.accountKey == currentKey }),
      let fallback = accounts.first
    {
      activeKey = fallback.accountKey
      ABSStoredAccountsPersistence.saveActiveAccountKey(activeKey)
    }
    return (accounts, activeKey)
  }

  private static func migrateLegacySingleAccountIntoStore() -> [ABSStoredAccount] {
    let server = UserDefaults.standard.string(forKey: Keys.server)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let token = UserDefaults.standard.string(forKey: Keys.token)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let userId = UserDefaults.standard.string(forKey: Keys.sessionUserId)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard ABSAPIClient.normalizeServerURL(server) != nil, !token.isEmpty, !userId.isEmpty else { return [] }
    let account = ABSStoredAccount(
      accountKey: ABSStoredAccount.makeKey(serverURL: server, userId: userId),
      serverURL: server,
      token: token,
      userId: userId,
      username: "",
      userType: nil,
      booksLibraryId: UserDefaults.standard.string(forKey: Keys.booksLibrary),
      podcastsLibraryId: UserDefaults.standard.string(forKey: Keys.podcastsLibrary),
      ebooksLibraryId: UserDefaults.standard.string(forKey: Keys.booksLibrary),
      lastUsedAt: Date()
    )
    ABSStoredAccountsPersistence.saveAccounts([account])
    ABSStoredAccountsPersistence.saveActiveAccountKey(account.accountKey)
    return [account]
  }

  func syncStoredAccountFromSession() {
    syncStoredAccountFromSession(markActive: true)
  }

  private func syncStoredAccountFromSession(markActive: Bool) {
    guard ABSAPIClient.normalizeServerURL(serverURL) != nil, !token.isEmpty else { return }
    let userId = sessionUserId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !userId.isEmpty else { return }
    let key = ABSStoredAccount.makeKey(serverURL: serverURL, userId: userId)
    let booksLib = UserDefaults.standard.string(forKey: Keys.booksLibrary)
    let podcastsLib = UserDefaults.standard.string(forKey: Keys.podcastsLibrary)
    if let idx = storedAccounts.firstIndex(where: { $0.accountKey == key }) {
      storedAccounts[idx].token = token
      storedAccounts[idx].serverURL = serverURL
      storedAccounts[idx].userId = userId
      storedAccounts[idx].username = sessionUsername
      storedAccounts[idx].userType = sessionUserType.isEmpty ? nil : sessionUserType
      storedAccounts[idx].booksLibraryId = booksLib
      storedAccounts[idx].podcastsLibraryId = podcastsLib
      storedAccounts[idx].ebooksLibraryId = booksLib
    } else if let legacyIdx = activeAccountKey.flatMap({ key in storedAccounts.firstIndex(where: { $0.accountKey == key }) }),
      storedAccounts[legacyIdx].userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      // Migration: userId war beim ersten Speichern noch leer — Eintrag umbenennen.
      storedAccounts[legacyIdx].accountKey = key
      storedAccounts[legacyIdx].token = token
      storedAccounts[legacyIdx].serverURL = serverURL
      storedAccounts[legacyIdx].userId = userId
      storedAccounts[legacyIdx].username = sessionUsername
      storedAccounts[legacyIdx].userType = sessionUserType.isEmpty ? nil : sessionUserType
      storedAccounts[legacyIdx].booksLibraryId = booksLib
      storedAccounts[legacyIdx].podcastsLibraryId = podcastsLib
      storedAccounts[legacyIdx].ebooksLibraryId = booksLib
    } else {
      storedAccounts.append(
        ABSStoredAccount(
          accountKey: key,
          serverURL: serverURL,
          token: token,
          userId: userId,
          username: sessionUsername,
          userType: sessionUserType.isEmpty ? nil : sessionUserType,
          booksLibraryId: booksLib,
          podcastsLibraryId: podcastsLib,
          ebooksLibraryId: booksLib,
          lastUsedAt: Date()
        ))
    }
    if markActive {
      activeAccountKey = key
      ABSStoredAccountsPersistence.saveActiveAccountKey(key)
    }
    persistStoredAccounts()
  }

  /// Neuen Account speichern, ohne die aktuelle Session zu wechseln.
  func addStoredAccount(server: String, username: String, password: String) async -> Bool {
    errorMessage = nil
    guard let url = ABSAPIClient.normalizeServerURL(server) else {
      errorMessage = "Please enter a valid server URL."
      return false
    }
    syncStoredAccountFromSession()
    let preserveActiveKey = activeAccountKey
    do {
      let res = try await ABSAPIClient.login(server: url, username: username, password: password)
      upsertStoredAccountFromUser(
        res.user,
        serverURL: server.trimmingCharacters(in: .whitespacesAndNewlines),
        markActive: false
      )
      activeAccountKey = preserveActiveKey
      ABSStoredAccountsPersistence.saveActiveAccountKey(preserveActiveKey)
      persistStoredAccounts()
      return true
    } catch {
      publishErrorUnlessBenignCancellation(error)
      return false
    }
  }

  private func upsertStoredAccountFromUser(_ user: ABSUser, serverURL: String, markActive: Bool) {
    let userId = user.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !userId.isEmpty else { return }
    let key = ABSStoredAccount.makeKey(serverURL: serverURL, userId: userId)
    if let idx = storedAccounts.firstIndex(where: { $0.accountKey == key }) {
      storedAccounts[idx].token = user.token
      storedAccounts[idx].serverURL = serverURL
      storedAccounts[idx].userId = userId
      storedAccounts[idx].username = user.username
      storedAccounts[idx].userType = user.type
    } else {
      storedAccounts.append(
        ABSStoredAccount(
          accountKey: key,
          serverURL: serverURL,
          token: user.token,
          userId: userId,
          username: user.username,
          userType: user.type,
          booksLibraryId: nil,
          podcastsLibraryId: nil,
          ebooksLibraryId: nil,
          lastUsedAt: Date()
        ))
    }
    if markActive {
      activeAccountKey = key
      ABSStoredAccountsPersistence.saveActiveAccountKey(key)
    }
    persistStoredAccounts()
  }

  private func resolvedStoredAccountKey() -> String? {
    let userId = sessionUserId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !userId.isEmpty else { return activeAccountKey }
    return ABSStoredAccount.makeKey(serverURL: serverURL, userId: userId)
  }

  private func persistStoredAccounts() {
    ABSStoredAccountsPersistence.saveAccounts(storedAccounts)
  }

  private func applyLibraryPreferencesFromStoredAccount(_ account: ABSStoredAccount) {
    applyStoredLibraryPreference(account.booksLibraryId, key: Keys.booksLibrary)
    applyStoredLibraryPreference(account.podcastsLibraryId, key: Keys.podcastsLibrary)
  }

  private func applyStoredLibraryPreference(_ value: String?, key: String) {
    if let value, !value.isEmpty {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }

  private func clearInMemorySessionState(clearCredentials: Bool) {
    cancelDeferredBootstrapWork()
    mainTab = .start
    if clearCredentials {
      clearCoverImageCache()
    }
    suppressOfflineModeSideEffects = true
    offlineHomeMode = false
    offlineHomeModeAuto = false
    isServerReachable = false
    isAppBootstrapInProgress = false
    pendingPostOfflineModeProgressSync = false
    pendingPostOfflineModeCatalogReload = false
    pendingLocalProgressSyncKeys = []
    UserDefaults.standard.removeObject(forKey: Keys.pendingOfflineListeningSeconds)
    suppressOfflineModeSideEffects = false
    if clearCredentials {
      token = ""
      serverURL = ""
      UserDefaults.standard.removeObject(forKey: Keys.token)
      UserDefaults.standard.removeObject(forKey: Keys.server)
    }
    isServerAdmin = false
    isServerRoot = false
    serverSettings = nil
    client = nil
    libraries = []
    selectedBooksLibrary = nil
    selectedBooksLibrary = nil
    selectedPodcastLibrary = nil
    books = []
    podcastEpisodes = []
    pendingPodcastRefreshOnResume = false
    podcastShows = []
    podcastSelectedShowId = nil
    podcastCatalogStripSectionId = PodcastCatalogStripSection.newEpisodes
    podcastFilteredEpisodes = []
    podcastFilteredEpisodesByShowId = [:]
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
    clearPodcastLibrarySearchResults()
    podcastLibrarySearchText = ""
    podcastCatalogStripSectionId = PodcastCatalogStripSection.newEpisodes
    clearPodcastDirectorySearch()
    clearPodcastCharts()
    podcastDirectoryCountryOverride = nil
    syncPodcastDirectoryEffectiveCountry()
    progressByItemId = [:]
    pendingLocalProgressSyncKeys = []
    localFinishedProgressKeys = []
    suppressedContinueListeningKeys = []
    persistLocalFinishedProgressKeys()
    bookmarks = []
    ebookReaderSession = nil
    isPreparingEbook = false
    sessionUserId = ""
    sessionUsername = ""
    sessionUserType = ""
    UserDefaults.standard.removeObject(forKey: Keys.sessionUserId)
    EbookLocalStore.updateActiveSession(account: clearCredentials ? nil : cacheAccountURL(), userId: nil)
    listeningStats = nil
    listeningStatsFetchedAt = nil
    listeningAchievementsRebuildTask?.cancel()
    listeningAchievementsSnapshot = .empty
    listeningOneTimeSnapshot = .empty
    UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
    if clearCredentials {
      UserDefaults.standard.removeObject(forKey: Keys.booksLibrary)
      UserDefaults.standard.removeObject(forKey: Keys.ebooksLibrary)
      UserDefaults.standard.removeObject(forKey: Keys.podcastsLibrary)
      UserDefaults.standard.removeObject(forKey: Keys.library)
    }
    UserDefaults.standard.removeObject(forKey: Keys.startDisabledCategories)
    UserDefaults.standard.removeObject(forKey: Keys.homeBrowseCategory)
    startDisabledCategories = []
    homeBrowseCategory = ABSStartShelfLocalization.homeBrowseContinueSectionID
    startSettingsCategoryList = ABSStartShelfLocalization.settingsCategoryOrder.map {
      (category: $0, label: ABSStartShelfLocalization.displayTitle(category: $0, serverLabel: ""))
    }
    browseCollectionBooksById = [:]
    browseNarratorCoverItemIdByNarratorName = [:]
    entityDetailBooks = []
    entityDetailTotal = 0
    entityDetailDescription = nil
    entityDetailMetaReady = false
    entityDetailAuthorSeriesSections = []
    entityDetailAuthorStandaloneBooks = []
    entityDetailNavKey = nil
    entityDetailPage = 0
    libraryPage = 0
    libraryTotal = 0
    podcastAutoDownloadEnabled = false
    podcastAutoDownloadInterval = .default
    podcastMaxEpisodesToKeep = 0
    podcastMaxNewEpisodesToDownload = 3
    podcastShowTranscriptionLanguage = ""
    podcastShowTranscriptionLanguageShowId = nil
    podcastRssFeedPreviewEpisodes = []
    podcastRssFeedPreviewForShowId = nil
    player.tearDownPlayer()
    downloadedShelfBooks = []
    downloadedItemIds = []
    isRestoringLaunchPlayback = false
    isPreparingPlayback = false
    libraryEntityDetailNav = nil
    homeEntityDetailNav = nil
    searchEntityDetailNav = nil
    localProgressLoaded = false
  }

  func selectBooksLibrary(_ lib: ABSLibrary, navigateToCatalog: Bool = false) {
    if selectedBooksLibrary?.id == lib.id {
      if selectedBooksLibrary?.name != lib.name || selectedBooksLibrary?.mediaType != lib.mediaType {
        selectedBooksLibrary = lib
      }
      if books.isEmpty {
        restoreBooksCatalogAndHomeFromLocalStore(libraryIdOverride: lib.id)
        restoreAllBrowseListsFromLocalStore()
      }
      if navigateToCatalog { navigateToMedia(.audiobooks) }
      return
    }
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    libraryCatalogQuickFilter = nil
    booksBrowseSection = .books
    resetBooksBrowseLists()
    selectedBooksLibrary = lib
    UserDefaults.standard.set(lib.id, forKey: Keys.booksLibrary)
    syncStoredAccountFromSession()
    if navigateToCatalog { navigateToMedia(.audiobooks) }
    restoreBooksCatalogAndHomeFromLocalStore(libraryIdOverride: lib.id)
    restoreAllBrowseListsFromLocalStore()
  }

  func selectPodcastLibrary(_ lib: ABSLibrary, navigateToCatalog: Bool = false) {
    if selectedPodcastLibrary?.id == lib.id {
      if selectedPodcastLibrary?.name != lib.name || selectedPodcastLibrary?.mediaType != lib.mediaType {
        selectedPodcastLibrary = lib
      }
      if podcastEpisodes.isEmpty, podcastShows.isEmpty {
        restorePodcastCatalogFromLocalStore(libraryIdOverride: lib.id)
      }
      setShowPodcastsTab(true)
      if navigateToCatalog, showPodcastsTab { navigateToMedia(.podcasts) }
      return
    }
    podcastSelectedShowId = nil
    podcastCatalogStripSectionId = PodcastCatalogStripSection.newEpisodes
    podcastFilteredEpisodes = []
    selectedPodcastLibrary = lib
    UserDefaults.standard.set(lib.id, forKey: Keys.podcastsLibrary)
    syncStoredAccountFromSession()
    setShowPodcastsTab(true)
    if navigateToCatalog, showPodcastsTab { navigateToMedia(.podcasts) }
    restorePodcastCatalogFromLocalStore(libraryIdOverride: lib.id)
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
    syncStoredAccountFromSession()
    if mainTab == .library, mediaCatalogKind == .audiobooks {
      clampMediaCatalogKindIfNeeded()
      if visibleMediaCatalogKinds.isEmpty { mainTab = .start }
    }
    Task { await loadStartDashboard() }
  }

  func clearPodcastLibrarySelection() {
    clearPodcastLibraryStateWithoutPersistingNone()
    UserDefaults.standard.set(Keys.librarySelectionNone, forKey: Keys.podcastsLibrary)
    syncStoredAccountFromSession()
    setShowPodcastsTab(false)
    Task { await loadStartDashboard() }
  }

  private func clearPodcastLibraryStateWithoutPersistingNone() {
    selectedPodcastLibrary = nil
    podcastEpisodes = []
    podcastShows = []
    podcastSelectedShowId = nil
    podcastCatalogStripSectionId = PodcastCatalogStripSection.newEpisodes
    podcastFilteredEpisodes = []
    podcastLibraryPage = 0
    podcastLibraryTotal = 0
  }

  /// Kaltstart: Bibliothekswahl synchron (billig), schwere SwiftData-Ladung (Progress/Bookmarks/Home-Regale)
  /// off-MainActor — kein synchroner Block vor dem ersten Frame (vgl. `restoreBooksCatalogPagesFromLocalStoreAsync`).
  private func scheduleHomeLaunchRestoreFromLocalStore() {
    let sp = AppLog.launchSignposter.beginInterval("restoreHome")
    guard cacheAccountURL() != nil else {
      AppLog.launchSignposter.endInterval("restoreHome", sp)
      return
    }
    homeContinueRestoreGeneration &+= 1
    let restoreGeneration = homeContinueRestoreGeneration
    isHomeContinueRestoreInProgress = true
    // Podcast-Bibliothek vor Continue-Cache — sonst fehlen Podcast-Zeilen beim Kaltstart. (billig, synchron)
    restorePodcastLibrarySelectionFromLocalStore()
    let libId =
      UserDefaults.standard.string(forKey: Keys.booksLibrary)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if libId == Keys.librarySelectionNone {
      selectedBooksLibrary = nil
      applyLaunchHomeContinueAndEbookCache(libraryId: nil, parsed: [])
      isHomeContinueRestoreInProgress = false
      AppLog.launchSignposter.endInterval("restoreHome", sp)
      return
    }
    guard !libId.isEmpty else {
      applyLaunchHomeContinueAndEbookCache(libraryId: nil, parsed: [])
      isHomeContinueRestoreInProgress = false
      AppLog.launchSignposter.endInterval("restoreHome", sp)
      return
    }
    if selectedBooksLibrary == nil || selectedBooksLibrary?.id != libId {
      selectedBooksLibrary = ABSLibrary(id: libId, name: "Books", mediaType: "book", displayOrder: nil)
    }
    homeLaunchLocalRestoreTask?.cancel()
    let localStore = currentLocalLibraryStore()
    homeLaunchLocalRestoreTask = Task(priority: .userInitiated) { @MainActor [weak self] in
      defer {
        AppLog.launchSignposter.endInterval("restoreHome", sp)
        if self?.homeContinueRestoreGeneration == restoreGeneration {
          self?.isHomeContinueRestoreInProgress = false
        }
      }
      guard let self, !Task.isCancelled else { return }
      async let localSnapshot: ([ABSUserMediaProgress], [ABSAudioBookmark]) = {
        guard let localStore else { return ([], []) }
        let progress = (try? await localStore.fetchAllProgress()) ?? []
        let bookmarks = (try? await localStore.fetchAllBookmarks()) ?? []
        return (progress, bookmarks)
      }()
      async let cachedShelvesTask: [ABSStartShelfSection]? = {
        guard let localStore else { return nil }
        return await localStore.fetchHomeShelves(libraryId: libId)
      }()
      let (progressList, bookmarksList) = await localSnapshot
      let cachedShelves = await cachedShelvesTask
      guard !Task.isCancelled else { return }
      if !progressList.isEmpty {
        self.applyUserProgress(progressList, persistToDisk: false)
      }
      if !bookmarksList.isEmpty {
        self.applyUserBookmarks(bookmarksList, persistToDisk: false)
      }
      var parsed: [ABSStartShelfSection] = []
      if let cached = cachedShelves {
        parsed = cached
        let visible = parsed.filter { self.isStartCategoryEnabled($0.category) }
        if !visible.isEmpty {
          var transaction = Transaction()
          transaction.disablesAnimations = true
          withTransaction(transaction) {
            self.startShelves = visible
            self.recomputeStartBooksUnion(from: visible)
            self.updateStartSettingsCategoryList(parsed: parsed)
            self.applyContinueListeningFromCachedItemsInProgress()
            self.repairContinueListeningShelfFromLocalProgressOnly()
            self.syncContinueListeningShelvesWithProgress()
          }
          return
        }
      }
      self.applyLaunchHomeContinueAndEbookCache(libraryId: libId, parsed: parsed)
    }
  }

  /// Kaltstart: Home-Regale + Fortschritt synchron (ein Frame, kein Katalog-Scan).
  /// Weiterhin genutzt für reaktive Bibliothekswechsel (`restoreBooksCatalogAndHomeFromLocalStore`) — dort ist
  /// sofortige Zustandsübernahme gewünscht, kein Kaltstart-Block.
  private func restoreHomeLaunchStateFromLocalStore(libraryIdOverride: String? = nil) {
    let sp = AppLog.launchSignposter.beginInterval("restoreHome")
    defer { AppLog.launchSignposter.endInterval("restoreHome", sp) }
    guard cacheAccountURL() != nil else { return }
    let context = currentLocalLibraryMainContext()
    if let context {
      let progressRows = (try? context.fetch(FetchDescriptor<LocalProgress>())) ?? []
      if !progressRows.isEmpty {
        applyUserProgress(progressRows.map { $0.toABSUserMediaProgress() }, persistToDisk: false)
      }
      let bookmarkRows = (try? context.fetch(FetchDescriptor<LocalBookmark>())) ?? []
      if !bookmarkRows.isEmpty {
        applyUserBookmarks(bookmarkRows.map { $0.toABSAudioBookmark() }, persistToDisk: false)
      }
    }
    // Podcast-Bibliothek vor Continue-Cache — sonst fehlen Podcast-Zeilen beim Kaltstart.
    restorePodcastLibrarySelectionFromLocalStore()
    let libId =
      (libraryIdOverride ?? UserDefaults.standard.string(forKey: Keys.booksLibrary))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if libId == Keys.librarySelectionNone {
      selectedBooksLibrary = nil
      applyLaunchHomeContinueAndEbookCache(libraryId: nil, parsed: [])
      return
    }
    guard !libId.isEmpty else {
      applyLaunchHomeContinueAndEbookCache(libraryId: nil, parsed: [])
      return
    }
    if selectedBooksLibrary == nil || selectedBooksLibrary?.id != libId {
      selectedBooksLibrary = ABSLibrary(id: libId, name: "Books", mediaType: "book", displayOrder: nil)
    }
    var parsed: [ABSStartShelfSection] = []
    if let context, let cached = LocalLibraryQueries.homeShelves(context: context, libraryId: libId) {
      parsed = cached
      let visible = parsed.filter { isStartCategoryEnabled($0.category) }
      if !visible.isEmpty {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          startShelves = visible
          recomputeStartBooksUnion(from: visible)
          updateStartSettingsCategoryList(parsed: parsed)
          applyContinueListeningFromCachedItemsInProgress()
          repairContinueListeningShelfFromLocalProgressOnly()
          syncContinueListeningShelvesWithProgress()
        }
        return
      }
    }
    applyLaunchHomeContinueAndEbookCache(libraryId: libId, parsed: parsed)
  }

  /// Continue-Regale aus LocalStore, wenn kein `/personalized`-Snapshot da ist.
  private func applyLaunchHomeContinueAndEbookCache(
    libraryId: String?,
    parsed: [ABSStartShelfSection]
  ) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      if libraryId == nil {
        repairContinueListeningShelfFromLocalProgressOnly()
      } else {
        applyContinueListeningFromCachedItemsInProgress()
        repairContinueListeningShelfFromLocalProgressOnly()
        syncContinueListeningShelvesWithProgress()
      }
      if !parsed.isEmpty {
        updateStartSettingsCategoryList(parsed: parsed)
      }
    }
  }

  /// Nach erstem Frame: nur Downloads — große Katalog-Caches erst bei Tab-Besuch (Home bleibt flüssig).
  func scheduleFinishDeferredLaunchLocalRestore() {
    launchLocalRestoreTask?.cancel()
    launchLocalRestoreTask = Task(priority: .utility) { @MainActor [weak self] in
      await Task.yield()
      guard let self, !Task.isCancelled else { return }
      self.refreshDownloadedShelfFromManifests()
    }
  }

  private var deferredBooksCatalogLocalRestoreScheduled = false
  private var deferredBrowseListsLocalRestoreScheduled = false

  /// LocalStore-Restore (Tab-Wechsel / Bibliothekswahl / Account-Wechsel) — Katalogseiten off-MainActor geladen.
  private func finishDeferredLaunchLocalRestore() async {
    await restoreBooksCatalogPagesFromLocalStoreAsync()
    restorePodcastCatalogFromLocalStore()
    restoreAllBrowseListsFromLocalStore()
    refreshDownloadedShelfFromManifests()
  }

  /// Nur paginierter Katalog — keine Home-Regale (die kommen aus `restoreHomeLaunchStateFromLocalStore`).
  private func restoreBooksCatalogPagesFromLocalStore(libraryIdOverride: String? = nil) {
    guard let context = currentLocalLibraryMainContext() else { return }
    let libId =
      (libraryIdOverride ?? UserDefaults.standard.string(forKey: Keys.booksLibrary))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if libId == Keys.librarySelectionNone || libId.isEmpty {
      if libraryIdOverride != nil || libId == Keys.librarySelectionNone {
        applyBooksCatalogLocalMerge(books: [], total: 0, nextPage: 0)
      }
      return
    }
    let ascending = catalogSortField == .random ? true : !catalogSortDescending
    let sortKey = catalogSortField.apiSortParameter
    let filter = activeLibraryFilter
    if let merged = LocalLibraryQueries.catalog(
      context: context, libraryId: libId, sortField: sortKey, ascending: ascending, filterKey: filter,
      pageLimit: Self.libraryCatalogPageLimit
    ) {
      applyBooksCatalogLocalMerge(books: merged.items, total: merged.total, nextPage: merged.nextPage)
    } else if libraryIdOverride != nil {
      applyBooksCatalogLocalMerge(books: [], total: 0, nextPage: 0)
    }
  }

  private func restoreBooksCatalogPagesFromLocalStoreAsync(libraryIdOverride: String? = nil) async {
    guard let store = currentLocalLibraryStore() else { return }
    let libId =
      (libraryIdOverride ?? UserDefaults.standard.string(forKey: Keys.booksLibrary))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if libId == Keys.librarySelectionNone || libId.isEmpty {
      if libraryIdOverride != nil || libId == Keys.librarySelectionNone {
        applyBooksCatalogLocalMerge(books: [], total: 0, nextPage: 0)
      }
      return
    }
    let ascending = catalogSortField == .random ? true : !catalogSortDescending
    let sortKey = catalogSortField.apiSortParameter
    let filter = activeLibraryFilter
    let pageLimit = Self.libraryCatalogPageLimit
    let merged = await store.fetchCatalog(
      libraryId: libId, sortField: sortKey, ascending: ascending, filterKey: filter, pageLimit: pageLimit)
    guard let merged else {
      if libraryIdOverride != nil {
        applyBooksCatalogLocalMerge(books: [], total: 0, nextPage: 0)
      }
      return
    }
    applyBooksCatalogLocalMerge(books: merged.items, total: merged.total, nextPage: merged.nextPage)
  }

  private func applyBooksCatalogLocalMerge(books: [ABSBook], total: Int, nextPage: Int) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      self.books = books
      libraryTotal = total
      libraryPage = nextPage
    }
  }

  /// Baut den Katalog aus der lokalen SwiftData-DB auf — nur für die SOFORT-Anzeige, bevor der
  /// Server antwortet (`reloadLibrary` ersetzt die Liste bei jedem Reset unten verbindlich durch
  /// die frische Server-Seite 0). Rückgabe `true`, wenn `books` lokal gefüllt wurde:
  /// 1. Gecachte Katalogseiten in **Server-Reihenfolge**, wenn Sort/Filter exakt passen.
  /// 2. Sonst `LocalBook`-Superset, client-seitig sortiert — nur ohne Server-Filter und wenn
  ///    das Sortierfeld lokal abbildbar ist (`supportsLocalBookSort`). Der frühere stille
  ///    Titel-Fallback zeigte bei allen anderen Sortierungen eine falsche, pro Fetch
  ///    wechselnde Reihenfolge an.
  @discardableResult
  private func loadLibraryFromLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext(),
      let libId = selectedBooksLibrary?.id else { return false }
    let ascending = catalogSortField == .random ? true : !catalogSortDescending
    let sortKey = catalogSortField.apiSortParameter
    if let merged = LocalLibraryQueries.catalog(
      context: context, libraryId: libId, sortField: sortKey, ascending: ascending,
      filterKey: activeLibraryFilter, pageLimit: Self.libraryCatalogPageLimit
    ), !merged.items.isEmpty {
      applyBooksCatalogLocalMerge(books: merged.items, total: merged.total, nextPage: merged.nextPage)
      return true
    }
    // Superset nur, wenn die gewählte Sortierung lokal korrekt abbildbar ist — offline
    // ausnahmsweise auch sonst (lieber Titel-Reihenfolge als gar keine Liste, Server-Reset
    // als Korrektur ist ohne Netz ohnehin nicht möglich).
    guard activeLibraryFilter == nil,
      LocalLibraryQueries.supportsLocalBookSort(catalogSortField) || !isNetworkReachable
    else { return false }
    let localBooks = LocalLibraryQueries.allBooks(
      context: context, libraryId: libId,
      sortField: catalogSortField, descending: catalogSortDescending
    )
    guard !localBooks.isEmpty else { return false }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      books = localBooks
      libraryTotal = localBooks.count
      // Lokale Quelle ist komplett — keine serverseitige Pagination mehr nötig.
      // `libraryPage` hochsetzen, damit `loadMoreIfNeeded` (books.count < libraryTotal)
      // nicht erneut Server-Seiten anfordert, solange der Refresh noch läuft.
      libraryPage = max(1, (localBooks.count + Self.libraryCatalogPageLimit - 1)
        / Self.libraryCatalogPageLimit)
    }
    return true
  }

  /// Ersetzt bei einem stillen, unbeauftragten Hintergrund-Refresh (`preserveOtherCachedPages`)
  /// nur die ersten `pageBooks.count` Positionen von `books` durch die frische Server-Seite 0 —
  /// exakt in Server-Reihenfolge — und lässt bereits gescrollte Folgeseiten unangetastet.
  /// Dubletten (ein Buch, das die Seite jetzt enthält, aber vorher weiter hinten stand, oder
  /// umgekehrt) werden aus dem hinteren Teil entfernt, dessen Reihenfolge bleibt sonst unverändert.
  private func mergeServerFirstPageIntoLocalBooksPreservingRest(_ pageBooks: [ABSBook], total: Int) {
    guard !pageBooks.isEmpty else {
      libraryTotal = max(books.count, total)
      return
    }
    let pageIds = Set(pageBooks.map(\.id))
    let rest = books.count > pageBooks.count
      ? Array(books[pageBooks.count...]).filter { !pageIds.contains($0.id) }
      : []
    let merged = pageBooks + rest
    let unchanged =
      merged.count == books.count
      && zip(merged, books).allSatisfy { $0.id == $1.id && $0.updatedAt == $1.updatedAt }
    if !unchanged {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        books = merged
      }
    }
    libraryTotal = max(merged.count, total)
  }

  private func browseEbooksSortKey() -> (sort: String, descending: Bool) {
    let descending = catalogSortField == .random ? false : catalogSortDescending
    return (catalogSortField.apiSortParameter, descending)
  }

  func ensureBrowseEbooksLoaded() async {
    await loadBrowseEbooks(force: false)
  }

  /// `true`, sobald ein Server-Fetch in dieser App-Session gelaufen ist — verhindert, dass ein
  /// veralteter/unvollständiger lokaler Flag-Stand (`catalogHasEbook`, geteilt mit dem Haupt-Katalog)
  /// den ersten Reload beim Öffnen des Tabs blockiert (sonst nur per Pull-to-Refresh sichtbar).
  private var browseEbooksSessionFetchDone = false

  private func loadBrowseEbooks(force: Bool) async {
    guard client != nil, selectedBooksLibrary != nil else { return }
    if browseEbooksLoading { return }
    if browseEbooks.isEmpty, browseEbooksSupplementary.isEmpty {
      _ = restoreBrowseEbooksFromLocalStore()
    }
    if !force, browseEbooksSessionFetchDone { return }
    if !isNetworkReachable {
      _ = restoreBrowseEbooksFromLocalStore()
      return
    }
    await loadBrowseEbooksPage(reset: true)
    browseEbooksSessionFetchDone = true
  }

  func loadMoreBrowseEbooksIfNeeded(currentItemId: String) async {
    guard !browseEbooksLoading, browseEbooks.count < browseEbooksTotal else { return }
    guard let idx = browseEbooks.firstIndex(where: { $0.id == currentItemId }) else { return }
    guard idx >= browseEbooks.count - 8 else { return }
    await loadBrowseEbooksPage(reset: false)
  }

  private func loadBrowseEbooksPage(reset: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if !isNetworkReachable {
      _ = restoreBrowseEbooksFromLocalStore()
      return
    }
    if browseEbooksLoading { return }
    if reset {
      browseEbooksNextPage = 0
      if browseEbooks.isEmpty, browseEbooksSupplementary.isEmpty {
        _ = restoreBrowseEbooksFromLocalStore()
      }
      if browseEbooks.isEmpty {
        browseEbooksTotal = 0
      }
    } else {
      guard browseEbooksTotal > 0, browseEbooks.count < browseEbooksTotal else { return }
    }
    let page = browseEbooksNextPage
    browseEbooksLoading = true
    defer { browseEbooksLoading = false }
    do {
      let (sort, descending) = browseEbooksSortKey()
      let (ebookPage, _) = try await c.libraryItems(
        libraryId: lib.id,
        page: page,
        limit: Self.libraryCatalogPageLimit,
        sort: sort,
        ascending: !descending,
        minified: true,
        filter: Self.catalogFilterKey(group: "ebooks", value: "ebook")
      )
      let rows = ebookPage.results.filter(\.isUsableEbookListRow)
      browseEbooksTotal = ebookPage.total
      if reset || page == 0 {
        browseEbooks = rows
      } else {
        let seen = Set(browseEbooks.map(\.id))
        browseEbooks.append(contentsOf: rows.filter { !seen.contains($0.id) })
      }
      browseEbooksNextPage = page + 1
      rememberEbookFormatsFromCatalog(rows)

      if reset || page == 0 {
        let (supPage, _) = try await c.libraryItems(
          libraryId: lib.id,
          page: 0,
          limit: 200,
          sort: sort,
          ascending: !descending,
          minified: false,
          filter: Self.catalogFilterKey(group: "ebooks", value: "supplementary")
        )
        let supRows = supPage.results.filter(\.isPlayableAudiobook)
        browseEbooksSupplementary = supRows
        rememberEbookFormatsFromCatalog(supRows)
        if let store = currentLocalLibraryStore() {
          try? await store.upsertEbookCatalogBooks(pure: browseEbooks, supplementary: supRows)
        }
      } else if let store = currentLocalLibraryStore() {
        try? await store.upsertEbookCatalogBooks(pure: rows, supplementary: [])
      }
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
    refreshEbookContinueReadingShelf()
  }

  @discardableResult
  private func restoreBrowseEbooksFromLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext(), let lib = selectedBooksLibrary else { return false }
    let pure = LocalLibraryQueries.browsePureEbooks(context: context, libraryId: lib.id)
    let supp = LocalLibraryQueries.browseSupplementaryEbooks(context: context, libraryId: lib.id)
    guard !pure.isEmpty || !supp.isEmpty else { return false }
    browseEbooks = pure
    browseEbooksSupplementary = supp
    browseEbooksTotal = pure.count
    browseEbooksNextPage = (pure.count + Self.libraryCatalogPageLimit - 1) / Self.libraryCatalogPageLimit
    return true
  }

  /// Browse-Listen (Autoren, Serien, …) aus dem Datenträger — sofort sichtbar beim Tab-Wechsel.
  private func restoreAllBrowseListsFromLocalStore() {
    guard cacheAccountURL() != nil, selectedBooksLibrary != nil else { return }
    _ = restoreBrowseAuthorsFromLocalStore()
    _ = restoreBrowseSeriesFromLocalStore()
    _ = restoreBrowseNarratorsFromLocalStore()
    _ = restoreBrowseCollectionsFromLocalStore()
    _ = restoreBrowseGenresFromLocalStore()
    _ = restoreBrowseTagsFromLocalStore()
  }

  /// `preserveOtherCachedPages`: bei stillen Hintergrund-Refreshes (gleicher Sort/Filter, z.B. deferred
  /// Bootstrap-Reload) den Cache-Slug **nicht** komplett löschen — nur Seite 0 wird sofort neu geholt,
  /// ein voller Wipe würde bei großen Bibliotheken bereits gecachte Folgeseiten bis zum nächsten Scroll
  /// verlieren. Bei echtem Sort-/Filter-/Bibliothekswechsel bleibt der destruktive Wipe (Default) korrekt,
  /// weil alte Seiten dort ohnehin nicht mehr zur neuen Reihenfolge passen.
  func reloadLibrary(reset: Bool, preserveOtherCachedPages: Bool = false) async {
    guard let lib = selectedBooksLibrary else {
      await loadStartDashboard()
      return
    }
    // Lokale DB nur für die SOFORT-Anzeige, bevor der Server antwortet — deterministische
    // Reihenfolge (siehe `loadLibraryFromLocalStore`), aber nie verbindlich: Ein echter Reset
    // holt unten IMMER Seite 0 frisch vom Server und diese Antwort entscheidet die Reihenfolge.
    // (Vorherige Version hielt `libraryPage` aus dem Cache-Stand und fragte je nach Sitzung eine
    // beliebige Seite ab, gemergt statt ersetzt — daher wechselnde/falsche Sortierung bei jedem
    // Pull-to-Refresh.)
    if reset {
      loadLibraryFromLocalStore()
    }
    guard let c = client else {
      if startShelves.isEmpty { await loadStartDashboard() }
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
      let (page, _) = try await c.libraryItems(
        libraryId: lib.id,
        page: pageIndex,
        limit: Self.libraryCatalogPageLimit,
        sort: sortKey,
        ascending: ascending,
        minified: true,
        filter: activeLibraryFilter
      )
      let pageBooks = page.results.filter(\.isUsableLibraryCatalogRow)
      if let store = currentLocalLibraryStore() {
        if reset, preserveOtherCachedPages {
          try? await store.refreshCatalogFirstPagePreservingRest(
            libraryId: lib.id, sortField: sortKey, ascending: ascending, filterKey: activeLibraryFilter,
            total: page.total, items: pageBooks)
        } else if reset {
          try? await store.replaceCatalogFirstPage(
            libraryId: lib.id, sortField: sortKey, ascending: ascending, filterKey: activeLibraryFilter,
            total: page.total, items: pageBooks)
        } else {
          try? await store.appendCatalogPage(libraryId: lib.id, total: page.total, items: pageBooks)
        }
      }
      if reset, preserveOtherCachedPages {
        // Stiller Hintergrund-Refresh (z. B. nach Bootstrap): nur die ersten `pageBooks.count`
        // Positionen mit der frischen Server-Reihenfolge ersetzen, bereits gescrollte Folgeseiten
        // bleiben unangetastet — sonst würde die Liste während eines unbeauftragten Refreshs
        // sichtbar auf Seite 0 zurückschrumpfen.
        mergeServerFirstPageIntoLocalBooksPreservingRest(pageBooks, total: page.total)
      } else if reset {
        // Echter Reset (Pull-to-Refresh, Sort-/Filterwechsel): Server-Seite 0 ist verbindlich.
        let unchanged =
          pageBooks.count == books.count
          && zip(pageBooks, books).allSatisfy { $0.id == $1.id && $0.updatedAt == $1.updatedAt }
        if !unchanged { books = pageBooks }
        libraryTotal = page.total
      } else {
        books.append(contentsOf: pageBooks)
        libraryTotal = page.total
      }
      libraryPage = page.page + 1
      if reset {
        lastBooksCatalogServerSyncAt = Date()
      }
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
    if startShelves.isEmpty {
      await loadStartDashboard()
    }
  }

  /// Kataloge gelten nach dieser Spanne als veraltet — Vordergrund-Wechsel stößt dann einen
  /// stillen Server-Refresh an, der auch die lokale DB fortschreibt (Listen bleiben cache-first).
  private static let catalogStaleRefreshInterval: TimeInterval = 15 * 60
  private var lastBooksCatalogServerSyncAt: Date?
  private var lastPodcastCatalogServerSyncAt: Date?

  /// Vordergrund: Listen kommen sofort aus der lokalen DB — hier nur prüfen, ob der letzte
  /// Server-Abgleich zu lange her ist, und dann still im Hintergrund aktualisieren
  /// (`preserveOtherCachedPages`: gecachte Folgeseiten bleiben erhalten).
  func refreshCatalogsIfStaleOnForeground() {
    guard isLoggedIn, !offlineHomeUIActive, !isAppBootstrapInProgress,
      isNetworkReachable, client != nil
    else { return }
    let now = Date()
    let booksStale =
      selectedBooksLibrary != nil
      && (lastBooksCatalogServerSyncAt.map { now.timeIntervalSince($0) > Self.catalogStaleRefreshInterval } ?? true)
    let podcastsStale =
      selectedPodcastLibrary != nil
      && (lastPodcastCatalogServerSyncAt.map { now.timeIntervalSince($0) > Self.catalogStaleRefreshInterval } ?? true)
    guard booksStale || podcastsStale else { return }
    Task(priority: .utility) { @MainActor [weak self] in
      guard let self else { return }
      if booksStale {
        await self.reloadLibrary(reset: true, preserveOtherCachedPages: true)
      }
      if podcastsStale {
        await self.reloadPodcastLibrary(reset: true)
      }
    }
  }

  /// Vordergrund-Self-Heal: Falls eine Podcast-Folge im gesperrten/offline Zustand beendet wurde
  /// (Liste lokal erleichtert, kein Server-Reload gelaufen) ODER die Liste jetzt leer ist, einmal
  /// nachladen. Idempotent — schlägt der Reload fehlt oder ist offline, bleibt das Flag ohne Schaden.
  func applyPendingPodcastRefreshIfNeeded() {
    guard isLoggedIn, selectedPodcastLibrary != nil, !offlineHomeUIActive else { return }
    // Entweder explizit markiert (Folge während Sperre beendet) oder die Liste ist leer gefallen.
    let needsRefresh = pendingPodcastRefreshOnResume || podcastEpisodes.isEmpty
    guard needsRefresh else { return }
    pendingPodcastRefreshOnResume = false
    Task { @MainActor in
      await reloadPodcastLibrary(reset: true)
    }
  }

  func reloadPodcastLibrary(reset: Bool) async {
    guard let lib = selectedPodcastLibrary else { return }
    if offlineHomeUIActive {
      if podcastEpisodes.isEmpty {
        applyPodcastListFromLocalStore(libraryId: lib.id)
      }
      await reloadPodcastShowsCatalog()
      return
    }
    if !isNetworkReachable {
      if podcastEpisodes.isEmpty {
        applyPodcastListFromLocalStore(libraryId: lib.id)
      }
      if podcastShows.isEmpty {
        let ascending = podcastCatalogSortField == .random ? true : !podcastCatalogSortDescending
        let sortKey = podcastCatalogSortField.apiSortParameter
        if let context = currentLocalLibraryMainContext(),
          let rows = LocalLibraryQueries.podcastShows(
            context: context, libraryId: lib.id, sortField: sortKey, ascending: ascending)
        {
          podcastShows = rows
        }
      }
      return
    }
    guard let c = client else { return }
    isLoadingPodcasts = true
    defer { isLoadingPodcasts = false }
    if reset, podcastEpisodes.isEmpty {
      applyPodcastListFromLocalStore(libraryId: lib.id)
    }
    do {
      if reset {
        podcastLibraryPage = 0
        podcastEpisodesPagingFromRecentAPI = true
      }
      let pageIndex = podcastLibraryPage

      if podcastEpisodesPagingFromRecentAPI {
        let (res, _) = try await c.recentPodcastEpisodes(libraryId: lib.id, page: pageIndex, limit: 40)
        let rows = res.episodes.compactMap { ABSPodcastEpisodeListItem.fromDTO($0, libraryId: lib.id) }

        if rows.isEmpty, pageIndex == 0 {
          let fallback = await loadPodcastEpisodesFallback(client: c, libraryId: lib.id)
          if !fallback.isEmpty {
            podcastEpisodesPagingFromRecentAPI = false
            podcastEpisodes = fallback
            podcastLibraryTotal = fallback.count
            podcastLibraryPage = 1
            if let store = currentLocalLibraryStore() {
              try? await store.replacePodcastEpisodes(
                libraryId: lib.id, total: fallback.count, pagingFromRecentAPI: false, items: fallback)
            }
            lastPodcastCatalogServerSyncAt = Date()
            if reset { await reloadPodcastShowsCatalog() }
            return
          }
        }

        if reset {
          podcastEpisodes = ABSPodcastEpisodeListItem.dedupeRows(rows)
        } else if !rows.isEmpty {
          podcastEpisodes = ABSPodcastEpisodeListItem.dedupeRows(podcastEpisodes + rows)
        }
        if rows.count >= 40 {
          podcastLibraryTotal = max(res.total, podcastEpisodes.count + 1)
        } else {
          podcastLibraryTotal = podcastEpisodes.count
        }
        podcastLibraryPage = res.page + 1
        if let store = currentLocalLibraryStore() {
          let snapshot = podcastEpisodes
          let total = podcastLibraryTotal
          try? await store.replacePodcastEpisodes(
            libraryId: lib.id, total: total, pagingFromRecentAPI: true, items: snapshot)
        }
        if reset {
          lastPodcastCatalogServerSyncAt = Date()
        }
      }
    } catch {
      publishErrorUnlessBenignCancellation(error)
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
      let deduped = ABSPodcastEpisodeListItem.dedupeRows(collected)
      return Array(deduped.prefix(80))
    } catch {
      return []
    }
  }

  /// Folgenliste auf dem Podcast-Tab (recent „New“ oder eine Sendung), inkl. abgeschlossener Folgen.
  /// Abgeschlossene Zeilen: gleiche Kennzeichnung wie bei Büchern (`checkmark.circle.fill` in `PodcastEpisodeRowCard`).
  var podcastEpisodesForPodcastsTab: [ABSPodcastEpisodeListItem] {
    podcastEpisodesForPodcastsTab(showId: podcastSelectedShowId)
  }

  /// Folgen für Podcast-Tab: `showId` nil = „New“, sonst Sendung (eigene Pane / Cache).
  func podcastEpisodesForPodcastsTab(showId: String?) -> [ABSPodcastEpisodeListItem] {
    if offlineHomeUIActive {
      // Offline nur, was tatsächlich lokal liegt — nicht der volle (evtl. veraltete) Server-Cache.
      let sid = showId?.trimmingCharacters(in: .whitespacesAndNewlines)
      let downloaded = podcastEpisodesFromLocalDownloadManifests(showId: sid?.isEmpty == true ? nil : sid)
      return Self.sortPodcastEpisodesNewestFirst(ABSPodcastEpisodeListItem.dedupeRows(downloaded))
    }
    let offlineList = !isNetworkReachable
    var pool: [ABSPodcastEpisodeListItem]
    if let sid = showId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
      if podcastSelectedShowId == sid, !podcastFilteredEpisodes.isEmpty {
        pool = podcastFilteredEpisodes
      } else if let cached = podcastFilteredEpisodesByShowId[sid] {
        pool = cached
      } else {
        pool = podcastEpisodes.filter { $0.libraryItemId == sid }
      }
      if offlineList, pool.isEmpty {
        pool = podcastEpisodes.filter { $0.libraryItemId == sid }
      }
      if offlineList {
        pool += podcastEpisodesFromLocalDownloadManifests(showId: sid)
      }
    } else {
      pool = podcastEpisodes
      if offlineList {
        pool += podcastEpisodesFromLocalDownloadManifests(showId: nil)
      }
    }
    return Self.sortPodcastEpisodesNewestFirst(ABSPodcastEpisodeListItem.dedupeRows(pool))
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

  /// Admin-Show-Detail: Bibliotheks-Folgen + RSS + Settings (ohne Podcast-Tab-„New“-Reload).
  func preloadPodcastShowAdminContext(showId: String) async {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return }
    applyPodcastShowFilterSelection(sid)
    podcastRssDraftDownloadCompletedIds = podcastRssDraftCompletedIdsByShowId[sid] ?? []
    async let episodes: Void = loadPodcastEpisodesForShowLibraryItem(sid)
    async let settings: Void = loadPodcastAutoDownloadSettings(showId: sid)
    async let feed: Void = loadPodcastRssFeedIntoEpisodeList(
      podcastLibraryItemId: sid, forceReload: false, applyToTabPreview: false)
    _ = await (episodes, settings, feed)
  }

  /// Bibliotheks-Folge zu einem RSS-Entwurf (Titel + Veröffentlichungsdatum).
  func libraryEpisodeMatchingPodcastRssDraft(
    _ draft: ABSPodcastRssFeedEpisodeDraft,
    showId: String
  ) -> ABSPodcastEpisodeListItem? {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty, podcastSelectedShowId == sid else { return nil }
    return podcastFilteredEpisodes.first { draft.matchesLibraryEpisode($0) }
  }

  /// RSS-Tab: nur laden wenn Cache leer (oder `forceReload`).
  func ensurePodcastRssFeedLoaded(
    forShowId showId: String,
    forceReload: Bool = false,
    applyToTabPreview: Bool = true
  ) async {
    guard podcastCanManageShowsOnServer, !showId.isEmpty else { return }
    if applyToTabPreview {
      applyActivePodcastRssFeedPreview(showId: showId)
    }
    if !forceReload, podcastRssFeedUnavailableByShowId[showId] != nil { return }
    if !forceReload, !podcastRssFeedCachedDrafts(forShowId: showId).isEmpty { return }
    await loadPodcastRssFeedIntoEpisodeList(
      podcastLibraryItemId: showId, forceReload: forceReload, applyToTabPreview: applyToTabPreview)
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

    if offlineHomeUIActive {
      applyOfflinePodcastShows(libraryId: lib.id, sortField: sortKey, ascending: ascending)
      return
    }

    if !isNetworkReachable {
      if let context = currentLocalLibraryMainContext(),
        let rows = LocalLibraryQueries.podcastShows(
          context: context, libraryId: lib.id, sortField: sortKey, ascending: ascending)
      {
        podcastShows = rows
      }
      return
    }

    guard let c = client else { return }
    podcastShowsLoading = true
    defer { podcastShowsLoading = false }
    do {
      let (page, _) = try await c.libraryItems(
        libraryId: lib.id,
        page: 0,
        limit: 120,
        sort: sortKey,
        ascending: ascending,
        minified: true,
        filter: nil
      )
      let rows = page.results.filter(\.isListablePodcastLibraryItem)
      if let store = currentLocalLibraryStore() {
        try? await store.replacePodcastShows(libraryId: lib.id, sortField: sortKey, ascending: ascending, items: rows)
      }
      podcastShows = rows
    } catch {}
  }

  /// Offline: Show-Leiste auf Sendungen mit mindestens einer heruntergeladenen Folge einschränken.
  private func applyOfflinePodcastShows(libraryId: String, sortField: String, ascending: Bool) {
    var allShows = podcastShows
    if let context = currentLocalLibraryMainContext(),
      let rows = LocalLibraryQueries.podcastShows(
        context: context, libraryId: libraryId, sortField: sortField, ascending: ascending)
    {
      allShows = rows
    }
    podcastShows = allShows.filter { podcastOfflineDownloadCount(forShowId: $0.id) > 0 }
  }

  /// Sofort UI (Leiste + Filter); Netzwerk danach (Cache zuerst, Refresh im Hintergrund wenn möglich).
  func selectPodcastShowFilter(_ showId: String?) async {
    applyPodcastShowFilterSelection(showId)
    guard let showId else {
      if podcastEpisodes.isEmpty, let lib = selectedPodcastLibrary {
        applyPodcastListFromLocalStore(libraryId: lib.id)
      }
      if podcastEpisodes.isEmpty {
        await reloadPodcastLibrary(reset: true)
      }
      return
    }
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    if let cached = podcastFilteredEpisodesByShowId[sid], !cached.isEmpty {
      Task { await loadPodcastEpisodesForShowLibraryItem(showId) }
      return
    }
    await loadPodcastEpisodesForShowLibraryItem(showId)
  }

  @MainActor
  func applyPodcastShowFilterSelection(_ showId: String?) {
    let newKey = showId ?? ""
    let previewKey = podcastRssFeedPreviewForShowId ?? ""
    if newKey != previewKey {
      clearActivePodcastRssFeedPreview()
      if showId == nil {
        clearPodcastAutoDownloadSettingsDraft()
      }
    }
    podcastSelectedShowId = showId
    if let sid = showId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
      podcastCatalogStripSectionId = sid
    } else {
      podcastCatalogStripSectionId = PodcastCatalogStripSection.newEpisodes
    }
    if let sid = showId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty,
      let cached = podcastFilteredEpisodesByShowId[sid]
    {
      podcastFilteredEpisodes = cached
    } else {
      podcastFilteredEpisodes = []
    }
  }

  func loadPodcastEpisodesForShowLibraryItem(_ showId: String) async {
    guard let lib = selectedPodcastLibrary else {
      podcastFilteredEpisodes = []
      return
    }
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else {
      podcastFilteredEpisodes = []
      return
    }
    if !mayUseServerNetwork || !isNetworkReachable {
      guard podcastSelectedShowId == sid else { return }
      var pool = podcastEpisodes.filter { $0.libraryItemId == sid }
      pool += podcastEpisodesFromLocalDownloadManifests(showId: sid)
      let sorted = Self.sortPodcastEpisodesNewestFirst(ABSPodcastEpisodeListItem.dedupeRows(pool))
      podcastFilteredEpisodesByShowId[sid] = sorted
      podcastFilteredEpisodes = sorted
      return
    }
    guard let c = client else {
      podcastFilteredEpisodes = []
      return
    }
    // Cache-first: Folgenliste sofort aus dem lokal persistierten Show-Detail aufbauen
    // (LocalBook.detailBlob) — der Server-Abruf unten ersetzt sie dann nur noch still.
    if podcastFilteredEpisodesByShowId[sid]?.isEmpty != false,
      let seeded = podcastShowEpisodesFromLocalStore(showId: sid, libraryId: lib.id),
      !seeded.isEmpty
    {
      podcastFilteredEpisodesByShowId[sid] = seeded
      if podcastSelectedShowId == sid {
        podcastFilteredEpisodes = seeded
      }
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
        podcastFilteredEpisodesByShowId[sid] = []
        podcastFilteredEpisodes = []
        return
      }
      let rows: [ABSPodcastEpisodeListItem] = eps.compactMap {
        ABSPodcastEpisodeListItem.fromDTO(
          $0, fallbackShow: full, libraryId: lib.id, forceLibraryItemId: full.id)
      }
      guard serial == podcastShowEpisodesLoadSerial, podcastSelectedShowId == sid else { return }
      let sorted = Self.sortPodcastEpisodesNewestFirst(ABSPodcastEpisodeListItem.dedupeRows(rows))
      podcastFilteredEpisodesByShowId[sid] = sorted
      podcastFilteredEpisodes = sorted
      // Expandiertes Show-Detail in die lokale DB — nächster Aufruf (auch nach App-Neustart)
      // baut die Folgenliste sofort daraus auf, bevor der Server antwortet.
      persistBookDetail(full)
    } catch {
      guard serial == podcastShowEpisodesLoadSerial, podcastSelectedShowId == showId else { return }
      publishErrorUnlessBenignCancellation(error)
    }
  }

  /// Folgenliste einer Sendung aus dem persistierten Show-Detail (`LocalBook.detailBlob`) —
  /// gleiche Aufbereitung wie der Online-Pfad (`fromDTO` + dedupe + newest-first).
  private func podcastShowEpisodesFromLocalStore(
    showId: String, libraryId: String
  ) -> [ABSPodcastEpisodeListItem]? {
    guard let show = cachedBookDetail(id: showId),
      let eps = show.media.podcastEpisodes, !eps.isEmpty
    else { return nil }
    let rows: [ABSPodcastEpisodeListItem] = eps.compactMap {
      ABSPodcastEpisodeListItem.fromDTO(
        $0, fallbackShow: show, libraryId: libraryId, forceLibraryItemId: show.id)
    }
    guard !rows.isEmpty else { return nil }
    return Self.sortPodcastEpisodesNewestFirst(ABSPodcastEpisodeListItem.dedupeRows(rows))
  }

  /// Normalisiert `nil`/leere Bibliotheks-IDs auf `nil` — Manifest-Stubs liefern `String?`, das
  /// persistente `LocalPodcastEpisode` ein non-optionales `String`; ohne Angleichung behandeln
  /// Filter „unbekannt“ (`nil`) und „leer“ (`""`) je nach Quelle unterschiedlich.
  private static func normalizedLibraryId(_ raw: String?) -> String? {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Offline: Folgen aus `download.json` (ohne Server-Metadaten), für Podcast-Tab und Sendungsfilter.
  private func podcastEpisodesFromLocalDownloadManifests(showId: String?) -> [ABSPodcastEpisodeListItem] {
    let filterShow = showId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let libId = Self.normalizedLibraryId(selectedPodcastLibrary?.id)
    var out: [ABSPodcastEpisodeListItem] = []
    out.reserveCapacity(downloadedItemIds.count)
    for storageId in downloadedItemIds {
      guard let row = podcastEpisodeForDownloadedStorageId(storageId) else { continue }
      if !filterShow.isEmpty, row.libraryItemId != filterShow { continue }
      if let libId, let rowLib = Self.normalizedLibraryId(row.libraryId), rowLib != libId {
        continue
      }
      out.append(row)
    }
    return out
  }

  private static func podcastEpisodeListItem(
    from manifest: ABSDownloadManifest,
    libraryId: String?
  ) -> ABSPodcastEpisodeListItem? {
    let eid = manifest.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !eid.isEmpty else { return nil }
    let lid = manifest.libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lid.isEmpty else { return nil }
    let titleRaw = manifest.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let episodeTitle = titleRaw.isEmpty ? "Episode" : titleRaw
    let authorRaw = manifest.displayAuthor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let showTitle: String
    let authorLine: String
    if authorRaw.isEmpty || authorRaw == "—" {
      showTitle = "—"
      authorLine = "—"
    } else {
      showTitle = authorRaw
      authorLine = authorRaw
    }
    let libRaw = (libraryId ?? manifest.libraryId)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let lib: String? = libRaw.isEmpty ? nil : libRaw
    let dur = manifest.totalDuration ?? 0
    return ABSPodcastEpisodeListItem(
      libraryItemId: lid,
      libraryId: lib,
      episodeId: eid,
      episodeTitle: episodeTitle,
      showTitle: showTitle,
      authorLine: authorLine,
      duration: dur,
      publishedAt: nil
    )
  }

  private static func sortPodcastEpisodesNewestFirst(_ rows: [ABSPodcastEpisodeListItem]) -> [ABSPodcastEpisodeListItem] {
    rows.sorted {
      let pa = $0.publishedAt ?? 0
      let pb = $1.publishedAt ?? 0
      if pa != pb { return pa > pb }
      return $0.episodeTitle.localizedCaseInsensitiveCompare($1.episodeTitle) == .orderedDescending
    }
  }

  private func shouldPrefetchNextCatalogPage<Item>(
    currentItemId: String?,
    in items: [Item],
    id: (Item) -> String
  ) -> Bool {
    guard let currentItemId, !items.isEmpty else { return false }
    guard let idx = items.firstIndex(where: { id($0) == currentItemId }) else { return false }
    let threshold = max(0, items.count - Self.catalogPrefetchItemsFromEnd)
    return idx >= threshold
  }

  func loadMoreIfNeeded(currentItemId: String?) async {
    guard mainTab == .library, mediaCatalogKind == .audiobooks,
      booksBrowseSection == .books, libraryCatalogQuickFilter != .downloaded,
      !offlineHomeUIActive
    else {
      return
    }
    // Läuft bereits ein Katalog-Fetch (Reset ODER Pagination), nicht erneut anstoßen: Beim
    // schnellen Scrollen feuert `.task(id: book.id)` für mehrere Zeilen nahe dem Ende quasi
    // gleichzeitig — ohne diesen Guard fragen mehrere Aufrufe dieselbe `libraryPage` an, bevor
    // der erste Fetch sie fortschreibt (Server-Seite wird dann mehrfach nachgeladen, spätere
    // Seiten werden dabei übersprungen — „scrollt nicht bis zum Ende, wiederholt eine Seite").
    // Der Check hier läuft synchron vor dem `await` unten, also ohne Suspension-Punkt dazwischen
    // — keine zwei Tasks können sich die Prüfung teilen.
    guard !isLoadingLibrary else { return }
    guard shouldPrefetchNextCatalogPage(currentItemId: currentItemId, in: books, id: \.id),
      books.count < libraryTotal
    else { return }
    await reloadLibrary(reset: false)
  }

  /// Cover für die nächsten paar noch nicht sichtbaren Bücher im Hintergrund vorladen (Memory/Disk/Netzwerk,
  /// kein UI-Update) — vermeidet Cover-Pop-in beim Weiterscrollen, analog zum Server-Pagination-Prefetch oben.
  private static let coverPrefetchLookahead = 6
  private var coverPrefetchInFlightKeys: Set<String> = []

  func prefetchUpcomingBookCovers(currentItemId: String?) {
    guard let currentItemId, let idx = books.firstIndex(where: { $0.id == currentItemId }) else { return }
    let upperBound = min(books.count, idx + 1 + Self.coverPrefetchLookahead)
    guard idx + 1 < upperBound else { return }
    let account = coverImageCacheAccountDirectory()
    let authToken = token
    for book in books[(idx + 1)..<upperBound] {
      guard let url = coverURL(for: book.id) else { continue }
      let key = CoverImageCache.cacheKey(
        scopeId: book.id, revision: coverImageCacheRevision(forItemUpdatedAt: book.updatedAt))
      guard CoverImageCache.memoryImage(itemId: key) == nil, !coverPrefetchInFlightKeys.contains(key) else {
        continue
      }
      coverPrefetchInFlightKeys.insert(key)
      Task.detached(priority: .utility) { [weak self] in
        defer { Task { @MainActor [weak self] in self?.coverPrefetchInFlightKeys.remove(key) } }
        if let account, let data = CoverImageCache.loadFromDisk(account: account, itemId: key),
          let ui = UIImage(data: data)
        {
          CoverImageCache.storeMemory(itemId: key, image: ui)
          return
        }
        var req = URLRequest(url: url)
        if !authToken.isEmpty {
          req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
          let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          let ui = UIImage(data: data)
        else { return }
        if let account {
          try? CoverImageCache.saveToDisk(account: account, itemId: key, data: data)
        }
        CoverImageCache.storeMemory(itemId: key, image: ui)
      }
    }
  }

  func loadMorePodcastsIfNeeded(currentItemId: String?) async {
    guard mainTab == .library, mediaCatalogKind == .podcasts, !offlineHomeUIActive else { return }
    guard podcastSelectedShowId == nil else { return }
    guard podcastEpisodesPagingFromRecentAPI else { return }
    // Gleicher Race wie bei `loadMoreIfNeeded` (Bücher): synchroner Guard, bevor mehrere
    // gleichzeitig feuernde `.task(id:)` dieselbe `podcastLibraryPage` mehrfach anfragen.
    guard !isLoadingPodcasts else { return }
    guard
      shouldPrefetchNextCatalogPage(currentItemId: currentItemId, in: podcastEpisodes, id: \.id),
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

  /// Pull-to-Refresh: Start-Tab (Regale / Stats / Offline-Reconnect).
  func refreshStartTabPullToRefresh() async {
    if ABSStartShelfLocalization.isHomeBrowseStatsCategory(homeBrowseCategory) {
      await performPullToRefresh { [self] in
        await loadListeningStats()
      }
      return
    }
    await performPullToRefresh { [self] in
      await refreshProgressFromServer()
      await loadStartDashboard(skipAuthorizeRefresh: true, force: true, forPullToRefresh: true)
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
    browseGenres = []
    browseGenresFetched = []
    browseTags = []
    browseTagsFetched = []
    browseTagsLoading = false
    browseCollectionBooksById = [:]
    browseNarratorCoverItemIdByNarratorName = [:]
    browseNarratorsFetched = []
    browseCollectionsFetched = []
    browseAuthorsLoading = false
    browseNarratorsLoading = false
    browseSeriesLoading = false
    browseCollectionsLoading = false
    browseGenresLoading = false
    browseAuthorsNextPage = 0
    browseAuthorsTotal = 0
    browseSeriesNextPage = 0
    browseSeriesTotal = 0
    browseCollectionsTotal = 0
    browseEbooks = []
    browseEbooksSupplementary = []
    browseEbooksLoading = false
    browseEbooksTotal = 0
    browseEbooksNextPage = 0
    browseEbooksSessionFetchDone = false
  }

  // MARK: - Offline: Browse-Listen aus Downloads ableiten

  /// Genres/Tags/Autoren/Narratoren stehen nicht mit Buch-IDs in SwiftData (`LocalGenreStat` etc. sind reine
  /// Server-Statistiken) — offline direkt aus den Metadaten der heruntergeladenen Titel aggregieren.
  private func applyOfflineBrowseGenres() {
    var counts: [String: Int] = [:]
    for book in downloadedAudiobooksWithFullMetadata() {
      for genre in book.media.metadata.genres ?? [] {
        let name = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { continue }
        counts[name, default: 0] += 1
      }
    }
    browseGenresFetched = counts.map { BooksBrowseGenreListItem(name: $0.key, numBooks: $0.value) }
    browseGenres = sortedBrowseGenres(browseGenresFetched)
  }

  private func applyOfflineBrowseTags() {
    var counts: [String: Int] = [:]
    for book in downloadedAudiobooksWithFullMetadata() {
      for tag in book.media.tags ?? [] {
        let name = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { continue }
        counts[name, default: 0] += 1
      }
    }
    browseTagsFetched = counts.map { BooksBrowseTagListItem(name: $0.key, numBooks: $0.value) }
    browseTags = sortedBrowseTags(browseTagsFetched)
  }

  private func applyOfflineBrowseAuthors() {
    var byKey: [String: (name: String, count: Int)] = [:]
    for book in downloadedAudiobooksWithFullMetadata() {
      for author in book.media.metadata.authors ?? [] {
        let name = author.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { continue }
        let id = author.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = id.isEmpty ? "name:\(name.lowercased())" : id
        var entry = byKey[key] ?? (name, 0)
        entry.count += 1
        byKey[key] = entry
      }
    }
    let items = byKey.map { key, value in
      ABSLibraryAuthorListItem(id: key, name: value.name, numBooks: value.count, imagePath: nil)
    }
    browseAuthors = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    browseAuthorsTotal = browseAuthors.count
  }

  private func applyOfflineBrowseNarrators() {
    var counts: [String: Int] = [:]
    for book in downloadedAudiobooksWithFullMetadata() {
      for narrator in book.media.metadata.narrators ?? [] {
        let name = narrator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { continue }
        counts[name, default: 0] += 1
      }
    }
    browseNarratorsFetched = counts.map { ABSLibraryNarratorListItem(id: $0.key, name: $0.key, numBooks: $0.value) }
    browseNarrators = sortedBrowseNarrators(browseNarratorsFetched)
    browseNarratorCoverItemIdByNarratorName = [:]
  }

  /// Serien/Collections liegen mit `bookIds` in SwiftData vor (`LocalSeries`/`LocalCollection`) — offline
  /// den vollen lokalen Cache laden und auf Downloads einschränken statt neu zu aggregieren.
  private func applyOfflineBrowseSeries() {
    _ = restoreBrowseSeriesFromLocalStore()
    browseSeries = browseSeries.compactMap { series -> ABSLibrarySeriesListItem? in
      let books = (series.books ?? []).filter { downloadedItemIds.contains($0.id) }
      guard !books.isEmpty else { return nil }
      return ABSLibrarySeriesListItem(id: series.id, name: series.name, books: books)
    }
    browseSeriesTotal = browseSeries.count
    browseSeriesNextPage = 1
  }

  private func applyOfflineBrowseCollections() {
    _ = restoreBrowseCollectionsFromLocalStore()
    var filteredDict: [String: [ABSBook]] = [:]
    browseCollectionsFetched = browseCollectionsFetched.compactMap { item -> ABSLibraryCollectionListItem? in
      let books = (item.books ?? []).filter { downloadedItemIds.contains($0.id) }
      guard !books.isEmpty else { return nil }
      filteredDict[item.id] = books
      return ABSLibraryCollectionListItem(
        id: item.id, name: item.name, description: item.description, books: books,
        createdAt: item.createdAt, lastUpdate: item.lastUpdate)
    }
    browseCollections = sortedBrowseCollections(browseCollectionsFetched)
    browseCollectionsTotal = browseCollections.count
    browseCollectionBooksById = filteredDict
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
    if section == .search {
      // Suche ist jetzt ein eigener Tab — dorthin navigieren statt Strip-Sektion.
      mainTab = .search
      return
    }
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
    case allCatalogs
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
      case .allCatalogs:
        await reloadLibrary(reset: true)
        await loadBrowseEbooks(force: true)
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
    case .books, .search: break
    case .ebooks, .ebooksSupplementary: await loadBrowseEbooks(force: false)
    case .author: await loadBrowseAuthors(force: false)
    case .narrators: await loadBrowseNarrators(force: false)
    case .series: await loadBrowseSeries(force: false)
    case .collections: await loadBrowseCollections(force: false)
    case .genres: await loadBrowseGenres(force: false)
    case .tags: await loadBrowseTags(force: false)
    }
  }

  private func refreshBooksBrowseSectionLists() async {
    switch booksBrowseSection {
    case .books: break
    case .ebooks, .ebooksSupplementary: await loadBrowseEbooks(force: true)
    case .search:
      await refreshBooksSearchResults()
    case .author: await loadBrowseAuthors(force: true)
    case .narrators: await loadBrowseNarrators(force: true)
    case .series: await loadBrowseSeries(force: true)
    case .collections: await loadBrowseCollections(force: true)
    case .genres: await loadBrowseGenres(force: true)
    case .tags: await loadBrowseTags(force: true)
    }
  }

  private func browseSeriesAPIDescending() -> Bool {
    browseSeriesSortField == .random ? false : browseSeriesSortDescending
  }

  /// `nil`/`false`, wenn die angefragte Sortierung von der zuletzt gecachten abweicht — wie zuvor ein
  /// Slug-Cache-Miss (nur die exakt zuletzt geladene Sort-Kombination bleibt offline nutzbar).
  @discardableResult
  private func restoreBrowseAuthorsFromLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext(), let lib = selectedBooksLibrary else { return false }
    let libId = lib.id
    let sortField = browseAuthorsSortField.apiSortParameter
    let descending = browseAuthorsSortDescending
    var stateDescriptor = FetchDescriptor<LocalAuthorListState>(
      predicate: #Predicate { $0.libraryId == libId })
    stateDescriptor.fetchLimit = 1
    guard let state = (try? context.fetch(stateDescriptor))?.first,
      state.sortField == sortField, state.descending == descending
    else { return false }
    let rowsDescriptor = FetchDescriptor<LocalAuthor>(
      predicate: #Predicate { $0.libraryId == libId }, sortBy: [SortDescriptor(\.sortRank)])
    let rows = (try? context.fetch(rowsDescriptor)) ?? []
    guard !rows.isEmpty else { return false }
    browseAuthors = rows.map { $0.toItem() }
    browseAuthorsTotal = state.total
    browseAuthorsNextPage = (rows.count + 49) / 50
    return true
  }

  @discardableResult
  private func restoreBrowseSeriesFromLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext(), let lib = selectedBooksLibrary else { return false }
    let descending = browseSeriesAPIDescending()
    let sort = browseSeriesSortField.apiSortParameter
    guard
      let m = LocalLibraryQueries.series(
        context: context, libraryId: lib.id, sortField: sort, descending: descending)
    else { return false }
    browseSeries = m.items
    browseSeriesTotal = m.total
    browseSeriesNextPage = m.nextPage
    return true
  }

  @discardableResult
  private func restoreBrowseCollectionsFromLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext(), let lib = selectedBooksLibrary else { return false }
    guard let pair = LocalLibraryQueries.collections(context: context, libraryId: lib.id) else { return false }
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
  private func restoreBrowseNarratorsFromLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext(), let lib = selectedBooksLibrary else { return false }
    let libId = lib.id
    let rows =
      (try? context.fetch(FetchDescriptor<LocalNarrator>(predicate: #Predicate { $0.libraryId == libId }))) ?? []
    guard !rows.isEmpty else { return false }
    var coverMap: [String: String] = [:]
    for row in rows {
      if let coverItemId = row.coverItemId { coverMap[row.name] = coverItemId }
    }
    browseNarratorsFetched = rows.map { $0.toItem() }
    browseNarrators = sortedBrowseNarrators(browseNarratorsFetched)
    browseNarratorCoverItemIdByNarratorName = coverMap
    return true
  }

  private func loadBrowseAuthors(force: Bool) async {
    if offlineHomeUIActive {
      if !force, !browseAuthors.isEmpty { return }
      applyOfflineBrowseAuthors()
      return
    }
    guard client != nil, selectedBooksLibrary != nil else { return }
    if browseAuthorsLoading { return }
    if !force, !browseAuthors.isEmpty { return }
    if browseAuthors.isEmpty {
      _ = restoreBrowseAuthorsFromLocalStore()
    }
    if !force, !browseAuthors.isEmpty { return }
    if !isNetworkReachable {
      _ = restoreBrowseAuthorsFromLocalStore()
      return
    }
    await loadBrowseAuthorsPage(reset: true)
  }

  private func loadBrowseAuthorsPage(reset: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if !isNetworkReachable {
      _ = restoreBrowseAuthorsFromLocalStore()
      return
    }
    if browseAuthorsLoading { return }
    if reset {
      browseAuthorsNextPage = 0
      if browseAuthors.isEmpty {
        _ = restoreBrowseAuthorsFromLocalStore()
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
      let (items, total, _) = try await c.libraryAuthorsPage(
        libraryId: lib.id,
        page: page,
        limit: 50,
        sort: browseAuthorsSortField.apiSortParameter,
        descending: descending
      )
      if let store = currentLocalLibraryStore() {
        if reset, page == 0 {
          try? await store.replaceAuthorsFirstPage(
            libraryId: lib.id, sortField: browseAuthorsSortField.apiSortParameter, descending: descending,
            total: total, items: items)
        } else {
          try? await store.appendAuthorsPage(libraryId: lib.id, total: total, items: items)
        }
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
      publishErrorUnlessBenignCancellation(error)
    }
  }

  private func loadBrowseNarrators(force: Bool) async {
    if offlineHomeUIActive {
      if !force, !browseNarrators.isEmpty { return }
      applyOfflineBrowseNarrators()
      return
    }
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if browseNarratorsLoading { return }
    if !force, !browseNarrators.isEmpty { return }
    if browseNarrators.isEmpty {
      _ = restoreBrowseNarratorsFromLocalStore()
    }
    if !force, !browseNarrators.isEmpty { return }
    if !isNetworkReachable {
      _ = restoreBrowseNarratorsFromLocalStore()
      return
    }
    browseNarratorsLoading = true
    defer { browseNarratorsLoading = false }
    do {
      let (items, _) = try await c.libraryNarrators(libraryId: lib.id)
      browseNarratorsFetched = items
      browseNarrators = sortedBrowseNarrators(items)
      browseNarratorCoverItemIdByNarratorName = [:]
      if let store = currentLocalLibraryStore() {
        try? await store.replaceNarrators(libraryId: lib.id, items: items)
      }
      await fillBrowseNarratorCoverItemIds()
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
  }

  func resortBrowseNarratorsDisplay() {
    browseNarrators = sortedBrowseNarrators(browseNarratorsFetched)
  }

  func resortBrowseCollectionsDisplay() {
    browseCollections = sortedBrowseCollections(browseCollectionsFetched)
  }

  func resortBrowseGenresDisplay() {
    browseGenres = sortedBrowseGenres(browseGenresFetched)
  }

  func resortBrowseTagsDisplay() {
    browseTags = sortedBrowseTags(browseTagsFetched)
  }

  private func sortedBrowseGenres(_ rows: [BooksBrowseGenreListItem]) -> [BooksBrowseGenreListItem] {
    let desc = browseGenresSortDescending
    switch browseGenresSortField {
    case .name:
      return rows.sorted {
        desc
          ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
          : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
    case .bookCount:
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

  private func sortedBrowseTags(_ rows: [BooksBrowseTagListItem]) -> [BooksBrowseTagListItem] {
    let desc = browseTagsSortDescending
    switch browseTagsSortField {
    case .name:
      return rows.sorted {
        desc
          ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
          : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
    case .bookCount:
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
    if let store = currentLocalLibraryStore(), let lib = selectedBooksLibrary, !map.isEmpty {
      try? await store.updateNarratorCoverMap(libraryId: lib.id, coverItemIdByName: map)
    }
  }

  private func loadBrowseSeries(force: Bool) async {
    if offlineHomeUIActive {
      if !force, !browseSeries.isEmpty { return }
      applyOfflineBrowseSeries()
      return
    }
    guard client != nil, selectedBooksLibrary != nil else { return }
    if browseSeriesLoading { return }
    if !force, !browseSeries.isEmpty { return }
    if browseSeries.isEmpty {
      _ = restoreBrowseSeriesFromLocalStore()
    }
    if !force, !browseSeries.isEmpty { return }
    if !isNetworkReachable {
      _ = restoreBrowseSeriesFromLocalStore()
      return
    }
    await loadBrowseSeriesPage(reset: true)
  }

  private func loadBrowseSeriesPage(reset: Bool) async {
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if !isNetworkReachable {
      _ = restoreBrowseSeriesFromLocalStore()
      return
    }
    if browseSeriesLoading { return }
    if reset {
      browseSeriesNextPage = 0
      if browseSeries.isEmpty {
        _ = restoreBrowseSeriesFromLocalStore()
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
      let (items, total, _) = try await c.librarySeriesPage(
        libraryId: lib.id,
        page: page,
        limit: 40,
        sort: browseSeriesSortField.apiSortParameter,
        descending: descending
      )
      if let store = currentLocalLibraryStore() {
        if reset, page == 0 {
          try? await store.replaceSeriesFirstPage(
            libraryId: lib.id, sortField: browseSeriesSortField.apiSortParameter, descending: descending,
            total: total, items: items)
        } else {
          try? await store.appendSeriesPage(libraryId: lib.id, total: total, items: items)
        }
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
      publishErrorUnlessBenignCancellation(error)
    }
  }

  private func loadBrowseCollections(force: Bool) async {
    if offlineHomeUIActive {
      if !force, !browseCollections.isEmpty { return }
      applyOfflineBrowseCollections()
      return
    }
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if browseCollectionsLoading { return }
    if !force, !browseCollections.isEmpty { return }
    if browseCollections.isEmpty {
      _ = restoreBrowseCollectionsFromLocalStore()
    }
    if !force, !browseCollections.isEmpty { return }
    if !isNetworkReachable {
      _ = restoreBrowseCollectionsFromLocalStore()
      return
    }
    browseCollectionsLoading = true
    defer { browseCollectionsLoading = false }
    do {
      let (items, total, _) = try await c.libraryCollectionsAll(libraryId: lib.id, minified: true)
      if let store = currentLocalLibraryStore() {
        try? await store.replaceCollections(libraryId: lib.id, total: total, items: items)
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
      publishErrorUnlessBenignCancellation(error)
    }
  }

  /// Mindestens ein Genre mit Server-Zähler (`/stats`), nicht nur Namen aus altem filterdata-Cache.
  private var browseGenresHaveServerCounts: Bool {
    browseGenres.contains { $0.numBooks != nil }
  }

  private func loadBrowseGenres(force: Bool) async {
    if offlineHomeUIActive {
      if !force, !browseGenres.isEmpty { return }
      applyOfflineBrowseGenres()
      return
    }
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if browseGenresLoading { return }
    if browseGenres.isEmpty {
      _ = restoreBrowseGenresFromLocalStore()
    }
    if !force, browseGenresHaveServerCounts { return }
    if !isNetworkReachable {
      _ = restoreBrowseGenresFromLocalStore()
      return
    }
    browseGenresLoading = true
    defer { browseGenresLoading = false }
    do {
      let stats = try await c.serverLibraryStats(libraryId: lib.id)
      if let store = currentLocalLibraryStore(), !stats.genresWithCount.isEmpty {
        try? await store.replaceGenreStats(libraryId: lib.id, stats: stats.genresWithCount)
      }
      applyBrowseGenresFromStats(stats.genresWithCount)
    } catch {
      if browseGenres.isEmpty {
        _ = restoreBrowseGenresFromLocalStore()
      }
      if browseGenres.isEmpty {
        publishErrorUnlessBenignCancellation(error)
      }
    }
  }

  @discardableResult
  private func restoreBrowseGenresFromLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext(), let lib = selectedBooksLibrary else { return false }
    let libId = lib.id
    let predicate = #Predicate<LocalGenreStat> { $0.libraryId == libId }
    let cached = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.map { $0.toStat() } ?? []
    if !cached.isEmpty {
      applyBrowseGenresFromStats(cached)
      return browseGenresHaveServerCounts
    }
    return false
  }

  private func applyBrowseGenresFromStats(_ rows: [ABSLibraryGenreStat]) {
    browseGenresFetched =
      rows.compactMap { row -> BooksBrowseGenreListItem? in
        let name = row.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return BooksBrowseGenreListItem(
          name: name,
          numBooks: row.count > 0 ? row.count : nil
        )
      }
    browseGenres = sortedBrowseGenres(browseGenresFetched)
  }

  private var browseTagsHaveServerCounts: Bool {
    browseTags.contains { $0.numBooks != nil }
  }

  private func loadBrowseTags(force: Bool) async {
    if offlineHomeUIActive {
      if !force, !browseTags.isEmpty { return }
      applyOfflineBrowseTags()
      return
    }
    guard let c = client, let lib = selectedBooksLibrary else { return }
    if browseTagsLoading { return }
    if browseTags.isEmpty {
      _ = restoreBrowseTagsFromLocalStore()
    }
    if !force, browseTagsHaveServerCounts { return }
    if !isNetworkReachable {
      _ = restoreBrowseTagsFromLocalStore()
      return
    }
    browseTagsLoading = true
    defer { browseTagsLoading = false }
    do {
      let filterData = try await c.libraryFilterData(libraryId: lib.id)
      let names =
        (filterData.tags ?? [])
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      let unique = Array(Set(names)).sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
      }
      applyBrowseTagsFromNames(unique)
      let stats = await fetchBrowseTagBookCounts(tagNames: unique)
      if let store = currentLocalLibraryStore(), !stats.isEmpty {
        try? await store.replaceTagStats(libraryId: lib.id, stats: stats)
      }
      applyBrowseTagsFromStats(stats)
    } catch {
      if browseTags.isEmpty {
        _ = restoreBrowseTagsFromLocalStore()
      }
      if browseTags.isEmpty {
        publishErrorUnlessBenignCancellation(error)
      }
    }
  }

  @discardableResult
  private func restoreBrowseTagsFromLocalStore() -> Bool {
    guard let context = currentLocalLibraryMainContext(), let lib = selectedBooksLibrary else { return false }
    let libId = lib.id
    let predicate = #Predicate<LocalTagStat> { $0.libraryId == libId }
    let cached = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.map { $0.toStat() } ?? []
    if !cached.isEmpty {
      applyBrowseTagsFromStats(cached)
      return browseTagsHaveServerCounts
    }
    return false
  }

  private func applyBrowseTagsFromNames(_ names: [String]) {
    browseTagsFetched = names.map { BooksBrowseTagListItem(name: $0, numBooks: nil) }
    browseTags = sortedBrowseTags(browseTagsFetched)
  }

  private func applyBrowseTagsFromStats(_ rows: [ABSLibraryTagStat]) {
    browseTagsFetched =
      rows.compactMap { row -> BooksBrowseTagListItem? in
        let name = row.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return BooksBrowseTagListItem(name: name, numBooks: row.count > 0 ? row.count : nil)
      }
    browseTags = sortedBrowseTags(browseTagsFetched)
  }

  /// Pro Tag ein `libraryItems`-Request (limit 1) für `total` — ABS liefert keine Tag-Stats wie bei Genres.
  private func fetchBrowseTagBookCounts(tagNames: [String]) async -> [ABSLibraryTagStat] {
    guard let c = client, let lib = selectedBooksLibrary else { return [] }
    let names = Array(Set(tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
    guard !names.isEmpty else { return [] }
    let cap = 120
    let batch = names.count > cap ? Array(names.prefix(cap)) : names
    let sortKey = catalogSortField.apiSortParameter
    let ascending = catalogSortField == .random ? true : !catalogSortDescending
    let filters = batch.map { name in
      (name, Self.catalogFilterKey(group: "tags", value: name))
    }
    var stats: [ABSLibraryTagStat] = []
    stats.reserveCapacity(batch.count)
    let rows = await fetchBrowseFacetFilterRowsBatched(
      client: c,
      libraryId: lib.id,
      entries: filters,
      sortKey: sortKey,
      ascending: ascending
    ) { name, page in
      ABSLibraryTagStat(tag: name, count: page.total)
    }
    for row in rows {
      stats.append(row.value)
    }
    return stats.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
  }

  private struct BrowseFacetFilterFetchRow<T> {
    let name: String
    let value: T
  }

  /// `libraryItems`-Stichproben in kleinen Batches — entlastet den API-Actor.
  private func fetchBrowseFacetFilterRowsBatched<T>(
    client: ABSAPIClient,
    libraryId: String,
    entries: [(name: String, filter: String)],
    sortKey: String,
    ascending: Bool,
    map: @escaping @Sendable (String, ABSPage<ABSBook>) -> T?
  ) async -> [BrowseFacetFilterFetchRow<T>] {
    guard !entries.isEmpty else { return [] }
    var out: [BrowseFacetFilterFetchRow<T>] = []
    out.reserveCapacity(entries.count)
    let chunkSize = Self.browseFacetNetworkConcurrency
    var start = 0
    while start < entries.count {
      let end = min(start + chunkSize, entries.count)
      let chunk = Array(entries[start..<end])
      await withTaskGroup(of: BrowseFacetFilterFetchRow<T>?.self) { group in
        for entry in chunk {
          group.addTask {
            do {
              let (page, _) = try await client.libraryItems(
                libraryId: libraryId,
                page: 0,
                limit: 1,
                sort: sortKey,
                ascending: ascending,
                minified: true,
                filter: entry.filter
              )
              guard let value = map(entry.name, page) else { return nil }
              return BrowseFacetFilterFetchRow(name: entry.name, value: value)
            } catch {
              return nil
            }
          }
        }
        for await row in group {
          if let row { out.append(row) }
        }
      }
      start = end
    }
    return out
  }

  func loadMoreBrowseAuthorsIfNeeded(currentItemId: String?) async {
    guard booksBrowseSection == .author else { return }
    guard browseAuthorsTotal > 0 else { return }
    guard shouldPrefetchNextCatalogPage(currentItemId: currentItemId, in: browseAuthors, id: \.id) else {
      return
    }
    guard browseAuthors.count < browseAuthorsTotal else { return }
    await loadBrowseAuthorsPage(reset: false)
  }

  func loadMoreBrowseSeriesIfNeeded(currentItemId: String?) async {
    guard booksBrowseSection == .series else { return }
    guard browseSeriesTotal > 0 else { return }
    guard shouldPrefetchNextCatalogPage(currentItemId: currentItemId, in: browseSeries, id: \.id) else {
      return
    }
    guard browseSeries.count < browseSeriesTotal else { return }
    await loadBrowseSeriesPage(reset: false)
  }

  /// Pull-to-Refresh: Podcast-Tab (Sendungsleiste, „New“-Liste oder gewählte Sendung).
  func refreshPodcastsTab() async {
    await performPullToRefresh { [self] in
      if !podcastLibrarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        await refreshPodcastLibrarySearchResults()
        return
      }
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
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return }
    if podcastSelectedShowId != sid {
      applyPodcastShowFilterSelection(sid)
    }
    await refreshProgressFromServer()
    await reloadPodcastShowsCatalog()
    await loadPodcastEpisodesForShowLibraryItem(sid)
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

  func podcastShowTranscriptionLanguage(for showId: String) -> String? {
    let language: String
    if podcastShowTranscriptionLanguageShowId == showId {
      language = podcastShowTranscriptionLanguage
    } else {
      language = podcastShows.first(where: { $0.id == showId })?.media.metadata.language ?? ""
    }
    let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  func savePodcastShowTranscriptionLanguage(showId: String) async {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !sid.isEmpty,
      podcastShowTranscriptionLanguageShowId == sid,
      let c = client,
      isNetworkReachable,
      !podcastShowTranscriptionLanguageSaving
    else { return }
    let language = podcastShowTranscriptionLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
    podcastShowTranscriptionLanguageSaving = true
    defer { podcastShowTranscriptionLanguageSaving = false }
    do {
      var patch = ABSItemMediaMetadataPatch()
      // Ein leerer Wert leert die Server-Metadaten und aktiviert den automatischen Fallback.
      patch.language = language
      try await c.updateItemMedia(itemId: sid, patch: patch, coverURL: nil)
      let updated = try await c.item(id: sid, expanded: true)
      replacePodcastShowInCatalog(updated)
      applyPodcastAutoDownloadSettings(from: updated, showId: sid)
      if player.activeBook?.id == sid, player.activePlaybackEpisodeId != nil {
        player.setTranscriptionLanguageOverride(updated.media.metadata.language)
      }
      errorMessage = nil
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
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
    forceReload: Bool = false,
    applyToTabPreview: Bool = true
  ) async {
    guard podcastCanManageShowsOnServer else { return }
    let sid = podcastLibraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty, let c = client else { return }

    if !forceReload, podcastRssFeedUnavailableByShowId[sid] != nil {
      if applyToTabPreview { applyActivePodcastRssFeedPreview(showId: sid) }
      return
    }

    if !forceReload, let cached = podcastRssFeedCacheByShowId[sid], !cached.isEmpty {
      if applyToTabPreview { applyActivePodcastRssFeedPreview(showId: sid) }
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
        if applyToTabPreview { applyActivePodcastRssFeedPreview(showId: sid) }
        return
      }
      podcastRssFeedUnavailableByShowId.removeValue(forKey: sid)
      let data = try await c.fetchPodcastRssFeed(rssFeedUrl: feedUrl)
      let drafts = try ABSPodcastRssFeedEpisodeDraft.episodesFromFeedApiResponse(data)
      podcastRssFeedCacheByShowId[sid] = drafts
      if forceReload {
        podcastRssDraftCompletedIdsByShowId[sid] = []
      }
      if applyToTabPreview { applyActivePodcastRssFeedPreview(showId: sid) }
      if drafts.isEmpty {
        errorMessage = "No episodes found in the feed."
      } else {
        errorMessage = nil
      }
    } catch {
      publishErrorUnlessBenignCancellation(error)
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
        publishErrorUnlessBenignCancellation(error)
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
      publishErrorUnlessBenignCancellation(error)
    }
  }

  private func applyPodcastAutoDownloadSettings(from item: ABSBook, showId: String) {
    podcastAutoDownloadSettingsShowId = showId
    podcastAutoDownloadEnabled = item.media.autoDownloadEpisodes ?? false
    podcastAutoDownloadInterval = PodcastAutoDownloadInterval.from(cron: item.media.autoDownloadSchedule)
    podcastMaxEpisodesToKeep = item.media.maxEpisodesToKeep ?? 0
    podcastMaxNewEpisodesToDownload = item.media.maxNewEpisodesToDownload ?? 3
    podcastShowTranscriptionLanguageShowId = showId
    podcastShowTranscriptionLanguage = Self.podcastShowLanguageSettingValue(
      from: item.media.metadata.language)
  }

  /// Bestehende ISO-/BCP-47-Werte aus dem Server für die menschenlesbare Settings-Auswahl normalisieren.
  private static func podcastShowLanguageSettingValue(from raw: String?) -> String {
    let language = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    switch language.lowercased() {
    case "de", "de-de": return "German"
    case "en", "en-us", "en-gb": return "English"
    case "fr", "fr-fr": return "French"
    case "es", "es-es": return "Spanish"
    case "it", "it-it": return "Italian"
    case "nl", "nl-nl": return "Dutch"
    default: return language
    }
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
      publishErrorUnlessBenignCancellation(error)
    }
  }

  /// `nil` = kein API-Limit („No limit“ in der UI = 0).
  private func podcastCheckNewDownloadLimit(forShowId sid: String) -> Int? {
    let raw: Int? = {
      if podcastAutoDownloadSettingsShowId == sid {
        return podcastMaxNewEpisodesToDownload
      }
      return podcastShows.first(where: { $0.id == sid })?.media.maxNewEpisodesToDownload
    }()
    guard let raw, raw > 0 else { return nil }
    return raw
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
      publishErrorUnlessBenignCancellation(error)
    }
  }

  /// Eine Feed-Folge auf den Server laden (`download-episodes`).
  func downloadPodcastRssEpisodeDraft(_ draft: ABSPodcastRssFeedEpisodeDraft, podcastLibraryItemId: String) async {
    guard podcastCanManageShowsOnServer else { return }
    guard let c = client else { return }
    let sid = podcastLibraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    if podcastSelectedShowId != sid {
      applyPodcastShowFilterSelection(sid)
    }
    if podcastFilteredEpisodes.isEmpty {
      await loadPodcastEpisodesForShowLibraryItem(sid)
    }
    guard !podcastRssEpisodeDownloadInProgressDraftIds.contains(draft.id) else { return }
    guard !podcastRssDraftDownloadCompletedIds.contains(draft.id) else { return }
    if libraryEpisodeMatchingPodcastRssDraft(draft, showId: sid) != nil { return }

    podcastRssEpisodeDownloadInProgressDraftIds.insert(draft.id)
    defer { podcastRssEpisodeDownloadInProgressDraftIds.remove(draft.id) }
    let draftId = draft.id
    do {
      let obj = try JSONSerialization.jsonObject(with: draft.episodePayloadJSON, options: [.fragmentsAllowed])
      let body = try JSONSerialization.data(withJSONObject: [obj])
      try await c.downloadPodcastEpisodesToLibrary(
        podcastLibraryItemId: sid,
        episodesJsonArray: body
      )
      var done = podcastRssDraftCompletedIdsByShowId[sid] ?? []
      done.insert(draftId)
      podcastRssDraftCompletedIdsByShowId[sid] = done
      podcastRssDraftDownloadCompletedIds = done
      await refreshProgressFromServer()
      await mergeNewPodcastLibraryEpisodesFromExpandedItem(showLibraryItemId: sid)
      errorMessage = nil
      await loadStartDashboard()
    } catch {
      publishErrorUnlessBenignCancellation(error)
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
    let sid = showLibraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return }
    if podcastSelectedShowId != sid {
      applyPodcastShowFilterSelection(sid)
    }

    func attemptMerge() async throws -> Int {
      let full = try await c.item(id: sid, expanded: true)
      guard podcastSelectedShowId == sid else { return 0 }
      guard let eps = full.media.podcastEpisodes, !eps.isEmpty else { return 0 }
      let rows: [ABSPodcastEpisodeListItem] = eps.compactMap {
        ABSPodcastEpisodeListItem.fromDTO(
          $0, fallbackShow: full, libraryId: lib.id, forceLibraryItemId: full.id)
      }
      var seenKeys = Set(podcastFilteredEpisodes.map(\.progressLookupKey))
      var merged = podcastFilteredEpisodes
      var added = 0
      for row in rows where row.libraryItemId == sid {
        let k = row.progressLookupKey
        guard seenKeys.insert(k).inserted else { continue }
        merged.append(row)
        added += 1
      }
      guard added > 0 else { return 0 }
      podcastFilteredEpisodes = Self.sortPodcastEpisodesNewestFirst(
        ABSPodcastEpisodeListItem.dedupeRows(merged))
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

  /// Einheitliche Suche für den Search-Tab: durchsucht Bücher UND Podcasts gleichzeitig mit demselben
  /// Suchtext (dieselbe Suche für alle Szenarien, unabhängig davon, von wo man in den Tab gewechselt ist).
  func scheduleUnifiedSearch() {
    guard mainTab == .search else { return }
    podcastLibrarySearchText = searchText
    scheduleSearch()
    schedulePodcastLibrarySearch()
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

  func clearPodcastSearchResults() {
    podcastSearchBooks = []
    podcastSearchAuthors = []
    podcastSearchNarrators = []
    podcastSearchSeries = []
    podcastSearchTags = []
    podcastSearchGenres = []
  }

  func clearPodcastLibrarySearchResults() {
    podcastLibrarySearchShows = []
    podcastLibrarySearchEpisodes = []
  }

  func schedulePodcastLibrarySearch() {
    guard mainTab == .search, showPodcastsTab, selectedPodcastLibrary != nil else { return }
    podcastLibrarySearchTask?.cancel()
    let q = podcastLibrarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    podcastLibrarySearchTask = Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      await performPodcastLibrarySearch(query: q)
    }
  }

  private func performPodcastLibrarySearch(query: String) async {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.count < 3 {
      clearPodcastLibrarySearchResults()
      return
    }
    guard selectedPodcastLibrary != nil else { return }
    // Lokale DB ist mit dem Server synchronisiert — sofort lokal anzeigen, siehe `performSearch`.
    applyLocalPodcastLibrarySearchResults(query: q)
    if !mayUseServerNetwork || !isNetworkReachable || client == nil {
      return
    }
    guard let c = client, let lib = selectedPodcastLibrary else { return }
    isLoadingPodcasts = true
    defer { isLoadingPodcasts = false }
    do {
      let res = try await c.search(libraryId: lib.id, query: q)
      podcastLibrarySearchShows = res.podcastSearchShowLibraryItems()
      podcastLibrarySearchEpisodes = mergedPodcastLibrarySearchEpisodes(
        server: res.podcastEpisodeMatches, query: q)
    } catch {
      if podcastLibrarySearchShows.isEmpty, podcastLibrarySearchEpisodes.isEmpty {
        publishErrorUnlessBenignCancellation(error)
      }
    }
  }

  private func mergedPodcastLibrarySearchEpisodes(
    server: [ABSPodcastEpisodeListItem],
    query: String
  ) -> [ABSPodcastEpisodeListItem] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard q.count >= 2 else { return server }
    return ABSPodcastEpisodeListItem.dedupeRows(server + localPodcastEpisodesMatchingSearch(q))
      .sorted { $0.episodeTitle.localizedStandardCompare($1.episodeTitle) == .orderedAscending }
  }

  private func localPodcastEpisodesMatchingSearch(_ query: String) -> [ABSPodcastEpisodeListItem] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard q.count >= 2 else { return [] }
    var byKey: [String: ABSPodcastEpisodeListItem] = [:]
    func consider(_ list: [ABSPodcastEpisodeListItem]) {
      for ep in list where (ep.episodeTitle + " " + ep.showTitle).localizedCaseInsensitiveContains(q) {
        byKey[ep.canonicalDedupeKey] = ep
      }
    }
    consider(podcastEpisodes)
    for cached in podcastFilteredEpisodesByShowId.values {
      consider(cached)
    }
    return Array(byKey.values)
  }

  /// Sofort-Suche in der lokalen DB (Podcast-Bibliothek) — läuft IMMER zuerst, siehe `applyLocalSearchResults`.
  private func applyLocalPodcastLibrarySearchResults(query: String) {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.count < 3 {
      clearPodcastLibrarySearchResults()
      return
    }
    var byId: [String: ABSBook] = [:]
    if let libId = selectedPodcastLibrary?.id {
      for show in searchLocalPodcastShows(libraryId: libId, query: q) {
        byId[show.id] = show
      }
    }
    for show in podcastShows where bookMatchesSearchQuery(show, query: q) {
      if let existing = byId[show.id] {
        byId[show.id] = show.preferringRicherListMetadata(than: existing)
      } else {
        byId[show.id] = show
      }
    }
    podcastLibrarySearchShows = Array(byId.values)
      .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    podcastLibrarySearchEpisodes = mergedPodcastLibrarySearchEpisodes(server: [], query: q)
  }

  func refreshPodcastLibrarySearchResults() async {
    await performPullToRefresh { [self] in
      podcastLibrarySearchTask?.cancel()
      let q = podcastLibrarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
      await performPodcastLibrarySearch(query: q)
    }
  }

  /// Hörbücher + reine eBooks aus Speicher/Caches (Autor-Detail offline).
  private func mergedLocalAuthorDetailBooks() -> [ABSBook] {
    var byId: [String: ABSBook] = [:]
    func add(_ list: [ABSBook]) {
      for book in list where book.isUsableAuthorDetailRow {
        if let existing = byId[book.id] {
          byId[book.id] = book.preferringRicherListMetadata(than: existing)
        } else {
          byId[book.id] = book
        }
      }
    }
    add(mergedLocalCatalogBooks())
    return Array(byId.values)
  }

  /// Alle Hörbuch-Stubs aus Speicher + LocalStore (wie Library-Katalog beim Start).
  private func mergedLocalCatalogBooks() -> [ABSBook] {
    var byId: [String: ABSBook] = [:]
    func add(_ list: [ABSBook]) {
      for book in list where book.isUsableLibraryCatalogRow {
        if let existing = byId[book.id] {
          byId[book.id] = book.preferringRicherListMetadata(than: existing)
        } else {
          byId[book.id] = book
        }
      }
    }
    func addEbookBrowse(_ list: [ABSBook]) {
      for book in list where book.isUsableEbookListRow || book.isUsableLibraryCatalogRow {
        if let existing = byId[book.id] {
          byId[book.id] = book.preferringRicherListMetadata(than: existing)
        } else {
          byId[book.id] = book
        }
      }
    }
    add(books)
    add(startBooks)
    add(searchBooks)
    add(downloadedShelfBooks)
    addEbookBrowse(browseEbooks)
    addEbookBrowse(browseEbooksSupplementary)
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

  /// Alle Podcast-Folgen-Stubs aus jedem In-Memory-Array — Pendant zu `mergedLocalCatalogBooks()`.
  /// Dedupliziert nach `canonicalDedupeKey`, reichere Zeile gewinnt (`preferringRicherMetadata`), damit
  /// eine Folge unabhängig davon auffindbar ist, über welchen Pfad (Tab-Besuch, Show-Filter, Suche) sie
  /// zuletzt in den Speicher kam.
  private func mergedLocalPodcastEpisodes() -> [ABSPodcastEpisodeListItem] {
    var byKey: [String: ABSPodcastEpisodeListItem] = [:]
    func add(_ list: [ABSPodcastEpisodeListItem]) {
      for episode in list {
        let key = episode.canonicalDedupeKey
        if let existing = byKey[key] {
          byKey[key] = episode.preferringRicherMetadata(than: existing)
        } else {
          byKey[key] = episode
        }
      }
    }
    add(podcastEpisodes)
    add(podcastFilteredEpisodes)
    add(podcastLibrarySearchEpisodes)
    for list in podcastFilteredEpisodesByShowId.values {
      add(list)
    }
    return Array(byKey.values)
  }

  /// Browse-Listen und Katalog aus der lokalen SwiftData-Kopie in `@Published`, falls noch leer.
  private func ensureLocalCatalogCachesInMemory() {
    guard selectedBooksLibrary != nil else { return }
    if books.isEmpty {
      restoreBooksCatalogAndHomeFromLocalStore()
    }
    if browseAuthors.isEmpty { _ = restoreBrowseAuthorsFromLocalStore() }
    if browseSeries.isEmpty { _ = restoreBrowseSeriesFromLocalStore() }
    if browseNarrators.isEmpty { _ = restoreBrowseNarratorsFromLocalStore() }
    if browseCollections.isEmpty { _ = restoreBrowseCollectionsFromLocalStore() }
    ensureLocalProgressLoaded()
  }

  /// Sucht Bücher direkt in der lokalen SwiftData-DB einer Bibliothek (Titel/Autor/Serie) — vollständiger
  /// als die aktuell im Speicher gehaltenen Katalog-Arrays (`mergedLocalCatalogBooks()`), da unabhängig
  /// davon, welche Screens der Nutzer bereits besucht hat. Gleiche Quelle wie der Cache-first-Katalog.
  private func searchLocalBooks(libraryId: String, query: String, limit: Int = 60) -> [ABSBook] {
    guard let context = currentLocalLibraryMainContext() else { return [] }
    let all = LocalLibraryQueries.allBooks(
      context: context, libraryId: libraryId, sortField: .title, descending: false)
    return Array(all.filter { bookMatchesSearchQuery($0, query: query) }.prefix(limit))
  }

  /// Podcast-Sendungen leben in derselben `LocalBook`-Tabelle wie Bücher (nur mit der Podcast-`libraryId`).
  private func searchLocalPodcastShows(libraryId: String, query: String, limit: Int = 40) -> [ABSBook] {
    searchLocalBooks(libraryId: libraryId, query: query, limit: limit)
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

  private func bookMatchesGenre(_ book: ABSBook, genreName: String) -> Bool {
    let want = genreName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !want.isEmpty else { return false }
    return (book.media.metadata.genres ?? []).contains {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(want)
        == .orderedSame
    }
  }

  private func bookMatchesTag(_ book: ABSBook, tagName: String) -> Bool {
    let want = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !want.isEmpty else { return false }
    return (book.media.tags ?? []).contains {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(want)
        == .orderedSame
    }
  }

  private func booksInLocalSeries(seriesId: String, displayName: String, libraryId: String? = nil) -> [ABSBook] {
    if let cached = browseSeries.first(where: { $0.id == seriesId })?.books {
      let filtered = cached.filter {
        isUsableEntityDetailCatalogRow($0) && bookMatchesEntityDetailLibrary($0, libraryId: libraryId)
      }
      if !filtered.isEmpty { return filtered }
    }
    let sid = seriesId.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return mergedLocalBooksForEntityDetail(libraryId: libraryId).filter { book in
      guard let series = book.media.metadata.series else { return false }
      return series.contains { item in
        if !sid.isEmpty, item.id == sid { return true }
        if !name.isEmpty, item.name.localizedCaseInsensitiveContains(name) { return true }
        return false
      }
    }
  }

  /// Sofort-Suche in der lokalen DB — läuft IMMER zuerst (auch online), damit die Ergebnisse ohne
  /// Netzwerk-Wartezeit erscheinen; der Server-Abruf in `performSearch` verfeinert danach nur noch.
  private func applyLocalSearchResults(query: String) {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.count < 3 {
      clearSearchResults()
      return
    }
    ensureLocalCatalogCachesInMemory()
    var byId: [String: ABSBook] = [:]
    if let libId = selectedBooksLibrary?.id {
      for book in searchLocalBooks(libraryId: libId, query: q) {
        byId[book.id] = book
      }
    }
    for book in mergedLocalCatalogBooks() where bookMatchesSearchQuery(book, query: q) {
      if let existing = byId[book.id] {
        byId[book.id] = book.preferringRicherListMetadata(than: existing)
      } else {
        byId[book.id] = book
      }
    }
    searchBooks = Array(byId.values)
      .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
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

  /// Offline: nur heruntergeladene Titel innerhalb einer Entity-Detailansicht anzeigen.
  private func offlineFilteredIfNeeded(_ books: [ABSBook]) -> [ABSBook] {
    guard offlineHomeUIActive else { return books }
    return books.filter { downloadedItemIds.contains($0.id) }
  }

  private func applyEntityDetailFromLocalCache(for nav: BooksEntityDetailNav) {
    ensureLocalCatalogCachesInMemory()
    entityDetailDescription = nil
    entityDetailAuthorSeriesSections = []
    entityDetailAuthorStandaloneBooks = []
    entityDetailUsesLibraryItemFilter = false
    switch nav.kind {
    case .author:
      let rows = offlineFilteredIfNeeded(
        mergedLocalAuthorDetailBooks().filter {
          bookMatchesAuthor($0, authorId: nav.entityId, displayName: nav.title)
        })
      entityDetailBooks = entityDetailSortBooksBySeriesOrder(rows)
      entityDetailTotal = rows.count
    case .series:
      let rows = entityDetailSortBooksBySeriesOrder(
        offlineFilteredIfNeeded(
          booksInLocalSeries(
            seriesId: nav.entityId, displayName: nav.title, libraryId: nav.libraryId)),
        seriesId: nav.entityId)
      entityDetailBooks = rows
      entityDetailTotal = rows.count
    case .narrator:
      let rows = offlineFilteredIfNeeded(
        mergedLocalCatalogBooks().filter { bookMatchesNarrator($0, narratorName: nav.entityId) })
      entityDetailBooks = rows
      entityDetailTotal = rows.count
    case .collection:
      applyCollectionDetailBooks(collectionId: nav.entityId)
      entityDetailDescription = collectionDescription(for: nav.entityId)
    case .genre:
      let rows = offlineFilteredIfNeeded(
        mergedLocalCatalogBooks().filter { bookMatchesGenre($0, genreName: nav.entityId) })
      entityDetailBooks = rows
      entityDetailTotal = rows.count
    case .tag:
      let rows = offlineFilteredIfNeeded(
        mergedLocalCatalogBooks().filter { bookMatchesTag($0, tagName: nav.entityId) })
      entityDetailBooks = rows
      entityDetailTotal = rows.count
    }
  }

  private func collectionDescription(for collectionId: String) -> String? {
    browseCollections.first(where: { $0.id == collectionId })?.description
  }

  private func applyCollectionDetailBooks(collectionId: String) {
    let rows = offlineFilteredIfNeeded(
      (browseCollectionBooksById[collectionId] ?? []).filter(\.isUsableLibraryCatalogRow))
    entityDetailBooks = rows
    entityDetailTotal = rows.count
  }

  private func applyCollectionDetailFromFetched(_ detail: ABSLibraryCollectionListItem) {
    let books = detail.books ?? []
    browseCollectionBooksById[detail.id] = books
    let rows = books.filter(\.isUsableLibraryCatalogRow)
    entityDetailBooks = rows
    entityDetailTotal = rows.count
  }

  private func performSearch(query: String) async {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.count < 3 {
      clearSearchResults()
      return
    }
    guard selectedBooksLibrary != nil else { return }
    // Lokale DB ist mit dem Server synchronisiert — sofort lokal anzeigen, kein Warten auf den
    // Netzwerk-Roundtrip. Der Server-Abruf unten (wenn online) verfeinert/ergänzt danach nur noch
    // (vollständige Bibliotheksabdeckung + Autoren/Serien/Tags/Genres-Abschnitte).
    applyLocalSearchResults(query: q)
    if !mayUseServerNetwork || !isNetworkReachable || client == nil {
      return
    }
    guard let c = client, let lib = selectedBooksLibrary else { return }
    isLoadingLibrary = true
    defer { isLoadingLibrary = false }
    do {
      let res = try await c.search(libraryId: lib.id, query: q)
      searchBooks = res.bookSearchLibraryItems()
      searchAuthors = res.authors
      searchNarrators = res.narrators
      searchSeries = res.series
      searchTags = res.tags
      searchGenres = res.genres
      // Cross-Media-Treffer bleiben die lokalen (Server-Suche ist pro Bibliothek/Medientyp getrennt).
    } catch {
      // Lokale Treffer aus `applyLocalSearchResults` oben bleiben stehen — nur bei komplett leeren
      // lokalen Treffern zusätzlich eine Fehlermeldung zeigen.
      if searchBooks.isEmpty, searchAuthors.isEmpty, searchNarrators.isEmpty, searchSeries.isEmpty {
        publishErrorUnlessBenignCancellation(error)
      }
    }
  }

  private func setBooksLibraryFilterSummary(prefix: String, detail: String?) {
    let d = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    activeLibraryFilterSummary = d.isEmpty ? prefix : "\(prefix): \(d)"
  }

  func openAuthorDetail(authorId: String, displayName: String? = nil, numBooks: Int? = nil) {
    let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    presentEntityDetailNav(
      BooksEntityDetailNav(
        kind: .author,
        entityId: authorId,
        title: name.isEmpty ? "Author" : name,
        numBooks: numBooks
      ))
  }

  func openSeriesDetail(seriesId: String, displayName: String? = nil, numBooks: Int? = nil) {
    let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    presentEntityDetailNav(
      BooksEntityDetailNav(
        kind: .series,
        entityId: seriesId,
        title: name.isEmpty ? "Series" : name,
        numBooks: numBooks
      ))
  }

  func openNarratorDetail(narratorName: String, numBooks: Int? = nil) {
    let name = narratorName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    presentEntityDetailNav(
      BooksEntityDetailNav(
        kind: .narrator,
        entityId: name,
        title: name,
        numBooks: numBooks
      ))
  }

  func openCollectionDetail(collectionId: String, displayName: String? = nil, numBooks: Int? = nil) {
    let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    presentEntityDetailNav(
      BooksEntityDetailNav(
        kind: .collection,
        entityId: collectionId,
        title: name.isEmpty ? "Collection" : name,
        numBooks: numBooks
      ))
  }

  func openGenreDetail(genreName: String, numBooks: Int? = nil) {
    let name = genreName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    presentEntityDetailNav(
      BooksEntityDetailNav(
        kind: .genre,
        entityId: name,
        title: name,
        numBooks: numBooks
      ))
  }

  func openTagDetail(tagName: String, numBooks: Int? = nil) {
    let name = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    presentEntityDetailNav(
      BooksEntityDetailNav(
        kind: .tag,
        entityId: name,
        title: name,
        numBooks: numBooks
      ))
  }

  /// Leert gemeinsamen Detail-State synchron — verhindert Flash der vorherigen Entity vor `.task`.
  func entityDetailMatches(_ nav: BooksEntityDetailNav) -> Bool {
    entityDetailNavKey == nav.id
  }

  /// Bibliothek für Entity-Detail — eBooks und Audiobooks teilen dieselbe Server-Bibliothek.
  private func libraryForEntityDetail(for nav: BooksEntityDetailNav) -> ABSLibrary? {
    if let lib = resolvedLibrary(forLibraryId: nav.libraryId) { return lib }
    return selectedBooksLibrary
  }

  private func resolvedLibrary(forLibraryId libraryId: String?) -> ABSLibrary? {
    guard let raw = libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }
    if selectedBooksLibrary?.id == raw { return selectedBooksLibrary }
    return libraries.first { $0.id == raw }
  }

  private func bookMatchesEntityDetailLibrary(_ book: ABSBook, libraryId: String?) -> Bool {
    guard let want = libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !want.isEmpty else {
      return true
    }
    guard let lid = book.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty else {
      return true
    }
    return lid == want
  }

  /// Entity-Detail-Listen: Hörbücher plus eBooks (nicht nur `isUsableLibraryCatalogRow`).
  private func isUsableEntityDetailCatalogRow(_ book: ABSBook) -> Bool {
    book.isUsableAuthorDetailRow
  }

  private func mergedLocalBooksForEntityDetail(libraryId: String?) -> [ABSBook] {
    mergedLocalCatalogBooks().filter { bookMatchesEntityDetailLibrary($0, libraryId: libraryId) }
  }

  func prepareEntityDetail(for nav: BooksEntityDetailNav) {
    entityDetailNavKey = nav.id
    entityDetailPage = 0
    entityDetailBooks = []
    entityDetailTotal = 0
    entityDetailDescription = nil
    entityDetailMetaReady = false
    entityDetailAuthorSeriesSections = []
    entityDetailAuthorStandaloneBooks = []
    entityDetailUsesLibraryItemFilter = false
    entityDetailLoading = true
  }

  /// Entity-Detail nur im aktuellen Tab pushen — Tabs bleiben unabhängig.
  private func presentEntityDetailNav(_ nav: BooksEntityDetailNav) {
    prepareEntityDetail(for: nav)
    switch mainTab {
    case .start:
      homeEntityDetailNav = nav
    case .library:
      mediaCatalogKind = .audiobooks
      libraryEntityDetailNav = nav
    case .settings:
      break
    case .search:
      mediaCatalogKind = .audiobooks
      searchEntityDetailNav = nav
    }
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
    guard libraryForEntityDetail(for: nav) != nil else { return }
    let key = nav.id
    if reset {
      prepareEntityDetail(for: nav)
    }
    guard entityDetailNavKey == key else { return }
    if !mayUseServerNetwork || !isNetworkReachable || client == nil {
      applyEntityDetailFromLocalCache(for: nav)
      entityDetailMetaReady = true
      entityDetailLoading = false
      return
    }
    entityDetailLoading = true
    defer {
      if entityDetailNavKey == key {
        entityDetailLoading = false
        entityDetailMetaReady = true
      }
    }
    guard let c = client, let lib = libraryForEntityDetail(for: nav) else {
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
        entityDetailDescription = nil
        if let cached = browseSeries.first(where: { $0.id == nav.entityId })?.books {
          let rows = cached
            .filter(isUsableEntityDetailCatalogRow)
            .filter { bookMatchesEntityDetailLibrary($0, libraryId: nav.libraryId) }
          if !rows.isEmpty {
            entityDetailBooks = entityDetailSortBooksBySeriesOrder(rows, seriesId: nav.entityId)
            entityDetailTotal = rows.count
            entityDetailUsesLibraryItemFilter = false
          } else {
            entityDetailUsesLibraryItemFilter = true
            try await reloadEntityDetailBooksViaLibraryFilter(for: nav, reset: true, key: key)
          }
        } else {
          entityDetailUsesLibraryItemFilter = true
          try await reloadEntityDetailBooksViaLibraryFilter(for: nav, reset: true, key: key)
        }
      case .narrator:
        entityDetailDescription = nil
        entityDetailUsesLibraryItemFilter = true
        try await reloadEntityDetailBooksViaLibraryFilter(for: nav, reset: true, key: key)
      case .collection:
        entityDetailUsesLibraryItemFilter = false
        if !isNetworkReachable {
          applyCollectionDetailBooks(collectionId: nav.entityId)
          entityDetailDescription = collectionDescription(for: nav.entityId)
        } else {
          do {
            let detail = try await c.collectionDetail(collectionId: nav.entityId)
            guard entityDetailNavKey == key else { return }
            entityDetailDescription = detail.description
            applyCollectionDetailFromFetched(detail)
          } catch {
            if browseCollectionBooksById[nav.entityId] == nil {
              await loadBrowseCollections(force: true)
            }
            guard entityDetailNavKey == key else { return }
            applyCollectionDetailBooks(collectionId: nav.entityId)
            entityDetailDescription = collectionDescription(for: nav.entityId)
          }
        }
      case .genre:
        entityDetailDescription = nil
        entityDetailUsesLibraryItemFilter = true
        try await reloadEntityDetailBooksViaLibraryFilter(for: nav, reset: true, key: key)
      case .tag:
        entityDetailDescription = nil
        entityDetailUsesLibraryItemFilter = true
        try await reloadEntityDetailBooksViaLibraryFilter(for: nav, reset: true, key: key)
      }
    } catch {
      guard entityDetailNavKey == key else { return }
      applyEntityDetailFromLocalCache(for: nav)
      if entityDetailBooks.isEmpty {
        publishErrorUnlessBenignCancellation(error)
      }
    }
  }

  private func applyAuthorDetailBooksLayout(detail: ABSAuthorDetail) {
    let allItems = (detail.libraryItems ?? []).filter(\.isUsableAuthorDetailRow)
    var inSeriesIds = Set<String>()
    var sections: [EntityDetailAuthorSeriesSection] = []
    for series in detail.series ?? [] {
      let books = entityDetailSortBooksBySeriesOrder(
        (series.items ?? []).filter(\.isUsableAuthorDetailRow),
        seriesId: series.id)
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

  private func entityDetailSortBooksBySeriesOrder(
    _ books: [ABSBook], seriesId: String? = nil
  ) -> [ABSBook] {
    books.sorted { lhs, rhs in
      let lk = entityDetailSeriesSortKey(for: lhs, seriesId: seriesId)
      let rk = entityDetailSeriesSortKey(for: rhs, seriesId: seriesId)
      if lk.number != rk.number { return lk.number < rk.number }
      if lk.text != rk.text { return lk.text.localizedStandardCompare(rk.text) == .orderedAscending }
      return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
    }
  }

  private func entityDetailSeriesSortKey(
    for book: ABSBook, seriesId: String? = nil
  ) -> (number: Double, text: String) {
    let allSeries = book.media.metadata.series ?? []
    // Wenn eine seriesId übergeben wurde, die passende Series auswählen (Bücher können
    // in mehreren Serien sein — sonst nimmt .first die falsche Sequence-Nummer).
    let series: ABSSeries?
    if let sid = seriesId {
      series = allSeries.first(where: { $0.id == sid }) ?? allSeries.first
    } else {
      series = allSeries.first
    }
    guard let series else {
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
    guard let c = client, let lib = libraryForEntityDetail(for: nav) else { return }
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
    let rawRows = page.results.filter(isUsableEntityDetailCatalogRow)
    // Bei Series-Detail nach Series-Reihenfolge sortieren (Sequence-Nummer), nicht nach
    // dem allgemeinen Katalog-Sortierfeld — sonst stimmt die Reihenfolge nicht.
    let rows = nav.kind == .series
      ? entityDetailSortBooksBySeriesOrder(rawRows, seriesId: nav.entityId)
      : rawRows
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
    guard shouldPrefetchNextCatalogPage(currentItemId: currentItemId, in: entityDetailBooks, id: \.id) else {
      return
    }
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
      publishErrorUnlessBenignCancellation(error)
    }
  }

  func entityDetailCoverURL(for nav: BooksEntityDetailNav) -> URL? {
    switch nav.kind {
    case .author:
      return authorImageURL(authorId: nav.entityId)
    case .narrator, .genre, .tag, .collection:
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
    podcastLibrarySearchTask?.cancel()
    activeLibraryFilter = nil
    activeLibraryFilterSummary = nil
    searchText = q
    podcastLibrarySearchText = q
    mainTab = .search
    Task { await performSearch(query: q) }
    Task { await performPodcastLibrarySearch(query: q) }
  }

  /// Katalog durchsuchender Sprung: Podcast-Tab, passende Sendung wählen oder Suche nach Show.
  func openPodcastSearchFromText(_ raw: String) {
    let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty, q != "—", showPodcastsTab, selectedPodcastLibrary != nil else { return }
    podcastSearchTask?.cancel()
    podcastSearchText = ""
    navigateToMedia(.podcasts)
    Task { await navigatePodcastsToShowMatchingQuery(q) }
  }

  /// Folgen-Detail → Podcasts-Tab mit Episodenliste dieser Sendung (wie Strip-Auswahl).
  func openPodcastShowCatalog(showId: String) async {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty, showPodcastsTab, selectedPodcastLibrary != nil else { return }
    navigateToMedia(.podcasts)
    podcastCatalogStripSectionId = sid
    await selectPodcastShowFilter(sid)
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
      let shows = res.podcastSearchShowLibraryItemsIncludingEpisodeMatches()
      if let first = shows.first {
        await selectPodcastShowFilter(first.id)
      } else {
        await selectPodcastShowFilter(nil)
      }
    } catch {
      publishErrorUnlessBenignCancellation(error)
      await selectPodcastShowFilter(nil)
    }
  }

  /// Lädt den zuletzt relevanten Fortschritt (`mediaProgress`) in den Player — pausiert (Hörbuch oder Podcast-Folge).
  /// Nutzt Authorize-Fortschritt; Katalog/Home dürfen parallel noch laden.
  func restoreLastPlayedOnLaunch() async {
    let sp = AppLog.launchSignposter.beginInterval("restorePlayback")
    defer { AppLog.launchSignposter.endInterval("restorePlayback", sp) }
    isRestoringLaunchPlayback = true
    defer {
      isRestoringLaunchPlayback = false
      if player.activeBook == nil {
        player.setMiniPlayerPlaceholder(false)
      }
    }
    guard let c = client else {
      return
    }
    guard let progress = launchResumeProgress(), !progress.isFinished else {
      UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
      return
    }
    let libraryItemId = progress.libraryItemId
    if let live = progressByItemId[progress.progressLookupKey], live.isFinished {
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
          transcriptionLanguageOverride: podcastShowTranscriptionLanguage(for: episode.libraryItemId),
          autoPlay: false,
          attemptServerPlaySession: mayUseServerNetwork && isNetworkReachable
        )
      } catch {
        UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
        publishErrorUnlessBenignCancellation(error)
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
    }
  }

  private func cachedBookFallback(id: String) -> ABSBook? {
    let lookupId = normalizedStatsLibraryItemId(id)
    guard !lookupId.isEmpty else { return nil }
    if let book = allInMemoryBooksForIdLookup().first(where: { $0.id == lookupId }) { return book }
    if let book = podcastShows.first(where: { $0.id == lookupId }) { return book }
    if let book = podcastSearchBooks.first(where: { $0.id == lookupId }) { return book }
    if let episode = podcastEpisodes.first(where: { $0.libraryItemId == lookupId }) {
      return episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
    }
    if let book = bookFromLocalStore(libraryItemId: lookupId) { return book }
    return nil
  }

  /// Podcast-Folge aus Stats-Session (Katalog-Treffer oder Stub aus Session-Feldern).
  func podcastEpisodeForStatsSession(_ session: ABSListeningStatsRecentSession) -> ABSPodcastEpisodeListItem? {
    guard session.isPodcastEpisodeSession else { return nil }
    let lid = normalizedStatsLibraryItemId(session.libraryItemId)
    let eid = session.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !lid.isEmpty, !eid.isEmpty else { return nil }

    func find(in list: [ABSPodcastEpisodeListItem]) -> ABSPodcastEpisodeListItem? {
      list.first { $0.libraryItemId == lid && $0.episodeId == eid }
    }
    if let hit = find(in: podcastEpisodes) ?? find(in: podcastFilteredEpisodes) {
      return hit
    }

    let showTitle: String = {
      if let show = podcastShows.first(where: { $0.id == lid }) {
        return show.displayTitle
      }
      if let show = podcastSearchBooks.first(where: { $0.id == lid }) {
        return show.displayTitle
      }
      let auth = session.displayAuthor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return auth.isEmpty ? "—" : auth
    }()
    let rawEpisodeTitle = session.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let episodeTitle = rawEpisodeTitle.isEmpty ? "Episode" : rawEpisodeTitle
    let author = session.displayAuthor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let authorLine = author.isEmpty ? showTitle : author
    return ABSPodcastEpisodeListItem(
      libraryItemId: lid,
      libraryId: selectedPodcastLibrary?.id,
      episodeId: eid,
      episodeTitle: episodeTitle,
      showTitle: showTitle,
      authorLine: authorLine,
      duration: 0,
      publishedAt: session.startedAt > 0 ? session.startedAt : nil
    )
  }

  /// Katalog-Treffer oder Stats-Metadaten-Stub für Anzeige/Navigation aus dem Stats-Tab.
  func bookForStatsNavigation(
    libraryItemId: String,
    metadata: ABSListeningStatsMetadata?
  ) -> ABSBook {
    let id = normalizedStatsLibraryItemId(libraryItemId)
    if !id.isEmpty, let cached = cachedBookFallback(id: id) {
      return cached
    }
    if !id.isEmpty, let metadata {
      return metadata.stubBook(libraryItemId: id)
    }
    let title = metadata?.displayTitle ?? "—"
    let author = metadata?.displayAuthorLine ?? "—"
    return ABSBook(
      id: id.isEmpty ? UUID().uuidString : id,
      libraryId: nil,
      media: ABSBookMedia(
        metadata: ABSBookMediaMetadata(offlineTitle: title, authorLine: author),
        duration: nil,
        numTracks: nil,
        chapters: nil,
        tracks: nil
      ),
      addedAt: nil,
      updatedAt: nil
    )
  }

  func loadBookDetail(id: String) async -> ABSBook? {
    if let root = localDownloadRoot(for: id),
      let manifest = ABSDownloadManifest.load(from: root)
    {
      let fromManifest = ABSBook.fromDownloadManifest(manifest)
      let cachedDetail = cachedBookDetail(id: id)
      if !isNetworkReachable {
        return cachedDetail ?? fromManifest
      }
      guard let c = client else { return cachedDetail ?? fromManifest }
      if let expanded = try? await c.item(id: id, expanded: true) {
        let merged = expanded.mergingLocalDownloadPlayback(fromManifest)
        persistBookDetail(merged)
        return merged
      }
      return cachedDetail ?? fromManifest
    }
    guard let c = client else { return cachedBookDetail(id: id) ?? cachedBookFallback(id: id) }
    do {
      let expanded = try await c.item(id: id, expanded: true)
      persistBookDetail(expanded)
      return expanded
    } catch {
      return cachedBookDetail(id: id) ?? cachedBookFallback(id: id)
    }
  }

  // MARK: - Metadata Match (absorb-style)

  /// Verfügbare Metadaten-Provider (`GET /api/search/providers`).
  func loadMetadataProviders() async throws -> [ABSMetadataProvider] {
    guard let c = client else { throw ABSAPIError.emptyBody }
    let resp = try await c.metadataProviders()
    return resp.books
  }

  /// Online-Suche nach Metadaten-Treffern (`GET /api/search/books`).
  func searchMetadataBooks(title: String, author: String?, provider: String, region: String?) async throws -> [ABSMetadataMatch] {
    guard let c = client else { throw ABSAPIError.emptyBody }
    return try await c.searchBooks(title: title, author: author, provider: provider, region: region)
  }

  /// Wendet ausgewählte Match-Felder an (`PATCH /api/items/:id/media` + optional `POST /api/items/:id/cover`).
  /// Detail-Refresh übernimmt die aufrufende View per Sheet-`onDismiss` — hier kein `loadBookDetail`, um
  /// parallele SwiftData-Schreibvorgänge und doppelte Netzwerk-Loads zu vermeiden.
  @discardableResult
  func applyMetadataMatch(itemId: String, patch: ABSItemMediaMetadataPatch, coverURL: String?) async -> Bool {
    guard let c = client else { return false }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return false
    }
    do {
      try await c.updateItemMedia(itemId: itemId, patch: patch, coverURL: coverURL)
      if let coverURL, !coverURL.isEmpty {
        clearCoverImageCache()
      }
      errorMessage = nil
      return true
    } catch {
      publishErrorUnlessBenignCancellation(error)
      return false
    }
  }

  // MARK: - Audible chapters lookup (Audnexus via `/api/search/chapters`)

  /// Audible-Kapitel für eine ASIN abrufen (`GET /api/search/chapters?asin=&region=`).
  func searchAudibleChapters(asin: String, region: String) async throws -> ABSAudibleChaptersResponse {
    guard let c = client else { throw ABSAPIError.emptyBody }
    return try await c.searchChapters(asin: asin, region: region)
  }

  // MARK: - Cover online search & apply (`/api/search/covers`, `/api/items/:id/cover`)

  /// Online-Cover-Suche (`GET /api/search/covers?title=&author=&provider=`).
  func searchCoversOnline(title: String, author: String?, provider: String) async throws -> [String] {
    guard let c = client else { throw ABSAPIError.emptyBody }
    return try await c.searchCovers(title: title, author: author, provider: provider)
  }

  /// Setzt ein Cover per Remote-URL (`POST /api/items/:id/cover` mit `{ url }`) und aktualisiert das Detail.
  @discardableResult
  func applyCoverURL(itemId: String, url: String) async -> Bool {
    guard let c = client else { return false }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return false
    }
    do {
      try await c.applyCoverURL(itemId: itemId, url: url)
      // Cache löschen + Detail-Refresh, damit das neue Cover sofort erscheint.
      clearCoverImageCache()
      _ = await loadBookDetail(id: itemId)
      errorMessage = nil
      return true
    } catch {
      publishErrorUnlessBenignCancellation(error)
      return false
    }
  }

  /// Kapitel speichern (`POST /api/items/:id/chapters`) und Detail anschließend aktualisieren.
  @discardableResult
  func applyItemChapters(itemId: String, chapters: [ABSItemChaptersPayload.Chapter]) async -> Bool {
    guard let c = client else { return false }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return false
    }
    do {
      try await c.updateItemChapters(itemId: itemId, chapters: chapters)
      _ = await loadBookDetail(id: itemId)
      errorMessage = nil
      return true
    } catch {
      publishErrorUnlessBenignCancellation(error)
      return false
    }
  }

  /// Sofort verfügbare, zuletzt geladene Detail-Antwort (Beschreibung, Kapitel, volle Tracks, …) — lässt
  /// `BookDetailView` beim Öffnen direkt mit vollen Metadaten starten, statt auf den Server-Refresh zu warten.
  func cachedBookDetail(id: String) -> ABSBook? {
    guard let context = currentLocalLibraryMainContext() else { return cachedBookFallback(id: id) }
    return LocalLibraryQueries.bookDetail(context: context, id: id) ?? cachedBookFallback(id: id)
  }

  /// Erweiterte Antwort im Hintergrund persistieren — Detail-View muss nicht auf den Schreibvorgang warten.
  private func persistBookDetail(_ book: ABSBook) {
    guard let store = currentLocalLibraryStore() else { return }
    Task {
      try? await store.upsertBookDetail(book)
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
      return cachedPodcastEpisodeDetail(episode) ?? Self.emptyPodcastEpisodeDetail(episode)
    }
    do {
      let show = try await c.item(id: episode.libraryItemId, expanded: true)
      persistBookDetail(show)
      return Self.makePodcastEpisodeDetail(episode: episode, show: show)
    } catch {
      return cachedPodcastEpisodeDetail(episode) ?? Self.emptyPodcastEpisodeDetail(episode)
    }
  }

  /// Sofort verfügbare Episoden-/Show-Beschreibung aus der zuletzt gecachten Show-Detail-Antwort (`LocalBook.detailBlob`)
  /// — lässt `PodcastEpisodeDetailView` beim Öffnen direkt mit voller Beschreibung starten.
  func cachedPodcastEpisodeDetail(_ episode: ABSPodcastEpisodeListItem) -> ABSPodcastEpisodeExpandedDetail? {
    guard let context = currentLocalLibraryMainContext(),
      let show = LocalLibraryQueries.bookDetail(context: context, id: episode.libraryItemId)
    else { return nil }
    return Self.makePodcastEpisodeDetail(episode: episode, show: show)
  }

  private static func makePodcastEpisodeDetail(
    episode: ABSPodcastEpisodeListItem, show: ABSBook
  ) -> ABSPodcastEpisodeExpandedDetail {
    let dto = show.media.podcastEpisodes?.first { $0.id == episode.episodeId }
    let showMeta = show.media.metadata
    return ABSPodcastEpisodeExpandedDetail(
      episode: episode,
      subtitle: dto?.subtitle,
      episodeDescriptionHTML: dto?.description,
      showDescriptionHTML: showMeta.descriptionPlain ?? showMeta.description,
      pubDate: dto?.pubDate,
      showGenres: showMeta.genres,
      showAuthors: showMeta.authors ?? []
    )
  }

  private static func emptyPodcastEpisodeDetail(_ episode: ABSPodcastEpisodeListItem)
    -> ABSPodcastEpisodeExpandedDetail
  {
    ABSPodcastEpisodeExpandedDetail(
      episode: episode,
      subtitle: nil,
      episodeDescriptionHTML: nil,
      showDescriptionHTML: nil,
      pubDate: nil,
      showGenres: nil,
      showAuthors: []
    )
  }

  func requestPresentNowPlayingSheet() {
    nowPlayingSheetPresentationCounter &+= 1
  }

  func requestDismissNowPlayingSheet() {
    Self.debugLog.log("requestDismissNowPlayingSheet CALLED")
    nowPlayingSheetDismissCounter &+= 1
  }

  /// Nach `play` / `playPodcastEpisode`: nur wenn online und Setting aktiv.
  private func presentNowPlayingSheetOnAutoPlayIfNeeded() {
    guard !offlineHomeUIActive, openPlayerWhenStartPlaying else { return }
    requestPresentNowPlayingSheet()
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
      lastUpdate: lastUp,
      ebookProgress: progressByItemId[book.id]?.ebookProgress,
      ebookLocation: progressByItemId[book.id]?.ebookLocation
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
    let localInfo = resolvedLocalDownloadForPlayback(book: book)
    let local = localInfo?.root
    if offlineHomeUIActive, local == nil {
      errorMessage = "Download this title to play it offline."
      return
    }
    guard let c = clientForOfflineLocalPlayback() else { return }
    isPreparingPlayback = true
    defer { isPreparingPlayback = false }
    errorMessage = nil
    let playbackItemId = localInfo?.libraryItemId ?? book.id
    let manifestEpisodeId = localInfo?.episodeId
    let progressKey: String = {
      if let ep = manifestEpisodeId, !ep.isEmpty { return "\(playbackItemId)-\(ep)" }
      return playbackItemId
    }()
    let (resume, restartFromBeginning) = resolvedPlaybackStart(
      progressKey: progressKey,
      resumeAtOverride: resumeAtOverride
    )
    if restartFromBeginning {
      await preparePlaybackRestartFromBeginning(
        libraryItemId: playbackItemId,
        episodeId: manifestEpisodeId,
        progressKey: progressKey
      )
    }
    do {
      var resolved = book
      if let root = local, let manifest = ABSDownloadManifest.load(from: root) {
        let fromManifest = ABSBook.fromDownloadManifest(manifest)
        if mayUseServerNetwork, isNetworkReachable, !book.media.metadata.hasRichMetadata,
          let expanded = try? await c.item(id: playbackItemId, expanded: true)
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
            resolved = try await c.item(id: playbackItemId, expanded: true)
          } catch {}
        }
      }
      try await player.playBook(
        client: c,
        book: resolved,
        resumeAt: resume,
        localDownloadRoot: local,
        episodeId: manifestEpisodeId,
        autoPlay: autoPlay,
        attemptServerPlaySession: mayUseServerNetwork && isNetworkReachable,
        preferClientResumePosition: restartFromBeginning
      )
      UserDefaults.standard.set(resolved.id, forKey: Keys.lastPlayedItemId)
      if autoPlay {
        if let ep = manifestEpisodeId, !ep.isEmpty {
          let showLine = resolved.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
          let episode = ABSPodcastEpisodeListItem(
            libraryItemId: playbackItemId,
            libraryId: selectedPodcastLibrary?.id,
            episodeId: ep,
            episodeTitle: resolved.displayTitle,
            showTitle: showLine.isEmpty || showLine == "—" ? resolved.displayTitle : showLine,
            authorLine: resolved.displayAuthorsCardLine,
            duration: resolved.media.duration ?? 0,
            publishedAt: nil
          )
          bumpOptimisticContinueListeningForPodcastEpisode(episode, resumeAt: resume)
        } else {
          bumpOptimisticContinueListeningForAudiobook(resolved, resumeAt: resume)
        }
        presentNowPlayingSheetOnAutoPlayIfNeeded()
        if mayUseServerNetwork {
          Task { await loadStartDashboard() }
        }
      }
    } catch {
      publishErrorUnlessBenignCancellation(error)
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
    let progressKey = episode.progressLookupKey
    let (resume, restartFromBeginning) = resolvedPlaybackStart(
      progressKey: progressKey,
      resumeAtOverride: resumeAtOverride
    )
    if restartFromBeginning {
      await preparePlaybackRestartFromBeginning(
        libraryItemId: episode.libraryItemId,
        episodeId: episode.episodeId,
        progressKey: progressKey
      )
    }
    let stub = episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
    do {
      try await player.playBook(
        client: c,
        book: stub,
        resumeAt: resume,
        localDownloadRoot: local,
        episodeId: episode.episodeId,
        transcriptionLanguageOverride: podcastShowTranscriptionLanguage(for: episode.libraryItemId),
        autoPlay: autoPlay,
        attemptServerPlaySession: mayUseServerNetwork && isNetworkReachable,
        preferClientResumePosition: restartFromBeginning
      )
      UserDefaults.standard.set(stub.id, forKey: Keys.lastPlayedItemId)
      if autoPlay {
        bumpOptimisticContinueListeningForPodcastEpisode(episode, resumeAt: resume)
        presentNowPlayingSheetOnAutoPlayIfNeeded()
        if mayUseServerNetwork {
          Task { await loadStartDashboard() }
        }
      }
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
  }

  /// Fertige Hörbücher / Podcast-Folgen aus `progressByItemId` (für Stats-Achievements).
  private func listeningAchievementFinishedCounts() -> (books: Int, episodes: Int) {
    ensureLocalProgressLoaded()
    var books = 0
    var episodes = 0
    for progress in progressByItemId.values where progress.isFinished {
      let ep = progress.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if ep.isEmpty {
        books += 1
      } else {
        episodes += 1
      }
    }
    return (books, episodes)
  }

  /// Beim Öffnen des Stats-Tabs: leere Platzhalter oder letzter SwiftData-Snapshot.
  func prepareListeningAchievementsForStatsTab() {
    listeningAchievementsRebuildTask?.cancel()
    guard let context = currentLocalLibraryMainContext() else {
      listeningAchievementsSnapshot = .empty
      listeningOneTimeSnapshot = .empty
      return
    }
    listeningAchievementsSnapshot = LocalLibraryQueries.achievementsSnapshot(context: context) ?? .empty
    listeningOneTimeSnapshot = LocalLibraryQueries.oneTimeAchievementsSnapshot(context: context) ?? .empty
  }

  /// Nach geladenen Stats: Achievements im Hintergrund berechnen und cachen.
  func scheduleListeningAchievementsRebuild() {
    listeningAchievementsRebuildTask?.cancel()
    listeningAchievementsRebuildTask = Task { @MainActor [weak self] in
      guard let self else { return }
      guard !Task.isCancelled else { return }
      guard let stats = self.listeningStats else { return }
      let finished = self.listeningAchievementFinishedCounts()
      guard !Task.isCancelled else { return }
      let cal = Calendar(identifier: .gregorian)
      let snap = ListeningAchievementsSnapshot.make(
        stats: stats,
        calendar: cal,
        finishedBooks: finished.books,
        finishedEpisodes: finished.episodes
      )
      let oneTime = ListeningOneTimeAchievementsSnapshot.make(
        stats: stats,
        finishedBooks: finished.books,
        finishedEpisodes: finished.episodes,
        downloadedItemCount: self.downloadedItemIds.count,
        bookmarkCount: self.bookmarks.count,
        flags: OneTimeAchievementPersistentFlags.load()
      )
      self.listeningAchievementsSnapshot = snap
      self.listeningOneTimeSnapshot = oneTime
      if let store = self.currentLocalLibraryStore() {
        Task.detached(priority: .utility) {
          try? await store.replaceAchievementsSnapshot(snap)
          try? await store.replaceOneTimeAchievementsSnapshot(oneTime)
        }
      }
    }
  }

  func loadListeningStats() async {
    listeningStatsLoading = true
    defer { listeningStatsLoading = false }
    ensureLocalProgressLoaded()

    // Zuerst Cache — Stats-Tab sofort aufbauen, Netzwerk danach.
    if listeningStats == nil, let store = currentLocalLibraryStore(),
      let cachedResponse = await store.fetchListeningStatsResponse(),
      let cached = try? ABSListeningStatsResponse.decodeAPIPayload(cachedResponse.data)
    {
      listeningStats = cached
      listeningStatsFetchedAt = cachedResponse.fetchedAt
    }

    guard let c = client else {
      scheduleListeningAchievementsRebuild()
      return
    }

    if !isNetworkReachable {
      scheduleListeningAchievementsRebuild()
      return
    }

    errorMessage = nil
    do {
      let result = try await c.listeningStats()
      listeningStats = result.stats
      listeningStatsFetchedAt = Date()
      if let store = currentLocalLibraryStore() {
        try? await store.replaceListeningStatsResponse(rawData: result.rawData)
      }
      scheduleListeningAchievementsRebuild()
    } catch {
      if listeningStats == nil, let store = currentLocalLibraryStore(),
        let cachedResponse = await store.fetchListeningStatsResponse(),
        let cached = try? ABSListeningStatsResponse.decodeAPIPayload(cachedResponse.data)
      {
        listeningStats = cached
        listeningStatsFetchedAt = cachedResponse.fetchedAt
      }
      if listeningStats == nil {
        publishErrorUnlessBenignCancellation(error)
      } else {
        scheduleListeningAchievementsRebuild()
      }
    }
  }

  /// Wiedergabe beenden. `idlePlaceholder: false` entfernt die Mini-Player-Leiste vollständig (z. B. nach „Fertig“).
  func dismissPlayer(idlePlaceholder: Bool = true) async {
    Self.debugLog.log("dismissPlayer START idlePlaceholder=\(idlePlaceholder) activeBook=\(player.activeBook?.id ?? "nil") episodes=\(podcastEpisodes.count) chromeVisible=\(floatingChrome.gate.chromeVisible)")
    await player.closeSessionIfNeeded()
    await pushPendingEbookProgressSyncIfSafe()
    player.tearDownPlayer()
    // Gate + Inset sofort synchron leeren — tearDownPlayer setzt activeBook=nil, aber
    // floatingChrome wird sonst erst im nächsten Runloop-Tick via Combine-Sink aktualisiert.
    // In diesem stale-chrome Fenster (chromeVisible=true bei activeBook=nil) entsteht die
    // White-View beim Podcast „Fertig"-Flow.
    floatingChrome.syncChrome()
    player.setMiniPlayerPlaceholder(idlePlaceholder)
    // Floating-Bar-Visibility synchron nach dem Placeholder-Update aktualisieren.
    floatingChrome.syncChrome()
    Self.debugLog.log("dismissPlayer END activeBook=\(player.activeBook?.id ?? "nil") episodes=\(podcastEpisodes.count) chromeVisible=\(floatingChrome.gate.chromeVisible) inset=\(nowPlayingAccessoryScrollBottomInset)")
  }

  /// Hörbuch bis zum Ende gehört: lokal fertig (Offline) bzw. inkl. Server-Sync.
  private func handleAudiobookPlaybackCompleted() async {
    guard let bookId = player.activeBook?.id,
      player.activePlaybackEpisodeId == nil
    else { return }
    await markFinished(bookId: bookId)
  }

  /// Podcast-Folge bis zum Ende gehört: lokal fertig (Offline) bzw. inkl. Server-Sync.
  private func handlePodcastEpisodePlaybackCompleted() async {
    Self.debugLog.log("handlePodcastEpisodePlaybackCompleted CALLED episodeId=\(player.activePlaybackEpisodeId ?? "nil") activeBook=\(player.activeBook?.id ?? "nil")")
    guard player.activePlaybackEpisodeId != nil,
      let episode = podcastEpisodeForActivePlayback()
    else {
      Self.debugLog.log("handlePodcastEpisodePlaybackCompleted GUARD FAILED — no active episode")
      return
    }
    await markPodcastEpisodeFinished(episode)
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

  /// Aktuelle Position + ggf. Hörzeit lokal sichern (wie Pause / Offline-Modus betreten).
  private func flushActivePlaybackBeforeLocalProgressWrite() async {
    guard player.activeBook != nil else { return }
    recordActivePlaybackProgressLocally(markPendingServerSync: true)
    await player.flushPendingPlaySessionSync()
  }

  private func finishMarkFinishedLocally(
    downloadRemovalStorageId: String,
    wasPlaying: Bool,
    clearLastPlayedIfBookId: String?
  ) async {
    if wasPlaying {
      await dismissPlayer(idlePlaceholder: false)
    }
    requestDismissNowPlayingSheet()
    let dbgEpCount2 = podcastEpisodes.count
    let dbgFiltCount2 = podcastFilteredEpisodes.count
    let dbgChrome2 = floatingChrome.gate.chromeVisible
    let dbgInset2 = nowPlayingAccessoryScrollBottomInset
    let dbgActiveBook = player.activeBook?.id ?? "nil"
    Self.debugLog.log("finishMarkFinishedLocally AFTER dismiss wasPlaying=\(wasPlaying) episodes=\(dbgEpCount2) filtered=\(dbgFiltCount2) chromeVisible=\(dbgChrome2) inset=\(dbgInset2) activeBook=\(dbgActiveBook)")
    if let bid = clearLastPlayedIfBookId,
      UserDefaults.standard.string(forKey: Keys.lastPlayedItemId) == bid
    {
      UserDefaults.standard.removeObject(forKey: Keys.lastPlayedItemId)
    }
    removeLocalDownloadIfFinishedSetting(bookId: downloadRemovalStorageId)
    await refreshStartDashboardIfNeeded()
  }

  func markFinished(bookId: String) async {
    ensureLocalProgressLoaded()
    let wasCurrentPlayback = wasCurrentPlaybackForBook(bookId)
    if wasCurrentPlayback {
      await flushActivePlaybackBeforeLocalProgressWrite()
    }
    applyLocalMarkFinished(libraryItemId: bookId, episodeId: nil)
    patchBooksCatalogAfterAudiobookProgressChange(bookId: bookId, finished: true)
    pendingLocalProgressSyncKeys.insert(bookId)
    syncContinueListeningShelvesWithProgress()
    if defersProgressSyncToServer {
      persistHomeShelvesSnapshot()
      await finishMarkFinishedLocally(
        downloadRemovalStorageId: bookId,
        wasPlaying: wasCurrentPlayback,
        clearLastPlayedIfBookId: bookId
      )
      return
    }
    restoreServerClientIfNeeded()
    guard let c = client else {
      await finishMarkFinishedLocally(
        downloadRemovalStorageId: bookId,
        wasPlaying: wasCurrentPlayback,
        clearLastPlayedIfBookId: bookId
      )
      return
    }
    do {
      if wasCurrentPlayback {
        // Play-Session VOR dem PATCH schließen: `closeSessionIfNeeded` schickt einen letzten
        // `syncPlaySession(currentTime:)` + `closePlaySession` — liefe das erst nach
        // `markFinished` (wie früher via `finishMarkFinishedLocally`), würde der Server den
        // Media-Progress wieder mit currentTime < duration überschreiben und `isFinished`
        // zurücksetzen (Folge/Buch taucht nach Reload wieder als „neu"/angefangen auf).
        await dismissPlayer(idlePlaceholder: false)
        requestDismissNowPlayingSheet()
      }
      try await c.markFinished(libraryItemId: bookId)
      let auth = try await c.authorize()
      applyAuthorizeUser(auth.user)
      clearLocallyFinishedProgressKey(bookId)
      reconcileProgressAfterMarkFinished(libraryItemId: bookId, episodeId: nil)
      syncContinueListeningShelvesWithProgress()
      persistHomeShelvesSnapshot()
      if needsFullLibraryReloadAfterAudiobookProgressChange(bookId: bookId, finished: true) {
        await reloadLibrary(reset: true)
      }
      await finishMarkFinishedLocally(
        downloadRemovalStorageId: bookId,
        wasPlaying: wasCurrentPlayback,
        clearLastPlayedIfBookId: bookId
      )
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
  }

  func markUnfinished(bookId: String) async {
    await applyMarkUnfinished(
      libraryItemId: bookId,
      episodeId: nil,
      patchCatalog: { [weak self] in
        self?.patchBooksCatalogAfterAudiobookProgressChange(bookId: bookId, finished: false)
      },
      reloadLibraryIfNeeded: { [weak self] in
        guard let self else { return }
        if self.needsFullLibraryReloadAfterAudiobookProgressChange(bookId: bookId, finished: false) {
          await self.reloadLibrary(reset: true)
        }
      }
    )
  }

  func markPodcastEpisodeUnfinished(_ episode: ABSPodcastEpisodeListItem) async {
    await applyMarkUnfinished(
      libraryItemId: episode.libraryItemId,
      episodeId: episode.episodeId,
      patchCatalog: { },
      reloadLibraryIfNeeded: { [weak self] in
        guard let self else { return }
        if self.mainTab == .library, self.mediaCatalogKind == .podcasts {
          await self.reloadPodcastLibrary(reset: true)
        }
      }
    )
  }

  /// Gemeinsamer Rumpf für „Mark as not finished" (Hörbücher & Podcast-Folgen).
  /// `patchCatalog` wird nach `patchProgress` (vor `authorize`) aufgerufen, `reloadLibraryIfNeeded`
  /// nach `authorize` (awaited).
  private func applyMarkUnfinished(
    libraryItemId: String,
    episodeId: String?,
    patchCatalog: @escaping () -> Void,
    reloadLibraryIfNeeded: @escaping () async -> Void
  ) async {
    ensureLocalProgressLoaded()
    let key: String = {
      let ep = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return ep.isEmpty ? libraryItemId : "\(libraryItemId)-\(ep)"
    }()
    applyLocalMarkUnfinished(libraryItemId: libraryItemId, episodeId: episodeId)
    pendingLocalProgressSyncKeys.insert(key)
    syncContinueListeningShelvesWithProgress()
    if defersProgressSyncToServer {
      await refreshStartDashboardIfNeeded()
      return
    }
    restoreServerClientIfNeeded()
    guard let c = client else {
      await refreshStartDashboardIfNeeded()
      return
    }
    do {
      try await c.patchProgress(
        libraryItemId: libraryItemId,
        episodeId: episodeId,
        patch: ABSProgressPatch(currentTime: nil, duration: nil, progress: nil, isFinished: false)
      )
      patchCatalog()
      let auth = try await c.authorize()
      applyAuthorizeSession(auth)
      syncContinueListeningShelvesWithProgress()
      await reloadLibraryIfNeeded()
      await refreshStartDashboardIfNeeded()
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
  }

  /// Hörbuch: Fortschritt UND Hör-Sitzungen vollständig löschen (`DELETE /api/me/progress/:id`
  /// + `DELETE /api/sessions/:id` je Sitzung). Läuft der Titel gerade, wird die Wiedergabe
  /// beendet — sonst legt der nächste Play-Session-Sync sofort wieder einen 0%-Progress an
  /// („Reset wirkt erst beim zweiten Mal").
  func discardBookProgress(bookId: String) async {
    guard let c = client else { return }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    guard let row = progressByItemId[bookId] else { return }
    let playing = player.activeBook?.id == bookId && player.activePlaybackEpisodeId == nil
    suppressedContinueListeningKeys.insert(bookId)
    progressByItemId.removeValue(forKey: bookId)
    pendingLocalProgressSyncKeys.remove(bookId)
    clearLocallyFinishedProgressKey(bookId)
    removeAudiobookFromContinueListeningShelves(bookId: bookId)
    persistProgressToLocalStore()
    syncContinueListeningShelvesWithProgress()
    patchBooksCatalogAfterAudiobookProgressDiscard(bookId: bookId)
    do {
      if playing {
        // Wiedergabe VOR dem Löschen beenden: schließt die offene Play-Session — sonst
        // erzeugt deren nächster `syncPlaySession(currentTime:)` den Media-Progress direkt neu.
        await dismissPlayer(idlePlaceholder: false)
        requestDismissNowPlayingSheet()
      }
      clearPendingOfflineListeningSeconds(progressKey: bookId)
      await deleteAllListeningSessions(client: c, libraryItemId: bookId, episodeId: nil)
      try await c.deleteMediaProgress(progressRowId: row.idForMediaProgressDeleteRequest)
      progressByItemId.removeValue(forKey: bookId)
      removeAudiobookFromContinueListeningShelves(bookId: bookId)
      syncContinueListeningShelvesWithProgress()
      persistHomeShelvesSnapshot()
      let auth = try await c.authorize()
      applyAuthorizeSession(auth)
      progressByItemId.removeValue(forKey: bookId)
      removeAudiobookFromContinueListeningShelves(bookId: bookId)
      syncContinueListeningShelvesWithProgress()
      if needsFullLibraryReloadAfterAudiobookProgressDiscard(bookId: bookId) {
        await reloadLibrary(reset: true)
      }
      await refreshProgressFromServer()
      await refreshStartDashboardIfNeeded()
      suppressedContinueListeningKeys.remove(bookId)
      // `refreshProgressFromServer` könnte eine Restspur re-mergen — lokal endgültig verwerfen.
      progressByItemId.removeValue(forKey: bookId)
      persistProgressToLocalStore()
    } catch {
      suppressedContinueListeningKeys.remove(bookId)
      publishErrorUnlessBenignCancellation(error)
    }
  }

  func markPodcastEpisodeFinished(_ episode: ABSPodcastEpisodeListItem) async {
    let dbgWasPlaying = player.activeBook?.id == episode.libraryItemId && player.activePlaybackEpisodeId == episode.episodeId
    let dbgEpCount = podcastEpisodes.count
    let dbgFiltCount = podcastFilteredEpisodes.count
    let dbgChrome = floatingChrome.gate.chromeVisible
    let dbgInset = nowPlayingAccessoryScrollBottomInset
    let dbgTab = String(describing: mainTab)
    Self.debugLog.log("markPodcastEpisodeFinished START wasPlaying=\(dbgWasPlaying) episodes=\(dbgEpCount) filtered=\(dbgFiltCount) tab=\(dbgTab) chromeVisible=\(dbgChrome) inset=\(dbgInset)")
    ensureLocalProgressLoaded()
    let wasPlaying =
      player.activeBook?.id == episode.libraryItemId && player.activePlaybackEpisodeId == episode.episodeId
    if wasPlaying {
      await flushActivePlaybackBeforeLocalProgressWrite()
    }
    let storageId = podcastEpisodeOfflineStorageId(episode)
    applyLocalMarkFinished(libraryItemId: episode.libraryItemId, episodeId: episode.episodeId)
    pendingLocalProgressSyncKeys.insert(episode.progressLookupKey)
    syncContinueListeningShelvesWithProgress()
    // „New“-Feed sofort erleichtern (nicht erst beim nächsten Listen-Refresh) — Sendungs-Listen
    // bleiben unangetastet, dort steht die Folge wie bei Hörbüchern mit Häkchen weiter drin.
    removeFinishedPodcastEpisodeFromNewFeed(episode)
    if defersProgressSyncToServer {
      // Gerät gesperrt / kein Netz: New-Feed wurde lokal um die fertige Folge erleichtert;
      // beim nächsten Vordergrund-Wechsel Liste nachladen (sonst bleibt sie u. U. leer) und
      // Server-Sync durchführen. Siehe `applyPendingPodcastRefreshIfNeeded()`.
      pendingPodcastRefreshOnResume = true
      persistHomeShelvesSnapshot()
      await finishMarkFinishedLocally(
        downloadRemovalStorageId: storageId,
        wasPlaying: wasPlaying,
        clearLastPlayedIfBookId: nil
      )
      return
    }
    restoreServerClientIfNeeded()
    guard let c = client else {
      persistHomeShelvesSnapshot()
      await finishMarkFinishedLocally(
        downloadRemovalStorageId: storageId,
        wasPlaying: wasPlaying,
        clearLastPlayedIfBookId: nil
      )
      return
    }
    do {
      if wasPlaying {
        // Play-Session VOR dem PATCH schließen — sonst überschreibt der Session-Sync/-Close
        // aus `dismissPlayer` (bisher erst nach der Server-Antwort in
        // `finishMarkFinishedLocally`) den frisch gesetzten `isFinished`-Status auf dem Server
        // wieder mit currentTime < duration, und die Folge bleibt in „New".
        await dismissPlayer(idlePlaceholder: false)
        requestDismissNowPlayingSheet()
      }
      try await c.markFinished(libraryItemId: episode.libraryItemId, episodeId: episode.episodeId)
      let auth = try await c.authorize()
      applyAuthorizeUser(auth.user)
      clearLocallyFinishedProgressKey(episode.progressLookupKey)
      reconcileProgressAfterMarkFinished(
        libraryItemId: episode.libraryItemId, episodeId: episode.episodeId)
      syncContinueListeningShelvesWithProgress()
      persistHomeShelvesSnapshot()
      await finishMarkFinishedLocally(
        downloadRemovalStorageId: storageId,
        wasPlaying: wasPlaying,
        clearLastPlayedIfBookId: nil
      )
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
  }

  /// Podcast-Folge: Fortschritt UND Hör-Sitzungen vollständig löschen (wie beim Hörbuch).
  func discardPodcastEpisodeProgress(_ episode: ABSPodcastEpisodeListItem) async {
    guard let c = client else { return }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    let key = episode.progressLookupKey
    guard let row = progressByItemId[key] ?? progressByItemId["\(episode.libraryItemId)/ep/\(episode.episodeId)"]
    else { return }
    let playing =
      player.activeBook?.id == episode.libraryItemId && player.activePlaybackEpisodeId == episode.episodeId
    suppressedContinueListeningKeys.insert(key)
    purgeLocalProgressForPodcastEpisode(episode)
    removePodcastEpisodeFromContinueListeningShelves(episode)
    persistProgressToLocalStore()
    syncContinueListeningShelvesWithProgress()
    do {
      if playing {
        // Wiedergabe VOR dem Löschen beenden: schließt die offene Play-Session — sonst
        // erzeugt deren nächster `syncPlaySession(currentTime:)` den Media-Progress direkt neu.
        await dismissPlayer(idlePlaceholder: false)
        requestDismissNowPlayingSheet()
      }
      clearPendingOfflineListeningSeconds(progressKey: key)
      await deleteAllListeningSessions(
        client: c, libraryItemId: episode.libraryItemId, episodeId: episode.episodeId)
      try await c.deleteMediaProgress(progressRowId: row.idForMediaProgressDeleteRequest)
      purgeLocalProgressForPodcastEpisode(episode)
      removePodcastEpisodeFromContinueListeningShelves(episode)
      syncContinueListeningShelvesWithProgress()
      persistHomeShelvesSnapshot()
      let auth = try await c.authorize()
      applyAuthorizeSession(auth)
      purgeLocalProgressForPodcastEpisode(episode)
      removePodcastEpisodeFromContinueListeningShelves(episode)
      syncContinueListeningShelvesWithProgress()
      await refreshProgressFromServer()
      await refreshStartDashboardIfNeeded()
      suppressedContinueListeningKeys.remove(key)
      // `refreshProgressFromServer` könnte eine Restspur re-mergen — lokal endgültig verwerfen.
      purgeLocalProgressForPodcastEpisode(episode)
      persistProgressToLocalStore()
    } catch {
      suppressedContinueListeningKeys.remove(key)
      publishErrorUnlessBenignCancellation(error)
    }
  }

  /// Alle Hör-Sitzungen eines Buchs / einer Folge auf dem Server löschen (Reset Progress).
  /// Fehler einzelner Löschungen sind nicht fatal — der Progress-Delete läuft trotzdem weiter.
  private func deleteAllListeningSessions(
    client c: ABSAPIClient,
    libraryItemId: String,
    episodeId: String?
  ) async {
    let sessions: [ABSListeningSession]
    if let eid = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines), !eid.isEmpty {
      let episode = podcastEpisodes.first {
        $0.libraryItemId == libraryItemId && $0.episodeId == eid
      }
      let showMid =
        podcastShows.first(where: { $0.id == libraryItemId })?.mediaId
        ?? podcastSearchBooks.first(where: { $0.id == libraryItemId })?.mediaId
      if let episode {
        sessions = await loadPodcastEpisodeListeningSessions(episode, showMediaId: showMid)
      } else {
        sessions = (try? await c.listeningSessionsForLibraryItem(
          libraryItemId: libraryItemId, episodeId: eid, itemsPerPage: 100, page: 0))?.sessions ?? []
      }
    } else {
      let mediaId =
        books.first(where: { $0.id == libraryItemId })?.mediaId
        ?? startBooks.first(where: { $0.id == libraryItemId })?.mediaId
      sessions = await loadBookListeningSessions(libraryItemId: libraryItemId, bookMediaId: mediaId)
    }
    for session in sessions {
      try? await c.deleteListeningSession(sessionId: session.id)
    }
  }

  /// Reset Progress: aufgelaufene Offline-Hörsekunden für diesen Key verwerfen — sonst legt
  /// `flushPendingOfflineListeningTime` beim nächsten Sync wieder eine Server-Session an.
  private func clearPendingOfflineListeningSeconds(progressKey: String) {
    var map = Self.loadPendingOfflineListeningSecondsMap()
    guard map.removeValue(forKey: progressKey) != nil else { return }
    Self.savePendingOfflineListeningSecondsMap(map)
  }

  private func endDownloadBackgroundExecution() {
    guard downloadBackgroundTaskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(downloadBackgroundTaskId)
    downloadBackgroundTaskId = .invalid
  }

  private func beginDownloadBackgroundExecution() {
    // BG-Task für die gesamte Download-Queue offenhalten (nicht pro Item neu starten).
    guard downloadBackgroundTaskId == .invalid else { return }
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
    guard player.activeBook?.id == manifest.libraryItemId else { return }
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
        transcriptionLanguageOverride: ep == nil
          ? nil
          : podcastShowTranscriptionLanguage(for: manifest.libraryItemId),
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
    let book = episode.playbackStubBook(libraryId: selectedPodcastLibrary?.id)
    beginOfflineItemDownload(
      book: book,
      episodeId: episode.episodeId,
      storageItemId: podcastEpisodeOfflineStorageId(episode)
    )
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
      publishErrorUnlessBenignCancellation(error)
    }
  }

  func startDownload(book: ABSBook) {
    beginOfflineItemDownload(book: book, episodeId: nil, storageItemId: book.id)
  }

  /// Einheitlicher Download-Einstieg für Hörbücher und Podcast-Folgen (`DownloadManager` löst Tracks auf).
  private func beginOfflineItemDownload(
    book: ABSBook,
    episodeId: String?,
    storageItemId: String
  ) {
    guard let c = client else { return }
    // Anzeige-Metadaten für den Download-Manager cachen — BEVOR der Download startet.
    // Das Manifest existiert erst nach Abschluss; Podcast-Folgen sind oft nicht im In-Memory-Katalog.
    let epId = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines)
    pendingDownloadCatalog[storageItemId] = DownloadCatalogEntry(
      libraryItemId: book.id,
      title: book.displayTitle,
      subtitle: book.displayAuthors,
      isPodcastEpisode: (epId?.isEmpty == false)
    )
    beginDownloadBackgroundExecution()
    let reuse = player.playSessionIdForReuseWhenDownloadingSameItem(
      libraryItemId: book.id,
      episodeId: episodeId
    )
    let reuseTracks = reuse != nil ? player.audioTracksForActiveSessionReuse() : []
    downloads.startDownload(
      client: c,
      book: book,
      episodeId: episodeId,
      storageItemId: storageItemId,
      reusePlaySessionId: reuse,
      reusePlaySessionTracks: reuseTracks.isEmpty ? nil : reuseTracks
    ) { [weak self] ok in
      Task { @MainActor [weak self] in
        guard let model = self else { return }
        // BG-Task erst beenden, wenn die komplette Queue leer ist (kein aktiver/wartender Download).
        if model.downloads.activeItemId == nil, model.downloads.queuedItemIds.isEmpty {
          model.endDownloadBackgroundExecution()
        }
        // Cache-Eintrag aufräumen — nach Abschluss liefert das Manifest die Metadaten.
        if ok || (!model.downloads.queuedItemIds.contains(storageItemId)
          && model.downloads.activeItemId != storageItemId)
        {
          model.pendingDownloadCatalog.removeValue(forKey: storageItemId)
        }
        if ok {
          model.downloadedItemIds.insert(storageItemId)
          model.persistDownloads()
          await model.applyLocalPlaybackIfDownloadMatchesCurrent(storageId: storageItemId)
        } else if model.downloads.activeItemId != storageItemId,
          !model.downloads.queuedItemIds.contains(storageItemId)
        {
          // Weder aktiv noch wartend → echter Fehler (kein Queue-bedingter Cancel).
          model.errorMessage = "Download failed."
        }
      }
    }
  }

  func removeLocalDownload(bookId: String) {
    // Gezielter Cancel: entfernt das Item aus der Queue oder bricht nur es ab, falls aktiv.
    downloads.cancel(itemId: bookId)
    downloads.deleteDownload(itemId: bookId)
    downloadedItemIds.remove(bookId)
    pendingDownloadCatalog.removeValue(forKey: bookId)
    persistDownloads()
  }

  func localDownloadRoot(for itemId: String) -> URL? {
    guard downloadedItemIds.contains(itemId) else { return nil }
    return try? downloads.downloadFolder(for: itemId)
  }

  func coverURL(for itemId: String, tier: CoverImageTier = .thumbnail) -> URL? {
    guard let url = ABSAPIClient.normalizeServerURL(serverURL) else { return nil }
    return ABSAPIClient.itemCoverURL(baseURL: url, itemId: itemId, tier: tier)
  }

  func coverImageCacheScopeId(for itemId: String, tier: CoverImageTier = .thumbnail) -> String {
    if let suffix = tier.cacheScopeSuffix { return "\(itemId)#\(suffix)" }
    return itemId
  }

  /// Kombiniert den globalen Revision-Zähler (manuelles „Clear cache") mit `updatedAt` eines Items,
  /// damit ein geändertes Server-Cover automatisch erkannt wird — nicht erst nach manueller Cache-Leerung.
  /// Ohne `updatedAt` (z. B. Autorenbild, generische IDs ohne Katalog-Objekt) bleibt es beim globalen Zähler.
  func coverImageCacheRevision(forItemUpdatedAt updatedAt: Date?) -> Int {
    guard let updatedAt else { return coverImageCacheRevision }
    return coverImageCacheRevision &+ Int(updatedAt.timeIntervalSince1970)
  }

  /// Autorenfoto (`GET /api/authors/:id/image`).
  func authorImageURL(authorId: String) -> URL? {
    guard let url = ABSAPIClient.normalizeServerURL(serverURL) else { return nil }
    return url.appendingPathComponent("api/authors/\(authorId)/image")
  }

  /// Erstes Hörbuch in einer Serie/Sammlung für das Cover.
  func browseRepresentativeBookItemId(from books: [ABSBook]?) -> String? {
    browseSeriesCoverBookIds(from: books, maxCount: 1).first
  }

  /// Bis zu vier Bücher einer Serie für das Multi-Cover in Listen.
  func browseSeriesCoverBookIds(from books: [ABSBook]?, maxCount: Int = 4) -> [String] {
    guard let books, maxCount > 0 else { return [] }
    var ids: [String] = []
    ids.reserveCapacity(min(maxCount, books.count))
    for book in books {
      guard !book.id.isEmpty else { continue }
      ids.append(book.id)
      if ids.count == maxCount { break }
    }
    return ids
  }

  /// Ordner für Library-Cache inkl. Cover (`AccountCacheDirectory.accountDir`); nil ohne Login/URL.
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
    DetailCoverAverageRGBCache.clearAll(account: account)
    coverImageCacheRevision &+= 1
  }

  func applySleepTimer(seconds: TimeInterval?) {
    if let seconds, seconds > 0 {
      player.applySleepTimerRemaining(seconds)
      OneTimeAchievementPersistentFlags.markSleepTimerUsed()
    } else {
      player.clearSleepTimer()
      player.sleepTimerMode = .off
    }
  }

  func applySleepTimer(minutes: Int) {
    if minutes <= 0 {
      applySleepTimer(seconds: nil)
    } else {
      player.sleepTimerMode = .minutes(minutes)
      applySleepTimer(seconds: TimeInterval(minutes * 60))
    }
  }

  @discardableResult
  func applySleepTimer(chapters: Int) -> Bool {
    guard chapters >= 1, let targetIndex = player.chapterTargetIndex(forCount: chapters) else {
      return false
    }
    player.sleepTimerMode = .chapters(chapters)
    player.applySleepTimerChapterTarget(targetIndex)
    OneTimeAchievementPersistentFlags.markSleepTimerUsed()
    return player.isSleepTimerActive
  }

  /// Client-Validierung für Passwort-Änderung; `nil` = ok.
  func validateAccountPasswordChange(current: String, new: String, confirm: String) -> String? {
    if new != confirm {
      return "New password and confirmation do not match."
    }
    if !new.isEmpty, current == new {
      return "New password must be different from the current password."
    }
    if !isServerRoot, new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Please enter a new password."
    }
    return nil
  }

  /// Passwort am Server ändern; bei Erfolg `nil`, sonst Fehlermeldung.
  func changeAccountPassword(current: String, new: String, confirm: String) async -> String? {
    guard mayUseServerNetwork, let c = client else {
      return "Password change is not available in offline mode."
    }
    if let validation = validateAccountPasswordChange(current: current, new: new, confirm: confirm) {
      return validation
    }
    do {
      try await c.changePassword(current: current, new: new)
      return nil
    } catch let ABSAPIError.httpStatus(_, body) {
      let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return trimmed.isEmpty ? "Could not change password." : trimmed
    } catch {
      return error.localizedDescription
    }
  }

  func applyPlaybackSpeed(_ rate: Float) {
    player.setPlaybackRate(rate)
    if rate > 1.01 {
      OneTimeAchievementPersistentFlags.markFasterPlaybackUsed()
    }
  }

  /// EQ-Preset für die laufende Wiedergabe setzen (Voice Focus etc.).
  func applyEQPreset(_ preset: AudioEQPreset) {
    player.setEQPreset(preset)
  }

  /// Schreibt die aktuelle Player-Position in `progressByItemId` und in LocalStore (vor Server-PATCH).
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
    persistProgressToLocalStore()
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
    Self.debugLog.log("handlePlaybackPaused CALLED mainTab=\(String(describing: mainTab)) activeBook=\(player.activeBook?.id ?? "nil")")
    recordActivePlaybackProgressLocally()
    if mayUseServerNetwork {
      if player.isRemotePlaySessionActive {
        await player.flushPendingPlaySessionSync()
      } else {
        await syncProgressToServer()
      }
      // eBook-PATCH erst nach Hörbuch-Session-Sync — sonst setzt ABS `currentTime` zurück.
      await pushPendingEbookProgressSyncIfSafe()
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
  /// - Returns: `true` nur bei vollständig sauberem Sync (alle Patches erfolgreich). Bei `false` bleiben betroffene
  ///   Keys in `pendingLocalProgressSyncKeys` — der Aufrufer setzt `pendingPostOfflineModeProgressSync`, sodass der
  ///   nächste `isNetworkReachable`-Wechsel (`pathMonitor.pathUpdateHandler`) automatisch erneut synct.
  @discardableResult
  func syncOfflineProgressToServer() async -> Bool {
    guard isNetworkReachable,
      ABSAPIClient.normalizeServerURL(serverURL) != nil,
      !token.isEmpty
    else { return false }
    ensureLocalProgressLoaded()
    restoreServerClientIfNeeded()
    guard let c = client else { return false }
    await player.flushPendingPlaySessionSync()
    await flushPendingOfflineListeningTime()
    let keysToSync = pendingLocalProgressSyncKeys.isEmpty
      ? Set(progressByItemId.values.map(\.progressLookupKey))
      : pendingLocalProgressSyncKeys
    var syncedFinishedKeys: [String] = []
    var finishedSnapshots: [String: ABSUserMediaProgress] = [:]
    var hadFailure = false
    for key in keysToSync {
      guard let p = progressByItemId[key] else { continue }
      if p.isFinished {
        finishedSnapshots[key] = p
      }
      do {
        if p.isFinished {
          try await c.markFinished(libraryItemId: p.libraryItemId, episodeId: p.episodeId)
          syncedFinishedKeys.append(key)
        } else {
          let dur = max(p.duration, 0)
          let pos = max(0, p.currentTime)
          let prog: Double = {
            if dur > 0 { return min(1, max(0, pos / dur)) }
            return min(1, max(0, p.progress))
          }()
          try await c.patchProgress(
            libraryItemId: p.libraryItemId,
            episodeId: p.episodeId,
            patch: ABSProgressPatch(
              currentTime: pos,
              duration: dur > 0 ? dur : nil,
              progress: prog,
              isFinished: false
            )
          )
          pendingLocalProgressSyncKeys.remove(p.progressLookupKey)
        }
      } catch {
        // Key bleibt in `pendingLocalProgressSyncKeys` (nie hier entfernt) — nächster Versuch holt ihn nach.
        hadFailure = true
      }
    }
    await refreshProgressFromServer()
    for key in syncedFinishedKeys {
      guard let snapshot = finishedSnapshots[key] else { continue }
      let lid = snapshot.libraryItemId
      let ep = snapshot.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if progressByItemId[key]?.isFinished == true {
        clearLocallyFinishedProgressKey(key)
        pendingLocalProgressSyncKeys.remove(key)
        reconcileProgressAfterMarkFinished(libraryItemId: lid, episodeId: ep.isEmpty ? nil : ep)
      } else {
        progressByItemId[key] = snapshot
        markProgressKeyLocallyFinished(key)
        pendingLocalProgressSyncKeys.insert(key)
      }
      if ep.isEmpty {
        removeBookFromCatalogList(lid)
      }
    }
    persistHomeShelvesSnapshot()
    syncContinueListeningShelvesWithProgress()
    persistProgressToLocalStore()
    return !hadFailure
  }

  private func persistDownloads(skipRefresh: Bool = false) {
    UserDefaults.standard.set(Array(downloadedItemIds), forKey: downloadsUserDefaultsKey())
    if !skipRefresh {
      refreshDownloadedShelfFromManifests()
    }
  }

  private func downloadsUserDefaultsKey() -> String {
    if let key = activeAccountKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
      return "\(Keys.downloads).\(key)"
    }
    return Keys.downloads
  }

  private func loadDownloadedItemIdsForActiveAccount() {
    migrateLegacyDownloadsIfNeeded()
    downloadedItemIds = Set(UserDefaults.standard.stringArray(forKey: downloadsUserDefaultsKey()) ?? [])
  }

  /// Einmalig: globale Download-Liste dem aktiven Account zuordnen.
  private func migrateLegacyDownloadsIfNeeded() {
    let accountKey = downloadsUserDefaultsKey()
    guard UserDefaults.standard.object(forKey: accountKey) == nil else { return }
    guard let legacy = UserDefaults.standard.stringArray(forKey: Keys.downloads), !legacy.isEmpty else { return }
    UserDefaults.standard.set(legacy, forKey: accountKey)
  }

  private func activeLibraryIdSet() -> Set<String> {
    var ids = Set<String>()
    if let id = selectedBooksLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
      ids.insert(id)
    }
    if let id = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
      ids.insert(id)
    }
    if let id = selectedBooksLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
      ids.insert(id)
    }
    for lib in libraries {
      let id = lib.id.trimmingCharacters(in: .whitespacesAndNewlines)
      if !id.isEmpty { ids.insert(id) }
    }
    return ids
  }

  func downloadManifestBelongsToActiveAccount(_ manifest: ABSDownloadManifest) -> Bool {
    // Während Account-Wechsel / Bootstrap sind `libraries` noch leer — dann nicht
    // alle Downloads blind akzeptieren, sondern anhand der gespeicherten Account-Library-IDs filtern.
    let activeLibs = activeLibraryIdSet()
    guard let lid = manifest.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty else {
      return true
    }
    if activeLibs.isEmpty {
      // Fallback: Library-IDs aus dem aktiven Stored Account.
      let stored = activeAccountKey.flatMap { key in
        storedAccounts.first(where: { $0.accountKey == key })
      }
      var storedLibIds = Set<String>()
      for libId in [stored?.booksLibraryId, stored?.podcastsLibraryId, stored?.ebooksLibraryId] {
        if let lid2 = libId?.trimmingCharacters(in: .whitespacesAndNewlines), !lid2.isEmpty {
          storedLibIds.insert(lid2)
        }
      }
      if storedLibIds.isEmpty { return true }
      return storedLibIds.contains(lid)
    }
    return activeLibs.contains(lid)
  }

  private func downloadBookBelongsToActiveAccount(_ book: ABSBook) -> Bool {
    guard downloadedShelfBooks.contains(where: { $0.id == book.id }) else { return true }
    let activeLibs = activeLibraryIdSet()
    guard let lid = book.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty else {
      return false
    }
    guard !activeLibs.isEmpty else { return true }
    return activeLibs.contains(lid)
  }

  /// Continue-Regale: Downloads anderer Server/User nicht anzeigen (gemeinsamer Download-Ordner).
  private func purgeForeignContinueListeningItems() {
    guard !startShelves.isEmpty else { return }
    let activeLibs = activeLibraryIdSet()
    let booksLib = selectedBooksLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let podcastsLib = selectedPodcastLibrary?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var changed = false
    let newShelves = startShelves.map { shelf -> ABSStartShelfSection in
      guard isHomeContinueCategory(shelf.category) else { return shelf }
      let books = shelf.books.filter { book in
        if downloadedShelfBooks.contains(where: { $0.id == book.id }) {
          return downloadBookBelongsToActiveAccount(book)
        }
        if !booksLib.isEmpty, let lid = book.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !lid.isEmpty
        {
          return lid == booksLib
        }
        if !activeLibs.isEmpty, let lid = book.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !lid.isEmpty
        {
          return activeLibs.contains(lid)
        }
        return true
      }
      let episodes = shelf.podcastEpisodes.filter { episode in
        if let lid = episode.libraryId?.trimmingCharacters(in: .whitespacesAndNewlines), !lid.isEmpty {
          if !podcastsLib.isEmpty { return lid == podcastsLib }
          if !activeLibs.isEmpty { return activeLibs.contains(lid) }
        }
        if !podcastsLib.isEmpty {
          return episode.libraryId == nil || episode.libraryId?.isEmpty == true
        }
        return true
      }
      if books.count == shelf.books.count, episodes.count == shelf.podcastEpisodes.count { return shelf }
      changed = true
      return ABSStartShelfSection(
        id: shelf.id,
        category: shelf.category,
        displayTitle: shelf.displayTitle,
        books: books,
        podcastEpisodes: episodes,
        authors: shelf.authors,
        series: shelf.series
      )
    }
    if changed {
      startShelves = newShelves
      recomputeStartBooksUnion(from: newShelves)
    }
  }

  private func cacheAccountURL() -> URL? {
    guard let u = ABSAPIClient.normalizeServerURL(serverURL)?.absoluteString, !token.isEmpty else { return nil }
    return AccountCacheDirectory.accountDir(serverURL: u, userId: resolvedLocalStoreUserId())
  }

  /// SwiftData-"Server-Kopie" für den aktiven Account (siehe Migrationsplan „SwiftData-Vollmigration“).
  /// Lazy geöffnet/gewechselt bei Server-/User-Wechsel, `nil` vor Login.
  func currentLocalLibraryStore() -> LocalLibraryStore? {
    guard ABSAPIClient.normalizeServerURL(serverURL) != nil, !token.isEmpty else { return nil }
    return LocalLibraryStoreManager.store(serverURL: serverURL, userId: resolvedLocalStoreUserId())
  }

  /// Synchroner Main-Actor-Zugriff auf dieselbe SwiftData-"Server-Kopie" — für schnelle Einzel-Lookups
  /// (Existenz-Checks, reaktive Bibliothekswechsel), die bisher einen synchronen LocalStore-Read gemacht haben.
  private func currentLocalLibraryMainContext() -> ModelContext? {
    guard ABSAPIClient.normalizeServerURL(serverURL) != nil, !token.isEmpty else { return nil }
    return LocalLibraryStoreManager.mainContext(serverURL: serverURL, userId: resolvedLocalStoreUserId())
  }

  /// UserId für LocalStore — auch zwischen Authorize und gespeichertem Account-Wechsel.
  private func resolvedLocalStoreUserId() -> String? {
    let fromSession = sessionUserId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !fromSession.isEmpty { return fromSession }
    if let key = activeAccountKey,
      let account = storedAccounts.first(where: { $0.accountKey == key })
    {
      let uid = account.userId.trimmingCharacters(in: .whitespacesAndNewlines)
      if !uid.isEmpty { return uid }
    }
    return nil
  }

  /// eBook-Lesesession — erst bei Reader/eBook-Refresh, nicht beim Kaltstart.
  private func ensureEbookLocalSessionIfNeeded() {
    let uid =
      UserDefaults.standard.string(forKey: Keys.sessionUserId)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !uid.isEmpty, let account = cacheAccountURL() else { return }
    sessionUserId = uid
    EbookLocalStore.updateActiveSession(account: account, userId: uid)
  }

  /// Bücher-Katalog + Home-Regale aus dem letzten Server-Stand (Tab-Wechsel / Bibliothekswahl).
  private func restoreBooksCatalogAndHomeFromLocalStore(libraryIdOverride: String? = nil) {
    restoreHomeLaunchStateFromLocalStore(libraryIdOverride: libraryIdOverride)
    restoreBooksCatalogPagesFromLocalStore(libraryIdOverride: libraryIdOverride)
  }

  /// Lädt gespeicherte Podcast-Folgen (recent-episodes oder Expand-Fallback) aus der lokalen Server-Kopie.
  private func applyPodcastListFromLocalStore(libraryId: String) {
    let lid = libraryId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lid.isEmpty, let context = currentLocalLibraryMainContext() else { return }
    guard let cached = LocalLibraryQueries.podcastEpisodes(context: context, libraryId: lid), !cached.items.isEmpty
    else { return }
    podcastEpisodes = ABSPodcastEpisodeListItem.dedupeRows(cached.items)
    podcastLibraryTotal = max(cached.total, podcastEpisodes.count)
    podcastEpisodesPagingFromRecentAPI = cached.pagingFromRecentAPI
    podcastLibraryPage = cached.pagingFromRecentAPI ? (podcastEpisodes.count + 39) / 40 : 1
  }

  /// Podcast-Bibliothek aus UserDefaults (Kaltstart, vor Katalog-Restore).
  private func restorePodcastLibrarySelectionFromLocalStore(libraryIdOverride: String? = nil) {
    if !libraries.isEmpty, sortedPodcastLibraries.isEmpty {
      clearPodcastLibraryStateWithoutPersistingNone()
      return
    }
    let libId =
      (libraryIdOverride ?? UserDefaults.standard.string(forKey: Keys.podcastsLibrary))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if libId == Keys.librarySelectionNone {
      selectedPodcastLibrary = nil
      return
    }
    guard !libId.isEmpty else { return }
    if selectedPodcastLibrary == nil || selectedPodcastLibrary?.id != libId {
      selectedPodcastLibrary = ABSLibrary(id: libId, name: "Podcasts", mediaType: "podcast", displayOrder: nil)
    }
  }

  private func restorePodcastCatalogFromLocalStore(libraryIdOverride: String? = nil) {
    if !libraries.isEmpty, sortedPodcastLibraries.isEmpty {
      clearPodcastLibraryStateWithoutPersistingNone()
      return
    }
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
      applyPodcastListFromLocalStore(libraryId: libId)
    } else if podcastEpisodes.isEmpty {
      applyPodcastListFromLocalStore(libraryId: libId)
    }
    let ascending = podcastCatalogSortField == .random ? true : !podcastCatalogSortDescending
    let sortKey = podcastCatalogSortField.apiSortParameter
    if let context = currentLocalLibraryMainContext(),
      let rows = LocalLibraryQueries.podcastShows(
        context: context, libraryId: libId, sortField: sortKey, ascending: ascending)
    {
      podcastShows = rows
    }
    if !startShelves.isEmpty, !isNetworkReachable, !offlineHomeUIActive {
      repairContinueListeningShelfFromLocalProgressOnly()
    }
  }

  /// Vereinigt **alle** lokalen Quellen (wie `mergedLocalCatalogBooks()` für Bücher) statt nur eine
  /// einzelne `@Published`-Liste zurückzugeben — sonst fehlt eine Folge, sobald `podcastEpisodes` gerade
  /// einen (Show-)Ausschnitt statt der vollen Menge hält.
  private func continuePodcastEpisodeMetadataPool() -> [ABSPodcastEpisodeListItem] {
    var byKey: [String: ABSPodcastEpisodeListItem] = [:]
    func add(_ list: [ABSPodcastEpisodeListItem]) {
      for episode in list {
        let key = episode.canonicalDedupeKey
        if let existing = byKey[key] {
          byKey[key] = episode.preferringRicherMetadata(than: existing)
        } else {
          byKey[key] = episode
        }
      }
    }
    add(mergedLocalPodcastEpisodes())
    // Downloads immer dazu — verlässliche Metadaten auch offline, bevor die Folgenliste je geladen/gecacht wurde.
    add(podcastEpisodesFromLocalDownloadManifests(showId: nil))
    if let context = currentLocalLibraryMainContext(),
      let cached = LocalLibraryQueries.itemsInProgressPayload(context: context, limit: 200)?.podcastEpisodes
    {
      add(cached)
    }
    return Array(byKey.values)
  }

  /// Wie `localContinueAudiobookBookCandidates()`: die Bibliotheks-ID grenzt nur zusätzlich ein, wenn sie
  /// aufgelöst werden konnte — sie ist nie ein Total-Blocker (z. B. Kaltstart offline vor Podcasts-Tab-Besuch).
  private func localContinuePodcastEpisodeCandidates() -> [ABSPodcastEpisodeListItem] {
    var pool: [ABSPodcastEpisodeListItem] = []
    for e in continuePodcastEpisodeMetadataPool() {
      guard let p = progressByItemId[e.progressLookupKey], !p.isFinished, p.currentTime > 2 else { continue }
      pool.append(e)
    }
    if let plid = resolvedPodcastLibraryId() {
      pool = pool.filter { row in
        guard let rowLib = Self.normalizedLibraryId(row.libraryId) else { return true }
        return rowLib == plid
      }
    }
    return dedupePodcastEpisodesForHomeContinueList(pool)
  }

  func applyAuthorizeSession(_ auth: ABSLoginResponse, persistToDisk: Bool = true) {
    applyAuthorizeUser(auth.user, persistToDisk: persistToDisk)
    if let settings = auth.serverSettings {
      serverSettings = settings
    }
    if let libId = auth.userDefaultLibraryId?.trimmingCharacters(in: .whitespacesAndNewlines),
      !libId.isEmpty
    {
      UserDefaults.standard.set(libId, forKey: Keys.userDefaultLibraryId)
    }
    if persistToDisk {
      syncStoredAccountFromSession()
    }
  }

  var isSessionGuest: Bool {
    sessionUserType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "guest"
  }

  var sessionAccountTypeLabel: String {
    let t = sessionUserType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !t.isEmpty else { return "User" }
    return t.prefix(1).uppercased() + t.dropFirst()
  }

  func applyAuthorizeUser(_ user: ABSUser, persistToDisk: Bool = true) {
    isServerRoot = user.isRoot
    isServerAdmin = user.isAdmin
    sessionUserId = user.id
    sessionUsername = user.username
    sessionUserType = user.type ?? "user"
    UserDefaults.standard.set(user.id, forKey: Keys.sessionUserId)
    EbookLocalStore.updateActiveSession(account: cacheAccountURL(), userId: user.id)
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

  /// Ein bereits lokal gespeichertes eBook bleibt auch ohne Serververbindung lesbar.
  func cachedEbookFormat(libraryItemId: String) -> ABSEbookFormat? {
    EbookLocalStore.cachedEbookIfPresent(
      account: cacheAccountURL(),
      libraryItemId: libraryItemId
    )?.format
  }

  /// EPUB oder PDF öffnen: lokaler Cache zuerst, sonst Download vom Server.
  func openAttachedEbook(for book: ABSBook) async {
    ensureEbookLocalSessionIfNeeded()
    isPreparingEbook = true
    errorMessage = nil
    defer { isPreparingEbook = false }

    if mayUseServerNetwork, isNetworkReachable {
      await refreshProgressFromServer()
    }

    if let account = cacheAccountURL(),
      let cached = EbookLocalStore.cachedEbookIfPresent(account: account, libraryItemId: book.id)
    {
      let meta = EbookLocalStore.loadDownloadMeta(
        account: account, libraryItemId: book.id, format: cached.format)
      let title = meta?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
      EbookLocalStore.rememberKnownFormat(cached.format, libraryItemId: book.id)
      prepareEbookOpenFromServer(libraryItemId: book.id, format: cached.format)
      ebookReaderSession = EbookReaderPresentation(
        title: (title?.isEmpty == false ? title! : book.displayTitle),
        author: book.displayAuthors,
        libraryItemId: book.id,
        localFileURL: cached.url,
        format: cached.format,
        serverResumeProgression: ebookResumeProgressionForReader(libraryItemId: book.id)
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
        errorMessage = "No eBook or PDF file is available for this audiobook."
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
      prepareEbookOpenFromServer(libraryItemId: resolved.id, format: format)
      ebookReaderSession = EbookReaderPresentation(
        title: resolved.displayTitle,
        author: resolved.displayAuthors,
        libraryItemId: resolved.id,
        localFileURL: fileURL,
        format: format,
        serverResumeProgression: ebookResumeProgressionForReader(libraryItemId: resolved.id)
      )
    } catch {
      publishErrorUnlessBenignCancellation(error)
    }
  }

  /// Lesefortschritt (0…1): Hilfs-Cache sofort; Server-PATCH nur wenn Hörbuch-Fortschritt nicht gefährdet wird.
  func scheduleEbookProgressSync(libraryItemId: String, fraction: Double) {
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    let f = min(1, max(0, fraction))
    guard !id.isEmpty, f > 0.001 else { return }
    if let local = EbookLocalStore.loadProgressFraction(libraryItemId: id), local >= 0.995, f < 0.995 {
      return
    }
    EbookLocalStore.saveProgressFraction(f, libraryItemId: id)
    if let last = lastSyncedEbookFractionByItemId[id], abs(last - f) < 0.003 { return }
    pendingEbookProgressSync = (id, f)
    // Während aktiver Hörbuch-Play-Session kein `PATCH` — wartet auf Pause/Close.
    guard !shouldDeferEbookProgressServerPatch(libraryItemId: id) else { return }
    ebookProgressSyncTask?.cancel()
    ebookProgressSyncTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 450_000_000)
      guard !Task.isCancelled else { return }
      await self?.pushPendingEbookProgressSyncIfSafe()
    }
  }

  /// Reader geschlossen: letzten Stand senden (ohne `/authorize` — der überschreibt laufenden Hör-Fortschritt).
  func flushEbookProgressSync() {
    ebookProgressSyncTask?.cancel()
    ebookProgressSyncTask = nil
    Task { @MainActor [weak self] in
      await self?.pushPendingEbookProgressSyncIfSafe()
      self?.refreshEbookContinueReadingShelf()
    }
  }

  /// eBook-PATCH nur wenn keine offene Hörbuch-Session und Hörbuch-Felder mitgeschickt werden können.
  private func pushPendingEbookProgressSyncIfSafe() async {
    guard let pending = pendingEbookProgressSync else { return }
    if shouldDeferEbookProgressServerPatch(libraryItemId: pending.libraryItemId) { return }
    guard mayUseServerNetwork, isNetworkReachable, let c = client else { return }
    guard
      let patch = patchPreservingAudiobookFields(
        libraryItemId: pending.libraryItemId,
        ebookProgress: pending.fraction
      )
    else { return }
    do {
      try await c.patchProgress(libraryItemId: pending.libraryItemId, patch: patch)
      lastSyncedEbookFractionByItemId[pending.libraryItemId] = pending.fraction
      pendingEbookProgressSync = nil
      mergeEbookProgressIntoRow(libraryItemId: pending.libraryItemId, fraction: pending.fraction)
      refreshEbookContinueReadingShelf()
    } catch {}
  }

  /// Hörbuch-Play-Session läuft — eBook-`PATCH` würde Session/Fortschritt stören.
  private func shouldDeferEbookProgressServerPatch(libraryItemId: String) -> Bool {
    guard player.isRemotePlaySessionActive,
      player.activeBook?.id == libraryItemId,
      (player.activePlaybackEpisodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return false }
    return true
  }

  /// Titel mit Hörbuch-Spur: `PATCH` nur mit `currentTime`/`duration` — sonst `nil` (nur lokaler eBook-Cache).
  private func itemNeedsAudiobookFieldsInEbookProgressPatch(libraryItemId: String) -> Bool {
    if isActivelyPlayingMedia(libraryItemId: libraryItemId, episodeId: nil) { return true }
    if let row = progressByItemId[libraryItemId], row.episodeId == nil {
      if row.isFinished || row.currentTime > 0.5 || row.duration > 0 { return true }
    }
    for b in mergedLocalCatalogBooks() where b.id == libraryItemId {
      if b.isPlayableAudiobook { return true }
    }
    return false
  }

  private func audiobookFieldsForEbookProgressPatch(
    libraryItemId: String
  ) -> (currentTime: Double, duration: Double, progress: Double, isFinished: Bool)? {
    if isActivelyPlayingMedia(libraryItemId: libraryItemId, episodeId: nil) {
      let dur = player.totalDuration
      guard dur > 0 else { return nil }
      let pos = max(0, player.globalPosition)
      return (pos, dur, min(1, max(0, pos / dur)), false)
    }
    guard let row = progressByItemId[libraryItemId], row.episodeId == nil else { return nil }
    guard row.currentTime > 0.5 || row.duration > 0 || row.isFinished else { return nil }
    let dur = row.duration
    let prog: Double = {
      if dur > 0 { return min(1, max(0, row.progress > 0 ? row.progress : row.currentTime / dur)) }
      return min(1, max(0, row.progress))
    }()
    return (row.currentTime, dur, prog, row.isFinished)
  }

  /// Hörbuch-Felder beim eBook-PATCH mitschicken — sonst setzt ABS `currentTime` zurück.
  /// Reine eBook-Items: nur `ebookProgress`. Hörbuch+EPUB ohne bekannte Hörposition: kein PATCH (`nil`).
  private func patchPreservingAudiobookFields(
    libraryItemId: String,
    ebookProgress: Double
  ) -> ABSProgressPatch? {
    var patch = ABSProgressPatch(ebookProgress: ebookProgress)
    guard itemNeedsAudiobookFieldsInEbookProgressPatch(libraryItemId: libraryItemId) else {
      return patch
    }
    guard let fields = audiobookFieldsForEbookProgressPatch(libraryItemId: libraryItemId) else {
      return nil
    }
    patch.currentTime = fields.currentTime
    if fields.duration > 0 {
      patch.duration = fields.duration
      patch.progress = fields.progress
    }
    patch.isFinished = fields.isFinished
    return patch
  }

  /// Anzeige: Server/`authorize`-Cache plus On-Device-Hilfs-Fortschritt (Maximum).
  func ebookDisplayProgressFraction(libraryItemId: String, format: ABSEbookFormat? = nil) -> Double? {
    _ = format
    let serverF = progressByItemId[libraryItemId]?.ebookProgress
    let localF = EbookLocalStore.loadProgressFraction(libraryItemId: libraryItemId)
    let f = [serverF, localF].compactMap { $0 }.max()
    guard let f, f > 0.005 else { return nil }
    let clamped = min(1, max(0, f))
    if clamped >= 0.995 { return 1.0 }
    return clamped
  }

  /// Listen-Metadaten für eBooks (Prozent aus Server-Fortschritt).
  func ebookProgressMetadataLabel(libraryItemId: String) -> String? {
    guard let f = ebookDisplayProgressFraction(libraryItemId: libraryItemId), f < 0.995 else { return nil }
    return "\(Int((f * 100).rounded()))% read"
  }

  /// Play-/Read-Button-Beschriftung aus Server-Fortschritt.
  func ebookOpenPillCaption(libraryItemId: String) -> String {
    guard let f = ebookDisplayProgressFraction(libraryItemId: libraryItemId) else { return "Read" }
    if f >= 0.995 { return "Finished" }
    if f > 0.005 { return "Continue reading" }
    return "Read"
  }

  /// Resume beim Öffnen: Maximum aus Server (`/authorize`) und On-Device-Hilfs-Cache.
  func ebookResumeProgressionForReader(libraryItemId: String) -> Double? {
    let serverF = progressByItemId[libraryItemId]?.ebookProgress
    let localF = EbookLocalStore.loadProgressFraction(libraryItemId: libraryItemId)
    guard let f = [serverF, localF].compactMap({ $0 }).filter({ $0 > 0.005 }).max(),
      f < 0.995
    else { return nil }
    let clamped = min(1, max(0, f))
    EbookLocalStore.saveProgressFraction(clamped, libraryItemId: libraryItemId)
    return clamped
  }

  /// Vor dem Öffnen: kein Locator löschen — seitengenaues Resume bleibt lokal erhalten.
  private func prepareEbookOpenFromServer(libraryItemId: String, format: ABSEbookFormat) {
    _ = libraryItemId
    _ = format
  }

  /// Gespeicherter Readium-Locator (seitengenau), falls vorhanden.
  func ebookResumeLocatorForReader(libraryItemId: String, format: ABSEbookFormat) -> Locator? {
    ensureEbookLocalSessionIfNeeded()
    return EbookLocalStore.loadReadiumLocator(libraryItemId: libraryItemId, format: format)
  }

  /// Nur `ebookProgress` in bestehender Zeile aktualisieren — Hörbuch-Felder unangetastet.
  private func mergeEbookProgressIntoRow(libraryItemId: String, fraction: Double?) {
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }
    if let fraction { EbookLocalStore.saveProgressFraction(fraction, libraryItemId: id) }
    if let existing = progressByItemId[id] {
      progressByItemId[id] = ABSUserMediaProgress(
        mediaProgressServerId: existing.mediaProgressServerId,
        libraryItemId: existing.libraryItemId,
        episodeId: existing.episodeId,
        duration: existing.duration,
        progress: existing.progress,
        currentTime: existing.currentTime,
        isFinished: existing.isFinished,
        lastUpdate: existing.lastUpdate,
        ebookProgress: fraction ?? existing.ebookProgress,
        ebookLocation: existing.ebookLocation
      )
    } else if let fraction {
      progressByItemId[id] = ABSUserMediaProgress(
        libraryItemId: id,
        episodeId: nil,
        duration: 0,
        progress: 0,
        currentTime: 0,
        isFinished: false,
        lastUpdate: nil,
        ebookProgress: fraction
      )
    }
    persistProgressToLocalStore()
  }

  private func syncEbookFractionCacheFromAuthorizeRow(_ progress: ABSUserMediaProgress) {
    guard progress.episodeId == nil, let f = progress.ebookProgress, f > 0.001 else { return }
    if let localF = EbookLocalStore.loadProgressFraction(libraryItemId: progress.libraryItemId),
      localF >= 0.995, f < 0.995
    { return }
    EbookLocalStore.saveProgressFraction(f, libraryItemId: progress.libraryItemId)
    lastSyncedEbookFractionByItemId[progress.libraryItemId] = f
  }

  /// eBook als gelesen markieren (100 %), Reader schließen, aus Continue Reading entfernen.
  func markEbookAsFinished(libraryItemId: String, format: ABSEbookFormat) async {
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }
    ebookProgressSyncTask?.cancel()
    ebookProgressSyncTask = nil
    pendingEbookProgressSync = nil
    let fraction = 1.0
    EbookLocalStore.clearReadiumLocator(libraryItemId: id, format: format)
    EbookLocalStore.saveProgressFraction(fraction, libraryItemId: id)
    lastSyncedEbookFractionByItemId[id] = fraction
    mergeEbookProgressIntoRow(libraryItemId: id, fraction: fraction)
    if ebookReaderSession?.libraryItemId == id {
      ebookReaderSession = nil
    }
    persistHomeShelvesSnapshot()
    refreshEbookContinueReadingShelf()
    guard mayUseServerNetwork, isNetworkReachable, let c = client else { return }
    guard let patch = patchPreservingAudiobookFields(libraryItemId: id, ebookProgress: fraction) else { return }
    do {
      try await c.patchProgress(libraryItemId: id, patch: patch)
      refreshEbookContinueReadingShelf()
    } catch {}
  }

  /// Lesezeichen zurücksetzen: Server-PATCH + Hilfs-Cache löschen.
  func resetEbookReadingProgress(libraryItemId: String, format: ABSEbookFormat) async {
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }
    ebookProgressSyncTask?.cancel()
    ebookProgressSyncTask = nil
    pendingEbookProgressSync = nil
    lastSyncedEbookFractionByItemId.removeValue(forKey: id)
    EbookLocalStore.clearReadiumLocator(libraryItemId: id, format: format)
    EbookLocalStore.clearProgressFraction(libraryItemId: id)
    mergeEbookProgressIntoRow(libraryItemId: id, fraction: 0)
    refreshEbookContinueReadingShelf()
    guard mayUseServerNetwork, isNetworkReachable, let c = client else { return }
    guard let patch = patchPreservingAudiobookFields(libraryItemId: id, ebookProgress: 0) else { return }
    do {
      try await c.patchProgress(libraryItemId: id, patch: patch)
      refreshEbookContinueReadingShelf()
    } catch {}
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
      persistBookmarksToLocalStore()
      return true
    } catch {
      publishErrorUnlessBenignCancellation(error)
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
      persistBookmarksToLocalStore()
    } catch {
      publishErrorUnlessBenignCancellation(error)
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
      publishErrorUnlessBenignCancellation(error)
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

  private func persistBookmarksToLocalStore() {
    guard let store = currentLocalLibraryStore() else { return }
    let list = bookmarks
    Task.detached(priority: .utility) {
      try? await store.replaceAllBookmarks(list)
    }
  }

  private func applyUserBookmarks(_ list: [ABSAudioBookmark]?, persistToDisk: Bool = true) {
    bookmarks = list ?? []
    guard persistToDisk else { return }
    persistBookmarksToLocalStore()
  }

  /// Neueren `lastUpdate` behalten; bei abweichendem `isFinished` gewinnt die Server-Zeile — außer bei aktiver Wiedergabe / frischerem lokalem „nicht fertig“.
  private func mergedUserMediaProgress(
    existing: ABSUserMediaProgress?,
    incoming: ABSUserMediaProgress
  ) -> ABSUserMediaProgress {
    func finish(_ base: ABSUserMediaProgress) -> ABSUserMediaProgress {
      mergedApplyingServerEbookProgress(existing: existing, incoming: incoming, base: base)
    }

    let key = incoming.progressLookupKey
    if localFinishedProgressKeys.contains(key) {
      if incoming.isFinished {
        return finish(incoming)
      }
      if let existing, existing.isFinished {
        return finish(existing)
      }
      let dur = max(existing?.duration ?? 0, incoming.duration, existing?.currentTime ?? 0, 1)
      return finish(
        ABSUserMediaProgress(
          mediaProgressServerId: existing?.mediaProgressServerId ?? incoming.mediaProgressServerId,
          libraryItemId: incoming.libraryItemId,
          episodeId: incoming.episodeId,
          duration: dur,
          progress: 1,
          currentTime: dur,
          isFinished: true,
          lastUpdate: max(existing?.lastUpdate ?? 0, incoming.lastUpdate ?? 0, Int64(Date().timeIntervalSince1970 * 1000)),
          ebookProgress: incoming.ebookProgress ?? existing?.ebookProgress,
          ebookLocation: incoming.ebookLocation ?? existing?.ebookLocation
        )
      )
    }
    guard let existing else { return finish(incoming) }
    if pendingLocalProgressSyncKeys.contains(key) {
      // Lokal gesetzter Fortschritt (z. B. „mark as not finished") hat Vorrang vor veraltetem
      // Server-Stand aus `authorize` — der `patchProgress`-Call hat den neuen Zustand bereits
      // gesendet; ein kurz danach eintreffender `authorize` kann noch den alten Stand liefern.
      if existing.isFinished != incoming.isFinished { return finish(existing) }
      let localTs = existing.lastUpdate ?? 0
      let serverTs = incoming.lastUpdate ?? 0
      if existing.currentTime + 1 >= incoming.currentTime || localTs >= serverTs {
        return finish(existing)
      }
    }
    if incoming.isFinished != existing.isFinished {
      if isActivelyPlayingProgress(existing) || isActivelyPlayingProgress(incoming) {
        return finish(existing.isFinished ? incoming : existing)
      }
      if !existing.isFinished, (existing.lastUpdate ?? 0) >= (incoming.lastUpdate ?? 0) {
        return finish(existing)
      }
      // Lokal „fertig“ (z. B. Offline markiert) — nicht durch veralteten authorize-Eintrag überschreiben.
      if existing.isFinished, !incoming.isFinished { return finish(existing) }
      return finish(incoming)
    }
    let t0 = existing.lastUpdate ?? 0
    let t1 = incoming.lastUpdate ?? 0
    if t0 > t1 { return finish(existing) }
    if t1 > t0 { return finish(incoming) }
    return finish(existing.currentTime >= incoming.currentTime ? existing : incoming)
  }

  /// eBook-Lesefortschritt: Maximum aus Zeile, Server und On-Device-`ebook_fraction.json`.
  private func mergedApplyingServerEbookProgress(
    existing: ABSUserMediaProgress?,
    incoming: ABSUserMediaProgress,
    base: ABSUserMediaProgress
  ) -> ABSUserMediaProgress {
    let resolved = resolvedEbookProgressFraction(
      libraryItemId: base.libraryItemId,
      rowFraction: base.ebookProgress,
      serverFraction: incoming.ebookProgress
    )
    guard let resolved else { return base }
    return ABSUserMediaProgress(
      mediaProgressServerId: base.mediaProgressServerId,
      libraryItemId: base.libraryItemId,
      episodeId: base.episodeId,
      duration: base.duration,
      progress: base.progress,
      currentTime: base.currentTime,
      isFinished: base.isFinished,
      lastUpdate: base.lastUpdate,
      ebookProgress: resolved,
      ebookLocation: incoming.ebookLocation ?? base.ebookLocation
    )
  }

  private func resolvedEbookProgressFraction(
    libraryItemId: String,
    rowFraction: Double?,
    serverFraction: Double?
  ) -> Double? {
    let localF = EbookLocalStore.loadProgressFraction(libraryItemId: libraryItemId)
    guard let f = [rowFraction, serverFraction, localF].compactMap({ $0 }).max() else { return nil }
    let clamped = min(1, max(0, f))
    if clamped >= 0.995 { return 1.0 }
    return clamped > 0.001 ? clamped : nil
  }

  /// Katalog nutzt Server-Filter auf Fortschritt (nicht „Alle“ / nur Download/eBook).
  private func catalogUsesProgressServerFilter() -> Bool {
    switch libraryCatalogQuickFilter {
    case .inProgress, .finished, .notStarted:
      return true
    case .downloaded, .ebooks, .ebooksSupplementary, nil:
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
    if let book = books.first(where: { $0.id == id }) { return book }
    if let book = browseEbooks.first(where: { $0.id == id }) { return book }
    if let book = browseEbooksSupplementary.first(where: { $0.id == id }) { return book }
    if let book = startBooks.first(where: { $0.id == id }) { return book }
    if let book = searchBooks.first(where: { $0.id == id }) { return book }
    return downloadedShelfBooks.first(where: { $0.id == id })
  }

  /// Autor-/Serien-Detail liefert oft dünnere Stubs — eBook-/Spur-Metadaten aus Katalog/LocalStore mergen.
  func bookStubEnrichedForListDisplay(_ book: ABSBook) -> ABSBook {
    var result = book
    if let cached = mergedLocalCatalogBooks().first(where: { $0.id == book.id }) {
      result = result.preferringRicherListMetadata(than: cached)
    }
    if let stub = lookupBookStub(id: book.id) {
      result = result.preferringRicherListMetadata(than: stub)
    }
    if let context = currentLocalLibraryMainContext() {
      if let stored = LocalLibraryQueries.book(context: context, id: book.id) {
        result = result.preferringRicherListMetadata(than: stored)
      }
      if let detail = LocalLibraryQueries.bookDetail(context: context, id: book.id) {
        result = result.preferringRicherListMetadata(than: detail)
      }
    }
    return result
  }

  /// Katalog-eBook-Filter — Stub-Metadaten und persistierte Flags (OR, nie DB-only false blockieren).
  func bookMatchesEbookCatalogFilter(_ book: ABSBook) -> Bool {
    if book.matchesBooksEbookCatalogFilter { return true }
    if let context = currentLocalLibraryMainContext(),
      let flags = LocalLibraryQueries.bookCatalogEbookFlags(context: context, id: book.id),
      flags.hasEbook
    {
      return true
    }
    return false
  }

  /// Cover-Badge supplementäres eBook — Stub zuerst, dann persistierte Flags (z. B. nach expandiertem Detail).
  func bookShowsSupplementaryEbookBadge(_ book: ABSBook) -> Bool {
    if book.isCatalogSupplementaryEbook { return true }
    if let context = currentLocalLibraryMainContext(),
      let flags = LocalLibraryQueries.bookCatalogEbookFlags(context: context, id: book.id),
      flags.hasSupplementary
    {
      return true
    }
    return false
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
    case .downloaded, .ebooks, .ebooksSupplementary, nil:
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

  /// Podcast-Tab „New“ (`recent-episodes`): fertige Folge sofort ausblenden. Bewusst NUR der
  /// New-Feed — in Sendungs-Listen (`podcastFilteredEpisodes` / Show-Cache) bleibt die Folge wie
  /// bei Hörbüchern mit `isFinished`-Häkchen stehen. Das Mutieren während des Overlay-Dismiss war
  /// früher nur deshalb problematisch, weil der `chromeVisible`-Branch in `MainTabShellView` bei
  /// jedem Flip die View-Identität zerstörte (seit `tabViewBottomAccessory(isEnabled:)` behoben).
  private func removeFinishedPodcastEpisodeFromNewFeed(_ episode: ABSPodcastEpisodeListItem) {
    let key = episode.progressLookupKey
    let hadInNew = podcastEpisodes.contains { $0.progressLookupKey == key }
    guard hadInNew else { return }
    podcastEpisodes.removeAll { $0.progressLookupKey == key }
    podcastLibraryTotal = max(podcastEpisodes.count, podcastLibraryTotal - 1)
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
    case .downloaded, .ebooks, .ebooksSupplementary, nil:
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

  private func localFinishedProgressKeysStorageKey() -> String {
    guard let u = ABSAPIClient.normalizeServerURL(serverURL)?.absoluteString, !u.isEmpty else {
      return Keys.localFinishedProgressKeys
    }
    return "\(Keys.localFinishedProgressKeys).\(u)"
  }

  private func loadLocalFinishedProgressKeys() {
    localFinishedProgressKeys = Set(
      UserDefaults.standard.stringArray(forKey: localFinishedProgressKeysStorageKey()) ?? []
    )
  }

  private func persistLocalFinishedProgressKeys() {
    UserDefaults.standard.set(
      Array(localFinishedProgressKeys),
      forKey: localFinishedProgressKeysStorageKey()
    )
  }

  private func markProgressKeyLocallyFinished(_ key: String) {
    let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !k.isEmpty else { return }
    localFinishedProgressKeys.insert(k)
    persistLocalFinishedProgressKeys()
  }

  private func clearLocallyFinishedProgressKey(_ key: String) {
    let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !k.isEmpty else { return }
    localFinishedProgressKeys.remove(k)
    persistLocalFinishedProgressKeys()
  }

  private func isProgressKeyBlockedFromContinueListening(_ key: String) -> Bool {
    let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !k.isEmpty else { return false }
    if suppressedContinueListeningKeys.contains(k) { return true }
    return isLocallyMarkedFinished(progressKey: k)
  }

  private func isLocallyMarkedFinished(progressKey: String) -> Bool {
    let k = progressKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !k.isEmpty else { return false }
    if localFinishedProgressKeys.contains(k) { return true }
    return progressByItemId[k]?.isFinished == true
  }

  /// Startposition für Wiedergabe; nach „Fertig“ ohne Override von vorn.
  private func resolvedPlaybackStart(
    progressKey: String,
    resumeAtOverride: Double?
  ) -> (resume: Double, restartFromBeginning: Bool) {
    ensureLocalProgressLoaded()
    if let override = resumeAtOverride {
      return (max(0, override), override <= 0.001)
    }
    if isLocallyMarkedFinished(progressKey: progressKey) {
      return (0, true)
    }
    return (progressByItemId[progressKey]?.currentTime ?? 0, false)
  }

  /// Fortschritt lokal/auf dem Server zurücksetzen, bevor ein fertiges Medium neu startet.
  private func preparePlaybackRestartFromBeginning(
    libraryItemId: String,
    episodeId: String?,
    progressKey: String
  ) async {
    clearLocallyFinishedProgressKey(progressKey)
    if progressByItemId[progressKey] != nil {
      applyLocalMarkUnfinished(libraryItemId: libraryItemId, episodeId: episodeId)
      pendingLocalProgressSyncKeys.insert(progressKey)
    }
    if mayUseServerNetwork, isNetworkReachable, let c = client {
      try? await c.patchProgress(
        libraryItemId: libraryItemId,
        episodeId: episodeId,
        patch: ABSProgressPatch(currentTime: 0, duration: nil, progress: 0, isFinished: false)
      )
    }
    syncContinueListeningShelvesWithProgress()
  }

  private func applyLocalMarkFinished(libraryItemId: String, episodeId: String?) {
    let key: String = {
      let ep = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if ep.isEmpty { return libraryItemId }
      return "\(libraryItemId)-\(ep)"
    }()
    markProgressKeyLocallyFinished(key)
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
      lastUpdate: max(now, (existing?.lastUpdate ?? 0) + 1),
      ebookProgress: existing?.ebookProgress,
      ebookLocation: existing?.ebookLocation
    )
    persistProgressToLocalStore()
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
    // Sonst überschreibt der nächste `applyUserProgress`-Merge (nach `authorize()`) das
    // „nicht fertig" wieder mit „fertig", weil der Key noch als lokal-finished markiert ist.
    clearLocallyFinishedProgressKey(key)
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
      lastUpdate: max(now, (existing.lastUpdate ?? 0) + 1),
      ebookProgress: existing.ebookProgress,
      ebookLocation: existing.ebookLocation
    )
    persistProgressToLocalStore()
  }

  /// Nach „Fertig“: Server-Zeile übernehmen oder lokalen Eintrag entfernen (ABS liefert den Eintrag oft nicht mehr).
  private func reconcileProgressAfterMarkFinished(libraryItemId: String, episodeId: String?) {
    let key: String = {
      let ep = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if ep.isEmpty { return libraryItemId }
      return "\(libraryItemId)-\(ep)"
    }()
    if localFinishedProgressKeys.contains(key) {
      if progressByItemId[key]?.isFinished != true {
        applyLocalMarkFinished(libraryItemId: libraryItemId, episodeId: episodeId)
      } else {
        persistProgressToLocalStore()
      }
      return
    }
    if let row = progressByItemId[key], row.isFinished {
      persistProgressToLocalStore()
      return
    }
    progressByItemId.removeValue(forKey: key)
    clearLocallyFinishedProgressKey(key)
    persistProgressToLocalStore()
  }

  private func persistProgressToLocalStore() {
    guard let store = currentLocalLibraryStore() else { return }
    let list = Array(progressByItemId.values)
    Task.detached(priority: .utility) {
      try? await store.replaceAllProgress(list)
    }
  }

  /// SwiftData-`LocalProgress` in `progressByItemId` mergen — z. B. Offline-Home ohne vorherigen `/authorize`.
  private var localProgressLoaded = false

  private func ensureLocalProgressLoaded() {
    guard !localProgressLoaded else { return }
    localProgressLoaded = true
    loadLocalFinishedProgressKeys()
    guard let context = currentLocalLibraryMainContext() else { return }
    let list = (try? context.fetch(FetchDescriptor<LocalProgress>()))?.map { $0.toABSUserMediaProgress() } ?? []
    guard !list.isEmpty else { return }
    applyUserProgress(list, persistToDisk: false)
  }

  /// Nach Fortschrittsänderungen (Fertig markiert, Download entfernt, …): aktuellen `startShelves`-Snapshot
  /// neu persistieren — ersetzt die frühere Datei-Löschung (`invalidateCachedPersonalizedHome`), da SwiftData
  /// den Snapshot direkt korrekt überschreiben kann statt ihn nur zu invalidieren.
  private func persistHomeShelvesSnapshot() {
    persistHomeShelvesToLocalStore()
  }

  private func applyUserProgress(_ list: [ABSUserMediaProgress]?, persistToDisk: Bool = true) {
    for p in list ?? [] {
      let key = p.progressLookupKey
      if p.isFinished {
        clearLocallyFinishedProgressKey(key)
      }
      progressByItemId[key] = mergedUserMediaProgress(existing: progressByItemId[key], incoming: p)
      if let merged = progressByItemId[key] {
        syncEbookFractionCacheFromAuthorizeRow(merged)
      }
    }
    syncLastPlayedPreferenceWithServerProgress()
    syncContinueListeningShelvesWithProgress()
    guard persistToDisk else { return }
    persistProgressToLocalStore()
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

  /// App-Start: Fortschritt aus `authorize` / LocalStore — ohne geladenes Home-Regal oder Katalogseite.
  private func launchResumeProgress() -> ABSUserMediaProgress? {
    if let shelf = preferredContinueListeningResumeProgress() { return shelf }

    let open =
      progressByItemId.values.filter {
        !$0.isFinished && $0.currentTime > Self.continueListeningMinPositionSeconds
      }
    guard !open.isEmpty else { return nil }

    if let lastId = UserDefaults.standard.string(forKey: Keys.lastPlayedItemId)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !lastId.isEmpty
    {
      if let hit = open.first(where: { $0.libraryItemId == lastId }) { return hit }
      if let p = progressByItemId[lastId],
        !p.isFinished,
        p.currentTime > Self.continueListeningMinPositionSeconds
      {
        return p
      }
      if let hit = open.first(where: { $0.progressLookupKey.hasPrefix("\(lastId)/ep/") }) {
        return hit
      }
    }

    return open.max(by: resumeProgressOrderedBefore)
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
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      final class ResumeBox: @unchecked Sendable {
        var continuation: CheckedContinuation<Void, Never>?
        func resumeOnce() {
          continuation?.resume()
          continuation = nil
        }
      }
      let box = ResumeBox()
      box.continuation = continuation
      Task.detached(priority: .userInitiated) { @MainActor in
        await work()
        box.resumeOnce()
      }
    }
  }

  private func publishErrorUnlessBenignCancellation(_ error: Error, forceDisplay: Bool = false) {
    if Task.isCancelled || AbstandErrorFilter.isBenignCancellation(error) { return }
    // Kaltstart mit Cache: Hintergrund-Sync darf nicht stören — Pull-to-Refresh ausgenommen.
    if !forceDisplay, hasCachedBootstrapContent, AbstandErrorFilter.isTransientNetworkError(error) {
      return
    }
    errorMessage = error.localizedDescription
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

  /// Auto-Storefront: ABS-Server-Sprache, sonst Geräte-Region.
  func defaultPodcastDirectoryCountryCode() -> String {
    ABSPodcastCharts.countryCode(serverLanguage: serverSettings?.language)
  }

  func podcastDirectoryCountryCode() -> String {
    let raw =
      podcastDirectoryCountryOverride?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    if !raw.isEmpty { return raw }
    return defaultPodcastDirectoryCountryCode()
  }

  func syncPodcastDirectoryEffectiveCountry() {
    let code = podcastDirectoryCountryCode()
    guard podcastDirectoryEffectiveCountry != code else { return }
    podcastDirectoryEffectiveCountry = code
  }

  func setPodcastDirectoryCountryOverride(_ code: String) {
    let c = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !c.isEmpty else { return }
    let changed = podcastDirectoryCountryOverride != c
    podcastDirectoryCountryOverride = c
    syncPodcastDirectoryEffectiveCountry()
    guard changed else { return }
    podcastChartsHits = []
    podcastChartsLoadedCountry = nil
    podcastChartsLoadedGenreId = nil
  }

  func clearPodcastDirectoryCountryOverride() {
    guard podcastDirectoryCountryOverride != nil else { return }
    podcastDirectoryCountryOverride = nil
    syncPodcastDirectoryEffectiveCountry()
    podcastChartsHits = []
    podcastChartsLoadedCountry = nil
    podcastChartsLoadedGenreId = nil
  }

  func clearPodcastCharts() {
    podcastChartsHits = []
    podcastChartsLoading = false
    podcastChartsSelectedGenreId = nil
    podcastChartsLoadedCountry = nil
    podcastChartsLoadedGenreId = nil
  }

  func selectPodcastChartsCategory(genreId: Int?) {
    guard podcastChartsSelectedGenreId != genreId else { return }
    podcastChartsSelectedGenreId = genreId
    podcastChartsHits = []
    Task { await loadPodcastCharts(force: true) }
  }

  func loadPodcastCharts(force: Bool = false) async {
    guard isNetworkReachable else {
      errorMessage = "No network connection."
      return
    }
    if podcastChartsLoading { return }
    let country = podcastDirectoryCountryCode()
    let genreId = podcastChartsSelectedGenreId
    if !force,
      !podcastChartsHits.isEmpty,
      podcastChartsLoadedCountry == country,
      podcastChartsLoadedGenreId == genreId
    {
      return
    }
    podcastChartsLoading = true
    defer { podcastChartsLoading = false }
    do {
      podcastChartsHits = try await ABSPodcastCharts.fetchChart(
        country: country,
        genreId: genreId
      )
      podcastChartsLoadedCountry = country
      podcastChartsLoadedGenreId = genreId
      errorMessage = nil
    } catch {
      publishErrorUnlessBenignCancellation(error)
      podcastChartsHits = []
      podcastChartsLoadedCountry = nil
      podcastChartsLoadedGenreId = nil
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
      publishErrorUnlessBenignCancellation(error)
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
      publishErrorUnlessBenignCancellation(error)
      return false
    }
  }

  /// Entfernt eine Podcast-Sendung von der Bibliothek (`DELETE /api/items/:id`). Erfordert Lösch-Rechte auf dem Server.
  @discardableResult
  func removePodcastShowFromLibrary(showLibraryItemId: String) async -> Bool {
    guard let c = client else { return false }
    guard isNetworkReachable else {
      errorMessage = "No network connection."
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
      publishErrorUnlessBenignCancellation(error)
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
