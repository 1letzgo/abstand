import SwiftUI
import Translation
import UIKit

// MARK: - Model

struct PlayerTranscriptWordLookupSelection: Identifiable, Equatable {
  let word: PlayerTranscriptWord
  let term: String

  var id: String { word.id }
}

enum PlayerTranscriptWordLookup {
  /// `Locale` der Transkription → `Locale.Language` für das Translation-Framework.
  static func translationLanguage(from locale: Locale) -> Locale.Language {
    if let code = locale.language.languageCode?.identifier, !code.isEmpty {
      return Locale.Language(identifier: code)
    }
    return Locale.Language(identifier: locale.identifier(.bcp47))
  }

  static func localizedLanguageName(for locale: Locale) -> String {
    let code = locale.language.languageCode?.identifier ?? locale.identifier(.bcp47)
    return Locale.current.localizedString(forLanguageCode: code) ?? code
  }

  /// Lemma für Wörterbuch / Übersetzung (ohne Rand-Interpunktion).
  static func normalizedTerm(from raw: String) -> String {
    var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while let first = t.unicodeScalars.first, CharacterSet.punctuationCharacters.contains(first) {
      t.removeFirst()
    }
    while let last = t.unicodeScalars.last, CharacterSet.punctuationCharacters.contains(last) {
      t.removeLast()
    }
    return t.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func hasDictionaryDefinition(for term: String) -> Bool {
    let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return false }
    return UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: t)
  }
}

// MARK: - Sheet

struct PlayerTranscriptWordLookupSheet: View {
  let selection: PlayerTranscriptWordLookupSelection
  let sourceLocale: Locale?
  @Environment(\.dismiss) private var dismiss

  @State private var showDictionary = false
  @State private var translationConfiguration: TranslationSession.Configuration?
  @State private var translatedText: String?
  @State private var translationError: String?
  @State private var isTranslating = false

  private let dictionaryAvailable: Bool
  private let sourceLanguage: Locale.Language?
  private let targetLanguage: Locale.Language

  init(selection: PlayerTranscriptWordLookupSelection, sourceLocale: Locale?) {
    self.selection = selection
    self.sourceLocale = sourceLocale
    dictionaryAvailable = PlayerTranscriptWordLookup.hasDictionaryDefinition(for: selection.term)
    sourceLanguage = sourceLocale.map(PlayerTranscriptWordLookup.translationLanguage(from:))
    targetLanguage = Locale.current.language
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
        Text(selection.term)
          .font(.title2.weight(.bold))
          .foregroundStyle(AppTheme.textPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)

        if let sourceLocale {
          Text(
            String(
              format: String(
                localized: "Transcript language: %@",
                comment: "Teleprompter word lookup source language"
              ),
              PlayerTranscriptWordLookup.localizedLanguageName(for: sourceLocale)
            )
          )
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
        }

        VStack(spacing: 10) {
          if dictionaryAvailable {
            lookupActionButton(
              icon: "character.book.closed",
              title: String(localized: "Look up definition", comment: "Teleprompter word lookup")
            ) {
              showDictionary = true
            }
          }
          lookupActionButton(
            icon: "translate",
            title: String(localized: "Translate", comment: "Teleprompter word lookup")
          ) {
            requestTranslation()
          }
        }

        if isTranslating {
          HStack(spacing: 10) {
            ProgressView()
              .controlSize(.small)
            Text(String(localized: "Translating…", comment: "Teleprompter word lookup"))
              .font(.subheadline)
              .foregroundStyle(AppTheme.textSecondary)
          }
          .padding(.top, 4)
        }

        if let translatedText {
          VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Translation", comment: "Teleprompter word lookup result label"))
              .font(.caption.weight(.bold))
              .foregroundStyle(AppTheme.textSecondary)
              .textCase(.uppercase)
            Text(translatedText)
              .font(.body)
              .foregroundStyle(AppTheme.textPrimary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(14)
          .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }

        if let translationError {
          Text(translationError)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
        }

        if !dictionaryAvailable, translatedText == nil, !isTranslating {
          Text(
            String(
              localized: "No dictionary entry on this device for this word.",
              comment: "Teleprompter word lookup hint"
            )
          )
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
        }

        Spacer(minLength: 0)
      }
      .padding(AppTheme.Layout.tabPaddingH)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(AppTheme.background)
      .navigationTitle(String(localized: "Word", comment: "Teleprompter word lookup title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "Done", comment: "Dismiss sheet")) {
            dismiss()
          }
        }
      }
    }
    .sheet(isPresented: $showDictionary) {
      DictionaryReferenceView(term: selection.term)
        .ignoresSafeArea()
    }
    .translationTask(translationConfiguration) { session in
      do {
        let response = try await session.translate(selection.term)
        translatedText = response.targetText
        translationError = nil
      } catch {
        translatedText = nil
        translationError = error.localizedDescription
      }
      isTranslating = false
    }
  }

  private func requestTranslation() {
    translatedText = nil
    translationError = nil
    isTranslating = true
    var config = TranslationSession.Configuration(
      source: sourceLanguage,
      target: targetLanguage
    )
    if translationConfiguration != nil {
      config.invalidate()
    }
    translationConfiguration = config
  }

  private func lookupActionButton(
    icon: String,
    title: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.body.weight(.semibold))
          .frame(width: 22)
        Text(title)
          .font(.body.weight(.semibold))
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppTheme.textSecondary)
      }
      .foregroundStyle(AppTheme.textPrimary)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - UIKit

private struct DictionaryReferenceView: UIViewControllerRepresentable {
  let term: String

  func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
    UIReferenceLibraryViewController(term: term)
  }

  func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {}
}
