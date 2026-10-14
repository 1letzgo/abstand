package de.letzgo.abstand.ui.home

import androidx.compose.foundation.layout.Arrangement
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
 * iOS: `HomeTabRootView` + `StartDashboardView` — Großtitel „Home“, Offline-Schalter in der Toolbar,
 * darunter alle eingeschalteten Regale (Continue listening als Hero-Karten, alle anderen als
 * Kompaktkarten). Kein Browse-Streifen (iOS `showsStrip: false`), Pull-to-Refresh.
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
    AbstandFixedBrowseStripSectionsLayout(
        title = MainTab.start.label,
        selection = continueId,
        showsStrip = false,
        fullBleed = true,
        sectionSpacing = AppTheme.Layout.homeSectionSpacing,
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
            !HomeShelfLogic.isAnyShelfEnabled(categoryList, disabled) -> item(key = "all-off") {
                HomeAllShelvesDisabledState()
            }
            else -> {
                val visible = HomeShelfLogic.shelvesForHomeBrowseSection(continueId, categoryList, shelves, disabled)
                    .filter(HomeShelfLogic::shelfHasVisibleContent)
                if (visible.isEmpty()) {
                    item(key = "empty") { HomeSectionEmptyState(continueId, offline) }
                } else {
                    visible.forEach { shelf -> item(key = "shelf-${shelf.category}-${shelf.id}") { StartDashboardShelf(shelf) } }
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
                    ContinueListeningHeroCarousel(shelf, rowPadding)
                }
            }
            if (shelf.hasAuthors) {
                Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
                    TabContentSectionTitle(shelf.displayTitle, titleModifier)
                    HomeAuthorsCoverCardCarousel(shelf.authors, rowPadding)
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
