import SwiftUI
import UIKit

/// Server-Cover-Auflösung: ABS skaliert `/api/items/:id/cover` (Default sonst 400 px).
enum CoverImageTier {
  /// Listen, Karten, Mini-Player.
  case thumbnail
  /// Buch-/Folgen-Detail, Vollplayer, Now Playing.
  case hero

  var cacheScopeSuffix: String? {
    switch self {
    case .thumbnail: return nil
    case .hero: return "cover-hero"
    }
  }
}

enum CoverImageContentMode {
  /// Wie Mini-Player und Karten: füllt den Rahmen, kann oben/unten oder an den Seiten beschneiden.
  case fill
  /// Vollansicht: komplettes Cover sichtbar, Briefkasten nach Bedarf.
  case fit
  /// eBook-Zeilen: Höhe fix, Breite folgt dem Seitenverhältnis des Covers (kein Beschnitt, kein Strecken).
  case fitVariableWidth
}

struct CoverImageView: View {
  let url: URL?
  let token: String
  let itemId: String
  /// Disk-/Memory-Key; Standard `itemId`, Hero z. B. `id#cover-hero` (getrennt vom Thumbnail).
  let cacheScopeId: String
  /// `model.coverImageCacheAccountDirectory()`; ohne Wert kein Persistenz-Cache.
  let cacheAccount: URL?
  var cacheRevision: Int = 0
  /// `false` für externe URLs (z. B. Apple Podcasts Directory) ohne Bearer-Token.
  var requiresAuthorization: Bool = true
  var contentMode: CoverImageContentMode = .fill

  @State private var image: UIImage?

  private var loadIdentity: String {
    "\(itemId)|\(url?.absoluteString ?? "")|\(cacheRevision)"
  }

  /// Storage-Key für Memory-/Disk-Cache. `cacheRevision` fließt hier mit ein (nicht nur in
  /// `loadIdentity`), sonst würde ein geänderter Revision-Wert zwar `.task` neu triggern, aber
  /// `load()` würde trotzdem sofort den alten, unter demselben Key liegenden Cache-Treffer zurückgeben.
  private func effectiveCacheKey(for scopeId: String) -> String {
    CoverImageCache.cacheKey(scopeId: scopeId, revision: cacheRevision)
  }

  init(
    url: URL?,
    token: String,
    itemId: String,
    cacheAccount: URL?,
    cacheScopeId: String? = nil,
    cacheRevision: Int = 0,
    requiresAuthorization: Bool = true,
    contentMode: CoverImageContentMode = .fill
  ) {
    self.url = url
    self.token = token
    self.itemId = itemId
    self.cacheScopeId = cacheScopeId ?? itemId
    self.cacheAccount = cacheAccount
    self.cacheRevision = cacheRevision
    self.requiresAuthorization = requiresAuthorization
    self.contentMode = contentMode
    let resolvedScopeId = cacheScopeId ?? itemId
    let resolvedKey = CoverImageCache.cacheKey(scopeId: resolvedScopeId, revision: cacheRevision)
    // Nur Memory-Treffer synchron (schnell) — Disk-Fallback läuft erst in `.task`/`load()`, sonst
    // blockiert der Init (läuft auf dem Main Thread während des SwiftUI-Renderns) mit Disk-I/O.
    _image = State(initialValue: CoverImageCache.memoryImage(itemId: resolvedKey))
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
      image = CoverImageCache.memoryImage(itemId: effectiveCacheKey(for: cacheScopeId))
      await load()
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
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .fitVariableWidth:
        // Kein greedy Frame: Breite ergibt sich aus Zeilenhöhe × Seitenverhältnis.
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
      case .fitVariableWidth:
        // Platzhalter im typischen Buch-Hochformat (10:16).
        content
          .aspectRatio(10 / 16, contentMode: .fit)
      }
    }
  }

  private func load() async {
    let scopeId = cacheScopeId
    let key = effectiveCacheKey(for: scopeId)
    guard let url, !scopeId.isEmpty else {
      await MainActor.run {
        guard !Task.isCancelled, cacheScopeId == scopeId else { return }
        image = nil
      }
      return
    }

    if let cached = CoverImageCache.memoryImage(itemId: key) {
      await MainActor.run {
        guard !Task.isCancelled, cacheScopeId == scopeId else { return }
        image = cached
      }
      return
    }

    if let account = cacheAccount {
      // Disk-Read + Decode off-MainActor — sonst blockiert das den Aufrufer-Thread des `.task`.
      let diskImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
        guard let data = CoverImageCache.loadFromDisk(account: account, itemId: key),
          let ui = UIImage(data: data)
        else { return nil }
        return ui
      }.value
      if let diskImage {
        CoverImageCache.storeMemory(itemId: key, image: diskImage)
        await MainActor.run {
          guard !Task.isCancelled, cacheScopeId == scopeId else { return }
          image = diskImage
        }
        return
      }
    }

    var req = URLRequest(url: url)
    if requiresAuthorization, !token.isEmpty {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      try Task.checkCancellation()
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let ui = UIImage(data: data)
      else { return }
      if let account = cacheAccount {
        try? CoverImageCache.saveToDisk(account: account, itemId: key, data: data)
      }
      CoverImageCache.storeMemory(itemId: key, image: ui)
      await MainActor.run {
        guard !Task.isCancelled, cacheScopeId == scopeId else { return }
        image = ui
      }
    } catch {}
  }
}
