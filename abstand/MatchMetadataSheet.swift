import SwiftUI

/// Match-Metadaten-Sheet (absorb-style): Online-Suche über `/api/search/books`,
/// Trefferliste mit Vorschau, pro-Feld-Auswahl vor dem Apply (`PATCH /api/items/:id/media` + optional Cover).
/// Nur für Admin-oder-Root-User (`model.isServerAdmin || model.isServerRoot`).
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

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          searchHeader
          if isSearching {
            ProgressView()
              .padding(.top, AppTheme.Layout.sectionSpacing)
              .frame(maxWidth: .infinity)
          } else if let searchError {
            Text(searchError)
              .font(.footnote)
              .foregroundStyle(AppTheme.danger)
              .padding(.top, AppTheme.Layout.sectionSpacing)
              .frame(maxWidth: .infinity)
          } else if results.isEmpty {
            emptyState
          } else {
            resultsList
          }
        }
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.tabPaddingTop)
        .padding(.bottom, AppTheme.Layout.scrollBottomInsetBase)
      }
      .abstandScrollScreenBackground()
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

  // MARK: Search header

  @ViewBuilder
  private var searchHeader: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Title")
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
        TextField("Title", text: $titleQuery)
          .textFieldStyle(.roundedBorder)
          .submitLabel(.search)
          .onSubmit { Task { await runSearch() } }
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Author")
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
        TextField("Author", text: $authorQuery)
          .textFieldStyle(.roundedBorder)
          .submitLabel(.search)
          .onSubmit { Task { await runSearch() } }
      }
      HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Provider")
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
          Picker("Provider", selection: $provider) {
            ForEach(availableProviders) { p in
              Text(p.text).tag(p.value)
            }
          }
          .pickerStyle(.menu)
        }
        Spacer()
        Button {
          Task { await runSearch() }
        } label: {
          Label("Search", systemImage: "magnifyingglass")
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(themeAccent)
        .disabled(titleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
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

  // MARK: Empty state

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: hasSearched ? "magnifyingglass" : "text.magnifyingglass")
        .font(.system(size: 40))
        .foregroundStyle(AppTheme.textSecondary)
      Text(hasSearched ? "No matches found." : "Search for a book to match metadata.")
        .font(.footnote)
        .foregroundStyle(AppTheme.textSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, AppTheme.Layout.sectionSpacing * 1.5)
  }

  // MARK: Results

  @ViewBuilder
  private var resultsList: some View {
    LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
      ForEach(results) { match in
        matchCard(match)
          .onTapGesture { openFieldSelection(for: match) }
      }
    }
    .padding(.top, AppTheme.Layout.withinSectionSpacing)
  }

  @ViewBuilder
  private func matchCard(_ match: ABSMetadataMatch) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        // Cover (klein)
        if let url = match.displayCoverURL {
          AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
              RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.card)
                .overlay { ProgressView() }
            case .success(let img):
              img.resizable().scaledToFit()
            default:
              RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.card)
                .overlay {
                  Image(systemName: "book")
                    .foregroundStyle(AppTheme.textSecondary)
                }
            }
          }
          .frame(width: 56, height: 80)
          .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
          RoundedRectangle(cornerRadius: 6)
            .fill(AppTheme.card)
            .overlay {
              Image(systemName: "book")
                .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(width: 56, height: 80)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(match.title ?? "—")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(2)
          if let a = match.displayAuthors {
            Text(a)
              .font(.footnote)
              .foregroundStyle(AppTheme.textSecondary)
              .lineLimit(1)
          }
          if let n = match.displayNarrator {
            Text("Narrated by \(n)")
              .font(.footnote)
              .foregroundStyle(AppTheme.textSecondary)
              .lineLimit(1)
          }
          HStack(spacing: 6) {
            if let y = match.displayYear { chip(y) }
            if let p = match.publisher?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty { chip(p) }
          }
        }
        Spacer(minLength: 0)
      }

      if let s = match.displaySeries {
        Text(s)
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
          .lineLimit(1)
      }
      if let desc = match.displayDescription {
        Text(desc)
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
          .lineLimit(2)
      }
    }
    .padding(AppTheme.Layout.detailSectionCardPadding)
    .background(AppTheme.card)
    .clipShape(
      RoundedRectangle(cornerRadius: AppTheme.Layout.detailSectionCardCornerRadius,
                       style: .continuous)
    )
    .abstandCardElevation(.subtle)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func chip(_ text: String) -> some View {
    Text(text)
      .font(.caption2)
      .foregroundStyle(AppTheme.textSecondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(AppTheme.background.opacity(0.6))
      .clipShape(Capsule())
  }

  // MARK: Field selection sheet

  @ViewBuilder
  private func fieldSelectionSheet(for match: ABSMetadataMatch) -> some View {
    NavigationStack {
      List {
        Section {
          // Vorschau des gewählten Treffers.
          VStack(alignment: .leading, spacing: 4) {
            Text(match.title ?? "—")
              .font(.subheadline.weight(.semibold))
            if let a = match.displayAuthors {
              Text(a).font(.footnote).foregroundStyle(AppTheme.textSecondary)
            }
          }
          .padding(.vertical, 4)
        }
        Section("Choose fields to apply") {
          ForEach(availableFields(for: match)) { field in
            Toggle(isOn: Binding(
              get: { selectedFields.contains(field) },
              set: { isOn in
                if isOn { selectedFields.insert(field) } else { selectedFields.remove(field) }
              }
            )) {
              VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                  .font(.subheadline)
                Text(previewText(for: field, in: match))
                  .font(.caption)
                  .foregroundStyle(AppTheme.textSecondary)
                  .lineLimit(2)
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

