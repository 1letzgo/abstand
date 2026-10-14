package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsAuthor
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookMedia
import de.letzgo.abstand.data.AbsBookMediaMetadata
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsSearchAuthorRow
import de.letzgo.abstand.data.AbsSearchBookRow
import de.letzgo.abstand.data.AbsSearchNamedCount
import de.letzgo.abstand.data.AbsSearchNarratorRow
import de.letzgo.abstand.data.AbsSearchResponse
import de.letzgo.abstand.data.AbsSearchSeriesRow
import de.letzgo.abstand.data.AbsSeries
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchLogicTest {
    private fun book(id: String, title: String, author: String? = null, series: String? = null) = AbsBook(
        id = id, libraryId = "L", addedAt = null, updatedAt = null,
        media = AbsBookMedia(
            metadata = AbsBookMediaMetadata(
                title = title,
                authors = author?.let { listOf(AbsAuthor("a-$it", it)) },
                series = series?.let { listOf(AbsSeries("s-$it", it, null)) },
            ),
            duration = 100.0, numTracks = 1, tracks = null,
        ),
    )

    private fun episode(item: String, ep: String, title: String, show: String = "Show") =
        AbsPodcastEpisodeListItem(libraryItemId = item, episodeId = ep, episodeTitle = title, showTitle = show, authorLine = show, duration = 1.0)

    private fun response(
        books: List<AbsBook> = emptyList(),
        authors: List<AbsSearchAuthorRow> = emptyList(),
        narrators: List<AbsSearchNarratorRow> = emptyList(),
        series: List<AbsSearchSeriesRow> = emptyList(),
        tags: List<AbsSearchNamedCount> = emptyList(),
        genres: List<AbsSearchNamedCount> = emptyList(),
        episodes: List<AbsPodcastEpisodeListItem> = emptyList(),
    ) = AbsSearchResponse(
        book = books.map { AbsSearchBookRow(it) }, podcast = emptyList(), episodes = emptyList(), authors = authors,
        narrators = narrators, series = series, tags = tags, genres = genres, podcastEpisodeMatches = episodes,
    )

    @Test
    fun statusFollowsQueryLengthLoadingAndResults() {
        val empty = SearchResults()
        val some = SearchResults(authors = listOf(AbsSearchAuthorRow("1", "A", 1)))
        assertEquals(SearchStatus.Prompt, SearchLogic.status("   ", false, empty))
        assertEquals(SearchStatus.TooShort, SearchLogic.status(" ab ", true, empty))
        assertEquals(SearchStatus.Loading, SearchLogic.status("abc", true, empty))
        assertEquals(SearchStatus.Results, SearchLogic.status("abc", true, some))
        assertEquals(SearchStatus.NoResults, SearchLogic.status("abc", false, empty))
    }

    @Test
    fun visibleSectionsKeepIosOrderAndHidePodcastsWithoutTab() {
        val results = SearchResults(
            books = listOf(book("1", "X")),
            genres = listOf(AbsSearchNamedCount("Fantasy", 2)),
            authors = listOf(AbsSearchAuthorRow("a", "A", 1)),
            podcastEpisodes = listOf(episode("p", "e", "Ep")),
        )
        assertEquals(
            listOf(SearchSection.Books, SearchSection.Authors, SearchSection.Genres, SearchSection.Episodes),
            SearchLogic.visibleSections(results, showPodcasts = true),
        )
        assertEquals(listOf(SearchSection.Books, SearchSection.Authors, SearchSection.Genres), SearchLogic.visibleSections(results, showPodcasts = false))
    }

    @Test
    fun mergeBookResponsesDedupesAndSumsCounts() {
        val r1 = response(
            books = listOf(book("b1", "One")),
            authors = listOf(AbsSearchAuthorRow("a1", "Ann", 2)),
            narrators = listOf(AbsSearchNarratorRow("Ned", 1)),
            series = listOf(AbsSearchSeriesRow("s1", "Saga", listOf(book("b1", "One")))),
            tags = listOf(AbsSearchNamedCount("t", 1)),
        )
        val r2 = response(
            books = listOf(book("b2", "Two"), book("b1", "One")),
            authors = listOf(AbsSearchAuthorRow("a1", "Ann", 3), AbsSearchAuthorRow("a2", "Bob", null)),
            narrators = listOf(AbsSearchNarratorRow("Ned", 4)),
            series = listOf(AbsSearchSeriesRow("s1", "Saga", listOf(book("b3", "Three")))),
            tags = listOf(AbsSearchNamedCount("t", null)),
            genres = listOf(AbsSearchNamedCount("g", 2)),
        )
        val merged = SearchLogic.mergeBookResponses(listOf(r1, r2))
        assertEquals(listOf("b1", "b2"), merged.books.map { it.id })
        assertEquals(listOf(5, null), merged.authors.map { it.numBooks })
        assertEquals(5, merged.narrators.single().numBooks)
        assertEquals(listOf("b1", "b3"), merged.series.single().books!!.map { it.id })
        assertEquals(1, merged.tags.single().numItems)
        assertEquals(listOf("g"), merged.genres.map { it.name })
        assertTrue(merged.hasAnyResults)
    }

    @Test
    fun podcastMergeDedupesEpisodesAndSortsByTitle() {
        val r = response(episodes = listOf(episode("p", "2", "beta"), episode("p", "1", "Alpha")))
        val (shows, eps) = SearchLogic.mergePodcastResponses(listOf(r), localEpisodes = listOf(episode("p", "2", "beta")))
        assertTrue(shows.isEmpty())
        assertEquals(listOf("Alpha", "beta"), eps.map { it.episodeTitle })
    }

    @Test
    fun localResultsMatchTitleAuthorAndSeries() {
        val books = listOf(book("1", "Dune", "Frank Herbert"), book("2", "Other", series = "Dune Chronicles"), book("3", "Nothing"), book("1", "Dune"))
        val local = SearchLogic.localResults("dune", books, episodes = listOf(episode("p", "e", "Talk", show = "Dune Pod")))
        assertEquals(listOf("1", "2"), local.books.map { it.id })
        assertEquals(1, local.podcastEpisodes.size)
        assertTrue(SearchLogic.bookMatches(books[0], "herb"))
        assertFalse(SearchLogic.bookMatches(books[2], "dune"))
        assertFalse(SearchLogic.localResults("du", books).hasAnyResults)
    }
}
