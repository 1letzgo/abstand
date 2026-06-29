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
  let slots: [PlayerTeleprompterSlot]
  let centerLineIndex: Int
  /// 0…1 Fortschritt in der aktuellen Zeile (für weiches Hochscrollen).
  let lineProgress: Double
}

struct PlayerTeleprompterLayout: Equatable {
  let slotHeight: CGFloat
  let lineSpacing: CGFloat
  let fontSize: CGFloat
  /// Immer gerenderte Zeilen (Mitte ± Puffer); sichtbar nur der Container-Ausschnitt.
  let renderedLineCount: Int

  var linesBeforeCenter: Int { (renderedLineCount - 1) / 2 }
  var rowStride: CGFloat { slotHeight + lineSpacing }
  /// Volle Stack-Höhe — kann größer als der sichtbare Viewport sein (Clipping).
  var stackHeight: CGFloat {
    CGFloat(renderedLineCount) * slotHeight
      + CGFloat(max(0, renderedLineCount - 1)) * lineSpacing
  }

  var transcriptFont: Font { .system(size: fontSize, weight: .bold) }
}

enum PlayerTeleprompterMetrics {
  /// Schriftgröße: so viele Zeilen passen in die kompakte Kartenhöhe.
  static let collapsedVisibleLineCount = 9
  /// Immer gerendert (Mitte ±10); Expand zeigt mehr durch größeren Container + Clip.
  static let renderedLinesBeforeCenter = 10
  static var renderedLineCount: Int { renderedLinesBeforeCenter * 2 + 1 }
  /// Legacy-Alias für Controller-Helfer.
  static var visibleLineCount: Int { renderedLineCount }
  static var linesBeforeCenter: Int { renderedLinesBeforeCenter }
  /// Innenabstand Text ↔ Kartenrand.
  static let cardContentPadding: CGFloat = 14
  static let defaultLineSpacing: CGFloat = 0
  /// Zeilenhöhe für .bold (sonst wird Text im Slot abgeschnitten).
  static let lineHeightFactor: CGFloat = 1.22
  /// Gegenüber der Karten-Fit-Berechnung etwas kleiner.
  static let fontSizeReduction: CGFloat = 4
  static let defaultFontSize: CGFloat = 24
  static let minFontSize: CGFloat = 14
  static let maxFontSize: CGFloat = 34
  static let fontSizeStep: CGFloat = 2
  static let fontSizeStorageKey = "abstand_teleprompter_font_size"
  /// Zeilen ober/unterhalb der aktiven Zeile (symmetrisch ausgeblendet).
  static let inactiveLineTextOpacity: CGFloat = 0.32
  /// Wörter in der aktiven Zeile (ohne Hervorhebung).
  static let activeLineTextOpacity: CGFloat = 0.65

  static func clampFontSize(_ size: CGFloat) -> CGFloat {
    min(maxFontSize, max(minFontSize, size))
  }

  static func savedFontSize() -> CGFloat? {
    let d = UserDefaults.standard
    guard d.object(forKey: fontSizeStorageKey) != nil else { return nil }
    return clampFontSize(CGFloat(d.double(forKey: fontSizeStorageKey)))
  }

  static func persistFontSize(_ size: CGFloat) {
    UserDefaults.standard.set(Double(clampFontSize(size)), forKey: fontSizeStorageKey)
  }

  /// Automatische Schriftgröße aus Kartenbreite (9 Zeilen Referenz).
  static func autoFontSize(sizingViewportHeight: CGFloat) -> CGFloat {
    let lineSpacing = defaultLineSpacing
    let sizingCount = CGFloat(collapsedVisibleLineCount)
    let gaps = sizingCount - 1
    let fitSize: CGFloat
    if sizingViewportHeight > gaps * lineSpacing {
      fitSize = (sizingViewportHeight - gaps * lineSpacing) / (sizingCount * lineHeightFactor)
    } else {
      fitSize = defaultFontSize + fontSizeReduction
    }
    return clampFontSize(fitSize - fontSizeReduction)
  }

  static var defaultLayout: PlayerTeleprompterLayout {
    layout(sizingViewportHeight: 300)
  }

