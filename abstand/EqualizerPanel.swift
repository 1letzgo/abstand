import SwiftUI

private enum EqualizerPanelMetrics {
  static let handleSize: CGFloat = 26
  static let curveLineWidth: CGFloat = 2
  /// Etwas Luft über dem Maximum, damit die Griffe nicht am Rand kleben.
  static let displayRangeDB: Double = AudioEQBands.maxGain + 2
  static let curveSamples = 96
  static let fillOpacity: Double = 0.22
  static let readoutOffset: CGFloat = 30
  static let chipMinimumScale: CGFloat = 0.7
}

/// EQ als Player-Panel: sechs ziehbare Bänder über dem echten Betragsgang, darunter die Vorlagen.
/// Ziehen an einer Vorlage übernimmt deren Werte als Startpunkt für `.custom`.
/// `player` bewusst nicht beobachtet, siehe `SleepTimerPanel`.
struct EqualizerPanel: View {
  let player: PlaybackController

  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent

  @State private var preset: AudioEQPreset
  @State private var customGains: [Double]
  @State private var draggedBand: Int?

  init(player: PlaybackController) {
    self.player = player
    _preset = State(initialValue: player.eqPreset)
    _customGains = State(initialValue: player.eqCustomGains)
  }

  private var filters: [AudioEQBiquadFilter] {
    preset == .custom ? AudioEQBands.filters(gains: customGains) : preset.filters
  }

  /// Griffposition: bei Custom der eingestellte Wert, sonst die Kurve der Vorlage an dieser Frequenz.
  private var handleGains: [Double] {
    if preset == .custom { return customGains }
    let current = filters
    return AudioEQBands.frequencies.map { frequency in
      let db = AudioEQBands.responseDB(filters: current, frequency: frequency)
      return min(max(db, -AudioEQBands.maxGain), AudioEQBands.maxGain)
    }
  }

  var body: some View {
    VStack(spacing: AppTheme.Layout.withinSectionSpacing) {
      graph
      bandLabels
      presetRow
    }
    .onReceive(player.$eqPreset) { preset = $0 }
    .onReceive(player.$eqCustomGains) { customGains = $0 }
  }

