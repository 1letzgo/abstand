import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Paper-Tokens (Extension)

/// „Paper"-Palette für die Extension. `AppTheme`/`AppColorPalette` gehören zum App-Target und
/// stehen hier nicht zur Verfügung — die Werte spiegeln `AppColorPalette.paperPalette`/`inkPalette`
/// und `AppTheme.defaultLightAccent`/`defaultAccent`. Bei Änderungen dort hier mitziehen.
private struct SleepActivityPalette {
  let background: Color
  let textPrimary: Color
  let textSecondary: Color
  let progressTrack: Color
  let rule: Color
  let accent: Color

  static let paper = SleepActivityPalette(
    background: Color(red: 243 / 255, green: 238 / 255, blue: 227 / 255),
    textPrimary: Color(red: 31 / 255, green: 27 / 255, blue: 22 / 255),
    textSecondary: Color(red: 124 / 255, green: 114 / 255, blue: 99 / 255),
    progressTrack: Color(red: 220 / 255, green: 210 / 255, blue: 192 / 255),
    rule: Color(red: 220 / 255, green: 210 / 255, blue: 192 / 255),
    accent: Color(red: 179 / 255, green: 38 / 255, blue: 30 / 255)
  )

  static let ink = SleepActivityPalette(
    background: Color(red: 27 / 255, green: 25 / 255, blue: 21 / 255),
    textPrimary: Color(red: 239 / 255, green: 232 / 255, blue: 218 / 255),
    textSecondary: Color(red: 163 / 255, green: 154 / 255, blue: 138 / 255),
    progressTrack: Color(red: 239 / 255, green: 232 / 255, blue: 218 / 255).opacity(0.16),
    rule: Color(red: 239 / 255, green: 232 / 255, blue: 218 / 255).opacity(0.14),
    accent: Color(red: 224 / 255, green: 99 / 255, blue: 79 / 255)
  )

  static func palette(for scheme: ColorScheme) -> SleepActivityPalette {
    scheme == .dark ? ink : paper
  }
}

/// Maße der Live Activity (Werte wie `AppTheme.Layout`, das hier nicht erreichbar ist).
private enum SleepActivityMetrics {
  static let tightSpacing: CGFloat = 4
  static let compactSpacing: CGFloat = 6
  static let stackSpacing: CGFloat = 8
  static let rowSpacing: CGFloat = 12
  static let cardPadding: CGFloat = 14
  static let screenPadding: CGFloat = 16
  static let pillVerticalPadding: CGFloat = 7
  static let hairlineWidth: CGFloat = 1
  /// Feste Breite für den Countdown — `Text(timerInterval:)` nimmt sonst die ganze Zeile ein.
  static let countdownWidth: CGFloat = 96
  static let compactCountdownWidth: CGFloat = 46
  static let minimalRingLineWidth: CGFloat = 2.5
  static let minimalGlyphScale: CGFloat = 0.5
  /// Dynamic Island: Abstand der unteren Region zum Inselrand.
  static let islandBottomPadding: CGFloat = 4
}

private enum SleepActivitySymbols {
  static let timer = "moon.zzz.fill"
  static let paused = "pause.fill"
  static let chapter = "book.closed.fill"
}

// MARK: - Zustand → Darstellung

private enum SleepActivityPhase {
  case running(start: Date, end: Date)
  case paused(remaining: TimeInterval, fraction: Double)
  case chapters(Int)
  /// Ende erreicht, die App hat die Activity aber (noch) nicht beendet.
  case ended

  init(_ state: SleepTimerActivityAttributes.ContentState, isStale: Bool, now: Date = .now) {
    if let chapters = state.chaptersRemaining {
      self = .chapters(max(1, chapters))
    } else if let end = state.endDate {
      if isStale || end <= now {
        self = .ended
      } else {
        // Balkenanfang = Ende − Gesamtdauer; nach „+5 min" kann das in der Zukunft liegen.
        let start = min(end.addingTimeInterval(-max(1, state.totalSeconds)), now)
        self = .running(start: start, end: end)
      }
    } else if let remaining = state.pausedRemaining {
      let total = max(remaining, state.totalSeconds, 1)
      self = .paused(remaining: remaining, fraction: min(1, max(0, remaining / total)))
    } else {
      self = .ended
    }
  }

  var isTimed: Bool {
    switch self {
    case .running, .paused: true
    case .chapters, .ended: false
    }
  }
}

