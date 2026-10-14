package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsAdminMediaProgressRow
import de.letzgo.abstand.data.AbsAdminUserDetail
import de.letzgo.abstand.data.AbsAdminUserSummary
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsApiError
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookSerializer
import de.letzgo.abstand.data.AbsJson
import de.letzgo.abstand.data.AbsLibraryDetailEnvelope
import de.letzgo.abstand.data.AbsLibraryEpisodeDownloadsPayload
import de.letzgo.abstand.data.AbsLibraryStatsResponse
import de.letzgo.abstand.data.AbsListeningSessionsPayload
import de.letzgo.abstand.data.AbstandErrorFilter
import de.letzgo.abstand.data.AdminSocketClient
import de.letzgo.abstand.data.AdminSocketEvent
import de.letzgo.abstand.data.M4BEncodeProgressStore
import de.letzgo.abstand.data.Prefs
import de.letzgo.abstand.data.ServerM4BEncodeJob
import de.letzgo.abstand.data.ServerM4BEncodeJobSerializer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer

/**
 * Server-Admin-Teil von iOS `AppModel` (Users, Bibliotheks-Stats, Scan, M4B-Encode inkl.
 * Admin-Socket und Polling, Media-Cache-Purge, Passwort ändern). Lazy-Singleton [shared], meldet
 * sich selbst als [SessionParticipant] an.
 */
class AdminStore private constructor(private val model: AppModel) : SessionParticipant {
    private val session: SessionStore get() = model.session

    private val _m4bEncodeJobs = MutableStateFlow<List<ServerM4BEncodeJob>>(emptyList())
    /** iOS: `m4bEncodeJobs`. */
    val m4bEncodeJobs: StateFlow<List<ServerM4BEncodeJob>> = _m4bEncodeJobs.asStateFlow()

    /** iOS: `m4bEncodeProgressStore`. */
    val m4bEncodeProgressStore = M4BEncodeProgressStore()

    private val m4bAdminSocket = AdminSocketClient().also { socket ->
        socket.onEvent = { handleM4BSocketEvent(it) }
        socket.tokenProvider = { session.client?.currentToken().orEmpty() }
    }
    private var m4bEncodePollJob: Job? = null
    private var loadedJobsKey: String? = null

    private val isAdminOrRoot: Boolean get() = session.isServerAdmin.value || session.isServerRoot.value
    private val client: AbsApiClient? get() = session.client

    // MARK: - SessionParticipant

    override fun onSessionActivated() = loadM4BEncodeJobs()

    override fun onSessionCleared(clearCredentials: Boolean) {
        m4bEncodePollJob?.cancel()
        m4bEncodePollJob = null
        m4bAdminSocket.disconnect()
        _m4bEncodeJobs.value = emptyList()
        m4bEncodeProgressStore.clearAll()
        loadedJobsKey = null
    }

    override fun onTokensRefreshed(accessToken: String, refreshToken: String) {
        // Token rotiert: der Socket holt sich beim nächsten Reconnect das neue über `tokenProvider`.
    }

    // MARK: - Users

    suspend fun fetchServerUsers(): List<AbsAdminUserSummary> {
        val c = client
        if (!session.isServerRoot.value || c == null) return emptyList()
        return c.serverUsers()
    }

    suspend fun fetchServerOnlineUserIds(): Set<String> {
        val c = client
        if (!session.isServerRoot.value || c == null) return emptySet()
        return c.serverOnlineUserIds()
    }

    /** iOS: `fetchServerUserDetail` inkl. Nachladen fehlender Titel/Autoren (lokal, sonst Item-API). */
    suspend fun fetchServerUserDetail(userId: String): AbsAdminUserDetail {
        val c = client
        if (!session.isServerRoot.value || c == null) throw AbsApiError.HttpStatus(0, "Not available")
        val detail = AbsAdminUserDetail.decode(c.serverUserDetailData(userId))
        return detail.copy(mediaProgress = enrichAdminMediaProgressRows(detail.mediaProgress, c))
    }

    suspend fun fetchServerUserListeningSessions(userId: String): AbsListeningSessionsPayload {
        val c = client
        if (!session.isServerRoot.value || c == null) return AbsListeningSessionsPayload(0, 0, 0, 0, emptyList())
        return c.serverUserListeningSessions(userId)
    }

