import AVFoundation
import Combine
import CoreImage
import Foundation
import MediaPlayer
import os
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

/// Skip-Intervalle — außerhalb von `@MainActor PlaybackController` referenzierbar (z. B. Snapshots).
enum ABSPlaybackSkipDefaults {
  static let intervalOptions: [Int] = [5, 10, 15, 30, 45, 60]
  static let backwardSeconds = 15
  static let forwardSeconds = 30
}

/// Aktive Sleep-Timer-Konfiguration (für Popover-Anzeige).
enum SleepTimerMode: Equatable {
  case off
  case minutes(Int)
  case chapters(Int)
}

/// `AVPlayer`/`NotificationCenter`-Callbacks sind `@Sendable`; Zustandsänderungen laufen über Main-Queue + `MainActor.assumeIsolated`.
@MainActor
final class PlaybackController: NSObject, ObservableObject {
  /// Mitlesen (SpeechAnalyzer / on-device).
  let liveTranscription = PlayerLiveTranscriptionController()

  @Published private(set) var activeBook: ABSBook?
  /// Gesetzte Podcast-Folge (`play/.../episodeId`); bei Hörbüchern `nil`.
  @Published private(set) var activePlaybackEpisodeId: String?
  /// Lokale Show-Vorgabe für die Spracherkennung; hat Vorrang vor den Item-Metadaten.
  private(set) var transcriptionLanguageOverride: String?
  @Published private(set) var isPlaying = false
  /// Laufende Position — absichtlich **nicht** `@Published`, damit SwiftUI nicht ~3×/s invalidiert
  /// (`tabViewBottomAccessory`, Listen). Vollplayer nutzt `TimelineView`; Sync/Now Playing lesen hier.
  private(set) var globalPosition: Double = 0
  @Published private(set) var totalDuration: Double = 0
  @Published private(set) var isBuffering = false

  /// Floating-Bar Play/Pause: AVPlayerItem wirklich bereit (nicht nur `playBook` returned).
  var isPlaybackControlsReady: Bool {
    guard activeBook != nil else { return true }
    guard let player, let item = player.currentItem else { return false }
    guard item.status == .readyToPlay else { return false }
    if isBuffering { return false }
    if player.timeControlStatus == .waitingToPlayAtSpecifiedRate { return false }
    return true
  }

  @Published var sleepEndDate: Date?
  @Published var sleepTimerMode: SleepTimerMode = .off
  /// Leere Mini-Player-Leiste („Nothing playing“) ohne aktives Medium.
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

  /// EQ-Preset für die Wiedergabe (Voice Focus etc.) — über `MTAudioProcessingTap` auf `AVPlayerItem`.
  @Published private(set) var eqPreset: AudioEQPreset = AudioEQPreset.loadSaved()
  private static let eqPresetDefaultsKey = "abstand_eq_preset"
  /// Tap + Context müssen für die Lebensdauer des Player-Items gehalten werden.
  private var eqTap: MTAudioProcessingTap?
  private var eqTapContext: AudioEQTapContext?
  /// Player-Item, an dem der EQ-Tap hängt — für sauberes Abriss beim Trackwechsel
  /// (`currentItem` zeigt dann schon das neue Item; Tap muss am alten Item abgehängt werden).
  private weak var eqTapPlayerItem: AVPlayerItem?

  /// Skip-Intervalle für Zurück/Vor (Player, Mini-Player, Sperrbildschirm).
  /// Nur Werte mit SF-Symbolen (`gobackward.N` / `goforward.N`).
  static let skipIntervalOptions = ABSPlaybackSkipDefaults.intervalOptions
  static let defaultSkipBackwardSeconds = ABSPlaybackSkipDefaults.backwardSeconds
  static let defaultSkipForwardSeconds = ABSPlaybackSkipDefaults.forwardSeconds
  private static let skipBackwardDefaultsKey = "abstand_skip_backward_seconds"
  private static let skipForwardDefaultsKey = "abstand_skip_forward_seconds"

  @Published var skipBackwardSeconds: Int = defaultSkipBackwardSeconds {
    didSet {
      let clamped = Self.clampedSkipSeconds(
        skipBackwardSeconds, fallback: Self.defaultSkipBackwardSeconds)
      if clamped != skipBackwardSeconds {
        skipBackwardSeconds = clamped
        return
      }
      guard clamped != oldValue else { return }
      UserDefaults.standard.set(clamped, forKey: Self.skipBackwardDefaultsKey)
      updateRemoteSkipIntervals()
    }
  }

  @Published var skipForwardSeconds: Int = defaultSkipForwardSeconds {
    didSet {
      let clamped = Self.clampedSkipSeconds(
        skipForwardSeconds, fallback: Self.defaultSkipForwardSeconds)
      if clamped != skipForwardSeconds {
        skipForwardSeconds = clamped
        return
      }
      guard clamped != oldValue else { return }
      UserDefaults.standard.set(clamped, forKey: Self.skipForwardDefaultsKey)
      updateRemoteSkipIntervals()
    }
  }

  private var player: AVPlayer?
  private var timeObserver: Any?
  /// Read-Along: häufigere Position-Updates für flüssigeres Teleprompter-Scrollen.
  private var readAlongHighFrequencyTicks = false
  private var endObserver: NSObjectProtocol?
  private var statusObserver: NSKeyValueObservation?
  /// `timeControlStatus`: System/andere App kann pausieren ohne unsere `pause()` — UI angleichen.
  private var playbackEngineStateObserver: NSKeyValueObservation?
  /// Serialisiert Resume nach Pause/Fremd-App — verhindert parallele Session-Neuaufbauten.
  private var playResumeTask: Task<Void, Never>?

  private var playSessionId: String?
  private var apiClient: ABSAPIClient?

  /// `true`, solange ein Audiobookshelf-Stream mit Session-Sync aktiv ist.
  var isRemotePlaySessionActive: Bool { playSessionId != nil }

  /// Wenn gerade **dieselbe** Remote-Session läuft, dieselbe `sessionId` für parallele Downloads nutzen — vermeidet ein zweites `POST …/play`, das die Wiedergabe beenden würde.
  func playSessionIdForReuseWhenDownloadingSameItem(libraryItemId: String, episodeId: String?) -> String? {
    guard let sid = playSessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty else {
      return nil
    }
    guard let b = activeBook, b.id == libraryItemId else { return nil }
    let playingEp = activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let wantEp = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if playingEp != wantEp { return nil }
    return sid
  }

  /// Tracks der aktiven Remote-Session — für parallele Downloads ohne zweites `POST …/play` (Absorb-Muster).
  func audioTracksForActiveSessionReuse() -> [ABSAudioTrack] {
    guard isRemotePlaySessionActive, !tracks.isEmpty else { return [] }
    return tracks
  }

  private var tracks: [ABSAudioTrack] = []
  private var trackStarts: [Double] = []
  private var currentTrackIndex: Int = 0
  private var pendingListenSeconds: Double = 0
  private var lastListenTick: Date = .init()
  private var syncTask: Task<Void, Never>?

