package de.letzgo.abstand.ui.detail

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsBookMedia
import de.letzgo.abstand.data.AbsBookMediaMetadata
import de.letzgo.abstand.data.AbsEbookFormat
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.logic.BookDetailLogic
import de.letzgo.abstand.logic.BooksEntityDetailNav
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.store.CoverImageCache
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandBlockingProgressDialog
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandMenuButton
import de.letzgo.abstand.ui.components.DetailScaffold
import de.letzgo.abstand.ui.components.LocalCoverEnvironment
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.library.LibraryPlayback
import de.letzgo.abstand.ui.library.coverRevisionFor
import kotlinx.coroutines.launch

/** Platzhalter, bis Stub/Detail da sind (iOS: `ABSBook(… offlineTitle: "…")`). */
private fun placeholderBook(id: String) = AbsBook(
    id = id, libraryId = null,
    media = AbsBookMedia(metadata = AbsBookMediaMetadata.offline("…", ""), duration = null, numTracks = null, tracks = null),
    addedAt = null, updatedAt = null,
)

/**
 * iOS: `BookDetailView` — gepushte Detailseite: Hero-Cover mit Cover-Tint-Hintergrund, Titel/Autoren
 * (Links), Aktionsleiste (Play/Pause + „fertig", Read + „gelesen"), Meta-Karten (Description,
 * Narrators, Series, Published, Genres, Tags), Kapitel, Lesezeichen, Hörverlauf.
 * Top-Bar (Android): Teilen, Download, Fortschritt zurücksetzen + Überlauf für Admin-Aktionen.
 *
 * @param onOpenEbook Reader öffnen; `null` blendet „Read" aus (Reader folgt später).
 * @param onEditMetadata/onMatchMetadata/onEditChapters Admin-Sheets; `null` = Eintrag ausgeblendet.
 * @param reloadSignal Erhöhen lädt das Detail neu (z. B. nach einem Admin-Sheet).
 */
