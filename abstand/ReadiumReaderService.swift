import Foundation
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import UIKit

enum ReadiumReaderError: LocalizedError {
  case invalidFileURL
  case openFailed(String)
  case formatNotSupported

  var errorDescription: String? {
    switch self {
    case .invalidFileURL: return "The eBook file could not be opened."
    case let .openFailed(msg): return msg
    case .formatNotSupported: return "This file format is not supported."
    }
  }
}

/// Readium-Setup (Streamer + Navigator) für lokale EPUB/PDF-Dateien.
@MainActor
final class ReadiumReaderService {
  static let shared = ReadiumReaderService()

  private let httpClient = DefaultHTTPClient()
  private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
  private lazy var publicationOpener = PublicationOpener(
    parser: DefaultPublicationParser(
      httpClient: httpClient,
      assetRetriever: assetRetriever,
      pdfFactory: DefaultPDFDocumentFactory()
    )
  )

  /// Rand-Taps (links/zurück, rechts/weiter); muss stark gehalten werden.
  private var directionalNavigationAdapter: DirectionalNavigationAdapter?

  private init() {}

  func makeReader(
    localFileURL: URL,
    libraryItemId: String,
    format: ABSEbookFormat,
    resumeLocator: Locator? = nil,
    resumeProgression: Double? = nil
  ) async throws -> UIViewController {
    guard let absolute = FileURL(url: localFileURL) else {
      throw ReadiumReaderError.invalidFileURL
    }
    let asset: Asset
    switch await assetRetriever.retrieve(url: absolute) {
    case let .success(a): asset = a
    case let .failure(err):
      throw ReadiumReaderError.openFailed(err.localizedDescription)
    }
    let publication: Publication
    switch await publicationOpener.open(asset: asset, allowUserInteraction: false, sender: nil) {
    case let .success(pub): publication = pub
    case let .failure(err):
      throw ReadiumReaderError.openFailed(err.localizedDescription)
    }

    let positions = try? await publication.positions().get()
    ReadiumReaderDelegate.shared.setPositionCount(positions?.count)
    let locator = await resolveInitialLocator(
      publication: publication,
      positions: positions ?? [],
      resumeLocator: resumeLocator,
      resumeProgression: resumeProgression
    )

    if publication.conforms(to: .epub) {
      return try makeEPUBNavigator(publication: publication, locator: locator)
    }
    if publication.conforms(to: .pdf) {
      return try makePDFNavigator(publication: publication, locator: locator)
    }
    throw ReadiumReaderError.formatNotSupported
  }

  private func readiumTheme(from theme: EpubReaderTheme) -> Theme {
    switch theme {
    case .light: return .light
    case .sepia: return .sepia
    case .dark: return .dark
    }
  }

  private func makeEPUBPreferences() -> EPUBPreferences {
    EPUBPreferences(
      fontSize: EpubReaderSettings.loadFontSize(),
      publisherStyles: false,
      scroll: EpubReaderSettings.loadContinuousScroll(),
      theme: readiumTheme(from: EpubReaderSettings.loadTheme())
    )
  }

  private func makePDFPreferences() -> PDFPreferences {
    let theme = readiumTheme(from: EpubReaderSettings.loadTheme())
    let continuous = EpubReaderSettings.loadContinuousScroll()
    return PDFPreferences(
      backgroundColor: theme.backgroundColor,
      scroll: continuous,
      scrollAxis: continuous ? .vertical : nil
    )
  }

