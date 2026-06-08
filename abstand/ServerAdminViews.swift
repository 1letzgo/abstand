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
  @EnvironmentObject private var model: AppModel
  let title: String

  var body: some View {
    Text(title)
      .font(.title3)
      .bold()
      .foregroundStyle(model.appearancePalette.textPrimary)
      .frame(maxWidth: .infinity, alignment: .leading)
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
  @EnvironmentObject private var model: AppModel
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, AppTheme.Layout.settingsCardInsetHPadding)
      .padding(.vertical, AppTheme.Layout.settingsCardInsetVPadding)
      .background(model.appearancePalette.card)
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
      .abstandCardElevation(.standard)
  }
}

/// Einzelne Info-/Nav-Zeile ohne zusätzliche Kartenhöhe (z. B. Account).
private struct ServerAdminCompactCard<Content: View>: View {
  @EnvironmentObject private var model: AppModel
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, AppTheme.Layout.settingsCardInsetHPadding)
      .background(model.appearancePalette.card)
      .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
      .abstandCardElevation(.standard)
  }
}

private extension View {
  /// Interaktive Zeile (Toggle, Picker, Secure Field).
  func settingsCardRowFrame(alignment: Alignment = .leading) -> some View {
    abstandCardListRowFrame(alignment: alignment)
  }

  /// Kompakte Nur-Lese- oder Nav-Zeile.
  func settingsCardCompactRowFrame(alignment: Alignment = .center) -> some View {
    abstandCardListRowFrame(alignment: alignment)
  }
}

private struct ServerAdminNavRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let icon: String
  let title: String
  let subtitle: String?

  var body: some View {
    let _ = themeRevision
    let palette = model.appearancePalette
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.body.weight(.semibold))
        .foregroundStyle(themeAccent)
        .frame(width: 28, alignment: .center)
      VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
        Text(title)
          .font(.body.weight(.medium))
          .foregroundStyle(palette.textPrimary)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
    }
    .settingsCardCompactRowFrame(alignment: .leading)
  }
}

// MARK: - Settings card rows

private struct SettingsCardIcon: View {
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let systemName: String
  var tint: Color?

  var body: some View {
    let _ = themeRevision
    Image(systemName: systemName)
      .font(.body.weight(.semibold))
      .foregroundStyle(tint ?? themeAccent)
      .frame(width: 28, alignment: .center)
  }
}

private struct SettingsCardToggleRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let icon: String
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: icon)
      Toggle(isOn: $isOn) {
        Text(title)
          .font(.body)
          .foregroundStyle(model.appearancePalette.textPrimary)
      }
      .tint(themeAccent)
    }
    .settingsCardRowFrame()
  }
}

private struct SettingsCardAppearanceModeRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  @Binding var selection: AppearanceMode

  var body: some View {
    let _ = themeRevision
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        SettingsCardIcon(systemName: "circle.lefthalf.filled")
        Text("Appearance")
          .font(.body)
          .foregroundStyle(model.appearancePalette.textPrimary)
        Spacer(minLength: 0)
      }
      Picker("Appearance", selection: $selection) {
        ForEach(AppearanceMode.allCases) { mode in
          Text(mode.label).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .tint(themeAccent)
      .id(themeRevision)
    }
    .padding(.vertical, 6)
    .settingsCardRowFrame()
  }
}

private struct SettingsCardColorPickerRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let icon: String
  let title: String

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: icon)
      Text(title)
        .font(.body)
        .foregroundStyle(model.appearancePalette.textPrimary)
      Spacer(minLength: 8)
      // Kein `.id(themeRevision)` — sonst wird der Picker nach jeder Wahl neu
      // aufgebaut und akzeptiert keine weiteren Auswahlen.
      ColorPicker(
        "",
        selection: Binding(
          get: { model.appearanceAccentColor },
          set: { model.setAppearanceAccentColor($0) }
        ),
        supportsOpacity: false
      )
      .labelsHidden()
      .tint(themeAccent)
    }
    .settingsCardRowFrame()
  }
}

