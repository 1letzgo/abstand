package de.letzgo.abstand.logic

import de.letzgo.abstand.data.AbsAuthor
import de.letzgo.abstand.data.AbsAuthorDetail
import de.letzgo.abstand.data.AbsAuthorDetailSeries
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookMedia
import de.letzgo.abstand.data.AbsBookMediaMetadata
import de.letzgo.abstand.data.AbsChapter
import de.letzgo.abstand.data.AbsLibraryCollectionListItem
import de.letzgo.abstand.data.AbsLibraryNarratorListItem
import de.letzgo.abstand.data.AbsSeries
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.BooksBrowseGenreListItem
import de.letzgo.abstand.data.BooksBrowseTagListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private fun book(
    id: String,
    title: String = id,
    updatedAt: Long? = 1,
    duration: Double? = 100.0,
    series: List<AbsSeries>? = null,
    authors: List<AbsAuthor>? = null,
    narrators: List<String>? = null,
    genres: List<String>? = null,
    tags: List<String>? = null,
    libraryId: String? = "lib",
) = AbsBook(
    id = id,
    libraryId = libraryId,
    media = AbsBookMedia(
        metadata = AbsBookMediaMetadata(title = title, series = series, authors = authors, narrators = narrators, genres = genres),
        duration = duration,
        numTracks = if ((duration ?: 0.0) > 0) 1 else null,
        tracks = null,
        tags = tags,
    ),
    addedAt = null,
    updatedAt = updatedAt,
)

private fun progress(currentTime: Double = 0.0, duration: Double = 100.0, value: Double = 0.0, finished: Boolean = false) =
    AbsUserMediaProgress(libraryItemId = "b", episodeId = null, duration = duration, progress = value, currentTime = currentTime, isFinished = finished, lastUpdate = 1)

class CatalogLogicTest {
    // MARK: Sortierung / Legacy-Migration

    @Test
    fun legacyCatalogSortMapsAllKnownValues() {
        assertEquals(CatalogSortField.TITLE to false, CatalogLogic.migrateLegacyCatalogSort("titleAsc"))
        assertEquals(CatalogSortField.ADDED_AT to true, CatalogLogic.migrateLegacyCatalogSort("addedAtNewest"))
        assertEquals(CatalogSortField.DURATION to false, CatalogLogic.migrateLegacyCatalogSort("durationShortest"))
        assertEquals(CatalogSortField.PROGRESS_FINISHED_AT to true, CatalogLogic.migrateLegacyCatalogSort("progressFinished"))
        assertEquals(CatalogSortField.RANDOM to false, CatalogLogic.migrateLegacyCatalogSort("randomOrder"))
        assertNull(CatalogLogic.migrateLegacyCatalogSort("bogus"))
    }

    @Test
    fun resolveSortStatePrefersLegacyAndPersists() {
        var persisted: Pair<CatalogSortField, Boolean>? = null
        val r = CatalogLogic.resolveCatalogSortState("authorNameLFDesc", "title", false) { f, d -> persisted = f to d }
        assertEquals(CatalogSortField.AUTHOR_NAME_LF to true, r)
        assertEquals(r, persisted)
    }

    @Test
    fun resolveSortStateFallsBackToStoredOrTitle() {
        var persisted = false
        assertEquals(CatalogSortField.SIZE to true, CatalogLogic.resolveCatalogSortState("unknown", "size", true) { _, _ -> persisted = true })
        assertFalse(persisted)
        assertEquals(CatalogSortField.TITLE to false, CatalogLogic.resolveCatalogSortState(null, "nope", false))
    }

    @Test
    fun randomSortNeverDescending() {
        assertTrue(CatalogLogic.catalogAscending(CatalogSortField.RANDOM, descending = true))
        assertFalse(CatalogLogic.catalogAscending(CatalogSortField.TITLE, descending = true))
        assertFalse(CatalogLogic.seriesApiDescending(BooksBrowseSeriesSortField.RANDOM, true))
        assertEquals("random" to false, CatalogLogic.ebooksSortKey(CatalogSortField.RANDOM, true))
    }