  private func makeEPUBNavigator(publication: Publication, locator: Locator?) throws -> UIViewController {
    let prefs = makeEPUBPreferences()
    var epubConfig = EPUBNavigatorViewController.Configuration(preferences: prefs)
    epubConfig.contentInset = [
      .compact: (top: 0, bottom: 0),
      .regular: (top: 0, bottom: 0),
    ]
    ReadiumReaderDelegate.shared.configureEPUBReadingOrder(publication.readingOrder)
    let navigator = try EPUBNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      config: epubConfig
    )
    navigator.delegate = ReadiumReaderDelegate.shared
    updateDirectionalNavigation(for: navigator, scrollEnabled: EpubReaderSettings.loadContinuousScroll())
    return navigator
  }

  private func makePDFNavigator(publication: Publication, locator: Locator?) throws -> UIViewController {
    let prefs = makePDFPreferences()
    let navigator = try PDFNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      config: PDFNavigatorViewController.Configuration(preferences: prefs)
    )
    navigator.delegate = ReadiumReaderDelegate.shared
    updateDirectionalNavigation(for: navigator, scrollEnabled: EpubReaderSettings.loadContinuousScroll())
    return navigator
  }

  private func updateDirectionalNavigation(for navigator: VisualNavigator, scrollEnabled: Bool) {
    if scrollEnabled {
      directionalNavigationAdapter?.unbind()
      directionalNavigationAdapter = nil
    } else {
      bindEdgeTapNavigation(to: navigator)
    }
  }

  /// Links/rechts am Bildrand tippen → Seite zurück/vor (LTR: links=zurück, rechts=weiter).
  private func bindEdgeTapNavigation(to navigator: VisualNavigator) {
    directionalNavigationAdapter?.unbind()
    let adapter = DirectionalNavigationAdapter(
      pointerPolicy: DirectionalNavigationAdapter.PointerPolicy(
        types: [.touch],
        edges: .horizontal,
        ignoreWhileScrolling: false
      ),
      animatedTransition: true
    )
    adapter.bind(to: navigator)
    directionalNavigationAdapter = adapter
  }

  func applyPDFPreferences(to navigator: PDFNavigatorViewController) {
    navigator.submitPreferences(makePDFPreferences())
    updateDirectionalNavigation(for: navigator, scrollEnabled: EpubReaderSettings.loadContinuousScroll())
  }

  func applyEPUBPreferences(to navigator: EPUBNavigatorViewController) {
    ReadiumReaderDelegate.shared.invalidateChapterPageCache()
    navigator.submitPreferences(makeEPUBPreferences())
    updateDirectionalNavigation(for: navigator, scrollEnabled: EpubReaderSettings.loadContinuousScroll())
    Task { await refreshEpubProgressDisplay(epub: navigator) }
  }

  /// Nach Layout-Umbruch (Schriftgröße, Theme): Fortschritt inkl. gerenderte Seitenzahl aktualisieren.
  func refreshEpubProgressDisplay(epub: EPUBNavigatorViewController) async {
    try? await Task.sleep(nanoseconds: 450_000_000)
    guard let locator = epub.currentLocation else { return }
    await publishProgressUpdate(locator: locator, format: .epub, epub: epub)
  }

  func publishProgressUpdate(
    locator: Locator,
    format: ABSEbookFormat,
    epub: EPUBNavigatorViewController? = nil
  ) async {
    var userInfo: [String: Any] = [ReadiumReaderProgressInfo.locatorKey: locator]
    if format == .epub, let epub {
      if let chapterPages = await fetchRenderedPageInfo(from: epub) {
        let bookPages = ReadiumReaderDelegate.shared.bookWidePageProgress(
          locator: locator, chapterPages: chapterPages)
        userInfo[ReadiumReaderProgressInfo.bookPageProgressKey] = bookPages
        persistPageProgress(locator: locator, format: format, bookPages: bookPages)
      }
    } else {
      persistPageProgress(locator: locator, format: format, bookPages: nil)
    }
    NotificationCenter.default.post(
      name: .readiumReaderProgressDidChange,
      object: nil,
      userInfo: userInfo
    )
  }

  /// Kapitelindex (readingOrder) für die aktuelle Locator-URL; für Ebook-Sync-Markup.
  func chapterIndex(for locator: Locator?) -> Int? {
    ReadiumReaderDelegate.shared.chapterIndex(for: locator)
  }

  /// Installiert Sync-Spans/CSS im sichtbaren EPUB-Dokument.
  @MainActor
  @discardableResult
  func installEbookSyncMarkup(
    on navigator: EPUBNavigatorViewController,
    chapterIndex: Int
  ) async -> Bool {
    let script = EbookSyncHighlightBridge.installMarkupScript(chapterIndex: chapterIndex)
    switch await navigator.evaluateJavaScript(script) {
    case let .success(value):
      if let dict = value as? [String: Any], let count = dict["count"] as? Int {
        return count > 0
      }
      if let dict = value as? [String: Any], let count = dict["count"] as? NSNumber {
        return count.intValue > 0
      }
      return true
    case .failure: return false
    }
  }

  /// Ob Sync-Spans für das Kapitel noch im aktuellen DOM liegen.
  @MainActor
  func ebookSyncMarkupInstalled(
    on navigator: EPUBNavigatorViewController,
    chapterIndex: Int
  ) async -> Bool {
    let script = """
    (function() {
      if (window.__absSyncInstalled !== \(chapterIndex)) return false;
      return document.querySelectorAll('span.abs-sync-sentence').length > 0;
    })();
    """
    switch await navigator.evaluateJavaScript(script) {
    case let .success(value):
      if let flag = value as? Bool { return flag }
      if let num = value as? NSNumber { return num.boolValue }
      return false
    case .failure:
      return false
    }
  }

  @MainActor
  @discardableResult
  func applyEbookSyncHighlight(
    on navigator: EPUBNavigatorViewController,
    sentenceId: String?,
    wordIndex: Int?,
    sentenceText: String? = nil,
    scrollIntoView: Bool = true
  ) async -> Bool {
    let script = EbookSyncHighlightBridge.highlightScript(
      sentenceId: sentenceId,
      wordIndex: wordIndex,
      sentenceText: sentenceText,
      scrollIntoView: scrollIntoView
    )
    switch await navigator.evaluateJavaScript(script) {
    case let .success(value):
      if let flag = value as? Bool { return flag }
      if let num = value as? NSNumber { return num.boolValue }
      return sentenceId != nil
    case .failure:
      return false
    }
  }

  @MainActor
  func bindEbookSyncTapHandler(on navigator: EPUBNavigatorViewController) async {
    _ = await navigator.evaluateJavaScript(EbookSyncHighlightBridge.tappedSentenceIdScript())
  }

  @MainActor
  func consumeEbookSyncTap(on navigator: EPUBNavigatorViewController) async -> String? {
    switch await navigator.evaluateJavaScript(EbookSyncHighlightBridge.consumeTapScript()) {
    case let .success(value):
      if let s = value as? String, !s.isEmpty { return s }
      return nil
    case .failure:
      return nil
    }
  }

  /// Springt zum Kapitel der Alignment-Sentence (href) und lässt den Sync das Highlight setzen.
  @MainActor
  @discardableResult
  func seekToEbookSyncHref(
    navigator: EPUBNavigatorViewController,
    href: String
  ) async -> Bool {
    let key = EbookTextExtractor.hrefKey(href)
    guard let link = navigator.publication.readingOrder.first(where: {
      EbookTextExtractor.hrefKey($0.url().string) == key
    }) else {
      return false
    }
    return await navigator.go(to: link)
  }

  /// Paginierte EPUB-Ansicht: tatsächliche Spalten/Seiten im aktuellen Abschnitt (reagiert auf Schriftgröße).
  private func fetchRenderedPageInfo(from navigator: EPUBNavigatorViewController) async -> RenderedPageInfo? {
    let script = """
    (function() {
      var root = document.scrollingElement;
      if (!root) return null;
      var vw = window.innerWidth, vh = window.innerHeight;
      if (vw <= 0 || vh <= 0) return null;
      var vertical = root.scrollHeight > root.clientHeight * 1.25;
      var total, cur;
      if (vertical) {
        total = Math.max(1, Math.ceil(root.scrollHeight / vh));
        cur = Math.min(total, Math.max(1, Math.floor((window.scrollY + vh * 0.5) / vh)));
      } else {
        total = Math.max(1, Math.ceil(root.scrollWidth / vw));
        var x = Math.abs(window.scrollX);
        cur = Math.min(total, Math.max(1, Math.floor(x / vw) + 1));
      }
      return { current: cur, total: total };
    })();
    """
    switch await navigator.evaluateJavaScript(script) {
    case let .success(value):
      guard let dict = value as? [String: Any] else { return nil }
      guard let current = jsInt(dict["current"]), let total = jsInt(dict["total"]), total > 0 else {
        return nil
      }
      return RenderedPageInfo(current: min(max(1, current), total), total: total)
    case .failure:
      return nil
    }
  }

  private func jsInt(_ value: Any?) -> Int? {
    if let i = value as? Int { return i }
    if let n = value as? NSNumber { return n.intValue }
    return nil
  }

  private func persistPageProgress(
    locator: Locator, format: ABSEbookFormat, bookPages: BookPageProgress?
  ) {
    guard let libraryItemId = ReadiumReaderDelegate.shared.resolvedLibraryItemId else { return }
    EbookLocalStore.saveReadiumLocator(locator, libraryItemId: libraryItemId, format: format)
    if let bookPages {
      EbookLocalStore.savePageProgress(
        current: bookPages.current,
        total: bookPages.total,
        libraryItemId: libraryItemId,
        format: format
      )
    }
  }

  /// Lesezeichen löschen und zum Anfang springen.
  @MainActor
  func resetReadingPosition(
    navigator: Navigator,
    libraryItemId: String,
    format: ABSEbookFormat
  ) async {
    _ = libraryItemId
    _ = format
    guard let locator = await startLocator(for: navigator.publication) else { return }
    _ = await navigator.go(to: locator)
    await publishProgressAfterNavigation(navigator: navigator, format: format)
  }

  /// Start-Locator: zuerst gespeicherter Readium-Stand, sonst Server-/Hilfs-Prozent.
  private func resolveInitialLocator(
    publication: Publication,
    positions: [Locator],
    resumeLocator: Locator?,
    resumeProgression: Double?
  ) async -> Locator? {
    if let saved = resumeLocator {
      if let located = await publication.locate(saved) {
        return located
      }
      return saved
    }
    guard let raw = resumeProgression, raw > 0.005, raw < 0.995 else { return nil }
    let fraction = min(1, max(0, raw))
    if let located = await publication.locate(progression: fraction) {
      return located
    }
    guard positions.count > 1 else { return positions.first }
    let index = min(positions.count - 1, max(0, Int((fraction * Double(positions.count - 1)).rounded())))
    return positions[index]
  }

  /// Springt zu einer Stelle im Buch (0…1 Gesamtfortschritt), z. B. per Fortschritts-Slider.
  @MainActor
  @discardableResult
  func seekToProgression(
    navigator: Navigator,
    libraryItemId: String,
    format: ABSEbookFormat,
    progression: Double,
    maxAttempts: Int = 6
  ) async -> Bool {
    let fraction = min(1, max(0, progression))
    _ = libraryItemId
    for attempt in 0 ..< maxAttempts {
      if let locator = await navigator.publication.locate(progression: fraction) {
        if await navigator.go(to: locator) {
          await publishProgressAfterNavigation(navigator: navigator, format: format)
          return true
        }
      }
      if attempt < maxAttempts - 1 {
        try? await Task.sleep(nanoseconds: UInt64(100_000_000 + attempt * 100_000_000))
      }
    }
    return false
  }

  private func publishProgressAfterNavigation(navigator: Navigator, format: ABSEbookFormat) async {
    guard let locator = navigator.currentLocation else { return }
    if format == .epub, let epub = navigator as? EPUBNavigatorViewController {
      await publishProgressUpdate(locator: locator, format: .epub, epub: epub)
    } else {
      await publishProgressUpdate(locator: locator, format: format, epub: nil)
    }
  }

  private func startLocator(for publication: Publication) async -> Locator? {
    if case let .success(positions) = await publication.positions(), let first = positions.first {
      return first
    }
    guard let link = publication.readingOrder.first else { return nil }
    return locator(for: link, locations: Locator.Locations())
  }

  private func locator(for link: Link, locations: Locator.Locations) -> Locator? {
    Locator(
      href: link.url(),
      mediaType: link.mediaType ?? MediaType.html,
      locations: locations
    )
  }
}

