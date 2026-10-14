import Foundation

// Erzeugt shared/fixtures/alignment/unicode_tables.json aus Foundation-Verhalten:
// - wordRanges: Skalare, für die Character(s).isLetter || isNumber gilt
// - removedRanges: Skalare, deren normalize() leer ist
// - mapped: Skalar → normalize() wenn != Skalar selbst und nicht leer

func normalize(_ token: some StringProtocol) -> String {
  let folded = token.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
  let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
  return String(String.UnicodeScalarView(scalars))
}

var wordRanges: [[Int]] = []
var removedRanges: [[Int]] = []
var mapped: [String: String] = [:]

func appendRange(_ ranges: inout [[Int]], _ v: Int) {
  if let last = ranges.last, last[1] == v - 1 {
    ranges[ranges.count - 1][1] = v
  } else {
    ranges.append([v, v])
  }
}

let planes: [ClosedRange<Int>] = [0x0...0x3FFFF, 0xE0000...0xE01EF]
for plane in planes {
  for v in plane {
    if (0xD800...0xDFFF).contains(v) { continue }
    guard let scalar = Unicode.Scalar(v) else { continue }
    if scalar.properties.generalCategory == .unassigned { continue }
    let ch = Character(scalar)
    if ch.isLetter || ch.isNumber { appendRange(&wordRanges, v) }
    let n = normalize(String(scalar))
    if n.isEmpty {
      appendRange(&removedRanges, v)
    } else if n != String(scalar) || n.unicodeScalars.count != 1 || n.unicodeScalars.first!.value != UInt32(v) {
      mapped[String(v, radix: 16)] = n.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")
    }
  }
}

let out: [String: Any] = [
  "description": "Foundation reference (generated with Swift on macOS): wordRanges = Character.isLetter || isNumber per scalar; removedRanges = ReadAlongText.normalize(scalar) is empty; mapped = normalize(scalar) as hex scalars when it differs from the scalar. Only assigned scalars of planes 0-3 and E0000-E01EF.",
  "wordRanges": wordRanges,
  "removedRanges": removedRanges,
  "mapped": mapped,
]
let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
FileManager.default.createFile(atPath: CommandLine.arguments[1], contents: data)
print("word", wordRanges.count, "removed", removedRanges.count, "mapped", mapped.count)
