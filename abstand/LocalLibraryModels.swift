import Foundation
import SwiftData

/// `@Model`-Typen der lokalen SwiftData-"Server-Kopie" (siehe Migrationsplan „SwiftData-Vollmigration“).
/// Rein persistenzintern — `ABS*`-Structs bleiben für Netzwerk/Anzeige bestehen, Mapping über
/// `init(_:)`/`to...()` auf jedem Typ. `AppModel` bleibt die `@Published`-Fassade, Views bleiben unangetastet.

/// Bootstrap-/Versionsinfo je Store — ein Datensatz pro Account-Store.
@Model
final class LocalStoreMeta {
  @Attribute(.unique) var id: String
  var schemaVersion: Int
  var lastOpenedAt: Date

  init(id: String = "meta", schemaVersion: Int = 2, lastOpenedAt: Date = Date()) {
    self.id = id
    self.schemaVersion = schemaVersion
    self.lastOpenedAt = lastOpenedAt
  }
}

/// Wiedergabe-/Lesefortschritt — 1:1-Ersatz für das ehemalige `progress.json`.
/// Unique-Key `progressLookupKey` = `AppModel.progressByItemId`-Schlüssel (`libraryItemId[-episodeId]`).
@Model
final class LocalProgress {
  @Attribute(.unique) var progressLookupKey: String
  var mediaProgressServerId: String?
  var libraryItemId: String
  var episodeId: String?
  var duration: Double
  var progress: Double
  var currentTime: Double
  var isFinished: Bool
  var lastUpdate: Int64?
  var ebookProgress: Double?
  var ebookLocation: String?

  init(_ p: ABSUserMediaProgress) {
    progressLookupKey = p.progressLookupKey
    mediaProgressServerId = p.mediaProgressServerId
    libraryItemId = p.libraryItemId
    episodeId = p.episodeId
    duration = p.duration
    progress = p.progress
    currentTime = p.currentTime
    isFinished = p.isFinished
    lastUpdate = p.lastUpdate
    ebookProgress = p.ebookProgress
    ebookLocation = p.ebookLocation
  }

  func toABSUserMediaProgress() -> ABSUserMediaProgress {
    ABSUserMediaProgress(
      mediaProgressServerId: mediaProgressServerId,
      libraryItemId: libraryItemId,
      episodeId: episodeId,
      duration: duration,
      progress: progress,
      currentTime: currentTime,
      isFinished: isFinished,
      lastUpdate: lastUpdate,
      ebookProgress: ebookProgress,
      ebookLocation: ebookLocation
    )
  }
}

/// Lesezeichen — 1:1-Ersatz für das ehemalige `bookmarks.json`.
/// Unique-Key wie `ABSAudioBookmark.id` (`"\(libraryItemId)-\(time)"`).
@Model
final class LocalBookmark {
  @Attribute(.unique) var id: String
  var libraryItemId: String
  var title: String
  var time: Int
  var createdAt: Int64?

  init(_ b: ABSAudioBookmark) {
    id = b.id
    libraryItemId = b.libraryItemId
    title = b.title
    time = b.time
    createdAt = b.createdAt
  }

  func toABSAudioBookmark() -> ABSAudioBookmark {
    ABSAudioBookmark(libraryItemId: libraryItemId, title: title, time: time, createdAt: createdAt)
  }
}

/// Genre-Statistik je Bibliothek — 1:1-Ersatz für `browseGenres/<libraryId>.json`.
/// Zusammengesetzter Unique-Key `"\(libraryId)|\(genre)"` (SwiftData-`#Predicate` erlaubt keine Tupel-Keys).
@Model
final class LocalGenreStat {
  @Attribute(.unique) var compositeKey: String
  var libraryId: String
  var genre: String
  var count: Int

  init(libraryId: String, stat: ABSLibraryGenreStat) {
    compositeKey = "\(libraryId)|\(stat.genre)"
    self.libraryId = libraryId
    genre = stat.genre
    count = stat.count
  }

  func toStat() -> ABSLibraryGenreStat {
    ABSLibraryGenreStat(genre: genre, count: count)
  }
}

/// Tag-Statistik je Bibliothek — 1:1-Ersatz für `browseTags/<libraryId>.json`.
@Model
final class LocalTagStat {
  @Attribute(.unique) var compositeKey: String
  var libraryId: String
  var tag: String
  var count: Int

  init(libraryId: String, stat: ABSLibraryTagStat) {
    compositeKey = "\(libraryId)|\(stat.tag)"
    self.libraryId = libraryId
    tag = stat.tag
    count = stat.count
  }

