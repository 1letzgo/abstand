package de.letzgo.abstand.ui.podcasts

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.AbsPodcastEpisodeExpandedDetail
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.data.absPlainText
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.PodcastStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandConfirmDialog
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.DetailScaffold
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.formatPlaybackTime
import java.text.SimpleDateFormat
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandProgressRing

/** Navigationsziel: Folgen-Detail (iOS: `navigationDestination(item: $podcastDetailEpisode)`). */
class PodcastEpisodeDetailDestination(val episode: AbsPodcastEpisodeListItem) : TabDestination {
    override val key: String = "podcast-episode/${episode.progressLookupKey}"

    @Composable
    override fun Content(navigator: TabNavigator) {
        PodcastEpisodeDetailView(episode, navigator)
    }
}

/** Bestätigungsdialoge der Detailseite. */
private enum class EpisodeConfirm { discard, finish, unfinish }

/**
 * iOS: `PodcastEpisodeDetailView` — Hero (Show-Cover, Folgentitel, Sendung als Link, Dauer · Jahr),
 * Play-/Fertig-Aktionen, Meta-Karten (Beschreibung, Hosts, Untertitel, Veröffentlicht, Kategorien,
 * Show notes) und die Hörhistorie. Toolbar: Teilen, Download, Fortschritt zurücksetzen.
 * HTML aus dem Feed wird über [absPlainText] zu Klartext.
 */
