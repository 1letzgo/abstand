package de.letzgo.abstand.logic.speech

import java.util.Locale

/**
 * Die On-Device-Sprachmodelle (iOS: `SpeechTranscriber.supportedLocales` + `AssetInventory`).
 * Android hat keine System-Spracherkennung mit PCM-Eingang und Wortzeiten; wie stashy nutzt abstand
 * Vosk (Kaldi) mit den kleinen Modellen je Sprache. Nie ohne ausdrücklichen „Download"-Tap geladen,
 * abgelegt unter `filesDir/speech-models/` (übernommen aus stashy `SpeechModelCatalog`).
 */
object SpeechModelCatalog {
    /** Ein ladbares Modell; [code] ist die Sprache (ggf. mit Region), die es bedient. */
    data class Entry(val code: String, val modelName: String, val megabytes: Int) {
        val url: String get() = "https://alphacephei.com/vosk/models/$modelName.zip"
        val sizeText: String get() = "$megabytes MB"
        val displayName: String get() = displayName(code)

        /** Locale des Modells (BCP-47 wie `code`, z. B. `en-gb`). */
        val locale: Locale get() = Locale.forLanguageTag(code)
    }

    /** Vosks aktuelle „small"-Modelle (alphacephei.com/vosk/models/model-list.json). */
    val entries: List<Entry> = listOf(
        Entry("ar", "vosk-model-small-ar-0.3", 104),
        Entry("ca", "vosk-model-small-ca-0.4", 43),
        Entry("cs", "vosk-model-small-cs-0.4-rhasspy", 46),
        Entry("de", "vosk-model-small-de-0.15", 46),
        Entry("en", "vosk-model-small-en-us-0.15", 41),
        Entry("en-gb", "vosk-model-small-en-gb-0.15", 43),
        Entry("en-in", "vosk-model-small-en-in-0.4", 38),
        Entry("eo", "vosk-model-small-eo-0.42", 44),
        Entry("es", "vosk-model-small-es-0.42", 40),
        Entry("fa", "vosk-model-small-fa-0.42", 53),
        Entry("fr", "vosk-model-small-fr-0.22", 42),
        Entry("gu", "vosk-model-small-gu-0.42", 108),
        Entry("hi", "vosk-model-small-hi-0.22", 44),
        Entry("it", "vosk-model-small-it-0.22", 50),
        Entry("ja", "vosk-model-small-ja-0.22", 50),
        Entry("ka", "vosk-model-small-ka-0.42", 46),
        Entry("kk", "vosk-model-small-kz-0.42", 60),
        Entry("ko", "vosk-model-small-ko-0.22", 87),
        Entry("ky", "vosk-model-small-ky-0.42", 51),
        Entry("nl", "vosk-model-small-nl-0.22", 40),
        Entry("pl", "vosk-model-small-pl-0.22", 53),
        Entry("pt", "vosk-model-small-pt-0.3", 32),
        Entry("ru", "vosk-model-small-ru-0.22", 46),
        Entry("sv", "vosk-model-small-sv-rhasspy-0.15", 303),
        Entry("te", "vosk-model-small-te-0.42", 60),
        Entry("tg", "vosk-model-small-tg-0.22", 52),
        Entry("tr", "vosk-model-small-tr-0.3", 37),
        Entry("uk", "vosk-model-small-uk-v3-small", 144),
        Entry("uz", "vosk-model-small-uz-0.22", 51),
        Entry("vi", "vosk-model-small-vn-0.4", 34),
        Entry("zh", "vosk-model-small-cn-0.22", 44),
    )

    /** Sprachen ohne Leerzeichen zwischen Wörtern — ihre Wörter werden ohne Leerzeichen verbunden. */
    val unspacedLanguages = setOf("zh", "ja")

    /** Basis-Sprachcode eines Tags (2/3-Buchstaben-Codes bleiben erhalten). */
    fun languageCode(identifier: String): String? {
        val id = identifier.lowercase().replace('_', '-')
        val dash = id.indexOf('-')
        if (dash >= 0) return id.substring(0, dash).ifEmpty { null }
        if (id.length == 2 || id.length == 3) return id
        return if (id.length >= 2) id.take(2) else id.ifEmpty { null }
    }

    fun displayName(code: String, display: Locale = Locale.getDefault()): String {
        val id = code.replace('_', '-')
        val name = Locale.forLanguageTag(id).let { if (id.contains('-')) it.getDisplayName(display) else it.getDisplayLanguage(display) }
        return name.takeIf { it.isNotEmpty() && !it.equals(id, ignoreCase = true) }
            ?.replaceFirstChar { it.titlecase(display) } ?: id.uppercase()
    }

    /**
     * Passendes Modell für einen Sprach-Tag: exaktes Regionalmodell (`en-GB`) zuerst, dann die Sprache.
     * Nie eine andere Sprache (ein tschechisches Buch darf nicht mit dem deutschen Modell laufen).
     */
    fun entry(tag: String?): Entry? {
        val t = tag?.trim()?.lowercase()?.replace('_', '-')?.takeIf { it.isNotEmpty() } ?: return null
        entries.firstOrNull { it.code == t }?.let { return it }
        val base = languageCode(t) ?: return null
        if (base == "yue") return null // Kantonesisch ist kein Mandarin.
        val region = t.split('-').drop(1).firstOrNull { it.length == 2 }
        if (region != null) entries.firstOrNull { it.code == "$base-$region" }?.let { return it }
        return entries.firstOrNull { it.code == base }
    }

    /** iOS: `SpeechTranscriber.supportedLocales` — die Locales aller Katalogmodelle. */
    val supportedLocales: List<Locale> get() = entries.map { it.locale }

    /** Eine Zeile je Sprache, nach Namen sortiert. */
    fun pickerOptions(display: Locale = Locale.getDefault()): List<Pair<String, String>> =
        entries.map { it.code }.filter { !it.contains('-') }
            .map { it to displayName(it, display) }
            .sortedBy { it.second.lowercase(display) }

    /** Gespeicherter Tag → Picker-Zeile. */
    fun matchingPickerId(stored: String?, optionIds: List<String>): String? {
        val needle = stored?.replace('_', '-')?.lowercase() ?: return null
        optionIds.firstOrNull { it.lowercase() == needle }?.let { return it }
        val base = languageCode(needle) ?: return null
        return optionIds.firstOrNull { it == base }
    }
}
