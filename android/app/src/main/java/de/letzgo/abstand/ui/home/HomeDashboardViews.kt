package de.letzgo.abstand.ui.home

import de.letzgo.abstand.ui.podcasts.PodcastEpisodeDetailDestination
import de.letzgo.abstand.ui.podcasts.PodcastEpisodeListRow
import de.letzgo.abstand.ui.library.bookCards
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandBrowseStripItem
import de.letzgo.abstand.ui.components.AbstandDropdownPill
import de.letzgo.abstand.data.AbsLibrary
import androidx.compose.ui.layout.layout
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.ui.components.AbstandDockChip
import de.letzgo.abstand.data.Prefs
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.lazy.LazyListScope
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.layout.Arrangement
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.AppType
import androidx.compose.material3.Text
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.heading
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import de.letzgo.abstand.data.AbsAuthorShelfEntity
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsLibrarySeriesListItem
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfLocalization
import de.letzgo.abstand.data.AbsStartShelfSection
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.HomeShelfLogic
import de.letzgo.abstand.model.MainTab
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.LocalAbstandCardShadowEnabled
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandFixedBrowseStripSectionsLayout
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.destinations.AuthorDestination
import de.letzgo.abstand.ui.destinations.BookDetailDestination
import de.letzgo.abstand.ui.destinations.EpisodeDestination
import de.letzgo.abstand.ui.destinations.SeriesDestination
import de.letzgo.abstand.ui.components.AbstandIconButton

// iOS: HomeDashboardViews.swift — Home-Tab (`HomeTabRootView` + `StartDashboardView`).

/**
 * iOS: `HomeTabRootView` + `StartDashboardView` — Offline-Schalter in der Toolbar, darunter alle
 * eingeschalteten Regale (Continue listening als Hero-Karten, alle anderen als Kompaktkarten),
 * Pull-to-Refresh. Android: Kopfzeile in der Höhe der Bereichsleisten der anderen Tabs mit der
 * festen Überschrift „abstand“, ohne Buttons (iOS: `showsStrip: false`).
 */
