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
          "Search podcasts",
          systemImage: "dot.radiowaves.left.and.right",
          description: Text(
            "Results come from Apple Podcasts. Subscribing adds the show to your Audiobookshelf library (server admin rights are often required)."
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
          "No shows found",
          systemImage: "magnifyingglass",
          description: Text("Try a different search term.")
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
                  Text("\(n) episodes")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                }
              }
              Spacer(minLength: 0)
              if model.podcastDirectoryHitIsInLibrary(hit) {
                Text("In library")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(AppTheme.textSecondary)
                  .padding(.horizontal, 4)
              } else {
                Button {
                  Task {
                    let ok = await model.subscribeToPodcastDirectoryHit(hit)
                    if ok { dismiss() }
                  }
                } label: {
                  if model.podcastSubscribeInProgressDirectoryHitId == hit.id {
                    ProgressView()
                  } else {
                    Text("Subscribe")
                  }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(
                  model.podcastSubscribeInProgressDirectoryHitId != nil
                    || (hit.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                    || !model.isNetworkReachable)
              }
            }
            .padding(.vertical, 4)
          }
        }
        .listStyle(.plain)
      }
    }
    .searchable(text: $query, prompt: "Search Apple Podcasts")
    .task {
      if model.podcastShows.isEmpty {
        await model.reloadPodcastShowsCatalog()
      }
    }
    .onChange(of: query) { _, newValue in
      model.schedulePodcastDirectorySearch(term: newValue)
    }
    .onDisappear {
      query = ""
      model.clearPodcastDirectorySearch()
    }
  }
}
