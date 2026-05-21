import SwiftUI

// MARK: - Add podcast (directory search + iTunes charts)

private enum PodcastAddSource: String, CaseIterable, Identifiable {
  case search = "Search"
  case charts = "Charts"

  var id: String { rawValue }
}

struct PodcastAddFromSearchView: View {
  @EnvironmentObject private var model: AppModel
  @State private var query: String = ""
  @State private var source: PodcastAddSource = .search

  var body: some View {
    VStack(spacing: 0) {
      Picker("Source", selection: $source) {
        ForEach(PodcastAddSource.allCases) { s in
          Text(s.rawValue).tag(s)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, 12)
      .padding(.bottom, source == .search ? 8 : 12)

      if source == .search {
        podcastSearchField
          .padding(.horizontal, AppTheme.Layout.tabPaddingH)
          .padding(.bottom, 12)
      }

      Group {
        switch source {
        case .search:
          searchBody
        case .charts:
          chartsBody
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(AppTheme.background)
    .navigationTitle("Add podcast")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      if model.podcastShows.isEmpty {
        await model.reloadPodcastShowsCatalog()
      }
    }
    .onChange(of: query) { _, newValue in
      guard source == .search else { return }
      model.schedulePodcastDirectorySearch(term: newValue)
    }
    .onChange(of: source) { _, newSource in
      if newSource == .charts {
        Task { await model.loadPodcastCharts() }
      }
    }
    .onAppear {
      if source == .charts {
        Task { await model.loadPodcastCharts() }
      }
    }
    .onDisappear {
      query = ""
      model.clearPodcastDirectorySearch()
      model.clearPodcastCharts()
    }
  }

  private var podcastSearchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(AppTheme.textSecondary)
      TextField("Search Apple Podcasts", text: $query)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(AppTheme.textPrimary)
      if !query.isEmpty {
        Button {
          query = ""
          model.clearPodcastDirectorySearch()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  @ViewBuilder
  private var searchBody: some View {
    if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
      ContentUnavailableView(
        "Search podcasts",
        systemImage: "dot.radiowaves.left.and.right",
        description: Text(
          "Results come from Apple Podcasts (\(model.podcastDirectoryCountryCode().uppercased()) store). Subscribing adds the show to your Audiobookshelf library."
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
      podcastHitsList(model.podcastDirectorySearchHits)
    }
  }

  @ViewBuilder
  private var chartsBody: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      Text("Apple Podcasts Top Charts · \(model.podcastDirectoryCountryCode().uppercased())")
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)

      if model.podcastChartsLoading, model.podcastChartsHits.isEmpty {
        ProgressView()
          .controlSize(.large)
          .tint(AppTheme.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.vertical, 48)
      } else if model.podcastChartsHits.isEmpty {
        ContentUnavailableView(
          "Charts unavailable",
          systemImage: "chart.bar",
          description: Text("Pull to refresh or check your network connection.")
        )
      } else {
        podcastHitsList(model.podcastChartsHits)
      }
    }
    .refreshable {
      await model.loadPodcastCharts(force: true)
    }
  }

  private func podcastHitsList(_ hits: [ABSPodcastDirectorySearchHit]) -> some View {
    List {
      ForEach(hits) { hit in
        PodcastDirectoryHitRow(hit: hit) {
          Task { await model.subscribeToPodcastDirectoryHit(hit) }
        }
        .padding(.vertical, 4)
      }
    }
    .listStyle(.plain)
    .abstandScrollScreenBackground()
  }
}

private struct PodcastDirectoryHitRow: View {
  @EnvironmentObject private var model: AppModel
  let hit: ABSPodcastDirectorySearchHit
  let onSubscribe: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      if let u = hit.cover.flatMap(URL.init(string:)) {
        CoverImageView(
          url: u,
          token: model.token,
          itemId: "podcast-dir:\(hit.id)",
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision,
          requiresAuthorization: false
        )
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
        Button(action: onSubscribe) {
          if model.podcastSubscribeInProgressDirectoryHitId == hit.id {
            ProgressView()
          } else {
            Text("Subscribe")
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)
        .disabled(
          (hit.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
            || !model.isNetworkReachable)
        .allowsHitTesting(model.podcastSubscribeInProgressDirectoryHitId == nil)
      }
    }
  }
}