@Composable
fun HomeTabRoot(model: AppModel = AppModel.shared) {
    val home = model.home
    val session = model.session
    val shelves by home.startShelves.collectAsState()
    val categoryList by home.startSettingsCategoryList.collectAsState()
    val disabled by home.startDisabledCategories.collectAsState()
    val isRestoring by session.isHomeContinueRestoreInProgress.collectAsState()
    val isBootstrapping by session.isAppBootstrapInProgress.collectAsState()
    val offlineManual by session.offlineHomeMode.collectAsState()
    val offlineAuto by session.offlineHomeModeAuto.collectAsState()
    val offline = offlineManual || offlineAuto
    val username by session.sessionUsername.collectAsState()
    var showOfflineConfirmation by remember { mutableStateOf(false) }

    // iOS: `.task(id: sessionUserId-isAppBootstrapInProgress)` → `probeServerConnectionIfNeeded`.
    LaunchedEffect(username, isBootstrapping) {
        if (!isBootstrapping) session.probeServerConnectionIfNeeded()
    }
    // iOS: Dashboard laden, wenn leer und kein Bootstrap/Cache läuft.
    LaunchedEffect(offline, username, isBootstrapping) {
        if (shelves.isEmpty() && !isBootstrapping && !session.hasCachedBootstrapContent()) {
            home.loadStartDashboard(force = offline)
        }
    }
    // iOS: `.onChange(of: offlineHomeUIActive)` / `startDisabledCategories` → Kategorie klemmen.
    LaunchedEffect(offline, disabled, categoryList.size) {
        if (!isBootstrapping) home.clampHomeBrowseSectionIfNeeded()
    }

    val continueId = AbsStartShelfLocalization.homeBrowseContinueSectionID
    val anyShelfEnabled = HomeShelfLogic.isAnyShelfEnabled(categoryList, disabled)
    val visibleShelves = if (isRestoring || !anyShelfEnabled) emptyList() else
        HomeShelfLogic.shelvesForHomeBrowseSection(continueId, categoryList, shelves, disabled)
            .filter(HomeShelfLogic::shelfHasVisibleContent)
    // Android: oben das gewählte Regal als horizontale Kartenreihe, darunter die Kategorie-Pills
    // (beim Scrollen oben fixiert), darunter die Bibliothek (Books + Podcasts, kombinierte Auswahl).
    var selectedCategory by rememberSaveable { mutableStateOf(Prefs.string(HOME_SHELF_KEY).orEmpty()) }
    val selectedShelf = visibleShelves.firstOrNull { it.category == selectedCategory } ?: visibleShelves.firstOrNull()
    val libraryChoices = rememberHomeLibraryChoices(model)
    var libraryChoiceId by rememberSaveable { mutableStateOf(Prefs.string(HOME_LIBRARY_KEY).orEmpty()) }
    val libraryChoice = libraryChoices.firstOrNull { it.id == libraryChoiceId } ?: libraryChoices.firstOrNull()
    LaunchedEffect(libraryChoice?.id) { libraryChoice?.let { focusHomeLibrary(model, it) } }
    val books by model.catalog.displayBooks.collectAsState()
    val booksLoading by model.catalog.isLoadingLibrary.collectAsState()
    val cardStyle by model.catalog.libraryBookCardStyle.collectAsState()
    val episodes by model.podcasts.podcastEpisodes.collectAsState()
    val episodesLoading by model.podcasts.isLoadingPodcasts.collectAsState()
    val navigator = LocalTabNavigator.current
    AbstandFixedBrowseStripSectionsLayout(
        title = MainTab.start.label,
        selection = continueId,
        showsStrip = true,
        sectionSpacing = AppTheme.Layout.withinSectionSpacing,
        strip = {
            Box(
                Modifier
                    .padding(start = AppTheme.Layout.tabPaddingH, top = AppTheme.ExpandingDock.verticalPadding, bottom = AppTheme.ExpandingDock.verticalPadding)
                    .height(AppTheme.ExpandingDock.activeHeight)
                    .semantics { heading() },
                contentAlignment = Alignment.CenterStart,
            ) {
                Text("abstand", style = AppType.titleLarge, color = Theme.palette.textPrimary, maxLines = 1)
            }
        },
        actions = {
            HomeGoOfflineToolbarButton(offline) {
                if (offline) session.exitOfflineHomeUI() else showOfflineConfirmation = true
            }
        },
        onRefresh = { home.refreshStartTabPullToRefresh() },
    ) {
        when {
            isRestoring -> item(key = "bootstrap") {
                // Kurz leer halten, bis die lokal rekonstruierten Regale atomar vorliegen.
                Spacer(Modifier.fillMaxWidth().height(AppTheme.Layout.homeBrowseBootstrapMinHeight))
            }
            !anyShelfEnabled -> item(key = "all-off") { HomeAllShelvesDisabledState() }
            selectedShelf == null -> item(key = "empty") { HomeSectionEmptyState(continueId, offline) }
            else -> {
                item(key = "shelf-row-${selectedShelf.category}") {
                    Box(Modifier.fullBleed(AppTheme.Layout.tabPaddingH)) { HomeShelfCarousel(selectedShelf) }
                }
                @OptIn(ExperimentalFoundationApi::class)
                stickyHeader(key = "shelf-pills") {
                    Box(Modifier.fullBleed(AppTheme.Layout.tabPaddingH).background(Theme.palette.background)) {
                        HomeShelfPills(visibleShelves, selectedShelf.category) { category ->
                            selectedCategory = category
                            Prefs.setString(HOME_SHELF_KEY, category)
                        }
                    }
                }
            }
        }
        if (libraryChoices.isNotEmpty() && libraryChoice != null) {
            item(key = "library-pill") {
                Row(Modifier.fillMaxWidth().padding(top = AppTheme.Layout.stackSpacing)) {
                    AbstandDropdownPill(
                        libraryChoices.map { AbstandBrowseStripItem(it.id, it.name, it.icon) },
                        libraryChoice.id,
                        { id ->
                            libraryChoiceId = id
                            Prefs.setString(HOME_LIBRARY_KEY, id)
                        },
                        Modifier.fillMaxWidth(),
                        SF.booksVerticalFill,
                        "Library",
                    )
                }
            }
            if (libraryChoice.isPodcast) {
                when {
                    episodesLoading && episodes.isEmpty() -> item(key = "lib-loading") { AbstandLoadingSpinner() }
                    episodes.isEmpty() -> item(key = "lib-empty") { AbstandSectionEmptyState("No episodes in the list.") }
                    else -> items(episodes, key = { "lib-ep-${it.progressLookupKey}" }) { episode ->
                        PodcastEpisodeListRow(model.podcasts, episode) { navigator?.push(PodcastEpisodeDetailDestination(episode)) }
                        LaunchedEffect(episode.progressLookupKey) { model.podcasts.loadMorePodcastsIfNeeded(episode.id) }
                    }
                }
            } else {
                when {
                    booksLoading && books.isEmpty() -> item(key = "lib-loading") { AbstandLoadingSpinner() }
                    books.isEmpty() -> item(key = "lib-empty") { AbstandSectionEmptyState("No books in this library.") }
                    else -> bookCards(books, cardStyle, 1, "lib-book", onAppear = { model.catalog.loadMoreIfNeeded(it.id) })
                }
            }
        }
    }

    if (showOfflineConfirmation) {
        AbstandDialog(
            title = "Enable offline mode?",
            onDismiss = { showOfflineConfirmation = false },
            message = "The server connection will be paused. You can only play downloaded content. Progress syncs when you go back online.",
            confirmLabel = "Go offline",
            dismissOnConfirm = false,
            onConfirm = {
                showOfflineConfirmation = false
                session.setOfflineHomeMode(true)
            },
        )
    }
}

