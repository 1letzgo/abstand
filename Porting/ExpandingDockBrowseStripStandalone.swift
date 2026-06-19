// ExpandingDockBrowseStripStandalone.swift
//
// Standalone-Port des abstand horizontalen Browse-Menüs (Expanding Dock).
// Eine Datei — in ein anderes iOS-Projekt kopieren, zum Target hinzufügen, fertig.
//
// Verwendung (Minimal):
//
//   @State private var selection = "home"
//
//   ExpandingDockIconMenu(
//     items: [
//       .init(id: "home", label: "Home", systemImage: "house.fill"),
//       .init(id: "library", label: "Library", systemImage: "books.vertical.fill"),
//     ],
//     selectionID: selection,
//     onSelect: { selection = $0 }
//   )
//   .expandingDockTheme(.darkYellow)   // oder .environment(\.expandingDockPalette, …)
//
// Mit fixem Strip + Sektionen:
//
//   FixedExpandingDockSectionsLayout(
//     screenBackground: Color(white: 0.07),
//     selection: selection,
//     sectionIDs: ["home", "library"],
//     scrollBottomInset: 24
//   ) {
//     ExpandingDockIconMenu(items: …, selectionID: selection, onSelect: { selection = $0 })
//   } sectionBody: { id in … }
//
// Cover-Pills: `coverURL` am Item setzen (AsyncImage). Eigenes Cover:
//   ExpandingDockBrowseStrip(…, cover: { item, size in AnyView(…) })

import SwiftUI
import UIKit

// MARK: - Theme

/// Farben für Dock-Pills — an deine App anpassen.
struct ExpandingDockPalette: Equatable {
  var background: Color
  var card: Color
  var textSecondary: Color
  var cardShadow: Color

  /// Lesbare Schrift auf voller Akzentfläche.
  func foregroundOnAccent(_ accent: Color) -> Color {
    guard let rgb = Self.rgbComponents(from: accent) else { return .white }
    let luminance = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
    return luminance > 0.55 ? Color(red: 42 / 255, green: 32 / 255, blue: 24 / 255) : .white
  }

  private static func rgbComponents(from color: Color) -> (r: Double, g: Double, b: Double)? {
    #if canImport(UIKit)
      let ui = UIColor(color)
      var r: CGFloat = 0
      var g: CGFloat = 0
      var b: CGFloat = 0
      var a: CGFloat = 0
      guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
      return (Double(r), Double(g), Double(b))
    #else
      return nil
    #endif
  }

  /// Entspricht abstand Dark + gelbem Akzent (#121212 / #252525 / #FBC02D).
  static let darkYellow = ExpandingDockPalette(
    background: Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255),
    card: Color(red: 37 / 255, green: 37 / 255, blue: 37 / 255),
    textSecondary: Color(red: 170 / 255, green: 170 / 255, blue: 170 / 255),
    cardShadow: Color.black.opacity(0.36)
  )
}

private struct ExpandingDockPaletteKey: EnvironmentKey {
  static let defaultValue = ExpandingDockPalette.darkYellow
}

private struct ExpandingDockAccentKey: EnvironmentKey {
  static let defaultValue = Color(red: 251 / 255, green: 192 / 255, blue: 45 / 255)
}

private struct ExpandingDockThemeRevisionKey: EnvironmentKey {
  static let defaultValue = 0
}

private struct ExpandingDockCardShadowEnabledKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  var expandingDockPalette: ExpandingDockPalette {
    get { self[ExpandingDockPaletteKey.self] }
    set { self[ExpandingDockPaletteKey.self] = newValue }
  }

  var expandingDockAccent: Color {
    get { self[ExpandingDockAccentKey.self] }
    set { self[ExpandingDockAccentKey.self] = newValue }
  }

  var expandingDockThemeRevision: Int {
    get { self[ExpandingDockThemeRevisionKey.self] }
    set { self[ExpandingDockThemeRevisionKey.self] = newValue }
  }

  var expandingDockCardShadowEnabled: Bool {
    get { self[ExpandingDockCardShadowEnabledKey.self] }
    set { self[ExpandingDockCardShadowEnabledKey.self] = newValue }
  }
}

extension View {
  func expandingDockTheme(
    _ palette: ExpandingDockPalette,
    accent: Color = Color(red: 251 / 255, green: 192 / 255, blue: 45 / 255),
    revision: Int = 0
  ) -> some View {
    environment(\.expandingDockPalette, palette)
      .environment(\.expandingDockAccent, accent)
      .environment(\.expandingDockThemeRevision, revision)
  }

  func expandingDockThemeRefresh() -> some View {
    modifier(ExpandingDockThemeRefreshModifier())
  }

  /// Kein Schatten-Bleed in horizontalen Scroll-Reihen.
  func expandingDockHorizontalScrollRow() -> some View {
    environment(\.expandingDockCardShadowEnabled, false)
      .background { ExpandingDockUIScrollViewClearBackground() }
  }

