package de.letzgo.abstand.store

import android.content.Context
import android.util.Log
import androidx.room.Room
import androidx.room.withTransaction
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsItemsInProgressPayload
import de.letzgo.abstand.data.AbsLibrary
import de.letzgo.abstand.data.AbsLibraryAuthorListItem
import de.letzgo.abstand.data.AbsLibraryCollectionListItem
import de.letzgo.abstand.data.AbsLibraryGenreStat
import de.letzgo.abstand.data.AbsLibraryNarratorListItem
import de.letzgo.abstand.data.AbsLibrarySeriesListItem
import de.letzgo.abstand.data.AbsLibraryTagStat
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfSection
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.swiftTrim
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File

/**
 * iOS: `LocalLibraryStore` (`@ModelActor`) — Persistenzschicht für die lokale Server-Kopie eines
 * Accounts. Gleiche Methodennamen wie iOS, alles `suspend` (Room führt die Queries auf seinem
 * eigenen Executor aus). Mehrschrittige Schreibvorgänge laufen als eine Transaktion.
 */
class LocalLibraryStore internal constructor(val database: LocalLibraryDatabase) {
    val dao: LocalLibraryDao = database.dao()

    private suspend fun <T> tx(block: suspend () -> T): T = database.withTransaction { block() }

    /** Beim Öffnen Meta-Eintrag anlegen/aktualisieren — vor allem ein Existenz-/Schreibtest. */
    suspend fun markOpened() {
        try {
            tx {
                val meta = dao.meta() ?: LocalStoreMeta(schemaVersion = 0)
                val updated = backfillEbookCatalogFlagsIfNeeded(meta)
                dao.upsertMeta(updated.copy(lastOpenedAt = System.currentTimeMillis()))
            }
        } catch (e: Exception) {
            // Fehlgeschlagener Schreibtest darf nicht stumm bleiben — Store ist dann faktisch read-only.
            Log.e(TAG, "markOpened failed: ${e.message}")
        }
    }

    /** Einmalig: `catalogHasEbook`/`catalogHasSupplementaryEbook` aus gespeichertem Blob berechnen. */
    private suspend fun backfillEbookCatalogFlagsIfNeeded(meta: LocalStoreMeta): LocalStoreMeta {
        if (meta.schemaVersion >= LocalLibrarySchema.ebookCatalogFlagsMetaVersion) return meta
        val rows = dao.allBookRows().map { row ->
            val book = row.toAbsBook() ?: row.toAbsBookDetail()
            if (book == null) row else row.copy(
                catalogHasEbook = book.matchesBooksEbookCatalogFilter || row.catalogHasEbook,
                catalogHasSupplementaryEbook = book.isCatalogSupplementaryEbook || row.catalogHasSupplementaryEbook,
            )
        }
        if (rows.isNotEmpty()) dao.upsertBookRows(rows)
        return meta.copy(schemaVersion = LocalLibrarySchema.ebookCatalogFlagsMetaVersion)
    }

    // MARK: - Progress

    /** Gleicht alle Progress-Zeilen mit [list] ab: nur geänderte Zeilen schreiben, fehlende löschen. Nur voller Server-Sync. */
    suspend fun replaceAllProgress(list: List<AbsUserMediaProgress>) = tx {
        val existing = dao.allProgress().associateBy { it.progressLookupKey }
        val keep = HashSet<String>()
        val changed = ArrayList<LocalProgress>()
        for (p in list) {
            val key = p.progressLookupKey
            keep.add(key)
            val row = existing[key]
            if (row == null || row.differs(p)) changed.add(LocalProgress.from(p))
        }
        if (changed.isNotEmpty()) dao.upsertProgress(changed)
        val removed = existing.keys.filter { it !in keep }
        if (removed.isNotEmpty()) removed.chunked(900).forEach { dao.deleteProgress(it) }
    }

    /** Einzelne Zeilen per `progressLookupKey` aktualisieren/anlegen — für laufende Wiedergabe (Tick). */
    suspend fun upsertProgress(list: List<AbsUserMediaProgress>) {
        if (list.isEmpty()) return
        tx {
            val changed = list.filter { p -> dao.progress(p.progressLookupKey)?.differs(p) ?: true }.map(LocalProgress::from)
            if (changed.isNotEmpty()) dao.upsertProgress(changed)
        }
    }