@MainActor
final class ReadiumReaderDelegate: NSObject, EPUBNavigatorDelegate, PDFNavigatorDelegate {
  static let shared = ReadiumReaderDelegate()

  private var libraryItemId: String?
  private var format: ABSEbookFormat?

  private var positionCount: Int?

  /// Lese-Reihenfolge (ein Eintrag ≈ Kapitel/Ressource) für buchweite Seitenschätzung.
  private var epubReadingOrderHrefs: [String] = []
  /// Gerenderte Seitenzahl pro Kapitel (aktueller Schriftgrad); wird bei Font-Änderung geleert.
  private var chapterPageTotalsByHref: [String: Int] = [:]

  func configure(libraryItemId: String, format: ABSEbookFormat) {
    self.libraryItemId = libraryItemId
    self.format = format
  }

  func configureEPUBReadingOrder(_ links: [Link]) {
    epubReadingOrderHrefs = links.map { hrefKey($0.url()) }
    chapterPageTotalsByHref.removeAll()
  }

  func invalidateChapterPageCache() {
    chapterPageTotalsByHref.removeAll()
  }

  func setPositionCount(_ count: Int?) {
    positionCount = count
  }

  var positionCountForDisplay: Int? {
    positionCount
  }

  var resolvedLibraryItemId: String? {
    libraryItemId
  }

