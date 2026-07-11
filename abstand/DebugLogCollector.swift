import Foundation
import SwiftUI
import Combine

/// Temporärer In-Memory-Log-Puffer für die White-View-Diagnose.
/// Sammelt Log-Zeilen mit Zeitstempel; exportierbar als Text via Share-Sheet.
@MainActor
final class DebugLogCollector: ObservableObject {
  static let shared = DebugLogCollector()

  @Published private(set) var entries: [Entry] = []
  private let maxEntries = 500

  struct Entry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String
  }

  private init() {}

  func log(_ message: String) {
    let entry = Entry(timestamp: Date(), message: message)
    entries.append(entry)
    if entries.count > maxEntries {
      entries.removeFirst(entries.count - maxEntries)
    }
  }

  /// Kompletter Log als formatierter Text (für Export/Share).
  var exportText: String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return entries.map { e in
      "\(formatter.string(from: e.timestamp)) \(e.message)"
    }.joined(separator: "\n")
  }

  func clear() {
    entries.removeAll()
  }
}
