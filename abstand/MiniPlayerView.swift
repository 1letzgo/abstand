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
  /// Abstand Autorzeile ↔ Fortschritts-Scrubber ↔ Panel-Steuerzeile (symmetrisch).
  static let scrubberVerticalSpacing: CGFloat = 20
  /// Abstand Panel-Steuerzeile bis Play-Button-Reihe.
  static let spacingAbovePlayRow: CGFloat = 24
  /// Abstand Play-Button-Reihe bis Utility-Bar (Speed, Download, …).
  static let spacingBelowPlayRow: CGFloat = 8
}

/// Fortschrittsbalken im Vollplayer — Anzeige; Scrub per Long-Press + Ziehen.
private enum FullPlayerProgressLayout {
  /// Gemeinsame Zeilenhöhe für Buch- und Kapitel-Scrubber.
  static let rowHeight: CGFloat = 14
  static let trackHeight: CGFloat = 12
  static let scrubThumbDiameter: CGFloat = 16
}

/// Layout für Buch- und Kapitel-Scrubber (ohne Kartenhülle).
private enum FullPlayerScrubberLayout {
  static let blockSpacing: CGFloat = 10
  /// Freiraum oberhalb des sichtbaren Balkens (Scrub-Thumb).
  static let paddingAboveBar: CGFloat = 6
  /// Abstand Fortschrittsbalken → Laufzeiten.
  static let barToTimeSpacing: CGFloat = 2

  static var scrubTrackBlockHeight: CGFloat {
    paddingAboveBar + FullPlayerProgressLayout.rowHeight
  }
}

private struct FullPlayerProgressTrack: View {
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  let value: Double
  let total: Double
  /// Relative Positionen (0…1) der Kapitelgrenzen.
  var chapterMarkers: [Double] = []
  var showsScrubThumb = false
  var trackHeight: CGFloat = FullPlayerProgressLayout.trackHeight
  var rowHeight: CGFloat = FullPlayerProgressLayout.rowHeight
  var accessibilityLabelText = "Playback position"
  var onSeek: ((Double) -> Void)?

  private var fraction: Double {
    guard total > 0 else { return 0 }
    return min(1, max(0, value / total))
  }

  private var trackCornerRadius: CGFloat { trackHeight / 2 }

  var body: some View {
    let _ = themeRevision
    return GeometryReader { geo in
      let w = geo.size.width
      let fillWidth = max(0, w * fraction)
      let fillTrailingRadius = fraction >= 0.999 ? trackCornerRadius : 0.0
      ZStack(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(AppTheme.progressTrack)
          .frame(height: trackHeight)
        themeAccent
          .frame(width: fillWidth, height: trackHeight)
          .clipShape(
            UnevenRoundedRectangle(
              topLeadingRadius: trackCornerRadius,
              bottomLeadingRadius: trackCornerRadius,
              bottomTrailingRadius: fillTrailingRadius,
              topTrailingRadius: fillTrailingRadius,
              style: .continuous
            )
          )
        ForEach(Array(chapterMarkers.enumerated()), id: \.element) { _, marker in
          Rectangle()
            .fill(AppTheme.textSecondary.opacity(0.65))
            .frame(width: 1, height: trackHeight)
            .offset(x: max(0, w * marker - 0.5))
        }
        if showsScrubThumb {
          Circle()
            .fill(themeAccent)
            .overlay {
              Circle()
                .strokeBorder(AppTheme.background, lineWidth: 2)
            }
            .frame(
              width: FullPlayerProgressLayout.scrubThumbDiameter,
              height: FullPlayerProgressLayout.scrubThumbDiameter
            )
            .offset(x: max(0, fillWidth - FullPlayerProgressLayout.scrubThumbDiameter / 2))
        }
      }
      .frame(width: w, height: rowHeight)
      .frame(maxHeight: .infinity, alignment: .center)
    }
    .frame(height: rowHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabelText)
    .accessibilityValue(fullPlayerProgressAccessibilityValue)
    .accessibilityAdjustableAction { direction in
      guard total > 0 else { return }
      let step = max(15, total * 0.02)
      switch direction {
      case .increment:
        onSeek?(min(total, value + step))
      case .decrement:
        onSeek?(max(0, value - step))
      @unknown default:
        break
      }
    }
  }

  private var fullPlayerProgressAccessibilityValue: String {
    let pct = Int((fraction * 100).rounded())
    guard !chapterMarkers.isEmpty else { return "\(pct) percent" }
    return "\(pct) percent, \(chapterMarkers.count + 1) chapters"
  }
}

/// Vollplayer-Fortschritt: Long-Press auf dem Balken, dann ziehen zum Suchen.
private struct FullPlayerScrubberSection: View {
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let player: PlaybackController
  let globalPosition: Double
  let totalDuration: Double
  let chapterCount: Int
  let chapterMarkerFractions: [Double]
  let currentChapterTitle: String
  let currentChapterOrdinal: Int
  let isBuffering: Bool
  let hasActiveBook: Bool
  let centerCaption: String

  @State private var isScrubbing = false
  @State private var scrubPosition: Double = 0
  @State private var didScrubHaptic = false
  @State private var isChapterScrubbing = false
  @State private var chapterScrubGlobal: Double = 0
  @State private var didChapterScrubHaptic = false

  private var duration: Double { max(totalDuration, 1) }

  private var displayGlobalPosition: Double {
    if isScrubbing { return scrubPosition }
    if isChapterScrubbing { return chapterScrubGlobal }
    return globalPosition
  }

  private var scrubEnabled: Bool {
    hasActiveBook && totalDuration > 0 && !isBuffering
  }

  private var showsChapterProgress: Bool { chapterCount > 0 }

