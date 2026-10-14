package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsPodcastDirectorySearchHit
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsPodcastFeedPreview
import de.letzgo.abstand.data.AbsPodcastRssFeedEpisodeDraft
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PodcastLogicTest {
    private fun ep(id: String, title: String, published: Long?, duration: Double = 0.0, show: String = "show1") =
        AbsPodcastEpisodeListItem(
            libraryItemId = show, libraryId = "lib", episodeId = id, episodeTitle = title,
            showTitle = "Show", authorLine = "Host", duration = duration, publishedAt = published,
        )

    @Test
    fun newestFirstSortsByDateThenTitleDescending() {
        val rows = listOf(ep("a", "Alpha", 100), ep("b", "Beta", 300), ep("c", "Charlie", 100), ep("d", "Delta", null))
        assertEquals(listOf("b", "c", "a", "d"), PodcastLogic.sortEpisodesNewestFirst(rows).map { it.episodeId })
    }

    @Test
    fun showEpisodeSortHonoursFieldAndDirection() {
        val rows = listOf(ep("a", "Episode 2", 200, 50.0), ep("b", "Episode 10", 100, 90.0), ep("c", "Another", 300, 50.0))
        assertEquals(listOf("c", "a", "b"), PodcastLogic.sortShowEpisodes(rows, PodcastEpisodeSortField.publishedAt, true).map { it.episodeId })
        assertEquals(listOf("b", "a", "c"), PodcastLogic.sortShowEpisodes(rows, PodcastEpisodeSortField.publishedAt, false).map { it.episodeId })
        // Titel aufsteigend; Collator ohne Zahlen-Sortierung → „Episode 10“ vor „Episode 2“.
        assertEquals(listOf("c", "b", "a"), PodcastLogic.sortShowEpisodes(rows, PodcastEpisodeSortField.title, false).map { it.episodeId })
        assertEquals(listOf("a", "b", "c"), PodcastLogic.sortShowEpisodes(rows, PodcastEpisodeSortField.title, true).map { it.episodeId })
        // Dauer: Gleichstand → neuestes zuerst.
        assertEquals(listOf("c", "a", "b"), PodcastLogic.sortShowEpisodes(rows, PodcastEpisodeSortField.duration, false).map { it.episodeId })
        assertEquals(listOf("b", "c", "a"), PodcastLogic.sortShowEpisodes(rows, PodcastEpisodeSortField.duration, true).map { it.episodeId })
    }

    @Test
    fun newFeedDropsFinishedEpisodes() {
        val rows = listOf(ep("a", "A", 1), ep("b", "B", 2), ep("c", "C", 3))
        val finished = setOf("show1-b")
        assertEquals(listOf("a", "c"), PodcastLogic.unplayedForNewFeed(rows) { it in finished }.map { it.episodeId })
    }

    @Test
    fun mergeNewShowEpisodesAppendsOnlyUnknownRowsOfTheShow() {
        val existing = listOf(ep("a", "A", 100))
        val fetched = listOf(ep("a", "A", 100), ep("b", "B", 200), ep("x", "X", 300, show = "other"))
        val merged = PodcastLogic.mergeNewShowEpisodes(existing, fetched, "show1")
        assertEquals(listOf("b", "a"), merged?.map { it.episodeId })
        assertNull(PodcastLogic.mergeNewShowEpisodes(existing, listOf(ep("a", "A", 100)), "show1"))
    }

    @Test
    fun prefetchTriggersNearTheEnd() {
        val ids = (1..20).map { "id$it" }
        assertFalse(PodcastLogic.shouldPrefetchNextPage("id1", ids))
        assertFalse(PodcastLogic.shouldPrefetchNextPage("id12", ids))
        assertTrue(PodcastLogic.shouldPrefetchNextPage("id13", ids))
        assertFalse(PodcastLogic.shouldPrefetchNextPage(null, ids))
        assertFalse(PodcastLogic.shouldPrefetchNextPage("missing", ids))
    }

    @Test
    fun feedUrlNormalization() {
        assertEquals("https://feeds.example.com/show", PodcastLogic.normalizedPodcastFeedURL(" HTTPS://Feeds.Example.com/show/ "))
        assertEquals("http://example.com:8080/rss?id=1", PodcastLogic.normalizedPodcastFeedURL("http://EXAMPLE.com:8080/rss/?id=1"))
        assertEquals("example.com/feed", PodcastLogic.normalizedPodcastFeedURL("Example.com/Feed//"))
        assertNull(PodcastLogic.normalizedPodcastFeedURL("   "))
        assertNull(PodcastLogic.normalizedPodcastFeedURL(null))
    }

    @Test
    fun extractFeedUrlFromItemJson() {
        val nested = """{"id":"li1","media":{"metadata":{"title":"T","feedURL":"https://A.example.com/rss/"}}}"""
        assertEquals("https://a.example.com/rss", PodcastLogic.extractPodcastFeedURL(nested))
        val flat = """{"id":"li1","media":{"feed_url":"https://b.example.com/x"}}"""
        assertEquals("https://b.example.com/x", PodcastLogic.extractPodcastFeedURL(flat))
        assertNull(PodcastLogic.extractPodcastFeedURL("""{"media":{"metadata":{}}}"""))
        assertNull(PodcastLogic.extractPodcastFeedURL("not json"))
    }

    @Test
    fun autoDownloadIntervalFromCron() {
        assertEquals(PodcastAutoDownloadInterval.daily, PodcastAutoDownloadInterval.from("0 0 * * *"))
        assertEquals(PodcastAutoDownloadInterval.every6Hours, PodcastAutoDownloadInterval.from(" 0  */6 * * * "))
        assertEquals(PodcastAutoDownloadInterval.every6Hours, PodcastAutoDownloadInterval.from("15 */6 * * *"))
        assertEquals(PodcastAutoDownloadInterval.everyHour, PodcastAutoDownloadInterval.from("30 * * * *"))
        assertEquals(PodcastAutoDownloadInterval.weekly, PodcastAutoDownloadInterval.from("0 3 * * 5"))
        assertEquals(PodcastAutoDownloadInterval.daily, PodcastAutoDownloadInterval.from("30 4 * * *"))
        assertEquals(PodcastAutoDownloadInterval.daily, PodcastAutoDownloadInterval.from(null))
        assertEquals(PodcastAutoDownloadInterval.daily, PodcastAutoDownloadInterval.from("garbage"))
    }

    @Test
    fun catalogSortMigration() {
        assertEquals(PodcastCatalogSortField.numEpisodes, PodcastLogic.migratePodcastCatalogSortField("numEpisodes"))
        assertEquals(PodcastCatalogSortField.author, PodcastLogic.migratePodcastCatalogSortField("authorNameLF"))
        assertEquals(PodcastCatalogSortField.numEpisodes, PodcastLogic.migratePodcastCatalogSortField("media.duration"))
        assertEquals(PodcastCatalogSortField.title, PodcastLogic.migratePodcastCatalogSortField("progressFinishedAt"))
        assertEquals(PodcastCatalogSortField.title, PodcastLogic.migratePodcastCatalogSortField("unknown"))
        assertNull(PodcastLogic.migratePodcastCatalogSortFromBookCatalog("media.numTracks"))
    }

    @Test
    fun subscribeBodyMatchesServerShape() {
        val hit = AbsPodcastDirectorySearchHit(
            id = "123", artistId = "9", title = " My Show ", artistName = "Host", genres = listOf("News"),
            cover = "https://img", feedUrl = " https://feed ", explicit = true,
        )
        val root = AbsJson.decoder.parseToJsonElement(PodcastLogic.buildSubscribeRequestBody(hit, "fold", "lib", "/podcasts/")) as JsonObject
        assertEquals("/podcasts/My Show", root["path"]!!.jsonPrimitive.content)
        assertEquals("fold", root["folderId"]!!.jsonPrimitive.content)
        val media = root["media"] as JsonObject
        assertEquals("0 0 * * *", media["autoDownloadSchedule"]!!.jsonPrimitive.content)
        val meta = media["metadata"] as JsonObject
        assertEquals("My Show", meta["title"]!!.jsonPrimitive.content)
        assertEquals("https://feed", meta["feedUrl"]!!.jsonPrimitive.content)
        assertEquals("true", meta["explicit"]!!.jsonPrimitive.content)
        assertEquals(1, (meta["genres"] as JsonArray).size)
    }

    @Test
    fun singleEpisodeArrayBodyWrapsPayload() {
        assertEquals("""[{"title":"A","enclosure":{"url":"u"}}]""", PodcastLogic.singleEpisodeArrayBody("""{"title":"A","enclosure":{"url":"u"}}"""))
    }

    @Test
    fun rssDraftParsingAndLibraryMatching() {
        val feed = """{"podcast":{"metadata":{"title":"Feed","categories":["Tech"]},"episodes":[
            {"title":"Old","publishedAt":1000000000000,"enclosure":{"url":"a"}},
            {"title":" New ","pubDate":"Tue, 02 Sep 2025 10:00:00 +0000","publishedAt":1756807200000},
            {"title":"","subtitle":"s"}]}}"""
        val drafts = AbsPodcastRssFeedEpisodeDraft.episodesFromFeedApiResponse(feed)
        assertEquals(listOf("New", "Old", "Episode"), drafts.map { it.title })
        val lib = ep("e1", "new", 1756807201000)
        assertTrue(drafts[0].matchesLibraryEpisode(lib))
        assertFalse(drafts[1].matchesLibraryEpisode(lib))

        val preview = AbsPodcastFeedPreview.fromFeedApiResponse(feed)
        assertEquals("Feed", preview.title)
        assertEquals(listOf("Tech"), preview.categories)
        assertEquals(3, preview.episodeCount)
    }

    @Test
    fun episodeCountLabels() {
        assertEquals("0 episodes", PodcastLogic.episodeCountLabel(null))
        assertEquals("1 episode", PodcastLogic.episodeCountLabel(1))
        assertEquals("12 episodes", PodcastLogic.episodeCountLabel(12))
    }
}
