import CryptoKit
import Foundation

/// Lokaler Cache (Application Support): Katalog-Seiten als Server-JSON, personalisierte Regale, Fortschritt.
enum LibraryDiskCache {
  private static let fm = FileManager.default

  private static var baseDir: URL {
    let app = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return app.appendingPathComponent("ABStandLibraryCache", isDirectory: true)
  }

  /// Nur Server-URL (normalisiert), damit der Ordner bei Token-Refresh stabil bleibt.
  static func accountDir(serverURL: String) -> URL {
    let digest = SHA256.hash(data: Data(serverURL.utf8))
    let id = digest.map { String(format: "%02x", $0) }.joined()
    let u = baseDir.appendingPathComponent("accounts", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }

  static func clearEverything() {
    try? fm.removeItem(at: baseDir)
  }

  private static func catalogSlug(filter: String?, sortField: String, ascending: Bool) -> String {
    let f = filter ?? ""
    let raw = "\(f)|\(sortField)|\(ascending)"
    let h = SHA256.hash(data: Data(raw.utf8))
    return h.map { String(format: "%02x", $0) }.joined()
  }

  private static func catalogFolder(
    account: URL, libraryId: String, filter: String?, sortField: String, ascending: Bool
  ) -> URL {
    let slug = catalogSlug(filter: filter, sortField: sortField, ascending: ascending)
    let u = account.appendingPathComponent("catalog", isDirectory: true)
      .appendingPathComponent(libraryId, isDirectory: true)
      .appendingPathComponent(slug, isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }

  /// Vor einem neuen Katalog-`reset`-Fetch: alte Seiten dieses Slugs entfernen.
  static func wipeCatalogSlug(
    account: URL, libraryId: String, filter: String?, sortField: String, ascending: Bool
  ) throws {
    let u = catalogFolder(account: account, libraryId: libraryId, filter: filter, sortField: sortField, ascending: ascending)
    if fm.fileExists(atPath: u.path) {
      try fm.removeItem(at: u)
    }
    try fm.createDirectory(at: u, withIntermediateDirectories: true)
  }

  static func saveCatalogPage(
    account: URL, libraryId: String, filter: String?, sortField: String, ascending: Bool, pageIndex: Int, data: Data
  ) throws {
    let dir = catalogFolder(account: account, libraryId: libraryId, filter: filter, sortField: sortField, ascending: ascending)
    let file = dir.appendingPathComponent("page_\(pageIndex).json")
    try data.write(to: file, options: .atomic)
  }

  static func loadMergedCatalog(
    account: URL,
    libraryId: String,
    filter: String?,
    sortField: String,
    ascending: Bool,
    decoder: JSONDecoder
  ) -> (books: [ABSBook], total: Int, nextPage: Int)? {
    let dir = catalogFolder(account: account, libraryId: libraryId, filter: filter, sortField: sortField, ascending: ascending)
    guard fm.fileExists(atPath: dir.path) else { return nil }
    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    let pageFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("page_") }
    guard !pageFiles.isEmpty else { return nil }

    func pageIndex(_ url: URL) -> Int {
      let base = url.deletingPathExtension().lastPathComponent
      let parts = base.split(separator: "_")
      return Int(parts.last ?? "0") ?? 0
    }
    let sorted = pageFiles.sorted { pageIndex($0) < pageIndex($1) }

    var all: [ABSBook] = []
    var total = 0
    for url in sorted {
      guard let data = try? Data(contentsOf: url) else { continue }
      guard let page = try? decoder.decode(ABSPage<ABSBook>.self, from: data) else { continue }
      total = page.total
      let filtered = page.results.filter(\.isUsableLibraryCatalogRow)
      all.append(contentsOf: filtered)
    }
    if sorted.isEmpty { return nil }
    return (all, total, sorted.count)
  }

  static func savePersonalized(account: URL, libraryId: String, data: Data) throws {
    let dir = account.appendingPathComponent("personalized", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent("\(libraryId).json"), options: .atomic)
  }

  static func loadPersonalized(account: URL, libraryId: String) -> Data? {
    let u = account.appendingPathComponent("personalized", isDirectory: true).appendingPathComponent("\(libraryId).json")
    guard fm.fileExists(atPath: u.path) else { return nil }
    return try? Data(contentsOf: u)
  }

  /// `GET /api/me/items-in-progress` — Continue listening / Continue reading auf Home.
  static func saveItemsInProgress(account: URL, libraryId: String, data: Data) throws {
    let dir = account.appendingPathComponent("itemsInProgress", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent("\(libraryId).json"), options: .atomic)
  }

  static func loadItemsInProgress(account: URL, libraryId: String) -> Data? {
    let u = account.appendingPathComponent("itemsInProgress", isDirectory: true)
      .appendingPathComponent("\(libraryId).json")
    guard fm.fileExists(atPath: u.path) else { return nil }
    return try? Data(contentsOf: u)
  }

  static func saveFilterData(account: URL, libraryId: String, data: Data) throws {
    let dir = account.appendingPathComponent("filterdata", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent("\(libraryId).json"), options: .atomic)
  }

  static func loadFilterData(account: URL, libraryId: String) -> Data? {
    let u = account.appendingPathComponent("filterdata", isDirectory: true).appendingPathComponent("\(libraryId).json")
    guard fm.fileExists(atPath: u.path) else { return nil }
    return try? Data(contentsOf: u)
  }

  static func saveBrowseGenreStats(account: URL, libraryId: String, genres: [ABSLibraryGenreStat]) throws {
    let dir = account.appendingPathComponent("browseGenres", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try ABSJSON.encoder().encode(genres)
    try data.write(to: dir.appendingPathComponent("\(libraryId).json"), options: .atomic)
  }

  static func loadBrowseGenreStats(
    account: URL, libraryId: String, decoder: JSONDecoder
  ) -> [ABSLibraryGenreStat]? {
    let u =
      account
      .appendingPathComponent("browseGenres", isDirectory: true)
      .appendingPathComponent("\(libraryId).json")
    guard fm.fileExists(atPath: u.path), let data = try? Data(contentsOf: u) else { return nil }
    return try? decoder.decode([ABSLibraryGenreStat].self, from: data)
  }

  static func saveBrowseTagStats(account: URL, libraryId: String, tags: [ABSLibraryTagStat]) throws {
    let dir = account.appendingPathComponent("browseTags", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try ABSJSON.encoder().encode(tags)
    try data.write(to: dir.appendingPathComponent("\(libraryId).json"), options: .atomic)
  }

  static func loadBrowseTagStats(
    account: URL, libraryId: String, decoder: JSONDecoder
  ) -> [ABSLibraryTagStat]? {
    let u =
      account
      .appendingPathComponent("browseTags", isDirectory: true)
      .appendingPathComponent("\(libraryId).json")
    guard fm.fileExists(atPath: u.path), let data = try? Data(contentsOf: u) else { return nil }
    return try? decoder.decode([ABSLibraryTagStat].self, from: data)
  }

  static func saveProgress(account: URL, list: [ABSUserMediaProgress]) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(list)
    try data.write(to: account.appendingPathComponent("progress.json"), options: .atomic)
  }

  static func loadProgress(account: URL, decoder: JSONDecoder) -> [ABSUserMediaProgress]? {
    let u = account.appendingPathComponent("progress.json")
    guard let data = try? Data(contentsOf: u) else { return nil }
    return try? decoder.decode([ABSUserMediaProgress].self, from: data)
  }

  static func saveBookmarks(account: URL, list: [ABSAudioBookmark]) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(list)
    try data.write(to: account.appendingPathComponent("bookmarks.json"), options: .atomic)
  }

  static func loadBookmarks(account: URL, decoder: JSONDecoder) -> [ABSAudioBookmark]? {
    let u = account.appendingPathComponent("bookmarks.json")
    guard let data = try? Data(contentsOf: u) else { return nil }
    return try? decoder.decode([ABSAudioBookmark].self, from: data)
  }

  // MARK: - Podcast recent-episodes (pro Bibliothek, wie Paginierung vom Server)

  private static func podcastRecentLibraryURL(account: URL, libraryId: String) -> URL {
    account.appendingPathComponent("podcastRecent", isDirectory: true)
      .appendingPathComponent(libraryId, isDirectory: true)
  }

  private static func podcastRecentDir(account: URL, libraryId: String) -> URL {
    let u = podcastRecentLibraryURL(account: account, libraryId: libraryId)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }

  /// Vor einem neuen Podcast-Katalog-`reset`-Fetch: recent-Seiten + Fallback-Datei entfernen.
  static func wipePodcastRecent(account: URL, libraryId: String) throws {
    let u = podcastRecentLibraryURL(account: account, libraryId: libraryId)
    if fm.fileExists(atPath: u.path) {
      try fm.removeItem(at: u)
    }
    try fm.createDirectory(at: u, withIntermediateDirectories: true)
  }

  static func savePodcastRecentPage(account: URL, libraryId: String, pageIndex: Int, data: Data) throws {
    let dir = podcastRecentDir(account: account, libraryId: libraryId)
    let file = dir.appendingPathComponent("page_\(pageIndex).json")
    try data.write(to: file, options: .atomic)
  }

  struct MergedPodcastRecent {
    let episodes: [ABSPodcastEpisodeListItem]
    let total: Int
    let nextPageIndex: Int
  }

  static func loadMergedPodcastRecent(
    account: URL,
    libraryId: String,
    libraryIdForRows: String?,
    decoder: JSONDecoder
  ) -> MergedPodcastRecent? {
    let dir = podcastRecentLibraryURL(account: account, libraryId: libraryId)
    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    let pageFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("page_") }
    guard !pageFiles.isEmpty else { return nil }

    func pageIndex(_ url: URL) -> Int {
      let base = url.deletingPathExtension().lastPathComponent
      let parts = base.split(separator: "_")
      return Int(parts.last ?? "0") ?? 0
    }
    let sorted = pageFiles.sorted { pageIndex($0) < pageIndex($1) }

    var all: [ABSPodcastEpisodeListItem] = []
    var total = 0
    for url in sorted {
      guard let data = try? Data(contentsOf: url) else { continue }
      guard let res = try? decoder.decode(ABSRecentEpisodesResponse.self, from: data) else { continue }
      total = res.total
      let rows = res.episodes.compactMap { ABSPodcastEpisodeListItem.fromDTO($0, libraryId: libraryIdForRows) }
      all.append(contentsOf: rows)
    }
    guard !sorted.isEmpty else { return nil }
    return MergedPodcastRecent(episodes: all, total: total, nextPageIndex: sorted.count)
  }

