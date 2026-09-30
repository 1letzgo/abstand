import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

private enum ReaderChromeMetrics {
  /// Höhe des dünnen passiven Lesefortschrittsbalkens.
  static let passiveProgressBarHeight: CGFloat = 3
  /// Max. Breite des Hinweis-Overlays für die Reading-Controls.
  static let chromeHintMaxWidth: CGFloat = 320
}

struct EbookReaderPresentation: Identifiable {
  let id = UUID()
  let title: String
  let author: String
  let libraryItemId: String
  let localFileURL: URL
  let format: ABSEbookFormat
  /// Server-Lesefortschritt (0…1) als Startposition, wenn lokal kein Lesezeichen existiert.
  var serverResumeProgression: Double? = nil
}

struct ReadiumReaderView: View {
  let title: String
  let author: String
  let libraryItemId: String
  let localFileURL: URL
  let format: ABSEbookFormat
  /// Server-Lesefortschritt als Startposition (nur gesetzt, wenn lokal kein Lesezeichen existiert).
  var serverResumeProgression: Double? = nil
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.themeAccent) private var themeAccent
  @State private var readerTheme = EpubReaderSettings.loadTheme()
  @State private var fontSize = EpubReaderSettings.defaultFontSize
  @State private var continuousScroll = EpubReaderSettings.loadContinuousScroll()
  @State private var navigatorController: UIViewController?
  @State private var epubNavigator: EPUBNavigatorViewController?
  @State private var pdfNavigator: PDFNavigatorViewController?
  @State private var loadError: String?
  @State private var isLoading = true
  @State private var showReaderChrome = false
  @State private var readProgress: Double = 0
  @State private var readProgressLabel = "0 %"
  @State private var bookPageProgress: BookPageProgress?
  @State private var readerActionInProgress = false
  @State private var confirmResetReadingPosition = false
  @State private var confirmMarkAsFinished = false
  @State private var isScrubbingProgress = false
  @State private var scrubProgress: Double = 0
  @AppStorage("abstand_ebook_reader_chrome_hint_seen") private var didShowReaderChromeHint = false
  @State private var showsReaderChromeHint = false
  /// Verhindert Sync mit Anfangs-Locator, bevor Server-Resume oder gespeicherte Position gilt.
  @State private var isInitialReaderLoad = true
  /// Sprung zur Hörposition (nur EPUB, nur wenn dieses Hörbuch im Player geladen ist).
  @State private var narrationJump: EbookNarrationJumpController?
  /// Server steht deutlich weiter als der lokale Locator (z. B. auf einem anderen Gerät gelesen):
  /// Angebot statt stillem Überschreiben. Solange es offen ist, geht kein Fortschritt zum Server.
  @State private var serverPositionOffer: ServerPositionOffer?

  /// So viel weiter (Anteil am Buch) muss der Server sein, damit das Angebot erscheint.
  private static let serverPositionOfferThreshold = 0.02

  private var chromeColorScheme: ColorScheme {
    readerTheme == .dark ? .dark : .light
  }

  private var readerBackground: SwiftUI.Color {
    switch readerTheme {
    case .dark: AppTheme.background
    case .light: .white
    case .sepia: Color(red: 250 / 255, green: 244 / 255, blue: 232 / 255)
    }
  }

  private var readerChromeForeground: SwiftUI.Color {
    readerTheme == .dark ? .white : .primary
  }

  private var readerChromeSecondary: SwiftUI.Color {
    readerTheme == .dark ? .white.opacity(0.72) : .secondary
  }

  var body: some View {
    ZStack {
      Group {
        if isLoading {
          AbstandLoadingSpinner(controlSize: .regular)
        } else if let loadError {
          ContentUnavailableView("Could not open", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else if let navigatorController {
          ReadiumNavigatorHost(controller: navigatorController)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(readerBackground)
      .ignoresSafeArea()

      if !isLoading, loadError == nil, navigatorController != nil {
        readerChromeOverlay
          .allowsHitTesting(showReaderChrome)
      }

      if showsReaderChromeHint, serverPositionOffer == nil {
        readerChromeHint
      }

      if let offer = serverPositionOffer, !showReaderChrome {
        EbookServerPositionBanner(
          offer: offer,
          foreground: readerChromeForeground,
          secondary: readerChromeSecondary,
          onStay: { withAnimation(.snappy(duration: 0.25)) { serverPositionOffer = nil } },
          onContinue: {
            withAnimation(.snappy(duration: 0.25)) { serverPositionOffer = nil }
            Task { await seekToProgression(offer.serverFraction) }
          }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .background(readerBackground)
    .preferredColorScheme(chromeColorScheme)
    // Alert-Buttons (Reset position, Mark as finished, Fehler) folgen dem Tint der Ansicht — ohne
    // diese Zeile erscheint „Cancel" in der App-Akzentfarbe statt in der Reader-Schriftfarbe.
    .tint(readerChromeForeground)
    .statusBarHidden(!showReaderChrome)
    .persistentSystemOverlays(showReaderChrome ? .automatic : .hidden)
    .onReceive(NotificationCenter.default.publisher(for: .readiumReaderToggleChrome)) { _ in
      withAnimation(.easeInOut(duration: 0.2)) {
        showReaderChrome.toggle()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .readiumReaderProgressDidChange)) { note in
      guard !isScrubbingProgress, !isInitialReaderLoad else { return }
      guard let locator = note.userInfo?[ReadiumReaderProgressInfo.locatorKey] as? Locator else { return }
      let pages = note.userInfo?[ReadiumReaderProgressInfo.bookPageProgressKey] as? BookPageProgress
      applyProgress(from: locator, bookPages: pages)
      narrationJump?.readerLocationDidChange()
      // Offenes Server-Angebot: der (ältere) lokale Stand darf den Server nicht überschreiben.
      guard serverPositionOffer == nil else { return }
      model.scheduleEbookProgressSync(
        libraryItemId: libraryItemId,
        fraction: ReadiumReaderProgressInfo.fraction(from: locator)
      )
    }
    .onDisappear { narrationJump?.stop() }
    .task(id: localFileURL.path) {
      fontSize = EpubReaderSettings.loadFontSize()
      continuousScroll = EpubReaderSettings.loadContinuousScroll()
      await loadNavigator()
    }
    // Fehler während der Reader offen ist hier zeigen — der Root-Alert liegt unter dem Cover.
    .alert(
      "Error",
      isPresented: Binding(
        get: { model.errorMessage != nil && model.ebookReaderSession != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .alert("Reset reading position?", isPresented: $confirmResetReadingPosition) {
      Button("Cancel", role: .cancel) {}
      Button("Reset", role: .destructive) {
        Task { await resetReadingPosition() }
      }
    } message: {
      Text("This removes your saved position for this book. You cannot undo this.")
    }
    .alert("Mark as finished?", isPresented: $confirmMarkAsFinished) {
      Button("Cancel", role: .cancel) {}
      Button("Mark as finished") {
        Task { await markAsFinishedReading() }
      }
    } message: {
      Text("Your reading progress will be saved as complete.")
    }
  }

  private var isEbookMarkedFinished: Bool {
    (model.ebookDisplayProgressFraction(libraryItemId: libraryItemId) ?? 0) >= 0.995
  }

  private var readerChromeOverlay: some View {
    VStack(spacing: 0) {
      if showReaderChrome {
        readerTopChrome
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      Spacer()
      if showReaderChrome {
        readerBottomChrome
          .transition(.move(edge: .bottom).combined(with: .opacity))
      } else {
        readerPassiveProgressIndicator
      }
    }
    .animation(.easeInOut(duration: 0.2), value: showReaderChrome)
  }

  /// Orientierung und Schließen bleiben oben; alle Leseaktionen liegen separat am unteren Rand.
  private var readerTopChrome: some View {
    HStack(spacing: AppTheme.Layout.rowSpacing) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title2)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(readerChromeForeground)
      }
      .accessibilityLabel("Close")

      VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .foregroundStyle(readerChromeForeground)

        Text(author)
          .font(.caption)
          .lineLimit(1)
          .foregroundStyle(readerChromeSecondary)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, AppTheme.Layout.screenPadding)
    .padding(.vertical, AppTheme.Layout.withinSectionSpacing)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .safeAreaPadding(.top, 4)
  }

  /// Primäre Lesesteuerung bewusst am unteren Bildschirmrand für einhändige Bedienung.
  private var readerBottomChrome: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      readerProgressScrubber

      HStack(spacing: AppTheme.Layout.rowSpacing) {
        if format == .epub {
          HStack(spacing: AppTheme.Layout.stackSpacing) {
            Button {
              fontSize = max(EpubReaderSettings.minFontSize, fontSize - EpubReaderSettings.fontSizeStep)
              EpubReaderSettings.saveFontSize(fontSize)
              applyEPUBPrefs()
            } label: {
              Image(systemName: "textformat.size.smaller")
                .font(.body)
                .frame(width: AppTheme.Layout.compactIconButtonSize, height: AppTheme.Layout.compactIconButtonSize)
            }
            .disabled(fontSize <= EpubReaderSettings.minFontSize)

            Button {
              fontSize = min(EpubReaderSettings.maxFontSize, fontSize + EpubReaderSettings.fontSizeStep)
              EpubReaderSettings.saveFontSize(fontSize)
              applyEPUBPrefs()
            } label: {
              Image(systemName: "textformat.size.larger")
                .font(.body)
                .frame(width: AppTheme.Layout.compactIconButtonSize, height: AppTheme.Layout.compactIconButtonSize)
            }
            .disabled(fontSize >= EpubReaderSettings.maxFontSize)
          }
        }

        Spacer(minLength: 0)

        if let narrationJump {
          EbookNarrationJumpButton(controller: narrationJump)
        }

        Button {
          continuousScroll.toggle()
          EpubReaderSettings.saveContinuousScroll(continuousScroll)
          if format == .epub {
            applyEPUBPrefs()
          } else {
            applyPDFPrefs()
          }
        } label: {
          Image(systemName: continuousScroll ? "scroll" : "book.pages")
            .font(.body)
            .frame(width: AppTheme.Layout.iconButtonSize, height: AppTheme.Layout.iconButtonSize)
        }
        .accessibilityLabel("Continuous scroll")
        .accessibilityValue(continuousScroll ? "On" : "Off")

        Menu {
          Button {
            applyReaderTheme(.light)
          } label: {
            Label("Light", systemImage: readerTheme == .light ? "checkmark" : "sun.max")
          }
          Button {
            applyReaderTheme(.sepia)
          } label: {
            Label("Sepia", systemImage: readerTheme == .sepia ? "checkmark" : "text.page")
          }
          Button {
            applyReaderTheme(.dark)
          } label: {
            Label("Dark", systemImage: readerTheme == .dark ? "checkmark" : "moon")
          }
        } label: {
          Image(systemName: readerTheme.themeToolbarIcon)
            .font(.body)
            .frame(width: AppTheme.Layout.iconButtonSize, height: AppTheme.Layout.iconButtonSize)
        }
        .accessibilityLabel("Reader theme")
        .accessibilityValue(readerTheme.displayName)

        Menu {
          Button {
            confirmMarkAsFinished = true
          } label: {
            Label(
              isEbookMarkedFinished ? "Finished reading" : "Mark as finished",
              systemImage: isEbookMarkedFinished ? "checkmark.circle.fill" : "checkmark.circle"
            )
          }
          .disabled(readerActionInProgress || isEbookMarkedFinished)

          Button(role: .destructive) {
            confirmResetReadingPosition = true
          } label: {
            Label("Reset position", systemImage: "arrow.counterclockwise")
          }
          .disabled(readerActionInProgress)
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.title3)
            .frame(width: AppTheme.Layout.iconButtonSize, height: AppTheme.Layout.iconButtonSize)
        }
        .accessibilityLabel("Reader options")
      }
      .foregroundStyle(readerChromeForeground)
      .tint(readerChromeForeground)
    }
    .padding(.horizontal, AppTheme.Layout.screenPadding)
    .padding(.vertical, AppTheme.Layout.withinSectionSpacing)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .safeAreaPadding(.bottom, 4)
  }

  /// Dezente Orientierung auch bei ausgeblendeter Steuerung, ohne den Lesefluss zu stören.
  private var readerPassiveProgressIndicator: some View {
    GeometryReader { geo in
      Rectangle()
        .fill(themeAccent.opacity(0.75))
        .frame(width: geo.size.width * min(1, max(0, readProgress)), height: ReaderChromeMetrics.passiveProgressBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: ReaderChromeMetrics.passiveProgressBarHeight)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var readerChromeHint: some View {
    VStack {
      Spacer()
      VStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        Image(systemName: "hand.tap")
          .font(.title2)
          .foregroundStyle(themeAccent)
        Text("Reading controls")
          .font(.headline)
        Text("Tap the middle of the page to show reading controls and progress.")
          .font(.subheadline)
          .foregroundStyle(readerChromeSecondary)
          .multilineTextAlignment(.center)
        Button("Got it") {
          didShowReaderChromeHint = true
          withAnimation(.easeOut(duration: 0.2)) {
            showsReaderChromeHint = false
          }
        }
        .buttonStyle(AbstandProminentButtonStyle())
      }
      .padding(AppTheme.Layout.overlayPadding)
      .frame(maxWidth: ReaderChromeMetrics.chromeHintMaxWidth)
      .background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: AppTheme.Layout.readerChromeCornerRadius, style: .continuous)
      )
      .padding(.bottom, AppTheme.Layout.minTapTarget)
    }
    .padding(.horizontal, AppTheme.Layout.blockSpacing)
  }

  private var readerProgressScrubber: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.tightSpacing) {
      Slider(
        value: isScrubbingProgress ? $scrubProgress : $readProgress,
        in: 0 ... 1,
        onEditingChanged: { editing in
          if editing {
            isScrubbingProgress = true
            scrubProgress = readProgress
          } else {
            let target = scrubProgress
            isScrubbingProgress = false
            Task { await seekToProgression(target) }
          }
        }
      )
      .tint(themeAccent)
      .disabled(readerActionInProgress || isLoading)
      .accessibilityLabel("Reading progress")
      .accessibilityValue(
        isScrubbingProgress
          ? "\(Int((scrubProgress * 100).rounded())) percent"
          : readProgressLabel
      )

      Text(isScrubbingProgress ? scrubProgressCaption : readProgressLabel)
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(readerChromeSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
  }

  private var scrubProgressCaption: String {
    let pct = Int((scrubProgress * 100).rounded())
    if format == .pdf,
      let total = ReadiumReaderDelegate.shared.positionCountForDisplay,
      total > 1
    {
      let page = min(total, max(1, Int((scrubProgress * Double(total)).rounded())))
      return "Page \(page) of \(total) · \(pct)%"
    }
    return "\(pct)%"
  }

  @MainActor
  private func seekToProgression(_ progression: Double) async {
    guard let navigator: Navigator = epubNavigator ?? pdfNavigator else { return }
    readerActionInProgress = true
    defer { readerActionInProgress = false }
    await ReadiumReaderService.shared.seekToProgression(
      navigator: navigator,
      libraryItemId: libraryItemId,
      format: format,
      progression: progression
    )
  }

  private func applyProgress(from locator: Locator, bookPages: BookPageProgress? = nil) {
    if let bookPages {
      self.bookPageProgress = bookPages
    }
    if let bookPages {
      readProgress = Double(bookPages.percent) / 100.0
    } else {
      readProgress = ReadiumReaderProgressInfo.fraction(from: locator)
    }
    readProgressLabel = ReadiumReaderProgressInfo.label(
      from: locator,
      format: format,
      positionCount: ReadiumReaderDelegate.shared.positionCountForDisplay,
      bookPages: self.bookPageProgress
    )
  }

  private func applyEPUBPrefs() {
    guard let epubNavigator else { return }
    ReadiumReaderService.shared.applyEPUBPreferences(to: epubNavigator)
  }

  private func applyReaderTheme(_ theme: EpubReaderTheme) {
    guard readerTheme != theme else { return }
    readerTheme = theme
    EpubReaderSettings.saveTheme(theme)
    if format == .epub {
      applyEPUBPrefs()
    } else {
      applyPDFPrefs()
    }
  }

  private func applyPDFPrefs() {
    guard let pdfNavigator else { return }
    ReadiumReaderService.shared.applyPDFPreferences(to: pdfNavigator)
  }

  @MainActor
  private func resetReadingPosition() async {
    guard let navigator: Navigator = epubNavigator ?? pdfNavigator else { return }
    readerActionInProgress = true
    defer { readerActionInProgress = false }
    await model.resetEbookReadingProgress(libraryItemId: libraryItemId, format: format)
    await ReadiumReaderService.shared.resetReadingPosition(
      navigator: navigator,
      libraryItemId: libraryItemId,
      format: format
    )
    readProgress = 0
    readProgressLabel = "0 %"
    bookPageProgress = nil
  }

  @MainActor
  private func markAsFinishedReading() async {
    readerActionInProgress = true
    defer { readerActionInProgress = false }
    await model.markEbookAsFinished(libraryItemId: libraryItemId, format: format)
  }

  @MainActor
  private func loadNavigator() async {
    isLoading = true
    isInitialReaderLoad = true
    loadError = nil
    ReadiumReaderDelegate.shared.configure(libraryItemId: libraryItemId, format: format)
    let savedLocator = model.ebookResumeLocatorForReader(
      libraryItemId: libraryItemId, format: format)
    let resumeTarget =
      savedLocator == nil
      ? (serverResumeProgression
        ?? model.ebookResumeProgressionForReader(libraryItemId: libraryItemId))
      : nil
    defer { isInitialReaderLoad = false }
    do {
      let vc = try await ReadiumReaderService.shared.makeReader(
        localFileURL: localFileURL,
        libraryItemId: libraryItemId,
        format: format,
        resumeLocator: savedLocator,
        resumeProgression: resumeTarget
      )
      navigatorController = vc
      epubNavigator = vc as? EPUBNavigatorViewController
      pdfNavigator = vc as? PDFNavigatorViewController
      // Ohne gespeicherten Locator: EPUB-WebView oft erst nach Layout bereit — ggf. erneut springen.
      if savedLocator == nil, let target = resumeTarget, format == .epub, let epub = epubNavigator {
        let atStart = (epub.currentLocation.map { ReadiumReaderProgressInfo.fraction(from: $0) } ?? 0) < target * 0.5
        if atStart {
          _ = await ReadiumReaderService.shared.seekToProgression(
            navigator: epub,
            libraryItemId: libraryItemId,
            format: format,
            progression: target
          )
        }
      } else if savedLocator == nil, let target = resumeTarget, pdfNavigator != nil {
        _ = await ReadiumReaderService.shared.seekToProgression(
          navigator: pdfNavigator!,
          libraryItemId: libraryItemId,
          format: format,
          progression: target
        )
      }
      if format == .epub, let epub = epubNavigator {
        narrationJump?.stop()
        narrationJump = EbookNarrationJumpController(
          model: model,
          libraryItemId: libraryItemId,
          navigator: epub
        )
        if let current = epub.currentLocation {
          applyProgress(from: current)
        }
        await ReadiumReaderService.shared.refreshEpubProgressDisplay(epub: epub)
      } else if let current = pdfNavigator?.currentLocation {
        applyProgress(from: current)
      }
      // Lokaler Locator vorhanden, Server aber weiter: anbieten statt stumm die alte Seite zu öffnen.
      if let saved = savedLocator,
        let server = model.serverEbookFractionForReader(libraryItemId: libraryItemId)
      {
        let local = ReadiumReaderProgressInfo.fraction(from: saved)
        if server - local >= Self.serverPositionOfferThreshold {
          serverPositionOffer = ServerPositionOffer(serverFraction: server, localFraction: local)
        }
      }
      isLoading = false
      if !didShowReaderChromeHint {
        showsReaderChromeHint = true
      }
    } catch {
      loadError = error.localizedDescription
      isLoading = false
    }
  }
}

private struct ReadiumNavigatorHost: UIViewControllerRepresentable {
  let controller: UIViewController

  func makeUIViewController(context: Context) -> UIViewController {
    ReaderNavigatorContainerViewController(child: controller)
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// Füllt den gesamten Bildschirm aus (ohne zusätzliche Safe-Area-Reserve der SwiftUI-Hülle).
private final class ReaderNavigatorContainerViewController: UIViewController {
  private let childNavigator: UIViewController

  init(child: UIViewController) {
    childNavigator = child
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    addChild(childNavigator)
    childNavigator.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(childNavigator.view)
    NSLayoutConstraint.activate([
      childNavigator.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      childNavigator.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      childNavigator.view.topAnchor.constraint(equalTo: view.topAnchor),
      childNavigator.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    childNavigator.didMove(toParent: self)
  }

}

extension Notification.Name {
  static let readiumReaderToggleChrome = Notification.Name("abstand.readiumReaderToggleChrome")
  static let readiumReaderProgressDidChange = Notification.Name("abstand.readiumReaderProgressDidChange")
}

/// Springt zur Seite der aktuellen Hörposition und markiert die letzten Wörter — nur sichtbar, wenn das
/// Hörbuch im Player geladen ist.
private struct EbookNarrationJumpButton: View {
  @ObservedObject var controller: EbookNarrationJumpController
  // Blendet den Button mit dem Player-Zustand ein und aus.
  @EnvironmentObject private var player: PlaybackController

  var body: some View {
    if controller.isAvailable {
      Button {
        controller.jumpToNarration()
      } label: {
        Group {
          if controller.isBusy {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "headphones").font(.body)
          }
        }
        .frame(width: AppTheme.Layout.iconButtonSize, height: AppTheme.Layout.iconButtonSize)
      }
      .disabled(controller.isBusy)
      .accessibilityLabel("Go to audiobook position")
      .alert(
        "Can't jump to the audiobook position",
        isPresented: Binding(
          get: { controller.notice != nil },
          set: { if !$0 { controller.notice = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(controller.notice ?? "")
      }
    }
  }
}

// MARK: - Server-Position

struct ServerPositionOffer: Equatable {
  let serverFraction: Double
  let localFraction: Double
}

/// Unten im Reader: „Auf einem anderen Gerät weitergelesen" — zur Serverposition springen oder hier
/// bleiben. Der Server kennt nur einen Prozentwert, der Sprung ist deshalb ungefähr, nicht seitengenau.
/// Farben kommen vom Reader-Theme (wie beim Catch-up-Banner).
private struct EbookServerPositionBanner: View {
  @EnvironmentObject private var model: AppModel
  let offer: ServerPositionOffer
  let foreground: SwiftUI.Color
  let secondary: SwiftUI.Color
  let onStay: () -> Void
  let onContinue: () -> Void

  private func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded())) %" }

  var body: some View {
    VStack {
      Spacer()
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        HStack(alignment: .top, spacing: AppTheme.Layout.rowSpacing) {
          Image(systemName: "arrow.triangle.2.circlepath")
            .font(.subheadline)
            .foregroundStyle(model.appearanceAccentColor)
            .padding(.top, AppTheme.Layout.hairlineSpacing)
          VStack(alignment: .leading, spacing: AppTheme.Layout.tightSpacing) {
            Text("You've read further elsewhere")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(foreground)
            Text("Your synced position is at \(percent(offer.serverFraction)), this device is at \(percent(offer.localFraction)).")
              .font(.caption)
              .foregroundStyle(secondary)
          }
          Spacer(minLength: 0)
        }
        HStack(spacing: AppTheme.Layout.rowSpacing) {
          Button(action: onStay) {
            Text("Stay here")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(foreground)
              .frame(minHeight: AppTheme.Layout.minTapTarget)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          Spacer(minLength: 0)
          Button("Go to \(percent(offer.serverFraction))", action: onContinue)
            .buttonStyle(AbstandProminentButtonStyle())
        }
      }
      .padding(AppTheme.Layout.cardPadding)
      .background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: AppTheme.Layout.continueHeroCardCornerRadius, style: .continuous)
      )
      .padding(.horizontal, AppTheme.Layout.screenPadding)
      .padding(.bottom, AppTheme.Layout.blockSpacing)
    }
  }
}
