package de.letzgo.abstand.ui.podcasts

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.text.style.TextOverflow
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsPodcastRssFeedEpisodeDraft
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.PodcastAutoDownloadInterval
import de.letzgo.abstand.model.PodcastStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandGroupedCard
import de.letzgo.abstand.ui.components.AbstandInlineNotice
import de.letzgo.abstand.ui.components.AbstandInlineSpinner
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.AbstandSpinnerSize
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.ServerAdminSection
import de.letzgo.abstand.ui.components.SettingsCardActionRow
import de.letzgo.abstand.ui.components.SettingsCardDivider
import de.letzgo.abstand.ui.components.SettingsCardPickerRow
import de.letzgo.abstand.ui.components.SettingsCardStepperRow
import de.letzgo.abstand.ui.components.SettingsCardToggleRow
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.components.abstandScrollBottomPadding
import kotlinx.coroutines.launch

/** Navigationsziel der Sendungs-Verwaltung (iOS: Toolbar-Zahnrad → `ServerAdminPodcastShowView`). */
class PodcastShowSettingsDestination(val showId: String, val showTitle: String) : TabDestination {
    override val key: String = "podcast-show-settings/$showId"

    @Composable
    override fun Content(navigator: TabNavigator) {
        PodcastShowSettingsScreen(showId, showTitle, navigator)
    }
}

/** iOS: `ServerAdminPodcastShowTab`. */
private enum class PodcastShowSettingsTab(val label: String) { feed("RSS feed"), settings("Settings") }

