package de.letzgo.abstand.ui.podcasts

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsPodcastCharts
import de.letzgo.abstand.data.AbsPodcastDirectorySearchHit
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.PodcastLogic
import de.letzgo.abstand.model.PodcastStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandBackButton
import de.letzgo.abstand.ui.components.AbstandChip
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandInlineSpinner
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandMenuBox
import de.letzgo.abstand.ui.components.AbstandMenuButton
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.components.AbstandSearchField
import de.letzgo.abstand.ui.components.AbstandSegmentedControl
import de.letzgo.abstand.ui.components.AbstandTextButton
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.abstandScrollBottomPadding
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.launch

// MARK: - Sort-Menü (iOS: `AbstandCatalogSortToolbarMenu`)

/**
 * iOS: `AbstandCatalogSortToolbarMenu` — Toolbar-Knopf mit Menü „Sort by“ (Häkchen am aktuellen
 * Feld) und, außer bei [showsOrder] = `false` (Random), „Ascending“/„Descending“.
 */
@Composable
internal fun <F> PodcastSortMenuButton(
    fields: List<F>,
    selected: F,
    title: (F) -> String,
    descending: Boolean,
    showsOrder: Boolean,
    onSelectField: (F) -> Unit,
    onSelectDescending: (Boolean) -> Unit,
) {
    AbstandMenuButton(SF.arrowUpArrowDown, "Sort", tint = Theme.accent) {
        picker(fields, selected, title, onSelectField, title = "Sort by")
        if (showsOrder) {
            divider()
            picker(
                listOf(false, true), descending, { if (it) "Descending" else "Ascending" }, onSelectDescending,
                icon = { if (it) SF.arrowDown else SF.arrowUp },
            )
        }
    }
}

// MARK: - Gerüst für gepushte Seiten mit Inline-Titel

/** Inline-Titel + Zurück + Aktionen, Inhalt erhält das Top-Bar-Padding (iOS: Push mit `.inline`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PodcastInlineTitleScaffold(
    title: String,
    onBack: () -> Unit,
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    val palette = Theme.palette
    Scaffold(
        containerColor = palette.background,
        contentColor = palette.textPrimary,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { AbstandBackButton(onBack) },
                actions = actions,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = palette.background,
                    scrolledContainerColor = palette.background,
                    titleContentColor = palette.textPrimary,
                    navigationIconContentColor = palette.textPrimary,
                    actionIconContentColor = Theme.accent,
                ),
            )
        },
    ) { inner -> content(inner) }
}

/** iOS: `Picker(.segmented)` — [AbstandSegmentedControl]. */
@Composable
internal fun <T> PodcastSegmentedPicker(options: List<T>, selection: T, label: (T) -> String, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    AbstandSegmentedControl(options, selection, label, onSelect, modifier)
}

// MARK: - Add podcast (Verzeichnissuche + iTunes-Charts)

/** iOS: `PodcastAddSource`. */
internal enum class PodcastAddSource(val label: String) { search("Search"), charts("Charts") }

/** iOS: `PodcastCatalogNavigation.addPodcast` → `PodcastAddFromSearchView` (Titel „Add podcast“). */
class PodcastAddDestination : TabDestination {
    override val key: String = "podcast-add"

    @Composable
    override fun Content(navigator: TabNavigator) {
        PodcastAddScreen(navigator, this)
    }
}

/**
 * iOS: `PodcastAddFromSearchView` — Segment „Search“ (Apple-Podcasts-Suche über den Server) /
 * „Charts“ (iTunes-Toplisten je Kategorie), Storefront-Menü rechts oben, Treffer öffnen die
 * Sendungsvorschau [PodcastDirectoryShowDestination].
 */