    /** Progress-Zeilen löschen, die im aktuellen Server-/Memory-Stand nicht mehr vorkommen. */
    suspend fun pruneProgress(keeping: Set<String>) = tx {
        val removed = dao.allProgress().map { it.progressLookupKey }.filter { it !in keeping }
        removed.chunked(900).forEach { dao.deleteProgress(it) }
    }

    suspend fun fetchAllProgress(): List<AbsUserMediaProgress> = dao.allProgress().map { it.toAbsUserMediaProgress() }

    /** Billiger Existenz-Check (iOS: `FetchDescriptor<LocalProgress>` mit `fetchLimit = 1`). */
    suspend fun hasAnyProgress(): Boolean = dao.progressCount() > 0

    // MARK: - Bookmarks

    /** Komplett-Ersatz aller Lesezeichen. */
    suspend fun replaceAllBookmarks(list: List<AbsAudioBookmark>) = tx {
        dao.deleteAllBookmarks()
        if (list.isNotEmpty()) dao.insertBookmarks(list.map(LocalBookmark::from))
    }

    suspend fun fetchAllBookmarks(): List<AbsAudioBookmark> = dao.allBookmarks().map { it.toAbsAudioBookmark() }

    // MARK: - Browse-Genres / Browse-Tags

    suspend fun replaceGenreStats(libraryId: String, stats: List<AbsLibraryGenreStat>) = tx {
        dao.deleteGenreStats(libraryId)
        dao.insertGenreStats(stats.map { LocalGenreStat.from(libraryId, it) })
    }

    suspend fun replaceTagStats(libraryId: String, stats: List<AbsLibraryTagStat>) = tx {
        dao.deleteTagStats(libraryId)
        dao.insertTagStats(stats.map { LocalTagStat.from(libraryId, it) })
    }

    /** Android-Ergänzung (iOS liest die Tabellen nur über Browse-Restore im AppModel). */
    suspend fun fetchGenreStats(libraryId: String): List<AbsLibraryGenreStat> = dao.genreStats(libraryId).map { it.toStat() }

    suspend fun fetchTagStats(libraryId: String): List<AbsLibraryTagStat> = dao.tagStats(libraryId).map { it.toStat() }

    // MARK: - Browse-Autoren

    /** Reset-Fetch (Seite 0): alte Zeilen der Bibliothek weg, neue Seite mit `sortRank` ab 0. */
    suspend fun replaceAuthorsFirstPage(
        libraryId: String, sortField: String, descending: Boolean, total: Int, items: List<AbsLibraryAuthorListItem>,
    ) = tx {
        dao.deleteAuthors(libraryId)
        dao.insertAuthors(items.mapIndexed { idx, item -> LocalAuthor.from(libraryId, item, idx) })
        dao.upsertAuthorListState(LocalAuthorListState(libraryId, sortField, descending, total))
    }

    /** Folgeseite: an bestehenden `sortRank` anhängen (kein Wipe). */
    suspend fun appendAuthorsPage(libraryId: String, total: Int, items: List<AbsLibraryAuthorListItem>) = tx {
        val existingCount = dao.authorCount(libraryId)
        dao.insertAuthors(items.mapIndexed { idx, item -> LocalAuthor.from(libraryId, item, existingCount + idx) })
        dao.authorListState(libraryId)?.let { dao.upsertAuthorListState(it.copy(total = total)) }
    }

    /** `null`, wenn kein Cache oder die Sortierung von der zuletzt gecachten abweicht. */
    suspend fun fetchAuthors(libraryId: String, sortField: String, descending: Boolean): LocalPagedList<AbsLibraryAuthorListItem>? =
        LocalLibraryQueries.authors(dao, libraryId, sortField, descending)

    // MARK: - Browse-Sprecher

    suspend fun replaceNarrators(libraryId: String, items: List<AbsLibraryNarratorListItem>) = tx {
        dao.deleteNarrators(libraryId)
        dao.insertNarrators(items.map { LocalNarrator.from(libraryId, it) })
    }

