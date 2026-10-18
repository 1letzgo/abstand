package de.letzgo.abstand.ui.podcasts

import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.PodcastCatalogSortField
import de.letzgo.abstand.model.PodcastCatalogStripSection
import de.letzgo.abstand.model.PodcastEpisodeSortField
import de.letzgo.abstand.model.PodcastStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandBrowseStripItem
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.AbstandSpinnerSize

/**
 * Zustand des Podcasts-Abschnitts (iOS: Podcasts-Tab-Root in `MainRootView`, `podcastsTabRoot` +
 * `PodcastCatalogTabShell`) — gesammelt von [rememberPodcastsSectionContent], gerendert von
 * [podcastsSectionItems]. Android: Teil der Home-Bibliotheksleiste mit Podcast-Bibliothek.
 */
internal class PodcastsSectionContent(
    val store: PodcastStore,
    /** „New“ (keine Sendung gewählt). */
    val isNewView: Boolean,
    val selectedShowId: String?,
    val shows: List<AbstandBrowseStripItem>,
    val stripSectionId: String,
    val episodes: List<AbsPodcastEpisodeListItem>,
    val sectionTitle: String,
    val listLoading: Boolean,
    val isLoadingShowEpisodes: Boolean,
    val navigator: TabNavigator?,
)

/** Sammelt die Flows des Podcasts-Abschnitts (Folgenliste „New“ bzw. der gewählten Sendung). */
@Composable
internal fun rememberPodcastsSectionContent(model: AppModel = AppModel.shared): PodcastsSectionContent {
    val session = model.session
    val store = model.podcasts
    val newEpisodes by store.podcastEpisodes.collectAsState()
    val shows by store.podcastShows.collectAsState()
    val selectedShowId by store.podcastSelectedShowId.collectAsState()
    val filtered by store.podcastFilteredEpisodes.collectAsState()
    val byShow by store.podcastEpisodesByShowId.collectAsState()
    val episodeSortField by store.podcastEpisodeSortField.collectAsState()
    val episodeSortDescending by store.podcastEpisodeSortDescending.collectAsState()
    val isLoadingPodcasts by store.isLoadingPodcasts.collectAsState()
    val isLoadingShowEpisodes by store.isLoadingPodcastShowEpisodes.collectAsState()
    val stripSection by store.podcastCatalogStripSectionId.collectAsState()
    val reachable by session.isNetworkReachable.collectAsState()
    val offline by session.offlineHomeMode.collectAsState()
    val offlineAuto by session.offlineHomeModeAuto.collectAsState()
    val focused by session.focusedPodcastLibrary.collectAsState()
    val actionsRevision by store.actions.revision.collectAsState()

    val isNewView = selectedShowId == null
    val episodes = remember(
        selectedShowId, newEpisodes, filtered, byShow, episodeSortField, episodeSortDescending,
        reachable, offline, offlineAuto, actionsRevision, focused?.id,
    ) { store.podcastEpisodesForPodcastsTab(selectedShowId) }
    val sectionTitle = selectedShowId?.let { sid ->
        shows.firstOrNull { it.id == sid }?.displayTitle?.trim()?.ifEmpty { null } ?: "Episodes"
    } ?: "New episodes"
    val listLoading = if (isNewView) isLoadingPodcasts && episodes.isEmpty() else isLoadingShowEpisodes && episodes.isEmpty()
    val showItems = remember(shows) { shows.map { AbstandBrowseStripItem(it.id, it.displayTitle, SF.micFill) } }
    return PodcastsSectionContent(
        store = store,
        isNewView = isNewView,
        selectedShowId = selectedShowId,
        shows = showItems,
        stripSectionId = stripSection,
        episodes = episodes,
        sectionTitle = sectionTitle,
        listLoading = listLoading,
        isLoadingShowEpisodes = isLoadingShowEpisodes,
        navigator = LocalTabNavigator.current,
    )
}

/** Bereiche der Bibliotheksleiste: „New“ zuerst, dann die Sendungen (iOS: `AbstandPinnedBrowseStrip`). */
internal fun podcastSectionStripItems(shows: List<AbstandBrowseStripItem>): List<AbstandBrowseStripItem> {
    val newItem = AbstandBrowseStripItem(PodcastCatalogStripSection.newEpisodes, "New", SF.squareGrid2x2)
    return listOf(newItem) + shows.filter { it.id != newItem.id }
}

/**
 * iOS: Folgenliste des gewählten Abschnitts — Überschrift, Lade-/Leerzustand (immer sichtbar),
 * Folgen-Zeilen, Paging („New“) bzw. Nachlade-Spinner (Sendung). Liste/Pull-to-Refresh: Aufrufer.
 */
