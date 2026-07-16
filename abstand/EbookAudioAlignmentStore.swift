import Foundation

/// Persistiert Alignment-Maps lokal neben dem E-Book-Cache (pro Account/User).
enum EbookAudioAlignmentStore {
  private static let fm = FileManager.default

  private static func alignmentsDir(account: URL, userId: String) -> URL {
    let u = account
      .appendingPathComponent("ebooks", isDirectory: true)
      .appendingPathComponent("alignments", isDirectory: true)
      .appendingPathComponent(userId, isDirectory: true)
    try? fm.createDirectory(at: u, withIntermediateDirectories: true)
    return u
  }

  private static func mapURL(account: URL, userId: String, libraryItemId: String) -> URL {
    alignmentsDir(account: account, userId: userId)
      .appendingPathComponent("\(libraryItemId).alignment.json", isDirectory: false)
  }

  static func load(
    account: URL?,
    userId: String?,
    libraryItemId: String
  ) -> EbookAudioAlignmentMap? {
    guard let account, let userId, !userId.isEmpty else { return nil }
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return nil }
    let url = mapURL(account: account, userId: userId, libraryItemId: id)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? ABSJSON.decoder().decode(EbookAudioAlignmentMap.self, from: data)
  }

  static func save(
    _ map: EbookAudioAlignmentMap,
    account: URL?,
    userId: String?
  ) throws {
    guard let account, let userId, !userId.isEmpty else { return }
    let url = mapURL(account: account, userId: userId, libraryItemId: map.libraryItemId)
    let data = try ABSJSON.encoder().encode(map)
    try data.write(to: url, options: .atomic)
  }

  static func invalidate(account: URL?, userId: String?, libraryItemId: String) {
    guard let account, let userId, !userId.isEmpty else { return }
    let id = libraryItemId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }
    let url = mapURL(account: account, userId: userId, libraryItemId: id)
    try? fm.removeItem(at: url)
  }

  /// File-Fingerprint für Cache-Invalidierung (Größe + mtime).
  static func fileFingerprint(url: URL) -> String {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let size = values?.fileSize ?? 0
    let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
    return "\(size)-\(Int(mtime.rounded()))"
  }

  static func audioFingerprint(trackURLs: [URL], trackOffsets: [Double]) -> String {
    var parts: [String] = []
    for (idx, url) in trackURLs.enumerated() {
      let offset = idx < trackOffsets.count ? trackOffsets[idx] : 0
      parts.append("\(idx):\(fileFingerprint(url: url))@\(String(format: "%.3f", offset))")
    }
    return parts.joined(separator: "|")
  }
}
