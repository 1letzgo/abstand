import SwiftUI
import UIKit

// MARK: - Zoom-Quelle (Mini-Player im Tab-Zubehör)

/// Die UIView, aus der der Vollbild-Player per Zoom wächst und in die er beim Schließen zurückschrumpft.
/// Weak: verschwindet das Tab-Zubehör, fällt UIKit auf die Standard-Transition zurück.
@MainActor
enum NowPlayingZoomSource {
  static weak var view: UIView?
}

/// Unsichtbarer Anker hinter dem Mini-Player-Inhalt — liefert UIKit die Quell-View der Zoom-Transition.
struct NowPlayingZoomSourceAnchor: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    NowPlayingZoomSource.view = view
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    NowPlayingZoomSource.view = uiView
  }
}

// MARK: - Präsentation

/// Präsentiert den Vollbild-Player per UIKit mit `preferredTransition = .zoom` aus dem Mini-Player.
///
/// Warum UIKit statt `.fullScreenCover` + `.navigationTransition(.zoom)`: Die SwiftUI-Variante bietet keine
/// Optionen. Über `ZoomOptions` steuern wir hier, (1) wann das Herunterziehen das Schließen startet
/// (`interactiveDismissShouldBegin` — vorher erkannte der System-Default die Geste nicht zuverlässig)
/// und (2) welcher Bereich des Players auf den Mini-Player ausgerichtet wird (`alignmentRectProvider` —
/// nur das obere Band statt der ganzen Karte, sonst „schnappte“ der Player beim Schließen unsauber ein).
///
/// Der Hosting-Controller wird wiederverwendet: der SwiftUI-Baum des Players muss so nicht bei jedem
/// Öffnen neu aufgebaut werden (sonst >100 ms Main-Thread genau zum Animationsstart).
/// Er liegt außerhalb des SwiftUI-Baums — benötigte `EnvironmentObject`s im Content-Closure setzen.
struct NowPlayingZoomPresenter<OverlayContent: View>: UIViewControllerRepresentable {
  @Binding var isPresented: Bool
  /// Nach abgeschlossener Dismiss-Animation — für Aufräumarbeiten, die währenddessen ruckeln.
  var onDismissCompleted: (() -> Void)?
  @ViewBuilder var overlayContent: () -> OverlayContent

  func makeUIViewController(context: Context) -> UIViewController {
    UIViewController()
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    context.coordinator.isPresented = $isPresented
    context.coordinator.onDismissCompleted = onDismissCompleted
    if isPresented {
      context.coordinator.present(overlayContent(), from: uiViewController)
    } else {
      context.coordinator.dismiss()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(isPresented: $isPresented, onDismissCompleted: onDismissCompleted)
  }

  /// Meldet das Ende jeder Dismissal — auch der interaktiven per Zoom-Geste, die nicht über unseren
  /// `dismiss()`-Aufruf läuft.
  final class HostingController: UIHostingController<OverlayContent> {
    var onDidDisappear: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)
      // Abgebrochene interaktive Dismissal: Controller bleibt präsentiert.
      guard presentingViewController == nil else { return }
      onDidDisappear?()
    }
  }

  @MainActor
  final class Coordinator: NSObject {
    var isPresented: Binding<Bool>
    var onDismissCompleted: (() -> Void)?
    private var host: HostingController?
    private var isTransitioning = false

    init(isPresented: Binding<Bool>, onDismissCompleted: (() -> Void)?) {
      self.isPresented = isPresented
      self.onDismissCompleted = onDismissCompleted
    }

    func present(_ content: OverlayContent, from anchor: UIViewController) {
      let host = self.host ?? makeHost(content)
      host.rootView = content
      guard host.presentingViewController == nil, !isTransitioning,
        let presenter = topmostPresenter(from: anchor)
      else { return }
      isTransitioning = true
      presenter.present(host, animated: true) { [weak self] in
        self?.isTransitioning = false
      }
    }

    func dismiss() {
      guard let host, host.presentingViewController != nil, !host.isBeingDismissed else { return }
      host.dismiss(animated: true)
    }

    private func makeHost(_ content: OverlayContent) -> HostingController {
      let host = HostingController(rootView: content)
      host.modalPresentationStyle = .overFullScreen
      host.view.backgroundColor = .clear
      // `.overFullScreen` lässt die präsentierende View aktiv — VoiceOver soll sie nicht erreichen.
      host.view.accessibilityViewIsModal = true
      host.preferredTransition = .zoom(options: Self.zoomOptions(for: host)) { _ in
        NowPlayingZoomSource.view
      }
      host.onDidDisappear = { [weak self] in
        guard let self else { return }
        self.isTransitioning = false
        if self.isPresented.wrappedValue { self.isPresented.wrappedValue = false }
        self.onDismissCompleted?()
      }
      self.host = host
      return host
    }

    private static func zoomOptions(for host: HostingController) -> UIViewController.Transition.ZoomOptions {
      let options = UIViewController.Transition.ZoomOptions()
      // Schließen per Ziehen: zusätzlich zum System-Default (`willBegin`) jede klar nach unten gerichtete
      // Bewegung, egal wo sie beginnt — außer in einer heruntergescrollten Liste (Kapitel, Teleprompter):
      // dort scrollt dieselbe Bewegung nach oben und darf den Player nicht schließen.
      options.interactiveDismissShouldBegin = { [weak host] context in
        if let host, isInsideScrolledScrollView(context.location, in: host.view) { return false }
        let v = context.velocity
        return context.willBegin || (v.dy > 0 && v.dy > abs(v.dx))
      }
      // Den Mini-Player auf das obere Band des Players ausrichten (gleiches Seitenverhältnis wie die
      // Leiste) statt die ganze Karte in die Leiste zu stauchen.
      options.alignmentRectProvider = { context in
        let source = context.sourceView.bounds
        let zoomed = context.zoomedViewController.view.bounds
        guard source.width > 0, source.height > 0, zoomed.width > 0 else { return nil }
        let height = zoomed.width * source.height / source.width
        return CGRect(x: 0, y: 0, width: zoomed.width, height: height)
      }
      return options
    }

    /// Liegt `point` in einer Scroll-View, die nicht am oberen Rand steht?
    private static func isInsideScrolledScrollView(_ point: CGPoint, in root: UIView) -> Bool {
      var view = root.hitTest(point, with: nil)
      while let current = view, current !== root {
        if let scroll = current as? UIScrollView,
          scroll.contentOffset.y > -scroll.adjustedContentInset.top + 1
        {
          return true
        }
        view = current.superview
      }
      return false
    }

    private func topmostPresenter(from anchor: UIViewController) -> UIViewController? {
      guard var presenter = anchor.view.window?.rootViewController else { return nil }
      while let presented = presenter.presentedViewController {
        guard !presented.isBeingDismissed else { return nil }
        presenter = presented
      }
      return presenter
    }
  }
}
