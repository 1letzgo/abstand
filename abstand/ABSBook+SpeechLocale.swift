import Foundation

extension ABSBook {
  static func locale(fromABSMetadataLanguage raw: String?) -> Locale? {
    let tag = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !tag.isEmpty else { return nil }

    let lower = tag.lowercased()
    let nameMap: [String: String] = [
      "german": "de", "deutsch": "de", "ger": "de", "deu": "de",
      "english": "en", "englisch": "en", "eng": "en",
      "french": "fr", "français": "fr", "francais": "fr", "fre": "fr", "fra": "fr",
      "spanish": "es", "español": "es", "espanol": "es", "spa": "es",
      "italian": "it", "italiano": "it", "ita": "it",
      "dutch": "nl", "nederlands": "nl", "dut": "nl", "nld": "nl",
      "portuguese": "pt", "português": "pt", "portugues": "pt", "por": "pt",
      "polish": "pl", "polski": "pl", "pol": "pl",
      "russian": "ru", "rus": "ru",
      "japanese": "ja", "jpn": "ja",
      "chinese": "zh", "mandarin": "zh", "zho": "zh", "chi": "zh",
      "korean": "ko", "kor": "ko",
      "swedish": "sv", "swe": "sv",
      "norwegian": "nb", "nor": "nb",
      "danish": "da", "dan": "da",
      "finnish": "fi", "fin": "fi",
      "turkish": "tr", "tur": "tr",
      "arabic": "ar", "ara": "ar",
      "hindi": "hi", "hin": "hi",
      "ukrainian": "uk", "ukr": "uk",
      "czech": "cs", "ces": "cs", "cze": "cs",
      "hungarian": "hu", "hun": "hu",
      "romanian": "ro", "ron": "ro", "rum": "ro",
      "greek": "el", "gre": "el", "ell": "el",
      "hebrew": "he", "heb": "he",
      "indonesian": "id", "ind": "id",
      "vietnamese": "vi", "vie": "vi",
      "thai": "th", "tha": "th",
    ]
    if let code = nameMap[lower] { return Locale(identifier: code) }

    if lower.contains("-") || lower.contains("_") {
      let normalized = lower.replacingOccurrences(of: "_", with: "-")
      return Locale(identifier: normalized)
    }

    if lower.count == 2 || lower.count == 3 {
      return Locale(identifier: lower)
    }

    return Locale(identifier: tag)
  }
}
