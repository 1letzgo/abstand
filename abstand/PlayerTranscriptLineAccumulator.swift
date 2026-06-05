import Foundation

/// Baut Teleprompter-Zeilen inkrementell — Wörter wechseln nie die Zeile nachträglich.
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

  func appendFinalizedWords(_ incoming: [PlayerTranscriptWord]) {
    for raw in incoming where !raw.isVolatile {
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
      if endsSentence(in: word.text) {
        closeOpenLine()
      }
    }
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

  func publishedLines() -> [PlayerTranscriptLine] {
    var all = closedLines
    if let open = openLineSnapshot() { all.append(open) }
    return all
  }

  private var openLineId: String { "line-\(nextLineIndex)" }

  private func openLineSnapshot() -> PlayerTranscriptLine? {
    let spoken = openWords.filter { !$0.isWhitespaceOnly }
    guard !spoken.isEmpty else { return nil }
    return PlayerTranscriptLine(
      id: openLineId,
      words: openWords,
      globalStart: spoken.first!.globalStart,
      globalEnd: max(spoken.last!.globalEnd, spoken.first!.globalStart + 0.05),
      isVolatile: false
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
      globalEnd: word.globalEnd,
      isVolatile: false
    )
  }
}
