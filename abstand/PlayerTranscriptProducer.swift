import AVFoundation
import Foundation
import Speech

/// Erzeugt Transkripte für einen Track-Bereich **so schnell das Gerät kann** — entkoppelt von der
/// Wiedergabe. Das ersetzt den früheren Live-Feed, der Audio im Abspieltakt nachschob und deshalb
/// nie Vorsprung aufbauen konnte (Drossel hing an der Ergebniszeit des Analyzers).
///
/// Ergebnisse kommen als Batches finalisierter Wörter mit **lokalen Track-Sekunden** heraus.
/// Der Aufrufer entscheidet, was er anzeigt und was er persistiert.
struct PlayerTranscriptProducedWord: Sendable {
  let text: String
  let start: Double
  let end: Double
}

struct PlayerTranscriptProductionBatch: Sendable {
  let words: [PlayerTranscriptProducedWord]
  /// Bis hierher (lokale Track-Sekunde) ist der Bereich abgearbeitet.
  let processedThrough: Double
  let isFinalBatch: Bool
}

enum PlayerTranscriptProducerError: Error {
  case audioUnavailable
  case conversionFailed
}

/// Ein Lauf = ein Track-Bereich. Kein Watchdog, kein Selbstheilen: bricht etwas ab, wirft der
/// Stream — der Aufrufer bricht über die Stream-Termination ab (kein eigener Zustand nötig,
/// deshalb enum statt actor).
enum PlayerTranscriptProducer {
  /// Audio in Blöcken lesen; nach jedem Block kurz kooperativ abgeben.
  private static let buffersPerYield = 64
  /// Wie weit (Audiosekunden) das Füttern der Erkennung vorauslaufen darf. Ohne Grenze landet bei
  /// langen Einzeldatei-Hörbüchern fast die ganze Datei als PCM im Speicher (GB-Bereich).
  private static let maxFeedLeadSeconds: Double = 120
  /// Bei Stille liefert die Erkennung keine Ergebnisse — dann nach dieser Wartezeit trotzdem
  /// ein Stück weiterfüttern, statt sich festzuwarten.
  private static let stallNudgeNanoseconds: UInt64 = 1_500_000_000
  private static let throttleSleepNanoseconds: UInt64 = 100_000_000

