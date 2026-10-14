package de.letzgo.abstand.ui.admin

import android.text.format.Formatter
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsLibraryDetailEnvelope
import de.letzgo.abstand.data.AbsLibraryEpisodeDownloadsPayload
import de.letzgo.abstand.data.AbsLibraryStatsResponse
import de.letzgo.abstand.data.AbsPodcastEpisodeDownload
import de.letzgo.abstand.model.AdminStore
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCard
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.AbstandInlineNotice
import de.letzgo.abstand.ui.components.AbstandInlineSpinner
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandMenu
import de.letzgo.abstand.ui.components.ServerAdminMetricTile
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardDivider
import de.letzgo.abstand.ui.components.SettingsSubpageScaffold
import de.letzgo.abstand.ui.components.abstandCardListRowFrame
import de.letzgo.abstand.ui.formatPlaybackDurationShortHuman
import de.letzgo.abstand.ui.medium
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/** iOS: `ServerLibrariesListView`. */
data object ServerLibrariesDestination : TabDestination {
    override val key = "admin/libraries"

    @Composable
    override fun Content(navigator: TabNavigator) = ServerLibrariesListScreen(navigator)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ServerLibrariesListScreen(navigator: TabNavigator, model: AppModel = AppModel.shared, admin: AdminStore = AdminStore.shared) {
    val session = model.session
    val libraries by session.libraries.collectAsState()
    val sorted = remember(libraries) { libraries.sortedBy { it.displayOrderOrZero } }
    var scanningId by remember { mutableStateOf<String?>(null) }
    var scanMessage by remember { mutableStateOf<String?>(null) }
    var menuFor by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { if (libraries.isEmpty()) session.reloadSettingsTab() }

    fun scan(lib: AbsLibrary) = scope.launch {
        scanningId = lib.id
        scanMessage = try {
            admin.scanServerLibrary(lib.id)
            "Scan started for ${lib.name}."
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            e.message
        } finally {
            scanningId = null
        }
    }

    AdminRefreshBox(onRefresh = { session.reloadSettingsTab() }) {
        SettingsSubpageScaffold(title = "Libraries", onBack = { navigator.pop() }) {
            if (sorted.isEmpty()) {
                item(key = "empty") {
                    AbstandEmptyScreen(
                        title = "No libraries", icon = SF.booksVertical, description = "No libraries on this server.",
                        modifier = Modifier.height(EmptyScreenHeight),
                    )
                }
            } else {
                scanMessage?.let { msg -> item(key = "scanMessage") { Text(msg, style = IosType.caption, color = Theme.palette.textSecondary) } }
                item(key = "libraries") {
                    ServerAdminSection("Libraries") {
                        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
                            sorted.forEach { lib ->
                                Box {
                                    // iOS: Kontextmenü „Scan“ → Android: langer Druck.
                                    AbstandCard(
                                        Modifier.fillMaxWidth().combinedClickable(
                                            onClick = { navigator.push(ServerLibraryDetailDestination(lib)) },
                                            onLongClick = { menuFor = lib.id },
                                        ),
                                    ) {
                                        Box(Modifier.fillMaxWidth().padding(horizontal = AppTheme.Layout.settingsCardInsetHPadding, vertical = AppTheme.Layout.settingsCardInsetVPadding)) {
                                            ServerLibraryListRow(lib, isScanning = scanningId == lib.id, admin = admin)
                                        }
                                    }
                                    AbstandMenu(expanded = menuFor == lib.id, onDismiss = { menuFor = null }) {
                                        item("Scan", { scan(lib) }, icon = SF.arrowClockwise)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** iOS: `ServerLibraryListRow` — lädt die Stats der Bibliothek für den Untertitel. */
@Composable
private fun ServerLibraryListRow(library: AbsLibrary, isScanning: Boolean, admin: AdminStore) {
    val palette = Theme.palette
    var stats by remember(library.id) { mutableStateOf<AbsLibraryStatsResponse?>(null) }
    var statsFailed by remember(library.id) { mutableStateOf(false) }
    LaunchedEffect(library.id) {
        if (stats != null || statsFailed) return@LaunchedEffect
        try {
            stats = admin.fetchServerLibraryStats(library.id)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            statsFailed = true
        }
    }
    val subtitle = AdminLibraryLogic.listSubtitle(library, stats)
    Row(
        Modifier.abstandCardListRowFrame(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        Box(Modifier.width(AppTheme.Layout.settingsIconColumnWidth), contentAlignment = Alignment.Center) {
            Icon(if (library.isPodcastLibrary) SF.micFill else SF.booksVerticalFill, contentDescription = null, tint = Theme.accent)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
            Text(library.name, style = IosType.body.medium, color = palette.textPrimary)
            Text(subtitle, style = IosType.caption, color = palette.textSecondary, maxLines = 2)
        }
        if (isScanning || (stats == null && !statsFailed)) {
            AbstandInlineSpinner()
        } else {
            Icon(SF.chevronRight, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(AppTheme.Layout.coverBadgeSize))
        }
    }
}

/** Reine Texte der Bibliotheks-Admin-Ansichten (testbar). */
object AdminLibraryLogic {
    /** iOS: `ServerLibraryListRow.subtitle`. */
    fun listSubtitle(library: AbsLibrary, stats: AbsLibraryStatsResponse?): String {
        if (stats == null) return library.mediaType?.replaceFirstChar { it.uppercase() } ?: "Library"
        val itemsLabel = if (library.isPodcastLibrary) "Shows" else "Items"
        val tracksLabel = if (library.isPodcastLibrary) "Audio files" else "Audio tracks"
        return "${stats.totalItems} $itemsLabel · ${formatPlaybackDurationShortHuman(stats.totalDuration)} · ${stats.numAudioTrack} $tracksLabel"
    }

    /** iOS: `episodeDownloadStatus`. */
    fun episodeDownloadStatus(row: AbsPodcastEpisodeDownload, payload: AbsLibraryEpisodeDownloadsPayload?): String = when {
        row.failed == true -> "Failed"
        row.isFinished == true -> "Finished"
        payload?.currentDownload?.id == row.id -> "Downloading"
        else -> "Queued"
    }
}

/** iOS: `ServerLibraryDetailView`. */
data class ServerLibraryDetailDestination(val library: AbsLibrary) : TabDestination {
    override val key = "admin/library/${library.id}"

    @Composable
    override fun Content(navigator: TabNavigator) = ServerLibraryDetailScreen(library, navigator)
}

@Composable
fun ServerLibraryDetailScreen(library: AbsLibrary, navigator: TabNavigator, admin: AdminStore = AdminStore.shared) {
    val context = LocalContext.current
    val palette = Theme.palette
    val isPodcast = library.isPodcastLibrary
    var stats by remember { mutableStateOf<AbsLibraryStatsResponse?>(null) }
    var detail by remember { mutableStateOf<AbsLibraryDetailEnvelope?>(null) }
    var episodeDownloads by remember { mutableStateOf<AbsLibraryEpisodeDownloadsPayload?>(null) }
    var loading by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var scanMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    suspend fun reload() {
        loading = true
        try {
            coroutineScope {
                val s = async { admin.fetchServerLibraryStats(library.id) }
                val d = async { admin.fetchServerLibraryDetail(library.id) }
                stats = s.await()
                detail = d.await()
            }
            loadError = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            loadError = e.message
        } finally {
            loading = false
        }
        // 404 oder nicht verfügbar → Sektion weglassen.
        episodeDownloads = if (isPodcast) runCatching { admin.fetchServerLibraryEpisodeDownloads(library.id) }.getOrNull() else null
    }
    LaunchedEffect(library.id) { reload() }

    AdminRefreshBox(onRefresh = { reload() }) {
        SettingsSubpageScaffold(
            title = library.name,
            onBack = { navigator.pop() },
            actions = {
                IconButton(onClick = {
                    scope.launch {
                        try {
                            admin.scanServerLibrary(library.id)
                            scanMessage = "Scan started."
                            loadError = null
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            scanMessage = null
                            loadError = e.message
                        }
                    }
                }) { Icon(SF.arrowClockwise, contentDescription = "Scan library") }
            },
        ) {
            scanMessage?.let { msg -> item(key = "scan") { Text(msg, style = IosType.caption, color = palette.textSecondary) } }
            val s = stats
            when {
                loading && s == null && detail == null -> item(key = "loading") { AbstandLoadingSpinner() }
                loadError != null && s == null && detail == null -> item(key = "error") { AbstandInlineNotice(loadError!!, isError = true) }
                else -> {
                    if (s != null) {
                        item(key = "overview") {
                            ServerAdminSection("Overview") {
                                val items = listOf(
                                    (if (isPodcast) "Shows" else "Items") to "${s.totalItems}",
                                    "Authors" to "${s.totalAuthors}",
                                    "Genres" to "${s.totalGenres}",
                                    "Duration" to formatPlaybackDurationShortHuman(s.totalDuration),
                                    "Size" to Formatter.formatFileSize(context, s.totalSize),
                                    (if (isPodcast) "Audio files" else "Audio tracks") to "${s.numAudioTrack}",
                                )
                                items.chunked(2).forEach { pair ->
                                    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
                                        pair.forEach { (label, value) -> ServerAdminMetricTile(value, label, Modifier.weight(1f)) }
                                    }
                                }
                            }
                        }
                        val genres = s.genresWithCount.sortedByDescending { it.count }.take(TOP_COUNT)
                        if (genres.isNotEmpty()) item(key = "genres") { RankedCard("Top Genres", genres.map { it.genre to "${it.count}" }) }
                        val authors = s.authorsWithCount.sortedByDescending { it.count }.take(TOP_COUNT)
                        if (authors.isNotEmpty()) item(key = "authors") { RankedCard("Top Authors", authors.map { it.name to "${it.count}" }) }
                        val longest = s.longestItems.take(TOP_ITEMS)
                        if (longest.isNotEmpty()) item(key = "longest") {
                            RankedCard("Longest Items", longest.map { it.title.ifEmpty { "Untitled" } to formatPlaybackDurationShortHuman(it.duration) }, valueSmall = true)
                        }
                        val largest = s.largestItems.take(TOP_ITEMS)
                        if (largest.isNotEmpty()) item(key = "largest") {
                            RankedCard("Largest Items", largest.map { it.title.ifEmpty { "Untitled" } to Formatter.formatFileSize(context, it.size) }, valueSmall = true)
                        }
                    }
                    val folders = detail?.library?.folders.orEmpty()
                    val provider = detail?.library?.provider?.trim()?.ifEmpty { null }
                    val issues = detail?.issues
                    if (folders.isNotEmpty() || provider != null || issues != null) {
                        item(key = "info") {
                            ServerAdminSection("Library Info") {
                                AbstandGroupedCard {
                                    var first = true
                                    fun divider() = if (first) { first = false; false } else true
                                    issues?.let { if (divider()) SettingsCardDivider(); MetaRow("Issues", "$it") }
                                    provider?.let { if (divider()) SettingsCardDivider(); MetaRow("Provider", it) }
                                    folders.forEach { f -> if (divider()) SettingsCardDivider(); MetaRow("Folder", f.fullPath) }
                                }
                            }
                        }
                    }
                    val rows = episodeDownloads?.allRows.orEmpty()
                    if (isPodcast && rows.isNotEmpty()) {
                        item(key = "episodeDownloads") {
                            ServerAdminSection("Episode Downloads") {
                                AbstandGroupedCard {
                                    rows.forEachIndexed { index, row ->
                                        if (index > 0) SettingsCardDivider()
                                        Column(Modifier.abstandCardListRowFrame(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing, Alignment.CenterVertically)) {
                                            Text(row.episodeDisplayTitle ?: "Episode", style = IosType.body.medium, color = palette.textPrimary, maxLines = 2)
                                            Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing)) {
                                                row.podcastTitle?.takeIf { it.isNotEmpty() }?.let {
                                                    Text(it, style = IosType.caption, color = palette.textSecondary, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                                                }
                                                Box(Modifier.weight(1f))
                                                Text(
                                                    AdminLibraryLogic.episodeDownloadStatus(row, episodeDownloads),
                                                    style = IosType.caption.semibold, color = palette.textSecondary,
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RankedCard(title: String, rows: List<Pair<String, String>>, valueSmall: Boolean = false) {
    val palette = Theme.palette
    ServerAdminSection(title) {
        AbstandGroupedCard {
            rows.forEachIndexed { index, (name, value) ->
                if (index > 0) SettingsCardDivider()
                Row(
                    Modifier.abstandCardListRowFrame(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing),
                ) {
                    Text(name, style = IosType.body, color = palette.textPrimary, maxLines = if (valueSmall) 2 else 1, modifier = Modifier.weight(1f))
                    Text(value, style = if (valueSmall) IosType.caption.semibold else IosType.subheadline.semibold, color = palette.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun MetaRow(title: String, value: String) {
    val palette = Theme.palette
    Row(Modifier.abstandCardListRowFrame(), horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = IosType.subheadline, color = palette.textSecondary, modifier = Modifier.width(ServerAdminLayoutMetrics.compactMetaLabelColumnWidth))
        Text(value, style = IosType.subheadline.medium, color = palette.textPrimary, modifier = Modifier.weight(1f))
    }
}

/** iOS: Top-Genres/-Autoren `prefix(8)`, Longest/Largest `prefix(5)`. */
private const val TOP_COUNT = 8
private const val TOP_ITEMS = 5
