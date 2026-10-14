package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookMedia
import de.letzgo.abstand.data.AbsBookMediaMetadata
import de.letzgo.abstand.data.AbsListeningStatsMetadata
import de.letzgo.abstand.data.AbsListeningStatsRecentSession
import de.letzgo.abstand.data.AbsListeningStatsResponse
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.logic.ListeningAchievementKind
import de.letzgo.abstand.logic.ListeningAchievementState
import de.letzgo.abstand.logic.ListeningAchievementsSnapshot
import de.letzgo.abstand.store.LocalAchievementState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * iOS: Listening-Stats-Teil von `AppModel` (`listeningStats`, `listeningStatsFetchedAt`,
 * `listeningStatsLoading`, `listeningAchievementsSnapshot`, `loadListeningStats`,
 * `prepareListeningAchievementsForStatsTab`, `scheduleListeningAchievementsRebuild`).
 * Cache-first: zuerst der LocalStore-Blob, dann das Netz.
 */
class StatsStore private constructor(private val model: AppModel) : SessionParticipant {
    private val session: SessionStore get() = model.session

    private val _listeningStats = MutableStateFlow<AbsListeningStatsResponse?>(null)
    val listeningStats: StateFlow<AbsListeningStatsResponse?> = _listeningStats.asStateFlow()

    private val _listeningStatsFetchedAt = MutableStateFlow<Long?>(null)
    /** Millisekunden seit 1970. */
    val listeningStatsFetchedAt: StateFlow<Long?> = _listeningStatsFetchedAt.asStateFlow()

    private val _listeningStatsLoading = MutableStateFlow(false)
    val listeningStatsLoading: StateFlow<Boolean> = _listeningStatsLoading.asStateFlow()

    private val _achievements = MutableStateFlow(ListeningAchievementsSnapshot.empty)
    /** iOS: `listeningAchievementsSnapshot`. */
    val achievements: StateFlow<ListeningAchievementsSnapshot> = _achievements.asStateFlow()

    private var rebuildJob: Job? = null

    override fun onSessionCleared(clearCredentials: Boolean) {
        rebuildJob?.cancel()
        _listeningStats.value = null
        _listeningStatsFetchedAt.value = null
        _listeningStatsLoading.value = false
        _achievements.value = ListeningAchievementsSnapshot.empty
    }

    /** iOS: `prepareListeningAchievementsForStatsTab` — leere Platzhalter oder letzter Snapshot. */
    fun prepareListeningAchievementsForStatsTab() {
        rebuildJob?.cancel()
        val store = session.currentLocalLibraryStore() ?: run {
            _achievements.value = ListeningAchievementsSnapshot.empty
            return
        }
        model.scope.launch {
            _achievements.value = StatsLogicExt.snapshotFromLocal(store.fetchAchievementStates()) ?: ListeningAchievementsSnapshot.empty
        }
    }

    /** iOS: `loadListeningStats`. */
    suspend fun loadListeningStats() {
        _listeningStatsLoading.value = true
        try {
            val store = session.currentLocalLibraryStore()
            if (_listeningStats.value == null) restoreFromCache()
            val c = session.client
            if (c == null || !session.isNetworkReachable.value) {
                scheduleListeningAchievementsRebuild()
                return
            }
            // Account vor dem Request festhalten: späte Antwort nach Wechsel verwerfen.
            val epoch = session.accountSessionEpoch.value
            try {
                val (stats, raw) = c.listeningStats()
                if (epoch != session.accountSessionEpoch.value) return
                _listeningStats.value = stats
                _listeningStatsFetchedAt.value = System.currentTimeMillis()
                runCatching { store?.replaceListeningStatsResponse(raw) }
                scheduleListeningAchievementsRebuild()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (_listeningStats.value == null) restoreFromCache()
                if (_listeningStats.value == null) session.publishErrorUnlessBenignCancellation(e) else scheduleListeningAchievementsRebuild()
            }
        } finally {
            _listeningStatsLoading.value = false
        }
    }

    private suspend fun restoreFromCache() {
        val store = session.currentLocalLibraryStore() ?: return
        val cached = runCatching { store.fetchListeningStatsResponse() }.getOrNull() ?: return
        val decoded = runCatching { AbsListeningStatsResponse.decodeAPIPayload(cached.first) }.getOrNull() ?: return
        _listeningStats.value = decoded
        _listeningStatsFetchedAt.value = cached.second
    }

