import CarPlay
import Combine
import Foundation

/// CarPlay-Listen: „Continue listening“ + Now Playing (Steuerung über `PlaybackController` / Now Playing).
@MainActor
final class CarPlayCoordinator: NSObject {
  static let shared = CarPlayCoordinator()

  private weak var appModel: AppModel?
  private weak var interfaceController: CPInterfaceController?
  private var cancellables = Set<AnyCancellable>()
  private var connectTask: Task<Void, Never>?

  private override init() {
    super.init()
  }

  func bind(appModel: AppModel) {
    guard self.appModel !== appModel else { return }
    cancellables.removeAll()
    self.appModel = appModel

    appModel.$startShelves
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshRootTemplateIfConnected() }
      .store(in: &cancellables)

    appModel.$serverURL
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshRootTemplateIfConnected() }
      .store(in: &cancellables)

    appModel.player.$activeBook
      .map(\.?.id)
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshRootTemplateIfConnected() }
      .store(in: &cancellables)
  }

  func connect(interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    interfaceController.delegate = self
    connectTask?.cancel()
    connectTask = Task { [weak self] in
      guard let self, let model = self.appModel else { return }
      if model.isLoggedIn, model.startShelves.isEmpty {
        await model.loadStartDashboard()
      }
      guard !Task.isCancelled else { return }
      self.refreshRootTemplateIfConnected()
    }
  }

  func disconnect(interfaceController: CPInterfaceController) {
    if self.interfaceController === interfaceController {
      connectTask?.cancel()
      connectTask = nil
      self.interfaceController = nil
    }
  }

  private func refreshRootTemplateIfConnected() {
    guard let interfaceController else { return }
    let template = buildRootListTemplate()
    interfaceController.setRootTemplate(template, animated: true, completion: nil)
  }

  private func buildRootListTemplate() -> CPListTemplate {
    guard let model = appModel else {
      return emptyListTemplate(message: "Open abstand on your iPhone.")
    }
    guard model.isLoggedIn else {
      return emptyListTemplate(message: "Sign in on your iPhone to use abstand in the car.")
    }

    var sections: [CPListSection] = []

    if let shelf = continueListeningShelf(in: model.startShelves) {
      let rows = ABSStartShelfMergedRow.merged(
        books: shelf.books,
        podcastEpisodes: shelf.podcastEpisodes,
        progress: model.progressByItemId
      )
      let items = rows.prefix(24).map { row in listItem(for: row, model: model) }
      if !items.isEmpty {
        sections.append(CPListSection(items: items, header: "Continue listening", sectionIndexTitle: nil))
      }
    }

    if model.offlineHomeUIActive || !model.downloadedShelfBooks.isEmpty {
      let downloads = model.downloadedShelfBooks.prefix(24)
      if !downloads.isEmpty {
        let items = downloads.map { book in
          let item = CPListItem(text: book.displayTitle, detailText: book.displayAuthors)
          item.handler = { [weak self] _, completion in
            Task { @MainActor in
              await model.play(book: book)
              self?.showNowPlaying()
              completion()
            }
          }
          return item
        }
        sections.append(CPListSection(items: items, header: "Downloads", sectionIndexTitle: nil))
      }
    }

    if sections.isEmpty {
      return emptyListTemplate(message: "Nothing to play yet. Start listening on your iPhone.")
    }

    let template = CPListTemplate(title: "abstand", sections: sections)
    template.tabTitle = "Library"
    template.tabImage = UIImage(systemName: "books.vertical.fill")
    return template
  }

  private func emptyListTemplate(message: String) -> CPListTemplate {
    let item = CPListItem(text: message, detailText: nil)
    item.isEnabled = false
    let section = CPListSection(items: [item])
    let template = CPListTemplate(title: "abstand", sections: [section])
    template.tabTitle = "Library"
    template.tabImage = UIImage(systemName: "books.vertical.fill")
    return template
  }

  private func continueListeningShelf(in shelves: [ABSStartShelfSection]) -> ABSStartShelfSection? {
    shelves.first { shelf in
      shelf.category == "recentlyListened" || shelf.category == "itemsInProgressFallback"
    }
  }

  private func listItem(for row: ABSStartShelfMergedRow, model: AppModel) -> CPListItem {
    switch row {
    case .book(let book):
      let item = CPListItem(text: book.displayTitle, detailText: book.displayAuthors)
      item.handler = { [weak self] _, completion in
        Task { @MainActor in
          await model.play(book: book)
          self?.showNowPlaying()
          completion()
        }
      }
      return item
    case .podcastEpisode(let episode):
      let detail = episode.showTitle.isEmpty ? episode.authorLine : episode.showTitle
      let item = CPListItem(text: episode.episodeTitle, detailText: detail)
      item.handler = { [weak self] _, completion in
        Task { @MainActor in
          await model.playPodcastEpisode(episode)
          self?.showNowPlaying()
          completion()
        }
      }
      return item
    }
  }

  private func showNowPlaying() {
    guard let interfaceController else { return }
    let nowPlaying = CPNowPlayingTemplate.shared
    if interfaceController.topTemplate !== nowPlaying {
      interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
    }
  }
}

extension CarPlayCoordinator: CPInterfaceControllerDelegate {}
