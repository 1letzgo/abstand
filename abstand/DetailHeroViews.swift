import SwiftUI
import UIKit

func coverDominantBackgroundTint(from image: UIImage) -> Color {
  guard let (r, g, b) = coverAverageRGB(from: image) else { return AppTheme.background }

  if AppTheme.palette.isDarkLike {
    let mix: CGFloat = 0.25
    let floor: CGFloat = 0.04
    return Color(
      red: Double(min(1, r * mix + floor)),
      green: Double(min(1, g * mix + floor)),
      blue: Double(min(1, b * mix + floor))
    )
  }

  let paper = UIColor(AppTheme.background)
  var pr: CGFloat = 0
  var pg: CGFloat = 0
  var pb: CGFloat = 0
  var pa: CGFloat = 0
  paper.getRed(&pr, green: &pg, blue: &pb, alpha: &pa)
  let coverWeight: CGFloat = 0.2
  let paperWeight = 1 - coverWeight
  return Color(
    red: Double(r * coverWeight + pr * paperWeight),
    green: Double(g * coverWeight + pg * paperWeight),
    blue: Double(b * coverWeight + pb * paperWeight)
  )
}

/// Kartenfläche für Buch-/Folgen-Detail, abgestimmt auf den Cover-Tint-Hintergrund
/// (`abstandDetailScrollBackground`): gleiche Farbfamilie wie der getönte Hintergrund statt der
/// neutralen Palette-`card`. Dark: etwas heller als der Tint (erhabene Fläche, gleiches Delta wie
/// Palette #121212 → #252525). Light: die tatsächlich gerenderte Fläche (Tint 0.42 über Papier)
/// nachbilden und leicht abdunkeln (Verhältnis Papier → Karte der Light-Palette, ~0.93).
/// Ohne echten Cover-Tint (Fallback = Palette-Hintergrund) konvergiert das Ergebnis auf die
/// normale Palette-`card`-Fläche.
func detailSectionCardTint(forBackgroundTint tint: Color) -> Color {
  guard let t = colorRGBComponents(of: tint) else { return AppTheme.card }

  if AppTheme.palette.isDarkLike {
    return Color(
      red: Double(min(1, t.r * 1.15 + 0.065)),
      green: Double(min(1, t.g * 1.15 + 0.065)),
      blue: Double(min(1, t.b * 1.15 + 0.065))
    )
  }

  guard let p = colorRGBComponents(of: AppTheme.background) else { return AppTheme.card }
  let darken: CGFloat = 0.93
  func channel(_ tintValue: CGFloat, _ paperValue: CGFloat) -> Double {
    let effective = tintValue * 0.42 + paperValue * 0.58
    return Double(min(1, effective * darken))
  }
  return Color(
    red: channel(t.r, p.r),
    green: channel(t.g, p.g),
    blue: channel(t.b, p.b)
  )
}

private func colorRGBComponents(of color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
  let ui = UIColor(color)
  var r: CGFloat = 0
  var g: CGFloat = 0
  var b: CGFloat = 0
  var a: CGFloat = 0
  guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
  return (r, g, b)
}

private func coverAverageRGB(from image: UIImage) -> (CGFloat, CGFloat, CGFloat)? {
  guard let ciImage = CIImage(image: image) else { return nil }
  var extent = ciImage.extent
  if !extent.width.isFinite || extent.width < 1 || !extent.height.isFinite || extent.height < 1 {
    extent = CGRect(origin: .zero, size: image.size)
  }
  guard extent.width >= 1, extent.height >= 1,
    let filter = CIFilter(
      name: "CIAreaAverage",
      parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: CIVector(cgRect: extent)]
    ),
    let output = filter.outputImage
  else { return nil }
  var bitmap = [UInt8](repeating: 0, count: 4)
  let ctx = CIContext(options: [.workingColorSpace: NSNull()])
  ctx.render(
    output,
    toBitmap: &bitmap,
    rowBytes: 4,
    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
    format: .RGBA8,
    colorSpace: CGColorSpaceCreateDeviceRGB()
  )
  return (
    CGFloat(bitmap[0]) / 255,
    CGFloat(bitmap[1]) / 255,
    CGFloat(bitmap[2]) / 255
  )
}