/** iOS: `HomeGoOfflineToolbarButton` — statischer Offline-/Online-Schalter (nur Symbol). */
@Composable
private fun HomeGoOfflineToolbarButton(offline: Boolean, onClick: () -> Unit) {
    AbstandIconButton(if (offline) SF.icloudSlash else SF.icloud, if (offline) "Go online" else "Go offline", onClick = onClick)
}

/** iOS: `startDashboardShelfContent` — Continue listening als Hero-Karten, sonst Kompaktkarten. */
@Composable
private fun StartDashboardShelf(shelf: AbsStartShelfSection) {
    val rowPadding = PaddingValues(horizontal = AppTheme.Layout.tabPaddingH)
    val titleModifier = Modifier.padding(horizontal = AppTheme.Layout.tabPaddingH)
    if (shelf.category == HomeShelfLogic.homeContinueCategory) {
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.sectionSpacing)) {
            if (shelf.hasBooks || shelf.hasPodcastEpisodes) {
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
                    TabContentSectionTitle(shelf.displayTitle, titleModifier)
                    // Android: Kompaktkarten mit Play-Pille statt Hero-Karten.
                    HomeContinueCompactCarousel(shelf, rowPadding)
                }
            }
            if (shelf.hasAuthors) {
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
                    TabContentSectionTitle(shelf.displayTitle, titleModifier)
                    HomeAuthorsCompactCarousel(shelf.authors, rowPadding)
                }
            }
        }
    } else {
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
            TabContentSectionTitle(shelf.displayTitle, titleModifier)
            if (shelf.hasBooks) {
                HomeBooksCompactCarousel(shelf.books, rowPadding, usesEbookProgressDisplay = shelf.category == HomeShelfLogic.continueEbooksCategory)
            }
            if (shelf.hasSeries) HomeSeriesCompactCarousel(shelf.series, rowPadding)
            if (shelf.hasAuthors) HomeAuthorsCompactCarousel(shelf.authors, rowPadding)
            if (shelf.hasPodcastEpisodes) HomePodcastEpisodesCompactCarousel(shelf.podcastEpisodes, rowPadding)
        }
    }
}

// MARK: - Kategorie-Pills, Regal-Reihe und Bibliothek (Android)

/** Merkt die auf Home gewählte Bibliothek (Books- oder Podcast-Bibliothek). */
private const val HOME_LIBRARY_KEY = "abstand_android_home_library"

/** Eintrag der kombinierten Bibliotheks-Auswahl (Books + Podcasts). */
private data class HomeLibraryChoice(val id: String, val name: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val isPodcast: Boolean, val library: AbsLibrary)

@Composable
private fun rememberHomeLibraryChoices(model: AppModel): List<HomeLibraryChoice> {
    val session = model.session
    session.activeBooksLibraryIds.collectAsState().value
    session.activePodcastLibraryIds.collectAsState().value
    session.libraries.collectAsState().value
    return session.activeBookLibraries.map { HomeLibraryChoice("b:${it.id}", it.name, SF.booksVerticalFill, false, it) } +
        session.activePodcastLibraries.map { HomeLibraryChoice("p:${it.id}", it.name, SF.micFill, true, it) }
}

