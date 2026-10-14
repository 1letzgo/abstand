package de.letzgo.abstand.ui.metadata

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsItemMediaMetadataPatch
import de.letzgo.abstand.data.AbsMatchField
import de.letzgo.abstand.data.AbsMetadataMatch
import de.letzgo.abstand.data.AbsMetadataProvider
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandAlert
import de.letzgo.abstand.ui.components.AbstandCard
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandInlineNotice
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSheet
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.MetadataSheetCard
import de.letzgo.abstand.ui.components.MetadataSheetCardDivider
import de.letzgo.abstand.ui.components.MetadataSheetMenuPicker
import de.letzgo.abstand.ui.components.MetadataSheetMetrics
import de.letzgo.abstand.ui.components.MetadataSheetScaffold
import de.letzgo.abstand.ui.components.MetadataSheetSearchButton
import de.letzgo.abstand.ui.components.MetadataSheetSection
import de.letzgo.abstand.ui.components.MetadataSheetTextField
import de.letzgo.abstand.ui.components.MetadataSheetToggleRow
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** iOS: `MatchResultCoverMetrics`. */
private val MatchCoverWidth = 56.dp
private val MatchCoverHeight = 80.dp
/** Höhe des Leerzustands im Sheet. */
private val MatchEmptyHeight = 280.dp
/** Max. Höhe des Feld-Sheets (scrollt darunter). */
private val FieldSheetMaxHeight = 520.dp

/**
 * iOS: `MatchMetadataSheet` — Online-Suche (`/api/search/books`), Trefferliste, pro-Feld-Auswahl
 * vor dem Apply (`PATCH /api/items/:id/media` + optional Cover). Admin/Root-only.
 */
