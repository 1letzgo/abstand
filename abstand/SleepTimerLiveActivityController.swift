import ActivityKit
import Foundation

/// Hält die Live Activity des Sleep-Timers (Sperrbildschirm, Dynamic Island) passend zum Timer in
/// `PlaybackController`. Der Player meldet nur den gewünschten Zustand (`nil` = kein Timer); Start,
/// Update und Ende entscheidet dieser Controller. Rührt weder Audio-Session noch Disk/Netz an.
@MainActor
final class SleepTimerLiveActivityController {
  static let shared = SleepTimerLiveActivityController()

  typealias State = SleepTimerActivityAttributes.ContentState

  /// Ab dieser Abweichung gilt ein laufendes Ende als geändert (Pause/Resume-Flattern erzeugt
  /// sonst Updates ohne sichtbaren Unterschied).
  private static let endDateTolerance: TimeInterval = 1
  /// So lange nach dem Timer-Ende gilt der Inhalt als veraltet, falls die App ihn nicht mehr
  /// selbst beenden konnte (Absturz) — die Activity zeigt dann „Ended" statt 0:00.
  private static let staleGraceSeconds: TimeInterval = 5

  private var activity: Activity<SleepTimerActivityAttributes>?
  private var lastState: State?
  /// Der Nutzer hat die Activity weggewischt oder das Starten schlug fehl: für diesen Timer nicht
  /// erneut anfordern. Wird zurückgesetzt, sobald der Timer endet.
  private var suppressedForCurrentTimer = false
  /// Aufrufe laufen strikt nacheinander (ActivityKit-Aufrufe sind `async`).
  private var pending: Task<Void, Never>?

  private init() {}

  /// Gewünschten Zustand anwenden. `nil` beendet jede Sleep-Timer-Activity — auch verwaiste aus
  /// einem früheren App-Lauf.
  func apply(_ state: State?) {
    let previous = pending
    pending = Task { @MainActor [weak self] in
      await previous?.value
      await self?.perform(state)
    }
  }

  private func perform(_ state: State?) async {
    guard let state else {
      suppressedForCurrentTimer = false
      await endAll()
      return
    }
    if let activity {
      switch activity.activityState {
      case .active, .stale, .pending:
        guard !Self.isSame(lastState, state) else { return }
        lastState = state
        await activity.update(Self.content(for: state))
        return
      case .dismissed, .ended:
        // Vom Nutzer entfernt oder vom System beendet — nicht eigenmächtig wieder einblenden.
        self.activity = nil
        lastState = nil
        suppressedForCurrentTimer = true
        return
      @unknown default:
        return
      }
    }
    guard !suppressedForCurrentTimer else { return }
    // Reste aus einem früheren App-Lauf gehören zu keinem laufenden Timer mehr.
    await endAll()
    // Live Activities systemweit oder für die App abgeschaltet: still nichts tun.
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    do {
      activity = try Activity.request(
        attributes: SleepTimerActivityAttributes(),
        content: Self.content(for: state),
        pushType: nil
      )
      lastState = state
    } catch {
      // Typisch: App nicht im Vordergrund (Timer-Neustart per Sperrbildschirm-Play). Kein Fehlerfall
      // für den Timer selbst — er läuft ohne Activity weiter.
      suppressedForCurrentTimer = true
    }
  }

  private func endAll() async {
    activity = nil
    lastState = nil
    for existing in Activity<SleepTimerActivityAttributes>.activities {
      await existing.end(nil, dismissalPolicy: .immediate)
    }
  }

  private static func content(for state: State) -> ActivityContent<State> {
    ActivityContent(
      state: state,
      staleDate: state.endDate?.addingTimeInterval(staleGraceSeconds)
    )
  }

  private static func isSame(_ lhs: State?, _ rhs: State) -> Bool {
    guard var lhs else { return false }
    if let a = lhs.endDate, let b = rhs.endDate, abs(a.timeIntervalSince(b)) < endDateTolerance {
      lhs.endDate = b
    }
    return lhs == rhs
  }
}