    @Test
    fun filterKeyIsBase64() {
        assertEquals("tags.U2NpLUZp", CatalogLogic.catalogFilterKey("tags", "Sci-Fi"))
        assertEquals(LibraryCatalogQuickFilter.IN_PROGRESS.serverFilterKey, CatalogLogic.catalogFilterKey("progress", "in-progress"))
    }

    // MARK: Paging

    @Test
    fun prefetchOnlyNearEnd() {
        val items = (0 until 30).map { "id$it" }
        assertFalse(CatalogLogic.shouldPrefetchNextPage("id5", items) { it })
        assertTrue(CatalogLogic.shouldPrefetchNextPage("id18", items) { it })
        assertFalse(CatalogLogic.shouldPrefetchNextPage("missing", items) { it })
        assertFalse(CatalogLogic.shouldPrefetchNextPage(null, items) { it })
        assertTrue(CatalogLogic.shouldPrefetchNextPage("id0", listOf("id0")) { it })
    }

    @Test
    fun mergeFirstPageReplacesPrefixAndDropsDuplicatesFromRest() {
        val current = listOf(book("a"), book("b"), book("c"), book("d"))
        val page = listOf(book("c"), book("a", updatedAt = 2))
        val (merged, total) = CatalogLogic.mergeFirstPagePreservingRest(current, page, total = 3)
        assertEquals(listOf("c", "a", "d"), merged!!.map { it.id })
        assertEquals(3, total)
    }

    @Test
    fun mergeFirstPageUnchangedReturnsNull() {
        val current = listOf(book("a"), book("b"))
        val (merged, total) = CatalogLogic.mergeFirstPagePreservingRest(current, listOf(book("a")), total = 1)
        assertNull(merged)
        assertEquals(2, total)
        assertEquals(null to 5, CatalogLogic.mergeFirstPagePreservingRest(current, emptyList(), 5))
    }

    @Test
    fun morePagesMath() {
        assertTrue(CatalogLogic.hasMorePages(total = 161, nextPage = 2))
        assertFalse(CatalogLogic.hasMorePages(total = 160, nextPage = 2))
        assertFalse(CatalogLogic.hasMorePages(total = 0, nextPage = 0))
    }

    // MARK: Facetten

    @Test
    fun genresSortByNameAndCountWithNameTiebreak() {
        val rows = listOf(BooksBrowseGenreListItem("b", 2), BooksBrowseGenreListItem("A", 5), BooksBrowseGenreListItem("c", 2))
        assertEquals(listOf("A", "b", "c"), CatalogLogic.sortedGenres(rows, BooksBrowseFacetSortField.NAME, false).map { it.name })
        assertEquals(listOf("c", "b", "A"), CatalogLogic.sortedGenres(rows, BooksBrowseFacetSortField.NAME, true).map { it.name })
        assertEquals(listOf("A", "b", "c"), CatalogLogic.sortedGenres(rows, BooksBrowseFacetSortField.BOOK_COUNT, true).map { it.name })
        assertEquals(listOf("b", "c", "A"), CatalogLogic.sortedGenres(rows, BooksBrowseFacetSortField.BOOK_COUNT, false).map { it.name })
    }

    @Test
    fun tagsAndNarratorsTreatMissingCountAsZero() {
        val tags = listOf(BooksBrowseTagListItem("x", null), BooksBrowseTagListItem("y", 1))
        assertEquals(listOf("x", "y"), CatalogLogic.sortedTags(tags, BooksBrowseFacetSortField.BOOK_COUNT, false).map { it.name })
        val narrators = listOf(AbsLibraryNarratorListItem("2", "Zoe", 1), AbsLibraryNarratorListItem("1", "adam", 3))
        assertEquals(listOf("adam", "Zoe"), CatalogLogic.sortedNarrators(narrators, BooksBrowseNarratorsSortField.NAME, false).map { it.name })
        assertEquals(listOf("adam", "Zoe"), CatalogLogic.sortedNarrators(narrators, BooksBrowseNarratorsSortField.NUM_BOOKS, true).map { it.name })
    }

