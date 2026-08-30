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
  /// Zählt bei jedem Start/Stop hoch. Ein auslaufender alter Lauf darf `task`/`isRunning`
  /// des neuen nicht mehr zurücksetzen — sonst hielte `scheduleIfNeeded` den Slot für frei
  /// und zwei Vorproduktionen liefen parallel.
  private var runGeneration: UInt = 0
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
    runGeneration &+= 1
    let generation = runGeneration
    task = Task { @MainActor [weak self] in
      await self?.run(generation: generation)
      guard let self, self.runGeneration == generation else { return }
      self.task = nil
      self.isRunning = false
      self.pausedReason = nil
    }
  }

  /// App in den Hintergrund, Buchwechsel, Einstellung aus.
  func stop() {
    runGeneration &+= 1
    task?.cancel()
    task = nil
    isRunning = false
    pausedReason = nil
  }

  private func run(generation: UInt) async {
    // Zähler gehören zum Lauf, nicht zur Lebenszeit des Objekts — sonst zeigt die Einstellung
    // nach ein paar Büchern „37 von 12 Tracks“.
    preparedTracks = 0
    totalTracks = 0
    guard let player, let bookId = player.activeBook?.id, !bookId.isEmpty else { return }

    // Sprache: nur bereits installierte Modelle — ein Download im Hintergrund wäre eine
    // Überraschung auf fremdem Mobilfunk.
    guard
      let resolution = try? await SpeechTranscriptionLocaleResolver.resolve(
        preferredLanguageTag: player.preferredTranscriptionLanguageTag
      )
    else { return }
    // Nur die Buchsprache vorproduzieren. Bei Fallback wäre das Ergebnis in einer fremden
    // Sprache transkribiert — stundenlange Rechenzeit für ein unbrauchbares Transkript.
    guard !resolution.usedFallback else { return }
    let locale = resolution.locale
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
      let completed = await prepare(
        bookId: bookId, source: source, locale: locale, from: from, generation: generation)
      if Task.isCancelled { return }
      // Nur zählen, was wirklich durchgelaufen ist — sonst meldet die Einstellung Fortschritt,
      // den es nicht gibt (abgebrochene oder fehlgeschlagene Tracks).
      if completed { preparedTracks += 1 }
    }
    isRunning = false
    pausedReason = nil
  }

  /// `true`, wenn der Track vollständig abgedeckt ist.
  @discardableResult
  private func prepare(
    bookId: String,
    source: PlayerTranscriptTrackSource,
    locale: Locale,
    from: Double,
    generation: UInt
  ) async -> Bool {
    var cursor = from
    while !Task.isCancelled {
      guard
        let gapStart = await PlayerTranscriptLibrary.firstUncoveredTime(
          bookId: bookId, source: source, locale: locale, from: cursor)
      else { return true }
      guard runGeneration == generation else { return false }

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
          toLocalTime: nil,
          onBatch: { [weak self] _ in
            // Ein Track läuft minutenlang. Ohne diese Prüfung zwischendrin liefe die
            // Vorproduktion weiter, während der Teleprompter startet oder das Gerät heiß wird —
            // die Pause griffe erst beim nächsten Track.
            guard let self, self.runGeneration == generation, self.blockingReason() == nil else {
              throw CancellationError()
            }
          }
        )
        guard produced > gapStart + 0.5 else { return true }
        cursor = produced
      } catch {
        guard !AbstandErrorFilter.isBenignCancellation(error) else { return false }
        DebugLogCollector.shared.log(
          "readAlong prefetch failed track=\(source.trackIndex): \(error.localizedDescription)")
        return false
      }
    }
    return false
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
