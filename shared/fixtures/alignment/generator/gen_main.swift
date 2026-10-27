// Golden-Generator: läuft den originalen iOS-Code (EbookAudioAlignment.swift, ReadAlongText aus
// EbookReadAlong.swift) gegen Fall-Eingaben und schreibt die erwarteten Ergebnisse.

struct PlayerTranscriptWord {
  let id: String
  let text: String
  let globalStart: Double
  let globalEnd: Double
}

struct LocText { let before: String?; let highlight: String?; let after: String? }

// Nachbau von EbookReadAlongIndex ohne Readium (Sentence trägt den Locator-Text statt Locator).
struct EbookReadAlongIndex {
  struct Sentence { let segment: Int; let text: LocText }
  struct Word { let normalized: String; let sentence: Int; let display: String }
  let sentences: [Sentence]
  let words: [Word]
  let trigrams: [Int: [Int]]
  let ids: [Int32]
  let vocabulary: [String: Int32]
  let uniquePositions: [Int32]
  var isEmpty: Bool { words.isEmpty }

  func uniquePosition(ofWordId id: Int32) -> Int? {
    guard uniquePositions.indices.contains(Int(id)) else { return nil }
    let position = uniquePositions[Int(id)]
    return position >= 0 ? Int(position) : nil
  }

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

