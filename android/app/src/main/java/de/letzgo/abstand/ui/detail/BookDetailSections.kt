package de.letzgo.abstand.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsAudioBookmark
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsChapter
import de.letzgo.abstand.data.AbsListeningSession
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.logic.BookChapterPlayState
import de.letzgo.abstand.logic.BookDetailLogic
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.player.PlaybackController
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.AppType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandDialog
import de.letzgo.abstand.ui.components.AbstandLabeledTextField
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.MetadataSheetScaffold
import de.letzgo.abstand.ui.formatPlaybackTime
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import de.letzgo.abstand.ui.components.AbstandIconButton
import de.letzgo.abstand.ui.components.AbstandDivider
import de.letzgo.abstand.ui.components.AbstandListRow


// MARK: - Kapitel

/** iOS: `BookChapterRowView` — Titel, Zeitspanne, Status-Symbol, Play. */
@Composable
fun BookChapterRow(chapter: AbsChapter, playState: BookChapterPlayState, onPlay: () -> Unit) {
    val palette = Theme.palette
    AbstandListRow(
        title = chapter.title,
        subtitle = "${formatPlaybackTime(chapter.start)} – ${formatPlaybackTime(chapter.end)}",
        onClick = onPlay,
        titleStyle = AppType.titleMedium,
        titleMaxLines = Int.MAX_VALUE,
        verticalPadding = AppTheme.Layout.withinSectionSpacing,
    ) {
        when (playState) {
            BookChapterPlayState.Completed -> Icon(SF.checkmarkCircleFill, "Completed", tint = Theme.accent)
            BookChapterPlayState.InProgress -> Icon(SF.playCircleFill, "In progress", tint = Theme.accent)
            BookChapterPlayState.NotStarted -> Icon(SF.circle, null, tint = palette.textSecondary.copy(alpha = 0.35f))
        }
    }
}

/** iOS: `BookChapterListView` / `bookChaptersSection` — nach Start sortiert, Trenner dazwischen. */
@Composable
fun BookChapterList(book: AbsBook, progress: AbsUserMediaProgress?, onPlayChapter: (AbsChapter) -> Unit) {
    val chapters = book.media.chapters.orEmpty().sortedBy { it.start }
    if (chapters.isEmpty()) {
        AbstandSectionEmptyState("No chapters available.")
        return
    }
    Column(Modifier.fillMaxWidth()) {
        chapters.forEachIndexed { idx, ch ->
            BookChapterRow(ch, BookChapterPlayState.resolve(ch, progress)) { onPlayChapter(ch) }
            if (idx < chapters.lastIndex) AbstandDivider(opacity = 0.15f)
        }
    }
}

// MARK: - Lesezeichen

/**
 * iOS: `AudiobookBookmarkListView` — Lesezeichen des Hörbuchs; Tippen springt, Papierkorb fragt nach
 * (nur online). Leer: Hinweis „Set one while playing" bzw. „offline nicht verfügbar".
 */
@Composable
fun AudiobookBookmarkList(libraryItemId: String, onJump: (AbsAudioBookmark) -> Unit, model: AppModel = AppModel.shared) {
    val all by model.progress.bookmarks.collectAsState()
    val reachable by model.session.isNetworkReachable.collectAsState()
    val marks = remember(all, libraryItemId) { all.filter { it.libraryItemId == libraryItemId }.sortedBy { it.time } }
    var confirmDelete by remember { mutableStateOf<AbsAudioBookmark?>(null) }
    val scope = rememberCoroutineScope()
    val palette = Theme.palette

    if (marks.isEmpty()) {
        Text(
            if (reachable) "No bookmarks for this audiobook yet. Set one while playing." else "Bookmarks are unavailable offline.",
            style = AppType.bodyLarge, color = palette.textSecondary, modifier = Modifier.fillMaxWidth(),
        )
    } else {
        Column(Modifier.fillMaxWidth()) {
            marks.forEachIndexed { idx, mark ->
                AbstandListRow(
                    title = mark.title.trim().ifEmpty { "—" },
                    subtitle = formatPlaybackTime(mark.time.toDouble()),
                    onClick = { onJump(mark) },
                    titleStyle = AppType.titleSmall,
                    verticalPadding = AppTheme.Layout.rowVerticalPadding,
                ) {
                    if (reachable) {
                        AbstandIconButton(SF.trash, "Delete bookmark", onClick = { confirmDelete = mark }, tint = AppTheme.danger)
                    }
                }
                if (idx < marks.lastIndex) AbstandDivider(opacity = 0.15f)
            }
        }
    }

    confirmDelete?.let { b ->
        AbstandDialog(
            title = "Delete bookmark?",
            onDismiss = { confirmDelete = null },
            message = "“${b.title}” at ${formatPlaybackTime(b.time.toDouble())}",
            confirmLabel = "Delete",
            destructive = true,
            dismissOnConfirm = false,
            onConfirm = {
                confirmDelete = null
                scope.launch { model.catalog.deleteBookmark(b) }
            },
        )
    }
}