struct ListeningHistoryDisclosure: View {
  @Environment(\.themeAccent) private var themeAccent
  @Binding var expanded: Bool
  let sessions: [ABSListeningSession]
  let isNetworkReachable: Bool
  let emptyOnlineText: String
  let emptyOfflineText: String
  let onJumpToSessionStart: (ABSListeningSession) -> Void

  var body: some View {
    DetailMetaDisclosure(title: "Listening history", isExpanded: $expanded) {
      ListeningHistorySessionList(
        sessions: sessions,
        isNetworkReachable: isNetworkReachable,
        emptyOnlineText: emptyOnlineText,
        emptyOfflineText: emptyOfflineText,
        onJumpToSessionStart: onJumpToSessionStart
      )
    }
    .tint(themeAccent)
  }
}

// MARK: - Detail navigation toolbar (Download / Reset / Finished)

struct DetailToolbarDownloadItem: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let storageId: String
  let onStartDownload: () -> Void
  let onRemoveDownload: () -> Void

  var body: some View {
    Group {
      if model.downloads.activeItemId == storageId {
        ProgressView(value: model.downloads.progress)
          .progressViewStyle(.circular)
          .tint(themeAccent)
      } else if model.downloads.queuedItemIds.contains(storageId) {
        // Wartet in der Queue — kein Cancel-Button (nur über „Remove offline copy" nach Aktivierung).
        Image(systemName: "circle.dashed")
          .foregroundStyle(themeAccent)
          .accessibilityLabel("Queued")
      } else if model.downloadedItemIds.contains(storageId) {
        Button(action: onRemoveDownload) {
          Image(systemName: "arrow.down.circle.badge.xmark")
            .foregroundStyle(themeAccent)
        }
        .accessibilityLabel("Remove offline copy")
      } else {
        Button(action: onStartDownload) {
          Image(systemName: "arrow.down.circle")
            .foregroundStyle(themeAccent)
        }
        .accessibilityLabel("Download")
      }
    }
  }
}

struct DetailToolbarResetProgressItem: View {
  let enabled: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      Image(systemName: "clock.arrow.circlepath")
    }
    .disabled(!enabled)
    .accessibilityLabel("Reset listening progress")
  }
}

/// Gemeinsame Kanten für Play / Read / Mark in der Buch-Detail-Leiste.
enum DetailActionRowMetrics {
  static let cornerRadius = MiniPlayerMetrics.controlCorner
  static let borderWidth: CGFloat = 1.5

  static var corner: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }
}

/// Apple-Music-ähnliches Detail-Hero: Cover, Titel und Aktionszeile.
enum DetailHeroLayoutMetrics {
  static let coverTopPadding: CGFloat = 4
  /// Quadratisches Cover (Hörbuch/Podcast/eBook) — nicht volle Bildschirmbreite.
  static let squareCoverMaxWidth: CGFloat = 280
  /// Legacy-Alias — alle Detail-Cover nutzen `squareCoverMaxWidth` + 1:1-Letterboxing.
  static let ebookCoverMaxWidth: CGFloat = squareCoverMaxWidth
  /// Leicht abgerundete Cover-Ecken (Album-Artwork, Detail + Vollplayer).
  static let coverCornerRadius: CGFloat = 8
  static let titleTopSpacing: CGFloat = 18
  static let heroInfoLineSpacing: CGFloat = 5
  static let sideControlSize: CGFloat = 52
  static let compactSideControlSize: CGFloat = 46
  static let primaryControlHeight: CGFloat = 52
  static let compactPrimaryControlHeight: CGFloat = 48
  /// Breite der einzelnen Play-/Read-Pille (1 Medien-Aktion).
  static let singlePrimaryWidthFraction: CGFloat = 0.54
  static let actionRowSpacing: CGFloat = 16
  static let compactActionRowSpacing: CGFloat = 10
}

