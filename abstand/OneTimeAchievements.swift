import SwiftUI

/// Einmal-Achievements (ohne Level-Stufen), Kacheln 1–8.
enum OneTimeAchievementKind: String, Codable, CaseIterable, Identifiable {
  case firstListen
  case firstBookFinished
  case firstEpisodeFinished
  case firstDownload
  case firstBookmark
  case sleepTimerUsed
  case fasterPlayback
  case oneHourListened

  var id: String { rawValue }

  var title: String {
    switch self {
    case .firstListen: return "First listen"
    case .firstBookFinished: return "First book"
    case .firstEpisodeFinished: return "First episode"
    case .firstDownload: return "First download"
    case .firstBookmark: return "First bookmark"
    case .sleepTimerUsed: return "Sleep timer"
    case .fasterPlayback: return "Faster playback"
    case .oneHourListened: return "First hour"
    }
  }

  var systemImage: String {
    switch self {
    case .firstListen: return "play.circle.fill"
    case .firstBookFinished: return "book.fill"
    case .firstEpisodeFinished: return "mic.fill"
    case .firstDownload: return "arrow.down.circle.fill"
    case .firstBookmark: return "bookmark.fill"
    case .sleepTimerUsed: return "moon.fill"
    case .fasterPlayback: return "gauge.with.dots.needle.67percent"
    case .oneHourListened: return "clock.fill"
    }
  }

  /// Erklärung für das Info-Popup.
  var explanation: String {
    switch self {
    case .firstListen:
      return "Start playback of any audiobook or podcast episode."
    case .firstBookFinished:
      return "Mark an audiobook as finished in the library or player."
    case .firstEpisodeFinished:
      return "Mark a podcast episode as finished."
    case .firstDownload:
      return "Download at least one title for offline listening."
    case .firstBookmark:
      return "Create a bookmark while listening."
    case .sleepTimerUsed:
      return "Set a sleep timer from the player (minutes or chapters)."
    case .fasterPlayback:
      return "Play audio faster than 1× speed."
    case .oneHourListened:
      return "Reach one hour of total listening time on this server account."
    }
  }

  func alertMessage(unlocked: Bool) -> String {
    let status = unlocked ? "Unlocked on this account." : "Not unlocked yet."
    return "\(explanation)\n\n\(status)"
  }
}

struct OneTimeAchievementState: Identifiable, Codable, Equatable {
  let kind: OneTimeAchievementKind
  let isUnlocked: Bool

  var id: String { kind.id }
}

struct ListeningOneTimeAchievementsSnapshot: Codable, Equatable {
  let achievements: [OneTimeAchievementState]
  var savedAt: Date?

  static let empty = ListeningOneTimeAchievementsSnapshot(
    achievements: OneTimeAchievementKind.allCases.map {
      OneTimeAchievementState(kind: $0, isUnlocked: false)
    },
    savedAt: nil
  )

  static func make(
    stats: ABSListeningStatsResponse,
    finishedBooks: Int,
    finishedEpisodes: Int,
    downloadedItemCount: Int,
    bookmarkCount: Int,
    flags: OneTimeAchievementPersistentFlags
  ) -> ListeningOneTimeAchievementsSnapshot {
    let unlocked: [OneTimeAchievementKind: Bool] = [
      .firstListen: stats.totalTime > 0,
      .firstBookFinished: finishedBooks >= 1,
      .firstEpisodeFinished: finishedEpisodes >= 1,
      .firstDownload: downloadedItemCount >= 1,
      .firstBookmark: bookmarkCount >= 1,
      .sleepTimerUsed: flags.sleepTimerUsed,
      .fasterPlayback: flags.fasterPlaybackUsed,
      .oneHourListened: stats.totalTime >= 3600,
    ]
    let list = OneTimeAchievementKind.allCases.map { kind in
      OneTimeAchievementState(kind: kind, isUnlocked: unlocked[kind, default: false])
    }
    return ListeningOneTimeAchievementsSnapshot(achievements: list, savedAt: Date())
  }
}

/// Persistent „einmal erlebt“-Flags (UserDefaults).
struct OneTimeAchievementPersistentFlags: Codable, Equatable {
  var sleepTimerUsed: Bool
  var fasterPlaybackUsed: Bool

  static func load() -> OneTimeAchievementPersistentFlags {
    let d = UserDefaults.standard
    return OneTimeAchievementPersistentFlags(
      sleepTimerUsed: d.bool(forKey: sleepTimerKey),
      fasterPlaybackUsed: d.bool(forKey: fasterPlaybackKey)
    )
  }

  private static let sleepTimerKey = "abstand_one_time_sleep_timer"
  private static let fasterPlaybackKey = "abstand_one_time_fast_playback"

  static func markSleepTimerUsed() {
    UserDefaults.standard.set(true, forKey: sleepTimerKey)
  }

  static func markFasterPlaybackUsed() {
    UserDefaults.standard.set(true, forKey: fasterPlaybackKey)
  }
}

struct OneTimeAchievementCard: View {
  @EnvironmentObject private var model: AppModel
  let achievement: OneTimeAchievementState

  @State private var showExplanation = false

  var body: some View {
    Button {
      showExplanation = true
    } label: {
      cardBody
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      achievement.isUnlocked
        ? "\(achievement.kind.title), unlocked"
        : "\(achievement.kind.title), locked")
    .accessibilityHint("Shows how to unlock this achievement.")
    .alert(achievement.kind.title, isPresented: $showExplanation) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(achievement.kind.alertMessage(unlocked: achievement.isUnlocked))
    }
  }

  private var cardBody: some View {
    VStack(alignment: .center, spacing: 6) {
      RoundedRectangle(cornerRadius: AppTheme.Layout.podcastShelfCoverCorner, style: .continuous)
        .fill(AppTheme.card)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .overlay {
          Image(systemName: achievement.kind.systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(
              achievement.isUnlocked
                ? model.appearanceAccentColor : AppTheme.textSecondary.opacity(0.4))
        }
        .overlay(alignment: .topTrailing) {
          if !achievement.isUnlocked {
            Image(systemName: "lock.fill")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
              .padding(6)
          }
        }
      Text(achievement.kind.title)
        .font(.caption2.weight(.medium))
        .foregroundStyle(achievement.isUnlocked ? AppTheme.textPrimary : AppTheme.textSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity)
    }
    .accessibilityElement(children: .ignore)
  }
}
