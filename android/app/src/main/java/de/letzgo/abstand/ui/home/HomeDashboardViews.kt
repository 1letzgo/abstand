package de.letzgo.abstand.ui.home

import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsAuthorShelfEntity
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsLibrarySeriesListItem
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfLocalization
import de.letzgo.abstand.data.AbsStartShelfMergedRow
import de.letzgo.abstand.data.AbsStartShelfSection
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.logic.BooksBrowseSection
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.HomeLibraryLogic
import de.letzgo.abstand.model.HomeShelfLogic
import de.letzgo.abstand.model.ShellRoute
import de.letzgo.abstand.model.SessionStore
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.LocalAbstandCardShadowEnabled
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandBrowsePills
import de.letzgo.abstand.ui.components.AbstandBrowseStripItem
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandFixedBrowseStripSectionsLayout
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandProminentButton
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.destinations.AuthorDestination
import de.letzgo.abstand.ui.destinations.BookDetailDestination
import de.letzgo.abstand.ui.destinations.EpisodeDestination
import de.letzgo.abstand.ui.destinations.SeriesDestination
import de.letzgo.abstand.ui.library.BooksLibraryToolbar
import de.letzgo.abstand.ui.library.bookCards
import de.letzgo.abstand.ui.library.icon
import de.letzgo.abstand.ui.library.booksBrowseSectionItems
import de.letzgo.abstand.ui.library.rememberBooksBrowseSectionContent
import de.letzgo.abstand.ui.podcasts.PodcastsToolbarActions
import de.letzgo.abstand.ui.podcasts.podcastSectionStripItems
import de.letzgo.abstand.ui.podcasts.podcastsSectionItems
import de.letzgo.abstand.ui.podcasts.rememberPodcastsSectionContent

// iOS: HomeDashboardViews.swift — Home-Tab (`HomeTabRootView` + `StartDashboardView`).


/**
 * iOS: `HomeTabRootView` + `StartDashboardView` (Offline-Schalter, Regale, Pull-to-Refresh).
 * Android: Home ist die gemeinsame Bibliotheksansicht (die Tabs Books und Podcasts gibt es nicht):
 * - Kopfzeile: Kategorie-Pills der Regale (aktive in Akzentfarbe), rechts der Offline-Schalter.
 * - Das gewählte Regal als horizontale Kartenreihe (randlos).
 * - Darunter die Bibliotheksleiste, beim Scrollen unter der Kopfzeile fixiert: Bibliothek (Books
 *   und Podcasts kombiniert) + Bereich als Pills, rechts die Aktionen des alten Tabs.
 * - Darunter der Bereichsinhalt wie in den alten Tabs (Books-Sektionen bzw. Podcast-Folgen).
 * Pull-to-Refresh lädt Regale und die gewählte Bibliothek neu.
 */
