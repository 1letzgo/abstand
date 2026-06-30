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
    DisclosureGroup(isExpanded: $expanded) {
      ListeningHistorySessionList(
        sessions: sessions,
        isNetworkReachable: isNetworkReachable,
        emptyOnlineText: emptyOnlineText,
        emptyOfflineText: emptyOfflineText,
        onJumpToSessionStart: onJumpToSessionStart
      )
      .padding(.top, 6)
    } label: {
      Text("Listening history")
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .textCase(.uppercase)
        .tracking(0.6)
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

struct DetailToolbarMarkFinishedItem: View {
  @Environment(\.themeAccent) private var themeAccent
  let isFinished: Bool
  let enabled: Bool
  let onTap: () -> Void

  private var iconColor: Color {
    enabled ? themeAccent : AppTheme.textSecondary
  }

  var body: some View {
    Button(action: onTap) {
      Image(systemName: isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle")
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(iconColor)
    }
    .disabled(!enabled)
    .accessibilityLabel(isFinished ? "Mark as not finished" : "Mark as finished")
  }
}

/// Gemeinsame Kanten für Play / Read / Mark in der Buch-Detail-Leiste.
enum DetailActionRowMetrics {
  static let cornerRadius = MiniPlayerMetrics.controlCorner
  static let borderWidth: CGFloat = 1.5
  static let markButtonWidth: CGFloat = 52

  static var corner: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  @ViewBuilder
  static func progressFill(
    width: CGFloat,
    height: CGFloat,
    fillAmount: Double,
    isFinished: Bool,
    color: Color
  ) -> some View {
    let roundTrailing = isFinished || fillAmount >= 0.999
    if roundTrailing {
      corner
        .fill(color)
        .frame(width: width, height: height)
    } else {
      UnevenRoundedRectangle(
        topLeadingRadius: cornerRadius,
        bottomLeadingRadius: cornerRadius,
        bottomTrailingRadius: 0,
        topTrailingRadius: 0,
        style: .continuous
      )
      .fill(color)
      .frame(width: width, height: height)
    }
  }
}

/// Apple-Music-ähnliches Detail-Hero: Cover, Titel und Aktionszeile.
enum DetailHeroLayoutMetrics {
  static let coverTopPadding: CGFloat = 4
  /// eBook-Detail: maximale Cover-Breite (Hochformat, kein 1:1-Zwang).
  static let ebookCoverMaxWidth: CGFloat = 300
  static let titleTopSpacing: CGFloat = 18
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
  static let markIcon = Font.title3
  static let primaryAction = Font.headline
  static let compactPrimaryAction = Font.subheadline
  static let metaLabel = Font.footnote.weight(.semibold)
  static let metaValue = Font.body
  static let metaLink = Font.body
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

/// Kreis-Button links/rechts neben der Play-Pille (Finish, Read, …).
struct DetailHeroCircularButton: View {
  let systemImage: String
  let isActive: Bool
  let enabled: Bool
  let size: CGFloat
  let accessibilityLabel: String
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      ZStack {
        Circle()
          .fill(AppTheme.card.opacity(0.88))
        Image(systemName: systemImage)
          .font(DetailHeroTypography.markIcon)
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(isActive ? AppTheme.textPrimary : AppTheme.textSecondary)
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
      isActive: true,
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

@ViewBuilder
private func detailHeroBalanceSlot(size: CGFloat) -> some View {
  Color.clear
    .frame(width: size, height: size)
    .accessibilityHidden(true)
}

/// Hintergrund: Rahmen, Fortschrittsfüllung oder Vollfläche — einheitlich für alle Detail-Aktionsbuttons.
struct DetailActionControlChrome: View {
  @Environment(\.themeAccent) private var themeAccent
  let isFinished: Bool
  var progress01: Double = 0

  private var fillAmount: Double {
    if isFinished { return 1 }
    return min(1, max(0, progress01))
  }

  private var isEmptyProgress: Bool {
    !isFinished && fillAmount < 0.001
  }

  var body: some View {
    ZStack {
      if isFinished {
        DetailActionRowMetrics.corner.fill(themeAccent)
      } else {
        DetailActionRowMetrics.corner.stroke(
          themeAccent, lineWidth: DetailActionRowMetrics.borderWidth)
        if !isEmptyProgress {
          GeometryReader { geo in
            DetailActionRowMetrics.progressFill(
              width: max(0, geo.size.width * fillAmount),
              height: geo.size.height,
              fillAmount: fillAmount,
              isFinished: isFinished,
              color: themeAccent
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          }
        }
      }
    }
    .clipShape(DetailActionRowMetrics.corner)
  }
}

/// Schmaler Mark-Button neben Play/Read in der Detail-Leiste (deutlich schmaler als Hauptaktion).
struct DetailSecondaryMarkButton: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  let isFinished: Bool
  let markAccessibilityLabel: String
  let unmarkAccessibilityLabel: String
  let enabled: Bool
  let onTap: () -> Void

  private var iconColor: Color {
    let _ = model.appearanceThemeRevision
    guard enabled else { return AppTheme.textSecondary }
    if isFinished {
      return model.appearancePalette.foregroundOnAccent(themeAccent)
    }
    return themeAccent
  }

  var body: some View {
    Button(action: onTap) {
      ZStack {
        DetailActionControlChrome(isFinished: isFinished)
        Image(systemName: isFinished ? "arrow.uturn.backward" : "checkmark")
          .font(.subheadline.weight(.semibold))
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(iconColor)
      }
      .frame(width: DetailActionRowMetrics.markButtonWidth)
      .frame(maxHeight: .infinity)
      .contentShape(DetailActionRowMetrics.corner)
      .clipShape(DetailActionRowMetrics.corner)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityLabel(isFinished ? unmarkAccessibilityLabel : markAccessibilityLabel)
  }
}

/// Play-/Read-Button in Details: Akzentfläche füllt sich mit Fortschritt (keine separate Progress-Bar).
struct DetailProgressFillActionButton: View {
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

  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent

  let kind: Kind
  let progress01: Double
  let isFinished: Bool
  let action: () -> Void

  private var fillAmount: Double {
    if isFinished { return 1 }
    return min(1, max(0, progress01))
  }

  /// Kein Fortschritt und nicht abgeschlossen → nur Rahmen, kein Fill-Hintergrund.
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

  private var labelOnAccentFill: Color {
    let _ = model.appearanceThemeRevision
    return model.appearancePalette.foregroundOnAccent(themeAccent)
  }

  private var actionLabel: some View {
    HStack(spacing: 6) {
      Image(systemName: kind.systemImage)
        .symbolRenderingMode(.monochrome)
      Text(kind.title)
    }
    .font(.subheadline.weight(.semibold))
  }

  /// Solange der Balken Label nicht erreicht hat: Akzent; darunter kontrastreich auf gefüllter Fläche.
  @ViewBuilder
  private func actionLabelColored(fillWidth: CGFloat, in size: CGSize) -> some View {
    let masked = actionLabel
      .foregroundStyle(labelOnAccentFill)
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
  private var actionLabelColored: some View {
    if isFinished {
      actionLabel.foregroundStyle(labelOnAccentFill)
    } else {
      GeometryReader { geo in
        actionLabelColored(
          fillWidth: geo.size.width * fillAmount,
          in: geo.size
        )
        .frame(width: geo.size.width, height: geo.size.height)
      }
    }
  }

  private var actionControl: some View {
    ZStack {
      DetailActionControlChrome(isFinished: isFinished, progress01: progress01)
      actionLabelColored
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(DetailActionRowMetrics.corner)
    .clipShape(DetailActionRowMetrics.corner)
  }

  var body: some View {
    Button(action: action) {
      actionControl
    }
    .buttonStyle(.plain)
    .tint(nil)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(kind.accessibilityLabel)
    .accessibilityValue(progressAccessibilityLabel)
    .accessibilityHint(isFinished ? "Starts from the beginning" : "")
  }
}

extension DetailProgressFillActionButton {
  init(progress01: Double, isFinished: Bool, action: @escaping () -> Void) {
    self.init(kind: .play, progress01: progress01, isFinished: isFinished, action: action)
  }
}