    @Test
    fun collectionsSortByDatesAndCount() {
        fun c(id: String, created: Double?, updated: Double?, n: Int) =
            AbsLibraryCollectionListItem(id, id, null, List(n) { book("$id$it") }, created, updated)
        val rows = listOf(c("a", 10.0, 1.0, 1), c("b", 5.0, 3.0, 3), c("c", null, 2.0, 2))
        assertEquals(listOf("a", "b", "c"), CatalogLogic.sortedCollections(rows, BooksBrowseCollectionsSortField.CREATED_AT, true).map { it.id })
        assertEquals(listOf("a", "c", "b"), CatalogLogic.sortedCollections(rows, BooksBrowseCollectionsSortField.LAST_UPDATE, false).map { it.id })
        assertEquals(listOf("b", "c", "a"), CatalogLogic.sortedCollections(rows, BooksBrowseCollectionsSortField.BOOK_COUNT, true).map { it.id })
    }

    @Test
    fun offlineAggregations() {
        val books = listOf(
            book("1", genres = listOf("Fantasy", " "), tags = listOf("fav"), narrators = listOf("N1"), authors = listOf(AbsAuthor("a1", "Ann"))),
            book("2", genres = listOf("Fantasy", "SF"), narrators = listOf("N1", "N2"), authors = listOf(AbsAuthor("", "bob"), AbsAuthor("a1", "Ann"))),
        )
        assertEquals(mapOf("Fantasy" to 2, "SF" to 1), CatalogLogic.offlineGenres(books).associate { it.name to it.numBooks })
        assertEquals(mapOf("fav" to 1), CatalogLogic.offlineTags(books).associate { it.name to it.numBooks })
        assertEquals(mapOf("N1" to 2, "N2" to 1), CatalogLogic.offlineNarrators(books).associate { it.name to it.numBooks })
        val authors = CatalogLogic.offlineAuthors(books)
        assertEquals(listOf("Ann", "bob"), authors.map { it.name })
        assertEquals(listOf("a1", "name:bob"), authors.map { it.id })
        assertEquals(2, authors.first().numBooks)
    }

    // MARK: Entity-Detail

    @Test
    fun seriesSequenceParsing() {
        assertEquals(1.0, CatalogLogic.parseSeriesSequenceNumber("1")!!, 0.0)
        assertEquals(1.5, CatalogLogic.parseSeriesSequenceNumber(" 1.5 ")!!, 0.0)
        assertEquals(2.0, CatalogLogic.parseSeriesSequenceNumber("2a")!!, 0.0)
        assertEquals(1.0, CatalogLogic.parseSeriesSequenceNumber("1.0 (ebook)")!!, 0.0)
        assertEquals(3.0, CatalogLogic.parseSeriesSequenceNumber("Book 3")!!, 0.0)
        assertNull(CatalogLogic.parseSeriesSequenceNumber(""))
        assertNull(CatalogLogic.parseSeriesSequenceNumber("abc"))
    }

    @Test
    fun seriesOrderNeedsTwoNumbers() {
        val a = book("a", series = listOf(AbsSeries("s", "S", "2")))
        val b = book("b", series = listOf(AbsSeries("s", "S", "1")))
        val c = book("c", series = listOf(AbsSeries("s", "S", null)))
        assertEquals(listOf("b", "a", "c"), CatalogLogic.sortBooksBySeriesOrder(listOf(a, c, b), "s", "S").map { it.id })
        // Nur eine Nummer → Eingangsreihenfolge bleibt.
        assertEquals(listOf("c", "a"), CatalogLogic.sortBooksBySeriesOrder(listOf(c, a), "s", "S").map { it.id })
    }

    @Test
    fun seriesOrderUsesTargetSeriesNotFirst() {
        val a = book("a", series = listOf(AbsSeries("x", "Other", "9"), AbsSeries("s", "S", "1")))
        val b = book("b", series = listOf(AbsSeries("s", "S", "2")))
        assertEquals(listOf("a", "b"), CatalogLogic.sortBooksBySeriesOrder(listOf(b, a), "s", "S").map { it.id })
    }

