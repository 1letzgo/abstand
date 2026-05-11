import AVFoundation
import Combine
import CoreImage
import Foundation
import MediaPlayer
import SwiftUI
import UIKit

enum ABSPlaybackError: LocalizedError {
  case noTracks
  var errorDescription: String? {
    switch self {
    case .noTracks: return "No audio tracks found for this audiobook."
    }
  }
}

/// `AVPlayer`/`NotificationCenter`-Callbacks sind `@Sendable`; Zustandsänderungen laufen über Main-Queue + `MainActor.assumeIsolated`.
@MainActor
final class PlaybackController: NSObject, ObservableObject {
  @Published private(set) var activeBook: ABSBook?
  /// Gesetzte Podcast-Folge (`play/.../episodeId`); bei Hörbüchern `nil`.
  @Published private(set) var activePlaybackEpisodeId: String?
  @Published private(set) var isPlaying = false
  @Published private(set) var globalPosition: Double = 0
  @Published private(set) var totalDuration: Double = 0
  @Published private(set) var isBuffering = false
  @Published var sleepEndDate: Date?
  /// Mini-Player bleibt sichtbar nach „Fertig“, ohne aktives Hörbuch.
  @Published private(set) var showMiniPlayerPlaceholder = false
  /// Hintergrundfarbe der Mini-Player-Karte, abgeleitet vom Cover (sonst `AppTheme.card`).
  @Published private(set) var miniPlayerBarFillColor: Color = AppTheme.card
  /// Kapitel 1…n (nach `start` sortiert); leer wenn der Server keine Kapitel liefert.
  private var sortedChapters: [ABSChapter] = []
  @Published private(set) var chapterCount: Int = 0
  /// 1-basierter Index des aktuellen Kapitels, `0` wenn keine Kapitel.
  @Published private(set) var currentChapterOrdinal: Int = 0
  @Published private(set) var currentChapterTitle: String = ""

  /// Gespeicherte Abspielgeschwindigkeit (Menü: `playbackRatePresets`); wiederhergestellt bei App-Start.
  @Published private(set) var playbackRate: Float = 1.0

  static let playbackRatePresets: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  private static let playbackRateDefaultsKey = "abstand_playback_rate"

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var statusObserver: NSKeyValueObservation?
  /// `timeControlStatus`: System/andere App kann pausieren ohne unsere `pause()` — UI angleichen.
  private var playbackEngineStateObserver: NSKeyValueObservation?

  private var playSessionId: String?
  private var apiClient: ABSAPIClient?

  /// `true`, solange ein Audiobookshelf-Stream mit Session-Sync aktiv ist.
  var isRemotePlaySessionActive: Bool { playSessionId != nil }
  private var tracks: [ABSAudioTrack] = []
  private var trackStarts: [Double] = []
  private var currentTrackIndex: Int = 0
  private var pendingListenSeconds: Double = 0
  private var lastListenTick: Date = .init()
  private var syncTask: Task<Void, Never>?

  private var localRoot: URL?
  /// Nach Laden: sofort abspielen oder nur positionieren (App-Start).
  private var shouldAutoPlayAfterLoad = true

  private var nowPlayingArtwork: MPMediaItemArtwork?
  private var coverLoadTask: Task<Void, Never>?
  /// Nur in `deinit` (nicht isoliert) und im Beobachter-Setup verwendet.
  nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
  nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var sleepWakeTask: Task<Void, Never>?

