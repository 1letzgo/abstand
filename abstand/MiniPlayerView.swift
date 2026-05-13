import AVKit
import SwiftUI
import UIKit

// MARK: - Abspielgeschwindigkeit (Label, locale Zahlenformat)

private func miniPlayerFormatPlaybackRate(_ rate: Float) -> String {
  let n = NSNumber(value: rate)
  let f = NumberFormatter()
  f.locale = Locale.autoupdatingCurrent
  f.minimumFractionDigits = 0
  f.maximumFractionDigits = 2
  f.numberStyle = .decimal
  let s = f.string(from: n) ?? String(format: "%g", rate)
  return "\(s)×"
}

// MARK: - Metriken (geteilt mit Bibliothekskarten-Buttons)

enum MiniPlayerMetrics {
  /// Bibliothekszeile: 76×76; Mini-Player-Cover = 1,5×
  static let coverSide: CGFloat = 76 * 1.5
  static let controlMinHeight: CGFloat = 30
  static let controlCorner: CGFloat = 7

  /// Mini-Player: ±Seek, Kapitel (ohne Play-Orb).
  static let miniPlayerTransportHeight: CGFloat = 44
  /// Schlummer / Tempo / AirPlay: eine flache Zeile mit Text.
  static let miniPlayerSecondaryRowHeight: CGFloat = 28
  /// Weicher Play-Kreis (Durchmesser); Zeilenhöhe richtet sich danach.
  static let miniPlayerPlayOrb: CGFloat = 52

  /// Eine Zeile: Sleep · Transport · AirPlay (Höhe = max(Transport, Play-Orb)).
  static var miniPlayerControlsTotalHeight: CGFloat {
    max(miniPlayerTransportHeight, miniPlayerPlayOrb)
  }
}


// MARK: - Player-Layout (SwiftUI-typische Komponenten)

private enum PlayerChromeLayout {
  static let miniBarMaxHeight: CGFloat = 56
  static let miniCover: CGFloat = 40
  /// Kompaktes Cover in `tabViewBottomAccessory` (System-Miniplayer-Größe).
  static let tabAccessoryCover: CGFloat = 32
  static let skipBackward: Double = 15
  static let skipForward: Double = 30
}

private func audiobookRemainingTimeCaption(total: Double, position: Double) -> String {
  formatPlaybackTime(max(0, total - position))
}

private func authorDashTitleLine(for book: ABSBook) -> String {
  let a = book.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
  let t = book.displayTitle
  if a.isEmpty || a == "—" { return t }
  return "\(a) – \(t)"
}

private func playbackProgressPercent(total: Double, position: Double) -> Int {
  let t = max(total, 1)
  let p = max(0, position)
  return min(100, max(0, Int((p / t * 100).rounded())))
}

private func remainingTimeDashPercent(total: Double, position: Double) -> String {
  let rem = audiobookRemainingTimeCaption(total: total, position: position)
  let pct = playbackProgressPercent(total: total, position: position)
  return "\(rem) – \(pct)%"
}

private struct FullPlayerAirPlayButton: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let v = AVRoutePickerView()
    v.prioritizesVideoDevices = false
    v.tintColor = .white
    v.activeTintColor = .white
    v.backgroundColor = .clear
    return v
  }

  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Vollansicht (Now Playing)