private struct SettingsCardPickerRow: View {
  @EnvironmentObject private var model: AppModel
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
      .pickerStyle(.menu)
      .labelsHidden()
      .tint(model.appearanceAccentColor)
    }
    .settingsCardRowFrame()
  }
}

private struct SettingsSkipSecondsPickerRow: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  let backward: Bool
  @Binding var seconds: Int

  private var rowIcon: String {
    backward
      ? PlaybackController.gobackwardSystemImage(seconds: seconds)
      : PlaybackController.goforwardSystemImage(seconds: seconds)
  }

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: rowIcon)
      Text(title)
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
      Spacer(minLength: 8)
      Picker(title, selection: $seconds) {
        ForEach(PlaybackController.skipIntervalOptions, id: \.self) { value in
          Text("\(value) s").tag(value)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .tint(model.appearanceAccentColor)
    }
    .settingsCardRowFrame()
  }
}

/// Kompakte Info-Karte (Titel oben, Wert unten) — wie Streak-Kacheln in Stats.
private struct SettingsMetricCard: View {
  @EnvironmentObject private var model: AppModel
  let icon: String
  var tint: Color?
  let title: String
  let value: String

  private var resolvedTint: Color { tint ?? model.appearanceAccentColor }

  var body: some View {
    let palette = model.appearancePalette
    let textColumn = VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
      Text(value.isEmpty ? "—" : value)
        .font(.headline.weight(.bold))
        .foregroundStyle(palette.textPrimary)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }

    HStack(alignment: .center, spacing: 12) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(resolvedTint)
        .frame(width: 26, alignment: .center)
      textColumn
      Spacer(minLength: 0)
    }
    .abstandCardListRowFrame()
    .padding(.horizontal, AppTheme.Layout.settingsCardInsetHPadding)
    .padding(.vertical, AppTheme.Layout.settingsCardInsetVPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(model.appearancePalette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }
}

/// Passwortzeile wie Picker-Zeilen: Titel links, Eingabe rechts (ohne doppeltes Label/Placeholder).
private struct SettingsCardSecureFieldRow: View {
  let icon: String
  let title: String
  @Binding var text: String
  var placeholder: String = "••••••••"

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: icon)
      Text(title)
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
      Spacer(minLength: 8)
      SecureField(
        "",
        text: $text,
        prompt: Text(placeholder).foregroundStyle(AppTheme.textSecondary.opacity(0.55))
      )
      .font(.body)
      .foregroundStyle(AppTheme.textPrimary)
      .multilineTextAlignment(.trailing)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .frame(maxWidth: 180)
    }
    .settingsCardRowFrame()
  }
}

private struct SettingsCardDivider: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Divider()
      .overlay(model.appearancePalette.textSecondary.opacity(0.25))
      .padding(.vertical, AppTheme.Layout.settingsCardDividerSpacing)
  }
}

private struct SettingsCardStepperRow: View {
  @EnvironmentObject private var model: AppModel
  let icon: String
  let title: String
  let valueLabel: String
  @Binding var value: Int
  let range: ClosedRange<Int>

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: icon)
      Text(title)
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
      Spacer(minLength: 8)
      Text(valueLabel)
        .font(.subheadline)
        .foregroundStyle(AppTheme.textSecondary)
        .monospacedDigit()
        .frame(minWidth: 88, alignment: .trailing)
      Stepper("", value: $value, in: range)
        .labelsHidden()
        .tint(model.appearanceAccentColor)
    }
    .settingsCardRowFrame()
  }
}

private struct SettingsCardAutoDownloadIntervalRow: View {
  @EnvironmentObject private var model: AppModel
  @Binding var selection: PodcastAutoDownloadInterval

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: "clock.arrow.circlepath")
      Text("Interval")
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
      Spacer(minLength: 8)
      Picker("Interval", selection: $selection) {
        ForEach(PodcastAutoDownloadInterval.allCases) { interval in
          Text(interval.label).tag(interval)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .tint(model.appearanceAccentColor)
    }
    .settingsCardRowFrame()
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
  ABSStartShelfLocalization.stripSystemImage(category: category)
}

