import Foundation

// Abgleich Hörbuch ↔ eBook: genau eine Quelle der Wahrheit für „welches eBook-Wort wird wann gesprochen".
// Nutzer: der Reader-Button `EbookNarrationJumpController` (springt zur Seite der Hörposition, markiert
// die letzten gesprochenen Wörter) und der Player-Button „Jump to ebook position"
// (`EbookNarrationSync.playbackPosition`, Rückrichtung Wort → Zeit). Der Teleprompter zeigt immer das
// Transkript und nutzt den Abgleich nicht.
//
// Je Track wird das Transkript (Erkennung, mit Zeiten) global-monoton gegen das eBook ausgerichtet:
// eindeutige Trigramme und seltene lange Wörter als Fixpunkte (längste aufsteigende Teilfolge), Lücken rekursiv über eindeutige
// Wörter und zuletzt per LCS. Ein falscher Treffer kann die Kette so nicht mehr verbiegen — er passt
// nicht in die globale Ordnung und fällt heraus. Das Ergebnis wird je Track gespeichert.

// MARK: - Eingabe

/// Ein erkanntes Wort mit Zeit in lokalen Track-Sekunden.
nonisolated struct AlignmentInputWord: Sendable {
  let text: String
  let start: Double
  let end: Double
}

// MARK: - Ergebnis (ein Track)