/**
 * iOS: `ServerAdminPodcastShowView` (Settings-Unterseite) — Segment „RSS feed“ (Feed-Folgen mit
 * Server-Download bzw. Löschen, „In library only“) und „Settings“ (Auto-Download, Check new,
 * Remove from library). Toolbar: Feed neu laden, Sendung entfernen.
 * Abweichung: die Transkriptions-Sprache fehlt (Transkription ist noch nicht portiert).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PodcastShowSettingsScreen(showId: String, showTitle: String, navigator: TabNavigator, store: PodcastStore = AppModel.shared.podcasts) {
    val scope = rememberCoroutineScope()
    val admin by store.showAdmin.collectAsState()
    val filtered by store.podcastFilteredEpisodes.collectAsState()
    val selectedShowId by store.podcastSelectedShowId.collectAsState()
    val reachable by AppModel.shared.session.isNetworkReachable.collectAsState()
    val isAdmin by AppModel.shared.session.isServerAdmin.collectAsState()
    var tab by rememberSaveable { mutableStateOf(PodcastShowSettingsTab.feed) }
    var confirmRemove by remember { mutableStateOf(false) }

    LaunchedEffect(showId) { store.preloadPodcastShowAdminContext(showId) }
    LaunchedEffect(tab) {
        when (tab) {
            PodcastShowSettingsTab.feed -> store.ensurePodcastRssFeedLoaded(showId)
            PodcastShowSettingsTab.settings -> if (store.showAdmin.value.autoDownload?.showId != showId) store.loadPodcastAutoDownloadSettings(showId)
        }
    }

    PodcastInlineTitleScaffold(
        title = showTitle,
        onBack = { navigator.pop() },
        actions = {
            if (tab == PodcastShowSettingsTab.feed) {
                IconButton(
                    onClick = { scope.launch { store.ensurePodcastRssFeedLoaded(showId, forceReload = true) } },
                    enabled = reachable && showId !in admin.rssFeedLoadInProgressShowIds,
                ) { Icon(SF.arrowClockwise, contentDescription = "Refresh RSS feed") }
            }
            IconButton(onClick = { confirmRemove = true }, enabled = reachable) {
                Icon(SF.trash, contentDescription = "Remove from library", tint = if (reachable) AppTheme.danger else Theme.palette.textSecondary)
            }
        },
    ) { inner ->
        Column(Modifier.fillMaxSize().padding(top = inner.calculateTopPadding())) {
            PodcastSegmentedPicker(
                options = PodcastShowSettingsTab.entries,
                selection = tab,
                label = { it.label },
                onSelect = { tab = it },
                modifier = Modifier.padding(horizontal = AppTheme.Layout.tabPaddingH, vertical = AppTheme.Layout.rowSpacing),
            )
            when (tab) {
                PodcastShowSettingsTab.feed -> PodcastRssFeedSection(
                    store, showId, admin.rssFeedCacheByShowId[showId] ?: emptyList(),
                    libraryEpisodes = if (selectedShowId == showId) filtered else emptyList(),
                    loading = showId in admin.rssFeedLoadInProgressShowIds,
                    unavailable = admin.rssFeedUnavailableByShowId[showId],
                    inProgressDraftIds = admin.rssEpisodeDownloadInProgressDraftIds,
                    completedDraftIds = admin.rssDraftCompletedIdsByShowId[showId] ?: emptySet(),
                    reachable = reachable,
                    showTitle = showTitle,
                )
                PodcastShowSettingsTab.settings -> LazyColumn(
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(
                        start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.tabPaddingH,
                        top = AppTheme.Layout.withinSectionSpacing, bottom = abstandScrollBottomPadding(),
                    ),
                    verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.sectionSpacing),
                ) {
                    item(key = "auto") {
                        ServerAdminSection("Auto download") {
                            AutoDownloadSettingsCard(store, showId, admin.autoDownload, admin.autoDownloadSaving, reachable)
                        }
                    }
                    if (isAdmin) {
                        item(key = "checknew") {
                            val busy = admin.checkNewInProgressShowId == showId
                            AbstandGroupedCard {
                                SettingsCardActionRow(
                                    icon = SF.arrowClockwiseCircle,
                                    title = "Check & download new episodes",
                                    onClick = { scope.launch { store.checkAndDownloadNewPodcastEpisodes(showId) } },
                                    enabled = reachable && !busy,
                                    isBusy = busy,
                                )
                            }
                        }
                    }
                    item(key = "remove") {
                        AbstandGroupedCard {
                            SettingsCardActionRow(
                                icon = SF.minusCircle,
                                title = "Remove from library",
                                onClick = { confirmRemove = true },
                                tint = AppTheme.danger,
                                enabled = reachable,
                            )
                        }
                    }
                }
            }
        }
    }

    if (confirmRemove) {
        AbstandDialog(
            title = "Remove from library?",
            onDismiss = { confirmRemove = false },
            message = "\"$showTitle\" will be deleted on the server. Local downloads for this show will be removed.",
            confirmLabel = "Remove from library",
            destructive = true,
            dismissOnConfirm = false,
            onConfirm = {
                confirmRemove = false
                scope.launch { if (store.removePodcastShowFromLibrary(showId)) navigator.pop() }
            },
        )
    }
}

/** iOS: `PodcastShowAutoDownloadSettingsContent` — jede Änderung speichert sofort auf dem Server. */
@Composable
private fun AutoDownloadSettingsCard(
    store: PodcastStore,
    showId: String,
    settings: de.letzgo.abstand.model.PodcastAutoDownloadSettings?,
    saving: Boolean,
    reachable: Boolean,
) {
    val scope = rememberCoroutineScope()
    AbstandGroupedCard {
        if (settings == null || settings.showId != showId) {
            AbstandLoadingSpinner(size = AbstandSpinnerSize.Small, verticalPadding = AppTheme.Layout.blockSpacing)
            return@AbstandGroupedCard
        }
        val enabled = reachable && !saving
        fun save(next: de.letzgo.abstand.model.PodcastAutoDownloadSettings) {
            scope.launch { store.savePodcastAutoDownloadSettings(next) }
        }
        SettingsCardToggleRow(
            icon = SF.arrowDownCircle,
            title = "Download new episodes automatically",
            checked = settings.enabled,
            onCheckedChange = { save(settings.copy(enabled = it)) },
            enabled = enabled,
        )
        if (settings.enabled) {
            SettingsCardDivider()
            SettingsCardPickerRow(
                icon = SF.clock,
                title = "Check interval",
                selection = settings.interval,
                options = PodcastAutoDownloadInterval.entries,
                label = { it.label },
                onSelect = { save(settings.copy(interval = it)) },
                enabled = enabled,
            )
        }
        SettingsCardDivider()
        SettingsCardStepperRow(
            icon = SF.trayFull,
            title = "Max. episodes to keep",
            valueLabel = if (settings.maxEpisodesToKeep == 0) "All episodes" else "${settings.maxEpisodesToKeep}",
            value = settings.maxEpisodesToKeep,
            range = 0..500,
            onValueChange = { if (enabled) save(settings.copy(maxEpisodesToKeep = it)) },
        )
        SettingsCardDivider()
        SettingsCardStepperRow(
            icon = SF.plusRectangleOnRectangle,
            title = "Max. new episodes per check",
            valueLabel = if (settings.maxNewEpisodesToDownload == 0) "No limit" else "${settings.maxNewEpisodesToDownload}",
            value = settings.maxNewEpisodesToDownload,
            range = 0..100,
            onValueChange = { if (enabled) save(settings.copy(maxNewEpisodesToDownload = it)) },
        )
    }
}

