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
  /// Je Wort-ID: einzige Position im eBook, -1 bei mehrfachem Vorkommen (seltene Wörter als Fixpunkte).
  let uniquePositions: [Int32]

  var isEmpty: Bool { words.isEmpty }

  static let empty = EbookReadAlongIndex(
    sentences: [], words: [], trigrams: [:], ids: [], vocabulary: [:], uniquePositions: [])

  func uniquePosition(ofWordId id: Int32) -> Int? {
    guard uniquePositions.indices.contains(Int(id)) else { return nil }
    let position = uniquePositions[Int(id)]
    return position >= 0 ? Int(position) : nil
  }

  /// Erstes eBook-Wort an einer Lese-Position. Mit Text (erstes sichtbares Element der Seite) wird
  /// dessen Wortfolge im Kapitel gesucht, sonst die Position anteilig über `progression` geschätzt.
  func wordPosition(for locator: Locator) -> Int? {
    guard !words.isEmpty else { return nil }
    let href = Self.resourcePath(locator.href.string)
    var lower: Int?
    var upper = 0
    for (i, sentence) in sentences.enumerated() where Self.resourcePath(sentence.locator.href.string) == href {
      if lower == nil { lower = i }
      upper = i + 1
    }
    guard let lower else {
      let fraction = locator.locations.totalProgression ?? 0
      return min(words.count - 1, max(0, Int(fraction * Double(words.count))))
    }
    let first = wordRange(ofSentence: lower).lowerBound
    let end = wordRange(ofSentence: upper - 1).upperBound
    guard first < end else { return nil }

    if let text = locator.text.highlight, let match = wordSequence(ReadAlongText.words(in: text).map(\.word), in: first..<end) {
      return match
    }
    let progression = min(1, max(0, locator.locations.progression ?? 0))
    return min(end - 1, first + Int(progression * Double(end - first)))
  }

  /// Erste Stelle, an der die ersten (bis zu acht) Wörter von `needle` lückenlos stehen.
  private func wordSequence(_ needle: [String], in range: Range<Int>) -> Int? {
    let probe = Array(needle.prefix(8))
    guard probe.count >= 3, range.count >= probe.count else { return nil }
    for start in range.lowerBound...(range.upperBound - probe.count) {
      if probe.indices.allSatisfy({ words[start + $0].normalized == probe[$0] }) { return start }
    }
    return nil
  }

  private static func resourcePath(_ href: String) -> String {
    let path = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
    return path.removingPercentEncoding ?? path
  }

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
    var uniquePositions: [Int32] = []
    ids.reserveCapacity(words.count)
    for (position, word) in words.enumerated() {
      if let id = vocabulary[word.normalized] {
        ids.append(id)
        uniquePositions[Int(id)] = -1
      } else {
        let id = Int32(vocabulary.count)
        vocabulary[word.normalized] = id
        ids.append(id)
        uniquePositions.append(Int32(position))
      }
    }
    return EbookReadAlongIndex(
      sentences: sentences, words: words, trigrams: trigrams, ids: ids, vocabulary: vocabulary,
      uniquePositions: uniquePositions)
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


// MARK: - Abgleich in beide Richtungen

/// Hörposition ↔ eBook-Wort über den Abgleich (`EbookAudioAlignment.swift`). Genutzt vom Reader-Button
/// (Hörposition → Seite) und vom Player-Button (Leseposition → Hörposition). Beides nur auf Knopfdruck —
/// bewusst kein automatischer Seiten-Sync.
@MainActor
enum EbookNarrationSync {
  /// So lange gilt ein Abgleich im Speicher, ohne das Transkript neu von der Platte zu prüfen.
  private static let alignmentMaxAge: TimeInterval = 30
  private static var locales: [String: Locale] = [:]

  static let downloadRequiredMessage = "Download the audiobook to jump between it and the ebook."
  static let ebookUnreadableMessage = "The ebook couldn't be read."

