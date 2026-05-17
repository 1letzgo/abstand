import Foundation

/// Preset cron schedules for Audiobookshelf `autoDownloadSchedule` (5-field cron).
enum PodcastAutoDownloadInterval: String, CaseIterable, Identifiable, Equatable {
  case everyHour
  case every6Hours
  case every12Hours
  case daily
  case weekly

  var id: String { rawValue }

  var label: String {
    switch self {
    case .everyHour: "Every hour"
    case .every6Hours: "Every 6 hours"
    case .every12Hours: "Every 12 hours"
    case .daily: "Daily"
    case .weekly: "Weekly"
    }
  }

  var cronExpression: String {
    switch self {
    case .everyHour: "0 * * * *"
    case .every6Hours: "0 */6 * * *"
    case .every12Hours: "0 */12 * * *"
    case .daily: "0 0 * * *"
    case .weekly: "0 0 * * 1"
    }
  }

  static let `default` = PodcastAutoDownloadInterval.daily

  static func from(cron: String?) -> PodcastAutoDownloadInterval {
    let normalized = normalizeCron(cron)
    if let match = allCases.first(where: { $0.cronExpression == normalized }) {
      return match
    }
    let parts = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
    guard parts.count >= 5 else { return .default }
    let dom = parts[2]
    let month = parts[3]
    let dow = parts[4]
    if dom == "*", month == "*", dow == "*" { return .daily }
    if dom == "*", month == "*", dow != "*" { return .weekly }
    if parts[1] == "*" { return .everyHour }
    if parts[1].hasPrefix("*/6") { return .every6Hours }
    if parts[1].hasPrefix("*/12") { return .every12Hours }
    return .default
  }

  private static func normalizeCron(_ cron: String?) -> String {
    cron?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ") ?? ""
  }
}
