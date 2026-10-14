package de.letzgo.abstand.ui.metadata

import de.letzgo.abstand.data.AbsAudibleChaptersResponse
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsChapter
import de.letzgo.abstand.data.AbsItemChaptersPayload
import de.letzgo.abstand.data.AbsItemMediaMetadataPatch
import de.letzgo.abstand.data.AbsMetadataMatch
import de.letzgo.abstand.data.AbsMetadataProvider
import de.letzgo.abstand.data.AbstandErrorFilter
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch

/**
 * Metadaten-Aktionen aus iOS `AppModel` (`loadMetadataProviders`, `searchMetadataBooks`,
 * `applyMetadataMatch`, `searchCoversOnline`, `searchLibrarySeries`, `applyCoverURL`,
 * `searchAudibleChapters`, `applyItemChapters`, `refreshEditedBookEverywhere`). Fehler kommen als
 * Rückgabewert (Alert im Sheet), nie über den Root-Alert.
 */
object MetadataActions {
    private val model: AppModel get() = AppModel.shared

    private val _bookUpdated = MutableSharedFlow<AbsBook>(extraBufferCapacity = 8)
    /**
     * Frischer Serverstand nach Metadaten-/Cover-/Kapitel-Änderung — Katalog, Home und Detail
     * abonnieren das und ersetzen ihre Kopie (iOS: `applyUpdatedBookToLoadedLists`).
     */
    val bookUpdated: SharedFlow<AbsBook> = _bookUpdated.asSharedFlow()

    /** Detail für die Sheets: LocalStore-Detail, sonst Server (expandiert). */
    suspend fun loadItem(itemId: String): AbsBook? {
        val session = model.session
        session.currentLocalLibraryStore()?.let { store -> runCatching { store.fetchBookDetail(itemId) }.getOrNull()?.let { return it } }
        val c = session.client ?: return session.currentLocalLibraryStore()?.let { runCatching { it.fetchBook(itemId) }.getOrNull() }
        return try {
            c.item(itemId, expanded = true)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.currentLocalLibraryStore()?.let { runCatching { it.fetchBook(itemId) }.getOrNull() }
        }
    }

    suspend fun loadMetadataProviders(): List<AbsMetadataProvider> {
        val c = model.session.client ?: error("Not connected to the server.")
        return c.metadataProviders().books
    }

    suspend fun searchMetadataBooks(title: String, author: String?, provider: String): List<AbsMetadataMatch> {
        val c = model.session.client ?: error("Not connected to the server.")
        return c.searchBooks(title, author, provider, null)
    }

    suspend fun searchCoversOnline(title: String, author: String?, provider: String): List<String> {
        val c = model.session.client ?: error("Not connected to the server.")
        return c.searchCovers(title, author, provider)
    }

    /** iOS: `searchLibrarySeries` — Serien-Namen (ab 3 Zeichen, max. 12, dedupliziert). */
    suspend fun searchLibrarySeries(query: String, libraryId: String?): List<String> {
        val q = query.trim()
        if (q.length < 3) return emptyList()
        val session = model.session
        val c = session.client ?: return emptyList()
        val lib = libraryId?.trim()?.ifEmpty { null } ?: session.booksCatalogLibrary?.id ?: session.selectedBooksLibrary.value?.id
        if (lib.isNullOrEmpty()) return emptyList()
        val res = c.search(lib, q, limit = 24)
        return MetadataLogic.filterSeriesSuggestions(res.series.map { it.name }, q)
    }

    /** iOS: `applyMetadataMatch` — `null` bei Erfolg, sonst Fehlertext. */
    suspend fun applyMetadataMatch(itemId: String, patch: AbsItemMediaMetadataPatch, coverURL: String?): String? {
        val session = model.session
        val c = session.client ?: return "Not connected to the server."
        if (!session.isNetworkReachable.value) return "No network connection."
        return try {
            c.updateItemMedia(itemId, patch, coverURL)
            if (!coverURL.isNullOrEmpty()) session.clearCoverImageCache()
            // Im Hintergrund — das Sheet schließt sofort.
            model.scope.launch { refreshEditedBookEverywhere(itemId) }
            null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (AbstandErrorFilter.isBenignCancellation(e)) null else e.message ?: ""
        }
    }

    /** iOS: `applyCoverURL`. */
    suspend fun applyCoverURL(itemId: String, url: String): String? {
        val session = model.session
        val c = session.client ?: return "Not connected to the server."
        if (!session.isNetworkReachable.value) return "No network connection."
        return try {
            c.applyCoverURL(itemId, url)
            session.clearCoverImageCache()
            model.scope.launch { refreshEditedBookEverywhere(itemId) }
            null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (AbstandErrorFilter.isBenignCancellation(e)) null else e.message ?: ""
        }
    }

    suspend fun searchAudibleChapters(asin: String, region: String): AbsAudibleChaptersResponse {
        val c = model.session.client ?: error("Not connected to the server.")
        return c.searchChapters(asin, region)
    }

    /** iOS: `applyItemChapters` — Kapitel speichern, laufenden Player sofort mitziehen. */
    suspend fun applyItemChapters(itemId: String, chapters: List<AbsItemChaptersPayload.Chapter>): String? {
        val session = model.session
        val c = session.client ?: return "Not connected to the server."
        if (!session.isNetworkReachable.value) return "No network connection."
        return try {
            c.updateItemChapters(itemId, chapters)
            PlaybackController.shared(model.appContext).refreshActiveBookChapters(
                itemId, chapters.map { AbsChapter(it.id, it.start, it.end, it.title) },
            )
            model.scope.launch { refreshEditedBookEverywhere(itemId) }
            null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (AbstandErrorFilter.isBenignCancellation(e)) null else e.message ?: ""
        }
    }