  func toStat() -> ABSLibraryTagStat {
    ABSLibraryTagStat(tag: tag, count: count)
  }
}

/// Merkt sich Sortierung/Gesamtzahl der zuletzt gecachten Autoren-Seite je Bibliothek — ersetzt den
/// SHA256-Slug-Ordner-Mechanismus (nur die zuletzt gesehene Sort-/Filter-Kombination bleibt offline nutzbar,
/// ein Wechsel der Sortierung erzwingt wie zuvor einen frischen Server-Fetch statt eines Cache-Hits).
@Model
final class LocalAuthorListState {
  @Attribute(.unique) var libraryId: String
  var sortField: String
  var descending: Bool
  var total: Int

  init(libraryId: String, sortField: String, descending: Bool, total: Int) {
    self.libraryId = libraryId
    self.sortField = sortField
    self.descending = descending
    self.total = total
  }
}

/// Autor einer Browse-Liste — 1:1-Ersatz für `browseAuthors/<libraryId>/<slug>/page_*.json`.
/// `sortRank` hält die vom Server gelieferte Reihenfolge der zuletzt gecachten Sortierung (siehe `LocalAuthorListState`).
/// Beschreibung bewusst nicht hier: Browse-`replaceAuthorsFirstPage` wipet diese Zeilen — siehe `LocalAuthorDetail`.
@Model
final class LocalAuthor {
  @Attribute(.unique) var id: String
  var libraryId: String
  var name: String
  var numBooks: Int?
  var imagePath: String?
  var sortRank: Int

  init(libraryId: String, item: ABSLibraryAuthorListItem, sortRank: Int) {
    id = item.id
    self.libraryId = libraryId
    name = item.name
    numBooks = item.numBooks
    imagePath = item.imagePath
    self.sortRank = sortRank
  }

  func toItem() -> ABSLibraryAuthorListItem {
    ABSLibraryAuthorListItem(id: id, name: name, numBooks: numBooks, imagePath: imagePath)
  }
}

/// Autor-Detail (Beschreibung) — getrennt von `LocalAuthor`, damit Browse-Listen-Reloads die Bio nicht verwerfen.
@Model
final class LocalAuthorDetail {
  @Attribute(.unique) var id: String
  var libraryId: String
  /// `description` kollidiert mit `CustomStringConvertible` — analog `LocalCollection.collectionDescription`.
  var authorDescription: String?

  init(id: String, libraryId: String, authorDescription: String?) {
    self.id = id
    self.libraryId = libraryId
    self.authorDescription = authorDescription
  }
}

/// Sprecher einer Browse-Liste — 1:1-Ersatz für `browseNarrators/<libraryId>.json` (+ Cover-Map als Feld
/// statt eigener Datei). Server liefert Sprecher unsortiert; Anzeige-Sortierung passiert clientseitig.
@Model
final class LocalNarrator {
  @Attribute(.unique) var id: String
  var libraryId: String
  var name: String
  var numBooks: Int?
  var coverItemId: String?

  init(libraryId: String, item: ABSLibraryNarratorListItem) {
    id = item.id
    self.libraryId = libraryId
    name = item.name
    numBooks = item.numBooks
  }

  func toItem() -> ABSLibraryNarratorListItem {
    ABSLibraryNarratorListItem(id: id, name: name, numBooks: numBooks)
  }
}

/// Bücher-/eBook-/Podcast-Show-"Server-Kopie" — 1:1-Ersatz für die Katalog-Slug-Seiten (`catalog/<libraryId>/<slug>/page_*.json`)
/// und für `bookFromLocalStore`. Eine Zeile pro `libraryItemId`, unabhängig davon über welchen Weg
/// (Katalog, Serie, Sammlung, eBook-Liste, …) sie zuletzt gesehen wurde — siehe Migrationsplan Prinzip 1+2.
/// Core-Felder für Sortierung/Anzeige echt, restliche Tiefe (Kapitel, Spuren, `ebookFile`, …) als Blob.
@Model
final class LocalBook {
  @Attribute(.unique) var id: String
  var libraryId: String?
  var title: String
  var authorName: String
  var addedAt: Date?
  var updatedAt: Date?
  var duration: Double
  var isUsableLibraryCatalogRow: Bool
  var isUsableEbookListRow: Bool
  /// Katalogfilter „eBook“ (reines eBook oder supplementäres eBook) — aus Server-Metadaten beim Upsert.
  var catalogHasEbook: Bool = false
  /// Hörbuch mit supplementärem eBook — Cover-Badge unten rechts.
  var catalogHasSupplementaryEbook: Bool = false
  /// eBooks-Browse „Supplementary“-Sektion (Schema V1, ungenutzt) — Spalte bleibt für leichte Migration.
  var isEbookSupplementary: Bool = false
  @Attribute(.externalStorage) var blob: Data
  /// Erweiterte Detail-Antwort (`GET /api/items/:id?expanded=1`, u. a. Beschreibung) — bewusst getrennt vom
  /// Katalog-Blob, damit ein späterer Katalog-/Browse-Reload (minified Listeneinträge ohne Beschreibung)
  /// diese einmal geladene Tiefe nicht wieder verwirft. Nur von `BookDetailView`/`PodcastEpisodeDetailView`
  /// gepflegt (`apply()`/Upserts der Listen-Endpunkte fassen dieses Feld nie an).
  @Attribute(.externalStorage) var detailBlob: Data?

