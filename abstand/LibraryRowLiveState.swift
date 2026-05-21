import Combine
import SwiftUI

// MARK: - Fortschritt / Download pro Karte (ohne `@EnvironmentObject` → kein Katalog-Rebuild)

enum LibraryRowLiveState {
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
  @Published private(set) var downloadProgress: Double = 0
  @Published private(set) var isPreparingEbook = false

  private let bookId: String
  private let observesProgress: Bool
  private let observesDownload: Bool
  private var cancellables = Set<AnyCancellable>()

  init(
    bookId: String,
    model: AppModel,
    observesProgress: Bool = true,
    observesDownload: Bool = true
  ) {
    self.bookId = bookId
    self.observesProgress = observesProgress
    self.observesDownload = observesDownload
    if observesProgress {
      progress = model.progressByItemId[bookId]
    }
    if observesDownload {
      isDownloaded = model.downloadedItemIds.contains(bookId)
      syncDownloadState(activeItemId: model.downloads.activeItemId, progress: model.downloads.progress)
    }
    isPreparingEbook = model.isPreparingEbook
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
        .map { [bookId] in $0.contains(bookId) }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.isDownloaded = $0 }
        .store(in: &cancellables)

      Publishers.CombineLatest(
        model.downloads.$activeItemId,
        model.downloads.$progress
      )
      .receive(on: RunLoop.main)
      .sink { [weak self] activeId, progress in
        self?.syncDownloadState(activeItemId: activeId, progress: progress)
      }
      .store(in: &cancellables)
    }

    model.$isPreparingEbook
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.isPreparingEbook = $0 }
      .store(in: &cancellables)
  }

  private func syncDownloadState(activeItemId: String?, progress: Double) {
    let active = activeItemId == self.bookId
    isDownloading = active
    downloadProgress = active ? progress : 0
  }
}

/// Podcast-Folge: Fortschritt über `progressLookupKey`, Offline-ID separat.
@MainActor
final class LibraryPodcastEpisodeRowLiveState: ObservableObject {
  @Published private(set) var progress: ABSUserMediaProgress?
  @Published private(set) var isDownloaded = false
  @Published private(set) var isDownloading = false
  @Published private(set) var downloadProgress: Double = 0

  private let progressLookupKey: String
  private let offlineStorageId: String
  private var cancellables = Set<AnyCancellable>()

  init(progressLookupKey: String, offlineStorageId: String, model: AppModel) {
    self.progressLookupKey = progressLookupKey
    self.offlineStorageId = offlineStorageId
    progress = model.progressByItemId[progressLookupKey]
    isDownloaded = model.downloadedItemIds.contains(offlineStorageId)
    syncDownloadState(activeItemId: model.downloads.activeItemId, progress: model.downloads.progress)
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

    Publishers.CombineLatest(
      model.downloads.$activeItemId,
      model.downloads.$progress
    )
    .receive(on: RunLoop.main)
    .sink { [weak self] activeId, progress in
      self?.syncDownloadState(activeItemId: activeId, progress: progress)
    }
    .store(in: &cancellables)
  }

  private func syncDownloadState(activeItemId: String?, progress: Double) {
    let active = activeItemId == self.offlineStorageId
    isDownloading = active
    downloadProgress = active ? progress : 0
  }
}
