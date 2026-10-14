package de.letzgo.abstand.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.components.AbstandLabeledTextField
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.MetadataSheetScaffold
import de.letzgo.abstand.ui.formatPlaybackTime
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

private val ThinDivider @Composable get() = Theme.palette.textSecondary.copy(alpha = 0.15f)

// MARK: - Kapitel

/** iOS: `BookChapterRowView` — Titel, Zeitspanne, Status-Symbol, Play. */
@Composable
fun BookChapterRow(chapter: AbsChapter, playState: BookChapterPlayState, onPlay: () -> Unit) {
    val palette = Theme.palette
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onPlay).padding(vertical = AppTheme.Layout.withinSectionSpacing),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing)) {
            Text(chapter.title, style = IosType.headline, color = palette.textPrimary)
            Text("${formatPlaybackTime(chapter.start)} – ${formatPlaybackTime(chapter.end)}", style = IosType.caption, color = palette.textSecondary)
        }
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
            if (idx < chapters.lastIndex) HorizontalDivider(color = ThinDivider)
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
            style = IosType.body, color = palette.textSecondary, modifier = Modifier.fillMaxWidth(),
        )
    } else {
        Column(Modifier.fillMaxWidth()) {
            marks.forEachIndexed { idx, mark ->
                Row(
                    Modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.rowVerticalPadding),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
                ) {
                    Column(
                        Modifier.weight(1f).clickable { onJump(mark) },
                        verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.tightSpacing),
                    ) {
                        Text(mark.title.trim().ifEmpty { "—" }, style = IosType.subheadline.semibold, color = palette.textPrimary)
                        Text(formatPlaybackTime(mark.time.toDouble()), style = IosType.caption, color = palette.textSecondary)
                    }
                    if (reachable) {
                        IconButton(onClick = { confirmDelete = mark }) { Icon(SF.trash, "Delete bookmark", tint = AppTheme.danger) }
                    }
                }
                if (idx < marks.lastIndex) HorizontalDivider(color = ThinDivider)
            }
        }
    }

    confirmDelete?.let { b ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text("Delete bookmark?") },
            text = { Text("“${b.title}” at ${formatPlaybackTime(b.time.toDouble())}") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = null
                    scope.launch { model.catalog.deleteBookmark(b) }
                }) { Text("Delete", color = AppTheme.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = null }) { Text("Cancel") } },
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
        Text("Position: ${formatPlaybackTime(timeSeconds.toDouble())}", style = IosType.footnote, color = Theme.palette.textSecondary)
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
                Text(started, style = IosType.subheadline.semibold, color = palette.textPrimary)
                Text(
                    "Listened ${formatPlaybackTime(session.timeListening.toDouble())} · ${formatPlaybackTime(session.startTime)} → ${formatPlaybackTime(session.currentTime)}",
                    style = IosType.caption, color = palette.textSecondary,
                )
            }
            IconButton(onClick = { onJump(session) }) {
                Icon(SF.arrowCounterclockwiseCircleFill, "Jump to this session", tint = Theme.accent, modifier = Modifier.size(28.dp))
            }
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(7.dp).background(palette.card, CircleShape)) {
            val x0 = (maxWidth * rel0.toFloat()).coerceIn(0.dp, maxWidth)
            val x1 = (maxWidth * rel1.toFloat()).coerceIn(x0 + 2.dp, maxWidth)
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
            style = IosType.caption, color = Theme.palette.textSecondary,
            modifier = Modifier.fillMaxWidth().padding(vertical = AppTheme.Layout.compactSpacing),
        )
    } else {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.cardPadding)) {
            sessions.forEach { ListeningHistoryRow(it, onJump) }
        }
    }
}
