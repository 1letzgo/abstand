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
    // Nur ein pinned item (z. B. nur Audiobooks, keine Podcast-Bibliothek) →
    // Switch-Chip + Divider ausblenden, nur den sekundären Strip zeigen.
    if pinnedItems.count <= 1 {
      HStack(spacing: 0) {
        secondary()
          .frame(maxWidth: .infinity)
          .layoutPriority(1)
      }
      .abstandThemeRefresh()
    } else {
      HStack(spacing: AppTheme.ExpandingDock.itemSpacing) {
        HStack(spacing: AppTheme.ExpandingDock.itemSpacing) {
          ForEach(pinnedItems) { item in
            AbstandExpandingDockChip(
              item: item,
              isSelected: item.id == pinnedSelectionID,
              showsLabelWhenSelected: false,
              onSelect: {
                guard item.id != pinnedSelectionID else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(AppTheme.ExpandingDock.selectionAnimation) {
                  onSelectPinned(item.id)
                }
              }
            )
          }
        }
        .padding(.leading, AppTheme.ExpandingDock.horizontalPadding)
        .padding(.vertical, AppTheme.ExpandingDock.verticalPadding)

        Divider()
          .frame(height: AppTheme.ExpandingDock.circleSize)

        secondary()
          .frame(maxWidth: .infinity)
          .layoutPriority(1)
      }
      .abstandThemeRefresh()
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