internal fun LazyListScope.podcastsSectionItems(content: PodcastsSectionContent) {
    val store = content.store
    val episodes = content.episodes
    val isNewView = content.isNewView
    if (content.listLoading) {
        item(key = "podcast-loading") { AbstandLoadingSpinner() }
    } else if (episodes.isEmpty()) {
        item(key = "podcast-empty") {
            AbstandSectionEmptyState(
                if (isNewView) "No episodes in the list. Pull to refresh or check your network."
                else "No episodes in the library for this show.",
            )
        }
    }
    items(episodes, key = { "podcast-ep-${it.progressLookupKey}" }) { episode ->
        PodcastEpisodeListRow(store, episode) { content.navigator?.push(PodcastEpisodeDetailDestination(episode)) }
        if (isNewView) {
            LaunchedEffect(episode.progressLookupKey) { store.loadMorePodcastsIfNeeded(episode.id) }
        }
    }
    if (!isNewView && content.isLoadingShowEpisodes && episodes.isNotEmpty()) {
        item(key = "podcast-loading-more") {
            AbstandLoadingSpinner(size = AbstandSpinnerSize.Small, verticalPadding = AppTheme.Layout.stackSpacing)
        }
    }
}

/**
 * iOS: `PodcastCatalogToolbarContent` — Add podcast (Root, „New“), Show-Einstellungen (Root,
 * gewählte Sendung), Sortierung (Shows in „New“, Folgen bei gewählter Sendung). Android: rechts in
 * der Home-Bibliotheksleiste, wenn eine Podcast-Bibliothek gewählt ist.
 */
@Composable
internal fun PodcastsToolbarActions(model: AppModel = AppModel.shared) {
    val session = model.session
    val store = model.podcasts
    val navigator = LocalTabNavigator.current
    val shows by store.podcastShows.collectAsState()
    val selectedShowId by store.podcastSelectedShowId.collectAsState()
    val catalogSortField by store.podcastCatalogSortField.collectAsState()
    val catalogSortDescending by store.podcastCatalogSortDescending.collectAsState()
    val episodeSortField by store.podcastEpisodeSortField.collectAsState()
    val episodeSortDescending by store.podcastEpisodeSortDescending.collectAsState()
    val isRoot by session.isServerRoot.collectAsState()
    val reachable by session.isNetworkReachable.collectAsState()
    val isNewView = selectedShowId == null
    if (isRoot && isNewView) {
        // Kopfzeilen-Aktionen wie in Books: einfache Kontur-Symbole in Textfarbe.
        AbstandIconButton(
            SF.plus, "Add podcast", onClick = { navigator?.push(PodcastAddDestination()) },
            enabled = reachable && store.podcastCatalogLibrary != null, tint = Theme.palette.textSecondary,
        )
    }
    val sid = selectedShowId
    if (isRoot && sid != null) {
        val title = shows.firstOrNull { it.id == sid }?.displayTitle?.trim()?.ifEmpty { null } ?: "Podcast"
        AbstandIconButton(SF.gearshape, "Show settings", onClick = { navigator?.push(PodcastShowSettingsDestination(sid, title)) }, tint = Theme.palette.textSecondary)
    }
    if (isNewView) {
        PodcastSortMenuButton(
            fields = PodcastCatalogSortField.entries,
            selected = catalogSortField,
            title = { it.menuTitle },
            descending = catalogSortDescending,
            showsOrder = !catalogSortField.suppressesSortOrderPicker,
            onSelectField = store::setPodcastCatalogSortField,
            onSelectDescending = store::setPodcastCatalogSortDescending,
        )
    } else {
        PodcastSortMenuButton(
            fields = PodcastEpisodeSortField.entries,
            selected = episodeSortField,
            title = { it.menuTitle },
            descending = episodeSortDescending,
            showsOrder = true,
            onSelectField = store::setPodcastEpisodeSortField,
            onSelectDescending = store::setPodcastEpisodeSortDescending,
        )
    }
}

/** Folgen-Zeile mit Live-Zustand aus Store + [PodcastActions] (Fortschritt, Download, Wiedergabe). */
@Composable
internal fun PodcastEpisodeListRow(store: PodcastStore, episode: AbsPodcastEpisodeListItem, onOpenDetail: () -> Unit) {
    val progressMap by store.progressByItemId.collectAsState()
    val actions = store.actions
    val revision by actions.revision.collectAsState()
    val lid = episode.libraryItemId
    val eid = episode.episodeId
    val live = remember(progressMap, revision, episode.progressLookupKey) {
        PodcastEpisodeRowLive(
            progress = progressMap[episode.progressLookupKey],
            isDownloaded = actions.isDownloaded(lid, eid),
            downloadProgress = actions.downloadProgress(lid, eid),
            isPlaying = actions.isPlaying(lid, eid),
        )
    }
    PodcastEpisodeRowCard(
        episode = episode,
        live = live,
        onOpenDetail = onOpenDetail,
        onPlayToggle = {
            if (live.isPlaying) actions.pause()
            else actions.play(episode, resumeAt = if (live.progress?.isFinished == true) 0.0 else null)
        },
    )
}
