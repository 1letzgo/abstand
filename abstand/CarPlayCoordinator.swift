import CarPlay
import Combine
import Foundation
import UIKit

/// CarPlay-Oberfläche (Audio-Kategorie): Tab-Leiste mit „Continue listening“ und „Downloads“,
/// Wiedergabe über `PlaybackController`, Transportsteuerung über Now Playing / Remote Commands.
///
/// Die Templates werden vollständig neu gebaut, wenn sich Regale, Downloads, Login oder der
/// laufende Titel ändern — CarPlay hat keine Diff-API, `updateSections` ersetzt ohnehin alles.
@MainActor
final class CarPlayCoordinator: NSObject {
  static let shared = CarPlayCoordinator()

  /// Fallback, falls das Fahrzeug keine Grenzen meldet (CarPlay erlaubt maximal 12 Sektionen).
  private static let defaultMaximumItemCount = 48
  private static let defaultMaximumSectionCount = 8

  private weak var appModel: AppModel?
  private weak var interfaceController: CPInterfaceController?
  private var cancellables = Set<AnyCancellable>()
  private var connectTask: Task<Void, Never>?
  private var artworkTasks: [String: Task<Void, Never>] = [:]
  /// Alle Zeilen, die auf dasselbe Cover warten — ein Ladevorgang bedient sie gemeinsam.
  private var artworkPendingItems: [String: [WeakListItemBox]] = [:]
  /// Generation pro Key: Nur der Task, dessen Generation noch eingetragen ist, räumt auf.
  private var artworkTaskGenerations: [String: UInt64] = [:]
  private var artworkGenerationCounter: UInt64 = 0
  /// Wiederverwendete Listen-Templates — sonst springt die Tab-Auswahl bei jedem Refresh zurück.
  private let continueTemplate = CPListTemplate(title: "Continue", sections: [])
  private let downloadsTemplate = CPListTemplate(title: "Downloads", sections: [])
  private var tabBarTemplate: CPTabBarTemplate?

  private override init() {
    super.init()
  }

  func bind(appModel: AppModel) {
    guard self.appModel !== appModel else { return }
    cancellables.removeAll()
    self.appModel = appModel

    appModel.$startShelves
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshTemplatesIfConnected() }
      .store(in: &cancellables)

