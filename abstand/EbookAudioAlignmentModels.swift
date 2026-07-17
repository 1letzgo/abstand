import Foundation

/// Ein Wort innerhalb eines aligned Satzes (Zeiten global zum Hörbuch).
struct AlignedWord: Codable, Equatable, Identifiable, Sendable {
  var id: String { "\(sentenceId)-\(index)" }
  let sentenceId: String
  let index: Int
  let text: String
  let globalStart: Double
  let globalEnd: Double
}

/// Satz aus dem EPUB mit Audio-Zeitfenster.
struct AlignedSentence: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let href: String
  let chapterIndex: Int
  let sentenceIndex: Int
  let text: String
  let globalStart: Double
  let globalEnd: Double
  let words: [AlignedWord]

  var sentenceId: String { id }
}

/// Extrahierter EPUB-Satz vor dem Alignment (ohne Audiozeiten).
struct EbookExtractedSentence: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let href: String
  let chapterIndex: Int
  let sentenceIndex: Int
  let text: String
}

struct EbookExtractedChapter: Codable, Equatable, Identifiable, Sendable {
  var id: String { href }
  let href: String
  let chapterIndex: Int
  let title: String?
  let sentences: [EbookExtractedSentence]
}

/// Persistierte Alignment-Map für ein Library-Item.
struct EbookAudioAlignmentMap: Codable, Equatable, Sendable {
  let libraryItemId: String
  let ebookFileHash: String
  let audioFingerprint: String
  let createdAt: Date
  let localeIdentifier: String
  let sentences: [AlignedSentence]
  /// Abgedecktes Audio-Fenster (global, s). `nil` = Legacy-Vollbuch-Map.
  let coveredGlobalStart: Double?
  let coveredGlobalEnd: Double?

  enum CodingKeys: String, CodingKey {
    case libraryItemId, ebookFileHash, audioFingerprint, createdAt, localeIdentifier, sentences
    case coveredGlobalStart, coveredGlobalEnd
  }

  init(
    libraryItemId: String,
    ebookFileHash: String,
    audioFingerprint: String,
    createdAt: Date,
    localeIdentifier: String,
    sentences: [AlignedSentence],
    coveredGlobalStart: Double? = nil,
    coveredGlobalEnd: Double? = nil
  ) {
    self.libraryItemId = libraryItemId
    self.ebookFileHash = ebookFileHash
    self.audioFingerprint = audioFingerprint
    self.createdAt = createdAt
    self.localeIdentifier = localeIdentifier
    self.sentences = sentences
    self.coveredGlobalStart = coveredGlobalStart
    self.coveredGlobalEnd = coveredGlobalEnd
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    libraryItemId = try c.decode(String.self, forKey: .libraryItemId)
    ebookFileHash = try c.decode(String.self, forKey: .ebookFileHash)
    audioFingerprint = try c.decode(String.self, forKey: .audioFingerprint)
    createdAt = try c.decode(Date.self, forKey: .createdAt)
    localeIdentifier = try c.decode(String.self, forKey: .localeIdentifier)
    sentences = try c.decode([AlignedSentence].self, forKey: .sentences)
    coveredGlobalStart = try c.decodeIfPresent(Double.self, forKey: .coveredGlobalStart)
    coveredGlobalEnd = try c.decodeIfPresent(Double.self, forKey: .coveredGlobalEnd)
  }

  /// Ob die Map die Hörposition abdeckt (`slack` in Sekunden Toleranz am Rand).
  func covers(globalTime time: Double, slack: Double = 45) -> Bool {
    guard let start = coveredGlobalStart, let end = coveredGlobalEnd, end > start else {
      // Legacy ohne Fenster = ganzes Buch.
      return true
    }
    return time >= (start - slack) && time <= (end + slack)
  }

  func sentence(atGlobalTime time: Double) -> AlignedSentence? {
    guard !sentences.isEmpty else { return nil }
    // Satz erst kurz nach Speech-Start aktiv — sonst wirkt die Markierung vor der Tonspur.
    if let exact = sentences.first(where: {
      let dur = max(0.25, $0.globalEnd - $0.globalStart)
      let from = $0.globalStart + min(0.55, dur * 0.15)
      return time >= from && time < $0.globalEnd
    }) {
      return exact
    }
    // Außerhalb des abgedeckten Fensters: kein „letzter Satz“-Pin (sonst bleibt Highlight hängen).
    if let start = coveredGlobalStart, let end = coveredGlobalEnd, end > start,
      time < start - 45 || time > end + 45
    {
      return nil
    }
    // In Lücken / vor Aktiv-Punkt: vorherigen Satz halten.
    if let prev = sentences.last(where: {
      let dur = max(0.25, $0.globalEnd - $0.globalStart)
      return time >= $0.globalStart + min(0.55, dur * 0.15)
    }) {
      return prev
    }
    return sentences.first
  }

