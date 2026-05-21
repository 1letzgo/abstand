import Combine
import SwiftUI

struct BooksBrowseCollectionNav: Hashable, Identifiable {
  let id: String
  let title: String
}

// MARK: - Bücher-Tab: Toolbar nur bei Sort/Filter-Änderungen (nicht bei Playback-Ticks)

@MainActor
final class BooksLibraryToolbarState: ObservableObject {
  @Published var booksBrowseSection: BooksBrowseSection = .books
  @Published var catalogSortField: CatalogSortField = .addedAt
  @Published var catalogSortDescending: Bool = true
  @Published var libraryCatalogQuickFilter: LibraryCatalogQuickFilter?
  @Published var isLibraryCatalogFiltered = false
  @Published var isAllFilterActive = true
  @Published var browseAuthorsSortField: BooksBrowseAuthorsSortField = .name
  @Published var browseAuthorsSortDescending: Bool = true
  @Published var browseNarratorsSortField: BooksBrowseNarratorsSortField = .name
  @Published var browseNarratorsSortDescending: Bool = true
  @Published var browseSeriesSortField: BooksBrowseSeriesSortField = .name
  @Published var browseSeriesSortDescending: Bool = true
  @Published var browseCollectionsSortField: BooksBrowseCollectionsSortField = .name
  @Published var browseCollectionsSortDescending: Bool = true

  private weak var model: AppModel?
  private var cancellables = Set<AnyCancellable>()

  func attach(_ model: AppModel) {
    self.model = model
    cancellables.removeAll()
    sync(from: model)

    let publishers: [AnyPublisher<Void, Never>] = [
      model.$booksBrowseSection.map { _ in () }.eraseToAnyPublisher(),
      model.$catalogSortField.map { _ in () }.eraseToAnyPublisher(),
      model.$catalogSortDescending.map { _ in () }.eraseToAnyPublisher(),
      model.$libraryCatalogQuickFilter.map { _ in () }.eraseToAnyPublisher(),
      model.$activeLibraryFilter.map { _ in () }.eraseToAnyPublisher(),
      model.$browseAuthorsSortField.map { _ in () }.eraseToAnyPublisher(),
      model.$browseAuthorsSortDescending.map { _ in () }.eraseToAnyPublisher(),
      model.$browseNarratorsSortField.map { _ in () }.eraseToAnyPublisher(),
      model.$browseNarratorsSortDescending.map { _ in () }.eraseToAnyPublisher(),
      model.$browseSeriesSortField.map { _ in () }.eraseToAnyPublisher(),
      model.$browseSeriesSortDescending.map { _ in () }.eraseToAnyPublisher(),
      model.$browseCollectionsSortField.map { _ in () }.eraseToAnyPublisher(),
      model.$browseCollectionsSortDescending.map { _ in () }.eraseToAnyPublisher(),
    ]

    Publishers.MergeMany(publishers)
      .receive(on: RunLoop.main)
      .sink { [weak self] in
        guard let self, let model = self.model else { return }
        self.sync(from: model)
      }
      .store(in: &cancellables)
  }

  func detach() {
    cancellables.removeAll()
    model = nil
  }

  private func sync(from model: AppModel) {
    setIfChanged(\.booksBrowseSection, model.booksBrowseSection)
    setIfChanged(\.catalogSortField, model.catalogSortField)
    setIfChanged(\.catalogSortDescending, model.catalogSortDescending)
    setIfChanged(\.libraryCatalogQuickFilter, model.libraryCatalogQuickFilter)
    setIfChanged(\.isLibraryCatalogFiltered, model.isLibraryCatalogFiltered)
    let allActive =
      model.libraryCatalogQuickFilter == nil
      && (model.activeLibraryFilter?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    setIfChanged(\.isAllFilterActive, allActive)
    setIfChanged(\.browseAuthorsSortField, model.browseAuthorsSortField)
    setIfChanged(\.browseAuthorsSortDescending, model.browseAuthorsSortDescending)
    setIfChanged(\.browseNarratorsSortField, model.browseNarratorsSortField)
    setIfChanged(\.browseNarratorsSortDescending, model.browseNarratorsSortDescending)
    setIfChanged(\.browseSeriesSortField, model.browseSeriesSortField)
    setIfChanged(\.browseSeriesSortDescending, model.browseSeriesSortDescending)
    setIfChanged(\.browseCollectionsSortField, model.browseCollectionsSortField)
    setIfChanged(\.browseCollectionsSortDescending, model.browseCollectionsSortDescending)
  }

  private func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<BooksLibraryToolbarState, T>, _ value: T) {
    if self[keyPath: keyPath] != value {
      self[keyPath: keyPath] = value
    }
  }