@OptIn(ExperimentalFoundationApi::class)
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
    // Oben fest nur „Continue listening“; die übrigen Regale stehen im Bereichs-Dropdown der Bibliothek.
    val continueShelf = visibleShelves.firstOrNull { HomeShelfLogic.isContinueCategory(it.category) }

    // Bibliotheksleiste: kombinierte Auswahl (Books + Podcasts), gemerkt im Session-Store.
    val libraryChoices = rememberHomeLibraryChoices(session)
    val storedChoiceId by session.homeLibraryChoiceId.collectAsState()
    val focusedBooks by session.focusedBooksLibrary.collectAsState()
    val focusedPodcasts by session.focusedPodcastLibrary.collectAsState()
    val libraryChoice = HomeLibraryLogic.resolve(libraryChoices, storedChoiceId, focusedBooks?.id, focusedPodcasts?.id)
    LaunchedEffect(libraryChoice?.id) {
        val choice = libraryChoice ?: return@LaunchedEffect
        session.selectHomeLibraryChoice(choice.id)
        if (choice.isPodcast) {
            // iOS: `.onAppear` des Podcasts-Tabs — leere Liste nachladen.
            val store = model.podcasts
            if (store.podcastEpisodes.value.isEmpty() && !store.isLoadingPodcasts.value) {
                store.restorePodcastCatalogFromLocalStore()
                store.reloadPodcastLibrary(reset = true)
            }
        } else {
            // iOS: `.task` der Books-Sektion.
            model.catalog.ensureActiveSectionLoaded()
        }
    }
    val libraryShelves = remember(visibleShelves, libraryChoice) { libraryChoice?.let { homeShelvesForLibrary(visibleShelves, it) }.orEmpty() }
    // Gewähltes Regal im Dropdown, gemerkt als „<Bibliothek>|<Kategorie>“ (leer = normaler Bereich).
    var shelfPick by rememberSaveable { mutableStateOf(Prefs.string(HOME_SHELF_KEY).orEmpty()) }
    val activeShelf = libraryChoice?.let { choice -> libraryShelves.firstOrNull { "${choice.id}|${it.category}" == shelfPick } }
    val selectShelf: (String?) -> Unit = { category ->
        shelfPick = if (category == null || libraryChoice == null) "" else "${libraryChoice.id}|$category"
        Prefs.setString(HOME_SHELF_KEY, shelfPick)
    }
    val booksContent = if (libraryChoice != null && !libraryChoice.isPodcast) rememberBooksBrowseSectionContent(model.catalog, model) else null
    val podcastsContent = if (libraryChoice?.isPodcast == true) rememberPodcastsSectionContent(model) else null

    // Bereichswechsel / Sortierung / Filter: Inhalt beginnt direkt unter der fixierten Leiste.
    val listState = rememberLazyListState()
    val catalogScrollEpoch by model.catalog.libraryCatalogScrollToTopEpoch.collectAsState()
    val sectionKey = when {
        activeShelf != null -> "s-${activeShelf.category}"
        booksContent != null -> "b-${booksContent.section.rawValue}-$catalogScrollEpoch"
        podcastsContent != null -> "p-${podcastsContent.stripSectionId}"
        else -> ""
    }
    LaunchedEffect(libraryChoice?.id, sectionKey) {
        if (listState.firstVisibleItemIndex > 0) listState.scrollToItem(0)
    }
    // Sprung aus Suche/Detail („Sendung zeigen“): zur Bibliotheksleiste scrollen.
    val revealEpoch by session.homeLibraryRevealEpoch.collectAsState()
    var handledRevealEpoch by rememberSaveable { mutableIntStateOf(revealEpoch) }
    LaunchedEffect(revealEpoch) {
        if (revealEpoch != handledRevealEpoch) {
            handledRevealEpoch = revealEpoch
            listState.animateScrollToItem(0)
        }
    }

    AbstandFixedBrowseStripSectionsLayout(
        title = "abstand",
        selection = continueId,
        showsStrip = false,
        // Liste wie in Books/Podcasts: Karten mit dem Abstand innerhalb einer Sektion.
        sectionSpacing = AppTheme.Layout.withinSectionSpacing,
        listState = listState,
        // Titelzeile „abstand“ mit Offline/Search/Settings.
        showsTitleRow = true,
        // Fest unter der Kategorie-Reihe (scrollt nicht mit): gewähltes Regal + Bibliotheksleiste.
        belowStrip = {
            // Kein Zusatzabstand zur Bibliotheksleiste: deren 48-dp-Zeile lässt über den Pills schon
            // denselben Rand wie zwischen Karte und Punkten — so sitzen die Punkte mittig.
            Column {
                when {
                    isRestoring -> Spacer(Modifier.fillMaxWidth().height(AppTheme.Layout.homeBrowseBootstrapMinHeight))
                    !anyShelfEnabled -> Box(Modifier.padding(horizontal = AppTheme.Layout.tabPaddingH)) { HomeAllShelvesDisabledState() }
                    continueShelf == null -> Box(Modifier.padding(horizontal = AppTheme.Layout.tabPaddingH)) { HomeSectionEmptyState(continueId, offline) }
                    else -> Box(Modifier.padding(top = AppTheme.Layout.tightSpacing)) {
                        CompositionLocalProvider(
                            LocalHomeCompactCardCoverSide provides AppTheme.Layout.homeContinueCardCoverSide,
                            LocalHomeCompactCardIsHero provides true,
                        ) {
                            // Randlos über die volle Breite — keine Nachbarkarte, die rechts hereinragt.
                            HomeContinueCompactCarousel(continueShelf, PaddingValues(0.dp))
                        }
                    }
                }
                if (libraryChoice != null) {
                    HomeLibraryBar(model, libraryChoices, libraryChoice, booksContent?.section, podcastsContent?.let { it.shows to it.stripSectionId }, libraryShelves, activeShelf?.category, selectShelf)
                }
            }
        },
        // Android: keine Tab-Leiste — Search und Settings öffnen sich als Seiten über Home.
        actions = {
            HomeGoOfflineToolbarButton(offline) {
                if (offline) session.exitOfflineHomeUI() else showOfflineConfirmation = true
            }
            AbstandIconButton(SF.magnifyingglass, "Search", onClick = session::openSearch, tint = Theme.palette.textSecondary)
            AbstandIconButton(SF.gearshape, "Settings", onClick = session::openSettings, tint = Theme.palette.textSecondary)
        },
        onRefresh = {
            home.refreshStartTabPullToRefresh()
            // Gewählte Bibliothek mit neu laden (wie Pull-to-Refresh der alten Tabs).
            val choice = session.resolvedHomeLibraryChoice()
            when {
                choice == null -> Unit
                choice.isPodcast -> model.podcasts.refreshPodcastsTab()
                else -> model.catalog.refreshBooksCatalog()
            }
        },
    ) {
        if (libraryChoice == null) {
            item(key = "library-none") {
                if (isBootstrapping) AbstandLoadingSpinner()
                else AbstandSectionEmptyState("No library selected. Choose a library in Settings.")
            }
            return@AbstandFixedBrowseStripSectionsLayout
        }
        when {
            activeShelf != null -> homeShelfListItems(activeShelf)
            booksContent != null -> booksBrowseSectionItems(booksContent)
            podcastsContent != null -> podcastsSectionItems(podcastsContent)
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
    AbstandIconButton(
        if (offline) SF.icloudSlash else SF.icloud,
        if (offline) "Go online" else "Go offline",
        onClick = onClick,
        tint = if (offline) Theme.accent else Theme.palette.textSecondary,
    )
}

// MARK: - Bibliotheksleiste (Android)

/** Kombinierte Auswahl (aktive Books- + Podcast-Bibliotheken); beobachtet die zugrunde liegenden Flows. */
@Composable
private fun rememberHomeLibraryChoices(session: SessionStore): List<HomeLibraryLogic.Choice> {
    val activeBooks by session.activeBooksLibraryIds.collectAsState()
    val activePodcasts by session.activePodcastLibraryIds.collectAsState()
    val libraries by session.libraries.collectAsState()
    return remember(activeBooks, activePodcasts, libraries) { session.homeLibraryChoices }
}

/**
 * Fixierte Bibliotheksleiste — wie die Kopfzeilen der alten Books-/Podcasts-Tabs: kompakte
 * Bibliotheks-Pill (Books + Podcasts in einem Menü), Bereichs-Pill (Books-Sektionen bzw. „New“ +
 * Sendungen), rechts die Aktionen (Books: Filter + Sortierung; Podcasts: Add, Show-Einstellungen,
 * Sortierung). Höhe und Ränder wie die Kopfzeile von `TabRootScaffold`.
 */
@Composable
private fun HomeLibraryBar(
    model: AppModel,
    choices: List<HomeLibraryLogic.Choice>,
    choice: HomeLibraryLogic.Choice,
    booksSection: BooksBrowseSection?,
    podcastSections: Pair<List<AbstandBrowseStripItem>, String>?,
    shelves: List<AbsStartShelfSection>,
    activeShelfCategory: String?,
    onSelectShelf: (String?) -> Unit,
) {
    val session = model.session
    // Regale als eigene Gruppe hinter den Bereichen (Trenner vor dem ersten Regal).
    val shelfItems = shelves.mapIndexed { i, it ->
        AbstandBrowseStripItem(HOME_SHELF_ITEM_PREFIX + it.category, it.displayTitle, SF.named(AbsStartShelfLocalization.stripSystemImage(it.category)) ?: SF.squareGrid2x2, dividerBefore = i == 0)
    }
    val shelfSelectionId = activeShelfCategory?.let { HOME_SHELF_ITEM_PREFIX + it }
    // Regal-Einträge abfangen, sonst normaler Bereich (und Regal abwählen).
    fun select(id: String, section: (String) -> Unit) {
        if (id.startsWith(HOME_SHELF_ITEM_PREFIX)) onSelectShelf(id.removePrefix(HOME_SHELF_ITEM_PREFIX)) else { onSelectShelf(null); section(id) }
    }
    val catalog = model.catalog
    val libraryItems = remember(choices) {
        choices.map { AbstandBrowseStripItem(it.id, it.library.name, if (it.isPodcast) SF.micFill else SF.booksVerticalFill) }
    }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = AppTheme.Layout.minTapTarget)
            .padding(end = AppTheme.Layout.tightSpacing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f)) {
            if (podcastSections != null) {
                AbstandBrowsePills(
                    items = podcastSectionStripItems(podcastSections.first) + shelfItems,
                    selectionId = shelfSelectionId ?: podcastSections.second,
                    onSelect = { id -> select(id, model.podcasts::selectStripSection) },
                    libraryItems = libraryItems,
                    librarySelectionId = choice.id,
                    onSelectLibrary = session::selectHomeLibraryChoice,
                    sectionAccessibilityLabel = "Shows",
                )
            } else {
                val sections = BooksBrowseSection.audiobookStripOrder
                AbstandBrowsePills(
                    items = sections.map { AbstandBrowseStripItem(it.rawValue, it.title, it.icon) } + shelfItems,
                    selectionId = shelfSelectionId ?: booksSection?.rawValue.orEmpty(),
                    onSelect = { id -> select(id) { raw -> sections.firstOrNull { it.rawValue == raw }?.let(catalog::selectBooksBrowseSection) } },
                    libraryItems = libraryItems,
                    librarySelectionId = choice.id,
                    onSelectLibrary = session::selectHomeLibraryChoice,
                )
            }
        }
        // M3: Aktions-Symbole onSurfaceVariant (aktiver Zustand setzt selbst primary).
        CompositionLocalProvider(LocalContentColor provides Theme.palette.textSecondary) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (choice.isPodcast) {
                    PodcastsToolbarActions(model)
                } else {
                    val snapshot by catalog.toolbarSnapshot.collectAsState()
                    BooksLibraryToolbar(snapshot, catalog)
                }
            }
        }
    }
}

