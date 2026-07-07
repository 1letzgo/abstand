import SwiftUI

struct LoginView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  /// Sheet-Modus: weiteren Account hinzufügen (Felder leer, nach Erfolg schließen).
  var addAccountMode: Bool = false
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
            Text(addAccountMode ? "Add account" : "Abstand")
              .font(.largeTitle.bold())
              .foregroundStyle(model.appearancePalette.textPrimary)
            if !addAccountMode {
              Text("Audiobookshelf")
                .font(.title3.weight(.semibold))
                .abstandAccentForeground()
            }
            Text(
              addAccountMode
                ? "Sign in with another Audiobookshelf account."
                : "Sign in with your Audiobookshelf account."
            )
            .font(.subheadline)
            .foregroundStyle(model.appearancePalette.textSecondary)
          }

          VStack(spacing: 14) {
            AbstandLabeledTextField(title: "Server URL", text: $server)
            AbstandLabeledTextField(title: "Username", text: $username)
            AbstandLabeledTextField(title: "Password", text: $password, isSecure: true)
          }
          .onAppear {
            if addAccountMode {
              server = ""
              username = ""
              password = ""
            } else if server.isEmpty {
              server = model.serverURL
            }
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
              if addAccountMode {
                let ok = await model.addStoredAccount(
                  server: server, username: username, password: password)
                if ok { dismiss() }
              } else {
                await model.login(server: server, username: username, password: password)
              }
            }
          } label: {
            HStack(spacing: 8) {
              if busy { ProgressView().tint(Color.black.opacity(0.85)) }
              Text(addAccountMode ? "Add account" : "Sign in")
            }
          }
          .buttonStyle(AbstandPrimaryButtonStyle())
          .disabled(busy || server.isEmpty || username.isEmpty || password.isEmpty)
        }
        .padding(24)
        .frame(maxWidth: AppTheme.Layout.readableFormMaxWidth)
        .frame(maxWidth: .infinity)
      }
      .abstandScrollScreenBackground()
      .refreshable {
        if !addAccountMode {
          await model.bootstrapFromStoredCredentials()
        }
      }
    }
    .abstandThemeRefresh()
  }
}