  private struct PodcastFallbackFile: Codable {
    let episodes: [ABSPodcastEpisodeListItem]
  }

  static func savePodcastFallback(account: URL, libraryId: String, episodes: [ABSPodcastEpisodeListItem]) throws {
    let dir = podcastRecentDir(account: account, libraryId: libraryId)
    let data = try JSONEncoder().encode(PodcastFallbackFile(episodes: episodes))
    try data.write(to: dir.appendingPathComponent("episodes_fallback.json"), options: .atomic)
  }

  static func loadPodcastFallback(
    account: URL,
    libraryId: String
  ) -> [ABSPodcastEpisodeListItem]? {
    let u = podcastRecentLibraryURL(account: account, libraryId: libraryId).appendingPathComponent("episodes_fallback.json")
    guard let data = try? Data(contentsOf: u) else { return nil }
    return try? ABSJSON.decoder().decode(PodcastFallbackFile.self, from: data).episodes
  }

  // MARK: - Books browse (authors / series paginated; collections + narrators blob)

  private static func browseSortSlug(sort: String, descending: Bool) -> String {
    let raw = "\(sort)|\(descending)"
    let h = SHA256.hash(data: Data(raw.utf8))
    return h.map { String(format: "%02x", $0) }.joined()
  }

  private static func browseAuthorsSlugURL(account: URL, libraryId: String, sort: String, descending: Bool) -> URL {
    let slug = browseSortSlug(sort: sort, descending: descending)
    return account.appendingPathComponent("browseAuthors", isDirectory: true)
      .appendingPathComponent(libraryId, isDirectory: true)
      .appendingPathComponent(slug, isDirectory: true)
  }

