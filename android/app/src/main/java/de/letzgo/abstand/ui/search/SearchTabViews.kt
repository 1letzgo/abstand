package de.letzgo.abstand.ui.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.MainTab
import de.letzgo.abstand.model.SearchLogic
import de.letzgo.abstand.model.SearchResults
import de.letzgo.abstand.model.SearchSection
import de.letzgo.abstand.model.SearchStatus
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.library.BrowseEntityRowCard
import de.letzgo.abstand.logic.CatalogLogic
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSearchField
import de.letzgo.abstand.ui.components.TabContentSectionTitle
import de.letzgo.abstand.ui.components.TabRootScaffold
import de.letzgo.abstand.ui.destinations.AuthorDestination
import de.letzgo.abstand.ui.destinations.BookDetailDestination
import de.letzgo.abstand.ui.destinations.EpisodeDestination
import de.letzgo.abstand.ui.destinations.GenreDestination
import de.letzgo.abstand.ui.destinations.NarratorDestination
import de.letzgo.abstand.ui.destinations.PodcastShowDestination
import de.letzgo.abstand.ui.destinations.SeriesDestination
import de.letzgo.abstand.ui.destinations.TagDestination
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.home.seriesCoverBookIds

/**
 * iOS: `SearchTabRootView` — ein Suchtext durchsucht Bücher und Podcasts zugleich. iOS nutzt das
 * native `.searchable`-Feld in der Navigationsleiste; Android legt das Suchfeld fix unter den Titel
 * (Header des Tab-Gerüsts), Ergebnisse scrollen darunter. Sektionen in iOS-Reihenfolge: Books,
 * Authors, Series, Narrators, Tags, Genres, dann Shows und Episodes.
 */
@Composable
fun SearchTabRoot(model: AppModel = AppModel.shared) {
    val search = model.search
    val query by search.query.collectAsState()
    val results by search.results.collectAsState()
    val isSearching by search.isSearching.collectAsState()
    val showPodcasts by model.session.showPodcastsTab.collectAsState()
    val navigator = LocalTabNavigator.current
    val focus = LocalFocusManager.current
    val status = SearchLogic.status(query, isSearching, results)

    TabRootScaffold(
        title = MainTab.search.label,
        header = {
            AbstandSearchField(
                query = query,
                onQueryChange = search::updateQuery,
                placeholder = "Title, author, show, episode…",
                onSubmit = {
                    focus.clearFocus()
                    search.submit()
                },
                modifier = Modifier.padding(horizontal = AppTheme.Layout.tabPaddingH),
            )
        },
    ) { padding ->
        when (status) {
            SearchStatus.Prompt -> AbstandEmptyScreen(
                title = "Search",
                icon = SF.magnifyingglass,
                description = "Search your audiobooks and podcasts at once.",
                modifier = Modifier.padding(padding),
            )
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = padding,
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
            ) {
                when (status) {
                    SearchStatus.TooShort -> item(key = "too-short") { SearchStatusText("Enter at least three characters.") }
                    SearchStatus.Loading -> item(key = "loading") { AbstandLoadingSpinner() }
                    SearchStatus.NoResults -> item(key = "no-results") { SearchStatusText("No results.") }
                    else -> searchResultSections(results, showPodcasts, navigator)
                }
            }
        }
    }
}

/** iOS: Hinweistext unter dem Suchfeld (`subheadline`, `textSecondary`, zentriert, `blockSpacing`). */
@Composable
private fun SearchStatusText(text: String) {
    Text(
        text,
        style = AppType.bodyMedium,
        color = Theme.palette.textSecondary,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(AppTheme.Layout.blockSpacing),
    )
}

