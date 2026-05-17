import SwiftUI

// MARK: - Add podcast (directory search, eigene Navigationseite)

struct PodcastAddFromSearchView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var query: String = ""

  var body: some View {
    Group {
      if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
        ContentUnavailableView(
          "Podcast suchen",
          systemImage: "dot.radiowaves.left.and.right",
          description: Text(
            "Treffer stammen von Apple Podcasts. Abonnieren legt die Sendung in deiner Audiobookshelf-Bibliothek an (auf dem Server oft Admin-Rechte nötig)."
          )
        )
        .padding(.horizontal)
      } else if model.podcastDirectorySearchLoading {
        ProgressView()
          .controlSize(.large)
          .tint(AppTheme.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.vertical, 48)
      } else if model.podcastDirectorySearchHits.isEmpty {
        ContentUnavailableView(
          "Keine Sendungen",
          systemImage: "magnifyingglass",
          description: Text("Anderen Suchbegriff versuchen.")
        )
      } else {
        List {
          ForEach(model.podcastDirectorySearchHits) { hit in
            HStack(alignment: .top, spacing: 12) {
              if let u = hit.cover.flatMap(URL.init(string:)) {
                AsyncImage(url: u) { phase in
                  switch phase {
                  case .success(let img):
                    img.resizable().scaledToFill()
                  default:
                    Color.clear
                  }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .fill(AppTheme.card)
                  .frame(width: 56, height: 56)
              }
              VStack(alignment: .leading, spacing: 4) {
                Text(hit.title)
                  .font(.headline)
                  .foregroundStyle(AppTheme.textPrimary)
                if let a = hit.artistName, !a.isEmpty {
                  Text(a)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                }
                if let n = hit.trackCount, n > 0 {
                  Text("\(n) Folgen")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                }
              }
              Spacer(minLength: 0)
              Button {
                Task {
                  let ok = await model.subscribeToPodcastDirectoryHit(hit)
                  if ok { dismiss() }
                }
              } label: {
                if model.podcastSubscribeInProgressDirectoryHitId == hit.id {
                  ProgressView()
                } else {
                  Text("Abonnieren")
                }
              }
              .buttonStyle(.borderedProminent)
              .tint(AppTheme.accent)
              .disabled(
                model.podcastSubscribeInProgressDirectoryHitId != nil
                  || (hit.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                  || !model.isNetworkReachable)
            }
            .padding(.vertical, 4)
          }
        }
        .listStyle(.plain)
      }
    }
    .searchable(text: $query, prompt: "Apple Podcasts durchsuchen")
    .onChange(of: query) { _, newValue in
      model.schedulePodcastDirectorySearch(term: newValue)
    }
    .onDisappear {
      query = ""
      model.clearPodcastDirectorySearch()
    }
  }
}
