import AVFoundation
import Combine
import Foundation
import FoundationModels
import Speech
import SwiftUI
import UIKit

enum PlayerLiveTranscriptionError: LocalizedError {
  case noActivePlayback
  case speechRecognitionDenied
  case localeNotSupported
  case modelDownloadFailed
  case conversionFailed
  case audioSourceUnavailable
  case streamingPlaybackUnavailable
  case transcriptionStartupTimedOut
  case transcriptionProgressStalled

  var errorDescription: String? {
    switch self {
    case .noActivePlayback:
      return String(localized: "Nothing is playing.", comment: "Live transcript error")
    case .speechRecognitionDenied:
      return String(
        localized:
          "Speech recognition is not allowed. You can enable it in Settings → Privacy & Security → Speech Recognition.",
        comment: "Live transcript error")
    case .localeNotSupported:
      return String(
        localized:
          "Speech recognition is not available for this language on this device. Try setting the book language in Audiobookshelf or install the language in iOS Settings.",
        comment: "Live transcript error")
    case .modelDownloadFailed:
      return String(
        localized: "Could not download the speech model. Check your connection and try again.",
        comment: "Live transcript error")
    case .conversionFailed:
      return String(localized: "Audio could not be prepared for transcription.", comment: "Live transcript error")
    case .audioSourceUnavailable:
      return String(localized: "No audio source for transcription.", comment: "Live transcript error")
    case .streamingPlaybackUnavailable:
      return String(
        localized:
          "Read along needs a server stream or a fully downloaded audiobook. Finish the download or go online.",
        comment: "Live transcript error")
    case .transcriptionStartupTimedOut:
      return String(
        localized: "Transcription took too long to start. Try again.",
        comment: "Live transcript error")
    case .transcriptionProgressStalled:
      return String(
        localized: "Transcription stopped making progress. Try again.",
        comment: "Live transcript error")
    }
  }
}

private actor PlayerRecapTranscriptCollector {
  private var segments: [String] = []

  func append(_ raw: String) {
    let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !segment.isEmpty else { return }
    guard let last = segments.last else {
      segments.append(segment)
      return
    }
    if segment == last || last.hasPrefix(segment) { return }
    if segment.hasPrefix(last) {
      segments[segments.count - 1] = segment
    } else {
      segments.append(segment)
    }
  }

  var text: String {
    segments.joined(separator: " ")
  }
}

/// Ein Wort (oder Leerzeichen) mit Zeitfenster für Highlight / Scroll.
struct PlayerTranscriptWord: Identifiable, Equatable {
  let id: String
  let text: String
  let globalStart: Double
  let globalEnd: Double
  let isVolatile: Bool

  var isWhitespaceOnly: Bool {
    text.allSatisfy(\.isWhitespace)
  }
}

struct PlayerTranscriptionAudioContext: Equatable {
  let assetURL: URL
  let streamAuthToken: String?
  /// Globale Hörbuch-Zeit (s) am Anfang des aktuellen Tracks.
  let trackGlobalOffset: Double
  let locale: Locale
  let trackIndex: Int
}

@MainActor
final class PlayerLiveTranscriptionController: ObservableObject {
  static let preRollSeconds: Double = 4
  /// Audio weit voraus transkribieren, damit Zeilen fertig sind bevor sie im Teleprompter erscheinen.
  static let leadBufferSeconds: Double = 120
  /// Mindestens so viele fertige Zeilen, bevor der Teleprompter sichtbar wird.
  static let minClosedLinesForDisplay = 4
  /// Mindestens so viel Audio (global, s) seit Feed-Start transkribiert.
  static let minTranscribedSecondsForDisplay: Double = 10
  /// Beim laufenden Play: Transkript darf höchstens so weit hinter der Wiedergabe liegen.
  static let maxPlaybackLagWhilePlaying: Double = 15
  /// Fallback: Spinner spätestens nach so vielen Sekunden aus, wenn Text da ist.
  static let teleprompterReadinessTimeoutSeconds: Double = 14
  /// Beim Start / Buchwechsel: „nah an Live“ erst nach kurzer Pufferphase erzwingen.
  static let teleprompterStartupGraceSeconds: Double = 35
  /// Hartes Startup-Timeout — danach Modus beenden.
  static let transcriptionStartupTimeoutSeconds: Double = 45
  /// Kein Transkript-Fortschritt über diese Dauer → Fehler (nur während Startup-Puffer).
  static let transcriptionProgressStallSeconds: Double = 45
  /// `makeTranscriptionAudioContext()` wiederholt nil über diese Dauer → Fehler.
  static let audioContextUnavailableSeconds: Double = 10
  /// Wiedergabe so weit voraus: Feed-Throttle aus, Audio maximal schnell nachschieben.
  static let transcriptionCatchUpLagSeconds: Double = 6
  /// Gegendruck: höchstens so viel noch nicht transkribiertes Audio im Analyzer.
  /// Lesen und Konvertieren laufen um Größenordnungen schneller als die Erkennung. Ohne diese
  /// Grenze schiebt der Feed in der Pufferphase Minuten an Audio in wenigen Sekunden hinein —
  /// danach liefert der Analyzer nur noch ein paar Wörter und bleibt stehen.
  static let maxAnalyzerBacklogSeconds: Double = 30
  /// Wiedergabe so weit vor dem gefütterten Audio (z. B. großer Sprung): Reader neu am
  /// Abspielpunkt aufsetzen, statt die übersprungene Strecke durch den Analyzer zu schieben.
  static let feedReseekLagSeconds: Double = 45
  /// Feed-Segment startet so weit vor dem bisherigen Transkript-Ende (Rücksprung) → neu ankern.
  /// Muss deutlich über dem Pre-Roll liegen: an jeder Trackgrenze setzt der Feed
  /// planmäßig `preRollSeconds` vor dem bereits Transkribierten auf.
  static let feedBackwardResetSeconds: Double = 30
  /// Nach erreichter Bereitschaft: kein Fortschritt über diese Dauer bei laufender Wiedergabe
  /// → Feed bzw. Session selbst heilen, statt still stehenzubleiben.
  static let feedRecoveryStallSeconds: Double = 12
  /// So viele Feed-Neustarts, bevor die ganze Speech-Session neu aufgebaut wird.
  static let maxFeedRestartsBeforeSessionRestart = 2
  /// So lange ohne Stillstand → Zähler der Selbstheilungsversuche zurücksetzen.
  static let feedStallRecoveryResetSeconds: Double = 300
  /// Obergrenzen fürs Transkript — halten Publish- und Reflow-Kosten über Stunden konstant.
  static let maxRetainedTranscriptLines = 1200
  static let maxRetainedTranscriptWords = 14000
  private static let transcriptPruneChunk = 200
  /// Ein Player-State-Check deckt so viele Sample-Buffer ab (~0,4 s Audio).
  /// `nonisolated`, weil der Feed außerhalb des MainActors liest.
  private nonisolated static let feedBuffersPerStateCheck = 16
  private static let maxFeedTimelineSegments = 32
  /// Ein Recap bleibt für mindestens eine weitere Hörminute gültig.
  static let recapCachePlaybackSeconds: Double = 60
  /// On-device Recap hart abbrechen nach dieser Dauer (gegen endlosen Spinner).
  static let recapGenerationTimeoutSeconds: Double = 90

  /// Nutzer hat Read-Along/Teleprompter eingeschaltet — steuert UI und Lebenszyklus.
  @Published private(set) var isTeleprompterModeActive = false
  @Published private(set) var isEnabled = false
  @Published private(set) var isPreparing = false
  /// Start/Stop läuft — Button blockieren, kein paralleler Toggle.
  @Published private(set) var isSessionBusy = false
  /// Erst true, wenn genug finalisierter Text vorgepuffert ist — bis dahin Spinner in der Karte.
  @Published private(set) var isTeleprompterReady = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var words: [PlayerTranscriptWord] = []
  @Published private(set) var transcriptLines: [PlayerTranscriptLine] = []
  @Published private(set) var modelDownloadProgress: Double?
  /// Hinweis, wenn eine andere Sprache als in den Buch-Metadaten genutzt wird.
  @Published private(set) var localeFallbackNotice: String?
  /// `false` auf Geräten ohne `SpeechTranscriber` (z. B. iPhone 11).
  @Published private(set) var isReadAlongAvailable = SpeechTranscriber.isAvailable
  /// Wort-Lookup-Sheet wird am stabilen Vollplayer-Root präsentiert — nicht an der
  /// volatilen Teleprompter-View (Translation-Session crasht, wenn ihre Anker-View verschwindet).
  @Published var wordLookupSelection: PlayerTranscriptWordLookupSelection?
  /// Erhöht nach Teleprompter-Start-Sync — View setzt die Anzeige-Uhr zurück.
  @Published private(set) var teleprompterSyncGeneration: UInt = 0
  /// Zielzeit für Teleprompter-Highlight nach Start-Sync (= Wiedergabe).
  @Published private(set) var teleprompterSyncedPlaybackTime: Double = 0
  /// Ergebnis der lokalen Zusammenfassung des letzten Transkriptfensters.
  @Published private(set) var recapText: String?
  @Published private(set) var recapErrorMessage: String?
  @Published private(set) var isGeneratingRecap = false
  /// Hinweis, wenn der Recap mit einer anderen Sprache als dem Buch erzeugt wurde.
  @Published private(set) var recapFallbackNotice: String?
  /// True, wenn statt einer Zusammenfassung das rohe Transkript gezeigt wird (Filter-/LLM-Fehler).
  @Published private(set) var recapShowsTranscript = false

  /// Sprache der laufenden Transkription (für Wort-Übersetzung).
  var transcriptionLocale: Locale? { activeContext?.locale }
  /// Nur aktivierbar, wenn Apple Intelligence verfügbar ist.
  var canGenerateRecap: Bool { SystemLanguageModel.default.availability == .available }

