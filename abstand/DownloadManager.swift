import Combine
import Foundation

private struct DownloadWIP: Codable {
  var storageItemId: String
  var libraryItemId: String
  var episodeId: String?
  var completedTrackIndexes: [Int]
}

/// Aufgelöste Tracks + Session für einen Download-Lauf (einheitlich Bücher & Podcast-Folgen).
private struct DownloadTrackResolution {
  var book: ABSBook
  var tracks: [ABSAudioTrack]
  var streamSessionId: String
  var ownsPlaySession: Bool
  var serverSession: ABSPlaySession?
}

/// Vollständige Parameter eines Download-Requests (für sequenzielle Queue-Ausführung).
private struct QueuedDownload {
  var client: ABSAPIClient
  var book: ABSBook
  var episodeId: String?
  var storageItemId: String
  var reusePlaySessionId: String?
  var reusePlaySessionTracks: [ABSAudioTrack]?
  var completion: ((Bool) -> Void)?
}

@MainActor
final class DownloadManager: ObservableObject {
  @Published private(set) var activeItemId: String?
  @Published private(set) var progress: Double = 0
  /// Wartende Downloads (FIFO). `activeItemId`/`progress` beschreiben weiterhin nur den aktiven Lauf.
  @Published private(set) var queuedItemIds: [String] = []

  private var task: Task<Void, Never>?

  private static let trackDownloadMaxAttempts = 3
  private static let wipFilename = "download-wip.json"

  private var downloadRunId: Int = 0

  /// Zeitstempel des letzten Intra-Track-Progress-Emits (Throttling der Byte-Callback-Flut).
  private var lastIntraTrackEmit: Date = .distantPast

  /// Interne FIFO-Queue mit allen Parametern für verzögerten Start.
  private var downloadQueue: [QueuedDownload] = []

  /// Client des aktuell laufenden Downloads — für URLSession-Task-Cancel.
  private var activeClient: ABSAPIClient?

  /// Bricht nur den aktuell laufenden Download ab (falls vorhanden). Für gezieltes Abbrechen
  /// eines bestimmten Items `cancel(itemId:)` verwenden — sonst bleibt die Queue unberührt.
  func cancel() {
    task?.cancel()
    task = nil
    let client = activeClient
    activeClient = nil
    activeItemId = nil
    progress = 0
    if let client {
      Task { await client.cancelInFlightDownloads() }
    }
  }

  /// Bricht den Download für `itemId` gezielt ab: entweder aus der Queue entfernen (wartet noch)
  /// oder, falls aktiv, den Lauf canceln und anschließend das nächste Queue-Element starten.
  func cancel(itemId: String) {
    if let idx = downloadQueue.firstIndex(where: { $0.storageItemId == itemId }) {
      downloadQueue.remove(at: idx)
      queuedItemIds = downloadQueue.map(\.storageItemId)
      // Wartender Download wurde nie gestartet → kein Completion-Call, kein BG-Task-Ende nötig.
      return
    }
    guard activeItemId == itemId else { return }
    task?.cancel()
    task = nil
    let client = activeClient
    activeClient = nil
    activeItemId = nil
    progress = 0
    if let client {
      Task { await client.cancelInFlightDownloads() }
    }
    startNextQueuedDownload()
  }

