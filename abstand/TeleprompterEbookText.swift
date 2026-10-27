import Foundation
import ReadiumShared

/// Liefert den eBook-Index eines angehängten (bereits geladenen) EPUBs für die Sprung-Buttons
/// zwischen eBook und Hörbuch (`EbookReadAlong`). Der Teleprompter zeigt bewusst immer das
/// Transkript; der Abgleich liegt in `EbookAudioAlignment.swift`.
@MainActor
final class TeleprompterEbookTextProvider {
  static let shared = TeleprompterEbookTextProvider()

  private var cache: [String: Task<EbookReadAlongIndex?, Never>] = [:]

  /// eBook-Index für das Hörbuch — nur wenn das EPUB schon auf dem Gerät liegt (kein Download).
  func index(forLibraryItemId libraryItemId: String, model: AppModel) async -> EbookReadAlongIndex? {
    if let task = cache[libraryItemId] { return await task.value }
    guard let url = model.cachedEpubURL(libraryItemId: libraryItemId) else { return nil }
    let task = Task<EbookReadAlongIndex?, Never> {
      guard let publication = try? await ReadiumReaderService.shared.openPublication(localFileURL: url) else {
        return nil
      }
      let box = TeleprompterPublicationBox(publication)
      let built = await Task.detached(priority: .userInitiated) {
        await EbookReadAlongIndex.build(publication: box.value)
      }.value
      return built.isEmpty ? nil : built
    }
    cache[libraryItemId] = task
    let result = await task.value
    // Fehlschlag nicht merken — sonst bleibt der eBook-Text bis zum App-Neustart aus.
    if result == nil { cache[libraryItemId] = nil }
    return result
  }
}

private final class TeleprompterPublicationBox: @unchecked Sendable {
  let value: Publication
  init(_ value: Publication) { self.value = value }
}
