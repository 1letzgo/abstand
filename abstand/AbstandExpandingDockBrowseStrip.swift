import SwiftUI
import UIKit

/// Inaktive Kategorien als Kreis-Icons, aktive als wachsende Kapsel (Expanding Dock).
struct AbstandExpandingDockBrowseStrip: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let items: [AbstandBrowseStripItem]
  let selectionID: String
  /// `false`: kein Leading-Padding (z. B. als Sekundär-Strip in `AbstandPinnedBrowseStrip`,
  /// wo der Divider bereits den Leading-Abstand definiert — sonst doppeltes Padding).
  var appliesLeadingPadding: Bool = true
  /// Erstes Element bleibt links stehen (z. B. „New“ im Podcast-Tab); der Rest scrollt darunter durch.
  var pinnedLeadingItem: AbstandBrowseStripItem? = nil
  let onSelect: (String) -> Void

  @Environment(\.appearanceThemeRevision) private var themeRevision

  private func chip(for item: AbstandBrowseStripItem) -> some View {
    AbstandExpandingDockChip(
      item: item,
      isSelected: item.id == selectionID,
      onSelect: {
        guard item.id != selectionID else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(reduceMotion ? nil : AppTheme.ExpandingDock.selectionAnimation) {
          onSelect(item.id)
        }
      }
    )
  }

  var body: some View {
    if let pinnedLeadingItem {
      pinnedBody(pinned: pinnedLeadingItem)
    } else {
      scrollingBody
    }
  }

  /// Fixes erstes Element links; daneben scrollen die übrigen Chips und werden zum fixen Chip hin
  /// ausgeblendet. Reines Stack-Layout ohne Messung: der fixe Chip bestimmt selbst, wo der Scrollbereich
  /// beginnt (er wächst/schrumpft mit der Auswahl), und die Überblendung ist ein `overlay` — sie
  /// beeinflusst die Höhe des Streifens nicht.
  private func pinnedBody(pinned: AbstandBrowseStripItem) -> some View {
    let _ = themeRevision
    let background = AppTheme.palette.background
    let leading = appliesLeadingPadding ? AppTheme.ExpandingDock.horizontalPadding : 0
    let fade = AppTheme.ExpandingDock.pinnedChipFadeWidth
    let scrolling = items.filter { $0.id != pinned.id }
    return HStack(spacing: 0) {
      chip(for: pinned)
        .padding(.leading, leading)
        .padding(.vertical, AppTheme.ExpandingDock.verticalPadding)
        .zIndex(1)
        .animation(reduceMotion ? nil : AppTheme.ExpandingDock.selectionAnimation, value: selectionID)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: AppTheme.ExpandingDock.itemSpacing) {
          ForEach(scrolling) { item in chip(for: item) }
        }
        // Ruhestellung: erster Chip liegt direkt hinter der Überblendung.
        .padding(.leading, fade)
        .padding(.trailing, AppTheme.ExpandingDock.horizontalPadding)
        .padding(.vertical, AppTheme.ExpandingDock.verticalPadding)
        .animation(reduceMotion ? nil : AppTheme.ExpandingDock.selectionAnimation, value: selectionID)
      }
      .scrollContentBackground(.hidden)
      .overlay(alignment: .leading) {
        LinearGradient(
          colors: [background, background.opacity(0)],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: fade)
        .allowsHitTesting(false)
      }
      .abstandHorizontalScrollRow()
    }
    .abstandThemeRefresh()
  }

  private var scrollingBody: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: AppTheme.ExpandingDock.itemSpacing) {
        ForEach(items) { item in chip(for: item) }
      }
      .padding(
        .leading,
        appliesLeadingPadding ? AppTheme.ExpandingDock.horizontalPadding : 0
      )
      .padding(.trailing, AppTheme.ExpandingDock.horizontalPadding)
      .padding(.vertical, AppTheme.ExpandingDock.verticalPadding)
      .frame(maxWidth: items.count < AppTheme.ExpandingDock.centerWhenFewThreshold ? .infinity : nil)
      .animation(reduceMotion ? nil : AppTheme.ExpandingDock.selectionAnimation, value: selectionID)
    }
    .scrollContentBackground(.hidden)
    .abstandHorizontalScrollRow()
    .abstandThemeRefresh()
  }
}

