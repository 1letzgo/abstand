package de.letzgo.abstand.store

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.Upsert

/**
 * Rohzugriffe auf die Room-Tabellen (iOS: `FetchDescriptor`/`#Predicate` auf dem `ModelContext`).
 * Domänenlogik (Upsert-Regeln, Ränge, Listen-Zustände) liegt in [LocalLibraryStore] und
 * [LocalLibraryQueries]; hier nur einfache, einzeln lesbare SQL-Aufrufe.
 */
@Dao
interface LocalLibraryDao {
    // MARK: - Meta
    @Query("SELECT * FROM LocalStoreMeta LIMIT 1") suspend fun meta(): LocalStoreMeta?
    @Upsert suspend fun upsertMeta(meta: LocalStoreMeta)

    // MARK: - Progress
    @Query("SELECT * FROM LocalProgress") suspend fun allProgress(): List<LocalProgress>
    @Query("SELECT * FROM LocalProgress WHERE progressLookupKey = :key LIMIT 1") suspend fun progress(key: String): LocalProgress?
    @Query("SELECT * FROM LocalProgress ORDER BY lastUpdate DESC LIMIT :limit") suspend fun recentProgress(limit: Int): List<LocalProgress>
    @Query("SELECT COUNT(*) FROM LocalProgress") suspend fun progressCount(): Int
    @Upsert suspend fun upsertProgress(rows: List<LocalProgress>)
    @Query("DELETE FROM LocalProgress WHERE progressLookupKey IN (:keys)") suspend fun deleteProgress(keys: List<String>)

    // MARK: - Bookmarks
    @Query("SELECT * FROM LocalBookmark") suspend fun allBookmarks(): List<LocalBookmark>
    @Query("DELETE FROM LocalBookmark") suspend fun deleteAllBookmarks()
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertBookmarks(rows: List<LocalBookmark>)

