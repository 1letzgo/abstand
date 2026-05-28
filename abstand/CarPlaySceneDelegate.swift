import CarPlay
import UIKit

/// CarPlay-Szene (Audio-App); Verbindung an `CarPlayCoordinator`.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    Task { @MainActor in
      CarPlayCoordinator.shared.connect(interfaceController: interfaceController)
    }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    Task { @MainActor in
      CarPlayCoordinator.shared.disconnect(interfaceController: interfaceController)
    }
  }
}
