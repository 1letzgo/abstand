package de.letzgo.abstand.ui.podcasts

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsPodcastDirectorySearchHit
import de.letzgo.abstand.data.AbsPodcastFeedPreviewEpisode
import de.letzgo.abstand.data.absPlainText
import de.letzgo.abstand.data.swiftCapitalized
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.PodcastStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandAlert
import de.letzgo.abstand.ui.components.AbstandInlineNotice
import de.letzgo.abstand.ui.components.AbstandInlineSpinner
import de.letzgo.abstand.ui.components.AbstandPrimaryButton
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.CoverImageContentMode
import de.letzgo.abstand.ui.components.DetailScaffold
import de.letzgo.abstand.ui.formatPlaybackDurationShortHuman
import java.text.DateFormat
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date
import kotlinx.coroutines.launch
import de.letzgo.abstand.ui.components.AbstandIconButton

/** Navigationsziel: Sendungsvorschau aus dem „Add podcast“-Flow (iOS: `navigationDestination(item: $previewHit)`). */
class PodcastDirectoryShowDestination(val hit: AbsPodcastDirectorySearchHit) : TabDestination {
    override val key: String = "podcast-directory/${hit.id}"

    @Composable
    override fun Content(navigator: TabNavigator) {
        PodcastDirectoryShowView(hit, onBack = { navigator.pop() })
    }
}

/** Erste Seite der Folgenliste — lange Feeds (oft 500+) bleiben flüssig. */
private const val InitialEpisodeCount = 20

