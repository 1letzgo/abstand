import Foundation

/// Baut Teleprompter-Zeilen inkrementell; bei Schriftgrößenwechsel optional komplett neu umbrechen.
@MainActor
final class PlayerTranscriptLineAccumulator {
  private(set) var closedLines: [PlayerTranscriptLine] = []
  private var openWords: [PlayerTranscriptWord] = []
  private var openCharCount = 0
  private var nextLineIndex = 0
  private var nextWordIndex = 0
  /// Aus Panel-Breite abgeleitet; Fallback bis Layout bekannt ist.
  var maxCharactersPerLine = 84

  func reset() {
    closedLines = []
    openWords = []
    openCharCount = 0
    nextLineIndex = 0
    nextWordIndex = 0
  }

  /// Bestehende Wörter mit neuem Zeichenlimit neu umbrechen (z. B. Schriftgröße).
  func rebuildLines(from words: [PlayerTranscriptWord], maxCharactersPerLine limit: Int) {
    maxCharactersPerLine = limit
    closedLines = []
    openWords = []
    openCharCount = 0
    nextLineIndex = 0
    nextWordIndex = 0
    appendFinalizedWords(words)
  }

  func appendFinalizedWords(_ incoming: [PlayerTranscriptWord]) {
    appendWords(incoming, includeVolatile: false, lineVolatile: false)
  }

  /// Einmalige Zeilen aus Wortliste (z. B. volatiler Teleprompter-Schwanz).
  static func makeLines(
    from words: [PlayerTranscriptWord],
    maxCharactersPerLine limit: Int,
    volatile: Bool
  ) -> [PlayerTranscriptLine] {
    let builder = PlayerTranscriptLineAccumulator()
    builder.maxCharactersPerLine = limit
    builder.appendWords(words, includeVolatile: true, lineVolatile: volatile)
    return builder.publishedLines(volatile: volatile)
  }

  private func appendWords(
    _ incoming: [PlayerTranscriptWord],
    includeVolatile: Bool,
    lineVolatile: Bool
  ) {
    for raw in incoming where includeVolatile || !raw.isVolatile {
      let word = stabilized(raw, preserveVolatileFlag: lineVolatile)
      if word.isWhitespaceOnly {
        if !openWords.isEmpty { openWords.append(word) }
        continue
      }
      let add = word.text.count
      if openCharCount > 0, openCharCount + add > maxCharactersPerLine {
        closeOpenLine(volatile: lineVolatile)
      }
      openWords.append(word)
      openCharCount += add
      if endsSentence(in: word.text) {
        closeOpenLine(volatile: lineVolatile)
      }
    }
  }

  private var openLineId: String { "line-\(nextLineIndex)" }

  func publishedLines(volatile: Bool = false) -> [PlayerTranscriptLine] {
    var all = closedLines
    if let open = openLineSnapshot(volatile: volatile) { all.append(open) }
    return all
  }

  private func openLineSnapshot(volatile: Bool = false) -> PlayerTranscriptLine? {
    let spoken = openWords.filter { !$0.isWhitespaceOnly }
    guard !spoken.isEmpty else { return nil }
    return PlayerTranscriptLine(
      id: volatile ? "volatile-\(openLineId)" : openLineId,
      words: openWords,
      globalStart: spoken.first!.globalStart,
      globalEnd: max(spoken.last!.globalEnd, spoken.first!.globalStart + 0.05),
      isVolatile: volatile
    )
  }

  private func closeOpenLine(volatile: Bool = false) {
    guard let snapshot = openLineSnapshot(volatile: volatile) else {
      openWords = []
      openCharCount = 0
      return
    }
    closedLines.append(snapshot)
    nextLineIndex += 1
    openWords = []
    openCharCount = 0
  }

  private func stabilized(_ word: PlayerTranscriptWord, preserveVolatileFlag: Bool = false) -> PlayerTranscriptWord {
    let id = preserveVolatileFlag && word.isVolatile
      ? "vw-\(nextWordIndex)"
      : "w-\(nextWordIndex)"
    nextWordIndex += 1
    return PlayerTranscriptWord(
      id: id,
      text: word.text,
      globalStart: word.globalStart,
      globalEnd: word.globalEnd,
      isVolatile: preserveVolatileFlag ? word.isVolatile : false
    )
  }

  /// Satzende: Zeile nach `.` `!` `?` `…` schließen (Anführungszeichen am Ende ignorieren).
  private func endsSentence(in text: String) -> Bool {
    var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = t.last, "'\"»」)]}".contains(last) {
      t.removeLast()
    }
    guard let last = t.last else { return false }
    return ".!?…".contains(last)
  }
}