  init(_ book: ABSBook) {
    id = book.id
    libraryId = book.libraryId
    title = book.displayTitle
    authorName = book.displayAuthorsCardLine
    addedAt = book.addedAt
    updatedAt = book.updatedAt
    duration = book.totalDuration
    isUsableLibraryCatalogRow = book.isUsableLibraryCatalogRow
    isUsableEbookListRow = book.isUsableEbookListRow
    catalogHasEbook = book.matchesBooksEbookCatalogFilter
    catalogHasSupplementaryEbook = book.isCatalogSupplementaryEbook
    isEbookSupplementary = false
    blob = (try? ABSJSON.encoder().encode(book)) ?? Data()
  }

  func apply(_ book: ABSBook) {
    libraryId = book.libraryId
    title = book.displayTitle
    authorName = book.displayAuthorsCardLine
    addedAt = book.addedAt
    updatedAt = book.updatedAt
    duration = book.totalDuration
    isUsableLibraryCatalogRow = book.isUsableLibraryCatalogRow
    isUsableEbookListRow = book.isUsableEbookListRow
    catalogHasEbook = book.matchesBooksEbookCatalogFilter || catalogHasEbook
    catalogHasSupplementaryEbook = book.isCatalogSupplementaryEbook || catalogHasSupplementaryEbook
    blob = (try? ABSJSON.encoder().encode(book)) ?? blob
  }

  func toABSBook() -> ABSBook? {
    try? ABSJSON.decoder().decode(ABSBook.self, from: blob)
  }

  func applyDetail(_ book: ABSBook) {
    detailBlob = try? ABSJSON.encoder().encode(book)
    catalogHasEbook = book.matchesBooksEbookCatalogFilter || catalogHasEbook
    catalogHasSupplementaryEbook = book.isCatalogSupplementaryEbook || catalogHasSupplementaryEbook
  }

  func toABSBookDetail() -> ABSBook? {
    guard let detailBlob else { return nil }
    return try? ABSJSON.decoder().decode(ABSBook.self, from: detailBlob)
  }
}

/// Merkt sich Filter/Sortierung/Gesamtzahl der zuletzt gecachten Katalogseite je Bibliothek — ersetzt den
/// SHA256-Slug-Ordner-Mechanismus (siehe `LocalAuthorListState`-Pendant aus Etappe 3, gleiches Prinzip:
/// nur die exakt zuletzt geladene Filter-/Sort-Kombination bleibt offline nutzbar).
@Model
final class LocalCatalogListState {
  @Attribute(.unique) var libraryId: String
  var sortField: String
  var ascending: Bool
  var filterKey: String?
  var total: Int

  init(libraryId: String, sortField: String, ascending: Bool, filterKey: String?, total: Int) {
    self.libraryId = libraryId
    self.sortField = sortField
    self.ascending = ascending
    self.filterKey = filterKey
    self.total = total
  }
}

/// Reihenfolge-Index für die zuletzt gecachte Katalogseite — getrennt von `LocalBook`, damit dieselbe
/// Buchzeile gleichzeitig von Serien/Sammlungen/eBook-Listen (spätere Etappen) referenziert werden kann,
/// ohne dass ein Katalog-Sortierwechsel deren Daten zerstört.
@Model
final class LocalCatalogEntry {
  @Attribute(.unique) var compositeKey: String
  var libraryId: String
  var rank: Int
  var bookId: String

  init(libraryId: String, rank: Int, bookId: String) {
    compositeKey = "\(libraryId)|\(rank)"
    self.libraryId = libraryId
    self.rank = rank
    self.bookId = bookId
  }
}