    /** Cover-Zuordnung nachträglich befüllen — Name ist der Schlüssel. */
    suspend fun updateNarratorCoverMap(libraryId: String, coverItemIdByName: Map<String, String>) = tx {
        val updated = dao.narrators(libraryId).mapNotNull { row -> coverItemIdByName[row.name]?.let { row.copy(coverItemId = it) } }
        if (updated.isNotEmpty()) dao.upsertNarrators(updated)
    }

    suspend fun fetchNarrators(libraryId: String): LocalNarratorList? {
        val rows = dao.narrators(libraryId)
        if (rows.isEmpty()) return null
        val coverMap = HashMap<String, String>()
        rows.forEach { row -> row.coverItemId?.let { coverMap[row.name] = it } }
        return LocalNarratorList(rows.map { it.toItem() }, coverMap)
    }

    // MARK: - Browse-Serien

    /** Reset-Fetch (Seite 0); eingebettete Bücher wandern per Upsert in die geteilte [LocalBook]-Tabelle. */
    suspend fun replaceSeriesFirstPage(
        libraryId: String, sortField: String, descending: Boolean, total: Int, items: List<AbsLibrarySeriesListItem>,
    ) = tx {
        dao.deleteSeries(libraryId)
        upsertBooksInternal(items.flatMap { it.books ?: emptyList() })
        dao.insertSeries(items.mapIndexed { idx, item -> LocalSeries.from(libraryId, item, idx) })
        dao.upsertSeriesListState(LocalSeriesListState(libraryId, sortField, descending, total))
    }

    /** Folgeseite: an bestehenden `sortRank` anhängen. */
    suspend fun appendSeriesPage(libraryId: String, total: Int, items: List<AbsLibrarySeriesListItem>) = tx {
        val existingCount = dao.seriesCount(libraryId)
        upsertBooksInternal(items.flatMap { it.books ?: emptyList() })
        dao.insertSeries(items.mapIndexed { idx, item -> LocalSeries.from(libraryId, item, existingCount + idx) })
        dao.seriesListState(libraryId)?.let { dao.upsertSeriesListState(it.copy(total = total)) }
    }

    suspend fun fetchSeries(libraryId: String, sortField: String, descending: Boolean): LocalPagedList<AbsLibrarySeriesListItem>? =
        LocalLibraryQueries.series(dao, libraryId, sortField, descending)

    // MARK: - Browse-Sammlungen

    /** Voll-Ersatz (Sammlungen kommen als ein Voll-Fetch). */
    suspend fun replaceCollections(libraryId: String, total: Int, items: List<AbsLibraryCollectionListItem>) = tx {
        dao.deleteCollections(libraryId)
        upsertBooksInternal(items.flatMap { it.books ?: emptyList() })
        dao.insertCollections(items.map { LocalCollection.from(libraryId, it) })
        dao.upsertCollectionListState(LocalCollectionListState(libraryId, total))
    }

    suspend fun fetchCollections(libraryId: String): Pair<List<AbsLibraryCollectionListItem>, Int>? =
        LocalLibraryQueries.collections(dao, libraryId)

    // MARK: - Podcast-Folgen

    /** Voll-Ersatz je Sync-Zyklus. */
    suspend fun replacePodcastEpisodes(
        libraryId: String, total: Int, pagingFromRecentAPI: Boolean, items: List<AbsPodcastEpisodeListItem>,
    ) = tx {
        dao.deletePodcastEpisodes(libraryId)
        dao.insertPodcastEpisodes(items.mapIndexed { idx, item -> LocalPodcastEpisode.from(libraryId, item, idx) })
        dao.upsertPodcastEpisodeListState(LocalPodcastEpisodeListState(libraryId, total, pagingFromRecentAPI))
    }

    suspend fun fetchPodcastEpisodes(libraryId: String): LocalPodcastEpisodeList? = LocalLibraryQueries.podcastEpisodes(dao, libraryId)

    suspend fun fetchPodcastEpisode(progressLookupKey: String): AbsPodcastEpisodeListItem? =
        LocalLibraryQueries.podcastEpisode(dao, progressLookupKey)

