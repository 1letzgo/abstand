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
      Picker("Sort by", selection: sortFieldBinding) {
        ForEach(Array(Field.allCases)) { field in
          Text(field.menuTitle).tag(field)
        }
      }
      if !sortField.suppressesSortOrderPicker {
        Picker("Order", selection: sortDescendingBinding) {
          Label("Ascending", systemImage: "arrow.up").tag(false)
          Label("Descending", systemImage: "arrow.down").tag(true)
        }
      }
    } label: {
      Label("Sort", systemImage: "arrow.up.arrow.down")
    }
  }

  private var sortFieldBinding: Binding<Field> {
    Binding(get: { sortField }, set: onSortFieldChange)
  }

  private var sortDescendingBinding: Binding<Bool> {
    Binding(get: { sortDescending }, set: onSortDescendingChange)
  }
}

typealias BooksCatalogSortToolbarMenu = AbstandCatalogSortToolbarMenu<CatalogSortField>
typealias BrowseAuthorsSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseAuthorsSortField>
typealias BrowseNarratorsSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseNarratorsSortField>
typealias BrowseSeriesSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseSeriesSortField>
typealias BrowseCollectionsSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseCollectionsSortField>
typealias BrowseFacetSortToolbarMenu = AbstandCatalogSortToolbarMenu<BooksBrowseFacetSortField>
typealias PodcastCatalogSortToolbarMenu = AbstandCatalogSortToolbarMenu<PodcastCatalogSortField>
