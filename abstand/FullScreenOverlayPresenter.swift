import SwiftUI
import UIKit

/// Präsentiert SwiftUI-Inhalt über `UIViewController.present(_:animated:)` mit
/// `.overFullScreen` statt SwiftUIs `.fullScreenCover`.
///
/// `.fullScreenCover` entfernt die darunterliegende View komplett aus der Hierarchie — beim
/// eigenen Drag-to-dismiss (siehe `NowPlayingDetailView.fullPlayerStack`) wird darüber deshalb
/// nur eine leere (weiße) Fläche sichtbar, sobald der Inhalt nach unten verschoben wird.
/// `.overFullScreen` hält die präsentierende View dagegen am Leben und einfach dahinter liegend —
/// mit transparentem Hintergrund der gehosteten View scheint sie durch, sobald der eigene Inhalt
/// per Geste verschoben wird. Das entspricht dem Verhalten von Apple Music: Vollbild beim Öffnen,
/// aber beim Herunterziehen wird die App dahinter sichtbar statt einer leeren Fläche.
struct FullScreenOverlayPresenter<OverlayContent: View>: UIViewControllerRepresentable {
  @Binding var isPresented: Bool
  @ViewBuilder var overlayContent: () -> OverlayContent

  func makeUIViewController(context: Context) -> UIViewController {
    UIViewController()
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    // Bewusst KEIN `.environment(\.self, context.environment)`: Das hat zwischenzeitlich das
    // komplette `EnvironmentValues` des Aufrufers durchgereicht — inklusive dessen Safe-Area-/
    // Geometrie-Kontext (der `.background`-Sitz neben `MainTabShellView` ist selbst nicht
    // vollbildgroß). Ergebnis: der Player startete unterhalb der Notch und war unten
    // abgeschnitten. Alles, was der gehostete Inhalt wirklich braucht (Theme, Accent,
    // `EnvironmentObject`s), wird stattdessen explizit im Content-Closure gesetzt
    // (siehe `abstandApp.swift`).
    let content = overlayContent()
    if isPresented {
      context.coordinator.present(content, from: uiViewController)
    } else {
      context.coordinator.dismiss()
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

  @MainActor
  final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    private let isPresented: Binding<Bool>
    private var hostingController: UIHostingController<OverlayContent>?
    private weak var presentationAnchor: UIViewController?
    private var pendingContent: OverlayContent?
    private var isDismissing = false
    private var presentationRetryScheduled = false

    init(isPresented: Binding<Bool>) {
      self.isPresented = isPresented
    }

    func present(_ content: OverlayContent, from anchor: UIViewController) {
      presentationAnchor = anchor
      if isDismissing {
        pendingContent = content
        return
      }
      if let hostingController {
        // Bereits präsentiert — nur den Inhalt aktualisieren (z. B. Theme-/Appearance-Änderungen),
        // `@State` in `OverlayContent` bleibt dabei erhalten (analog zu `.sheet`-Content-Closures).
        hostingController.rootView = content
        return
      }
      guard let presenter = topmostPresenter(from: anchor) else {
        pendingContent = content
        schedulePendingPresentationRetry()
        return
      }
      let host = UIHostingController(rootView: content)
      host.modalPresentationStyle = .overFullScreen
      host.view.backgroundColor = .clear
      // `.overFullScreen` lässt die präsentierende View (technisch) im Hintergrund aktiv —
      // ohne dieses Flag könnte VoiceOver dorthin navigieren, obwohl sie visuell verdeckt ist.
      host.view.accessibilityViewIsModal = true
      host.presentationController?.delegate = self
      hostingController = host
      pendingContent = nil
      presenter.present(host, animated: true)
    }

    private func topmostPresenter(from anchor: UIViewController) -> UIViewController? {
      var presenter = anchor.view.window?.rootViewController ?? anchor
      while let presented = presenter.presentedViewController {
        guard !presented.isBeingDismissed else { return nil }
        presenter = presented
      }
      return presenter
    }

    private func schedulePendingPresentationRetry() {
      guard !presentationRetryScheduled else { return }
      presentationRetryScheduled = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        guard let self else { return }
        self.presentationRetryScheduled = false
        guard self.isPresented.wrappedValue,
          let content = self.pendingContent,
          let anchor = self.presentationAnchor
        else { return }
        self.present(content, from: anchor)
      }
    }

    func dismiss() {
      guard let hostingController, !isDismissing else { return }
      isDismissing = true
      hostingController.dismiss(animated: true) { [weak self, weak hostingController] in
        guard let self else { return }
        self.hostingController = nil
        self.isDismissing = false
        guard self.isPresented.wrappedValue,
          let content = self.pendingContent ?? hostingController?.rootView,
          let anchor = self.presentationAnchor
        else {
          self.pendingContent = nil
          return
        }
        self.present(content, from: anchor)
      }
    }

    /// Falls der Controller je außerhalb unseres eigenen Bindings verschwindet (z. B. System),
    /// Binding nachziehen, damit kein Zustand verwaist.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
      hostingController = nil
      isDismissing = false
      pendingContent = nil
      isPresented.wrappedValue = false
    }
  }
}
