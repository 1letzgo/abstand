import SwiftUI

enum PlayerTickRulerMetrics {
  /// Abstand der Striche.
  static let tickSpacing: CGFloat = 12
  static let minorTickHeight: CGFloat = 20
  static let majorTickHeight: CGFloat = 36
  static let rulerHeight: CGFloat = 76
  static let indicatorHeight: CGFloat = 44
  static let edgeFadeFraction: CGFloat = 0.14
  static let pillFillOpacity: Double = 0.08
  static let readoutFontSize: CGFloat = 56
  static let readoutMinimumScale: CGFloat = 0.45
  static let readoutHeight: CGFloat = 68
  static let actionsHeight: CGFloat = 32
}

/// Gemeinsames Gerüst von Sleep-Timer und Tempo: Hero-Wert und Skala stehen in beiden Panels an
/// derselben Stelle in derselben Größe. Dafür haben alle Zeilen feste Höhen, auch ein leerer
/// Zusatz-Platz (Kapitel-Stepper gibt es nur beim Sleep-Timer) bleibt reserviert.
struct PlayerDialPanelLayout<Hero: View, Actions: View, Ruler: View, Accessory: View, Presets: View>: View {
  @ViewBuilder let hero: () -> Hero
  @ViewBuilder let actions: () -> Actions
  @ViewBuilder let ruler: () -> Ruler
  @ViewBuilder let accessory: () -> Accessory
  @ViewBuilder let presets: () -> Presets

  var body: some View {
    VStack(spacing: AppTheme.Layout.withinSectionSpacing) {
      Spacer(minLength: 0)
      VStack(spacing: AppTheme.Layout.inlineSpacing) {
        hero()
          .font(
            .system(
              size: PlayerTickRulerMetrics.readoutFontSize,
              weight: .semibold,
              design: AppTheme.Typography.titleDesign
            )
          )
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(PlayerTickRulerMetrics.readoutMinimumScale)
          .frame(maxWidth: .infinity)
          .frame(height: PlayerTickRulerMetrics.readoutHeight)
        Color.clear
          .frame(height: PlayerTickRulerMetrics.actionsHeight)
          .overlay { actions() }
      }
      ruler()
      Spacer(minLength: 0)
      // `Color.clear` trägt die Höhe: ein `.frame` auf einem leeren View fiele weg.
      Color.clear
        .frame(height: AppTheme.Layout.minTapTarget)
        .overlay { accessory() }
      presets()
    }
  }
}

/// Skala der Player-Panels (Sleep-Timer, Tempo): nativer `ScrollView`, rastet je Strich ein.
/// Übernommen wird erst beim Ausrollen, sonst löste jeder überstrichene Wert die Aktion aus.
struct PlayerTickRuler: View {
  @Binding var value: Int?
  @Binding var isAdjusting: Bool
  let range: ClosedRange<Int>
  /// Lange Striche samt Beschriftung; zugleich die Schrittweite für VoiceOver.
  let majorInterval: Int
  let accessibilityLabel: String
  let label: (Int) -> String
  let accessibilityValue: (Int) -> String
  let onCommit: (Int) -> Void

  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent

  /// Wert beim Öffnen: `scrollPosition(id:)` übernimmt ihn beim ersten Layout nicht zuverlässig und
  /// meldet stattdessen den Anfang der Skala.
  @State private var initialValue: Int?

  private let spacing = PlayerTickRulerMetrics.tickSpacing

  init(
    value: Binding<Int?>,
    isAdjusting: Binding<Bool>,
    range: ClosedRange<Int>,
    majorInterval: Int,
    accessibilityLabel: String,
    label: @escaping (Int) -> String,
    accessibilityValue: @escaping (Int) -> String,
    onCommit: @escaping (Int) -> Void
  ) {
    _value = value
    _isAdjusting = isAdjusting
    self.range = range
    self.majorInterval = majorInterval
    self.accessibilityLabel = accessibilityLabel
    self.label = label
    self.accessibilityValue = accessibilityValue
    self.onCommit = onCommit
    _initialValue = State(initialValue: value.wrappedValue)
  }