/// Legacy: früherer eBooks-Browse-Cache (Schema V1) — nur noch für Migration V1→V2.
@Model
final class LocalEbookListState {
  @Attribute(.unique) var libraryId: String
  var sortField: String
  var descending: Bool
  var total: Int

  init(libraryId: String, sortField: String, descending: Bool, total: Int) {
    self.libraryId = libraryId
    self.sortField = sortField
    self.descending = descending
    self.total = total
  }
}

/// Legacy: früherer eBooks-Browse-Reihenfolge-Index (Schema V1) — nur noch für Migration V1→V2.
@Model
final class LocalEbookEntry {
  @Attribute(.unique) var compositeKey: String
  var libraryId: String
  var rank: Int
  var bookId: String

  init(libraryId: String, rank: Int, bookId: String) {
    compositeKey = "\(libraryId)|\(rank)"
    self.libraryId = libraryId
    self.rank = rank
    self.bookId = bookId
  }
}

/// Merkt sich Sortierung/Gesamtzahl der zuletzt gecachten Serien-Seite je Bibliothek (analog `LocalAuthorListState`).
@Model
final class LocalSeriesListState {
  @Attribute(.unique) var libraryId: String
  var sortField: String
  var descending: Bool
  var total: Int

  init(libraryId: String, sortField: String, descending: Bool, total: Int) {
    self.libraryId = libraryId
    self.sortField = sortField
    self.descending = descending
    self.total = total
  }
}

/// Serie einer Browse-Liste — 1:1-Ersatz für `browseSeries/<libraryId>/<slug>/page_*.json`. Referenziert
/// Bücher nur über `bookIds` statt eingebetteter `ABSBook`-Kopien — die geteilte `LocalBook`-Tabelle liefert
/// die eigentlichen Daten (Migrationsplan Etappe 5).
@Model
final class LocalSeries {
  @Attribute(.unique) var id: String
  var libraryId: String
  var name: String
  var bookIds: [String]
  var sortRank: Int

  init(libraryId: String, item: ABSLibrarySeriesListItem, sortRank: Int) {
    id = item.id
    self.libraryId = libraryId
    name = item.name
    bookIds = (item.books ?? []).map(\.id)
    self.sortRank = sortRank
  }

  func toItem(booksById: [String: ABSBook]) -> ABSLibrarySeriesListItem {
    let books = bookIds.compactMap { booksById[$0] }
    return ABSLibrarySeriesListItem(id: id, name: name, books: books.isEmpty ? nil : books)
  }
}

/// Merkt sich Gesamtzahl der zuletzt gecachten Sammlungen je Bibliothek (Sammlungen kommen als ein
/// Voll-Fetch, keine echte Pagination — dient nur als Cache-Existenz-/Zähler-Marker).
@Model
final class LocalCollectionListState {
  @Attribute(.unique) var libraryId: String
  var total: Int

  init(libraryId: String, total: Int) {
    self.libraryId = libraryId
    self.total = total
  }
}

/// Sammlung — 1:1-Ersatz für `browseCollections/<libraryId>/all.json`. Referenziert Bücher nur über
/// `bookIds` statt eingebetteter `ABSBook`-Kopien (siehe `LocalSeries`).
@Model
final class LocalCollection {
  @Attribute(.unique) var id: String
  var libraryId: String
  var name: String
  var collectionDescription: String?
  var bookIds: [String]
  var createdAt: Double?
  var lastUpdate: Double?

  init(libraryId: String, item: ABSLibraryCollectionListItem) {
    id = item.id
    self.libraryId = libraryId
    name = item.name
    collectionDescription = item.description
    bookIds = (item.books ?? []).map(\.id)
    createdAt = item.createdAt
    lastUpdate = item.lastUpdate
  }

  func toItem(booksById: [String: ABSBook]) -> ABSLibraryCollectionListItem {
    let books = bookIds.compactMap { booksById[$0] }
    return ABSLibraryCollectionListItem(
      id: id, name: name, description: collectionDescription, books: books.isEmpty ? nil : books,
      createdAt: createdAt, lastUpdate: lastUpdate)
  }
}

/// Merkt sich Gesamtzahl/Paging-Modus der zuletzt gecachten Podcast-Folgenliste je Bibliothek — 1:1-Ersatz
/// für `podcastRecent/<libraryId>/page_*.json` + `episodes_fallback.json` (Migrationsplan Etappe 7).
/// `pagingFromRecentAPI = false` markiert den Expand-Fallback (`AppModel.loadPodcastEpisodesFallback`).
@Model
final class LocalPodcastEpisodeListState {
  @Attribute(.unique) var libraryId: String
  var total: Int
  var pagingFromRecentAPI: Bool

