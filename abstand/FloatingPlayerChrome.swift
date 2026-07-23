import Combine
import Foundation
import SwiftUI

// MARK: - Player-Layout (SwiftUI-typische Komponenten)

private enum PlayerChromeLayout {
  static let miniBarMaxHeight: CGFloat = 56
  static let miniCover: CGFloat = 40
  /// Kompaktes Cover in `tabViewBottomAccessory` (System-Miniplayer-Größe).
  static let tabAccessoryCover: CGFloat = 32
}

/// Primärzeile Floating-Bar: „Show/Autor – Titel“. Bei Podcast-Folgen die Show, sonst Autor.
private func playerDashTitleLine(for book: ABSBook, secondaryLine: String?) -> String {
  let fallback = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
  let raw = secondaryLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  let a = (!raw.isEmpty && raw != "—") ? raw : fallback
  let t = book.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  if a.isEmpty || a == "—" { return t }
  return "\(a) – \(t)"
}

private func floatingBarPrimaryLine(
  for book: ABSBook,
  connecting: Bool,
  episodeShowTitle: String?
) -> String {
  let line = playerDashTitleLine(for: book, secondaryLine: episodeShowTitle)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  if !line.isEmpty, line != "—", line != "…" { return line }
  if connecting { return "Loading…" }
  return ""
}

/// Untertitel der Floating-Bar: nur Restzeit (kompakt, ohne Sekunden).
private func floatingBarRemainingSubtitle(total: Double, position: Double) -> String {
  formatPlaybackDurationShortHuman(max(0, total - position))
}
// MARK: - Tab bar accessory artwork (equatable: ignore high-frequency playback ticks)

private struct FloatingBarCoverEquatable: View, Equatable {
  var itemId: String
  var coverURL: URL?
  var coverToken: String
  var coverCacheAccount: URL?
  var coverRevision: Int

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.itemId == rhs.itemId && lhs.coverRevision == rhs.coverRevision
      && lhs.coverURL == rhs.coverURL && lhs.coverToken == rhs.coverToken
      && lhs.coverCacheAccount == rhs.coverCacheAccount
  }

  var body: some View {
    let side = PlayerChromeLayout.tabAccessoryCover
    let plateRadius = DetailHeroLayoutMetrics.coverCornerRadius
    CoverImageView(
      url: coverURL,
      token: coverToken,
      itemId: itemId,
      cacheAccount: coverCacheAccount,
      cacheRevision: coverRevision
    )
    .frame(width: side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: plateRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
        .strokeBorder(.quaternary, lineWidth: 0.5)
    }
  }
}

/// Ein Snapshot für die Tab-Bar — wie AudioBooth `MiniBookPlayer` (Equatable, keine Position-Ticks).
struct TabAccessoryMiniPlayerSnapshot: Equatable {
  let activeBookId: String?
  let coverRevision: Int
  let coverURL: URL?
  let coverToken: String
  let coverCacheAccount: URL?
  let primaryLine: String
  let subtitleText: String?
  /// Restzeit in ganzen Minuten — Snapshot ändert sich nur bei Minutenwechsel (nicht bei Position-Ticks).
  let remainingMinuteBucket: Int?
  let showsRestoringCover: Bool
  /// App-Start / `play`: noch kein `activeBook`, Verbindung oder Session wird aufgebaut.
  let showsConnectionLoading: Bool
  let isPlaying: Bool
  let isBuffering: Bool
  let canTogglePlayback: Bool
  let skipBackwardSeconds: Int

  static let hidden = TabAccessoryMiniPlayerSnapshot(
    activeBookId: nil,
    coverRevision: 0,
    coverURL: nil,
    coverToken: "",
    coverCacheAccount: nil,
    primaryLine: "",
    subtitleText: nil,
    remainingMinuteBucket: nil,
    showsRestoringCover: false,
    showsConnectionLoading: false,
    isPlaying: false,
    isBuffering: false,
    canTogglePlayback: false,
    skipBackwardSeconds: ABSPlaybackSkipDefaults.backwardSeconds
  )