  static func wipeBrowseAuthorsSlug(
    account: URL, libraryId: String, sort: String, descending: Bool
  ) throws {
    let u = browseAuthorsSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    if fm.fileExists(atPath: u.path) {
      try fm.removeItem(at: u)
    }
    try fm.createDirectory(at: u, withIntermediateDirectories: true)
  }

  static func saveBrowseAuthorsPage(
    account: URL, libraryId: String, sort: String, descending: Bool, pageIndex: Int, data: Data
  ) throws {
    let dir = browseAuthorsSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("page_\(pageIndex).json")
    try data.write(to: file, options: .atomic)
  }

  static func loadMergedBrowseAuthors(
    account: URL,
    libraryId: String,
    sort: String,
    descending: Bool,
    decoder: JSONDecoder
  ) -> (items: [ABSLibraryAuthorListItem], total: Int, nextPage: Int)? {
    let dir = browseAuthorsSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    guard fm.fileExists(atPath: dir.path) else { return nil }
    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    let pageFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("page_") }
    guard !pageFiles.isEmpty else { return nil }

    func pageIndex(_ url: URL) -> Int {
      let base = url.deletingPathExtension().lastPathComponent
      let parts = base.split(separator: "_")
      return Int(parts.last ?? "0") ?? 0
    }
    let sorted = pageFiles.sorted { pageIndex($0) < pageIndex($1) }