private func sleepActivityClock(_ seconds: TimeInterval) -> String {
  let total = max(0, Int(seconds.rounded()))
  let h = total / 3600
  let m = (total % 3600) / 60
  let s = total % 60
  return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

private func sleepActivityChapterLabel(_ count: Int) -> String {
  count <= 1 ? "End of chapter" : "\(count) chapters left"
}

// MARK: - Bausteine

/// Restzeit: laufend als System-Countdown, pausiert als feste Zahl, Kapitel-Timer als Text.
private struct SleepActivityReadout: View {
  let phase: SleepActivityPhase
  let palette: SleepActivityPalette
  var font: Font = .title2
  var width: CGFloat = SleepActivityMetrics.countdownWidth

  var body: some View {
    switch phase {
    case .running(_, let end):
      Text(timerInterval: Date.now...end, countsDown: true)
        .font(font.weight(.semibold))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(palette.textPrimary)
        .frame(width: width, alignment: .trailing)
    case .paused(let remaining, _):
      Text(verbatim: sleepActivityClock(remaining))
        .font(font.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(palette.textSecondary)
        .frame(width: width, alignment: .trailing)
    case .chapters(let count):
      Text(verbatim: sleepActivityChapterLabel(count))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.textPrimary)
        .lineLimit(1)
    case .ended:
      Text("Ended")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
    }
  }
}

/// Fortschrittsbalken (Akzent) — nur für den Zeit-Timer; der Kapitel-Timer hat kein festes Ende.
private struct SleepActivityProgress: View {
  let phase: SleepActivityPhase
  let palette: SleepActivityPalette

  var body: some View {
    switch phase {
    case .running(let start, let end):
      ProgressView(timerInterval: start...end, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
        .progressViewStyle(.linear)
        .tint(palette.accent)
    case .paused(_, let fraction):
      ProgressView(value: fraction)
        .progressViewStyle(.linear)
        .tint(palette.accent)
    case .chapters, .ended:
      Rectangle()
        .fill(palette.rule)
        .frame(height: SleepActivityMetrics.hairlineWidth)
    }
  }
}

private struct SleepActivityHeader: View {
  let state: SleepTimerActivityAttributes.ContentState
  let phase: SleepActivityPhase
  let palette: SleepActivityPalette

  private var caption: String {
    switch phase {
    case .paused: "Sleep Timer · Paused"
    case .chapters where !state.isPlaying: "Sleep Timer · Paused"
    default: "Sleep Timer"
    }
  }

  var body: some View {
    HStack(spacing: SleepActivityMetrics.compactSpacing) {
      Image(systemName: SleepActivitySymbols.timer)
      Text(verbatim: caption)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(palette.textSecondary)
    .lineLimit(1)
  }
}

private struct SleepActivityTitleBlock: View {
  let state: SleepTimerActivityAttributes.ContentState
  let palette: SleepActivityPalette

  var body: some View {
    VStack(alignment: .leading, spacing: SleepActivityMetrics.tightSpacing) {
      // Paper: Inhalts-Titel in Serife.
      Text(verbatim: state.title)
        .font(.headline)
        .fontDesign(.serif)
        .foregroundStyle(palette.textPrimary)
        .lineLimit(1)
      if let author = state.author, !author.isEmpty {
        Text(verbatim: author)
          .font(.caption)
          .foregroundStyle(palette.textSecondary)
          .lineLimit(1)
      }
    }
  }
}

/// „+5 min" (nur Zeit-Timer) und „Cancel". Paper: Buttons in Tinte, nicht im Akzent.
private struct SleepActivityButtons: View {
  let phase: SleepActivityPhase
  let palette: SleepActivityPalette

  var body: some View {
    HStack(spacing: SleepActivityMetrics.stackSpacing) {
      if phase.isTimed {
        Button(intent: ExtendSleepTimerIntent()) {
          Text(verbatim: "+\(SleepTimerActivityConstants.extendMinutes) min")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SleepActivityMetrics.pillVerticalPadding)
            .background(palette.textPrimary, in: Capsule())
        }
        .buttonStyle(.plain)
      }
      Button(intent: CancelSleepTimerIntent()) {
        Text("Cancel")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.textPrimary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, SleepActivityMetrics.pillVerticalPadding)
          .overlay(Capsule().strokeBorder(palette.rule, lineWidth: SleepActivityMetrics.hairlineWidth))
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - Sperrbildschirm

private struct SleepTimerLockScreenView: View {
  let context: ActivityViewContext<SleepTimerActivityAttributes>
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = SleepActivityPalette.palette(for: colorScheme)
    let phase = SleepActivityPhase(context.state, isStale: context.isStale)
    VStack(alignment: .leading, spacing: SleepActivityMetrics.stackSpacing) {
      SleepActivityHeader(state: context.state, phase: phase, palette: palette)
      HStack(alignment: .center, spacing: SleepActivityMetrics.rowSpacing) {
        SleepActivityTitleBlock(state: context.state, palette: palette)
          .frame(maxWidth: .infinity, alignment: .leading)
        SleepActivityReadout(phase: phase, palette: palette)
      }
      SleepActivityProgress(phase: phase, palette: palette)
      SleepActivityButtons(phase: phase, palette: palette)
    }
    .padding(.horizontal, SleepActivityMetrics.screenPadding)
    .padding(.vertical, SleepActivityMetrics.cardPadding)
    .activityBackgroundTint(palette.background)
    .activitySystemActionForegroundColor(palette.textPrimary)
  }
}

// MARK: - Widget

struct SleepTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SleepTimerActivityAttributes.self) { context in
      SleepTimerLockScreenView(context: context)
    } dynamicIsland: { context in
      // Die Insel ist immer dunkel — Tinten-Palette unabhängig vom System-Modus.
      let palette = SleepActivityPalette.ink
      let phase = SleepActivityPhase(context.state, isStale: context.isStale)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          SleepActivityHeader(state: context.state, phase: phase, palette: palette)
            .padding(.leading, SleepActivityMetrics.tightSpacing)
        }
        DynamicIslandExpandedRegion(.trailing) {
          if phase.isTimed {
            SleepActivityReadout(phase: phase, palette: palette, font: .title3)
              .padding(.trailing, SleepActivityMetrics.tightSpacing)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: SleepActivityMetrics.stackSpacing) {
            HStack(spacing: SleepActivityMetrics.rowSpacing) {
              SleepActivityTitleBlock(state: context.state, palette: palette)
                .frame(maxWidth: .infinity, alignment: .leading)
              if !phase.isTimed {
                SleepActivityReadout(phase: phase, palette: palette)
              }
            }
            SleepActivityProgress(phase: phase, palette: palette)
            SleepActivityButtons(phase: phase, palette: palette)
          }
          .padding(.horizontal, SleepActivityMetrics.tightSpacing)
          .padding(.bottom, SleepActivityMetrics.islandBottomPadding)
        }
      } compactLeading: {
        Image(systemName: SleepActivitySymbols.timer)
          .foregroundStyle(palette.textPrimary)
      } compactTrailing: {
        SleepTimerCompactTrailing(phase: phase, palette: palette)
      } minimal: {
        SleepTimerMinimal(phase: phase, palette: palette)
      }
      .keylineTint(palette.accent)
    }
  }
}