/// Ausgerichtete eBook-Wörter eines Tracks, streng aufsteigend nach eBook-Position und damit auch
/// nach Zeit. Nicht ausgerichtete Wörter (nur im Buch oder nur im Hörbuch vorhanden) fehlen.
nonisolated struct EbookTrackAlignment: Sendable {
  // 2: Tokenzeiten nach Zeichenzahl, Lückenfüllung mit Pausen (alte Dateien werden neu berechnet).
  // 3: seltene Wörter als zusätzliche Fixpunkte.
  static let formatVersion: UInt32 = 3
  private static let magic: UInt32 = 0x4142_4C31

  /// Für die Gültigkeit der gespeicherten Datei: eBook und Transkript, mit denen gerechnet wurde.
  let ebookWordCount: Int
  let spokenWordCount: Int
  /// Ende des letzten erkannten Worts (lokale Sekunden). Nur Teil des Dateiformats — für Abfragen
  /// ungeeignet, weil Transkript-Lücken auch mitten im Track liegen (dafür `EbookTranscriptCoverage`).
  let spokenEnd: Double

  let words: [Int32]
  /// Lokale Track-Sekunden.
  let starts: [Float]
  let ends: [Float]
  /// 1 = direkt erkannt, 0 = zwischen erkannten Nachbarn verteilt. Wird in der App nicht gelesen,
  /// bleibt aber Teil des Dateiformats (Android und Golden-Files lesen/schreiben es mit).
  let flags: [UInt8]

  var isEmpty: Bool { words.isEmpty }

  static func empty(ebookWordCount: Int, spokenWordCount: Int, spokenEnd: Double) -> EbookTrackAlignment {
    EbookTrackAlignment(
      ebookWordCount: ebookWordCount, spokenWordCount: spokenWordCount, spokenEnd: spokenEnd,
      words: [], starts: [], ends: [], flags: [])
  }

  // MARK: Abfragen

  /// Index (in `words`) des letzten ausgerichteten Worts, das bis zur Track-Zeit begonnen hat.
  /// `nil` vor dem ersten ausgerichteten Wort des Tracks. Ob der Treffer plausibel ist (Abdeckung des
  /// Transkripts, Abstand), prüft der Aufrufer — siehe `EbookTrackLookup`.
  func lastAlignedIndex(atOrBeforeLocalTime time: Double) -> Int? {
    guard !words.isEmpty else { return nil }
    var low = 0
    var high = words.count
    while low < high {
      let mid = (low + high) / 2
      if Double(starts[mid]) <= time { low = mid + 1 } else { high = mid }
    }
    return low > 0 ? low - 1 : nil
  }

  /// Erstes und letztes ausgerichtetes eBook-Wort dieses Tracks.
  var ebookWordRange: ClosedRange<Int>? {
    guard let first = words.first, let last = words.last else { return nil }
    return Int(first)...Int(last)
  }

  /// Index (in `words`) des eBook-Worts oder — bei nicht ausgerichtetem Wort (nur im Buch vorhanden) —
  /// des nächsten ausgerichteten danach. `nil` außerhalb von `ebookWordRange`.
  func alignedIndex(forEbookWord position: Int) -> Int? {
    guard let range = ebookWordRange, range.contains(position) else { return nil }
    let target = Int32(position)
    var low = 0
    var high = words.count
    while low < high {
      let mid = (low + high) / 2
      if words[mid] < target { low = mid + 1 } else { high = mid }
    }
    return words.indices.contains(low) ? low : nil
  }

  // MARK: Persistenz

  func encoded() -> Data {
    var data = Data()
    func put<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
    put(Self.magic)
    put(Self.formatVersion)
    put(Int32(ebookWordCount))
    put(Int32(spokenWordCount))
    put(spokenEnd)
    put(Int32(words.count))
    words.withUnsafeBytes { data.append(contentsOf: $0) }
    starts.withUnsafeBytes { data.append(contentsOf: $0) }
    ends.withUnsafeBytes { data.append(contentsOf: $0) }
    flags.withUnsafeBytes { data.append(contentsOf: $0) }
    return data
  }

  init(
    ebookWordCount: Int, spokenWordCount: Int, spokenEnd: Double,
    words: [Int32], starts: [Float], ends: [Float], flags: [UInt8]
  ) {
    self.ebookWordCount = ebookWordCount
    self.spokenWordCount = spokenWordCount
    self.spokenEnd = spokenEnd
    self.words = words
    self.starts = starts
    self.ends = ends
    self.flags = flags
  }

  init?(data: Data) {
    var offset = 0
    func read<T>(_: T.Type) -> T? {
      let size = MemoryLayout<T>.size
      guard offset + size <= data.count else { return nil }
      let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
      offset += size
      return value
    }
    func readArray<T>(_: T.Type, count: Int) -> [T]? {
      let size = MemoryLayout<T>.stride * count
      guard count >= 0, offset + size <= data.count else { return nil }
      let chunk = data.subdata(in: offset..<(offset + size))
      offset += size
      return chunk.withUnsafeBytes { Array($0.bindMemory(to: T.self)) }
    }
    guard
      read(UInt32.self) == Self.magic,
      read(UInt32.self) == Self.formatVersion,
      let ebookCount = read(Int32.self),
      let spokenCount = read(Int32.self),
      let spokenEnd = read(Double.self),
      let count = read(Int32.self),
      let words = readArray(Int32.self, count: Int(count)),
      let starts = readArray(Float.self, count: Int(count)),
      let ends = readArray(Float.self, count: Int(count)),
      let flags = readArray(UInt8.self, count: Int(count))
    else { return nil }
    self.init(
      ebookWordCount: Int(ebookCount), spokenWordCount: Int(spokenCount), spokenEnd: spokenEnd,
      words: words, starts: starts, ends: ends, flags: flags)
  }
}

// MARK: - Abfrage mit Transkript-Abdeckung

/// Transkribierte Zeitbereiche eines Tracks (lokale Sekunden, sortiert, überschneidungsfrei) — aus den
/// Segmenten der Transkriptdatei, nicht aus dem `.bin`. Außerhalb davon weiß der Abgleich nichts.
nonisolated struct EbookTranscriptCoverage: Sendable {
  struct Span: Sendable {
    let start: Double
    let end: Double
  }

  let spans: [Span]

  /// Wie `PlayerTranscriptTrackCache.covers`: halbe Sekunde Toleranz am Segmentanfang.
  static let tolerance = 0.5

  func span(containing time: Double) -> Span? {
    spans.first { $0.start - Self.tolerance <= time && time < $0.end }
  }

  /// Liegt `start...end` ohne Lücke in einem transkribierten Bereich?
  func coversContinuously(from start: Double, through end: Double) -> Bool {
    guard let span = span(containing: start) else { return false }
    return end <= span.end + Self.tolerance
  }
}