  override init() {
    super.init()
    playbackRate = Self.loadSavedPlaybackRate()
    ensureAudioSessionForPlayback()
    configureRemoteCommands()
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self else { return }
      let info = notification.userInfo
      let typeRaw = (info?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue ?? 0
      let optionRaw = (info?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
      MainActor.assumeIsolated {
        self.handleAudioSessionInterruption(typeRaw: typeRaw, optionRaw: optionRaw)
      }
    }
    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] n in
      guard let self else { return }
      let raw = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
      MainActor.assumeIsolated {
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable {
          self.syncPlayingStateFromPlayerIfNeeded()
        }
      }
    }
    $sleepEndDate
      .sink { [weak self] end in
        self?.rescheduleSleepWake(for: end)
      }
      .store(in: &cancellables)
  }

  deinit {
    sleepWakeTask?.cancel()
    if let interruptionObserver {
      NotificationCenter.default.removeObserver(interruptionObserver)
    }
    if let routeChangeObserver {
      NotificationCenter.default.removeObserver(routeChangeObserver)
    }
  }

  /// Wanduhr-basiert: funktioniert auch bei pausiertem Player (nicht nur über `AVPlayer`-Ticks).
  private func rescheduleSleepWake(for end: Date?) {
    sleepWakeTask?.cancel()
    sleepWakeTask = nil
    guard let end else { return }
    let delay = end.timeIntervalSinceNow
    if delay <= 0 {
      sleepEndDate = nil
      pause()
      return
    }
    let expectedEnd = end
    sleepWakeTask = Task { @MainActor [weak self] in
      do {
        let ns = UInt64(max(1, delay * 1_000_000_000))
        try await Task.sleep(nanoseconds: ns)
      } catch {
        return
      }
      guard let self else { return }
      guard !Task.isCancelled else { return }
      guard self.sleepEndDate == expectedEnd else { return }
      self.sleepEndDate = nil
      self.pause()
    }
  }

  /// Session für Hintergrund / Sperrbildschirm; `setCategory` nur bei Bedarf (erneuter Aufruf kann sonst kurz unterbrechen).
  func ensureAudioSessionForPlayback() {
    let session = AVAudioSession.sharedInstance()
    let opts: AVAudioSession.CategoryOptions = [
      .allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay,
    ]
    do {
      if session.category != .playback || session.mode != .spokenAudio {
        try session.setCategory(
          .playback,
          mode: .spokenAudio,
          policy: .longFormAudio,
          options: opts
        )
      }
      try session.setActive(true, options: [])
    } catch {
      try? session.setCategory(
        .playback,
        mode: .default,
        options: opts
      )
      try? session.setActive(true, options: [])
    }
  }

  private func handleAudioSessionInterruption(typeRaw: UInt, optionRaw: UInt) {
    guard let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
    switch type {
    case .ended:
      let opts = AVAudioSession.InterruptionOptions(rawValue: optionRaw)
      if opts.contains(.shouldResume) {
        ensureAudioSessionForPlayback()
        if isPlaying {
          applyPlayingRate()
        }
      }
    case .began:
      syncPlayingStateFromPlayerIfNeeded()
    @unknown default:
      break
    }
  }

  /// Abgleich nach App-Rückkehr oder wenn das OS den Player stilllegt (ohne unser `pause()`).
  func refreshPlaybackStateFromEngine() {
    syncPlayingStateFromPlayerIfNeeded()
  }

  /// Echter Abspielzustand (Unterbrechungen, andere Audio-App, Kopfhörer ziehen).
  private static func engineIndicatesPlaying(_ player: AVPlayer) -> Bool {
    switch player.timeControlStatus {
    case .playing, .waitingToPlayAtSpecifiedRate:
      return true
    case .paused:
      return false
    @unknown default:
      return player.rate > 0.001
    }
  }

  private func syncPlayingStateFromPlayerIfNeeded() {
    guard let p = player, p.currentItem != nil else { return }
    let enginePlaying = Self.engineIndicatesPlaying(p)
    guard isPlaying != enginePlaying else { return }
    if enginePlaying {
      isPlaying = true
      lastListenTick = Date()
    } else {
      accumulateListenTime()
      isPlaying = false
      Task { await flushSync(force: true) }
    }
    updateNowPlaying()
  }

  private func applyBackgroundPlaybackPolicy(_ player: AVPlayer?) {
    guard let player else { return }
    player.allowsExternalPlayback = true
    player.automaticallyWaitsToMinimizeStalling = false
    if #available(iOS 15.0, macOS 12.0, *) {
      player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }
  }

  private func configureRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      MainActor.assumeIsolated { self.play() }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      MainActor.assumeIsolated { self.pause() }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      MainActor.assumeIsolated { self.togglePlayPause() }
      return .success
    }
    center.skipBackwardCommand.preferredIntervals = [15]
    center.skipBackwardCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      MainActor.assumeIsolated { self.skip(seconds: -15) }
      return .success
    }
    center.skipForwardCommand.preferredIntervals = [30]
    center.skipForwardCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      MainActor.assumeIsolated { self.skip(seconds: 30) }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      let t = e.positionTime
      guard let self else { return .commandFailed }
      MainActor.assumeIsolated { self.seek(global: t) }
      return .success
    }
  }

  func setMiniPlayerPlaceholder(_ show: Bool) {
    showMiniPlayerPlaceholder = show
  }

  func tearDownPlayer() {
    sleepWakeTask?.cancel()
    sleepWakeTask = nil
    sleepEndDate = nil
    showMiniPlayerPlaceholder = false
    miniPlayerBarFillColor = AppTheme.card
    coverLoadTask?.cancel()
    coverLoadTask = nil
    nowPlayingArtwork = nil
    syncTask?.cancel()
    syncTask = nil
    if let sid = playSessionId, let client = apiClient {
      Task {
        try? await client.closePlaySession(sessionId: sid)
      }
    }
    playSessionId = nil
    apiClient = nil
    if let timeObserver, let p = player {
      p.removeTimeObserver(timeObserver)
    }
    timeObserver = nil
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    endObserver = nil
    statusObserver?.invalidate()
    statusObserver = nil
    playbackEngineStateObserver?.invalidate()
    playbackEngineStateObserver = nil
    player?.pause()
    player = nil
    tracks = []
    trackStarts = []
    sortedChapters = []
    chapterCount = 0
    currentChapterOrdinal = 0
    currentChapterTitle = ""
    currentTrackIndex = 0
    pendingListenSeconds = 0
    isPlaying = false
    activeBook = nil
    activePlaybackEpisodeId = nil
    localRoot = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  func playBook(
    client: ABSAPIClient,
    book: ABSBook,
    resumeAt resumeHint: Double,
    localDownloadRoot: URL?,
    episodeId: String? = nil,
    autoPlay: Bool = true
  ) async throws {
    tearDownPlayer()
    ensureAudioSessionForPlayback()
    shouldAutoPlayAfterLoad = autoPlay
    apiClient = client
    activeBook = book
    let trimmedEp = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let resolvedEpisodeId: String? = trimmedEp.isEmpty ? nil : trimmedEp
    activePlaybackEpisodeId = resolvedEpisodeId
    localRoot = localDownloadRoot

    if let root = localDownloadRoot, Self.allTracksPresent(root: root, book: book) {
      try await startLocalPlayback(book: book, root: root, resumeAt: resumeHint)
    } else {
      try await startRemotePlayback(
        client: client, book: book, resumeAt: resumeHint, episodeId: resolvedEpisodeId)
    }

    scheduleCoverLoad(for: book.id)
    startPeriodicSync()
  }

  static func stableDeviceId() -> String {
    let k = "abstand_device_id"
    if let existing = UserDefaults.standard.string(forKey: k) { return existing }
    let id = UUID().uuidString
    UserDefaults.standard.set(id, forKey: k)
    return id
  }

  /// Nur als Vorschlagsname für den Download-Stamm (`track_3`); die echte Endung setzt der Client per MIME/Sniff.
  static func trackFilename(index: Int) -> String {
    "track_\(index).abs"
  }

  /// Lokale Track-Datei mit erkennbarer Endung (AVPlayer erkennt `.abs` oft nicht).
  static func resolvedLocalTrackURL(root: URL, trackIndex: Int, manifest: ABSDownloadManifest?) -> URL? {
    let preferred =
      manifest?.audioFileExtension?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: ".", with: "")
    var exts: [String] = []
    if let p = preferred, !p.isEmpty { exts.append(p) }
    exts.append(contentsOf: ["m4a", "mp3", "aac", "flac", "ogg", "wav", "abs"])
    var seen = Set<String>()
    for ext in exts where seen.insert(ext).inserted {
      let u = root.appendingPathComponent("track_\(trackIndex).\(ext)")
      if FileManager.default.fileExists(atPath: u.path) { return u }
    }
    let prefix = "track_\(trackIndex)."
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: nil)
    else { return nil }
    return urls.first { $0.lastPathComponent.hasPrefix(prefix) }
  }

  private static func allTracksPresent(root: URL, book: ABSBook) -> Bool {
    let manifest = ABSDownloadManifest.load(from: root)
    if let m = manifest, !m.tracks.isEmpty {
      return m.tracks.allSatisfy { tr in
        resolvedLocalTrackURL(root: root, trackIndex: tr.index, manifest: m) != nil
      }
    }
    let list = book.media.tracks ?? []
    guard !list.isEmpty else { return false }
    for t in list {
      if resolvedLocalTrackURL(root: root, trackIndex: t.index, manifest: manifest) == nil {
        return false
      }
    }
    return true
  }

  /// Globale Startzeiten: Server-`startOffset`, falls plausibel (monoton); sonst aus Dauern kumulieren.
  private func rebuildTrackStarts() {
    trackStarts = []
    guard !tracks.isEmpty else { return }
    let offsets = tracks.map(\.startOffset)
    let allOffsetsZero = offsets.allSatisfy { $0 == 0 }
    let monotonic =
      zip(offsets, offsets.dropFirst()).allSatisfy { $0.1 + 0.001 >= $0.0 }
    if tracks.count > 1, allOffsetsZero || !monotonic {
      var t = 0.0
      for tr in tracks {
        trackStarts.append(t)
        t += tr.duration
      }
    } else {
      trackStarts = offsets
    }
  }

  private func trackIndex(forGlobal g: Double) -> Int {
    guard !trackStarts.isEmpty else { return 0 }
    for i in stride(from: trackStarts.count - 1, through: 0, by: -1) {
      if g >= trackStarts[i] { return i }
    }
    return 0
  }

  private func globalTime(trackIndex: Int, localSeconds: Double) -> Double {
    guard trackIndex < trackStarts.count else { return localSeconds }
    return trackStarts[trackIndex] + localSeconds
  }

  private func startLocalPlayback(book: ABSBook, root: URL, resumeAt: Double) async throws {
    let manifest = ABSDownloadManifest.load(from: root)
    let fromManifest: [ABSAudioTrack]? = manifest.flatMap { m in
      guard !m.tracks.isEmpty else { return nil }
      return m.tracks.map { row in
        ABSAudioTrack(
          index: row.index,
          startOffset: row.startOffset,
          duration: row.duration,
          title: row.title,
          ino: nil
        )
      }
    }
    let catalogTracks = (book.media.tracks ?? []).sorted { $0.index < $1.index }
    let mediaTracks = (fromManifest ?? catalogTracks).sorted { $0.index < $1.index }
    guard !mediaTracks.isEmpty else { throw ABSPlaybackError.noTracks }
    tracks = mediaTracks
    rebuildTrackStarts()
    let manifestDur = manifest?.totalDuration.flatMap { $0 > 0 ? $0 : nil }
    totalDuration =
      manifestDur
      ?? book.media.duration
      ?? (trackStarts.last! + tracks.last!.duration)
    applyChapters(from: book, sessionChapters: nil)

    currentTrackIndex = trackIndex(forGlobal: resumeAt)
    let offsetInTrack = max(0, resumeAt - trackStarts[currentTrackIndex])

    guard
      let url = Self.resolvedLocalTrackURL(
        root: root, trackIndex: tracks[currentTrackIndex].index, manifest: manifest)
    else { throw ABSPlaybackError.noTracks }
    let asset = AVURLAsset(url: url)
    if #available(iOS 15.0, *) {
      _ = try? await asset.load(.isPlayable)
    }
    let item = AVPlayerItem(asset: asset)
    player = AVPlayer(playerItem: item)
    applyBackgroundPlaybackPolicy(player)
    installObservers()
    let resumeSnapshot = resumeAt
    player?.seek(to: CMTime(seconds: offsetInTrack, preferredTimescale: 600)) { [weak self] _ in
      guard let self else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        MainActor.assumeIsolated {
          self.globalPosition = resumeSnapshot
          self.updateChapterUI(global: resumeSnapshot)
          self.playSessionId = nil
          self.updateNowPlaying()
          if self.shouldAutoPlayAfterLoad {
            self.applyPlayingRate()
            self.isPlaying = true
          } else {
            self.player?.pause()
            self.isPlaying = false
          }
          self.lastListenTick = Date()
        }
      }
    }
  }

  private func startRemotePlayback(
    client: ABSAPIClient,
    book: ABSBook,
    resumeAt: Double,
    episodeId: String?
  ) async throws {
    let session = try await client.startPlaySession(
      itemId: book.id,
      episodeId: episodeId,
      deviceId: Self.stableDeviceId(),
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    )
    playSessionId = session.id
    let uiBook = session.bookForPlayerUI()
    activeBook = uiBook

    let serverTracks = session.audioTracks ?? book.media.tracks ?? []
    guard !serverTracks.isEmpty else { throw ABSPlaybackError.noTracks }
    tracks = serverTracks.sorted { $0.index < $1.index }
    rebuildTrackStarts()
    applyChapters(
      from: uiBook, sessionChapters: session.chapters, libraryItemFallback: session.libraryItem)

    let serverResume = max(session.currentTime, resumeAt)
    totalDuration =
      session.duration > 0
      ? session.duration
      : (uiBook.media.duration ?? book.media.duration ?? (trackStarts.last! + tracks.last!.duration))

    currentTrackIndex = trackIndex(forGlobal: serverResume)
    let offsetInTrack = max(0, serverResume - trackStarts[currentTrackIndex])

    let streamURL = try await client.publicStreamURL(
      sessionId: session.id,
      trackIndex: tracks[currentTrackIndex].index
    )
    let asset = AVURLAsset(url: streamURL, options: AVURLAsset.httpHeaderOptions(token: await client.currentToken()))
    let item = AVPlayerItem(asset: asset)
    player = AVPlayer(playerItem: item)
    applyBackgroundPlaybackPolicy(player)
    installObservers()
    let resumeSnapshot = serverResume
    player?.seek(to: CMTime(seconds: offsetInTrack, preferredTimescale: 600)) { [weak self] _ in
      guard let self else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        MainActor.assumeIsolated {
          self.globalPosition = resumeSnapshot
          self.updateChapterUI(global: resumeSnapshot)
          self.updateNowPlaying()
          if self.shouldAutoPlayAfterLoad {
            self.applyPlayingRate()
            self.isPlaying = true
          } else {
            self.player?.pause()
            self.isPlaying = false
          }
          self.lastListenTick = Date()
        }
      }
    }
  }

  private func installObservers() {
    guard let p = player else { return }
    let interval = CMTime(seconds: 0.35, preferredTimescale: 600)
    timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated {
        self.tick()
      }
    }

    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: p.currentItem,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated {
        self.advanceToNextTrack()
      }
    }

    statusObserver = p.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
      let buffering = item.status == .unknown
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        MainActor.assumeIsolated {
          self.isBuffering = buffering
        }
      }
    }

    playbackEngineStateObserver?.invalidate()
    playbackEngineStateObserver = p.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      guard let self else { return }
      Task { @MainActor [weak self] in
        self?.syncPlayingStateFromPlayerIfNeeded()
      }
    }
  }

  private func tick() {
    accumulateListenTime()
    refreshGlobalFromPlayer()
    updateChapterUI(global: globalPosition)
    updateNowPlaying()
    if let end = sleepEndDate, Date() >= end {
      sleepEndDate = nil
      pause()
    }
  }

  private func accumulateListenTime() {
    let now = Date()
    if isPlaying {
      pendingListenSeconds += now.timeIntervalSince(lastListenTick)
    }
    lastListenTick = now
  }

  private func refreshGlobalFromPlayer() {
    guard let p = player, let item = p.currentItem else { return }
    let local = p.currentTime().seconds
    if local.isFinite {
      globalPosition = globalTime(trackIndex: currentTrackIndex, localSeconds: local)
    }
    if item.status == .failed {
      isBuffering = false
    }
  }

  private func advanceToNextTrack() {
    guard currentTrackIndex + 1 < tracks.count else {
      globalPosition = totalDuration
      updateChapterUI(global: globalPosition)
      pause()
      return
    }
    currentTrackIndex += 1
    Task {
      await loadCurrentTrack(play: true, localOffset: 0)
    }
  }

  private func loadCurrentTrack(play: Bool, localOffset: Double) async {
    guard let book = activeBook else { return }
    if let root = localRoot, Self.allTracksPresent(root: root, book: book) {
      let man = ABSDownloadManifest.load(from: root)
      guard
        let url = Self.resolvedLocalTrackURL(
          root: root, trackIndex: tracks[currentTrackIndex].index, manifest: man)
      else { return }
      let asset = AVURLAsset(url: url)
      if #available(iOS 15.0, *) {
        _ = try? await asset.load(.isPlayable)
      }
      replacePlayerItem(AVPlayerItem(asset: asset), localOffset: localOffset, play: play)
      return
    }
    guard let client = apiClient, let sid = playSessionId else { return }
    do {
      let streamURL = try await client.publicStreamURL(
        sessionId: sid,
        trackIndex: tracks[currentTrackIndex].index
      )
      let asset = AVURLAsset(url: streamURL, options: AVURLAsset.httpHeaderOptions(token: await client.currentToken()))
      replacePlayerItem(AVPlayerItem(asset: asset), localOffset: localOffset, play: play)
    } catch {
      pause()
    }
  }

  private func replacePlayerItem(_ item: AVPlayerItem, localOffset: Double, play: Bool) {
    if let timeObserver, let p = player {
      p.removeTimeObserver(timeObserver)
    }
    timeObserver = nil
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    endObserver = nil
    statusObserver?.invalidate()
    statusObserver = nil

    player?.replaceCurrentItem(with: item)
    installObservers()
    let offsetSnapshot = localOffset
    player?.seek(to: CMTime(seconds: localOffset, preferredTimescale: 600)) { [weak self] _ in
      guard let self else { return }
      let shouldPlay = play
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        MainActor.assumeIsolated {
          let g = self.globalTime(trackIndex: self.currentTrackIndex, localSeconds: offsetSnapshot)
          self.globalPosition = g
          self.updateChapterUI(global: g)
          self.updateNowPlaying()
          if shouldPlay {
            self.applyPlayingRate()
            self.isPlaying = true
          }
        }
      }
    }
  }

  /// Startet die Wiedergabe mit der gewählten `playbackRate` (nach Störung / neuem Item / Play).
  private func applyPlayingRate() {
    guard let p = player else { return }
    if #available(iOS 15.0, *) {
      p.playImmediately(atRate: playbackRate)
    } else {
      p.play()
      p.rate = playbackRate
    }
  }

  func setPlaybackRate(_ rate: Float) {
    let snapped =
      Self.playbackRatePresets.min(by: { abs($0 - rate) < abs($1 - rate) }) ?? 1.0
    playbackRate = snapped
    UserDefaults.standard.set(Double(snapped), forKey: Self.playbackRateDefaultsKey)
    if isPlaying {
      player?.rate = snapped
    }
    updateNowPlaying()
  }

  private static func loadSavedPlaybackRate() -> Float {
    let v = UserDefaults.standard.double(forKey: playbackRateDefaultsKey)
    guard v > 0.09 else { return 1.0 }
    let f = Float(v)
    return playbackRatePresets.min(by: { abs($0 - f) < abs($1 - f) }) ?? 1.0
  }

  func play() {
    ensureAudioSessionForPlayback()
    applyPlayingRate()
    isPlaying = true
    lastListenTick = Date()
    updateNowPlaying()
  }

  func pause() {
    accumulateListenTime()
    player?.pause()
    isPlaying = false
    updateNowPlaying()
    Task { await flushSync(force: true) }
  }

  func togglePlayPause() {
    if isPlaying { pause() } else { play() }
  }

  func skip(seconds: Double) {
    seek(global: globalPosition + seconds)
  }

  /// Vorheriges Kapitel: zuerst Kapitelanfang, sonst vorheriges Kapitel.
  func skipToPreviousChapter() {
    guard let idx = chapterIndex(for: globalPosition) else { return }
    let start = sortedChapters[idx].start
    if globalPosition > start + 1.5 {
      seek(global: start)
    } else if idx > 0 {
      seek(global: sortedChapters[idx - 1].start)
    } else {
      seek(global: 0)
    }
  }

  /// Nächstes Kapitel (Anfang).
  func skipToNextChapter() {
    guard let idx = chapterIndex(for: globalPosition), idx + 1 < sortedChapters.count else { return }
    seek(global: sortedChapters[idx + 1].start)
  }

  var canSkipToPreviousChapter: Bool {
    guard let idx = chapterIndex(for: globalPosition) else { return false }
    return idx > 0 || globalPosition > sortedChapters[idx].start + 1.5
  }

  var canSkipToNextChapter: Bool {
    guard let idx = chapterIndex(for: globalPosition) else { return false }
    return idx + 1 < sortedChapters.count
  }

  func seek(global: Double) {
    let g = min(max(0, global), max(totalDuration - 0.25, 0))
    let idx = trackIndex(forGlobal: g)
    let offset = g - trackStarts[idx]
    if idx != currentTrackIndex {
      currentTrackIndex = idx
      Task {
        await loadCurrentTrack(play: isPlaying, localOffset: offset)
      }
    } else {
      let position = g
      player?.seek(to: CMTime(seconds: offset, preferredTimescale: 600)) { [weak self] _ in
        guard let self else { return }
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          MainActor.assumeIsolated {
            self.globalPosition = position
            self.updateChapterUI(global: position)
            self.updateNowPlaying()
          }
        }
      }
    }
    globalPosition = g
    updateChapterUI(global: g)
    updateNowPlaying()
  }

  private func applyChapters(
    from book: ABSBook,
    sessionChapters: [ABSChapter]?,
    libraryItemFallback: ABSBook? = nil
  ) {
    // Play session often returns `chapters: []`; `??` alone would discard embedded item chapters.
    let fromSession = sessionChapters ?? []
    let fromBook = book.media.chapters ?? []
    let fromFallback = libraryItemFallback?.media.chapters ?? []
    let raw: [ABSChapter]
    if !fromSession.isEmpty {
      raw = fromSession
    } else if !fromBook.isEmpty {
      raw = fromBook
    } else {
      raw = fromFallback
    }
    sortedChapters = raw.sorted { $0.start < $1.start }
    chapterCount = sortedChapters.count
    updateChapterUI(global: globalPosition)
  }

  private func chapterIndex(for global: Double) -> Int? {
    guard !sortedChapters.isEmpty else { return nil }
    var idx = 0
    for (i, ch) in sortedChapters.enumerated() {
      if global >= ch.start { idx = i }
    }
    return idx
  }

  private func updateChapterUI(global: Double) {
    guard !sortedChapters.isEmpty else {
      chapterCount = 0
      currentChapterOrdinal = 0
      currentChapterTitle = ""
      return
    }
    chapterCount = sortedChapters.count
    let idx = chapterIndex(for: global) ?? 0
    currentChapterOrdinal = idx + 1
    currentChapterTitle = sortedChapters[idx].title
  }

  private func startPeriodicSync() {
    syncTask?.cancel()
    syncTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 20_000_000_000)
        await self?.flushSync(force: false)
      }
    }
  }

  private func flushSync(force: Bool) async {
    guard let sid = playSessionId, let client = apiClient else { return }
    accumulateListenTime()
    let raw = pendingListenSeconds
    let tl = Int(floor(raw))
    if !force, tl < 1 { return }
    pendingListenSeconds = max(0, raw - Double(tl))
    do {
      try await client.syncPlaySession(sessionId: sid, timeListened: max(0, tl), currentTime: globalPosition)
    } catch {
      pendingListenSeconds += Double(tl)
    }
  }

  private func updateNowPlaying() {
    guard let book = activeBook else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: book.displayTitle,
      MPMediaItemPropertyArtist: book.displayAuthors,
      MPMediaItemPropertyPlaybackDuration: totalDuration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: globalPosition,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(playbackRate),
      MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPMediaType.audioBook.rawValue),
    ]
    if let art = nowPlayingArtwork {
      info[MPMediaItemPropertyArtwork] = art
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func scheduleCoverLoad(for bookId: String) {
    coverLoadTask?.cancel()
    coverLoadTask = Task { [weak self] in
      await self?.loadNowPlayingArtwork(bookId: bookId)
    }
  }

  private func loadNowPlayingArtwork(bookId: String) async {
    guard let client = apiClient else { return }
    let url = await client.coverURL(itemId: bookId)
    let data: Data
    do {
      data = try await client.authenticatedData(from: url)
    } catch {
      return
    }
    guard !Task.isCancelled, activeBook?.id == bookId else { return }
    guard let image = UIImage(data: data) else { return }
    miniPlayerBarFillColor = Self.miniPlayerTintColor(from: image)
    let artwork = Self.makeNowPlayingArtwork(from: image)
    nowPlayingArtwork = artwork
    updateNowPlaying()
  }

  /// Dunkle Kartenfarbe aus dem Cover-Mittel (lesbar mit hellem Text).
  private static func miniPlayerTintColor(from image: UIImage) -> Color {
    guard let ciImage = CIImage(image: image) else { return AppTheme.card }
    var extent = ciImage.extent
    if !extent.width.isFinite || extent.width < 1 || !extent.height.isFinite || extent.height < 1 {
      extent = CGRect(origin: .zero, size: image.size)
    }
    guard extent.width >= 1, extent.height >= 1,
      let filter = CIFilter(
        name: "CIAreaAverage",
        parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: CIVector(cgRect: extent)]
      ),
      let output = filter.outputImage
    else { return AppTheme.card }
    var bitmap = [UInt8](repeating: 0, count: 4)
    let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    ctx.render(
      output,
      toBitmap: &bitmap,
      rowBytes: 4,
      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    let r = CGFloat(bitmap[0]) / 255
    let g = CGFloat(bitmap[1]) / 255
    let b = CGFloat(bitmap[2]) / 255
    let mix: CGFloat = 0.44
    let floor: CGFloat = 0.07
    let nr = min(1, r * mix + floor)
    let ng = min(1, g * mix + floor)
    let nb = min(1, b * mix + floor)
    return Color(red: Double(nr), green: Double(ng), blue: Double(nb))
  }

  private static func makeNowPlayingArtwork(from image: UIImage) -> MPMediaItemArtwork {
    let preview = scaleImage(image, maxSide: 512)
    let w = preview.size.width
    let h = preview.size.height
    let bounds =
      w > 0 && h > 0
      ? CGSize(width: w, height: h)
      : CGSize(width: 320, height: 320)
    return MPMediaItemArtwork(boundsSize: bounds) { requested in
      let side = max(64, min(1024, max(requested.width, requested.height)))
      return scaleImage(image, maxSide: side)
    }
  }

  private static func scaleImage(_ image: UIImage, maxSide: CGFloat) -> UIImage {
    let w = image.size.width
    let h = image.size.height
    guard w > 0, h > 0, maxSide > 0 else { return image }
    let longest = max(w, h)
    guard longest > maxSide else { return image }
    let scale = maxSide / longest
    let nw = max(1, floor(w * scale))
    let nh = max(1, floor(h * scale))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = image.scale
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: nw, height: nh), format: format)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: CGSize(width: nw, height: nh)))
    }
  }

  func closeSessionIfNeeded() async {
    await flushSync(force: true)
    if let sid = playSessionId, let client = apiClient {
      try? await client.closePlaySession(sessionId: sid)
    }
    playSessionId = nil
  }
}

private extension AVURLAsset {
  static func httpHeaderOptions(token: String) -> [String: Any] {
    ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
  }
}
