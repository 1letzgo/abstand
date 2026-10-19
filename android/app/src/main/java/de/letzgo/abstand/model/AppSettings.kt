package de.letzgo.abstand.model

import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.downloads.DownloadManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale

/**
 * iOS: die einfachen `@Published`-Einstellungen von `AppModel` (`openPlayerWhenStartPlaying`,
 * `readAlongPrefetchEnabled`, `translationTargetLanguageCode`, `smartDownloadOnWiFi`,
 * `smartDownloadRemoveWhenFinished`). Die iOS-Kartenstil-Auswahl (`libraryBookCardStyle`/
 * `libraryPodcastCardStyle`) gibt es auf Android nicht — es existiert nur die kompakte Zeile.
 * Gleiche Prefs-Keys und Defaults wie iOS; Leser beobachten die `StateFlow`s.
 */
object AppSettings {
    private val _openPlayerWhenStartPlaying = MutableStateFlow(initialOpenPlayer())
    /** iOS: `openPlayerWhenStartPlaying` — Standard an (Key fehlt → `true`). */
    val openPlayerWhenStartPlaying: StateFlow<Boolean> = _openPlayerWhenStartPlaying.asStateFlow()

    private val _readAlongPrefetchEnabled = MutableStateFlow(if (prefsReady()) Prefs.bool(Keys.readAlongPrefetch, true) else true)
    /** iOS: `readAlongPrefetchEnabled` — Standard an. */
    val readAlongPrefetchEnabled: StateFlow<Boolean> = _readAlongPrefetchEnabled.asStateFlow()

    private val _translationTargetLanguageCode = MutableStateFlow(TranslationTargetLanguage.load())
    /** iOS: `translationTargetLanguageCode`. */
    val translationTargetLanguageCode: StateFlow<String> = _translationTargetLanguageCode.asStateFlow()

    private val _smartDownloadOnWiFi = MutableStateFlow(if (prefsReady()) DownloadManager.smartDownloadOnWiFi else false)
    val smartDownloadOnWiFi: StateFlow<Boolean> = _smartDownloadOnWiFi.asStateFlow()

    private val _smartDownloadRemoveWhenFinished = MutableStateFlow(if (prefsReady()) DownloadManager.smartDownloadRemoveWhenFinished else false)
    val smartDownloadRemoveWhenFinished: StateFlow<Boolean> = _smartDownloadRemoveWhenFinished.asStateFlow()

    /** Externe Beobachter (z. B. Transkript-Vorproduktion) — iOS: `transcriptPrefetcher.setEnabled`. */
    var onReadAlongPrefetchChanged: ((Boolean) -> Unit)? = null

    fun setOpenPlayerWhenStartPlaying(value: Boolean) {
        _openPlayerWhenStartPlaying.value = value
        Prefs.setBool(Keys.openPlayerWhenStartPlaying, value)
    }

    fun setReadAlongPrefetchEnabled(value: Boolean) {
        val old = _readAlongPrefetchEnabled.value
        _readAlongPrefetchEnabled.value = value
        Prefs.setBool(Keys.readAlongPrefetch, value)
        if (old != value) onReadAlongPrefetchChanged?.invoke(value)
    }

    /** iOS: `translationTargetLanguageCode.didSet` — normalisieren, dann persistieren. */
    fun setTranslationTargetLanguageCode(code: String) {
        val normalized = TranslationTargetLanguage.normalized(code)
        if (normalized == _translationTargetLanguageCode.value) return
        _translationTargetLanguageCode.value = normalized
        Prefs.setString(Keys.translationTargetLanguageCode, normalized)
    }

    fun setSmartDownloadOnWiFi(value: Boolean) {
        DownloadManager.smartDownloadOnWiFi = value
        _smartDownloadOnWiFi.value = value
    }

    fun setSmartDownloadRemoveWhenFinished(value: Boolean) {
        DownloadManager.smartDownloadRemoveWhenFinished = value
        _smartDownloadRemoveWhenFinished.value = value
    }

    private fun initialOpenPlayer(): Boolean {
        if (!prefsReady() || !Prefs.has(Keys.openPlayerWhenStartPlaying)) return true
        return Prefs.bool(Keys.openPlayerWhenStartPlaying, true)
    }

    /** Unit-Tests ohne `Prefs.init` — dann Defaults. */
    internal fun prefsReady(): Boolean = runCatching { Prefs.prefs }.isSuccess
}

/** iOS: `TranslationTargetLanguage` (AppAppearance.swift) — Zielsprache der Teleprompter-Wortübersetzung. */
object TranslationTargetLanguage {
    /** Häufige Zielsprachen für den Picker (Reihenfolge wie iOS). */
    val selectableLanguageCodes = listOf(
        "de", "en", "fr", "es", "it", "nl", "pt", "pl", "ru", "ja", "zh", "ko",
        "ar", "hi", "tr", "sv", "da", "nb", "fi", "cs", "hu", "uk", "el", "he", "vi", "th", "id", "ro",
    )

    fun defaultLanguageCode(deviceLocale: Locale = Locale.getDefault()): String =
        languageCode(deviceLocale.toLanguageTag()) ?: "en"

    fun load(deviceLocale: Locale = Locale.getDefault()): String {
        val raw = if (AppSettings.prefsReady()) Prefs.string(Keys.translationTargetLanguageCode)?.trim().orEmpty() else ""
        return if (raw.isNotEmpty()) normalized(raw, deviceLocale) else defaultLanguageCode(deviceLocale)
    }

    /** Gültiger Picker-Wert (nur bekannte ISO-639-1-Codes), sonst Gerätesprache. */
    fun normalized(code: String, deviceLocale: Locale = Locale.getDefault()): String {
        val def = defaultLanguageCode(deviceLocale)
        val trimmed = code.trim().lowercase()
        if (trimmed.isEmpty()) return def
        val base = languageCode(trimmed) ?: trimmed
        val allowed = selectableLanguageCodes.toSet() + def
        return if (base in allowed) base else def
    }

    fun displayName(code: String, locale: Locale = Locale.getDefault()): String {
        val name = Locale.forLanguageTag(code).getDisplayLanguage(locale)
        return if (name.isNullOrEmpty() || name == code) code.uppercase() else name
    }

    /** iOS: `pickerOptions` — nach Anzeigename sortiert, inkl. Default und aktuellem Wert. */
    fun pickerOptions(current: String, locale: Locale = Locale.getDefault()): List<Pair<String, String>> {
        val codes = (selectableLanguageCodes + defaultLanguageCode(locale) + current).toSet()
        return codes.map { it to displayName(it, locale) }.sortedBy { it.second }
    }

    /** iOS: `languageCode(from identifier:)` — Teil vor `-`/`_`, sonst die ersten zwei Zeichen. */
    fun languageCode(identifier: String): String? {
        val id = identifier.lowercase()
        id.indexOf('-').takeIf { it >= 0 }?.let { return id.substring(0, it) }
        id.indexOf('_').takeIf { it >= 0 }?.let { return id.substring(0, it) }
        return if (id.length >= 2) id.take(2) else id.ifEmpty { null }
    }
}