  func chapterIndex(for locator: Locator?) -> Int? {
    guard let locator else { return nil }
    let key = hrefKey(locator.href)
    return epubReadingOrderHrefs.firstIndex(of: key)
  }

  private func hrefKey(_ href: AnyURL) -> String {
    let s = href.string
    if let hash = s.firstIndex(of: "#") {
      return String(s[..<hash])
    }
    return s
  }

  /// Aus Kapitel-Paginierung (JS) + Cache aller besuchten Kapitel → Buch gesamt.
  func bookWidePageProgress(locator: Locator, chapterPages: RenderedPageInfo) -> BookPageProgress {
    let key = hrefKey(locator.href)
    chapterPageTotalsByHref[key] = chapterPages.total

    let percent = Int((ReadiumReaderProgressInfo.fraction(from: locator) * 100).rounded())
    guard !epubReadingOrderHrefs.isEmpty, let chapterIndex = epubReadingOrderHrefs.firstIndex(of: key) else {
      return BookPageProgress(current: chapterPages.current, total: chapterPages.total, percent: percent)
    }

    let knownTotals = epubReadingOrderHrefs.compactMap { chapterPageTotalsByHref[$0] }
    let averageChapterPages = max(
      1,
      knownTotals.isEmpty ? chapterPages.total : knownTotals.reduce(0, +) / knownTotals.count
    )

    var bookTotal = 0
    for href in epubReadingOrderHrefs {
      bookTotal += chapterPageTotalsByHref[href] ?? averageChapterPages
    }
    bookTotal = max(1, bookTotal)

    let pagesBefore = epubReadingOrderHrefs.prefix(chapterIndex).compactMap { chapterPageTotalsByHref[$0] }
      .reduce(0, +)
    let fromChapter = pagesBefore + chapterPages.current
    let fromProgression = Int((ReadiumReaderProgressInfo.fraction(from: locator) * Double(bookTotal)).rounded())
    let bookCurrent = min(bookTotal, max(1, max(fromChapter, fromProgression)))

    return BookPageProgress(current: bookCurrent, total: bookTotal, percent: percent)
  }

