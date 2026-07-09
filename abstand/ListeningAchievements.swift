import SwiftUI

/// Abzeichen-Stufe (Level 1–5).
enum ListeningAchievementTier: Int, Comparable, CaseIterable {
  case locked = 0
  case level1 = 1
  case level2 = 2
  case level3 = 3
  case level4 = 4
  case level5 = 5

  static func < (lhs: ListeningAchievementTier, rhs: ListeningAchievementTier) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  var levelNumber: Int? {
    switch self {
    case .locked: return nil
    case .level1: return 1
    case .level2: return 2
    case .level3: return 3
    case .level4: return 4
    case .level5: return 5
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .locked: return "Not unlocked"
    case .level1: return "Level 1"
    case .level2: return "Level 2"
    case .level3: return "Level 3"
    case .level4: return "Level 4"
    case .level5: return "Maximum level"
    }
  }

  /// Icon-/Badge-Farbe abgestuft aus der Appearance-Akzentfarbe.
  func adaptiveTint(accent: Color, palette: AppColorPalette) -> Color {
    switch self {
    case .locked:
      return palette.textSecondary.opacity(0.45)
    case .level1:
      return accent.opacity(palette.isDarkLike ? 0.48 : 0.38)
    case .level2:
      return accent.opacity(palette.isDarkLike ? 0.60 : 0.52)
    case .level3:
      return accent.opacity(palette.isDarkLike ? 0.74 : 0.68)
    case .level4:
      return accent.opacity(palette.isDarkLike ? 0.88 : 0.84)
    case .level5:
      return accent
    }
  }

  /// Deckung der Badge-Fläche: je höher das Level, desto deckender ("dunkler").
  func badgeFillOpacity(isDarkLike: Bool) -> Double {
    switch self {
    case .locked:
      return isDarkLike ? 0.10 : 0.08
    case .level1:
      return isDarkLike ? 0.14 : 0.12
    case .level2:
      return isDarkLike ? 0.26 : 0.22
    case .level3:
      return isDarkLike ? 0.42 : 0.36
    case .level4:
      return isDarkLike ? 0.70 : 0.62
    case .level5:
      return 1.0
    }
  }

  /// Ab Level 4 ist das Badge flächig gefüllt → Ziffer kontrastiert (weiß/dunkel).
  var usesSolidBadgeFill: Bool {
    self == .level4 || self == .level5
  }
}

/// Messgröße für Stats-Achievements (Schwellen pro Level 1–5).
enum ListeningAchievementKind: String, Codable, CaseIterable, Identifiable {
  case listeningTimeHours
  case activeDays
  case longestStreak
  case currentStreak
  case marathonDay
  case finishedBooks
  case finishedEpisodes
  case libraryDepthAuthors

  var id: String { rawValue }

  /// Reihenfolge in der Level-Ansicht (`allCases`: Listening time, dann Active days, …).
  static func sortedForDisplay(_ achievements: [ListeningAchievementState]) -> [ListeningAchievementState] {
    allCases.compactMap { kind in achievements.first { $0.kind == kind } }
  }

  var title: String {
    switch self {
    case .longestStreak: return "Longest streak"
    case .currentStreak: return "Current streak"
    case .listeningTimeHours: return "Listening time"
    case .activeDays: return "Active days"
    case .marathonDay: return "Marathon day"
    case .finishedBooks: return "Finished books"
    case .finishedEpisodes: return "Finished episodes"
    case .libraryDepthAuthors: return "Authors listened"
    }
  }

  var systemImage: String {
    switch self {
    case .longestStreak: return "flame.fill"
    case .currentStreak: return "bolt.fill"
    case .listeningTimeHours: return "headphones.circle.fill"
    case .activeDays: return "calendar"
    case .marathonDay: return "sun.max.fill"
    case .finishedBooks: return "book.fill"
    case .finishedEpisodes: return "mic.fill"
    case .libraryDepthAuthors: return "person.2.fill"
    }
  }

  /// Schwellen in der Einheit von `currentValue` (Streak/Tage/Anzahl/Stunden), Level 1–5.
  var thresholds: [Int] {
    switch self {
    case .longestStreak: return [50, 100, 250, 400, 600]
    case .currentStreak: return [3, 7, 14, 30, 90]
    case .listeningTimeHours: return [100, 250, 500, 1000, 2500]
    case .activeDays: return [50, 250, 500, 750, 1000]
    case .marathonDay: return [3_600, 7_200, 14_400, 21_600, 28_800]
    case .finishedBooks: return [25, 50, 100, 250, 400]
    case .finishedEpisodes: return [25, 50, 100, 250, 400]
    case .libraryDepthAuthors: return [10, 25, 50, 100, 200]
    }
  }

  private func achievedCount(for value: Int) -> Int {
    thresholds.reduce(0) { count, threshold in
      value >= threshold ? count + 1 : count
    }
  }

