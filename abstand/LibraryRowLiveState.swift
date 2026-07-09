import Combine
import SwiftUI

// MARK: - Fortschritt / Download pro Karte (ohne `@EnvironmentObject` → kein Katalog-Rebuild)

enum LibraryRowLiveState {
  static func resolveEbookProgressFraction(
    libraryItemId: String,
    serverEbookProgress: Double?
  ) -> Double? {
    let localF = EbookLocalStore.loadProgressFraction(libraryItemId: libraryItemId)
    let f = [serverEbookProgress, localF].compactMap { $0 }.max()
    guard let f, f > 0.005 else { return nil }
    let clamped = min(1, max(0, f))
    if clamped >= 0.995 { return 1.0 }
    return clamped
  }

  static func ebookProgressLabel(for fraction: Double?) -> String? {
    guard let f = fraction, f < 0.995 else { return nil }
    return "\(Int((f * 100).rounded()))% read"
  }

  static func ebookOpenPillCaption(for fraction: Double?) -> String {
    guard let f = fraction else { return "Read" }
    if f >= 0.995 { return "Finished" }
    if f > 0.005 { return "Continue reading" }
    return "Read"
  }

  static func progressMateriallyEqual(_ lhs: ABSUserMediaProgress?, _ rhs: ABSUserMediaProgress?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
      return true
    case let (l?, r?):
      return l.isFinished == r.isFinished
        && abs(l.currentTime - r.currentTime) < 1.0
        && abs(l.progress - r.progress) < 0.01
        && abs(l.duration - r.duration) < 0.5
    default:
      return false
    }
  }
}

/// Hörbuch-Zeile: nur `progressByItemId[bookId]` + Download-Status für diese ID.
@MainActor
final class LibraryBookRowLiveState: ObservableObject {
  @Published private(set) var progress: ABSUserMediaProgress?
  @Published private(set) var isDownloaded = false
  @Published private(set) var isDownloading = false
  @Published private(set) var isQueued = false
  @Published private(set) var downloadProgress: Double = 0
  @Published private(set) var isPreparingEbook = false
  @Published private(set) var ebookProgressFraction: Double?

  private let bookId: String
  private let observesProgress: Bool
  private let observesDownload: Bool
  private let observesEbookProgress: Bool
  private var cancellables = Set<AnyCancellable>()

  init(
    bookId: String,
    model: AppModel,
    observesProgress: Bool = true,
    observesDownload: Bool = true,
    observesEbookProgress: Bool = false
  ) {
    self.bookId = bookId
    self.observesProgress = observesProgress
    self.observesDownload = observesDownload
    self.observesEbookProgress = observesEbookProgress
    if observesProgress {
      progress = model.progressByItemId[bookId]
    }
    if observesDownload {
      isDownloaded = model.isLibraryItemDownloaded(libraryItemId: bookId)
      syncDownloadState(model: model)
    }
    isPreparingEbook = model.isPreparingEbook
    if observesEbookProgress {
      ebookProgressFraction = LibraryRowLiveState.resolveEbookProgressFraction(
        libraryItemId: bookId,
        serverEbookProgress: model.progressByItemId[bookId]?.ebookProgress
      )
    }
    bind(model)
  }

  private func bind(_ model: AppModel) {
    if observesProgress {
      model.$progressByItemId
        .map { [bookId] in $0[bookId] }
        .removeDuplicates(by: LibraryRowLiveState.progressMateriallyEqual)
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.progress = $0 }
        .store(in: &cancellables)
    }

    if observesDownload {
      model.$downloadedItemIds
        .map { [bookId] _ in model.isLibraryItemDownloaded(libraryItemId: bookId) }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.isDownloaded = $0 }
        .store(in: &cancellables)

      Publishers.CombineLatest3(
        model.downloads.$activeItemId,
        model.downloads.$progress,
        model.downloads.$queuedItemIds
      )
      .receive(on: RunLoop.main)
      .sink { [weak self] activeId, progress, queuedIds in
        guard let self else { return }
        self.syncDownloadState(model: model, activeItemId: activeId, progress: progress, queuedItemIds: queuedIds)
      }
      .store(in: &cancellables)
    }

    model.$isPreparingEbook
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.isPreparingEbook = $0 }
      .store(in: &cancellables)

    if observesEbookProgress {
      model.$progressByItemId
        .map { [bookId] dict in
          LibraryRowLiveState.resolveEbookProgressFraction(
            libraryItemId: bookId,
            serverEbookProgress: dict[bookId]?.ebookProgress
          )
        }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.ebookProgressFraction = $0 }
        .store(in: &cancellables)
    }
  }

  private func syncDownloadState(
    model: AppModel,
    activeItemId: String? = nil,
    progress: Double = 0,
    queuedItemIds: [String] = []
  ) {
    let activeId = (activeItemId ?? model.downloads.activeItemId)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let storageId = model.downloadStorageIdForLibraryItem(bookId) ?? bookId
    let queueIds = queuedItemIds.isEmpty ? model.downloads.queuedItemIds : queuedItemIds
    isQueued = queueIds.contains(bookId) || queueIds.contains(storageId)
    guard !activeId.isEmpty else {
      isDownloading = false
      downloadProgress = 0
      return
    }
    isDownloading = activeId == bookId || activeId == storageId
    downloadProgress = isDownloading ? progress : 0
  }
}

/// Podcast-Folge: Fortschritt über `progressLookupKey`, Offline-ID separat.
@MainActor
final class LibraryPodcastEpisodeRowLiveState: ObservableObject {
  @Published private(set) var progress: ABSUserMediaProgress?
  @Published private(set) var isDownloaded = false
  @Published private(set) var isDownloading = false
  @Published private(set) var isQueued = false
  @Published private(set) var downloadProgress: Double = 0

  private let progressLookupKey: String
  private let offlineStorageId: String
  private var cancellables = Set<AnyCancellable>()

  init(progressLookupKey: String, offlineStorageId: String, model: AppModel) {
    self.progressLookupKey = progressLookupKey
    self.offlineStorageId = offlineStorageId
    progress = model.progressByItemId[progressLookupKey]
    isDownloaded = model.downloadedItemIds.contains(offlineStorageId)
    syncDownloadState(
      activeItemId: model.downloads.activeItemId,
      progress: model.downloads.progress,
      queuedItemIds: model.downloads.queuedItemIds
    )
    bind(model)
  }

  private func bind(_ model: AppModel) {
    model.$progressByItemId
      .map { [progressLookupKey] in $0[progressLookupKey] }
      .removeDuplicates(by: LibraryRowLiveState.progressMateriallyEqual)
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.progress = $0 }
      .store(in: &cancellables)

    model.$downloadedItemIds
      .map { [offlineStorageId] in $0.contains(offlineStorageId) }
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.isDownloaded = $0 }
      .store(in: &cancellables)

    Publishers.CombineLatest3(
      model.downloads.$activeItemId,
      model.downloads.$progress,
      model.downloads.$queuedItemIds
    )
    .receive(on: RunLoop.main)
    .sink { [weak self] activeId, progress, queuedIds in
      self?.syncDownloadState(activeItemId: activeId, progress: progress, queuedItemIds: queuedIds)
    }
    .store(in: &cancellables)
  }

  private func syncDownloadState(activeItemId: String?, progress: Double, queuedItemIds: [String]) {
    let active = activeItemId == self.offlineStorageId
    isDownloading = active
    isQueued = queuedItemIds.contains(self.offlineStorageId)
    downloadProgress = active ? progress : 0
  }
}