// MARK: - Kategorie-Pills und Regal-Reihe (Android)

/** Merkt das im Dropdown gewählte Regal als „<Bibliothek>|<Kategorie>“ (Android-eigen). */
private const val HOME_SHELF_KEY = "abstand_android_home_shelf_category"

/** ID-Präfix der Regal-Einträge im Bereichs-Dropdown. */
private const val HOME_SHELF_ITEM_PREFIX = "__shelf__:"

/**
 * Android: Regale (außer „Continue listening“) für die gewählte Bibliothek — Books-Bibliotheken
 * bekommen Buch-/Serien-/Autoren-Regale mit ihren Büchern, Podcast-Bibliotheken Folgen-Regale
 * (ohne „Newest episodes“, das ist dort schon „New“).
 */
private fun homeShelvesForLibrary(shelves: List<AbsStartShelfSection>, choice: HomeLibraryLogic.Choice): List<AbsStartShelfSection> {
    val libraryId = choice.library.id
    fun inLibrary(id: String?) = id.isNullOrBlank() || id == libraryId
    return shelves.filter { !HomeShelfLogic.isContinueCategory(it.category) }.mapNotNull { shelf ->
        if (choice.isPodcast) {
            if (shelf.category == HomeShelfLogic.newestEpisodesCategory) return@mapNotNull null
            shelf.copy(books = emptyList(), series = emptyList(), authors = emptyList(), podcastEpisodes = shelf.podcastEpisodes.filter { inLibrary(it.libraryId) })
                .takeIf { it.hasPodcastEpisodes }
        } else {
            shelf.copy(podcastEpisodes = emptyList(), books = shelf.books.filter { inLibrary(it.libraryId) })
                .takeIf { it.hasBooks || it.hasSeries || it.hasAuthors }
        }
    }
}

