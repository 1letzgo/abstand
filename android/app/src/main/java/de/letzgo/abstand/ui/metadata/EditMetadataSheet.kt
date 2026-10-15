package de.letzgo.abstand.ui.metadata

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsItemMediaMetadataPatch
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandAlert
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandInlineNotice
import de.letzgo.abstand.ui.components.AbstandInlineSpinner
import de.letzgo.abstand.ui.components.AbstandInsetTextField
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSpinnerSize
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.MetadataSheetCard
import de.letzgo.abstand.ui.components.MetadataSheetCardDivider
import de.letzgo.abstand.ui.components.MetadataSheetFieldLabel
import de.letzgo.abstand.ui.components.MetadataSheetMenuPicker
import de.letzgo.abstand.ui.components.MetadataSheetMetrics
import de.letzgo.abstand.ui.components.MetadataSheetScaffold
import de.letzgo.abstand.ui.components.MetadataSheetSearchButton
import de.letzgo.abstand.ui.components.MetadataSheetSection
import de.letzgo.abstand.ui.components.MetadataSheetTextField
import de.letzgo.abstand.ui.medium
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import de.letzgo.abstand.ui.components.AbstandIconButton

/** Feste Breite des Seriennummer-Feldes (iOS: `SeriesRowMetrics.numberFieldWidth`). */
private val SeriesNumberFieldWidth = 64.dp

/** Editierbare Serie-Zeile (iOS: `EditSeriesRow`). */
private data class EditSeriesRow(
    val name: String = "",
    val sequence: String = "",
    /** Stabile Zeilen-ID für Vorschläge/Such-Jobs (nicht Teil des Patches). */
    val id: String = java.util.UUID.randomUUID().toString(),
)

/**
 * iOS: `EditMetadataSheet` — Metadaten bearbeiten (`PATCH /api/items/:id/media`) und Cover online
 * suchen/übernehmen. Admin/Root-only. Lädt das Item selbst ([MetadataActions.loadItem]).
 */
@Composable
fun EditMetadataSheet(itemId: String, onDismiss: () -> Unit) {
    var book by remember { mutableStateOf<AbsBook?>(null) }
    var loadFailed by remember { mutableStateOf(false) }
    LaunchedEffect(itemId) {
        book = MetadataActions.loadItem(itemId)
        loadFailed = book == null
    }
    val b = book
    if (b == null) {
        MetadataSheetScaffold(title = "Edit Metadata", onCancel = onDismiss) {
            if (loadFailed) AbstandInlineNotice("Could not load this item.", isError = true) else AbstandLoadingSpinner()
        }
    } else {
        EditMetadataForm(itemId, b, onDismiss)
    }
}

