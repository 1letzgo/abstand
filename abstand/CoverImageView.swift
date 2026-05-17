import SwiftUI
import UIKit

enum CoverImageContentMode {
  /// Wie Mini-Player und Karten: füllt den Rahmen, kann oben/unten oder an den Seiten beschneiden.
  case fill
  /// Vollansicht: komplettes Cover sichtbar, Briefkasten nach Bedarf.
  case fit
}

struct CoverImageView: View {
  let url: URL?
  let token: String
  let itemId: String
  /// `model.coverImageCacheAccountDirectory()`; ohne Wert kein Persistenz-Cache.
  let cacheAccount: URL?
  var cacheRevision: Int = 0
  var contentMode: CoverImageContentMode = .fill

  @State private var image: UIImage?

  private var loadIdentity: String {
    "\(itemId)|\(url?.absoluteString ?? "")"
  }

  init(
    url: URL?,
    token: String,
    itemId: String,
    cacheAccount: URL?,
    
    cacheRevision: Int = 0,
    contentMode: CoverImageContentMode = .fill
  ) {
    self.url = url
    self.token = token
    self.itemId = itemId
    self.cacheAccount = cacheAccount
    self.cacheRevision = cacheRevision
    self.contentMode = contentMode
    _image = State(
      initialValue: CoverImageCache.syncUIImage(itemId: itemId, account: cacheAccount))
  }

  var body: some View {
    Group {
      if contentMode == .fill {
        imageOrPlaceholder
          .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
      } else {
        imageOrPlaceholder
      }
    }
    .clipped()
    .contentShape(Rectangle())
    .task(id: loadIdentity) {
      await load()
    }
    .onChange(of: cacheRevision) { _, _ in
      image = CoverImageCache.syncUIImage(itemId: itemId, account: cacheAccount)
    }
  }

  @ViewBuilder
  private var imageOrPlaceholder: some View {
    if let image {
      switch contentMode {
      case .fill:
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
      case .fit:
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      }
    } else {
      ZStack {
        AppTheme.card
        Image(systemName: "book.closed.fill")
          .font(.title3)
          .foregroundStyle(AppTheme.textSecondary)
      }
      .modifier(FillOnlyExpand(contentMode: contentMode))
    }
  }

  /// Platzhalter füllt den Kartenrahmen nur bei `.fill`; bei `.fit` kein erzwungenes Strecken.
  private struct FillOnlyExpand: ViewModifier {
    let contentMode: CoverImageContentMode
    func body(content: Content) -> some View {
      switch contentMode {
      case .fill:
        content
          .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
      case .fit:
        content
          .frame(minWidth: 44, minHeight: 44)
      }
    }
  }

  private func load() async {
    let scopeId = itemId
    guard let url, !scopeId.isEmpty else {
      await MainActor.run {
        guard !Task.isCancelled, itemId == scopeId else { return }
        image = nil
      }
      return
    }

    if let cached = CoverImageCache.memoryImage(itemId: scopeId) {
      await MainActor.run {
        guard !Task.isCancelled, itemId == scopeId else { return }
        image = cached
      }
      return
    }

    if let account = cacheAccount,
      let data = CoverImageCache.loadFromDisk(account: account, itemId: scopeId),
      let ui = UIImage(data: data)
    {
      CoverImageCache.storeMemory(itemId: scopeId, image: ui)
      await MainActor.run {
        guard !Task.isCancelled, itemId == scopeId else { return }
        image = ui
      }
      return
    }

    var req = URLRequest(url: url)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      try Task.checkCancellation()
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let ui = UIImage(data: data)
      else { return }
      if let account = cacheAccount {
        try? CoverImageCache.saveToDisk(account: account, itemId: scopeId, data: data)
      }
      CoverImageCache.storeMemory(itemId: scopeId, image: ui)
      await MainActor.run {
        guard !Task.isCancelled, itemId == scopeId else { return }
        image = ui
      }
    } catch {}
  }
}