  /// eBook-Wort an der aktuellen Hörposition. Steht sie vor dem ersten erkannten Wort des Tracks
  /// (Kapitelansage, Musik), gilt das letzte Wort des Vortracks.
  static func narrationWord(player: PlaybackController, index: EbookReadAlongIndex) async -> Int? {
    guard let context = await context(player: player) else { return nil }
    player.syncGlobalPositionFromPlayer()
    let position = player.liveGlobalPlaybackPosition
    let sources = context.sources
    guard let current = sources.lastIndex(where: { $0.globalOffset <= position }),
      let alignment = await alignment(sources[current], context: context, index: index)
    else { return nil }
    if let word = alignment.lastEbookWord(atOrBeforeLocalTime: position - sources[current].globalOffset) {
      return word
    }
    guard current > 0, let previous = await self.alignment(sources[current - 1], context: context, index: index)
    else { return nil }
    return previous.ebookWordRange?.upperBound
  }

  /// Globale Hörposition, ab der das eBook-Wort gesprochen wird. Zuerst der Track, in dem das Wort
  /// anteilig liegen müsste, sonst alle Tracks der Reihe nach. Fällt das Wort zwischen zwei Tracks
  /// (Kapitelgrenze, nur im Buch vorhandener Text), beginnt die Wiedergabe am Anfang des nächsten.
  static func playbackPosition(
    forEbookWord word: Int, player: PlaybackController, index: EbookReadAlongIndex
  ) async -> Double? {
    guard let context = await context(player: player) else { return nil }
    let sources = context.sources
    guard let last = sources.last else { return nil }
    let total = last.globalOffset + last.duration
    let estimate = Double(word) / Double(max(1, index.words.count)) * total
    if let guess = sources.lastIndex(where: { $0.globalOffset <= estimate }),
      let alignment = await alignment(sources[guess], context: context, index: index),
      let time = alignment.localTime(forEbookWord: word)
    {
      return sources[guess].globalOffset + time
    }

    // Ein Track ohne Transkript: dahinter ist offen, wo das Wort liegt — lieber keine Antwort als eine falsche.
    var missingTranscript = false
    for source in sources {
      guard let alignment = await alignment(source, context: context, index: index) else {
        missingTranscript = true
        continue
      }
      guard let range = alignment.ebookWordRange else { continue }
      if word < range.lowerBound {
        guard !missingTranscript, let first = alignment.localTime(forEbookWord: range.lowerBound) else { return nil }
        return source.globalOffset + first
      }
      if let time = alignment.localTime(forEbookWord: word) { return source.globalOffset + time }
      missingTranscript = false
    }
    return nil
  }

  /// Ziel des Player-Buttons „Jump to ebook position": Hörposition der Stelle, an der man im eBook
  /// gerade liest. Erst berechnen, dann nachfragen, dann `jumpPlayer(to:)`.
  struct PlayerJumpTarget {
    let bookId: String
    let position: Double
    let chapterTitle: String?
  }

  /// `.success` mit Ziel oder `.failure` mit der Meldung für den Nutzer.
  static func playerReadingTarget(model: AppModel) async -> Result<PlayerJumpTarget, NoticeError> {
    let player = model.player
    guard let book = player.activeBook, player.activePlaybackEpisodeId == nil else {
      return .failure(NoticeError(ebookUnreadableMessage))
    }
    guard player.isReadAlongDownloadReady else { return .failure(NoticeError(downloadRequiredMessage)) }
    guard
      let locator = EbookReadingAnchorStore.anchor(libraryItemId: book.id)
        ?? EbookLocalStore.loadReadiumLocator(libraryItemId: book.id, format: .epub)
    else { return .failure(NoticeError("Open the ebook first — there's no reading position yet.")) }
    guard
      let index = await TeleprompterEbookTextProvider.shared.index(forLibraryItemId: book.id, model: model),
      let word = index.wordPosition(for: locator)
    else { return .failure(NoticeError(ebookUnreadableMessage)) }
    guard let position = await playbackPosition(forEbookWord: word, player: player, index: index) else {
      model.transcriptPrefetcher.scheduleIfNeeded()
      return .failure(NoticeError(
        "This part of the ebook can't be matched to the audiobook yet. If its transcript is still being prepared, try again later."))
    }
    return .success(
      PlayerJumpTarget(bookId: book.id, position: position, chapterTitle: player.chapterTitle(atGlobal: position)))
  }

