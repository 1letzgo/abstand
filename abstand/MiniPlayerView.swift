import AVKit
import Combine
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
  /// Bibliothekszeile: 82×82; Mini-Player-Cover = 1,5×
  static let coverSide: CGFloat = AppTheme.Layout.libraryRowCoverSide * 1.5
  static let controlMinHeight: CGFloat = 30
  static let controlCorner: CGFloat = 7

  /// Mini-Player: ±Seek, Kapitel (ohne Play-Orb).
  static let miniPlayerTransportHeight: CGFloat = 44
  /// Schlummer / Tempo / AirPlay: eine flache Zeile mit Text.
  static let miniPlayerSecondaryRowHeight: CGFloat = 28
  /// Weicher Play-Kreis (Durchmesser); Zeilenhöhe richtet sich danach.
  static let miniPlayerPlayOrb: CGFloat = 52

  /// Now-Playing-Sheet: Abstand Cover zu links/rechts/oben (gleich).
  static let fullPlayerCoverInset: CGFloat = 24

  /// Eine Zeile: Sleep · Transport · AirPlay (Höhe = max(Transport, Play-Orb)).
  static var miniPlayerControlsTotalHeight: CGFloat {
    max(miniPlayerTransportHeight, miniPlayerPlayOrb)
  }
}

/// Obere Steuerzeile + Beschriftung im Vollplayer unten: gleiche Primärhöhe für alle Spalten.
enum FullPlayerUtilityBarLayout {
  static let primaryRowHeight: CGFloat = 44
  static let rowSpacing: CGFloat = 4
}

/// Kapitel- und Sekunden-Buttons links/rechts vom Play-Orb.
private enum FullPlayerTransportLayout {
  static let auxiliarySymbolFont: Font = .system(size: 30, weight: .medium)
}

/// Fortschrittsbalken im Vollplayer — nur Anzeige, kein Scrubber-Thumb.
private enum FullPlayerProgressLayout {
  /// Feste Zeilenhöhe — mit/ohne Kapitelmarker identisch.
  static let rowHeight: CGFloat = 8
  static let trackHeight: CGFloat = 6
}

private struct FullPlayerProgressTrack: View {
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  let value: Double
  let total: Double
  /// Relative Positionen (0…1) der Kapitelgrenzen.
  var chapterMarkers: [Double] = []

  private var fraction: Double {
    guard total > 0 else { return 0 }
    return min(1, max(0, value / total))
  }

  private var trackCornerRadius: CGFloat { FullPlayerProgressLayout.trackHeight / 2 }

  var body: some View {
    let _ = themeRevision
    return GeometryReader { geo in
      let w = geo.size.width
      let fillWidth = max(0, w * fraction)
      let fillTrailingRadius = fraction >= 0.999 ? trackCornerRadius : 0.0
      ZStack(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(AppTheme.progressTrack)
          .frame(height: FullPlayerProgressLayout.trackHeight)
        themeAccent
          .frame(width: fillWidth, height: FullPlayerProgressLayout.trackHeight)
          .clipShape(
            UnevenRoundedRectangle(
              topLeadingRadius: trackCornerRadius,
              bottomLeadingRadius: trackCornerRadius,
              bottomTrailingRadius: fillTrailingRadius,
              topTrailingRadius: fillTrailingRadius,
              style: .continuous
            )
          )
        ForEach(Array(chapterMarkers.enumerated()), id: \.offset) { _, marker in
          Rectangle()
            .fill(AppTheme.textSecondary.opacity(0.65))
            .frame(width: 1, height: FullPlayerProgressLayout.trackHeight)
            .offset(x: max(0, w * marker - 0.5))
        }
      }
      .frame(width: w, height: FullPlayerProgressLayout.rowHeight)
    }
    .frame(height: FullPlayerProgressLayout.rowHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Playback position")
    .accessibilityValue(fullPlayerProgressAccessibilityValue)
  }

  private var fullPlayerProgressAccessibilityValue: String {
    let pct = Int((fraction * 100).rounded())
    guard !chapterMarkers.isEmpty else { return "\(pct) percent" }
    return "\(pct) percent, \(chapterMarkers.count + 1) chapters"
  }
}


// MARK: - Player-Layout (SwiftUI-typische Komponenten)

private enum PlayerChromeLayout {
  static let miniBarMaxHeight: CGFloat = 56
  static let miniCover: CGFloat = 40
  /// Kompaktes Cover in `tabViewBottomAccessory` (System-Miniplayer-Größe).
  static let tabAccessoryCover: CGFloat = 32
}

private func authorDashTitleLine(for book: ABSBook) -> String {
  let a = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
  let t = book.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  if a.isEmpty || a == "—" { return t }
  return "\(a) – \(t)"
}

private func floatingBarPrimaryLine(for book: ABSBook, connecting: Bool) -> String {
  let line = authorDashTitleLine(for: book).trimmingCharacters(in: .whitespacesAndNewlines)
  if !line.isEmpty, line != "—", line != "…" { return line }
  if connecting { return "Loading…" }
  return ""
}

/// Untertitel der Floating-Bar: nur Restzeit (kompakt, ohne Sekunden).
private func floatingBarRemainingSubtitle(total: Double, position: Double) -> String {
  formatPlaybackDurationShortHuman(max(0, total - position))
}

/// `AVRoutePickerView` meldet in SwiftUI oft keine sinnvolle Intrinsic-Größe — ohne feste Bounds
/// frisst die Spalte die ganze Zeile bzw. vertikalen Platz.
private final class InlineRoutePickerView: AVRoutePickerView {
  override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }
}

private struct FullPlayerAirPlayButton: View {
  @Environment(\.themeAccent) private var themeAccent

  var body: some View {
    FullPlayerAirPlayButtonRepresentable(tint: UIColor(themeAccent))
  }
}

private struct FullPlayerAirPlayButtonRepresentable: UIViewRepresentable {
  let tint: UIColor