  private var finalizedWords: [PlayerTranscriptWord] = []
  private var recapBookId: String?
  private var recapPlaybackTime: Double?
  /// Inkrementelle ID pro Recap-Versuch — erlaubt Timeout-Erkennung bei mehreren Aufrufen.
  private var currentRecapGeneration = UUID()
  /// Volatile Speech-Ergebnisse während der Pufferphase (ersetzt, nicht angehängt).
  private var volatileTailWords: [PlayerTranscriptWord] = []
  private let lineAccumulator = PlayerTranscriptLineAccumulator()
  /// Letztes Teleprompter-Layout für Reflow bei Schriftgrößenwechsel.
  private var teleprompterReflowFontSize: CGFloat = 0
  private var teleprompterReflowWidth: CGFloat = 0
  /// Nur neue Final-Segmente anhängen (keine Duplikate bei kumulativen Ergebnissen).
  private var appendedThroughGlobalTime: Double = 0
  private var activeContext: PlayerTranscriptionAudioContext?

  /// Ein `SpeechAnalyzer` läuft über alle Tracks; seine Zeitachse zählt ab dem ersten
  /// Buffer fortlaufend weiter und kennt Trackgrenzen oder Sprünge nicht. Pro Feed-Segment
  /// wird hier festgehalten, welcher Hörbuchzeit sein Beginn entspricht.
  private struct FeedTimelineSegment {
    let analyzerStart: Double
    let globalStart: Double
  }
  private var feedTimeline: [FeedTimelineSegment] = []
  /// Summe aller in den Analyzer geschobenen Audiosekunden (= seine Zeitachse).
  private var fedAnalyzerSeconds: Double = 0

  /// Feed soll am Abspielpunkt neu aufsetzen (Selbstheilung bei Stillstand).
  private var feedRestartRequested = false
  /// Generation des laufenden Feed-Loops, `nil` wenn keiner läuft — dann hilft nur ein
  /// Session-Neustart. Generationsgebunden, damit ein auslaufender Loop der alten Session
  /// die neue nicht als „Feed tot“ markiert.
  private var runningFeedLoopGeneration: UInt?
  private var feedStallRecoveryCount = 0
  private var lastFeedStallRecoveryAt: Date?

  private var transcriber: SpeechTranscriber?
  private var analyzer: SpeechAnalyzer?
  private var analyzerFormat: AVAudioFormat?
  private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
  private var resultsTask: Task<Void, Never>?
  private var feedTask: Task<Void, Never>?

  private weak var boundPlayer: PlaybackController?
  private var lastFeedTrackKey: String?
  /// Wird bei Track-Wechsel erhöht — Feed-Schleife startet nächste Datei ohne Session-Neustart.
  private var feedTrackGeneration = 0

  /// Letzte Wiedergabezeit mit aktivem Teleprompter (für Start-Abgleich).
  private var lastTeleprompterPlaybackTime: Double = 0
  /// Erste Player-Ticks nach Enable: Position erneut syncen (Seek nach App-Start).
  private var pendingStartupSyncTicks = 0
  /// Globale Zeit am Feed-Start (für Puffer-Berechnung unabhängig von laufender Wiedergabe).
  private var sessionFeedStartGlobalTime: Double = 0
  private var teleprompterBufferingStartedAt: Date?
  /// Laufender Start-Task — bei `disable()` abbrechen, damit kein Zombie-Session bleibt.
  private var enableTask: Task<Void, Never>?
  /// Wartet ggf. auf laufendes `stopSession()` — verhindert parallele SpeechAnalyzer.
  private var stopSessionTask: Task<Void, Never>?
  private var startupWatchdogTask: Task<Void, Never>?
  private var progressStallWatchdogTask: Task<Void, Never>?
  /// Läuft im Gegensatz zu den Startup-Watchdogs über die ganze Session.
  private var stallRecoveryWatchdogTask: Task<Void, Never>?
  /// Inkrementiert bei jedem Start — Tasks ignorieren veraltete Generationen.
  private var sessionGeneration: UInt = 0
  /// Start-Absicht. `disable()` erhöht sie, damit `startTeleprompterMode` nach einem
  /// `await` nicht eine Session aufsetzt, die inzwischen beendet wurde.
  private var teleprompterIntentGeneration: UInt = 0
  /// Aktives Buch zum Erkennen von Quellenwechseln.
  private var activeTranscriptionBookId: String?
  private var lastTranscriptionProgressAt: Date?
  private var lastAppendedThroughGlobalTime: Double = 0
  /// Inkl. volatiler Speech-Ergebnisse — für Stall-Erkennung und Catch-up.
  private var lastObservedTranscriptionEnd: Double = 0
  private var audioContextUnavailableSince: Date?

  /// Vom Player bei Kapitel-/Track-Wechsel aufrufen (schneller Handoff).
  func notifyPlaybackTrackAdvanced() {
    feedTrackGeneration += 1
  }

  func refreshReadAlongAvailability() async {
    isReadAlongAvailable = await SpeechTranscriberAvailability.isSupported()
  }

  func toggle(player: PlaybackController) async {
    guard isReadAlongAvailable, player.isReadAlongDownloadReady else { return }

    resetZombieTeleprompterModeIfNeeded()

    // Auch ein noch laufender Start zählt als „an“ — der Tap bricht ihn dann ab.
    if isTeleprompterModeActive || isEnabled || isSessionBusy {
      errorMessage = nil
      await disable()
      return
    }

    await startTeleprompterMode(player: player)
  }

  /// Steuer-UI: hängende Busy-Flags ohne laufenden Task zurücksetzen.
  func sanitizeInteractionStateForControls() {
    resetZombieTeleprompterModeIfNeeded()
    guard enableTask == nil else { return }
    if !isTeleprompterModeActive {
      isSessionBusy = false
      isPreparing = false
    }
  }

  /// UI-Modus an, Session nie gestartet — blockiert sonst jeden Neustart.
  private func resetZombieTeleprompterModeIfNeeded() {
    guard isTeleprompterModeActive, !isEnabled, !isSessionBusy, enableTask == nil else { return }
    finishTeleprompterMode(resetContent: true)
  }

