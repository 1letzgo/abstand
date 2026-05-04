import SwiftUI

@main
struct abstandApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      AppRootContainer()
        .environmentObject(model)
    }
  }
}

private struct AppRootContainer: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if model.isLoggedIn {
        MainRootView()
      } else {
        LoginView()
      }
    }
    .preferredColorScheme(.dark)
    .task {
      await model.bootstrapFromStoredCredentials()
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        model.player.ensureAudioSessionForPlayback()
      case .inactive, .background:
        // Session erneut aktivieren, damit Streaming im Hintergrund nicht abreißt.
        if model.player.isPlaying {
          model.player.ensureAudioSessionForPlayback()
        }
      @unknown default:
        break
      }
    }
  }
}
