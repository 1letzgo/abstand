package de.letzgo.abstand.ui.podcasts

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.PodcastCatalogSortField
import de.letzgo.abstand.model.PodcastCatalogStripSection
import de.letzgo.abstand.model.PodcastEpisodeSortField
import de.letzgo.abstand.model.PodcastStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandLabeledLoadingState
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.AbstandSpinnerSize
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.components.TabRootScaffold
import de.letzgo.abstand.ui.semibold
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
                IconButton(
                    onClick = { navigator?.push(PodcastAddDestination()) },
                    enabled = reachable && store.podcastCatalogLibrary != null,
                ) { Icon(SF.plusCircleFill, contentDescription = "Add podcast", tint = if (reachable) Theme.accent else Theme.palette.textSecondary) }
            }
            val sid = selectedShowId
            if (isRoot && sid != null) {
                val title = shows.firstOrNull { it.id == sid }?.displayTitle?.trim()?.ifEmpty { null } ?: "Podcast"
                IconButton(onClick = { navigator?.push(PodcastShowSettingsDestination(sid, title)) }) {
                    Icon(SF.gearshapeFill, contentDescription = "Show settings", tint = Theme.accent)
                }
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
                shows = shows.map { PodcastStripItem(it.id, it.displayTitle, SF.micFill, coverItemId = it.id) },
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

/** iOS: `AbstandBrowseStripItem`. */
internal data class PodcastStripItem(val id: String, val label: String, val icon: ImageVector, val coverItemId: String? = null)

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
    shows: List<PodcastStripItem>,
    selectedSectionId: String,
    onSelectSection: (String) -> Unit,
) {
    val newItem = PodcastStripItem(PodcastCatalogStripSection.newEpisodes, "New", SF.squareGrid2x2)
    if (libraries.size > 1) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AppTheme.Layout.tabPaddingH),
            horizontalArrangement = Arrangement.spacedBy(AppTheme.ExpandingDock.itemSpacing),
        ) {
            PodcastDropdownPill(
                items = libraries.map { PodcastStripItem(it.id, it.name, SF.micFill) },
                selectedId = selectedLibraryId,
                fallbackIcon = SF.booksVerticalFill,
                accessibilityLabel = "Library",
                onSelect = onSelectLibrary,
                modifier = Modifier.weight(1f),
            )
            PodcastDropdownPill(
                items = listOf(newItem) + shows,
                selectedId = selectedSectionId,
                fallbackIcon = SF.squareGrid2x2,
                accessibilityLabel = "Shows",
                onSelect = onSelectSection,
                modifier = Modifier.weight(1f),
            )
        }
        return
    }
    Row(
        Modifier.fillMaxWidth().padding(vertical = AppTheme.ExpandingDock.verticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.padding(start = AppTheme.Layout.tabPaddingH, end = AppTheme.ExpandingDock.pinnedChipFadeWidth)) {
            PodcastDockChip(newItem, selected = selectedSectionId == newItem.id) { onSelectSection(newItem.id) }
        }
        LazyRow(
            Modifier.weight(1f),
            contentPadding = PaddingValues(end = AppTheme.Layout.tabPaddingH),
            horizontalArrangement = Arrangement.spacedBy(AppTheme.ExpandingDock.itemSpacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items(shows, key = { it.id }) { item ->
                PodcastDockChip(item, selected = selectedSectionId == item.id) { onSelectSection(item.id) }
            }
        }
    }
}

/**
 * iOS: `AbstandExpandingDockChip` — aktiv: Akzent-Kapsel mit Cover/Symbol + Titel; inaktiv:
 * runder Chip nur mit Cover/Symbol (Titel als Accessibility-Label).
 */
@Composable
private fun PodcastDockChip(item: PodcastStripItem, selected: Boolean, onClick: () -> Unit) {
    val colors = AppTheme.ExpandingDock.Colors.of(Theme.palette, Theme.accent)
    val dock = AppTheme.ExpandingDock
    val base = Modifier
        .clip(CircleShape)
        .clickable(onClick = onClick)
        .semantics {
            this.selected = selected
            role = Role.Tab
            contentDescription = item.label
        }
    if (selected) {
        Row(
            base
                .background(colors.activeBackground)
                .height(dock.activeHeight)
                .padding(start = dock.activeLeadingPadding, end = dock.activeTrailingPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dock.iconLabelSpacing),
        ) {
            if (item.coverItemId != null) {
                Box(Modifier.size(dock.activeCoverSize).clip(CircleShape)) { CoverImage(itemId = item.coverItemId) }
            } else {
                Icon(item.icon, contentDescription = null, tint = colors.activeForeground, modifier = Modifier.size(dock.iconSize))
            }
            Text(item.label, style = IosType.subheadline.semibold, color = colors.activeForeground, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    } else {
        Box(base.background(colors.inactiveBackground).size(dock.circleSize), contentAlignment = Alignment.Center) {
            if (item.coverItemId != null) {
                Box(Modifier.size(dock.circleSize).clip(CircleShape)) { CoverImage(itemId = item.coverItemId) }
            } else {
                Icon(
                    item.icon, contentDescription = null, tint = colors.inactiveForeground,
                    modifier = Modifier.size(dock.iconSize).alpha(dock.inactiveIconOpacity),
                )
            }
        }
    }
}

/** iOS: `AbstandBrowseStripDropdownPill` — Kapsel mit Symbol, aktuellem Eintrag und Auswahlmenü. */
@Composable
private fun PodcastDropdownPill(
    items: List<PodcastStripItem>,
    selectedId: String,
    fallbackIcon: ImageVector,
    accessibilityLabel: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val palette = Theme.palette
    val current = items.firstOrNull { it.id == selectedId }
    Box(modifier) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = AppTheme.ExpandingDock.activeHeight)
                .clip(CircleShape)
                .background(palette.card)
                .clickable { expanded = true }
                .semantics { contentDescription = "$accessibilityLabel: ${current?.label ?: ""}" }
                .padding(horizontal = AppTheme.ExpandingDock.horizontalPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.inlineSpacing),
        ) {
            Icon(current?.icon ?: fallbackIcon, contentDescription = null, tint = Theme.accent, modifier = Modifier.size(AppTheme.ExpandingDock.iconSize))
            Text(
                current?.label ?: "—", style = IosType.subheadline.semibold, color = palette.textPrimary,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            Icon(SF.chevronUpChevronDown, contentDescription = null, tint = palette.textSecondary, modifier = Modifier.size(AppTheme.Layout.coverBadgeSize))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = palette.card) {
            items.forEach { item ->
                DropdownMenuItem(
                    text = { Text(item.label, style = IosType.body, color = palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    leadingIcon = { Icon(item.icon, contentDescription = null, tint = palette.textSecondary) },
                    trailingIcon = if (item.id == selectedId) {
                        { Icon(SF.checkmark, contentDescription = "Selected", tint = Theme.accent) }
                    } else null,
                    onClick = {
                        expanded = false
                        onSelect(item.id)
                    },
                )
            }
        }
    }
}