@Composable
internal fun PodcastAddScreen(navigator: TabNavigator, self: TabDestination, store: PodcastStore = AppModel.shared.podcasts) {
    val dir by store.directory.collectAsState()
    val shows by store.podcastShows.collectAsState()
    val reachable by AppModel.shared.session.isNetworkReachable.collectAsState()
    var query by rememberSaveable { mutableStateOf("") }
    var lastScheduledQuery by rememberSaveable { mutableStateOf<String?>(null) }
    var source by rememberSaveable { mutableStateOf(PodcastAddSource.search) }
    var lastChartsCountry by rememberSaveable { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        store.syncPodcastDirectoryEffectiveCountry()
        // Frisch geöffnet (kein Rücksprung aus dem Sendungsdetail): alte Treffer verwerfen.
        if (query.swiftTrim().isEmpty()) store.clearPodcastDirectorySearch()
        if (store.podcastShows.value.isEmpty()) store.reloadPodcastShowsCatalog()
    }
    LaunchedEffect(query, source) {
        if (source == PodcastAddSource.search && query != lastScheduledQuery) {
            lastScheduledQuery = query
            store.schedulePodcastDirectorySearch(query)
        }
    }
    LaunchedEffect(source, dir.effectiveCountry) {
        val countryChanged = lastChartsCountry != null && lastChartsCountry != dir.effectiveCountry
        lastChartsCountry = dir.effectiveCountry
        when (source) {
            PodcastAddSource.charts -> store.loadPodcastCharts(force = countryChanged)
            PodcastAddSource.search -> if (countryChanged && query.swiftTrim().length >= 2) store.schedulePodcastDirectorySearch(query)
        }
    }
    DisposableEffect(Unit) {
        onDispose {
            // Push aufs Sendungsdetail lässt die Seite im Stack — dann Suche/Charts behalten.
            if (self !in navigator.backStack) {
                store.clearPodcastDirectorySearch()
                store.clearPodcastCharts()
                store.clearPodcastDirectoryCountryOverride()
            }
        }
    }

    PodcastInlineTitleScaffold(
        title = "Add podcast",
        onBack = { navigator.pop() },
        actions = { PodcastDirectoryCountryMenu(store, dir.effectiveCountry) },
    ) { inner ->
        Column(Modifier.fillMaxSize().padding(top = inner.calculateTopPadding())) {
            PodcastSegmentedPicker(
                options = PodcastAddSource.entries,
                selection = source,
                label = { it.label },
                onSelect = { source = it },
                modifier = Modifier.padding(horizontal = AppTheme.Layout.tabPaddingH).padding(
                    top = AppTheme.Layout.rowSpacing,
                    bottom = if (source == PodcastAddSource.search) AppTheme.Layout.inlineSpacing else AppTheme.Layout.rowSpacing,
                ),
            )
            val onOpen: (AbsPodcastDirectorySearchHit) -> Unit = { navigator.push(PodcastDirectoryShowDestination(it)) }
            when (source) {
                PodcastAddSource.search -> {
                    AbstandSearchField(
                        query = query,
                        onQueryChange = { query = it },
                        placeholder = "Search Apple Podcasts",
                        modifier = Modifier.padding(horizontal = AppTheme.Layout.tabPaddingH).padding(bottom = AppTheme.Layout.rowSpacing),
                    )
                    when {
                        query.swiftTrim().length < 2 -> AbstandEmptyScreen(
                            title = "Search podcasts",
                            icon = SF.dotRadiowavesLeftAndRight,
                            description = "Results come from Apple Podcasts (${dir.effectiveCountry.uppercase()} store). " +
                                "Subscribing adds the show to your Audiobookshelf library.",
                        )
                        dir.searchLoading -> AbstandLoadingSpinner()
                        dir.searchHits.isEmpty() -> AbstandEmptyScreen(
                            title = "No shows found", icon = SF.magnifyingglass, description = "Try a different search term.",
                        )
                        else -> PodcastHitsList(store, dir.searchHits, shows, reachable, dir.subscribeInProgressHitId, onOpen)
                    }
                }
                PodcastAddSource.charts -> {
                    PodcastChartsCategoryPillStrip(
                        categories = AbsPodcastCharts.chartCategories,
                        selectedGenreId = dir.chartsSelectedGenreId,
                        onSelect = { store.selectPodcastChartsCategory(it) },
                    )
                    Spacer(Modifier.height(AppTheme.Layout.withinSectionSpacing))
                    when {
                        dir.chartsLoading && dir.chartsHits.isEmpty() -> AbstandLoadingSpinner()
                        dir.chartsHits.isEmpty() -> AbstandEmptyScreen(
                            title = "Charts unavailable", icon = SF.chartBar,
                            description = "Check your network connection or try another category.",
                        )
                        else -> PodcastHitsList(store, dir.chartsHits, shows, reachable, dir.subscribeInProgressHitId, onOpen)
                    }
                }
            }
        }
    }
}

/** iOS: `PodcastDirectoryCountryMenuItems` — Storefront wählen (Code rechts oben). */
@Composable
private fun PodcastDirectoryCountryMenu(store: PodcastStore, effective: String) {
    val codes = remember { AbsPodcastCharts.directoryStorefrontMenuCodes(store.defaultPodcastDirectoryCountryCode()) }
    AbstandMenuBox(
        Modifier.semantics { contentDescription = "Podcast store region" },
        anchor = { open -> AbstandTextButton(effective.uppercase(), open, emphasized = true) },
    ) {
        picker(
            codes, effective,
            { code -> "${AbsPodcastCharts.directoryStorefrontDisplayName(code)} (${code.uppercase()})" },
            { code -> store.setPodcastDirectoryCountryOverride(code) },
        )
    }
}

