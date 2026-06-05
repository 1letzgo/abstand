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

    if let first = supported.first {
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

    return langMatches.first { $0.identifier(.bcp47).contains("-") } ?? langMatches.first
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
