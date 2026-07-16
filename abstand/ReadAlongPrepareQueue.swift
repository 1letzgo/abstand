import Combine
import Foundation

enum ReadAlongPrepareKind: String, Codable, Sendable {
  case speechOnly
  case speechAndEbookSync
}

struct ReadAlongPrepareCatalogEntry: Equatable, Sendable, Identifiable {
  let itemId: String
  let libraryItemId: String
  let episodeId: String?
  let title: String
  let subtitle: String?
  let kind: ReadAlongPrepareKind

  var id: String { itemId }

  var isPodcastEpisode: Bool { episodeId != nil }
}

/// FIFO-Queue für Read-Along-Vorbereitung (Speech-Modell ± EPUB-Alignment).
@MainActor
final class ReadAlongPrepareQueue: ObservableObject {
  @Published private(set) var activeItemId: String?
  @Published private(set) var progress: Double = 0
  @Published private(set) var statusMessage: String?
  @Published private(set) var queuedItemIds: [String] = []
  @Published private(set) var lastErrorMessage: String?
  /// Erfolgreich vorbereitete Items (Session-Cache + UI).
  @Published private(set) var readyItemIds: [String] = []
  /// Metadaten für aktive/wartende/fertige Einträge (Settings-UI).
  @Published private(set) var catalogById: [String: ReadAlongPrepareCatalogEntry] = [:]

  private struct QueuedPrepare {
    let entry: ReadAlongPrepareCatalogEntry
    let run: () async throws -> Void
  }

  private var queue: [QueuedPrepare] = []
  private var task: Task<Void, Never>?
  private var runId = 0
  private var cancelHandler: ((String) -> Void)?

  var pendingCount: Int {
    (activeItemId == nil ? 0 : 1) + queuedItemIds.count
  }

  var hasWork: Bool {
    pendingCount > 0 || !readyItemIds.isEmpty
  }

  var activeEntry: ReadAlongPrepareCatalogEntry? {
    guard let activeItemId else { return nil }
    return catalogById[activeItemId]
  }

  func isActive(_ itemId: String) -> Bool { activeItemId == itemId }
  func isQueued(_ itemId: String) -> Bool { queuedItemIds.contains(itemId) }
  func isReady(_ itemId: String) -> Bool { readyItemIds.contains(itemId) }
  func isPending(_ itemId: String) -> Bool { isActive(itemId) || isQueued(itemId) }

  /// Wird bei Cancel aufgerufen (Speech-/Alignment-Tasks abbrechen).
  func setCancelHandler(_ handler: @escaping (String) -> Void) {
    cancelHandler = handler
  }

  func markReady(_ itemId: String) {
    if !readyItemIds.contains(itemId) {
      readyItemIds.append(itemId)
    }
  }

  func clearReady(_ itemId: String) {
    readyItemIds.removeAll { $0 == itemId }
  }

  /// Enqueued; gleiche ID wird dedupliziert.
  func enqueue(
    entry: ReadAlongPrepareCatalogEntry,
    run: @escaping () async throws -> Void
  ) {
    let id = entry.itemId
    if activeItemId == id || queuedItemIds.contains(id) { return }
    lastErrorMessage = nil
    catalogById[id] = entry
    readyItemIds.removeAll { $0 == id }
    if activeItemId != nil {
      queue.append(QueuedPrepare(entry: entry, run: run))
      queuedItemIds = queue.map(\.entry.itemId)
      return
    }
    start(QueuedPrepare(entry: entry, run: run))
  }

  func cancel(itemId: String) {
    if let idx = queue.firstIndex(where: { $0.entry.itemId == itemId }) {
      queue.remove(at: idx)
      queuedItemIds = queue.map(\.entry.itemId)
      return
    }
    guard activeItemId == itemId else {
      clearReady(itemId)
      return
    }
    runId += 1
    cancelHandler?(itemId)
    task?.cancel()
    task = nil
    activeItemId = nil
    progress = 0
    statusMessage = nil
    startNext()
  }

  func cancelAll() {
    let active = activeItemId
    runId += 1
    if let active { cancelHandler?(active) }
    task?.cancel()
    task = nil
    queue.removeAll()
    queuedItemIds = []
    activeItemId = nil
    progress = 0
    statusMessage = nil
  }

  func updateProgress(_ value: Double, status: String?) {
    progress = min(1, max(0, value))
    if let status { statusMessage = status }
  }

  private func start(_ item: QueuedPrepare) {
    runId += 1
    let currentRun = runId
    activeItemId = item.entry.itemId
    catalogById[item.entry.itemId] = item.entry
    progress = 0
    statusMessage = String(localized: "Preparing…", comment: "Read along prepare")
    lastErrorMessage = nil

    task = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await item.run()
        guard currentRun == self.runId else { return }
        if !self.readyItemIds.contains(item.entry.itemId) {
          self.readyItemIds.append(item.entry.itemId)
        }
        self.progress = 1
        self.statusMessage = String(localized: "Ready for read along", comment: "Read along prepare")
      } catch is CancellationError {
        // cancelled
      } catch {
        guard currentRun == self.runId else { return }
        self.lastErrorMessage =
          (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        self.readyItemIds.removeAll { $0 == item.entry.itemId }
      }
      guard currentRun == self.runId else { return }
      self.activeItemId = nil
      self.progress = 0
      self.statusMessage = nil
      self.task = nil
      self.startNext()
    }
  }

  private func startNext() {
    guard activeItemId == nil, !queue.isEmpty else { return }
    let next = queue.removeFirst()
    queuedItemIds = queue.map(\.entry.itemId)
    start(next)
  }
}