@Composable
private fun PodcastHitsList(
    store: PodcastStore,
    hits: List<AbsPodcastDirectorySearchHit>,
    shows: List<AbsBook>,
    reachable: Boolean,
    subscribingId: String?,
    onOpen: (AbsPodcastDirectorySearchHit) -> Unit,
) {
    val scope = rememberCoroutineScope()
    // Feed-URLs der Bibliothek — „In library“ statt Subscribe (iOS: `podcastDirectoryHitIsInLibrary`).
    val libraryFeeds = remember(shows) { shows.mapNotNull { PodcastLogic.normalizedPodcastFeedURL(it.media.metadata.feedUrl) }.toSet() }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.tabPaddingH,
            top = AppTheme.Layout.tightSpacing, bottom = abstandScrollBottomPadding(),
        ),
        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
    ) {
        items(hits, key = { "hit-${it.id}-${it.feedUrl}" }) { hit ->
            PodcastDirectoryHitRow(
                hit = hit,
                isInLibrary = PodcastLogic.normalizedPodcastFeedURL(hit.feedUrl)?.let { it in libraryFeeds } ?: false,
                isSubscribing = subscribingId == hit.id,
                subscribeEnabled = !hit.feedUrl.isNullOrBlank() && reachable && subscribingId == null,
                onOpen = { onOpen(hit) },
                onSubscribe = { scope.launch { store.subscribeToPodcastDirectoryHit(hit) } },
            )
        }
    }
}

/**
 * iOS: `PodcastChartsCategoryPillStrip` — Kategorien als Text-Kapseln im Dock-Farbschema,
 * horizontal scrollend.
 */
@Composable
internal fun PodcastChartsCategoryPillStrip(
    categories: List<AbsPodcastCharts.ChartCategory>,
    selectedGenreId: Int?,
    onSelect: (Int?) -> Unit,
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = AppTheme.Layout.tabPaddingH, vertical = AppTheme.Layout.pillVerticalPadding),
        horizontalArrangement = Arrangement.spacedBy(AppTheme.ExpandingDock.itemSpacing),
    ) {
        items(categories, key = { it.id }) { category ->
            val selected = selectedGenreId == category.genreId
            AbstandChip(category.title, selected, onClick = { if (!selected) onSelect(category.genreId) })
        }
    }
}

/** iOS: `PodcastDirectoryHitRow` — Treffer-Karte (Cover, Titel, Host, Genres, Folgenzahl, Subscribe). */
@Composable
internal fun PodcastDirectoryHitRow(
    hit: AbsPodcastDirectorySearchHit,
    isInLibrary: Boolean,
    isSubscribing: Boolean,
    subscribeEnabled: Boolean,
    onOpen: () -> Unit,
    onSubscribe: () -> Unit,
) {
    val palette = Theme.palette
    PodcastRowCardChrome(onClick = onOpen) {
        Row(horizontalArrangement = Arrangement.spacedBy(PodcastRowLayout.cardInset)) {
            CoverImage(
                url = hit.cover,
                cacheScopeId = "podcast-dir:${hit.id}",
                requiresAuthorization = false,
                modifier = Modifier.size(PodcastRowLayout.coverSide),
            )
            Column(
                Modifier
                    .weight(1f)
                    .height(PodcastRowLayout.coverSide)
                    .padding(vertical = AppTheme.Layout.libraryRowTextInset)
                    .padding(end = AppTheme.Layout.libraryRowTextInset),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing),
            ) {
                Text(hit.title, style = IosType.headline, color = palette.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                hit.artistName?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = IosType.subheadline, color = palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                directoryHitContextLine(hit)?.let {
                    Text(it, style = IosType.caption, color = palette.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Spacer(Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val n = hit.trackCount ?: 0
                    Text(
                        if (n > 0) (if (n == 1) "1 episode" else "$n episodes") else "",
                        style = IosType.subheadline, color = palette.textSecondary, modifier = Modifier.weight(1f),
                    )
                    if (isInLibrary) {
                        PodcastInLibraryLabel()
                    } else {
                        AbstandProminentButton(onClick = onSubscribe, enabled = subscribeEnabled || isSubscribing) {
                            if (isSubscribing) AbstandInlineSpinner(color = Theme.onAccent) else Text("Subscribe")
                        }
                    }
                }
            }
        }
    }
}

/** Einheitlicher „In library“-Status (Icon + Text im Akzent). */
@Composable
internal fun PodcastInLibraryLabel(style: androidx.compose.ui.text.TextStyle = IosType.caption.semibold) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.badgeSpacing)) {
        Icon(SF.checkmarkCircleFill, contentDescription = null, tint = Theme.accent, modifier = Modifier.size(InLibraryIconSize))
        Text("In library", style = style, color = Theme.accent)
    }
}

private val InLibraryIconSize = 14.dp

/** Genres + Explicit aus dem Verzeichnis (iOS: `contextLine`). */
private fun directoryHitContextLine(hit: AbsPodcastDirectorySearchHit): String? {
    val parts = mutableListOf<String>()
    val genres = (hit.genres ?: emptyList()).map { it.swiftTrim() }.filter { it.isNotEmpty() }
    if (genres.isNotEmpty()) parts.add(genres.take(2).joinToString(" · "))
    if (hit.explicit == true) parts.add("Explicit")
    return if (parts.isEmpty()) null else parts.joinToString(" · ")
}
