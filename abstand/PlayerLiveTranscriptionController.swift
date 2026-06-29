import AVFoundation
import Combine
import Foundation
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
  /// Audio weit voraus transkribieren, damit Zeilen fertig sind bevor sie im Teleprompter erscheinen.
  static let leadBufferSeconds: Double = 120
  /// Mindestens so viele fertige Zeilen, bevor der Teleprompter sichtbar wird.
  static let minClosedLinesForDisplay = 4
  /// Mindestens so viel Audio (global, s) seit Feed-Start transkribiert.
  static let minTranscribedSecondsForDisplay: Double = 10
  /// Beim laufenden Play: Transkript darf höchstens so weit hinter der Wiedergabe liegen.
  static let maxPlaybackLagWhilePlaying: Double = 8
  /// Fallback: Spinner spätestens nach so vielen Sekunden aus, wenn Text da ist.
  static let teleprompterReadinessTimeoutSeconds: Double = 14
  /// Beim Start / Buchwechsel: „nah an Live“ erst nach kurzer Pufferphase erzwingen.
  static let teleprompterStartupGraceSeconds: Double = 35

  /// Nutzer hat Read-Along/Teleprompter eingeschaltet — steuert UI und Lebenszyklus.
  @Published private(set) var isTeleprompterModeActive = false
  @Published private(set) var isEnabled = false
  @Published private(set) var isPreparing = false
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

  /// Sprache der laufenden Transkription (für Wort-Übersetzung).
  var transcriptionLocale: Locale? { activeContext?.locale }

  private var finalizedWords: [PlayerTranscriptWord] = []
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
  private var feedCooperativeCounter = 0
  /// Aktives Buch zum Erkennen von Quellenwechseln.
  private var activeTranscriptionBookId: String?

  /// Vom Player bei Kapitel-/Track-Wechsel aufrufen (schneller Handoff).
  func notifyPlaybackTrackAdvanced() {
    feedTrackGeneration += 1
  }

  /// Vor `tearDownPlayer` / neuem Titel: Session beenden, Modus-UI bleibt an.
  func prepareForPlaybackHandoff() async {
    enableTask?.cancel()
    enableTask = nil
    setSessionRunning(false)
    isTeleprompterReady = false
    words = []
    resetTranscriptContent()
    activeTranscriptionBookId = nil
    stopSessionTask?.cancel()
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.stopSession()
    }
    stopSessionTask = task
    await task.value
    if stopSessionTask == task {
      stopSessionTask = nil
    }
  }

  /// Nach neuem Titel: Transkription neu starten, wenn Read-Along noch aktiv ist.
  func restartSessionForCurrentPlayback(player: PlaybackController) async {
    guard isTeleprompterModeActive else { return }
    guard isReadAlongAvailable, player.isReadAlongDownloadReady, player.activeBook != nil else {
      isTeleprompterReady = false
      return
    }
    boundPlayer = player
    enableTask?.cancel()
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.runEnableSession(player: player)
    }
    enableTask = task
    await task.value
    if enableTask == task {
      enableTask = nil
    }
  }

  func refreshReadAlongAvailability() async {
    isReadAlongAvailable = await SpeechTranscriberAvailability.isSupported()
  }

  func toggle(player: PlaybackController) async {
    guard isReadAlongAvailable, player.isReadAlongDownloadReady else { return }
    if isTeleprompterModeActive {
      disable()
      return
    }
    await startTeleprompterMode(player: player)
  }

  /// Teleprompter-Modus einschalten: UI sofort, Session asynchron starten.
  func startTeleprompterMode(player: PlaybackController) async {
    guard isReadAlongAvailable, player.isReadAlongDownloadReady else { return }
    guard !isTeleprompterModeActive else { return }

    errorMessage = nil
    guard player.activeBook != nil else {
      errorMessage = PlayerLiveTranscriptionError.noActivePlayback.localizedDescription
      return
    }

    boundPlayer = player
    isTeleprompterModeActive = true
    applyTeleprompterSideEffects()

    enableTask?.cancel()
    enableTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.runEnableSession(player: player)
    }
    // Nicht blockieren — Session startet im Hintergrund, UI bleibt responsiv.
  }

  private func runEnableSession(player: PlaybackController) async {
    isPreparing = true
    defer { isPreparing = false }

    do {
      try Task.checkCancellation()
      guard isTeleprompterModeActive else { return }

      player.syncGlobalPositionFromPlayer()
      try await startSession(player: player)

      try Task.checkCancellation()
      guard isTeleprompterModeActive else {
        stopSessionTask?.cancel()
        let stopTask = Task { @MainActor [weak self] in
          guard let self else { return }
          await self.stopSession()
        }
        stopSessionTask = stopTask
        await stopTask.value
        return
      }

      setSessionRunning(true)
      pendingStartupSyncTicks = 15
      syncTeleprompterToPlayback(at: player.liveGlobalPlaybackPosition, force: true)
    } catch {
      guard !Task.isCancelled, !AbstandErrorFilter.isBenignCancellation(error) else { return }
      guard isTeleprompterModeActive else { return }

      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      finishTeleprompterMode(resetContent: true)
      errorMessage = message
    }
  }

  func disable() {
    enableTask?.cancel()
    enableTask = nil

    if let player = boundPlayer {
      lastTeleprompterPlaybackTime = player.liveGlobalPlaybackPosition
    }
    finishTeleprompterMode(resetContent: true)
  }

  /// Modus beenden und Session aufräumen (idempotent).
  private func finishTeleprompterMode(resetContent: Bool) {
    let wasActive = isTeleprompterModeActive || isEnabled
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
    if wasActive {
      errorMessage = nil
    }
    stopSessionTask?.cancel()
    stopSessionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.stopSession()
    }
  }

  func handlePlaybackTick(player: PlaybackController) {
    guard isTeleprompterModeActive, isEnabled else { return }
    boundPlayer = player
    if !isTeleprompterReady {
      publishWords()
    }
    if pendingStartupSyncTicks > 0 {
      pendingStartupSyncTicks -= 1
      syncTeleprompterToPlayback(at: player.liveGlobalPlaybackPosition, force: true)
    }
  }

  func playbackDidStop() {
    if isTeleprompterModeActive { disable() }
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

  private func startSession(player: PlaybackController) async throws {
    if let pendingStop = stopSessionTask {
      await pendingStop.value
    }
    try await ensureSpeechRecognitionAuthorized()
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
    resetTranscriptContent()
    feedTrackGeneration = 0
    feedCooperativeCounter = 0
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
    let languageTag = player.activeBook?.media.metadata.language
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

    resultsTask = Task { [weak self] in
      await self?.consumeResults(from: speechTranscriber)
    }

    let localStart = player.transcriptionLocalStartSeconds(preRoll: Self.preRollSeconds)
    sessionFeedStartGlobalTime = context.trackGlobalOffset + localStart
    teleprompterBufferingStartedAt = Date()
    wordsTimeOffset = context.trackGlobalOffset + localStart
    publishWords()
    syncTeleprompterToPlayback(at: player.liveGlobalPlaybackPosition, force: true)
    feedTask = Task.detached(priority: .userInitiated) { [weak self] in
      await self?.continuousFeedLoop(targetFormat: format)
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

  private func consumeResults(from transcriber: SpeechTranscriber) async {
    do {
      for try await result in transcriber.results {
        await MainActor.run {
          self.applyTranscriptionResult(result)
        }
      }
    } catch {
      guard !AbstandErrorFilter.isBenignCancellation(error) else { return }
      await MainActor.run {
        if self.isTeleprompterModeActive {
          self.errorMessage = error.localizedDescription
        }
      }
    }
  }

  private func applyTranscriptionResult(_ result: SpeechTranscriber.Result) {
    guard result.isFinal else { return }
    applyFinalTranscriptionResult(result)
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
    }
    return out
  }

  private func resetTranscriptContent() {
    finalizedWords = []
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
    transcriptLines = isTeleprompterReady ? lineAccumulator.publishedLines() : []
  }

  /// Puffer prüfen: genug Zeilen + transkribierte Dauer (nicht „X s vor Live“, das klappt bei Play nicht).
  private func refreshTeleprompterReadiness() {
    guard isTeleprompterModeActive, let player = boundPlayer else {
      if isTeleprompterReady { isTeleprompterReady = false }
      return
    }

    let playback = player.liveGlobalPlaybackPosition
    let closedLines = lineAccumulator.publishedLines().count
    let transcribedSpan = max(0, appendedThroughGlobalTime - sessionFeedStartGlobalTime)
    let inStartupGrace: Bool = {
      guard let start = teleprompterBufferingStartedAt else { return true }
      return Date().timeIntervalSince(start) < Self.teleprompterStartupGraceSeconds
    }()
    let nearLiveWhilePlaying =
      !player.isPlaying
      || inStartupGrace
      || appendedThroughGlobalTime >= playback - Self.maxPlaybackLagWhilePlaying

    let hasMinimumContent =
      closedLines >= Self.minClosedLinesForDisplay
      && transcribedSpan >= Self.minTranscribedSecondsForDisplay
      && appendedThroughGlobalTime > 0.5

    let timedOut: Bool = {
      guard let start = teleprompterBufferingStartedAt else { return false }
      return Date().timeIntervalSince(start) >= Self.teleprompterReadinessTimeoutSeconds
    }()
    let fallbackReady =
      timedOut
      && closedLines >= max(2, Self.minClosedLinesForDisplay - 2)
      && appendedThroughGlobalTime > 0.5
      && transcribedSpan >= 2

    // Früher sichtbar: genug Text da, auch wenn Wiedergabe voraus ist (Scroll-Sync folgt nach).
    let earlyPartialReady =
      closedLines >= max(2, Self.minClosedLinesForDisplay - 1)
      && transcribedSpan >= 4
      && appendedThroughGlobalTime > 0.5

    let ready =
      (hasMinimumContent && (nearLiveWhilePlaying || earlyPartialReady))
      || fallbackReady

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

  private func continuousFeedLoop(targetFormat: AVAudioFormat) async {
    do {
      try await runContinuousFeedLoop(targetFormat: targetFormat)
    } catch {
      guard !AbstandErrorFilter.isBenignCancellation(error) else { return }
      await MainActor.run {
        if self.isTeleprompterModeActive {
          self.errorMessage = error.localizedDescription
        }
      }
    }
  }

  /// Ein SpeechAnalyzer für alle Tracks — bei Kapitelwechsel nur die Quelldatei wechseln.
  private func runContinuousFeedLoop(targetFormat: AVAudioFormat) async throws {
    while !Task.isCancelled, isTeleprompterModeActive {
      guard let player = boundPlayer else {
        try await Task.sleep(nanoseconds: 80_000_000)
        continue
      }

      let bookId = player.activeBook?.id
      if let bookId, let activeTranscriptionBookId, bookId != activeTranscriptionBookId {
        // Quelle gewechselt — Feed beenden; Neustart kommt von `playBook` / `restartSessionForCurrentPlayback`.
        return
      }

      guard let context = await player.makeTranscriptionAudioContext() else {
        try await Task.sleep(nanoseconds: 80_000_000)
        continue
      }

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
    let buffering = await MainActor.run { !self.isTeleprompterReady }
    if buffering {
      feedCooperativeCounter += 1
      if feedCooperativeCounter % 8 == 0 {
        await Task.yield()
        try await Task.sleep(nanoseconds: 8_000_000)
      }
      return
    }

    let maxLead = Self.preRollSeconds + Self.leadBufferSeconds
    while !Task.isCancelled {
      let playbackState = await MainActor.run { () -> (local: Double, playing: Bool) in
        if let player = self.boundPlayer {
          return (
            player.transcriptionLocalPlaybackSeconds(trackGlobalOffset: trackGlobalOffset),
            player.isPlaying
          )
        }
        return (0, false)
      }
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
