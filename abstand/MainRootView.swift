import Combine
import SwiftUI

struct MainRootView: View {
  // internal (nicht private), damit die Browse-Section-Extension in `MainRootBrowseSections.swift` darauf zugreifen kann.
  @EnvironmentObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @StateObject private var booksLibraryToolbarState = BooksLibraryToolbarState()
  /// Eigene Instanz für den eBooks-Tab — Filter/Sortierung kommen aus demselben Model.
  @StateObject private var ebooksLibraryToolbarState = BooksLibraryToolbarState()
  @StateObject private var podcastCatalogToolbarState = PodcastCatalogToolbarState()
  /// Tabs erst bei erstem Besuch aufbauen — Home sofort, Rest lazy (Prewarm nach Bootstrap).
  @State private var activatedTabs: Set<AppModel.MainTab> = [.start]
  @State private var libraryRelayoutEpoch = 0
  @State private var ebooksRelayoutEpoch = 0
  /// Leisten-Auswahl im eBooks-Tab (reine eBooks / mit Hörbuch) — rein lokaler UI-Zustand.
  @State private var ebooksBrowseSection: EbooksBrowseSection = .ebooks
  @State private var podcastsRelayoutEpoch = 0
  /// Eine Destination am Katalog-Stack — nicht pro Lazy-Zeile (`isPresented` kommt dort oft nicht an).
  @State private var podcastDetailEpisode: ABSPodcastEpisodeListItem?

