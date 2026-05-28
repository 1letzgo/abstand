import SwiftUI

struct LoginView: View {
  @EnvironmentObject private var model: AppModel
  @State private var server = ""
  @State private var username = ""
  @State private var password = ""
  @State private var busy = false

  var body: some View {
    ZStack {
      AppTheme.background.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("Abstand")
            .font(.largeTitle.bold())
            .foregroundStyle(AppTheme.textPrimary)
          Text("Audiobookshelf")
            .font(.title3)
            .foregroundStyle(Color.accentColor)
          Text("Sign in with your Audiobookshelf account.")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)

          VStack(spacing: 14) {
            labeledField("Server URL", text: $server, secure: false)
            labeledField("Username", text: $username, secure: false)
            labeledField("Password", text: $password, secure: true)
          }
          .onAppear {
            if server.isEmpty { server = model.serverURL }
          }

          if let err = model.errorMessage {
            Text(err)
              .font(.footnote)
              .foregroundStyle(AppTheme.danger)
          }

          Button {
            Task {
              busy = true
              defer { busy = false }
              await model.login(server: server, username: username, password: password)
            }
          } label: {
            HStack {
              if busy { ProgressView().tint(.white) }
              Text("Sign in")
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor)
            .foregroundStyle(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
          .disabled(busy || server.isEmpty || username.isEmpty || password.isEmpty)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
      }
      .abstandScrollScreenBackground()
      .refreshable {
        await model.bootstrapFromStoredCredentials()
      }
    }
  }

  private func labeledField(
    _ title: String,
    text: Binding<String>,
    secure: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)
      Group {
        if secure {
          SecureField("", text: text)
        } else {
          TextField("", text: text)
        }
      }
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .padding(12)
      .background(AppTheme.card)
      .foregroundStyle(AppTheme.textPrimary)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
  }
}