    // MARK: - Genres / Tags
    @Query("DELETE FROM LocalGenreStat WHERE libraryId = :libraryId") suspend fun deleteGenreStats(libraryId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertGenreStats(rows: List<LocalGenreStat>)
    @Query("SELECT * FROM LocalGenreStat WHERE libraryId = :libraryId") suspend fun genreStats(libraryId: String): List<LocalGenreStat>
    @Query("DELETE FROM LocalTagStat WHERE libraryId = :libraryId") suspend fun deleteTagStats(libraryId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertTagStats(rows: List<LocalTagStat>)
    @Query("SELECT * FROM LocalTagStat WHERE libraryId = :libraryId") suspend fun tagStats(libraryId: String): List<LocalTagStat>

    // MARK: - Autoren
    @Query("DELETE FROM LocalAuthor WHERE libraryId = :libraryId") suspend fun deleteAuthors(libraryId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertAuthors(rows: List<LocalAuthor>)
    @Query("SELECT COUNT(*) FROM LocalAuthor WHERE libraryId = :libraryId") suspend fun authorCount(libraryId: String): Int
    @Query("SELECT * FROM LocalAuthor WHERE libraryId = :libraryId ORDER BY sortRank") suspend fun authors(libraryId: String): List<LocalAuthor>
    @Query("SELECT * FROM LocalAuthorListState WHERE libraryId = :libraryId LIMIT 1") suspend fun authorListState(libraryId: String): LocalAuthorListState?
    @Upsert suspend fun upsertAuthorListState(state: LocalAuthorListState)
    @Query("SELECT * FROM LocalAuthorDetail WHERE id = :id LIMIT 1") suspend fun authorDetail(id: String): LocalAuthorDetail?
    @Upsert suspend fun upsertAuthorDetail(row: LocalAuthorDetail)

    // MARK: - Sprecher
    @Query("DELETE FROM LocalNarrator WHERE libraryId = :libraryId") suspend fun deleteNarrators(libraryId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertNarrators(rows: List<LocalNarrator>)
    @Query("SELECT * FROM LocalNarrator WHERE libraryId = :libraryId") suspend fun narrators(libraryId: String): List<LocalNarrator>
    @Upsert suspend fun upsertNarrators(rows: List<LocalNarrator>)

    // MARK: - Bücher
    @Query("SELECT * FROM LocalBook WHERE id IN (:ids)") suspend fun books(ids: List<String>): List<LocalBook>
    @Query("SELECT * FROM LocalBook WHERE id = :id LIMIT 1") suspend fun book(id: String): LocalBook?
    @Query("SELECT * FROM LocalBook") suspend fun allBookRows(): List<LocalBook>
    @Query("SELECT * FROM LocalBook WHERE libraryId = :libraryId") suspend fun booksInLibrary(libraryId: String): List<LocalBook>
    @Query(
        "SELECT * FROM LocalBook WHERE libraryId = :libraryId AND catalogHasEbook = 1 AND catalogHasSupplementaryEbook = 0 ORDER BY title",
    )
    suspend fun pureEbookRows(libraryId: String): List<LocalBook>
    @Query("SELECT * FROM LocalBook WHERE libraryId = :libraryId AND catalogHasSupplementaryEbook = 1 ORDER BY title")
    suspend fun supplementaryEbookRows(libraryId: String): List<LocalBook>
    @Upsert suspend fun upsertBookRows(rows: List<LocalBook>)
    @Query("DELETE FROM LocalBook WHERE id = :id") suspend fun deleteBook(id: String)

    // MARK: - Katalog
    @Query("SELECT * FROM LocalCatalogListState WHERE libraryId = :libraryId LIMIT 1") suspend fun catalogListState(libraryId: String): LocalCatalogListState?
    @Upsert suspend fun upsertCatalogListState(state: LocalCatalogListState)
    @Query("DELETE FROM LocalCatalogEntry WHERE libraryId = :libraryId") suspend fun deleteCatalogEntries(libraryId: String)
    @Query("DELETE FROM LocalCatalogEntry WHERE bookId = :bookId") suspend fun deleteCatalogEntriesForBook(bookId: String)
    @Query("SELECT * FROM LocalCatalogEntry WHERE bookId = :bookId") suspend fun catalogEntriesForBook(bookId: String): List<LocalCatalogEntry>
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertCatalogEntries(rows: List<LocalCatalogEntry>)
    @Query("SELECT COUNT(*) FROM LocalCatalogEntry WHERE libraryId = :libraryId") suspend fun catalogEntryCount(libraryId: String): Int
    @Query("SELECT * FROM LocalCatalogEntry WHERE libraryId = :libraryId ORDER BY rank") suspend fun catalogEntries(libraryId: String): List<LocalCatalogEntry>

    // MARK: - Serien
    @Query("DELETE FROM LocalSeries WHERE libraryId = :libraryId") suspend fun deleteSeries(libraryId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertSeries(rows: List<LocalSeries>)
    @Query("SELECT COUNT(*) FROM LocalSeries WHERE libraryId = :libraryId") suspend fun seriesCount(libraryId: String): Int
    @Query("SELECT * FROM LocalSeries WHERE libraryId = :libraryId ORDER BY sortRank") suspend fun series(libraryId: String): List<LocalSeries>
    @Query("SELECT * FROM LocalSeriesListState WHERE libraryId = :libraryId LIMIT 1") suspend fun seriesListState(libraryId: String): LocalSeriesListState?
    @Upsert suspend fun upsertSeriesListState(state: LocalSeriesListState)

    // MARK: - Sammlungen
    @Query("DELETE FROM LocalCollection WHERE libraryId = :libraryId") suspend fun deleteCollections(libraryId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertCollections(rows: List<LocalCollection>)
    @Query("SELECT * FROM LocalCollection WHERE libraryId = :libraryId") suspend fun collections(libraryId: String): List<LocalCollection>
    @Query("SELECT * FROM LocalCollectionListState WHERE libraryId = :libraryId LIMIT 1") suspend fun collectionListState(libraryId: String): LocalCollectionListState?
    @Upsert suspend fun upsertCollectionListState(state: LocalCollectionListState)

    // MARK: - Podcast-Folgen
    @Query("DELETE FROM LocalPodcastEpisode WHERE libraryId = :libraryId") suspend fun deletePodcastEpisodes(libraryId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertPodcastEpisodes(rows: List<LocalPodcastEpisode>)
    @Query("SELECT * FROM LocalPodcastEpisode WHERE libraryId = :libraryId ORDER BY rank") suspend fun podcastEpisodes(libraryId: String): List<LocalPodcastEpisode>
    @Query("SELECT * FROM LocalPodcastEpisode WHERE progressLookupKey = :key LIMIT 1") suspend fun podcastEpisode(key: String): LocalPodcastEpisode?
    @Query("SELECT * FROM LocalPodcastEpisode WHERE progressLookupKey IN (:keys)") suspend fun podcastEpisodes(keys: List<String>): List<LocalPodcastEpisode>
    @Query("SELECT * FROM LocalPodcastEpisodeListState WHERE libraryId = :libraryId LIMIT 1")
    suspend fun podcastEpisodeListState(libraryId: String): LocalPodcastEpisodeListState?
    @Upsert suspend fun upsertPodcastEpisodeListState(state: LocalPodcastEpisodeListState)

    // MARK: - Podcast-Shows
    @Query("DELETE FROM LocalPodcastShowEntry WHERE libraryId = :libraryId") suspend fun deletePodcastShowEntries(libraryId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertPodcastShowEntries(rows: List<LocalPodcastShowEntry>)
    @Query("SELECT * FROM LocalPodcastShowEntry WHERE libraryId = :libraryId ORDER BY rank") suspend fun podcastShowEntries(libraryId: String): List<LocalPodcastShowEntry>
    @Query("SELECT * FROM LocalPodcastShowListState WHERE libraryId = :libraryId LIMIT 1")
    suspend fun podcastShowListState(libraryId: String): LocalPodcastShowListState?
    @Upsert suspend fun upsertPodcastShowListState(state: LocalPodcastShowListState)

    // MARK: - Home-Regale / eBook-Continue
    @Query("SELECT * FROM LocalHomeShelvesSnapshot WHERE libraryId = :libraryId LIMIT 1") suspend fun homeShelves(libraryId: String): LocalHomeShelvesSnapshot?
    @Upsert suspend fun upsertHomeShelves(row: LocalHomeShelvesSnapshot)
    @Query("DELETE FROM LocalEbookContinueEntry WHERE libraryId = :libraryId") suspend fun deleteEbookContinueEntries(libraryId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertEbookContinueEntries(rows: List<LocalEbookContinueEntry>)
    @Query("SELECT * FROM LocalEbookContinueEntry WHERE libraryId = :libraryId ORDER BY rank") suspend fun ebookContinueEntries(libraryId: String): List<LocalEbookContinueEntry>

    // MARK: - Stats / Achievements
    @Query("SELECT * FROM LocalListeningStatsSnapshot LIMIT 1") suspend fun listeningStats(): LocalListeningStatsSnapshot?
    @Upsert suspend fun upsertListeningStats(row: LocalListeningStatsSnapshot)
    @Query("SELECT * FROM LocalAchievementState") suspend fun achievementStates(): List<LocalAchievementState>
    @Upsert suspend fun upsertAchievementStates(rows: List<LocalAchievementState>)

    // MARK: - Libraries / Sessions / RSS
    @Query("SELECT * FROM LocalLibrariesSnapshot LIMIT 1") suspend fun librariesSnapshot(): LocalLibrariesSnapshot?
    @Upsert suspend fun upsertLibrariesSnapshot(row: LocalLibrariesSnapshot)
    @Query("SELECT * FROM LocalListeningSessionsSnapshot WHERE compositeKey = :key LIMIT 1")
    suspend fun listeningSessions(key: String): LocalListeningSessionsSnapshot?
    @Upsert suspend fun upsertListeningSessions(row: LocalListeningSessionsSnapshot)
    @Query("SELECT * FROM LocalPodcastRssFeedSnapshot WHERE showId = :showId LIMIT 1") suspend fun podcastRssFeed(showId: String): LocalPodcastRssFeedSnapshot?
    @Upsert suspend fun upsertPodcastRssFeed(row: LocalPodcastRssFeedSnapshot)
    @Query("DELETE FROM LocalPodcastRssFeedSnapshot WHERE showId = :showId") suspend fun deletePodcastRssFeed(showId: String)
}

/** iOS: `LocalLibrarySchema.current` (`ModelContainer`) — eine Room-Datenbank pro Account. */
@Database(
    entities = [
        LocalStoreMeta::class, LocalProgress::class, LocalBookmark::class,
        LocalGenreStat::class, LocalTagStat::class,
        LocalAuthorListState::class, LocalAuthor::class, LocalAuthorDetail::class, LocalNarrator::class,
        LocalBook::class, LocalCatalogListState::class, LocalCatalogEntry::class,
        LocalSeriesListState::class, LocalSeries::class,
        LocalCollectionListState::class, LocalCollection::class,
        LocalPodcastEpisodeListState::class, LocalPodcastEpisode::class,
        LocalPodcastShowListState::class, LocalPodcastShowEntry::class,
        LocalHomeShelvesSnapshot::class, LocalEbookContinueEntry::class,
        LocalListeningStatsSnapshot::class, LocalAchievementState::class,
        LocalLibrariesSnapshot::class, LocalListeningSessionsSnapshot::class, LocalPodcastRssFeedSnapshot::class,
    ],
    version = LocalLibrarySchema.ROOM_VERSION,
    exportSchema = true,
)
@TypeConverters(LocalLibraryConverters::class)
abstract class LocalLibraryDatabase : RoomDatabase() {
    abstract fun dao(): LocalLibraryDao
}
