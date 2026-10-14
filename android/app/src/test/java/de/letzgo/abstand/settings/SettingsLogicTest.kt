package de.letzgo.abstand.settings

import de.letzgo.abstand.data.AbsAudibleChapter
import de.letzgo.abstand.data.AbsAudibleChaptersResponse
import de.letzgo.abstand.data.AbsDownloadManifest
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsLibraryStatsResponse
import de.letzgo.abstand.data.AbsListeningStatsRecentSession
import de.letzgo.abstand.data.AbsMatchField
import de.letzgo.abstand.data.AbsMatchSeries
import de.letzgo.abstand.data.AbsMetadataMatch
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.ServerM4BEncodeJob
import de.letzgo.abstand.logic.ListeningAchievementKind
import de.letzgo.abstand.model.AdminLogic
import de.letzgo.abstand.model.LibraryCardStyle
import de.letzgo.abstand.model.StatsLogicExt
import de.letzgo.abstand.model.TranslationTargetLanguage
import de.letzgo.abstand.store.LocalAchievementState
import de.letzgo.abstand.ui.admin.AdminLibraryLogic
import de.letzgo.abstand.ui.admin.M4BLogic
import de.letzgo.abstand.ui.metadata.MatchLogic
import de.letzgo.abstand.ui.metadata.MetadataLogic
import de.letzgo.abstand.ui.settings.DebugLogCollector
import de.letzgo.abstand.ui.settings.DownloadsLogic
import de.letzgo.abstand.ui.settings.SettingsHubSection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class SettingsLogicTest {
    @Test
    fun hubStripOrderFollowsIos() {
        assertEquals(
            listOf("Stats", "Account", "Appearance", "Playback", "Downloads", "Server", "Debug"),
            SettingsHubSection.stripOrder(isServerRoot = true, offlineHome = false).map { it.label },
        )
        assertEquals(
            listOf("Stats", "Account", "Appearance", "Playback", "Debug"),
            SettingsHubSection.stripOrder(isServerRoot = false, offlineHome = true).map { it.label },
        )
    }

    @Test
    fun passwordValidationMatchesIos() {
        assertEquals("New password and confirmation do not match.", AdminLogic.validatePasswordChange("a", "b", "c", false))
        assertEquals("New password must be different from the current password.", AdminLogic.validatePasswordChange("a", "a", "a", false))
        assertEquals("Please enter a new password.", AdminLogic.validatePasswordChange("a", " ", " ", false))
        // Root darf das Passwort leeren.
        assertNull(AdminLogic.validatePasswordChange("a", "", "", true))
        assertNull(AdminLogic.validatePasswordChange("a", "b", "b", false))
    }

    @Test
    fun m4bKeysAndActions() {
        assertEquals("abstand_m4b_encode_jobs", AdminLogic.m4bEncodeJobsStorageKey(null))
        assertEquals("abstand_m4b_encode_jobs.https://abs.example.org", AdminLogic.m4bEncodeJobsStorageKey("https://abs.example.org"))
        assertTrue(AdminLogic.isM4BTaskAction("encode-m4b"))
        assertTrue(AdminLogic.isM4BTaskAction(""))
        assertFalse(AdminLogic.isM4BTaskAction("scan-library"))
        val running = ServerM4BEncodeJob("li", "T", "A", 0, ServerM4BEncodeJob.Status.running)
        assertEquals("Converting 42%", M4BLogic.statusLabel(running, 42.4))
        assertEquals("Converting…", M4BLogic.statusLabel(running, null))
        assertEquals("Cancelled", M4BLogic.statusLabel(running.copy(status = ServerM4BEncodeJob.Status.cancelled), 10.0))
    }

    @Test
    fun translationLanguageNormalization() {
        val de = Locale.GERMANY
        assertEquals("de", TranslationTargetLanguage.defaultLanguageCode(de))
        assertEquals("fr", TranslationTargetLanguage.normalized("fr-CA", de))
        assertEquals("de", TranslationTargetLanguage.normalized("xx", de))
        assertEquals("de", TranslationTargetLanguage.normalized("  ", de))
        assertEquals("pt", TranslationTargetLanguage.languageCode("pt_BR"))
        val options = TranslationTargetLanguage.pickerOptions("ja", Locale.US)
        assertTrue(options.any { it.first == "ja" && it.second == "Japanese" })
        assertEquals(options.sortedBy { it.second }, options)
    }

    @Test
    fun cardStyleRawValues() {
        assertEquals(LibraryCardStyle.heroCover, LibraryCardStyle.fromRaw("coverOnly", migrateCoverOnly = true))
        assertEquals(LibraryCardStyle.compact, LibraryCardStyle.fromRaw("coverOnly", migrateCoverOnly = false))
        assertEquals(LibraryCardStyle.compact, LibraryCardStyle.fromRaw(null, migrateCoverOnly = true))
        assertEquals("Cover card", LibraryCardStyle.fromRaw("heroCover", false).label)
    }

    @Test
    fun downloadsHelpers() {
        assertNull(DownloadsLogic.manageDownloadsSubtitle(0, 0, 0))
        assertEquals("3 saved", DownloadsLogic.manageDownloadsSubtitle(3, 0, 0))
        assertEquals("3 saved · 2 pending", DownloadsLogic.manageDownloadsSubtitle(3, 1, 1))
        assertEquals("1 pending", DownloadsLogic.manageDownloadsSubtitle(0, 0, 1))
        assertEquals("10h 23m", DownloadsLogic.formatDuration(10 * 3600 + 23 * 60 + 10.0))
        assertEquals("45m", DownloadsLogic.formatDuration(45 * 60.0))
        val manifest = AbsDownloadManifest(
            format = 1, libraryItemId = "li", episodeId = null, libraryId = "lib1", displayTitle = "T", displayAuthor = null,
            playSessionId = null, savedAtEpoch = 0.0, audioFileExtension = "m4a", totalDuration = null, tracks = emptyList(),
        )
        assertTrue(DownloadsLogic.belongsToAccount(manifest, emptySet()))
        assertTrue(DownloadsLogic.belongsToAccount(manifest, setOf("lib1")))
        assertFalse(DownloadsLogic.belongsToAccount(manifest, setOf("lib2")))
        assertTrue(DownloadsLogic.belongsToAccount(manifest.copy(libraryId = null), setOf("lib2")))
    }

    @Test
    fun statsHelpers() {
        assertEquals("li_abc", StatsLogicExt.normalizedStatsLibraryItemId(" li_abc/ep/ep_1 "))
        assertEquals("li_abc", StatsLogicExt.normalizedStatsLibraryItemId("li_abc-ep_42"))
        assertEquals("abc-ep_42", StatsLogicExt.normalizedStatsLibraryItemId("abc-ep_42"))
        assertEquals("", StatsLogicExt.normalizedStatsLibraryItemId("  "))
        val progress = listOf(
            AbsUserMediaProgress(libraryItemId = "a", episodeId = null, duration = 1.0, progress = 1.0, currentTime = 1.0, isFinished = true, lastUpdate = null),
            AbsUserMediaProgress(libraryItemId = "b", episodeId = "e", duration = 1.0, progress = 1.0, currentTime = 1.0, isFinished = true, lastUpdate = null),
            AbsUserMediaProgress(libraryItemId = "c", episodeId = " ", duration = 1.0, progress = 0.2, currentTime = 1.0, isFinished = false, lastUpdate = null),
        )
        assertEquals(1 to 1, StatsLogicExt.finishedCounts(progress))
        assertNull(StatsLogicExt.snapshotFromLocal(emptyList()))
        val snap = StatsLogicExt.snapshotFromLocal(listOf(LocalAchievementState("activeDays", 12, 5L), LocalAchievementState("bogus", 3, 9L)))!!
        assertEquals(ListeningAchievementKind.entries.size, snap.achievements.size)
        assertEquals(12, snap.achievements.first { it.kind == ListeningAchievementKind.activeDays }.currentValue)
        assertEquals(9L, snap.savedAt)
        val session = AbsListeningStatsRecentSession(
            id = "s", libraryItemId = "li_x-ep_y", episodeId = "ep_y", displayTitle = " ", displayAuthor = "Host",
            mediaType = "podcast", timeListening = 10, startTime = 0.0, startedAt = 1000L,
        )
        val ep = StatsLogicExt.podcastEpisodeForStatsSession(session, "lib")!!
        assertEquals("li_x", ep.libraryItemId)
        assertEquals("Episode", ep.episodeTitle)
        assertEquals("Host", ep.authorLine)
    }

    @Test
    fun seriesSuggestionsAndCommaLists() {
        assertEquals(listOf("a", "b c"), MetadataLogic.splitCommaList(" a, ,b c ,"))
        assertEquals(
            listOf("The Expanse Saga"),
            MetadataLogic.filterSeriesSuggestions(listOf("The Expanse", "the expanse", "The Expanse Saga", "Other", " "), "the expanse"),
        )
    }

    @Test
    fun chapterPreviewWithBranding() {
        val resp = AbsAudibleChaptersResponse(
            chapters = listOf(AbsAudibleChapter("B", 100.0, 900.0), AbsAudibleChapter("A", 0.0, 100.0), AbsAudibleChapter("Outro", 1000.0, 20.0)),
            runtimeLengthSec = 1020.0, brandIntroDurationMs = 2000.0, brandOutroDurationMs = 30000.0, error = null,
        )
        val plain = MetadataLogic.previewChapters(resp, null, removeBranding = false)
        assertEquals(listOf("A", "B", "Outro"), plain.map { it.title })
        assertEquals(1020.0, plain.last().end, 0.0)
        val stripped = MetadataLogic.previewChapters(resp, null, removeBranding = true)
        // Letztes Kapitel (18 s nach Intro-Abzug) ist kürzer als das Outro → entfällt.
        assertEquals(listOf("A", "B"), stripped.map { it.title })
        assertEquals(0.0, stripped[0].start, 0.0)
        assertEquals(98.0, stripped[0].end, 0.0)
        assertEquals(998.0, stripped[1].end, 0.0)
        // Ohne Laufzeit: letztes Kapitel bis start+length bzw. Mediendauer.
        val noRuntime = resp.copy(runtimeLengthSec = null)
        assertEquals(1020.0, MetadataLogic.previewChapters(noRuntime, null, false).last().end, 0.0)
        assertEquals(1500.0, MetadataLogic.previewChapters(noRuntime, 1500.0, false).last().end, 0.0)
        assertTrue(MetadataLogic.previewChapters(null, null, false).isEmpty())
    }

    @Test
    fun audibleRegionFromLanguage() {
        assertEquals("de", MetadataLogic.audibleRegion("German"))
        assertEquals("gb", MetadataLogic.audibleRegion("en-GB"))
        assertEquals("us", MetadataLogic.audibleRegion("en"))
        assertEquals("fr", MetadataLogic.audibleRegion("Français"))
        assertNull(MetadataLogic.audibleRegion("Klingon"))
        assertNull(MetadataLogic.audibleRegion(null))
    }

    @Test
    fun matchFieldsAndPatch() {
        val match = AbsMetadataMatch(
            title = "Leviathan Wakes", author = "James S. A. Corey, Someone", narrator = "Jefferson Mays",
            publishedYear = "2011-06-15", series = listOf(AbsMatchSeries("The Expanse", "1")), cover = "https://x/c.jpg",
        )
        val fields = MatchLogic.availableFields(match)
        assertEquals(
            listOf(AbsMatchField.title, AbsMatchField.author, AbsMatchField.narrator, AbsMatchField.publishedYear, AbsMatchField.series, AbsMatchField.cover),
            fields,
        )
        val patch = MatchLogic.patch(match, setOf(AbsMatchField.author, AbsMatchField.publishedYear, AbsMatchField.series))
        assertEquals(listOf("James S. A. Corey", "Someone"), patch.authorNames)
        assertEquals("2011", patch.publishedYear)
        assertNull(patch.title)
        assertEquals("The Expanse", patch.series!!.single().name)
        assertNull(MatchLogic.coverURL(match, setOf(AbsMatchField.title)))
        assertEquals("https://x/c.jpg", MatchLogic.coverURL(match, setOf(AbsMatchField.cover)))
        // Leere Einträge fallen weg (wie `splitCommaList`).
        val sparse = AbsMetadataMatch(title = null, author = "A, ,B", narrator = " , N ,")
        val sparsePatch = MatchLogic.patch(sparse, setOf(AbsMatchField.author, AbsMatchField.narrator))
        assertEquals(listOf("A", "B"), sparsePatch.authorNames)
        assertEquals(listOf("N"), sparsePatch.narratorNames)
    }

    @Test
    fun librarySubtitleAndEpisodeStatus() {
        val books = AbsLibrary("l", "Books", "book")
        val pods = AbsLibrary("p", "Pods", "podcast")
        assertEquals("Book", AdminLibraryLogic.listSubtitle(books, null))
        val stats = AbsLibraryStatsResponse(12, 3, 4, 7260.0, 1000L, 40, emptyList(), emptyList(), emptyList(), emptyList())
        assertEquals("12 Items · 2 hrs 1 min · 40 Audio tracks", AdminLibraryLogic.listSubtitle(books, stats))
        assertEquals("12 Shows · 2 hrs 1 min · 40 Audio files", AdminLibraryLogic.listSubtitle(pods, stats))
    }

    @Test
    fun debugLogRingBufferAndExport() {
        DebugLogCollector.clear()
        repeat(510) { i -> DebugLogCollector.log("m$i") }
        val entries = DebugLogCollector.entries
        assertEquals(500, entries.size)
        assertEquals("m10", entries.first().message)
        val text = DebugLogCollector.exportText(listOf(DebugLogCollector.Entry(timestampMillis = 0, message = "hello")))
        assertEquals("1970-01-01T00:00:00Z hello", text)
        DebugLogCollector.isCollecting = false
        DebugLogCollector.log { error("must not build the message") }
        DebugLogCollector.isCollecting = true
        DebugLogCollector.clear()
        assertTrue(DebugLogCollector.entries.isEmpty())
    }
}
