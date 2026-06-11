import SwiftUI
import Translation
import UIKit

// MARK: - Model

struct PlayerTranscriptWordLookupSelection: Identifiable, Equatable {
  let word: PlayerTranscriptWord
  let term: String
  /// Beim Tippen eingefroren — bleibt gültig, auch wenn die Transkription stoppt.
  let sourceLocale: Locale?

  /// Zeitanker statt volatiler Wort-IDs aus dem Live-Transkript.
  var id: String { "\(term)|\(word.globalStart)" }
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
    let code = TranslationTargetLanguage.languageCode(from: locale) ?? locale.identifier(.bcp47)
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
  @ObservedObject var model: AppModel
  @Environment(\.dismiss) private var dismiss

  @State private var showDictionary = false
  @State private var dictionaryAvailable = false
  @State private var targetLanguageCode: String
  @State private var translationConfiguration: TranslationSession.Configuration?
  @State private var translationRequestGeneration = 0
  @State private var translatedText: String?
  @State private var translationError: String?
  @State private var isTranslating = false
  /// Sprachpaket fehlt — Download nur auf expliziten Nutzer-Tap (nie automatisch).
  @State private var needsLanguageDownload = false
  @State private var languageDownloadApproved = false

  init(
    selection: PlayerTranscriptWordLookupSelection,
    sourceLocale: Locale?,
    model: AppModel
  ) {
    self.selection = selection
    self.sourceLocale = sourceLocale
    _model = ObservedObject(wrappedValue: model)
    _targetLanguageCode = State(
      initialValue: TranslationTargetLanguage.normalized(model.translationTargetLanguageCode)
    )
  }

  private var sourceLanguage: Locale.Language? {
    sourceLocale.map(PlayerTranscriptWordLookup.translationLanguage(from:))
  }

  private var targetLanguage: Locale.Language {
    TranslationTargetLanguage.toLocaleLanguage(targetLanguageCode)
  }

  private var sameLanguagePair: Bool {
    TranslationTargetLanguage.sameLanguage(sourceLocale, targetLanguageCode)
  }

