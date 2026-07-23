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