/// System-Typografie für Buch-/Folgen-Detail (Dynamic Type, HIG).
enum DetailHeroTypography {
  static let heroTitle = Font.title.bold()
  static let heroSubtitle = Font.title2
  /// Künstler/Autor unter dem Titel (Apple-Music-Album-Ansicht).
  static let heroArtist = Font.title3
  /// Dauer · Jahr · … — kleinere Zeile unter Autor.
  static let heroTertiary = Font.subheadline
  static let markIcon = Font.title3
  static let primaryAction = Font.headline
  static let compactPrimaryAction = Font.subheadline
  static let metaLabel = Font.footnote.weight(.semibold)
  static let metaValue = Font.body
  static let metaLink = Font.body
}

/// Cover mit Max-Breite, optional Max-Höhe, zentriert und leichtem Schatten (Album-Artwork).
struct DetailHeroCoverFrame<Content: View>: View {
  var maxWidth: CGFloat
  var maxHeight: CGFloat?
  var aspectRatio: CGFloat?
  @ViewBuilder var content: () -> Content

  init(
    maxWidth: CGFloat = DetailHeroLayoutMetrics.squareCoverMaxWidth,
    maxHeight: CGFloat? = nil,
    aspectRatio: CGFloat? = 1,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.aspectRatio = aspectRatio
    self.content = content
  }

  var body: some View {
    Group {
      if let aspectRatio {
        content()
          .aspectRatio(aspectRatio, contentMode: .fit)
      } else {
        content()
      }
    }
    .frame(maxWidth: maxWidth)
    .frame(maxHeight: maxHeight)
    .clipShape(
      RoundedRectangle(cornerRadius: DetailHeroLayoutMetrics.coverCornerRadius, style: .continuous)
    )
    .abstandCardElevation(.standard)
    .frame(maxWidth: .infinity)
    .padding(.top, DetailHeroLayoutMetrics.coverTopPadding)
  }
}

/// Titel, Autor/Künstler und Dauer·Jahr unter dem Cover (Apple-Music-Stil).
struct DetailHeroInfoSection: View {
  @Environment(\.themeAccent) private var themeAccent

  let title: String
  var subtitle: String? = nil
  /// Autoren mit ID — tippbar in Akzentfarbe (Hero); ersetzt `subtitle`, wenn gesetzt.
  var authorLinks: [(id: String, name: String)] = []
  var onAuthorTap: ((String, String) -> Void)? = nil
  var tertiaryParts: [String] = []

  private var resolvedSubtitle: String? {
    guard authorLinks.isEmpty else { return nil }
    guard let subtitle else { return nil }
    let t = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, t != "—" else { return nil }
    return t
  }