  func makeUIView(context: Context) -> InlineRoutePickerView {
    let v = InlineRoutePickerView()
    v.prioritizesVideoDevices = false
    v.backgroundColor = .clear
    v.clipsToBounds = true
    applyTint(to: v)
    return v
  }

  func updateUIView(_ uiView: InlineRoutePickerView, context: Context) {
    applyTint(to: uiView)
  }

  private func applyTint(to view: InlineRoutePickerView) {
    view.tintColor = tint
    view.activeTintColor = tint
  }
}

/// Sleep-Menü-Label: bei Pause eingefrorener Countdown, sonst `TimelineView` (kein Menu-Flackern).
private struct SleepTimerUtilityMenuLabel: View {
  @ObservedObject var player: PlaybackController
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  var body: some View {
    let _ = themeRevision
    VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
      Group {
        if let seconds = player.sleepTimerDisplaySeconds, seconds > 0 {
          if player.sleepEndDate != nil {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
              sleepCountdownText(player.sleepTimerDisplaySeconds ?? seconds)
            }
          } else {
            sleepCountdownText(seconds)
          }
        } else {
          Text("Off")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
        }
      }
      .frame(
        maxWidth: .infinity,
        minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
        maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
        alignment: .center
      )
      Text("Sleep", comment: "Player control label")
        .font(.caption2)
        .foregroundStyle(AppTheme.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .contentShape(Rectangle())
  }

  private func sleepCountdownText(_ seconds: TimeInterval) -> some View {
    Text(formatPlaybackTime(max(0, seconds)))
      .font(.subheadline.weight(.medium))
      .monospacedDigit()
      .foregroundStyle(themeAccent)
  }
}

private enum SleepTimerMetrics {
  static let popoverWidth: CGFloat = 272
  static let minuteStep = 15
  static let minuteMax = 120
}

private func sleepTimerOffLabel() -> String {
  String(localized: "Off", comment: "Sleep timer: disabled")
}

private func sleepTimerMinutesLabel(_ minutes: Int) -> String {
  if minutes <= 0 { return sleepTimerOffLabel() }
  return String(format: String(localized: "%lld min", comment: "Sleep timer: minutes"), minutes)
}

private func sleepTimerChaptersLabel(_ count: Int) -> String {
  if count <= 0 { return sleepTimerOffLabel() }
  return String(format: String(localized: "%lld ch.", comment: "Sleep timer: chapter count"), count)
}

private func sleepTimerMinutesAccessibilityLabel(_ minutes: Int) -> String {
  if minutes <= 0 {
    return String(localized: "Sleep timer by time, off", comment: "Sleep timer accessibility")
  }
  return String(
    format: String(localized: "Sleep timer by time, %lld minutes", comment: "Sleep timer accessibility"),
    minutes
  )
}

private func sleepTimerChaptersAccessibilityLabel(_ count: Int) -> String {
  if count <= 0 {
    return String(localized: "Sleep timer by chapters, off", comment: "Sleep timer accessibility")
  }
  return String(
    format: String(localized: "Sleep timer by chapters, %lld chapters", comment: "Sleep timer accessibility"),
    count
  )
}

/// Capsule-Stepper wie im Referenz-Screenshot (– / Wert / +).
private struct SleepTimerCapsuleStepper: View {
  let centerText: String
  /// Kleines Icon vor „Off“, um Minuten- vs. Kapitel-Zeile zu unterscheiden.
  let offLeadingIcon: String?
  let isOff: Bool
  let centerAccessibilityLabel: String
  let minusEnabled: Bool
  let plusEnabled: Bool
  var capsuleFill: Color = AppTheme.background
  let onMinus: () -> Void
  let onPlus: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      stepperButton(systemName: "minus", enabled: minusEnabled, action: onMinus)
      HStack(spacing: 5) {
        if isOff, let offLeadingIcon {
          Image(systemName: offLeadingIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .accessibilityHidden(true)
        }
        Text(centerText)
          .font(.body.weight(.medium))
          .monospacedDigit()
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(centerAccessibilityLabel)
      stepperButton(systemName: "plus", enabled: plusEnabled, action: onPlus)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 6)
    .background(
      Capsule(style: .continuous)
        .fill(capsuleFill)
    )
  }

  private func stepperButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.body.weight(.semibold))
        .foregroundStyle(AppTheme.textPrimary)
        .frame(width: 44, height: 36)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.32)
  }
}

private struct SleepTimerPopoverContent: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var player: PlaybackController

  @State private var minutes = 0
  @State private var chapters = 0

  private var palette: AppColorPalette { model.appearancePalette }

  private var maxChapters: Int { player.maxSleepChapterCount() }
  private var showsChapterRow: Bool { player.chapterCount > 0 }
  private var chapterTimerActive: Bool {
    if case .chapters = player.sleepTimerMode { return true }
    return false
  }

  var body: some View {
    VStack(spacing: 10) {
      Text("Sleep Timer", comment: "Sleep timer popover title")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)

      SleepTimerCapsuleStepper(
        centerText: sleepTimerMinutesLabel(minutes),
        offLeadingIcon: "clock",
        isOff: minutes <= 0,
        centerAccessibilityLabel: sleepTimerMinutesAccessibilityLabel(minutes),
        minusEnabled: minutes > 0,
        plusEnabled: minutes < SleepTimerMetrics.minuteMax,
        capsuleFill: palette.background,
        onMinus: { adjustMinutes(by: -SleepTimerMetrics.minuteStep) },
        onPlus: { adjustMinutes(by: SleepTimerMetrics.minuteStep) }
      )

      if showsChapterRow {
        SleepTimerCapsuleStepper(
          centerText: sleepTimerChaptersLabel(chapters),
          offLeadingIcon: "list.number",
          isOff: chapters <= 0,
          centerAccessibilityLabel: sleepTimerChaptersAccessibilityLabel(chapters),
          minusEnabled: chapters > 0 && (chapters > 1 || chapterTimerActive),
          plusEnabled: chapters < maxChapters,
          capsuleFill: palette.background,
          onMinus: { adjustChapters(by: -1) },
          onPlus: { adjustChapters(by: 1) }
        )
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .frame(width: SleepTimerMetrics.popoverWidth)
    .background(palette.card)
    .onAppear(perform: syncFromActiveTimer)
  }

  private func syncFromActiveTimer() {
    switch player.sleepTimerMode {
    case .off:
      minutes = 0
      chapters = 0
    case .minutes(let m):
      minutes = m
      chapters = 0
    case .chapters(let c):
      minutes = 0
      chapters = min(max(1, c), max(1, maxChapters))
    }
  }

  private func adjustMinutes(by delta: Int) {
    let next = min(SleepTimerMetrics.minuteMax, max(0, minutes + delta))
    minutes = next
    if next <= 0 {
      chapters = 0
    }
    model.applySleepTimer(minutes: next)
  }

  private func adjustChapters(by delta: Int) {
    let cap = max(1, maxChapters)
    let previous = chapters
    let next = min(cap, max(0, chapters + delta))
    if next <= 0 {
      chapters = 0
      minutes = 0
      model.applySleepTimer(minutes: 0)
      return
    }
    minutes = 0
    chapters = next
    if !model.applySleepTimer(chapters: next) {
      chapters = previous
    }
  }
}