  @MainActor
  static func make(model: AppModel) -> TabAccessoryMiniPlayerSnapshot {
    let player = model.player
    if player.showMiniPlayerPlaceholder, player.activeBook == nil, !model.isPlayerConnectionLoading {
      return .hidden
    }
    if let book = player.activeBook {
      let total = max(player.totalDuration, 1)
      let remainingSeconds = max(0, total - player.globalPosition)
      let caption = floatingBarRemainingSubtitle(total: total, position: player.globalPosition)
      let connecting = player.isBuffering || model.isPreparingPlayback
      let primaryLine = floatingBarPrimaryLine(
        for: book,
        connecting: connecting,
        episodeShowTitle: model.podcastEpisodeForActivePlayback()?.showTitle
      )
      guard !primaryLine.isEmpty else { return .hidden }
      return TabAccessoryMiniPlayerSnapshot(
        activeBookId: book.id,
        coverRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt),
        coverURL: model.coverURL(for: book.id),
        coverToken: model.token,
        coverCacheAccount: model.coverImageCacheAccountDirectory(),
        primaryLine: primaryLine,
        subtitleText: connecting ? "Loading…" : caption,
        remainingMinuteBucket: connecting ? nil : Int(remainingSeconds / 60),
        showsRestoringCover: connecting,
        showsConnectionLoading: false,
        isPlaying: player.isPlaying,
        isBuffering: player.isBuffering,
        canTogglePlayback: !model.isPlayerConnectionLoading && !connecting,
        skipBackwardSeconds: player.skipBackwardSeconds
      )
    }
    if model.isPlayerConnectionLoading {
      return TabAccessoryMiniPlayerSnapshot(
        activeBookId: nil,
        coverRevision: model.coverImageCacheRevision,
        coverURL: nil,
        coverToken: model.token,
        coverCacheAccount: model.coverImageCacheAccountDirectory(),
        primaryLine: "Loading…",
        subtitleText: nil,
        remainingMinuteBucket: nil,
        showsRestoringCover: true,
        showsConnectionLoading: true,
        isPlaying: false,
        isBuffering: false,
        canTogglePlayback: false,
        skipBackwardSeconds: player.skipBackwardSeconds
      )
    }
    return .hidden
  }
}

/// Sichtbarkeit + Mini-Player-Snapshot — entkoppelt von `AppModel` (vgl. AudioBooth `PlayerManager`).
@MainActor
final class FloatingAccessoryGate: ObservableObject {
  // Kein @Published — wir senden objectWillChange manuell, damit beide Felder
  // atomar in einem einzigen SwiftUI-Rebuild landen statt in zwei getrennten.
  private(set) var chromeVisible = false
  private(set) var snapshot = TabAccessoryMiniPlayerSnapshot.hidden

  fileprivate func apply(chromeVisible: Bool, snapshot: TabAccessoryMiniPlayerSnapshot) {
    guard chromeVisible != self.chromeVisible || snapshot != self.snapshot else { return }
    objectWillChange.send()
    self.chromeVisible = chromeVisible
    self.snapshot = snapshot
  }
}

/// Nur Player-relevante Updates — nicht an `AppModel.books`, Downloads, Suche, … gekoppelt.
@MainActor
final class FloatingPlayerChromeController: ObservableObject {
  let gate = FloatingAccessoryGate()

  private weak var model: AppModel?
  private var cancellables = Set<AnyCancellable>()
  private var lastOpenNowPlayingUptime: TimeInterval = 0

  func openNowPlaying() {
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastOpenNowPlayingUptime > 0.35 else { return }
    lastOpenNowPlayingUptime = now
    model?.requestPresentNowPlayingSheet()
  }

  func skipBackward() {
    guard let seconds = model?.player.skipBackwardSeconds else { return }
    model?.player.skip(seconds: -Double(seconds))
  }

  func togglePlayPause() {
    model?.player.togglePlayPause()
  }

  func dismissPlayback() {
    Task { await model?.dismissPlayer() }
  }

  func bind(model: AppModel) {
    self.model = model
    cancellables.removeAll()
    let player = model.player

    // Sofort: Play/Pause, Buchwechsel, Buffering/Verbindung (Loading-Zeile).
    Publishers.MergeMany(
      player.$activeBook.map { _ in () }.eraseToAnyPublisher(),
      player.$activePlaybackEpisodeId.map { _ in () }.eraseToAnyPublisher(),
      player.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
      player.$isBuffering.map { _ in () }.eraseToAnyPublisher(),
      player.$showMiniPlayerPlaceholder.map { _ in () }.eraseToAnyPublisher(),
      player.$skipBackwardSeconds.map { _ in () }.eraseToAnyPublisher(),
      player.$skipForwardSeconds.map { _ in () }.eraseToAnyPublisher(),
      model.$isRestoringLaunchPlayback.map { _ in () }.eraseToAnyPublisher(),
      model.$isPreparingPlayback.map { _ in () }.eraseToAnyPublisher(),
      model.$offlineHomeMode.map { _ in () }.eraseToAnyPublisher(),
      model.$offlineHomeModeAuto.map { _ in () }.eraseToAnyPublisher()
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] in self?.refresh() }
    .store(in: &cancellables)

