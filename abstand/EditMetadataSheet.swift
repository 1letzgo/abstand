import SwiftUI

/// Metadaten-Editor + Cover-Online-Suche.
/// Sektion A: manuelle Bearbeitung aller Metadaten-Felder (Save via `PATCH /api/items/:id/media`).
/// Sektion B: Cover-Suche über `GET /api/search/covers` mit Grid-Vorschau + Apply via `POST /api/items/:id/cover`.
/// Admin/Root-only (`model.isServerAdmin || model.isServerRoot`).
/// Chrome (Sektionen, Karten, Felder): `MetadataSheetComponents` — gleiche Sprache wie Buch-Detail.
struct EditMetadataSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.themeAccent) private var themeAccent

  let itemId: String
  /// Bibliothek des Items — für Series-Suche; Fallback in `AppModel.searchLibrarySeries`.
  var libraryId: String? = nil
  let metadata: ABSBookMediaMetadata
  let tags: [String]?

  // Metadaten-Form-State
  @State private var title: String = ""
  @State private var subtitle: String = ""
  @State private var author: String = ""
  @State private var narrator: String = ""
  @State private var seriesRows: [EditSeriesRow] = []
  @State private var descriptionText: String = ""
  @State private var publisher: String = ""
  @State private var publishedYear: String = ""
  @State private var language: String = ""
  @State private var genres: String = ""
  @State private var tagsText: String = ""
  @State private var asin: String = ""
  /// Vorschläge pro Series-Zeile (Index → Namen aus Library-Search).
  @State private var seriesSuggestionsByRow: [Int: [String]] = [:]
  @State private var seriesSearchBusyRow: Int?
  /// Laufende Debounce-Tasks pro Zeile (nur bei Nutzer-Eingabe, nicht Prefill).
  @State private var seriesSearchTasks: [Int: Task<Void, Never>] = [:]
  /// Nächstes `onChange` überspringen (Vorschlag übernommen / Zeile geleert).
  @State private var seriesSearchSuppressRows: Set<Int> = []

  // Save-State
  @State private var isSaving = false
  @State private var saveError: String?

  // Cover-Suche-State
  @State private var coverTitle: String = ""
  @State private var coverAuthor: String = ""
  @State private var coverProvider: String = "google"
  @State private var coverResults: [String] = []
  @State private var isSearchingCovers = false
  @State private var hasSearchedCovers = false
  @State private var coverSearchError: String?
  @State private var pendingCoverURL: String?
  @State private var isApplyingCover = false
  @State private var coverApplyError: String?

  private let coverProviders: [(value: String, label: String)] = [
    ("google", "Google"),
    ("audible", "Audible"),
    ("itunes", "iTunes"),
    ("openlibrary", "OpenLibrary"),
    ("audiobookcovers", "AudiobookCovers"),
    ("fantlab", "FantLab"),
  ]

  private var palette: AppColorPalette { model.appearancePalette }

  var body: some View {
    NavigationStack {
      MetadataSheetScrollScreen {
        metadataSection
        coverSearchSection
      }
      .navigationTitle("Edit Metadata")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await saveMetadata() } }
            .disabled(isSaving)
        }
      }
      .onAppear { prefetchFromMetadata() }
      .onDisappear {
        for (_, task) in seriesSearchTasks { task.cancel() }
        seriesSearchTasks = [:]
        seriesSearchBusyRow = nil
      }
      .alert("Save failed", isPresented: presentedBinding($saveError)) {
        Button("OK", role: .cancel) { saveError = nil }
      } message: { Text(saveError ?? "") }
      .alert("Apply cover failed", isPresented: presentedBinding($coverApplyError)) {
        Button("OK", role: .cancel) { coverApplyError = nil }
      } message: { Text(coverApplyError ?? "") }
      .alert("Apply this cover?", isPresented: presentedBinding($pendingCoverURL)) {
        Button("Cancel", role: .cancel) { pendingCoverURL = nil }
        Button("Apply") {
          if let url = pendingCoverURL { Task { await applyCover(url: url) } }
        }
      } message: {
        if let url = pendingCoverURL { Text(url) }
      }
    }
    .presentationDetents([.large])
  }

  /// Alert-Bindung, die auch bei System-Dismiss zurückschreibt (statt `.constant`).
  private func presentedBinding(_ value: Binding<String?>) -> Binding<Bool> {
    Binding(
      get: { value.wrappedValue != nil },
      set: { if !$0 { value.wrappedValue = nil } }
    )
  }

  // MARK: Metadata form

  @ViewBuilder
  private var metadataSection: some View {
    MetadataSheetSection(title: "Details") {
      MetadataSheetCard {
        MetadataSheetTextField(title: "Title", text: $title)
        MetadataSheetTextField(title: "Subtitle", text: $subtitle)
        MetadataSheetTextField(title: "Author", text: $author, hint: "Comma separated")
        MetadataSheetTextField(title: "Narrator", text: $narrator, hint: "Comma separated")
        seriesEditor
        MetadataSheetTextField(
          title: "Description",
          text: $descriptionText,
          axis: .vertical,
          lineLimit: 3...8
        )
        MetadataSheetTextField(title: "Publisher", text: $publisher)
        HStack(alignment: .top, spacing: 12) {
          MetadataSheetTextField(title: "Year", text: $publishedYear, keyboardType: .numberPad)
          MetadataSheetTextField(title: "Language", text: $language)
        }
        MetadataSheetTextField(title: "Genres", text: $genres, hint: "Comma separated")
        MetadataSheetTextField(title: "Tags", text: $tagsText, hint: "Comma separated")
        MetadataSheetTextField(
          title: "ASIN",
          text: $asin,
          autocapitalization: .characters,
          disablesAutocorrection: true
        )
      }
    }
  }

  // Series — wiederholbare Zeilen (Name + Sequence); ab 3 Zeichen Server-Suche.
  @ViewBuilder
  private var seriesEditor: some View {
    VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.labelToContentSpacing) {
      MetadataSheetFieldLabel(title: "Series", hint: "Search from 3 letters")
      ForEach(Array(seriesRows.enumerated()), id: \.offset) { idx, _ in
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            TextField(
              "",
              text: $seriesRows[idx].name,
              prompt: Text("Series name")
                .foregroundStyle(palette.textSecondary.opacity(0.55))
            )
            .font(.body)
            .foregroundStyle(palette.textPrimary)
            .tint(themeAccent)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .accessibilityLabel("Series name")
            .metadataSheetFieldChrome()
            .onChange(of: seriesRows[idx].name) { _, _ in
              scheduleSeriesSearch(rowIndex: idx)
            }
            TextField(
              "",
              text: $seriesRows[idx].sequence,
              prompt: Text("#").foregroundStyle(palette.textSecondary.opacity(0.55))
            )
            .font(.body)
            .foregroundStyle(palette.textPrimary)
            .tint(themeAccent)
            .multilineTextAlignment(.center)
            .keyboardType(.decimalPad)
            .accessibilityLabel("Series number")
            .metadataSheetFieldChrome(horizontalPadding: 8)
            .frame(width: 64)
            Button {
              removeSeriesRow(idx)
            } label: {
              Image(systemName: "minus.circle")
                .font(.body)
                .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove series")
          }
          if seriesSearchBusyRow == idx {
            ProgressView()
              .controlSize(.mini)
              .tint(themeAccent)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.leading, 2)
          } else if let suggestions = seriesSuggestionsByRow[idx], !suggestions.isEmpty {
            seriesSuggestionsList(rowIndex: idx, suggestions: suggestions)
          }
        }
      }
      Button {
        seriesRows.append(EditSeriesRow())
      } label: {
        Label("Add series", systemImage: "plus.circle")
          .font(.footnote.weight(.medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(themeAccent)
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func removeSeriesRow(_ idx: Int) {
    seriesSearchTasks[idx]?.cancel()
    seriesSearchTasks[idx] = nil
    seriesSearchSuppressRows.insert(idx)
    if seriesRows.count == 1 {
      seriesRows[0] = EditSeriesRow()
    } else {
      seriesRows.remove(at: idx)
    }
    seriesSuggestionsByRow[idx] = nil
    if seriesSearchBusyRow == idx { seriesSearchBusyRow = nil }
  }

  @ViewBuilder
  private func seriesSuggestionsList(rowIndex: Int, suggestions: [String]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(suggestions, id: \.self) { name in
        Button {
          seriesSearchTasks[rowIndex]?.cancel()
          seriesSearchTasks[rowIndex] = nil
          seriesSearchSuppressRows.insert(rowIndex)
          seriesRows[rowIndex].name = name
          seriesSuggestionsByRow[rowIndex] = []
          if seriesSearchBusyRow == rowIndex { seriesSearchBusyRow = nil }
        } label: {
          Text(name)
            .font(.subheadline)
            .foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MetadataSheetMetrics.fieldInsetH)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if name != suggestions.last {
          MetadataSheetCardDivider()
            .padding(.horizontal, MetadataSheetMetrics.fieldInsetH)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.background, in: MetadataSheetMetrics.fieldShape)
    .overlay {
      MetadataSheetMetrics.fieldShape
        .strokeBorder(
          palette.textSecondary.opacity(MetadataSheetMetrics.fieldBorderOpacity),
          lineWidth: 1
        )
    }
  }

  /// Nur bei aktiver Texteingabe — nicht beim Prefill aus vorhandenen Metadaten.
  private func scheduleSeriesSearch(rowIndex: Int) {
    if seriesSearchSuppressRows.contains(rowIndex) {
      seriesSearchSuppressRows.remove(rowIndex)
      seriesSuggestionsByRow[rowIndex] = []
      if seriesSearchBusyRow == rowIndex { seriesSearchBusyRow = nil }
      return
    }
    seriesSearchTasks[rowIndex]?.cancel()
    seriesSearchTasks[rowIndex] = Task {
      await runSeriesSearch(rowIndex: rowIndex)
    }
  }

  /// Debounced Library-Search für Series-Namen (ab 3 Zeichen).
  private func runSeriesSearch(rowIndex: Int) async {
    guard seriesRows.indices.contains(rowIndex) else { return }
    let q = seriesRows[rowIndex].name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard q.count >= 3 else {
      seriesSuggestionsByRow[rowIndex] = []
      if seriesSearchBusyRow == rowIndex { seriesSearchBusyRow = nil }
      return
    }
    guard model.isNetworkReachable else {
      seriesSuggestionsByRow[rowIndex] = []
      return
    }
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    guard seriesRows.indices.contains(rowIndex) else { return }
    let still = seriesRows[rowIndex].name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard still == q else { return }

    seriesSearchBusyRow = rowIndex
    defer {
      if seriesSearchBusyRow == rowIndex { seriesSearchBusyRow = nil }
    }
    do {
      let rows = try await model.searchLibrarySeries(query: q, libraryId: libraryId)
      guard !Task.isCancelled else { return }
      let names = rows
        .map(\.name)
        .filter { $0.caseInsensitiveCompare(q) != .orderedSame }
      seriesSuggestionsByRow[rowIndex] = names
    } catch is CancellationError {
      // Stille.
    } catch {
      seriesSuggestionsByRow[rowIndex] = []
    }
  }

  // MARK: Cover search

  @ViewBuilder
  private var coverSearchSection: some View {
    MetadataSheetSection(title: "Cover") {
      MetadataSheetCard {
        MetadataSheetTextField(
          title: "Title",
          text: $coverTitle,
          submitLabel: .search,
          onSubmit: { Task { await runCoverSearch() } }
        )
        MetadataSheetTextField(
          title: "Author",
          text: $coverAuthor,
          submitLabel: .search,
          onSubmit: { Task { await runCoverSearch() } }
        )
        HStack(alignment: .bottom, spacing: 12) {
          MetadataSheetMenuPicker(title: "Provider", selection: $coverProvider) {
            ForEach(coverProviders, id: \.value) { p in
              Text(p.label).tag(p.value)
            }
          }
          Button {
            Task { await runCoverSearch() }
          } label: {
            Label("Search", systemImage: "magnifyingglass")
              .labelStyle(.titleAndIcon)
          }
          .buttonStyle(AbstandProminentButtonStyle())
          .disabled(
            coverTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingCovers)
        }
      }

      coverResultsContent
    }
  }

  @ViewBuilder
  private var coverResultsContent: some View {
    if isSearchingCovers {
      MetadataSheetCard {
        AbstandLoadingSpinner(controlSize: .regular, verticalPadding: 24)
      }
    } else if let coverSearchError {
      MetadataSheetCard {
        AbstandInlineNotice(text: coverSearchError, isError: true)
      }
    } else if coverResults.isEmpty {
      if hasSearchedCovers {
        MetadataSheetCard {
          AbstandInlineNotice(text: "No covers found.")
        }
      }
    } else {
      MetadataSheetCard {
        coverGrid
      }
    }
  }

  // 3-Spalten-Grid mit Thumbnail-Vorschauen.
  private let coverColumns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
  ]

  @ViewBuilder
  private var coverGrid: some View {
    LazyVGrid(columns: coverColumns, spacing: 8) {
      ForEach(Array(coverResults.enumerated()), id: \.offset) { _, url in
        Button { pendingCoverURL = url } label: {
          AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .empty:
              RoundedRectangle(cornerRadius: AppTheme.Layout.chipCornerRadius)
                .fill(palette.background)
                .overlay { ProgressView().controlSize(.small).tint(themeAccent) }
            case .success(let img):
              img.resizable().scaledToFit()
            default:
              RoundedRectangle(cornerRadius: AppTheme.Layout.chipCornerRadius)
                .fill(palette.background)
                .overlay {
                  Image(systemName: "photo")
                    .foregroundStyle(palette.textSecondary)
                }
            }
          }
          .aspectRatio(2 / 3, contentMode: .fit)
          .clipShape(
            RoundedRectangle(cornerRadius: AppTheme.Layout.chipCornerRadius, style: .continuous)
          )
        }
        .buttonStyle(.plain)
        .disabled(isApplyingCover)
        .accessibilityLabel("Cover option")
      }
    }
  }

  // MARK: Actions

  private func prefetchFromMetadata() {
    guard title.isEmpty else { return }
    title = metadata.title
    subtitle = metadata.subtitle ?? ""
    author = metadata.authorName ?? ""
    narrator = metadata.narratorName ?? ""
    descriptionText = metadata.description ?? ""
    publisher = metadata.publisher ?? ""
    publishedYear = metadata.publishedYear ?? ""
    language = metadata.language ?? ""
    asin = metadata.asin ?? ""
    genres = (metadata.genres ?? []).joined(separator: ", ")
    tagsText = (tags ?? []).joined(separator: ", ")
    if let s = metadata.series, !s.isEmpty {
      seriesRows = s.map { EditSeriesRow(name: $0.name, sequence: $0.sequence ?? "") }
    } else if seriesRows.isEmpty {
      seriesRows = [EditSeriesRow()]
    }
    // Cover-Suchfelder mit Titel/Autor vorbefüllen.
    if coverTitle.isEmpty { coverTitle = metadata.title }
    if coverAuthor.isEmpty { coverAuthor = metadata.authorName ?? "" }
  }

  private func saveMetadata() async {
    isSaving = true
    defer { isSaving = false }

    var patch = ABSItemMediaMetadataPatch()
    patch.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    patch.subtitle = subtitle.nilIfEmpty
    patch.authorNames = splitCommaList(author)
    patch.narratorNames = splitCommaList(narrator)
    patch.descriptionText = descriptionText.nilIfEmpty
    patch.publisher = publisher.nilIfEmpty
    patch.publishedYear = publishedYear.nilIfEmpty
    patch.language = language.nilIfEmpty
    patch.asin = asin.nilIfEmpty
    patch.genres = splitCommaList(genres)
    patch.tags = splitCommaList(tagsText)
    patch.series = seriesRows
      .map { $0.trimmed }
      .filter { !$0.name.isEmpty }
      .map { .init(name: $0.name, sequence: $0.sequence.nilIfEmpty) }

    let ok = await model.applyMetadataMatch(itemId: itemId, patch: patch, coverURL: nil)
    if ok {
      dismiss()
    } else {
      saveError = model.errorMessage?.isEmpty == false
        ? model.errorMessage!
        : "Could not save metadata. Check your connection and permissions."
    }
  }

  private func runCoverSearch() async {
    let q = coverTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    isSearchingCovers = true
    coverSearchError = nil
    coverResults = []
    hasSearchedCovers = false
    do {
      coverResults = try await model.searchCoversOnline(
        title: q, author: coverAuthor.nilIfEmpty, provider: coverProvider)
      hasSearchedCovers = true
    } catch is CancellationError {
      // Stille.
    } catch {
      coverSearchError = error.localizedDescription
    }
    isSearchingCovers = false
  }

  private func applyCover(url: String) async {
    isApplyingCover = true
    defer { isApplyingCover = false }
    let ok = await model.applyCoverURL(itemId: itemId, url: url)
    if ok {
      pendingCoverURL = nil
      dismiss()
    } else {
      coverApplyError = model.errorMessage?.isEmpty == false
        ? model.errorMessage!
        : "Could not apply the cover. Check your connection and permissions."
    }
  }

  /// Komma-Separierten String in bereinigtes `[String]` umwandeln.
  private func splitCommaList(_ text: String) -> [String] {
    text.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

/// Editierbare Serie-Zeile (Name + Sequence) für den Metadaten-Editor.
private struct EditSeriesRow {
  var name: String = ""
  var sequence: String = ""

  var trimmed: EditSeriesRow {
    EditSeriesRow(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      sequence: sequence.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }
}
