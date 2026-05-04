import SwiftUI
import UIKit

struct MainRootView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ZStack(alignment: .top) {
      AppTheme.background.ignoresSafeArea()
      VStack(spacing: 0) {
        MiniPlayerBar()
          .padding(12)
        TabView(selection: $model.mainTab) {
          StartDashboardView()
            .tabItem {
              Label(AppModel.MainTab.start.rawValue, systemImage: "house.fill")
            }
            .tag(AppModel.MainTab.start)

          VStack(spacing: 0) {
            if model.activeLibraryFilter != nil {
              catalogFilterBanner
            }
            catalogBookList
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .tabItem {
            Label(AppModel.MainTab.library.rawValue, systemImage: "books.vertical.fill")
          }
          .tag(AppModel.MainTab.library)

          VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
              tabContentSectionTitle("Search")
              searchFieldRow
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            if model.activeLibraryFilter != nil {
              catalogFilterBanner
            }
            SearchTabView()
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .tabItem {
            Label(AppModel.MainTab.search.rawValue, systemImage: "magnifyingglass")
          }
          .tag(AppModel.MainTab.search)

          AppSettingsRootView()
            .tabItem {
              Label(AppModel.MainTab.settings.rawValue, systemImage: "gearshape.fill")
            }
            .tag(AppModel.MainTab.settings)
        }
        .tint(AppTheme.accent)
      }
    }
    .sheet(isPresented: $model.showSleepPicker) {
      SleepTimerSheet()
        .presentationDetents([.height(320)])
    }
    .onChange(of: model.player.isPlaying) { _, playing in
      if !playing {
        Task {
          await model.syncProgressToServer()
          await model.loadStartDashboard()
        }
      }
    }
    .onChange(of: model.mainTab) { _, tab in
      if tab == .start, model.startShelves.isEmpty {
        Task { await model.loadStartDashboard() }
      }
      if tab == .search {
        model.scheduleSearch()
      }
      if tab == .settings {
        Task { await model.reloadSettingsTab() }
      }
    }
  }

  private var searchFieldRow: some View {
    HStack {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(AppTheme.textSecondary)
      TextField("Title, author, series…", text: $model.searchText)
        .foregroundStyle(AppTheme.textPrimary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onChange(of: model.searchText) { _, _ in
          model.scheduleSearch()
        }
      if !model.searchText.isEmpty {
        Button {
          model.searchText = ""
          model.clearSearchResults()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(AppTheme.textSecondary)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(AppTheme.card)
    .clipShape(Capsule())
    .padding(.bottom, 10)
  }

  private var catalogFilterBanner: some View {
    HStack(alignment: .center, spacing: 12) {
      Text("Filtered library")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
      Spacer(minLength: 0)
      Button("Show all") {
        model.clearCatalogFilter()
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(AppTheme.accent)
    }
    .padding(.horizontal, 14)
    .padding(.top, 12)
    .padding(.bottom, 10)
    .background(AppTheme.card)
    .clipShape(Capsule())
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 8)
  }

  private var catalogBookList: some View {
    let rows = model.booksForDisplay()
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        tabContentSectionTitle(AppModel.MainTab.library.rawValue)
        ForEach(rows) { book in
          BookRowCard(book: book)
            .task(id: book.id) {
              await model.loadMoreIfNeeded(currentItemId: book.id)
            }
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 16)
      .padding(.bottom, 24)
    }
  }
}

/// Kleine Kategoriezeile wie auf Home (`shelf.displayTitle`).
private func tabContentSectionTitle(_ title: String) -> some View {
  Text(title)
    .font(.caption.weight(.bold))
    .foregroundStyle(AppTheme.textSecondary)
    .textCase(.uppercase)
    .tracking(0.6)
}

// MARK: - Home dashboard

private struct StartDashboardView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 22) {
        let hasHomeDownloads =
          !model.downloadedItemIds.isEmpty || model.downloads.activeItemId != nil
        let showStartEmpty =
          model.startShelves.isEmpty && model.startBooks.isEmpty && !hasHomeDownloads
            && model.downloadedTitlesForHome.isEmpty
        if showStartEmpty {
          startDashboardEmptyVisual
            .frame(maxWidth: .infinity)
            .padding(32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(startDashboardEmptyAccessibility)
        }
        if hasHomeDownloads {
          VStack(alignment: .leading, spacing: 12) {
            tabContentSectionTitle("Heruntergeladen")
            ForEach(model.downloadedTitlesForHome) { book in
              BookRowCard(book: book)
            }
          }
        }
        ForEach(model.startShelves) { shelf in
          VStack(alignment: .leading, spacing: 12) {
            if shelf.hasBooks || shelf.hasAuthors {
              tabContentSectionTitle(shelf.displayTitle)
            }

            if shelf.hasBooks {
              ForEach(shelf.books) { book in
                BookRowCard(book: book)
              }
            }

            if shelf.hasAuthors {
              ForEach(shelf.authors) { author in
                Button {
                  model.applyAuthorFilter(authorId: author.id)
                } label: {
                  HStack {
                    Text(author.name)
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(AppTheme.textPrimary)
                      .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(AppTheme.textSecondary)
                  }
                  .padding(14)
                  .background(AppTheme.card)
                  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 16)
      .padding(.bottom, 24)
    }
  }

  private var startDashboardAllShelvesDisabled: Bool {
    let cats = model.startSettingsCategoryList.map(\.category)
    let basis = cats.isEmpty ? ABSStartShelfLocalization.settingsCategoryOrder : cats
    return basis.allSatisfy { !model.isStartCategoryEnabled($0) }
  }

  @ViewBuilder
  private var startDashboardEmptyVisual: some View {
    Image(
      systemName: startDashboardAllShelvesDisabled
        ? "gearshape.2"
        : "books.vertical"
    )
    .font(.system(size: 44, weight: .light))
    .foregroundStyle(AppTheme.textSecondary.opacity(0.45))
    .symbolRenderingMode(.hierarchical)
  }

  private var startDashboardEmptyAccessibility: String {
    if startDashboardAllShelvesDisabled {
      return
        "Alle Start-Regale sind in den Einstellungen ausgeschaltet. Tippe auf das Zahnrad, um Regale wieder anzuzeigen."
    }
    return
      "Hier erscheinen personalisierte Regale, sobald der Server dazu Daten liefert."
  }
}

// MARK: - Settings sheet

/// Eigenes Sheet statt `Menu`: lange UIMenu-Listen scrollen oft mit Layout-Flackern.
private struct CatalogSortFieldPickerSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(CatalogSortField.allCases) { field in
            Button {
              model.catalogSortField = field
              dismiss()
              Task { await model.reloadLibrary(reset: true) }
            } label: {
              HStack(alignment: .center, spacing: 12) {
                Text(field.menuTitle)
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.textPrimary)
                  .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if model.catalogSortField == field {
                  Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(AppTheme.accent)
                }
              }
              .padding(14)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(AppTheme.card)
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
      }
      .background(AppTheme.background)
      .navigationTitle("Sort by")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(AppTheme.background, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
            .foregroundStyle(AppTheme.accent)
        }
      }
    }
    .tint(AppTheme.accent)
    .preferredColorScheme(.dark)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}

private struct AppSettingsRootView: View {
  @EnvironmentObject private var model: AppModel
  @State private var showCatalogSortPicker = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 10) {
            settingsSheetSectionTitle("Libraries")

            VStack(spacing: 10) {
              if model.libraries.isEmpty {
                Text("No audiobook libraries on this server.")
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.textSecondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(14)
                  .background(AppTheme.card)
                  .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              } else {
                ForEach(model.sortedLibraries) { lib in
                  Button {
                    model.selectLibrary(lib, navigateToCatalog: true)
                    Task { await model.reloadLibrary(reset: true) }
                  } label: {
                    HStack {
                      Text(lib.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                      Spacer()
                      if model.selectedLibrary?.id == lib.id {
                        Image(systemName: "checkmark.circle.fill")
                          .font(.body)
                          .foregroundStyle(AppTheme.accent)
                      }
                    }
                    .padding(14)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            settingsSheetSectionTitle("Catalog order")

            VStack(spacing: 0) {
              HStack(alignment: .center, spacing: 12) {
                Text("Sort by")
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 8)
                Button {
                  showCatalogSortPicker = true
                } label: {
                  HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.catalogSortField.menuTitle)
                      .font(.subheadline)
                      .foregroundStyle(AppTheme.textPrimary)
                      .lineLimit(2)
                      .minimumScaleFactor(0.85)
                      .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                      .font(.caption2.weight(.semibold))
                      .foregroundStyle(AppTheme.textSecondary)
                  }
                  .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 12)

              Divider()
                .background(AppTheme.textSecondary.opacity(0.2))
                .padding(.leading, 14)

              HStack(alignment: .center, spacing: 12) {
                Text("Direction")
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                  Button {
                    model.catalogSortDescending = false
                    Task { await model.reloadLibrary(reset: true) }
                  } label: {
                    Text("Ascending")
                      .font(.subheadline)
                      .foregroundStyle(
                        model.catalogSortField == .random
                          ? AppTheme.textSecondary : AppTheme.textPrimary
                      )
                      .padding(.horizontal, 12)
                      .padding(.vertical, 8)
                      .background(
                        model.catalogSortField != .random && !model.catalogSortDescending
                          ? AppTheme.accent.opacity(0.3)
                          : AppTheme.card.opacity(0.45)
                      )
                      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                  }
                  .buttonStyle(.plain)
                  .disabled(model.catalogSortField == .random)

                  Button {
                    model.catalogSortDescending = true
                    Task { await model.reloadLibrary(reset: true) }
                  } label: {
                    Text("Descending")
                      .font(.subheadline)
                      .foregroundStyle(
                        model.catalogSortField == .random
                          ? AppTheme.textSecondary : AppTheme.textPrimary
                      )
                      .padding(.horizontal, 12)
                      .padding(.vertical, 8)
                      .background(
                        model.catalogSortField != .random && model.catalogSortDescending
                          ? AppTheme.accent.opacity(0.3)
                          : AppTheme.card.opacity(0.45)
                      )
                      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                  }
                  .buttonStyle(.plain)
                  .disabled(model.catalogSortField == .random)
                }
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 12)
            }
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          }

          VStack(alignment: .leading, spacing: 10) {
            settingsSheetSectionTitle("Home shelves")

            VStack(spacing: 0) {
              ForEach(
                Array(model.startSettingsCategoryList.enumerated()),
                id: \.element.category
              ) { index, row in
                Toggle(
                  row.label,
                  isOn: Binding(
                    get: { model.isStartCategoryEnabled(row.category) },
                    set: { model.setStartCategoryEnabled(row.category, enabled: $0) }
                  )
                )
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .tint(AppTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                if index < model.startSettingsCategoryList.count - 1 {
                  Divider()
                    .background(AppTheme.textSecondary.opacity(0.2))
                    .padding(.leading, 14)
                }
              }
            }
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          }

          VStack(alignment: .leading, spacing: 10) {
            settingsSheetSectionTitle("Account")
            Button {
              model.logout()
            } label: {
              Text("Log out")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .foregroundStyle(AppTheme.danger)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 24)
      }
      .background(AppTheme.background)
      .sheet(isPresented: $showCatalogSortPicker) {
        CatalogSortFieldPickerSheet()
          .environmentObject(model)
      }
      .tint(AppTheme.accent)
  }
}

private func settingsSheetSectionTitle(_ title: String) -> some View {
  Text(title)
    .font(.caption.weight(.bold))
    .foregroundStyle(AppTheme.textSecondary)
    .textCase(.uppercase)
    .tracking(0.6)
}

// MARK: - Search tab

private struct SearchTabView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    let q = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        if model.isLoadingLibrary, q.count >= 2 {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding()
        }
        if q.count > 0, q.count < 2 {
          Text("Enter at least two characters.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(24)
        }
        if q.count >= 2, !model.isLoadingLibrary, model.searchBooks.isEmpty,
          model.searchAuthors.isEmpty, model.searchNarrators.isEmpty, model.searchSeries.isEmpty,
          model.searchTags.isEmpty, model.searchGenres.isEmpty
        {
          Text("No results.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(24)
        }

        searchSection(title: "Books", isEmpty: model.searchBooks.isEmpty) {
          ForEach(model.searchBooks) { book in
            BookRowCard(book: book)
          }
        }
        searchSection(title: "Authors", isEmpty: model.searchAuthors.isEmpty) {
          ForEach(model.searchAuthors) { a in
            searchNavRow(title: a.name, subtitle: a.numBooks.map { "\($0) titles" }) {
              model.applyAuthorFilter(authorId: a.id)
            }
          }
        }
        searchSection(title: "Series", isEmpty: model.searchSeries.isEmpty) {
          ForEach(model.searchSeries) { s in
            searchNavRow(title: s.name, subtitle: nil) {
              model.applySeriesFilter(seriesId: s.id)
            }
          }
        }
        searchSection(title: "Narrators", isEmpty: model.searchNarrators.isEmpty) {
          ForEach(model.searchNarrators) { n in
            searchNavRow(title: n.name, subtitle: n.numBooks.map { "\($0) titles" }) {
              model.applyNarratorFilter(narratorName: n.name)
            }
          }
        }
        searchSection(title: "Tags", isEmpty: model.searchTags.isEmpty) {
          ForEach(model.searchTags) { t in
            searchNavRow(title: t.name, subtitle: t.numItems.map { "\($0)" }) {
              model.applyTagFilter(tagName: t.name)
            }
          }
        }
        searchSection(title: "Genres", isEmpty: model.searchGenres.isEmpty) {
          ForEach(model.searchGenres) { g in
            searchNavRow(title: g.name, subtitle: g.numItems.map { "\($0)" }) {
              model.applyGenreFilter(genreName: g.name)
            }
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)
      .padding(.bottom, 24)
    }
  }

  @ViewBuilder
  private func searchSection<Content: View>(
    title: String,
    isEmpty: Bool,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if !isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        tabContentSectionTitle(title)
        content()
      }
    }
  }
}

