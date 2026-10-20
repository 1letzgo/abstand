package de.letzgo.abstand.ui.destinations

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.logic.BooksEntityDetailNav
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.MainTab
import de.letzgo.abstand.model.NowPlayingState
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.DetailScaffold
import de.letzgo.abstand.ui.detail.AuthorDetailDestination as DetailAuthor
import de.letzgo.abstand.ui.detail.BookDetailDestination as DetailBook
import de.letzgo.abstand.ui.detail.CollectionDetailDestination as DetailCollection
import de.letzgo.abstand.ui.detail.FacetFilteredBooksDestination as DetailFacet
import de.letzgo.abstand.ui.detail.NarratorDetailDestination as DetailNarrator
import de.letzgo.abstand.ui.detail.SeriesDetailDestination as DetailSeries
import de.letzgo.abstand.ui.podcasts.PodcastEpisodeDetailView

// Navigationsziele, die Home/Suche pushen (iOS: `navigationDestination` → `BookDetailView`,
// `PodcastEpisodeDetailView`, `BooksEntityDetailView` …). Konstruktoren und `key` bleiben stabil;
// `Content` leitet auf die portierten Detailseiten (`ui/detail/`, `ui/podcasts/`) weiter.

/** iOS: `BookDetailView(bookId:)`. */
data class BookDetailDestination(val itemId: String) : TabDestination {
    override val key: String get() = "book/$itemId"

    @Composable
    override fun Content(navigator: TabNavigator) = DetailBook(itemId).Content(navigator)
}

/**
 * iOS: Sendung aus Home/Suche → Podcasts-Tab mit gewählter Sendung (`selectPodcastShowFilter`).
 * Der Eintrag springt sofort in den Podcasts-Tab und nimmt sich selbst vom Stapel.
 */
data class PodcastShowDestination(val itemId: String) : TabDestination {
    override val key: String get() = "podcast/$itemId"

    @Composable
    override fun Content(navigator: TabNavigator) {
        LaunchedEffect(itemId) {
            val model = AppModel.shared
            model.podcasts.selectStripSection(itemId)
            navigator.pop()
            model.session.selectMainTab(MainTab.podcasts)
        }
        DetailScaffold(onBack = { navigator.pop() }, title = "Podcast") { padding ->
            AbstandLoadingSpinner(Modifier.padding(padding))
        }
    }
}

/** iOS: `PodcastEpisodeDetailView(episode:)` — Folge aus Listen/LocalStore auflösen. */
data class EpisodeDestination(val itemId: String, val episodeId: String) : TabDestination {
    override val key: String get() = "episode/$itemId/$episodeId"

    @Composable
    override fun Content(navigator: TabNavigator) {
        val model = AppModel.shared
        val episode by produceState<AbsPodcastEpisodeListItem?>(model.player.podcastEpisode(itemId, episodeId), itemId, episodeId) {
            if (value != null) return@produceState
            val key = NowPlayingState.progressKeyOf(itemId, episodeId)
            value = model.session.currentLocalLibraryStore()?.let { runCatching { it.fetchPodcastEpisode(key) }.getOrNull() }
                ?: model.progress.progress(key)?.let { AbsPodcastEpisodeListItem.forResumePlayback(it, model.session.resolvedPodcastLibraryId()) }
        }
        val ep = episode
        if (ep != null) {
            PodcastEpisodeDetailView(ep, navigator)
        } else {
            DetailScaffold(onBack = { navigator.pop() }, title = "Episode") { padding ->
                AbstandEmptyScreen(title = "Episode unavailable", icon = SF.waveform, modifier = Modifier.padding(padding))
            }
        }
    }
}

/** iOS: `openAuthorDetail(authorId:displayName:numBooks:)`. */
data class AuthorDestination(val id: String, val name: String? = null) : TabDestination {
    override val key: String get() = "author/$id"

    @Composable
    override fun Content(navigator: TabNavigator) = DetailAuthor(id, name?.ifBlank { null }).Content(navigator)
}

/** iOS: `openSeriesDetail(seriesId:displayName:numBooks:)`. */
data class SeriesDestination(val id: String, val name: String? = null) : TabDestination {
    override val key: String get() = "series/$id"

    @Composable
    override fun Content(navigator: TabNavigator) = DetailSeries(id, name?.ifBlank { null }).Content(navigator)
}

/** iOS: `openCollectionDetail(collectionId:displayName:numBooks:)`. */
data class CollectionDestination(val id: String, val name: String? = null) : TabDestination {
    override val key: String get() = "collection/$id"

    @Composable
    override fun Content(navigator: TabNavigator) = DetailCollection(id, name?.ifBlank { null }).Content(navigator)
}

/** iOS: `openNarratorDetail(narratorName:numBooks:)` — Sprecher werden über den Namen identifiziert. */
data class NarratorDestination(val name: String) : TabDestination {
    override val key: String get() = "narrator/$name"

    @Composable
    override fun Content(navigator: TabNavigator) = DetailNarrator(name).Content(navigator)
}

/** iOS: `openGenreDetail(genreName:numBooks:)`. */
data class GenreDestination(val name: String) : TabDestination {
    override val key: String get() = "genre/$name"

    @Composable
    override fun Content(navigator: TabNavigator) = DetailFacet(BooksEntityDetailNav.Kind.GENRE, name).Content(navigator)
}

/** iOS: `openTagDetail(tagName:numBooks:)`. */
data class TagDestination(val name: String) : TabDestination {
    override val key: String get() = "tag/$name"

    @Composable
    override fun Content(navigator: TabNavigator) = DetailFacet(BooksEntityDetailNav.Kind.TAG, name).Content(navigator)
}