@Composable
private fun EditMetadataForm(itemId: String, book: AbsBook, onDismiss: () -> Unit) {
    val metadata = book.media.metadata
    val palette = Theme.palette
    val scope = rememberCoroutineScope()

    var title by remember { mutableStateOf(metadata.title) }
    var subtitle by remember { mutableStateOf(metadata.subtitle.orEmpty()) }
    var author by remember { mutableStateOf(metadata.authorName ?: metadata.authors?.joinToString(", ") { it.name }.orEmpty()) }
    var narrator by remember { mutableStateOf(metadata.narratorName ?: metadata.narrators?.joinToString(", ").orEmpty()) }
    var descriptionText by remember { mutableStateOf(metadata.description.orEmpty()) }
    var publisher by remember { mutableStateOf(metadata.publisher.orEmpty()) }
    var publishedYear by remember { mutableStateOf(metadata.publishedYear.orEmpty()) }
    var language by remember { mutableStateOf(metadata.language.orEmpty()) }
    var genres by remember { mutableStateOf(metadata.genres.orEmpty().joinToString(", ")) }
    var tagsText by remember { mutableStateOf(book.media.tags.orEmpty().joinToString(", ")) }
    var asin by remember { mutableStateOf(metadata.asin.orEmpty()) }
    val seriesRows = remember {
        mutableStateListOf<EditSeriesRow>().apply {
            val s = metadata.series
            if (!s.isNullOrEmpty()) addAll(s.map { EditSeriesRow(it.name, it.sequence.orEmpty()) }) else add(EditSeriesRow())
        }
    }
    // Nach stabiler Zeilen-ID, nicht nach Index — sonst hängen Vorschläge nach dem Entfernen an der falschen Zeile.
    val suggestions = remember { mutableStateMapOf<String, List<String>>() }
    var searchBusyRow by remember { mutableStateOf<String?>(null) }
    val searchJobs = remember { HashMap<String, Job>() }

    var isSaving by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf<String?>(null) }

    var coverTitle by remember { mutableStateOf(metadata.title) }
    var coverAuthor by remember { mutableStateOf(metadata.authorName.orEmpty()) }
    var coverProvider by remember { mutableStateOf("google") }
    var coverResults by remember { mutableStateOf<List<String>>(emptyList()) }
    var isSearchingCovers by remember { mutableStateOf(false) }
    var hasSearchedCovers by remember { mutableStateOf(false) }
    var coverSearchError by remember { mutableStateOf<String?>(null) }
    var pendingCoverURL by remember { mutableStateOf<String?>(null) }
    var isApplyingCover by remember { mutableStateOf(false) }
    var coverApplyError by remember { mutableStateOf<String?>(null) }

    /** iOS: `scheduleSeriesSearch` — nur bei Nutzereingabe, entprellt (300 ms), ab 3 Zeichen. */
    fun scheduleSeriesSearch(row: String) {
        searchJobs[row]?.cancel()
        searchJobs[row] = scope.launch {
            val q = seriesRows.firstOrNull { it.id == row }?.name?.trim().orEmpty()
            if (q.length < 3) {
                suggestions[row] = emptyList()
                if (searchBusyRow == row) searchBusyRow = null
                return@launch
            }
            delay(SERIES_SEARCH_DEBOUNCE_MS)
            if (seriesRows.firstOrNull { it.id == row }?.name?.trim() != q) return@launch
            searchBusyRow = row
            try {
                val names = MetadataActions.searchLibrarySeries(q, book.libraryId)
                if (seriesRows.any { it.id == row }) suggestions[row] = names
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                suggestions[row] = emptyList()
            } finally {
                if (searchBusyRow == row) searchBusyRow = null
            }
        }
    }

    fun runCoverSearch() {
        val q = coverTitle.trim()
        if (q.isEmpty()) return
        scope.launch {
            isSearchingCovers = true
            coverSearchError = null
            coverResults = emptyList()
            hasSearchedCovers = false
            try {
                coverResults = MetadataActions.searchCoversOnline(q, coverAuthor.trim().ifEmpty { null }, coverProvider)
                hasSearchedCovers = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                coverSearchError = e.message ?: "Search failed"
            } finally {
                isSearchingCovers = false
            }
        }
    }

    fun save() = scope.launch {
        isSaving = true
        val patch = AbsItemMediaMetadataPatch(
            title = title.trim(),
            subtitle = subtitle.trim().ifEmpty { null },
            authorNames = MetadataLogic.splitCommaList(author),
            narratorNames = MetadataLogic.splitCommaList(narrator),
            descriptionText = descriptionText.trim().ifEmpty { null },
            publisher = publisher.trim().ifEmpty { null },
            publishedYear = publishedYear.trim().ifEmpty { null },
            language = language.trim().ifEmpty { null },
            asin = asin.trim().ifEmpty { null },
            genres = MetadataLogic.splitCommaList(genres),
            tags = MetadataLogic.splitCommaList(tagsText),
            series = seriesRows.map { EditSeriesRow(it.name.trim(), it.sequence.trim()) }
                .filter { it.name.isNotEmpty() }
                .map { AbsItemMediaMetadataPatch.SeriesPayload(it.name, it.sequence.ifEmpty { null }) },
        )
        val failure = try { MetadataActions.applyMetadataMatch(itemId, patch, null) } finally { isSaving = false }
        if (failure != null) saveError = failure.ifEmpty { "Could not save metadata. Check your connection and permissions." } else onDismiss()
    }

    MetadataSheetScaffold(
        title = "Edit Metadata",
        onCancel = onDismiss,
        onConfirm = { save() },
        confirmLabel = "Save",
        confirmEnabled = !isSaving,
        isBusy = isSaving,
    ) {
        MetadataSheetSection("Details") {
            MetadataSheetCard {
                MetadataSheetTextField("Title", title, { title = it })
                MetadataSheetTextField("Subtitle", subtitle, { subtitle = it })
                MetadataSheetTextField("Author", author, { author = it }, hint = "Comma separated")
                MetadataSheetTextField("Narrator", narrator, { narrator = it }, hint = "Comma separated")
                // Series — wiederholbare Zeilen (Name + Nummer); ab 3 Zeichen Server-Suche.
                Column(verticalArrangement = Arrangement.spacedBy(MetadataSheetMetrics.labelToContentSpacing)) {
                    MetadataSheetFieldLabel("Series", hint = "Search from 3 letters")
                    seriesRows.forEachIndexed { idx, row ->
                        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing), verticalAlignment = Alignment.CenterVertically) {
                                AbstandInsetTextField(
                                    value = row.name, placeholder = "Series name", label = "Series name",
                                    onValueChange = { seriesRows[idx] = row.copy(name = it); scheduleSeriesSearch(row.id) },
                                    capitalization = KeyboardCapitalization.Words,
                                    modifier = Modifier.weight(1f),
                                )
                                AbstandInsetTextField(
                                    value = row.sequence, placeholder = "#", label = "Series number",
                                    onValueChange = { seriesRows[idx] = row.copy(sequence = it) },
                                    keyboardType = KeyboardType.Decimal,
                                    centered = true,
                                    modifier = Modifier.width(SeriesNumberFieldWidth),
                                )
                                AbstandIconButton(
                                    SF.minusCircle,
                                    "Remove series",
                                    onClick = {
                                        searchJobs.remove(row.id)?.cancel()
                                        suggestions.remove(row.id)
                                        if (searchBusyRow == row.id) searchBusyRow = null
                                        val i = seriesRows.indexOfFirst { it.id == row.id }
                                        if (i >= 0) {
                                            if (seriesRows.size == 1) seriesRows[0] = EditSeriesRow() else seriesRows.removeAt(i)
                                        }
                                    },
                                    tint = palette.textSecondary,
                                )
                            }
                            val rowSuggestions = suggestions[row.id].orEmpty()
                            if (searchBusyRow == row.id) {
                                AbstandInlineSpinner(Modifier.padding(start = AppTheme.Layout.hairlineSpacing))
                            } else if (rowSuggestions.isNotEmpty()) {
                                SeriesSuggestionsList(rowSuggestions) { name ->
                                    searchJobs.remove(row.id)?.cancel()
                                    val i = seriesRows.indexOfFirst { it.id == row.id }
                                    if (i >= 0) seriesRows[i] = seriesRows[i].copy(name = name)
                                    suggestions[row.id] = emptyList()
                                }
                            }
                        }
                    }
                    Row(
                        Modifier.clickable { seriesRows.add(EditSeriesRow()) }.padding(top = AppTheme.Layout.hairlineSpacing),
                        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(SF.plusCircle, contentDescription = null, tint = Theme.accent, modifier = Modifier.width(AppTheme.Layout.coverBadgeSize))
                        Text("Add series", style = AppType.bodySmall.medium, color = Theme.accent)
                    }
                }
                MetadataSheetTextField("Description", descriptionText, { descriptionText = it }, minLines = 3, maxLines = 8)
                MetadataSheetTextField("Publisher", publisher, { publisher = it })
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing), verticalAlignment = Alignment.Top) {
                    MetadataSheetTextField("Year", publishedYear, { publishedYear = it }, Modifier.weight(1f), keyboardType = KeyboardType.Number)
                    MetadataSheetTextField("Language", language, { language = it }, Modifier.weight(1f))
                }
                MetadataSheetTextField("Genres", genres, { genres = it }, hint = "Comma separated")
                MetadataSheetTextField("Tags", tagsText, { tagsText = it }, hint = "Comma separated")
                MetadataSheetTextField(
                    "ASIN", asin, { asin = it },
                    capitalization = KeyboardCapitalization.Characters, autoCorrect = false,
                )
            }
        }

        MetadataSheetSection("Cover") {
            MetadataSheetCard {
                MetadataSheetTextField("Title", coverTitle, { coverTitle = it }, imeAction = ImeAction.Search, onSubmit = { runCoverSearch() })
                MetadataSheetTextField("Author", coverAuthor, { coverAuthor = it }, imeAction = ImeAction.Search, onSubmit = { runCoverSearch() })
                MetadataSheetMenuPicker(
                    title = "Provider",
                    selection = MetadataLogic.coverProviders.firstOrNull { it.first == coverProvider } ?: MetadataLogic.coverProviders.first(),
                    options = MetadataLogic.coverProviders,
                    label = { it.second },
                    onSelect = { coverProvider = it.first },
                )
                MetadataSheetSearchButton(onClick = { runCoverSearch() }, enabled = coverTitle.isNotBlank() && !isSearchingCovers)
            }
            when {
                isSearchingCovers -> MetadataSheetCard { AbstandLoadingSpinner(size = AbstandSpinnerSize.Regular, verticalPadding = AppTheme.Layout.blockSpacing) }
                coverSearchError != null -> MetadataSheetCard { AbstandInlineNotice(coverSearchError!!, isError = true) }
                coverResults.isEmpty() -> if (hasSearchedCovers) MetadataSheetCard { AbstandInlineNotice("No covers found.") }
                else -> MetadataSheetCard {
                    coverResults.chunked(COVER_COLUMNS).forEach { rowUrls ->
                        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing)) {
                            rowUrls.forEach { url ->
                                Box(
                                    Modifier.weight(1f).aspectRatio(2f / 3f)
                                        .clip(RoundedCornerShape(AppTheme.Layout.chipCornerRadius))
                                        .background(palette.background)
                                        .clickable(enabled = !isApplyingCover) { pendingCoverURL = url }
                                        .semantics { contentDescription = "Cover option" },
                                ) {
                                    CoverImage(url = url, cacheScopeId = "coverSearch", requiresAuthorization = false, modifier = Modifier.fillMaxWidth().aspectRatio(2f / 3f))
                                }
                            }
                            repeat(COVER_COLUMNS - rowUrls.size) { Box(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
    }

    saveError?.let { msg ->
        AbstandAlert("Save failed", onDismiss = { saveError = null }, message = msg)
    }
    coverApplyError?.let { msg ->
        AbstandAlert("Apply cover failed", onDismiss = { coverApplyError = null }, message = msg)
    }
    pendingCoverURL?.let { url ->
        AbstandDialog(
            title = "Apply this cover?",
            onDismiss = { pendingCoverURL = null },
            message = url,
            confirmLabel = "Apply",
            dismissOnConfirm = false,
            onConfirm = {
                scope.launch {
                    isApplyingCover = true
                    val failure = try { MetadataActions.applyCoverURL(itemId, url) } finally { isApplyingCover = false }
                    if (failure != null) {
                        coverApplyError = failure.ifEmpty { "Could not apply the cover. Check your connection and permissions." }
                    } else {
                        pendingCoverURL = null
                        onDismiss()
                    }
                }
            },
        )
    }
}

/** iOS: `seriesSuggestionsList`. */
@Composable
private fun SeriesSuggestionsList(names: List<String>, onPick: (String) -> Unit) {
    val palette = Theme.palette
    Column(
        Modifier.fillMaxWidth()
            .clip(MetadataSheetMetrics.fieldShape)
            .background(palette.background)
            .border(AppTheme.Layout.hairlineWidth, palette.textSecondary.copy(alpha = MetadataSheetMetrics.fieldBorderOpacity), MetadataSheetMetrics.fieldShape),
    ) {
        names.forEachIndexed { index, name ->
            Text(
                name, style = AppType.bodyMedium, color = palette.textPrimary,
                modifier = Modifier.fillMaxWidth().clickable { onPick(name) }
                    .padding(horizontal = MetadataSheetMetrics.fieldInsetH, vertical = AppTheme.Layout.rowVerticalPadding),
            )
            if (index < names.lastIndex) Box(Modifier.padding(horizontal = MetadataSheetMetrics.fieldInsetH)) { MetadataSheetCardDivider() }
        }
    }
}

private const val SERIES_SEARCH_DEBOUNCE_MS = 300L
/** iOS: 3-Spalten-Grid der Cover-Vorschau. */
private const val COVER_COLUMNS = 3
