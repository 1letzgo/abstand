package de.letzgo.abstand.ui.detail

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.logic.BooksEntityDetailNav
import de.letzgo.abstand.ui.TabDestination
import de.letzgo.abstand.ui.TabNavigator
import de.letzgo.abstand.ui.metadata.MetadataActions

// Ziele für `TabNavigator.push` (iOS: `navigationDestination` je Tab-Stack). Home/Search/Settings
// können ihre Platzhalter direkt hierauf umstellen.

/**
 * iOS: `BookDetailView(bookId:)`. Die Admin-/Reader-Callbacks sind optional (ausgeblendet, wenn
 * `null`) — der Integrator reicht sie durch, sobald Reader und Metadaten-Sheets portiert sind.
 */
data class BookDetailDestination(
    val itemId: String,
    val onOpenEbook: ((AbsBook) -> Unit)? = null,
    val onEditMetadata: ((AbsBook) -> Unit)? = null,
    val onMatchMetadata: ((AbsBook) -> Unit)? = null,
    val onEditChapters: ((AbsBook) -> Unit)? = null,
) : TabDestination {
    override val key: String get() = "book/$itemId"

    @Composable
    override fun Content(navigator: TabNavigator) {
        // Nach Metadaten-/Kapitel-Änderung neu laden (iOS: `applyUpdatedBookToLoadedLists`).
        val reload by produceState(0, itemId) {
            MetadataActions.bookUpdated.collect { if (it.id == itemId) value += 1 }
        }
        BookDetailScreen(
            itemId = itemId,
            reloadSignal = reload,
            onBack = { navigator.pop() },
            onOpenEbook = onOpenEbook ?: defaultOpenEbook,
            onEditMetadata = onEditMetadata ?: defaultEditMetadata,
            onMatchMetadata = onMatchMetadata ?: defaultMatchMetadata,
            onEditChapters = onEditChapters ?: defaultEditChapters,
        )
    }

    companion object {
        /**
         * App-weite Standard-Callbacks (vom Integrator gesetzt, z. B. in `AppRoot`), damit auch
         * Karten ohne eigene Parameter Reader und Admin-Sheets erreichen. `null` = ausgeblendet.
         */
        var defaultOpenEbook: ((AbsBook) -> Unit)? = null
        var defaultEditMetadata: ((AbsBook) -> Unit)? = null
        var defaultMatchMetadata: ((AbsBook) -> Unit)? = null
        var defaultEditChapters: ((AbsBook) -> Unit)? = null
    }
}

/** iOS: `BooksEntityDetailView(nav:)` — beliebige Entity (Autor, Serie, Sprecher, Sammlung, Genre, Tag). */
data class EntityDetailDestination(val nav: BooksEntityDetailNav) : TabDestination {
    override val key: String get() = "entity/${nav.id}"

    @Composable
    override fun Content(navigator: TabNavigator) = BooksEntityDetailScreen(nav, onBack = { navigator.pop() })
}

/** Autor-Detail (iOS: `openAuthorDetail`). */
data class AuthorDetailDestination(val authorId: String, val title: String? = null, val numBooks: Int? = null, val libraryId: String? = null) : TabDestination {
    override val key: String get() = "author/$authorId"

    @Composable
    override fun Content(navigator: TabNavigator) = AuthorDetailScreen(authorId, title, numBooks, libraryId)
}

/** Serien-Detail (iOS: `openSeriesDetail`). */
data class SeriesDetailDestination(val seriesId: String, val title: String? = null, val numBooks: Int? = null, val libraryId: String? = null) : TabDestination {
    override val key: String get() = "series/$seriesId"

    @Composable
    override fun Content(navigator: TabNavigator) = SeriesDetailScreen(seriesId, title, numBooks, libraryId)
}

/** Sammlungs-Detail (iOS: `openCollectionDetail`). */
data class CollectionDetailDestination(val collectionId: String, val title: String? = null, val numBooks: Int? = null, val libraryId: String? = null) : TabDestination {
    override val key: String get() = "collection/$collectionId"

    @Composable
    override fun Content(navigator: TabNavigator) = CollectionDetailScreen(collectionId, title, numBooks, libraryId)
}

/** Sprecher-Detail (iOS: `openNarratorDetail`). */
data class NarratorDetailDestination(val name: String, val numBooks: Int? = null, val libraryId: String? = null) : TabDestination {
    override val key: String get() = "narrator/$name"

    @Composable
    override fun Content(navigator: TabNavigator) = NarratorDetailScreen(name, numBooks, libraryId)
}

/** Genre-/Tag-Detail (iOS: `openGenreDetail` / `openTagDetail`). */
data class FacetFilteredBooksDestination(
    val kind: BooksEntityDetailNav.Kind,
    val value: String,
    val numBooks: Int? = null,
    val libraryId: String? = null,
) : TabDestination {
    override val key: String get() = "${kind.rawValue}/$value"

    @Composable
    override fun Content(navigator: TabNavigator) = FacetFilteredBooksScreen(kind, value, numBooks, libraryId)
}
