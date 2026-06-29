import SwiftUI
import UIKit
import os

@main
struct abstandApp: App {
  @StateObject private var model = AppModel()

  init() {
    let s = AppLog.launchSignposter.beginInterval("appInit")
    defer { AppLog.launchSignposter.endInterval("appInit", s) }
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
    .onChange(of: scenePhase) { _, phase in
      // Nur im Vordergrund die Session setzen: Bei `.inactive` (z. B. Control Center,
      // Sperrbildschirm) erneutes `setCategory`/`setActive` kann die laufende Wiedergabe unterbrechen.
      if phase == .active {
        model.player.handleReturnToForeground()
      } else if phase == .background {
        model.player.disableTeleprompterIfNeeded()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.protectedDataWillBecomeUnavailableNotification
      )
    ) { _ in
      // Display aus / Gerät gesperrt — Teleprompter beenden, Wiedergabe läuft weiter.
      model.player.disableTeleprompterIfNeeded()
    }
    .alert("Connecting ABS Server", isPresented: serverConnectionAlertPresented) {
      Button("Go offline") {
        model.goOfflineDuringBootstrap()
      }
    }
  }

  /// Nur lesbar — Schließen über Bootstrap-Ende oder „Go offline“.
  private var serverConnectionAlertPresented: Binding<Bool> {
    Binding(
      get: { model.showsServerConnectionConnectingOverlay },
      set: { _ in }
    )
  }
}

/// Zentrale Logging- und Signpost-Infrastruktur (vgl. debugging-instruments-Skill).
/// `Logger`-Instanzen filterbar in Console.app nach Subsystem `de.letzgo.abstand`.
/// `OSSignposter` für Start-Pfad-Intervals — in Instruments sichtbar, Release-builds no-op.
enum AppLog {
  static let subsystem = "de.letzgo.abstand"

  static let bootstrap = Logger(subsystem: subsystem, category: "bootstrap")
  static let playback = Logger(subsystem: subsystem, category: "playback")
  static let downloads = Logger(subsystem: subsystem, category: "downloads")
  static let library = Logger(subsystem: subsystem, category: "library")
  static let appearance = Logger(subsystem: subsystem, category: "appearance")

  static let launchSignposter = OSSignposter(subsystem: subsystem, category: "Launch")
}
