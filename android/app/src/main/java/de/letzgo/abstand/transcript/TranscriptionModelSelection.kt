package de.letzgo.abstand.transcript

import de.letzgo.abstand.data.absLocale
import de.letzgo.abstand.logic.speech.SpeechModelCatalog
import de.letzgo.abstand.logic.speech.SpeechTranscriptionLocaleResolver
import java.util.Locale

/**
 * Sprache → Vosk-Modell (iOS: `SpeechTranscriptionLocaleResolver.resolve` + `ensureSpeechModel`).
 *
 * Der Resolver bevorzugt bei einer Sprache die Regional-Locale (iOS kennt nur `de-DE`, `en-US` …);
 * im Vosk-Katalog ist die Basissprache (`en` = US-Modell) aber das Standardmodell und `en-gb`/`en-in`
 * sind Varianten. Deshalb löst der Resolver nur die **Sprache** (Buch → Gerät → Englisch/Deutsch),
 * und [SpeechModelCatalog.entry] wählt danach das Modell — mit der Region des Buchs, wenn es eine gibt.
 */
object TranscriptionModelSelection {
    data class Selection(
        val entry: SpeechModelCatalog.Entry,
        /** Sprach-Tag für die Transkriptdateien (`t<track>-<locale>.json`), z. B. `de`, `en-GB`. */
        val localeIdentifier: String,
        /** Buch-Metadaten hatten eine Sprache, aber es wurde eine andere genutzt. */
        val usedFallback: Boolean,
    ) {
        val locale: Locale get() = Locale.forLanguageTag(localeIdentifier)
    }

    /** Basissprachen des Katalogs (je Sprache einmal). */
    val baseLocales: List<Locale>
        get() = SpeechModelCatalog.entries.filter { !it.code.contains('-') }.map { Locale.forLanguageTag(it.code) }

    fun localeIdentifier(entry: SpeechModelCatalog.Entry): String = Locale.forLanguageTag(entry.code).toLanguageTag()

    /** Wirft [SpeechTranscriptionLocaleResolver.LocaleNotSupportedException], wenn nichts passt. */
    fun select(preferredLanguageTag: String?, deviceLocales: List<Locale> = listOf(Locale.getDefault())): Selection {
        val resolution = SpeechTranscriptionLocaleResolver.resolve(preferredLanguageTag, baseLocales, deviceLocales)
        val language = resolution.locale.language
        val book = absLocale(fromABSMetadataLanguage = preferredLanguageTag)
        val device = deviceLocales.firstOrNull { it.language == language }
        // Regionalmodell nur, wenn Buch (oder Gerät bei Fallback) genau diese Sprache mit Region hat.
        val regional = listOfNotNull(book?.takeIf { it.language == language }, device)
            .firstNotNullOfOrNull { candidate ->
                SpeechModelCatalog.entry(candidate.toLanguageTag())?.takeIf { it.code.contains('-') }
            }
        val entry = regional ?: SpeechModelCatalog.entry(language)
            ?: throw SpeechTranscriptionLocaleResolver.LocaleNotSupportedException()
        return Selection(entry, localeIdentifier(entry), resolution.usedFallback)
    }

    /**
     * iOS: `PlayerTranscriptPrefetcher.installedLocale(forLanguageTag:installed:)` — nur die Buchsprache,
     * kein Fallback, und nur mit bereits installiertem Modell (kein Download im Hintergrund).
     */
    fun prefetchSelection(
        languageTag: String?,
        isInstalled: (SpeechModelCatalog.Entry) -> Boolean,
        deviceLocales: List<Locale> = listOf(Locale.getDefault()),
    ): Selection? {
        val selection = runCatching { select(languageTag, deviceLocales) }.getOrNull() ?: return null
        if (selection.usedFallback) return null
        return selection.takeIf { isInstalled(it.entry) }
    }
}
