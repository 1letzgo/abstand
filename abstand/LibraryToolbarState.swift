import Combine
import SwiftUI

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
  @Published var browseGenresSortField: BooksBrowseFacetSortField = .name
  @Published var browseGenresSortDescending: Bool = true
  @Published var browseTagsSortField: BooksBrowseFacetSortField = .name
  @Published var browseTagsSortDescending: Bool = true

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
      model.$browseGenresSortField.map { _ in () }.eraseToAnyPublisher(),
      model.$browseGenresSortDescending.map { _ in () }.eraseToAnyPublisher(),
      model.$browseTagsSortField.map { _ in () }.eraseToAnyPublisher(),
      model.$browseTagsSortDescending.map { _ in () }.eraseToAnyPublisher(),
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

  /// Nach Account-Wechsel: lokale Toolbar-Zustände zurücksetzen (neuer attach folgt).
  func resetForAccountSwitch() {
    detach()
    booksBrowseSection = .books
    catalogSortField = .addedAt
    catalogSortDescending = true
    libraryCatalogQuickFilter = nil
    isLibraryCatalogFiltered = false
    isAllFilterActive = true
    browseAuthorsSortField = .name
    browseAuthorsSortDescending = true
    browseNarratorsSortField = .name
    browseNarratorsSortDescending = true
    browseSeriesSortField = .name
    browseSeriesSortDescending = true
    browseCollectionsSortField = .name
    browseCollectionsSortDescending = true
    browseGenresSortField = .name
    browseGenresSortDescending = true
    browseTagsSortField = .name
    browseTagsSortDescending = true
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
    setIfChanged(\.browseGenresSortField, model.browseGenresSortField)
    setIfChanged(\.browseGenresSortDescending, model.browseGenresSortDescending)
    setIfChanged(\.browseTagsSortField, model.browseTagsSortField)
    setIfChanged(\.browseTagsSortDescending, model.browseTagsSortDescending)
  }

  private func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<BooksLibraryToolbarState, T>, _ value: T) {
    if self[keyPath: keyPath] != value {
      self[keyPath: keyPath] = value
    }
  }

  private func isEbooksBrowseSection(_ section: BooksBrowseSection) -> Bool {
    section == .ebooks || section == .ebooksSupplementary
  }

  func applyCatalogSortField(_ field: CatalogSortField) {
    guard let model, model.catalogSortField != field else { return }
    model.catalogSortField = field
    let kind: AppModel.BooksToolbarSortReloadKind =
      isEbooksBrowseSection(model.booksBrowseSection) ? .browseEbooks : .mainCatalog
    model.scheduleBooksToolbarSortReload(kind)
  }

  func applyCatalogSortDescending(_ descending: Bool) {
    guard let model, model.catalogSortDescending != descending else { return }
    model.catalogSortDescending = descending
    let kind: AppModel.BooksToolbarSortReloadKind =
      isEbooksBrowseSection(model.booksBrowseSection) ? .browseEbooks : .mainCatalog
    model.scheduleBooksToolbarSortReload(kind)
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

  func applyBrowseGenresSortField(_ field: BooksBrowseFacetSortField) {
    guard let model, model.browseGenresSortField != field else { return }
    model.browseGenresSortField = field
    model.resortBrowseGenresDisplay()
  }

  func applyBrowseGenresSortDescending(_ descending: Bool) {
    guard let model, model.browseGenresSortDescending != descending else { return }
    model.browseGenresSortDescending = descending
    model.resortBrowseGenresDisplay()
  }

  func applyBrowseTagsSortField(_ field: BooksBrowseFacetSortField) {
    guard let model, model.browseTagsSortField != field else { return }
    model.browseTagsSortField = field
    model.resortBrowseTagsDisplay()
  }

  func applyBrowseTagsSortDescending(_ descending: Bool) {
    guard let model, model.browseTagsSortDescending != descending else { return }
    model.browseTagsSortDescending = descending
    model.resortBrowseTagsDisplay()
  }
}

