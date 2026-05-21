import SwiftUI

// MARK: - Shared layout

private struct ServerAdminScrollScreen<Content: View>: View {
  @EnvironmentObject private var model: AppModel
  @ViewBuilder let content: () -> Content

  var body: some View {
    ScrollView {
      content()
        .padding(.horizontal, AppTheme.Layout.tabPaddingH)
        .padding(.top, AppTheme.Layout.withinSectionSpacing)
        .padding(
          .bottom,
          AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset
        )
    }
    .abstandScrollScreenBackground(ignoreSafeArea: true)
  }
}

private struct ServerAdminSectionLabel: View {
  let title: String

  var body: some View {
    TabContentSectionTitle(title: title)
  }
}

/// Wie `Form`-Section in App Settings: enger Abstand Überschrift → Inhalt, `sectionSpacing` nur zwischen Blöcken.
private struct ServerAdminSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      ServerAdminSectionLabel(title: title)
      content()
    }
  }
}

private struct ServerAdminCard<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(AppTheme.card)
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }
}

private struct ServerAdminNavRow: View {
  let icon: String
  let title: String
  let subtitle: String?

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.body.weight(.semibold))
        .foregroundStyle(AppTheme.accent)
        .frame(width: 28, alignment: .center)
      VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
        Text(title)
          .font(.body.weight(.medium))
          .foregroundStyle(AppTheme.textPrimary)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
    }
  }
}

// MARK: - Settings card rows

private struct SettingsCardIcon: View {
  let systemName: String
  var tint: Color = AppTheme.accent

  var body: some View {
    Image(systemName: systemName)
      .font(.body.weight(.semibold))
      .foregroundStyle(tint)
      .frame(width: 28, alignment: .center)
  }
}

private struct SettingsCardToggleRow: View {
  let icon: String
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: icon)
      Toggle(isOn: $isOn) {
        Text(title)
          .font(.body)
          .foregroundStyle(AppTheme.textPrimary)
      }
      .tint(AppTheme.accent)
    }
  }
}

private struct SettingsCardPickerRow: View {
  let icon: String
  let title: String
  @Binding var selection: String
  let options: [(id: String, label: String)]

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: icon)
      Text(title)
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
      Spacer(minLength: 8)
      Picker(title, selection: $selection) {
        ForEach(options, id: \.id) { opt in
          Text(opt.label).tag(opt.id)
        }
      }
      .labelsHidden()
      .tint(AppTheme.accent)
    }
  }
}

private struct SettingsCardActionRow: View {
  let icon: String
  let title: String
  let subtitle: String?
  let trailingIcon: String
  var isEnabled: Bool = true

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: icon)
      VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
        Text(title)
          .font(.body.weight(.medium))
          .foregroundStyle(AppTheme.textPrimary)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: trailingIcon)
        .foregroundStyle(AppTheme.textSecondary)
    }
    .opacity(isEnabled ? 1 : 0.45)
  }
}

private func startShelfSettingsIcon(category: String) -> String {
  switch category {
  case "continueListening", "recentlyListened": return "play.circle.fill"
  case "continueEbooks": return "book.closed.fill"
  case "recentlyAdded": return "sparkles"
  case "recentSeries": return "books.vertical.fill"
  case "newestAuthors": return "person.fill"
  case "discover": return "lightbulb.fill"
  default: return "square.grid.2x2"
  }
}

// MARK: - Settings hub (Tab)

private enum SettingsHubScope: String, CaseIterable, Identifiable {
  case stats = "Stats"
  case user = "User"
  case server = "Server"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .stats: return "chart.bar.fill"
    case .user: return "person.crop.circle"
    case .server: return "server.rack"
    }
  }

  static func visibleCases(isServerRoot: Bool) -> [SettingsHubScope] {
    isServerRoot ? [.user, .stats, .server] : [.user, .stats]
  }
}

private struct SettingsScopeStrip: View {
  let scopes: [SettingsHubScope]
  @Binding var selection: SettingsHubScope