    /** iOS: `scheduleListeningAchievementsRebuild` — Level aus Stats + fertigen Titeln, im Store cachen. */
    private fun scheduleListeningAchievementsRebuild() {
        rebuildJob?.cancel()
        val stats = _listeningStats.value ?: return
        rebuildJob = model.scope.launch {
            val store = session.currentLocalLibraryStore()
            val progress = runCatching { store?.fetchAllProgress() }.getOrNull().orEmpty()
            val (books, episodes) = StatsLogicExt.finishedCounts(progress)
            val snap = ListeningAchievementsSnapshot.make(stats, books, episodes)
            _achievements.value = snap
            runCatching { store?.replaceAchievementsSnapshot(snap.achievements.associate { it.kind.rawValue to it.currentValue }, snap.savedAt) }
        }
    }

    companion object {
        val shared: StatsStore by lazy { StatsStore(AppModel.shared).also { AppModel.shared.register(it) } }
    }
}

/** Reine Stats-Hilfen aus iOS `AppModel` (testbar). */
object StatsLogicExt {
    /** iOS: `listeningAchievementFinishedCounts`. */
    fun finishedCounts(progress: Collection<AbsUserMediaProgress>): Pair<Int, Int> {
        var books = 0
        var episodes = 0
        progress.filter { it.isFinished }.forEach { p -> if (p.episodeId?.trim().isNullOrEmpty()) books++ else episodes++ }
        return books to episodes
    }

    /** iOS: `LocalLibraryQueries.achievementsSnapshot`. */
    fun snapshotFromLocal(states: List<LocalAchievementState>?): ListeningAchievementsSnapshot? {
        if (states.isNullOrEmpty()) return null
        val byKind = states.associateBy { it.kind }
        return ListeningAchievementsSnapshot(
            ListeningAchievementKind.entries.map { ListeningAchievementState(it, byKind[it.rawValue]?.currentValue ?: 0) },
            states.mapNotNull { it.savedAt }.maxOrNull(),
        )
    }

    /** iOS: `normalizedStatsLibraryItemId` — Stats-`items`-Key oder Folgen-ID → `libraryItemId`. */
    fun normalizedStatsLibraryItemId(raw: String): String {
        val t = raw.trim()
        if (t.isEmpty()) return ""
        t.indexOf("/ep/").takeIf { it >= 0 }?.let { return t.substring(0, it).trim() }
        if (t.startsWith("li_")) t.indexOf("-ep_").takeIf { it >= 0 }?.let { return t.substring(0, it).trim() }
        return t
    }

    /** iOS: `bookForStatsNavigation` ohne Katalogtreffer — Stub aus Stats-Metadaten. */
    fun bookForStats(libraryItemId: String, metadata: AbsListeningStatsMetadata?, cached: AbsBook?): AbsBook {
        val id = normalizedStatsLibraryItemId(libraryItemId)
        if (id.isNotEmpty() && cached != null) return cached
        if (id.isNotEmpty() && metadata != null) return metadata.stubBook(id)
        val title = metadata?.displayTitle ?: "—"
        val author = metadata?.displayAuthorLine ?: "—"
        return AbsBook(
            id = id.ifEmpty { UUID.randomUUID().toString() },
            libraryId = null,
            media = AbsBookMedia(
                metadata = AbsBookMediaMetadata.offline(offlineTitle = title, authorLine = author),
                duration = null, numTracks = null, chapters = null, tracks = null,
            ),
            addedAt = null, updatedAt = null,
        )
    }

    /** iOS: `podcastEpisodeForStatsSession` (Stub-Zweig, ohne In-Memory-Katalog). */
    fun podcastEpisodeForStatsSession(session: AbsListeningStatsRecentSession, podcastLibraryId: String?): AbsPodcastEpisodeListItem? {
        if (!session.isPodcastEpisodeSession) return null
        val lid = normalizedStatsLibraryItemId(session.libraryItemId)
        val eid = session.episodeId?.trim().orEmpty()
        if (lid.isEmpty() || eid.isEmpty()) return null
        val author = session.displayAuthor?.trim().orEmpty()
        val showTitle = author.ifEmpty { "—" }
        return AbsPodcastEpisodeListItem(
            libraryItemId = lid,
            libraryId = podcastLibraryId,
            episodeId = eid,
            episodeTitle = session.displayTitle?.trim().orEmpty().ifEmpty { "Episode" },
            showTitle = showTitle,
            authorLine = author.ifEmpty { showTitle },
            duration = 0.0,
            publishedAt = if (session.startedAt > 0) session.startedAt else null,
        )
    }
}
