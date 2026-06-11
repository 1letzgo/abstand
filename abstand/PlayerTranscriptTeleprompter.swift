import SwiftUI

// MARK: - Model

struct PlayerTranscriptLine: Identifiable, Equatable {
  let id: String
  let words: [PlayerTranscriptWord]
  let globalStart: Double
  let globalEnd: Double
  let isVolatile: Bool

  var spokenWords: [PlayerTranscriptWord] {
    words.filter { !$0.isWhitespaceOnly }
  }
}

enum PlayerTeleprompterLineRole: Equatable {
  case past
  case current
  case upcoming
  case empty
}

struct PlayerTeleprompterSlot: Identifiable, Equatable {
  let id: String
  let line: PlayerTranscriptLine?
  let role: PlayerTeleprompterLineRole
}

struct PlayerTeleprompterWindow: Equatable {
  /// Immer 9 Slots: 4 zurück, Mitte, 4 voraus.
  let slots: [PlayerTeleprompterSlot]
  let centerLineIndex: Int
  /// 0…1 Fortschritt in der aktuellen Zeile (für weiches Hochscrollen).
  let lineProgress: Double
}

struct PlayerTeleprompterLayout: Equatable {
  let slotHeight: CGFloat
  let lineSpacing: CGFloat
  let fontSize: CGFloat

  var rowStride: CGFloat { slotHeight + lineSpacing }
  var totalHeight: CGFloat {
    CGFloat(PlayerTeleprompterMetrics.visibleLineCount) * slotHeight
      + CGFloat(PlayerTeleprompterMetrics.visibleLineCount - 1) * lineSpacing
  }

  var transcriptFont: Font { .system(size: fontSize, weight: .bold) }
}

enum PlayerTeleprompterMetrics {
  static let visibleLineCount = 9
  static let linesBeforeCenter = 4
  /// Innenabstand Text ↔ Kartenrand.
  static let cardContentPadding: CGFloat = 14
  static let defaultLineSpacing: CGFloat = 0
  /// Zeilenhöhe für .bold (sonst wird Text im Slot abgeschnitten).
  static let lineHeightFactor: CGFloat = 1.22
  /// Gegenüber der Karten-Fit-Berechnung etwas kleiner.
  static let fontSizeReduction: CGFloat = 4
  static let defaultFontSize: CGFloat = 24
  /// Zeilen ober/unterhalb der aktiven Zeile (symmetrisch ausgeblendet).
  static let inactiveLineTextOpacity: CGFloat = 0.32
  /// Wörter in der aktiven Zeile (ohne Hervorhebung).
  static let activeLineTextOpacity: CGFloat = 0.65

  static var defaultLayout: PlayerTeleprompterLayout {
    layout(forViewportHeight: defaultViewportHeight)
  }

  static var defaultViewportHeight: CGFloat {
    defaultLayout.totalHeight
  }

  /// Schrift skaliert in die Kartenhöhe; Zeilen dicht beieinander.
  static func layout(forViewportHeight viewportHeight: CGFloat) -> PlayerTeleprompterLayout {
    let lineSpacing = defaultLineSpacing
    let count = CGFloat(visibleLineCount)
    let gaps = count - 1
    let fitSize: CGFloat
    if viewportHeight > gaps * lineSpacing {
      fitSize = (viewportHeight - gaps * lineSpacing) / (count * lineHeightFactor)
    } else {
      fitSize = defaultFontSize + fontSizeReduction
    }
    let fontSize = min(30, max(15, fitSize - fontSizeReduction))
    let slotHeight = ceil(fontSize * lineHeightFactor)
    return PlayerTeleprompterLayout(
      slotHeight: slotHeight,
      lineSpacing: lineSpacing,
      fontSize: fontSize
    )
  }

  /// Zeichen pro Teleprompter-Zeile aus verfügbarer Breite.
  static func characterLimit(forContentWidth width: CGFloat, layout: PlayerTeleprompterLayout) -> Int {
    guard width > 1 else { return 42 }
    let charWidth = layout.fontSize * 0.56
    return max(12, Int(floor(width / charWidth)))
  }
}

// MARK: - View

