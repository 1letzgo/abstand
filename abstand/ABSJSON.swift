import Foundation

enum ABSJSON: Sendable {
  nonisolated static func decoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { dec in
      let c = try dec.singleValueContainer()
      let ms = try c.decode(Int64.self)
      return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
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
