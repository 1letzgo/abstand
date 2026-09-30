import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

// eBook-Index (Sätze und Wörter in Lesereihenfolge) für Teleprompter und Abgleich, dazu der Button im
// eBook-Reader, der zur Seite der aktuellen Hörposition springt und die letzten Wörter markiert.
// Die Stelle kommt aus dem Abgleich Transkript ↔ eBook (`EbookAudioAlignment.swift`).

// MARK: - Normalisierung

/// Vergleichbare Wortform für Transkript und eBook: klein, ohne Akzente, nur Buchstaben/Ziffern.
nonisolated enum ReadAlongText {
  static func normalize(_ token: some StringProtocol) -> String {
    let folded = token.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
    return String(String.UnicodeScalarView(scalars))
  }

  /// Wörter eines Satzes mit ihren Bereichen im Satztext.
  static func words(in text: String) -> [(word: String, range: Range<String.Index>)] {
    text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap { token in
      let word = normalize(token)
      return word.isEmpty ? nil : (word, token.startIndex..<token.endIndex)
    }
  }

  static func trigramKey(_ a: String, _ b: String, _ c: String) -> Int {
    var hasher = Hasher()
    hasher.combine(a)
    hasher.combine(b)
    hasher.combine(c)
    return hasher.finalize()
  }
}

// MARK: - eBook-Index

/// Sätze und Wörter des eBooks in Lesereihenfolge, plus Trigramm-Index für den Abgleich.
nonisolated struct EbookReadAlongIndex: Sendable {
  struct Sentence: Sendable {
    let locator: Locator
  }

  struct Word: Sendable {
    let normalized: String
    let sentence: Int
    /// Originaltext dieses Worts inkl. folgender Satzzeichen/Leerzeichen (für die Anzeige —
    /// aneinandergereiht ergibt sich wieder der eBook-Text).
    let display: String
  }

  let sentences: [Sentence]
  let words: [Word]
  /// Trigramm (drei aufeinanderfolgende Wörter) → Wortpositionen des ersten Worts.
  let trigrams: [Int: [Int]]
  /// Wort-ID je eBook-Wort (Index in `vocabulary`) — schneller Vergleich im Abgleich.
  let ids: [Int32]
  let vocabulary: [String: Int32]

  var isEmpty: Bool { words.isEmpty }

  static let empty = EbookReadAlongIndex(sentences: [], words: [], trigrams: [:], ids: [], vocabulary: [:])

  /// Wörter eines Satzes (sie sind nach Satz sortiert → Binärsuche).
  func wordRange(ofSentence sentence: Int) -> Range<Int> {
    func firstWord(ofSentence target: Int) -> Int {
      var low = 0
      var high = words.count
      while low < high {
        let mid = (low + high) / 2
        if words[mid].sentence < target { low = mid + 1 } else { high = mid }
      }
      return low
    }
    return firstWord(ofSentence: sentence)..<firstWord(ofSentence: sentence + 1)
  }

  func sentenceIndex(forWord position: Int) -> Int? {
    guard words.indices.contains(position) else { return nil }
    return words[position].sentence
  }

  /// Baut den Index über Readiums Content-Iterator (Text-Elemente → Sätze → Wörter).
  static func build(publication: Publication) async -> EbookReadAlongIndex {
    guard let content = publication.content(from: nil) else {
      return .empty
    }
    let tokenizer = makeDefaultTextTokenizer(unit: .sentence, language: publication.metadata.language)
    var sentences: [Sentence] = []
    var words: [Word] = []

    for await element in content.sequence() {
      if Task.isCancelled { break }
      guard let text = element as? TextContentElement else { continue }
      for segment in text.segments {
        let segmentText = segment.text
        let ranges = (try? tokenizer(segmentText)) ?? [segmentText.startIndex..<segmentText.endIndex]
        for range in ranges {
          let sentenceText = String(segmentText[range])
          let tokens = ReadAlongText.words(in: sentenceText)
          guard !tokens.isEmpty else { continue }
          let sentenceIndex = sentences.count
          for (offset, token) in tokens.enumerated() {
            // Von Wortbeginn bis zum nächsten Wort (Satzzeichen hängen am Wort); das erste Wort
            // übernimmt führende Zeichen wie Anführungszeichen, das letzte den Satzrest.
            let start = offset == 0 ? sentenceText.startIndex : token.range.lowerBound
            let end = offset + 1 < tokens.count ? tokens[offset + 1].range.lowerBound : sentenceText.endIndex
            var display = String(sentenceText[start..<end])
            if offset + 1 == tokens.count, !(display.last?.isWhitespace ?? false) { display += " " }
            words.append(Word(normalized: token.word, sentence: sentenceIndex, display: display))
          }
          sentences.append(Sentence(locator: segment.locator.highlighting(range, in: segmentText)))
        }
      }
    }

    var trigrams: [Int: [Int]] = [:]
    if words.count >= 3 {
      for i in 0..<(words.count - 2) {
        let key = ReadAlongText.trigramKey(
          words[i].normalized, words[i + 1].normalized, words[i + 2].normalized)
        trigrams[key, default: []].append(i)
      }
    }
    var vocabulary: [String: Int32] = [:]
    var ids: [Int32] = []
    ids.reserveCapacity(words.count)
    for word in words {
      if let id = vocabulary[word.normalized] {
        ids.append(id)
      } else {
        let id = Int32(vocabulary.count)
        vocabulary[word.normalized] = id
        ids.append(id)
      }
    }
    return EbookReadAlongIndex(
      sentences: sentences, words: words, trigrams: trigrams, ids: ids, vocabulary: vocabulary)
  }
}

