import SwiftUI

/// Kapitel-Editor-Sheet: Audible-Kapitel-Lookup via Audnexus (`GET /api/search/chapters`),
/// Vorschau inkl. „Branding entfernen"-Option, Apply via `POST /api/items/:id/chapters`.
/// Vollständige Übernahme von Zeiten + Titeln (keine manuelle Einzeledit). Admin/Root-only.
struct ChaptersEditorSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.themeAccent) private var themeAccent

  let itemId: String
  /// ASIN aus Buch-Metadaten (Prefill).
  let currentASIN: String?
  /// Medien-Gesamtdauer in Sekunden — Fallback für das `end` des letzten Kapitels.
  let mediaDuration: Double?

  // Lookup-State
  @State private var asinInput: String = ""
  @State private var region: String = "us"
  @State private var response: ABSAudibleChaptersResponse?
  @State private var isSearching = false
  @State private var lookupError: String?

  // Apply-State
  @State private var removeBranding = false
  @State private var isApplying = false
  @State private var applyError: String?

  /// Verfügbare Audible-Regionen (Lowercase für API, Display uppercase).
  private let regions: [(value: String, label: String)] = [
    ("us", "US"), ("gb", "UK"), ("de", "DE"), ("ca", "CA"), ("au", "AU"),
    ("fr", "FR"), ("jp", "JP"), ("it", "IT"), ("in", "IN"), ("es", "ES"),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          lookupHeader
          if isSearching {
            ProgressView()
              .padding(.top, AppTheme.Layout.sectionSpacing)
              .frame(maxWidth: .infinity)
          } else if let lookupError {
            Text(lookupError)
              .font(.footnote)
              .foregroundStyle(AppTheme.danger)
              .frame(maxWidth: .infinity)
              .padding(.top, AppTheme.Layout.sectionSpacing)
          } else if let serverError = response?.error {
            Text(serverError)
              .font(.footnote)
              .foregroundStyle(AppTheme.danger)
              .frame(maxWidth: .infinity)
              .padding(.top, AppTheme.Layout.sectionSpacing)
          } else if let resp = response, !resp.chapters.isEmpty {
            resultsPreview(resp)
          } else {
            emptyState
          }
        }
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.tabPaddingTop)
        .padding(.bottom, AppTheme.Layout.scrollBottomInsetBase)
      }
      .abstandScrollScreenBackground()
      .navigationTitle("Edit Chapters")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        if response?.chapters.isEmpty == false {
          ToolbarItem(placement: .confirmationAction) {
            Button("Apply") { Task { await applyChapters() } }
              .disabled(isApplying)
          }
        }
      }
      .onAppear { prefetchASIN() }
      .alert("Apply failed", isPresented: .constant(applyError != nil)) {
        Button("OK", role: .cancel) { applyError = nil }
      } message: {
        Text(applyError ?? "")
      }
    }
    .presentationDetents([.large])
  }

  // MARK: Lookup header

  @ViewBuilder
  private var lookupHeader: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Audible ASIN")
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
        TextField("e.g. B08XYZ1234", text: $asinInput)
          .textFieldStyle(.roundedBorder)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .submitLabel(.search)
          .onSubmit { Task { await runLookup() } }
      }
      HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Region")
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
          Picker("Region", selection: $region) {
            ForEach(regions, id: \.value) { r in
              Text(r.label).tag(r.value)
            }
          }
          .pickerStyle(.menu)
        }
        Spacer()
        Button {
          Task { await runLookup() }
        } label: {
          Label("Search", systemImage: "magnifyingglass")
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(AbstandProminentButtonStyle())
        .disabled(asinInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
      }
    }
  }

  // MARK: Empty state

  @ViewBuilder
  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "list.bullet.below.rectangle")
        .font(.system(size: 40))
        .foregroundStyle(AppTheme.textSecondary)
      Text("Enter an Audible ASIN to fetch chapter timings.")
        .font(.footnote)
        .foregroundStyle(AppTheme.textSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, AppTheme.Layout.sectionSpacing * 1.5)
  }

  // MARK: Results preview

  @ViewBuilder
  private func resultsPreview(_ resp: ABSAudibleChaptersResponse) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      // Branding-Toggle nur relevant, wenn der Server Branding-Dauern liefert.
      if resp.brandIntroDurationMs != nil || resp.brandOutroDurationMs != nil {
        Toggle(isOn: $removeBranding) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Remove branding")
              .font(.subheadline)
            Text("Strip Audible intro/outro from chapter timings.")
              .font(.caption)
              .foregroundStyle(AppTheme.textSecondary)
          }
        }
        .tint(themeAccent)
      }

      Text("\(previewChapters.count) chapters")
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)

      LazyVStack(spacing: 0) {
        ForEach(Array(previewChapters.enumerated()), id: \.offset) { idx, ch in
          VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
              Text("\(idx + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 24, alignment: .leading)
              VStack(alignment: .leading, spacing: 2) {
                Text(ch.title.isEmpty ? "Chapter \(idx + 1)" : ch.title)
                  .font(.subheadline)
                  .foregroundStyle(AppTheme.textPrimary)
                  .lineLimit(2)
                Text("\(formatPlaybackTime(ch.start)) – \(formatPlaybackTime(ch.end))")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(AppTheme.textSecondary)
              }
              Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            if idx < previewChapters.count - 1 {
              Divider().background(AppTheme.textSecondary.opacity(0.15))
            }
          }
        }
      }
      .padding(AppTheme.Layout.detailSectionCardPadding)
      .background(AppTheme.card)
      .clipShape(
        RoundedRectangle(cornerRadius: AppTheme.Layout.detailSectionCardCornerRadius,
                         style: .continuous)
      )
      .abstandCardElevation(.subtle)
    }
    .padding(.top, AppTheme.Layout.withinSectionSpacing)
  }

  // MARK: Derived chapters (inkl. Branding-Entfernung)

  /// Die für Vorschau/Apply bestimmten Kapitel — ggf. um Audible-Branding bereinigt.
  private var previewChapters: [(title: String, start: Double, end: Double)] {
    guard let resp = response else { return [] }
    let raw = resp.chapters.sorted { $0.start < $1.start }
    guard !raw.isEmpty else { return [] }

    // Gesamtlaufzeit: bevorzugt `runtimeLengthSec`, Fallback auf `mediaDuration`.
    let total = resp.runtimeLengthSec ?? mediaDuration ?? 0
    let introSec = (resp.brandIntroDurationMs ?? 0) / 1000.0
    let outroSec = (resp.brandOutroDurationMs ?? 0) / 1000.0

    var entries: [(title: String, start: Double, end: Double)] = []
    for (i, ch) in raw.enumerated() {
      var start = ch.start
      var end: Double
      if i + 1 < raw.count {
        end = raw[i + 1].start
      } else {
        // Letztes Kapitel: bis Gesamtlaufzeit bzw. start+length.
        end = total > 0 ? total : (ch.start + ch.length)
      }
      if removeBranding {
        start = max(0, start - introSec)
        end = max(start, end - introSec)
      }
      entries.append((ch.title, start, end))
    }

    // Branding entfernen: evtl. trailing Kapitel das nur aus Outro besteht, wegfallen.
    if removeBranding && outroSec > 0, var last = entries.last {
      let lastLen = last.end - last.start
      if lastLen <= outroSec {
        entries.removeLast()
      } else {
        last.end = max(last.start, last.end - outroSec)
        entries[entries.count - 1] = last
      }
    }
    return entries
  }

  // MARK: Actions

  private func prefetchASIN() {
    if asinInput.isEmpty {
      asinInput = currentASIN ?? ""
    }
  }

  private func runLookup() async {
    let asin = asinInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !asin.isEmpty else { return }
    isSearching = true
    lookupError = nil
    response = nil
    do {
      let resp = try await model.searchAudibleChapters(asin: asin, region: region)
      response = resp
    } catch is CancellationError {
      // Stille — bspw. Sheet schließt.
    } catch {
      lookupError = error.localizedDescription
    }
    isSearching = false
  }

  private func applyChapters() async {
    let entries = previewChapters
    guard !entries.isEmpty else { return }
    isApplying = true
    defer { isApplying = false }

    let payload = entries.enumerated().map { idx, ch in
      ABSItemChaptersPayload.Chapter(
        id: idx,
        start: ch.start,
        end: ch.end,
        title: ch.title
      )
    }
    let ok = await model.applyItemChapters(itemId: itemId, chapters: payload)
    if ok {
      dismiss()
    } else {
      applyError = model.errorMessage?.isEmpty == false
        ? model.errorMessage!
        : "Could not apply the chapters. Check your connection and permissions."
    }
  }
}
