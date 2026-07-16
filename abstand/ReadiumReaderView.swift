import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

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
          ProgressView()
            .tint(themeAccent)
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

      if showsReaderChromeHint {
        readerChromeHint
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
    }
    .onReceive(NotificationCenter.default.publisher(for: .readiumReaderProgressDidChange)) { note in
      guard !isScrubbingProgress, !isInitialReaderLoad else { return }
      guard let locator = note.userInfo?[ReadiumReaderProgressInfo.locatorKey] as? Locator else { return }
      let pages = note.userInfo?[ReadiumReaderProgressInfo.bookPageProgressKey] as? BookPageProgress
      applyProgress(from: locator, bookPages: pages)
      model.scheduleEbookProgressSync(
        libraryItemId: libraryItemId,
        fraction: ReadiumReaderProgressInfo.fraction(from: locator)
      )
    }
    .task(id: localFileURL.path) {
      fontSize = EpubReaderSettings.loadFontSize()
      continuousScroll = EpubReaderSettings.loadContinuousScroll()
      await loadNavigator()
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
    HStack(spacing: 12) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title2)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(readerChromeForeground)
      }
      .accessibilityLabel("Close")

      VStack(alignment: .leading, spacing: 2) {
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
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .safeAreaPadding(.top, 4)
  }

  /// Primäre Lesesteuerung bewusst am unteren Bildschirmrand für einhändige Bedienung.
  private var readerBottomChrome: some View {
    VStack(alignment: .leading, spacing: 10) {
      readerProgressScrubber

      HStack(spacing: 12) {
        if format == .epub {
          HStack(spacing: 8) {
            Button {
              fontSize = max(EpubReaderSettings.minFontSize, fontSize - EpubReaderSettings.fontSizeStep)
              EpubReaderSettings.saveFontSize(fontSize)
              applyEPUBPrefs()
            } label: {
              Image(systemName: "textformat.size.smaller")
                .font(.body)
                .frame(width: 36, height: 36)
            }
            .disabled(fontSize <= EpubReaderSettings.minFontSize)

            Button {
              fontSize = min(EpubReaderSettings.maxFontSize, fontSize + EpubReaderSettings.fontSizeStep)
              EpubReaderSettings.saveFontSize(fontSize)
              applyEPUBPrefs()
            } label: {
              Image(systemName: "textformat.size.larger")
                .font(.body)
                .frame(width: 36, height: 36)
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
            .frame(width: 40, height: 40)
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
            .frame(width: 40, height: 40)
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
            .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Reader options")
      }
      .foregroundStyle(readerChromeForeground)
      .tint(readerChromeForeground)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .safeAreaPadding(.bottom, 4)
  }

  /// Dezente Orientierung auch bei ausgeblendeter Steuerung, ohne den Lesefluss zu stören.
  private var readerPassiveProgressIndicator: some View {
    GeometryReader { geo in
      Rectangle()
        .fill(themeAccent.opacity(0.75))
        .frame(width: geo.size.width * min(1, max(0, readProgress)), height: 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 3)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var readerChromeHint: some View {
    VStack {
      Spacer()
      VStack(spacing: 10) {
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
        .buttonStyle(.borderedProminent)
        .tint(themeAccent)
      }
      .padding(20)
      .frame(maxWidth: 320)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .padding(.bottom, 44)
    }
    .padding(.horizontal, 24)
  }

  private var readerProgressScrubber: some View {
    VStack(alignment: .leading, spacing: 4) {
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
        if let current = epub.currentLocation {
          applyProgress(from: current)
        }
        await ReadiumReaderService.shared.refreshEpubProgressDisplay(epub: epub)
      } else if let current = pdfNavigator?.currentLocation {
        applyProgress(from: current)
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