  func applyCatalogSortField(_ field: CatalogSortField) {
    guard let model, model.catalogSortField != field else { return }
    model.catalogSortField = field
    model.scheduleBooksToolbarSortReload(.mainCatalog)
  }

  func applyCatalogSortDescending(_ descending: Bool) {
    guard let model, model.catalogSortDescending != descending else { return }
    model.catalogSortDescending = descending
    model.scheduleBooksToolbarSortReload(.mainCatalog)
  }

  func clearCatalogFilter() {
    model?.clearCatalogFilter()
  }

  func applyLibraryCatalogQuickFilter(_ filter: LibraryCatalogQuickFilter) {
    model?.applyLibraryCatalogQuickFilter(filter)
  }

  func applyBrowseAuthorsSortField(_ field: BooksBrowseAuthorsSortField) {
    guard let model, model.browseAuthorsSortField != field else { return }
    model.browseAuthorsSortField = field
    model.scheduleBooksToolbarSortReload(.browseAuthors)
  }

  func applyBrowseAuthorsSortDescending(_ descending: Bool) {
    guard let model, model.browseAuthorsSortDescending != descending else { return }
    model.browseAuthorsSortDescending = descending
    model.scheduleBooksToolbarSortReload(.browseAuthors)
  }

  func applyBrowseNarratorsSortField(_ field: BooksBrowseNarratorsSortField) {
    guard let model, model.browseNarratorsSortField != field else { return }
    model.browseNarratorsSortField = field
    model.resortBrowseNarratorsDisplay()
  }

  func applyBrowseNarratorsSortDescending(_ descending: Bool) {
    guard let model, model.browseNarratorsSortDescending != descending else { return }
    model.browseNarratorsSortDescending = descending
    model.resortBrowseNarratorsDisplay()
  }

  func applyBrowseSeriesSortField(_ field: BooksBrowseSeriesSortField) {
    guard let model, model.browseSeriesSortField != field else { return }
    model.browseSeriesSortField = field
    model.scheduleBooksToolbarSortReload(.browseSeries)
  }

  func applyBrowseSeriesSortDescending(_ descending: Bool) {
    guard let model, model.browseSeriesSortDescending != descending else { return }
    model.browseSeriesSortDescending = descending
    model.scheduleBooksToolbarSortReload(.browseSeries)
  }

  func applyBrowseCollectionsSortField(_ field: BooksBrowseCollectionsSortField) {
    guard let model, model.browseCollectionsSortField != field else { return }
    model.browseCollectionsSortField = field
    model.resortBrowseCollectionsDisplay()
  }

  func applyBrowseCollectionsSortDescending(_ descending: Bool) {
    guard let model, model.browseCollectionsSortDescending != descending else { return }
    model.browseCollectionsSortDescending = descending
    model.resortBrowseCollectionsDisplay()
  }
}

@MainActor
final class PodcastCatalogToolbarState: ObservableObject {
  @Published var sortField: PodcastCatalogSortField = .addedAt
  @Published var sortDescending: Bool = true

  private weak var model: AppModel?
  private var cancellables = Set<AnyCancellable>()

  func attach(_ model: AppModel) {
    self.model = model
    cancellables.removeAll()
    sync(from: model)

    Publishers.MergeMany(
      model.$podcastCatalogSortField.map { _ in () }.eraseToAnyPublisher(),
      model.$podcastCatalogSortDescending.map { _ in () }.eraseToAnyPublisher()
    )
    .receive(on: RunLoop.main)
    .sink { [weak self] in
      guard let self, let model = self.model else { return }
      self.sync(from: model)
    }
    .store(in: &cancellables)
  }