/// Abgleich eines Tracks plus Abdeckung seines Transkripts — Abfragen liefern nur dann eine Stelle,
/// wenn sie durch das Transkript belegt ist. Sonst `nil`, statt still Minuten daneben zu springen.
nonisolated struct EbookTrackLookup: Sendable {
  let alignment: EbookTrackAlignment
  let coverage: EbookTranscriptCoverage

  /// Höchster Abstand (Sekunden) zwischen Abfragezeit und nächstem ausgerichteten Wort — wie die
  /// Plausibilitätsgrenze der Lückenfüllung im Builder.
  static let maxGapSeconds: Double = 120

  enum NarratedWord {
    case word(Int)
    /// Transkribiert, aber vor dem ersten ausgerichteten Wort (Kapitelansage, Musik).
    case beforeFirstWord
    case unavailable
  }

  /// Zuletzt gesprochenes eBook-Wort bis zur Track-Zeit („wo war ich?").
  func narratedWord(atLocalTime time: Double) -> NarratedWord {
    guard let span = coverage.span(containing: time) else { return .unavailable }
    guard let i = alignment.lastAlignedIndex(atOrBeforeLocalTime: time) else {
      return span.start <= EbookTranscriptCoverage.tolerance ? .beforeFirstWord : .unavailable
    }
    // Das Wort muss im selben lückenlos transkribierten Bereich liegen und nah genug sein.
    guard Double(alignment.starts[i]) >= span.start - EbookTranscriptCoverage.tolerance,
      time - Double(alignment.ends[i]) <= Self.maxGapSeconds
    else { return .unavailable }
    return .word(Int(alignment.words[i]))
  }

  /// Track-Zeit, ab der das eBook-Wort gesprochen wird. Ein nicht ausgerichtetes Wort nimmt das nächste
  /// ausgerichtete danach — aber nur, wenn zwischen den Nachbarn lückenlos transkribiert ist und sie
  /// nicht weiter als `maxGapSeconds` auseinanderliegen.
  func localTime(forEbookWord position: Int) -> Double? {
    guard let i = alignment.alignedIndex(forEbookWord: position) else { return nil }
    let start = Double(alignment.starts[i])
    if Int(alignment.words[i]) == position { return start }
    guard i > 0 else { return nil }
    let previousEnd = Double(alignment.ends[i - 1])
    guard start - previousEnd <= Self.maxGapSeconds,
      coverage.coversContinuously(from: previousEnd, through: start)
    else { return nil }
    return start
  }

  /// Zeit des ersten ausgerichteten Worts, wenn es nah am Trackanfang liegt und davor lückenlos
  /// transkribiert ist (Wort fällt zwischen zwei Tracks → Anfang des nächsten).
  var leadingWordTime: Double? {
    guard let first = alignment.starts.first else { return nil }
    let time = Double(first)
    guard time <= Self.maxGapSeconds, coverage.coversContinuously(from: 0, through: time) else { return nil }
    return time
  }

  /// Letztes ausgerichtetes eBook-Wort, wenn es nah am Trackende liegt und dahinter lückenlos
  /// transkribiert ist.
  func trailingWord(trackDuration: Double) -> Int? {
    guard let last = alignment.words.indices.last else { return nil }
    let end = Double(alignment.ends[last])
    guard end >= trackDuration - Self.maxGapSeconds,
      coverage.coversContinuously(from: Double(alignment.starts[last]), through: max(0, trackDuration - 1))
    else { return nil }
    return Int(alignment.words[last])
  }

  /// Ganzer Track transkribiert (Kriterium wie `firstUncoveredTime`: bis eine Sekunde vor Ende).
  func isFullyCovered(trackDuration: Double) -> Bool {
    coverage.coversContinuously(from: 0, through: max(0, trackDuration - 1))
  }
}

// MARK: - Berechnung

