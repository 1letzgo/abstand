import Combine
import SwiftUI

/// `TabView` + `tabViewBottomAccessory` ohne `MainRootView`-Rebuilds — nur `FloatingAccessoryGate` + Sheet-Binding.
struct MainTabShellView<Content: View>: View {
  @ObservedObject var gate: FloatingAccessoryGate
  let chrome: FloatingPlayerChromeController
  @Binding var nowPlayingSheetPresented: Bool
  @ViewBuilder var content: () -> Content

  @State private var keyboardVisible = false

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
    // Nur bei geladenem Titel — sonst reserviert iOS 26 eine leere Accessory-Leiste.
    if gate.chromeVisible {
      content.tabViewBottomAccessory {
        FloatingAccessoryLayer(
          gate: gate,
          chrome: chrome,
          sheetPresented: sheetPresented,
          keyboardVisible: keyboardVisible
        )
      }
    } else {
      content
    }
  }
}
