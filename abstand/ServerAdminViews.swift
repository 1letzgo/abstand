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
  var subtitle: String? = nil

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: icon)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
          .foregroundStyle(model.appearancePalette.textPrimary)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(model.appearancePalette.textSecondary)
        }
      }
      Spacer(minLength: 8)
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .tint(themeAccent)
    }
    .settingsCardRowFrame()
  }
}

/// Settings: alle Server-Libraries aktivieren/deaktivieren und per Drag sortieren.
private struct SettingsLibrariesActivationList: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    List {
      ForEach(model.librariesInActivationOrder) { lib in
        SettingsCardToggleRow(
          icon: lib.isPodcastLibrary ? "mic.fill" : "books.vertical.fill",
          title: lib.name,
          isOn: Binding(
            get: { model.isLibraryActivationEnabled(lib.id) },
            set: { model.setLibraryActivationEnabled(lib.id, enabled: $0) }
          ),
          subtitle: lib.isPodcastLibrary ? "Podcasts" : "Books"
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }
      .onMove { source, destination in
        model.moveLibraryActivation(fromOffsets: source, toOffset: destination)
      }
    }
    .listStyle(.plain)
    .scrollDisabled(true)
    .frame(minHeight: CGFloat(max(model.librariesInActivationOrder.count, 1)) * 56)
    .environment(\.editMode, .constant(.active))
    .padding(.vertical, 4)
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
        .foregroundStyle(model.appearancePalette.textPrimary)
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
        .foregroundStyle(model.appearancePalette.textPrimary)
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
  @EnvironmentObject private var model: AppModel
  let icon: String
  let title: String
  @Binding var text: String
  var placeholder: String = "••••••••"