// MARK: - Settings hub (Tab)

private enum SettingsHubSection: String, CaseIterable, Identifiable, Hashable {
  case appearance = "Appearance"
  case playback = "Playback"
  case downloads = "Downloads"
  case account = "Account"
  case server = "Server"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .appearance: return "paintbrush.fill"
    case .playback: return "play.circle"
    case .downloads: return "arrow.down.circle"
    case .account: return "person.crop.circle"
    case .server: return "server.rack"
    }
  }

  static func stripOrder(isServerRoot: Bool, offlineHome: Bool) -> [SettingsHubSection] {
    var sections: [SettingsHubSection] = [.account, .appearance, .playback]
    if !offlineHome { sections.append(.downloads) }
    if isServerRoot { sections.append(.server) }
    return sections
  }
}

private struct SettingsIconStrip<Section: Identifiable & Hashable>: View {
  @EnvironmentObject private var model: AppModel
  let sections: [Section]
  @Binding var selection: Section
  let icon: (Section) -> String
  let title: (Section) -> String

  var body: some View {
    AbstandBrowseStripIconMenu(
      items: sections.map { section in
        AbstandBrowseStripItem(
          id: String(describing: section.id),
          label: title(section),
          systemImage: icon(section)
        )
      },
      selectionID: String(describing: selection.id),
      onSelect: { id in
        if let match = sections.first(where: { String(describing: $0.id) == id }) {
          selection = match
        }
      }
    )
  }
}

struct SettingsHubRootView: View {
  @EnvironmentObject private var model: AppModel
  @State private var hubSection: SettingsHubSection = .account
  @State private var coverCacheByteCount: Int64 = 0

  private var hubSectionIDs: [SettingsHubSection] {
    SettingsHubSection.stripOrder(
      isServerRoot: model.isServerRoot,
      offlineHome: model.offlineHomeUIActive
    )
  }

  private var scrollBottomInset: CGFloat {
    AppTheme.Layout.scrollBottomInsetBase + model.nowPlayingAccessoryScrollBottomInset
  }

  var body: some View {
    let _ = model.appearanceThemeRevision
    let sections = hubSectionIDs
    AbstandFixedBrowseStripSectionsLayout(
      retainOffscreenSections: false,
      selection: hubSection,
      sectionIDs: sections,
      scrollBottomInset: scrollBottomInset,
      onRefresh: {
        guard hubSection == .account, !model.offlineHomeUIActive else { return }
        await model.reloadSettingsTab(reloadCatalogs: false)
      }
    ) {
      SettingsIconStrip(
        sections: sections,
        selection: $hubSection,
        icon: \.icon,
        title: { $0.rawValue }
      )
    } sectionBody: { section in
      settingsHubSectionBody(section)
    }
    .task {
      guard !model.offlineHomeUIActive else { return }
      await model.reloadSettingsTab(reloadCatalogs: false)
    }
    .onAppear {
      clampHubSectionIfNeeded()
      refreshCoverCacheByteCount()
    }
    .onChange(of: model.isServerRoot) { _, _ in
      clampHubSectionIfNeeded()
    }
    .onChange(of: model.offlineHomeUIActive) { _, offline in
      clampHubSectionIfNeeded()
      if !offline {
        Task { await model.reloadSettingsTab(reloadCatalogs: false) }
      }
    }
    .onChange(of: model.coverImageCacheRevision) { _, _ in
      refreshCoverCacheByteCount()
    }
    .tint(model.appearanceAccentColor)
    .themeAccentFromAppModel(model)
    .abstandThemeRefresh()
  }

  private func clampHubSectionIfNeeded() {
    let visible = hubSectionIDs
    if !visible.contains(hubSection), let first = visible.first {
      hubSection = first
    }
  }