  var body: some View {
    let tile = AppTheme.Layout.horizontalBrowseStripTile
    let captionW = tile + AppTheme.Layout.horizontalBrowseStripLabelWidthExtra
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: AppTheme.Layout.horizontalBrowseStripInterTileSpacing) {
        ForEach(scopes) { scope in
          Button {
            withAnimation(.easeOut(duration: 0.2)) {
              selection = scope
            }
          } label: {
            VStack(spacing: AppTheme.Layout.horizontalBrowseStripTileLabelSpacing) {
              ZStack {
                RoundedRectangle(
                  cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous
                )
                .fill(AppTheme.card)
                .frame(width: tile, height: tile)
                Image(systemName: scope.icon)
                  .font(.title2)
                  .foregroundStyle(selection == scope ? AppTheme.accent : AppTheme.textSecondary)
              }
              .overlay {
                RoundedRectangle(
                  cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous
                )
                .strokeBorder(
                  selection == scope ? AppTheme.accent : Color.clear, lineWidth: 2.5)
              }
              Text(scope.rawValue)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(width: captionW)
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, AppTheme.Layout.horizontalBrowseStripVerticalPadding)
    }
    .scrollContentBackground(.hidden)
  }
}

struct SettingsHubRootView: View {
  @EnvironmentObject private var model: AppModel
  @State private var coverCacheByteCount: Int64 = 0
  @State private var hubScope: SettingsHubScope = .user

  private var visibleHubScopes: [SettingsHubScope] {
    SettingsHubScope.visibleCases(isServerRoot: model.isServerRoot)
  }

  private var booksLibraryPickerSelection: Binding<String> {
    Binding(
      get: {
        if model.booksLibraryPreferenceIsNone { return AppModel.libraryPickerNoneTag }
        return model.selectedBooksLibrary?.id ?? AppModel.libraryPickerNoneTag
      },
      set: { newId in
        if newId == AppModel.libraryPickerNoneTag {
          model.clearBooksLibrarySelection()
        } else if let lib = model.sortedBookLibraries.first(where: { $0.id == newId }) {
          model.selectBooksLibrary(lib, navigateToCatalog: true)
          Task { await model.reloadLibrary(reset: true) }
        }
      })
  }

  private var podcastsLibraryPickerSelection: Binding<String> {
    Binding(
      get: {
        if model.podcastsLibraryPreferenceIsNone { return AppModel.libraryPickerNoneTag }
        return model.selectedPodcastLibrary?.id ?? AppModel.libraryPickerNoneTag
      },
      set: { newId in
        if newId == AppModel.libraryPickerNoneTag {
          model.clearPodcastLibrarySelection()
        } else if let lib = model.sortedPodcastLibraries.first(where: { $0.id == newId }) {
          model.selectPodcastLibrary(lib, navigateToCatalog: true)
          Task { await model.reloadPodcastLibrary(reset: true) }
        }
      })
  }

  private var coverCacheSizeLabel: String {
    guard model.coverImageCacheAccountDirectory() != nil else {
      return "Cover art is cached after you sign in."
    }
    if coverCacheByteCount == 0 {
      return "No cover cache in use."
    }
    return ByteCountFormatter.string(fromByteCount: coverCacheByteCount, countStyle: .file)
  }

  private func refreshCoverCacheByteCount() {
    coverCacheByteCount = model.coverImageCacheByteCount()
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        SettingsScopeStrip(scopes: visibleHubScopes, selection: $hubScope)

        switch hubScope {
        case .stats:
          StatsTabView(embeddedInParentScroll: true)
        case .user:
          userSettingsSections
          logoutSection
        case .server:
          serverSettingsMenuSections
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.withinSectionSpacing)
      .padding(
        .bottom,
        AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset
      )
    }
    .abstandScrollScreenBackground(ignoreSafeArea: true)
    .navigationTitle(AppModel.MainTab.settings.rawValue)
    .toolbarTitleDisplayMode(.inlineLarge)
    .tint(AppTheme.accent)
    .onAppear {
      refreshCoverCacheByteCount()
      clampHubScopeIfNeeded()
    }
    .onChange(of: model.coverImageCacheRevision) { _, _ in
      refreshCoverCacheByteCount()
    }
    .onChange(of: model.isServerRoot) { _, _ in
      clampHubScopeIfNeeded()
    }
    .onChange(of: hubScope) { _, scope in
      if scope == .stats {
        Task { await model.loadListeningStats() }
      } else if scope == .user, !model.offlineHomeUIActive {
        Task { await model.reloadSettingsTab() }
      }
    }
    .onChange(of: model.offlineHomeUIActive) { _, offline in
      if !offline, hubScope == .user {
        Task { await model.reloadSettingsTab() }
      }
    }
    .task {
      if hubScope == .stats {
        await model.loadListeningStats()
      }
    }
  }

