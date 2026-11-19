import AVFoundation
import Foundation
import Speech

/// Erzeugt Transkripte für einen Track-Bereich **so schnell das Gerät kann** — entkoppelt von der
/// Wiedergabe. Das ersetzt den früheren Live-Feed, der Audio im Abspieltakt nachschob und deshalb
/// nie Vorsprung aufbauen konnte (Drossel hing an der Ergebniszeit des Analyzers).
///
/// Ergebnisse kommen als Batches finalisierter Wörter mit **lokalen Track-Sekunden** heraus.
/// Wortanfänge nach Sprechpausen sind bereits auf den akustischen Einsatz gelegt
/// (`SpeechOnsetRefiner`). Der Aufrufer entscheidet, was er anzeigt und was er persistiert.
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
  /// Stream ohne finalen Batch beendet (weder fertig gefüttert noch als Fehler) — nie als „fertig" werten.
  case endedWithoutFinalBatch
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
  /// Bei Stille liefert die Erkennung keine Ergebnisse — kam so lange kein Ergebnis mehr, trotzdem
  /// ein Stück weiterfüttern, statt sich festzuwarten. Nur bei echter Ergebnis-Stille: eine bloß
  /// langsame Erkennung liefert weiter Ergebnisse und bremst damit das Füttern.
  private static let stallNudgeNanoseconds: UInt64 = 1_500_000_000
  /// Harte Grenze für den echten Vorsprung (gefüttert − Ende des letzten Ergebnisses), unabhängig
  /// vom Schub — sonst puffert der `AsyncStream` bei langsamer Erkennung unbegrenzt PCM.
  private static let maxTrueLeadSeconds: Double = 300
  /// Steht die harte Grenze und kommt so lange gar kein Ergebnis (minutenlange Musik/Stille), darf
  /// trotzdem ein Stück nachgeschoben werden — die Erkennung arbeitet Stille weit schneller als
  /// Echtzeit ab, der Puffer wächst dadurch nicht.
  private static let hardCapEscapeNanoseconds: UInt64 = 30_000_000_000
  private static let throttleSleepNanoseconds: UInt64 = 100_000_000

  /// Transkribiert `[startSeconds, endSeconds)` der Datei und liefert Wort-Batches.
  /// Der Stream endet, wenn der Bereich fertig ist oder der Aufrufer ihn abbricht.
  /// `priority`: Live `.userInitiated`, Vorproduktion im Hintergrund `.utility`.
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
    // Pegel des gefütterten Audios: Wortanfänge nach Sprechpausen auf den echten Einsatz legen.
    let envelope = SpeechEnvelopeTracker()

    // Ergebnisse einsammeln, während parallel gefüttert wird.
    let resultsTask = Task {
      var batcher = PlayerTranscriptRefinementBatcher()
      // Zurückgehaltenes Wort mit ausgeben (Ende des Laufs oder Abbruch) — kein Wortverlust.
      func flush() {
        let words = batcher.finish { envelope.refine($0, previous: $1) }
        guard let last = words.last else { return }
        continuation.yield(
          PlayerTranscriptProductionBatch(words: words, processedThrough: last.end, isFinalBatch: false))
      }
      do {
        for try await result in transcriber.results where result.isFinal {
          if Task.isCancelled { break }
          // Ergebnisse kommen erst nach dem ersten gefütterten Buffer — der Ursprung steht dann fest.
          let recognized = Self.words(from: result.text, offset: gate.timelineOrigin ?? startSeconds)
          gate.recordResult(end: recognized.last?.end)
          guard !recognized.isEmpty else { continue }
          // Das letzte Wort eines Ergebnisses bleibt bis zum nächsten zurück: erst dann ist bekannt,
          // ob dessen Einsatz nach einer Pause liegt — und das Wortende auf den Pausenbeginn gehört.
          let words = batcher.add(recognized) { envelope.refine($0, previous: $1) }
          guard let last = words.last else { continue }
          continuation.yield(
            PlayerTranscriptProductionBatch(words: words, processedThrough: last.end, isFinalBatch: false))
        }
        flush()
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
        gate: gate,
        envelope: envelope
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
    gate: FeedGate,
    envelope: SpeechEnvelopeTracker
  ) async throws -> Double {
    // Präzises Timing: bei VBR-MP3 schätzt AVFoundation die Startposition sonst aus der Bitrate
    // (Sekunden daneben). Der Producer liest nur lokale Dateien.
    let asset = AVURLAsset(url: assetURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let audioTrack = tracks.first else {
      throw PlayerTranscriptProducerError.audioUnavailable
    }

    let sourceFormat = await sourceFormatDescription(audioTrack)
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
      if gate.timelineOrigin == nil {
        // Ausgabe-PTS berücksichtigt `TrimDurationAtStart` (Encoder-Delay/Priming).
        let pts = CMSampleBufferGetOutputPresentationTimeStamp(sample)
        if pts.isValid, pts.isNumeric { origin = max(0, pts.seconds) }
        gate.setTimelineOrigin(origin)
        envelope.setOrigin(origin)
        // Nur Diagnose (Gerät 30–40 ms zu früh bei Einstieg mitten in eine MP3, am Mac nicht
        // nachstellbar): alles, was die Zeitachse des ersten Buffers bestimmt, in eine Zeile.
        let message = Self.timelineDiagnostics(
          requestedStart: startSeconds, origin: origin, firstSample: sample, sourceFormat: sourceFormat,
          usedBuffer: buffer)
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
      // Lückenlos füttern, ohne `bufferStartTime`: aus den Ausgabe-PTS abgeleitete Startzeiten
      // überlappen nach Resampling/Trimming um Bruchteile von Samples — der Analyzer bricht dann
      // mit „Audio input timestamp overlaps or precedes prior audio input" ab (am Mac nachgemessen).
      // Hüllkurve vor dem Füttern: ein Ergebnis kann nie Audio betreffen, das sie noch nicht kennt.
      envelope.append(analyzerBuffer)
      input.yield(AnalyzerInput(buffer: analyzerBuffer))
      fedSeconds += Double(analyzerBuffer.frameLength) / targetFormat.sampleRate

      sinceYield += 1
      if sinceYield >= Self.buffersPerYield {
        sinceYield = 0
        await Task.yield()
      }

      // Gegendruck: nicht mehr als `maxFeedLeadSeconds` vor der Erkennung. Echte Stille (seit
      // `stallNudge` kein Ergebnis) löst einen Schub aus, damit das Füttern nie ganz stehen bleibt —
      // aber nie über `maxTrueLeadSeconds` echten Vorsprung hinaus.
      while !Task.isCancelled {
        let fedThrough = origin + fedSeconds
        let softBlocked = fedThrough - gate.analyzedThrough > Self.maxFeedLeadSeconds
        let hardBlocked = fedThrough - gate.recognizedThrough > Self.maxTrueLeadSeconds
        guard softBlocked || hardBlocked else { break }
        if let failure = gate.failure { throw failure }
        try? await Task.sleep(nanoseconds: Self.throttleSleepNanoseconds)
        let silence = gate.nanosecondsSinceLastResult
        if hardBlocked {
          if silence >= Self.hardCapEscapeNanoseconds {
            gate.advanceRecognized(to: fedThrough - Self.maxFeedLeadSeconds / 2)
          }
        } else if silence >= Self.stallNudgeNanoseconds {
          gate.advance(to: fedThrough - Self.maxFeedLeadSeconds / 2)
        }
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

  /// Diagnosezeile zum ersten Ausgabe-Buffer: angeforderter Start, Ausgabe-PTS (= Zeitachsen-Ursprung),
  /// Dekodier-PTS, Trim-Werte (Encoder-Delay/Padding), Frames vor/nach dem Trimmen, Quell- und
  /// Ausgabeformat. Ändert nichts am Verhalten.
  private nonisolated static func timelineDiagnostics(
    requestedStart: Double,
    origin: Double,
    firstSample sample: CMSampleBuffer,
    sourceFormat: String,
    usedBuffer: AVAudioPCMBuffer
  ) -> String {
    func seconds(_ time: CMTime) -> String { time.isNumeric ? String(format: "%.4f", time.seconds) : "n/a" }
    func trim(_ key: CFString) -> String {
      guard let value = CMGetAttachment(sample, key: key, attachmentModeOut: nil),
        CFGetTypeID(value) == CFDictionaryGetTypeID()
      else { return "0" }
      return seconds(CMTimeMakeFromDictionary((value as! CFDictionary)))
    }
    return String(
      format:
        "transcript producer: start=%.4f firstPTS=%.4f delta=%+.4f decodePTS=%@ dur=%@ trimStart=%@ trimEnd=%@ frames=%ld used=%u src=[%@] out=%.0fHz ch=%u %@",
      requestedStart, origin, origin - requestedStart,
      seconds(CMSampleBufferGetPresentationTimeStamp(sample)),
      seconds(CMSampleBufferGetDuration(sample)),
      trim(kCMSampleBufferAttachmentKey_TrimDurationAtStart),
      trim(kCMSampleBufferAttachmentKey_TrimDurationAtEnd),
      CMSampleBufferGetNumSamples(sample), usedBuffer.frameLength, sourceFormat,
      usedBuffer.format.sampleRate, usedBuffer.format.channelCount,
      usedBuffer.format.commonFormat == .pcmFormatFloat32 ? "f32" : "i16")
  }

  /// Quellformat des Tracks für die Diagnosezeile (Codec, Rate, Kanäle, Frames je Paket).
  private nonisolated static func sourceFormatDescription(_ track: AVAssetTrack) async -> String {
    guard let description = try? await track.load(.formatDescriptions).first,
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
    else { return "?" }
    let code = asbd.mFormatID
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
    let fourCC = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
    return String(
      format: "%@ %.0fHz ch=%u fpp=%u", fourCC, asbd.mSampleRate, asbd.mChannelsPerFrame, asbd.mFramesPerPacket)
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
  /// Fortschritt inkl. Stille-Schub (weicher Gegendruck).
  private var value: Double
  /// Ende des letzten echten Ergebnisses (harte Grenze).
  private var recognized: Double
  private var lastResultAt = ContinuousClock.now
  private var origin: Double?
  private var error: Error?

  init(analyzedThrough: Double) {
    value = analyzedThrough
    recognized = analyzedThrough
  }

  /// Finales Ergebnis eingetroffen (auch ohne Wörter: die Erkennung arbeitet).
  func recordResult(end: Double?) {
    lock.lock()
    lastResultAt = ContinuousClock.now
    if let end {
      if end > value { value = end }
      if end > recognized { recognized = end }
    }
    lock.unlock()
  }

  var recognizedThrough: Double {
    lock.lock(); defer { lock.unlock() }
    return recognized
  }

  /// Nur für den Notausgang bei minutenlanger Stille an der harten Grenze.
  func advanceRecognized(to time: Double) {
    lock.lock()
    if time > recognized { recognized = time }
    if time > value { value = time }
    lastResultAt = ContinuousClock.now
    lock.unlock()
  }

  var nanosecondsSinceLastResult: UInt64 {
    lock.lock(); defer { lock.unlock() }
    let elapsed = ContinuousClock.now - lastResultAt
    let (seconds, attoseconds) = elapsed.components
    return UInt64(max(0, seconds)) * 1_000_000_000 + UInt64(max(0, attoseconds) / 1_000_000_000)
  }

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