  var body: some View {
    HStack(spacing: 12) {
      SettingsCardIcon(systemName: icon)
      Text(title)
        .font(.body)
        .foregroundStyle(model.appearancePalette.textPrimary)
      Spacer(minLength: 8)
      SecureField(
        "",
        text: $text,
        prompt: Text(placeholder).foregroundStyle(model.appearancePalette.textSecondary.opacity(0.55))
      )
      .font(.body)
      .foregroundStyle(model.appearancePalette.textPrimary)
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
        .foregroundStyle(model.appearancePalette.textPrimary)
      Spacer(minLength: 8)
      Text(valueLabel)
        .font(.subheadline)
        .foregroundStyle(model.appearancePalette.textSecondary)
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
        .foregroundStyle(model.appearancePalette.textPrimary)
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
  @EnvironmentObject private var model: AppModel
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
          .foregroundStyle(model.appearancePalette.textPrimary)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(model.appearancePalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: trailingIcon)
        .foregroundStyle(model.appearancePalette.textSecondary)
    }
    .settingsCardCompactRowFrame(alignment: .leading)
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
  case debug = "Debug"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .appearance: return "paintbrush.fill"
    case .playback: return "play.circle"
    case .downloads: return "arrow.down.circle"
    case .account: return "person.crop.circle"
    case .server: return "server.rack"
    case .debug: return "ladybug"
    }
  }

  static func stripOrder(isServerRoot: Bool, offlineHome: Bool) -> [SettingsHubSection] {
    var sections: [SettingsHubSection] = [.account, .appearance, .playback]
    if !offlineHome { sections.append(.downloads) }
    if isServerRoot { sections.append(.server) }
    sections.append(.debug)
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
        guard !model.offlineHomeUIActive else { return }
        switch hubSection {
        case .account:
          await model.reloadSettingsTab(reloadCatalogs: false)
        default:
          break
        }
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
    .task(id: hubSection) {
      guard !model.offlineHomeUIActive else { return }
      switch hubSection {
      case .account, .downloads:
        await model.reloadSettingsTab(reloadCatalogs: false)
      default:
        break
      }
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

  /// Untertitel für „Manage downloads": Anzahl fertiger Downloads + ggf. aktive/wartende.
  private var manageDownloadsSubtitle: String? {
    let total = model.downloadedItemIds.count
    let active = model.downloads.activeItemId != nil ? 1 : 0
    let queued = model.downloads.queuedItemIds.count
    if total == 0, active == 0, queued == 0 { return nil }
    var parts: [String] = []
    if total > 0 { parts.append("\(total) saved") }
    let inFlight = active + queued
    if inFlight > 0 { parts.append("\(inFlight) pending") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
            AbstandGroupedCard {
              SettingsCardToggleRow(
                icon: "arrow.down.circle",
                title: "Auto download on Wi‑Fi",
                isOn: $model.smartDownloadOnWiFi
              )
            }
            AbstandGroupedCard {
              SettingsCardToggleRow(
                icon: "checkmark.circle",
                title: "Remove download when finished",
                isOn: $model.smartDownloadRemoveWhenFinished
              )
            }
            NavigationLink {
              SettingsDownloadsManageView()
                .navigationTitle("Downloads")
                .toolbarTitleDisplayMode(.inline)
            } label: {
              AbstandGroupedCard {
                ServerAdminNavRow(
                  icon: "list.bullet.below.rectangle",
                  title: "Manage downloads",
                  subtitle: manageDownloadsSubtitle
                )
              }
            }
            .buttonStyle(.plain)
          }
        }
        ServerAdminSection(title: "Cache") {
          AbstandGroupedCard {
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
      case .debug:
        DebugLogExportView()
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
          AbstandGroupedCard {
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
          AbstandGroupedCard {
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
        AbstandGroupedCard {
          ServerAdminNavRow(icon: "person.2.fill", title: "Users", subtitle: nil)
        }
      }
      .buttonStyle(.plain)
    }

    ServerAdminLibrariesSection()
  }
}

// MARK: - Home stats

struct HomeListeningStatsSectionView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private var isRegularWidth: Bool { horizontalSizeClass == .regular }

  private var categoryColumns: [GridItem] {
    let spacing = AppTheme.Layout.withinSectionSpacing
    if isRegularWidth {
      return [
        GridItem(.flexible(), spacing: spacing),
        GridItem(.flexible(), spacing: spacing),
      ]
    }
    return [GridItem(.flexible(), spacing: spacing)]
  }

  var body: some View {
    LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
      StatsLevelSectionView()
      StatsTimelineHubSectionView()

      if isRegularWidth {
        LazyVGrid(columns: categoryColumns, spacing: AppTheme.Layout.withinSectionSpacing) {
          ForEach(SettingsStatsCategory.allCases) { category in
            statsCategoryLink(category)
          }
        }
      } else {
        ForEach(SettingsStatsCategory.allCases) { category in
          ServerAdminSection(title: category.rawValue) {
            statsCategoryLink(category)
          }
        }
      }
    }
  }

  private func statsCategoryLink(_ category: SettingsStatsCategory) -> some View {
    NavigationLink {
      category.detailView
        .navigationTitle(category.rawValue)
        .toolbarTitleDisplayMode(.inline)
    } label: {
      AbstandGroupedCard {
        ServerAdminNavRow(
          icon: category.icon,
          title: category.rawValue,
          subtitle: category.subtitle
        )
      }
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Account

struct SettingsAccountView: View {
  @EnvironmentObject private var model: AppModel
  @State private var showAddAccount = false
  @State private var accountPendingLogout: ABSStoredAccount?

  var body: some View {
    ServerAdminSection(title: "Accounts") {
      LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        AbstandGroupedCard {
          VStack(spacing: 0) {
            ForEach(Array(model.storedAccounts.enumerated()), id: \.element.id) { index, account in
              if index > 0 { SettingsCardDivider() }
              Button {
                guard !model.isActiveStoredAccount(account) else { return }
                Task { await model.switchToAccount(account.accountKey) }
              } label: {
                HStack(spacing: 12) {
                  SettingsCardIcon(
                    systemName: model.isActiveStoredAccount(account) ? "person.crop.circle.fill" : "person.crop.circle"
                  )
                  VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayUsername)
                      .font(.body.weight(.medium))
                      .foregroundStyle(model.appearancePalette.textPrimary)
                    Text(account.displayServerHost)
                      .font(.caption)
                      .foregroundStyle(model.appearancePalette.textPrimary)
                      .lineLimit(1)
                  }
                  Spacer(minLength: 0)
                  if model.isActiveStoredAccount(account) {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(model.appearanceAccentColor)
                  }
                }
                .settingsCardCompactRowFrame(alignment: .leading)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .disabled(model.isSwitchingAccount)
              .contextMenu {
                Button("Log out", role: .destructive) {
                  accountPendingLogout = account
                }
              }
            }
            if !model.storedAccounts.isEmpty { SettingsCardDivider() }
            Button {
              showAddAccount = true
            } label: {
              HStack(spacing: 12) {
                SettingsCardIcon(systemName: "plus.circle.fill")
                Text("Add account")
                  .font(.body.weight(.medium))
                  .foregroundStyle(model.appearancePalette.textPrimary)
                Spacer(minLength: 0)
              }
              .settingsCardCompactRowFrame()
            }
            .buttonStyle(.plain)
            .disabled(model.isSwitchingAccount)
          }
        }
      }
    }
    .sheet(isPresented: $showAddAccount) {
      NavigationStack {
        LoginView(addAccountMode: true)
          .environmentObject(model)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel") { showAddAccount = false }
            }
          }
      }
      .presentationDetents([.large])
    }

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

        if !model.isSessionGuest {
          NavigationLink {
            SettingsChangePasswordView()
          } label: {
            AbstandGroupedCard {
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

        AbstandGroupedCard {
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

    ServerAdminSection(title: "Libraries") {
      LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
        AbstandGroupedCard {
          if model.libraries.isEmpty {
            Text("No libraries on this server.")
              .font(.subheadline)
              .foregroundStyle(model.appearancePalette.textSecondary)
              .settingsCardCompactRowFrame(alignment: .leading)
          } else {
            SettingsLibrariesActivationList()
          }
        }
      }
    }
    .alert("Log out?", isPresented: Binding(
      get: { accountPendingLogout != nil },
      set: { if !$0 { accountPendingLogout = nil } }
    )) {
      Button("Log out", role: .destructive) {
        if let account = accountPendingLogout {
          model.removeStoredAccount(accountKey: account.accountKey)
        }
        accountPendingLogout = nil
      }
      Button("Cancel", role: .cancel) {
        accountPendingLogout = nil
      }
    } message: {
      if let account = accountPendingLogout {
        Text("Remove \(account.displayUsername) from @\(account.displayServerHost)?")
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
        AbstandGroupedCard {
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

        Button {
          Task { await submit() }
        } label: {
          HStack(spacing: 8) {
            if busy {
              ProgressView()
                .tint(model.appearancePalette.foregroundOnAccent(model.appearanceAccentColor))
            }
            Text("Save password")
          }
        }
        .buttonStyle(AbstandPrimaryButtonStyle())
        .disabled(!submitEnabled)

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
        AbstandGroupedCard {
          SettingsSkipSecondsPickerRow(
            title: "Skip back",
            backward: true,
            seconds: $player.skipBackwardSeconds
          )
        }
        AbstandGroupedCard {
          SettingsSkipSecondsPickerRow(
            title: "Skip forward",
            backward: false,
            seconds: $player.skipForwardSeconds
          )
        }
        AbstandGroupedCard {
          SettingsCardToggleRow(
            icon: "play.circle",
            title: "Open player when start playing",
            isOn: $model.openPlayerWhenStartPlaying
          )
        }
      }
    }
    ServerAdminSection(title: "Teleprompter") {
      AbstandGroupedCard {
        SettingsCardPickerRow(
          icon: "translate",
          title: "Translation language",
          selection: $model.translationTargetLanguageCode,
          options: TranslationTargetLanguage.pickerOptions()
        )
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
          AbstandGroupedCard {
            SettingsCardAppearanceModeRow(selection: $model.appearanceMode)
          }
          AbstandGroupedCard {
            SettingsCardColorPickerRow(
              icon: "paintpalette.fill",
              title: "Accent color"
            )
          }
          AbstandGroupedCard {
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
        LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
          AbstandGroupedCard {
            SettingsCardPickerRow(
              icon: "books.vertical.fill",
              title: "Book",
              selection: Binding(
                get: { model.libraryBookCardStyle.rawValue },
                set: { raw in
                  if let style = LibraryBookCardStyle(rawValue: raw) {
                    model.libraryBookCardStyle = style
                  }
                }
              ),
              options: LibraryBookCardStyle.allCases.map { (id: $0.rawValue, label: $0.label) }
            )
          }
          AbstandGroupedCard {
            SettingsCardPickerRow(
              icon: "mic.fill",
              title: "Podcast episode cards",
              selection: Binding(
                get: { model.libraryPodcastCardStyle.rawValue },
                set: { raw in
                  if let style = LibraryPodcastCardStyle(rawValue: raw) {
                    model.libraryPodcastCardStyle = style
                  }
                }
              ),
              options: LibraryPodcastCardStyle.allCases.map { (id: $0.rawValue, label: $0.label) }
            )
          }
          NavigationLink {
            SettingsAppearanceHomeView()
          } label: {
            AbstandGroupedCard {
              ServerAdminNavRow(
                icon: "house.fill",
                title: "Home",
                subtitle: "Show or hide shelves under Dashboard"
              )
            }
          }
          .buttonStyle(.plain)
        }
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
          AbstandGroupedCard {
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
                    AbstandGroupedCard {
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
    .background(model.appearancePalette.background.ignoresSafeArea())
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
        .fill(isOnline ? AppTheme.success : model.appearancePalette.textSecondary.opacity(0.35))
        .frame(width: 8, height: 8)
      Text(user.username)
        .font(.body.weight(.medium))
        .foregroundStyle(model.appearancePalette.textPrimary)
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
          .foregroundStyle(model.appearancePalette.textSecondary)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(model.appearancePalette.textSecondary)
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
            .foregroundStyle(model.appearancePalette.textSecondary)
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
        .foregroundStyle(model.appearancePalette.textSecondary)
      if let type = detail.typeLabel {
        Text(type)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(model.appearancePalette.card)
          .foregroundStyle(model.appearancePalette.textSecondary)
          .clipShape(Capsule())
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var summaryStrip: some View {
    HStack(spacing: 10) {
      summaryCard(value: "\(inProgressCount)", label: "In Progress", color: model.appearanceAccentColor)
      summaryCard(value: "\(finishedCount)", label: "Finished", color: AppTheme.success)
      summaryCard(value: "\(progressRows.count)", label: "Total", color: model.appearancePalette.textPrimary)
    }
  }

  private func summaryCard(value: String, label: String, color: Color) -> some View {
    VStack(spacing: 6) {
      Text(value)
        .font(.title2.weight(.bold))
        .foregroundStyle(color)
      Text(label)
        .font(.caption)
        .foregroundStyle(model.appearancePalette.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(model.appearancePalette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }

  private var recentSessionsButton: some View {
    Button {
      showSessions = true
    } label: {
      AbstandGroupedCard {
        HStack {
          Image(systemName: "clock.arrow.circlepath")
            .foregroundStyle(model.appearanceAccentColor)
          Text("Recent Sessions")
            .fontWeight(.medium)
            .foregroundStyle(model.appearancePalette.textPrimary)
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(model.appearancePalette.textSecondary)
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
              AbstandGroupedCard {
                VStack(alignment: .leading, spacing: 4) {
                  Text(session.libraryItemId.isEmpty ? session.id : session.libraryItemId)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(model.appearancePalette.textPrimary)
                  Text(
                    "\(formatPlaybackTime(session.startTime)) → \(formatPlaybackTime(session.currentTime))"
                  )
                  .font(.caption)
                  .foregroundStyle(model.appearancePalette.textSecondary)
                }
              }
            }
          }
        }
      }
    }
    .background(model.appearancePalette.background.ignoresSafeArea())
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
            .foregroundStyle(model.appearancePalette.textSecondary)
        }
        if sortedLibraries.isEmpty {
          Text("No libraries on this server.")
            .font(.subheadline)
            .foregroundStyle(model.appearancePalette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
          ForEach(sortedLibraries) { lib in
            NavigationLink {
              ServerLibraryDetailView(library: lib)
            } label: {
              AbstandGroupedCard {
                HStack(spacing: 12) {
                  Image(systemName: "books.vertical.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(model.appearanceAccentColor)
                    .frame(width: 28, alignment: .center)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(lib.name)
                      .font(.body.weight(.medium))
                      .foregroundStyle(model.appearancePalette.textPrimary)
                    Text(lib.mediaType?.capitalized ?? "Library")
                      .font(.caption)
                      .foregroundStyle(model.appearancePalette.textSecondary)
                  }
                  Spacer(minLength: 0)
                  if scanningId == lib.id {
                    ProgressView()
                      .controlSize(.small)
                  } else {
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(model.appearancePalette.textSecondary)
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
            .foregroundStyle(model.appearancePalette.textSecondary)
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
            .foregroundStyle(model.appearancePalette.textSecondary)
          Text(row.1)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(model.appearancePalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(model.appearancePalette.card)
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
    .background(model.appearancePalette.background.ignoresSafeArea())
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
    .background(model.appearancePalette.background)
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
            .foregroundStyle(model.appearancePalette.textSecondary)
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
            .foregroundStyle(model.appearancePalette.textSecondary)
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
              .foregroundStyle(model.appearancePalette.textSecondary)
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
          .foregroundStyle(model.appearancePalette.textPrimary)
          .multilineTextAlignment(.leading)
          .lineLimit(3)
        Text(publishedCaption)
          .font(.caption)
          .foregroundStyle(model.appearancePalette.textSecondary)
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
    .background(model.appearancePalette.card)
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
    AbstandGroupedCard {
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

private enum PodcastShowTranscriptionLanguage: String, CaseIterable, Identifiable {
  case automatic = ""
  case german = "German"
  case english = "English"
  case french = "French"
  case spanish = "Spanish"
  case italian = "Italian"
  case dutch = "Dutch"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic: return "Automatic"
    case .german: return "German"
    case .english: return "English"
    case .french: return "French"
    case .spanish: return "Spanish"
    case .italian: return "Italian"
    case .dutch: return "Dutch"
    }
  }
}

private struct PodcastShowTranscriptionLanguageSettingsContent: View {
  @EnvironmentObject private var model: AppModel
  let showId: String

  private var selection: Binding<String> {
    Binding(
      get: { model.podcastShowTranscriptionLanguage },
      set: { language in
        model.podcastShowTranscriptionLanguage = language
        Task { await model.savePodcastShowTranscriptionLanguage(showId: showId) }
      }
    )
  }

  var body: some View {
    AbstandGroupedCard {
      Group {
        if model.podcastShowTranscriptionLanguageShowId != showId {
          ProgressView()
            .controlSize(.small)
            .tint(model.appearanceAccentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
          VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
              SettingsCardIcon(systemName: "captions.bubble")
              Text("Language")
                .font(.body.weight(.medium))
                .foregroundStyle(model.appearancePalette.textPrimary)
              Spacer(minLength: 0)
              Picker("Language", selection: selection) {
                ForEach(PodcastShowTranscriptionLanguage.allCases) { language in
                  Text(language.title).tag(language.rawValue)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
              .disabled(!model.isNetworkReachable || model.podcastShowTranscriptionLanguageSaving)
            }
          }
          .settingsCardRowFrame()
        }
      }
    }
    .task(id: showId) {
      if model.podcastShowTranscriptionLanguageShowId != showId {
        await model.preparePodcastShowSettingsSheet(showId: showId)
      }
    }
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
        ServerAdminSection(title: "Language") {
          PodcastShowTranscriptionLanguageSettingsContent(showId: showId)
        }

        ServerAdminSection(title: "Auto download") {
          PodcastShowAutoDownloadSettingsContent(showId: showId)
        }

        if model.isServerAdmin {
          AbstandGroupedCard {
            Button {
              Task { await model.checkAndDownloadNewPodcastEpisodes(showId: showId) }
            } label: {
              HStack(spacing: 12) {
                SettingsCardIcon(systemName: "arrow.clockwise.circle")
                Text("Check & download new episodes")
                  .font(.body.weight(.medium))
                  .foregroundStyle(model.appearancePalette.textPrimary)
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

        AbstandGroupedCard {
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

// MARK: - Manage downloads (aktive + gespeicherte Downloads verwalten)

/// Zeigt laufende/wartende Downloads sowie alle gespeicherten Offline-Dateien mit Löschfunktion.
private struct SettingsDownloadsManageView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent

  /// Geladene Manifeste + Ordnergrößen; einmal beim Erscheinen und nach Löschungen neu aufgebaut.
  @State private var rows: [DownloadManageRow] = []
  @State private var totalBytes: Int64 = 0
  /// Live-Fortschritt des aktiven Downloads — direkt (ohne AppModel-Throttling) beobachtet,
  /// damit die ProgressView auch bei schnellen Podcast-Episoden (oft nur ein Track) sichtbar läuft.
  @State private var activeDownloadProgress: Double = 0

  var body: some View {
    ServerAdminScrollScreen {
      LazyVStack(alignment: .leading, spacing: AppTheme.Layout.sectionSpacing) {
        activeSection
        savedSection
      }
    }
    .themeAccentFromAppModel(model)
    .abstandThemeRefresh()
    .toolbarTitleDisplayMode(.inlineLarge)
    .tint(model.appearanceAccentColor)
    .task { await reload() }
    .onReceive(model.$downloadedItemIds) { _ in
      Task { await reload() }
    }
    .onReceive(model.downloads.$activeItemId) { _ in
      activeDownloadProgress = model.downloads.progress
      Task { await reload() }
    }
    .onReceive(model.downloads.$progress) { p in
      // Nur während ein Download aktiv ist — sonst bleibt die Anzeige auf dem letzten Stand.
      guard model.downloads.activeItemId != nil else { return }
      activeDownloadProgress = p
    }
    .onReceive(model.downloads.$queuedItemIds) { _ in
      Task { await reload() }
    }
  }

  // MARK: Active / queued

  @ViewBuilder
  private var activeSection: some View {
    let activeId = model.downloads.activeItemId
    let queued = model.downloads.queuedItemIds
    if activeId != nil || !queued.isEmpty {
      ServerAdminSection(title: "In progress") {
        LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
          if let activeId {
            let entry = model.downloadCatalogEntry(forStorageId: activeId)
            AbstandGroupedCard {
              DownloadManageActiveRow(
                storageId: activeId,
                entry: entry,
                progress: activeDownloadProgress,
                isQueued: false,
                token: model.token,
                coverURL: entry.flatMap { model.coverURL(for: $0.libraryItemId) },
                cacheAccount: model.coverImageCacheAccountDirectory(),
                cacheRevision: entry.map { model.coverImageCacheRevision(forBookId: $0.libraryItemId) }
                  ?? model.coverImageCacheRevision,
                onCancel: { model.removeLocalDownload(bookId: activeId) }
              )
            }
          }
          ForEach(Array(queued.enumerated()), id: \.element) { _, qid in
            let entry = model.downloadCatalogEntry(forStorageId: qid)
            AbstandGroupedCard {
              DownloadManageActiveRow(
                storageId: qid,
                entry: entry,
                progress: 0,
                isQueued: true,
                token: model.token,
                coverURL: entry.flatMap { model.coverURL(for: $0.libraryItemId) },
                cacheAccount: model.coverImageCacheAccountDirectory(),
                cacheRevision: entry.map { model.coverImageCacheRevision(forBookId: $0.libraryItemId) }
                  ?? model.coverImageCacheRevision,
                onCancel: { model.removeLocalDownload(bookId: qid) }
              )
            }
          }
        }
      }
    }
  }

  // MARK: Saved downloads

  @ViewBuilder
  private var savedSection: some View {
    ServerAdminSection(title: "Saved offline") {
      if rows.isEmpty {
        AbstandGroupedCard {
          VStack(alignment: .leading, spacing: 4) {
            Text("No downloads yet.")
              .font(.body)
              .foregroundStyle(model.appearancePalette.textPrimary)
            Text("Downloads appear here once you save an audiobook or episode offline.")
              .font(.caption)
              .foregroundStyle(model.appearancePalette.textSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
        }
      } else {
        LazyVStack(spacing: AppTheme.Layout.withinSectionSpacing) {
          if totalBytes > 0 {
            AbstandGroupedCard {
              HStack(spacing: 12) {
                SettingsCardIcon(systemName: "internaldrive")
                VStack(alignment: .leading, spacing: 2) {
                  Text("Total storage")
                    .font(.body.weight(.medium))
                    .foregroundStyle(model.appearancePalette.textPrimary)
                  Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(model.appearancePalette.textSecondary)
                }
                Spacer(minLength: 0)
              }
            }
          }
          ForEach(rows) { row in
            AbstandGroupedCard {
              DownloadManageSavedRow(
                row: row,
                token: model.token,
                coverURL: model.coverURL(for: row.libraryItemId),
                cacheAccount: model.coverImageCacheAccountDirectory(),
                cacheRevision: model.coverImageCacheRevision(forBookId: row.libraryItemId),
                onDelete: { delete(row) }
              )
            }
          }
        }
      }
    }
  }

  // MARK: Helpers

  /// Lädt alle Manifeste + Ordnergrößen; sortiert nach Speicherdatum (neu zuerst).
  private func reload() async {
    var collected: [DownloadManageRow] = []
    var sum: Int64 = 0
    for id in model.downloadedItemIds.sorted() {
      guard let root = try? model.downloads.downloadFolder(for: id),
        let manifest = ABSDownloadManifest.load(from: root),
        model.downloadManifestBelongsToActiveAccount(manifest)
      else { continue }
      let bytes = folderSize(at: root)
      sum += bytes
      collected.append(
        DownloadManageRow(
          storageId: id,
          libraryItemId: manifest.libraryItemId,
          episodeId: manifest.episodeId,
          title: manifest.displayTitle ?? "Unknown title",
          author: manifest.displayAuthor,
          isPodcastEpisode: manifest.episodeId != nil,
          savedAtEpoch: manifest.savedAtEpoch,
          totalDuration: manifest.totalDuration,
          byteCount: bytes
        )
      )
    }
    collected.sort { $0.savedAtEpoch > $1.savedAtEpoch }
    rows = collected
    totalBytes = sum
  }

  private func delete(_ row: DownloadManageRow) {
    model.removeLocalDownload(bookId: row.storageId)
  }

  /// Rekursive Verzeichnisgröße (Bytes) — nur für Anzeige, bewusst einfach gehalten.
  private func folderSize(at url: URL) -> Int64 {
    var total: Int64 = 0
    let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else { return 0 }
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true,
        let size = values.fileSize
      else { continue }
      total += Int64(size)
    }
    return total
  }
}

/// Eine gespeicherte Download-Zeile (Manifest-Metadaten + Größe).
private struct DownloadManageRow: Identifiable {
  let storageId: String
  let libraryItemId: String
  let episodeId: String?
  let title: String
  let author: String?
  let isPodcastEpisode: Bool
  let savedAtEpoch: TimeInterval
  let totalDuration: Double?
  let byteCount: Int64

  var id: String { storageId }

  var sizeLabel: String {
    ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
  }

  var durationLabel: String? {
    guard let d = totalDuration, d > 0 else { return nil }
    return formatDuration(seconds: d)
  }

  var savedLabel: String {
    guard savedAtEpoch > 0 else { return "" }
    let date = Date(timeIntervalSince1970: savedAtEpoch)
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.timeStyle = .none
    return fmt.string(from: date)
  }

  /// Kompakte Daueranzeige (z. B. „10h 23m").
  private func formatDuration(seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
  }
}

/// Zeile für aktiven oder wartenden Download mit Cover, Titel, Medienart und Progress / „Queued"-Badge.
private struct DownloadManageActiveRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let storageId: String
  let entry: DownloadCatalogEntry?
  let progress: Double
  let isQueued: Bool
  let token: String
  let coverURL: URL?
  let cacheAccount: URL?
  let cacheRevision: Int
  let onCancel: () -> Void

  private var titleText: String {
    entry?.title?.nilIfEmpty ?? (isQueued ? "Waiting…" : "Downloading…")
  }

  var body: some View {
    HStack(spacing: 12) {
      // Cover (quadratisch, 44 pt) — falls Library-ID bekannt; sonst Platzhalter-Icon.
      if let lid = entry?.libraryItemId {
        ZStack {
          model.appearancePalette.cardShadow
          CoverImageView(
            url: coverURL,
            token: token,
            itemId: lid,
            cacheAccount: cacheAccount,
            cacheRevision: cacheRevision,
            contentMode: .fill
          )
          .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
        }
        .frame(width: 44, height: 44)
      } else {
        SettingsCardIcon(
          systemName: isQueued ? "circle.dashed" : "arrow.down.circle",
          tint: themeAccent
        )
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(titleText)
          .font(.body.weight(.medium))
          .foregroundStyle(model.appearancePalette.textPrimary)
          .lineLimit(2)
        if let subtitle = entry?.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(model.appearancePalette.textSecondary)
            .lineLimit(1)
        }
        if isQueued {
          Text("Queued")
            .font(.caption2)
            .foregroundStyle(themeAccent)
        } else if entry?.isPodcastEpisode != true {
          // Fortschrittsbalken nur bei Hörbüchern — bei Podcast-Folgen (oft Einzel-Track
          // ohne zuverlässige Content-Length) springt der Balken sonst nur von 0 auf fertig.
          ProgressView(value: progress)
            .tint(themeAccent)
            .padding(.top, 1)
        } else {
          Text("Downloading…")
            .font(.caption2)
            .foregroundStyle(model.appearancePalette.textSecondary)
        }
      }
      Spacer(minLength: 8)
      Button(action: onCancel) {
        Image(systemName: "xmark.circle.fill")
          .font(.title3)
          .foregroundStyle(model.appearancePalette.textSecondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isQueued ? "Remove from queue" : "Cancel download")
    }
  }
}

/// Gespeicherte Download-Zeile mit Cover, Titel, Metadaten und Löschen-Button.
private struct DownloadManageSavedRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let row: DownloadManageRow
  let token: String
  let coverURL: URL?
  let cacheAccount: URL?
  let cacheRevision: Int
  let onDelete: () -> Void

  @State private var confirmDelete = false

  var body: some View {
    HStack(spacing: 12) {
      // Cover (quadratisch, 44 pt) — serverseitig gecacht, funktioniert dank CoverImageCache auch offline.
      ZStack {
        model.appearancePalette.cardShadow
        CoverImageView(
          url: coverURL,
          token: token,
          itemId: row.libraryItemId,
          cacheAccount: cacheAccount,
          cacheRevision: cacheRevision,
          contentMode: .fill
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.coverCornerRadius, style: .continuous))
      }
      .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 3) {
        Text(row.title)
          .font(.body.weight(.medium))
          .foregroundStyle(model.appearancePalette.textPrimary)
          .lineLimit(2)
        if let author = row.author, !author.isEmpty {
          Text(author)
            .font(.caption)
            .foregroundStyle(model.appearancePalette.textSecondary)
            .lineLimit(1)
        }
        HStack(spacing: 6) {
          if let dur = row.durationLabel {
            Text(dur)
          }
          if !row.savedLabel.isEmpty {
            Text("·")
            Text(row.savedLabel)
          }
        }
        .font(.caption2)
        .foregroundStyle(model.appearancePalette.textSecondary)
        .lineLimit(1)
      }
      Spacer(minLength: 8)

      Text(row.sizeLabel)
        .font(.caption.monospacedDigit())
        .foregroundStyle(model.appearancePalette.textSecondary)

      Button(role: .destructive) {
        confirmDelete = true
      } label: {
        Image(systemName: "trash")
          .font(.body)
          .foregroundStyle(AppTheme.danger)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Delete download")
      .confirmationDialog(
        "Delete \"\(row.title)\"?",
        isPresented: $confirmDelete,
        titleVisibility: .visible
      ) {
        Button("Delete", role: .destructive) {
          onDelete()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This removes the offline copy from this device. The item stays on your server.")
      }
    }
  }
}

// MARK: - Debug log export

private struct DebugLogExportView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var collector = DebugLogCollector.shared
  @State private var showShareSheet = false
  @State private var shareText = ""

  var body: some View {
    ServerAdminSection(title: "Debug Log") {
      AbstandGroupedCard {
        VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
          Text("\(collector.entries.count) entries")
            .font(.subheadline)
            .foregroundStyle(model.appearancePalette.textSecondary)

          HStack(spacing: AppTheme.Layout.withinSectionSpacing) {
            Button {
              shareText = collector.exportText
              showShareSheet = true
            } label: {
              Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .tint(model.appearanceAccentColor)

            Button(role: .destructive) {
              collector.clear()
            } label: {
              Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
          }
        }
      }

      if collector.entries.isEmpty {
        Text("No log entries yet.")
          .font(.subheadline)
          .foregroundStyle(model.appearancePalette.textSecondary)
          .padding(.vertical, 8)
      } else {
        AbstandGroupedCard {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(collector.entries.suffix(50)) { entry in
              Text(entry.message)
                .font(.caption.monospaced())
                .foregroundStyle(model.appearancePalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
    }
    .sheet(isPresented: $showShareSheet) {
      ShareSheet(items: [shareText])
    }
  }
}

private struct ShareSheet: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
