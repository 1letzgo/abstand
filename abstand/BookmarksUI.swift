import SwiftUI

// MARK: - Bookmarks (detail & player)

struct BookmarksDisclosure: View {
  @EnvironmentObject private var model: AppModel
  @Binding var expanded: Bool
  let libraryItemId: String
  var onJump: (ABSAudioBookmark) -> Void

  @State private var confirmDelete: ABSAudioBookmark?

  private var marks: [ABSAudioBookmark] {
    model.bookmarks(for: libraryItemId)
  }

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 10) {
        if marks.isEmpty {
          Text(
            model.isNetworkReachable
              ? "No bookmarks for this audiobook yet. Set one while playing."
              : "Bookmarks are unavailable offline."
          )
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        } else {
          ForEach(marks) { mark in
            bookmarkRow(mark)
            if mark.id != marks.last?.id {
              Divider().background(AppTheme.textSecondary.opacity(0.15))
            }
          }
        }
      }
      .padding(.top, 4)
    } label: {
      Text("Bookmarks")
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .textCase(.uppercase)
        .tracking(0.6)
    }
    .tint(AppTheme.accent)
    .alert(
      "Delete bookmark?",
      isPresented: Binding(
        get: { confirmDelete != nil },
        set: { if !$0 { confirmDelete = nil } }
      )
    ) {
      Button("Cancel", role: .cancel) { confirmDelete = nil }
      Button("Delete", role: .destructive) {
        if let b = confirmDelete {
          Task { await model.deleteBookmark(b) }
        }
        confirmDelete = nil
      }
    } message: {
      if let b = confirmDelete {
        Text("“\(b.title)” at \(formatPlaybackTime(Double(b.time)))")
      }
    }
  }

  private func bookmarkRow(_ mark: ABSAudioBookmark) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Button {
        onJump(mark)
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(mark.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : mark.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
          Text(formatPlaybackTime(Double(mark.time)))
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)

      if model.isNetworkReachable {
        Button {
          confirmDelete = mark
        } label: {
          Image(systemName: "trash")
            .font(.body)
            .foregroundStyle(AppTheme.danger)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete bookmark")
      }
    }
    .padding(.vertical, 8)
  }
}

/// Titel eingeben, dann Lesezeichen anlegen (Speichern immer aktiv — leerer Titel → Standard aus Position).
struct AddBookmarkTitleSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let libraryItemId: String
  let timeSeconds: Int
  @State private var title: String
  @State private var saving = false

  init(libraryItemId: String, timeSeconds: Int, initialTitle: String) {
    self.libraryItemId = libraryItemId
    self.timeSeconds = timeSeconds
    _title = State(initialValue: initialTitle)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Title", text: $title)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled(false)
        } header: {
          Text("Title")
        } footer: {
          Text("Position: \(formatPlaybackTime(Double(timeSeconds)))")
        }
      }
      .scrollContentBackground(.hidden)
      .background(AppTheme.background)
      .navigationTitle("Bookmark")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(AppTheme.background, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(saving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard !saving else { return }
            saving = true
            Task {
              let ok = await model.createBookmark(
                libraryItemId: libraryItemId,
                time: timeSeconds,
                title: title
              )
              await MainActor.run {
                saving = false
                if ok { dismiss() }
              }
            }
          }
          .disabled(saving)
        }
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
    .preferredColorScheme(.dark)
  }
}

/// Bookmark control in the full-player utility bar: tap = title sheet; long-press = list.
struct PlayerBookmarkUtilityControl: View {
  @EnvironmentObject private var model: AppModel
  let activeAudiobookId: String?

  @State private var showAddSheet = false
  @State private var sheetTimeSeconds = 0

  private var marks: [ABSAudioBookmark] {
    guard let activeAudiobookId else { return [] }
    return model.bookmarks(for: activeAudiobookId)
  }

  var body: some View {
    if let activeAudiobookId {
      Button {
        sheetTimeSeconds = Int(model.player.globalPosition.rounded())
        showAddSheet = true
      } label: {
        VStack(spacing: FullPlayerUtilityBarLayout.rowSpacing) {
          Image(systemName: "bookmark")
            .font(.title3)
            .foregroundStyle(Color.white)
            .frame(
              maxWidth: .infinity,
              minHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              maxHeight: FullPlayerUtilityBarLayout.primaryRowHeight,
              alignment: .center
            )
          Text("Bookmark", comment: "Player control label")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Add bookmark at current position")
      .sheet(isPresented: $showAddSheet) {
        AddBookmarkTitleSheet(
          libraryItemId: activeAudiobookId,
          timeSeconds: sheetTimeSeconds,
          initialTitle: model.defaultBookmarkTitle(atSeconds: sheetTimeSeconds)
        )
        .environmentObject(model)
      }
      .contextMenu {
        if !marks.isEmpty {
          ForEach(marks) { mark in
            Button {
              Task { await model.jumpToBookmark(mark) }
            } label: {
              Text("\(mark.title) · \(formatPlaybackTime(Double(mark.time)))")
            }
          }
          Divider()
          ForEach(marks) { mark in
            Button(role: .destructive) {
              Task { await model.deleteBookmark(mark) }
            } label: {
              Label(mark.title, systemImage: "trash")
            }
          }
        }
      }
    }
  }
}
