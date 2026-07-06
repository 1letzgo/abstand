import SwiftUI

/// Metadaten-Editor + Cover-Online-Suche.
/// Sektion A: manuelle Bearbeitung aller Metadaten-Felder (Save via `PATCH /api/items/:id/media`).
/// Sektion B: Cover-Suche über `GET /api/search/covers` mit Grid-Vorschau + Apply via `POST /api/items/:id/cover`.
/// Admin/Root-only (`model.isServerAdmin || model.isServerRoot`).
struct EditMetadataSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.themeAccent) private var themeAccent

  let itemId: String
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

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
          metadataSection
          coverSearchSection
        }
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.tabPaddingTop)
        .padding(.bottom, AppTheme.Layout.scrollBottomInsetBase)
      }
      .abstandScrollScreenBackground()
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
      .alert("Save failed", isPresented: .constant(saveError != nil)) {
        Button("OK", role: .cancel) { saveError = nil }
      } message: { Text(saveError ?? "") }
      .alert("Apply cover failed", isPresented: .constant(coverApplyError != nil)) {
        Button("OK", role: .cancel) { coverApplyError = nil }
      } message: { Text(coverApplyError ?? "") }
      .alert("Apply this cover?", isPresented: .constant(pendingCoverURL != nil)) {
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

  // MARK: Metadata form

  @ViewBuilder
  private var metadataSection: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      sectionLabel("Details")
      metadataCard {
        fieldRow("Title", text: $title)
        fieldRow("Subtitle", text: $subtitle)
        fieldRow("Author", text: $author, hint: "Comma separated")
        fieldRow("Narrator", text: $narrator, hint: "Comma separated")
        seriesEditor
        fieldRowMultiline("Description", text: $descriptionText)
        fieldRow("Publisher", text: $publisher)
        HStack(spacing: 12) {
          fieldRow("Year", text: $publishedYear).keyboardType(.numberPad)
          fieldRow("Language", text: $language)
        }
        fieldRow("Genres", text: $genres, hint: "Comma separated")
        fieldRow("Tags", text: $tagsText, hint: "Comma separated")
        fieldRow("ASIN", text: $asin)
      }
    }
  }

  @ViewBuilder
  private func metadataCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AppTheme.Layout.detailSectionCardPadding)
    .background(AppTheme.card, in: cardShape)
    .abstandCardElevation(.subtle)
  }

  @ViewBuilder
  private func fieldRow(_ label: String, text: Binding<String>, hint: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      fieldLabel(label, hint: hint)
      TextField(label, text: text, axis: .horizontal)
        .textFieldStyle(.roundedBorder)
    }
  }

  @ViewBuilder
  private func fieldRowMultiline(_ label: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      fieldLabel(label)
      TextField(label, text: text, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(3...8)
    }
  }

  @ViewBuilder
  private func fieldLabel(_ label: String, hint: String? = nil) -> some View {
    HStack(spacing: 6) {
      Text(label)
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)
      if let hint {
        Text(hint)
          .font(.caption2)
          .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
      }
    }
  }

  // Series — wiederholbare Zeilen (Name + Sequence).
  @ViewBuilder
  private var seriesEditor: some View {
    VStack(alignment: .leading, spacing: 6) {
      fieldLabel("Series")
      ForEach(Array(seriesRows.enumerated()), id: \.offset) { idx, _ in
        HStack(spacing: 8) {
          TextField("Series name", text: $seriesRows[idx].name)
            .textFieldStyle(.roundedBorder)
          TextField("#", text: $seriesRows[idx].sequence)
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .keyboardType(.decimalPad)
          Button {
            if seriesRows.count == 1 {
              seriesRows[0] = EditSeriesRow()
            } else {
              seriesRows.remove(at: idx)
            }
          } label: {
            Image(systemName: "minus.circle")
              .foregroundStyle(AppTheme.textSecondary)
          }
          .buttonStyle(.plain)
        }
      }
      Button {
        seriesRows.append(EditSeriesRow())
      } label: {
        Label("Add series", systemImage: "plus.circle")
          .font(.footnote)
      }
      .buttonStyle(.plain)
      .foregroundStyle(themeAccent)
    }
  }

  // MARK: Cover search

  @ViewBuilder
  private var coverSearchSection: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      sectionLabel("Cover")
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          TextField("Title", text: $coverTitle)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.search)
            .onSubmit { Task { await runCoverSearch() } }
          TextField("Author", text: $coverAuthor)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.search)
            .onSubmit { Task { await runCoverSearch() } }
        }
        HStack(spacing: 8) {
          Picker("Provider", selection: $coverProvider) {
            ForEach(coverProviders, id: \.value) { p in
              Text(p.label).tag(p.value)
            }
          }
          .pickerStyle(.menu)
          Spacer()
          Button {
            Task { await runCoverSearch() }
          } label: {
            Label("Search", systemImage: "magnifyingglass")
              .labelStyle(.titleAndIcon)
          }
          .buttonStyle(.borderedProminent)
          .tint(themeAccent)
          .disabled(coverTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingCovers)
        }
      }

      if isSearchingCovers {
        ProgressView()
          .padding(.vertical, AppTheme.Layout.withinSectionSpacing)
          .frame(maxWidth: .infinity)
      } else if let coverSearchError {
        Text(coverSearchError)
          .font(.footnote)
          .foregroundStyle(AppTheme.danger)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else if coverResults.isEmpty {
        if hasSearchedCovers {
          Text("No covers found.")
            .font(.footnote)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppTheme.Layout.withinSectionSpacing)
        }
      } else {
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
              RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.card)
                .overlay { ProgressView() }
            case .success(let img):
              img.resizable().scaledToFit()
            default:
              RoundedRectangle(cornerRadius: 6)
                .fill(AppTheme.card)
                .overlay {
                  Image(systemName: "photo")
                    .foregroundStyle(AppTheme.textSecondary)
                }
            }
          }
          .aspectRatio(2/3, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isApplyingCover)
      }
    }
    .padding(.top, 4)
  }

  // MARK: Common helpers

  @ViewBuilder
  private func sectionLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(DetailHeroTypography.metaLabel)
      .foregroundStyle(AppTheme.textSecondary)
      .tracking(0.6)
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: AppTheme.Layout.detailSectionCardCornerRadius, style: .continuous)
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
