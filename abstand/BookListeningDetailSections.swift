import SwiftUI

private enum SessionRangeBarMetrics {
  /// Höhe des kleinen Fortschrittsbalkens (Sitzungs-Zeitraum in der Kapitel-/Sitzungsliste).
  static let barHeight: CGFloat = 7
}

enum ListeningHistoryDateFormatting {
  static let sessionList: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()
}

struct ListeningHistoryRow: View {
  @Environment(\.appearanceThemeRevision) private var themeRevision
  @Environment(\.themeAccent) private var themeAccent
  let session: ABSListeningSession
  let onJump: (ABSListeningSession) -> Void

  var body: some View {
    // Statische AppTheme-Farben neu binden, ohne die Zeile an AppModel zu koppeln.
    let _ = themeRevision
    let denom = max(session.duration, session.currentTime, session.startTime, 1)
    let rel0 = CGFloat(session.startTime / denom)
    let rel1 = CGFloat(session.currentTime / denom)
    let started = Date(timeIntervalSince1970: Double(session.startedAt) / 1000)
    VStack(alignment: .leading, spacing: AppTheme.Layout.stackSpacing) {
      HStack(alignment: .center, spacing: AppTheme.Layout.withinSectionSpacing) {
        VStack(alignment: .leading, spacing: AppTheme.Layout.hairlineSpacing) {
          Text(ListeningHistoryDateFormatting.sessionList.string(from: started))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
          Text(
            "Listened \(formatPlaybackTime(Double(session.timeListening))) · \(formatPlaybackTime(session.startTime)) → \(formatPlaybackTime(session.currentTime))"
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(AppTheme.textSecondary)
        }
        Spacer(minLength: AppTheme.Layout.stackSpacing)
        Button {
          onJump(session)
        } label: {
          Image(systemName: "arrow.counterclockwise.circle.fill")
            .font(.title2)
            .abstandAccentForeground()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to this session")
      }
      GeometryReader { geo in
        let w = geo.size.width
        let x0 = min(max(rel0 * w, 0), w)
        let x1 = min(max(rel1 * w, x0 + 2), w)
        ZStack(alignment: .leading) {
          Capsule()
            .fill(AppTheme.card)
          Capsule()
            .fill(themeAccent.opacity(0.88))
            .frame(width: x1 - x0)
            .offset(x: x0)
        }
      }
      .frame(height: SessionRangeBarMetrics.barHeight)
    }
    .padding(.vertical, AppTheme.Layout.tightSpacing)
  }
}

/// Sessions-Liste (Book Detail + Vollplayer-Cover-Panel).
struct ListeningHistorySessionList: View {
  let sessions: [ABSListeningSession]
  let isNetworkReachable: Bool
  let emptyOnlineText: String
  let emptyOfflineText: String
  let onJumpToSessionStart: (ABSListeningSession) -> Void

  var body: some View {
    Group {
      if sessions.isEmpty {
        Text(isNetworkReachable ? emptyOnlineText : emptyOfflineText)
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, AppTheme.Layout.compactSpacing)
      } else {
        VStack(alignment: .leading, spacing: AppTheme.Layout.cardPadding) {
          ForEach(sessions) { session in
            ListeningHistoryRow(session: session, onJump: onJumpToSessionStart)
          }
        }
      }
    }
  }
}

enum BookChapterPlayState {
  case notStarted
  case inProgress
  case completed

  static func resolve(chapter: ABSChapter, progress: ABSUserMediaProgress?) -> BookChapterPlayState {
    if progress?.isFinished == true { return .completed }
    let t = progress?.currentTime ?? 0
    let eps = 0.75
    if t + eps >= chapter.end { return .completed }
    if t + eps >= chapter.start { return .inProgress }
    return .notStarted
  }
}

struct BookChapterRowView: View {
  @Environment(\.appearanceThemeRevision) private var themeRevision
  @Environment(\.themeAccent) private var themeAccent
  let chapter: ABSChapter
  let playState: BookChapterPlayState
  let onPlay: () -> Void

  var body: some View {
    // Statische AppTheme-Farben neu binden, ohne die Zeile an AppModel zu koppeln.
    let _ = themeRevision
    Button(action: onPlay) {
      HStack(alignment: .top, spacing: AppTheme.Layout.withinSectionSpacing) {
        VStack(alignment: .leading, spacing: AppTheme.Layout.tightSpacing) {
          Text(chapter.title)
            .font(.headline)
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
          Text("\(formatPlaybackTime(chapter.start)) – \(formatPlaybackTime(chapter.end))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
        }
        Spacer(minLength: AppTheme.Layout.stackSpacing)
        chapterStatusIcon
        Image(systemName: "play.circle")
          .font(.title3)
          .abstandAccentForeground()
      }
      .padding(.vertical, AppTheme.Layout.withinSectionSpacing)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Play from chapter \(chapter.title)")
  }

  @ViewBuilder
  private var chapterStatusIcon: some View {
    switch playState {
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .abstandAccentForeground()
        .font(.body)
    case .inProgress:
      Image(systemName: "play.circle.fill")
        .abstandAccentForeground()
        .font(.body)
    case .notStarted:
      EmptyView()
    }
  }
}

/// Buchbeschreibung (Book Detail + Vollplayer-Panel) — Typografie wie DetailHeroTypography.metaValue.
struct BookDescriptionPanelView: View {
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let text: String

  var body: some View {
    // Statische AppTheme-Farben neu binden, ohne die Zeile an AppModel zu koppeln.
    let _ = themeRevision
    Group {
      if text.isEmpty {
        Text("—")
          .font(.body)
          .foregroundStyle(AppTheme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text(text)
          .font(.body)
          .foregroundStyle(AppTheme.textPrimary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

/// Kapitelliste (Book Detail + Vollplayer-Cover-Panel).
struct BookChapterListView: View {
  @Environment(\.appearanceThemeRevision) private var themeRevision
  let book: ABSBook
  let progress: ABSUserMediaProgress?
  let onPlayChapter: (ABSChapter) -> Void

  var body: some View {
    // Statische AppTheme-Farben neu binden, ohne die Zeile an AppModel zu koppeln.
    let _ = themeRevision
    let chapters = (book.media.chapters ?? []).sorted { $0.start < $1.start }
    Group {
      if chapters.isEmpty {
        AbstandSectionEmptyState(text: "No chapters available.")
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, chapter in
            BookChapterRowView(
              chapter: chapter,
              playState: BookChapterPlayState.resolve(chapter: chapter, progress: progress)
            ) {
              onPlayChapter(chapter)
            }
            if idx < chapters.count - 1 {
              Divider().background(AppTheme.textSecondary.opacity(0.15))
            }
          }
        }
      }
    }
  }
}