/** Gewähltes Regal als Liste — Bücher mit derselben kompakten Zeile wie die Bibliothek. */
private fun LazyListScope.homeShelfListItems(shelf: AbsStartShelfSection) {
    when {
        shelf.hasBooks -> bookCards(
            shelf.books, "shelf-${shelf.category}",
            usesEbookProgressDisplay = shelf.category == HomeShelfLogic.continueEbooksCategory,
        )
        shelf.hasPodcastEpisodes -> items(shelf.podcastEpisodes, key = { "se-${it.progressLookupKey}" }) { HomeShelfEpisodeCard(it) }
        shelf.hasSeries -> items(shelf.series, key = { "ss-${it.id}" }) { HomeShelfSeriesCard(it) }
        shelf.hasAuthors -> items(shelf.authors, key = { "sa-${it.id}" }) { HomeShelfAuthorCard(it) }
    }
}

// MARK: - Karussells

/**
 * iOS: `HomeCompactCardCarousel` (Karten ≈ 3/4 der Breite). Android: Pager — jede Karte in voller
 * Breite, seitlich wischen; darunter ein Indikator, wie viele Karten es gibt und welche sichtbar ist
 * (Punkte bis [HomePagerMaxDots], darüber „n / m“). Eine Karte = kein Indikator.
 */