nonisolated enum EbookAlignmentBuilder {
  /// Mindestanzahl erkannter Wörter und Anteil am Transkript, damit der Abgleich als verlässlich gilt.
  private static let minimumMatches = 12
  private static let minimumMatchRatio = 0.2
  /// Lückenfüllung: Höchstdauer eines nicht erkannten Worts mittlerer Länge (Gewicht
  /// `referenceWordWeight` = 5 Zeichen + 2); längere Wörter dürfen anteilig länger dauern.
  private static let maxFilledWordSeconds = 0.5
  private static let referenceWordWeight = 7.0
  /// Kürzere Reste gelten nicht als Pause (Rundung), die Wörter füllen die Lücke dann ganz.
  private static let minimumFilledPauseSeconds = 0.05
  /// Seltene Wörter als Fixpunkt erst ab dieser Länge — kurze Wörter sind zu oft Erkennungs-Zufall.
  private static let rareWordMinimumLength = 7

  /// Wo die Pause in einer Lücke hinter eBook-Wort `previousE` mit `gap` Wörtern steht: Index des
  /// ersten Lückenworts nach der Pause (`gap` = direkt vor dem nächsten erkannten Wort). Bevorzugt
  /// die letzte Satzgrenze in der Lücke, sonst direkt vor dem nächsten erkannten Wort.
  static func pauseSlot(afterWord previousE: Int, gap: Int, index: EbookReadAlongIndex) -> Int {
    var slot = gap
    while slot >= 0 {
      let before = previousE + slot
      if index.words[before].sentence != index.words[before + 1].sentence { return slot }
      slot -= 1
    }
    return gap
  }

  static func build(words input: [AlignmentInputWord], index: EbookReadAlongIndex) -> EbookTrackAlignment {
    let spokenEnd = input.last?.end ?? 0
    let empty = EbookTrackAlignment.empty(
      ebookWordCount: index.words.count, spokenWordCount: input.count, spokenEnd: spokenEnd)
    guard !index.isEmpty, input.count >= 8 else { return empty }

    // Erkannte Wörter in eBook-Tokens zerlegen („don't" → „don", „t"), Zeit nach Zeichenzahl verteilen
    // (ein langes Wort dauert länger als ein kurzes — gleichmäßig verteilt liefe die Markierung voraus).
    var sNorm: [String] = []
    var sStart: [Double] = []
    var sEnd: [Double] = []
    sNorm.reserveCapacity(input.count)
    for word in input {
      let tokens = ReadAlongText.words(in: word.text)
      guard !tokens.isEmpty else { continue }
      let duration = max(0, word.end - word.start)
      let weights = tokens.map { Double(max(1, $0.word.count)) }
      let total = weights.reduce(0, +)
      var cumulative = 0.0
      for (offset, token) in tokens.enumerated() {
        sNorm.append(token.word)
        sStart.append(word.start + duration * cumulative / total)
        cumulative += weights[offset]
        sEnd.append(word.start + duration * cumulative / total)
      }
    }
    let n = sNorm.count
    guard n >= 8 else { return empty }
    let sIds = sNorm.map { index.vocabulary[$0] ?? -1 }

    // 1. Fixpunkte: Trigramme, die im eBook und im Transkript genau einmal vorkommen.
    var keys = [Int](repeating: 0, count: n - 2)
    var firstPosition: [Int: Int] = [:]
    for i in 0..<(n - 2) {
      let key = ReadAlongText.trigramKey(sNorm[i], sNorm[i + 1], sNorm[i + 2])
      keys[i] = key
      firstPosition[key] = firstPosition[key] == nil ? i : -1
    }
    var anchors: [(e: Int, s: Int, length: Int)] = []
    for i in 0..<(n - 2) {
      let key = keys[i]
      guard firstPosition[key] == i, let e = index.uniqueTrigramPosition(forKey: key) else { continue }
      guard e + 2 < index.ids.count,
        sIds[i] >= 0, sIds[i] == index.ids[e],
        sIds[i + 1] == index.ids[e + 1], sIds[i + 2] == index.ids[e + 2]
      else { continue }
      anchors.append((e, i, 3))
    }

    // 1b. Seltene lange Wörter, die im eBook und im Transkript genau einmal vorkommen. Ein einzelner
    // Erkennungsfehler zerstört drei Trigramme, ein seltenes Wort („Thornfield") bleibt oft erhalten.
    var spokenCount: [Int32: Int] = [:]
    for id in sIds where id >= 0 { spokenCount[id, default: 0] += 1 }
    let trigramStarts = Set(anchors.map(\.s))
    var rare: [(e: Int, s: Int, length: Int)] = []
    for s in 0..<n {
      let id = sIds[s]
      guard id >= 0, sNorm[s].count >= Self.rareWordMinimumLength, spokenCount[id] == 1,
        let e = index.uniquePosition(ofWordId: id)
      else { continue }
      // Schon von einem Trigramm-Fixpunkt abgedeckt?
      if trigramStarts.contains(s) || trigramStarts.contains(s - 1) || trigramStarts.contains(s - 2) { continue }
      rare.append((e, s, 1))
    }
    if !rare.isEmpty { anchors = (anchors + rare).sorted { $0.s < $1.s } }
    guard !anchors.isEmpty else { return empty }

    // 2. Globale Ordnung: längste aufsteigende Teilfolge — Zufallstreffer fallen heraus.
    let chain = longestIncreasingSubsequence(anchors.map(\.e)).map { anchors[$0] }

    // 3. Kleine Inseln (unplausibles Tempo zum Nachbarn, weniger als drei Anker) verwerfen.
    var clusters: [[(e: Int, s: Int, length: Int)]] = []
    for anchor in chain {
      if let last = clusters.last?.last {
        let de = anchor.e - last.e
        let ds = anchor.s - last.s
        let ratio = Double(de) / Double(max(ds, 1))
        if de >= 1, ds >= 1, (de <= 12 && ds <= 12) || (ratio >= 0.25 && ratio <= 4) {
          clusters[clusters.count - 1].append(anchor)
          continue
        }
      }
      clusters.append([anchor])
    }
    let kept = clusters.filter { $0.count >= 3 }.flatMap { $0 }
    guard let first = kept.first else { return empty }

    // 4. Lücken zwischen den Fixpunkten füllen.
    var aligner = GapAligner(index: index, sIds: sIds, sNorm: sNorm)
    aligner.fill(
      eLo: max(0, first.e - (first.s * 2 + 12)), eHi: first.e, sLo: 0, sHi: first.s, depth: 0)
    for (i, anchor) in kept.enumerated() {
      for k in 0..<anchor.length { aligner.add(anchor.e + k, anchor.s + k) }
      guard let lastE = aligner.matchE.last, let lastS = aligner.matchS.last else { continue }
      if i + 1 < kept.count {
        aligner.fill(
          eLo: Int(lastE) + 1, eHi: kept[i + 1].e, sLo: Int(lastS) + 1, sHi: kept[i + 1].s, depth: 0)
      }
    }
    if let lastE = aligner.matchE.last, let lastS = aligner.matchS.last {
      let tailEbook = Int(lastE) + 1
      let tailSpoken = Int(lastS) + 1
      aligner.fill(
        eLo: tailEbook,
        eHi: min(index.words.count, tailEbook + (n - tailSpoken) * 2 + 12),
        sLo: tailSpoken, sHi: n, depth: 0)
    }

    let matchCount = aligner.matchE.count
    guard matchCount >= minimumMatches, Double(matchCount) >= minimumMatchRatio * Double(n) else {
      return empty
    }

    // 5. Zeiten: erkannte Wörter übernehmen ihre Zeit, Wörter dazwischen werden nach Länge verteilt.
    var outWords: [Int32] = []
    var outStarts: [Float] = []
    var outEnds: [Float] = []
    var outFlags: [UInt8] = []
    outWords.reserveCapacity(matchCount)
    outStarts.reserveCapacity(matchCount)
    outEnds.reserveCapacity(matchCount)
    outFlags.reserveCapacity(matchCount)
    var lastEnd = 0.0

    for m in 0..<matchCount {
      let e = Int(aligner.matchE[m])
      let s = Int(aligner.matchS[m])
      if m > 0 {
        let previousE = Int(aligner.matchE[m - 1])
        let gap = e - previousE - 1
        if gap > 0 {
          let from = lastEnd
          let to = max(sStart[s], from)
          let span = to - from
          let plausible: Bool
          if gap <= 3 {
            plausible = span <= 15
          } else {
            let rate = Double(gap) / max(span, 0.001)
            plausible = span <= 120 && rate >= 0.3 && rate <= 9
          }
          if plausible {
            let weights = ((previousE + 1)..<e).map { Double(max(1, index.words[$0].normalized.count) + 2) }
            let total = weights.reduce(0, +)
            // Je Wort höchstens so lange wie gesprochen plausibel; der Rest ist eine Pause (Atempause,
            // Satzende) und wird nicht über die Wörter verschmiert — sonst läuft die Markierung hinterher.
            let lengths = weights.map { weight in
              min(span * weight / total, Self.maxFilledWordSeconds * max(1, weight / Self.referenceWordWeight))
            }
            var pause = span - lengths.reduce(0, +)
            if pause < Self.minimumFilledPauseSeconds { pause = 0 }
            let pauseBefore =
              pause > 0 ? Self.pauseSlot(afterWord: previousE, gap: weights.count, index: index) : weights.count
            var cursor = from
            for (offset, length) in lengths.enumerated() {
              if offset == pauseBefore { cursor += pause }
              outWords.append(Int32(previousE + 1 + offset))
              outStarts.append(Float(cursor))
              outEnds.append(Float(cursor + length))
              outFlags.append(0)
              cursor += length
            }
            if pauseBefore == weights.count { cursor += pause }
            lastEnd = cursor
          }
        }
      }
      let start = max(sStart[s], lastEnd)
      let end = max(sEnd[s], start + 0.02)
      outWords.append(Int32(e))
      outStarts.append(Float(start))
      outEnds.append(Float(end))
      outFlags.append(1)
      lastEnd = end
    }

    return EbookTrackAlignment(
      ebookWordCount: index.words.count, spokenWordCount: input.count, spokenEnd: spokenEnd,
      words: outWords, starts: outStarts, ends: outEnds, flags: outFlags)
  }

  /// Indizes einer längsten streng aufsteigenden Teilfolge (O(n log n)).
  static func longestIncreasingSubsequence(_ values: [Int]) -> [Int] {
    var tails: [Int] = []
    var previous = [Int](repeating: -1, count: values.count)
    for i in values.indices {
      var low = 0
      var high = tails.count
      while low < high {
        let mid = (low + high) / 2
        if values[tails[mid]] < values[i] { low = mid + 1 } else { high = mid }
      }
      if low > 0 { previous[i] = tails[low - 1] }
      if low == tails.count { tails.append(i) } else { tails[low] = i }
    }
    var result: [Int] = []
    var k = tails.last ?? -1
    while k >= 0 {
      result.append(k)
      k = previous[k]
    }
    return result.reversed()
  }
}