  func tier(for value: Int) -> ListeningAchievementTier {
    let count = achievedCount(for: value)
    guard count > 0 else { return .locked }
    return ListeningAchievementTier(rawValue: min(count, ListeningAchievementTier.level5.rawValue)) ?? .level5
  }

  func nextThreshold(after value: Int) -> Int? {
    thresholds.first { value < $0 }
  }

  func progressFraction(toward value: Int) -> Double {
    let t = thresholds
    guard !t.isEmpty else { return 0 }
    let achieved = achievedCount(for: value)
    if achieved >= t.count { return 1 }
    if achieved == 0 {
      let goal = Double(t[0])
      guard goal > 0 else { return 0 }
      return min(1, max(0, Double(value) / goal))
    }
    let span = Double(t[achieved] - t[achieved - 1])
    guard span > 0 else { return 1 }
    return min(1, max(0, Double(value - t[achieved - 1]) / span))
  }

  func formattedValue(_ value: Int) -> String {
    switch self {
    case .listeningTimeHours:
      return "\(value) h"
    case .marathonDay:
      return Self.formatMarathonDaySeconds(value)
    case .longestStreak, .currentStreak, .activeDays:
      return "\(value)"
    case .finishedBooks, .finishedEpisodes, .libraryDepthAuthors:
      return "\(value)"
    }
  }

  func formattedThreshold(_ threshold: Int) -> String {
    switch self {
    case .listeningTimeHours: return "\(threshold) h"
    case .marathonDay: return Self.formatMarathonDaySeconds(threshold)
    default: return "\(threshold)"
    }
  }

  private static func formatMarathonDaySeconds(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    if h > 0, m > 0 { return "\(h) h \(m) m" }
    if h > 0 { return "\(h) h" }
    if m > 0 { return "\(m) m" }
    return "0 m"
  }

  /// Erklärung für das Info-Popup.
  var explanation: String {
    switch self {
    case .listeningTimeHours:
      return "Total listening time on this account (hours)."
    case .longestStreak:
      return "Longest run of consecutive calendar days with any listening."
    case .currentStreak:
      return "Your current streak of consecutive days with listening."
    case .activeDays:
      return "Total number of calendar days on which you listened."
    case .marathonDay:
      return "Most listening time on a single calendar day."
    case .finishedBooks:
      return "Audiobooks marked as finished."
    case .finishedEpisodes:
      return "Podcast episodes marked as finished."
    case .libraryDepthAuthors:
      return "Distinct authors you have listened to."
    }
  }

  private var thresholdsDescription: String {
    let parts = thresholds.enumerated().map { index, threshold in
      "Level \(index + 1): \(formattedThreshold(threshold))"
    }
    return parts.joined(separator: "\n")
  }

  func alertMessage(for state: ListeningAchievementState) -> String {
    let progress: String
    switch state.tier {
    case .locked:
      progress = "Not unlocked yet. \(formattedValue(state.currentValue))"
    case .level5:
      progress = formattedValue(state.currentValue)
    default:
      progress = "\(state.tier.accessibilityLabel). \(state.valueLine)"
    }
    return "\(explanation)\n\n\(thresholdsDescription)\n\n\(progress)"
  }
}

struct ListeningAchievementState: Identifiable, Codable, Equatable {
  let kind: ListeningAchievementKind
  let currentValue: Int

  var id: String { kind.id }
  var tier: ListeningAchievementTier { kind.tier(for: currentValue) }
  var nextThreshold: Int? { kind.nextThreshold(after: currentValue) }
  var progressToNext: Double { kind.progressFraction(toward: currentValue) }

  var valueLine: String {
    if let next = nextThreshold {
      return "\(kind.formattedValue(currentValue)) / \(kind.formattedThreshold(next))"
    }
    return kind.formattedValue(currentValue)
  }
}

/// Werte aus Listening-Stats + lokalem Fortschritt für fertige Titel (Disk-Cache).
struct ListeningAchievementsSnapshot: Codable, Equatable {
  let achievements: [ListeningAchievementState]
  var savedAt: Date?

  static let empty = ListeningAchievementsSnapshot(
    achievements: ListeningAchievementKind.allCases.map {
      ListeningAchievementState(kind: $0, currentValue: 0)
    },
    savedAt: nil
  )

  static func make(
    stats: ABSListeningStatsResponse,
    calendar: Calendar,
    finishedBooks: Int,
    finishedEpisodes: Int
  ) -> ListeningAchievementsSnapshot {
    let listeningHours = max(0, stats.totalTime / 3600)
    let values: [ListeningAchievementKind: Int] = [
      .longestStreak: stats.bestListeningStreakDays(calendar: calendar),
      .currentStreak: stats.currentListeningStreakDays(calendar: calendar),
      .listeningTimeHours: listeningHours,
      .activeDays: stats.daysActive,
      .marathonDay: stats.marathonDayListeningSeconds,
      .finishedBooks: finishedBooks,
      .finishedEpisodes: finishedEpisodes,
      .libraryDepthAuthors: stats.distinctListenedAuthorCount,
    ]
    let list = ListeningAchievementKind.allCases.map { kind in
      ListeningAchievementState(kind: kind, currentValue: values[kind, default: 0])
    }
    return ListeningAchievementsSnapshot(achievements: list, savedAt: Date())
  }
}