    // Restzeit nur 1× pro Minute (keine Position-/Duration-Ticks).
    Timer.publish(every: 60, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        guard let self, model.player.activeBook != nil else { return }
        self.refresh()
      }
      .store(in: &cancellables)

    refresh()
  }

  /// Gate + Snapshot sofort aktualisieren (z. B. vor Launch-Readiness-Check).
  func syncChrome() {
    refresh()
  }

  private func refresh() {
    guard let model else { return }
    let wasVisible = gate.chromeVisible
    let next = TabAccessoryMiniPlayerSnapshot.make(model: model)
    let title = next.primaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasLoadedTitle =
      next.activeBookId != nil
      && !title.isEmpty
      && title != "Loading…"
      && !next.showsConnectionLoading
    // Mini-Player bleibt auch offline sichtbar — normale Tab-Struktur mit Downloads-Filter.
    let visible = hasLoadedTitle
    gate.apply(chromeVisible: visible, snapshot: next)
    if wasVisible != visible {
      DebugLogCollector.shared.log("chromeController.refresh VISIBILITY CHANGED wasVisible=\(wasVisible) -> visible=\(visible) activeBookId=\(next.activeBookId ?? "nil") objectWillChange sent")
      model.objectWillChange.send()
    }
  }
}

extension FloatingPlayerChromeController {
  var playbackController: PlaybackController? { model?.player }
}

/// `tabViewBottomAccessory` — stabiler Inhalt wie AudioBooth `MiniBookPlayer` (`.equatable()`).
struct FloatingAccessoryLayer: View {
  @ObservedObject var gate: FloatingAccessoryGate
  let chrome: FloatingPlayerChromeController
  let sheetPresented: Bool
  let keyboardVisible: Bool

  private var showsFloatingPlayer: Bool {
    gate.chromeVisible && !sheetPresented && !keyboardVisible && chrome.playbackController != nil
  }

  var body: some View {
    // Immer gemountet (nicht per `if`) — sonst misst der native `tabViewBottomAccessory`-Host
    // beim Wiedererscheinen (z. B. nach Schließen des Now-Playing-Sheets) kurz eine leere Breite
    // und schrumpft die Floatingbar auf iPad auf ein Minimum, statt volle Breite zu nutzen.
    TabAccessoryMiniPlayer(snapshot: gate.snapshot, chrome: chrome)
      .equatable()
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .opacity(showsFloatingPlayer ? 1 : 0)
      .allowsHitTesting(showsFloatingPlayer)
      .accessibilityHidden(!showsFloatingPlayer)
  }
}

