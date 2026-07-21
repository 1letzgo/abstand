import SwiftUI

/// Ergebnis der lokalen Recap-Transkription innerhalb der Vollplayer-Cover-Karte.
struct PlayerTranscriptRecapCard: View {
  @ObservedObject var transcription: PlayerLiveTranscriptionController

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(String(localized: "Last 5 minutes", comment: "Read along recap title"))
          .font(.caption.weight(.bold))
          .foregroundStyle(AppTheme.textSecondary)
          .textCase(.uppercase)
          .tracking(0.6)
        if transcription.recapShowsTranscript {
          Text(String(localized: "transcript", comment: "Read along recap transcript badge"))
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppTheme.card.opacity(0.9), in: Capsule())
        }
      }

      Group {
        if transcription.isGeneratingRecap {
          VStack(spacing: 12) {
            ProgressView()
            Text(String(localized: "Creating on-device recap…", comment: "Read along recap progress"))
              .foregroundStyle(AppTheme.textSecondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let recap = transcription.recapText, !recap.isEmpty {
          ScrollView {
            Text(recap)
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
          }
          if let notice = transcription.recapFallbackNotice {
            Text(notice)
              .font(.caption)
              .foregroundStyle(AppTheme.textSecondary)
              .lineLimit(2)
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(AppTheme.card.opacity(0.9))
          }
        } else if let error = transcription.recapErrorMessage {
          ContentUnavailableView(
            String(localized: "Recap unavailable", comment: "Read along recap empty title"),
            systemImage: "sparkles",
            description: Text(error)
          )
          if let notice = transcription.recapFallbackNotice {
            Text(notice)
              .font(.caption)
              .foregroundStyle(AppTheme.textSecondary)
              .lineLimit(2)
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(AppTheme.card.opacity(0.9))
          }
        } else {
          ContentUnavailableView(
            String(localized: "No recap yet", comment: "Read along recap empty title"),
            systemImage: "sparkles",
            description: Text(
              String(
                localized: "Listen a little longer, then try creating a recap again.",
                comment: "Read along recap empty description"
              )
            )
          )
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