    // MARK: - Podcast-Shows

    /** Voll-Ersatz je Fetch — Shows selbst landen in der geteilten [LocalBook]-Tabelle. */
    suspend fun replacePodcastShows(libraryId: String, sortField: String, ascending: Boolean, items: List<AbsBook>) = tx {
        dao.deletePodcastShowEntries(libraryId)
        upsertBooksInternal(items)
        dao.insertPodcastShowEntries(items.mapIndexed { idx, item -> LocalPodcastShowEntry.of(libraryId, idx, item.id) })
        dao.upsertPodcastShowListState(LocalPodcastShowListState(libraryId, sortField, ascending, items.size))
    }

    suspend fun fetchPodcastShows(libraryId: String, sortField: String, ascending: Boolean): List<AbsBook>? =
        LocalLibraryQueries.podcastShows(dao, libraryId, sortField, ascending)

    // MARK: - Bücher

    /** Insert-or-update je `id` — teilt sich [LocalBook] mit allen Domänen, die Bücher referenzieren. */
    suspend fun upsertBooks(items: List<AbsBook>) {
        if (items.isEmpty()) return
        tx { upsertBooksInternal(items) }
    }

    private suspend fun upsertBooksInternal(items: List<AbsBook>) {
        if (items.isEmpty()) return
        val byId = LinkedHashMap<String, LocalBook>()
        LocalLibraryQueries.bookRows(dao, items.map { it.id }).forEach { byId[it.id] = it }
        for (item in items) byId[item.id] = byId[item.id]?.applying(item) ?: LocalBook.from(item)
        dao.upsertBookRows(byId.values.toList())
    }

    /** eBook-Katalog — Flags explizit setzen (rein + supplementär). */
    suspend fun upsertEbookCatalogBooks(pure: List<AbsBook>, supplementary: List<AbsBook>) {
        if (pure.isEmpty() && supplementary.isEmpty()) return
        tx {
            val byId = LinkedHashMap<String, LocalBook>()
            LocalLibraryQueries.bookRows(dao, (pure + supplementary).map { it.id }).forEach { byId[it.id] = it }
            for (item in pure) {
                byId[item.id] = (byId[item.id]?.applying(item) ?: LocalBook.from(item)).copy(catalogHasEbook = true)
            }
            for (item in supplementary) {
                byId[item.id] = (byId[item.id]?.applying(item) ?: LocalBook.from(item))
                    .copy(catalogHasEbook = true, catalogHasSupplementaryEbook = true)
            }
            dao.upsertBookRows(byId.values.toList())
        }
    }

    suspend fun fetchEbookCatalogBooks(libraryId: String): List<AbsBook> = LocalLibraryQueries.ebookCatalogBooks(dao, libraryId)

    suspend fun fetchBook(id: String): AbsBook? = LocalLibraryQueries.book(dao, id)

    /** Entfernt die lokale Buchzeile (Katalog- + Detail-Blob) und Katalog-Einträge nach Server-Löschung. */
    suspend fun deleteBook(id: String) {
        val bid = id.swiftTrim()
        if (bid.isEmpty()) return
        tx {
            dao.deleteBook(bid)
            val touched = dao.catalogEntriesForBook(bid).map { it.libraryId }.toSet()
            dao.deleteCatalogEntriesForBook(bid)
            for (libraryId in touched) {
                dao.catalogListState(libraryId)?.let { dao.upsertCatalogListState(it.copy(total = maxOf(0, it.total - 1))) }
            }
        }
    }

    /** Erweiterte Detail-Antwort separat vom Katalog-Blob sichern — siehe [LocalBook.detailBlob]. */
    suspend fun upsertBookDetail(book: AbsBook) = tx {
        val row = dao.book(book.id) ?: LocalBook.from(book)
        dao.upsertBookRows(listOf(row.applyingDetail(book)))
    }

    suspend fun fetchBookDetail(id: String): AbsBook? = LocalLibraryQueries.bookDetail(dao, id)