  private var tertiaryLine: String {
    tertiaryParts
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0 != "—" }
      .joined(separator: " · ")
  }

  var body: some View {
    VStack(spacing: DetailHeroLayoutMetrics.heroInfoLineSpacing) {
      Text(title)
        .font(DetailHeroTypography.heroTitle)
        .foregroundStyle(AppTheme.textPrimary)
        .multilineTextAlignment(.center)
      if !authorLinks.isEmpty {
        heroAuthorLinksRow
      } else if let resolvedSubtitle {
        Text(resolvedSubtitle)
          .font(DetailHeroTypography.heroArtist)
          .foregroundStyle(AppTheme.textPrimary)
          .multilineTextAlignment(.center)
      }
      if !tertiaryLine.isEmpty {
        Text(tertiaryLine)
          .font(DetailHeroTypography.heroTertiary)
          .foregroundStyle(AppTheme.textSecondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, DetailHeroLayoutMetrics.titleTopSpacing)
  }

  private var heroAuthorLinksRow: some View {
    HStack(spacing: 0) {
      ForEach(Array(authorLinks.enumerated()), id: \.offset) { idx, link in
        if idx > 0 {
          Text(", ")
            .font(DetailHeroTypography.heroArtist)
            .foregroundStyle(AppTheme.textPrimary)
        }
        Button {
          onAuthorTap?(link.id, link.name)
        } label: {
          Text(link.name)
            .font(DetailHeroTypography.heroArtist)
            .foregroundStyle(themeAccent)
        }
        .buttonStyle(.plain)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
  }
}

struct DetailHeroMediaAction: Identifiable {
  let id: String
  let markSystemImage: String
  let markAccessibilityLabel: String
  let markEnabled: Bool
  let onMark: () -> Void
  let kind: DetailHeroPrimaryButton.Kind
  let progress01: Double
  let isFinished: Bool
  let primaryEnabled: Bool
  let onPrimary: () -> Void
}

/// Kreis-Button links/rechts neben der Play-Pille (Finish, Read, …). Gleiche Akzentfarblogik wie
/// `DetailHeroPrimaryButton` (Umriss in Akzentfarbe, gefüllt bei „fertig"), damit Mark- und
/// Primäraktion optisch als ein zusammengehöriges Bedienelement wirken statt als Fremdkörper.
struct DetailHeroCircularButton: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let systemImage: String
  let isFinished: Bool
  let enabled: Bool
  let size: CGFloat
  let accessibilityLabel: String
  let onTap: () -> Void

  private var iconColor: Color {
    let _ = model.appearanceThemeRevision
    guard enabled else { return AppTheme.textSecondary }
    return isFinished ? model.appearancePalette.foregroundOnAccent(themeAccent) : themeAccent
  }

  private var strokeColor: Color {
    enabled ? themeAccent : AppTheme.textSecondary
  }

  var body: some View {
    Button(action: onTap) {
      ZStack {
        if isFinished, enabled {
          Circle().fill(themeAccent)
        } else {
          Circle().stroke(strokeColor, lineWidth: DetailActionRowMetrics.borderWidth)
        }
        Image(systemName: systemImage)
          .font(DetailHeroTypography.markIcon)
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(iconColor)
      }
      .frame(width: size, height: size)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityLabel(accessibilityLabel)
  }
}

/// Zentrale Play-/Read-Pille: beide in Appearance-Akzent.
struct DetailHeroPrimaryButton: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent

  enum Kind {
    case play
    case read

    var systemImage: String {
      switch self {
      case .play: "play.fill"
      case .read: "book.closed.fill"
      }
    }

    var title: String {
      switch self {
      case .play: "Play"
      case .read: "Read"
      }
    }

    var accessibilityLabel: String {
      switch self {
      case .play: "Play"
      case .read: "Read eBook"
      }
    }

    func progressAccessibilityValue(fillAmount: Double, isFinished: Bool, isEmpty: Bool) -> String {
      if isFinished { return "Finished" }
      if isEmpty { return "Not started" }
      switch self {
      case .play:
        return "\(Int(fillAmount * 100)) percent listened"
      case .read:
        return "\(Int(fillAmount * 100)) percent read"
      }
    }
  }

  let kind: Kind
  let progress01: Double
  let isFinished: Bool
  let enabled: Bool
  var compact: Bool = false
  let action: () -> Void

  private var fillAmount: Double {
    if isFinished { return 1 }
    return min(1, max(0, progress01))
  }

  private var isEmptyProgress: Bool {
    !isFinished && fillAmount < 0.001
  }

  private var progressAccessibilityLabel: String {
    kind.progressAccessibilityValue(
      fillAmount: fillAmount,
      isFinished: isFinished,
      isEmpty: isEmptyProgress
    )
  }

  private var labelOnAccent: Color {
    let _ = model.appearanceThemeRevision
    return model.appearancePalette.foregroundOnAccent(themeAccent)
  }

  private var actionLabel: some View {
    Label(kind.title, systemImage: kind.systemImage)
      .font(compact ? DetailHeroTypography.compactPrimaryAction : DetailHeroTypography.primaryAction)
      .labelStyle(.titleAndIcon)
  }

  @ViewBuilder
  private func accentLabelColored(fillWidth: CGFloat, in size: CGSize) -> some View {
    let masked = actionLabel
      .foregroundStyle(labelOnAccent)
      .frame(width: size.width, height: size.height)
      .mask(alignment: .leading) {
        Rectangle().frame(width: max(0, fillWidth))
      }

    actionLabel
      .foregroundStyle(themeAccent)
      .frame(width: size.width, height: size.height)
      .overlay(alignment: .leading) { masked }
  }

  @ViewBuilder
  private var buttonLabel: some View {
    if isFinished {
      actionLabel.foregroundStyle(labelOnAccent)
    } else {
      GeometryReader { geo in
        accentLabelColored(
          fillWidth: geo.size.width * fillAmount,
          in: geo.size
        )
        .frame(width: geo.size.width, height: geo.size.height)
      }
    }
  }

  @ViewBuilder
  private var primaryButtonChrome: some View {
    ZStack {
      if isFinished {
        Capsule(style: .continuous)
          .fill(themeAccent)
      } else {
        Capsule(style: .continuous)
          .stroke(themeAccent, lineWidth: DetailActionRowMetrics.borderWidth)
        if !isEmptyProgress {
          capsuleProgressFill(color: themeAccent)
        }
      }
    }
  }

  /// Fortschrittsfüllung in Pillenform — an Capsule-Umriss ausgerichtet (nicht abgeschnitten).
  @ViewBuilder
  private func capsuleProgressFill(color: Color) -> some View {
    Capsule(style: .continuous)
      .fill(color)
      .mask(alignment: .leading) {
        GeometryReader { geo in
          Rectangle()
            .frame(width: max(0, geo.size.width * fillAmount))
        }
      }
  }

  private var controlHeight: CGFloat {
    compact
      ? DetailHeroLayoutMetrics.compactPrimaryControlHeight
      : DetailHeroLayoutMetrics.primaryControlHeight
  }

  var body: some View {
    Button(action: action) {
      ZStack {
        primaryButtonChrome
        buttonLabel
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .frame(height: controlHeight)
      .contentShape(Capsule(style: .continuous))
      .clipShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(kind.accessibilityLabel)
    .accessibilityValue(progressAccessibilityLabel)
    .accessibilityHint(isFinished ? "Starts from the beginning" : "")
  }
}

/// Variable Aktionszeile: 3 Slots (Mark · Play · Balance) oder 4 (Mark · Play · Read · Mark).
struct DetailHeroActionsBar: View {
  let actions: [DetailHeroMediaAction]

  private var isCompact: Bool { actions.count > 1 }
  private var sideSize: CGFloat {
    isCompact
      ? DetailHeroLayoutMetrics.compactSideControlSize
      : DetailHeroLayoutMetrics.sideControlSize
  }
  private var rowSpacing: CGFloat {
    isCompact
      ? DetailHeroLayoutMetrics.compactActionRowSpacing
      : DetailHeroLayoutMetrics.actionRowSpacing
  }

  var body: some View {
    Group {
      if actions.count > 1 {
        compactActionsRow
      } else if let action = actions.first {
        singleActionRow(action)
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// Vier Buttons: [Mark Hören] [Play] [Read] [Mark Lesen]
  private var compactActionsRow: some View {
    HStack(spacing: rowSpacing) {
      heroMarkButton(actions[0])
      heroPrimaryButton(actions[0], compact: true)
        .frame(maxWidth: .infinity)
      if actions.count > 1 {
        heroPrimaryButton(actions[1], compact: true)
          .frame(maxWidth: .infinity)
        heroMarkButton(actions[1])
      }
    }
    .frame(height: DetailHeroLayoutMetrics.compactPrimaryControlHeight)
  }

  /// Drei Slots: [Mark] [Play/Read] [Balance] — zentriert wie Apple Music.
  private func singleActionRow(_ action: DetailHeroMediaAction) -> some View {
    HStack(spacing: rowSpacing) {
      Spacer(minLength: 0)
      heroMarkButton(action)
      heroPrimaryButton(action, compact: false)
        .containerRelativeFrame(.horizontal) { width, _ in
          width * DetailHeroLayoutMetrics.singlePrimaryWidthFraction
        }
      detailHeroBalanceSlot(size: sideSize)
      Spacer(minLength: 0)
    }
    .frame(height: DetailHeroLayoutMetrics.primaryControlHeight)
  }

  private func heroMarkButton(_ action: DetailHeroMediaAction) -> some View {
    DetailHeroCircularButton(
      systemImage: action.markSystemImage,
      isFinished: action.isFinished,
      enabled: action.markEnabled,
      size: sideSize,
      accessibilityLabel: action.markAccessibilityLabel,
      onTap: action.onMark
    )
  }

  private func heroPrimaryButton(_ action: DetailHeroMediaAction, compact: Bool) -> some View {
    DetailHeroPrimaryButton(
      kind: action.kind,
      progress01: action.progress01,
      isFinished: action.isFinished,
      enabled: action.primaryEnabled,
      compact: compact,
      action: action.onPrimary
    )
  }
}

// MARK: - Detail metadata (stacked label + content)

enum DetailMetaLayoutMetrics {
  static let thumbnailSize: CGFloat = 44
  static let thumbnailCornerRadius: CGFloat = 8
  static let labelToContentSpacing: CGFloat = 6
  static let labelIconSpacing: CGFloat = 5
  static let linkRowSpacing: CGFloat = 10
  static let pairColumnSpacing: CGFloat = AppTheme.Layout.withinSectionSpacing
  static let disclosureContentTopPadding: CGFloat = 6
  static let sectionCardSpacing: CGFloat = AppTheme.Layout.withinSectionSpacing
  /// Description-Card: Zeilen vor „More“.
  static let descriptionCollapsedLineLimit: Int = 4
  /// Grobe Schwelle — unterhalb kein „More“-Button.
  static let descriptionExpandCharacterThreshold: Int = 200
}

/// SF-Symbol je Meta-Überschrift (Detail Buch/Folge).
enum DetailMetaLabelIcon {
  static func systemImage(for title: String) -> String? {
    switch title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "author": "person.fill"
    case "narrator": "mic.fill"
    case "series": "books.vertical.fill"
    case "publisher": "building.2.fill"
    case "duration": "clock.fill"
    case "year": "calendar"
    case "genres": "square.grid.2x2.fill"
    case "tags": "tag.fill"
    case "description", "about": "text.alignleft"
    case "show": "dot.radiowaves.left.and.right"
    case "host": "person.wave.2.fill"
    case "subtitle": "text.quote"
    case "published": "calendar.badge.clock"
    case "categories": "folder.fill"
    case "episode": "waveform"
    case "show notes": "doc.text"
    case "chapters": "list.bullet"
    case "bookmarks": "bookmark.fill"
    case "listening history": "clock.arrow.circlepath"
    default: nil
    }
  }
}

/// Einheitliches Disclosure-Label (Chapters, Bookmarks, About, …).
struct DetailMetaDisclosureLabel: View {
  let title: String

  var body: some View {
    HStack(spacing: DetailMetaLayoutMetrics.labelIconSpacing) {
      if let icon = DetailMetaLabelIcon.systemImage(for: title) {
        Image(systemName: icon)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(AppTheme.textSecondary)
          .accessibilityHidden(true)
      }
      Text(title.uppercased())
        .font(DetailHeroTypography.metaLabel)
        .foregroundStyle(AppTheme.textSecondary)
        .tracking(0.6)
    }
  }
}

/// Kartenfläche in Buch-/Folgen-Details: aus dem Cover-Tint abgeleitet (siehe
/// `detailSectionCardTint(forBackgroundTint:)`) statt neutraler Palette-`card`.
/// `nil` (Default, z. B. Entity-Details ohne Cover-Tint) = Palette-`card`.
private struct DetailSectionCardBackgroundKey: EnvironmentKey {
  static let defaultValue: Color? = nil
}

extension EnvironmentValues {
  var detailSectionCardBackground: Color? {
    get { self[DetailSectionCardBackgroundKey.self] }
    set { self[DetailSectionCardBackgroundKey.self] = newValue }
  }
}

extension View {
  /// Buch-/Folgen-Detail: Karten in einer aus dem Cover-Tint abgesetzten Fläche rendern.
  func detailSectionCardsTinted(fromBackgroundTint tint: Color) -> some View {
    environment(\.detailSectionCardBackground, detailSectionCardTint(forBackgroundTint: tint))
  }
}

/// Disclosure mit Meta-Label-Stil (statt gemischter `.caption.bold`-Varianten).
/// Rendert eine Karte (wie `DetailDetailSectionCard`) — einheitlich für Chapters, Bookmarks, Sessions.
struct DetailMetaDisclosure<Content: View>: View {
  @Environment(\.detailSectionCardBackground) private var cardBackground
  let title: String
  @Binding var isExpanded: Bool
  @ViewBuilder var content: () -> Content

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      content()
        .padding(.top, DetailMetaLayoutMetrics.disclosureContentTopPadding)
    } label: {
      DetailMetaDisclosureLabel(title: title)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AppTheme.Layout.detailSectionCardPadding)
    .background(cardBackground ?? AppTheme.card, in: detailSectionCardShape)
    .abstandCardElevation(.subtle)
  }

  private var detailSectionCardShape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: AppTheme.Layout.detailSectionCardCornerRadius,
      style: .continuous
    )
  }
}

/// Gruppierter Meta-Block unter Play (People, Publication, Explore).
struct DetailDetailSectionCard<Content: View>: View {
  @Environment(\.detailSectionCardBackground) private var cardBackground
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(AppTheme.Layout.detailSectionCardPadding)
      .background(cardBackground ?? AppTheme.card, in: detailSectionCardShape)
      .abstandCardElevation(.subtle)
  }

  private var detailSectionCardShape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: AppTheme.Layout.detailSectionCardCornerRadius,
      style: .continuous
    )
  }
}

