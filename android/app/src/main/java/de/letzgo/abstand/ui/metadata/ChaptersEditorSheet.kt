package de.letzgo.abstand.ui.metadata

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsAudibleChaptersResponse
import de.letzgo.abstand.data.AbsItemChaptersPayload
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandInlineNotice
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.MetadataSheetCard
import de.letzgo.abstand.ui.components.MetadataSheetCardDivider
import de.letzgo.abstand.ui.components.MetadataSheetMenuPicker
import de.letzgo.abstand.ui.components.MetadataSheetScaffold
import de.letzgo.abstand.ui.components.MetadataSheetSearchButton
import de.letzgo.abstand.ui.components.MetadataSheetSection
import de.letzgo.abstand.ui.components.MetadataSheetTextField
import de.letzgo.abstand.ui.components.MetadataSheetToggleRow
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.medium
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** iOS: `ChapterPreviewRowMetrics.indexColumnWidth`. */
private val IndexColumnWidth = 24.dp
private val ChaptersEmptyHeight = 280.dp

/**
 * iOS: `ChaptersEditorSheet` — Audible-Kapitel per ASIN (`/api/search/chapters`), Vorschau mit
 * optionaler Branding-Entfernung, Apply über `POST /api/items/:id/chapters`. Admin/Root-only.
 */
@Composable
fun ChaptersEditorSheet(itemId: String, onDismiss: () -> Unit) {
    val palette = Theme.palette
    val scope = rememberCoroutineScope()
    var asinInput by remember { mutableStateOf("") }
    var region by remember { mutableStateOf("us") }
    var mediaDuration by remember { mutableStateOf<Double?>(null) }
    var response by remember { mutableStateOf<AbsAudibleChaptersResponse?>(null) }
    var isSearching by remember { mutableStateOf(false) }
    var lookupError by remember { mutableStateOf<String?>(null) }
    var removeBranding by remember { mutableStateOf(false) }
    var isApplying by remember { mutableStateOf(false) }
    var applyError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(itemId) {
        // iOS: `prefetchASIN` — ASIN vorbelegen, Region einmalig aus der Buchsprache wählen.
        val book = MetadataActions.loadItem(itemId) ?: return@LaunchedEffect
        mediaDuration = book.media.duration
        if (asinInput.isEmpty()) asinInput = book.media.metadata.asin.orEmpty()
        MetadataLogic.audibleRegion(book.media.metadata.language)
            ?.takeIf { r -> MetadataLogic.audibleRegions.any { it.first == r } }
            ?.let { region = it }
    }

    fun runLookup() {
        val asin = asinInput.trim()
        if (asin.isEmpty()) return
        scope.launch {
            isSearching = true
            lookupError = null
            response = null
            try {
                response = MetadataActions.searchAudibleChapters(asin, region)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                lookupError = e.message ?: "Lookup failed"
            } finally {
                isSearching = false
            }
        }
    }

    val preview = MetadataLogic.previewChapters(response, mediaDuration, removeBranding)
    val hasChapters = response?.chapters?.isNotEmpty() == true

    MetadataSheetScaffold(
        title = "Edit Chapters",
        onCancel = onDismiss,
        onConfirm = if (hasChapters) {
            {
                scope.launch {
                    if (preview.isEmpty()) return@launch
                    isApplying = true
                    val payload = preview.mapIndexed { idx, ch -> AbsItemChaptersPayload.Chapter(idx, ch.start, ch.end, ch.title) }
                    val failure = try { MetadataActions.applyItemChapters(itemId, payload) } finally { isApplying = false }
                    if (failure != null) applyError = failure.ifEmpty { "Could not apply the chapters. Check your connection and permissions." } else onDismiss()
                }
            }
        } else null,
        confirmLabel = "Apply",
        confirmEnabled = !isApplying,
        isBusy = isApplying,
    ) {
        MetadataSheetSection("Lookup") {
            MetadataSheetCard {
                MetadataSheetTextField(
                    "Audible ASIN", asinInput, { asinInput = it },
                    placeholder = "e.g. B08XYZ1234",
                    capitalization = KeyboardCapitalization.Characters, autoCorrect = false,
                    imeAction = ImeAction.Search, onSubmit = { runLookup() },
                )
                MetadataSheetMenuPicker(
                    title = "Region",
                    selection = MetadataLogic.audibleRegions.firstOrNull { it.first == region } ?: MetadataLogic.audibleRegions.first(),
                    options = MetadataLogic.audibleRegions,
                    label = { it.second },
                    onSelect = { region = it.first },
                )
                MetadataSheetSearchButton(onClick = { runLookup() }, enabled = asinInput.isNotBlank() && !isSearching)
            }
        }
        val serverError = response?.error
        when {
            isSearching -> AbstandLoadingSpinner()
            lookupError != null -> MetadataSheetSection("Chapters") { MetadataSheetCard { AbstandInlineNotice(lookupError!!, isError = true) } }
            serverError != null -> MetadataSheetSection("Chapters") { MetadataSheetCard { AbstandInlineNotice(serverError, isError = true) } }
            hasChapters -> MetadataSheetSection("Chapters") {
                val resp = response!!
                // Branding-Schalter nur, wenn der Server Branding-Dauern liefert.
                if (resp.brandIntroDurationMs != null || resp.brandOutroDurationMs != null) {
                    MetadataSheetCard {
                        MetadataSheetToggleRow(
                            title = "Remove branding",
                            subtitle = "Strip Audible intro/outro from chapter timings.",
                            checked = removeBranding,
                            onCheckedChange = { removeBranding = it },
                        )
                    }
                }
                MetadataSheetCard(spacing = AppTheme.Layout.withinSectionSpacing) {
                    Text(if (preview.size == 1) "1 chapter" else "${preview.size} chapters", style = IosType.caption.medium, color = palette.textSecondary)
                    Column {
                        preview.forEachIndexed { idx, ch ->
                            Row(
                                Modifier.padding(vertical = AppTheme.Layout.rowVerticalPadding),
                                horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
                                verticalAlignment = Alignment.Top,
                            ) {
                                Text("${idx + 1}", style = IosType.caption, color = palette.textSecondary, modifier = Modifier.width(IndexColumnWidth))
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing)) {
                                    Text(ch.title.ifEmpty { "Chapter ${idx + 1}" }, style = IosType.subheadline, color = palette.textPrimary, maxLines = 2)
                                    Text("${formatPlaybackTime(ch.start)} – ${formatPlaybackTime(ch.end)}", style = IosType.caption, color = palette.textSecondary)
                                }
                            }
                            if (idx < preview.lastIndex) MetadataSheetCardDivider()
                        }
                    }
                }
            }
            else -> AbstandEmptyScreen(
                title = "Fetch chapters",
                icon = SF.listBulletBelowRectangle,
                description = "Enter an Audible ASIN to fetch chapter timings for this book.",
                modifier = Modifier.height(ChaptersEmptyHeight),
            )
        }
    }

    applyError?.let { msg ->
        AlertDialog(
            onDismissRequest = { applyError = null },
            title = { Text("Apply failed") }, text = { Text(msg) },
            confirmButton = { TextButton(onClick = { applyError = null }) { Text("OK") } },
        )
    }
}
