@file:OptIn(ExperimentalReadiumApi::class)

package de.letzgo.abstand.reader

import android.content.Context
import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.logic.EbookReadAlongIndex
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.store.EbookLocalStore
import de.letzgo.abstand.store.EpubReaderSettings
import de.letzgo.abstand.store.EpubReaderTheme
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.Theme
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.content
import org.readium.r2.shared.publication.services.locate
import org.readium.r2.shared.publication.services.locateProgression
import org.readium.r2.shared.publication.services.positions
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.tokenizer.DefaultTextContentTokenizer
import org.readium.r2.shared.util.tokenizer.TextUnit
import org.readium.r2.shared.util.Url
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.io.File

/** iOS: `ReadiumReaderError`. */
class ReadiumReaderException(message: String) : Exception(message) {
    companion object {
        fun invalidFile() = ReadiumReaderException("The eBook file could not be opened.")
        fun formatNotSupported() = ReadiumReaderException("This file format is not supported.")
    }
}

/**
 * iOS: `ReadiumReaderService` — Readium-Setup (Streamer) für lokale EPUBs, Startposition, Locator-
 * Persistenz und EPUB-Einstellungen.
 *
 * Abweichung: PDFs öffnet Android nicht über Readium (dessen PDF-Engines liegen nicht auf Maven
 * Central), sondern mit `android.graphics.pdf.PdfRenderer` ([PdfDocumentSource]); die Locatoren
 * haben trotzdem Readium-Form (`position`, `totalProgression`).
 */
object ReadiumReaderService {
    private val appContext: Context get() = AppModel.shared.appContext

    private val httpClient by lazy { DefaultHttpClient() }
    private val assetRetriever by lazy { AssetRetriever(appContext.contentResolver, httpClient) }
    private val publicationOpener by lazy {
        PublicationOpener(DefaultPublicationParser(appContext, httpClient, assetRetriever, pdfFactory = null))
    }

    /** Publikation nur öffnen (ohne Navigator) — Reader und eBook-Index. */
    suspend fun openPublication(file: File): Publication {
        if (!file.isFile) throw ReadiumReaderException.invalidFile()
        val asset = assetRetriever.retrieve(file).getOrElse { throw ReadiumReaderException(it.message) }
        val publication = publicationOpener.open(asset, allowUserInteraction = false).getOrElse {
            asset.close()
            throw ReadiumReaderException(it.message)
        }
        if (!publication.conformsTo(Publication.Profile.EPUB)) {
            publication.close()
            throw ReadiumReaderException.formatNotSupported()
        }
        return publication
    }

    // MARK: - Einstellungen

    fun readiumTheme(theme: EpubReaderTheme): Theme = when (theme) {
        EpubReaderTheme.light -> Theme.LIGHT
        EpubReaderTheme.sepia -> Theme.SEPIA
        EpubReaderTheme.dark -> Theme.DARK
    }

    /** iOS: `makeEPUBPreferences`. */
    fun epubPreferences(): EpubPreferences = EpubPreferences(
        fontSize = EpubReaderSettings.loadFontSize(),
        publisherStyles = false,
        scroll = EpubReaderSettings.loadContinuousScroll(),
        theme = readiumTheme(EpubReaderSettings.loadTheme()),
    )

    // MARK: - Startposition

    /** iOS: `resolveInitialLocator` — zuerst gespeicherter Readium-Stand, sonst Server-/Hilfs-Prozent. */
    suspend fun resolveInitialLocator(publication: Publication, resumeLocator: Locator?, resumeProgression: Double?): Locator? {
        if (resumeLocator != null) return publication.locate(resumeLocator) ?: resumeLocator
        val fraction = EbookProgressRules.usableResumeProgression(resumeProgression) ?: return null
        publication.locateProgression(fraction)?.let { return it }
        val positions = publication.positions()
        if (positions.isEmpty()) return null
        return positions[EbookProgressRules.positionIndex(fraction, positions.size)]
    }

    /** iOS: `startLocator(for:)`. */
    suspend fun startLocator(publication: Publication): Locator? =
        publication.positions().firstOrNull() ?: publication.readingOrder.firstOrNull()?.let { publication.locatorFromLink(it) }

    // MARK: - Locator-Persistenz (gleiche Dateien wie iOS, Readium-JSON)

    fun fraction(locator: Locator): Double =
        ReaderProgressInfo.fraction(locator.locations.totalProgression, locator.locations.progression)

    fun loadLocator(libraryItemId: String, format: AbsEbookFormat): Locator? {
        val json = EbookLocalStore.loadReadiumLocatorJson(libraryItemId, format) ?: return null
        return runCatching { Locator.fromJSON(JSONObject(json)) }.getOrNull()
    }

    fun saveLocator(locator: Locator, libraryItemId: String, format: AbsEbookFormat) {
        EbookLocalStore.saveReadiumLocatorJson(locator.toJSON().toString(), libraryItemId, format)
    }

    /** iOS: `ReadiumReaderDelegate.navigator(_:locationDidChange:)` — lokaler Stand sofort. */
    fun persistLocation(locator: Locator, libraryItemId: String, format: AbsEbookFormat) {
        val f = fraction(locator)
        if (f > 0.001) EbookLocalStore.saveProgressFraction(f, libraryItemId)
        saveLocator(locator, libraryItemId, format)
    }