  var body: some View {
    let _ = model.appearanceThemeRevision
    return tabViewBody
      .tint(model.appearanceAccentColor)
      .themeAccentFromAppModel(model)
      // Abgeschlossener Download — einmaliges System-Feedback statt stiller Zustandsänderung.
      .sensoryFeedback(.success, trigger: model.downloads.completedDownloadCount)
      .background {
        AppThemeScreenBackground(ignoresSafeArea: true)
      }
    // Selbstheilung: Sollte dieser View je seine Strukturidentität verlieren (alle `@State`
    // zurückgesetzt, `activatedTabs` wieder `[.start]`), den gerade sichtbaren Tab sofort
    // reaktivieren — sonst rendert `lazyTabContent` für ihn dauerhaft `Color.clear` (weißer
    // Screen), weil `.onChange(of: model.mainTab)` ohne Tab-Wechsel nie feuert.
    .onAppear {
      activatedTabs.insert(model.mainTab)
      if model.shouldPrewarmSecondaryTabs {
        activatedTabs.formUnion(prewarmTabs)
      }
    }
    .fullScreenCover(item: $model.ebookReaderSession) { session in
      ReadiumReaderView(
        title: session.title,
        author: session.author,
        libraryItemId: session.libraryItemId,
        localFileURL: session.localFileURL,
        format: session.format,
        serverResumeProgression: session.serverResumeProgression
      )
      .themeAccentFromAppModel(model)
      .tint(model.appearanceAccentColor)
    }
    .onReceive(model.player.$isPlaying.dropFirst()) { playing in
      guard !playing else { return }
      Task { await model.handlePlaybackPaused() }
    }
    .onChange(of: model.mainTab) { _, tab in
      activatedTabs.insert(tab)
      switch tab {
      case .library:
        libraryRelayoutEpoch += 1
        model.mediaCatalogKind = .audiobooks
        let previousFocus = model.focusedBooksLibrary?.id
        model.resetFocusedBooksLibraryToPrimaryOrFirstActive()
        if model.focusedBooksLibrary?.id != previousFocus {
          Task { await model.reloadLibrary(reset: true) }
        }
      case .ebooks:
        ebooksRelayoutEpoch += 1
        model.mediaCatalogKind = .audiobooks
        // Wie Audiobooks: Tab-Wechsel fokussiert die eBook-Primary (eigener Fokus, Audiobooks bleiben).
        // Die eBook-Listen merken sich ihre Bibliothek und laden bei Abweichung selbst neu (`.task(id:)`).
        model.resetFocusedEbooksLibraryToPrimary()
      case .podcasts:
        podcastsRelayoutEpoch += 1
        model.mediaCatalogKind = .podcasts
        let previousFocus = model.focusedPodcastLibrary?.id
        model.resetFocusedPodcastLibraryToPrimaryOrFirstActive()
        if model.focusedPodcastLibrary?.id != previousFocus {
          Task { await model.reloadPodcastLibrary(reset: true) }
        }
      default:
        break
      }
      if tab == .start, model.startShelves.isEmpty {
        Task { await model.loadStartDashboard() }
      }
    }
    .onChange(of: model.shouldPrewarmSecondaryTabs) { _, prewarm in
      guard prewarm else { return }
      activatedTabs.formUnion(prewarmTabs)
    }
    .onChange(of: model.ebookReaderSession?.libraryItemId) { _, newId in
      if newId == nil {
        model.refreshEbookContinueReadingShelf()
        model.flushEbookProgressSync()
      }
    }
    .onChange(of: model.selectedBooksLibrary?.id) { _, _ in
      model.clampMediaCatalogKindIfNeeded()
      if !model.showAudiobooksTab, model.mainTab == .library {
        model.mainTab = .start
      }
    }
    .onChange(of: model.selectedEbooksLibrary?.id) { _, _ in
      model.clampMediaCatalogKindIfNeeded()
      if !model.showEbooksTab, model.mainTab == .ebooks {
        model.mainTab = .start
      }
    }
    .onChange(of: model.selectedPodcastLibrary?.id) { _, _ in
      model.clampMediaCatalogKindIfNeeded()
    }
    .onChange(of: model.showAudiobooksTab) { _, visible in
      model.clampMediaCatalogKindIfNeeded()
      if visible { activatedTabs.insert(.library) }
    }
    .onChange(of: model.showEbooksTab) { _, visible in
      model.clampMediaCatalogKindIfNeeded()
      if visible { activatedTabs.insert(.ebooks) }
    }
    .onChange(of: model.showPodcastsTab) { _, visible in
      model.clampMediaCatalogKindIfNeeded()
      if visible { activatedTabs.insert(.podcasts) }
    }
    .onChange(of: model.accountSessionEpoch) { _, _ in
      activatedTabs = [.start]
      libraryRelayoutEpoch += 1
      ebooksRelayoutEpoch += 1
      podcastsRelayoutEpoch += 1
      ebooksBrowseSection = .ebooks
      booksLibraryToolbarState.resetForAccountSwitch()
      ebooksLibraryToolbarState.resetForAccountSwitch()
      podcastCatalogToolbarState.resetForAccountSwitch()
      podcastDetailEpisode = nil
    }
    .onReceive(model.nowPlayingSheetDismissCompleted) { _ in
      // UIKit-Overlay-Dismiss kann die Katalog-ScrollViews aus dem Layout bringen. Erst **nach**
      // der Animation aufräumen: währenddessen kostete das Frames und ließ die Inhalte hinter
      // dem schließenden Player sichtbar springen.
      libraryRelayoutEpoch += 1
      ebooksRelayoutEpoch += 1
      podcastsRelayoutEpoch += 1
    }
    .alert(
      "Error",
      isPresented: Binding(
        // Liegt der Vollbild-Player oder Reader darüber, zeigen die den Fehler selbst.
        get: { model.showsRootErrorAlert },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .alert("Enable offline mode?", isPresented: $model.showOfflineModeConfirmation) {
      Button("Cancel", role: .cancel) {
        model.cancelEnterOfflineHomeModeConfirmation()
      }
      Button("Go offline") {
        model.confirmEnterOfflineHomeMode()
      }
    } message: {
      Text(
        "The server connection will be paused. You can only play downloaded content. Progress syncs when you go back online."
      )
    }
  }

  /// Sekundär-Tabs, die nach dem Bootstrap vorgebaut werden (Settings ist kein Tab mehr).
  private var prewarmTabs: Set<AppModel.MainTab> {
    var tabs: Set<AppModel.MainTab> = []
    if model.showAudiobooksTab { tabs.insert(.library) }
    if model.showEbooksTab { tabs.insert(.ebooks) }
    if model.showPodcastsTab { tabs.insert(.podcasts) }
    return tabs
  }

  private var tabViewBody: some View {
    // Tab-Struktur bleibt auch offline erhalten — Inhalte filtern sich selbst auf Downloads.
    onlineTabView
  }

  private var onlineTabView: some View {
    TabView(selection: $model.mainTab) {
      Tab(AppModel.MainTab.start.rawValue, systemImage: "house.fill", value: AppModel.MainTab.start) {
        HomeTabRootView()
          .id("abstand-home-tab-root-\(model.accountSessionEpoch)")
      }

      // Sichtbarkeit folgt Settings (Library != None). Während Bootstrap gecachte Flags nutzen,
      // damit die TabView-Struktur nicht mitten im Start umgebaut wird.
      if model.showAudiobooksTab {
        Tab(AppModel.MainTab.library.rawValue, systemImage: "books.vertical", value: AppModel.MainTab.library) {
          lazyTabContent(.library) {
            if model.selectedBooksLibrary != nil {
              libraryTabRoot
            } else {
              tabLibraryBootstrapPlaceholder
            }
          }
        }
      }

      // Eigene eBook-Primary (Settings „Primary eBook library“) — „None“ blendet den Tab aus.
      if model.showEbooksTab {
        Tab(AppModel.MainTab.ebooks.rawValue, systemImage: "book.closed", value: AppModel.MainTab.ebooks) {
          lazyTabContent(.ebooks) {
            if model.selectedEbooksLibrary != nil {
              ebooksTabRoot
            } else {
              tabLibraryBootstrapPlaceholder
            }
          }
        }
      }

      if model.showPodcastsTab {
        Tab(AppModel.MainTab.podcasts.rawValue, systemImage: "mic.fill", value: AppModel.MainTab.podcasts) {
          lazyTabContent(.podcasts) {
            if model.selectedPodcastLibrary != nil {
              podcastsTabRoot
            } else {
              tabLibraryBootstrapPlaceholder
            }
          }
        }
      }

      // iOS-26-nativer Such-Tab (`role: .search`): System pinnt den Tab an den Rand der
      // Tabbar und morpht das Icon beim Aktivieren in ein Suchfeld (Liquid Glass).
      // `.searchable` liegt lokal auf SearchTabRootView, damit das Feld NUR hier erscheint.
      Tab(
        AppModel.MainTab.search.rawValue, systemImage: "magnifyingglass",
        value: AppModel.MainTab.search, role: .search
      ) {
        lazyTabContent(.search) {
          SearchTabRootView()
        }
        .id("abstand-search-tab-root-\(model.accountSessionEpoch)")
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    // Paper: Tab-Auswahl und Bedienelemente in Tinte; der Akzent (Zinnober) bleibt Fortschritt
    // und Links vorbehalten (`themeAccent`).
    .tint(model.appearancePalette.textPrimary)
  }

  /// Platzhalter bis Bibliotheken aus Bootstrap da sind — Tab-Struktur bleibt stabil.
  private var tabLibraryBootstrapPlaceholder: some View {
    Color.clear
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .abstandTabScreenChrome()
  }

  @ViewBuilder
  private func lazyTabContent<Content: View>(
    _ tab: AppModel.MainTab,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if activatedTabs.contains(tab) {
      content()
    } else {
      Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  // MARK: - Library tab

  private var libraryTabRoot: some View {
    BooksLibraryTabShell(
      toolbarState: booksLibraryToolbarState,
      catalog: { booksCatalogScrollView }
    )
    .id("books-library-tab-\(model.accountSessionEpoch)")
    .onAppear { booksLibraryToolbarState.attach(model) }
    .onDisappear { booksLibraryToolbarState.detach() }
  }

  private var booksCatalogScrollView: some View {
    AbstandFixedBrowseStripSectionsLayout(
      relayoutTrigger: libraryRelayoutEpoch,
      bottomInsetRevalidationTrigger: model.nowPlayingAccessoryScrollBottomInset,
      scrollToTopTrigger: model.libraryCatalogScrollToTopEpoch,
      selection: model.booksBrowseSection,
      sectionIDs: BooksBrowseSection.audiobookStripOrder,
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      onRefresh: { await model.refreshBooksCatalog() }
    ) {
      booksBrowseSectionStrip
    } sectionBody: { section in
      booksBrowseSectionScrollContent(for: section)
    }
  }

  private var booksBrowseSectionStrip: some View {
    let libraryItems = model.activeBookLibraries.map {
      AbstandBrowseStripItem(id: $0.id, label: $0.name, systemImage: "books.vertical.fill")
    }
    let librarySelectionID =
      model.focusedBooksLibrary?.id
      ?? model.selectedBooksLibrary?.id
      ?? libraryItems.first?.id
      ?? ""
    let sectionItems = BooksBrowseSection.audiobookStripOrder.map {
      AbstandBrowseStripItem(id: $0.rawValue, label: $0.title, systemImage: $0.systemImage)
    }
    return AbstandPinnedBrowseStrip(
      libraryPickerItems: libraryItems,
      libraryPickerSelectionID: librarySelectionID,
      onSelectLibrary: { id in
        guard let lib = model.activeBookLibraries.first(where: { $0.id == id }) else { return }
        model.focusBooksLibrary(lib)
      },
      secondaryItems: sectionItems,
      secondarySelectionID: model.booksBrowseSection.rawValue,
      onSelectSecondary: { id in
        if let section = BooksBrowseSection(rawValue: id) {
          model.selectBooksBrowseSection(section)
        }
      },
      secondaryAccessibilityLabel: "Browse",
      secondaryAccessibilityHint: "Chooses which catalog section to browse"
    )
  }

  @ViewBuilder
  private func booksBrowseSectionScrollContent(for section: BooksBrowseSection) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      booksBrowseSectionContent(for: section)
    }
  }

  @ViewBuilder
  private func booksBrowseSectionContent(for section: BooksBrowseSection) -> some View {
    switch section {
    case .books:
      booksCatalogBookListBody
    case .search:
      EmptyView()
    case .author:
      booksBrowseAuthorListBody
    case .narrators:
      booksBrowseNarratorListBody
    case .series:
      booksBrowseSeriesListBody
    case .collections:
      booksBrowseCollectionsListBody
    case .genres:
      booksBrowseGenresListBody
    case .tags:
      booksBrowseTagsListBody
    }
  }

  private var booksCatalogBookListBody: some View {
    let rows = model.booksForDisplay()
    return LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      // Immer „Audiobooks" — wie „New episodes" im Podcast-Tab. Welche Bibliothek gemeint
      // ist, sagt die Picker-Pill darüber.
      TabContentSectionTitle(title: BooksBrowseSection.books.title)
      if model.isLibraryCatalogFiltered {
        catalogFilterBanner
      }
      if model.isLoadingLibrary, rows.isEmpty {
        AbstandLoadingSpinner()
      } else if rows.isEmpty {
        // Empty-State (wie eBooks/Podcasts) — verhindert den „weißen" View, wenn die Liste
        // nach Filterwechsel, „Mark as finished" oder Progress-Sync leer wird.
        AbstandSectionEmptyState(text: "No books match the current filter.")
      } else if model.libraryBookCardStyle.usesMultiColumnGrid {
        libraryHeroMultiColumnBookRows(books: rows)
      } else {
        ForEach(rows) { book in
          libraryCatalogBookCard(book)
        }
      }
      // Listenende: weiterblättern, auch wenn die letzte Server-Seite nur reine eBooks enthielt.
      Color.clear
        .frame(height: AppTheme.Layout.hairlineWidth)
        .accessibilityHidden(true)
        .task(id: model.books.count) {
          await model.loadMoreAtCatalogEndIfNeeded()
        }
    }
  }

  // MARK: - eBooks tab

  private var ebooksTabRoot: some View {
    EbooksLibraryTabShell(
      toolbarState: ebooksLibraryToolbarState,
      catalog: { ebooksCatalogScrollView }
    )
    .id("ebooks-library-tab-\(model.accountSessionEpoch)")
    .onAppear { ebooksLibraryToolbarState.attach(model) }
    .onDisappear { ebooksLibraryToolbarState.detach() }
    // Erstes Öffnen und jeder Bibliothekswechsel (Picker, Tab-Wechsel auf Primary) laden die Listen.
    .task(id: "\(model.ebooksCatalogLibrary?.id ?? "")-\(model.offlineHomeUIActive)") {
      await model.ensureBrowseEbooksLoaded()
    }
  }

  private var ebooksCatalogScrollView: some View {
    AbstandFixedBrowseStripSectionsLayout(
      relayoutTrigger: ebooksRelayoutEpoch,
      bottomInsetRevalidationTrigger: model.nowPlayingAccessoryScrollBottomInset,
      scrollToTopTrigger: model.libraryCatalogScrollToTopEpoch,
      selection: ebooksBrowseSection,
      sectionIDs: EbooksBrowseSection.allCases,
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      onRefresh: { await model.refreshEbooksTab() }
    ) {
      ebooksBrowseSectionStrip
    } sectionBody: { section in
      ebooksSectionBody(for: section)
    }
  }

  private var ebooksBrowseSectionStrip: some View {
    // Eigener Fokus: ein Wechsel hier stellt den Audiobooks-Katalog nicht um.
    let pickerLibraries = model.ebooksPickerLibraries
    let libraryItems = pickerLibraries.map {
      AbstandBrowseStripItem(id: $0.id, label: $0.name, systemImage: "books.vertical.fill")
    }
    let librarySelectionID =
      model.focusedEbooksLibrary?.id
      ?? model.selectedEbooksLibrary?.id
      ?? libraryItems.first?.id
      ?? ""
    let sectionItems = EbooksBrowseSection.allCases.map {
      AbstandBrowseStripItem(id: $0.rawValue, label: $0.title, systemImage: $0.systemImage)
    }
    return AbstandPinnedBrowseStrip(
      libraryPickerItems: libraryItems,
      libraryPickerSelectionID: librarySelectionID,
      onSelectLibrary: { id in
        guard let lib = pickerLibraries.first(where: { $0.id == id }) else { return }
        model.focusEbooksLibrary(lib)
      },
      secondaryItems: sectionItems,
      secondarySelectionID: ebooksBrowseSection.rawValue,
      onSelectSecondary: { id in
        if let section = EbooksBrowseSection(rawValue: id) {
          ebooksBrowseSection = section
        }
      },
      secondaryAccessibilityLabel: "Browse",
      secondaryAccessibilityHint: "Chooses which eBook list to browse"
    )
  }

  /// eBooks-Tab: reine eBooks bzw. Hörbücher mit angehängtem eBook — immer mit Leerzustand.
  @ViewBuilder
  private func ebooksSectionBody(for section: EbooksBrowseSection) -> some View {
    let rows = section == .ebooks ? model.ebooksTabPureRows() : model.ebooksTabAudiobookRows()
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      TabContentSectionTitle(title: section.title)
      if model.browseEbooksLoading, rows.isEmpty {
        AbstandLoadingSpinner()
      } else if rows.isEmpty {
        AbstandSectionEmptyState(text: ebooksEmptyStateText(for: section))
      } else {
        ebookCards(rows, loadsMore: section == .ebooks)
      }
    }
  }

  private func ebooksEmptyStateText(for section: EbooksBrowseSection) -> String {
    if model.ebookCatalogQuickFilter != nil {
      return section == .ebooks
        ? "No eBooks match the current filter."
        : "No audiobooks with an eBook match the current filter."
    }
    if model.offlineHomeUIActive {
      return section == .ebooks
        ? "No downloaded eBooks."
        : "No downloaded eBooks that belong to an audiobook."
    }
    return section == .ebooks
      ? "No eBooks in this library."
      : "No audiobooks with an eBook in this library."
  }

  @ViewBuilder
  private func ebookCards(_ books: [ABSBook], loadsMore: Bool) -> some View {
    if model.libraryBookCardStyle.usesMultiColumnGrid {
      LibraryHeroMultiColumnRows(
        items: books,
        columns: model.libraryBookCardStyle.phoneGridColumns,
        spacing: AppTheme.Layout.withinSectionSpacing
      ) { book in
        ebookCard(book, loadsMore: loadsMore)
      }
    } else {
      ForEach(books) { book in
        ebookCard(book, loadsMore: loadsMore)
      }
    }
  }

  private func ebookCard(_ book: ABSBook, loadsMore: Bool) -> some View {
    LibraryBookListCard(
      book: book,
      model: model,
      // Kein `showEbookBadge:` — die Karte ermittelt das Badge selbst (einmal im Init).
      usesEbookProgressDisplay: true
    )
    .task(id: book.id) {
      guard loadsMore else { return }
      await model.loadMoreBrowseEbooksIfNeeded(currentItemId: book.id)
    }
  }

  private func libraryCatalogBookCard(_ book: ABSBook) -> some View {
    LibraryBookListCard(
      book: book,
      model: model
    )
    .task(id: book.id) {
      await model.loadMoreIfNeeded(currentItemId: book.id)
      model.prefetchUpcomingBookCovers(currentItemId: book.id)
    }
  }

  @ViewBuilder
  private func libraryHeroMultiColumnBookRows(books: [ABSBook]) -> some View {
    LibraryHeroMultiColumnRows(
      items: books,
      columns: model.libraryBookCardStyle.phoneGridColumns,
      spacing: AppTheme.Layout.withinSectionSpacing
    ) { book in
      libraryCatalogBookCard(book)
    }
  }

  private var catalogFilterBanner: some View {
    let palette = model.appearancePalette
    return HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
      Image(systemName: "line.3.horizontal.decrease.circle")
        .foregroundStyle(palette.textSecondary)
      Text(model.activeLibraryFilterSummary ?? "Library filtered")
        .font(.body)
        .foregroundStyle(palette.textPrimary)
        .lineLimit(2)
      Spacer(minLength: 0)
      Button("Show all") {
        model.clearCatalogFilter()
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(model.appearanceAccentColor)
    }
    .padding(.horizontal, AppTheme.Layout.tabPaddingH)
    .padding(.vertical, AppTheme.Layout.rowVerticalPadding)
    .background(palette.card)
    .clipShape(Capsule())
  }

  private var podcastsTabRoot: some View {
    PodcastCatalogTabShell(toolbarState: podcastCatalogToolbarState) {
      podcastCatalogScrollView
        .navigationDestination(item: $podcastDetailEpisode) { episode in
          PodcastEpisodeDetailView(episode: episode)
        }
    }
    .id("podcast-catalog-tab-\(model.accountSessionEpoch)")
    .onAppear { podcastCatalogToolbarState.attach(model) }
    .onDisappear { podcastCatalogToolbarState.detach() }
  }

  private static let podcastCatalogNewSectionId = PodcastCatalogStripSection.newEpisodes
  private static let podcastCatalogSearchSectionId = PodcastCatalogStripSection.search

  private var podcastCatalogScrollSectionIDs: [String] {
    [Self.podcastCatalogNewSectionId] + model.podcastShows.map(\.id)
  }

  private var podcastCatalogScrollSelection: String {
    model.podcastCatalogStripSectionId
  }

  private func podcastCatalogShowId(forSectionId sectionId: String) -> String? {
    sectionId == Self.podcastCatalogNewSectionId
      ? nil : sectionId
  }

  private var podcastCatalogScrollView: some View {
    AbstandFixedBrowseStripSectionsLayout(
      relayoutTrigger: podcastsRelayoutEpoch,
      bottomInsetRevalidationTrigger: model.nowPlayingAccessoryScrollBottomInset,
      selection: podcastCatalogScrollSelection,
      sectionIDs: podcastCatalogScrollSectionIDs,
      scrollBottomInset: AppTheme.Layout.scrollBottomInsetBase
        + model.nowPlayingAccessoryScrollBottomInset,
      onRefresh: { await model.refreshPodcastsTab() }
    ) {
      podcastShowsDockStrip
    } sectionBody: { sectionId in
      podcastCatalogSectionScrollContent(showId: podcastCatalogShowId(forSectionId: sectionId))
    }
  }

  @ViewBuilder
  private func podcastCatalogSectionScrollContent(showId: String?) -> some View {
    podcastPodcastsTabEpisodesContent(showId: showId)
  }

  private var podcastDockStripItems: [AbstandBrowseStripItem] {
    [
      AbstandBrowseStripItem(
        id: Self.podcastCatalogNewSectionId,
        label: "New",
        systemImage: "square.grid.2x2"
      ),
    ] + model.podcastShows.map { show in
      AbstandBrowseStripItem(
        id: show.id,
        label: show.displayTitle,
        systemImage: "mic.fill",
        coverItemId: show.id
      )
    }
  }

  private var podcastShowsDockStrip: some View {
    let _ = model.appearanceThemeRevision
    let libraryItems = model.activePodcastLibraries.map {
      AbstandBrowseStripItem(id: $0.id, label: $0.name, systemImage: "mic.fill")
    }
    let librarySelectionID =
      model.focusedPodcastLibrary?.id
      ?? model.selectedPodcastLibrary?.id
      ?? libraryItems.first?.id
      ?? ""
    return AbstandPinnedBrowseStrip(
      libraryPickerItems: libraryItems,
      libraryPickerSelectionID: librarySelectionID,
      onSelectLibrary: { id in
        guard let lib = model.activePodcastLibraries.first(where: { $0.id == id }) else { return }
        model.focusPodcastLibrary(lib)
      },
      secondaryItems: podcastDockStripItems,
      secondarySelectionID: podcastCatalogScrollSelection,
      // „New“ bleibt links stehen, die Sendungen scrollen darunter durch.
      pinnedLeadingItem: podcastDockStripItems.first,
      onSelectSecondary: { id in
        if id == Self.podcastCatalogNewSectionId {
          model.podcastCatalogStripSectionId = id
          Task { await model.selectPodcastShowFilter(nil) }
        } else {
          model.podcastCatalogStripSectionId = id
          model.applyPodcastShowFilterSelection(id)
          Task { await model.loadPodcastEpisodesForShowLibraryItem(id) }
        }
      },
      secondaryAccessibilityLabel: "Shows",
      secondaryAccessibilityHint: "Chooses which podcast show to browse"
    )
  }

  /// Titel über der Folgenliste im Podcast-Tab.
  private func podcastCatalogSectionTitle(showId: String?) -> String {
    guard let showId else { return "New episodes" }
    let show = model.podcastShows.first { $0.id == showId }
    let title = show?.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return title.isEmpty ? "Episodes" : title
  }

  @ViewBuilder
  private func podcastPodcastsTabEpisodesContent(showId: String?) -> some View {
    let _ = model.appearanceThemeRevision
    let episodes = model.podcastEpisodesForPodcastsTab(showId: showId)
    let isShowPane = showId != nil
    let isActivePane =
      isShowPane
      ? model.podcastSelectedShowId == showId
      : model.podcastSelectedShowId == nil
    let listLoading: Bool = {
      guard isActivePane else { return false }
      if isShowPane {
        return model.isLoadingPodcastShowEpisodes && episodes.isEmpty
      }
      return model.isLoadingPodcasts && episodes.isEmpty
    }()

    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      // Überschrift wie in den Browse-Sektionen: „New episodes" für den Sammelbereich,
      // sonst der Sendungstitel des gewählten Panels.
      TabContentSectionTitle(title: podcastCatalogSectionTitle(showId: showId))

      if listLoading {
        AbstandLoadingSpinner()
      } else if episodes.isEmpty {
        // Leerzustand — Bibliothek hat keine Folgen für diese Sendung bzw. der Feed ist leer.
        if isShowPane {
          AbstandSectionEmptyState(text: "No episodes in the library for this show.")
        } else {
          AbstandSectionEmptyState(
            text: "No episodes in the list. Pull to refresh or check your network."
          )
        }
      }

      if model.libraryPodcastCardStyle == .heroCover {
        LibraryHeroTwoColumnRows(
          items: episodes,
          spacing: AppTheme.Layout.withinSectionSpacing
        ) { episode in
          LibraryPodcastListCard(
            episode: episode,
            model: model,
            onOpenDetail: { podcastDetailEpisode = episode }
          )
            .task(id: episode.progressLookupKey) {
              if showId == nil {
                await model.loadMorePodcastsIfNeeded(currentItemId: episode.id)
              }
            }
        }
      } else {
        LibraryPodcastCardsFlow {
          ForEach(episodes, id: \.progressLookupKey) { episode in
            LibraryPodcastListCard(
              episode: episode,
              model: model,
              onOpenDetail: { podcastDetailEpisode = episode }
            )
              .task(id: episode.progressLookupKey) {
                if showId == nil {
                  await model.loadMorePodcastsIfNeeded(currentItemId: episode.id)
                }
              }
          }
        }
      }

      if isShowPane,
        isActivePane,
        model.isLoadingPodcastShowEpisodes,
        !episodes.isEmpty
      {
        AbstandLoadingSpinner(controlSize: .small, verticalPadding: AppTheme.Layout.rowVerticalPadding)
      }
    }
  }
}
