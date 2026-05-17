import Combine
import Foundation

private struct DownloadWIP: Codable {
  var storageItemId: String
  var libraryItemId: String
  var episodeId: String?
  var completedTrackIndexes: [Int]
}

@MainActor
final class DownloadManager: ObservableObject {
  @Published private(set) var activeItemId: String?
  @Published private(set) var progress: Double = 0

  private var task: Task<Void, Never>?

  private static let trackDownloadMaxAttempts = 3
  private static let wipFilename = "download-wip.json"

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

  private func wipURL(in folder: URL) -> URL {
    folder.appendingPathComponent(Self.wipFilename)
  }

  private func loadWIP(folder: URL, storageId: String, episodeId: String?) -> DownloadWIP? {
    let url = wipURL(in: folder)
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard let wip = try? JSONDecoder().decode(DownloadWIP.self, from: data) else { return nil }
    guard wip.storageItemId == storageId else { return nil }
    let wEp = wip.episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let eEp = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if wEp != eEp { return nil }
    return wip
  }

  private func saveWIP(_ wip: DownloadWIP, folder: URL) throws {
    let data = try JSONEncoder().encode(wip)
    try data.write(to: wipURL(in: folder), options: .atomic)
  }

  /// Nur aufrufen, wenn `runId` noch der aktuelle Download-Lauf ist (verhindert Löschen durch abgebrochene Tasks).
  private func finishDownloadFailureIfCurrent(runId: Int, itemId: String, completion: ((Bool) -> Void)?) {
    guard runId == downloadRunId else { return }
    deleteDownload(itemId: itemId)
    activeItemId = nil
    progress = 0
    completion?(false)
  }

  private func finishDownloadInterruptedIfCurrent(runId: Int, completion: ((Bool) -> Void)?) {
    guard runId == downloadRunId else { return }
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

  func startDownload(
    client: ABSAPIClient,
    book: ABSBook,
    episodeId: String? = nil,
    storageItemId: String? = nil,
    reusePlaySessionId: String? = nil,
    completion: ((Bool) -> Void)? = nil
  ) {
    cancel()
    downloadRunId += 1
    let runId = downloadRunId
    let trimmedEp = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let resolvedEp: String? = trimmedEp.isEmpty ? nil : trimmedEp
    let id = storageItemId ?? book.id
    activeItemId = id
    progress = 0
    let reuseSid: String? = {
      guard let r = reusePlaySessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
        return nil
      }
      return r
    }()

    task = Task { @MainActor in
      var ownsPlaySession = false
      var streamSessionId = ""
      var serverSession: ABSPlaySession?
      do {
        let folder: URL
        var resumeCompleted = Set<Int>()
        do {
          let root = try downloadsRootURL()
          try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
          setExcludedFromBackup(root)
          let itemDir = root.appendingPathComponent(id, isDirectory: true)
          if FileManager.default.fileExists(atPath: itemDir.path),
            ABSDownloadManifest.load(from: itemDir) == nil,
            let wip = loadWIP(folder: itemDir, storageId: id, episodeId: resolvedEp),
            !wip.completedTrackIndexes.isEmpty
          {
            resumeCompleted = Set(wip.completedTrackIndexes)
          } else if FileManager.default.fileExists(atPath: itemDir.path) {
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

        if let reuse = reuseSid,
          let tracksFromBook = book.media.tracks,
          !tracksFromBook.isEmpty
        {
          streamSessionId = reuse
          ownsPlaySession = false
        } else {
          let session = try await client.startPlaySession(
            itemId: book.id,
            episodeId: resolvedEp,
            deviceId: PlaybackController.stableDeviceId(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
          )
          serverSession = session
          streamSessionId = session.id
          ownsPlaySession = true
        }

        let serverTracks =
          (serverSession?.audioTracks ?? book.media.tracks ?? [])
          .sorted { $0.index < $1.index }
        guard !serverTracks.isEmpty else { throw ABSPlaybackError.noTracks }
        let sorted = serverTracks

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
          libraryItemId: book.id,
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
          let finalURL: URL
          if let ino = tr.ino, !ino.isEmpty {
            let fileURL = try await client.itemFileDownloadURL(itemId: id, ino: ino)
            finalURL = try await client.downloadAuthenticatedFile(
              from: fileURL,
              to: suggested,
              maxAttempts: Self.trackDownloadMaxAttempts
            )
          } else {
            let stream = try await client.publicStreamURL(sessionId: streamSessionId, trackIndex: tr.index)
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
        } else if let d = book.media.duration, d > 0 {
          totalDur = d
        } else {
          totalDur = nil
        }
        let manifest = ABSDownloadManifest(
          format: 1,
          libraryItemId: book.id,
          episodeId: resolvedEp,
          libraryId: book.libraryId,
          displayTitle: book.displayTitle,
          displayAuthor: book.displayAuthors,
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
          }
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