  private var localRoot: URL?
  /// `true`, wenn die Wiedergabe aus einem lokalen Download-Ordner läuft (kein Auto-Download nötig).
  var isPlaybackFromOfflineDownload: Bool { localRoot != nil }
  /// Wie `playBook`: alle Tracks lokal — sonst Stream trotz Download-Ordner.
  var isUsingLocalTrackFiles: Bool {
    guard let root = localRoot, let book = activeBook else { return false }
    return Self.allTracksPresent(root: root, book: book)
  }

  /// Read-along nur bei vollständig heruntergeladenem Titel mit lokalen Audio-Dateien.
  var isReadAlongDownloadReady: Bool { isUsingLocalTrackFiles }

  var canBuildTranscriptionStreamContext: Bool {
    apiClient != nil && playSessionId != nil
  }
  /// Nach Laden: sofort abspielen oder nur positionieren (App-Start).
  private var shouldAutoPlayAfterLoad = true

  /// Wird bei jedem periodischen Player-Tick aufgerufen (z. B. Smart-Download).
  var onPlaybackTick: (() -> Void)?
  /// Letzter Track eines Hörbuchs zu Ende (keine Podcast-Folge).
  var onAudiobookPlaybackCompleted: (() -> Void)?
  /// Letzter Track einer Podcast-Folge zu Ende.
  var onPodcastEpisodePlaybackCompleted: (() -> Void)?
  /// Lokale Download-Wiedergabe ohne aktive Play-Session: PATCH / Offline-Hörzeit (vgl. Absorb).
  var onLocalPlaybackWithoutSessionSync: ((Int, Double, Double) async -> Void)?

  /// Wie Absorb `_playFromLocal`: Session starten wenn online (nicht im Offline-Home-Modus).
  private var attemptServerPlaySessionForLocal = true

  private var nowPlayingArtwork: MPMediaItemArtwork?
  private var coverLoadTask: Task<Void, Never>?
  /// Für Cover-Verlauf im Vollplayer (nur Dark); bei Appearance-Wechsel neu anwenden.
  private var lastCoverImageForBarTint: UIImage?
  /// Nur in `deinit` (nicht isoliert) und im Beobachter-Setup verwendet.
  nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
  nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?
  private var cancellables = Set<AnyCancellable>()
  private var sleepWakeTask: Task<Void, Never>?
  /// Verbleibende Laufzeit; bei Pause eingefroren, `sleepEndDate` nur während Wiedergabe.
  private var sleepTimerRemaining: TimeInterval?
  private var sleepTimerPaused = false
  /// Für `.shouldResume` nach Telefonanruf / Unterbrechung.
  private var wasPlayingBeforeInterruption = false

  /// Intelligenter Sleep-Timer: letzte Konfiguration + Zeitstempel bei natürlichem Ablauf.
  /// Wenn die Wiedergabe innerhalb von `sleepTimerGraceSeconds` nach Ablauf neu startet,
  /// wird der Timer mit derselben Dauer (nur `.minutes`) automatisch wiederhergestellt.
  private static let sleepTimerGraceSeconds: TimeInterval = 60
  private var lastExpiredSleepMode: SleepTimerMode?
  private var lastExpiredSleepSeconds: TimeInterval?
  private var lastExpiredSleepDate: Date?
  /// Ziel-Kapitelindex (0-basiert) für den Kapitel-Sleep-Timer; `nil` = nicht aktiv.
  /// Wanduhr-unabhängig: in `tick()` geprüft, sobald das Ziel-Kapitel erreicht wird.
  private var sleepTimerChapterTarget: Int?

  override init() {
    let sp = AppLog.launchSignposter.beginInterval("playbackControllerInit")
    defer { AppLog.launchSignposter.endInterval("playbackControllerInit", sp) }
    super.init()
    playbackRate = Self.loadSavedPlaybackRate()
    skipBackwardSeconds = Self.loadSkipBackwardSeconds()
    skipForwardSeconds = Self.loadSkipForwardSeconds()
    // AVAudioSession erst bei Wiedergabe aktivieren — nicht beim Kaltstart (vgl. avkit-Skill).
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
    liveTranscription.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)

    Task { @MainActor in
      await liveTranscription.refreshReadAlongAvailability()
    }

