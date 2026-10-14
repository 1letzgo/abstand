package de.letzgo.abstand.store

import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsBookSerializer
import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.AbsPage
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.data.Fixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class LocalStoreTest {
    @get:Rule val tmp = TemporaryFolder()

    // MARK: - AccountCacheDirectory

    @Test
    fun accountDirPathMatchesIosScheme() {
        val base = File("/base")
        val server = "https://abs.example.org"
        // SHA-256("https://abs.example.org") / SHA-256("user-1") wie iOS `CryptoKit.SHA256` (hex, klein).
        val serverHash = sha256Hex(server)
        assertEquals(64, serverHash.length)
        assertEquals(serverHash.lowercase(), serverHash)
        assertEquals(File("/base/accounts/$serverHash"), AccountCacheDirectory.accountDirPath(base, server, null))
        assertEquals(File("/base/accounts/$serverHash"), AccountCacheDirectory.accountDirPath(base, server, "  \n"))
        assertEquals(
            File("/base/accounts/$serverHash/users/${sha256Hex("user-1")}"),
            AccountCacheDirectory.accountDirPath(base, server, " user-1 "),
        )
    }

    @Test
    fun sha256KnownVector() {
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", sha256Hex(""))
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", sha256Hex("abc"))
    }

    @Test
    fun accountDirCreatesAndMemoizes() {
        AccountCacheDirectory.baseDirOverride = tmp.root
        AccountCacheDirectory.resetMemoForTests()
        try {
            val dir = AccountCacheDirectory.accountDir("https://x.test", "u")
            assertTrue(dir.isDirectory)
            assertTrue(dir.path.startsWith(tmp.root.path))
            assertEquals(dir, AccountCacheDirectory.accountDir("https://x.test", "u"))
        } finally {
            AccountCacheDirectory.baseDirOverride = null
            AccountCacheDirectory.resetMemoForTests()
        }
    }

    // MARK: - ActiveLibraryIdsStore

    @Test
    fun activeLibraryIdsRoundTrip() {
        val encoded = ActiveLibraryIdsStore.encode(listOf(" a ", "", "b", "  "))
        assertEquals("[\"a\",\"b\"]", encoded)
        assertEquals(listOf("a", "b"), ActiveLibraryIdsStore.decode(encoded))
        assertEquals(emptyList<String>(), ActiveLibraryIdsStore.decode(null))
        assertEquals(emptyList<String>(), ActiveLibraryIdsStore.decode("not json"))
        assertEquals(listOf("x"), ActiveLibraryIdsStore.decode("[\" x \",\"\"]"))
    }

    // MARK: - Entities

    private fun progress(id: String, ep: String? = null, t: Double = 10.0, last: Long? = 5) = AbsUserMediaProgress(
        mediaProgressServerId = "srv", libraryItemId = id, episodeId = ep, duration = 100.0, progress = 0.1,
        currentTime = t, isFinished = false, lastUpdate = last, ebookProgress = 0.2, ebookLocation = "cfi",
    )

    @Test
    fun localProgressMappingAndDiff() {
        val p = progress("li_1", " ep_1 ")
        val row = LocalProgress.from(p)
        assertEquals("li_1-ep_1", row.progressLookupKey)
        assertEquals(p, row.toAbsUserMediaProgress())
        assertFalse(row.differs(p))
        assertTrue(row.differs(p.copy(currentTime = 11.0)))
        assertTrue(row.differs(p.copy(ebookLocation = null)))
    }

    @Test
    fun compositeKeys() {
        assertEquals("lib|3", LocalCatalogEntry.of("lib", 3, "b").compositeKey)
        assertEquals("lib|series|0", LocalEbookContinueEntry.of("lib", LocalEbookContinueEntry.KIND_SERIES, 0, "b").compositeKey)
        assertEquals("li|", LocalListeningSessionsSnapshot.makeKey(" li ", null))
        assertEquals("li|ep", LocalListeningSessionsSnapshot.makeKey("li", " ep\n"))
    }

    @Test
    fun localBookBlobRoundTripAndFlags() {
        val page = AbsJson.decoder.decodeFromString(AbsPage.serializer(AbsBookSerializer), Fixtures.api("library_items_page_book.json"))
        val book = page.results.first()
        val row = LocalBook.from(book)
        assertEquals(book.id, row.id)
        assertEquals(book.displayTitle, row.title)
        assertEquals(book, row.toAbsBook())
        assertNull(row.toAbsBookDetail())
        val withDetail = row.applyingDetail(book)
        assertEquals(book, withDetail.toAbsBookDetail())
        // eBook-Flags werden beim Update nur ODER-verknüpft.
        val flagged = row.copy(catalogHasEbook = true, catalogHasSupplementaryEbook = true).applying(book)
        assertTrue(flagged.catalogHasEbook)
        assertTrue(flagged.catalogHasSupplementaryEbook)
    }

    @Test
    fun homeShelvesSnapshotRoundTrip() {
        val sections = AbsApiClient.parsePersonalizedStartShelves(Fixtures.api("personalized_shelves.json"))
        assertTrue(sections.isNotEmpty())
        val blob = LocalHomeShelvesSnapshot.encode(sections)
        assertNotNull(blob)
        val restored = LocalHomeShelvesSnapshot("lib", blob!!).toSections()
        assertEquals(sections, restored)
    }

    @Test
    fun listeningSessionsSnapshotRoundTrip() {
        val s = AbsListeningSession("s1", "li", null, "ep", 100.0, 1.0, 50.0, 49, 1000L, 2000L)
        val blob = LocalListeningSessionsSnapshot.encode(listOf(s))!!
        val restored = LocalListeningSessionsSnapshot("li|ep", "li", "ep", 0, blob).toSessions()!!
        assertEquals(1, restored.size)
        val r = restored.first()
        assertEquals("s1", r.id)
        assertEquals("ep", r.episodeId)
        assertEquals(49, r.timeListening)
        assertEquals(2000L, r.updatedAt)
    }

    @Test
    fun stringListConverter() {
        val c = LocalLibraryConverters()
        assertEquals(listOf("a", "b"), c.toStringList(c.fromStringList(listOf("a", "b"))))
        assertEquals(emptyList<String>(), c.toStringList("garbage"))
    }

    // MARK: - Queries (reine Helfer)

    @Test
    fun nextPageMath() {
        assertEquals(0, LocalLibraryQueries.nextPage(0, 80))
        assertEquals(1, LocalLibraryQueries.nextPage(1, 80))
        assertEquals(1, LocalLibraryQueries.nextPage(80, 80))
        assertEquals(2, LocalLibraryQueries.nextPage(81, 80))
    }

    private fun bookRow(id: String, title: String, author: String = "A", addedAt: Long? = null, duration: Double = 0.0) = LocalBook(
        id = id, libraryId = "lib", title = title, authorName = author, addedAt = addedAt, updatedAt = null, duration = duration,
        isUsableLibraryCatalogRow = true, isUsableEbookListRow = false, blob = "",
    )

    @Test
    fun localBookSortHasStableTiebreakers() {
        val rows = listOf(bookRow("3", "B", "X"), bookRow("1", "A", "X"), bookRow("2", "A", "X"), bookRow("4", "C", "W"))
        assertEquals(listOf("1", "2", "3", "4"), LocalLibraryQueries.sortLocalBookRows(rows, "title", false).map { it.id })
        assertEquals(listOf("4", "1", "2", "3"), LocalLibraryQueries.sortLocalBookRows(rows, "authorName", false).map { it.id })
        // Absteigend nur das Primärfeld; Titel/ID bleiben aufsteigend.
        assertEquals(listOf("1", "2", "3", "4"), LocalLibraryQueries.sortLocalBookRows(rows, "authorName", true).map { it.id })
        assertTrue(LocalLibraryQueries.supportsLocalBookSort("duration"))
        assertFalse(LocalLibraryQueries.supportsLocalBookSort("progress"))
    }

    // MARK: - Cover-Cache

    @Test
    fun coverKeysAndFileNames() {
        assertEquals("id", CoverImageCache.cacheKey("id", 0))
        assertEquals("id#cover-hero#r42", CoverImageCache.cacheKey(CoverImageCache.scopeId("id", CoverImageTier.hero), 42))
        assertEquals("id", CoverImageCache.scopeId("id", CoverImageTier.thumbnail))
        assertEquals(sha256Hex("id") + ".img", CoverImageCache.coverFileName("id"))
    }

    @Test
    fun coverDiskCacheAndPrune() {
        val account = tmp.newFolder("acct")
        CoverImageCache.saveToDisk(account, "a", ByteArray(10))
        CoverImageCache.saveToDisk(account, "b", ByteArray(20))
        CoverImageCache.saveToDisk(account, "c", ByteArray(30))
        assertEquals(60L, CoverImageCache.totalByteCount(account))
        val now = System.currentTimeMillis()
        CoverImageCache.fileFor(account, "a").setLastModified(now - 50L * 86_400_000L)
        CoverImageCache.fileFor(account, "b").setLastModified(now - 2_000)
        CoverImageCache.fileFor(account, "c").setLastModified(now - 1_000)
        CoverImageCache.pruneStaleEntries(account, maxAgeDays = 45, maxTotalBytes = 40, now = now)
        assertNull(CoverImageCache.loadFromDisk(account, "a"))
        assertNull(CoverImageCache.loadFromDisk(account, "b"))
        assertEquals(30, CoverImageCache.loadFromDisk(account, "c")!!.size)
    }

    // MARK: - EbookLocalStore

    @Test
    fun ebookLocalStoreFilesAndProgress() {
        val account = tmp.newFolder("acct2")
        EbookLocalStore.updateActiveSession(null, null)
        assertNull(EbookLocalStore.loadProgressFraction("x"))

        EbookLocalStore.updateActiveSession(account, " user ")
        EbookLocalStore.saveProgressFraction(0.5, "item")
        assertEquals(0.5, EbookLocalStore.loadProgressFraction("item")!!, 1e-9)
        assertFalse(EbookLocalStore.isMarkedFinished("item"))
        assertEquals(listOf("item"), EbookLocalStore.inProgressLibraryItemIds())
        assertTrue(File(account, "ebooks/reading/user/item.ebook_fraction.json").exists())

        // „Mark as read“ schützt gegen niedrigere Werte.
        EbookLocalStore.saveProgressFraction(1.0, "item", markFinished = true)
        assertTrue(EbookLocalStore.isMarkedFinished("item"))
        EbookLocalStore.saveProgressFraction(0.2, "item")
        assertEquals(1.0, EbookLocalStore.loadProgressFraction("item")!!, 1e-9)
        EbookLocalStore.clearProgressFraction("item")
        assertNull(EbookLocalStore.loadProgressFraction("item"))

        EbookLocalStore.savePageProgress(current = 0, total = 10, libraryItemId = "item", format = AbsEbookFormat.epub)
        assertEquals(1 to 10, EbookLocalStore.loadPageProgress("item", AbsEbookFormat.epub))

        EbookLocalStore.saveReadiumLocatorJson("{\"href\":\"x\"}", "item", AbsEbookFormat.epub)
        assertEquals("{\"href\":\"x\"}", EbookLocalStore.loadReadiumLocatorJson("item", AbsEbookFormat.epub))
        EbookLocalStore.clearReadiumLocator("item", AbsEbookFormat.epub)
        assertNull(EbookLocalStore.loadReadiumLocatorJson("item", AbsEbookFormat.epub))
        assertNull(EbookLocalStore.loadPageProgress("item", AbsEbookFormat.epub))

        // Datei-Cache + bekannte Formate.
        File(account, "ebooks").mkdirs()
        EbookLocalStore.ebookFile(account, "pdfitem", AbsEbookFormat.pdf).writeBytes(ByteArray(7))
        assertEquals(AbsEbookFormat.pdf, EbookLocalStore.cachedEbookIfPresent(account, "pdfitem")?.second)
        assertEquals(7L, EbookLocalStore.cachedEbookFileByteCount(account, "pdfitem"))
        EbookLocalStore.saveDownloadMeta(account, EbookDownloadMeta("epubitem", "ino1", AbsEbookFormat.epub, "T"))
        assertEquals("ino1", EbookLocalStore.loadDownloadMeta(account, "epubitem", AbsEbookFormat.epub)?.ino)
        EbookLocalStore.syncKnownFormatsFromDisk(account)
        assertEquals(AbsEbookFormat.pdf, EbookLocalStore.knownFormat("pdfitem"))
        assertEquals(AbsEbookFormat.epub, EbookLocalStore.knownFormat("epubitem"))
        EbookLocalStore.updateActiveSession(null, null)
        assertNull(EbookLocalStore.knownFormat("pdfitem"))
    }

    @Test
    fun ebookPageDisplayInfo() {
        assertEquals("3/10", EbookPageDisplayInfo(3, 10).coverLabel)
        assertEquals("10 pages", EbookPageDisplayInfo(null, 10).metadataLabel)
        assertEquals("Page 3 of 10", EbookPageDisplayInfo(3, 10).metadataLabel)
    }

    @Test
    fun staleDownloadTempFilesRemoved() {
        val dir = tmp.newFolder("dl")
        val old = File(dir, "abs-dl-1.part").apply { writeBytes(ByteArray(3)); setLastModified(1_000) }
        val fresh = File(dir, "abs-dl-2.part").apply { writeBytes(ByteArray(3)) }
        val other = File(dir, "track.m4a").apply { writeBytes(ByteArray(3)); setLastModified(1_000) }
        LocalStoreMaintenance.removeStaleDownloadTempFiles(dir)
        assertFalse(old.exists())
        assertTrue(fresh.exists())
        assertTrue(other.exists())
    }
}
