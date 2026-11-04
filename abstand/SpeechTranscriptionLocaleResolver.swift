import Foundation
import Speech

/// Wählt eine von `SpeechTranscriber` unterstützte Locale (Buchsprache → Gerät → Englisch).
enum SpeechTranscriptionLocaleResolver {
  struct Resolution {
    let locale: Locale
    /// Buch-Metadaten hatten eine Sprache, aber es wurde eine andere Locale genutzt.
    let usedFallback: Bool
  }

  static func resolve(preferredLanguageTag: String?) async throws -> Resolution {
    let supported = await SpeechTranscriber.supportedLocales
    guard !supported.isEmpty else {
      throw PlayerLiveTranscriptionError.localeNotSupported
    }

    let bookLocale = ABSBook.locale(fromABSMetadataLanguage: preferredLanguageTag)
    var candidates: [Locale] = []
    if let bookLocale { candidates.append(bookLocale) }
    candidates.append(Locale.current)
    for id in Locale.preferredLanguages {
      candidates.append(Locale(identifier: id))
    }
    candidates.append(contentsOf: [
      Locale(identifier: "en-US"),
      Locale(identifier: "en-GB"),
      Locale(identifier: "en"),
      Locale(identifier: "de-DE"),
      Locale(identifier: "de"),
    ])

    var seen = Set<String>()
    for candidate in candidates {
      let key = candidate.identifier(.bcp47).lowercased()
      guard seen.insert(key).inserted else { continue }
      if let match = matchLocale(candidate, in: supported) {
        let usedFallback =
          bookLocale != nil
          && match.identifier(.bcp47).lowercased() != bookLocale!.identifier(.bcp47).lowercased()
          && !sameLanguage(match, bookLocale!)
        return Resolution(locale: match, usedFallback: usedFallback)
      }
    }

    if let first = stableVariant(of: supported) {
      return Resolution(locale: first, usedFallback: true)
    }
    throw PlayerLiveTranscriptionError.localeNotSupported
  }

  /// Exakte oder Sprachcode-Übereinstimmung (z. B. `de` → `de-DE`).
  static func matchLocale(_ requested: Locale, in supported: [Locale]) -> Locale? {
    let reqId = requested.identifier(.bcp47).lowercased()
    if reqId.isEmpty { return nil }

    if let exact = supported.first(where: { $0.identifier(.bcp47).lowercased() == reqId }) {
      return exact
    }

    let reqLang = languageCode(from: requested) ?? (reqId.count >= 2 ? String(reqId.prefix(2)) : nil)
    guard let reqLang else { return nil }

    let langMatches = supported.filter { locale in
      let id = locale.identifier(.bcp47).lowercased()
      if id == reqLang { return true }
      if id.hasPrefix(reqLang + "-") { return true }
      return languageCode(from: locale) == reqLang
    }

    return stableVariant(of: langMatches)
  }

  /// Immer dieselbe Variante einer Sprache: `supportedLocales` wechselt die Reihenfolge bei jedem
  /// App-Start, und die Variante steckt im Namen der Transkriptdatei. `first` lieferte deshalb mal
  /// `de-CH`, mal `de-AT` — vorhandene Transkripte wurden nicht gefunden und neu erzeugt.
  /// Reihenfolge: Region des Geräts, Standardvariante der Sprache, dann alphabetisch.
  private static func stableVariant(of locales: [Locale]) -> Locale? {
    let sorted = locales.sorted { $0.identifier(.bcp47).lowercased() < $1.identifier(.bcp47).lowercased() }
    let regional = sorted.filter { $0.identifier(.bcp47).contains("-") }
    guard let language = regional.first.flatMap(languageCode(from:)) else { return sorted.first }
    let sameLanguage = regional.filter { languageCode(from: $0) == language }
    var preferred: [String] = []
    if let region = Locale.current.region?.identifier.lowercased() {
      preferred.append("\(language)-\(region)")
    }
    preferred.append(defaultVariants[language] ?? "\(language)-\(language)")
    for id in preferred {
      if let match = sameLanguage.first(where: { $0.identifier(.bcp47).lowercased() == id }) { return match }
    }
    return regional.first
  }

  /// Standardvarianten, die nicht dem Muster `de-de` folgen.
  private static let defaultVariants = ["en": "en-us", "zh": "zh-cn", "pt": "pt-br", "ja": "ja-jp", "ko": "ko-kr"]

  /// Genau diese Variante ist installiert — `matchLocale` würde auch eine andere Region akzeptieren
  /// und den Download der tatsächlich gewählten Variante überspringen.
  static func isInstalled(_ locale: Locale, in installed: [Locale]) -> Bool {
    let id = locale.identifier(.bcp47).lowercased()
    return installed.contains { $0.identifier(.bcp47).lowercased() == id }
  }

  private static func languageCode(from locale: Locale) -> String? {
    if #available(iOS 16, *) {
      return locale.language.languageCode?.identifier.lowercased()
    }
    let id = locale.identifier(.bcp47).lowercased()
    guard let dash = id.firstIndex(of: "-") else {
      return id.count >= 2 ? String(id.prefix(2)) : id
    }
    return String(id[..<dash])
  }

  private static func sameLanguage(_ a: Locale, _ b: Locale) -> Bool {
    guard let ca = languageCode(from: a), let cb = languageCode(from: b) else { return false }
    return ca == cb
  }
}
