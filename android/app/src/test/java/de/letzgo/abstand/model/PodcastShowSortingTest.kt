package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookMedia
import de.letzgo.abstand.data.AbsBookMediaMetadata
import de.letzgo.abstand.data.AbsJson
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS: `PodcastShowSorting` — Sortierung der Sendungs-Leiste im Podcasts-Tab. */
class PodcastShowSortingTest {
    private fun show(
        id: String,
        title: String,
        author: String? = null,
        episodes: Int? = null,
        addedAt: Long? = null,
        updatedAt: Long? = null,
        size: Long? = null,
        titleIgnorePrefix: String? = null,
    ) = AbsBook(
        id = id, libraryId = "L", addedAt = addedAt, updatedAt = updatedAt,
        media = AbsBookMedia(
            metadata = AbsBookMediaMetadata(title = title, authorName = author, titleIgnorePrefix = titleIgnorePrefix),
            duration = null, size = size, numTracks = null, tracks = null, numEpisodes = episodes,
        ),
    )

    private val shows = listOf(
        show("a", "Zeitfragen", author = "DLF", episodes = 12, addedAt = 300, updatedAt = 900, size = 50),
        show("b", "alternativlos", author = "CCC", episodes = 120, addedAt = 100, updatedAt = 500, size = 900),
        show("c", "Folge 10", author = null, episodes = null, addedAt = null, updatedAt = 700, size = null),
        show("d", "Folge 2", author = "Ärzteblatt", episodes = 3, addedAt = 200, updatedAt = null, size = 10),
    )

    private fun ids(field: PodcastCatalogSortField, descending: Boolean, ignorePrefix: Boolean = false, input: List<AbsBook> = shows) =
        PodcastShowSorting.sorted(input, field, descending, ignorePrefix).map { it.id }

    @Test
    fun titleIgnoresCaseAndSortsNumbersNumerically() {
        assertEquals(listOf("b", "d", "c", "a"), ids(PodcastCatalogSortField.title, descending = false))
        assertEquals(listOf("a", "c", "d", "b"), ids(PodcastCatalogSortField.title, descending = true))
    }

    @Test
    fun titleUsesIgnorePrefixOnlyWhenServerSaysSo() {
        val input = listOf(show("x", "The Daily", titleIgnorePrefix = "Daily, The"), show("y", "Lage der Nation"))
        assertEquals(listOf("y", "x"), ids(PodcastCatalogSortField.title, false, ignorePrefix = false, input = input))
        assertEquals(listOf("x", "y"), ids(PodcastCatalogSortField.title, false, ignorePrefix = true, input = input))
    }

    @Test
    fun authorIgnoresDiacriticsAndKeepsMissingLast() {
        assertEquals(listOf("d", "b", "a", "c"), ids(PodcastCatalogSortField.author, descending = false))
        assertEquals(listOf("a", "b", "d", "c"), ids(PodcastCatalogSortField.author, descending = true))
    }

    @Test
    fun numberOfEpisodesFallsBackToLoadedEpisodesAndKeepsUnknownLast() {
        assertEquals(listOf("d", "a", "b", "c"), ids(PodcastCatalogSortField.numEpisodes, descending = false))
        assertEquals(listOf("b", "a", "d", "c"), ids(PodcastCatalogSortField.numEpisodes, descending = true))
    }

    @Test
    fun datesAndSize() {
        assertEquals(listOf("a", "d", "b", "c"), ids(PodcastCatalogSortField.addedAt, descending = true))
        assertEquals(listOf("b", "d", "a", "c"), ids(PodcastCatalogSortField.addedAt, descending = false))
        assertEquals(listOf("a", "c", "b", "d"), ids(PodcastCatalogSortField.updatedAt, descending = true))
        assertEquals(listOf("b", "a", "d", "c"), ids(PodcastCatalogSortField.size, descending = true))
    }

    @Test
    fun tiesFallBackToTitleThenOriginalOrder() {
        val input = listOf(show("p", "Beta", episodes = 5), show("q", "Alpha", episodes = 5), show("r", "Alpha", episodes = 5))
        assertEquals(listOf("q", "r", "p"), ids(PodcastCatalogSortField.numEpisodes, true, input = input))
    }

    @Test
    fun randomKeepsServerOrder() {
        assertEquals(listOf("a", "b", "c", "d"), ids(PodcastCatalogSortField.random, descending = true))
    }

    @Test
    fun decoderReadsNumEpisodesOfMinifiedPodcast() {
        val json = """{"metadata":{"title":"Show","author":"Host"},"numEpisodes":42,"size":1234}"""
        val media = AbsJson.decoder.decodeFromString(AbsBookMedia.serializer(), json)
        assertEquals(42, media.numEpisodes)
        val roundTrip = AbsJson.decoder.decodeFromString(
            AbsBookMedia.serializer(), AbsJson.encoder.encodeToString(AbsBookMedia.serializer(), media),
        )
        assertEquals(42, roundTrip.numEpisodes)
        assertEquals("Host", roundTrip.metadata.authorName)
    }

    @Test
    fun removedFileTimeFieldsMigrate() {
        assertEquals(PodcastCatalogSortField.addedAt, PodcastLogic.migratePodcastCatalogSortField("birthtimeMs"))
        assertEquals(PodcastCatalogSortField.updatedAt, PodcastLogic.migratePodcastCatalogSortField("mtimeMs"))
        assertEquals(PodcastCatalogSortField.updatedAt, PodcastLogic.migratePodcastCatalogSortField("updatedAt"))
        assertEquals("mtimeMs", PodcastCatalogSortField.updatedAt.apiSortParameter)
    }
}
