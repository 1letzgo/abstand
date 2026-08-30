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
  private let lineAccumulator = PlayerTranscriptLineAccumulator()
  /// Letztes Teleprompter-Layout für Reflow bei Schriftgrößenwechsel.
  private var teleprompterReflowFontSize: CGFloat = 0
  private var teleprompterReflowWidth: CGFloat = 0
  private var activeContext: PlayerTranscriptionAudioContext?



  /// Zwischenspeichern nach so vielen produzierten Audiosekunden.
  static let transcriptPersistIntervalSeconds: Double = 120
  /// So weit darf die Wiedergabe vor dem Produktionsstand liegen, bevor neu aufgesetzt wird.
  static let productionFollowToleranceSeconds: Double = 30

  /// Persistiertes Transkript des aktiven Tracks (Cache + frisch Produziertes).
  private var trackCache: PlayerTranscriptTrackCache?
  private var activeTrackKey: String?
  private var activeTrackDuration: Double = 0
  private var productionTask: Task<Void, Never>?
  private var isActivatingTrack = false
  /// Entwertet nach dem Cache-Load-await eine ältere, überholte Track-Aktivierung.
  private var trackActivationGeneration: UInt = 0
  private var productionStartLocalTime: Double = 0
  private var productionThroughLocalTime: Double = 0
  /// Läuft gerade eine Transkript-Produktion? (UI: „wird vorbereitet")
  @Published private(set) var isProducingTranscript = false


  private weak var boundPlayer: PlaybackController?

  /// Letzte Wiedergabezeit mit aktivem Teleprompter (für Start-Abgleich).
  private var lastTeleprompterPlaybackTime: Double = 0
  /// Erste Player-Ticks nach Enable: Position erneut syncen (Seek nach App-Start).
  private var pendingStartupSyncTicks = 0
  /// Laufender Start-Task — bei `disable()` abbrechen, damit kein Zombie-Session bleibt.
  private var enableTask: Task<Void, Never>?
  /// Wartet ggf. auf laufendes `stopSession()` — verhindert parallele SpeechAnalyzer.
  private var stopSessionTask: Task<Void, Never>?
  /// Inkrementiert bei jedem Start — Tasks ignorieren veraltete Generationen.
  private var sessionGeneration: UInt = 0
  /// Start-Absicht. `disable()` erhöht sie, damit `startTeleprompterMode` nach einem
  /// `await` nicht eine Session aufsetzt, die inzwischen beendet wurde.
  private var teleprompterIntentGeneration: UInt = 0
  /// Aktives Buch zum Erkennen von Quellenwechseln.
  private var activeTranscriptionBookId: String?

  /// Vom Player bei Kapitel-/Track-Wechsel aufrufen (schneller Handoff).
  func notifyPlaybackTrackAdvanced() {
    guard isTeleprompterModeActive, isEnabled, let player = boundPlayer else { return }
    followPlaybackPosition(player: player)
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


    setSessionRunning(false)

    stopSessionTask?.cancel()
    let pendingStop = stopSessionTask
    stopSessionTask = nil
    await pendingStop?.value

    await stopSession()
    resetTranscriptContent()
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

    let recapRange = max(0, end - 300)...end
    let sources = player.localTranscriptionTrackSources().filter {
      $0.globalRange.upperBound >= recapRange.lowerBound
        && $0.globalRange.lowerBound <= recapRange.upperBound
    }
    guard !sources.isEmpty else {
      recapText = nil
      recapErrorMessage = String(
        localized: "The last five minutes of audio are unavailable for transcription.",
        comment: "Read along recap error"
      )
      return
    }

    isGeneratingRecap = true
    PlayerTranscriptLibrary.beginPriorityWork()
    recapText = nil
    recapErrorMessage = nil
    recapFallbackNotice = nil
    recapShowsTranscript = false
    defer {
      isGeneratingRecap = false
      PlayerTranscriptLibrary.endPriorityWork()
    }

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

      // Read-Along-Cache mitbenutzen: Was der Teleprompter (oder die Vorproduktion) schon
      // transkribiert hat, wird gelesen statt erneut durch die Spracherkennung geschickt.
      let transcript = try await PlayerTranscriptLibrary.transcriptText(
        bookId: bookId ?? "",
        sources: sources,
        globalRange: recapRange,
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


    if let player = boundPlayer {
      lastTeleprompterPlaybackTime = player.liveGlobalPlaybackPosition
    }

    sessionGeneration &+= 1
    finishTeleprompterMode(resetContent: true)

    // Alten Stop-Lauf abwarten statt nur canceln — zwei überlappende `stopSession()`
    // räumen sich sonst gegenseitig `trackCache`/`activeContext` unter den Füßen weg.
    if let pendingStop = stopSessionTask {
      pendingStop.cancel()
      await pendingStop.value
    }
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
    // Track-Wechsel und Sprünge: Produktion an der neuen Stelle aufsetzen (Cache-Treffer sind gratis).
    followPlaybackPosition(player: player)
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

  // MARK: - Session: Cache laden, fehlende Strecke produzieren

  /// Kein Live-Feed mehr. Beim Start wird das Transkript des aktuellen Tracks aus dem
  /// persistenten Cache geladen; nur die noch nicht abgedeckte Strecke wird produziert —
  /// ungedrosselt und unabhängig von der Wiedergabe. Cache-Treffer heißt: sofort da,
  /// Sprünge kosten nichts, und der Text kann nicht mehr hinter dem Ton zurückfallen.
  private func startSession(player: PlaybackController, generation: UInt) async throws {
    guard sessionIsCurrent(generation) else { return }
    try await ensureSpeechRecognitionAuthorized()
    guard sessionIsCurrent(generation) else { return }

    resetTranscriptContent()
    boundPlayer = player
    activeTranscriptionBookId = player.activeBook?.id
    player.syncGlobalPositionFromPlayer()
    guard player.activeBook != nil else { throw PlayerLiveTranscriptionError.noActivePlayback }
    guard let context = await player.makeTranscriptionAudioContext() else {
      if player.isPlaybackFromOfflineDownload, !player.isUsingLocalTrackFiles {
        throw PlayerLiveTranscriptionError.streamingPlaybackUnavailable
      }
      if !player.canBuildTranscriptionStreamContext {
        throw PlayerLiveTranscriptionError.streamingPlaybackUnavailable
      }
      throw PlayerLiveTranscriptionError.audioSourceUnavailable
    }
    guard sessionIsCurrent(generation) else { return }

    let localeResolution = try await SpeechTranscriptionLocaleResolver.resolve(
      preferredLanguageTag: player.preferredTranscriptionLanguageTag
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

    try await ensureSpeechModel(locale: localeResolution.locale)
    guard sessionIsCurrent(generation) else { return }

    await activateTrack(
      context: PlayerTranscriptionAudioContext(
        assetURL: context.assetURL,
        streamAuthToken: context.streamAuthToken,
        trackGlobalOffset: context.trackGlobalOffset,
        locale: localeResolution.locale,
        trackIndex: context.trackIndex
      ),
      player: player,
      generation: generation
    )
  }

  /// Track wechseln oder erstmals aktivieren: Cache laden, anzeigen, Produktion anstoßen.
  private func activateTrack(
    context: PlayerTranscriptionAudioContext,
    player: PlaybackController,
    generation: UInt
  ) async {
    // Alten Produktions-Task erst abwarten: sein catch-Pfad persistiert noch — solange gehören
    // `activeContext`/`trackCache` dem alten Track. Ohne das Warten landeten dessen Wörter in
    // der Cache-Datei des neuen Tracks.
    if let running = productionTask {
      running.cancel()
      productionTask = nil
      await running.value
    }
    trackActivationGeneration &+= 1
    let activation = trackActivationGeneration

    let bookId = activeTranscriptionBookId ?? ""
    let localeId = context.locale.identifier(.bcp47)
    let trackKey = player.transcriptionTrackKey
    let trackDuration = player.currentTranscriptionTrackDuration
    // Datei-I/O und JSON-Dekodierung off-main — ein Track-Transkript ist schnell mehrere
    // hundert Kilobyte, und dieser Pfad läuft mitten in der Wiedergabe.
    let loaded = await PlayerTranscriptLibrary.cache(
      bookId: bookId, trackIndex: context.trackIndex, locale: context.locale)
    guard sessionIsCurrent(generation), trackActivationGeneration == activation else { return }
    // Kontext und Cache atomar setzen — vorher zeigt `followPlaybackPosition` noch auf den
    // alten Track und `covers()` rechnet nicht gegen die falsche Datei.
    activeContext = context
    activeTrackKey = trackKey
    activeTrackDuration = trackDuration
    finalizedWords = []
    lineAccumulator.reset()
    trackCache =
      loaded ?? PlayerTranscriptTrackCache(localeIdentifier: localeId, trackIndex: context.trackIndex)

    rebuildDisplayFromCache()
    let playbackLocal = player.transcriptionLocalPlaybackSeconds(
      trackGlobalOffset: context.trackGlobalOffset)
    startProduction(fromLocalTime: playbackLocal - Self.preRollSeconds, generation: generation)
    syncTeleprompterToPlayback(at: player.liveGlobalPlaybackPosition, force: true)
  }

  /// Gecachte Wörter (lokale Track-Zeit) in die Anzeige übernehmen (globale Hörbuchzeit).
  private func rebuildDisplayFromCache() {
    guard let cache = trackCache, let context = activeContext else {
      finalizedWords = []
      lineAccumulator.reset()
      publishWords()
      return
    }
    let offset = context.trackGlobalOffset
    finalizedWords = cache.allWords.enumerated().map { index, word in
      PlayerTranscriptWord(
        id: "c-\(context.trackIndex)-\(index)",
        text: word.t + " ",
        globalStart: offset + word.s,
        globalEnd: max(offset + word.s, offset + word.e),
        isVolatile: false
      )
    }
    lineAccumulator.rebuildLines(
      from: finalizedWords, maxCharactersPerLine: lineAccumulator.maxCharactersPerLine)
    publishWords()
  }

  /// Produktionslauf für die erste nicht abgedeckte Stelle ab `fromLocalTime`.
  /// Läuft bis zum Track-Ende durch — der Vorlauf ist damit nicht mehr begrenzt.
  private func startProduction(fromLocalTime requested: Double, generation: UInt) {
    guard let context = activeContext, let cache = trackCache else { return }
    guard
      let start = cache.firstUncoveredTime(
        from: max(0, requested), duration: activeTrackDuration)
    else {
      isProducingTranscript = false
      return
    }

    productionTask?.cancel()
    let assetURL = context.assetURL
    let locale = context.locale
    let trackIndex = context.trackIndex
    let bookId = activeTranscriptionBookId ?? ""
    productionStartLocalTime = start
    productionThroughLocalTime = start
    isProducingTranscript = true
    // Hintergrund-Vorproduktion pausiert, solange der Teleprompter selbst produziert.
    PlayerTranscriptLibrary.beginPriorityWork()

    productionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let producer = PlayerTranscriptProducer()
      var pending: [PlayerTranscriptTrackCache.Word] = []
      var lastPersistThrough = start
      // Lauf-lokales Ende: das geteilte `productionThroughLocalTime` gehört nach einem
      // Track-Wechsel schon dem neuen Lauf — der catch-Pfad hier muss mit dem eigenen
      // Stand persistieren, nicht mit dem des Nachfolgers.
      var through = start
      defer {
        PlayerTranscriptLibrary.endPriorityWork()
        if self.sessionIsCurrent(generation), self.activeContext?.trackIndex == trackIndex {
          self.isProducingTranscript = false
        }
      }

      do {
        for try await batch in producer.transcribe(
          assetURL: assetURL, startSeconds: start, endSeconds: nil, locale: locale)
        {
          guard self.sessionIsCurrent(generation),
            self.activeContext?.trackIndex == trackIndex,
            !Task.isCancelled
          else { break }

          if !batch.words.isEmpty {
            pending.append(
              contentsOf: batch.words.map {
                PlayerTranscriptTrackCache.Word(t: $0.text, s: $0.start, e: $0.end)
              })
            self.appendProducedWords(batch.words, trackIndex: trackIndex)
          }
          through = max(through, batch.processedThrough)
          self.productionThroughLocalTime = through

          // Zwischenspeichern: ein Absturz oder App-Wechsel soll die Rechenzeit nicht verlieren.
          if through - lastPersistThrough >= Self.transcriptPersistIntervalSeconds {
            lastPersistThrough = through
            await self.persistProducedSegment(
              start: start, end: through, words: pending, bookId: bookId,
              trackIndex: trackIndex, locale: locale)
          }
        }
        await self.persistProducedSegment(
          start: start, end: through, words: pending, bookId: bookId,
          trackIndex: trackIndex, locale: locale)
        // Lauf durch, aber kein einziges Wort — sonst bliebe die Karte dauerhaft im Ladezustand.
        if pending.isEmpty, self.transcriptLines.isEmpty, self.sessionIsCurrent(generation) {
          await self.failTeleprompterSession(.transcriptionProgressStalled, generation: generation)
        }
      } catch {
        // Auch bei Abbruch sichern — sonst ist die bereits verbrauchte Rechenzeit verloren.
        await self.persistProducedSegment(
          start: start, end: through, words: pending, bookId: bookId,
          trackIndex: trackIndex, locale: locale)
        guard !AbstandErrorFilter.isBenignCancellation(error) else { return }
        DebugLogCollector.shared.log(
          "readAlong production failed: \(error.localizedDescription)")
        // Nur melden, wenn nichts angezeigt werden kann — sonst läuft der Cache-Teil weiter.
        if self.transcriptLines.isEmpty, self.sessionIsCurrent(generation) {
          await self.failTeleprompterSession(
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
            generation: generation
          )
        }
      }
    }
  }

  /// Frisch produzierte Wörter anhängen (Normalfall: zeitlich hinter allem Bisherigen).
  private func appendProducedWords(_ words: [PlayerTranscriptProducedWord], trackIndex: Int) {
    guard let context = activeContext, context.trackIndex == trackIndex, !words.isEmpty else { return }
    let offset = context.trackGlobalOffset
    let tail = finalizedWords.last?.globalStart ?? -1
    let mapped = words.enumerated().map { index, word in
      PlayerTranscriptWord(
        id: "p-\(trackIndex)-\(Int((word.start * 1000).rounded()))-\(index)",
        text: word.text + " ",
        globalStart: offset + word.start,
        globalEnd: max(offset + word.start, offset + word.end),
        isVolatile: false
      )
    }
    guard let firstStart = mapped.first?.globalStart else { return }
    if firstStart > tail {
      // Normalfall: der Lauf produziert hinter allem bereits Angezeigten.
      finalizedWords.append(contentsOf: mapped)
      lineAccumulator.appendFinalizedWords(mapped)
    } else {
      // Der Cache enthält schon ein späteres Segment (z. B. früher gehörtes Kapitelende) —
      // dann muss einsortiert und neu umgebrochen werden statt angehängt.
      finalizedWords = Self.mergedByTime(finalizedWords + mapped)
      lineAccumulator.rebuildLines(
        from: finalizedWords, maxCharactersPerLine: lineAccumulator.maxCharactersPerLine)
    }
    publishWords()
  }

  /// Nach Startzeit sortieren und Wörter im selben Zeitfenster nur einmal behalten.
  private static func mergedByTime(_ words: [PlayerTranscriptWord]) -> [PlayerTranscriptWord] {
    let sorted = words.sorted { $0.globalStart < $1.globalStart }
    var out: [PlayerTranscriptWord] = []
    out.reserveCapacity(sorted.count)
    for word in sorted {
      if let last = out.last, abs(last.globalStart - word.globalStart) < 0.05, last.text == word.text {
        continue
      }
      out.append(word)
    }
    return out
  }

  /// Produzierten Bereich in den Cache legen und auf Platte schreiben.
  /// `trackIndex`/`locale` sind die beim **Produktionsstart** eingefangenen Werte — nicht
  /// `activeContext`, der bei einem Track-Wechsel bereits auf den neuen Track zeigen kann,
  /// während der gecancelte alte Lauf hier noch seinen Rest sichert.
  private func persistProducedSegment(
    start: Double,
    end: Double,
    words: [PlayerTranscriptTrackCache.Word],
    bookId: String,
    trackIndex: Int,
    locale: Locale
  ) async {
    guard end > start, !bookId.isEmpty else { return }
    // Frisch von Platte lesen statt den eigenen Stand fortzuschreiben: Recap und
    // Hintergrund-Vorproduktion schreiben in dieselbe Datei und dürfen sich nicht überschreiben.
    // Lesen, Einfügen und Schreiben laufen off-main (`PlayerTranscriptLibrary`).
    var cache =
      await PlayerTranscriptLibrary.cache(bookId: bookId, trackIndex: trackIndex, locale: locale)
      ?? PlayerTranscriptTrackCache(
        localeIdentifier: locale.identifier(.bcp47), trackIndex: trackIndex)
    cache.insert(
      segment: PlayerTranscriptTrackCache.Segment(start: start, end: end, words: words))
    // Anzeige-Cache nur fortschreiben, wenn der Track noch der aktive ist.
    if activeContext?.trackIndex == trackIndex {
      trackCache = cache
    }
    await PlayerTranscriptLibrary.save(cache, bookId: bookId)
  }

  /// Track-Wechsel und Sprünge: Produktion an der neuen Stelle aufsetzen.
  private func followPlaybackPosition(player: PlaybackController) {
    guard isTeleprompterModeActive, isEnabled, let context = activeContext else { return }
    let generation = sessionGeneration

    if player.transcriptionTrackKey != activeTrackKey {
      // Der Tick feuert mehrmals pro Sekunde; `activeTrackKey` steht erst nach dem `await`.
      guard !isActivatingTrack else { return }
      isActivatingTrack = true
      Task { @MainActor [weak self] in
        guard let self else { return }
        defer { self.isActivatingTrack = false }
        guard self.sessionIsCurrent(generation) else { return }
        guard let fresh = await player.makeTranscriptionAudioContext() else { return }
        guard self.sessionIsCurrent(generation) else { return }
        await self.activateTrack(
          context: PlayerTranscriptionAudioContext(
            assetURL: fresh.assetURL,
            streamAuthToken: fresh.streamAuthToken,
            trackGlobalOffset: fresh.trackGlobalOffset,
            locale: context.locale,
            trackIndex: fresh.trackIndex
          ),
          player: player,
          generation: generation
        )
      }
      return
    }

    let playbackLocal = player.transcriptionLocalPlaybackSeconds(
      trackGlobalOffset: context.trackGlobalOffset)
    guard let cache = trackCache else { return }
    if cache.covers(playbackLocal) { return }
    // Läuft die Produktion bereits auf diese Stelle zu, nicht neu aufsetzen.
    if isProducingTranscript,
      playbackLocal >= productionStartLocalTime - 1,
      playbackLocal <= productionThroughLocalTime + Self.productionFollowToleranceSeconds
    {
      return
    }
    startProduction(fromLocalTime: playbackLocal - Self.preRollSeconds, generation: generation)
  }

  /// Produktion stoppen und den bisher erzeugten Stand sichern.
  private func stopSession() async {
    let task = productionTask
    productionTask = nil
    task?.cancel()
    await task?.value
    isProducingTranscript = false
    trackCache = nil
    activeContext = nil
    activeTrackKey = nil
    productionStartLocalTime = 0
    productionThroughLocalTime = 0
  }

  /// Ende des vorliegenden Transkripts (globale Hörbuchzeit).
  private var transcriptionProgressEnd: Double {
    finalizedWords.last?.globalEnd ?? 0
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

  private func resetTranscriptContent() {
    finalizedWords = []
    lineAccumulator.reset()
    transcriptLines = []
    isTeleprompterReady = false
    teleprompterReflowFontSize = 0
    teleprompterReflowWidth = 0
  }



  /// `words` wird bewusst **nicht** mehr veröffentlicht: Die Views lesen ausschließlich
  /// `transcriptLines`. Die frühere Vollkopie des Wort-Arrays (bis 14.000 Einträge, bis zu
  /// zehnmal pro Sekunde) lief auf dem MainActor gegen das 60-fps-Rendering des Teleprompters.
  func publishWords() {
    transcriptLines = finalizedWords.isEmpty ? [] : lineAccumulator.publishedLines()
    refreshTeleprompterReadiness()
  }

  /// Bereit, sobald Text für die aktuelle Stelle vorliegt. Kein Zeilen- oder Sekundenkontingent
  /// mehr: bei einem Cache-Treffer ist das direkt beim Einschalten der Fall, und während der
  /// ersten Produktion genügt der erste Treffer am Abspielpunkt.
  private func refreshTeleprompterReadiness() {
    guard isTeleprompterModeActive, let player = boundPlayer else {
      if isTeleprompterReady { isTeleprompterReady = false }
      return
    }
    let playback = player.liveGlobalPlaybackPosition
    let lines = transcriptLines
    let ready =
      !lines.isEmpty
      && (transcriptionProgressEnd >= playback - 1
        || lines.contains { $0.globalStart <= playback && $0.globalEnd >= playback })

    guard ready != isTeleprompterReady else { return }
    isTeleprompterReady = ready
    if ready {
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

}