// MARK: - Lückenfüllung

/// Füllt den Bereich zwischen zwei Fixpunkten: kleine Lücken per LCS, große rekursiv über Wörter, die
/// in beiden Bereichen genau einmal vorkommen (wie „patience diff"). Treffer entstehen immer in
/// aufsteigender Reihenfolge.
nonisolated private struct GapAligner {
  let index: EbookReadAlongIndex
  let sIds: [Int32]
  let sNorm: [String]
  var matchE: [Int32] = []
  var matchS: [Int32] = []

  private static let lcsCellLimit = 250_000
  private static let maxDepth = 12

  init(index: EbookReadAlongIndex, sIds: [Int32], sNorm: [String]) {
    self.index = index
    self.sIds = sIds
    self.sNorm = sNorm
  }

  mutating func add(_ e: Int, _ s: Int) {
    guard index.words.indices.contains(e), sIds.indices.contains(s) else { return }
    if let lastE = matchE.last, let lastS = matchS.last, Int32(e) <= lastE || Int32(s) <= lastS { return }
    matchE.append(Int32(e))
    matchS.append(Int32(s))
  }

  /// Ab dieser Länge zählt ein gemeinsamer Wortstamm als Treffer — die Erkennung trifft Endungen oft nicht.
  private static let stemMinimumLength = 4

  mutating func fill(eLo: Int, eHi: Int, sLo: Int, sHi: Int, depth: Int) {
    let n = eHi - eLo
    let m = sHi - sLo
    guard n > 0, m > 0 else { return }
    // Völlig unterschiedlich lange Bereiche gehören nicht zusammen (Kapitel fehlt, Vorwort nur im Ton).
    guard n <= 8 * m + 24, m <= 8 * n + 24 else { return }
    if n * m <= Self.lcsCellLimit {
      lcs(eLo: eLo, n: n, sLo: sLo, m: m)
      return
    }
    guard depth < Self.maxDepth else { return }

    var ebookCount: [Int32: Int] = [:]
    var ebookPosition: [Int32: Int] = [:]
    for e in eLo..<eHi {
      let id = index.ids[e]
      ebookCount[id, default: 0] += 1
      ebookPosition[id] = e
    }
    var spokenCount: [Int32: Int] = [:]
    for s in sLo..<sHi where sIds[s] >= 0 { spokenCount[sIds[s], default: 0] += 1 }
    var pairs: [(e: Int, s: Int)] = []
    for s in sLo..<sHi {
      let id = sIds[s]
      guard id >= 0, spokenCount[id] == 1, ebookCount[id] == 1, let e = ebookPosition[id] else { continue }
      pairs.append((e, s))
    }
    guard !pairs.isEmpty else { return }

    var previousE = eLo
    var previousS = sLo
    for i in EbookAlignmentBuilder.longestIncreasingSubsequence(pairs.map(\.e)) {
      let pair = pairs[i]
      fill(eLo: previousE, eHi: pair.e, sLo: previousS, sHi: pair.s, depth: depth + 1)
      add(pair.e, pair.s)
      previousE = pair.e + 1
      previousS = pair.s + 1
    }
    fill(eLo: previousE, eHi: eHi, sLo: previousS, sHi: sHi, depth: depth + 1)
  }

  /// Treffer: gleiche Wort-ID oder (beide ab `stemMinimumLength` Zeichen) gemeinsamer Wortstamm.
  /// Längen und Treffer werden je Lücke einmal vorberechnet — nicht in jeder Tabellenzelle zweimal.
  private mutating func lcs(eLo: Int, n: Int, sLo: Int, m: Int) {
    let eLong = (0..<n).map { index.words[eLo + $0].normalized.count >= Self.stemMinimumLength }
    let sLong = (0..<m).map { sNorm[sLo + $0].count >= Self.stemMinimumLength }
    var matches = [Bool](repeating: false, count: n * m)
    for i in 0..<n {
      let e = eLo + i
      let eId = index.ids[e]
      for j in 0..<m {
        let s = sLo + j
        if sIds[s] >= 0, sIds[s] == eId {
          matches[i * m + j] = true
        } else if eLong[i], sLong[j] {
          let a = index.words[e].normalized
          let b = sNorm[s]
          matches[i * m + j] = a.hasPrefix(b) || b.hasPrefix(a)
        }
      }
    }

    let width = m + 1
    var table = [UInt16](repeating: 0, count: (n + 1) * width)
    for i in stride(from: n - 1, through: 0, by: -1) {
      for j in stride(from: m - 1, through: 0, by: -1) {
        table[i * width + j] =
          matches[i * m + j]
          ? table[(i + 1) * width + j + 1] + 1
          : max(table[(i + 1) * width + j], table[i * width + j + 1])
      }
    }
    var i = 0
    var j = 0
    while i < n, j < m {
      if matches[i * m + j], table[i * width + j] == table[(i + 1) * width + j + 1] + 1 {
        add(eLo + i, sLo + j)
        i += 1
        j += 1
      } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
        i += 1
      } else {
        j += 1
      }
    }
  }
}

