import Combine
import Foundation
import Speech
import SwiftUI

/// Produziert Read-Along-Transkripte für das laufende, heruntergeladene Hörbuch im Voraus —
/// **nur solange die App im Vordergrund ist**. Damit ist der Teleprompter beim Einschalten
/// bereits gefüllt und der Recap kostet keine eigene Spracherkennung mehr.
///
/// Bewusste Grenzen: kein Hintergrundmodus (die App hat nur `audio`), Pause bei Stromsparmodus
/// und bei thermischer Drosselung, und Vorrang für Teleprompter/Recap
/// (`PlayerTranscriptLibrary.isPriorityWorkActive`).
@MainActor
final class PlayerTranscriptPrefetcher: ObservableObject {
  /// Reihenfolge: aktueller Track ab Abspielposition, dann die folgenden, zuletzt der Anfang.
  @Published private(set) var isRunning = false
  @Published private(set) var preparedTracks = 0
  @Published private(set) var totalTracks = 0
  /// Grund der Pause für die Einstellungen-Anzeige (`nil` = läuft oder nichts zu tun).
  @Published private(set) var pausedReason: String?

  /// Warten, bevor nach einer Pause erneut geprüft wird.
  private static let idleRecheckSeconds: UInt64 = 5_000_000_000

  private var task: Task<Void, Never>?
  private weak var player: PlaybackController?
  private var isEnabled = false

  func configure(player: PlaybackController) {
    self.player = player
  }

  /// Einstellung geändert, Buch gewechselt, App in den Vordergrund: Lauf neu bewerten.
  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    if enabled {
      scheduleIfNeeded()
    } else {
      stop()
    }
  }

  func scheduleIfNeeded() {
    guard isEnabled, task == nil, let player else { return }
    guard player.isReadAlongDownloadReady, player.activeBook != nil else { return }
    guard SpeechTranscriber.isAvailable else { return }
    task = Task { @MainActor [weak self] in
      await self?.run()
      self?.task = nil
      self?.isRunning = false
    }
  }

  /// App in den Hintergrund, Buchwechsel, Einstellung aus.
  func stop() {
    task?.cancel()
    task = nil
    isRunning = false
    pausedReason = nil
  }

  private func run() async {
    guard let player, let bookId = player.activeBook?.id, !bookId.isEmpty else { return }

    // Sprache: nur bereits installierte Modelle — ein Download im Hintergrund wäre eine
    // Überraschung auf fremdem Mobilfunk.
    guard
      let locale = try? await SpeechTranscriptionLocaleResolver.resolve(
        preferredLanguageTag: player.preferredTranscriptionLanguageTag
      ).locale
    else { return }
    let installed = await SpeechTranscriber.installedLocales
    guard
      installed.contains(where: {
        SpeechTranscriptionLocaleResolver.matchLocale(locale, in: [$0]) != nil
      })
    else { return }

    let sources = player.localTranscriptionTrackSources()
    guard !sources.isEmpty else { return }
    totalTracks = sources.count

    let currentIndex = sources.firstIndex {
      $0.globalRange.contains(player.liveGlobalPlaybackPosition)
    } ?? 0
    // Erst ab hier nach vorn, danach der übersprungene Anfang.
    let ordered = Array(sources[currentIndex...]) + Array(sources[..<currentIndex])

    isRunning = true
    for source in ordered {
      if Task.isCancelled { return }
      // Aktueller Track ab Abspielposition, alle anderen von vorn.
      let from =
        source.trackIndex == sources[currentIndex].trackIndex
        ? max(0, player.liveGlobalPlaybackPosition - source.globalOffset)
        : 0
      await prepare(bookId: bookId, source: source, locale: locale, from: from)
      if Task.isCancelled { return }
      preparedTracks += 1
    }
    isRunning = false
    pausedReason = nil
  }

  private func prepare(
    bookId: String,
    source: PlayerTranscriptTrackSource,
    locale: Locale,
    from: Double
  ) async {
    var cursor = from
    while !Task.isCancelled {
      guard
        let gapStart = PlayerTranscriptLibrary.firstUncoveredTime(
          bookId: bookId, source: source, locale: locale, from: cursor)
      else { return }

      // Vorrang und Gerätezustand vor jedem Abschnitt prüfen.
      if let reason = blockingReason() {
        pausedReason = reason
        isRunning = false
        try? await Task.sleep(nanoseconds: Self.idleRecheckSeconds)
        isRunning = !Task.isCancelled
        continue
      }
      pausedReason = nil

      do {
        let produced = try await PlayerTranscriptLibrary.produceAndPersist(
          bookId: bookId,
          source: source,
          locale: locale,
          fromLocalTime: gapStart,
          toLocalTime: nil
        )
        guard produced > gapStart + 0.5 else { return }
        cursor = produced
      } catch {
        guard !AbstandErrorFilter.isBenignCancellation(error) else { return }
        DebugLogCollector.shared.log(
          "readAlong prefetch failed track=\(source.trackIndex): \(error.localizedDescription)")
        return
      }
    }
  }

  /// `nil`, wenn gearbeitet werden darf.
  private func blockingReason() -> String? {
    if PlayerTranscriptLibrary.isPriorityWorkActive {
      return String(localized: "Paused while read along is preparing", comment: "Transcript prefetch")
    }
    if ProcessInfo.processInfo.isLowPowerModeEnabled {
      return String(localized: "Paused in Low Power Mode", comment: "Transcript prefetch")
    }
    switch ProcessInfo.processInfo.thermalState {
    case .serious, .critical:
      return String(localized: "Paused while the device is warm", comment: "Transcript prefetch")
    default:
      return nil
    }
  }
}
