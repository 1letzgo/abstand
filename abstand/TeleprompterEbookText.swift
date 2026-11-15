import Foundation
import ReadiumShared
import UIKit

/// Liefert den eBook-Index eines angehängten (bereits geladenen) EPUBs für die Sprung-Buttons
/// zwischen eBook und Hörbuch (`EbookReadAlong`). Der Teleprompter zeigt bewusst immer das
/// Transkript; der Abgleich liegt in `EbookAudioAlignment.swift`.
@MainActor
final class TeleprompterEbookTextProvider {
  static let shared = TeleprompterEbookTextProvider()

  /// Ein Index ist bei langen Büchern viele MB groß — nur die zuletzt genutzten Bücher behalten.
  private static let maxCachedBooks = 2

  private var cache: [String: Task<EbookReadAlongIndex?, Never>] = [:]
  /// Zuletzt genutzt am Ende.
  private var recentIds: [String] = []
  private var memoryWarningObserver: NSObjectProtocol?

  private init() {
    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.removeAll() }
    }
  }

  /// Speicherwarnung: alle Indizes verwerfen — sie werden beim nächsten Sprung neu gebaut.
  func removeAll() {
    cache.removeAll()
    recentIds.removeAll()
  }

  /// eBook-Index für das Hörbuch — nur wenn das EPUB schon auf dem Gerät liegt (kein Download).
  func index(forLibraryItemId libraryItemId: String, model: AppModel) async -> EbookReadAlongIndex? {
    if let task = cache[libraryItemId] {
      touch(libraryItemId)
      return await task.value
    }
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
    touch(libraryItemId)
    let result = await task.value
    // Fehlschlag nicht merken — sonst bleibt der eBook-Text bis zum App-Neustart aus.
    if result == nil, cache[libraryItemId] == task {
      cache[libraryItemId] = nil
      recentIds.removeAll { $0 == libraryItemId }
    }
    return result
  }

  private func touch(_ libraryItemId: String) {
    recentIds.removeAll { $0 == libraryItemId }
    recentIds.append(libraryItemId)
    while recentIds.count > Self.maxCachedBooks {
      cache[recentIds.removeFirst()] = nil
    }
  }
}

private final class TeleprompterPublicationBox: @unchecked Sendable {
  let value: Publication
  init(_ value: Publication) { self.value = value }
}