@Composable
fun MatchMetadataSheet(itemId: String, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var titleQuery by remember { mutableStateOf("") }
    var authorQuery by remember { mutableStateOf("") }
    var provider by remember { mutableStateOf("audible") }
    var providers by remember { mutableStateOf<List<AbsMetadataProvider>>(emptyList()) }
    var results by remember { mutableStateOf<List<AbsMetadataMatch>>(emptyList()) }
    var isSearching by remember { mutableStateOf(false) }
    var hasSearched by remember { mutableStateOf(false) }
    var searchError by remember { mutableStateOf<String?>(null) }
    var selectedMatch by remember { mutableStateOf<AbsMetadataMatch?>(null) }
    var selectedFields by remember { mutableStateOf(AbsMatchField.entries.toSet()) }
    var isApplying by remember { mutableStateOf(false) }
    var applyError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(itemId) {
        // iOS: `prefetchQueryFromCurrent` — Titel/Autor des Buchs vorbelegen.
        MetadataActions.loadItem(itemId)?.let { b ->
            if (titleQuery.isEmpty()) titleQuery = b.displayTitle
            if (authorQuery.isEmpty()) authorQuery = b.media.metadata.authorName.orEmpty()
        }
    }
    LaunchedEffect(Unit) {
        // Nicht fatal — Default-Provider bleibt.
        providers = runCatching { MetadataActions.loadMetadataProviders() }.getOrDefault(emptyList())
        if (providers.isNotEmpty() && providers.none { it.value == provider }) provider = providers.first().value
    }
    val availableProviders = providers.ifEmpty { listOf(AbsMetadataProvider(text = "Audible", value = "audible")) }

    fun runSearch() {
        val title = titleQuery.trim()
        if (title.isEmpty()) return
        scope.launch {
            isSearching = true
            searchError = null
            results = emptyList()
            hasSearched = false
            try {
                results = MetadataActions.searchMetadataBooks(title, authorQuery.trim().ifEmpty { null }, provider)
                hasSearched = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                searchError = e.message ?: "Search failed"
            } finally {
                isSearching = false
            }
        }
    }

    MetadataSheetScaffold(title = "Match Metadata", onCancel = onDismiss) {
        MetadataSheetSection("Search") {
            MetadataSheetCard {
                MetadataSheetTextField("Title", titleQuery, { titleQuery = it }, imeAction = ImeAction.Search, onSubmit = { runSearch() })
                MetadataSheetTextField("Author", authorQuery, { authorQuery = it }, imeAction = ImeAction.Search, onSubmit = { runSearch() })
                MetadataSheetMenuPicker(
                    title = "Provider",
                    selection = availableProviders.firstOrNull { it.value == provider } ?: availableProviders.first(),
                    options = availableProviders,
                    label = { it.text },
                    onSelect = { provider = it.value },
                )
                MetadataSheetSearchButton(onClick = { runSearch() }, enabled = titleQuery.isNotBlank() && !isSearching)
            }
        }
        when {
            isSearching -> AbstandLoadingSpinner()
            searchError != null -> MetadataSheetSection("Results") { MetadataSheetCard { AbstandInlineNotice(searchError!!, isError = true) } }
            results.isEmpty() -> AbstandEmptyScreen(
                title = if (hasSearched) "No matches found" else "Match metadata",
                icon = if (hasSearched) SF.magnifyingglass else SF.textMagnifyingglass,
                description = if (hasSearched) "Try another title, author or provider."
                else "Search a metadata provider, then pick which fields to apply to this book.",
                modifier = Modifier.height(MatchEmptyHeight),
            )
            else -> MetadataSheetSection("Results") {
                results.forEach { match ->
                    MatchCard(match) {
                        selectedFields = MatchLogic.availableFields(match).toSet()
                        selectedMatch = match
                    }
                }
            }
        }
    }

    selectedMatch?.let { match ->
        val fields = MatchLogic.availableFields(match)
        AbstandSheet(
            title = "Apply Match",
            onDismiss = { selectedMatch = null },
            onConfirm = {
                scope.launch {
                    isApplying = true
                    val failure = try {
                        MetadataActions.applyMetadataMatch(itemId, MatchLogic.patch(match, selectedFields), MatchLogic.coverURL(match, selectedFields))
                    } finally {
                        isApplying = false
                    }
                    if (failure != null) {
                        applyError = failure.ifEmpty { "Could not apply the selected fields. Check your connection and permissions." }
                    } else {
                        selectedMatch = null
                        onDismiss()
                    }
                }
            },
            confirmLabel = "Apply",
            confirmEnabled = selectedFields.isNotEmpty() && !isApplying,
            isBusy = isApplying,
            cancelLabel = "Cancel",
        ) {
            Column(
                Modifier.fillMaxWidth().height(FieldSheetMaxHeight).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.sectionSpacing),
            ) {
                MetadataSheetSection("Match") {
                    MetadataSheetCard(spacing = AppTheme.Layout.tightSpacing) {
                        Text(match.title ?: "—", style = IosType.subheadline.semibold, color = Theme.palette.textPrimary)
                        match.displayAuthors?.let { Text(it, style = IosType.footnote, color = Theme.palette.textSecondary) }
                    }
                }
                MetadataSheetSection("Fields") {
                    MetadataSheetCard(spacing = 0.dp) {
                        fields.forEachIndexed { idx, field ->
                            Box(Modifier.padding(vertical = AppTheme.Layout.rowVerticalPadding)) {
                                MetadataSheetToggleRow(
                                    title = field.label,
                                    subtitle = MatchLogic.previewText(field, match),
                                    subtitleMaxLines = 2,
                                    checked = field in selectedFields,
                                    onCheckedChange = { on -> selectedFields = if (on) selectedFields + field else selectedFields - field },
                                )
                            }
                            if (idx < fields.lastIndex) MetadataSheetCardDivider()
                        }
                    }
                }
            }
        }
    }

    applyError?.let { msg ->
        AbstandAlert("Apply failed", onDismiss = { applyError = null }, message = msg)
    }
}

@Composable
private fun MatchCard(match: AbsMetadataMatch, onClick: () -> Unit) {
    val palette = Theme.palette
    AbstandCard(Modifier.fillMaxWidth(), shape = MetadataSheetMetrics.cardShape, onClick = onClick) {
        Column(Modifier.padding(AppTheme.Layout.detailSectionCardPadding), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing), verticalAlignment = Alignment.Top) {
                Box(
                    Modifier.size(MatchCoverWidth, MatchCoverHeight).clip(RoundedCornerShape(AppTheme.Layout.chipCornerRadius)).background(palette.background),
                    contentAlignment = Alignment.Center,
                ) {
                    val url = match.displayCoverURL
                    if (url != null) {
                        CoverImage(url = url, cacheScopeId = "metadataMatch", requiresAuthorization = false, modifier = Modifier.size(MatchCoverWidth, MatchCoverHeight))
                    } else {
                        Icon(SF.book, contentDescription = null, tint = palette.textSecondary)
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
                    Text(match.title ?: "—", style = IosType.subheadline.semibold, color = palette.textPrimary, maxLines = 2)
                    match.displayAuthors?.let { Text(it, style = IosType.footnote, color = palette.textSecondary, maxLines = 1) }
                    match.displayNarrator?.let { Text("Narrated by $it", style = IosType.footnote, color = palette.textSecondary, maxLines = 1) }
                    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
                        match.displayYear?.let { Chip(it) }
                        match.publisher?.trim()?.takeIf { it.isNotEmpty() }?.let { Chip(it) }
                    }
                }
            }
            match.displaySeries?.let { Text(it, style = IosType.caption, color = palette.textSecondary, maxLines = 1) }
            match.displayDescription?.let { Text(it, style = IosType.caption, color = palette.textSecondary, maxLines = 2) }
        }
    }
}