@Composable
fun PodcastEpisodeDetailView(
    episode: AbsPodcastEpisodeListItem,
    navigator: TabNavigator,
    store: PodcastStore = AppModel.shared.podcasts,
) {
    val session = AppModel.shared.session
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val progressMap by store.progressByItemId.collectAsState()
    val reachable by session.isNetworkReachable.collectAsState()
    val serverURL by session.serverURL.collectAsState()
    val actions = store.actions
    val revision by actions.revision.collectAsState()
    val prog = progressMap[episode.progressLookupKey]
    val isFinished = prog?.isFinished == true

    var detail by remember { mutableStateOf<AbsPodcastEpisodeExpandedDetail?>(null) }
    var sessions by remember { mutableStateOf<List<AbsListeningSession>>(emptyList()) }
    var sessionsLoaded by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<EpisodeConfirm?>(null) }
    val descriptionExpanded = remember { mutableStateOf(false) }
    val showNotesExpanded = remember { mutableStateOf(false) }
    val sessionsExpanded = remember { mutableStateOf(false) }

    LaunchedEffect(episode.progressLookupKey) {
        // Sofort mit gecachtem Show-Detail starten, dann still aktualisieren.
        if (detail == null) detail = store.cachedPodcastEpisodeDetail(episode)
        coroutineScope {
            val d = async { store.loadPodcastEpisodeDetail(episode) }
            val s = async { store.loadPodcastEpisodeListeningSessions(episode) }
            detail = d.await()
            sessions = s.await()
            sessionsLoaded = true
        }
    }

    val total = resolvedEpisodeDuration(episode, prog)
    val progress01 = when {
        prog == null -> 0.0
        prog.isFinished -> 1.0
        prog.duration > 0 -> prog.progress.coerceIn(0.0, 1.0)
        total > 0 -> (prog.currentTime / total).coerceIn(0.0, 1.0)
        else -> 0.0
    }
    val canDiscard = prog != null && (prog.isFinished || prog.currentTime > 1 || (prog.duration > 0 && prog.progress > 0.001))
    val lid = episode.libraryItemId
    val eid = episode.episodeId
    @Suppress("UNUSED_VARIABLE") val rev = revision
    val isPlaying = actions.isPlaying(lid, eid)
    val isDownloaded = actions.isDownloaded(lid, eid)
    val downloadProgress = actions.downloadProgress(lid, eid)
    val shareUrl = AbsApiClient.normalizeServerURL(serverURL)?.let { base -> lid.swiftTrim().ifEmpty { null }?.let { "${base.trimEnd('/')}/item/$it" } }
    val showName = episode.showTitle.swiftTrim().takeIf { it.isNotEmpty() && it != "—" }

    DetailScaffold(
        onBack = { navigator.pop() },
        actions = {
            if (shareUrl != null) {
                AbstandIconButton(
                    SF.squareAndArrowUp,
                    "Share",
                    onClick = {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_SUBJECT, episode.episodeTitle)
                            putExtra(Intent.EXTRA_TEXT, shareUrl)
                        }
                        runCatching { context.startActivity(Intent.createChooser(send, null)) }
                    },
                )
            }
            // iOS: `DetailToolbarDownloadItem`.
            when {
                downloadProgress != null && !isDownloaded -> AbstandIconButton(onClick = { actions.removeDownload(lid, eid) }, "Cancel download") {
                    AbstandProgressRing(downloadProgress, size = ToolbarProgressSize)
                }
                isDownloaded -> AbstandIconButton(
                    SF.arrowDownCircleBadgeXmark,
                    "Remove download",
                    onClick = { actions.removeDownload(lid, eid) },
                )
                else -> AbstandIconButton(SF.arrowDownCircle, "Download", onClick = { actions.enqueueDownload(episode) })
            }
            AbstandIconButton(
                SF.arrowCounterclockwise,
                "Reset progress",
                onClick = { confirm = EpisodeConfirm.discard },
                enabled = canDiscard && reachable,
                tint = if (canDiscard && reachable) AppTheme.danger else Theme.palette.textSecondary,
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.tabPaddingH,
                top = padding.calculateTopPadding() + AppTheme.Layout.withinSectionSpacing,
                bottom = padding.calculateBottomPadding(),
            ),
            verticalArrangement = Arrangement.spacedBy(PodcastDetailMetrics.sectionCardSpacing),
        ) {
            item(key = "hero") {
                Column {
                    PodcastDetailHeroCover { SquareCoverImage(itemId = lid, tier = CoverImageTier.hero, modifier = Modifier.fillMaxSize()) }
                    PodcastDetailHeroInfo(
                        title = episode.episodeTitle,
                        subtitle = showName,
                        tertiaryParts = listOf(if (total > 0) formatPlaybackTime(total) else "—", publishedYearLabel(detail?.pubDate)),
                        onSubtitleClick = if (showName != null) {
                            {
                                // iOS: `openPodcastShowCatalog` — Podcasts-Tab mit dieser Sendung;
                                // Android: Home-Bibliotheksleiste (Podcast-Bibliothek + Sendung).
                                navigator.popToRoot()
                                session.showPodcastLibraryOnHome(session.activePodcastLibraries.firstOrNull { it.id == episode.libraryId })
                                store.selectStripSection(lid)
                            }
                        } else null,
                    )
                }
            }
            val d = detail ?: return@LazyColumn
            item(key = "actions") {
                Column(Modifier.padding(bottom = AppTheme.Layout.detailMetaAfterPlaySpacing)) {
                    PodcastDetailPlayActions(
                        isPlaying = isPlaying,
                        isFinished = isFinished,
                        progress01 = progress01,
                        onMark = { confirm = if (isFinished) EpisodeConfirm.unfinish else EpisodeConfirm.finish },
                        onPrimary = {
                            if (isPlaying) actions.pause() else actions.play(episode, resumeAt = if (isFinished) 0.0 else null)
                        },
                    )
                }
            }
            absPlainText(d.episodeDescriptionHTML).ifEmpty { null }?.let { text ->
                item(key = "description") {
                    PodcastDetailSectionCard { PodcastDetailMetaField("Description") { PodcastDetailExpandableText(text, descriptionExpanded) } }
                }
            }
            if (d.showAuthors.isNotEmpty()) {
                item(key = "hosts") {
                    PodcastDetailSectionCard {
                        PodcastDetailMetaField(if (d.showAuthors.size == 1) "Host" else "Hosts", icon = SF.personFill) {
                            d.showAuthors.forEach { PodcastDetailMetaText(it.name) }
                        }
                    }
                }
            }
            trimmedMetaValue(d.subtitle)?.let { subtitle ->
                item(key = "subtitle") {
                    PodcastDetailSectionCard { PodcastDetailMetaField("Subtitle") { PodcastDetailMetaText(subtitle) } }
                }
            }
            episodePublishedDateLabel(d.pubDate)?.let { published ->
                item(key = "published") {
                    PodcastDetailSectionCard { PodcastDetailMetaField("Published", icon = SF.calendar) { PodcastDetailMetaText(published) } }
                }
            }
            val categories = (d.showGenres ?: emptyList()).map { it.swiftTrim() }.filter { it.isNotEmpty() }
            if (categories.isNotEmpty()) {
                item(key = "categories") {
                    PodcastDetailSectionCard { PodcastDetailMetaField("Categories", icon = SF.tag) { PodcastDetailMetaText(categories.joinToString(", ")) } }
                }
            }
            absPlainText(d.showDescriptionHTML).ifEmpty { null }?.let { notes ->
                item(key = "show-notes") {
                    PodcastDetailSectionCard { PodcastDetailMetaField("Show notes") { PodcastDetailExpandableText(notes, showNotesExpanded) } }
                }
            }
            item(key = "history") {
                PodcastDetailDisclosure("Listening history", sessionsExpanded) {
                    when {
                        !sessionsLoaded -> AbstandSectionEmptyState("Loading…")
                        sessions.isEmpty() -> AbstandSectionEmptyState(
                            if (reachable) "No listening sessions recorded for this episode yet." else "No listening history cached yet.",
                        )
                        else -> sessions.forEach { s ->
                            de.letzgo.abstand.ui.detail.ListeningHistoryRow(s) { actions.play(episode, resumeAt = s.startTime) } // iOS: dieselbe `ListeningHistoryRow`
                        }
                    }
                }
            }
        }
    }

    when (confirm) {
        EpisodeConfirm.discard -> ConfirmDialog(
            title = "Reset listening progress?",
            message = "This removes your saved position and listening sessions for this episode. You cannot undo this.",
            confirmLabel = "Reset",
            destructive = true,
            onDismiss = { confirm = null },
        ) {
            scope.launch {
                store.discardPodcastEpisodeProgress(episode)
                sessions = store.loadPodcastEpisodeListeningSessions(episode)
            }
        }
        EpisodeConfirm.finish -> ConfirmDialog(
            title = "Mark as finished?",
            message = "Your current position will be saved as complete.",
            confirmLabel = "Mark as finished",
            onDismiss = { confirm = null },
        ) { scope.launch { store.markPodcastEpisodeFinished(episode) } }
        EpisodeConfirm.unfinish -> ConfirmDialog(
            title = "Mark as not finished?",
            message = "You can resume from your saved position.",
            confirmLabel = "Mark as not finished",
            onDismiss = { confirm = null },
        ) { scope.launch { store.markPodcastEpisodeUnfinished(episode) } }
        null -> {}
    }
}

