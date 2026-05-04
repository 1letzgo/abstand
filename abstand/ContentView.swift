import SwiftUI

/// Unused placeholder; the app entry point is `abstandApp` → `MainRootView`.
struct ContentView: View {
  var body: some View {
    MainRootView()
  }
}

#Preview {
  ContentView()
    .environmentObject(AppModel())
}
