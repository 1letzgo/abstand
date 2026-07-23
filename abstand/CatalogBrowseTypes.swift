import Foundation

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

