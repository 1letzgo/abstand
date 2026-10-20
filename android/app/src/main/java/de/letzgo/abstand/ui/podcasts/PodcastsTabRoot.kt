package de.letzgo.abstand.ui.podcasts

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.selected
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.PodcastCatalogSortField
import de.letzgo.abstand.model.PodcastCatalogStripSection
import de.letzgo.abstand.model.PodcastEpisodeSortField
import de.letzgo.abstand.model.PodcastStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandBrowseStripItem
import de.letzgo.abstand.ui.components.AbstandFixedBrowseStripSectionsLayout
import de.letzgo.abstand.ui.components.AbstandPillIconButton
import de.letzgo.abstand.ui.components.AbstandLabeledLoadingState
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandPinnedBrowseStrip
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.AbstandSpinnerSize
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.components.TabRootScaffold
import kotlinx.coroutines.launch

/**
 * iOS: Podcasts-Tab-Root in `MainRootView` (`podcastsTabRoot` + `PodcastCatalogTabShell`):
 * Großtitel „Podcasts“, Toolbar (Add podcast in „New“ für Root, Show-Einstellungen bei gewählter
 * Sendung, Sortierung: Shows in „New“, Folgen bei gewählter Sendung), fixe Leiste mit gepinntem
 * „New“ und den Sendungen (bei mehreren Podcast-Bibliotheken zwei Auswahl-Pillen) und darunter
 * die Folgenliste des gewählten Abschnitts mit Pull-to-Refresh. Leerzustände immer sichtbar.
 *
 * Abweichung: iOS blättert horizontal zwischen den Abschnitten (`AbstandFixedBrowseStripSectionsLayout`);
 * Android zeigt den gewählten Abschnitt (Auswahl über die Leiste), Scrollposition je Abschnitt.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PodcastsTabRoot(model: AppModel = AppModel.shared) {
    val session = model.session
    val store = model.podcasts
    val selectedLibrary by session.selectedPodcastLibrary.collectAsState()
    if (selectedLibrary == null) {
        // iOS: `tabLibraryBootstrapPlaceholder` — Bibliothek wird noch aufgelöst.
        TabRootScaffold(title = "Podcasts") { padding ->
            AbstandLabeledLoadingState(Modifier.padding(padding), text = "Loading library…")
        }
        return
    }
    val navigator = LocalTabNavigator.current
    val scope = rememberCoroutineScope()

    val newEpisodes by store.podcastEpisodes.collectAsState()
    val shows by store.podcastShows.collectAsState()
    val selectedShowId by store.podcastSelectedShowId.collectAsState()
    val filtered by store.podcastFilteredEpisodes.collectAsState()
    val byShow by store.podcastEpisodesByShowId.collectAsState()
    val catalogSortField by store.podcastCatalogSortField.collectAsState()
    val catalogSortDescending by store.podcastCatalogSortDescending.collectAsState()
    val episodeSortField by store.podcastEpisodeSortField.collectAsState()
    val episodeSortDescending by store.podcastEpisodeSortDescending.collectAsState()
    val isLoadingPodcasts by store.isLoadingPodcasts.collectAsState()
    val isLoadingShowEpisodes by store.isLoadingPodcastShowEpisodes.collectAsState()
    val stripSection by store.podcastCatalogStripSectionId.collectAsState()
    val isRoot by session.isServerRoot.collectAsState()
    val reachable by session.isNetworkReachable.collectAsState()
    val offline by session.offlineHomeMode.collectAsState()
    val offlineAuto by session.offlineHomeModeAuto.collectAsState()
    val focusedLibrary by session.focusedPodcastLibrary.collectAsState()
    val activeIds by session.activePodcastLibraryIds.collectAsState()
    val libraries by session.libraries.collectAsState()
    val actionsRevision by store.actions.revision.collectAsState()

    // iOS: `.onAppear` des Tabs — Fokus auf Primary/erste aktive Bibliothek, leere Liste nachladen.
    LaunchedEffect(selectedLibrary?.id) {
        val previous = session.focusedPodcastLibrary.value?.id
        session.resetFocusedPodcastLibraryToPrimaryOrFirstActive()
        val focusChanged = session.focusedPodcastLibrary.value?.id != previous
        if (focusChanged || (store.podcastEpisodes.value.isEmpty() && !store.isLoadingPodcasts.value)) {
            store.restorePodcastCatalogFromLocalStore()
            store.reloadPodcastLibrary(reset = true)
        }
    }

    val isNewView = selectedShowId == null
    val episodes = remember(
        selectedShowId, newEpisodes, filtered, byShow, episodeSortField, episodeSortDescending,
        reachable, offline, offlineAuto, actionsRevision,
    ) { store.podcastEpisodesForPodcastsTab(selectedShowId) }
    val sectionTitle = selectedShowId?.let { sid ->
        shows.firstOrNull { it.id == sid }?.displayTitle?.trim()?.ifEmpty { null } ?: "Episodes"
    } ?: "New episodes"
    val listLoading = if (isNewView) isLoadingPodcasts && episodes.isEmpty() else isLoadingShowEpisodes && episodes.isEmpty()
    val activeLibraries = remember(activeIds, libraries) { session.activePodcastLibraries }

    TabRootScaffold(
        title = "Podcasts",
        actions = {
            if (isRoot && isNewView) {
                // Leisten-Aktionen als Symbol-Pillen wie Filter/Sortieren in Books.
                AbstandPillIconButton(
                    SF.plus, "Add podcast", onClick = { navigator?.push(PodcastAddDestination()) },
                    enabled = reachable && store.podcastCatalogLibrary != null,
                )
            }
            val sid = selectedShowId
            if (isRoot && sid != null) {
                val title = shows.firstOrNull { it.id == sid }?.displayTitle?.trim()?.ifEmpty { null } ?: "Podcast"
                AbstandPillIconButton(SF.gearshape, "Show settings", onClick = { navigator?.push(PodcastShowSettingsDestination(sid, title)) })
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
        },
        header = {
            PodcastShowsStrip(
                libraries = activeLibraries,
                selectedLibraryId = focusedLibrary?.id ?: selectedLibrary?.id ?: activeLibraries.firstOrNull()?.id ?: "",
                onSelectLibrary = { id -> activeLibraries.firstOrNull { it.id == id }?.let { session.focusPodcastLibrary(it) } },
                shows = shows.map { AbstandBrowseStripItem(it.id, it.displayTitle, SF.micFill, coverItemId = it.id) },
                selectedSectionId = stripSection,
                onSelectSection = store::selectStripSection,
            )
        },
    ) { padding ->
        var refreshing by remember { mutableStateOf(false) }
        PodcastPullToRefresh(
            refreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    store.refreshPodcastsTab()
                    refreshing = false
                }
            },
            topInset = padding.calculateTopPadding(),
        ) {
            // Eigene Scrollposition je Abschnitt (iOS: eine Seite je Abschnitt).
            val listState = key(stripSection) { rememberLazyListState() }
            LazyColumn(
                Modifier.fillMaxSize(),
                state = listState,
                contentPadding = padding,
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
            ) {
                item(key = "title") { TabContentSectionTitle(sectionTitle) }
                if (listLoading) {
                    item(key = "loading") { AbstandLoadingSpinner() }
                } else if (episodes.isEmpty()) {
                    item(key = "empty") {
                        AbstandSectionEmptyState(
                            if (isNewView) "No episodes in the list. Pull to refresh or check your network."
                            else "No episodes in the library for this show.",
                        )
                    }
                }
                items(episodes, key = { it.progressLookupKey }) { episode ->
                    PodcastEpisodeListRow(store, episode) { navigator?.push(PodcastEpisodeDetailDestination(episode)) }
                    if (isNewView) {
                        LaunchedEffect(episode.progressLookupKey) { store.loadMorePodcastsIfNeeded(episode.id) }
                    }
                }
                if (!isNewView && isLoadingShowEpisodes && episodes.isNotEmpty()) {
                    item(key = "loading-more") {
                        AbstandLoadingSpinner(size = AbstandSpinnerSize.Small, verticalPadding = AppTheme.Layout.stackSpacing)
                    }
                }
            }
        }
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

/**
 * iOS: `AbstandPinnedBrowseStrip` für Podcasts — eine aktive Bibliothek: „New“ links fix, die
 * Sendungen scrollen daneben (Dock-Chips, aktiv mit Cover + Titel). Mehrere Bibliotheken: zwei
 * Auswahl-Pillen (Bibliothek, Abschnitt).
 */
@Composable
internal fun PodcastShowsStrip(
    libraries: List<AbsLibrary>,
    selectedLibraryId: String,
    onSelectLibrary: (String) -> Unit,
    shows: List<AbstandBrowseStripItem>,
    selectedSectionId: String,
    onSelectSection: (String) -> Unit,
) {
    val newItem = AbstandBrowseStripItem(PodcastCatalogStripSection.newEpisodes, "New", SF.squareGrid2x2)
    AbstandPinnedBrowseStrip(
        secondaryItems = listOf(newItem) + shows,
        secondarySelectionId = selectedSectionId,
        onSelectSecondary = onSelectSection,
        libraryPickerItems = libraries.map { AbstandBrowseStripItem(it.id, it.name, SF.micFill) },
        libraryPickerSelectionId = selectedLibraryId,
        onSelectLibrary = onSelectLibrary,
        pinnedLeadingItem = newItem,
        secondaryAccessibilityLabel = "Shows",
    )
}