/** Gewählte Bibliothek fokussieren, damit Katalog bzw. Podcast-Feed sie laden. */
private fun focusHomeLibrary(model: AppModel, choice: HomeLibraryChoice) {
    if (choice.isPodcast) model.session.focusPodcastLibrary(choice.library) else model.session.focusBooksLibrary(choice.library)
}

/** Kinder randlos über die horizontalen Listen-Ränder hinaus (Karussell, fixierte Pills). */
private fun Modifier.fullBleed(horizontal: Dp): Modifier = layout { measurable, constraints ->
    val extra = horizontal.roundToPx() * 2
    val placeable = measurable.measure(constraints.copy(minWidth = constraints.maxWidth + extra, maxWidth = constraints.maxWidth + extra))
    layout(constraints.maxWidth, placeable.height) { placeable.place(-extra / 2, 0) }
}

/** Gewähltes Regal als horizontale Kartenreihe (ohne Überschrift — die Pill darunter nennt es). */
@Composable
private fun HomeShelfCarousel(shelf: AbsStartShelfSection) {
    val rowPadding = PaddingValues(horizontal = AppTheme.Layout.tabPaddingH)
    when {
        shelf.category == HomeShelfLogic.homeContinueCategory && (shelf.hasBooks || shelf.hasPodcastEpisodes) -> HomeContinueCompactCarousel(shelf, rowPadding)
        shelf.hasBooks -> HomeBooksCompactCarousel(shelf.books, rowPadding, usesEbookProgressDisplay = shelf.category == HomeShelfLogic.continueEbooksCategory)
        shelf.hasPodcastEpisodes -> HomePodcastEpisodesCompactCarousel(shelf.podcastEpisodes, rowPadding)
        shelf.hasSeries -> HomeSeriesCompactCarousel(shelf.series, rowPadding)
        shelf.hasAuthors -> HomeAuthorsCompactCarousel(shelf.authors, rowPadding)
    }
}

// MARK: - (bisher) Kategorie-Liste (Android)

/** Merkt die zuletzt gewählte Home-Kategorie (Android-eigen; iOS zeigt alle Regale untereinander). */
private const val HOME_SHELF_KEY = "abstand_android_home_shelf_category"