/// Bei mehreren Libraries: zwei fixierte Dropdown-Pills (50/50). Sonst: scrollbarer Expanding-Dock-Strip.
struct AbstandPinnedBrowseStrip: View {
  /// Wenn `count > 1`: Library-Dropdown links.
  var libraryPickerItems: [AbstandBrowseStripItem] = []
  var libraryPickerSelectionID: String = ""
  var onSelectLibrary: ((String) -> Void)? = nil

  let secondaryItems: [AbstandBrowseStripItem]
  let secondarySelectionID: String
  /// Nur im Dock-Strip (eine Library): dieses Element bleibt links stehen, der Rest scrollt darunter durch.
  var pinnedLeadingItem: AbstandBrowseStripItem? = nil
  let onSelectSecondary: (String) -> Void
  var secondaryAccessibilityLabel: String = "Browse"
  var secondaryAccessibilityHint: String = "Chooses which section to browse"

  private var showsLibraryPicker: Bool {
    onSelectLibrary != nil && libraryPickerItems.count > 1
  }

  var body: some View {
    if showsLibraryPicker, let onSelectLibrary {
      HStack(spacing: AppTheme.ExpandingDock.itemSpacing) {
        AbstandBrowseStripDropdownPill(
          items: libraryPickerItems,
          selectionID: libraryPickerSelectionID,
          fallbackSystemImage: "books.vertical.fill",
          accessibilityLabel: "Library",
          accessibilityHint: "Chooses which library to browse",
          onSelect: onSelectLibrary
        )
        .equatable()
        .frame(maxWidth: .infinity)

        AbstandBrowseStripDropdownPill(
          items: secondaryItems,
          selectionID: secondarySelectionID,
          fallbackSystemImage: "square.grid.2x2",
          accessibilityLabel: secondaryAccessibilityLabel,
          accessibilityHint: secondaryAccessibilityHint,
          onSelect: onSelectSecondary
        )
        .equatable()
        .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, AppTheme.ExpandingDock.horizontalPadding)
      .padding(.vertical, AppTheme.ExpandingDock.verticalPadding)
      .abstandThemeRefresh()
    } else {
      AbstandExpandingDockBrowseStrip(
        items: secondaryItems,
        selectionID: secondarySelectionID,
        appliesLeadingPadding: true,
        pinnedLeadingItem: pinnedLeadingItem,
        onSelect: onSelectSecondary
      )
    }
  }
}

/// Fixierte Dropdown-Pill im Expanding-Dock-Stil (Library- oder Sektionswahl).
///
/// Equatable und bewusst **ohne** `@EnvironmentObject AppModel`: Der Strip hängt im Katalog-Layout,
/// das bei jedem `objectWillChange` des Models neu evaluiert wird (Download-Fortschritt alle
/// 450 ms, Play/Pause, Fortschritt …). Ein `Menu`, dessen Label/Inhalt dabei jedes Mal neu
/// gebaut wird, flackert — auch im geöffneten Zustand. Farben kommen deshalb über den
/// Revision-Key + `AppTheme.palette` (siehe CLAUDE.md, Ausnahme zur Palette-Regel).
struct AbstandBrowseStripDropdownPill: View, Equatable {
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  let items: [AbstandBrowseStripItem]
  let selectionID: String
  var fallbackSystemImage: String = "books.vertical.fill"
  var accessibilityLabel: String = "Menu"
  var accessibilityHint: String = ""
  /// Feste Label-Breite. `Menu` schlägt seinem Label nicht in jedem Kontext eine Breite vor —
  /// im `HStack` des Browse-Strips verteilt der Stack, in einer Karte bleibt die Kapsel sonst
  /// auf Inhaltsbreite. Dort die gemessene Kartenbreite durchreichen.
  var labelWidth: CGFloat? = nil
  let onSelect: (String) -> Void

