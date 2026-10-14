package de.letzgo.abstand.data

import kotlinx.serialization.SerializationException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Golden-File-Parität: dieselben Fixtures sollen später auch die iOS-Tests speisen. */
class ModelsDecodingTest {
    private val dec = AbsJson.decoder

    @Test
    fun loginResponse() {
        val r = dec.decodeFromString(AbsLoginResponseSerializer, Fixtures.api("login_response.json"))
        val u = r.user
        assertEquals("usr_7f3c2a1e", u.id)
        assertEquals("legacy-token-abc123", u.token)
        assertEquals("refresh-token-r1", u.refreshToken)
        assertTrue(u.effectiveBearerToken.startsWith("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."))
        assertFalse(u.effectiveBearerToken.endsWith(" "))
        assertTrue(u.isAdmin)
        assertFalse(u.isRoot)
        assertEquals("lib_books_main", r.userDefaultLibraryId)
        assertEquals("de-de", r.serverSettings?.language)
        assertEquals(2, r.serverSettings?.logLevel)
        assertEquals(false, r.serverSettings?.scannerFindCovers)
        assertNull(r.serverSettings?.chromecastEnabled)

        val p = u.mediaProgress!!
        assertEquals(3, p.size)
        p[0].let {
            assertEquals("6f1d0b52-1111-4c4c-9e9e-000000000001", it.mediaProgressServerId)
            assertEquals("li_book_0001", it.libraryItemId)
            assertNull(it.episodeId)
            assertEquals(0.25, it.ebookProgress!!, 0.0)
            assertEquals("epubcfi(/6/14!/4/2/1:0)", it.ebookLocation)
            assertEquals(1760430000000L, it.lastUpdate)
            assertEquals("li_book_0001", it.progressLookupKey)
            assertEquals("6f1d0b52-1111-4c4c-9e9e-000000000001", it.idForMediaProgressDeleteRequest)
        }
        p[1].let {
            // `libraryItemId` fehlt → aus Composite-`id` vor `-ep_`.
            assertEquals("li_pod_0001", it.libraryItemId)
            assertEquals("ep_0042", it.episodeId)
            assertTrue(it.isFinished)
            assertEquals(2710.0, it.duration, 0.0)
            // `try?` — falscher Typ wird still `nil`.
            assertNull(it.ebookProgress)
            assertEquals("li_pod_0001-ep_0042", it.progressLookupKey)
        }
        assertEquals("li_book_0002", p[2].libraryItemId)
        assertNull(p[2].lastUpdate)

        val b = u.bookmarks!!
        assertEquals(1235, b[0].time) // 1234.6 → gerundet
        assertEquals(1760000000000L, b[0].createdAt)
        assertEquals("li_book_0001-1235", b[0].id)
        assertEquals("", b[1].title)
        assertNull(b[1].createdAt)
    }

    @Test
    fun mediaProgressRoundTrip() {
        val r = dec.decodeFromString(AbsLoginResponseSerializer, Fixtures.api("login_response.json"))
        val first = r.user.mediaProgress!![0]
        val json = AbsJson.encoder.encodeToString(AbsUserMediaProgressSerializer, first)
        assertTrue(json.contains("\"id\":\"6f1d0b52-1111-4c4c-9e9e-000000000001\""))
        assertEquals(first, dec.decodeFromString(AbsUserMediaProgressSerializer, json))
    }

    @Test
    fun mediaProgressWithoutIdsFails() {
        assertThrows(SerializationException::class.java) {
            dec.decodeFromString(AbsUserMediaProgressSerializer, """{"duration": 10}""")
        }
        // `decodeIfPresent(Double)` ist strikt: String statt Zahl verwirft die Zeile (wie iOS).
        assertThrows(SerializationException::class.java) {
            dec.decodeFromString(AbsUserMediaProgressSerializer, """{"libraryItemId":"x","duration":"10"}""")
        }
    }

