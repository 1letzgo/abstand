import SwiftUI

private enum SeriesRowMetrics {
  /// Feste Breite des schmalen Seriennummer-Feldes.
  static let numberFieldWidth: CGFloat = 64
}

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
  /// Vorschläge pro Series-Zeile (stabile Zeilen-ID → Namen aus Library-Search).
  /// Bewusst nicht per Index: nach dem Entfernen einer Zeile hingen sie sonst an der falschen.
  @State private var seriesSuggestionsByRow: [UUID: [String]] = [:]
  @State private var seriesSearchBusyRow: UUID?
  /// Laufende Debounce-Tasks pro Zeile (nur bei Nutzer-Eingabe, nicht Prefill).
  @State private var seriesSearchTasks: [UUID: Task<Void, Never>] = [:]
  /// Nächstes `onChange` überspringen (Vorschlag übernommen).
  @State private var seriesSearchSuppressRows: Set<UUID> = []

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
        HStack(alignment: .top, spacing: AppTheme.Layout.rowSpacing) {
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
      ForEach($seriesRows) { $row in
        let rowId = row.id
        VStack(alignment: .leading, spacing: AppTheme.Layout.compactSpacing) {
          HStack(spacing: AppTheme.Layout.inlineSpacing) {
            TextField(
              "",
              text: $row.name,
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
            .onChange(of: row.name) { _, _ in
              scheduleSeriesSearch(rowId: rowId)
            }
            TextField(
              "",
              text: $row.sequence,
              prompt: Text("#").foregroundStyle(palette.textSecondary.opacity(0.55))
            )
            .font(.body)
            .foregroundStyle(palette.textPrimary)
            .tint(themeAccent)
            .multilineTextAlignment(.center)
            .keyboardType(.decimalPad)
            .accessibilityLabel("Series number")
            .metadataSheetFieldChrome(horizontalPadding: AppTheme.Layout.inlineSpacing)
            .frame(width: SeriesRowMetrics.numberFieldWidth)
            Button {
              removeSeriesRow(rowId)
            } label: {
              Image(systemName: "minus.circle")
                .font(.body)
                .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove series")
          }
          if seriesSearchBusyRow == rowId {
            ProgressView()
              .controlSize(.mini)
              .tint(themeAccent)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.leading, AppTheme.Layout.hairlineSpacing)
          } else if let suggestions = seriesSuggestionsByRow[rowId], !suggestions.isEmpty {
            seriesSuggestionsList(rowId: rowId, suggestions: suggestions)
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
      .padding(.top, AppTheme.Layout.hairlineSpacing)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func removeSeriesRow(_ rowId: UUID) {
    seriesSearchTasks[rowId]?.cancel()
    seriesSearchTasks[rowId] = nil
    seriesSearchSuppressRows.remove(rowId)
    seriesSuggestionsByRow[rowId] = nil
    if seriesSearchBusyRow == rowId { seriesSearchBusyRow = nil }
    guard let idx = seriesRows.firstIndex(where: { $0.id == rowId }) else { return }
    if seriesRows.count == 1 {
      // Neue Zeile mit neuer ID — erzeugt kein `onChange` auf der alten.
      seriesRows[0] = EditSeriesRow()
    } else {
      seriesRows.remove(at: idx)
    }
  }

  @ViewBuilder
  private func seriesSuggestionsList(rowId: UUID, suggestions: [String]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(suggestions, id: \.self) { name in
        Button {
          seriesSearchTasks[rowId]?.cancel()
          seriesSearchTasks[rowId] = nil
          if let idx = seriesRows.firstIndex(where: { $0.id == rowId }) {
            seriesSearchSuppressRows.insert(rowId)
            seriesRows[idx].name = name
          }
          seriesSuggestionsByRow[rowId] = []
          if seriesSearchBusyRow == rowId { seriesSearchBusyRow = nil }
        } label: {
          Text(name)
            .font(.subheadline)
            .foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MetadataSheetMetrics.fieldInsetH)
            .padding(.vertical, AppTheme.Layout.rowVerticalPadding)
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
          lineWidth: AppTheme.Layout.hairlineWidth
        )
    }
  }

  /// Nur bei aktiver Texteingabe — nicht beim Prefill aus vorhandenen Metadaten.
  private func scheduleSeriesSearch(rowId: UUID) {
    if seriesSearchSuppressRows.contains(rowId) {
      seriesSearchSuppressRows.remove(rowId)
      seriesSuggestionsByRow[rowId] = []
      if seriesSearchBusyRow == rowId { seriesSearchBusyRow = nil }
      return
    }
    seriesSearchTasks[rowId]?.cancel()
    seriesSearchTasks[rowId] = Task {
      await runSeriesSearch(rowId: rowId)
    }
  }

  private func seriesRowName(_ rowId: UUID) -> String? {
    seriesRows.first(where: { $0.id == rowId })?.name
  }

  /// Debounced Library-Search für Series-Namen (ab 3 Zeichen).
  private func runSeriesSearch(rowId: UUID) async {
    guard let name = seriesRowName(rowId) else { return }
    let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard q.count >= 3 else {
      seriesSuggestionsByRow[rowId] = []
      if seriesSearchBusyRow == rowId { seriesSearchBusyRow = nil }
      return
    }
    guard model.isNetworkReachable else {
      seriesSuggestionsByRow[rowId] = []
      return
    }
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    guard let stillName = seriesRowName(rowId) else { return }
    let still = stillName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard still == q else { return }

    seriesSearchBusyRow = rowId
    defer {
      if seriesSearchBusyRow == rowId { seriesSearchBusyRow = nil }
    }
    do {
      let rows = try await model.searchLibrarySeries(query: q, libraryId: libraryId)
      guard !Task.isCancelled else { return }
      let names = rows
        .map(\.name)
        .filter { $0.caseInsensitiveCompare(q) != .orderedSame }
      // Zeile inzwischen entfernt → keine Vorschläge mehr ablegen.
      guard seriesRowName(rowId) != nil else { return }
      seriesSuggestionsByRow[rowId] = names
    } catch is CancellationError {
      // Stille.
    } catch {
      seriesSuggestionsByRow[rowId] = []
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
        MetadataSheetMenuPicker(
          title: "Provider",
          selection: $coverProvider,
          options: coverProviders.map { (id: $0.value, label: $0.label) }
        )
        MetadataSheetSearchButton(
          isEnabled: !coverTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSearchingCovers
        ) {
          Task { await runCoverSearch() }
        }
      }

      coverResultsContent
    }
  }

  @ViewBuilder
  private var coverResultsContent: some View {
    if isSearchingCovers {
      MetadataSheetCard {
        AbstandLoadingSpinner(controlSize: .regular, verticalPadding: AppTheme.Layout.blockSpacing)
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
    GridItem(.flexible(), spacing: AppTheme.Layout.inlineSpacing),
    GridItem(.flexible(), spacing: AppTheme.Layout.inlineSpacing),
    GridItem(.flexible(), spacing: AppTheme.Layout.inlineSpacing),
  ]

  @ViewBuilder
  private var coverGrid: some View {
    LazyVGrid(columns: coverColumns, spacing: AppTheme.Layout.inlineSpacing) {
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

    if let failure = await model.applyMetadataMatch(itemId: itemId, patch: patch, coverURL: nil) {
      saveError = failure.isEmpty ? "Could not save metadata. Check your connection and permissions." : failure
    } else {
      dismiss()
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
    if let failure = await model.applyCoverURL(itemId: itemId, url: url) {
      coverApplyError = failure.isEmpty ? "Could not apply the cover. Check your connection and permissions." : failure
    } else {
      pendingCoverURL = nil
      dismiss()
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
private struct EditSeriesRow: Identifiable {
  /// Stabile Zeilen-ID für Vorschläge/Such-Tasks (nicht Teil des Patches).
  let id = UUID()
  var name: String = ""
  var sequence: String = ""

  var trimmed: EditSeriesRow {
    EditSeriesRow(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      sequence: sequence.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }
}