struct PlayerLiveTranscriptPanelView: View {
  @Environment(\.appearanceThemeRevision) private var themeRevision
  @ObservedObject var transcription: PlayerLiveTranscriptionController
  let globalPlaybackTime: Double
  var isPlaying: Bool = false
  var playbackRate: Double = 1
  /// Volle Kartenhöhe/-breite (Cover 1:1); sonst Standardmaße.
  var viewportSize: CGSize?

  @State private var playbackClock = ReadAlongPlaybackClock()

  private var teleprompterLayout: PlayerTeleprompterLayout {
    if let viewportSize, viewportSize.height > 0 {
      return PlayerTeleprompterMetrics.layout(forViewportHeight: viewportSize.height)
    }
    return PlayerTeleprompterMetrics.defaultLayout
  }

  var body: some View {
    let _ = themeRevision
    return ZStack(alignment: .topLeading) {
      if transcription.transcriptLines.isEmpty {
        HStack(spacing: 10) {
          ProgressView()
            .controlSize(.small)
          Text(placeholderText)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      } else {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
          let displayTime = playbackClock.displayedTime(
            at: timeline.date,
            target: globalPlaybackTime,
            isPlaying: isPlaying,
            playbackRate: playbackRate
          )
          VStack(spacing: 0) {
            Spacer(minLength: 0)
            teleprompterStack(at: displayTime)
              .frame(height: teleprompterLayout.totalHeight, alignment: .topLeading)
              .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .background {
          GeometryReader { geo in
            Color.clear
              .onAppear { syncContentWidth(geo.size.width) }
              .onChange(of: geo.size.width) { _, width in
                syncContentWidth(width)
              }
          }
        }
      }

      if let notice = transcription.localeFallbackNotice {
        Text(notice)
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
          .lineLimit(2)
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(AppTheme.card.opacity(0.9))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      playbackClock.hardReset(to: globalPlaybackTime)
      if let viewportSize { syncContentWidth(viewportSize.width) }
    }
    .onChange(of: viewportSize) { _, size in
      if let size { syncContentWidth(size.width) }
    }
    .abstandThemeRefresh()
  }

  private func syncContentWidth(_ width: CGFloat) {
    let contentWidth = viewportSize.map { max(0, $0.width) } ?? width
    transcription.updateTeleprompterContentWidth(contentWidth, layout: teleprompterLayout)
  }

  private func teleprompterStack(at time: Double) -> some View {
    let lines = transcription.transcriptLines
    let fractionalLine = transcription.fractionalActiveLinePosition(at: time)
    let centerIdx = Int(floor(fractionalLine))
    let progress = fractionalLine - floor(fractionalLine)
    let layout = teleprompterLayout
    let intraLineOffset = -CGFloat(progress) * layout.rowStride
    let activeWord = transcription.activeWord(at: time)
    let activeLineIndex = activeTranscriptLineIndex(
      in: lines, centerIdx: centerIdx, activeWord: activeWord)

    return VStack(alignment: .leading, spacing: layout.lineSpacing) {
      ForEach(-PlayerTeleprompterMetrics.linesBeforeCenter...PlayerTeleprompterMetrics.linesBeforeCenter, id: \.self) { delta in
        let lineIndex = centerIdx + delta

        Group {
          if lineIndex >= 0, lineIndex < lines.count {
            lineText(
              lines[lineIndex],
              lineIndex: lineIndex,
              activeLineIndex: activeLineIndex,
              activeWord: activeWord,
              layout: layout,
              lookupSelection: transcription.wordLookupSelection,
              onWordTap: selectWordForLookup
            )
          } else {
            Text(" ")
              .font(layout.transcriptFont)
              .foregroundStyle(.clear)
          }
        }
        .frame(height: layout.slotHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .offset(y: intraLineOffset)
    .compositingGroup()
  }

  private func activeTranscriptLineIndex(
    in lines: [PlayerTranscriptLine],
    centerIdx: Int,
    activeWord: PlayerTranscriptWord?
  ) -> Int {
    guard let activeWord,
      let idx = lines.firstIndex(where: { line in
        line.words.contains { $0.id == activeWord.id }
      })
    else { return centerIdx }
    return idx
  }

  private func selectWordForLookup(_ word: PlayerTranscriptWord) {
    guard !word.isWhitespaceOnly else { return }
    let term = PlayerTranscriptWordLookup.normalizedTerm(from: word.text)
    guard !term.isEmpty else { return }
    transcription.wordLookupSelection = PlayerTranscriptWordLookupSelection(
      word: word,
      term: term,
      sourceLocale: transcription.transcriptionLocale
    )
  }

  @ViewBuilder
  private func lineText(
    _ line: PlayerTranscriptLine,
    lineIndex: Int,
    activeLineIndex: Int,
    activeWord: PlayerTranscriptWord?,
    layout: PlayerTeleprompterLayout,
    lookupSelection: PlayerTranscriptWordLookupSelection?,
    onWordTap: @escaping (PlayerTranscriptWord) -> Void
  ) -> some View {
    let isOnActiveLine = lineIndex == activeLineIndex
    HStack(spacing: 0) {
      ForEach(line.words) { word in
        let isActive = activeWord?.id == word.id
        let isSelected = lookupSelection?.word.id == word.id
        if word.isWhitespaceOnly {
          Text(word.text)
            .font(layout.transcriptFont)
            .foregroundStyle(.clear)
        } else {
          Button {
            onWordTap(word)
          } label: {
            Text(word.text)
              .font(layout.transcriptFont)
              .foregroundStyle(
                wordColor(
                  isOnActiveLine: isOnActiveLine,
                  isActive: isActive,
                  isSelected: isSelected,
                  isVolatile: word.isVolatile
                )
              )
              .underline(isSelected, color: AppTheme.accent)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(word.text)
          .accessibilityHint(
            String(localized: "Look up or translate this word", comment: "Teleprompter word tap")
          )
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .lineLimit(1)
  }

  private func wordColor(
    isOnActiveLine: Bool,
    isActive: Bool,
    isSelected: Bool,
    isVolatile: Bool
  ) -> Color {
    if isSelected { return AppTheme.accent }
    if isActive { return AppTheme.accent }
    if isVolatile { return AppTheme.textPrimary.opacity(0.4) }
    let opacity = isOnActiveLine
      ? PlayerTeleprompterMetrics.activeLineTextOpacity
      : PlayerTeleprompterMetrics.inactiveLineTextOpacity
    return AppTheme.textPrimary.opacity(opacity)
  }

  private var placeholderText: String {
    if transcription.modelDownloadProgress != nil {
      return String(localized: "Downloading speech model…", comment: "Live transcript placeholder")
    }
    if transcription.isPreparing {
      return String(localized: "Preparing transcript…", comment: "Live transcript placeholder")
    }
    return String(localized: "Transcribing audio…", comment: "Live transcript placeholder")
  }
}

// MARK: - Smooth time (60 fps)

/// Extrapoliert zwischen Player-Ticks (≈0,35 s) mit konstanter Rate — ohne pro-Frame `.task`.
private final class ReadAlongPlaybackClock {
  private var anchorTime: Double = 0
  private var anchorInstant: TimeInterval = 0
  private var lastTarget: Double = -1
  private var hasAnchor = false

  func hardReset(to target: Double) {
    anchorTime = target
    anchorInstant = Date().timeIntervalSinceReferenceDate
    lastTarget = target
    hasAnchor = true
  }

  func displayedTime(
    at instant: Date,
    target: Double,
    isPlaying: Bool,
    playbackRate: Double
  ) -> Double {
    let now = instant.timeIntervalSinceReferenceDate
    let rate = max(0.25, min(3, playbackRate))

    if !hasAnchor || abs(target - lastTarget) > 2 {
      anchorTime = target
      anchorInstant = now
      lastTarget = target
      hasAnchor = true
      return target
    }

    if !isPlaying {
      anchorTime = target
      anchorInstant = now
      lastTarget = target
      return target
    }

    if target != lastTarget {
      let extrapolated = anchorTime + (now - anchorInstant) * rate
      anchorTime = extrapolated
      anchorInstant = now
      lastTarget = target
    }

    let extrapolated = anchorTime + (now - anchorInstant) * rate
    let drift = target - extrapolated
    if abs(drift) > 0.4 {
      anchorTime = target
      anchorInstant = now
      return target
    }
    if abs(drift) > 0.04 {
      anchorTime += drift * 0.18
      anchorInstant = now
    }
    return anchorTime + (now - anchorInstant) * rate
  }
}
