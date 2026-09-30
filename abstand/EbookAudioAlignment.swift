import Foundation

// Abgleich Hörbuch ↔ eBook: genau eine Quelle der Wahrheit für „welches eBook-Wort wird wann gesprochen".
// Teleprompter, Read Along, Catch Up und „Go to ebook position" lesen nur noch diese Karte.
//
// Je Track wird das Transkript (Erkennung, mit Zeiten) global-monoton gegen das eBook ausgerichtet:
// eindeutige Trigramme als Fixpunkte (längste aufsteigende Teilfolge), Lücken rekursiv über eindeutige
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
  static let formatVersion: UInt32 = 1
  private static let magic: UInt32 = 0x4142_4C31

  /// Für die Gültigkeit der gespeicherten Datei: eBook und Transkript, mit denen gerechnet wurde.
  let ebookWordCount: Int
  let spokenWordCount: Int
  /// Ende des letzten erkannten Worts (lokale Sekunden) — dahinter gibt es noch kein Transkript.
  let spokenEnd: Double

  let words: [Int32]
  /// Lokale Track-Sekunden.
  let starts: [Float]
  let ends: [Float]
  /// 1 = direkt erkannt, 0 = zwischen erkannten Nachbarn verteilt.
  let flags: [UInt8]

  var isEmpty: Bool { words.isEmpty }

  static func empty(ebookWordCount: Int, spokenWordCount: Int, spokenEnd: Double) -> EbookTrackAlignment {
    EbookTrackAlignment(
      ebookWordCount: ebookWordCount, spokenWordCount: spokenWordCount, spokenEnd: spokenEnd,
      words: [], starts: [], ends: [], flags: [])
  }

  // MARK: Abfragen

  /// eBook-Wort, das zur Track-Zeit gesprochen wird. In einer Pause bleibt das letzte Wort stehen,
  /// nach längerer Lücke (nur im Hörbuch gesprochener Teil) gibt es keine Antwort.
  func ebookWord(atLocalTime time: Double, maxGap: Double = 3) -> Int? {
    guard !words.isEmpty else { return nil }
    var low = 0
    var high = words.count
    while low < high {
      let mid = (low + high) / 2
      if Double(starts[mid]) <= time { low = mid + 1 } else { high = mid }
    }
    guard low > 0 else { return nil }
    let i = low - 1
    guard time <= Double(ends[i]) + maxGap else { return nil }
    return Int(words[i])
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

// MARK: - Anzeige (Teleprompter)

/// eBook-Wörter eines Tracks in globaler Zeit plus die Zeitspannen, in denen der eBook-Text lückenlos
/// steht. Nur außerhalb dieser Spannen bleibt der Erkennungstext sichtbar.
nonisolated struct EbookDisplayWords {
  let words: [PlayerTranscriptWord]
  let spans: [(start: Double, end: Double)]
}

extension EbookTrackAlignment {
  nonisolated func displayWords(index: EbookReadAlongIndex, globalOffset: Double) -> EbookDisplayWords {
    var out: [PlayerTranscriptWord] = []
    out.reserveCapacity(words.count)
    var spans: [(start: Double, end: Double)] = []
    var previousPosition = -2
    for i in words.indices {
      let position = Int(words[i])
      guard index.words.indices.contains(position) else { continue }
      let start = globalOffset + Double(starts[i])
      let end = globalOffset + Double(ends[i])
      out.append(
        PlayerTranscriptWord(
          id: "e-\(position)", text: index.words[position].display, globalStart: start, globalEnd: end))
      if position == previousPosition + 1, !spans.isEmpty {
        spans[spans.count - 1].end = end
      } else {
        spans.append((start, end))
      }
      previousPosition = position
    }
    return EbookDisplayWords(words: out, spans: spans)
  }
}

// MARK: - Berechnung

nonisolated enum EbookAlignmentBuilder {
  /// Mindestanzahl erkannter Wörter und Anteil am Transkript, damit der Abgleich als verlässlich gilt.
  private static let minimumMatches = 12
  private static let minimumMatchRatio = 0.2

  static func build(words input: [AlignmentInputWord], index: EbookReadAlongIndex) -> EbookTrackAlignment {
    let spokenEnd = input.last?.end ?? 0
    let empty = EbookTrackAlignment.empty(
      ebookWordCount: index.words.count, spokenWordCount: input.count, spokenEnd: spokenEnd)
    guard !index.isEmpty, input.count >= 8 else { return empty }

    // Erkannte Wörter in eBook-Tokens zerlegen („don't" → „don", „t"), Zeit anteilig verteilen.
    var sNorm: [String] = []
    var sStart: [Double] = []
    var sEnd: [Double] = []
    sNorm.reserveCapacity(input.count)
    for word in input {
      let tokens = ReadAlongText.words(in: word.text)
      guard !tokens.isEmpty else { continue }
      let duration = max(0, word.end - word.start)
      let share = duration / Double(tokens.count)
      for (offset, token) in tokens.enumerated() {
        sNorm.append(token.word)
        sStart.append(word.start + share * Double(offset))
        sEnd.append(word.start + share * Double(offset + 1))
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
    var anchors: [(e: Int, s: Int)] = []
    for i in 0..<(n - 2) {
      let key = keys[i]
      guard firstPosition[key] == i, let positions = index.trigrams[key], positions.count == 1 else { continue }
      let e = positions[0]
      guard e + 2 < index.ids.count,
        sIds[i] >= 0, sIds[i] == index.ids[e],
        sIds[i + 1] == index.ids[e + 1], sIds[i + 2] == index.ids[e + 2]
      else { continue }
      anchors.append((e, i))
    }
    guard !anchors.isEmpty else { return empty }

    // 2. Globale Ordnung: längste aufsteigende Teilfolge — Zufallstreffer fallen heraus.
    let chain = longestIncreasingSubsequence(anchors.map(\.e)).map { anchors[$0] }

    // 3. Kleine Inseln (unplausibles Tempo zum Nachbarn, weniger als drei Anker) verwerfen.
    var clusters: [[(e: Int, s: Int)]] = []
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
      for k in 0..<3 { aligner.add(anchor.e + k, anchor.s + k) }
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
            var cursor = from
            for (offset, weight) in weights.enumerated() {
              let length = span * weight / total
              outWords.append(Int32(previousE + 1 + offset))
              outStarts.append(Float(cursor))
              outEnds.append(Float(cursor + length))
              outFlags.append(0)
              cursor += length
            }
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

  /// Gleich oder (ab 4 Zeichen) gemeinsamer Wortstamm — die Erkennung trifft Endungen oft nicht.
  private func wordsMatch(_ e: Int, _ s: Int) -> Bool {
    if sIds[s] >= 0, sIds[s] == index.ids[e] { return true }
    let a = index.words[e].normalized
    let b = sNorm[s]
    guard a.count >= 4, b.count >= 4 else { return false }
    return a.hasPrefix(b) || b.hasPrefix(a)
  }

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

  private mutating func lcs(eLo: Int, n: Int, sLo: Int, m: Int) {
    let width = m + 1
    var table = [UInt16](repeating: 0, count: (n + 1) * width)
    for i in stride(from: n - 1, through: 0, by: -1) {
      for j in stride(from: m - 1, through: 0, by: -1) {
        table[i * width + j] =
          wordsMatch(eLo + i, sLo + j)
          ? table[(i + 1) * width + j + 1] + 1
          : max(table[(i + 1) * width + j], table[i * width + j + 1])
      }
    }
    var i = 0
    var j = 0
    while i < n, j < m {
      if wordsMatch(eLo + i, sLo + j), table[i * width + j] == table[(i + 1) * width + j + 1] + 1 {
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
/// Transkript oder eBook neu. Die Berechnung läuft im Hintergrund.
@MainActor
final class EbookAlignmentStore {
  static let shared = EbookAlignmentStore()

  private struct Entry {
    let alignment: EbookTrackAlignment
    let validatedAt: Date
  }

  private var entries: [String: Entry] = [:]
  private var inflight: [String: Task<EbookTrackAlignment?, Never>] = [:]

  private func key(bookId: String, trackIndex: Int, locale: Locale, index: EbookReadAlongIndex) -> String {
    "\(bookId)|\(trackIndex)|\(locale.identifier(.bcp47))|\(index.words.count)"
  }

  /// Abgleich eines Tracks aus den gespeicherten Transkripten. `maxAge`: so lange gilt ein
  /// Speicher-Treffer, ohne das Transkript erneut von der Platte zu prüfen.
  func alignment(
    forTrack trackIndex: Int,
    bookId: String,
    locale: Locale,
    index: EbookReadAlongIndex,
    maxAge: TimeInterval
  ) async -> EbookTrackAlignment? {
    let key = key(bookId: bookId, trackIndex: trackIndex, locale: locale, index: index)
    if let entry = entries[key], Date().timeIntervalSince(entry.validatedAt) < maxAge {
      return entry.alignment
    }
    if let running = inflight[key] { return await running.value }

    let account = PlayerTranscriptCacheStore.activeAccount
    let localeId = locale.identifier(.bcp47)
    let task = Task<EbookTrackAlignment?, Never> {
      let cached = await PlayerTranscriptLibrary.cachedWords(
        bookId: bookId, trackIndex: trackIndex, locale: locale)
      guard !cached.isEmpty else { return nil }
      let input = cached.map { AlignmentInputWord(text: $0.t, start: $0.s, end: $0.e) }
      return await Task.detached(priority: .utility) {
        Self.loadOrBuild(
          account: account, bookId: bookId, trackIndex: trackIndex, localeId: localeId,
          words: input, index: index)
      }.value
    }
    inflight[key] = task
    let result = await task.value
    inflight[key] = nil
    if let result { entries[key] = Entry(alignment: result, validatedAt: Date()) }
    return result
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
      stored.spokenWordCount == words.count
    {
      return stored
    }
    let built = EbookAlignmentBuilder.build(words: words, index: index)
    PlayerTranscriptCacheStore.saveAlignment(
      built.encoded(), account: account, bookId: bookId, trackIndex: trackIndex, localeIdentifier: localeId)
    return built
  }
}