/** iOS: `ServerAdminPodcastRssSection` — Feed-Folgen + „In library only“. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PodcastRssFeedSection(
    store: PodcastStore,
    showId: String,
    drafts: List<AbsPodcastRssFeedEpisodeDraft>,
    libraryEpisodes: List<AbsPodcastEpisodeListItem>,
    loading: Boolean,
    unavailable: String?,
    inProgressDraftIds: Set<java.util.UUID>,
    completedDraftIds: Set<java.util.UUID>,
    reachable: Boolean,
    showTitle: String,
) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    var deleteConfirmation by remember { mutableStateOf<AbsPodcastEpisodeListItem?>(null) }
    val libraryOnly = remember(drafts, libraryEpisodes) { libraryEpisodes.filter { ep -> drafts.none { it.matchesLibraryEpisode(ep) } } }

    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                store.loadPodcastEpisodesForShowLibraryItem(showId)
                store.ensurePodcastRssFeedLoaded(showId, forceReload = true)
                refreshing = false
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.tabPaddingH,
                top = AppTheme.Layout.withinSectionSpacing, bottom = abstandScrollBottomPadding(),
            ),
            verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
        ) {
            if (unavailable != null) item(key = "unavailable") { AbstandInlineNotice(unavailable, isError = true) }
            if (loading && drafts.isEmpty() && libraryOnly.isEmpty() && unavailable == null) {
                item(key = "loading") { AbstandLoadingSpinner(verticalPadding = AppTheme.Layout.emptyStateVerticalPadding) }
            } else if (drafts.isEmpty() && libraryOnly.isEmpty() && unavailable == null) {
                item(key = "empty") { AbstandSectionEmptyState("No episodes found in the feed.", isStandalone = true) }
            } else {
                items(drafts, key = { "draft-${it.id}" }) { draft ->
                    val match = libraryEpisodes.firstOrNull { draft.matchesLibraryEpisode(it) }
                    FeedDraftRow(
                        showId = showId,
                        title = draft.title,
                        showTitle = showTitle,
                        publishedAt = draft.publishedAt,
                    ) {
                        when {
                            match != null -> IconButton(onClick = { deleteConfirmation = match }, enabled = reachable) {
                                Icon(SF.trash, contentDescription = "Delete episode from library", tint = AppTheme.danger)
                            }
                            draft.id in inProgressDraftIds -> AbstandInlineSpinner()
                            draft.id in completedDraftIds -> PodcastInLibraryLabel()
                            else -> IconButton(
                                onClick = { scope.launch { store.downloadPodcastRssEpisodeDraft(draft, showId) } },
                                enabled = reachable,
                            ) { Icon(SF.arrowDownCircle, contentDescription = "Download episode to server", tint = Theme.accent) }
                        }
                    }
                }
                if (libraryOnly.isNotEmpty()) {
                    item(key = "library-only-title") {
                        TabContentSectionTitle("In library only", Modifier.padding(top = AppTheme.Layout.withinSectionSpacing))
                    }
                    items(libraryOnly, key = { "lib-${it.progressLookupKey}" }) { episode ->
                        FeedDraftRow(showId, episode.episodeTitle, showTitle, episode.publishedAt) {
                            IconButton(onClick = { deleteConfirmation = episode }, enabled = reachable) {
                                Icon(SF.trash, contentDescription = "Delete episode from library", tint = AppTheme.danger)
                            }
                        }
                    }
                }
            }
        }
    }

    deleteConfirmation?.let { episode ->
        AbstandDialog(
            title = "Delete episode?",
            onDismiss = { deleteConfirmation = null },
            message = "\"${episode.episodeTitle}\" will be removed from the server library.",
            confirmLabel = "Delete",
            destructive = true,
            dismissOnConfirm = false,
            onConfirm = {
                deleteConfirmation = null
                scope.launch { store.deletePodcastEpisodeFromLibrary(showId, episode) }
            },
        )
    }
}

/** iOS: `PodcastRssFeedDraftRow` / `ServerAdminPodcastLibraryEpisodeRow` — Show-Cover, Titel, Sendung, Datum, Aktion. */
@Composable
private fun FeedDraftRow(
    showId: String,
    title: String,
    showTitle: String,
    publishedAt: Long?,
    trailing: @Composable () -> Unit,
) {
    val palette = Theme.palette
    PodcastRowCardChrome {
        Row(horizontalArrangement = Arrangement.spacedBy(PodcastRowLayout.cardInset)) {
            CoverImage(itemId = showId, modifier = Modifier.size(PodcastRowLayout.coverSide))
            Column(
                Modifier
                    .weight(1f)
                    .height(PodcastRowLayout.coverSide)
                    .padding(vertical = AppTheme.Layout.libraryRowTextInset)
                    .padding(end = AppTheme.Layout.libraryRowTextInset),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
            ) {
                Text(title, style = IosType.headline, color = palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                PodcastRowMetaLine("Show", showTitle)
                Spacer(Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        publishedAt?.takeIf { it > 0 }?.let { dateLabelMillis(it) } ?: "—",
                        style = IosType.subheadline, color = palette.textSecondary, modifier = Modifier.weight(1f),
                    )
                    Box(Modifier.sizeIn(minWidth = AppTheme.Layout.minTapTarget, minHeight = AppTheme.Layout.minTapTarget), contentAlignment = Alignment.Center) { trailing() }
                }
            }
        }
    }
}