@Composable
private fun Chip(text: String) {
    val palette = Theme.palette
    Text(
        text, style = IosType.caption2, color = palette.textSecondary, maxLines = 1,
        modifier = Modifier.clip(CircleShape).background(palette.background.copy(alpha = 0.6f))
            .padding(horizontal = AppTheme.Layout.inlineSpacing, vertical = AppTheme.Layout.tightSpacing),
    )
}

/** Reine Logik des Match-Sheets (testbar). */
object MatchLogic {
    /** iOS: `previewText(for:in:)` — leer, wenn der Treffer das Feld nicht liefert. */
    fun previewText(field: AbsMatchField, match: AbsMetadataMatch): String = when (field) {
        AbsMatchField.title -> match.title.orEmpty()
        AbsMatchField.subtitle -> match.subtitle.orEmpty()
        AbsMatchField.author -> match.displayAuthors.orEmpty()
        AbsMatchField.narrator -> match.displayNarrator.orEmpty()
        AbsMatchField.description -> match.displayDescription.orEmpty()
        AbsMatchField.publisher -> match.publisher.orEmpty()
        AbsMatchField.publishedYear -> match.displayYear.orEmpty()
        AbsMatchField.asin -> match.asin.orEmpty()
        AbsMatchField.isbn -> match.isbn.orEmpty()
        AbsMatchField.language -> match.language.orEmpty()
        AbsMatchField.genres -> match.genres.orEmpty().joinToString(", ")
        AbsMatchField.tags -> match.tags.orEmpty().joinToString(", ")
        AbsMatchField.series -> match.displaySeries.orEmpty()
        AbsMatchField.cover -> match.displayCoverURL.orEmpty()
    }

    /** iOS: `availableFields(for:)`. */
    fun availableFields(match: AbsMetadataMatch): List<AbsMatchField> = AbsMatchField.entries.filter { previewText(it, match).isNotEmpty() }

    /** iOS: `applyMatch` — Patch aus den gewählten Feldern. */
    fun patch(match: AbsMetadataMatch, fields: Set<AbsMatchField>): AbsItemMediaMetadataPatch {
        val p = AbsItemMediaMetadataPatch()
        if (AbsMatchField.title in fields) p.title = match.title
        if (AbsMatchField.subtitle in fields) p.subtitle = match.subtitle
        if (AbsMatchField.author in fields) match.displayAuthors?.let { a -> p.authorNames = a.split(",").map { it.trim() }.filter { it.isNotEmpty() } }
        if (AbsMatchField.narrator in fields) match.displayNarrator?.let { n -> p.narratorNames = n.split(",").map { it.trim() }.filter { it.isNotEmpty() } }
        if (AbsMatchField.description in fields) p.descriptionText = match.displayDescription
        if (AbsMatchField.publisher in fields) p.publisher = match.publisher
        if (AbsMatchField.publishedYear in fields) p.publishedYear = match.displayYear
        if (AbsMatchField.asin in fields) p.asin = match.asin
        if (AbsMatchField.isbn in fields) p.isbn = match.isbn
        if (AbsMatchField.language in fields) p.language = match.language
        if (AbsMatchField.genres in fields) p.genres = match.genres
        if (AbsMatchField.tags in fields) p.tags = match.tags
        if (AbsMatchField.series in fields) match.series?.let { s -> p.series = s.map { AbsItemMediaMetadataPatch.SeriesPayload(it.name, it.sequence) } }
        return p
    }

    fun coverURL(match: AbsMetadataMatch, fields: Set<AbsMatchField>): String? = if (AbsMatchField.cover in fields) match.cover else null
}