    /** PDF-Locator in Readium-Form (Seite 1…n, `totalProgression` wie Readium Swift). */
    fun pdfLocator(file: File, pageIndex: Int, pageCount: Int): Locator = Locator(
        href = Url(file.name) ?: Url("publication.pdf")!!,
        mediaType = MediaType.PDF,
        locations = Locator.Locations(
            position = pageIndex + 1,
            totalProgression = if (pageCount > 0) pageIndex.toDouble() / pageCount else 0.0,
        ),
    )

    /** Seite (0-basiert) eines gespeicherten PDF-Locators. */
    fun pdfPageIndex(locator: Locator, pageCount: Int): Int? {
        if (pageCount <= 0) return null
        locator.locations.position?.let { return (it - 1).coerceIn(0, pageCount - 1) }
        val f = locator.locations.totalProgression ?: return null
        return (f * pageCount).toInt().coerceIn(0, pageCount - 1)
    }
}

/**
 * iOS: `TeleprompterEbookTextProvider` + `EbookReadAlongIndex.build(publication:)` — eBook-Index über
 * Readiums Content-Iterator (Text-Elemente → Sätze → Wörter), je Buch einmal gebaut und geteilt
 * (Reader-Sprung, Teleprompter). Nur wenn das EPUB schon auf dem Gerät liegt (kein Download).
 */
object EbookTextIndexProvider {
    /** Index plus die Readium-Locatoren der Segmente (`EbookReadAlongIndex.Sentence.segment`). */
    class Built(val index: EbookReadAlongIndex, val segmentLocators: List<Locator>) {
        /** iOS: `Sentence.locator` mit Highlight-Kontext. */
        fun locator(segment: Int, text: de.letzgo.abstand.logic.LocatorTextContext): Locator? =
            segmentLocators.getOrNull(segment)?.copy(text = Locator.Text(before = text.before, highlight = text.highlight, after = text.after))

        /** iOS: `EbookReadAlongIndex.wordPosition(for:)` — erstes Wort an einer Lese-Position (Kapitel = gleiches `href`). */
        fun wordPosition(locator: Locator): Int? {
            val href = resourcePath(locator.href.toString())
            var first = -1
            var last = -1
            for ((i, sentence) in index.sentences.withIndex()) {
                val segmentHref = segmentLocators.getOrNull(sentence.segment)?.href?.toString() ?: continue
                if (resourcePath(segmentHref) != href) continue
                if (first < 0) first = i
                last = i
            }
            return index.wordPosition(
                chapterSentences = if (first >= 0) first..last else null,
                highlight = locator.text.highlight,
                progression = locator.locations.progression,
                totalProgression = locator.locations.totalProgression,
            )
        }

        private fun resourcePath(href: String): String {
            val path = href.substringBefore('#')
            return runCatching { java.net.URLDecoder.decode(path.replace("+", "%2B"), "UTF-8") }.getOrDefault(path)
        }
    }

    private val cache = HashMap<String, CompletableDeferred<Built?>>()

    /** Main-Thread. `null`, wenn kein EPUB gecacht ist oder der Text nicht lesbar war (wird nicht gemerkt). */
    suspend fun index(libraryItemId: String): Built? {
        cache[libraryItemId]?.let { return it.await() }
        val account = AppModel.shared.session.cacheAccountDir()
        val cached = EbookLocalStore.cachedEbookIfPresent(account, libraryItemId)
        if (cached == null || cached.second != AbsEbookFormat.epub) return null
        val deferred = CompletableDeferred<Built?>()
        cache[libraryItemId] = deferred
        val result = runCatching { build(cached.first) }.getOrNull()?.takeUnless { it.index.isEmpty }
        deferred.complete(result)
        // Fehlschlag nicht merken — sonst bliebe der eBook-Text bis zum App-Neustart aus.
        if (result == null) cache.remove(libraryItemId)
        return result
    }

    private suspend fun build(file: File): Built {
        val publication = ReadiumReaderService.openPublication(file)
        try {
            return withContext(Dispatchers.Default) { build(publication) }
        } finally {
            publication.close()
        }
    }

    /** iOS: `EbookReadAlongIndex.build(publication:)`. */
    suspend fun build(publication: Publication): Built {
        val content = publication.content(null) ?: return Built(EbookReadAlongIndex.empty, emptyList())
        val tokenizer = DefaultTextContentTokenizer(TextUnit.Sentence, publication.metadata.language)
        val builder = EbookReadAlongIndex.Builder()
        val locators = ArrayList<Locator>()
        val iterator = content.iterator()
        while (iterator.hasNext()) {
            currentCoroutineContext().ensureActive()
            val text = iterator.next() as? Content.TextElement ?: continue
            for (segment in text.segments) {
                val ranges = runCatching { tokenizer.tokenize(segment.text) }.getOrNull()
                builder.addSegment(segment.text, ranges)
                locators.add(segment.locator)
            }
        }
        return Built(builder.build(), locators)
    }
}