    appModel.$downloadedShelfBooks
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshTemplatesIfConnected() }
      .store(in: &cancellables)

    appModel.$serverURL
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshTemplatesIfConnected() }
      .store(in: &cancellables)

    appModel.player.$activeBook
      .map(\.?.id)
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshTemplatesIfConnected() }
      .store(in: &cancellables)

    // Play/Pause ändert nur die Markierung der laufenden Zeile — kein voller Neuaufbau.
    appModel.player.$isPlaying
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshTemplatesIfConnected() }
      .store(in: &cancellables)
  }

  func connect(interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    interfaceController.delegate = self
    configureNowPlayingTemplate()

    connectTask?.cancel()
    connectTask = Task { [weak self] in
      guard let self, let model = self.appModel else { return }
      // Aus dem Auto gestartet: Downloads-Liste steht sofort, Regale kommen ggf. erst nach Bootstrap.
      model.refreshDownloadedShelfFromManifests()
      self.setRootTemplate()
      if model.isLoggedIn, model.startShelves.isEmpty {
        await model.loadStartDashboard()
      }
      guard !Task.isCancelled else { return }
      self.refreshTemplatesIfConnected()
    }
  }

  func disconnect(interfaceController: CPInterfaceController) {
    guard self.interfaceController === interfaceController else { return }
    connectTask?.cancel()
    connectTask = nil
    artworkTasks.values.forEach { $0.cancel() }
    artworkTasks.removeAll()
    artworkTaskGenerations.removeAll()
    artworkPendingItems.removeAll()
    tabBarTemplate = nil
    self.interfaceController = nil
  }

  // MARK: - Templates

  private func setRootTemplate() {
    guard let interfaceController else { return }
    updateListTemplates()
    let tabs = CPTabBarTemplate(templates: [continueTemplate, downloadsTemplate])
    tabBarTemplate = tabs
    // `CPTabBarTemplate` darf ausschließlich Root sein — nie pushen oder präsentieren.
    interfaceController.setRootTemplate(tabs, animated: true, completion: nil)
  }

  private func refreshTemplatesIfConnected() {
    guard interfaceController != nil else { return }
    guard tabBarTemplate != nil else {
      setRootTemplate()
      return
    }
    updateListTemplates()
  }

  private func updateListTemplates() {
    continueTemplate.tabTitle = "Continue"
    continueTemplate.tabImage = UIImage(systemName: "play.circle.fill")
    downloadsTemplate.tabTitle = "Downloads"
    downloadsTemplate.tabImage = UIImage(systemName: "arrow.down.circle.fill")

    continueTemplate.updateSections(clamped(continueSections()))
    downloadsTemplate.updateSections(clamped(downloadsSections()))
  }

  /// Fahrzeuggrenzen einhalten: zu lange Listen weist CarPlay sonst komplett zurück.
  private func clamped(_ sections: [CPListSection]) -> [CPListSection] {
    let maxItems = max(1, CPListTemplate.maximumItemCount)
    let maxSections = max(1, min(CPListTemplate.maximumSectionCount, Self.defaultMaximumSectionCount))
    var remaining = min(maxItems, Self.defaultMaximumItemCount)
    var out: [CPListSection] = []
    for section in sections.prefix(maxSections) {
      guard remaining > 0 else { break }
      let items = Array(section.items.prefix(remaining))
      remaining -= items.count
      out.append(CPListSection(items: items, header: section.header, sectionIndexTitle: nil))
    }
    return out
  }

  private func continueSections() -> [CPListSection] {
    guard let model = appModel else {
      return [messageSection("Open abstand on your iPhone.")]
    }
    guard model.isLoggedIn else {
      return [messageSection("Sign in on your iPhone to use abstand in the car.")]
    }
    guard let shelf = continueListeningShelf(in: model.startShelves) else {
      return [messageSection("Nothing in progress. Start listening on your iPhone.")]
    }
    let rows = ABSStartShelfMergedRow.merged(
      books: shelf.books,
      podcastEpisodes: shelf.podcastEpisodes,
      progress: model.progressByItemId
    )
    let items = rows.map { listItem(for: $0, model: model) }
    guard !items.isEmpty else {
      return [messageSection("Nothing in progress. Start listening on your iPhone.")]
    }
    return [CPListSection(items: items, header: "Continue listening", sectionIndexTitle: nil)]
  }

  private func downloadsSections() -> [CPListSection] {
    guard let model = appModel, model.isLoggedIn else { return [] }
    let books = model.downloadedShelfBooks
    guard !books.isEmpty else {
      return [messageSection("No downloads yet. Download on your iPhone to listen offline.")]
    }
    let items = books.map { book -> CPListItem in
      makeItem(
        title: book.displayTitle,
        detail: book.displayAuthors,
        progressKey: book.id,
        coverItemId: book.id,
        model: model,
        play: { await model.play(book: book) }
      )
    }
    return [CPListSection(items: items, header: "Downloaded", sectionIndexTitle: nil)]
  }

  private func messageSection(_ message: String) -> CPListSection {
    let item = CPListItem(text: message, detailText: nil)
    item.isEnabled = false
    return CPListSection(items: [item])
  }

  private func continueListeningShelf(in shelves: [ABSStartShelfSection]) -> ABSStartShelfSection? {
    shelves.first { shelf in
      shelf.category == "recentlyListened" || shelf.category == "itemsInProgressFallback"
    }
  }

  private func listItem(for row: ABSStartShelfMergedRow, model: AppModel) -> CPListItem {
    switch row {
    case .book(let book):
      return makeItem(
        title: book.displayTitle,
        detail: book.displayAuthors,
        progressKey: book.id,
        coverItemId: book.id,
        model: model,
        play: { await model.play(book: book) }
      )
    case .podcastEpisode(let episode):
      let detail = episode.showTitle.isEmpty ? episode.authorLine : episode.showTitle
      return makeItem(
        title: episode.episodeTitle,
        detail: detail,
        progressKey: episode.progressLookupKey,
        coverItemId: episode.libraryItemId,
        model: model,
        play: { await model.playPodcastEpisode(episode) }
      )
    }
  }

  private func makeItem(
    title: String,
    detail: String,
    progressKey: String,
    coverItemId: String,
    model: AppModel,
    play: @escaping () async -> Void
  ) -> CPListItem {
    let item = CPListItem(text: title, detailText: detail)
    if let progress = model.progressByItemId[progressKey], progress.duration > 0 {
      item.playbackProgress = CGFloat(min(1, max(0, progress.progress)))
    }
    item.isPlaying = model.player.activeBook?.id == coverItemId && model.player.isPlaying
    item.handler = { [weak self] _, completion in
      Task { @MainActor in
        // Completion in jedem Pfad — sonst bleibt die Zeile im Ladezustand hängen.
        defer { completion() }
        await play()
        self?.showNowPlaying()
      }
    }
    loadArtwork(for: item, itemId: coverItemId, model: model)
    return item
  }

  /// Cover asynchron nachladen und in die Zeile hängen (CarPlay skaliert selbst nicht herunter).
  private func loadArtwork(for item: CPListItem, itemId: String, model: AppModel) {
    guard let url = model.coverURL(for: itemId) else { return }
    let key = CoverImageCache.cacheKey(
      scopeId: itemId, revision: model.coverImageCacheRevision(forBookId: itemId))
    if let cached = CoverImageCache.memoryImage(itemId: key) {
      item.setImage(cached.carPlayThumbnail())
      return
    }
    // Zeile als Empfänger registrieren (derselbe Titel kann in „Continue“ und „Downloads“ stehen);
    // freigegebene Zeilen dabei ausmisten, damit die Liste nicht wächst.
    var waiting = (artworkPendingItems[key] ?? []).filter { $0.item != nil }
    waiting.append(WeakListItemBox(item))
    artworkPendingItems[key] = waiting

    // Läuft für den Key schon ein Ladevorgang, bedient er die neue Zeile mit — nicht abbrechen.
    guard artworkTasks[key] == nil else { return }

    artworkGenerationCounter &+= 1
    let generation = artworkGenerationCounter
    artworkTaskGenerations[key] = generation
    artworkTasks[key] = Task { [weak self] in
      let image = await CoverImageLoader.shared.image(
        key: key,
        account: model.coverImageCacheAccountDirectory(),
        url: url,
        token: model.token
      )
      guard let self else { return }
      // Aufräumen in jedem Ausgang (Abbruch, kein Bild, freigegebene Zeilen).
      defer { self.finishArtworkTask(key: key, generation: generation) }
      guard !Task.isCancelled, let image else { return }
      let thumbnail = image.carPlayThumbnail()
      // Zustellung bleibt auf dem MainActor — CPListItem ist nicht Sendable.
      for box in self.artworkPendingItems[key] ?? [] {
        box.item?.setImage(thumbnail)
      }
    }
  }

  /// Eintrag nur räumen, wenn er noch zum eigenen Task gehört — ein spät fertiger Alt-Task
  /// darf einen inzwischen gestarteten neueren Ladevorgang nicht aus `artworkTasks` werfen.
  private func finishArtworkTask(key: String, generation: UInt64) {
    guard artworkTaskGenerations[key] == generation else { return }
    artworkTaskGenerations.removeValue(forKey: key)
    artworkTasks.removeValue(forKey: key)
    artworkPendingItems.removeValue(forKey: key)
  }

  // MARK: - Now Playing

  private func configureNowPlayingTemplate() {
    let nowPlaying = CPNowPlayingTemplate.shared
    nowPlaying.isUpNextButtonEnabled = false
    nowPlaying.isAlbumArtistButtonEnabled = false
    // Hörbuch-Tempo ist die einzige Einstellung, die im Auto wirklich gebraucht wird.
    nowPlaying.updateNowPlayingButtons([
      CPNowPlayingPlaybackRateButton { [weak self] _ in
        self?.advancePlaybackRate()
      }
    ])
  }

  /// Nächstes Preset aus `PlaybackController.playbackRatePresets` (zyklisch).
  private func advancePlaybackRate() {
    guard let player = appModel?.player else { return }
    let presets = PlaybackController.playbackRatePresets
    let current = player.playbackRate
    let next =
      presets.first(where: { $0 > current + 0.01 })
      ?? presets.first
      ?? 1.0
    player.setPlaybackRate(next)
  }

  private func showNowPlaying() {
    guard let interfaceController else { return }
    let nowPlaying = CPNowPlayingTemplate.shared
    guard interfaceController.topTemplate !== nowPlaying else { return }
    interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
  }
}

extension CarPlayCoordinator: CPInterfaceControllerDelegate {}

/// Schwache Referenz auf eine CarPlay-Zeile; `CPListItem` ist nicht Sendable, daher MainActor.
@MainActor
private final class WeakListItemBox {
  weak var item: CPListItem?

  init(_ item: CPListItem) {
    self.item = item
  }
}

private extension UIImage {
  /// CarPlay lehnt zu große Bilder ab; auf die vom System gemeldete Maximalgröße bringen.
  func carPlayThumbnail() -> UIImage {
    let maxSize = CPListItem.maximumImageSize
    guard size.width > maxSize.width || size.height > maxSize.height else { return self }
    let scale = min(maxSize.width / size.width, maxSize.height / size.height)
    let target = CGSize(width: size.width * scale, height: size.height * scale)
    return UIGraphicsImageRenderer(size: target).image { _ in
      draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
