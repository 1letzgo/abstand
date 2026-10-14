package de.letzgo.abstand.logic.speech

import de.letzgo.abstand.data.absLocale
import java.util.Locale

/**
 * iOS: `SpeechTranscriptionLocaleResolver` — wählt eine unterstützte Locale (Buchsprache → Gerät →
 * Englisch/Deutsch). „Unterstützt" heißt auf Android: es gibt ein Vosk-Modell im
 * [SpeechModelCatalog] (ob es schon geladen ist, entscheidet der Aufrufer).
 */
object SpeechTranscriptionLocaleResolver {
    data class Resolution(
        val locale: Locale,
        /** Buch-Metadaten hatten eine Sprache, aber es wurde eine andere genutzt. */
        val usedFallback: Boolean,
    )

    class LocaleNotSupportedException : Exception("Live transcription is not available for this language on this device.")

    /**
     * @param deviceLocales iOS `Locale.current` gefolgt von `Locale.preferredLanguages`.
     */
    fun resolve(
        preferredLanguageTag: String?,
        supported: List<Locale> = SpeechModelCatalog.supportedLocales,
        deviceLocales: List<Locale> = listOf(Locale.getDefault()),
    ): Resolution {
        if (supported.isEmpty()) throw LocaleNotSupportedException()
        val bookLocale = absLocale(fromABSMetadataLanguage = preferredLanguageTag)
        val candidates = ArrayList<Locale>()
        if (bookLocale != null) candidates.add(bookLocale)
        candidates.addAll(deviceLocales)
        candidates.addAll(listOf("en-US", "en-GB", "en", "de-DE", "de").map(Locale::forLanguageTag))

        val seen = HashSet<String>()
        for (candidate in candidates) {
            val key = bcp47(candidate).lowercase()
            if (!seen.add(key)) continue
            val match = matchLocale(candidate, supported) ?: continue
            val usedFallback = bookLocale != null &&
                bcp47(match).lowercase() != bcp47(bookLocale).lowercase() &&
                !sameLanguage(match, bookLocale)
            return Resolution(match, usedFallback)
        }
        return Resolution(supported.first(), usedFallback = true)
    }

    /** Exakte oder Sprachcode-Übereinstimmung (z. B. `de` → `de-DE`). */
    fun matchLocale(requested: Locale, supported: List<Locale>): Locale? {
        val reqId = bcp47(requested).lowercase()
        if (reqId.isEmpty() || reqId == "und") return null
        supported.firstOrNull { bcp47(it).lowercase() == reqId }?.let { return it }
        val reqLang = languageCode(requested) ?: (if (reqId.length >= 2) reqId.take(2) else null) ?: return null
        val langMatches = supported.filter { locale ->
            val id = bcp47(locale).lowercase()
            id == reqLang || id.startsWith("$reqLang-") || languageCode(locale) == reqLang
        }
        return langMatches.firstOrNull { bcp47(it).contains("-") } ?: langMatches.firstOrNull()
    }

    /** iOS: `locale.identifier(.bcp47)`. */
    fun bcp47(locale: Locale): String = locale.toLanguageTag()

    private fun languageCode(locale: Locale): String? = locale.language.lowercase().takeIf { it.isNotEmpty() }

    private fun sameLanguage(a: Locale, b: Locale): Boolean {
        val ca = languageCode(a) ?: return false
        val cb = languageCode(b) ?: return false
        return ca == cb
    }
}

/**
 * iOS: `SpeechTranscriberAvailability` — Read-Along braucht eine Spracherkennung. Auf Android immer
 * möglich, sobald der Modellkatalog nicht leer ist (Vosk läuft auf jedem Gerät, Modelle sind ladbar).
 */
object SpeechTranscriberAvailability {
    fun isSupported(): Boolean = SpeechModelCatalog.entries.isNotEmpty()
}