  /// Transkribiert `[startSeconds, endSeconds)` der Datei und liefert Wort-Batches.
  /// Der Stream endet, wenn der Bereich fertig ist oder der Aufrufer ihn abbricht.
  /// `priority`: Live/Recap `.userInitiated`, Vorproduktion im Hintergrund `.utility`.
  static func transcribe(
    assetURL: URL,
    startSeconds: Double,
    endSeconds: Double?,
    locale: Locale,
    priority: TaskPriority = .userInitiated
  ) -> AsyncThrowingStream<PlayerTranscriptProductionBatch, Error> {
    AsyncThrowingStream { continuation in
      let work = Task(priority: priority) {
        do {
          try await Self.run(
            assetURL: assetURL,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            locale: locale,
            continuation: continuation
          )
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in work.cancel() }
    }
  }

  private static func run(
    assetURL: URL,
    startSeconds: Double,
    endSeconds: Double?,
    locale: Locale,
    continuation: AsyncThrowingStream<PlayerTranscriptProductionBatch, Error>.Continuation
  ) async throws {
    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    else { throw PlayerTranscriptProducerError.conversionFailed }
    // Modell schon laden, während der Reader die Datei öffnet — sonst zahlt der erste Buffer die Ladezeit.
    try await analyzer.prepareToAnalyze(in: format)

    let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
    try await analyzer.start(inputSequence: stream)
    let gate = FeedGate(analyzedThrough: startSeconds)

    // Ergebnisse einsammeln, während parallel gefüttert wird.
    let resultsTask = Task {
      do {
        for try await result in transcriber.results where result.isFinal {
          if Task.isCancelled { return }
          // Ergebnisse kommen erst nach dem ersten gefütterten Buffer — der Ursprung steht dann fest.
          let words = Self.words(from: result.text, offset: gate.timelineOrigin ?? startSeconds)
          if let end = words.last?.end { gate.advance(to: end) }
          guard !words.isEmpty else { continue }
          continuation.yield(
            PlayerTranscriptProductionBatch(
              words: words,
              processedThrough: words.last?.end ?? (gate.timelineOrigin ?? startSeconds),
              isFinalBatch: false
            )
          )
        }
      } catch {
        // Fütter-Schleife sofort stoppen statt die restliche Datei ins Leere zu schieben.
        gate.fail(error)
        throw error
      }
    }

    do {
      let fedSeconds = try await feed(
        assetURL: assetURL,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        targetFormat: format,
        input: input,
        gate: gate
      )
      input.finish()
      // Ohne Finalisieren bleibt der letzte Satz im Analyzer hängen.
      try await analyzer.finalizeAndFinishThroughEndOfInput()
      _ = try await resultsTask.value
      continuation.yield(
        PlayerTranscriptProductionBatch(
          words: [],
          processedThrough: (gate.timelineOrigin ?? startSeconds) + fedSeconds,
          isFinalBatch: true
        )
      )
    } catch {
      input.finish()
      resultsTask.cancel()
      await analyzer.cancelAndFinishNow()
      throw error
    }
  }

  /// Liest die Datei ungedrosselt und schiebt konvertierte Buffer in den Analyzer.
  /// Rückgabe: tatsächlich gefütterte Audiosekunden.
  private static func feed(
    assetURL: URL,
    startSeconds: Double,
    endSeconds: Double?,
    targetFormat: AVAudioFormat,
    input: AsyncStream<AnalyzerInput>.Continuation,
    gate: FeedGate
  ) async throws -> Double {
    // Präzises Timing: bei VBR-MP3 schätzt AVFoundation die Startposition sonst aus der Bitrate
    // (Sekunden daneben). Der Producer liest nur lokale Dateien.
    let asset = AVURLAsset(url: assetURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let audioTrack = tracks.first else {
      throw PlayerTranscriptProducerError.audioUnavailable
    }

    let reader = try AVAssetReader(asset: asset)
    // Der Reader dekodiert direkt ins Analyzer-Format (Rate, Kanäle, Sampletyp) — keine
    // Zwischenstufe in Quellrate plus zweite Kopie durch einen Resampler.
    let isFloat = targetFormat.commonFormat == .pcmFormatFloat32
    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: targetFormat.sampleRate,
      AVNumberOfChannelsKey: targetFormat.channelCount,
      AVLinearPCMBitDepthKey: isFloat ? 32 : 16,
      AVLinearPCMIsFloatKey: isFloat,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: !targetFormat.isInterleaved,
    ]
    let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw PlayerTranscriptProducerError.conversionFailed }
    reader.add(output)

    let start = CMTime(seconds: max(0, startSeconds), preferredTimescale: 600)
    let duration: CMTime
    if let endSeconds, endSeconds > startSeconds {
      duration = CMTime(seconds: endSeconds - startSeconds, preferredTimescale: 600)
    } else {
      duration = .positiveInfinity
    }
    reader.timeRange = CMTimeRange(start: start, duration: duration)
    guard reader.startReading() else {
      throw reader.error ?? PlayerTranscriptProducerError.audioUnavailable
    }
    defer { if reader.status == .reading { reader.cancelReading() } }

    // Nur nötig, falls der Reader das Zielformat doch nicht exakt liefert (z. B. exotische Layouts).
    var converter: PlayerTranscriptionAudioConverter?
    var fedSeconds: Double = 0
    var sinceYield = 0
    // Zeitachse der Erkennung beginnt beim ersten gefütterten Sample — dessen tatsächlicher PTS
    // (nicht `startSeconds`: der Reader startet am Paket-/Frame-Raster, ggf. vor dem Ziel).
    var origin = startSeconds

    while reader.status == .reading, !Task.isCancelled {
      if let failure = gate.failure { throw failure }
      guard let sample = output.copyNextSampleBuffer() else { break }
      guard let buffer = PlayerTranscriptProducer.pcmBuffer(from: sample) else { continue }
      // Ausgabe-PTS berücksichtigt `TrimDurationAtStart` (Encoder-Delay/Priming).
      let pts = CMSampleBufferGetOutputPresentationTimeStamp(sample)
      let ptsSeconds: Double? = (pts.isValid && pts.isNumeric) ? max(0, pts.seconds) : nil
      if gate.timelineOrigin == nil {
        if let ptsSeconds { origin = ptsSeconds }
        gate.setTimelineOrigin(origin)
        let message = String(
          format: "transcript producer: start=%.3f firstPTS=%.3f delta=%+.3f",
          startSeconds, origin, origin - startSeconds)
        Task { @MainActor in DebugLogCollector.shared.log(message) }
      }
      let analyzerBuffer: AVAudioPCMBuffer
      if Self.matches(buffer.format, targetFormat) {
        analyzerBuffer = buffer
      } else {
        if converter == nil {
          converter = PlayerTranscriptionAudioConverter(
            sourceFormat: buffer.format, targetFormat: targetFormat)
        }
        guard let converter else { throw PlayerTranscriptProducerError.conversionFailed }
        analyzerBuffer = try converter.convert(buffer, to: targetFormat)
      }
      // Startzeit je Buffer mitgeben (relativ zum Ursprung): verworfene oder kürzere Buffer
      // verschieben so nicht mehr alle späteren Wortzeiten.
      let relativeStart = max(0, (ptsSeconds ?? (origin + fedSeconds)) - origin)
      input.yield(
        AnalyzerInput(
          buffer: analyzerBuffer,
          bufferStartTime: CMTime(seconds: relativeStart, preferredTimescale: 48_000)))
      fedSeconds = max(
        fedSeconds, relativeStart + Double(analyzerBuffer.frameLength) / targetFormat.sampleRate)

      sinceYield += 1
      if sinceYield >= Self.buffersPerYield {
        sinceYield = 0
        await Task.yield()
      }

      // Gegendruck: nicht mehr als `maxFeedLeadSeconds` vor der Erkennung. Stille (keine Ergebnisse)
      // löst nach `stallNudge` einen Schub aus, damit das Füttern nie ganz stehen bleibt.
      var waited: UInt64 = 0
      while origin + fedSeconds - gate.analyzedThrough > Self.maxFeedLeadSeconds,
        waited < Self.stallNudgeNanoseconds, !Task.isCancelled
      {
        try? await Task.sleep(nanoseconds: Self.throttleSleepNanoseconds)
        waited += Self.throttleSleepNanoseconds
      }
      if waited >= Self.stallNudgeNanoseconds {
        gate.advance(to: origin + fedSeconds - Self.maxFeedLeadSeconds / 2)
      }
    }

    if Task.isCancelled { throw CancellationError() }
    if let failure = gate.failure { throw failure }
    // Lesefehler (beschädigte Datei, entzogene Datei) nicht als „Track fertig" melden.
    if reader.status == .failed {
      throw reader.error ?? PlayerTranscriptProducerError.audioUnavailable
    }
    return fedSeconds
  }