    /** iOS: `refreshEditedBookEverywhere` — frischen Stand in Player, LocalStore und Listen. */
    suspend fun refreshEditedBookEverywhere(itemId: String) {
        val session = model.session
        val c = session.client ?: return
        val fresh = runCatching { c.item(itemId, expanded = true) }.getOrNull() ?: return
        PlaybackController.shared(model.appContext).refreshActiveBookMetadata(fresh)
        session.currentLocalLibraryStore()?.let { store ->
            runCatching { store.upsertBookDetail(fresh) }
            runCatching { store.upsertBooks(listOf(fresh)) }
        }
        _bookUpdated.tryEmit(fresh)
    }
}

/** Reine Logik der Metadaten-Sheets (testbar). */
object MetadataLogic {
    /** iOS: `splitCommaList`. */
    fun splitCommaList(text: String): List<String> = text.split(",").map { it.trim() }.filter { it.isNotEmpty() }

    /** iOS: `searchLibrarySeries` — enthält Suchtext, ohne Duplikate (case-insensitive), max. 12, ohne exakten Treffer. */
    fun filterSeriesSuggestions(names: List<String>, query: String): List<String> {
        val needle = query.trim().lowercase()
        val seen = HashSet<String>()
        val out = mutableListOf<String>()
        for (raw in names) {
            val name = raw.trim()
            if (name.isEmpty()) continue
            val key = name.lowercase()
            if (!key.contains(needle) || !seen.add(key)) continue
            out += name
            if (out.size >= 12) break
        }
        // iOS (Sheet): exakten Treffer nicht als Vorschlag anbieten.
        return out.filter { !it.equals(query.trim(), ignoreCase = true) }
    }

    data class PreviewChapter(val title: String, val start: Double, val end: Double)

    /** iOS: `ChaptersEditorSheet.previewChapters` — inkl. optionaler Branding-Entfernung. */
    fun previewChapters(resp: AbsAudibleChaptersResponse?, mediaDuration: Double?, removeBranding: Boolean): List<PreviewChapter> {
        if (resp == null) return emptyList()
        val raw = resp.chapters.sortedBy { it.start }
        if (raw.isEmpty()) return emptyList()
        val total = resp.runtimeLengthSec ?: mediaDuration ?: 0.0
        val introSec = (resp.brandIntroDurationMs ?: 0.0) / 1000.0
        val outroSec = (resp.brandOutroDurationMs ?: 0.0) / 1000.0
        val entries = raw.mapIndexed { i, ch ->
            var start = ch.start
            var end = if (i + 1 < raw.size) raw[i + 1].start else if (total > 0) total else ch.start + ch.length
            if (removeBranding) {
                start = maxOf(0.0, start - introSec)
                end = maxOf(start, end - introSec)
            }
            PreviewChapter(ch.title, start, end)
        }.toMutableList()
        if (removeBranding && outroSec > 0 && entries.isNotEmpty()) {
            val last = entries.last()
            if (last.end - last.start <= outroSec) entries.removeAt(entries.lastIndex)
            else entries[entries.lastIndex] = last.copy(end = maxOf(last.start, last.end - outroSec))
        }
        return entries
    }

    /** iOS: Audible-Regionen (API lowercase, Anzeige uppercase). */
    val audibleRegions = listOf(
        "us" to "US", "gb" to "UK", "de" to "DE", "ca" to "CA", "au" to "AU",
        "fr" to "FR", "jp" to "JP", "it" to "IT", "in" to "IN", "es" to "ES",
    )

    private val languageRegions = mapOf(
        "en" to "us", "eng" to "us", "english" to "us",
        "de" to "de", "deu" to "de", "ger" to "de", "german" to "de", "deutsch" to "de",
        "fr" to "fr", "fra" to "fr", "fre" to "fr", "french" to "fr", "francais" to "fr", "français" to "fr",
        "it" to "it", "ita" to "it", "italian" to "it", "italiano" to "it",
        "es" to "es", "spa" to "es", "spanish" to "es", "espanol" to "es", "español" to "es",
        "ja" to "jp", "jpn" to "jp", "japanese" to "jp",
    )

    private val countryRegions = mapOf(
        "us" to "us", "gb" to "gb", "uk" to "gb", "de" to "de", "ca" to "ca",
        "au" to "au", "fr" to "fr", "jp" to "jp", "it" to "it", "in" to "in", "es" to "es",
    )

    /** iOS: `ChaptersEditorSheet.audibleRegion(forLanguage:)` — Freitext-Sprache → Audible-Store. */
    fun audibleRegion(forLanguage: String?): String? {
        val value = forLanguage?.trim()?.lowercase().orEmpty()
        if (value.isEmpty()) return null
        val parts = value.split('-', '_', ' ').filter { it.isNotEmpty() }
        val language = parts.firstOrNull() ?: return null
        if (parts.size > 1) countryRegions[parts[1]]?.let { return it }
        return languageRegions[language]
    }

    /** iOS: Cover-Provider des Editors. */
    val coverProviders = listOf(
        "google" to "Google", "audible" to "Audible", "itunes" to "iTunes",
        "openlibrary" to "OpenLibrary", "audiobookcovers" to "AudiobookCovers", "fantlab" to "FantLab",
    )
}
