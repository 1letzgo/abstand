import SwiftUI

/// Editor für Custom-Header eines Servers (wie stashy): je Zeile Name + Wert (verdeckt),
/// Entfernen-Button, „Add header“ und Hinweis. Ungültige Zeilen werden beim Speichern verworfen,
/// angefangene zeigen ihren Fehler direkt darunter.
struct ServerCustomHeadersEditor: View {
  @EnvironmentObject private var model: AppModel
  @Binding var headers: [ServerHTTPHeader]

  var body: some View {
    let palette = model.appearancePalette
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      ForEach($headers) { $header in
        HStack(alignment: .top, spacing: AppTheme.Layout.inlineSpacing) {
          VStack(alignment: .leading, spacing: AppTheme.Layout.stackSpacing) {
            headerField("Header name", text: $header.name, isSecure: false)
              .font(.body.monospaced())
            headerField("Value", text: $header.value, isSecure: true)
            if let problem = problem(for: header) {
              Text(problem)
                .font(.caption)
                .foregroundStyle(AppTheme.danger)
            }
          }
          Button {
            withAnimation(.snappy(duration: 0.25)) {
              headers.removeAll { $0.id == header.id }
            }
          } label: {
            Image(systemName: "minus.circle.fill")
              .font(.title3)
              .foregroundStyle(AppTheme.danger)
              .frame(width: AppTheme.Layout.minTapTarget, height: AppTheme.Layout.minTapTarget)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove header")
        }
        .transition(.opacity)
      }

      Button {
        withAnimation(.snappy(duration: 0.25)) {
          headers.append(ServerHTTPHeader(name: "", value: ""))
        }
      } label: {
        Label("Add header", systemImage: "plus.circle.fill")
          .font(.body.weight(.medium))
          .foregroundStyle(model.appearanceAccentColor)
      }
      .buttonStyle(.plain)

      Text(
        "Sent with every request to this server, e.g. for SSO or a reverse proxy that needs its own token. Stored in the Keychain."
      )
      .font(.footnote)
      .foregroundStyle(palette.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func headerField(_ placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
    let palette = model.appearancePalette
    return Group {
      if isSecure {
        SecureField(placeholder, text: text)
      } else {
        TextField(placeholder, text: text)
      }
    }
    .textInputAutocapitalization(.never)
    .autocorrectionDisabled()
    .padding(AppTheme.Layout.rowSpacing)
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(palette.textPrimary)
    .background(palette.card)
    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Layout.fieldCornerRadius, style: .continuous))
  }

  /// Nur für begonnene Zeilen; leere Zeilen werden beim Speichern einfach ignoriert.
  private func problem(for header: ServerHTTPHeader) -> String? {
    let name = header.trimmedName
    guard !name.isEmpty || !header.trimmedValue.isEmpty else { return nil }
    if name.isEmpty { return "Enter a header name." }
    if ServerHTTPHeader.reservedNames.contains(name.lowercased()) {
      return "\(name) is managed by the app and can't be set."
    }
    if header.trimmedValue.isEmpty { return "Enter a value." }
    if !header.isUsable {
      return "Header names may only contain letters, digits and - _ . ! # $ % & ' * + ^ ` | ~"
    }
    return nil
  }
}

/// Einklappbare Custom-Header-Karte für Login / „Add account“ — standardmäßig zu, die meisten
/// Server brauchen keine zusätzlichen Header.
struct ServerCustomHeadersDisclosure: View {
  @EnvironmentObject private var model: AppModel
  @Binding var headers: [ServerHTTPHeader]
  @State private var isExpanded = false

  var body: some View {
    let palette = model.appearancePalette
    let usableCount = ServerHTTPHeader.sanitized(headers).count
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      Button {
        isExpanded.toggle()
      } label: {
        HStack(spacing: AppTheme.Layout.compactSpacing) {
          Text("Custom headers")
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.textSecondary)
          if usableCount > 0 {
            Text("\(usableCount)")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(palette.textSecondary)
          }
          Spacer(minLength: 0)
          // Ein Symbol, gedreht — ein Symbolwechsel „springt“ statt mitzulaufen.
          Image(systemName: "chevron.down")
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Custom headers")
      .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

      if isExpanded {
        ServerCustomHeadersEditor(headers: $headers)
          // Nur einblenden: ein „move“ würde die Felder über die Klappzeile schieben.
          .transition(.opacity)
      }
    }
    // Eine gemeinsame Animation für Höhe, Einblenden und Chevron — statt `withAnimation` am Tap,
    // das den umgebenden ScrollView ruckartig nachzieht. Clip verhindert Überlappen beim Zuklappen.
    .animation(.snappy(duration: 0.28), value: isExpanded)
    .clipped()
    // Schon gespeicherte Header sofort sichtbar machen, statt sie hinter der Klappe zu verstecken.
    .onAppear { if usableCount > 0 { isExpanded = true } }
  }
}