// MARK: - Speicher

/// Hält die Abgleiche im Speicher, lädt/schreibt sie je Track und rechnet nur bei geändertem
/// Transkript oder eBook neu. Gültigkeit im Speicher hängt am Stempel der Transkriptdatei (Größe +
/// Änderungszeit) — ein unverändertes Transkript wird nicht erneut dekodiert. Die Arbeit läuft im
/// Hintergrund, aber mit `.userInitiated`: sie hängt immer an einem Knopfdruck.
@MainActor
final class EbookAlignmentStore {
  static let shared = EbookAlignmentStore()

  nonisolated private struct Entry: Sendable {
    let lookup: EbookTrackLookup
    let stamp: PlayerTranscriptFileStamp
  }

  private var entries: [String: Entry] = [:]
  private var inflight: [String: Task<Entry?, Never>] = [:]

  private func key(bookId: String, trackIndex: Int, locale: Locale, index: EbookReadAlongIndex) -> String {
    "\(bookId)|\(trackIndex)|\(locale.identifier(.bcp47))|\(index.words.count)"
  }

  /// Abgleich eines Tracks samt Abdeckung seines Transkripts. `nil` ohne Transkript.
  func lookup(
    forTrack trackIndex: Int,
    bookId: String,
    locale: Locale,
    index: EbookReadAlongIndex
  ) async -> EbookTrackLookup? {
    let key = key(bookId: bookId, trackIndex: trackIndex, locale: locale, index: index)
    if let running = inflight[key] { return await running.value?.lookup }

    let account = PlayerTranscriptCacheStore.activeAccount
    let localeId = locale.identifier(.bcp47)
    let previous = entries[key]
    let task = Task.detached(priority: .userInitiated) { () -> Entry? in
      Self.refresh(
        previous: previous, account: account, bookId: bookId, trackIndex: trackIndex,
        localeId: localeId, index: index)
    }
    inflight[key] = task
    let result = await task.value
    inflight[key] = nil
    entries[key] = result
    return result?.lookup
  }

