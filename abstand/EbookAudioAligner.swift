import AVFoundation
import Foundation
import FoundationModels
import Speech

/// On-device Forced Alignment: SpeechTranscriber → Fuzzy-Match gegen EPUB-Sätze.
@MainActor
final class EbookAudioAligner {
  struct Progress: Equatable, Sendable {
    var fraction: Double
    var statusMessage: String
  }

  private var modelDownloadProgress: Double?

  func ensureSpeechAuthorized() async throws {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      return
    case .notDetermined:
      let status = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
      }
      guard status == .authorized else { throw EbookSyncError.speechRecognitionDenied }
    case .denied, .restricted:
      throw EbookSyncError.speechRecognitionDenied
    @unknown default:
      throw EbookSyncError.speechRecognitionDenied
    }
  }

  func ensureSpeechModel(locale: Locale, onProgress: ((Double?) -> Void)? = nil) async throws {
    let supported = await SpeechTranscriber.supportedLocales
    guard let installLocale = SpeechTranscriptionLocaleResolver.matchLocale(locale, in: supported)
    else {
      throw EbookSyncError.localeNotSupported
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
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
    guard let downloader = try await AssetInventory.assetInstallationRequest(supporting: [installerModule])
    else {
      throw EbookSyncError.modelDownloadFailed
    }
    modelDownloadProgress = 0
    onProgress?(0)
    let progress = downloader.progress
    let progressTask = Task { @MainActor in
      while !Task.isCancelled {
        let frac = progress.fractionCompleted
        self.modelDownloadProgress = frac
        onProgress?(frac)
        if progress.isFinished { break }
        try? await Task.sleep(nanoseconds: 120_000_000)
      }
    }
    do {
      try await downloader.downloadAndInstall()
      progressTask.cancel()
      modelDownloadProgress = nil
      onProgress?(nil)
    } catch {
      progressTask.cancel()
      modelDownloadProgress = nil
      onProgress?(nil)
      throw EbookSyncError.modelDownloadFailed
    }
  }

  /// Transkribiert lokale Tracks vollständig und aligned sie gegen EPUB-Sätze.
  func align(
    libraryItemId: String,
    ebookFileURL: URL,
    contexts: [PlayerTranscriptionAudioContext],
    preferredLanguageTag: String?,
    ebookFileHash: String,
    audioFingerprint: String,
    onProgress: @escaping @MainActor (Progress) -> Void
  ) async throws -> EbookAudioAlignmentMap {
    guard await SpeechTranscriberAvailability.isSupported() else {
      throw EbookSyncError.speechUnavailable
    }
    guard !contexts.isEmpty else { throw EbookSyncError.audioUnavailable }

    onProgress(Progress(fraction: 0.02, statusMessage: String(
      localized: "Extracting ebook text…", comment: "Ebook sync prep")))
    let chapters = try await EbookTextExtractor.extractChapters(from: ebookFileURL)
    let ebookSentences = chapters.flatMap(\.sentences)
    guard !ebookSentences.isEmpty else { throw EbookSyncError.extractionFailed }

    try await ensureSpeechAuthorized()
    let localeResolution = try await SpeechTranscriptionLocaleResolver.resolve(
      preferredLanguageTag: preferredLanguageTag
    )
    try await ensureSpeechModel(locale: localeResolution.locale) { frac in
      if let frac {
        onProgress(Progress(
          fraction: 0.05 + frac * 0.1,
          statusMessage: String(localized: "Downloading speech model…", comment: "Ebook sync prep")
        ))
      }
    }

    onProgress(Progress(fraction: 0.18, statusMessage: String(
      localized: "Transcribing audiobook…", comment: "Ebook sync prep")))
    let transcriptWords = try await transcribeAllTracks(
      contexts: contexts,
      locale: localeResolution.locale
    ) { trackFrac in
      onProgress(Progress(
        fraction: 0.18 + trackFrac * 0.55,
        statusMessage: String(localized: "Transcribing audiobook…", comment: "Ebook sync prep")
      ))
    }
    guard !transcriptWords.isEmpty else { throw EbookSyncError.alignmentFailed }

    onProgress(Progress(fraction: 0.78, statusMessage: String(
      localized: "Aligning text and audio…", comment: "Ebook sync prep")))
    var aligned = fuzzyAlign(
      ebookSentences: ebookSentences,
      transcriptWords: transcriptWords
    )

    if shouldTryLLMReanchor(aligned: aligned, ebookCount: ebookSentences.count) {
      onProgress(Progress(fraction: 0.9, statusMessage: String(
        localized: "Refining alignment…", comment: "Ebook sync prep")))
      if let refined = await llmReanchorIfNeeded(
        ebookSentences: ebookSentences,
        transcriptWords: transcriptWords,
        current: aligned
      ) {
        aligned = refined
      }
    }

    interpolateGaps(in: &aligned, transcriptEnd: transcriptWords.last?.globalEnd ?? 0)

    onProgress(Progress(fraction: 1, statusMessage: String(
      localized: "Alignment ready", comment: "Ebook sync prep")))

    return EbookAudioAlignmentMap(
      libraryItemId: libraryItemId,
      ebookFileHash: ebookFileHash,
      audioFingerprint: audioFingerprint,
      createdAt: Date(),
      localeIdentifier: localeResolution.locale.identifier(.bcp47),
      sentences: aligned
    )
  }

  // MARK: - Transcription

  private func transcribeAllTracks(
    contexts: [PlayerTranscriptionAudioContext],
    locale: Locale,
    onTrackProgress: @escaping @MainActor (Double) -> Void
  ) async throws -> [EbookAlignerTranscriptWord] {
    var all: [EbookAlignerTranscriptWord] = []
    let total = max(1, contexts.count)
    for (index, context) in contexts.enumerated() {
      let words = try await transcribeTrack(context: context, locale: locale)
      all.append(contentsOf: words)
      onTrackProgress(Double(index + 1) / Double(total))
      if Task.isCancelled { throw CancellationError() }
    }
    return all.sorted { $0.globalStart < $1.globalStart }
  }

  private func transcribeTrack(
    context: PlayerTranscriptionAudioContext,
    locale: Locale
  ) async throws -> [EbookAlignerTranscriptWord] {
    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    else {
      throw EbookSyncError.conversionFailed
    }

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    try await analyzer.start(inputSequence: stream)

    let collector = TranscriptWordCollector(offset: context.trackGlobalOffset)
    let resultTask = Task {
      for try await result in transcriber.results where result.isFinal {
        await collector.append(result.text)
      }
    }

    do {
      try await feedEntireTrack(context: context, targetFormat: format, input: continuation)
      continuation.finish()
      try await analyzer.finalizeAndFinishThroughEndOfInput()
      _ = try await resultTask.value
      return await collector.words()
    } catch {
      continuation.finish()
      resultTask.cancel()
      try? await analyzer.finalizeAndFinishThroughEndOfInput()
      throw error
    }
  }

  private func feedEntireTrack(
    context: PlayerTranscriptionAudioContext,
    targetFormat: AVAudioFormat,
    input: AsyncStream<AnalyzerInput>.Continuation
  ) async throws {
    let asset: AVURLAsset
    if let token = context.streamAuthToken, !token.isEmpty {
      asset = AVURLAsset(
        url: context.assetURL,
        options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
      )
    } else {
      asset = AVURLAsset(url: context.assetURL)
    }

    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let audioTrack = tracks.first else { throw EbookSyncError.audioUnavailable }

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
    guard reader.canAdd(output) else { throw EbookSyncError.conversionFailed }
    reader.add(output)
    guard reader.startReading() else {
      throw reader.error ?? EbookSyncError.audioUnavailable
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
      guard let converter else { throw EbookSyncError.conversionFailed }
      input.yield(AnalyzerInput(buffer: try converter.convert(buffer, to: targetFormat)))
      bufferCount += 1
      if bufferCount & 15 == 0 { await Task.yield() }
    }
    if Task.isCancelled { throw CancellationError() }
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

  // MARK: - Fuzzy alignment (Storyteller-style)

  private func fuzzyAlign(
    ebookSentences: [EbookExtractedSentence],
    transcriptWords: [EbookAlignerTranscriptWord]
  ) -> [AlignedSentence] {
    let transcriptTokens = transcriptWords.map(\.normalized).filter { !$0.isEmpty }
    guard !transcriptTokens.isEmpty else { return [] }

    var cursor = 0
    var aligned: [AlignedSentence] = []
    var missStreak = 0
    let windowBase = 40

    for sentence in ebookSentences {
      let sentenceTokens = EbookTextExtractor.tokens(from: sentence.text)
      guard !sentenceTokens.isEmpty else { continue }

      let window = max(windowBase, sentenceTokens.count * 4)
      let searchEnd = min(transcriptTokens.count, cursor + window)
      guard cursor < searchEnd else {
        missStreak += 1
        if missStreak >= 3 { cursor = min(transcriptTokens.count, cursor + sentenceTokens.count) }
        continue
      }

      if let match = bestWindowMatch(
        sentenceTokens: sentenceTokens,
        transcriptTokens: transcriptTokens,
        from: cursor,
        to: searchEnd
      ) {
        let startWord = transcriptWords[safe: match.start] ?? transcriptWords[cursor]
        let endIdx = min(transcriptWords.count - 1, match.end - 1)
        let endWord = transcriptWords[safe: endIdx] ?? startWord
        let words = interpolateWords(
          sentence: sentence,
          globalStart: startWord.globalStart,
          globalEnd: max(startWord.globalEnd, endWord.globalEnd)
        )
        aligned.append(
          AlignedSentence(
            id: sentence.id,
            href: sentence.href,
            chapterIndex: sentence.chapterIndex,
            sentenceIndex: sentence.sentenceIndex,
            text: sentence.text,
            globalStart: startWord.globalStart,
            globalEnd: max(startWord.globalEnd, endWord.globalEnd),
            words: words
          )
        )
        cursor = match.end
        missStreak = 0
      } else {
        missStreak += 1
        if missStreak >= 3 {
          // Storyteller: after consecutive misses, advance the window and retry later sentences.
          cursor = min(transcriptTokens.count, cursor + max(1, sentenceTokens.count / 2))
          missStreak = 0
        }
      }
    }
    return aligned
  }

  private func bestWindowMatch(
    sentenceTokens: [String],
    transcriptTokens: [String],
    from: Int,
    to: Int
  ) -> (start: Int, end: Int)? {
    let needleLen = sentenceTokens.count
    guard needleLen > 0, from < to else { return nil }
    let minLen = max(1, Int(Double(needleLen) * 0.7))
    let maxLen = min(to - from, Int(Double(needleLen) * 1.6) + 4)
    var bestScore = 0.0
    var best: (Int, Int)?

    for start in from ..< to {
      for len in minLen ... maxLen {
        let end = start + len
        guard end <= to else { break }
        let window = Array(transcriptTokens[start ..< end])
        let score = tokenOverlapScore(a: sentenceTokens, b: window)
        if score > bestScore {
          bestScore = score
          best = (start, end)
        }
      }
      // Cheap early exit when we already have a strong prefix match.
      if bestScore >= 0.92 { break }
    }

    // Threshold scales slightly with sentence length.
    let threshold = needleLen <= 4 ? 0.55 : 0.45
    guard let best, bestScore >= threshold else { return nil }
    return (best.0, best.1)
  }

  private func tokenOverlapScore(a: [String], b: [String]) -> Double {
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    let setB = Set(b)
    var hits = 0
    for token in a where setB.contains(token) { hits += 1 }
    let recall = Double(hits) / Double(a.count)
    let precision = Double(hits) / Double(max(1, b.count))
    // Favor ordered-ish matches via simple LCS ratio as a light tie-breaker.
    let lcs = Double(longestCommonSubsequence(a, b)) / Double(max(a.count, b.count))
    return recall * 0.55 + precision * 0.2 + lcs * 0.25
  }

  private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> Int {
    if a.isEmpty || b.isEmpty { return 0 }
    // Bounded DP for short windows.
    let n = a.count
    let m = b.count
    if n * m > 8_000 {
      // Fallback: count sequential greedy matches.
      var i = 0
      var j = 0
      var count = 0
      while i < n, j < m {
        if a[i] == b[j] {
          count += 1
          i += 1
          j += 1
        } else {
          j += 1
        }
      }
      return count
    }
    var prev = Array(repeating: 0, count: m + 1)
    var cur = Array(repeating: 0, count: m + 1)
    for i in 1 ... n {
      for j in 1 ... m {
        if a[i - 1] == b[j - 1] {
          cur[j] = prev[j - 1] + 1
        } else {
          cur[j] = max(prev[j], cur[j - 1])
        }
      }
      prev = cur
      cur = Array(repeating: 0, count: m + 1)
    }
    return prev[m]
  }

  private func interpolateWords(
    sentence: EbookExtractedSentence,
    globalStart: Double,
    globalEnd: Double
  ) -> [AlignedWord] {
    let rawTokens = sentence.text.split(whereSeparator: \.isWhitespace).map(String.init)
    let spoken = rawTokens.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard !spoken.isEmpty else { return [] }
    let duration = max(0.05, globalEnd - globalStart)
    return spoken.enumerated().map { index, token in
      let start = globalStart + duration * Double(index) / Double(spoken.count)
      let end = globalStart + duration * Double(index + 1) / Double(spoken.count)
      return AlignedWord(
        sentenceId: sentence.id,
        index: index,
        text: token,
        globalStart: start,
        globalEnd: end
      )
    }
  }

  private func interpolateGaps(in sentences: inout [AlignedSentence], transcriptEnd: Double) {
    guard sentences.count >= 2 else { return }
    sentences.sort { $0.globalStart < $1.globalStart }
    for i in 0 ..< (sentences.count - 1) {
      let current = sentences[i]
      let next = sentences[i + 1]
      if current.globalEnd > next.globalStart + 0.01 {
        let mid = (current.globalStart + next.globalStart) / 2
        sentences[i] = resized(current, end: max(current.globalStart + 0.05, mid))
        sentences[i + 1] = resized(next, start: sentences[i].globalEnd)
      }
    }
    if let last = sentences.last, last.globalEnd < transcriptEnd {
      sentences[sentences.count - 1] = resized(last, end: transcriptEnd)
    }
  }

  private func resized(_ sentence: AlignedSentence, start: Double? = nil, end: Double? = nil) -> AlignedSentence {
    let s = start ?? sentence.globalStart
    let e = end ?? sentence.globalEnd
    let words = interpolateWords(
      sentence: EbookExtractedSentence(
        id: sentence.id,
        href: sentence.href,
        chapterIndex: sentence.chapterIndex,
        sentenceIndex: sentence.sentenceIndex,
        text: sentence.text
      ),
      globalStart: s,
      globalEnd: max(s + 0.05, e)
    )
    return AlignedSentence(
      id: sentence.id,
      href: sentence.href,
      chapterIndex: sentence.chapterIndex,
      sentenceIndex: sentence.sentenceIndex,
      text: sentence.text,
      globalStart: s,
      globalEnd: max(s + 0.05, e),
      words: words
    )
  }

  // MARK: - FoundationModels re-anchor (coarse only)

  private func shouldTryLLMReanchor(aligned: [AlignedSentence], ebookCount: Int) -> Bool {
    guard ebookCount > 0 else { return false }
    let coverage = Double(aligned.count) / Double(ebookCount)
    guard coverage < 0.55 else { return false }
    return SystemLanguageModel.default.availability == .available
  }

  private func llmReanchorIfNeeded(
    ebookSentences: [EbookExtractedSentence],
    transcriptWords: [EbookAlignerTranscriptWord],
    current: [AlignedSentence]
  ) async -> [AlignedSentence]? {
    guard case .available = SystemLanguageModel.default.availability else { return nil }
    // Use a short transcript sample + first unmatched ebook paragraph candidates.
    let alignedIds = Set(current.map(\.id))
    let unmatched = ebookSentences.filter { !alignedIds.contains($0.id) }.prefix(8)
    guard !unmatched.isEmpty else { return nil }

    let sample = transcriptWords.prefix(120).map(\.text).joined(separator: " ")
    let candidates = unmatched.enumerated().map { idx, s in
      "\(idx + 1). \(s.text)"
    }.joined(separator: "\n")

    do {
      let session = LanguageModelSession(model: SystemLanguageModel.default)
      let response = try await session.respond(
        to: """
        You help align audiobook transcript text to ebook paragraphs.
        Pick the single best matching candidate number for where this transcript snippet begins.
        Reply with only the number.

        Transcript snippet:
        \(sample)

        Candidates:
        \(candidates)
        """
      )
      let digits = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        .filter(\.isNumber)
      guard let number = Int(digits), number >= 1, number <= unmatched.count else { return nil }
      let chosen = Array(unmatched)[number - 1]
      // Re-run fuzzy align starting conceptually near the chosen sentence by
      // stitching: keep current matches, then fuzzy-align from chosen onward.
      guard let chosenIndex = ebookSentences.firstIndex(where: { $0.id == chosen.id }) else {
        return nil
      }
      let tail = Array(ebookSentences[chosenIndex...])
      let tailAligned = fuzzyAlign(ebookSentences: tail, transcriptWords: transcriptWords)
      var merged = current
      let existing = Set(merged.map(\.id))
      for sentence in tailAligned where !existing.contains(sentence.id) {
        merged.append(sentence)
      }
      return merged.sorted { $0.globalStart < $1.globalStart }
    } catch {
      return nil
    }
  }
}

// MARK: - Collectors

fileprivate struct EbookAlignerTranscriptWord: Sendable {
  let text: String
  let normalized: String
  let globalStart: Double
  let globalEnd: Double
}

private actor TranscriptWordCollector {
  private let offset: Double
  private var collected: [EbookAlignerTranscriptWord] = []

  init(offset: Double) {
    self.offset = offset
  }

  func append(_ text: AttributedString) {
    for run in text.runs {
      guard let tr = run.audioTimeRange else { continue }
      let start = offset + tr.start.seconds
      let end = offset + tr.end.seconds
      let chunk = String(text[run.range].characters)
      collected.append(contentsOf: split(chunk: chunk, start: start, end: end))
    }
  }

  func words() -> [EbookAlignerTranscriptWord] { collected }

  private func split(chunk: String, start: Double, end: Double) -> [EbookAlignerTranscriptWord] {
    let tokens = chunk.split(whereSeparator: \.isWhitespace).map(String.init)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard !tokens.isEmpty else { return [] }
    let duration = max(0.01, end - start)
    return tokens.enumerated().map { index, token in
      let wStart = start + duration * Double(index) / Double(tokens.count)
      let wEnd = start + duration * Double(index + 1) / Double(tokens.count)
      return EbookAlignerTranscriptWord(
        text: token,
        normalized: EbookTextExtractor.normalizeForMatch(token),
        globalStart: wStart,
        globalEnd: wEnd
      )
    }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}
