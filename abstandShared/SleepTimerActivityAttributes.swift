import ActivityKit
import AppIntents
import Foundation

// Gehört zu beiden Targets (App + Widget-Extension `abstandWidgets`): die App startet und
// aktualisiert die Live Activity, die Extension zeichnet sie.

/// Live Activity für den Sleep-Timer. Alles Veränderliche (auch Titel/Autor) steckt im
/// `ContentState` — so reicht bei einem Titelwechsel ein Update; ein neues `Activity.request`
/// wäre im Hintergrund gar nicht erlaubt.
struct SleepTimerActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var title: String
    var author: String?
    /// Zeit-Timer läuft: Wanduhr-Ende. Das System zählt selbst herunter (`Text(timerInterval:)`).
    var endDate: Date?
    /// Zeit-Timer eingefroren (Wiedergabe pausiert): feste Restzeit in Sekunden.
    var pausedRemaining: TimeInterval?
    /// Gesamtdauer für den Fortschrittsbalken (gewählte Minuten, mindestens die Restzeit).
    var totalSeconds: TimeInterval
    /// Kapitel-Timer: verbleibende Kapitel bis zum Stopp (1 = Ende des laufenden Kapitels).
    /// Positionsbasiert, daher bewusst ohne Countdown.
    var chaptersRemaining: Int?
    /// Wiedergabe läuft (für die Kapitel-Darstellung, die keine eigene Pause kennt).
    var isPlaying: Bool
  }
}

enum SleepTimerActivityAction: Sendable {
  case extend
  case cancel
}

enum SleepTimerActivityConstants {
  /// Verlängerung über den Button in der Live Activity.
  static let extendMinutes = 5
}

/// Brücke Intent → App. Die App (`PlaybackController`) setzt `handler`; in der Extension bleibt er
/// leer — `LiveActivityIntent`s laufen ohnehin im App-Prozess.
@MainActor
enum SleepTimerActivityActionHub {
  static var handler: ((SleepTimerActivityAction) -> Void)?

  static func perform(_ action: SleepTimerActivityAction) async {
    if let handler {
      handler(action)
      return
    }
    // Kein laufender Player (App wurde nur für den Intent gestartet): Die Activity gehört zu
    // keinem Timer mehr — wegräumen statt einen toten Button stehen zu lassen.
    for activity in Activity<SleepTimerActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}

struct ExtendSleepTimerIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Extend Sleep Timer"
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await SleepTimerActivityActionHub.perform(.extend)
    return .result()
  }
}

struct CancelSleepTimerIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Cancel Sleep Timer"
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await SleepTimerActivityActionHub.perform(.cancel)
    return .result()
  }
}
