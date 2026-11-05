import SwiftUI

func sleepTimerOffLabel() -> String {
  String(localized: "Off", comment: "Sleep timer: disabled")
}

func sleepTimerChaptersMenuLabel(_ count: Int) -> String {
  switch count {
  case ...1:
    return String(localized: "End of this chapter", comment: "Sleep timer: stop at end of current chapter")
  case 2:
    return String(localized: "After next chapter", comment: "Sleep timer: stop after the following chapter")
  default:
    return String(
      format: String(localized: "After %lld more chapters", comment: "Sleep timer: stop after n further chapters"),
      count - 1
    )
  }
}

private enum SleepTimerPanelMetrics {
  /// Ein Tipp für die häufigen Dauern, alles andere über die Skala.
  static let minutePresets = [10, 15, 30, 45]
  /// Ein Strich = eine Minute.
  static let maxRulerMinutes = 180
  static let majorTickInterval = 5
}

/// Sleep-Timer als Player-Panel (selber Kasten wie Read Along, Kapitel usw.): große Restzeit,
/// Minuten-Skala, Vorgaben und Kapitelende.
/// `player` bewusst nicht beobachtet: der Controller meldet laufend Positionsänderungen, das würde
/// die ganze Skala mitten im Wischen neu auswerten. Der Modus kommt per `onReceive`, die Restzeit aus
/// der `TimelineView`.
struct SleepTimerPanel: View {
  let player: PlaybackController

  @EnvironmentObject private var model: AppModel
  @State private var mode: SleepTimerMode
  @State private var rulerMinutes: Int?
  @State private var isAdjustingRuler = false
  @State private var maxChapters: Int

  init(player: PlaybackController) {
    self.player = player
    _mode = State(initialValue: player.sleepTimerMode)
    _rulerMinutes = State(initialValue: Self.rulerValue(for: player))
    _maxChapters = State(initialValue: player.chapterCount > 0 ? player.maxSleepChapterCount() : 0)
  }

  var body: some View {
    PlayerDialPanelLayout {
      countdown
    } actions: {
      timerActions
    } ruler: {
        PlayerTickRuler(
          value: $rulerMinutes,
          isAdjusting: $isAdjustingRuler,
          range: 0...SleepTimerPanelMetrics.maxRulerMinutes,
          majorInterval: SleepTimerPanelMetrics.majorTickInterval,
          accessibilityLabel: String(localized: "Sleep timer duration", comment: "Accessibility"),
          label: { "\($0)" },
          accessibilityValue: { minutes in
            minutes > 0
              ? String(format: String(localized: "%lld min", comment: "Sleep timer: minutes"), minutes)
              : sleepTimerOffLabel()
          },
          onCommit: { model.applySleepTimer(minutes: $0) }
        )
    } accessory: {
      if maxChapters > 0 {
        chapterStepper
      }
    } presets: {
      presets
    }
    .onReceive(player.$sleepTimerMode) { newMode in
      mode = newMode
      maxChapters = player.chapterCount > 0 ? player.maxSleepChapterCount() : 0
    }
    // Nicht im `onReceive`: `$sleepTimerMode` meldet vor dem Setzen des Kapitelziels,
    // die Restzeit wäre dort noch die des alten Ziels.
    .onChange(of: mode) {
      guard !isAdjustingRuler else { return }
      let target = Self.rulerValue(for: player)
      if target != rulerMinutes {
        withAnimation(.snappy) { rulerMinutes = target }
      }
    }
  }

  /// Minuten-Timer: die gewählte Dauer. Kapitel-Timer: Restzeit bis Kapitelende, gerundet.
  private static func rulerValue(for player: PlaybackController) -> Int {
    let minutes: Int
    switch player.sleepTimerMode {
    case .off: minutes = 0
    case .minutes(let selected): minutes = selected
    case .chapters: minutes = Int(((player.sleepTimerDisplaySeconds ?? 0) / 60).rounded())
    }
    return min(max(0, minutes), SleepTimerPanelMetrics.maxRulerMinutes)
  }

