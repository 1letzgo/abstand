import BackgroundTasks
import Combine
import Foundation
import Speech
import SwiftUI
import UIKit

/// Ein heruntergeladener Titel, für den Transkripte vorproduziert werden.
struct PlayerTranscriptJob {
  /// Schlüssel der Transkriptdateien (= Download-Ordner; bei Folgen `<Show>-<Folge>`).
  let storageId: String
  let title: String
  let languageTag: String?
  let sources: [PlayerTranscriptTrackSource]
}

/// Produziert Read-Along-Transkripte für heruntergeladene Titel im Voraus — der laufende Titel
/// zuerst (ab Abspielposition), dann alle anderen Downloads. Läuft im Vordergrund und per
/// iOS-Hintergrundverarbeitung (`BGProcessingTask`, nur am Strom — typischerweise nachts).
/// Damit sind Read Along, Teleprompter und Recap meist sofort bereit.
///
/// Grenzen: Pause bei Stromsparmodus und thermischer Drosselung, Vorrang für Teleprompter/Recap
/// (`PlayerTranscriptLibrary.isPriorityWorkActive`), nur bereits installierte Sprachmodelle.
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
  private var jobsProvider: (() -> [PlayerTranscriptJob])?
  private var isEnabled = false
  /// Titel, der gerade vorbereitet wird (Einstellungen-Anzeige).
  @Published private(set) var currentJobTitle: String?

  /// Laufende iOS-Hintergrundverarbeitung (nur dann darf ohne aktive App gearbeitet werden).
  private var backgroundTask: BGProcessingTask?
  /// Nach dem Lauf noch offene Arbeit (unvollständige Tracks) → neue Hintergrund-Anfrage.
  private var runLeftWorkPending = false

  static let backgroundTaskIdentifier = "de.letzgo.abstand.transcripts"
  /// Einzige Instanz (im `AppModel`) — für den beim App-Start registrierten Hintergrund-Handler.
  private(set) weak static var current: PlayerTranscriptPrefetcher?

  init() {
    Self.current = self
  }

  func configure(player: PlaybackController, jobs: @escaping () -> [PlayerTranscriptJob]) {
    self.player = player
    self.jobsProvider = jobs
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
    guard isEnabled, task == nil, player != nil else { return }
    // Im Vordergrund oder in einer von iOS gewährten Hintergrundverarbeitung (am Strom). Ein Titel,
    // der per CarPlay/Sperrbildschirm im Hintergrund geladen wird, startet sonst ungefragt Arbeit.
    guard UIApplication.shared.applicationState == .active || backgroundTask != nil else { return }
    guard SpeechTranscriber.isAvailable else {
      finishBackgroundTask(success: true)
      return
    }
    runGeneration &+= 1
    let generation = runGeneration
    task = Task { @MainActor [weak self] in
      await self?.run(generation: generation)
      guard let self, self.runGeneration == generation else { return }
      self.task = nil
      self.isRunning = false
      self.pausedReason = nil
      self.currentJobTitle = nil
      self.finishBackgroundTask(success: true)
    }
  }

  // MARK: Hintergrundverarbeitung

  /// Beim App-Start (vor Ende des Launches) registrieren — Pflicht für `BGTaskScheduler`.
  static func registerBackgroundTask() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
      let box = BackgroundTaskBox(task)
      Task { @MainActor in
        guard let processing = box.task as? BGProcessingTask, let prefetcher = Self.current else {
          box.task.setTaskCompleted(success: false)
          return
        }
        prefetcher.handleBackgroundTask(processing)
      }
    }
  }

  /// Beim Wechsel in den Hintergrund: iOS um Rechenzeit bitten — nur am Strom, damit Akku und
  /// Wärme kein Thema sind (typisch nachts beim Laden).
  func scheduleBackgroundProcessingIfNeeded() {
    guard isEnabled, SpeechTranscriber.isAvailable else { return }
    guard !(jobsProvider?() ?? []).isEmpty || player?.transcriptionStorageId != nil else { return }
    let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
    request.requiresExternalPower = true
    request.requiresNetworkConnectivity = false
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      DebugLogCollector.shared.log("readAlong prefetch: background request failed \(error.localizedDescription)")
    }
  }

  private func handleBackgroundTask(_ processing: BGProcessingTask) {
    backgroundTask = processing
    processing.expirationHandler = { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        // Zeit abgelaufen: Lauf abbrechen (Zwischenstand ist gesichert) und später weitermachen.
        self.runLeftWorkPending = true
        self.stop()
        self.finishBackgroundTask(success: false)
      }
    }
    stop()
    scheduleIfNeeded()
    // Nichts gestartet (aus, kein Player …) → iOS sofort Bescheid geben, sonst wertet es die
    // Aufgabe als hängend und plant die App künftig seltener ein.
    if task == nil { finishBackgroundTask(success: true) }
  }

  private func finishBackgroundTask(success: Bool) {
    guard let processing = backgroundTask else { return }
    backgroundTask = nil
    processing.setTaskCompleted(success: success)
    if runLeftWorkPending {
      runLeftWorkPending = false
      scheduleBackgroundProcessingIfNeeded()
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
    runLeftWorkPending = false

    // Reihenfolge: laufender Titel (ab Abspielposition), dann alle anderen Downloads.
    var jobs: [(job: PlayerTranscriptJob, startGlobal: Double?)] = []
    if let player, player.isReadAlongDownloadReady, let activeId = player.transcriptionStorageId {
      let sources = player.localTranscriptionTrackSources()
      if !sources.isEmpty {
        jobs.append((
          PlayerTranscriptJob(
            storageId: activeId,
            title: player.activeBook?.displayTitle ?? "",
            languageTag: player.preferredTranscriptionLanguageTag,
            sources: sources
          ),
          player.liveGlobalPlaybackPosition
        ))
      }
    }
    let activeId = jobs.first?.job.storageId
    for job in jobsProvider?() ?? [] where job.storageId != activeId {
      jobs.append((job, nil))
    }
    guard !jobs.isEmpty else { return }
    totalTracks = jobs.reduce(0) { $0 + $1.job.sources.count }

    // Sprachauflösung einmal je Sprache.
    var localeByTag: [String: Locale?] = [:]
    let installed = await SpeechTranscriber.installedLocales

    isRunning = true
    for (job, startGlobal) in jobs {
      if Task.isCancelled { return }
      let tag = job.languageTag ?? ""
      if localeByTag[tag] == nil {
        localeByTag[tag] = await Self.installedLocale(forLanguageTag: job.languageTag, installed: installed)
      }
      // Nur die Buchsprache und nur installierte Modelle — kein Download im Hintergrund, kein
      // stundenlanges Transkribieren in einer fremden Sprache.
      guard let locale = localeByTag[tag] ?? nil else { continue }
      currentJobTitle = job.title.isEmpty ? nil : job.title

      let sources = job.sources
      let currentIndex = startGlobal.flatMap { g in sources.firstIndex { $0.globalRange.contains(g) } } ?? 0
      // Erst ab hier nach vorn, danach der übersprungene Anfang.
      let ordered = Array(sources[currentIndex...]) + Array(sources[..<currentIndex])
      for source in ordered {
        if Task.isCancelled { return }
        // Laufender Track ab Abspielposition, alle anderen von vorn.
        let from =
          (startGlobal != nil && source.trackIndex == sources[currentIndex].trackIndex)
          ? max(0, (startGlobal ?? 0) - source.globalOffset)
          : 0
        let completed = await prepare(
          bookId: job.storageId, source: source, locale: locale, from: from, generation: generation)
        if Task.isCancelled { return }
        // Nur zählen, was wirklich durchgelaufen ist — sonst meldet die Einstellung Fortschritt,
        // den es nicht gibt (abgebrochene oder fehlgeschlagene Tracks).
        if completed {
          preparedTracks += 1
        } else {
          runLeftWorkPending = true
        }
      }
    }
    isRunning = false
    pausedReason = nil
  }

  /// Installiertes Sprachmodell für die Buchsprache — `nil` bei Fallback oder fehlendem Modell.
  private static func installedLocale(forLanguageTag tag: String?, installed: [Locale]) async -> Locale? {
    guard
      let resolution = try? await SpeechTranscriptionLocaleResolver.resolve(preferredLanguageTag: tag),
      !resolution.usedFallback
    else { return nil }
    let locale = resolution.locale
    guard installed.contains(where: { SpeechTranscriptionLocaleResolver.matchLocale(locale, in: [$0]) != nil })
    else { return nil }
    return locale
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
        if AbstandErrorFilter.isBenignCancellation(error) {
          // Pause (Teleprompter/Recap, Gerät warm) bricht nur den Abschnitt ab — Track nicht
          // aufgeben, sondern oben warten und an der Lücke weitermachen. Echter Abbruch: raus.
          if !Task.isCancelled, runGeneration == generation {
            // Ohne Blockade-Grund (anderer Abbruch) nicht in eine enge Schleife laufen.
            if blockingReason() == nil { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            continue
          }
          return false
        }
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

/// `BGTask` ist nicht Sendable — der Handler reicht die Instanz nur an den MainActor weiter.
private final class BackgroundTaskBox: @unchecked Sendable {
  let task: BGTask
  init(_ task: BGTask) { self.task = task }
}
