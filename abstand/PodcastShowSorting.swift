import Foundation

/// Sortierung der Sendungs-Leiste im Podcasts-Tab.
///
/// Die Server-Reihenfolge (`GET …/items?sort=`) ist nur ein Vorschlag: Verbindlich ist diese reine
/// Funktion. Sie greift sofort nach der Auswahl im Menü, auf gecachte Zeilen (offline, beliebiger
/// zuvor gespeicherter Sortierschlüssel) und auf jede Server-Antwort — dadurch sieht die Leiste
/// immer gleich aus, egal woher die Zeilen kommen. Android: `PodcastShowSorting.kt` (gleiche Regeln).
///
/// Regeln: fehlende Werte (kein Autor, unbekannte Folgenzahl, kein Datum) stehen in beiden Richtungen
/// hinten; Gleichstand → Titel aufsteigend → ursprüngliche Reihenfolge (stabil). `.random` lässt die
/// Reihenfolge unverändert (die Mischung kommt vom Server bzw. aus dem Cache).
enum PodcastShowSorting {
  static func sorted(
    _ shows: [ABSBook],
    by field: PodcastCatalogSortField,
    descending: Bool,
    ignoreTitlePrefix: Bool = false
  ) -> [ABSBook] {
    guard field != .random, shows.count > 1 else { return shows }
    let keyed = shows.enumerated().map { offset, show in
      (offset: offset, show: show, key: sortKey(show, field: field, ignoreTitlePrefix: ignoreTitlePrefix),
       title: titleKey(show, ignoreTitlePrefix: ignoreTitlePrefix))
    }
    return keyed.sorted { a, b in
      switch (a.key, b.key) {
      case (.missing, .missing):
        break
      case (.missing, _):
        return false
      case (_, .missing):
        return true
      default:
        let order = compare(a.key, b.key)
        if order != .orderedSame {
          return descending ? order == .orderedDescending : order == .orderedAscending
        }
      }
      let titleOrder = compareText(a.title, b.title)
      if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
      return a.offset < b.offset
    }
    .map(\.show)
  }

  /// Anzahl Folgen einer Sendung: `media.numEpisodes` (minified Katalog), sonst geladene Folgen.
  static func episodeCount(_ show: ABSBook) -> Int? {
    show.media.numEpisodes ?? show.media.podcastEpisodes?.count
  }

  enum Key {
    case text(String)
    case number(Double)
    case missing
  }

  static func sortKey(_ show: ABSBook, field: PodcastCatalogSortField, ignoreTitlePrefix: Bool) -> Key {
    switch field {
    case .title:
      return .text(titleKey(show, ignoreTitlePrefix: ignoreTitlePrefix))
    case .author:
      let author = show.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
      return author.isEmpty || author == "—" ? .missing : .text(author)
    case .numEpisodes:
      return episodeCount(show).map { .number(Double($0)) } ?? .missing
    case .addedAt:
      return show.addedAt.map { .number($0.timeIntervalSince1970) } ?? .missing
    case .updatedAt:
      return show.updatedAt.map { .number($0.timeIntervalSince1970) } ?? .missing
    case .size:
      return show.media.size.map { .number(Double($0)) } ?? .missing
    case .random:
      return .missing
    }
  }

  static func titleKey(_ show: ABSBook, ignoreTitlePrefix: Bool) -> String {
    if ignoreTitlePrefix,
      let stripped = show.media.metadata.titleIgnorePrefix?.trimmingCharacters(in: .whitespacesAndNewlines),
      !stripped.isEmpty
    {
      return stripped
    }
    return show.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func compare(_ a: Key, _ b: Key) -> ComparisonResult {
    switch (a, b) {
    case let (.text(x), .text(y)):
      return compareText(x, y)
    case let (.number(x), .number(y)):
      return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
    default:
      return .orderedSame
    }
  }

  /// Groß-/Kleinschreibung und Akzente egal, Zahlen numerisch („Folge 2“ < „Folge 10“).
  static func compareText(_ a: String, _ b: String) -> ComparisonResult {
    a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .numeric])
  }
}
