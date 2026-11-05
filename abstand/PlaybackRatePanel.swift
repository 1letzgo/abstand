import SwiftUI

private enum PlaybackRatePanelMetrics {
  /// Ein Strich = 0,05× (`PlaybackController.playbackRateStep`), deckt 0,75× und 1,25× mit ab.
  static let ticksPerUnit = Int((1 / PlaybackController.playbackRateStep).rounded())
  static let ticksRange =
    Int((PlaybackController.playbackRateRange.lowerBound * Float(ticksPerUnit)).rounded())
    ...
    Int((PlaybackController.playbackRateRange.upperBound * Float(ticksPerUnit)).rounded())
  /// Lange Striche alle 0,5×.
  static let majorTickInterval = ticksPerUnit / 2
  static let presets: [Float] = [0.5, 1.0, 1.5, 2.0]
}

private func playbackRateTicks(_ rate: Float) -> Int {
  Int((rate * Float(PlaybackRatePanelMetrics.ticksPerUnit)).rounded())
}

private func playbackRateValue(ticks: Int) -> Float {
  Float(ticks) / Float(PlaybackRatePanelMetrics.ticksPerUnit)
}

/// „1.0“, „1.25“ — mindestens eine Nachkommastelle, anders als die kompakte Anzeige im Button.
private func playbackRateText(_ rate: Float) -> String {
  rate.formatted(.number.precision(.fractionLength(1...2)))
}

/// Tempo als Player-Panel, gleicher Aufbau wie `SleepTimerPanel`.
/// `player` bewusst nicht beobachtet, siehe dort.
struct PlaybackRatePanel: View {
  let player: PlaybackController

  @EnvironmentObject private var model: AppModel

  @State private var rate: Float
  @State private var rulerTicks: Int?
  @State private var isAdjustingRuler = false

  init(player: PlaybackController) {
    self.player = player
    _rate = State(initialValue: player.playbackRate)
    _rulerTicks = State(initialValue: playbackRateTicks(player.playbackRate))
  }

  var body: some View {
    PlayerDialPanelLayout {
      Text(verbatim: "\(playbackRateText(displayedRate))×")
        .foregroundStyle(model.appearancePalette.textPrimary)
        .contentTransition(.numericText())
        .animation(.default, value: displayedRate)
    } actions: {
      // Platz bleibt reserviert, damit nichts springt.
      Button(String(localized: "Reset", comment: "Playback speed: back to normal")) {
        model.applyPlaybackSpeed(1)
      }
      .buttonStyle(PlayerPanelChipButtonStyle(compact: true))
      .opacity(rate == 1 ? 0 : 1)
      .disabled(rate == 1)
      .accessibilityHidden(rate == 1)
    } ruler: {
        PlayerTickRuler(
          value: $rulerTicks,
          isAdjusting: $isAdjustingRuler,
          range: PlaybackRatePanelMetrics.ticksRange,
          majorInterval: PlaybackRatePanelMetrics.majorTickInterval,
          accessibilityLabel: String(localized: "Playback speed", comment: "Accessibility"),
          label: { playbackRateText(playbackRateValue(ticks: $0)) },
          accessibilityValue: { "\(playbackRateText(playbackRateValue(ticks: $0)))×" },
          onCommit: { model.applyPlaybackSpeed(playbackRateValue(ticks: $0)) }
        )
    } accessory: {
      EmptyView()
    } presets: {
        HStack(spacing: AppTheme.Layout.inlineSpacing) {
          ForEach(PlaybackRatePanelMetrics.presets, id: \.self) { preset in
            Button {
              model.applyPlaybackSpeed(preset)
            } label: {
              Text(verbatim: playbackRateText(preset))
            }
            .buttonStyle(PlayerPanelChipButtonStyle(isSelected: rate == preset))
            .accessibilityLabel("\(playbackRateText(preset))×")
            .accessibilityAddTraits(rate == preset ? .isSelected : [])
          }
        }
    }
    .onReceive(player.$playbackRate) { rate = $0 }
    .onChange(of: rate) {
      guard !isAdjustingRuler else { return }
      let target = playbackRateTicks(rate)
      if target != rulerTicks {
        withAnimation(.snappy) { rulerTicks = target }
      }
    }
  }

  private var displayedRate: Float {
    isAdjustingRuler ? playbackRateValue(ticks: rulerTicks ?? playbackRateTicks(rate)) : rate
  }
}
