import SwiftUI

/// Filter-Button neben Sort im Bücher-Katalog (nur Schnellfilter).
/// Equatable: kein Re-Render bei unrelated `AppModel`-Updates (verhindert Menü-Flackern).
struct BooksCatalogFilterToolbarMenu: View, Equatable {
  var isActive: Bool
  var libraryCatalogQuickFilter: LibraryCatalogQuickFilter?
  var isAllFilterActive: Bool
  var onClear: () -> Void
  var onSelect: (LibraryCatalogQuickFilter) -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.isActive == rhs.isActive
      && lhs.libraryCatalogQuickFilter == rhs.libraryCatalogQuickFilter
      && lhs.isAllFilterActive == rhs.isAllFilterActive
  }

  var body: some View {
    Menu {
      filterRow(title: "All", systemImage: "line.3.horizontal.decrease.circle", isSelected: isAllFilterActive) {
        onClear()
      }

      filterButton(.inProgress)
      filterButton(.finished)
      filterButton(.notStarted)

      Divider()

      filterButton(.ebook)
      filterButton(.downloaded)
    } label: {
      Image(
        systemName: isActive
          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
      )
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(isActive ? AppTheme.accent : Color.primary)
    }
  }

  private func filterButton(_ filter: LibraryCatalogQuickFilter) -> some View {
    filterRow(
      title: filter.menuTitle,
      systemImage: filter.menuSystemImage,
      isSelected: libraryCatalogQuickFilter == filter
    ) {
      onSelect(filter)
    }
  }

  private func filterRow(
    title: String,
    systemImage: String,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Image(systemName: systemImage)
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
        Text(title)
          .foregroundStyle(AppTheme.textPrimary)
        Spacer(minLength: 8)
        if isSelected {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(AppTheme.accent)
        }
      }
    }
    .tint(AppTheme.textPrimary)
  }
}
