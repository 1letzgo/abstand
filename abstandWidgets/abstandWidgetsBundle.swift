import SwiftUI
import WidgetKit

/// Widget-Extension der App. Bisher nur die Live Activity des Sleep-Timers.
@main
struct AbstandWidgetsBundle: WidgetBundle {
  var body: some Widget {
    SleepTimerLiveActivity()
  }
}
