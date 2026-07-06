import SwiftUI
import Combine

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

  var body: some View {
    let _ = themeRevision
    return DetailMetaDisclosure(title: "Bookmarks", isExpanded: $expanded) {
      AudiobookBookmarkListView(libraryItemId: libraryItemId, onJump: onJump)
    }
    .tint(model.appearanceAccentColor)
    .abstandThemeRefresh()
  }
}

/// Lesezeichen-Liste (Book Detail + Vollplayer-Cover-Panel).
struct AudiobookBookmarkListView: View {
  @EnvironmentObject private var model: AppModel
  let libraryItemId: String
  let onJump: (ABSAudioBookmark) -> Void

  @State private var confirmDelete: ABSAudioBookmark?

  private var marks: [ABSAudioBookmark] {
    model.bookmarks(for: libraryItemId)
  }

  var body: some View {
    Group {
      if marks.isEmpty {
        Text(
          model.isNetworkReachable
            ? "No bookmarks for this audiobook yet. Set one while playing."
            : "Bookmarks are unavailable offline."
        )
        .font(.body)
        .foregroundStyle(AppTheme.textSecondary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(marks) { mark in
            AudiobookBookmarkRow(
              mark: mark,
              showsDelete: model.isNetworkReachable,
              onJump: onJump,
              onDelete: { confirmDelete = mark }
            )
            if mark.id != marks.last?.id {
              Divider().background(AppTheme.textSecondary.opacity(0.15))
            }
          }
        }
      }
    }
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
}

private struct AudiobookBookmarkRow: View {
  let mark: ABSAudioBookmark
  let showsDelete: Bool
  let onJump: (ABSAudioBookmark) -> Void
  let onDelete: () -> Void

  var body: some View {
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

      if showsDelete {
        Button(action: onDelete) {
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
    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
      refreshPositionAndDefaultTitle()
    }
  }

  private func refreshPositionAndDefaultTitle() {
    let at = model.player.snapshotPlaybackTimeSeconds()
    timeSeconds = at
    title = model.defaultBookmarkTitle(atSeconds: at)
  }
}

/// Bookmark-Pille auf dem Cover: Tippen = Lesezeichen anlegen; Kontextmenü = Sprungliste.
struct PlayerBookmarkAddCoverControl: View {
  @EnvironmentObject private var model: AppModel
  let activeAudiobookId: String
  let menuItems: [PlayerBookmarkMenuItem]
  /// Kompakter Kreis wie Teleprompter ± (in Panel-Karte statt Steuerzeile).
  var compact: Bool = false

  @State private var showAddSheet = false

  var body: some View {
    PlayerBookmarkAddCoverControlChrome(
      menuItems: menuItems,
      compact: compact,
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

private struct PlayerBookmarkAddCoverControlChrome: View, Equatable {
  let menuItems: [PlayerBookmarkMenuItem]
  var compact: Bool = false
  @Binding var showAddSheet: Bool
  let onJump: (ABSAudioBookmark) -> Void
  @Environment(\.appearanceThemeRevision) private var themeRevision

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.menuItems == rhs.menuItems
      && lhs.compact == rhs.compact
      && lhs.showAddSheet == rhs.showAddSheet
      && lhs.themeRevision == rhs.themeRevision
  }

  var body: some View {
    let _ = themeRevision
    return FullPlayerCoverOverlayButton(
      systemName: "bookmark",
      isActive: false,
      compact: compact,
      accessibilityLabel: "Add bookmark at current position",
      action: { showAddSheet = true }
    )
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
