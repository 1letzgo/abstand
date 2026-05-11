import Foundation

/// Gespeichert neben den Track-Dateien (`download.json`), damit lokale Wiedergabe
/// dieselbe Track-Liste/Indizes wie der Download nutzt.
struct ABSDownloadManifest: Codable {
  static let filename = "download.json"

  /// Schema-Version für spätere Migrationen.
  let format: Int
  let libraryItemId: String
  /// Podcast-Folge (optional); Hörbücher ohne Folge = `nil`.
  let episodeId: String?
  /// Bibliotheks-ID zum Filtern / Anzeige (ohne API offline nutzbar).
  let libraryId: String?
  /// Anzeige aus dem Buch zum Zeitpunkt des Downloads (nicht vom Server geliefert).
  let displayTitle: String?
  let displayAuthor: String?
  let playSessionId: String?
  /// Sekunden seit 1970 (zuverlässiger als ISO8601-Strings zwischen Encoder/Decoder).
  let savedAtEpoch: TimeInterval
  /// Dateiendung der gespeicherten Tracks (z. B. `m4a`, `mp3`) ohne Punkt.
  let audioFileExtension: String?
  let totalDuration: Double?
  let tracks: [Track]

  struct Track: Codable {
    let index: Int
    let startOffset: Double
    let duration: Double
    let title: String?
  }

  enum CodingKeys: String, CodingKey {
    case format, libraryItemId, episodeId, libraryId, displayTitle, displayAuthor, playSessionId, savedAtEpoch, savedAt, audioFileExtension, totalDuration, tracks
  }

  init(
    format: Int,
    libraryItemId: String,
    episodeId: String? = nil,
    libraryId: String?,
    displayTitle: String?,
    displayAuthor: String?,
    playSessionId: String?,
    savedAtEpoch: TimeInterval,
    audioFileExtension: String?,
    totalDuration: Double?,
    tracks: [Track]
  ) {
    self.format = format
    self.libraryItemId = libraryItemId
    self.episodeId = episodeId
    self.libraryId = libraryId
    self.displayTitle = displayTitle
    self.displayAuthor = displayAuthor
    self.playSessionId = playSessionId
    self.savedAtEpoch = savedAtEpoch
    self.audioFileExtension = audioFileExtension
    self.totalDuration = totalDuration
    self.tracks = tracks
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    format = try c.decode(Int.self, forKey: .format)
    libraryItemId = try c.decode(String.self, forKey: .libraryItemId)
    episodeId = try c.decodeIfPresent(String.self, forKey: .episodeId)
    libraryId = try c.decodeIfPresent(String.self, forKey: .libraryId)
    displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
    displayAuthor = try c.decodeIfPresent(String.self, forKey: .displayAuthor)
    playSessionId = try c.decodeIfPresent(String.self, forKey: .playSessionId)
    if let epoch = try c.decodeIfPresent(TimeInterval.self, forKey: .savedAtEpoch) {
      savedAtEpoch = epoch
    } else if let s = try c.decodeIfPresent(String.self, forKey: .savedAt) {
      let fmt = ISO8601DateFormatter()
      fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let d = fmt.date(from: s) {
        savedAtEpoch = d.timeIntervalSince1970
      } else {
        fmt.formatOptions = [.withInternetDateTime]
        savedAtEpoch = fmt.date(from: s)?.timeIntervalSince1970 ?? 0
      }
    } else {
      savedAtEpoch = 0
    }
    audioFileExtension = try c.decodeIfPresent(String.self, forKey: .audioFileExtension)
    totalDuration = try c.decodeIfPresent(Double.self, forKey: .totalDuration)
    tracks = try c.decode([Track].self, forKey: .tracks)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(format, forKey: .format)
    try c.encode(libraryItemId, forKey: .libraryItemId)
    try c.encodeIfPresent(episodeId, forKey: .episodeId)
    try c.encodeIfPresent(libraryId, forKey: .libraryId)
    try c.encodeIfPresent(displayTitle, forKey: .displayTitle)
    try c.encodeIfPresent(displayAuthor, forKey: .displayAuthor)
    try c.encodeIfPresent(playSessionId, forKey: .playSessionId)
    try c.encode(savedAtEpoch, forKey: .savedAtEpoch)
    try c.encodeIfPresent(audioFileExtension, forKey: .audioFileExtension)
    try c.encodeIfPresent(totalDuration, forKey: .totalDuration)
    try c.encode(tracks, forKey: .tracks)
  }

  static func load(from downloadRoot: URL) -> ABSDownloadManifest? {
    let url = downloadRoot.appendingPathComponent(filename)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(ABSDownloadManifest.self, from: data)
  }

  func write(to downloadRoot: URL) throws {
    let url = downloadRoot.appendingPathComponent(Self.filename)
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(self)
    try data.write(to: url, options: .atomic)
  }
}