    private suspend fun enrichAdminMediaProgressRows(rows: List<AbsAdminMediaProgressRow>, c: AbsApiClient): List<AbsAdminMediaProgressRow> {
        if (rows.isEmpty()) return rows
        val store = session.currentLocalLibraryStore()
        val done = mutableListOf<AbsAdminMediaProgressRow>()
        val pending = mutableListOf<AbsAdminMediaProgressRow>()
        for (row in rows) {
            var working = row
            if (!working.hasPodcastEpisodeId && working.needsDisplayMetadataEnrichment) {
                store?.fetchBook(row.libraryItemId)?.let { book ->
                    working = mergeRow(working, book.displayTitle, book.displayAuthorsCardLine)
                }
            }
            if (working.needsEpisodeTitleResolution || working.needsDisplayMetadataEnrichment) pending += working else done += working
        }
        if (pending.isNotEmpty() && session.isNetworkReachable.value) {
            done += coroutineScope { pending.map { async { fetchAdminProgressRowMetadata(it, c) } }.awaitAll() }
        } else {
            done += pending
        }
        return done.sortedByDescending { it.lastUpdate ?: 0L }
    }

    private fun mergeRow(row: AbsAdminMediaProgressRow, title: String, author: String): AbsAdminMediaProgressRow {
        if (row.needsEpisodeTitleResolution) {
            val t = title.trim()
            val useTitle = t.isNotEmpty() && t != "—"
            return row.replacingDisplayMetadata(
                title = if (useTitle) t else null,
                author = if (row.needsAuthorEnrichment || useTitle) author else null,
            )
        }
        return row.withDisplayMetadata(
            title = if (row.needsTitleEnrichment) title else row.resolvedDisplayTitle,
            author = if (row.needsAuthorEnrichment) author else row.resolvedDisplayAuthor,
        )
    }

    private suspend fun fetchAdminProgressRowMetadata(row: AbsAdminMediaProgressRow, c: AbsApiClient): AbsAdminMediaProgressRow = try {
        val data = c.itemResponseData(row.libraryItemId, expanded = true)
        val eid = row.episodeId?.trim().orEmpty()
        val item = runCatching { AbsJson.decoder.decodeFromString(AbsBookSerializer, data) }.getOrNull()
        if (eid.isNotEmpty()) {
            val ep = AbsAdminMediaProgressRow.episodeMetadata(data, eid)
            when {
                ep != null -> row.replacingDisplayMetadata(ep.first, ep.second)
                item != null -> {
                    val match = item.media.podcastEpisodes?.firstOrNull { it.id == eid || eid.endsWith(it.id) || it.id.endsWith(eid) }
                    val show = item.displayTitle.trim()
                    if (match != null) row.replacingDisplayMetadata(match.title, show.ifEmpty { null })
                    else row.replacingDisplayMetadata(null, item.displayTitle)
                }
                else -> row
            }
        } else if (item != null) {
            mergeRow(row, item.displayTitle, item.displayAuthorsCardLine)
        } else row
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        row
    }

    // MARK: - Libraries

    suspend fun fetchServerLibraryStats(libraryId: String): AbsLibraryStatsResponse {
        val c = client
        if (!session.isServerRoot.value || c == null) throw AbsApiError.HttpStatus(0, "Not available")
        return c.serverLibraryStats(libraryId)
    }

    suspend fun fetchServerLibraryDetail(libraryId: String): AbsLibraryDetailEnvelope {
        val c = client
        if (!session.isServerRoot.value || c == null) throw AbsApiError.HttpStatus(0, "Not available")
        return c.libraryDetail(libraryId, includeFilterData = true)
    }

    suspend fun fetchServerLibraryEpisodeDownloads(libraryId: String): AbsLibraryEpisodeDownloadsPayload {
        val c = client
        if (!session.isServerRoot.value || c == null) throw AbsApiError.HttpStatus(0, "Not available")
        return c.libraryEpisodeDownloads(libraryId)
    }

    suspend fun scanServerLibrary(libraryId: String) {
        val c = client
        if (!session.isServerRoot.value || c == null || !session.isNetworkReachable.value) return
        c.scanServerLibrary(libraryId)
    }

    // MARK: - Passwort

    /** iOS: `changeAccountPassword` — `null` bei Erfolg, sonst Fehlermeldung. */
    suspend fun changeAccountPassword(current: String, new: String, confirm: String): String? {
        val c = client
        if (!session.mayUseServerNetwork || c == null) return "Password change is not available in offline mode."
        AdminLogic.validatePasswordChange(current, new, confirm, session.isServerRoot.value)?.let { return it }
        return try {
            c.changePassword(current, new)
            null
        } catch (e: CancellationException) {
            throw e
        } catch (e: AbsApiError.HttpStatus) {
            e.body?.trim()?.ifEmpty { null } ?: "Could not change password."
        } catch (e: Exception) {
            e.message ?: "Could not change password."
        }
    }

    // MARK: - M4B