  var body: some View {
    let _ = themeRevision
    let dur = duration
    let pos = min(max(0, displayGlobalPosition), dur)

    VStack(alignment: .leading, spacing: FullPlayerScrubberLayout.blockSpacing) {
      bookScrubberBlock(pos: pos, dur: dur)

      if showsChapterProgress, let chapter = chapterProgressForDisplay() {
        chapterProgressSection(chapter: chapter)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityHint("Long press and drag on the bar to seek.")
  }

  private func bookScrubberBlock(pos: Double, dur: Double) -> some View {
    VStack(alignment: .leading, spacing: FullPlayerScrubberLayout.barToTimeSpacing) {
      GeometryReader { geo in
        let trackWidth = max(geo.size.width, 1)
        VStack(spacing: 0) {
          Spacer(minLength: 0)
            .frame(height: FullPlayerScrubberLayout.paddingAboveBar)
          FullPlayerProgressTrack(
            value: pos,
            total: dur,
            chapterMarkers: chapterMarkerFractions,
            showsScrubThumb: isScrubbing,
            onSeek: { player.seek(global: $0) }
          )
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        .contentShape(Rectangle())
        .gesture(scrubEnabled ? bookScrubGesture(trackWidth: trackWidth) : nil)
      }
      .frame(height: FullPlayerScrubberLayout.scrubTrackBlockHeight)

      HStack {
        Text(formatPlaybackTime(pos))
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
        Spacer()
        if !centerCaption.isEmpty, !isScrubbing, !isChapterScrubbing {
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

  @ViewBuilder
  private func chapterProgressSection(
    chapter: (position: Double, duration: Double, start: Double)
  ) -> some View {
    let chPos = min(max(0, chapter.position), chapter.duration)
    VStack(alignment: .leading, spacing: FullPlayerScrubberLayout.barToTimeSpacing) {
      GeometryReader { geo in
        let trackWidth = max(geo.size.width, 1)
        VStack(spacing: 0) {
          Spacer(minLength: 0)
            .frame(height: FullPlayerScrubberLayout.paddingAboveBar)
          FullPlayerProgressTrack(
            value: chPos,
            total: chapter.duration,
            showsScrubThumb: isChapterScrubbing,
            accessibilityLabelText: "Chapter position",
            onSeek: { player.seek(global: $0) }
          )
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        .contentShape(Rectangle())
        .gesture(scrubEnabled ? chapterScrubGesture(trackWidth: trackWidth, chapter: chapter) : nil)
      }
      .frame(height: FullPlayerScrubberLayout.scrubTrackBlockHeight)

      HStack {
        Text(formatPlaybackTime(chPos))
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
        Spacer()
        Text(chapterCaption)
          .font(.caption)
          .foregroundStyle(AppTheme.textPrimary)
          .lineLimit(1)
          .accessibilityLabel("Chapter")
          .accessibilityValue(chapterCaption)
        Spacer()
        Text(formatPlaybackTime(max(0, chapter.duration - chPos)))
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
      }
      .monospacedDigit()
    }
  }

  private var chapterCaption: String {
    let raw = currentChapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !raw.isEmpty { return raw }
    if currentChapterOrdinal > 0 { return "Chapter \(currentChapterOrdinal)" }
    return String(localized: "Chapter", comment: "Player chapter progress label")
  }

  private func chapterProgressForDisplay() -> (position: Double, duration: Double, start: Double)? {
    player.currentChapterProgress(global: displayGlobalPosition)
  }

  private func bookScrubGesture(trackWidth: CGFloat) -> some Gesture {
    LongPressGesture(minimumDuration: 0.35)
      .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
      .onChanged { value in
        switch value {
        case .second(true, let drag?):
          if !isScrubbing {
            isScrubbing = true
            scrubPosition = globalPosition
            if !didScrubHaptic {
              didScrubHaptic = true
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
          }
          scrubPosition = globalTime(forX: drag.location.x, trackWidth: trackWidth, total: duration)
        default:
          break
        }
      }
      .onEnded { value in
        defer {
          isScrubbing = false
          didScrubHaptic = false
        }
        guard case .second(true, _) = value else { return }
        player.seek(global: scrubPosition)
      }
  }

  private func chapterScrubGesture(
    trackWidth: CGFloat,
    chapter: (position: Double, duration: Double, start: Double)
  ) -> some Gesture {
    LongPressGesture(minimumDuration: 0.35)
      .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
      .onChanged { value in
        switch value {
        case .second(true, let drag?):
          if !isChapterScrubbing {
            isChapterScrubbing = true
            chapterScrubGlobal = displayGlobalPosition
            if !didChapterScrubHaptic {
              didChapterScrubHaptic = true
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
          }
          let fraction = min(1, max(0, Double(drag.location.x / trackWidth)))
          chapterScrubGlobal = chapter.start + fraction * chapter.duration
        default:
          break
        }
      }
      .onEnded { value in
        defer {
          isChapterScrubbing = false
          didChapterScrubHaptic = false
        }
        guard case .second(true, _) = value else { return }
        player.seek(global: chapterScrubGlobal)
      }
  }

  private func globalTime(forX x: CGFloat, trackWidth: CGFloat, total: Double) -> Double {
    let fraction = min(1, max(0, Double(x / trackWidth)))
    return fraction * total
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
  let offlineStorageId: String?
  let isDownloaded: Bool
  let isDownloading: Bool
  let downloadProgressBucket: Int
  let isLoggedIn: Bool

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.playbackRate == rhs.playbackRate
      && lhs.offlineStorageId == rhs.offlineStorageId
      && lhs.isDownloaded == rhs.isDownloaded
      && lhs.isDownloading == rhs.isDownloading
      && lhs.downloadProgressBucket == rhs.downloadProgressBucket
      && lhs.isLoggedIn == rhs.isLoggedIn
      && lhs.themeRevision == rhs.themeRevision
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

/// Transport + Utility-Bar — Equatable, ohne Positions-Ticks.
struct FullPlayerChromeSnapshot: Equatable {
  let hasActiveBook: Bool
  let chapterCount: Int
  let isBuffering: Bool
  let isPlaying: Bool
  let skipBackwardSeconds: Int
  let skipForwardSeconds: Int
  let canSkipToPreviousChapter: Bool
  let canSkipToNextChapter: Bool
  let playbackRate: Float
  let offlineStorageId: String?
  let isDownloaded: Bool
  let isDownloading: Bool
  let downloadProgressBucket: Int
  let isLoggedIn: Bool
  let sleepTimerModeSignature: Int

  static let empty = FullPlayerChromeSnapshot(
    hasActiveBook: false,
    chapterCount: 0,
    isBuffering: false,
    isPlaying: false,
    skipBackwardSeconds: ABSPlaybackSkipDefaults.backwardSeconds,
    skipForwardSeconds: ABSPlaybackSkipDefaults.forwardSeconds,
    canSkipToPreviousChapter: false,
    canSkipToNextChapter: false,
    playbackRate: 1,
    offlineStorageId: nil,
    isDownloaded: false,
    isDownloading: false,
    downloadProgressBucket: -1,
    isLoggedIn: false,
    sleepTimerModeSignature: 0
  )

  @MainActor
  static func make(model: AppModel) -> FullPlayerChromeSnapshot {
    let player = model.player
    let sid = model.currentPlaybackOfflineStorageId()
    let isDownloading = sid != nil && model.downloads.activeItemId == sid
    let sleepSig: Int = {
      switch player.sleepTimerMode {
      case .off: return 0
      case .minutes(let m): return 10_000 + m
      case .chapters(let c): return 20_000 + c
      }
    }()
    return FullPlayerChromeSnapshot(
      hasActiveBook: player.activeBook != nil,
      chapterCount: player.chapterCount,
      isBuffering: player.isBuffering,
      isPlaying: player.isPlaying,
      skipBackwardSeconds: player.skipBackwardSeconds,
      skipForwardSeconds: player.skipForwardSeconds,
      canSkipToPreviousChapter: player.canSkipToPreviousChapter,
      canSkipToNextChapter: player.canSkipToNextChapter,
      playbackRate: player.playbackRate,
      offlineStorageId: sid,
      isDownloaded: sid.map { model.downloadedItemIds.contains($0) } ?? false,
      isDownloading: isDownloading,
      downloadProgressBucket: isDownloading ? Int(model.downloads.progress * 20) : -1,
      isLoggedIn: model.isLoggedIn,
      sleepTimerModeSignature: sleepSig
    )
  }
}

struct FullPlayerScrubberSnapshot: Equatable {
  let globalPosition: Double
  let totalDuration: Double
  let chapterCount: Int
  let chapterMarkerFractions: [Double]
  let currentChapterTitle: String
  let currentChapterOrdinal: Int
  let isBuffering: Bool
  let hasActiveBook: Bool

  @MainActor
  static func make(player: PlaybackController) -> FullPlayerScrubberSnapshot {
    FullPlayerScrubberSnapshot(
      globalPosition: player.globalPosition,
      totalDuration: player.totalDuration,
      chapterCount: player.chapterCount,
      chapterMarkerFractions: player.chapterMarkerFractions,
      currentChapterTitle: player.currentChapterTitle,
      currentChapterOrdinal: player.currentChapterOrdinal,
      isBuffering: player.isBuffering,
      hasActiveBook: player.activeBook != nil
    )
  }
}

private struct FullPlayerTransportRowChrome: View, Equatable {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  let snapshot: FullPlayerChromeSnapshot
  let showsFullPlayerPanelControls: Bool
  let isCoverPanelExpanded: Bool

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.snapshot == rhs.snapshot
      && lhs.showsFullPlayerPanelControls == rhs.showsFullPlayerPanelControls
      && lhs.isCoverPanelExpanded == rhs.isCoverPanelExpanded
      && lhs.themeRevision == rhs.themeRevision
  }

  var body: some View {
    let _ = themeRevision
    let player = model.player
    let hasChapters = snapshot.chapterCount > 0
    let isBusy = snapshot.hasActiveBook && snapshot.isBuffering
  return HStack(alignment: .center, spacing: 0) {
      fullPlayerTransportChapterSlot(isLeading: true, hasChapters: hasChapters, player: player)
        .frame(maxWidth: .infinity)

      Button {
        player.skip(seconds: -Double(snapshot.skipBackwardSeconds))
      } label: {
        Image(systemName: PlaybackController.gobackwardSystemImage(seconds: snapshot.skipBackwardSeconds))
          .font(FullPlayerTransportLayout.auxiliarySymbolFont)
      }
      .disabled(isBusy)
      .accessibilityLabel(
        PlaybackController.skipAccessibilityLabel(
          backward: true, seconds: snapshot.skipBackwardSeconds))
      .frame(maxWidth: .infinity)

      Button {
        player.togglePlayPause()
      } label: {
        Group {
          if isBusy {
            ProgressView()
              .controlSize(.large)
              .tint(model.appearancePalette.foregroundOnAccent(themeAccent))
          } else {
            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
              .font(.largeTitle)
              .symbolVariant(.fill)
              .foregroundStyle(model.appearancePalette.foregroundOnAccent(themeAccent))
          }
        }
        .frame(width: 72, height: 44)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .clipShape(Capsule(style: .continuous))
      .tint(themeAccent)
      .disabled(!snapshot.hasActiveBook)
      .frame(maxWidth: .infinity)

      Button {
        player.skip(seconds: Double(snapshot.skipForwardSeconds))
      } label: {
        Image(systemName: PlaybackController.goforwardSystemImage(seconds: snapshot.skipForwardSeconds))
          .font(FullPlayerTransportLayout.auxiliarySymbolFont)
      }
      .disabled(isBusy)
      .accessibilityLabel(
        PlaybackController.skipAccessibilityLabel(
          backward: false, seconds: snapshot.skipForwardSeconds))
      .frame(maxWidth: .infinity)

      fullPlayerTransportChapterSlot(isLeading: false, hasChapters: hasChapters, player: player)
        .frame(maxWidth: .infinity)
    }
    .foregroundStyle(AppTheme.textPrimary)
    .buttonStyle(.borderless)
    .padding(
      .top,
      showsFullPlayerPanelControls ? 0 : FullPlayerTransportLayout.spacingAbovePlayRow
    )
    .padding(.bottom, FullPlayerTransportLayout.spacingBelowPlayRow)
    .animation(nil, value: isCoverPanelExpanded)
  }

  @ViewBuilder
  private func fullPlayerTransportChapterSlot(
    isLeading: Bool,
    hasChapters: Bool,
    player: PlaybackController
  ) -> some View {
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
      .disabled(isLeading ? !snapshot.canSkipToPreviousChapter : !snapshot.canSkipToNextChapter)
      .accessibilityLabel(isLeading ? "Previous chapter" : "Next chapter")
    } else {
      Image(systemName: symbol)
        .font(FullPlayerTransportLayout.auxiliarySymbolFont)
        .symbolVariant(.fill)
        .hidden()
        .accessibilityHidden(true)
    }
  }
}

private struct NowPlayingCoverHeaderShell<Content: View>: View {
  @ObservedObject var player: PlaybackController
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
  }
}

struct NowPlayingDetailView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  @State private var readAlongDownloadWarningPresented = false
  @State private var chromeSnapshot = FullPlayerChromeSnapshot.empty
  @State private var activeBook: ABSBook?
  @State private var isTeleprompterActive = false
  @AppStorage(PlayerTeleprompterMetrics.fontSizeStorageKey) private var teleprompterFontSizeStorage: Double = 0
  @State private var coverPanel: FullPlayerCoverPanel = .artwork
  @State private var panelBookDetail: ABSBook?
  @State private var panelListeningSessions: [ABSListeningSession] = []

  private var player: PlaybackController { model.player }

  /// Cover durch Teleprompter oder Kapitel-/Sessions-/Bookmarks-Panel ersetzt.
  private var isCoverPanelExpanded: Bool {
    isTeleprompterActive || coverPanel != .artwork || showsReadAlongErrorCard
  }

  /// Nach fehlgeschlagenem Start: Karte mit „Try again“ statt sofort zum Cover zurückspringen.
  /// Nur solange kein anderes Panel angewählt wurde (sonst hätte der Nutzer bereits weggeklickt).
  private var showsReadAlongErrorCard: Bool {
    !isTeleprompterActive
      && coverPanel == .artwork
      && player.liveTranscription.errorMessage != nil
  }

  private var isAudiobookPlayback: Bool {
    guard let activeBook else { return false }
    let ep = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return ep.isEmpty && activeBook.isPlayableAudiobook
  }

  private var panelChapterBook: ABSBook? {
    panelBookDetail ?? activeBook
  }

  private var showsChaptersButton: Bool {
    isAudiobookPlayback
  }

  private var showsSessionsButton: Bool {
    activeBook != nil
  }

  private var showsDescriptionButton: Bool {
    activeBook != nil
  }

  private var showsConnectionLoading: Bool {
    model.isPlayerConnectionLoading && activeBook == nil
  }

  private func refreshChromeSnapshot() {
    chromeSnapshot = FullPlayerChromeSnapshot.make(model: model)
  }

  var body: some View {
    fullPlayerRootWithSnapshotHooks
      .task {
        await player.liveTranscription.refreshReadAlongAvailability()
      }
      .onDisappear {
        player.liveTranscription.wordLookupSelection = nil
        if player.liveTranscription.isTeleprompterModeActive {
          Task { @MainActor in
            await player.liveTranscription.disable()
          }
        } else if player.liveTranscription.errorMessage != nil {
          player.liveTranscription.dismissError()
        }
        coverPanel = .artwork
      }
      .onChange(of: isTeleprompterActive) { _, active in
        if active { coverPanel = .artwork }
      }
      .onChange(of: player.liveTranscription.errorMessage) { _, err in
        if let err, !AbstandErrorFilter.isBenignCancellationMessage(err) {
          model.errorMessage = err
        }
      }
      .onChange(of: player.activeBook?.id) { _, _ in
        coverPanel = .artwork
        panelBookDetail = nil
        panelListeningSessions = []
      }
      .task(id: coverPanel) {
        await loadCoverPanelDataIfNeeded()
      }
      // Am stabilen Player-Root statt in der Teleprompter-View: die Translation-Session
      // crasht (fatalError), wenn ihre Anker-View verschwindet (Rotation, Card-Swap).
      .sheet(
        item: Binding(
          get: { player.liveTranscription.wordLookupSelection },
          set: { player.liveTranscription.wordLookupSelection = $0 }
        )
      ) { selection in
        PlayerTranscriptWordLookupSheet(
          selection: selection,
          sourceLocale: selection.sourceLocale,
          model: model
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
      }
      .alert(
        String(localized: "Download required", comment: "Read along alert title"),
        isPresented: $readAlongDownloadWarningPresented
      ) {
        Button(String(localized: "OK", comment: "Dismiss"), role: .cancel) {}
      } message: {
        Text(
          String(
            localized: "Read along only works when the audiobook is fully downloaded.",
            comment: "Read along download required alert")
        )
      }
  }

  private var fullPlayerRootWithSnapshotHooks: some View {
    fullPlayerStack
      .preferredColorScheme(model.resolvedInterfaceColorScheme)
      .onAppear {
        activeBook = player.activeBook
        isTeleprompterActive = player.liveTranscription.isTeleprompterModeActive
        player.liveTranscription.sanitizeInteractionStateForControls()
        refreshChromeSnapshot()
      }
      .onReceive(player.$activeBook) { book in
        activeBook = book
        refreshChromeSnapshot()
      }
      .onReceive(player.$isPlaying) { _ in refreshChromeSnapshot() }
      .onReceive(player.$isBuffering) { _ in refreshChromeSnapshot() }
      .onReceive(player.$chapterCount) { _ in refreshChromeSnapshot() }
      .onReceive(player.$playbackRate) { _ in refreshChromeSnapshot() }
      .onReceive(player.$skipBackwardSeconds) { _ in refreshChromeSnapshot() }
      .onReceive(player.$skipForwardSeconds) { _ in refreshChromeSnapshot() }
      .onReceive(player.$sleepTimerMode) { _ in refreshChromeSnapshot() }
      .onReceive(model.downloads.objectWillChange.receive(on: DispatchQueue.main)) { _ in
        refreshChromeSnapshot()
      }
      .onReceive(model.$downloadedItemIds) { _ in refreshChromeSnapshot() }
      .onReceive(player.liveTranscription.objectWillChange.receive(on: DispatchQueue.main)) { _ in
        isTeleprompterActive = player.liveTranscription.isTeleprompterModeActive
      }
  }

  private var fullPlayerStack: some View {
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
      if let b = activeBook {
        fullPlayerPortraitLayout(book: b)
      } else if showsConnectionLoading {
        connectionLoadingPlaceholder
      } else {
        idlePlaceholder
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var showsFullPlayerPanelControls: Bool {
    player.liveTranscription.isReadAlongAvailable
      || showsDescriptionButton
      || activeAudiobookBookmarkId != nil
      || showsChaptersButton
      || showsSessionsButton
  }

  @ViewBuilder
  private func fullPlayerPortraitLayout(book: ABSBook) -> some View {
    let panelExpanded = isCoverPanelExpanded
    VStack(spacing: 0) {
      if panelExpanded {
        playerHeaderArea(book: book)
          .frame(maxWidth: .infinity)
          .frame(maxHeight: .infinity, alignment: .top)
          .layoutPriority(1)
      } else {
        VStack(spacing: 0) {
          playerHeaderArea(book: book)
            .frame(maxWidth: .infinity, alignment: .top)
          Spacer(minLength: 0)
          chapterTitleArea(book: book)
          Spacer(minLength: 0)
          TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            scrubberSection(book: book)
          }
        }
        .frame(maxWidth: 800)
        .frame(maxHeight: .infinity)
      }

      fullPlayerPanelControlRow()
        .frame(maxWidth: 800)

      FullPlayerTransportRowChrome(
        snapshot: chromeSnapshot,
        showsFullPlayerPanelControls: showsFullPlayerPanelControls,
        isCoverPanelExpanded: panelExpanded
      )
      .equatable()
      .frame(maxWidth: 800)

      fullPlayerUtilityBar
        .equatable()
      Spacer(minLength: 8)
    }
    .animation(.easeInOut(duration: 0.28), value: panelExpanded)
    .animation(.easeInOut(duration: 0.28), value: coverPanel)
  }

  private var landscapeLayout: some View {
    Group {
      if let b = activeBook {
        fullPlayerLandscapeLayout(book: b)
      } else {
        restoringOrIdleInLandscape
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private func fullPlayerLandscapeLayout(book: ABSBook) -> some View {
    let panelExpanded = isCoverPanelExpanded
    HStack(alignment: .top, spacing: MiniPlayerMetrics.fullPlayerCoverInset) {
      playerHeaderArea(book: book)
        .containerRelativeFrame(.horizontal) { w, _ in w * 0.48 }
        .frame(maxHeight: .infinity, alignment: .top)
        .layoutPriority(panelExpanded ? 1 : 0)
      VStack(spacing: 0) {
        if !panelExpanded {
          chapterTitleArea(book: book)
          TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            scrubberSection(book: book)
          }
        } else {
          Spacer(minLength: 0)
        }
        fullPlayerPanelControlRow()
        FullPlayerTransportRowChrome(
          snapshot: chromeSnapshot,
          showsFullPlayerPanelControls: showsFullPlayerPanelControls,
          isCoverPanelExpanded: panelExpanded
        )
        .equatable()
        fullPlayerUtilityBar
          .equatable()
        Spacer(minLength: 8)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .animation(.easeInOut(duration: 0.28), value: panelExpanded)
    .animation(.easeInOut(duration: 0.28), value: coverPanel)
  }

  private var restoringOrIdleInLandscape: some View {
    Group {
      if showsConnectionLoading {
        connectionLoadingPlaceholder
      } else {
        idlePlaceholder
      }
    }
  }

  /// Titel und Autor unter dem Cover.
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
    .padding(.top, 12)
    .padding(.bottom, FullPlayerTransportLayout.scrubberVerticalSpacing)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func playerHeaderArea(book: ABSBook) -> some View {
    NowPlayingCoverHeaderShell(player: player) {
      Group {
        if isTeleprompterActive || showsReadAlongErrorCard {
          readAlongKaraokeCard()
        } else if coverPanel == .bookmarks, let audiobookId = activeAudiobookBookmarkId {
          bookmarksCoverCard(audiobookId: audiobookId)
        } else if coverPanel != .artwork {
          fullPlayerExpandedListCard(book: book)
        } else {
          fullPlayerArtworkCard(book: book)
        }
      }
    }
  }

  /// Quadratische Cover-Karte (1:1) — nur für Artwork.
  private func fullPlayerSquareCoverCard<Overlay: View>(
    cardOpacity: CGFloat = 1,
    @ViewBuilder overlay: @escaping () -> Overlay
  ) -> some View {
    let corner = FullPlayerCoverOverlayMetrics.coverSurfaceCornerRadius
    let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
    return Color.clear
      .aspectRatio(1, contentMode: .fit)
      .frame(maxWidth: .infinity, alignment: .top)
      .background(AppTheme.card.opacity(cardOpacity), in: shape)
      .overlay {
        GeometryReader { geo in
          overlay()
            .frame(width: geo.size.width, height: geo.size.height)
        }
      }
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
      }
      .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
  }

  /// Ausgeklapptes Panel/Teleprompter — volle Höhe bis zur Panel-Steuerzeile (ohne Schatten).
  private func fullPlayerExpandedCoverCard<Overlay: View>(
    cardOpacity: CGFloat = 0.35,
    @ViewBuilder overlay: @escaping () -> Overlay
  ) -> some View {
    let corner = FullPlayerCoverOverlayMetrics.coverSurfaceCornerRadius
    let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
    return Color.clear
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(AppTheme.card.opacity(cardOpacity), in: shape)
      .overlay {
        overlay()
      }
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
      }
  }

  /// Nur Cover-Bild (1:1).
  private func fullPlayerArtworkCard(book: ABSBook) -> some View {
    fullPlayerSquareCoverCard {
      CoverImageView(
        url: model.coverURL(for: book.id, tier: .hero),
        token: model.token,
        itemId: book.id,
        cacheAccount: model.coverImageCacheAccountDirectory(),
        cacheScopeId: model.coverImageCacheScopeId(for: book.id, tier: .hero),
        cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: book.updatedAt),
        contentMode: .fill
      )
    }
  }

  /// Kapitel-, Sessions- oder Bookmarks-Panel — klappt bis zur Progress-Karte auf.
  private func fullPlayerExpandedListCard(book: ABSBook) -> some View {
    fullPlayerExpandedCoverCard {
      fullPlayerCoverPanelBody(book: book)
    }
    .animation(.easeInOut(duration: 0.22), value: coverPanel)
  }

  @ViewBuilder
  private func fullPlayerCoverPanelBody(book: ABSBook) -> some View {
    switch coverPanel {
    case .artwork:
      EmptyView()
    case .description:
      fullPlayerCoverPanelContent(title: "Description") {
        BookDescriptionPanelView(text: resolvedBookDescriptionText(for: book))
      }
    case .chapters:
      if let chapterBook = panelChapterBook {
        fullPlayerCoverPanelContent(title: "Chapters") {
          BookChapterListView(
            book: chapterBook,
            progress: model.progressByItemId[chapterBook.id]
          ) { chapter in
            Task {
              await model.play(book: chapterBook, resumeAtOverride: chapter.start, autoPlay: true)
            }
          }
        }
      }
    case .sessions:
      fullPlayerCoverPanelContent(title: "Listening history") {
        let isEpisode = model.podcastEpisodeForActivePlayback() != nil
        ListeningHistorySessionList(
          sessions: panelListeningSessions,
          isNetworkReachable: model.isNetworkReachable,
          emptyOnlineText: isEpisode
            ? "No listening sessions recorded for this episode yet."
            : "No listening sessions recorded for this book yet.",
          emptyOfflineText: "Listening history is unavailable offline.",
          onJumpToSessionStart: { session in
            Task {
              if let episode = model.podcastEpisodeForActivePlayback() {
                await model.playPodcastEpisode(
                  episode, autoPlay: true, resumeAtOverride: session.startTime)
              } else {
                await model.play(book: book, resumeAtOverride: session.startTime, autoPlay: true)
              }
            }
          }
        )
      }
    case .bookmarks:
      EmptyView()
    }
  }

  /// Bookmarks-Panel — Liste oben, „Add“ kompakt unten rechts (wie Teleprompter ±).
  private func bookmarksCoverCard(audiobookId: String) -> some View {
    fullPlayerExpandedCoverCard {
      GeometryReader { geo in
        let pad = PlayerTeleprompterMetrics.cardContentPadding
        let controlsBlock = FullPlayerCoverOverlayMetrics.teleprompterControlsBlockHeight
        let titleBlock = pad + 22
        let listHeight = max(
          0,
          geo.size.height - pad - FullPlayerCoverOverlayMetrics.verticalInset - controlsBlock - titleBlock
        )
        VStack(spacing: FullPlayerCoverOverlayMetrics.teleprompterControlsSpacingAbove) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Bookmarks")
              .font(.caption.weight(.bold))
              .foregroundStyle(AppTheme.textSecondary)
              .textCase(.uppercase)
              .tracking(0.6)
            ScrollView {
              AudiobookBookmarkListView(libraryItemId: audiobookId) { mark in
                Task { await model.jumpToBookmark(mark, autoPlay: true) }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: listHeight)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

          HStack {
            Spacer(minLength: 0)
            PlayerBookmarkAddCoverControl(
              activeAudiobookId: audiobookId,
              menuItems: model.bookmarks(for: audiobookId).map(PlayerBookmarkMenuItem.init),
              compact: true
            )
          }
        }
        .padding(.horizontal, pad)
        .padding(.top, pad)
        .padding(.bottom, FullPlayerCoverOverlayMetrics.verticalInset)
      }
    }
    .accessibilityLabel(String(localized: "Bookmarks", comment: "Accessibility"))
  }

  private func fullPlayerCoverPanelContent<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let pad = PlayerTeleprompterMetrics.cardContentPadding
    return VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .textCase(.uppercase)
        .tracking(0.6)
        .padding(.horizontal, pad)
        .padding(.top, pad)
      ScrollView {
        content()
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, pad)
          .padding(.bottom, pad)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private func loadCoverPanelDataIfNeeded() async {
    guard let activeBook = player.activeBook else { return }
    switch coverPanel {
    case .artwork, .bookmarks:
      break
    case .description, .chapters:
      if panelBookDetail?.id != activeBook.id {
        panelBookDetail = await model.loadBookDetail(id: activeBook.id)
      } else if coverPanel == .chapters,
        (panelBookDetail?.media.chapters ?? []).isEmpty
      {
        panelBookDetail = await model.loadBookDetail(id: activeBook.id)
      }
    case .sessions:
      if let episode = model.podcastEpisodeForActivePlayback() {
        let showMid =
          model.podcastShows.first(where: { $0.id == episode.libraryItemId })?.mediaId
          ?? model.podcastSearchBooks.first(where: { $0.id == episode.libraryItemId })?.mediaId
        panelListeningSessions = await model.loadPodcastEpisodeListeningSessions(
          episode, showMediaId: showMid)
      } else {
        let detail = panelBookDetail?.id == activeBook.id
          ? panelBookDetail
          : await model.loadBookDetail(id: activeBook.id)
        if panelBookDetail?.id != activeBook.id {
          panelBookDetail = detail
        }
        panelListeningSessions = await model.loadBookListeningSessions(
          libraryItemId: activeBook.id,
          bookMediaId: detail?.mediaId ?? activeBook.mediaId
        )
      }
    }
  }

  private func toggleCoverPanel(_ panel: FullPlayerCoverPanel) {
    if coverPanel == panel {
      coverPanel = .artwork
      return
    }
    if isTeleprompterActive {
      Task { @MainActor in
        await player.liveTranscription.disable()
      }
    } else if player.liveTranscription.errorMessage != nil {
      player.liveTranscription.dismissError()
    }
    coverPanel = panel
  }

  private func resolvedBookDescriptionText(for book: ABSBook) -> String {
    let source = panelBookDetail?.id == book.id ? panelBookDetail : book
    let meta = source?.media.metadata ?? book.media.metadata
    let raw = meta.descriptionPlain ?? meta.description
    return absPlainText(fromHTML: raw)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @ViewBuilder
  private func fullPlayerPanelControlRow() -> some View {
    if showsFullPlayerPanelControls {
      let items = fullPlayerPanelControlKinds(
        showsReadAlong: player.liveTranscription.isReadAlongAvailable
      )
      HStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, kind in
          if index > 0 {
            Spacer(minLength: 0)
          }
          fullPlayerPanelControlButton(kind: kind)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: FullPlayerUtilityBarLayout.primaryRowHeight)
      .padding(.top, FullPlayerTransportLayout.scrubberVerticalSpacing)
      .padding(.bottom, FullPlayerTransportLayout.spacingAbovePlayRow)
    }
  }

  private enum FullPlayerPanelControlKind: Identifiable {
    case description
    case bookmarkList
    case chapters
    case sessions
    /// Leerer Platzhalter zwischen History und Read-along bei >3 Buttons.
    case panelSpacer
    case readAlong

    var id: String {
      switch self {
      case .description: "description"
      case .bookmarkList: "bookmarkList"
      case .chapters: "chapters"
      case .sessions: "sessions"
      case .panelSpacer: "panelSpacer"
      case .readAlong: "readAlong"
      }
    }
  }

  private func fullPlayerPanelControlKinds(showsReadAlong: Bool) -> [FullPlayerPanelControlKind] {
    var items: [FullPlayerPanelControlKind] = []
    if showsDescriptionButton { items.append(.description) }
    if activeAudiobookBookmarkId != nil {
      items.append(.bookmarkList)
    }
    if showsChaptersButton { items.append(.chapters) }
    if showsSessionsButton { items.append(.sessions) }
    if showsReadAlong {
      if items.count > 3 {
        items.append(.panelSpacer)
      }
      items.append(.readAlong)
    }
    return items
  }

  @ViewBuilder
  private func fullPlayerPanelControlButton(kind: FullPlayerPanelControlKind) -> some View {
    switch kind {
    case .description:
      FullPlayerCoverOverlayButton(
        systemName: "doc.text",
        isActive: coverPanel == .description,
        accessibilityLabel: coverPanel == .description ? "Hide description" : "Show description"
      ) {
        toggleCoverPanel(.description)
      }
    case .bookmarkList:
      FullPlayerCoverOverlayButton(
        systemName: "text.book.closed",
        isActive: coverPanel == .bookmarks,
        accessibilityLabel: coverPanel == .bookmarks ? "Hide bookmarks" : "Show bookmarks"
      ) {
        toggleCoverPanel(.bookmarks)
      }
    case .chapters:
      FullPlayerCoverOverlayButton(
        systemName: "list.bullet",
        isActive: coverPanel == .chapters,
        accessibilityLabel: coverPanel == .chapters ? "Hide chapters" : "Show chapters"
      ) {
        toggleCoverPanel(.chapters)
      }
    case .sessions:
      FullPlayerCoverOverlayButton(
        systemName: "clock.arrow.circlepath",
        isActive: coverPanel == .sessions,
        accessibilityLabel: coverPanel == .sessions ? "Hide listening history" : "Show listening history"
      ) {
        toggleCoverPanel(.sessions)
      }
    case .panelSpacer:
      FullPlayerPanelControlSpacerPill()
    case .readAlong:
      ReadAlongPanelButton(readAlongDownloadWarningPresented: $readAlongDownloadWarningPresented) {
        coverPanel = .artwork
      }
    }
  }
  private var teleprompterFontSizeControls: some View {
    let sizingHeight = teleprompterFontSizingReferenceHeight
    let stored = teleprompterFontSizeStorage > 0 ? CGFloat(teleprompterFontSizeStorage) : nil
    let current = stored
      ?? PlayerTeleprompterMetrics.savedFontSize()
      ?? PlayerTeleprompterMetrics.autoFontSize(sizingViewportHeight: sizingHeight)
    let atMin = current <= PlayerTeleprompterMetrics.minFontSize + 0.01
    let atMax = current >= PlayerTeleprompterMetrics.maxFontSize - 0.01
    return HStack(spacing: 8) {
      FullPlayerCoverOverlayButton(
        systemName: "minus",
        isActive: false,
        isEnabled: !atMin,
        compact: true,
        accessibilityLabel: String(
          localized: "Decrease teleprompter text size", comment: "Accessibility")
      ) {
        teleprompterFontSizeStorage = Double(
          PlayerTeleprompterMetrics.bumpFontSize(
            delta: -PlayerTeleprompterMetrics.fontSizeStep,
            sizingViewportHeight: sizingHeight,
            storedFontSize: stored ?? PlayerTeleprompterMetrics.savedFontSize()
          )
        )
      }
      FullPlayerCoverOverlayButton(
        systemName: "plus",
        isActive: false,
        isEnabled: !atMax,
        compact: true,
        accessibilityLabel: String(
          localized: "Increase teleprompter text size", comment: "Accessibility")
      ) {
        teleprompterFontSizeStorage = Double(
          PlayerTeleprompterMetrics.bumpFontSize(
            delta: PlayerTeleprompterMetrics.fontSizeStep,
            sizingViewportHeight: sizingHeight,
            storedFontSize: stored ?? PlayerTeleprompterMetrics.savedFontSize()
          )
        )
      }
    }
    .contentShape(Rectangle())
  }

  /// Referenzbreite für Auto-Schrift und erste +/--Anpassung (≈ Kartenbreite).
  private var teleprompterFontSizingReferenceHeight: CGFloat {
    let inset = MiniPlayerMetrics.fullPlayerCoverInset * 2
    let screenWidth = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first?.screen.bounds.width ?? 390
    let width = screenWidth - inset
    return min(max(width, 280), 400)
  }

  private var resolvedTeleprompterUserFontSize: CGFloat? {
    if teleprompterFontSizeStorage > 0 {
      return CGFloat(teleprompterFontSizeStorage)
    }
    return PlayerTeleprompterMetrics.savedFontSize()
  }

  /// Hörbuch-ID für Lesezeichen (keine Podcast-Folgen).
  private var activeAudiobookBookmarkId: String? {
    guard let id = player.activeBook?.id else { return nil }
    let episode = player.activePlaybackEpisodeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return episode.isEmpty ? id : nil
  }

  /// Teleprompter-Karte — klappt bis zur Progress-Karte auf.
  private func readAlongKaraokeCard() -> some View {
    fullPlayerExpandedCoverCard {
      GeometryReader { geo in
        let pad = PlayerTeleprompterMetrics.cardContentPadding
        let controlsBlock = FullPlayerCoverOverlayMetrics.teleprompterControlsBlockHeight
        let transcriptHeight = max(0, geo.size.height - pad - FullPlayerCoverOverlayMetrics.verticalInset - controlsBlock)
        VStack(spacing: FullPlayerCoverOverlayMetrics.teleprompterControlsSpacingAbove) {
          PlayerLiveTranscriptPanelView(
            player: player,
            transcription: player.liveTranscription,
            viewportSize: CGSize(
              width: max(0, geo.size.width - pad * 2),
              height: transcriptHeight
            ),
            userFontSize: resolvedTeleprompterUserFontSize
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          HStack {
            Spacer(minLength: 0)
            teleprompterFontSizeControls
          }
        }
        .padding(.horizontal, pad)
        .padding(.top, pad)
        .padding(.bottom, FullPlayerCoverOverlayMetrics.verticalInset)
      }
    }
    .accessibilityLabel(String(localized: "Read along transcript", comment: "Accessibility"))
  }

  private func scrubberSection(book: ABSBook) -> some View {
    let scrubSnapshot = FullPlayerScrubberSnapshot.make(player: player)
    return FullPlayerScrubberSection(
      player: player,
      globalPosition: scrubSnapshot.globalPosition,
      totalDuration: scrubSnapshot.totalDuration,
      chapterCount: scrubSnapshot.chapterCount,
      chapterMarkerFractions: scrubSnapshot.chapterMarkerFractions,
      currentChapterTitle: scrubSnapshot.currentChapterTitle,
      currentChapterOrdinal: scrubSnapshot.currentChapterOrdinal,
      isBuffering: scrubSnapshot.isBuffering,
      hasActiveBook: scrubSnapshot.hasActiveBook,
      centerCaption: ""
    )
  }

  private var fullPlayerUtilityBar: FullPlayerUtilityBar {
    FullPlayerUtilityBar(
      playbackRate: chromeSnapshot.playbackRate,
      offlineStorageId: chromeSnapshot.offlineStorageId,
      isDownloaded: chromeSnapshot.isDownloaded,
      isDownloading: chromeSnapshot.isDownloading,
      downloadProgressBucket: chromeSnapshot.downloadProgressBucket,
      isLoggedIn: chromeSnapshot.isLoggedIn
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

/// Read-along-Button — `@EnvironmentObject` `PlaybackController`, damit Busy-State die UI erreicht.
private struct ReadAlongPanelButton: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var player: PlaybackController
  @Binding var readAlongDownloadWarningPresented: Bool
  var onActivate: () -> Void
  /// Schützt vor Doppel-Tap-Rennen, solange der Button-Status noch asynchron nachzieht.
  @State private var isHandlingTap = false

  var body: some View {
    let tx = player.liveTranscription
    let isDownloadReady = player.isReadAlongDownloadReady
    FullPlayerCoverOverlayButton(
      systemName: "text.word.spacing",
      isActive: tx.isTeleprompterModeActive,
      isBusy: tx.isSessionBusy || tx.modelDownloadProgress != nil
        || (tx.isPreparing && !tx.isEnabled),
      isEnabled: true,
      accessibilityLabel: tx.isTeleprompterModeActive
        ? String(localized: "Stop read-along transcript", comment: "Accessibility")
        : String(localized: "Start read-along transcript", comment: "Accessibility")
    ) {
      guard !isHandlingTap else { return }
      isHandlingTap = true
      tx.sanitizeInteractionStateForControls()
      guard isDownloadReady else {
        readAlongDownloadWarningPresented = true
        isHandlingTap = false
        return
      }
      if !tx.isTeleprompterModeActive {
        onActivate()
      }
      Task { @MainActor in
        defer { isHandlingTap = false }
        await tx.toggle(player: player)
        if let err = tx.errorMessage, !AbstandErrorFilter.isBenignCancellationMessage(err) {
          model.errorMessage = err
        }
      }
    }
    .opacity(isDownloadReady ? 1 : 0.45)
    .accessibilityHint(
      isDownloadReady
        ? ""
        : String(
          localized: "Requires a full download of this audiobook.",
          comment: "Read along accessibility hint")
    )
    .onAppear {
      tx.sanitizeInteractionStateForControls()
    }
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
      let primaryLine = floatingBarPrimaryLine(for: book, connecting: connecting)
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
    lhs.snapshot == rhs.snapshot && lhs.themeRevision == rhs.themeRevision
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
          Capsule(style: .continuous)
            .fill(themeAccent)
            .frame(width: playWidth, height: playHeight)
          if busy {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(AppTheme.foregroundOnAccent(themeAccent))
              .scaleEffect(0.72)
          } else {
            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(AppTheme.foregroundOnAccent(themeAccent))
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

// MARK: - Vollplayer Cover-Overlays

private enum FullPlayerCoverPanel: Equatable {
  case artwork
  case description
  case bookmarks
  case chapters
  case sessions
}

enum FullPlayerCoverOverlayMetrics {
  static let verticalInset: CGFloat = 12
  static let horizontalInset: CGFloat = 16
  /// Icon-Kreise in der Panel-Steuerzeile unter der Play-Reihe.
  static let panelControlButtonSize: CGFloat = FullPlayerUtilityBarLayout.primaryRowHeight
  /// Kompakte Kreise auf der Teleprompter-Karte (±).
  static let compactButtonSize: CGFloat = 36
  static let coverSurfaceCornerRadius: CGFloat = 24
  /// Abstand Transcript-Text → ±-Zeile (eigene Zeile, kein Overlay).
  static let teleprompterControlsSpacingAbove: CGFloat = 8
  static var teleprompterControlsBlockHeight: CGFloat {
    teleprompterControlsSpacingAbove + compactButtonSize
  }
}

private extension View {
  /// Cover-Ecken: vertikales und horizontales Inset getrennt (kein Vollbreiten-Overlay).
  func fullPlayerCoverCornerOverlayPadding(
    top: Bool = false,
    bottom: Bool = false,
    leading: Bool = false,
    trailing: Bool = false
  ) -> some View {
    let v = FullPlayerCoverOverlayMetrics.verticalInset
    let h = FullPlayerCoverOverlayMetrics.horizontalInset
    return fixedSize()
      .padding(.top, top ? v : 0)
      .padding(.bottom, bottom ? v : 0)
      .padding(.leading, leading ? h : 0)
      .padding(.trailing, trailing ? h : 0)
  }
}

/// Unsichtbarer Platzhalter in der Panel-Steuerzeile — Abstand vor Read-along bei >3 Buttons.
struct FullPlayerPanelControlSpacerPill: View {
  var body: some View {
    Color.clear
      .frame(
        width: FullPlayerCoverOverlayMetrics.panelControlButtonSize,
        height: FullPlayerCoverOverlayMetrics.panelControlButtonSize
      )
      .accessibilityHidden(true)
  }
}

/// Panel-Steuerbuttons — Icon-Kreis, aktiv in Appearance-Akzent (ohne Text-Pill).
struct FullPlayerCoverOverlayButton: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  let systemName: String
  let isActive: Bool
  var isBusy: Bool = false
  var isEnabled: Bool = true
  /// Kompakter Kreis auf der Teleprompter-Karte (±).
  var compact: Bool = false
  let accessibilityLabel: String
  let action: () -> Void

  private var dockColors: AppTheme.ExpandingDock.Colors {
    let _ = themeRevision
    return AppTheme.ExpandingDock.Colors(
      palette: model.appearancePalette,
      accent: themeAccent
    )
  }

  private var buttonSize: CGFloat {
    compact
      ? FullPlayerCoverOverlayMetrics.compactButtonSize
      : FullPlayerCoverOverlayMetrics.panelControlButtonSize
  }

  var body: some View {
    Button(action: action) {
      iconContent(
        foreground: isActive
          ? dockColors.activeForeground
          : dockColors.inactiveForeground.opacity(AppTheme.ExpandingDock.inactiveIconOpacity),
        size: compact ? 17 : AppTheme.ExpandingDock.iconSize
      )
      .frame(width: buttonSize, height: buttonSize)
      .background {
        Capsule(style: .continuous)
          .fill(
            isActive
              ? dockColors.activeBackground
              : dockColors.inactiveBackground
          )
      }
      .clipShape(Capsule(style: .continuous))
      .contentShape(Capsule(style: .continuous))
    }
    .opacity(isEnabled ? 1 : 0.45)
    .buttonStyle(AbstandExpandingDockButtonStyle())
    .disabled(!isEnabled)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityAddTraits(isActive ? .isSelected : [])
    .abstandThemeRefresh()
  }

  @ViewBuilder
  private func iconContent(foreground: Color, size: CGFloat) -> some View {
    Group {
      if isBusy {
        ProgressView()
          .controlSize(.small)
          .tint(foreground)
      } else {
        Image(systemName: systemName)
          .font(.headline.weight(.semibold))
          .symbolRenderingMode(.monochrome)
          .symbolVariant(isActive ? .fill : .none)
          .foregroundStyle(foreground)
          .frame(width: size, height: size)
      }
    }
  }
}

