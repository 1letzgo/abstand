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

  /// Sprache der laufenden Transkription (für Wort-Übersetzung).
  var transcriptionLocale: Locale? { activeContext?.locale }
  /// Nur aktivierbar, wenn Apple Intelligence verfügbar ist und nicht bereits läuft.
  var canGenerateRecap: Bool { !isGeneratingRecap && SystemLanguageModel.default.availability == .available }

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
  /// Offset für Wort-Timestamps — pro Feed-Segment fix, bis späte Ergebnisse eingetroffen sind.
  private var wordsTimeOffset: Double = 0
  private var activeContext: PlayerTranscriptionAudioContext?

  private var transcriber: SpeechTranscriber?
  private var analyzer: SpeechAnalyzer?
  private var analyzerFormat: AVAudioFormat?
  private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
  private var resultsTask: Task<Void, Never>?
  private var feedTask: Task<Void, Never>?
  private var audioConverter: PlayerTranscriptionAudioConverter?

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
  /// Inkrementiert bei jedem Start — Tasks ignorieren veraltete Generationen.
  private var sessionGeneration: UInt = 0
  private var feedCooperativeCounter = 0
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

    if isTeleprompterModeActive || isEnabled {
      errorMessage = nil
      await disable()
      return
    }

    if isSessionBusy {
      await recoverFromStuckEnableAttempt()
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

  /// Vorheriger Enable-Task hängt — abbrechen, damit Start nicht still ignoriert wird.
  private func recoverFromStuckEnableAttempt() async {
    enableTask?.cancel()
    if let pendingEnable = enableTask {
      enableTask = nil
      await pendingEnable.value
    } else {
      enableTask = nil
    }
    stopSessionTask?.cancel()
    if let pendingStop = stopSessionTask {
      stopSessionTask = nil
      await pendingStop.value
    }
    isPreparing = false
    isSessionBusy = false
    if isTeleprompterModeActive {
      sessionGeneration &+= 1
      finishTeleprompterMode(resetContent: true)
      await stopSession()
    }
  }

  /// Teleprompter-Modus einschalten: UI sofort, Session asynchron starten.
  func startTeleprompterMode(player: PlaybackController) async {
    guard isReadAlongAvailable, player.isReadAlongDownloadReady else { return }

    resetZombieTeleprompterModeIfNeeded()

    guard !isTeleprompterModeActive, !isSessionBusy else { return }

    errorMessage = nil
    guard player.activeBook != nil else {
      errorMessage = PlayerLiveTranscriptionError.noActivePlayback.localizedDescription
      return
    }

    if let pendingStop = stopSessionTask {
      pendingStop.cancel()
      stopSessionTask = nil
      await pendingStop.value
    }

    sessionGeneration &+= 1
    let generation = sessionGeneration
    boundPlayer = player
    isTeleprompterModeActive = true
    applyTeleprompterSideEffects()

    enableTask?.cancel()
    enableTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.runEnableSession(player: player, generation: generation)
    }
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
    startupWatchdogTask?.cancel()
    startupWatchdogTask = nil
    progressStallWatchdogTask?.cancel()
    progressStallWatchdogTask = nil
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
      let recap = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      guard currentRecapGeneration == generation, isGeneratingRecap else { return }
      guard !recap.isEmpty else {
        recapErrorMessage = String(
          localized: "The summary could not be generated. Please try again.",
          comment: "Read along recap error"
        )
        return
      }
      recapText = recap
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

  func clearRecap() {
    recapText = nil
    recapErrorMessage = nil
    recapFallbackNotice = nil
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
    if resetError {
      errorMessage = nil
    }
    enableTask?.cancel()
    let pendingEnable = enableTask
    enableTask = nil
    if let pendingEnable {
      await pendingEnable.value
    }

    startupWatchdogTask?.cancel()
    startupWatchdogTask = nil
    progressStallWatchdogTask?.cancel()
    progressStallWatchdogTask = nil

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
    // Volatile Tail + Catch-up-Anzeige auch nach Ready aktualisieren.
    publishWords()
    if pendingStartupSyncTicks > 0 {
      pendingStartupSyncTicks -= 1
      syncTeleprompterToPlayback(at: player.liveGlobalPlaybackPosition, force: true)
    }
  }

  func playbackDidStop() {
    Task { @MainActor in
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

  private func startSession(player: PlaybackController, generation: UInt) async throws {
    guard sessionIsCurrent(generation) else { return }
    if let pendingStop = stopSessionTask {
      await pendingStop.value
    }
    try await ensureSpeechRecognitionAuthorized()
    guard sessionIsCurrent(generation) else { return }
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
    guard sessionIsCurrent(generation) else { return }
    resetTranscriptContent()
    feedTrackGeneration = 0
    feedCooperativeCounter = 0
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
    wordsTimeOffset = context.trackGlobalOffset + localStart
    publishWords()
    syncTeleprompterToPlayback(at: player.liveGlobalPlaybackPosition, force: true)
    feedTask = Task.detached(priority: .userInitiated) { [weak self] in
      await self?.continuousFeedLoop(targetFormat: format, generation: generation)
    }
  }

  private enum TrackFeedOutcome {
    case completed
    case trackChanged
  }

  private func stopSession() async {
    feedTask?.cancel()
    feedTask = nil
    resultsTask?.cancel()
    resultsTask = nil
    inputBuilder?.finish()
    inputBuilder = nil

    let analyzerToFinish = analyzer
    transcriber = nil
    analyzer = nil
    analyzerFormat = nil
    audioConverter = nil
    activeContext = nil
    wordsTimeOffset = 0

    if let analyzerToFinish {
      try? await analyzerToFinish.finalizeAndFinishThroughEndOfInput()
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

  private func consumeResults(from transcriber: SpeechTranscriber, generation: UInt) async {
    do {
      for try await result in transcriber.results {
        let stillCurrent = await MainActor.run { self.sessionIsCurrent(generation) }
        guard stillCurrent else { return }
        await MainActor.run {
          self.applyTranscriptionResult(result)
        }
      }
    } catch {
      guard !AbstandErrorFilter.isBenignCancellation(error) else { return }
      let message = error.localizedDescription
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
    publishWords()
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
    feedCooperativeCounter = 0
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
    let offset = wordsTimeOffset
    var out: [PlayerTranscriptWord] = []
    for run in text.runs {
      guard let tr = run.audioTimeRange else { continue }
      let start = offset + tr.start.seconds
      let end = offset + tr.end.seconds
      let chunk = String(text[run.range].characters)
      guard !chunk.isEmpty else { continue }
      out.append(contentsOf: splitIntoWords(chunk: chunk, start: start, end: end, isVolatile: isVolatile))
    }
    if out.isEmpty {
      let plain = String(text.characters)
      guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
      out.append(
        contentsOf: splitIntoWords(
          chunk: plain, start: offset, end: offset + 0.01, isVolatile: isVolatile))
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
    let closedLines = lineAccumulator.publishedLines().count
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
    let lines = transcriptLines
    if let idx = lines.firstIndex(where: { globalTime >= $0.globalStart && globalTime < $0.globalEnd }) {
      return activeWord(in: lines[idx], at: globalTime)
    }
    return nil
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

    for i in lines.indices {
      let line = lines[i]
      if globalTime < line.globalStart {
        return Double(i)
      }
      if globalTime < line.globalEnd {
        let span = line.globalEnd - line.globalStart
        let progress = span > 0 ? (globalTime - line.globalStart) / span : 0
        return Double(i) + progress
      }
    }

    return Double(lastIdx) + min(0.92, max(0, (globalTime - lines[lastIdx].globalEnd) / max(0.35, lines[lastIdx].globalEnd - lines[lastIdx].globalStart)))
  }

  private func activeLineIndex(in lines: [PlayerTranscriptLine], at globalTime: Double) -> Int {
    guard !lines.isEmpty else { return 0 }
    if let idx = lines.firstIndex(where: { globalTime >= $0.globalStart && globalTime < $0.globalEnd }) {
      return idx
    }
    if globalTime < lines[0].globalStart { return 0 }
    if let last = lines.indices.last, globalTime >= lines[last].globalEnd { return last }
    return lines.lastIndex(where: { $0.globalStart <= globalTime }) ?? 0
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

  // MARK: - Audio-Feed

  private func continuousFeedLoop(targetFormat: AVAudioFormat, generation: UInt) async {
    do {
      try await runContinuousFeedLoop(targetFormat: targetFormat, generation: generation)
    } catch {
      guard !AbstandErrorFilter.isBenignCancellation(error) else { return }
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

      let trackKey = player.transcriptionTrackKey
      lastFeedTrackKey = trackKey
      let localStart = player.transcriptionLocalStartSeconds(preRoll: Self.preRollSeconds)
      let feedOffset = context.trackGlobalOffset + localStart
      wordsTimeOffset = feedOffset
      if let active = activeContext {
        activeContext = PlayerTranscriptionAudioContext(
          assetURL: context.assetURL,
          streamAuthToken: context.streamAuthToken,
          trackGlobalOffset: context.trackGlobalOffset,
          locale: active.locale,
          trackIndex: context.trackIndex
        )
      }
      audioConverter = nil

      let generation = feedTrackGeneration
      let outcome = try await feedSingleTrack(
        context: context,
        expectedTrackKey: trackKey,
        localStartSeconds: localStart,
        targetFormat: targetFormat
      )

      switch outcome {
      case .trackChanged:
        continue
      case .completed:
        yieldSilenceFlush(format: targetFormat)
        guard boundPlayer?.hasNextTranscriptionTrack == true else { return }
        try await waitForNextTrack(after: trackKey, generation: generation)
      }
    }
  }

  private func waitForNextTrack(after trackKey: String, generation: Int) async throws {
    while !Task.isCancelled, isTeleprompterModeActive {
      if feedTrackGeneration > generation { return }
      if let player = boundPlayer, player.transcriptionTrackKey != trackKey { return }
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
  }

  private func feedSingleTrack(
    context: PlayerTranscriptionAudioContext,
    expectedTrackKey: String,
    localStartSeconds: Double,
    targetFormat: AVAudioFormat
  ) async throws -> TrackFeedOutcome {
    let assetURL = context.assetURL
    let streamToken = context.streamAuthToken
    let trackGlobalOffset = context.trackGlobalOffset

    return try await Task.detached(priority: .userInitiated) { [weak self] () async throws -> TrackFeedOutcome in
      guard let self else { return .trackChanged }

      let asset: AVURLAsset
      if let token = streamToken, !token.isEmpty {
        asset = AVURLAsset(url: assetURL, options: Self.streamHeaderOptions(token: token))
      } else {
        asset = AVURLAsset(url: assetURL)
      }

      let tracks = try await asset.loadTracks(withMediaType: .audio)
      guard let audioTrack = tracks.first else { throw PlayerLiveTranscriptionError.audioSourceUnavailable }

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

      var fedLocalSeconds = localStartSeconds
      var audioConverter: PlayerTranscriptionAudioConverter?
      var burstCount = 0

      while reader.status == .reading, !Task.isCancelled {
        burstCount += 1
        if burstCount & 15 == 0 {
          await Task.yield()
        }

        let trackChanged = await MainActor.run { () -> Bool in
          guard self.isTeleprompterModeActive else { return true }
          guard self.boundPlayer?.transcriptionTrackKey == expectedTrackKey else { return true }
          return false
        }
        if trackChanged { return .trackChanged }

        try await self.throttleFeed(
          fedLocalSeconds: fedLocalSeconds,
          trackGlobalOffset: trackGlobalOffset
        )

        guard let sample = output.copyNextSampleBuffer() else {
          if reader.status == .completed { return .completed }
          try await Task.sleep(nanoseconds: 50_000_000)
          continue
        }

        guard let buffer = Self.sampleBufferToPCMBuffer(sample) else { continue }
        if audioConverter == nil {
          audioConverter = PlayerTranscriptionAudioConverter(
            sourceFormat: buffer.format,
            targetFormat: targetFormat
          )
        }
        guard let converter = audioConverter else { throw PlayerLiveTranscriptionError.conversionFailed }
        let converted = try converter.convert(buffer, to: targetFormat)

        _ = await MainActor.run {
          self.inputBuilder?.yield(AnalyzerInput(buffer: converted))
        }

        let dur = CMSampleBufferGetDuration(sample).seconds
        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        if pts.isFinite { fedLocalSeconds = pts + (dur.isFinite ? dur : 0) }
      }

      return reader.status == .completed ? .completed : .trackChanged
    }.value
  }

  private func throttleFeed(fedLocalSeconds: Double, trackGlobalOffset: Double) async throws {
    let feedState = await MainActor.run { () -> (buffering: Bool, catchUp: Bool) in
      guard let player = self.boundPlayer else { return (true, false) }
      let playback = player.liveGlobalPlaybackPosition
      let lag = playback - self.transcriptionProgressEnd
      return (!self.isTeleprompterReady, lag > Self.transcriptionCatchUpLagSeconds)
    }

    // Hinter der Wiedergabe: Audio-Feed ohne Drossel, damit Speech aufholen kann.
    if feedState.catchUp { return }

    if feedState.buffering {
      feedCooperativeCounter += 1
      if feedCooperativeCounter % 16 == 0 {
        await Task.yield()
      }
      return
    }

    let maxLead = Self.preRollSeconds + Self.leadBufferSeconds
    while !Task.isCancelled {
      let playbackState = await MainActor.run { () -> (local: Double, playing: Bool, catchUp: Bool) in
        if let player = self.boundPlayer {
          let playback = player.liveGlobalPlaybackPosition
          let lag = playback - self.transcriptionProgressEnd
          return (
            player.transcriptionLocalPlaybackSeconds(trackGlobalOffset: trackGlobalOffset),
            player.isPlaying,
            lag > Self.transcriptionCatchUpLagSeconds
          )
        }
        return (0, false, false)
      }
      if playbackState.catchUp { return }
      let lead = fedLocalSeconds - playbackState.local
      if lead <= maxLead { break }
      let sleepNs: UInt64 =
        lead > maxLead * 0.85
          ? (playbackState.playing ? 100_000_000 : 60_000_000)
          : 25_000_000
      try await Task.sleep(nanoseconds: sleepNs)
    }
  }

  private nonisolated static func streamHeaderOptions(token: String) -> [String: Any] {
    ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
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