  /// Nach der Rückfrage: springen und abspielen. Hat das Hörbuch inzwischen gewechselt, passiert nichts.
  static func jumpPlayer(to target: PlayerJumpTarget, model: AppModel) {
    let player = model.player
    guard player.activeBook?.id == target.bookId else { return }
    player.seek(global: target.position)
    if !player.isPlaying { player.play() }
  }

  struct NoticeError: Error {
    let message: String
    init(_ message: String) { self.message = message }
  }

  // MARK: Intern

  private struct Context {
    let bookId: String
    let locale: Locale
    let sources: [PlayerTranscriptTrackSource]
  }

  private static func context(player: PlaybackController) async -> Context? {
    guard let bookId = player.transcriptionStorageId else { return nil }
    let sources = player.localTranscriptionTrackSources()
    guard !sources.isEmpty else { return nil }
    let tag = player.preferredTranscriptionLanguageTag ?? ""
    if locales[tag] == nil {
      locales[tag] = (try? await SpeechTranscriptionLocaleResolver.resolve(
        preferredLanguageTag: player.preferredTranscriptionLanguageTag))?.locale
    }
    guard let locale = locales[tag] else { return nil }
    return Context(bookId: bookId, locale: locale, sources: sources)
  }

  private static func alignment(
    _ source: PlayerTranscriptTrackSource, context: Context, index: EbookReadAlongIndex
  ) async -> EbookTrackAlignment? {
    await EbookAlignmentStore.shared.alignment(
      forTrack: source.trackIndex, bookId: context.bookId, locale: context.locale, index: index,
      maxAge: alignmentMaxAge)
  }
}

/// Letzte Leseposition je eBook mit dem Text des ersten sichtbaren Elements — genauer als der
/// gespeicherte Locator (nur Kapitel + Anteil). Nur im Speicher: Grundlage für „Jump to ebook position".
@MainActor
enum EbookReadingAnchorStore {
  private static var anchors: [String: Locator] = [:]

  static func update(_ locator: Locator, libraryItemId: String) {
    anchors[libraryItemId] = locator
  }

  static func anchor(libraryItemId: String) -> Locator? {
    anchors[libraryItemId]
  }

  /// Aktuelle Seite des Readers samt Text ihres ersten sichtbaren Elements merken.
  static func capture(from navigator: EPUBNavigatorViewController, locator: Locator, libraryItemId: String) async {
    guard let visible = await navigator.firstVisibleElementLocator(),
      visible.href.string == locator.href.string
    else {
      update(locator, libraryItemId: libraryItemId)
      return
    }
    update(locator.copy(text: { $0 = visible.text }), libraryItemId: libraryItemId)
  }
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

  /// Zum eBook gibt es ein Hörbuch — dann steht der Button immer im Reader, auch wenn der Player gerade
  /// nichts oder ein anderes Buch geladen hat (es wird beim Tippen pausiert geladen).
  var isAvailable: Bool {
    if isLoadedInPlayer { return true }
    return model.cachedBookDetail(id: libraryItemId)?.isPlayableAudiobook ?? false
  }

  private var isLoadedInPlayer: Bool {
    model.player.activeBook?.id == libraryItemId && model.player.activePlaybackEpisodeId == nil
  }

  /// So lange wartet der Sprung, bis das pausiert geladene Hörbuch seine Tracks kennt.
  private static let playerLoadTimeout: Duration = .seconds(8)

