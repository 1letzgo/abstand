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
/// Stream — der Aufrufer startet den Bereich neu oder gibt auf.
actor PlayerTranscriptProducer {
  /// Audio in Blöcken lesen; nach jedem Block kurz kooperativ abgeben.
  private static let buffersPerYield = 64

  private var task: Task<Void, Never>?

  func cancel() {
    task?.cancel()
    task = nil
  }

  /// Transkribiert `[startSeconds, endSeconds)` der Datei und liefert Wort-Batches.
  /// Der Stream endet, wenn der Bereich fertig ist oder der Aufrufer ihn abbricht.
  nonisolated func transcribe(
    assetURL: URL,
    startSeconds: Double,
    endSeconds: Double?,
    locale: Locale
  ) -> AsyncThrowingStream<PlayerTranscriptProductionBatch, Error> {
    AsyncThrowingStream { continuation in
      let work = Task {
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

    let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
    try await analyzer.start(inputSequence: stream)

    // Ergebnisse einsammeln, während parallel gefüttert wird.
    let resultsTask = Task {
      for try await result in transcriber.results where result.isFinal {
        if Task.isCancelled { return }
        let words = Self.words(from: result.text, offset: startSeconds)
        guard !words.isEmpty else { continue }
        continuation.yield(
          PlayerTranscriptProductionBatch(
            words: words,
            processedThrough: words.last?.end ?? startSeconds,
            isFinalBatch: false
          )
        )
      }
    }

    do {
      let fedSeconds = try await feed(
        assetURL: assetURL,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        targetFormat: format,
        input: input
      )
      input.finish()
      // Ohne Finalisieren bleibt der letzte Satz im Analyzer hängen.
      try await analyzer.finalizeAndFinishThroughEndOfInput()
      _ = try await resultsTask.value
      continuation.yield(
        PlayerTranscriptProductionBatch(
          words: [],
          processedThrough: startSeconds + fedSeconds,
          isFinalBatch: true
        )
      )
    } catch {
      input.finish()
      resultsTask.cancel()
      try? await analyzer.cancelAndFinishNow()
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
    input: AsyncStream<AnalyzerInput>.Continuation
  ) async throws -> Double {
    let asset = AVURLAsset(url: assetURL)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let audioTrack = tracks.first else {
      throw PlayerTranscriptProducerError.audioUnavailable
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

    var converter: PlayerTranscriptionAudioConverter?
    var fedSeconds: Double = 0
    var sinceYield = 0

    while reader.status == .reading, !Task.isCancelled {
      guard let sample = output.copyNextSampleBuffer() else { break }
      guard let buffer = PlayerTranscriptProducer.pcmBuffer(from: sample) else { continue }
      if converter == nil {
        converter = PlayerTranscriptionAudioConverter(
          sourceFormat: buffer.format, targetFormat: targetFormat)
      }
      guard let converter else { throw PlayerTranscriptProducerError.conversionFailed }
      let converted = try converter.convert(buffer, to: targetFormat)
      input.yield(AnalyzerInput(buffer: converted))
      fedSeconds += Double(converted.frameLength) / targetFormat.sampleRate

      sinceYield += 1
      if sinceYield >= Self.buffersPerYield {
        sinceYield = 0
        await Task.yield()
      }
    }

    if Task.isCancelled { throw CancellationError() }
    return fedSeconds
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
      // Ein Run kann mehrere Wörter enthalten — Zeit gleichmäßig verteilen.
      let pieces = chunk.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
      guard pieces.count > 1 else {
        out.append(
          PlayerTranscriptProducedWord(
            text: chunk.trimmingCharacters(in: .whitespaces), start: start, end: end))
        continue
      }
      let span = max(0.01, end - start) / Double(pieces.count)
      for (i, piece) in pieces.enumerated() {
        let s = start + Double(i) * span
        out.append(PlayerTranscriptProducedWord(text: piece, start: s, end: s + span))
      }
    }
    return out
  }

  private nonisolated static func pcmBuffer(from sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let desc = CMSampleBufferGetFormatDescription(sample),
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
      let format = AVAudioFormat(streamDescription: asbd)
    else { return nil }
    let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
    else { return nil }
    buffer.frameLength = frames
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
    guard status == noErr else { return nil }
    return buffer
  }
}