    var all: [ABSLibraryAuthorListItem] = []
    var total = 0
    for url in sorted {
      guard let data = try? Data(contentsOf: url) else { continue }
      if let env = try? decoder.decode(ABSLibraryAuthorsAPIEnvelope.self, from: data) {
        let pair = env.itemsAndTotal()
        total = pair.1
        all.append(contentsOf: pair.0)
      } else if let leg = try? decoder.decode(ABSLibraryAuthorsEnvelope.self, from: data) {
        total = leg.authors.count
        all.append(contentsOf: leg.authors)
      }
    }
    guard !sorted.isEmpty, !all.isEmpty else { return nil }
    return (all, total, sorted.count)
  }

  private static func browseSeriesSlugURL(account: URL, libraryId: String, sort: String, descending: Bool) -> URL {
    let slug = browseSortSlug(sort: sort, descending: descending)
    return account.appendingPathComponent("browseSeries", isDirectory: true)
      .appendingPathComponent(libraryId, isDirectory: true)
      .appendingPathComponent(slug, isDirectory: true)
  }

  static func wipeBrowseSeriesSlug(
    account: URL, libraryId: String, sort: String, descending: Bool
  ) throws {
    let u = browseSeriesSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    if fm.fileExists(atPath: u.path) {
      try fm.removeItem(at: u)
    }
    try fm.createDirectory(at: u, withIntermediateDirectories: true)
  }

  static func saveBrowseSeriesPage(
    account: URL, libraryId: String, sort: String, descending: Bool, pageIndex: Int, data: Data
  ) throws {
    let dir = browseSeriesSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("page_\(pageIndex).json")
    try data.write(to: file, options: .atomic)
  }

  static func loadMergedBrowseSeries(
    account: URL,
    libraryId: String,
    sort: String,
    descending: Bool,
    decoder: JSONDecoder
  ) -> (items: [ABSLibrarySeriesListItem], total: Int, nextPage: Int)? {
    let dir = browseSeriesSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    guard fm.fileExists(atPath: dir.path) else { return nil }
    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    let pageFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("page_") }
    guard !pageFiles.isEmpty else { return nil }

    func pageIndex(_ url: URL) -> Int {
      let base = url.deletingPathExtension().lastPathComponent
      let parts = base.split(separator: "_")
      return Int(parts.last ?? "0") ?? 0
    }
    let sorted = pageFiles.sorted { pageIndex($0) < pageIndex($1) }

    var all: [ABSLibrarySeriesListItem] = []
    var total = 0
    for url in sorted {
      guard let data = try? Data(contentsOf: url) else { continue }
      guard let env = try? decoder.decode(ABSLibraryResultsPageEnvelope<ABSLibrarySeriesListItem>.self, from: data)
      else { continue }
      total = env.total
      all.append(contentsOf: env.results)
    }
    guard !sorted.isEmpty, !all.isEmpty else { return nil }
    return (all, total, sorted.count)
  }

  private static func browseEbooksSlugURL(account: URL, libraryId: String, sort: String, descending: Bool) -> URL {
    let slug = browseSortSlug(sort: sort, descending: descending)
    return account.appendingPathComponent("browseEbooks", isDirectory: true)
      .appendingPathComponent(libraryId, isDirectory: true)
      .appendingPathComponent("full", isDirectory: true)
      .appendingPathComponent(slug, isDirectory: true)
  }

  static func wipeBrowseEbooksSlug(
    account: URL, libraryId: String, sort: String, descending: Bool
  ) throws {
    let u = browseEbooksSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    if fm.fileExists(atPath: u.path) {
      try fm.removeItem(at: u)
    }
    try fm.createDirectory(at: u, withIntermediateDirectories: true)
  }

  static func saveBrowseEbooksPage(
    account: URL, libraryId: String, sort: String, descending: Bool, pageIndex: Int, data: Data
  ) throws {
    let dir = browseEbooksSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("page_\(pageIndex).json")
    try data.write(to: file, options: .atomic)
  }

  static func saveBrowseEbooksSupplementary(
    account: URL, libraryId: String, sort: String, descending: Bool, data: Data
  ) throws {
    let dir = browseEbooksSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent("supplementary.json"), options: .atomic)
  }

  static func loadMergedBrowseEbooks(
    account: URL,
    libraryId: String,
    sort: String,
    descending: Bool,
    decoder: JSONDecoder
  ) -> (books: [ABSBook], total: Int, nextPage: Int)? {
    let dir = browseEbooksSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    guard fm.fileExists(atPath: dir.path) else { return nil }
    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    let pageFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("page_") }
    guard !pageFiles.isEmpty else { return nil }

    func pageIndex(_ url: URL) -> Int {
      let base = url.deletingPathExtension().lastPathComponent
      let parts = base.split(separator: "_")
      return Int(parts.last ?? "0") ?? 0
    }
    let sorted = pageFiles.sorted { pageIndex($0) < pageIndex($1) }

    var all: [ABSBook] = []
    var total = 0
    for url in sorted {
      guard let data = try? Data(contentsOf: url) else { continue }
      guard let page = try? decoder.decode(ABSPage<ABSBook>.self, from: data) else { continue }
      total = page.total
      all.append(contentsOf: page.results.filter(\.isUsableEbookListRow))
    }
    let supURL = dir.appendingPathComponent("supplementary.json")
    if fm.fileExists(atPath: supURL.path),
      let sdata = try? Data(contentsOf: supURL),
      let spage = try? decoder.decode(ABSPage<ABSBook>.self, from: sdata)
    {
      var seen = Set(all.map(\.id))
      for book in spage.results.filter(\.isUsableEbookListRow) where seen.insert(book.id).inserted {
        all.append(book)
      }
    }
    guard !all.isEmpty else { return nil }
    return (all, total, sorted.count)
  }

  /// eBooks-Browse-Sektion: primäre eBooks (paginiert) und supplementäre getrennt zurückgeben.
  static func loadBrowseEbooksSplit(
    account: URL,
    libraryId: String,
    sort: String,
    descending: Bool,
    decoder: JSONDecoder
  ) -> (ebooks: [ABSBook], supplementary: [ABSBook], total: Int, nextPage: Int)? {
    let dir = browseEbooksSlugURL(account: account, libraryId: libraryId, sort: sort, descending: descending)
    guard fm.fileExists(atPath: dir.path) else { return nil }
    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    let pageFiles = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("page_") }

    func pageIndex(_ url: URL) -> Int {
      let base = url.deletingPathExtension().lastPathComponent
      let parts = base.split(separator: "_")
      return Int(parts.last ?? "0") ?? 0
    }
    let sorted = pageFiles.sorted { pageIndex($0) < pageIndex($1) }

    var ebooks: [ABSBook] = []
    var total = 0
    for url in sorted {
      guard let data = try? Data(contentsOf: url) else { continue }
      guard let page = try? decoder.decode(ABSPage<ABSBook>.self, from: data) else { continue }
      total = page.total
      ebooks.append(contentsOf: page.results.filter(\.isUsableEbookListRow))
    }
    var supplementary: [ABSBook] = []
    let supURL = dir.appendingPathComponent("supplementary.json")
    if fm.fileExists(atPath: supURL.path),
      let sdata = try? Data(contentsOf: supURL),
      let spage = try? decoder.decode(ABSPage<ABSBook>.self, from: sdata)
    {
      // Nur ergänzende eBooks zu Hörbüchern — reine eBook-Items gehören in die primäre Liste.
      supplementary = spage.results.filter(\.isPlayableAudiobook)
    }
    guard !ebooks.isEmpty || !supplementary.isEmpty else { return nil }
    return (ebooks, supplementary, total, sorted.count)
  }

  private static func browseCollectionsURL(account: URL, libraryId: String) -> URL {
    account.appendingPathComponent("browseCollections", isDirectory: true)
      .appendingPathComponent(libraryId, isDirectory: true)
  }

  static func saveBrowseCollections(account: URL, libraryId: String, data: Data) throws {
    let dir = browseCollectionsURL(account: account, libraryId: libraryId)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent("all.json"), options: .atomic)
  }

  static func loadBrowseCollections(
    account: URL,
    libraryId: String,
    decoder: JSONDecoder
  ) -> (items: [ABSLibraryCollectionListItem], total: Int)? {
    let u = browseCollectionsURL(account: account, libraryId: libraryId).appendingPathComponent("all.json")
    guard let data = try? Data(contentsOf: u) else { return nil }
    guard let env = try? decoder.decode(ABSLibraryResultsPageEnvelope<ABSLibraryCollectionListItem>.self, from: data)
    else { return nil }
    return (env.results, env.total)
  }

  private static func browseNarratorsURL(account: URL, libraryId: String) -> URL {
    account.appendingPathComponent("browseNarrators", isDirectory: true)
      .appendingPathComponent(libraryId, isDirectory: true)
  }

  private struct NarratorCoverMapFile: Codable {
    let entries: [String: String]
  }

  static func saveBrowseNarrators(account: URL, libraryId: String, narratorsJSON: Data, coverMap: [String: String]?)
    throws
  {
    let dir = browseNarratorsURL(account: account, libraryId: libraryId)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try narratorsJSON.write(to: dir.appendingPathComponent("narrators.json"), options: .atomic)
    if let coverMap, !coverMap.isEmpty {
      try saveBrowseNarratorCoverMap(account: account, libraryId: libraryId, coverMap: coverMap)
    }
  }

  static func saveBrowseNarratorCoverMap(account: URL, libraryId: String, coverMap: [String: String]) throws {
    let dir = browseNarratorsURL(account: account, libraryId: libraryId)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(NarratorCoverMapFile(entries: coverMap))
    try data.write(to: dir.appendingPathComponent("coverMap.json"), options: .atomic)
  }

  static func loadBrowseNarrators(
    account: URL,
    libraryId: String,
    decoder: JSONDecoder
  ) -> (narrators: [ABSLibraryNarratorListItem], coverMap: [String: String])? {
    let dir = browseNarratorsURL(account: account, libraryId: libraryId)
    let narrPath = dir.appendingPathComponent("narrators.json")
    guard let ndata = try? Data(contentsOf: narrPath) else { return nil }
    guard let env = try? decoder.decode(ABSLibraryNarratorsEnvelope.self, from: ndata) else { return nil }
    var map: [String: String] = [:]
    let mapURL = dir.appendingPathComponent("coverMap.json")
    if let mdata = try? Data(contentsOf: mapURL),
      let parsed = try? decoder.decode(NarratorCoverMapFile.self, from: mdata)
    {
      map = parsed.entries
    }
    return (env.narrators, map)
  }

  // MARK: - Podcast shows strip (library items, podcast rows)

  private static func podcastShowsFolderSlug(sortField: String, ascending: Bool) -> String {
    let raw = "podcastShows|\(sortField)|\(ascending)"
    let h = SHA256.hash(data: Data(raw.utf8))
    return h.map { String(format: "%02x", $0) }.joined()
  }

  private static func podcastShowsSlugURL(account: URL, libraryId: String, sortField: String, ascending: Bool) -> URL {
    let slug = podcastShowsFolderSlug(sortField: sortField, ascending: ascending)
    return account.appendingPathComponent("podcastShows", isDirectory: true)
      .appendingPathComponent(libraryId, isDirectory: true)
      .appendingPathComponent(slug, isDirectory: true)
  }

  static func wipePodcastShowsSlug(
    account: URL, libraryId: String, sortField: String, ascending: Bool
  ) throws {
    let u = podcastShowsSlugURL(account: account, libraryId: libraryId, sortField: sortField, ascending: ascending)
    if fm.fileExists(atPath: u.path) {
      try fm.removeItem(at: u)
    }
    try fm.createDirectory(at: u, withIntermediateDirectories: true)
  }

  static func savePodcastShows(
    account: URL, libraryId: String, sortField: String, ascending: Bool, data: Data
  ) throws {
    let dir = podcastShowsSlugURL(account: account, libraryId: libraryId, sortField: sortField, ascending: ascending)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent("shows.json"), options: .atomic)
  }

  static func loadPodcastShows(
    account: URL,
    libraryId: String,
    sortField: String,
    ascending: Bool,
    decoder: JSONDecoder
  ) -> [ABSBook]? {
    let u =
      podcastShowsSlugURL(account: account, libraryId: libraryId, sortField: sortField, ascending: ascending)
      .appendingPathComponent("shows.json")
    guard let data = try? Data(contentsOf: u) else { return nil }
    guard let page = try? decoder.decode(ABSPage<ABSBook>.self, from: data) else { return nil }
    let rows = page.results.filter(\.isListablePodcastLibraryItem)
    return rows.isEmpty ? nil : rows
  }

  // MARK: - Listening stats (`api/me/listening-stats`)

  private static let listeningStatsResponseFile = "listeningStats.response.json"

  static func saveListeningStatsResponse(account: URL, data: Data) throws {
    try data.write(to: account.appendingPathComponent(listeningStatsResponseFile), options: .atomic)
  }

  static func loadListeningStatsResponse(account: URL) -> Data? {
    let u = account.appendingPathComponent(listeningStatsResponseFile)
    guard fm.fileExists(atPath: u.path) else { return nil }
    return try? Data(contentsOf: u)
  }

  static func listeningStatsResponseModificationDate(account: URL) -> Date? {
    let u = account.appendingPathComponent(listeningStatsResponseFile)
    guard fm.fileExists(atPath: u.path) else { return nil }
    return try? fm.attributesOfItem(atPath: u.path)[.modificationDate] as? Date
  }

  private static let listeningAchievementsSnapshotFile = "listeningAchievements.snapshot.json"

  static func saveListeningAchievementsSnapshot(account: URL, snapshot: ListeningAchievementsSnapshot) throws {
    let data = try ABSJSON.encoder().encode(snapshot)
    try data.write(
      to: account.appendingPathComponent(listeningAchievementsSnapshotFile),
      options: .atomic
    )
  }

  static func loadListeningAchievementsSnapshot(
    account: URL,
    decoder: JSONDecoder = ABSJSON.decoder()
  ) -> ListeningAchievementsSnapshot? {
    let u = account.appendingPathComponent(listeningAchievementsSnapshotFile)
    guard fm.fileExists(atPath: u.path), let data = try? Data(contentsOf: u) else { return nil }
    return try? decoder.decode(ListeningAchievementsSnapshot.self, from: data)
  }

  private static let listeningOneTimeAchievementsSnapshotFile = "listeningOneTimeAchievements.snapshot.json"

  static func saveListeningOneTimeAchievementsSnapshot(
    account: URL,
    snapshot: ListeningOneTimeAchievementsSnapshot
  ) throws {
    let data = try ABSJSON.encoder().encode(snapshot)
    try data.write(
      to: account.appendingPathComponent(listeningOneTimeAchievementsSnapshotFile),
      options: .atomic
    )
  }

  static func loadListeningOneTimeAchievementsSnapshot(
    account: URL,
    decoder: JSONDecoder = ABSJSON.decoder()
  ) -> ListeningOneTimeAchievementsSnapshot? {
    let u = account.appendingPathComponent(listeningOneTimeAchievementsSnapshotFile)
    guard fm.fileExists(atPath: u.path), let data = try? Data(contentsOf: u) else { return nil }
    return try? decoder.decode(ListeningOneTimeAchievementsSnapshot.self, from: data)
  }
}
