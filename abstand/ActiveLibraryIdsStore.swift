import Foundation

/// Persistierte Aktivierung von Server-Libraries pro Medientyp (Primary bleibt separat).
enum ActiveLibraryIdsStore {
  static func encode(_ ids: [String]) -> Data? {
    let normalized = ids
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return try? ABSJSON.encoder().encode(normalized)
  }

  static func decode(_ data: Data?) -> [String] {
    guard let data,
      let ids = try? ABSJSON.decoder().decode([String].self, from: data)
    else { return [] }
    return ids
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
