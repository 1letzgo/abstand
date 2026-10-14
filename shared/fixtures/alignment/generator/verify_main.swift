struct PlayerTranscriptWord { let id: String; let text: String; let globalStart: Double; let globalEnd: Double }
struct EbookReadAlongIndex { struct Word { let display: String }; let words: [Word]; let ids: [Int32]; let vocabulary: [String: Int32]; let trigrams: [Int: [Int]]; var isEmpty: Bool { words.isEmpty } }

struct PlayerTranscriptTrackCache: Codable, Equatable {
  struct Word: Codable, Equatable { let t: String; let s: Double; let e: Double }
  struct Segment: Codable, Equatable { var start: Double; var end: Double; var words: [Word] }
  var version: Int
  var localeIdentifier: String
  var trackIndex: Int
  var segments: [Segment]
}

let dir = CommandLine.arguments[1]
let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/contents.json"))) as! [String: Any]
let exp = contents["alignment"] as! [String: Any]
let bin = try Data(contentsOf: URL(fileURLWithPath: dir + "/a3-en-US.bin"))
let a = EbookTrackAlignment(data: bin)!
precondition(a.ebookWordCount == exp["ebookWordCount"] as! Int)
precondition(a.spokenWordCount == exp["spokenWordCount"] as! Int)
precondition(a.spokenEnd == exp["spokenEnd"] as! Double)
precondition(a.words.map { Int($0) } == exp["words"] as! [Int])
precondition(a.starts == (exp["starts"] as! [Double]).map { Float($0) })
precondition(a.ends == (exp["ends"] as! [Double]).map { Float($0) })
precondition(a.flags.map { Int($0) } == exp["flags"] as! [Int])
precondition(a.encoded() == bin, "re-encode differs")
let t = try JSONDecoder().decode(PlayerTranscriptTrackCache.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/t3-en-US.json")))
let expT = try JSONDecoder().decode(PlayerTranscriptTrackCache.self, from: JSONSerialization.data(withJSONObject: contents["transcript"]!))
precondition(t == expT)
precondition(t.segments[0].words[3].t == "Straße")
import CryptoKit
let digest = SHA256.hash(data: Data((contents["bookId"] as! String).utf8)).map { String(format: "%02x", $0) }.joined()
precondition("transcripts/" + digest == contents["bookDirectory"] as! String)
print("iOS reads Kotlin transcript_cache fixtures identically")
