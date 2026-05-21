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
    // `tabViewBottomAccessory` immer am Baum lassen — sonst baut SwiftUI die ganze TabView neu,
    // sobald nach dem Start `activeBook` gesetzt wird (sichtbarer Flackern).
    content()
      .tabViewBottomAccessory {
        FloatingAccessoryLayer(
          gate: gate,
          chrome: chrome,
          sheetPresented: nowPlayingSheetPresented,
          keyboardVisible: keyboardVisible
        )
        .id("abstand-floating-player")
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
        keyboardVisible = true
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
        keyboardVisible = false
      }
  }
}
