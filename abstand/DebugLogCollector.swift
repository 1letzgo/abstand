import Foundation

/// In-Memory-Log-Puffer für Felddiagnose (Export in Einstellungen → Server-Admin).
/// Bewusst auch im Release aktiv — TestFlight-Tester können den Log exportieren.
///
/// Kein `ObservableObject`/`@Published` mehr: `log()` läuft in heißen Pfaden
/// (Playback-Teardown, Track-Wechsel, Audio-Session) und darf dort keine
/// `objectWillChange`-Wellen auslösen. Die Export-View liest per Snapshot.
@MainActor
final class DebugLogCollector {
  static let shared = DebugLogCollector()

  /// Abschaltbar (z. B. künftig per Einstellung) — dank `@autoclosure` kostet ein
  /// deaktivierter Log-Aufruf dann nicht einmal den Aufbau der Message.
  var isCollecting = true

  private var buffer: [Entry] = []
  private let maxEntries = 500

  struct Entry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String
  }

  private init() {}

  func log(_ message: @autoclosure () -> String) {
    guard isCollecting else { return }
    buffer.append(Entry(timestamp: Date(), message: message()))
    if buffer.count > maxEntries {
      buffer.removeFirst(buffer.count - maxEntries)
    }
  }

  /// Snapshot für die Export-View (bewusst Kopie — kein Live-Binding an heiße Pfade).
  var entries: [Entry] { buffer }

  /// Kompletter Log als formatierter Text (für Export/Share).
  var exportText: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return buffer.map { e in
      "\(formatter.string(from: e.timestamp)) \(e.message)"
    }.joined(separator: "\n")
  }

  func clear() {
    buffer.removeAll()
  }
}