  init(libraryId: String, total: Int, pagingFromRecentAPI: Bool) {
    self.libraryId = libraryId
    self.total = total
    self.pagingFromRecentAPI = pagingFromRecentAPI
  }
}

/// Podcast-Folge aus `/recent-episodes` oder Expand-Fallback. Unique-Key `progressLookupKey`
/// (`"\(libraryItemId)-\(episodeId)"`, wie `AppModel.progressByItemId`). `rank` hält die zuletzt gesehene
/// Reihenfolge (Voll-Ersatz je Sync-Zyklus, analog `LocalProgress`/`LocalBookmark` aus Etappe 1).
@Model
final class LocalPodcastEpisode {
  @Attribute(.unique) var progressLookupKey: String
  var libraryId: String
  var libraryItemId: String
  var episodeId: String
  var episodeTitle: String
  var showTitle: String
  var authorLine: String
  var duration: Double
  var publishedAt: Int64?
  var rank: Int

  init(libraryId: String, item: ABSPodcastEpisodeListItem, rank: Int) {
    progressLookupKey = item.progressLookupKey
    self.libraryId = libraryId
    libraryItemId = item.libraryItemId
    episodeId = item.episodeId
    episodeTitle = item.episodeTitle
    showTitle = item.showTitle
    authorLine = item.authorLine
    duration = item.duration
    publishedAt = item.publishedAt
    self.rank = rank
  }

  func toItem() -> ABSPodcastEpisodeListItem {
    ABSPodcastEpisodeListItem(
      libraryItemId: libraryItemId, libraryId: libraryId, episodeId: episodeId, episodeTitle: episodeTitle,
      showTitle: showTitle, authorLine: authorLine, duration: duration, publishedAt: publishedAt)
  }
}

/// Merkt sich Sortierung/Gesamtzahl der zuletzt gecachten Podcast-Show-Liste je Bibliothek (analog
/// `LocalCatalogListState`) — kommt als ein Voll-Fetch (`limit=120`), keine echte Pagination.
@Model
final class LocalPodcastShowListState {
  @Attribute(.unique) var libraryId: String
  var sortField: String
  var ascending: Bool
  var total: Int

  init(libraryId: String, sortField: String, ascending: Bool, total: Int) {
    self.libraryId = libraryId
    self.sortField = sortField
    self.ascending = ascending
    self.total = total
  }
}

/// Reihenfolge-Index der zuletzt gecachten Podcast-Show-Liste — referenziert die geteilte `LocalBook`-Zeile
/// (Shows sind `ABSBook`-Items, Migrationsplan Etappe 7: „Shows nutzen `LocalBook` weiter“).
@Model
final class LocalPodcastShowEntry {
  @Attribute(.unique) var compositeKey: String
  var libraryId: String
  var rank: Int
  var bookId: String

  init(libraryId: String, rank: Int, bookId: String) {
    compositeKey = "\(libraryId)|\(rank)"
    self.libraryId = libraryId
    self.rank = rank
    self.bookId = bookId
  }
}

/// DTO für den `LocalHomeShelvesSnapshot`-Blob — spiegelt `ABSStartShelfSection` 1:1, da dieser Domain-Typ
/// selbst nicht `Codable` sein soll (nur für diese Persistenz relevant, siehe Migrationsplan Etappe 8).
private struct LocalHomeShelfSectionDTO: Codable {
  let id: String
  let category: String
  let displayTitle: String
  let books: [ABSBook]
  let podcastEpisodes: [ABSPodcastEpisodeListItem]
  let authors: [ABSAuthorShelfEntity]
  let series: [ABSLibrarySeriesListItem]

  init(_ section: ABSStartShelfSection) {
    id = section.id
    category = section.category
    displayTitle = section.displayTitle
    books = section.books
    podcastEpisodes = section.podcastEpisodes
    authors = section.authors
    series = section.series
  }

  func toSection() -> ABSStartShelfSection {
    ABSStartShelfSection(
      id: id, category: category, displayTitle: displayTitle, books: books, podcastEpisodes: podcastEpisodes,
      authors: authors, series: series)
  }
}

/// Home-Regale (`/personalized` + gemergtes Continue-Listening) — ein Voll-Snapshot pro Bibliothek, 1:1-Ersatz
/// für `homeContinue.json`/`personalized/<libraryId>.json` (Migrationsplan Etappe 8, Grundprinzip 8). Regale
/// werden nie einzeln gefiltert/sortiert — daher als ein Blob statt zerlegter Relationen (Grundprinzip 2).
@Model
final class LocalHomeShelvesSnapshot {
  @Attribute(.unique) var libraryId: String
  @Attribute(.externalStorage) var blob: Data