/** Pill-Reihe der Kategorien in der Kopfzeile — aktive Pill in Akzentfarbe, horizontal scrollbar. */
@Composable
private fun HomeShelfPills(shelves: List<AbsStartShelfSection>, selectedCategory: String?, onSelect: (String) -> Unit) {
    val dock = AppTheme.ExpandingDock
    val state = rememberLazyListState()
    val selectedIndex = shelves.indexOfFirst { it.category == selectedCategory }
    LaunchedEffect(selectedIndex) { if (selectedIndex > 0) state.animateScrollToItem(selectedIndex - 1) }
    LazyRow(
        Modifier.fillMaxWidth(),
        state = state,
        contentPadding = PaddingValues(start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.stackSpacing, top = dock.verticalPadding, bottom = dock.verticalPadding),
        horizontalArrangement = Arrangement.spacedBy(dock.itemSpacing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(shelves, key = { it.category }) { shelf ->
            AbstandDockChip(
                label = shelf.displayTitle,
                icon = SF.named(AbsStartShelfLocalization.stripSystemImage(shelf.category)) ?: SF.squareGrid2x2,
                selected = shelf.category == selectedCategory,
                onClick = { onSelect(shelf.category) },
                checkmarkWhenSelected = false,
                accentWhenSelected = true,
            )
        }
    }
}

/** Gewählte Kategorie als senkrechte Liste aus Kompaktkarten (volle Breite). */
private fun LazyListScope.homeShelfList(shelf: AbsStartShelfSection, progress: Map<String, AbsUserMediaProgress>) {
    item(key = "title-${shelf.category}") { TabContentSectionTitle(shelf.displayTitle) }
    if (shelf.category == HomeShelfLogic.homeContinueCategory) {
        val rows = AbsStartShelfMergedRow.merged(shelf.books, shelf.podcastEpisodes, progress)
        items(rows, key = { "row-${it.id}" }) { row ->
            when (row) {
                is AbsStartShelfMergedRow.Book -> HomeBookListCard(row.book, usesEbookProgressDisplay = false)
                is AbsStartShelfMergedRow.PodcastEpisode -> HomeEpisodeListCard(row.episode)
            }
        }
    } else {
        val ebooks = shelf.category == HomeShelfLogic.continueEbooksCategory
        items(shelf.books, key = { "book-${it.id}" }) { HomeBookListCard(it, ebooks) }
        items(shelf.podcastEpisodes, key = { "ep-${it.progressLookupKey}" }) { HomeEpisodeListCard(it) }
    }
    items(shelf.series, key = { "series-${it.id}" }) { HomeSeriesCard(it) }
    items(shelf.authors, key = { "author-${it.id}" }) { HomeAuthorCard(it) }
}

@Composable
private fun HomeBookListCard(book: AbsBook, usesEbookProgressDisplay: Boolean) {
    val navigator = LocalTabNavigator.current
    HomeBookCompactCard(book, onOpen = { navigator?.push(BookDetailDestination(book.id)) }, usesEbookProgressDisplay = usesEbookProgressDisplay)
}

@Composable
private fun HomeEpisodeListCard(episode: AbsPodcastEpisodeListItem) {
    val navigator = LocalTabNavigator.current
    HomeEpisodeCompactCard(episode, onOpen = { navigator?.push(EpisodeDestination(episode.libraryItemId, episode.episodeId)) })
}

@Composable
private fun HomeSeriesCard(item: AbsLibrarySeriesListItem) {
    val navigator = LocalTabNavigator.current
    val coverId = seriesCoverBookIds(item.books).firstOrNull()
    val count = item.books?.size ?: 0
    val authors = item.cardAuthorsLine?.trim().orEmpty()
    HomeEntityCompactCard(
        title = item.name,
        subtitleLabel = if (authors.isEmpty()) "Books" else "Author",
        subtitle = if (authors.isEmpty()) (if (count > 0) "$count" else "—") else authors,
        footer = booksCountLabel(count),
        accessibilityHint = "Opens series details.",
        onOpen = { navigator?.push(SeriesDestination(item.id, item.name)) },
    ) {
        if (coverId != null) SquareCoverImage(itemId = coverId, tint = coverTint(coverId)) else HomeEntityCoverPlaceholder(SF.booksVerticalFill)
    }
}

@Composable
private fun HomeAuthorCard(author: AbsAuthorShelfEntity) {
    val navigator = LocalTabNavigator.current
    HomeEntityCompactCard(
        title = author.name,
        subtitleLabel = "Books",
        subtitle = author.numBooks?.toString() ?: "—",
        footer = booksCountLabel(author.numBooks),
        accessibilityHint = "Opens author details.",
        onOpen = { navigator?.push(AuthorDestination(author.id, author.name)) },
    ) {
        if (author.hasAuthorImage) AuthorImage(author.id) else HomeEntityCoverPlaceholder(SF.personFill)
    }
}

// MARK: - Karussells

private val isRegularWidth: Boolean
    @Composable get() = LocalConfiguration.current.screenWidthDp >= TabletWidthDp

/**
 * iOS: `HomeCompactCardCarousel` — Karten ≈ 3/4 der Regalbreite, Mindesthöhe = Cover-Seite.
 * Material: randloser `LazyRow` mit `tabPaddingH`-Innenabstand (uncontained carousel).
 */
@Composable
private fun <T> HomeCompactCardCarousel(
    items: List<T>,
    key: (T) -> String,
    contentPadding: PaddingValues,
    card: @Composable LazyItemScope.(T, Dp) -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val cardWidth = AppTheme.Layout.homeCompactCardWidth(maxWidth - AppTheme.Layout.tabPaddingH * 2)
        CompositionLocalProvider(LocalAbstandCardShadowEnabled provides false) {
            LazyRow(
                contentPadding = contentPadding,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
                verticalAlignment = Alignment.Top,
                modifier = Modifier.fillMaxWidth().heightIn(min = AppTheme.Layout.homeCompactCardCoverSide),
            ) {
                items(items, key = key) { item -> card(item, cardWidth) }
            }
        }
    }
}

/**
 * iOS: `HomeCoverCardCarousel` — Cover-Karten in der Breite von „New episodes“
 * (Compact 2¼ sichtbar, Tablet +2).
 */