nonisolated private extension Locator {
  /// Locator auf genau diesen Satz (Readium findet ihn über Highlight + Kontext).
  func highlighting(_ range: Range<String.Index>, in text: String) -> Locator {
    let contextLength = 40
    return copy(text: {
      $0 = Locator.Text(
        after: String(text[range.upperBound...].prefix(contextLength)).nilIfEmptyString,
        before: String(text[..<range.lowerBound].suffix(contextLength)).nilIfEmptyString,
        highlight: String(text[range])
      )
    })
  }
}

nonisolated private extension String {
  var nilIfEmptyString: String? { isEmpty ? nil : self }
}


// MARK: - Sprung zur Hörposition

/// Button im eBook-Reader: springt zur Seite der aktuellen Hörposition und markiert die letzten Wörter
/// davor — „wo war ich?" auch bei pausiertem Hörbuch.
@MainActor
final class EbookNarrationJumpController: ObservableObject {
  @Published private(set) var isBusy = false
  /// Hinweis, wenn die Stelle nicht bestimmbar ist (Hörbuch nicht geladen, kein Transkript o. Ä.).
  @Published var notice: String?

  private let model: AppModel
  private let libraryItemId: String
  private weak var navigator: EPUBNavigatorViewController?
  private var index: EbookReadAlongIndex?
  private var locale: Locale?
  private var hasMarking = false
  private var lastProgrammaticNavigationAt: Date?

  private static let markingGroup = "abstand-recent-words"
  /// So viele der zuletzt gehörten Wörter werden markiert.
  private static let recentWordCount = 25

  init(model: AppModel, libraryItemId: String, navigator: EPUBNavigatorViewController) {
    self.model = model
    self.libraryItemId = libraryItemId
    self.navigator = navigator
  }

  /// Nur sinnvoll, wenn genau dieses Hörbuch im Player geladen ist.
  var isAvailable: Bool {
    model.player.activeBook?.id == libraryItemId && model.player.activePlaybackEpisodeId == nil
  }

  func jumpToNarration() {
    guard !isBusy, isAvailable, navigator != nil else { return }
    isBusy = true
    Task { [weak self] in
      guard let self else { return }
      notice = await performJump()
      isBusy = false
    }
  }

  /// Vom Reader bei jeder Positionsänderung: blättert der Nutzer selbst weiter, hat die Markierung
  /// ihren Zweck erfüllt.
  func readerLocationDidChange() {
    guard hasMarking else { return }
    if let at = lastProgrammaticNavigationAt, Date().timeIntervalSince(at) < 1.5 { return }
    clearMarking()
  }

  func stop() {
    clearMarking()
  }