  // Wie build(publication:): Segmente → Sätze (Bereiche des Tokenizers) → Wörter.
  static func build(segments: [(text: String, ranges: [Range<String.Index>])]) -> EbookReadAlongIndex {
    var sentences: [Sentence] = []
    var words: [Word] = []
    for (segIndex, seg) in segments.enumerated() {
      let segmentText = seg.text
      for range in seg.ranges {
        let sentenceText = String(segmentText[range])
        let tokens = ReadAlongText.words(in: sentenceText)
        guard !tokens.isEmpty else { continue }
        let sentenceIndex = sentences.count
        for (offset, token) in tokens.enumerated() {
          let start = offset == 0 ? sentenceText.startIndex : token.range.lowerBound
          let end = offset + 1 < tokens.count ? tokens[offset + 1].range.lowerBound : sentenceText.endIndex
          var display = String(sentenceText[start..<end])
          if offset + 1 == tokens.count, !(display.last?.isWhitespace ?? false) { display += " " }
          words.append(Word(normalized: token.word, sentence: sentenceIndex, display: display))
        }
        let contextLength = 40
        let after = String(segmentText[range.upperBound...].prefix(contextLength))
        let before = String(segmentText[..<range.lowerBound].suffix(contextLength))
        sentences.append(Sentence(segment: segIndex, text: LocText(
          before: before.isEmpty ? nil : before, highlight: String(segmentText[range]), after: after.isEmpty ? nil : after)))
      }
    }
    var trigrams: [Int: [Int]] = [:]
    if words.count >= 3 {
      for i in 0..<(words.count - 2) {
        let key = ReadAlongText.trigramKey(words[i].normalized, words[i + 1].normalized, words[i + 2].normalized)
        trigrams[key, default: []].append(i)
      }
    }
    var vocabulary: [String: Int32] = [:]
    var ids: [Int32] = []
    var uniquePositions: [Int32] = []
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

// Nachbau von EbookNarrationJumpController.performJump / chunkLocator (nur Text).
func narrationDecorations(index: EbookReadAlongIndex, end: Int) -> [[String: Any]] {
  guard let endSentence = index.sentenceIndex(forWord: end) else { return [] }
  let start = max(0, end - 25 + 1)
  guard let startSentence = index.sentenceIndex(forWord: start) else { return [] }
  var out: [[String: Any]] = []
  for sentence in startSentence...endSentence {
    let range = index.wordRange(ofSentence: sentence)
    let chunk = max(range.lowerBound, start)..<min(range.upperBound, end + 1)
    guard !chunk.isEmpty else { continue }
    let base = index.sentences[sentence].text
    let all = index.wordRange(ofSentence: sentence)
    let prefix = index.words[all.lowerBound..<chunk.lowerBound].map(\.display).joined()
    let suffix = index.words[chunk.upperBound..<all.upperBound].map(\.display).joined()
    let highlight = index.words[chunk].map(\.display).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    let after = String((suffix + (base.after ?? "")).prefix(40))
    let before = String(((base.before ?? "") + prefix).suffix(40))
    var d: [String: Any] = ["id": "recent-\(sentence)", "sentence": sentence, "wordStart": chunk.lowerBound, "wordEnd": chunk.upperBound, "highlight": highlight]
    d["before"] = before.isEmpty ? NSNull() : before
    d["after"] = after.isEmpty ? NSNull() : after
    out.append(d)
  }
  return out
}

func nullable(_ s: String?) -> Any { s ?? NSNull() }

// MARK: - Fälle

let args = CommandLine.arguments
let inputDir = args[1]
let outputDir = args[2]
let fm = FileManager.default
let files = try fm.contentsOfDirectory(atPath: inputDir).filter { $0.hasSuffix(".input.json") }.sorted()

for file in files {
  let data = try Data(contentsOf: URL(fileURLWithPath: inputDir + "/" + file))
  let input = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  let name = input["name"] as! String
  // eBook: Segmente als Satzlisten; Segmenttext = Sätze mit " " verbunden.
  let segmentsIn = input["segments"] as! [[String]]
  var segments: [(text: String, ranges: [Range<String.Index>])] = []
  var segmentsOut: [[String: Any]] = []
  for sentenceTexts in segmentsIn {
    let text = sentenceTexts.joined(separator: " ")
    var ranges: [Range<String.Index>] = []
    var utf16Ranges: [[Int]] = []
    var cursor = text.startIndex
    for (k, s) in sentenceTexts.enumerated() {
      let start = cursor
      let end = text.index(start, offsetBy: s.count)
      ranges.append(start..<end)
      utf16Ranges.append([text.utf16.distance(from: text.startIndex, to: start), text.utf16.distance(from: text.startIndex, to: end)])
      cursor = end
      if k + 1 < sentenceTexts.count { cursor = text.index(after: cursor) }
    }
    segments.append((text, ranges))
    segmentsOut.append(["text": text, "sentenceRanges": utf16Ranges])
  }
  let index = EbookReadAlongIndex.build(segments: segments)

  // Transkript: Sprechtext mit Pausen-Markern „|2.5|"; Zeit je Wort deterministisch aus der Länge.
  var transcript: [[String: Any]] = []
  var inputWords: [AlignmentInputWord] = []
  var t = input["startTime"] as? Double ?? 0
  for raw in (input["spoken"] as! String).split(separator: " ") {
    if raw.hasPrefix("|") && raw.hasSuffix("|") {
      t += Double(raw.dropFirst().dropLast())!
      continue
    }
    let text = String(raw).replacingOccurrences(of: "_", with: " ")
    let duration = ((0.22 + 0.045 * Double(text.count)) * 100).rounded() / 100
    let start = (t * 100).rounded() / 100
    let end = ((start + duration) * 100).rounded() / 100
    transcript.append(["t": text, "s": start, "e": end])
    inputWords.append(AlignmentInputWord(text: text, start: start, end: end))
    t = end + 0.08
  }

  let alignment = EbookAlignmentBuilder.build(words: inputWords, index: index)
  let encoded = alignment.encoded()
  let roundTrip = EbookTrackAlignment(data: encoded)!
  precondition(roundTrip.words == alignment.words)

  // Abfragen: alle 0,5 s über den Track plus etwas dahinter.
  var queries: [[String: Any]] = []
  var q = 0.0
  while q <= (inputWords.last?.end ?? 0) + 5 {
    queries.append([
      "t": q, "word": alignment.ebookWord(atLocalTime: q).map { $0 as Any } ?? NSNull(),
      "last": alignment.lastEbookWord(atOrBeforeLocalTime: q).map { $0 as Any } ?? NSNull(),
    ])
    q += 0.5
  }
  // Rückrichtung: Startzeit je eBook-Wort (nil außerhalb des ausgerichteten Bereichs).
  let wordTimes: [Any] = index.words.indices.map { alignment.localTime(forEbookWord: $0).map { $0 as Any } ?? NSNull() }
  let globalOffset = input["globalOffset"] as? Double ?? 0
  let display = alignment.displayWords(index: index, globalOffset: globalOffset)

  var jumps: [[String: Any]] = []
  for jt in (input["jumpTimes"] as? [Double] ?? []) {
    let word = alignment.ebookWord(atLocalTime: jt)
    jumps.append(["t": jt, "word": word.map { $0 as Any } ?? NSNull(),
                  "decorations": word.map { narrationDecorations(index: index, end: $0) } ?? []])
  }

  let out: [String: Any] = [
    "name": name,
    "description": input["description"] as! String,
    "generatedBy": "Swift (abstand iOS EbookAudioAlignment.swift / ReadAlongText, unchanged) via android/../shared fixture generator",
    "input": [
      "segments": segmentsOut,
      "transcript": transcript,
      "globalOffset": globalOffset,
    ],
    "expected": [
      "index": [
        "words": index.words.map { ["n": $0.normalized, "s": $0.sentence, "d": $0.display] },
        "sentences": index.sentences.map { ["segment": $0.segment, "before": nullable($0.text.before), "highlight": nullable($0.text.highlight), "after": nullable($0.text.after)] },
        "vocabularySize": index.vocabulary.count,
      ],
      "alignment": [
        "ebookWordCount": alignment.ebookWordCount,
        "spokenWordCount": alignment.spokenWordCount,
        "spokenEnd": alignment.spokenEnd,
        "words": alignment.words.map { Int($0) },
        "starts": alignment.starts.map { Double($0) },
        "ends": alignment.ends.map { Double($0) },
        "flags": alignment.flags.map { Int($0) },
        "binBase64": encoded.base64EncodedString(),
      ],
      "queries": queries,
      "wordTimes": wordTimes,
      "displayWords": display.words.map { ["id": $0.id, "text": $0.text, "start": $0.globalStart, "end": $0.globalEnd] },
      "displaySpans": display.spans.map { [$0.start, $0.end] },
      "narrationJumps": jumps,
    ],
  ]
  let json = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
  try json.write(to: URL(fileURLWithPath: outputDir + "/" + name + ".json"))
  print(name, "ebookWords", index.words.count, "spoken", inputWords.count, "aligned", alignment.words.count,
        "recognized", alignment.flags.filter { $0 == 1 }.count)
}

// MARK: - Tokenisierung

let tokenInputs: [String] = [
  "Hello, world!", "Don't stop — it's well-known.", "„Straße“, sagte Müller… und ging.", "ÆON Øre Łódź İstanbul ıi ﬁnal",
  "café cafe\u{301} naïve résumé", "x² ½ ① Ⅻ １２３ ٣", "ΣΑΣ ὈΔΥΣΣΕΎΣ", "Ѐ й ё", "क्षि नमस्ते", "ガ カ\u{3099} が",
  "日本語のテキスト", "가나다 ᄀ\u{1161}", "e\u{301}\u{327} a\u{20DD}b", "'quoted' \"double\" «guillemets»",
  "tab\tnewline\nCR\r\nend", "non\u{00A0}breaking thin\u{2009}space", "emoji 👍🏽 test 👨‍👩‍👧 ok", "🇩🇪🇫🇷 flags",
  "ŉ ǰ ẞ ß ſ µ", "\u{301}leading mark", "A\u{200D}B zwj", "1,000.50 3rd 4th", "l'été c'est", "O'Brien’s",
  "ⓐⓑ ™ ℃ ℌ", "Ǆ ǅ ǆ", "ᾳ ᾼ", "ﬀ ﬃ", "fe\u{FE0F}\u{3099}x", "Ⅰ ⅰ", "ÅNGSTRÖM Ångström",
]
var tokenCases: [[String: Any]] = []
for s in tokenInputs {
  let tokens = ReadAlongText.words(in: s).map { tok -> [String: Any] in
    ["word": tok.word,
     "start": s.utf16.distance(from: s.startIndex, to: tok.range.lowerBound),
     "end": s.utf16.distance(from: s.startIndex, to: tok.range.upperBound)]
  }
  tokenCases.append(["text": s, "normalized": ReadAlongText.normalize(s), "count": s.count, "tokens": tokens])
}
// Zufallsstrings aus heiklen Skalaren (deterministischer Generator).
var seed: UInt64 = 0x5EED
func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
var pool: [Unicode.Scalar] = []
let poolRanges: [ClosedRange<UInt32>] = [0x41...0x5A, 0x61...0x7A, 0xC0...0x17F, 0x300...0x36F, 0x370...0x3FF, 0x400...0x45F, 0x483...0x489, 0x591...0x5C7, 0x5D0...0x5EA, 0x900...0x97F, 0x1100...0x1112, 0x1161...0x1175, 0x11A8...0x11C2, 0xAC00...0xAC10, 0x3041...0x30FF, 0x1E00...0x1EFF, 0x1F00...0x1FFF, 0x20D0...0x20F0, 0xFE20...0xFE2F, 0xFB00...0xFB06, 0x2160...0x2188, 0x200C...0x200D, 0xFE0F...0xFE0F, 0x20...0x2F, 0x1C80...0x1C88, 0x130...0x131, 0x1E9E...0x1E9E, 0xE00...0xE5B, 0xFF10...0xFF5A, 0x2000...0x200A]
for r in poolRanges { for v in r { if let s = Unicode.Scalar(v), s.properties.generalCategory != .unassigned { pool.append(s) } } }
var randomCases: [[String: Any]] = []
for _ in 0..<4000 {
  let len = Int(next() % 7) + 1
  var sv = String.UnicodeScalarView()
  for _ in 0..<len { sv.append(pool[Int(next() % UInt64(pool.count))]) }
  let s = String(sv)
  let tokens = ReadAlongText.words(in: s).map { tok -> [Any] in
    [tok.word, s.utf16.distance(from: s.startIndex, to: tok.range.lowerBound), s.utf16.distance(from: s.startIndex, to: tok.range.upperBound)]
  }
  randomCases.append(["s": s.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "),
                      "n": ReadAlongText.normalize(s).unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "),
                      "c": s.count, "w": tokens])
}
let tokenOut: [String: Any] = [
  "description": "ReadAlongText.normalize / words(in:) / String.count from Swift Foundation. random: s/n = hex scalars, c = Character count, w = [word, utf16Start, utf16End].",
  "cases": tokenCases,
  "random": randomCases,
]
try JSONSerialization.data(withJSONObject: tokenOut, options: [.sortedKeys]).write(to: URL(fileURLWithPath: outputDir + "/tokenization.json"))
print("tokenization", tokenCases.count, randomCases.count)