@Composable
private fun <T> HomeCoverCardCarousel(
    items: List<T>,
    key: (T) -> String,
    contentPadding: PaddingValues,
    card: @Composable LazyItemScope.(T, Dp) -> Unit,
) {
    val regular = isRegularWidth
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val cardWidth = AppTheme.Layout.homeNewestEpisodesCardWidth(maxWidth - AppTheme.Layout.tabPaddingH * 2, regular)
        CompositionLocalProvider(LocalAbstandCardShadowEnabled provides false) {
            LazyRow(
                contentPadding = contentPadding,
                horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
                verticalAlignment = Alignment.Top,
                modifier = Modifier.fillMaxWidth().heightIn(min = cardWidth + AppTheme.Layout.libraryHeroMetadataBlockHeight),
            ) {
                items(items, key = key) { item -> card(item, cardWidth) }
            }
        }
    }
}

/** iOS: `HomeBooksCompactCarousel`. */
@Composable
private fun HomeBooksCompactCarousel(books: List<AbsBook>, contentPadding: PaddingValues, usesEbookProgressDisplay: Boolean) {
    val navigator = LocalTabNavigator.current
    HomeCompactCardCarousel(books, { it.id }, contentPadding) { book, width ->
        Column(Modifier.width(width)) {
            HomeBookCompactCard(book, onOpen = { navigator?.push(BookDetailDestination(book.id)) }, usesEbookProgressDisplay = usesEbookProgressDisplay)
        }
    }
}

/**
 * Android: „Continue listening“ als Kompakt-Karussell — Bücher und Folgen gemischt nach
 * `lastUpdate` (Reihenfolge wie die Hero-Reihe, nur bei geänderter Rangfolge neu gebaut).
 */
@Composable
private fun HomeContinueCompactCarousel(shelf: AbsStartShelfSection, contentPadding: PaddingValues) {
    val navigator = LocalTabNavigator.current
    val progress by AppModel.shared.home.progressByItemId.collectAsState()
    val merged = AbsStartShelfMergedRow.merged(shelf.books, shelf.podcastEpisodes, progress)
    val signature = merged.joinToString("\u001f") { it.id }
    val rows = remember(signature) { merged }
    HomeCompactCardCarousel(rows, { it.id }, contentPadding) { row, width ->
        Column(Modifier.width(width)) {
            when (row) {
                is AbsStartShelfMergedRow.Book ->
                    HomeBookCompactCard(row.book, onOpen = { navigator?.push(BookDetailDestination(row.book.id)) })
                is AbsStartShelfMergedRow.PodcastEpisode ->
                    HomeEpisodeCompactCard(row.episode, onOpen = { navigator?.push(EpisodeDestination(row.episode.libraryItemId, row.episode.episodeId)) })
            }
        }
    }
}

/** iOS: `HomePodcastEpisodesCompactCarousel`. */
@Composable
private fun HomePodcastEpisodesCompactCarousel(episodes: List<AbsPodcastEpisodeListItem>, contentPadding: PaddingValues) {
    val navigator = LocalTabNavigator.current
    HomeCompactCardCarousel(episodes, { it.progressLookupKey }, contentPadding) { episode, width ->
        Column(Modifier.width(width)) {
            HomeEpisodeCompactCard(episode, onOpen = { navigator?.push(EpisodeDestination(episode.libraryItemId, episode.episodeId)) })
        }
    }
}

/** iOS: `HomeSeriesCompactCarousel`. */
@Composable
private fun HomeSeriesCompactCarousel(series: List<AbsLibrarySeriesListItem>, contentPadding: PaddingValues) {
    val navigator = LocalTabNavigator.current
    HomeCompactCardCarousel(series, { it.id }, contentPadding) { item, width ->
        val coverId = seriesCoverBookIds(item.books).firstOrNull()
        val count = item.books?.size ?: 0
        val authors = item.cardAuthorsLine?.trim().orEmpty()
        Column(Modifier.width(width)) {
            HomeEntityCompactCard(
                title = item.name,
                subtitleLabel = if (authors.isEmpty()) "Books" else "Author",
                subtitle = if (authors.isEmpty()) (if (count > 0) "$count" else "—") else authors,
                footer = booksCountLabel(count),
                accessibilityHint = "Opens series details.",
                onOpen = { navigator?.push(SeriesDestination(item.id, item.name)) },
            ) {
                if (coverId != null) SquareCoverImage(itemId = coverId, tint = coverTint(coverId)) else HomeEntityCoverPlaceholder(SF.booksVerticalFill)
            }
        }
    }
}