  /// Wurzel `…/Downloads` (ohne Item-ID).
  private func downloadsRootURL() throws -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent("Downloads", isDirectory: true)
  }

  private func setExcludedFromBackup(_ url: URL) {
    var u = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? u.setResourceValues(values)
  }

  func downloadFolder(for itemId: String) throws -> URL {
    let root = try downloadsRootURL()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    setExcludedFromBackup(root)
    let dir = root.appendingPathComponent(itemId, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    setExcludedFromBackup(dir)
    return dir
  }

  /// Entfernt den kompletten Download-Ordner inkl. partieller Tracks (Mini-Roadmap: Multi-Track-Fehler).
  func deleteDownload(itemId: String) {
    guard let root = try? downloadsRootURL() else { return }
    let url = root.appendingPathComponent(itemId, isDirectory: true)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private func wipURL(in folder: URL) -> URL {
    folder.appendingPathComponent(Self.wipFilename)
  }

  private func loadWIP(folder: URL, storageId: String, episodeId: String?) -> DownloadWIP? {
    let url = wipURL(in: folder)
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard let wip = try? ABSJSON.decoder().decode(DownloadWIP.self, from: data) else { return nil }
    guard wip.storageItemId == storageId else { return nil }
    let wEp = wip.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let eEp = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if wEp != eEp { return nil }
    return wip
  }

  private func saveWIP(_ wip: DownloadWIP, folder: URL) throws {
    let data = try ABSJSON.encoder().encode(wip)
    try data.write(to: wipURL(in: folder), options: .atomic)
  }

  /// Nur aufrufen, wenn `runId` noch der aktuelle Download-Lauf ist (verhindert Löschen durch abgebrochene Tasks).
  private func finishDownloadFailureIfCurrent(runId: Int, itemId: String, completion: ((Bool) -> Void)?) {
    guard runId == downloadRunId else { return }
    deleteDownload(itemId: itemId)
    activeItemId = nil
    progress = 0
    completion?(false)
    startNextQueuedDownload()
  }

  private func finishDownloadInterruptedIfCurrent(runId: Int, completion: ((Bool) -> Void)?) {
    guard runId == downloadRunId else { return }
    activeItemId = nil
    progress = 0
    completion?(false)
    startNextQueuedDownload()
  }

  private func finishDownloadSuccessIfCurrent(runId: Int, completion: ((Bool) -> Void)?) {
    guard runId == downloadRunId else { return }
    activeItemId = nil
    progress = 1
    completion?(true)
    startNextQueuedDownload()
  }

  /// Startet den nächsten wartenden Download (FIFO), sofern keiner aktiv läuft.
  /// Wird nach jedem Completion-Pfad aufgerufen — auch nach gezieltem `cancel(itemId:)`.
  private func startNextQueuedDownload() {
    guard activeItemId == nil, !downloadQueue.isEmpty else { return }
    let entry = downloadQueue.removeFirst()
    queuedItemIds = downloadQueue.map(\.storageItemId)
    downloadRunId += 1
    let runId = downloadRunId
    activeItemId = entry.storageItemId
    progress = 0
    runDownload(entry, runId: runId)
  }

  private static func sortedCatalogTracks(from book: ABSBook) -> [ABSAudioTrack] {
    (book.media.tracks ?? []).sorted { $0.index < $1.index }
  }

  private static func allTracksHaveDirectIno(_ tracks: [ABSAudioTrack]) -> Bool {
    !tracks.isEmpty
      && tracks.allSatisfy {
        !($0.ino ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }

  /// Einheitliche Track-Quelle (vgl. Absorb: Play-Session; Bücher optional direkt per `ino`).
  private func resolveDownloadTracks(
    client: ABSAPIClient,
    book: ABSBook,
    episodeId: String?,
    reusePlaySessionId: String?,
    reusePlaySessionTracks: [ABSAudioTrack]?
  ) async throws -> DownloadTrackResolution {
    let trimmedEp = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let resolvedEp: String? = trimmedEp.isEmpty ? nil : trimmedEp
    let isPodcastEpisode = resolvedEp != nil

    var workingBook = book
    var sorted = Self.sortedCatalogTracks(from: workingBook)

    let reuseSid = reusePlaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasReuse = !(reuseSid ?? "").isEmpty

    if hasReuse {
      let reused = (reusePlaySessionTracks ?? []).sorted { $0.index < $1.index }
      if !reused.isEmpty {
        return DownloadTrackResolution(
          book: workingBook,
          tracks: reused,
          streamSessionId: reuseSid!,
          ownsPlaySession: false,
          serverSession: nil
        )
      }
      // Parallele Session ohne Track-Liste: bei Podcast kein zweites `POST …/play`.
      if isPodcastEpisode {
        throw ABSPlaybackError.noTracks
      }
    }

    if !isPodcastEpisode, sorted.isEmpty {
      let expanded = try await client.item(id: workingBook.id, expanded: true)
      workingBook = expanded
      sorted = Self.sortedCatalogTracks(from: workingBook)
    }

    if isPodcastEpisode {
      let session = try await client.startPlaySession(
        itemId: workingBook.id,
        episodeId: resolvedEp,
        deviceId: PlaybackController.stableDeviceId(),
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      )
      let sessionTracks = (session.audioTracks ?? []).sorted { $0.index < $1.index }
      guard !sessionTracks.isEmpty else { throw ABSPlaybackError.noTracks }
      return DownloadTrackResolution(
        book: workingBook,
        tracks: sessionTracks,
        streamSessionId: session.id,
        ownsPlaySession: true,
        serverSession: session
      )
    }

    if Self.allTracksHaveDirectIno(sorted) {
      return DownloadTrackResolution(
        book: workingBook,
        tracks: sorted,
        streamSessionId: "",
        ownsPlaySession: false,
        serverSession: nil
      )
    }

    let session = try await client.startPlaySession(
      itemId: workingBook.id,
      episodeId: nil,
      deviceId: PlaybackController.stableDeviceId(),
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    )
    let sessionTracks = (session.audioTracks ?? []).sorted { $0.index < $1.index }
    let tracks = !sessionTracks.isEmpty ? sessionTracks : sorted
    guard !tracks.isEmpty else { throw ABSPlaybackError.noTracks }
    return DownloadTrackResolution(
      book: workingBook,
      tracks: tracks,
      streamSessionId: session.id,
      ownsPlaySession: true,
      serverSession: session
    )
  }

  func startDownload(
    client: ABSAPIClient,
    book: ABSBook,
    episodeId: String? = nil,
    storageItemId: String? = nil,
    reusePlaySessionId: String? = nil,
    reusePlaySessionTracks: [ABSAudioTrack]? = nil,
    completion: ((Bool) -> Void)? = nil
  ) {
    let id = storageItemId ?? book.id
    // Bereits aktiv oder wartend → idempotentes No-Op (kein Doppel-Enqueue, kein EPIPE-Risiko).
    if activeItemId == id || queuedItemIds.contains(id) {
      return
    }
    let entry = QueuedDownload(
      client: client,
      book: book,
      episodeId: episodeId,
      storageItemId: id,
      reusePlaySessionId: reusePlaySessionId,
      reusePlaySessionTracks: reusePlaySessionTracks,
      completion: completion
    )
    // Wenn gerade ein Download läuft → an Queue anhängen, späterer Start via `startNextQueuedDownload`.
    if activeItemId != nil {
      downloadQueue.append(entry)
      queuedItemIds = downloadQueue.map(\.storageItemId)
      return
    }
    downloadRunId += 1
    let runId = downloadRunId
    activeItemId = id
    progress = 0
    runDownload(entry, runId: runId)
  }

  /// Führt einen einzelnen Download-Lauf aus (aus `startDownload` oder `startNextQueuedDownload`).
  private func runDownload(_ entry: QueuedDownload, runId: Int) {
    let id = entry.storageItemId
    let client = entry.client
    let book = entry.book
    let completion = entry.completion
    let trimmedEp = entry.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let resolvedEp: String? = trimmedEp.isEmpty ? nil : trimmedEp
    let reuseSid: String? = {
      guard let r = entry.reusePlaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
        return nil
      }
      return r
    }()

    activeClient = client
    task = Task { @MainActor in
      var ownsPlaySession = false
      var streamSessionId = ""
      defer {
        if runId == downloadRunId { activeClient = nil }
      }
      do {
        let folder: URL
        var resumeCompleted = Set<Int>()
        do {
          // Disk-I/O off-Main — nur Ergebnis zurück auf MainActor.
          let prepared = try await Task.detached(priority: .utility) { [id, resolvedEp] in
            let fm = FileManager.default
            let base = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            let root = base.appendingPathComponent("Downloads", isDirectory: true)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            var rootURL = root
            var rootValues = URLResourceValues()
            rootValues.isExcludedFromBackup = true
            try? rootURL.setResourceValues(rootValues)
            let itemDir = root.appendingPathComponent(id, isDirectory: true)
            var resume = Set<Int>()
            if fm.fileExists(atPath: itemDir.path),
              ABSDownloadManifest.load(from: itemDir) == nil
            {
              let wipURL = itemDir.appendingPathComponent(DownloadManager.wipFilename)
              if let data = try? Data(contentsOf: wipURL),
                let wip = try? ABSJSON.decoder().decode(DownloadWIP.self, from: data),
                wip.storageItemId == id,
                (wip.episodeId ?? "") == (resolvedEp ?? ""),
                !wip.completedTrackIndexes.isEmpty
              {
                resume = Set(wip.completedTrackIndexes)
              } else {
                try fm.removeItem(at: itemDir)
              }
            } else if fm.fileExists(atPath: itemDir.path) {
              try fm.removeItem(at: itemDir)
            }
            try fm.createDirectory(at: itemDir, withIntermediateDirectories: true)
            var itemURL = itemDir
            var itemValues = URLResourceValues()
            itemValues.isExcludedFromBackup = true
            try? itemURL.setResourceValues(itemValues)
            return (itemDir, resume)
          }.value
          folder = prepared.0
          resumeCompleted = prepared.1
        } catch {
          guard runId == downloadRunId else { return }
          activeItemId = nil
          progress = 0
          completion?(false)
          startNextQueuedDownload()
          return
        }

        let resolved = try await resolveDownloadTracks(
          client: client,
          book: book,
          episodeId: resolvedEp,
          reusePlaySessionId: reuseSid,
          reusePlaySessionTracks: entry.reusePlaySessionTracks
        )
        let downloadBook = resolved.book
        let sorted = resolved.tracks
        streamSessionId = resolved.streamSessionId
        ownsPlaySession = resolved.ownsPlaySession
        let serverSession = resolved.serverSession

        let weights: [Double] = sorted.map { tr in
          let d = tr.duration
          if d.isFinite, d > 0 { return max(d, 30) }
          return 300
        }
        let sumW = max(weights.reduce(0, +), 1)
        var doneW: Double = 0
        for (i, tr) in sorted.enumerated() where resumeCompleted.contains(tr.index) {
          doneW += weights[i]
        }

        var savedAudioExtension: String?
        var wip = DownloadWIP(
          storageItemId: id,
          libraryItemId: downloadBook.id,
          episodeId: resolvedEp,
          completedTrackIndexes: Array(resumeCompleted).sorted()
        )

        for (i, tr) in sorted.enumerated() {
          try Task.checkCancellation()
          if resumeCompleted.contains(tr.index) {
            progress = min(1, doneW / sumW)
            continue
          }
          progress = doneW / sumW
          let suggested = folder.appendingPathComponent(PlaybackController.trackFilename(index: tr.index))
          let trackWeight = weights[i]
          let baseDoneW = doneW
          // Intra-Track-Fortschritt: `fraction` (0…1) vom Delegate → interpoliert in den Gesamtfortschritt.
          // Throttling über `lastProgressEmit`, damit nicht jedes Byte-Event einen Main-Actor-Hop auslöst.
          let progressSink: @Sendable (Double) -> Void = { [weak self] fraction in
            guard let self else { return }
            Task { @MainActor [weak self] in
              guard let self else { return }
              let now = Date()
              if now.timeIntervalSince(self.lastIntraTrackEmit) < 0.08 { return }
              self.lastIntraTrackEmit = now
              self.progress = min(1, (baseDoneW + fraction * trackWeight) / sumW)
            }
          }
          let finalURL: URL
          if let ino = tr.ino, !ino.isEmpty {
            let fileURL = try await client.itemFileDownloadURL(itemId: downloadBook.id, ino: ino)
            finalURL = try await client.downloadAuthenticatedFile(
              from: fileURL,
              to: suggested,
              maxAttempts: Self.trackDownloadMaxAttempts,
              progress: progressSink
            )
          } else {
            guard !streamSessionId.isEmpty else { throw ABSPlaybackError.noTracks }
            let stream = try await client.publicStreamURL(sessionId: streamSessionId, trackIndex: tr.index)
            finalURL = try await client.downloadAuthenticatedFile(
              from: stream,
              to: suggested,
              maxAttempts: Self.trackDownloadMaxAttempts,
              progress: progressSink
            )
          }
          if savedAudioExtension == nil {
            savedAudioExtension = finalURL.pathExtension.lowercased()
          }
          doneW += weights[i]
          progress = min(1, doneW / sumW)
          lastIntraTrackEmit = .distantPast
          resumeCompleted.insert(tr.index)
          wip.completedTrackIndexes = Array(resumeCompleted).sorted()
          try? saveWIP(wip, folder: folder)
        }

        if savedAudioExtension == nil, let first = sorted.first,
          let u = PlaybackController.resolvedLocalTrackURL(root: folder, trackIndex: first.index, manifest: nil)
        {
          let ext = u.pathExtension.lowercased()
          if !ext.isEmpty { savedAudioExtension = ext }
        }

        let totalDur: Double?
        if let s = serverSession, s.duration > 0 {
          totalDur = s.duration
        } else if let d = downloadBook.media.duration, d > 0 {
          totalDur = d
        } else {
          totalDur = nil
        }
        let chapterSource: [ABSChapter]? = {
          if let ch = downloadBook.media.chapters, !ch.isEmpty { return ch }
          if let ch = serverSession?.chapters, !ch.isEmpty { return ch }
          if let ch = serverSession?.libraryItem.media.chapters, !ch.isEmpty { return ch }
          return nil
        }()
        let manifest = ABSDownloadManifest(
          format: 1,
          libraryItemId: downloadBook.id,
          episodeId: resolvedEp,
          libraryId: downloadBook.libraryId,
          displayTitle: downloadBook.displayTitle,
          displayAuthor: downloadBook.displayAuthors,
          playSessionId: streamSessionId,
          savedAtEpoch: Date().timeIntervalSince1970,
          audioFileExtension: savedAudioExtension,
          totalDuration: totalDur,
          tracks: sorted.map { tr in
            ABSDownloadManifest.Track(
              index: tr.index,
              startOffset: tr.startOffset,
              duration: tr.duration,
              title: tr.title
            )
          },
          chapters: chapterSource?.map { ABSDownloadManifest.Chapter($0) }
        )
        try manifest.write(to: folder)
        try? FileManager.default.removeItem(at: wipURL(in: folder))
        if ownsPlaySession {
          try? await client.closePlaySession(sessionId: streamSessionId)
        }
        finishDownloadSuccessIfCurrent(runId: runId, completion: completion)
      } catch {
        let cancelled =
          error is CancellationError
          || (error as? URLError)?.code == .cancelled
        if ownsPlaySession, !streamSessionId.isEmpty {
          try? await client.closePlaySession(sessionId: streamSessionId)
        }
        if cancelled {
          finishDownloadInterruptedIfCurrent(runId: runId, completion: completion)
        } else {
          finishDownloadFailureIfCurrent(runId: runId, itemId: id, completion: completion)
        }
      }
    }
  }
}