private val ToolbarProgressSize = 20.dp

@Composable
private fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    onDismiss: () -> Unit,
    destructive: Boolean = false,
    onConfirm: () -> Unit,
) {
    AbstandConfirmDialog(title, confirmLabel, onConfirm, onDismiss, message = message, destructive = destructive)
}

private fun trimmedMetaValue(value: String?): String? {
    val t = value?.swiftTrim() ?: return null
    return if (t.isEmpty() || t == "—") null else t
}

/** iOS: `episodePublishedDateLabel` — Veröffentlichungsdatum ohne Uhrzeit. */
internal fun episodePublishedDateLabel(raw: String?): String? {
    val value = trimmedMetaValue(raw) ?: return null
    val prefix = value.take(10)
    if (Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(prefix)) return prefix
    parseEpisodePublicationDate(value)?.let { return dateLabelMillis(it) }
    value.indexOf('T').takeIf { it > 0 }?.let { t -> value.substring(0, t).swiftTrim().ifEmpty { null }?.let { return it } }
    val space = value.indexOf(' ')
    if (space > 0 && value.substring(space).contains(':')) value.substring(0, space).swiftTrim().ifEmpty { null }?.let { return it }
    return value
}

/** Hero: nur das Jahr, wenn ein Kalenderdatum erkannt wurde. */
private fun publishedYearLabel(raw: String?): String {
    val label = episodePublishedDateLabel(raw) ?: return ""
    return if (label.length >= 4 && label.take(4).all { it.isDigit() }) label.take(4) else label
}

private fun parseEpisodePublicationDate(raw: String): Long? {
    runCatching { return OffsetDateTime.parse(raw, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant().toEpochMilli() }
    val formats = listOf(
        "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss", "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z",
    )
    for (f in formats) {
        val df = SimpleDateFormat(f, Locale.US).apply { isLenient = false }
        runCatching { df.parse(raw) }.getOrNull()?.let { return it.time }
    }
    return null
}