    /** Reset-Fetch (Seite 0): alter Reihenfolge-Index weg (Buchzeilen bleiben), neuer Index ab Rang 0. */
    suspend fun replaceCatalogFirstPage(
        libraryId: String, sortField: String, ascending: Boolean, filterKey: String?, total: Int, items: List<AbsBook>,
    ) = tx { replaceCatalogFirstPageInternal(libraryId, sortField, ascending, filterKey, total, items) }

    private suspend fun replaceCatalogFirstPageInternal(
        libraryId: String, sortField: String, ascending: Boolean, filterKey: String?, total: Int, items: List<AbsBook>,
    ) {
        dao.deleteCatalogEntries(libraryId)
        upsertBooksInternal(items)
        dao.insertCatalogEntries(items.mapIndexed { idx, item -> LocalCatalogEntry.of(libraryId, idx, item.id) })
        dao.upsertCatalogListState(LocalCatalogListState(libraryId, sortField, ascending, filterKey, total))
    }

    /**
     * Stiller Hintergrund-Refresh bei unveränderter Filter-/Sort-Kombination: nur die ersten
     * `items.size` Ränge ersetzen, gecachte Folgeseiten bleiben.
     */
    suspend fun refreshCatalogFirstPagePreservingRest(
        libraryId: String, sortField: String, ascending: Boolean, filterKey: String?, total: Int, items: List<AbsBook>,
    ) = tx {
        val state = dao.catalogListState(libraryId)
        if (state == null || state.sortField != sortField || state.ascending != ascending || state.filterKey != filterKey) {
            // Kein passender Cache zum Erhalten — wie ein normaler Reset behandeln.
            replaceCatalogFirstPageInternal(libraryId, sortField, ascending, filterKey, total, items)
        } else {
            upsertBooksInternal(items)
            // REPLACE über den Rang-Key überschreibt bestehende Einträge der ersten Seite.
            dao.insertCatalogEntries(items.mapIndexed { idx, item -> LocalCatalogEntry.of(libraryId, idx, item.id) })
            dao.upsertCatalogListState(state.copy(total = total))
        }
    }

    /** Folgeseite: an bestehenden Reihenfolge-Index anhängen. */
    suspend fun appendCatalogPage(libraryId: String, total: Int, items: List<AbsBook>) = tx {
        val existingCount = dao.catalogEntryCount(libraryId)
        upsertBooksInternal(items)
        dao.insertCatalogEntries(items.mapIndexed { idx, item -> LocalCatalogEntry.of(libraryId, existingCount + idx, item.id) })
        dao.catalogListState(libraryId)?.let { dao.upsertCatalogListState(it.copy(total = total)) }
    }

    /** `null`, wenn kein Cache oder Filter/Sortierung abweichen. [pageLimit] nur zur Herleitung von `nextPage`. */
    suspend fun fetchCatalog(
        libraryId: String, sortField: String, ascending: Boolean, filterKey: String?, pageLimit: Int,
    ): LocalPagedList<AbsBook>? = LocalLibraryQueries.catalog(dao, libraryId, sortField, ascending, filterKey, pageLimit)

    /** Voller lokaler Katalog (Superset), client-seitig sortiert. */
    suspend fun fetchAllBooks(libraryId: String, sortField: String, descending: Boolean): List<AbsBook> =
        LocalLibraryQueries.allBooks(dao, libraryId, sortField, descending)

    // MARK: - Home-Regale

    /** Voll-Ersatz je Bibliothek — spiegelt `startShelves` zum Persistierzeitpunkt. */
    suspend fun replaceHomeShelves(libraryId: String, sections: List<AbsStartShelfSection>) = tx {
        upsertBooksInternal(sections.flatMap { it.books })
        val blob = LocalHomeShelvesSnapshot.encode(sections)
        if (blob != null) dao.upsertHomeShelves(LocalHomeShelvesSnapshot(libraryId, blob))
    }

    suspend fun fetchHomeShelves(libraryId: String): List<AbsStartShelfSection>? = LocalLibraryQueries.homeShelves(dao, libraryId)

    suspend fun fetchItemsInProgressPayload(limit: Int): AbsItemsInProgressPayload? = LocalLibraryQueries.itemsInProgressPayload(dao, limit)

    // MARK: - eBook-Continue-Regale

