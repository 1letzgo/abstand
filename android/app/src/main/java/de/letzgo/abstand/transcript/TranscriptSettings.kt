package de.letzgo.abstand.transcript

import android.content.Context
import de.letzgo.abstand.data.Keys
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.logic.PlayerTranscriptCacheStore
import de.letzgo.abstand.logic.speech.SpeechModelCatalog
import de.letzgo.abstand.logic.speech.SpeechModelStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import java.util.Locale

/**
 * Einstiegspunkt für Einstellungen und App-Start (iOS: Teleprompter-Sektion in `ServerAdminViews`,
 * `AppModel.readAlongPrefetchEnabled`, `abstandApp` → `registerBackgroundTask`).
 */
object TranscriptSettings {
    /** Einmal in `Application.onCreate` (idempotent): Vorproduktion an den App-Lebenszyklus koppeln. */
    fun install(context: Context) {
        PlayerTranscriptPrefetcher.install(context)
        PlayerLiveTranscriptionController.shared(context)
    }

    // MARK: Vorproduktion

    /** iOS: Schalter „Prepare transcripts in background" (Standard an). */
    fun isPrefetchEnabled(): Boolean = PlayerTranscriptPrefetcher.isPrefetchEnabled()

    fun setPrefetchEnabled(context: Context, enabled: Boolean) = PlayerTranscriptPrefetcher.setPrefetchEnabled(context, enabled)

    /** iOS: `teleprompterPrefetchSubtitle` — Statuszeile unter dem Schalter (`null` = aus). */
    fun prefetchSubtitle(): Flow<String?> = combine(
        PlayerTranscriptPrefetcher.pausedReason,
        PlayerTranscriptPrefetcher.isRunning,
        PlayerTranscriptPrefetcher.preparedTracks,
        PlayerTranscriptPrefetcher.totalTracks,
        PlayerTranscriptPrefetcher.currentJobTitle,
    ) { reason, running, done, total, title ->
        prefetchSubtitle(isPrefetchEnabled(), reason, running, done, total, title)
    }

    fun prefetchSubtitle(enabled: Boolean, pausedReason: String?, isRunning: Boolean, done: Int, total: Int, title: String?): String? {
        if (!enabled) return null
        if (pausedReason != null) return pausedReason
        if (isRunning) {
            val progress = "$done of $total tracks"
            return if (title != null) "Preparing $title · $progress" else "Preparing… $progress"
        }
        return "Downloaded titles are up to date. More is prepared overnight while charging."
    }

    // MARK: Sprachmodelle

    /** Modell für eine Sprache (Picker-Code wie `de`, `en-gb`), `null` = nicht unterstützt. */
    fun speechModel(languageTag: String?): SpeechModelCatalog.Entry? = SpeechModelCatalog.entry(languageTag)

    fun isSpeechModelInstalled(context: Context, entry: SpeechModelCatalog.Entry): Boolean = SpeechModelStore.isInstalled(context, entry)

    /** Nur nach ausdrücklichem Nutzer-Tap aufrufen. [progress] 0…1 (beliebiger Thread). */
    suspend fun downloadSpeechModel(context: Context, entry: SpeechModelCatalog.Entry, progress: (Double) -> Unit) =
        SpeechModelStore.download(context, entry, progress)

    /** Belegter Speicher aller Sprachmodelle (Bytes). */
    suspend fun speechModelsBytes(context: Context): Long = withContext(Dispatchers.IO) { SpeechModelStore.installedBytes(context) }

    /** „Delete speech models" — gerade benutzte Modelle bleiben bis zum Ende der Erkennung liegen. */
    suspend fun deleteSpeechModels(context: Context) = SpeechModelStore.deleteAll(context)

    /** Belegter Speicher der Transkripte des aktiven Accounts (Bytes). */
    suspend fun transcriptCacheBytes(): Long = withContext(Dispatchers.IO) {
        PlayerTranscriptCacheStore.totalSizeBytes(TranscriptAccount.current())
    }

    // MARK: Übersetzungssprache

    /** iOS: `TranslationTargetLanguage.load()` — Zielsprache für „Translate" im Wort-Sheet. */
    fun translationTargetLanguageCode(): String = TranslationTargetLanguage.load()

    fun setTranslationTargetLanguageCode(code: String) = TranslationTargetLanguage.persist(code)

    fun translationTargetLanguageOptions(): List<Pair<String, String>> = TranslationTargetLanguage.pickerOptions()
}

/** iOS: `TranslationTargetLanguage` (AppAppearance.swift) — Schlüssel `Keys.translationTargetLanguageCode`. */
object TranslationTargetLanguage {
    /** Häufige Zielsprachen für Picker in Settings und Wort-Sheet. */
    val selectableLanguageCodes = listOf(
        "de", "en", "fr", "es", "it", "nl", "pt", "pl", "ru", "ja", "zh", "ko",
        "ar", "hi", "tr", "sv", "da", "nb", "fi", "cs", "hu", "uk", "el", "he", "vi", "th", "id", "ro",
    )

    fun defaultLanguageCode(device: Locale = Locale.getDefault()): String = languageCode(device.toLanguageTag()) ?: "en"

    fun load(stored: String? = Prefs.string(Keys.translationTargetLanguageCode), device: Locale = Locale.getDefault()): String {
        val raw = stored?.trim().orEmpty()
        return if (raw.isNotEmpty()) normalized(raw, device) else defaultLanguageCode(device)
    }

    /** Gültiger Picker-Wert (nur bekannte ISO-639-1-Codes). */
    fun normalized(code: String, device: Locale = Locale.getDefault()): String {
        val trimmed = code.trim().lowercase()
        val fallback = defaultLanguageCode(device)
        if (trimmed.isEmpty()) return fallback
        val base = languageCode(trimmed) ?: trimmed
        val allowed = selectableLanguageCodes.toSet() + fallback
        return if (base in allowed) base else fallback
    }

    fun persist(code: String) = Prefs.setString(Keys.translationTargetLanguageCode, code)

    fun displayName(code: String, display: Locale = Locale.getDefault()): String =
        Locale.forLanguageTag(code).getDisplayLanguage(display).takeIf { it.isNotEmpty() && it != code }
            ?.replaceFirstChar { it.titlecase(display) } ?: code.uppercase()

    fun pickerOptions(display: Locale = Locale.getDefault()): List<Pair<String, String>> {
        val codes = (selectableLanguageCodes + defaultLanguageCode() + load()).toSet()
        return codes.map { it to displayName(it, display) }.sortedBy { it.second }
    }

    fun sameLanguage(source: Locale?, targetCode: String): Boolean {
        val src = source?.language?.lowercase()?.takeIf { it.isNotEmpty() } ?: return false
        return src == targetCode.trim().lowercase()
    }

    /** Basis-Sprachcode eines Bezeichners (`de-DE` → `de`, `zh_Hans` → `zh`). */
    fun languageCode(identifier: String): String? {
        val id = identifier.trim().replace('_', '-')
        if (id.isEmpty()) return null
        val base = id.substringBefore('-').lowercase()
        return base.takeIf { it.isNotEmpty() }
    }
}