  func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    guard let format else { return }
    if let libraryItemId {
      let fraction = ReadiumReaderProgressInfo.fraction(from: locator)
      if fraction > 0.001 {
        EbookLocalStore.saveProgressFraction(fraction, libraryItemId: libraryItemId)
      }
      EbookLocalStore.saveReadiumLocator(locator, libraryItemId: libraryItemId, format: format)
    }
    if format == .epub, let epub = navigator as? EPUBNavigatorViewController {
      Task {
        await ReadiumReaderService.shared.publishProgressUpdate(
          locator: locator, format: .epub, epub: epub)
      }
    } else {
      NotificationCenter.default.post(
        name: .readiumReaderProgressDidChange,
        object: nil,
        userInfo: [ReadiumReaderProgressInfo.locatorKey: locator]
      )
    }
  }

  func navigator(_ navigator: VisualNavigator, presentationDidChange presentation: VisualNavigatorPresentation) {
    guard format == .epub, let epub = navigator as? EPUBNavigatorViewController else { return }
    invalidateChapterPageCache()
    Task { await ReadiumReaderService.shared.refreshEpubProgressDisplay(epub: epub) }
  }

  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}

  func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
    let width = navigator.view.bounds.width
    let edge = max(80, width * 0.3)
    if point.x > edge, point.x < width - edge {
      NotificationCenter.default.post(name: .readiumReaderToggleChrome, object: nil)
    }
  }

  /// Nur Geräte-Notch/Home-Indicator — keine zusätzlichen Leser-Ränder.
  func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
    let safe = navigator.view.window?.safeAreaInsets ?? navigator.view.safeAreaInsets
    return UIEdgeInsets(top: safe.top, left: 0, bottom: safe.bottom, right: 0)
  }
}

struct RenderedPageInfo: Equatable {
  let current: Int
  let total: Int
}

struct BookPageProgress: Equatable {
  let current: Int
  let total: Int
  let percent: Int
}

enum ReadiumReaderProgressInfo {
  static let locatorKey = "locator"
  static let bookPageProgressKey = "bookPageProgress"

  static func fraction(from locator: Locator) -> Double {
    if let total = locator.locations.totalProgression {
      return min(1, max(0, total))
    }
    if let local = locator.locations.progression {
      return min(1, max(0, local))
    }
    return 0
  }

  static func label(
    from locator: Locator,
    format: ABSEbookFormat,
    positionCount: Int?,
    bookPages: BookPageProgress?
  ) -> String {
    let pct = Int((fraction(from: locator) * 100).rounded())
    switch format {
    case .epub:
      if let bookPages {
        return "Page \(bookPages.current) of \(bookPages.total) · \(bookPages.percent)%"
      }
      return "\(pct)%"
    case .pdf:
      if let position = locator.locations.position, let total = positionCount, total > 0 {
        return "Page \(position) of \(total)"
      }
      return "\(pct) %"
    }
  }
}