  /// Nutzer-Schriftgröße schlägt Auto-Fit; persistiert in UserDefaults.
  static func layout(sizingViewportHeight: CGFloat, userFontSize: CGFloat? = nil) -> PlayerTeleprompterLayout {
    let lineSpacing = defaultLineSpacing
    let resolvedSize: CGFloat
    if let userFontSize {
      resolvedSize = clampFontSize(userFontSize)
    } else if let saved = savedFontSize() {
      resolvedSize = saved
    } else {
      resolvedSize = autoFontSize(sizingViewportHeight: sizingViewportHeight)
    }
    let fontSize = resolvedSize
    let slotHeight = ceil(fontSize * lineHeightFactor)
    return PlayerTeleprompterLayout(
      slotHeight: slotHeight,
      lineSpacing: lineSpacing,
      fontSize: fontSize,
      renderedLineCount: renderedLineCount
    )
  }

  /// +/- am Player: aktuelle Größe (gespeichert oder Auto) anpassen und cachen.
  static func bumpFontSize(
    delta: CGFloat,
    sizingViewportHeight: CGFloat,
    storedFontSize: CGFloat?
  ) -> CGFloat {
    let current = storedFontSize.map(clampFontSize) ?? autoFontSize(sizingViewportHeight: sizingViewportHeight)
    let next = clampFontSize(current + delta)
    persistFontSize(next)
    return next
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
  @ObservedObject var player: PlaybackController
  @ObservedObject var transcription: PlayerLiveTranscriptionController
  /// Volle Kartenhöhe/-breite (Cover 1:1); sonst Standardmaße.
  var viewportSize: CGSize?
  /// Gespeicherte Nutzer-Schriftgröße (nil = Auto-Fit bzw. noch kein Override).
  var userFontSize: CGFloat?

  @State private var playbackClock = ReadAlongPlaybackClock()

  private var livePlaybackTime: Double { player.liveGlobalPlaybackPosition }

  private var teleprompterLayout: PlayerTeleprompterLayout {
    guard let viewportSize, viewportSize.height > 0 else {
      return PlayerTeleprompterMetrics.defaultLayout
    }
    // Schrift wie im quadratischen Cover (Breite), Stack höher als Viewport → Clip zeigt mehr im Expand.
    let sizingHeight = max(viewportSize.width, 1)
    return PlayerTeleprompterMetrics.layout(
      sizingViewportHeight: sizingHeight,
      userFontSize: userFontSize
    )
  }

  var body: some View {
    let _ = themeRevision
    return ZStack {
      if showsTeleprompterContent {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
          let displayTime = playbackClock.displayedTime(
            at: timeline.date,
            target: livePlaybackTime,
            isPlaying: player.isPlaying,
            playbackRate: Double(player.playbackRate)
          )
          GeometryReader { geo in
            let layout = teleprompterLayout
            // Aktive Zeile (Mitte des Stacks) immer auf Viewport-Mitte — auch beim Start.
            let activeLineCenterY =
              CGFloat(layout.linesBeforeCenter) * layout.rowStride + layout.slotHeight / 2
            let yOffset = geo.size.height * 0.5 - activeLineCenterY

            teleprompterStack(at: displayTime)
              .frame(width: geo.size.width, alignment: .leading)
              .offset(y: yOffset)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .background {
          GeometryReader { geo in
            Color.clear
              .onAppear { syncTeleprompterLayout(fromWidth: geo.size.width) }
              .onChange(of: geo.size.width) { _, width in
                syncTeleprompterLayout(fromWidth: width)
              }
          }
        }
      }

      if showsLoadingOverlay {
        teleprompterLoadingOverlay
      }

      if showsErrorOverlay, let error = transcription.errorMessage {
        teleprompterErrorOverlay(message: error)
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
      alignTeleprompterToLivePlayback(force: true)
      syncTeleprompterLayout()
    }
    .onChange(of: transcription.isTeleprompterModeActive) { _, active in
      if active {
        alignTeleprompterToLivePlayback(force: true)
        syncTeleprompterLayout()
      }
    }
    .onChange(of: livePlaybackTime) { _, newTime in
      if abs(newTime - playbackClock.lastSyncedTarget) > 2 {
        playbackClock.hardReset(to: newTime)
      }
    }
    .onChange(of: transcription.teleprompterSyncGeneration) { _, _ in
      playbackClock.hardReset(to: transcription.teleprompterSyncedPlaybackTime)
    }
    .onChange(of: transcription.isTeleprompterReady) { _, ready in
      if ready {
        alignTeleprompterToLivePlayback(force: true)
      }
    }
    .onChange(of: transcription.isEnabled) { _, enabled in
      if enabled {
        alignTeleprompterToLivePlayback(force: true)
      }
    }
    .onChange(of: viewportSize) { _, _ in
      syncTeleprompterLayout()
    }
    .onChange(of: userFontSize) { _, _ in
      syncTeleprompterLayout()
    }
    .abstandThemeRefresh()
  }

  private func syncTeleprompterLayout() {
    let width = viewportSize.map { max(0, $0.width) } ?? 0
    if width > 0 {
      transcription.updateTeleprompterContentWidth(width, layout: teleprompterLayout)
    }
  }

  private func syncTeleprompterLayout(fromWidth width: CGFloat? = nil) {
    let resolvedWidth = width ?? viewportSize.map { max(0, $0.width) } ?? 0
    if resolvedWidth > 0 {
      transcription.updateTeleprompterContentWidth(resolvedWidth, layout: teleprompterLayout)
    }
  }

  private var showsTeleprompterContent: Bool {
    !transcription.transcriptLines.isEmpty
  }

  private var showsLoadingOverlay: Bool {
    transcription.isTeleprompterModeActive
      && !showsTeleprompterContent
      && transcription.errorMessage == nil
  }

  private var showsErrorOverlay: Bool {
    transcription.isTeleprompterModeActive
      && !showsTeleprompterContent
      && transcription.errorMessage != nil
  }

  private var teleprompterLoadingOverlay: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.regular)
      if !loadingHintText.isEmpty {
        Text(loadingHintText)
          .font(.subheadline)
          .foregroundStyle(AppTheme.textSecondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func teleprompterErrorOverlay(message: String) -> some View {
    VStack(spacing: 16) {
      Text(message)
        .font(.subheadline)
        .foregroundStyle(AppTheme.danger)
        .multilineTextAlignment(.center)
      Button(String(localized: "Try again", comment: "Live transcript retry")) {
        Task { @MainActor in
          await transcription.disable()
          await transcription.startTeleprompterMode(player: player)
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(AppTheme.accent)
    }
    .padding(.horizontal, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var loadingHintText: String {
    if transcription.modelDownloadProgress != nil {
      return String(localized: "Downloading speech model…", comment: "Live transcript placeholder")
    }
    if transcription.isPreparing {
      return String(localized: "Preparing transcript…", comment: "Live transcript placeholder")
    }
    return String(localized: "Transcribing audio…", comment: "Live transcript placeholder")
  }

  /// Teleprompter an Live-Wiedergabe ausrichten und Uhr zurücksetzen.
  private func alignTeleprompterToLivePlayback(force: Bool) {
    player.syncGlobalPositionFromPlayer()
    let live = player.liveGlobalPlaybackPosition
    transcription.syncTeleprompterToPlayback(at: live, force: force)
    playbackClock.hardReset(to: live)
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
      ForEach(-layout.linesBeforeCenter...layout.linesBeforeCenter, id: \.self) { delta in
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
}

// MARK: - Smooth time (60 fps)

/// Während Wiedergabe direkt AVPlayer-Ziel — keine Extrapolation (verhindert Nachhängen).
private final class ReadAlongPlaybackClock {
  private var anchorTime: Double = 0
  private var anchorInstant: TimeInterval = 0
  private var lastTarget: Double = -1
  private var hasAnchor = false

  var lastSyncedTarget: Double { lastTarget }

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

    if isPlaying {
      lastTarget = target
      anchorTime = target
      anchorInstant = now
      hasAnchor = true
      return target
    }

    if !hasAnchor || abs(target - lastTarget) > 2 {
      anchorTime = target
      anchorInstant = now
      lastTarget = target
      hasAnchor = true
      return target
    }

    anchorTime = target
    anchorInstant = now
    lastTarget = target
    return target
  }
}