@MainActor
final class PodcastCatalogToolbarState: ObservableObject {
  @Published var sortField: PodcastCatalogSortField = .addedAt
  @Published var sortDescending: Bool = true
  @Published private(set) var isServerRoot = false
  @Published private(set) var isNetworkReachable = true
  @Published private(set) var hasPodcastLibrary = false
  @Published private(set) var selectedShowId: String?
  @Published private(set) var selectedShowTitle = ""

  private weak var model: AppModel?
  private var cancellables = Set<AnyCancellable>()

  func attach(_ model: AppModel) {
    self.model = model
    cancellables.removeAll()
    sync(from: model)

    Publishers.MergeMany(
      model.$podcastCatalogSortField.map { _ in () }.eraseToAnyPublisher(),
      model.$podcastCatalogSortDescending.map { _ in () }.eraseToAnyPublisher(),
      model.$isServerRoot.map { _ in () }.eraseToAnyPublisher(),
      model.$isNetworkReachable.map { _ in () }.eraseToAnyPublisher(),
      model.$selectedPodcastLibrary.map { _ in () }.eraseToAnyPublisher(),
      model.$podcastSelectedShowId.map { _ in () }.eraseToAnyPublisher(),
      model.$podcastShows.map { _ in () }.eraseToAnyPublisher()
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

  /// Nach Account-Wechsel: lokale Toolbar-Zustände zurücksetzen (neuer attach folgt).
  func resetForAccountSwitch() {
    detach()
    sortField = .addedAt
    sortDescending = true
    isServerRoot = false
    isNetworkReachable = true
    hasPodcastLibrary = false
    selectedShowId = nil
    selectedShowTitle = ""
  }

  private func sync(from model: AppModel) {
    if sortField != model.podcastCatalogSortField { sortField = model.podcastCatalogSortField }
    if sortDescending != model.podcastCatalogSortDescending {
      sortDescending = model.podcastCatalogSortDescending
    }
    if isServerRoot != model.isServerRoot { isServerRoot = model.isServerRoot }
    if isNetworkReachable != model.isNetworkReachable { isNetworkReachable = model.isNetworkReachable }
    let hasLib = model.selectedPodcastLibrary != nil
    if hasPodcastLibrary != hasLib { hasPodcastLibrary = hasLib }
    let sid = model.podcastSelectedShowId
    if selectedShowId != sid { selectedShowId = sid }
    let title: String = {
      guard let sid else { return "" }
      return model.podcastShows.first(where: { $0.id == sid })?.displayTitle
        ?? ""
    }()
    if selectedShowTitle != title { selectedShowTitle = title }
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
  var browseGenresSortField: BooksBrowseFacetSortField
  var browseGenresSortDescending: Bool
  var browseTagsSortField: BooksBrowseFacetSortField
  var browseTagsSortDescending: Bool

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
    browseGenresSortField = state.browseGenresSortField
    browseGenresSortDescending = state.browseGenresSortDescending
    browseTagsSortField = state.browseTagsSortField
    browseTagsSortDescending = state.browseTagsSortDescending
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
    case .genres:
      BrowseGenresSortToolbarContent(snapshot: snapshot, toolbarState: toolbarState)
    case .tags:
      BrowseTagsSortToolbarContent(snapshot: snapshot, toolbarState: toolbarState)
    case .ebooks, .ebooksSupplementary:
      BrowseEbooksSortToolbarContent(snapshot: snapshot, toolbarState: toolbarState)
    default:
      BooksLibraryToolbarBodyStandard(snapshot: snapshot, toolbarState: toolbarState)
    }
  }
}

private struct BooksLibraryToolbarBodyStandard: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  var body: some ToolbarContent {
    switch snapshot.booksBrowseSection {
    case .books:
      BrowseBooksCatalogToolbarContent(snapshot: snapshot, toolbarState: toolbarState)
    case .author:
      BrowseAuthorsSortToolbarContent(snapshot: snapshot, toolbarState: toolbarState)
    case .narrators:
      BrowseNarratorsSortToolbarContent(snapshot: snapshot, toolbarState: toolbarState)
    case .series:
      BrowseSeriesSortToolbarContent(snapshot: snapshot, toolbarState: toolbarState)
    case .collections:
      BrowseCollectionsSortToolbarContent(snapshot: snapshot, toolbarState: toolbarState)
    default:
      ToolbarItem(placement: .topBarTrailing) { EmptyView() }
    }
  }
}