private extension SearchTabView {
  @ViewBuilder
  func searchNavRow(title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(AppTheme.textSecondary)
          }
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppTheme.textSecondary)
      }
      .padding(14)
      .background(AppTheme.card)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Mini player slider (global UISlider thumb; only one Slider in app)

private enum MiniPlayerSliderThumb {
  private static var didApply = false

  static func applyOnce() {
    guard !didApply else { return }
    didApply = true
    let d: CGFloat = 12
    let size = CGSize(width: d, height: d)
    let img = UIGraphicsImageRenderer(size: size).image { ctx in
      UIColor.white.setFill()
      ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
    }
    UISlider.appearance().setThumbImage(img, for: .normal)
    UISlider.appearance().setThumbImage(img, for: .highlighted)
  }
}

// MARK: - Mini Player

/// Bibliothekszeile: 76×76; Mini-Player-Cover = 1,5×
private let miniPlayerCoverSide: CGFloat = 76 * 1.5
private let miniPlayerControlMinHeight: CGFloat = 30
private let miniPlayerControlCorner: CGFloat = 7

/// Umrandete Mini-Player-Steuerung, gleich breit in der Zeile.
private struct MiniPlayerOutlinedButtonStyle: ButtonStyle {
  var accentBorder: Bool = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      // SF Symbols melden sonst kurz eine extreme Idealgröße → Mini-Player bläht auf.
      .fixedSize(horizontal: true, vertical: true)
      .frame(maxWidth: .infinity)
      .frame(height: miniPlayerControlMinHeight, alignment: .center)
      .background(
        RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous)
          .fill(accentBorder ? AppTheme.accent.opacity(0.12) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous)
          .stroke(
            accentBorder
              ? AppTheme.accent.opacity(isEnabled ? 0.55 : 0.22)
              : AppTheme.textSecondary.opacity(isEnabled ? 0.42 : 0.22),
            lineWidth: 1
          )
      )
      .opacity(
        isEnabled
          ? (configuration.isPressed ? 0.72 : 1)
          : 0.38
      )
      .contentShape(RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous))
  }
}