  init(libraryId: String, sections: [ABSStartShelfSection]) {
    self.libraryId = libraryId
    blob = (try? ABSJSON.encoder().encode(sections.map(LocalHomeShelfSectionDTO.init))) ?? Data()
  }

  func apply(_ sections: [ABSStartShelfSection]) {
    blob = (try? ABSJSON.encoder().encode(sections.map(LocalHomeShelfSectionDTO.init))) ?? blob
  }

  func toSections() -> [ABSStartShelfSection]? {
    guard let dtos = try? ABSJSON.decoder().decode([LocalHomeShelfSectionDTO].self, from: blob) else { return nil }
    return dtos.map { $0.toSection() }
  }
}

/// Lokal injizierte eBook-„Continue reading“/„Continue series“-Regalzeilen (aus Readium-Lesefortschritt,
/// nicht vom Server) — 1:1-Ersatz für `ebookContinueShelves/<libraryId>.json`. `kind` unterscheidet die
/// beiden Regale, `rank` hält die zuletzt berechnete Reihenfolge. Referenziert die geteilte `LocalBook`-Zeile.
@Model
final class LocalEbookContinueEntry {
  @Attribute(.unique) var compositeKey: String
  var libraryId: String
  var kind: String
  var rank: Int
  var bookId: String

  init(libraryId: String, kind: String, rank: Int, bookId: String) {
    compositeKey = "\(libraryId)|\(kind)|\(rank)"
    self.libraryId = libraryId
    self.kind = kind
    self.rank = rank
    self.bookId = bookId
  }
}

/// Rohantwort von `/api/me/listening-stats` — 1:1-Ersatz für `listeningStats.response.json`. Ein Datensatz
/// pro Account-Store (kein Bibliotheks-Bezug) — `fetchedAt` ersetzt die bisherige Datei-Modifikationszeit.
@Model
final class LocalListeningStatsSnapshot {
  @Attribute(.unique) var id: String
  var fetchedAt: Date
  @Attribute(.externalStorage) var blob: Data

  init(rawData: Data, fetchedAt: Date = Date()) {
    id = "stats"
    self.fetchedAt = fetchedAt
    blob = rawData
  }
}

/// Level-Achievement — 1:1-Ersatz für `listeningAchievements.snapshot.json`. Unique-Key `kind.rawValue`
/// (Migrationsplan Grundprinzip 3), eine Zeile je `ListeningAchievementKind`.
@Model
final class LocalAchievementState {
  @Attribute(.unique) var kind: String
  var currentValue: Int
  var savedAt: Date?

  init(kind: ListeningAchievementKind, currentValue: Int, savedAt: Date?) {
    self.kind = kind.rawValue
    self.currentValue = currentValue
    self.savedAt = savedAt
  }
}

/// Historisches Einmal-Achievement-Modell (Schema V1–V3). Ab V4 nicht mehr im aktuellen Schema;
/// Klasse bleibt für VersionedSchema-/Migrationspfade erhalten.
@Model
final class LocalOneTimeAchievementState {
  @Attribute(.unique) var kind: String
  var isUnlocked: Bool
  var savedAt: Date?

  init(kind: String, isUnlocked: Bool, savedAt: Date?) {
    self.kind = kind
    self.isUnlocked = isUnlocked
    self.savedAt = savedAt
  }
}

/// Account-weite Bibliotheksliste (`GET /api/libraries`) — ein Blob pro Store, analog `LocalListeningStatsSnapshot`.
@Model
final class LocalLibrariesSnapshot {
  @Attribute(.unique) var id: String
  var fetchedAt: Date
  @Attribute(.externalStorage) var blob: Data

  init(libraries: [ABSLibrary], fetchedAt: Date = Date()) {
    id = "libraries"
    self.fetchedAt = fetchedAt
    blob = (try? ABSJSON.encoder().encode(libraries)) ?? Data()
  }

  func apply(_ libraries: [ABSLibrary]) {
    blob = (try? ABSJSON.encoder().encode(libraries)) ?? blob
    fetchedAt = Date()
  }

  func toLibraries() -> [ABSLibrary]? {
    try? ABSJSON.decoder().decode([ABSLibrary].self, from: blob)
  }
}