/**
 * iOS: `PodcastDirectoryShowView` — Sendungsdetail einer (noch) nicht abonnierten Sendung:
 * Hero (Cover, Titel, Host, „128 episodes · Latest … · Explicit“), Subscribe bzw. „In library“,
 * Meta-Karten (Beschreibung, Kategorien, Feed-Details, Apple-Podcasts-Link) und — nach dem
 * Abonnieren, für Server-Verwalter — die Feed-Folgen mit Einzel-Download auf den Server.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PodcastDirectoryShowView(hit: AbsPodcastDirectorySearchHit, onBack: () -> Unit, store: PodcastStore = AppModel.shared.podcasts) {
    val palette = Theme.palette
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val dir by store.directory.collectAsState()
    val shows by store.podcastShows.collectAsState()
    val reachable by AppModel.shared.session.isNetworkReachable.collectAsState()
    val isRoot by AppModel.shared.session.isServerRoot.collectAsState()
    val isAdmin by AppModel.shared.session.isServerAdmin.collectAsState()
    val descriptionExpanded = remember { mutableStateOf(false) }
    val episodesExpanded = remember { mutableStateOf(true) }
    var showsAllEpisodes by rememberSaveable { mutableStateOf(false) }
    var expandedEpisodeIds by remember { mutableStateOf(emptySet<String>()) }
    var subscribeError by remember { mutableStateOf<String?>(null) }
    var refreshing by remember { mutableStateOf(false) }

    val feedKey = store.podcastDirectoryPreviewKey(hit)
    val preview = feedKey?.let { dir.previewByFeedURL[it] }
    val isLoading = feedKey != null && feedKey in dir.previewLoadingFeedURLs
    val loadError = if (feedKey == null) "This result has no RSS feed URL, so its episodes cannot be loaded." else dir.previewErrorByFeedURL[feedKey]
    val libraryShow = remember(shows, hit) { store.podcastLibraryShowMatchingDirectoryHit(hit) }
    val isInLibrary = libraryShow != null
    val isSubscribing = dir.subscribeInProgressHitId == hit.id
    val canDownloadEpisodes = isRoot || isAdmin

    // Feed erst nach dem Abonnieren laden — vorher reichen die Verzeichnisdaten für die Seite.
    LaunchedEffect(libraryShow?.id) {
        if (libraryShow == null) return@LaunchedEffect
        store.loadPodcastDirectoryPreview(hit)
        store.loadPodcastDirectoryLibraryEpisodeTitles(hit)
    }

    val displayTitle = preview?.title?.swiftTrim()?.ifEmpty { null } ?: hit.title.swiftTrim().ifEmpty { "Podcast" }
    val displayAuthor = (preview?.author ?: hit.artistName)?.swiftTrim()?.ifEmpty { null }
    val coverUrl = preview?.imageUrl ?: hit.cover
    val episodeCount = preview?.takeIf { it.episodes.isNotEmpty() }?.episodeCount ?: hit.trackCount?.takeIf { it > 0 }
    val latestLabel = preview?.latestEpisodePublishedAt?.takeIf { it > 0 }?.let { dateLabelMillis(it) }
        ?: hit.releaseDate?.let { dateLabelIsoDay(it) }
    val heroTertiary = buildList {
        episodeCount?.let { add(if (it == 1) "1 episode" else "$it episodes") }
        latestLabel?.let { add("Latest $it") }
        if (preview?.explicit ?: hit.explicit ?: false) add("Explicit")
    }
    val aboutText = preview?.descriptionPlain?.takeIf { it.isNotEmpty() } ?: absPlainText(hit.descriptionPlain).ifEmpty { null }
    val categories = preview?.categories?.takeIf { it.isNotEmpty() }
        ?: (hit.genres ?: emptyList()).map { it.swiftTrim() }.filter { it.isNotEmpty() }
    val pageUrl = preview?.pageUrl ?: hit.pageUrl
    val detailRows = buildList {
        preview?.language?.takeIf { it.isNotEmpty() }?.let { add("Language" to it) }
        preview?.type?.takeIf { it.isNotEmpty() }?.let { add("Feed type" to swiftCapitalized(it)) }
        preview?.totalDurationSeconds?.takeIf { it > 0 }?.let { add("Total runtime" to formatPlaybackDurationShortHuman(it)) }
        hit.releaseDate?.takeIf { it.isNotEmpty() }?.let { r -> dateLabelIsoDay(r)?.let { add("First release" to it) } }
        (preview?.feedUrl ?: hit.feedUrl)?.takeIf { it.isNotEmpty() }?.let { add("RSS feed" to it) }
    }
    val showsEpisodeList = isInLibrary && canDownloadEpisodes

    DetailScaffold(onBack = onBack) { padding ->
        PodcastPullToRefresh(
            refreshing = refreshing,
            onRefresh = {
                if (isInLibrary) {
                    scope.launch {
                        refreshing = true
                        store.loadPodcastDirectoryPreview(hit, forceReload = true)
                        refreshing = false
                    }
                }
            },
            topInset = padding.calculateTopPadding(),
        ) {
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
                        PodcastDetailHeroCover {
                            CoverImage(
                                url = coverUrl,
                                cacheScopeId = "podcast-dir:${hit.id}",
                                requiresAuthorization = false,
                                contentMode = CoverImageContentMode.Fit,
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                        PodcastDetailHeroInfo(displayTitle, displayAuthor, heroTertiary)
                    }
                }
                item(key = "subscribe") {
                    Column(
                        Modifier.fillMaxWidth().padding(
                            top = AppTheme.Layout.detailPlayButtonTopPadding,
                            bottom = AppTheme.Layout.detailPlayButtonBottomPadding + AppTheme.Layout.detailMetaAfterPlaySpacing,
                        ),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(PodcastDetailMetrics.linkRowSpacing),
                    ) {
                        if (isInLibrary) {
                            PodcastInLibraryLabel(AppType.titleSmall)
                        } else {
                            val hasFeed = !hit.feedUrl.isNullOrBlank()
                            AbstandPrimaryButton(
                                text = if (isSubscribing) "Subscribing…" else "Subscribe",
                                onClick = {
                                    scope.launch {
                                        val failure = store.subscribeToPodcastDirectoryHitReportingError(hit)
                                        if (!failure.isNullOrEmpty()) subscribeError = failure
                                    }
                                },
                                icon = SF.plusCircleFill,
                                enabled = hasFeed && reachable,
                                isBusy = isSubscribing,
                                modifier = Modifier.fillMaxWidth(PodcastDetailMetrics.singlePrimaryWidthFraction),
                            )
                            Text(
                                when {
                                    !hasFeed -> "This result has no RSS feed URL and cannot be added."
                                    !reachable -> "Connect to your server to add this show."
                                    else -> "Adds the show to your Audiobookshelf library and downloads new episodes automatically."
                                },
                                style = AppType.bodySmall, color = palette.textSecondary, textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
                // Feed-Fehler (kein Spinner: der Feed liefert nur Zusatzdetails).
                if (preview == null && !isLoading && loadError != null && isInLibrary) {
                    item(key = "feed-error") {
                        PodcastDetailSectionCard {
                            PodcastDetailMetaField("Feed") {
                                AbstandInlineNotice(loadError, isError = true)
                                AbstandProminentButton(
                                    text = "Try again",
                                    onClick = { scope.launch { store.loadPodcastDirectoryPreview(hit, forceReload = true) } },
                                    enabled = reachable,
                                )
                            }
                        }
                    }
                }
                aboutText?.let { about ->
                    item(key = "about") {
                        PodcastDetailSectionCard { PodcastDetailMetaField("Description") { PodcastDetailExpandableText(about, descriptionExpanded) } }
                    }
                }
                if (categories.isNotEmpty()) {
                    item(key = "categories") {
                        PodcastDetailSectionCard { PodcastDetailMetaField("Categories") { PodcastDetailMetaText(categories.joinToString(", ")) } }
                    }
                }
                if (detailRows.isNotEmpty()) {
                    item(key = "details") {
                        PodcastDetailSectionCard {
                            detailRows.forEach { (title, value) -> PodcastDetailMetaField(title) { PodcastDetailMetaText(value) } }
                        }
                    }
                }
                if (!pageUrl.isNullOrBlank()) {
                    item(key = "links") {
                        PodcastDetailSectionCard {
                            PodcastDetailMetaField("Links") {
                                Text(
                                    "Open in Apple Podcasts",
                                    style = AppType.titleMedium,
                                    color = Theme.accent,
                                    modifier = Modifier.clickable {
                                        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(pageUrl))) }
                                    },
                                )
                            }
                        }
                    }
                }
                if (showsEpisodeList && preview != null && preview.episodes.isNotEmpty()) {
                    item(key = "episodes") {
                        PodcastDetailDisclosure("Episodes", episodesExpanded) {
                            val episodes = if (!showsAllEpisodes && preview.episodes.size > InitialEpisodeCount) {
                                preview.episodes.take(InitialEpisodeCount)
                            } else {
                                preview.episodes
                            }
                            Column {
                                episodes.forEachIndexed { idx, episode ->
                                    val expanded = episode.id in expandedEpisodeIds
                                    FeedEpisodeRow(
                                        episode = episode,
                                        expanded = expanded,
                                        onToggleExpanded = {
                                            expandedEpisodeIds = if (expanded) expandedEpisodeIds - episode.id else expandedEpisodeIds + episode.id
                                        },
                                        trailing = { FeedEpisodeDownloadControl(store, hit, episode, dir.episodeDownloadInProgressKeys, reachable) },
                                    )
                                    if (idx < episodes.size - 1) HorizontalDivider(color = palette.textSecondary.copy(alpha = 0.15f))
                                }
                                if (preview.episodes.size > InitialEpisodeCount) {
                                    Text(
                                        if (showsAllEpisodes) "Show fewer episodes" else "Show all ${preview.episodes.size} episodes",
                                        style = AppType.titleSmall,
                                        color = Theme.accent,
                                        modifier = Modifier.padding(top = PodcastDetailMetrics.linkRowSpacing).clickable { showsAllEpisodes = !showsAllEpisodes },
                                    )
                                }
                            }
                        }
                    }
                } else if (showsEpisodeList && preview != null && !isLoading) {
                    item(key = "episodes-empty") {
                        PodcastDetailSectionCard {
                            PodcastDetailMetaField("Episodes") { AbstandSectionEmptyState("This feed does not list any episodes yet.") }
                        }
                    }
                }
            }
        }
    }

    subscribeError?.let { msg ->
        AbstandAlert("Could not subscribe", onDismiss = { subscribeError = null }, message = msg)
    }
}

/** Feed-Folge: Titel, Metazeile, Notizen (2 Zeilen, Tipp klappt auf) + Trailing-Control. */
@Composable
private fun FeedEpisodeRow(
    episode: AbsPodcastFeedPreviewEpisode,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    trailing: @Composable () -> Unit,
) {
    val palette = Theme.palette
    Row(
        Modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.rowVerticalPadding),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing),
    ) {
        Column(
            Modifier.weight(1f).clickable(onClick = onToggleExpanded),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing),
        ) {
            Text(episode.title, style = AppType.titleSmall, color = palette.textPrimary)
            feedEpisodeMetaLine(episode)?.let { Text(it, style = AppType.bodySmall, color = palette.textSecondary) }
            (episode.descriptionPlain ?: episode.subtitle)?.let {
                Text(it, style = AppType.bodySmall, color = palette.textSecondary, maxLines = if (expanded) Int.MAX_VALUE else 2)
            }
        }
        trailing()
    }
}

