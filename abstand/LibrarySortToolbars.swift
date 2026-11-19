import SwiftUI

// MARK: - Sort-Menü (Katalog / Browse / Podcasts)

/// Sortierfeld für Toolbar-Menüs — `menuTitle` pro Enum, optional ohne Auf-/Ab-Picker.
protocol AbstandSortMenuField: CaseIterable, Identifiable, Hashable {
  var menuTitle: String { get }
  /// Bei `.random` o. Ä. keinen Auf-/Ab-Picker anzeigen.
  var suppressesSortOrderPicker: Bool { get }
}

extension AbstandSortMenuField {
  var suppressesSortOrderPicker: Bool { false }
}

/// Einheitliches Sort-Toolbar-Menü; Equatable nur über Feld + Richtung (kein Closure-Vergleich).
struct AbstandCatalogSortToolbarMenu<Field: AbstandSortMenuField>: View, Equatable {
  var sortField: Field
  var sortDescending: Bool
  var onSortFieldChange: (Field) -> Void
  var onSortDescendingChange: (Bool) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sortField == rhs.sortField && lhs.sortDescending == rhs.sortDescending
  }

  var body: some View {
    Menu {
      AbstandSortMenuPickers(
        sortField: sortField,
        sortDescending: sortDescending,
        onSortFieldChange: onSortFieldChange,
        onSortDescendingChange: onSortDescendingChange
      )
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }
}

/// Inhalt eines Sort-Menüs: Feld-Picker + (außer bei `.random` o. Ä.) Auf-/Ab-Picker.
struct AbstandSortMenuPickers<Field: AbstandSortMenuField>: View {
  var sortField: Field
  var sortDescending: Bool
  var onSortFieldChange: (Field) -> Void
  var onSortDescendingChange: (Bool) -> Void

  var body: some View {
    Picker("Sort by", selection: Binding(get: { sortField }, set: onSortFieldChange)) {
      ForEach(Array(Field.allCases)) { field in
        Text(field.menuTitle).tag(field)
      }
    }
    if !sortField.suppressesSortOrderPicker {
      Picker("Order", selection: Binding(get: { sortDescending }, set: onSortDescendingChange)) {
        Label("Ascending", systemImage: "arrow.up").tag(false)
        Label("Descending", systemImage: "arrow.down").tag(true)
      }
    }
  }
}

/// Podcasts-Tab mit gewählter Sendung: Folgen-Sortierung plus Untermenü für die Sendungs-Leiste —
/// die Leiste bleibt sichtbar, ihre Sortierung muss deshalb auch hier erreichbar sein.
/// Equatable nur über die vier Werte (kein Closure-Vergleich), damit das offene Menü stabil bleibt.
struct PodcastShowEpisodeSortToolbarMenu: View, Equatable {
  var episodeSortField: PodcastEpisodeSortField
  var episodeSortDescending: Bool
  var showSortField: PodcastCatalogSortField
  var showSortDescending: Bool
  var onEpisodeSortFieldChange: (PodcastEpisodeSortField) -> Void
  var onEpisodeSortDescendingChange: (Bool) -> Void
  var onShowSortFieldChange: (PodcastCatalogSortField) -> Void
  var onShowSortDescendingChange: (Bool) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.episodeSortField == rhs.episodeSortField
      && lhs.episodeSortDescending == rhs.episodeSortDescending
      && lhs.showSortField == rhs.showSortField
      && lhs.showSortDescending == rhs.showSortDescending
  }

  var body: some View {
    Menu {
      Section("Episodes") {
        AbstandSortMenuPickers(
          sortField: episodeSortField,
          sortDescending: episodeSortDescending,
          onSortFieldChange: onEpisodeSortFieldChange,
          onSortDescendingChange: onEpisodeSortDescendingChange
        )
      }
      Menu {
        AbstandSortMenuPickers(
          sortField: showSortField,
          sortDescending: showSortDescending,
          onSortFieldChange: onShowSortFieldChange,
          onSortDescendingChange: onShowSortDescendingChange
        )
      } label: {
        Label("Sort shows", systemImage: "mic")
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }
}

typealias BooksCatalogSortToolbarMenu = AbstandCatalogSortToolbarMenu<CatalogSortField>
typealias BrowseAuthorsSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseAuthorsSortField>
typealias BrowseNarratorsSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseNarratorsSortField>
typealias BrowseSeriesSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseSeriesSortField>
typealias BrowseCollectionsSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseCollectionsSortField>
typealias BrowseFacetSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseFacetSortField>
typealias PodcastCatalogSortToolbarMenu = AbstandCatalogSortToolbarMenu<PodcastCatalogSortField>
typealias PodcastEpisodeSortToolbarMenu = AbstandCatalogSortToolbarMenu<PodcastEpisodeSortField>