  func detach() {
    cancellables.removeAll()
    model = nil
  }

  private func sync(from model: AppModel) {
    if sortField != model.podcastCatalogSortField { sortField = model.podcastCatalogSortField }
    if sortDescending != model.podcastCatalogSortDescending {
      sortDescending = model.podcastCatalogSortDescending
    }
  }

  func applySortField(_ field: PodcastCatalogSortField) {
    guard let model, model.podcastCatalogSortField != field else { return }
    model.podcastCatalogSortField = field
    model.schedulePodcastCatalogSortReload()
  }

  func applySortDescending(_ descending: Bool) {
    guard let model, model.podcastCatalogSortDescending != descending else { return }
    model.podcastCatalogSortDescending = descending
    model.schedulePodcastCatalogSortReload()
  }
}

// MARK: - Toolbar (ToolbarItemGroup → Sort + Filter nebeneinander)

/// Wert-Snapshot für `ToolbarContent` — kein `@ObservedObject`, damit offene Menüs bei Katalog-Ticks stabil bleiben.
struct BooksLibraryToolbarSnapshot: Equatable {
  var booksBrowseSection: BooksBrowseSection
  var catalogSortField: CatalogSortField
  var catalogSortDescending: Bool
  var libraryCatalogQuickFilter: LibraryCatalogQuickFilter?
  var isLibraryCatalogFiltered: Bool
  var isAllFilterActive: Bool
  var browseAuthorsSortField: BooksBrowseAuthorsSortField
  var browseAuthorsSortDescending: Bool
  var browseNarratorsSortField: BooksBrowseNarratorsSortField
  var browseNarratorsSortDescending: Bool
  var browseSeriesSortField: BooksBrowseSeriesSortField
  var browseSeriesSortDescending: Bool
  var browseCollectionsSortField: BooksBrowseCollectionsSortField
  var browseCollectionsSortDescending: Bool

  @MainActor
  init(_ state: BooksLibraryToolbarState) {
    booksBrowseSection = state.booksBrowseSection
    catalogSortField = state.catalogSortField
    catalogSortDescending = state.catalogSortDescending
    libraryCatalogQuickFilter = state.libraryCatalogQuickFilter
    isLibraryCatalogFiltered = state.isLibraryCatalogFiltered
    isAllFilterActive = state.isAllFilterActive
    browseAuthorsSortField = state.browseAuthorsSortField
    browseAuthorsSortDescending = state.browseAuthorsSortDescending
    browseNarratorsSortField = state.browseNarratorsSortField
    browseNarratorsSortDescending = state.browseNarratorsSortDescending
    browseSeriesSortField = state.browseSeriesSortField
    browseSeriesSortDescending = state.browseSeriesSortDescending
    browseCollectionsSortField = state.browseCollectionsSortField
    browseCollectionsSortDescending = state.browseCollectionsSortDescending
  }
}