    suspend fun replaceEbookContinueEntries(libraryId: String, reading: List<AbsBook>, series: List<AbsBook>) = tx {
        dao.deleteEbookContinueEntries(libraryId)
        upsertBooksInternal(reading + series)
        val rows = reading.mapIndexed { idx, b -> LocalEbookContinueEntry.of(libraryId, LocalEbookContinueEntry.KIND_READING, idx, b.id) } +
            series.mapIndexed { idx, b -> LocalEbookContinueEntry.of(libraryId, LocalEbookContinueEntry.KIND_SERIES, idx, b.id) }
        dao.insertEbookContinueEntries(rows)
    }

    suspend fun fetchEbookContinueEntries(libraryId: String): LocalEbookContinueShelves? =
        LocalLibraryQueries.ebookContinueEntries(dao, libraryId)

    // MARK: - Listening-Stats + Achievements

    /** Voll-Ersatz (ein Datensatz pro Store). */
    suspend fun replaceListeningStatsResponse(rawData: String) =
        dao.upsertListeningStats(LocalListeningStatsSnapshot(fetchedAt = System.currentTimeMillis(), blob = rawData))

    /** Rohdaten + Abrufzeit (ms). */
    suspend fun fetchListeningStatsResponse(): Pair<String, Long>? = dao.listeningStats()?.let { it.blob to it.fetchedAt }

    /** Upsert je Achievement-Kind (iOS: `replaceAchievementsSnapshot`; Kind als `rawValue`-String). */
    suspend fun replaceAchievementsSnapshot(valuesByKind: Map<String, Int>, savedAt: Long?) {
        if (valuesByKind.isEmpty()) return
        dao.upsertAchievementStates(valuesByKind.map { (kind, value) -> LocalAchievementState(kind, value, savedAt) })
    }

    suspend fun fetchAchievementStates(): List<LocalAchievementState>? = LocalLibraryQueries.achievementStates(dao)

    // MARK: - Libraries / Author-Detail / Listening-Sessions / Podcast-RSS

    /** Voll-Ersatz der Account-Bibliotheksliste — Local-DB-First für den Library-Picker. */
    suspend fun replaceLibraries(libraries: List<AbsLibrary>) {
        val blob = LocalLibrariesSnapshot.encode(libraries) ?: return
        dao.upsertLibrariesSnapshot(LocalLibrariesSnapshot(fetchedAt = System.currentTimeMillis(), blob = blob))
    }

    suspend fun fetchLibraries(): List<AbsLibrary>? = LocalLibraryQueries.libraries(dao)

    /** Upsert der Autor-Bio — getrennt von Browse-[LocalAuthor]. */
    suspend fun upsertAuthorDetail(authorId: String, libraryId: String, description: String?) {
        val aid = authorId.swiftTrim()
        if (aid.isEmpty()) return
        val value = description?.swiftTrim()?.ifEmpty { null }
        dao.upsertAuthorDetail(LocalAuthorDetail(aid, libraryId.swiftTrim(), value))
    }

    suspend fun fetchAuthorDescription(authorId: String): String? = LocalLibraryQueries.authorDescription(dao, authorId)

    /** Voll-Ersatz der Hör-Sitzungen für ein Medium (Buch oder Podcast-Folge). */
    suspend fun replaceListeningSessions(libraryItemId: String, episodeId: String?, sessions: List<AbsListeningSession>) {
        val lid = libraryItemId.swiftTrim()
        if (lid.isEmpty()) return
        val blob = LocalListeningSessionsSnapshot.encode(sessions) ?: return
        dao.upsertListeningSessions(
            LocalListeningSessionsSnapshot(
                compositeKey = LocalListeningSessionsSnapshot.makeKey(lid, episodeId),
                libraryItemId = lid,
                episodeId = (episodeId ?: "").swiftTrim(),
                fetchedAt = System.currentTimeMillis(),
                blob = blob,
            ),
        )
    }

    suspend fun fetchListeningSessions(libraryItemId: String, episodeId: String?): List<AbsListeningSession>? =
        LocalLibraryQueries.listeningSessions(dao, libraryItemId, episodeId)