/// Hör-Sitzungen je Medium — Key `libraryItemId|episodeId` (episodeId leer bei Büchern).
@Model
final class LocalListeningSessionsSnapshot {
  @Attribute(.unique) var compositeKey: String
  var libraryItemId: String
  var episodeId: String
  var fetchedAt: Date
  @Attribute(.externalStorage) var blob: Data

  init(libraryItemId: String, episodeId: String?, sessions: [ABSListeningSession], fetchedAt: Date = Date()) {
    let ep = (episodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    self.libraryItemId = libraryItemId
    self.episodeId = ep
    compositeKey = Self.makeKey(libraryItemId: libraryItemId, episodeId: ep)
    self.fetchedAt = fetchedAt
    blob = (try? ABSJSON.encoder().encode(sessions.map(LocalListeningSessionDTO.init))) ?? Data()
  }

  func apply(_ sessions: [ABSListeningSession]) {
    blob = (try? ABSJSON.encoder().encode(sessions.map(LocalListeningSessionDTO.init))) ?? blob
    fetchedAt = Date()
  }

  func toSessions() -> [ABSListeningSession]? {
    guard let dtos = try? ABSJSON.decoder().decode([LocalListeningSessionDTO].self, from: blob) else {
      return nil
    }
    return dtos.map { $0.toSession() }
  }

  static func makeKey(libraryItemId: String, episodeId: String?) -> String {
    let lid = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    let ep = (episodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(lid)|\(ep)"
  }
}

/// Codable-Spiegel von `ABSListeningSession` (API-Typ ist nur `Decodable` mit Custom-Init).
struct LocalListeningSessionDTO: Codable {
  let id: String
  let libraryItemId: String
  let bookId: String?
  let episodeId: String?
  let duration: Double
  let startTime: Double
  let currentTime: Double
  let timeListening: Int
  let startedAt: Int64
  let updatedAt: Int64

  init(_ session: ABSListeningSession) {
    id = session.id
    libraryItemId = session.libraryItemId
    bookId = session.bookId
    episodeId = session.episodeId
    duration = session.duration
    startTime = session.startTime
    currentTime = session.currentTime
    timeListening = session.timeListening
    startedAt = session.startedAt
    updatedAt = session.updatedAt
  }

  func toSession() -> ABSListeningSession {
    ABSListeningSession(
      id: id,
      libraryItemId: libraryItemId,
      bookId: bookId,
      episodeId: episodeId,
      duration: duration,
      startTime: startTime,
      currentTime: currentTime,
      timeListening: timeListening,
      startedAt: startedAt,
      updatedAt: updatedAt
    )
  }
}

/// Rohantwort von `POST /api/podcasts/feed` je Sendung — 1:1-Ersatz für den bisherigen In-Memory-RSS-Cache.
@Model
final class LocalPodcastRssFeedSnapshot {
  @Attribute(.unique) var showId: String
  var fetchedAt: Date
  @Attribute(.externalStorage) var blob: Data

  init(showId: String, rawFeedData: Data, fetchedAt: Date = Date()) {
    self.showId = showId
    self.fetchedAt = fetchedAt
    blob = rawFeedData
  }

  func apply(rawFeedData: Data) {
    blob = rawFeedData
    fetchedAt = Date()
  }
}

// MARK: - Schema-Versionen (SwiftData)

private enum LocalLibrarySchemaModels {
  /// Gemeinsame Modelle ohne Einmal-Achievements (ab Schema V4).
  static let coreWithoutOneTime: [any PersistentModel.Type] = [
    LocalStoreMeta.self, LocalProgress.self, LocalBookmark.self,
    LocalGenreStat.self, LocalTagStat.self,
    LocalAuthorListState.self, LocalAuthor.self, LocalNarrator.self,
    LocalBook.self, LocalCatalogListState.self, LocalCatalogEntry.self,
    LocalSeriesListState.self, LocalSeries.self,
    LocalCollectionListState.self, LocalCollection.self,
    LocalPodcastEpisodeListState.self, LocalPodcastEpisode.self,
    LocalPodcastShowListState.self, LocalPodcastShowEntry.self,
    LocalHomeShelvesSnapshot.self, LocalEbookContinueEntry.self,
    LocalListeningStatsSnapshot.self, LocalAchievementState.self,
  ]

  /// Modelle bis Schema V3 (inkl. Einmal-Achievements).
  static let coreThroughV3: [any PersistentModel.Type] {
    coreWithoutOneTime + [LocalOneTimeAchievementState.self]
  }

  static let v1BrowseEbooks: [any PersistentModel.Type] = [
    LocalEbookListState.self, LocalEbookEntry.self,
  ]

  /// Additive Local-DB-First-Lücken: Libraries, Sessions, Author-Bio, Podcast-RSS.
  static let v3LocalFirstGaps: [any PersistentModel.Type] = [
    LocalAuthorDetail.self,
    LocalLibrariesSnapshot.self,
    LocalListeningSessionsSnapshot.self,
    LocalPodcastRssFeedSnapshot.self,
  ]
}

/// Produktionsschema vor Entfernung des eBooks-Browse-Caches (identisch zur bisher unversionierten DB).
enum LocalLibrarySchemaV1: VersionedSchema {
  static var versionIdentifier = Schema.Version(1, 0, 0)

  static var models: [any PersistentModel.Type] {
    LocalLibrarySchemaModels.coreThroughV3 + LocalLibrarySchemaModels.v1BrowseEbooks
  }
}

/// Schema nach Entfernung der eBooks-Browse-Tabellen; Lesefortschritt über `LocalEbookContinueEntry`.
enum LocalLibrarySchemaV2: VersionedSchema {
  static var versionIdentifier = Schema.Version(2, 0, 0)

  static var models: [any PersistentModel.Type] {
    LocalLibrarySchemaModels.coreThroughV3
  }
}

/// Libraries-/Sessions-/Author-Detail-/RSS-Snapshots für Local-DB-First.
enum LocalLibrarySchemaV3: VersionedSchema {
  static var versionIdentifier = Schema.Version(3, 0, 0)

  static var models: [any PersistentModel.Type] {
    LocalLibrarySchemaModels.coreThroughV3 + LocalLibrarySchemaModels.v3LocalFirstGaps
  }
}

/// Aktuelles Schema — ohne Einmal-Achievement-Tabelle (Milestones entfernt).
enum LocalLibrarySchemaV4: VersionedSchema {
  static var versionIdentifier = Schema.Version(4, 0, 0)

  static var models: [any PersistentModel.Type] {
    LocalLibrarySchemaModels.coreWithoutOneTime + LocalLibrarySchemaModels.v3LocalFirstGaps
  }
}

enum LocalLibraryMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [
      LocalLibrarySchemaV1.self, LocalLibrarySchemaV2.self, LocalLibrarySchemaV3.self,
      LocalLibrarySchemaV4.self,
    ]
  }

