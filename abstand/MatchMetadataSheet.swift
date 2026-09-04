import SwiftUI

/// Match-Metadaten-Sheet (absorb-style): Online-Suche über `/api/search/books`,
/// Trefferliste mit Vorschau, pro-Feld-Auswahl vor dem Apply (`PATCH /api/items/:id/media` + optional Cover).
/// Nur für Admin-oder-Root-User (`model.isServerAdmin || model.isServerRoot`).
/// Chrome (Sektionen, Karten, Felder): `MetadataSheetComponents` — gleiche Sprache wie Buch-Detail.
struct MatchMetadataSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.themeAccent) private var themeAccent

  let itemId: String
  let currentTitle: String
  let currentAuthor: String?

  // Such-State
  @State private var titleQuery: String = ""
  @State private var authorQuery: String = ""
  @State private var provider: String = "audible"
  @State private var providers: [ABSMetadataProvider] = []
  @State private var results: [ABSMetadataMatch] = []
  @State private var isSearching = false
  @State private var hasSearched = false
  @State private var searchError: String?

  // Apply-State
  @State private var selectedMatch: ABSMetadataMatch?
  @State private var selectedFields: Set<ABSMatchField> = Set(ABSMatchField.allCases)
  @State private var isApplying = false
  @State private var applyError: String?
  /// Nach erfolgreichem Apply erst Unter-Sheet schließen, dann Haupt-Sheet — nicht beides gleichzeitig.
  @State private var dismissSheetAfterFieldSelectionCloses = false

  private var palette: AppColorPalette { model.appearancePalette }

  var body: some View {
    NavigationStack {
      MetadataSheetScrollScreen {
        searchSection
        resultsSection
      }
      .navigationTitle("Match Metadata")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .task { await loadProviders() }
      .onAppear { prefetchQueryFromCurrent() }
      .onChange(of: selectedMatch) { _, newValue in
        guard newValue == nil, dismissSheetAfterFieldSelectionCloses else { return }
        dismissSheetAfterFieldSelectionCloses = false
        dismiss()
      }
      .sheet(item: $selectedMatch) { match in
        fieldSelectionSheet(for: match)
      }
      .alert("Apply failed", isPresented: applyErrorAlertPresented) {
        Button("OK", role: .cancel) { applyError = nil }
      } message: {
        Text(applyError ?? "")
      }
    }
    .presentationDetents([.large])
  }

  // MARK: Search

  @ViewBuilder
  private var searchSection: some View {
    MetadataSheetSection(title: "Search") {
      MetadataSheetCard {
        MetadataSheetTextField(
          title: "Title",
          text: $titleQuery,
          submitLabel: .search,
          onSubmit: { Task { await runSearch() } }
        )
        MetadataSheetTextField(
          title: "Author",
          text: $authorQuery,
          submitLabel: .search,
          onSubmit: { Task { await runSearch() } }
        )
        HStack(alignment: .bottom, spacing: 12) {
          MetadataSheetMenuPicker(title: "Provider", selection: $provider) {
            ForEach(availableProviders) { p in
              Text(p.text).tag(p.value)
            }
          }
          Button {
            Task { await runSearch() }
          } label: {
            Label("Search", systemImage: "magnifyingglass")
              .labelStyle(.titleAndIcon)
          }
          .buttonStyle(AbstandProminentButtonStyle())
          .disabled(
            titleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
        }
      }
    }
  }

  private var availableProviders: [ABSMetadataProvider] {
    providers.isEmpty
      ? [ABSMetadataProvider(text: "Audible", value: "audible")]
      : providers
  }

  private var applyErrorAlertPresented: Binding<Bool> {
    Binding(
      get: { applyError != nil },
      set: { if !$0 { applyError = nil } }
    )
  }

  // MARK: Results

  @ViewBuilder
  private var resultsSection: some View {
    if isSearching {
      AbstandLoadingSpinner()
    } else if let searchError {
      MetadataSheetSection(title: "Results") {
        MetadataSheetCard {
          AbstandInlineNotice(text: searchError, isError: true)
        }
      }
    } else if results.isEmpty {
      emptyState
    } else {
      MetadataSheetSection(title: "Results") {
        LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(results) { match in
            Button {
              openFieldSelection(for: match)
            } label: {
              matchCard(match)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    ContentUnavailableView(
      hasSearched ? "No matches found" : "Match metadata",
      systemImage: hasSearched ? "magnifyingglass" : "text.magnifyingglass",
      description: Text(
        hasSearched
          ? "Try another title, author or provider."
          : "Search a metadata provider, then pick which fields to apply to this book."
      )
    )
    .padding(.top, AppTheme.Layout.sectionSpacing)
  }

  @ViewBuilder
  private func matchCard(_ match: ABSMetadataMatch) -> some View {
    MetadataSheetCard(spacing: AppTheme.Layout.withinSectionSpacing) {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        matchCover(match)
        VStack(alignment: .leading, spacing: 4) {
          Text(match.title ?? "—")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.textPrimary)
            .lineLimit(2)
          if let a = match.displayAuthors {
            Text(a)
              .font(.footnote)
              .foregroundStyle(palette.textSecondary)
              .lineLimit(1)
          }
          if let n = match.displayNarrator {
            Text("Narrated by \(n)")
              .font(.footnote)
              .foregroundStyle(palette.textSecondary)
              .lineLimit(1)
          }
          HStack(spacing: 6) {
            if let y = match.displayYear { chip(y) }
            if let p = match.publisher?.trimmingCharacters(in: .whitespacesAndNewlines),
              !p.isEmpty
            {
              chip(p)
            }
          }
        }
        Spacer(minLength: 0)
      }

      if let s = match.displaySeries {
        Text(s)
          .font(.caption)
          .foregroundStyle(palette.textSecondary)
          .lineLimit(1)
      }
      if let desc = match.displayDescription {
        Text(desc)
          .font(.caption)
          .foregroundStyle(palette.textSecondary)
          .lineLimit(2)
      }
    }
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func matchCover(_ match: ABSMetadataMatch) -> some View {
    let shape = RoundedRectangle(
      cornerRadius: AppTheme.Layout.chipCornerRadius, style: .continuous)
    Group {
      if let url = match.displayCoverURL {
        AsyncImage(url: url) { phase in
          switch phase {
          case .empty:
            shape.fill(palette.background)
              .overlay { ProgressView().controlSize(.small).tint(themeAccent) }
          case .success(let img):
            img.resizable().scaledToFit()
          default:
            coverPlaceholder(shape)
          }
        }
      } else {
        coverPlaceholder(shape)
      }
    }
    .frame(width: 56, height: 80)
    .clipShape(shape)
  }

  @ViewBuilder
  private func coverPlaceholder(_ shape: RoundedRectangle) -> some View {
    shape
      .fill(palette.background)
      .overlay {
        Image(systemName: "book")
          .foregroundStyle(palette.textSecondary)
      }
  }

  @ViewBuilder
  private func chip(_ text: String) -> some View {
    Text(text)
      .font(.caption2)
      .foregroundStyle(palette.textSecondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(palette.background.opacity(0.6), in: Capsule())
  }

  // MARK: Field selection sheet

  @ViewBuilder
  private func fieldSelectionSheet(for match: ABSMetadataMatch) -> some View {
    NavigationStack {
      MetadataSheetScrollScreen {
        MetadataSheetSection(title: "Match") {
          MetadataSheetCard(spacing: 4) {
            Text(match.title ?? "—")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(palette.textPrimary)
            if let a = match.displayAuthors {
              Text(a)
                .font(.footnote)
                .foregroundStyle(palette.textSecondary)
            }
          }
        }

        MetadataSheetSection(title: "Fields") {
          MetadataSheetCard(spacing: 0) {
            let fields = availableFields(for: match)
            ForEach(Array(fields.enumerated()), id: \.element) { idx, field in
              MetadataSheetToggleRow(
                title: field.label,
                subtitle: previewText(for: field, in: match),
                subtitleLineLimit: 2,
                isOn: Binding(
                  get: { selectedFields.contains(field) },
                  set: { isOn in
                    if isOn { selectedFields.insert(field) } else { selectedFields.remove(field) }
                  }
                )
              )
              .padding(.vertical, 8)
              if idx < fields.count - 1 {
                MetadataSheetCardDivider()
              }
            }
          }
        }
      }
      .navigationTitle("Apply Match")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { selectedMatch = nil }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            Task { await applyMatch(match) }
          }
          .disabled(selectedFields.isEmpty || isApplying)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .onAppear { selectedFields = Set(availableFields(for: match)) }
    .onDisappear { selectedFields = Set(ABSMatchField.allCases) }
  }

  /// Nur Felder anzeigen, für die der Treffer auch einen Wert liefert.
  private func availableFields(for match: ABSMetadataMatch) -> [ABSMatchField] {
    ABSMatchField.allCases.filter { field in
      !previewText(for: field, in: match).isEmpty
    }
  }

  /// Vorschau-Text pro Feld (leer, wenn nicht vorhanden).
  private func previewText(for field: ABSMatchField, in match: ABSMetadataMatch) -> String {
    switch field {
    case .title: return match.title ?? ""
    case .subtitle: return match.subtitle ?? ""
    case .author: return match.displayAuthors ?? ""
    case .narrator: return match.displayNarrator ?? ""
    case .description: return match.displayDescription ?? ""
    case .publisher: return match.publisher ?? ""
    case .publishedYear: return match.displayYear ?? ""
    case .asin: return match.asin ?? ""
    case .isbn: return match.isbn ?? ""
    case .language: return match.language ?? ""
    case .genres: return (match.genres ?? []).joined(separator: ", ")
    case .tags: return (match.tags ?? []).joined(separator: ", ")
    case .series: return match.displaySeries ?? ""
    case .cover: return match.displayCoverURL?.absoluteString ?? ""
    }
  }

  // MARK: Actions

  private func prefetchQueryFromCurrent() {
    if titleQuery.isEmpty { titleQuery = currentTitle }
    if authorQuery.isEmpty { authorQuery = currentAuthor ?? "" }
  }

  private func loadProviders() async {
    guard providers.isEmpty else { return }
    do {
      providers = try await model.loadMetadataProviders()
      if !providers.isEmpty, !providers.contains(where: { $0.value == provider }) {
        provider = providers.first?.value ?? "audible"
      }
    } catch {
      // Nicht fatal — Default-Provider bleibt hängen.
      providers = []
    }
  }

  private func runSearch() async {
    let title = titleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    isSearching = true
    searchError = nil
    results = []
    hasSearched = false
    do {
      results = try await model.searchMetadataBooks(
        title: title,
        author: authorQuery.nilIfEmpty,
        provider: provider,
        region: nil
      )
      hasSearched = true
    } catch is CancellationError {
      // Stillschweigend — bspw. Sheet schließt.
    } catch {
      searchError = error.localizedDescription
    }
    isSearching = false
  }

  private func openFieldSelection(for match: ABSMetadataMatch) {
    selectedFields = Set(availableFields(for: match))
    selectedMatch = match
  }

  private func applyMatch(_ match: ABSMetadataMatch) async {
    guard !selectedFields.isEmpty else { return }
    isApplying = true
    defer { isApplying = false }

    var patch = ABSItemMediaMetadataPatch()
    if selectedFields.contains(.title) { patch.title = match.title }
    if selectedFields.contains(.subtitle) { patch.subtitle = match.subtitle }
    if selectedFields.contains(.author), let a = match.displayAuthors {
      patch.authorNames = a.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    if selectedFields.contains(.narrator), let n = match.displayNarrator {
      patch.narratorNames = n.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    if selectedFields.contains(.description) { patch.descriptionText = match.displayDescription }
    if selectedFields.contains(.publisher) { patch.publisher = match.publisher }
    if selectedFields.contains(.publishedYear) { patch.publishedYear = match.displayYear }
    if selectedFields.contains(.asin) { patch.asin = match.asin }
    if selectedFields.contains(.isbn) { patch.isbn = match.isbn }
    if selectedFields.contains(.language) { patch.language = match.language }
    if selectedFields.contains(.genres) { patch.genres = match.genres }
    if selectedFields.contains(.tags) { patch.tags = match.tags }
    if selectedFields.contains(.series), let series = match.series {
      patch.series = series.map { .init(name: $0.name, sequence: $0.sequence) }
    }
    let coverURL: String? = selectedFields.contains(.cover) ? match.cover : nil

    let ok = await model.applyMetadataMatch(itemId: itemId, patch: patch, coverURL: coverURL)
    if ok {
      if selectedMatch != nil {
        dismissSheetAfterFieldSelectionCloses = true
        selectedMatch = nil
      } else {
        dismiss()
      }
    } else {
      applyError = model.errorMessage?.isEmpty == false
        ? model.errorMessage!
        : "Could not apply the selected fields. Check your connection and permissions."
    }
  }
}