  func expandingDockFixedStripHeaderChrome() -> some View {
    modifier(ExpandingDockStripHeaderChromeModifier())
  }
}

private struct ExpandingDockThemeRefreshModifier: ViewModifier {
  @Environment(\.expandingDockThemeRevision) private var themeRevision

  func body(content: Content) -> some View {
    let _ = themeRevision
    content
  }
}

private struct ExpandingDockStripHeaderChromeModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.top, ExpandingDockLayout.stripToTitleSpacing)
      .padding(.bottom, ExpandingDockLayout.stripToContentSpacing)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Metriken (1:1 abstand)

enum ExpandingDockMetrics {
  static let inactiveIconOpacity: CGFloat = 0.72

  static let itemSpacing: CGFloat = 10
  static let horizontalPadding: CGFloat = 18
  static let verticalPadding: CGFloat = 4
  static let circleSize: CGFloat = 46
  static let iconSize: CGFloat = 21
  static let activeCoverSize: CGFloat = 28
  static let activeHeight: CGFloat = 46
  static let activeLeadingPadding: CGFloat = 14
  static let activeTrailingPadding: CGFloat = 18
  static let iconLabelSpacing: CGFloat = 9
  static let labelFontSize: CGFloat = 15.5
  static let centerWhenFewThreshold = 4

  static let selectionAnimation = Animation.spring(response: 0.32, dampingFraction: 0.72)

  static var inactiveIconSideInset: CGFloat { (circleSize - iconSize) / 2 }

  struct ChipColors {
    let activeBackground: Color
    let activeForeground: Color
    let inactiveBackground: Color
    let inactiveForeground: Color
    let activeShadow: Color

    init(palette: ExpandingDockPalette, accent: Color) {
      activeBackground = accent
      activeForeground = palette.foregroundOnAccent(accent)
      inactiveBackground = palette.card
      inactiveForeground = palette.textSecondary
      activeShadow = palette.cardShadow
    }
  }
}

enum ExpandingDockLayout {
  static let tabPaddingH: CGFloat = 16
  static let stripToTitleSpacing: CGFloat = 8
  static let stripToContentSpacing: CGFloat = 16
  static let titleToContentSpacing: CGFloat = 16
  static let scrollBottomInsetBase: CGFloat = 24
}

// MARK: - Datenmodell

struct ExpandingDockBrowseStripItem: Identifiable, Hashable {
  let id: String
  let label: String
  let systemImage: String
  /// Optional: Remote-Cover (AsyncImage). Für eigenes Laden → `ExpandingDockBrowseStrip.cover`.
  var coverURL: URL?
}

// MARK: - Scroll-Hintergrund transparent

struct ExpandingDockUIScrollViewClearBackground: UIViewRepresentable {
  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    DispatchQueue.main.async {
      Self.clearScrollViews(startingAt: uiView)
    }
  }

  private static func clearScrollViews(startingAt view: UIView) {
    var ancestor: UIView? = view.superview
    while let current = ancestor {
      if let scroll = current as? UIScrollView {
        scroll.backgroundColor = .clear
        scroll.isOpaque = false
        for sub in scroll.subviews {
          sub.backgroundColor = .clear
        }
        return
      }
      ancestor = current.superview
    }
  }
}

// MARK: - Button-Stil

struct ExpandingDockButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.9 : 1)
  }
}

// MARK: - Expanding Dock Strip

/// Inaktive Kategorien als Kreis-Icons, aktive als wachsende Kapsel.
struct ExpandingDockBrowseStrip: View {
  let items: [ExpandingDockBrowseStripItem]
  let selectionID: String
  let onSelect: (String) -> Void
  /// Optional: eigenes Cover statt `coverURL` / SF Symbol.
  var cover: ((ExpandingDockBrowseStripItem, CGFloat) -> AnyView)?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: ExpandingDockMetrics.itemSpacing) {
        ForEach(items) { item in
          ExpandingDockChip(
            item: item,
            isSelected: item.id == selectionID,
            cover: cover,
            onSelect: {
              guard item.id != selectionID else { return }
              UIImpactFeedbackGenerator(style: .soft).impactOccurred()
              withAnimation(ExpandingDockMetrics.selectionAnimation) {
                onSelect(item.id)
              }
            }
          )
        }
      }
      .padding(.horizontal, ExpandingDockMetrics.horizontalPadding)
      .padding(.vertical, ExpandingDockMetrics.verticalPadding)
      .frame(maxWidth: items.count < ExpandingDockMetrics.centerWhenFewThreshold ? .infinity : nil)
      .animation(ExpandingDockMetrics.selectionAnimation, value: selectionID)
    }
    .scrollContentBackground(.hidden)
    .expandingDockHorizontalScrollRow()
    .expandingDockThemeRefresh()
  }
}

