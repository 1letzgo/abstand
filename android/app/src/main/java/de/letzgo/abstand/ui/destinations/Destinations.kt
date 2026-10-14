package de.letzgo.abstand.ui.destinations

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.components.AbstandEmptyScreen
import de.letzgo.abstand.ui.components.DetailScaffold

// Navigationsziele der Detailseiten (iOS: `navigationDestination` → `BookDetailView`,
// `PodcastEpisodeDetailView`, `BooksEntityDetailView` …). Vorerst Platzhalter — die Detail-Ports
// ersetzen nur `Content`; Konstruktoren und `key` bleiben stabil, damit Home/Suche/Kataloge sie
// schon heute pushen können.

/** Gemeinsamer Platzhalter, bis die Detailseite portiert ist. */
@Composable
private fun ComingSoon(title: String, navigator: TabNavigator) {
    DetailScaffold(onBack = { navigator.pop() }, title = title) { padding ->
        AbstandEmptyScreen(
            title = "Coming soon",
            icon = SF.hourglass,
            description = "This page isn't available on Android yet.",
            modifier = Modifier.padding(padding),
        )
    }
}

/** iOS: `BookDetailView(bookId:)`. */
data class BookDetailDestination(val itemId: String) : TabDestination {
    override val key: String get() = "book/$itemId"

    @Composable
    override fun Content(navigator: TabNavigator) = ComingSoon("Book", navigator)
}

/** iOS: Podcast-Sendung (Podcasts-Tab mit Show-Filter bzw. `PodcastShowDetail`). */
data class PodcastShowDestination(val itemId: String) : TabDestination {
    override val key: String get() = "podcast/$itemId"

    @Composable
    override fun Content(navigator: TabNavigator) = ComingSoon("Podcast", navigator)
}

/** iOS: `PodcastEpisodeDetailView(episode:)`. */
data class EpisodeDestination(val itemId: String, val episodeId: String) : TabDestination {
    override val key: String get() = "episode/$itemId/$episodeId"

    @Composable
    override fun Content(navigator: TabNavigator) = ComingSoon("Episode", navigator)
}

/** iOS: `openAuthorDetail(authorId:displayName:numBooks:)`. */
data class AuthorDestination(val id: String, val name: String? = null) : TabDestination {
    override val key: String get() = "author/$id"

    @Composable
    override fun Content(navigator: TabNavigator) = ComingSoon(name?.ifBlank { null } ?: "Author", navigator)
}

/** iOS: `openSeriesDetail(seriesId:displayName:numBooks:)`. */
data class SeriesDestination(val id: String, val name: String? = null) : TabDestination {
    override val key: String get() = "series/$id"

    @Composable
    override fun Content(navigator: TabNavigator) = ComingSoon(name?.ifBlank { null } ?: "Series", navigator)
}

/** iOS: `openCollectionDetail(collectionId:displayName:numBooks:)`. */
data class CollectionDestination(val id: String, val name: String? = null) : TabDestination {
    override val key: String get() = "collection/$id"

    @Composable
    override fun Content(navigator: TabNavigator) = ComingSoon(name?.ifBlank { null } ?: "Collection", navigator)
}

/** iOS: `openNarratorDetail(narratorName:numBooks:)` — Sprecher werden über den Namen identifiziert. */
data class NarratorDestination(val name: String) : TabDestination {
    override val key: String get() = "narrator/$name"

    @Composable
    override fun Content(navigator: TabNavigator) = ComingSoon(name, navigator)
}

/** iOS: `openGenreDetail(genreName:numBooks:)`. */
data class GenreDestination(val name: String) : TabDestination {
    override val key: String get() = "genre/$name"

    @Composable
    override fun Content(navigator: TabNavigator) = ComingSoon(name, navigator)
}

/** iOS: `openTagDetail(tagName:numBooks:)`. */
data class TagDestination(val name: String) : TabDestination {
    override val key: String get() = "tag/$name"

    @Composable
    override fun Content(navigator: TabNavigator) = ComingSoon(name, navigator)
}
