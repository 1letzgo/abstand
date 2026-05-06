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

// MARK: - AirPlay (Mini-Player: nur Tapp-Bereich, Beschriftung in SwiftUI)

private struct MiniPlayerAirPlayRoutePicker: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let v = AVRoutePickerView()
    v.prioritizesVideoDevices = false
    v.tintColor = .clear
    v.activeTintColor = .clear
    return v
  }

  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Mini-Player: dezente Tap-Stile (ohne Kasten-Raster)

private struct MiniPlayerIconTapStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.38)
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

private struct MiniPlayerPlayOrbButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let d = MiniPlayerMetrics.miniPlayerPlayOrb
    return configuration.label
      .font(.title2)
      .foregroundStyle(AppTheme.accent)
      .frame(width: d, height: d)
      .background(
        Circle()
          .fill(AppTheme.accent.opacity(configuration.isPressed ? 0.22 : 0.14))
      )
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .opacity(isEnabled ? 1 : 0.45)
      .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
      .contentShape(Circle())
  }
}

// MARK: - Mini-Player: Umrandung (wie Karten-Aktionen)

private extension View {
  func miniPlayerOutlinedRect() -> some View {
    overlay(
      RoundedRectangle(cornerRadius: MiniPlayerMetrics.controlCorner, style: .continuous)
        .stroke(AppTheme.textSecondary.opacity(0.42), lineWidth: 1)
    )
  }

  func miniPlayerOutlinedCircle() -> some View {
    overlay(
      Circle()
        .stroke(AppTheme.textSecondary.opacity(0.42), lineWidth: 1)
    )
  }
}

/// Schlummer, Tempo, AirPlay: **gleiche Breite**, nur Icons, niedrige Zeile (`miniPlayerSecondaryRowHeight`).
private struct MiniPlayerSleepAirPlayRow: View {
  @EnvironmentObject private var model: AppModel

  private var rowH: CGFloat { MiniPlayerMetrics.miniPlayerSecondaryRowHeight }

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      sleepColumn
        .frame(maxWidth: .infinity)
        .frame(height: rowH)
        .miniPlayerOutlinedRect()

      tempoColumn
        .frame(maxWidth: .infinity)
        .frame(height: rowH)
        .miniPlayerOutlinedRect()

