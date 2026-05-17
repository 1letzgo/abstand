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
  nonisolated static func decoderListeningStats() -> JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    applyAPIDateDecoding(d)
    return d
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