struct NowPlayingDetailView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  @State private var scrubLocal: Double?

  private var showIdlePlaceholder: Bool {
    model.player.showMiniPlayerPlaceholder && model.player.activeBook == nil
  }

  var body: some View {
    ZStack {
      fullPlayerBackground
        .accessibilityHidden(true)
        .ignoresSafeArea()

      Group {
        if verticalSizeClass == .compact {
          landscapeLayout
        } else {
          portraitLayout
        }
      }
      .padding(.top, 14)
    }
    .preferredColorScheme(.dark)
  }

  private var fullPlayerBackground: some View {
    let top = model.player.miniPlayerBarFillColor
    let dark = Color(white: 0.1)
    return LinearGradient(colors: [top, dark], startPoint: .top, endPoint: .bottom)
  }

  private var portraitLayout: some View {
    VStack(spacing: 0) {
      if let b = model.player.activeBook {
        Spacer(minLength: 8)
        fullPlayerArtwork(book: b)
        Spacer(minLength: 24)
        VStack(spacing: 32) {
          chapterTitleArea(book: b)
          playbackColumn(book: b)
        }
        .frame(maxWidth: 800)
        Spacer(minLength: 24)
        bottomUtilityBar
        Spacer(minLength: 8)
      } else if model.isRestoringLaunchPlayback {
        restoringPlaceholder
      } else if showIdlePlaceholder {
        idlePlaceholder
      }
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var landscapeLayout: some View {
    HStack(spacing: 24) {
      if let b = model.player.activeBook {
        fullPlayerArtwork(book: b)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          .containerRelativeFrame(.horizontal) { w, _ in w * 0.4 }
        VStack(spacing: 24) {
          Spacer()
          chapterTitleArea(book: b)
          playbackColumn(book: b)
          bottomUtilityBar
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        restoringOrIdleInLandscape
      }
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var restoringOrIdleInLandscape: some View {
    Group {
      if model.isRestoringLaunchPlayback {
        restoringPlaceholder
      } else if showIdlePlaceholder {
        idlePlaceholder
      }
    }
  }

  private func chapterTitleArea(book: ABSBook) -> some View {
    Text(authorDashTitleLine(for: book))
      .font(.headline)
      .foregroundStyle(.primary)
      .multilineTextAlignment(.center)
      .lineLimit(3)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 8)
  }

  private func scrubberCenterCaption(book: ABSBook) -> String {
    let chapters = model.player.chapterCount
    guard chapters > 0 else { return "" }
    let raw = model.player.currentChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !raw.isEmpty { return raw }
    let ord = model.player.currentChapterOrdinal
    if ord > 0 { return "Chapter \(ord)" }
    return "—"
  }

  private func fullPlayerArtwork(book: ABSBook) -> some View {
    let dur = max(model.player.totalDuration, 1)
    let pos = model.player.globalPosition
    let pct = min(100, max(0, Int((pos / dur * 100).rounded())))
    let corner: CGFloat = 24
    return CoverImageView(
      url: model.coverURL(for: book.id),
      token: model.token,
      itemId: book.id,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheRevision: model.coverImageCacheRevision,
      contentMode: .fit
    )
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: 400)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
    .overlay(alignment: .topTrailing) {
      Text(verbatim: "\(pct)%")
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
        .accessibilityLabel("Fortschritt \(pct) Prozent")
    }
  }

  private func playbackColumn(book: ABSBook) -> some View {
    VStack(spacing: 32) {
      scrubberSection(book: book)
      transportControls
    }
  }

  private func scrubberSection(book: ABSBook) -> some View {
    let dur = max(model.player.totalDuration, 1)
    let pos = scrubLocal ?? model.player.globalPosition
    let centerCaption = scrubberCenterCaption(book: book)
    return VStack(alignment: .leading, spacing: 10) {
      Slider(
        value: Binding(
          get: { pos },
          set: { scrubLocal = $0 }
        ),
        in: 0 ... dur,
        onEditingChanged: { editing in
          if !editing, let s = scrubLocal {
            model.player.seek(global: s)
            scrubLocal = nil
          }
        }
      )
      .tint(AppTheme.accent)
      .controlSize(.regular)
      .padding(.top, 6)
      .accessibilityLabel("Playback position")

      HStack {
        Text(formatPlaybackTime(pos))
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if !centerCaption.isEmpty {
          Text(centerCaption)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        } else {
          Spacer()
            .frame(maxWidth: .infinity)
        }
        Spacer()
        Text(formatPlaybackTime(max(0, dur - pos)))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .monospacedDigit()
    }
  }

  private var transportControls: some View {
    let hasChapters = model.player.chapterCount > 0
    let isBusy = model.player.activeBook != nil && model.player.isBuffering
    return HStack(spacing: 0) {
      if hasChapters {
        Button {
          model.player.skipToPreviousChapter()
        } label: {
          Image(systemName: "backward.end")
            .font(.title2)
            .symbolVariant(.fill)
        }
        .disabled(!model.player.canSkipToPreviousChapter)
        .accessibilityLabel("Previous chapter")
        Spacer(minLength: 8)
      }

      Button {
        model.player.skip(seconds: -PlayerChromeLayout.skipBackward)
      } label: {
        Image(systemName: "gobackward.15")
          .font(hasChapters ? .title2 : .largeTitle)
      }
      .disabled(isBusy)
      .accessibilityLabel("Back 15 seconds")

      Spacer(minLength: 8)

      Button {
        model.player.togglePlayPause()
      } label: {
        Group {
          if isBusy {
            ProgressView()
              .controlSize(.large)
          } else {
            Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 40))
              .symbolVariant(.fill)
          }
        }
        .frame(width: 64, height: 64)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .clipShape(Circle())
      .disabled(model.player.activeBook == nil)

      Spacer(minLength: 8)

      Button {
        model.player.skip(seconds: PlayerChromeLayout.skipForward)
      } label: {
        Image(systemName: "goforward.30")
          .font(hasChapters ? .title2 : .largeTitle)
      }
      .disabled(isBusy)
      .accessibilityLabel("Forward 30 seconds")

      if hasChapters {
        Spacer(minLength: 8)
        Button {
          model.player.skipToNextChapter()
        } label: {
          Image(systemName: "forward.end")
            .font(.title2)
            .symbolVariant(.fill)
        }
        .disabled(!model.player.canSkipToNextChapter)
        .accessibilityLabel("Next chapter")
      }
    }
    .buttonStyle(.borderless)
  }

  private var bottomUtilityBar: some View {
    HStack(spacing: 0) {
      Menu {
        ForEach(PlaybackController.playbackRatePresets, id: \.self) { r in
          Button {
            model.applyPlaybackSpeed(r)
          } label: {
            HStack {
              Text(miniPlayerFormatPlaybackRate(r))
              Spacer(minLength: 8)
              if model.player.playbackRate == r {
                Image(systemName: "checkmark")
                  .foregroundStyle(AppTheme.accent)
              }
            }
          }
        }
      } label: {
        VStack(spacing: 4) {
          Text(miniPlayerFormatPlaybackRate(model.player.playbackRate))
            .font(.subheadline.weight(.medium))
          Text("Tempo", comment: "Player control label")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .menuActionDismissBehavior(.automatic)

      Menu {
        Button("Off") { model.applySleepTimer(minutes: nil) }
        Button("15 Min") { model.applySleepTimer(minutes: 15) }
        Button("30 Min") { model.applySleepTimer(minutes: 30) }
        Button("45 Min") { model.applySleepTimer(minutes: 45) }
        Button("60 Min") { model.applySleepTimer(minutes: 60) }
      } label: {
        VStack(spacing: 4) {
          if let end = model.player.sleepEndDate {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
              Text(formatPlaybackTime(max(0, end.timeIntervalSinceNow)))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(AppTheme.accent)
            }
          } else {
            Text("Off")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
          }
          Text("Sleep", comment: "Player control label")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .menuActionDismissBehavior(.automatic)

      FullPlayerAirPlayButton()
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }
    .padding(.vertical, 8)
    .buttonStyle(.plain)
  }

  private var restoringPlaceholder: some View {
    ContentUnavailableView {
      ProgressView()
    } description: {
      Text("Loading last position…")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var idlePlaceholder: some View {
    ContentUnavailableView(
      "Nothing playing",
      systemImage: "waveform",
      description: Text("Choose an audiobook in the library.")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Tab bar accessory artwork (equatable: ignore high-frequency playback ticks)

private struct FloatingBarCoverEquatable: View, Equatable {
  @EnvironmentObject private var model: AppModel
  var itemId: String
  var coverRevision: Int

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.itemId == rhs.itemId && lhs.coverRevision == rhs.coverRevision
  }

  var body: some View {
    let side = PlayerChromeLayout.tabAccessoryCover
    let plateRadius: CGFloat = 6
    CoverImageView(
      url: model.coverURL(for: itemId),
      token: model.token,
      itemId: itemId,
      cacheAccount: model.coverImageCacheAccountDirectory(),
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

struct FloatingNowPlayingBar: View {
  @EnvironmentObject private var model: AppModel
  var onExpand: () -> Void

  private var showIdlePlaceholder: Bool {
    model.player.showMiniPlayerPlaceholder && model.player.activeBook == nil
  }

  private var canTogglePlayback: Bool {
    model.player.activeBook != nil && !model.isRestoringLaunchPlayback
  }

  var body: some View {
    HStack(spacing: 0) {
      openNowPlayingTapRegion
      trailingAccessoryButtons
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 16)
    .contextMenu {
      Button(role: .destructive) {
        Task { await model.dismissPlayer() }
      } label: {
        Label("Stop playback", systemImage: "xmark.circle")
      }
    }
  }

  /// Nur Cover + Titelzeilen: Sheet öffnen. Nicht über die Transport-Buttons legen, sonst frisst
  /// `onTapGesture` die Touches und Play/Skip reagieren nicht.
  private var openNowPlayingTapRegion: some View {
    HStack(spacing: 0) {
      miniCover
      VStack(alignment: .leading, spacing: 2) {
        Text(primaryLine)
          .font(.footnote)
          .fontWeight(.medium)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)

        Text(secondaryLine)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fontWeight(.medium)
          .lineLimit(1)
      }
      .padding(.leading, 10)
    }
    .contentShape(Rectangle())
    .onTapGesture { onExpand() }
    /// Nimmt den freien Platz links; Transport bleibt rechts — unabhängig von `accessoryPlacement`,
    /// damit Play/Pause nicht „fehlt“, wenn die Bar in der Tab-Leiste eingebettet ist.
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Etwas größer als Standard-Symbol, Tab-Leiste bleibt schmal.
  private static let accessoryTransportSide: CGFloat = 34

  @ViewBuilder
  private var trailingAccessoryButtons: some View {
    let busy = model.player.activeBook != nil && model.player.isBuffering
    HStack(spacing: 8) {
      Button {
        model.player.skip(seconds: -PlayerChromeLayout.skipBackward)
      } label: {
        Image(systemName: "gobackward.15")
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(.primary)
          .frame(width: Self.accessoryTransportSide, height: Self.accessoryTransportSide)
          .contentShape(Rectangle())
      }
      .disabled(!canTogglePlayback || busy)
      .buttonStyle(.plain)
      .accessibilityLabel("Back 15 seconds")

      Button {
        model.player.togglePlayPause()
      } label: {
        ZStack {
          Circle()
            .fill(Color.accentColor)
            .aspectRatio(1, contentMode: .fit)
          if model.player.isBuffering && canTogglePlayback {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.white)
              .scaleEffect(0.78)
          } else {
            Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.white)
          }
        }
        .frame(width: Self.accessoryTransportSide, height: Self.accessoryTransportSide)
        .contentShape(Circle())
      }
      /// Während Pufferung: Pause erlauben („Steckenbleiben“ vermeiden); erneuter Tap startet wie gewohnt.
      .disabled(!canTogglePlayback)
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private var miniCover: some View {
    let side = PlayerChromeLayout.tabAccessoryCover
    let plateRadius: CGFloat = 6
    if let b = model.player.activeBook {
      FloatingBarCoverEquatable(itemId: b.id, coverRevision: model.coverImageCacheRevision)
    } else if model.isRestoringLaunchPlayback {
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
            .foregroundStyle(.secondary)
        }
    }
  }

  private var primaryLine: String {
    if let b = model.player.activeBook { return authorDashTitleLine(for: b) }
    if model.isRestoringLaunchPlayback { return "Playback" }
    if showIdlePlaceholder { return "Nothing playing" }
    return "Playback"
  }

  private var secondaryLine: String {
    if model.player.activeBook != nil {
      let t = max(model.player.totalDuration, 1)
      let p = model.player.globalPosition
      return remainingTimeDashPercent(total: t, position: p)
    }
    if model.isRestoringLaunchPlayback { return "Loading…" }
    if showIdlePlaceholder { return "Choose an audiobook" }
    return ""
  }
}


/// Umrandete Aktions-Buttons (Bibliothekskarte), optisch an den Mini-Player angelehnt.
struct LibraryCardActionButtonStyle: ButtonStyle {
  enum Variant {
    case neutral
    case accent
    case danger
  }

  var variant: Variant = .neutral
  var minHeight: CGFloat = MiniPlayerMetrics.controlMinHeight
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let stroke: Color = {
      switch variant {
      case .neutral:
        return AppTheme.textSecondary.opacity(isEnabled ? 0.42 : 0.22)
      case .accent:
        return AppTheme.accent.opacity(isEnabled ? 0.55 : 0.22)
      case .danger:
        return AppTheme.danger.opacity(isEnabled ? 0.55 : 0.22)
      }
    }()
    let fill: Color = {
      switch variant {
      case .neutral: return .clear
      case .accent: return AppTheme.accent.opacity(0.12)
      case .danger: return AppTheme.danger.opacity(0.12)
      }
    }()

    return configuration.label
      .fixedSize(horizontal: true, vertical: true)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
          .fill(fill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
          .stroke(stroke, lineWidth: 1)
      )
      .opacity(
        isEnabled
          ? (configuration.isPressed ? 0.72 : 1)
          : 0.38
      )
      .contentShape(RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous))
      .frame(minHeight: minHeight)
  }
}


