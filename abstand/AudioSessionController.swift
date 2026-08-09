import AVFoundation

/// Zentrale `AVAudioSession`-Verwaltung für Langform-Audio (vgl. avkit-Skill).
///
/// Die Regeln, die hier durchgesetzt werden, entscheiden über die Hintergrund-Wiedergabe:
/// - Category/Mode/Policy genau **einmal** setzen. Ein `setCategory` während laufender
///   Wiedergabe unterbricht den Ton kurz; passiert das beim Wechsel in den Hintergrund,
///   suspendiert iOS die App ohne laufendes Audio.
/// - `setActive(true)` erst unmittelbar vor dem Start der Wiedergabe — nicht beim Kaltstart.
/// - **Nie** `setActive(false)`, solange gespielt werden soll. Das beendet die
///   Hintergrund-Wiedergabe und löst eine eigene Interruption aus.
/// - Beim Wechsel in Hintergrund / Sperrbildschirm gar nichts tun: mit `.playback` und dem
///   `audio`-Background-Mode hält iOS die Wiedergabe von selbst.
///
/// Interruption-, Route- und Media-Services-Events beobachtet der `PlaybackController`.
@MainActor
final class AudioSessionController {
  static let shared = AudioSessionController()

  private let session = AVAudioSession.sharedInstance()
  private var didConfigureCategory = false

  private static let categoryOptions: AVAudioSession.CategoryOptions = [
    .allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay,
  ]

  private init() {}

  /// `.playback` + `.spokenAudio` + `.longFormAudio` — idempotent. Erneut gesetzt wird nur,
  /// wenn eine andere Komponente oder iOS die Session verändert hat.
  func configureForLongFormAudioIfNeeded() {
    guard needsCategoryUpdate else { return }
    do {
      try session.setCategory(
        .playback,
        mode: .spokenAudio,
        policy: .longFormAudio,
        options: Self.categoryOptions
      )
      didConfigureCategory = true
      return
    } catch {
      DebugLogCollector.shared.log(
        "audioSession setCategory(longFormAudio) failed err=\(error.localizedDescription)"
      )
    }
    // `.longFormAudio` kann belegt sein (andere Langform-App, laufendes Telefonat) —
    // ohne Policy ist die Category weiterhin hintergrundfähig.
    do {
      try session.setCategory(.playback, mode: .spokenAudio, options: Self.categoryOptions)
      didConfigureCategory = true
    } catch {
      DebugLogCollector.shared.log(
        "audioSession setCategory failed err=\(error.localizedDescription)"
      )
    }
  }

  private var needsCategoryUpdate: Bool {
    !didConfigureCategory || session.category != .playback || session.mode != .spokenAudio
  }

  /// Session für den Start der Wiedergabe aktivieren.
  /// `reclaimingOutput` nur bei explizitem Play/Resume — andere Apps dürfen dann fortsetzen,
  /// sobald wir die Session später abgeben.
  @discardableResult
  func activateForPlayback(reclaimingOutput: Bool = false) -> Bool {
    configureForLongFormAudioIfNeeded()
    var options: AVAudioSession.SetActiveOptions = []
    if reclaimingOutput {
      options.insert(.notifyOthersOnDeactivation)
    }
    do {
      try session.setActive(true, options: options)
      return true
    } catch {
      DebugLogCollector.shared.log(
        "audioSession setActive failed err=\(error.localizedDescription)"
      )
      return false
    }
  }

  /// Direkt nach einem Telefonat kann `setActive` scheitern, weil die Session noch beim
  /// Anrufdienst liegt. Apples Antwort darauf ist erneutes Aktivieren nach kurzer Wartezeit —
  /// kein `setActive(false)`-Neuaufbau.
  @discardableResult
  func activateForPlayback(
    retries: Int,
    delay: Duration = .milliseconds(250),
    reclaimingOutput: Bool = true
  ) async -> Bool {
    let attempts = max(1, retries + 1)
    for attempt in 1...attempts {
      if activateForPlayback(reclaimingOutput: reclaimingOutput) { return true }
      guard attempt < attempts else { break }
      try? await Task.sleep(for: delay)
    }
    return false
  }

  /// `mediaServicesWereReset`: laut Apple-Doku müssen Category und Aktivierung komplett neu
  /// gesetzt werden — der gecachte Konfigurationsstand gilt danach nicht mehr.
  @discardableResult
  func rebuildAfterMediaServicesReset() -> Bool {
    didConfigureCategory = false
    return activateForPlayback(reclaimingOutput: true)
  }
}