  /// `onSelect` bleibt außen vor — Closures sind nicht vergleichbar, und die Aufrufer fangen
  /// nur stabile Referenzen (Model) ein.
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.items == rhs.items
      && lhs.selectionID == rhs.selectionID
      && lhs.fallbackSystemImage == rhs.fallbackSystemImage
      && lhs.accessibilityLabel == rhs.accessibilityLabel
      && lhs.accessibilityHint == rhs.accessibilityHint
      && lhs.labelWidth == rhs.labelWidth
  }

  private var dockColors: AppTheme.ExpandingDock.Colors {
    let _ = themeRevision
    return AppTheme.ExpandingDock.Colors(
      palette: AppTheme.palette,
      accent: AppTheme.palette.textPrimary
    )
  }

  private var selectedItem: AbstandBrowseStripItem? {
    items.first(where: { $0.id == selectionID }) ?? items.first
  }

  var body: some View {
    Menu {
      ForEach(items) { item in
        Button {
          guard item.id != selectionID else { return }
          UIImpactFeedbackGenerator(style: .soft).impactOccurred()
          onSelect(item.id)
        } label: {
          Label(item.label, systemImage: item.systemImage)
        }
      }
    } label: {
      HStack(spacing: AppTheme.ExpandingDock.iconLabelSpacing) {
        Image(systemName: selectedItem?.systemImage ?? fallbackSystemImage)
          .font(.system(size: AppTheme.ExpandingDock.iconSize, weight: .semibold))
          .layoutPriority(1)
        Text(selectedItem?.label ?? accessibilityLabel)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 10, weight: .bold))
          .layoutPriority(1)
      }
      .foregroundStyle(dockColors.activeForeground)
      .padding(.horizontal, AppTheme.Layout.cardPadding)
      .frame(maxWidth: .infinity)
      .frame(width: labelWidth)
      .frame(height: AppTheme.ExpandingDock.activeHeight)
      .background {
        Capsule(style: .continuous)
          .fill(dockColors.activeBackground)
          .shadow(color: dockColors.activeShadow.opacity(0.35), radius: 6, x: 0, y: 3)
      }
      .contentShape(Capsule(style: .continuous))
    }
    .tint(themeAccent)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(selectedItem?.label ?? "")
    .accessibilityHint(accessibilityHint)
  }
}

/// Legacy-Alias für den Library-Dropdown.
typealias AbstandLibraryPickerMenu = AbstandBrowseStripDropdownPill