  static var stages: [MigrationStage] {
    [migrateV1toV2, migrateV2toV3, migrateV3toV4]
  }

  static let migrateV1toV2 = MigrationStage.custom(
    fromVersion: LocalLibrarySchemaV1.self,
    toVersion: LocalLibrarySchemaV2.self,
    willMigrate: { context in
      try context.delete(model: LocalEbookEntry.self)
      try context.delete(model: LocalEbookListState.self)
      let supplementaryBooks = try context.fetch(
        FetchDescriptor<LocalBook>(predicate: #Predicate { $0.isEbookSupplementary == true })
      )
      for book in supplementaryBooks {
        book.isEbookSupplementary = false
      }
      try context.save()
    },
    didMigrate: { context in
      let descriptor = FetchDescriptor<LocalStoreMeta>()
      if let meta = try context.fetch(descriptor).first {
        meta.schemaVersion = 2
      } else {
        context.insert(LocalStoreMeta(schemaVersion: 2))
      }
      try context.save()
    }
  )

  /// Rein additiv (neue Tabellen) — lightweight, kein Datenverlust.
  static let migrateV2toV3 = MigrationStage.lightweight(
    fromVersion: LocalLibrarySchemaV2.self,
    toVersion: LocalLibrarySchemaV3.self
  )

  static let migrateV3toV4 = MigrationStage.custom(
    fromVersion: LocalLibrarySchemaV3.self,
    toVersion: LocalLibrarySchemaV4.self,
    willMigrate: { context in
      try context.delete(model: LocalOneTimeAchievementState.self)
      try context.save()
    },
    didMigrate: { context in
      let descriptor = FetchDescriptor<LocalStoreMeta>()
      if let meta = try context.fetch(descriptor).first {
        meta.schemaVersion = 4
      } else {
        context.insert(LocalStoreMeta(schemaVersion: 4))
      }
      try context.save()
    }
  )
}

enum LocalLibrarySchema {
  static var current: Schema {
    Schema(versionedSchema: LocalLibrarySchemaV4.self)
  }

  /// Logische Meta-Version in `LocalStoreMeta` — Backfill der eBook-Katalog-Flags (`catalogHasEbook`, …).
  static let ebookCatalogFlagsMetaVersion = 3
}
