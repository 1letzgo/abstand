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
  @Environment(\.themeAccent) private var themeAccent
  @State private var query: String = ""
  @State private var source: PodcastAddSource = .search
  /// Getippter Treffer → Sendungsdetail mit Feed-Infos und allen Folgen.
  @State private var previewHit: ABSPodcastDirectorySearchHit?

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
    .background(model.appearancePalette.background)
    .navigationTitle("Add podcast")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(item: $previewHit) { hit in
      PodcastDirectoryShowView(hit: hit)
    }
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
      // Frisch geöffnet (kein Rücksprung aus dem Sendungsdetail): alte Treffer verwerfen.
      if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        model.clearPodcastDirectorySearch()
      }
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
            .foregroundStyle(themeAccent)
        }
        .accessibilityLabel("Podcast store region")
      }
    }
    .onDisappear {
      // Beim Push aufs Sendungsdetail feuert `onDisappear` ebenfalls — dann Suche/Charts
      // behalten, sonst steht die Liste nach dem Zurück leer da.
      guard previewHit == nil else { return }
      query = ""
      model.clearPodcastDirectorySearch()
      model.clearPodcastCharts()
      model.clearPodcastDirectoryCountryOverride()
    }
  }

  private var podcastSearchField: some View {
    let palette = model.appearancePalette
    return HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(palette.textSecondary)
      TextField("Search Apple Podcasts", text: $query)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(palette.textPrimary)
        .tint(themeAccent)
      if !query.isEmpty {
        Button {
          query = ""
          model.clearPodcastDirectorySearch()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(palette.textSecondary)
        }
        .buttonStyle(.plain)
      }
    }
    .abstandSearchFieldChrome()
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
      AbstandLoadingSpinner()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
          AbstandLoadingSpinner()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        ForEach(hits) { hit in
          PodcastDirectoryHitRow(
            hit: hit,
            onOpen: { previewHit = hit },
            onSubscribe: { Task { await model.subscribeToPodcastDirectoryHit(hit) } }
          )
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, 4)
      .padding(.bottom, AppTheme.Layout.scrollBottomInsetBase)
    }
    .abstandScrollScreenBackground()
  }
}

private struct PodcastChartsCategoryPillStrip: View {
  @EnvironmentObject private var model: AppModel
  let categories: [ABSPodcastCharts.ChartCategory]
  let selectedGenreId: Int?
  let onSelect: (Int?) -> Void

  private var accent: Color { model.appearanceAccentColor }

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
              .foregroundStyle(selected ? accent : model.appearancePalette.textPrimary)
              .lineLimit(1)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(model.appearancePalette.card, in: Capsule(style: .continuous))
              .overlay {
                Capsule(style: .continuous)
                  .strokeBorder(selected ? accent : Color.clear, lineWidth: 2)
              }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, AppTheme.Layout.cardShadowYSubtle)
    }
    .contentMargins(.horizontal, AppTheme.Layout.tabPaddingH, for: .scrollContent)
    .scrollContentBackground(.hidden)
    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    .fixedSize(horizontal: false, vertical: true)
    .abstandThemeRefresh()
  }
}

private struct PodcastDirectoryHitRow: View {
  @EnvironmentObject private var model: AppModel
  let hit: ABSPodcastDirectorySearchHit
  /// Ganze Karte öffnet die Sendung (Feed-Infos + alle Folgen), wie Library-Zeilen ihr Detail.
  let onOpen: () -> Void
  let onSubscribe: () -> Void

  var body: some View {
    let palette = model.appearancePalette
    return LibraryRowLayout.libraryRowCardChrome(
      cardColor: palette.card,
      showsBottomProgressBar: false,
      progressValue: 0,
      openDetails: onOpen
    ) {
      HStack(alignment: .top, spacing: LibraryRowLayout.cardInset) {
        LibraryRowLayout.coverSlot {
          LibraryRowLayout.rowCoverImage(
            url: hit.cover.flatMap(URL.init(string:)),
            token: model.token,
            itemId: "podcast-dir:\(hit.id)",
            cacheAccount: model.coverImageCacheAccountDirectory(),
            cacheRevision: model.coverImageCacheRevision,
            requiresAuthorization: false
          )
          .accessibilityHidden(true)
        }

        LibraryRowLayout.metadataColumn(showsProgressBar: false) {
          VStack(alignment: .leading, spacing: 2) {
            Text(hit.title)
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.textPrimary)
              .lineLimit(1)
              .truncationMode(.tail)
              .minimumScaleFactor(0.85)
              .fixedSize(horizontal: false, vertical: true)
            if let a = hit.artistName, !a.isEmpty {
              Text(a)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            }
            if let context = contextLine {
              Text(context)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            LibraryRowLayout.metadataFooter {
              if let n = hit.trackCount, n > 0 {
                Text("\(n) episodes")
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(palette.textSecondary)
              }
            } trailing: {
              subscribeControl
            }
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityHint("Opens show details")
    .abstandThemeRefresh()
  }

  /// Genres und Explicit-Kennzeichnung aus dem Verzeichnis — bisher ungenutzte Treffer-Daten.
  private var contextLine: String? {
    var parts: [String] = []
    let genres = (hit.genres ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: " · ")) }
    if hit.explicit == true { parts.append("Explicit") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  @ViewBuilder
  private var subscribeControl: some View {
    if model.podcastDirectoryHitIsInLibrary(hit) {
      Text("In library")
        .font(.caption.weight(.semibold))
        .foregroundStyle(model.appearancePalette.textSecondary)
    } else {
      Button(action: onSubscribe) {
        if model.podcastSubscribeInProgressDirectoryHitId == hit.id {
          ProgressView()
            .tint(model.appearancePalette.foregroundOnAccent(model.appearanceAccentColor))
        } else {
          Text("Subscribe")
        }
      }
      .buttonStyle(AbstandProminentButtonStyle())
      .disabled(
        (hit.feedUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
          || !model.isNetworkReachable)
      .allowsHitTesting(model.podcastSubscribeInProgressDirectoryHitId == nil)
    }
  }
}