  /// Teleprompter-Modus einschalten: UI sofort, Session asynchron starten.
  /// Jedes Einschalten beginnt eine **neue** Session — vorheriger Modus, hängender Start und
  /// alter Analyzer werden vorher hart abgeräumt, statt den Aufruf still zu verwerfen.
  func startTeleprompterMode(player: PlaybackController) async {
    guard isReadAlongAvailable, player.isReadAlongDownloadReady else { return }

    errorMessage = nil
    guard player.activeBook != nil else {
      errorMessage = PlayerLiveTranscriptionError.noActivePlayback.localizedDescription
      return
    }

    teleprompterIntentGeneration &+= 1
    let intent = teleprompterIntentGeneration

    // Modus und Busy sofort — nicht erst nach dem Teardown. Sonst ist
    // `isTeleprompterModeActive` während `await stopSession` kurz false, `playBook`
    // überspringt disable(), und `playbackDidStop` räumt die neue Session wieder weg.
    isTeleprompterModeActive = true
    isSessionBusy = true
    isPreparing = true
    applyTeleprompterSideEffects()

    await teardownForFreshStart()

    guard teleprompterIntentGeneration == intent else { return }
    guard player.activeBook != nil else {
      errorMessage = PlayerLiveTranscriptionError.noActivePlayback.localizedDescription
      await disable()
      return
    }

    sessionGeneration &+= 1
    let generation = sessionGeneration
    boundPlayer = player
    isTeleprompterModeActive = true
    applyTeleprompterSideEffects()

    enableTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.runEnableSession(player: player, generation: generation)
    }
  }

  /// Alles aus einer eventuell noch laufenden Session beenden, damit der folgende Start auf
  /// leerem Zustand aufsetzt: Generation hochzählen (entwertet alle alten Tasks), Enable-Task
  /// und Watchdogs abbrechen und den Analyzer sofort verwerfen.
  ///
  /// `isTeleprompterModeActive` bleibt gesetzt — der Aufrufer will den Modus anlassen.
  /// Ein kurzes false würde `playBook` den Disable-Guard überspringen lassen.
  private func teardownForFreshStart() async {
    sessionGeneration &+= 1

    enableTask?.cancel()
    let pendingEnable = enableTask
    enableTask = nil
    await pendingEnable?.value

    cancelSessionWatchdogs()

    setSessionRunning(false)

    stopSessionTask?.cancel()
    let pendingStop = stopSessionTask
    stopSessionTask = nil
    await pendingStop?.value

    await stopSession()
    resetTranscriptContent()
  }

  private func cancelSessionWatchdogs() {
    startupWatchdogTask?.cancel()
    startupWatchdogTask = nil
    progressStallWatchdogTask?.cancel()
    progressStallWatchdogTask = nil
    stallRecoveryWatchdogTask?.cancel()
    stallRecoveryWatchdogTask = nil
  }

  private func runEnableSession(player: PlaybackController, generation: UInt) async {
    isPreparing = true
    isSessionBusy = true
    defer {
      isPreparing = false
      isSessionBusy = false
    }

    do {
      try Task.checkCancellation()
      guard isTeleprompterModeActive, sessionGeneration == generation else {
        await rollbackAbortedEnable(generation: generation)
        return
      }

      player.syncGlobalPositionFromPlayer()
      try await startSession(player: player, generation: generation)

      try Task.checkCancellation()
      guard isTeleprompterModeActive, sessionGeneration == generation else {
        await stopSession()
        await rollbackAbortedEnable(generation: generation)
        return
      }

      setSessionRunning(true)
      pendingStartupSyncTicks = 15
      syncTeleprompterToPlayback(at: player.liveGlobalPlaybackPosition, force: true)
      startStartupWatchdog(generation: generation)
      startProgressStallWatchdog(generation: generation)
      startStallRecoveryWatchdog(generation: generation)
      // Start erfolgreich abgeschlossen — kein hängender Task mehr für Recovery-Prüfungen.
      enableTask = nil
    } catch {
      guard !Task.isCancelled, !AbstandErrorFilter.isBenignCancellation(error) else {
        await rollbackAbortedEnable(generation: generation)
        return
      }
      guard sessionGeneration == generation else { return }

      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      await tearDownAfterFailedEnable(generation: generation, message: message)
    }
  }

  /// Enable abgebrochen, bevor `isEnabled` gesetzt wurde — Modus-Flag zurücksetzen.
  private func rollbackAbortedEnable(generation: UInt) async {
    guard sessionGeneration == generation, isTeleprompterModeActive, !isEnabled else { return }
    sessionGeneration &+= 1
    finishTeleprompterMode(resetContent: true)
    await stopSession()
    enableTask = nil
  }

  /// Fehler während `runEnableSession` — kein `disable()` (Deadlock auf MainActor).
  private func tearDownAfterFailedEnable(generation: UInt, message: String) async {
    guard sessionGeneration == generation else { return }
    cancelSessionWatchdogs()
    errorMessage = message
    sessionGeneration &+= 1
    finishTeleprompterMode(resetContent: true)
    await stopSession()
    enableTask = nil
  }

  /// Fehlerkarte manuell verworfen (z. B. anderes Panel geöffnet, View verlassen) — Session bereits beendet.
  func dismissError() {
    errorMessage = nil
  }

  /// Transkribiert die letzten fünf Minuten separat aus den lokalen Audiodateien und fasst
  /// anschließend nur dieses Ergebnis mit dem Systemmodell auf dem Gerät zusammen.
  func generateRecap(player: PlaybackController) async {
    guard !isGeneratingRecap else { return }

    player.syncGlobalPositionFromPlayer()
    let end = player.liveGlobalPlaybackPosition
    let bookId = player.activeBook?.id
    if
      let recapText,
      recapBookId == bookId,
      let recapPlaybackTime,
      end >= recapPlaybackTime,
      end - recapPlaybackTime < Self.recapCachePlaybackSeconds
    {
      self.recapText = recapText
      recapErrorMessage = nil
      return
    }

    guard player.isReadAlongDownloadReady else {
      recapText = nil
      recapErrorMessage = String(
        localized: "Download the audiobook to create an on-device recap.",
        comment: "Read along recap error"
      )
      return
    }

    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
      recapText = nil
      recapErrorMessage = String(
        localized: "On-device recap is unavailable. Enable Apple Intelligence and try again.",
        comment: "Read along recap error"
      )
      return
    }

    let contexts = player.makeLocalTranscriptionAudioContexts(
      overlapping: max(0, end - 300)...end
    )
    guard !contexts.isEmpty else {
      recapText = nil
      recapErrorMessage = String(
        localized: "The last five minutes of audio are unavailable for transcription.",
        comment: "Read along recap error"
      )
      return
    }

    isGeneratingRecap = true
    recapText = nil
    recapErrorMessage = nil
    recapFallbackNotice = nil
    recapShowsTranscript = false
    defer { isGeneratingRecap = false }

    let generation = UUID()
    let timeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.recapGenerationTimeoutSeconds * 1_000_000_000))
      guard !Task.isCancelled, let self else { return }
      // Nur abbrechen, wenn noch dieselbe Generation läuft.
      guard self.currentRecapGeneration == generation, self.isGeneratingRecap else { return }
      self.recapErrorMessage = String(
        localized: "Recap took too long. Please try again later.",
        comment: "Read along recap error"
      )
      self.isGeneratingRecap = false
    }

    do {
      currentRecapGeneration = generation
      try await ensureSpeechRecognitionAuthorized()
      let languageTag = player.preferredTranscriptionLanguageTag
      let resolution = try await SpeechTranscriptionLocaleResolver.resolve(
        preferredLanguageTag: languageTag
      )
      let locale = resolution.locale
      // Fallback-Hinweis wie beim Teleprompter: Buchsprache nicht installiert.
      if resolution.usedFallback, ABSBook.locale(fromABSMetadataLanguage: languageTag) != nil {
        let code = locale.language.languageCode?.identifier ?? locale.identifier(.bcp47)
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        recapFallbackNotice = String(
          format: String(
            localized: "Recap transcribed in %@ (book language not installed).",
            comment: "Read along recap locale fallback"),
          name
        )
      }
      try await ensureSpeechModel(locale: locale)
      guard currentRecapGeneration == generation, isGeneratingRecap else { return }

      let transcript = try await transcribeRecapAudio(
        contexts: contexts,
        globalRange: max(0, end - 300)...end,
        locale: locale
      )
      guard currentRecapGeneration == generation, isGeneratingRecap else { return }
      guard !transcript.isEmpty else {
        recapErrorMessage = String(
          localized: "No speech was recognized in the last five minutes. Try again later.",
          comment: "Read along recap error"
        )
        return
      }

      // Ausgabesprache = Buchsprache (nicht die für die Transkription aufgelöste Locale).
      // Nur falls keine Buchsprache vorliegt, fällt die Ausgabe auf die Transkriptions-Locale.
      let outputLocale = ABSBook.locale(fromABSMetadataLanguage: languageTag) ?? locale
      let recapLanguage = outputLocale.identifier(.bcp47)
      // LLM-Zusammenfassung versuchen — schlägt sie fehl (leer, Filter-Blockade, Timeout),
      //Fallback aufs rohe Transkript, damit der Nutzer nie mit nichts dasteht.
      let summary = try? await generateRecapSummary(
        model: model,
        transcript: transcript,
        recapLanguage: recapLanguage
      )
      guard currentRecapGeneration == generation, isGeneratingRecap else { return }

      let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let trimmed, !trimmed.isEmpty {
        recapText = trimmed
        recapShowsTranscript = false
      } else {
        // Keine Zusammenfassung möglich (Filter-Blockade / leere Antwort) → Transkript zeigen.
        recapText = transcript
        recapShowsTranscript = true
        recapFallbackNotice = String(
          localized: "Summary unavailable for this content — showing the transcript instead.",
          comment: "Read along recap transcript fallback"
        )
      }
      recapBookId = bookId
      recapPlaybackTime = end
    } catch is CancellationError {
      // Timeout oder neuer Recap-Versuch — Fehler bereits von timeoutTask gesetzt.
    } catch {
      recapText = nil
      recapErrorMessage = (error as? LocalizedError)?.errorDescription
        ?? String(
          localized: "The on-device recap could not be created. Please try again.",
          comment: "Read along recap error"
        )
    }
    timeoutTask.cancel()
  }

  /// LLM-Zusammenfassung aus einem Transkript. Wirft bei beliebigem Fehler (Filter-Blockade,
  /// Timeout, leere Antwort) — Aufrufer fällt dann aufs rohe Transkript zurück.
  private func generateRecapSummary(
    model: SystemLanguageModel,
    transcript: String,
    recapLanguage: String
  ) async throws -> String {
    let session = LanguageModelSession(model: model)
    let response = try await session.respond(
      to: """
      Summarize the following audiobook transcript from the last five minutes.
      Output language: \(recapLanguage).
      Write the recap exclusively in that language. Do not translate it to English unless the
      output language is English. Be concise, factual, and use 3–5 bullet points.
      Do not invent details or mention that this is a transcript.

      Transcript:
      \(transcript)
      """
    )
    return response.content
  }

  func clearRecap() {
    recapText = nil
    recapErrorMessage = nil
    recapFallbackNotice = nil
    recapShowsTranscript = false
    recapBookId = nil
    recapPlaybackTime = nil
  }

  private func transcribeRecapAudio(
    contexts: [PlayerTranscriptionAudioContext],
    globalRange: ClosedRange<Double>,
    locale: Locale
  ) async throws -> String {
    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: []
    )
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
      throw PlayerLiveTranscriptionError.conversionFailed
    }

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await analyzer.start(inputSequence: stream)
    let collector = PlayerRecapTranscriptCollector()
    let resultTask = Task {
      for try await result in transcriber.results where result.isFinal {
        await collector.append(String(result.text.characters))
      }
    }

    do {
      try await feedRecapAudio(
        contexts: contexts,
        globalRange: globalRange,
        targetFormat: format,
        input: continuation
      )
      continuation.finish()
      try await analyzer.finalizeAndFinishThroughEndOfInput()
      _ = try await resultTask.value
      return await collector.text
    } catch {
      continuation.finish()
      resultTask.cancel()
      try? await analyzer.finalizeAndFinishThroughEndOfInput()
      throw error
    }
  }

  private func feedRecapAudio(
    contexts: [PlayerTranscriptionAudioContext],
    globalRange: ClosedRange<Double>,
    targetFormat: AVAudioFormat,
    input: AsyncStream<AnalyzerInput>.Continuation
  ) async throws {
    for context in contexts {
      let localStart = max(0, globalRange.lowerBound - context.trackGlobalOffset)
      let localEnd = max(localStart, globalRange.upperBound - context.trackGlobalOffset)
      guard localEnd > localStart else { continue }

      let asset = AVURLAsset(url: context.assetURL)
      let tracks = try await asset.loadTracks(withMediaType: .audio)
      guard let audioTrack = tracks.first else {
        throw PlayerLiveTranscriptionError.audioSourceUnavailable
      }

      let reader = try AVAssetReader(asset: asset)
      let output = AVAssetReaderTrackOutput(
        track: audioTrack,
        outputSettings: [
          AVFormatIDKey: kAudioFormatLinearPCM,
          AVLinearPCMBitDepthKey: 16,
          AVLinearPCMIsFloatKey: false,
          AVLinearPCMIsBigEndianKey: false,
          AVLinearPCMIsNonInterleaved: false,
        ]
      )
      output.alwaysCopiesSampleData = false
      guard reader.canAdd(output) else { throw PlayerLiveTranscriptionError.conversionFailed }
      reader.add(output)
      reader.timeRange = CMTimeRange(
        start: CMTime(seconds: localStart, preferredTimescale: 600),
        duration: CMTime(seconds: localEnd - localStart, preferredTimescale: 600)
      )
      guard reader.startReading() else {
        throw reader.error ?? PlayerLiveTranscriptionError.audioSourceUnavailable
      }

      var converter: PlayerTranscriptionAudioConverter?
      var bufferCount = 0
      while reader.status == .reading, !Task.isCancelled {
        guard let sample = output.copyNextSampleBuffer() else { continue }
        guard let buffer = Self.sampleBufferToPCMBuffer(sample) else { continue }
        if converter == nil {
          converter = PlayerTranscriptionAudioConverter(
            sourceFormat: buffer.format,
            targetFormat: targetFormat
          )
        }
        guard let converter else { throw PlayerLiveTranscriptionError.conversionFailed }
        input.yield(AnalyzerInput(buffer: try converter.convert(buffer, to: targetFormat)))
        bufferCount += 1
        if bufferCount & 15 == 0 { await Task.yield() }
      }
      if Task.isCancelled { throw CancellationError() }
      guard reader.status == .completed else {
        throw reader.error ?? PlayerLiveTranscriptionError.audioSourceUnavailable
      }
    }
  }

  /// Modus beenden und Session vollständig stoppen (idempotent).
  func disable(resetError: Bool = true) async {
    teleprompterIntentGeneration &+= 1
    if resetError {
      errorMessage = nil
    }
    enableTask?.cancel()
    let pendingEnable = enableTask
    enableTask = nil
    if let pendingEnable {
      await pendingEnable.value
    }

    cancelSessionWatchdogs()

    if let player = boundPlayer {
      lastTeleprompterPlaybackTime = player.liveGlobalPlaybackPosition
    }

    sessionGeneration &+= 1
    finishTeleprompterMode(resetContent: true)

    stopSessionTask?.cancel()
    let stopTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.stopSession()
    }
    stopSessionTask = stopTask
    await stopTask.value
    if stopSessionTask == stopTask {
      stopSessionTask = nil
    }
    isSessionBusy = false
  }

  /// Modus-Flags zurücksetzen (ohne async Stop — nur intern).
  private func finishTeleprompterMode(resetContent: Bool) {
    isTeleprompterModeActive = false
    setSessionRunning(false)
    isPreparing = false
    isSessionBusy = false
    applyTeleprompterSideEffects()
    if resetContent {
      words = []
      resetTranscriptContent()
    }
    isTeleprompterReady = false
    teleprompterSyncGeneration = 0
    teleprompterSyncedPlaybackTime = 0
    modelDownloadProgress = nil
    localeFallbackNotice = nil
    activeTranscriptionBookId = nil
  }

  func handlePlaybackTick(player: PlaybackController) {
    guard isTeleprompterModeActive, isEnabled else { return }
    boundPlayer = player
    // Kein `publishWords()` pro Tick (12,5 Hz): Wörter und Zeilen ändern sich nur mit neuen
    // Speech-Ergebnissen, und der Teleprompter leitet seine Position selbst aus der Zeit ab.
    // Jede Veröffentlichung schlägt sonst als `objectWillChange` auf den ganzen Player durch.
    refreshTeleprompterReadiness()
    if pendingStartupSyncTicks > 0 {
      pendingStartupSyncTicks -= 1
      syncTeleprompterToPlayback(at: player.liveGlobalPlaybackPosition, force: true)
    }
  }

  func playbackDidStop() {
    let intentAtStop = teleprompterIntentGeneration
    Task { @MainActor in
      // Veralteter Stop darf einen neueren Start nicht mehr abwürgen.
      guard self.teleprompterIntentGeneration == intentAtStop else { return }
      guard self.isTeleprompterModeActive else { return }
      await self.disable()
    }
  }

  private func failTeleprompterSession(
    _ error: PlayerLiveTranscriptionError,
    generation: UInt
  ) async {
    await failTeleprompterSession(message: error.localizedDescription, generation: generation)
  }

  private func failTeleprompterSession(message: String, generation: UInt) async {
    guard sessionGeneration == generation, isTeleprompterModeActive else { return }
    errorMessage = message
    await disable(resetError: false)
  }

  private func startStartupWatchdog(generation: UInt) {
    startupWatchdogTask?.cancel()
    startupWatchdogTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(Self.transcriptionStartupTimeoutSeconds * 1_000_000_000))
      guard let self, !Task.isCancelled else { return }
      guard self.sessionGeneration == generation,
        self.isTeleprompterModeActive,
        !self.isTeleprompterReady
      else { return }
      await self.failTeleprompterSession(.transcriptionStartupTimedOut, generation: generation)
    }
  }

  private func startProgressStallWatchdog(generation: UInt) {
    progressStallWatchdogTask?.cancel()
    lastTranscriptionProgressAt = Date()
    lastAppendedThroughGlobalTime = transcriptionProgressEnd
    progressStallWatchdogTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard let self, !Task.isCancelled else { return }
        guard self.sessionGeneration == generation, self.isTeleprompterModeActive else { return }
        if self.isTeleprompterReady { return }
        let progressEnd = self.transcriptionProgressEnd
        if progressEnd > self.lastAppendedThroughGlobalTime + 0.05 {
          self.lastAppendedThroughGlobalTime = progressEnd
          self.lastTranscriptionProgressAt = Date()
          continue
        }
        guard let lastProgress = self.lastTranscriptionProgressAt else { continue }
        if Date().timeIntervalSince(lastProgress) >= Self.transcriptionProgressStallSeconds {
          await self.failTeleprompterSession(.transcriptionProgressStalled, generation: generation)
          return
        }
      }
    }
  }

  /// Die Startup-Watchdogs enden mit der Bereitschaft. Danach kann der Audio-Feed oder der
  /// Analyzer still hängen bleiben — sichtbar als „etwas Text, dann nichts mehr". Dieser
  /// Watchdog läuft über die ganze Session und setzt Feed bzw. Session selbst neu auf.
  private func startStallRecoveryWatchdog(generation: UInt) {
    stallRecoveryWatchdogTask?.cancel()
    stallRecoveryWatchdogTask = Task { @MainActor [weak self] in
      var lastEnd = -1.0
      var lastProgressAt = Date()
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard let self, !Task.isCancelled else { return }
        guard self.sessionIsCurrent(generation), self.isEnabled else { return }

        let end = self.transcriptionProgressEnd
        let stalled = self.isTranscriptionStalled(progressEnd: end)
        if end > lastEnd + 0.05 || !stalled {
          lastEnd = max(lastEnd, end)
          lastProgressAt = Date()
          continue
        }
        guard Date().timeIntervalSince(lastProgressAt) >= Self.feedRecoveryStallSeconds else {
          continue
        }
        lastProgressAt = Date()
        lastEnd = -1
        self.recoverStalledTranscription(generation: generation)
      }
    }
  }

  /// Nur ein echter Stillstand: erst nach Bereitschaft, bei laufender Wiedergabe und wenn das
  /// Transkript nicht bewusst weit vorausliegt (dann pausiert der Feed planmäßig).
  private func isTranscriptionStalled(progressEnd: Double) -> Bool {
    guard isTeleprompterReady, let player = boundPlayer, player.isPlaying else { return false }
    return progressEnd < player.liveGlobalPlaybackPosition + Self.transcriptionCatchUpLagSeconds
  }

  /// Ergebnis-Stream vorzeitig beendet — Session neu aufbauen, sofern noch Bedarf besteht.
  private func handleResultsStreamEndedUnexpectedly(generation: UInt) {
    guard sessionIsCurrent(generation), isEnabled else { return }
    DebugLogCollector.shared.log("readAlong results stream ended while session active")
    restartSessionAfterStall()
  }

  /// Erst den Audio-Feed am Abspielpunkt neu aufsetzen; hilft das nicht (oder läuft der
  /// Feed-Loop nicht mehr), die ganze Speech-Session neu aufbauen.
  private func recoverStalledTranscription(generation: UInt) {
    guard sessionIsCurrent(generation) else { return }
    if let last = lastFeedStallRecoveryAt,
      Date().timeIntervalSince(last) > Self.feedStallRecoveryResetSeconds
    {
      feedStallRecoveryCount = 0
    }
    lastFeedStallRecoveryAt = Date()
    feedStallRecoveryCount += 1

    let feedLoopAlive = runningFeedLoopGeneration == generation
    let needsSessionRestart =
      !feedLoopAlive || feedStallRecoveryCount > Self.maxFeedRestartsBeforeSessionRestart
    DebugLogCollector.shared.log(
      "readAlong stall attempt=\(feedStallRecoveryCount) feedLoop=\(feedLoopAlive) "
        + "progressEnd=\(String(format: "%.1f", transcriptionProgressEnd)) "
        + "playback=\(String(format: "%.1f", boundPlayer?.liveGlobalPlaybackPosition ?? -1)) "
        + "sessionRestart=\(needsSessionRestart)"
    )

    guard needsSessionRestart else {
      feedRestartRequested = true
      return
    }
    restartSessionAfterStall()
  }

  /// Neustart wie „Try again“, nur ohne Fehlerkarte. Läuft in einem eigenen Task, weil
  /// `disable()` den aufrufenden Watchdog bzw. Ergebnis-Task abbricht.
  private func restartSessionAfterStall() {
    guard let player = boundPlayer else { return }
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.disable(resetError: true)
      guard player.isReadAlongDownloadReady else { return }
      await self.startTeleprompterMode(player: player)
    }
  }

  /// Transkript-Fortschritt inkl. volatiler Ergebnisse.
  private var transcriptionProgressEnd: Double {
    let volatileEnd = volatileTailWords.last(where: { !$0.isWhitespaceOnly })?.globalEnd ?? 0
    return max(appendedThroughGlobalTime, volatileEnd)
  }

  private func markTranscriptionActivity(endTime: Double? = nil) {
    lastTranscriptionProgressAt = Date()
    if let endTime {
      lastObservedTranscriptionEnd = max(lastObservedTranscriptionEnd, endTime)
    }
  }

  private func cancelStartupWatchdogsIfPreviewVisible() {
    guard isTeleprompterReady || !transcriptLines.isEmpty else { return }
    startupWatchdogTask?.cancel()
    startupWatchdogTask = nil
  }

  private func sessionIsCurrent(_ generation: UInt) -> Bool {
    isTeleprompterModeActive && sessionGeneration == generation
  }

  private func setSessionRunning(_ running: Bool) {
    guard isEnabled != running else { return }
    isEnabled = running
    applyTeleprompterSideEffects()
  }

  private func applyTeleprompterSideEffects() {
    UIApplication.shared.isIdleTimerDisabled = isTeleprompterModeActive
    // Hohe Tick-Rate erst bei laufender Session — nicht während Modell-Download/Vorbereitung.
    boundPlayer?.setReadAlongHighFrequencyTicks(isTeleprompterModeActive && isEnabled)
  }

  // MARK: - Berechtigung

  /// `SpeechAnalyzer` nutzt dieselbe Nutzerfreigabe wie `SFSpeechRecognizer`.
  private func ensureSpeechRecognitionAuthorized() async throws {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      return
    case .notDetermined:
      let status = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
      }
      guard status == .authorized else {
        throw PlayerLiveTranscriptionError.speechRecognitionDenied
      }
    case .denied, .restricted:
      throw PlayerLiveTranscriptionError.speechRecognitionDenied
    @unknown default:
      throw PlayerLiveTranscriptionError.speechRecognitionDenied
    }
  }

  // MARK: - Session

  /// Baut eine frische Speech-Session auf. `teardownForFreshStart()` hat die vorherige bereits
  /// vollständig verworfen — hier wird nichts mehr recycelt.
  private func startSession(player: PlaybackController, generation: UInt) async throws {
    guard sessionIsCurrent(generation) else { return }
    try await ensureSpeechRecognitionAuthorized()
    guard sessionIsCurrent(generation) else { return }
    resetTranscriptContent()
    resetFeedState()
    feedTrackGeneration = 0
    audioContextUnavailableSince = nil
    boundPlayer = player
    activeTranscriptionBookId = player.activeBook?.id
    player.syncGlobalPositionFromPlayer()
    guard player.activeBook != nil else {
      throw PlayerLiveTranscriptionError.noActivePlayback
    }
    guard let context = await player.makeTranscriptionAudioContext() else {
      if player.isPlaybackFromOfflineDownload, !player.isUsingLocalTrackFiles {
        throw PlayerLiveTranscriptionError.streamingPlaybackUnavailable
      }
      if !player.canBuildTranscriptionStreamContext {
        throw PlayerLiveTranscriptionError.streamingPlaybackUnavailable
      }
      throw PlayerLiveTranscriptionError.audioSourceUnavailable
    }
    let languageTag = player.preferredTranscriptionLanguageTag
    let localeResolution = try await SpeechTranscriptionLocaleResolver.resolve(
      preferredLanguageTag: languageTag
    )
    let resolvedContext = PlayerTranscriptionAudioContext(
      assetURL: context.assetURL,
      streamAuthToken: context.streamAuthToken,
      trackGlobalOffset: context.trackGlobalOffset,
      locale: localeResolution.locale,
      trackIndex: context.trackIndex
    )
    if localeResolution.usedFallback {
      let code =
        localeResolution.locale.language.languageCode?.identifier
        ?? localeResolution.locale.identifier(.bcp47)
      let name = Locale.current.localizedString(forLanguageCode: code) ?? code
      localeFallbackNotice = String(
        format: String(
          localized: "Using %@ speech recognition (book language not installed).",
          comment: "Live transcript locale fallback"),
        name
      )
    } else {
      localeFallbackNotice = nil
    }

    try await ensureSpeechModel(locale: resolvedContext.locale)
    activeContext = resolvedContext
    lastFeedTrackKey = player.transcriptionTrackKey

    let speechTranscriber = SpeechTranscriber(
      locale: resolvedContext.locale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults],
      attributeOptions: [.audioTimeRange]
    )
    transcriber = speechTranscriber
    let speechAnalyzer = SpeechAnalyzer(modules: [speechTranscriber])
    analyzer = speechAnalyzer
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [speechTranscriber])
    else {
      throw PlayerLiveTranscriptionError.conversionFailed
    }
    analyzerFormat = format

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    inputBuilder = continuation
    try await speechAnalyzer.start(inputSequence: stream)

    guard sessionIsCurrent(generation) else {
      continuation.finish()
      try? await speechAnalyzer.finalizeAndFinishThroughEndOfInput()
      return
    }

    resultsTask = Task { [weak self] in
      await self?.consumeResults(from: speechTranscriber, generation: generation)
    }

    let localStart = player.transcriptionLocalStartSeconds(preRoll: Self.preRollSeconds)
    sessionFeedStartGlobalTime = context.trackGlobalOffset + localStart
    teleprompterBufferingStartedAt = Date()
    fedAnalyzerSeconds = 0
    feedTimeline = [FeedTimelineSegment(analyzerStart: 0, globalStart: sessionFeedStartGlobalTime)]
    publishWords()
    syncTeleprompterToPlayback(at: player.liveGlobalPlaybackPosition, force: true)
    feedTask = Task.detached(priority: .userInitiated) { [weak self] in
      await self?.continuousFeedLoop(targetFormat: format, generation: generation)
    }
  }

  private enum TrackFeedOutcome {
    case completed
    case trackChanged
    /// Wiedergabe ist dem Feed weit vorausgesprungen — Reader am Abspielpunkt neu aufsetzen.
    case restartAtPlayback
  }

  private struct TrackFeedResult {
    let outcome: TrackFeedOutcome
    /// Tatsächlich geschobene Audiosekunden — hält `fedAnalyzerSeconds` exakt.
    let fedAnalyzerSeconds: Double
  }

  /// Entscheidung des Feed-Loops aus einem einzigen MainActor-Hop.
  private enum FeedStep {
    case feed
    case wait(nanoseconds: UInt64)
    case trackChanged
    case restartAtPlayback
  }

  /// Session vollständig verwerfen. Reihenfolge: Input schließen, Feed abbrechen und auslaufen
  /// lassen, dann den Analyzer sofort abbrechen (beendet auch den Ergebnis-Stream).
  ///
  /// `cancelAndFinishNow()` statt `finalizeAndFinishThroughEndOfInput()`: beim Abschalten ist
  /// kein Restergebnis mehr von Interesse, und das Finalisieren arbeitet zuerst den gesamten
  /// noch eingespeisten Backlog ab (bis `maxAnalyzerBacklogSeconds` an Audio). Genau darauf
  /// wartete der nächste Start — sichtbar als Teleprompter, der nicht anläuft.
  private func stopSession() async {
    inputBuilder?.finish()
    inputBuilder = nil

    let feed = feedTask
    feedTask = nil
    feed?.cancel()

    let results = resultsTask
    resultsTask = nil
    results?.cancel()

    let analyzerToCancel = analyzer
    transcriber = nil
    analyzer = nil
    analyzerFormat = nil
    activeContext = nil

    await feed?.value
    if let analyzerToCancel {
      await analyzerToCancel.cancelAndFinishNow()
    }
    await results?.value

    resetFeedState()
  }

  /// Feed-Zustand und Selbstheilungszähler. Ohne dieses Zurücksetzen erbt die nächste Session
  /// die verbrauchten Recovery-Versuche und eskaliert sofort wieder zum Neustart.
  private func resetFeedState() {
    feedTimeline = []
    fedAnalyzerSeconds = 0
    feedRestartRequested = false
    feedStallRecoveryCount = 0
    lastFeedStallRecoveryAt = nil
    lastFeedTrackKey = nil
    runningFeedLoopGeneration = nil
  }

  private func ensureSpeechModel(locale: Locale) async throws {
    let supported = await SpeechTranscriber.supportedLocales
    guard let installLocale = SpeechTranscriptionLocaleResolver.matchLocale(locale, in: supported)
    else {
      throw PlayerLiveTranscriptionError.localeNotSupported
    }
    let installed = await SpeechTranscriber.installedLocales
    if installed.contains(where: {
      SpeechTranscriptionLocaleResolver.matchLocale(installLocale, in: [$0]) != nil
    }) {
      return
    }

    let installerModule = SpeechTranscriber(
      locale: installLocale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults],
      attributeOptions: [.audioTimeRange]
    )
    guard let downloader = try await AssetInventory.assetInstallationRequest(supporting: [installerModule])
    else {
      throw PlayerLiveTranscriptionError.modelDownloadFailed
    }

    modelDownloadProgress = 0
    let progress = downloader.progress
    let progressTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        self?.modelDownloadProgress = progress.fractionCompleted
        try? await Task.sleep(nanoseconds: 200_000_000)
      }
    }
    defer {
      progressTask.cancel()
      modelDownloadProgress = nil
    }
    try await downloader.downloadAndInstall()
  }

  private func consumeResults(from transcriber: SpeechTranscriber, generation: UInt) async {
    do {
      // Volatile Results batchen — Finals sofort; vermeidet MainActor-Hop pro Token.
      var lastVolatile: SpeechTranscriber.Result?
      let clock = ContinuousClock()
      var lastFlush = clock.now
      let volatileMinInterval: Duration = .milliseconds(100)
      for try await result in transcriber.results {
        if result.isFinal {
          lastVolatile = nil
        } else {
          lastVolatile = result
          guard clock.now - lastFlush >= volatileMinInterval else { continue }
          lastVolatile = nil
        }
        // Prüfung und Anwendung in einem Hop — zwei Hops pro Ergebnis summieren sich.
        let stillCurrent = await MainActor.run { () -> Bool in
          guard self.sessionIsCurrent(generation) else { return false }
          self.applyTranscriptionResult(result)
          return true
        }
        guard stillCurrent else { return }
        lastFlush = clock.now
      }
      if let lastVolatile {
        await MainActor.run { self.applyTranscriptionResult(lastVolatile) }
      }
      // Der Analyzer hat den Ergebnis-Stream beendet, ohne Fehler und ohne dass wir gestoppt
      // hätten. Ein neuer Audio-Feed kann daran nichts ändern — nur eine neue Session.
      await MainActor.run { self.handleResultsStreamEndedUnexpectedly(generation: generation) }
    } catch {
      guard !AbstandErrorFilter.isBenignCancellation(error) else { return }
      let message = error.localizedDescription
      await MainActor.run { DebugLogCollector.shared.log("readAlong results failed: \(message)") }
      await failTeleprompterSession(message: message, generation: generation)
    }
  }

  private func applyTranscriptionResult(_ result: SpeechTranscriber.Result) {
    if result.isFinal {
      volatileTailWords = []
      applyFinalTranscriptionResult(result)
    } else {
      volatileTailWords = words(from: result.text, isVolatile: true)
      if let end = volatileTailWords.last(where: { !$0.isWhitespaceOnly })?.globalEnd {
        markTranscriptionActivity(endTime: end)
      } else {
        markTranscriptionActivity()
      }
      publishWords()
    }
  }

  private func applyFinalTranscriptionResult(_ result: SpeechTranscriber.Result) {
    let parsed = words(from: result.text, isVolatile: false)
    let fresh = deduplicatedNewFinalWords(parsed)
    guard !fresh.isEmpty else { return }
    finalizedWords.append(contentsOf: fresh)
    lineAccumulator.appendFinalizedWords(fresh)
    pruneRetainedTranscript()
    publishWords()
  }

  /// Ohne Obergrenze wachsen Wörter und Zeilen über Stunden Laufzeit unbegrenzt, und jede
  /// Veröffentlichung kopiert mehr Daten. Wörter überleben Zeilen, damit ein Reflow bei
  /// Schriftgrößenwechsel die angezeigte Historie nicht verkürzt.
  private func pruneRetainedTranscript() {
    if finalizedWords.count >= Self.maxRetainedTranscriptWords + Self.transcriptPruneChunk {
      finalizedWords.removeFirst(finalizedWords.count - Self.maxRetainedTranscriptWords)
    }
    lineAccumulator.pruneClosedLines(
      keeping: Self.maxRetainedTranscriptLines,
      chunk: Self.transcriptPruneChunk
    )
  }

  private func deduplicatedNewFinalWords(_ parsed: [PlayerTranscriptWord]) -> [PlayerTranscriptWord] {
    var out: [PlayerTranscriptWord] = []
    for word in parsed {
      if word.isWhitespaceOnly { continue }
      if word.globalStart < appendedThroughGlobalTime - 0.05,
        word.globalEnd <= appendedThroughGlobalTime + 0.02
      { continue }
      if let last = finalizedWords.last(where: { !$0.isWhitespaceOnly }),
        last.text == word.text,
        abs(last.globalStart - word.globalStart) < 0.15
      {
        continue
      }
      out.append(word)
    }
    if let last = out.last(where: { !$0.isWhitespaceOnly }) {
      appendedThroughGlobalTime = max(appendedThroughGlobalTime, last.globalEnd)
      markTranscriptionActivity(endTime: last.globalEnd)
    }
    return out
  }

  private func resetTranscriptContent() {
    finalizedWords = []
    volatileTailWords = []
    lineAccumulator.reset()
    appendedThroughGlobalTime = 0
    words = []
    transcriptLines = []
    isTeleprompterReady = false
    sessionFeedStartGlobalTime = 0
    teleprompterBufferingStartedAt = nil
    teleprompterReflowFontSize = 0
    teleprompterReflowWidth = 0
    feedTimeline = []
    fedAnalyzerSeconds = 0
    audioContextUnavailableSince = nil
    lastTranscriptionProgressAt = nil
    lastAppendedThroughGlobalTime = 0
    lastObservedTranscriptionEnd = 0
  }

  private func transcriptLinesForDisplay() -> [PlayerTranscriptLine] {
    var lines = lineAccumulator.publishedLines()
    if !volatileTailWords.isEmpty {
      lines.append(
        contentsOf: PlayerTranscriptLineAccumulator.makeLines(
          from: volatileTailWords,
          maxCharactersPerLine: lineAccumulator.maxCharactersPerLine,
          volatile: true
        )
      )
    }
    return lines
  }

  private func words(from text: AttributedString, isVolatile: Bool) -> [PlayerTranscriptWord] {
    var out: [PlayerTranscriptWord] = []
    for run in text.runs {
      guard let tr = run.audioTimeRange else { continue }
      let start = globalTime(forAnalyzerSeconds: tr.start.seconds)
      let end = max(start, globalTime(forAnalyzerSeconds: tr.end.seconds))
      let chunk = String(text[run.range].characters)
      guard !chunk.isEmpty else { continue }
      out.append(contentsOf: splitIntoWords(chunk: chunk, start: start, end: end, isVolatile: isVolatile))
    }
    if out.isEmpty {
      let plain = String(text.characters)
      guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
      let fallback = fallbackGlobalTime
      out.append(
        contentsOf: splitIntoWords(
          chunk: plain, start: fallback, end: fallback + 0.01, isVolatile: isVolatile))
    }
    return out
  }

  private func splitIntoWords(
    chunk: String,
    start: Double,
    end: Double,
    isVolatile: Bool
  ) -> [PlayerTranscriptWord] {
    var tokens: [String] = []
    var current = ""
    for ch in chunk {
      if ch.isWhitespace {
        if !current.isEmpty {
          tokens.append(current)
          current = ""
        }
        tokens.append(String(ch))
      } else {
        current.append(ch)
      }
    }
    if !current.isEmpty { tokens.append(current) }

    let spoken = tokens.filter { !$0.allSatisfy(\.isWhitespace) }
    let spokenCount = max(1, spoken.count)
    var spokenIndex = 0
    let duration = max(0.01, end - start)
    var result: [PlayerTranscriptWord] = []

    for token in tokens {
      let isSpace = token.allSatisfy(\.isWhitespace)
      let wStart: Double
      let wEnd: Double
      if isSpace {
        wStart = start
        wEnd = start
      } else {
        wStart = start + duration * Double(spokenIndex) / Double(spokenCount)
        wEnd = start + duration * Double(spokenIndex + 1) / Double(spokenCount)
        spokenIndex += 1
      }
      let display = isSpace ? token : token + " "
      let id = "w-\(Int((wStart * 1000).rounded()))-\(result.count)"
      result.append(
        PlayerTranscriptWord(
          id: id,
          text: display,
          globalStart: wStart,
          globalEnd: wEnd,
          isVolatile: isVolatile
        )
      )
    }
    return result
  }

  func publishWords() {
    refreshTeleprompterReadiness()
    words = finalizedWords
    if !volatileTailWords.isEmpty {
      words.append(contentsOf: volatileTailWords)
    }
    transcriptLines = words.isEmpty ? [] : transcriptLinesForDisplay()
    cancelStartupWatchdogsIfPreviewVisible()
  }

  /// Puffer prüfen: genug Zeilen + transkribierte Dauer (nicht „X s vor Live“, das klappt bei Play nicht).
  private func refreshTeleprompterReadiness() {
    guard isTeleprompterModeActive, let player = boundPlayer else {
      if isTeleprompterReady { isTeleprompterReady = false }
      return
    }

    let playback = player.liveGlobalPlaybackPosition
    let progressEnd = transcriptionProgressEnd
    let closedLines = lineAccumulator.publishedLineCount
    let transcribedSpan = max(0, progressEnd - sessionFeedStartGlobalTime)
    let inStartupGrace: Bool = {
      guard let start = teleprompterBufferingStartedAt else { return true }
      return Date().timeIntervalSince(start) < Self.teleprompterStartupGraceSeconds
    }()
    let nearLiveWhilePlaying =
      !player.isPlaying
      || inStartupGrace
      || progressEnd >= playback - Self.maxPlaybackLagWhilePlaying

    let hasMinimumContent =
      closedLines >= Self.minClosedLinesForDisplay
      && transcribedSpan >= Self.minTranscribedSecondsForDisplay
      && progressEnd > 0.5

    let timedOut: Bool = {
      guard let start = teleprompterBufferingStartedAt else { return false }
      return Date().timeIntervalSince(start) >= Self.teleprompterReadinessTimeoutSeconds
    }()
    let fallbackReady =
      timedOut
      && closedLines >= max(2, Self.minClosedLinesForDisplay - 2)
      && progressEnd > 0.5
      && transcribedSpan >= 2

    // Früher sichtbar: genug Text da, auch wenn Wiedergabe voraus ist (Scroll-Sync folgt nach).
    let earlyPartialReady =
      (closedLines >= 2 || !volatileTailWords.isEmpty)
      && transcribedSpan >= 3
      && progressEnd > 0.5

    let ready =
      (hasMinimumContent && (inStartupGrace ? (nearLiveWhilePlaying || earlyPartialReady) : true))
      || fallbackReady
      || earlyPartialReady

    guard ready != isTeleprompterReady else { return }
    isTeleprompterReady = ready
    if ready {
      startupWatchdogTask?.cancel()
      startupWatchdogTask = nil
      progressStallWatchdogTask?.cancel()
      progressStallWatchdogTask = nil
      syncTeleprompterToPlayback(at: playback, force: true)
    }
  }

  /// Zeilenumbruch an Display-Breite und Schriftgröße anpassen; bestehende Zeilen neu umbrechen.
  func updateTeleprompterContentWidth(
    _ width: CGFloat,
    layout: PlayerTeleprompterLayout = PlayerTeleprompterMetrics.defaultLayout
  ) {
    let limit = PlayerTeleprompterMetrics.characterLimit(forContentWidth: width, layout: layout)
    let layoutChanged = abs(teleprompterReflowFontSize - layout.fontSize) > 0.01
      || abs(teleprompterReflowWidth - width) > 0.01
    let limitChanged = lineAccumulator.maxCharactersPerLine != limit
    guard layoutChanged || limitChanged else { return }

    teleprompterReflowFontSize = layout.fontSize
    teleprompterReflowWidth = width

    if finalizedWords.isEmpty {
      lineAccumulator.maxCharactersPerLine = limit
      return
    }
    lineAccumulator.rebuildLines(from: finalizedWords, maxCharactersPerLine: limit)
    publishWords()
  }
  func continuousLinePosition(at globalTime: Double) -> Double {
    let lines = transcriptLines
    guard !lines.isEmpty else { return 0 }
    let idx = activeLineIndex(in: lines, at: globalTime)
    let progress = lineProgress(in: lines, lineIndex: idx, at: globalTime)
    return Double(idx) + progress
  }

  func teleprompterRole(forLineIndex index: Int, centerFractional: Double) -> PlayerTeleprompterLineRole {
    let delta = Double(index) - centerFractional
    if delta < -0.35 { return .past }
    if delta > 0.35 { return .upcoming }
    return .current
  }

  func teleprompterWindow(at globalTime: Double) -> PlayerTeleprompterWindow {
    let lines = transcriptLines
    let centerIdx = activeLineIndex(in: lines, at: globalTime)
    let progress = lineProgress(in: lines, lineIndex: centerIdx, at: globalTime)
    var slots: [PlayerTeleprompterSlot] = []

    for delta in -PlayerTeleprompterMetrics.renderedLinesBeforeCenter...PlayerTeleprompterMetrics.renderedLinesBeforeCenter {
      let idx = centerIdx + delta
      let role: PlayerTeleprompterLineRole
      if delta < 0 { role = .past }
      else if delta > 0 { role = .upcoming }
      else { role = .current }

      if idx >= 0, idx < lines.count {
        slots.append(
          PlayerTeleprompterSlot(
            id: "slot-\(delta)-\(lines[idx].id)",
            line: lines[idx],
            role: role
          )
        )
      } else {
        slots.append(
          PlayerTeleprompterSlot(id: "slot-empty-\(delta)", line: nil, role: .empty)
        )
      }
    }
    return PlayerTeleprompterWindow(
      slots: slots,
      centerLineIndex: centerIdx,
      lineProgress: progress
    )
  }

  /// Aktuelles Wort zur Wiedergabezeit.
  func activeWord(at globalTime: Double) -> PlayerTranscriptWord? {
    activeWordHit(at: globalTime)?.word
  }

  /// Aktives Wort samt Zeilenindex. Die View braucht pro Frame beides und darf dafür nicht
  /// über alle bisherigen Zeilen und Wörter suchen.
  func activeWordHit(at globalTime: Double) -> (lineIndex: Int, word: PlayerTranscriptWord)? {
    let lines = transcriptLines
    guard !lines.isEmpty else { return nil }
    let idx = activeLineIndex(in: lines, at: globalTime)
    let line = lines[idx]
    guard globalTime >= line.globalStart, globalTime < line.globalEnd else { return nil }
    guard let word = activeWord(in: line, at: globalTime) else { return nil }
    return (idx, word)
  }

  func activeWord(in line: PlayerTranscriptLine, at globalTime: Double) -> PlayerTranscriptWord? {
    line.spokenWords.first { globalTime >= $0.globalStart && globalTime < $0.globalEnd }
  }

  func activeLineIndex(at globalTime: Double) -> Int {
    activeLineIndex(in: transcriptLines, at: globalTime)
  }

  func lineProgress(at globalTime: Double) -> Double {
    let lines = transcriptLines
    let idx = activeLineIndex(in: lines, at: globalTime)
    return lineProgress(in: lines, lineIndex: idx, at: globalTime)
  }

  /// Teleprompter beim Start an die aktuelle Wiedergabe ausrichten.
  func syncTeleprompterToPlayback(at playbackGlobalTime: Double, force: Bool = false) {
    let playback = max(0, playbackGlobalTime)

    let transcriptImplied = impliedTranscriptCenterTime(near: playback)
    let driftFromTranscript = abs(playback - transcriptImplied)
    let driftFromLastSession =
      lastTeleprompterPlaybackTime > 0
      ? abs(playback - lastTeleprompterPlaybackTime)
      : 0

    let needsJump =
      force
      || driftFromTranscript > 0.5
      || driftFromLastSession > 0.5

    teleprompterSyncedPlaybackTime = playback
    lastTeleprompterPlaybackTime = playback
    if needsJump || !transcriptLines.isEmpty {
      teleprompterSyncGeneration &+= 1
    }
    publishWords()
  }

  /// Mitte der Zeile/Wortposition, die der Teleprompter ohne Sync anzeigen würde.
  private func impliedTranscriptCenterTime(near playback: Double) -> Double {
    if let word = activeWord(at: playback) {
      return (word.globalStart + word.globalEnd) * 0.5
    }
    let lines = transcriptLines
    guard !lines.isEmpty else { return 0 }
    let idx = activeLineIndex(in: lines, at: playback)
    let line = lines[idx]
    return (line.globalStart + line.globalEnd) * 0.5
  }

  /// Fortlaufende Zeilenposition (Ganzzahl = Zeilenanfang, Nachkomma = Fortschritt in der Zeile).
  func fractionalActiveLinePosition(at globalTime: Double) -> Double {
    fractionalActiveLinePosition(in: transcriptLines, at: globalTime)
  }

  private func fractionalActiveLinePosition(
    in lines: [PlayerTranscriptLine],
    at globalTime: Double
  ) -> Double {
    guard !lines.isEmpty else { return 0 }
    if globalTime <= lines[0].globalStart { return 0 }

    let lastIdx = lines.count - 1
    if globalTime >= lines[lastIdx].globalEnd {
      let gap = globalTime - lines[lastIdx].globalEnd
      let span = max(0.35, lines[lastIdx].globalEnd - lines[lastIdx].globalStart)
      // Wiedergabe voraus: in leeren Bereich hinter letzter Zeile scrollen (nicht alten Text zentrieren).
      if gap > 0.25 {
        return Double(lastIdx + 1) + min(2.5, gap / span)
      }
      return Double(lastIdx) + min(0.92, gap / span)
    }

    let idx = activeLineIndex(in: lines, at: globalTime)
    let line = lines[idx]
    if globalTime < line.globalEnd {
      let span = line.globalEnd - line.globalStart
      let progress = span > 0 ? (globalTime - line.globalStart) / span : 0
      return Double(idx) + min(1, max(0, progress))
    }
    // Lücke zwischen zwei Zeilen — am Anfang der nächsten stehen bleiben.
    return Double(min(lastIdx, idx + 1))
  }

  /// Letzte Zeile, die nicht nach `globalTime` beginnt. Zeilen sind zeitlich sortiert
  /// (Rücksprünge ankern das Transkript neu), deshalb genügt eine Binärsuche — eine
  /// lineare Suche würde bei 60 fps mit der Transkriptlänge immer teurer.
  private func activeLineIndex(in lines: [PlayerTranscriptLine], at globalTime: Double) -> Int {
    guard !lines.isEmpty else { return 0 }
    var low = 0
    var high = lines.count - 1
    var candidate = 0
    while low <= high {
      let mid = low + (high - low) / 2
      if lines[mid].globalStart <= globalTime {
        candidate = mid
        low = mid + 1
      } else {
        high = mid - 1
      }
    }
    return candidate
  }

  private func lineProgress(
    in lines: [PlayerTranscriptLine],
    lineIndex: Int,
    at globalTime: Double
  ) -> Double {
    guard lines.indices.contains(lineIndex) else { return 0 }
    let line = lines[lineIndex]
    let span = line.globalEnd - line.globalStart
    guard span > 0 else { return 0 }
    return min(1, max(0, (globalTime - line.globalStart) / span))
  }

  // MARK: - Analyzer-Zeitachse → Hörbuchzeit

  /// Analyzer-Zeitstempel auf globale Hörbuchzeit abbilden.
  private func globalTime(forAnalyzerSeconds analyzerSeconds: Double) -> Double {
    guard
      let segment = feedTimeline.last(where: { analyzerSeconds >= $0.analyzerStart - 0.001 })
        ?? feedTimeline.first
    else { return analyzerSeconds }
    return segment.globalStart + max(0, analyzerSeconds - segment.analyzerStart)
  }

  /// Ergebnis ohne `audioTimeRange` — ans bekannte Transkript-Ende hängen.
  private var fallbackGlobalTime: Double {
    max(appendedThroughGlobalTime, feedTimeline.last?.globalStart ?? 0)
  }

  /// Neues Feed-Segment anmelden, bevor dessen erster Buffer geschoben wird.
  private func beginFeedSegment(globalStart: Double) {
    // Rücksprung (z. B. vorheriges Kapitel): Transkript neu ankern. Sonst verwirft die
    // Dedup-Logik alle Wörter vor dem alten Höchststand und der Teleprompter friert ein.
    if appendedThroughGlobalTime > globalStart + Self.feedBackwardResetSeconds {
      DebugLogCollector.shared.log(
        "readAlong reanchor transcript at=\(String(format: "%.1f", globalStart)) "
          + "was=\(String(format: "%.1f", appendedThroughGlobalTime))"
      )
      reanchorTranscript(atGlobalTime: globalStart)
    }
    DebugLogCollector.shared.log(
      "readAlong segment begin global=\(String(format: "%.1f", globalStart)) "
        + "analyzer=\(String(format: "%.1f", fedAnalyzerSeconds))"
    )
    feedTimeline.append(
      FeedTimelineSegment(analyzerStart: fedAnalyzerSeconds, globalStart: globalStart)
    )
    if feedTimeline.count > Self.maxFeedTimelineSegments {
      feedTimeline.removeFirst(feedTimeline.count - Self.maxFeedTimelineSegments)
    }
  }

  /// Transkript-Inhalt verwerfen und auf eine neue Position setzen (Watchdogs bleiben aus).
  /// Hält die Zeilen zeitlich sortiert — Voraussetzung für die Binärsuche in der Anzeige.
  private func reanchorTranscript(atGlobalTime globalTime: Double) {
    finalizedWords = []
    volatileTailWords = []
    lineAccumulator.reset()
    appendedThroughGlobalTime = 0
    lastAppendedThroughGlobalTime = 0
    lastObservedTranscriptionEnd = 0
    sessionFeedStartGlobalTime = globalTime
    teleprompterBufferingStartedAt = Date()
    words = []
    transcriptLines = []
    isTeleprompterReady = false
  }

  // MARK: - Audio-Feed

  private func continuousFeedLoop(targetFormat: AVAudioFormat, generation: UInt) async {
    runningFeedLoopGeneration = generation
    defer {
      if runningFeedLoopGeneration == generation { runningFeedLoopGeneration = nil }
    }
    do {
      try await runContinuousFeedLoop(targetFormat: targetFormat, generation: generation)
      DebugLogCollector.shared.log("readAlong feed loop ended cleanly")
    } catch {
      guard !AbstandErrorFilter.isBenignCancellation(error) else { return }
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      DebugLogCollector.shared.log("readAlong feed loop failed: \(message)")
      await failTeleprompterSession(message: message, generation: generation)
    }
  }

  /// Ein SpeechAnalyzer für alle Tracks — bei Kapitelwechsel nur die Quelldatei wechseln.
  private func runContinuousFeedLoop(targetFormat: AVAudioFormat, generation: UInt) async throws {
    while !Task.isCancelled, sessionIsCurrent(generation) {
      guard let player = boundPlayer else {
        try await Task.sleep(nanoseconds: 80_000_000)
        continue
      }

      let bookId = player.activeBook?.id
      if let bookId, let activeTranscriptionBookId, bookId != activeTranscriptionBookId {
        return
      }

      guard let context = await player.makeTranscriptionAudioContext() else {
        if audioContextUnavailableSince == nil {
          audioContextUnavailableSince = Date()
        } else if let since = audioContextUnavailableSince,
          Date().timeIntervalSince(since) >= Self.audioContextUnavailableSeconds
        {
          throw PlayerLiveTranscriptionError.audioSourceUnavailable
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        continue
      }
      audioContextUnavailableSince = nil

      guard let input = inputBuilder else { return }

      let trackKey = player.transcriptionTrackKey
      lastFeedTrackKey = trackKey
      let localStart = player.transcriptionLocalStartSeconds(preRoll: Self.preRollSeconds)
      if let active = activeContext {
        activeContext = PlayerTranscriptionAudioContext(
          assetURL: context.assetURL,
          streamAuthToken: context.streamAuthToken,
          trackGlobalOffset: context.trackGlobalOffset,
          locale: active.locale,
          trackIndex: context.trackIndex
        )
      }
      beginFeedSegment(globalStart: context.trackGlobalOffset + localStart)

      let trackGeneration = feedTrackGeneration
      let result = try await feedSingleTrack(
        context: context,
        expectedTrackKey: trackKey,
        localStartSeconds: localStart,
        targetFormat: targetFormat,
        input: input,
        generation: generation
      )
      guard sessionIsCurrent(generation) else { return }
      fedAnalyzerSeconds += result.fedAnalyzerSeconds
      DebugLogCollector.shared.log(
        "readAlong segment end outcome=\(result.outcome) track=\(trackKey) "
          + "fed=\(String(format: "%.1f", result.fedAnalyzerSeconds))s "
          + "progressEnd=\(String(format: "%.1f", transcriptionProgressEnd))"
      )

      switch result.outcome {
      case .trackChanged, .restartAtPlayback:
        // Bruchstelle im Audio: Stille nachschieben, damit der Analyzer das offene Segment
        // abschließt statt zwei unzusammenhängende Stellen zu einem Satz zu verkleben.
        yieldSilenceFlush(format: targetFormat)
        continue
      case .completed:
        yieldSilenceFlush(format: targetFormat)
        guard boundPlayer?.hasNextTranscriptionTrack == true else { return }
        try await waitForNextTrack(
          after: trackKey,
          trackGeneration: trackGeneration,
          generation: generation
        )
      }
    }
  }

  private func waitForNextTrack(
    after trackKey: String,
    trackGeneration: Int,
    generation: UInt
  ) async throws {
    while !Task.isCancelled, sessionIsCurrent(generation) {
      if feedTrackGeneration > trackGeneration { return }
      if let player = boundPlayer, player.transcriptionTrackKey != trackKey { return }
      // Selbstheilung muss auch hier greifen: der Reader kann eine Datei vorzeitig beenden,
      // während die Wiedergabe noch minutenlang im selben Track bleibt.
      if feedRestartRequested { return }
      try await Task.sleep(nanoseconds: 40_000_000)
    }
  }

  private func yieldSilenceFlush(format: AVAudioFormat) {
    guard let builder = inputBuilder else { return }
    let frames = AVAudioFrameCount(max(1, format.sampleRate * 0.35))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
    buffer.frameLength = frames
    if let channels = buffer.floatChannelData {
      for ch in 0..<Int(format.channelCount) {
        memset(channels[ch], 0, Int(frames) * MemoryLayout<Float>.size)
      }
    } else if let channels = buffer.int16ChannelData {
      for ch in 0..<Int(format.channelCount) {
        memset(channels[ch], 0, Int(frames) * MemoryLayout<Int16>.size)
      }
    }
    builder.yield(AnalyzerInput(buffer: buffer))
    fedAnalyzerSeconds += Double(frames) / format.sampleRate
  }

  /// `nonisolated`, damit Lesen und Konvertieren nicht auf dem MainActor laufen. Bewusst **kein**
  /// `Task.detached`: ein losgelöster Task erbt die Cancellation des Feed-Tasks nicht, und der
  /// Reader lief nach dem Abschalten bis zum Dateiende weiter — er verbrannte CPU und schrieb in
  /// die tote Session, während die nächste schon startete.
  private nonisolated func feedSingleTrack(
    context: PlayerTranscriptionAudioContext,
    expectedTrackKey: String,
    localStartSeconds: Double,
    targetFormat: AVAudioFormat,
    input: AsyncStream<AnalyzerInput>.Continuation,
    generation: UInt
  ) async throws -> TrackFeedResult {
    let streamToken = context.streamAuthToken
    let trackGlobalOffset = context.trackGlobalOffset

    let asset: AVURLAsset
    if let token = streamToken, !token.isEmpty {
      asset = AVURLAsset(url: context.assetURL, options: Self.streamHeaderOptions(token: token))
    } else {
      asset = AVURLAsset(url: context.assetURL)
    }

    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let audioTrack = tracks.first else {
      throw PlayerLiveTranscriptionError.audioSourceUnavailable
    }

    let reader = try AVAssetReader(asset: asset)
    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw PlayerLiveTranscriptionError.conversionFailed }
    reader.add(output)

    let startTime = CMTime(seconds: localStartSeconds, preferredTimescale: 600)
    reader.timeRange = CMTimeRange(start: startTime, duration: .positiveInfinity)
    guard reader.startReading() else {
      throw reader.error ?? PlayerLiveTranscriptionError.audioSourceUnavailable
    }
    // Nach dem Abbruch nicht weiterlesen — sonst bleibt der Reader an der Datei hängen.
    defer { if reader.status == .reading { reader.cancelReading() } }

    var fedLocalSeconds = localStartSeconds
    var fedAnalyzerSeconds: Double = 0
    var audioConverter: PlayerTranscriptionAudioConverter?

    func result(_ outcome: TrackFeedOutcome) -> TrackFeedResult {
      TrackFeedResult(outcome: outcome, fedAnalyzerSeconds: fedAnalyzerSeconds)
    }

    while reader.status == .reading, !Task.isCancelled {
      switch await nextFeedStep(
        expectedTrackKey: expectedTrackKey,
        fedLocalSeconds: fedLocalSeconds,
        trackGlobalOffset: trackGlobalOffset,
        generation: generation
      ) {
      case .trackChanged:
        return result(.trackChanged)
      case .restartAtPlayback:
        return result(.restartAtPlayback)
      case .wait(let nanoseconds):
        try await Task.sleep(nanoseconds: nanoseconds)
        continue
      case .feed:
        break
      }

      // Mehrere Buffer pro Prüfung: jeder MainActor-Hop konkurriert mit dem
      // Teleprompter-Rendering, und der Vorlauf ist mit 120 s grob genug dafür.
      for _ in 0..<Self.feedBuffersPerStateCheck {
        guard reader.status == .reading, !Task.isCancelled else { break }
        guard let sample = output.copyNextSampleBuffer() else {
          if reader.status == .completed { return result(.completed) }
          try await Task.sleep(nanoseconds: 50_000_000)
          break
        }

        guard let buffer = Self.sampleBufferToPCMBuffer(sample) else { continue }
        if audioConverter == nil {
          audioConverter = PlayerTranscriptionAudioConverter(
            sourceFormat: buffer.format,
            targetFormat: targetFormat
          )
        }
        guard let converter = audioConverter else {
          throw PlayerLiveTranscriptionError.conversionFailed
        }
        let converted = try converter.convert(buffer, to: targetFormat)
        // `AsyncStream.Continuation` ist thread-safe — kein Umweg über den MainActor.
        input.yield(AnalyzerInput(buffer: converted))
        fedAnalyzerSeconds += Double(converted.frameLength) / targetFormat.sampleRate

        let dur = CMSampleBufferGetDuration(sample).seconds
        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        if pts.isFinite { fedLocalSeconds = pts + (dur.isFinite ? dur : 0) }
      }
      await Task.yield()
    }

    if Task.isCancelled { throw CancellationError() }
    return result(reader.status == .completed ? .completed : .trackChanged)
  }

  /// Gefüttertes, aber noch nicht transkribiertes Audio. Bezugspunkt ist der Beginn des
  /// aktuellen Feed-Segments, solange von dort noch kein Ergebnis vorliegt.
  private func analyzerBacklogSeconds(
    fedLocalSeconds: Double,
    trackGlobalOffset: Double
  ) -> Double {
    let feedStart = feedTimeline.last?.globalStart ?? sessionFeedStartGlobalTime
    let transcribedThrough = max(transcriptionProgressEnd, feedStart)
    return trackGlobalOffset + fedLocalSeconds - transcribedThrough
  }

  /// Track-Wechsel, Sprungerkennung, Gegendruck und Vorlauf-Drossel in einem MainActor-Hop.
  private func nextFeedStep(
    expectedTrackKey: String,
    fedLocalSeconds: Double,
    trackGlobalOffset: Double,
    generation: UInt
  ) -> FeedStep {
    // Veraltete Generation: der Feed gehört zu einer abgeschalteten Session und hört hier auf.
    guard sessionIsCurrent(generation) else { return .trackChanged }
    if feedRestartRequested {
      feedRestartRequested = false
      return .restartAtPlayback
    }
    guard let player = boundPlayer else { return .wait(nanoseconds: 80_000_000) }
    guard player.transcriptionTrackKey == expectedTrackKey else { return .trackChanged }

    let playbackLocal = player.transcriptionLocalPlaybackSeconds(trackGlobalOffset: trackGlobalOffset)
    // Weit vorausgesprungen: übersprungenes Audio nicht erst durch den Analyzer schieben.
    if playbackLocal - fedLocalSeconds > Self.feedReseekLagSeconds { return .restartAtPlayback }

    // Gegendruck vor allen anderen Regeln: der Analyzer ist die langsamste Stufe und darf
    // nicht überfüllt werden — auch nicht in der Pufferphase oder beim Aufholen.
    if analyzerBacklogSeconds(fedLocalSeconds: fedLocalSeconds, trackGlobalOffset: trackGlobalOffset)
      > Self.maxAnalyzerBacklogSeconds
    {
      return .wait(nanoseconds: 100_000_000)
    }

    // Hinter der Wiedergabe bzw. noch im Aufbau: ohne Drossel, damit Speech aufholt.
    let lag = player.liveGlobalPlaybackPosition - transcriptionProgressEnd
    if lag > Self.transcriptionCatchUpLagSeconds { return .feed }
    if !isTeleprompterReady { return .feed }

    let lead = fedLocalSeconds - playbackLocal
    guard lead > Self.preRollSeconds + Self.leadBufferSeconds else { return .feed }
    return .wait(nanoseconds: player.isPlaying ? 200_000_000 : 400_000_000)
  }

  private nonisolated static func streamHeaderOptions(token: String) -> [String: Any] {
    AbstandHTTPSession.authorizedAssetHeaders(token: token)
  }

  private nonisolated static func sampleBufferToPCMBuffer(_ sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let desc = CMSampleBufferGetFormatDescription(sample) else { return nil }
    guard let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return nil }
    guard let format = AVAudioFormat(streamDescription: asbdPtr) else { return nil }
    let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
    buffer.frameLength = frameCount
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sample,
      at: 0,
      frameCount: Int32(frameCount),
      into: buffer.mutableAudioBufferList
    )
    guard status == noErr else { return nil }
    return buffer
  }
}
