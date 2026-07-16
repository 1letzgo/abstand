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

  func sentence(atGlobalTime time: Double) -> AlignedSentence? {
    guard !sentences.isEmpty else { return nil }
    if let exact = sentences.first(where: { time >= $0.globalStart && time < $0.globalEnd }) {
      return exact
    }
    // Nach Seek / Lücken: nächster Satz ab der aktuellen Zeit, sonst letzter davor.
    if let next = sentences.first(where: { $0.globalStart >= time }) {
      return next
    }
    return sentences.last
  }

  func word(atGlobalTime time: Double, in sentence: AlignedSentence) -> AlignedWord? {
    guard !sentence.words.isEmpty else { return nil }
    if let exact = sentence.words.first(where: { time >= $0.globalStart && time < $0.globalEnd }) {
      return exact
    }
    if let next = sentence.words.first(where: { $0.globalStart >= time }) {
      return next
    }
    return sentence.words.last
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