    @Test
    fun libraries() {
        val libs = dec.decodeFromString(AbsLibrariesResponseSerializer, Fixtures.api("libraries.json")).libraries
        assertEquals(listOf("lib_books_main", "lib_pods", "lib_legacy"), libs.map { it.id })
        assertTrue(libs[0].isBookLibrary)
        assertTrue(libs[1].isPodcastLibrary)
        assertNull(libs[2].mediaType)
        assertTrue(libs[2].isBookLibrary)
        assertEquals(0, libs[2].displayOrderOrZero)
    }

    @Test
    fun libraryItemsPageBook() {
        val page = dec.decodeFromString(AbsPage.serializer(AbsBookSerializer), Fixtures.api("library_items_page_book.json"))
        assertEquals(187, page.total)
        assertEquals(0, page.page)
        assertEquals(3, page.results.size)

        val a = page.results[0]
        assertEquals("The Quiet Lighthouse", a.displayTitle)
        assertEquals("Mara Feldt, Jonas Brink", a.displayAuthors)
        assertEquals("book_media_0001", a.mediaId)
        assertEquals(1700000000000L, a.addedAt)
        assertTrue(a.isPlayableAudiobook)
        assertEquals("epub", a.media.ebookFormat)
        assertTrue(a.hasSupplementalEpub)
        assertTrue(a.isCatalogSupplementaryEbook)
        assertTrue(a.showsAttachedEbookCoverBadge)
        assertEquals("Coastline #2", a.media.metadata.resolvedSeriesDisplay)
        assertEquals(listOf("favourite"), a.media.tags)
        assertEquals(523456789L, a.media.size)
        assertEquals("B0TESTASIN", a.media.metadata.asin)

        val b = page.results[1]
        assertEquals("Pia Morgen", b.media.metadata.authorName) // Fallback-Key `author`
        assertEquals(listOf(AbsSeries("ser_atlas", "Atlas", "1")), b.media.metadata.series) // Einzelobjekt → Liste
        assertEquals("https://feeds.example.org/atlas.xml", b.media.metadata.feedUrl) // `feedURL`, getrimmt
        assertEquals("Atlas (1)", b.media.metadata.resolvedSeriesDisplay)
        assertFalse(b.isPlayableAudiobook)
        assertTrue(b.isUsableLibraryCatalogRow)
        assertTrue(b.belongsToLibrarySeries)

        val c = page.results[2]
        assertEquals("pdf", c.media.ebookFormat) // Fallback-Key `ebookFileFormat`
        assertEquals("Ruth Okafor", c.displayAuthors)
        assertFalse(c.belongsToLibrarySeries) // Serien-Stub ohne Namen
        assertEquals(setOf(AbsEbookFormat.pdf), c.attachedEbookFormats)
        assertTrue(c.isCatalogPureEbookLibraryItem)
        assertTrue(c.matchesBooksEbookCatalogFilter)
    }

    @Test
    fun libraryItemsPagePodcast() {
        val page = dec.decodeFromString(AbsPage.serializer(AbsBookSerializer), Fixtures.api("library_items_page_podcast.json"))
        assertEquals(2, page.results.size)
        val show = page.results[0]
        assertEquals(true, show.media.autoDownloadEpisodes)
        assertEquals("0 * * * *", show.media.autoDownloadSchedule)
        assertEquals(3, show.media.maxNewEpisodesToDownload)
        assertEquals("https://feeds.example.org/nightshift", show.media.metadata.feedUrl)
        assertTrue(show.isListablePodcastLibraryItem)
        // Leerer Titel, aber Autor vorhanden → trotzdem listbar.
        assertTrue(page.results[1].isListablePodcastLibraryItem)
    }