  /// Vereinigt zwei Fenster-Maps (für Nachladen während Sync).
  func merging(with other: EbookAudioAlignmentMap) -> EbookAudioAlignmentMap {
    var byId: [String: AlignedSentence] = Dictionary(
      uniqueKeysWithValues: sentences.map { ($0.id, $0) })
    for sentence in other.sentences {
      byId[sentence.id] = sentence
    }
    let merged = byId.values.sorted { $0.globalStart < $1.globalStart }
    let starts = [coveredGlobalStart, other.coveredGlobalStart].compactMap { $0 }
    let ends = [coveredGlobalEnd, other.coveredGlobalEnd].compactMap { $0 }
    return EbookAudioAlignmentMap(
      libraryItemId: libraryItemId,
      ebookFileHash: other.ebookFileHash.isEmpty ? ebookFileHash : other.ebookFileHash,
      audioFingerprint: other.audioFingerprint.isEmpty ? audioFingerprint : other.audioFingerprint,
      createdAt: max(createdAt, other.createdAt),
      localeIdentifier: other.localeIdentifier.isEmpty ? localeIdentifier : other.localeIdentifier,
      sentences: merged,
      coveredGlobalStart: starts.min(),
      coveredGlobalEnd: ends.max()
    )
  }

  func word(atGlobalTime time: Double, in sentence: AlignedSentence) -> AlignedWord? {
    guard !sentence.words.isEmpty else { return nil }
    // Wort erst ab ~35 % seiner Dauer als „aktuell“ werten — Startzeiten aus Speech sind früh.
    if let exact = sentence.words.first(where: {
      let dur = max(0.05, $0.globalEnd - $0.globalStart)
      let activeFrom = $0.globalStart + dur * 0.35
      return time >= activeFrom && time < $0.globalEnd
    }) {
      return exact
    }
    // Lücke / vor dem 35 %-Punkt: vorheriges Wort halten.
    if let prev = sentence.words.last(where: {
      let dur = max(0.05, $0.globalEnd - $0.globalStart)
      return time >= $0.globalStart + dur * 0.35
    }) {
      return prev
    }
    if let first = sentence.words.first, time < first.globalStart + max(0.05, first.globalEnd - first.globalStart) * 0.35 {
      return nil
    }
    return sentence.words.last
  }
}

/// Fenster um den Hörfortschritt für Prepare (statt Vollbuch-Transkription).
enum EbookSyncPrepWindow {
  /// ~5 % zurück, ~8 % voraus — mit Minuten-Mindestdauer und Cap.
  static func range(around anchor: Double, totalDuration: Double) -> ClosedRange<Double> {
    let total = max(1, totalDuration)
    let lookback = min(max(total * 0.05, 120), 12 * 60)
    let lookahead = min(max(total * 0.08, 180), 18 * 60)
    let start = max(0, anchor - lookback)
    var end = min(total, anchor + lookahead)
    if end - start < min(120, total) {
      end = min(total, start + min(total, 120))
    }
    return start...max(start + 1, end)
  }
}

enum EbookSyncError: LocalizedError {
  case speechUnavailable
  case speechRecognitionDenied
  case localeNotSupported
  case modelDownloadFailed
  case downloadRequired
  case epubRequired
  case ebookUnavailable
  case audioUnavailable
  case extractionFailed
  case alignmentFailed
  case conversionFailed

  var errorDescription: String? {
    switch self {
    case .speechUnavailable:
      return String(
        localized: "Ebook sync needs on-device speech recognition, which is not available on this device.",
        comment: "Ebook sync error")
    case .speechRecognitionDenied:
      return String(
        localized:
          "Speech recognition is not allowed. Enable it in Settings → Privacy & Security → Speech Recognition.",
        comment: "Ebook sync error")
    case .localeNotSupported:
      return String(
        localized:
          "Speech recognition is not available for this language on this device.",
        comment: "Ebook sync error")
    case .modelDownloadFailed:
      return String(
        localized: "Could not download the speech model. Check your connection and try again.",
        comment: "Ebook sync error")
    case .downloadRequired:
      return String(
        localized: "Download the audiobook and open the EPUB once to use ebook sync.",
        comment: "Ebook sync error")
    case .epubRequired:
      return String(
        localized: "Ebook sync requires an EPUB (PDF is not supported).",
        comment: "Ebook sync error")
    case .ebookUnavailable:
      return String(
        localized: "No local EPUB is available for this title.",
        comment: "Ebook sync error")
    case .audioUnavailable:
      return String(
        localized: "No local audiobook tracks are available for transcription.",
        comment: "Ebook sync error")
    case .extractionFailed:
      return String(
        localized: "Could not extract text from the EPUB.",
        comment: "Ebook sync error")
    case .alignmentFailed:
      return String(
        localized: "Could not align the audiobook with the EPUB text.",
        comment: "Ebook sync error")
    case .conversionFailed:
      return String(
        localized: "Audio could not be prepared for transcription.",
        comment: "Ebook sync error")
    }
  }
}