    /** Roh-RSS-Feed je Sendung speichern (wird beim Lesen erneut geparst). */
    suspend fun replacePodcastRssFeed(showId: String, rawFeedData: ByteArray) {
        val sid = showId.swiftTrim()
        if (sid.isEmpty()) return
        dao.upsertPodcastRssFeed(LocalPodcastRssFeedSnapshot(sid, System.currentTimeMillis(), rawFeedData))
    }

    suspend fun fetchPodcastRssFeedRaw(showId: String): ByteArray? = LocalLibraryQueries.podcastRssFeedRaw(dao, showId)

    suspend fun deletePodcastRssFeed(showId: String) {
        val sid = showId.swiftTrim()
        if (sid.isEmpty()) return
        dao.deletePodcastRssFeed(sid)
    }

    private companion object {
        const val TAG = "LocalLibraryStore"
    }
}

/**
 * iOS: `LocalLibraryStoreManager` — öffnet/wechselt die Room-Datenbank je Account. Pfadschema wie
 * [AccountCacheDirectory], aber eigene Wurzel `filesDir/ABStandLocalStore/accounts/<sha>/users/<sha>/`.
 * Es ist immer nur der Store des aktiven Accounts offen.
 */
object LocalLibraryStoreManager {
    const val ROOT_DIR_NAME = "ABStandLocalStore"

    /** iOS: `LocalLibrary.v2.store` — Room-Datei gleichen Namens (+ `-wal`/`-shm`). */
    const val STORE_FILE_NAME = "LocalLibrary.v2.store"

    private val lock = Any()
    private var openedFile: File? = null
    private var openedStore: LocalLibraryStore? = null
    private var didScheduleOtherStoreMaintenance = false
    private val maintenanceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val context: Context get() = Prefs.appContext

    private val baseDir: File get() = File(context.filesDir, ROOT_DIR_NAME)

    /** Account-Verzeichnis für den Store — getrennt pro Server-URL (+ optional User-ID). */
    fun accountStoreDirectory(serverURL: String, userId: String?): File =
        AccountCacheDirectory.accountDirPath(baseDir, serverURL, userId).also { it.mkdirs() }

    /**
     * Liefert den Store für den Account — öffnet/wechselt bei Bedarf. `null` vor Login bzw. solange
     * eine Hintergrund-Verkleinerung läuft (Bootstrap fällt dann auf das Netzwerk zurück).
     * Room öffnet die Datei erst beim ersten Query — der Aufruf selbst macht keine Platten-I/O außer `mkdirs`.
     */
    fun store(serverURL: String, userId: String?): LocalLibraryStore? {
        val normalized = AbsApiClient.normalizeServerURL(serverURL) ?: return null
        val file = File(accountStoreDirectory(normalized, userId), STORE_FILE_NAME)
        synchronized(lock) {
            if (file == openedFile) openedStore?.let { return it }
            if (LocalStoreMaintenance.compactInBackgroundIfOversized(file)) return null
            openedStore?.database?.close()
            val db = Room.databaseBuilder(context, LocalLibraryDatabase::class.java, file.absolutePath)
                // Kaputter/unbekannter Stand: neu anlegen — reiner Server-Spiegel (iOS: Store-Dateien löschen).
                .fallbackToDestructiveMigration()
                .build()
            val store = LocalLibraryStore(db)
            openedFile = file
            openedStore = store
            scheduleMaintenanceOfOtherStoresOnce(file)
            return store
        }
    }

    /** Aktiven Store schließen (Logout ohne Folge-Account). */
    fun closeActiveStore() = synchronized(lock) {
        openedStore?.database?.close()
        openedStore = null
        openedFile = null
    }

    /** Einmal je Start: aufgeblähte Stores anderer Accounts/alter Server-URLs entfernen. */
    private fun scheduleMaintenanceOfOtherStoresOnce(active: File) {
        if (didScheduleOtherStoreMaintenance) return
        didScheduleOtherStoreMaintenance = true
        val accounts = File(baseDir, "accounts")
        maintenanceScope.launch { LocalStoreMaintenance.discardOversizedOtherStores(accounts, active) }
    }
}