  /// Stempel unverändert → bisheriger Eintrag (nur ein `stat`); sonst Transkript laden und den
  /// gespeicherten Abgleich prüfen bzw. neu berechnen.
  nonisolated private static func refresh(
    previous: Entry?,
    account: URL?,
    bookId: String,
    trackIndex: Int,
    localeId: String,
    index: EbookReadAlongIndex
  ) -> Entry? {
    guard
      let stamp = PlayerTranscriptCacheStore.transcriptStamp(
        account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId)
    else { return nil }
    if let previous, previous.stamp == stamp { return previous }
    guard
      let loaded = PlayerTranscriptCacheStore.loadStamped(
        account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId)
    else { return nil }
    let cached = loaded.cache.allWords
    guard !cached.isEmpty else { return nil }
    let input = cached.map { AlignmentInputWord(text: $0.t, start: $0.s, end: $0.e) }
    let alignment = loadOrBuild(
      account: account, bookId: bookId, trackIndex: trackIndex, localeId: localeId,
      words: input, index: index)
    let coverage = EbookTranscriptCoverage(
      spans: loaded.cache.segments.map { EbookTranscriptCoverage.Span(start: $0.start, end: $0.end) })
    return Entry(lookup: EbookTrackLookup(alignment: alignment, coverage: coverage), stamp: loaded.stamp)
  }

  nonisolated private static func loadOrBuild(
    account: URL?,
    bookId: String,
    trackIndex: Int,
    localeId: String,
    words: [AlignmentInputWord],
    index: EbookReadAlongIndex
  ) -> EbookTrackAlignment {
    if let data = PlayerTranscriptCacheStore.loadAlignment(
      account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId),
      let stored = EbookTrackAlignment(data: data),
      stored.ebookWordCount == index.words.count,
      stored.spokenWordCount == words.count,
      // Gleiche Wortzahl reicht nicht: ein neu erzeugtes Transkript (andere Zeiten) muss neu
      // abgeglichen werden. Das Ende des letzten Worts steht schon im Dateiformat.
      stored.spokenEnd == (words.last?.end ?? 0)
    {
      return stored
    }
    let built = EbookAlignmentBuilder.build(words: words, index: index)
    PlayerTranscriptCacheStore.saveAlignment(
      built.encoded(), account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId)
    return built
  }
}