/// Kompakter Zweiseiten-Umschalter (z. B. Audiobooks ↔ Podcasts) im Expanding-Dock-Stil.
struct AbstandExpandingDockBinarySwitch: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let items: [AbstandBrowseStripItem]
  let selectionID: String
  let onSelect: (String) -> Void

  private var dockColors: AppTheme.ExpandingDock.Colors {
    let _ = themeRevision
    return AppTheme.ExpandingDock.Colors(
      palette: model.appearancePalette,
      accent: model.appearancePalette.textPrimary
    )
  }

  private var selectedLabel: String {
    items.first(where: { $0.id == selectionID })?.label ?? items.first?.label ?? ""
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(items) { item in
        segmentButton(for: item)
      }
    }
    .padding(AppTheme.ExpandingDock.binarySwitchInnerPadding)
    .frame(height: AppTheme.ExpandingDock.activeHeight)
    .background {
      Capsule(style: .continuous)
        .fill(dockColors.inactiveBackground)
        .shadow(color: dockColors.activeShadow.opacity(0.35), radius: 6, x: 0, y: 3)
    }
    .clipShape(Capsule(style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Library media")
    .accessibilityValue(selectedLabel)
    .accessibilityAddTraits(.isToggle)
    .accessibilityHint("Switches between \(items.map(\.label).joined(separator: " and "))")
    .accessibilityAdjustableAction { direction in
      guard items.count >= 2,
        let currentIndex = items.firstIndex(where: { $0.id == selectionID })
      else { return }
      let nextIndex: Int
      switch direction {
      case .increment:
        nextIndex = (currentIndex + 1) % items.count
      case .decrement:
        nextIndex = (currentIndex - 1 + items.count) % items.count
      @unknown default:
        return
      }
      select(items[nextIndex].id)
    }
    .animation(reduceMotion ? nil : AppTheme.ExpandingDock.selectionAnimation, value: selectionID)
    .abstandThemeRefresh()
  }

  private func segmentButton(for item: AbstandBrowseStripItem) -> some View {
    let isSelected = item.id == selectionID
    return Button {
      select(item.id)
    } label: {
      Image(systemName: item.systemImage)
        .font(.headline.weight(.semibold))
        .foregroundStyle(
          isSelected
            ? dockColors.activeForeground
            : dockColors.inactiveForeground.opacity(AppTheme.ExpandingDock.inactiveIconOpacity)
        )
        .frame(
          width: AppTheme.ExpandingDock.binarySwitchSegmentWidth,
          height: AppTheme.ExpandingDock.circleSize - (AppTheme.ExpandingDock.binarySwitchInnerPadding * 2)
        )
        .background {
          if isSelected {
            Capsule(style: .continuous)
              .fill(dockColors.activeBackground)
          }
        }
        .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(AbstandExpandingDockButtonStyle())
    .accessibilityHidden(true)
  }

  private func select(_ id: String) {
    guard id != selectionID else { return }
    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    withAnimation(reduceMotion ? nil : AppTheme.ExpandingDock.selectionAnimation) {
      onSelect(id)
    }
  }
}

struct AbstandExpandingDockChip: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  let item: AbstandBrowseStripItem
  let isSelected: Bool
  var showsLabelWhenSelected = true
  let onSelect: () -> Void

  private var usesCover: Bool { item.coverItemId != nil }
  private var showsExpandedLabel: Bool { isSelected && showsLabelWhenSelected }

  private var dockColors: AppTheme.ExpandingDock.Colors {
    let _ = themeRevision
    return AppTheme.ExpandingDock.Colors(
      palette: model.appearancePalette,
      accent: model.appearancePalette.textPrimary
    )
  }

  var body: some View {
    Button(action: onSelect) {
      Group {
        if usesCover, !isSelected {
          coverThumbnail(size: AppTheme.ExpandingDock.circleSize)
            .frame(
              width: AppTheme.ExpandingDock.circleSize,
              height: AppTheme.ExpandingDock.circleSize
            )
            .clipShape(Circle())
            .contentShape(Circle())
        } else {
          symbolOrCoverPill
        }
      }
    }
    .buttonStyle(AbstandExpandingDockButtonStyle())
    .accessibilityLabel(item.label)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .abstandThemeRefresh()
  }

  private var symbolOrCoverPill: some View {
    HStack(spacing: showsExpandedLabel ? AppTheme.ExpandingDock.iconLabelSpacing : 0) {
      Group {
        if usesCover, let coverItemId = item.coverItemId {
          coverThumbnail(size: AppTheme.ExpandingDock.activeCoverSize, itemId: coverItemId)
        } else {
          Image(systemName: item.systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(
              isSelected
                ? dockColors.activeForeground
                : dockColors.inactiveForeground.opacity(
                  AppTheme.ExpandingDock.inactiveIconOpacity)
            )
            .frame(width: AppTheme.ExpandingDock.iconSize, height: AppTheme.ExpandingDock.iconSize)
        }
      }

      Text(item.label)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(dockColors.activeForeground)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .opacity(showsExpandedLabel ? 1 : 0)
        .frame(width: showsExpandedLabel ? nil : 0, alignment: .leading)
        .clipped()
    }
    .padding(
      .leading,
      showsExpandedLabel
        ? AppTheme.ExpandingDock.activeLeadingPadding : AppTheme.ExpandingDock.inactiveIconSideInset
    )
    .padding(
      .trailing,
      showsExpandedLabel
        ? AppTheme.ExpandingDock.activeTrailingPadding : AppTheme.ExpandingDock.inactiveIconSideInset
    )
    .frame(height: AppTheme.ExpandingDock.activeHeight)
    .frame(width: showsExpandedLabel ? nil : AppTheme.ExpandingDock.circleSize)
    .frame(minWidth: AppTheme.ExpandingDock.circleSize, minHeight: AppTheme.ExpandingDock.circleSize)
    .background { chipBackground }
    .clipShape(Capsule(style: .continuous))
    .contentShape(Capsule(style: .continuous))
  }

  @ViewBuilder
  private var chipBackground: some View {
    Capsule(style: .continuous)
      .fill(
        isSelected
          ? dockColors.activeBackground
          : dockColors.inactiveBackground
      )
      .shadow(
        color: isSelected ? dockColors.activeShadow : .clear,
        radius: 8,
        x: 0,
        y: 4
      )
  }

  @ViewBuilder
  private func coverThumbnail(size: CGFloat, itemId: String? = nil) -> some View {
    let resolvedItemId = itemId ?? item.coverItemId ?? item.id
    CoverImageView(
      url: model.coverURL(for: resolvedItemId),
      token: model.token,
      itemId: resolvedItemId,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheRevision: model.coverImageCacheRevision(forBookId: resolvedItemId)
    )
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}
