import SwiftUI

// MARK: - Bookmarks (detail & player)

/// Stabile Menüzeile (entkoppelt von `@Published bookmarks`-Ticks im Player).
struct PlayerBookmarkMenuItem: Equatable, Identifiable {
  let id: String
  let libraryItemId: String
  let title: String
  let time: Int

  init(_ mark: ABSAudioBookmark) {
    id = mark.id
    libraryItemId = mark.libraryItemId
    title = mark.title
    time = mark.time
  }

  var bookmark: ABSAudioBookmark {
    ABSAudioBookmark(libraryItemId: libraryItemId, title: title, time: time)
  }
}

struct BookmarksDisclosure: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.appearanceThemeRevision) private var themeRevision
  @Binding var expanded: Bool
  let libraryItemId: String
  var onJump: (ABSAudioBookmark) -> Void

  @State private var confirmDelete: ABSAudioBookmark?

  private var marks: [ABSAudioBookmark] {
    model.bookmarks(for: libraryItemId)
  }

  var body: some View {
    let _ = themeRevision
    return DisclosureGroup(isExpanded: $expanded) {
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
    .tint(model.appearanceAccentColor)
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
    .abstandThemeRefresh()
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
  @State private var timeSeconds = 0
  @State private var title = ""
  @State private var saving = false

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
      .abstandScrollScreenBackground()
      .navigationTitle("Bookmark")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(model.appearancePalette.background, for: .navigationBar)
      .toolbarColorScheme(model.resolvedInterfaceColorScheme, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(saving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard !saving else { return }
            saving = true
            let at = model.player.snapshotPlaybackTimeSeconds()
            Task {
              let ok = await model.createBookmark(
                libraryItemId: libraryItemId,
                time: at,
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
    .preferredColorScheme(model.resolvedInterfaceColorScheme)
    .onAppear { refreshPositionAndDefaultTitle() }
  }

  private func refreshPositionAndDefaultTitle() {
    let at = model.player.snapshotPlaybackTimeSeconds()
    timeSeconds = at
    title = model.defaultBookmarkTitle(atSeconds: at)
  }
}

/// Bookmark-Pille auf dem Cover: Tippen = Lesezeichen setzen; Long-Press = Sprungliste.
struct PlayerBookmarkCoverControl: View {
  @EnvironmentObject private var model: AppModel
  let activeAudiobookId: String
  let menuItems: [PlayerBookmarkMenuItem]

  @State private var showAddSheet = false

  var body: some View {
    PlayerBookmarkCoverControlChrome(
      menuItems: menuItems,
      showAddSheet: $showAddSheet,
      onJump: { mark in
        Task { await model.jumpToBookmark(mark) }
      }
    )
    .equatable()
    .sheet(isPresented: $showAddSheet) {
      AddBookmarkTitleSheet(libraryItemId: activeAudiobookId)
        .environmentObject(model)
    }
  }
}

private struct PlayerBookmarkCoverControlChrome: View, Equatable {
  let menuItems: [PlayerBookmarkMenuItem]
  @Binding var showAddSheet: Bool
  let onJump: (ABSAudioBookmark) -> Void
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.menuItems == rhs.menuItems && lhs.showAddSheet == rhs.showAddSheet
  }

  var body: some View {
    let _ = themeRevision
    Button {
      showAddSheet = true
    } label: {
      Image(systemName: "bookmark")
        .font(.body.weight(.semibold))
        .symbolVariant(.fill)
        .foregroundStyle(themeAccent)
        .frame(width: 36, height: 36)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(themeAccent.opacity(0.55), lineWidth: 0.5)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Add bookmark at current position")
    .contextMenu {
      if !menuItems.isEmpty {
        ForEach(menuItems) { item in
          Button {
            onJump(item.bookmark)
          } label: {
            Text("\(item.title) · \(formatPlaybackTime(Double(item.time)))")
          }
        }
      }
    }
  }
}