    @Test
    fun expandedItemWithTracksChaptersAndFiles() {
        val book = dec.decodeFromString(AbsBookSerializer, Fixtures.api("item_expanded_book.json"))
        val tracks = book.media.tracks!!
        assertEquals(2, tracks.size) // `tracks` vorhanden → `audioFiles` ignoriert
        assertEquals("1001", tracks[0].ino) // aus verschachteltem `metadata.ino`
        assertEquals("1004", tracks[1].ino)
        assertEquals(3600.0, tracks[1].startOffset, 0.0)
        val chapters = book.media.chapters!!
        assertEquals(listOf("Opening", "The Letter"), chapters.map { it.title })
        assertEquals(1800.5, chapters[1].start, 0.0)
        assertEquals(3, book.libraryFiles!!.size)
        assertEquals("1002", book.epubIno)
        assertEquals("1002" to AbsEbookFormat.epub, book.readableAttachedEbook)
        assertEquals(2345678L, book.attachedEbookLibraryFileByteCount)
        assertFalse(book.isSingleM4BAudiobook)
        assertTrue(book.isM4BConversionCandidate)
        assertEquals(listOf("Ilse Raven", "Tom Weller"), book.media.metadata.narratorNamesForLibraryBrowseCoverMatch())
        assertEquals("Mara Feldt, Jonas Brink", book.displayAuthors)
        assertTrue(book.media.metadata.hasRichMetadata)

        // Encode → Decode bleibt stabil (Cache-Pfad).
        val json = AbsJson.encoder.encodeToString(AbsBookSerializer, book)
        assertEquals(book, dec.decodeFromString(AbsBookSerializer, json))
    }

    @Test
    fun expandedItemFallsBackToSortedAudioFiles() {
        val book = dec.decodeFromString(AbsBookSerializer, Fixtures.api("item_expanded_audiofiles_only.json"))
        val tracks = book.media.tracks!!
        assertEquals(listOf(1, 2, 3), tracks.map { it.index })
        assertEquals(listOf("a.m4a", "b.m4a", "c.m4a"), tracks.map { it.title })
        assertEquals(listOf(0.0, 100.0, 100.0), tracks.map { it.startOffset })
        assertEquals(0.0, tracks[1].duration, 0.0)
        assertNull(tracks[0].ino)
    }

    @Test
    fun numericInoBreaksDecodingLikeIOS() {
        // iOS: `try decodeIfPresent(String.self, forKey: .ino)` wirft bei Zahl — der Int64-Zweig greift nie.
        assertThrows(SerializationException::class.java) {
            dec.decodeFromString(AbsAudioTrackSerializer, """{"index":1,"duration":1,"ino":42}""")
        }
        assertThrows(SerializationException::class.java) {
            dec.decodeFromString(AbsLibraryFileSerializer, """{"ino":42}""")
        }
        assertThrows(SerializationException::class.java) {
            dec.decodeFromString(AbsLibraryFileSerializer, """{"fileType":"audio"}""")
        }
    }

    @Test
    fun itemsInProgress() {
        val payload = AbsApiClient.decodeInProgressPayload(Fixtures.api("items_in_progress.json"))
        assertEquals(listOf("li_book_0001"), payload.books.map { it.id })
        assertEquals(2, payload.podcastEpisodes.size)
        payload.podcastEpisodes[0].let {
            assertEquals("li_pod_0001", it.libraryItemId)
            assertEquals("ep_0042", it.episodeId)
            assertEquals("lib_pods", it.libraryId)
            assertEquals("Episode 42: The Long Night", it.episodeTitle)
            assertEquals("Night Shift Radio", it.showTitle)
            assertEquals("Studio Nord", it.authorLine)
            assertEquals(2710.0, it.duration, 0.0)
            assertEquals(1759723200000L, it.publishedAt)
            assertEquals("li_pod_0001-ep_0042", it.id)
        }
        payload.podcastEpisodes[1].let {
            assertEquals("Episode", it.episodeTitle)
            assertEquals("Sunday Papers (nested)", it.showTitle)
            assertEquals("Lena Paar", it.authorLine)
            assertEquals(1759000000000L, it.publishedAt) // 1759000000000.4 → gerundet
        }
    }

    @Test
    fun personalizedShelves() {
        val shelves = AbsApiClient.parsePersonalizedStartShelves(Fixtures.api("personalized_shelves.json"))
        assertEquals(listOf("recentlyListened", "continueSeries", "newestSeries", "newestAuthors"), shelves.map { it.category })
        assertEquals(listOf("Continue listening", "Continue series", "Recent series", "New authors"), shelves.map { it.displayTitle })
        assertEquals(listOf("li_book_0001"), shelves[0].books.map { it.id })
        assertEquals(listOf("li_ebook_0005"), shelves[1].books.map { it.id })
        assertEquals(listOf("ser_atlas"), shelves[2].series.map { it.id })
        assertEquals("Pia Morgen", shelves[2].series[0].cardAuthorsLine)
        assertEquals(listOf("aut_mara"), shelves[3].authors.map { it.id })
        assertTrue(shelves[3].authors[0].hasAuthorImage)
    }