private struct BrowseGenresSortToolbarContent: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      BrowseFacetSortToolbarMenu(
        sortField: snapshot.browseGenresSortField,
        sortDescending: snapshot.browseGenresSortDescending,
        onSortFieldChange: { toolbarState.applyBrowseGenresSortField($0) },
        onSortDescendingChange: { toolbarState.applyBrowseGenresSortDescending($0) }
      )
      .equatable()
    }
  }
}

private struct BrowseTagsSortToolbarContent: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      BrowseFacetSortToolbarMenu(
        sortField: snapshot.browseTagsSortField,
        sortDescending: snapshot.browseTagsSortDescending,
        onSortFieldChange: { toolbarState.applyBrowseTagsSortField($0) },
        onSortDescendingChange: { toolbarState.applyBrowseTagsSortDescending($0) }
      )
      .equatable()
    }
  }
}

private struct BrowseEbooksSortToolbarContent: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      BooksCatalogSortToolbarMenu(
        sortField: snapshot.catalogSortField,
        sortDescending: snapshot.catalogSortDescending,
        onSortFieldChange: { toolbarState.applyCatalogSortField($0) },
        onSortDescendingChange: { toolbarState.applyCatalogSortDescending($0) }
      )
      .equatable()
    }
  }
}

private struct BrowseBooksCatalogToolbarContent: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  var body: some ToolbarContent {
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
  }
}

private struct BrowseAuthorsSortToolbarContent: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      BrowseAuthorsSortToolbarMenu(
        sortField: snapshot.browseAuthorsSortField,
        sortDescending: snapshot.browseAuthorsSortDescending,
        onSortFieldChange: { toolbarState.applyBrowseAuthorsSortField($0) },
        onSortDescendingChange: { toolbarState.applyBrowseAuthorsSortDescending($0) }
      )
      .equatable()
    }
  }
}

private struct BrowseNarratorsSortToolbarContent: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      BrowseNarratorsSortToolbarMenu(
        sortField: snapshot.browseNarratorsSortField,
        sortDescending: snapshot.browseNarratorsSortDescending,
        onSortFieldChange: { toolbarState.applyBrowseNarratorsSortField($0) },
        onSortDescendingChange: { toolbarState.applyBrowseNarratorsSortDescending($0) }
      )
      .equatable()
    }
  }
}

private struct BrowseSeriesSortToolbarContent: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      BrowseSeriesSortToolbarMenu(
        sortField: snapshot.browseSeriesSortField,
        sortDescending: snapshot.browseSeriesSortDescending,
        onSortFieldChange: { toolbarState.applyBrowseSeriesSortField($0) },
        onSortDescendingChange: { toolbarState.applyBrowseSeriesSortDescending($0) }
      )
      .equatable()
    }
  }
}

private struct BrowseCollectionsSortToolbarContent: ToolbarContent {
  let snapshot: BooksLibraryToolbarSnapshot
  let toolbarState: BooksLibraryToolbarState