    /** iOS: `startM4BEncode` — für Book Detail → More → Convert. */
    suspend fun startM4BEncode(book: AbsBook, bitrate: String = "64k", codec: String = "aac", channels: Int = 2) {
        val c = client
        if (!isAdminOrRoot || c == null) return
        if (!session.isNetworkReachable.value) {
            session.setErrorMessage("No network connection.")
            return
        }
        if (_m4bEncodeJobs.value.any { it.id == book.id && it.isActive }) {
            session.setErrorMessage("Conversion already in progress for this title.")
            return
        }
        try {
            c.encodeLibraryItemM4B(book.id, bitrate, codec, channels)
            val job = ServerM4BEncodeJob(
                id = book.id, title = book.displayTitle, author = book.displayAuthors,
                startedAt = System.currentTimeMillis(), status = ServerM4BEncodeJob.Status.running,
            )
            _m4bEncodeJobs.value = listOf(job) + _m4bEncodeJobs.value.filter { it.id != book.id }
            m4bEncodeProgressStore.setPercent(book.id, 0.0)
            persistM4BEncodeJobs()
            ensureM4BAdminSocket()
            ensureM4BEncodePolling()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    suspend fun cancelM4BEncode(libraryItemId: String) {
        val c = client
        if (!isAdminOrRoot || c == null) return
        try {
            c.cancelLibraryItemM4BEncode(libraryItemId)
            updateM4BEncodeJob(libraryItemId) { it.copy(status = ServerM4BEncodeJob.Status.cancelled, message = "Cancelled") }
            m4bEncodeProgressStore.clear(libraryItemId)
            stopM4BAdminSocketIfIdle()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session.publishErrorUnlessBenignCancellation(e)
        }
    }

    /** iOS: `purgeServerItemsMediaCache` — `true` bei Erfolg (Fehler landen im Root-Alert). */
    suspend fun purgeServerItemsMediaCache(): Boolean {
        val c = client
        if (!isAdminOrRoot || c == null) return false
        if (!session.isNetworkReachable.value) {
            session.setErrorMessage("No network connection.")
            return false
        }
        return try {
            c.purgeItemsMediaCache()
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (AbstandErrorFilter.isBenignCancellation(e)) return false
            session.publishErrorUnlessBenignCancellation(e)
            false
        }
    }

    fun clearFinishedM4BEncodeJobs() {
        _m4bEncodeJobs.value = _m4bEncodeJobs.value.filter { it.isActive }
        persistM4BEncodeJobs()
    }

    private fun m4bEncodeJobsStorageKey(): String =
        AdminLogic.m4bEncodeJobsStorageKey(AbsApiClient.normalizeServerURL(session.serverURL.value))

    /** iOS: `loadM4BEncodeJobs` — gespeicherte Jobs des Servers; aktive nehmen Socket + Polling wieder auf. */
    fun loadM4BEncodeJobs() {
        val key = m4bEncodeJobsStorageKey()
        loadedJobsKey = key
        val raw = Prefs.string(key)
        _m4bEncodeJobs.value = raw?.let {
            runCatching { AbsJson.decoder.decodeFromString(ListSerializer(ServerM4BEncodeJobSerializer), it) }.getOrNull()
        }.orEmpty()
        if (_m4bEncodeJobs.value.any { it.isActive }) {
            ensureM4BAdminSocket()
            ensureM4BEncodePolling()
        }
    }

    /** Einmalig beim ersten Zugriff (Settings/Book Detail): Jobs des aktiven Servers laden. */
    internal fun loadIfNeeded() {
        if (session.isLoggedIn.value && loadedJobsKey != m4bEncodeJobsStorageKey()) loadM4BEncodeJobs()
    }

    private fun persistM4BEncodeJobs() {
        val json = AbsJson.encoder.encodeToString(ListSerializer(ServerM4BEncodeJobSerializer), _m4bEncodeJobs.value)
        Prefs.setString(m4bEncodeJobsStorageKey(), json)
    }

    private fun updateM4BEncodeJob(id: String, mutate: (ServerM4BEncodeJob) -> ServerM4BEncodeJob) {
        val list = _m4bEncodeJobs.value
        val idx = list.indexOfFirst { it.id == id }
        if (idx < 0) return
        _m4bEncodeJobs.value = list.toMutableList().also { it[idx] = mutate(it[idx].copy()) }
        persistM4BEncodeJobs()
    }

    private fun ensureM4BAdminSocket() {
        if (!isAdminOrRoot) return
        val base = AbsApiClient.normalizeServerURL(session.serverURL.value) ?: return
        val tok = client?.currentToken()?.trim().orEmpty()
        if (tok.isEmpty()) return
        m4bAdminSocket.connect(base, tok)
    }

    private fun stopM4BAdminSocketIfIdle() {
        if (_m4bEncodeJobs.value.any { it.isActive }) return
        m4bAdminSocket.disconnect()
    }

    private fun handleM4BSocketEvent(event: AdminSocketEvent) {
        when (event) {
            is AdminSocketEvent.TaskProgress -> {
                if (_m4bEncodeJobs.value.none { it.id == event.libraryItemId && it.isActive }) return
                // Nur ProgressStore — Job-Liste bleibt ruhig (sonst flackern Detail/Menü).
                m4bEncodeProgressStore.setPercent(event.libraryItemId, event.percent)
            }
            is AdminSocketEvent.TaskFinished -> {
                if (!AdminLogic.isM4BTaskAction(event.action)) return
                if (_m4bEncodeJobs.value.none { it.id == event.libraryItemId && it.isActive }) return
                if (!event.failed) m4bEncodeProgressStore.setPercent(event.libraryItemId, 100.0)
                updateM4BEncodeJob(event.libraryItemId) {
                    it.copy(
                        status = if (event.failed) ServerM4BEncodeJob.Status.failed else ServerM4BEncodeJob.Status.finished,
                        message = if (event.failed) (it.message ?: "Failed") else "Done",
                    )
                }
                stopM4BAdminSocketIfIdle()
            }
            AdminSocketEvent.Connected, AdminSocketEvent.Disconnected -> Unit
        }
    }

    private fun ensureM4BEncodePolling() {
        if (m4bEncodePollJob?.isActive == true) return
        m4bEncodePollJob = model.scope.launch {
            while (isActive) {
                val active = _m4bEncodeJobs.value.filter { it.isActive }
                if (active.isEmpty()) {
                    stopM4BAdminSocketIfIdle()
                    break
                }
                active.forEach { refreshM4BEncodeJobStatus(it.id) }
                delay(POLL_INTERVAL_MS)
            }
            m4bEncodePollJob = null
        }
    }

    private suspend fun refreshM4BEncodeJobStatus(jobId: String) {
        val c = client ?: return
        try {
            val item = c.item(jobId, expanded = true)
            if (item.isSingleM4BAudiobook) {
                m4bEncodeProgressStore.setPercent(jobId, 100.0)
                updateM4BEncodeJob(jobId) { it.copy(status = ServerM4BEncodeJob.Status.finished, message = "Done") }
                stopM4BAdminSocketIfIdle()
                return
            }
            // Nach 6 Stunden ohne M4B: als fehlgeschlagen markieren.
            val started = _m4bEncodeJobs.value.firstOrNull { it.id == jobId }?.startedAt
            if (started != null && System.currentTimeMillis() - started > TIMEOUT_MS) {
                updateM4BEncodeJob(jobId) { it.copy(status = ServerM4BEncodeJob.Status.failed, message = "Timed out waiting for conversion") }
                m4bEncodeProgressStore.clear(jobId)
                stopM4BAdminSocketIfIdle()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Netzwerkfehler beim Poll — Job weiterlaufen lassen.
        }
    }

    companion object {
        private const val POLL_INTERVAL_MS = 4_000L
        private const val TIMEOUT_MS = 6 * 3600 * 1000L

        /** Process-weite Instanz; meldet sich beim ersten Zugriff als Session-Teilnehmer an. */
        val shared: AdminStore by lazy {
            AdminStore(AppModel.shared).also { AppModel.shared.register(it) }
        }

        /** Erster Zugriff aus der UI: Instanz anlegen und Jobs des aktiven Servers laden. */
        fun prepared(): AdminStore = shared.also { it.loadIfNeeded() }
    }
}

/** Reine Hilfslogik des Admin-Teils (testbar). */
object AdminLogic {
    /** iOS: `validateAccountPasswordChange` — `null` = gültig. */
    fun validatePasswordChange(current: String, new: String, confirm: String, isServerRoot: Boolean): String? {
        if (new != confirm) return "New password and confirmation do not match."
        if (new.isNotEmpty() && current == new) return "New password must be different from the current password."
        if (!isServerRoot && new.trim().isEmpty()) return "Please enter a new password."
        return null
    }

    /** iOS: `m4bEncodeJobsStorageKey()` — je Server getrennt. */
    fun m4bEncodeJobsStorageKey(normalizedServerURL: String?): String =
        if (normalizedServerURL.isNullOrEmpty()) "abstand_m4b_encode_jobs" else "abstand_m4b_encode_jobs.$normalizedServerURL"

    /** iOS: Filter in `handleM4BSocketEvent(.taskFinished)`. */
    fun isM4BTaskAction(action: String): Boolean = action == "encode-m4b" || action.isEmpty() || action.contains("m4b")
}
