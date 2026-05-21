import SwiftUI

/// Unused placeholder; the app entry point is `abstandApp` → `MainRootView`.
struct ContentView: View {
  var body: some View {
    MainRootView(nowPlayingSheetPresented: .constant(false))
  }
}

#Preview {
  let model = AppModel()
  return ContentView()
    .environmentObject(model)
    .environmentObject(model.player)
}
