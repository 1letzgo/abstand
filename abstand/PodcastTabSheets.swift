import SwiftUI

// MARK: - Apple Podcasts storefront (Add-Podcast-View)

struct PodcastDirectoryCountryMenuItems: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    let defaultCode = model.defaultPodcastDirectoryCountryCode()
    let effective = model.podcastDirectoryCountryCode()
    ForEach(ABSPodcastCharts.directoryStorefrontMenuCodes(defaultCode: defaultCode), id: \.self) { code in
      Button {
        model.setPodcastDirectoryCountryOverride(code)
      } label: {
        countryMenuLabel(code: code, effective: effective)
      }
    }
  }

  @ViewBuilder
  private func countryMenuLabel(code: String, effective: String) -> some View {
    let title =
      "\(ABSPodcastCharts.directoryStorefrontDisplayName(for: code)) (\(code.uppercased()))"
    if code == effective {
      Label(title, systemImage: "checkmark")
    } else {
      Text(title)
    }
  }
}

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
      model.syncPodcastDirectoryEffectiveCountry()
      if source == .charts {
        Task { await model.loadPodcastCharts() }
      }
    }
    .onChange(of: model.podcastDirectoryEffectiveCountry) { _, _ in
      switch source {
      case .charts:
        Task { await model.loadPodcastCharts(force: true) }
      case .search:
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 2 {
          model.schedulePodcastDirectorySearch(term: t)
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          PodcastDirectoryCountryMenuItems()
        } label: {
          Text(model.podcastDirectoryCountryCode().uppercased())
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .accessibilityLabel("Podcast store region")
      }
    }
    .onDisappear {
      query = ""
      model.clearPodcastDirectorySearch()
      model.clearPodcastCharts()
      model.clearPodcastDirectoryCountryOverride()
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
        .tint(Color.accentColor)
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
    VStack(spacing: 0) {
      PodcastChartsCategoryPillStrip(
        categories: ABSPodcastCharts.chartCategories,
        selectedGenreId: model.podcastChartsSelectedGenreId,
        onSelect: { model.selectPodcastChartsCategory(genreId: $0) }
      )
      .padding(.bottom, 10)

      Group {
        if model.podcastChartsLoading, model.podcastChartsHits.isEmpty {
          ProgressView()
            .controlSize(.large)
            .tint(Color.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 48)
        } else if model.podcastChartsHits.isEmpty {
          ContentUnavailableView(
            "Charts unavailable",
            systemImage: "chart.bar",
            description: Text("Check your network connection or try another category.")
          )
        } else {
          podcastHitsList(model.podcastChartsHits)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct PodcastChartsCategoryPillStrip: View {
  let categories: [ABSPodcastCharts.ChartCategory]
  let selectedGenreId: Int?
  let onSelect: (Int?) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(categories) { category in
          let selected = selectedGenreId == category.genreId
          Button {
            onSelect(category.genreId)
          } label: {
            Text(category.title)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(selected ? Color.accentColor : AppTheme.textPrimary)
              .lineLimit(1)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(AppTheme.card, in: Capsule(style: .continuous))
              .overlay {
                Capsule(style: .continuous)
                  .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
              }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
    }
    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    .fixedSize(horizontal: false, vertical: true)
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
        .tint(Color.accentColor)
        .disabled(
          (hit.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
            || !model.isNetworkReachable)
        .allowsHitTesting(model.podcastSubscribeInProgressDirectoryHitId == nil)
      }
    }
  }
}