private struct SleepTimerPopoverControl<Label: View>: View {
  @ViewBuilder let label: () -> Label
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      label()
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      SleepTimerPopoverContent()
        .presentationCompactAdaptation(.popover)
    }
  }
}

/// Untere Steuerzeile: von `globalPosition`-Ticks entkoppelt, damit `Menu` nicht flackert.
private struct FullPlayerUtilityBar: View, Equatable {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  let playbackRate: Float
  let activeAudiobookId: String?
  let offlineStorageId: String?
  let isDownloaded: Bool
  let isDownloading: Bool
  let downloadProgressBucket: Int
  let bookmarkMenuItems: [PlayerBookmarkMenuItem]
  let isLoggedIn: Bool
  let isLiveTranscriptionEnabled: Bool
  let isLiveTranscriptionBusy: Bool
  let onToggleLiveTranscription: () -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.playbackRate == rhs.playbackRate
      && lhs.activeAudiobookId == rhs.activeAudiobookId
      && lhs.offlineStorageId == rhs.offlineStorageId
      && lhs.isDownloaded == rhs.isDownloaded
      && lhs.isDownloading == rhs.isDownloading
      && lhs.downloadProgressBucket == rhs.downloadProgressBucket
      && lhs.bookmarkMenuItems == rhs.bookmarkMenuItems
      && lhs.isLoggedIn == rhs.isLoggedIn
      && lhs.isLiveTranscriptionEnabled == rhs.isLiveTranscriptionEnabled
      && lhs.isLiveTranscriptionBusy == rhs.isLiveTranscriptionBusy
  }

  var body: some View {
    let _ = themeRevision
    return HStack(spacing: 0) {
      Menu {
        ForEach(PlaybackController.playbackRatePresets, id: \.self) { r in
          Button {
            model.applyPlaybackSpeed(r)
          } label: {
            HStack {
              Text(miniPlayerFormatPlaybackRate(r))
              Spacer(minLength: 8)
              if playbackRate == r {
                Image(systemName: "checkmark")
                  .foregroundStyle(themeAccent)
              }
            }
          }
        }
      } label: {
        VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
          Text(miniPlayerFormatPlaybackRate(playbackRate))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(
              maxWidth: .infinity,
              minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              alignment: .center
            )
          Text("Tempo", comment: "Player control label")
            .font(.caption2)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }

      SleepTimerPopoverControl {
        SleepTimerUtilityMenuLabel(player: model.player)
      }

      PlayerBookmarkUtilityControl(
        activeAudiobookId: activeAudiobookId,
        menuItems: bookmarkMenuItems
      )

      Button(action: onToggleLiveTranscription) {
        VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
          Group {
            if isLiveTranscriptionBusy {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: isLiveTranscriptionEnabled ? "text.word.spacing" : "text.word.spacing")
                .font(.title3)
                .symbolVariant(isLiveTranscriptionEnabled ? .fill : .none)
            }
          }
          .foregroundStyle(isLiveTranscriptionEnabled ? themeAccent : AppTheme.textPrimary)
          .frame(
            maxWidth: .infinity,
            minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
            maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
            alignment: .center
          )
          Text("Read along", comment: "Player live transcript toggle")
            .font(.caption2)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isLiveTranscriptionBusy)
      .accessibilityLabel(
        isLiveTranscriptionEnabled
          ? String(localized: "Stop read-along transcript", comment: "Accessibility")
          : String(localized: "Start read-along transcript", comment: "Accessibility")
      )

      VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
        FullPlayerAirPlayButton()
          .frame(width: 44, height: 44)
          .frame(
            maxWidth: .infinity,
            minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
            maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
            alignment: .center
          )
        Text("AirPlay", comment: "Player control label")
          .font(.caption2)
          .foregroundStyle(AppTheme.textSecondary)
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())

      downloadControl
        .frame(maxWidth: .infinity)
    }
    .padding(.vertical, 8)
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var downloadControl: some View {
    if offlineStorageId != nil {
      if isDownloaded {
        Button {
          model.removeLocalDownloadForActivePlayback()
        } label: {
          VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
            Image(systemName: "arrow.down.circle.fill")
              .font(.title3)
              .foregroundStyle(themeAccent)
              .frame(
                maxWidth: .infinity,
                minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
                maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
                alignment: .center
              )
            Text("Download", comment: "Player download control caption")
              .font(.caption2)
              .foregroundStyle(AppTheme.textSecondary)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLoggedIn)
        .accessibilityLabel("Remove download")
      } else if isDownloading {
        VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
          ProgressView(value: Double(downloadProgressBucket) / 20.0)
            .tint(themeAccent)
            .scaleEffect(x: 1, y: 0.9, anchor: .center)
            .frame(
              maxWidth: .infinity,
              minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              alignment: .center
            )
          Text("Download", comment: "Player download control caption")
            .font(.caption2)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Download in progress")
      } else {
        Button {
          model.startDownloadForActivePlayback()
        } label: {
          VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
            Image(systemName: "arrow.down.circle")
              .font(.title3)
              .foregroundStyle(AppTheme.textPrimary)
              .frame(
                maxWidth: .infinity,
                minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
                maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
                alignment: .center
              )
            Text("Download", comment: "Player download control caption")
              .font(.caption2)
              .foregroundStyle(AppTheme.textSecondary)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLoggedIn)
        .accessibilityLabel("Download")
      }
    }
  }
}

