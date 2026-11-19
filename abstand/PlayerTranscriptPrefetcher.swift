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
/// Damit sind Read Along und Teleprompter meist sofort bereit.
///
/// Grenzen: Pause bei Stromsparmodus und thermischer Drosselung, Vorrang für den Teleprompter
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

  /// Buchsprache eines Downloads aus Detail-Cache und lokalem Katalog.
  func languageTag(forStorageId storageId: String) -> String? {
    jobsProvider?().first { $0.storageId == storageId }?.languageTag
  }

  /// Einstellung geändert, Buch gewechselt, App in den Vordergrund: Lauf neu bewerten.
  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    if enabled {
      scheduleIfNeeded()
    } else {
      stop(reason: "disabled")
    }
  }

  func scheduleIfNeeded() {
    // Diagnose: jeder Nicht-Start mit Grund (am Gerät sonst nicht nachvollziehbar, warum nichts läuft).
    guard isEnabled else { return Self.log("not started: disabled") }
    guard task == nil else {
      return Self.log("not started: run gen=\(runGeneration) already active (bg=\(backgroundTask != nil))")
    }
    guard player != nil else { return Self.log("not started: no player") }
    // Im Vordergrund oder in einer von iOS gewährten Hintergrundverarbeitung (am Strom). Ein Titel,
    // der per CarPlay/Sperrbildschirm im Hintergrund geladen wird, startet sonst ungefragt Arbeit.
    let appState = UIApplication.shared.applicationState
    guard appState == .active || backgroundTask != nil else {
      return Self.log("not started: app \(Self.name(of: appState)), no background task")
    }
    guard SpeechTranscriber.isAvailable else {
      Self.log("not started: SpeechTranscriber unavailable")
      finishBackgroundTask(success: true)
      return
    }
    runGeneration &+= 1
    let generation = runGeneration
    Self.log("run gen=\(generation) started (app \(Self.name(of: appState)), bg=\(backgroundTask != nil))")
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
    Self.log("background task started (app \(Self.name(of: UIApplication.shared.applicationState)))")
    // Eine noch offene frühere Aufgabe sauber abschließen, bevor die neue übernimmt.
    if backgroundTask != nil {
      runLeftWorkPending = true
      finishBackgroundTask(success: false)
    }
    backgroundTask = processing
    let processingId = ObjectIdentifier(processing)
    processing.expirationHandler = { [weak self] in
      Task { @MainActor [weak self] in
        // Nur, wenn diese Aufgabe noch die laufende ist.
        guard let self, let current = self.backgroundTask, ObjectIdentifier(current) == processingId else { return }
        self.handleBackgroundTaskExpiration()
      }
    }
    cancelRun(reason: "background task takes over")
    scheduleIfNeeded()
    // Nichts gestartet (aus, kein Player …) → iOS sofort Bescheid geben, sonst wertet es die
    // Aufgabe als hängend und plant die App künftig seltener ein.
    if task == nil { finishBackgroundTask(success: true) }
  }

  /// iOS beendet die Hintergrundverarbeitung — Zeit abgelaufen oder, typisch, weil der Nutzer das Gerät
  /// entsperrt und benutzt. Ist die App inzwischen im Vordergrund, läuft der Lauf als Vordergrund-Lauf
  /// weiter: Das `.active`-Ereignis beim Entsperren kam, während er noch als Hintergrund-Lauf lief
  /// (`scheduleIfNeeded` fand ihn belegt) — ein `stop()` hier ließe die App bis zum nächsten Entsperren
  /// oder Neustart ohne Vorproduktion (Gerätefund: Teilsegment, danach minutenlang nichts).
  private func handleBackgroundTaskExpiration() {
    let appState = UIApplication.shared.applicationState
    if appState == .active, task != nil {
      Self.log("background task expired, app active — run gen=\(runGeneration) continues in foreground")
      // Restarbeit meldet der Wechsel in den Hintergrund ohnehin neu an.
      finishBackgroundTask(success: false)
      return
    }
    Self.log("background task expired (app \(Self.name(of: appState)))")
    stop(reason: "background task expired")
    // Vordergrund ohne laufenden Lauf (z. B. schon beendet): neu anstoßen; sonst ohne Wirkung.
    if appState == .active { scheduleIfNeeded() }
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

  /// App in den Hintergrund, Buchwechsel, Einstellung aus. Läuft gerade eine iOS-Hintergrund-
  /// verarbeitung, wird sie wie beim Ablauf der Zeit beendet (Arbeit offen → neue Anfrage) — sonst
  /// bliebe `backgroundTask` gesetzt und erlaubte später Arbeit ohne Hintergrund-Erlaubnis.
  func stop(reason: String) {
    cancelRun(reason: reason)
    if backgroundTask != nil {
      runLeftWorkPending = true
      finishBackgroundTask(success: false)
    }
  }

  /// Buchwechsel: Lauf am neuen Titel neu aufsetzen. Anders als `stop()` bleibt eine laufende
  /// Hintergrundverarbeitung bestehen — ein Hintergrund-Launch, der den letzten Titel wiederherstellt,
  /// würde sich sonst die eigene Aufgabe beenden.
  func restart() {
    cancelRun(reason: "restart (media prepared)")
    scheduleIfNeeded()
    // Nichts gestartet → iOS sofort Bescheid geben (wie in `handleBackgroundTask`).
    if task == nil { finishBackgroundTask(success: true) }
  }

  /// Nur den laufenden Lauf abbrechen; eine Hintergrundverarbeitung bleibt bestehen.
  private func cancelRun(reason: String) {
    if task != nil { Self.log("run gen=\(runGeneration) cancelled: \(reason)") }
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
    guard !jobs.isEmpty else { return Self.log("run gen=\(generation) ended: no downloaded jobs") }
    totalTracks = jobs.reduce(0) { $0 + $1.job.sources.count }

    // Sprachauflösung einmal je Sprache.
    var localeByTag: [String: Locale?] = [:]
    let installed = await SpeechTranscriber.installedLocales

    isRunning = true
    var skippedJobs = 0
    for (job, startGlobal) in jobs {
      if Task.isCancelled { return Self.log("run gen=\(generation) ended: cancelled") }
      let tag = job.languageTag ?? ""
      if localeByTag[tag] == nil {
        localeByTag[tag] = await Self.installedLocale(forLanguageTag: job.languageTag, installed: installed)
      }
      // Nur die Buchsprache und nur installierte Modelle — kein Download im Hintergrund, kein
      // stundenlanges Transkribieren in einer fremden Sprache.
      guard let locale = localeByTag[tag] ?? nil else {
        skippedJobs += 1
        Self.log("skip \(job.storageId): no installed model for language '\(tag)'")
        continue
      }
      currentJobTitle = job.title.isEmpty ? nil : job.title

      let sources = job.sources
      let currentIndex = startGlobal.flatMap { g in sources.firstIndex { $0.globalRange.contains(g) } } ?? 0
      // Erst ab hier nach vorn, danach der übersprungene Anfang.
      let ordered = Array(sources[currentIndex...]) + Array(sources[..<currentIndex])
      for source in ordered {
        if Task.isCancelled { return Self.log("run gen=\(generation) ended: cancelled") }
        // Laufender Track ab Abspielposition, alle anderen von vorn.
        let from =
          (startGlobal != nil && source.trackIndex == sources[currentIndex].trackIndex)
          ? max(0, (startGlobal ?? 0) - source.globalOffset)
          : 0
        var completed = await prepare(
          bookId: job.storageId, source: source, locale: locale, from: from, generation: generation)
        // Beim laufenden Track danach auch den Anfang vor der Hörposition — sonst fehlt er bei
        // Ein-Datei-Hörbüchern dauerhaft (Sprung zurück ins eBook).
        if completed, from > 0, !Task.isCancelled {
          completed = await prepare(
            bookId: job.storageId, source: source, locale: locale, from: 0, generation: generation)
        }
        if Task.isCancelled {
          return Self.log("run gen=\(generation) ended: cancelled during track=\(source.trackIndex)")
        }
        // Nur zählen, was wirklich durchgelaufen ist — sonst meldet die Einstellung Fortschritt,
        // den es nicht gibt (abgebrochene oder fehlgeschlagene Tracks).
        if completed {
          preparedTracks += 1
        } else {
          runLeftWorkPending = true
        }
      }
    }
    Self.log(
      "run gen=\(generation) ended: all jobs done, prepared \(preparedTracks)/\(totalTracks), "
        + "left work=\(runLeftWorkPending), skipped jobs=\(skippedJobs)")
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
    guard SpeechTranscriptionLocaleResolver.isInstalled(locale, in: installed) else { return nil }
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
    // Lückenanfang des letzten regulär durchgelaufenen Abschnitts. Taucht dieselbe Lücke danach wieder
    // auf (Merge abgelehnt, Datei nicht schreibbar), nicht endlos neu transkribieren.
    var lastFilledGapStart: Double?
    // Diagnose: Pausen nur beim Wechsel protokollieren, Abbrüche ohne Grund gezählt (Ringpuffer schonen).
    var loggedPause: String?
    var unexplainedCancellations = 0
    while !Task.isCancelled {
      // Lückenanfang und -ende aus einem Lesevorgang (Transkript bleibt im Speicher, solange die
      // Datei unverändert ist) — nach einer Pause neu, weil der Teleprompter inzwischen geschrieben haben kann.
      guard
        let gap = await PlayerTranscriptLibrary.nextGap(
          bookId: bookId, source: source, locale: locale, from: cursor)
      else { return true }
      let gapStart = gap.start
      guard runGeneration == generation, !Task.isCancelled else { return false }
      if let lastFilledGapStart, gapStart <= lastFilledGapStart + 0.5 {
        DebugLogCollector.shared.log(
          "readAlong prefetch: gap at \(gapStart) track=\(source.trackIndex) not closed — giving up for this run")
        return false
      }

      // Vorrang und Gerätezustand vor jedem Abschnitt prüfen.
      if let reason = blockingReason() {
        if loggedPause != reason {
          loggedPause = reason
          Self.log("paused track=\(source.trackIndex) at \(Int(gapStart)) s: \(reason)")
        }
        pausedReason = reason
        isRunning = false
        try? await Task.sleep(nanoseconds: Self.idleRecheckSeconds)
        isRunning = !Task.isCancelled
        continue
      }
      if loggedPause != nil {
        loggedPause = nil
        Self.log("resumed track=\(source.trackIndex) at \(Int(gapStart)) s")
      }
      pausedReason = nil

      do {
        // Nur die Lücke (mit Vor-/Nachlauf) — am nächsten vorhandenen Segment aufhören, die Schleife
        // sucht dann die nächste. Abbruch kommt immer als Fehler zurück, nie als „nichts produziert".
        cursor = try await PlayerTranscriptLibrary.fillGap(
          bookId: bookId,
          source: source,
          locale: locale,
          gapStart: gapStart,
          gapEnd: gap.end,
          priority: .utility,
          isCurrent: { [weak self] in
            !Task.isCancelled && self?.runGeneration == generation
          },
          onBatch: { [weak self] _ in
            // Ein Track läuft minutenlang. Ohne diese Prüfung zwischendrin liefe die
            // Vorproduktion weiter, während der Teleprompter startet oder das Gerät heiß wird —
            // die Pause griffe erst beim nächsten Track.
            guard let self, self.runGeneration == generation, self.blockingReason() == nil else {
              throw CancellationError()
            }
          }
        )
        // Ohne folgendes Segment lief der Producer bis Dateiende — ab der Lücke ist der Track fertig.
        if gap.end == nil { return true }
        lastFilledGapStart = gapStart
      } catch {
        if AbstandErrorFilter.isBenignCancellation(error) {
          // Pause (Teleprompter, Gerät warm) bricht nur den Abschnitt ab — Track nicht
          // aufgeben, sondern oben warten und an der Lücke weitermachen. Echter Abbruch: raus.
          if !Task.isCancelled, runGeneration == generation {
            // Ohne Blockade-Grund (anderer Abbruch) nicht in eine enge Schleife laufen.
            if blockingReason() == nil {
              unexplainedCancellations += 1
              // Erster Fall und dann selten — eine stille Wiederholschleife bliebe sonst unsichtbar.
              if unexplainedCancellations == 1 || unexplainedCancellations % 30 == 0 {
                Self.log(
                  "cancellation without pause reason track=\(source.trackIndex) at \(Int(gapStart)) s "
                    + "(#\(unexplainedCancellations)): \(error.localizedDescription)")
              }
              try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
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

  /// Diagnosezeile im Debug-Log (Einstellungen → Debug-Log), einheitlich präfixiert.
  private static func log(_ message: String) {
    DebugLogCollector.shared.log("readAlong prefetch: \(message)")
  }

  private static func name(of state: UIApplication.State) -> String {
    switch state {
    case .active: return "active"
    case .inactive: return "inactive"
    case .background: return "background"
    @unknown default: return "unknown"
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

/// `BGTask` ist nicht Sendable — der Handler reicht die Instanz nur an den MainActor weiter.
private final class BackgroundTaskBox: @unchecked Sendable {
  let task: BGTask
  init(_ task: BGTask) { self.task = task }
}
