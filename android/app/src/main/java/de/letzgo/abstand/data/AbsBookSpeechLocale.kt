package de.letzgo.abstand.data

import java.util.Locale

// iOS: ABSBook+SpeechLocale.swift

private val speechLanguageNameMap: Map<String, String> = mapOf(
    "german" to "de", "deutsch" to "de", "ger" to "de", "deu" to "de",
    "english" to "en", "englisch" to "en", "eng" to "en",
    "french" to "fr", "français" to "fr", "francais" to "fr", "fre" to "fr", "fra" to "fr",
    "spanish" to "es", "español" to "es", "espanol" to "es", "spa" to "es",
    "italian" to "it", "italiano" to "it", "ita" to "it",
    "dutch" to "nl", "nederlands" to "nl", "dut" to "nl", "nld" to "nl",
    "portuguese" to "pt", "português" to "pt", "portugues" to "pt", "por" to "pt",
    "polish" to "pl", "polski" to "pl", "pol" to "pl",
    "russian" to "ru", "rus" to "ru",
    "japanese" to "ja", "jpn" to "ja",
    "chinese" to "zh", "mandarin" to "zh", "zho" to "zh", "chi" to "zh",
    "korean" to "ko", "kor" to "ko",
    "swedish" to "sv", "swe" to "sv",
    "norwegian" to "nb", "nor" to "nb",
    "danish" to "da", "dan" to "da",
    "finnish" to "fi", "fin" to "fi",
    "turkish" to "tr", "tur" to "tr",
    "arabic" to "ar", "ara" to "ar",
    "hindi" to "hi", "hin" to "hi",
    "ukrainian" to "uk", "ukr" to "uk",
    "czech" to "cs", "ces" to "cs", "cze" to "cs",
    "hungarian" to "hu", "hun" to "hu",
    "romanian" to "ro", "ron" to "ro", "rum" to "ro",
    "greek" to "el", "gre" to "el", "ell" to "el",
    "hebrew" to "he", "heb" to "he",
    "indonesian" to "id", "ind" to "id",
    "vietnamese" to "vi", "vie" to "vi",
    "thai" to "th", "tha" to "th",
)

/**
 * iOS: `ABSBook.locale(fromABSMetadataLanguage:)` — Sprach-Feld der ABS-Metadaten → Locale
 * (Namen, ISO-639-2/3-Kürzel, BCP-47-Tags).
 */
fun absLocale(fromABSMetadataLanguage: String?): Locale? {
    val tag = fromABSMetadataLanguage?.swiftTrim() ?: ""
    if (tag.isEmpty()) return null
    val lower = tag.lowercase()
    speechLanguageNameMap[lower]?.let { return Locale.forLanguageTag(it) }
    if (lower.contains("-") || lower.contains("_")) return Locale.forLanguageTag(lower.replace("_", "-"))
    if (lower.length == 2 || lower.length == 3) return Locale.forLanguageTag(lower)
    // iOS: `Locale(identifier: tag)` akzeptiert beliebige Bezeichner.
    @Suppress("DEPRECATION")
    return Locale(tag)
}
