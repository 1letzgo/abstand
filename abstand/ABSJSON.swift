import Foundation

enum ABSJSON: Sendable {
  /// ISO-internes Datumsformat der Audiobookshelf-API (Millisekunden seit 1970).
  nonisolated static func applyAPIDateDecoding(_ decoder: JSONDecoder) {
    decoder.dateDecodingStrategy = .custom { dec in
      let c = try dec.singleValueContainer()
      let ms = try c.decode(Int64.self)
      return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
  }

  nonisolated static func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    applyAPIDateDecoding(d)
    return d
  }

  /// Hördaten-Endpunkt: manche Instanzen/Proxys liefern `snake_case`; gleiche Datumslogik wie `decoder()`.
  /// Wie `.convertFromSnakeCase`, aber die Keys direkt unter `items` sind Library-Item-IDs
  /// (`li_x_1`) und bleiben unverändert — sonst würden sie zu `liX1`.
  nonisolated static func decoderListeningStats() -> JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .custom { path in
      let raw = path.last?.stringValue ?? ""
      if path.count == 2, path[0].stringValue == "items" {
        return ABSJSONRawKey(stringValue: raw)
      }
      return ABSJSONRawKey(stringValue: convertFromSnakeCase(raw))
    }
    applyAPIDateDecoding(d)
    return d
  }

  /// Nachbau von `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` für einen einzelnen Key:
  /// führende/abschließende Unterstriche bleiben, erste Komponente unverändert, weitere `capitalized`.
  nonisolated static func convertFromSnakeCase(_ key: String) -> String {
    guard let first = key.firstIndex(where: { $0 != "_" }) else { return key }
    guard let lastNonUnderscore = key.lastIndex(where: { $0 != "_" }) else { return key }
    let core = key[first...lastNonUnderscore]
    guard core.contains("_") else { return key }
    let parts = core.split(separator: "_", omittingEmptySubsequences: true)
    var out = String(key[..<first])
    out += parts.first.map(String.init) ?? ""
    for part in parts.dropFirst() { out += part.capitalized }
    out += key[key.index(after: lastNonUnderscore)...]
    return out
  }

  nonisolated static func encoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .custom { date, enc in
      var c = enc.singleValueContainer()
      try c.encode(Int64(date.timeIntervalSince1970 * 1000))
    }
    return e
  }
}

/// Beliebiger String-Key für `.custom`-Key-Strategien.
struct ABSJSONRawKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}