@Composable
private fun <T> HomeCompactCardCarousel(
    items: List<T>,
    key: (T) -> String,
    contentPadding: PaddingValues,
    card: @Composable (T, Dp) -> Unit,
) {
    if (items.isEmpty()) return
    val pagerState = rememberPagerState { items.size }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val cardWidth = maxWidth - contentPadding.calculateLeftPadding(LayoutDirection.Ltr) - contentPadding.calculateRightPadding(LayoutDirection.Ltr)
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
            CompositionLocalProvider(LocalAbstandCardShadowEnabled provides false) {
                HorizontalPager(
                    state = pagerState,
                    contentPadding = contentPadding,
                    pageSpacing = AppTheme.Layout.withinSectionSpacing,
                    key = { key(items[it]) },
                    verticalAlignment = Alignment.Top,
                    modifier = Modifier.fillMaxWidth().heightIn(min = LocalHomeCompactCardCoverSide.current),
                ) { page -> card(items[page], cardWidth) }
            }
            // Ohne Punkte: leerer Platzhalter, damit der Abstand zur Bibliotheksleiste gleich bleibt.
            if (items.size > 1) HomePagerIndicator(items.size, pagerState.currentPage) else Spacer(Modifier)
        }
    }
}

/** Ab so vielen Karten zeigt der Indikator „n / m“ statt Punkte. */
private const val HomePagerMaxDots = 10

@Composable
private fun HomePagerIndicator(count: Int, current: Int) {
    val palette = Theme.palette
    Row(
        Modifier.fillMaxWidth().semantics { contentDescription = "Card ${current + 1} of $count" },
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (count > HomePagerMaxDots) {
            Text("${current + 1} / $count", style = AppType.labelMedium, color = palette.textSecondary)
        } else {
            repeat(count) { i ->
                Box(
                    Modifier
                        .size(AppTheme.Layout.homePagerDotSize)
                        .background(if (i == current) Theme.accent else palette.scheme.outlineVariant, CircleShape),
                )
            }
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

/** iOS: Karte aus `HomePodcastEpisodesCompactCarousel`. */
@Composable
private fun HomeShelfEpisodeCard(episode: AbsPodcastEpisodeListItem) {
    val navigator = LocalTabNavigator.current
    HomeEpisodeCompactCard(episode, onOpen = { navigator?.push(EpisodeDestination(episode.libraryItemId, episode.episodeId)) })
}

/** iOS: Karte aus `HomeSeriesCompactCarousel`. */
@Composable
private fun HomeShelfSeriesCard(item: AbsLibrarySeriesListItem) {
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

/** iOS: Karte aus `HomeAuthorsCompactCarousel`. */
@Composable
private fun HomeShelfAuthorCard(author: AbsAuthorShelfEntity) {
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

/** iOS: `browseSeriesCoverBookIds(from:)` — Buch-IDs für Serien-Cover (erste zuerst). */
fun seriesCoverBookIds(books: List<AbsBook>?, maxCount: Int = 4): List<String> {
    val seen = HashSet<String>()
    return books.orEmpty().map { it.id.trim() }.filter { it.isNotEmpty() && seen.add(it) }.take(maxCount)
}

// MARK: - Leerzustände

/** iOS: `startDashboardSectionEmptyState` (`ContentUnavailableView`) — Android: über der Bibliotheksleiste, eigene Höhe. */
@Composable
private fun HomeSectionEmptyState(category: String, offline: Boolean) {
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
        modifier = Modifier.padding(vertical = AppTheme.Layout.sectionSpacing),
    )
}

/** iOS: `startDashboardAllShelvesDisabledState` — Android: Knopf direkt zu den Home-Einstellungen. */
@Composable
private fun HomeAllShelvesDisabledState() {
    val navigator = LocalTabNavigator.current
    AbstandEmptyScreen(
        title = "All shelves are off",
        icon = SF.gearshape2,
        description = "Open Settings → Appearance → Home to turn shelves back on.",
        modifier = Modifier.padding(vertical = AppTheme.Layout.sectionSpacing),
        actions = {
            AbstandProminentButton("Home settings", onClick = { navigator?.push(HomeShelvesSettingsDestination) })
        },
    )
}

