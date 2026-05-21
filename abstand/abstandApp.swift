import SwiftUI

@main
struct abstandApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      AppRootContainer()
        .environmentObject(model)
        .environmentObject(model.player)
    }
  }
}

private struct AppRootContainer: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var nowPlayingSheetPresented = false

  var body: some View {
    Group {
      if model.isLoggedIn {
        MainTabShellView(
          gate: model.floatingChrome.gate,
          chrome: model.floatingChrome,
          nowPlayingSheetPresented: $nowPlayingSheetPresented
        ) {
          MainRootView(nowPlayingSheetPresented: $nowPlayingSheetPresented)
        }
        .sheet(isPresented: $nowPlayingSheetPresented) {
          NowPlayingDetailView()
            .environmentObject(model)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: model.nowPlayingSheetPresentationCounter) { _, _ in
          nowPlayingSheetPresented = true
        }
      } else {
        LoginView()
      }
    }
    .preferredColorScheme(.dark)
    .task {
      await model.bootstrapFromStoredCredentials()
    }
    .onChange(of: scenePhase) { _, phase in
      // Nur im Vordergrund die Session setzen: Bei `.inactive` (z. B. Control Center,
      // Sperrbildschirm) erneutes `setCategory`/`setActive` kann die laufende Wiedergabe unterbrechen.
      if phase == .active {
        model.player.ensureAudioSessionForPlayback()
        model.player.refreshPlaybackStateFromEngine()
      }
    }
  }
}