@ViewBuilder
private func miniPlayerPlaceholderControlCell(
  _ label: some View,
  accentBorder: Bool = false
) -> some View {
  label
    .fixedSize(horizontal: true, vertical: true)
    .foregroundStyle(
      accentBorder ? AppTheme.accent.opacity(0.35) : AppTheme.textSecondary.opacity(0.35)
    )
    .frame(maxWidth: .infinity)
    .frame(height: miniPlayerControlMinHeight, alignment: .center)
    .background(
      RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous)
        .fill(accentBorder ? AppTheme.accent.opacity(0.08) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous)
        .stroke(
          accentBorder
            ? AppTheme.accent.opacity(0.22)
            : AppTheme.textSecondary.opacity(0.22),
          lineWidth: 1
        )
    )
}

/// Umrandete Aktions-Buttons (Bibliothekskarte), optisch an den Mini-Player angelehnt.
private struct LibraryCardActionButtonStyle: ButtonStyle {
  enum Variant {
    case neutral
    case accent
    case danger
  }

  var variant: Variant = .neutral
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let stroke: Color = {
      switch variant {
      case .neutral:
        return AppTheme.textSecondary.opacity(isEnabled ? 0.42 : 0.22)
      case .accent:
        return AppTheme.accent.opacity(isEnabled ? 0.55 : 0.22)
      case .danger:
        return AppTheme.danger.opacity(isEnabled ? 0.55 : 0.22)
      }
    }()
    let fill: Color = {
      switch variant {
      case .neutral: return .clear
      case .accent: return AppTheme.accent.opacity(0.12)
      case .danger: return AppTheme.danger.opacity(0.12)
      }
    }()

