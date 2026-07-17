import CryptoKit
import Foundation
import SwiftData
import os

/// SwiftData-Persistenzschicht ("Server-Kopie") — siehe Migrationsplan „SwiftData-Vollmigration“.
/// `@Model`-Typen (siehe `LocalLibraryModels.swift`) sind rein persistenzintern;
/// `AppModel` bleibt die zentrale `@Published`-Fassade, Views bleiben unangetastet.

/// Persistenz-Actor für die lokale Server-Kopie. Schreiben/Sync und große Fetches laufen hier statt auf dem
/// Main-`ModelContext` (analog zum `Task.detached`-Muster für das bisherige JSON-I/O). Domänen-Methoden
/// (Progress, Katalog, Browse-Listen, …) kommen etappenweise dazu.
@ModelActor
actor LocalLibraryStore {
  /// Beim Öffnen eines Stores Meta-Eintrag anlegen/aktualisieren — vor allem ein einfacher Existenz-/Schreibtest.
  func markOpened() {
    let descriptor = FetchDescriptor<LocalStoreMeta>()
    let meta: LocalStoreMeta
    if let existing = try? modelContext.fetch(descriptor).first {
      existing.lastOpenedAt = Date()
      meta = existing
    } else {
      let row = LocalStoreMeta()
      modelContext.insert(row)
      meta = row
    }
    backfillEbookCatalogFlagsIfNeeded(meta: meta)
    try? modelContext.save()
  }

  /// Einmalig nach Update: `catalogHasEbook`/`catalogHasSupplementaryEbook` aus gespeichertem Blob berechnen.
  private func backfillEbookCatalogFlagsIfNeeded(meta: LocalStoreMeta) {
    guard meta.schemaVersion < LocalLibrarySchema.ebookCatalogFlagsMetaVersion else { return }
    let rows = (try? modelContext.fetch(FetchDescriptor<LocalBook>())) ?? []
    for row in rows {
      if let book = row.toABSBook() {
        row.catalogHasEbook = book.matchesBooksEbookCatalogFilter || row.catalogHasEbook
        row.catalogHasSupplementaryEbook = book.isCatalogSupplementaryEbook || row.catalogHasSupplementaryEbook
      } else if let detail = row.toABSBookDetail() {
        row.catalogHasEbook = detail.matchesBooksEbookCatalogFilter || row.catalogHasEbook
        row.catalogHasSupplementaryEbook = detail.isCatalogSupplementaryEbook || row.catalogHasSupplementaryEbook
      }
    }
    meta.schemaVersion = LocalLibrarySchema.ebookCatalogFlagsMetaVersion
  }

  // MARK: - Progress

  /// Komplett-Ersatz aller Progress-Zeilen — spiegelt das bisherige `saveProgress` (ganzes Array pro Schreibvorgang).
  func replaceAllProgress(_ list: [ABSUserMediaProgress]) throws {
    try modelContext.delete(model: LocalProgress.self)
    for p in list {
      modelContext.insert(LocalProgress(p))
    }
    try modelContext.save()
  }

  func fetchAllProgress() throws -> [ABSUserMediaProgress] {
    try modelContext.fetch(FetchDescriptor<LocalProgress>()).map { $0.toABSUserMediaProgress() }
  }

  // MARK: - Bookmarks

  /// Komplett-Ersatz aller Lesezeichen — spiegelt das bisherige `saveBookmarks` (ganzes Array pro Schreibvorgang).
  func replaceAllBookmarks(_ list: [ABSAudioBookmark]) throws {
    try modelContext.delete(model: LocalBookmark.self)
    for b in list {
      modelContext.insert(LocalBookmark(b))
    }
    try modelContext.save()
  }

  func fetchAllBookmarks() throws -> [ABSAudioBookmark] {
    try modelContext.fetch(FetchDescriptor<LocalBookmark>()).map { $0.toABSAudioBookmark() }
  }

  // MARK: - Browse-Genres / Browse-Tags

  func replaceGenreStats(libraryId: String, stats: [ABSLibraryGenreStat]) throws {
    let predicate = #Predicate<LocalGenreStat> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      modelContext.delete(existing)
    }
    for stat in stats {
      modelContext.insert(LocalGenreStat(libraryId: libraryId, stat: stat))
    }
    try modelContext.save()
  }

  func replaceTagStats(libraryId: String, stats: [ABSLibraryTagStat]) throws {
    let predicate = #Predicate<LocalTagStat> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      modelContext.delete(existing)
    }
    for stat in stats {
      modelContext.insert(LocalTagStat(libraryId: libraryId, stat: stat))
    }
    try modelContext.save()
  }

  // MARK: - Browse-Autoren

  /// Reset-Fetch (Seite 0): alte Zeilen der Bibliothek weg, neue Seite mit frischem `sortRank` ab 0.
  func replaceAuthorsFirstPage(
    libraryId: String, sortField: String, descending: Bool, total: Int, items: [ABSLibraryAuthorListItem]
  ) throws {
    let predicate = #Predicate<LocalAuthor> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      modelContext.delete(existing)
    }
    for (idx, item) in items.enumerated() {
      modelContext.insert(LocalAuthor(libraryId: libraryId, item: item, sortRank: idx))
    }
    try upsertAuthorListState(libraryId: libraryId, sortField: sortField, descending: descending, total: total)
    try modelContext.save()
  }

  /// Folgeseite: an bestehenden `sortRank` anhängen (kein Wipe).
  func appendAuthorsPage(libraryId: String, total: Int, items: [ABSLibraryAuthorListItem]) throws {
    let predicate = #Predicate<LocalAuthor> { $0.libraryId == libraryId }
    let existingCount = try modelContext.fetchCount(FetchDescriptor(predicate: predicate))
    for (idx, item) in items.enumerated() {
      modelContext.insert(LocalAuthor(libraryId: libraryId, item: item, sortRank: existingCount + idx))
    }
    if let state = try fetchAuthorListStateRow(libraryId: libraryId) {
      state.total = total
    }
    try modelContext.save()
  }

  private func upsertAuthorListState(libraryId: String, sortField: String, descending: Bool, total: Int) throws {
    if let state = try fetchAuthorListStateRow(libraryId: libraryId) {
      state.sortField = sortField
      state.descending = descending
      state.total = total
    } else {
      modelContext.insert(
        LocalAuthorListState(libraryId: libraryId, sortField: sortField, descending: descending, total: total))
    }
  }

  private func fetchAuthorListStateRow(libraryId: String) throws -> LocalAuthorListState? {
    let predicate = #Predicate<LocalAuthorListState> { $0.libraryId == libraryId }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  /// `nil`, wenn kein Cache oder die angefragte Sortierung von der zuletzt gecachten abweicht (wie zuvor ein
  /// Slug-Cache-Miss — nur die exakt zuletzt geladene Sort-/Filter-Kombination bleibt offline nutzbar).
  func fetchAuthors(
    libraryId: String, sortField: String, descending: Bool
  ) throws -> (items: [ABSLibraryAuthorListItem], total: Int, nextPage: Int)? {
    guard let state = try fetchAuthorListStateRow(libraryId: libraryId),
      state.sortField == sortField, state.descending == descending
    else { return nil }
    let predicate = #Predicate<LocalAuthor> { $0.libraryId == libraryId }
    let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.sortRank)])
    let rows = try modelContext.fetch(descriptor)
    guard !rows.isEmpty else { return nil }
    let items = rows.map { $0.toItem() }
    return (items, state.total, (items.count + 49) / 50)
  }

  // MARK: - Browse-Sprecher

  func replaceNarrators(libraryId: String, items: [ABSLibraryNarratorListItem]) throws {
    let predicate = #Predicate<LocalNarrator> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      modelContext.delete(existing)
    }
    for item in items {
      modelContext.insert(LocalNarrator(libraryId: libraryId, item: item))
    }
    try modelContext.save()
  }

  /// Cover-Bild-Zuordnung nachträglich befüllen (`fillBrowseNarratorCoverItemIds`) — Name ist der Schlüssel,
  /// wie zuvor in der separaten `NarratorCoverMapFile`.
  func updateNarratorCoverMap(libraryId: String, coverItemIdByName: [String: String]) throws {
    let predicate = #Predicate<LocalNarrator> { $0.libraryId == libraryId }
    for row in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      if let coverItemId = coverItemIdByName[row.name] {
        row.coverItemId = coverItemId
      }
    }
    try modelContext.save()
  }

  func fetchNarrators(libraryId: String) throws -> (narrators: [ABSLibraryNarratorListItem], coverMap: [String: String])? {
    let predicate = #Predicate<LocalNarrator> { $0.libraryId == libraryId }
    let rows = try modelContext.fetch(FetchDescriptor(predicate: predicate))
    guard !rows.isEmpty else { return nil }
    var coverMap: [String: String] = [:]
    for row in rows {
      if let coverItemId = row.coverItemId { coverMap[row.name] = coverItemId }
    }
    return (rows.map { $0.toItem() }, coverMap)
  }

  // MARK: - Browse-Serien

  /// Reset-Fetch (Seite 0): alte Zeilen der Bibliothek weg, neue Seite mit frischem `sortRank` ab 0.
  /// Eingebettete Bücher wandern per Upsert in die geteilte `LocalBook`-Tabelle.
  func replaceSeriesFirstPage(
    libraryId: String, sortField: String, descending: Bool, total: Int, items: [ABSLibrarySeriesListItem]
  ) throws {
    let predicate = #Predicate<LocalSeries> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      modelContext.delete(existing)
    }
    for item in items {
      try upsertBooks(item.books ?? [])
    }
    for (idx, item) in items.enumerated() {
      modelContext.insert(LocalSeries(libraryId: libraryId, item: item, sortRank: idx))
    }
    try upsertSeriesListState(libraryId: libraryId, sortField: sortField, descending: descending, total: total)
    try modelContext.save()
  }

  /// Folgeseite: an bestehenden `sortRank` anhängen (kein Wipe).
  func appendSeriesPage(libraryId: String, total: Int, items: [ABSLibrarySeriesListItem]) throws {
    let predicate = #Predicate<LocalSeries> { $0.libraryId == libraryId }
    let existingCount = try modelContext.fetchCount(FetchDescriptor(predicate: predicate))
    for item in items {
      try upsertBooks(item.books ?? [])
    }
    for (idx, item) in items.enumerated() {
      modelContext.insert(LocalSeries(libraryId: libraryId, item: item, sortRank: existingCount + idx))
    }
    if let state = try fetchSeriesListStateRow(libraryId: libraryId) {
      state.total = total
    }
    try modelContext.save()
  }

  private func upsertSeriesListState(libraryId: String, sortField: String, descending: Bool, total: Int) throws {
    if let state = try fetchSeriesListStateRow(libraryId: libraryId) {
      state.sortField = sortField
      state.descending = descending
      state.total = total
    } else {
      modelContext.insert(
        LocalSeriesListState(libraryId: libraryId, sortField: sortField, descending: descending, total: total))
    }
  }

  private func fetchSeriesListStateRow(libraryId: String) throws -> LocalSeriesListState? {
    let predicate = #Predicate<LocalSeriesListState> { $0.libraryId == libraryId }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  /// `nil`, wenn kein Cache oder die angefragte Sortierung von der zuletzt gecachten abweicht.
  func fetchSeries(
    libraryId: String, sortField: String, descending: Bool
  ) throws -> (items: [ABSLibrarySeriesListItem], total: Int, nextPage: Int)? {
    LocalLibraryQueries.series(
      context: modelContext, libraryId: libraryId, sortField: sortField, descending: descending)
  }

  // MARK: - Browse-Sammlungen

  /// Voll-Ersatz (Sammlungen kommen als ein Voll-Fetch ohne echte Pagination).
  func replaceCollections(libraryId: String, total: Int, items: [ABSLibraryCollectionListItem]) throws {
    let predicate = #Predicate<LocalCollection> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      modelContext.delete(existing)
    }
    for item in items {
      try upsertBooks(item.books ?? [])
      modelContext.insert(LocalCollection(libraryId: libraryId, item: item))
    }
    var descriptor = FetchDescriptor<LocalCollectionListState>(predicate: #Predicate { $0.libraryId == libraryId })
    descriptor.fetchLimit = 1
    if let state = try modelContext.fetch(descriptor).first {
      state.total = total
    } else {
      modelContext.insert(LocalCollectionListState(libraryId: libraryId, total: total))
    }
    try modelContext.save()
  }

  func fetchCollections(libraryId: String) -> (items: [ABSLibraryCollectionListItem], total: Int)? {
    LocalLibraryQueries.collections(context: modelContext, libraryId: libraryId)
  }

  // MARK: - Podcast-Folgen

  /// Voll-Ersatz je Sync-Zyklus (analog `replaceAllProgress`/`replaceAllBookmarks`) — die in-memory Liste in
  /// `AppModel.podcastEpisodes` entsteht ohnehin bei jedem Reset/Append-Schritt per Neuzuweisung (Dedupe).
  func replacePodcastEpisodes(
    libraryId: String, total: Int, pagingFromRecentAPI: Bool, items: [ABSPodcastEpisodeListItem]
  ) throws {
    let predicate = #Predicate<LocalPodcastEpisode> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      modelContext.delete(existing)
    }
    for (idx, item) in items.enumerated() {
      modelContext.insert(LocalPodcastEpisode(libraryId: libraryId, item: item, rank: idx))
    }
    var stateDescriptor = FetchDescriptor<LocalPodcastEpisodeListState>(
      predicate: #Predicate { $0.libraryId == libraryId })
    stateDescriptor.fetchLimit = 1
    if let state = try modelContext.fetch(stateDescriptor).first {
      state.total = total
      state.pagingFromRecentAPI = pagingFromRecentAPI
    } else {
      modelContext.insert(
        LocalPodcastEpisodeListState(libraryId: libraryId, total: total, pagingFromRecentAPI: pagingFromRecentAPI))
    }
    try modelContext.save()
  }

  func fetchPodcastEpisodes(
    libraryId: String
  ) -> (items: [ABSPodcastEpisodeListItem], total: Int, pagingFromRecentAPI: Bool)? {
    LocalLibraryQueries.podcastEpisodes(context: modelContext, libraryId: libraryId)
  }

  // MARK: - Podcast-Shows

  /// Voll-Ersatz je Fetch (kommt als ein `limit=120`-Request ohne echte Pagination) — Shows selbst landen
  /// in der geteilten `LocalBook`-Tabelle (Migrationsplan Etappe 7).
  func replacePodcastShows(libraryId: String, sortField: String, ascending: Bool, items: [ABSBook]) throws {
    let entryPredicate = #Predicate<LocalPodcastShowEntry> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: entryPredicate)) {
      modelContext.delete(existing)
    }
    try upsertBooks(items)
    for (idx, item) in items.enumerated() {
      modelContext.insert(LocalPodcastShowEntry(libraryId: libraryId, rank: idx, bookId: item.id))
    }
    var stateDescriptor = FetchDescriptor<LocalPodcastShowListState>(
      predicate: #Predicate { $0.libraryId == libraryId })
    stateDescriptor.fetchLimit = 1
    if let state = try modelContext.fetch(stateDescriptor).first {
      state.sortField = sortField
      state.ascending = ascending
      state.total = items.count
    } else {
      modelContext.insert(
        LocalPodcastShowListState(libraryId: libraryId, sortField: sortField, ascending: ascending, total: items.count))
    }
    try modelContext.save()
  }

  func fetchPodcastShows(libraryId: String, sortField: String, ascending: Bool) -> [ABSBook]? {
    LocalLibraryQueries.podcastShows(
      context: modelContext, libraryId: libraryId, sortField: sortField, ascending: ascending)
  }

  // MARK: - Bücher (Katalog + geteilte "Server-Kopie" für Serien/Sammlungen/eBooks/Suche)

  /// Insert-or-update je `id` — teilt sich `LocalBook` mit allen Domänen, die Bücher referenzieren.
  func upsertBooks(_ items: [ABSBook]) throws {
    guard !items.isEmpty else { return }
    let ids = items.map(\.id)
    let existing = try modelContext.fetch(FetchDescriptor<LocalBook>(predicate: #Predicate { ids.contains($0.id) }))
    var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
    for item in items {
      if let row = byId[item.id] {
        row.apply(item)
      } else {
        let row = LocalBook(item)
        modelContext.insert(row)
        byId[item.id] = row
      }
    }
    try modelContext.save()
  }

  /// eBook-Katalog — Flags explizit setzen (alte Browse-Logik: rein + supplementär).
  func upsertEbookCatalogBooks(pure: [ABSBook], supplementary: [ABSBook]) throws {
    let allIds = (pure + supplementary).map(\.id)
    guard !allIds.isEmpty else { return }
    let existing = try modelContext.fetch(
      FetchDescriptor<LocalBook>(predicate: #Predicate { allIds.contains($0.id) }))
    var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
    for item in pure {
      if let row = byId[item.id] {
        row.apply(item)
        row.catalogHasEbook = true
      } else {
        let row = LocalBook(item)
        row.catalogHasEbook = true
        modelContext.insert(row)
        byId[item.id] = row
      }
    }
    for item in supplementary {
      if let row = byId[item.id] {
        row.apply(item)
        row.catalogHasEbook = true
        row.catalogHasSupplementaryEbook = true
      } else {
        let row = LocalBook(item)
        row.catalogHasEbook = true
        row.catalogHasSupplementaryEbook = true
        modelContext.insert(row)
        byId[item.id] = row
      }
    }
    try modelContext.save()
  }

  func fetchEbookCatalogBooks(libraryId: String) -> [ABSBook] {
    LocalLibraryQueries.ebookCatalogBooks(context: modelContext, libraryId: libraryId)
  }

  func fetchBook(id: String) -> ABSBook? {
    LocalLibraryQueries.book(context: modelContext, id: id)
  }

  /// Entfernt die lokale Buchzeile (Katalog- + Detail-Blob) und Katalog-Einträge nach Server-Löschung.
  func deleteBook(id: String) throws {
    let bid = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bid.isEmpty else { return }
    var bookDescriptor = FetchDescriptor<LocalBook>(predicate: #Predicate { $0.id == bid })
    bookDescriptor.fetchLimit = 1
    if let row = try modelContext.fetch(bookDescriptor).first {
      modelContext.delete(row)
    }
    let catalogEntries = try modelContext.fetch(
      FetchDescriptor<LocalCatalogEntry>(predicate: #Predicate { $0.bookId == bid })
    )
    var touchedLibraries = Set<String>()
    for entry in catalogEntries {
      touchedLibraries.insert(entry.libraryId)
      modelContext.delete(entry)
    }
    for libraryId in touchedLibraries {
      var stateDescriptor = FetchDescriptor<LocalCatalogListState>(
        predicate: #Predicate { $0.libraryId == libraryId })
      stateDescriptor.fetchLimit = 1
      if let state = try modelContext.fetch(stateDescriptor).first {
        state.total = max(0, state.total - 1)
      }
    }
    try modelContext.save()
  }

  /// Erweiterte Detail-Antwort (inkl. Beschreibung) separat vom Katalog-Blob sichern — siehe `LocalBook.detailBlob`.
  func upsertBookDetail(_ book: ABSBook) throws {
    let bid = book.id
    var descriptor = FetchDescriptor<LocalBook>(predicate: #Predicate { $0.id == bid })
    descriptor.fetchLimit = 1
    if let row = try modelContext.fetch(descriptor).first {
      row.applyDetail(book)
    } else {
      let row = LocalBook(book)
      row.applyDetail(book)
      modelContext.insert(row)
    }
    try modelContext.save()
  }

  func fetchBookDetail(id: String) -> ABSBook? {
    LocalLibraryQueries.bookDetail(context: modelContext, id: id)
  }

  private func upsertCatalogListState(
    libraryId: String, sortField: String, ascending: Bool, filterKey: String?, total: Int
  ) throws {
    var descriptor = FetchDescriptor<LocalCatalogListState>(predicate: #Predicate { $0.libraryId == libraryId })
    descriptor.fetchLimit = 1
    if let state = try modelContext.fetch(descriptor).first {
      state.sortField = sortField
      state.ascending = ascending
      state.filterKey = filterKey
      state.total = total
    } else {
      modelContext.insert(
        LocalCatalogListState(
          libraryId: libraryId, sortField: sortField, ascending: ascending, filterKey: filterKey, total: total))
    }
  }

  /// Reset-Fetch (Seite 0): alter Reihenfolge-Index der Bibliothek weg (die `LocalBook`-Zeilen selbst bleiben —
  /// sie können parallel von Serien/Sammlungen/eBook-Listen referenziert sein), neuer Index ab `rank` 0.
  func replaceCatalogFirstPage(
    libraryId: String, sortField: String, ascending: Bool, filterKey: String?, total: Int, items: [ABSBook]
  ) throws {
    let entryPredicate = #Predicate<LocalCatalogEntry> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: entryPredicate)) {
      modelContext.delete(existing)
    }
    try upsertBooks(items)
    for (idx, item) in items.enumerated() {
      modelContext.insert(LocalCatalogEntry(libraryId: libraryId, rank: idx, bookId: item.id))
    }
    try upsertCatalogListState(
      libraryId: libraryId, sortField: sortField, ascending: ascending, filterKey: filterKey, total: total)
    try modelContext.save()
  }

  /// Stiller Hintergrund-Refresh bei unveränderter Filter-/Sort-Kombination (`preserveOtherCachedPages`):
  /// nur die ersten `items.count` Ränge werden ersetzt, bereits gecachte Folgeseiten (höhere Ränge) bleiben
  /// erhalten — ein voller Wipe würde sie bis zum nächsten Scroll unnötig verlieren.
  func refreshCatalogFirstPagePreservingRest(
    libraryId: String, sortField: String, ascending: Bool, filterKey: String?, total: Int, items: [ABSBook]
  ) throws {
    var stateDescriptor = FetchDescriptor<LocalCatalogListState>(predicate: #Predicate { $0.libraryId == libraryId })
    stateDescriptor.fetchLimit = 1
    guard let state = try modelContext.fetch(stateDescriptor).first,
      state.sortField == sortField, state.ascending == ascending, state.filterKey == filterKey
    else {
      // Kein passender Cache zum Erhalten — wie ein normaler Reset behandeln.
      try replaceCatalogFirstPage(
        libraryId: libraryId, sortField: sortField, ascending: ascending, filterKey: filterKey, total: total,
        items: items)
      return
    }
    try upsertBooks(items)
    let firstPageCount = items.count
    let existingFirstPageEntries = try modelContext.fetch(
      FetchDescriptor<LocalCatalogEntry>(
        predicate: #Predicate { $0.libraryId == libraryId && $0.rank < firstPageCount }))
    let existingByRank = Dictionary(uniqueKeysWithValues: existingFirstPageEntries.map { ($0.rank, $0) })
    for (idx, item) in items.enumerated() {
      if let entry = existingByRank[idx] {
        entry.bookId = item.id
      } else {
        modelContext.insert(LocalCatalogEntry(libraryId: libraryId, rank: idx, bookId: item.id))
      }
    }
    state.total = total
    try modelContext.save()
  }

  /// Folgeseite: an bestehenden Reihenfolge-Index anhängen (kein Wipe).
  func appendCatalogPage(libraryId: String, total: Int, items: [ABSBook]) throws {
    let entryPredicate = #Predicate<LocalCatalogEntry> { $0.libraryId == libraryId }
    let existingCount = try modelContext.fetchCount(FetchDescriptor(predicate: entryPredicate))
    try upsertBooks(items)
    for (idx, item) in items.enumerated() {
      modelContext.insert(LocalCatalogEntry(libraryId: libraryId, rank: existingCount + idx, bookId: item.id))
    }
    var stateDescriptor = FetchDescriptor<LocalCatalogListState>(predicate: #Predicate { $0.libraryId == libraryId })
    stateDescriptor.fetchLimit = 1
    if let state = try modelContext.fetch(stateDescriptor).first {
      state.total = total
    }
    try modelContext.save()
  }

  /// `nil`, wenn kein Cache oder die angefragte Filter-/Sort-Kombination von der zuletzt gecachten abweicht.
  /// `pageLimit`: Server-Seitengröße (`AppModel.libraryCatalogPageLimit`) — nur zur Herleitung von `nextPage`.
  func fetchCatalog(
    libraryId: String, sortField: String, ascending: Bool, filterKey: String?, pageLimit: Int
  ) -> (items: [ABSBook], total: Int, nextPage: Int)? {
    LocalLibraryQueries.catalog(
      context: modelContext, libraryId: libraryId, sortField: sortField, ascending: ascending,
      filterKey: filterKey, pageLimit: pageLimit)
  }

  // MARK: - Home-Regale (`/personalized` + Continue-Listening-Snapshot)

  /// Voll-Ersatz je Bibliothek — spiegelt exakt `AppModel.startShelves` zum Persistierzeitpunkt (inkl. bereits
  /// gemergter Continue-Listening-Zeile), 1:1-Ersatz für `homeContinue.json`/`personalized/<libraryId>.json`.
  func replaceHomeShelves(libraryId: String, sections: [ABSStartShelfSection]) throws {
    try upsertBooks(sections.flatMap(\.books))
    var descriptor = FetchDescriptor<LocalHomeShelvesSnapshot>(predicate: #Predicate { $0.libraryId == libraryId })
    descriptor.fetchLimit = 1
    if let existing = try modelContext.fetch(descriptor).first {
      existing.apply(sections)
    } else {
      modelContext.insert(LocalHomeShelvesSnapshot(libraryId: libraryId, sections: sections))
    }
    try modelContext.save()
  }

  func fetchHomeShelves(libraryId: String) -> [ABSStartShelfSection]? {
    LocalLibraryQueries.homeShelves(context: modelContext, libraryId: libraryId)
  }

  // MARK: - eBook-Continue-Regale (lokal injiziert aus Readium-Lesefortschritt)

  /// Voll-Ersatz je Bibliothek (kleine Listen) — 1:1-Ersatz für `ebookContinueShelves/<libraryId>.json`.
  func replaceEbookContinueEntries(libraryId: String, reading: [ABSBook], series: [ABSBook]) throws {
    let predicate = #Predicate<LocalEbookContinueEntry> { $0.libraryId == libraryId }
    for existing in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      modelContext.delete(existing)
    }
    try upsertBooks(reading)
    try upsertBooks(series)
    for (idx, book) in reading.enumerated() {
      modelContext.insert(LocalEbookContinueEntry(libraryId: libraryId, kind: "reading", rank: idx, bookId: book.id))
    }
    for (idx, book) in series.enumerated() {
      modelContext.insert(LocalEbookContinueEntry(libraryId: libraryId, kind: "series", rank: idx, bookId: book.id))
    }
    try modelContext.save()
  }

  func fetchEbookContinueEntries(libraryId: String) -> (reading: [ABSBook], series: [ABSBook])? {
    LocalLibraryQueries.ebookContinueEntries(context: modelContext, libraryId: libraryId)
  }

  // MARK: - Listening-Stats + Achievements

  /// Voll-Ersatz (ein Datensatz pro Store) — 1:1-Ersatz für `listeningStats.response.json`.
  func replaceListeningStatsResponse(rawData: Data) throws {
    var descriptor = FetchDescriptor<LocalListeningStatsSnapshot>()
    descriptor.fetchLimit = 1
    if let existing = try modelContext.fetch(descriptor).first {
      existing.blob = rawData
      existing.fetchedAt = Date()
    } else {
      modelContext.insert(LocalListeningStatsSnapshot(rawData: rawData))
    }
    try modelContext.save()
  }

  func fetchListeningStatsResponse() -> (data: Data, fetchedAt: Date)? {
    var descriptor = FetchDescriptor<LocalListeningStatsSnapshot>()
    descriptor.fetchLimit = 1
    guard let row = (try? modelContext.fetch(descriptor))?.first else { return nil }
    return (row.blob, row.fetchedAt)
  }

  /// Upsert je Achievement-Kind — 1:1-Ersatz für `listeningAchievements.snapshot.json`.
  func replaceAchievementsSnapshot(_ snapshot: ListeningAchievementsSnapshot) throws {
    let existing = try modelContext.fetch(FetchDescriptor<LocalAchievementState>())
    var byKind = Dictionary(uniqueKeysWithValues: existing.map { ($0.kind, $0) })
    for achievement in snapshot.achievements {
      if let row = byKind[achievement.kind.rawValue] {
        row.currentValue = achievement.currentValue
        row.savedAt = snapshot.savedAt
      } else {
        let row = LocalAchievementState(
          kind: achievement.kind, currentValue: achievement.currentValue, savedAt: snapshot.savedAt)
        modelContext.insert(row)
        byKind[achievement.kind.rawValue] = row
      }
    }
    try modelContext.save()
  }

  func fetchAchievementsSnapshot() -> ListeningAchievementsSnapshot? {
    LocalLibraryQueries.achievementsSnapshot(context: modelContext)
  }

  // MARK: - Libraries / Author-Detail / Listening-Sessions / Podcast-RSS

  /// Voll-Ersatz der Account-Bibliotheksliste — Local-DB-First für den Library-Picker.
  func replaceLibraries(_ libraries: [ABSLibrary]) throws {
    var descriptor = FetchDescriptor<LocalLibrariesSnapshot>()
    descriptor.fetchLimit = 1
    if let existing = try modelContext.fetch(descriptor).first {
      existing.apply(libraries)
    } else {
      modelContext.insert(LocalLibrariesSnapshot(libraries: libraries))
    }
    try modelContext.save()
  }

  func fetchLibraries() -> [ABSLibrary]? {
    LocalLibraryQueries.libraries(context: modelContext)
  }

  /// Upsert der Autor-Bio — getrennt von Browse-`LocalAuthor`, damit Listen-Reloads die Beschreibung behalten.
  func upsertAuthorDetail(authorId: String, libraryId: String, description: String?) throws {
    let aid = authorId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !aid.isEmpty else { return }
    let lid = libraryId.trimmingCharacters(in: .whitespacesAndNewlines)
    let predicate = #Predicate<LocalAuthorDetail> { $0.id == aid }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = (trimmed?.isEmpty == false) ? trimmed : nil
    if let existing = try modelContext.fetch(descriptor).first {
      existing.libraryId = lid
      existing.authorDescription = value
    } else {
      modelContext.insert(LocalAuthorDetail(id: aid, libraryId: lid, authorDescription: value))
    }
    try modelContext.save()
  }

  func fetchAuthorDescription(authorId: String) -> String? {
    LocalLibraryQueries.authorDescription(context: modelContext, authorId: authorId)
  }

  /// Voll-Ersatz der Hör-Sitzungen für ein Medium (Buch oder Podcast-Folge).
  func replaceListeningSessions(
    libraryItemId: String, episodeId: String?, sessions: [ABSListeningSession]
  ) throws {
    let lid = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lid.isEmpty else { return }
    let key = LocalListeningSessionsSnapshot.makeKey(libraryItemId: lid, episodeId: episodeId)
    let predicate = #Predicate<LocalListeningSessionsSnapshot> { $0.compositeKey == key }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    if let existing = try modelContext.fetch(descriptor).first {
      existing.apply(sessions)
    } else {
      modelContext.insert(
        LocalListeningSessionsSnapshot(libraryItemId: lid, episodeId: episodeId, sessions: sessions))
    }
    try modelContext.save()
  }

  func fetchListeningSessions(libraryItemId: String, episodeId: String?) -> [ABSListeningSession]? {
    LocalLibraryQueries.listeningSessions(
      context: modelContext, libraryItemId: libraryItemId, episodeId: episodeId)
  }

  /// Roh-RSS-Feed je Sendung speichern (wird beim Lesen erneut zu Drafts geparst).
  func replacePodcastRssFeed(showId: String, rawFeedData: Data) throws {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return }
    let predicate = #Predicate<LocalPodcastRssFeedSnapshot> { $0.showId == sid }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    if let existing = try modelContext.fetch(descriptor).first {
      existing.apply(rawFeedData: rawFeedData)
    } else {
      modelContext.insert(LocalPodcastRssFeedSnapshot(showId: sid, rawFeedData: rawFeedData))
    }
    try modelContext.save()
  }

  func fetchPodcastRssFeedRaw(showId: String) -> Data? {
    LocalLibraryQueries.podcastRssFeedRaw(context: modelContext, showId: showId)
  }

  func deletePodcastRssFeed(showId: String) throws {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return }
    let predicate = #Predicate<LocalPodcastRssFeedSnapshot> { $0.showId == sid }
    for row in try modelContext.fetch(FetchDescriptor(predicate: predicate)) {
      modelContext.delete(row)
    }
    try modelContext.save()
  }
}

/// Reine Lesefunktionen, die sowohl vom `LocalLibraryStore`-Actor (Hintergrund-Fetches) als auch direkt vom
/// `ModelContainer.mainContext` (synchrone Einzel-Lookups auf dem Main-Actor) genutzt werden — `ModelContext`
/// selbst ist nicht Actor-gebunden, nur der jeweilige Aufrufer.
enum LocalLibraryQueries {
  static func catalog(
    context: ModelContext, libraryId: String, sortField: String, ascending: Bool, filterKey: String?, pageLimit: Int
  ) -> (items: [ABSBook], total: Int, nextPage: Int)? {
    var stateDescriptor = FetchDescriptor<LocalCatalogListState>(predicate: #Predicate { $0.libraryId == libraryId })
    stateDescriptor.fetchLimit = 1
    guard let state = (try? context.fetch(stateDescriptor))?.first,
      state.sortField == sortField, state.ascending == ascending, state.filterKey == filterKey
    else { return nil }
    let entryPredicate = #Predicate<LocalCatalogEntry> { $0.libraryId == libraryId }
    let entries =
      (try? context.fetch(FetchDescriptor(predicate: entryPredicate, sortBy: [SortDescriptor(\.rank)]))) ?? []
    guard !entries.isEmpty else { return nil }
    let bookIds = entries.map(\.bookId)
    let books =
      (try? context.fetch(FetchDescriptor<LocalBook>(predicate: #Predicate { bookIds.contains($0.id) }))) ?? []
    let booksById = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
    let items = entries.compactMap { booksById[$0.bookId]?.toABSBook() }
    guard !items.isEmpty else { return nil }
    return (items, state.total, (entries.count + pageLimit - 1) / pageLimit)
  }

  static func book(context: ModelContext, id: String) -> ABSBook? {
    var descriptor = FetchDescriptor<LocalBook>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor))?.first?.toABSBook()
  }

  /// Persistierte Katalog-eBook-Flags — Filter/Badge ohne Heuristik-Enrichment.
  static func bookCatalogEbookFlags(
    context: ModelContext, id: String
  ) -> (hasEbook: Bool, hasSupplementary: Bool)? {
    var descriptor = FetchDescriptor<LocalBook>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    guard let row = (try? context.fetch(descriptor))?.first else { return nil }
    return (row.catalogHasEbook, row.catalogHasSupplementaryEbook)
  }

  /// Reine eBooks im Browse-Tab (`catalogHasEbook`, nicht supplementär).
  static func browsePureEbooks(context: ModelContext, libraryId: String) -> [ABSBook] {
    let lid = libraryId
    let rows =
      (try? context.fetch(
        FetchDescriptor<LocalBook>(
          predicate: #Predicate { $0.libraryId == lid && $0.catalogHasEbook && !$0.catalogHasSupplementaryEbook },
          sortBy: [SortDescriptor(\.title)]))) ?? []
    return decodeLocalBookRows(rows)
  }

  /// Hörbücher mit supplementärem eBook im Browse-Tab.
  static func browseSupplementaryEbooks(context: ModelContext, libraryId: String) -> [ABSBook] {
    let lid = libraryId
    let rows =
      (try? context.fetch(
        FetchDescriptor<LocalBook>(
          predicate: #Predicate { $0.libraryId == lid && $0.catalogHasSupplementaryEbook },
          sortBy: [SortDescriptor(\.title)]))) ?? []
    return decodeLocalBookRows(rows)
  }

  private static func decodeLocalBookRows(_ rows: [LocalBook]) -> [ABSBook] {
    var byId: [String: ABSBook] = [:]
    for row in rows {
      let book = row.toABSBookDetail() ?? row.toABSBook()
      guard let book else { continue }
      if let existing = byId[book.id] {
        byId[book.id] = book.preferringRicherListMetadata(than: existing)
      } else {
        byId[book.id] = book
      }
    }
    return Array(byId.values)
  }

  /// Offline eBook-Katalogfilter — alte Browse-Logik (rein: `isUsableEbookListRow`, supplementär: `isPlayableAudiobook`).
  static func ebookCatalogBooks(context: ModelContext, libraryId: String) -> [ABSBook] {
    let lid = libraryId
    let rows =
      (try? context.fetch(FetchDescriptor<LocalBook>(predicate: #Predicate { $0.libraryId == lid }))) ?? []
    var byId: [String: ABSBook] = [:]
    for row in rows {
      let stub = row.toABSBook()
      let detail = row.toABSBookDetail()
      let candidate: ABSBook?
      if row.catalogHasEbook, let book = stub ?? detail {
        candidate = book
      } else if let book = stub, book.isUsableEbookListRow, !book.isPlayableAudiobook {
        candidate = book
      } else if let book = stub ?? detail, book.isPlayableAudiobook,
        row.catalogHasSupplementaryEbook || book.isCatalogSupplementaryEbook
      {
        candidate = book
      } else {
        candidate = nil
      }
      guard let book = candidate else { continue }
      if let existing = byId[book.id] {
        byId[book.id] = book.preferringRicherListMetadata(than: existing)
      } else {
        byId[book.id] = book
      }
    }
    return Array(byId.values).sorted {
      $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
    }
  }

  /// Erweiterte Detail-Kopie (mit Beschreibung), falls schon einmal per `?expanded=1` geladen — siehe `LocalBook.detailBlob`.
  static func bookDetail(context: ModelContext, id: String) -> ABSBook? {
    var descriptor = FetchDescriptor<LocalBook>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor))?.first?.toABSBookDetail()
  }

  /// Voller lokaler Katalog aus `LocalBook`-Reihen (Superset — mehr als `LocalCatalogEntry`).
  /// Sortierung client-seitig; Felder die nicht auf `LocalBook` liegen (progress, random, etc.)
  /// fallen auf `\.title` zurück und werden vom Server-Reload korrigiert.
  static func allBooks(
    context: ModelContext, libraryId: String,
    sortField: CatalogSortField, descending: Bool
  ) -> [ABSBook] {
    let lid = libraryId
    var descriptor = FetchDescriptor<LocalBook>(
      predicate: #Predicate { $0.libraryId == lid },
      sortBy: localBookSortDescriptors(sortField, descending)
    )
    descriptor.fetchLimit = 0
    let rows = (try? context.fetch(descriptor)) ?? []
    return decodeLocalBookRows(rows)
  }

  /// `true`, wenn das Sortierfeld direkt auf `LocalBook` liegt und die Superset-Abfrage
  /// (`allBooks`) die gewählte Reihenfolge wirklich abbilden kann. Für alle anderen Felder
  /// (Jahr, Größe, Fortschritt, Zufall, …) muss die Server-Reihenfolge verwendet werden —
  /// der frühere stille Titel-Fallback zeigte sonst eine falsche Sortierung an.
  static func supportsLocalBookSort(_ sortField: CatalogSortField) -> Bool {
    switch sortField {
    case .title, .authorName, .authorNameLF, .addedAt, .duration:
      return true
    default:
      return false
    }
  }

  /// Mappt `CatalogSortField` auf `SortDescriptor`s für `LocalBook` — immer mit Titel + ID als
  /// Tiebreaker, sonst ist die Reihenfolge bei gleichen Sortierwerten (z. B. gleicher Autor)
  /// pro Fetch zufällig und die Liste „springt" bei jedem App-Start.
  private static func localBookSortDescriptors(
    _ sortField: CatalogSortField, _ descending: Bool
  ) -> [SortDescriptor<LocalBook>] {
    let order: SortOrder = descending ? .reverse : .forward
    let primary: SortDescriptor<LocalBook>
    switch sortField {
    case .title:
      primary = SortDescriptor(\.title, order: order)
    case .authorName, .authorNameLF:
      primary = SortDescriptor(\.authorName, order: order)
    case .addedAt:
      primary = SortDescriptor(\.addedAt, order: order)
    case .duration:
      primary = SortDescriptor(\.duration, order: order)
    default:
      primary = SortDescriptor(\.title, order: order)
    }
    return [
      primary,
      SortDescriptor(\.title, order: .forward),
      SortDescriptor(\.id, order: .forward),
    ]
  }

  /// Bücher zu einer Menge von IDs aus der geteilten `LocalBook`-Tabelle nachladen (für `LocalSeries`/
  /// `LocalCollection`, die nur `bookIds` statt eingebetteter Kopien speichern).
  private static func booksById(context: ModelContext, ids: [String]) -> [String: ABSBook] {
    guard !ids.isEmpty else { return [:] }
    let rows = (try? context.fetch(FetchDescriptor<LocalBook>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
    var result: [String: ABSBook] = [:]
    result.reserveCapacity(rows.count)
    for row in rows {
      if let book = row.toABSBook() { result[row.id] = book }
    }
    return result
  }

  static func series(
    context: ModelContext, libraryId: String, sortField: String, descending: Bool
  ) -> (items: [ABSLibrarySeriesListItem], total: Int, nextPage: Int)? {
    var stateDescriptor = FetchDescriptor<LocalSeriesListState>(predicate: #Predicate { $0.libraryId == libraryId })
    stateDescriptor.fetchLimit = 1
    guard let state = (try? context.fetch(stateDescriptor))?.first,
      state.sortField == sortField, state.descending == descending
    else { return nil }
    let predicate = #Predicate<LocalSeries> { $0.libraryId == libraryId }
    let rows =
      (try? context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.sortRank)]))) ?? []
    guard !rows.isEmpty else { return nil }
    let booksById = booksById(context: context, ids: Array(Set(rows.flatMap(\.bookIds))))
    let items = rows.map { $0.toItem(booksById: booksById) }
    return (items, state.total, (items.count + 39) / 40)
  }

  static func collections(
    context: ModelContext, libraryId: String
  ) -> (items: [ABSLibraryCollectionListItem], total: Int)? {
    var stateDescriptor = FetchDescriptor<LocalCollectionListState>(
      predicate: #Predicate { $0.libraryId == libraryId })
    stateDescriptor.fetchLimit = 1
    guard let state = (try? context.fetch(stateDescriptor))?.first else { return nil }
    let predicate = #Predicate<LocalCollection> { $0.libraryId == libraryId }
    let rows = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
    guard !rows.isEmpty else { return nil }
    let booksById = booksById(context: context, ids: Array(Set(rows.flatMap(\.bookIds))))
    let items = rows.map { $0.toItem(booksById: booksById) }
    return (items, state.total)
  }

  static func podcastEpisodes(
    context: ModelContext, libraryId: String
  ) -> (items: [ABSPodcastEpisodeListItem], total: Int, pagingFromRecentAPI: Bool)? {
    var stateDescriptor = FetchDescriptor<LocalPodcastEpisodeListState>(
      predicate: #Predicate { $0.libraryId == libraryId })
    stateDescriptor.fetchLimit = 1
    guard let state = (try? context.fetch(stateDescriptor))?.first else { return nil }
    let predicate = #Predicate<LocalPodcastEpisode> { $0.libraryId == libraryId }
    let rows =
      (try? context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.rank)]))) ?? []
    guard !rows.isEmpty else { return nil }
    return (rows.map { $0.toItem() }, state.total, state.pagingFromRecentAPI)
  }

  /// Einzelne Folge über ihren `progressLookupKey` — Pendant zu `book(context:id:)`. Findet Folgen, die in
  /// einer früheren Session synchronisiert wurden, auch wenn kein `@Published`-Array sie mehr im Speicher hält.
  static func podcastEpisode(context: ModelContext, progressLookupKey: String) -> ABSPodcastEpisodeListItem? {
    var descriptor = FetchDescriptor<LocalPodcastEpisode>(
      predicate: #Predicate { $0.progressLookupKey == progressLookupKey })
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor))?.first?.toItem()
  }

  static func podcastShows(
    context: ModelContext, libraryId: String, sortField: String, ascending: Bool
  ) -> [ABSBook]? {
    var stateDescriptor = FetchDescriptor<LocalPodcastShowListState>(
      predicate: #Predicate { $0.libraryId == libraryId })
    stateDescriptor.fetchLimit = 1
    guard let state = (try? context.fetch(stateDescriptor))?.first,
      state.sortField == sortField, state.ascending == ascending
    else { return nil }
    let entryPredicate = #Predicate<LocalPodcastShowEntry> { $0.libraryId == libraryId }
    let entries =
      (try? context.fetch(FetchDescriptor(predicate: entryPredicate, sortBy: [SortDescriptor(\.rank)]))) ?? []
    guard !entries.isEmpty else { return nil }
    let booksById = booksById(context: context, ids: entries.map(\.bookId))
    let items = entries.compactMap { booksById[$0.bookId] }
    guard !items.isEmpty else { return nil }
    return items
  }

  static func homeShelves(context: ModelContext, libraryId: String) -> [ABSStartShelfSection]? {
    var descriptor = FetchDescriptor<LocalHomeShelvesSnapshot>(predicate: #Predicate { $0.libraryId == libraryId })
    descriptor.fetchLimit = 1
    guard let row = (try? context.fetch(descriptor))?.first else { return nil }
    return row.toSections()
  }

  static func ebookContinueEntries(
    context: ModelContext, libraryId: String
  ) -> (reading: [ABSBook], series: [ABSBook])? {
    let predicate = #Predicate<LocalEbookContinueEntry> { $0.libraryId == libraryId }
    let rows =
      (try? context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.rank)]))) ?? []
    guard !rows.isEmpty else { return nil }
    let booksById = booksById(context: context, ids: rows.map(\.bookId))
    let reading = rows.filter { $0.kind == "reading" }.compactMap { booksById[$0.bookId] }
    let series = rows.filter { $0.kind == "series" }.compactMap { booksById[$0.bookId] }
    guard !reading.isEmpty || !series.isEmpty else { return nil }
    return (reading, series)
  }

  /// Ersetzt `items-in-progress`-Snapshot: Top-`limit` `LocalProgress`-Zeilen nach `lastUpdate`, gejoint mit
  /// `LocalBook`/`LocalPodcastEpisode` (Migrationsplan Etappe 8, Grundprinzip 8 — lebendige Query statt Cache).
  static func itemsInProgressPayload(context: ModelContext, limit: Int) -> ABSItemsInProgressPayload? {
    var descriptor = FetchDescriptor<LocalProgress>(sortBy: [SortDescriptor(\.lastUpdate, order: .reverse)])
    descriptor.fetchLimit = limit
    let rows = (try? context.fetch(descriptor)) ?? []
    guard !rows.isEmpty else { return nil }
    let bookRows = rows.filter { ($0.episodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let episodeRows = rows.filter { !($0.episodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let booksById = booksById(context: context, ids: bookRows.map(\.libraryItemId))
    var episodesByKey: [String: ABSPodcastEpisodeListItem] = [:]
    if !episodeRows.isEmpty {
      let episodeKeys = episodeRows.map(\.progressLookupKey)
      let episodeModelRows =
        (try? context.fetch(FetchDescriptor<LocalPodcastEpisode>(
          predicate: #Predicate { episodeKeys.contains($0.progressLookupKey) }))) ?? []
      episodesByKey = Dictionary(uniqueKeysWithValues: episodeModelRows.map { ($0.progressLookupKey, $0.toItem()) })
    }
    var books: [ABSBook] = []
    var episodes: [ABSPodcastEpisodeListItem] = []
    for row in rows {
      let epId = (row.episodeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if epId.isEmpty {
        if let book = booksById[row.libraryItemId] {
          books.append(book)
        }
      } else if let episode = episodesByKey[row.progressLookupKey] {
        episodes.append(episode)
      }
    }
    guard !books.isEmpty || !episodes.isEmpty else { return nil }
    return ABSItemsInProgressPayload(books: books, podcastEpisodes: episodes)
  }

  static func achievementsSnapshot(context: ModelContext) -> ListeningAchievementsSnapshot? {
    let rows = (try? context.fetch(FetchDescriptor<LocalAchievementState>())) ?? []
    guard !rows.isEmpty else { return nil }
    let byKind = Dictionary(uniqueKeysWithValues: rows.map { ($0.kind, $0) })
    let list = ListeningAchievementKind.allCases.map { kind in
      ListeningAchievementState(kind: kind, currentValue: byKind[kind.rawValue]?.currentValue ?? 0)
    }
    return ListeningAchievementsSnapshot(achievements: list, savedAt: rows.compactMap(\.savedAt).max())
  }

  static func libraries(context: ModelContext) -> [ABSLibrary]? {
    var descriptor = FetchDescriptor<LocalLibrariesSnapshot>()
    descriptor.fetchLimit = 1
    guard let row = (try? context.fetch(descriptor))?.first else { return nil }
    return row.toLibraries()
  }

  static func authorDescription(context: ModelContext, authorId: String) -> String? {
    let aid = authorId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !aid.isEmpty else { return nil }
    let predicate = #Predicate<LocalAuthorDetail> { $0.id == aid }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    guard let row = (try? context.fetch(descriptor))?.first else { return nil }
    let text = row.authorDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? nil : text
  }

  static func listeningSessions(
    context: ModelContext, libraryItemId: String, episodeId: String?
  ) -> [ABSListeningSession]? {
    let key = LocalListeningSessionsSnapshot.makeKey(libraryItemId: libraryItemId, episodeId: episodeId)
    let predicate = #Predicate<LocalListeningSessionsSnapshot> { $0.compositeKey == key }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    guard let row = (try? context.fetch(descriptor))?.first else { return nil }
    return row.toSessions()
  }

  static func podcastRssFeedRaw(context: ModelContext, showId: String) -> Data? {
    let sid = showId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sid.isEmpty else { return nil }
    let predicate = #Predicate<LocalPodcastRssFeedSnapshot> { $0.showId == sid }
    var descriptor = FetchDescriptor(predicate: predicate)
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor))?.first?.blob
  }
}

/// Öffnet/wechselt den `ModelContainer` je Account. Pfadschema analog `AccountCacheDirectory.accountDir`
/// (SHA256 von Server-URL + optional User-ID als Verzeichnisname), aber eigener Wurzelordner — Downloads/
/// Cover/eBook-Lokaldaten bleiben dateibasiert und laufen unabhängig vom SwiftData-Store weiter.
@MainActor
enum LocalLibraryStoreManager {
  private static let fm = FileManager.default

  private static var baseDir: URL {
    let app = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return app.appendingPathComponent("ABStandLocalStore", isDirectory: true)
  }

  private static func sha256Hex(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// Account-Verzeichnis für den SwiftData-Store — getrennt pro Server-URL (+ optional User-ID).
  static func accountStoreDirectory(serverURL: String, userId: String?) -> URL {
    let serverRoot = baseDir.appendingPathComponent("accounts", isDirectory: true)
      .appendingPathComponent(sha256Hex(serverURL), isDirectory: true)
    try? fm.createDirectory(at: serverRoot, withIntermediateDirectories: true)

    let trimmedUser = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmedUser.isEmpty else { return serverRoot }

    let userRoot = serverRoot.appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(sha256Hex(trimmedUser), isDirectory: true)
    try? fm.createDirectory(at: userRoot, withIntermediateDirectories: true)
    return userRoot
  }

  private static var openedDirectory: URL?
  private static var openedContainer: ModelContainer?
  private static var openedStore: LocalLibraryStore?

  /// Öffnet/wechselt den Container bei Bedarf und liefert ihn zusammen mit dem passenden Actor zurück.
  private static func openContainer(serverURL: String, userId: String?) -> ModelContainer? {
    guard let normalized = ABSAPIClient.normalizeServerURL(serverURL)?.absoluteString else { return nil }
    let directory = accountStoreDirectory(serverURL: normalized, userId: userId)
    if directory == openedDirectory, let container = openedContainer {
      return container
    }
    let storeURL = directory.appendingPathComponent(localLibraryStoreFileName)
    removeLegacyLocalLibraryStoreIfPresent(in: directory)
    let configuration = ModelConfiguration(url: storeURL)
    if let container = try? ModelContainer(
      for: LocalLibrarySchema.current,
      migrationPlan: LocalLibraryMigrationPlan.self,
      configurations: configuration
    ) {
      openedDirectory = directory
      openedContainer = container
      openedStore = LocalLibraryStore(modelContainer: container)
      return container
    }
    // Kaputter Migrationsstand (z. B. fehlgeschlagene Custom-Migration) — Store neu anlegen.
    AppLog.bootstrap.error(
      "SwiftData: ModelContainer fehlgeschlagen, Store wird neu angelegt: \(storeURL.path, privacy: .public)")
    removeLocalLibraryStoreFiles(at: storeURL)
    guard let container = try? ModelContainer(
      for: LocalLibrarySchema.current,
      migrationPlan: LocalLibraryMigrationPlan.self,
      configurations: configuration
    ) else {
      AppLog.bootstrap.error(
        "SwiftData: ModelContainer konnte nicht geöffnet werden: \(storeURL.path, privacy: .public)")
      return nil
    }
    openedDirectory = directory
    openedContainer = container
    openedStore = LocalLibraryStore(modelContainer: container)
    return container
  }

  /// Store-Dateiname (historisch `.v2` nach früherem Migrations-Wipe). Schema selbst: `LocalLibrarySchemaV4`.
  private static let localLibraryStoreFileName = "LocalLibrary.v2.store"

  private static func removeLegacyLocalLibraryStoreIfPresent(in directory: URL) {
    removeLocalLibraryStoreFiles(at: directory.appendingPathComponent("LocalLibrary.store"))
  }

  /// SQLite-Store + WAL/SHM entfernen, damit ein frischer Container angelegt werden kann.
  private static func removeLocalLibraryStoreFiles(at storeURL: URL) {
    let fm = FileManager.default
    for url in [storeURL, storeURL.appendingPathExtension("wal"), storeURL.appendingPathExtension("shm")] {
      try? fm.removeItem(at: url)
    }
  }

  /// Liefert den `LocalLibraryStore` für den angegebenen Account — öffnet/wechselt den Container bei Bedarf.
  /// `nil`, solange Server-URL/User (noch) nicht bekannt sind (z. B. vor Login). Für Schreiben/große Fetches.
  static func store(serverURL: String, userId: String?) -> LocalLibraryStore? {
    guard openContainer(serverURL: serverURL, userId: userId) != nil else { return nil }
    return openedStore
  }

  /// Main-Actor-`ModelContext` für schnelle synchrone Einzel-Lookups (z. B. Existenz-Checks vor dem ersten Frame).
  /// Für Schreiben/größere Fetches stattdessen `store(...)` (läuft auf dem `LocalLibraryStore`-Actor).
  static func mainContext(serverURL: String, userId: String?) -> ModelContext? {
    openContainer(serverURL: serverURL, userId: userId)?.mainContext
  }
}