  var body: some View {
    NavigationStack {
      sheetContent
        .padding(AppTheme.Layout.tabPaddingH)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.background)
        .navigationTitle(
          String(localized: "Look up & translate", comment: "Teleprompter word lookup title")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Done", comment: "Dismiss sheet")) {
              dismiss()
            }
          }
        }
        .task(id: selection.id) {
          dictionaryAvailable = PlayerTranscriptWordLookup.hasDictionaryDefinition(for: selection.term)
          // Sheet-Einblendung abwarten: startet die Translation-Session während der
          // Präsentations-Transition, crasht UIKit beim Andocken des Remote-Sheets
          // (`_tryToConnectToRemoteSheet:` → unrecognized selector).
          try? await Task.sleep(for: .milliseconds(650))
          guard !Task.isCancelled else { return }
          requestTranslationIfNeeded()
        }
        .onDisappear {
          // Laufende Übersetzung abbrechen — Session nach Sheet-Schließen nicht mehr anfassen.
          translationRequestGeneration += 1
          isTranslating = false
        }
    }
    .sheet(isPresented: $showDictionary) {
      DictionaryReferenceView(term: selection.term)
        .ignoresSafeArea()
    }
    .translationTask(translationConfiguration) { session in
      await runTranslation(using: session)
    }
  }

  private var sheetContent: some View {
    VStack(alignment: .leading, spacing: AppTheme.Layout.withinSectionSpacing) {
      Text(selection.term)
        .font(.title2.weight(.bold))
        .foregroundStyle(AppTheme.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)

      languagePairRow

      if isTranslating {
        HStack(spacing: 10) {
          ProgressView()
            .controlSize(.small)
          Text(String(localized: "Translating…", comment: "Teleprompter word lookup"))
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
        }
      }

      if sameLanguagePair {
        Text(
          String(
            localized: "Source and target language are the same — translation is not needed.",
            comment: "Teleprompter word lookup"
          )
        )
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)
      } else if let translatedText {
        lookupResultCard(
          title: String(localized: "Translation", comment: "Teleprompter word lookup result label"),
          body: translatedText
        )
      }

      if needsLanguageDownload {
        lookupActionButton(
          icon: "arrow.down.circle",
          title: String(
            localized: "Download translation language",
            comment: "Teleprompter word lookup download button"
          )
        ) {
          languageDownloadApproved = true
          requestTranslationIfNeeded()
        }
        Text(
          String(
            localized: "The language pack for this pair is not installed yet.",
            comment: "Teleprompter word lookup download hint"
          )
        )
        .font(.caption)
        .foregroundStyle(AppTheme.textSecondary)
      }

      if let translationError {
        Text(translationError)
          .font(.caption)
          .foregroundStyle(AppTheme.textSecondary)
      }

      if dictionaryAvailable {
        lookupActionButton(
          icon: "character.book.closed",
          title: String(localized: "Look up in dictionary", comment: "Teleprompter word lookup")
        ) {
          showDictionary = true
        }
      } else if !sameLanguagePair, translatedText == nil, !isTranslating {
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
  }

  private var languagePairRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let sourceLocale {
        HStack(spacing: 8) {
          Text(String(localized: "From", comment: "Teleprompter translation source language label"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
          Text(PlayerTranscriptWordLookup.localizedLanguageName(for: sourceLocale))
            .font(.subheadline)
            .foregroundStyle(AppTheme.textPrimary)
          Image(systemName: "arrow.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
          Text(String(localized: "To", comment: "Teleprompter translation target language label"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
          Spacer(minLength: 0)
        }
      }

      HStack(spacing: 12) {
        Image(systemName: "globe")
          .font(.body.weight(.semibold))
          .foregroundStyle(AppTheme.textSecondary)
          .frame(width: 22)
        Text(String(localized: "Target language", comment: "Teleprompter translation target picker"))
          .font(.body)
          .foregroundStyle(AppTheme.textPrimary)
        Spacer(minLength: 8)
        Picker(
          String(localized: "Target language", comment: "Teleprompter translation target picker"),
          selection: $targetLanguageCode
        ) {
          ForEach(TranslationTargetLanguage.pickerOptions(), id: \.id) { opt in
            Text(opt.label).tag(opt.id)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(model.appearanceAccentColor)
        .disabled(isTranslating)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .onChange(of: targetLanguageCode) { _, code in
        let normalized = TranslationTargetLanguage.normalized(code)
        if normalized != code {
          targetLanguageCode = normalized
          return
        }
        if model.translationTargetLanguageCode != normalized {
          model.translationTargetLanguageCode = normalized
        }
        // Neues Sprachpaar — Download wieder nur nach explizitem Tap.
        languageDownloadApproved = false
        requestTranslationIfNeeded()
      }
    }
  }

  private func lookupResultCard(title: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.bold))
        .foregroundStyle(AppTheme.textSecondary)
        .textCase(.uppercase)
      Text(body)
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(14)
    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  @MainActor
  private func requestTranslationIfNeeded() {
    guard !sameLanguagePair else {
      translatedText = nil
      translationError = nil
      isTranslating = false
      return
    }
    let term = selection.term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else {
      translatedText = nil
      translationError = nil
      isTranslating = false
      return
    }

    translatedText = nil
    translationError = nil
    needsLanguageDownload = false
    isTranslating = true
    translationRequestGeneration += 1
    scheduleTranslationSessionRequest()
  }

  /// Bestehende Config mutieren / `invalidate()` — kein `nil` setzen (Re-Entrancy/fatalError).
  @MainActor
  private func scheduleTranslationSessionRequest() {
    let source = sourceLanguage
    let target = targetLanguage

    if var config = translationConfiguration {
      let languagesChanged = config.source != source || config.target != target
      if languagesChanged {
        config.source = source
        config.target = target
        translationConfiguration = config
      } else {
        config.invalidate()
        translationConfiguration = config
      }
    } else {
      translationConfiguration = TranslationSession.Configuration(
        source: source,
        target: target
      )
    }
  }

  @MainActor
  private func runTranslation(using session: TranslationSession) async {
    let generation = translationRequestGeneration
    let term = selection.term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else {
      if translationRequestIsCurrent(generation) { isTranslating = false }
      return
    }

    do {
      let pairingStatus = try await translationPairingStatus()
      guard translationRequestIsCurrent(generation) else { return }

      switch pairingStatus {
      case .installed:
        break
      case .supported:
        // Download-Dialog (Remote-Sheet) nur nach explizitem Nutzer-Tap präsentieren —
        // automatisch während/kurz nach der Sheet-Transition crasht UIKit.
        guard languageDownloadApproved else {
          translatedText = nil
          translationError = nil
          isTranslating = false
          needsLanguageDownload = true
          return
        }
        do {
          try await session.prepareTranslation()
        } catch {
          guard translationRequestIsCurrent(generation) else { return }
          applyTranslationFailure(
            generation: generation,
            message: translationErrorMessage(for: error)
          )
          return
        }
        guard translationRequestIsCurrent(generation) else { return }
      case .unsupported:
        applyTranslationFailure(
          generation: generation,
          message: String(
            localized:
              "This language pair is not supported for translation on this device.",
            comment: "Teleprompter word lookup"
          )
        )
        return
      @unknown default:
        applyTranslationFailure(
          generation: generation,
          message: String(
            localized: "Translation is not available for this language pair.",
            comment: "Teleprompter word lookup"
          )
        )
        return
      }

      guard translationRequestIsCurrent(generation) else { return }
      let response = try await session.translate(term)
      guard translationRequestIsCurrent(generation) else { return }
      translatedText = response.targetText
      translationError = nil
      isTranslating = false
    } catch {
      guard translationRequestIsCurrent(generation) else { return }
      if Task.isCancelled || error is CancellationError {
        isTranslating = false
        return
      }
      applyTranslationFailure(generation: generation, message: translationErrorMessage(for: error))
    }
  }

  private func translationRequestIsCurrent(_ generation: Int) -> Bool {
    !Task.isCancelled && generation == translationRequestGeneration
  }

  private func translationPairingStatus() async throws -> LanguageAvailability.Status {
    let availability = LanguageAvailability()
    if let sourceLanguage {
      return await availability.status(from: sourceLanguage, to: targetLanguage)
    }
    return try await availability.status(for: selection.term, to: targetLanguage)
  }

  @MainActor
  private func applyTranslationFailure(generation: Int, message: String) {
    guard translationRequestIsCurrent(generation) else { return }
    translatedText = nil
    translationError = message.isEmpty ? nil : message
    isTranslating = false
  }

  private func translationErrorMessage(for error: Error) -> String {
    if error is CancellationError {
      return String(
        localized:
          "Translation cancelled. Allow the language download when prompted, or try again later.",
        comment: "Teleprompter word lookup"
      )
    }
    if let cocoa = error as? CocoaError, cocoa.code == .userCancelled {
      return String(
        localized:
          "Language download was skipped. Translation needs the language pack — try again and allow the download.",
        comment: "Teleprompter word lookup"
      )
    }
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError {
      return String(
        localized:
          "Language download was skipped. Translation needs the language pack — try again and allow the download.",
        comment: "Teleprompter word lookup"
      )
    }
    return error.localizedDescription
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