/** iOS: `HomeAuthorsCompactCarousel`. */
@Composable
private fun HomeAuthorsCompactCarousel(authors: List<AbsAuthorShelfEntity>, contentPadding: PaddingValues) {
    val navigator = LocalTabNavigator.current
    HomeCompactCardCarousel(authors, { it.id }, contentPadding) { author, width ->
        Column(Modifier.width(width)) {
            HomeEntityCompactCard(
                title = author.name,
                subtitleLabel = "Books",
                subtitle = author.numBooks?.toString() ?: "—",
                footer = booksCountLabel(author.numBooks),
                accessibilityHint = "Opens author details.",
                onOpen = { navigator?.push(AuthorDestination(author.id, author.name)) },
            ) {
                if (author.hasAuthorImage) AuthorImage(author.id) else HomeEntityCoverPlaceholder(SF.personFill)
            }
        }
    }
}

/** iOS: `HomeAuthorsCoverCardCarousel` — Autoren im Continue-Regal als Cover-Karten. */
@Composable
private fun HomeAuthorsCoverCardCarousel(authors: List<AbsAuthorShelfEntity>, contentPadding: PaddingValues) {
    val navigator = LocalTabNavigator.current
    HomeCoverCardCarousel(authors, { it.id }, contentPadding) { author, width ->
        HomeEntityCoverCard(
            title = author.name,
            detailLabel = "Books",
            detailValue = author.numBooks?.toString() ?: "—",
            accessibilityHint = "Opens author details.",
            cardWidth = width,
            onOpen = { navigator?.push(AuthorDestination(author.id, author.name)) },
        ) {
            if (author.hasAuthorImage) AuthorImage(author.id) else HomeEntityCoverPlaceholder(SF.personFill)
        }
    }
}

/** iOS: `browseSeriesCoverBookIds(from:)` — Buch-IDs für Serien-Cover (erste zuerst). */
fun seriesCoverBookIds(books: List<AbsBook>?, maxCount: Int = 4): List<String> {
    val seen = HashSet<String>()
    return books.orEmpty().map { it.id.trim() }.filter { it.isNotEmpty() && seen.add(it) }.take(maxCount)
}

// MARK: - Leerzustände

/** iOS: `startDashboardSectionEmptyState` (`ContentUnavailableView`). */
@Composable
private fun LazyItemScope.HomeSectionEmptyState(category: String, offline: Boolean) {
    val label = when (category) {
        AbsStartShelfLocalization.homeBrowseContinueSectionID -> AbsStartShelfLocalization.homeBrowseContinueStripLabel
        AbsStartShelfLocalization.homeBrowseRecentSectionID -> AbsStartShelfLocalization.homeBrowseRecentStripLabel
        else -> AbsStartShelfLocalization.displayTitle(category, "")
    }
    val description = if (offline) {
        "Titles you're currently playing will appear here once downloaded."
    } else {
        "Content for this shelf appears when your server provides it."
    }
    AbstandEmptyScreen(
        title = label,
        icon = SF.byName[AbsStartShelfLocalization.stripSystemImage(category)] ?: SF.playCircleFill,
        description = description,
        modifier = Modifier.fillParentMaxHeight(EmptyStateParentFraction).padding(top = AppTheme.Layout.sectionSpacing),
    )
}

/** iOS: `startDashboardAllShelvesDisabledState` — Android: Knopf direkt zu den Home-Einstellungen. */
@Composable
private fun LazyItemScope.HomeAllShelvesDisabledState() {
    val navigator = LocalTabNavigator.current
    AbstandEmptyScreen(
        title = "All shelves are off",
        icon = SF.gearshape2,
        description = "Open Settings → Appearance → Home to turn shelves back on.",
        modifier = Modifier.fillParentMaxHeight(EmptyStateParentFraction),
        actions = {
            AbstandProminentButton("Home settings", onClick = { navigator?.push(HomeShelvesSettingsDestination) })
        },
    )
}

/** Leerzustände füllen den sichtbaren Bereich (Material: zentriert im Viewport). */
private const val EmptyStateParentFraction = 0.8f

/** Stabiler Schlüssel eines Home-Regals (Listen-Key und Pill-ID). */
private fun homeShelfKey(shelf: AbsStartShelfSection): String = "${shelf.category}-${shelf.id}"