      airPlayColumn
        .frame(maxWidth: .infinity)
        .frame(height: rowH)
        .miniPlayerOutlinedRect()
    }
    .frame(maxWidth: .infinity)
    .frame(height: rowH, alignment: .center)
    .clipped()
  }

  private var sleepColumn: some View {
    Group {
      if let end = model.player.sleepEndDate {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let sleepOn = end > context.date
          let remaining = sleepOn ? end.timeIntervalSince(context.date) : nil
          sleepButton(sleepOn: sleepOn, remaining: remaining)
        }
      } else {
        sleepButton(sleepOn: false, remaining: nil)
      }
    }
  }

  private func sleepButton(sleepOn: Bool, remaining: Double?) -> some View {
    Button { model.showSleepPicker = true } label: {
      HStack(spacing: 3) {
        Image(systemName: "moon.fill")
          .font(.caption.weight(.semibold))
        if sleepOn, let r = remaining, r > 0 {
          Text(formatPlaybackTime(r))
            .font(.caption2.monospacedDigit().weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
      }
      .foregroundStyle(sleepOn ? AppTheme.accent : AppTheme.textSecondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .buttonStyle(MiniPlayerIconTapStyle())
    .accessibilityLabel("Schlummer")
    .accessibilityValue(
      sleepOn && (remaining ?? 0) > 0
        ? "Noch \(formatPlaybackTime(remaining ?? 0))"
        : ""
    )
  }

  private var tempoColumn: some View {
    Button { model.showPlaybackSpeedPicker = true } label: {
      Image(systemName: "gauge.with.dots.needle.67percent")
        .font(.body.weight(.medium))
        .foregroundStyle(AppTheme.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .buttonStyle(MiniPlayerIconTapStyle())
    .accessibilityLabel("Abspielgeschwindigkeit")
    .accessibilityValue(miniPlayerFormatPlaybackRate(model.player.playbackRate))
  }

  private var airPlayColumn: some View {
    ZStack {
      Image(systemName: "airplayaudio")
        .font(.body.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary)
        .allowsHitTesting(false)

      MiniPlayerAirPlayRoutePicker()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityLabel("AirPlay")
  }
}

/// Nur Transport (Skip, Play): volle Breite, ohne Umrandung.
private struct MiniPlayerActiveControlRows: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    let rowH = MiniPlayerMetrics.miniPlayerControlsTotalHeight
    let transportH = MiniPlayerMetrics.miniPlayerTransportHeight
    let hasChapters = model.player.chapterCount > 0

    HStack(alignment: .center, spacing: 0) {
      Spacer(minLength: 0)

      if hasChapters {
        Button { model.player.skipToPreviousChapter() } label: {
          Image(systemName: "backward.end.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
        }
        .buttonStyle(MiniPlayerIconTapStyle())
        .disabled(!model.player.canSkipToPreviousChapter)
        .frame(width: 44, height: transportH)
        .contentShape(Rectangle())
        .accessibilityLabel("Previous chapter")

        Spacer(minLength: 0)
      }

      Button { model.player.skip(seconds: -15) } label: {
        Image(systemName: "gobackward.15")
          .font(.title3)
          .foregroundStyle(AppTheme.textPrimary)
      }
      .buttonStyle(MiniPlayerIconTapStyle())
      .frame(width: 44, height: transportH)
      .contentShape(Rectangle())
      .accessibilityLabel("Back 15 seconds")

      Spacer(minLength: 0)

      Button { model.player.togglePlayPause() } label: {
        Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
      }
      .buttonStyle(MiniPlayerPlayOrbButtonStyle())
      .accessibilityLabel(model.player.isPlaying ? "Pause" : "Play")

      Spacer(minLength: 0)

      Button { model.player.skip(seconds: 30) } label: {
        Image(systemName: "goforward.30")
          .font(.title3)
          .foregroundStyle(AppTheme.textPrimary)
      }
      .buttonStyle(MiniPlayerIconTapStyle())
      .frame(width: 44, height: transportH)
      .contentShape(Rectangle())
      .accessibilityLabel("Forward 30 seconds")

      if hasChapters {
        Spacer(minLength: 0)

        Button { model.player.skipToNextChapter() } label: {
          Image(systemName: "forward.end.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
        }
        .buttonStyle(MiniPlayerIconTapStyle())
        .disabled(!model.player.canSkipToNextChapter)
        .frame(width: 44, height: transportH)
        .contentShape(Rectangle())
        .accessibilityLabel("Next chapter")
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
    .frame(height: rowH)
  }
}

/// Inaktiv: drei Icon-Spalten, gleiche Maße wie aktiv.
private struct MiniPlayerSleepAirPlayPlaceholderRow: View {
  private var rowH: CGFloat { MiniPlayerMetrics.miniPlayerSecondaryRowHeight }

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      Image(systemName: "moon.fill")
        .font(.body.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary.opacity(0.35))
        .frame(maxWidth: .infinity)
        .frame(height: rowH)
        .miniPlayerOutlinedRect()

      Image(systemName: "gauge.with.dots.needle.67percent")
        .font(.body.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary.opacity(0.35))
        .frame(maxWidth: .infinity)
        .frame(height: rowH)
        .miniPlayerOutlinedRect()

      Image(systemName: "airplayaudio")
        .font(.body.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary.opacity(0.35))
        .frame(maxWidth: .infinity)
        .frame(height: rowH)
        .miniPlayerOutlinedRect()
    }
    .frame(maxWidth: .infinity)
    .frame(height: rowH, alignment: .center)
    .clipped()
  }
}

// MARK: - Mini player slider (global UISlider thumb; only one Slider in app)

private enum MiniPlayerSliderThumb {
  private static var didApply = false

  static func applyOnce() {
    guard !didApply else { return }
    didApply = true
    let d: CGFloat = 12
    let size = CGSize(width: d, height: d)
    let img = UIGraphicsImageRenderer(size: size).image { ctx in
      UIColor.white.setFill()
      ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
    }
    UISlider.appearance().setThumbImage(img, for: .normal)
    UISlider.appearance().setThumbImage(img, for: .highlighted)
  }
}

// MARK: - Mini Player Styles (Bibliothek / Karten)

/// Inaktiver Transport: volle Breite, ohne Umrandung.
private struct MiniPlayerPlaceholderControlStrip: View {
  var body: some View {
    let rowH = MiniPlayerMetrics.miniPlayerControlsTotalHeight
    let transportH = MiniPlayerMetrics.miniPlayerTransportHeight
    let orb = MiniPlayerMetrics.miniPlayerPlayOrb

    HStack(alignment: .center, spacing: 0) {
      Spacer(minLength: 0)

      Image(systemName: "backward.end.fill")
        .font(.title3.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary.opacity(0.28))
        .frame(width: 44, height: transportH)

      Spacer(minLength: 0)

      Image(systemName: "gobackward.15")
        .font(.title3)
        .foregroundStyle(AppTheme.textSecondary.opacity(0.28))
        .frame(width: 44, height: transportH)

      Spacer(minLength: 0)

      Image(systemName: "play.fill")
        .font(.title2)
        .foregroundStyle(AppTheme.accent.opacity(0.35))
        .frame(width: orb, height: orb)
        .background(Circle().fill(AppTheme.accent.opacity(0.08)))

      Spacer(minLength: 0)

      Image(systemName: "goforward.30")
        .font(.title3)
        .foregroundStyle(AppTheme.textSecondary.opacity(0.28))
        .frame(width: 44, height: transportH)

      Spacer(minLength: 0)

      Image(systemName: "forward.end.fill")
        .font(.title3.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary.opacity(0.28))
        .frame(width: 44, height: transportH)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
    .frame(height: rowH)
    .fixedSize(horizontal: false, vertical: true)
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
      .frame(maxWidth: .infinity)
      .frame(height: MiniPlayerMetrics.controlMinHeight, alignment: .center)
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
  }
}

// MARK: - Mini Player Bar

struct MiniPlayerBar: View {
  @EnvironmentObject private var model: AppModel
  @State private var scrubLocal: Double?

  private var showIdlePlaceholder: Bool {
    model.player.showMiniPlayerPlaceholder && model.player.activeBook == nil
  }

  var body: some View {
    let book = model.player.activeBook
    let pos = scrubLocal ?? model.player.globalPosition
    let dur = max(model.player.totalDuration, 1)

    VStack(alignment: .leading, spacing: 0) {
      if let b = book {
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .top, spacing: 8) {
            CoverImageView(url: model.coverURL(for: b.id), token: model.token)
              .frame(width: MiniPlayerMetrics.coverSide, height: MiniPlayerMetrics.coverSide)
              .clipped()
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
              Text(b.displayTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
              Text(b.displayAuthors)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
              if model.player.chapterCount > 0 {
                let counter = String(
                  format: "%03d/%03d",
                  model.player.currentChapterOrdinal,
                  model.player.chapterCount
                )
                let chapterName = model.player.currentChapterTitle
                  .trimmingCharacters(in: .whitespacesAndNewlines)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                  Text(counter).monospacedDigit()
                  if !chapterName.isEmpty {
                    Text(" - ")
                    Text(chapterName)
                      .lineLimit(1)
                      .truncationMode(.tail)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(
                  chapterName.isEmpty
                    ? "Kapitel \(counter)"
                    : "Kapitel \(counter), \(chapterName)"
                )
              }

              Spacer(minLength: 0)

              MiniPlayerSleepAirPlayRow()
            }
            .frame(
              maxWidth: .infinity,
              minHeight: MiniPlayerMetrics.coverSide,
              alignment: .topLeading
            )
          }
          .fixedSize(horizontal: false, vertical: true)

          VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
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
              .controlSize(.mini)

              Group {
                HStack(spacing: 0) {
                  Text(formatPlaybackTime(pos))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                  Text(formatPlaybackTime(dur))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline.monospacedDigit())
              }
              .padding(.top, -4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MiniPlayerActiveControlRows()
              .frame(maxWidth: .infinity)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else if model.isRestoringLaunchPlayback {
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(AppTheme.textSecondary.opacity(0.12))
              .frame(width: MiniPlayerMetrics.coverSide, height: MiniPlayerMetrics.coverSide)
              .overlay {
                ProgressView()
                  .tint(AppTheme.accent)
              }
              .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
              Text("Wiedergabe")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
              Text("Letzte Position wird geladen …")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)

              Spacer(minLength: 0)

              MiniPlayerSleepAirPlayPlaceholderRow()
            }
            .frame(
              maxWidth: .infinity,
              minHeight: MiniPlayerMetrics.coverSide,
              alignment: .topLeading
            )
          }
          .fixedSize(horizontal: false, vertical: true)

          VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
              ProgressView()
                .controlSize(.small)
                .tint(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
              HStack(spacing: 6) {
                Text("0:00")
                Spacer(minLength: 0)
                Text("—")
              }
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
              .padding(.top, -4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MiniPlayerPlaceholderControlStrip()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wiedergabe wird geladen.")
      } else if showIdlePlaceholder {
        VStack(alignment: .leading, spacing: 2) {
          HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(AppTheme.textSecondary.opacity(0.12))
              .frame(width: MiniPlayerMetrics.coverSide, height: MiniPlayerMetrics.coverSide)
              .overlay {
                Image(systemName: "waveform")
                  .font(.title2)
                  .foregroundStyle(AppTheme.textSecondary.opacity(0.45))
              }
              .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
              Text("Keine Wiedergabe")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
              Text("Wähle ein anderes Hörbuch in der Bibliothek.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)

              Spacer(minLength: 0)

              MiniPlayerSleepAirPlayPlaceholderRow()
            }
            .frame(
              maxWidth: .infinity,
              minHeight: MiniPlayerMetrics.coverSide,
              alignment: .topLeading
            )
          }
          .fixedSize(horizontal: false, vertical: true)

          VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
              Slider(value: .constant(0), in: 0 ... 1)
                .tint(AppTheme.accent.opacity(0.35))
                .controlSize(.mini)
                .disabled(true)
              HStack(spacing: 6) {
                Text("0:00")
                Spacer(minLength: 0)
                Text("0:00")
              }
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
              .padding(.top, -4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MiniPlayerPlaceholderControlStrip()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keine Wiedergabe. Wähle ein Hörbuch in der Bibliothek.")
      }
    }
    .padding(12)
    .background(model.player.miniPlayerBarFillColor)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onAppear {
      MiniPlayerSliderThumb.applyOnce()
    }
  }
}

// MARK: - Abspielgeschwindigkeit (Sheet wie Schlummer-Timer)

struct PlaybackSpeedSheet: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    NavigationStack {
      List {
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
      }
      .navigationTitle("Tempo")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Fertig") { model.showPlaybackSpeedPicker = false }
        }
      }
    }
  }
}