  private func clampHubScopeIfNeeded() {
    let visible = visibleHubScopes
    if !visible.contains(hubScope), let first = visible.first {
      hubScope = first
    }
  }

  @ViewBuilder
  private var userSettingsSections: some View {
    ServerAdminSection(title: "Libraries") {
      ServerAdminCard {
        VStack(alignment: .leading, spacing: 12) {
          if model.sortedBookLibraries.isEmpty {
            Text("No book libraries on this server.")
              .font(.subheadline)
              .foregroundStyle(AppTheme.textSecondary)
          } else {
            SettingsCardPickerRow(
              icon: "books.vertical.fill",
              title: "Books",
              selection: booksLibraryPickerSelection,
              options: [(id: AppModel.libraryPickerNoneTag, label: "None")]
                + model.sortedBookLibraries.map { (id: $0.id, label: $0.name) }
            )
          }
          if model.sortedPodcastLibraries.isEmpty {
            Text("No podcast libraries on this server.")
              .font(.subheadline)
              .foregroundStyle(AppTheme.textSecondary)
          } else {
            SettingsCardPickerRow(
              icon: "mic.fill",
              title: "Podcasts",
              selection: podcastsLibraryPickerSelection,
              options: [(id: AppModel.libraryPickerNoneTag, label: "None")]
                + model.sortedPodcastLibraries.map { (id: $0.id, label: $0.name) }
            )
          }
        }
      }
    }

    ServerAdminSection(title: "Downloads") {
      ServerAdminCard {
        VStack(alignment: .leading, spacing: 12) {
          SettingsCardToggleRow(icon: "arrow.down.circle", title: "Auto download", isOn: $model.smartDownloadOnWiFi)
          Divider().overlay(AppTheme.textSecondary.opacity(0.25))
          SettingsCardToggleRow(
            icon: "checkmark.circle",
            title: "Remove download when finished",
            isOn: $model.smartDownloadRemoveWhenFinished)
          Divider().overlay(AppTheme.textSecondary.opacity(0.25))
          Button {
            model.clearCoverImageCache()
            refreshCoverCacheByteCount()
          } label: {
            SettingsCardActionRow(
              icon: "photo.on.rectangle.angled",
              title: "Clear cover cache",
              subtitle: coverCacheSizeLabel,
              trailingIcon: "trash",
              isEnabled: model.coverImageCacheAccountDirectory() != nil
            )
          }
          .buttonStyle(.plain)
          .disabled(model.coverImageCacheAccountDirectory() == nil)
        }
      }
    }
    .disabled(model.offlineHomeUIActive)

    ServerAdminSection(title: "Home") {
      NavigationLink {
        SettingsHomeShelvesView()
      } label: {
        ServerAdminCard {
          ServerAdminNavRow(
            icon: "house.fill",
            title: "Home shelves",
            subtitle: "Show or hide shelves on Home"
          )
        }
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private var serverSettingsMenuSections: some View {
    if model.podcastCanManageShowsOnServer {
      ServerAdminSection(title: "Podcasts") {
        NavigationLink {
          PodcastAddFromSearchView()
            .navigationTitle("Add podcast")
            .toolbarTitleDisplayMode(.inline)
        } label: {
          ServerAdminCard {
            ServerAdminNavRow(
              icon: "plus.circle.fill",
              title: "Add podcast",
              subtitle: "Search or browse iTunes Top Charts"
            )
          }
        }
        .buttonStyle(.plain)
        .disabled(model.selectedPodcastLibrary == nil || !model.isNetworkReachable)

        NavigationLink {
          ServerAdminPodcastShowsListView()
        } label: {
          ServerAdminCard {
            ServerAdminNavRow(
              icon: "list.bullet",
              title: "Manage shows",
              subtitle: "RSS feed, auto-download, unsubscribe"
            )
          }
        }
        .buttonStyle(.plain)
      }
    }

    ServerAdminSection(title: "Users") {
      NavigationLink {
        ServerUsersListView()
      } label: {
        ServerAdminCard {
          ServerAdminNavRow(icon: "person.2.fill", title: "Users", subtitle: nil)
        }
      }
      .buttonStyle(.plain)
    }

    ServerAdminLibrariesSection()
  }

  private var logoutSection: some View {
    ServerAdminSection(title: "Account") {
      ServerAdminCard {
        Button {
          model.logout()
        } label: {
          HStack(spacing: 12) {
            SettingsCardIcon(systemName: "rectangle.portrait.and.arrow.right", tint: AppTheme.danger)
            Text("Log out")
              .font(.body.weight(.medium))
              .foregroundStyle(AppTheme.danger)
            Spacer(minLength: 0)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }
}

// MARK: - Home shelves (user settings)

struct SettingsHomeShelvesView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ServerAdminScrollScreen {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        ServerAdminSection(title: "Home shelves") {
          ServerAdminCard {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(Array(model.startSettingsCategoryList.enumerated()), id: \.element.category) {
                index, row in
                if index > 0 {
                  Divider().overlay(AppTheme.textSecondary.opacity(0.25))
                }
                VStack(alignment: .leading, spacing: 8) {
                  SettingsCardToggleRow(
                    icon: startShelfSettingsIcon(category: row.category),
                    title: row.label,
                    isOn: Binding(
                      get: { model.isStartCategoryEnabled(row.category) },
                      set: { model.setStartCategoryEnabled(row.category, enabled: $0) }
                    )
                  )
                  if model.isStartCategoryEnabled(row.category),
                    model.supportsStartShelfBookLayoutSetting(row.category)
                  {
                    Picker(
                      "Layout",
                      selection: Binding(
                        get: { model.startShelfBookLayout(for: row.category) },
                        set: { model.setStartShelfBookLayout(row.category, layout: $0) }
                      )
                    ) {
                      ForEach(StartShelfBookLayout.allCases) { layout in
                        Text(layout.label).tag(layout)
                      }
                    }
                    .pickerStyle(.segmented)
                  }
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Home shelves")
    .toolbarTitleDisplayMode(.inlineLarge)
    .tint(AppTheme.accent)
  }
}

// MARK: - Users

struct ServerUsersListView: View {
  @EnvironmentObject private var model: AppModel
  @State private var users: [ABSAdminUserSummary] = []
  @State private var onlineIds: Set<String> = []
  @State private var loading = false
  @State private var loadError: String?

  var body: some View {
    Group {
      if loading && users.isEmpty {
        ProgressView()
          .tint(AppTheme.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let loadError, users.isEmpty {
        ContentUnavailableView(
          "Could not load users",
          systemImage: "person.2.slash",
          description: Text(loadError)
        )
      } else {
        ServerAdminScrollScreen {
          LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
            ServerAdminSection(title: "Users") {
              LazyVStack(spacing: 8) {
                ForEach(users) { user in
                  NavigationLink {
                    ServerUserDetailView(userId: user.id, username: user.username)
                  } label: {
                    ServerAdminCard {
                      ServerUserListRow(user: user, isOnline: onlineIds.contains(user.id))
                    }
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }
        }
      }
    }
    .background(AppTheme.background.ignoresSafeArea())
    .navigationTitle("Users")
    .toolbarTitleDisplayMode(.inlineLarge)
    .tint(AppTheme.accent)
    .refreshable { await reload() }
    .task { await reload() }
  }

  private func reload() async {
    loading = true
    defer { loading = false }
    do {
      async let userRows = model.fetchServerUsers()
      async let online = model.fetchServerOnlineUserIds()
      users = try await userRows
      onlineIds = try await online
      loadError = nil
    } catch {
      loadError = error.localizedDescription
    }
  }
}

private struct ServerUserListRow: View {
  let user: ABSAdminUserSummary
  let isOnline: Bool

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(isOnline ? AppTheme.success : Color.secondary.opacity(0.35))
        .frame(width: 8, height: 8)
      Text(user.username)
        .font(.body.weight(.medium))
        .foregroundStyle(AppTheme.textPrimary)
      if user.isRoot {
        Text("root")
          .font(.caption2.weight(.semibold))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(AppTheme.accent.opacity(0.2))
          .foregroundStyle(AppTheme.accent)
          .clipShape(Capsule())
      } else if let type = user.typeLabel {
        Text(type)
          .font(.caption2)
          .foregroundStyle(AppTheme.textSecondary)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.textSecondary)
    }
  }
}

// MARK: - User detail

struct ServerUserDetailView: View {
  @EnvironmentObject private var model: AppModel
  let userId: String
  let username: String

  @State private var detail: ABSAdminUserDetail?
  @State private var loading = false
  @State private var loadError: String?
  @State private var showSessions = false

  private var progressRows: [ABSAdminMediaProgressRow] {
    detail?.mediaProgressSorted ?? []
  }

  private var inProgressCount: Int {
    progressRows.filter { $0.isInProgress }.count
  }

  private var finishedCount: Int {
    progressRows.filter(\.isFinished).count
  }

  var body: some View {
    ServerAdminScrollScreen {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        if loading && detail == nil {
          ProgressView()
            .tint(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if let loadError, detail == nil {
          Text(loadError)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else if let detail {
          headerBlock(detail)
          summaryStrip
          recentSessionsButton
          libraryProgressSection
        }
      }
    }
    .navigationTitle(username)
    .toolbarTitleDisplayMode(.inlineLarge)
    .tint(AppTheme.accent)
    .navigationDestination(isPresented: $showSessions) {
      ServerUserListeningSessionsView(userId: userId, username: username)
    }
    .refreshable { await reload() }
    .task { await reload() }
  }

  private func headerBlock(_ detail: ABSAdminUserDetail) -> some View {
    HStack(spacing: 8) {
      Text(detail.lastSeenCaption)
        .font(.subheadline)
        .foregroundStyle(AppTheme.textSecondary)
      if let type = detail.typeLabel {
        Text(type)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(AppTheme.card)
          .foregroundStyle(AppTheme.textSecondary)
          .clipShape(Capsule())
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var summaryStrip: some View {
    HStack(spacing: 10) {
      summaryCard(value: "\(inProgressCount)", label: "In Progress", color: AppTheme.accent)
      summaryCard(value: "\(finishedCount)", label: "Finished", color: AppTheme.success)
      summaryCard(value: "\(progressRows.count)", label: "Total", color: AppTheme.textPrimary)
    }
  }

  private func summaryCard(value: String, label: String, color: Color) -> some View {
    VStack(spacing: 6) {
      Text(value)
        .font(.title2.weight(.bold))
        .foregroundStyle(color)
      Text(label)
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
  }

  private var recentSessionsButton: some View {
    Button {
      showSessions = true
    } label: {
      ServerAdminCard {
        HStack {
          Image(systemName: "clock.arrow.circlepath")
            .foregroundStyle(AppTheme.accent)
          Text("Recent Sessions")
            .fontWeight(.medium)
            .foregroundStyle(AppTheme.textPrimary)
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
        }
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var libraryProgressSection: some View {
    if !progressRows.isEmpty {
      ServerAdminSection(title: "Library Progress") {
        ForEach(progressRows) { row in
          BookRowCard(
            book: row.asBookStub(),
            model: model,
            progressOverride: row.asUserMediaProgress(),
            authorLineOverride: row.resolvedAuthorForCard,
            showsPlaybackControls: false,
            showsDownloadStatus: false
          )
        }
      }
    }
  }

  private func reload() async {
    loading = true
    defer { loading = false }
    do {
      detail = try await model.fetchServerUserDetail(userId: userId)
      loadError = nil
    } catch {
      loadError = error.localizedDescription
    }
  }
}

struct ServerUserListeningSessionsView: View {
  @EnvironmentObject private var model: AppModel
  let userId: String
  let username: String

  @State private var sessions: [ABSListeningSession] = []
  @State private var loading = false
  @State private var loadError: String?

  var body: some View {
    Group {
      if loading && sessions.isEmpty {
        ProgressView()
          .tint(AppTheme.accent)
      } else if let loadError, sessions.isEmpty {
        ContentUnavailableView(
          "No sessions",
          systemImage: "clock",
          description: Text(loadError)
        )
      } else if sessions.isEmpty {
        ContentUnavailableView("No sessions", systemImage: "clock")
      } else {
        ServerAdminScrollScreen {
          LazyVStack(spacing: 8) {
            ForEach(sessions) { session in
              ServerAdminCard {
                VStack(alignment: .leading, spacing: 4) {
                  Text(session.libraryItemId.isEmpty ? session.id : session.libraryItemId)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                  Text(
                    "\(formatPlaybackTime(session.startTime)) → \(formatPlaybackTime(session.currentTime))"
                  )
                  .font(.caption)
                  .foregroundStyle(AppTheme.textSecondary)
                }
              }
            }
          }
        }
      }
    }
    .background(AppTheme.background.ignoresSafeArea())
    .navigationTitle("Recent Sessions")
    .toolbarTitleDisplayMode(.inline)
    .tint(AppTheme.accent)
    .task { await reload() }
  }

  private func reload() async {
    loading = true
    defer { loading = false }
    do {
      let payload = try await model.fetchServerUserListeningSessions(userId: userId)
      sessions = payload.sessions
      loadError = nil
    } catch {
      loadError = error.localizedDescription
    }
  }
}

// MARK: - Libraries

/// Bibliotheksliste direkt in Server Settings (ohne Zwischen-Navigation).
private struct ServerAdminLibrariesSection: View {
  @EnvironmentObject private var model: AppModel
  @State private var scanningId: String?
  @State private var scanMessage: String?

  private var sortedLibraries: [ABSLibrary] {
    model.libraries.sorted { $0.displayOrderOrZero < $1.displayOrderOrZero }
  }

  var body: some View {
    ServerAdminSection(title: "Libraries") {
      LazyVStack(spacing: 8) {
        if let scanMessage {
          Text(scanMessage)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
        }
        if sortedLibraries.isEmpty {
          Text("No libraries on this server.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
          ForEach(sortedLibraries) { lib in
            NavigationLink {
              ServerLibraryDetailView(library: lib)
            } label: {
              ServerAdminCard {
                HStack(spacing: 12) {
                  Image(systemName: "books.vertical.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, alignment: .center)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(lib.name)
                      .font(.body.weight(.medium))
                      .foregroundStyle(AppTheme.textPrimary)
                    Text(lib.mediaType?.capitalized ?? "Library")
                      .font(.caption)
                      .foregroundStyle(AppTheme.textSecondary)
                  }
                  Spacer(minLength: 0)
                  if scanningId == lib.id {
                    ProgressView()
                      .controlSize(.small)
                  } else {
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(AppTheme.textSecondary)
                  }
                }
              }
            }
            .buttonStyle(.plain)
            .contextMenu {
              Button {
                Task { await scanLibrary(lib) }
              } label: {
                Label("Scan", systemImage: "arrow.clockwise")
              }
            }
          }
        }
      }
    }
  }

  private func scanLibrary(_ lib: ABSLibrary) async {
    scanningId = lib.id
    defer { scanningId = nil }
    do {
      try await model.scanServerLibrary(libraryId: lib.id)
      scanMessage = "Scan started for \(lib.name)."
    } catch {
      scanMessage = error.localizedDescription
    }
  }
}

struct ServerLibraryDetailView: View {
  @EnvironmentObject private var model: AppModel
  let library: ABSLibrary

  @State private var stats: ABSLibraryStatsResponse?
  @State private var loading = false
  @State private var loadError: String?

  var body: some View {
    ServerAdminScrollScreen {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        if loading && stats == nil {
          ProgressView()
            .tint(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if let loadError, stats == nil {
          Text(loadError)
            .foregroundStyle(AppTheme.textSecondary)
        } else if let stats {
          ServerAdminSection(title: "Overview") {
            statGrid(stats)
          }
        }
      }
    }
    .navigationTitle(library.name)
    .toolbarTitleDisplayMode(.inline)
    .tint(AppTheme.accent)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task {
            do {
              try await model.scanServerLibrary(libraryId: library.id)
              loadError = nil
            } catch {
              loadError = error.localizedDescription
            }
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Scan library")
      }
    }
    .task { await reload() }
    .refreshable { await reload() }
  }

  private func statGrid(_ stats: ABSLibraryStatsResponse) -> some View {
    let items: [(String, String)] = [
      ("Items", "\(stats.totalItems)"),
      ("Authors", "\(stats.totalAuthors)"),
      ("Genres", "\(stats.totalGenres)"),
      ("Duration", formatPlaybackDurationShortHuman(stats.totalDuration)),
      ("Size", ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file)),
      ("Audio tracks", "\(stats.numAudioTrack)"),
    ]
    return LazyVGrid(
      columns: [GridItem(.flexible()), GridItem(.flexible())],
      spacing: 10
    ) {
      ForEach(items, id: \.0) { row in
        VStack(alignment: .leading, spacing: 4) {
          Text(row.0)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
          Text(row.1)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
      }
    }
  }

  private func reload() async {
    loading = true
    defer { loading = false }
    do {
      stats = try await model.fetchServerLibraryStats(libraryId: library.id)
      loadError = nil
    } catch {
      loadError = error.localizedDescription
    }
  }
}

// MARK: - Podcasts (admin)

private struct ServerAdminPodcastRemoveConfirmation: Identifiable {
  let id: String
  let title: String
}

struct ServerAdminPodcastShowsListView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Group {
      if model.podcastShowsLoading, model.podcastShows.isEmpty {
        ProgressView()
          .tint(AppTheme.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.podcastShows.isEmpty {
        ContentUnavailableView(
          "No podcasts",
          systemImage: "mic.fill",
          description: Text("Subscribe to a show or pull to refresh.")
        )
      } else {
        ServerAdminScrollScreen {
          LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
            ForEach(model.podcastShows) { show in
              NavigationLink {
                ServerAdminPodcastShowView(showId: show.id, showTitle: show.displayTitle)
              } label: {
                PodcastShowRowCard(show: show)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .background(AppTheme.background.ignoresSafeArea())
    .navigationTitle("Shows")
    .toolbarTitleDisplayMode(.inline)
    .tint(AppTheme.accent)
    .refreshable { await model.refreshPodcastsTab() }
    .task {
      if model.podcastShows.isEmpty {
        await model.refreshPodcastsTab()
      }
    }
  }
}

private enum ServerAdminPodcastShowTab: String, CaseIterable, Identifiable {
  case feed = "Feed"
  case settings = "Settings"

  var id: String { rawValue }
}

struct ServerAdminPodcastShowView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  let showId: String
  let showTitle: String

  @State private var selectedTab: ServerAdminPodcastShowTab = .feed
  @State private var removeConfirmation: ServerAdminPodcastRemoveConfirmation?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Picker("Section", selection: $selectedTab) {
        ForEach(ServerAdminPodcastShowTab.allCases) { tab in
          Text(tab.rawValue).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.vertical, 12)

      Group {
        switch selectedTab {
        case .feed:
          ServerAdminPodcastRssSection(showId: showId)
        case .settings:
          ServerAdminPodcastSettingsSection(showId: showId, showTitle: showTitle) {
            removeConfirmation = ServerAdminPodcastRemoveConfirmation(id: showId, title: showTitle)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .background(AppTheme.background)
    .navigationTitle(showTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if selectedTab == .feed {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task {
              await model.ensurePodcastRssFeedLoaded(
                forShowId: showId, forceReload: true, applyToTabPreview: false)
            }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(
            !model.isNetworkReachable
              || model.podcastRssFeedLoadInProgressShowIds.contains(showId))
          .accessibilityLabel("Refresh RSS feed")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          removeConfirmation = ServerAdminPodcastRemoveConfirmation(id: showId, title: showTitle)
        } label: {
          Image(systemName: "trash")
            .foregroundStyle(AppTheme.danger)
        }
        .disabled(!model.isNetworkReachable)
        .accessibilityLabel("Remove show from library")
      }
    }
    .alert(
      "Remove show?",
      isPresented: Binding(
        get: { removeConfirmation != nil },
        set: { if !$0 { removeConfirmation = nil } }
      )
    ) {
      Button("Remove from library", role: .destructive) {
        guard let item = removeConfirmation else { return }
        let id = item.id
        removeConfirmation = nil
        Task {
          let ok = await model.removePodcastShowFromLibrary(showLibraryItemId: id)
          if ok { dismiss() }
        }
      }
      Button("Cancel", role: .cancel) {
        removeConfirmation = nil
      }
    } message: {
      if let item = removeConfirmation {
        Text(
          "\"\(item.title)\" will be deleted on the server. Local downloads for this show will be removed."
        )
      }
    }
    .task(id: showId) {
      await model.preloadPodcastShowAdminContext(showId: showId)
    }
    .onChange(of: selectedTab) { _, tab in
      Task {
        switch tab {
        case .feed:
          await model.ensurePodcastRssFeedLoaded(
            forShowId: showId, forceReload: false, applyToTabPreview: false)
        case .settings:
          await model.preparePodcastShowSettingsSheet(showId: showId)
        }
      }
    }
    .onDisappear {
      Task { await model.selectPodcastShowFilter(nil) }
    }
    .tint(AppTheme.accent)
  }
}

private struct ServerAdminPodcastRssSection: View {
  @EnvironmentObject private var model: AppModel
  let showId: String

  var body: some View {
    let loading = model.podcastRssFeedLoadInProgressShowIds.contains(showId)
    let drafts = model.podcastRssFeedCachedDrafts(forShowId: showId)
    let unavailable = model.podcastRssFeedUnavailableMessage(forShowId: showId)

    ScrollView {
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        let libraryOnly = libraryEpisodesNotInFeed(showId: showId, drafts: drafts)

        if let unavailable {
          Text(unavailable)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if loading, drafts.isEmpty, libraryOnly.isEmpty, unavailable == nil {
          ProgressView()
            .controlSize(.large)
            .tint(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else if drafts.isEmpty, libraryOnly.isEmpty, unavailable == nil {
          Text("No episodes found in the feed.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
        } else {
          ForEach(drafts) { draft in
            PodcastRssFeedDraftRow(
              draft: draft,
              podcastLibraryItemId: showId,
              showsDeleteWhenInLibrary: true
            )
          }
          if !libraryOnly.isEmpty {
            Text("In library only")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(AppTheme.textSecondary)
              .padding(.top, 8)
            ForEach(libraryOnly, id: \.progressLookupKey) { episode in
              ServerAdminPodcastLibraryEpisodeRow(showId: showId, episode: episode)
            }
          }
        }
      }
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(
        .bottom, AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset)
    }
    .abstandScrollScreenBackground()
    .refreshable {
      await model.reloadPodcastShowEpisodeListForCurrentShow(showId)
      await model.ensurePodcastRssFeedLoaded(forShowId: showId, forceReload: true)
    }
  }

  private func libraryEpisodesNotInFeed(
    showId: String,
    drafts: [ABSPodcastRssFeedEpisodeDraft]
  ) -> [ABSPodcastEpisodeListItem] {
    model.podcastFeedEpisodes(forShowId: showId).filter { episode in
      !drafts.contains { $0.matchesLibraryEpisode(episode) }
    }
  }
}

private struct ServerAdminPodcastLibraryEpisodeRow: View {
  @EnvironmentObject private var model: AppModel
  let showId: String
  let episode: ABSPodcastEpisodeListItem

  @State private var deleteConfirmation = false

  private var publishedCaption: String {
    guard let ms = episode.publishedAt, ms > 0 else { return "—" }
    let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    return d.formatted(date: .abbreviated, time: .omitted)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(episode.episodeTitle)
          .font(.body.weight(.medium))
          .foregroundStyle(AppTheme.textPrimary)
          .multilineTextAlignment(.leading)
          .lineLimit(3)
        Text(publishedCaption)
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
      }
      Spacer(minLength: 0)
      Button {
        deleteConfirmation = true
      } label: {
        Image(systemName: "trash")
          .font(.title3)
          .foregroundStyle(AppTheme.danger)
      }
      .buttonStyle(.plain)
      .disabled(!model.isNetworkReachable)
      .accessibilityLabel("Delete episode from library")
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppTheme.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.libraryRowCornerRadius, style: .continuous))
    .alert("Delete episode?", isPresented: $deleteConfirmation) {
      Button("Delete", role: .destructive) {
        Task { await model.deletePodcastEpisodeFromLibrary(showLibraryItemId: showId, episode: episode) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("\"\(episode.episodeTitle)\" will be removed from the server library.")
    }
  }
}

private struct ServerAdminPodcastSettingsSection: View {
  @EnvironmentObject private var model: AppModel
  let showId: String
  let showTitle: String
  let onRemove: () -> Void

  var body: some View {
    Form {
      Section("Auto download") {
        PodcastShowAutoDownloadSettingsContent(showId: showId)
      }

      if model.isServerAdmin {
        Section {
          Button {
            Task { await model.checkAndDownloadNewPodcastEpisodes(showId: showId) }
          } label: {
            HStack {
              Text("Check & download new episodes")
              Spacer()
              if model.podcastCheckNewInProgressShowId == showId {
                ProgressView()
                  .controlSize(.small)
                  .tint(AppTheme.accent)
              }
            }
          }
          .disabled(!model.isNetworkReachable || model.podcastCheckNewInProgressShowId == showId)
        }
      }

      Section {
        Button("Unsubscribe", role: .destructive) {
          onRemove()
        }
        .disabled(!model.isNetworkReachable)
      }
    }
    .abstandScrollScreenBackground()
  }
}