  var body: some ToolbarContent {
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

/// Navigation + Toolbar; Katalog kommt als `let model`-Child (ohne `@EnvironmentObject` am Shell).
struct BooksLibraryTabShell<Catalog: View>: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject var toolbarState: BooksLibraryToolbarState
  @ViewBuilder var catalog: () -> Catalog

  var body: some View {
    navigationRoot
  }

  /// „Books“ wird zu „Audiobooks“, sobald eBooks einen eigenen Tab haben.
  private var navigationTitle: String {
    model.ebooksSeparateTabEnabled ? "Audiobooks" : AppModel.MainTab.library.rawValue
  }

  private var navigationRoot: some View {
    NavigationStack {
      catalog()
        .abstandTabScreenChrome()
        .navigationTitle(navigationTitle)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
          if model.booksBrowseSection != .search {
            BooksLibraryToolbarContent(toolbarState: toolbarState)
          }
        }
        .booksEntityDetailNavigation(for: .library)
    }
  }
}

struct PodcastCatalogToolbarSnapshot: Equatable {
  var sortField: PodcastCatalogSortField
  var sortDescending: Bool
  var isServerRoot: Bool
  var isNetworkReachable: Bool
  var hasPodcastLibrary: Bool
  var selectedShowId: String?
  var selectedShowTitle: String

  /// `nil` / leer = „New“-Ansicht (keine Sendung gewählt).
  var isPodcastNewView: Bool {
    let sid = selectedShowId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return sid.isEmpty
  }

  @MainActor
  init(_ state: PodcastCatalogToolbarState) {
    sortField = state.sortField
    sortDescending = state.sortDescending
    isServerRoot = state.isServerRoot
    isNetworkReachable = state.isNetworkReachable
    hasPodcastLibrary = state.hasPodcastLibrary
    selectedShowId = state.selectedShowId
    selectedShowTitle = state.selectedShowTitle
  }
}

enum PodcastCatalogNavigation: Hashable {
  case addPodcast
}

struct PodcastCatalogToolbarContent: ToolbarContent {
  let snapshot: PodcastCatalogToolbarSnapshot
  let toolbarState: PodcastCatalogToolbarState
  @Environment(\.themeAccent) private var themeAccent

  @MainActor
  init(toolbarState: PodcastCatalogToolbarState) {
    self.toolbarState = toolbarState
    snapshot = PodcastCatalogToolbarSnapshot(toolbarState)
  }

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      if snapshot.isServerRoot, snapshot.isPodcastNewView {
        NavigationLink(value: PodcastCatalogNavigation.addPodcast) {
          Image(systemName: "plus.circle.fill")
            .foregroundStyle(themeAccent)
        }
        .disabled(!snapshot.hasPodcastLibrary || !snapshot.isNetworkReachable)
        .accessibilityLabel("Add podcast")
      }

      if snapshot.isServerRoot,
        let showId = snapshot.selectedShowId?.trimmingCharacters(in: .whitespacesAndNewlines),
        !showId.isEmpty
      {
        let title = snapshot.selectedShowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        NavigationLink {
          ServerAdminPodcastShowView(
            showId: showId,
            showTitle: title.isEmpty ? "Podcast" : title
          )
        } label: {
          Image(systemName: "gearshape.fill")
            .foregroundStyle(themeAccent)
        }
        .accessibilityLabel("Show settings")
      }

      PodcastCatalogSortToolbarSnapshot(toolbarState: toolbarState)
        .equatable()
    }
  }
}

struct PodcastCatalogTabShell<Catalog: View>: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject var toolbarState: PodcastCatalogToolbarState
  @State private var navigationPath = NavigationPath()
  @ViewBuilder var catalog: () -> Catalog

  var body: some View {
    let _ = model.appearanceThemeRevision
    return NavigationStack(path: $navigationPath) {
      catalog()
        .abstandTabScreenChrome()
        .navigationTitle(AppModel.MainTab.podcasts.rawValue)
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: PodcastCatalogNavigation.self) { destination in
          switch destination {
          case .addPodcast:
            PodcastAddFromSearchView()
              .navigationTitle("Add podcast")
              .toolbarTitleDisplayMode(.inline)
          }
        }
        .toolbar {
          PodcastCatalogToolbarContent(toolbarState: toolbarState)
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