struct BooksLibraryToolbarContent: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  @MainActor
  init(toolbarState: BooksLibraryToolbarState) {
    self.toolbarState = toolbarState
    snapshot = BooksLibraryToolbarSnapshot(toolbarState)
  }

  var body: some ToolbarContent {
    switch snapshot.booksBrowseSection {
    case .books:
      ToolbarItemGroup(placement: .topBarTrailing) {
        BooksCatalogFilterToolbarMenu(
          isActive: snapshot.isLibraryCatalogFiltered,
          libraryCatalogQuickFilter: snapshot.libraryCatalogQuickFilter,
          isAllFilterActive: snapshot.isAllFilterActive,
          onClear: { toolbarState.clearCatalogFilter() },
          onSelect: { toolbarState.applyLibraryCatalogQuickFilter($0) }
        )
        .equatable()
        BooksCatalogSortToolbarMenu(
          sortField: snapshot.catalogSortField,
          sortDescending: snapshot.catalogSortDescending,
          onSortFieldChange: { toolbarState.applyCatalogSortField($0) },
          onSortDescendingChange: { toolbarState.applyCatalogSortDescending($0) }
        )
        .equatable()
      }
    case .author:
      ToolbarItemGroup(placement: .topBarTrailing) {
        BrowseAuthorsSortToolbarMenu(
          sortField: snapshot.browseAuthorsSortField,
          sortDescending: snapshot.browseAuthorsSortDescending,
          onSortFieldChange: { toolbarState.applyBrowseAuthorsSortField($0) },
          onSortDescendingChange: { toolbarState.applyBrowseAuthorsSortDescending($0) }
        )
        .equatable()
      }
    case .narrators:
      ToolbarItemGroup(placement: .topBarTrailing) {
        BrowseNarratorsSortToolbarMenu(
          sortField: snapshot.browseNarratorsSortField,
          sortDescending: snapshot.browseNarratorsSortDescending,
          onSortFieldChange: { toolbarState.applyBrowseNarratorsSortField($0) },
          onSortDescendingChange: { toolbarState.applyBrowseNarratorsSortDescending($0) }
        )
        .equatable()
      }
    case .series:
      ToolbarItemGroup(placement: .topBarTrailing) {
        BrowseSeriesSortToolbarMenu(
          sortField: snapshot.browseSeriesSortField,
          sortDescending: snapshot.browseSeriesSortDescending,
          onSortFieldChange: { toolbarState.applyBrowseSeriesSortField($0) },
          onSortDescendingChange: { toolbarState.applyBrowseSeriesSortDescending($0) }
        )
        .equatable()
      }
    case .collections:
      ToolbarItemGroup(placement: .topBarTrailing) {
        BrowseCollectionsSortToolbarMenu(
          sortField: snapshot.browseCollectionsSortField,
          sortDescending: snapshot.browseCollectionsSortDescending,
          onSortFieldChange: { toolbarState.applyBrowseCollectionsSortField($0) },
          onSortDescendingChange: { toolbarState.applyBrowseCollectionsSortDescending($0) }
        )
        .equatable()
      }
    }
  }
}

/// Navigation + Toolbar; Katalog kommt als `let model`-Child (ohne `@EnvironmentObject` am Shell).
struct BooksLibraryTabShell<Catalog: View>: View {
  @ObservedObject var toolbarState: BooksLibraryToolbarState
  @Binding var collectionNav: BooksBrowseCollectionNav?
  @ViewBuilder var catalog: () -> Catalog
  var collectionDetail: (BooksBrowseCollectionNav) -> AnyView

  var body: some View {
    NavigationStack {
      catalog()
        .abstandTabScreenChrome()
        .navigationTitle(AppModel.MainTab.library.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
          BooksLibraryToolbarContent(toolbarState: toolbarState)
        }
        .navigationDestination(item: $collectionNav) { nav in
          collectionDetail(nav)
        }
    }
  }
}

struct PodcastCatalogTabShell<Catalog: View>: View {
  @ObservedObject var toolbarState: PodcastCatalogToolbarState
  @ViewBuilder var catalog: () -> Catalog

  var body: some View {
    NavigationStack {
      catalog()
        .abstandTabScreenChrome()
        .navigationTitle(AppModel.MainTab.podcasts.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
          ToolbarItem(id: "podcastCatalogSort", placement: .topBarTrailing) {
            PodcastCatalogSortToolbarSnapshot(toolbarState: toolbarState)
              .equatable()
          }
        }
    }
  }
}

/// Wert-Snapshot — offenes Sort-Menü bleibt bei Katalog-Ticks stabil.
struct PodcastCatalogSortToolbarSnapshot: View, Equatable {
  let sortField: PodcastCatalogSortField
  let sortDescending: Bool
  let toolbarState: PodcastCatalogToolbarState

  init(toolbarState: PodcastCatalogToolbarState) {
    self.toolbarState = toolbarState
    sortField = toolbarState.sortField
    sortDescending = toolbarState.sortDescending
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sortField == rhs.sortField && lhs.sortDescending == rhs.sortDescending
  }

  var body: some View {
    PodcastCatalogSortToolbarMenu(
      sortField: sortField,
      sortDescending: sortDescending,
      onSortFieldChange: { toolbarState.applySortField($0) },
      onSortDescendingChange: { toolbarState.applySortDescending($0) }
    )
  }
}