/// Meta-Zeile: Label oben, Inhalt darunter (nicht mehr nebeneinander).
struct DetailMetaField<Content: View>: View {
  let title: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.labelToContentSpacing) {
      HStack(spacing: DetailMetaLayoutMetrics.labelIconSpacing) {
        if let icon = DetailMetaLabelIcon.systemImage(for: title) {
          Image(systemName: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .accessibilityHidden(true)
        }
        Text(title.uppercased())
          .font(DetailHeroTypography.metaLabel)
          .foregroundStyle(AppTheme.textSecondary)
          .tracking(0.6)
      }
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Zwei Meta-Felder nebeneinander (z. B. Series + Year, Genres + Tags).
struct DetailMetaFieldPair<Left: View, Right: View>: View {
  let leftTitle: String
  let rightTitle: String
  @ViewBuilder var left: () -> Left
  @ViewBuilder var right: () -> Right

  var body: some View {
    HStack(alignment: .top, spacing: DetailMetaLayoutMetrics.pairColumnSpacing) {
      DetailMetaField(title: leftTitle, content: left)
        .frame(maxWidth: .infinity, alignment: .leading)
      DetailMetaField(title: rightTitle, content: right)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Wie `DetailMetaFieldPair`, aber auf schmalen Screens untereinander.
struct DetailMetaFieldPairAdaptive<Left: View, Right: View>: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  let leftTitle: String
  let rightTitle: String
  @ViewBuilder var left: () -> Left
  @ViewBuilder var right: () -> Right

  var body: some View {
    Group {
      if horizontalSizeClass == .regular {
        DetailMetaFieldPair(
          leftTitle: leftTitle,
          rightTitle: rightTitle,
          left: left,
          right: right
        )
      } else {
        VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.sectionCardSpacing) {
          DetailMetaField(title: leftTitle, content: left)
          DetailMetaField(title: rightTitle, content: right)
        }
      }
    }
  }
}

struct DetailMetaTextBlock: View {
  let text: String

  var body: some View {
    Text(text)
      .font(DetailHeroTypography.metaValue)
      .foregroundStyle(AppTheme.textPrimary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Description o. Ä.: gekürzt mit „More“ / „Less“.
struct DetailMetaExpandableTextBlock: View {
  @Environment(\.themeAccent) private var themeAccent
  let text: String
  @Binding var isExpanded: Bool
  var collapsedLineLimit: Int = DetailMetaLayoutMetrics.descriptionCollapsedLineLimit

  var body: some View {
    Group {
      if offersExpansion {
        expandableBody
      } else {
        DetailMetaTextBlock(text: text)
      }
    }
  }

  private var offersExpansion: Bool {
    let newlineCount = text.filter { $0 == "\n" }.count
    return text.count > DetailMetaLayoutMetrics.descriptionExpandCharacterThreshold
      || newlineCount >= collapsedLineLimit
  }

  @ViewBuilder
  private var expandableBody: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(text)
        .font(DetailHeroTypography.metaValue)
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(isExpanded ? nil : collapsedLineLimit)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack {
        Spacer(minLength: 0)
        Button(isExpanded ? "Less" : "More") {
          withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
          }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(themeAccent)
        .buttonStyle(.plain)
      }
    }
  }
}

struct DetailMetaLink: View {
  @Environment(\.themeAccent) private var themeAccent
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(DetailHeroTypography.metaLink)
        .foregroundStyle(themeAccent)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
  }
}

/// Autorenzeile mit rundem Thumbnail (`GET /api/authors/:id/image`).
struct DetailAuthorLinkRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let authorId: String
  let name: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        DetailAuthorThumbnail(authorId: authorId)
        Text(name)
          .font(DetailHeroTypography.metaLink)
          .foregroundStyle(themeAccent)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(name)
  }
}

/// Sprecher-Zeile mit Mikrofon-Platzhalter (kein API-Bild).
struct DetailNarratorLinkRow: View {
  @Environment(\.themeAccent) private var themeAccent
  let name: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack {
          Circle().fill(AppTheme.card)
          Image(systemName: "mic.fill")
            .font(.body)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(
          width: DetailMetaLayoutMetrics.thumbnailSize,
          height: DetailMetaLayoutMetrics.thumbnailSize
        )
        Text(name)
          .font(DetailHeroTypography.metaLink)
          .foregroundStyle(themeAccent)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(name)
  }
}

/// Show-/Cover-Zeile mit quadratischem Thumbnail (Podcast-Sendung, Serie, …).
struct DetailCoverLinkRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let itemId: String
  let title: String
  var updatedAt: Date? = nil
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        DetailCoverThumbnail(itemId: itemId, updatedAt: updatedAt)
        Text(title)
          .font(DetailHeroTypography.metaLink)
          .foregroundStyle(themeAccent)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}