@Composable
fun BookDetailScreen(
    itemId: String,
    onBack: (() -> Unit)? = null,
    onOpenEbook: ((AbsBook) -> Unit)? = null,
    onEditMetadata: ((AbsBook) -> Unit)? = null,
    onMatchMetadata: ((AbsBook) -> Unit)? = null,
    onEditChapters: ((AbsBook) -> Unit)? = null,
    reloadSignal: Int = 0,
    model: AppModel = AppModel.shared,
) {
    val context = LocalContext.current
    val navigator = LocalTabNavigator.current
    val back: () -> Unit = onBack ?: { navigator?.pop() }
    val catalog = model.catalog
    val session = model.session
    val scope = rememberCoroutineScope()
    val player = remember { PlaybackController.shared(context) }

    var detail by remember(itemId) { mutableStateOf<AbsBook?>(null) }
    var sessions by remember(itemId) { mutableStateOf<List<AbsListeningSession>>(emptyList()) }
    var chaptersExpanded by rememberSaveable(itemId) { mutableStateOf(false) }
    var bookmarksExpanded by rememberSaveable(itemId) { mutableStateOf(false) }
    var sessionsExpanded by rememberSaveable(itemId) { mutableStateOf(false) }
    var descriptionExpanded by rememberSaveable(itemId) { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<BookDetailConfirm?>(null) }
    var isDeleting by remember { mutableStateOf(false) }

    val progressMap by model.progress.progressByItemId.collectAsState()
    val reachable by session.isNetworkReachable.collectAsState()
    val isAdmin by session.isServerAdmin.collectAsState()
    val isRoot by session.isServerRoot.collectAsState()
    val activeBook by player.activeBook.collectAsState()
    val activeEpisode by player.activePlaybackEpisodeId.collectAsState()
    val isPlaying by player.isPlaying.collectAsState()
    catalog.downloadedItemIds.collectAsState().value

    LaunchedEffect(itemId, reloadSignal) {
        if (detail?.id != itemId) detail = catalog.immediateBookDetail(itemId)
        catalog.loadBookDetail(itemId)?.let { detail = it }
        sessions = catalog.loadBookListeningSessions(itemId, detail?.mediaId)
    }

    val book = detail ?: catalog.lookupBookStub(itemId) ?: placeholderBook(itemId)
    val prog = progressMap[itemId]
    val isPureEbook = book.isPureEbookLibraryItem
    val ebookFraction = model.progress.ebookDisplayProgressFraction(itemId)
    val isEbookReadFinished = (ebookFraction ?: 0.0) >= 0.995
    val isListenFinished = prog?.isFinished == true
    val cachedEbookFormat = catalog.cachedEbookFormat(itemId)
    val ebookFormat: AbsEbookFormat? = book.readableAttachedEbook?.second ?: book.attachedEbookFormats.firstOrNull() ?: cachedEbookFormat

    // Cover-Tint aus dem Hero-Cover (iOS: `resolvedCoverTint` + `detailSectionCardsTinted`).
    val env = LocalCoverEnvironment.current
    val revision = coverRevisionFor(book.updatedAt)
    val heroUrl = env.serverBaseURL?.let { AbsApiClient.itemCoverURL(it, itemId, CoverImageTier.hero) }
    val heroKey = CoverImageCache.cacheKey(CoverImageCache.scopeId(itemId, CoverImageTier.hero), revision)
    val tint = rememberDetailCoverTint(heroUrl, heroKey, persistItemId = itemId)

    fun openEntity(kind: BooksEntityDetailNav.Kind, entityId: String, title: String, numBooks: Int? = null) {
        val lib = book.libraryId?.trim()?.ifEmpty { null } ?: session.selectedBooksLibrary.value?.id
        navigator?.push(EntityDetailDestination(BooksEntityDetailNav(kind, entityId, title, numBooks, lib)))
    }

    DetailScaffold(
        onBack = back,
        coverTint = tint.background,
        actions = {
            BookDetailToolbar(
                book = book,
                isPureEbook = isPureEbook,
                canDiscard = (BookDetailLogic.canDiscardListeningProgress(prog, isPureEbook) || (isPureEbook && (ebookFraction ?: 0.0) > 0.005)) && reachable,
                showsAdminMenu = isAdmin || isRoot,
                isRoot = isRoot,
                reachable = reachable,
                enabled = !isDeleting,
                onShare = {
                    catalog.serverWebURL(book.id)?.let { url ->
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, url).putExtra(Intent.EXTRA_SUBJECT, book.displayTitle)
                        context.startActivity(Intent.createChooser(send, null))
                    }
                },
                onReset = { confirm = if (isPureEbook) BookDetailConfirm.ResetEbook else BookDetailConfirm.DiscardProgress },
                onEditMetadata = onEditMetadata?.let { cb -> { cb(book) } },
                onMatchMetadata = onMatchMetadata?.let { cb -> { cb(book) } },
                onEditChapters = onEditChapters?.let { cb -> { cb(book) } },
                onDelete = { confirm = BookDetailConfirm.Delete },
            )
        },
    ) { padding ->
        DetailSectionCardsTinted(tint.card) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding)
                    .padding(horizontal = AppTheme.Layout.tabPaddingH).padding(top = AppTheme.Layout.withinSectionSpacing),
            ) {
                DetailHeroCoverFrame {
                    SquareCoverImage(itemId = itemId, tier = CoverImageTier.hero, cacheRevision = revision, modifier = Modifier.fillMaxSize())
                }
                val authorLinks = BookDetailLogic.heroAuthorLinks(book)
                DetailHeroInfoSection(
                    title = book.displayTitle,
                    subtitle = book.displayAuthors,
                    authorLinks = authorLinks,
                    onAuthorTap = { id, name -> openEntity(BooksEntityDetailNav.Kind.AUTHOR, id, name) },
                    tertiaryLine = BookDetailLogic.tertiaryLine(BookDetailLogic.tertiaryParts(book, prog)),
                )
                val d = detail
                if (d != null) {
                    val actions = buildList {
                        if (d.isPlayableAudiobook) {
                            val isCurrent = activeBook?.id == d.id && activeEpisode.isNullOrBlank()
                            add(
                                DetailHeroMediaAction(
                                    id = "play",
                                    markIcon = if (isListenFinished) SF.arrowUturnBackward else SF.checkmark,
                                    markAccessibilityLabel = if (isListenFinished) "Mark as not finished" else "Mark as finished",
                                    markEnabled = true,
                                    onMark = { confirm = if (isListenFinished) BookDetailConfirm.MarkUnfinished else BookDetailConfirm.MarkFinished },
                                    kind = if (isCurrent && isPlaying) DetailHeroPrimaryKind.Pause else DetailHeroPrimaryKind.Play,
                                    progress01 = BookDetailLogic.playProgress01(prog, book.media.duration),
                                    isFinished = isListenFinished,
                                    primaryEnabled = true,
                                    onPrimary = {
                                        when {
                                            isCurrent && isPlaying -> player.pause()
                                            isCurrent && !isListenFinished -> player.play()
                                            else -> scope.launch { LibraryPlayback.play(context, d, resumeAtOverride = if (isListenFinished) 0.0 else null) }
                                        }
                                    },
                                ),
                            )
                        }
                        if (onOpenEbook != null && (d.hasReadableAttachedEbook || cachedEbookFormat != null)) {
                            add(
                                DetailHeroMediaAction(
                                    id = "read",
                                    markIcon = if (isEbookReadFinished) SF.arrowUturnBackward else SF.checkmark,
                                    markAccessibilityLabel = if (isEbookReadFinished) "Mark as not read" else "Mark as read",
                                    markEnabled = ebookFormat != null,
                                    onMark = { confirm = if (isEbookReadFinished) BookDetailConfirm.ResetEbook else BookDetailConfirm.MarkEbookRead },
                                    kind = DetailHeroPrimaryKind.Read,
                                    progress01 = if (isEbookReadFinished) 1.0 else (ebookFraction ?: 0.0),
                                    isFinished = isEbookReadFinished,
                                    primaryEnabled = reachable || cachedEbookFormat != null,
                                    onPrimary = { onOpenEbook(d) },
                                ),
                            )
                        }
                    }
                    DetailHeroActionsBar(
                        actions,
                        Modifier.padding(top = AppTheme.Layout.detailPlayButtonTopPadding, bottom = AppTheme.Layout.detailPlayButtonBottomPadding),
                    )
                    BookDetailMetaSections(
                        book = d,
                        progress = prog,
                        descriptionExpanded = descriptionExpanded,
                        onToggleDescription = { descriptionExpanded = !descriptionExpanded },
                        chaptersExpanded = chaptersExpanded,
                        onToggleChapters = { chaptersExpanded = !chaptersExpanded },
                        bookmarksExpanded = bookmarksExpanded,
                        onToggleBookmarks = { bookmarksExpanded = !bookmarksExpanded },
                        sessionsExpanded = sessionsExpanded,
                        onToggleSessions = { sessionsExpanded = !sessionsExpanded },
                        sessions = sessions,
                        reachable = reachable,
                        onOpenEntity = ::openEntity,
                        onPlayFrom = { at -> scope.launch { LibraryPlayback.play(context, d, resumeAtOverride = at) } },
                        onJumpToBookmark = { mark -> scope.launch { LibraryPlayback.jumpToBookmark(context, mark) } },
                        model = model,
                    )
                }
            }
        }
    }

    // MARK: Bestätigungen (iOS: `.alert`s)
    confirm?.let { c ->
        val d = detail ?: book
        AbstandDialog(
            title = c.title,
            onDismiss = { confirm = null },
            message = c.message(d.displayTitle),
            confirmLabel = c.confirmLabel,
            destructive = c.destructive,
            dismissOnConfirm = false,
            onConfirm = {
                confirm = null
                scope.launch {
                    when (c) {
                        BookDetailConfirm.DiscardProgress -> {
                            catalog.discardBookProgress(itemId)
                            // Sitzungen wurden serverseitig mitgelöscht — Liste nachziehen.
                            sessions = catalog.loadBookListeningSessions(itemId, d.mediaId)
                        }
                        BookDetailConfirm.MarkFinished -> catalog.markFinished(itemId)
                        BookDetailConfirm.MarkUnfinished -> catalog.markUnfinished(itemId)
                        BookDetailConfirm.MarkEbookRead -> ebookFormat?.let { catalog.markEbookAsFinished(itemId, it) }
                        BookDetailConfirm.ResetEbook -> ebookFormat?.let { catalog.resetEbookReadingProgress(itemId, it) }
                        BookDetailConfirm.Delete -> {
                            isDeleting = true
                            val ok = catalog.deleteFromServer(itemId, hardDelete = true)
                            isDeleting = false
                            if (ok) back()
                        }
                    }
                }
            },
        )
    }
    if (isDeleting) AbstandBlockingProgressDialog("Deleting book") // iOS: `deletingBookPopup`
}

