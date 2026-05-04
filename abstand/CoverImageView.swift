import SwiftUI
import UIKit

struct CoverImageView: View {
  let url: URL?
  let token: String

  @State private var image: UIImage?

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        AppTheme.card
        Image(systemName: "book.closed.fill")
          .font(.title3)
          .foregroundStyle(AppTheme.textSecondary)
      }
    }
    // Feste Außengröße kommt vom Aufrufer; ohne diese Begrenzung kann das
    // volauflösende Bild den Mini-Player kurz extrem aufblasen.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .contentShape(Rectangle())
    .task(id: url?.absoluteString) {
      await load()
    }
  }

  private func load() async {
    image = nil
    guard let url else { return }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
        let ui = UIImage(data: data)
      else { return }
      await MainActor.run { image = ui }
    } catch {}
  }
}
