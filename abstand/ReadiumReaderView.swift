import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

private enum ReaderChromeMetrics {
  /// Höhe des dünnen passiven Lesefortschrittsbalkens.
  static let passiveProgressBarHeight: CGFloat = 3
  /// So weit (Anteil im Kapitel) muss der Nutzer blättern, damit das Server-Angebot als abgelehnt gilt.
  static let serverOfferDeclineProgression = 0.002
}

/// Paper-Look im Reader: Hell = Papier mit Tinte, Dunkel = Tinte mit Papier-Schrift (dieselben festen
/// Paletten wie die App), Sepia bleibt Readiums Sepia mit Tinten-Schrift. Seite und Leisten teilen die Farben.
extension EpubReaderTheme {
  var palette: AppColorPalette {
    AppColorPalette.derived(from: .clear, isDarkLike: self == .dark)
  }

  var pageBackground: SwiftUI.Color {
    self == .sepia ? SwiftUI.Color(uiColor: Theme.sepia.backgroundColor.uiColor) : palette.background
  }

  var pageBackgroundUIColor: UIColor { UIColor(pageBackground) }
  var pageTextUIColor: UIColor { UIColor(palette.textPrimary) }
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
  /// Beim ersten Öffnen stehen die Leisten offen, mit einer Zeile, wie man sie aus- und einblendet.
  @AppStorage("abstand_ebook_reader_chrome_hint_seen") private var didShowReaderChromeHint = false
  @State private var showsReaderChromeHint = false
  /// Verhindert Sync mit Anfangs-Locator, bevor Server-Resume oder gespeicherte Position gilt.
  @State private var isInitialReaderLoad = true
  /// Sprung zur Hörposition (nur EPUB, nur wenn dieses Hörbuch im Player geladen ist).
  @State private var narrationJump: EbookNarrationJumpController?
  /// Server steht deutlich weiter als der lokale Locator (z. B. auf einem anderen Gerät gelesen):
  /// Button in der unteren Leiste statt stillem Überschreiben. Solange das Angebot offen ist, geht kein
  /// Fortschritt zum Server; es endet mit dem Sprung oder sobald der Nutzer hier weiterblättert.
  @State private var serverPositionOffer: ServerPositionOffer?

  /// So viel weiter (Anteil am Buch) muss der Server sein, damit das Angebot erscheint.
  private static let serverPositionOfferThreshold = 0.02

  private var chromeColorScheme: ColorScheme {
    readerTheme == .dark ? .dark : .light
  }

  private var readerBackground: SwiftUI.Color { readerTheme.pageBackground }

  private var readerChromeForeground: SwiftUI.Color { readerTheme.palette.textPrimary }