/** iOS: die Bestätigungs-Alerts von `BookDetailView`. */
private enum class BookDetailConfirm(val title: String, val confirmLabel: String, val destructive: Boolean) {
    DiscardProgress("Reset listening progress?", "Reset", true),
    MarkFinished("Mark as finished?", "Mark as finished", false),
    MarkUnfinished("Mark as not finished?", "Mark as not finished", false),
    MarkEbookRead("Mark as read?", "Mark as read", false),
    ResetEbook("Mark as not read?", "Mark as not read", true),
    Delete("Delete book?", "Delete including file", true);

    fun message(title: String): String = when (this) {
        DiscardProgress -> "This removes your saved position and listening sessions for this book. You cannot undo this."
        MarkFinished -> "Your current position will be saved as complete."
        MarkUnfinished -> "You can resume from your saved position."
        MarkEbookRead -> "Your reading progress will be saved as complete."
        ResetEbook -> "This resets your saved eBook position. You cannot undo this."
        Delete -> "\"$title\" will be deleted on the server including its files. Local downloads will be removed. You cannot undo this."
    }
}

/** iOS: `bookDetailUtilityToolbarItems` — Teilen, Download, Reset; Admin-Aktionen im Überlauf. */
@Composable
private fun androidx.compose.foundation.layout.RowScope.BookDetailToolbar(
    book: AbsBook,
    isPureEbook: Boolean,
    canDiscard: Boolean,
    showsAdminMenu: Boolean,
    isRoot: Boolean,
    reachable: Boolean,
    enabled: Boolean,
    onShare: () -> Unit,
    onReset: () -> Unit,
    onEditMetadata: (() -> Unit)?,
    onMatchMetadata: (() -> Unit)?,
    onEditChapters: (() -> Unit)?,
    onDelete: () -> Unit,
    model: AppModel = AppModel.shared,
) {
    val catalog = model.catalog
    AbstandIconButton(SF.squareAndArrowUp, "Share", onClick = onShare, enabled = enabled, tint = Theme.palette.textPrimary)
    val storageId = catalog.downloadStorageIdForLibraryItem(book.id) ?: book.id
    if (!isPureEbook) {
        DetailToolbarDownloadItem(
            storageId = storageId,
            onStartDownload = { catalog.startDownload(book) },
            onRemoveDownload = { catalog.removeLocalDownload(storageId) },
            enabled = enabled,
        )
    }
    AbstandIconButton(
        SF.clockArrowCirclepath, "Reset listening progress", onClick = onReset, enabled = enabled && canDiscard,
        tint = if (canDiscard) AppTheme.danger else Theme.palette.textSecondary,
    )
    val adminItems = listOfNotNull(
        onEditMetadata?.let { Triple("Edit Metadata", SF.pencil, it) },
        onMatchMetadata?.let { Triple("Match Metadata", SF.magnifyingglass, it) },
        onEditChapters?.let { Triple("Edit Chapters", SF.listBulletBelowRectangle, it) },
    )
    if (showsAdminMenu && (adminItems.isNotEmpty() || isRoot)) {
        AbstandMenuButton(SF.ellipsisCircle, "More actions", enabled = enabled && reachable, tint = Theme.palette.textPrimary) {
            adminItems.forEach { (title, icon, action) -> item(title, action, icon = icon) }
            if (isRoot) {
                if (adminItems.isNotEmpty()) divider()
                item("Delete book", onDelete, icon = SF.trash, destructive = true)
            }
        }
    }
}

