package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsAuthorShelfEntity
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookMedia
import de.letzgo.abstand.data.AbsBookMediaMetadata
import de.letzgo.abstand.data.AbsItemsInProgressPayload
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfLocalization
import de.letzgo.abstand.data.AbsStartShelfSection
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.ui.home.ContinueHeroMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeShelfLogicTest {
    private fun book(id: String, title: String = id, lib: String? = "L1", tracks: Int? = 1, duration: Double? = 3600.0, addedAt: Long? = null) =
        AbsBook(
            id = id, libraryId = lib, addedAt = addedAt, updatedAt = null,
            media = AbsBookMedia(metadata = AbsBookMediaMetadata(title = title), duration = duration, numTracks = tracks, tracks = null),
        )

    private fun episode(item: String, ep: String, lib: String? = "P1", title: String = ep) = AbsPodcastEpisodeListItem(
        libraryItemId = item, libraryId = lib, episodeId = ep, episodeTitle = title, showTitle = "Show", authorLine = "A", duration = 600.0,
    )

    private fun progress(item: String, ep: String? = null, current: Double = 100.0, finished: Boolean = false, last: Long = 0, ebook: Double? = null) =
        AbsUserMediaProgress(
            libraryItemId = item, episodeId = ep, duration = 3600.0, progress = current / 3600.0, currentTime = current,
            isFinished = finished, lastUpdate = last, ebookProgress = ebook,
        )

    private fun progressMap(vararg p: AbsUserMediaProgress) = p.associateBy { it.progressLookupKey }

    private val continueCat = HomeShelfLogic.homeContinueCategory

    // MARK: Kategorien

    @Test
    fun effectiveOrderKeepsContinueFirstAndInsertsEbooksAfterIt() {
        val order = HomeShelfLogic.effectiveCategoryOrder(emptyList(), showNewestEpisodes = false)
        assertEquals(continueCat, order[0])
        assertEquals("continueEbooks", order[1])
        assertFalse("newestEpisodes" in order)
    }

    @Test
    fun effectiveOrderAppliesSavedTailAndNewestEpisodesOnlyWithPodcasts() {
        val saved = listOf("recommended", continueCat, "newestItems", "unknownCategory")
        val order = HomeShelfLogic.effectiveCategoryOrder(saved, showNewestEpisodes = true)
        assertEquals(listOf(continueCat, "recommended", "newestItems"), order.take(3))
        assertTrue("newestEpisodes" in order)
        assertFalse("unknownCategory" in order)
        // Standardposition aus `settingsCategoryOrder` (nach Continue series).
        val plain = HomeShelfLogic.effectiveCategoryOrder(emptyList(), showNewestEpisodes = true)
        assertEquals(plain.indexOf("continueSeries") + 1, plain.indexOf("newestEpisodes"))
    }

    @Test
    fun disabledCategoriesMigrateLegacyFallback() {
        assertNull(HomeShelfLogic.migratedDisabledCategories(setOf("recommended")))
        assertEquals(setOf("recommended", continueCat), HomeShelfLogic.migratedDisabledCategories(setOf("recommended", "itemsInProgressFallback")))
        assertFalse(HomeShelfLogic.isEnabled("itemsInProgressFallback", setOf(continueCat)))
        assertTrue(HomeShelfLogic.isEnabled("recommended", setOf(continueCat)))
    }

    @Test
    fun moveCategoryKeepsContinueFixed() {
        val cats = listOf(continueCat, "a", "b", "c")
        assertNull(HomeShelfLogic.moveCategory(cats, continueCat, "b"))
        assertNull(HomeShelfLogic.moveCategory(cats, "a", continueCat))
        assertEquals(listOf(continueCat, "b", "c", "a"), HomeShelfLogic.moveCategory(cats, "a", "c"))
        assertEquals(listOf(continueCat, "c", "a", "b"), HomeShelfLogic.moveCategory(cats, "c", "a"))
    }

    @Test
    fun shelvesForDashboardFollowSettingsOrderAndSkipDisabled() {
        val rows = listOf(StartCategoryRow(continueCat, "Continue listening"), StartCategoryRow("newestItems", "Recently added"), StartCategoryRow("recommended", "Recommended"))
        val shelves = listOf(
            AbsStartShelfSection("r", "recommended", "Recommended", books = listOf(book("x"))),
            AbsStartShelfSection("n", "newestItems", "Recently added", books = listOf(book("y"))),
            AbsStartShelfSection("c", continueCat, "Continue listening", books = listOf(book("z"))),
        )
        val visible = HomeShelfLogic.shelvesForHomeBrowseSection(AbsStartShelfLocalization.homeBrowseContinueSectionID, rows, shelves, setOf("newestItems"))
        assertEquals(listOf(continueCat, "recommended"), visible.map { it.category })
        assertTrue(HomeShelfLogic.isAnyShelfEnabled(rows, setOf("newestItems")))
        assertFalse(HomeShelfLogic.isAnyShelfEnabled(rows, setOf(continueCat, "newestItems", "recommended")))
    }

    @Test
    fun homeBrowseCategoryClampsLegacyPillsToDashboard() {
        val continueId = AbsStartShelfLocalization.homeBrowseContinueSectionID
        val strip = HomeShelfLogic.homeBrowseStripIds(offline = false, anyEnabled = true)
        assertEquals(continueId, HomeShelfLogic.clampHomeBrowseCategory("stats", emptyList(), strip))
        assertEquals(continueId, HomeShelfLogic.clampHomeBrowseCategory("newestSeries", emptyList(), strip))
        assertEquals(continueId, HomeShelfLogic.clampHomeBrowseCategory("whatever", emptyList(), strip))
        assertEquals("whatever", HomeShelfLogic.clampHomeBrowseCategory("whatever", emptyList(), emptyList()))
        assertEquals(continueId, HomeShelfLogic.initialHomeBrowseCategory("recentlyListened"))
        assertEquals(AbsStartShelfLocalization.homeBrowseRecentSectionID, HomeShelfLogic.initialHomeBrowseCategory("newestItems"))
        assertEquals(continueId, HomeShelfLogic.initialHomeBrowseCategory(null))
        assertEquals(listOf(continueId), HomeShelfLogic.homeBrowseStripIds(offline = true, anyEnabled = false))
    }

    // MARK: Merge

    @Test
    fun mergePersonalizedShelvesCombinesLibrariesPerCategory() {
        val p = progressMap(progress("b", last = 10), progress("a", last = 20))
        val base = listOf(
            AbsStartShelfSection("c1", continueCat, "Continue listening", books = listOf(book("b"))),
            AbsStartShelfSection("n1", "newestItems", "Recently added", books = listOf(book("old", addedAt = 1))),
        )
        val extra = listOf(
            AbsStartShelfSection("c2", continueCat, "", books = listOf(book("a"), book("b"))),
            AbsStartShelfSection("n2", "newestItems", "Recently added", books = listOf(book("new", addedAt = 5), book("nodate"))),
            AbsStartShelfSection("au", "newestAuthors", "New authors", authors = listOf(AbsAuthorShelfEntity("1", "X", 2, null))),
        )
        val merged = HomeShelfLogic.mergePersonalizedShelves(base, extra, p)
        assertEquals(listOf(continueCat, "newestItems", "newestAuthors"), merged.map { it.category })
        assertEquals("c1", merged[0].id)
        assertEquals(listOf("a", "b"), merged[0].books.map { it.id }) // nach lastUpdate
        assertEquals(listOf("new", "old", "nodate"), merged[1].books.map { it.id }) // nach addedAt, undatiert hinten
    }

    @Test
    fun upsertLocalOnlyShelfInsertsAtSettingsPosition() {
        val order = listOf(continueCat, "continueEbooks", "newestEpisodes", "newestItems")
        val shelves = listOf(
            AbsStartShelfSection("c", continueCat, "C"),
            AbsStartShelfSection("n", "newestItems", "N"),
        )
        val ebooks = AbsStartShelfSection("e", "continueEbooks", "E")
        assertEquals(listOf(continueCat, "continueEbooks", "newestItems"), HomeShelfLogic.upsertLocalOnlyShelf(ebooks, shelves, order).map { it.category })
        // Unbekannt in der Reihenfolge → direkt nach Continue.
        val other = AbsStartShelfSection("o", "continueEbooks", "E")
        assertEquals(listOf(continueCat, "continueEbooks", "newestItems"), HomeShelfLogic.upsertLocalOnlyShelf(other, shelves, listOf()).map { it.category })
        // Server-Apply behält lokal-only Regale.
        val next = listOf(AbsStartShelfSection("n2", "newestItems", "N"))
        val prior = listOf(ebooks, AbsStartShelfSection("ne", "newestEpisodes", "NE"))
        val kept = HomeShelfLogic.mergingPreservedLocalOnly(next, prior, setOf("newestEpisodes"), order)
        assertEquals(listOf("continueEbooks", "newestItems"), kept.map { it.category })
    }

    // MARK: Continue listening

    @Test
    fun finishedFilterDropsFinishedShortAndBlockedButKeepsActive() {
        val shelves = listOf(
            AbsStartShelfSection("c", continueCat, "C", books = listOf(book("done"), book("short"), book("ok"), book("blocked"), book("playing")), podcastEpisodes = listOf(episode("s", "e1"))),
            AbsStartShelfSection("n", "newestItems", "N", books = listOf(book("done"))),
        )
        val ctx = ContinueContext(
            progressMap(
                progress("done", finished = true), progress("short", current = 1.0), progress("ok", last = 5),
                progress("blocked"), progress("s", "e1", last = 9),
            ),
            blockedKeys = setOf("blocked"),
            activeKey = "playing",
        )
        val filtered = HomeShelfLogic.applyFinishedFilter(shelves, ctx)!!
        assertEquals(listOf("ok", "playing"), filtered[0].books.map { it.id })
        assertEquals(listOf("s-e1"), filtered[0].podcastEpisodes.map { it.progressLookupKey })
        assertEquals(listOf("done"), filtered[1].books.map { it.id }) // andere Regale unberührt
        assertNull(HomeShelfLogic.applyFinishedFilter(filtered, ctx))
    }

    @Test
    fun mergeIntoContinueAddsMissingOrCreatesShelf() {
        val p = progressMap(progress("a", last = 1), progress("b", last = 2))
        val withShelf = listOf(AbsStartShelfSection("n", "newestItems", "N"), AbsStartShelfSection("c", continueCat, "C", books = listOf(book("a"))))
        val merged = HomeShelfLogic.mergeIntoContinueShelf(withShelf, listOf(book("a"), book("b")), emptyList(), emptySet(), p, "new")!!
        assertEquals(listOf("b", "a"), merged[1].books.map { it.id })
        assertNull(HomeShelfLogic.mergeIntoContinueShelf(merged, listOf(book("b")), emptyList(), emptySet(), p, "new"))
        val created = HomeShelfLogic.mergeIntoContinueShelf(listOf(AbsStartShelfSection("n", "newestItems", "N")), listOf(book("a")), emptyList(), emptySet(), p, "fresh")!!
        assertEquals("fresh", created[0].id)
        assertEquals(continueCat, created[0].category)
        // Ausgeschaltetes Continue-Regal zählt nicht als vorhanden.
        val disabledResult = HomeShelfLogic.mergeIntoContinueShelf(withShelf, listOf(book("b")), emptyList(), setOf(continueCat), p, "x")!!
        assertEquals("x", disabledResult[0].id)
    }

    @Test
    fun inProgressCandidatesRespectLibrariesAndProgress() {
        val payload = AbsItemsInProgressPayload(
            books = listOf(book("a", lib = "L1"), book("b", lib = "L2"), book("c", lib = "L1", tracks = 0, duration = 0.0), book("d", lib = "L1")),
            podcastEpisodes = listOf(episode("s", "1", lib = "P1"), episode("s", "2", lib = "P2"), episode("s", "3", lib = "P1")),
        )
        val ctx = ContinueContext(progressMap(progress("a", last = 1), progress("b"), progress("c"), progress("s", "1"), progress("s", "2"), progress("s", "3", finished = true)))
        assertEquals(listOf("a"), HomeShelfLogic.inProgressAudiobookCandidates(payload, ctx, setOf("L1"), null).map { it.id })
        assertEquals(listOf("a"), HomeShelfLogic.inProgressAudiobookCandidates(payload, ctx, emptySet(), "L1").map { it.id })
        assertTrue(HomeShelfLogic.inProgressAudiobookCandidates(payload, ctx, emptySet(), null).isEmpty())
        assertEquals(listOf("s-1"), HomeShelfLogic.inProgressPodcastEpisodeCandidates(payload, ctx, setOf("P1"), null).map { it.progressLookupKey })
    }

    @Test
    fun localCandidatesIncludeDownloadsFromOtherLibraries() {
        val ctx = ContinueContext(progressMap(progress("a", last = 2), progress("b", last = 3), progress("ep", ep = "x")))
        val pool = listOf(book("a", lib = "L1"), book("b", lib = "L9"), book("ep"))
        val out = HomeShelfLogic.localContinueAudiobookCandidates(pool, setOf("b"), ctx, setOf("L1"), null)
        assertEquals(listOf("b", "a"), out.map { it.id })
    }

    @Test
    fun normalizeConsolidatesDuplicateContinueShelves() {
        val p = progressMap(progress("a", last = 1), progress("b", last = 2))
        val shelves = listOf(
            AbsStartShelfSection("legacy", "itemsInProgressFallback", "Old", books = listOf(book("a"))),
            AbsStartShelfSection("n", "newestItems", "N"),
            AbsStartShelfSection("c", continueCat, "C", books = listOf(book("b"), book("a"))),
        )
        val out = HomeShelfLogic.normalizeContinueShelves(shelves, emptySet(), p)!!
        assertEquals(listOf(continueCat, "newestItems"), out.map { it.category })
        assertEquals("legacy", out[0].id)
        assertEquals(listOf("b", "a"), out[0].books.map { it.id })
        assertNull(HomeShelfLogic.normalizeContinueShelves(out, emptySet(), p))
    }

    @Test
    fun continueShelfVisibilityAndOpenProgress() {
        val shelves = listOf(AbsStartShelfSection("c", continueCat, "C"))
        assertFalse(HomeShelfLogic.continueShelfHasVisibleItems(shelves, emptySet()))
        assertTrue(HomeShelfLogic.hasOpenProgressExpectingContinue(progressMap(progress("a"))))
        assertFalse(HomeShelfLogic.hasOpenProgressExpectingContinue(progressMap(progress("a", finished = true), progress("b", current = 1.0))))
        assertEquals(listOf("x", "y"), HomeShelfLogic.startBooksUnion(listOf(AbsStartShelfSection("1", "a", "A", books = listOf(book("x"), book("y"))), AbsStartShelfSection("2", "b", "B", books = listOf(book("x"))))).map { it.id })
    }

    @Test
    fun ebookFractionAndHeroMath() {
        assertNull(HomeShelfLogic.ebookDisplayFraction(null, 0.004))
        assertEquals(0.5, HomeShelfLogic.ebookDisplayFraction(0.2, 0.5)!!, 1e-9)
        assertEquals(1.0, HomeShelfLogic.ebookDisplayFraction(0.996, null)!!, 1e-9)
        val p = progress("a", current = 600.0)
        assertEquals(3000.0, ContinueHeroMath.bookRemainingSeconds(3600.0, p), 1e-9)
        assertEquals(3600.0, ContinueHeroMath.bookRemainingSeconds(3600.0, null), 1e-9)
        assertEquals(0.0, ContinueHeroMath.bookRemainingSeconds(3600.0, progress("a", finished = true)), 1e-9)
        assertNull(ContinueHeroMath.bookProgress(progress("a", finished = true)))
        assertEquals(1800.0, ContinueHeroMath.episodeRemainingSeconds(0.0, progress("s", "e", current = 1800.0)), 1e-9)
    }
}