/** iOS: `BooksSearchBrowseView` + `PodcastLibrarySearchResultsView`. */
private fun LazyListScope.searchResultSections(results: SearchResults, showPodcasts: Boolean, navigator: TabNavigator?) {
    SearchLogic.visibleSections(results, showPodcasts).forEachIndexed { index, section ->
        item(key = "title-${section.name}") {
            TabContentSectionTitle(
                section.title,
                Modifier.padding(top = if (index == 0) 0.dp else AppTheme.Layout.sectionSpacing - AppTheme.Layout.withinSectionSpacing),
            )
        }
        when (section) {
            SearchSection.Books -> items(results.books, key = { "book-${it.id}" }) { book ->
                BrowseEntityRowCard(
                    title = book.displayTitle,
                    detailLabel = "Duration",
                    detailValue = book.media.duration?.takeIf { it > 0 }?.let(::formatPlaybackTime),
                    authorLine = book.displayAuthorsCardLine,
                    coverItemId = book.id,
                    onClick = { navigator?.push(BookDetailDestination(book.id)) },
                )
            }
            SearchSection.Authors -> items(results.authors, key = { "author-${it.id}" }) { a ->
                BrowseEntityRowCard(
                    title = a.name,
                    detailLabel = "Books",
                    detailValue = a.numBooks?.toString(),
                    authorImageId = a.id,
                    onClick = { navigator?.push(AuthorDestination(a.id, a.name)) },
                )
            }
            SearchSection.Series -> items(results.series, key = { "series-${it.id}" }) { s ->
                BrowseEntityRowCard(
                    title = s.name,
                    detailLabel = "Books",
                    detailValue = s.books?.size?.toString(),
                    authorLine = s.cardAuthorsLine,
                    coverItemId = seriesCoverBookIds(s.books).firstOrNull(),
                    onClick = { navigator?.push(SeriesDestination(s.id, s.name)) },
                )
            }
            SearchSection.Narrators -> items(results.narrators, key = { "narrator-${it.name}" }) { n ->
                BrowseEntityRowCard(
                    title = n.name,
                    detailLabel = "Books",
                    detailValue = n.numBooks?.toString(),
                    placeholderIcon = SF.personWave2Fill,
                    onClick = { navigator?.push(NarratorDestination(n.name)) },
                )
            }
            SearchSection.Tags -> items(results.tags, key = { "tag-${it.name}" }) { t ->
                BrowseEntityRowCard(
                    title = t.name,
                    detailLabel = "Books",
                    detailValue = CatalogLogic.booksCountLine(t.numItems) ?: t.numItems?.toString(),
                    placeholderIcon = SF.tagFill,
                    onClick = { navigator?.push(TagDestination(t.name)) },
                )
            }
            SearchSection.Genres -> items(results.genres, key = { "genre-${it.name}" }) { g ->
                BrowseEntityRowCard(
                    title = g.name,
                    detailLabel = "Books",
                    detailValue = CatalogLogic.booksCountLine(g.numItems) ?: g.numItems?.toString(),
                    placeholderIcon = SF.sparkles,
                    onClick = { navigator?.push(GenreDestination(g.name)) },
                )
            }
            SearchSection.Shows -> items(results.podcastShows, key = { "show-${it.id}" }) { show ->
                BrowseEntityRowCard(
                    title = show.displayTitle,
                    detailLabel = "Author",
                    detailValue = show.displayAuthorsCardLine,
                    coverItemId = show.id,
                    placeholderIcon = SF.micFill,
                    onClick = { navigator?.push(PodcastShowDestination(show.id)) },
                )
            }
            SearchSection.Episodes -> items(results.podcastEpisodes, key = { "episode-${it.progressLookupKey}" }) { ep ->
                BrowseEntityRowCard(
                    title = ep.episodeTitle,
                    detailLabel = "Show",
                    detailValue = ep.showTitle,
                    coverItemId = ep.libraryItemId,
                    placeholderIcon = SF.micFill,
                    onClick = { navigator?.push(EpisodeDestination(ep.libraryItemId, ep.episodeId)) },
                )
            }
        }
    }
}