    $sleepEndDate
      .sink { [weak self] end in
        guard let self else { return }
        if end == nil {
          // Kapitel-Timer nutzt bewusst kein `sleepEndDate` — nicht als „aus" werten.
          if !self.sleepTimerPaused, self.sleepTimerChapterTarget == nil {
            self.sleepTimerMode = .off
            self.sleepTimerRemaining = nil
          }
        } else {
          self.rescheduleSleepWake(for: end)
        }
      }
      .store(in: &cancellables)
  }

  /// Countdown für UI — bei Pause konstant, bei Wiedergabe läuft die Uhr weiter.
  /// Kapitel-Timer hat keine Laufzeit → `nil` (UI zeigt stattdessen den Modus-Label).
  var sleepTimerDisplaySeconds: TimeInterval? {
    guard sleepTimerMode != .off else { return nil }
    if sleepTimerPaused {
      return sleepTimerRemaining
    }
    if let end = sleepEndDate {
      return max(0, end.timeIntervalSinceNow)
    }
    if let remaining = sleepTimerRemaining, remaining > 0 {
      return remaining
    }
    return nil
  }

  var isSleepTimerActive: Bool {
    guard sleepTimerMode != .off else { return false }
    if sleepTimerChapterTarget != nil { return true }
    return (sleepTimerDisplaySeconds ?? 0) > 0
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

  /// Sleep-Timer komplett aus (manuell „Aus”, Ablauf, Track-Ende).
  func clearSleepTimer() {
    sleepWakeTask?.cancel()
    sleepWakeTask = nil
    sleepTimerRemaining = nil
    sleepTimerPaused = false
    sleepEndDate = nil
    sleepTimerChapterTarget = nil
    // Manuelles „Aus” oder Track-Ende → kein intelligenter Restart mehr.
    lastExpiredSleepMode = nil
    lastExpiredSleepSeconds = nil
    lastExpiredSleepDate = nil
  }

  func applySleepTimerRemaining(_ seconds: TimeInterval) {
    sleepTimerRemaining = max(0, seconds)
    // Minuten-Modus aktiv: Kapitel-Target verwerfen (beide Modi schließen sich gegenseitig aus).
    sleepTimerChapterTarget = nil
    // Konfiguration für intelligenten Restart merken (nur `.minutes` — Kapitel-Dauer wäre nach
    // Restart semantisch falsch). Bei aktivem Timer altes Grace-Fenster verwerfen.
    if seconds > 0, case .minutes(let m) = sleepTimerMode, m > 0 {
      lastExpiredSleepMode = .minutes(m)
      lastExpiredSleepSeconds = TimeInterval(m * 60)
    }
    lastExpiredSleepDate = nil
    if isPlaying {
      sleepTimerPaused = false
      scheduleSleepTimerWakeIfNeeded()
    } else {
      sleepWakeTask?.cancel()
      sleepWakeTask = nil
      sleepEndDate = nil
    }
  }

  /// Kapitel-Sleep-Timer setzen: feuert, sobald die Wiedergabe das Ende des Ziel-Kapitels
  /// erreicht. Wanduhr-unabhängig — wird in `tick()` geprüft, nicht über `sleepEndDate`.
  func applySleepTimerChapterTarget(_ targetIndex: Int) {
    sleepTimerChapterTarget = targetIndex
    sleepTimerRemaining = nil
    sleepTimerPaused = false
    sleepEndDate = nil
    sleepWakeTask?.cancel()
    sleepWakeTask = nil
    lastExpiredSleepDate = nil
  }

  private func scheduleSleepTimerWakeIfNeeded() {
    guard let remaining = sleepTimerRemaining, remaining > 0, !sleepTimerPaused, isPlaying else {
      sleepWakeTask?.cancel()
      sleepWakeTask = nil
      sleepEndDate = nil
      return
    }
    sleepEndDate = Date().addingTimeInterval(remaining)
  }

  private func pauseSleepTimer() {
    guard sleepTimerMode != .off else { return }
    guard sleepEndDate != nil || (sleepTimerRemaining ?? 0) > 0 else { return }
    if let end = sleepEndDate {
      sleepTimerRemaining = max(0, end.timeIntervalSinceNow)
    }
    sleepTimerPaused = true
    sleepWakeTask?.cancel()
    sleepWakeTask = nil
    sleepEndDate = nil
  }

  private func resumeSleepTimerIfNeeded() {
    guard sleepTimerMode != .off, let remaining = sleepTimerRemaining, remaining > 0 else { return }
    sleepTimerPaused = false
    scheduleSleepTimerWakeIfNeeded()
  }

  /// Wanduhr-basiert: funktioniert auch bei pausiertem Player (nicht nur über `AVPlayer`-Ticks).
  private func rescheduleSleepWake(for end: Date?) {
    sleepWakeTask?.cancel()
    sleepWakeTask = nil
    guard let end else { return }
    let delay = end.timeIntervalSinceNow
    if delay <= 0 {
      markSleepTimerExpired()
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
      self.markSleepTimerExpired()
      self.pause()
    }
  }

  /// Natürlicher Ablauf: Timer-Daten zurücksetzen, aber Grace-Fenster (60 s) für intelligenten
  /// Restart öffnen — im Gegensatz zu `clearSleepTimer()`, das auch die Grace-Daten löscht.
  private func markSleepTimerExpired() {
    let mode = sleepTimerMode
    let seconds = sleepTimerRemaining
    sleepWakeTask?.cancel()
    sleepWakeTask = nil
    sleepTimerRemaining = nil
    sleepTimerPaused = false
    sleepEndDate = nil
    sleepTimerChapterTarget = nil
    sleepTimerMode = .off
    // Nur `.minutes`-Modus für intelligenten Restart; Konfiguration wurde beim Setzen gemerkt.
    if case .minutes = mode, seconds ?? 0 > 0 {
      lastExpiredSleepDate = Date()
    } else {
      lastExpiredSleepMode = nil
      lastExpiredSleepSeconds = nil
      lastExpiredSleepDate = nil
    }
  }

  /// Intelligenter Restart: bei Wiedergabe-Start innerhalb des Grace-Fensters (60 s) nach
  /// natürlichem Ablauf den Sleep-Timer mit derselben Dauer (`.minutes`) automatisch neu starten.
  private func restoreSleepTimerIfWithinGraceIfNeeded() {
    guard let expired = lastExpiredSleepDate,
      Date().timeIntervalSince(expired) <= Self.sleepTimerGraceSeconds,
      case .minutes(let m) = lastExpiredSleepMode ?? .off,
      let seconds = lastExpiredSleepSeconds, seconds > 0, m > 0
    else { return }
    sleepTimerMode = .minutes(m)
    applySleepTimerRemaining(seconds)
    lastExpiredSleepDate = nil
  }

  /// Session für Hintergrund / Sperrbildschirm; `setCategory` nur bei Bedarf (erneuter Aufruf kann sonst kurz unterbrechen).
  /// `reclaimFromOtherApps`: Tonspur von anderer App zurückholen (explizites Play), nicht beim bloßen Vordergrund-Wechsel.
  func ensureAudioSessionForPlayback(reclaimFromOtherApps: Bool = false) {
    let session = AVAudioSession.sharedInstance()
    let categoryOpts: AVAudioSession.CategoryOptions = [
      .allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay,
    ]
    var activeOpts: AVAudioSession.SetActiveOptions = []
    if reclaimFromOtherApps {
      activeOpts.insert(.notifyOthersOnDeactivation)
    }
    do {
      if session.category != .playback || session.mode != .spokenAudio {
        try session.setCategory(
          .playback,
          mode: .spokenAudio,
          policy: .longFormAudio,
          options: categoryOpts
        )
      }
      try session.setActive(true, options: activeOpts)
    } catch {
      try? session.setCategory(
        .playback,
        mode: .default,
        options: categoryOpts
      )
      try? session.setActive(true, options: activeOpts)
    }
  }

  private func handleAudioSessionInterruption(typeRaw: UInt, optionRaw: UInt) {
    guard let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
    switch type {
    case .began:
      wasPlayingBeforeInterruption = isPlaying
      player?.pause()
      syncPlayingStateFromPlayerIfNeeded()
    case .ended:
      ensureAudioSessionForPlayback(reclaimFromOtherApps: true)
      let opts = AVAudioSession.InterruptionOptions(rawValue: optionRaw)
      if opts.contains(.shouldResume), wasPlayingBeforeInterruption {
        play()
      } else {
        syncPlayingStateFromPlayerIfNeeded()
      }
      wasPlayingBeforeInterruption = false
    @unknown default:
      break
    }
  }

  /// Abgleich nach App-Rückkehr oder wenn das OS den Player stilllegt (ohne unser `pause()`).
  func refreshPlaybackStateFromEngine() {
    reconcilePlayingStateWithEngine()
  }

  /// Vordergrund nach langer Pause: UI-Zustand angleichen (kein Ton-Overtake, keine Session-Aktivierung).
  func handleReturnToForeground() {
    refreshPlaybackStateFromEngine()
    reconcileSleepTimerAfterBackground()
  }

  /// Sleep-Timer nach Hintergrund-Phase angleichen: AVPlayer läuft im Hintergrund weiter,
  /// aber `Task.sleep` / periodische Observer sind unzuverlässig. Der Timer kann im Hintergrund
  /// pausiert worden sein (kurzzeitiger `timeControlStatus`-Wechsel) oder sogar abgelaufen sein,
  /// ohne dass `pause()` feuern konnte.
  private func reconcileSleepTimerAfterBackground() {
    guard sleepTimerMode != .off else { return }
    // Kapitel-Timer ist positionsbasiert und braucht keine Wanduhr-Reconcile.
    guard sleepTimerChapterTarget == nil else { return }
    // Timer pausiert im Hintergrund → Restlaufzeit prüfen.
    if sleepTimerPaused, let remaining = sleepTimerRemaining {
      if remaining <= 0 {
        // Im Hintergrund abgelaufen — Wiedergabe stoppen.
        markSleepTimerExpired()
        pause()
      } else {
        // Noch Restlaufzeit — Timer fortsetzen, Countdown läuft wieder.
        resumeSleepTimerIfNeeded()
      }
      return
    }
    // Timer nicht pausiert, aber evtl. im Hintergrund abgelaufen (Observer/Tick nicht gefeuert).
    if let end = sleepEndDate, Date() >= end {
      clearSleepTimer()
      pause()
    }
  }

  /// UI/`isPlaying` an echten `AVPlayer`-Zustand — auch wenn `currentItem` fehlt oder Engine pausiert wurde.
  private func reconcilePlayingStateWithEngine() {
    guard let p = player else {
      if isPlaying {
        isPlaying = false
        updateNowPlaying()
      }
      return
    }
    guard p.currentItem != nil else {
      if isPlaying {
        isPlaying = false
        updateNowPlaying()
      }
      return
    }
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
      // Engine-Recovery (z. B. nach Bluetooth-Wechsel / Interruption): der `timeControlStatus`-
      // Observer setzt isPlaying=true, ohne dass `play()` durchläuft. Sleep-Timer hier
      // symmetrisch zum `pauseSleepTimer()` im else-Zweig wiederherstellen, sonst bleibt der
      // Countdown eingefroren und der Timer feuert nie.
      resumeSleepTimerIfNeeded()
    } else {
      accumulateListenTime()
      isPlaying = false
      pauseSleepTimer()
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

  private func updateRemoteSkipIntervals() {
    let center = MPRemoteCommandCenter.shared()
    center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardSeconds)]
    center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardSeconds)]
  }

  static func gobackwardSystemImage(seconds: Int) -> String {
    guard skipIntervalOptions.contains(seconds) else { return "gobackward.\(defaultSkipBackwardSeconds)" }
    return "gobackward.\(seconds)"
  }

  static func goforwardSystemImage(seconds: Int) -> String {
    guard skipIntervalOptions.contains(seconds) else { return "goforward.\(defaultSkipForwardSeconds)" }
    return "goforward.\(seconds)"
  }

  static func skipAccessibilityLabel(backward: Bool, seconds: Int) -> String {
    backward ? "Back \(seconds) seconds" : "Forward \(seconds) seconds"
  }

  private static func clampedSkipSeconds(_ value: Int, fallback: Int) -> Int {
    skipIntervalOptions.contains(value) ? value : fallback
  }

  private static func loadSkipBackwardSeconds() -> Int {
    let d = UserDefaults.standard
    guard d.object(forKey: skipBackwardDefaultsKey) != nil else { return defaultSkipBackwardSeconds }
    return clampedSkipSeconds(d.integer(forKey: skipBackwardDefaultsKey), fallback: defaultSkipBackwardSeconds)
  }

  private static func loadSkipForwardSeconds() -> Int {
    let d = UserDefaults.standard
    guard d.object(forKey: skipForwardDefaultsKey) != nil else { return defaultSkipForwardSeconds }
    return clampedSkipSeconds(d.integer(forKey: skipForwardDefaultsKey), fallback: defaultSkipForwardSeconds)
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
    center.skipBackwardCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      MainActor.assumeIsolated {
        self.skip(seconds: -Double(self.skipBackwardSeconds))
      }
      return .success
    }
    center.skipForwardCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      MainActor.assumeIsolated {
        self.skip(seconds: Double(self.skipForwardSeconds))
      }
      return .success
    }
    updateRemoteSkipIntervals()
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

  /// Nach einem Theme-Wechsel die palette-abhängige Cover-Tönung aktualisieren.
  func refreshMiniPlayerBarFillForAppearance() {
    applyMiniPlayerBarFillFromStoredCover()
  }

  /// Teleprompter bei Hintergrund / Display aus beenden (Audio läuft weiter).
  func disableTeleprompterIfNeeded() {
    guard liveTranscription.isTeleprompterModeActive else { return }
    Task { @MainActor in
      await liveTranscription.disable()
    }
  }

  func tearDownPlayer() {
    DebugLogCollector.shared.log("tearDownPlayer START activeBook=\(activeBook?.id ?? "nil") episodeId=\(activePlaybackEpisodeId ?? "nil") isPlaying=\(isPlaying)")
    playResumeTask?.cancel()
    playResumeTask = nil
    liveTranscription.playbackDidStop()
    clearSleepTimer()
    showMiniPlayerPlaceholder = false
    miniPlayerBarFillColor = AppTheme.card
    lastCoverImageForBarTint = nil
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
    teardownEQTap()
    tracks = []
    trackStarts = []
    sortedChapters = []
    chapterCount = 0
    currentChapterOrdinal = 0
    currentChapterTitle = ""
    currentTrackIndex = 0
    pendingListenSeconds = 0
    isPlaying = false
    globalPosition = 0
    totalDuration = 0
    isBuffering = false
    activeBook = nil
    activePlaybackEpisodeId = nil
    transcriptionLanguageOverride = nil
    localRoot = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  func playBook(
    client: ABSAPIClient,
    book: ABSBook,
    resumeAt resumeHint: Double,
    localDownloadRoot: URL?,
    episodeId: String? = nil,
    transcriptionLanguageOverride: String? = nil,
    autoPlay: Bool = true,
    attemptServerPlaySession: Bool = true,
    /// Bei Neustart nach „Fertig“: Client-Position statt Server-Ende (`max(session, resume)`).
    preferClientResumePosition: Bool = false
  ) async throws {
    if liveTranscription.isTeleprompterModeActive {
      await liveTranscription.disable()
    }
    tearDownPlayer()
    ensureAudioSessionForPlayback()
    shouldAutoPlayAfterLoad = autoPlay
    apiClient = client
    activeBook = book
    let language = transcriptionLanguageOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.transcriptionLanguageOverride = language.isEmpty ? nil : language
    let trimmedEp = episodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let resolvedEpisodeId: String? = trimmedEp.isEmpty ? nil : trimmedEp
    activePlaybackEpisodeId = resolvedEpisodeId
    localRoot = localDownloadRoot
    attemptServerPlaySessionForLocal = attemptServerPlaySession

    do {
      if let root = localDownloadRoot, Self.allTracksPresent(root: root, book: book) {
        try await startLocalPlayback(
          client: client,
          book: book,
          root: root,
          resumeAt: resumeHint,
          preferClientResumePosition: preferClientResumePosition
        )
      } else {
        try await startRemotePlayback(
          client: client,
          book: book,
          resumeAt: resumeHint,
          episodeId: resolvedEpisodeId,
          preferClientResumePosition: preferClientResumePosition
        )
      }
      scheduleCoverLoad(for: book.id)
      startPeriodicSync()
    } catch {
      tearDownPlayer()
      throw error
    }
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

  /// Alle erwarteten Track-Dateien im Download-Ordner vorhanden (z. B. nach abgeschlossenem Download).
  static func allLocalTracksPresentForOfflinePlayback(root: URL, book: ABSBook) -> Bool {
    allTracksPresent(root: root, book: book)
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

  /// Play-Session für lokale Dateien (Absorb: max. 5s Timeout, sonst Offline-Modus mit PATCH/Flush).
  private func startPlaySessionWithTimeout(
    client: ABSAPIClient,
    itemId: String,
    episodeId: String?,
    timeoutSeconds: UInt64 = 5
  ) async -> ABSPlaySession? {
    await withTaskGroup(of: ABSPlaySession?.self) { group in
      group.addTask {
        try? await client.startPlaySession(
          itemId: itemId,
          episodeId: episodeId,
          deviceId: Self.stableDeviceId(),
          appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }

  private func startLocalPlayback(
    client: ABSAPIClient,
    book: ABSBook,
    root: URL,
    resumeAt resumeHint: Double,
    preferClientResumePosition: Bool = false
  ) async throws {
    playSessionId = nil
    var resumeAt = resumeHint
    let manifest = ABSDownloadManifest.load(from: root)
    let manifestChapters = manifest?.chapters?.map { ABSChapter(manifest: $0) }

    if attemptServerPlaySessionForLocal {
      if let session = await startPlaySessionWithTimeout(
        client: client,
        itemId: book.id,
        episodeId: activePlaybackEpisodeId
      ) {
        playSessionId = session.id
        let uiBook = session.bookForPlayerUI()
        activeBook = uiBook
        applyChapters(
          from: book,
          sessionChapters: session.chapters,
          libraryItemFallback: session.libraryItem,
          manifestChapters: manifestChapters
        )
        let serverResume =
          preferClientResumePosition
          ? resumeAt
          : max(session.currentTime, resumeAt)
        let cap = session.duration > 0 ? session.duration : serverResume
        resumeAt = min(serverResume, cap)
      }
    }

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
    if sortedChapters.isEmpty {
      applyChapters(
        from: book,
        sessionChapters: nil,
        libraryItemFallback: activeBook,
        manifestChapters: manifestChapters
      )
    }

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
    applyEQToCurrentItem()
    let resumeSnapshot = resumeAt
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

  private func startRemotePlayback(
    client: ABSAPIClient,
    book: ABSBook,
    resumeAt: Double,
    episodeId: String?,
    preferClientResumePosition: Bool = false
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
      from: book,
      sessionChapters: session.chapters,
      libraryItemFallback: session.libraryItem
    )

    let serverResume =
      preferClientResumePosition
      ? resumeAt
      : max(session.currentTime, resumeAt)
    let safeResume = min(serverResume, session.duration > 0 ? session.duration : serverResume)
    totalDuration =
      session.duration > 0
      ? session.duration
      : (uiBook.media.duration ?? book.media.duration ?? (trackStarts.last! + tracks.last!.duration))

    currentTrackIndex = trackIndex(forGlobal: safeResume)
    let offsetInTrack = max(0, safeResume - trackStarts[currentTrackIndex])

    let streamURL = try await client.publicStreamURL(
      sessionId: session.id,
      trackIndex: tracks[currentTrackIndex].index
    )
    let asset = AVURLAsset(url: streamURL, options: AVURLAsset.httpHeaderOptions(token: await client.currentToken()))
    let item = AVPlayerItem(asset: asset)
    player = AVPlayer(playerItem: item)
    applyBackgroundPlaybackPolicy(player)
    installObservers()
    applyEQToCurrentItem()
    let resumeSnapshot = safeResume
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

  /// Zeit-Observer-Intervall für Read-Along (0,08 s) vs. normal (0,35 s).
  func setReadAlongHighFrequencyTicks(_ active: Bool) {
    guard readAlongHighFrequencyTicks != active else { return }
    readAlongHighFrequencyTicks = active
    guard player != nil else { return }
    installPeriodicTimeObserver()
  }

  private func installPeriodicTimeObserver() {
    if let timeObserver, let p = player {
      p.removeTimeObserver(timeObserver)
    }
    timeObserver = nil
    guard let p = player else { return }
    let seconds = readAlongHighFrequencyTicks ? 0.08 : 0.35
    let interval = CMTime(seconds: seconds, preferredTimescale: 600)
    timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated {
        self.tick()
      }
    }
  }

  private func installObservers() {
    guard player != nil else { return }
    installPeriodicTimeObserver()

    guard let p = player else { return }
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
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        MainActor.assumeIsolated {
          self.updateBufferingState(for: item)
        }
      }
    }

    playbackEngineStateObserver?.invalidate()
    playbackEngineStateObserver = p.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      guard let self else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let item = self.player?.currentItem {
          self.updateBufferingState(for: item)
        }
        self.syncPlayingStateFromPlayerIfNeeded()
      }
    }
    if let item = p.currentItem {
      updateBufferingState(for: item)
    }
  }

  private func updateBufferingState(for item: AVPlayerItem) {
    let waiting =
      player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
      && item.status != .failed
    isBuffering = item.status == .unknown || waiting
  }

  private func tick() {
    accumulateListenTime()
    onPlaybackTick?()
    liveTranscription.handlePlaybackTick(player: self)
    refreshGlobalFromPlayer()
    updateChapterUI(global: globalPosition)
    updateNowPlaying()
    // Zeit-Timer: Wanduhr-abhängig.
    if isPlaying, let end = sleepEndDate, Date() >= end {
      clearSleepTimer()
      pause()
    }
    // Kapitel-Timer: feuert, sobald die Wiedergabe das Ende des Ziel-Kapitels erreicht
    // (positionsbasiert, nicht wanduhr-abhängig — immun gegen Pause/Resume-Zyklen).
    if isPlaying, let target = sleepTimerChapterTarget,
      target < sortedChapters.count,
      playbackGlobalPosition() >= chapterEndTime(at: target)
    {
      clearSleepTimer()
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

  /// Frische Abspielposition (AVPlayer + Track-Offset), z. B. für Lesezeichen — nicht nur gecachtes `globalPosition`.
  func snapshotPlaybackTimeSeconds() -> Int {
    max(0, Int(liveGlobalPlaybackPosition.rounded(.down)))
  }

  /// Live-Position für Read-Along (AVPlayer), falls verfügbar — sonst `globalPosition`.
  var liveGlobalPlaybackPosition: Double {
    if let p = player, p.currentItem != nil {
      let local = p.currentTime().seconds
      if local.isFinite {
        let g = globalTime(trackIndex: currentTrackIndex, localSeconds: local)
        if g.isFinite, g >= 0 { return g }
      }
    }
    let raw = globalPosition
    guard raw.isFinite, raw >= 0 else { return 0 }
    return raw
  }

  private func advanceToNextTrack() {
    guard currentTrackIndex + 1 < tracks.count else {
      DebugLogCollector.shared.log("advanceToNextTrack END OF TRACKS episodeId=\(activePlaybackEpisodeId ?? "nil") isPodcast=\(activePlaybackEpisodeId != nil)")
      globalPosition = totalDuration
      updateChapterUI(global: globalPosition)
      pause()
      if activePlaybackEpisodeId == nil {
        onAudiobookPlaybackCompleted?()
      } else {
        onPodcastEpisodePlaybackCompleted?()
      }
      return
    }
    currentTrackIndex += 1
    liveTranscription.notifyPlaybackTrackAdvanced()
    Task {
      await loadCurrentTrack(play: true, localOffset: 0)
    }
  }

  private func loadCurrentTrack(play: Bool, localOffset: Double, pauseOnFailure: Bool = true) async {
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
      if pauseOnFailure {
        pause()
      }
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
    applyEQToCurrentItem()
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

  // MARK: - EQ

  /// Setzt das EQ-Preset und wendet es auf das aktuelle Player-Item an.
  /// Live-Reconfigure des Processors — kein Tap-Rebuild, kein audioMix-Swap während
  /// der Audio-Realtime-Thread läuft (das wäre die Crash-Ursache beim Preset-Wechsel).
  func setEQPreset(_ preset: AudioEQPreset) {
    guard preset != eqPreset else { return }
    eqPreset = preset
    UserDefaults.standard.set(preset.rawValue, forKey: Self.eqPresetDefaultsKey)
    if let ctx = eqTapContext {
      // Tap existiert schon: nur Filterkoeffizienten tauschen (thread-sicher im Processor).
      ctx.reconfigure(preset: preset)
    } else {
      // Noch kein Tap (z. B. Player noch nicht geladen) — beim nächsten Apply greift das neue Preset.
      applyEQToCurrentItem()
    }
  }

  /// Hängt den EQ-Tap ans aktive `AVPlayerItem`. Bei Preset-Wechsel wird der Tap
  /// NICHT neu gebaut — stattdessen rekonfiguriert `setEQPreset` den Processor live.
  /// Der Tap bleibt auch bei `.flat` bestehen (Processor mit leerer Filterliste = Passthrough),
  /// damit ein späterer Wechsel kein audioMix-Swap-while-playing braucht.
  /// Bei Item-Wechsel (anderes `currentItem`) muss der alte Tap abgerissen werden —
  /// erkannt daran, dass `eqTapPlayerItem` nicht mehr das aktuelle Item ist.
  func applyEQToCurrentItem() {
    guard let item = player?.currentItem else { return }
    // Bereits am selben Item? Nichts tun.
    if eqTapContext != nil, eqTapPlayerItem === item { return }
    // Anderes Item (Trackwechsel) — alten Tap sauber abreißen.
    teardownEQTap()

    let processor = AudioEQProcessor()
    let context = AudioEQTapContext(processor: processor, preset: eqPreset)
    guard let tap = AudioEQTapFactory.makeTap(context: context) else { return }

    let params = AVMutableAudioMixInputParameters()
    params.audioTapProcessor = tap
    let mix = AVMutableAudioMix()
    mix.inputParameters = [params]
    item.audioMix = mix

    eqTap = tap
    eqTapContext = context
    eqTapPlayerItem = item
  }

  /// Gibt den aktuellen EQ-Tap + Context frei. Zuerst `audioMix` am Item abhängen —
  /// triggert `finalize` auf dem Tap, bevor der Controller seine Context-Referenz loslässt.
  private func teardownEQTap() {
    eqTapPlayerItem?.audioMix = nil
    eqTap = nil
    eqTapContext = nil
    eqTapPlayerItem = nil
  }

  func play() {
    playResumeTask?.cancel()
    playResumeTask = Task { @MainActor [weak self] in
      await self?.performPlayResume()
    }
  }

  /// Resume nach Pause, Unterbrechung oder Fremd-App: Session + Stream ggf. neu verbinden.
  private func performPlayResume() async {
    guard !Task.isCancelled else { return }
    ensureAudioSessionForPlayback(reclaimFromOtherApps: true)

    if localRoot != nil, playSessionId == nil, attemptServerPlaySessionForLocal {
      await recreatePlaySessionForLocalPlaybackIfNeeded()
    }

    if !isUsingLocalTrackFiles, activeBook != nil, apiClient != nil, playSessionId == nil {
      await recoverPlaySessionAfterSyncFailure(lostTimeListened: 0)
    }

    if let item = player?.currentItem, item.status == .failed {
      let local = player?.currentTime().seconds ?? 0
      let offset = local.isFinite ? max(0, local) : 0
      await loadCurrentTrack(play: true, localOffset: offset)
      return
    }

    guard !Task.isCancelled else { return }
    beginPlaybackEngine()
    await schedulePlaybackEngineKickstartIfStillPaused()
  }

  private func beginPlaybackEngine() {
    applyPlayingRate()
    isPlaying = true
    lastListenTick = Date()
    // Intelligenter Restart: nur greifen, wenn gerade kein aktiver Timer läuft (sonst hat der User
    // nach Ablauf selbst neu gesetzt → dessen Wahl respektieren).
    if sleepTimerMode == .off {
      restoreSleepTimerIfWithinGraceIfNeeded()
    }
    resumeSleepTimerIfNeeded()
    updateNowPlaying()
  }

  /// Kurz nach `play()`: Session/Stream erneuern, falls iOS den Engine-Start verschluckt hat.
  private func schedulePlaybackEngineKickstartIfStillPaused() async {
    try? await Task.sleep(nanoseconds: 350_000_000)
    guard !Task.isCancelled else { return }
    guard isPlaying, let p = player, p.currentItem != nil else { return }
    guard !Self.engineIndicatesPlaying(p) else { return }

    ensureAudioSessionForPlayback(reclaimFromOtherApps: true)
    applyPlayingRate()

    try? await Task.sleep(nanoseconds: 250_000_000)
    guard !Task.isCancelled else { return }
    guard isPlaying, let p2 = player, p2.currentItem != nil else { return }
    guard !Self.engineIndicatesPlaying(p2) else { return }

    // Nach langer Pause / Fremd-App: oft abgelaufene Session oder stale Stream-URL.
    if await recoverStaleRemotePlaybackIfNeeded() {
      ensureAudioSessionForPlayback(reclaimFromOtherApps: true)
      applyPlayingRate()
      updateNowPlaying()
      return
    }

    // Kein „spielt“-Zustand ohne tatsächlich laufende Engine: Nach einer Session-Übernahme
    // durch eine andere App kann iOS den Start ablehnen. Der nächste Tap bleibt dadurch ein
    // Startversuch statt fälschlich als Pause interpretiert zu werden.
    if let stalledPlayer = player, !Self.engineIndicatesPlaying(stalledPlayer) {
      isPlaying = false
      pauseSleepTimer()
      updateNowPlaying()
    }
  }

  /// Remote-Wiedergabe: Play-Session und Stream-URL an aktuelle Position neu anbinden.
  private func recoverStaleRemotePlaybackIfNeeded() async -> Bool {
    guard activeBook != nil, apiClient != nil, !isUsingLocalTrackFiles, !tracks.isEmpty else { return false }
    let resumeAt = playbackGlobalPosition()
    currentTrackIndex = trackIndex(forGlobal: resumeAt)
    guard currentTrackIndex < trackStarts.count else { return false }
    let offsetInTrack = max(0, resumeAt - trackStarts[currentTrackIndex])

    if playSessionId == nil {
      await recoverPlaySessionAfterSyncFailure(lostTimeListened: 0)
      guard playSessionId != nil else { return false }
    }

    await loadCurrentTrack(play: false, localOffset: offsetInTrack, pauseOnFailure: false)
    if player?.currentItem?.status == .failed {
      await recoverPlaySessionAfterSyncFailure(lostTimeListened: 0)
      guard playSessionId != nil else { return false }
      await loadCurrentTrack(play: false, localOffset: offsetInTrack, pauseOnFailure: false)
    }
    return player?.currentItem != nil && player?.currentItem?.status != .failed
  }

  /// Absorb `_resumeServerSync`: Session nach Pause/Offline erneut anlegen.
  private func recreatePlaySessionForLocalPlaybackIfNeeded() async {
    guard playSessionId == nil,
      let client = apiClient,
      let book = activeBook,
      attemptServerPlaySessionForLocal
    else { return }
    if let session = await startPlaySessionWithTimeout(
      client: client,
      itemId: book.id,
      episodeId: activePlaybackEpisodeId
    ) {
      playSessionId = session.id
    }
  }

  func pause() {
    accumulateListenTime()
    pauseSleepTimer()
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

  /// Aktuelle Abspielposition (frisch vom Player, falls möglich).
  func playbackGlobalPosition() -> Double {
    if let p = player, p.currentItem != nil {
      let local = p.currentTime().seconds
      if local.isFinite {
        let g = globalTime(trackIndex: currentTrackIndex, localSeconds: local)
        if g.isFinite, g >= 0 {
          globalPosition = g
          return g
        }
      }
    }
    return globalPosition
  }

  /// Index des laufenden Kapitels (0-basiert); laufendes Kapitel zählt als 1.
  func currentChapterIndex() -> Int? {
    guard !sortedChapters.isEmpty else { return nil }
    return chapterIndex(for: playbackGlobalPosition())
  }

  /// Fortschritt im aktuellen Kapitel — für den Kapitel-Fortschrittsbalken im Vollplayer.
  func currentChapterProgress(global override: Double? = nil) -> (position: Double, duration: Double, start: Double)? {
    guard !sortedChapters.isEmpty else { return nil }
    let g = override ?? playbackGlobalPosition()
    guard let idx = chapterIndex(for: g) else { return nil }
    let start = sortedChapters[idx].start
    let end = chapterEndTime(at: idx)
    let duration = max(end - start, 0.001)
    let position = min(max(g - start, 0), duration)
    return (position, duration, start)
  }

  /// Ziel-Kapitelindex (0-basiert) für den Kapitel-Sleep-Timer; `count == 1` = aktuelles Kapitel.
  func chapterTargetIndex(forCount count: Int) -> Int? {
    guard count >= 1, let idx = currentChapterIndex() else { return nil }
    let targetIndex = idx + count - 1
    guard targetIndex < sortedChapters.count else { return nil }
    return targetIndex
  }

  /// Relative Kapitelgrenzen (0…1) für Markierungen im Fortschrittsbalken; ohne Start bei 0.
  var chapterMarkerFractions: [Double] {
    guard totalDuration > 0, sortedChapters.count > 1 else { return [] }
    let minGap = max(2.0, totalDuration * 0.005)
    return sortedChapters.dropFirst()
      .map(\.start)
      .filter { $0 >= minGap && $0 <= totalDuration - minGap }
      .map { min(1, max(0, $0 / totalDuration)) }
  }

  /// Wie viele Kapitel wählbar (laufendes = 1, bis zum letzten Kapitel).
  func maxSleepChapterCount() -> Int {
    _ = playbackGlobalPosition()
    if let idx = currentChapterIndex() {
      return max(1, sortedChapters.count - idx)
    }
    if chapterCount > 0, currentChapterOrdinal > 0 {
      return max(1, chapterCount - currentChapterOrdinal + 1)
    }
    return chapterCount > 0 ? chapterCount : 0
  }

  func seek(global: Double) {
    let g = min(max(0, global), max(totalDuration - 0.25, 0))
    let idx = trackIndex(forGlobal: g)
    let offset = g - trackStarts[idx]
    if idx != currentTrackIndex {
      currentTrackIndex = idx
      liveTranscription.notifyPlaybackTrackAdvanced()
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
    libraryItemFallback: ABSBook? = nil,
    manifestChapters: [ABSChapter]? = nil
  ) {
    // Play session often returns `chapters: []`; `??` alone would discard embedded item chapters.
    let fromSession = sessionChapters ?? []
    let fromManifest = manifestChapters ?? []
    let fromBook = book.media.chapters ?? []
    let fromFallback = libraryItemFallback?.media.chapters ?? []
    let raw: [ABSChapter]
    if !fromSession.isEmpty {
      raw = fromSession
    } else if !fromManifest.isEmpty {
      raw = fromManifest
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

  /// Kapitelende: Start des nächsten Kapitels (nicht `chapter.end`, falls der die Buchlänge trägt).
  private func chapterEndTime(at index: Int) -> Double {
    let ch = sortedChapters[index]
    if index + 1 < sortedChapters.count {
      let nextStart = sortedChapters[index + 1].start
      if ch.end > ch.start + 0.5, ch.end <= nextStart + 0.5 {
        return ch.end
      }
      return nextStart
    }
    let bookEnd = totalDuration > 0 ? totalDuration : ch.end
    if ch.end > ch.start + 0.5, ch.end <= bookEnd + 0.5 {
      return ch.end
    }
    return max(bookEnd, ch.start + 1)
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
    accumulateListenTime()
    let raw = pendingListenSeconds
    let tl = Int(floor(raw))
    if !force, tl < 1, playSessionId != nil { return }

    if let sid = playSessionId, let client = apiClient {
      if tl < 1, !force { return }
      pendingListenSeconds = max(0, raw - Double(tl))
      do {
        try await client.syncPlaySession(
          sessionId: sid, timeListened: max(0, tl), currentTime: globalPosition)
      } catch {
        pendingListenSeconds += Double(tl)
        if Self.isTransientNetworkError(error) { return }
        await recoverPlaySessionAfterSyncFailure(lostTimeListened: tl)
      }
      return
    }

    guard localRoot != nil, tl > 0 || force else { return }
    pendingListenSeconds = max(0, raw - Double(tl))
    let listen = max(0, tl)
    await onLocalPlaybackWithoutSessionSync?(listen, globalPosition, totalDuration)
  }

  /// Keine neue Play-Session bei Netzwerkfehler — sonst wirkt die alte Server-Session „gelöscht“.
  private static func isTransientNetworkError(_ error: Error) -> Bool {
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain {
      switch ns.code {
      case NSURLErrorNotConnectedToInternet,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorCannotFindHost,
        NSURLErrorTimedOut,
        NSURLErrorDNSLookupFailed,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorDataNotAllowed:
        return true
      default:
        break
      }
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut,
        .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
        return true
      default:
        break
      }
    }
    return false
  }

  /// Absorb: bei ungültiger Session neue starten und verlorene Hörzeit nachsyncen.
  private func recoverPlaySessionAfterSyncFailure(lostTimeListened: Int) async {
    guard let client = apiClient, let book = activeBook else { return }
    let resumeAt = playbackGlobalPosition()
    let ep = activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines)
    let episodeId = (ep?.isEmpty == false) ? ep : nil
    do {
      let session = try await client.startPlaySession(
        itemId: book.id,
        episodeId: episodeId,
        deviceId: Self.stableDeviceId(),
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      )
      playSessionId = session.id
      if lostTimeListened > 0 {
        try await client.syncPlaySession(
          sessionId: session.id,
          timeListened: max(0, lostTimeListened),
          currentTime: resumeAt
        )
      }
      guard !isUsingLocalTrackFiles, !tracks.isEmpty else { return }
      currentTrackIndex = trackIndex(forGlobal: resumeAt)
      guard currentTrackIndex < trackStarts.count else { return }
      let offsetInTrack = max(0, resumeAt - trackStarts[currentTrackIndex])
      await loadCurrentTrack(play: isPlaying, localOffset: offsetInTrack, pauseOnFailure: false)
    } catch {
      if !Self.isTransientNetworkError(error) {
        playSessionId = nil
      }
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
    let url = await client.coverURL(itemId: bookId, tier: .hero)
    let data: Data
    do {
      data = try await client.authenticatedData(from: url)
    } catch {
      return
    }
    guard !Task.isCancelled, activeBook?.id == bookId else { return }
    guard let image = UIImage(data: data) else { return }
    lastCoverImageForBarTint = image
    applyMiniPlayerBarFillFromStoredCover()
    let artwork = Self.makeNowPlayingArtwork(from: image)
    nowPlayingArtwork = artwork
    updateNowPlaying()
  }

  private func applyMiniPlayerBarFillFromStoredCover() {
    if let image = lastCoverImageForBarTint {
      // Dieselbe palette-sichere Cover-Tönung wie die Detailansichten; die
      // Mini-Player-Leiste kann damit in hellen und dunklen Themes sichtbar reagieren.
      miniPlayerBarFillColor = coverDominantBackgroundTint(from: image)
    } else {
      miniPlayerBarFillColor = AppTheme.card
    }
  }

  /// RGB wie in `coverBarTintFromCoverImage` (z. B. für Platten-Cache der Continue-Hero-Karten).
  static func coverBarTintRGB(from image: UIImage) -> (Double, Double, Double)? {
    guard let ciImage = CIImage(image: image) else { return nil }
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
    else { return nil }
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
    return (Double(nr), Double(ng), Double(nb))
  }

  /// Hintergrundfarbe aus Cover-Mittel (Mini-Player, Continue-Hero-Karten, …).
  static func coverBarTintFromCoverImage(_ image: UIImage) -> Color {
    guard let (r, g, b) = coverBarTintRGB(from: image) else { return AppTheme.card }
    return Color(red: r, green: g, blue: b)
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

  /// Offline-Modus: keine weiteren Play-Session- oder Cover-Requests.
  /// Vorher `flushPendingPlaySessionSync()` aufrufen — Session absichtlich offen lassen (kein `closePlaySession`).
  func suspendServerNetworkingForOfflineMode() {
    syncTask?.cancel()
    syncTask = nil
    coverLoadTask?.cancel()
    coverLoadTask = nil
    playSessionId = nil
    apiClient = nil
  }

  func closeSessionIfNeeded() async {
    await flushSync(force: true)
    if let sid = playSessionId, let client = apiClient {
      try? await client.closePlaySession(sessionId: sid)
    }
    playSessionId = nil
  }

  /// Für `AppModel.syncOfflineProgressToServer`: offene Play-Session-Zeit an den Server schreiben.
  func flushPendingPlaySessionSync() async {
    await flushSync(force: true)
  }

  var transcriptionTrackKey: String {
    let bookId = activeBook?.id ?? ""
    return "\(bookId)-\(currentTrackIndex)"
  }

  var preferredTranscriptionLanguageTag: String? {
    transcriptionLanguageOverride ?? activeBook?.media.metadata.language
  }

  func setTranscriptionLanguageOverride(_ languageTag: String?) {
    let language = languageTag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    transcriptionLanguageOverride = language.isEmpty ? nil : language
  }

  var hasNextTranscriptionTrack: Bool {
    !tracks.isEmpty && currentTrackIndex + 1 < tracks.count
  }

  func transcriptionLocalStartSeconds(preRoll: Double) -> Double {
    let offset = trackStarts[safe: currentTrackIndex] ?? 0
    let playbackGlobal = liveGlobalPlaybackPosition
    return max(0, playbackGlobal - preRoll - offset)
  }

  /// AVPlayer-Zeit in `globalPosition` übernehmen (Read-Along nach Pause/Neustart).
  func syncGlobalPositionFromPlayer() {
    refreshGlobalFromPlayer()
  }

  func transcriptionLocalPlaybackSeconds(trackGlobalOffset: Double) -> Double {
    max(0, liveGlobalPlaybackPosition - trackGlobalOffset)
  }

  func makeTranscriptionAudioContext() async -> PlayerTranscriptionAudioContext? {
    guard activeBook != nil, !tracks.isEmpty, currentTrackIndex < trackStarts.count else { return nil }
    let offset = trackStarts[currentTrackIndex]
    let trackIdx = tracks[currentTrackIndex].index
    let placeholderLocale = Locale.current

    if isUsingLocalTrackFiles, let root = localRoot {
      let manifest = ABSDownloadManifest.load(from: root)
      guard
        let url = Self.resolvedLocalTrackURL(
          root: root, trackIndex: trackIdx, manifest: manifest)
      else { return nil }
      return PlayerTranscriptionAudioContext(
        assetURL: url,
        streamAuthToken: nil,
        trackGlobalOffset: offset,
        locale: placeholderLocale,
        trackIndex: currentTrackIndex
      )
    }

    guard let client = apiClient, let sid = playSessionId else { return nil }
    do {
      let streamURL = try await client.publicStreamURL(sessionId: sid, trackIndex: trackIdx)
      let token = await client.currentToken()
      return PlayerTranscriptionAudioContext(
        assetURL: streamURL,
        streamAuthToken: token.isEmpty ? nil : token,
        trackGlobalOffset: offset,
        locale: placeholderLocale,
        trackIndex: currentTrackIndex
      )
    } catch {
      return nil
    }
  }

  /// Lokale Track-Dateien, die einen globalen Zeitbereich berühren — z. B. für einen
  /// eigenständigen On-device-Recap. Anders als der Live-Teleprompter berücksichtigt
  /// dies auch Track-Grenzen innerhalb des angeforderten Bereichs.
  func makeLocalTranscriptionAudioContexts(
    overlapping globalRange: ClosedRange<Double>
  ) -> [PlayerTranscriptionAudioContext] {
    guard
      activeBook != nil,
      isUsingLocalTrackFiles,
      let root = localRoot,
      tracks.count == trackStarts.count
    else { return [] }

    let manifest = ABSDownloadManifest.load(from: root)
    let locale = Locale.current
    return tracks.enumerated().compactMap { index, track in
      let start = trackStarts[index]
      let end = start + track.duration
      guard end >= globalRange.lowerBound, start <= globalRange.upperBound else { return nil }
      guard let url = Self.resolvedLocalTrackURL(root: root, trackIndex: track.index, manifest: manifest) else {
        return nil
      }
      return PlayerTranscriptionAudioContext(
        assetURL: url,
        streamAuthToken: nil,
        trackGlobalOffset: start,
        locale: locale,
        trackIndex: index
      )
    }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}

private extension AVURLAsset {
  static func httpHeaderOptions(token: String) -> [String: Any] {
    ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
  }
}
