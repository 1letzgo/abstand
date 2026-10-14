package de.letzgo.abstand.ui.stats

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsListeningStatsItemAggregate
import de.letzgo.abstand.data.AbsListeningStatsRecentSession
import de.letzgo.abstand.data.AbsListeningStatsResponse
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.logic.ListeningAchievementKind
import de.letzgo.abstand.logic.StatsLogic
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.StatsLogicExt
import de.letzgo.abstand.model.StatsStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandCard
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardNavRow
import de.letzgo.abstand.ui.components.SettingsSubpageScaffold
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.formatPlaybackDurationShortHuman
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import de.letzgo.abstand.ui.components.AbstandCoverPillText

/**
 * Navigation aus Stats in Detailseiten anderer Domänen (iOS: `BookDetailView`,
 * `PodcastEpisodeDetailView`). Vom Integrator gesetzt; ohne Belegung sind die Karten nicht tippbar.
 */
object StatsNavigation {
    @Volatile var bookDetail: ((libraryItemId: String) -> TabDestination)? = null
    @Volatile var episodeDetail: ((AbsPodcastEpisodeListItem) -> TabDestination)? = null
}

/** iOS: `SettingsStatsCategory` (Top 10 / Sessions). */
enum class StatsCategory(val title: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val subtitle: String) {
    topListened("Top 10", SF.listStar, "Most listened titles"),
    sessions("Sessions", SF.playCircleFill, "Recent playback sessions");

    val destination: TabDestination get() = if (this == topListened) StatsTopListenedDestination else StatsSessionsDestination
}

/**
 * iOS: `SettingsStatsSectionView` — Offline-Hinweis, Level, Timeline und die Unterseiten Top 10 /
 * Sessions als Karten. Für den Stats-Bereich im Settings-Hub (Daten lädt der Hub).
 */
fun LazyListScope.statsHubSections() {
    item(key = "stats/banner") { StatsOfflineBannerIfNeeded() }
    item(key = "stats/level") { StatsLevelSection() }
    item(key = "stats/timeline") { StatsTimelineSection() }
    StatsCategory.entries.forEach { category ->
        item(key = "stats/${category.name}") {
            val navigator = LocalTabNavigator.current
            ServerAdminSection(category.title) {
                AbstandGroupedCard {
                    SettingsCardNavRow(category.icon, category.title, subtitle = category.subtitle, onClick = { navigator?.push(category.destination) })
                }
            }
        }
    }
}

/** Stats als eigene Seite (z. B. von Home): gleiche Inhalte wie der Settings-Bereich. */
data object StatsDestination : TabDestination {
    override val key = "stats"

    @Composable
    override fun Content(navigator: TabNavigator) = StatsScreen(onBack = { navigator.pop() })
}

/** Öffentliche Stats-Seite: lädt Achievements und Stats beim Erscheinen, Pull-to-Refresh. */
@Composable
fun StatsScreen(onBack: () -> Unit, stats: StatsStore = StatsStore.shared) {
    LaunchedEffect(Unit) {
        stats.prepareListeningAchievementsForStatsTab()
        stats.loadListeningStats()
    }
    StatsRefreshBox(stats) {
        SettingsSubpageScaffold(title = "Stats", onBack = onBack) { statsHubSections() }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StatsRefreshBox(stats: StatsStore, content: @Composable () -> Unit) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                try { stats.loadListeningStats() } finally { refreshing = false }
            }
        },
    ) { content() }
}

@Composable
private fun StatsOfflineBannerIfNeeded(model: AppModel = AppModel.shared, stats: StatsStore = StatsStore.shared) {
    val fetchedAt by stats.listeningStatsFetchedAt.collectAsState()
    val response by stats.listeningStats.collectAsState()
    val reachable by model.session.isNetworkReachable.collectAsState()
    val at = fetchedAt
    if (at != null && response != null && !reachable) StatsOfflineCacheBanner(at)
}

/** iOS: `StatsOfflineCacheBanner`. */
@Composable
fun StatsOfflineCacheBanner(fetchedAtMillis: Long) {
    val palette = Theme.palette
    val formatted = remember(fetchedAtMillis) {
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT).withLocale(StatsLogic.statsLocale)
            .format(Instant.ofEpochMilli(fetchedAtMillis).atZone(ZoneId.systemDefault()))
    }
    AbstandGroupedCard(horizontalPadding = BannerPadding, verticalPadding = BannerPadding) {
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing), verticalAlignment = Alignment.Top) {
            Icon(SF.icloudSlash, contentDescription = null, tint = Theme.accent)
            Text("Offline — cached $formatted.", style = IosType.caption, color = palette.textSecondary)
        }
    }
}