  private func refreshCoverCacheByteCount() {
    coverCacheByteCount = model.coverImageCacheByteCount()
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

  @ViewBuilder
  private func settingsHubSectionBody(_ section: SettingsHubSection) -> some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      switch section {
      case .appearance:
        SettingsAppearanceView()
      case .playback:
        SettingsPlaybackView()
      case .downloads:
        ServerAdminSection(title: "Downloads") {
          LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
            ServerAdminCard {
              SettingsCardToggleRow(
                icon: "arrow.down.circle",
                title: "Auto download on Wi‑Fi",
                isOn: $model.smartDownloadOnWiFi
              )
            }
            ServerAdminCard {
              SettingsCardToggleRow(
                icon: "checkmark.circle",
                title: "Remove download when finished",
                isOn: $model.smartDownloadRemoveWhenFinished
              )
            }
          }
        }
        ServerAdminSection(title: "Cache") {
          ServerAdminCard {
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
      case .account:
        SettingsAccountView()
      case .server:
        serverSettingsMenuSections
      }
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
}

// MARK: - Account

struct SettingsAccountView: View {
  @EnvironmentObject private var model: AppModel

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

  var body: some View {
    ServerAdminSection(title: "Account") {
      LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
          SettingsMetricCard(
            icon: "person.fill",
            title: "Username",
            value: model.sessionUsername
          )
          SettingsMetricCard(
            icon: "person.badge.key.fill",
            title: "Account Type",
            value: model.sessionAccountTypeLabel
          )
        }

        ServerAdminCard {
          if model.sortedBookLibraries.isEmpty {
            Text("No book libraries on this server.")
              .font(.subheadline)
              .foregroundStyle(AppTheme.textSecondary)
              .settingsCardCompactRowFrame(alignment: .leading)
          } else {
            SettingsCardPickerRow(
              icon: "books.vertical.fill",
              title: "Books library",
              selection: booksLibraryPickerSelection,
              options: [(id: AppModel.libraryPickerNoneTag, label: "None")]
                + model.sortedBookLibraries.map { (id: $0.id, label: $0.name) }
            )
          }
        }

        ServerAdminCard {
          if model.sortedPodcastLibraries.isEmpty {
            Text("No podcast libraries on this server.")
              .font(.subheadline)
              .foregroundStyle(AppTheme.textSecondary)
              .settingsCardCompactRowFrame(alignment: .leading)
          } else {
            SettingsCardPickerRow(
              icon: "mic.fill",
              title: "Podcasts library",
              selection: podcastsLibraryPickerSelection,
              options: [(id: AppModel.libraryPickerNoneTag, label: "None")]
                + model.sortedPodcastLibraries.map { (id: $0.id, label: $0.name) }
            )
          }
        }

        if !model.isSessionGuest {
          NavigationLink {
            SettingsChangePasswordView()
          } label: {
            ServerAdminCompactCard {
              ServerAdminNavRow(
                icon: "lock.rotation",
                title: "Change Password",
                subtitle: model.mayUseServerNetwork
                  ? nil
                  : "Requires a server connection"
              )
            }
          }
          .buttonStyle(.plain)
          .disabled(!model.mayUseServerNetwork)
          .opacity(model.mayUseServerNetwork ? 1 : 0.45)
        }

        ServerAdminCompactCard {
          Button {
            model.logout()
          } label: {
            HStack(spacing: 12) {
              SettingsCardIcon(
                systemName: "rectangle.portrait.and.arrow.right", tint: AppTheme.danger)
              Text("Log out")
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.danger)
              Spacer(minLength: 0)
            }
            .settingsCardCompactRowFrame()
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

struct SettingsChangePasswordView: View {
  @EnvironmentObject private var model: AppModel
  @State private var currentPassword = ""
  @State private var newPassword = ""
  @State private var confirmPassword = ""
  @State private var busy = false
  @State private var statusMessage: String?
  @State private var statusIsError = false

  var body: some View {
    ServerAdminScrollScreen {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        ServerAdminCard {
          VStack(alignment: .leading, spacing: 0) {
            SettingsCardSecureFieldRow(
              icon: "lock.fill",
              title: "Current password",
              text: $currentPassword
            )
            SettingsCardDivider()
            SettingsCardSecureFieldRow(
              icon: "lock.open.fill",
              title: "New password",
              text: $newPassword,
              placeholder: model.isServerRoot ? "Optional" : "Required"
            )
            SettingsCardDivider()
            SettingsCardSecureFieldRow(
              icon: "lock.fill",
              title: "Confirm password",
              text: $confirmPassword,
              placeholder: model.isServerRoot ? "Optional" : "Required"
            )
          }
        }

        ServerAdminCard {
          Button {
            Task { await submit() }
          } label: {
            HStack {
              if busy {
                ProgressView()
                  .tint(Color.black.opacity(0.85))
              }
              Text("Save password")
                .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .settingsCardRowFrame(alignment: .center)
            .background(submitEnabled ? model.appearanceAccentColor : AppTheme.textSecondary.opacity(0.35))
            .foregroundStyle(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          .buttonStyle(.plain)
          .disabled(!submitEnabled)
        }

        if let statusMessage {
          Text(statusMessage)
            .font(.footnote)
            .foregroundStyle(statusIsError ? AppTheme.danger : AppTheme.success)
        }
      }
    }
    .navigationTitle("Change Password")
    .navigationBarTitleDisplayMode(.inline)
    .tint(model.appearanceAccentColor)
  }

  private var submitEnabled: Bool {
    !busy && model.mayUseServerNetwork
  }

  private func submit() async {
    statusMessage = nil
    busy = true
    defer { busy = false }
    if let err = await model.changeAccountPassword(
      current: currentPassword,
      new: newPassword,
      confirm: confirmPassword
    ) {
      statusIsError = true
      statusMessage = err
      return
    }
    statusIsError = false
    statusMessage = "Password updated."
    currentPassword = ""
    newPassword = ""
    confirmPassword = ""
  }
}

// MARK: - Playback

struct SettingsPlaybackView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    SettingsPlaybackContent(player: model.player)
      .environmentObject(model)
      .tint(model.appearanceAccentColor)
  }
}

private struct SettingsPlaybackContent: View {
  @ObservedObject var player: PlaybackController
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ServerAdminSection(title: "Playback") {
      LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        ServerAdminCard {
          SettingsSkipSecondsPickerRow(
            title: "Skip back",
            backward: true,
            seconds: $player.skipBackwardSeconds
          )
        }
        ServerAdminCard {
          SettingsSkipSecondsPickerRow(
            title: "Skip forward",
            backward: false,
            seconds: $player.skipForwardSeconds
          )
        }
        ServerAdminCard {
          SettingsCardToggleRow(
            icon: "play.circle",
            title: "Open player when start playing",
            isOn: $model.openPlayerWhenStartPlaying
          )
        }
      }
    }
  }
}

// MARK: - Appearance

struct SettingsAppearanceView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    let _ = model.appearanceThemeRevision
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      ServerAdminSection(title: "Theme") {
        LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
          ServerAdminCard {
            SettingsCardAppearanceModeRow(selection: $model.appearanceMode)
          }
          ServerAdminCard {
            SettingsCardColorPickerRow(
              icon: "paintpalette.fill",
              title: "Accent color"
            )
          }
          ServerAdminCard {
            Button {
              model.resetAppearanceAccentToDefault()
            } label: {
              HStack(spacing: 12) {
                SettingsCardIcon(systemName: "arrow.counterclockwise")
                Text("Reset to default")
                  .font(.body.weight(.medium))
                  .foregroundStyle(model.appearancePalette.textPrimary)
                Spacer(minLength: 0)
              }
              .settingsCardRowFrame()
            }
            .buttonStyle(.plain)
            .disabled(model.appearanceAccentMatchesDefault)
            .opacity(model.appearanceAccentMatchesDefault ? 0.45 : 1)
          }
        }
      }
      ServerAdminSection(title: "Views") {
        NavigationLink {
          SettingsAppearanceHomeView()
        } label: {
          ServerAdminCard {
            ServerAdminNavRow(
              icon: "house.fill",
              title: "Home",
              subtitle: "Shelf layout & sections"
            )
          }
        }
        .buttonStyle(.plain)
      }
    }
    .tint(model.appearanceAccentColor)
    .themeAccentFromAppModel(model)
    .abstandThemeRefresh()
  }
}