/**
 * iOS: `AddBookmarkTitleSheet` — Titel eingeben (vorbelegt mit der Position, solange unverändert),
 * Position läuft sekündlich mit; Speichern legt das Lesezeichen an der aktuellen Player-Position an.
 */
@Composable
fun AddBookmarkTitleSheet(libraryItemId: String, onDismiss: () -> Unit, model: AppModel = AppModel.shared) {
    val context = LocalContext.current
    val player = remember { PlaybackController.shared(context) }
    var timeSeconds by remember { mutableIntStateOf(player.globalPosition.value.toInt()) }
    var title by remember { mutableStateOf(BookDetailLogic.defaultBookmarkTitle(timeSeconds)) }
    var lastDefault by remember { mutableStateOf(title) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            val at = player.globalPosition.value.toInt()
            timeSeconds = at
            val fresh = BookDetailLogic.defaultBookmarkTitle(at)
            if (title.isEmpty() || title == lastDefault) title = fresh
            lastDefault = fresh
        }
    }
    MetadataSheetScaffold(
        title = "Bookmark",
        onCancel = { if (!saving) onDismiss() },
        onConfirm = {
            if (!saving) {
                saving = true
                scope.launch {
                    val ok = model.catalog.createBookmark(libraryItemId, player.globalPosition.value.toInt(), title)
                    saving = false
                    if (ok) onDismiss()
                }
            }
        },
        isBusy = saving,
    ) {
        AbstandLabeledTextField(title = "Title", value = title, onValueChange = { title = it })
        Text("Position: ${formatPlaybackTime(timeSeconds.toDouble())}", style = AppType.bodySmall, color = Theme.palette.textSecondary)
    }
}

// MARK: - Hörverlauf

/** iOS: `ListeningHistoryRow` — Datum, Hördauer + Bereich, Sprung-Button, Bereichsbalken. */
@Composable
fun ListeningHistoryRow(session: AbsListeningSession, onJump: (AbsListeningSession) -> Unit) {
    val palette = Theme.palette
    val (rel0, rel1) = BookDetailLogic.sessionRange(session.duration, session.startTime, session.currentTime)
    val started = remember(session.startedAt) {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(session.startedAt))
    }
    Column(Modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.tightSpacing), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.stackSpacing)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.hairlineSpacing)) {
                Text(started, style = AppType.titleSmall, color = palette.textPrimary)
                Text(
                    "Listened ${formatPlaybackTime(session.timeListening.toDouble())} · ${formatPlaybackTime(session.startTime)} → ${formatPlaybackTime(session.currentTime)}",
                    style = AppType.bodySmall, color = palette.textSecondary,
                )
            }
            AbstandIconButton(
                SF.arrowCounterclockwiseCircleFill,
                "Jump to this session",
                onClick = { onJump(session) },
                iconSize = HistoryJumpIconSize,
                tint = Theme.accent,
            )
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(HistoryRangeBarHeight).background(palette.card, CircleShape)) {
            val x0 = (maxWidth * rel0.toFloat()).coerceIn(0.dp, maxWidth)
            val x1 = (maxWidth * rel1.toFloat()).coerceIn(x0 + AppTheme.Layout.hairlineSpacing, maxWidth)
            Box(Modifier.offset(x = x0).width(x1 - x0).fillMaxHeight().background(Theme.accent.copy(alpha = 0.88f), CircleShape))
        }
    }
}

/** iOS: `ListeningHistorySessionList`. */
@Composable
fun ListeningHistorySessionList(
    sessions: List<AbsListeningSession>,
    isNetworkReachable: Boolean,
    emptyOnlineText: String,
    emptyOfflineText: String,
    onJump: (AbsListeningSession) -> Unit,
) {
    if (sessions.isEmpty()) {
        Text(
            if (isNetworkReachable) emptyOnlineText else emptyOfflineText,
            style = AppType.bodySmall, color = Theme.palette.textSecondary,
            modifier = Modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.compactSpacing),
        )
    } else {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.cardPadding)) {
            sessions.forEach { ListeningHistoryRow(it, onJump) }
        }
    }
}

/** iOS: `ListeningHistoryRow` — Sprung-Symbol und Höhe des Bereichsbalkens. */
private val HistoryJumpIconSize = 28.dp
private val HistoryRangeBarHeight = 8.dp