/** iOS: `StatsLevelSectionView` — Achievements, 2 Spalten (4 auf breiten Geräten). */
@Composable
fun StatsLevelSection(stats: StatsStore = StatsStore.shared) {
    val snapshot by stats.achievements.collectAsState()
    val columns = StatsLogic.levelColumnCount(LocalConfiguration.current.screenWidthDp >= RegularWidthDp)
    val list = ListeningAchievementKind.sortedForDisplay(snapshot.achievements)
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
        TabContentSectionTitle("Level")
        list.chunked(columns).forEach { rowItems ->
            Row(Modifier.fillMaxWidth().height(androidx.compose.foundation.layout.IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
                rowItems.forEach { ListeningAchievementCard(it, Modifier.weight(1f), compact = true) }
                repeat(columns - rowItems.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

/** iOS: `StatsTimelineHubSectionView`. */
@Composable
fun StatsTimelineSection(stats: StatsStore = StatsStore.shared) {
    val response by stats.listeningStats.collectAsState()
    val loading by stats.listeningStatsLoading.collectAsState()
    Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
        TabContentSectionTitle("Timeline")
        val r = response
        when {
            loading && r == null -> AbstandLoadingSpinner(verticalPadding = AppTheme.Layout.blockSpacing)
            r != null -> ListeningMonthHeatmapCard(r)
            else -> AbstandSectionEmptyState("No statistics loaded.")
        }
    }
}

/** iOS: `StatsTopListenedDetailView`. */
data object StatsTopListenedDestination : TabDestination {
    override val key = "stats/top10"

    @Composable
    override fun Content(navigator: TabNavigator) = StatsDetailScreen("Top 10", navigator) { r -> statsTopListenedItems(r) }
}

/** iOS: `StatsSessionsDetailView`. */
data object StatsSessionsDestination : TabDestination {
    override val key = "stats/sessions"

    @Composable
    override fun Content(navigator: TabNavigator) = StatsDetailScreen("Sessions", navigator) { r -> statsSessionItems(r) }
}

/** iOS: `StatsDetailScrollScreen` — Offline-Hinweis, Lade-/Leerzustand, Pull-to-Refresh. */
@Composable
private fun StatsDetailScreen(
    title: String,
    navigator: TabNavigator,
    model: AppModel = AppModel.shared,
    stats: StatsStore = StatsStore.shared,
    content: LazyListScope.(AbsListeningStatsResponse) -> Unit,
) {
    val response by stats.listeningStats.collectAsState()
    val loading by stats.listeningStatsLoading.collectAsState()
    val reachable by model.session.isNetworkReachable.collectAsState()
    StatsRefreshBox(stats) {
        SettingsSubpageScaffold(title = title, onBack = { navigator.pop() }) {
            item(key = "banner") { StatsOfflineBannerIfNeeded() }
            val r = response
            when {
                loading && r == null -> item(key = "loading") { AbstandLoadingSpinner() }
                r != null -> content(r)
                !reachable -> item(key = "empty") {
                    AbstandSectionEmptyState(
                        "No saved statistics. Connect to the server to load and cache your listening data.",
                        isStandalone = true,
                    )
                }
                else -> item(key = "empty") { AbstandSectionEmptyState("No statistics loaded.", isStandalone = true) }
            }
        }
    }
}

private fun LazyListScope.statsTopListenedItems(stats: AbsListeningStatsResponse) {
    val top = stats.itemsSortedByListeningTime.take(TOP_COUNT)
    item(key = "top") {
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
            TabContentSectionTitle("Top 10")
            if (top.isEmpty()) {
                AbstandSectionEmptyState("No listening history for individual titles yet.", isStandalone = true)
            } else {
                top.forEachIndexed { index, (id, item) -> StatsTopListenedBookCard(index + 1, id, item) }
            }
        }
    }
}

private fun LazyListScope.statsSessionItems(stats: AbsListeningStatsResponse) {
    val sessions = stats.recentSessions
    item(key = "sessions") {
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
            TabContentSectionTitle("Sessions")
            if (sessions.isEmpty()) {
                AbstandSectionEmptyState("No listening sessions yet.", isStandalone = true)
            } else {
                sessions.forEach { StatsRecentSessionCard(it) }
            }
        }
    }
}

/** iOS: `StatsTopListenedBookCard`. */
@Composable
private fun StatsTopListenedBookCard(rank: Int, lookupId: String, item: AbsListeningStatsItemAggregate) {
    val navigator = LocalTabNavigator.current
    val libraryItemId = StatsLogicExt.normalizedStatsLibraryItemId(lookupId)
    val book = remember(lookupId, item) { StatsLogicExt.bookForStats(lookupId, item.mediaMetadata, null) }
    val fromStats = item.mediaMetadata?.displayAuthorLine?.trim().orEmpty()
    val authorLine = if (fromStats.isNotEmpty() && fromStats != "—") fromStats else book.displayAuthorsCardLine.trim().ifEmpty { "—" }
    val open = StatsNavigation.bookDetail?.let { f -> { navigator?.push(f(libraryItemId)); Unit } }
    StatsLibraryRowCard(
        coverItemId = book.id,
        rank = rank,
        title = book.displayTitle,
        authorLine = authorLine,
        listened = formatPlaybackDurationShortHuman(item.timeListening.toDouble()),
        trailing = "listened",
        onClick = open,
    )
}

/** iOS: `StatsRecentSessionCard`. */
@Composable
private fun StatsRecentSessionCard(session: AbsListeningStatsRecentSession, model: AppModel = AppModel.shared) {
    val navigator = LocalTabNavigator.current
    val libraryItemId = StatsLogicExt.normalizedStatsLibraryItemId(session.libraryItemId)
    val book = remember(session.id) { StatsLogicExt.bookForStats(session.libraryItemId, null, null) }
    val title = session.displayTitle?.trim().orEmpty().ifEmpty { book.displayTitle }
    val author = session.displayAuthor?.trim().orEmpty().ifEmpty { book.displayAuthorsCardLine.trim().ifEmpty { "—" } }
    val startedAt = remember(session.startedAt) {
        if (session.startedAt <= 0) "" else DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .withLocale(StatsLogic.statsLocale).format(Instant.ofEpochMilli(session.startedAt).atZone(ZoneId.systemDefault()))
    }
    val episode = remember(session.id) {
        StatsLogicExt.podcastEpisodeForStatsSession(session, model.session.selectedPodcastLibrary.value?.id)
    }
    val open: (() -> Unit)? = if (episode != null) {
        StatsNavigation.episodeDetail?.let { f -> { navigator?.push(f(episode)); Unit } }
    } else {
        StatsNavigation.bookDetail?.let { f -> { navigator?.push(f(libraryItemId)); Unit } }
    }
    StatsLibraryRowCard(
        coverItemId = libraryItemId,
        rank = null,
        title = title,
        authorLine = author,
        listened = formatPlaybackDurationShortHuman(session.timeListening.toDouble()),
        trailing = startedAt,
        onClick = open,
    )
}

/** iOS: `StatsLibraryRowLayout.libraryRowCardChrome` — Cover links, Metadaten rechts. */
@Composable
private fun StatsLibraryRowCard(
    coverItemId: String,
    rank: Int?,
    title: String,
    authorLine: String,
    listened: String,
    trailing: String,
    onClick: (() -> Unit)?,
) {
    val palette = Theme.palette
    val side = AppTheme.Layout.libraryRowCoverSide
    val inset = AppTheme.Layout.libraryRowTextInset
    AbstandCard(Modifier.fillMaxWidth(), shape = RoundedCornerShape(AppTheme.Layout.libraryRowCornerRadius), onClick = onClick) {
        Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.libraryRowCardInset)) {
            Box(Modifier.size(side), contentAlignment = Alignment.BottomStart) {
                SquareCoverImage(itemId = coverItemId, modifier = Modifier.size(side))
                if (rank != null) {
                    AbstandCoverPillText("$rank")
                }
            }
            Column(
                Modifier.weight(1f).height(side).padding(top = inset, bottom = inset, end = inset),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
            ) {
                Text(title, style = IosType.headline, color = palette.textPrimary, maxLines = 1)
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
                    Text("Author", style = IosType.footnote.semibold, color = palette.textSecondary)
                    val line = authorLine.trim()
                    Text(
                        if (line.isEmpty()) "—" else line, style = IosType.footnote,
                        color = if (line.isEmpty() || line == "—") palette.textSecondary else palette.textPrimary, maxLines = 2,
                    )
                }
                Box(Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing)) {
                    Text(listened, style = IosType.subheadline, color = Theme.accent)
                    if (trailing.isNotEmpty()) Text(trailing, style = IosType.subheadline, color = palette.textSecondary, maxLines = 1)
                }
            }
        }
    }
}

private const val TOP_COUNT = 10
/** iOS: Banner-Padding 12/12. */
private val BannerPadding = 12.dp
