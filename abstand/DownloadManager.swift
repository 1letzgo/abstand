import Combine
import Foundation

@MainActor
final class DownloadManager: ObservableObject {
  @Published private(set) var activeItemId: String?
  @Published private(set) var progress: Double = 0

  private var task: Task<Void, Never>?

  private static let trackDownloadMaxAttempts = 3

  private var downloadRunId: Int = 0

  func cancel() {
    task?.cancel()
    task = nil
    activeItemId = nil
    progress = 0
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

  /// Nur aufrufen, wenn `runId` noch der aktuelle Download-Lauf ist (verhindert Löschen durch abgebrochene Tasks).
  private func finishDownloadFailureIfCurrent(runId: Int, itemId: String, completion: ((Bool) -> Void)?) {
    guard runId == downloadRunId else { return }
    deleteDownload(itemId: itemId)
    activeItemId = nil
    progress = 0
    completion?(false)
  }

  private func finishDownloadSuccessIfCurrent(runId: Int, completion: ((Bool) -> Void)?) {
    guard runId == downloadRunId else { return }
    activeItemId = nil
    progress = 1
    completion?(true)
  }

  func startDownload(client: ABSAPIClient, book: ABSBook, completion: ((Bool) -> Void)? = nil) {
    cancel()
    downloadRunId += 1
    let runId = downloadRunId
    let id = book.id
    activeItemId = id
    progress = 0
    task = Task { @MainActor in
      var playSessionId: String?
      do {
        let folder: URL
        do {
          let root = try downloadsRootURL()
          try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
          setExcludedFromBackup(root)
          let itemDir = root.appendingPathComponent(id, isDirectory: true)
          if FileManager.default.fileExists(atPath: itemDir.path) {
            try FileManager.default.removeItem(at: itemDir)
          }
          try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
          setExcludedFromBackup(itemDir)
          folder = itemDir
        } catch {
          guard runId == downloadRunId else { return }
          activeItemId = nil
          progress = 0
          completion?(false)
          return
        }

        let session = try await client.startPlaySession(
          itemId: id,
          deviceId: PlaybackController.stableDeviceId(),
          appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
        playSessionId = session.id

        let serverTracks = session.audioTracks ?? book.media.tracks ?? []
        guard !serverTracks.isEmpty else { throw ABSPlaybackError.noTracks }
        let sorted = serverTracks.sorted { $0.index < $1.index }

        let weights: [Double] = sorted.map { tr in
          let d = tr.duration
          if d.isFinite, d > 0 { return max(d, 30) }
          return 300
        }
        let sumW = max(weights.reduce(0, +), 1)
        var doneW: Double = 0

        var savedAudioExtension: String?
        for (i, tr) in sorted.enumerated() {
          try Task.checkCancellation()
          progress = doneW / sumW
          let suggested = folder.appendingPathComponent(PlaybackController.trackFilename(index: tr.index))
          let finalURL: URL
          if let ino = tr.ino, !ino.isEmpty {
            let fileURL = try await client.itemFileDownloadURL(itemId: id, ino: ino)
            finalURL = try await client.downloadAuthenticatedFile(
              from: fileURL,
              to: suggested,
              maxAttempts: Self.trackDownloadMaxAttempts
            )
          } else {
            let stream = try await client.publicStreamURL(sessionId: session.id, trackIndex: tr.index)
            finalURL = try await client.downloadAuthenticatedFile(
              from: stream,
              to: suggested,
              maxAttempts: Self.trackDownloadMaxAttempts
            )
          }
          if savedAudioExtension == nil {
            savedAudioExtension = finalURL.pathExtension.lowercased()
          }
          doneW += weights[i]
          progress = min(1, doneW / sumW)
        }

        let totalDur: Double?
        if session.duration > 0 {
          totalDur = session.duration
        } else if let d = book.media.duration, d > 0 {
          totalDur = d
        } else {
          totalDur = nil
        }
        let manifest = ABSDownloadManifest(
          format: 1,
          libraryItemId: id,
          libraryId: book.libraryId,
          displayTitle: book.displayTitle,
          displayAuthor: book.displayAuthors,
          playSessionId: session.id,
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
          }
        )
        try manifest.write(to: folder)
        try? await client.closePlaySession(sessionId: session.id)
        playSessionId = nil
        finishDownloadSuccessIfCurrent(runId: runId, completion: completion)
      } catch {
        if let sid = playSessionId {
          try? await client.closePlaySession(sessionId: sid)
        }
        finishDownloadFailureIfCurrent(runId: runId, itemId: id, completion: completion)
      }
    }
  }
}