/// Dünner Wrapper — entspricht `AbstandBrowseStripIconMenu`.
struct ExpandingDockIconMenu: View {
  let items: [ExpandingDockBrowseStripItem]
  let selectionID: String
  let onSelect: (String) -> Void
  var cover: ((ExpandingDockBrowseStripItem, CGFloat) -> AnyView)?

  var body: some View {
    ExpandingDockBrowseStrip(
      items: items,
      selectionID: selectionID,
      onSelect: onSelect,
      cover: cover
    )
  }
}

// MARK: - Chip

private struct ExpandingDockChip: View {
  @Environment(\.expandingDockPalette) private var palette
  @Environment(\.expandingDockAccent) private var accent
  @Environment(\.expandingDockThemeRevision) private var themeRevision

  let item: ExpandingDockBrowseStripItem
  let isSelected: Bool
  let cover: ((ExpandingDockBrowseStripItem, CGFloat) -> AnyView)?
  let onSelect: () -> Void

  private var usesCover: Bool { item.coverURL != nil || cover != nil }

  private var chipColors: ExpandingDockMetrics.ChipColors {
    let _ = themeRevision
    return ExpandingDockMetrics.ChipColors(palette: palette, accent: accent)
  }

  var body: some View {
    Button(action: onSelect) {
      Group {
        if usesCover, !isSelected {
          coverThumbnail(size: ExpandingDockMetrics.circleSize)
            .frame(
              width: ExpandingDockMetrics.circleSize,
              height: ExpandingDockMetrics.circleSize
            )
            .clipShape(Circle())
            .contentShape(Circle())
        } else {
          symbolOrCoverPill
        }
      }
    }
    .buttonStyle(ExpandingDockButtonStyle())
    .accessibilityLabel(item.label)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .expandingDockThemeRefresh()
  }

  private var symbolOrCoverPill: some View {
    HStack(spacing: isSelected ? ExpandingDockMetrics.iconLabelSpacing : 0) {
      Group {
        if usesCover {
          coverThumbnail(size: ExpandingDockMetrics.activeCoverSize)
        } else {
          Image(systemName: item.systemImage)
            .font(.system(size: ExpandingDockMetrics.iconSize, weight: .semibold))
            .foregroundStyle(
              isSelected
                ? chipColors.activeForeground
                : chipColors.inactiveForeground.opacity(ExpandingDockMetrics.inactiveIconOpacity)
            )
            .frame(width: ExpandingDockMetrics.iconSize, height: ExpandingDockMetrics.iconSize)
        }
      }

      Text(item.label)
        .font(.system(size: ExpandingDockMetrics.labelFontSize, weight: .semibold))
        .foregroundStyle(chipColors.activeForeground)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .opacity(isSelected ? 1 : 0)
        .frame(width: isSelected ? nil : 0, alignment: .leading)
        .clipped()
    }
    .padding(
      .leading,
      isSelected
        ? ExpandingDockMetrics.activeLeadingPadding
        : ExpandingDockMetrics.inactiveIconSideInset
    )
    .padding(
      .trailing,
      isSelected
        ? ExpandingDockMetrics.activeTrailingPadding
        : ExpandingDockMetrics.inactiveIconSideInset
    )
    .frame(height: ExpandingDockMetrics.activeHeight)
    .frame(width: isSelected ? nil : ExpandingDockMetrics.circleSize)
    .frame(minWidth: ExpandingDockMetrics.circleSize, minHeight: ExpandingDockMetrics.circleSize)
    .background { chipBackground }
    .clipShape(Capsule(style: .continuous))
    .contentShape(Capsule(style: .continuous))
  }

  @ViewBuilder
  private var chipBackground: some View {
    Capsule(style: .continuous)
      .fill(isSelected ? chipColors.activeBackground : chipColors.inactiveBackground)
      .shadow(
        color: isSelected ? chipColors.activeShadow : .clear,
        radius: 8,
        x: 0,
        y: 4
      )
  }

  @ViewBuilder
  private func coverThumbnail(size: CGFloat) -> some View {
    if let cover {
      cover(item, size)
    } else if let url = item.coverURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
        default:
          Image(systemName: item.systemImage)
            .font(.system(size: ExpandingDockMetrics.iconSize, weight: .semibold))
            .foregroundStyle(chipColors.inactiveForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(chipColors.inactiveBackground)
        }
      }
      .frame(width: size, height: size)
      .clipShape(Circle())
    } else {
      Image(systemName: item.systemImage)
        .font(.system(size: ExpandingDockMetrics.iconSize, weight: .semibold))
        .frame(width: size, height: size)
    }
  }
}

// MARK: - Fixer Strip + Sektionen

