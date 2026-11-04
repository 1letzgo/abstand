import Foundation

/// Baut Teleprompter-Zeilen inkrementell; bei Schriftgrößenwechsel optional komplett neu umbrechen.
/// Die frühere „volatile"-Unterscheidung (vorläufige Speech-Ergebnisse der Live-Pipeline) ist mit
/// dem Umbau auf vorproduzierte Transkripte entfallen — es gibt nur noch finalisierte Wörter.
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
    for raw in incoming {
      let word = stabilized(raw)
      if word.isWhitespaceOnly {
        if !openWords.isEmpty { openWords.append(word) }
        continue
      }
      let add = word.text.count
      if openCharCount > 0, openCharCount + add > maxCharactersPerLine {
        closeOpenLine()
      }
      openWords.append(word)
      openCharCount += add
      if Self.endsSentence(in: word.text) {
        closeOpenLine()
      }
    }
  }

  private var openLineId: String { "line-\(nextLineIndex)" }

  func publishedLines() -> [PlayerTranscriptLine] {
    var all = closedLines
    if let open = openLineSnapshot() { all.append(open) }
    return all
  }

  private func openLineSnapshot() -> PlayerTranscriptLine? {
    let spoken = openWords.filter { !$0.isWhitespaceOnly }
    guard !spoken.isEmpty else { return nil }
    return PlayerTranscriptLine(
      id: openLineId,
      words: openWords,
      globalStart: spoken.first!.globalStart,
      globalEnd: max(spoken.last!.globalEnd, spoken.first!.globalStart + 0.05)
    )
  }

  private func closeOpenLine() {
    guard let snapshot = openLineSnapshot() else {
      openWords = []
      openCharCount = 0
      return
    }
    closedLines.append(snapshot)
    nextLineIndex += 1
    openWords = []
    openCharCount = 0
  }

  private func stabilized(_ word: PlayerTranscriptWord) -> PlayerTranscriptWord {
    let id = "w-\(nextWordIndex)"
    nextWordIndex += 1
    return PlayerTranscriptWord(
      id: id,
      text: word.text,
      globalStart: word.globalStart,
      globalEnd: word.globalEnd
    )
  }

  /// Satzende: Zeile nach `.` `!` `?` `…` schließen (Anführungszeichen am Ende ignorieren).
  static func endsSentence(in text: String) -> Bool {
    var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = t.last, "'\"»」)]}".contains(last) {
      t.removeLast()
    }
    guard let last = t.last else { return false }
    return ".!?…".contains(last)
  }
}

/// Absätze für die Read-Along-Markierung. Das Transkript kennt selbst keine Absätze, daher
/// abgeleitet: ein Absatz endet an einem Satzende mit Sprechpause oder nach einigen Sätzen,
/// spätestens nach einer festen Zeilenzahl (Text ganz ohne Satzzeichen).
@MainActor
enum PlayerTranscriptParagraphs {
  static let minPauseSeconds: Double = 0.7
  static let maxSentences = 3
  static let maxLines = 6

  /// Je Zeile die laufende Nummer ihres Absatzes.
  static func paragraphIndices(for lines: [PlayerTranscriptLine]) -> [Int] {
    var result: [Int] = []
    result.reserveCapacity(lines.count)
    var paragraph = 0
    var sentences = 0
    var linesInParagraph = 0
    for (index, line) in lines.enumerated() {
      result.append(paragraph)
      linesInParagraph += 1
      let endsSentence = line.spokenWords.last.map {
        PlayerTranscriptLineAccumulator.endsSentence(in: $0.text)
      } ?? false
      if endsSentence { sentences += 1 }
      let pause = index + 1 < lines.count ? lines[index + 1].globalStart - line.globalEnd : 0
      if (endsSentence && (pause >= minPauseSeconds || sentences >= maxSentences))
        || linesInParagraph >= maxLines
      {
        paragraph += 1
        sentences = 0
        linesInParagraph = 0
      }
    }
    return result
  }
}