    @Test
    fun authorLayoutGroupsSeriesAndStandalone() {
        val s1 = book("s1", series = listOf(AbsSeries("s", "Saga", "2")))
        val s2 = book("s2", series = listOf(AbsSeries("s", "Saga", "1")))
        val solo = book("solo")
        val detail = AbsAuthorDetail(
            id = "a", name = "A", description = null,
            libraryItems = listOf(s1, solo, s2),
            series = listOf(AbsAuthorDetailSeries("s", "Saga", listOf(s1, s2)), AbsAuthorDetailSeries("e", "Empty", emptyList())),
        )
        val layout = CatalogLogic.authorDetailLayout(detail)
        assertEquals(listOf("Saga"), layout.seriesSections.map { it.name })
        assertEquals(listOf("s2", "s1"), layout.seriesSections.single().books.map { it.id })
        assertEquals(listOf("solo"), layout.standalone.map { it.id })
        assertEquals(3, layout.all.size)
    }

    @Test
    fun entityMatchers() {
        val b = book(
            "x", authors = listOf(AbsAuthor("a1", "Terry Pratchett")), narrators = listOf("Stephen Briggs"),
            genres = listOf(" Fantasy "), tags = listOf("Discworld"), series = listOf(AbsSeries("s9", "Discworld", "1")),
        )
        assertTrue(CatalogLogic.bookMatchesAuthor(b, "a1", ""))
        assertTrue(CatalogLogic.bookMatchesAuthor(b, "zz", "pratchett"))
        assertFalse(CatalogLogic.bookMatchesAuthor(b, "zz", "Gaiman"))
        assertTrue(CatalogLogic.bookMatchesNarrator(b, "stephen briggs"))
        assertTrue(CatalogLogic.bookMatchesGenre(b, "fantasy"))
        assertTrue(CatalogLogic.bookMatchesTag(b, "discworld"))
        assertTrue(CatalogLogic.bookMatchesSeries(b, "nope", "disc"))
        assertTrue(CatalogLogic.bookMatchesLibrary(b, null))
        assertFalse(CatalogLogic.bookMatchesLibrary(b, "other"))
        assertTrue(CatalogLogic.bookMatchesLibrary(book("y", libraryId = null), "other"))
    }

    @Test
    fun countLabels() {
        assertEquals("1 book", CatalogLogic.bookCountLabel(1))
        assertEquals("3 books", CatalogLogic.bookCountLabel(3))
        assertNull(CatalogLogic.bookCountLabel(0))
        assertNull(CatalogLogic.booksCountLine(null))
        assertEquals("4", CatalogLogic.booksCountLine(4))
        assertEquals(listOf("a", "b"), CatalogLogic.seriesCoverBookIds(listOf(book("a"), book("b"), book("c")), maxCount = 2))
    }

    @Test
    fun mergePreferringRicherKeepsFirstOrder() {
        val thin = book("a", duration = null)
        val rich = book("a", duration = 50.0)
        val merged = CatalogLogic.mergeBooksPreferringRicher(listOf(listOf(thin, book("b")), listOf(rich))) { true }
        assertEquals(listOf("a", "b"), merged.map { it.id })
        assertEquals(50.0, merged.first().media.duration!!, 0.0)
    }
}

class BookDetailLogicTest {
    @Test
    fun chapterPlayStateUsesTolerance() {
        val ch = AbsChapter(1, 10.0, 20.0, "One")
        assertEquals(BookChapterPlayState.NotStarted, BookChapterPlayState.resolve(ch, null))
        assertEquals(BookChapterPlayState.InProgress, BookChapterPlayState.resolve(ch, progress(currentTime = 9.5)))
        assertEquals(BookChapterPlayState.Completed, BookChapterPlayState.resolve(ch, progress(currentTime = 19.3)))
        assertEquals(BookChapterPlayState.Completed, BookChapterPlayState.resolve(ch, progress(finished = true)))
    }

