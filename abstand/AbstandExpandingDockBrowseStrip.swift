import SwiftUI
import UIKit

/// Inaktive Kategorien als Kreis-Icons, aktive als wachsende Kapsel (Expanding Dock).
struct AbstandExpandingDockBrowseStrip: View {
  let items: [AbstandBrowseStripItem]
  let selectionID: String
  /// `false`: kein Leading-Padding (z. B. als Sekundär-Strip in `AbstandPinnedBrowseStrip`,
  /// wo der Divider bereits den Leading-Abstand definiert — sonst doppeltes Padding).
  var appliesLeadingPadding: Bool = true
  let onSelect: (String) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: AppTheme.ExpandingDock.itemSpacing) {
        ForEach(items) { item in
          AbstandExpandingDockChip(
            item: item,
            isSelected: item.id == selectionID,
            onSelect: {
              guard item.id != selectionID else { return }
              UIImpactFeedbackGenerator(style: .soft).impactOccurred()
              withAnimation(AppTheme.ExpandingDock.selectionAnimation) {
                onSelect(item.id)
              }
            }
          )
        }
      }
      .padding(
        .leading,
        appliesLeadingPadding ? AppTheme.ExpandingDock.horizontalPadding : 0
      )
      .padding(.trailing, AppTheme.ExpandingDock.horizontalPadding)
      .padding(.vertical, AppTheme.ExpandingDock.verticalPadding)
      .frame(maxWidth: items.count < AppTheme.ExpandingDock.centerWhenFewThreshold ? .infinity : nil)
      .animation(AppTheme.ExpandingDock.selectionAnimation, value: selectionID)
    }
    .scrollContentBackground(.hidden)
    .abstandHorizontalScrollRow()
    .abstandThemeRefresh()
  }
}

/// Feste Primär-Auswahl links; nur der vom Aufrufer gelieferte Sekundär-Strip scrollt.
struct AbstandPinnedBrowseStrip<Secondary: View>: View {
  let pinnedItems: [AbstandBrowseStripItem]
  let pinnedSelectionID: String
  let onSelectPinned: (String) -> Void
  @ViewBuilder var secondary: () -> Secondary

  var body: some View {
    // Nur ein pinned item → Umschalter ausblenden, nur den sekundären Strip zeigen.
    if pinnedItems.count <= 1 {
      HStack(spacing: 0) {
        secondary()
          .frame(maxWidth: .infinity)
          .layoutPriority(1)
      }
      .abstandThemeRefresh()
    } else {
      HStack(spacing: AppTheme.ExpandingDock.itemSpacing) {
        AbstandExpandingDockBinarySwitch(
          items: pinnedItems,
          selectionID: pinnedSelectionID,
          onSelect: onSelectPinned
        )
        .padding(.leading, AppTheme.ExpandingDock.horizontalPadding)
        .padding(.vertical, AppTheme.ExpandingDock.verticalPadding)

        secondary()
          .frame(maxWidth: .infinity)
          .layoutPriority(1)
      }
      .abstandThemeRefresh()
    }
  }
}

/// Kompakter Zweiseiten-Umschalter (z. B. Audiobooks ↔ Podcasts) im Expanding-Dock-Stil.
struct AbstandExpandingDockBinarySwitch: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision

  let items: [AbstandBrowseStripItem]
  let selectionID: String
  let onSelect: (String) -> Void

  private var dockColors: AppTheme.ExpandingDock.Colors {
    let _ = themeRevision
    return AppTheme.ExpandingDock.Colors(
      palette: model.appearancePalette,
      accent: themeAccent
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
    .animation(AppTheme.ExpandingDock.selectionAnimation, value: selectionID)
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
    withAnimation(AppTheme.ExpandingDock.selectionAnimation) {
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
      accent: themeAccent
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