  /// Reader-Ausgabe passt direkt zum Analyzer (Rate, Kanäle, Sampletyp, Anordnung).
  private nonisolated static func matches(_ a: AVAudioFormat, _ b: AVAudioFormat) -> Bool {
    a.sampleRate == b.sampleRate && a.channelCount == b.channelCount
      && a.commonFormat == b.commonFormat && a.isInterleaved == b.isInterleaved
  }

  private static func words(
    from text: AttributedString,
    offset: Double
  ) -> [PlayerTranscriptProducedWord] {
    var out: [PlayerTranscriptProducedWord] = []
    for run in text.runs {
      guard let range = run.audioTimeRange else { continue }
      let chunk = String(text[run.range].characters)
      guard !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
      let start = offset + range.start.seconds
      let end = max(start, offset + range.end.seconds)
      // Ein Run kann mehrere Wörter enthalten — Zeit nach Zeichenzahl verteilen (lange Wörter
      // dauern länger; gleichmäßig verteilt liefe die Markierung bei kurzen Wörtern hinterher).
      let pieces = chunk.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
      guard pieces.count > 1 else {
        out.append(
          PlayerTranscriptProducedWord(
            text: chunk.trimmingCharacters(in: .whitespaces), start: start, end: end))
        continue
      }
      let span = max(0.01, end - start)
      let weights = pieces.map { Double(max(1, $0.count)) }
      let total = weights.reduce(0, +)
      var cumulative = 0.0
      for (i, piece) in pieces.enumerated() {
        let s = start + span * cumulative / total
        cumulative += weights[i]
        out.append(PlayerTranscriptProducedWord(text: piece, start: s, end: start + span * cumulative / total))
      }
    }
    return out
  }