/** iOS: `episodeDownloadControl` — Häkchen (in Bibliothek), Spinner (angefragt) oder Download-Pfeil. */
@Composable
private fun FeedEpisodeDownloadControl(
    store: PodcastStore,
    hit: AbsPodcastDirectorySearchHit,
    episode: AbsPodcastFeedPreviewEpisode,
    inProgressKeys: Set<String>,
    reachable: Boolean,
) {
    val scope = rememberCoroutineScope()
    if (!episode.canDownloadToServer) return
    val key = store.podcastDirectoryEpisodeKey(episode, hit) ?: return
    Box(Modifier.size(AppTheme.Layout.minTapTarget), contentAlignment = Alignment.Center) {
        when {
            store.podcastDirectoryEpisodeIsInLibrary(episode, hit) ->
                Icon(SF.checkmarkCircleFill, contentDescription = "Episode already in library", tint = Theme.accent, modifier = Modifier.size(ControlIconSize))
            key in inProgressKeys -> AbstandInlineSpinner()
            else -> AbstandIconButton(
                SF.arrowDownCircle,
                "Download episode to server",
                onClick = { scope.launch { store.downloadPodcastDirectoryEpisode(episode, hit) } },
                enabled = reachable,
                iconSize = ControlIconSize,
                tint = Theme.accent,
            )
        }
    }
}

private val ControlIconSize = 24.dp

/** „Sep 2, 2026 · 48 min · S2 · E14 · Trailer“ — nur was der Feed liefert. */
private fun feedEpisodeMetaLine(episode: AbsPodcastFeedPreviewEpisode): String? {
    val parts = mutableListOf<String>()
    episode.publishedAt?.takeIf { it > 0 }?.let { parts.add(dateLabelMillis(it)) }
    episode.durationSeconds?.takeIf { it > 0 }?.let { parts.add(formatPlaybackDurationShortHuman(it)) }
    episode.numberingLabel?.let { parts.add(it) }
    episode.specialTypeLabel?.let { parts.add(it) }
    return if (parts.isEmpty()) null else parts.joinToString(" · ")
}

/** iOS: `.formatted(date: .abbreviated, time: .omitted)`. */
internal fun dateLabelMillis(millis: Long): String = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(millis))

/** iTunes-`releaseDate` als ISO-String — nur den Tag anzeigen. */
internal fun dateLabelIsoDay(value: String): String? {
    val day = value.take(10)
    if (!Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(day)) return value.ifEmpty { null }
    val date = runCatching { LocalDate.parse(day) }.getOrNull() ?: return day
    return dateLabelMillis(date.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli())
}
