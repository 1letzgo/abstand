package de.letzgo.abstand.logic

import de.letzgo.abstand.logic.speech.PcmResampler
import de.letzgo.abstand.logic.speech.SpeechModelCatalog
import de.letzgo.abstand.logic.speech.SpeechTranscriptionLocaleResolver
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.util.Locale

class MiscLogicTest {
    @Test
    fun localeResolverPrefersBookLanguageThenDevice() {
        val r = SpeechTranscriptionLocaleResolver
        val de = r.resolve("German", deviceLocales = listOf(Locale.US))
        assertEquals("de", r.bcp47(de.locale)); assertFalse(de.usedFallback)
        val at = r.resolve("de-AT", deviceLocales = listOf(Locale.US))
        assertEquals("de", r.bcp47(at.locale)); assertFalse(at.usedFallback)
        assertEquals("en-GB", r.bcp47(r.resolve("en-GB").locale))
        // iOS-Verhalten: bei mehreren Regionalmodellen gewinnt das erste mit Region.
        assertEquals("en-GB", r.bcp47(r.resolve("en-AU").locale))
        val unknown = r.resolve("Klingon", deviceLocales = listOf(Locale.forLanguageTag("fr-FR")))
        assertEquals("fr", r.bcp47(unknown.locale)); assertTrue(unknown.usedFallback)
        val none = r.resolve(null, deviceLocales = listOf(Locale.JAPAN))
        assertEquals("ja", r.bcp47(none.locale)); assertFalse(none.usedFallback)
        assertNull(r.matchLocale(Locale.forLanguageTag("xx"), SpeechModelCatalog.supportedLocales))
    }

    @Test
    fun modelCatalogEntryLookup() {
        assertEquals("vosk-model-small-en-gb-0.15", SpeechModelCatalog.entry("en_GB")!!.modelName)
        assertEquals("vosk-model-small-en-us-0.15", SpeechModelCatalog.entry("en-US")!!.modelName)
        assertEquals("vosk-model-small-de-0.15", SpeechModelCatalog.entry("de-CH")!!.modelName)
        assertNull(SpeechModelCatalog.entry("yue-HK"))
        assertNull(SpeechModelCatalog.entry(" "))
        assertEquals("de", SpeechModelCatalog.matchingPickerId("de_DE", listOf("de", "en")))
    }

    @Test
    fun resamplerDownsamplesLinearly() {
        val r = PcmResampler(48_000, 1)
        assertArrayEquals(shortArrayOf(0, 900), r.process(shortArrayOf(0, 300, 600, 900, 1200, 1500)))
        assertArrayEquals(shortArrayOf(0, 900), r.process(shortArrayOf(0, 300, 600, 900, 1200, 1500)))
        assertEquals(16_000, PcmResampler(44_100, 2).silence(1.0).size)
    }

    @Test
    fun achievementsTiersAndProgress() {
        val hours = ListeningAchievementState(ListeningAchievementKind.listeningTimeHours, 300)
        assertEquals(ListeningAchievementTier.LEVEL2, hours.tier)
        assertEquals(0.2, hours.progressToNext, 1e-12)
        assertEquals("300 h / 500 h", hours.valueLine)
        val maxed = ListeningAchievementState(ListeningAchievementKind.listeningTimeHours, 2600)
        assertEquals(ListeningAchievementTier.LEVEL5, maxed.tier)
        assertEquals(1.0, maxed.progressToNext, 0.0)
        assertEquals("2600 h", maxed.valueLine)
        assertEquals("1 h 30 m", ListeningAchievementKind.marathonDay.formattedValue(5400))
        assertEquals("0 m", ListeningAchievementKind.marathonDay.formattedValue(59))
        val locked = ListeningAchievementState(ListeningAchievementKind.currentStreak, 1)
        assertEquals(ListeningAchievementTier.LOCKED, locked.tier)
        assertEquals(1.0 / 3.0, locked.progressToNext, 1e-12)
        assertEquals(
            "Your current streak of consecutive days with listening.\n\nLevel 1: 3\nLevel 2: 7\nLevel 3: 14\nLevel 4: 30\nLevel 5: 90\n\nNot unlocked yet. 1",
            ListeningAchievementKind.currentStreak.alertMessage(locked),
        )
        assertEquals(ListeningAchievementKind.entries.map { it.rawValue }, ListeningAchievementsSnapshot.empty.achievements.map { it.id })
        assertEquals(
            listOf(ListeningAchievementKind.listeningTimeHours, ListeningAchievementKind.currentStreak),
            ListeningAchievementKind.sortedForDisplay(listOf(locked, hours)).map { it.kind },
        )
    }