/// Vorbild: [AudioBooth `MiniBookPlayer`](https://github.com/AudioBooth/AudioBooth/blob/main/AudioBooth/AudioBooth/Screens/BookPlayer/MiniBookPlayer.swift)
private struct TabAccessoryMiniPlayer: View, Equatable {
  let snapshot: TabAccessoryMiniPlayerSnapshot
  let chrome: FloatingPlayerChromeController

  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private static let rowMinHeight: CGFloat = 48
  private static let accessoryTransportSide: CGFloat = 44

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.snapshot == rhs.snapshot && lhs.themeRevision == rhs.themeRevision
  }

  private var horizontalPadding: CGFloat {
    horizontalSizeClass == .regular
      ? MiniPlayerMetrics.accessoryHorizontalPaddingRegular
      : MiniPlayerMetrics.accessoryHorizontalPaddingCompact
  }

  /// Direkt aus dem lokalen Cache, bevor der asynchrone Artwork-Loader die Player-Farbe setzt.
  private var backgroundTint: Color {
    guard let itemId = snapshot.activeBookId else { return model.player.miniPlayerBarFillColor }
    let scope = model.coverImageCacheScopeId(for: itemId, tier: .hero)
    return CoverDominantTintSeed.resolve(
      account: snapshot.coverCacheAccount,
      itemId: itemId,
      heroScopeId: scope,
      fallbackScopeId: itemId,
      revision: snapshot.coverRevision
    )?.tint ?? model.player.miniPlayerBarFillColor
  }

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Button {
        chrome.openNowPlaying()
      } label: {
        openRegionLabel
          .frame(maxWidth: .infinity, minHeight: Self.rowMinHeight, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .layoutPriority(1)
      .accessibilityLabel("Open now playing")
      .accessibilityHint("Shows the full player")

      if showsTransportControls {
        transportControls
          .fixedSize(horizontal: true, vertical: false)
      }
    }
    .frame(maxWidth: .infinity, minHeight: Self.rowMinHeight + 16, alignment: .center)
    .padding(.horizontal, horizontalPadding)
    .background(backgroundTint)
    .contentShape(Rectangle())
  }

  private var showsTransportControls: Bool {
    snapshot.canTogglePlayback
  }

  /// Nur Anzeige — Tap auf gesamte linke Fläche über umschließenden `Button` (`.plain`).
  private var openRegionLabel: some View {
    let _ = themeRevision
    return HStack(spacing: 0) {
      miniCover
      VStack(alignment: .leading, spacing: 2) {
        Text(snapshot.primaryLine)
          .font(.footnote)
          .fontWeight(.medium)
          .foregroundStyle(model.appearancePalette.textPrimary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let subtitle = snapshot.subtitleText {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(model.appearancePalette.textSecondary)
            .fontWeight(.medium)
            .lineLimit(1)
        }
      }
      .padding(.leading, 10)
      Spacer(minLength: 0)
    }
  }

  private var transportControls: some View {
    let _ = themeRevision
    let busy = snapshot.canTogglePlayback && snapshot.isBuffering
    let playWidth: CGFloat = 52
    let playHeight: CGFloat = 36
    return HStack(spacing: 8) {
      Button {
        chrome.skipBackward()
      } label: {
        Image(
          systemName: PlaybackController.gobackwardSystemImage(
            seconds: snapshot.skipBackwardSeconds))
          .font(.headline.weight(.medium))
          .foregroundStyle(model.appearancePalette.textPrimary)
          .frame(width: Self.accessoryTransportSide, height: Self.accessoryTransportSide)
          .contentShape(Rectangle())
      }
      .disabled(busy)
      .buttonStyle(.borderless)
      .accessibilityLabel(
        PlaybackController.skipAccessibilityLabel(
          backward: true, seconds: snapshot.skipBackwardSeconds))

      Button {
        chrome.togglePlayPause()
      } label: {
        ZStack {
          Capsule(style: .continuous)
            .fill(themeAccent)
            .frame(width: playWidth, height: playHeight)
          if busy {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(model.appearancePalette.foregroundOnAccent(themeAccent))
              .scaleEffect(0.72)
          } else {
            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(model.appearancePalette.foregroundOnAccent(themeAccent))
          }
        }
        .frame(width: Self.accessoryTransportSide, height: Self.accessoryTransportSide)
        .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(snapshot.isPlaying ? "Pause" : "Play")
    }
  }

  @ViewBuilder
  private var miniCover: some View {
    let side = PlayerChromeLayout.tabAccessoryCover
    let plateRadius = DetailHeroLayoutMetrics.coverCornerRadius
    if let id = snapshot.activeBookId {
      FloatingBarCoverEquatable(
        itemId: id,
        coverURL: snapshot.coverURL,
        coverToken: snapshot.coverToken,
        coverCacheAccount: snapshot.coverCacheAccount,
        coverRevision: snapshot.coverRevision
      )
      .contextMenu {
        Button(role: .destructive) {
          chrome.dismissPlayback()
        } label: {
          Label("Stop playback", systemImage: "xmark.circle")
        }
      }
    } else if snapshot.showsRestoringCover {
      RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
        .fill(.quaternary.opacity(0.5))
        .frame(width: side, height: side)
        .overlay { ProgressView() }
    } else {
      RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
        .fill(.quaternary.opacity(0.5))
        .frame(width: side, height: side)
        .overlay {
          Image(systemName: "waveform")
            .font(.caption2)
            .foregroundStyle(model.appearancePalette.textSecondary)
        }
    }
  }
}