    @Test
    fun publishedLineAndMetaValues() {
        assertEquals("Tor - 1999", BookDetailLogic.publishedDisplayLine("Tor", "1999"))
        assertEquals("Tor", BookDetailLogic.publishedDisplayLine("Tor", null))
        assertEquals("1999", BookDetailLogic.publishedDisplayLine(null, "1999"))
        assertNull(BookDetailLogic.publishedDisplayLine(null, null))
        assertNull(BookDetailLogic.trimmedMetaValue(" — "))
        assertEquals("x", BookDetailLogic.trimmedMetaValue(" x "))
        assertEquals("Saga (2)", BookDetailLogic.seriesDisplayLine(AbsSeries("s", "Saga", " 2 ")))
        assertEquals("Saga", BookDetailLogic.seriesDisplayLine(AbsSeries("s", "Saga", "")))
    }

    @Test
    fun discardOnlyWithRealProgress() {
        assertFalse(BookDetailLogic.canDiscardListeningProgress(null, false))
        assertFalse(BookDetailLogic.canDiscardListeningProgress(progress(), false))
        assertTrue(BookDetailLogic.canDiscardListeningProgress(progress(currentTime = 5.0), false))
        assertTrue(BookDetailLogic.canDiscardListeningProgress(progress(finished = true), false))
        assertTrue(BookDetailLogic.canDiscardListeningProgress(progress(value = 0.01), false))
        assertFalse(BookDetailLogic.canDiscardListeningProgress(progress(currentTime = 5.0), true))
    }

    @Test
    fun playProgressFraction() {
        assertEquals(0.0, BookDetailLogic.playProgress01(null, 100.0), 0.0)
        assertEquals(1.0, BookDetailLogic.playProgress01(progress(finished = true), 100.0), 0.0)
        assertEquals(0.4, BookDetailLogic.playProgress01(progress(value = 0.4), 100.0), 0.0)
        assertEquals(0.25, BookDetailLogic.playProgress01(progress(currentTime = 25.0, duration = 0.0), 100.0), 1e-9)
    }

    @Test
    fun remainingCaptionAndBookmarkTitle() {
        assertEquals("1 hr", BookDetailLogic.remainingCaption(3600.0, null))
        assertEquals("30 min", BookDetailLogic.remainingCaption(3600.0, progress(currentTime = 1800.0, duration = 3600.0)))
        assertEquals("< 1 min", BookDetailLogic.remainingCaption(3600.0, progress(finished = true)))
        assertEquals("< 1 min", BookDetailLogic.remainingCaption(0.0, null))
        assertEquals("1:05", BookDetailLogic.defaultBookmarkTitle(65))
        assertEquals("1 hr 1 min", BookDetailLogic.defaultBookmarkTitle(3660))
    }

    @Test
    fun heroLinesAndExpansion() {
        assertEquals("1:00 · 1999", BookDetailLogic.tertiaryLine(listOf("1:00", " 1999 ", "—", "")))
        assertTrue(BookDetailLogic.offersExpansion("x".repeat(201)))
        assertTrue(BookDetailLogic.offersExpansion("a\nb\nc\nd\ne"))
        assertFalse(BookDetailLogic.offersExpansion("short"))
        assertEquals(listOf("a1" to "Ann"), BookDetailLogic.heroAuthorLinks(book("x", authors = listOf(AbsAuthor("a1", "Ann")))))
        assertEquals(emptyList<Pair<String, String>>(), BookDetailLogic.heroAuthorLinks(book("x")))
        val (r0, r1) = BookDetailLogic.sessionRange(duration = 200.0, startTime = 50.0, currentTime = 100.0)
        assertEquals(0.25, r0, 1e-9)
        assertEquals(0.5, r1, 1e-9)
    }

    @Test
    fun ebookFractionClamps() {
        assertNull(BookDetailLogic.ebookDisplayFraction(null, 0.004))
        assertEquals(1.0, BookDetailLogic.ebookDisplayFraction(0.996, null)!!, 0.0)
        assertEquals(0.5, BookDetailLogic.ebookDisplayFraction(0.3, 0.5)!!, 0.0)
    }
}