  private var readerChromeSecondary: SwiftUI.Color { readerTheme.palette.textSecondary }

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
          .allowsHitTesting(showReaderChrome || narrationJump != nil)
      }

    }
    .background(readerBackground)
    .preferredColorScheme(chromeColorScheme)
    .statusBarHidden(!showReaderChrome)
    .persistentSystemOverlays(showReaderChrome ? .automatic : .hidden)
    .onReceive(NotificationCenter.default.publisher(for: .readiumReaderToggleChrome)) { _ in
      withAnimation(.easeInOut(duration: 0.2)) {
        showReaderChrome.toggle()
      }
      if showsReaderChromeHint {
        didShowReaderChromeHint = true
        showsReaderChromeHint = false
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .readiumReaderProgressDidChange)) { note in
      guard !isScrubbingProgress, !isInitialReaderLoad else { return }
      guard let locator = note.userInfo?[ReadiumReaderProgressInfo.locatorKey] as? Locator else { return }
      let pages = note.userInfo?[ReadiumReaderProgressInfo.bookPageProgressKey] as? BookPageProgress
      applyProgress(from: locator, bookPages: pages)
      narrationJump?.readerLocationDidChange()
      if format == .epub, let epubNavigator {
        Task { await EbookReadingAnchorStore.capture(from: epubNavigator, locator: locator, libraryItemId: libraryItemId) }
      }
      // Offenes Server-Angebot: der (ältere) lokale Stand darf den Server nicht überschreiben — erst
      // wenn der Nutzer hier selbst weiterblättert, gilt das Angebot als abgelehnt.
      if let offer = serverPositionOffer {
        guard offer.isLeft(by: locator) else { return }
        withAnimation(.snappy(duration: 0.25)) { serverPositionOffer = nil }
      }
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
    // Ganz außen, hinter allen `.alert`: Alert-Buttons (Reset position, Mark as finished, Fehler)
    // erben den Tint der Ansicht, an der sie hängen — davor bliebe „Cancel" in der App-Akzentfarbe.
    .tint(readerChromeForeground)
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
        // Sprung zur Hörposition bleibt auch bei ausgeblendeten Leisten erreichbar.
        if let narrationJump {
          EbookNarrationJumpButton(controller: narrationJump, palette: readerTheme.palette, compact: true)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.bottom, AppTheme.Layout.inlineSpacing)
            .transition(.opacity)
        }
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
        Image(systemName: "xmark")
          .font(.body.weight(.semibold))
          .frame(width: AppTheme.Layout.iconButtonSize, height: AppTheme.Layout.iconButtonSize)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(readerChromeForeground)
      .accessibilityLabel("Close")

      VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
        Text(title)
          .font(.headline)
          .fontDesign(AppTheme.Typography.titleDesign)
          .lineLimit(1)
          .foregroundStyle(readerChromeForeground)

        Text(author)
          .font(.caption)
          .lineLimit(1)
          .foregroundStyle(readerChromeSecondary)
      }

      Spacer(minLength: 0)
    }
    .padding(.leading, AppTheme.Layout.inlineSpacing)
    .padding(.trailing, AppTheme.Layout.screenPadding)
    .padding(.vertical, AppTheme.Layout.tightSpacing)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(alignment: .bottom) { readerChromeRule }
    .background(readerBackground.ignoresSafeArea(edges: .top))
  }

  /// Haarlinie zwischen Leiste und Seite (Paper-Look: Linie statt Material/Schatten).
  private var readerChromeRule: some View {
    Rectangle()
      .fill(readerTheme.palette.rule)
      .frame(height: AppTheme.Layout.hairlineWidth)
  }

  /// Sprünge nur auf Knopfdruck: zur Hörposition (Hörbuch im Player) und zur synchronisierten Position.
  @ViewBuilder
  private var readerJumpRow: some View {
    let showsNarration = narrationJump != nil
    if showsNarration || serverPositionOffer != nil {
      HStack(spacing: AppTheme.Layout.inlineSpacing) {
        if let narrationJump {
          EbookNarrationJumpButton(controller: narrationJump, palette: readerTheme.palette)
        }
        if let offer = serverPositionOffer {
          Button {
            withAnimation(.snappy(duration: 0.25)) { serverPositionOffer = nil }
            Task { await seekToProgression(offer.serverFraction) }
          } label: {
            Label("Synced · \(offer.serverPercent)", systemImage: "arrow.triangle.2.circlepath")
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
          }
          .buttonStyle(AbstandProminentButtonStyle(palette: readerTheme.palette))
          .accessibilityLabel("Go to synced position, \(offer.serverPercent)")
          .accessibilityHint("You've read further on another device. This device is at \(offer.localPercent).")
        }
        Spacer(minLength: 0)
      }
    }
  }

  /// Primäre Lesesteuerung bewusst am unteren Bildschirmrand für einhändige Bedienung.
  private var readerBottomChrome: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      if showsReaderChromeHint {
        Text("Tap the middle of the page to hide or show these controls.")
          .font(.footnote)
          .foregroundStyle(readerChromeSecondary)
      }

      readerJumpRow

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
          Image(systemName: "ellipsis")
            .font(.body)
            .frame(width: AppTheme.Layout.iconButtonSize, height: AppTheme.Layout.iconButtonSize)
        }
        .accessibilityLabel("Reader options")
      }
      .buttonStyle(.plain)
      .foregroundStyle(readerChromeForeground)
      .tint(readerChromeForeground)
    }
    .padding(.horizontal, AppTheme.Layout.screenPadding)
    .padding(.top, AppTheme.Layout.rowSpacing)
    .padding(.bottom, AppTheme.Layout.tightSpacing)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(alignment: .top) { readerChromeRule }
    .background(readerBackground.ignoresSafeArea(edges: .bottom))
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
          serverPositionOffer = ServerPositionOffer(serverFraction: server, localFraction: local, origin: saved)
        }
      }
      if let epub = epubNavigator, let current = epub.currentLocation {
        await EbookReadingAnchorStore.capture(from: epub, locator: current, libraryItemId: libraryItemId)
      }
      isLoading = false
      // Erstes Öffnen oder offenes Server-Angebot: Leisten zeigen statt eines Popups.
      if !didShowReaderChromeHint { showsReaderChromeHint = true }
      if showsReaderChromeHint || serverPositionOffer != nil { showReaderChrome = true }
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
  let palette: AppColorPalette
  /// Nur das Symbol als runde Kapsel — schwebend über der Seite, wenn die Leisten ausgeblendet sind.
  var compact = false
  // Blendet den Button mit dem Player-Zustand ein und aus.
  @EnvironmentObject private var player: PlaybackController

  var body: some View {
    if controller.isAvailable {
      Button {
        controller.jumpToNarration()
      } label: {
        HStack(spacing: AppTheme.Layout.compactSpacing) {
          if controller.isBusy {
            ProgressView().controlSize(.small).tint(palette.background)
          } else {
            Image(systemName: "headphones")
          }
          if !compact { Text("Audiobook position") }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .frame(
          width: compact ? AppTheme.Layout.compactIconButtonSize : nil,
          height: compact ? AppTheme.Layout.compactIconButtonSize : nil)
      }
      .buttonStyle(AbstandProminentButtonStyle(capsule: compact, palette: palette))
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

/// Server steht weiter als dieses Gerät. Der Server kennt nur einen Prozentwert — der Sprung ist
/// deshalb ungefähr, nicht seitengenau.
struct ServerPositionOffer: Equatable {
  let serverFraction: Double
  let localFraction: Double
  /// Locator beim Öffnen — blättert der Nutzer davon weg, bleibt er bewusst hier.
  let origin: Locator

  var serverPercent: String { Self.percent(serverFraction) }
  var localPercent: String { Self.percent(localFraction) }

  func isLeft(by locator: Locator) -> Bool {
    guard locator.href.string == origin.href.string else { return true }
    let delta = abs((locator.locations.progression ?? 0) - (origin.locations.progression ?? 0))
    return delta > ReaderChromeMetrics.serverOfferDeclineProgression
  }

  private static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded())) %" }
}