    return configuration.label
      .fixedSize(horizontal: true, vertical: true)
      .frame(maxWidth: .infinity)
      .frame(height: miniPlayerControlMinHeight, alignment: .center)
      .background(
        RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous)
          .fill(fill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous)
          .stroke(stroke, lineWidth: 1)
      )
      .opacity(
        isEnabled
          ? (configuration.isPressed ? 0.72 : 1)
          : 0.38
      )
      .contentShape(RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous))
  }
}

struct MiniPlayerBar: View {
  @EnvironmentObject private var model: AppModel
  @State private var scrubLocal: Double?

  private var showIdlePlaceholder: Bool {
    model.player.showMiniPlayerPlaceholder && model.player.activeBook == nil
  }

  var body: some View {
    let book = model.player.activeBook
    let pos = scrubLocal ?? model.player.globalPosition
    let dur = max(model.player.totalDuration, 1)

    VStack(alignment: .leading, spacing: 0) {
      if let b = book {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
              Text(b.displayTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
              Text(b.displayAuthors)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
              if model.player.chapterCount > 0 {
                let counter = String(
                  format: "%03d/%03d",
                  model.player.currentChapterOrdinal,
                  model.player.chapterCount
                )
                let chapterName = model.player.currentChapterTitle
                  .trimmingCharacters(in: .whitespacesAndNewlines)
                (
                  Text(counter).monospacedDigit()
                    + (chapterName.isEmpty
                      ? Text(verbatim: "")
                      : Text(" - ") + Text(chapterName))
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
              }

              VStack(alignment: .leading, spacing: 2) {
                Slider(
                  value: Binding(
                    get: { pos },
                    set: { scrubLocal = $0 }
                  ),
                  in: 0 ... dur,
                  onEditingChanged: { editing in
                    if !editing, let s = scrubLocal {
                      model.player.seek(global: s)
                      scrubLocal = nil
                    }
                  }
                )
                .tint(AppTheme.accent)
                .controlSize(.mini)

                if let sleepEnd = model.player.sleepEndDate, sleepEnd > Date() {
                  TimelineView(.periodic(from: .now, by: 1)) { context in
                    ZStack {
                      HStack(spacing: 0) {
                        Text(formatPlaybackTime(pos))
                          .foregroundStyle(AppTheme.textSecondary)
                          .frame(maxWidth: .infinity, alignment: .leading)
                        Text(formatPlaybackTime(dur))
                          .foregroundStyle(AppTheme.textSecondary)
                          .frame(maxWidth: .infinity, alignment: .trailing)
                      }
                      if sleepEnd > context.date {
                        Text(formatPlaybackTime(sleepEnd.timeIntervalSince(context.date)))
                          .font(.caption2.monospacedDigit().weight(.medium))
                          .foregroundStyle(AppTheme.accent)
                      }
                    }
                    .font(.caption2.monospacedDigit())
                  }
                } else {
                  HStack(spacing: 0) {
                    Text(formatPlaybackTime(pos))
                      .foregroundStyle(AppTheme.textSecondary)
                      .frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatPlaybackTime(dur))
                      .foregroundStyle(AppTheme.textSecondary)
                      .frame(maxWidth: .infinity, alignment: .trailing)
                  }
                  .font(.caption2.monospacedDigit())
                }
              }
              .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, minHeight: miniPlayerCoverSide, alignment: .top)

            Button {
              model.player.togglePlayPause()
            } label: {
              ZStack(alignment: .bottomTrailing) {
                CoverImageView(url: model.coverURL(for: b.id), token: model.token)
                  .frame(width: miniPlayerCoverSide, height: miniPlayerCoverSide)
                  .clipped()
                Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                  .font(.callout)
                  .foregroundStyle(.white)
                  .frame(width: 34, height: 34)
                  .background(AppTheme.accent)
                  .clipShape(Circle())
                  .padding(6)
              }
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.player.isPlaying ? "Pause" : "Play")
          }

          HStack(spacing: 6) {
            Group {
              if model.player.chapterCount > 0 {
                Button { model.player.skipToPreviousChapter() } label: {
                  Image(systemName: "backward.end.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(MiniPlayerOutlinedButtonStyle())
                .disabled(!model.player.canSkipToPreviousChapter)
                .accessibilityLabel("Previous chapter")
              } else {
                Color.clear
                  .frame(maxWidth: .infinity)
                  .frame(height: miniPlayerControlMinHeight)
                  .overlay(
                    RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous)
                      .stroke(AppTheme.textSecondary.opacity(0.22), lineWidth: 1)
                  )
                  .accessibilityHidden(true)
              }
            }

            Button { model.player.skip(seconds: -15) } label: {
              Image(systemName: "gobackward.15")
                .font(.callout)
                .foregroundStyle(AppTheme.textPrimary)
            }
            .buttonStyle(MiniPlayerOutlinedButtonStyle())

            Group {
              if model.player.sleepEndDate != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                  let sleepOn =
                    (model.player.sleepEndDate ?? .distantPast) > context.date
                  Button { model.showSleepPicker = true } label: {
                    Image(systemName: "moon.fill")
                      .font(.callout)
                      .foregroundStyle(sleepOn ? AppTheme.accent : AppTheme.textPrimary)
                  }
                  .buttonStyle(MiniPlayerOutlinedButtonStyle(accentBorder: sleepOn))
                  .accessibilityLabel("Sleep timer")
                }
                .frame(maxWidth: .infinity, minHeight: miniPlayerControlMinHeight, maxHeight: miniPlayerControlMinHeight)
              } else {
                Button { model.showSleepPicker = true } label: {
                  Image(systemName: "moon.fill")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(MiniPlayerOutlinedButtonStyle())
                .accessibilityLabel("Sleep timer")
              }
            }

            Button { model.player.skip(seconds: 30) } label: {
              Image(systemName: "goforward.30")
                .font(.callout)
                .foregroundStyle(AppTheme.textPrimary)
            }
            .buttonStyle(MiniPlayerOutlinedButtonStyle())

            Group {
              if model.player.chapterCount > 0 {
                Button { model.player.skipToNextChapter() } label: {
                  Image(systemName: "forward.end.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(MiniPlayerOutlinedButtonStyle())
                .disabled(!model.player.canSkipToNextChapter)
                .accessibilityLabel("Next chapter")
              } else {
                Color.clear
                  .frame(maxWidth: .infinity)
                  .frame(height: miniPlayerControlMinHeight)
                  .overlay(
                    RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous)
                      .stroke(AppTheme.textSecondary.opacity(0.22), lineWidth: 1)
                  )
                  .accessibilityHidden(true)
              }
            }
          }
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)
        }
      } else if model.isRestoringLaunchPlayback {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Wiedergabe")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
              Text("Letzte Position wird geladen …")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
              VStack(alignment: .leading, spacing: 2) {
                ProgressView()
                  .controlSize(.small)
                  .tint(AppTheme.accent)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.vertical, 8)
                HStack(spacing: 6) {
                  Text("0:00")
                    .font(.caption2.monospacedDigit())
                  Spacer(minLength: 0)
                  Text("—")
                    .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
              }
              .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, minHeight: miniPlayerCoverSide, alignment: .top)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(AppTheme.textSecondary.opacity(0.12))
              .frame(width: miniPlayerCoverSide, height: miniPlayerCoverSide)
              .overlay {
                ProgressView()
                  .tint(AppTheme.accent)
              }
              .accessibilityHidden(true)
          }

          HStack(spacing: 6) {
            miniPlayerPlaceholderControlCell(
              Image(systemName: "backward.end.fill")
                .font(.caption2.weight(.semibold))
            )
            miniPlayerPlaceholderControlCell(
              Image(systemName: "gobackward.15").font(.callout)
            )
            miniPlayerPlaceholderControlCell(
              Image(systemName: "moon.fill").font(.callout),
              accentBorder: true
            )
            miniPlayerPlaceholderControlCell(
              Image(systemName: "goforward.30").font(.callout)
            )
            miniPlayerPlaceholderControlCell(
              Image(systemName: "forward.end.fill")
                .font(.caption2.weight(.semibold))
            )
          }
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wiedergabe wird geladen.")
      } else if showIdlePlaceholder {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Keine Wiedergabe")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
              Text("Wähle ein anderes Hörbuch in der Bibliothek.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
              VStack(alignment: .leading, spacing: 2) {
                Slider(value: .constant(0), in: 0 ... 1)
                  .tint(AppTheme.accent.opacity(0.35))
                  .controlSize(.mini)
                  .disabled(true)
                HStack(spacing: 6) {
                  Text("0:00")
                    .font(.caption2.monospacedDigit())
                  Spacer(minLength: 0)
                  Text("0:00")
                    .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
              }
              .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, minHeight: miniPlayerCoverSide, alignment: .top)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(AppTheme.textSecondary.opacity(0.12))
              .frame(width: miniPlayerCoverSide, height: miniPlayerCoverSide)
              .overlay {
                Image(systemName: "waveform")
                  .font(.title2)
                  .foregroundStyle(AppTheme.textSecondary.opacity(0.45))
              }
              .accessibilityHidden(true)
          }

          HStack(spacing: 6) {
            miniPlayerPlaceholderControlCell(
              Image(systemName: "backward.end.fill")
                .font(.caption2.weight(.semibold))
            )
            miniPlayerPlaceholderControlCell(
              Image(systemName: "gobackward.15").font(.callout)
            )
            miniPlayerPlaceholderControlCell(
              Image(systemName: "moon.fill").font(.callout),
              accentBorder: true
            )
            miniPlayerPlaceholderControlCell(
              Image(systemName: "goforward.30").font(.callout)
            )
            miniPlayerPlaceholderControlCell(
              Image(systemName: "forward.end.fill")
                .font(.caption2.weight(.semibold))
            )
          }
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keine Wiedergabe. Wähle ein Hörbuch in der Bibliothek.")
      }
    }
    .padding(12)
    .background(model.player.miniPlayerBarFillColor)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onAppear {
      MiniPlayerSliderThumb.applyOnce()
    }
  }
}

