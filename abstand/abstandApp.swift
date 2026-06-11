import SwiftUI

@main
struct abstandApp: App {
  @StateObject private var model = AppModel()

  init() {
    AppTheme.configureTabBarAppearance()
  }

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
  @Environment(\.colorScheme) private var systemColorScheme
  @Environment(\.scenePhase) private var scenePhase
  @State private var nowPlayingSheetPresented = false

  var body: some View {
    let _ = model.appearanceThemeRevision
    return Group {
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
            .tint(model.appearanceAccentColor)
            .themeAccentFromAppModel(model)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: model.nowPlayingSheetPresentationCounter) { _, _ in
          nowPlayingSheetPresented = true
        }
        .onChange(of: model.nowPlayingSheetDismissCounter) { _, _ in
          nowPlayingSheetPresented = false
        }
      } else {
        LoginView()
      }
    }
    .tint(model.appearanceAccentColor)
    .themeAccentFromAppModel(model)
    .environment(\.appearanceThemeRevision, model.appearanceThemeRevision)
    .background {
      AppThemeScreenBackground(ignoresSafeArea: true)
        .environmentObject(model)
    }
    .preferredColorScheme(model.preferredSwiftUIColorScheme)
    .onAppear {
      model.reapplyAppearance(systemColorScheme: systemColorScheme)
    }
    .onChange(of: systemColorScheme) { _, scheme in
      model.reapplyAppearance(systemColorScheme: scheme)
    }
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
    .alert(
      String(localized: "Connecting to Server", comment: "Bootstrap alert title"),
      isPresented: bootstrapConnectingAlertPresented
    ) {
      Button(String(localized: "Go offline", comment: "Bootstrap alert offline action")) {
        model.goOfflineDuringBootstrap()
      }
    }
  }

  /// Nur lesbar — Schließen erfolgt über Bootstrap-Ende oder „Go offline“.
  private var bootstrapConnectingAlertPresented: Binding<Bool> {
    Binding(
      get: { model.isLoggedIn && model.isAppBootstrapInProgress },
      set: { _ in }
    )
  }
}