  private var countdown: some View {
    TimelineView(.periodic(from: .now, by: 1)) { _ in
      Text(countdownText)
        .contentTransition(.numericText(countsDown: true))
        .animation(.default, value: countdownText)
        .foregroundStyle(
          mode == .off && !isAdjustingRuler
            ? model.appearancePalette.textSecondary
            : model.appearancePalette.textPrimary
        )
    }
    .accessibilityAddTraits(.updatesFrequently)
  }

  private var countdownText: String {
    if isAdjustingRuler {
      let minutes = rulerMinutes ?? 0
      return minutes > 0 ? formatPlaybackTime(TimeInterval(minutes * 60)) : sleepTimerOffLabel()
    }
    if let seconds = player.sleepTimerDisplaySeconds, seconds > 0 {
      return formatPlaybackTime(seconds)
    }
    return sleepTimerOffLabel()
  }

  /// Platz bleibt reserviert, damit die Skala beim Ein- und Ausschalten nicht springt.
  private var timerActions: some View {
    HStack(spacing: AppTheme.Layout.inlineSpacing) {
      if mode != .off {
        Button(String(localized: "Reset", comment: "Sleep timer: restart countdown")) {
          switch mode {
          case .off: break
          case .minutes(let minutes): model.applySleepTimer(minutes: minutes)
          case .chapters(let count): model.applySleepTimer(chapters: count)
          }
        }
      }
      Button(String(localized: "Turn Off", comment: "Sleep timer: disable")) {
        model.applySleepTimer(minutes: 0)
      }
    }
    .buttonStyle(PlayerPanelChipButtonStyle(compact: true))
    .opacity(mode == .off ? 0 : 1)
    .disabled(mode == .off)
    .accessibilityHidden(mode == .off)
  }

  private var presets: some View {
    HStack(spacing: AppTheme.Layout.inlineSpacing) {
      ForEach(SleepTimerPanelMetrics.minutePresets, id: \.self) { minutes in
        Button {
          model.applySleepTimer(minutes: minutes)
        } label: {
          Text(verbatim: "\(minutes)")
        }
        .buttonStyle(PlayerPanelChipButtonStyle(isSelected: mode == .minutes(minutes)))
        .accessibilityLabel(
          String(format: String(localized: "%lld min", comment: "Sleep timer: minutes"), minutes)
        )
        .accessibilityAddTraits(mode == .minutes(minutes) ? .isSelected : [])
      }
    }
  }

  private var chapterCountSelection: Int {
    if case .chapters(let count) = mode { return count }
    return 0
  }

  private var chapterStepper: some View {
    let count = chapterCountSelection
    return HStack(spacing: AppTheme.Layout.stackSpacing) {
      Text(
        count > 0
          ? sleepTimerChaptersMenuLabel(count)
          : String(localized: "No chapter timer", comment: "Sleep timer: chapter stepper at zero")
      )
      .font(.subheadline)
      .foregroundStyle(
        count > 0 ? model.appearancePalette.textPrimary : model.appearancePalette.textSecondary
      )
      .lineLimit(1)
      .minimumScaleFactor(PlayerTickRulerMetrics.readoutMinimumScale)
      .frame(maxWidth: .infinity, alignment: .leading)
      FullPlayerCoverOverlayButton(
        systemName: "minus",
        isActive: false,
        isEnabled: count > 0,
        compact: true,
        accessibilityLabel: String(localized: "One chapter less", comment: "Accessibility")
      ) {
        if count == 1 {
          model.applySleepTimer(minutes: 0)
        } else {
          model.applySleepTimer(chapters: count - 1)
        }
      }
      FullPlayerCoverOverlayButton(
        systemName: "plus",
        isActive: false,
        isEnabled: count < maxChapters,
        compact: true,
        accessibilityLabel: String(localized: "One chapter more", comment: "Accessibility")
      ) {
        model.applySleepTimer(chapters: count + 1)
      }
    }
  }
}