  private func clearMarking() {
    guard hasMarking else { return }
    navigator?.apply(decorations: [], in: Self.markingGroup)
    hasMarking = false
  }

  /// `nil` bei Erfolg, sonst die Meldung für den Nutzer.
  private func performJump() async -> String? {
    guard model.player.isReadAlongDownloadReady else {
      return "Download the audiobook to jump to its position in the ebook."
    }
    guard let index = await ensureIndex(), !index.isEmpty else { return "The ebook couldn't be read." }
    guard let end = await narrationWord(index: index), let endSentence = index.sentenceIndex(forWord: end) else {
      model.transcriptPrefetcher.scheduleIfNeeded()
      return
        "This part of the audiobook can't be matched to the ebook yet. If its transcript is still being prepared, try again later."
    }
    let start = max(0, end - Self.recentWordCount + 1)
    guard let startSentence = index.sentenceIndex(forWord: start) else { return "The ebook couldn't be read." }

    var decorations: [Decoration] = []
    for sentence in startSentence...endSentence {
      let range = index.wordRange(ofSentence: sentence)
      let chunk = max(range.lowerBound, start)..<min(range.upperBound, end + 1)
      guard !chunk.isEmpty else { continue }
      decorations.append(
        Decoration(
          id: "recent-\(sentence)",
          locator: Self.chunkLocator(sentence: sentence, words: chunk, index: index),
          style: .highlight(tint: .systemYellow, isActive: false)))
    }
    guard let first = decorations.first, let navigator else { return "The ebook couldn't be read." }
    navigator.apply(decorations: decorations, in: Self.markingGroup)
    hasMarking = true
    lastProgrammaticNavigationAt = Date()
    _ = await navigator.go(to: first.locator, options: NavigatorGoOptions(animated: true))
    lastProgrammaticNavigationAt = Date()
    return nil
  }

  /// eBook-Index über den geteilten Provider — Teleprompter und Reader bauen ihn so nur einmal.
  private func ensureIndex() async -> EbookReadAlongIndex? {
    if let index { return index }
    let built = await TeleprompterEbookTextProvider.shared.index(
      forLibraryItemId: libraryItemId, model: model)
    index = built
    return built
  }

  /// eBook-Wort an der aktuellen Hörposition (Abgleich des laufenden Tracks).
  private func narrationWord(index: EbookReadAlongIndex) async -> Int? {
    let player = model.player
    if locale == nil {
      locale = (try? await SpeechTranscriptionLocaleResolver.resolve(
        preferredLanguageTag: player.preferredTranscriptionLanguageTag))?.locale
    }
    guard let locale, let bookId = player.transcriptionStorageId else { return nil }
    player.syncGlobalPositionFromPlayer()
    let position = player.liveGlobalPlaybackPosition
    guard let source = player.localTranscriptionTrackSources().first(where: { $0.globalRange.contains(position) }),
      let alignment = await EbookAlignmentStore.shared.alignment(
        forTrack: source.trackIndex, bookId: bookId, locale: locale, index: index, maxAge: 5)
    else { return nil }
    return alignment.ebookWord(atLocalTime: position - source.globalOffset)
  }

  /// Locator auf einen Wortbereich innerhalb eines Satzes: Satz-Locator mit Teilstring als Highlight,
  /// der restliche Satz dient als Kontext davor/danach (Readium sucht das Highlight über den Text).
  private static func chunkLocator(sentence: Int, words: Range<Int>, index: EbookReadAlongIndex) -> Locator {
    let base = index.sentences[sentence].locator
    let all = index.wordRange(ofSentence: sentence)
    let prefix = index.words[all.lowerBound..<words.lowerBound].map(\.display).joined()
    let suffix = index.words[words.upperBound..<all.upperBound].map(\.display).joined()
    let highlight = index.words[words].map(\.display).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    let contextLength = 40
    return base.copy(text: {
      $0 = Locator.Text(
        after: String((suffix + (base.text.after ?? "")).prefix(contextLength)).nilIfEmptyString,
        before: String(((base.text.before ?? "") + prefix).suffix(contextLength)).nilIfEmptyString,
        highlight: highlight
      )
    })
  }
}
