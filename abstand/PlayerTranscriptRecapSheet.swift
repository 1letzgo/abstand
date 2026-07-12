import SwiftUI

/// Ergebnis der ausschließlich lokalen Zusammenfassung des Read-along-Transkripts.
struct PlayerTranscriptRecapSheet: View {
  @ObservedObject var transcription: PlayerLiveTranscriptionController
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
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
              .padding(AppTheme.Layout.tabPaddingH)
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
      .padding(transcription.isGeneratingRecap ? AppTheme.Layout.tabPaddingH : 0)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(AppTheme.background)
      .navigationTitle(String(localized: "Last 5 minutes", comment: "Read along recap title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "Done", comment: "Dismiss sheet")) {
            dismiss()
          }
        }
      }
    }
  }
}