/// Großtitel → fixer Dock-Streifen → scrollender Inhalt je Sektion (Scroll-Position bleibt).
struct FixedExpandingDockSectionsLayout<ID: Hashable, Strip: View, Content: View>: View {
  var showsStrip: Bool = true
  var retainOffscreenSections: Bool = true
  var relayoutTrigger: AnyHashable?
  let screenBackground: Color
  let selection: ID
  let sectionIDs: [ID]
  let scrollBottomInset: CGFloat
  var onRefresh: (() async -> Void)?
  @ViewBuilder var strip: () -> Strip
  @ViewBuilder var sectionBody: (ID) -> Content

  @State private var mountedSectionIDs: Set<ID> = []
  @State private var sectionScrollPositions: [ID: ScrollPosition] = [:]

  var body: some View {
    VStack(spacing: 0) {
      if showsStrip {
        strip().expandingDockFixedStripHeaderChrome()
      }
      ZStack {
        screenBackground
        if shouldRenderSection(selection) {
          sectionScrollView(for: selection)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(screenBackground)
    .onAppear {
      if retainOffscreenSections {
        mountedSectionIDs.insert(selection)
      }
    }
    .onChange(of: selection) { _, newSelection in
      if retainOffscreenSections {
        mountedSectionIDs.insert(newSelection)
      }
    }
    .onChange(of: relayoutTrigger) { _, _ in
      guard relayoutTrigger != nil else { return }
      reapplyScrollPosition(for: selection)
    }
  }

  private func shouldRenderSection(_ sectionID: ID) -> Bool {
    retainOffscreenSections
      ? mountedSectionIDs.contains(sectionID)
      : selection == sectionID
  }

  private func scrollPositionBinding(for sectionID: ID) -> Binding<ScrollPosition> {
    Binding(
      get: { sectionScrollPositions[sectionID] ?? ScrollPosition(edge: .top) },
      set: { sectionScrollPositions[sectionID] = $0 }
    )
  }

  private func reapplyScrollPosition(for sectionID: ID) {
    let saved = sectionScrollPositions[sectionID]
    sectionScrollPositions[sectionID] = nil
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 32_000_000)
      sectionScrollPositions[sectionID] = saved ?? ScrollPosition(edge: .top)
    }
  }

  @ViewBuilder
  private func sectionScrollView(for sectionID: ID) -> some View {
    let base = ScrollView {
      sectionBody(sectionID)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, showsStrip ? 0 : ExpandingDockLayout.titleToContentSpacing)
        .padding(.bottom, scrollBottomInset)
        .background(screenBackground)
        .scrollTargetLayout()
    }
    .contentMargins(.horizontal, ExpandingDockLayout.tabPaddingH, for: .scrollContent)
    .scrollPosition(scrollPositionBinding(for: sectionID))
    .scrollContentBackground(.hidden)
    .background(screenBackground)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .id(sectionID)

    if let onRefresh {
      base.refreshable { await onRefresh() }
    } else {
      base
    }
  }
}

// MARK: - Preview

#if DEBUG
private enum PreviewSection: String, CaseIterable {
  case home = "Home"
  case library = "Library"
  case stats = "Stats"
  case settings = "Settings"

  var icon: String {
    switch self {
    case .home: "house.fill"
    case .library: "books.vertical.fill"
    case .stats: "chart.bar.fill"
    case .settings: "gearshape.fill"
    }
  }
}

#Preview("Expanding Dock") {
  struct Demo: View {
    @State private var selection = PreviewSection.home.rawValue

    var body: some View {
      NavigationStack {
        FixedExpandingDockSectionsLayout(
          screenBackground: ExpandingDockPalette.darkYellow.background,
          selection: selection,
          sectionIDs: PreviewSection.allCases.map(\.rawValue),
          scrollBottomInset: ExpandingDockLayout.scrollBottomInsetBase
        ) {
          ExpandingDockIconMenu(
            items: PreviewSection.allCases.map {
              ExpandingDockBrowseStripItem(
                id: $0.rawValue,
                label: $0.rawValue,
                systemImage: $0.icon
              )
            },
            selectionID: selection,
            onSelect: { selection = $0 }
          )
        } sectionBody: { id in
          VStack(alignment: .leading, spacing: 16) {
            Text(id)
              .font(.title2.bold())
              .foregroundStyle(.white)
            ForEach(0..<20, id: \.self) { i in
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ExpandingDockPalette.darkYellow.card)
                .frame(height: 72)
                .overlay(alignment: .leading) {
                  Text("Row \(i + 1)")
                    .padding(.horizontal, 16)
                    .foregroundStyle(.white)
                }
            }
          }
        }
        .navigationTitle("Demo")
        .toolbarTitleDisplayMode(.inlineLarge)
      }
      .expandingDockTheme(.darkYellow)
    }
  }

  return Demo()
}
#endif
