import SwiftUI

/// Ergebnis der lokalen Recap-Transkription innerhalb der Vollplayer-Cover-Karte.
struct PlayerTranscriptRecapCard: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject var transcription: PlayerLiveTranscriptionController

  var body: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.stackSpacing) {
      HStack(alignment: .firstTextBaseline, spacing: AppTheme.Layout.compactSpacing) {
        Text(String(localized: "Last 5 minutes", comment: "Read along recap title"))
          .font(DetailHeroTypography.metaLabel)
          .foregroundStyle(model.appearancePalette.textSecondary)
        if transcription.recapShowsTranscript {
          Text(String(localized: "transcript", comment: "Read along recap transcript badge"))
            .font(.caption2.weight(.medium))
            .foregroundStyle(model.appearancePalette.textSecondary)
            .padding(.horizontal, AppTheme.Layout.compactSpacing)
            .padding(.vertical, AppTheme.Layout.hairlineSpacing)
            .background(model.appearancePalette.card.opacity(0.9), in: Capsule())
        }
      }

      Group {
        if transcription.isGeneratingRecap {
          AbstandLabeledLoadingState(
            text: String(localized: "Creating on-device recap…", comment: "Read along recap progress")
          )
        } else if let recap = transcription.recapText, !recap.isEmpty {
          ScrollView {
            Text(recap)
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
          }
          if let notice = transcription.recapFallbackNotice {
            Text(notice)
              .font(.caption)
              .foregroundStyle(model.appearancePalette.textSecondary)
              .lineLimit(2)
              .padding(AppTheme.Layout.withinSectionSpacing)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(model.appearancePalette.card.opacity(0.9))
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
              .foregroundStyle(model.appearancePalette.textSecondary)
              .lineLimit(2)
              .padding(AppTheme.Layout.withinSectionSpacing)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(model.appearancePalette.card.opacity(0.9))
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