struct ListeningAchievementCard: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let achievement: ListeningAchievementState
  /// Zwei Karten pro Zeile (Stats Level).
  var compact: Bool = false

  @State private var showExplanation = false

  private static let iconSlotWidth: CGFloat = 28
  private static let compactIconSlotWidth: CGFloat = 22
  private static let rowSpacing: CGFloat = 12
  private static let compactRowSpacing: CGFloat = 8
  private static let progressBarHeight = AppTheme.Layout.libraryRowBottomProgressHeight
  private static let compactInset: CGFloat = 10
  private static let compactBadgeEdge: CGFloat = 28

  var body: some View {
    Button {
      showExplanation = true
    } label: {
      cardBody
    }
    .buttonStyle(.plain)
    .frame(maxHeight: compact ? .infinity : nil)
    .accessibilityLabel(
      "\(achievement.kind.title), \(achievement.valueLine), \(achievement.tier.accessibilityLabel)")
    .accessibilityHint("Shows how levels work for this achievement.")
    .alert(achievement.kind.title, isPresented: $showExplanation) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(achievement.kind.alertMessage(for: achievement))
    }
  }

  private var progressBarValue: Double {
    achievement.tier == .level5 ? 1 : achievement.progressToNext
  }

  private var tierAccentColor: Color {
    let _ = themeRevision
    return achievement.tier.adaptiveTint(
      accent: themeAccent,
      palette: model.appearancePalette
    )
  }

  @ViewBuilder
  private var cardBody: some View {
    if compact {
      compactCardBody
    } else {
      regularCardBody
    }
  }

  private var regularCardBody: some View {
    let palette = model.appearancePalette
    let contentBottom = 14 + Self.progressBarHeight
    return VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: Self.rowSpacing) {
        achievementIcon(size: 21, slotWidth: Self.iconSlotWidth)

        VStack(alignment: .leading, spacing: 2) {
          Text(achievement.kind.title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)

          Text(achievement.valueLine)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        levelBadge(edge: 36, levelFont: .title3.weight(.bold), cornerRadius: 10)
      }
      .padding(.horizontal, 14)
      .padding(.top, 14)
      .padding(.bottom, contentBottom)
    }
    .overlay(alignment: .bottom) {
      bottomProgressSlot
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }

  private var compactCardBody: some View {
    let palette = model.appearancePalette
    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: Self.compactRowSpacing) {
        HStack(alignment: .top, spacing: Self.compactRowSpacing) {
          achievementIcon(size: 17, slotWidth: Self.compactIconSlotWidth)
          Spacer(minLength: 0)
          levelBadge(edge: Self.compactBadgeEdge, levelFont: .headline.weight(.bold), cornerRadius: 8)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(achievement.kind.title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(palette.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .topLeading)

          Text(achievement.valueLine)
            .font(.caption.monospacedDigit())
            .foregroundStyle(palette.textSecondary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }
      .padding(Self.compactInset)

      Spacer(minLength: 0)

      bottomProgressSlot
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(palette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.cardCornerRadius, style: .continuous))
    .abstandCardElevation(.standard)
  }

  private var bottomProgressSlot: some View {
    AbstandCardBottomProgress(value: progressBarValue)
    .frame(height: Self.progressBarHeight)
    .allowsHitTesting(false)
  }

  private func achievementIcon(size: CGFloat, slotWidth: CGFloat) -> some View {
    Image(systemName: achievement.kind.systemImage)
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(tierAccentColor)
      .frame(width: slotWidth, alignment: .center)
  }

  @ViewBuilder
  private func levelBadge(edge: CGFloat, levelFont: Font, cornerRadius: CGFloat) -> some View {
    let palette = model.appearancePalette
    let tier = achievement.tier
    let isSolid = tier.usesSolidBadgeFill
    let fillOpacity = tier.badgeFillOpacity(isDarkLike: palette.isDarkLike)
    if let level = tier.levelNumber {
      Text("\(level)")
        .font(levelFont)
        .monospacedDigit()
        .foregroundStyle(isSolid ? palette.foregroundOnAccent(themeAccent) : tierAccentColor)
        .frame(width: edge, height: edge)
        .background(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tierAccentColor.opacity(fillOpacity))
        )
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(tierAccentColor, lineWidth: isSolid ? 0 : 1.5)
        }
        .accessibilityLabel(tier.accessibilityLabel)
    } else {
      Image(systemName: "lock.fill")
        .font(levelFont)
        .foregroundStyle(tierAccentColor)
        .frame(width: edge, height: edge)
        .accessibilityLabel(tier.accessibilityLabel)
    }
  }

}
