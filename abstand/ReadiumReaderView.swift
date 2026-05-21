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
}

struct ReadiumReaderView: View {
  let title: String
  let author: String
  let libraryItemId: String
  let localFileURL: URL
  let format: ABSEbookFormat
  @Environment(\.dismiss) private var dismiss
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
  @State private var isScrubbingProgress = false
  @State private var scrubProgress: Double = 0

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
    readerTheme == .dark ? AppTheme.textPrimary : .primary
  }

  private var readerChromeSecondary: SwiftUI.Color {
    readerTheme == .dark ? AppTheme.textSecondary : .secondary
  }

  var body: some View {
    ZStack {
      Group {
        if isLoading {
          ProgressView()
            .tint(AppTheme.accent)
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
      guard !isScrubbingProgress else { return }
      guard let locator = note.userInfo?[ReadiumReaderProgressInfo.locatorKey] as? Locator else { return }
      let pages = note.userInfo?[ReadiumReaderProgressInfo.bookPageProgressKey] as? BookPageProgress
      applyProgress(from: locator, bookPages: pages)
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
  }

  private var readerChromeOverlay: some View {
    VStack(spacing: 0) {
      if showReaderChrome {
        readerToolbar
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      Spacer()
    }
    .animation(.easeInOut(duration: 0.2), value: showReaderChrome)
  }

  private var readerToolbar: some View {
    VStack(alignment: .leading, spacing: 10) {
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
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(readerChromeForeground)

          Text(author)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(readerChromeSecondary)
        }

        Spacer(minLength: 0)
      }

      HStack(spacing: 0) {
        if format == .epub {
          HStack(spacing: 24) {
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

        Spacer(minLength: 20)

        HStack(spacing: 20) {
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
              .frame(width: 36, height: 36)
          }
          .accessibilityLabel("Continuous scroll")
          .accessibilityValue(continuousScroll ? "On" : "Off")

          Button {
            readerTheme = readerTheme.next()
            EpubReaderSettings.saveTheme(readerTheme)
            if format == .epub {
              applyEPUBPrefs()
            } else {
              applyPDFPrefs()
            }
          } label: {
            Image(systemName: readerTheme.nextThemeToolbarIcon)
              .font(.body)
              .frame(width: 36, height: 36)
          }
          .accessibilityLabel("Reading theme")
          .accessibilityValue(readerTheme.rawValue.capitalized)

          Button {
            confirmResetReadingPosition = true
          } label: {
            Image(systemName: "arrow.counterclockwise")
              .font(.body)
              .frame(width: 36, height: 36)
          }
          .disabled(readerActionInProgress)
          .accessibilityLabel("Reset position")
        }
      }
      .foregroundStyle(readerChromeForeground)

      readerProgressScrubber
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .safeAreaPadding(.top, 4)
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
      .tint(AppTheme.accent)
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

  private func applyPDFPrefs() {
    guard let pdfNavigator else { return }
    ReadiumReaderService.shared.applyPDFPreferences(to: pdfNavigator)
  }

  @MainActor
  private func resetReadingPosition() async {
    guard let navigator: Navigator = epubNavigator ?? pdfNavigator else { return }
    readerActionInProgress = true
    defer { readerActionInProgress = false }
    await ReadiumReaderService.shared.resetReadingPosition(
      navigator: navigator,
      libraryItemId: libraryItemId,
      format: format
    )
  }

  @MainActor
  private func loadNavigator() async {
    isLoading = true
    loadError = nil
    ReadiumReaderDelegate.shared.configure(libraryItemId: libraryItemId, format: format)
    do {
      let vc = try await ReadiumReaderService.shared.makeReader(
        localFileURL: localFileURL,
        libraryItemId: libraryItemId,
        format: format
      )
      navigatorController = vc
      epubNavigator = vc as? EPUBNavigatorViewController
      pdfNavigator = vc as? PDFNavigatorViewController
      if format == .epub, let epub = epubNavigator {
        if let current = epub.currentLocation {
          applyProgress(from: current)
        }
        await ReadiumReaderService.shared.refreshEpubProgressDisplay(epub: epub)
      } else if let current = pdfNavigator?.currentLocation {
        applyProgress(from: current)
      } else if let cached = EbookLocalStore.loadReadiumLocator(
        libraryItemId: libraryItemId, format: format)
      {
        applyProgress(from: cached)
      }
      isLoading = false
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

/// Badge für Hörbücher mit angehängter E-Book-/PDF-Datei.
struct EpubAvailableBadge: View {
  var body: some View {
    Image(systemName: "book.closed.fill")
      .font(.caption)
      .foregroundStyle(AppTheme.accent)
      .accessibilityLabel("eBook available")
  }
}