  private var graph: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let gains = handleGains
      ZStack {
        gridLines(size: size)
        curveFill(size: size)
        curveLine(size: size)
        ForEach(gains.indices, id: \.self) { band in
          handle(band: band, gain: gains[band], size: size)
        }
      }
      .contentShape(Rectangle())
      .gesture(dragGesture(size: size, startGains: gains))
    }
    .frame(maxHeight: .infinity)
    .sensoryFeedback(.selection, trigger: draggedBand.map { customGains[$0] }) { _, _ in draggedBand != nil }
    .accessibilityElement(children: .contain)
  }

  private func bandX(_ band: Int, width: CGFloat) -> CGFloat {
    width * (CGFloat(band) + 0.5) / CGFloat(AudioEQBands.frequencies.count)
  }

  private func y(forDB db: Double, height: CGFloat) -> CGFloat {
    let range = EqualizerPanelMetrics.displayRangeDB
    let clamped = min(max(db, -range), range)
    return height / 2 - CGFloat(clamped / range) * (height / 2)
  }

  /// Bänder liegen gleichmäßig, dazwischen wird logarithmisch interpoliert.
  private func frequency(atX x: CGFloat, width: CGFloat) -> Double {
    let frequencies = AudioEQBands.frequencies
    let position = Double(x / width) * Double(frequencies.count) - 0.5
    let lower = min(max(Int(position.rounded(.down)), 0), frequencies.count - 2)
    let fraction = position - Double(lower)
    return exp(log(frequencies[lower]) + fraction * (log(frequencies[lower + 1]) - log(frequencies[lower])))
  }

  private func curvePath(size: CGSize) -> Path {
    let current = filters
    return Path { path in
      for sample in 0...EqualizerPanelMetrics.curveSamples {
        let x = size.width * CGFloat(sample) / CGFloat(EqualizerPanelMetrics.curveSamples)
        let db = AudioEQBands.responseDB(filters: current, frequency: frequency(atX: x, width: size.width))
        let point = CGPoint(x: x, y: y(forDB: db, height: size.height))
        if sample == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private func gridLines(size: CGSize) -> some View {
    Path { path in
      for band in AudioEQBands.frequencies.indices {
        let x = bandX(band, width: size.width)
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
      }
      path.move(to: CGPoint(x: 0, y: size.height / 2))
      path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
    }
    .stroke(model.appearancePalette.rule, lineWidth: AppTheme.Layout.hairlineWidth)
  }

  private func curveFill(size: CGSize) -> some View {
    var area = curvePath(size: size)
    area.addLine(to: CGPoint(x: size.width, y: size.height))
    area.addLine(to: CGPoint(x: 0, y: size.height))
    area.closeSubpath()
    return area.fill(
      LinearGradient(
        colors: [themeAccent.opacity(EqualizerPanelMetrics.fillOpacity), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private func curveLine(size: CGSize) -> some View {
    curvePath(size: size)
      .stroke(themeAccent, style: StrokeStyle(lineWidth: EqualizerPanelMetrics.curveLineWidth, lineJoin: .round))
  }

  private func handle(band: Int, gain: Double, size: CGSize) -> some View {
    let position = CGPoint(x: bandX(band, width: size.width), y: y(forDB: gain, height: size.height))
    return Circle()
      .fill(model.appearancePalette.textPrimary)
      .frame(width: EqualizerPanelMetrics.handleSize, height: EqualizerPanelMetrics.handleSize)
      .overlay(alignment: .center) {
        if draggedBand == band {
          Text(verbatim: gainText(gain))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(model.appearancePalette.textPrimary)
            .fixedSize()
            .offset(y: gain >= 0 ? EqualizerPanelMetrics.readoutOffset : -EqualizerPanelMetrics.readoutOffset)
        }
      }
      .position(position)
      .accessibilityElement()
      .accessibilityLabel(bandLabel(band))
      .accessibilityValue(gainText(gain))
      .accessibilityAdjustableAction { direction in
        var gains = handleGains
        let step = direction == .increment ? AudioEQBands.gainStep * 2 : -AudioEQBands.gainStep * 2
        gains[band] = min(max(gains[band] + step, -AudioEQBands.maxGain), AudioEQBands.maxGain)
        model.applyEQCustomGains(gains, persist: true)
      }
  }

  private func dragGesture(size: CGSize, startGains: [Double]) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let band: Int
        if let draggedBand {
          band = draggedBand
        } else {
          let slot = Int(value.startLocation.x / size.width * CGFloat(AudioEQBands.frequencies.count))
          band = min(max(slot, 0), AudioEQBands.frequencies.count - 1)
          draggedBand = band
        }
        var gains = preset == .custom ? customGains : startGains.map(snapped)
        gains[band] = gain(atY: value.location.y, height: size.height)
        guard gains != customGains || preset != .custom else { return }
        model.applyEQCustomGains(gains, persist: false)
      }
      .onEnded { _ in
        draggedBand = nil
        guard preset == .custom else { return }
        model.applyEQCustomGains(customGains, persist: true)
      }
  }

  private func gain(atY y: CGFloat, height: CGFloat) -> Double {
    let db = Double((height / 2 - y) / (height / 2)) * EqualizerPanelMetrics.displayRangeDB
    return snapped(db)
  }

  private func snapped(_ db: Double) -> Double {
    let stepped = (db / AudioEQBands.gainStep).rounded() * AudioEQBands.gainStep
    return min(max(stepped, -AudioEQBands.maxGain), AudioEQBands.maxGain)
  }

  private func gainText(_ gain: Double) -> String {
    let number = gain.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
    return "\(number) dB"
  }

  private func bandLabel(_ band: Int) -> String {
    let frequency = AudioEQBands.frequencies[band]
    if frequency >= 1000 {
      let kilohertz = (frequency / 1000).formatted(.number.precision(.fractionLength(0...1)))
      return "\(kilohertz) kHz"
    }
    return "\(Int(frequency)) Hz"
  }

  private var bandLabels: some View {
    HStack(spacing: 0) {
      ForEach(AudioEQBands.frequencies.indices, id: \.self) { band in
        Text(verbatim: bandLabel(band))
          .font(.caption2)
          .monospacedDigit()
          .foregroundStyle(model.appearancePalette.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(EqualizerPanelMetrics.chipMinimumScale)
          .frame(maxWidth: .infinity)
      }
    }
    .accessibilityHidden(true)
  }

  private var presetRow: some View {
    HStack(spacing: AppTheme.Layout.compactSpacing) {
      ForEach(AudioEQPreset.allCases) { option in
        Button {
          model.applyEQPreset(option)
        } label: {
          Text(chipTitle(option))
            .lineLimit(1)
            .minimumScaleFactor(EqualizerPanelMetrics.chipMinimumScale)
            .padding(.horizontal, AppTheme.Layout.tightSpacing)
        }
        .buttonStyle(PlayerPanelChipButtonStyle(isSelected: preset == option))
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(preset == option ? .isSelected : [])
      }
    }
  }

  private func chipTitle(_ option: AudioEQPreset) -> String {
    switch option {
    case .flat: return "Flat"
    case .voiceFocus: return "Voice"
    case .bassBoost: return "Bass"
    case .trebleBoost: return "Treble"
    case .custom: return "Custom"
    }
  }
}