struct DetailCoverThumbnail: View {
  @EnvironmentObject private var model: AppModel
  let itemId: String
  var updatedAt: Date? = nil

  var body: some View {
    CoverImageView(
      url: model.coverURL(for: itemId),
      token: model.token,
      itemId: itemId,
      cacheAccount: model.coverImageCacheAccountDirectory(),
      cacheRevision: model.coverImageCacheRevision(forItemUpdatedAt: updatedAt),
      contentMode: .fill
    )
    .frame(
      width: DetailMetaLayoutMetrics.thumbnailSize,
      height: DetailMetaLayoutMetrics.thumbnailSize
    )
    .clipShape(
      RoundedRectangle(
        cornerRadius: DetailMetaLayoutMetrics.thumbnailCornerRadius,
        style: .continuous
      )
    )
    .accessibilityHidden(true)
  }
}

struct DetailAuthorThumbnail: View {
  @EnvironmentObject private var model: AppModel
  let authorId: String

  var body: some View {
    Group {
      if let url = model.authorImageURL(authorId: authorId) {
        CoverImageView(
          url: url,
          token: model.token,
          itemId: "author:\(authorId)",
          cacheAccount: model.coverImageCacheAccountDirectory(),
          cacheRevision: model.coverImageCacheRevision,
          contentMode: .fill
        )
      } else {
        detailAuthorPlaceholder
      }
    }
    .frame(
      width: DetailMetaLayoutMetrics.thumbnailSize,
      height: DetailMetaLayoutMetrics.thumbnailSize
    )
    .clipShape(Circle())
    .accessibilityHidden(true)
  }

  private var detailAuthorPlaceholder: some View {
    ZStack {
      Circle().fill(AppTheme.card)
      Image(systemName: "person.fill")
        .font(.body)
        .foregroundStyle(AppTheme.textSecondary)
    }
  }
}

@ViewBuilder
private func detailHeroBalanceSlot(size: CGFloat) -> some View {
  Color.clear
    .frame(width: size, height: size)
    .accessibilityHidden(true)
}