  /// Gerade selbst navigiert (Sprung) — Positionsmeldungen bis kurz danach stammen nicht vom Nutzer.
  var isProgrammaticNavigationRecent: Bool {
    lastProgrammaticNavigationAt.map { Date().timeIntervalSince($0) < 1.5 } ?? false
  }

  func jumpToNarration() {
    guard !isBusy, navigator != nil else { return }
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
    guard hasMarking, !isProgrammaticNavigationRecent else { return }
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
    if !isLoadedInPlayer, let notice = await loadAudiobookPaused() { return notice }
    guard model.player.isReadAlongDownloadReady else { return EbookNarrationSync.downloadRequiredMessage }
    guard let index = await ensureIndex(), !index.isEmpty else { return EbookNarrationSync.ebookUnreadableMessage }
    guard let end = await EbookNarrationSync.narrationWord(player: model.player, index: index),
      let endSentence = index.sentenceIndex(forWord: end)
    else {
      model.transcriptPrefetcher.scheduleIfNeeded()
      return
        "This part of the audiobook can't be matched to the ebook yet. If its transcript is still being prepared, try again later."
    }
    let start = max(0, end - Self.recentWordCount + 1)
    guard let startSentence = index.sentenceIndex(forWord: start) else {
      return EbookNarrationSync.ebookUnreadableMessage
    }

    // Markierung im Akzent (Daten-Farbe des Paper-Looks), dezent genug für jedes Reader-Theme.
    let tint = UIColor(model.appearanceAccentColor)
    var decorations: [Decoration] = []
    for sentence in startSentence...endSentence {
      let range = index.wordRange(ofSentence: sentence)
      let chunk = max(range.lowerBound, start)..<min(range.upperBound, end + 1)
      guard !chunk.isEmpty else { continue }
      decorations.append(
        Decoration(
          id: "recent-\(sentence)",
          locator: Self.chunkLocator(sentence: sentence, words: chunk, index: index),
          style: .highlight(tint: tint, isActive: false)))
    }
    guard let first = decorations.first, let navigator else { return EbookNarrationSync.ebookUnreadableMessage }
    navigator.apply(decorations: decorations, in: Self.markingGroup)
    hasMarking = true
    lastProgrammaticNavigationAt = Date()
    _ = await navigator.go(to: first.locator, options: NavigatorGoOptions(animated: true))
    lastProgrammaticNavigationAt = Date()
    return nil
  }

  /// Hörbuch dieses eBooks pausiert in den Player laden (an seiner gespeicherten Hörposition).
  /// Läuft gerade ein anderer Titel, wird er nicht ungefragt ersetzt. `nil` bei Erfolg.
  private func loadAudiobookPaused() async -> String? {
    guard let book = model.cachedBookDetail(id: libraryItemId), book.isPlayableAudiobook else {
      return "There's no audiobook for this ebook."
    }
    guard model.resolvedLocalDownloadForPlayback(book: book) != nil else {
      return EbookNarrationSync.downloadRequiredMessage
    }
    guard !model.player.isPlaying else {
      return "Another title is playing. Pause it first to jump to this audiobook's position."
    }
    await model.play(book: book, autoPlay: false)
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: Self.playerLoadTimeout)
    while clock.now < deadline {
      if isLoadedInPlayer, !model.player.localTranscriptionTrackSources().isEmpty { return nil }
      try? await Task.sleep(for: .milliseconds(200))
    }
    return isLoadedInPlayer ? nil : "The audiobook couldn't be loaded."
  }

  /// eBook-Index über den geteilten Provider — Teleprompter und Reader bauen ihn so nur einmal.
  private func ensureIndex() async -> EbookReadAlongIndex? {
    if let index { return index }
    let built = await TeleprompterEbookTextProvider.shared.index(
      forLibraryItemId: libraryItemId, model: model)
    index = built
    return built
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
