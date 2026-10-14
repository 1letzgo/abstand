package de.letzgo.abstand.reader

import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.data.swiftTrim
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.store.EbookDownloadMeta
import de.letzgo.abstand.store.EbookLocalStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** iOS: `EbookReaderPresentation`. */
data class EbookReaderSession(
    val title: String,
    val author: String,
    val libraryItemId: String,
    val file: File,
    val format: AbsEbookFormat,
    /** Server-Lesefortschritt (0…1) als Startposition, wenn lokal kein Lesezeichen existiert. */
    val serverResumeProgression: Double? = null,
    /** Neu je Öffnen — der Reader lädt bei jedem Öffnen frisch (iOS: `id = UUID()`). */
    val openedAt: Long = System.nanoTime(),
)

/**
 * Einstieg in den eBook-Reader (iOS: `AppModel.openAttachedEbook` + `ebookReaderSession`, das
 * `MainRootView` als `fullScreenCover` zeigt). `ui/AppRoot.kt` beobachtet [session] und legt
 * `ReaderScreen` über die Tabs.
 *
 * Aufruf aus Buch-Detail / Now Playing: `EbookReaderLauncher.open(itemId)` (oder mit dem bereits
 * geladenen `AbsBook`). Lokaler Cache zuerst, sonst Download vom Server.
 */
object EbookReaderLauncher {
    private val _session = MutableStateFlow<EbookReaderSession?>(null)
    /** Offener Reader (iOS `ebookReaderSession`) — `null` = geschlossen. */
    val session: StateFlow<EbookReaderSession?> = _session.asStateFlow()

    private val _isPreparing = MutableStateFlow(false)
    /** iOS `isPreparingEbook` — Download/Auflösung läuft (für Spinner im Lese-Button). */
    val isPreparing: StateFlow<Boolean> = _isPreparing.asStateFlow()

    private var openJob: Job? = null

    private val model: AppModel get() = AppModel.shared

    /** eBook zum Hörbuch/eBook-Item öffnen; das Item wird aus Start-Regal, Downloads, LocalStore oder Server aufgelöst. */
    fun open(itemId: String) {
        val id = itemId.swiftTrim()
        if (id.isEmpty()) return
        launchOpen { resolveBook(id)?.let { openAttachedEbook(it) } ?: openWithoutBook(id) }
    }

    /** Wie [open], mit bereits geladenem Item (z. B. aus der Detailseite). */
    fun open(book: AbsBook) = launchOpen { openAttachedEbook(book) }

    /** Reader schließen (iOS: `ebookReaderSession = nil` → Regal aktualisieren, letzten Stand senden). */
    fun close() {
        if (_session.value == null) return
        _session.value = null
        EbookProgressSync.flush()
    }

    private fun launchOpen(block: suspend () -> Unit) {
        openJob?.cancel()
        openJob = model.scope.launch {
            _isPreparing.value = true
            model.session.setErrorMessage(null)
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                model.session.publishErrorUnlessBenignCancellation(e, forceDisplay = true)
            } finally {
                _isPreparing.value = false
            }
        }
    }

    private suspend fun resolveBook(id: String): AbsBook? {
        model.home.startBooks.value.firstOrNull { it.id == id && it.readableAttachedEbook != null }?.let { return it }
        model.downloadStatus.downloadedBooks().firstOrNull { it.id == id }?.let { return it }
        val store = model.session.currentLocalLibraryStore()
        if (store != null) {
            val local = runCatching { withContext(Dispatchers.IO) { store.fetchBookDetail(id) ?: store.fetchBook(id) } }.getOrNull()
            if (local != null) return local
        }
        return model.session.client?.takeIf { model.session.mayUseServerNetwork }
            ?.let { c -> runCatching { c.item(id, expanded = true) }.getOrNull() }
    }

    /** Ohne Katalogeintrag: nur ein bereits gecachtes eBook öffnen. */
    private suspend fun openWithoutBook(id: String) {
        val account = model.session.cacheAccountDir()
        val cached = withContext(Dispatchers.IO) { EbookLocalStore.cachedEbookIfPresent(account, id) }
        if (account == null || cached == null) {
            model.session.setErrorMessage("No eBook or PDF file is available for this audiobook.")
            return
        }
        val meta = withContext(Dispatchers.IO) { EbookLocalStore.loadDownloadMeta(account, id, cached.second) }
        present(meta?.title?.swiftTrim()?.ifEmpty { null } ?: "eBook", "", id, cached.first, cached.second)
    }

    /** iOS: `openAttachedEbook(for:)`. */
    private suspend fun openAttachedEbook(book: AbsBook) {
        val session = model.session
        if (session.mayUseServerNetwork && session.isNetworkReachable.value) session.refreshProgressFromServer()

        val account = session.cacheAccountDir()
        if (account != null) {
            val cached = withContext(Dispatchers.IO) { EbookLocalStore.cachedEbookIfPresent(account, book.id) }
            if (cached != null) {
                val meta = withContext(Dispatchers.IO) { EbookLocalStore.loadDownloadMeta(account, book.id, cached.second) }
                EbookLocalStore.rememberKnownFormat(cached.second, book.id)
                val title = meta?.title?.swiftTrim()?.ifEmpty { null } ?: book.displayTitle
                present(title, book.displayAuthors, book.id, cached.first, cached.second)
                return
            }
        }

        val c = session.client
        if (!session.mayUseServerNetwork || !session.isNetworkReachable.value || c == null || account == null) {
            session.setErrorMessage("No server connection. Open the eBook once while online to cache it on this device.")
            return
        }
        var resolved = book
        if (resolved.readableAttachedEbook == null) {
            runCatching { c.item(book.id, expanded = true) }.getOrNull()?.let { resolved = it }
        }
        val (ino, format) = resolved.readableAttachedEbook ?: run {
            session.setErrorMessage("No eBook or PDF file is available for this audiobook.")
            return
        }
        EbookLocalStore.rememberKnownFormat(format, resolved.id)
        EbookLocalStore.ensureAccountDirs(account)
        val file = EbookLocalStore.ebookFile(account, resolved.id, format)
        if (!EbookLocalStore.hasCachedEbook(account, resolved.id, format)) {
            c.downloadEbookFile(resolved.id, ino, format, File(file.parentFile, file.nameWithoutExtension))
            withContext(Dispatchers.IO) {
                EbookLocalStore.saveDownloadMeta(account, EbookDownloadMeta(resolved.id, ino, format, resolved.displayTitle))
            }
        }
        present(resolved.displayTitle, resolved.displayAuthors, resolved.id, file, format)
    }

    private fun present(title: String, author: String, id: String, file: File, format: AbsEbookFormat) {
        _session.value = EbookReaderSession(
            title = title,
            author = author,
            libraryItemId = id,
            file = file,
            format = format,
            serverResumeProgression = EbookProgressSync.resumeProgression(id),
        )
    }
}
