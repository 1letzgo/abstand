import Combine
import Foundation

/// Ergebnis eines Online-Continue-Refreshs (Lazy-Bootstrap / Fallback-Entscheidung).
struct ContinueRefreshAttemptResult {
  var appliedOnline = false
  var error: Error?
  /// `true`, sobald `loadStartDashboard` tatsächlich einen Request gestartet hat
  /// (nicht nur früh per Cache/Guard zurückgekehrt ist). Wird gebraucht, um
  /// Server-Erreichbarkeit nicht ungeprüft aus einem übersprungenen Refresh abzuleiten.
  var attemptedNetwork = false
}

/// Abgebrochene Requests/Tasks nicht als Fehlerdialog anzeigen.
enum AbstandErrorFilter {
  static func isBenignCancellationMessage(_ message: String) -> Bool {
    let desc = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !desc.isEmpty else { return false }
    if desc == "cancelled" || desc == "canceled" { return true }
    if desc.contains("cancelled") || desc.contains("canceled") { return true }
    if desc.contains("error -999") { return true }
    return false
  }

  static func isBenignCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
    if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return true }
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error,
      isBenignCancellation(underlying)
    {
      return true
    }
    if isBenignCancellationMessage(error.localizedDescription) { return true }
    return false
  }

  /// Timeouts/Netz-Hiccups beim Kaltstart mit Cache — kein Fehlerdialog.
  static func isTransientNetworkError(_ error: Error) -> Bool {
    if let url = error as? URLError {
      switch url.code {
      case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed:
        return true
      default:
        break
      }
    }
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain,
      [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
       NSURLErrorCannotConnectToHost]
        .contains(ns.code)
    {
      return true
    }
    let desc = error.localizedDescription.lowercased()
    return desc.contains("timed out") || desc.contains("timeout")
  }
}

/// Laufende/abgeschlossene M4B-Encode-Jobs (Status selten; %-Fortschritt separat im ProgressStore).
struct ServerM4BEncodeJob: Identifiable, Equatable, Codable {
  enum Status: String, Codable, Equatable {
    case running
    case finished
    case failed
    case cancelled
  }

  var id: String
  var title: String
  var author: String
  var startedAt: Date
  var status: Status
  var message: String?

  var isActive: Bool { status == .running }
}

/// %-Updates für M4B-Encode — eigener ObservableObject, damit Book Detail nicht bei jedem Tick neu zeichnet.
@MainActor
final class M4BEncodeProgressStore: ObservableObject {
  @Published private(set) var percentById: [String: Double] = [:]
  private var lastPublishedWholePercent: [String: Int] = [:]

  func setPercent(id: String, percent: Double) {
    let whole = Int(min(100, max(0, percent)).rounded())
    if lastPublishedWholePercent[id] == whole { return }
    lastPublishedWholePercent[id] = whole
    var next = percentById
    next[id] = Double(whole)
    percentById = next
  }

  func percentLabel(for id: String) -> String? {
    guard let p = percentById[id] else { return nil }
    return "\(Int(p.rounded()))%"
  }

  func clear(id: String) {
    guard percentById[id] != nil || lastPublishedWholePercent[id] != nil else { return }
    var next = percentById
    next.removeValue(forKey: id)
    percentById = next
    lastPublishedWholePercent.removeValue(forKey: id)
  }

  func clearAll() {
    guard !percentById.isEmpty || !lastPublishedWholePercent.isEmpty else { return }
    percentById = [:]
    lastPublishedWholePercent = [:]
  }
}