    @Test
    fun catalogFilterEncodingsMatchIos() {
        assertEquals("progress.aW4tcHJvZ3Jlc3M=", LibraryCatalogQuickFilter.IN_PROGRESS.serverFilterKey)
        assertEquals("progress.ZmluaXNoZWQ=", LibraryCatalogQuickFilter.FINISHED.serverFilterKey)
        assertEquals("progress.bm90LXN0YXJ0ZWQ=", LibraryCatalogQuickFilter.NOT_STARTED.serverFilterKey)
        assertEquals("ebooks.ZWJvb2s=", LibraryCatalogQuickFilter.EBOOKS.serverFilterKey)
        assertEquals("ebooks.c3VwcGxlbWVudGFyeQ==", LibraryCatalogQuickFilter.EBOOKS_SUPPLEMENTARY.serverFilterKey)
        assertNull(LibraryCatalogQuickFilter.DOWNLOADED.serverFilterKey)
        val nav = BooksEntityDetailNav(BooksEntityDetailNav.Kind.AUTHOR, "aut_1", "Jane", 3, libraryId = " lib1 ")
        assertEquals("author:lib1:aut_1", nav.id)
        assertEquals("authors.YXV0XzE=", nav.libraryFilter)
        assertEquals("series:x", BooksEntityDetailNav(BooksEntityDetailNav.Kind.SERIES, "x", "", null).id)
        assertEquals(CatalogSortField.AUTHOR_NAME_LF, CatalogSortField.fromRaw("authorNameLF"))
        assertEquals("media.metadata.authorNameLF", CatalogSortField.AUTHOR_NAME_LF.apiSortParameter)
        assertTrue(CatalogSortField.RANDOM.suppressesSortOrderPicker)
        assertEquals("media.numTracks", PodcastCatalogSortField.NUM_EPISODES.apiSortParameter)
        assertEquals("Audiobooks", BooksBrowseSection.BOOKS.title)
        assertEquals(BooksBrowseSection.EBOOKS_SUPPLEMENTARY, BooksBrowseSection.fromRaw("Supplementary"))
        assertEquals("lastBookUpdated", BooksBrowseSeriesSortField.LAST_BOOK_UPDATED.apiSortParameter)
    }

    @Test
    fun rowLiveState() {
        val s = LibraryRowLiveState
        assertEquals(0.5, s.resolveEbookProgressFraction(0.3, 0.5)!!, 0.0)
        assertEquals(1.0, s.resolveEbookProgressFraction(0.996, null)!!, 0.0)
        assertNull(s.resolveEbookProgressFraction(0.004, null))
        assertEquals("46% read", s.ebookProgressLabel(0.456))
        assertNull(s.ebookProgressLabel(1.0))
        assertEquals("Continue reading", s.ebookOpenPillCaption(0.4))
        assertEquals("Read", s.ebookOpenPillCaption(null))
        val d = s.bookDownloadState("b1", "b1-store", " b1-store ", 0.4, listOf("b2"))
        assertTrue(d.isDownloading); assertFalse(d.isQueued); assertEquals(0.4, d.downloadProgress, 0.0)
        assertEquals(LibraryRowLiveState.DownloadState(false, true, 0.0), s.bookDownloadState("b2", null, null, 0.4, listOf("b2")))
    }

    @Test
    fun coverTintMath() {
        val avg = CoverRgb(0.5, 0.2, 1.0)
        val dark = CoverTintMath.continueListeningCardTint(avg, true, CoverRgb(0.0, 0.0, 0.0))
        assertEquals(0.37, dark.r, 1e-12); assertEquals(0.184, dark.g, 1e-12); assertEquals(0.68, dark.b, 1e-12)
        val light = CoverTintMath.coverDominantBackgroundTint(avg, false, CoverRgb(1.0, 1.0, 1.0))
        assertEquals(0.85, light.r, 1e-12); assertEquals(0.76, light.g, 1e-12); assertEquals(1.0, light.b, 1e-12)
        val px = CoverTintMath.averageRgb(intArrayOf(0xFFFF0000.toInt(), 0xFF0000FF.toInt()))!!
        assertEquals(128 / 255.0, px.r, 1e-12); assertEquals(0.0, px.g, 0.0); assertEquals(128 / 255.0, px.b, 1e-12)
        assertNull(CoverTintMath.averageRgb(IntArray(0)))
        assertEquals("item#r7", CoverAverageRgbCache.continueHero.cacheKey("item", 7))
        assertEquals("item", CoverAverageRgbCache.detailCover.cacheKey("item", 7))
    }

    @Test
    fun statsLayoutAndWeekdays() {
        val sun = listOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
        assertEquals(listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"), StatsLogic.orderedWeekdaySymbols(2, sun))
        assertEquals(sun, StatsLogic.orderedWeekdaySymbols(1, sun))
        val layout = StatsLogic.monthHeatmapLayout(7, 5, 360.0, 16.0, 2, sun)
        assertEquals(36.0, layout.blockSize, 0.0)
        assertEquals(76.0 / 6.0, layout.columnGap, 1e-12)
        assertEquals(328.0, layout.gridWidth, 1e-9)
        assertEquals(318.0, layout.calendarCardHeight, 1e-9)
        assertEquals("Mo", layout.weekdayLabel(0))
        assertEquals("", layout.weekdayLabel(7))
        assertEquals(7, StatsLogic.maxMonthsBack(LocalDate.of(2025, 3, 1), LocalDate.of(2025, 10, 14)))
        assertTrue(StatsLogic.canGoBack(6, LocalDate.of(2025, 3, 1), LocalDate.of(2025, 10, 14)))
        assertFalse(StatsLogic.canGoBack(7, LocalDate.of(2025, 3, 1), LocalDate.of(2025, 10, 14)))
        assertEquals(LocalDate.of(2025, 8, 1), StatsLogic.displayedMonthStart(2, LocalDate.of(2025, 10, 14)))
        assertEquals("No listening", StatsLogic.listeningTimeLabel(0))
    }
}