// MARK: - Vollansicht (Now Playing)

struct NowPlayingDetailView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var player: PlaybackController
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  private var showIdlePlaceholder: Bool {
    player.showMiniPlayerPlaceholder && player.activeBook == nil && !model.isPlayerConnectionLoading
  }

  private var showsConnectionLoading: Bool {
    model.isPlayerConnectionLoading && player.activeBook == nil
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
      .safeAreaPadding(.horizontal, MiniPlayerMetrics.fullPlayerCoverInset)
      .safeAreaPadding(.top, MiniPlayerMetrics.fullPlayerCoverInset)
    }
    .preferredColorScheme(model.resolvedInterfaceColorScheme)
    .onDisappear {
      if player.liveTranscription.isEnabled {
        player.liveTranscription.disable()
      }
    }
  }

  @ViewBuilder
  private var fullPlayerBackground: some View {
    let _ = themeRevision
    let palette = model.appearancePalette
    if palette.isDarkLike {
      LinearGradient(
        colors: [player.miniPlayerBarFillColor, Color(white: 0.1)],
        startPoint: .top,
        endPoint: .bottom
      )
    } else {
      // Wie Buch-Detail im Light/Sepia: kein Cover-Verlauf, nur App-Hintergrund.
      palette.background
    }
  }

  private var portraitLayout: some View {
    Group {
      if let b = player.activeBook {
        fullPlayerPortraitLayout(book: b)
      } else if showsConnectionLoading {
        connectionLoadingPlaceholder
      } else if showIdlePlaceholder {
        idlePlaceholder
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private func fullPlayerPortraitLayout(book: ABSBook) -> some View {
    VStack(spacing: 0) {
      playerHeaderArea(book: book)
      Spacer(minLength: 24)
      VStack(spacing: 32) {
        chapterTitleArea(book: book)
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
          playbackColumn(book: book)
        }
      }
      .frame(maxWidth: 800)
      Spacer(minLength: 24)
      fullPlayerUtilityBar
      Spacer(minLength: 8)
    }
  }

  private var landscapeLayout: some View {
    Group {
      if let b = player.activeBook {
        fullPlayerLandscapeLayout(book: b)
      } else {
        restoringOrIdleInLandscape
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private func fullPlayerLandscapeLayout(book: ABSBook) -> some View {
    HStack(alignment: .top, spacing: MiniPlayerMetrics.fullPlayerCoverInset) {
      playerHeaderArea(book: book)
        .containerRelativeFrame(.horizontal) { w, _ in w * 0.48 }
      VStack(spacing: 24) {
        Spacer()
        chapterTitleArea(book: book)
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
          playbackColumn(book: book)
        }
        fullPlayerUtilityBar
        Spacer()
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var restoringOrIdleInLandscape: some View {
    Group {
      if showsConnectionLoading {
        connectionLoadingPlaceholder
      } else if showIdlePlaceholder {
        idlePlaceholder
      }
    }
  }

  private func chapterTitleArea(book: ABSBook) -> some View {
    let authors = book.displayAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
    return VStack(alignment: .center, spacing: 8) {
      Text(book.displayTitle)
        .font(.title2.weight(.bold))
        .foregroundStyle(AppTheme.textPrimary)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .frame(maxWidth: .infinity)
      if !authors.isEmpty, authors != "—" {
        Text(authors)
          .font(.title3)
          .foregroundStyle(AppTheme.textSecondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .frame(maxWidth: .infinity)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 8)
    .accessibilityElement(children: .combine)
  }

  private func scrubberCenterCaption(book: ABSBook) -> String {
    let chapters = player.chapterCount
    guard chapters > 0 else { return "" }
    let raw = player.currentChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !raw.isEmpty { return raw }
    let ord = player.currentChapterOrdinal
    if ord > 0 { return "Chapter \(ord)" }
    return "—"
  }

  @ViewBuilder
  private func playerHeaderArea(book: ABSBook) -> some View {
    if player.liveTranscription.isEnabled {
      readAlongKaraokeCard(book: book)
    } else {
      fullPlayerArtwork(book: book)
    }
  }

  /// Gleicher Platz und Rahmen wie `fullPlayerArtwork`, Inhalt = Karaoke-Transkript (100 % Kartenfläche).
  private func readAlongKaraokeCard(book: ABSBook) -> some View {
    let dur = max(player.totalDuration, 1)
    let pos = player.globalPosition
    let pct = min(100, max(0, Int((pos / dur * 100).rounded())))
    let corner: CGFloat = 24
    return Color.clear
      .fullPlayerHeaderSquareFrame()
      .background(AppTheme.card.opacity(0.35), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
      .overlay {
        GeometryReader { geo in
          let pad = PlayerTeleprompterMetrics.cardContentPadding
          PlayerLiveTranscriptPanelView(
            transcription: player.liveTranscription,
            globalPlaybackTime: player.globalPosition,
            isPlaying: player.isPlaying,
            playbackRate: Double(player.playbackRate),
            viewportSize: CGSize(
              width: max(0, geo.size.width - pad * 2),
              height: max(0, geo.size.height - pad * 2)
            )
          )
          .padding(pad)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
      }
      .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
      .overlay(alignment: .topTrailing) {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
          playbackProgressBadge(percent: pct)
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
      }
      .accessibilityLabel(String(localized: "Read along transcript", comment: "Accessibility"))
  }

  private func playbackProgressBadge(percent: Int) -> some View {
    Text(verbatim: "\(percent)%")
      .font(.caption.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(AppTheme.textPrimary)
      .padding(.horizontal, 11)
      .padding(.vertical, 6)
      .background(.ultraThinMaterial, in: Capsule(style: .continuous))
      .overlay {
        Capsule(style: .continuous)
          .strokeBorder(AppTheme.textSecondary.opacity(0.35), lineWidth: 0.5)
      }
      .accessibilityLabel("Fortschritt \(percent) Prozent")
  }

  private func fullPlayerArtwork(book: ABSBook) -> some View {
    let dur = max(player.totalDuration, 1)
    let pos = player.globalPosition
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
    .fullPlayerHeaderSquareFrame()
    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
    .overlay(alignment: .topTrailing) {
      TimelineView(.periodic(from: .now, by: 0.5)) { _ in
        playbackProgressBadge(percent: pct)
          .padding(.top, 12)
          .padding(.trailing, 12)
      }
    }
  }

  private func playbackColumn(book: ABSBook) -> some View {
    VStack(spacing: 32) {
      scrubberSection(book: book)
      transportControls
    }
  }

  private func scrubberSection(book: ABSBook) -> some View {
    let dur = max(player.totalDuration, 1)
    let pos = player.globalPosition
    let centerCaption = scrubberCenterCaption(book: book)
    return VStack(alignment: .leading, spacing: 10) {
      FullPlayerProgressTrack(
        value: pos,
        total: dur,
        chapterMarkers: player.chapterMarkerFractions
      )
      .padding(.top, 6)

      HStack {
        Text(formatPlaybackTime(pos))
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
        Spacer()
        if !centerCaption.isEmpty {
          Text(centerCaption)
            .font(.caption)
            .foregroundStyle(AppTheme.textPrimary)
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
          .foregroundStyle(AppTheme.textSecondary)
      }
      .monospacedDigit()
    }
  }

  private var transportControls: some View {
    let hasChapters = player.chapterCount > 0
    let isBusy = player.activeBook != nil && player.isBuffering
    return HStack(alignment: .center, spacing: 0) {
      fullPlayerTransportChapterSlot(isLeading: true, hasChapters: hasChapters)
        .frame(maxWidth: .infinity)

      Button {
        player.skip(seconds: -Double(player.skipBackwardSeconds))
      } label: {
        Image(systemName: PlaybackController.gobackwardSystemImage(seconds: player.skipBackwardSeconds))
          .font(FullPlayerTransportLayout.auxiliarySymbolFont)
      }
      .disabled(isBusy)
      .accessibilityLabel(
        PlaybackController.skipAccessibilityLabel(
          backward: true, seconds: player.skipBackwardSeconds))
      .frame(maxWidth: .infinity)

      Button {
        player.togglePlayPause()
      } label: {
        Group {
          if isBusy {
            ProgressView()
              .controlSize(.large)
          } else {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 40))
              .symbolVariant(.fill)
          }
        }
        .frame(width: 64, height: 64)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .clipShape(Circle())
      .tint(themeAccent)
      .disabled(player.activeBook == nil)
      .frame(maxWidth: .infinity)

      Button {
        player.skip(seconds: Double(player.skipForwardSeconds))
      } label: {
        Image(systemName: PlaybackController.goforwardSystemImage(seconds: player.skipForwardSeconds))
          .font(FullPlayerTransportLayout.auxiliarySymbolFont)
      }
      .disabled(isBusy)
      .accessibilityLabel(
        PlaybackController.skipAccessibilityLabel(
          backward: false, seconds: player.skipForwardSeconds))
      .frame(maxWidth: .infinity)

      fullPlayerTransportChapterSlot(isLeading: false, hasChapters: hasChapters)
        .frame(maxWidth: .infinity)
    }
    .foregroundStyle(AppTheme.textPrimary)
    .buttonStyle(.borderless)
  }

  /// Kapitel-Slots bleiben reserviert (Podcasts ohne Kapitel → ±15/30 bleiben zentriert).
  @ViewBuilder
  private func fullPlayerTransportChapterSlot(isLeading: Bool, hasChapters: Bool) -> some View {
    let symbol = isLeading ? "backward.end" : "forward.end"
    if hasChapters {
      Button {
        if isLeading {
          player.skipToPreviousChapter()
        } else {
          player.skipToNextChapter()
        }
      } label: {
        Image(systemName: symbol)
          .font(FullPlayerTransportLayout.auxiliarySymbolFont)
          .symbolVariant(.fill)
      }
      .disabled(isLeading ? !player.canSkipToPreviousChapter : !player.canSkipToNextChapter)
      .accessibilityLabel(isLeading ? "Previous chapter" : "Next chapter")
    } else {
      Image(systemName: symbol)
        .font(FullPlayerTransportLayout.auxiliarySymbolFont)
        .symbolVariant(.fill)
        .hidden()
        .accessibilityHidden(true)
    }
  }

  private var fullPlayerUtilityBar: some View {
    let sid = model.currentPlaybackOfflineStorageId()
    let isDownloading = sid != nil && model.downloads.activeItemId == sid
    let audiobookId: String? = {
      guard let id = player.activeBook?.id else { return nil }
      let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return ep.isEmpty ? id : nil
    }()
    let tx = player.liveTranscription
    return FullPlayerUtilityBar(
      playbackRate: player.playbackRate,
      activeAudiobookId: audiobookId,
      offlineStorageId: sid,
      isDownloaded: sid.map { model.downloadedItemIds.contains($0) } ?? false,
      isDownloading: isDownloading,
      downloadProgressBucket: isDownloading ? Int(model.downloads.progress * 20) : -1,
      bookmarkMenuItems: audiobookId.map { id in
        model.bookmarks(for: id).map(PlayerBookmarkMenuItem.init)
      } ?? [],
      isLoggedIn: model.isLoggedIn,
      isLiveTranscriptionEnabled: tx.isEnabled,
      isLiveTranscriptionBusy: tx.isPreparing || tx.modelDownloadProgress != nil,
      onToggleLiveTranscription: {
        Task { @MainActor in
          await tx.toggle(player: player)
          if let err = tx.errorMessage {
            model.errorMessage = err
          }
        }
      }
    )
  }

  private var connectionLoadingPlaceholder: some View {
    ContentUnavailableView {
      ProgressView()
    } description: {
      Text(model.isRestoringLaunchPlayback ? "Loading last position…" : "Loading…")
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
    let plateRadius: CGFloat = 6
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
    skipBackwardSeconds: PlaybackController.defaultSkipBackwardSeconds
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
      let primaryLine = floatingBarPrimaryLine(for: book, connecting: connecting)
      guard !primaryLine.isEmpty else { return .hidden }
      return TabAccessoryMiniPlayerSnapshot(
        activeBookId: book.id,
        coverRevision: model.coverImageCacheRevision,
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

  private func refresh() {
    guard let model else { return }
    let wasVisible = gate.chromeVisible
    let next = TabAccessoryMiniPlayerSnapshot.make(model: model)
    let hasTitle = !next.primaryLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let visible =
      !model.offlineHomeUIActive
      && (next.showsConnectionLoading || (next.activeBookId != nil && hasTitle))
    gate.apply(chromeVisible: visible, snapshot: next)
    if wasVisible != visible {
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
    gate.chromeVisible && !sheetPresented && !keyboardVisible
  }

  var body: some View {
    if showsFloatingPlayer, chrome.playbackController != nil {
      TabAccessoryMiniPlayer(snapshot: gate.snapshot, chrome: chrome)
        .equatable()
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
  }
}

/// Vorbild: [AudioBooth `MiniBookPlayer`](https://github.com/AudioBooth/AudioBooth/blob/main/AudioBooth/AudioBooth/Screens/BookPlayer/MiniBookPlayer.swift)
private struct TabAccessoryMiniPlayer: View, Equatable {
  let snapshot: TabAccessoryMiniPlayerSnapshot
  let chrome: FloatingPlayerChromeController

  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  private static let rowMinHeight: CGFloat = 48
  private static let accessoryTransportSide: CGFloat = 44

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.snapshot == rhs.snapshot
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
    .padding(.horizontal, 12)
    .contentShape(Rectangle())
  }

  private var showsTransportControls: Bool {
    placement != .inline && snapshot.canTogglePlayback
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
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let subtitle = snapshot.subtitleText {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
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
    let playDiameter: CGFloat = 36
    return HStack(spacing: 8) {
      Button {
        chrome.skipBackward()
      } label: {
        Image(
          systemName: PlaybackController.gobackwardSystemImage(
            seconds: snapshot.skipBackwardSeconds))
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(AppTheme.textPrimary)
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
          Circle()
            .fill(themeAccent)
            .frame(width: playDiameter, height: playDiameter)
          if busy {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.white)
              .scaleEffect(0.72)
          } else {
            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white)
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
    let plateRadius: CGFloat = 6
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
            .foregroundStyle(AppTheme.textSecondary)
        }
    }
  }
}


/// Umrandete Aktions-Buttons (Bibliothekskarte), optisch an den Mini-Player angelehnt.
struct LibraryCardActionButtonStyle: ButtonStyle {
  enum Variant {
    case neutral
    case accent
    case danger
    /// Lokale Kopie vorhanden — dezenter Akzent-Hintergrund (nicht mit „deaktiviert“ verwechseln).
    case downloaded
    /// Als fertig markiert — dezenter Erfolgs-Hintergrund (wie Häkchen in Listenzeilen).
    case finished
  }

  var variant: Variant = .neutral
  var minHeight: CGFloat = MiniPlayerMetrics.controlMinHeight
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  func makeBody(configuration: Configuration) -> some View {
    let _ = themeRevision
    let stroke: Color = {
      switch variant {
      case .neutral:
        return AppTheme.textSecondary.opacity(isEnabled ? 0.42 : 0.22)
      case .accent:
        return themeAccent.opacity(isEnabled ? 0.55 : 0.22)
      case .danger:
        return AppTheme.danger.opacity(isEnabled ? 0.55 : 0.22)
      case .downloaded, .finished:
        return themeAccent.opacity(isEnabled ? 0.72 : 0.5)
      }
    }()
    let fill: Color = {
      switch variant {
      case .neutral: return .clear
      case .accent: return themeAccent.opacity(0.12)
      case .danger: return AppTheme.danger.opacity(0.12)
      case .downloaded, .finished: return themeAccent.opacity(0.28)
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

// MARK: - Offline-Home: Mini-Player-Karte (Cover links, über „Downloaded“)

/// Kompakte Wiedergabe-Karte auf der Offline-Home — ersetzt `tabViewBottomAccessory` + Tab-Bar.
struct OfflineHomeMiniPlayerCard: View {
  @ObservedObject var gate: FloatingAccessoryGate
  let chrome: FloatingPlayerChromeController
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var player: PlaybackController
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  @State private var confirmMarkFinished = false
  @State private var confirmMarkUnfinished = false

  private var snapshot: TabAccessoryMiniPlayerSnapshot { gate.snapshot }

  var body: some View {
    cardBody
      .alert("Mark as finished?", isPresented: $confirmMarkFinished) {
        Button("Cancel", role: .cancel) {}
        Button("Mark as finished") {
          Task { await offlineApplyMarkFinished() }
        }
      } message: {
        Text("Your current position will be saved as complete.")
      }
      .alert("Mark as not finished?", isPresented: $confirmMarkUnfinished) {
        Button("Cancel", role: .cancel) {}
        Button("Mark as not finished") {
          Task { await offlineApplyMarkUnfinished() }
        }
      } message: {
        Text("You can resume from your saved position.")
      }
  }

  private var cardBody: some View {
    let _ = themeRevision
    let inset = AppTheme.Layout.libraryRowCardInset
    let shape = RoundedRectangle(
      cornerRadius: AppTheme.Layout.libraryRowCornerRadius, style: .continuous)
    let palette = model.appearancePalette

    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: inset) {
        Button {
          chrome.openNowPlaying()
        } label: {
          HStack(alignment: .top, spacing: inset) {
            offlineCover
            metadataColumn
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open now playing")
        .accessibilityHint("Shows the full player")

        if showsTransport {
          offlineTransportRow
        } else if snapshot.showsConnectionLoading {
          HStack(spacing: 8) {
            ProgressView()
              .tint(themeAccent)
            Text("Loading…")
              .font(.subheadline)
              .foregroundStyle(palette.textSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        if showsProgress {
          offlineProgressTimeRow(
            totalDuration: max(player.totalDuration, 1),
            position: min(max(0, player.globalPosition), max(player.totalDuration, 1))
          )
        }
      }
      .padding(inset)
      .overlay(alignment: .topTrailing) {
        HStack(spacing: 6) {
          offlineMarkFinishedCornerButton
          offlineAirPlayCornerButton
          offlineSleepTimerCornerButton
        }
        .padding(inset)
      }

      if showsProgress {
        AbstandCardBottomProgress(value: player.globalPosition / max(player.totalDuration, 1))
          .allowsHitTesting(false)
          .accessibilityLabel("Playback progress")
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.card)
    .clipShape(shape)
    .contentShape(shape)
  }

  private var showsTransport: Bool {
    player.activeBook != nil || snapshot.showsConnectionLoading
  }

  private var offlineTransportRow: some View {
    let hasChapters = player.chapterCount > 0
    let isBusy = player.activeBook != nil && player.isBuffering
    let playDiameter = MiniPlayerMetrics.miniPlayerPlayOrb
    let sideSlot = MiniPlayerMetrics.controlMinHeight
    let rowHeight = max(playDiameter, sideSlot)
    return HStack(alignment: .center, spacing: 0) {
      offlineTransportChapterSlot(
        isLeading: true,
        hasChapters: hasChapters,
        side: sideSlot
      )
      .frame(maxWidth: .infinity, maxHeight: rowHeight)

      offlineTransportControlButton(
        systemName: PlaybackController.gobackwardSystemImage(seconds: player.skipBackwardSeconds),
        label: PlaybackController.skipAccessibilityLabel(
          backward: true, seconds: player.skipBackwardSeconds),
        disabled: isBusy || player.activeBook == nil
      ) {
        player.skip(seconds: -Double(player.skipBackwardSeconds))
      }
      .frame(maxWidth: .infinity, maxHeight: rowHeight)

      Button {
        chrome.togglePlayPause()
      } label: {
        ZStack {
          Circle()
            .fill(themeAccent)
            .frame(width: playDiameter, height: playDiameter)
          if isBusy {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.black.opacity(0.85))
              .scaleEffect(0.85)
          } else {
            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.88))
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(!snapshot.canTogglePlayback)
      .accessibilityLabel(snapshot.isPlaying ? "Pause" : "Play")
      .frame(maxWidth: .infinity, maxHeight: rowHeight)

      offlineTransportControlButton(
        systemName: PlaybackController.goforwardSystemImage(seconds: player.skipForwardSeconds),
        label: PlaybackController.skipAccessibilityLabel(
          backward: false, seconds: player.skipForwardSeconds),
        disabled: isBusy || player.activeBook == nil
      ) {
        player.skip(seconds: Double(player.skipForwardSeconds))
      }
      .frame(maxWidth: .infinity, maxHeight: rowHeight)

      offlineTransportChapterSlot(
        isLeading: false,
        hasChapters: hasChapters,
        side: sideSlot
      )
      .frame(maxWidth: .infinity, maxHeight: rowHeight)
    }
    .frame(maxWidth: .infinity)
    .frame(height: rowHeight)
  }

  @ViewBuilder
  private func offlineTransportChapterSlot(isLeading: Bool, hasChapters: Bool, side: CGFloat) -> some View {
    HStack {
      Spacer(minLength: 0)
      Group {
        if hasChapters {
          if isLeading {
            offlineTransportControlButton(
              systemName: "backward.end.fill",
              label: "Previous chapter",
              disabled: !player.canSkipToPreviousChapter
            ) {
              player.skipToPreviousChapter()
            }
          } else {
            offlineTransportControlButton(
              systemName: "forward.end.fill",
              label: "Next chapter",
              disabled: !player.canSkipToNextChapter
            ) {
              player.skipToNextChapter()
            }
          }
        } else {
          Color.clear
            .frame(width: side, height: side)
            .accessibilityHidden(true)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(height: side)
  }

  private var offlineActiveAudiobookId: String? {
    guard let book = player.activeBook else { return nil }
    let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return ep.isEmpty ? book.id : nil
  }

  private var offlineActivePodcastEpisode: ABSPodcastEpisodeListItem? {
    model.podcastEpisodeForActivePlayback()
  }

  private var offlineActiveItemIsFinished: Bool {
    if let episode = offlineActivePodcastEpisode {
      return model.progressByItemId[episode.progressLookupKey]?.isFinished == true
    }
    if let bookId = offlineActiveAudiobookId {
      return model.progressByItemId[bookId]?.isFinished == true
    }
    return false
  }

  private var offlineMarkFinishedCornerButton: some View {
    let finished = offlineActiveItemIsFinished
    return Button {
      if finished {
        confirmMarkUnfinished = true
      } else {
        confirmMarkFinished = true
      }
    } label: {
      Image(systemName: finished ? "arrow.uturn.backward.circle" : "checkmark.circle")
        .font(.callout)
        .foregroundStyle(themeAccent)
    }
    .buttonStyle(
      LibraryCardActionButtonStyle(
        variant: finished ? .finished : .accent,
        minHeight: 36
      )
    )
    .disabled(player.activeBook == nil)
    .frame(width: 36, height: 36)
    .accessibilityLabel(finished ? "Mark as not finished" : "Mark as finished")
  }

  private func offlineApplyMarkFinished() async {
    if let episode = offlineActivePodcastEpisode {
      await model.markPodcastEpisodeFinished(episode)
    } else if let bookId = offlineActiveAudiobookId {
      await model.markFinished(bookId: bookId)
    }
  }

  private func offlineApplyMarkUnfinished() async {
    if let episode = offlineActivePodcastEpisode {
      await model.markPodcastEpisodeUnfinished(episode)
    } else if let bookId = offlineActiveAudiobookId {
      await model.markUnfinished(bookId: bookId)
    }
  }

  private var offlineAirPlayCornerButton: some View {
    let enabled = player.activeBook != nil
    return FullPlayerAirPlayButton()
      .frame(width: 22, height: 22)
      .frame(width: 36, height: 36)
      .background(
        RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
          .fill(Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
          .stroke(AppTheme.textSecondary.opacity(enabled ? 0.42 : 0.22), lineWidth: 1)
      )
      .opacity(enabled ? 1 : 0.38)
      .allowsHitTesting(enabled)
      .accessibilityLabel("AirPlay")
      .accessibilityHint("Choose an audio output")
  }

  private var offlineSleepTimerCornerButton: some View {
    let sleepActive = player.isSleepTimerActive
    return SleepTimerPopoverControl {
      Image(systemName: sleepActive ? "moon.fill" : "moon")
        .font(.callout)
        .foregroundStyle(sleepActive ? themeAccent : AppTheme.textPrimary)
    }
    .buttonStyle(
      LibraryCardActionButtonStyle(
        variant: sleepActive ? .accent : .neutral,
        minHeight: 36
      )
    )
    .disabled(player.activeBook == nil)
    .frame(width: 36, height: 36)
    .accessibilityLabel("Sleep timer")
    .accessibilityHint(sleepActive ? "Timer active" : "Set sleep timer")
  }

  private func offlineTransportControlButton(
    systemName: String,
    label: String,
    disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Spacer(minLength: 0)
      Button(action: action) {
        Image(systemName: systemName)
          .font(.title3.weight(.medium))
          .foregroundStyle(AppTheme.textPrimary)
          .frame(width: MiniPlayerMetrics.controlMinHeight, height: MiniPlayerMetrics.controlMinHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(disabled)
      .opacity(disabled ? 0.35 : 1)
      .accessibilityLabel(label)
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private var offlineCover: some View {
    let side = AppTheme.Layout.libraryRowCoverSide
    let radius = AppTheme.Layout.libraryRowCornerRadius
    if let id = snapshot.activeBookId {
      CoverImageView(
        url: snapshot.coverURL,
        token: snapshot.coverToken,
        itemId: id,
        cacheAccount: snapshot.coverCacheAccount,
        cacheRevision: snapshot.coverRevision
      )
      .frame(width: side, height: side)
      .scaledToFill()
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    } else if snapshot.showsRestoringCover {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(AppTheme.background)
        .frame(width: side, height: side)
        .overlay { ProgressView().tint(themeAccent) }
    } else {
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(AppTheme.background)
        .frame(width: side, height: side)
        .overlay {
          Image(systemName: "waveform")
            .font(.title3)
            .foregroundStyle(AppTheme.textSecondary)
        }
    }
  }

  private var metadataColumn: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let book = player.activeBook {
        offlineTitleLine(book: book)
        offlineAuthorLine(book: book)
        if let chapter = offlineChapterCaption {
          Text(chapter)
            .font(.footnote)
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(2)
            .minimumScaleFactor(0.88)
        }
      } else {
        Text(snapshot.primaryLine)
          .font(.headline.weight(.semibold))
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(2)
      }
      if !showsProgress, let subtitle = snapshot.subtitleText {
        Text(subtitle)
          .font(.caption.monospacedDigit())
          .foregroundStyle(themeAccent)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(.trailing, player.activeBook != nil ? 122 : 0)
  }

  /// Wie `BookRowCard.libraryRowTitleText`.
  private func offlineTitleLine(book: ABSBook) -> some View {
    Text(book.displayTitle)
      .font(.headline.weight(.semibold))
      .foregroundStyle(AppTheme.textPrimary)
      .lineLimit(1)
      .truncationMode(.tail)
      .minimumScaleFactor(0.85)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Wie `BookCollapsedAuthorLine` in Library-Zeilen (`.footnote`).
  @ViewBuilder
  private func offlineAuthorLine(book: ABSBook) -> some View {
    let author = book.displayAuthorsCardLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if !author.isEmpty, author != "—" {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("Author")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(AppTheme.textSecondary)
          .textCase(.uppercase)
        Text(author)
          .font(.footnote)
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(2)
          .minimumScaleFactor(0.88)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var offlineChapterCaption: String? {
    guard player.chapterCount > 0 else { return nil }
    let title = player.currentChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }
    return title
  }

  private var showsProgress: Bool {
    player.activeBook != nil && player.totalDuration > 0
  }

  private func offlineProgressTimeRow(totalDuration dur: Double, position pos: Double) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(formatPlaybackTime(dur))
        .frame(maxWidth: .infinity, alignment: .leading)
      offlineSleepTimerCountdownLabel
        .frame(minWidth: 52)
      Text(formatPlaybackTime(max(0, dur - pos)))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .font(.subheadline.monospacedDigit())
    .foregroundStyle(AppTheme.textSecondary)
  }

  @ViewBuilder
  private var offlineSleepTimerCountdownLabel: some View {
    if let seconds = player.sleepTimerDisplaySeconds, seconds > 0 {
      if player.sleepEndDate != nil {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
          Text(formatPlaybackTime(max(0, player.sleepTimerDisplaySeconds ?? seconds)))
            .foregroundStyle(themeAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
        }
      } else {
        Text(formatPlaybackTime(seconds))
          .foregroundStyle(themeAccent)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .frame(maxWidth: .infinity)
      }
    } else {
      Color.clear
        .frame(minWidth: 52, minHeight: 1)
        .accessibilityHidden(true)
    }
  }
}

// MARK: - Full player header (1:1)

private extension View {
  /// Gleicher 1:1-Rahmen für Cover und Read-along-Karte.
  func fullPlayerHeaderSquareFrame() -> some View {
    aspectRatio(1, contentMode: .fit)
      .frame(maxWidth: 400)
      .frame(maxWidth: .infinity)
  }
}