private struct SleepTimerCompactTrailing: View {
  let phase: SleepActivityPhase
  let palette: SleepActivityPalette

  var body: some View {
    switch phase {
    case .running(_, let end):
      Text(timerInterval: Date.now...end, countsDown: true)
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(palette.textPrimary)
        .frame(width: SleepActivityMetrics.compactCountdownWidth, alignment: .trailing)
    case .paused(let remaining, _):
      HStack(spacing: SleepActivityMetrics.tightSpacing) {
        Image(systemName: SleepActivitySymbols.paused)
        Text(verbatim: sleepActivityClock(remaining)).monospacedDigit()
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(palette.textSecondary)
    case .chapters(let count):
      HStack(spacing: SleepActivityMetrics.tightSpacing) {
        Image(systemName: SleepActivitySymbols.chapter)
        Text(verbatim: "\(count)").monospacedDigit()
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(palette.textPrimary)
    case .ended:
      Image(systemName: SleepActivitySymbols.paused)
        .foregroundStyle(palette.textSecondary)
    }
  }
}

private struct SleepTimerMinimal: View {
  let phase: SleepActivityPhase
  let palette: SleepActivityPalette

  var body: some View {
    switch phase {
    case .running(let start, let end):
      // Ring läuft systemseitig mit; Mond als Kennung in der Mitte.
      ProgressView(timerInterval: start...end, countsDown: true, label: { EmptyView() }, currentValueLabel: {
        Image(systemName: SleepActivitySymbols.timer)
          .scaleEffect(SleepActivityMetrics.minimalGlyphScale)
          .foregroundStyle(palette.textPrimary)
      })
      .progressViewStyle(.circular)
      .tint(palette.accent)
    case .paused, .ended:
      Image(systemName: SleepActivitySymbols.timer)
        .foregroundStyle(palette.textSecondary)
    case .chapters:
      Image(systemName: SleepActivitySymbols.timer)
        .foregroundStyle(palette.textPrimary)
    }
  }
}
