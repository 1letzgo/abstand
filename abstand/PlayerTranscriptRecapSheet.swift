import SwiftUI

/// Ergebnis der lokalen Recap-Transkription innerhalb der Vollplayer-Cover-Karte.
struct PlayerTranscriptRecapCard: View {
  @ObservedObject var transcription: PlayerLiveTranscriptionController

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(String(localized: "Last 5 minutes", comment: "Read along recap title"))
        .font(.headline)
        .foregroundStyle(AppTheme.textPrimary)

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
        } else if let error = transcription.recapErrorMessage {
          ContentUnavailableView(
            String(localized: "Recap unavailable", comment: "Read along recap empty title"),
            systemImage: "sparkles",
            description: Text(error)
          )
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