/** iOS: `detailBelowPlaySection` (ohne Aktionsleiste) — Meta-Karten, Kapitel, Lesezeichen, Verlauf. */
@Composable
private fun BookDetailMetaSections(
    book: AbsBook,
    progress: de.letzgo.abstand.data.AbsUserMediaProgress?,
    descriptionExpanded: Boolean,
    onToggleDescription: () -> Unit,
    chaptersExpanded: Boolean,
    onToggleChapters: () -> Unit,
    bookmarksExpanded: Boolean,
    onToggleBookmarks: () -> Unit,
    sessionsExpanded: Boolean,
    onToggleSessions: () -> Unit,
    sessions: List<AbsListeningSession>,
    reachable: Boolean,
    onOpenEntity: (BooksEntityDetailNav.Kind, String, String, Int?) -> Unit,
    onPlayFrom: (Double) -> Unit,
    onJumpToBookmark: (de.letzgo.abstand.data.AbsAudioBookmark) -> Unit,
    model: AppModel,
) {
    val m = book.media.metadata
    val narrators = m.narratorNamesForLibraryBrowseCoverMatch()
    val publishedLine = BookDetailLogic.publishedDisplayLine(BookDetailLogic.trimmedMetaValue(m.publisher), BookDetailLogic.trimmedMetaValue(m.publishedYear))
    val genres = BookDetailLogic.genres(m)
    val tags = BookDetailLogic.tags(book)
    val about = remember(m.description, m.descriptionPlain) { BookDetailLogic.aboutText(m) }
    val browse by model.catalog.browse.collectAsState()

    Column(
        Modifier.fillMaxWidth().padding(top = AppTheme.Layout.detailMetaAfterPlaySpacing),
        verticalArrangement = Arrangement.spacedBy(DetailMetaLayoutMetrics.sectionCardSpacing),
    ) {
        if (about != null) {
            DetailSectionCard { DetailMetaField("Description") { DetailMetaExpandableTextBlock(about, descriptionExpanded, onToggleDescription) } }
        }
        if (book.isPlayableAudiobook && narrators.isNotEmpty()) {
            DetailSectionCard {
                DetailMetaField(if (narrators.size == 1) "Narrator" else "Narrators") {
                    Column(verticalArrangement = Arrangement.spacedBy(DetailMetaLayoutMetrics.linkRowSpacing)) {
                        narrators.forEach { n -> DetailMetaLink(n) { onOpenEntity(BooksEntityDetailNav.Kind.NARRATOR, n, n, null) } }
                    }
                }
            }
        }
        if (BookDetailLogic.hasSeriesContent(m)) {
            DetailSectionCard {
                DetailMetaField("Series") {
                    val list = m.series.orEmpty()
                    if (list.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(DetailMetaLayoutMetrics.linkRowSpacing)) {
                            list.forEach { s -> DetailMetaLink(BookDetailLogic.seriesDisplayLine(s)) { onOpenEntity(BooksEntityDetailNav.Kind.SERIES, s.id, s.name, null) } }
                        }
                    } else {
                        m.resolvedSeriesDisplay?.trim()?.takeIf { it.isNotEmpty() }?.let { DetailMetaTextBlock(it) }
                    }
                }
            }
        }
        if (publishedLine != null) {
            DetailSectionCard { DetailMetaField("Published") { DetailMetaTextBlock(publishedLine) } }
        }
        if (genres.isNotEmpty()) {
            DetailSectionCard {
                DetailMetaField("Genres") {
                    Column(verticalArrangement = Arrangement.spacedBy(DetailMetaLayoutMetrics.linkRowSpacing)) {
                        genres.forEach { g ->
                            DetailMetaLink(g) {
                                val count = browse.genres.firstOrNull { it.name.equals(g, ignoreCase = true) }?.numBooks
                                onOpenEntity(BooksEntityDetailNav.Kind.GENRE, g, g, count)
                            }
                        }
                    }
                }
            }
        }
        if (tags.isNotEmpty()) {
            DetailSectionCard {
                DetailMetaField("Tags") {
                    Column(verticalArrangement = Arrangement.spacedBy(DetailMetaLayoutMetrics.linkRowSpacing)) {
                        tags.forEach { t ->
                            DetailMetaLink(t) {
                                val count = browse.tags.firstOrNull { it.name.equals(t, ignoreCase = true) }?.numBooks
                                onOpenEntity(BooksEntityDetailNav.Kind.TAG, t, t, count)
                            }
                        }
                    }
                }
            }
        }
        if (book.isPlayableAudiobook) {
            if (book.media.chapters.orEmpty().isNotEmpty()) {
                DetailMetaDisclosure("Chapters", chaptersExpanded, onToggleChapters) {
                    BookChapterList(book, progress) { ch -> onPlayFrom(ch.start) }
                }
            }
            DetailMetaDisclosure("Bookmarks", bookmarksExpanded, onToggleBookmarks) {
                AudiobookBookmarkList(book.id, onJumpToBookmark, model)
            }
            DetailMetaDisclosure("Listening history", sessionsExpanded, onToggleSessions) {
                ListeningHistorySessionList(
                    sessions, reachable,
                    emptyOnlineText = "No listening sessions recorded for this book yet.",
                    emptyOfflineText = "No listening history cached yet.",
                    onJump = { s -> onPlayFrom(s.startTime) },
                )
            }
        }
    }
}
