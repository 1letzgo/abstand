import Foundation

/// Persistierte Aktivierung und Reihenfolge einer Server-Library (Settings).
struct LibraryActivationPreference: Codable, Identifiable, Equatable, Hashable {
  var libraryId: String
  var enabled: Bool
  var sortOrder: Int

  var id: String { libraryId }

  init(libraryId: String, enabled: Bool = true, sortOrder: Int) {
    self.libraryId = libraryId
    self.enabled = enabled
    self.sortOrder = sortOrder
  }
}
