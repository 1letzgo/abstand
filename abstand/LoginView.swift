import SwiftUI

struct LoginView: View {
  @EnvironmentObject private var model: AppModel
  @State private var server = ""
  @State private var username = ""
  @State private var password = ""
  @State private var busy = false

  var body: some View {
    ZStack {
      AppThemeScreenBackground(ignoresSafeArea: true)
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Abstand")
              .font(.largeTitle.bold())
              .foregroundStyle(model.appearancePalette.textPrimary)
            Text("Audiobookshelf")
              .font(.title3.weight(.semibold))
              .abstandAccentForeground()
            Text("Sign in with your Audiobookshelf account.")
              .font(.subheadline)
              .foregroundStyle(model.appearancePalette.textSecondary)
          }

          VStack(spacing: 14) {
            AbstandLabeledTextField(title: "Server URL", text: $server)
            AbstandLabeledTextField(title: "Username", text: $username)
            AbstandLabeledTextField(title: "Password", text: $password, isSecure: true)
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
            HStack(spacing: 8) {
              if busy { ProgressView().tint(Color.black.opacity(0.85)) }
              Text("Sign in")
            }
          }
          .buttonStyle(AbstandPrimaryButtonStyle())
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
    .abstandThemeRefresh()
  }
}