  var body: some View {
    GeometryReader { proxy in
      ScrollViewReader { reader in
      ScrollView(.horizontal) {
        HStack(spacing: 0) {
          ForEach(range, id: \.self) { tickValue in
            tick(tickValue)
              .id(tickValue)
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .contentMargins(.horizontal, max(0, (proxy.size.width - spacing) / 2), for: .scrollContent)
      .scrollTargetBehavior(.viewAligned)
      .scrollPosition(id: $value, anchor: .center)
      .onScrollPhaseChange { _, phase in
        if phase == .interacting {
          isAdjusting = true
        } else if phase == .idle, isAdjusting {
          isAdjusting = false
          onCommit(value ?? range.lowerBound)
        }
      }
      .task {
        guard let initialValue else { return }
        await Task.yield()
        reader.scrollTo(initialValue, anchor: .center)
        value = initialValue
      }
      }
    }
    .frame(height: PlayerTickRulerMetrics.rulerHeight)
    .mask {
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0),
          .init(color: .black, location: PlayerTickRulerMetrics.edgeFadeFraction),
          .init(color: .black, location: 1 - PlayerTickRulerMetrics.edgeFadeFraction),
          .init(color: .clear, location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    }
    .overlay(alignment: .top) {
      Capsule()
        .fill(themeAccent)
        .frame(width: AppTheme.Layout.hairlineSpacing, height: PlayerTickRulerMetrics.indicatorHeight)
        .allowsHitTesting(false)
    }
    .sensoryFeedback(.selection, trigger: value) { _, _ in isAdjusting }
    .accessibilityElement()
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(accessibilityValue(value ?? range.lowerBound))
    .accessibilityAdjustableAction { direction in
      let current = value ?? range.lowerBound
      let next: Int
      switch direction {
      case .increment: next = min(current + majorInterval, range.upperBound)
      case .decrement: next = max(current - majorInterval, range.lowerBound)
      @unknown default: return
      }
      value = next
      onCommit(next)
    }
  }

  private func tick(_ tickValue: Int) -> some View {
    let palette = model.appearancePalette
    let isMajor = tickValue % majorInterval == 0
    return Rectangle()
      .fill(isMajor ? palette.textSecondary : palette.rule)
      .frame(
        width: AppTheme.Layout.hairlineWidth,
        height: isMajor ? PlayerTickRulerMetrics.majorTickHeight : PlayerTickRulerMetrics.minorTickHeight
      )
      .frame(width: spacing, height: PlayerTickRulerMetrics.indicatorHeight, alignment: .center)
      .frame(height: PlayerTickRulerMetrics.rulerHeight, alignment: .top)
      .overlay(alignment: .bottom) {
        if isMajor {
          Text(verbatim: label(tickValue))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(palette.textSecondary)
            .fixedSize()
        }
      }
  }
}

struct PlayerPanelPresetButtonStyle: ButtonStyle {
  let isSelected: Bool
  @EnvironmentObject private var model: AppModel

  func makeBody(configuration: Configuration) -> some View {
    let palette = model.appearancePalette
    configuration.label
      .font(.title3.weight(.medium))
      .monospacedDigit()
      .foregroundStyle(isSelected ? palette.background : palette.textPrimary)
      .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minTapTarget)
      .abstandCardChrome(
        isSelected ? palette.textPrimary : palette.card,
        shape: RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous)
      )
      .opacity(configuration.isPressed ? 0.7 : 1)
      .contentShape(Rectangle())
  }
}

struct PlayerPanelPillButtonStyle: ButtonStyle {
  @EnvironmentObject private var model: AppModel

  func makeBody(configuration: Configuration) -> some View {
    let palette = model.appearancePalette
    configuration.label
      .font(.subheadline.weight(.medium))
      .foregroundStyle(palette.textPrimary)
      .padding(.horizontal, AppTheme.Layout.cardPadding)
      .padding(.vertical, AppTheme.Layout.compactSpacing)
      .background(
        Capsule(style: .continuous)
          .fill(palette.textPrimary.opacity(PlayerTickRulerMetrics.pillFillOpacity))
      )
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}
