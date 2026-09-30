import Combine
import SwiftUI

/// `TabView` + `tabViewBottomAccessory` ohne `MainRootView`-Rebuilds — nur `FloatingAccessoryGate` + Sheet-Binding.
/// `Equatable`: `AppRootContainer` beobachtet das ganze `AppModel` und würde die Hülle samt
/// Tab-Zubehör sonst bei jeder Model-Änderung neu aufbauen — das riss die Navigationsleiste
/// (Books-Dropdowns) mit. Der Inhalt (`MainRootView`) beobachtet das Model selbst und bleibt aktuell.
struct MainTabShellView<Content: View>: View, Equatable {
  @ObservedObject var gate: FloatingAccessoryGate
  let chrome: FloatingPlayerChromeController
  @Binding var nowPlayingSheetPresented: Bool
  @ViewBuilder var content: () -> Content

  @State private var keyboardVisible = false

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    MainActor.assumeIsolated {
      lhs.gate === rhs.gate && lhs.chrome === rhs.chrome
        && lhs.nowPlayingSheetPresented == rhs.nowPlayingSheetPresented
    }
  }

  var body: some View {
    // Auch offline normales Tab-Zubehör — Mini-Player wie im Online-Modus.
    content()
      .modifier(
        FloatingTabBottomAccessoryModifier(
          gate: gate,
          chrome: chrome,
          sheetPresented: nowPlayingSheetPresented,
          keyboardVisible: keyboardVisible
        )
      )
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
        keyboardVisible = true
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
        keyboardVisible = false
      }
  }
}

/// `tabViewBottomAccessory` nur bei geladenem Titel — sonst leere System-Leiste (iOS 26).
private struct FloatingTabBottomAccessoryModifier: ViewModifier {
  @ObservedObject var gate: FloatingAccessoryGate
  let chrome: FloatingPlayerChromeController
  let sheetPresented: Bool
  let keyboardVisible: Bool

  func body(content: Content) -> some View {
    // WICHTIG: `isEnabled:` (iOS 26.2) statt strukturellem `if gate.chromeVisible { … } else { content }`.
    // Der frühere Branch-Wechsel war ein `_ConditionalContent`-Identitätswechsel des KOMPLETTEN
    // TabView-Subtrees: Bei jedem `chromeVisible`-Flip (Playback-Start, `dismissPlayer` nach
    // „Mark as finished") zerstörte SwiftUI den alten Baum samt allen `@State`-Werten darunter —
    // `MainRootView.activatedTabs` fiel auf `[.start]` zurück, `lazyTabContent` renderte für den
    // gerade sichtbaren Tab nur noch `Color.clear` → weißer Screen auf allen Tabs, zeitversetzt
    // mit der Server-Antwort des Finish-Flows (dort kippt `chromeVisible` erst nach `authorize`).
    content.tabViewBottomAccessory(isEnabled: gate.chromeVisible && !keyboardVisible) {
      FloatingAccessoryLayer(
        gate: gate,
        chrome: chrome,
        sheetPresented: sheetPresented,
        keyboardVisible: keyboardVisible
      )
    }
  }
}
