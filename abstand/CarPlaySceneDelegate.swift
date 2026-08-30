import CarPlay
import UIKit

/// CarPlay-Szene (Audio-App); Verbindung an `CarPlayCoordinator`.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    Task { @MainActor in
      // Kaltstart aus dem Auto: `bind` passiert sonst erst, wenn die Telefon-Oberfläche startet.
      CarPlayCoordinator.shared.bind(appModel: AppModel.shared)
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