    @Test
    fun listeningStats() {
        val s = AbsListeningStatsResponse.decodeAPIPayload(Fixtures.api("listening_stats.json"))
        assertEquals(98765, s.totalTime)
        assertEquals(1800, s.today)
        assertEquals(1201, s.days["2026-10-13"]) // Double-Map → gerundet
        assertEquals(5, s.days.size)
        assertEquals(mapOf("0" to 600, "1" to 3600, "2" to 3000), s.dayOfWeek)
        assertEquals(setOf("li_book_0001", "li_pod_0001", "li_book_0009", "li_meta_broken"), s.items.keys)
        assertEquals(54322, s.items["li_book_0001"]!!.timeListening)
        assertEquals("li_pod_0001", s.items["li_pod_0001"]!!.id) // Key als ID-Fallback
        assertTrue(s.items["li_pod_0001"]!!.mediaMetadata!!.isPodcastLike)
        assertEquals("Ada North", s.items["li_book_0009"]!!.mediaMetadata!!.authors!!.single().name)
        assertEquals("stats-author-0", s.items["li_book_0009"]!!.mediaMetadata!!.authors!!.single().id)
        assertNull(s.items["li_meta_broken"]!!.mediaMetadata)
        assertEquals(2, s.recentSessions.size)
        assertEquals(1500, s.recentSessions[0].timeListening)
        assertTrue(s.recentSessions[0].isPodcastEpisodeSession)
        assertFalse(s.recentSessions[1].isPodcastEpisodeSession)
        assertEquals(14000.5, s.recentSessions[1].startTime, 0.0)

        val today = java.time.LocalDate.of(2026, 10, 14)
        assertEquals("li_book_0001", s.itemsSortedByListeningTime.first().first)
        assertEquals(5, s.daysActive)
        assertEquals(3600, s.marathonDayListeningSeconds)
        assertEquals(4, s.distinctListenedAuthorCount)
        assertEquals(6601, s.secondsInLastDays(3, today))
        assertEquals(6601, s.secondsThisCalendarMonth(today))
        assertEquals(7201, s.secondsThisCalendarYear(today))
        assertEquals(3, s.currentListeningStreakDays(today))
        assertEquals(3, s.bestListeningStreakDays())
        assertEquals(3, s.bookLikeItemCount)
        assertEquals(1, s.podcastLikeItemCount)
        val bars = s.dayOfWeekBars(java.util.Locale.US)
        assertEquals(listOf(3600, 3000, 0, 0, 0, 0, 600), bars.map { it.third })
        assertEquals(listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"), bars.map { it.second })
        assertEquals(java.time.LocalDate.of(2025, 12, 1), s.earliestListeningMonthStart())

        val month = s.monthListeningHeatmap(today, java.util.Locale.GERMANY, firstWeekday = 2)
        assertEquals(3, month.daysListenedInMonth)
        assertEquals(6601, month.totalSecondsInMonth)
        assertEquals(5, month.rowCount) // Okt. 2026 beginnt Donnerstag → 3 Leerfelder
        assertEquals(4, month.cells.first { it.id == "2026-10-12" }.colorLevel)
    }

    @Test
    fun listeningStatsFractionalStartedAtDropsRecentSessionsLikeIOS() {
        val json = """{"recentSessions":[{"id":"a","startedAt":1.5}],"totalTime":1}"""
        val s = AbsListeningStatsResponse.decodeAPIPayload(json)
        assertEquals(1, s.totalTime)
        assertTrue(s.recentSessions.isEmpty())
    }

    @Test
    fun listeningStatsSnakeCase() {
        val raw = Fixtures.api("listening_stats_snake.json")
        // iOS-Verhalten: der camelCase-Decoder scheitert nicht (alles optional/lenient), daher greift der
        // snake_case-Fallback in `decodeAPIPayload` nie — nur gleichnamige Keys kommen an.
        val viaPayload = AbsListeningStatsResponse.decodeAPIPayload(raw)
        assertEquals(0, viaPayload.totalTime)
        assertEquals(600, viaPayload.today)
        assertEquals(2, viaPayload.days.size)
        assertTrue(viaPayload.dayOfWeek.isEmpty())
        assertTrue(viaPayload.recentSessions.isEmpty())

        // Direkt mit dem snake_case-Decoder (iOS `ABSJSON.decoderListeningStats()`).
        val s = AbsJson.decoderListeningStats.decodeFromString(AbsListeningStatsResponseSerializer, raw)
        assertEquals(7200, s.totalTime)
        assertEquals(mapOf("1" to 6600, "2" to 600), s.dayOfWeek)
        // `convertFromSnakeCase` wandelt auch Dictionary-Keys um (Swift-Verhalten).
        val item = s.items["liSnake1"]!!
        assertEquals("li_snake_1", item.id)
        assertEquals(7200, item.timeListening)
        assertEquals("Cora Snake", item.mediaMetadata!!.authorName)
        assertEquals("li_snake_1", s.recentSessions.single().libraryItemId)
        assertEquals(10.0, s.recentSessions.single().startTime, 0.0)
        assertEquals(1760400000000L, s.recentSessions.single().startedAt)
    }

    @Test
    fun convertFromSnakeCaseMatchesSwift() {
        assertEquals("totalTime", SwiftJson.convertFromSnakeCase("total_time"))
        assertEquals("totalTime", SwiftJson.convertFromSnakeCase("totalTime"))
        assertEquals("_privateKey_", SwiftJson.convertFromSnakeCase("_private_key_"))
        assertEquals("aB", SwiftJson.convertFromSnakeCase("a__b"))
        assertEquals("helloWorld", SwiftJson.convertFromSnakeCase("hello_WORLD"))
        assertEquals("___", SwiftJson.convertFromSnakeCase("___"))
    }

    @Test
    fun listeningSessionsLenientFallback() {
        val p = AbsListeningSessionsPayload.decodeLenient(Fixtures.api("listening_sessions.json"))
        assertEquals(4, p.total)
        assertEquals(1, p.numPages)
        assertEquals(50, p.itemsPerPage)
        assertEquals(listOf("ses_a", "ses_b_broken", "987"), p.sessions.map { it.id })
        p.sessions[0].let {
            assertEquals("li_book_0001", it.libraryItemId)
            assertEquals("book_media_0001", it.bookId)
            assertNull(it.episodeId)
            assertEquals(1219, it.timeListening)
            assertEquals(1760421219000L, it.updatedAt)
        }
        p.sessions[1].let {
            assertEquals(2710.0, it.duration, 0.0) // String → Double im Fallback
            assertEquals(600, it.timeListening) // 600.4 → gerundet
            assertEquals("ep_0042", it.episodeId)
        }
        p.sessions[2].let {
            assertEquals("li_book_0002", it.libraryItemId)
            assertNull(it.bookId) // nur Leerzeichen
            assertEquals(300, it.timeListening)
            assertEquals(1760200000000L, it.startedAt)
            assertEquals(42.0, it.currentTime, 0.0)
        }
    }

    @Test
    fun listeningSessionsStrictPath() {
        val raw = Fixtures.api("listening_sessions_strict.json")
        // Strikter Decoder schafft dieses Dokument → kein Fallback.
        val strict = dec.decodeFromString(AbsListeningSessionsPayloadSerializer, raw)
        assertEquals(strict.sessions.map { it.id }, AbsListeningSessionsPayload.decodeLenient(raw).sessions.map { it.id })
        assertEquals("li_nested_only", strict.sessions[0].libraryItemId)
        assertEquals("4711", strict.sessions[1].id)
        assertEquals("", strict.sessions[1].libraryItemId)
        assertEquals("book_media_9", strict.sessions[1].bookId)
        // Bruch in `timeListening` wirft im strikten Pfad (Swift `decodeIfPresent(Int)`).
        assertThrows(SerializationException::class.java) {
            dec.decodeFromString(AbsListeningSessionSerializer, """{"id":"x","timeListening":1.5}""")
        }
    }

    @Test
    fun recentEpisodes() {
        val r = dec.decodeFromString(AbsRecentEpisodesResponseSerializer, Fixtures.api("recent_episodes.json"))
        assertEquals(3, r.total) // String "3"
        assertEquals(3, r.episodes.size)
        assertEquals(2950.7, r.episodes[0].duration!!, 0.0)
        assertEquals("Episode", r.episodes[1].title)
        assertEquals(1759900000001L, r.episodes[1].publishedAt)
        assertNull(r.episodes[1].podcast!!.metadata!!.title)
        assertEquals("", r.episodes[2].libraryItemId)
        val rows = r.episodes.mapNotNull { AbsPodcastEpisodeListItem.fromDTO(it, libraryId = " lib_pods ") }
        assertEquals(2, rows.size)
        assertEquals("lib_pods", rows[0].libraryId)
        assertEquals("Night Shift Radio", rows[0].showTitle)
        assertEquals("—", rows[1].showTitle)
        assertEquals("—", rows[1].authorLine)
        assertEquals("Stories from the early shift.", absPlainText(r.episodes[0].description))
    }

    @Test
    fun seriesAuthorCollectionDetail() {
        val series = dec.decodeFromString(AbsSeriesDetailSerializer, Fixtures.api("series_detail.json"))
        assertEquals("Coastline", series.name)
        assertNull(series.description)

        val author = dec.decodeFromString(AbsAuthorDetailSerializer, Fixtures.api("author_detail.json"))
        assertEquals("Mara Feldt", author.name)
        assertEquals(2, author.libraryItems!!.size)
        assertTrue(author.libraryItems!![1].isUsableAuthorDetailRow)
        assertEquals("ser_coast", author.series!!.single().id)
        assertEquals(1, author.series!!.single().items!!.size)

        val col = dec.decodeFromString(AbsLibraryCollectionListItemSerializer, Fixtures.api("collection_detail.json"))
        assertEquals("Road Trip", col.name)
        assertEquals(2, col.books!!.size)
        assertEquals(1760000000.0, col.lastUpdate!!, 0.0) // String-Millisekunden → Sekunden
        assertEquals(1700000000.0, col.createdAt!!, 0.0)
    }

    @Test
    fun playSession() {
        val s = dec.decodeFromString(AbsPlaySessionSerializer, Fixtures.api("play_session.json"))
        assertEquals("play_ses_001", s.id)
        assertEquals("ep_0042", s.episodeId)
        assertEquals(1200.5, s.currentTime, 0.0)
        assertEquals("2001", s.audioTracks!!.single().ino)
        assertTrue(s.chapters!!.isEmpty())
        assertEquals("ep_0042", s.libraryItem.media.podcastEpisodes!!.single().id)
        val ui = s.bookForPlayerUI()
        assertEquals("Episode 42: The Long Night", ui.displayTitle)
        assertEquals("Studio Nord", ui.media.metadata.authorName)
        assertEquals(1, ui.media.numTracks)
        assertEquals(2710.0, ui.media.duration!!, 0.0)
        assertEquals("https://feeds.example.org/nightshift", ui.media.metadata.feedUrl)
    }

    @Test
    fun downloadManifestRoundTripWithSortedKeys() {
        val m = AbsDownloadManifest(
            format = 2,
            libraryItemId = "li_pod_0001",
            episodeId = "ep/0042",
            libraryId = "lib_pods",
            displayTitle = "Episode 42",
            displayAuthor = "Studio Nord",
            playSessionId = null,
            savedAtEpoch = 1760430000.5,
            audioFileExtension = "mp3",
            totalDuration = 2710.0,
            tracks = listOf(AbsDownloadManifest.Track(1, 0.0, 2710.0, "ep42.mp3")),
            chapters = listOf(AbsDownloadManifest.Chapter(0, 0.0, 2710.0, "Full")),
        )
        val json = AbsDownloadManifest.encodeToString(m)
        assertTrue(json.startsWith("{\"audioFileExtension\":\"mp3\",\"chapters\":"))
        // Zahlen wie Swift-`JSONEncoder` (`2710`, `0`), siehe auch `DownloadsTest` (Golden-File).
        assertTrue(json.contains("{\"duration\":2710,\"index\":1,\"startOffset\":0,\"title\":\"ep42.mp3\"}"))
        assertEquals(m, dec.decodeFromString(AbsDownloadManifestSerializer, json))
        assertEquals("li_pod_0001-ep_0042", m.offlineStorageItemId)

        // Ältere Manifeste: ISO-`savedAt` statt `savedAtEpoch`.
        val legacy = dec.decodeFromString(
            AbsDownloadManifestSerializer,
            """{"format":1,"libraryItemId":"li","savedAt":"2025-01-01T00:00:00.500Z","tracks":[]}""",
        )
        assertEquals(1735689600.5, legacy.savedAtEpoch, 0.0001)
        val book = AbsBook.fromDownloadManifest(m)
        assertEquals("Episode 42", book.displayTitle)
        assertEquals(1, book.media.numTracks)
        assertEquals("Full", book.media.chapters!!.single().title)
    }

    @Test
    fun storedAccountsPersistenceFormat() {
        val acc = AbsStoredAccount(
            accountKey = AbsStoredAccount.makeKey("Abs.Example.org/", " usr_1 "),
            serverURL = "https://abs.example.org",
            token = "t",
            refreshToken = "r",
            userId = "usr_1",
            username = " ",
            userType = "user",
            booksLibraryId = null,
            podcastsLibraryId = null,
            ebooksLibraryId = null,
            lastUsedAt = 1760000000000,
        )
        assertEquals("https://abs.example.org|usr_1", acc.accountKey)
        assertEquals("Account", acc.displayUsername)
        assertEquals("abs.example.org", acc.displayServerHost)
        val json = AbsStoredAccountsPersistence.encodeAccounts(listOf(acc))
        assertTrue(json.contains("\"lastUsedAt\":1760000000000"))
        assertEquals(listOf(acc), AbsStoredAccountsPersistence.decodeAccounts(json))
        assertTrue(AbsStoredAccountsPersistence.decodeAccounts("not json").isEmpty())
    }

    @Test
    fun plainTextAndLocale() {
        assertEquals("Hello\nWorld\n\nNext", absPlainText("  <p>Hello<BR>World</p>\r\n\r\n\r\n<p>Next</p>  "))
        assertEquals("", absPlainText(null))
        assertEquals("de", absLocale("Deutsch")!!.language)
        assertEquals("pt-BR", absLocale("pt_br")!!.toLanguageTag())
        assertNull(absLocale("  "))
    }

    @Test
    fun feedPreviewParsing() {
        val json = """
        {"podcast":{"metadata":{"title":" My Feed ","author":"Host","descriptionPlain":"","description":"<p>About</p>",
         "categories":["Tech"," "],"explicit":"yes","link":"https://example.org","pubDate":"Mon, 06 Oct 2025 04:00:00 +0000"},
         "episodes":[
          {"title":"B","guid":"g2","duration":"01:02:03","publishedAt":1700000000,"episode":7,"episodeType":"bonus"},
          {"title":"","duration":90,"pubDate":"2025-10-06T04:00:00Z"},
          {"title":"A","guid":"g1","duration":"12:34","publishedAt":1700000000000,"season":"2"}
         ]}}
        """.trimIndent()
        val p = AbsPodcastFeedPreview.fromFeedApiResponse(json)
        assertEquals("My Feed", p.title)
        assertEquals("About", p.descriptionPlain)
        assertEquals(listOf("Tech"), p.categories)
        assertTrue(p.explicit)
        assertEquals(1759723200000L, p.publishedAt)
        assertEquals(listOf("Episode 2", "A", "B"), p.episodes.map { it.title })
        assertEquals("feed-episode-1-Episode 2", p.episodes[0].id)
        assertEquals(3723.0, p.episodes[2].durationSeconds!!, 0.0)
        assertEquals("7", p.episodes[2].episodeNumber)
        assertEquals("Bonus", p.episodes[2].specialTypeLabel)
        assertEquals("S2", p.episodes[1].numberingLabel)
        assertEquals(1700000000000L, p.episodes[2].publishedAt) // Sekunden → Millisekunden
        assertNotNull(p.totalDurationSeconds)
    }
}