struct SettingsAppearanceHomeView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ServerAdminScrollScreen {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        ServerAdminSection(title: "Home") {
          ServerAdminCard {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(Array(model.startSettingsCategoryList.enumerated()), id: \.element.category) {
                index, row in
                if index > 0 {
                  Divider().overlay(model.appearancePalette.textSecondary.opacity(0.25))
                }
                SettingsCardToggleRow(
                  icon: startShelfSettingsIcon(category: row.category),
                  title: row.label,
                  isOn: Binding(
                    get: { model.isStartCategoryEnabled(row.category) },
                    set: { model.setStartCategoryEnabled(row.category, enabled: $0) }
                  )
                )
              }
            }
          }
        }
      }
    }
    .navigationTitle("Home")
    .themeAccentFromAppModel(model)
    .abstandThemeRefresh()
    .toolbarTitleDisplayMode(.inlineLarge)
    .tint(model.appearanceAccentColor)
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
          .tint(model.appearanceAccentColor)
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
    .tint(model.appearanceAccentColor)
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
  @EnvironmentObject private var model: AppModel
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
          .background(model.appearanceAccentColor.opacity(0.2))
          .foregroundStyle(model.appearanceAccentColor)
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
            .tint(model.appearanceAccentColor)
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
    .tint(model.appearanceAccentColor)
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
      summaryCard(value: "\(inProgressCount)", label: "In Progress", color: model.appearanceAccentColor)
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
    .abstandCardElevation(.standard)
  }

  private var recentSessionsButton: some View {
    Button {
      showSessions = true
    } label: {
      ServerAdminCard {
        HStack {
          Image(systemName: "clock.arrow.circlepath")
            .foregroundStyle(model.appearanceAccentColor)
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
          .tint(model.appearanceAccentColor)
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
    .tint(model.appearanceAccentColor)
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
                    .foregroundStyle(model.appearanceAccentColor)
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
            .tint(model.appearanceAccentColor)
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
    .tint(model.appearanceAccentColor)
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
        .abstandCardElevation(.standard)
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
          .tint(model.appearanceAccentColor)
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
    .tint(model.appearanceAccentColor)
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
    .tint(model.appearanceAccentColor)
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
            .tint(model.appearanceAccentColor)
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

struct PodcastShowAutoDownloadSettingsContent: View {
  @EnvironmentObject private var model: AppModel
  let showId: String

  private var controlsDisabled: Bool {
    !model.isNetworkReachable || model.podcastAutoDownloadSettingsSaving
  }

  private var intervalBinding: Binding<PodcastAutoDownloadInterval> {
    Binding(
      get: { model.podcastAutoDownloadInterval },
      set: { interval in
        model.podcastAutoDownloadInterval = interval
        Task { await model.savePodcastAutoDownloadSettings(showId: showId) }
      }
    )
  }

  private var autoDownloadBinding: Binding<Bool> {
    Binding(
      get: { model.podcastAutoDownloadEnabled },
      set: { enabled in
        model.podcastAutoDownloadEnabled = enabled
        Task { await model.savePodcastAutoDownloadSettings(showId: showId) }
      }
    )
  }

  private var episodesToKeepBinding: Binding<Int> {
    Binding(
      get: { model.podcastMaxEpisodesToKeep },
      set: { value in
        model.podcastMaxEpisodesToKeep = value
        Task { await model.savePodcastAutoDownloadSettings(showId: showId) }
      }
    )
  }

  private var newEpisodesPerCheckBinding: Binding<Int> {
    Binding(
      get: { model.podcastMaxNewEpisodesToDownload },
      set: { value in
        model.podcastMaxNewEpisodesToDownload = value
        Task { await model.savePodcastAutoDownloadSettings(showId: showId) }
      }
    )
  }

  var body: some View {
    ServerAdminCard {
      Group {
        if model.podcastAutoDownloadSettingsShowId != showId {
          ProgressView()
            .controlSize(.small)
            .tint(model.appearanceAccentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
          VStack(alignment: .leading, spacing: 0) {
            SettingsCardToggleRow(
              icon: "arrow.down.circle",
              title: "Download new episodes automatically",
              isOn: autoDownloadBinding
            )
            .disabled(controlsDisabled)

            if model.podcastAutoDownloadEnabled {
              SettingsCardDivider()
              SettingsCardAutoDownloadIntervalRow(selection: intervalBinding)
                .disabled(controlsDisabled)
            }

            SettingsCardDivider()
            SettingsCardStepperRow(
              icon: "tray.full",
              title: "Max. episodes to keep",
              valueLabel: PodcastAutoDownloadLimitInfo.episodesToKeepLabel(
                model.podcastMaxEpisodesToKeep),
              value: episodesToKeepBinding,
              range: 0 ... 500
            )
            .disabled(controlsDisabled)

            SettingsCardDivider()
            SettingsCardStepperRow(
              icon: "plus.rectangle.on.rectangle",
              title: "Max. new episodes per check",
              valueLabel: PodcastAutoDownloadLimitInfo.newEpisodesPerCheckLabel(
                model.podcastMaxNewEpisodesToDownload),
              value: newEpisodesPerCheckBinding,
              range: 0 ... 100
            )
            .disabled(controlsDisabled)
          }
          .animation(.none, value: model.podcastAutoDownloadSettingsSaving)
        }
      }
    }
    .task(id: showId) {
      if model.podcastAutoDownloadSettingsShowId != showId {
        await model.loadPodcastAutoDownloadSettings(showId: showId)
      }
    }
  }
}

private enum PodcastAutoDownloadLimitInfo {
  static func episodesToKeepLabel(_ value: Int) -> String {
    value == 0 ? "All episodes" : "\(value)"
  }

  static func newEpisodesPerCheckLabel(_ value: Int) -> String {
    value == 0 ? "No limit" : "\(value)"
  }
}

private struct ServerAdminPodcastSettingsSection: View {
  @EnvironmentObject private var model: AppModel
  let showId: String
  let showTitle: String
  let onRemove: () -> Void

  var body: some View {
    ServerAdminScrollScreen {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        ServerAdminSection(title: "Auto download") {
          PodcastShowAutoDownloadSettingsContent(showId: showId)
        }

        if model.isServerAdmin {
          ServerAdminCard {
            Button {
              Task { await model.checkAndDownloadNewPodcastEpisodes(showId: showId) }
            } label: {
              HStack(spacing: 12) {
                SettingsCardIcon(systemName: "arrow.clockwise.circle")
                Text("Check & download new episodes")
                  .font(.body.weight(.medium))
                  .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 0)
                if model.podcastCheckNewInProgressShowId == showId {
                  ProgressView()
                    .controlSize(.small)
                    .tint(model.appearanceAccentColor)
                }
              }
              .settingsCardRowFrame()
              .opacity(
                model.isNetworkReachable && model.podcastCheckNewInProgressShowId != showId ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!model.isNetworkReachable || model.podcastCheckNewInProgressShowId == showId)
          }
        }

        ServerAdminCompactCard {
          Button {
            onRemove()
          } label: {
            HStack(spacing: 12) {
              SettingsCardIcon(systemName: "minus.circle", tint: AppTheme.danger)
              Text("Unsubscribe")
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.danger)
              Spacer(minLength: 0)
            }
            .settingsCardCompactRowFrame()
          }
          .buttonStyle(.plain)
          .disabled(!model.isNetworkReachable)
          .opacity(model.isNetworkReachable ? 1 : 0.45)
        }
      }
    }
  }
}