// MARK: - Book row

private let bookRowCoverSide: CGFloat = 76

struct BookRowCard: View {
  @EnvironmentObject private var model: AppModel
  let book: ABSBook
  @State private var confirmDelete = false

  private var expanded: Bool { model.expandedItemId == book.id }
  private var detail: ABSBook? { expanded ? (model.expandedDetail ?? book) : book }
  private var prog: ABSUserMediaProgress? { model.progressByItemId[book.id] }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 10) {
        Button {
          Task { await model.play(book: book) }
        } label: {
          ZStack(alignment: .bottomTrailing) {
            CoverImageView(url: model.coverURL(for: book.id), token: model.token)
              .frame(width: bookRowCoverSide, height: bookRowCoverSide)
              .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            Image(systemName: "play.fill")
              .font(.system(size: 7, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 18, height: 18)
              .background(Color(white: 0.38, opacity: 0.88))
              .clipShape(Circle())
              .padding(4)
              .accessibilityHidden(true)
          }
          .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abspielen")
        .accessibilityHint("Startet die Wiedergabe dieses Hörbuchs.")

        Button {
          Task { await model.expandItem(book.id) }
        } label: {
          ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
              Text(book.displayTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
              Text(book.displayAuthors)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.trailing, 4)

            VStack(alignment: .leading, spacing: 4) {
              if let p = prog, !p.isFinished, p.duration > 0 {
                ProgressView(value: min(1, max(0, p.progress)))
                  .tint(AppTheme.accent)
                  .scaleEffect(x: 1, y: 1.15, anchor: .center)
              }
              HStack(spacing: 8) {
                Text(formatPlaybackTime(book.media.duration ?? 0))
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(AppTheme.textSecondary)
                if prog?.isFinished == true {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
                    .font(.caption)
                }
                downloadIcon
                Spacer(minLength: 0)
              }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          }
          .frame(height: bookRowCoverSide)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Details ausblenden" : "Details einblenden")
      }
      .padding(.leading, 6)
      .padding(.trailing, 14)
      .padding(.top, 8)
      .padding(.bottom, 8)

      if expanded, let d = detail {
        expandedBlock(d)
      }
    }
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .confirmationDialog(
      "Remove this audiobook from the library?",
      isPresented: $confirmDelete,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        Task { await model.deleteFromServer(bookId: book.id) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The library item will be deleted on the server.")
    }
  }

  @ViewBuilder
  private var downloadIcon: some View {
    if model.downloadedItemIds.contains(book.id) {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(AppTheme.accent)
        .font(.caption)
        .accessibilityLabel("Saved offline")
    } else if model.downloads.activeItemId == book.id {
      ProgressView(value: model.downloads.progress)
        .frame(width: 36)
        .tint(AppTheme.accent)
        .accessibilityLabel("Downloading")
    }
  }

  @ViewBuilder
  private func expandedBlock(_ d: ABSBook) -> some View {
    let m = d.media.metadata
    let rowProgress = model.progressByItemId[d.id]
    let isFinished = rowProgress?.isFinished == true

    VStack(alignment: .leading, spacing: 8) {
      Divider().background(AppTheme.textSecondary.opacity(0.2))
      metaRow("Narrator", (m.narratorName ?? m.narrators?.joined(separator: ", ")) ?? "—")
      if let seriesLine = m.resolvedSeriesDisplay {
        metaRow("Series", seriesLine)
      }
      metaRow("Year", m.publishedYear ?? "—")
      metaRow("Publisher", m.publisher ?? "—")
      metaRow("Categories", (m.genres ?? []).joined(separator: ", ").nilIfEmpty ?? "—")
      metaRow(
        "Description",
        absPlainText(fromHTML: m.descriptionPlain ?? m.description).nilIfEmpty ?? "—")

      HStack(spacing: 8) {
        Group {
          if model.downloads.activeItemId == d.id {
            ZStack {
              RoundedRectangle(cornerRadius: miniPlayerControlCorner, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.45), lineWidth: 1)
              ProgressView(value: model.downloads.progress)
                .tint(AppTheme.accent)
                .scaleEffect(x: 1, y: 1.1, anchor: .center)
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: miniPlayerControlMinHeight)
            .accessibilityLabel("Download läuft")
          } else if model.downloadedItemIds.contains(d.id) {
            Button {
              model.removeLocalDownload(bookId: d.id)
            } label: {
              Image(systemName: "arrow.down.circle.badge.xmark")
                .font(.callout)
                .foregroundStyle(AppTheme.textPrimary)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .neutral))
            .accessibilityLabel("Offline-Daten löschen")
          } else {
            Button {
              model.startDownload(book: d)
            } label: {
              Image(systemName: "arrow.down.circle")
                .font(.callout)
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(LibraryCardActionButtonStyle(variant: .accent))
            .accessibilityLabel("Herunterladen")
          }
        }
        .frame(maxWidth: .infinity)

        Button {
          Task {
            if isFinished {
              await model.markUnfinished(bookId: d.id)
            } else {
              await model.markFinished(bookId: d.id)
            }
          }
        } label: {
          Image(systemName: isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle")
            .font(.callout)
            .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.textPrimary)
        }
        .buttonStyle(LibraryCardActionButtonStyle(variant: isFinished ? .accent : .neutral))
        .accessibilityLabel(isFinished ? "Als nicht fertig markieren" : "Als fertig markieren")

        Button(role: .destructive) {
          confirmDelete = true
        } label: {
          Image(systemName: "trash.fill")
            .font(.callout)
            .foregroundStyle(AppTheme.danger)
        }
        .buttonStyle(LibraryCardActionButtonStyle(variant: .danger))
        .accessibilityLabel("Titel löschen")
      }
      .frame(maxWidth: .infinity)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 8)
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
  }

  private func metaRow(_ k: String, _ v: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(k.uppercased())
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .frame(width: 112, alignment: .leading)
      Text(v)
        .font(.subheadline)
        .foregroundStyle(AppTheme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Sleep timer

struct SleepTimerSheet: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    NavigationStack {
      List {
        Button("Off") { model.applySleepTimer(minutes: nil) }
        Button("15 Min") { model.applySleepTimer(minutes: 15) }
        Button("30 Min") { model.applySleepTimer(minutes: 30) }
        Button("45 Min") { model.applySleepTimer(minutes: 45) }
        Button("60 Min") { model.applySleepTimer(minutes: 60) }
      }
      .navigationTitle("Sleep timer")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { model.showSleepPicker = false }
        }
      }
    }
  }
}
