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
  /// Je geschlossener Zeile: Anzahl der bis dahin verarbeiteten Eingabewörter (Wiederaufsetzpunkt).
  /// Damit lässt sich ab einer Zeile neu umbrechen, ohne die Zeilen davor anzufassen.
  private var lineRestartPoints: [Int] = []
  /// Je geschlossener Zeile: Anzahl der Eingabewörter, von denen ihr Umbruch abhängt. Bei Satzende
  /// gleich dem Wiederaufsetzpunkt; bei Überlauf eins mehr — dort entscheidet das Wort AM
  /// Wiederaufsetzpunkt über den Umbruch. Monoton steigend wie `lineRestartPoints`.
  private var lineDependencyEnds: [Int] = []
  /// Zeichenlimit, mit dem die bestehenden Zeilen gebaut wurden (`nil` = gemischt/unbekannt).
  private var linesLimit: Int?
  /// Aus Panel-Breite abgeleitet; Fallback bis Layout bekannt ist.
  var maxCharactersPerLine = 84

  func reset() {
    closedLines = []
    openWords = []
    openCharCount = 0
    nextLineIndex = 0
    nextWordIndex = 0
    lineRestartPoints = []
    lineDependencyEnds = []
    linesLimit = maxCharactersPerLine
  }

  /// Bestehende Wörter mit neuem Zeichenlimit neu umbrechen (z. B. Schriftgröße).
  func rebuildLines(from words: [PlayerTranscriptWord], maxCharactersPerLine limit: Int) {
    maxCharactersPerLine = limit
    reset()
    appendFinalizedWords(words)
  }

  /// Neu umbrechen, wenn sich `words` erst ab Index `unchangedPrefix` geändert hat (eingefügte
  /// Wörter): Zeilen, die vollständig davor liegen, bleiben stehen — Ergebnis wie `rebuildLines`.
  func rebuildLines(from words: [PlayerTranscriptWord], unchangedPrefix: Int) {
    guard linesLimit == maxCharactersPerLine else {
      rebuildLines(from: words, maxCharactersPerLine: maxCharactersPerLine)
      return
    }
    // Letzte Zeile, deren Umbruch nur von Wörtern im unveränderten Teil abhängt (Binärsuche).
    var low = 0
    var high = lineDependencyEnds.count
    while low < high {
      let mid = (low + high) / 2
      if lineDependencyEnds[mid] <= unchangedPrefix { low = mid + 1 } else { high = mid }
    }
    let keptLines = low
    let restart = keptLines > 0 ? lineRestartPoints[keptLines - 1] : 0
    guard restart <= words.count else {
      rebuildLines(from: words, maxCharactersPerLine: maxCharactersPerLine)
      return
    }
    closedLines.removeSubrange(keptLines...)
    lineRestartPoints.removeSubrange(keptLines...)
    lineDependencyEnds.removeSubrange(keptLines...)
    openWords = []
    openCharCount = 0
    nextLineIndex = keptLines
    nextWordIndex = restart
    appendFinalizedWords(words[restart...])
  }

  func appendFinalizedWords<Words: Sequence<PlayerTranscriptWord>>(_ incoming: Words) {
    if linesLimit != maxCharactersPerLine, !closedLines.isEmpty || !openWords.isEmpty {
      linesLimit = nil
    } else if closedLines.isEmpty, openWords.isEmpty {
      linesLimit = maxCharactersPerLine
    }
    for raw in incoming {
      let word = stabilized(raw)
      if word.isWhitespaceOnly {
        if !openWords.isEmpty { openWords.append(word) }
        continue
      }
      let add = word.text.count
      if openCharCount > 0, openCharCount + add > maxCharactersPerLine {
        // Das aktuelle Wort gehört schon zur nächsten Zeile — Wiederaufsetzpunkt davor.
        closeOpenLine(restartPoint: nextWordIndex - 1, dependsOnRestartWord: true)
      }
      openWords.append(word)
      openCharCount += add
      if Self.endsSentence(in: word.text) {
        closeOpenLine(restartPoint: nextWordIndex, dependsOnRestartWord: false)
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

  private func closeOpenLine(restartPoint: Int, dependsOnRestartWord: Bool) {
    guard let snapshot = openLineSnapshot() else {
      openWords = []
      openCharCount = 0
      return
    }
    closedLines.append(snapshot)
    lineRestartPoints.append(restartPoint)
    lineDependencyEnds.append(dependsOnRestartWord ? restartPoint + 1 : restartPoint)
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

// MARK: - Wortanfänge nach Sprechpausen

/// Korrigiert Wortanfänge, die der Erkenner in eine vorausgehende Sprechpause vorzieht.
///
/// `SpeechTranscriber` lässt im Deutschen nach Pausen fast nie eine Lücke: Das Wort nach der Pause
/// beginnt laut Erkenner schon am Ende des vorigen Worts, nur sein Ende stimmt. Die Markierung
/// sprang dadurch bis ~1 s zu früh. Ein Wort darf deshalb höchstens `maxDuration` vor seinem Ende
/// beginnen (Basis + je sichtbarem Zeichen). Gemessen mit synthetischer Sprache (DE/EN, bekannte
/// Phrasenanfänge): Fehler erkannt − wahr DE Mittel −0,29 → −0,12 s, P5 −1,05 → −0,40 s; EN
/// unverändert (−0,11 s). Konstanten aus TTS-Sprechtempo, eher großzügig gewählt.
///
/// Seit Transkript-Version 4 legt der Producer Wortanfänge nach Pausen auf den akustischen Einsatz
/// (`SpeechOnsetRefiner`). Diese Heuristik bleibt nur der Rückfall für alte Transkripte (Version 2),
/// bis sie neu erzeugt sind: Sie wirkt beim Lesen auf die Read-Along-Anzeige (Zeilen, Markierung,
/// Scroll) und nie auf verfeinerte Wörter — die würde sie sonst ein zweites Mal verschieben.
enum ReadAlongWordTiming {
  static let baseMaxDuration: Double = 0.15
  static let maxDurationPerCharacter: Double = 0.10

  /// Sichtbare Zeichen ohne Leerraum.
  static func characterCount(_ text: String) -> Int {
    text.reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
  }

  static func maxDuration(characterCount: Int) -> Double {
    baseMaxDuration + maxDurationPerCharacter * Double(max(0, characterCount))
  }

  /// `max(start, end − maxDuration)`, höchstens bis zum (unkorrigierten) Start des Folgeworts —
  /// so bleiben die Anfänge monoton. Unverändert bei `end ≤ start` oder ungültigen Zeiten.
  static func correctedStart(start: Double, end: Double, characterCount: Int, nextStart: Double?) -> Double {
    guard start.isFinite, end.isFinite, end > start else { return start }
    var corrected = max(start, end - maxDuration(characterCount: characterCount))
    if let nextStart, nextStart.isFinite {
      corrected = max(start, min(corrected, nextStart))
    }
    return corrected
  }

  /// Wörter (nach Startzeit sortiert) mit korrigierten Anfängen; Ende, Text und ID bleiben.
  /// Folgewort ist das nächste Nicht-Leerraum-Wort derselben Liste.
  static func corrected(_ words: [PlayerTranscriptWord]) -> [PlayerTranscriptWord] {
    var out = words
    var nextStart: Double?
    for index in words.indices.reversed() {
      let word = words[index]
      guard !word.isWhitespaceOnly else { continue }
      let start = correctedStart(
        start: word.globalStart, end: word.globalEnd,
        characterCount: characterCount(word.text), nextStart: nextStart)
      if start != word.globalStart {
        out[index] = PlayerTranscriptWord(
          id: word.id, text: word.text, globalStart: start, globalEnd: word.globalEnd)
      }
      nextStart = word.globalStart
    }
    return out
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