  private nonisolated static func pcmBuffer(from sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let desc = CMSampleBufferGetFormatDescription(sample),
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
      let format = AVAudioFormat(streamDescription: asbd)
    else { return nil }
    let total = CMSampleBufferGetNumSamples(sample)
    // Getrimmte Frames (Encoder-Delay am Anfang, Padding am Ende) gehören nicht zur Zeitachse.
    let trimStart = trimmedFrames(sample, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart, rate: format.sampleRate)
    let trimEnd = trimmedFrames(sample, key: kCMSampleBufferAttachmentKey_TrimDurationAtEnd, rate: format.sampleRate)
    let count = total - trimStart - trimEnd
    guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
    else { return nil }
    buffer.frameLength = AVAudioFrameCount(count)
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sample, at: Int32(trimStart), frameCount: Int32(count), into: buffer.mutableAudioBufferList)
    guard status == noErr else { return nil }
    return buffer
  }

  private nonisolated static func trimmedFrames(_ sample: CMSampleBuffer, key: CFString, rate: Double) -> Int {
    guard let value = CMGetAttachment(sample, key: key, attachmentModeOut: nil),
      CFGetTypeID(value) == CFDictionaryGetTypeID()
    else { return 0 }
    let time = CMTimeMakeFromDictionary((value as! CFDictionary))
    guard time.isValid, time.isNumeric, time.seconds > 0 else { return 0 }
    return Int((time.seconds * rate).rounded())
  }
}

/// Erkennungsfortschritt (Track-Sekunden), geteilt zwischen Ergebnis- und Fütter-Task.
private final class FeedGate: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Double
  private var origin: Double?
  private var error: Error?

  init(analyzedThrough: Double) { value = analyzedThrough }

  /// Track-Sekunde des ersten gefütterten Samples (Nullpunkt der Erkennungszeiten).
  var timelineOrigin: Double? {
    lock.lock(); defer { lock.unlock() }
    return origin
  }

  func setTimelineOrigin(_ time: Double) {
    lock.lock()
    origin = time
    lock.unlock()
  }

  var analyzedThrough: Double {
    lock.lock(); defer { lock.unlock() }
    return value
  }

  func advance(to time: Double) {
    lock.lock()
    if time > value { value = time }
    lock.unlock()
  }

  /// Fehler der Ergebnis-Seite — die Fütter-Schleife bricht daran ab.
  var failure: Error? {
    lock.lock(); defer { lock.unlock() }
    return error
  }

  func fail(_ failure: Error) {
    lock.lock()
    if error == nil { error = failure }
    lock.unlock()
  }
}
