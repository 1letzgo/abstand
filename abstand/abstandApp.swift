import Combine
import SwiftUI
import UIKit
import os

@main
struct abstandApp: App {
  @StateObject private var model = AppModel.shared

  init() {
    let s = AppLog.launchSignposter.beginInterval("appInit")
    defer { AppLog.launchSignposter.endInterval("appInit", s) }
    AppTheme.configureTabBarAppearance()
    // Muss vor Ende des App-Starts registriert sein (BGTaskScheduler-Vorgabe).
    PlayerTranscriptPrefetcher.registerBackgroundTask()
    // Zwischendateien abgebrochener Downloads (CFNetworkDownload_*.tmp) wegräumen.
    Task.detached(priority: .background) { LocalStoreMaintenance.removeStaleDownloadTempFiles() }
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
          chrome: model.floatingChrome
        ) {
          MainRootView()
        }
        .equatable()
        // Vollbild-Player wie in Apple Music: wächst per Zoom-Transition aus dem Mini-Player im
        // `tabViewBottomAccessory` heraus und schrumpft beim Schließen wieder hinein. UIKit-Zoom statt
        // `.fullScreenCover` + `.navigationTransition(.zoom)`, weil nur dort Geste und Ausrichtung
        // einstellbar sind (siehe `NowPlayingZoomPresenter`). Der Presenter liegt außerhalb des
        // SwiftUI-Baums — `EnvironmentObject`s und Theme darum explizit setzen (`model.player` fehlte
        // früher → Absturz in Unteransichten mit `@EnvironmentObject private var player`).
        .background {
          NowPlayingZoomPresenter(
            isPresented: $nowPlayingSheetPresented,
            onDismissCompleted: { model.notifyNowPlayingSheetDismissCompleted() }
          ) {
            NowPlayingDetailView(seedFrom: model.player)
              .environmentObject(model)
              .environmentObject(model.player)
              // Wie am App-Root: ohne den Revision-Key rendern Theme-abhängige Views im Overlay nicht neu.
              .environment(\.appearanceThemeRevision, model.appearanceThemeRevision)
              .tint(model.appearanceAccentColor)
              .themeAccentFromAppModel(model)
          }
        }
        .onReceive(model.nowPlayingSheetRequests) { present in
          nowPlayingSheetPresented = present
        }
        .onChange(of: nowPlayingSheetPresented) { _, presented in
          model.player.setNowPlayingUIVisible(presented)
          model.isNowPlayingOverlayVisible = presented
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
      DebugLogCollector.shared.log(
        "scenePhase -> \(phase) isPlaying=\(model.player.isPlaying) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)"
      )
      if phase == .active {
        model.player.handleReturnToForeground()
        // Self-Heal: Podcast-Liste nachladen, falls während Sperre eine Folge beendet wurde
        // (oder die Liste leer gefallen ist), sonst bleibt der "New"-Bereich leer.
        model.applyPendingPodcastRefreshIfNeeded()
        // Cache-first: Listen stehen bereits aus der lokalen DB — hier nur die DB still
        // fortschreiben, wenn der letzte Server-Abgleich zu lange her ist.
        model.refreshCatalogsIfStaleOnForeground()
        // Transkript-Vorproduktion im Vordergrund fortsetzen.
        model.transcriptPrefetcher.scheduleIfNeeded()
      } else if phase == .background {
        // Nur Teleprompter beenden. Die Audio-Session bleibt unangetastet — iOS hält die
        // laufende Wiedergabe über `.playback` + `audio`-Background-Mode selbst am Leben.
        // `.inactive` bewusst ausgenommen: das feuert auch bei Control Center, App-Switcher
        // oder Anruf-Banner, wo die App gleich wieder aktiv ist.
        model.player.handleEnterBackground()
        // Vordergrund-Lauf beenden; Rest übernimmt iOS später am Strom (Hintergrundverarbeitung).
        model.transcriptPrefetcher.stop()
        model.transcriptPrefetcher.scheduleBackgroundProcessingIfNeeded()
      }
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
  static let debug = Logger(subsystem: subsystem, category: "debug")

  static let launchSignposter = OSSignposter(subsystem: subsystem, category: "Launch")
}
